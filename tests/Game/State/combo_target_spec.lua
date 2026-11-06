-- tests/Game/State/combo_target_spec.lua: a resource the game binds to one target (L90; the owner's probes 2026-11-06,
-- memory forever-combo-points-plain): the pool (UnitPower) survives a target swap, but only the points on the current
-- target (GetComboPoints("player", "target")) are usable, so the belief's value is that answer: at every poll and at
-- once on PLAYER_TARGET_CHANGED (fired twice per swap: the read is idempotent). No target, or a secret answer: 0.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local alloc = require("Game.State.helpers.alloc")

local ENERGY, POINTS = 3, 4
local SECRET = fake.SECRET

describe("a target-bound resource", function()
    local ns, VS, I, api, ctl, saved, t

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({
            CreateFrame = api.CreateFrame,
            issecretvalue = api.issecretvalue,
            GetTime = api.GetTime,
            debugprofilestop = function()
                return 0
            end,
        }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        I.Build({
            abilities = {},
            abilityIds = {},
            abilitySlot = {},
            resources = {
                { key = "energy", type = ENERGY, token = "ENERGY", max = 100, rest = true, regen = 10 },
                { key = "points", type = POINTS, token = "COMBO_POINTS", max = 5, onTarget = true },
            },
            auras = {},
            auraIds = {},
            talents = {},
            units = { "player", "target" },
            fsr = load.constant("FSR"),
            gcdSpell = load.constant("GCD_SPELL"),
            oracleMin = load.constant("ORACLE_MIN"),
        }, 1)
        VS.Start(api)
        t = 100
        ctl.combat = true
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    -- The client's pool and its answer for the current target from now on, then one drain (the polls run).
    local function drain(pool, usable)
        ctl.power[POINTS], ctl.comboPoints.target = pool, usable
        t = t + 0.2
        ctl.now = t
        VS.Drain(t)
        return VS.Power(POINTS, t).est
    end

    -- A target swap: PLAYER_TARGET_CHANGED twice (as the client fires it), the fold after each, no poll.
    local function swap(guid, pool, usable)
        ctl.guid.target, ctl.power[POINTS], ctl.comboPoints.target = guid, pool, usable
        local got = {}
        for i = 1, 2 do
            t = t + 0.01
            ctl.now = t
            ctl.Fire("PLAYER_TARGET_CHANGED")
            I.Sources.Flush()
            I.Fold(t)
            got[i] = VS.Power(POINTS, t).est
        end
        return got
    end

    it("answers the points on the current target, not the pool kept from another", function()
        assert.are.equal(0, drain(4, 0)) -- pool 4 bound to a target we swapped off: 0 usable here
        assert.are.equal(4, drain(4, nil)) -- the fake's default: the current target holds the pool
    end)

    it("follows the owner's swap and swap-back probe, at once on each PLAYER_TARGET_CHANGED", function()
        -- measured 2026-11-06 20:58 (Rogue): generator on A 1/1, swap to B 1/0, swap back to A 1/1 (pool / usable)
        assert.are.equal(1, drain(1, 1))
        assert.are.same({ 0, 0 }, swap("Creature-B", 1, 0))
        assert.are.same({ 1, 1 }, swap("Creature-1", 1, 1))
        -- measured 2026-11-06: a generator on B clears A's points (A reads 0 on return) and starts B's count fresh
        assert.are.same({ 0, 0 }, swap("Creature-B", 1, 0))
        assert.are.equal(1, drain(1, 1)) -- the generator on B: the pool restarts at 1, all of it on B
        assert.are.same({ 0, 0 }, swap("Creature-1", 1, 0))
    end)

    it("reads 0 with no target (no answer) and on a secret answer, never the pool", function()
        assert.are.equal(0, drain(3, false)) -- GetComboPoints answers nil: no unit
        assert.are.equal(0, drain(3, SECRET))
        assert.are.equal("secret", I.Sources.status.GetComboPoints)
        assert.are.equal(3, drain(3, nil))
    end)

    it("leaves every other resource on UnitPower", function()
        ctl.power[ENERGY] = 40
        drain(2, 0)
        assert.are.equal(40, VS.Power(ENERGY, t).est)
    end)

    it("allocates nothing reading it at a poll or a swap", function()
        ctl.power[POINTS] = 2
        assert.are.equal(
            0,
            alloc.bytes(function(i)
                ctl.comboPoints.target = i % 2 == 0 and 2 or 0
                t = t + 0.01
                ctl.now = t
                ctl.Fire("PLAYER_TARGET_CHANGED")
                VS.Drain(t)
            end, 1000)
        )
    end)
end)
