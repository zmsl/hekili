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
-- 4. Solo exports: `auraIsKnown` (another player's aura) is false.
-- 5. Keys: a spell ID maps through the recipe's `map`, else the class kit's abilities (`id` and `copy`), auras by the
--    kit's auras then abilities, items by an ability's `item`; `includeReactionTime`, `tag` and `rank` are ignored.
-- 6. Leveling guard: every value or test that reads another ability `X` (its cooldown, cast time, cost, readiness, or
--    an aura whose key is `X`) is wrapped `(!action.X.known|<test>)` where it must hold and `(action.X.known&<test>)`
--    under a `not`, so an unknown `X` never blocks the line; an aura whose ID is a talent's spell is guarded the same
--    way by `talent.<key>.enabled`. The line's own action is never guarded (the engine skips an unknown action).
-- 7. `focus` from the recipe (the tiers the retired list carried, by action), `use_off_gcd=1` on an ability whose
--    `gcd` is `"off"`; the recipe's `leveling` lines are appended to `actions`, each silent at 60.
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
    remainingTime = "fight_remains",
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

--- The translation context of a class kit (`abilities`, `auras`, `talents` as the engine registers them) and recipe
--- `r` (map, focus, executePhase, leveling).
function M.context(kit, r)
    local c = {
        keyOf = {},
        auraOf = {},
        itemKey = {},
        ability = {},
        offGcd = {},
        talent = {},
        map = r.map or {},
        focus = r.focus or {},
        executePhase = r.executePhase,
        leveling = r.leveling or {},
    }
    local keys = {}
    for key, a in pairs(kit.abilities) do
        if type(key) == "string" and type(a) == "table" and a.key == key then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local a = kit.abilities[key]
        c.ability[key] = true
        c.offGcd[key] = a.gcd == "off" or nil
        if type(a.item) == "number" then
            c.itemKey[a.item] = key
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
    for key, a in pairs(kit.auras) do
        if type(key) == "string" and type(a) == "table" and type(a.id) == "number" then
            akeys[#akeys + 1] = key
        end
    end
    table.sort(akeys)
    for _, key in ipairs(akeys) do
        local a = kit.auras[key]
        c.auraOf[a.id] = c.auraOf[a.id] or key
        for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
            if type(id) == "number" then
                c.auraOf[id] = c.auraOf[id] or key
            end
        end
    end
    for key, t in pairs(kit.talents or {}) do
        local aura = type(t) == "table" and c.auraOf[t[2]]
        if aura and not c.ability[aura] then
            c.talent[aura] = key
        end
    end
    return c
end

local function const(v)
    if v == "true" then
        return nil, true
    elseif v == "false" then
        return nil, false
    end
    local n, unit = tostring(v):match("^(%-?[%d.]+)(m?s?)$")
    if not n then
        unsupported("const " .. tostring(v))
    end
    return ("%g"):format(tonumber(n) / (unit == "ms" and 1000 or 1))
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

local function unit(v)
    return (v.sourceUnit and v.sourceUnit.type == "CurrentTarget") and "debuff" or "buff"
end

-- `atom` reads `x`: guarded so an unknown `x` cannot block its entry (rule 6); `neg` under an odd number of nots.
local function guard(c, x, atom, neg)
    if x == c.self then
        return atom
    end
    local test = c.ability[x] and ("action." .. x .. ".known")
        or (c.talent[x] and ("talent." .. c.talent[x] .. ".enabled"))
    if not test then
        return atom
    end
    return neg and ("(" .. test .. "&" .. atom .. ")") or ("(!" .. test .. "|" .. atom .. ")")
end

local function value(c, n)
    local k, v = next(n)
    if k == "const" then
        local s = const(v.val)
        if s == nil then
            unsupported("boolean as a value")
        end
        return s, {}
    elseif M.VALUES[k] then
        return M.VALUES[k], {}
    elseif k == "variableRef" then
        return value(c, c.vars[v.name] or unsupported("variable " .. v.name))
    elseif k == "math" then
        local l, lr = value(c, v.lhs)
        local r, rr = value(c, v.rhs)
        for _, x in ipairs(rr) do
            lr[#lr + 1] = x
        end
        return "(" .. l .. (M.MATH[v.op] or unsupported("math " .. tostring(v.op))) .. r .. ")", lr
    elseif k == "spellTimeToReady" or k == "spellCastTime" or k == "spellCurrentCost" then
        local x = spellKey(c, v.spellId)
        local field = ({
            spellTimeToReady = "cooldown." .. x .. ".remains",
            spellCastTime = "action." .. x .. ".cast",
            spellCurrentCost = "action." .. x .. ".cost",
        })[k]
        return field, { x }
    elseif k == "dotRemainingTime" then
        local a = auraKey(c, v.spellId.spellId)
        return "debuff." .. a .. ".remains", { a }
    elseif k == "auraRemainingTime" or k == "auraNumStacks" then
        local a = auraKey(c, v.auraId.spellId)
        return unit(v) .. "." .. a .. (k == "auraNumStacks" and ".stack" or ".remains"), { a }
    elseif k == "autoTimeToNext" and v.autoType == "MainHandAuto" then
        return "mainhand_remains", {}
    elseif k == "autoTimeSinceLast" and v.autoType == "MainHandAuto" then
        return "(mainhand_speed-mainhand_remains)", {}
    elseif k == "totemRemainingTime" then
        return "totem." .. M.snake(tostring(v.totemType)):gsub("^totem_", "") .. ".remains", {}
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

local bool
local function negate(c, n, neg)
    local s, b = bool(c, n, not neg)
    if b ~= nil then
        return nil, not b
    end
    return (s:match("^[%w_.]+$") or grouped(s)) and ("!" .. s) or ("!(" .. s .. ")")
end

-- A condition: its text, or nil and a constant when it folds.
function bool(c, n, neg)
    local k, v = next(n)
    if k == "and" or k == "or" then
        local absorb, parts = k == "or", {}
        for _, x in ipairs(v.vals or {}) do
            local s, b = bool(c, x, neg)
            if b == absorb then
                return nil, absorb
            elseif b == nil then
                parts[#parts + 1] = s
            end
        end
        if #parts == 0 then
            return nil, not absorb
        elseif #parts == 1 then
            return parts[1]
        end
        return "(" .. table.concat(parts, k == "and" and "&" or "|") .. ")"
    elseif k == "not" then
        return negate(c, v.val, neg)
    elseif k == "const" then
        local _, b = const(v.val)
        if b == nil then
            unsupported("number as a condition")
        end
        return nil, b
    elseif k == "cmp" then
        local l, lr = value(c, v.lhs)
        local r, rr = value(c, v.rhs)
        local s = l .. (M.OPS[v.op] or unsupported("op " .. tostring(v.op))) .. r
        local done = {}
        for _, list in ipairs({ lr, rr }) do
            for _, x in ipairs(list) do
                if not done[x] then
                    done[x] = true
                    s = guard(c, x, s, neg)
                end
            end
        end
        return s
    elseif k == "auraIsActive" then
        local a = auraKey(c, v.auraId.spellId)
        return guard(c, a, unit(v) .. "." .. a .. ".up", neg)
    elseif k == "auraIsInactive" then
        return negate(c, { auraIsActive = v }, neg)
    elseif k == "auraIsKnown" then
        return nil, false -- rule 4: solo exports
    elseif k == "dotIsActive" then
        local a = auraKey(c, v.spellId.spellId)
        return guard(c, a, "debuff." .. a .. ".up", neg)
    elseif k == "spellIsReady" then
        local x = spellKey(c, v.spellId)
        return guard(c, x, "cooldown." .. x .. ".ready", neg)
    elseif k == "spellCanCast" then
        local x = spellKey(c, v.spellId)
        return guard(c, x, "action." .. x .. ".ready", neg)
    elseif k == "spellIsKnown" then
        return "action." .. spellKey(c, v.spellId) .. ".known"
    elseif k == "isExecutePhase" then
        if v.threshold == "E20" and c.executePhase then
            return c.executePhase
        end
        unsupported("isExecutePhase " .. tostring(v.threshold))
    elseif k == "actionGroupUsed" then
        return "settings." .. (c.toggles[v.name] or unsupported("actionGroupUsed " .. tostring(v.name)))
    elseif k == "variableRef" then
        return bool(c, c.vars[v.name] or unsupported("variable " .. v.name), neg)
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
    else
        unsupported(kind)
    end
    if a.condition then
        local s, b = bool(c, a.condition, false)
        if b == false then
            return nil, "never"
        elseif s then
            body = body .. ",if=" .. s
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
    local kit = require("Forever.helpers.engine").load(r.class).class.kit
    local text, omitted, toggles = M.translate(req.raid.parties[1].players[1].rotation, M.context(kit, r))
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
