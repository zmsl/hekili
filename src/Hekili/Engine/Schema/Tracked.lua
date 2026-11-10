-- Engine/Schema/Tracked.lua
-- The tracked set (VirtualState spec §3.6, decision 8; border batch 3): what the belief tracks, built from the active
-- spec's registrations (class.*, the race pack's modifiers, the passives, the providers) and handed to
-- it through ns.VirtualState.Build(def), the core's one build-time call into the belief. `def` carries plain records
-- (border batch 4, the owner's design 2026-11-01): no metatable, never a live Hekili table. Each field is a value, a
-- function the belief runs in its own `now` context, or absent; Spec.lua's `funcs` are flattened in beside the raw
-- fields, and the belief never runs auraRegen's `last`/`stop` or the flattened `handler`, `cast`, `known`. A function field may carry a static value the core computes under `state` once the talents are known
-- (ns.TrackedStatics, after ns.updateTalents): the belief's order is the function in its context, then the static only
-- if it raised (a working function's nil is its answer), then 0. Nothing in `def` runs under `state` at runtime: the
-- belief swaps a function's environment for the call (I.Eval, Game/State/Families/Casts.lua; `now`, `onCrit`, `taken` and
-- a window's `evaluator` are bound to the context), and no function it evaluates captures `state`, `Hekili` or `class`
-- (tests/Forever/plain_records_spec.lua). What only the core knows arrives as a number (`fsrOf`). The declared gear
-- crosses as data (`def.gear`: keys and item or aura IDs); the belief reads the equipment itself. Allocates;
-- SpecializationChanged only.

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
    providers = {}, -- outcomes, presence, viewer (providersOf)
    settings = {}, -- the spec's settings as plain values (Families/Now.lua's `settings`; refreshed by Hekili:SettingsChanged)
    windows = {}, -- the rotation windows (RegisterWindow's records; `steps` as ability indexes): Families/Windows.lua
    reactions = {}, -- RegisterReaction's records { key, who, outcome, hand, now }: Families/Now.lua (no ability index)
    gear = {}, -- the declared gear (spec:RegisterGear's sets and items, spec:RegisterSetBonus's bonuses): Families/Gear.lua
}
local LISTS = {
    "abilities",
    "abilityIds",
    "abilitySlot",
    "resources",
    "auras",
    "auraIds",
    "talents",
    "units",
    "pets",
    "windows",
    "reactions",
    "gear",
}

local HANDS = { mainhand = 1, offhand = 2 }
-- L90: a resource the game binds to one target: only the count on the current target is usable
-- (GetComboPoints("player", "target")); the pool UnitPower answers survives a swap (Game/State/Sources/Power.lua).
local ON_TARGET = { combo_points = true }
-- a test's stand-in class may have no `pets`, `windows`, `reactions`, `gear` or `setBonuses`
local NO_PETS, NO_WINDOWS, NO_GEAR = {}, {}, {}
-- The sim's own generated entries (Spec/Regen.lua RegisterResource: the stepped decay and the hits taken), reserved names
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

-- The five-second rule's parts as numbers, read here: they depend on the spec's tree, the core's fact (a function of
-- a pack names `state.spec`), and only a spec change moves them. A raise is reported and leaves the part out (inert).
local function fsrOf(meta)
    local fsr = plain(meta.fsr, {})
    if type(fsr) == "table" then
        for k, v in pairs(fsr) do
            if type(v) == "function" then
                local ok, n = pcall(v)
                if not ok then
                    ns.Error("Tracked: fsr." .. tostring(k) .. ": " .. tostring(n))
                end
                fsr[k] = ok and n or nil
            end
        end
    end
    return fsr
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

-- (providers spec §3.4, decision 82) The build config's providers. The router is always injected; without the viewer
-- leaf it covers nothing (the Default path). No engine where a test loads the schema alone.
local NO_META, NO_SETTINGS = {}, {}
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
    -- no option for the adaptive providers (cdm-default decision 107): the Outcomes provider is the default one and the
    -- Cooldown Manager is on unless the debug-only session switch Hekili.cdmOff is true; a saved value is ignored
    return "default", "router", Hekili.cdmOff ~= true
end

-- (cdm-panel) The Cooldown Manager switch of aura record `rec` (the Cooldown Manager panel, Options.lua): the profile's
-- per-spec value by aura key when set (profile.specs[id].cdm[key]), else the pack's `cdm = false` (RegisterAura data,
-- copied raw by recordOf), else on (nil). False: the leaf maps none of the aura's items (Presence/CooldownViewer.lua).
local function cdmOf(rec)
    local e = Hekili.Engine
    local specs = e and e.settings.specs
    local spec = specs and state and state.spec and specs[state.spec.id]
    local cdm = type(spec) == "table" and spec.cdm
    if type(cdm) == "table" and type(cdm[rec.key]) == "boolean" then
        return cdm[rec.key]
    end
    local aura = class.auras[rec.key]
    if aura and rawget(aura, "cdm") == false then
        return false
    end
    return nil
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
            onTarget = ON_TARGET[k] == true, -- usable only on the current target (Sources/Power.lua, L90)
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
            fsr = fsrOf(meta), -- the five-second rule's parts, numbers (Resources.lua, C3)
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
            local enchant = rawget(a, "weaponEnchant") ~= nil or type(rawget(a, "enchants")) == "table"
            if #ids == 0 and enchant and type(a.id) == "number" then
                ids[1] = a.id -- an id-less weapon-enchant aura (C4): RegisterAura's negative pseudo-ID
            end
            if #ids > 0 then
                local rec = recordOf(a)
                rec.cdm = cdmOf(rec)
                insert(def.auras, rec)
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
    -- the declared gear (gear-aware spec §4): an item's or a set's piece IDs (RegisterGear's array part), a bonus's aura
    -- spell (RegisterSetBonus); the belief reads the equipment itself (Sources/Gear.lua)
    for _, k in ipairs(sortedKeys(class.gear or NO_GEAR)) do
        local items = {}
        for _, id in ipairs(class.gear[k]) do
            if type(id) == "number" then
                items[#items + 1] = id
            end
        end
        insert(def.gear, { key = k, items = items })
    end
    for _, k in ipairs(sortedKeys(class.setBonuses or NO_GEAR)) do
        local spell = class.setBonuses[k]
        if type(spell) == "number" then
            insert(def.gear, { key = k, aura = spell })
        end
    end
    for _, k in ipairs(sortedKeys(class.pets or NO_PETS)) do
        local p = class.pets[k]
        if p.token == k and type(p.cap) == "number" and p.cap >= 1 then -- its token's entry, not an alias's
            insert(def.pets, { key = k, cap = floor(p.cap), duration = p.duration, slot = p.slot })
        end
    end
    -- the windows, a step's key resolved to its ability index (0: an ability the belief does not track, never due)
    local indexOf = {}
    for i = 1, #def.abilities do
        indexOf[def.abilities[i].key] = i
    end
    for _, k in ipairs(sortedKeys(class.windows or NO_WINDOWS)) do
        local rec = recordOf(class.windows[k])
        for i = 1, rec.steps and #rec.steps or 0 do
            rec.steps[i] = indexOf[rec.steps[i]] or 0
        end
        insert(def.windows, rec)
    end
    for _, k in ipairs(sortedKeys(class.reactions or NO_WINDOWS)) do
        insert(def.reactions, recordOf(class.reactions[k])) -- its `now` crosses as the function itself
    end
    def.units[1], def.units[2] = "player", "target"
    settingsOf()
end

--- (providers spec §3.4, decision 82; audit E17) The providers' inputs changed (Hekili.cdmOff, the harness's arms): the
--- build's providers follow providersOf; the belief swaps at its next drain (out of combat; at combat end
--- otherwise), keeping its records. Never a rebuild.
function Hekili:ProvidersChanged()
    local pv = def.providers
    pv.outcomes, pv.presence, pv.viewer = providersOf()
end

--- (cdm-panel) A Cooldown Manager switch changed (the Cooldown Manager panel's setters): each aura record's `cdm`
--- follows the profile, and def.providers.cdmGen moves so the belief re-activates the presence provider at its next
--- drain, out of combat (at combat end otherwise: Belief.lua I.SetProviders): the leaf rebuilds its map. Never a rebuild.
function Hekili:CdmSwitchChanged()
    for j = 1, #def.auras do
        def.auras[j].cdm = cdmOf(def.auras[j])
    end
    def.providers.cdmGen = (def.providers.cdmGen or 0) + 1
end

--- Rebuilds the belief's tracked set from the active spec (decision 8). Called at the end of
--- Hekili:SpecializationChanged, after every registration. Allocates; SpecializationChanged only.
function ns.BuildTracked()
    buildDef()
    ns.VirtualState.Build(def)
end
