-- tests/Forever/wowsims_dry_spec.lua (re-pin plan, Task 2): tools/wowsims/dry.lua's omitted breakdown by node kind.
local dry = assert(loadfile("tools/wowsims/dry.lua"))()

describe("wowsims dry run", function()
    it("breaks the omitted entries down by the omit reason's node kind", function()
        assert.are.equal(
            "[sequence=1 wait=2 waitUntil=1 move=1 other=4]",
            dry.kinds({
                "precombat #3: move",
                "default #10: resetSequence",
                "default #11: sequence",
                "default #12: never",
                "weave #2: wait",
                "weave #3: wait",
                "walk_in #2: waitUntil",
                "default #16: unitDistance OpNe max(13.19,11.67)",
                "default: empty group weave",
            })
        )
    end)
end)
