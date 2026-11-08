-- tests/Forever/loop_steady_spec.lua: the steady icons (Engine/Output.lua, always on for players) on our instance
-- in the Fury L60 20-fight loop (#loop), reported, not gated: the engine's health only. Since CN8 they are on by
-- default, so this run matches loop_warrior_fury_spec.lua's; the flicker design study measured it as hold3 (first-icon
-- flicker 1.71 -> 0.93/min, presses, refusals and dps identical).
local fury_gate = require("Forever.helpers.fury_gate")
local loop = require("Game.harness.loop")
local pack_gate = require("Forever.helpers.pack_gate")

describe("the steady icons, reported #loop", function()
    it("Fury solo, level 60, one mob, 20 fights, steady icons on", function()
        local m = loop.tally(loop.new(fury_gate.content(60)), 20, { steady = true })
        local r, line = loop.summary(m), loop.line(m)
        print("\nFury L60 solo: " .. line .. " (reported)")
        pack_gate.health(m, r, line)
    end)
end)
