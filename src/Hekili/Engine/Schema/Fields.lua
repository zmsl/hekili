-- Engine/Schema/Fields.lua
-- The pack field registry (refactor plan lane 3, L1819, L1827; belief-purpose-taxonomy 5.2): one row per field a
-- registration may declare on an ability (RegisterAbility), an aura (RegisterAura), a resource's meta and its `fsr`
-- (RegisterResource) and a regen entry, each with its type, today's default (stated, never written: the consumers keep
-- their own), its bounds and one doc line. Generic: no class, spell or form word. Only the fields that exist today: the
-- ones the shipped content declares and the ones the registration calls or the belief read. The registration calls
-- validate what the pack wrote against it (F.Check), before they read or move anything, so a valid pack changes
-- nothing and a mistake stops at load, never in combat:
--   V1 an unknown key: one edit from a registered name of 4 or more characters fails; on a regen entry or an `fsr` (belief-only tables) any
--      unknown key fails; on an ability, an aura or a meta, which also carry the engine's own fields, it is listed
--      (F.findings)
--   V2 type and range       V3 references resolve (aura, resource, talent and ability keys: at the end of the load,
--                            F.Finish, since a regen entry names an aura its pack registers after it)
--   V4 an ability's landing evidence agrees with its other fields (the belief's own rule, Game/State/Families/Expect.lua
--      X.Malformed, which counts and falls back at the build; a copy here, held equal by tests/Forever/fields_spec.lua)
--   V5 a combat-starting ability with no declared `expects` is listed (F.unlanded), not refused
--   V6 a tunable row (`tune`) names its source and ledger row and its default lies inside its bounds
--   V7 a field related to another (`atLeast`) is not below it on the same object
-- V6 and V7 have no row today (no pack field is tunable yet); their checks run on every row and every registration.
-- A failure raises "Hekili field check Vn: <pack> <object> <key>: <field> <why>". Load only: nothing here runs per update.

local addon, ns = ...
local Hekili = _G[addon]
local class = Hekili.Class
local format = string.format

local F = {
    rows = { ability = {}, aura = {}, meta = {}, fsr = {}, regen = {} },
    names = { ability = {}, aura = {}, meta = {}, fsr = {}, regen = {} }, -- each kind's rows in order (the page's table)
    findings = {}, -- V1's listed keys: "<pack> <object> <key>: <field> (V1)"
    unlanded = {}, -- V5: "<pack> <key>" of each combat-starting ability with no `expects`
    pending = {}, -- V3's references and V4's declarations, checked at F.Finish
    closed = false, -- true once ns.LoadContent has run the end-of-load pass: F.Check returns at once
}
ns.Fields = F

-- Belief-only tables: any key the registry lacks fails (V1).
local STRICT = { regen = true, fsr = true }
local KIND_OF = { aura = "auras", resource = "resources", talent = "talents", ability = "abilities" }
local SOURCES = { measured = true, wowsims = true, ruling = true, design = true, unmeasured = true } -- as the latency table's

local function fail(n, who, field, why)
    local msg = format("Hekili field check V%d: %s: %s %s", n, who, tostring(field), why)
    F.failed = F.failed or msg -- the first failure: ns.LoadContent's notice names it, also when a pack file raised
    error(msg, 0)
end

local function isa(t, v)
    local ty = type(v)
    if t == "any" then
        return true
    elseif t == "bool" then
        return ty == "boolean"
    elseif t == "fn" then
        return ty == "function"
    elseif t == "key" then
        return ty == "number" or ty == "string"
    elseif t == "aura" or t == "resource" or t == "talent" or t == "ability" or t == "enum" then
        return ty == "string"
    end
    return ty == t -- number, string, table
end

--- Adds field `name` to kind `on` ("ability", "aura", "meta", "fsr", "regen"). `ty`: alternatives joined by "|" of
--- bool, number, string, table, fn, key (a number or a string), any, enum (a string of `opt.enum`), or a reference
--- (aura, resource, talent, ability: a key checked at F.Finish), each optionally "list:" (an array of it). "fn" on an
--- ability also admits a `{ byRank = values }` table (only RegisterAbility converts it: Spec/Ranks.lua). `opt`: min, max, gt (a number above it), enum, tune
--- ({ source, row }: V6), atLeast (another field of the same object: V7). Load only.
function F.Row(on, name, ty, default, doc, opt)
    opt = opt or {}
    assert(F.rows[on] and not F.rows[on][name] and type(doc) == "string", name)
    local alts = {}
    for a in ty:gmatch("[^|]+") do
        alts[#alts + 1] = a
    end
    local r = {
        name = name,
        on = on,
        type = ty,
        alts = alts,
        default = default,
        doc = doc,
        min = opt.min,
        max = opt.max,
        gt = opt.gt,
        tune = opt.tune,
        atLeast = opt.atLeast,
    }
    if opt.enum then
        r.enum = {}
        for _, v in ipairs(opt.enum) do
            r.enum[v] = true
        end
        r.enumList = opt.enum
    end
    local t = r.tune -- V6: a tunable value names where it comes from, and its default is inside its own bounds
    if t ~= nil then
        if type(t) ~= "table" or not SOURCES[t.source] or type(t.row) ~= "string" or t.row == "" then
            fail(6, "registry " .. on, name, "is tunable with no source or ledger row")
        end
        if type(default) ~= "number" or (r.min and default < r.min) or (r.max and default > r.max) then
            fail(6, "registry " .. on, name, "default " .. tostring(default) .. " lies outside its bounds")
        end
    end
    if r.atLeast and not F.rows[on][r.atLeast] then -- V7: a relation names a row registered before it
        fail(7, "registry " .. on, name, "is related to no field " .. tostring(r.atLeast))
    end
    F.rows[on][name] = r
    F.names[on][#F.names[on] + 1] = name
    return r
end

-- Whether `a` and `b` are one edit apart: one character inserted, removed or replaced, or two neighbours swapped.
local function near(a, b)
    local la, lb = #a, #b
    if la == lb then
        local i = 1
        while i <= la and a:byte(i) == b:byte(i) do
            i = i + 1
        end
        if i > la then
            return false
        end -- equal
        if a:sub(i + 1) == b:sub(i + 1) then
            return true
        end
        return a:sub(i, i + 1) == b:sub(i + 1, i + 1) .. b:sub(i, i) and a:sub(i + 2) == b:sub(i + 2)
    end
    if la < lb then
        a, b, la, lb = b, a, lb, la
    end
    if la - lb ~= 1 then
        return false
    end
    local i = 1
    while i <= lb and a:byte(i) == b:byte(i) do
        i = i + 1
    end
    return a:sub(i + 1) == b:sub(i)
end
F.Near = near

-- Why value `v` does not fit row `r`'s type and bounds (V2), or nil.
local function misfit(r, v)
    local ok = false
    for _, a in ipairs(r.alts) do
        local list = a:match("^list:(.+)$")
        if list then
            if type(v) == "table" then -- an empty list is one (a single-rank `copy`)
                ok = true
                for _, x in ipairs(v) do
                    if not isa(list, x) then
                        ok = false
                        break
                    end
                end
                if ok and list == "enum" then
                    for _, x in ipairs(v) do
                        if not r.enum[x] then
                            return "lists " .. tostring(x) .. ", not one of its values"
                        end
                    end
                end
            end
        elseif isa(a, v) or (a == "fn" and r.on == "ability" and type(v) == "table" and rawget(v, "byRank") ~= nil) then
            ok = true
            if a == "enum" and not r.enum[v] then
                return "is " .. tostring(v) .. ", not one of " .. table.concat(r.enumList, ", ")
            end
        end
        if ok then
            break
        end
    end
    if not ok then
        return "is a " .. type(v) .. ", not " .. r.type
    end
    if type(v) == "number" then
        if v ~= v then
            return "is not a number (NaN)"
        end
        if r.min and v < r.min then
            return "is " .. v .. ", below " .. r.min
        end
        if r.max and v > r.max then
            return "is " .. v .. ", above " .. r.max
        end
        if r.gt and not (v > r.gt) then
            return "is " .. v .. ", not above " .. r.gt
        end
    end
end
F.Misfit = misfit

local function packOf(spec)
    if spec and spec.id == 0 then
        return "Shared"
    end -- spec 0: the shared and race content, and the core's own
    return tostring(spec and (spec.name or spec.key or spec.id) or "?")
end

-- V3: each key `v` names (a list's every entry) waits for F.Finish: a string by the row's reference alternative, a
-- table by its list-of-references alternative, whatever their order (aura|list:aura).
local function refer(r, v, who, field)
    for _, a in ipairs(r.alts) do
        local list = a:match("^list:(.+)$")
        local kind = KIND_OF[list or a]
        if kind and not list and type(v) == "string" then
            F.pending[#F.pending + 1] = { kind = kind, value = v, who = who, field = field }
            return
        elseif kind and list and type(v) == "table" then
            for _, x in ipairs(v) do
                if type(x) == "string" then
                    F.pending[#F.pending + 1] = { kind = kind, value = x, who = who, field = field }
                end
            end
            return
        end
    end
end

-- Whether ability `data` names a positive spell ID (its id, a rank or a copy), as Tracked.lua's idsOf asks.
local function spellIds(data)
    local ids = { data.id, data.copy, data.ranks }
    for i = 1, 3 do -- not ipairs: any of the three may be nil
        local v = ids[i]
        if type(v) == "number" and v > 0 then
            return true
        end
        if type(v) == "table" then
            for _, x in ipairs(v) do
                if type(x) == "number" and x > 0 then
                    return true
                end
            end
        end
    end
    return false
end

--- Checks registration `data` (object kind `on`, key `key`) of `spec` against the registry: V1, V2, V7 here, V3 and V4
--- queued for F.Finish, V5 listed. Reads `data` only (never its metatable or a function). Raises on a failure.
--- Once ns.LoadContent has run the end-of-load pass (F.closed), returns at once: a later registration (the simulation's
--- unknown-aura fallbacks, Engine/Sim/State.lua applyBuff and applyDebuff) is unchecked, as before the registry.
function F.Check(on, spec, key, data)
    if F.closed then
        return
    end
    local rows = F.rows[on]
    local who = packOf(spec) .. " " .. on .. " " .. tostring(key)
    for k, v in pairs(data) do
        local r = type(k) == "string" and rows[k]
        if not r then
            local close
            if type(k) == "string" then
                for _, name in ipairs(F.names[on]) do
                    -- one edit on a name of 2 or 3 letters is no evidence of a typo (cd, icd and ids against id)
                    if #name >= 4 and near(k, name) then
                        close = name
                        break
                    end
                end
            end
            if close then
                fail(1, who, k, "is one edit from " .. close)
            end
            if STRICT[on] then
                fail(1, who, k, "is no field of a " .. on .. " entry")
            end
            F.findings[#F.findings + 1] = who .. ": " .. tostring(k) .. " (V1)"
        else
            local why = misfit(r, v)
            if why then
                fail(2, who, k, why)
            end
            refer(r, v, who, k)
            local other = r.atLeast and data[r.atLeast]
            if type(v) == "number" and type(other) == "number" and v < other then
                fail(7, who, k, "is " .. v .. ", below its " .. r.atLeast .. " " .. other)
            end
        end
    end
    if on == "meta" and type(data.fsr) == "table" then
        F.Check("fsr", spec, key, data.fsr)
    elseif on == "ability" then
        if data.expects ~= nil then -- V4 needs the ticking aura, which may register later
            F.pending[#F.pending + 1] = {
                landing = true,
                key = key,
                who = who,
                expects = data.expects,
                velocity = data.velocity,
                school = data.school,
                onNextSwing = data.onNextSwing,
                cycle = data.cycle,
                aura = data.aura,
            }
        elseif data.startsCombat == true and data.variantOf == nil and spellIds(data) then
            -- only what the belief compiles (Tracked.lua: no variant, a positive spell ID)
            F.unlanded[#F.unlanded + 1] = packOf(spec) .. " " .. tostring(key)
        end
    end
end

-- The aura `name` the belief's build hands it, when it declares a tick_time (a number above 0 or a function:
-- RegisterAura keeps the declared one as `base_tick_time`, raw or in `funcs`). Found as the belief finds it: the entry
-- under `name` in a class spec (the kit, which every tree reads) before the shared spec's, as Activation merges
-- { the active spec, 0 }; then only when the build compiles it (Tracked.lua ns.TrackedAuraIds: a primary key, a
-- positive spell ID or the id-less weapon-enchant exception). Raw reads only: no aura's onLoad runs at load.
local function tickAura(name)
    if type(name) ~= "string" then
        return
    end
    local au
    for id, s in pairs(class.specs) do
        local t = id ~= 0 and rawget(s, "auras")
        au = t and rawget(t, name)
        if au then
            break
        end
    end
    if not au then
        local shared = class.specs[0]
        au = shared and rawget(shared, "auras") and rawget(shared.auras, name)
    end
    if not (au and ns.TrackedAuraIds(au, name, rawget)) then
        return
    end
    local funcs = rawget(au, "funcs") or {}
    local tt = rawget(au, "base_tick_time")
    if tt == nil then
        tt = rawget(funcs, "base_tick_time")
    end
    if tt == nil then
        tt = rawget(au, "tick_time")
    end
    if tt == nil then
        tt = rawget(funcs, "tick_time")
    end
    if type(tt) == "function" or (type(tt) == "number" and tt > 0) then
        return au
    end
end

--- V4: why ability record `d` (expects, velocity, school, onNextSwing) with ticking aura `au` (nil: none) is malformed,
--- or nil: Families/Expect.lua's rule past the type checks V2 makes.
function F.Landing(d, au)
    local e, dot = d.expects, au and rawget(au, "dot")
    if e == "debuff" and (d.school ~= nil or dot == "debuff") then
        return 'debuff deals no direct damage: no school, no dot = "debuff" aura'
    elseif e == "instant" and d.school == nil then
        return 'instant needs a school (no damage: expects "debuff")'
    elseif e == "travel" and d.velocity == nil then
        return "travel needs velocity"
    elseif e == "ticks" and dot ~= "debuff" then
        return 'ticks needs an aura with tick_time and dot = "debuff"'
    elseif e == "channel" and not au then
        return "channel needs an aura with tick_time"
    elseif e == "strike" and not d.onNextSwing then
        return "strike needs onNextSwing"
    end
end

local function registered(kind, value)
    for _, s in pairs(class.specs) do
        local t = rawget(s, kind)
        if t and rawget(t, value) ~= nil then
            return true
        end
    end
    return false
end

--- The end of the load (ns.LoadContent, after the class pack): V3 and V4 over everything queued since the last call.
--- Raises on the first failure. Load only.
function F.Finish()
    local pending = F.pending
    F.pending = {}
    for _, p in ipairs(pending) do
        if p.landing then
            local why = F.Landing(p, tickAura(p.cycle or p.aura or p.key))
            if why then
                fail(4, p.who, "expects", why)
            end
        elseif not registered(p.kind, p.value) then
            fail(3, p.who, p.field, "names " .. p.value .. ", which no registration declares (" .. p.kind .. ")")
        end
    end
end

local row = F.Row
local SCHOOLS = {}
for k in pairs(ns.SCHOOL) do
    SCHOOLS[#SCHOOLS + 1] = k
end
table.sort(SCHOOLS)

-- Abilities: Hekili's own fields, then the Forever content fields (Spec/Abilities.lua's notes, Content.lua's API list).
row(
    "ability",
    "id",
    "number|fn",
    "a pseudo ID below 0",
    "the spell ID (rank 1); an item or pseudo ability gets a negative one"
)
row("ability", "copy", "key|list:key", nil, "other IDs or keys that name this ability (its other ranks)")
row("ability", "ranks", "list:number", nil, "the rank IDs in order: gives id, copy and known (Spec/Ranks.lua)")
row("ability", "effect", "fn", nil, "one factory for both the handler and now, when neither is declared")
row("ability", "name", "string", "the spell's name", "the display name, in place of the client's")
row("ability", "suffix", "string", nil, "words added after the client's name")
row("ability", "texture", "number|string|fn", "the spell's icon", "the icon, in place of the client's")
row("ability", "listName", "string", nil, "the label in the options' ability list")
row("ability", "unlisted", "bool", false, "true: kept out of the options' ability list")
row("ability", "indicator", "string", nil, "a small marker drawn on the recommendation's icon")
row("ability", "item", "number|fn", nil, "the item this ability uses")
row("ability", "items", "list:number", nil, "more items the same ability uses")
row("ability", "bagItem", "bool", false, "true: the item is used from the bags, not equipped")
row("ability", "category", "number", nil, "the item's cooldown category (no reader in the core today)")
row("ability", "categoryCooldown", "number", nil, "seconds a use holds its category's other items", { min = 0 })
row("ability", "consumable", "fn", nil, "the consumable's state key")
row("ability", "passive", "bool", false, "true: a spellbook passive the belief tracks the known rank of; never cast")
row("ability", "known", "bool|number|fn", "the spellbook", "whether the player has it")
row("ability", "usable", "bool|fn", true, "whether it may be recommended now")
row("ability", "usable_on", "fn", nil, "a check of the target it may be used on")
row("ability", "cast", "number|fn", 0, "the cast time in seconds, haste-scaled unless fixedCast", { min = 0 })
row("ability", "fixedCast", "bool", false, "true: the cast time ignores haste")
row("ability", "channeled", "bool", false, "true: a channel (start, tick, finish)")
row("ability", "cooldown", "number|fn", 0, "the cooldown in seconds", { min = 0 })
row("ability", "recharge", "number|fn", "the cooldown", "a charge's recharge in seconds", { min = 0 })
row("ability", "charges", "number|fn", 1, "the charges it holds", { min = 1 })
row("ability", "hasteCD", "bool", false, "true: the cooldown and recharge are haste-scaled")
row(
    "ability",
    "gcd",
    "enum|fn",
    "spell",
    "the global cooldown kind it triggers",
    { enum = { "spell", "totem", "off" } }
)
row("ability", "gcdTime", "number|fn", nil, "the global cooldown's length, in place of the kind's", { min = 0 })
row("ability", "spend", "number|fn", nil, "its cost (a fraction of the pool below 1, or of the base with spendBase)")
row("ability", "spendType", "resource", nil, "the resource its cost is paid in")
row("ability", "spendBase", "bool", false, "true: the cost is always a fraction of the pool's base power")
row("ability", "startsCombat", "bool", false, "true: casting it on an enemy starts combat")
row("ability", "toggle", "string", nil, "the toggle that gates it (cooldowns, defensives, interrupts, a custom one)")
row("ability", "essential", "bool", false, "true: recommended even while its toggle is off")
row("ability", "interrupt", "bool", false, "true: an interrupt")
row("ability", "readyTime", "number|fn", nil, "seconds until it may be used, beside the cooldown")
row("ability", "timeToReady", "number|fn", nil, "seconds until it may be used, in place of the cooldown")
row("ability", "range", "number|fn", nil, "its range in yards", { min = 0 })
row("ability", "rangeSpell", "number|fn", nil, "the spell whose range the range check reads")
row("ability", "equipped", "string|number", nil, "a slot kind or item that must be equipped")
row("ability", "talent", "talent", nil, "the talent it needs")
row("ability", "form", "aura|fn", nil, "the form or stance aura it needs")
row("ability", "buff", "aura|list:aura|fn", nil, "a player aura it needs (a list: each of them)")
row("ability", "nobuff", "aura|list:aura", nil, "a player aura it may not be used under (a list: any of them)")
row("ability", "debuff", "aura|list:aura", nil, "a target aura it needs (a list: each of them)")
row("ability", "aura", "aura", "its own key", "the aura it applies (the simulation's and the belief's)")
row("ability", "cycle", "aura|fn", nil, "the target aura a target swap spreads")
row("ability", "auras", "table", nil, "auras registered with it (RegisterAuras)")
row("ability", "meta", "table", nil, "named state functions read through the ability")
row("ability", "tick_time", "number|fn", nil, "a channel's tick in seconds", { gt = 0 })
row("ability", "velocity", "number", nil, "a projectile's speed in yards a second", { gt = 0 })
row("ability", "flightTime", "number|fn", nil, "a projectile's flight in seconds", { min = 0 })
row("ability", "isProjectile", "bool", "with velocity or flightTime and impact", "true: a projectile")
row("ability", "dual_cast", "bool", false, "true: may be cast beside another")
row(
    "ability",
    "healthGate",
    "number",
    nil,
    "the target health percent at or below which it is usable",
    { min = 0, max = 100 }
)
row("ability", "excess_cap", "fn", nil, "the resource it may spend past its cost")
row("ability", "movesOnly", "bool", false, "true: a movement spell (no reader in the core today)")
row("ability", "resets", "table", nil, "the cooldowns it ends")
row("ability", "ttdBelow", "table", nil, "a time-to-die hint sent to the time-to-die source")
row("ability", "variantOf", "ability", nil, "another ability's spell under its own key and toggle")
row(
    "ability",
    "sequence_ignore",
    "list:enum",
    nil,
    "the gates a stepped window's start test skips",
    { enum = { "form", "noform", "buff", "nobuff" } }
)
for _, name in ipairs({ "handler", "start", "tick", "finish", "impact", "sequence_ready" }) do
    row("ability", name, "fn", nil, "the simulation's " .. name .. " function")
end
row("ability", "now", "fn", nil, "the belief's effect of the cast, in its own verbs")
row("ability", "now_finish", "fn", nil, "the belief's effect when a channel runs to its end")
row("ability", "onCrit", "fn", nil, "the belief's extra effect of the cast's own critical hit")
row("ability", "onLand", "fn", nil, "the belief's effect once the cast's hit is settled as landed")
row("ability", "onAvoid", "fn", nil, "what the belief takes back when the cast is dodged, parried or missed")
row(
    "ability",
    "expects",
    "enum",
    "derived from startsCombat and onNextSwing",
    "the evidence that this cast landed",
    { enum = { "none", "instant", "debuff", "travel", "strike", "ticks", "channel" } }
)
row("ability", "school", "enum", "any school", "the school of its direct damage", { enum = SCHOOLS })
row("ability", "onNextSwing", "bool", false, "true: it replaces the next melee swing")
row("ability", "rangedSwing", "bool", false, "true: the ranged auto-attack")
row("ability", "startsAtLanding", "bool", false, "true: the belief starts its target auras when the projectile lands")
row("ability", "missable", "bool|aura", nil, "a missed cast leaves this debuff (true: its own key) off the target")
row("ability", "ladder", "bool", true, "false: its short answers are no rungs of the belief's cost ladder")
row(
    "ability",
    "refundOnAvoid",
    "bool|number",
    nil,
    "the share of the cost given back on an avoid (true: the resource's)",
    { min = 0, max = 1 }
)
row("ability", "refundNowOnAvoid", "bool", false, "true: an avoid also gives back what the cast's now spent")

-- Auras.
row("aura", "id", "number", "a pseudo ID below 0", "the spell ID")
row("aura", "copy", "key|list:key", nil, "other IDs or keys that name this aura")
row("aura", "name", "string", "the spell's name", "the display name")
row("aura", "duration", "number|fn", 30, "seconds it lasts", { min = 0 })
row("aura", "max_stack", "number|fn", 1, "its most stacks", { min = 1 })
row("aura", "tick_time", "number|fn", nil, "seconds between ticks, haste-scaled unless tick_fixed", { gt = 0 })
row("aura", "tick_fixed", "bool", false, "true: the tick ignores haste")
row(
    "aura",
    "dot",
    "enum",
    nil,
    "a periodic aura on the target (debuff) or the player (buff)",
    { enum = { "buff", "debuff" } }
)
row("aura", "shared", "string", nil, "the unit whose aura of anyone's casting it reads")
row("aura", "generate", "fn", nil, "fills the aura's state itself")
row("aura", "meta", "table", nil, "named state functions read through the aura")
row("aura", "alias", "list:aura", nil, "the auras this one stands for")
row("aura", "aliasMode", "enum", nil, "which of the aliases answers", { enum = { "first", "longest", "shortest" } })
row("aura", "aliasType", "enum", nil, "where the aliases are looked up", { enum = { "buff", "debuff" } })
row("aura", "cdm", "bool", true, "false: the Cooldown Manager's entry is never read for it")
row("aura", "family", "string", nil, "a set of auras the Cooldown Manager shows as one entry")
row("aura", "consumedBy", "table", nil, "the row kinds that spend a charge of it")
row("aura", "consumeIcd", "number", 0, "seconds between two spends by consumedBy", { min = 0 })
row("aura", "icd", "number", nil, "seconds before it can proc again", { min = 0 })
row("aura", "icdSpell", "number", nil, "the spell of that internal cooldown (no reader in the core today)")
row("aura", "overlay", "number", nil, "the spell whose overlay glow shows the proc while the aura walk is secret")
row("aura", "isStealthed", "bool", false, "true: up while the client says the player is stealthed")
row("aura", "weaponEnchant", "number", nil, "the weapon slot (0 main, 1 off) whose enchant it is", { min = 0, max = 1 })
row("aura", "enchants", "list:number", nil, "the enchant IDs that put it up on either weapon")
row("aura", "spellHaste", "number", nil, "the spell haste it gives, split from the out-of-combat read", { min = 0 })
row("aura", "swingHaste", "number", nil, "the melee haste it gives, split from the out-of-combat read", { min = 0 })
row("aura", "stats", "table", nil, "the flat stats it gives, split from the out-of-combat read")
row("aura", "statsPct", "table", nil, "the stat percentages it gives, split from the out-of-combat read")

-- A resource's meta (the fourth argument of RegisterResource) and its five-second rule.
row("meta", "max", "number|fn", 100, "the pool's maximum")
row("meta", "base", "number", nil, "the pool's base power at the top level (a percent-of-base cost)", { min = 0 })
row("meta", "regen", "number|fn", nil, "the declared base rate a second")
row("meta", "decay", "number|fn", nil, "the loss a second out of combat")
row("meta", "decayInterval", "number|fn", nil, "seconds per quantum of that loss (0: continuous)", { min = 0 })
row("meta", "refundOnAvoid", "number", nil, "the share of an avoided cast's cost given back", { min = 0, max = 1 })
row("meta", "fsr", "table", nil, "the five-second rule's parts (spirit, mp5, share)")
row("fsr", "spirit", "number|fn", nil, "the spirit part a second, paused after our spend")
row("fsr", "mp5", "number|fn", nil, "the part a second that never pauses")
row("fsr", "share", "number|fn", nil, "the spirit part's share kept while casting", { min = 0, max = 1 })

-- A regen entry (the second argument of RegisterResource).
row("regen", "resource", "resource", "the registering resource", "the resource it fills")
row("regen", "aura", "aura", nil, "the player aura it needs up")
row("regen", "debuff", "aura", nil, "the target aura it needs up")
row("regen", "talent", "talent", nil, "the talent it needs")
row("regen", "spec", "key", nil, "the spec it needs")
row("regen", "equip", "key", nil, "the item it needs")
row("regen", "set_bonus", "string", nil, "the set bonus it needs")
row("regen", "setting", "string", nil, "the setting it needs")
row("regen", "channel", "string", nil, "the channel it needs")
row("regen", "item", "number", nil, "the item that gives it")
row("regen", "value", "number|fn", nil, "the amount each beat")
row("regen", "interval", "number|string|fn", nil, "seconds between beats, or a state name (a hand's speed)", { gt = 0 })
row("regen", "last", "fn", nil, "the time of the last beat")
row("regen", "stop", "fn", nil, "whether the beats have stopped")
row("regen", "swing", "enum", nil, "the hand whose melee swing pays it", { enum = { "mainhand", "offhand" } })
row("regen", "crit", "number|fn", nil, "a swing's extra amount on a critical hit")
row("regen", "width", "number|fn", nil, "a swing amount's half-width (a proc the belief cannot see)")
row("regen", "taken", "fn", nil, "the gain from a hit on the player")
row("regen", "forecastOnly", "bool", false, "true: the simulation's forecast only; the belief pays it another way")
row("regen", "pausesDecay", "bool", false, "true: the out-of-combat loss pauses while its aura is up")
row("regen", "mult", "number", nil, "the whole rate times this while the aura is up (0 stops it)", { min = 0 })
row("regen", "spirit", "number|fn", nil, "the spirit regen times this while the aura is up")
row("regen", "share", "number|fn", nil, "the spirit regen kept while casting, added", { min = 0, max = 1 })
row("regen", "mp5", "number|fn", nil, "a second's flat regen while the aura is up")
row("regen", "mp5Mult", "number", nil, "the gear and buff flat regen times this", { min = 0 })
row("regen", "energize", "bool", false, "true: the mp5 is a periodic energize that ticks its own amount")
