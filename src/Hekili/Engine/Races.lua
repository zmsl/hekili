-- Engine/Races.lua
-- Race packs (event-facade spec §12b). `Hekili:NewRace( token )` returns a registration object a race file
-- (Forever/Races/<Race>.lua) uses like a spec: RegisterAbility, RegisterAura, RegisterResourceMod, RegisterCostMod
-- (a class file declares its own cost modifiers with spec:RegisterCostMod, into the same list).
-- Registrations count only when the token is the player's race (`state.race_token`, UnitRace's locale-free second
-- return); otherwise they are accepted and inert, so every race file runs unconditionally and loads headless.
-- Abilities and auras go to the shared `all` spec (over `all`'s own entry for the same key), and ns.applyRace writes
-- them over the class's after Engine/Spec.lua's merge (which takes the class first and only adds missing keys), so a race
-- registration wins a key clash with the class and with `all`. Resource and cost modifiers go to `ns.raceMods`, one
-- declaration read by two layers:
-- VirtualState's belief (Virtual/State/Families/Modifiers.lua, through Adapter.lua) and Hekili's simulation (below).

local addon, ns = ...
local Hekili = _G[ addon ]

local mods = { maxMods = {}, costMods = {} }
ns.raceMods = mods
Hekili.RaceMods = mods -- read in game at CHECKPOINT B (ns is not global)

local function all()
    return Hekili.Class.specs[ 0 ]
end

-- The keys (and `copy` aliases) the live race registered, by kind: what ns.applyRace writes over the class's.
local owned = { abilities = {}, auras = {} }

-- Records every key of `all`'s `kind` table that holds the entry just registered under `key` (its aliases too).
local function own( kind, key )
    local t = all()[ kind ]
    local v = t[ key ]
    for k, w in pairs( t ) do
        if w == v then owned[ kind ][ k ] = true end
    end
end

--- Engine/Spec.lua's SpecializationChanged, after merging the specs: the race's abilities and auras win over the class's.
function ns.applyRace( class )
    local spec = all()
    for kind, keys in pairs( owned ) do
        for k in pairs( keys ) do
            class[ kind ][ k ] = spec[ kind ][ k ]
        end
    end
end

local Race = {}
Race.__index = Race

function Race:RegisterAbility( key, def )
    if self.live then
        all():RegisterAbility( key, def )
        own( "abilities", key )
    end
end

function Race:RegisterAura( key, def )
    if self.live then
        all():RegisterAura( key, def )
        own( "auras", key )
    end
end

--- { max = pct }: every resource the loaded class registered gets pct more maximum.
function Race:RegisterResourceMod( def )
    if self.live and type( def.max ) == "number" then
        mods.maxMods[ #mods.maxMods + 1 ] = { pct = def.max }
    end
end

--- { aura = key, pct = n | flat = n, charges = k | nil, spells = { spell IDs } | nil }: an ability whose spell ID (or
--- one of its `copy` ranks) is listed (every ability paid from the resource when `spells` is nil) costs less while the
--- aura is up; with charges, each such cast whose declared cost is above 0 takes a stack. Also a class file's
--- `spec:RegisterCostMod` (Engine/Spec.lua): the class file has returned for any other class, so its append is the player's.
function ns.RegisterCostMod( def )
    mods.costMods[ #mods.costMods + 1 ] = def
end

function Race:RegisterCostMod( def )
    if self.live then ns.RegisterCostMod( def ) end
end

function Hekili:NewRace( token )
    return setmetatable( { token = token, live = Hekili.State.race_token == token }, Race )
end

----------------------------------------------------------------------------------------------------------------------
-- The simulation's half of the cost modifiers: every ability's `spend` answers through the modifiers in scope whose
-- buff is up in Hekili's `state`, and a paid ability in the simulation takes a stack of each charged one.

local M = {}
ns.costMods = M

-- Whether ability `a` is in a modifier's scope: no `spells` (every ability), or its spell ID or a `copy` rank is
-- listed. Cached per ability key the first time (an allocation once per key, never per read).
local function inScope( m, a )
    if not m.spells then return true end
    local scope = m.scope
    if not scope then
        scope = {}
        m.scope = scope
    end
    local key = rawget( a, "key" )
    local hit = key and scope[ key ]
    if hit ~= nil then return hit end
    hit = false
    local id, copy = rawget( a, "id" ), rawget( a, "copy" )
    for _, spell in ipairs( m.spells ) do
        if spell == id or spell == copy then hit = true end
        if type( copy ) == "table" then
            for _, c in ipairs( copy ) do
                if c == spell then hit = true end
            end
        end
    end
    if key then scope[ key ] = hit end
    return hit
end

--- A declared cost of ability `a` after the modifiers in scope whose buff is up in the simulated state; a fraction of
--- the maximum (cost < 1) takes the same pct as the belief applies to it.
function M.Apply( cost, a )
    local list = mods.costMods
    if #list == 0 or type( cost ) ~= "number" or cost <= 0 then return cost end
    local buff = Hekili.State.buff
    for i = 1, #list do
        local m = list[ i ]
        if buff[ m.aura ].up and inScope( m, a ) then
            if type( m.pct ) == "number" then cost = cost * ( 1 + m.pct )
            elseif type( m.flat ) == "number" then cost = cost + m.flat end
        end
    end
    return cost > 0 and cost or 0
end

--- Ability `key` was cast in the simulation with declared cost `base` (ns.spendResources, before any discount): when
--- `base` is above 0, a stack of each charged modifier in scope whose buff is up (gone at the last), even when the
--- discount brought the paid cost to 0.
function M.Spend( base, key )
    local list = mods.costMods
    if #list == 0 or type( base ) ~= "number" or base <= 0 then return end
    local state = Hekili.State
    local a = Hekili.Class.abilities[ key ]
    if not a then return end
    for i = 1, #list do
        local m = list[ i ]
        if m.charges and state.buff[ m.aura ].up and inScope( m, a ) then state.removeStack( m.aura ) end
    end
end

--- Engine/Spec.lua's RegisterAbility: the ability's `spend` answers through the modifiers; `baseSpend` keeps the declared
--- cost (VirtualState's belief applies the same modifiers to it itself).
-- shortcut: a spend set later (by an ability's onLoad) skips this wrap; no ability does today, wrap there if one does.
function M.Wrap( a )
    local declared = rawget( a.funcs, "spend" )
    if declared == nil then declared = rawget( a, "spend" ) end
    if declared == nil then return end
    rawset( a, "spend", nil )
    local function base()
        if type( declared ) == "function" then return declared() end
        return declared
    end
    a.funcs.baseSpend = base
    a.funcs.spend = function()
        local c, r = base()
        return M.Apply( c, a ), r
    end
end
