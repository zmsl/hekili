-- tests/Game/State/helpers/load.lua
-- Loads the VirtualState files headless, in Hekili.toc order, into a fresh `ns` (each spec gets its own module
-- state). The core's build of the tracked set (Engine/Schema/Tracked.lua) needs Hekili, so it loads only through
-- `load.schema`.
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

--- Spec.lua's school enum, as a hand-built `def.school` (Engine/Schema loads after Game in Hekili.toc and needs
--- Hekili, so a fake takes the table from Spec.lua's own line: one source of truth). Read once.
local school
function M.school()
    if not school then
        local src = assert(io.open(M.ROOT .. "Engine/Schema/Spec.lua")):read("*a")
        school = assert(loadstring("return " .. assert(src:match("ns%.SCHOOL = (%b{})"))))()
    end
    return school
end

--- A fresh ns with every VirtualState file but Adapter.lua loaded.
function M.module()
    local ns = {}
    for _, path in ipairs(M.files()) do
        if not path:match("Adapter%.lua$") then
            assert(loadfile(path))("Hekili", ns)
        end
    end
    return ns
end

--- A game constant as Engine/Sim/Constants.lua defines it (`ns.FSR`, `ns.GCD_SPELL`, `ns.ORACLE_MIN`), read from its
--- own line: the one definition; a hand-built `def` carries them as the core's build does.
local constants = {}
function M.constant(name)
    if constants[name] == nil then
        local src = assert(io.open(M.ROOT .. "Engine/Sim/Constants.lua")):read("*a")
        constants[name] = assert(tonumber(src:match("\nns%." .. name .. " = ([%d%.]+)")), name)
    end
    return constants[name]
end

--- Loads the core's build of the tracked set (Engine/Schema/Tracked.lua: `ns.BuildTracked`, `ns.TrackPassive`) into
--- `ns` with `_G.Hekili` set to `hekili` (its State, Class) for the duration; `ns.SCHOOL` seeded as Spec.lua sets it.
function M.schema(ns, hekili)
    local saved = rawget(_G, "Hekili")
    _G.Hekili = hekili
    ns.SCHOOL = ns.SCHOOL or M.school()
    ns.FSR, ns.GCD_SPELL = ns.FSR or M.constant("FSR"), ns.GCD_SPELL or M.constant("GCD_SPELL")
    ns.ORACLE_MIN = ns.ORACLE_MIN or M.constant("ORACLE_MIN")
    assert(loadfile(M.ROOT .. "Engine/Schema/Tracked.lua"))("Hekili", ns)
    _G.Hekili = saved
end

return M
