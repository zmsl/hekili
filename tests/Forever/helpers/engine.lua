-- tests/Forever/helpers/engine.lua
-- Loads Hekili's REAL spec engine headless: Engine/Sim/Constants.lua, then every Engine\Schema\ file Hekili.toc
-- lists (Engine/Schema/Races.lua, Engine/Schema/Spec.lua, Engine/Schema/Shared.lua), then every content addon's files
-- in dependency order (tests/helpers/addons.lua: Hekili_Shared's Shared and Races, then the class packs), so each Register* call runs Engine/Schema/Spec.lua's own code (setfenv( f, state ),
-- the `funcs`/__index wrapper, the `item` resolution). Around it,
-- the smallest stub client: a plain ns.Facade, `Item`, `Enum`, a Hekili without Ace3, and STRICT stand-ins for
-- Hekili.Class, Enum.PowerType and `state`: a key they lack raises, so an ability function reading a name State.lua does not provide (a
-- bare `state`, `math`, `error`) fails the caller instead of reading nil.
local vload = require("Game.State.helpers.load")
local addons = require("helpers.addons")

local M = {}

-- A table whose missing keys raise "<what> lacks <key>" at the reader.
local function strict(t, what)
    return setmetatable(t, {
        __index = function(_, k)
            error(("stub %s lacks %q"):format(what, tostring(k)), 2)
        end,
    })
end

-- A table answering `value` for every key (State.lua builds buff.x, talent.x, cooldown.x... on demand).
local function every(value)
    return setmetatable({}, {
        __index = function()
            return value
        end,
    })
end

local function noop() end

-- The files the engine loads after Constants.lua: the core's Engine/Schema/ files, then the content addons'.
function M.files()
    local out = {}
    for _, path in ipairs(addons.files(addons.CORE)) do
        if path:match("/Engine/Schema/") then
            out[#out + 1] = path
        end
    end
    for _, path in ipairs(addons.lua(addons.CONTENT)) do
        out[#out + 1] = path
    end
    return out
end

-- The stand-in `state`: the Lua names State.lua puts on the real one (State.lua:199, 414-497, 520), the tables ability
-- functions read, and no-op verbs; anything else raises (strict) unless the class registered it as a state expression,
-- function or table, which State.lua's mt_state answers the same way.
local function newState(class, race)
    -- an aura, talent, cooldown or action entry: the fields the loaded functions read (strict, like the state)
    local leaf =
        strict({ up = false, down = true, remains = 0, stack = 0, rank = 0, enabled = false, in_range = true }, "leaf")
    local resource = strict({ current = 0, max = 100 }, "resource")
    local s = {
        table = table,
        max = math.max,
        min = math.min,
        abs = math.abs,
        ceil = math.ceil,
        floor = math.floor,
        format = string.format,
        ipairs = ipairs,
        pairs = pairs,
        rawget = rawget,
        rawset = rawset,
        select = select,
        tinsert = table.insert,
        insert = table.insert,
        remove = table.remove,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        unpack = unpack,
        class = class,
        race_token = race,
        timeToInterrupt = noop,
        args = {},
        spec = {},
        settings = {},
        buff = every(leaf),
        debuff = every(leaf),
        talent = every(leaf),
        totem = every(leaf),
        cooldown = every(leaf),
        action = every(leaf),
        active_dot = every(0),
        boss = false,
        history = { casts = {}, units = {} },
        target = strict({ is_boss = false }, "target"),
        health = resource,
        mana = resource,
        rage = resource,
        energy = resource,
        combo_points = resource,
        gcd = strict({ remains = 0 }, "gcd"),
        combat = 0,
        time = 0,
        now = 0,
        offset = 0,
        delay = 0,
        query_time = 0,
        level = 60,
        haste = 1,
        active_enemies = 1,
        display = "Primary",
    }
    for _, verb in ipairs({ "applyBuff", "applyDebuff", "removeBuff", "removeDebuff", "removeStack", "addStack" }) do
        s[verb] = noop
    end
    for _, verb in ipairs({ "spend", "gain", "setCooldown", "setDistance", "interrupt", "summonTotem", "summonPet" }) do
        s[verb] = noop
    end
    return setmetatable(s, {
        __index = function(_, k)
            if class.stateExprs[k] then
                return class.stateExprs[k]()
            end
            local v = class.stateFuncs[k] or class.stateTables[k]
            if v ~= nil then
                return v
            end
            error(("stub state lacks %q"):format(tostring(k)), 2)
        end,
    })
end

--- Loads the engine for a player of class token `classToken` (UnitClassBase) and race token `race` (UnitRace's second
--- return; default "Scourge"). Returns `{ Hekili, ns, state, class, errors, loadErrors, client }`: `errors` the
--- Hekili:Error calls, `loadErrors` one "<file>: <error>" per file whose main chunk raised (the rest still load),
--- `client` the scripted answers (`now` GetTime's, `threat`, `isUnit[unit]`, `exists[unit]`, `canAttack`; `client.SECRET` a secret answer).
function M.load(classToken, race)
    race = race or "Scourge"
    -- Hekili.lua's Class (Hekili.lua:102-130), strict: a misspelt field (class.abilites) raises at the reader
    local class = { specs = {}, num = 0, file = "NONE", initialized = false, range = 8 }
    for _, k in ipairs({
        "resources",
        "resourceAuras",
        "talents",
        "pvptalents",
        "auras",
        "auraList",
        "powers",
        "gear",
        "setBonuses",
        "knownAuraAttributes",
        "stateExprs",
        "stateFuncs",
        "stateTables",
        "abilities",
        "abilityByName",
        "abilityList",
        "itemList",
        "itemMap",
        "packs",
        "retiredPacks",
        "pets",
        "totems",
        "potions",
        "potionList",
        "hooks",
        "settings",
        "stances",
        "toggles",
        "variables",
        "specByShare",
    }) do
        class[k] = {}
    end
    class.itemPack = { lists = { items = {} } }
    class.kit = false
    strict(class, "class")
    local state = newState(class, race)
    local client = { SECRET = {}, isUnit = {}, exists = {} }
    local env = { errors = {}, loadErrors = {}, class = class, state = state, client = client }
    local hekili = { Class = class, State = state }
    function hekili.IsForever()
        return false
    end
    function hekili:Error(...)
        table.insert(env.errors, select("#", ...) > 1 and string.format(...) or (...))
    end
    function hekili:Loadstring(str)
        return loadstring(str)
    end
    function hekili:ContinueOnSpellLoad(_, fn)
        fn(true)
    end
    env.Hekili = hekili
    -- The race registry: every race file's token and the keys it registers (`races`, `raceKeys[token]` = { abilities,
    -- auras }), recorded whether or not the race is live (Engine/Schema/Races.lua registers another race's unknown).
    env.races, env.raceKeys = {}, {}
    setmetatable(hekili, {
        __newindex = function(t, k, v)
            if k == "NewRace" then
                local newRace = v
                v = function(self, token)
                    local keys = { abilities = {}, auras = {} }
                    env.races[#env.races + 1], env.raceKeys[token] = token, keys
                    local race = newRace(self, token)
                    return setmetatable({
                        RegisterAbility = function(_, key, def)
                            table.insert(keys.abilities, key)
                            return race:RegisterAbility(key, def)
                        end,
                        RegisterAura = function(_, key, def)
                            table.insert(keys.auras, key)
                            return race:RegisterAura(key, def)
                        end,
                    }, { __index = race })
                end
            end
            rawset(t, k, v)
        end,
    })

    local ns = vload.module() -- the real VirtualState (KnownRank, I.GCD_SPELL); Facade replaced below
    env.ns = ns
    local function spellInfo(id)
        return { name = "Spell " .. tostring(id), iconID = 0 }
    end
    ns.Facade = {
        C_Item = {
            GetItemCount = function()
                return 0
            end,
            GetItemSpell = noop,
            IsUsableItem = function()
                return true
            end,
        },
        C_Spell = {
            GetSpellInfo = spellInfo,
            GetSpellTexture = function()
                return 0
            end,
            GetSpellDescription = function()
                return ""
            end,
            IsCurrentSpell = function()
                return false
            end,
        },
        C_SpellBook = {},
        C_UnitAuras = { GetDebuffDataByIndex = noop },
        AuraUtil = { UnpackAuraData = noop },
        C_SpecializationInfo = { GetSpecialization = noop, GetSpecializationInfo = noop },
        C_LossOfControl = {
            GetActiveLossOfControlData = noop,
            GetActiveLossOfControlDataCount = function()
                return 0
            end,
        },
        GetNumClasses = function()
            return 0
        end,
        GetTime = function()
            return client.now or 0
        end,
        UnitClassBase = function()
            return classToken
        end,
        UnitClass = function()
            local ids = {
                WARRIOR = 1,
                PALADIN = 2,
                HUNTER = 3,
                ROGUE = 4,
                PRIEST = 5,
                SHAMAN = 7,
                MAGE = 8,
                WARLOCK = 9,
                DRUID = 11,
            }
            return classToken, classToken, ids[classToken]
        end,
        UnitRace = function()
            return "Undead", race
        end,
        GetShapeshiftForm = function()
            return 0
        end,
        GetShapeshiftFormInfo = noop,
        CombatLogGetCurrentEventInfo = noop,
        UnitThreatSituation = function()
            return client.threat
        end,
        UnitIsUnit = function(a, b)
            if b ~= "player" then -- only the "is it us" reads are scripted
                return nil
            end
            return client.isUnit[a]
        end,
        UnitExists = function(u)
            return client.exists[u]
        end,
        UnitCanAttack = function()
            return client.canAttack
        end,
        issecretvalue = function(v)
            return v == client.SECRET
        end,
    }
    ns.commitKey = noop
    ns.metatables = { mt_resource = {} }
    ns.RegisterEvent, ns.RegisterUnitEvent = noop, noop
    hekili.Client = ns.Facade -- the content's one engine name for the client (Hekili.lua)
    -- the belief's reads content calls through `state` (State.lua's names), from the real VirtualState
    local VS = ns.VirtualState
    rawset(state, "knownRank", VS.KnownRank)
    rawset(state, "swingBase", VS.SwingBase)
    rawset(state, "healthMax", VS.HealthMax)
    rawset(state, "stat", VS.Stat)

    local function item(id)
        return {
            IsItemEmpty = function()
                return false
            end,
            ContinueOnItemLoad = function(_, fn)
                fn(true)
            end,
            GetItemName = function()
                return "Item " .. id
            end,
            GetItemLink = function()
                return "[Item " .. id .. "]"
            end,
            GetItemIcon = function()
                return 0
            end,
        }
    end
    local fakes = {
        Hekili = hekili,
        Item = {
            CreateFromItemID = function(_, id)
                return item(id)
            end,
        },
        INVTYPE_WEAPONMAINHAND = "Main Hand", -- Hekili_Shared/Shared/Items.lua's main_hand name (a GlobalStrings constant)
        -- the client's power types, every one Constants.lua's ResourceInfo reads; strict, so a misspelt type raises
        Enum = {
            PowerType = strict({
                HealthCost = -2,
                None = -1,
                Mana = 0,
                Rage = 1,
                Focus = 2,
                Energy = 3,
                ComboPoints = 4,
                Runes = 5,
                RunicPower = 6,
                SoulShards = 7,
                LunarPower = 8,
                HolyPower = 9,
                Alternate = 10,
                Maelstrom = 11,
                Chi = 12,
                Insanity = 13,
                Obsolete = 14,
                Obsolete2 = 15,
                ArcaneCharges = 16,
                Fury = 17,
                Pain = 18,
                Essence = 19,
            }, "Enum.PowerType"),
        },
    }
    local saved = {}
    for k, v in pairs(fakes) do
        saved[k] = rawget(_G, k) or false
        _G[k] = v
    end
    assert(loadfile(vload.ROOT .. "Engine/Sim/Constants.lua"))("Hekili", ns)
    for _, path in ipairs(M.files()) do
        local ok, err = pcall(assert(loadfile(path)), "Hekili", ns)
        if not ok then
            table.insert(env.loadErrors, path .. ": " .. tostring(err))
        end
    end
    for k, v in pairs(saved) do
        _G[k] = v or nil
    end
    return env
end

-- Hekili.Class's abilities and auras after Engine/Schema/Spec.lua's SpecializationChanged merge of loaded `env`: the
-- kit's, then the shared `all` spec's for the keys the kit lacks, then the live race pack's over both (ns.applyRace).
local function merged(env)
    local class = env.class
    local t = { abilities = {}, auras = {} }
    for _, spec in ipairs({ assert(class.kit, "no class pack loaded"), class.specs[0] }) do
        for kind, out in pairs(t) do
            for k, v in pairs(spec[kind]) do
                if out[k] == nil then
                    out[k] = v
                end
            end
        end
    end
    env.ns.applyRace(t)
    return t
end

--- The character's ability set for class token `classToken`: the abilities and auras the engine itself holds for it
--- (Hekili.Class after SpecializationChanged: the class kit's, the shared content's (Hekili_Shared: consumables,
--- items, auras) and the engine's own, a race pack's over both), each its registered object (gcd, cooldown, cast,
--- known and the rest as registered). `race`: one race token (UnitRace's second return), that race's racials; nil:
--- every race the registry holds (a pack's priority serves every race). Returns { abilities, auras (keyed like
--- Hekili.Class's: keys, names, IDs), talents (the kit's), racial = { [key] = race token } }.
function M.abilitySet(classToken, race)
    local base = M.load(classToken, race or "")
    local set = merged(base)
    set.talents, set.racial = base.class.kit.talents, {}
    for _, r in ipairs(race and { race } or base.races) do
        local env = race and base or M.load(classToken, r)
        local t = merged(env)
        for kind, keys in pairs(env.raceKeys[r] or {}) do
            for _, key in ipairs(keys) do
                local v = t[kind][key]
                for k, w in pairs(t[kind]) do -- the key and its aliases (Races.lua's own())
                    if w == v then
                        set[kind][k] = w
                    end
                end
                if kind == "abilities" then
                    assert(
                        not set.racial[key],
                        ("races %s and %s both register %s"):format(tostring(set.racial[key]), r, key)
                    )
                    set.racial[key] = r
                end
            end
        end
    end
    return set
end

return M
