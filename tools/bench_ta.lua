-- tools/bench_ta.lua (unit-registry spec §10): a headless microbenchmark of the unit registry and the ticket pool.
-- Feeds N synthetic rows (plate, target and soft tokens of one outcome, our successes and swings among them) through
-- the event facade into a booted VirtualState and times them, then times the per-frame tick. Prints rows/s, ms/row and
-- ms/tick; fails above 0.02 ms a row or 0.10 ms a tick, or below 0.8 x tools/bench_ta_floor.lua's rows/s.
-- Run: make bench-ta (or lua5.1 tools/bench_ta.lua [N]).
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

local api, ctl = fake.new()
for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
    _G[k] = v
end
local ns = load.module()
local I = ns.VirtualStateInternal
I.Build(fs.def(fs.new(9, false, false, true)), 0.1)
ns.VirtualState.Start(api)
local TOK = {}
for k = 1, 40 do
    TOK[k] = "nameplate" .. k
    ctl.guid[TOK[k]] = "Creature-" .. k
    ctl.Fire("NAME_PLATE_UNIT_ADDED", TOK[k])
end
ctl.guid.softenemy = "Creature-1"
local FAN = { "nameplate1", "target", "softenemy" }

local N = tonumber(arg and arg[1]) or 200000
local now = 10
collectgarbage("collect")
local t0 = os.clock()
for i = 1, N do
    now = now + 0.001
    ctl.now = now
    if i % 50 == 0 then
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
    elseif i % 37 == 0 then
        ctl.Fire("PLAYER_SWING", 2.0, 0)
    end
    local k = i % 3 + 1
    ctl.Fire("UNIT_COMBAT", FAN[k], "WOUND", "", 30 + i % 11, i % 7 == 0 and 4 or 1)
end
local row = (os.clock() - t0) / N

local M = 20000
local t1 = os.clock()
for _ = 1, M do
    now = now + 0.016
    ctl.Tick(now)
end
local tick = (os.clock() - t1) / M

local floor = dofile("tools/bench_ta_floor.lua").rowsPerSec
print(
    ("bench-ta rows=%d rows/s=%.0f ms/row=%.4f ms/tick=%.4f (floor rows/s %d)"):format(
        N,
        1 / row,
        row * 1000,
        tick * 1000,
        floor
    )
)
if row * 1000 >= 0.02 or tick * 1000 >= 0.10 or 1 / row < 0.8 * floor then
    print("bench-ta: over budget or under the floor")
    os.exit(1)
end
