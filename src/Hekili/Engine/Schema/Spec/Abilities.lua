-- Engine/Schema/Spec/Abilities.lua
-- RegisterAbility(ies) for the spec mixin (Engine/Schema/Spec.lua's ns.SpecMixin), with the missable-DoT tracking and the
-- ability function fields that stay raw. Loads before Spec/All.lua, which copies the mixin into spec 0 at load.

local addon, ns = ...
local Facade = ns.Facade
local C_Item, C_Spell, GetTime = Facade.C_Item, Facade.C_Spell, Facade.GetTime
local Hekili = _G[ addon ]
local class = Hekili.Class
local state = Hekili.State
local CommitKey, GetItemInfo = ns.commitKey, ns.CachedGetItemInfo
local GetSpellDescription = C_Spell.GetSpellDescription
local GetSpellTexture = C_Spell.GetSpellTexture
local GetItemSpell = C_Item.GetItemSpell
local GetSpellInfo = C_Spell.GetSpellInfo

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


local methods = {
    -- Content fields beside Hekili's own. `ladder = false`: the ability's usability answers are no rungs of the
    -- belief's cost ladder (Game/State/Families/Resources.lua); without it a short answer is a rung only while its
    -- `usable` holds in the belief's `now` context (a finisher at 0 combo points pins no energy). `missable = true` or
    -- an aura key: a miss leaves that debuff off the target (trackMisses, above). `refundOnAvoid = true` (its resource
    -- meta's share) or a share 0-1: a dodged, parried or missed cast gives back that much of its cost (the belief's
    -- only, Game/State/Families/Now.lua; the sim does not predict avoidance). `onCrit = function() ... end`, beside
    -- `now`: what a critical hit of the cast gives, written with the same verbs when the target's row shows our cast's
    -- own crit (Primal Fury's `gain( 5, "rage" )`); the belief's only, the sim does not predict crits. `onLand`, the
    -- same way: what only a landed hit gives (a mana return), run once the cast's hit is settled as landed, never on an
    -- avoid (aura audit C10). `now_finish`: a channel's `finish` twin in the belief, run when the channel ran to its
    -- end (aura audit C11). `spendBase = true`:
    -- its `spend` (scalar or function) is a fraction of its pool's base power at any magnitude, floored, in both layers
    -- (a percent-of-base cost a stacking aura raises past 100%); without it only a cost between 0 and 1 is a fraction.
    -- Hekili's `form = key` (or a function returning one): the form or stance aura the ability needs (state:IsUsable);
    -- a kit declares that here, never through `buff` or a `usable` body (tests/Forever/forms_spec.lua); `nobuff` stays
    -- upstream's "not while this is up".
    RegisterAbility = function( self, ability, data )
        -- A passive (a spell the spellbook knows, never cast): the belief tracks its known rank; the sim never sees it.
        if data.passive then
            assert( type( data.id ) == "number", "RegisterAbility: passive " .. tostring( ability ) .. " needs a numeric id" )
            ns.TrackPassive( data.id )
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
}

for k, f in pairs( methods ) do ns.SpecMixin[ k ] = f end
