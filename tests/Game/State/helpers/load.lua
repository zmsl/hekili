-- tests/Game/State/helpers/load.lua
-- Loads the VirtualState files headless, in Hekili.toc order, into a fresh `ns` (each spec gets its own module
-- state). Adapter.lua needs Hekili, so it loads only through `load.adapter`.
local M = {}

--- The addon root (what WoW loads), relative to the repository root; Hekili.toc paths are relative to it.
M.ROOT = "src/Hekili/"

--- The VirtualState files Hekili.toc lists, in order, as repository-relative paths (ROOT included).
function M.files()
    local out = {}
    for _, path in ipairs(require("helpers.addons").files("Hekili")) do
        if path:find("^" .. M.ROOT .. "Game/") then
            out[#out + 1] = path
        end
    end
    return out
end

--- Spec.lua's school enum (Engine/Schema loads after Game in Hekili.toc and needs Hekili, so a headless ns, or a fake
--- Hekili, takes the table from Spec.lua's own line: one source of truth).
function M.school()
    local src = assert(io.open(M.ROOT .. "Engine/Schema/Spec.lua")):read("*a")
    return assert(loadstring("return " .. assert(src:match("ns%.SCHOOL = (%b{})"))))()
end

--- A fresh ns with every VirtualState file but Adapter.lua loaded, `ns.SCHOOL` seeded as Spec.lua sets it.
function M.module()
    local ns = { SCHOOL = M.school() }
    for _, path in ipairs(M.files()) do
        if not path:match("Adapter%.lua$") then
            assert(loadfile(path))("Hekili", ns)
        end
    end
    local I = ns.VirtualStateInternal
    if I and I.Tickets then
        I.Tickets.EARLY = os.getenv("TA_EARLY") == "1" -- the EARLY variant's measurement (attribution-recovery Task 2)
    end
    return ns
end

--- Loads Adapter.lua into `ns` with `_G.Hekili` set to `hekili` (its State, Class) for the duration.
function M.adapter(ns, hekili)
    local saved = rawget(_G, "Hekili")
    _G.Hekili = hekili
    assert(loadfile(M.ROOT .. "Game/State/Adapter.lua"))("Hekili", ns)
    _G.Hekili = saved
end

return M
