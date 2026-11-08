-- Engine/Schema/Spec.lua
-- The spec engine (was Classes.lua): the spec mixin and its Register* API, the shared `all` spec and the keys core reads
-- by name, and SpecializationChanged's merge. Game content shared by every class lives in Hekili_Shared/Shared/*.lua
-- (registered through Engine/Schema/Shared.lua) and the race packs.

local addon, ns = ...
local L = ns.L
local Facade = ns.Facade
local C_Item, C_SpecializationInfo, C_Spell = Facade.C_Item, Facade.C_SpecializationInfo, Facade.C_Spell
local GetSpecializationInfoByID, GetTime, InCombatLockdown, UnitAttackSpeed = Facade.GetSpecializationInfoByID, Facade.GetTime, Facade.InCombatLockdown, Facade.UnitAttackSpeed
local UnitCanAttack, UnitCastingInfo, UnitChannelInfo, UnitClassBase = Facade.UnitCanAttack, Facade.UnitCastingInfo, Facade.UnitChannelInfo, Facade.UnitClassBase
local UnitClass, UnitGUID, UnitLevel = Facade.UnitClass, Facade.UnitGUID, Facade.UnitLevel
local Hekili = _G[ addon ]

-- The client's spell schools by name (unit-registry spec §5.1): a game concept, not class content. Packs declare an
-- ability's `school` by name; Game/State/Families/Expect.lua compiles it to this mask at build.
ns.SCHOOL = { physical = 1, holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64 }
Hekili.SCHOOL = ns.SCHOOL

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
local floor = math.floor

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


-- Forever (border batch 2, E11): the facade's totem slots handed to capped guardians so far (RegisterPets); the
-- client's are 1-5.
local guardianSlots = 0

local HekiliSpecMixin = {
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

                    if Hekili.ActiveDebug then Hekili:Debug( "[ %s ] Phase '%s' set to '%s' (%s).", self.key or "Unspecified", key, tostring( phase.virtual[ d ] ), hook ) end
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

                    if Hekili.ActiveDebug and phase.virtual[ d ] ~= previous then Hekili:Debug( "[ %s ] Phase '%s' set to '%s' (%s) - virtual.", self.key or "Unspecified", key, tostring( phase.virtual[ d ] ), hook ) end
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
                        Hekili:Debug( "[ %s ] Phased variable '%s' set to '%s' (%s) - was '%s'.", self.key or "Unspecified", key, tostring( phase.virtual[ display or "Primary" ] ), hook, tostring( original ) )
                    end
                end )
            else
                self:RegisterHook( hook, function()
                    local d = display or "Primary"
                    local previous = phase.virtual[ d ]

                    phase.virtual[ d ] = phase.update( phase.virtual[ d ], phase.default() )

                    if Hekili.ActiveDebug and phase.virtual[ d ] ~= previous then Hekili:Debug( "[ %s ] Phased variable '%s' set to '%s' (%s) - virtual.", self.key or "Unspecified", key, tostring( phase.virtual[ display or "Primary" ] ), hook ) end
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

    -- (re-pin design §3a, decision 11) A rotation window: a span the client shows no aura for (never where an aura fits).
    -- `evaluator` (optional) is a function of the belief's reads, run once per update in the `now` context
    -- (Game/State/Families/Windows.lua): its false->true edge opens the window. `duration` is an open's length:
    -- seconds, "combat" (no timer: only combat end, a close, close_on_false or its steps end it), or a function of the
    -- forecast's reads (run under state at each forecast open and counted refresh); a function needs `now_duration`,
    -- the belief's own (run in the `now` context at each belief open and counted refresh): one function can't serve
    -- both, as an ability's now() and handler(). A function's non-positive answer opens nothing. `refresh` lets a new
    -- edge restart an open one; `max_duration` (s, from the first open) and `max_refresh` cap that, either, both or
    -- neither. `close_on_false`: the true->false edge closes it. `steps` (ability keys, registered before the window),
    -- `loop`, `on_deviation` ("stay", "skip", "end"; default "stay") and `strict` (any other on-GCD cast ends it) make
    -- it a stepped window. A plain record (Engine/Schema/Tracked.lua hands it to the belief).
    RegisterWindow = function( self, name, data )
        assert( type( name ) == "string" and type( data ) == "table", "RegisterWindow: needs a name and a table" )
        assert( self.windows[ name ] == nil, "RegisterWindow: " .. name .. " is already registered" )
        -- spec 0's windows merge beside every spec's (SpecializationChanged): one name in both would be lost
        for id, s in pairs( class.specs ) do
            assert( ( id == 0 ) == ( self.id == 0 ) or rawget( s, "windows" ) == nil or s.windows[ name ] == nil,
                "RegisterWindow: " .. name .. " is already registered in another spec" )
        end
        local ev, dur = data.evaluator, data.duration
        assert( ev == nil or type( ev ) == "function", "RegisterWindow: " .. name .. "'s evaluator is not a function" )
        local nowDur = data.now_duration
        assert( type( dur ) == "number" and dur > 0 or dur == "combat" or type( dur ) == "function",
            "RegisterWindow: " .. name .. " needs a positive duration, \"combat\" or a function" )
        assert( ( type( dur ) == "function" ) == ( type( nowDur ) == "function" )
            and ( nowDur == nil or type( nowDur ) == "function" ),
            "RegisterWindow: " .. name .. ": a function duration and a now_duration function go together" )
        if type( dur ) == "function" then setfenv( dur, state ) end
        local maxD, maxR = data.max_duration, data.max_refresh
        assert( maxD == nil or type( maxD ) == "number" and maxD > 0, "RegisterWindow: " .. name .. "'s max_duration" )
        assert( maxR == nil or type( maxR ) == "number" and maxR >= 0, "RegisterWindow: " .. name .. "'s max_refresh" )
        local dev = data.on_deviation or "stay"
        assert( dev == "stay" or dev == "skip" or dev == "end", "RegisterWindow: " .. name .. "'s on_deviation" )
        local steps
        if data.steps ~= nil then
            assert( type( data.steps ) == "table" and #data.steps > 0, "RegisterWindow: " .. name .. "'s steps" )
            steps = {}
            for i, key in ipairs( data.steps ) do
                assert( self.abilities[ key ], "RegisterWindow: " .. name .. "'s step " .. tostring( key ) .. " is no registered ability" )
                steps[ i ] = key
            end
        end
        self.windows[ name ] = {
            key = name,
            evaluator = ev,
            duration = dur,
            now_duration = nowDur,
            refresh = data.refresh == true,
            max_duration = maxD,
            max_refresh = maxR,
            close_on_false = data.close_on_false == true,
            steps = steps,
            loop = data.loop == true,
            on_deviation = dev,
            strict = data.strict == true,
        }
    end,

    -- (re-pin design §3a, decision 11; owner 2026-11-03) A reaction: a `now` function run by an observed outcome instead
    -- of a cast, so a window can open on a span only an outcome reveals (never where an aura or a usability flip fits).
    -- `who` "player" (a hit on us) or "target" (our cast or white swing); `outcome` "dodge", "parry", "block" (BLOCK and
    -- BLOCKED), "miss", "deflect", "evade" or "crit"; a spell of ours blocked fires nothing (Game/Events/Rows.lua stages
    -- DODGE, PARRY, MISS, DEFLECT and EVADE only; docs/dev/gaps.md). Outcome "swing" (who "target" only: a hit on us
    -- tells no white swing from a special) runs once per white swing of ours at its settled outcome, whatever it is;
    -- optional `hand` "main" or "off" (the hand the belief paired the swing to) filters it. Not an ability: no index,
    -- cast history, ticket, GCD or options row. The belief runs it in the `now` context at the settled outcome's time
    -- (Game/State/Families/Now.lua); the sim never sees it.
    RegisterReaction = function( self, name, data )
        assert( type( name ) == "string" and type( data ) == "table", "RegisterReaction: needs a name and a table" )
        assert( self.reactions[ name ] == nil, "RegisterReaction: " .. name .. " is already registered" )
        for id, s in pairs( class.specs ) do -- spec 0's reactions merge beside every spec's, as the windows
            assert( ( id == 0 ) == ( self.id == 0 ) or rawget( s, "reactions" ) == nil or s.reactions[ name ] == nil,
                "RegisterReaction: " .. name .. " is already registered in another spec" )
        end
        assert( data.who == "player" or data.who == "target", "RegisterReaction: " .. name .. "'s who" )
        local o = data.outcome
        assert( o == "dodge" or o == "parry" or o == "block" or o == "miss" or o == "deflect" or o == "evade" or o == "crit"
            or ( o == "swing" and data.who == "target" ), "RegisterReaction: " .. name .. "'s outcome" )
        assert( data.hand == nil or o == "swing" and ( data.hand == "main" or data.hand == "off" ),
            "RegisterReaction: " .. name .. "'s hand (a target swing's: main or off)" )
        assert( type( data.now ) == "function", "RegisterReaction: " .. name .. "'s now is not a function" )
        self.reactions[ name ] = { key = name, who = data.who, outcome = o, hand = data.hand, now = data.now }
    end,

    RegisterPack = function( self, name, version, import )
        self.packs[ name ] = {
            version = tonumber( version ),
            import = import:gsub("([^|])|([^|])", "%1||%2")
        }
    end,

    -- (selectors) A kit's spec and pack chooser, after the Hekili classic branch's RegisterPackSelector: `target` is
    -- { spec = a spec key of this class, pack = a built-in priority of that spec }, `condition( tab1, tab2, tab3 )`
    -- the points per tree, run in Selectors.lua's environment (`talent.<name>.rank`, `level`, `max`, `min`) on
    -- login, a talent change and a spec change. Kept in registration order: put the specific before the general; the
    -- first that holds picks its spec (unless the player activated another for the tree) and its pack (unless the
    -- player picked one: ns.SelectPack).
    RegisterSelector = function( self, key, target, condition )
        assert( type( key ) == "string", "RegisterSelector: the key is not a string" )
        assert( type( target ) == "table" and self.specs and self.specs[ target.spec ],
            "RegisterSelector: " .. key .. "'s spec is not one of the class's" )
        assert( type( target.pack ) == "string", "RegisterSelector: " .. key .. "'s pack is not a string" )
        assert( type( condition ) == "function", "RegisterSelector: " .. key .. "'s condition is not a function" )
        self.selectors = self.selectors or {}
        insert( self.selectors, { key = key, spec = target.spec, pack = target.pack, condition = condition } )
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
            -- Forever (border batch 2, E11): a capped guardian's summons sit in the facade's totem slots past the client's
            -- five (one per summon from `slot`); mt_pet's count reads them with GetTotemInfo at the query time.
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
            if data.cap then
                self.pets[ token ].slot = 6 + guardianSlots
                guardianSlots = guardianSlots + data.cap
            end
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
        Hekili:SettingsChanged() -- the belief's plain copy (Engine/Schema/Tracked.lua)
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
            local shown = sim and L["on"] or L["off"]
            if values then shown = tostring( values[ sim ] ) end
            option.desc = string.format( L["%s\n\nThe wowsims gate runs this as %s."], option.desc, shown )
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
            Hekili:SettingsChanged() -- the belief's plain copy (Engine/Schema/Tracked.lua)
        end
    end,

    -- For faster variables.
    RegisterVariable = function( self, key, func )
        CommitKey( key )
        self.variables[ key ] = setfenv( func, state )
    end,
}

-- The mixin crosses files: Engine/Schema/Spec/*.lua add their methods to it (before All.lua builds spec 0).
ns.SpecMixin = HekiliSpecMixin


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
                    sp.package, sp.packManual, sp.packAuto = ns.DefaultPackage( id ), nil, nil
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
                spec.packManual, spec.packAuto = nil, nil
            end
        end
    end

    -- the selectors' pack (Selectors.lua): at login the settle ran before the built-ins above existed
    ns.SelectPackForPick()

    if #changed > 0 or #reverted > 0 or #retired > 0 then
        self:LoadScripts()
    end

    -- A retired list is gone, not updated: say so, and where its specs went.
    if #retired > 0 then
        table.sort( retired )
        local label = Hekili.Engine.Registry.PackLabel
        local names = "|cFFFFD100" .. label( retired[1] ) .. "|r"
        for i = 2, #retired do
            names = names .. ( i == #retired and L[" and "] or ", " ) .. "|cFFFFD100" .. label( retired[i] ) .. "|r"
        end
        local msg = #retired == 1
            and string.format( L["The %s priority was retired; a spec that used it now runs its default priority."], names )
            or string.format( L["The %s priorities were retired; a spec that used one now runs its default priority."], names )
        C_Timer.After( 5, function()
            Hekili:ReviewPacks() -- the active-list cache drops the retired pack's lists
            if Hekili.Engine.settings.notifications.enabled then Hekili:Notify( msg, 6 ) end
            Hekili:Print( msg )
        end )
    end

    if #changed > 0 then
        local msg
        local label = Hekili.Engine.Registry.PackLabel
        for i = 1, #changed do changed[ i ] = label( changed[ i ] ) end

        if #changed == 1 then
            msg = string.format( L["The |cFFFFD100%s|r priority was updated."], changed[1] )
        elseif #changed == 2 then
            msg = string.format( L["The |cFFFFD100%s|r and |cFFFFD100%s|r priorities were updated."], changed[1], changed[2] )
        else
            msg = "|cFFFFD100" .. changed[1] .. "|r"

            for i = 2, #changed - 1 do
                msg = msg .. ", |cFFFFD100" .. changed[i] .. "|r"
            end

            msg = string.format( L["The %s, and |cFFFFD100%s|r priorities were updated."], msg, changed[ #changed ] )
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
        local label = Hekili.Engine.Registry.PackLabel
        for i = 1, #reverted do reverted[ i ] = label( reverted[ i ] ) end

        if #reverted == 1 then
            msg = string.format( L["The |cFFFFD100%s|r priority was reverted."], reverted[1] )
        elseif #reverted == 2 then
            msg = string.format( L["The |cFFFFD100%s|r and |cFFFFD100%s|r priorities were reverted."], reverted[1], reverted[2] )
        else
            msg = "|cFFFFD100" .. reverted[1] .. "|r"

            for i = 2, #reverted - 1 do
                msg = msg .. ", |cFFFFD100" .. reverted[i] .. "|r"
            end

            msg = string.format( L["The %s, and |cFFFFD100%s|r priorities were reverted."], msg, reverted[ #reverted ] )
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
        windows = {}, -- RegisterWindow's records by name
        reactions = {}, -- RegisterReaction's records by name

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

    for k, func in pairs( ns.SpecMixin ) do
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
--- role ("attack"|"tank"|"healer": shown, not simulated), ranged, package (its default priority), movement (true: its
--- priorities read the Movement toggle, whose options row it then shows), unsupported (true: no
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
            options = { package = d.package, movement = d.movement }, -- per spec: the kit's RegisterOptions reaches every tree
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

-- (selectors) The last settle's pick, selector and dominant tree (nil: no points or a tie, so the last pack holds),
-- the spec it settled on with points (nil until then: no notice at login; a read with no points
-- keeps it: PickSpec's `held`), and the notice due.
local picked, pickedBy, pickedTree, settledID, note

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

    -- The class pack's spec: the one chosen for the dominant tree, else its first (Engine/Schema/Selectors.lua). The ranks
    -- may be the last walk's here; SettleSpecChoice re-picks after this pass's walk.
    local kit = class.kit
    local tree, source
    local selector
    if kit then
        tree, source, _, selector = ns.PickSpec( kit, Hekili.Engine.settings.specChoice[ ns.CharKey() ], talentRank, UnitLevel( "player" ), Hekili.Engine.settings.specs, settledID and class.specs[ settledID ] )
    end
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
    wipe( class.windows )
    wipe( class.reactions )

    local specs = { currentID, 0 }

    state.spec.id = currentID
    state.spec.name = tree and tree.name or clientName
    state.spec.key = tree and tree.key or getSpecializationKey( currentID )
    state.spec.clientID = clientID
    state.spec.kitID = kit and kit.id or currentID
    state.spec.source = source or "client"
    state.spec.selector = selector and selector.key

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

            for k, v in pairs( spec.windows ) do
                if not class.windows[ k ] then class.windows[ k ] = v end
            end

            for k, v in pairs( spec.reactions ) do
                if not class.reactions[ k ] then class.reactions[ k ] = v end
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
                        Hekili:Error( "Cannot RegisterStateFunc for an existing expression ( " .. spec.key .. " - " .. name .. " )." )
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
                        Hekili:Error( "Cannot RegisterStateTable for an existing expression ( " .. spec.key .. " - " .. name .. " )." )
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

    -- the belief tracks what this spec registered (Engine/Schema/Tracked.lua); its talent walk runs here, before
    -- ns.updateTalents reads the ranks.
    ns.BuildTracked()
    state:BuildWindows() -- the core's window tables (Engine/Sim/State.lua), from class.windows

    ns.updateTalents()
    ns.TrackedStatics() -- the records' static values, under `state` with this spec's talent ranks (Tracked.lua)
    -- the core's gear read 1 s later (Engine/Sim/Events.lua): a set-bonus aura reads the belief's records, which this
    -- build cleared (gear-aware spec §7, Q2); the belief's own full read is at the same time (Sources/Gear.lua)
    ns.queueGearUpdate() -- Events.lua (before this file in the TOC) sets it at load
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

-- This character's spec choice table ({ [tree] = spec key, last = tree }; Selectors.lua's PickSpec), made on first use;
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


local function notifyPick()
    if note then
        Hekili:Notify( note, 6 )
        note = nil
    end
end

-- The picked spec's pack as its selector (or none) asks (ns.SelectPack); true when it changed.
local function selectPack()
    local settings = Hekili.Engine.settings
    -- no points or a tie (a walk before the ranks arrive, a talent wipe): keep the last pack (review I2)
    if not picked or not pickedTree or picked.unsupported or not settings.specs then return false end
    if not ns.SelectPack( rawget( settings.specs, picked.id ), settings.packs, picked, pickedBy ) then return false end
    ns.queueGearUpdate() -- the gear re-read rebuilds the usable items for the new pack, as a spec change does
    Hekili:ForceUpdate( "SPEC_PACKAGE_CHANGED" )
    local label = Hekili.Engine.Registry.PackLabel
    note = string.format( L["%s: the |cFFFFD100%s|r priority, picked from your talents."], picked.name, label( settings.specs[ picked.id ].package ) )
    C_Timer.After( 5, notifyPick )
    return true
end
ns.SelectPackForPick = selectPack -- RestoreDefaults: again once the built-in priorities exist

--- (per-spec plan) After a spec change's talent walk: share keys of imported packs resolved, the dominant tree
--- remembered (a talent swap to another tree activates that tree's spec), the selectors' pack set (Selectors.lua), and
--- one more pass when this pass's pick (made on the last walk's ranks) was not the settled one.
function Hekili:SettleSpecChoice( clientID )
    local kit, settings = class.kit, Hekili.Engine.settings
    local tree = ns.DominantTree( ns.TreePoints( kit.talents, talentRank ) )
    local choice = charChoice( tree )
    if tree then choice.last = tree end
    local pick, source, _, sel = ns.PickSpec( kit, choice, talentRank, UnitLevel( "player" ), settings.specs, settledID and class.specs[ settledID ] )
    if ns.MigrateTrees( settings.specs, settings.packs, settings.specMigrated, kit, clientID, pick ) then
        self:SettingsChanged() -- the migrated settings reach the belief's plain copy (Engine/Schema/Tracked.lua)
    end
    ns.ResolvePackSpecs( settings.packs, class.specByShare )
    picked, pickedBy, pickedTree = pick, sel, tree
    local packChanged = selectPack()
    if pick.id ~= state.spec.id then
        self.PendingSpecializationChange = true
        return
    end
    -- settled: the pick's source is this walk's (the pass's own pick may have been on the last walk's ranks)
    state.spec.source, state.spec.selector = source, sel and sel.key
    -- a selector's spec switch (not the first settle: a login) gets the notice a pack change has not given, on this
    -- pass or the last one (its notice, still pending, names the spec too)
    if source == "selector" and not packChanged and not note and settledID and settledID ~= pick.id then
        note = string.format( L["%s, picked from your talents."], pick.name )
        C_Timer.After( 5, notifyPick )
    end
    if tree then settledID = pick.id end
end

--- (selectors) Activates a pack, the player's: `name` (nil: the one in place) becomes spec `specID`'s package, marked
--- the player's (`packManual`: no selector replaces it), and the pack's spec this character's spec for the current
--- dominant tree (activation is at the pack level, owner 2026-11-08: a spec is active through one of its packs).
--- The spec page's Priority, a pack's Active toggle, /hekili priority and SetSpecChoice call it. Returns true when
--- it activated the pack (false: no readable profile for the spec).
function Hekili:ActivatePack( specID, name )
    local sp = Hekili.Engine.settings.specs[ specID ]
    if type( sp ) ~= "table" then return false end
    if name ~= nil then sp.package = name end
    sp.packManual, sp.packAuto = true, nil
    local kit, s = class.kit, class.specs[ specID ]
    if not kit or not s or rawget( s, "kit" ) ~= kit then return true end -- a spec outside the class kit
    local tree = ns.DominantTree( ns.TreePoints( kit.talents, talentRank ) )
    local choice = charChoice( tree )
    choice[ tree or choice.last or 0 ] = s.key
    self.PendingSpecializationChange = true
    return true
end

--- Activates a spec for this character's current dominant talent tree through its pack in place (ActivatePack: kept
--- until another pack is activated on that tree) and switches to it at the next frame: `key` is a spec key, or a
--- prefix of one spec's key or name (case-insensitive). Returns the spec, or nil when no spec or more than one matches.
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
    if not self:ActivatePack( s.id ) then return end
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
