-- tests/helpers/addons.lua
-- The addons this repository ships, in dependency order, each with its root and TOC: the one list every headless
-- loader, spec and tool reads its files from (restructure plan, Task 8). `lua5.1 tests/helpers/addons.lua lua` prints
-- every listed .lua path, in load order, for the shell tools. Pattern after Taco Dog Forever's tests/helpers/load.lua
-- (file lists read from each addon's TOC).
local M = {}

M.CORE = "Hekili"
-- the shared content (a dependency of every class pack), then the class packs; all load-on-demand, loaded by the
-- core's Engine/Content.lua in this order
M.CONTENT = {
    "Hekili_Shared",
    "Hekili_Warrior",
    "Hekili_Druid",
    "Hekili_Rogue",
    "Hekili_Paladin",
    "Hekili_Shaman",
    "Hekili_Hunter",
}
M.ADDONS = { M.CORE }
for _, name in ipairs(M.CONTENT) do
    M.ADDONS[#M.ADDONS + 1] = name
end

--- The class pack addon of a class ("Warrior": Hekili_Warrior) and its one file.
function M.pack(class)
    return "Hekili_" .. class
end
function M.classFile(class)
    return M.root(M.pack(class)) .. class .. ".lua"
end

--- The addon's folder, repository-relative, with its trailing slash.
function M.root(name)
    return "src/" .. name .. "/"
end

--- The addon's TOC path.
function M.toc(name)
    return M.root(name) .. name .. ".toc"
end

--- The files the addon's TOC lists, in order, as repository-relative paths (.xml lines too).
function M.files(name)
    local out = {}
    for line in io.lines(M.toc(name)) do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            out[#out + 1] = M.root(name) .. line:gsub("\\", "/")
        end
    end
    return out
end

--- The TOC's `## Key: value` fields.
function M.meta(name)
    local out = {}
    for line in io.lines(M.toc(name)) do
        local k, v = line:gsub("\r", ""):match("^## ([%w%-]+):%s*(.-)%s*$")
        if k then
            out[k] = v
        end
    end
    return out
end

--- Every .lua file of the addons `names` (default: all, in dependency order).
function M.lua(names)
    local out = {}
    for _, name in ipairs(names or M.ADDONS) do
        for _, path in ipairs(M.files(name)) do
            if path:match("%.lua$") then
                out[#out + 1] = path
            end
        end
    end
    return out
end

if ... == "lua" then
    for _, path in ipairs(M.lua()) do
        print(path)
    end
end

return M
