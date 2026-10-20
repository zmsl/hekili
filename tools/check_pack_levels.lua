-- tools/check_pack_levels.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 4): the
-- leveling rule's static check. A pack line may read another ability X's state (cooldown.X.*, action.X.* but known,
-- buff.X.*, debuff.X.*, dot.X.* with X an ability key) only inside a guard group for X: `(!action.X.known|...)` or
-- `(action.X.known&...)` (`(action.X.known|` and `(!action.X.known&` are false while X is unlearned, so they guard
-- nothing); a line's own action needs none (the engine skips an unknown action). Loaded with
-- loadfile(...)() it returns { unguarded, file }; run directly: lua tools/check_pack_levels.lua <file.simc>... lists
-- offences against every key (no class data), for a quick look.
local M = {}

local KINDS = { cooldown = true, action = true, buff = true, debuff = true, dot = true }

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
        if (bang == "!") == (op == "|") then
            spans[#spans + 1] = { s, i - 1, x }
        end
    end
    local bad = {}
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
