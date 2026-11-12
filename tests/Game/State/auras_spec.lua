-- tests/Game/State/auras_spec.lua: the auras family and source (spec §4.5, §6.3).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("auras", function()
    local VS, I, S, Obs, ctl, api
    local SHOUT, REND = 1, 2 -- aura indices in fs.def

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    local function fold(t)
        ctl.Tick(t)
        I.Fold(t, false)
        I.Settle(t)
    end

    it("reads a plain walk: expiry, stacks, an invented stable instance ID, AuraGen", function()
        ctl.now = 10
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SPENDER_A, expirationTime = 130, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        fold(10)
        local rec, stacks, applied, inst = VS.Aura("player", fs.SPENDER_A, 10)
        assert.are.same({ 130, 1, 10, "observed" }, { rec.est, stacks, applied, rec.basis })
        assert.is_true(inst > 0)
        local gen = VS.AuraGen("player")
        ctl.Fire("UNIT_AURA", "player")
        fold(11)
        assert.are.equal(gen, VS.AuraGen("player")) -- nothing changed
        assert.are.equal(inst, select(4, VS.Aura("player", fs.SPENDER_A, 11)))
        local id, r2 = VS.AuraByInstance("player", inst, 11)
        assert.are.same({ fs.SPENDER_A, 130 }, { id, r2.est })
    end)

    -- Reads of SPENDER_A at t expiring at `expires`, folded; its believed applied time.
    local function readA(t, expires)
        ctl.now = t
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SPENDER_A, expirationTime = expires, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        fold(t)
        return select(3, VS.Aura("player", fs.SPENDER_A, t))
    end

    it("a refreshed aura without an icd keeps its applied time (its tick phase)", function()
        assert.are.equal(10, readA(10, 25))
        assert.are.equal(10, readA(20, 35)) -- refreshed: a later expiry, the same phase
    end)

    it("an icd aura: a later expiry is a re-application, a jitter is not, a first-walk sighting is unknown", function()
        local def = fs.def(fs.new(9))
        def.auras[SHOUT].icd = 10
        I.Build(def, 1) -- the first clean walk is still to come
        assert.are.equal(0, readA(10, 25)) -- up at the first clean walk: gain unknown, applied one ICD back
        ctl.auras.player.HELPFUL[1] = nil
        ctl.Fire("UNIT_AURA", "player")
        fold(11) -- seen down
        assert.is_nil(VS.Aura("player", fs.SPENDER_A, 11))
        assert.are.equal(12, readA(12, 27)) -- a gain the walks saw
        assert.are.equal(20, readA(20, 35)) -- refreshed (a re-proc)
        assert.are.equal(20, readA(21, 35.2)) -- within I.AURA_REFRESH: the same application
    end)

    it("finds a tracked aura past the 40th slot of one filter", function()
        ctl.now = 10
        for i = 1, 40 do
            ctl.auras.player.HELPFUL[i] = { spellId = 999999, expirationTime = 130, applications = 0 } -- untracked
        end
        ctl.auras.player.HELPFUL[41] = { spellId = fs.SPENDER_A, expirationTime = 130, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        fold(10)
        assert.is_not_nil(VS.Aura("player", fs.SPENDER_A, 10))
        assert.are.equal(130, VS.Aura("player", fs.SPENDER_A, 10).est)
    end)

    it("in combat, counts a missing aura down only after it was seen readable in combat", function()
        ctl.now = 10
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SPENDER_A, expirationTime = 130, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        fold(10)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.auras.player.HELPFUL[1] = nil
        ctl.Fire("UNIT_AURA", "player")
        fold(12)
        assert.is_truthy(VS.Aura("player", fs.SPENDER_A, 12)) -- a miss may be the client hiding it
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SPENDER_A, expirationTime = 130, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        ctl.auras.player.HELPFUL[1] = nil
        ctl.Fire("UNIT_AURA", "player")
        fold(13)
        assert.is_nil(VS.Aura("player", fs.SPENDER_A, 13))
    end)

    it("stops at a walk that raises or answers a secret, and logs nothing for it", function()
        ctl.now = 10
        I.AuraModel(2, REND, 10, 25, 1, 10, Obs.CastSuccess, true)
        ctl.auraError.target = true
        ctl.Fire("UNIT_AURA", "target")
        assert.are.equal("error", S.status["aura walk target"])
        ctl.auraError.target = nil
        ctl.auras.target.HARMFUL[1] = fake.SECRET
        ctl.Fire("UNIT_AURA", "target")
        assert.are.equal(0, I.log.n)
        assert.are.equal("secret", S.status["aura walk target"])
        fold(10)
        assert.are.equal(25, VS.Aura("target", fs.SPENDER_C, 10).est) -- an incomplete walk logs nothing down
    end)

    it("notes the walk per unit: a raising target walk leaves the player's readable", function()
        ctl.now = 10
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SPENDER_A, expirationTime = 130, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        ctl.auraError.target = true
        ctl.Fire("UNIT_AURA", "target")
        assert.are.equal("readable", S.status["aura walk player"])
        assert.are.equal("error", S.status["aura walk target"])
    end)

    it("names a third unit's walk status, and notes a clean walk readable with no tracked aura up", function()
        local api2, ctl2 = fake.new()
        local ns2 = load.module()
        local def = fs.def(fs.new(9))
        def.units[3] = "focus"
        ctl2.auras.focus = { HELPFUL = {}, HARMFUL = {} }
        ctl2.exists.focus = true
        ns2.VirtualStateInternal.Build(def, 1)
        ns2.VirtualState.Start(api2)
        ctl2.Fire("UNIT_AURA", "player") -- nothing on the player
        ctl2.Fire("UNIT_AURA", "focus")
        local status = ns2.VirtualStateInternal.Sources.status
        assert.are.same({ "readable", "readable" }, { status["aura walk player"], status["aura walk focus"] })
    end)

    it("stops at an entry whose spellId is secret, so a modelled debuff is not logged down", function()
        ctl.now = 10
        I.AuraModel(2, REND, 10, 25, 1, 10, Obs.CastSuccess, true)
        ctl.auras.target.HARMFUL[1] = { spellId = fake.SECRET, expirationTime = 130, applications = 0 }
        ctl.Fire("UNIT_AURA", "target")
        fold(10)
        assert.are.equal("secret", S.status["aura walk target"])
        assert.are.equal(25, VS.Aura("target", fs.SPENDER_C, 10).est)
    end)

    it("orders AuraAt by applied time, filters by helpful/harmful and by est > now", function()
        I.AuraModel(2, REND, 5, 20, 1, 5, Obs.CastSuccess, true)
        I.AuraModel(1, SHOUT, 6, 126, 1, 6, Obs.CastSuccess, false)
        assert.are.equal(fs.SPENDER_C, (VS.AuraAt("target", "HARMFUL", 1, 7)))
        assert.is_nil(VS.AuraAt("target", "HELPFUL", 1, 7))
        assert.are.equal(fs.SPENDER_A, (VS.AuraAt("player", "HELPFUL", 1, 7)))
        assert.is_nil(VS.AuraAt("target", "HARMFUL", 1, 21))
        fold(21)
        assert.is_nil(VS.Aura("target", fs.SPENDER_C, 21)) -- expired by time
    end)

    it(
        "gives a target already held at a /reload its memory slot (Start, then the first build), so its death is seen",
        function()
            local api2, ctl2 = fake.new()
            ctl2.now = 1
            local ns2 = load.module()
            local VS2, I2 = ns2.VirtualState, ns2.VirtualStateInternal
            VS2.Start(api2) -- PLAYER_LOGIN: a target is held (ctl2.guid.target), nothing built yet
            I2.Build(fs.def(fs.new(9)), 1) -- the first SpecChanged (PLAYER_ENTERING_WORLD); no PLAYER_TARGET_CHANGED comes
            ctl2.Tick(1)
            I2.Fold(1, false)
            assert.is_true(I2.curSlot > 0)
            I2.AuraModel(2, REND, 1, 20, 1, 1, Obs.CastSuccess, true)
            ctl2.dead.target = true
            I2.Sources.RunPolls(2)
            I2.Fold(2, false)
            assert.is_nil(VS2.Aura("target", fs.SPENDER_C, 2))
        end
    )

    it("forgets the target's auras when the target is cleared or dies", function()
        ctl.now = 10
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(10)
        I.AuraModel(2, REND, 10, 25, 1, 10, Obs.CastSuccess, true)
        ctl.guid.target = nil
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(11)
        assert.is_nil(VS.Aura("target", fs.SPENDER_C, 11))
        ctl.guid.target = "Creature-1"
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(12)
        assert.are.equal(25, VS.Aura("target", fs.SPENDER_C, 12).est) -- still remembered
        ctl.dead.target = true
        ctl.Tick(13)
        I.Sources.RunPolls(13)
        I.Fold(13, false)
        assert.is_nil(VS.Aura("target", fs.SPENDER_C, 13))
    end)

    it("remembers what it believed about a target across a swap back", function()
        ctl.now = 10
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(10)
        I.AuraModel(2, REND, 10, 25, 1, 10, Obs.CastSuccess, true)
        ctl.guid.target = "Creature-2"
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(11)
        assert.is_nil(VS.Aura("target", fs.SPENDER_C, 11))
        assert.are.equal(1, VS.Count.WithAura(fs.SPENDER_C, 11)) -- remembered on the other target
        ctl.guid.target = "Creature-1"
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(12)
        assert.are.equal(25, VS.Aura("target", fs.SPENDER_C, 12).est)
    end)

    it("walks the player and target again once combat ends, so an aura hidden in combat reads up", function()
        local get, calls = api.C_UnitAuras.GetAuraDataByIndex, 0
        api.C_UnitAuras.GetAuraDataByIndex = function(...)
            calls = calls + 1
            return get(...)
        end
        ctl.now = 10
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SPENDER_A, expirationTime = 130, applications = 0 }
        ctl.auraError.player = true
        ctl.Fire("UNIT_AURA", "player")
        fold(10)
        assert.is_nil(VS.Aura("player", fs.SPENDER_A, 10)) -- the in-combat walk raised: believed down
        calls = 0
        S.RunPolls(11) -- in combat: no pending walk
        assert.are.equal(0, calls)
        ctl.auraError.player = nil
        ctl.Fire("PLAYER_REGEN_ENABLED")
        S.RunPolls(12)
        I.Fold(12, false)
        assert.are.equal(130, VS.Aura("player", fs.SPENDER_A, 12).est)
        assert.is_true(calls > 0)
        calls = 0
        S.RunPolls(13) -- the walk completed: nothing pending
        assert.are.equal(0, calls)
    end)

    it("retries the after-combat walk until the player walk completes", function()
        ctl.now = 10
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SPENDER_A, expirationTime = 130, applications = 0 }
        ctl.auraError.player = true
        ctl.Fire("PLAYER_REGEN_ENABLED")
        S.RunPolls(11)
        I.Fold(11, false)
        assert.is_nil(VS.Aura("player", fs.SPENDER_A, 11))
        ctl.auraError.player = nil
        S.RunPolls(12)
        I.Fold(12, false)
        assert.are.equal(130, VS.Aura("player", fs.SPENDER_A, 12).est)
    end)

    it("walks nothing when combat starts again before the poll, and walks an existing target after combat", function()
        local get, calls = api.C_UnitAuras.GetAuraDataByIndex, 0
        api.C_UnitAuras.GetAuraDataByIndex = function(...)
            calls = calls + 1
            return get(...)
        end
        ctl.now = 10
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.Fire("PLAYER_REGEN_ENABLED")
        ctl.Fire("PLAYER_REGEN_DISABLED")
        calls = 0
        S.RunPolls(11) -- pending, but in combat
        assert.are.equal(0, calls)
        ctl.auras.target.HARMFUL[1] = { spellId = fs.SPENDER_C, expirationTime = 30, applications = 0 }
        ctl.Fire("PLAYER_REGEN_ENABLED")
        S.RunPolls(12)
        I.Fold(12, false)
        assert.are.equal(30, VS.Aura("target", fs.SPENDER_C, 12).est)
    end)

    describe("the combat-exit walk counts its corrections (exitFix, decision 105)", function()
        local function exitWalk(t)
            ctl.Fire("PLAYER_REGEN_ENABLED")
            S.RunPolls(t)
            I.Fold(t, false)
        end
        local function up(spell, expires)
            ctl.auras.player.HELPFUL[1] = { spellId = spell, expirationTime = expires, applications = 0 }
        end

        before_each(function()
            ctl.now = 10
            ctl.Fire("PLAYER_REGEN_DISABLED")
        end)

        it("modelled up, the walk says down: corrected and counted once", function()
            I.AuraModel(1, SHOUT, 10, 40, 1, 10, Obs.CastSuccess, false)
            exitWalk(12)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 12))
            assert.are.equal(1, I.auraExitFix[SHOUT])
            S.RunPolls(13) -- nothing pending: no second count
            assert.are.equal(1, I.auraExitFix[SHOUT])
        end)

        it("modelled down (the in-combat walk raised), the walk says up: corrected and counted once", function()
            up(fs.SPENDER_A, 130)
            ctl.auraError.player = true
            ctl.Fire("UNIT_AURA", "player")
            fold(10)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 10))
            ctl.auraError.player = nil
            exitWalk(12)
            assert.are.equal(130, VS.Aura("player", fs.SPENDER_A, 12).est)
            assert.are.equal(1, I.auraExitFix[SHOUT])
        end)

        it("the walk agrees, up or down: nothing counted", function()
            I.AuraModel(1, SHOUT, 10, 130, 1, 10, Obs.CastSuccess, false)
            up(fs.SPENDER_A, 130)
            exitWalk(12)
            for j = 1, I.auras.nAura do
                assert.are.same({ j, 0, 0 }, { j, I.auraExitFix[j], I.auraExitFix[I.AURA_UNIT + j] })
            end
        end)

        it("a refresh edge (up with a later expiry) and a record already lapsed by time count nothing", function()
            I.AuraModel(1, SHOUT, 10, 40, 1, 10, Obs.CastSuccess, false)
            I.AuraModel(2, REND, 10, 11, 1, 10, Obs.CastSuccess, true) -- lapsed by 12, not yet folded down
            up(fs.SPENDER_A, 130)
            exitWalk(12)
            assert.are.equal(130, VS.Aura("player", fs.SPENDER_A, 12).est)
            assert.are.same({ 0, 0 }, { I.auraExitFix[SHOUT], I.auraExitFix[I.AURA_UNIT + REND] })
        end)

        it("counts the target's exit walk under its own key", function()
            I.AuraModel(2, REND, 10, 40, 1, 10, Obs.CastSuccess, true)
            exitWalk(12)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 12))
            assert.are.same({ 1, 0 }, { I.auraExitFix[I.AURA_UNIT + REND], I.auraExitFix[REND] })
        end)

        -- The real exit frame: the events, then the drain's polls (poll 10 walks again), then the fold.
        local function frame(t)
            ctl.Tick(t)
            S.RunPolls(t)
            I.Fold(t, false)
        end

        it("a UNIT_AURA walk in the exit frame, then poll 10's walk before the fold: down counted once", function()
            I.AuraModel(1, SHOUT, 10, 40, 1, 10, Obs.CastSuccess, false)
            ctl.Fire("PLAYER_REGEN_ENABLED")
            ctl.Fire("UNIT_AURA", "player")
            frame(12)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 12))
            assert.are.equal(1, I.auraExitFix[SHOUT])
        end)

        it("a UNIT_AURA walk in the exit frame, then poll 10's walk before the fold: up counted once", function()
            up(fs.SPENDER_A, 130)
            ctl.auraError.player = true
            ctl.Fire("UNIT_AURA", "player")
            fold(10)
            ctl.auraError.player = nil
            ctl.Fire("PLAYER_REGEN_ENABLED")
            ctl.Fire("UNIT_AURA", "player")
            frame(12)
            assert.are.equal(130, VS.Aura("player", fs.SPENDER_A, 12).est)
            assert.are.equal(1, I.auraExitFix[SHOUT])
        end)

        it("two UNIT_AURA walks in the exit frame count each correction once", function()
            I.AuraModel(1, SHOUT, 10, 40, 1, 10, Obs.CastSuccess, false)
            I.AuraModel(2, REND, 10, 40, 1, 10, Obs.CastSuccess, true)
            ctl.Fire("PLAYER_REGEN_ENABLED")
            ctl.Fire("UNIT_AURA", "player")
            ctl.Fire("UNIT_AURA", "target")
            ctl.Fire("UNIT_AURA", "player")
            ctl.Fire("UNIT_AURA", "target")
            frame(12)
            assert.are.same({ 1, 1 }, { I.auraExitFix[SHOUT], I.auraExitFix[I.AURA_UNIT + REND] })
        end)

        it("a failed exit walk then its retry counts once", function()
            up(fs.SPENDER_A, 130)
            ctl.auraError.player = true
            exitWalk(11)
            assert.are.equal(0, I.auraExitFix[SHOUT])
            ctl.auraError.player = nil
            exitWalk(12) -- the retry (pending still set)
            S.RunPolls(13)
            assert.are.equal(1, I.auraExitFix[SHOUT])
        end)

        it("a walk after a build, out of combat, counts nothing", function()
            exitWalk(11)
            up(fs.SPENDER_A, 130)
            I.Build(fs.def(fs.new(9)), 1) -- every record cleared; the next poll 10 walks
            S.RunPolls(12)
            I.Fold(12, false)
            assert.are.equal(130, VS.Aura("player", fs.SPENDER_A, 12).est)
            assert.are.equal(0, I.auraExitFix[SHOUT])
        end)

        it("resets at PLAYER_REGEN_DISABLED; a pull before the walk counts nothing", function()
            I.AuraModel(1, SHOUT, 10, 40, 1, 10, Obs.CastSuccess, false)
            exitWalk(12)
            assert.are.equal(1, I.auraExitFix[SHOUT])
            ctl.Fire("PLAYER_REGEN_DISABLED")
            assert.are.equal(0, I.auraExitFix[SHOUT])
            I.AuraModel(1, SHOUT, 13, 40, 1, 13, Obs.CastSuccess, false)
            ctl.Fire("PLAYER_REGEN_ENABLED")
            ctl.Fire("PLAYER_REGEN_DISABLED") -- pulled again before poll 10
            ctl.Fire("UNIT_AURA", "player") -- an in-combat walk misses it: no exit walk
            S.RunPolls(14)
            assert.are.equal(0, I.auraExitFix[SHOUT])
        end)

        it("allocates nothing over 1000 fights' exit walks, up and down", function()
            local alloc = require("Game.State.helpers.alloc")
            local t, n, total = 10, 0, 0
            local aura = { spellId = fs.SPENDER_A, expirationTime = 1e9, applications = 0 }
            assert.are.equal(
                0,
                alloc.bytes(function()
                    t = t + 0.01
                    n = n + 1
                    if n % 2 == 1 then -- modelled up, the walk says down
                        ctl.auras.player.HELPFUL[1] = nil
                        I.AuraModel(1, SHOUT, t, t + 30, 1, t, Obs.CastSuccess, false)
                    else -- believed down since the last fight, the walk says up
                        ctl.auras.player.HELPFUL[1] = aura
                    end
                    ctl.Fire("PLAYER_REGEN_ENABLED")
                    S.RunPolls(t)
                    I.Fold(t, false)
                    total = total + I.auraExitFix[SHOUT]
                    ctl.Fire("PLAYER_REGEN_DISABLED")
                end, 1000)
            )
            assert.is_true(total >= 1000) -- every fight's exit corrected SHOUT (both sides measured)
        end)
    end)

    describe("a proc seen through its spell's overlay (`overlay`, C2)", function()
        local OVERLAY = 5001 -- a generic spell whose overlay the proc lights
        local lit

        before_each(function()
            local def = fs.def(fs.new(9))
            def.auras[SHOUT] = { key = "spender_a", id = fs.SPENDER_A, overlay = OVERLAY }
            I.Build(def, 1)
            I.ObsLog.Clear(I.log)
            lit = {}
            api.C_SpellActivationOverlay.IsSpellOverlayed = function(id)
                return lit[id]
            end
        end)

        local function poll(t)
            ctl.Tick(t)
            S.RunPolls(t)
            I.Fold(t, false)
            I.Settle(t)
        end

        local function secretWalk()
            ctl.auras.player.HELPFUL[1] = fake.SECRET
            ctl.Fire("UNIT_AURA", "player")
        end

        it("in combat with the walk secret, reads the proc up while its overlay is on, down once it is off", function()
            ctl.now = 10
            ctl.Fire("PLAYER_REGEN_DISABLED")
            secretWalk()
            lit[OVERLAY] = true
            poll(10)
            local rec = VS.Aura("player", fs.SPENDER_A, 10)
            assert.are.same({ math.huge, "observed" }, { rec.est, rec.basis }) -- a Read with no expiry
            poll(11)
            assert.is_truthy(VS.Aura("player", fs.SPENDER_A, 11))
            lit[OVERLAY] = false
            poll(12)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 12))
        end)

        it("leaves the belief alone on a secret overlay answer", function()
            ctl.now = 10
            ctl.Fire("PLAYER_REGEN_DISABLED")
            secretWalk()
            I.AuraModel(1, SHOUT, 10, 20, 1, 10, Obs.CastSuccess, false)
            lit[OVERLAY] = fake.SECRET
            poll(11)
            assert.are.equal(20, VS.Aura("player", fs.SPENDER_A, 11).est)
        end)

        it("lets a plain walk win: the overlay is not read while the player walk completes", function()
            ctl.now = 10
            ctl.auras.player.HELPFUL[1] = { spellId = fs.SPENDER_A, expirationTime = 30, applications = 0 }
            ctl.Fire("UNIT_AURA", "player")
            lit[OVERLAY] = false
            poll(10)
            assert.are.equal(30, VS.Aura("player", fs.SPENDER_A, 10).est)
            ctl.auras.player.HELPFUL[1] = nil
            ctl.Fire("UNIT_AURA", "player")
            lit[OVERLAY] = true
            poll(11)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 11))
        end)

        it("takes an overlay-read proc down once its overlay is off, even after the walk turns plain", function()
            ctl.now = 10
            ctl.Fire("PLAYER_REGEN_DISABLED")
            secretWalk()
            lit[OVERLAY] = true
            poll(10)
            ctl.auras.player.HELPFUL[1] = nil
            ctl.Fire("UNIT_AURA", "player") -- plain and complete, but in combat a miss is not a down
            lit[OVERLAY] = false
            poll(11)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 11))
        end)

        it("allocates nothing over 1000 polls", function()
            local alloc = require("Game.State.helpers.alloc")
            ctl.now = 10
            ctl.Fire("PLAYER_REGEN_DISABLED")
            secretWalk()
            local t = 10
            assert.are.equal(
                0,
                alloc.bytes(function()
                    t = t + 0.01
                    lit[OVERLAY] = not lit[OVERLAY]
                    S.RunPolls(t)
                    I.Fold(t, false)
                end, 1000)
            )
        end)
    end)

    describe("an aura spent by hits on the player (`consumedBy`, tank design §3)", function()
        local BLOCKED, BLOCK, DODGE -- I.HitKind's, read once I is loaded (a tag-filtered run skips the earlier cases)

        local function hit(t, kind)
            S.Direct(Obs.PlayerHit, t, kind, 0, 20)
            I.Fold(t, false)
        end

        before_each(function()
            BLOCKED, BLOCK, DODGE = I.HitKind.BLOCKED, I.HitKind.BLOCK, I.HitKind.DODGE
            local def = fs.def(fs.new(9))
            def.auras[SHOUT] =
                { key = "spender_a", id = fs.SPENDER_A, max_stack = 2, consumedBy = { BLOCK = true, BLOCKED = true } }
            I.Build(def, 1)
            I.ObsLog.Clear(I.log)
            I.AuraModel(1, SHOUT, 10, 17, 2, 10, 0) -- up from 10 to 17 with 2 stacks (its `now`)
        end)

        it("takes one stack per hit of a listed kind and removes the aura at 0", function()
            hit(11, BLOCK)
            local rec, stacks = VS.Aura("player", fs.SPENDER_A, 11)
            assert.are.same({ 17, 1, "modelled" }, { rec.est, stacks, rec.basis })
            hit(12, BLOCKED)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 12))
            hit(13, BLOCK) -- down: nothing to spend
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 13))
        end)

        it("ignores the other kinds, an expired aura, and an aura without `consumedBy`", function()
            hit(11, DODGE)
            assert.are.equal(2, select(2, VS.Aura("player", fs.SPENDER_A, 11)))
            I.AuraModel(1, REND, 10, 30, 1, 10, 0) -- no `consumedBy`
            hit(12, BLOCK)
            assert.are.equal(1, select(2, VS.Aura("player", fs.SPENDER_C, 12)))
            hit(18, BLOCK) -- past the shout's expiry: its last stack is not spent
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 18))
            assert.are.equal(1, I.auras.stacks[1][SHOUT])
        end)

        it("with `consumeIcd` spends one stack per window: hits inside it spend none (aura audit C2)", function()
            local def = fs.def(fs.new(9))
            def.auras[SHOUT] = {
                key = "spender_a",
                id = fs.SPENDER_A,
                max_stack = 3,
                consumedBy = { BLOCK = true },
                consumeIcd = 3.5,
            }
            I.Build(def, 1)
            I.ObsLog.Clear(I.log)
            I.AuraModel(1, SHOUT, 10, 40, 3, 10, 0)
            hit(11, BLOCK)
            assert.are.equal(2, select(2, VS.Aura("player", fs.SPENDER_A, 11)))
            hit(12, BLOCK) -- inside the window
            hit(14.4, BLOCK)
            assert.are.equal(2, select(2, VS.Aura("player", fs.SPENDER_A, 14.4)))
            hit(14.5, BLOCK) -- the window's end: the next spends
            assert.are.equal(1, select(2, VS.Aura("player", fs.SPENDER_A, 14.5)))
            I.AuraModel(1, SHOUT, 15, 45, 3, 15, 0) -- a recast refills it; the window runs on (wowsims's timer)
            hit(16, BLOCK)
            assert.are.equal(3, select(2, VS.Aura("player", fs.SPENDER_A, 16)))
            hit(18, BLOCK)
            assert.are.equal(2, select(2, VS.Aura("player", fs.SPENDER_A, 18)))
        end)

        it("allocates nothing over 1000 hits", function()
            local alloc = require("Game.State.helpers.alloc")
            local t = 11
            assert.are.equal(
                0,
                alloc.bytes(function()
                    t = t + 0.01
                    I.AuraModel(1, SHOUT, t, t + 7, 2, t, 0)
                    hit(t, BLOCK)
                end, 1000)
            )
        end)
    end)

    describe("presence from the router and the viewer leaf (providers decision 80, 90)", function()
        local item

        before_each(function()
            ctl.viewer.sets[2] = { 501 }
            ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
            ctl.viewer.sets[0] = { 600 }
            ctl.viewer.infos[600] = { spellID = fs.SPENDER_A } -- a cooldown entry (Essential) for the same aura
            item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 501)
            item.unit = "player"
            -- shortcut: stands in for Task 1's provider resolution in I.Build; Task 1 replaces it with `d.providers` alone
            local P = I.PRESENCE.router
            P.Activate(api, 1, fs.def(fs.new(9)), { viewer = true })
            I.presence = P
            I.OnPresence(P)
            ctl.now = 10
            ctl.Fire("PLAYER_REGEN_DISABLED")
            ctl.auras.player.HELPFUL[1] = fake.SECRET -- the walk is secret: presence may stage
            ctl.Fire("UNIT_AURA", "player")
            I.ObsLog.Clear(I.log)
        end)

        local function poll(t)
            ctl.Tick(t)
            S.RunPolls(t)
            I.Fold(t, false)
            I.Settle(t)
        end

        it("a viewer UP for an aura believed down stages one Read up and counts one disagreement", function()
            ctl.ViewerAura(item, "player")
            poll(10) -- the sweep at poll 15 reads the item: an edge
            local rec = VS.Aura("player", fs.SPENDER_A, 10)
            assert.are.same({ 130, "observed" }, { rec.est, rec.basis }) -- from the light: its registered 120 s (C2)
            assert.are.same({ 1, 1 }, { I.presenceFacts[SHOUT], I.presenceDisagree[SHOUT] })
            poll(11) -- the poll agrees with the belief now: no fact
            assert.are.same({ 1, 1 }, { I.presenceFacts[SHOUT], I.presenceDisagree[SHOUT] })
        end)

        it("an UP for an aura already believed up counts a fact, no disagreement", function()
            I.AuraModel(1, SHOUT, 10, 20, 1, 10, Obs.CastSuccess, false)
            ctl.ViewerAura(item, "player")
            poll(11)
            assert.are.equal(20, VS.Aura("player", fs.SPENDER_A, 11).est)
            assert.are.same({ 1, 0 }, { I.presenceFacts[SHOUT], I.presenceDisagree[SHOUT] })
        end)

        it("the poll takes a believed-up aura down when an item seen holding it goes silent", function()
            I.AuraModel(1, SHOUT, 10, 20, 1, 10, Obs.CastSuccess, false)
            I.AuraOurs(1, SHOUT) -- our cast's (Families/Now.lua): rule 2.5.1
            ctl.ViewerAura(item, "player")
            poll(10.5) -- the item holds our application
            ctl.ViewerClear(item)
            poll(11)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 11))
            assert.are.same({ 2, 1 }, { I.presenceFacts[SHOUT], I.presenceDisagree[SHOUT] })
        end)

        it("a never-lit item, a cooldown entry (Essential) included, never closes our cast self-buff (L279)", function()
            ctl.ViewerRelease(item) -- the Essential entry alone
            ctl.ViewerAcquire("EssentialCooldownViewer", 600, true) -- grows in combat; never shows the aura (F12)
            I.AuraModel(1, SHOUT, 10, 20, 1, 10, Obs.CastSuccess, false)
            for t = 10.5, 14, 0.5 do
                poll(t)
                assert.are.equal(20, VS.Aura("player", fs.SPENDER_A, t).est)
            end
            assert.are.same({ 0, 0 }, { I.presenceFacts[SHOUT], I.presenceDisagree[SHOUT] })
        end)

        it(
            "an item seen only for the target, held for the player while hidden, then silent keeps our buff (F1)",
            function()
                I.AuraModel(1, SHOUT, 10, 20, 1, 10, Obs.CastSuccess, false) -- our player application at 10
                ctl.ViewerAura(item, "target")
                poll(10.5) -- seen holding for the target only
                ctl.viewer.shown.BuffIconCooldownViewer = false
                ctl.ViewerAura(item, "player")
                poll(11) -- hidden: stale for the player, no sSeen write
                ctl.viewer.shown.BuffIconCooldownViewer = nil
                ctl.ViewerClear(item)
                poll(11.5)
                poll(12)
                assert.are.equal(20, VS.Aura("player", fs.SPENDER_A, 12).est)
                assert.are.equal(0, I.presenceDisagree[SHOUT])
            end
        )

        it("out of combat, a plain walk wins: presence stages nothing (in combat it does not: I7)", function()
            ctl.Fire("PLAYER_REGEN_ENABLED")
            ctl.auras.player.HELPFUL[1] = nil
            ctl.Fire("UNIT_AURA", "player")
            I.ObsLog.Clear(I.log)
            ctl.ViewerAura(item, "player")
            poll(11)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 11))
            assert.are.same({ 0, 0 }, { I.presenceFacts[SHOUT], I.presenceDisagree[SHOUT] })
        end)

        it("a staged read cut short by a plain walk does not suppress the next fight's edge", function()
            ctl.ViewerAura(item, "player")
            poll(10) -- in combat: the sweep's edge stages a Read up, the fold takes it
            assert.are.equal(130, VS.Aura("player", fs.SPENDER_A, 10).est)
            assert.are.same({ 1, 1 }, { I.presenceFacts[SHOUT], I.presenceDisagree[SHOUT] })
            ctl.Fire("PLAYER_REGEN_ENABLED") -- combat ends, the walk turns plain and shows it gone
            ctl.auras.player.HELPFUL[1] = nil
            ctl.Fire("UNIT_AURA", "player")
            poll(10.5)
            ctl.Fire("UNIT_AURA", "player")
            ctl.ViewerClear(item)
            poll(11)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 11))
            ctl.now = 20 -- the next fight: the walk is secret, the viewer shows the aura before any poll
            ctl.Fire("PLAYER_REGEN_DISABLED")
            ctl.auras.player.HELPFUL[1] = fake.SECRET
            ctl.Fire("UNIT_AURA", "player")
            ctl.ViewerAura(item, "player")
            poll(21)
            poll(22)
            assert.are.equal(141, VS.Aura("player", fs.SPENDER_A, 22).est)
            assert.are.same({ 1, 1 }, { I.presenceFacts[SHOUT], I.presenceDisagree[SHOUT] })
        end)

        it("prints the exit walk's corrections on the presence line (exitFix)", function()
            I.AuraModel(1, SHOUT, 10, 40, 1, 10, Obs.CastSuccess, false)
            ctl.auras.player.HELPFUL[1] = nil -- plain again out of combat: the walk shows it gone
            ctl.Fire("PLAYER_REGEN_ENABLED")
            poll(12)
            local snap = VS.Snapshot()
            assert.is_truthy(snap:find("presence spender_a unit=player fact=unknown from=walk n=0 ", 1, true), snap)
            assert.is_truthy(snap:find("beliefDisagree=0 itemDisagree=0 ambiguous=0 lost=0 exitFix=1", 1, true), snap)
        end)

        it("allocates nothing over 1000 polls, sweeps and edges", function()
            local alloc = require("Game.State.helpers.alloc")
            local t = 10
            assert.are.equal(
                0,
                alloc.bytes(function()
                    t = t + 0.01
                    -- the item's fields directly (ctl.ViewerAura logs its writes: the fake's allocation)
                    local on = item.auraInstanceID == nil
                    item.auraInstanceID, item.auraDataUnit = on and fake.SECRET or nil, on and "player" or nil
                    S.RunPolls(t)
                    I.Fold(t, false)
                end, 1000)
            )
        end)
    end)

    -- cdm-default §2.5 (Task 4b): who may close (ours, decision 111 as amended: the target too), the bounded UP (C2,
    -- decision 112), the walk wins out of combat only (I7), forms skipped (M5), the floor, the snapshot section.
    describe("reconciliation of the reduced facts (cdm-default §2.5)", function()
        local pi, ti, P -- the player aura's item (SHOUT), the target debuff's item (REND), the router

        local function start(def)
            ctl.now = 1 -- a restart's own observations are stamped before the fight's (the log folds in order)
            def.providers = { presence = "router", viewer = true }
            I.Build(def, 1)
            VS.Start(api)
            P = I.presence
            ctl.now = 10
            ctl.Fire("PLAYER_TARGET_CHANGED") -- mob A (Creature-1) in its memory slot
            I.Fold(10, false)
            ctl.Fire("PLAYER_REGEN_DISABLED")
            ctl.auras.player.HELPFUL[1] = fake.SECRET -- both walks secret: only the reduced facts speak
            ctl.auras.target.HARMFUL[1] = fake.SECRET
            ctl.Fire("UNIT_AURA", "player")
            ctl.Fire("UNIT_AURA", "target")
            I.ObsLog.Clear(I.log)
        end

        before_each(function()
            ctl.viewer.sets[2] = { 501, 502 }
            ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
            ctl.viewer.infos[502] = { spellID = fs.SPENDER_C }
            pi = ctl.ViewerItem("BuffIconCooldownViewer", 1, 501)
            ti = ctl.ViewerItem("BuffIconCooldownViewer", 2, 502)
            start(fs.def(fs.new(9)))
        end)

        local function poll(t)
            ctl.now = t
            ctl.Tick(t)
            S.RunPolls(t)
            I.Fold(t, false)
            I.Settle(t)
        end
        -- Our cast's write as Families/Now.lua makes it: the record, then ours.
        local function cast(u, j, t, d)
            I.AuraModel(u, j, t, t + d, 1, t, Obs.CastSuccess, u == 2)
            I.AuraOurs(u, j)
        end
        local function est(unit, spell, t)
            local r = VS.Aura(unit, spell, t)
            return r and r.est
        end
        local function swap(guid, t)
            ctl.now = t
            ctl.guid.target = guid
            ctl.Fire("PLAYER_TARGET_CHANGED")
        end

        it(
            "a target DOWN closes our debuff once its item lit this application; never lit, it closes nothing",
            function()
                cast(2, REND, 10, 15)
                for t = 10.5, 12, 0.5 do
                    poll(t)
                    assert.are.equal(25, est("target", fs.SPENDER_C, t)) -- never lit: UNKNOWN, the model runs
                end
                assert.are.equal(I.UNDECIDED, P.Presence(REND, 2))
                ctl.ViewerAura(ti, "target")
                poll(12.5)
                assert.are.equal(I.UP, P.Presence(REND, 2))
                ctl.ViewerClear(ti) -- our debuff ends early (a dispel): the item that lit it goes silent
                poll(13)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 13))
            end
        )

        it("a target switch resets the item: silent on the new target it closes nothing; lit there, it does", function()
            I.verdictOff = true -- the seen rule alone (the item lit on A is proven: the verdict's twin is below)
            cast(2, REND, 10, 15)
            ctl.ViewerAura(ti, "target")
            poll(10.5)
            poll(11) -- lit for mob A's application
            swap("Creature-2", 11.1)
            ctl.ViewerClear(ti) -- the client clears A's light from the next frame
            poll(11.2)
            cast(2, REND, 11.5, 15) -- our debuff on mob B; its item has not lit it yet
            for t = 12, 13, 0.5 do
                poll(t)
                assert.are.equal(26.5, est("target", fs.SPENDER_C, t)) -- reset at the switch: no close
            end
            ctl.ViewerAura(ti, "target")
            poll(13.5)
            poll(14)
            ctl.ViewerClear(ti)
            poll(14.5)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 14.5)) -- control: lit on B, then silent: closes
        end)

        it("switching away and back does not restore a record the item closed", function()
            cast(2, REND, 10, 15)
            ctl.ViewerAura(ti, "target")
            poll(10.5)
            ctl.ViewerClear(ti)
            poll(11)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 11))
            swap("Creature-2", 12)
            poll(12.2)
            swap("Creature-1", 13)
            poll(13.2)
            poll(13.5)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 13.5))
        end)

        it("the switch's own frame (f=0) is stale: an old light opens nothing, a silence closes nothing", function()
            cast(2, REND, 10, 15)
            ctl.ViewerAura(ti, "target")
            poll(10.5) -- lit on mob A
            swap("Creature-2", 11)
            poll(11) -- f=0 (CDM-O; the switch's own t): the item still shows A's debuff
            assert.are.equal(I.UNDECIDED, P.Presence(REND, 2))
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 11)) -- no UP on mob B
            ctl.ViewerClear(ti) -- right from f=1
            poll(11.1)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 11.1))
            swap("Creature-1", 12)
            poll(12) -- f=0 back on A: the item is still silent (not re-lit yet)
            assert.are.equal(25, est("target", fs.SPENDER_C, 12)) -- no DOWN
            poll(12.1)
            assert.are.equal(25, est("target", fs.SPENDER_C, 12.1)) -- reset at the switch: no DOWN after it either
            ctl.ViewerAura(ti, "target") -- A's debuff lit again
            poll(12.2)
            ctl.ViewerClear(ti)
            poll(12.8)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 12.8)) -- control: lit after the switch, then silent
        end)

        it(
            "an item seen only for the player, held for the target while hidden, then silent keeps our debuff (F1)",
            function()
                cast(2, REND, 10, 15)
                ctl.ViewerAura(ti, "player")
                poll(10.5) -- seen holding for the player only
                ctl.viewer.shown.BuffIconCooldownViewer = false
                ctl.ViewerAura(ti, "target")
                poll(11) -- hidden: stale for the target, no sSeen write
                ctl.viewer.shown.BuffIconCooldownViewer = nil
                ctl.ViewerClear(ti)
                poll(11.5)
                poll(12)
                assert.are.equal(25, est("target", fs.SPENDER_C, 12))
                ctl.ViewerAura(ti, "target")
                poll(12.5)
                ctl.ViewerClear(ti)
                poll(13)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 13)) -- control: lit for the target, then silent
            end
        )

        it("a false target UP (a stale light) is bounded and taken down at the next silent sweep (L288)", function()
            ctl.ViewerAura(ti, "target")
            poll(10.5)
            assert.are.equal(25.5, est("target", fs.SPENDER_C, 10.5)) -- from the light: never math.huge
            ctl.ViewerClear(ti)
            poll(10.7)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 10.7))
        end)

        it("a target switch starts the fact over: mob B opens from its own light, not mob A's (review I1)", function()
            cast(2, REND, 10, 15)
            ctl.ViewerAura(ti, "target")
            poll(10.2)
            for t = 10.5, 19.5, 0.5 do
                poll(t)
            end
            swap("Creature-2", 20)
            ctl.ViewerAura(ti, "target") -- mob B carries our debuff too (an AoE): lit from the next frame
            poll(20.2) -- the first drain after the switch lands past its frame (no UNKNOWN sweep)
            poll(20.5)
            assert.are.equal(35.2, est("target", fs.SPENDER_C, 20.5)) -- from B's light at 20.2, not A's at 10.2
        end)

        it(
            "L299: the drain in the switch's frame is stale; the next frame's drain opens mob B from its light",
            function()
                cast(2, REND, 10, 15)
                ctl.ViewerAura(ti, "target")
                for t = 10.5, 19.5, 0.5 do
                    poll(t)
                end
                swap("Creature-2", 20)
                poll(20) -- f=0: the item still shows A's light; the fold takes the switch
                assert.are.equal(I.UNDECIDED, P.Presence(REND, 2))
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 20)) -- nothing on mob B
                poll(20.006) -- f=1 (CDM-O: ~6 ms): mob B carries our debuff too, the item shows it
                assert.are.equal(I.UP, P.Presence(REND, 2))
                assert.are.equal(35.006, est("target", fs.SPENDER_C, 20.006)) -- from B's first trusted light
            end
        )

        it(
            "the switch's drain applies nothing on the target: mob A's record never decides for mob B (review m3)",
            function()
                do -- the model's own expiry stands (L310)
                    local rule, held = "C", 25
                    ctl.guid.target = "Creature-1"
                    start(fs.def(fs.new(9)))
                    cast(2, REND, 10, 15) -- mob A's record expires at 25
                    ctl.ViewerAura(ti, "target")
                    for t = 10.5, 24.5, 0.5 do
                        poll(t)
                    end
                    assert.are.equal(held, est("target", fs.SPENDER_C, 24.5), rule)
                    swap("Creature-2", 25)
                    ctl.ViewerAura(ti, "target") -- mob B carries our debuff too: lit from the next frame
                    poll(25.1) -- the switch's drain: its polls run before the fold takes the switch (A's record near lapse)
                    poll(25.3)
                    assert.are.equal(40.1, est("target", fs.SPENDER_C, 25.3), rule) -- opened on B from B's light
                    ctl.ViewerClear(ti)
                    poll(25.6)
                    assert.is_nil(VS.Aura("target", fs.SPENDER_C, 25.6), rule) -- a CDM UP opened it on B: ours, so its NONE closes
                end
            end
        )

        -- Lane A (the swap guard): under Map every target's GUID is secret, so every swap names slot 0 and the m3
        -- guard (slot numbers) never saw a swap pending. The pending swap is a serial now.
        local function near(want, got, label)
            assert.is_true(got ~= nil and math.abs(got - want) < 1e-9, (label or "") .. " " .. tostring(got))
        end
        local function debounceWaits()
            return tonumber(VS.Snapshot():match("presence%-edge debounceWaits=(%d+)"))
        end

        it("Map: the switch's drain applies nothing on the target, B opens from its own light (lane A)", function()
            ctl.guid.target = fake.SECRET
            start(fs.def(fs.new(9)))
            cast(2, REND, 10, 15) -- mob A's record expires at 25
            ctl.ViewerAura(ti, "target")
            for t = 10.5, 12, 0.5 do
                poll(t)
            end
            assert.are.equal(25, est("target", fs.SPENDER_C, 12))
            swap(fake.SECRET, 13) -- mob B carries our debuff too: the item stays lit
            poll(13.1) -- the first drain past the switch's frame: its polls run before the fold
            poll(13.3)
            assert.are.equal(0, I.curSlot) -- the Map premise: no memory slot for a secret GUID
            near(28.1, est("target", fs.SPENDER_C, 13.3), "B opened from its own light")
            for t = 13.5, 16.5, 0.5 do
                poll(t)
                near(28.1, est("target", fs.SPENDER_C, t), t)
            end
            assert.are.equal(0, debounceWaits()) -- no Fix B: the debounce memory never held A's record for B
            swap(fake.SECRET, 17) -- back to A, B's record up, no drain in the switch's frame
            poll(17.1)
            poll(17.3)
            near(32.1, est("target", fs.SPENDER_C, 17.3), "A re-opened (no memory under Map: the seed)")
            for t = 17.5, 20, 0.5 do
                poll(t)
                near(32.1, est("target", fs.SPENDER_C, t), t)
            end
            assert.are.equal(0, debounceWaits())
        end)

        it("Map: a rebuild drops a logged swap before its fold; the target stays judgeable (lane A)", function()
            ctl.guid.target = fake.SECRET
            local def = fs.def(fs.new(9))
            start(def)
            swap(fake.SECRET, 11) -- logged, never folded: the rebuild clears the log
            ctl.Fire("PLAYER_REGEN_ENABLED") -- out of combat: an in-combat rebuild keeps the providers off (decision 89)
            I.Build(def, 11) -- logs its own swap (Sources/Target.lua's build hook)
            ctl.Fire("PLAYER_REGEN_DISABLED")
            ctl.Fire("UNIT_AURA", "player") -- both walks secret again
            ctl.Fire("UNIT_AURA", "target")
            ctl.ViewerAura(ti, "target")
            poll(11.1)
            poll(11.3)
            assert.is_not_nil(est("target", fs.SPENDER_C, 11.3)) -- a light opens the target's record
            ctl.ViewerClear(ti)
            poll(11.6)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 11.6)) -- and its NONE closes it
        end)

        -- The owner's rule (L310, decision 112 as amended; variant C, the default): trust the belief's duration. No
        -- extension before the model's expiry; past it, the CDM overrides only once its item stayed lit HOLD, then
        -- once, long (3600 s; -1 for a player aura with no numeric duration), closed by the observed down.
        it("C: a lit item at a correct expiry adds nothing: the record goes down at its own expiry (L310)", function()
            cast(2, REND, 10, 15)
            ctl.ViewerAura(ti, "target")
            for t = 10.5, 24.5, 0.5 do
                poll(t)
                assert.are.equal(25, est("target", fs.SPENDER_C, t), t)
            end
            poll(24.9)
            assert.are.equal(25, est("target", fs.SPENDER_C, 24.9))
            poll(25.1) -- the item still lit a poll past the end (its latency)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 25.1))
            ctl.ViewerClear(ti)
            for t = 25.3, 27.3, 0.5 do
                poll(t)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, t), t)
            end
        end)

        it("C: lit HOLD past the model's expiry, the CDM re-establishes it once, long; its NONE closes it", function()
            cast(2, REND, 10, 15)
            ctl.ViewerAura(ti, "target")
            for t = 10.5, 24.5, 0.5 do
                poll(t)
            end
            for _, t in ipairs({ 25, 25.4, 25.8 }) do
                poll(t)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, t), t) -- the debounce: down for up to HOLD
            end
            poll(26.2)
            local long = est("target", fs.SPENDER_C, 26.2)
            assert.is_true(math.abs(long - 3626.2) < 1e-9, long) -- finite: inf - inf is NaN
            for t = 26.6, 30.2, 0.4 do
                poll(t)
                assert.are.equal(long, est("target", fs.SPENDER_C, t), t) -- written once, no renewal
            end
            ctl.ViewerClear(ti)
            poll(30.6)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 30.6)) -- the observed down closes it (a CDM UP's: ours)
        end)

        -- review S1 (kept by the controller's ruling): a dark poll past the model's expiry is the CDM's fact that the
        -- aura is gone; the next light restarts nothing, it is a new application and opens at once. Not red under A (A
        -- also opens a new light at once); red-first against C without the dark reset (the first green run of this
        -- lane, before Sources/Auras.lua reset lastE on a non-UP poll past the expiry: est nil at 25.8, the light
        -- waited HOLD as if the old application still ran).
        it("C: an item dark past the model's expiry, then lit again: a new application, opened at once", function()
            cast(2, REND, 10, 15)
            ctl.ViewerAura(ti, "target")
            for t = 10.5, 24.5, 0.5 do
                poll(t)
            end
            poll(25.2)
            ctl.ViewerClear(ti)
            poll(25.6) -- dark: the aura ended
            ctl.ViewerAura(ti, "target") -- lit again: a new application (someone's), the model has none
            poll(25.8)
            assert.is_true(math.abs(est("target", fs.SPENDER_C, 25.8) - 40.8) < 1e-9) -- opened at once from its light
        end)

        it("C: a CDM UP with no model record opens at once; no numeric duration: long on the target too", function()
            local def = fs.def(fs.new(9))
            def.auras[SHOUT] = { key = "spender_a", id = fs.SPENDER_A }
            def.auras[REND] = { key = "spender_c", id = fs.SPENDER_C }
            start(def)
            ctl.ViewerAura(ti, "target")
            ctl.ViewerAura(pi, "player")
            poll(10.5)
            assert.are.equal(3610.5, est("target", fs.SPENDER_C, 10.5)) -- not math.huge on the target
            assert.are.equal(math.huge, est("player", fs.SPENDER_A, 10.5)) -- a permanent player aura: as before
            poll(11)
            assert.are.equal(3610.5, est("target", fs.SPENDER_C, 11)) -- no re-stage
            ctl.ViewerClear(pi)
            ctl.ViewerClear(ti)
            poll(11.5)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 11.5))
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 11.5))
        end)

        it(
            "C: a long record whose CDM stops answering (UNKNOWN, every viewer hidden) is clamped to HOLD once",
            function()
                local def = fs.def(fs.new(9))
                def.auras[SHOUT] = { key = "spender_a", id = fs.SPENDER_A }
                def.auras[REND] = { key = "spender_c", id = fs.SPENDER_C }
                start(def)
                ctl.ViewerAura(ti, "target")
                ctl.ViewerAura(pi, "player")
                poll(10.5)
                ctl.ViewerRelease(ti) -- the target's evidence goes away: UNKNOWN
                poll(11)
                assert.are.equal(I.UNDECIDED, P.Presence(REND, 2))
                assert.are.equal(12, est("target", fs.SPENDER_C, 11)) -- one HOLD write
                poll(11.5)
                assert.are.equal(12, est("target", fs.SPENDER_C, 11.5)) -- once
                poll(12.1)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 12.1))
                ctl.viewer.parentShown = false -- every viewer hidden: covered 0
                poll(12.5)
                assert.are.equal(13.5, est("player", fs.SPENDER_A, 12.5)) -- the player's -1 record too
                poll(13.6)
                assert.is_nil(VS.Aura("player", fs.SPENDER_A, 13.6))
            end
        )

        it(
            "C: a target switch clamps mob A's long record before it is remembered (Count.WithAura, swap back)",
            function()
                local def = fs.def(fs.new(9))
                def.auras[REND] = { key = "spender_c", id = fs.SPENDER_C }
                start(def)
                ctl.ViewerAura(ti, "target")
                poll(10.5)
                assert.are.equal(3610.5, est("target", fs.SPENDER_C, 10.5))
                swap("Creature-2", 11)
                ctl.ViewerClear(ti) -- mob B has none: dark from the next frame
                poll(11.1)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 11.1))
                assert.are.equal(1, VS.Count.WithAura(fs.SPENDER_C, 11.5)) -- mob A's, remembered for HOLD
                assert.are.equal(0, VS.Count.WithAura(fs.SPENDER_C, 12.1))
                swap("Creature-1", 13)
                poll(13.1)
                poll(13.5)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 13.5)) -- not restored for an hour
            end
        )

        -- F3 (cdm-task8-report.md): a CDM UP in the drain of our cast's write. Both orders: the poll's Read before the
        -- fold has the cast (the cast logged first folds first), and a light folded just before the cast (SAME_FRAME).
        it("F3: a CDM UP in our cast's drain never replaces the cast's expiry (a function duration)", function()
            local def = fs.def(fs.new(9))
            def.auras[REND] = {
                key = "spender_c",
                id = fs.SPENDER_C,
                duration = function() -- the pack's: no number here
                    return 18
                end,
            }
            start(def)
            ctl.ViewerAura(ti, "target")
            ctl.now = 10
            ctl.Tick(10)
            S.RunPolls(10) -- the record is down: the CDM UP stages
            cast(2, REND, 10, 18) -- the cast's write, logged before the poll's Read, folds first
            I.Fold(10, false)
            I.Settle(10)
            for t = 10, 13.6, 0.2 do
                if t > 10 then
                    poll(t)
                end
                assert.are.equal(28, est("target", fs.SPENDER_C, t), t)
            end
            -- the other order: the light folds first, our cast's write lands 0.02 s later (inside SAME_FRAME)
            ctl.guid.target = "Creature-1"
            start(def)
            ctl.ViewerAura(ti, "target")
            poll(20)
            cast(2, REND, 20.02, 18)
            for t = 20.2, 23.6, 0.2 do
                poll(t)
                assert.is_true(math.abs(est("target", fs.SPENDER_C, t) - 38.02) < 1e-9, t)
            end
        end)

        it("F3 control: a numeric duration's cast keeps its own expiry, not the light's t0 (+0.1 s before)", function()
            ctl.ViewerAura(ti, "target")
            ctl.now = 10.1
            ctl.Tick(10.1)
            S.RunPolls(10.1) -- the light stages from fact.t
            cast(2, REND, 10, 15) -- our cast's write at 10 folds first
            I.Fold(10.1, false)
            I.Settle(10.1)
            assert.are.equal(25, est("target", fs.SPENDER_C, 10.1))
        end)

        it(
            "C: an icd aura re-established after its expiry is a new application (its ICD restarts: L310 limit)",
            function()
                local def = fs.def(fs.new(9))
                def.auras[SHOUT] = { key = "spender_a", id = fs.SPENDER_A, duration = 3, icd = 10 }
                start(def)
                -- a clean walk first, as at login (firstWalk set; else the fold's first-walk sentinel moves applied)
                ctl.auras.player.HELPFUL[1] = nil
                ctl.Fire("UNIT_AURA", "player")
                ctl.auras.player.HELPFUL[1] = fake.SECRET
                ctl.Fire("UNIT_AURA", "player")
                cast(1, SHOUT, 10, 3)
                ctl.ViewerAura(pi, "player")
                for t = 10.2, 12.9, 0.2 do
                    poll(t)
                    assert.are.equal(10, select(3, VS.Aura("player", fs.SPENDER_A, t)), t)
                end
                poll(13.4)
                assert.is_nil(VS.Aura("player", fs.SPENDER_A, 13.4)) -- down at its 3 s, lit: the debounce
                poll(14.2)
                local rec, _, applied = VS.Aura("player", fs.SPENDER_A, 14.2)
                assert.is_true(math.abs(rec.est - 3614.2) < 1e-9, rec.est)
                assert.is_true(math.abs(applied - 14.2) < 1e-9, applied) -- a limit, pinned: the ICD restarts here
                ctl.ViewerClear(pi) -- (the 4b step cap kept 10)
                poll(14.6)
                assert.is_nil(VS.Aura("player", fs.SPENDER_A, 14.6)) -- a CDM re-establish is ours: its NONE closes it
            end
        )

        it("C: a re-establish carries the model's last stacks (rule 3), not one", function()
            I.AuraModel(2, REND, 10, 25, 3, 10, Obs.CastSuccess, true) -- our 3-stack debuff, expires 25
            I.AuraOurs(2, REND)
            ctl.ViewerAura(ti, "target")
            for t = 10.5, 24.5, 0.5 do
                poll(t)
            end
            poll(25.2)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 25.2)) -- the debounce
            poll(26.2)
            local rec, stacks = VS.Aura("target", fs.SPENDER_C, 26.2)
            assert.is_truthy(rec)
            assert.are.equal(3, stacks)
        end)

        it("in combat, a walk with nil at index 1 does not suppress the facts (I7)", function()
            ctl.auras.player.HELPFUL[1] = nil
            ctl.Fire("UNIT_AURA", "player") -- in combat a nil first entry reads as a complete walk (F1)
            ctl.ViewerAura(pi, "player")
            poll(10.5)
            assert.are.equal(130.5, est("player", fs.SPENDER_A, 10.5)) -- t0 + the registered 120 s
        end)

        it("C1: a partner's copy read out of combat is not ours: its NONE closes nothing; ours does", function()
            cast(1, SHOUT, 10, 120)
            ctl.ViewerAura(pi, "player")
            poll(10.5)
            poll(11)
            ctl.now = 12
            ctl.Fire("PLAYER_REGEN_ENABLED")
            ctl.auras.player.HELPFUL[1] =
                { spellId = fs.SPENDER_A, expirationTime = 200, applications = 0, sourceUnit = "party1" }
            ctl.Fire("UNIT_AURA", "player") -- a partner's copy overwrote ours
            poll(12)
            ctl.ViewerClear(pi)
            poll(12.5)
            ctl.now = 13
            ctl.Fire("PLAYER_REGEN_DISABLED")
            ctl.auras.player.HELPFUL[1] = fake.SECRET
            ctl.Fire("UNIT_AURA", "player")
            for t = 13, 15, 0.5 do
                poll(t)
                assert.are.equal(200, est("player", fs.SPENDER_A, t))
            end
            assert.are.equal(I.DOWN, P.Presence(SHOUT, 1)) -- the NONE is there; not ours, so no close
            cast(1, SHOUT, 16, 120)
            ctl.ViewerAura(pi, "player")
            poll(16.5)
            poll(17)
            ctl.ViewerClear(pi)
            poll(17.5)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 17.5)) -- control: our cast, lit, then it ends
        end)

        it("C1: a CDM UP opens ours; an out-of-combat walk read sets ours by its source", function()
            ctl.ViewerAura(pi, "player")
            poll(10.5)
            assert.is_true(I.auraOurs[SHOUT] ~= 0)
            ctl.ViewerClear(pi)
            poll(11)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 11)) -- opened by the CDM: its NONE closes
            ctl.now = 12
            ctl.Fire("PLAYER_REGEN_ENABLED")
            for i, c in ipairs({ { "player", true }, { "party1", false }, { "pet", true }, { fake.SECRET, false } }) do
                ctl.auras.player.HELPFUL[1] =
                    { spellId = fs.SPENDER_A, expirationTime = 200, applications = 0, sourceUnit = c[1] }
                ctl.Fire("UNIT_AURA", "player")
                assert.are.equal(c[2], I.auraOurs[SHOUT] ~= 0, "case " .. i)
            end
            local function entry(src)
                return { spellId = fs.SPENDER_A, expirationTime = 200, applications = 0, sourceUnit = src }
            end
            ctl.auras.player.HELPFUL[1], ctl.auras.player.HELPFUL[2] = entry("player"), entry("party1")
            ctl.Fire("UNIT_AURA", "player")
            assert.is_true(I.auraOurs[SHOUT] ~= 0) -- ours and a partner's copy in one walk: ours
            ctl.auras.player.HELPFUL[1], ctl.auras.player.HELPFUL[2] = entry("party1"), entry("player")
            ctl.Fire("UNIT_AURA", "player")
            assert.is_true(I.auraOurs[SHOUT] ~= 0)
        end)

        it("CDM-P: a partner's copy of our debuff lights nothing, and our item never closes it", function()
            cast(2, REND, 10, 15)
            ctl.ViewerAuraBySpell("target", fs.SPENDER_C, true, "player")
            poll(10.5)
            poll(11)
            ctl.now = 12
            ctl.Fire("PLAYER_REGEN_ENABLED")
            ctl.ViewerAuraBySpell("target", fs.SPENDER_C, true, "party1") -- the partner's copy: lights nothing (F10)
            assert.are.equal(1, #ti.writes) -- only our own light so far
            ctl.ViewerAuraBySpell("target", fs.SPENDER_C, false, "player") -- it overwrote ours: our item goes silent
            ctl.auras.target.HARMFUL[1] =
                { spellId = fs.SPENDER_C, expirationTime = 40, applications = 0, sourceUnit = "party1" }
            ctl.Fire("UNIT_AURA", "target")
            poll(12)
            ctl.now = 13
            ctl.Fire("PLAYER_REGEN_DISABLED")
            ctl.auras.target.HARMFUL[1] = fake.SECRET
            ctl.Fire("UNIT_AURA", "target")
            for t = 13, 15, 0.5 do
                poll(t)
                assert.are.equal(40, est("target", fs.SPENDER_C, t)) -- no needless close, no recast loop
            end
            cast(2, REND, 16, 15)
            ctl.ViewerAuraBySpell("target", fs.SPENDER_C, true, "player")
            poll(16.5)
            poll(17)
            ctl.ViewerAuraBySpell("target", fs.SPENDER_C, false, "player")
            poll(17.5)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 17.5)) -- control: our own cast, lit, then it ends
        end)

        it("a target's ours does not follow us to another mob: mob B's partner copy is not closed", function()
            ctl.now = 10
            ctl.Fire("PLAYER_REGEN_ENABLED")
            swap("Creature-2", 10)
            ctl.auras.target.HARMFUL[1] =
                { spellId = fs.SPENDER_C, expirationTime = 60, applications = 0, sourceUnit = "party1" }
            ctl.Fire("UNIT_AURA", "target") -- mob B: a partner's copy, not ours
            poll(10.2)
            swap("Creature-1", 10.5)
            ctl.auras.target.HARMFUL[1] = nil
            ctl.Fire("UNIT_AURA", "target")
            poll(10.7)
            ctl.now = 12
            ctl.Fire("PLAYER_REGEN_DISABLED")
            ctl.auras.target.HARMFUL[1] = fake.SECRET
            cast(2, REND, 12, 15) -- ours on mob A
            ctl.ViewerAura(ti, "target")
            poll(12.5)
            poll(13)
            swap("Creature-2", 14)
            ctl.ViewerClear(ti)
            poll(14.1)
            assert.are.equal(60, est("target", fs.SPENDER_C, 14.1))
            ctl.ViewerAura(ti, "target") -- the item shows a copy on B for a while
            poll(14.2)
            poll(14.8)
            ctl.ViewerClear(ti)
            for t = 15, 16, 0.5 do
                poll(t)
                assert.are.equal(60, est("target", fs.SPENDER_C, t)) -- A's cast does not make B's record ours
            end
            cast(2, REND, 17, 15) -- ours on B now
            ctl.ViewerAura(ti, "target")
            poll(17.5)
            poll(18)
            ctl.ViewerClear(ti)
            poll(18.5)
            assert.is_nil(VS.Aura("target", fs.SPENDER_C, 18.5)) -- control
        end)

        describe("the verdict (cdm-verdict §2.3-§2.7)", function()
            local function kT()
                return I.AURA_UNIT + REND
            end
            -- The target item proven on mob A by a CDM light that its own silence then closes (rule 1): dark since 10.5.
            local function prove()
                ctl.ViewerAura(ti, "target")
                poll(10.2)
                ctl.ViewerClear(ti)
                poll(10.5)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 10.5))
                assert.is_true(I.PRESENCE.viewer.proven[502])
            end

            it(
                "a miss from dark: our cast's record closes at the first poll >= cast + W with pdark, not before",
                function()
                    prove()
                    cast(2, REND, 11, 15) -- dodged: the item never lights
                    for _, t in ipairs({ 11.2, 11.5, 11.8, 11.95 }) do
                        poll(t)
                        assert.are.equal(26, est("target", fs.SPENDER_C, t), t)
                    end
                    assert.is_true(P.fact.pdark[kT()])
                    assert.are.equal(0, P.covered) -- dark is never live: the verdict runs with no live slot
                    poll(12)
                    assert.is_nil(VS.Aura("target", fs.SPENDER_C, 12))
                    assert.are.same({ 1, 12 }, { I.auraVerdict.n[kT()], I.auraVerdict.at[kT()] })
                    assert.are.same({ 1, 0 }, { I.presenceVerdict[kT()], I.presenceStrike[kT()] }) -- the harness's names
                    local snap = VS.Snapshot()
                    assert.is_truthy(
                        snap:find(
                            "presence-verdict spender_c unit=target W=1.00 verdicts=1 strikes=0 pdark=true darkSlots=1",
                            1,
                            true
                        ),
                        snap
                    )
                    assert.is_truthy(snap:find("presence-proof mappedNeverLit=spender_a", 1, true), snap)
                    local builds = I.PRESENCE.viewer.builds -- per session (review S2)
                    assert.is_true(builds >= 1)
                    assert.is_truthy(
                        snap:find("presence-proof repoints=0 struck=0 suspended=0 builds=" .. builds, 1, true),
                        snap
                    )
                end
            )

            it("review M1: an in-combat rebuild leaves no stale pdark: no leaf, no verdict", function()
                prove()
                cast(2, REND, 11, 15)
                poll(11.5)
                assert.is_true(P.fact.pdark[kT()])
                P.Deactivate(11.6) -- a build in combat (I.Build -> provide): the leaf goes, its activation waits
                P.Activate(api, 11.6, I.def, { viewer = true })
                assert.is_nil(P.Leaf())
                assert.is_false(P.fact.pdark[kT()])
                P.fact.pdark[kT()] = true -- even a stale one: the verdict needs the leaf
                for t = 11.8, 14, 0.2 do
                    poll(t)
                    assert.are.equal(26, est("target", fs.SPENDER_C, t), t)
                end
                assert.are.equal(0, I.auraVerdict.n[kT()])
            end)

            it("an item never lit (unproven) gives no verdict", function()
                cast(2, REND, 11, 15)
                for t = 11.5, 14, 0.5 do
                    poll(t)
                    assert.are.equal(26, est("target", fs.SPENDER_C, t), t)
                end
                assert.are.equal(0, I.auraVerdict.n[kT()])
            end)

            it("a lit item: no verdict; a refresh into the lit item: no verdict", function()
                prove()
                cast(2, REND, 11, 15)
                ctl.ViewerAura(ti, "target")
                for t = 11.1, 14, 0.3 do
                    poll(t)
                end
                assert.are.equal(26, est("target", fs.SPENDER_C, 14))
                cast(2, REND, 14.1, 15) -- refreshed while lit
                for t = 14.2, 17, 0.3 do
                    poll(t)
                end
                assert.are.equal(29.1, est("target", fs.SPENDER_C, 17))
                assert.are.equal(0, I.auraVerdict.n[kT()])
            end)

            it("W per travel: max(W0, travel + TOL)", function()
                prove()
                I.AuraModel(2, REND, 11, 26, 1, 11, Obs.CastSuccess, true)
                I.AuraOurs(2, REND, 1.5) -- a projectile: 1.5 s of travel
                assert.are.equal(1.8, I.auraVerdict.W[kT()])
                for _, t in ipairs({ 11.5, 12, 12.5, 12.75 }) do
                    poll(t)
                    assert.are.equal(26, est("target", fs.SPENDER_C, t), t)
                end
                poll(12.8)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 12.8))
                I.AuraOurs(2, REND, 0.2) -- short travel: W0
                assert.are.equal(1.0, I.auraVerdict.W[kT()])
            end)

            it("a CDM opener and a walk read of ours get W0", function()
                I.AuraOurs(2, REND, 3)
                assert.are.equal(3.3, I.auraVerdict.W[kT()])
                ctl.ViewerAura(ti, "target") -- a CDM UP with no record opens it
                poll(10.2)
                assert.are.same({ 2, 1.0 }, { I.auraOurs[kT()], I.auraVerdict.W[kT()] })
                I.AuraOurs(1, SHOUT, 3)
                ctl.Fire("PLAYER_REGEN_ENABLED")
                ctl.auras.player.HELPFUL[1] =
                    { spellId = fs.SPENDER_A, expirationTime = 200, applications = 0, sourceUnit = "player" }
                ctl.Fire("UNIT_AURA", "player")
                assert.are.same({ 3, 1.0 }, { I.auraOurs[SHOUT], I.auraVerdict.W[SHOUT] })
            end)

            it("a record ours did not open (ours 0) is never judged", function()
                prove()
                I.AuraModel(2, REND, 11, 26, 1, 11, Obs.CastSuccess, true) -- no AuraOurs: a partner's
                for t = 11.5, 14, 0.5 do
                    poll(t)
                    assert.are.equal(26, est("target", fs.SPENDER_C, t), t)
                end
            end)

            it(
                "a swap inside W: no verdict on mob B; mob A's record closes W after monitoring resumed (review M2)",
                function()
                    prove()
                    cast(2, REND, 11, 15)
                    poll(11.2)
                    swap("Creature-2", 11.3)
                    for t = 11.3, 12.9, 0.2 do
                        poll(t)
                    end
                    assert.are.equal(0, I.auraVerdict.n[kT()]) -- B has no record of ours
                    swap("Creature-1", 13)
                    poll(13) -- the swap's frame: settling
                    poll(13.2) -- the first monitored dark sweep: dark since 13.2
                    assert.are.equal(13.2, P.fact.pdarkT[kT()])
                    for _, t in ipairs({ 13.4, 13.8, 14.1 }) do
                        poll(t)
                        assert.are.equal(26, est("target", fs.SPENDER_C, t), t) -- W counts from 13.2, not the cast
                    end
                    poll(14.2)
                    assert.is_nil(VS.Aura("target", fs.SPENDER_C, 14.2)) -- continuously dark for W: dark means dark
                    assert.are.equal(1, I.auraVerdict.n[kT()])
                end
            )

            it("a hidden viewer restarts the dark: the record closes W after it is shown again (review M2)", function()
                prove()
                cast(2, REND, 11, 15)
                poll(11.5)
                ctl.viewer.shown.BuffIconCooldownViewer = false
                poll(12)
                assert.are.equal(26, est("target", fs.SPENDER_C, 12))
                ctl.viewer.shown.BuffIconCooldownViewer = nil
                for _, t in ipairs({ 12.2, 12.4, 13.1 }) do -- dark since 12.2
                    poll(t)
                    assert.are.equal(26, est("target", fs.SPENDER_C, t), t)
                end
                poll(13.2)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 13.2))
            end)

            it(
                "F52-B (review M2): swapped back to a mob whose real dot re-lights late: no verdict, no strike;"
                    .. " a truly dark one closes W after the swap back",
                function()
                    prove()
                    cast(2, REND, 11, 15)
                    ctl.ViewerAura(ti, "target") -- landed, lit
                    poll(11.2)
                    poll(11.7)
                    ctl.ViewerClear(ti)
                    swap("Creature-2", 13)
                    poll(13)
                    poll(13.2)
                    poll(13.7)
                    swap("Creature-1", 14) -- back to A: its dot is really up, the item re-lights late
                    poll(14)
                    poll(14.02) -- dark since here: applied (11) and upAt (11.7) are old, the monitoring is not
                    poll(14.04)
                    assert.are.same({ 26, 0, true, 14.02 }, {
                        est("target", fs.SPENDER_C, 14.04),
                        I.auraVerdict.n[kT()],
                        P.fact.pdark[kT()],
                        P.fact.pdarkT[kT()],
                    })
                    ctl.ViewerAura(ti, "target")
                    poll(14.06)
                    poll(14.08)
                    poll(14.5)
                    assert.are.same({ 26, 0, 0, 0 }, {
                        est("target", fs.SPENDER_C, 14.5), -- the cast's own expiry, never re-opened from the light
                        I.auraVerdict.n[kT()],
                        I.auraVerdict.strikes[kT()],
                        I.PRESENCE.viewer.strikes[502],
                    })
                    ctl.ViewerClear(ti) -- A's dot is dispelled while we look at B
                    swap("Creature-2", 15)
                    poll(15)
                    swap("Creature-1", 16)
                    poll(16)
                    for _, t in ipairs({ 16.2, 16.6, 17.1 }) do -- dark since 16.2
                        poll(t)
                        assert.are.equal(26, est("target", fs.SPENDER_C, t), t)
                    end
                    poll(17.2)
                    assert.is_nil(VS.Aura("target", fs.SPENDER_C, 17.2))
                    assert.are.equal(1, I.auraVerdict.n[kT()])
                end
            )

            it(
                "a light within STRIKE_WIN of a verdict is a strike; two strikes retire the item for the build",
                function()
                    prove()
                    cast(2, REND, 11, 15)
                    poll(11.5)
                    poll(12)
                    assert.is_nil(VS.Aura("target", fs.SPENDER_C, 12)) -- the verdict
                    ctl.ViewerAura(ti, "target") -- the late light (a lag spike): re-opens as a CDM open, one strike
                    poll(12.5)
                    assert.is_not_nil(VS.Aura("target", fs.SPENDER_C, 12.5))
                    assert.are.equal(0, I.auraVerdict.strikes[kT()]) -- (review M2) judged at the next poll
                    poll(12.7)
                    assert.are.same({ 1, 1, 0 }, {
                        I.auraVerdict.strikes[kT()],
                        I.PRESENCE.viewer.strikes[502],
                        I.auraVerdict.at[kT()],
                    })
                    ctl.ViewerClear(ti)
                    poll(13) -- rule 1 closes the CDM open
                    assert.is_nil(VS.Aura("target", fs.SPENDER_C, 13))
                    cast(2, REND, 15, 15)
                    poll(15.5)
                    poll(16)
                    assert.is_nil(VS.Aura("target", fs.SPENDER_C, 16)) -- the second verdict
                    ctl.ViewerAura(ti, "target")
                    poll(16.5)
                    poll(16.7)
                    assert.are.same({ 2, false, 1 }, {
                        I.auraVerdict.strikes[kT()],
                        I.PRESENCE.viewer.proven[502],
                        I.PRESENCE.viewer.struck,
                    })
                    ctl.ViewerClear(ti)
                    poll(17)
                    cast(2, REND, 19, 15) -- retired: belief-only
                    for t = 19.5, 22, 0.5 do
                        poll(t)
                        assert.are.equal(34, est("target", fs.SPENDER_C, t), t)
                    end
                    assert.are.equal(2, I.auraVerdict.n[kT()])
                end
            )

            it("a light after our new cast is no strike", function()
                prove()
                cast(2, REND, 11, 15)
                poll(11.5)
                poll(12) -- the verdict
                cast(2, REND, 12.3, 15) -- our recast lands and lights
                ctl.ViewerAura(ti, "target")
                poll(12.5)
                poll(12.7)
                assert.are.equal(0, I.auraVerdict.strikes[kT()])
            end)

            -- gate arm viewer-recast, Feral seed 3 (2026-11-09): the recast is stamped at the verdict's own time (a cast
            -- event in the frame of the poll that closed, staged after that drain: one GetTime per frame), so its
            -- applied time EQUALS verdictAt. It is still a new cast of ours: its light is no strike.
            it("a recast stamped at the verdict's own time is a new cast: its light is no strike", function()
                prove()
                cast(2, REND, 11, 15)
                poll(11.5)
                poll(12) -- the verdict: verdictAt 12
                assert.are.equal(12, I.auraVerdict.at[kT()])
                cast(2, REND, 12, 15) -- our recast, written at 12 after that drain
                ctl.ViewerAura(ti, "target")
                poll(12.2)
                poll(12.4)
                assert.are.same({ 0, 0, true }, {
                    I.auraVerdict.strikes[kT()],
                    I.PRESENCE.viewer.strikes[502],
                    I.PRESENCE.viewer.proven[502],
                })
            end)

            -- review M2: the drain runs the polls before the fold, so our recast's write (Now.lua's I.AuraOurs) lands
            -- after poll 15 saw its light; the strike is judged at the next poll.
            local function drain(t) -- VS.Drain's order (Sources.lua): staged, polls, fold, settle
                ctl.now = t
                ctl.Tick(t)
                S.Flush()
                S.RunPolls(t)
                I.Fold(t)
                I.Settle(t)
            end
            it("review M2: a verdict, then our logged recast whose light the same drain polls: no strike", function()
                local def = fs.def(fs.new(9))
                for _, ab in ipairs(def.abilities) do -- the plain record's `now` (Engine/Schema/Tracked.lua flattens it)
                    ab.now = ab.funcs and ab.funcs.now
                end
                start(def)
                prove()
                cast(2, REND, 11, 15) -- dodged
                drain(11.5)
                drain(12)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 12)) -- the verdict (correct)
                ctl.now = 12.8
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C) -- logged, folded by the drain
                ctl.ViewerAura(ti, "target") -- it lands and lights ~10 ms later, before the drain
                drain(13)
                assert.are.equal(1, I.auraOurs[kT()]) -- BY_CAST: the fold ran the recast's write after poll 15
                drain(13.2)
                drain(13.5)
                assert.are.same({ 0, 0 }, { I.auraVerdict.strikes[kT()], I.PRESENCE.viewer.strikes[502] })
                assert.is_true(I.PRESENCE.viewer.proven[502])
            end)

            it("review M2: a verdict, then a light with no cast of ours: the strike comes at the next poll", function()
                prove()
                cast(2, REND, 11, 15)
                drain(11.5)
                drain(12)
                ctl.ViewerAura(ti, "target")
                drain(12.5)
                assert.are.equal(0, I.auraVerdict.strikes[kT()])
                drain(12.7)
                assert.are.same({ 1, 1 }, { I.auraVerdict.strikes[kT()], I.PRESENCE.viewer.strikes[502] })
            end)

            it("F52-A (review M1): a recast folded in the verdict's own drain stands: no close, no strike", function()
                local def = fs.def(fs.new(9))
                for _, ab in ipairs(def.abilities) do
                    ab.now = ab.funcs and ab.funcs.now
                end
                start(def)
                prove()
                ctl.now = 11
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C) -- dodged: never lights
                drain(11)
                drain(11.2)
                drain(11.7)
                assert.are.same({ 26, 0 }, { est("target", fs.SPENDER_C, 11.7), I.auraVerdict.n[kT()] })
                ctl.now = 12.0
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_C) -- the recast at the GCD: it lands
                -- its drain is also the first poll >= cast 1 + W: the poll judges the OLD application, the fold writes
                -- the recast first (log order), and the close, naming the old one, is dropped
                drain(12.0)
                assert.are.same({ 27, 1, 0, 0 }, {
                    est("target", fs.SPENDER_C, 12.0), -- the recast's own expiry
                    I.auraOurs[kT()], -- BY_CAST
                    I.auraVerdict.n[kT()], -- no close happened: none counted
                    I.auraVerdict.at[kT()], -- and no strike window left open
                })
                assert.are.equal(0, I.PRESENCE.viewer.silent[502]) -- (re-review minor 1) nor a silent verdict counted
                ctl.ViewerAura(ti, "target") -- its light, a frame later
                drain(12.2)
                drain(12.4)
                assert.are.same({ 27, 1, 0, 0, 0 }, {
                    est("target", fs.SPENDER_C, 12.4),
                    I.auraOurs[kT()],
                    I.auraVerdict.n[kT()],
                    I.auraVerdict.strikes[kT()],
                    I.PRESENCE.viewer.strikes[502],
                })
                drain(12.6) -- lit REFRESH_LAG past the recast (D14)
                ctl.ViewerClear(ti) -- control: this application is still judged (rule 1 here: it was seen lit)
                drain(13)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 13))
            end)

            it("the verdict's read closes only the application it names (ReadOf.AuraVerdict)", function()
                cast(2, REND, 11, 15)
                S.Direct(Obs.Read, 11.5, kT(), 10.5, I.ReadOf.AuraVerdict) -- another application's applied time
                I.Fold(11.5, false)
                assert.are.equal(26, est("target", fs.SPENDER_C, 11.5))
                assert.are.equal(0, I.auraVerdict.n[kT()])
                S.Direct(Obs.Read, 11.6, kT(), 11, I.ReadOf.AuraVerdict) -- this one's
                I.Fold(11.6, false)
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 11.6))
                assert.are.same({ 1, 11.6 }, { I.auraVerdict.n[kT()], I.auraVerdict.at[kT()] })
                S.Direct(Obs.Read, 11.7, kT(), 0, I.ReadOf.AuraVerdict) -- a record already down: nothing
                I.Fold(11.7, false)
                assert.are.equal(1, I.auraVerdict.n[kT()])
            end)

            it("a verdict close drops the debounce's memory: a light at the very next poll re-opens at once", function()
                ctl.ViewerAura(ti, "target") -- a live slot throughout: poll 15's live branch
                cast(1, SHOUT, 10.1, 120)
                ctl.ViewerAura(pi, "player")
                poll(10.2) -- UP on a record up: lastE is the model's expiry
                poll(10.8)
                ctl.ViewerRelease(pi) -- re-pointed to a dark frame: no seen memory, no NONE; dark since 11.0
                local pi2 = ctl.ViewerItem("BuffIconCooldownViewer", 3, 501)
                poll(11.0)
                poll(11.5)
                assert.are.equal(130.1, est("player", fs.SPENDER_A, 11.5))
                poll(12.0)
                assert.is_nil(VS.Aura("player", fs.SPENDER_A, 12.0)) -- the verdict
                ctl.ViewerAura(pi2, "player") -- a wrong one: the item lights before any dark poll in between
                poll(12.2)
                assert.is_not_nil(VS.Aura("player", fs.SPENDER_A, 12.2)) -- not debounced against the old expiry
            end)

            it(
                "review S1: a verdict on mob A, a swap to mob B whose dot of ours is lit within 2 s: no strike",
                function()
                    prove()
                    cast(2, REND, 11, 15)
                    poll(11.5)
                    poll(12) -- the verdict on A (correct)
                    swap("Creature-2", 12.3)
                    ctl.ViewerAura(ti, "target") -- B carries our debuff: lit from the next frame
                    for t = 12.4, 13.2, 0.2 do
                        poll(t)
                    end
                    assert.are.same({ 0, 0 }, { I.auraVerdict.strikes[kT()], I.PRESENCE.viewer.strikes[502] })
                end
            )

            -- Fable 5.2 review M3 (it replaces the "V1 (review S3)" pin): a proven item silent for an application
            -- (F12 silence, a rank or variant the item does not follow, an immune mob) gives a verdict and never a
            -- strike (a strike needs a light). Two such verdicts with no light of the item between them suspend its
            -- proof: belief-only until it lights again, then it is judged as before.
            it(
                "V1 (review M3): two silent verdicts suspend the proof; belief-only until the item lights; then judged",
                function()
                    local Q = I.PRESENCE.viewer
                    prove()
                    for _, c in ipairs({ 11, 14 }) do
                        cast(2, REND, c, 15)
                        for t = c + 0.25, c + 0.75, 0.25 do
                            poll(t)
                            assert.are.equal(c + 15, est("target", fs.SPENDER_C, t), t)
                        end
                        poll(c + 1)
                        assert.is_nil(VS.Aura("target", fs.SPENDER_C, c + 1), c)
                        poll(c + 2.5) -- past STRIKE_WIN
                    end
                    assert.are.same({ 2, 0, false, 2, 1, 0 }, {
                        I.auraVerdict.n[kT()],
                        I.auraVerdict.strikes[kT()],
                        Q.proven[502],
                        Q.silent[502],
                        Q.suspended,
                        Q.strikes[502],
                    })
                    cast(2, REND, 17, 15) -- the third cast: belief-only, no recast loop
                    for t = 17.5, 21, 0.5 do
                        poll(t)
                        assert.are.equal(32, est("target", fs.SPENDER_C, t), t)
                    end
                    assert.are.equal(2, I.auraVerdict.n[kT()])
                    local snap = VS.Snapshot()
                    -- suspended is not "never lit"
                    assert.is_truthy(snap:find("presence-proof mappedNeverLit=spender_a\n", 1, true), snap)
                    assert.is_truthy(snap:find("presence-proof repoints=0 struck=0 suspended=1", 1, true), snap)
                    ctl.ViewerAura(ti, "target") -- any visible light re-proves it and zeroes the count
                    poll(21.2)
                    assert.are.same(
                        { true, 0, 32 },
                        { Q.proven[502], Q.silent[502], est("target", fs.SPENDER_C, 21.2) }
                    )
                    poll(21.8)
                    ctl.ViewerClear(ti)
                    poll(22) -- rule 1 (it was seen lit)
                    assert.is_nil(VS.Aura("target", fs.SPENDER_C, 22))
                    cast(2, REND, 24, 15) -- silent again: judged again
                    poll(24.5)
                    assert.are.equal(39, est("target", fs.SPENDER_C, 24.5))
                    poll(25)
                    assert.is_nil(VS.Aura("target", fs.SPENDER_C, 25))
                    assert.are.same({ 3, 1, true }, { I.auraVerdict.n[kT()], Q.silent[502], Q.proven[502] })
                end
            )

            it("F52-C (review S1): a player item's frame re-pointed, dark for one sweep, closes nothing", function()
                cast(1, SHOUT, 10.1, 120)
                ctl.ViewerAura(pi, "player")
                poll(10.2)
                poll(10.8) -- upAt >= oursAp + REFRESH_LAG: a NONE would close by rule 1
                ctl.ViewerRelease(pi) -- the reshuffle: 501 shows on a new frame, dark at its first sweep
                local pi2 = ctl.ViewerItem("BuffIconCooldownViewer", 3, 501)
                poll(11.0)
                assert.are.equal(130.1, est("player", fs.SPENDER_A, 11.0)) -- no inherited seen memory: no NONE
                assert.are.equal(0, I.auraVerdict.n[SHOUT])
                ctl.ViewerAura(pi2, "player")
                poll(11.2)
                assert.are.same({ 130.1, 1 }, { est("player", fs.SPENDER_A, 11.2), I.auraOurs[SHOUT] })
            end)

            it("the verdict off switch", function()
                I.verdictOff = true
                prove()
                cast(2, REND, 11, 15)
                for t = 11.5, 14, 0.5 do
                    poll(t)
                    assert.are.equal(26, est("target", fs.SPENDER_C, t), t)
                end
            end)

            it("a seen-rule close and the verdict never both stage", function()
                prove()
                cast(2, REND, 11, 15)
                ctl.ViewerAura(ti, "target")
                for t = 11.1, 12, 0.3 do
                    poll(t)
                end
                ctl.ViewerClear(ti)
                for t = 12.2, 14, 0.2 do
                    poll(t)
                end
                assert.is_nil(VS.Aura("target", fs.SPENDER_C, 12.2)) -- rule 1 at the first silent sweep
                assert.are.equal(0, I.auraVerdict.n[kT()]) -- the verdict found the record closed
            end)

            it("out of combat the plain walk wins", function()
                prove()
                cast(2, REND, 11, 15)
                ctl.Fire("PLAYER_REGEN_ENABLED")
                ctl.auras.target.HARMFUL[1] =
                    { spellId = fs.SPENDER_C, expirationTime = 26, applications = 0, sourceUnit = "player" }
                ctl.Fire("UNIT_AURA", "target")
                for t = 11.5, 14, 0.5 do
                    poll(t)
                    assert.are.equal(26, est("target", fs.SPENDER_C, t), t)
                end
                assert.are.equal(0, I.auraVerdict.n[kT()])
            end)

            it("a player form aura is skipped", function()
                ctl.ViewerAura(pi, "player") -- proven, opened by the CDM, closed by its silence
                poll(10.2)
                ctl.ViewerClear(pi)
                poll(10.5)
                I.formAura[SHOUT] = true -- Sources/Forms.lua's record
                cast(1, SHOUT, 11, 120)
                for t = 11.5, 14, 0.5 do
                    poll(t)
                    assert.are.equal(131, est("player", fs.SPENDER_A, t), t)
                end
                I.formAura[SHOUT] = false -- control: judged
                poll(14.5)
                assert.is_nil(VS.Aura("player", fs.SPENDER_A, 14.5))
            end)
        end)

        it(
            "D14: a refresh the item does not light closes nothing; one it holds past the lag closes at its end",
            function()
                I.verdictOff = true -- rule 1 alone: a proven item dark W past the refresh is the verdict's (§2.7)
                cast(1, SHOUT, 10, 120)
                ctl.ViewerAura(pi, "player")
                poll(10.5)
                poll(11)
                cast(1, SHOUT, 20, 120) -- our refresh before expiry: applied 20, expires 140
                poll(20.1) -- the item still holds the old application (the client's update not in yet)
                ctl.ViewerClear(pi) -- and it does not light the new one (an item that stops following)
                for t = 20.3, 22, 0.3 do
                    poll(t)
                    assert.are.equal(140, est("player", fs.SPENDER_A, t))
                end
                assert.are.equal(I.DOWN, P.Presence(SHOUT, 1)) -- the reduced NONE; the refresh guard keeps it open
                cast(1, SHOUT, 30, 120)
                ctl.ViewerAura(pi, "player")
                poll(30.1)
                poll(30.6) -- held past the refresh lag: it follows this application
                ctl.ViewerClear(pi)
                poll(31)
                assert.is_nil(VS.Aura("player", fs.SPENDER_A, 31)) -- control
            end
        )

        it(
            "an UP while believed up stages nothing; UNKNOWN leaves the record; an item flap never takes it down",
            function()
                cast(1, SHOUT, 10, 120)
                ctl.ViewerAuraBySpell("player", fs.SPENDER_A, true, "player")
                for t = 10.5, 12, 0.5 do
                    poll(t)
                    assert.are.equal(130, est("player", fs.SPENDER_A, t))
                end
                ctl.ViewerRemove("BuffIconCooldownViewer", pi) -- removed while up (F13): UNKNOWN
                poll(12.5)
                assert.are.equal(I.UNDECIDED, P.Presence(SHOUT, 1))
                assert.are.equal(130, est("player", fs.SPENDER_A, 12.5))
                ctl.ViewerAcquire("BuffIconCooldownViewer", 501) -- re-added: a new frame, lit at once
                poll(13)
                assert.are.equal(I.UP, P.Presence(SHOUT, 1))
                assert.are.equal(130, est("player", fs.SPENDER_A, 13))
            end
        )

        it("a form or enchant aura on the player is never written by the facts (M5)", function()
            I.formAura[SHOUT] = true
            ctl.ViewerAura(pi, "player")
            poll(10.5)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 10.5))
            I.formAura[SHOUT] = nil
            I.enchantAura[SHOUT] = 1
            poll(11)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 11))
        end)

        it("the floor: I.auraFloor[j] is 1 while the player fact is UP, else 0", function()
            assert.are.equal(0, I.auraFloor[SHOUT])
            ctl.ViewerAura(pi, "player")
            ctl.ViewerAura(ti, "target")
            poll(10.5)
            assert.are.same({ 1, 0 }, { I.auraFloor[SHOUT], I.auraFloor[REND] }) -- a target UP is no floor
            ctl.ViewerRelease(pi)
            poll(11)
            assert.are.equal(0, I.auraFloor[SHOUT]) -- UNKNOWN
            ctl.ViewerAcquire("BuffIconCooldownViewer", 501)
            ctl.ViewerAura(ctl.viewer.items.BuffIconCooldownViewer[3], "player")
            poll(11.5)
            assert.are.equal(1, I.auraFloor[SHOUT])
            ctl.viewer.parentShown = false -- every viewer hidden: no live slot, covered 0
            poll(12)
            assert.are.equal(0, I.auraFloor[SHOUT])
        end)

        describe("the floor read by the hit consumer (decision 114, Task 4c)", function()
            local function hit(t)
                S.Direct(Obs.PlayerHit, t, I.HitKind.BLOCK, 0, 20)
                I.Fold(t, false)
            end
            -- Our cast of the 3-charge shield at t (600 s).
            local function shield(t)
                I.AuraModel(1, SHOUT, t, t + 600, 3, t, Obs.CastSuccess, false)
                I.AuraOurs(1, SHOUT)
            end
            local function stacks(t)
                return (select(2, VS.Aura("player", fs.SPENDER_A, t)))
            end

            before_each(function()
                local def = fs.def(fs.new(9))
                def.auras[SHOUT] =
                    { key = "spender_a", id = fs.SPENDER_A, max_stack = 3, consumedBy = { BLOCK = true } }
                start(def)
            end)

            it("the fact UP: three hits leave ONE stack; the fact DOWN, the silent item closes it (rule 1)", function()
                shield(10)
                ctl.ViewerAura(pi, "player")
                poll(10.5)
                poll(11)
                assert.are.equal(1, I.auraFloor[SHOUT])
                hit(11.1)
                hit(11.2)
                assert.are.equal(1, stacks(11.2))
                hit(11.3) -- the hit that would spend the last charge: the item is still lit
                hit(11.4)
                assert.are.same({ 610, 1 }, { est("player", fs.SPENDER_A, 11.4), stacks(11.4) })
                poll(11.5)
                assert.are.same({ 610, 1 }, { est("player", fs.SPENDER_A, 11.5), stacks(11.5) })
                ctl.ViewerClear(pi) -- the game spent the last charge: the item goes silent
                poll(12)
                assert.are.equal(0, I.auraFloor[SHOUT])
                assert.is_nil(VS.Aura("player", fs.SPENDER_A, 12))
            end)

            it("the fact not UP (unknown, DOWN): the third hit closes it as before", function()
                shield(10)
                poll(10.5) -- its item never lit: UNKNOWN
                assert.are.same({ I.UNDECIDED, 0 }, { P.Presence(SHOUT, 1), I.auraFloor[SHOUT] })
                hit(10.6)
                hit(10.7)
                assert.are.equal(1, stacks(10.7))
                hit(10.8)
                assert.is_nil(VS.Aura("player", fs.SPENDER_A, 10.8))
                shield(11)
                ctl.ViewerAura(pi, "player")
                poll(11.5)
                poll(12)
                shield(20) -- our refresh; the item goes silent inside the refresh lag: DOWN, the record stays (D14)
                poll(20.1)
                ctl.ViewerClear(pi)
                poll(20.3)
                assert.are.same({ I.DOWN, 0 }, { P.Presence(SHOUT, 1), I.auraFloor[SHOUT] })
                assert.are.equal(3, stacks(20.3))
                hit(20.4)
                hit(20.5)
                hit(20.6)
                assert.is_nil(VS.Aura("player", fs.SPENDER_A, 20.6))
            end)
        end)

        it("out of combat, a walk turning plain then secret again leaves no stale staged read (L281)", function()
            ctl.now = 10
            ctl.Fire("PLAYER_REGEN_ENABLED")
            ctl.Fire("UNIT_AURA", "player") -- out of combat, still secret
            ctl.ViewerAura(pi, "player")
            poll(10.2)
            assert.is_true(math.abs(est("player", fs.SPENDER_A, 10.2) - 130.2) < 1e-9)
            ctl.auras.player.HELPFUL[1] = nil
            ctl.Fire("UNIT_AURA", "player") -- plain: the walk shows it gone, and wins
            poll(10.4)
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 10.4))
            ctl.auras.player.HELPFUL[1] = fake.SECRET
            ctl.Fire("UNIT_AURA", "player")
            poll(10.6)
            assert.is_truthy(VS.Aura("player", fs.SPENDER_A, 10.6)) -- staged again, not blocked by the old mark
        end)

        it("allocates nothing over 1000 polls of the rules: ours, the hold, closes and re-opens, the floor", function()
            local alloc = require("Game.State.helpers.alloc")
            cast(1, SHOUT, 10, 120)
            cast(2, REND, 10, 15)
            local t = 10
            assert.are.equal(
                0,
                alloc.bytes(function(i)
                    t = t + 0.1
                    -- the items' fields directly (ctl.ViewerAura logs its writes: the fake's allocation)
                    local on = i % 20 < 15
                    pi.auraInstanceID, pi.auraDataUnit = on and fake.SECRET or nil, on and "player" or nil
                    ti.auraInstanceID, ti.auraDataUnit = on and fake.SECRET or nil, on and "target" or nil
                    if i % 40 == 1 then
                        I.AuraOurs(1, SHOUT)
                    end
                    S.RunPolls(t)
                    I.Fold(t, false)
                    I.Settle(t)
                end, 1000)
            )
        end)

        it("the snapshot's CDM section: per thing and one summary line, each under 255 characters", function()
            ctl.viewer.sets[0] = { 600, 700 }
            ctl.viewer.infos[600] = { spellID = fs.SPENDER_A } -- a cooldown entry for the same aura
            ctl.viewer.infos[700] = { spellID = 9999, linkedSpellIDs = { fs.SPENDER_A, 9998 } } -- ambiguous
            ctl.viewer.sets[1] = { 800 }
            ctl.viewer.infos[800] = { spellID = 9997 } -- unmapped
            local e = ctl.ViewerItem("EssentialCooldownViewer", 1, 600)
            local amb = ctl.ViewerItem("EssentialCooldownViewer", 2, 700)
            ctl.ViewerItem("UtilityCooldownViewer", 1, 800)
            start(fs.def(fs.new(9)))
            ctl.ViewerAura(pi, "player")
            ctl.ViewerAura(e, "player")
            ctl.ViewerAura(amb, "player")
            poll(10.5)
            local snap = VS.Snapshot()
            assert.is_truthy(
                snap:find(
                    "presence spender_a unit=player fact=up from=viewer n=2 via=EB agree=true ours=cdm facts=1"
                        .. " beliefDisagree=1 itemDisagree=0 ambiguous=1 lost=0 exitFix=0",
                    1,
                    true
                ),
                snap
            )
            assert.is_truthy(snap:find("presence covered=1/2 unmapped=1 ambiguous=1 overflow=0 leaf=on", 1, true), snap)
            for line in snap:gmatch("[^\n]+") do
                assert.is_true(#line < 255, line)
            end
            P.onEdge = function()
                error("a belief handler raised")
            end
            ctl.ViewerClear(pi)
            ctl.ViewerClear(e)
            poll(11)
            assert.is_truthy(VS.Snapshot():find("leaf=off(error", 1, true))
        end)
    end)
end)
