-- tests/Game/State/memory_spec.lua (unit-registry spec §10): the registry, the ticket pool and the kinds are fixed
-- pools allocated at load; their resident memory stays under a ceiling. Measured at the first load, in Hekili.toc
-- order (a reload into a loaded ns frees the old Kinds and nets about 0 for it): measured 149.2 KB on 2026-10-23
-- (about Units 56, Tickets 71, Melee 14, Kinds 8). Measured + 25% would be 192 KB; the ceiling stays at the
-- brief's 160 KB until the owner rules.
local load = require("Game.State.helpers.load")

local FOUR = { ["Units.lua"] = true, ["Tickets.lua"] = true, ["Melee.lua"] = true, ["Kinds.lua"] = true }

describe("the registry's and tickets' resident memory", function()
    it("stays under its ceiling", function()
        local ns, kb = { SCHOOL = load.school() }, 0
        for _, path in ipairs(load.files()) do
            if not path:match("Adapter%.lua$") then
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
        end
        print(("\nregistry + tickets + kinds resident: %.1f KB"):format(kb))
        assert.is_true(kb < 160, ("%.1f KB"):format(kb))
    end)
end)
