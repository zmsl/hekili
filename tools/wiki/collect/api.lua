-- tools/wiki/collect/api.lua: the content surface's Register* calls, from the source that defines them (the class kit's
-- mixin in Engine/Schema/Spec.lua and Spec/*.lua, the shared and race objects in Shared.lua and Races.lua): each call's
-- parameters as the source names them, which registration objects offer it, and which content addons call it.
local addons = require("helpers.addons")

local M = {}

local SCHEMA = "src/Hekili/Engine/Schema/"
-- the registration objects: their entry point and the files that define their calls
M.OBJECTS = {
    { name = "class", files = { "Spec.lua", "Spec/Abilities.lua", "Spec/Auras.lua", "Spec/Regen.lua" } },
    { name = "shared", files = { "Shared.lua" } },
    { name = "race", files = { "Races.lua" } },
}

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function params(list)
    list = list:gsub("^%s*self%s*,?%s*", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return list
end

--- { [call] = { params = "...", objects = { "class", ... } } } from the definitions.
function M.calls()
    local out = {}
    for _, o in ipairs(M.OBJECTS) do
        for _, file in ipairs(o.files) do
            local s = slurp(SCHEMA .. file)
            local function add(name, list)
                local c = out[name] or { objects = {} }
                c.params = c.params or params(list)
                if c.objects[#c.objects] ~= o.name then
                    c.objects[#c.objects + 1] = o.name
                end
                out[name] = c
            end
            for name, list in s:gmatch("\n%s*(Register%w+)%s*=%s*function%s*%(([^)]*)%)") do
                add(name, list)
            end
            for name, list in s:gmatch("\nfunction %w+:(Register%w+)%s*%(([^)]*)%)") do
                add(name, list)
            end
        end
    end
    return out
end

-- Every .lua file a content addon's TOC lists.
local function contentFiles(name)
    local out = {}
    for _, p in ipairs(addons.files(name)) do
        if p:match("%.lua$") then
            out[#out + 1] = p
        end
    end
    return out
end

--- Call, parameters, offered by, used by: one row per Register* call, by name.
function M.rows()
    local calls = M.calls()
    local users = {}
    for _, name in ipairs(addons.CONTENT) do
        for _, p in ipairs(contentFiles(name)) do
            local s = slurp(p)
            for call in s:gmatch(":(Register%w+)%s*%(") do
                users[call] = users[call] or {}
                users[call][name:gsub("^Hekili_", "")] = true
            end
        end
    end
    local names = {}
    for name in pairs(calls) do
        names[#names + 1] = name
    end
    table.sort(names)
    local rows = {}
    for _, name in ipairs(names) do
        local by = {}
        for _, a in ipairs(addons.CONTENT) do
            local short = a:gsub("^Hekili_", "")
            if users[name] and users[name][short] then
                by[#by + 1] = short
            end
        end
        local c = calls[name]
        rows[#rows + 1] = {
            "`" .. name .. "`",
            c.params ~= "" and ("`" .. c.params .. "`") or "n/a",
            table.concat(c.objects, ", "),
            #by > 0 and table.concat(by, ", ") or "n/a",
        }
    end
    return rows
end

return M
