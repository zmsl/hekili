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
        -- a race pack's declarations (Engine/Schema/Races.lua), as Engine/Schema/Tracked.lua reads them
        ns.raceMods = {
            maxMods = { { pct = 0.05 } },
            costMods = { { aura = "mod_aura_a", pct = -0.10, charges = 3, spells = { fs.SPENDER_B, 999999 } } },
        }
        function h:ForceUpdate() end
        load.schema(ns, h)
        VS.Start(api)
        ns.BuildTracked()
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
        ns.BuildTracked()
        assert.are.equal(100, I.res.max[1])
    end)

    it(
        "takes 10% off spender_b while mod_aura_a is up and spends a charge a cast; spender_c, out of scope, neither",
        function()
            VS.Drain(1.5) -- the build's player walk first: the client lists no mod_aura_a, the model below is the fixture
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

    -- L576 bug 2: an up-read in the cast's frame or before it cannot include the cast's close of the last charge.
    it("closes a one-charge modifier's aura at the cast even after an up-read just before it", function()
        local spender_b = I.ab.bySpell[fs.SPENDER_B]
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -0.10, charges = 1, spells = { fs.SPENDER_B } } }
        ns.BuildTracked()
        VS.Drain(1.5)
        local j = I.auras.bySpell[MOD_AURA]
        I.Sources.Direct(VS.Obs.Read, 5.98, j, -1, I.ReadOf.Aura + I.AURA_STACK) -- up, permanent, in the cast's frame
        I.Fold(5.99)
        cast(fs.SPENDER_B, 6)
        assert.is_nil(VS.Aura("player", MOD_AURA, 6.1))
        I.clock = 6.1
        assert.are.equal(15, I.CostOf(spender_b))
    end)

    it("never raises a point resource's maximum", function()
        h.Class.resources.combo_points = { type = 4 }
        ns.BuildTracked()
        local R = I.res
        assert.are.same({ 105, 100 }, { R.max[R.slotOfToken.RAGE], R.max[R.slotOfToken.COMBO_POINTS] })
    end)

    it("matches a listed `copy` rank, and every ability of the resource when `spells` is absent", function()
        local spender_b, spender_c = I.ab.bySpell[fs.SPENDER_B], I.ab.bySpell[fs.SPENDER_C]
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -0.10, spells = { fs.SPENDER_C_R2 } } }
        ns.BuildTracked()
        I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.are.same({ 15, 9 }, { I.CostOf(spender_b), I.CostOf(spender_c) }) -- spender_c by its rank 2 ID
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -0.10 } }
        ns.BuildTracked()
        I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        assert.are.same({ 13.5, 9 }, { I.CostOf(spender_b), I.CostOf(spender_c) })
    end)

    it("spends a charge on a cast the modifier made free (pct = -1, a proc's shape)", function()
        local spender_b = I.ab.bySpell[fs.SPENDER_B]
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -1, charges = 1, spells = { fs.SPENDER_B } } }
        ns.BuildTracked()
        I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 1, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.are.equal(0, I.CostOf(spender_b))
        cast(fs.SPENDER_B, 6)
        assert.is_nil(VS.Aura("player", MOD_AURA, 6.1)) -- the free cast took the charge
        assert.are.equal(15, I.CostOf(spender_b))
    end)

    -- A percent-of-base cost is priced whole first, then cut by the modifiers, unrounded, as the simulation does
    -- (spend_base_spec.lua; wowsims e4ef929e54 spell.go:1055): 11% of 1720 is 189, halved 94.5, cut 12% 166.32.
    it("cuts a percent-of-base cost after pricing it whole, unrounded", function()
        local spender_c = I.ab.bySpell[fs.SPENDER_C]
        h.Class.abilities.spender_c.spend = 0.11
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -0.5 } }
        ns.BuildTracked()
        I.basePow[I.ab.slot[spender_c]] = 1720
        I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.are.same({ 189, 94.5 }, { I.BaseCostOf(spender_c), I.CostOf(spender_c) })
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -0.12 } }
        ns.BuildTracked()
        I.basePow[I.ab.slot[spender_c]] = 1720
        I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        assert.is_true(math.abs(I.CostOf(spender_c) - 166.32) < 1e-9, tostring(I.CostOf(spender_c)))
    end)

    -- A talent-gated modifier (`talent`, no aura): active while the talent has a rank, its `pct` by rank (a list) or
    -- one value; the cut lands on the whole price, unrounded (wowsims e4ef929e54 spell_mod.go:909 on a passive talent:
    -- 11% of 1720 is 189, a 12% rank 166.32), as the simulation applies it (spend_base_spec.lua).
    it("cuts a cost by a talent's rank with no aura, and not at rank 0", function()
        local spender_c = I.ab.bySpell[fs.SPENDER_C]
        h.Class.abilities.spender_c.spend = 0.11
        ns.raceMods.costMods = { { talent = "talent_a", pct = { -0.04, -0.08, -0.12 } } }
        ns.BuildTracked()
        I.basePow[I.ab.slot[spender_c]] = 1720
        I.clock = 5
        local got = {}
        for rank = 0, 3 do
            I.SetTalentRank(1, rank)
            got[#got + 1] = I.CostOf(spender_c)
        end
        assert.are.same({ 189, 181.44 }, { got[1], got[2] })
        assert.is_true(math.abs(got[3] - 173.88) < 1e-9 and math.abs(got[4] - 166.32) < 1e-9, table.concat(got, " "))
        ns.raceMods.costMods = { { talent = "talent_a", pct = -0.5, spells = { fs.SPENDER_B } } } -- one value, any rank
        ns.BuildTracked()
        I.SetTalentRank(1, 2)
        assert.are.equal(7.5, I.CostOf(I.ab.bySpell[fs.SPENDER_B]))
    end)

    -- An aura + talent modifier with charges needs the rank for its charge as for its price: at rank 0 the aura's
    -- stacks stay (the simulation's M.Spend alike, races_spec.lua).
    it("takes no charge from an aura + talent modifier at talent rank 0", function()
        local spender_b = I.ab.bySpell[fs.SPENDER_B]
        local def = { aura = "mod_aura_a", talent = "talent_a", pct = -0.10, charges = 3, spells = { fs.SPENDER_B } }
        ns.raceMods.costMods = { def }
        ns.BuildTracked()
        VS.Drain(1.5)
        local j = I.auras.bySpell[MOD_AURA]
        I.SetTalentRank(1, 0)
        I.AuraModel(1, j, 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.are.equal(15, I.CostOf(spender_b))
        cast(fs.SPENDER_B, 6)
        local _, stacks = VS.Aura("player", MOD_AURA, 6.1)
        assert.are.equal(3, stacks)
        I.SetTalentRank(1, 1)
        I.clock = 6.1
        assert.are.equal(13.5, I.CostOf(spender_b))
        cast(fs.SPENDER_B, 7)
        _, stacks = VS.Aura("player", MOD_AURA, 7.1)
        assert.are.equal(2, stacks)
    end)

    -- A talent key the class did not register never applies, with an aura or without (a shared or race modifier
    -- naming another class's talent).
    for _, aura in ipairs({ "mod_aura_a", false }) do
        it("never applies a talent key the class lacks (" .. (aura and "with" or "without") .. " an aura)", function()
            local spender_b = I.ab.bySpell[fs.SPENDER_B]
            ns.raceMods.costMods = { { aura = aura or nil, talent = "not_a_talent", pct = -0.5 } }
            ns.BuildTracked()
            I.SetTalentRank(1, 3)
            I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
            I.clock = 5
            assert.are.equal(15, I.CostOf(spender_b))
        end)
    end

    -- `unless` (CN11): while the named aura is believed up on the player, the modifier neither prices nor takes a
    -- charge; the other modifier's spend in the same cast never decides it, whichever comes first in the list.
    local function unlessMods(first)
        local held = { aura = "mod_aura_a", pct = -0.10, charges = 3, spells = { fs.SPENDER_B }, unless = "mod_aura_b" }
        local other = { aura = "mod_aura_b", pct = -0.5, charges = 1, spells = { fs.SPENDER_B } }
        h.Class.auras.mod_aura_b = { key = "mod_aura_b", id = 1032, duration = 30 }
        ns.raceMods.costMods = first and { held, other } or { other, held }
        ns.BuildTracked()
        VS.Drain(1.5) -- the build's player walk first: the client lists neither aura, the models below are the fixture
    end

    for _, first in ipairs({ true, false }) do
        it(
            "skips a modifier's price and charge while its `unless` aura is up (listed "
                .. (first and "first" or "last")
                .. ")",
            function()
                unlessMods(first)
                local spender_b = I.ab.bySpell[fs.SPENDER_B]
                local ja, jb = I.auras.bySpell[MOD_AURA], I.auras.bySpell[1032]
                I.AuraModel(1, ja, 5, 20, 3, 5, VS.Obs.CastSuccess, false)
                I.clock = 5
                assert.are.equal(13.5, I.CostOf(spender_b))
                cast(fs.SPENDER_B, 6)
                local _, stacks = VS.Aura("player", MOD_AURA, 6.1)
                assert.are.equal(2, stacks)
                I.AuraModel(1, jb, 7, 37, 1, 7, VS.Obs.CastSuccess, false)
                I.clock = 7
                assert.are.equal(7.5, I.CostOf(spender_b)) -- mod_aura_a held: mod_aura_b's half alone
                cast(fs.SPENDER_B, 8)
                _, stacks = VS.Aura("player", MOD_AURA, 8.1)
                assert.are.same({ false, 2 }, { VS.Aura("player", 1032, 8.1) ~= nil, stacks })
                I.clock = 8.1
                assert.are.equal(13.5, I.CostOf(spender_b))
            end
        )
    end

    -- B-D3 (DRY belief pass): a success folded late (staged, behind a later direct observation) spends at the cast's
    -- own time, so an aura a Cooldown Manager open gained after the cast was not up at it: it neither loses a charge
    -- nor holds another modifier by `unless` (I.AuraUpAt: applied at or before the cast, expiring after it).
    local function lateCast(id, t, j, lit)
        ctl.now = t
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id) -- staged until the frame's flush
        I.Sources.Direct(VS.Obs.Read, lit, j, 15, I.ReadOf.AuraOpen) -- lit after the cast, logged before it
        ctl.Tick(lit + 0.01)
        VS.Drain(lit + 0.02)
    end

    it("keeps the charge of an aura a Cooldown Manager open gained after a late-folded cast", function()
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -1, charges = 1, spells = { fs.SPENDER_B } } }
        ns.BuildTracked()
        VS.Drain(1.5)
        lateCast(fs.SPENDER_B, 6, I.auras.bySpell[MOD_AURA], 6.05)
        local _, stacks, applied = VS.Aura("player", MOD_AURA, 6.1)
        assert.are.same({ 1, 6.05 }, { stacks, applied })
    end)

    it("spends a charge its `unless` aura did not hold at a late-folded cast (the `unless` gained after it)", function()
        unlessMods(true)
        local ja = I.auras.bySpell[MOD_AURA]
        I.AuraModel(1, ja, 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        lateCast(fs.SPENDER_B, 6, I.auras.bySpell[1032], 6.05)
        local _, stacks = VS.Aura("player", MOD_AURA, 6.1)
        assert.are.equal(2, stacks)
    end)

    it("carries `unless` into the build as a plain copy, and an aura key the class lacks never holds", function()
        unlessMods(true)
        local built = I.mods.costMods[1]
        assert.are_not.equal(ns.raceMods.costMods, built) -- Tracked.lua's plain() copy, not the core's list
        assert.are.same({ "mod_aura_b", false }, { built[1].unless, built[2].unless or false })
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -0.10, spells = { fs.SPENDER_B }, unless = "no_such" } }
        ns.BuildTracked()
        I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.are.equal(13.5, I.CostOf(I.ab.bySpell[fs.SPENDER_B]))
    end)

    it("allocates nothing over 1000 casts with an `unless` modifier, its aura up and down", function()
        unlessMods(false)
        local ja, jb = I.auras.bySpell[MOD_AURA], I.auras.bySpell[1032]
        local t = 10
        local bytes = alloc.bytes(function()
            t = t + 1
            I.AuraModel(1, ja, t, t + 15, 3, t, VS.Obs.CastSuccess, false)
            I.AuraModel(1, jb, t, t + 15, 1, t, VS.Obs.CastSuccess, false)
            cast(fs.SPENDER_B, t + 0.3)
            cast(fs.SPENDER_B, t + 0.6)
        end, 1000)
        assert.are.equal(0, bytes)
    end)

    it(
        "prices a cast when it is heard: the free-cast aura it consumed, read away first, still makes it free",
        function()
            local spender_c = I.ab.bySpell[fs.SPENDER_C]
            ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -1, charges = 1, spells = { fs.SPENDER_C } } }
            ns.BuildTracked()
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

    it(
        "keeps a proc its own cast raised: the charge is spent at the cast's time, however late the success folds",
        function()
            ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -1, charges = 1, spells = { fs.SPENDER_B } } }
            ns.BuildTracked()
            local j = I.auras.bySpell[MOD_AURA]
            ctl.now = 6
            I.Sources.Direct(VS.Obs.Read, 6, j, 15, I.ReadOf.Aura + I.AURA_STACK) -- the proc's read, in the log first
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_B) -- staged at 6, the cast that raised it
            I.Sources.Direct(VS.Obs.Moving, 6.15, 0, 1) -- a later direct row: the fold's clock passes the cast
            ctl.Tick(6.16)
            VS.Drain(6.17)
            assert.is_truthy(VS.Aura("player", MOD_AURA, 6.2))
        end
    )

    -- L1110 (owner, in game): a free-cast proc comes on the cast's success, so the cast that raised it pays in full and
    -- the next covered cast takes it, whichever of the success and the proc's read the drain meets first. With one up
    -- before the cast (`up`), the cast takes that one free and its own proc is a fresh one (expires 21, not 20).
    for _, case in ipairs({ { false, false }, { true, false }, { false, true }, { true, true } }) do
        local readFirst, up = case[1], case[2]
        it(
            "never discounts a cast by the proc its own success raised (the proc's read "
                .. (readFirst and "before" or "after")
                .. " the success, one drain"
                .. (up and ", one already up)" or ")"),
            function()
                ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -1, charges = 1, spells = { fs.SPENDER_B } } }
                ns.BuildTracked()
                VS.Drain(1.5)
                local j = I.auras.bySpell[MOD_AURA]
                if up then
                    I.AuraModel(1, j, 5, 20, 1, 5, VS.Obs.CastSuccess, false)
                end
                local paid, shift = 0, I.ResourceShift
                I.ResourceShift = function(r, d, ...)
                    paid = paid - d
                    return shift(r, d, ...)
                end
                ctl.now = 6
                if readFirst then
                    I.Sources.Direct(VS.Obs.Read, 6, j, 21, I.ReadOf.Aura + I.AURA_STACK)
                end
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_B)
                if not readFirst then
                    I.Sources.Direct(VS.Obs.Read, 6, j, 21, I.ReadOf.Aura + I.AURA_STACK)
                end
                ctl.Tick(6.01)
                VS.Drain(6.02)
                I.ResourceShift = shift
                local _, stacks = VS.Aura("player", MOD_AURA, 6.1)
                -- paid in full (free on the one already up), the proc kept for the next cast
                assert.are.same({ up and 0 or 15, 1 }, { paid, stacks })
                I.clock = 6.1
                assert.are.equal(0, I.CostOf(I.ab.bySpell[fs.SPENDER_B]))
                cast(fs.SPENDER_B, 7) -- the next cast takes it
                assert.is_nil(VS.Aura("player", MOD_AURA, 7.1))
            end
        )
    end

    -- Wrath's shape: a spell out of the modifier's scope, and a covered one that costs nothing, neither price by nor
    -- take the charge (Families/Now.lua spends charges only when the declared cost is above 0).
    it("keeps the charge through an out-of-scope cast and a covered zero-cost one", function()
        ns.raceMods.costMods = { { aura = "mod_aura_a", pct = -1, charges = 1, spells = { fs.SPENDER_B } } }
        ns.BuildTracked()
        VS.Drain(1.5)
        local spender_b = I.ab.bySpell[fs.SPENDER_B]
        I.AuraModel(1, I.auras.bySpell[MOD_AURA], 5, 20, 1, 5, VS.Obs.CastSuccess, false)
        cast(fs.SPENDER_C, 6) -- out of scope: priced in full, no charge
        local _, stacks = VS.Aura("player", MOD_AURA, 6.1)
        assert.are.equal(1, stacks)
        local spend = rawget(I.ab.obj[spender_b], "spend")
        I.ab.obj[spender_b].spend = 0 -- covered, free as declared
        cast(fs.SPENDER_B, 6.5)
        I.ab.obj[spender_b].spend = spend
        _, stacks = VS.Aura("player", MOD_AURA, 6.6)
        assert.are.equal(1, stacks)
    end)

    it("prices a declared cost function in the belief's context: its aura reads are the belief's", function()
        local spender_c = I.ab.bySpell[fs.SPENDER_C]
        -- the record's `spend` is the declared function (Tracked.lua); this one reads the aura's stacks (a stacking
        -- free-cast proc's shape)
        I.ab.obj[spender_c].spend = function()
            return 20 * math.max(0, 1 - 0.2 * buff.mod_aura_a.stack) -- luacheck: ignore 113 (the context's)
        end
        local j = I.auras.bySpell[MOD_AURA]
        I.AuraModel(1, j, 5, 20, 3, 5, VS.Obs.CastSuccess, false)
        I.clock = 5
        assert.is_true(math.abs(I.CostOf(spender_c) - 8) < 1e-9) -- 20 x (1 - 0.6)
        local errors = I.nowErrors
        I.ab.obj[spender_c].spend = function()
            return no_such_name.field -- luacheck: ignore 113 (raises in the context: counted, the static prices it)
        end
        I.ab.obj[spender_c].static = { spend = 10 }
        assert.are.equal(10, I.CostOf(spender_c))
        assert.are.equal(errors + 1, I.nowErrors)
        I.ab.obj[spender_c].static = nil
        assert.are.equal(0, I.CostOf(spender_c)) -- no static: 0, never the simulation's answer
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

    it("adds a race's regen entry to its named resource only, once per build, the class's list untouched", function()
        h.Class.auras.mod_aura_b = { key = "mod_aura_b", id = 1032, duration = 30 }
        ns.raceMods.regenMods = {
            { resource = "rage", aura = "mod_aura_b", mult = 2 },
            { resource = "mana", aura = "mod_aura_b", mult = 2 }, -- the class has no mana: inert
        }
        ns.BuildTracked()
        ns.BuildTracked() -- a rebuild adds it once
        local R = I.res
        local M = R.regenMult
        assert.are.same({ 1, R.slotOfToken.RAGE, 2 }, { M.n, M.slot[1], M.mult[1] })
        assert.is_nil(h.Class.resources.rage.state.regenMult)
    end)
end)
