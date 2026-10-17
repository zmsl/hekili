-- tests/Virtual/State/modifiers_spec.lua (event-facade spec §12b): the resource definition's `maxMods` and `costMods`,
-- as a race pack declares them (Engine/Races.lua's ns.raceMods: Expansive Mind, Eureka!), through the adapter.
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")
local fs = require("Virtual.State.helpers.fake_spec")
local alloc = require("Virtual.State.helpers.alloc")

local EUREKA = 1259813

describe("resource modifiers", function()
    local ns, VS, I, api, ctl, h, saved

    local function cast(id, t)
        ctl.now = t
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
        ctl.Tick(t + 0.01)
        VS.Drain(t + 0.02)
    end

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        saved = {}
        for _, k in ipairs({ "GetTime", "UnitGUID", "CreateFrame", "issecretvalue", "debugprofilestop" }) do
            saved[k] = rawget(_G, k) or false
        end
        _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue =
            api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
        _G.debugprofilestop = function()
            return 0
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        h = fs.new(9)
        fs.clock = api.GetTime
        ns.spendResources = fs.spend
        ns.ResourceRegenerates = function()
            return false
        end
        ns.ResourceIsPoints = function(k) -- Constants.lua's, for the one point resource here
            return k == "combo_points"
        end
        h.Class.auras.eureka = { key = "eureka", id = EUREKA, duration = 15 }
        -- the Gnome race pack's declarations (Forever/Races/Gnome.lua through Engine/Races.lua), as Adapter.lua reads them
        ns.raceMods = {
            maxMods = { { pct = 0.05 } },
            costMods = { { aura = "eureka", pct = -0.10, charges = 3, spells = { fs.STRIKE, 999999 } } },
        }
        function h:ForceUpdate() end
        load.adapter(ns, h)
        VS.Start(api)
        VS.SpecChanged()
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        fs.clock = nil
    end)

    it("raises the maximum by Expansive Mind through the modifier, until a plain read", function()
        assert.are.equal(105, I.res.max[1]) -- 100 declared x 1.05
        assert.are.equal(105, I.res.hi0[1]) -- one evaluator: the interval is seeded at the raised maximum
        I.Sources.Direct(VS.Obs.CombatEnd, 2)
        I.Fold(2)
        assert.are.equal(105, I.res.max[1])
        I.Sources.Direct(VS.Obs.Read, 3, 1, 120, I.ReadOf.Max)
        I.Fold(3)
        I.Sources.Direct(VS.Obs.CombatEnd, 4)
        I.Fold(4)
        assert.are.equal(120, I.res.max[1]) -- the plain read keeps winning
        ns.raceMods = { maxMods = {}, costMods = {} } -- another race: no modifier
        VS.SpecChanged()
        assert.are.equal(100, I.res.max[1])
    end)

    it(
        "takes 10% off Heroic Strike while Eureka! is up and spends a charge a cast; Rend, out of scope, neither",
        function()
            local strike, rend = I.ab.bySpell[fs.STRIKE], I.ab.bySpell[fs.REND]
            assert.are.equal(15, I.CostOf(strike))
            local j = I.auras.bySpell[EUREKA]
            I.AuraModel(1, j, 5, 20, 3, 5, VS.Obs.CastSuccess, false) -- Eureka! up with its three charges
            I.clock = 5
            assert.are.same({ 13.5, 10 }, { I.CostOf(strike), I.CostOf(rend) })
            cast(fs.REND, 5.5)
            local _, stacks = VS.Aura("player", EUREKA, 5.6)
            assert.are.equal(3, stacks) -- Rend took no charge
            for k = 1, 3 do
                cast(fs.STRIKE, 5.5 + k)
                _, stacks = VS.Aura("player", EUREKA, 5.5 + k + 0.05)
                assert.are.equal(3 - k > 0 and 3 - k or nil, stacks)
            end
            assert.is_nil(VS.Aura("player", EUREKA, 8.6))
            assert.are.equal(15, I.CostOf(strike))
        end
    )

    it("lets an observed aura read win over the charges it modelled", function()
        local j = I.auras.bySpell[EUREKA]
        I.AuraModel(1, j, 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        cast(fs.STRIKE, 6) -- 2 left, modelled
        I.Sources.Direct(VS.Obs.Read, 6.5, j, 13.5, I.ReadOf.Aura + 3 * I.AURA_STACK) -- the client says 3
        I.Fold(6.6)
        local _, stacks = VS.Aura("player", EUREKA, 6.7)
        assert.are.equal(3, stacks)
    end)

    it("never raises a point resource's maximum", function()
        h.Class.resources.combo_points = { type = 4 }
        VS.SpecChanged()
        local R = I.res
        assert.are.same({ 105, 100 }, { R.max[R.slotOfToken.RAGE], R.max[R.slotOfToken.COMBO_POINTS] })
    end)

    it("matches a listed `copy` rank, and every ability of the resource when `spells` is absent", function()
        local strike, rend = I.ab.bySpell[fs.STRIKE], I.ab.bySpell[fs.REND]
        ns.raceMods.costMods = { { aura = "eureka", pct = -0.10, spells = { fs.REND_R2 } } }
        VS.SpecChanged()
        I.AuraModel(1, I.auras.bySpell[EUREKA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.are.same({ 15, 9 }, { I.CostOf(strike), I.CostOf(rend) }) -- Rend by its rank 2 ID
        ns.raceMods.costMods = { { aura = "eureka", pct = -0.10 } }
        VS.SpecChanged()
        I.AuraModel(1, I.auras.bySpell[EUREKA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        assert.are.same({ 13.5, 9 }, { I.CostOf(strike), I.CostOf(rend) })
    end)

    it("spends a charge on a cast the modifier made free (pct = -1, the Clearcasting shape)", function()
        local strike = I.ab.bySpell[fs.STRIKE]
        ns.raceMods.costMods = { { aura = "eureka", pct = -1, charges = 1, spells = { fs.STRIKE } } }
        VS.SpecChanged()
        I.AuraModel(1, I.auras.bySpell[EUREKA], 5, 20, 1, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.are.equal(0, I.CostOf(strike))
        cast(fs.STRIKE, 6)
        assert.is_nil(VS.Aura("player", EUREKA, 6.1)) -- the free cast took the charge
        assert.are.equal(15, I.CostOf(strike))
    end)

    it("allocates nothing over 1000 casts with both modifiers declared", function()
        local j = I.auras.bySpell[EUREKA]
        local t = 10
        local bytes = alloc.bytes(function()
            t = t + 1
            I.AuraModel(1, j, t, t + 15, 3, t, VS.Obs.CastSuccess, false)
            cast(fs.STRIKE, t + 0.5)
            cast(fs.REND, t + 0.7)
        end, 1000)
        assert.are.equal(0, bytes)
    end)
end)
