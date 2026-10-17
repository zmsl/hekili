-- tests/Virtual/State/helpers/load.lua
-- Loads the VirtualState files headless, in Hekili.toc order, into a fresh `ns` (each spec gets its own module
-- state). Adapter.lua needs Hekili, so it loads only through `load.adapter`.
local M = {}

--- The addon root (what WoW loads), relative to the repository root; Hekili.toc paths are relative to it.
M.ROOT = "src/Hekili/"

--- The VirtualState files Hekili.toc lists, in order, as repository-relative paths (ROOT included).
function M.files()
    local out = {}
    for _, path in ipairs(require("helpers.addons").files("Hekili")) do
        if path:find("^" .. M.ROOT .. "Virtual/") then
            out[#out + 1] = path
        end
    end
    return out
end

--- A fresh ns with every VirtualState file but Adapter.lua loaded. `before(ns)` runs first (e.g. to set fakes).
function M.module()
    local ns = {}
    for _, path in ipairs(M.files()) do
        if not path:match("Adapter%.lua$") then
            assert(loadfile(path))("Hekili", ns)
        end
    end
    return ns
end

--- Loads Adapter.lua into `ns` with `_G.Hekili` set to `hekili` (its State, Class) for the duration.
function M.adapter(ns, hekili)
    local saved = rawget(_G, "Hekili")
    _G.Hekili = hekili
    assert(loadfile(M.ROOT .. "Virtual/State/Adapter.lua"))("Hekili", ns)
    _G.Hekili = saved
end

return M
