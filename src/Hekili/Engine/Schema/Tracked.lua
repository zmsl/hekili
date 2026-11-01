-- Engine/Schema/Tracked.lua
-- The tracked set (VirtualState spec §3.6, decision 8; border batch 3): what the belief tracks, built from the active
-- spec's registrations (class.*, the race pack's modifiers, the passives, the experimental toggles) and handed to
-- it through ns.VirtualState.Build(def), the core's one build-time call into the belief. The belief reads Hekili's
-- ability and aura tables through `def` as they are: their metatables are Spec.lua's, so a `cooldown` read runs the
-- ability's function under `state`, and `funcs.now`, `funcs.usable`, `expects`, `school` are the pack's declarations.
-- Allocates; SpecializationChanged only.

local addon, ns = ...
local Hekili = _G[addon]
local class = Hekili.Class
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
local NO_PERF = {}
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
                    auraRegen[#auraRegen + 1] = m
                end
            end
        end
        if swing == 0 and offValue ~= nil then
            swing, value, offValue, crit, offCrit = 2, offValue, nil, offCrit, nil -- the off hand alone pays it
        end
        local d = {
            key = k,
            type = r.type,
            token = k:upper(),
            max = r.state and r.state.meta and r.state.meta.max or 100, -- a number or a state-bound function
            rest = ns.ResourceRegenerates(k) == true, -- a regenerating resource rests at its maximum (Resources.lua)
            swing = swing,
            swingValue = value,
            swingOff = offValue,
            swingCrit = crit,
            swingOffCrit = offCrit,
            swingAura = swingAura,
            taken = taken,
            auraRegen = auraRegen,
            decay = r.state and r.state.meta and r.state.meta.decay, -- out-of-combat loss per second (Resources.lua)
            decayInterval = r.state and r.state.meta and r.state.meta.decayInterval, -- seconds per quantum (stepped)
            fsr = r.state and r.state.meta and r.state.meta.fsr, -- the five-second rule's parts (Resources.lua, C3)
            -- the class's default share of an avoided cast's cost given back, for an ability with `refundOnAvoid = true`
            -- (a number, 0-1; Families/Now.lua's Obs.Avoided); the sim never reads it: it does not roll avoidance
            refundOnAvoid = r.state and r.state.meta and r.state.meta.refundOnAvoid,
            base = r.state and r.state.meta and r.state.meta.base, -- the pool's base power (Families/Casts.lua)
            mult = r.state and r.state.regenMult, -- the rate multipliers, out of the regen model (Spec.lua, C3b)
        }
        insert(def.resources, d)
        slotByKey[k] = #def.resources
        -- the race pack's resource and cost modifiers (Engine/Schema/Races.lua, event-facade spec §12b): every resource of the class,
        -- but a maximum modifier never scales a point resource (ns.ResourceIsPoints, Constants.lua)
        local race = ns.raceMods
        if race then
            d.maxMods, d.costMods = not ns.ResourceIsPoints(k) and race.maxMods or nil, race.costMods
            -- the race's regen entries on this resource (Races.lua RegisterRegenMod), after the class's: a fresh list,
            -- so a rebuild never appends to the class's own `regenMult`
            for _, e in ipairs(race.regenMods or {}) do
                if e.resource == k then
                    if d.mult == (r.state and r.state.regenMult) then
                        d.mult = { unpack(d.mult or {}) }
                    end
                    insert(d.mult, e)
                end
            end
        end
    end
    for _, k in ipairs(sortedKeys(class.abilities)) do
        local a = class.abilities[k]
        if a.key == k and k ~= "global_cooldown" then
            local ids = idsOf(a)
            if #ids > 0 then
                insert(def.abilities, a)
                def.abilityIds[#def.abilities] = ids
                local spends = rawget(a, "spend") ~= nil or a.funcs and a.funcs.spend ~= nil
                local slot = spends and slotByKey[a.spendType or class.primaryResource] or 0
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
                insert(def.auras, a)
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
end

--- Rebuilds the belief's tracked set from the active spec (decision 8). Called at the end of
--- Hekili:SpecializationChanged, after every registration. Allocates; SpecializationChanged only.
function ns.BuildTracked()
    buildDef()
    ns.VirtualState.Build(def)
end
