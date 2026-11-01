-- Engine/Schema/Tracked.lua
-- The tracked set (VirtualState spec §3.6, decision 8; border batch 3): what the belief tracks, built from the active
-- spec's registrations (class.*, the race pack's modifiers, the passives, the experimental toggles) and handed to
-- it through ns.VirtualState.Build(def), the core's one build-time call into the belief. `def` carries plain records
-- (border batch 4, the owner's design 2026-11-01): no metatable, never a live Hekili table. Each field is a value, a
-- function the belief runs in its own `now` context, or absent; Spec.lua's `funcs` are flattened in beside the raw
-- fields. A function field may carry a static value the core computes under `state` once the talents are known
-- (ns.TrackedStatics, after ns.updateTalents): the belief's order is the function in its context, then the static only
-- if it raised (a working function's nil is its answer), then 0. The belief runs no function in `def` with `state` as
-- its environment (I.Eval, Game/State/Families/Casts.lua, swaps it for the call; `now`, `onCrit` and `taken` are bound
-- to the context), but a pack function naming `state` through a file-level upvalue still reaches it, until border
-- batch 5 closes them (docs/dev/architecture.md §1). Allocates; SpecializationChanged only.

local addon, ns = ...
local Hekili = _G[addon]
local class = Hekili.Class
local state = Hekili.State
local insert, sort = table.insert, table.sort
local floor = math.floor

local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local def = {
    abilities = {},
    abilityIds = {},
    abilitySlot = {},
    resources = {},
    auras = {},
    auraIds = {},
    talents = {},
    units = {},
    pets = {}, -- the guardians: { key, cap, duration, slot } of each pet registered with a `cap` (Families/Pets.lua)
    providers = {}, -- outcomes, presence, viewer: the experimental toggles (providersOf)
    settings = {}, -- the spec's settings as plain values (Families/Now.lua's `settings`; refreshed by Hekili:SettingsChanged)
}
local LISTS = { "abilities", "abilityIds", "abilitySlot", "resources", "auras", "auraIds", "talents", "units", "pets" }

local HANDS = { mainhand = 1, offhand = 2 }
local NO_PETS = {} -- a test's stand-in class may have no `pets`
-- The sim's own generated entries (Spec.lua RegisterResource: the stepped decay and the hits taken), reserved names
-- the walk below skips: they are no regen entries of the belief.
local DECAY, TAKEN = "__decay", "__taken"

-- The passives (RegisterAbility{ passive = true }): spells the spellbook knows and the player never casts; the belief
-- tracks their known rank, the sim never sees them. Load time; never cleared (one session, one class).
local passives = {}
function ns.TrackPassive(id)
    insert(passives, id)
end

-- The spell IDs of a registration: its `id`, then its `copy` IDs (rank order), positive numbers only.
local function idsOf(obj)
    local ids = {}
    if type(obj.id) == "number" and obj.id > 0 then
        ids[1] = obj.id
    end
    local copy = obj.copy
    if type(copy) == "number" and copy > 0 then
        ids[#ids + 1] = copy
    elseif type(copy) == "table" then
        for _, v in ipairs(copy) do
            if type(v) == "number" and v > 0 then
                ids[#ids + 1] = v
            end
        end
    end
    return ids
end

-- A plain copy of `v`: a table's raw fields by value, its sub-tables copied the same way (a `copy` list, `consumedBy`,
-- a resource meta), never its metatable; a cycle maps to the copy already made. Functions and scalars as they are.
local function plain(v, seen)
    if type(v) ~= "table" then
        return v
    end
    if seen[v] then
        return seen[v]
    end
    local out = {}
    seen[v] = out
    for k, x in pairs(v) do
        out[k] = plain(x, seen)
    end
    return out
end

-- The plain record of registration `a` (an ability or an aura): its raw fields, then Spec.lua's `funcs` flattened in
-- (a declared function beside the values; a raw field of the same name wins). `spend` is the cost as declared (Races.lua's
-- Wrap keeps it as `declaredSpend`; the sim's wrapped `spend` and `baseSpend` are its own). `onLoad` is a client read of
-- the core's, never the belief's.
local function recordOf(a)
    local rec = plain(a, {})
    local declared = rawget(a, "declaredSpend")
    if declared ~= nil then
        rec.spend = declared
    end
    local funcs = rawget(a, "funcs")
    rec.funcs = nil
    if type(funcs) == "table" then
        for k, f in pairs(funcs) do
            if rec[k] == nil then
                rec[k] = f
            end
        end
    end
    rec.baseSpend, rec.declaredSpend, rec.onLoad = nil, nil, nil
    return rec
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" then
            keys[#keys + 1] = k
        end
    end
    sort(keys)
    return keys
end

-- (providers spec §3.4, decision 82) The experimental toggles as the build config's providers. The router is always
-- injected; without the viewer leaf it covers nothing (the Default path). No engine where a test loads the schema alone.
local NO_PERF, NO_META, NO_SETTINGS = {}, {}, {}
-- The active spec's settings (Engine.settings.specs[id].settings, the profile's) copied as plain values into
-- def.settings, which Families/Now.lua's `settings` reads: a pack's `usable` may gate on one (`settings.behind`).
-- The sim's `state.settings` reads the profile live; the record is refreshed by Hekili:SettingsChanged at every write.
local function settingsOf()
    local e = Hekili.Engine
    local specs = e and e.settings.specs
    local spec = specs and state and state.spec and specs[state.spec.id]
    local src = spec and spec.settings or NO_SETTINGS
    local dst = def.settings
    wipe(dst)
    for k, v in pairs(src) do
        if type(v) ~= "table" and type(v) ~= "function" then
            dst[k] = v
        end
    end
end

--- A spec setting changed (Spec.lua's setters, Options/ChatCommands.lua): the belief's plain copy follows. No rebuild.
function Hekili:SettingsChanged()
    settingsOf()
end

-- The fields a pack may declare as a function and the belief prices with: each gets a static value computed under
-- `state` once the talents are known (ns.TrackedStatics), the live game's safety net when its function raises in the
-- belief's context (the test suite fails on the raise itself).
local STATIC_FIELDS = { "cooldown", "spend", "gcdTime" }

--- Fills each ability record's `static` (by field, a number) from its declared functions under `state`. Called by
--- Hekili:SpecializationChanged AFTER ns.updateTalents (a static computed at Build would see the previous spec's talent
--- ranks: Build must precede updateTalents, whose ranks come from the belief's talent walk in Build). Allocates;
--- SpecializationChanged only.
function ns.TrackedStatics()
    for i = 1, #def.abilities do
        local rec = def.abilities[i]
        rec.static = nil
        for _, field in ipairs(STATIC_FIELDS) do
            local f = rec[field]
            if type(f) == "function" then
                local ok, v = pcall(f)
                if ok and type(v) == "number" then
                    rec.static = rec.static or {}
                    rec.static[field] = v
                end
            end
        end
    end
end

local function providersOf()
    local e = Hekili.Engine
    local p = e and e.settings.performance or NO_PERF
    return p.damageMeter == true and "meter" or "default", "router", p.cooldownViewer == true
end

local function buildDef()
    for _, name in ipairs(LISTS) do
        wipe(def[name])
    end
    local pv = def.providers
    pv.outcomes, pv.presence, pv.viewer = providersOf()
    def.school = ns.SCHOOL -- the spell schools by name (Families/Expect.lua compiles an ability's `school` to the mask)
    def.error = ns.Error -- the core's error channel (Sources/Forms.lua warns once per untracked form)
    -- the game constants, defined once in Engine/Sim/Constants.lua (border batch 3 item 4): the five-second rule's
    -- window (Families/Resources.lua), the GCD spell (Sources/Spellbook.lua, the facade) and the usability oracle's lag
    -- (Events/Melee.lua)
    def.fsr, def.gcdSpell, def.oracleMin = ns.FSR, ns.GCD_SPELL, ns.ORACLE_MIN
    local slotByKey = {}
    for _, k in ipairs(sortedKeys(class.resources)) do
        local r = class.resources[k]
        local swing, value, offValue, auraRegen, swingAura = 0, nil, nil, nil, nil
        local crit, offCrit -- a white crit's extra amount by hand (Resources.lua, I.SwingCrit)
        local taken -- the paying entry's gain from a hit on the player (Resources.lua, tank design §1.2)
        local model = r.state and r.state.regenModel
        if model then
            for name, m in pairs(model) do
                if m.swing == "offhand" then
                    offValue, offCrit = m.value, m.crit
                elseif m.swing and HANDS[m.swing] and swing == 0 then
                    swing, value, swingAura = HANDS[m.swing], m.value, m.aura -- `aura`: swings pay only while it is up
                    crit, taken = m.crit, m.taken
                elseif
                    name ~= DECAY
                    and name ~= TAKEN
                    and not (m.swing or m.debuff or m.channel or m.spec or m.equip or m.set_bonus or m.setting)
                then
                    auraRegen = auraRegen or {}
                    -- a player aura's regen { aura, interval, value }, or without `aura` a periodic one credited in
                    -- combat; either may name a `talent` (Resources.lua). Hekili's other gates are unseen there, so an
                    -- entry with one is not forwarded.
                    auraRegen[#auraRegen + 1] = plain(m, {})
                end
            end
        end
        if swing == 0 and offValue ~= nil then
            swing, value, offValue, crit, offCrit = 2, offValue, nil, offCrit, nil -- the off hand alone pays it
        end
        local meta = r.state and r.state.meta or NO_META
        local d = {
            key = k,
            type = r.type,
            token = k:upper(),
            max = meta.max or 100, -- a number, or a function the belief runs in its context
            rest = ns.ResourceRegenerates(k) == true, -- a regenerating resource rests at its maximum (Resources.lua)
            swing = swing,
            swingValue = value,
            swingOff = offValue,
            swingCrit = crit,
            swingOffCrit = offCrit,
            swingAura = swingAura,
            taken = taken,
            auraRegen = auraRegen,
            decay = meta.decay, -- out-of-combat loss per second (Resources.lua)
            decayInterval = meta.decayInterval, -- seconds per quantum (stepped)
            fsr = plain(meta.fsr, {}), -- the five-second rule's parts (Resources.lua, C3)
            -- the class's default share of an avoided cast's cost given back, for an ability with `refundOnAvoid = true`
            -- (a number, 0-1; Families/Now.lua's Obs.Avoided); the sim never reads it: it does not roll avoidance
            refundOnAvoid = meta.refundOnAvoid,
            base = meta.base, -- the pool's base power (Families/Casts.lua)
            mult = plain(r.state and r.state.regenMult, {}), -- the rate multipliers, out of the regen model (Spec.lua, C3b)
        }
        insert(def.resources, d)
        slotByKey[k] = #def.resources
        -- the race pack's resource and cost modifiers (Engine/Schema/Races.lua, event-facade spec §12b): every resource of the class,
        -- but a maximum modifier never scales a point resource (ns.ResourceIsPoints, Constants.lua)
        local race = ns.raceMods
        if race then
            d.maxMods = not ns.ResourceIsPoints(k) and plain(race.maxMods, {}) or nil
            d.costMods = plain(race.costMods, {})
            -- the race's regen entries on this resource (Races.lua RegisterRegenMod), after the class's (`mult` is a copy:
            -- a rebuild never appends to the class's own `regenMult`)
            for _, e in ipairs(race.regenMods or {}) do
                if e.resource == k then
                    d.mult = d.mult or {}
                    insert(d.mult, plain(e, {}))
                end
            end
        end
    end
    for _, k in ipairs(sortedKeys(class.abilities)) do
        local a = class.abilities[k]
        if a.key == k and k ~= "global_cooldown" then
            local ids = idsOf(a)
            if #ids > 0 then
                local rec = recordOf(a)
                insert(def.abilities, rec)
                def.abilityIds[#def.abilities] = ids
                local slot = rec.spend ~= nil and slotByKey[rec.spendType or class.primaryResource] or 0
                def.abilitySlot[#def.abilities] = slot
            end
        end
    end
    for _, id in ipairs(passives) do
        insert(def.abilities, { key = "track_" .. id, id = id, cooldown = 0 })
        def.abilityIds[#def.abilities] = { id }
        def.abilitySlot[#def.abilities] = 0
    end
    for _, k in ipairs(sortedKeys(class.auras)) do
        local a = class.auras[k]
        if a.key == k then
            local ids = idsOf(a)
            if #ids == 0 and rawget(a, "weaponEnchant") ~= nil and type(a.id) == "number" then
                ids[1] = a.id -- an id-less weapon-enchant pseudo-aura (C4): RegisterAura's negative pseudo-ID
            end
            if #ids > 0 then
                insert(def.auras, recordOf(a))
                def.auraIds[#def.auras] = ids
            end
        end
    end
    local seen = {}
    for _, k in ipairs(sortedKeys(class.talents)) do
        local v = class.talents[k]
        if type(v) == "table" and type(v[2]) == "number" and not seen[v[2]] then
            seen[v[2]] = true
            insert(def.talents, { key = k, spell = v[2], max = v[3] or 1 })
        end
    end
    for _, k in ipairs(sortedKeys(class.pets or NO_PETS)) do
        local p = class.pets[k]
        if p.token == k and type(p.cap) == "number" and p.cap >= 1 then -- its token's entry, not an alias's
            insert(def.pets, { key = k, cap = floor(p.cap), duration = p.duration, slot = p.slot })
        end
    end
    def.units[1], def.units[2] = "player", "target"
    settingsOf()
end

--- (providers spec §3.4, decision 82; audit E17) The experimental toggles changed (Options' setters): the build's
--- providers follow Engine.settings.performance; the belief swaps at its next drain (out of combat; at combat end
--- otherwise), keeping its records. Never a rebuild.
function Hekili:ProvidersChanged()
    local pv = def.providers
    pv.outcomes, pv.presence, pv.viewer = providersOf()
end

--- Rebuilds the belief's tracked set from the active spec (decision 8). Called at the end of
--- Hekili:SpecializationChanged, after every registration. Allocates; SpecializationChanged only.
function ns.BuildTracked()
    buildDef()
    ns.VirtualState.Build(def)
end
