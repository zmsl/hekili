-- tools/wowsims/apl.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 4): a
-- wowsims/forever APL (a request's player.rotation) as a "(wowsims.com)" pack's SimC text with the fork's keys.
-- Data: wowsims/forever (MIT, https://github.com/wowsims/forever); the APL JSON is translated as data, no code copied.
--
-- The translation rules (the plan's Task 4):
-- 1. One `.simc` line per APL entry, in order: `prepullActions` -> `actions.precombat`, `priorityList` -> `actions`,
--    each group a list `actions.<snake of its name>` called with `call_action_list,name=<snake>`, groups in the APL's
--    order as first called; `valueVariables` are inlined where referenced.
-- 2. Omitted, and listed in the file's second comment block: `hide: true` entries; entries whose condition folds to
--    false; entries whose action or condition uses a node the fork lacks (`autocastOtherCooldowns`,
--    `castAllStatBuffCooldowns`, `strictSequence`, `sequence`, `resetSequence`, `schedule`, `itemSwap`, `move`, `wait`,
--    `unitDistance`, `sequenceIsComplete`, `activeItemSwapSet`, `selectedConjured`, an unmapped spell, item or other
--    ID); a call of a group whose every entry was omitted.
-- 3. Toggles: a group whose actions are all empty is a wowsims ON/OFF switch: `actionGroupUsed` of it reads
--    `settings.wowsims_<snake of the name without " ON/OFF">`, its default on exactly when the APL's reference to it is
--    not hidden; the class registers that setting for the spec (named "<Group> (wowsims.com)").
-- 4. `auraIsKnown` (wowsims: the aura is registered on its source unit, Self by default): on Self or the target, an
--    ID that resolves (rule 5, or a kit talent's spell) to a talent's key or aura is `talent.<key>.enabled`, to an
--    ability's key `action.<key>.known`, to any other aura `true`; an ID nothing resolves, or another unit, is false.
--    (wowsims registers a gear, set or consumable aura only when it is equipped or configured; `true` for one of those
--    may disagree, no APL reads one today.) Solo exports: another player's aura (wowsims's External, tag -1) is never
--    registered, so it is not known (false) and every other read of it is nil (rule 6: dropped).
-- 5. Keys, from the character's ability set (tests/Forever/helpers/engine.lua abilitySet: the class kit, the shared
--    content and every race's racials, as the engine merges them): a spell ID maps through the recipe's `map`, else
--    an ability's `id` and `copy`, auras by the set's auras then abilities, items by an ability's `item` or `items`;
--    `includeReactionTime`, `rank` and a `tag` other than -1 (rule 4) are ignored. An aura's `sourceUnit` Self (or none) reads `buff.`,
--    CurrentTarget or Target `debuff.`; a resource value with a source unit other than Self is unsupported.
-- 6. Leveling guard: a read of another ability `X` (its cooldown, cast time, cost, readiness, or an aura whose key is
--    `X`; an aura whose ID is a talent's spell: the talent) is wowsims's unresolved (nil) node while `X` is unknown,
--    and nil propagates as wowsims builds the APL (sim/core/apl_values_operators.go): `not`, `cmp` and `math` of a nil
--    are nil; `and`/`or` drop a nil term and are nil when every term is; a nil condition is true (apl_action.go). So a
--    term that may be nil is written `(!<known>|<term>)` in an `and` and as the condition, `(<known>&<term>)` in an
--    `or`, with `<known>` its known test, `(kA|kB)` for an `and`/`or` whose every term may be nil, and one guard a
--    test for a comparison of two reads. An empty value and another player's aura are nil always (dropped here). The
--    line's own action is never guarded (the engine skips an unknown action).
-- 7. `focus` from the recipe (the tiers the retired list carried, by action), `use_off_gcd=1` on an ability whose
--    `gcd` is `"off"`; the recipe's `leveling` lines are appended to `actions`, each silent at 60.
-- 8. Constants: `true`/`false`; a number; a Go duration ("1.5s", "300ms", "2m", "1m30s") in seconds; "N%" as N
--    (wowsims's N/100 against its 0-1 percents; ours, `mana.pct` and `health.pct`, run 0-100).
-- 9. `auraIcdIsReady` (wowsims: the proc aura's internal cooldown is ready): the aura declaring `icd` (RegisterAura,
--    seconds from its last application) by its ID or its `icdSpell` (the proc trigger wowsims names the ICD by) is
--    `buff.<key>.icd_ready`, guarded by the talent when that ID is a talent's spell (rule 6); an aura declaring none is
--    unsupported (rule 2). `includeReactionTime` is ignored (rule 5).
-- 10. `auraShouldRefresh` (wowsims: no stronger exclusive effect is up and none of ours outlasts the overlap; solo, ours
--    is the only one): `<unit>.<key>.remains<=<maxOverlap>` (0 by default; the target's by default, as wowsims's
--    GetTargetUnit), `|...stack<max_stack` for a stacking aura, guarded (rule 6); `cancelAura` is the action
--    `cancel_buff,buff_name=<key>`; `autoSwingTime` MainHand / OffHand is `mainhand_speed` / `offhand_speed`.
--    `remainingTime` is `fight_remains`, which answers "unknown" (3600 s) on Forever: an API-forced deviation.
-- Any node not handled below is unsupported (rule 2), so a new wowsims node omits its entry rather than mistranslating.
--
-- The engine facts rule 6 rests on (tools/check_pack_levels.lua checks every pack for it):
-- - src/Hekili/Engine/Sim/State.lua `mt_default_cooldown`: for an ability `state:IsKnown` says is unknown (the
--   `if not state:IsKnown( t.key )` lines in its __index) `remains` is 0, `charges` max, `time_to_max_charges` 0, so
--   an unguarded `cooldown.X.remains>Y` is false and would block its line;
-- - State.lua `mt_default_action` answers `action.X.known`/`enabled` through `state:IsKnown` (its
--   `if k == "enabled" or k == "known"` branch), the guard's test;
-- - src/Hekili/Engine/Sim/Core.lua's list walk recommends an entry only when `ability and known and enabled` (after
--   `known, reason = self:IsSpellKnown( action )`), so a line whose own action is unlearned is skipped, never an error.
local M = {}

M.OPS = { OpEq = "=", OpNe = "!=", OpLt = "<", OpLe = "<=", OpGt = ">", OpGe = ">=" }
M.MATH = { OpAdd = "+", OpSub = "-", OpMul = "*", OpDiv = "%" } -- SimC's division is %
-- Values with one translation.
M.VALUES = {
    numberTargets = "active_enemies",
    currentRage = "rage.current",
    currentEnergy = "energy.current",
    currentMana = "mana.current",
    currentManaPercent = "mana.pct",
    maxMana = "mana.max",
    currentManaRegen = "mana.regen",
    currentComboPoints = "combo_points.current",
    currentHealthPercent = "health.pct",
    currentTime = "time",
    remainingTime = "fight_remains", -- API-forced: wowsims knows its fight length; ours answers "unknown" (3600 s)
    gcdTimeToReady = "gcd.remains",
    inputDelay = "0", -- wowsims's modelled reaction; the engine recommends without one
}

local function unsupported(what)
    error({ unsupported = what }, 0)
end

--- A name in snake_case ("Pre-pull: Stance" -> "pre_pull_stance").
function M.snake(s)
    return (s:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

--- The translation context of an ability set (`abilities`, `auras`, `talents` as the engine registers them:
--- tests/Forever/helpers/engine.lua abilitySet) and recipe `r` (map, focus, executePhase, leveling).
function M.context(set, r)
    local c = {
        keyOf = {},
        auraOf = {},
        icdOf = {},
        stackOf = {},
        itemKey = {},
        ability = {},
        offGcd = {},
        talent = {},
        talentOf = {},
        talentKey = {},
        map = r.map or {},
        focus = r.focus or {},
        executePhase = r.executePhase,
        leveling = r.leveling or {},
    }
    local keys = {}
    for key, a in pairs(set.abilities) do
        if type(key) == "string" and type(a) == "table" and a.key == key then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local a = set.abilities[key]
        c.ability[key] = true
        c.offGcd[key] = a.gcd == "off" or nil
        for _, id in ipairs(type(a.items) == "table" and a.items or { a.item }) do
            if type(id) == "number" then
                c.itemKey[id] = c.itemKey[id] or key
            end
        end
        local list = { a.id }
        for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
            list[#list + 1] = id
        end
        for _, id in ipairs(list) do
            if type(id) == "number" then
                c.keyOf[id] = c.keyOf[id] or key
            end
        end
    end
    local akeys = {}
    for key, a in pairs(set.auras) do
        if type(key) == "string" and type(a) == "table" and type(a.id) == "number" then
            akeys[#akeys + 1] = key
        end
    end
    table.sort(akeys)
    for _, key in ipairs(akeys) do
        local a = set.auras[key]
        c.auraOf[a.id] = c.auraOf[a.id] or key
        c.stackOf[key] = a.max_stack
        if a.icd then -- rule 9: by its own ID and by the spell wowsims names the ICD by (its proc trigger)
            c.icdOf[a.id] = key
            if a.icdSpell then
                c.icdOf[a.icdSpell] = key
            end
        end
        for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
            if type(id) == "number" then
                c.auraOf[id] = c.auraOf[id] or key
            end
        end
    end
    for key, t in pairs(set.talents or {}) do
        local aura = type(t) == "table" and c.auraOf[t[2]]
        if aura and not c.ability[aura] then
            c.talent[aura] = key
        end
        if type(t) == "table" and type(t[2]) == "number" then
            c.talentOf[t[2]], c.talentKey[key] = key, true
        end
    end
    return c
end

local SECONDS = { h = 3600, m = 60, s = 1, ms = 0.001, us = 1e-6, ns = 1e-9 } -- Go's time.ParseDuration units

local function const(v)
    v = tostring(v)
    if v:lower() == "true" then
        return nil, true
    elseif v:lower() == "false" then
        return nil, false
    end
    local n = tonumber(v:match("^(%-?[%d.]+)%%$") or v:match("^%-?[%d.]+$"))
    if not n and v:match("^%-?[%d.]+%a") then
        local sign, rest, sum = v:match("^(%-?)(.*)$")
        sum = 0
        local used = rest:gsub("([%d.]+)(%a+)", function(x, u)
            sum = sum + (tonumber(x) or 0 / 0) * (SECONDS[u] or 0 / 0)
            return ""
        end)
        n = used == "" and sum == sum and (sign == "-" and -sum or sum) or nil
    end
    if not n then
        unsupported("const " .. v)
    end
    return ("%g"):format(n)
end

local function spellKey(c, s)
    if s.spellId then
        return c.map[s.spellId] or c.keyOf[s.spellId] or unsupported("spell " .. s.spellId)
    elseif s.itemId then
        return c.map["item:" .. s.itemId] or c.itemKey[s.itemId] or unsupported("item " .. s.itemId)
    end
    return c.map[s.otherId] or unsupported("other " .. tostring(s.otherId))
end

local function auraKey(c, id)
    return c.map[id] or c.auraOf[id] or c.keyOf[id] or unsupported("aura " .. tostring(id))
end

local UNIT = { Self = "buff", CurrentTarget = "debuff", Target = "debuff" }
local function unit(v)
    local u = v.sourceUnit and v.sourceUnit.type or "Self"
    return UNIT[u] or unsupported("unit " .. tostring(u))
end

-- The known test of key `x` (an ability's or a talent's), or nil.
local function knownTest(c, x)
    return c.ability[x] and ("action." .. x .. ".known") or (c.talent[x] and ("talent." .. c.talent[x] .. ".enabled"))
end

-- Rule 6's nil conditions: when a translated node is wowsims's unresolved (nil) node. `false`: never; `true`: always
-- (dropped at translation); else a formula over known tests: { test = "action.X.known" } (nil while X is unknown),
-- { op = "or", ... } (nil when any part is: a comparison, a sum), { op = "and", ... } (nil when every part is: an
-- `and`/`or` whose every term is nil).
local function nilOr(a, b)
    if a == true or b == true then
        return true
    elseif a == false then
        return b
    elseif b == false then
        return a
    end
    local out, seen = { op = "or" }, {}
    for _, u in ipairs({ a, b }) do
        for _, x in ipairs(u.op == "or" and u or { u }) do
            if not (x.test and seen[x.test]) then
                out[#out + 1] = x
                seen[x.test or out] = true
            end
        end
    end
    return #out == 1 and out[1] or out
end

local function nilAnd(list)
    local out = { op = "and" }
    for _, u in ipairs(list) do
        if u == false then
            return false
        elseif u ~= true then
            out[#out + 1] = u
        end
    end
    return #out == 0 or (#out == 1 and out[1]) or out
end

-- The text of "`u` is not nil".
local function present(u)
    if u.test then
        return u.test
    end
    local parts = {}
    for i, x in ipairs(u) do
        parts[i] = present(x)
    end
    return "(" .. table.concat(parts, u.op == "or" and "&" or "|") .. ")"
end

-- Term `s` with nil condition `u` as wowsims evaluates it: a nil term is dropped, so it reads `want` (true in an
-- `and` and at the top, false in an `or`).
local function emit(u, s, want)
    if u == false then
        return s
    elseif u.op == "or" then -- one guard a known test, the first innermost
        for _, x in ipairs(u) do
            s = emit(x, s, want)
        end
        return s
    end
    local k = present(u)
    return want and ("(!" .. k .. "|" .. s .. ")") or ("(" .. k .. "&" .. s .. ")")
end

-- The nil condition of a read of key `x` (none for the line's own action).
local function reads(c, x)
    local test = x ~= c.self and knownTest(c, x)
    return test and { test = test } or false
end

-- A value: its text and nil condition (`true`: nil, no text).
local function value(c, n)
    local k, v = next(n)
    if k == nil then
        return nil, true -- an empty value
    elseif k == "const" then
        local s = const(v.val)
        if s == nil then
            unsupported("boolean as a value")
        end
        return s, false
    elseif M.VALUES[k] then
        if v.sourceUnit and v.sourceUnit.type ~= "Self" then
            unsupported(k .. " of " .. tostring(v.sourceUnit.type))
        end
        return M.VALUES[k], false
    elseif k == "variableRef" then
        return value(c, c.vars[v.name] or unsupported("variable " .. v.name))
    elseif k == "math" then
        local l, lu = value(c, v.lhs)
        local r, ru = value(c, v.rhs)
        local op = M.MATH[v.op] or unsupported("math " .. tostring(v.op))
        local u = nilOr(lu, ru)
        if u == true then
            return nil, true
        end
        return "(" .. l .. op .. r .. ")", u
    elseif k == "spellTimeToReady" or k == "spellCastTime" or k == "spellCurrentCost" then
        local x = spellKey(c, v.spellId)
        local field = ({
            spellTimeToReady = "cooldown." .. x .. ".remains",
            spellCastTime = "action." .. x .. ".cast",
            spellCurrentCost = "action." .. x .. ".cost",
        })[k]
        return field, reads(c, x)
    elseif k == "dotRemainingTime" then
        local a = auraKey(c, v.spellId.spellId)
        return "debuff." .. a .. ".remains", reads(c, a)
    elseif k == "auraRemainingTime" or k == "auraNumStacks" then
        if v.auraId.tag == -1 then
            return nil, true -- rule 4: another player's aura, never registered
        end
        local a = auraKey(c, v.auraId.spellId)
        return unit(v) .. "." .. a .. (k == "auraNumStacks" and ".stack" or ".remains"), reads(c, a)
    elseif k == "autoSwingTime" and (v.autoType == "MainHand" or v.autoType == "OffHand") then -- rule 10
        return v.autoType == "MainHand" and "mainhand_speed" or "offhand_speed", false
    elseif k == "autoTimeToNext" and v.autoType == "MainHandAuto" then
        return "mainhand_remains", false
    elseif k == "autoTimeSinceLast" and v.autoType == "MainHandAuto" then
        return "(mainhand_speed-mainhand_remains)", false
    elseif k == "totemRemainingTime" then
        return "totem." .. M.snake(tostring(v.totemType)):gsub("^totem_", "") .. ".remains", false
    end
    unsupported(tostring(k))
end

-- Whether `s` is one parenthesised group from its first character to its last.
local function grouped(s)
    if s:sub(1, 1) ~= "(" then
        return false
    end
    local depth = 0
    for i = 1, #s do
        local ch = s:sub(i, i)
        depth = depth + (ch == "(" and 1 or ch == ")" and -1 or 0)
        if depth == 0 then
            return i == #s
        end
    end
    return false
end

-- A condition: its text, constant (when it folds) and nil condition, as wowsims builds it (sim/core
-- apl_values_operators.go): a nil child of `and`/`or` is dropped and one whose every child is nil is nil; `not`,
-- `cmp` and `math` of a nil are nil; a constant `false` in an `and` (`true` in an `or`) decides it.
local function bool(c, n)
    local k, v = next(n)
    if k == nil then
        return nil, nil, true -- an empty value
    elseif k == "and" or k == "or" then
        local absorb, kids, identity = k == "or", {}, false
        for _, x in ipairs(v.vals or {}) do
            local s, b, u = bool(c, x)
            if u ~= true then
                if b == absorb then
                    return nil, absorb, false
                elseif b == nil then
                    kids[#kids + 1] = { s, u }
                else
                    identity = true
                end
            end
        end
        if #kids == 0 then
            if identity then
                return nil, not absorb, false
            end
            return nil, nil, true
        elseif #kids == 1 and not identity then
            return kids[1][1], nil, kids[1][2] -- wowsims's one-child and/or is the child
        end
        local parts, us = {}, {}
        for i, kid in ipairs(kids) do
            parts[i], us[i] = emit(kid[2], kid[1], k == "and"), kid[2]
        end
        local s = #parts == 1 and parts[1] or ("(" .. table.concat(parts, k == "and" and "&" or "|") .. ")")
        return s, nil, (not identity) and nilAnd(us)
    elseif k == "not" then
        local s, b, u = bool(c, v.val)
        if u == true then
            return nil, nil, true
        elseif b ~= nil then
            return nil, not b, false
        end
        return (s:match("^[%w_.]+$") or grouped(s)) and ("!" .. s) or ("!(" .. s .. ")"), nil, u
    elseif k == "const" then
        local _, b = const(v.val)
        if b == nil then
            unsupported("number as a condition")
        end
        return nil, b, false
    elseif k == "cmp" then
        local l, lu = value(c, v.lhs)
        local r, ru = value(c, v.rhs)
        local op = M.OPS[v.op] or unsupported("op " .. tostring(v.op))
        local u = nilOr(lu, ru)
        if u == true then
            return nil, nil, true
        end
        return l .. op .. r, nil, u
    elseif k == "auraIsActive" then
        if v.auraId.tag == -1 then
            return nil, nil, true -- rule 4: another player's aura, never registered
        end
        local a = auraKey(c, v.auraId.spellId)
        return unit(v) .. "." .. a .. ".up", nil, reads(c, a)
    elseif k == "auraIsInactive" then
        return bool(c, { ["not"] = { val = { auraIsActive = v } } })
    elseif k == "auraIsKnown" then -- rule 4
        local id = v.auraId and v.auraId.spellId
        if not UNIT[v.sourceUnit and v.sourceUnit.type or "Self"] or not id or v.auraId.tag == -1 then
            return nil, false, false
        end
        local x = c.map[id] or c.talentOf[id] or c.auraOf[id] or c.keyOf[id]
        if not x then
            return nil, false, false
        end
        local tk = c.talentOf[id] or (c.talentKey[x] and x) -- a talent's spell, or a recipe `map` to a talent's key
        local test = tk and ("talent." .. tk .. ".enabled") or knownTest(c, x)
        if not test then
            return nil, true, false
        end
        return test, nil, false
    elseif k == "auraShouldRefresh" then -- rule 10
        local a = auraKey(c, v.auraId.spellId)
        local un = v.sourceUnit and unit(v) or "debuff" -- wowsims reads it on the target by default
        local overlap, ou = "0", false
        if v.maxOverlap then
            overlap, ou = value(c, v.maxOverlap)
        end
        local u = nilOr(reads(c, a), ou)
        if u == true then
            return nil, nil, true
        end
        local atom = un .. "." .. a .. ".remains<=" .. overlap
        if (c.stackOf[a] or 1) > 1 then
            atom = "(" .. atom .. "|" .. un .. "." .. a .. ".stack<" .. c.stackOf[a] .. ")"
        end
        return atom, nil, u
    elseif k == "auraIcdIsReady" then -- rule 9
        local id = v.auraId and v.auraId.spellId
        local a = c.icdOf[id] or unsupported("auraIcdIsReady " .. tostring(id))
        local tk = c.talentOf[id] -- nil (dropped) while the proc's talent is untaken, as wowsims's unregistered aura
        return "buff." .. a .. ".icd_ready", nil, tk and { test = "talent." .. tk .. ".enabled" } or false
    elseif k == "dotIsActive" then
        local a = auraKey(c, v.spellId.spellId)
        return "debuff." .. a .. ".up", nil, reads(c, a)
    elseif k == "spellIsReady" then
        local x = spellKey(c, v.spellId)
        return "cooldown." .. x .. ".ready", nil, reads(c, x)
    elseif k == "spellCanCast" then
        local x = spellKey(c, v.spellId)
        return "action." .. x .. ".ready", nil, reads(c, x)
    elseif k == "spellIsKnown" then
        return "action." .. spellKey(c, v.spellId) .. ".known", nil, false
    elseif k == "isExecutePhase" then
        if v.threshold == "E20" and c.executePhase then
            return c.executePhase, nil, false
        end
        unsupported("isExecutePhase " .. tostring(v.threshold))
    elseif k == "actionGroupUsed" then
        return "settings." .. (c.toggles[v.name] or unsupported("actionGroupUsed " .. tostring(v.name))), nil, false
    elseif k == "variableRef" then
        return bool(c, c.vars[v.name] or unsupported("variable " .. v.name))
    end
    unsupported(tostring(k))
end

-- One entry as a line body, or nil and why it folds away.
local function entry(c, e)
    local a = e.action or {}
    local kind
    for k in pairs(a) do
        if k ~= "condition" then
            kind = k
        end
    end
    if not kind then
        return nil, "empty"
    end
    local body
    if kind == "castSpell" or kind == "channelSpell" then
        local x = spellKey(c, a[kind].spellId)
        c.self = x
        local tier = c.focus[x]
        if type(tier) == "table" then
            c.seen[x] = (c.seen[x] or 0) + 1
            tier = tier[c.seen[x]] or tier[#tier]
        end
        body = x .. (c.offGcd[x] and ",use_off_gcd=1" or "") .. (tier and (",focus=" .. tier) or "")
    elseif kind == "groupReference" then
        local g = a.groupReference.groupName
        if c.toggles[g] then
            return nil, "toggle"
        end
        c.used[g], c.self = true, nil
        body = "call_action_list,name=" .. M.snake(g)
    elseif kind == "cancelAura" then -- rule 10
        c.self = nil
        body = "cancel_buff,buff_name=" .. auraKey(c, a.cancelAura.auraId.spellId)
    else
        unsupported(kind)
    end
    if a.condition then
        local s, b, u = bool(c, a.condition)
        if u ~= true and b == false then
            return nil, "never"
        elseif u ~= true and s then -- a nil condition is always true (wowsims's apl_action.go)
            body = body .. ",if=" .. emit(u, s, true)
        end
    end
    return body
end

--- The SimC text of `rotation` (a wowsims APL table) under context `c`, the omitted entries
--- ({ "<list> #<n>: <why>" }) and the toggles ({ { setting key, default } } in the APL's group order).
function M.translate(rotation, c)
    c.vars, c.toggles, c.used, c.seen = {}, {}, {}, {}
    for _, v in ipairs(rotation.valueVariables or {}) do
        c.vars[v.name] = v.value
    end
    local toggles, shown = {}, {}
    for _, e in ipairs(rotation.priorityList or {}) do
        local g = e.action and e.action.groupReference
        if g and not e.hide then
            shown[g.groupName] = true
        end
    end
    for _, g in ipairs(rotation.groups or {}) do
        local empty = true
        for _, x in ipairs(g.actions or {}) do
            empty = empty and next(x.action or {}) == nil
        end
        if empty then
            c.toggles[g.name] = "wowsims_" .. M.snake((g.name:gsub(" ON/OFF$", "")))
            toggles[#toggles + 1] = { c.toggles[g.name], shown[g.name] == true }
        end
    end
    local omitted, lists, byName = {}, {}, {}
    local function run(name, entries)
        local out = {}
        for i, e in ipairs(entries) do
            if e.hide then
                omitted[#omitted + 1] = ("%s #%d: hidden"):format(name, i)
            else
                local ok, body, why = pcall(entry, c, e)
                if not ok then
                    if type(body) ~= "table" then
                        error(body, 0)
                    end
                    omitted[#omitted + 1] = ("%s #%d: %s"):format(name, i, body.unsupported)
                elseif body then
                    out[#out + 1] = body
                elseif why ~= "toggle" then
                    omitted[#omitted + 1] = ("%s #%d: %s"):format(name, i, why)
                end
            end
        end
        lists[#lists + 1], byName[name] = { name, out }, out
    end
    run("precombat", rotation.prepullActions or {})
    run("default", rotation.priorityList or {})
    for _, line in ipairs(c.leveling) do
        table.insert(byName.default, line)
    end
    local done = {}
    repeat
        local more = false
        for _, g in ipairs(rotation.groups or {}) do
            if c.used[g.name] and not done[g.name] then
                done[g.name], more = true, true
                run(M.snake(g.name), g.actions or {})
            end
        end
    until not more
    local text = {}
    for _, l in ipairs(lists) do
        local head = l[1] == "default" and "actions" or ("actions." .. l[1])
        local n = 0
        for _, body in ipairs(l[2]) do
            local called = body:match("^call_action_list,name=([%w_]+)")
            if called and #(byName[called] or {}) == 0 then
                omitted[#omitted + 1] = ("%s: empty group %s"):format(l[1], called)
            else
                n = n + 1
                text[#text + 1] = head .. (n == 1 and "=" or "+=/") .. body
            end
        end
    end
    return table.concat(text, "\n"), omitted, toggles
end

--- Writes spec `spec`'s pack: src/Hekili_<Class>/APLs/<recipe.pack>.simc from the checked-in request (`ex`:
--- export.lua's module), its description, toggles and omitted entries in the header.
function M.write(spec, ex)
    local json = require("dkjson")
    local r = ex.recipe(spec)
    local f = assert(io.open(ex.OUT .. spec .. ".json", "rb"))
    local req = json.decode(f:read("*a"))
    f:close()
    local set = require("Forever.helpers.engine").abilitySet(r.class)
    local text, omitted, toggles = M.translate(req.raid.parties[1].players[1].rotation, M.context(set, r))
    local Class = r.class:sub(1, 1) .. r.class:sub(2):lower()
    local out = {
        ("# %s: the wowsims/forever default APL for %s (%s), translated to this addon's keys."):format(
            r.pack,
            r.name,
            r.apl or r.build
        ),
        "# Data: wowsims/forever (MIT, https://github.com/wowsims/forever) at " .. ex.PIN:sub(1, 12) .. ".",
        "",
        ("# Generated by `make wowsims-packs` (tools/wowsims/apl.lua) from tools/wowsims/specs/%s.lua: edit that recipe, not this file."):format(
            spec
        ),
    }
    for _, t in ipairs(toggles) do
        out[#out + 1] = ("# Setting %s (wowsims ON/OFF group), default %s."):format(t[1], tostring(t[2]))
    end
    for _, o in ipairs(omitted) do
        out[#out + 1] = "# Omitted: " .. o
    end
    out[#out + 1] = ""
    out[#out + 1] = text
    local path = ("src/Hekili_%s/APLs/%s.simc"):format(Class, r.pack)
    local w = assert(io.open(path, "wb"))
    w:write(table.concat(out, "\n") .. "\n")
    w:close()
    print(("%s: %d omitted, %d toggles"):format(path, #omitted, #toggles))
end

return M
