-- tools/check_pack_levels.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 4): the
-- leveling rule's static check. A pack line may read another ability X's state (cooldown.X.*, action.X.* but known,
-- buff.X.*, debuff.X.*, dot.X.* with X an ability key) only inside a guard for X that drops the read's term while X
-- is unlearned (tools/wowsims/apl.lua rule 6). The criteria parse to and/or/not; each term must read the identity of its
-- operator when dropped: true at the top and as a term of an `&`, false as a term of a `|`, each `!` flipping it. A
-- guard `(!K|t)` reads true while K is false, `(K&t)` false, and `t` holds the guard's own position, so a guard nested
-- in another's term, or under a `!`, is checked where it sits. K is a known-test formula (`action.X.known`,
-- `talent.T.enabled`, `|`/`&` of them) and covers the keys it is false for unlearned: one key however often it repeats,
-- none of `(action.A.known|action.B.known)`. A guard of the wrong polarity covers nothing, and a misplaced group guard
-- (`(kA|kB)` as its K) is an offence "guard <its tests>". A line's own action needs no guard (the engine skips an
-- unknown action). Loaded with loadfile(...)() it returns { unguarded, file }; run directly: lua
-- tools/check_pack_levels.lua <file.simc>... lists offences against every key (no class data), for a quick look.
local M = {}

local KINDS = { cooldown = true, action = true, buff = true, debuff = true, dot = true }

-- The criteria's logic tree: { op = "or"|"and", ... }, { op = "not", x } or { op = "atom" } (a read, a comparison
-- or arithmetic, parentheses inside it included), `&` binding tighter than `|`; s, e: an atom's or a chain's span.
local function parse(c)
    local pos, orx = 1, nil
    local function bang()
        return c:sub(pos, pos) == "!" and c:sub(pos + 1, pos + 1) ~= "="
    end
    local function unary()
        if bang() then
            pos = pos + 1
            return { op = "not", unary() }
        end
        local s, items, last = pos, 0, nil
        while pos <= #c and not (c:find("^[&|)]", pos) or bang()) do
            if c:sub(pos, pos) == "(" then
                pos = pos + 1
                last = orx()
                pos = pos + 1 -- its ")"
            else
                last = nil
                pos = select(2, c:find("^!?=?[^&|()!]*", pos)) + 1
            end
            items = items + 1
        end
        if items == 1 and last then
            return last -- one parenthesised group: its logic
        end
        return { op = "atom", s = s, e = pos - 1 }
    end
    local function chain(op, sym, sub)
        return function()
            local node = { op = op, s = pos, sub() }
            while c:sub(pos, pos) == sym do
                pos = pos + 1
                node[#node + 1] = sub()
            end
            node.e = pos - 1
            return #node == 1 and node[1] or node
        end
    end
    orx = chain("or", "|", chain("and", "&", unary))
    return orx()
end

-- The keys a known-test formula (`action.X.known`, `talent.T.enabled`, and `&`/`|` of them; a talent's key is
-- "talent T", which covers no ability's read) is false for while that key is unlearned, as a set, or nil when `n` is
-- not one: an `&` is false when any term is, an `|` when every term is.
local function knownKeys(c, n)
    if n.op == "atom" then
        local t = c:sub(n.s, n.e)
        local x = t:match("^action%.([%w_]+)%.known$") or (t:match("^talent%.[%w_]+%.enabled$") and "talent " .. t)
        return x and { [x] = true }
    elseif n.op == "and" or n.op == "or" then
        local set
        for _, kid in ipairs(n) do
            local k = knownKeys(c, kid)
            if not k then
                return nil
            elseif not set then
                set = k
            elseif n.op == "and" then
                for x in pairs(k) do
                    set[x] = true
                end
            else
                for x in pairs(set) do
                    set[x] = k[x]
                end
            end
        end
        return set
    end
end

--- The unguarded cross-ability reads of one line's criteria (`self` its action; `isAbility(key)`), and each group
--- guard misplaced for its position, "guard <its tests>".
function M.unguarded(criteria, self, isAbility)
    local bad = {}
    -- `want`: what node `n` must read while an unlearned ability's reads in it are dropped (wowsims drops a nil term):
    -- true at the top and as a term of an `&`, false as a term of a `|`, flipped by a `!`; `covered`: the keys of the
    -- guards around `n`.
    local function walk(n, want, covered)
        if n.op == "atom" then
            for kind, x, field in criteria:sub(n.s, n.e):gmatch("(%a+)%.([%w_]+)%.([%w_]+)") do
                if KINDS[kind] and x ~= self and isAbility(x) and not (kind == "action" and field == "known") then
                    if not covered[x] then
                        bad[#bad + 1] = kind .. "." .. x .. "." .. field
                    end
                end
            end
            return
        elseif n.op == "not" then
            return walk(n[1], not want, covered)
        end
        -- a guard `(!K|t)` reads true while K's keys are unlearned, `(K&t)` false; while they are learned it reads `t`
        local head, negated = n[1], false
        if head.op == "not" then
            head, negated = head[1], true
        end
        local keys = #n > 1 and knownKeys(criteria, head)
        if keys and negated == (n.op == "or") and negated == want then
            local inner = setmetatable(keys, { __index = covered })
            if #n == 2 then
                return walk(n[2], want, inner)
            end
            for i = 2, #n do
                walk(n[i], n.op == "and", inner)
            end
            return
        elseif keys and head.op == "or" then -- a group guard (the translator's `(kA|kB)`) misplaced
            bad[#bad + 1] = "guard " .. criteria:sub(head.s, head.e)
        end
        for i = keys and 2 or 1, #n do -- a known-test head reads nothing to check
            walk(n[i], n.op == "and", covered)
        end
    end
    walk(parse(criteria), true, {})
    return bad
end

--- The offences of a .simc file: { "<line>: <read>" }.
function M.file(path, isAbility)
    local out = {}
    for line in io.lines(path) do
        local body = line:match("^actions[%w_.]*%+?=/?(.+)$")
        if body then
            local action = body:match("^([%w_]+)")
            local criteria = body:match(",if=(.*)$")
            for _, ref in ipairs(criteria and M.unguarded(criteria, action, isAbility) or {}) do
                out[#out + 1] = line .. ": " .. ref
            end
        end
    end
    return out
end

local args = { ... }
if args[1] and args[1]:match("%.simc$") then
    local n = 0
    for _, path in ipairs(args) do
        for _, o in
            ipairs(M.file(path, function()
                return true
            end))
        do
            print(path .. ": " .. o)
            n = n + 1
        end
    end
    os.exit(n == 0 and 0 or 1)
end
return M
