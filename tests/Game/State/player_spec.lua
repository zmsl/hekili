-- tests/Game/State/player_spec.lua: VS.Start on a client that lacks a CR_* constant, and a start hook that raises
-- (CHECKPOINT 2: Forever defines no CR_CRIT_TAKEN_SPELL, and the raise aborted every later start hook); the hits on
-- the player as `PlayerHit` observations (tank design §1.2.1) and the block value in the stat cache.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

describe("player start", function()
    local VS, I, S, api

    before_each(function()
        api = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S = I.Sources
        I.Build(fs.def(fs.new(9)), 1)
    end)

    it("Start survives a missing CR_* constant", function()
        api.CR_CRIT_TAKEN_SPELL = nil
        api.GetCombatRating = function(cr)
            assert(cr ~= nil, "Usage: GetCombatRating(ratingIndex)")
            return cr * 10
        end
        assert.has_no.errors(function()
            VS.Start(api)
        end)
        assert.equal("partial", S.status["stats CR_* constants"])
        assert.equal(180, (VS.Stat("GetCombatRating", api.CR_HASTE_MELEE)))
        assert.equal("readable", S.status.UnitSpellHaste)
        assert.equal("readable", S.status.UnitAttackSpeed) -- Swing.lua's start hook, registered after Player's
    end)

    it("keeps the start reads across the first build (PLAYER_LOGIN before PLAYER_ENTERING_WORLD)", function()
        local ctl = api.ctl
        ctl.speed[1], ctl.spellHaste = 2.6, 7
        VS.Start(api)
        I.Build(fs.def(fs.new(9)), 100) -- SpecChanged clears the log, the stage and the records
        S.Flush()
        I.Fold(100, false)
        local sp = VS.SwingSpeed(1, 100)
        assert.are.same({ 2.6, "observed" }, { sp.est, sp.basis })
        local h = VS.SpellHaste(100)
        assert.are.same({ 7, "observed" }, { h.est, h.basis })
    end)

    it("re-reads the stats out of combat when the weapon damage, attack power or level changes", function()
        local ctl = api.ctl
        local damage = { 40, 60, 15, 25, 0, 0, 1 }
        api.UnitDamage = function()
            return damage[1], damage[2], damage[3], damage[4], damage[5], damage[6], damage[7]
        end
        VS.Start(api)
        assert.are.same({ 40, 60, 15, 25, 0, 0, 1 }, { VS.Stat("UnitDamage") })
        damage[1], damage[2] = 44, 66 -- spender_a before a pull
        ctl.Fire("UNIT_ATTACK_POWER", "player")
        assert.are.same({ 44, 66, 15, 25, 0, 0, 1 }, { VS.Stat("UnitDamage") })
        damage[1] = 50
        ctl.Fire("UNIT_DAMAGE", "target") -- another unit: no read
        assert.are.equal(44, (VS.Stat("UnitDamage")))
        ctl.Fire("UNIT_DAMAGE", "player")
        assert.are.equal(50, (VS.Stat("UnitDamage")))
        damage[1] = 52
        ctl.Fire("PLAYER_LEVEL_UP", 23)
        assert.are.equal(52, (VS.Stat("UnitDamage")))
        ctl.Fire("PLAYER_REGEN_DISABLED")
        damage[1] = 70 -- a weapon swap in combat: secret then, so stale until combat ends
        ctl.Fire("UNIT_DAMAGE", "player")
        assert.are.equal(52, (VS.Stat("UnitDamage")))
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(70, (VS.Stat("UnitDamage")))
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(
            0,
            alloc.bytes(function()
                ctl.Fire("UNIT_DAMAGE", "player")
            end, 2000)
        )
    end)

    -- L967 (1): a buff, food or talent out of combat changes a stat, the spell power or a rating with no UNIT_DAMAGE or
    -- UNIT_ATTACK_POWER; the cache follows each event (all three on Forever: wow-ui-source's forever branch), so a pre-pull
    -- `now` (the belief's cache) and the simulation (the client's plain read) price one amount.
    it("re-reads the stats out of combat on UNIT_STATS, SPELL_POWER_CHANGED and COMBAT_RATING_UPDATE", function()
        local ctl = api.ctl
        local spirit, power, rating = 100, 300, 20
        api.UnitStat = function(_, i)
            return i * 10, i == 5 and spirit or i, 0, 0
        end
        api.GetSpellBonusDamage = function()
            return power
        end
        api.GetCombatRating = function()
            return rating
        end
        VS.Start(api)
        assert.are.equal(100, (select(2, VS.Stat("UnitStat", 5))))
        spirit = 140 -- a Spirit buff before the pull
        ctl.Fire("UNIT_STATS", "target") -- another unit: no read
        assert.are.equal(100, (select(2, VS.Stat("UnitStat", 5))))
        ctl.Fire("UNIT_STATS", "player")
        assert.are.equal(140, (select(2, VS.Stat("UnitStat", 5))))
        power = 350
        ctl.Fire("SPELL_POWER_CHANGED")
        assert.are.equal(350, (VS.Stat("GetSpellBonusDamage", 7)))
        rating = 25
        ctl.Fire("COMBAT_RATING_UPDATE")
        assert.are.equal(25, (VS.Stat("GetCombatRating", api.CR_HASTE_MELEE)))
        ctl.Fire("PLAYER_REGEN_DISABLED")
        spirit = 200 -- secret in combat: the cache keeps the last plain read
        ctl.Fire("UNIT_STATS", "player")
        assert.are.equal(140, (select(2, VS.Stat("UnitStat", 5))))
    end)

    it("reads the gear facts a pack's function names, at the start and at each change", function()
        local ctx, ctl = I.nowCtx, nil
        api, ctl = fake.new()
        ctl.inventory[16], ctl.inventory[17] = 1, nil
        ctl.items[1] = { "Two-Hander", "INVTYPE_2HWEAPON" }
        VS.Start(api)
        assert.are.same({ 2, false }, { ctx.weapon.size, ctx.equipped.shield })
        ctl.items[2], ctl.items[3] = { "Sword", "INVTYPE_WEAPON" }, { "Shield", "INVTYPE_SHIELD" }
        ctl.inventory[16], ctl.inventory[17] = 2, 3
        ctl.Fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
        assert.are.same({ 1, true }, { ctx.weapon.size, ctx.equipped.shield })
        ctl.inventory[16], ctl.inventory[17] = nil, nil
        ctl.Fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
        assert.are.same({ 0, false }, { ctx.weapon.size, ctx.equipped.shield })
    end)

    it("a raising gear read costs the gear facts only, never a build", function()
        local ctx = I.nowCtx
        api = fake.new()
        VS.Start(api)
        api.GetInventoryItemID = function()
            error("no such API")
        end
        assert.has_no.errors(function()
            I.Build(fs.def(fs.new(9)), 1)
        end)
        assert.are.same({ 0, false }, { ctx.weapon.size, ctx.equipped.shield })
    end)

    it("notes complete when every CR_* constant resolves", function()
        VS.Start(api)
        assert.equal("complete", S.status["stats CR_* constants"])
    end)

    it("Start isolates a start hook that raises", function()
        local seen
        api.geterrorhandler = function()
            return function(err)
                seen = err
            end
        end
        local after = false
        S.OnStart(function()
            error("boom")
        end)
        S.OnStart(function()
            after = true
        end)
        assert.has_no.errors(function()
            VS.Start(api)
        end)
        assert.equal("error", S.status.start)
        assert.truthy(seen and seen:find("boom"))
        assert.is_true(after)
    end)

    describe("hits on the player (UNIT_COMBAT, tank design §1.2.1)", function()
        local seen, ctl

        local function fire(...)
            ctl.Fire("UNIT_COMBAT", ...)
            S.Flush()
            I.Fold(ctl.now, false)
        end

        before_each(function()
            ctl = api.ctl
            seen = {}
            I.On(VS.Obs.PlayerHit, function(o)
                seen[#seen + 1] = { o.a, o.b, o.c }
            end)
            VS.Start(api)
        end)

        it("stages the seven kinds, a wound flagged BLOCK or BLOCK_REDUCED as BLOCKED, attributed or not", function()
            fire("player", "WOUND", "", 12, 1)
            fire("player", "WOUND", "BLOCK_REDUCED", 7, 1)
            fire("player", "WOUND", "BLOCK", 5, 1)
            fire("player", "BLOCK", "", 0, 1)
            fire("player", "DODGE", "", 0, 1)
            fire("player", "PARRY", "", 0, 1)
            fire("player", "MISS", "", 0, 1)
            fire("player", "HEAL", "", 30, 1)
            fire("player", "ABSORB", "", 9, 1) -- not a kind
            fire("target", "WOUND", "", 40, 1) -- the target's: Sources/Target.lua's
            assert.are.same({
                { 1, 12, 20 },
                { 2, 7, 20 },
                { 2, 5, 20 },
                { 3, 0, 20 },
                { 4, 0, 20 },
                { 5, 0, 20 },
                { 6, 0, 20 },
                { 7, 30, 20 },
            }, seen)
            assert.are.equal(7, I.Log.unattributed) -- no hostile on us: Attackers credits nobody, the belief still sees them
        end)

        it("takes the attacker's level from the target only while the target's target is the player", function()
            ctl.level.target = 23
            fire("player", "WOUND", "", 12, 1) -- the target attacks someone else
            ctl.unitIs.targettarget = "player"
            fire("player", "WOUND", "", 12, 1)
            ctl.level.target = nil -- secret: the player's level
            fire("player", "WOUND", "", 12, 1)
            ctl.level.target, ctl.level.player = -1, nil -- "??" and a secret player level: 0
            fire("player", "WOUND", "", 12, 1)
            assert.are.same({ 20, 23, 20, 0 }, { seen[1][3], seen[2][3], seen[3][3], seen[4][3] })
        end)

        it(
            "stages a wound whose amount is not plain as unknown (b = -1), with a note, and allocates nothing",
            function()
                fire("player", "WOUND", "", nil, 1) -- the event facade passes a secret slot as nil
                assert.are.same({ { 1, -1, 20 } }, seen)
                assert.equal("secret", S.status["UNIT_COMBAT player amount"])
                assert.are.equal(
                    0,
                    alloc.bytes(function()
                        ctl.Fire("UNIT_COMBAT", "player", "WOUND", "BLOCK", 12, 1)
                        ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", nil, 1) -- the drop and its note
                        S.Flush()
                    end, 2000)
                )
            end
        )

        it("stages a wound whose amount is a secret value as unknown (CN13, L152), with a note", function()
            fire("player", "WOUND", "", fake.SECRET, 1)
            fire("player", "WOUND", fake.SECRET, 12, 1) -- a secret flag: a plain wound, not BLOCKED
            fire("player", "WOUND", "BLOCK_REDUCED", fake.SECRET, 1)
            fire("player", "MISS", "", fake.SECRET, 1)
            assert.are.same({ { 1, -1, 20 }, { 1, 12, 20 }, { 2, -1, 20 }, { 6, 0, 20 } }, seen)
            assert.equal("secret", S.status["UNIT_COMBAT player amount"])
        end)

        it("a secret amount is -1 whatever its flag (rage per hit is not learned, owner L1723)", function()
            fire("player", "WOUND", "CRITICAL", fake.SECRET, 1)
            fire("player", "WOUND", "CRUSHING", fake.SECRET, 1)
            assert.are.same({ { 1, -1, 20 }, { 1, -1, 20 } }, seen)
        end)

        it("caches the shield's block value out of combat only", function()
            local block = 31
            api.GetShieldBlock = function()
                return block
            end
            ctl.Fire("PLAYER_EQUIPMENT_CHANGED")
            assert.are.equal(31, (VS.Stat("GetShieldBlock")))
            ctl.Fire("PLAYER_REGEN_DISABLED")
            block = 40
            ctl.Fire("PLAYER_EQUIPMENT_CHANGED")
            assert.are.equal(31, (VS.Stat("GetShieldBlock")))
            ctl.Fire("PLAYER_REGEN_ENABLED")
            assert.are.equal(40, (VS.Stat("GetShieldBlock")))
        end)
    end)
end)

-- Lane B3 (LibHiddenValues integration design 2.3, 2.5): the library's band on our health (Sources/Bands.lua, channel 0,
-- fractions 0-1) sets the player's health record, its middle the estimate, observed; a plain read of the same drain is
-- exact and wins; an unknown band is a secret read's "unknown" (full, conf 0). The fake library (harness fake_lhv.lua)
-- answers the band 11 frames after the watch, the build's.
describe("the player's health from the band (lane B3)", function()
    local fake_lhv = require("Game.harness.fake_lhv")
    local F = 1 / 60
    local VS, I, S, api, ctl, lhv, Obs

    local function drain(t)
        ctl.Tick(t)
        S.RunPolls(t)
        I.Fold(t, false)
        I.Settle(t)
    end

    local function frames(n)
        for _ = 1, n do
            drain(ctl.now + F)
        end
    end

    local function push(hp) -- our true health out of 1000, now
        lhv:Push("health", "player", nil, hp, 1000, ctl.now)
    end

    local function read()
        local h = VS.Health("player", ctl.now)
        return { h.lo, h.hi, h.est, h.basis, h.last.observed.event }
    end

    before_each(function()
        api = fake.new()
        ctl = api.ctl
        ctl.now = 100
        lhv = fake_lhv.new({
            now = function()
                return ctl.now
            end,
        })
        ctl.LibStub = function(name)
            return name == "LibHiddenValues-1.0" and lhv or nil
        end
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        local def = fs.def(fs.new(9))
        def.providers = { bands = true }
        VS.Start(api)
        I.Build(def, ctl.now)
        ctl.health, ctl.healthMax = 1000, 1000
    end)

    it("in combat a live band sets lo, hi and the middle, observed; a heal raises it", function()
        push(1000)
        frames(1)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.combat = true
        push(340)
        frames(12)
        assert.is_true(I.bandLive[0])
        assert.are.same({ 0.34, 0.35, 0.345, "observed", Obs.Band }, read())
        assert.is_true(VS.Health("player", ctl.now).conf > 0.99)
        push(705) -- a heal
        frames(3)
        assert.are.same({ 0.7, 0.71, 0.705, "observed", Obs.Band }, read())
        -- what it applied, for the harness's containment check (lane B2's hook, channel 0)
        assert.is_true(I.bandUsed[0] > 0)
        assert.are.same({ 0.7, 0.71 }, { I.bandUsedLo[0], I.bandUsedHi[0] })
    end)

    it("out of combat the plain read of the same drain is exact and wins", function()
        ctl.health = 300
        push(340)
        frames(12)
        assert.is_true(I.bandLive[0]) -- logged, not applied
        assert.are.same({ 0.3, 0.3, 0.3, "observed", Obs.Read }, read())
        assert.are.equal(0, I.bandUsed[0])
    end)

    it("at the pull: the band folds after CombatStart and the secret read, so the drain never reads full", function()
        push(340)
        ctl.health = 340
        frames(12)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.combat = true
        frames(1)
        assert.are.same({ 0.34, 0.35, 0.345, "observed", Obs.Band }, read())
    end)

    it("an empty band 0 0 (minor 9) reads exactly 0, observed", function()
        S.Direct(Obs.Band, 101, 0, 0, 0)
        I.Fold(101, false)
        assert.are.same({ 0, 0, 0, "observed", Obs.Band }, read())
    end)

    it("an unknown band restores 'unknown' (full, conf 0); in the drain of a plain read it leaves the read", function()
        S.Direct(Obs.Band, 101, 0, 0.5, 0.51)
        I.Fold(101, false)
        assert.are.same({ 0.5, 0.51, 0.505, "observed", Obs.Band }, read())
        S.Direct(Obs.Band, 102, 0, 1, 0)
        I.Fold(102, false)
        local h = VS.Health("player", 102)
        assert.are.same({ 0, 1, 1, "default", 0 }, { h.lo, h.hi, h.est, h.basis, h.conf })
        S.Direct(Obs.Read, 103, 0, 0.3, I.ReadOf.Health)
        S.Direct(Obs.Band, 103, 0, 1, 0)
        I.Fold(103, false)
        h = VS.Health("player", 103)
        assert.are.same({ 0.3, 0.3, "observed" }, { h.lo, h.est, h.basis })
        S.Direct(Obs.Band, 103, 0, 0.5, 0.51) -- a band in the same drain: the read still wins
        I.Fold(103, false)
        assert.are.equal(0.3, VS.Health("player", 103).est)
    end)

    -- (review M4) the unknown branch through the source: the drain's secret read already reads "unknown", so the pin is
    -- the band's own: the loss's drain ends on Obs.Band's "unknown"
    it("in combat the band lost: full, conf 0, the drain's last word the band's unknown", function()
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.combat = true
        push(340)
        frames(12)
        assert.are.same({ 0.34, 0.35, 0.345, "observed", Obs.Band }, read())
        lhv:SetAvailable("unavailable", "error")
        frames(1)
        local h = VS.Health("player", ctl.now)
        assert.are.same({ 0, 1, 1, "default", 0 }, { h.lo, h.hi, h.est, h.basis, h.conf })
        assert.are.equal(Obs.Band, h.last.default.event)
    end)

    it("another channel's band leaves the player's health alone", function()
        S.Direct(Obs.Band, 101, -1, 0.2, 0.21)
        S.Direct(Obs.Band, 101, 1, 40, 41)
        I.Fold(101, false)
        local h = VS.Health("player", 101)
        assert.are.same({ 1, "default" }, { h.est, h.basis })
    end)

    it("folds a band, an unknown and a plain-read drain allocating nothing", function()
        local t = 200
        assert.are.equal(
            0,
            alloc.bytes(function(i)
                t = t + 0.01
                if i % 3 == 0 then
                    S.Direct(Obs.Band, t, 0, 1, 0)
                elseif i % 3 == 1 then
                    S.Direct(Obs.Read, t, 0, 0.3, I.ReadOf.Health)
                end
                S.Direct(Obs.Band, t, 0, 0.5, 0.51)
                I.Fold(t, false)
                VS.Health("player", t)
            end, 3000)
        )
    end)
end)
