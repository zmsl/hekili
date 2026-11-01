-- tests/Forever/stream_spec.lua (border batch 2 Part B): the sim carries three streams per pool, the estimate
-- (`current`), the believed floor (`lo`) and ceiling (`hi`), moved by the same events (Engine/Sim/State.lua
-- forecastResources, resourceChange, advance). The reset seeds them from UnitPower's three slots, so lo <= current
-- <= hi holds everywhere a press gate asks (every TimeToReady, every forecast slice): the same deltas and clamps
-- keep the order. (Step 2 of the migration asserted equality here while one read seeded the three.) #loop
local loop = require("Game.harness.loop")

local WORLDS = {
    { "Forever.helpers.warrior_world", "Fury", "rage" }, -- swing-paid
    { "Forever.helpers.rogue_world", "Combat", "energy" },
    { "Forever.helpers.priest_world", "Smite", "mana" },
}

describe("the sim's resource streams (est, lo, hi) #loop", function()
    for _, w in ipairs(WORLDS) do
        it(("keep lo <= current <= hi at every press gate: %s"):format(w[3]), function()
            local world = require(w[1])
            local L = loop.new(w[2] and world[w[2]] or world)
            local S, class = L.us.Hekili.State, L.us.Hekili.Class
            local checks, bad = 0, nil
            local function check(k, r)
                local cur, lo, hi = r.current, r.lo, r.hi
                if not (lo <= cur and cur <= hi and r.actual_lo <= r.actual and r.actual <= r.actual_hi) then
                    bad = bad
                        or ("%s: current %s lo %s hi %s actual %s/%s/%s"):format(
                            k,
                            cur,
                            lo,
                            hi,
                            r.actual,
                            r.actual_lo,
                            r.actual_hi
                        )
                end
                for i = 1, r.fcount or 0 do
                    local f = r.forecast[i]
                    if not (f.l <= f.v and f.v <= f.h) then
                        bad = bad or ("%s slice %d (%s): v %s l %s h %s"):format(k, i, f.e, f.v, f.l, f.h)
                    end
                end
                checks = checks + 1
            end
            local orig = S.TimeToReady
            S.TimeToReady = function(self, ...)
                for k in pairs(class.resources) do
                    local r = rawget(S, k)
                    if r then
                        check(k, r)
                    end
                end
                return orig(self, ...)
            end
            loop.run(L, 1, { duration = 60 }, { { H = L.us } })
            S.TimeToReady = orig
            assert.is_true(checks > 1000, "too few gates checked: " .. checks)
            assert.is_nil(bad, bad)
        end)
    end

    -- The literal "dim never promote" invariant: every published record's floor sits at or under its estimate, under
    -- it at least once, and at or over the cost wherever the record carries one.
    for _, w in ipairs(WORLDS) do
        it(("publishes floors under the estimate and never under the cost: %s"):format(w[3]), function()
            local world = require(w[1])
            local L = loop.new(w[2] and world[w[2]] or world)
            local ns = L.us.ns
            local seen, under, over, short = 0, 0, 0, 0
            local function ann(_, rec)
                local rt = rec.resource_type
                local f, e = rt and rec.floors[rt], rt and rec.resources[rt]
                if f ~= nil and e ~= nil then
                    seen = seen + 1
                    if f < e then
                        under = under + 1
                    end
                    if f > e + 1e-9 then
                        over = over + 1
                    end
                    if rec.cost and rec.cost > 0 and f < rec.cost then
                        short = short + 1
                    end
                end
            end
            ns.Output.Annotate(ann)
            loop.run(L, 1, { duration = 60 }, { { H = L.us } })
            ns.Output.Unannotate(ann)
            assert.is_true(seen > 50, "records seen: " .. seen)
            assert.are.equal(0, over, "a floor above the estimate")
            assert.is_true(under > 0, "floors never under the estimate: do they read current?")
            assert.are.equal(0, short, "a record whose floor is under its cost")
        end)
    end
end)
