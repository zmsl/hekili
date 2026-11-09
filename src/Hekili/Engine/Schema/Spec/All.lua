-- Engine/Schema/Spec/All.lua
-- Spec 0 (`all`): the engine keys core reads by name (the cast and movement auras, the GCD, the APL verbs). It builds at
-- load and copies the spec mixin then, so every Spec/*.lua that adds mixin methods loads before this file.

local addon, ns = ...
local Facade = ns.Facade
local C_Spell, UnitCanAttack, UnitCastingInfo, UnitChannelInfo, UnitClassBase = Facade.C_Spell, Facade.UnitCanAttack, Facade.UnitCastingInfo, Facade.UnitChannelInfo, Facade.UnitClassBase
local Hekili = _G[ addon ]
local class = Hekili.Class
local state = Hekili.State
local GetSpellTexture = C_Spell.GetSpellTexture

class.file = UnitClassBase( "player" )
local all = Hekili:NewSpecialization( 0, "All", "Interface\\AddOns\\Hekili\\Textures\\HekiliForever" )

------------------------------------------------------------------------------------------------------------------------
-- The `all` spec's engine keys: what core reads by name (the cast and movement auras, the GCD, the APL verbs). Shared game
-- content (auras, consumables, items) is in Hekili_Shared/Shared/*.lua, racials in the race packs.

---@diagnostic disable-next-line: need-check-nil
all:RegisterAuras( {

    casting = {
        name = "Casting", -- l10n: verbatim
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
        id = ns.GCD_SPELL,
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
        name = "|cff00ccff[Call Action List]|r", -- l10n: verbatim
        listName = '|T136243:0|t |cff00ccff[Call Action List]|r',
        cast = 0,
        cooldown = 0,
        gcd = "off",
        essential = true,
    },

    run_action_list = {
        name = "|cff00ccff[Run Action List]|r", -- l10n: verbatim
        listName = '|T136243:0|t |cff00ccff[Run Action List]|r',
        cast = 0,
        cooldown = 0,
        gcd = "off",
        essential = true,
    },

    wait = {
        name = "|cff00ccff[Wait]|r", -- l10n: verbatim
        listName = '|T136243:0|t |cff00ccff[Wait]|r',
        cast = 0,
        cooldown = 0,
        gcd = "off",
        essential = true,
    },

    pool_resource = {
        name = "|cff00ccff[Pool Resource]|r", -- l10n: verbatim
        listName = "|T136243:0|t |cff00ccff[Pool Resource]|r",
        cast = 0,
        cooldown = 0,
        gcd = "off",
    },

    cancel_action = {
        name = "|cff00ccff[Cancel Action]|r", -- l10n: verbatim
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
        name = "|cff00ccff[Variable]|r", -- l10n: verbatim
        listName = '|T136243:0|t |cff00ccff[Variable]|r',
        cast = 0,
        cooldown = 0,
        gcd = "off",
        essential = true,
    },

    -- (re-pin design §3a) the rotation window lines: list-order entries with no icon, like `variable` (Engine/Sim/Core.lua)
    open_window = {
        name = "|cff00ccff[Open Window]|r", -- l10n: verbatim
        listName = '|T136243:0|t |cff00ccff[Open Window]|r',
        cast = 0,
        cooldown = 0,
        gcd = "off",
        essential = true,
    },

    close_window = {
        name = "|cff00ccff[Close Window]|r", -- l10n: verbatim
        listName = '|T136243:0|t |cff00ccff[Close Window]|r',
        cast = 0,
        cooldown = 0,
        gcd = "off",
        essential = true,
    },

    cancel_buff = {
        name = "|cff00ccff[Cancel Buff]|r", -- l10n: verbatim
        listName = '|T136243:0|t |cff00ccff[Cancel Buff]|r',
        cast = 0,
        gcd = "off",

        startsCombat = false,

        buff = function () return args.buff_name or nil end,

        indicator = "cancel",
        texture = function ()
            if not args.buff_name then return 134400 end

            local a = class.auras[ args.buff_name ]
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
