-- tests/Virtual/State/helpers/fake_api.lua
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

--- A new fake client and its control table.
function M.new()
    local ctl = {
        now = 100,
        combat = false,
        class = "WARRIOR",
        power = {}, -- [powerType] = value (SECRET for a secret read)
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
        totems = {},
        traits = nil, -- { config = id, trees = { tree }, nodes = { [node] = info }, entries = {}, defs = {} }
        inRange = {},
        handlers = {},
        unitSpeed = {}, -- [unit] = speed for UnitAttackSpeed of a unit other than the player (default: secret)
        unitIs = {}, -- [unit] = the token UnitIsUnit(unit, x) is true for (SECRET: a secret answer)
        unknownEvents = {}, -- [event] = true: RegisterEvent raises, as the client does for an event it does not know
        form = 0, -- GetShapeshiftForm (0: none)
        forms = {}, -- [form index] = its spell ID (GetShapeshiftFormInfo's 4th return)
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
        return ctl.exists[unit] == true
    end
    function api.UnitIsDead(unit)
        return ctl.dead[unit] == true
    end
    function api.UnitCanAttack()
        return true
    end
    function api.UnitPower(_, pt)
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
    function api.UnitHealth()
        return ctl.health
    end
    function api.UnitHealthMax()
        return ctl.healthMax
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
    function api.UnitIsUnit(a, b)
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
    api.UnitStat, api.GetSpellBonusDamage, api.UnitAttackPower, api.UnitWeaponAttackPower = zeros, zeros, zeros, zeros
    api.UnitDamage, api.UnitArmor, api.GetMasteryEffect, api.GetCritChance = zeros, zeros, zeros, zeros
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
            return ctl.inRange[unit] == true
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
