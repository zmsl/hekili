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

-- The client refuses a secret as a table key; Lua 5.1 does not (a proxy is a valid key). `strictKeys(t)` gives `t`
-- the client's two errors: a secret key is never stored, so every secret read or write reaches the metamethods.
-- `t` must have no metatable. Returns `t`.
function M.strictKeys(t)
    assert(getmetatable(t) == nil, "strictKeys: the table already has a metatable")
    return setmetatable(t, {
        __index = function(_, k)
            if k == SECRET then
                error("attempted to index a table that cannot be indexed with secret keys", 2)
            end
        end,
        __newindex = function(tt, k, v)
            if k == SECRET then
                error("attempted to perform indexed assignment on a table that cannot be indexed with secret keys", 2)
            end
            rawset(tt, k, v)
        end,
    })
end

-- The secrets `t` holds as a key or a value (the illegal stores a truth test can't trap): 0 for a clean table.
function M.secretsIn(t)
    local n = 0
    for k, v in pairs(t) do
        if k == SECRET or v == SECRET then
            n = n + 1
        end
    end
    return n
end
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
-- The Cooldown Manager's four viewer frames (providers spec §4.2; CV research §2), in category order 0-3.
M.VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

-- LibRangeCheck-3.0 run against the fake client (range plan R2, round 2): the vendored files, and what the library
-- reads at load that the client leaves to the headless loader (WoW's Lua aliases, C_Timer, Enum).
M.LIBSTUB = "src/Hekili/Libs/LibStub/LibStub.lua"
M.LIBRANGECHECK = "src/Hekili/Libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua"
M.LIB_SHIMS = {
    tinsert = table.insert,
    tremove = table.remove,
    sort = table.sort,
    wipe = function(t)
        for k in pairs(t) do
            t[k] = nil
        end
        return t
    end,
    C_Timer = {
        NewTicker = function()
            return {}
        end,
    },
    Enum = {
        SpellBookSpellBank = { Player = 0, Pet = 1 },
        SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
    },
    GetInventorySlotInfo = function()
        return 10 -- HANDSSLOT
    end,
}

--- The knobs on the library's GetRange (the headless instance's vendored copy, or api.LibStub's): `ctl.rangeLib`
--- "raise" raises, "none" answers nothing; `ctl.rangeLibCalls` counts the calls. A secret distance answers secret: in
--- game a secret check raises inside the library, a truth test Lua 5.1 cannot trap. Each call first runs the
--- library's init (a no-op once built): its frame does that after load and after each spell change, which no fake
--- runs.
function M.wrapRangeLib(lib, ctl)
    local real = lib.GetRange
    function lib.GetRange(self, unit, ...)
        ctl.rangeLibCalls = ctl.rangeLibCalls + 1
        if ctl.rangeLib == "raise" then
            error("LibRangeCheck-3.0: a secret range answer tested")
        elseif ctl.rangeLib == "none" then
            return nil
        elseif ctl.distance[unit] == SECRET then
            return SECRET, SECRET
        end
        self:init()
        return real(self, unit, ...)
    end
    lib.getRange = lib.GetRange
    return real
end

--- A new fake client and its control table.
function M.new()
    local ctl = {
        now = 100,
        combat = false,
        class = "CLASS_A",
        power = {}, -- [powerType] = value (SECRET for a secret read)
        -- [target token] = GetComboPoints("player", token): the points usable on that unit (SECRET: a secret answer;
        -- false: nil, no unit); unset: the pool, UnitPower("player", 4), as in a single-target world
        comboPoints = {},
        petPower = 0, -- UnitPower("pet") of the pet's power type `petPowerType` while exists.pet (SECRET: a secret read)
        petPowerType = 0,
        itemCount = {}, -- [itemID] = C_Item.GetItemCount (default 0)
        -- [index] = UnitStat's value (its first two returns; default 0); .armor UnitArmor's, .block GetShieldBlock's
        stats = {},
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
        -- [spellID] = { min, max[, reach] } yards: GetSpellInfo's minRange/maxRange (default 0, 5). maxRange 0 is a
        -- spell the client checks no range for (IsSpellInRange nil: self-centred), unless `reach` is set: the live
        -- client's melee strike reads maxRange 0 and still answers IsSpellInRange against `reach` (5)
        ranges = {},
        handlers = {},
        unitSpeed = {}, -- [unit] = speed for UnitAttackSpeed of a unit other than the player (default: secret)
        unitIs = {}, -- [unit] = the token UnitIsUnit(unit, x) is true for (SECRET: a secret answer)
        names = {}, -- [unit] = UnitName (default "Player" for the player, else "Unit"; SECRET: a secret answer)
        friendly = {}, -- [unit] = true: UnitCanAttack("player", unit) false, UnitIsFriend true (default: hostile)
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
        -- LibRangeCheck-3.0 is the vendored library itself, run against this client (M.wrapRangeLib): "none" answers
        -- nothing, "raise" raises; rangeLibCalls counts GetRange calls
        rangeLib = nil,
        rangeLibCalls = 0,
        -- [itemID] = yards: the items the client has cached, which the library's item checkers use (C_Item); the
        -- library's first Era/Forever HarmItems per range (its file, `HarmItems` under isEra or isForever).
        rangeItems = {
            [8149] = 5,
            [9606] = 10,
            [4559] = 15,
            [1191] = 20,
            [13289] = 25,
            [835] = 30,
            [1258] = 35,
            [4945] = 40,
            [221316] = 45,
            [5418] = 100,
        },
    }
    local api = { ctl = ctl }

    -- The vendored LibStub and LibRangeCheck-3.0 loaded once, on first ask, into an environment over this client (a
    -- headless instance has its own, loaded with the TOC, and never asks here).
    local libs
    function api.LibStub(name, silent)
        if not libs then
            local env = setmetatable({}, {
                __index = function(_, k)
                    local v = api[k]
                    if v == nil then
                        v = M.LIB_SHIMS[k]
                    end
                    if v == nil then
                        v = _G[k]
                    end
                    return v
                end,
            })
            env._G, env.LibStub = env, false -- LibStub.lua makes its own
            for _, path in ipairs({ M.LIBSTUB, M.LIBRANGECHECK }) do
                setfenv(assert(loadfile(path)), env)()
            end
            libs = env.LibStub
            M.wrapRangeLib(libs("LibRangeCheck-3.0"), ctl)
        end
        return libs(name, silent)
    end

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
        if ctl.friendly[unit] == SECRET then
            return SECRET
        end
        return ctl.friendly[unit] ~= true
    end
    -- LibRangeCheck's interact checkers: within the index's yards (the library's own table: 3 Duel 8, 4 Follow 28) of
    -- `distance`; a secret distance answers secret; no distance: in reach when in range (`inRange`)
    local INTERACT = { 28, 9, 8, 28, 7 }
    function api.CheckInteractDistance(unit, index)
        local d = ctl.distance[unit]
        if d == SECRET then
            return SECRET
        elseif d == nil then
            return ctl.inRange[unit] == true
        end
        return d <= (INTERACT[index] or 0)
    end
    function api.GetInventoryItemLink() end -- the library's hand-slot probe (gloves that change spell ranges): none
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
    function api.GetComboPoints(_, target)
        local v = ctl.comboPoints[target]
        if v == nil then
            return api.UnitPower("player", 4)
        elseif v == false then
            return nil
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
    api.GetMasteryEffect, api.GetCritChance = zeros, zeros
    function api.UnitArmor() -- base, effective, armor, positive, negative buffs: ctl.stats.armor (default 0)
        local a = ctl.stats.armor or 0
        return a, a, a, 0, 0
    end
    function api.UnitDamage()
        local d = ctl.damage
        return d[1], d[2], d[3], d[4], 0, 0, 1
    end
    function api.GetShieldBlock() -- ctl.stats.block (default 0)
        return ctl.stats.block or 0
    end
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
            local r = ctl.ranges[id]
            local lo, hi = r and r[1] or 0, r and (r[3] or r[2]) or 5
            if d == SECRET then
                return SECRET
            elseif d == nil then -- no position: in reach when in range, at 0 yd (the world's `distance or 0`): inside a minimum
                return ctl.inRange[unit] == true and lo <= 0
            end
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
    ctl.cvars = { cooldownViewerEnabled = "1" } -- GetCVar's answers (the game options' Cooldown Manager on)
    function api.GetCVar(name)
        return ctl.cvars[name]
    end
    api.GetCursorInfo, api.GetActionInfo, api.GetBindingKey = none, none, none
    api.GetMacroSpell, api.GetMacroItem = none, none
    api.GetSpecializationInfoByID, api.GetStablePetInfo = none, none
    function api.GetInventoryItemID(_, slot)
        return ctl.inventory[slot]
    end
    api.UnitPhaseReason, api.UnitThreatSituation, api.UnitTokenFromGUID, api.IsActionInRange = none, none, none, none
    api.HasOverrideActionBar, api.HasVehicleActionBar, api.SpellIsSelfBuff = no, no, no
    api.IsMounted, api.IsResting, api.IsInRaid, api.UnitCanAssist = no, no, no, no
    function api.IsInGroup() -- `ctl.inGroup` (the meter provider reads it at PLAYER_REGEN_DISABLED)
        return ctl.inGroup == true
    end
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
    function api.UnitName(u) -- ctl.names[u] when set (SECRET: a secret answer)
        local n = ctl.names[u]
        if n ~= nil then
            return n
        end
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
    function api.UnitIsFriend(_, u) -- ctl.friendly: the friendly units (SECRET: a secret answer)
        if ctl.friendly[u] == SECRET then
            return SECRET
        end
        return u == "player" or ctl.friendly[u] == true
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
            elseif ctl.rangeItems[id] then -- a cached range item (LibRangeCheck's selection)
                return "Item"
            end
        end,
        -- LibRangeCheck's item checkers: the cached range items (`rangeItems`), each within its yards of `distance`
        IsItemDataCachedByID = function(id)
            return ctl.rangeItems[id] ~= nil
        end,
        DoesItemExistByID = function(id)
            return ctl.rangeItems[id] ~= nil or ctl.items[id] ~= nil
        end,
        IsItemInRange = function(id, unit)
            local r, d = ctl.rangeItems[id], ctl.distance[unit]
            if d == SECRET then
                return SECRET
            elseif r == nil then
                return nil
            elseif d == nil then
                return ctl.inRange[unit] == true
            end
            return d <= r
        end,
        GetItemInfoInstant = function(id)
            local i = ctl.items[id]
            if i then
                return id, nil, nil, i[2]
            end
        end,
        GetItemCooldown = function()
            return 0, 0, 1
        end,
        IsEquippedItem = function(id) -- any slot holds it (ctl.inventory); no item cache needed
            for _, v in pairs(ctl.inventory) do
                if v == id then
                    return true
                end
            end
            return false
        end,
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
    -- the gamepad action bars: no storage slots on this client, so Hekili's gamepad keybind reader is a no-op
    api.C_ActionBar = { HasBonusActionBar = no }
    api.C_GamepadUI = {
        GetFirstGamepadActionStorageSlotIndex = none,
        GetFirstGamepadActionBarStorageSlotIndexForActiveStance = none,
    }
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
    -- The damage meter (providers spec §4.2; DM research): our session's totals, plain out of combat, every number
    -- secret in combat. `ctl.meter.done[1]` / `taken[1]`: our damage done (type 0) and taken (type 7).
    ctl.meter = { available = true, done = {}, taken = {} }
    local dmSecret = { combatSources = { { isLocalPlayer = true, totalAmount = SECRET } } }
    local dmDone = { combatSources = { { isLocalPlayer = true, totalAmount = 0 } } }
    local dmTaken = { combatSources = { { isLocalPlayer = true, totalAmount = 0 } } }
    local dmNone = { combatSources = {} }
    api.C_DamageMeter = {
        IsDamageMeterAvailable = function()
            return ctl.meter.available
        end,
        GetCombatSessionFromType = function(_, ty)
            if ty ~= 0 and ty ~= 7 then
                return dmNone
            elseif ctl.combat then
                return dmSecret
            end
            local r = ty == 0 and dmDone or dmTaken
            r.combatSources[1].totalAmount = (ty == 0 and ctl.meter.done or ctl.meter.taken)[1] or 0
            return r
        end,
    }
    -- The Cooldown Manager (providers spec §4.2; CV research §2): `sets[category]` its cooldown IDs, `infos[id]` their
    -- info ({ spellID, ... }), `items[viewer]` each viewer frame's children (ctl.ViewerItem); ctl.ViewerShow(item, up)
    -- is the client's show or hide 3-4 ms after the aura edge: auraInstanceID secret or nil, then the item's hooks. A
    -- shown item reads its `auraDataUnit` (set by the caller, else the item's `unit`); a hidden one reads no unit
    -- either (CDV_FRAME 5609).
    ctl.viewer = {
        available = true,
        sets = { [0] = {}, [1] = {}, [2] = {}, [3] = {} },
        unlearned = { [0] = {}, [1] = {}, [2] = {}, [3] = {} }, -- added by GetCooldownViewerCategorySet(c, true)
        infos = {},
        items = {}, -- [viewer name] = its children in order (items, unconfigured items, non-item children)
        shown = {}, -- [viewer name] = false: that viewer is not visible (nil: visible)
        parentShown = true, -- false: no viewer is visible (their parent is hidden)
        plainSpell = false, -- an applied item's auraSpellID is plain (out of combat, probed) instead of SECRET
        lag = false, -- ViewerAuraBySpell lights its items at the NEXT ctl.Tick, not in the same call
        log = true, -- items record their writes (the order tests); the loops turn it off (bounded memory, L279)
        applied = {}, -- the auras up on us: { unit, spellID }, for an item acquired while one is still running
        pending = {}, -- the lagged lights: { item, unit, up }
        hookCalls = {}, -- every HookScript / hooksecurefunc call (the leaf is asserted to make none)
        reshuffle = false, -- true: ViewerRetarget also reshuffles every viewer's frames (ViewerReshuffle)
        reshuffleN = 0, -- the counter ViewerRetarget passes ViewerReshuffle (the caller may seed it per fight)
        reshuffleDark = false, -- true: a reshuffle is not atomic: a moved lit item reads dark until the next flush
    }
    ctl.overrides = {} -- [spellID] = C_Spell.GetOverrideSpell's answer (default: the ID itself)
    api.C_CooldownViewer = {
        IsCooldownViewerAvailable = function()
            return ctl.viewer.available, ctl.viewer.failureReason -- (isAvailable, failureReason)
        end,
        GetCooldownViewerCategorySet = function(category, allowUnlearned)
            local set = ctl.viewer.sets[category]
            if not allowUnlearned then
                return set
            end
            local r = {}
            for _, id in ipairs(set) do
                r[#r + 1] = id
            end
            for _, id in ipairs(ctl.viewer.unlearned[category]) do
                r[#r + 1] = id
            end
            return r
        end,
        GetCooldownViewerCooldownInfo = function(id)
            return ctl.viewer.infos[id]
        end,
    }
    for _, name in ipairs(M.VIEWERS) do
        ctl.viewer.items[name] = {}
        api[name] = {
            IsVisible = function()
                return ctl.viewer.parentShown ~= false and ctl.viewer.shown[name] ~= false
            end,
            GetChildren = function()
                return unpack(ctl.viewer.items[name])
            end,
            GetNumChildren = function()
                return #ctl.viewer.items[name]
            end,
            GetItemFrames = function() -- the item children only (a non-item child is not an item frame)
                local r = {}
                for _, c in ipairs(ctl.viewer.items[name]) do
                    if c.isItem then
                        r[#r + 1] = c
                    end
                end
                return r
            end,
        }
    end
    function api.hooksecurefunc(...)
        local h = ctl.viewer.hookCalls
        h[#h + 1] = { ... }
    end
    local NO_HOOKS = {}
    local function hookScript(item, script, fn)
        local c = ctl.viewer.hookCalls
        c[#c + 1] = { item, script }
        local h = item.hooks[script] or {}
        item.hooks[script] = h
        h[#h + 1] = fn
    end
    local function write(item, what) -- the client's write order, recorded for the order tests
        if ctl.viewer.log then
            item.writes[#item.writes + 1] = what
        end
    end
    --- A child of viewer `name` tracking cooldown `id` at `layoutIndex` (`id` nil: an unconfigured slot), hidden.
    function ctl.ViewerItem(name, layoutIndex, id)
        local list = ctl.viewer.items[name]
        local item = {
            isItem = true,
            layoutIndex = layoutIndex,
            cooldownID = id,
            hooks = {},
            writes = {},
            HookScript = hookScript,
        }
        list[#list + 1] = item
        return item
    end
    --- A non-item child (no cooldownID, no layoutIndex).
    function ctl.ViewerChild(name)
        local list = ctl.viewer.items[name]
        local child = {}
        list[#list + 1] = child
        return child
    end
    local function clearAura(item)
        item.auraInstanceID, item.auraSpellID, item.auraDataUnit, item.litBy, item.litUnit = nil, nil, nil, nil, nil
        item.shown = false
        write(item, "clear")
    end
    --- The client's set (BD:368-392): a held aura is cleared first, then the new one set.
    function ctl.ViewerAura(item, unit, spellID)
        if item.auraInstanceID ~= nil then
            clearAura(item)
        end
        item.auraInstanceID, item.auraDataUnit, item.litBy, item.litUnit = SECRET, unit, spellID, unit
        if item.noUnit then -- a STRESS flag, not a client state (BD:368-379 always records the unit): held with
            -- auraDataUnit nil, the shape of a secret or unread unit, which the leaf must never count as live (§2.2a)
            item.auraDataUnit = nil
        end
        item.auraSpellID = ctl.viewer.plainSpell and spellID or SECRET
        item.shown = true
        write(item, "set")
    end
    function ctl.ViewerClear(item)
        clearAura(item)
    end
    --- Release (BD:95-98): the cooldownID first, then the aura clear, then the layoutIndex.
    function ctl.ViewerRelease(item)
        item.cooldownID = nil
        write(item, "cooldownID")
        clearAura(item)
        item.layoutIndex = nil
        write(item, "layoutIndex")
    end
    --- Does `info` name `spellID`? As the client does (FindLinkedSpellForCurrentAuras): an info with linkedSpellIDs
    --- matches ONLY those (its base spell stays dark, F4); otherwise spellID, overrideSpellID and overrideTooltipSpellID,
    --- each also through GetOverrideSpell.
    local function names(info, spellID)
        local links = info.linkedSpellIDs
        if links and links[1] ~= nil then
            for _, l in ipairs(links) do
                if l == spellID then
                    return true
                end
            end
            return false
        end
        local a, b, c = info.spellID, info.overrideSpellID, info.overrideTooltipSpellID -- (no ipairs: nil gaps)
        return a == spellID
            or b == spellID
            or c == spellID
            or (a ~= nil and ctl.overrides[a] == spellID)
            or (b ~= nil and ctl.overrides[b] == spellID)
            or (c ~= nil and ctl.overrides[c] == spellID)
    end
    local REFRESH_UNITS = { "player", "target" }
    --- Re-point (BV:137-147): the cooldownID, then the refresh (a held aura clears, then sets again).
    function ctl.ViewerRepoint(item, id)
        item.cooldownID = id
        write(item, "cooldownID")
        if item.auraInstanceID ~= nil then
            local info = ctl.viewer.infos[id]
            if item.litBy and info and not names(info, item.litBy) then
                clearAura(item) -- the new cooldownID does not name the aura it held: the refresh finds none
            else
                ctl.ViewerAura(item, item.auraDataUnit, item.litBy)
            end
        end
        local info = ctl.viewer.infos[id]
        if item.auraInstanceID == nil and info and not item.silent then -- the refresh finds an aura of the new entry,
            -- the player's before the target's (the client's scan order; CooldownViewerItemData.lua:16-79)
            for _, unit in ipairs(REFRESH_UNITS) do
                for _, a in ipairs(ctl.viewer.applied) do
                    if
                        item.auraInstanceID == nil
                        and a[1] == unit
                        and (item.unit == nil or item.unit == unit)
                        and names(info, a[2])
                    then
                        if ctl.viewer.lag then
                            local p = ctl.viewer.pending
                            p[#p + 1] = { item, a[1], true, a[2] }
                        else
                            ctl.ViewerAura(item, a[1], a[2])
                        end
                    end
                end
            end
        end
    end
    local function light(item, unit, up, spellID)
        if up then
            ctl.ViewerAura(item, unit, spellID)
        elseif item.auraInstanceID ~= nil then
            clearAura(item)
        end
    end
    --- An aura of `spellID` goes up or down on `unit`: every configured, non-`silent` item in any viewer whose info
    --- names the spell lights (an info listing another rank stays silent). Only our own auras ("player") light items.
    --- With ctl.viewer.lag the lights land at the next ctl.Tick instead.
    function ctl.ViewerAuraBySpell(unit, spellID, up, source)
        if source ~= "player" then
            return
        end
        local ap = ctl.viewer.applied
        for i = #ap, 1, -1 do
            if ap[i][1] == unit and ap[i][2] == spellID then
                table.remove(ap, i)
            end
        end
        if up then
            ap[#ap + 1] = { unit, spellID }
        end
        for _, name in ipairs(M.VIEWERS) do
            for _, item in ipairs(ctl.viewer.items[name]) do
                local info = item.cooldownID and ctl.viewer.infos[item.cooldownID]
                if info and not item.silent and (item.unit == nil or item.unit == unit) and names(info, spellID) then
                    if ctl.viewer.lag and up then -- removal stays immediate
                        local p = ctl.viewer.pending
                        p[#p + 1] = { item, unit, up, spellID }
                    else
                        light(item, unit, up, spellID)
                    end
                end
            end
        end
    end
    --- The pool grows (also in combat): a NEW frame table each time (an item can come back as a different frame for the
    --- same cooldownID), at the next layout index. An aura of its spell still up lights it at once (F13) unless `silent`
    --- (3rd argument) or ctl.viewer.lag (then at the next Tick). `frame`: a released child of `name` comes back from
    --- the pool instead (the same table, no new child).
    function ctl.ViewerAcquire(name, id, silent, frame)
        local top = 0 -- max + 1: a removal must not make a live index repeat
        for _, c in ipairs(ctl.viewer.items[name]) do
            top = math.max(top, c.layoutIndex or 0)
        end
        local item = frame
        if item then
            item.cooldownID, item.layoutIndex = id, top + 1
        else
            item = ctl.ViewerItem(name, top + 1, id)
        end
        item.silent = silent or nil
        local info = ctl.viewer.infos[id]
        for _, a in ipairs(ctl.viewer.applied) do
            if info and not silent and (item.unit == nil or item.unit == a[1]) and names(info, a[2]) then
                if ctl.viewer.lag then
                    local p = ctl.viewer.pending
                    p[#p + 1] = { item, a[1], true, a[2] }
                else
                    light(item, a[1], true, a[2])
                end
            end
        end
        return item
    end
    --- The item leaves the pool: released, and its frame drops out of the viewer's children and GetItemFrames.
    function ctl.ViewerRemove(name, item)
        ctl.ViewerRelease(item)
        local list = ctl.viewer.items[name]
        for i, c in ipairs(list) do
            if c == item then
                table.remove(list, i)
                return
            end
        end
    end
    local function flushLag()
        local p = ctl.viewer.pending
        ctl.viewer.pending = {}
        for _, e in ipairs(p) do
            local up = false -- an apply and its removal inside one poll: nothing to light (a held refresh stays lit)
            for _, a in ipairs(ctl.viewer.applied) do
                if a[1] == e[2] and a[2] == e[4] then
                    up = true
                end
            end
            if e[1].cooldownID ~= nil and up then
                light(e[1], e[2], e[3], e[4])
            end
        end
    end
    ctl.ViewerFlush = flushLag -- the loop harness never calls ctl.Tick: its cycle calls this
    local FRAME_OWN = { isItem = true, hooks = true, writes = true, HookScript = true } -- the rest is the item's
    --- The full UNIT_AURA update's release and re-acquire (verdict spec §1, §2.4): in each viewer the configured items
    --- move to other frames, a rotation by 1 + n % (count - 1) (deterministic from the caller's counter `n`, never
    --- the identity). An item carries everything but the frame itself: its cooldownID, layoutIndex, flags and aura
    --- state (a lit item stays lit on its new frame, as the client's refresh re-lights it); a pending light follows it.
    --- With ctl.viewer.reshuffleDark a moved lit item clears on its new frame and re-lights at the next flush (the
    --- verdict's settle under a non-atomic re-point; still applied then, else it stays dark).
    function ctl.ViewerReshuffle(n)
        local moved, order = {}, {} -- old frame -> new frame; the new frames in viewer order
        for _, name in ipairs(M.VIEWERS) do
            local frames, items = {}, {}
            for _, f in ipairs(ctl.viewer.items[name]) do
                if f.isItem and f.cooldownID ~= nil then
                    local b = {}
                    for k, v in pairs(f) do
                        if not FRAME_OWN[k] then
                            b[k] = v
                        end
                    end
                    for k in pairs(b) do
                        f[k] = nil
                    end
                    frames[#frames + 1], items[#items + 1] = f, b
                end
            end
            local c = #frames
            local r = c > 1 and 1 + n % (c - 1) or 0
            for i, f in ipairs(frames) do
                local from = frames[(i - 1 + r) % c + 1]
                for k, v in pairs(items[(i - 1 + r) % c + 1]) do
                    f[k] = v
                end
                moved[from], order[#order + 1] = f, f
                write(f, "reshuffle")
            end
        end
        for _, p in ipairs(ctl.viewer.pending) do
            p[1] = moved[p[1]] or p[1]
        end
        if ctl.viewer.reshuffleDark then
            local p = ctl.viewer.pending
            for _, f in ipairs(order) do
                if f.auraInstanceID ~= nil then
                    local unit, spellID = f.litUnit, f.litBy
                    clearAura(f)
                    p[#p + 1] = { f, unit, true, spellID }
                end
            end
        end
    end
    --- Our target changed (the client re-reads its target items): every item held for the target clears (a noUnit one
    --- by the unit it was lit for), the target's applied auras and pending lights go; the caller lights the new target's.
    --- With ctl.viewer.reshuffle the full update also re-points every frame in all four viewers (ViewerReshuffle).
    function ctl.ViewerRetarget()
        for _, name in ipairs(M.VIEWERS) do
            for _, item in ipairs(ctl.viewer.items[name]) do
                if item.isItem and item.auraInstanceID ~= nil and item.litUnit == "target" then
                    clearAura(item)
                end
            end
        end
        for _, list in ipairs({ ctl.viewer.applied, ctl.viewer.pending }) do
            local u = list == ctl.viewer.applied and 1 or 2
            for i = #list, 1, -1 do
                if list[i][u] == "target" then
                    table.remove(list, i)
                end
            end
        end
        if ctl.viewer.reshuffle then
            ctl.viewer.reshuffleN = ctl.viewer.reshuffleN + 1
            ctl.ViewerReshuffle(ctl.viewer.reshuffleN)
        end
    end
    --- A fresh fight (the loops): every item's aura cleared, no aura applied, no light pending; the frames stay.
    function ctl.ViewerReset()
        for _, name in ipairs(M.VIEWERS) do
            for _, item in ipairs(ctl.viewer.items[name]) do
                if item.isItem and item.auraInstanceID ~= nil then
                    clearAura(item)
                end
            end
        end
        ctl.viewer.applied, ctl.viewer.pending = {}, {}
    end
    function ctl.ViewerShow(item, up)
        item.shown = up
        if up then
            item.auraInstanceID, item.auraDataUnit = SECRET, item.auraDataUnit or item.unit
        else
            item.auraInstanceID, item.auraDataUnit = nil, nil
        end
        for _, fn in ipairs(item.hooks[up and "OnShow" or "OnHide"] or NO_HOOKS) do
            fn(item)
        end
    end
    local C = api.C_Spell
    function C.GetOverrideSpell(id)
        return ctl.overrides[id] or id
    end
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
    C.GetSpellCooldownDuration = none -- MayReturnNothing: the fake client has no duration objects (display class)
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
    -- The spellbook as LibRangeCheck scans it (its findSpellIdx): one skill line holding every known spell, by ID
    -- order, built at the skill line's read (the library's init only; allocates there)
    local book, LINE, ITEM = {}, { itemIndexOffset = 0, numSpellBookItems = 0 }, { itemType = 1, spellID = 0 }
    function B.GetNumSpellBookSkillLines()
        return 1
    end
    function B.GetSpellBookSkillLineInfo(i)
        if i ~= 1 then
            return nil
        end
        for k = #book, 1, -1 do
            book[k] = nil
        end
        for id, on in pairs(ctl.known) do
            if on == true then
                book[#book + 1] = id
            end
        end
        table.sort(book)
        LINE.numSpellBookItems = #book
        return LINE
    end
    function B.GetSpellBookItemName(i)
        return book[i] and C.GetSpellInfo(book[i]).name
    end
    function B.GetSpellBookItemInfo(i)
        if book[i] then
            ITEM.spellID = book[i]
            return ITEM
        end
    end

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
        function f:IsEventRegistered(e)
            return self.events[e] == true
        end
        function f:Show() -- LibRangeCheck shows its frame to schedule an init (wrapRangeLib runs it instead)
            self.shown = true
        end
        function f:Hide()
            self.shown = false
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
        if ctl.viewer.pending[1] then
            flushLag()
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
