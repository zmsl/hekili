-- tests/Game/State/target_health_spec.lua: the target health family (target-health design, 2026-10-16, §6). A
-- health-gated spender's flip pins the target's health at its gate and teaches M (the damage per full health) on a
-- target never held before; the guards keep a NOT from bounding it; WOUND damage moves it between answers, sampled only
-- from an anchor (R5); the resets. No time to die (dropped by the user, 2026-10-16).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")

local function within(want, got, tol)
    assert.is_true(math.abs(want - got) <= (tol or 1e-9), ("want %s, got %s"):format(want, got))
end

-- A gated spender (Smite: 15 rage, usable at or below 20%, not while Stance is up) and an ungated one; rage, no regen.
local SMITE, SLAM, STANCE = 2001, 2002, 3001
local GATED = 1 -- Smite's ability index
local OVER = 0.2 + 1e-6 -- a guarded NOT's bound: strictly over the gate

local function def()
    return {
        abilities = {
            { key = "smite", spend = 15, healthGate = 0.2, nobuff = "stance" },
            { key = "slam", spend = 10 },
        },
        abilityIds = { { SMITE }, { SLAM } },
        abilitySlot = { 1, 1 },
        resources = { { key = "rage", type = 1, token = "RAGE", max = 100, rest = false } },
        auras = { { key = "stance", id = STANCE } },
        auraIds = { { STANCE } },
        talents = {},
        units = { "player", "target" },
    }
end

describe("target health", function()
    local ns, VS, I, S, Obs, ReadOf, api, ctl

    before_each(function()
        api, ctl = fake.new()
        local getTime = rawget(_G, "GetTime") -- the facade resolves its clock at load
        _G.GetTime = api.GetTime
        ns = load.module()
        _G.GetTime = getTime
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs, ReadOf = I.Sources, VS.Obs, I.ReadOf
        ctl.known[SMITE], ctl.known[SLAM] = true, true
        I.api = api
        I.Build(def(), 1) -- the build's swap: Creature-1 takes slot 1, never held before, attackable
    end)

    local function obs(kind, t, a, b, c)
        S.Direct(kind, t, a, b, c)
    end

    -- 50 rage, 800 damage taken at 3, a guarded NOT at 9, then the flip at 10: health 0.2, M = 800 / (1 - 0.2).
    local function anchor()
        obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
        obs(Obs.TargetDamage, 3, 0, 800)
        obs(Obs.Usable, 9, GATED, 0, 0)
        obs(Obs.Usable, 10, GATED, 1, 0)
        I.Fold(10)
    end

    it("pins the health at the gate on a flip and learns M on a target never held before", function()
        anchor()
        local h = VS.Health("target", 10)
        assert.are.same({ 0.2, 0.2, 0.2, "pinned" }, { h.est, h.lo, h.hi, h.basis })
        within(1000, I.th.M, 1e-6)
    end)

    it("takes no bound from a NOT while the cost is believed unaffordable, nor from a short answer", function()
        obs(Obs.Read, 2, 1, 5, ReadOf.Resource) -- 5 rage: Smite's 15 believed unaffordable
        obs(Obs.Usable, 9, GATED, 0, 0)
        obs(Obs.Usable, 9.5, GATED, 0, 1) -- short (c = 1): no health signal until design §7 line 4 says so
        I.Fold(9.5)
        local h = VS.Health("target", 9.5)
        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })
        obs(Obs.Usable, 10, GATED, 1, 0) -- usable after the short: a bound at the gate, not a flip
        I.Fold(10)
        h = VS.Health("target", 10)
        assert.are.same({ 0.2, 0, 0.2, "pinned", 0 }, { h.est, h.lo, h.hi, h.basis, I.th.M })
    end)

    it("takes no bound from a NOT while the guard aura is believed up", function()
        obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
        obs(Obs.Read, 2, 1, 3600, ReadOf.Aura + I.AURA_STACK) -- Stance up on the player (unit 1, aura 1), 1 stack
        obs(Obs.Usable, 9, GATED, 0, 0)
        I.Fold(9)
        local h = VS.Health("target", 9)
        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })
        obs(Obs.Usable, 10, GATED, 1, 0) -- no guarded NOT before it: a bound at the gate, not a flip
        I.Fold(10)
        h = VS.Health("target", 10)
        assert.are.same({ 0.2, 0, 0.2, 0 }, { h.est, h.lo, h.hi, I.th.M })
    end)

    it("takes no bound from a NOT while the guard stance is up through the form reads (Sources/Forms.lua)", function()
        ctl.forms, ctl.form = { STANCE }, 1 -- a stance: a shapeshift form the aura walk never lists
        S.RunPolls(2) -- the first poll after build reads the forms
        obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
        obs(Obs.Usable, 9, GATED, 0, 0)
        I.Fold(9)
        assert.are.equal(math.huge, VS.Aura("player", STANCE, 9).est)
        local h = VS.Health("target", 9)
        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })
    end)

    it("takes no bound from a NOT under an untracked guard aura, and one under `buff` only while it is up", function()
        local d = def()
        d.abilities[GATED].nobuff, d.abilities[GATED].buff = nil, "ghost" -- named but untracked: index -1
        I.Build(d, 1)
        obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
        obs(Obs.Usable, 9, GATED, 0, 0)
        I.Fold(9)
        local h = VS.Health("target", 9)
        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })

        d = def()
        d.abilities[GATED].nobuff, d.abilities[GATED].buff = nil, "stance" -- usable only while Stance is up
        I.Build(d, 1)
        obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
        obs(Obs.Usable, 9, GATED, 0, 0) -- Stance down: unguarded
        I.Fold(9)
        h = VS.Health("target", 9)
        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })
        obs(Obs.Read, 9.5, 1, 3600, ReadOf.Aura + I.AURA_STACK) -- Stance up
        obs(Obs.Usable, 10, GATED, 0, 0) -- guarded: above the gate
        I.Fold(10)
        h = VS.Health("target", 10)
        within(0.2 + I.EPS, h.lo)
        assert.are.same({ 1, 1 }, { h.est, h.hi }) -- est already above the gate: bounded, no sample
    end)

    it("takes no bound from a NOT while the gated ability is not known", function()
        ctl.known[SMITE] = false
        I.Build(def(), 1)
        anchor() -- the NOT at 9 is unguarded, so the usable at 10 is a bound at the gate, not a flip
        local h = VS.Health("target", 10)
        assert.are.same({ 0.2, 0, 0.2, 0 }, { h.est, h.lo, h.hi, I.th.M })
    end)

    it("takes no bound from a NOT while the target is not attackable", function()
        obs(Obs.TargetSwap, 1, 1, 0, 0) -- slot 1, held before, not attackable
        obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
        obs(Obs.Usable, 9, GATED, 0, 0)
        I.Fold(9)
        local h = VS.Health("target", 9)
        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })
        obs(Obs.Usable, 10, GATED, 1, 0)
        I.Fold(10)
        h = VS.Health("target", 10)
        assert.are.same({ 0.2, 0, 0.2, 0 }, { h.est, h.lo, h.hi, I.th.M })
    end)

    it("moves the health by WOUND damage over M from a pin on a target never held before", function()
        anchor()
        obs(Obs.TargetDamage, 11, 0, 50)
        obs(Obs.TargetDamage, 12, 0, 50)
        I.Fold(12)
        local h = VS.Health("target", 12)
        within(0.1, h.est, 1e-6)
        within(0.1, h.lo, 1e-6)
        within(0.1, h.hi, 1e-6)
        assert.are.equal("modelled", h.basis)
    end)

    it("keeps a live target at the floor and reads a dead one as 0, observed", function()
        anchor()
        obs(Obs.TargetDamage, 11, 0, 500)
        I.Fold(11)
        local h = VS.Health("target", 11)
        assert.are.same({ 0.02, 0.02, 0.02, "modelled" }, { h.est, h.lo, h.hi, h.basis })
        obs(Obs.TargetGone, 12, 1)
        I.Fold(12)
        h = VS.Health("target", 12)
        assert.are.same({ 0, 0, 0, "observed" }, { h.est, h.lo, h.hi, h.basis })
    end)

    it("starts a new target over at the default and keeps M for a target swapped back to", function()
        anchor()
        VS.Start(api) -- the start's swap at 100: Creature-1 keeps slot 1 (held before)
        ctl.guid.target = "Creature-2"
        api.UnitCanAttack = function()
            return false
        end
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 70, 1)
        I.Fold(100)
        -- M unknown on the new target: its WOUND moves nothing
        local h = VS.Health("target", 100)
        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })
        assert.are.same({ 2, true, false, 70, 0 }, { I.th.slot, I.th.fresh, I.th.attackable, I.th.dmg, I.th.M })
        ctl.now = 101
        ctl.guid.target = "Creature-1"
        ctl.Fire("PLAYER_TARGET_CHANGED")
        I.Fold(101)
        assert.are.same({ 1, false, 0, "default" }, { I.th.slot, I.th.fresh, I.th.dmg, VS.Health("target", 101).basis })
        within(1000, I.th.M, 1e-6)
    end)

    it("writes no modelled sample after a swap back to a known slot until a pin", function()
        anchor() -- M 1000 on slot 1
        obs(Obs.TargetSwap, 11, 2, 1, 1) -- slot 2, never held before
        obs(Obs.TargetSwap, 12, 1, 0, 1) -- back to slot 1: M kept, no anchor
        obs(Obs.TargetDamage, 13, 0, 100)
        I.Fold(13)
        assert.are.same({ 1000, false, "default" }, { I.th.M, I.th.anchored, VS.Health("target", 13).basis })
        within(0.9, I.th.est0, 1e-6) -- the damage still moves the interval
        obs(Obs.Read, 14, 1, 50, ReadOf.Resource)
        obs(Obs.Usable, 14, GATED, 1, 0) -- a rung: the health at or below the gate, an anchor
        obs(Obs.TargetDamage, 15, 0, 100)
        I.Fold(15)
        local h = VS.Health("target", 15)
        assert.are.equal("modelled", h.basis)
        within(0.1, h.est, 1e-6)
    end)

    it("takes no anchor from a guarded NOT after a swap back to a known slot", function()
        anchor() -- M 1000 on slot 1
        obs(Obs.TargetSwap, 11, 2, 1, 1)
        obs(Obs.TargetSwap, 12, 1, 0, 1) -- back to slot 1: no anchor
        obs(Obs.Read, 13, 1, 50, ReadOf.Resource)
        obs(Obs.Usable, 13, GATED, 0, 0) -- guarded: a bound above the gate, not an anchor
        obs(Obs.TargetDamage, 14, 0, 100)
        I.Fold(14)
        assert.are.same({ false, "default" }, { I.th.anchored, VS.Health("target", 14).basis })
    end)

    it("takes no anchor from a rung that does not move the estimate", function()
        anchor() -- M 1000 on slot 1
        obs(Obs.TargetSwap, 11, 2, 1, 1)
        obs(Obs.TargetSwap, 12, 1, 0, 1) -- back to slot 1: no anchor
        obs(Obs.TargetDamage, 13, 0, 850) -- the estimate to 0.15, below the gate
        obs(Obs.Usable, 14, GATED, 1, 0) -- a rung at 0.2: the estimate stays, no anchor
        obs(Obs.TargetDamage, 15, 0, 10)
        I.Fold(15)
        assert.are.same({ false, "default" }, { I.th.anchored, VS.Health("target", 15).basis })
        within(0.14, I.th.est0, 1e-6)
    end)

    it("credits a WOUND fired before a same-frame target swap to the old target", function()
        local seen = {}
        I.On(Obs.TargetDamage, function()
            seen[#seen + 1] = { I.th.slot, I.th.dmg }
        end)
        VS.Start(api)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 70, 1)
        ctl.guid.target = "Creature-2"
        ctl.Fire("PLAYER_TARGET_CHANGED") -- the same frame: no tick between
        I.Fold(100)
        assert.are.same({ { 1, 70 } }, seen)
        assert.are.same({ 2, 0 }, { I.th.slot, I.th.dmg })
    end)

    it("starts a live target over full at combat end, an anchor", function()
        anchor()
        obs(Obs.TargetDamage, 11, 0, 100)
        obs(Obs.CombatEnd, 12)
        I.Fold(12)
        local h = VS.Health("target", 12)
        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })
        assert.are.same({ 0, true, false }, { I.th.dmg, I.th.anchored, I.th.fresh })
        obs(Obs.TargetDamage, 13, 0, 100)
        I.Fold(13)
        h = VS.Health("target", 13)
        assert.are.equal("modelled", h.basis)
        within(0.9, h.est, 1e-6)
    end)

    it("counts only the target's WOUNDs", function()
        VS.Start(api)
        ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 70, 1)
        ctl.Fire("UNIT_COMBAT", "target", "HEAL", "", 70, 1)
        I.Fold(100)
        assert.are.equal(0, I.th.dmg)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 70, 1)
        I.Fold(100)
        assert.are.equal(70, I.th.dmg)
    end)

    it("forgets a slot's M on its TargetGone without touching the current target", function()
        anchor() -- M 1000 on slot 1
        obs(Obs.TargetSwap, 11, 2, 1, 1)
        I.Fold(11)
        assert.are.equal(1000, math.floor(I.th.maxBy[1] + 0.5))
        obs(Obs.TargetGone, 12, 1)
        I.Fold(12)
        assert.are.same(
            { 0, 2, false, "default" },
            { I.th.maxBy[1], I.th.slot, I.th.dead, VS.Health("target", 12).basis }
        )
        obs(Obs.TargetSwap, 13, 1, 0, 1)
        I.Fold(13)
        assert.are.equal(0, I.th.M)
    end)

    -- LibHiddenValues lane B2 (integration design 2.3, 2.6): the target's band, Obs.Band channel -1 in fractions, as
    -- Sources/Bands.lua's poll logs it (its I.bandT/Lo/Hi/Live first, then the observation; lo nil: the unknown).
    describe("from the hidden-value band (lane B2)", function()
        local function band(t, lo, hi)
            if lo then
                I.bandT[-1], I.bandLo[-1], I.bandHi[-1], I.bandLive[-1] = t, lo, hi, true
                obs(Obs.Band, t, -1, lo, hi)
            else
                I.bandLive[-1] = false
                obs(Obs.Band, t, -1, 1, 0)
            end
        end

        it("counts bandDisagree only for a value more than one cell outside a live band (L1666 h)", function()
            obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
            band(9, 0.21, 0.22)
            obs(Obs.Usable, 9, GATED, 1, 0) -- usable: at or below 0.2, one cell under the band
            I.Fold(9)
            I.Settle(9)
            assert.are.equal(0, I.bandDisagree[-1])
            band(10, 0.25, 0.26)
            obs(Obs.Usable, 10, GATED, 1, 0) -- 0.2: more than a cell under it
            I.Fold(10)
            I.Settle(10)
            assert.are.equal(1, I.bandDisagree[-1])
            -- a power band in points, one cell = max / 100 (rage: 1 point)
            I.bandT[1], I.bandLo[1], I.bandHi[1], I.bandLive[1] = 10, 51, 52, true
            I.Settle(10)
            assert.are.equal(0, I.bandDisagree[1]) -- 50 against 51-52: one cell
            I.bandLo[1], I.bandHi[1] = 52, 53
            I.Settle(10)
            assert.are.equal(1, I.bandDisagree[1])
        end)

        it(
            "applies a live band: its interval, its middle, an anchor, observed; M kept; no memory slot needed",
            function()
                anchor() -- M 1000 on slot 1
                band(11, 0.63, 0.64) -- healed: the flip's bound was of its own drain, it caps no later band (L1675)
                I.Fold(11)
                local h = VS.Health("target", 11)
                within(0.635, h.est)
                assert.are.same({ 0.63, 0.64, "observed", true }, { h.lo, h.hi, h.basis, I.th.anchored })
                within(1000, I.th.M, 1e-6)
                assert.are.same({ 1, 0.63, 0.64 }, { I.bandUsed[-1], I.bandUsedLo[-1], I.bandUsedHi[-1] })
                obs(Obs.TargetSwap, 12, 0, 0, 1) -- no memory slot (the map lockdown: no plate answers)
                band(12.2, 0.4, 0.41)
                I.Fold(12.2)
                within(0.405, VS.Health("target", 12.2).est)
            end
        )

        it("a swap starts over at full, nothing low while the library primes, then the new band", function()
            band(2, 0.63, 0.64)
            I.Fold(2)
            obs(Obs.TargetSwap, 3, 2, 1, 1) -- a new target, never held before
            band(3) -- the library primes: one unknown
            I.Fold(3)
            local h = VS.Health("target", 3)
            assert.are.same({ 1, 0, 1, "default", true }, { h.est, h.lo, h.hi, h.basis, I.th.anchored })
            I.Fold(3.1) -- priming: nothing logged
            assert.are.equal(1, VS.Health("target", 3.1).est)
            band(3.2, 0.19, 0.2)
            I.Fold(3.2)
            within(0.195, VS.Health("target", 3.2).est)
        end)

        it("a usable answer wins: a contradicting band is clipped for that drain, counted (L1675)", function()
            obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
            band(9, 0.15, 0.16)
            obs(Obs.Usable, 9, GATED, 1, 0) -- at or below 0.2: agrees, the band narrows it
            I.Fold(9)
            I.Settle(9)
            local h = VS.Health("target", 9)
            within(0.155, h.est)
            assert.are.same({ 0.15, 0.16, 0 }, { h.lo, h.hi, I.bandDisagree[-1] })
            band(10, 0.25, 0.26) -- a band from before the drop (its stamp lags) against the client's own gate
            obs(Obs.Usable, 10, GATED, 1, 0)
            I.Fold(10)
            I.Settle(10)
            h = VS.Health("target", 10)
            assert.are.same({ 0.2, 0.2, 0.2, 1 }, { h.lo, h.hi, h.est, I.bandDisagree[-1] })
            band(11, 0.25, 0.26) -- the next drain's band, no answer in it: the bound was of the last one
            I.Fold(11)
            I.Settle(11)
            h = VS.Health("target", 11)
            assert.are.same({ 0.25, 0.26, 1 }, { h.lo, h.hi, I.bandDisagree[-1] })
            within(0.255, h.est)
            band(12, 0.15, 0.16)
            obs(Obs.Usable, 12, GATED, 0, 0) -- a guarded NOT (above 0.2) against 0.15-0.16: clipped up to gate + 1e-6
            I.Fold(12)
            I.Settle(12)
            h = VS.Health("target", 12)
            assert.are.same({ OVER, OVER, OVER, 2 }, { h.lo, h.hi, h.est, I.bandDisagree[-1] })
        end)

        it("a flip pins the gate against a lagging band and teaches M; the next band narrows under it", function()
            obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
            obs(Obs.TargetDamage, 3, 0, 800)
            obs(Obs.Usable, 9, GATED, 0, 0) -- guarded NOT: above 0.2
            I.Fold(9)
            band(10, 0.25, 0.26)
            obs(Obs.Usable, 10, GATED, 1, 0) -- a flip at 0.2 against 0.25-0.26
            I.Fold(10)
            local h = VS.Health("target", 10)
            assert.are.same({ 0.2, 0.2, 0.2 }, { h.lo, h.hi, h.est })
            within(1000, I.th.M, 1e-6)
            band(11, 0.18, 0.19) -- the band catches up
            obs(Obs.Usable, 11, GATED, 1, 0) -- poll 2 re-asserts: at or below 0.2, no flip
            I.Fold(11)
            h = VS.Health("target", 11)
            within(0.185, h.est)
            assert.are.same({ 0.18, 0.19 }, { h.lo, h.hi })
        end)

        it("death wins: a corpse's band is ignored until the next swap", function()
            band(2, 0.05, 0.06)
            I.Fold(2)
            obs(Obs.TargetGone, 3, 1)
            band(3, 0, 0.01) -- the library keeps the lowest band on a corpse (dungeon restrictions)
            I.Fold(3)
            local h = VS.Health("target", 3)
            assert.are.same({ 0, 0, 0, "observed", 1 }, { h.est, h.lo, h.hi, h.basis, I.bandUsed[-1] })
            obs(Obs.TargetSwap, 4, 2, 1, 1)
            band(4.2, 0.5, 0.51)
            I.Fold(4.2)
            within(0.505, VS.Health("target", 4.2).est)
        end)

        it("the unknown drops the band: [0, 1] and the gates' bounds stand; M and the damage kept", function()
            anchor() -- M 1000, 800 damage
            band(11, 0.15, 0.16)
            I.Fold(11)
            band(12)
            obs(Obs.Usable, 12, GATED, 1, 0) -- the gate's bound, as poll 2 re-asserts it
            I.Fold(12)
            local h = VS.Health("target", 12)
            assert.are.same({ 0.2, 0, 0.2, "pinned" }, { h.est, h.lo, h.hi, h.basis })
            assert.are.same({ 800 }, { I.th.dmg })
            within(1000, I.th.M, 1e-6)
            band(13) -- a second unknown with no band held: nothing
            I.Fold(13)
            assert.are.equal("pinned", VS.Health("target", 13).basis)
        end)

        it("a live target never reads under the floor (Targets.lua's UnitHealth > 1 scan)", function()
            band(2, 0, 0.01)
            I.Fold(2)
            local h = VS.Health("target", 2)
            assert.are.same({ I.TARGET_HEALTH_FLOOR, 0, I.TARGET_HEALTH_FLOOR }, { h.est, h.lo, h.hi }) -- never outside it
        end)

        local function reads(t, est, lo, hi)
            local h = VS.Health("target", t)
            within(est, h.est)
            within(lo, h.lo)
            within(hi, h.hi)
            return h
        end
        -- One drain: the band, the gated ability's answer (none: it read secret), the fold.
        local function drain(t, lo, hi, ok, short)
            band(t, lo, hi)
            if ok ~= nil then
                obs(Obs.Usable, t, GATED, ok, short or 0)
            end
            I.Fold(t)
        end

        describe("a usable bound lives for its drain (fix round 1, review B1)", function()
            before_each(function()
                obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
            end)

            it("a lower bound goes with a short answer, a NOT the aura explains, or no answer (probe A)", function()
                drain(3, 0.25, 0.26, 0)
                reads(3, 0.255, 0.25, 0.26)
                drain(4, 0.15, 0.16, 0, 1) -- short
                reads(4, 0.155, 0.15, 0.16)
                drain(5, 0.25, 0.26, 0)
                drain(6, 0.1, 0.11) -- no answer at all
                reads(6, 0.105, 0.1, 0.11)
                drain(7, 0.25, 0.26, 0)
                obs(Obs.Read, 8, 1, 3600, ReadOf.Aura + I.AURA_STACK)
                drain(8, 0.05, 0.06, 0) -- the stance: no bound
                reads(8, 0.055, 0.05, 0.06)
            end)

            it("an upper bound goes with the next band: a heal shows (probe B)", function()
                drain(3, 0.15, 0.16, 1)
                drain(4, 0.6, 0.61, 0, 1) -- short
                reads(4, 0.605, 0.6, 0.61)
                drain(5, 0.15, 0.16, 1)
                drain(6, 0.9, 0.91) -- no answer
                reads(6, 0.905, 0.9, 0.91)
            end)

            it("an answer from before the first band does not outlast it (probe B2)", function()
                obs(Obs.Usable, 3, GATED, 1, 0)
                I.Fold(3)
                drain(90, 0.7, 0.71, 0, 1)
                reads(90, 0.705, 0.7, 0.71)
            end)

            it(
                "through the poll: short under the gate follows the band, a current answer still wins (probe M)",
                function()
                    local function poll(t, health, power)
                        local low = health <= 0.2
                        ctl.usable[SMITE] = { low and power >= 15, low and power < 15 }
                        obs(Obs.Read, t, 1, power, ReadOf.Resource)
                        local cell = math.floor(health * 100) / 100
                        band(t, cell, cell + 0.01)
                        S.RunPolls(t)
                        I.Fold(t)
                    end
                    poll(20, 0.215, 50) -- NOT
                    reads(20, 0.215, 0.21, 0.22)
                    poll(21, 0.184, 0) -- short
                    reads(21, 0.185, 0.18, 0.19)
                    poll(25, 0.105, 0)
                    reads(25, 0.105, 0.1, 0.11)
                    poll(50, 0.004, 0)
                    reads(50, 0.02, 0, 0.02)
                    ctl.usable[SMITE] = { true, false } -- usable against a band that lags over the gate
                    band(51, 0.25, 0.26)
                    S.RunPolls(51)
                    I.Fold(51)
                    reads(51, 0.2, 0.2, 0.2)
                end
            )

            it("a NOT yields only a side it contradicts: the gate + 1e-6, not a cell over it (probe C)", function()
                drain(3, 0.2, 0.21, 0)
                reads(3, 0.205, OVER, 0.21)
            end)

            it("a usable after a NOT of the same drain voids its bound", function()
                band(3, 0.15, 0.16)
                obs(Obs.Usable, 3, GATED, 0, 0)
                obs(Obs.Usable, 3, GATED, 1, 0)
                I.Fold(3)
                reads(3, 0.155, 0.15, 0.16)
            end)

            it("a flip clips by the usable side alone, and still teaches M (probe D)", function()
                obs(Obs.TargetDamage, 2.5, 0, 800)
                drain(3, 0.25, 0.26, 0)
                drain(4, 0.05, 0.06, 1) -- the flip, the band agreeing
                reads(4, 0.055, 0.05, 0.06)
                within(1000, I.th.M, 1e-6)
            end)

            it("the unknown keeps a bound newer than the last band, as with no band (probes E, E2)", function()
                drain(3, 0.15, 0.16, 1)
                drain(4, nil, nil, 0, 1) -- the band unknown, short
                assert.are.equal("pinned", reads(4, 0.2, 0, 0.2).basis)
                drain(5, 0.15, 0.16, 1)
                drain(6) -- the band unknown, no answer
                reads(6, 0.2, 0, 0.2)
                drain(7, 0.25, 0.26, 0)
                drain(8) -- the same for a NOT
                reads(8, 1, OVER, 1)
            end)

            it("the unknown with no bound newer than the last band: [0, 1]", function()
                drain(3, 0.15, 0.16, 1)
                drain(4, 0.15, 0.16, 0, 1) -- that bound was drain 3's
                drain(5)
                assert.are.equal("default", reads(5, 1, 0, 1).basis)
            end)

            it("a swap, a combat end and a rebuild clear the bound (review M3)", function()
                local function bound(t)
                    drain(t, 0.15, 0.16, 1)
                    assert.are.equal(0.2, I.th.uHi)
                end
                local function none()
                    assert.are.same({ 0, 1 }, { I.th.uLo, I.th.uHi })
                end
                bound(3)
                obs(Obs.TargetSwap, 4, 2, 1, 1)
                I.Fold(4)
                none()
                drain(5, 0.25, 0.26, 0) -- a lower one
                assert.are.equal(OVER, I.th.uLo)
                obs(Obs.CombatEnd, 6)
                I.Fold(6)
                none()
                bound(7)
                I.Build(def(), 8)
                none()
            end)
        end)

        -- (fix round 1, review B2) An answer staged by an event before a swap folds after it: it is the old target's.
        -- Real events, all in one frame (one GetTime): the stamps are equal.
        describe("a swap (probe O)", function()
            local t
            before_each(function()
                VS.Start(api)
                t = ctl.now + 1
                ctl.now = t
                obs(Obs.Read, t, 1, 50, ReadOf.Resource)
            end)
            local function answer(ok, short)
                ctl.usable[SMITE] = { ok, short }
                ctl.Fire("SPELL_UPDATE_USABLE")
            end
            local function swapTo(guid)
                ctl.guid.target = guid
                ctl.Fire("PLAYER_TARGET_CHANGED")
            end
            local function frame(ok, short) -- the same frame's drain: the stage, then poll 2's answer
                ctl.usable[SMITE] = { ok, short }
                S.Flush()
                S.RunPolls(t)
                I.Fold(t)
            end

            it("with no band, a usable from before it never binds the new target", function()
                answer(true, false)
                swapTo("Creature-2")
                frame(false, true) -- short
                assert.are.equal("default", reads(t, 1, 0, 1).basis)
            end)

            it("nor when the poll reads secret (no answer of the new target at all)", function()
                answer(true, false)
                swapTo("Creature-2")
                frame(fake.SECRET, fake.SECRET)
                reads(t, 1, 0, 1)
            end)

            it("nor a NOT: no bound, no flip on the new target", function()
                answer(false, false)
                swapTo("Creature-2")
                frame(false, true)
                reads(t, 1, 0, 1)
                assert.are.equal(-1, I.th.prev[GATED]) -- nothing said
            end)

            it("with a band, full through the prime, then the new target's band", function()
                band(t, 0.15, 0.16)
                I.Fold(t)
                answer(true, false)
                swapTo("Creature-2")
                band(t)
                frame(false, true)
                reads(t, 1, 0, 1)
                band(t + 0.2, 0.7, 0.71)
                I.Fold(t + 0.2)
                reads(t + 0.2, 0.705, 0.7, 0.71)
            end)

            it("no plate (the map lockdown): a usable answer bounds the target by its ID (L1689 a)", function()
                swapTo(fake.SECRET)
                frame(true, false)
                reads(t, 0.2, 0, 0.2)
            end)

            it("no plate: a guarded NOT bounds it above the gate (L1689 a)", function()
                swapTo(fake.SECRET)
                frame(false, false)
                reads(t, 1, 0.2 + I.EPS, 1)
            end)

            it("two swaps in one frame: the first one's target answers nothing for the second", function()
                swapTo("Creature-2")
                answer(true, false)
                swapTo("Creature-3")
                frame(false, true)
                reads(t, 1, 0, 1)
            end)

            it("poll 2's re-ask in the swap's own drain is the new target's answer", function()
                answer(false, true)
                swapTo("Creature-2")
                frame(true, false)
                reads(t, 0.2, 0, 0.2)
            end)

            it("an event's answer after the swap, in its frame, is the new target's", function()
                swapTo("Creature-2")
                answer(true, false)
                frame(fake.SECRET, fake.SECRET)
                reads(t, 0.2, 0, 0.2)
            end)
        end)

        -- (fix round 1, review I6, design 2.3) The map restriction: the GUID secret, so no registry slot, with a plate (a
        -- memory slot) or without; poll 4's plain death read still ends the target.
        describe("a death under the map restriction (probe J)", function()
            for _, plate in ipairs({ false, true }) do
                it(("wins over the corpse's band, %s a plate"):format(plate and "with" or "without"), function()
                    local gone = {}
                    I.On(Obs.TargetGone, function(o)
                        gone[#gone + 1] = o.a
                    end)
                    VS.Start(api)
                    local t = ctl.now + 1
                    ctl.now = t
                    ctl.guid.target = fake.SECRET
                    if plate then
                        ctl.guid.nameplate1 = fake.SECRET
                        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
                        ctl.unitIs.target = "nameplate1"
                    end
                    ctl.Fire("PLAYER_TARGET_CHANGED")
                    band(t, 0.05, 0.06)
                    S.RunPolls(t)
                    I.Fold(t)
                    reads(t, 0.055, 0.05, 0.06)
                    assert.is_true(I.targetSlot > 0) -- a slot by its ID, with a plate or without
                    assert.are.equal(0, I.Units.Uid(1)) -- no identity either way
                    local before = #gone
                    ctl.dead.target = true
                    for i = 1, 3 do
                        band(t + i, 0, 0.01) -- the library keeps the lowest band on a corpse
                        S.RunPolls(t + i)
                        I.Fold(t + i)
                        assert.are.equal("observed", reads(t + i, 0, 0, 0).basis)
                    end
                    assert.are.same({ 0 }, { unpack(gone, before + 1) }) -- once, naming no slot
                    assert.is_true(I.th.dead)
                    ctl.dead.target, ctl.unitIs.target = nil, nil
                    ctl.now = t + 4
                    ctl.Fire("PLAYER_TARGET_CHANGED") -- the next target
                    band(t + 4.2, 0.5, 0.51)
                    I.Fold(t + 4.2)
                    reads(t + 4.2, 0.505, 0.5, 0.51)
                end)
            end

            it("a secret death read and no target at all say nothing", function()
                VS.Start(api)
                local t = ctl.now + 1
                ctl.now = t
                ctl.guid.target = fake.SECRET
                ctl.Fire("PLAYER_TARGET_CHANGED")
                ctl.dead.target = fake.SECRET
                band(t, 0.05, 0.06)
                S.RunPolls(t)
                I.Fold(t)
                reads(t, 0.055, 0.05, 0.06)
                ctl.guid.target = nil
                ctl.Fire("PLAYER_TARGET_CHANGED")
                ctl.dead.target = true -- a stale answer about nobody
                S.RunPolls(t + 1)
                I.Fold(t + 1)
                assert.is_false(I.th.dead)
            end)
        end)

        -- (fix round 2, review N2) A death the registry was told before the swap, or before poll 4.
        describe("a death the registry already holds", function()
            local READS =
                ": 0 in the belief and Facade.UnitHealth (core's target.health.pct answers 100 for a dead one)"
            local t
            before_each(function()
                VS.Start(api)
                t = ctl.now
            end)
            local function frame(lo)
                t = t + 1
                ctl.now = t
                band(t, lo, lo + 0.01)
                S.Flush()
                S.RunPolls(t)
                I.Fold(t)
            end
            local function target(guid, dead)
                ctl.guid.target, ctl.dead.target = guid, dead
                ctl.Fire("PLAYER_TARGET_CHANGED")
            end
            local function corpse()
                frame(0)
                assert.are.equal("observed", reads(t, 0, 0, 0).basis)
                assert.are.equal(0, ns.Facade.UnitHealth("target"))
            end

            it("a tab back to our kill" .. READS, function()
                ctl.dead.target = true
                corpse()
                target("Creature-2")
                frame(0.5)
                target("Creature-1", true)
                corpse()
            end)

            it("a mob killed while it was not the target, then targeted" .. READS, function()
                target("Creature-2")
                ctl.Fire("UNIT_DIED", "Creature-1")
                frame(0.5)
                reads(t, 0.505, 0.5, 0.51) -- another mob's death
                target("Creature-1", true)
                corpse()
            end)

            it("a rebuild while targeting a corpse" .. READS, function()
                ctl.dead.target = true
                corpse()
                I.Build(def(), t)
                corpse()
            end)

            for _, late in ipairs({ false, true }) do
                local when = late and "a later drain" or "that drain"
                it(("an event-first kill logs one TargetGone, poll 4 true in %s"):format(when), function()
                    local n = 0
                    I.On(Obs.TargetGone, function()
                        n = n + 1
                    end)
                    ctl.Fire("UNIT_DIED", "Creature-1")
                    if late then
                        corpse()
                    end
                    ctl.dead.target = true
                    corpse()
                    corpse()
                    assert.are.equal(1, n)
                end)
            end

            -- Unpinned until L1721: poll 4's inner `not dead`, and the latch's slot test.
            it("a poll-first kill logs one TargetGone", function()
                local n = 0
                I.On(Obs.TargetGone, function()
                    n = n + 1
                end)
                ctl.dead.target = true
                corpse()
                corpse()
                assert.are.equal(1, n)
            end)

            it("a remembered mob's death does not hide our target's own poll-only death", function()
                target("Creature-2")
                frame(0.5)
                target("Creature-1")
                frame(0.5)
                ctl.Fire("UNIT_DIED", "Creature-2")
                ctl.dead.target = true
                corpse()
            end)

            -- L1721: one rule, the dead -> alive edge of poll 4's UnitIsDead read, for each path to a believed death.
            describe("a target that lives again with no target change reads its band", function()
                local function die()
                    ctl.dead.target = true
                    corpse()
                end
                local function secret(plate)
                    if plate then
                        ctl.guid.nameplate1 = fake.SECRET
                        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
                        ctl.unitIs.target = "nameplate1"
                    end
                    target(fake.SECRET)
                    frame(0.5)
                    die()
                end
                local PATHS = {
                    {
                        "the event, then the poll",
                        function()
                            ctl.Fire("UNIT_DIED", "Creature-1")
                            corpse()
                            die()
                        end,
                    },
                    { "the poll alone (a feign read as dead)", die },
                    {
                        "a death first seen at the swap",
                        function()
                            target("Creature-2", true)
                            corpse()
                        end,
                    },
                    {
                        "a secret GUID, with a plate",
                        function()
                            secret(true)
                        end,
                    },
                    {
                        "a secret GUID, with no plate",
                        function()
                            secret(false)
                        end,
                    },
                    {
                        "a tab back to a corpse held dead",
                        function()
                            die()
                            target("Creature-2", false)
                            frame(0.5)
                            target("Creature-1", true)
                            corpse()
                        end,
                    },
                    {
                        "died while not the target, then targeted dead",
                        function()
                            target("Creature-2")
                            ctl.Fire("UNIT_DIED", "Creature-1")
                            frame(0.5)
                            target("Creature-1", true)
                            corpse()
                        end,
                    },
                    {
                        "a rebuild on a held corpse",
                        function()
                            die()
                            I.Build(def(), t)
                            corpse()
                        end,
                    },
                    {
                        "held dead, retargeted alive, dead again",
                        function()
                            die()
                            target("Creature-2", false)
                            frame(0.5)
                            target("Creature-1", false)
                            frame(0.5)
                            reads(t, 0.505, 0.5, 0.51)
                            die()
                        end,
                    },
                }
                for _, path in ipairs(PATHS) do
                    it(path[1], function()
                        path[2]()
                        local id, slot = I.targetID, I.targetSlot
                        ctl.dead.target = false
                        frame(0.6)
                        reads(t, 1, 0, 1) -- one drain at the default, as after a target change
                        for _ = 1, 3 do
                            frame(0.6)
                            reads(t, 0.605, 0.6, 0.61) -- and no flicker after
                        end
                        assert.is_true(ns.Facade.UnitHealth("target") > 0)
                        assert.are.same({ id, slot }, { I.targetID, I.targetSlot }) -- no target change: no new ID
                        die() -- and it can die again
                    end)
                end

                it("a secret answer is no revive; the next plain false is", function()
                    die()
                    ctl.dead.target = fake.SECRET
                    corpse()
                    corpse()
                    ctl.dead.target = false
                    frame(0.6)
                    frame(0.6)
                    reads(t, 0.605, 0.6, 0.61)
                end)

                it("the event alone has no edge: a false read behind it never revives", function()
                    ctl.Fire("UNIT_DIED", "Creature-1")
                    for _ = 1, 3 do
                        corpse()
                    end
                end)

                it("no target: a stale dead answer's end is no revive of nobody", function()
                    target(nil)
                    frame(0.5)
                    ctl.dead.target = true
                    frame(0.5)
                    local n = I.targetSwapN
                    ctl.dead.target = false
                    frame(0.5)
                    assert.are.equal(n, I.targetSwapN)
                end)

                it("allocates nothing over a death and a revive", function()
                    local alloc = require("Game.State.helpers.alloc")
                    die()
                    assert.are.equal(
                        0,
                        alloc.bytes(function()
                            ctl.dead.target = not ctl.dead.target
                            frame(0.3)
                        end, 1000)
                    )
                end)
            end)
        end)

        it("a combat end's restart is healed by the next drain's band", function()
            band(2, 0.4, 0.41)
            obs(Obs.CombatEnd, 3)
            band(3, 0.4, 0.41) -- the poll re-asserts after the staged event
            I.Fold(3)
            within(0.405, VS.Health("target", 3).est)
        end)

        it("allocates nothing over a swap, its answers and a bound's unknown", function()
            local alloc = require("Game.State.helpers.alloc")
            obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
            I.Fold(2)
            local t = 20
            local function cycle()
                t = t + 0.1
                obs(Obs.TargetSwap, t, 1, 0, 1)
                obs(Obs.Usable, t, GATED, 1, -9) -- an event's, from before the swap
                band(t, 0.19, 0.2)
                obs(Obs.Usable, t, GATED, 1, 0)
                I.Fold(t)
                band(t)
                I.Fold(t)
            end
            cycle()
            assert.are.equal(0, alloc.bytes(cycle, 1000))
        end)

        it("allocates nothing applying and dropping bands", function()
            local alloc = require("Game.State.helpers.alloc")
            local t = 20
            band(t, 0.33, 0.34)
            band(t)
            I.Fold(t)
            assert.are.equal(
                0,
                alloc.bytes(function()
                    t = t + 0.1
                    band(t, 0.33, 0.34)
                    I.Fold(t)
                    band(t)
                    I.Fold(t)
                end, 1000)
            )
        end)
    end)

    -- aura audit C8: a `now` reads whether its cast was instant (no start seen) and the target's health interval as
    -- percent bounds, `known` only once something bounded it (a fresh target's [0, 100] is unknown, never 100).
    describe("in the `now` context (aura audit C8)", function()
        local seen
        local function build()
            local d = def()
            d.abilities[2].now = function()
                local h = target.health -- luacheck: ignore 113 (the `now` context's names)
                seen[#seen + 1] = { instant, cast_start, h.known, h.lo, h.hi } -- luacheck: ignore 113
            end
            seen = {}
            I.Build(d, 1)
        end

        it("tells an instant cast from a hard one and answers the health bounds only once known", function()
            build()
            obs(Obs.CastSuccess, 2, 2, 0, 1) -- instant: no start
            I.Fold(2)
            obs(Obs.CastStart, 3, 2, 4.5)
            obs(Obs.CastSuccess, 4.5, 2, 0, 1)
            I.Fold(4.5)
            obs(Obs.Usable, 9, GATED, 1, 0) -- usable: at or below the gate (0.2)
            obs(Obs.CastSuccess, 10, 2, 0, 1)
            I.Fold(10)
            obs(Obs.TargetGone, 11, 1)
            obs(Obs.CastSuccess, 12, 2, 0, 1)
            I.Fold(12)
            assert.are.same({
                { true, 0, false, 0, 100 }, -- a fresh target: unknown
                { false, 3, false, 0, 100 },
                { true, 0, true, 0, 20 },
                { true, 0, true, 0, 0 }, -- dead: observed 0
            }, seen)
        end)
    end)
end)
