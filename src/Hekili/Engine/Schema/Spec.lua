-- Engine/Schema/Spec.lua
-- The spec engine (was Classes.lua): the spec mixin and its Register* API, the shared `all` spec and the keys core reads
-- by name, and SpecializationChanged's merge. Game content shared by every class lives in Hekili_Shared/Shared/*.lua
-- (registered through Engine/Schema/Shared.lua) and the race packs.

local addon, ns = ...
local Facade = ns.Facade
local C_Item, C_SpecializationInfo, C_Spell = Facade.C_Item, Facade.C_SpecializationInfo, Facade.C_Spell
local GetSpecializationInfoByID, GetTime, InCombatLockdown, UnitAttackSpeed = Facade.GetSpecializationInfoByID, Facade.GetTime, Facade.InCombatLockdown, Facade.UnitAttackSpeed
local UnitCanAttack, UnitCastingInfo, UnitChannelInfo, UnitClassBase = Facade.UnitCanAttack, Facade.UnitCastingInfo, Facade.UnitChannelInfo, Facade.UnitClassBase
local UnitClass, UnitGUID = Facade.UnitClass, Facade.UnitGUID
local Hekili = _G[ addon ]

local class = Hekili.Class
local state = Hekili.State

local CommitKey = ns.commitKey
local FindUnitBuffByID, FindUnitDebuffByID = ns.FindUnitBuffByID, ns.FindUnitDebuffByID
local GetItemInfo = ns.CachedGetItemInfo
local GetResourceInfo, GetResourceKey = ns.GetResourceInfo, ns.GetResourceKey
local ResetDisabledGearAndSpells = ns.ResetDisabledGearAndSpells
local RegisterEvent = ns.RegisterEvent
local RegisterUnitEvent = ns.RegisterUnitEvent

local getSpecializationKey = ns.getSpecializationKey

local insert, wipe = table.insert, table.wipe

local mt_resource = ns.metatables.mt_resource

local GetSpellDescription, GetSpellTexture = C_Spell.GetSpellDescription, C_Spell.GetSpellTexture
local GetSpecialization, GetSpecializationInfo = C_SpecializationInfo.GetSpecialization, C_SpecializationInfo.GetSpecializationInfo
local GetItemSpell = C_Item.GetItemSpell
local GetSpellInfo = C_Spell.GetSpellInfo
local GetRealmName, GetTalentInfoByID, UnitName = Facade.GetRealmName, Facade.GetTalentInfoByID, Facade.UnitName

-- A RegisterTalents entry's rank: the facade answers the C_Traits walk's rank as GetTalentInfoByID's 12th return.
local function talentRank( t )
    return ( select( 12, GetTalentInfoByID( t ) ) ) or 0
end

--- The key a character's spec choice is stored under: "Name-Realm".
function ns.CharKey()
    return ( UnitName( "player" ) or "?" ) .. "-" .. ( GetRealmName() or "?" )
end

local specTemplate = {
    enabled = true,

    aoe = 2,
    cycle = false,
    cycle_min = 6,
    gcdSync = true,

    nameplates = true,
    petbased = false,

    damage = true,
    damageExpiration = 8,
    damageDots = false,
    damageOnScreen = true,
    damageRange = 0,
    damagePets = false,

    -- Toggles
    custom1Name = "Custom 1",
    custom2Name = "Custom 2",
    noFeignedCooldown = false,
    disable_items = false,

    abilities = {
        ['**'] = {
            disabled = false,
            toggle = "default",
            clash = 0,
            targetMin = 0,
            targetMax = 0,
            dotCap = 0,
            boss = false
        }
    },
    items = {
        ['**'] = {
            disabled = false,
            toggle = "default",
            clash = 0,
            targetMin = 0,
            targetMax = 0,
            boss = false,
            criteria = nil
        }
    },

    placeboBar = 3,

    ranges = {},
    settings = {},
    phases = {},
    cooldowns = {},
    utility = {},
    defensives = {},
    custom1 = {},
    custom2 = {},
}
ns.specTemplate = specTemplate -- for options.


local function Aura_DetectSharedAura( t, type )
    if not t then return end
    local finder = type == "debuff" and FindUnitDebuffByID or FindUnitBuffByID
    local aura = class.auras[ t.key ]

    local name, _, count, _, duration, expirationTime, caster = finder( aura.shared, aura.id )

    if name then
        t.count = count > 0 and count or 1

        if expirationTime > 0 then
            t.applied = expirationTime - duration
            t.expires = expirationTime
        else
            t.applied = state.query_time
            t.expires = state.query_time + t.duration
        end
        t.caster = caster
        return
    end

    t.count = 0
    t.applied = 0
    t.expires = 0
    t.caster = "nobody"
end


local protectedFunctions = {
    -- Channels.
    start = true,
    tick = true,
    finish = true,

    -- Casts
    handler = true, -- Cast finish.
    impact = true,  -- Projectile impact.
}


-- A missable DoT (an ability's `missable`, C15): a dodged, parried or missed cast still raised SPELL_CAST_SUCCESS, so
-- its `now` applied the debuff (`missable = true`: the ability's own key; a string: that debuff's key). Our
-- SPELL_MISSED row of any of its IDs (Game/Events/Rows.lua synthesizes it) removes it at the next reset, unless it was
-- applied again since. One combat-log hook and one reset hook per spec; neither allocates.
local function trackMisses( spec, key, data )
    local missedAt, auraOf = spec.missedAt, spec.missAura
    if not missedAt then
        missedAt, auraOf = {}, {}
        spec.missedAt, spec.missAura = missedAt, auraOf
        local function onRow( _, subtype, _, sourceGUID, _, _, _, _, _, _, _, spellID )
            local aura = subtype == "SPELL_MISSED" and sourceGUID == state.GUID and auraOf[ spellID ]
            if aura then missedAt[ aura ] = GetTime() end
        end
        spec:RegisterHook( "COMBAT_LOG_EVENT_UNFILTERED", onRow )
        spec:RegisterHook( "reset_precast", function()
            if now == query_time then
                for aura, t in pairs( missedAt ) do
                    if t > 0 and debuff[ aura ].up and t >= debuff[ aura ].applied then
                        removeDebuff( "target", aura )
                    end
                end
            end
        end )
    end
    local aura = data.missable == true and key or data.missable
    missedAt[ aura ] = 0
    auraOf[ data.id ] = aura
    local copy = data.copy
    if type( copy ) == "number" then auraOf[ copy ] = aura end
    if type( copy ) == "table" then
        for _, id in ipairs( copy ) do auraOf[ id ] = aura end
    end
end


-- RegisterResource( resourceID, regen, model, meta ): `regen` is Hekili's regen model (named entries); `meta` holds
-- state-bound functions (each setfenv'd to `state`): `max`, `decay`, `decayInterval`, and two fields the belief reads
-- (Game/State/Families/Resources.lua):
--   fsr = { spirit = fn, mp5 = fn }  The five-second rule (C3): continuous regen in two parts, each a rate per second
--                                    (a number or a function, read at the build) and calibrated on its own; after our
--                                    own spend of the resource the spirit part pauses for 5 s, the mp5 part never does.
--                                    The belief's only: no APL field (`mana.fsr` would call the table and raise). Out
--                                    of combat GetPowerRegenForPowerType's two returns (not casting, casting) are read
--                                    as spirit + mp5 and mp5 (Sources/Power.lua). Mana is secret even out of combat:
--                                    its lower bound (`mana.current`, `mana.pct`) is the build's rest (full), moved by
--                                    our spends and the regen, until a short answer below it drops it to the ladder's.
-- A regen entry with `mult` (C3b), `{ aura = key, mult = n }` (n > 0; the belief ignores any other): the resource's
-- calibrated continuous rate x n while the player's aura `key` is up (an energy or mana surge). It is a rate
-- multiplier, not a forecast event: it moves out of the regen model into `state.regenMult` here (Hekili's forecast
-- would call its missing `last`).
-- shortcut: the sim's forecast takes the belief's regen rate at `now` as a constant (Game/API/Facade.lua's
-- GetPowerRegenForPowerType), so it sees neither a `mult` aura expire mid-forecast nor a simulated cast apply one;
-- upgrade with a per-forecast multiplier when a pack's pooling misjudges across a `mult` aura's edge.
-- refundOnAvoid = n (a number, 0-1)  The class's default share of an ability's cost of this resource given back when
--                                    the target dodges, parries or misses it, for an ability declaring
--                                    `refundOnAvoid = true` (RegisterAbility below): the belief's only (Families/Now.lua,
--                                    Obs.Avoided); the sim does not predict avoidance and never reads it.
-- base = n (a number)               The pool's base power at the class's top level (wowsims's base stats): a cost
--                                    between 0 and 1 (or any cost of an ability declaring `spendBase = true`) is
--                                    that fraction of it, floored, as the client prices a percent-of-base cost, in
--                                    both layers (ns.SpendPoints, Families/Casts.lua). The
--                                    belief learns the player's own from a plain out-of-combat cost read (login,
--                                    level-up, spell changes); without `base` a fraction is of the maximum (Hekili's).
local HekiliSpecMixin = {
    RegisterResource = function( self, resourceID, regen, model, meta )
        local resource = GetResourceKey( resourceID )

        if not resource then
            Hekili:Error( "Unable to identify resource with PowerType " .. resourceID .. "." )
            return
        end

        local r = self.resources[ resource ] or {}

        r.resource = resource
        r.type = resourceID
        r.state = model or setmetatable( {
            resource = resource,
            type = resourceID,

            forecast = {},
            fcount = 0,
            times = {},
            values = {},

            actual = 0,
            max = 1,

            active_regen = 0.001,
            inactive_regen = 0.001,
            last_tick = 0,

            swingGen = false,

            add = function( amt, overcap )
                -- Bypasses forecast, useful in hooks.
                if overcap then r.state.amount = r.state.amount + amt
                else r.state.amount = max( 0, min( r.state.amount + amt, r.state.max ) ) end
            end,

            timeTo = function( x )
                return state:TimeToResource( r.state, x )
            end,
        }, mt_resource )
        r.state.regenModel = regen
        r.state.meta = meta or {}

        for _, v in pairs( r.state.meta ) do
            if type( v ) == "table" then -- `fsr`'s parts
                for _, func in pairs( v ) do
                    if type( func ) == "function" then setfenv( func, state ) end
                end
            elseif type( v ) == "function" then -- a number (`refundOnAvoid`) is data
                setfenv( v, state )
            end
        end

        if r.state.regenModel then
            for k, v in pairs( r.state.regenModel ) do
                if v.mult then
                    r.state.regenMult = r.state.regenMult or {}
                    insert( r.state.regenMult, v )
                    r.state.regenModel[ k ] = nil -- clearing a field mid-traversal is allowed
                end
                v.resource = v.resource or resource
                self.resourceAuras[ v.resource ] = self.resourceAuras[ v.resource ] or {}

                if v.aura then
                    self.resourceAuras[ v.resource ][ v.aura ] = true
                end

                if v.channel then
                    self.resourceAuras[ v.resource ].casting = true
                end

                if v.swing then
                    r.state.swingGen = true
                end
            end
        end

        self.primaryResource = self.primaryResource or resource
        self.resources[ resource ] = r

        CommitKey( resource )
    end,

    RegisterTalents = function( self, talents )
        for talent, id in pairs( talents ) do
            self.talents[ talent ] = id
            CommitKey( talent )

            local hero = id[ 4 ]

            if hero then
                self.talents[ hero ] = id
                CommitKey( hero )
                id[ 4 ] = nil
            end
        end
    end,

    RegisterPvpTalents = function( self, pvp )
        for talent, spell in pairs( pvp ) do
            self.pvptalents[ talent ] = spell
            CommitKey( talent )
        end
    end,

    -- A content field beside Hekili's own: `overlay = spellID` on a player proc aura (C2). While the player aura walk is
    -- secret or stopped, the belief reads the proc from that spell's overlay glow (Game/State/Sources/Auras.lua, poll
    -- 11): up with no expiry while it glows, down once it stops. A plain walk wins, except that a permanent aura
    -- with `overlay` still goes down while the glow is off.
    -- Also `isStealthed = true` (C5): the player aura follows IsStealthed (Sources/Forms.lua); and `weaponEnchant = slot`
    -- (C4, Enum.WeaponSlot: 0 main hand, 1 off hand) on an id-less pseudo-aura, read out of combat from
    -- C_Item.GetWeaponEnchantInfo (Sources/Enchants.lua) and modelled from our apply cast in combat.
    RegisterAura = function( self, aura, data )
        CommitKey( aura )

        local a = setmetatable( {
            funcs = {}
        }, {
            __index = function( t, k )
                if t.funcs[ k ] then return t.funcs[ k ]() end

                local setup = rawget( t, "onLoad" )
                if setup then
                    t.onLoad = nil
                    setup( t )

                    return t[ k ]
                end
            end
        } )

        a.key = aura

        if not data.id then
            self.pseudoAuras = self.pseudoAuras + 1
            data.id = ( -1000 * self.id ) - self.pseudoAuras
        end

        -- default values.
        data.duration  = data.duration or 30
        data.max_stack = data.max_stack or 1

        -- This is a shared buff that can come from anyone, give it a special generator.
        --[[ if data.shared then
            a.generate = Aura_DetectSharedAura
        end ]]

        for element, value in pairs( data ) do
            if type( value ) == "function" then
                setfenv( value, state )
                if element ~= "generate" then a.funcs[ element ] = value
                else a[ element ] = value end
            else
                a[ element ] = value
            end

            class.knownAuraAttributes[ element ] = true
        end

        if data.tick_time and not data.tick_fixed then
            if a.funcs.tick_time then
                local original = a.funcs.tick_time
                a.funcs.tick_time = setfenv( function( ... )
                    local val = original( ... )
                    return ( val or 3 ) * haste
                end, state )
                a.funcs.base_tick_time = original
            else
                local original = a.tick_time
                a.funcs.tick_time = setfenv( function( ... )
                    return ( original or 3 ) * haste
                end, state )
                a.base_tick_time = original
                a.tick_time = nil
            end
        end

        self.auras[ aura ] = a

        if a.id then
            if a.id > 0 then
                -- Hekili:ContinueOnSpellLoad( a.id, function( success )
                a.onLoad = function( a )
                    local d = GetSpellInfo( a.id )
                    a.name = d and d.name

                    if not a.name then
                        for k, v in pairs( class.auraList ) do
                            if v == a then class.auraList[ k ] = nil end
                        end

                        Hekili.InvalidSpellIDs = Hekili.InvalidSpellIDs or {}
                        Hekili.InvalidSpellIDs[ a.id ] = a.name or a.key

                        a.id = a.key
                        a.name = a.name or a.key

                        return
                    end

                    a.desc = GetSpellDescription( a.id )

                    local texture = a.texture or GetSpellTexture( a.id )

                    if self.id > 0 then
                        class.auraList[ a.key ] = "|T" .. texture .. ":0|t " .. a.name
                    end

                    self.auras[ a.name ] = a
                    if state.spec.id == self.id or state.spec.kitID == self.id then
                        -- Copy to class table as well.
                        class.auras[ a.name ] = a
                    end

                    if self.pendingItemSpells[ a.name ] then
                        local items = self.pendingItemSpells[ a.name ]

                        if type( items ) == "table" then
                            for i, item in ipairs( items ) do
                                local ability = self.abilities[ item ]
                                ability.itemSpellKey = a.key .. "_" .. ability.itemSpellID

                                self.abilities[ ability.itemSpellKey ] = a
                                class.abilities[ ability.itemSpellKey ] = a
                            end
                        else
                            local ability = self.abilities[ items ]
                            ability.itemSpellKey = a.key .. "_" .. ability.itemSpellID

                            self.abilities[ ability.itemSpellKey ] = a
                            class.abilities[ ability.itemSpellKey ] = a
                        end

                        self.pendingItemSpells[ a.name ] = nil
                        self.itemPended = nil
                    end
                end
            end
            self.auras[ a.id ] = a
        end

        if data.meta then
            for k, v in pairs( data.meta ) do
                if type( v ) == "function" then data.meta[ k ] = setfenv( v, state ) end
                class.knownAuraAttributes[ k ] = true
            end
        end

        if data.copy then
            if type( data.copy ) ~= "table" then
                self.auras[ data.copy ] = a
            else
                for _, key in ipairs( data.copy ) do
                    self.auras[ key ] = a
                end
            end
        end
    end,

    RegisterAuras = function( self, auras )
        for aura, data in pairs( auras ) do
            self:RegisterAura( aura, data )
        end
    end,

    RegisterPower = function( self, power, id, aura )
        self.powers[ power ] = id
        CommitKey( power )

        if aura and type( aura ) == "table" then
            self:RegisterAura( power, aura )
        end
    end,

    RegisterPowers = function( self, powers )
        for k, v in pairs( powers ) do
            self.powers[ k ] = v.id
            self.powers[ v.id ] = k

            for token, ids in pairs( v.triggers ) do
                if not self.auras[ token ] then
                    self:RegisterAura( token, {
                        id = v.id,
                        copy = ids
                    } )
                end
            end
        end
    end,

    RegisterStateExpr = function( self, key, func )
        setfenv( func, state )
        self.stateExprs[ key ] = func
        class.stateExprs[ key ] = func
        CommitKey( key )
    end,

    RegisterStateFunction = function( self, key, func )
        setfenv( func, state )
        self.stateFuncs[ key ] = func
        class.stateFuncs[ key ] = func
        CommitKey( key )
    end,

    RegisterStateTable = function( self, key, data )
        for _, f in pairs( data ) do
            if type( f ) == "function" then
                setfenv( f, state )
            end
        end

        local meta = getmetatable( data )

        if meta and meta.__index then
            setfenv( meta.__index, state )
        end

        self.stateTables[ key ] = data
        class.stateTables[ key ] = data
        CommitKey( key )
    end,

    -- Phases are for more durable variables that should be recalculated over the course of recommendations.
    -- The start/finish conditions are calculated on reset and that state is persistent between sets of recommendations.
    -- Within a set of recommendations, the phase conditions are recalculated when the clock advances and/or when ability handlers are fired.
    -- Notably, finish is only fired if we are currently in the phase.
    RegisterPhase = function( self, key, start, finish, ... )
        if start then start = setfenv( start, state ) end
        if finish then finish = setfenv( finish, state ) end

        self.phases[ key ] = {
            activate = start,
            deactivate = finish,
            virtual = {},
            real = {}
        }

        local phase = self.phases[ key ]
        local n = select( "#", ... )

        for i = 1, n do
            local hook = select( i, ... )

            if hook == "reset_precast" then
                self:RegisterHook( hook, function()
                    local d = display or "Primary"

                    if phase.real[ d ] == nil then
                        phase.real[ d ] = false
                    end

                    local original = phase.real[ d ]

                    if state.time == 0 and not InCombatLockdown() then
                        phase.real[ d ] = false
                        -- Hekili:Print( format( "[ %s ] Phase '%s' set to '%s' (%s) - out of combat.", self.name or "Unspecified", key, tostring( phase.real[ d ] ), hook ) )
                        -- if Hekili.ActiveDebug then Hekili:Debug( "[ %s ] Phase '%s' set to '%s' (%s) - out of combat.", self.name or "Unspecified", key, tostring( phase.virtual[ display or "Primary" ] ), hook ) end
                    end

                    if not phase.real[ d ] and phase.activate() then
                        phase.real[ d ] = true
                    end

                    if phase.real[ d ] and phase.deactivate() then
                        phase.real[ d ] = false
                    end

                    --[[ if phase.real[ d ] ~= original then
                        if d == "Primary" then Hekili:Print( format( "Phase change for %s [ %s ] (from %s to %s).", key, d, tostring( original ), tostring( phase.real[ d ] ) ) ) end
                    end ]]

                    phase.virtual[ d ] = phase.real[ d ]

                    if Hekili.ActiveDebug then Hekili:Debug( "[ %s ] Phase '%s' set to '%s' (%s).", self.name or "Unspecified", key, tostring( phase.virtual[ d ] ), hook ) end
                end )
            else
                self:RegisterHook( hook, function()
                    local d = display or "Primary"
                    local previous = phase.virtual[ d ]

                    if phase.virtual[ d ] ~= true and phase.activate() then
                        phase.virtual[ d ] = true
                    end

                    if phase.virtual[ d ] == true and phase.deactivate() then
                        phase.virtual[ d ] = false
                    end

                    if Hekili.ActiveDebug and phase.virtual[ d ] ~= previous then Hekili:Debug( "[ %s ] Phase '%s' set to '%s' (%s) - virtual.", self.name or "Unspecified", key, tostring( phase.virtual[ d ] ), hook ) end
                end )
            end
        end

        self:RegisterVariable( key, function()
            return self.phases[ key ].virtual[ display or "Primary" ]
        end )
    end,

    RegisterPhasedVariable = function( self, key, default, value, ... )
        value = setfenv( value, state )

        self.phases[ key ] = {
            update = value,
            virtual = {},
            real = {}
        }

        local phase = self.phases[ key ]
        local n = select( "#", ... )

        if type( default ) == "function" then
            phase.default = setfenv( default, state )
        else
            phase.default = setfenv( function() return default end, state )
        end

        for i = 1, n do
            local hook = select( i, ... )

            if hook == "reset_precast" then
                self:RegisterHook( hook, function()
                    local d = display or "Primary"

                    if phase.real[ d ] == nil or ( state.time == 0 and not InCombatLockdown() ) then
                        phase.real[ d ] = phase.default()
                    end

                    local original = phase.real[ d ] or "nil"

                    phase.real[ d ] = phase.update( phase.real[ d ], phase.default() )
                    phase.virtual[ d ] = phase.real[ d ]

                    if Hekili.ActiveDebug then
                        Hekili:Debug( "[ %s ] Phased variable '%s' set to '%s' (%s) - was '%s'.", self.name or "Unspecified", key, tostring( phase.virtual[ display or "Primary" ] ), hook, tostring( original ) )
                    end
                end )
            else
                self:RegisterHook( hook, function()
                    local d = display or "Primary"
                    local previous = phase.virtual[ d ]

                    phase.virtual[ d ] = phase.update( phase.virtual[ d ], phase.default() )

                    if Hekili.ActiveDebug and phase.virtual[ d ] ~= previous then Hekili:Debug( "[ %s ] Phased variable '%s' set to '%s' (%s) - virtual.", self.name or "Unspecified", key, tostring( phase.virtual[ display or "Primary" ] ), hook ) end
                end )
            end
        end

        self:RegisterVariable( key, function()
            return self.phases[ key ].virtual[ display or "Primary" ]
        end )
    end,

    RegisterGear = function( self, ... )
        local arg1 = select( 1, ... )
        if not arg1 then return end

        -- If the first arg is a table, it's registering multiple items/sets
        if type( arg1 ) == "table" then
            for set, data in pairs( arg1 ) do
                self:RegisterGear( set, data )
            end
            return
        end

        local arg2 = select( 2, ... )
        if not arg2 then return end

        -- If the first arg is a string, register it
        if type( arg1 ) == "string" then
            local gear = self.gear[ arg1 ] or {}
            local found = false

            -- If the second arg is a table, it's a tier set with auras
            if type( arg2 ) == "table" then
                if arg2.items then
                    for _, item in ipairs( arg2.items ) do
                        if not gear[ item ] then
                            table.insert( gear, item )
                            gear[ item ] = true
                            found = true
                        end
                    end
                end

                if arg2.auras then
                    -- Register auras (even if no items are found, can be useful for early patch testing).
                    self:RegisterAuras( arg2.auras )
                end
            end

            -- If the second arg is a number, this is a legacy registration with a single set/item
            if type( arg2 ) == "number" then
                local n = select( "#", ... )

                for i = 2, n do
                    local item = select( i, ... )

                    if not gear[ item ] then
                        table.insert( gear, item )
                        gear[ item ] = true
                        found = true
                    end
                end
            end

            if found then
                self.gear[ arg1 ] = gear
                CommitKey( arg1 )
            end

            return
        end

        -- Debug print if needed
        -- Hekili:Print( "|cFFFF0000[Hekili]|r Invalid input passed to RegisterGear." )
    end,


    -- Check for the set bonus based on hidden aura instead of counting the number of equipped items.
    -- This may be useful for tier set items that are crafted so their item ID doesn't match.
    -- The alternative is *probably* to treat sets based on bonusIDs.
    RegisterSetBonus = function( self, key, spellID )
        self.setBonuses[ key ] = spellID
        CommitKey( key )
    end,

    RegisterSetBonuses = function( self, ... )
        local n = select( "#", ... )

        for i = 1, n, 2 do
            self:RegisterSetBonus( select( i, ... ) )
        end
    end,

    RegisterPotion = function( self, potion, data )
        self.potions[ potion ] = data

        data.key = potion

        if data.items then
            if type( data.items ) == "table" then
                for _, key in ipairs( data.items ) do
                    self.potions[ key ] = data
                    CommitKey( key )
                end
            else
                self.potions[ data.items ] = data
                CommitKey( data.items )
            end
        end

        local potionItem = Item:CreateFromItemID( data.item )

        if not potionItem:IsItemEmpty() then
            potionItem:ContinueOnItemLoad( function()
                local name = potionItem:GetItemName() or data.name
                local link = potionItem:GetItemLink() or data.link

                data.name = name
                data.link = link

                class.potionList[ potion ] = link
                return true
            end )
        end

        CommitKey( potion )
    end,

    RegisterPotions = function( self, potions )
        for k, v in pairs( potions ) do
            self:RegisterPotion( k, v )
        end
    end,

    RegisterRecheck = function( self, func )
        self.recheck = func
    end,

    RegisterHook = function( self, hook, func, noState )
        if not ( noState == true or hook == "COMBAT_LOG_EVENT_UNFILTERED" and noState == nil ) then
            func = setfenv( func, state )
        end
        self.hooks[ hook ] = self.hooks[ hook ] or {}
        insert( self.hooks[ hook ], func )
    end,

    -- Content fields beside Hekili's own. `ladder = false`: the ability's usability answers are no rungs of the
    -- belief's cost ladder (Game/State/Families/Resources.lua); without it a short answer is a rung only while its
    -- `usable` holds in the belief's `now` context (a finisher at 0 combo points pins no energy). `missable = true` or
    -- an aura key: a miss leaves that debuff off the target (trackMisses, above). `refundOnAvoid = true` (its resource
    -- meta's share) or a share 0-1: a dodged, parried or missed cast gives back that much of its cost (the belief's
    -- only, Game/State/Families/Now.lua; the sim does not predict avoidance). `onCrit = function() ... end`, beside
    -- `now`: what a critical hit of the cast gives, written with the same verbs when the target's row shows our cast's
    -- own crit (Primal Fury's `gain( 5, "rage" )`); the belief's only, the sim does not predict crits. `spendBase = true`:
    -- its `spend` (scalar or function) is a fraction of its pool's base power at any magnitude, floored, in both layers
    -- (a percent-of-base cost a stacking aura raises past 100%); without it only a cost between 0 and 1 is a fraction.
    RegisterAbility = function( self, ability, data )
        -- A passive (a spell the spellbook knows, never cast): the belief tracks its known rank; the sim never sees it.
        if data.passive then
            assert( type( data.id ) == "number", "RegisterAbility: passive " .. tostring( ability ) .. " needs a numeric id" )
            ns.VirtualState.Track( { abilities = { data.id } } )
            return
        end

        CommitKey( ability )

        local a = setmetatable( {
            funcs = {},
        }, {
            __index = function( t, k )
                local setup = rawget( t, "onLoad" )
                if setup then
                    t.onLoad = nil
                    setup( t )
                    return t[ k ]
                end

                if t.funcs[ k ] then return t.funcs[ k ]() end
                if k == "lastCast" then return state.history.casts[ t.key ] or t.realCast end
                if k == "lastUnit" then return state.history.units[ t.key ] or t.realUnit end
            end,
        } )

        a.key = ability
        a.from = self.id

        if not data.id then
            if data.item then
                class.specs[ 0 ].itemAbilities = class.specs[ 0 ].itemAbilities + 1
                data.id = -100 - class.specs[ 0 ].itemAbilities
            else
                self.pseudoAbilities = self.pseudoAbilities + 1
                data.id = -1000 * self.id - self.pseudoAbilities
            end
            a.id = data.id
        end

        if data.id and type( data.id ) == "function" then
            if not data.copy or type( data.copy ) == "table" and #data.copy == 0 then
                Hekili:Error( "RegisterAbility for %s (Specialization %d) will fail; ability has an ID function but needs to have 'copy' entries for the abilities table.", ability, self.id )
            end
        end


        local item = data.item
        if item and type( item ) == "function" then
            setfenv( item, state )
            item = item()
        end

        if data.meta then
            for k, v in pairs( data.meta ) do
                if type( v ) == "function" then data.meta[ k ] = setfenv( v, state ) end
            end
        end

        -- default values.
        if not data.cast     then data.cast     = 0             end
        if not data.cooldown then data.cooldown = 0             end
        if not data.recharge then data.recharge = data.cooldown end
        if not data.charges  then data.charges  = 1             end

        if data.hasteCD then
            if type( data.cooldown ) == "number" and data.cooldown > 0 then data.cooldown = Hekili:Loadstring( "return " .. data.cooldown .. " * haste" ) end
            if type( data.recharge ) == "number" and data.recharge > 0 then data.recharge = Hekili:Loadstring( "return " .. data.recharge .. " * haste" ) end
        end

        if not data.fixedCast and type( data.cast ) == "number" then
            data.cast = Hekili:Loadstring( "return " .. data.cast .. " * haste" )
        end

        if data.toggle == "interrupts" and data.gcd == "off" and data.readyTime == state.timeToInterrupt and data.interrupt == nil then
            data.interrupt = true
        end

        for key, value in pairs( data ) do
            if type( value ) == "function" then
                setfenv( value, state )

                if not protectedFunctions[ key ] then a.funcs[ key ] = value
                else a[ key ] = value end
                data[ key ] = nil
            else
                a[ key ] = value
            end
        end

        -- The race packs' cost modifiers in the simulation (Engine/Schema/Races.lua, event-facade spec §12b).
        ns.costMods.Wrap( a )

        if ( a.velocity or a.flightTime ) and a.impact and a.isProjectile == nil then
            a.isProjectile = true
        end

        a.realCast = 0

        if item then
            --[[ local name, link, _, _, _, _, _, _, _, texture = GetItemInfo( item )

            a.name = name or ability
            a.link = link or ability ]]

            class.itemMap[ item ] = ability

            -- Register the item if it doesn't already exist.
            class.specs[0]:RegisterGear( ability, item )
            if data.copy then
                if type( data.copy ) == "table" then
                    for _, iID in ipairs( data.copy ) do
                        if type( iID ) == "number" and iID < 0 then class.specs[0]:RegisterGear( ability, -iID ) end
                    end
                else
                    if type( data.copy ) == "number" and data.copy < 0 then class.specs[0]:RegisterGear( ability, -data.copy ) end
                end
            end

            local actionItem = Item:CreateFromItemID( item )
            if not actionItem:IsItemEmpty() then
                actionItem:ContinueOnItemLoad( function( success )
                    local name = actionItem:GetItemName()
                    local link = actionItem:GetItemLink()
                    local texture = actionItem:GetItemIcon()


                    if name then
                        if not a.name or a.name == a.key then a.name = name end
                        if not a.link or a.link == a.key then a.link = link end
                        if not a.funcs.texture then a.texture = a.texture or texture end

                        if a.suffix then
                            a.actualName = name
                            a.name = a.name .. " " .. a.suffix
                        end

                        self.abilities[ ability ] = self.abilities[ ability ] or a
                        self.abilities[ a.name ] = self.abilities[ a.name ] or a
                        self.abilities[ a.link ] = self.abilities[ a.link ] or a
                        self.abilities[ data.id ] = self.abilities[ a.link ] or a

                        a.itemLoaded = GetTime()

                        if a.item and a.item ~= 158075 then
                            a.itemSpellName, a.itemSpellID = GetItemSpell( a.item )

                            if a.itemSpellID then
                                a.itemSpellKey = a.key .. "_" .. a.itemSpellID
                                self.abilities[ a.itemSpellKey ] = a
                                class.abilities[ a.itemSpellKey ] = a
                            end

                            if a.itemSpellName then
                                local itemAura = self.auras[ a.itemSpellName ]

                                if itemAura then
                                    a.itemSpellKey = itemAura.key .. "_" .. a.itemSpellID
                                    self.abilities[ a.itemSpellKey ] = a
                                    class.abilities[ a.itemSpellKey ] = a

                                else
                                    if self.pendingItemSpells[ a.itemSpellName ] then
                                        if type( self.pendingItemSpells[ a.itemSpellName ] ) == "table" then
                                            table.insert( self.pendingItemSpells[ a.itemSpellName ], ability )
                                        else
                                            local first = self.pendingItemSpells[ a.itemSpellName ]
                                            self.pendingItemSpells[ a.itemSpellName ] = {
                                                first,
                                                ability
                                            }
                                        end
                                    else
                                        self.pendingItemSpells[ a.itemSpellName ] = ability
                                        a.itemPended = GetTime()
                                    end
                                end
                            end
                        end

                        if not a.unlisted then
                            class.abilityList[ ability ] = a.listName or ( "|T" .. ( a.texture or texture ) .. ":0|t " .. link )
                            class.itemList[ item ] = a.listName or ( "|T" .. a.texture .. ":0|t " .. link )
                            class.abilityByName[ a.name ] = a
                        end

                        if data.copy then
                            if type( data.copy ) == "string" or type( data.copy ) == "number" then
                                self.abilities[ data.copy ] = a
                            elseif type( data.copy ) == "table" then
                                for _, key in ipairs( data.copy ) do
                                    self.abilities[ key ] = a
                                end
                            end
                        end

                        if data.items then
                            local addedToItemList = false

                            for _, id in ipairs( data.items ) do
                                local copyItem = Item:CreateFromItemID( id )

                                if not copyItem:IsItemEmpty() then
                                    self:RegisterGear( a.key, id )
                                    copyItem:ContinueOnItemLoad( function()
                                        local name = copyItem:GetItemName()
                                        local link = copyItem:GetItemLink()
                                        local texture = copyItem:GetItemIcon()

                                        if name then
                                            class.abilities[ name ] = a
                                            self.abilities[ name ]  = a

                                            if not class.itemList[ id ] then
                                                class.itemList[ id ] = a.listName or ( "|T" .. ( a.texture or texture ) .. ":0|t " .. link )
                                                addedToItemList = true
                                            end
                                        end
                                    end )
                                end
                            end

                            if addedToItemList then
                                if ns.ReadKeybindings then ns.ReadKeybindings() end
                            end
                        end

                        if ability then class.abilities[ ability ] = a end
                        if a.name  then class.abilities[ a.name ]  = a end
                        if a.link  then class.abilities[ a.link ]  = a end
                        if a.id    then class.abilities[ a.id ]    = a end

                        Hekili.OptionsReady = false

                        return true
                    end

                    return false
                end )
            end
        end

        if a.id and a.id > 0 then
            -- Hekili:ContinueOnSpellLoad( a.id, function( success )
            a.onLoad = function()
                local spellInfo = GetSpellInfo( a.id )

                if spellInfo == nil then
                    spellInfo = GetItemInfo( a.id )
                end
                if spellInfo then
                    a.name = spellInfo.name
                else
                    a.name = nil
                end

                if not a.name then
                    for k, v in pairs( class.abilityList ) do
                        if v == a then class.abilityList[ k ] = nil end
                    end
                    Hekili.InvalidSpellIDs = Hekili.InvalidSpellIDs or {}
                    table.insert( Hekili.InvalidSpellIDs, a.id )
                    Hekili:Error( "Name info not available for " .. a.id .. "." )
                    return
                end

                if not a.name then Hekili:Error( "Name info not available for " .. a.id .. "." ); return false end

                a.desc = GetSpellDescription( a.id ) -- was returning raw tooltip data.

                if a.suffix then
                    a.actualName = a.name
                    a.name = a.name .. " " .. a.suffix
                end

                local texture = a.texture or GetSpellTexture( a.id )

                self.abilities[ a.name ] = self.abilities[ a.name ] or a
                class.abilities[ a.name ] = class.abilities[ a.name ] or a

                if not a.unlisted then
                    class.abilityList[ ability ] = a.listName or ( "|T" .. texture .. ":0|t " .. a.name )
                    class.abilityByName[ a.name ] = class.abilities[ a.name ] or a
                end

                if a.rangeSpell and type( a.rangeSpell ) == "number" then
                    Hekili:ContinueOnSpellLoad( a.rangeSpell, function( success )
                        if success then
                            local info = GetSpellInfo( a.rangeSpell )
                            if info then
                                a.rangeSpell = info.name
                            else
                                a.rangeSpell = nil
                            end
                        else
                            a.rangeSpell = nil
                        end
                    end )
                end

                Hekili.OptionsReady = false
            end
        end

        self.abilities[ ability ] = a
        self.abilities[ a.id ] = a

        if not a.unlisted then class.abilityList[ ability ] = class.abilityList[ ability ] or a.listName or a.name end

        if data.copy then
            if type( data.copy ) == "string" or type( data.copy ) == "number" then
                self.abilities[ data.copy ] = a
            elseif type( data.copy ) == "table" then
                for _, key in ipairs( data.copy ) do
                    self.abilities[ key ] = a
                end
            end
        end

        if data.items then
            for _, itemID in ipairs( data.items ) do
                class.itemMap[ itemID ] = ability
            end
        end

        if a.dual_cast or a.funcs.dual_cast then
            self.can_dual_cast = true
            self.dual_cast[ a.key ] = true
        end

        if a.auras then
            self:RegisterAuras( a.auras )
        end

        if data.missable then trackMisses( self, ability, data ) end
    end,

    RegisterAbilities = function( self, abilities )
        for ability, data in pairs( abilities ) do
            self:RegisterAbility( ability, data )
        end
    end,

    RegisterPack = function( self, name, version, import )
        self.packs[ name ] = {
            version = tonumber( version ),
            import = import:gsub("([^|])|([^|])", "%1||%2")
        }
    end,

    -- Built-in packs the class no longer ships (wowsims packs plan, Task 1): RestoreDefaults drops their saved copies
    -- and points a spec that chose one back at its default.
    RetirePacks = function( self, names )
        for _, name in ipairs( names ) do
            class.retiredPacks[ name ] = true
        end
    end,

    RegisterPriority = function( self, name, version, notes, priority )
    end,

    RegisterRanges = function( self, ... )
        if type( ... ) == "table" then
            self.ranges = ...
            return
        end

        for i = 1, select( "#", ... ) do
            insert( self.ranges, ( select( i, ... ) ) )
        end
    end,

    RegisterRangeFilter = function( self, name, func )
        self.filterName = name
        self.filter = func
    end,

    RegisterOptions = function( self, options )
        local trees = rawget( self, "trees" )
        if trees then -- the kit: every spec's options, but each spec keeps its own package (NewClass)
            for _, s in ipairs( trees ) do
                for k, v in pairs( options ) do
                    if k ~= "package" and s.options[ k ] == nil then s.options[ k ] = v end
                end
            end
            return
        end
        self.options = options
    end,

    -- A class's cost modifier (a proc that makes the next abilities cheaper, e.g. Clearcasting): the race object's
    -- RegisterCostMod signature, into the list both VirtualState's belief and the simulation read (Engine/Schema/Races.lua).
    RegisterCostMod = function( self, def )
        ns.RegisterCostMod( def )
    end,

    RegisterEvent = function( self, event, func )
        RegisterEvent( event, function( ... )
            if state.spec.id == self.id or state.spec.kitID == self.id then func( ... ) end
        end )
    end,

    RegisterUnitEvent = function( self, event, unit1, unit2, func )
        RegisterUnitEvent( event, unit1, unit2, function( ... )
            if state.spec.id == self.id or state.spec.kitID == self.id then func( ... ) end
        end )
    end,

    RegisterCombatLogEvent = function( self, func )
        self:RegisterHook( "COMBAT_LOG_EVENT_UNFILTERED", func )
    end,

    RegisterCycle = function( self, func )
        self.cycle = setfenv( func, state )
    end,

    RegisterPet = function( self, token, id, spell, duration, ... )
        CommitKey( token )

        -- Prepare the main model
        local model = {
            id = type( id ) == "function" and setfenv( id, state ) or id,
            token = token,
            spell = spell,
            duration = type( duration ) == "function" and setfenv( duration, state ) or duration
        }

        -- Register the main pet token
        self.pets[ token ] = model

        -- Register copies, but avoid overwriting unrelated registrations
        local n = select( "#", ... )
        if n and n > 0 then
            for i = 1, n do
                local alias = select( i, ... )

                if self.pets[ alias ] and self.pets[ alias ] ~= model then
                    if Hekili.ActiveDebug then
                        Hekili:Debug( "RegisterPet: Alias '%s' already assigned to a different pet. Skipping for token '%s'.", tostring( alias ), tostring( token ) )
                    end
                else
                    self.pets[ alias ] = model
                end
            end
        end
    end,


    RegisterPets = function( self, pets )
        for token, data in pairs( pets ) do
            -- Extract fields from the pet definition.
            local id = data.id
            local spell = data.spell
            local duration = data.duration
            local copy = data.copy

            -- Register the pet and handle the copy field if it exists.
            if copy then
                self:RegisterPet( token, id, spell, duration, type( copy ) == "string" and copy or unpack( copy ) )
            else
                self:RegisterPet( token, id, spell, duration )
            end
            -- Forever (content API 5): `cap` makes it a guardian the belief counts per summon (Game/State/Families/Pets.lua)
            self.pets[ token ].cap = data.cap
        end
    end,

    RegisterTotem = function( self, token, id, ... )
        -- Register the primary totem.
        self.totems[ token ] = id
        self.totems[ id ] = token

        -- Handle copies if provided.
        local n = select( "#", ... )
        if n and n > 0 then
            for i = 1, n do
                local copy = select( i, ... )
                self.totems[ copy ] = id
                self.totems[ id ] = copy
            end
        end

        -- Commit the primary token.
        CommitKey( token )
    end,

    RegisterTotems = function( self, totems )
        for token, data in pairs( totems ) do
            local id = data.id
            local copy = data.copy

            -- Register the primary totem.
            self.totems[ token ] = id
            self.totems[ id ] = token

            -- Register any copies (aliases).
            if copy then
                if type( copy ) == "string" then
                    self.totems[ copy ] = id
                    self.totems[ id ] = copy
                elseif type( copy ) == "table" then
                    for _, alias in ipairs( copy ) do
                        self.totems[ alias ] = token
                    end
                end
            end

            CommitKey( token )
        end
    end,

    GetSetting = function( self, info )
        local setting = info[ #info ]
        return Hekili.Engine.settings.specs[ self.id ].settings[ setting ]
    end,

    SetSetting = function( self, info, val )
        local setting = info[ #info ]
        Hekili.Engine.settings.specs[ self.id ].settings[ setting ] = val
    end,

    -- option should be an AceOption table.
    RegisterSetting = function( self, key, value, option, ... )
        local trees = rawget( self, "trees" )
        if trees then -- the kit: every supported spec (or the specs named after `option`), each with its own option table
            local only = select( "#", ... ) > 0 and { ... } or nil
            for _, k in ipairs( only or {} ) do
                if not self.specs[ k ] then error( "RegisterSetting " .. key .. ": no spec " .. tostring( k ), 2 ) end
            end
            for _, s in ipairs( trees ) do
                local wanted = not only and not s.unsupported
                for _, k in ipairs( only or {} ) do if k == s.key then wanted = true end end
                if wanted then
                    local o = {}
                    for k, v in pairs( option ) do o[ k ] = v end
                    s:RegisterSetting( key, value, o )
                end
            end
            return
        end

        CommitKey( key )

        -- `option.sim`: the harness's default (Engine.SettingDefault); taken out, AceConfig rejects unknown keys
        local sim = option.sim
        option.sim = nil -- the caller's own table on a direct spec call (the kit path passes each spec a copy)
        -- a choice (`select`): its default and `sim` must be candidates (keys of `values`), the note names the choice
        local values = option.type == "select" and type( option.values ) == "table" and option.values
        if values then
            for _, v in ipairs( { value, sim } ) do
                if values[ v ] == nil then error( "RegisterSetting " .. key .. ": " .. tostring( v ) .. " is not one of its values", 2 ) end
            end
        end
        -- the gate's note only on a string `desc`; a function `desc` is the caller's to word
        if sim ~= nil and type( option.desc ) == "string" then
            local shown = sim and "on" or "off"
            if values then shown = tostring( values[ sim ] ) end
            option.desc = option.desc .. "\n\nThe wowsims gate runs this as " .. shown .. "."
        end

        local entry = {
            name = key,
            default = value,
            sim = sim,
            info = option
        }
        table.insert( self.settings, entry )

        option.order = 100 + #self.settings

        option.get = option.get or function( info )
            local setting = info[ #info ]
            local val = Hekili.Engine.settings.specs[ self.id ].settings[ setting ]

            if val ~= nil then return val end
            return Hekili.Engine.SettingDefault( entry )
        end

        option.set = option.set or function( info, val )
            local setting = info[ #info ]
            Hekili.Engine.settings.specs[ self.id ].settings[ setting ] = val
        end
    end,

    -- For faster variables.
    RegisterVariable = function( self, key, func )
        CommitKey( key )
        self.variables[ key ] = setfenv( func, state )
    end,
}


--- A spec's default priority: the package its NewClass entry names (nil for none); load order never changes it.
function ns.DefaultPackage( specID )
    local s = class.specs[ specID ]
    return s and s.options.package
end


function Hekili:RestoreDefaults()
    local p = Hekili.Engine.settings
    local reverted = {}
    local changed = {}
    local retired = {}
    local decoded = {} -- specID -> a built-in decoded for it this call

    -- A retired built-in pack (kit:RetirePacks) leaves the profile; a spec that chose it falls back to its default.
    for k, v in pairs( p.packs ) do
        if class.retiredPacks[ k ] and v.builtIn then
            p.packs[ k ] = nil
            for id, sp in pairs( p.specs ) do
                -- AceDB copies a scalar default in (no __index), so nil would stay nil until the next login.
                if type( sp ) == "table" and rawget( sp, "package" ) == k then
                    sp.package = ns.DefaultPackage( id )
                end
            end
            insert( retired, k )
        end
    end

    for k, v in pairs( class.packs ) do
        local existing = rawget( p.packs, k )

        -- A built-in bound to a spec this session lacks (a pseudo-spec id from before specs per tree) decodes again.
        if not existing or not existing.version or existing.version ~= v.version
            or ( existing.builtIn and not class.specs[ existing.spec ] ) then
            local data = self.DeserializeActionPack( v.import )

            if data and type( data ) == "table" then
                p.packs[ k ] = data.payload
                data.payload.version = v.version
                data.payload.date = v.version
                data.payload.builtIn = true

                if not existing or not existing.version or existing.version <= v.version then
                    insert( changed, k )
                else
                    insert( reverted, k )
                end

                -- The least name, so a spec whose NewClass names no package gets the same one in any load order.
                local specID = data.payload.spec
                if specID and ( not decoded[ specID ] or k < decoded[ specID ] ) then decoded[ specID ] = k end
            end
        end
    end

    -- After every built-in has decoded (packs decode in pairs() order): a spec whose choice is missing or bound to
    -- another spec gets its default, the package its NewClass entry names; a valid saved choice wins.
    for specID, k in pairs( decoded ) do
        local spec = rawget( p.specs, specID )
        if spec then
            local currPack = spec.package and p.packs[ spec.package ]
            if not currPack or currPack.spec ~= specID then
                local def = ns.DefaultPackage( specID )
                local defPack = def and rawget( p.packs, def )
                spec.package = defPack and defPack.spec == specID and def or k
            end
        end
    end

    if #changed > 0 or #reverted > 0 or #retired > 0 then
        self:LoadScripts()
    end

    -- A retired list is gone, not updated: say so, and where its specs went.
    if #retired > 0 then
        table.sort( retired )
        local names = "|cFFFFD100" .. retired[1] .. "|r"
        for i = 2, #retired do
            names = names .. ( i == #retired and " and " or ", " ) .. "|cFFFFD100" .. retired[i] .. "|r"
        end
        local msg = #retired == 1
            and ( "The " .. names .. " priority was retired; a spec that used it now runs its default priority." )
            or ( "The " .. names .. " priorities were retired; a spec that used one now runs its default priority." )
        C_Timer.After( 5, function()
            Hekili:ReviewPacks() -- the active-list cache drops the retired pack's lists
            if Hekili.Engine.settings.notifications.enabled then Hekili:Notify( msg, 6 ) end
            Hekili:Print( msg )
        end )
    end

    if #changed > 0 then
        local msg

        if #changed == 1 then
            msg = "The |cFFFFD100" .. changed[1] .. "|r priority was updated."
        elseif #changed == 2 then
            msg = "The |cFFFFD100" .. changed[1] .. "|r and |cFFFFD100" .. changed[2] .. "|r priorities were updated."
        else
            msg = "|cFFFFD100" .. changed[1] .. "|r"

            for i = 2, #changed - 1 do
                msg = msg .. ", |cFFFFD100" .. changed[i] .. "|r"
            end

            msg = "The " .. msg .. ", and |cFFFFD100" .. changed[ #changed ] .. "|r priorities were updated."
        end

        if msg then
            C_Timer.After( 5, function()
                Hekili:ReviewPacks()
                if Hekili.Engine.settings.notifications.enabled then Hekili:Notify( msg, 6 ) end
                Hekili:Print( msg )
            end )
        end
    end

    if #reverted > 0 then
        local msg

        if #reverted == 1 then
            msg = "The |cFFFFD100" .. reverted[1] .. "|r priority was reverted."
        elseif #reverted == 2 then
            msg = "The |cFFFFD100" .. reverted[1] .. "|r and |cFFFFD100" .. reverted[2] .. "|r priorities were reverted."
        else
            msg = "|cFFFFD100" .. reverted[1] .. "|r"

            for i = 2, #reverted - 1 do
                msg = msg .. ", |cFFFFD100" .. reverted[i] .. "|r"
            end

            msg = "The " .. msg .. ", and |cFFFFD100" .. reverted[ #reverted ] .. "|r priorities were reverted."
        end

        if msg then
            C_Timer.After( 6, function()
                Hekili:ReviewPacks()
                if Hekili.Engine.settings.notifications.enabled then Hekili:Notify( msg, 6 ) end
                Hekili:Print( msg )
            end )
        end
    end
end


function Hekili:RestoreDefault( name )
    local p = Hekili.Engine.settings

    local default = class.packs[ name ]

    if default then
        local data = self.DeserializeActionPack( default.import )

        if data and type( data ) == "table" then
            p.packs[ name ] = data.payload
            data.payload.version = default.version
            data.payload.date = default.version
            data.payload.builtIn = true

            Hekili:ReviewPacks()
        end
    end
end


ns.restoreDefaults = function( category, purge )
end


ns.isDefault = function( name, category )
    if not name or not category then
        return false
    end

    for i, default in ipairs( class.defaults ) do
        if default.type == category and default.name == name then
            return true, i
        end
    end

    return false
end

local function buildSpec( id, key, name, texture, role, pClass, melee )
    local spec = class.specs[ id ] or {
        id = id,
        key = key,
        name = name,
        texture = texture,
        role = role,
        class = pClass,
        melee = melee,

        resources = {},
        resourceAuras = {},
        primaryResource = nil,
        primaryStat = nil,

        talents = {},
        pvptalents = {},
        powers = {},

        auras = {},
        pseudoAuras = 0,

        abilities = {},
        pseudoAbilities = 0,
        itemAbilities = 0,
        pendingItemSpells = {},

        pets = {},
        totems = {},

        potions = {},

        ranges = {},
        settings = {},

        stateExprs = {}, -- expressions are returned as values and take no args.
        stateFuncs = {}, -- functions can take arguments and can be used as helper functions in handlers.
        stateTables = {}, -- tables are... tables.

        gear = {},
        setBonuses = {},

        hooks = {},
        funcHooks = {},
        phases = {},
        interrupts = {},

        dual_cast = {},

        packs = {},
        options = {},

        variables = {}
    }

    class.num = class.num + 1

    for k, func in pairs( HekiliSpecMixin ) do
        spec[ k ] = func
    end

    class.specs[ id ] = spec
    return spec
end

--- Spec 0 (`all`) only; class packs call Hekili:NewClass.
function Hekili:NewSpecialization( specID, isRanged, icon )

    if not specID or specID < 0 then return end

    isRanged = isRanged or ns.Specializations[ specID ].ranged

    local id, name, _, texture, role, pClass

    if Hekili.IsForever() and specID > 0 then id, name, _, texture, role, pClass = GetSpecializationInfoByID( specID )
    else
        id = specID
        texture = icon
    end

    if not id then
        Hekili:Error( "Unable to generate specialization DB for spec ID #" .. specID .. "." )
        return nil
    end

    if specID ~= 0 then
        class.initialized = true
    end

    local token = getSpecializationKey( id )
    return buildSpec( id, token, name, texture, role, pClass, not isRanged )
end

--- (per-spec plan) A class pack's entry point. Returns the class kit: every Register* call on it (abilities, auras,
--- talents as { tree (1-3, 0 unknown), spell, max rank }, resources, hooks, packs, settings) is the class's, read by
--- each of its specs. `def.specs` lists the specs in order, each { key, name, tree (the talent tree it rides), icon,
--- role ("attack"|"tank"|"healer": shown, not simulated), ranged, package (its default priority), unsupported (true: no
--- priorities on Forever; the engine idles and the options page says so) }. Ids are ours: ns.TreeSpecID(client class
--- id, slot), the kit at slot 0. Nil when `token` is not the player's class.
function Hekili:NewClass( token, def )
    local _, playerToken, classID = UnitClass( "player" )
    if token ~= playerToken or type( classID ) ~= "number" or type( def ) ~= "table" or type( def.specs ) ~= "table" then return end

    class.initialized = true
    local kit = buildSpec( ns.TreeSpecID( classID, 0 ), "kit", token, nil, nil, token, true )
    kit.token, kit.trees, kit.specs = token, {}, {}

    for slot, d in ipairs( def.specs ) do
        local id = ns.TreeSpecID( classID, slot )
        local s = setmetatable( {
            id = id,
            key = d.key,
            name = d.name,
            texture = d.icon,
            role = d.role,
            tree = d.tree or 0,
            slot = slot,
            unsupported = d.unsupported or nil,
            melee = not d.ranged,
            kit = kit,
            settings = {},
            options = { package = d.package },
        }, { __index = kit } )
        if d.unsupported then s.options.enabled = false end -- no priorities: no displays

        class.specs[ id ] = s
        kit.trees[ slot ] = s
        kit.specs[ d.key ] = s
        class.specByShare[ token .. ":" .. d.key ] = id
    end

    class.kit = kit
    return kit
end

function Hekili:GetSpecialization( specID )
    if not specID then return class.specs[ 0 ] end
    return class.specs[ specID ]
end


class.file = UnitClassBase( "player" )
local all = Hekili:NewSpecialization( 0, "All", "Interface\\AddOns\\Hekili\\Textures\\HekiliForever" )

------------------------------------------------------------------------------------------------------------------------
-- The `all` spec's engine keys: what core reads by name (the cast and movement auras, the GCD, the APL verbs). Shared game
-- content (auras, consumables, items) is in Hekili_Shared/Shared/*.lua, racials in the race packs.

---@diagnostic disable-next-line: need-check-nil
all:RegisterAuras( {

    casting = {
        name = "Casting",
        generate = function( t, auraType )
            local unit = auraType == "debuff" and "target" or "player"

            if unit == "player" or UnitCanAttack( "player", unit ) then
                local spell, _, _, startCast, endCast, _, _, notInterruptible, spellID = UnitCastingInfo( unit )

                if spell then
                    startCast = startCast / 1000
                    endCast = endCast / 1000

                    t.name = spell
                    t.count = 1
                    t.expires = endCast
                    t.applied = startCast
                    t.duration = endCast - startCast
                    t.v1 = spellID
                    t.v2 = notInterruptible and 1 or 0
                    t.v3 = 0
                    t.caster = unit

                    if unit ~= "target" then return end

                    if state.target.is_dummy then
                        -- Pretend that all casts by target dummies are interruptible.
                        if Hekili.ActiveDebug then Hekili:Debug( "Cast '%s' is fake-interruptible", spell ) end
                        t.v2 = 0
                    end

                    return
                end

                spell, _, _, startCast, endCast, _, notInterruptible, spellID = UnitChannelInfo( unit )
                startCast = ( startCast or 0 ) / 1000
                endCast = ( endCast or 0 ) / 1000
                local duration = endCast - startCast

                -- Channels greater than 10 seconds are nonsense.  Probably.
                if spell and duration <= 10 then
                    t.name = spell
                    t.count = 1
                    t.expires = endCast
                    t.applied = startCast
                    t.duration = duration
                    t.v1 = spellID
                    t.v2 = notInterruptible and 1 or 0
                    t.v3 = 1 -- channeled.
                    t.caster = unit

                    if class.abilities[ spellID ] and class.abilities[ spellID ].dontChannel then
                        removeBuff( "casting" )
                        return
                    end

                    if unit ~= "target" then return end

                    if state.target.is_dummy then
                        -- Pretend that all casts by target dummies are interruptible.
                        if Hekili.ActiveDebug then Hekili:Debug( "Channel '%s' is fake-interruptible", spell ) end
                        t.v2 = 0
                    end

                    return
                end
            end

            t.name = "Casting"
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.v1 = 0
            t.v2 = 0
            t.v3 = 0
            t.caster = unit
        end,
    },

    movement = {
        duration = 5,
        max_stack = 1,
        generate = function ()
            local m = buff.movement

            if moving then
                m.count = 1
                m.expires = query_time + 5
                m.applied = query_time
                m.caster = "player"
                return
            end

            m.count = 0
            m.expires = 0
            m.applied = 0
            m.caster = "nobody"
        end,
    },

    -- Why do we have this, again?
    unknown_buff = {},
} )

all:RegisterAbilities( {
    global_cooldown = {
        id = ns.VirtualStateInternal.GCD_SPELL,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        unlisted = true,
        known = function () return true end,
    },
} )


all:RegisterAbilities( {
    -- INTERNAL HANDLERS
    call_action_list = {
        name = "|cff00ccff[Call Action List]|r",
        listName = '|T136243:0|t |cff00ccff[Call Action List]|r',
        cast = 0,
        cooldown = 0,
        gcd = "off",
        essential = true,
    },

    run_action_list = {
        name = "|cff00ccff[Run Action List]|r",
        listName = '|T136243:0|t |cff00ccff[Run Action List]|r',
        cast = 0,
        cooldown = 0,
        gcd = "off",
        essential = true,
    },

    wait = {
        name = "|cff00ccff[Wait]|r",
        listName = '|T136243:0|t |cff00ccff[Wait]|r',
        cast = 0,
        cooldown = 0,
        gcd = "off",
        essential = true,
    },

    pool_resource = {
        name = "|cff00ccff[Pool Resource]|r",
        listName = "|T136243:0|t |cff00ccff[Pool Resource]|r",
        cast = 0,
        cooldown = 0,
        gcd = "off",
    },

    cancel_action = {
        name = "|cff00ccff[Cancel Action]|r",
        listName = "|T136243:0|t |cff00ccff[Cancel Action]|r",
        cast = 0,
        cooldown = 0,
        gcd = "off",

        usable = function ()
            local a = args.action_name
            local ability = class.abilities[ a ]
            if not a or not ability then return false, "no action identified" end
            if buff.casting.down or buff.casting.v3 ~= 1 then return false, "not channeling" end
            if buff.casting.v1 ~= ability.id then return false, "not channeling " .. a end
            return true
        end,
        timeToReady = function () return gcd.remains end,
    },

    variable = {
        name = "|cff00ccff[Variable]|r",
        listName = '|T136243:0|t |cff00ccff[Variable]|r',
        cast = 0,
        cooldown = 0,
        gcd = "off",
        essential = true,
    },

    cancel_buff = {
        name = "|cff00ccff[Cancel Buff]|r",
        listName = '|T136243:0|t |cff00ccff[Cancel Buff]|r',
        cast = 0,
        gcd = "off",

        startsCombat = false,

        buff = function () return args.buff_name or nil end,

        indicator = "cancel",
        texture = function ()
            if not args.buff_name then return 134400 end

            local a = class.auras[ args.buff_name ]
            -- if not a then return 134400 end
            if a.texture then return a.texture end

            a = a and a.id
            a = a and GetSpellTexture( a )

            return a or 134400
        end,

        usable = function () return args.buff_name ~= nil, "no buff name detected" end,
        timeToReady = function () return gcd.remains end,
        handler = function ()
            if not args.buff_name then return end

            local cancel = args.buff_name and buff[ args.buff_name ]
            cancel = cancel and rawget( cancel, "onCancel" )

            if cancel then
                cancel()
                return
            end

            removeBuff( args.buff_name )
        end,
    }
} )

-- ns.addToggle and ns.addSetting (uncalled; they wrote "Toggle State: "/"Class Option: " keys onto the profile root)
-- removed with the profile port (Task 6): the engine no longer holds the AceDB table.


ns.addWhitespace = function( name, size )

    table.insert( class.settings, {
        name = name,
        option = {
            name = " ",
            type = "description",
            desc = " ",
            width = size
        }
    } )

end


ns.addHook = function( hook, func )
    insert( class.hooks[ hook ], func )
end


do
    local inProgress = {}
    local vars = {}

    local function load_args( ... )
        local count = select( "#", ... )
        if count == 0 then return end

        for i = 1, count do
            vars[ i ] = select( i, ... )
        end
    end

    ns.callHook = function( event, ... )
        if not class.hooks[ event ] or inProgress[ event ] then return ... end
        wipe( vars )
        load_args( ... )

        inProgress[ event ] = true
        for i, hook in ipairs( class.hooks[ event ] ) do
            load_args( hook( unpack( vars ) ) )
        end
        inProgress[ event ] = nil

        return unpack( vars )
    end
end


ns.registerCustomVariable = function( var, default )
    state[ var ] = default
end




ns.setClass = function( name )
    -- deprecated.
    --class.file = name
end


function ns.setRange( value )
    class.range = value
end


local function storeAbilityElements( key, values )

    local ability = class.abilities[ key ]

    if not ability then
        ns.Error( "storeAbilityElements( " .. key .. " ) - no such ability in abilities table." )
        return
    end

    for k, v in pairs( values ) do
        ability.elem[ k ] = type( v ) == "function" and setfenv( v, state ) or v
    end

end
ns.storeAbilityElements = storeAbilityElements


local function modifyElement( t, k, elem, value )

    local entry = class[ t ][ k ]

    if not entry then
        ns.Error( "modifyElement() - no such key '" .. k .. "' in '" .. t .. "' table." )
        return
    end

    if type( value ) == "function" then
        entry.mods[ elem ] = setfenv( value, Hekili.State )
    else
        entry.elem[ elem ] = value
    end

end
ns.modifyElement = modifyElement



function Hekili:GetAbilityInfo( index )

    local ability = class.abilities[ index ]

    if not ability then return end

    -- Decide if more details are needed later.
    return ability.id, ability.name, ability.key, ability.item
end

class.interrupts = {}


local function addPet( key, permanent )
    state.pet[ key ] = rawget( state.pet, key ) or {}
    state.pet[ key ].name = key
    state.pet[ key ].expires = 0

    ns.commitKey( key )
end
ns.addPet = addPet


local function addStance( key, spellID )
    class.stances[ key ] = spellID
    ns.commitKey( key )
end
ns.addStance = addStance


local function setRole( key )

    for k,v in pairs( state.role ) do
        state.role[ k ] = nil
    end

    state.role[ key ] = true

end
ns.setRole = setRole


function Hekili:GetActiveSpecOption( opt )
    if not self.currentSpecOpts then return end
    return self.currentSpecOpts[ opt ]
end


function Hekili:GetActivePack()
    return self:GetActiveSpecOption( "package" )
end


Hekili.SpecChangeHistory = {}

function Hekili:SpecializationChanged()
    local currentSpec = GetSpecialization()
    if currentSpec == 5 then currentSpec = 1 end -- no specialization: the first
    -- Forever's one pseudo-spec per class: its id keys the legacy profile; its role and primary stat stay the
    -- simulation's (a spec's role is shown, not simulated: per-spec plan).
    local clientID, clientName, _, _, clientRole, clientStat = GetSpecializationInfo( currentSpec )

    if clientID == nil then
        self.PendingSpecializationChange = true
        return
    end

    -- The class pack's spec: the one chosen for the dominant tree, else its first (Engine/Schema/Trees.lua). The ranks
    -- may be the last walk's here; SettleSpecChoice re-picks after this pass's walk.
    local kit = class.kit
    local tree, source
    if kit then tree, source = ns.PickSpec( kit, Hekili.Engine.settings.specChoice[ ns.CharKey() ], talentRank ) end
    local currentID = tree and tree.id or clientID

    self.PendingSpecializationChange = false
    self:ForceUpdate( "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" )

    insert( self.SpecChangeHistory, {
        spec = currentID,
        time = GetTime(),
        bt = debugstack()
    } )

    for k, _ in pairs( state.spec ) do
        state.spec[ k ] = nil
    end

    for key in pairs( GetResourceInfo() ) do
        state[ key ] = nil
        class[ key ] = nil
    end

    class.primaryResource = nil

    wipe( state.buff )
    wipe( state.debuff )
    wipe( state.cooldown )

    wipe( class.auras )
    wipe( class.abilities )
    wipe( class.hooks )
    wipe( class.talents )
    wipe( class.pvptalents )
    wipe( class.powers )
    wipe( class.gear )
    wipe( class.setBonuses )
    wipe( class.packs )
    wipe( class.resources )
    wipe( class.resourceAuras )

    wipe( class.pets )

    local specs = { currentID, 0 }

    state.spec.id = currentID
    state.spec.name = tree and tree.name or clientName
    state.spec.key = tree and tree.key or getSpecializationKey( currentID )
    state.spec.clientID = clientID
    state.spec.kitID = kit and kit.id or currentID
    state.spec.source = source or "client"

    for k in pairs( state.role ) do
        state.role[ k ] = false
    end

    if clientRole == "DAMAGER" then
        state.role.attack = true
    elseif clientRole == "TANK" then
        state.role.tank = true
    else
        state.role.healer = true
    end

    if clientStat == 1 then
        state.spec.primaryStat = "strength"
    elseif clientStat == 2 then
        state.spec.primaryStat = "agility"
    else
        state.spec.primaryStat = "intellect"
    end

    state.spec[ state.spec.key ] = true


    for key in pairs( GetResourceInfo() ) do
        state[ key ] = nil
        class[ key ] = nil
    end
    if rawget( state, "rune" ) then state.rune = nil; class.rune = nil; end

    for k in pairs( class.resourceAuras ) do
        class.resourceAuras[ k ] = nil
    end

    class.primaryResource = nil

    for k in pairs( class.stateTables ) do
        rawset( state, k, nil )
        class.stateTables[ k ] = nil
    end

    for k in pairs( class.stateFuncs ) do
        rawset( state, k, nil )
        class.stateFuncs[ k ] = nil
    end

    for k in pairs( class.stateExprs ) do
        class.stateExprs[ k ] = nil
    end

    self.currentSpec = nil
    self.currentSpecOpts = nil

    for i, specID in ipairs( specs ) do
        local spec = class.specs[ specID ]

        if spec then
            if specID == currentID then
                self.currentSpec = spec
                self.currentSpecOpts = rawget( Hekili.Engine.settings.specs, specID )
                state.settings.spec = self.currentSpecOpts

                state.spec.can_dual_cast = spec.can_dual_cast
                state.spec.dual_cast = spec.dual_cast

                for res, model in pairs( spec.resources ) do
                    class.resources[ res ] = model
                    state[ res ] = model.state
                end
                if rawget( state, "runes" ) then state.rune = state.runes end

                for k,v in pairs( spec.resourceAuras ) do
                    class.resourceAuras[ k ] = v
                end

                class.primaryResource = spec.primaryResource

                for talent, id in pairs( spec.talents ) do
                    class.talents[ talent ] = id
                end

                for talent, id in pairs( spec.pvptalents ) do
                    class.pvptalents[ talent ] = id
                end

                class.variables = spec.variables

                class.potionList.default = "|T967533:0|t |cFFFFD100Default|r"
            end

            if specID == currentID or specID == 0 then
                for event, hooks in pairs( spec.hooks ) do
                    for _, hook in ipairs( hooks ) do
                        class.hooks[ event ] = class.hooks[ event ] or {}
                        insert( class.hooks[ event ], hook )
                    end
                end
            end

            for res, model in pairs( spec.resources ) do
                if not class.resources[ res ] then
                    class.resources[ res ] = model
                    state[ res ] = model.state
                end
            end

            if rawget( state, "runes" ) then state.rune = state.runes end

            for k, v in pairs( spec.auras ) do
                if not class.auras[ k ] then class.auras[ k ] = v end
            end

            for k, v in pairs( spec.powers ) do
                if not class.powers[ k ] then class.powers[ k ] = v end
            end

            for k, v in pairs( spec.abilities ) do
                if not class.abilities[ k ] then class.abilities[ k ] = v end
            end

            for k, v in pairs( spec.gear ) do
                if not class.gear[ k ] then class.gear[ k ] = v end
            end

            for k, v in pairs( spec.setBonuses ) do
                if not class.setBonuses[ k ] then class.setBonuses[ k ] = v end
            end

            for k, v in pairs( spec.pets ) do
                if not class.pets[ k ] then class.pets[ k ] = v end
            end

            for k, v in pairs( spec.totems ) do
                if not class.totems[ k ] then class.totems[ k ] = v end
            end

            for k, v in pairs( spec.packs ) do
                if not class.packs[ k ] then class.packs[ k ] = v end
            end

            for name, func in pairs( spec.stateExprs ) do
                if not class.stateExprs[ name ] then
                    if rawget( state, name ) then state[ name ] = nil end
                    class.stateExprs[ name ] = func
                end
            end

            for name, func in pairs( spec.stateFuncs ) do
                if not class.stateFuncs[ name ] then
                    if rawget( state, name ) then
                        Hekili:Error( "Cannot RegisterStateFunc for an existing expression ( " .. spec.name .. " - " .. name .. " )." )
                    else
                        class.stateFuncs[ name ] = func
                        rawset( state, name, func )
                        -- Hekili:Error( "Not real error, registered " .. name .. " for " .. spec.name .. " (RSF)." )
                    end
                end
            end

            for name, t in pairs( spec.stateTables ) do
                if not class.stateTables[ name ] then
                    if rawget( state, name ) then
                        Hekili:Error( "Cannot RegisterStateTable for an existing expression ( " .. spec.name .. " - " .. name .. " )." )
                    else
                        class.stateTables[ name ] = t
                        rawset( state, name, t )
                        -- Hekili:Error( "Not real error, registered " .. name .. " for " .. spec.name .. " (RST)." )
                    end
                end
            end

            if spec.id > 0 then
                local s = rawget( Hekili.Engine.settings.specs, spec.id )

                if s then
                    for k, v in pairs( spec.settings ) do
                        if s.settings[ v.name ] == nil then s.settings[ v.name ] = Hekili.Engine.SettingDefault( v ) end
                    end
                end
            end
        end
    end

    -- The race pack's abilities and auras win a key clash with the class's and `all`'s (Engine/Schema/Races.lua, spec §12b).
    ns.applyRace( class )

    for k in pairs( class.abilityList ) do
        local ability = class.abilities[ k ]

        if ability and ability.id > 0 then
            if not ability.texture or not ability.name then
                local data = GetSpellInfo( ability.id )

                if data and data.name and data.iconID then
                    ability.name = ability.name or data.name
                    class.abilityList[ k ] = "|T" .. data.iconID .. ":0|t " .. ability.name
                end
            else
                class.abilityList[ k ] = "|T" .. ability.texture .. ":0|t " .. ability.name
            end
        end
    end

    state.GUID = UnitGUID( "player" )
    state.player.unit = UnitGUID( "player" )

    ns.callHook( "specializationChanged" )

    -- VirtualState tracks what this spec registered; its talent walk runs here, before ns.updateTalents reads the ranks.
    ns.VirtualState.SpecChanged()

    ns.updateTalents()
    if kit then self:SettleSpecChoice( clientID ) end
    ResetDisabledGearAndSpells()

    state.swings.mh_speed, state.swings.oh_speed = UnitAttackSpeed( "player" )

    ns.EngineFrame.activeThread = nil

    -- The UI and Options read the spec from the status record: publish the change now, not at the next update.
    local status = ns.Output.status
    if status.specID ~= state.spec.id then
        status.specID, status.specKey, status.specName = state.spec.id, state.spec.key, state.spec.name
        ns.Output.Publish( "status", 1 )
    end

    self:UpdateDisplayVisibility()
    self:UpdateDamageDetectionForCLEU()
end

-- This character's spec choice table ({ [tree] = spec key, last = tree }; Trees.lua's PickSpec), made on first use;
-- a legacy scalar choice moves onto `tree` (the dominant tree now, else 0) once.
local function charChoice( tree )
    local all, key = Hekili.Engine.settings.specChoice, ns.CharKey()
    local choice = all[ key ]
    if type( choice ) ~= "table" then
        all[ key ] = { [ tree or 0 ] = type( choice ) == "string" and choice or nil }
        choice = all[ key ]
    end
    return choice
end

--- (per-spec plan) After a spec change's talent walk: share keys of imported packs resolved, the dominant tree
--- remembered (a talent swap to another tree activates that tree's spec), and one more pass when this pass's pick
--- (made on the last walk's ranks) was not the settled one.
function Hekili:SettleSpecChoice( clientID )
    local kit, settings = class.kit, Hekili.Engine.settings
    local tree = ns.DominantTree( ns.TreePoints( kit.talents, talentRank ) )
    local choice = charChoice( tree )
    if tree then choice.last = tree end
    local pick = ns.PickSpec( kit, choice, talentRank )
    ns.MigrateTrees( settings.specs, settings.packs, settings.specMigrated, kit, clientID, pick )
    ns.ResolvePackSpecs( settings.packs, class.specByShare )
    if pick.id ~= state.spec.id then self.PendingSpecializationChange = true end
end

--- Activates a spec for this character's current dominant talent tree (kept until another is activated on that
--- tree) and switches to it at the next frame: `key` is a spec key, or a prefix of one spec's key or name
--- (case-insensitive). Returns the spec, or nil when no spec or more than one matches.
function Hekili:SetSpecChoice( key )
    local kit = class.kit
    if not kit or type( key ) ~= "string" then return end
    key = key:lower()
    local s = kit.specs[ key ]
    if not s then
        for _, t in ipairs( kit.trees ) do
            if t.key:sub( 1, #key ) == key or t.name:lower():sub( 1, #key ) == key then
                if s then return end -- ambiguous
                s = t
            end
        end
    end
    if not s then return end
    local tree = ns.DominantTree( ns.TreePoints( kit.talents, talentRank ) )
    local choice = charChoice( tree )
    choice[ tree or choice.last or 0 ] = s.key
    self.PendingSpecializationChange = true
    return s
end


do
    RegisterEvent( "PLAYER_ENTERING_WORLD", function( event, login, reload )
        if login or reload then
            local currentSpec = GetSpecialization()
            local currentID = GetSpecializationInfo( currentSpec )

            if currentID ~= state.spec.clientID then
                Hekili:SpecializationChanged()
            end
        end
    end )

    local SpellDisableEvents = {
        CHALLENGE_MODE_START = 1,
        CHALLENGE_MODE_RESET = 1,
        CHALLENGE_MODE_COMPLETED = 1,
        PLAYER_ALIVE = 1,
        ZONE_CHANGED_NEW_AREA = 1,
        QUEST_SESSION_CREATED = 1,
        QUEST_SESSION_DESTROYED = 1,
        QUEST_SESSION_ENABLED_STATE_CHANGED = 1,
        QUEST_SESSION_JOINED = 1,
        QUEST_SESSION_LEFT = 1
    }

    local function CheckSpellsAndGear()
        ResetDisabledGearAndSpells()
        ns.updateGear()
    end

    for k in pairs( SpellDisableEvents ) do
        RegisterEvent( k, function( event )
            C_Timer.After( 1, CheckSpellsAndGear )
        end )
    end
end
