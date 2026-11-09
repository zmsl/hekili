-- Engine/Schema/Spec/Auras.lua
-- RegisterAura(s) and RegisterPower(s) for the spec mixin (Engine/Schema/Spec.lua's ns.SpecMixin). Loads before
-- Spec/All.lua, which copies the mixin into spec 0 at load.

local addon, ns = ...
local Facade = ns.Facade
local C_Spell = Facade.C_Spell
local Hekili = _G[ addon ]
local class = Hekili.Class
local state = Hekili.State
local CommitKey = ns.commitKey
local GetSpellDescription = C_Spell.GetSpellDescription
local GetSpellTexture = C_Spell.GetSpellTexture
local GetSpellInfo = C_Spell.GetSpellInfo

local methods = {
    -- A content field beside Hekili's own: `overlay = spellID` on a player proc aura (C2). While the player aura walk is
    -- secret or stopped, the belief reads the proc from that spell's overlay glow (Game/State/Sources/Auras.lua, poll
    -- 11): up with no expiry while it glows, down once it stops. A plain walk wins, except that a permanent aura
    -- with `overlay` still goes down while the glow is off.
    -- Also `isStealthed = true` (C5): the player aura follows IsStealthed (Sources/Forms.lua); and `weaponEnchant = slot`
    -- (C4, Enum.WeaponSlot: 0 main hand, 1 off hand) on an id-less pseudo-aura: up while that slot carries an enchant
    -- of any layer but the temporary one (stones and oils); and `enchants = { enchant IDs }` on an id-less aura: up
    -- while either weapon slot carries one of those IDs (the client's enchantID). Both are read from
    -- C_Item.GetWeaponEnchantInfo, in combat too, on its events (Sources/Enchants.lua), and modelled from our apply cast
    -- between reads.
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
}

for k, f in pairs( methods ) do ns.SpecMixin[ k ] = f end
