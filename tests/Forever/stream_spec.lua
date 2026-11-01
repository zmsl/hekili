-- tests/Forever/stream_spec.lua (border batch 2 Part B): the sim carries three streams per pool, the estimate
-- (`current`), the believed floor (`lo`) and ceiling (`hi`), moved by the same events (Engine/Sim/State.lua
-- forecastResources, resourceChange, advance). Step 2 of the migration: the reset still seeds the three from one
-- read, so they are equal everywhere a press gate asks (every TimeToReady, every forecast slice): a site left on a
-- stale stream shows here before the reset splits them. #loop
local loop = require("Game.harness.loop")

local WORLDS = {
    { "Forever.helpers.warrior_world", "Fury", "rage" }, -- swing-paid
    { "Forever.helpers.rogue_world", "Combat", "energy" },
    { "Forever.helpers.priest_world", "Smite", "mana" },
}

describe("the sim's resource streams (est, lo, hi) #loop", function()
    for _, w in ipairs(WORLDS) do
        it(("stay equal at every press gate: %s"):format(w[3]), function()
            local world = require(w[1])
            local L = loop.new(w[2] and world[w[2]] or world)
            local S, class = L.us.Hekili.State, L.us.Hekili.Class
            local checks, bad = 0, nil
            local function check(k, r)
                local cur, lo, hi = r.current, r.lo, r.hi
                if cur ~= lo or lo ~= hi or r.actual ~= r.actual_lo or r.actual ~= r.actual_hi then
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
                    if f.v ~= f.l or f.v ~= f.h then
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
end)
