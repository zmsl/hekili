local _, ns = ...
-- Engine/Snapshot.lua: the debug snapshot (restructure plan, Task 5). Engine.Snapshot(isAuto) runs one update with
-- debugging on; SaveDebugSnapshot (from Hekili.lua) and GenerateProfile (from Options.lua) write its report. Moved
-- verbatim: they read the engine's state, which the UI and Options no longer may.
-- Upstream style (in .styluaignore), as moved.
local Facade = ns.Facade
local GetBuffDataByIndex, GetDebuffDataByIndex = Facade.C_UnitAuras.GetBuffDataByIndex, Facade.C_UnitAuras.GetDebuffDataByIndex
local GetFramerate, GetTime, UnitEffectiveLevel, UnitLevel = Facade.GetFramerate, Facade.GetTime, Facade.UnitEffectiveLevel, Facade.UnitLevel
local UnpackAuraData = Facade.AuraUtil.UnpackAuraData

local Hekili = Hekili
local class, state = Hekili.Class, Hekili.State
local debug = ns.debug
local orderedPairs = ns.orderedPairs
local format = string.format
local insert, concat = table.insert, table.concat

--- Runs one update with debugging on, so the displays' reports are saved; `isAuto` (the engine's own call) only when
--- the profile's autoSnapshot is on.
function Hekili.Engine.Snapshot( isAuto )
    if isAuto and not Hekili.Engine.settings.autoSnapshot then
        return
    end

    local first = #ns.snapshots + 1
    Hekili.ManualSnapshot = not isAuto
    Hekili.ActiveDebug = true
    Hekili.Update()
    Hekili.ActiveDebug = false
    Hekili.ManualSnapshot = nil
    ns.NotifySnapshotListeners( first, not not isAuto )

    -- The suspended build's thread would write into the set this snapshot just published; drop it (R1).
    ns.EngineFrame.activeThread = nil
end

local snapshots = ns.snapshots
local hasScreenshotted = false

-- Snapshot listeners: other addons' fn(index, record, isAuto), called once per snapshot after all its records (one per
-- display) are stored. A returned string is appended to each of those records under "## External" (each listener's
-- text capped at EXTERNAL_MAX characters).
local listeners = {}
local EXTERNAL_MAX = 4000

--- Registers `fn(index, record, isAuto)`, called inside pcall once per snapshot, after all its records (one per
--- display) are stored: `index` is the first one's in `Hekili.Snapshots`, `record` that first record (the rest follow
--- it, up to `#Hekili.Snapshots`). A returned string is appended to each of those records' `log` under "## External",
--- truncated at 4000 characters. Registering the same `fn` twice is a no-op.
---@param fn fun(index: integer, record: table, isAuto: boolean): string?
function Hekili:RegisterSnapshotListener( fn )
    assert( type( fn ) == "function", "RegisterSnapshotListener: fn must be a function" )
    for i = 1, #listeners do
        if listeners[ i ] == fn then return end
    end
    listeners[ #listeners + 1 ] = fn
end

--- Removes a listener added by RegisterSnapshotListener; unknown `fn` is a no-op.
function Hekili:UnregisterSnapshotListener( fn )
    for i = #listeners, 1, -1 do
        if listeners[ i ] == fn then table.remove( listeners, i ) end
    end
end

-- Engine.Snapshot's call: the records from `first` on are this snapshot's; none stored, no call.
function ns.NotifySnapshotListeners( first, isAuto )
    local snap = snapshots[ first ]
    if not snap then return end
    local parts
    for i = 1, #listeners do
        local ok, text = pcall( listeners[ i ], first, snap, isAuto )
        if not ok then text = "snapshot listener " .. i .. " failed: " .. tostring( text ) end
        if type( text ) == "string" and text ~= "" then
            parts = parts or {}
            parts[ #parts + 1 ] = text:sub( 1, EXTERNAL_MAX )
        end
    end
    if not parts then return end
    local ext = "\n\n## External\n" .. concat( parts, "\n" )
    for i = first, #snapshots do
        snapshots[ i ].log = snapshots[ i ].log .. ext
    end
end

function Hekili:SaveDebugSnapshot( dispName )
    local snapped = false
    local formatKey = ns.formatKey
    local state = Hekili.State

	for k, v in pairs( debug ) do
		if not dispName or dispName == k then
			for i = #v.log, v.index, -1 do
				v.log[ i ] = nil
			end

            -- Store previous spell data.
            local prevString = "\nprevious_spells:"

            -- Skip over the actions in the "prev" table that were added to computed the next recommended ability in the queue.
            local i, j = ( #state.predictions + 1 ), 1
            local spell = state.prev[i].spell or "no_action"

            if spell == "no_action" then
                prevString = prevString .. "  no history available"
            else
                local numHistory = #state.prev.history
                while i <= numHistory and spell ~= "no_action" do
                    prevString = format( "%s\n   %d - %s", prevString, j, spell )
                    i, j = i + 1, j + 1
                    spell = state.prev[i].spell or "no_action"
                end
            end
            prevString = prevString .. "\n\n"

            insert( v.log, 1, prevString )

            -- Store aura data.
            local auraString = "\n### Auras ###\n"

            local now = GetTime()
            local playerBuffs = {}
            local pbOrder = {}

            local longestKey, longestName = 0, 0

            Facade.AuraUtil.ForEachAura( "player", "HELPFUL", nil, function( aura )
                if aura.isFromPlayerOrPlayerPet then
                    local model = class.auras[ aura.spellId ]
                    local key = model and model.key or formatKey( aura.name )

                    local offset = 0
                    local newKey = key

                    while( playerBuffs[ newKey ] ) do
                        offset = offset + 1
                        newKey = format( "%s_%d", key, offset )
                    end

                    if newKey ~= key then key = newKey end

                    pbOrder[ #pbOrder + 1 ] = key
                    longestKey = max( longestKey, key:len() )
                    longestName = max( longestName, aura.name:len() )

                    playerBuffs[ key ] = {}
                    local elem = playerBuffs[ key ]

                    elem.spellId = aura.spellId
                    elem.key = key
                    elem.name = aura.name

                    elem.count = aura.applications > 0 and aura.applications or 1
                    elem.remains = aura.expirationTime > 0 and ( aura.expirationTime - now ) or 3600

                    local scraped = state.auras.player.buff[ model and model.key or key ]
                    if scraped and scraped.applied > 0 then
                        elem.sCount = scraped.count > 0 and scraped.count or 1
                        elem.sRemains = scraped.expires > 0 and ( scraped.expires - now ) or 3600
                    end
                end
            end, true )

            for token, caught in pairs( state.auras.player.buff ) do
                if not playerBuffs[ token ] and caught.expires > 0 then
                    playerBuffs[ token ] = {
                        spellId = caught.id,
                        key = caught.key,
                        name = "",

                        count = 0,
                        remains = 0,

                        sCount = caught.count > 0 and caught.count or 1,
                        sRemains = caught.expires > 0 and ( caught.expires - now ) or 3600
                    }

                    pbOrder[ #pbOrder + 1 ] = token
                    longestKey = max( longestKey, token:len() )
                end
            end

            sort( pbOrder )


            local playerDebuffs = {}
            local pdOrder = {}

            Facade.AuraUtil.ForEachAura( "player", "HARMFUL", nil, function( aura )
                local model = class.auras[ aura.spellId ]
                local key = model and model.key or formatKey( aura.name )

                local offset = 0
                local newKey = key

                while( playerDebuffs[ newKey ] ) do
                    offset = offset + 1
                    newKey = format( "%s_%d", key, offset )
                end
                if newKey ~= key then key = newKey end

                pdOrder[ #pdOrder + 1 ] = key
                longestKey = max( longestKey, key:len() )
                longestName = max( longestName, aura.name:len() )

                playerDebuffs[ key ] = {}
                local elem = playerDebuffs[ key ]

                elem.spellId = aura.spellId
                elem.key = key
                elem.name = aura.name

                elem.count = aura.applications > 0 and aura.applications or 1
                elem.remains = aura.expirationTime > 0 and ( aura.expirationTime - now ) or 3600

                local scraped = state.auras.player.debuff[ model and model.key or key ]
                if scraped and scraped.applied > 0 then
                    elem.sCount = scraped.count > 0 and scraped.count or 1
                    elem.sRemains = scraped.expires > 0 and ( scraped.expires - now ) or 3600
                end
            end, true )

            for token, caught in pairs( state.auras.player.debuff ) do
                if not playerDebuffs[ token ] and caught.expires > 0 then
                    playerDebuffs[ token ] = {
                        spellId = caught.id,
                        key = caught.key,
                        name = "",

                        count = 0,
                        remains = 0,

                        sCount = caught.count > 0 and caught.count or 1,
                        sRemains = caught.expires > 0 and ( caught.expires - now ) or 3600
                    }

                    pdOrder[ #pdOrder + 1 ] = token
                    longestKey = max( longestKey, token:len() )
                end
            end

            sort( pdOrder )


            local targetBuffs = {}
            local tbOrder = {}

            Facade.AuraUtil.ForEachAura( "target", "HELPFUL", nil, function( aura )
                local model = class.auras[ aura.spellId ]
                local key = model and model.key or formatKey( aura.name )

                local offset = 0
                local newKey = key

                while( targetBuffs[ newKey ] ) do
                    offset = offset + 1
                    newKey = format( "%s_%d", key, offset )
                end
                if newKey ~= key then key = newKey end

                tbOrder[ #tbOrder + 1 ] = key
                longestKey = max( longestKey, key:len() )
                longestName = max( longestName, aura.name:len() )

                targetBuffs[ key ] = {}
                local elem = targetBuffs[ key ]

                elem.spellId = aura.spellId
                elem.key = key
                elem.name = aura.name

                elem.count = aura.applications > 0 and aura.applications or 1
                elem.remains = aura.expirationTime > 0 and ( aura.expirationTime - now ) or 3600

                local scraped = state.auras.target.buff[ model and model.key or key ]
                if scraped and scraped.applied > 0 then
                    elem.sCount = scraped.count > 0 and scraped.count or 1
                    elem.sRemains = scraped.expires > 0 and ( scraped.expires - now ) or 3600
                end
            end, true )

            for token, caught in pairs( state.auras.target.buff ) do
                if not targetBuffs[ token ] and caught.expires > 0 then
                    targetBuffs[ token ] = {
                        spellId = caught.id,
                        key = caught.key,
                        name = "",

                        count = 0,
                        remains = 0,

                        sCount = caught.count > 0 and caught.count or 1,
                        sRemains = caught.expires > 0 and ( caught.expires - now ) or 3600
                    }

                    tbOrder[ #tbOrder + 1 ] = token
                    longestKey = max( longestKey, token:len() )
                end
            end

            sort( tbOrder )


            local targetDebuffs = {}
            local tdOrder = {}

            Facade.AuraUtil.ForEachAura( "target", "HARMFUL", nil, function( aura )
                if aura.isFromPlayerOrPlayerPet then
                    local model = class.auras[ aura.spellId ]
                    local key = model and model.key or formatKey( aura.name )

                    local offset = 0
                    local newKey = key

                    while( targetDebuffs[ newKey ] ) do
                        offset = offset + 1
                        newKey = format( "%s_%d", key, offset )
                    end
                    if newKey ~= key then key = newKey end

                    tdOrder[ #tdOrder + 1 ] = key
                    longestKey = max( longestKey, key:len() )
                    longestName = max( longestName, aura.name:len() )

                    targetDebuffs[ key ] = {}
                    local elem = targetDebuffs[ key ]

                    elem.spellId = aura.spellId
                    elem.key = key
                    elem.name = aura.name

                    elem.count = aura.applications > 0 and aura.applications or 1
                    elem.remains = aura.expirationTime > 0 and ( aura.expirationTime - now ) or 3600

                    local scraped = state.auras.target.debuff[ model and model.key or key ]
                    if scraped and scraped.applied > 0 then
                        elem.sCount = scraped.count > 0 and scraped.count or 1
                        elem.sRemains = scraped.expires > 0 and ( scraped.expires - now ) or 3600
                    end
                end
            end, true )

            for token, caught in pairs( state.auras.target.debuff ) do
                if not targetDebuffs[ token ] and caught.expires > 0 then
                    targetDebuffs[ token ] = {
                        spellId = caught.id,
                        key = caught.key,
                        name = "",

                        count = 0,
                        remains = 0,

                        sCount = caught.count > 0 and caught.count or 1,
                        sRemains = caught.expires > 0 and ( caught.expires - now ) or 3600
                    }

                    tdOrder[ #tdOrder + 1 ] = token
                    longestKey = max( longestKey, token:len() )
                end
            end

            sort( tdOrder )

            local header = "     n  | ID      | Token" .. string.rep( " ", longestKey - 4 ) .. " | Name" .. string.rep( " ", longestName - 4 ) .. " | A. Count | A. Remains | S. Count | S. Remains\n"
                .. "    --- | ------- | " .. string.rep( "-", longestKey + 1 ) .. " | " .. string.rep( "-", longestName ) .. " | -------- | ---------- | -------- | ----------"


            if #pbOrder > 0 then
                auraString = auraString .. "\nplayer_buffs:\n" .. header

                for i, token in ipairs( pbOrder ) do
                    local aura = playerBuffs[ token ]

                    auraString = format( "%s\n     %-2d | %7d | %s%-" .. longestKey .. "s | %-" .. longestName .. "s | %8d | %10.2f | %8d | %10.2f",
                        auraString, i, class.auras[ token ] and class.auras[ token ].id or -1, ( class.auras[ token ] and " " or "*" ), token, aura.name, aura.count, aura.remains, aura.sCount or -1, aura.sRemains or - 1 )
                end

            else
                auraString = auraString .. "\nplayer_buffs: none"
            end

            if #pdOrder > 0 then
                auraString = auraString .. "\n\nplayer_debuffs:\n" .. header

                for i, token in ipairs( pdOrder ) do
                    local aura = playerDebuffs[ token ]

                    auraString = format( "%s\n     %-2d | %7d | %s%-" .. longestKey .. "s | %-" .. longestName .. "s | %8d | %10.2f | %8d | %10.2f",
                        auraString, i, class.auras[ token ] and class.auras[ token ].id or -1, ( class.auras[ token ] and " " or "*" ), token, aura.name, aura.count, aura.remains, aura.sCount or -1, aura.sRemains or - 1 )
                end
            else
                auraString = auraString .. "\n\nplayer_debuffs: none"
            end

            if #tbOrder > 0 then
                auraString = auraString .. "\n\ntarget_buffs:\n" .. header

                for i, token in ipairs( tbOrder ) do
                    local aura = targetBuffs[ token ]
                    local model = class.auras[ token ]

                    auraString = format( "%s\n     %-2d | %7d | %s%-" .. longestKey .. "s | %-" .. longestName .. "s | %8d | %10.2f | %8d | %10.2f",
                        auraString, i, model and model.id or -1, model and " " or "*", token, aura.name, aura.count, aura.remains, aura.sCount or -1, aura.sRemains or - 1 )
                end

            else
                auraString = auraString .. "\n\ntarget_buffs: none"
            end

            if #tdOrder > 0 then
                auraString = auraString .. "\n\ntarget_debuffs:\n" .. header

                for i, token in ipairs( tdOrder ) do
                    local aura = targetDebuffs[ token ]

                    auraString = format( "%s\n     %-2d | %7d | %s%-" .. longestKey .. "s | %-" .. longestName .. "s | %8d | %10.2f | %8d | %10.2f",
                        auraString, i, class.auras[ token ] and class.auras[ token ].id or -1, ( class.auras[ token ] and " " or "*" ), token, aura.name, aura.count, aura.remains, aura.sCount or -1, aura.sRemains or - 1 )
                end

            else
                auraString = auraString .. "\n\ntarget_debuffs: none"
            end


            insert( v.log, 1, auraString )
            insert( v.log, 1, "\n### Targets ###\n\ndetected_targets:  " .. ( Hekili.TargetDebug or "no data" ) )
            insert( v.log, 1, self:GenerateProfile() )


            local performance
            local pInfo = ns.EngineFrame.threadUpdates

            -- TODO: Include # of active displays, number of icons displayed.

            if pInfo then
                performance = string.format( "\n\nPerformance\n"
                    .. "|| Updates || Updates / sec || Avg. Work || Avg. Time || Avg. Frames || Peak Work || Peak Time || Peak Frames || FPS || Work Cap ||\n"
                    .. "|| %7d || %13.2f || %9.2f || %9.2f || %11.2f || %9.2f || %9.2f || %11.2f || %3d || %8.2f ||",
                    pInfo.updates, pInfo.updatesPerSec, pInfo.meanWorkTime, pInfo.meanClockTime, pInfo.meanFrames, pInfo.peakWorkTime, pInfo.peakClockTime, pInfo.peakFrames, GetFramerate() or 0, Hekili.maxFrameTime or 0 )
            end

            if performance then insert( v.log, performance ) end

            local custom = ""

            local pack = Hekili.Engine.settings.packs[ state.system.packName ]
            if not pack.builtIn then
                custom = format( " |cFFFFA700(*%s[%d])|r", state.spec.name, state.spec.id )
            end

            local overview = format( "%s%s; %s|r", state.system.packName, custom, dispName or state.display )
            local out = Hekili.Engine.Output[ dispName or state.display ]

            if out.count == 0 then
                overview = format( "%s - |cFF666666N/A|r", overview )
            end

            for i = 1, out.count do
                local rec = out.recs[ i ]
                overview = format( "%s%s%s|cFFFFD100(%0.2f)|r", overview, ( i == 1 and " - " or ", " ), rec.actionName, rec.time or rec.exact_time or -1 )
            end

            insert( v.log, 1, overview )

            local snap = {
                header = "|cFFFFD100[" .. date( "%H:%M:%S" ) .. "]|r " .. overview,
                log = concat( v.log, "\n" ),
                data = ns.tableCopy( v.log ),
                recs = {}
            }

            insert( snapshots, snap )
            snapped = true
		end
    end

    -- Limit screenshot to once per login.
    if snapped then
        if Hekili.Engine.settings.screenshot and ( not hasScreenshotted or Hekili.ManualSnapshot ) then
            Screenshot()
            hasScreenshotted = true
        end
        return true
    end

    return false
end

Hekili.Snapshots = ns.snapshots


function Hekili:GenerateProfile()
    local s = state

    local spec = s.spec.key
    if spec and s.spec.source then spec = spec .. " (" .. s.spec.source .. ")" end

    local talents

    for k, v in orderedPairs( s.talent ) do
        if v.enabled then
            -- Forever: no `max` on state.talent (its metatable answers the key name); the entry's max rank instead.
            local entry = class.talents[ k ]
            local max = rawget( v, "max" ) or type( entry ) == "table" and entry[ 3 ] or 0
            if talents then talents = format( "%s\n    %s = %d/%d", talents, k, v.rank, max )
            else talents = format( "%s = %d/%d", k, v.rank, max ) end
        end
    end

    local sets
    for k, v in orderedPairs( class.gear ) do
        if s.set_bonus[ k ] > 0 then
            if sets then sets = format( "%s\n    %s = %d", sets, k, s.set_bonus[k] )
            else sets = format( "%s = %d", k, s.set_bonus[k] ) end
        end
    end

    local gear, items
    for k, v in orderedPairs( state.set_bonus ) do
        if type(v) == "number" and v > 0 then
            if type(k) == 'string' then
                if gear then gear = format( "%s\n    %s = %d", gear, k, v )
                else gear = format( "%s = %d", k, v ) end
            elseif type(k) == 'number' then
                if items then items = format( "%s, %d", items, k )
                else items = tostring(k) end
            end
        end
    end

    local settings
    if state.settings.spec then
        for k, v in orderedPairs( state.settings.spec ) do
            if type( v ) ~= "table" then
                if settings then settings = format( "%s\n    %s = %s", settings, k, tostring( v ) )
                else settings = format( "%s = %s", k, tostring( v ) ) end
            end
        end
        for k, v in orderedPairs( state.settings.spec.settings ) do
            if type( v ) ~= "table" then
                if settings then settings = format( "%s\n    %s = %s", settings, k, tostring( v ) )
                else settings = format( "%s = %s", k, tostring( v ) ) end
            end
        end
    end

    local toggles
    for k, v in orderedPairs( Hekili.Engine.settings.toggles ) do
        if type( v ) == "table" and rawget( v, "value" ) ~= nil then
            if toggles then toggles = format( "%s\n    %s = %s %s", toggles, k, tostring( v.value ), ( v.separate and "[separate]" or ( k ~= "cooldowns" and v.override and Hekili.Engine.settings.toggles.cooldowns.value and "[overridden]" ) or "" ) )
            else toggles = format( "%s = %s %s", k, tostring( v.value ), ( v.separate and "[separate]" or ( k ~= "cooldowns" and v.override and Hekili.Engine.settings.toggles.cooldowns.value and "[overridden]" ) or "" ) ) end
        end
    end

    local keybinds = ""
    local bindLength = 1

    for name in pairs( Hekili.KeybindInfo ) do
        if name:len() > bindLength then
            bindLength = name:len()
        end
    end

    for name, data in orderedPairs( Hekili.KeybindInfo ) do
        local action = format( "%-" .. bindLength .. "s =", name )
        local count = 0
        for i = 1, 12 do
            local bar = data.upper[ i ]
            if bar then
                if count > 0 then action = action .. "," end
                action = format( "%s %-4s[%02d]", action, bar, i )
                count = count + 1
            end
        end
        keybinds = keybinds .. "\n    " .. action
    end


    local warnings

    for i, err in ipairs( Hekili.ErrorKeys ) do
        if warnings then warnings = format( "%s\n[#%d] %s", warnings, i, err:gsub( "\n\n", "\n" ) )
        else warnings = format( "[#%d] %s", i, err:gsub( "\n\n", "\n" ) ) end
    end


    return format(
    "Hekili Forever build: %s\n" ..
    "level: %d (%d)\n" ..
    "class: %s\n" ..
    "spec: %s\n\n" ..

    "### Talents ###\n\n" ..
    "In-Game Import: %s\n\n" ..

    "### Gear & Items ###\n\n" ..
    "sets:\n    %s\n\n" ..
    "gear:\n    %s\n\n" ..
    "itemIDs: %s\n\n" ..

    "### Settings ###\n\n" ..
    "Settings:\n    %s\n\n" ..

    "Toggles:\n    %s\n\n" ..

    "Keybinds:%s\n\n" ..

    "### Warnings ###\n\n%s\n",
    self.Version or "no info",
    UnitLevel( 'player' ) or 0, UnitEffectiveLevel( 'player' ) or 0,
    class.file or "NONE",
    spec or "none",
    talents or "none",
    sets or "none",
    gear or "none",
    items or "none",
    settings or "none",
    toggles or "none",
    keybinds or "none",
    warnings or "none"
)

end
