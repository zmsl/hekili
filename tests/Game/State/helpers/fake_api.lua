-- tests/Game/State/helpers/fake_api.lua
-- A fake WoW client for headless VirtualState specs: every source gets the client as an injected `api`, so the specs
-- hand it this one. `ctl` sets what the game would answer; `api.frame:Fire(event, ...)` delivers an event and
-- `ctl.Tick(now)` runs the frame's OnUpdate (the staged flush). Every call the zero-allocation spec makes through it
-- allocates nothing: answers come from preallocated tables.
-- The SECRET proxy is ported from Taco Dog Forever, tests/helpers/wow.lua:16-25.
local M = {}

-- A secret value, as close to the client's as Lua 5.1 allows: comparing, ordering, arithmetic, concatenation,
-- indexing, length and tostring all fail. A boolean test can't be trapped in 5.1, so secrets_spec.lua checks
-- statically that every client read goes through Plain.
local function refuse(what)
    return function()
        error("attempt to " .. what .. " a secret value", 2)
    end
end
M.SECRET = newproxy(true)
do
    local mt = getmetatable(M.SECRET)
    mt.__eq, mt.__lt, mt.__le = refuse("compare"), refuse("compare"), refuse("compare")
    mt.__add, mt.__sub, mt.__mul, mt.__div =
        refuse("do arithmetic on"), refuse("do arithmetic on"), refuse("do arithmetic on"), refuse("do arithmetic on")
    mt.__mod, mt.__pow, mt.__unm = refuse("do arithmetic on"), refuse("do arithmetic on"), refuse("negate")
    mt.__concat, mt.__len, mt.__index = refuse("concatenate"), refuse("get the length of"), refuse("index")
    mt.__tostring = refuse("convert to a string")
end
local SECRET = M.SECRET
-- UnitCreatureType's IDs (CreatureType.db2) by State.lua's `target.creature_type` key.
local CREATURE_IDS = {}
for id, key in ipairs({
    "beast",
    "dragonkin",
    "demon",
    "elemental",
    "giant",
    "undead",
    "humanoid",
    "critter",
    "mechanical",
    "not_specified",
    "totem",
    "non_combat_pet",
    "gas_cloud",
    "wild_pet",
    "aberration",
}) do
    CREATURE_IDS[key] = id
end
local NO_ENCHANTS = {} -- an unenchanted weapon slot's list (shared: the fake allocates nothing per call)

--- A new fake client and its control table.
function M.new()
    local ctl = {
        now = 100,
        combat = false,
        class = "CLASS_A",
        power = {}, -- [powerType] = value (SECRET for a secret read)
        petPower = 0, -- UnitPower("pet") of the pet's power type `petPowerType` while exists.pet (SECRET: a secret read)
        petPowerType = 0,
        itemCount = {}, -- [itemID] = C_Item.GetItemCount (default 0)
        stats = {}, -- [index] = UnitStat's value (its first two returns; default 0)
        powerMax = {}, -- [powerType] = max
        regen = {}, -- [powerType] = { inactive, active }
        usable = {}, -- [spellID] = { ok, short }
        costs = {}, -- [spellID] = GetSpellPowerCost's list (default: none)
        known = {}, -- [spellID] = true
        cooldown = {}, -- [spellID] = { isActive = bool, isOnGCD = bool, startTime = SECRET, duration = SECRET }
        current = {}, -- [spellID] = true while queued (IsCurrentSpell)
        auras = { player = { HELPFUL = {}, HARMFUL = {} }, target = { HELPFUL = {}, HARMFUL = {} } },
        auraError = {}, -- [unit] = true: GetAuraDataByIndex raises (target in combat)
        guid = { player = "Player-1", target = "Creature-1" },
        dead = {},
        exists = { player = true, target = true },
        casting = nil, -- { startMS, endMS } for UnitCastingInfo("player")
        channel = nil,
        speed = { 2.6, nil },
        meleeHaste = 0,
        spellHaste = 0,
        health = 1000,
        healthMax = 1000,
        unitHealth = {}, -- [unit] = UnitHealth (default: health)
        unitHealthMax = {}, -- [unit] = UnitHealthMax (default: healthMax)
        totems = {},
        traits = nil, -- { config = id, trees = { tree }, nodes = { [node] = info }, entries = {}, defs = {} }
        inRange = {}, -- [unit] = true: every range check in range (when `distance` has no entry for the unit)
        distance = {}, -- [unit] = yards (SECRET: a secret answer): range checks against the spell's `ranges`
        ranges = {}, -- [spellID] = { min, max } yards: GetSpellInfo's minRange/maxRange (default 0, 5: melee)
        handlers = {},
        unitSpeed = {}, -- [unit] = speed for UnitAttackSpeed of a unit other than the player (default: secret)
        unitIs = {}, -- [unit] = the token UnitIsUnit(unit, x) is true for (SECRET: a secret answer)
        friendly = {}, -- [unit] = true: UnitCanAttack("player", unit) answers false (default: hostile)
        level = { player = 20 }, -- [unit] = UnitLevel (nil: a secret answer)
        creature = {}, -- [unit] = UnitCreatureType's type as State.lua's key ("undead"; default "beast"; SECRET: secret)
        unknownEvents = {}, -- [event] = true: RegisterEvent raises, as the client does for an event it does not know
        form = 0, -- GetShapeshiftForm (0: none)
        forms = {}, -- [form index] = its spell ID (GetShapeshiftFormInfo's 4th return)
        stealthed = false, -- IsStealthed (SECRET: a secret answer)
        enchants = {}, -- [weapon slot] = C_Item.GetWeaponEnchantInfo's list (SECRET: a secret answer; nil: none)
        enchantCalls = 0, -- C_Item.GetWeaponEnchantInfo calls
        ranged = { 3.1, 30, 40, 0, 0, 1 }, -- UnitRangedDamage("player")
        damage = { 0, 0, 0, 0 }, -- UnitDamage's min and max main, min and max off (the harness's out-of-combat cache)
        classID = 0, -- UnitClass's third return
        specID = nil, -- C_SpecializationInfo.GetSpecializationInfo(1)'s ID (nil: no specialization)
        powerType = { 0, "MANA" }, -- UnitPowerType("player")
        role = "DAMAGER",
        inventory = {}, -- [slot] = itemID (GetInventoryItemID("player", slot))
        items = {}, -- [itemID] = { name, equipLoc } (C_Item.GetItemInfo's first and ninth returns)
        tooltips = {}, -- [spellID] = C_TooltipInfo.GetSpellByID's data ({ lines = { { leftText }... } }; nil: none)
    }
    local api = { ctl = ctl }

    function api.issecretvalue(v)
        return v == SECRET -- rawequal semantics: the proxy's __eq only fires between two proxies
    end
    function api.GetTime()
        return ctl.now
    end
    function api.InCombatLockdown()
        return ctl.combat
    end
    function api.UnitClassBase()
        return ctl.class
    end
    function api.UnitGUID(unit)
        return ctl.guid[unit]
    end
    function api.UnitExists(unit)
        if ctl.exists[unit] == SECRET then
            return SECRET
        end
        return ctl.exists[unit] == true
    end
    function api.UnitIsDead(unit)
        if ctl.dead[unit] == SECRET then
            return SECRET
        end
        return ctl.dead[unit] == true
    end
    function api.UnitCanAttack(_, unit)
        return ctl.friendly[unit] ~= true
    end
    function api.CheckInteractDistance(unit) -- LibRangeCheck's interact checkers: within reach when in range
        return ctl.inRange[unit] == true
    end
    function api.UnitPower(unit, pt)
        if unit == "pet" then -- no pet: plain 0 (probe W PR12, a character with no pet); a secret pet: every type secret
            if ctl.exists.pet ~= true then
                return 0
            elseif ctl.petPower == SECRET then
                return SECRET
            end
            return (pt == nil or pt == ctl.petPowerType) and ctl.petPower or 0 -- another type than the pet's: 0
        end
        local v = ctl.power[pt]
        if v == nil then
            return SECRET
        end
        return v
    end
    function api.UnitPowerMax(_, pt)
        return ctl.powerMax[pt] or 100
    end
    function api.GetPowerRegenForPowerType(pt)
        local r = ctl.regen[pt]
        if not r then
            return SECRET, SECRET
        end
        return r[1], r[2]
    end
    function api.UnitHealth(unit)
        return ctl.unitHealth[unit] or ctl.health
    end
    function api.UnitHealthMax(unit)
        return ctl.unitHealthMax[unit] or ctl.healthMax
    end
    function api.UnitSpellHaste()
        return ctl.spellHaste
    end
    function api.GetMeleeHaste()
        return ctl.meleeHaste
    end
    function api.UnitAttackSpeed(unit)
        if unit ~= nil and unit ~= "player" then
            local v = ctl.unitSpeed[unit]
            if v == nil then
                return SECRET, SECRET
            end
            return v, nil
        end
        return ctl.speed[1], ctl.speed[2]
    end
    function api.UnitLevel(unit)
        local v = ctl.level[unit]
        if v == nil then
            return SECRET
        end
        return v
    end
    function api.UnitIsUnit(a, b)
        if a == b then -- the client: a unit is itself, never a secret (headless loop design §6.1)
            return true
        end
        local v = ctl.unitIs[a]
        if v == SECRET then
            return SECRET
        end
        return v == b
    end
    function api.GetShapeshiftForm()
        return ctl.form
    end
    function api.GetNumShapeshiftForms()
        return #ctl.forms
    end
    function api.GetShapeshiftFormInfo(i)
        return 0, i == ctl.form, true, ctl.forms[i]
    end
    function api.IsStealthed()
        return ctl.stealthed
    end
    function api.UnitCreatureFamily() end -- no pet
    function api.UnitRangedDamage()
        local r = ctl.ranged
        return r[1], r[2], r[3], r[4], r[5], r[6]
    end
    function api.GetTotemInfo(slot)
        local t = ctl.totems[slot]
        if not t then
            return false, "", 0, 0, 0
        end
        return true, t.name, t.start, t.duration, t.icon, 1, t.spell
    end
    function api.UnitCastingInfo()
        local c = ctl.casting
        if not c then
            return nil
        end
        return "Cast", "", 0, c[1], c[2]
    end
    function api.UnitChannelInfo()
        local c = ctl.channel
        if not c then
            return nil
        end
        return "Channel", "", 0, c[1], c[2]
    end
    local stats = { 0, 0, 0, 0, 0, 0, 0 }
    local function zeros()
        return stats[1], stats[2], stats[3], stats[4], stats[5], stats[6], stats[7]
    end
    function api.UnitStat(_, index)
        local v = ctl.stats[index] or 0
        return v, v, 0, 0
    end
    api.GetSpellBonusDamage, api.UnitAttackPower, api.UnitWeaponAttackPower = zeros, zeros, zeros
    api.UnitArmor, api.GetMasteryEffect, api.GetCritChance = zeros, zeros, zeros
    function api.UnitDamage()
        local d = ctl.damage
        return d[1], d[2], d[3], d[4], 0, 0, 1
    end
    api.GetShieldBlock = zeros
    api.GetSpellCritChance, api.GetRangedCritChance, api.GetCombatRating, api.GetCombatRatingBonus =
        zeros, zeros, zeros, zeros
    api.CR_CRIT_MELEE, api.CR_HASTE_MELEE, api.CR_CRIT_TAKEN_SPELL, api.CR_MASTERY = 10, 18, 11, 26
    api.CR_VERSATILITY_DAMAGE_DONE, api.CR_VERSATILITY_DAMAGE_TAKEN = 29, 31

    local READY = { isActive = false, isOnGCD = false, startTime = SECRET, duration = SECRET }
    local COSTS = {}
    api.C_Spell = {
        IsSpellUsable = function(id)
            local u = ctl.usable[id]
            if not u then
                return false, false
            end
            return u[1], u[2]
        end,
        GetSpellCooldown = function(id)
            return ctl.cooldown[id] or READY
        end,
        IsCurrentSpell = function(id)
            return ctl.current[id] == true
        end,
        GetSpellPowerCost = function(id)
            return ctl.costs[id] or COSTS
        end,
        IsSpellInRange = function(id, unit)
            local d = ctl.distance[unit]
            if d == SECRET then
                return SECRET
            elseif d == nil then
                return ctl.inRange[unit] == true
            end
            local r = ctl.ranges[id]
            local lo, hi = r and r[1] or 0, r and r[2] or 5
            if hi == 0 then
                return nil -- no range check (the client's nil)
            end
            return d >= lo and d <= hi
        end,
    }
    api.C_SpellBook = {
        IsSpellKnown = function(id)
            return ctl.known[id] == true
        end,
    }
    api.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            if ctl.auraError[unit] then
                error("Auras cannot be accessed when secret while tainted")
            end
            local list = ctl.auras[unit] and ctl.auras[unit][filter]
            return list and list[i]
        end,
    }
    -- absent on Forever (the facade's virtual rows); a secret-free client's, for the headless loop's oracle (o.raw)
    function api.C_UnitAuras.GetBuffDataByIndex(unit, i)
        return api.C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
    end
    function api.C_UnitAuras.GetDebuffDataByIndex(unit, i)
        return api.C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
    end
    api.C_ClassTalents = {
        GetActiveConfigID = function()
            return ctl.traits and ctl.traits.config
        end,
    }
    api.C_Traits = {
        GetConfigInfo = function()
            return ctl.traits and { treeIDs = ctl.traits.trees }
        end,
        GetTreeNodes = function()
            return ctl.traits and ctl.traits.nodeIDs
        end,
        GetNodeInfo = function(_, node)
            return ctl.traits and ctl.traits.nodes[node]
        end,
        GetEntryInfo = function(_, entry)
            return ctl.traits and { definitionID = entry }
        end,
        GetDefinitionInfo = function(def)
            return ctl.traits and { spellID = ctl.traits.defs[def] }
        end,
    }

    -- The rest of the client the facade resolves (headless loop design §6.2): every passthrough and hybrid row of
    -- ns.Facade.Inventory() but the five absent on Forever, so the client model is this one file. Each answers a plain
    -- constant or a `ctl` field: none is secret on Forever by the facade's probes.
    local function none() end
    local function no()
        return false
    end
    local function zero()
        return 0
    end
    function api.GetBuildInfo()
        return "1.60.1", "70338", "Oct 1 2026", 16001
    end
    function api.GetLocale()
        return "enUS"
    end
    api.GetCVar, api.GetCursorInfo, api.GetActionInfo, api.GetBindingKey = none, none, none, none
    api.GetSpecializationInfoByID, api.GetStablePetInfo = none, none
    function api.GetInventoryItemID(_, slot)
        return ctl.inventory[slot]
    end
    api.UnitPhaseReason, api.UnitThreatSituation, api.UnitTokenFromGUID, api.IsActionInRange = none, none, none, none
    api.HasOverrideActionBar, api.HasVehicleActionBar, api.SpellIsSelfBuff = no, no, no
    api.IsMounted, api.IsResting, api.IsInGroup, api.IsInRaid, api.UnitCanAssist = no, no, no, no, no
    api.UnitIsTrivial, api.UnitIsPVP, api.UnitInVehicle, api.UnitHasVehicleUI, api.UnitOnTaxi = no, no, no, no, no
    api.UnitInParty, api.UnitInRaid = no, none
    api.GetHaste, api.GetFrameCPUUsage, api.GetNumGroupMembers, api.GetNumSubgroupMembers = zero, zero, zero, zero
    function api.GetFramerate()
        return 60
    end
    function api.GetNetStats()
        return 0, 0, 50, 50
    end
    function api.GetRealmName()
        return "Realm"
    end
    function api.GetNumClasses()
        return 11
    end
    function api.GetClassInfo(i)
        if i == ctl.classID then
            return ctl.class, ctl.class, i
        end
    end
    function api.UnitClass()
        return ctl.class, ctl.class, ctl.classID
    end
    function api.UnitRace() -- ctl.race: the race token (the second return), e.g. the harness character's
        return ctl.race or "Race", ctl.race or "Race", 1
    end
    function api.UnitName(u)
        return u == "player" and "Player" or "Unit"
    end
    function api.UnitSex()
        return 2
    end
    function api.UnitFactionGroup()
        return "Horde", "Horde"
    end
    function api.UnitEffectiveLevel(u)
        return api.UnitLevel(u)
    end
    function api.UnitPowerType(unit)
        if unit == "pet" then
            return ctl.petPowerType
        end
        return ctl.powerType[1], ctl.powerType[2]
    end
    function api.UnitAffectingCombat()
        return ctl.combat
    end
    function api.UnitIsPlayer(u)
        return u == "player"
    end
    function api.UnitIsFriend(_, u)
        return u == "player"
    end
    function api.UnitIsDeadOrGhost(u)
        return ctl.dead[u] == true
    end
    function api.UnitClassification()
        return "normal"
    end
    function api.UnitCreatureType(unit)
        local key = ctl.creature[unit] or "beast"
        if key == SECRET then
            return SECRET, SECRET
        end
        local id = CREATURE_IDS[key]
        if id then -- the client's English name and its CreatureType ID
            return (key:gsub("_", " "):gsub("^%l", string.upper)), id
        end
    end
    function api.UnitIsConnected()
        return true
    end
    function api.GetUnitSpeed()
        return 0, 7, 7, 4.72
    end
    function api.IsInInstance()
        return false, "none"
    end
    function api.GetInstanceInfo()
        return "World", "none", 0, "", 5, 0, false, 1
    end
    function api.IsPlayerSpell(id)
        return ctl.known[id] == true
    end
    api.IsSpellKnown, api.IsSpellKnownOrOverridesKnown = api.IsPlayerSpell, api.IsPlayerSpell
    function api.GetManaRegen() -- (not casting, casting): mana's GetPowerRegenForPowerType pair, secret in combat [W PR16]
        return api.GetPowerRegenForPowerType(0)
    end
    function api.SecureCmdOptionParse(s)
        return s
    end
    api.AuraUtil = {
        UnpackAuraData = function(a)
            if not a then
                return nil
            end
            local p = a.points or {}
            return a.name,
                a.icon,
                a.applications,
                a.dispelName,
                a.duration,
                a.expirationTime,
                a.sourceUnit,
                a.isStealable,
                a.nameplateShowPersonal,
                a.spellId,
                a.canApplyAura,
                a.isBossAura,
                a.isFromPlayerOrPlayerPet,
                a.nameplateShowAll,
                a.timeMod,
                p[1],
                p[2],
                p[3]
        end,
    }
    -- C_AddOns.GetAddOnMetadata answers each shipped addon's TOC `## Key: value` lines (State.lua reads Hekili's
    -- Version; Engine/Content.lua a class pack's X-Hekili-ContentAPI), nil for an addon not installed
    local addons = require("helpers.addons") -- run from the repository root
    local toc = {}
    for _, name in ipairs(addons.ADDONS) do
        toc[name] = addons.meta(name)
    end
    assert(toc.Hekili.Version, "src/Hekili/Hekili.toc: no ## Version line")
    api.C_AddOns = {
        GetAddOnMetadata = function(name, k)
            return toc[name] and toc[name][k]
        end,
        IsAddOnLoaded = no,
        LoadAddOn = no,
    }
    local white = { r = 1, g = 1, b = 1 }
    function white.GenerateHexColor()
        return "ffffffff"
    end
    api.C_ClassColor = {
        GetClassColor = function()
            return white
        end,
    }
    api.C_ClassTalents.GetHeroTalentSpecsForClassSpec = none
    api.C_Item = {
        GetItemCount = function(id)
            return ctl.itemCount[id] or 0
        end,
        GetItemSpell = none,
        IsUsableItem = no,
        GetItemInfo = function(id)
            local i = ctl.items[id]
            if i then
                return i[1], nil, nil, nil, nil, nil, nil, nil, i[2]
            end
        end,
        GetItemInfoInstant = none,
        GetItemCooldown = function()
            return 0, 0, 1
        end,
        IsEquippedItem = no,
        IsCurrentItem = no,
        GetDetailedItemLevelInfo = none,
        GetItemGem = none,
        GetWeaponEnchantInfo = function(slot)
            ctl.enchantCalls = ctl.enchantCalls + 1
            return ctl.enchants[slot] or NO_ENCHANTS
        end,
    }
    api.C_LossOfControl = { GetActiveLossOfControlData = none, GetActiveLossOfControlDataCount = zero }
    api.C_PetBattles = { IsInBattle = no }
    api.C_PvP = { IsWarModeDesired = no }
    api.C_PlayerInfo = { IsPlayerInTimerunningHeroicWorldTier = no }
    api.C_SpecializationInfo = {
        GetSpecialization = function()
            return ctl.specID and 1 or nil
        end,
        GetSpecializationInfo = function(i) -- Forever: one pseudo-spec per class (Constants.lua), at index 1
            if i == 1 and ctl.specID then
                return ctl.specID, ctl.class, "", 0, ctl.role, 1
            end
        end,
        GetTalentInfo = none,
    }
    api.C_SpellActivationOverlay = { IsSpellOverlayed = no }
    api.C_Texture = { GetAtlasInfo = none }
    api.C_TooltipInfo = {
        GetInventoryItem = none,
        GetItemByID = none,
        GetSpellByID = function(id)
            return ctl.tooltips[id]
        end,
    }
    local window = { x = 1920, y = 1080 }
    api.C_VideoOptions = {
        GetCurrentGameWindowSize = function()
            return window
        end,
    }
    local C = api.C_Spell
    local info = {} -- [spellID] = GetSpellInfo's table, built once
    function C.GetSpellInfo(id)
        local i = info[id]
        if not i then
            i = {
                name = "Spell " .. tostring(id),
                iconID = 136000,
                spellID = id,
                castTime = 0,
            }
            info[id] = i
        end
        local r = ctl.ranges[id] -- read at each call: a test may set the ranges after the first
        i.minRange, i.maxRange = r and r[1] or 0, r and r[2] or 5
        return i
    end
    function C.GetSpellTexture()
        return 136000
    end
    function C.GetSpellDescription()
        return ""
    end
    C.GetSpellCharges, C.RequestLoadSpellData, C.IsSpellPassive, C.IsSpellHelpful = none, none, no, no
    function C.IsSpellHarmful()
        return true
    end
    function C.IsSpellDataCached()
        return true
    end
    function C.SpellHasRange() -- LibSpellRange's load probe
        return true
    end
    function api.IsUsableSpell(id)
        return C.IsSpellUsable(id)
    end
    local B = api.C_SpellBook
    B.IsSpellInSpellBook = B.IsSpellKnown
    B.FindSpellBookSlotForSpell = none
    B.GetNumSpellBookSkillLines = zero
    B.GetSpellBookItemName = none -- LibSpellRange's fallback probe: an empty book

    -- Frames: each records its registrations; the first one made is the client's view of VirtualState's frame
    -- (`api.frame`): Fire delivers an event to its OnEvent when registered, ctl.Tick runs its OnUpdate.
    function api.CreateFrame()
        local f = { events = {}, units = {}, scripts = {} }
        function f:RegisterEvent(e)
            if ctl.unknownEvents[e] then
                error('Attempt to register unknown event "' .. e .. '"')
            end
            self.events[e] = true
            self.units[e] = nil
            return true
        end
        function f:RegisterUnitEvent(e, u1, u2)
            self.events[e] = true
            self.units[e] = { u1, u2 }
            return true
        end
        function f:UnregisterEvent(e)
            self.events[e], self.units[e] = nil, nil
        end
        function f:SetScript(name, fn)
            self.scripts[name] = fn
        end
        function f:GetScript(name)
            return self.scripts[name]
        end
        function f:Fire(event, ...)
            local fn = self.scripts.OnEvent
            if fn and self.events[event] then
                fn(self, event, ...)
            end
        end
        api.frame = api.frame or f
        return f
    end
    function ctl.Tick(now)
        if now then
            ctl.now = now
        end
        local fn = api.frame and api.frame.scripts.OnUpdate
        if fn then
            fn(api.frame, 0)
        end
    end
    function ctl.Fire(event, ...)
        api.frame:Fire(event, ...)
    end
    return api, ctl
end

return M
