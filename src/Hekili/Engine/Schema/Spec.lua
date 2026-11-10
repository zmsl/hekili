-- Engine/Schema/Spec.lua
-- The spec engine (was Classes.lua): the spec mixin (ns.SpecMixin) and its small Register* methods. The rest of the spec
-- API is in Engine/Schema/Spec/: resources (Regen), auras and powers (Auras), abilities (Abilities), spec records (Kits),
-- the shared `all` spec and the keys core reads by name (All), the built-in packs (Packs) and SpecializationChanged's
-- merge (Activation). Game content shared by every class lives in Hekili_Shared/Shared/*.lua (registered through
-- Engine/Schema/Shared.lua) and the race packs.

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
                    end

                    if not phase.real[ d ] and phase.activate() then
                        phase.real[ d ] = true
                    end

                    if phase.real[ d ] and phase.deactivate() then
                        phase.real[ d ] = false
                    end

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
        -- `option.section` ({ name, desc }): the options page opens a section (a header and its text) before it
        local section = option.section
        option.section = nil
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
            section = section,
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
