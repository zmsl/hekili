-- Engine/Schema/Races.lua
-- Race packs (event-facade spec §12b). `Hekili:NewRace( token, raceID )` returns a registration object a race file
-- (Hekili_Shared/Races/<Race>.lua) uses like a spec: RegisterAbility, RegisterAura, RegisterResourceMod, RegisterCostMod,
-- RegisterRegenMod
-- (a class file declares its own cost modifiers with spec:RegisterCostMod, into the same list).
-- Registrations count only when the token is the player's race (`state.race_token`, UnitRace's locale-free second
-- return, or the race ID, its third, for a race whose token is unconfirmed), so every race file runs unconditionally
-- and loads headless. Another race's abilities and auras still go to `all` (under a key `all` lacks), the abilities
-- `known = false` and unlisted: a priority naming any race's racial reads `action.<racial>.known` false instead of
-- indexing nothing; its modifiers stay inert.
-- Abilities and auras go to the shared `all` spec (over `all`'s own entry for the same key), and ns.applyRace writes
-- them over the class's after Engine/Schema/Spec/Activation.lua's merge (which takes the class first and only adds missing keys), so a race
-- registration wins a key clash with the class and with `all`. Resource and cost modifiers go to `ns.raceMods`, one
-- declaration read by two layers:
-- VirtualState's belief (Game/State/Families/Modifiers.lua, through Tracked.lua) and Hekili's simulation (below).

local addon, ns = ...
local Hekili = _G[addon]

local mods = { maxMods = {}, costMods = {}, regenMods = {}, gcdMods = {} }
ns.raceMods = mods
Hekili.RaceMods = mods -- read in game at CHECKPOINT B (ns is not global)

local function all()
    return Hekili.Class.specs[0]
end

-- The keys (and `copy` aliases) the live race registered, by kind: what ns.applyRace writes over the class's.
local owned = { abilities = {}, auras = {} }

-- Records every key of `all`'s `kind` table that holds the entry just registered under `key` (its aliases too).
local function own(kind, key)
    local t = all()[kind]
    local v = t[key]
    for k, w in pairs(t) do
        if w == v then
            owned[kind][k] = true
        end
    end
end

--- Engine/Schema/Spec/Activation.lua's SpecializationChanged, after merging the specs: the race's abilities and auras win over the class's.
function ns.applyRace(class)
    local spec = all()
    for kind, keys in pairs(owned) do
        for k in pairs(keys) do
            class[kind][k] = spec[kind][k]
        end
    end
end

local Race = {}
Race.__index = Race

function Race:RegisterAbility(key, def)
    if self.live then
        all():RegisterAbility(key, def)
        own("abilities", key)
    elseif not all().abilities[key] then
        def.known, def.unlisted = false, true
        all():RegisterAbility(key, def)
    end
end

function Race:RegisterAura(key, def)
    if self.live then
        all():RegisterAura(key, def)
        own("auras", key)
    elseif not all().auras[key] then
        all():RegisterAura(key, def)
    end
end

--- { max = pct }: every resource the loaded class registered gets pct more maximum.
function Race:RegisterResourceMod(def)
    if self.live and type(def.max) == "number" then
        mods.maxMods[#mods.maxMods + 1] = { pct = def.max }
    end
end

--- { aura = key, pct = n | flat = n, charges = k | nil, spells = { spell IDs } | nil, unless = key | nil }: an ability
--- whose spell ID (or one of its `copy` ranks) is listed (every ability paid from the resource when `spells` is nil)
--- costs less while the aura is up; with charges, each such cast whose declared cost is above 0 takes a stack. While
--- the player's aura `unless` is up (as the cast starts: another modifier's spend in the same cast never decides it),
--- the modifier neither prices nor takes a stack. Also a class file's
--- `spec:RegisterCostMod` (Engine/Schema/Spec.lua): the class file has returned for any other class, so its append is the player's.
function ns.RegisterCostMod(def)
    mods.costMods[#mods.costMods + 1] = def
end

--- { aura = key, pct = n, spells = { spell IDs } | nil } (aura audit C12): a spell-kind GCD of an ability in scope
--- (as a cost modifier's: every ability when `spells` is nil) is (1 + pct) as long while the player's aura is up, before
--- the GCD floor (wowsims spell_mod.go GCDMultiplier, then the haste, then the minimum). A class file's
--- `spec:RegisterGcdMod` (Engine/Schema/Spec.lua). Both layers read it: the sim (M.GcdMult) and the belief (Tracked.lua's
--- def.gcdMods, Families/Casts.lua).
function ns.RegisterGcdMod(def)
    if type(def) == "table" and type(def.aura) == "string" and type(def.pct) == "number" then
        mods.gcdMods[#mods.gcdMods + 1] = def
    end
end

function Race:RegisterCostMod(def)
    if self.live then
        ns.RegisterCostMod(def)
    end
end

--- { resource = key, aura = key, mult = n | spirit = m | share = s | mp5 = x }: a regen entry (Engine/Schema/Spec/Regen.lua's
--- rate fields) on the class's resource `resource` while the player's aura `aura` is up; a class without that resource
--- ignores it (Tracked.lua). The belief's only: the sim's forecast reads the belief's rate.
function Race:RegisterRegenMod(def)
    if self.live and type(def.resource) == "string" and type(def.aura) == "string" then
        mods.regenMods[#mods.regenMods + 1] = def
    end
end

--- `raceID` (optional): UnitRace's third return, for a race whose token is unconfirmed; either match makes it live.
function Hekili:NewRace(token, raceID)
    local s = Hekili.State
    local live = s.race_token == token or (raceID ~= nil and rawget(s, "race_id") == raceID) -- rawget: a strict state
    return setmetatable({ token = token, live = live }, Race)
end

----------------------------------------------------------------------------------------------------------------------
-- The simulation's half of the cost modifiers: every ability's `spend` answers through the modifiers in scope whose
-- buff is up in Hekili's `state`, and a paid ability in the simulation takes a stack of each charged one.

local M = {}
ns.costMods = M

-- Whether ability `a` is in a modifier's scope: no `spells` (every ability), or its spell ID or a `copy` rank is
-- listed. Cached per ability key the first time (an allocation once per key, never per read).
local function inScope(m, a)
    if not m.spells then
        return true
    end
    local scope = m.scope
    if not scope then
        scope = {}
        m.scope = scope
    end
    local key = rawget(a, "key")
    local hit = key and scope[key]
    if hit ~= nil then
        return hit
    end
    hit = false
    local id, copy = rawget(a, "id"), rawget(a, "copy")
    for _, spell in ipairs(m.spells) do
        if spell == id or spell == copy then
            hit = true
        end
        if type(copy) == "table" then
            for _, c in ipairs(copy) do
                if c == spell then
                    hit = true
                end
            end
        end
    end
    if key then
        scope[key] = hit
    end
    return hit
end

--- A declared cost of ability `a` after the modifiers in scope whose buff is up in the simulated state; a fraction
--- (ns.SpendPoints: below 1, or any magnitude under `spendBase`) takes the same pct as the belief applies to it.
function M.Apply(cost, a)
    local list = mods.costMods
    if #list == 0 or type(cost) ~= "number" or cost <= 0 then
        return cost
    end
    local buff = Hekili.State.buff
    for i = 1, #list do
        local m = list[i]
        if buff[m.aura].up and not (m.unless and buff[m.unless].up) and inScope(m, a) then
            if type(m.pct) == "number" then
                cost = cost * (1 + m.pct)
            elseif type(m.flat) == "number" then
                cost = cost + m.flat
            end
        end
    end
    return cost > 0 and cost or 0
end

--- The simulation's GCD multiplier for ability `a` (nil: none in scope but a modifier without `spells`): the product
--- of (1 + pct) over the GCD modifiers in scope whose buff is up in Hekili's `state`; 1 with none. Allocates nothing
--- after each ability key's first scope read.
function M.GcdMult(a)
    local list = mods.gcdMods
    if #list == 0 then
        return 1
    end
    local buff, f = Hekili.State.buff, 1
    for i = 1, #list do
        local m = list[i]
        if (a and inScope(m, a) or not m.spells) and buff[m.aura].up then
            f = f * (1 + m.pct)
        end
    end
    return f
end

local held = {} -- M.Spend's per-modifier `unless` answers, decided before any stack goes; grows once, to the list's size

--- Ability `key` was cast in the simulation with declared cost `base` (ns.spendResources, before any discount): when
--- `base` is above 0, a stack of each charged modifier in scope whose buff is up (gone at the last), even when the
--- discount brought the paid cost to 0; a modifier whose `unless` aura is up as the cast starts takes none.
function M.Spend(base, key)
    local list = mods.costMods
    if #list == 0 or type(base) ~= "number" or base <= 0 then
        return
    end
    local state = Hekili.State
    local a = Hekili.Class.abilities[key]
    if not a then
        return
    end
    for i = 1, #list do
        local u = list[i].unless
        held[i] = u ~= nil and state.buff[u].up or false
    end
    for i = 1, #list do
        local m = list[i]
        if m.charges and not held[i] and state.buff[m.aura].up and inScope(m, a) then
            state.removeStack(m.aura)
        end
    end
end

--- Shadow check of the memoised cost (tests only; off in shipped code, where a memo hit costs this one boolean test and
--- allocates nothing): on every memo hit the cost is computed again and a difference raises. `shadowHits` counts the hits.
M.shadow = false
M.shadowHits = 0

local function shadowCheck(a, base, cost, resource)
    M.shadowHits = M.shadowHits + 1
    local c, r = base()
    c = M.Apply(c, a)
    if c ~= cost or r ~= resource then
        error(
            ("Hekili: stale memoised cost of %s at %s: %s %s held, %s %s now"):format(
                tostring(rawget(a, "key")),
                tostring(Hekili.State.query_time),
                tostring(cost),
                tostring(resource),
                tostring(c),
                tostring(r)
            )
        )
    end
end

--- Engine/Schema/Spec/Abilities.lua's RegisterAbility: the ability's `spend` answers through the modifiers; `baseSpend` keeps the declared
--- cost (VirtualState's belief applies the same modifiers to it itself). The answer is memoised per ability while the
--- state's mutation count (`state.changes`: reset and every mutator in Engine/Sim/State.lua) and query_time stand: a
--- cost-mod aura applied, consumed or expiring in the simulated future, the offset or delay moving, a form or stance
--- change, a talent (reset) and whatever else a pack's cost function reads through a mutator all move one of the two.
--- A cost function may read auras, talents and known ranks; anything else is not covered by the memo's key.
-- shortcut: a spend set later (by an ability's onLoad) skips this wrap; no ability does today, wrap there if one does.
function M.Wrap(a)
    local declared = rawget(a.funcs, "spend")
    if declared == nil then
        declared = rawget(a, "spend")
    end
    if declared == nil then
        return
    end
    rawset(a, "spend", nil)
    rawset(a, "declaredSpend", declared) -- as declared (a number or the raw function): the belief record's `spend` (Tracked.lua)
    local function base()
        if type(declared) == "function" then
            return declared()
        end
        return declared
    end
    a.funcs.baseSpend = base
    local mChanges, mQ, mCost, mResource = -1, -1, nil, nil -- the memo: upvalues, so a nil cost or resource stores without a table write
    a.funcs.spend = function()
        local state = Hekili.State
        local changes, q = state.changes, state.query_time
        if changes == mChanges and q == mQ then
            if M.shadow then
                shadowCheck(a, base, mCost, mResource)
            end
            return mCost, mResource
        end
        local c, r = base()
        c = M.Apply(c, a)
        mChanges, mQ, mCost, mResource = changes, q, c, r
        return c, r
    end
end
