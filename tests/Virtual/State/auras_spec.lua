-- tests/Virtual/State/auras_spec.lua: the auras family and source (spec §4.5, §6.3).
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")
local fs = require("Virtual.State.helpers.fake_spec")

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

    describe("an aura spent by hits on the player (`consumedBy`, tank design §3)", function()
        local BLOCKED, BLOCK, DODGE = 2, 3, 4

        local function hit(t, kind)
            S.Direct(Obs.PlayerHit, t, kind, 0, 20)
            I.Fold(t, false)
        end

        before_each(function()
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
            hit(18, BLOCK) -- past the shout's expiry
            assert.is_nil(VS.Aura("player", fs.SPENDER_A, 18))
        end)

        it("allocates nothing over 1000 hits", function()
            local alloc = require("Virtual.State.helpers.alloc")
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
end)
