-- tests/Virtual/State/target_health_spec.lua: the target health family (target-health design, 2026-10-16, §6). A
-- health-gated spender's flip pins the target's health at its gate and teaches M (the damage per full health) on a
-- target never held before; the guards keep a NOT from bounding it; WOUND damage moves it between answers; the time to
-- die and to a percentage follow; the facade and Targets.lua's GetTTD/GetTimeToPct (named core edit E4) answer it.
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
end)
