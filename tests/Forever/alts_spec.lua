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

-- The seeds 1-3 gate on a fresh boot, the band widened in both runs (helpers/alts.lua); every Update of both instances appends its
-- Primary records (one string each). With `need`, a passive subscriber on Primary declares the need. Returns the
-- Update strings and how many records carried an alternative.
local function run(need)
    local L = loop.new(ww)
    local seen, withAlts = {}, 0
    for name, H in pairs({ us = L.us, oracle = L.oracle }) do
        local hk = H.Hekili
        alts.widen(H.ns.VirtualState)
        if need then
            assert.is_true(hk.Engine.Subscribe("Primary", function() end, true, { alts = true }))
        end
        local upd = hk.Update
        hk.Update = function(...)
            local r = upd(...)
            local p, recs = hk.Engine.Output.Primary, {}
            for i = 1, p.count do
                recs[i] = dump(p.recs[i])
                if p.recs[i].alts.n > 0 then
                    withAlts = withAlts + 1
                end
            end
            seen[#seen + 1] = name .. " " .. p.version .. " " .. table.concat(recs, ";")
            return r
        end
    end
    loop.tally(L, 3)
    return seen, withAlts
end

describe("alternatives: the main records never depend on them #slow", function()
    it("every field of recs[1..count] but alts is identical with the need off and on, over seeds 1-3", function()
        local off, offAlts = run(false)
        local on, onAlts = run(true)
        print(("\nalts invariant: %d Updates, records with alts: off %d, on %d"):format(#on, offAlts, onAlts))
        assert.are.equal(0, offAlts)
        assert.is_true(onAlts > 0, "no record carried an alternative: the passes never ran")
        assert.are.equal(#off, #on)
        for i = 1, #off do
            if off[i] ~= on[i] then
                assert.are.equal(off[i], on[i], "Update " .. i)
            end
        end
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

    it("a band that does not straddle the pick's cost yields none", function()
        band = { est = 15, lo = 12, hi = 20 }
        cycle()
        assert.are.equal("hamstring", out.recs[1].actionName)
        for i = 1, out.count do
            assert.are.equal(0, out.recs[i].alts.n, i)
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
