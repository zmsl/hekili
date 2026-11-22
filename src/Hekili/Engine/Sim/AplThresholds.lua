-- Engine/Sim/AplThresholds.lua
-- The APL threshold harvest (LibHiddenValues integration design 3.1-3.4, lane B7): a resource the client hides reads
-- at 1% from the band library, and a priority's own whole-number thresholds can be watched exactly as points. A
-- load-time text scan beside AplWarnings.lua: Hekili:LoadScript runs ns.AplThresholds over an entry's texts and keeps
-- the records on its script (`Bands`); scripts:PackBands unions them over a priority; the active priority's go to the
-- belief through def (Tracked.lua ns.SetAplBands). Pure Lua, no belief state, no client read. Allocates: load only.

local addon, ns = ...
local Hekili = _G[addon]
local ceil = math.ceil

-- The library's distinct points per power value (LibHiddenValues POINTS_PER_SOURCE; a contract spec pins the two).
-- Over it the library refuses the whole list, so Hekili sends none for that resource and its editor warns.
ns.APL_POINT_CAP = 8

-- operator -> the operator with its sides swapped (`40<=energy` is `energy>=40`)
local FLIP = { [">="] = "<=", [">"] = "<", ["<"] = ">", ["<="] = ">=", ["="] = "=", ["=="] = "==", ["!="] = "!=", ["~="] = "~=" }
local HEALTH = {
    ["health.pct"] = "health",
    ["health.percent"] = "health",
    ["target.health.pct"] = "target.health",
    ["target.health.percent"] = "target.health",
    ["target.health_pct"] = "target.health",
}
local RES_KIND = { [""] = "points", current = "points", actual = "points", deficit = "deficit", pct = "pct", percent = "pct" }

local function add(out, key, kind, n)
    out[#out + 1] = { key = key, kind = kind, n = n }
    return 1
end

-- A bar answers "at least p" in whole points. The points that decide `x <op> N` for a whole-valued x: >= N and < N at
-- N, > N and <= N at N + 1, = and != at both; a fractional N at ceil(N) under every ordering operator (x > 40.5 is
-- x >= 41), and = or != never bound a whole value. `shift` -1 gives deficit's n (the point max - n): d >= N is
-- "not d <= N - 1".
local function points(out, key, kind, op, N, shift)
    local lo = shift == 0 and 1 or 0 -- a point below 1 (a deficit n below 0) is always true: no bar
    local p
    if N % 1 ~= 0 then
        if op == "=" or op == "==" or op == "!=" or op == "~=" then
            return 0
        end
        p = ceil(N)
    elseif op == ">=" or op == "<" then
        p = N
    elseif op == ">" or op == "<=" then
        p = N + 1
    else
        local c = 0
        if N + shift >= lo then
            c = add(out, key, kind, N + shift)
        end
        return c + add(out, key, kind, N + 1 + shift)
    end
    if p + shift < lo then
        return 0
    end
    return add(out, key, kind, p + shift)
end

local function leafRecords(leaf, resources, out)
    local tok, op, num = leaf:match("^([%a_][%w_%.]*)([<>=!~]+)([%d%.]+)$")
    if not tok then
        num, op, tok = leaf:match("^([%d%.]+)([<>=!~]+)([%a_][%w_%.]*)$")
        op = op and FLIP[op]
    end
    local N = tonumber(num)
    if not (tok and N and FLIP[op]) then
        return 0
    end
    local health = HEALTH[tok]
    if health then
        return add(out, health, "pct", N)
    end
    local ttp = tok:match("^target%.time_to_pct_(%d+)$")
    if ttp then
        return add(out, "target.health", "pct", tonumber(ttp))
    end
    if tok:match("^d?e?buff%.[%w_]+%.stack$") or tok:match("^d?e?buff%.[%w_]+%.remains$") or tok:match("^dot%.[%w_]+%.remains$") then
        return add(out, tok, "aura", N)
    end
    local base, suffix = tok:match("^([%w_]+)%.?(.*)$")
    local kind = resources[base] and RES_KIND[suffix]
    if kind == "pct" then
        return add(out, base, kind, N)
    elseif kind then
        return points(out, base, kind, op, N, kind == "deficit" and -1 or 0)
    end
    return 0
end

--- Appends a { key, kind, n } record to `out` for each comparison in `condition` of a known token with a number
--- literal; returns how many it added. key: a key of `resources` (a set of resource keys), "health", "target.health"
--- or an aura token (`buff.<k>.stack`, ..., for lane C4); kind "points" (n a point), "deficit" (n with the point
--- max - n), "pct" (n the percent as written: health, and a resource's, whose point the belief computes) or "aura" (n
--- as written). Not a string: 0. Expressions (`energy>=action.x.cost+10`) and spender costs are not harvested.
---@param condition any
---@param resources table
---@param out table
---@return integer
function ns.AplThresholds(condition, resources, out)
    if type(condition) ~= "string" then
        return 0
    end
    local text = condition:gsub("%s+", "")
    if text == "" then
        return 0
    end
    local n = 0
    for _, leaf in ipairs(Hekili.Scripts:SplitExpr(text)) do
        local prev
        repeat -- a leading ! and the parentheses around the whole leaf
            prev = leaf
            leaf = leaf:gsub("^!+", "")
            if leaf:match("^%b()$") then
                leaf = leaf:sub(2, -2)
            end
        until leaf == prev
        n = n + leafRecords(leaf, resources, out)
    end
    return n
end

--- A resource's distinct exact points in a priority (scripts:PackBands' entry): every one counts against the cap,
--- on the 1% grid or not. An upper bound: a deficit or percent point can meet a plain one only at the belief's max.
function ns.AplPointCount(e)
    return #e.points + #e.deficit + #e.pct
end

