-- Forever/Warrior.lua
-- The Forever Warrior (pseudo-spec 1491): the Classic Warrior kit with Forever's spell data (ranks, costs, cooldowns,
-- cast times and durations from the Forever DB2 at build 1.60.1.70338, wowdb; a cost of 100 there is 10 rage), Forever's
-- Victory Rush and Spearing Strike, rage with its main-hand swing model and Bloodrage's rage over time, stances from
-- the plain shapeshift reads, and the default priorities.
-- Talent modifiers: only rank 1 of each talent is in the Forever DB2, so a cost modifier is rank 1's value x the rank
-- (Classic's own convention), floored at 0; cooldown and duration modifiers are modelled only where every rank is in
-- the DB2 (Improved Taunt, Improved Shield Block). The in-game checkpoint compares the costs (Snapshot cost= / read=).
-- Unmodelled: Improved Slam's cast and GCD -0.5 s and cooldown -3 s (12862; only its replacement spells are tracked).
-- Credits: Hekili (registration API and pack format); the abilities, auras, stance swap, queue prediction and the Arms
-- and Fury priorities are ported from Hekili's Classic profile (origin/classic:Classic/Warrior.lua,
-- Classic/APLs/WarriorArms.simc, Classic/APLs/WarriorFury.simc); call shapes from archive/TheWarWithin/WarriorArms.lua.
-- Rage per swing from Taco Dog Forever's Warrior pack (src/TacoDogForever_Warrior/Warrior.lua:21-24).

local addon, ns = ...
local C_SpellBook, C_Spell, UnitClassBase = C_SpellBook, C_Spell, UnitClassBase
local GetShapeshiftForm, GetShapeshiftFormInfo = GetShapeshiftForm, GetShapeshiftFormInfo
local Hekili = _G[ addon ]

if UnitClassBase( "player" ) ~= "WARRIOR" then return end

local state = Hekili.State
local IsSpellKnown, IsCurrentSpell, IsSpellUsable = C_SpellBook.IsSpellKnown, C_Spell.IsCurrentSpell, C_Spell.IsSpellUsable
local floor, max, min = math.floor, math.max, math.min

local spec = Hekili:NewSpecialization( 1491, false, 135328 ) -- inv_sword_27; numeric because Options formats it with %d
if not spec then return end

-- Rank IDs, lowest first (the DB2's).
local BATTLE_SHOUT = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }
local REND = { 772, 6546, 6547, 6548, 11572, 11573, 11574 }
local REND_DURATION = { 9, 12, 15, 18, 21, 21, 21 }
local HEROIC_STRIKE = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }
local BLOODTHIRST = { 23881, 23892, 23893, 23894 }
local CHARGE = { 100, 6178, 11578 }
local CHARGE_RAGE = { 9, 12, 15 }
local CLEAVE = { 845, 7369, 11608, 11609, 20569 }
local DEMORALIZING_SHOUT = { 1160, 6190, 11554, 11555, 11556 }
local EXECUTE = { 5308, 20658, 20660, 20661, 20662 }
local HAMSTRING = { 1715, 7372, 7373 }
local INTERCEPT = { 20252, 20616, 20617 }
local MOCKING_BLOW = { 694, 7400, 7402, 20559, 20560 }
local MORTAL_STRIKE = { 12294, 21551, 21552, 21553 }
local OVERPOWER = { 7384, 7887, 11584, 11585 }
local PUMMEL = { 6552, 6554 }
local REVENGE = { 6572, 6574, 7379, 11600, 11601, 25288 }
local SHIELD_BASH = { 72, 1671, 1672 }
local SHIELD_SLAM = { 23922, 23923, 23924, 23925 }
-- Slam: Forever's rank 1 (1240193), then Improved Slam's replacements of each rank (1310196-1310200, the talent's
-- override effects), so a cast of either is ours.
local SLAM = { 1240193, 1464, 8820, 11604, 11605, 1310196, 1310197, 1310198, 1310199, 1310200 }
local SUNDER_ARMOR = { 7386, 7405, 8380, 11596, 11597 }
local THUNDER_CLAP = { 6343, 8198, 8204, 8205, 11580, 11581 }
local THUNDER_CLAP_DURATION = { 10, 14, 18, 22, 26, 30 }
local VICTORY_RUSH = { 402927 }
local SHIELD_BLOCK_BONUS = { 0.5, 1, 2 } -- Improved Shield Block's seconds by rank (all three in the DB2)
local TACTICAL_MASTERY = 1310185 -- Forever's level 14 passive: rage kept on a stance swap

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

local function knows( ids )
    return function () return knownRank( ids ) > 0 end
end

-- A reactive ability's window (Execute, Overpower's stance, Revenge, Victory Rush) from the plain usability read:
-- usable, or unusable only for lack of rage. The client's answer now, not at the simulated time (as Classic's
-- reset_precast read it); Forever has no combat log to time the window.
local function reactive( ids )
    local r = knownRank( ids )
    if r == 0 then return false end
    local usable, noMana = IsSpellUsable( ids[ r ] )
    return usable == true or noMana == true
end

-- Rage a second of the main hand's unhasted weapon speed: a white swing brings rate x that speed (haste adds swings,
-- never rage per swing): 4.5 for a two-hander, 3.46 for a one-hander (Hekili's gear scan sets main_hand.size).
-- shortcut: no off-hand swing source (VirtualState models one swing-paid hand), so a dual wielder's off hand is left
-- to VirtualState's calibration; upgrade when the resources family takes a second hand.
local function rageRate()
    return state.main_hand.size == 1 and 3.46 or 4.5
end

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
        value = function () return rageRate() * state.mainhand_speed / state.haste end,
    },

    -- Bloodrage's aura (29131): 1 rage every second for 10 s (DB2 effect: periodic energize 10 every 1000 ms).
    bloodrage = {
        aura = "bloodrage",

        last = function ()
            local app = state.buff.bloodrage.applied
            return app + floor( state.query_time - app )
        end,

        interval = 1,
        -- shortcut: Improved Bloodrage's +50% (12301) is unmodelled here, VirtualState's entries take a number fixed at
        -- build; the handler's instant gain carries it. Upgrade if the regen entries learn talent-scaled values.
        value = 1,
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
    battle_stance = {
        id = 2457,
        duration = 3600,
        max_stack = 1,
    },
    berserker_rage = {
        id = 18499,
        duration = 10,
        max_stack = 1,
    },
    berserker_stance = {
        id = 2458,
        duration = 3600,
        max_stack = 1,
    },
    blood_craze = {
        id = 16488,
        copy = { 16490, 16491 },
        duration = 6,
        tick_time = 1,
        max_stack = 1,
    },
    bloodrage = {
        id = 29131,
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    challenging_shout = {
        id = 1161,
        duration = 6,
        max_stack = 1,
    },
    charge_stun = {
        id = 7922,
        duration = 1,
        max_stack = 1,
    },
    -- Cleave or Heroic Strike queued on the next swing (C_Spell.IsCurrentSpell, applied in reset_precast). A full
    -- swing long, not the time to the swing, so it can outlast the real queue by up to one swing after a reset.
    cleave = {
        duration = function () return state.mainhand_speed end,
        max_stack = 1,
    },
    concussion_blow = {
        id = 12809,
        duration = 5,
        max_stack = 1,
    },
    death_wish = {
        id = 12328,
        duration = 30,
        max_stack = 1,
    },
    deep_wound = {
        id = 23255,
        copy = { 23256 },
        duration = 12,
        max_stack = 1,
    },
    defensive_stance = {
        id = 71,
        duration = 3600,
        max_stack = 1,
    },
    demoralizing_shout = {
        id = 1160,
        copy = rest( DEMORALIZING_SHOUT ),
        duration = 45,
        max_stack = 1,
    },
    disarm = {
        id = 676,
        duration = 10,
        max_stack = 1,
    },
    enrage = {
        id = 12880,
        copy = { 14201, 14202, 14203, 14204 },
        duration = 12,
        max_stack = 1,
    },
    -- A rogue's armor debuff; the Sunder Armor condition skips a target that has it.
    expose_armor = {
        id = 8647,
        copy = { 8649, 8650, 11197, 11198 },
        duration = 30,
        max_stack = 1,
    },
    flurry = {
        id = 12966,
        copy = { 12967, 12968, 12969, 12970 },
        duration = 15,
        max_stack = 1,
    },
    hamstring = {
        id = 1715,
        copy = rest( HAMSTRING ),
        duration = 15,
        max_stack = 1,
    },
    heroic_strike = {
        duration = function () return state.mainhand_speed end,
        max_stack = 1,
    },
    improved_hamstring = {
        id = 23694,
        duration = 5,
        max_stack = 1,
    },
    intercept_stun = {
        id = 20253,
        copy = { 20614, 20615 },
        duration = 3,
        max_stack = 1,
    },
    intimidating_shout = {
        id = 20511,
        copy = { 5246 },
        duration = 8,
        max_stack = 1,
    },
    last_stand = {
        id = 12976,
        duration = 20,
        max_stack = 1,
    },
    mocking_blow = {
        id = 694,
        copy = rest( MOCKING_BLOW ),
        duration = 6,
        max_stack = 1,
    },
    mortal_strike = {
        id = 12294,
        copy = rest( MORTAL_STRIKE ),
        duration = 10,
        max_stack = 1,
    },
    -- Forever's Overpower window: a 5 s player aura (DB2 1282733, "Overpower"), in place of Classic's combat log. It
    -- also grants a combo point (DB2 effect 0), so it may be a hidden aura the walk never sees (checkpoint Q6); the
    -- fallback is then Overpower on rage alone in Battle Stance, and the swap to Battle Stance after a dodge cannot be
    -- predicted from another stance (no combat log on Forever).
    overpower_ready = {
        id = 1282733,
        duration = 5,
        max_stack = 1,
    },
    piercing_howl = {
        id = 12323,
        duration = 6,
        max_stack = 1,
    },
    recklessness = {
        id = 1719,
        duration = 15,
        max_stack = 1,
    },
    rend = {
        id = 772,
        copy = rest( REND ),
        duration = function () return REND_DURATION[ knownRank( REND ) ] or 9 end,
        tick_time = 3,
        max_stack = 1,
    },
    retaliation = {
        id = 20230,
        duration = 15,
        max_stack = 1,
    },
    revenge_stun = {
        id = 12798,
        duration = 3,
        max_stack = 1,
    },
    -- Revenge's window from its plain usability (reset_precast): 5 s from that read, not from the block, dodge or
    -- parry (no combat log on Forever to time the proc).
    revenge_usable = {
        duration = 5,
        max_stack = 1,
    },
    shield_bash_silenced = {
        id = 18498,
        duration = 3,
        max_stack = 1,
    },
    shield_block = {
        id = 2565,
        duration = function () return 7 + ( SHIELD_BLOCK_BONUS[ talent.improved_shield_block.rank ] or 0 ) end,
        max_stack = 1,
    },
    shield_wall = {
        id = 871,
        duration = 12,
        max_stack = 1,
    },
    sunder_armor = {
        id = 7386,
        copy = rest( SUNDER_ARMOR ),
        duration = 30,
        max_stack = 5,
    },
    sweeping_strikes = {
        id = 12292,
        duration = 20,
        max_stack = 5,
    },
    taunt = {
        id = 355,
        duration = 3,
        max_stack = 1,
    },
    thunder_clap = {
        id = 6343,
        copy = rest( THUNDER_CLAP ),
        duration = function () return THUNDER_CLAP_DURATION[ knownRank( THUNDER_CLAP ) ] or 10 end,
        max_stack = 1,
        shared = "target",
    },
    windfury = {
        id = 8512,
        copy = { 10613, 10614 },
        duration = 300,
        max_stack = 1,
    },
} )

local STANCE_OF_SPELL = { [ 2457 ] = "battle_stance", [ 71 ] = "defensive_stance", [ 2458 ] = "berserker_stance" }

-- A stance change drops all rage above what is kept: Forever's Tactical Mastery passive keeps 10, Improved Tactical
-- Mastery 15 more a rank (DB2: 1310185 keeps $m1 + $12295m1; 12295's m1 is 15). Rage tops out at 100, so no cap.
spec:RegisterStateFunction( "swap_stance", function( stance )
    removeBuff( "battle_stance" )
    removeBuff( "defensive_stance" )
    removeBuff( "berserker_stance" )

    local kept = ( IsSpellKnown( TACTICAL_MASTERY ) and 10 or 0 ) + 15 * talent.improved_tactical_mastery.rank
    local lost = rage.current - kept
    if lost > 0 then spend( lost, "rage" ) end

    applyBuff( stance )
end )

spec:RegisterHook( "reset_precast", function()
    -- The stance from the plain shapeshift reads (forever-facade-notes: GetShapeshiftForm, GetShapeshiftFormInfo).
    removeBuff( "battle_stance" )
    removeBuff( "defensive_stance" )
    removeBuff( "berserker_stance" )
    local form = GetShapeshiftForm()
    if form and form > 0 then
        local _, _, _, spellID = GetShapeshiftFormInfo( form )
        local stance = STANCE_OF_SPELL[ spellID ]
        if stance then applyBuff( stance ) end
    end

    local hs, cl = knownRank( HEROIC_STRIKE ), knownRank( CLEAVE )
    if hs > 0 and IsCurrentSpell( HEROIC_STRIKE[ hs ] ) then applyBuff( "heroic_strike" ) end
    if cl > 0 and IsCurrentSpell( CLEAVE[ cl ] ) then applyBuff( "cleave" ) end

    if reactive( REVENGE ) then applyBuff( "revenge_usable" ) end
end )

-- `timeToReady` of the three stances: they share a 1 s category cooldown.
local function stanceReady()
    return max( cooldown.battle_stance.remains, cooldown.defensive_stance.remains, cooldown.berserker_stance.remains )
end

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
        known = knows( BATTLE_SHOUT ),

        handler = function ()
            applyBuff( "battle_shout" )
        end,
    },

    battle_stance = {
        id = 2457,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        known = knows( { 2457 } ),
        nobuff = "battle_stance",
        timeToReady = stanceReady,

        handler = function ()
            swap_stance( "battle_stance" )
        end,
    },

    berserker_rage = {
        id = 18499,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        startsCombat = false,
        known = knows( { 18499 } ),
        buff = "berserker_stance",

        handler = function ()
            applyBuff( "berserker_rage" )
            -- DB2 20500: energize 100 (10 rage) a rank.
            if talent.improved_berserker_rage.enabled then gain( 10 * talent.improved_berserker_rage.rank, "rage" ) end
        end,
    },

    berserker_stance = {
        id = 2458,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        known = knows( { 2458 } ),
        nobuff = "berserker_stance",
        timeToReady = stanceReady,

        handler = function ()
            swap_stance( "berserker_stance" )
        end,
    },

    -- 10 rage now (DB2: energize 100), then 10 over 10 s from its aura (the resource's bloodrage entry). Its health
    -- cost is not simulated: the player's health is secret on Forever.
    bloodrage = {
        id = 2687,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        startsCombat = true,
        known = knows( { 2687 } ),
        toggle = "cooldowns",

        handler = function ()
            -- DB2 12301: +50% of the rage Bloodrage generates a rank.
            gain( 10 * ( 1 + 0.5 * talent.improved_bloodrage.rank ), "rage" )
            applyBuff( "bloodrage" )
        end,
    },

    bloodthirst = {
        id = 23881,
        copy = rest( BLOODTHIRST ),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 30,
        spendType = "rage",

        talent = "bloodthirst",
        startsCombat = true,
        known = knows( BLOODTHIRST ),
    },

    challenging_shout = {
        id = 1161,
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        known = knows( { 1161 } ),
        toggle = "defensives",

        handler = function ()
            applyDebuff( "target", "challenging_shout" )
        end,
    },

    charge = {
        id = 100,
        copy = rest( CHARGE ),
        cast = 0,
        cooldown = 15,
        gcd = "off",

        startsCombat = true,
        known = knows( CHARGE ),
        buff = "battle_stance",

        usable = function ()
            return combat == 0 and target.minR >= 8 and target.minR <= 25, "cannot be in combat; target must be outside your deadzone"
        end,

        handler = function ()
            setDistance( 7 )
            if not target.is_boss then applyDebuff( "target", "charge_stun" ) end
            gain( ( CHARGE_RAGE[ knownRank( CHARGE ) ] or 9 ) + 3 * talent.improved_charge.rank, "rage" )
        end,
    },

    cleave = {
        id = 845,
        copy = rest( CLEAVE ),
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = function () return max( 0, 20 - 3 * talent.improved_cleave.rank ) end,
        spendType = "rage",

        startsCombat = true,
        onNextSwing = true, -- VirtualState: paid at the main hand's next swing, which then brings no rage
        known = knows( CLEAVE ),

        usable = function ()
            return not buff.heroic_strike.up and not buff.cleave.up, "a strike is already queued"
        end,

        handler = function ()
            applyBuff( "cleave" )
        end,
    },

    concussion_blow = {
        id = 12809,
        cast = 0,
        cooldown = 45,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        talent = "concussion_blow",
        startsCombat = true,
        known = knows( { 12809 } ),

        handler = function ()
            applyDebuff( "target", "concussion_blow" )
        end,
    },

    death_wish = {
        id = 12328,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        talent = "death_wish",
        startsCombat = true,
        known = knows( { 12328 } ),
        toggle = "cooldowns",

        handler = function ()
            applyBuff( "death_wish" )
        end,
    },

    defensive_stance = {
        id = 71,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        known = knows( { 71 } ),
        nobuff = "defensive_stance",
        timeToReady = stanceReady,

        handler = function ()
            swap_stance( "defensive_stance" )
        end,
    },

    demoralizing_shout = {
        id = 1160,
        copy = rest( DEMORALIZING_SHOUT ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( DEMORALIZING_SHOUT ),

        handler = function ()
            applyDebuff( "target", "demoralizing_shout" )
            active_dot.demoralizing_shout = active_enemies
        end,
    },

    disarm = {
        id = 676,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = 20,
        spendType = "rage",

        startsCombat = true,
        known = knows( { 676 } ),
        toggle = "cooldowns",
        buff = "defensive_stance",

        handler = function ()
            applyDebuff( "target", "disarm" )
        end,
    },

    -- Usable below 20% health: the target's health is secret on Forever, so the window is the plain usability read.
    execute = {
        id = 5308,
        copy = rest( EXECUTE ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function () return max( 0, 15 - 5 * talent.improved_execute.rank ) end,
        spendType = "rage",

        startsCombat = true,
        known = knows( EXECUTE ),

        usable = function () return reactive( EXECUTE ), "requires target health under 20 percent" end,

        handler = function ()
            spend( rage.current, "rage" ) -- the rest of the rage goes into the strike
        end,
    },

    hamstring = {
        id = 1715,
        copy = rest( HAMSTRING ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( HAMSTRING ),
        nobuff = "defensive_stance",

        handler = function ()
            applyDebuff( "target", "hamstring" )
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
        -- VirtualState: paid at the main hand's next swing, which then brings no rage. Hekili's own simulation ignores
        -- onNextSwing: it spends the cost at the press and still adds the replaced swing's rage, so its forward
        -- projection is one swing of rage optimistic per queued strike until VirtualState's next drain corrects the
        -- belief (checkpoint Q9). Cleave alike.
        onNextSwing = true,
        known = knows( HEROIC_STRIKE ),

        usable = function ()
            return not buff.heroic_strike.up and not buff.cleave.up, "a strike is already queued"
        end,

        handler = function ()
            applyBuff( "heroic_strike" )
        end,
    },

    intercept = {
        id = 20252,
        copy = rest( INTERCEPT ),
        cast = 0,
        cooldown = 30,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( INTERCEPT ),
        buff = "berserker_stance",

        handler = function ()
            setDistance( 7 )
            applyDebuff( "target", "intercept_stun" )
        end,
    },

    intimidating_shout = {
        id = 5246,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 25,
        spendType = "rage",

        startsCombat = true,
        known = knows( { 5246 } ),
        toggle = "cooldowns",

        handler = function ()
            applyDebuff( "target", "intimidating_shout" )
        end,
    },

    -- Classic also raised the simulated maximum health; the player's health is secret on Forever.
    last_stand = {
        id = 12975,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        talent = "last_stand",
        startsCombat = false,
        known = knows( { 12975 } ),
        toggle = "defensives",

        handler = function ()
            applyBuff( "last_stand" )
        end,
    },

    mocking_blow = {
        id = 694,
        copy = rest( MOCKING_BLOW ),
        cast = 0,
        cooldown = 120,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( MOCKING_BLOW ),
        toggle = "cooldowns",
        buff = "battle_stance",

        handler = function ()
            applyDebuff( "target", "mocking_blow" )
        end,
    },

    mortal_strike = {
        id = 12294,
        copy = rest( MORTAL_STRIKE ),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 30,
        spendType = "rage",

        talent = "mortal_strike",
        startsCombat = true,
        known = knows( MORTAL_STRIKE ),

        handler = function ()
            applyDebuff( "target", "mortal_strike" )
        end,
    },

    overpower = {
        id = 7384,
        copy = rest( OVERPOWER ),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        known = knows( OVERPOWER ),
        buff = "battle_stance",

        usable = function () return buff.overpower_ready.up, "only usable after the target dodges" end,

        handler = function ()
            removeBuff( "overpower_ready" )
        end,
    },

    piercing_howl = {
        id = 12323,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        talent = "piercing_howl",
        startsCombat = true,
        known = knows( { 12323 } ),

        handler = function ()
            applyDebuff( "target", "piercing_howl" )
        end,
    },

    pummel = {
        id = 6552,
        copy = rest( PUMMEL ),
        cast = 0,
        cooldown = 10,
        gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( PUMMEL ),
        buff = "berserker_stance",
        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            interrupt()
        end,
    },

    recklessness = {
        id = 1719,
        cast = 0,
        cooldown = 1800,
        gcd = "spell",

        startsCombat = false,
        known = knows( { 1719 } ),
        toggle = "cooldowns",
        buff = "berserker_stance",

        handler = function ()
            applyBuff( "recklessness" )
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
        known = knows( REND ),
        nobuff = "berserker_stance",

        handler = function ()
            applyDebuff( "target", "rend" )
        end,
    },

    retaliation = {
        id = 20230,
        cast = 0,
        cooldown = 900,
        gcd = "spell",

        startsCombat = false,
        known = knows( { 20230 } ),
        toggle = "cooldowns",
        buff = "battle_stance",

        handler = function ()
            applyBuff( "retaliation" )
        end,
    },

    revenge = {
        id = 6572,
        copy = rest( REVENGE ),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        known = knows( REVENGE ),

        buff = function ()
            if buff.revenge_usable.up then return "defensive_stance" end
            return "revenge_usable"
        end,

        handler = function ()
            removeBuff( "revenge_usable" )
        end,
    },

    shield_bash = {
        id = 72,
        copy = rest( SHIELD_BASH ),
        cast = 0,
        cooldown = 12,
        gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( SHIELD_BASH ),
        toggle = "interrupts",
        buff = function () return buff.battle_stance.up and "battle_stance" or "defensive_stance" end,
        equipped = "shield",
        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            interrupt()
            if talent.improved_shield_bash.rank >= 1 then applyDebuff( "target", "shield_bash_silenced" ) end
        end,
    },

    shield_block = {
        id = 2565,
        cast = 0,
        cooldown = 5,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        startsCombat = false,
        known = knows( { 2565 } ),
        buff = "defensive_stance",
        equipped = "shield",

        handler = function ()
            applyBuff( "shield_block" )
        end,
    },

    shield_slam = {
        id = 23922,
        copy = rest( SHIELD_SLAM ),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 20,
        spendType = "rage",

        startsCombat = true,
        known = knows( SHIELD_SLAM ),
        equipped = "shield",
    },

    shield_wall = {
        id = 871,
        cast = 0,
        cooldown = 900,
        gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)

        startsCombat = false,
        known = knows( { 871 } ),
        toggle = "defensives",
        buff = "defensive_stance",
        equipped = "shield",

        handler = function ()
            applyBuff( "shield_wall" )
        end,
    },

    -- Forever gave Slam an 18 s cooldown (DB2 category recovery) and a rank 1 at level 20.
    slam = {
        id = 1240193,
        copy = rest( SLAM ),
        cast = 1.5,
        cooldown = 18,
        gcd = "spell",

        spend = 15,
        spendType = "rage",

        startsCombat = true,
        known = knows( SLAM ),
    },

    -- Forever: a strike with a 20 s cooldown, learned at level 1 (DB2 1310222).
    spearing_strike = {
        id = 1310222,
        cast = 0,
        cooldown = 20,
        gcd = "spell",

        spend = 15,
        spendType = "rage",

        startsCombat = true,
        known = knows( { 1310222 } ),
    },

    sunder_armor = {
        id = 7386,
        copy = rest( SUNDER_ARMOR ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function () return max( 0, 15 - 3 * talent.improved_sunder_armor.rank ) end,
        spendType = "rage",

        startsCombat = true,
        known = knows( SUNDER_ARMOR ),

        handler = function ()
            applyDebuff( "target", "sunder_armor", nil, min( 5, debuff.sunder_armor.stack + 1 ) )
        end,
    },

    sweeping_strikes = {
        id = 12292,
        cast = 0,
        cooldown = 30,
        gcd = "off",

        spend = 30,
        spendType = "rage",

        talent = "sweeping_strikes",
        startsCombat = false,
        known = knows( { 12292 } ),
        buff = "battle_stance",

        handler = function ()
            applyBuff( "sweeping_strikes", nil, 5 )
        end,
    },

    taunt = {
        id = 355,
        cast = 0,
        cooldown = function () return 8 - talent.improved_taunt.rank end, -- Improved Taunt: -1 s a rank (both in the DB2)
        gcd = "off",

        startsCombat = true,
        known = knows( { 355 } ),
        buff = "defensive_stance",

        handler = function ()
            applyDebuff( "target", "taunt" )
        end,
    },

    thunder_clap = {
        id = 6343,
        copy = rest( THUNDER_CLAP ),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = function () return max( 0, 20 - 6 * talent.improved_thunder_clap.rank ) end,
        spendType = "rage",

        startsCombat = true,
        known = knows( THUNDER_CLAP ),
        buff = "battle_stance",

        handler = function ()
            applyDebuff( "target", "thunder_clap" )
            active_dot.thunder_clap = min( active_enemies, 4 + active_dot.thunder_clap )
        end,
    },

    -- Forever: usable for a while after a kill that yields experience or honor; free, 30 s cooldown (DB2 402927).
    victory_rush = {
        id = 402927,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        startsCombat = true,
        known = knows( VICTORY_RUSH ),

        usable = function () return reactive( VICTORY_RUSH ), "only usable after a kill" end,
    },

    whirlwind = {
        id = 1680,
        cast = 0,
        cooldown = 10,
        gcd = "spell",

        spend = 25,
        spendType = "rage",

        startsCombat = true,
        known = knows( { 1680 } ),
        buff = "berserker_stance",
    },
} )

spec:RegisterOptions( { package = "Warrior" } )

-- Payload: spec 1491; precombat battle_shout; default battle_shout, rend (!debuff.rend.up), heroic_strike (rage>=30). Generated by tools/make_pack.lua (the share format RestoreDefaults decodes).
spec:RegisterPack( "Warrior", 20261015, [[Hekili:TkvWUrnmq0VfUbIQWMwajQu4qpuv4WQkmcUn1tCM0yf3yl7jG6f)TZy3DxTlqpGekso2JFZBEVzm0cFfuditW2Z3C(7B30(oqXpgiqfqZmEVSzbFqw)ogJwFSe)rNhhkj2VAD8NwG()KJuGmW223(HwqnzhgONqrjdOU2hPFqXSEhNz9yzHNOS(B2iVIofl8L13oHj5xBwBMiZCWBx4lZ6RqMDsC1KFLZ61Wzz9xOLHSEMc7dCdf9wJaIJ2zb8pT8uwNcyuoefN1iEj6hToXDOHT(Lutisg)d9i31xRXDPsjoZo29I(1XXMJJ2SgYFExI)JWFD3BIIERahOk0Y5FdYu1b3LQgOGTO6p2DXgqjTVKG64oUZM4uDCsJ4QJLTBRJxAb7D0aC1EBkdUJ0fOmrltrlcQ)QQbwkZZqur1NqWPUPK6fptQN4UJ54Glz5tDyI8)0pvMXvEQ8G(gA26Sz9l39U8v1RHF9]] )
