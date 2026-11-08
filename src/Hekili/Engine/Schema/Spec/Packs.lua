-- Engine/Schema/Spec/Packs.lua
-- The built-in packs into the profile: a spec's DefaultPackage, RestoreDefaults (decode, retire, notify) and
-- RestoreDefault. Loads after Spec/All.lua: nothing here runs at load.

local addon, ns = ...
local L = ns.L
local Hekili = _G[ addon ]
local class = Hekili.Class
local insert = table.insert

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
