-- Forever/Warrior.lua
-- The Forever Warrior (pseudo-spec 1491): the Classic Warrior kit with Forever's spell data (ranks, costs, cooldowns,
-- cast times and durations from the Forever DB2 at build 1.60.1.70338, wowdb, a cost of 100 there being 10 rage; the
-- client is 1.60.1.70374, and its export wins where they differ), Forever's Victory Rush and Spearing Strike, rage per
-- hit for both hands, Bloodrage's and Anger Management's rage over time, stances from the plain shapeshift reads, and
-- the default priorities.
-- Talents: the 52 live nodes (a ForeverProbe export of the client, 1.60.1.70374, 2026-10-15). Only rank 1 of each
-- talent is in the Forever DB2, so a cost modifier is rank 1's value x the rank (Classic's own convention), floored
-- at 0; no cooldown or duration modifier is modelled. The in-game checkpoint compares the costs (Snapshot cost= /
-- read=).
-- Unmodelled: Improved Slam's cast and GCD -0.5 s and cooldown -3 s (12862; only its replacement spells are tracked).
-- Credits: Hekili (registration API and pack format); the abilities, auras, stance swap, queue prediction and the Arms
-- and Fury priorities are ported from Hekili's Classic profile (origin/classic:Classic/Warrior.lua,
-- Classic/APLs/WarriorArms.simc, Classic/APLs/WarriorFury.simc); call shapes from archive/TheWarWithin/WarriorArms.lua.
-- The one- and two-hander rage rates as in Taco Dog Forever's Warrior pack
-- (src/TacoDogForever_Warrior/Warrior.lua:21-24).

local addon, ns = ...
local C_SpellBook, C_Spell, UnitClassBase = C_SpellBook, C_Spell, UnitClassBase
local GetShapeshiftForm, GetShapeshiftFormInfo = GetShapeshiftForm, GetShapeshiftFormInfo
local Hekili = _G[ addon ]

if UnitClassBase( "player" ) ~= "WARRIOR" then return end

local state = Hekili.State
local VS = ns.VirtualState
local IsSpellKnown, IsCurrentSpell, IsSpellUsable = C_SpellBook.IsSpellKnown, C_Spell.IsCurrentSpell, C_Spell.IsSpellUsable
local floor, max, min, sort = math.floor, math.max, math.min, table.sort

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
local WHIRLWIND = { 1680 }
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

-- A reactive ability's window (Execute, Revenge, Victory Rush) from the plain usability read:
-- usable, or unusable only for lack of rage. The client's answer now, not at the simulated time (as Classic's
-- reset_precast read it); Forever has no combat log to time the window.
local function reactive( ids )
    local r = knownRank( ids )
    if r == 0 then return false end
    local usable, noMana = IsSpellUsable( ids[ r ] )
    return usable == true or noMana == true
end

-- Usable now by the plain read, not merely short of a cost: Overpower's second cost (a combo point a dodge grants)
-- reads as "short" without a dodge.
local function usableNow( ids )
    local r = knownRank( ids )
    return r > 0 and IsSpellUsable( ids[ r ] ) == true
end

-- Rage per white swing, as measured on Forever (build 1.60.1; https://github.com/magey/forever-warrior/issues/3 and
-- the warrior compendium v3.1.0, 2026-10-01, https://ppach-warriorcompendium.share.connect.posit.cloud/rage.html):
-- the weapon's unhasted speed x a rate by hand, independent of damage, level and haste: 3.46 main hand with a
-- one-hander, 4.5 with a two-hander, 1.73 off hand. Misses, dodges and parries give none, glancing blows full rage, a
-- crit one extra base swing. Dual Wield Specialization: the tooltip's +10% off-hand rage a rank (unverified on
-- Forever). Unbridled Wrath: 1 rage a proc (2 with a two-hander) at a measured ~7.5% a rank (36% at 5/5; the tooltip
-- says 60%). The two-hander flag is Hekili's gear scan (main_hand.size from C_Item.GetItemInfo's equip location on
-- PLAYER_EQUIPMENT_CHANGED; the Forever API data marks neither it nor GetInventoryItemID secret).
-- shortcut: crits (+1 base swing each) and misses are ignored; VirtualState's calibration scale absorbs them. Upgrade
-- when crit chance is read plainly.
local function rageOf( hand )
    local speed = VS.SwingBase( hand )
    if speed <= 0 then speed = hand == 1 and state.mainhand_speed or state.offhand_speed end -- no plain base read yet
    local twoHand = state.main_hand.size == 2
    local wrath = 0.075 * state.talent.unbridled_wrath.rank * ( twoHand and 2 or 1 )
    if hand ~= 1 then
        return 1.73 * speed * ( 1 + 0.1 * state.talent.dual_wield_specialization.rank ) + wrath
    end
    return ( twoHand and 4.5 or 3.46 ) * speed + wrath
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
        value = function () return rageOf( 1 ) end,
    },

    offhand = {
        swing = "offhand",

        last = function ()
            local swing = state.swings.offhand
            local t = state.query_time
            if state.offhand_speed == 0 then return 0 end
            return swing + floor( ( t - swing ) / state.offhand_speed ) * state.offhand_speed
        end,

        interval = "offhand_speed",

        stop = function () return state.swings.offhand == 0 end,
        value = function () return rageOf( 2 ) end,
    },

    -- Anger Management (12296): 1 rage every 3 s in combat (DB2 m2 = 1, m3 = 3), from the combat start.
    anger_management = {
        talent = "anger_management",

        last = function ()
            local start = state.combat
            if start == 0 then return state.query_time end
            return start + floor( ( state.query_time - start ) / 3 ) * 3
        end,

        interval = 3,

        stop = function () return state.combat == 0 end,
        value = 1,
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
}, nil, {
    -- Out-of-combat rage loss per second, VirtualState's `decay` (in the meta table: Hekili takes every regen entry for
    -- a model): measured 100 -> 0 in 82.2 s on 2026-10-15 (1.22/s); Anger Management's tooltip: 30% less.
    decay = function () return 1.22 * ( 1 - 0.3 * state.talent.anger_management.rank ) end,
} )

-- Talents: { node (unused on Forever), the definition spell, max rank }: the 52 nodes of Forever's one talent tree,
-- grouped by their columns as the pane shows them. Keys are Classic's where the talent exists (Bastion keeps Classic's
-- one_handed_weapon_specialization), snake_case names for the Forever-only ones. Each node reported one definition
-- spell at every rank the export saw (owned nodes at ranks 1-5 report their rank 1 spell; Iron Will and Defiance
-- define themselves by a higher DB2 rank's ID), so there are no rank aliases. VirtualState maps the trait walk's
-- spells to them.
spec:RegisterTalents( {
    -- Arms (17)
    improved_heroic_strike           = { 0, 12282, 3 },
    deflection                       = { 0, 16462, 5 },
    improved_rend                    = { 0, 12286, 3 },
    improved_charge                  = { 0, 12285, 2 },
    improved_tactical_mastery        = { 0, 12295, 5 },
    improved_overpower               = { 0, 12290, 2 },
    anger_management                 = { 0, 12296, 1 },
    deep_wounds                      = { 0, 12834, 3 },
    two_handed_weapon_specialization = { 0, 12163, 3 },
    impale                           = { 0, 16493, 2 },
    sweeping_strikes                 = { 0, 12292, 1 },
    improved_hamstring               = { 0, 12289, 3 },
    mortal_strike                    = { 0, 12294, 1 },
    improved_slam                    = { 0, 12862, 2 }, -- effect unmodelled
    -- Forever-only; Weaponmaster (in place of the four weapon specializations) and Bloodthrill unmodelled.
    weaponmaster                     = { 0, 1290261, 5 },
    spearing_strike                  = { 0, 1310222, 1 },
    bloodthrill                      = { 0, 1289682, 5 },
    -- Fury (17)
    booming_voice                    = { 0, 12321, 5 },
    cruelty                          = { 0, 12320, 5 },
    unbridled_wrath                  = { 0, 12322, 5 },
    piercing_howl                    = { 0, 12323, 1 },
    blood_craze                      = { 0, 16487, 3 },
    dual_wield_specialization        = { 0, 23584, 5 },
    improved_execute                 = { 0, 20502, 2 },
    enrage                           = { 0, 12317, 5 },
    death_wish                       = { 0, 12328, 1 },
    improved_intercept               = { 0, 20504, 2 },
    improved_berserker_rage          = { 0, 20500, 2 },
    flurry                           = { 0, 12319, 5 },
    bloodthirst                      = { 0, 23881, 1 },
    -- Forever-only: Raging Blows (-3 rage on Cleave and Whirlwind); the others unmodelled.
    furious_precision                = { 0, 1323963, 3 },
    raging_blows                     = { 0, 1310315, 1 },
    lingering_rage                   = { 0, 1323964, 5 },
    gore_drinker                     = { 0, 1323967, 2 },
    -- Protection (18)
    shield_specialization            = { 0, 12298, 5 },
    anticipation                     = { 0, 12297, 5 },
    improved_bloodrage               = { 0, 12301, 2 },
    improved_thunder_clap            = { 0, 12287, 3 },
    iron_will                        = { 0, 12962, 5 },
    last_stand                       = { 0, 12975, 1 },
    improved_revenge                 = { 0, 12797, 3 },
    defiance                         = { 0, 12792, 3 },
    improved_sunder_armor            = { 0, 12308, 3 },
    improved_disarm                  = { 0, 12313, 3 },
    improved_shield_wall             = { 0, 12312, 2 },
    concussion_blow                  = { 0, 12809, 1 },
    improved_shield_bash             = { 0, 12311, 2 },
    one_handed_weapon_specialization = { 0, 16538, 5 }, -- "Bastion" on Forever
    shield_slam                      = { 0, 23922, 1 },
    -- Forever-only: Focused Rage (-3 rage a rank on the offensive abilities), Vanguard (Charge in Defensive Stance);
    -- Master of Defense unmodelled.
    focused_rage                     = { 0, 29787, 3 },
    vanguard                         = { 0, 1310317, 1 },
    master_of_defense                = { 0, 1310316, 2 },
} )

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
    -- Forever's Overpower window: a 5 s player aura (DB2 1282733, "Overpower"). It is unseen on Forever (checkpoint Q6:
    -- the aura walk raises in combat), so Overpower's gate is the client's usability read, and the swap to Battle
    -- Stance after a dodge cannot be predicted (no combat log on Forever).
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
        duration = 7,
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

-- Focused Rage: -3 rage a rank on the offensive abilities (Forever's tooltip; DB2 29787 -30 at rank 1), floored at 0.
-- shortcut: which abilities count is a guess (every ability that strikes an enemy, and Disarm; not the shouts),
-- unseen until someone buys the talent; correct the offensive_cost calls from the client's costs (Snapshot cost= /
-- read=) then.
spec:RegisterStateFunction( "offensive_cost", function( cost )
    return max( 0, cost - 3 * talent.focused_rage.rank )
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

        spend = function () return offensive_cost( 30 ) end,
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
        -- Vanguard: Charge also in Defensive Stance (Forever, 1310317)
        buff = function ()
            if talent.vanguard.enabled and buff.defensive_stance.up then return "defensive_stance" end
            return "battle_stance"
        end,

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

        spend = function () return offensive_cost( 20 - 3 * talent.raging_blows.rank ) end, -- Raging Blows: -3
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

        spend = function () return offensive_cost( 10 ) end,
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

        spend = function () return offensive_cost( 20 ) end,
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

        spend = function () return offensive_cost( max( 0, 15 - 5 * talent.improved_execute.rank ) ) end,
        spendType = "rage",

        startsCombat = true,
        known = knows( EXECUTE ),
        nobuff = "defensive_stance",

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

        spend = function () return offensive_cost( 10 ) end,
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

        -- Improved Heroic Strike: -1 a rank
        spend = function () return offensive_cost( 15 - talent.improved_heroic_strike.rank ) end,
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

        spend = function () return offensive_cost( 10 ) end,
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

        spend = function () return offensive_cost( 10 ) end,
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

        spend = function () return offensive_cost( 30 ) end,
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

        spend = function () return offensive_cost( 5 ) end,
        spendType = "rage",

        startsCombat = true,
        known = knows( OVERPOWER ),
        buff = "battle_stance",

        -- interim until the virtual event facade delivers the dodge event
        usable = function () return usableNow( OVERPOWER ), "no dodge to overpower" end,

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

        spend = function () return offensive_cost( 10 ) end,
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

        spend = function () return offensive_cost( 10 ) end,
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

        spend = function () return offensive_cost( 5 ) end,
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

        spend = function () return offensive_cost( 10 ) end,
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

        spend = function () return offensive_cost( 20 ) end,
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

        spend = function () return offensive_cost( 15 ) end,
        spendType = "rage",

        startsCombat = true,
        known = knows( SLAM ),
    },

    -- Forever: a strike with a 20 s cooldown, an Arms talent (node 1310222; the DB2's level 1 is not the gate).
    spearing_strike = {
        id = 1310222,
        cast = 0,
        cooldown = 20,
        gcd = "spell",

        spend = function () return offensive_cost( 15 ) end,
        spendType = "rage",

        startsCombat = true,
        talent = "spearing_strike",
        known = knows( { 1310222 } ),
        buff = "battle_stance",
    },

    sunder_armor = {
        id = 7386,
        copy = rest( SUNDER_ARMOR ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function () return offensive_cost( max( 0, 15 - 3 * talent.improved_sunder_armor.rank ) ) end,
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
        cooldown = 8,
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

        spend = function () return offensive_cost( max( 0, 20 - 6 * talent.improved_thunder_clap.rank ) ) end,
        spendType = "rage",

        startsCombat = true,
        known = knows( THUNDER_CLAP ),
        nobuff = "berserker_stance",

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

        spend = function () return offensive_cost( 25 - 3 * talent.raging_blows.rank ) end, -- Raging Blows: -3
        spendType = "rage",

        startsCombat = true,
        known = knows( WHIRLWIND ),
        buff = "berserker_stance",
    },
} )

-- The execute phase: Execute's plain usability window (the target's health is secret on Forever).
spec:RegisterStateExpr( "execute_phase", function()
    return reactive( EXECUTE )
end )

-- Queue prediction, ported from Hekili's Classic profile (Classic/Warrior.lua:462-575, without its debug lines): the
-- time to the next main-hand swing, and whether a strike queued now still leaves rage for the next Mortal Strike (or
-- Bloodthirst) and Whirlwind as they come off cooldown.
spec:RegisterStateExpr( "mainhand_remains", function()
    if now == query_time then
        local real = nextMH - now
        return real > 0 and real or 0
    end
    if query_time <= nextMH then return nextMH - query_time end
    if mainhand_speed <= 0 then return 0 end -- no swing speed read yet
    return mainhand_speed - ( query_time - nextMH ) % mainhand_speed
end )

local queueEvents = {
    { time = 0, spend = 0, priority = 1 },
    { time = 0, spend = 0, priority = 2 },
    { time = 0, spend = 0, priority = 3 },
}

local function byTime( a, b )
    if a.time == b.time then return a.priority < b.priority end
    return a.time < b.time
end

spec:RegisterStateFunction( "should_queue", function( queue_cost )
    -- An unlearned strike or Whirlwind reserves no rage (none is at the beta cap of 30).
    local ms = knownRank( MORTAL_STRIKE ) > 0
    local bt = knownRank( BLOODTHIRST ) > 0
    local ww = knownRank( WHIRLWIND ) > 0
    for i = 1, #queueEvents do
        local e = queueEvents[ i ]
        if e.priority == 1 then
            e.time = query_time + ( ms and cooldown.mortal_strike.remains or cooldown.bloodthirst.remains )
            e.spend = ms and action.mortal_strike.cost or bt and action.bloodthirst.cost or 0
        elseif e.priority == 2 then
            e.time = query_time + cooldown.whirlwind.remains
            e.spend = ww and action.whirlwind.cost or 0
        else
            e.time = query_time + mainhand_remains
            e.spend = queue_cost
        end
    end
    sort( queueEvents, byTime )

    local spent = 0
    for i = 1, #queueEvents - 1 do
        spent = spent + queueEvents[ i ].spend
        local nextEvent = queueEvents[ i + 1 ]
        if query_time + state:TimeToResource( rage, nextEvent.spend + spent ) > nextEvent.time then return false end
    end
    return true
end )

spec:RegisterStateExpr( "should_hs", function()
    return should_queue( action.heroic_strike.cost )
end )

spec:RegisterStateExpr( "should_cleave", function()
    return should_queue( action.cleave.cost )
end )

-- The Classic settings the Arms and Fury priorities read (Classic/Warrior.lua:1574-1734, same defaults). Left out:
-- adaptive Whirlwind and Bloodthirst-in-execute (they need attack power and weapon damage, secret on Forever), the
-- unused queueing threshold, and the Overpower stance-swap settings (the dodge is unseen from another stance).
spec:RegisterSetting( "adaptive_queueing_enabled", true, {
    type = "toggle",
    name = "Use Queue Prediction",
    desc = "When enabled, recommendations will use swing timers and rage calculations to determine if Heroic Strike or Cleave should be queued.",
    width = "full",
} )

spec:RegisterSetting( "execute_queueing_enabled", true, {
    type = "toggle",
    name = "Queue During Execute",
    desc = "When enabled, recommendations will always queue Heroic Strike or Cleave during the execute phase.",
    width = "full",
} )

spec:RegisterSetting( "ww_min_enemies", 2, {
    type = "range",
    name = "Minimum Enemies For Whirlwind",
    desc = "Select the minimum number of enemies before recommending Whirlwind over Bloodthirst or Mortal Strike.",
    width = "full",
    min = 0,
    softMax = 4,
    step = 1,
} )

spec:RegisterSetting( "ww_cd_diff", 1.5, {
    type = "range",
    name = "Whirlwind Cooldown Differential",
    desc = "Select the remaining time on Bloodthirst or Mortal Strike before Whirlwind can be recommended.",
    width = "full",
    min = 0,
    softMax = 2,
    step = 0.1,
} )

spec:RegisterSetting( "hamstring_threshold", 80, {
    type = "range",
    name = "Hamstring Rage Threshold",
    desc = "Select the rage threshold after which Hamstring will be recommended.",
    width = "full",
    min = 0,
    softMax = 100,
    step = 1,
} )

spec:RegisterSetting( "hamstring_cd_diff", 1.5, {
    type = "range",
    name = "Hamstring Cooldown Differential",
    desc = "Select the remaining time on Bloodthirst or Mortal Strike and Whirlwind before Hamstring can be recommended.",
    width = "full",
    min = 0,
    softMax = 2,
    step = 0.1,
} )

spec:RegisterSetting( "debuff_sunder_enabled", true, {
    type = "toggle",
    name = "Maintain Sunder Armor",
    desc = "When enabled, the Arms and Fury priorities will include Sunder Armor.",
    width = "full",
} )

spec:RegisterSetting( "debuff_sunder_max_stack", 1, {
    type = "range",
    name = "Max Sunders",
    desc = "Select the maximum number of Sunder Armor stacks for Sunder Armor recommendations.",
    width = "full",
    min = 1,
    max = 5,
    step = 1,
} )

-- Forever default: Sunder Armor's own level in the DB2 (7386, level 10), so Sunder is on from the start; Classic's 61
-- kept it to raid bosses at level 60.
spec:RegisterSetting( "debuff_sunder_min_level", 10, {
    type = "range",
    name = "Minimum Sunder Level",
    desc = "Select the minimum target level before recommending Sunder Armor.",
    width = "full",
    min = 0,
    max = 63,
    step = 1,
} )

spec:RegisterSetting( "debuff_demoshout_enabled", false, {
    type = "toggle",
    name = "Maintain Demoralizing Shout",
    desc = "When enabled, the Arms and Fury priorities will include Demoralizing Shout.",
    width = "full",
} )

spec:RegisterOptions( { package = "Arms" } )

-- The three priorities, generated by tools/make_pack.lua (lua5.1 tools/make_pack.lua prints these strings, in this
-- order; Forever/spec/warrior_spec.lua checks they match). Pick one with /hekili priority <name>.
spec:RegisterPack( "Arms", 20261016, [[Hekili:LJvtVnUnq0Fl5IBcsGQv2K0gGid0UafT9qU4cS3KmT0ylctjQssfNue4F7Di1xuYuADa2w0MCWj2IZ7Xzgs(Mrm0p8pcxMquq4Jxp)678N7Fx4s1lfq4Ycs8oYw8l5Km8V)KitQF4lmojrJADjLP(T8W1htGSaIdF0)M79dxMstsGkRazC4YFHlGNaXHvAcpS6leHGYfxDyvbxOGKdR2i4zhw9RWokJ(DOfFMrKsACdGcT5u1lEOZi4BOm03iXkkpx6viGyE2AIka)OyqKmLxQUIUj4S1LB24z)uVYId)EnWazzEciIiIm0vqZLGsrZ3k9sanWO6XHCYAgKmR6PE2O8KkmF9WiaZiphzmy2z1yHNl4sOgBzXmfrSfuEmm3Wwm28NrZJmw065xg89jasbHr)leqxapKbTvMbBdIgp5y82PgCcIjmwu1pJyuP6k9gIGyoNLW3Nl1Z2AUu(A)qW8Vl)KnrIY8J5bEgIlvGML6VgvKsKWxfOGRi6h1AOxRlfi3dqHjEuc6oW4JAREcWWhYOGCHVdCMSjrLgTNktDpoUdBhdKYC8tNf1EEqki4046z9QsCbMJ5(TXjb(h7cb(Zo)8ZAxOijKcZW)zjucANVzLQz(9WfkfHvtVNaYi0C5IabEm1trZGifp6MRF9eOuVoZsIsLx8659s7ZAb384HyV4IJIB9MegqE6RgYl(hjKVD(BiKRC0VvHD936gQzxzWt0yfx8sKO0ERuZWi0pA7vSc9puBwSIBow4RGVhR(5A09PubBpnpXrQOtpF)EtzG6bE9BscYM84KOe6MnNssQFE92hMEAU0XS4on1dUtlWgmiIo9D32WizMs)ixqUAGtvhdorkGQ1GMkK6FRRr)2zkLKPTkFRMUtEvOfvtAQBbSDpYjbZSafxkWaqTWHDQubG70zUD(1moprtH25TP6H7N7gWWMUS6JONDGqcIDydnypr5XoecmidxIhxKie7wl11)L62pB4d)(JMUyRxhc)5M(br8wAWHkKMb2fJnscckPcX7a12UqVx1LWLwzyD6cZfF6eZf)VwfUlFuXHReXnJS5PvSwB0TJyu75XjsGVx1U15L7gjV0JfTH)WigoqjxB6poMPOGUDAEs5ynr3pcrA98Ee9w051e7pFeMBLwTP)Kxb)3x33emJPE2Q)BhmdQdyiyOSAlbw1d6LVllm4gxcsBrhndkx44qSsF7cBiLm1uLdSFFD7zRnd9F0323vPRMy643EFQi7nElatxNy8x63s2DWDhuvapQ6kLAFVAxYWDZtpvFRtX9VuGEmxdzkL7PG32BHzNv7Tkn1ERr3R76INQ4TXjDW6h5gto1M0E33yYWtEni62CRSpdnLW3GRdBQK60Innxo2u(N9vKzCs0njLQuTOB116Ey151xd8fMHd)7]] )
spec:RegisterPack( "Fury", 20261016, [[Hekili:LJ1tVTUnm8pl9swlEfEj912TcuNdBadB7qVKbSB2rXIjwiYwEsYnndf5Z(Js(FYo2Uj4Tn866H06yr(tK)efjddMf8hblOene80ntV5(ztNDFWc9(miyrgjAlzd(qkjb)7VKl3BE5EUGqnATkNX1)wAWQJbqLbrbpn72hMfSiMrPqHuGkcXriHNb5HLgapS8pjsjtiV(WYmHud0dlxlfjhw(RWwgN9DQdl)zorPyrvkKzeNP37HgJuSMXrBJePzIuLxMeIejRiAF8JMdHQyrU(A2A)lwLVETN7B9YZo87Lk6RYtPGmKitqtbfxbAnlDJYJcgfdlxhsjR4aDsXB9C1YtPr(6XbumH8sOvGjxuQl8sMqbL6MNnrtKBaThh5g(8H2)ewAOvIAl)t(FpfqiiC2FJk04WDrWiLDXANOYsowFxQb3GicNhw81qotPV2eq4hjeCQyxQYSBRek1RTDb7)(0NDbsMNEmoWlquUgmOu(yywmrbVPIsHMyEvTGE1MKpfi64WDmvCpRAaeI2YbLkf)0ir5(7hdsblcpWKSTW154XKazWnru)zgZ0i(ZaYJqcdu(ZMC5Lxut3ekjZU8FLd5GHsR47Q93BfxiO6yMuP9KqcHLQM7lXRAEAwceQfH3EZRNaGMZkonmwD1Rx2I6MuRC1R7Q7vxDKxBoO5a5530HN)VGdF30ZWHlmZ)PC6YNAwQkUY)zwKwi3hkZDdJQwgv9JvCIJJ)bkqXXRfyzRmXoS2vFRUdnB(owkThIOjB8UD2K4Ll0lqoKWBVrF90RRPfrdPS1RpfkU9PYDpo2MC(wqVoo2vbrAlszVW1VmCsILx0eoKQBTHLMEV6jHs(SSOO57MYYNloXKeJ1LUXa2j6216u59n8v9z9jPM9mjkxIgVEEpYPJLaE1G3VPBnsdegt3fQhFyA)k0ThlN2gAjhivGCl2)c2cuAup5nSAgSaVFPqvC7K0uUxz62Scp85NSnTwEke8tvT)H67KWoqJW0rUiSVrqYifA8Up1CJJ3QquWch(1qwit85tKjEhNYUHnkWOpA42bcCQZSBe6UbeQ(U4i03qj6n4E)a46WGgX(HZz7)6pQ(Mm9VHh(Xb4HovbmI(WqIIfdAXwdNm3aZSPdGJPyqlCo9IewChkFvDMzxWprY6)(IgwxPBk1wbXs74cACLofrSa0ntunaoftAX15zw96E1TTenW0Pwtpzb0MjrSMKZ1JvlX9327UB1m03OtgOV6Ev(0X)s)X8SZCIbJxMz4be4K3UZCgkQ(hwm(P6F9EF5XB2NwLnCUb3EacTqUuLXs9pM61nMyJSQNa1yXwdgR33qQkWTYi7b1pUD1CQ939)8UAgkLAtGT29(ZibMnJnBS0iUdpZcocpjxhBsuwm22dlVSCmVxzxo4ld]] )
spec:RegisterPack( "Protection", 20261016, [[Hekili:LA12UTnpm4NLD3kwr(ZXUTFuxG1nm01lkgMhWUt2kY0XcrrYqsodDyWp7JY2jr(uA72fTjHh(i5NiPezg57KWeQfipmF68RMnD2vKq7J5ajmNY2s3GFrs3H))RALfywUs6u9OqrtC(UUGlSFrsw3hgtoWipmB57NrcZ4jjqTvGHrc)Ssd7bDz8jylJ)bvR5ku4RZ1Q9CdkKkU4)lJ)eKcsdFpughAPsgCj(LmoiskJVvOyBlJlYrzFdXuUbTIktozrOGUZ5qHmXfXpO35IHXI1hGQTQY4vO(7aTIZCrqZ3Iy4m6JcG6I6p52m0LCQg)HgzLjijOvPCbYm0Q03mjxdm1U1uBa(NvarMmvH9sEAWRwxKMoXx6KI8Y7754Bc(VKdLAKPUsp6Exn(qeyQQ1O1ut2rHdHwHbIuPPrByjbZEEyJWSNZSk9Jr6I2WFiQUJGXG23MoWIYujo2SVVvCmRqRbP965tB51lICrh0fYO6Ffj4g7LU(5aQQIADYXQgKWooyUjyHVJmQq03ZnOXASr54XhcvqcGnvub)xC5gVulbAO3UABD(Ja4sZMM3oIB4pd2e3vfRQ788K3nblN2dYQjHiA1GWrDn1vqV8OrXy5INApCD5rt17lEs1y31R(9q60WokxAUEXqGNvnEI9NUPZNQMxn9PYVY7jH4ci3og)DwUJzJBVgYu4hpuTFeK01ciHC7HzD3wSUNOKqMMBXirjHN9CNyXaocSnCVZKfJyI3zGZSLDm7us0Tl4ee19nKqps0vPiARglOEmhAhwSnS654iVIzS6TtXmAn7hEVs8VUb7LWCR8yUwnH)BeiUYLwiSNJa9wQpej61Vn2sC)g22khk5hJ(9x)FEMBWv(9liNINd7n8rcEFWjipEhYq4D1ifK)Lf9t)oxL4a6TJMy9UaXR)V99o1lxIQFnLB9cI77gjb7EZtlFpm6v1gD8TdNRr6fxVJnV2Vl650eARtvAHnZn)EhSLl44R8AEe4fvQj)5d]] )
