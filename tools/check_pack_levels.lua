-- tools/check_pack_levels.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 4): the
-- leveling rule's static check. A pack line may read another ability X's state (cooldown.X.*, action.X.* but known,
-- buff.X.*, debuff.X.*, dot.X.* with X an ability key) only inside a guard group for X that drops the read's term
-- while X is unlearned (tools/wowsims/apl.lua rule 6): `(!action.X.known|...)`, true, where the group must come out
-- true (the whole condition, a term of an `&`), `(action.X.known&...)`, false, where it must come out false (a term
-- of a `|`), each `!` before it or an enclosing group flipping that (`(action.X.known|` and `(!action.X.known&` guard
-- nothing); a line's own action needs none (the engine skips an unknown action). A group guard (an `and`/`or` whose
-- every term reads an unlearned ability: `(!(action.A.known|action.B.known)|...)`, `((action.A.known|...)&...)`) is held
-- to the same position rule, an offence "guard <its tests>" when misplaced. Loaded with
-- loadfile(...)() it returns { unguarded, file }; run directly: lua tools/check_pack_levels.lua <file.simc>... lists
-- offences against every key (no class data), for a quick look.
local M = {}

local KINDS = { cooldown = true, action = true, buff = true, debuff = true, dot = true }

-- What the group at [s, e] of `criteria` must come out as for its line to hold: true at the top or as a term of an `&`,
-- false as a term of a `|`, each `!` before it or before an enclosing group flipping it.
local function wanted(criteria, s, e)
    local flip = false
    while true do
        local i = s - 1
        while criteria:sub(i, i) == "!" do
            flip, i = not flip, i - 1
        end
        local before, after = criteria:sub(i, i), criteria:sub(e + 1, e + 1)
        if before == "&" or after == "&" then
            return not flip
        elseif before == "|" or after == "|" then
            return flip
        elseif before == "(" and after == ")" then -- the group's only term: what its parent wants
            s, e = i, e + 1
        else
            return not flip
        end
    end
end

--- The unguarded cross-ability reads of one line's criteria (`self` its action; `isAbility(key)`).
function M.unguarded(criteria, self, isAbility)
    local spans = {}
    for s, bang, x, op in criteria:gmatch("()%((!?)action%.([%w_]+)%.known([|&])") do
        local depth, i = 0, s
        repeat
            local ch = criteria:sub(i, i)
            depth = depth + (ch == "(" and 1 or ch == ")" and -1 or 0)
            i = i + 1
        until depth == 0 or i > #criteria
        if (bang == "!") == (op == "|") and wanted(criteria, s, i - 1) == (bang == "!") then
            spans[#spans + 1] = { s, i - 1, x }
        end
    end
    local bad = {}
    for s, bang, tests, op in criteria:gmatch("()%((!?)%(([%w_.|]+)%)([|&])") do
        if tests:find("|", 1, true) and (tests:find(".known", 1, true) or tests:find(".enabled", 1, true)) then
            local depth, i = 0, s
            repeat
                local ch = criteria:sub(i, i)
                depth = depth + (ch == "(" and 1 or ch == ")" and -1 or 0)
                i = i + 1
            until depth == 0 or i > #criteria
            if (bang == "!") ~= (op == "|") or wanted(criteria, s, i - 1) ~= (bang == "!") then
                bad[#bad + 1] = "guard " .. tests
            end
        end
    end
    for s, kind, x, field in criteria:gmatch("()(%a+)%.([%w_]+)%.([%w_]+)") do
        if KINDS[kind] and x ~= self and isAbility(x) and not (kind == "action" and field == "known") then
            local covered = false
            for _, sp in ipairs(spans) do
                covered = covered or (sp[3] == x and s > sp[1] and s <= sp[2])
            end
            if not covered then
                bad[#bad + 1] = kind .. "." .. x .. "." .. field
            end
        end
    end
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
