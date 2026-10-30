-- tests/Forever/alts_spec.lua (display styles plan, Task 3c): alternatives under resource uncertainty. A subscriber
-- declaring needs = { alts = true } gets, on records 1 and 2, the picks the APL makes with the gating resource pinned
-- at the belief's low and high bound. The invariant first: the main records never depend on whether they were
-- computed (one Arms gate fight run twice in-process, the need off then on, every field but alts compared:
-- helpers/alts.lua); seed 1 here, seeds 2 and 3 in alts_seed2_spec.lua and alts_seed3_spec.lua, one fight a file so
-- the parallel runner spreads them.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local alts = require("Forever.helpers.alts")

describe("alternatives: the main records never depend on them #slow", function()
    it("every display's recs[1..count], every field but alts, is identical with the need off and on, seed 1", function()
        alts.invariant(1)
    end)
end)

describe("alternatives (headless Arms, a scripted belief band)", function()
    local H, out, t, band
    local function need() end

    -- Rage (power type 1) as the belief: Core's bound read gets the scripted band; every other reader (the client
    -- facade's UnitPower, so the main records) gets the estimate as its low bound.
    local function script()
        local VS = H.ns.VirtualState
        local power, fake = VS.Power, { est = 0, lo = 0, hi = 0, conf = 1 }
        VS.Power = function(pt, now)
            local r = power(pt, now)
            if pt ~= 1 then
                return r
            end
            local core = debug.getinfo(2, "S").source:find("Engine/Sim/Core.lua", 1, true)
            fake.est, fake.lo, fake.hi = band.est, core and band.lo or band.est, band.hi
            return fake
        end
    end

    local function cycle()
        t = t + 0.2
        assert(headless.cycle(H, t))
    end

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        -- A spender (30 rage), a cheaper spender (10) and a free filler, in that order.
        H.Hekili.DB.profile.packs[ww.PACK].lists = {
            precombat = {},
            default = {
                { enabled = true, action = "mortal_strike" },
                { enabled = true, action = "hamstring" },
                { enabled = true, action = "berserker_stance" },
            },
        }
        H.Hekili:LoadScripts()
        H.Fire("PLAYER_REGEN_DISABLED")
        script()
        out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", need, true, { alts = true }))
    end)

    it(
        "a band straddling the pick's cost yields the spender (hi) and the filler (lo) on recs[1], in APL order",
        function()
            band = { est = 15, lo = 5, hi = 40 }
            cycle()
            local r = out.recs[1]
            assert.are.equal("hamstring", r.actionName)
            assert.are.equal(10, r.cost)
            local a = r.alts
            assert.are.equal(2, a.n)
            assert.are.same(
                { "mortal_strike", "hi", 1, "default" },
                { a[1].actionName, a[1].bound, a[1].action, a[1].list }
            )
            assert.are.same(
                { "berserker_stance", "lo", 3, "default" },
                { a[2].actionName, a[2].bound, a[2].action, a[2].list }
            )
            local abilities = H.Hekili.Class.abilities
            assert.are.equal(abilities.mortal_strike.id, a[1].actionID)
            assert.are.equal(abilities.berserker_stance.id, a[2].actionID)
            assert.is_not_nil(a[1].texture)
            assert.is_not_nil(a[2].texture)
            assert.are.same({}, H.errors)
        end
    )

    it("the same pick at both bounds is one alternative, not two", function()
        -- the free filler only outside 10..30 rage: at 15 the pick is hamstring, at 5 and at 40 the filler
        H.Hekili.DB.profile.packs[ww.PACK].lists.default = {
            { enabled = true, action = "berserker_stance", criteria = "rage<10|rage>30" },
            { enabled = true, action = "hamstring" },
        }
        H.Hekili:LoadScripts()
        band = { est = 15, lo = 5, hi = 40 }
        cycle()
        local r = out.recs[1]
        assert.are.equal("hamstring", r.actionName)
        assert.are.equal(1, r.alts.n)
        assert.are.same({ "berserker_stance", "lo" }, { r.alts[1].actionName, r.alts[1].bound })
        assert.are.same({}, H.errors)
    end)

    it("a band that does not straddle the pick's cost yields none", function()
        local st = H.Hekili.State
        band = { est = 15, lo = 5, hi = 40 }
        cycle()
        assert.are.equal(2, out.recs[1].alts.n)
        assert.is_true(st.fullNext, "passes ran: the next reset must be full") -- no display follows Primary here
        band = { est = 15, lo = 12, hi = 20 }
        cycle()
        assert.is_false(st.fullNext, "no pass ran: Primary's reset consumed the flag and none set it")
        assert.are.equal("hamstring", out.recs[1].actionName)
        for i = 1, out.count do
            assert.are.equal(0, out.recs[i].alts.n, i)
        end
        assert.are.same({}, H.errors)
    end)

    it("during a cast in progress each pass picks at its record's time, not that time after the cast", function()
        band = { est = 15, lo = 5, hi = 40 }
        -- a hard cast in progress, 1 s left: the client's cast bar (the fake names every cast "Cast"; aliased to a
        -- cast-time ability so the reset finds it) delays the queue to the cast's end
        local abilities = H.Hekili.Class.abilities
        abilities.Cast = abilities.slam
        H.ctl.casting = { (t + 0.2 - 0.5) * 1000, (t + 0.2 + 1) * 1000 }
        local hk, at = H.Hekili, {}
        local predict = hk.GetNextPrediction
        hk.GetNextPrediction = function(...)
            at[#at + 1] = H.Hekili.State.offset
            return predict(...)
        end
        cycle()
        hk.GetNextPrediction, H.ctl.casting, abilities.Cast = predict, nil, nil
        assert.is_true(out.recs[1].time >= 1, "the cast did not delay the queue")
        -- the passes are the last calls: two per straddling record, at that record's time
        local want = {}
        for i = 1, math.min(2, out.count) do
            local c = out.recs[i].cost
            if c > 0 and band.lo < c and band.hi >= c then
                want[#want + 1] = out.recs[i].time
                want[#want + 1] = out.recs[i].time
            end
        end
        assert.is_true(#want > 0)
        for j = 1, #want do
            assert.is_true(
                math.abs(want[j] - at[#at - #want + j]) < 1e-6,
                ("pass %d at %.3f, want %.3f"):format(j, at[#at - #want + j], want[j])
            )
        end
        assert.are.same({}, H.errors)
    end)

    it("unsubscribing the need stops the passes: alts empty, the pick unchanged", function()
        band = { est = 15, lo = 5, hi = 40 }
        cycle()
        assert.are.equal(2, out.recs[1].alts.n)
        H.Hekili.Engine.Unsubscribe("Primary", need)
        assert.are.equal(0, out.needAlts)
        cycle()
        assert.are.equal("hamstring", out.recs[1].actionName)
        assert.are.equal(0, out.recs[1].alts.n)
    end)
end)
