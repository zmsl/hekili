-- tests/Forever/alts_seed2_spec.lua: the alternatives invariant on Arms gate fight 2 (helpers/alts.lua), one fight a
-- file so the parallel runner spreads them; split out of alts_spec.lua (seed 1 and the scripted-band tests).
local alts = require("Forever.helpers.alts")

describe("alternatives: the main records never depend on them #slow", function()
    it("every display's recs[1..count], every field but alts, is identical with the need off and on, seed 2", function()
        alts.invariant(2)
    end)
end)
