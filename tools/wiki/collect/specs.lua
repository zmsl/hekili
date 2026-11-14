-- tools/wiki/collect/specs.lua: what each class pack declares per specialization, read from the booted kits
-- (Hekili:NewClass, RegisterSetting, RegisterPack): the specializations and their priorities, each spec's default
-- Enemy Range Radius, and the class settings.
local boot = require("tools.wiki.boot")
local text = require("tools.wiki.text")

local M = {}

local function className(token)
    return token:sub(1, 1) .. token:sub(2):lower()
end

-- Every class's kit specs, in load order: { class, H, spec } per spec.
local function each()
    local out = {}
    for _, token in ipairs(boot.tokens()) do
        local H = boot.get(token)
        local kit = H.Hekili.Class.kit
        for _, s in ipairs(kit and kit.trees or {}) do
            out[#out + 1] = { class = className(token), H = H, spec = s }
        end
    end
    return out
end

-- Rows that differ only in the specialization are joined: "Arms, Fury".
local function joinSpecs(rows, specCol)
    local out, at = {}, {}
    for _, r in ipairs(rows) do
        local parts = {}
        for i, v in ipairs(r) do
            if i ~= specCol then
                parts[#parts + 1] = tostring(v)
            end
        end
        local k = table.concat(parts, "\1")
        if at[k] then
            local o = out[at[k]]
            o[specCol] = o[specCol] .. ", " .. r[specCol]
        else
            out[#out + 1] = r
            at[k] = #out
        end
    end
    return out
end

--- Class, specializations, default radius (yards), per supported spec.
function M.nameplate()
    local rows = {}
    for _, e in ipairs(each()) do
        if not e.spec.unsupported then
            local p = e.H.Hekili.DB.profile.specs[e.spec.id]
            rows[#rows + 1] = { e.class, e.spec.name, text.num(p.nameplateRange) }
        end
    end
    return joinSpecs(rows, 2)
end

--- Class, specialization, default priority, the other built-in priorities ("n/a": none), per spec.
function M.packs()
    local rows = {}
    for _, e in ipairs(each()) do
        local s = e.spec
        if s.unsupported then
            rows[#rows + 1] = { e.class, s.name, "None: no priorities on Forever", "n/a" }
        else
            local default = s.options.package
            local others = {}
            for name, p in pairs(e.H.Hekili.DB.profile.packs) do
                if p.builtIn and p.spec == s.id and name ~= default then
                    others[#others + 1] = name
                end
            end
            table.sort(others)
            rows[#rows + 1] = { e.class, s.name, default, #others > 0 and table.concat(others, ", ") or "n/a" }
        end
    end
    return rows
end

--- The class settings (RegisterSetting) per spec: class, specializations, label, key, type, default, description.
function M.settings()
    local rows = {}
    for _, e in ipairs(each()) do
        for _, st in ipairs(e.spec.settings or {}) do
            local info = st.info
            local name = type(info.name) == "function" and info.name() or info.name
            local desc = type(info.desc) == "function" and info.desc() or info.desc
            local default = st.default
            if info.type == "toggle" then
                default = default and "On" or "Off"
            elseif info.type == "select" and type(info.values) == "table" then
                default = text.strip(info.values[default])
            else
                default = text.num(default, 2)
            end
            local kind = ({ toggle = "toggle", range = "slider", select = "choice" })[info.type] or info.type
            rows[#rows + 1] = {
                e.class,
                e.spec.name,
                text.strip(name),
                text.code(st.name),
                kind,
                default,
                desc and text.sentence(desc) or nil,
            }
        end
    end
    return joinSpecs(rows, 2)
end

return M
