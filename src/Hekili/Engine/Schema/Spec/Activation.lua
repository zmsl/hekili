-- Engine/Schema/Spec/Activation.lua
-- The spec switch: Hekili:SpecializationChanged's merge of the current spec and spec 0, the character's spec and pack
-- choice (SettleSpecChoice, SetSpecChoice, ActivatePack) and the login and zone events. Loads last in the Spec slot, as
-- the events were once the end of Spec.lua.

local addon, ns = ...
local L = ns.L
local Facade = ns.Facade
local C_SpecializationInfo, C_Spell, GetTime, UnitAttackSpeed, UnitGUID, UnitLevel = Facade.C_SpecializationInfo, Facade.C_Spell, Facade.GetTime, Facade.UnitAttackSpeed, Facade.UnitGUID, Facade.UnitLevel
local Hekili = _G[ addon ]
local class = Hekili.Class
local state = Hekili.State
local GetResourceInfo, ResetDisabledGearAndSpells, RegisterEvent, getSpecializationKey = ns.GetResourceInfo, ns.ResetDisabledGearAndSpells, ns.RegisterEvent, ns.getSpecializationKey
local insert = table.insert
local wipe = table.wipe
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo
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
