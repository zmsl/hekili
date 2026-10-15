-- Forever/Warrior.lua
-- The Forever Warrior (pseudo-spec 1491) for the VirtualState Phase 1 checkpoint (spec §10, §11): rage with its
-- main-hand swing model, Battle Shout, Rend and Heroic Strike with their costs, cooldowns, handlers and aura
-- durations, the Arms talents, and a default priority that recommends the spenders. Bloodrage is left out of Phase 1:
-- its rage over time is an aura-gated regen model VirtualState's resources family does not apply.
-- Spell data: the Forever DB2 at build 1.60.1.70338 (wowdb); a cost of 100 there is 10 rage.
-- Credits: Hekili (registration API and pack format); call shapes from archive/TheWarWithin/WarriorArms.lua:36-56.
-- Rage per swing from Taco Dog Forever's Warrior pack (src/TacoDogForever_Warrior/Warrior.lua:21-24).

local addon, ns = ...
local VGA = LibStub( "VirtualGameAPI-1.0" )
local C_SpellBook, UnitClassBase = VGA.C_SpellBook, VGA.UnitClassBase
local Hekili = _G[ addon ]

if UnitClassBase( "player" ) ~= "WARRIOR" then return end

local state = Hekili.State
local IsSpellKnown = C_SpellBook.IsSpellKnown
local floor = math.floor

local spec = Hekili:NewSpecialization( 1491, false, 135328 ) -- inv_sword_27; numeric because Options formats it with %d
if not spec then return end

-- Rank IDs, lowest first (the DB2's).
local BATTLE_SHOUT = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }
local REND = { 772, 6546, 6547, 6548, 11572, 11573, 11574 }
local REND_DURATION = { 9, 12, 15, 18, 21, 21, 21 }
local HEROIC_STRIKE = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }

local function rest( ids )
    local out = {}
    for i = 2, #ids do out[ #out + 1 ] = ids[ i ] end
    return out
end

-- The highest rank of `ids` the player knows (0: none). C_SpellBook, not the deprecation shims (cleanup Q12).
local function knownRank( ids )
    for i = #ids, 1, -1 do
        if IsSpellKnown( ids[ i ] ) then return i end
    end
    return 0
end

-- Rage a second of the main hand's unhasted weapon speed: a white swing brings rate x that speed (haste adds swings,
-- never rage per swing). shortcut: one rate (two-handed 4.5; one-handed is 3.46), upgrade with a weapon-size read when
-- a one-hander matters; VirtualState's calibration absorbs the difference meanwhile.
local RAGE_RATE = 4.5

spec:RegisterResource( Enum.PowerType.Rage, {
    mainhand = {
        swing = "mainhand",

        last = function ()
            local swing = state.swings.mainhand
            local t = state.query_time
            if state.mainhand_speed == 0 then return 0 end
            return swing + floor( ( t - swing ) / state.mainhand_speed ) * state.mainhand_speed
        end,

        interval = "mainhand_speed",

        stop = function () return state.swings.mainhand == 0 end,
        value = function () return RAGE_RATE * state.mainhand_speed / state.haste end,
    },
} )

-- Talents: { node (unused on Forever), the rank 1 spell, max rank }; VirtualState maps the trait walk's spells to them.
spec:RegisterTalents( {
    improved_heroic_strike           = { 0, 12282, 3 },
    deflection                       = { 0, 16462, 5 },
    improved_rend                    = { 0, 12286, 3 },
    improved_charge                  = { 0, 12285, 2 },
    improved_tactical_mastery        = { 0, 12295, 5 },
    improved_thunder_clap            = { 0, 12287, 3 },
    improved_overpower               = { 0, 12290, 2 },
    anger_management                 = { 0, 12296, 1 },
    deep_wounds                      = { 0, 12834, 3 },
    two_handed_weapon_specialization = { 0, 12163, 5 },
    impale                           = { 0, 16493, 2 },
    sweeping_strikes                 = { 0, 12292, 1 },
    improved_hamstring               = { 0, 12289, 3 },
    mortal_strike                    = { 0, 12294, 1 },
} )

-- The higher rank spells of each talent, in case the trait walk names a rank rather than rank 1 (spec §3.6 Track).
ns.VirtualState.Track( { talents = {
    [ 12663 ] = 12282, [ 12664 ] = 12282,
    [ 16463 ] = 16462, [ 16464 ] = 16462, [ 16465 ] = 16462, [ 16466 ] = 16462,
    [ 12658 ] = 12286, [ 12659 ] = 12286,
    [ 12697 ] = 12285,
    [ 12676 ] = 12295, [ 12677 ] = 12295, [ 12678 ] = 12295, [ 12679 ] = 12295,
    [ 12665 ] = 12287, [ 12666 ] = 12287,
    [ 12963 ] = 12290,
    [ 12849 ] = 12834, [ 12867 ] = 12834,
    [ 12711 ] = 12163, [ 12712 ] = 12163, [ 12713 ] = 12163, [ 12714 ] = 12163,
    [ 16494 ] = 16493,
    [ 12668 ] = 12289, [ 23695 ] = 12289,
} } )

spec:RegisterAuras( {
    battle_shout = {
        id = 6673,
        copy = rest( BATTLE_SHOUT ),
        duration = 180,
        max_stack = 1,
    },
    rend = {
        id = 772,
        copy = rest( REND ),
        duration = function () return REND_DURATION[ knownRank( REND ) ] or 9 end,
        tick_time = 3,
        max_stack = 1,
    },
} )

spec:RegisterAbilities( {
    battle_shout = {
        id = 6673,
        copy = rest( BATTLE_SHOUT ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = false,
        known = function () return knownRank( BATTLE_SHOUT ) > 0 end,

        handler = function ()
            applyBuff( "battle_shout" )
        end,
    },

    rend = {
        id = 772,
        copy = rest( REND ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = function () return knownRank( REND ) > 0 end,

        handler = function ()
            applyDebuff( "target", "rend" )
        end,
    },

    heroic_strike = {
        id = 78,
        copy = rest( HEROIC_STRIKE ),
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = function () return 15 - talent.improved_heroic_strike.rank end, -- Improved Heroic Strike: -1 a rank
        spendType = "rage",

        startsCombat = true,
        onNextSwing = true, -- VirtualState: paid at the main hand's next swing, which then brings no rage
        known = function () return knownRank( HEROIC_STRIKE ) > 0 end,
    },
} )

spec:RegisterOptions( { package = "Warrior" } )

-- Payload: spec 1491; precombat battle_shout; default battle_shout, rend (!debuff.rend.up), heroic_strike (rage>=30). Generated by tools/make_pack.lua (the share format RestoreDefaults decodes).
spec:RegisterPack( "Warrior", 20261015, [[Hekili:TkvWUrnmq0VfUbIQWMwajQu4qpuv4WQkmcUn1tCM0yf3yl7jG6f)TZy3DxTlqpGekso2JFZBEVzm0cFfuditW2Z3C(7B30(oqXpgiqfqZmEVSzbFqw)ogJwFSe)rNhhkj2VAD8NwG()KJuGmW223(HwqnzhgONqrjdOU2hPFqXSEhNz9yzHNOS(B2iVIofl8L13oHj5xBwBMiZCWBx4lZ6RqMDsC1KFLZ61Wzz9xOLHSEMc7dCdf9wJaIJ2zb8pT8uwNcyuoefN1iEj6hToXDOHT(Lutisg)d9i31xRXDPsjoZo29I(1XXMJJ2SgYFExI)JWFD3BIIERahOk0Y5FdYu1b3LQgOGTO6p2DXgqjTVKG64oUZM4uDCsJ4QJLTBRJxAb7D0aC1EBkdUJ0fOmrltrlcQ)QQbwkZZqur1NqWPUPK6fptQN4UJ54Glz5tDyI8)0pvMXvEQ8G(gA26Sz9l39U8v1RHF9]] )
