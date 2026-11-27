-- tests/Game/State/memory_spec.lua (unit-registry spec §10): the registry, the ticket pool and the kinds are fixed
-- pools allocated at load; their resident memory stays under a ceiling. Measured at the first load, in Hekili.toc
-- order (a reload into a loaded ns frees the old Kinds and nets about 0 for it): measured 149.2 KB on 2026-10-23
-- (about Units 56, Tickets 71, Melee 14, Kinds 8). Ceiling 192 KB = measured + 25% rounded up to 8 KB (owner
-- ruling 2026-10-23: more memory is fine). Refactor lane 9 (Pr-2) moved Rows.lua's claim arrays into Tickets (the same
-- memory, counted here now): 188.9 KB at the base 0de708b0a, 207.6 KB with the lane. Ceiling 216 KB until the owner
-- rules (216 or 224, ledger L1995): one constant.
local load = require("Game.State.helpers.load")

local CEILING_KB = 216

local FOUR = { ["Units.lua"] = true, ["Tickets.lua"] = true, ["Melee.lua"] = true, ["Kinds.lua"] = true }

describe("the registry's and tickets' resident memory", function()
    it("stays under its ceiling", function()
        local ns, kb = { SCHOOL = load.school() }, 0
        for _, path in ipairs(load.files()) do
            local mine = FOUR[path:match("[^/]+$")] and path:match("([^/]+)%.lua$")
            collectgarbage("collect")
            collectgarbage("collect")
            local before = collectgarbage("count")
            assert(loadfile(path))("Hekili", ns)
            if mine then
                collectgarbage("collect")
                collectgarbage("collect")
                local d = collectgarbage("count") - before
                print(("\n%s resident: %.1f KB"):format(mine, d))
                kb = kb + d
            end
        end
        print(("\nregistry + tickets + kinds resident: %.1f KB"):format(kb))
        assert.is_true(kb < CEILING_KB, ("%.1f KB"):format(kb))
    end)
end)
