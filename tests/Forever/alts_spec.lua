-- tests/Forever/alts_spec.lua (display styles plan, Task 3c): alternatives under resource uncertainty. A subscriber
-- declaring needs = { alts = true } gets, on records 1 and 2, the picks the APL makes with the gating resource pinned
-- at the belief's low and high bound. The invariant first: the main records never depend on whether they were
-- computed (the seeds 1-3 Arms gate run twice in-process, the need off then on, every field but alts compared).
local loop = require("Game.harness.loop")
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local alts = require("Forever.helpers.alts")

-- One record as a string: every field but alts, nested tables (resources, belief) with sorted keys.
local function dump(v)
    if type(v) ~= "table" then
        return type(v) == "string" and ("%q"):format(v) or tostring(v)
    end
    local keys = {}
    for k in pairs(v) do
        if k ~= "alts" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = tostring(k) .. "=" .. dump(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local DISPLAYS = { "Interrupts", "Defensives", "Cooldowns", "Primary", "AOE" }

-- The seeds 1-3 gate on a fresh boot, the band widened in both runs (helpers/alts.lua), every display computed (each
-- subscribed, the toggles separate, the mode dual): a display following one whose passes ran (AOE after Primary, the
-- next Update's Interrupts after AOE) starts from whatever reset it gets. Every Update of both instances appends one
-- string of every display's records. With `need`, a passive subscriber on Primary and on AOE declares the need.
-- Returns the Update strings, how many records carried an alternative and, per display, how many Updates computed it.
local function run(need)
    local L = loop.new(ww)
    local seen, withAlts, computed = {}, 0, {}
    for _, d in ipairs(DISPLAYS) do
        computed[d] = 0
    end
    for name, H in pairs({ us = L.us, oracle = L.oracle }) do
        local hk = H.Hekili
        alts.widen(H.ns.VirtualState)
        local toggles = hk.DB.profile.toggles
        for _, k in ipairs({ "interrupts", "defensives", "cooldowns" }) do
            toggles[k].value, toggles[k].separate = true, true
        end
        toggles.mode.value = "dual"
        for _, d in ipairs(DISPLAYS) do
            assert.is_true(hk.Engine.Subscribe(d, function() end))
        end
        if need then
            assert.is_true(hk.Engine.Subscribe("Primary", function() end, true, { alts = true }))
            assert.is_true(hk.Engine.Subscribe("AOE", function() end, true, { alts = true }))
        end
        local upd, versions = hk.Update, {}
        hk.Update = function(...)
            local r = upd(...)
            local parts = { name }
            for _, d in ipairs(DISPLAYS) do
                local p = hk.Engine.Output[d]
                if p.version ~= versions[d] then
                    versions[d], computed[d] = p.version, computed[d] + 1
                end
                parts[#parts + 1] = d .. " " .. p.version
                for i = 1, p.count do
                    parts[#parts + 1] = dump(p.recs[i])
                    if p.recs[i].alts.n > 0 then
                        withAlts = withAlts + 1
                    end
                end
            end
            seen[#seen + 1] = table.concat(parts, ";")
            return r
        end
    end
    loop.tally(L, 3)
    return seen, withAlts, computed
end

describe("alternatives: the main records never depend on them #slow", function()
    it(
        "every display's recs[1..count], every field but alts, is identical with the need off and on, seeds 1-3",
        function()
            local off, offAlts = run(false)
            local on, onAlts, computed = run(true)
            local c = {}
            for _, d in ipairs(DISPLAYS) do
                c[#c + 1] = d .. " " .. computed[d]
            end
            print(
                ("\nalts invariant: %d Updates, records with alts: off %d, on %d; computed: %s"):format(
                    #on,
                    offAlts,
                    onAlts,
                    table.concat(c, ", ")
                )
            )
            for _, d in ipairs(DISPLAYS) do
                assert.is_true(computed[d] > 100, d .. " was not computed")
            end
            assert.are.equal(0, offAlts)
            assert.is_true(onAlts > 0, "no record carried an alternative: the passes never ran")
            assert.are.equal(#off, #on)
            for i = 1, #off do
                if off[i] ~= on[i] then
                    assert.are.equal(off[i], on[i], "Update " .. i)
                end
            end
        end
    )
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
