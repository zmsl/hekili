-- Engine/Sim/AplThresholds.lua
-- The APL threshold harvest (bands integration design 3.1-3.4, lane B7): a resource the client hides reads
-- at 1% from the band library, and a priority's own whole-number thresholds can be watched exactly as points. A
-- load-time text scan: Hekili:LoadScript runs ns.AplThresholds over an entry's texts and keeps
-- the records on its script (`Bands`); scripts:PackBands unions them over a priority; the active priority's go to the
-- belief through def (Tracked.lua ns.SetAplBands). Pure Lua, no belief state, no client read. Allocates: load only.

local addon, ns = ...
local Hekili = _G[addon]
local ceil = math.ceil

-- The library's distinct points per power value (the band library's POINTS_PER_SOURCE; a contract spec pins the two).
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
-- `lo`, `pct_lo`: the band's floor, what the shipped priorities and press gates read (the bare token reads it too)
local RES_KIND = { [""] = "points", current = "points", actual = "points", deficit = "deficit", pct = "pct", percent = "pct", lo = "points", pct_lo = "pct" }

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


-- (L1805 rule 23, L1808) The player's own health read without its enablement term guarding the whole condition: the
-- translator refuses such a generated line, and a custom priority line is warned at load (Scripts.lua). Unknown
-- health reads full, so an unguarded line (`health.pct>80`, or a `|` branch beside the term) passes on no reading.
-- `s`: a condition, or a whole APL line (`actions=x,if=...`: its `if=` is the condition). Guarded: the condition is
-- `health.known&R`, R one group or free of a top-level `|`, or `(G)&T` with G guarded and T free of a top-level `|`.
-- Reads: `health.<field>` but `health.known` (not another unit's `<unit>.health.`), and the other names of the
-- player's health (State.lua): `stat.health`, `stat.health_pct`, `stat.maximum_health` (the `health.max` read),
-- `group_health` (the player's with the party's), `raid_health` (its twin in the state's list), `at_risk`.
-- Allocates: load only (gsub/sub on the text).
local ALIASES = {
    "[^%w_.]stat%.health%f[^%w_]",
    "[^%w_.]stat%.health_pct%f[^%w_]",
    "[^%w_.]stat%.maximum_health%f[^%w_]",
    "[^%w_.]group_health%f[^%w_]",
    "[^%w_.]raid_health%f[^%w_]",
    "[^%w_.]at_risk%f[^%w_]",
}

local function readsHealth(t)
    for field in t:gmatch("[^%w_.]health%.([%a_][%w_]*)") do
        if field ~= "known" then
            return true
        end
    end
    for i = 1, #ALIASES do
        if t:find(ALIASES[i]) then
            return true
        end
    end
    return false
end

-- The index of the `)` closing the `(` at `i` of `s`, or nil.
local function closing(s, i)
    local depth = 0
    for j = i, #s do
        local c = s:sub(j, j)
        if c == "(" then
            depth = depth + 1
        elseif c == ")" then
            depth = depth - 1
            if depth == 0 then
                return j
            end
        end
    end
end

-- Whether `s` has a `|` outside every parenthesis.
local function topOr(s)
    local depth = 0
    for j = 1, #s do
        local c = s:sub(j, j)
        if c == "(" then
            depth = depth + 1
        elseif c == ")" then
            depth = depth - 1
        elseif c == "|" and depth == 0 then
            return true
        end
    end
    return false
end

local TERM = "health.known&"

local function guarded(s)
    if s:sub(1, #TERM) == TERM then
        local rest = s:sub(#TERM + 1)
        return rest ~= "" and (closing(rest, 1) == #rest and rest:sub(1, 1) == "(" or not topOr(rest))
    end
    if s:sub(1, 1) == "(" then
        local j = closing(s, 1)
        local tail = j and s:sub(j + 1) or ""
        return j ~= nil and guarded(s:sub(2, j - 1)) and (tail == "" or tail:sub(1, 1) == "&" and not topOr(tail))
    end
    return false
end

--- (def-2 review, CPU) Whether condition `s` needs the player's health read: `health.known` guards all of it (the
--- sense above), so its line cannot pass while the health is unread (Scripts.lua's NeedsHealth, read by Core.lua's
--- display skip). Load only.
function ns.HealthGuarded(s)
    return type(s) == "string" and guarded((s:gsub("%s", "")))
end

function ns.HealthUnguarded(s)
    if type(s) ~= "string" then
        return false
    end
    s = s:gsub("%s", "")
    if not readsHealth(" " .. s) then
        return false
    end
    local cond = s
    if s:find("^actions") then
        cond = s:match(",if=(.*)$")
        if not cond or readsHealth(" " .. s:sub(1, #s - #cond)) then
            return true -- read outside the line's condition (a value=, a target_if=)
        end
    end
    return not guarded(cond)
end
