-- tools/wiki/collect/expressions.lua: the expressions a priority line can test. The keys of a root come from a scan of
-- its metatable's __index branches in Engine/Sim/State.lua (`k == "lo"`, `k:sub(1, 8) == "time_to_"`: keys are
-- branches in a function, so nothing can list them at runtime); their meanings from the hand-written
-- docs/wiki/data/expressions.lua. The check runs both ways: a scanned key with no entry fails, and so does an entry
-- that no longer evaluates in a booted state (it raises or answers nil) or whose example no longer compiles.
local boot = require("tools.wiki.boot")
local text = require("tools.wiki.text")

local M = {}

M.STATE = "src/Hekili/Engine/Sim/State.lua"
M.DATA = "docs/wiki/data/expressions.lua"
M.N = "40" -- what a <N> in a key stands for when it is evaluated

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

--- The keys of metatable `mt` (its name in State.lua) as "<prefix>.<key>", a key read by prefix as "<key><N>".
function M.scan(source, mt, prefix)
    local body = source:match("\nlocal " .. mt .. " = {(.-)\nns%.metatables%." .. mt .. " = " .. mt)
    assert(body, M.STATE .. ": no " .. mt .. " block")
    local keys = {}
    for k in body:gmatch("k%s*==%s*[\"']([%w_]+)[\"']") do
        keys[prefix .. "." .. k] = true
    end
    for n, k in body:gmatch("k:sub%(%s*1,%s*(%d+)%s*%)%s*==%s*[\"']([%w_]+)[\"']") do
        assert(#k == tonumber(n), mt .. ": " .. k .. " is not " .. n .. " characters")
        keys[prefix .. "." .. k .. "<N>"] = true
    end
    return keys
end

-- The data file, its <N> placeholder written either way.
local function data()
    return dofile(M.DATA)
end

-- The value of `key` in state H.Hekili.State, `<resource>` read as `resource`, <N> as M.N.
local function value(H, key, resource)
    local path = key:gsub("<resource>", resource):gsub("<N>", M.N)
    local v = H.Hekili.State
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then
            return nil, path .. ": " .. part .. " of a " .. type(v)
        end
        local ok, r = pcall(function()
            return v[part]
        end)
        if not ok then
            return nil, path .. " raises: " .. tostring(r)
        end
        v = r
    end
    return v, path
end

-- A resource the booted class has, chosen generically: the first (by name) state table with the resource metatable
-- that keeps a band (the hidden resources do), else the first.
local function aResource(H)
    local mt = H.ns.metatables.mt_resource
    local names = {}
    for k, v in pairs(H.Hekili.State) do
        if type(k) == "string" and type(v) == "table" and getmetatable(v) == mt then
            names[#names + 1] = k
        end
    end
    table.sort(names)
    for _, k in ipairs(names) do
        if rawget(H.Hekili.State[k], "actual_lo") ~= nil then
            return k
        end
    end
    return names[1]
end

--- Problems (strings) for table `def` (a manifest entry): scanned keys without an entry, entries that do not
--- evaluate, examples that do not compile. `H` (a booted instance), `scanned` and `d` (the data) default to the real
--- ones; the tests pass their own.
function M.problems(def, H, scanned, d)
    H = H or boot.get(def.class)
    d = d or data()
    local out = {}
    if def.root and not H.ns.metatables[def.root] then -- the root as the running code exports it
        out[#out + 1] = ("tools/wiki/manifest.lua: %s is not in ns.metatables"):format(def.root)
    end
    if def.root then
        scanned = scanned or M.scan(slurp(M.STATE), def.root, def.prefix)
        for k in pairs(scanned) do
            if not d[k] then
                out[#out + 1] = ("%s: %s (scanned in %s) has no entry"):format(M.DATA, k, def.root)
            end
        end
    end
    local resource = aResource(H)
    for _, k in ipairs(M.keys(def, d)) do
        local e = d[k]
        if not e then
            out[#out + 1] = ("%s: %s has no entry"):format(M.DATA, k)
        elseif not e.omit then
            local v, why = value(H, k, resource)
            if v == nil then
                out[#out + 1] = ("%s: %s does not evaluate (%s)"):format(M.DATA, k, why)
            end
            if e.example then
                -- an example names one class's resource: it must compile and run in at least one class's boot
                local err
                for _, token in ipairs(boot.tokens()) do
                    local s = boot.get(token).Hekili.Scripts
                        .ConvertScript({ action = "wait", criteria = e.example }, false, "wiki:" .. k)
                    err = s.Error
                    if not err then
                        break
                    end
                end
                if err then
                    out[#out + 1] = ("%s: %s's example %s does not compile: %s"):format(M.DATA, k, e.example, err)
                end
            end
        end
    end
    table.sort(out)
    return out
end

--- The documented keys of table `def`, in its order: def.keys, or the entries under def.prefix (by def.order or
--- name), omitted ones left out.
function M.keys(def, d)
    if def.keys then
        return def.keys
    end
    d = d or data()
    local out = {}
    for k, e in pairs(d) do
        if k:sub(1, #def.prefix + 1) == def.prefix .. "." and not e.omit then
            out[#out + 1] = k
        end
    end
    local rank = {}
    for i, k in ipairs(def.order or {}) do
        rank[def.prefix .. "." .. k] = i
    end
    table.sort(out, function(a, b)
        local ra, rb = rank[a] or 1e9, rank[b] or 1e9
        if ra ~= rb then
            return ra < rb
        end
        return a < b
    end)
    return out
end

--- Expression, type, meaning, on Forever, example: one row per documented key.
function M.rows(def)
    local d = data()
    local rows = {}
    for _, k in ipairs(M.keys(def)) do
        local e = d[k]
        rows[#rows + 1] = {
            text.code(k),
            e.type,
            e.meaning,
            e.forever,
            e.example and text.code(e.example) or nil,
        }
    end
    return rows
end

return M
