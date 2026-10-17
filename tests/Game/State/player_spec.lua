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
            assert.are.equal(7, I.Log.unattributed) -- no hostile on us: Attackers made no row, the belief still sees them
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

        it("drops a wound whose amount is not plain, with a note, and allocates nothing", function()
            fire("player", "WOUND", "", nil, 1) -- the event facade passes a secret slot as nil
            assert.are.same({}, seen)
            assert.equal("secret", S.status["UNIT_COMBAT player amount"])
            assert.are.equal(
                0,
                alloc.bytes(function()
                    ctl.Fire("UNIT_COMBAT", "player", "WOUND", "BLOCK", 12, 1)
                    ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", nil, 1) -- the drop and its note
                    S.Flush()
                end, 2000)
            )
        end)

        it("drops a wound whose amount is a secret value, with a note", function()
            fire("player", "WOUND", "", fake.SECRET, 1)
            fire("player", "WOUND", fake.SECRET, 12, 1) -- a secret flag: a plain wound, not BLOCKED
            assert.are.same({ { 1, 12, 20 } }, seen)
            assert.equal("secret", S.status["UNIT_COMBAT player amount"])
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
