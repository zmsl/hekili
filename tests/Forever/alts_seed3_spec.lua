-- tests/Forever/alts_seed3_spec.lua: the alternatives invariant on Arms gate fights 2 and 3 on one boot, so fight 3
-- runs on the state fight 2 left (helpers/alts.lua); split out of alts_spec.lua (seed 1 and the scripted-band tests).
local alts = require("Forever.helpers.alts")

describe("alternatives: the main records never depend on them #slow", function()
    it(
        "every display's recs[1..count], every field but alts, is identical with the need off and on, seeds 2-3",
        function()
            alts.invariant(2, 2)
        end
    )
end)
