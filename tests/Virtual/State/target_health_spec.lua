-- tests/Virtual/State/target_health_spec.lua: the target health family (target-health design, 2026-10-16, §6). A
-- health-gated spender's flip pins the target's health at its gate and teaches M (the damage per full health) on a
-- target never held before; the guards keep a NOT from bounding it; WOUND damage moves it between answers, sampled only
-- from an anchor (R5); the resets. No time to die (dropped by the user, 2026-10-16).
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")

local function within(want, got, tol)
    assert.is_true(math.abs(want - got) <= (tol or 1e-9), ("want %s, got %s"):format(want, got))
end

-- A gated spender (Smite: 15 rage, usable at or below 20%, not while Stance is up) and an ungated one; rage, no regen.
local SMITE, SLAM, STANCE = 2001, 2002, 3001
local GATED = 1 -- Smite's ability index

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
        ns = load.module()
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
end)
