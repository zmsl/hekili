-- tools/wiki/collect/options.lua: the options a player sees under one node of the options tree (Hekili.Options, as
-- built in a headless boot), one row per option: its section, label, type, default (the option's own `get` on a
-- fresh profile), values and description. Spacers, headers and text-only rows are left out; so is an option hidden
-- for good (`hidden = true`). A conditional `hidden` (a function) is kept: the option shows in some states.
local boot = require("tools.wiki.boot")
local text = require("tools.wiki.text")

local M = {}

local SKIP_TYPES = { description = true, header = true }
local TYPE_NAMES = {
    toggle = "toggle",
    range = "slider",
    select = "choice",
    multiselect = "choices",
    input = "text",
    color = "colour",
    keybinding = "keybind",
    execute = "button",
}

local function call(v, info)
    if type(v) == "function" then
        local ok, r = pcall(v, info)
        return ok and r or nil
    end
    return v
end

-- The value `get` answers for `node` (inherited from its groups, as AceConfig does), or nil.
local function current(node, info, inherited)
    local get = node.get or inherited.get
    local handler = node.handler or inherited.handler
    if type(get) == "string" then
        if not handler or type(handler[get]) ~= "function" then
            return nil
        end
        local ok, r = pcall(handler[get], handler, info)
        if ok then
            return r
        end
    elseif type(get) == "function" then
        local ok, a, b, c = pcall(get, info)
        if node.type == "color" and ok and type(a) == "number" then
            return ("#%02X%02X%02X"):format(a * 255 + 0.5, b * 255 + 0.5, c * 255 + 0.5)
        end
        if ok then
            return a
        end
    end
end

local function valueList(node, info)
    local values = call(node.values, info)
    if type(values) ~= "table" then
        return nil, values
    end
    local keys = {}
    local sorting = call(node.sorting, info)
    if type(sorting) == "table" then
        for _, k in ipairs(sorting) do
            keys[#keys + 1] = k
        end
    else
        for k in pairs(values) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
    end
    return keys, values
end

local function shown(node, info, value)
    if value == nil then
        return nil
    end
    local t = node.type
    if t == "toggle" then
        return value and "On" or "Off"
    elseif t == "range" then
        local pct = node.isPercent and type(value) == "number"
        return pct and (text.num(value * 100, 1) .. "%") or text.num(value, 2)
    elseif t == "select" then
        local _, values = valueList(node, info)
        if type(values) == "table" and values[value] ~= nil then
            return text.strip(values[value])
        end
        return text.strip(value)
    elseif t == "multiselect" or type(value) == "table" then
        return nil
    end
    return text.strip(value)
end

local function range(node, info)
    local t = node.type
    if t == "range" then
        local lo, hi = node.softMin or node.min, node.softMax or node.max
        if node.isPercent then
            return ("%s%% to %s%%, step %s"):format(
                text.num((lo or 0) * 100, 1),
                text.num((hi or 1) * 100, 1),
                text.num((node.step or node.bigStep or 0.01) * 100, 1)
            )
        end
        return ("%s to %s, step %s"):format(text.num(lo, 2), text.num(hi, 2), text.num(node.step or node.bigStep, 2))
    elseif t == "select" or t == "multiselect" then
        local keys, values = valueList(node, info)
        if not keys then
            return nil
        end
        if #keys > 8 then
            return ("%d choices"):format(#keys)
        end
        local out = {}
        for _, k in ipairs(keys) do
            out[#out + 1] = text.strip(values[k])
        end
        return table.concat(out, "; ")
    end
end

-- The node at `path` under `root`, and the get/handler it inherits.
local function find(root, path)
    local node, inherited, info = root, {}, {}
    for _, key in ipairs(path) do
        inherited = { get = node.get or inherited.get, handler = node.handler or inherited.handler }
        local args = node.args or {}
        local child = args[key]
        for _, group in pairs(type(node.plugins) == "table" and node.plugins or {}) do
            child = child or group[key]
        end
        assert(child, "no option node " .. table.concat(path, "."))
        node = child
        info[#info + 1] = key
    end
    return node, { get = node.get or inherited.get, handler = node.handler or inherited.handler }, info
end

local function children(node)
    local out = {}
    for k, v in pairs(type(node.args) == "table" and node.args or {}) do
        out[#out + 1] = { k, v }
    end
    for _, group in pairs(type(node.plugins) == "table" and node.plugins or {}) do
        for k, v in pairs(group) do
            out[#out + 1] = { k, v }
        end
    end
    table.sort(out, function(a, b)
        local oa, ob = tonumber(a[2].order) or 100, tonumber(b[2].order) or 100
        if oa ~= ob then
            return oa < ob
        end
        return tostring(a[1]) < tostring(b[1])
    end)
    return out
end

local function walk(node, info, inherited, section, rows, o, depth)
    for _, kv in ipairs(children(node)) do
        local key, child = kv[1], kv[2]
        if not o.exclude[key] and type(child) == "table" and child.hidden ~= true then
            local ci = {}
            for i, s in ipairs(info) do
                ci[i] = s
            end
            ci[#ci + 1] = key
            ci.option, ci.options, ci.type = child, o.root, child.type
            local label = text.strip(call(child.name, ci))
            if o.rename then
                label = o.rename(label)
            end
            local inh = { get = child.get or inherited.get, handler = child.handler or inherited.handler }
            if child.type == "group" then
                if depth < o.depth then
                    local sub = label == "" and section or section ~= "" and (section .. " > " .. label) or label
                    walk(child, ci, inh, sub, rows, o, depth + 1)
                end
            elseif not SKIP_TYPES[child.type] and label ~= "" then
                local desc = call(child.desc, ci)
                local perSpec = o.perSpec[key]
                rows[#rows + 1] = {
                    key = key,
                    section = section,
                    label = label,
                    type = TYPE_NAMES[child.type] or child.type,
                    default = perSpec and "Set per specialization" or shown(child, ci, current(child, ci, inh)),
                    range = perSpec and "The specialization's own" or range(child, ci),
                    description = desc and (o.rename and o.rename(text.sentence(desc)) or text.sentence(desc)) or nil,
                }
            end
        end
    end
end

--- The rows under `def.path` (a list of keys; "<spec>" is the boot's first supported spec, "<pack>" that spec's
--- default priority), at most `def.depth` groups deep (default 3), leaving out the keys in `def.exclude`.
function M.rows(def)
    local H = boot.get(def.class)
    local kit = H.Hekili.Class.kit
    local spec
    for _, s in ipairs(kit and kit.trees or {}) do
        if not s.unsupported then
            spec = spec or s
        end
    end
    local function resolve(k)
        if k == "<spec>" then
            return spec.key
        elseif k == "<pack>" then
            return spec.options.package
        end
        return k
    end
    local path = {}
    for i, k in ipairs(def.path) do
        path[i] = resolve(k)
    end
    local root = H.Hekili.Options
    local node, inherited, info = find(root, path)
    local exclude = {}
    for _, k in ipairs(def.exclude or {}) do
        exclude[resolve(k)] = true
    end
    for _, s in ipairs(def.noSettings and spec.settings or {}) do
        exclude[s.name] = true -- the class settings (RegisterSetting): a table of their own
    end
    local name = spec and spec.name
    local perSpec = {}
    for _, k in ipairs(def.perSpec or {}) do
        perSpec[k] = true
    end
    local o = {
        root = root,
        exclude = exclude,
        perSpec = perSpec, -- keys whose default and values differ per spec: not one spec's
        depth = def.depth or 3,
        rename = name and function(s) -- the spec's own name reads as a placeholder: the table is every spec's
            return (s:gsub("%f[%w]" .. name:gsub("%p", "%%%0") .. "%f[%W]", "*your specialization*"))
        end,
    }
    local rows = {}
    walk(node, info, inherited, "", rows, o, 1)
    local top = text.strip(call(node.name, info)) -- an option straight under the node: its section is the node
    for _, r in ipairs(rows) do
        if r.section == "" then
            r.section = top
        end
    end
    return rows
end

--- Every option label of every class's tree (stripped), as a set: what a page may name in bold.
function M.labels()
    local out = {}
    local function visit(node, seen)
        if type(node) ~= "table" or seen[node] then
            return
        end
        seen[node] = true
        local name = call(node.name, {})
        if type(name) == "string" then
            out[text.strip(name)] = true
        end
        for _, kv in ipairs(children(node)) do
            visit(kv[2], seen)
        end
    end
    for _, token in ipairs(boot.tokens()) do
        visit(boot.get(token).Hekili.Options, {})
    end
    return out
end

return M
