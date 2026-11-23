-- Targets.lua
-- July 2024

local addon, ns = ...
local Facade = ns.Facade
local C_AddOns, C_PlayerInfo, C_PvP = Facade.C_AddOns, Facade.C_PlayerInfo, Facade.C_PvP
local GetActionInfo, GetCVar, GetHaste, GetNumGroupMembers = Facade.GetActionInfo, Facade.GetCVar, Facade.GetHaste, Facade.GetNumGroupMembers
local GetTime, GetUnitSpeed, InCombatLockdown, IsActionInRange = Facade.GetTime, Facade.GetUnitSpeed, Facade.InCombatLockdown, Facade.IsActionInRange
local IsInInstance, IsInRaid, UnitAffectingCombat, UnitCanAttack = Facade.IsInInstance, Facade.IsInRaid, Facade.UnitAffectingCombat, Facade.UnitCanAttack
local UnitClassBase, UnitExists, UnitGUID = Facade.UnitClassBase, Facade.UnitExists, Facade.UnitGUID
local UnitHealth, UnitHealthMax, UnitInParty, UnitInRaid = Facade.UnitHealth, Facade.UnitHealthMax, Facade.UnitInParty, Facade.UnitInRaid
local UnitIsDead, UnitIsFriend, UnitIsPVP, UnitIsPlayer = Facade.UnitIsDead, Facade.UnitIsFriend, Facade.UnitIsPVP, Facade.UnitIsPlayer
local UnitIsUnit, UnitName = Facade.UnitIsUnit, Facade.UnitName
local UnitPhaseReason, UnitTokenFromGUID = Facade.UnitPhaseReason, Facade.UnitTokenFromGUID
local issecretvalue = Facade.issecretvalue
local Hekili = _G[addon]
local L = ns.L

local class = Hekili.Class
local state = Hekili.State

local FindUnitBuffByID = ns.FindUnitBuffByID
local FindUnitDebuffByID = ns.FindUnitDebuffByID
local FindExclusionAuraByID

local targetCount = 0
local targets = {}

local myTargetCount = 0
local myTargets = {}

local addMissingTargets = true
local counted = {}

local formatKey = ns.formatKey
local orderedPairs = ns.orderedPairs
local FeignEvent, RegisterEvent = ns.FeignEvent, ns.RegisterEvent
local TargetDummies = ns.TargetDummies

local format = string.format
local wipe = table.wipe

local unitIDs = { "target", "targettarget", "focus", "focustarget", "boss1", "boss2", "boss3", "boss4", "boss5", "arena1", "arena2", "arena3", "arena4", "arena5" }

local npGUIDs = {}
local npUnits = {}
-- T1 (plate count plan v2 §3): the plate tokens whose GUID answered nothing at ADDED (the Map restriction), [token] =
-- true. Presence only: tokens are recycled, so nothing per mob is kept by them. A token is in npGUIDs or here, never both.
local npTokens = {}

Hekili.unitIDs = unitIDs
Hekili.npGUIDs = npGUIDs
Hekili.npUnits = npUnits
Hekili.npTokens = npTokens


function Hekili:GetNameplateUnitForGUID( id )
    return npUnits[ id ]
end

function Hekili:GetGUIDForNameplateUnit( unit )
    return npGUIDs[ unit ]
end

function Hekili:GetUnitByGUID( id )
    for _, unit in ipairs( unitIDs ) do
        if UnitGUID( unit ) == id then return unit end
    end
end

function Hekili:GetUnitByName( name )
    for _, unit in ipairs( unitIDs ) do
        if UnitName( unit ) == name then return unit end
    end

    for unit in pairs( npUnits ) do
        if UnitName( unit ) == name then return unit end
    end
end


do
    -- Pet-Based Target Detection
    -- Requires a class-appropriate pet ability on the player's action bars.
    -- ** Not the pet's action bar. **
    local petAction = 0
    local petSlot = 0

    local myClass = UnitClassBase( "player" )

    local petSpells = {
        HUNTER = {
            [288962] = 10,
            [17253]  = 5,
            [16827]  = 5,
            [159953] = 5,
            [49966]  = 5,
            [263863] = 7,
            [50433]  = 7,
            [24423]  = 7,
            [160060] = 7,
            [50285]  = 7,
            [263840] = 7,
            [263856] = 7,
            [263861] = 7,
            [279362] = 7,
            [160018] = 7,
            [263853] = 7,
            [263423] = 7,
            [54680]  = 7,
            [344352] = 7,
            [50245]  = 7,
            [263857] = 7,
            [263854] = 7,
            [263852] = 7,
            [160065] = 7,
            [263858] = 7,
            [341118] = 7,
            [35346]  = 7,
            [160067] = 7,

            best     = 288962,
            count    = 28
        },

        WARLOCK = {
            [6360]   = 10,
            [7814]   = 7,
            [30213]  = 7,
            [115625] = 7,
            [54049]  = 7,
            [115778] = 7,

            best     = 6360,
            count    = 6
        }
    }

    function Hekili:GetPetBasedTargetSpells()
        return petSpells[ myClass ]
    end

    function Hekili:CanUsePetBasedTargetDetection()
        return petSpells[ myClass ] ~= nil
    end

    function Hekili:HasPetBasedTargetSpell()
        return petSlot > 0
    end

    function Hekili:GetPetBasedTargetSpell()
        return petAction > 0 and petAction or nil
    end

    function Hekili:PetBasedTargetDetectionIsReady( skipRange )
        if petSlot == 0 then return false, "Pet action not found in player action bars." end
        if not UnitExists( "pet" ) then return false, "No active pet." end
        if UnitIsDead( "pet" ) then return false, "Pet is dead." end

        -- If we have a target and the target is out of our pet's range, don't use pet detection.
        if not skipRange and UnitExists( "target" ) and not IsActionInRange( petSlot ) then return false, "Player has target and player's target not in range of pet." end
        return true
    end

    function Hekili:SetupPetBasedTargetDetection()
        petAction = 0
        petSlot = 0

        if not self:CanUsePetBasedTargetDetection() then return end

        local spells = petSpells[ myClass ]
        local success = false

        for i = 1, 180 do
            local slotType, spell = GetActionInfo( i )

            if slotType and spell and spells[ spell ] then
                petAction = spell
                petSlot = i
                return true
            end
        end

        return success
    end

    function Hekili:TargetIsNearPet( unit )
        return IsActionInRange( petSlot, unit )
    end

    function Hekili:DumpPetBasedTargetInfo()
        self:Print( petAction, petSlot )
    end
end


-- Excluding enemy by NPC ID (as string).  This keeps the enemy from being counted if they are not your target.
-- = true           Always Exclude
-- = number         If table, [1] = de/buff Id per below, [2] = boolean (true = exclude if not present)
-- = number < 0     Exclude if debuff ID abs( number ) is active on unit.
-- = number > 0     Exclude if buff ID number is active on unit.
local enemyExclusions = {
    [23775]  = true,              -- Head of the Horseman
    [120651] = true,              -- Explosives
    [128652] = true,              -- Viq'Goth (Siege of Boralus - untargetable background boss)
    [156227] = true,              -- Neferset Denizen
    [160966] = true,              -- Thing from Beyond?
    [161895] = true,              -- Thing from Beyond?
    [157452] = true,              -- Nightmare Antigen in Carapace
    [158041] = 310126,            -- N'Zoth with Psychic Shell
    [164698] = true,              -- Tor'ghast Junk
    [177117] = 355790,            -- Ner'zhul: Orb of Torment (Protected by Eternal Torment)
    [176581] = true,              -- Painsmith:  Spiked Ball
    [186150] = true,              -- Soul Fragment (Gavel of the First Arbiter)
    [185685] = true,              -- Season 3 Relics
    [185680] = true,              -- Season 3 Relics
    [185683] = true,              -- Season 3 Relics
    [183501] = 367573,            -- Xy'mox: Genesis Bulwark
    [166969] = true,              -- Frieda
    [166970] = true,              -- Stavros
    [166971] = true,              -- Niklaus
    [168113] = 329606,            -- Grashaal (when shielded)
    [168112] = 329636,            -- Kaal (when shielded)
    [193760] = true,              -- Surging Ruiner (Raszageth) -- gives bad range information.
    [204560] = true,              -- Incorporeal Being
    [229296] = true,              -- Orb of Ascendance (TWW S1 Affix)
    [218884] = true,              -- Silken Court: Scattershell Scarab
    [235187] = true,              -- Cauldron: Voltaic Image
    [231788] = true,              -- Mug'Zee: Unstable Crawler Mine
    [233474] = true,              -- Mug'Zee: Gallagio Goon (they are within a cage with LoS restrictions)
    [231727] = true,              -- Gallywix: 1500-Pound "Dud"
    [237967] = true,              -- Gallywix: Discharged Giga Bomb
    [237968] = true,              -- Gallywix: Charged Giga Bomb
    [151579] = true,              -- Operation: Mechagon - Shield Generator
    [219588] = true,              -- Cinderbrew Meadery - Yes Man (etc.),
    [165913] = true,              -- Halls of Atonement: Ghastly Parishioner
    [240905] = 1231726,           -- Manaforge Omega: Forgeweaver Araz - Arcane Collectord immunity during P1
    [233817] = 1231726,           -- Manaforge Omega: Forgeweaver Araz - Forgeweaver Araz immunity during Intermission
    [237763] = 1228284,           -- Manaforge Omega: Nexus King Salad Bar - Royal Ward immunity
    [245705] = true               -- Manaforge Omega: Dimensius - Voidwarden (one should be focussed/cleaved down off miniboss, no reason to full AoE)
}

local requiredForInclusion = {
    [131825] = 260805,    -- Focusing Iris (damage on others is wasted)
    [131823] = 260805,    -- Same
    [131824] = 206805,    -- Same
    [230312] = 467454     -- Mug'Zee: Volunteer Rocketeer, only attackable with "Charred"
}

if Hekili.IsDev then
    -- Add these exclusions only in development copies, until a solution is built for funnelers vs. non-funnelers.
    enemyExclusions[202971] = 404705 -- Null Glimmer
    enemyExclusions[202969] = 404705 -- Empty Recollection
end

-- A client answer, or nil when it is secret: never truth-tested, compared or used as a key (T1).
local function plain( v )
    if issecretvalue( v ) then return nil end
    return v
end

-- Under the Map addon restriction a unit's identity is secret, which the facade answers as nil (unknown): a nil GUID
-- keys nothing, and a plate whose GUID turned secret is dropped by the GUID stored while it was plain. Such a plate is
-- kept by its token (npTokens, T1), so the count still sees it.
local function plateAdded( unit )
    local old = npGUIDs[ unit ]
    npGUIDs[ unit ], npTokens[ unit ] = nil, nil
    if old ~= nil and npUnits[ old ] == unit then npUnits[ old ] = nil end

    if plain( UnitIsFriend( "player", unit ) ) then return end

    local id = UnitGUID( unit )
    if id == nil then
        npTokens[ unit ] = true
        return
    end

    npGUIDs[ unit ] = id
    npUnits[ id ]   = unit
end

RegisterEvent( "NAME_PLATE_UNIT_ADDED", function( event, unit )
    plateAdded( unit )
end )

-- Plates already up at a login or /reload: their ADDED may not fire again (assumed until probe P14, ledger L77), so
-- each existing token is taken as added.
do
    local TOKENS = {}
    for i = 1, 40 do TOKENS[ i ] = "nameplate" .. i end

    RegisterEvent( "PLAYER_ENTERING_WORLD", function( event, login, reload )
        if not ( login or reload ) then return end
        for i = 1, 40 do
            local unit = TOKENS[ i ]
            if plain( UnitExists( unit ) ) then plateAdded( unit ) end
        end
    end )
end

RegisterEvent( "NAME_PLATE_UNIT_REMOVED", function( event, unit )
    local storedGUID = npGUIDs[ unit ]
    local id = UnitGUID( unit )

    npGUIDs[ unit ], npTokens[ unit ] = nil, nil -- never UnitExists here: it still answers true during the event

    if npUnits[ id ] and npUnits[ id ] == unit then npUnits[ id ] = nil end
    if npUnits[ storedGUID ] and npUnits[ storedGUID ] == unit then npUnits[ storedGUID ] = nil end
end )

RegisterEvent( "UNIT_FLAGS", function( event, unit )
    if unit == "player" or UnitIsUnit( unit, "player" ) then return end

    if plain( UnitIsFriend( "player", unit ) ) then
        local id = UnitGUID( unit ) or npGUIDs[ unit ] -- secret: the GUID stored while it was plain
        if id ~= nil then
            ns.eliminateUnit( id )
            npUnits[ id ] = nil
        end
        npGUIDs[ unit ], npTokens[ unit ] = nil, nil
    end
end )


local RC = Facade.LibRangeCheck -- the one range source (range plan R2): LibRangeCheck through the facade
local NEAR_YD = 10 -- caster range (L644): within this many yards a plate counts in or out of combat, as melee always did
local LSR = LibStub( "SpellRange-1.0" )

local lastCount = 1
local lastStationary = 1
local heldLow = false -- the token count's fall held this update (T1)
local unheldCount = 1 -- the count before the hold: what target swaps read (integ/dot I1)
local several, sawSeveral = false, false -- time to die's one or several enemies (B8 I2), and the last update's


-- War Mode
local warmode = false

do
    local function CheckWarMode( event, login, reload )
        if event ~= "PLAYER_ENTERING_WORLD" or login or reload then
            warmode = C_PvP.IsWarModeDesired()
        end
    end

    RegisterEvent( "UI_INFO_MESSAGE", CheckWarMode )
    RegisterEvent( "PLAYER_ENTERING_WORLD", CheckWarMode )
end

-- Timerunning Hardmode
local timeRunningHwt = false

do
    local IsPlayerInTimerunningHeroicWorldTier = C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier

    local function UpdateTimerunning()
        timeRunningHwt = IsPlayerInTimerunningHeroicWorldTier()
    end

    local function TimerunningCheck()
        timeRunningHwt = IsPlayerInTimerunningHeroicWorldTier()
        C_Timer.After( 2, UpdateTimerunning )
    end

    ns.TimerunningCheck = TimerunningCheck

    RegisterEvent( "PLAYER_ENTERING_WORLD", TimerunningCheck )
end

local function UnitInPhase( unit )
    local reason = UnitPhaseReason( unit )
    local wm = not IsInInstance() and warmode

    if reason == 4 and timeRunningHwt then return true end
    if reason == 2 and wm then return true end
    if reason == nil then return true end

    return false
end


--[[

For targeting, let's keep more of the settings static to reduce overhead with target counting.

We have:
1. Count Nameplates
   - Spell
   - Filter UnitAffectingCombat
   -

]]--


do
    function ns.iterateTargets()
        return next, counted, nil
    end

    FindExclusionAuraByID = function( unit, spellID, invert )
        local result
        if spellID < 0 then
            result = FindUnitDebuffByID( unit, -1 * spellID ) ~= nil
        else
            result = FindUnitBuffByID( unit, spellID ) ~= nil
        end
        return invert and ( not result ) or result
    end

    -- L675: in an instance with the plate CVars off, a nameplate-counting spec counts its target only; say so once
    -- each time that starts (the Warnings page text stays English, as every Hekili:Error)
    local PLATES_OFF = "Enemy nameplates are off, so in this instance Hekili Forever counts only your target. "
        .. "Turn on Show Enemy Nameplates and Show All Nameplates."
    local platesOffShown = false

    -- New Nameplate Proximity System
    function ns.getNumberTargets( forceUpdate )
        if not forceUpdate then
            return lastCount, lastStationary, unheldCount
        end

        local debugging = Hekili.ActiveDebug
        local details = nil
        local showNPs = GetCVar( "nameplateShowEnemies" ) == "1" and GetCVar( "nameplateShowAll" ) == "1"

        wipe( counted )

        local count, stationary = 0, 0
        -- T1: a plate counted as the target; a target compare answered secret; token plates counted (the hold's mode)
        local targetSeen, unknown, tokenMode = false, false, false
        if debugging then details = format( "Nameplates are %s.", showNPs and "enabled" or "disabled" ) end

        local spec = state.spec.id
        spec = spec and rawget( Hekili.Engine.settings.specs, spec )

        local inRaid = IsInRaid()
        local inGroup = GetNumGroupMembers() > 0

        local FriendCheck = inRaid and UnitInRaid or UnitInParty

        local platesOff = not showNPs and spec and spec.nameplates and IsInInstance() and true or false
        if platesOff and not platesOffShown then
            Hekili:Notify( L["Enemy nameplates are off, so in this instance Hekili Forever counts only your target. "
                .. "Turn on Show Enemy Nameplates and Show All Nameplates."], 10 )
            Hekili:Error( PLATES_OFF )
        end
        platesOffShown = platesOff

        local checkPets = showNPs and spec and spec.petbased and Hekili:PetBasedTargetDetectionIsReady()

        local checkPlates = showNPs and spec and spec.nameplates and ( spec.nameplateRange or class.specs[ state.spec.id ].nameplateRange or 10 )

        if spec then
            if checkPets or checkPlates then
                for unit, guid in pairs( npGUIDs ) do
                    local npcid = tonumber( guid:match( "(%d+)-%x-$" ) or 0 )

                    if UnitExists( unit ) and not UnitIsDead( unit ) and UnitCanAttack( "player", unit ) and UnitInPhase( unit ) and ( UnitHealth( unit ) > 1 or TargetDummies[ npcid ] ) and ( not inGroup or not FriendCheck( unit ) ) and ( UnitIsPVP( "player" ) or not UnitIsPlayer( unit ) ) then
                        local isT = UnitIsUnit( unit, "target" ) -- nil: secret (an identity turned secret since ADDED)
                        local excluded = not isT
                        if isT then targetSeen = true elseif isT == nil then unknown = true end
                        local _, range = nil, -1

                        if debugging then details = format( "%s\n - Checking nameplate list for %s [ %s ] %s.", details, unit, guid, UnitName( unit ) or "Unknown" ) end

                        if excluded then
                            if requiredForInclusion[ npcid ] then
                                excluded = not FindExclusionAuraByID( unit, requiredForInclusion[ npcid ] )
                            else
                                excluded = enemyExclusions[ npcid ]
                            end

                            -- If our table has a number, unit is ruled out based on aura.
                            local invert = false

                            if type( excluded ) == "table" then
                                invert = excluded[ 2 ]
                                excluded = excluded[ 1 ]
                            end

                            if excluded and type( excluded ) == "number" then
                                excluded = FindExclusionAuraByID( unit, excluded, invert )

                                if debugging and excluded then
                                    details = format( "%s\n    - Excluded by %s aura.", details, ( invert and "missing" or "present" ) )
                                end
                            end

                            if not excluded and checkPets then
                                excluded = not Hekili:TargetIsNearPet( unit )

                                if debugging and excluded then
                                    details = format( "%s\n    - Excluded by pet range.", details )
                                end
                            end
                            -- FIXME It looks like some kind of resolution/backup plan is needed for range checking (note to self: see Targets.lua line 436)
                            -- https://github.com/Hekili/hekili/issues/4845
                            if not excluded and checkPlates then
                                local _, maxR = RC:GetRange( unit )
                                excluded = maxR ~= nil and maxR > checkPlates

                                if debugging and excluded then
                                    details = format( "%s\n    - Excluded by range (%d > %d).", details, maxR, checkPlates )
                                end

                                -- caster range (L644): past the near band a plate counts only while plainly in combat
                                if not excluded and checkPlates > NEAR_YD and ( maxR == nil or maxR > NEAR_YD ) then
                                    excluded = plain( UnitAffectingCombat( unit ) ) ~= true

                                    if debugging and excluded then
                                        details = format( "%s\n    - Excluded: not in combat beyond %d yd.", details, NEAR_YD )
                                    end
                                end
                            end

                            if not excluded and showNPs and spec.damageOnScreen and not npUnits[ guid ] then
                                excluded = true
                                if debugging then details = format( "%s\n    - Excluded by on-screen nameplate requirement.", details ) end
                            end
                        end

                        if not excluded then
                            local rate, n = Hekili:GetTTD( unit )
                            count = count + 1
                            counted[ guid ] = true

                            local moving = GetUnitSpeed( unit ) > 0

                            if not moving then
                                stationary = stationary + 1
                            end

                            if debugging then details = format( "%s\n    %-12s - %2d - %s - %.2f - %d - %s %s\n", details, unit, range or -1, guid, rate or -1, n or -1, unit and UnitName( unit ) or "Unknown", ( moving and "(moving)" or "" ) ) end
                        end
                    end

                    counted[ guid ] = counted[ guid ] or false
                end

                -- T1: the plates with no GUID (the Map restriction), by the reads measured plain on plate tokens in a
                -- dungeon in combat (UnitExists, UnitCanAttack, the target compare); every other read is unknown when
                -- secret and never excludes. Deliberately absent: UnitHealth (its row answers 0 for a secret UnitIsDead
                -- and would drop every plate), UnitInPhase (identity, a constant under Map), the npcid exclusions (no
                -- GUID), GetUnitSpeed (0 for any other unit: stationary), time to die, and `counted` (GUID-keyed).
                for unit in pairs( npTokens ) do
                    tokenMode = true
                    if plain( UnitExists( unit ) ) and plain( UnitCanAttack( "player", unit ) ) and plain( UnitIsDead( unit ) ) ~= true
                        and not ( inGroup and plain( FriendCheck( unit ) ) )
                        and ( plain( UnitIsPVP( "player" ) ) or not plain( UnitIsPlayer( unit ) ) ) then
                        local isT = UnitIsUnit( "target", unit ) -- true / false / nil (secret); the measured order
                        if isT == true then targetSeen = true elseif isT == nil then unknown = true end

                        local excluded = false
                        if isT ~= true and checkPets then excluded = plain( Hekili:TargetIsNearPet( unit ) ) == false end
                        if isT ~= true and not excluded and checkPlates then
                            local _, maxR = RC:GetRange( unit ) -- nil: unknown, kept
                            excluded = maxR ~= nil and maxR > checkPlates
                            -- caster range (L644): past the near band a plate counts only while plainly in combat
                            -- (UnitAffectingCombat on plates plain under forced Map: owner 2026-11-12, 109/120 ticks)
                            if not excluded and checkPlates > NEAR_YD and ( maxR == nil or maxR > NEAR_YD ) then
                                excluded = plain( UnitAffectingCombat( unit ) ) ~= true
                            end
                        end

                        if not excluded then
                            count = count + 1
                            stationary = stationary + 1
                        end

                        if debugging then details = format( "%s\n    %-12s - token - %s%s", details, unit, isT == nil and "S" or isT and "T" or "-", excluded and " (excluded)" or "" ) end
                    end
                end

                for _, unit in ipairs( unitIDs ) do
                    local guid = UnitGUID( unit )

                    if guid and counted[ guid ] == nil then
                        local npcid = tonumber( guid:match( "(%d+)-%x-$" ) or 0 )

                        if UnitExists( unit ) and not UnitIsDead( unit ) and UnitCanAttack( "player", unit ) and UnitAffectingCombat( unit ) and UnitInPhase( unit ) and ( UnitHealth( unit ) > 1 or TargetDummies[ npcid ] ) and ( not inGroup or not FriendCheck( unit ) ) and ( UnitIsPVP( "player" ) or not UnitIsPlayer( unit ) ) then
                            local excluded = not UnitIsUnit( unit, "target" )

                            local _, range = nil, -1

                            if debugging then details = format( "%s\n - Checking %s [ %s ] %s.", details, unit, guid, UnitName( unit ) or "Unknown" ) end

                            if excluded then
                                excluded = enemyExclusions[ npcid ]

                                -- If our table has a number, unit is ruled out only if the buff is present.
                                if excluded and type( excluded ) == "number" then
                                    excluded = FindExclusionAuraByID( unit, excluded )

                                    if debugging and excluded then
                                        details = format( "%s\n    - Excluded by aura.", details )
                                    end
                                end

                                if not excluded and checkPets then
                                    excluded = not Hekili:TargetIsNearPet( unit )

                                    if debugging and excluded then
                                        details = format( "%s\n    - Excluded by pet range.", details )
                                    end
                                end

                                if not excluded and checkPlates then
                                    local _, maxR = RC:GetRange( unit )
                                    excluded = maxR ~= nil and maxR > checkPlates

                                    if debugging and excluded then
                                        details = format( "%s\n    - Excluded by range (%d > %d).", details, maxR, checkPlates )
                                    end
                                end

                                if not excluded and spec.damageOnScreen and showNPs and not npUnits[ guid ] then
                                    excluded = true
                                    if debugging then details = format( "%s\n    - Excluded by on-screen nameplate requirement.", details ) end
                                end
                            end

                            if not excluded then
                                local rate, n = Hekili:GetTTD(unit)
                                count = count + 1
                                counted[ guid ] = true

                                local moving = GetUnitSpeed( unit ) > 0

                                if not moving then
                                    stationary = stationary + 1
                                end

                                if debugging then details = format( "%s\n    %-12s - %2d - %s - %.2f - %d - %s %s\n", details, unit, range or -1, guid, rate or -1, n or -1, unit and UnitName( unit ) or "Unknown", ( moving and "(moving)" or "" ) ) end
                            end

                            counted[ guid ] = counted[ guid ] or false
                        end
                    end
                end
            end
        end

        if not spec or spec.damage or not checkPets and not checkPlates then
            local db = spec and ( spec.myTargetsOnly and myTargets or targets ) or targets

            for guid, seen in pairs( db ) do
                if counted[ guid ] == nil then
                    local npcid = guid:match( "(%d+)-%x-$" ) or 0
                    npcid = tonumber( npcid )

                    local unit = Hekili:GetUnitByGUID( guid ) or UnitTokenFromGUID( guid )
                    local excluded = false

                    if unit and not UnitIsUnit( unit, "target" ) then
                        excluded = enemyExclusions[ npcid ]

                        if debugging then details = format( "%s\n - Checking %s [ %s ] #%s.", details, unit, guid, UnitName( unit ) or "Unknown" ) end

                        -- If our table has a number, unit is ruled out only if the buff is present.
                        if excluded and type( excluded ) == "number" then
                            excluded = FindExclusionAuraByID( unit, excluded )

                            if debugging and excluded then
                                details = format( "%s\n    - Excluded by aura.", details )
                            end
                        end

                        if not excluded and inGroup and FriendCheck( unit ) then
                            excluded = true
                            if debugging then details = format( "%s\n    - Excluded by friend check.", details ) end
                        end

                        if not excluded and checkPets then
                            excluded = not Hekili:TargetIsNearPet( unit )

                            if debugging and excluded then
                                details = format( "%s\n    - Excluded by pet range.", details )
                            end
                        end
                    end

                    if not excluded and spec.damageOnScreen and showNPs and not npUnits[ guid ] then
                        excluded = true
                        if debugging then details = format( "%s\n    - Excluded by on-screen nameplate requirement.", details ) end
                    end

                    if not excluded then
                        count = count + 1
                        counted[ guid ] = true

                        local moving = unit and GetUnitSpeed( unit ) > 0

                        if not moving then
                            stationary = stationary + 1
                        end

                        if debugging then details = format("%s\n    %-12s - %s %s\n", details, "dmg", guid, ( moving and "(moving)" or "" ) ) end
                    else
                        counted[ guid ] = false
                    end
                end
            end
        end

        local targetGUID = UnitGUID( "target" )
        if targetGUID then
            if not targetSeen and counted[ targetGUID ] == nil and UnitExists( "target" ) and not UnitIsDead( "target" ) and UnitCanAttack( "player", "target" ) and UnitInPhase( "target" ) and ( UnitIsPVP( "player" ) or not UnitIsPlayer( "target" ) ) then
                count = count + 1
                counted[ targetGUID ] = true

                local moving = GetUnitSpeed( "target" ) > 0

                if not moving then
                    stationary = stationary + 1
                end

                if debugging then details = format("%s\n    %-12s - %2d - %s %s\n", details, "target", 0, targetGUID, ( moving and "(moving)" or "" ) ) end
            else
                counted[ targetGUID ] = false
            end
        elseif plain( UnitExists( "target" ) ) then
            -- T1: the target's identity is secret (Map). Counted unless a plate was it, or a secret compare may have
            -- made it one of the counted plates.
            if not targetSeen and ( not unknown or count == 0 ) and plain( UnitCanAttack( "player", "target" ) )
                and plain( UnitIsDead( "target" ) ) ~= true and ( plain( UnitIsPVP( "player" ) ) or not plain( UnitIsPlayer( "target" ) ) ) then
                count = count + 1
                stationary = stationary + 1
                if debugging then details = format( "%s\n    %-12s - token", details, "target" ) end
            end
        end

        count = max( 1, count )

        -- T1, the owner's no-jitter rule: with token plates, a fall publishes on the next forced update if it holds
        -- (0.1-0.5 s later); a rise at once. The GUID and damage paths are untouched.
        unheldCount = count
        -- B8 I2: one or several follows a change that held one update; unheld, so a fall held below waits no second one
        if ( count > 1 ) == sawSeveral then several = sawSeveral end
        sawSeveral = count > 1
        if tokenMode and count < lastCount and not heldLow then
            heldLow = true
            count, stationary = lastCount, lastStationary
        else
            heldLow = false
        end

        if count ~= lastCount or stationary ~= lastStationary then
            lastCount = count
            lastStationary = stationary
            ns.callHook( "TARGET_COUNT_CHANGED" )
        end

        if details then
            Hekili.TargetDebug = details
        end

        return count, stationary
    end
end

function Hekili:GetNumTargets( forceUpdate )
    return ns.getNumberTargets( forceUpdate )
end


function ns.dumpNameplateInfo()
    return counted
end


function ns.updateTarget( id, time, mine, spellID )
    local spec = rawget( Hekili.Engine.settings.specs, state.spec.id )
    if not spec or not spec.damage then return end

    id, time, mine, spellID = ns.callHook( "filter_target", id, time, mine, spellID )

    if id == nil or id == state.GUID then
        return
    end

    if time then
        if not targets[id] then
            targetCount = targetCount + 1
            targets[id] = time
            ns.updatedTargetCount = true
        else
            targets[id] = time
        end

        if mine then
            if not myTargets[id] then
                myTargetCount = myTargetCount + 1
                myTargets[id] = time
                ns.updatedTargetCount = true
            else
                myTargets[id] = time
            end
        end
    else
        if targets[id] then
            targetCount = max( 0, targetCount - 1 )
            targets[id] = nil
        end

        if myTargets[id] then
            myTargetCount = max( 0, myTargetCount - 1 )
            myTargets[id] = nil
        end

        ns.updatedTargetCount = true
    end
end

ns.reportTargets = function()
    for k, v in pairs(targets) do
        Hekili:Print("Saw " .. k .. " exactly " .. GetTime() - v .. " seconds ago.") -- l10n: verbatim
    end
end

ns.numTargets = function()
    return targetCount > 0 and targetCount or 1
end
ns.numMyTargets = function()
    return myTargetCount > 0 and myTargetCount or 1
end
ns.isTarget = function(id)
    return targets[id] ~= nil
end
ns.isMyTarget = function(id)
    return myTargets[id] ~= nil
end

-- MINIONS
local minions = {}

ns.updateMinion = function(id, time)
    minions[id] = time
end

ns.isSummoned = function(id)
    return minions[id] ~= nil
end

ns.isMinion = function(id)
    return minions[id] ~= nil or UnitGUID("pet") == id
end

function Hekili:HasMinionID(id)
    for k, v in pairs(minions) do
        local npcID = tonumber(k:match("%-(%d+)%-[0-9A-F]+$"))

        if npcID == id and v > state.now then
            return true, v
        end
    end
end

function Hekili:DumpMinions()
    local o = ""

    for k, v in orderedPairs(minions) do
        o = o .. k .. " " .. tostring(v) .. "\n"
    end

    return o
end

local debuffs = {}
local debuffCount = {}
local debuffMods = {}

function ns.saveDebuffModifier( id, val )
    debuffMods[ id ] = val
end

ns.wipeDebuffs = function()
    for k, _ in pairs(debuffs) do
        table.wipe(debuffs[k])
        debuffCount[k] = 0
    end
end

ns.actorHasDebuff = function( target, spell )
    return ( debuffs[ spell ] and debuffs[ spell ][ target ] ~= nil ) or false
end

ns.trackDebuff = function( spell, target, time, application, snapshotHaste )
    debuffs[spell] = debuffs[spell] or {}
    debuffCount[spell] = debuffCount[spell] or 0

    if not time then
        if debuffs[spell][target] then
            -- Remove it.
            debuffs[spell][target] = nil
            debuffCount[spell] = max( 0, debuffCount[spell] - 1 )
        end
    else
        if not debuffs[spell][target] then
            debuffs[spell][target] = {}
            debuffCount[spell] = debuffCount[spell] + 1
        end

        local debuff = debuffs[spell][target]

        debuff.last_seen = time
        debuff.applied = debuff.applied or time

        local model = class.auras[ spell ]

        if model and snapshotHaste then
            debuff.haste = 100 / ( 100 + GetHaste() )
            debuff.next_tick = time + ( model.base_tick_time or model.tick_time ) * debuff.haste
        else
            debuff.haste = -1
            debuff.next_tick = time + ( model.base_tick_time or model.tick_time or 3 )
        end

        if application then
            debuff.pmod = debuffMods[spell]
        else
            debuff.pmod = debuff.pmod or 1
        end
    end
end

ns.GetDebuffLastTick = function( spell, target )
    local aura = debuffs[ spell ] and debuffs[ spell ][ target ]
    if not aura then return 0 end
    return aura.last_seen or 0
end

ns.GetDebuffNextTick = function( spell, target )
    local aura = debuffs[ spell ] and debuffs[ spell ][ target ]
    if not aura then return 0 end
    if ( aura.last_seen or 0 ) == 0 then return 0 end

    local model = class.auras[ spell ]
    return aura.next_tick or ( aura.last_seen + ( model.tick_time or 3 ) )
end

ns.GetDebuffHaste = function( spell, target )
    local aura = debuffs[ spell ] and debuffs[ spell ][ target ]
    if not aura then return 1 end
    return aura.haste or state.haste or 1
end

ns.GetDebuffApplicationTime = function( spell, target )
    if not debuffCount[ spell ] or debuffCount[ spell ] == 0 then return 0 end
    return debuffs[ spell ] and debuffs[ spell ][ target ] and ( debuffs[ spell ][ target ].applied or debuffs[ spell ][ target ].last_seen ) or 0
end


function ns.getModifier( id, target )
    local debuff = debuffs[ id ]
    if not debuff then
        return 1
    end

    local app = debuff[target]
    if not app then
        return 1
    end

    return app.pmod or 1
end

ns.numDebuffs = function(spell)
    return debuffCount[spell] or 0
end

ns.compositeDebuffCount = function( ... )
    local n = 0

    for i = 1, select("#", ...) do
        local debuff = select( i, ... )
        debuff = class.auras[ debuff ] and class.auras[ debuff ].id
        debuff = debuff and debuffs[ debuff ]

        if debuff then
            for unit in pairs(debuff) do
                n = n + 1
            end
        end
    end

    return n
end

ns.conditionalDebuffCount = function(req1, req2, req3, ...)
    local n = 0

    req1 = class.auras[req1] and class.auras[req1].id
    req2 = class.auras[req2] and class.auras[req2].id
    req3 = class.auras[req3] and class.auras[req3].id

    for i = 1, select("#", ...) do
        local debuff = select(i, ...)
        debuff = class.auras[debuff] and class.auras[debuff].id
        debuff = debuff and debuffs[debuff]

        if debuff then
            for unit in pairs(debuff) do
                if (req1 and debuffs[req1] and debuffs[req1][unit]) or (req2 and debuffs[req2] and debuffs[req2][unit]) or (req3 and debuffs[req3] and debuffs[req3][unit]) then
                    n = n + 1
                end
            end
        end
    end

    return n
end

do
    local counted = {}

    -- Useful for "count number of enemies with at least one of these debuffs applied".
    -- i.e., poisoned_enemies for Assassination Rogue.

    ns.countUnitsWithDebuffs = function( ... )
        wipe( counted )

        local n = 0

        for i = 1, select("#", ...) do
            local debuff = select( i, ... )
            debuff = class.auras[ debuff ] and class.auras[ debuff ].id
            debuff = debuff and debuffs[ debuff ]

            if debuff then
                for unit in pairs( debuff ) do
                    if not counted[ unit ] then
                        n = n + 1
                        counted[ unit ] = true
                    end
                end
            end
        end

        return n
    end
end

ns.isWatchedDebuff = function(spell)
    return debuffs[spell] ~= nil
end

ns.eliminateUnit = function( id, force )
    ns.updateMinion(id)
    ns.updateTarget(id)

    if force then
        for k, v in pairs( debuffs ) do
            if v[ id ] then
                ns.trackDebuff( k, id )
            end
        end
    end

    ns.callHook( "UNIT_ELIMINATED", id )
end


do
    -- Incoming damage and healing as ring buffers of { time, amount } (two parallel arrays each), summed on read over the
    -- entries newer than GetTime() - seconds: no table, closure or timer per hit. RING entries a kind: the newest RING
    -- hits are kept, so past RING hits of one kind in 10 s the 10 s sums drop the oldest (undercount).
    local RING = 128
    local NEVER = -math.huge

    local function newRing()
        local r = { time = {}, amount = {}, head = 0 }
        for i = 1, RING do r.time[ i ], r.amount[ i ] = NEVER, 0 end
        return r
    end

    local physical, magical, healing = newRing(), newRing(), newRing()

    local function store( r, amount )
        local h = r.head % RING + 1
        r.head = h
        r.time[ h ], r.amount[ h ] = GetTime(), amount
    end

    -- The sum of the entries newer than `seconds` ago, newest first (times only grow, so stop at the first older one).
    local function sum( r, seconds )
        local cutoff = GetTime() - seconds
        local times, amounts, h = r.time, r.amount, r.head
        local total = 0
        for n = 0, RING - 1 do
            local i = ( h - n - 1 ) % RING + 1
            if times[ i ] <= cutoff then break end
            total = total + amounts[ i ]
        end
        return total
    end

    local function window( seconds, isPhysical )
        if isPhysical == nil then return sum( physical, seconds ) + sum( magical, seconds ) end
        return sum( isPhysical and physical or magical, seconds )
    end

    -- Upstream's 1 s / 5 s / 10 s buckets and its interpolation between them for any other window.
    local function interpolate( f, seconds, arg )
        if seconds == 1 or seconds == 5 or seconds == 10 then return f( seconds, arg ) end

        if seconds < 1 then
            return f( 1, arg ) * ( seconds / 1 )
        end

        if seconds < 5 then
            local d1 = f( 1, arg )
            return d1 + ( f( 5, arg ) - d1 ) * ( seconds - 1 ) / 5
        end

        if seconds < 10 then
            local d5 = f( 5, arg )
            return d5 + ( f( 10, arg ) - d5 ) * ( seconds - 5 ) / 10
        end

        return f( 10, arg ) * seconds / 10
    end

    ns.storeDamage = function( _, dam, isPhysical )
        if dam and dam > 0 then
            store( isPhysical and physical or magical, dam )
        end
    end

    ns.damageInLast = function( seconds, isPhysical )
        return interpolate( window, seconds, isPhysical )
    end

    ns.storeHealing = function( _, amount )
        if amount and amount > 0 then
            store( healing, amount )
        end
    end

    local function healed( seconds )
        return sum( healing, seconds )
    end

    ns.healingInLast = function( seconds )
        return interpolate( healed, seconds )
    end
end


-- Auditor should clean things up for us.
do
    ns.Audit = function( special )
        -- Don't audit while recommendations are being generated.
        if ns.EngineFrame:IsThreadActive() then
            return
        end

        if special == "combatExit" and InCombatLockdown() then
            special = nil
        end

        if not special and not Hekili.Engine.settings.enabled or not Hekili:IsValidSpec() then
            return
        end

        Hekili:ExpireTTDs()

        local now = GetTime()
        local spec = state.spec.id and rawget( Hekili.Engine.settings.specs, state.spec.id )
        local grace = spec and spec.damageExpiration or 6

        for whom, when in pairs( targets ) do
            if now - when > grace then
                ns.eliminateUnit( whom )
            end
        end

        for aura, targets in pairs( debuffs ) do
            local a = class.auras[ aura ]
            local window = a and a.duration or grace
            local friendly = a and ( a.friendly or a.dot == "buff" ) or false

            for unit, entry in pairs( targets ) do
                if now - entry.last_seen > window then
                    ns.trackDebuff( aura, unit )
                elseif special == "combatExit" and not friendly then
                    ns.trackDebuff( aura, unit )
                end
            end
        end
    end

    Hekili.AuditTimer = C_Timer.NewTicker( 1, ns.Audit )
end
Hekili:ProfileCPU( "Audit", ns.Audit )


local IsAddOnLoaded, LoadAddOn = C_AddOns.IsAddOnLoaded, C_AddOns.LoadAddOn

function Hekili:DumpDotInfo( aura )
    if not IsAddOnLoaded( "Blizzard_DebugTools" ) then
        LoadAddOn( "Blizzard_DebugTools" )
    end

    aura = aura and class.auras[ aura ] and class.auras[ aura ].id or aura

    Hekili:Print( "Current DoT Information at " .. GetTime() .. ( aura and ( " for " .. aura ) or "" ) .. ":" ) -- l10n: verbatim
    DevTools_Dump( aura and debuffs[ aura ] or debuffs )
end

do
    -- Forever: "unknown", far beyond any fight (State.lua's time_to_die treats 3600 as unknown too): the answer for a
    -- time to die only the old GUID tracker could give (never fed on Forever: target health is secret; removed, L1703),
    -- and for the target's while the library has none.
    local FOREVER = 3600

    -- Forever (lane B8, owner L1676): the target's time to die from LibTimeToDie, called directly, and the execute-line
    -- hints to it (docs/dev/architecture.md, "Time to die"). A missed LibStub lookup is repeated: the library may load late.
    local TTD_MAJOR, TTD_OWNER = "LibTimeToDie-1.0", "Hekili"
    local TTD_RETRY = 1 -- seconds: between refused Tracks (each allocates)
    local ttdLib, ttdTrack -- the library once found; the target's handle
    local ttdRetryAt = 0 -- no Track before this

    local function ttdRelease()
        if ttdTrack then
            ttdTrack:Release()
            ttdTrack = nil
        end
    end

    -- Hints: read out of combat only (UnitClass and roles on group tokens probed plain out of combat, L1658).
    local UnitClass, UnitGroupRolesAssigned = Facade.UnitClass, Facade.UnitGroupRolesAssigned
    local classLines = ns.ttdLines -- [class token] = pct (shared content; Engine/Schema/Shared.lua)
    local hintsDirty = true -- the lines are to be sent at the next chance out of combat
    local sentBelow -- the line sent (nil: none)

    -- The player's own line from its pack (nil: none active), and whether the pack declares any.
    local function ownLine()
        local best, declared = nil, false
        for key, a in pairs( class.abilities ) do
            if type( key ) == "string" and type( a ) == "table" then
                local g, d = rawget( a, "healthGate" ), rawget( a, "ttdBelow" )
                if type( g ) == "number" then
                    declared = true
                    local v = floor( 100 * g + 0.5 )
                    if state:IsKnown( key ) and ( not best or v > best ) then best = v end
                end
                if type( d ) == "table" and type( d.pct ) == "number" then
                    declared = true
                    local t = d.talent and rawget( state.talent, d.talent )
                    if ( not d.talent or t and ( t.rank or 0 ) > 0 ) and ( not best or d.pct > best ) then best = d.pct end
                end
            end
        end
        return best, declared
    end

    local function groupLine( best, token )
        if UnitExists( token ) and UnitIsUnit( token, "player" ) ~= true and UnitGroupRolesAssigned( token ) ~= "TANK" then
            local _, c = UnitClass( token )
            local v = c and classLines[ c ]
            if v and ( not best or v > best ) then return v end
        end
        return best
    end

    local function sendHints()
        if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED sends them
        ttdLib = ttdLib or LibStub( TTD_MAJOR, true )
        if not ttdLib then return end
        hintsDirty = false
        local best, declared = ownLine()
        if not declared then
            local _, c = UnitClass( "player" )
            best = c and classLines[ c ]
        end
        if IsInRaid() then
            for i = 1, 40 do best = groupLine( best, "raid" .. i ) end
        elseif GetNumGroupMembers() > 0 then
            for i = 1, 4 do best = groupLine( best, "party" .. i ) end
        end
        if best ~= sentBelow then
            ttdLib:HintBelow( TTD_OWNER, best )
            sentBelow = best
        end
    end

    -- Activation.lua, after the talent ranks are read (login, a spec or talent change).
    function ns.TtdHintsChanged()
        hintsDirty = true
        sendHints()
    end

    RegisterEvent( "GROUP_ROSTER_UPDATE", ns.TtdHintsChanged ) -- its own registration: core has no handler of it

    -- Events.lua's PLAYER_REGEN_ENABLED handler.
    function ns.TtdCombatEnded()
        if hintsDirty then sendHints() end
    end

    -- The snapshot's time-to-die line (English only; Hekili:GetTTDInfo). Allocates.
    local function ttdLine()
        local est, lo, hi, s, why
        if ttdTrack then est, lo, hi, s, why = ttdTrack:Get() end
        return format( "time to die: %s %s est %s lo %s hi %s; hints: below %s", s or "not tracked", tostring( why ), tostring( est ), tostring( lo ), tostring( hi ), tostring( sentBelow or "none" ) ) -- l10n: verbatim
    end

    -- The target's live estimate in seconds or nil. Allocates nothing once tracked or refused.
    local function targetTTD()
        if Hekili.bandOff then
            ttdRelease()
            return nil
        end
        if not ttdTrack then
            ttdLib = ttdLib or LibStub( TTD_MAJOR, true )
            if not ttdLib then return nil end
            local now = GetTime()
            if now < ttdRetryAt then return nil end
            ttdTrack = ttdLib:Track( TTD_OWNER, "target" )
            if not ttdTrack then
                ttdRetryAt = now + TTD_RETRY
                return nil
            end
            if hintsDirty then sendHints() end
        end
        local est, _, _, s, why = ttdTrack:Get()
        -- shortcut: a seed answer reads unknown (owner L1742). LibTimeToDie minor 4 seeds only after 1.5 s of loss, but a
        -- burst then a far slower fall still seeds at about half the true time; vendor-libs kept the rule on its fight
        -- runs (removing it raised the swap set's flicker, L1736). Drop it when a library minor or a re-run shows no cost.
        return s == "live" and why ~= "seed" and est or nil
    end

    -- targetTTD's answer when the target is plainly attackable, else nil. The library first, so with none (or
    -- Hekili.bandOff) no client call is made.
    local function hostileTargetTTD()
        local est = targetTTD()
        if est and plain( UnitExists( "target" ) ) and plain( UnitCanAttack( "player", "target" ) ) then
            return est
        end
    end

    -- The longest (and the shortest) time to die among the enemies (owner L1694): the target's with one enemy, unknown
    -- with several (only the target is tracked; no scan here: that scan calls GetTTD itself). The core keeps nothing
    -- across a target change: the library's answer is about whatever the target is now (a mob targeted again resumes
    -- from its plate, LibTimeToDie minor 5; a new one reads nothing before 1.5 s of its loss).
    local function onlyEnemyTTD()
        if several then return nil end
        return hostileTargetTTD()
    end

    -- Forever: the getters below keep the answers of the old GUID tracker's empty table (L1703); only the target's time
    -- is known, from the library.
    function Hekili:GetDeathClockByGUID( guid )
        if state.target.is_dummy then return 180 end
        return FOREVER
    end

    function Hekili:GetTTD( unit, isGUID )
        if state.target.is_dummy then return 180 end

        if unit == "target" and not isGUID then
            return hostileTargetTTD() or FOREVER
        end

        -- Forever: unknown for every other unit, a grey one too, as fight_remains (wowsims's remainingTime has no trivial case)
        return FOREVER
    end

    function Hekili:GetTimeToPct( unit, percent )
        if percent >= 1 then
            percent = percent / 100
        end

        if unit == "target" then
            -- The library answers the time to 0 only: scaled by the share of the health left above the percent, h the
            -- facade's target health (the belief's, 0-100), on the estimate's own rate.
            local est = hostileTargetTTD()
            if not est then return FOREVER end
            local hm = UnitHealthMax( "target" )
            local h = hm > 0 and 100 * UnitHealth( "target" ) / hm or 0
            local p = 100 * percent
            if h <= p then return 0 end
            return est * ( h - p ) / h
        end

        return FOREVER
    end

    -- Forever: no caller. shortcut: a GUID is secret in dungeons, so no GUID is matched to the tracked target; compare
    -- with the target's GUID (plain only) if a caller appears.
    function Hekili:GetTimeToPctByGUID( guid, percent )
        if percent >= 1 then
            percent = percent / 100
        end

        return percent * FOREVER
    end

    function Hekili:GetGreatestTTD()
        if state.target.is_dummy then return 180 end

        -- Forever: fight_remains (longest_ttd) is the only enemy's estimate.
        -- shortcut: only the target is tracked, so with more than one enemy the longest is unknown (FOREVER); track
        -- the others when LibTimeToDie proves their tokens (plates, boss: its version 2).
        return onlyEnemyTTD() or FOREVER
    end

    function Hekili:GetGreatestTimeToPct( percent )
        return FOREVER
    end

    function Hekili:GetLowestTTD()
        if state.target.is_dummy then return 180 end

        return onlyEnemyTTD() or FOREVER -- Forever: the only enemy's estimate, as GetGreatestTTD
    end

    function Hekili:GetNumTTDsWithin( x )
        return 0
    end
    Hekili.GetNumTTDsBefore = Hekili.GetNumTTDsWithin

    function Hekili:GetNumTTDsAfter( x )
        return state.active_enemies -- Forever: no enemy's time is known, so all count as after x
    end

    function Hekili:GetNumTargetsAboveHealthPct( amount, inclusive, minTTD )
        return 0
    end

    function Hekili:GetNumTargetsBelowHealthPct( amount, inclusive, minTTD )
        return 0
    end

    function Hekili:GetAddWaveTTD()
        if state.target.is_dummy then return 180 end

        if not UnitExists( "boss1" ) then
            return self:GetGreatestTTD()
        end

        return 0 -- Forever: no add's time is known
    end

    function Hekili:GetTTDInfo()
        local output = ttdLine() .. "\ntargets:"

        if state.target.is_dummy then
            output = output .. "    Target TTDs overridden; target is a training dummy"
        end

        return output .. "  none"
    end

    function Hekili:ExpireTTDs( all )
        if all then ttdRelease() end -- Forever: the library's track (OnDisable); the next query tracks again
    end
end
