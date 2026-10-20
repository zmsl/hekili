-- tests/Game/State/modifiers_spec.lua (event-facade spec §12b): the resource definition's `maxMods` and `costMods`,
-- as a race pack declares them (Engine/Schema/Races.lua's ns.raceMods: a +5% maximum, a charged discount), through the adapter.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

local MOD_AURA = 1031

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
        h.Class.auras.mod_aura_a = { key = "mod_aura_a", id = MOD_AURA, duration = 15 }
        -- a race pack's declarations (Engine/Schema/Races.lua), as Adapter.lua reads them
        ns.raceMods = {
            maxMods = { { pct = 0.05 } },
            costMods = { { aura = "mod_aura_a", pct = -0.10, charges = 3, spells = { fs.SPENDER_B, 999999 } } },
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

    it("raises the maximum by a +5% maximum modifier through the modifier, until a plain read", function()
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
        "takes 10% off spender_b while mod_aura_a is up and spends a charge a cast; spender_c, out of scope, neither",
        function()
            local spender_b, spender_c = I.ab.bySpell[fs.SPENDER_B], I.ab.bySpell[fs.SPENDER_C]
            assert.are.equal(15, I.CostOf(spender_b))
            local j = I.auras.bySpell[MOD_AURA]
            I.AuraModel(1, j, 5, 20, 3, 5, VS.Obs.CastSuccess, false) -- mod_aura_a up with its three charges
            I.clock = 5
            assert.are.same({ 13.5, 10 }, { I.CostOf(spender_b), I.CostOf(spender_c) })
            cast(fs.SPENDER_C, 5.5)
            local _, stacks = VS.Aura("player", MOD_AURA, 5.6)
            assert.are.equal(3, stacks) -- spender_c took no charge
            for k = 1, 3 do
                cast(fs.SPENDER_B, 5.5 + k)
                _, stacks = VS.Aura("player", MOD_AURA, 5.5 + k + 0.05)
                assert.are.equal(3 - k > 0 and 3 - k or nil, stacks)
            end
            assert.is_nil(VS.Aura("player", MOD_AURA, 8.6))
            assert.are.equal(15, I.CostOf(spender_b))
        end
    )

    it("lets an observed aura read win over the charges it modelled", function()
        local j = I.auras.bySpell[MOD_AURA]
        I.AuraModel(1, j, 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        cast(fs.SPENDER_B, 6) -- 2 left, modelled
        I.Sources.Direct(VS.Obs.Read, 6.5, j, 13.5, I.ReadOf.Aura + 3 * I.AURA_STACK) -- the client says 3
        I.Fold(6.6)
        local _, stacks = VS.Aura("player", MOD_AURA, 6.7)
        assert.are.equal(3, stacks)
    end)

    it("never raises a point resource's maximum", function()
        h.Class.resources.combo_points = { type = 4 }
        VS.SpecChanged()
        local R = I.res
        assert.are.same({ 105, 100 }, { R.max[R.slotOfToken.RAGE], R.max[R.slotOfToken.COMBO_POINTS] })
    end)

    it("matches a listed `copy` rank, and every ability of the resource when `spells` is absent", function()
        local spender_b, spender_c = I.ab.bySpell[fs.SPENDER_B], I.ab.bySpell[fs.SPENDER_C]
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -0.10, spells = { fs.SPENDER_C_R2 } } }
        VS.SpecChanged()
        I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.are.same({ 15, 9 }, { I.CostOf(spender_b), I.CostOf(spender_c) }) -- spender_c by its rank 2 ID
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -0.10 } }
        VS.SpecChanged()
        I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        assert.are.same({ 13.5, 9 }, { I.CostOf(spender_b), I.CostOf(spender_c) })
    end)

    it("spends a charge on a cast the modifier made free (pct = -1, a proc's shape)", function()
        local spender_b = I.ab.bySpell[fs.SPENDER_B]
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -1, charges = 1, spells = { fs.SPENDER_B } } }
        VS.SpecChanged()
        I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 1, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.are.equal(0, I.CostOf(spender_b))
        cast(fs.SPENDER_B, 6)
        assert.is_nil(VS.Aura("player", MOD_AURA, 6.1)) -- the free cast took the charge
        assert.are.equal(15, I.CostOf(spender_b))
    end)

    it(
        "prices a cast when it is heard: the free-cast aura it consumed, read away first, still makes it free",
        function()
            local spender_c = I.ab.bySpell[fs.SPENDER_C]
            ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -1, charges = 1, spells = { fs.SPENDER_C } } }
            VS.SpecChanged()
            local j = I.auras.bySpell[MOD_AURA]
            I.AuraModel(1, j, 5, 20, 1, 5, VS.Obs.CastSuccess, false)
            I.clock = 5
            assert.are.equal(0, I.CostOf(spender_c))
            local spends = I.res.spends[1]
            ctl.now = 6
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_C) -- staged, priced now: 0
            I.Sources.Direct(VS.Obs.Read, 6, j, 0, I.ReadOf.Aura) -- the same frame's aura walk: gone, in the log first
            ctl.Tick(6.01)
            VS.Drain(6.02)
            assert.are.equal(spends, I.res.spends[1]) -- no spend: nothing paid, no five-second window
            assert.are.equal(10, I.CostOf(spender_c))
        end
    )

    it("prices a declared cost function in the belief's context: its aura reads are the belief's", function()
        local spender_c = I.ab.bySpell[fs.SPENDER_C]
        -- Races.lua keeps the declared function; this one reads the aura's stacks (a stacking free-cast proc's shape)
        rawset(I.ab.obj[spender_c], "declaredSpend", function()
            return 20 * math.max(0, 1 - 0.2 * buff.mod_aura_a.stack) -- luacheck: ignore 113 (the context's)
        end)
        local j = I.auras.bySpell[MOD_AURA]
        I.AuraModel(1, j, 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.is_true(math.abs(I.CostOf(spender_c) - 8) < 1e-9) -- 20 x (1 - 0.6)
        rawset(I.ab.obj[spender_c], "declaredSpend", function()
            return no_such_name.field -- luacheck: ignore 113 (raises in the context: the simulation prices it)
        end)
        assert.are.equal(10, I.CostOf(spender_c))
    end)

    it("allocates nothing over 1000 casts with both modifiers declared", function()
        local j = I.auras.bySpell[MOD_AURA]
        local t = 10
        local bytes = alloc.bytes(function()
            t = t + 1
            I.AuraModel(1, j, t, t + 15, 3, t, VS.Obs.CastSuccess, false)
            cast(fs.SPENDER_B, t + 0.5)
            cast(fs.SPENDER_C, t + 0.7)
        end, 1000)
        assert.are.equal(0, bytes)
    end)

    it("allocates nothing over 1000 casts priced by a declared cost function in the belief's context", function()
        local spender_c = I.ab.bySpell[fs.SPENDER_C]
        rawset(I.ab.obj[spender_c], "declaredSpend", function()
            return 20 * math.max(0, 1 - 0.2 * buff.mod_aura_a.stack) -- luacheck: ignore 113 (the context's)
        end)
        local j = I.auras.bySpell[MOD_AURA]
        local t = 10
        local bytes = alloc.bytes(function()
            t = t + 1
            I.AuraModel(1, j, t, t + 15, 3, t, VS.Obs.CastSuccess, false)
            cast(fs.SPENDER_C, t + 0.7)
        end, 1000)
        assert.are.equal(0, bytes)
    end)
end)
