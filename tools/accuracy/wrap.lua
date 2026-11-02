-- tools/accuracy/wrap.lua: a busted --helper for `make accuracy` (tools/accuracy/run.sh). It changes no gate: it
-- wraps the helpers the existing specs call so one run of them prints the structured ACC lines the report reads.
--   pack_gate.solo, 20+ fights: the spec's own call becomes three seed sets (seeds 1-20, 21-40, 41-60), one
--     "ACC loop\t<label>\t<set>\t<loop line>\t<agreed>/<ticks>" each; the first set is returned to the spec.
--   wowsims.gate / wowsims.ready: print the replay floor and the ready-time floor beside the lines they print.
local pack_gate = require("Forever.helpers.pack_gate")
local loop = require("Game.harness.loop")
local ws = require("Forever.helpers.wowsims")

local solo = pack_gate.solo
function pack_gate.solo(label, world, n, seed0, ...)
    if n < 20 then
        return solo(label, world, n, seed0, ...)
    end
    local r1, line1, m1
    for set = 0, 2 do
        local m = loop.tally(loop.new(world), n, { seed0 = (seed0 or 0) + n * set })
        local line = loop.line(m)
        print(("\nACC loop\t%s\t%d\t%s\t%d/%d"):format(label, set + 1, line, m.agree, m.both)) -- unrounded agreement
        if set == 0 then
            r1, line1, m1 = loop.summary(m), line, m
        end
    end
    -- crowded target (reported only): seeds 1-20 again with 39 other sources on our target, the mix of
    -- tests/Game/harness/group_spec.lua's raid case. The others' damage would kill a finite-health target in a
    -- pull, so the target's health is scaled (two pilot runs of 2 fights, H *= solo ticks / crowded ticks) until
    -- a crowded fight lasts about as long as the solo one; the ratio of the ticks is printed beside the line.
    local others = {}
    for i = 1, 39 do
        others[i] = ({ "melee", "melee", "caster", "pet", "ranged", "melee" })[i % 6 + 1]
    end
    local function ticks(m)
        return tonumber(loop.line(m):match("%((%d+) ticks%)"))
    end
    local soloPerFight = ticks(m1) / n
    local health = loop.new(world).content.WORLD.mobHealth
    if health < 1e8 then -- a world with a finite target; 1e9 runs to the duration cap as it is
        for _ = 1, 2 do
            local pilot = loop.tally(loop.new(world), 2, { seed0 = seed0 or 0, others = others, mobHealth = health })
            health = health * soloPerFight / math.max(1, ticks(pilot) / 2)
        end
    end
    local m = loop.tally(loop.new(world), n, { seed0 = seed0 or 0, others = others, mobHealth = health })
    print(("\nACC crowd\t%s\t1\t%s\t%.3f\t%.0f"):format(label, loop.line(m), ticks(m) / ticks(m1), health))
    return r1, line1
end

local gate = ws.gate
function ws.gate(label, C, spec, floor, ...)
    print(("\nACC floor\t%s\t%s\t%s"):format(label, spec, tostring(floor)))
    return gate(label, C, spec, floor, ...)
end

local ready = ws.ready
function ws.ready(label, spec, R)
    local f = ws.READY[spec] or {}
    print(("\nACC ready-floor\t%s\t%s\t%s\t%s"):format(label, spec, tostring(f[1]), tostring(f[2])))
    return ready(label, spec, R)
end
