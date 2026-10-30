-- tests/Forever/helpers/alts.lua (display styles plan, Task 3c): widens the belief band the alternative passes read,
-- and the alternatives invariant (alts_spec.lua, alts_seed2_spec.lua, alts_seed3_spec.lua): the main records never
-- depend on whether the alternatives were computed.
local assert = require("luassert")
local loop = require("Game.harness.loop")
local ww = require("Forever.helpers.warrior_world")

local M = {}

--- `VS.Power` answers with the high bound raised by 40 (capped at 100): in the Arms fights rage's band is otherwise
--- zero, so no pass would run. The low bound (all the client facade's UnitPower reads, so the main records) and the
--- estimate are unchanged. One preallocated answer: nothing is allocated per call.
function M.widen(VS)
    local power, fake = VS.Power, { est = 0, lo = 0, hi = 0, conf = 0 }
    VS.Power = function(pt, now)
        local r = power(pt, now)
        fake.est, fake.lo, fake.hi, fake.conf = r.est, r.lo, math.min(100, r.hi + 40), r.conf
        return fake
    end
end

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

-- Fight `seed` of the Arms gate on a fresh boot (traced, as the gate's first fight, when it is seed 1), the band
-- widened in both runs (M.widen), every display computed (each subscribed, the toggles separate, the mode dual): a
-- display following one whose passes ran (AOE after Primary, the next Update's Interrupts after AOE) starts from
-- whatever reset it gets. Every Update of both instances appends one
-- string of every display's records. With `need`, a passive subscriber on Primary and on AOE declares the need.
-- Returns the Update strings, how many records carried an alternative and, per display, how many Updates computed it.
local function run(need, seed)
    local L = loop.new(ww)
    local seen, withAlts, computed = {}, 0, {}
    for _, d in ipairs(DISPLAYS) do
        computed[d] = 0
    end
    for name, H in pairs({ us = L.us, oracle = L.oracle }) do
        local hk = H.Hekili
        M.widen(H.ns.VirtualState)
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
    loop.tally(L, 1, { seed0 = seed - 1, trace = seed == 1 })
    return seen, withAlts, computed
end

--- The invariant on Arms gate fight `seed` (split one seed a file from the seeds 1-3 run so the parallel runner
--- spreads them): every display's recs[1..count], every field but alts, identical with the need off and on.
function M.invariant(seed)
    local off, offAlts = run(false, seed)
    local on, onAlts, computed = run(true, seed)
    local c = {}
    for _, d in ipairs(DISPLAYS) do
        c[#c + 1] = d .. " " .. computed[d]
    end
    print(
        ("\nalts invariant, seed %d: %d Updates, records with alts: off %d, on %d; computed: %s"):format(
            seed,
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

return M
