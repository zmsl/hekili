if UnitClassBase( 'player' ) ~= 'DRUID' then return end

local addon, ns = ...
local Hekili = _G.Hekili or _G[ addon ]

if not Hekili.IsTBC() then return end

local class, state = Hekili.Class, Hekili.State
local strformat = string.format

local spec = Hekili:NewSpecialization( 11 )

spec:RegisterCombatLogEvent( function( _, subtype, _, sourceGUID, sourceName, _, _, destGUID, destName, destFlags, _, spellID, spellName )
    if sourceGUID ~= state.GUID then
        return
    end
end, false )

spec:RegisterUnitEvent( "UNIT_SPELLCAST_SUCCEEDED", "player", "target", function(event, unit, _, spellID )

end)

spec:RegisterUnitEvent( "UNIT_POWER_UPDATE", "player", "COMBO_POINTS", function(event, unit)

end)

local function rage_amount()
    local d = UnitDamage( "player" ) * 0.7
    local c = ( state.level > 70 and 1.4139 or 1 ) * ( 0.0091107836 * ( state.level ^ 2 ) + 3.225598133 * state.level + 4.2652911 )
    local f = 3.5
    local s = 2.5

    return min( ( 15 * d ) / ( 4 * c ) + ( f * s * 0.5 ), 15 * d / c )
end
local avg_rage_amount = rage_amount()
spec:RegisterHook( "reset_precast", function()
    if IsCurrentSpell( class.abilities.maul.id ) then
        start_maul()
        Hekili:Debug( "Starting Maul, next swing in %.2f...", buff.maul.remains)
    end

    avg_rage_amount = rage_amount()
end )

spec:RegisterStateExpr("rage_gain", function()
    return avg_rage_amount
end)

spec:RegisterStateExpr( "mainhand_remains", function()
    local next_swing, real_swing, pseudo_swing = 0, 0, 0
    if now == query_time then
        real_swing = nextMH - now
        next_swing = real_swing > 0 and real_swing or 0
    else
        if query_time <= nextMH then
            pseudo_swing = nextMH - query_time
        else
            pseudo_swing = (query_time - nextMH) % mainhand_speed
        end
        next_swing = pseudo_swing
    end
    return next_swing
end)

local dummy_names = {
    ["Combat Dummy"] = 1
}
local end_thresh = 10
spec:RegisterStateExpr("ttd", function()
    if dummy_names[target.name] then
        return Hekili.Version:match( "^Dev" ) and settings.dummy_ttd or 300
    end

    return target.time_to_die
end)

spec:RegisterStateExpr("combat_mode_group", function()
    local mode = settings.combat_mode
    if mode == "group" then return true end
    if mode == "solo"  then return false end
    -- dynamic modes
    if mode == "dynamic_everywhere" then
        return group
    elseif mode == "dynamic_raid" then
        return group and instanceType == "raid"
    else -- "dynamic_dungeon_raid" (default)
        return group and ( instanceType == "party" or instanceType == "raid" )
    end
end)

spec:RegisterStateExpr("combat_mode_solo", function()
    local mode = settings.combat_mode
    if mode == "solo"  then return true end
    if mode == "group" then return false end
    -- dynamic modes
    if mode == "dynamic_everywhere" then
        return not group
    elseif mode == "dynamic_raid" then
        return not ( group and instanceType == "raid" )
    else -- "dynamic_dungeon_raid" (default)
        return not ( group and ( instanceType == "party" or instanceType == "raid" ) )
    end
end)

spec:RegisterStateExpr("preferred_form_cat", function()
    return settings.preferred_form == "cat"
end)

spec:RegisterStateExpr("preferred_form_bear", function()
    return settings.preferred_form == "bear"
end)

-- Form Helper
spec:RegisterStateFunction( "swap_form", function( form )
    removeBuff( "form" )
    removeBuff( "maul" )

    if form == "bear_form" or form == "dire_bear_form" then
        spend( rage.current, "rage" )
        if talent.furor.rank == 5 then
            gain( 10, "rage" )
        end
        if set_bonus.wolfshead == 1 then
            gain( 5, "rage" )
        end
    elseif form == "cat_form" then
        if talent.furor.rank == 5 then
            gain( 40, "energy" )
        end
        if set_bonus.wolfshead == 1 then
            gain( 20, "energy" )
        end
    end

    if form then
        applyBuff( form )
    end
end )

-- Maul Helper
local finish_maul = setfenv( function()
    spend( (buff.clearcasting.up and 0) or ((15 - talent.ferocity.rank)), "rage" )
end, state )

spec:RegisterStateFunction( "start_maul", function()
    local next_swing = mainhand_remains
    if next_swing <= 0 then
        next_swing = mainhand_speed
    end
    applyBuff( "maul", next_swing )
    state:QueueAuraExpiration( "maul", finish_maul, buff.maul.expires )
end )

-- Gear
spec:RegisterGear( "wolfshead", 8345 )
spec:RegisterGear( "staff_of_natural_fury", 31334 )
spec:RegisterGear( "tier5_balance", 30231, 30232, 30233, 30234, 30235 )

-- Resources
spec:RegisterResource( Enum.PowerType.Rage, {
    enrage = {
        aura = "enrage",

        last = function ()
            local app = state.buff.enrage.applied
            local t = state.query_time

            return app + floor( t - app )
        end,

        interval = 1,
        value = 2,
    },

    mainhand = {
        swing = "mainhand",
        aura = "bear_form",

        last = function ()
            local swing = state.combat == 0 and state.now or state.swings.mainhand
            local t = state.query_time

            return swing + ( floor( ( t - swing ) / state.swings.mainhand_speed ) * state.swings.mainhand_speed )
        end,

        interval = "mainhand_speed",

        stop = function () return state.swings.mainhand == 0 end,
        value = function( now )
            return state.buff.maul.expires < now and rage_amount() or 0
        end,
    },
} )
spec:RegisterResource( Enum.PowerType.Mana )
spec:RegisterResource( Enum.PowerType.ComboPoints )
spec:RegisterResource( Enum.PowerType.Energy, {
    tick = {
        last = function ()
            local last_tick = state.energy.last_tick > 0 and state.energy.last_tick or state.now
            local elapsed_time = max(0, state.query_time - last_tick)
            local full_intervals = floor(elapsed_time / state.energy.tick_time_avg)
            local rtn = last_tick + (full_intervals * state.energy.tick_time_avg)
            return rtn
        end,

        interval = function()
            return state.energy.tick_time_avg
        end,

        stop = function ( val )
            return false
        end,
        value = function( now )
            return 20
        end,
    }
})

-- Talents
spec:RegisterTalents({
    starlight_wrath = { 762, 5, 16814, 16815, 16816, 16817, 16818 },
    natures_grasp = { 761, 1, 16689 },
    improved_natures_grasp = { 921, 4, 17245, 17247, 17248, 17249 },
    control_of_nature = { 787, 3, 16918, 16919, 16920 },
    focused_starlight = { 1822, 2, 35363, 35364 },
    improved_moonfire = { 763, 2, 16821, 16822 },
    brambles = { 782, 3, 16836, 16839, 16840 },
    insect_swarm = { 788, 1, 5570 },
    natures_reach = { 764, 2, 16819, 16820 },
    vengeance = { 792, 5, 16909, 16910, 16911, 16912, 16913 },
    celestial_focus = { 784, 3, 16850, 16923, 16924 },
    lunar_guidance = { 1782, 3, 33589, 33590, 33591 },
    natures_grace = { 789, 1, 16880 },
    moonglow = { 783, 3, 16845, 16846, 16847 },
    moonfury = { 790, 5, 16896, 16897, 16899, 16900, 16901 },
    balance_of_power = { 1783, 2, 33592, 33596 },
    dreamstate = { 1784, 3, 33597, 33599, 33956 },
    moonkin_form = { 793, 1, 24858 },
    improved_faerie_fire = { 1785, 3, 33600, 33601, 33602 },
    wrath_of_cenarius = { 1786, 5, 33603, 33604, 33605, 33606, 33607 },
    force_of_nature = { 1787, 1, 33831 },
    ferocity = { 796, 5, 16934, 16935, 16936, 16937, 16938 },
    feral_aggression = { 795, 5, 16858, 16859, 16860, 16861, 16862 },
    feral_instinct = { 799, 3, 16947, 16948, 16949 },
    brutal_impact = { 797, 2, 16940, 16941 },
    thick_hide = { 794, 3, 16929, 16930, 16931 },
    feline_swiftness = { 807, 2, 17002, 24866 },
    feral_charge = { 804, 1, 16979 },
    sharpened_claws = { 798, 3, 16942, 16943, 16944 },
    shredding_attacks = { 802, 2, 16966, 16968 },
    predatory_strikes = { 803, 3, 16972, 16974, 16975 },
    primal_fury = { 801, 2, 37116, 37117 },
    savage_fury = { 805, 2, 16998, 16999 },
    faerie_fire_feral = { 1162, 1, 16857 },
    nurturing_instinct = { 1792, 2, 33872, 33873 },
    heart_of_the_wild = { 808, 5, 17003, 17004, 17005, 17006, 24894 },
    survival_of_the_fittest = { 1794, 3, 33853, 33855, 33856 },
    primal_tenacity = { 1793, 3, 33851, 33852, 33957 },
    leader_of_the_pack = { 809, 1, 17007 },
    improved_leader_of_the_pack = { 1798, 2, 34297, 34300 },
    predatory_instincts = { 1795, 5, 33859, 33866, 33867, 33868, 33869 },
    mangle = { 1796, 1, 33917 },
    improved_mark_of_the_wild = { 821, 5, 17050, 17051, 17053, 17054, 17055 },
    furor = { 822, 5, 17056, 17058, 17059, 17060, 17061 },
    naturalist = { 824, 5, 17069, 17070, 17071, 17072, 17073 },
    natures_focus = { 823, 5, 17063, 17065, 17066, 17067, 17068 },
    natural_shapeshifter = { 826, 3, 16833, 16834, 16835 },
    intensity = { 829, 3, 17106, 17107, 17108 },
    subtlety = { 841, 5, 17118, 17119, 17120, 17121, 17122 },
    omen_of_clarity = { 827, 1, 16864 },
    tranquil_spirit = { 843, 5, 24968, 24969, 24970, 24971, 24972 },
    improved_rejuvenation = { 830, 3, 17111, 17112, 17113 },
    natures_swiftness = { 831, 1, 17116 },
    gift_of_nature = { 828, 5, 17104, 24943, 24944, 24945, 24946 },
    improved_tranquility = { 842, 2, 17123, 17124 },
    empowered_touch = { 1788, 2, 33879, 33880 },
    improved_regrowth = { 825, 5, 17074, 17075, 17076, 17077, 17078 },
    living_spirit = { 1797, 3, 34151, 34152, 34153 },
    swiftmend = { 844, 1, 18562 },
    natural_perfection = { 1790, 3, 33881, 33882, 33883 },
    empowered_rejuvenation = { 1789, 5, 33886, 33887, 33888, 33889, 33890 },
    tree_of_life = { 1791, 1, 33891 },
})

-- Auras
spec:RegisterAuras( {
    -- Attempts to cure $3137s1 poison every $t1 seconds.
    abolish_poison = {
        id = 2893,
        duration = 8,
        tick_time = 2,
        max_stack = 1,
    },
    -- Immune to Polymorph effects.  Increases swim speed by $5421s1% and allows underwater breathing.
    aquatic_form = {
        id = 1066,
        duration = 3600,
        max_stack = 1,
    },
    -- All damage taken is reduced by $s2%.  While protected, damaging attacks will not cause spellcasting delays.
    barkskin = {
        id = 22812,
        duration = 12,
        max_stack = 1,
    },
    -- Stunned.
    bash = {
        id = 5211,
        duration = function() return 2 + ( 0.5 * talent.brutal_impact.rank ) end,
        max_stack = 1,
        copy = { 5211, 6798, 8983 },
    },
    bear_form = {
        id = 5487,
        duration = 3600,
        max_stack = 1,
        copy = { 5487, 9634 }
    },
    -- Immunity to Polymorph effects.  Increases melee attack power by $3025s1 plus Agility.
    cat_form = {
        id = 768,
        duration = 3600,
        max_stack = 1,
    },
    -- Taunted.
    challenging_roar = {
        id = 5209,
        duration = 6,
        max_stack = 1,
    },
    -- Your next damage or healing spell or offensive ability has its mana, rage or energy cost reduced by $s1%.
    clearcasting = {
        id = 16870,
        duration = 15,
        max_stack = 1,
    },
    -- Increases movement speed by $s1% while in Cat Form.
    dash = {
        id = 1850,
        duration = 15,
        max_stack = 1,
        copy = { 1850, 9821, 33357 },
    },
    -- Decreases melee attack power by $s1.
    demoralizing_roar = {
        id = 48560,
        duration = 30,
        max_stack = 1,
        copy = { 99, 1735, 9490, 9747, 9898, 26998 },
    },
    -- Immune to Polymorph effects.  Increases melee attack power by $9635s3, armor contribution from cloth and leather items by $9635s1%, and Stamina by $9635s2%.
    dire_bear_form = {
        id = 9634,
        duration = 3600,
        max_stack = 1,
    },
    -- Gain $/10;s1 rage per second.  Base armor reduced.
    enrage = {
        id = 5229,
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    -- Rooted.  Causes $s2 Nature damage every $t2 seconds.
    entangling_roots = {
        id = 339,
        duration = 12,
        max_stack = 1,
        copy = { 339, 1062, 5195, 5196, 9852, 9853, 26989 },
    },
    feline_grace = {
        id = 20719,
        duration = 3600,
        max_stack = 1,
    },
    feral_aggression = {
        id = 16858,
        duration = 3600,
        max_stack = 1,
        copy = { 16862, 16861, 16860, 16859, 16858 },
    },
    -- Immobilized.
    feral_charge_effect = {
        id = 19675,
        duration = 4,
        max_stack = 1,
    },
    form = {
        alias = { "aquatic_form", "cat_form", "bear_form", "dire_bear_form", "moonkin_form", "travel_form", "tree_of_life" },
        aliasType = "buff",
        aliasMode = "first"
    },
    -- Converting rage into health.
    frenzied_regeneration = {
        id = 22842,
        duration = 10,
        tick_time = 1,
        max_stack = 1,
        copy = { 22842, 22895, 22896, 26999 },
    },
    -- Taunted.
    growl = {
        id = 6795,
        duration = 3,
        max_stack = 1,
    },
    -- Asleep.
    hibernate = {
        id = 2637,
        duration = 20,
        max_stack = 1,
        copy = { 2637, 18657, 18658 },
    },
    -- $42231s1 damage every $t3 seconds, and time between attacks increased by $s2%.$?$w1<0[ Movement slowed by $w1%.][]
    hurricane = {
        id = 16914,
        duration = function() return 10 * haste end,
        tick_time = function() return 1 * haste end,
        max_stack = 1,
        copy = { 16914, 17401, 17402, 27012 },
    },
    improved_moonfire = {
        id = 16821,
        duration = 3600,
        max_stack = 1,
        copy = { 16822, 16821 },
    },
    improved_rejuvenation = {
        id = 17111,
        duration = 3600,
        max_stack = 1,
        copy = { 17113, 17112, 17111 },
    },
    -- Regenerating mana.
    innervate = {
        id = 29166,
        duration = 20,
        tick_time = 1,
        max_stack = 1,
    },
    -- Chance to hit with melee and ranged attacks decreased by $s2% and $s1 Nature damage every $t1 sec.
    insect_swarm = {
        id = 5570,
        duration = 12,
        tick_time = 2,
        max_stack = 1,
        shared = "target",
        copy = { 5570, 24974, 24975, 24976, 24977, 27013 },
    },
    maul = {
        duration = function () return swings.mainhand_speed end,
        max_stack = 1,
    },
    -- $s1 Arcane damage every $t1 seconds.
    moonfire = {
        id = 8921,
        duration = function() return set_bonus.tier5_balance >= 4 and 15 or 12 end,
        tick_time = 3,
        max_stack = 1,
        copy = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835, 26987, 26988 },
    },
    -- Increases spell critical chance by $s1%.
    moonkin_aura = {
        id = 24907,
        duration = 3600,
        max_stack = 1,
    },
    -- Immune to Polymorph effects.  Armor contribution from items is increased by $24905s1%.  Damage taken while stunned reduced $69366s1%.  Single target spell criticals instantly regenerate $53506s1% of your total mana.
    moonkin_form = {
        id = 24858,
        duration = 3600,
        max_stack = 1,
    },
    -- Reduces all damage taken by $s1%.
    natural_perfection = {
        id = 45283,
        duration = 8,
        max_stack = 3,
        copy = { 45281, 45282, 45283 },
    },
    natural_shapeshifter = {
        id = 16833,
        duration = 6,
        max_stack = 1,
        copy = { 16835, 16834, 16833 },
    },
    -- Spell casting speed increased by $s1%.
    natures_grace = {
        id = 16886,
        duration = 15,
        max_stack = 1,
    },
    -- Melee damage you take has a chance to entangle the enemy.
    natures_grasp = {
        id = 16689,
        duration = 45,
        max_stack = 1,
        copy = { 16689, 16810, 16811, 16812, 16813, 17329, 27009 },
    },
    -- Your next Nature spell will be an instant cast spell.
    natures_swiftness = {
        id = 17116,
        duration = 3600,
        max_stack = 1,
    },
    -- Your next damage or healing spell or offensive ability has its mana, rage or energy cost reduced by $s1%.
    omen_of_clarity = {
        id = 16864,
        duration = 1800,
        max_stack = 1,
    },
    -- Stunned.
    pounce = {
        id = 9005,
        duration = 3,
        max_stack = 1,
        copy = { 9005, 9823, 9827, 27006 },
    },
    -- Bleeding for $s1 damage every $t1 seconds.
    pounce_bleed = {
        id = 9007,
        duration = 18,
        tick_time = 3,
        max_stack = 1,
        copy = { 9007, 9824, 9826, 27007 },
    },
    -- Stealthed.  Movement speed slowed by $s2%.
    prowl = {
        id = 5215,
        duration = 3600,
        max_stack = 1,
        copy = { 5215, 6783, 9913 }
    },
    -- Bleeding for $s2 damage every $t2 seconds.
    rake = {
        id = 1822,
        duration = 9,
        max_stack = 1,
        copy = { 1822, 1823, 1824, 9904, 27003 },
    },
	    -- Bleeding for $s2 damage every $t2 seconds.
    lacerate = {
        id = 33745,
        duration = 15,
        max_stack = 5,
    },
    -- Heals $s2 every $t2 seconds.
    regrowth = {
        id = 8936,
        duration = 21,
        max_stack = 1,
        copy = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858, 26980 },
    },
    -- Heals $s1 damage every $t1 seconds.
    rejuvenation = {
        id = 774,
        duration = 12,
        tick_time = 3,
        max_stack = 1,
        copy = { 774, 1058, 1430, 2090, 2091, 3627, 8070, 8910, 9839, 9840, 9841, 25299, 26981, 26982 },
    },
    -- Bleed damage every $t1 seconds.
    rip = {
        id = 1079,
        duration = 12,
        tick_time = 2,
        max_stack = 1,
        copy = { 1079, 9492, 9493, 9752, 9894, 9896, 27008 },
    },
    sharpened_claws = { -- TODO: Check Aura (https://wowhead.com/wotlk/spell=16944)
        id = 16942,
        duration = 3600,
        max_stack = 1,
        copy = { 16944, 16943, 16942 },
    },
    -- Reduced distance at which target will attack.
    soothe_animal = {
        id = 2908,
        duration = 15,
        max_stack = 1,
        copy = { 2908, 8955, 9901, 26995 },
    },
    -- Causes $s1 Nature damage to attackers.
    thorns = {
        id = 467,
        duration = 600,
        max_stack = 1,
        shared = "player",
        copy = { 467, 782, 1075, 8914, 9756, 9910, 26992 },
    },
    -- Increases damage done by $s1.
    tigers_fury = {
        id = 5217,
        duration = 6,
        max_stack = 1,
        copy = { 5217, 6793, 9845, 9846 },
    },
    -- Tracking humanoids.
    track_humanoids = {
        id = 5225,
        duration = 3600,
        max_stack = 1,
    },
    -- Heals nearby party members for $s1 every $t2 seconds.
    tranquility = {
        id = 740,
        duration = 10,
        tick_time = 2,
        max_stack = 1,
        copy = { 740, 8918, 9862, 9863, 26983 },
    },
    -- Immune to Polymorph effects.  Movement speed increased by $5419s1%.
    travel_form = {
        id = 783,
        duration = 3600,
        max_stack = 1,
    },
    -- Increases healing done by 20%.
    tree_of_life = {
        id = 33891,
        duration = 3600,
        max_stack = 1,
    },
    -- Stunned.
    war_stomp = {
        id = 20549,
        duration = 2,
        max_stack = 1,
    },
    rupture = {
        id = 1943,
        duration = 6,
        max_stack = 1,
        shared = "target",
        copy = { 1943, 8639, 8640, 11273, 11274, 11275, 26867 }
    },
    garrote = {
        id = 703,
        duration = 18,
        max_stack = 1,
        shared = "target",
        copy = { 703, 8631, 8632, 8633, 11289, 11290, 26839, 26884 }
    },
    rend = {
        id = 772,
        duration = 21,
        max_stack = 1,
        shared = "target",
        copy = { 772, 6546, 6547, 6548, 11572, 11573, 11574, 25208 }
    },
    deep_wound = {
        id = 12834,
        duration = 12,
        max_stack = 1,
        shared = "target",
        copy = { 12834, 12849, 12867, 12162 }
    },
    bleed = {
        alias = { "lacerate", "pounce_bleed", "rip", "rake", "deep_wound", "rend", "garrote", "rupture" },
        aliasType = "debuff",
        aliasMode = "longest"
    }
} )

-- Abilities
spec:RegisterAbilities( {
    -- Attempts to cure 1 poison effect on the target, and 1 more poison effect every 3 seconds for 12 sec.
    abolish_poison = {
        id = 2893,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 0.13,
        spendType = "mana",

        startsCombat = true,
        texture = 136068,

        handler = function ()
        end,
    },


    -- Shapeshift into aquatic form, increasing swim speed by 50% and allowing the druid to breathe underwater.  Also protects the caster from Polymorph effects.    The act of shapeshifting frees the caster of Polymorph and Movement Impairing effects.
    aquatic_form = {
        id = 1066,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            local base = set_bonus.staff_of_natural_fury == 1 and max(0, 0.13 - 200 / mana.modmax) or 0.13
            return base * (1 - (talent.natural_shapeshifter.rank * 0.1))
        end,
        spendType = "mana",

        startsCombat = true,
        texture = 132112,

        handler = function ()
            swap_form( "aquatic_form" )
        end,
    },


    -- The druid's skin becomes as tough as bark.  All damage taken is reduced by 20%.  While protected, damaging attacks will not cause spellcasting delays.  This spell is usable while stunned, frozen, incapacitated, feared or asleep.  Usable in all forms.  Lasts 12 sec.
    barkskin = {
        id = 22812,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        startsCombat = true,
        texture = 136097,

        toggle = "cooldowns",

        handler = function ()
        end,
    },


    -- Stuns the target for 4 sec and interrupts non-player spellcasting for 3 sec.
    bash = {
        id = 5211,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = function() return (buff.clearcasting.up and 0) or 10 end,
        spendType = "rage",

        startsCombat = true,
        texture = 132114,

        toggle = "cooldowns",

        handler = function ()
            removeBuff( "clearcasting" )
        end,

        copy = { 5211, 6798, 8983 }
    },


    -- Shapeshift into cat form, increasing melee attack power by 160 plus Agility.  Also protects the caster from Polymorph effects and allows the use of various cat abilities.    The act of shapeshifting frees the caster of Polymorph and Movement Impairing effects.
    cat_form = {
        id = 768,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            local base = set_bonus.staff_of_natural_fury == 1 and max(0, 0.35 - 200 / mana.modmax) or 0.35
            return base * (1 - (talent.natural_shapeshifter.rank * 0.1))
        end,
        spendType = "mana",

        startsCombat = true,
        texture = 132115,

        handler = function ()
            swap_form( "cat_form" )
        end,
    },


    -- Forces all nearby enemies within 10 yards to focus attacks on you for 6 sec.
    challenging_roar = {
        id = 5209,
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        spend = 15,
        spendType = "rage",

        startsCombat = true,
        texture = 132117,

        toggle = "cooldowns",

        handler = function ()
        end,
    },


    -- Claw the enemy, causing 370 additional damage.  Awards 1 combo point.
    claw = {
        id = 1082,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function() return ((buff.clearcasting.up and 0) or 45) - talent.ferocity.rank end,
        spendType = "energy",

        startsCombat = true,
        texture = 132140,

        handler = function ()
            removeBuff( "clearcasting" )
            gain( 1, "combo_points" )
        end,

        copy = { 1082, 3029, 5201, 9849, 9850, 27000 }
    },
	
	
	-- Mangle (Bear)
mangle_bear = {
    id = 33986,
    cast = 0,
    cooldown = 6,
    gcd = "totem",

    spend = function() return ((buff.clearcasting.up and 0) or 20) - talent.ferocity.rank end,
    spendType = "rage",

    startsCombat = true,
    texture = 132135,

    handler = function ()
        applyDebuff( "target", "mangle_bear" )
		removeBuff( "clearcasting" )
    end,

    copy = { 33986, 33987, 33878 }
},


	-- Mangle (Cat)
mangle_cat = {
    id = 33983,
    cast = 0,
    cooldown = 0,
    gcd = "totem",

    spend = function() return ((buff.clearcasting.up and 0) or 45) - talent.ferocity.rank end,
    spendType = "energy",

    startsCombat = true,
    texture = 132135,

    handler = function ()
        gain( 1, "combo_points" )
        applyDebuff( "target", "mangle_cat" )
		removeBuff( "clearcasting" )
    end,

    copy = { 33983, 33876, 33982 }
},


-- Lacerate
lacerate = {
    id = 33745,
    cast = 0,
    cooldown = 0,
    gcd = "totem",

    spend = function() return ((buff.clearcasting.up and 0) or 15) - talent.shredding_attacks.rank end,
    spendType = "rage",

    startsCombat = true,
    texture = 132131,

    handler = function ()
        applyDebuff( "target", "lacerate", nil, min( 5, debuff.lacerate.stack + 1 ) )
        removeBuff( "clearcasting" )
    end,

    copy = { 33745 }
},


    -- Cower, causing no damage but lowering your threat a large amount, making the enemy less likely to attack you.
    cower = {
        id = 8998,
        cast = 0,
        cooldown = 10,
        gcd = "totem",

        spend = 20,
        spendType = "energy",

        startsCombat = true,
        texture = 132118,

        handler = function ()
        end,

        copy = { 8998, 9000, 9892, 31709, 27004 }
    },


    -- Cures 1 poison effect on the target.
    cure_poison = {
        id = 8946,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 0.13,
        spendType = "mana",

        startsCombat = true,
        texture = 136067,

        handler = function ()
        end,
    },


    -- Increases movement speed by 70% while in Cat Form for 15 sec.  Does not break prowling.
    dash = {
        id = 1850,
        cast = 0,
        cooldown = 300,
        gcd = "off",

        spend = 0,
        spendType = "energy",

        startsCombat = true,
        texture = 132120,

        toggle = "cooldowns",

        handler = function ()
        end,

        copy = { 1850, 9821, 33357 }
    },


    -- The druid roars, decreasing nearby enemies' melee attack power by 411.  Lasts 30 sec.
    demoralizing_roar = {
        id = 99,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function() return (buff.clearcasting.up and 0) or 10 end,
        spendType = "rage",

        startsCombat = true,
        texture = 132121,

        handler = function ()
            removeBuff( "clearcasting" )
            applyDebuff( "target", "demoralizing_roar" )
        end,

        copy = { 99, 1735, 9490, 9747, 9898, 26998 }
    },


    -- Shapeshift into dire bear form, increasing melee attack power, armor contribution from cloth and leather items, and Stamina. Also protects the caster from Polymorph effects and allows the use of various bear abilities. The act of shapeshifting frees the caster of Polymorph and Movement Impairing effects.
    dire_bear_form = {
        id = 9634,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            local base = set_bonus.staff_of_natural_fury == 1 and max(0, 0.35 - 200 / mana.modmax) or 0.35
            return base * (1 - (talent.natural_shapeshifter.rank * 0.1))
        end,
        spendType = "mana",

        startsCombat = true,
        texture = 132276,

        handler = function ()
            swap_form( "dire_bear_form" )
        end,

        copy = { 5487, 9634, "bear_form" }
    },


    -- Generates 20 rage, and then generates an additional 10 rage over 10 sec, but reduces base armor by 27% in Bear Form and 16% in Dire Bear Form.
    enrage = {
        id = 5229,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        spend = 0,
        spendType = "rage",

        startsCombat = true,
        texture = 132126,

        toggle = "cooldowns",

        handler = function ()
            gain( 20 + ( { 0, 4, 7, 10 } )[ talent.intensity.rank + 1 ], "rage" )
            applyBuff( "enrage" )
        end,
    },

    -- Roots the target in place and causes 20 Nature damage over 12 sec.  Damage caused may interrupt the effect.
    entangling_roots = {
        id = 339,
        cast = function() return buff.natures_swiftness.up and 0 or 1.5 - (buff.natures_grace.up and 0.5 or 0) end,
        cooldown = 0,
        gcd = "spell",

        spend = function() return (buff.clearcasting.up and 0) or 0.07 end,
        spendType = "mana",

        startsCombat = true,
        texture = 136100,

        handler = function ()
            removeBuff( "clearcasting" )
            removeBuff( "natures_swiftness" )
            applyDebuff( "target", "entangling_roots", 27 )
        end,

        copy = { 339, 1062, 5195, 5196, 9852, 9853, 26989 },
    },


    -- Decrease the armor of the target by 5% for 5 min.  While affected, the target cannot stealth or turn invisible.
    faerie_fire = {
        id = 770,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        cycle = "faerie_fire",

        spend = 0.08,
        spendType = "mana",

        startsCombat = true,
        texture = 136033,

        handler = function ()
            removeDebuff( "armor_reduction" )
            removeBuff( "natures_grace" )
            applyDebuff( "target", "faerie_fire", 300 )
        end,

        copy = { 770, 778, 9749, 9907, 26993 }
    },


    -- Decrease the armor of the target by 5% for 5 min.  While affected, the target cannot stealth or turn invisible.  Deals 26 damage and additional threat when used in Bear Form or Dire Bear Form.
    faerie_fire_feral = {
        id = 16857,
        cast = 0,
        cooldown = 6,
        gcd = "totem",

        spend = 0,
        spendType = "energy",

        startsCombat = true,
        texture = 136033,

        handler = function ()
            removeDebuff( "armor_reduction" )
            applyDebuff( "target", "faerie_fire_feral", 300 )
        end,

        copy = { 16857, 17390, 17391, 17392, 27011 }
    },


    -- Finishing move that causes damage per combo point and converts each extra point of energy (up to a maximum of 30 extra energy) into 9.8 additional damage.  Damage is increased by your attack power.     1 point  : 422-562 damage     2 points: 724-864 damage     3 points: 1025-1165 damage     4 points: 1327-1467 damage     5 points: 1628-1768 damage
    ferocious_bite = {
        id = 22568,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function() return (buff.clearcasting.up and 0) or 35 end,
        spendType = "energy",

        startsCombat = true,
        texture = 132127,

        usable = function() return combo_points.current > 0, "requires combo_points" end,

        handler = function ()
            removeBuff( "clearcasting" )
            spend( combo_points.current, "combo_points" )
            spend( energy.current, "energy" )
        end,

        copy = { 22568, 22827, 22828, 22829, 31018, 24248 }
    },


    -- Summons 3 Treants to attack nearby enemies for 30 sec.
    force_of_nature = {
        id = 33831,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 0.12,
        spendType = "mana",

        talent = "force_of_nature",
        startsCombat = true,
        texture = 132129,

        handler = function ()
        end,
    },


    -- Converts up to 10 rage per second into health for 10 sec.  Each point of rage is converted into 0.3% of max health.
    frenzied_regeneration = {
        id = 22842,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 0,
        spendType = "rage",

        startsCombat = true,
        texture = 132091,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "frenzied_regeneration" )
        end,

        copy = { 22842, 22895, 22896, 26999 }
    },


    -- Gives the Gift of the Wild to all party and raid members, increasing armor by 240, all attributes by 10 and all resistances by 15 for 1 |4hour:hrs;.
    gift_of_the_wild = {
        id = 21849,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 0.64,
        spendType = "mana",

        startsCombat = true,
        texture = 136038,

        handler = function ()
            applyBuff( "gift_of_the_wild" )
            swap_form( "" )
        end,

        copy = { 21849, 21850, 26991 },
    },


    -- Taunts the target to attack you, but has no effect if the target is already attacking you.
    growl = {
        id = 6795,
        cast = 0,
        cooldown = 10,
        gcd = "off",

        spend = 0,
        spendType = "rage",

        startsCombat = true,
        texture = 132270,

        handler = function ()
        end,
    },


    -- Heals a friendly target for 40 to 55.
    healing_touch = {
        id = 5185,
        cast = function() return buff.natures_swiftness.up and 0 or 3.5 - (buff.natures_grace.up and 0.5 or 0) - (talent.naturalist.rank * 0.1) end,
        cooldown = 0,
        gcd = "spell",

        spend = function() return 0.17 * (1 - (talent.moonglow.rank * 0.03)) * (1 - (talent.tranquil_spirit.rank * 0.02)) end,
        spendType = "mana",

        usable = function() return buff.moonkin_form.down end,

        startsCombat = true,
        texture = 136041,

        handler = function ()
            removeBuff( "clearcasting" )
            removeBuff( "natures_swiftness" )
        end,

        copy = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297, 26978, 26979 },
    },


    -- Forces the enemy target to sleep for up to 20 sec.  Any damage will awaken the target.  Only one target can be forced to hibernate at a time.  Only works on Beasts and Dragonkin.
    hibernate = {
        id = 2637,
        cast = function() return buff.natures_swiftness.up and 0 or 1.5 - (buff.natures_grace.up and 0.5 or 0) end,
        cooldown = 0,
        gcd = "spell",

        spend = 0.07,
        spendType = "mana",

        startsCombat = true,
        texture = 136090,

        handler = function ()
            removeBuff( "natures_swiftness" )
        end,

        copy = { 2637, 18657, 18658 },
    },


    -- Creates a violent storm in the target area causing 101 Nature damage to enemies every 1 sec, and increasing the time between attacks of enemies by 20%.  Lasts 10 sec.  Druid must channel to maintain the spell.
    hurricane = {
        id = 16914,
        cast = function() return 10 * haste end,
        channeled = true,
        breakable = true,
        cooldown = 60,
        gcd = "spell",

        spend = function() return (buff.clearcasting.up and 0) or 0.81 end,
        spendType = "mana",

        startsCombat = true,
        texture = 136018,

        aura = "hurricane",
        tick_time = function () return class.auras.hurricane.tick_time end,

        start = function ()
            removeBuff( "natures_grace" )
            applyDebuff( "target", "hurricane" )
        end,

        tick = function ()
        end,

        breakchannel = function ()
            removeDebuff( "target", "hurricane" )
        end,

        handler = function ()
            removeBuff( "clearcasting" )
        end,

        copy = { 16914, 17401, 17402, 27012 },
    },


    -- Causes the target to regenerate mana equal to 225% of the casting Druid's base mana pool over 10 sec.
    innervate = {
        id = 29166,
        cast = 0,
        cooldown = 360,
        gcd = "spell",

        startsCombat = true,
        texture = 136048,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "innervate" )
            swap_form( "" )
        end,
    },


    -- The enemy target is swarmed by insects, decreasing their chance to hit by 3% and causing 144 Nature damage over 12 sec.
    insect_swarm = {
        id = 5570,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function() return (buff.clearcasting.up and 0) or 0.08 end,
        spendType = "mana",

        talent = "insect_swarm",
        startsCombat = true,
        texture = 136045,

        handler = function ()
            applyDebuff( "target", "insect_swarm" )
            removeBuff( "clearcasting" )
            removeBuff( "natures_grace" )
        end,

        copy = { 5570, 24974, 24975, 24976, 24977, 27013 }
    },

    -- A strong attack that increases melee damage and causes a high amount of threat. Effects which increase Bleed damage also increase Maul damage.
    maul = {
        id = 6807,
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = function()
            return (buff.clearcasting.up and 0) or (15 - talent.ferocity.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        texture = 132136,

        nobuff = "maul",

        usable = function() return not buff.maul.up end,
        readyTime = function() return buff.maul.expires end,

        handler = function( rank )
            gain( (buff.clearcasting.up and 0) or (15 - talent.ferocity.rank), "rage" )
            start_maul()
        end,

        copy = { 6807, 6808, 6809, 8972, 9745, 9880, 9881, 26996 }
    },


    -- Increases the friendly target's armor by 25 for 30 min.
    mark_of_the_wild = {
        id = 1126,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend =  0.24,
        spendType = "mana",

        startsCombat = true,
        texture = 136078,

        handler = function ()
            applyBuff( "mark_of_the_wild" )
        end,

        copy = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990 },
    },


    -- Burns the enemy for 9 to 12 Arcane damage and then an additional 12 Arcane damage over 9 sec.
    moonfire = {
        id = 8921,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        min_ttd = 12,

        spend = function()
            local base = buff.clearcasting.up and 0 or 0.21
            base = base * ( 1 - talent.moonglow.rank * 0.03 )
            base = base * ( buff.moonkin_form.up and 0.5 or 1 )
            if set_bonus.tier5_balance >= 4 then base = base * 0.7 end
            return base
        end,
        spendType = "mana",

        cycle = "moonfire",

        startsCombat = true,
        texture = 136096,

        handler = function ()
            removeBuff( "clearcasting" )
            removeBuff( "natures_grace" )
            applyDebuff( "target", "moonfire" )
        end,

        copy = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835, 26987, 26988 },
    },


    -- Shapeshift into Moonkin Form.  While in this form the armor contribution from items is increased by 370%, damage taken while stunned is reduced by 15%, and all party and raid members within 100 yards have their spell critical chance increased by 5%.  Single target spell critical strikes in this form instantly regenerate 2% of your total mana.  The Moonkin can not cast healing or resurrection spells while shapeshifted.    The act of shapeshifting frees the caster of Polymorph and Movement Impairing effects.
    moonkin_form = {
        id = 24858,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            local base = set_bonus.staff_of_natural_fury == 1 and max(0, 0.22 - 200 / mana.modmax) or 0.22
            return base * (1 - (talent.natural_shapeshifter.rank * 0.1))
        end,
        spendType = "mana",

        talent = "moonkin_form",
        startsCombat = true,
        texture = 136036,

        handler = function ()
            swap_form( "moonkin_form" )
        end,
    },


    -- While active, any time an enemy strikes the caster they have a 100% chance to become afflicted by Entangling Roots (Rank 1). 3 charges.  Lasts 45 sec.
    natures_grasp = {
        id = 16689,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        startsCombat = true,
        texture = 136063,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "natures_grasp" )
        end,

        copy = { 16689, 16810, 16811, 16812, 16813, 17329, 27009 },
    },


    -- When activated, your next Nature spell with a base casting time less than 10 sec. becomes an instant cast spell.
    natures_swiftness = {
        id = 17116,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        talent = "natures_swiftness",
        startsCombat = true,
        texture = 136076,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "natures_swiftness" )
        end,
    },


    -- When activated, your next Nature spell with a base casting time less than 10 sec. becomes an instant cast spell.
    omen_of_clarity = {
        id = 16864,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 120,
        spendType = "mana",

        talent = "omen_of_clarity",
        startsCombat = false,
        texture = 136017,

        handler = function ()
            applyBuff( "omen_of_clarity" )
        end,
    },


    -- Pounce, stunning the target for 3 sec and causing 2100 damage over 18 sec.  Must be prowling.  Awards 1 combo point.
    pounce = {
        id = 9827,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function() return (buff.clearcasting.up and 0) or 50 end,
        spendType = "energy",

        startsCombat = true,
        texture = 132142,

        buff = "prowl",

        handler = function ()
            setDistance( 0 )
            removeBuff( "clearcasting" )
            removeBuff( "prowl" )
            applyDebuff( "target", "pounce", 3)
            applyDebuff( "target", "pounce_bleed", 18 )
            gain( 1, "combo_points" )
        end,

        copy = { 9005, 9823, 9827, 27006 }
    },


    -- Allows the Druid to prowl around, but reduces your movement speed by 30%.  Lasts until cancelled.
    prowl = {
        id = 5215,
        cast = 0,
        cooldown = 10,
        gcd = "off",

        spend = 0,
        spendType = "energy",

        startsCombat = true,
        texture = 132089,

        handler = function ()
            applyBuff( "prowl" )
        end,

        copy = { 5215, 6783, 9913 }
    },


    -- Rake the target for 178 bleed damage and an additional 1104 damage over 9 sec.  Awards 1 combo point.
    rake = {
        id = 1822,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function () return (buff.clearcasting.up and 0) or (40 - talent.ferocity.rank) end,
        spendType = "energy",

        startsCombat = true,
        texture = 132122,

        readyTime = function() return debuff.rake.remains end,

        handler = function ()
            applyDebuff( "target", "rake" )
            removeBuff( "clearcasting" )
            gain( 1, "combo_points" )
        end,

        copy = { 1822, 1823, 1824, 9904, 27003 }
    },


    -- Ravage the target, causing 385% damage plus 1771 to the target.  Must be prowling and behind the target.  Awards 1 combo point.
    ravage = {
        id = 6785,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function() return (buff.clearcasting.up and 0) or 60 end,
        spendType = "energy",

        startsCombat = true,
        texture = 132141,

        buff = "prowl",

        handler = function ()
            removeBuff( "clearcasting" )
            gain( 1, "combo_points" )
        end,

        copy = { 6785, 6787, 9866, 9867, 27005 }
    },


    -- Returns the spirit to the body, restoring a dead target to life with 400 health and 700 mana.
    rebirth = {
        id = 20484,
        cast = function() return buff.natures_swiftness.up and 0 or 2 - (buff.natures_grace.up and 0.5 or 0) end,
        cooldown = 1800,
        gcd = "spell",

        spend = 0.68,
        spendType = "mana",

        startsCombat = true,
        texture = 136080,

        toggle = "cooldowns",

        handler = function ()
            removeBuff( "natures_swiftness" )
        end,

        copy = { 20484, 20739, 20742, 20747, 20748, 26994 },
    },


    -- Heals a friendly target for 93 to 107 and another 98 over 21 sec.
    regrowth = {
        id = 8936,
        cast = function() return buff.natures_swiftness.up and 0 or 2 - (buff.natures_grace.up and 0.5 or 0) end,
        cooldown = 0,
        gcd = "spell",

        spend = function() return ((buff.clearcasting.up and 0) or 0.29) * (1 - (talent.moonglow.rank * 0.03)) end,
        spendType = "mana",

        usable = function() return buff.moonkin_form.down end,

        startsCombat = true,
        texture = 136085,

        handler = function ()
            removeBuff( "clearcasting" )
            removeBuff( "natures_swiftness")
        end,

        copy = { 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858, 26980 },
    },


    -- Heals the target for 40 over 15 sec.
    rejuvenation = {
        id = 774,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function() return ((buff.clearcasting.up and 0) or 0.18) * (1 - (talent.moonglow.rank * 0.03)) end,
        spendType = "mana",

        usable = function() return buff.moonkin_form.down end,

        startsCombat = true,
        texture = 136081,

        handler = function ()
            removeBuff( "clearcasting" )
        end,

        copy = { 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299, 26981, 26982 },
    },


    -- Dispels 1 Curse from a friendly target.
    remove_curse = {
        id = 2782,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 0.08,
        spendType = "mana",

        startsCombat = true,
        texture = 135952,

        handler = function ()
        end,
    },


    -- Finishing move that causes damage over time.  Damage increases per combo point and by your attack power:     1 point: 784 damage over 12 sec.     2 points: 1352 damage over 12 sec.     3 points: 1920 damage over 12 sec.     4 points: 2488 damage over 12 sec.     5 points: 3056 damage over 12 sec.
    rip = {
        id = 1079,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function () return buff.clearcasting.up and 0 or 30 end,
        spendType = "energy",

        startsCombat = true,
        texture = 132152,

        usable = function() return combo_points.current > 0, "requires combo_points" end,
        readyTime = function() return debuff.rip.remains end, -- Clipping rip is a DPS loss and an unpredictable recommendation. AP snapshot on previous rip will prevent overriding

        handler = function ()
            applyDebuff( "target", "rip" )
            removeBuff( "clearcasting" )
            spend( combo_points.current, "combo_points" )
        end,

        copy = { 1079, 9492, 9493, 9752, 9894, 9896, 27008 }
    },


    -- Shred the target, causing 225% damage plus 666 to the target.  Must be behind the target.  Awards 1 combo point.  Effects which increase Bleed damage also increase Shred damage.
    shred = {
        id = 5221,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function () return (buff.clearcasting.up and 0) or (60 - (talent.shredding_attacks.rank * 9)) end,
        spendType = "energy",

        startsCombat = true,
        texture = 136231,

        handler = function ()
            gain( 1, "combo_points" )
            removeBuff( "clearcasting" )
        end,

        copy = { 5221, 6800, 8992, 9829, 9830, 27001, 27002 }
    },


    -- Soothes the target beast, reducing the range at which it will attack you by 10 yards.  Only affects Beast and Dragonkin targets level 40 or lower.  Lasts 15 sec.
    soothe_animal = {
        id = 2908,
        cast = function() return buff.natures_swiftness.up and 0 or 1.5 - (buff.natures_grace.up and 0.5 or 0) end,
        cooldown = 0,
        gcd = "spell",

        spend = 0.06,
        spendType = "mana",

        startsCombat = true,
        texture = 132163,

        handler = function ()
            removeBuff( "natures_swiftness" )
        end,

        copy = { 2908, 8955, 9901, 26995 },
    },


    -- Causes 127 to 155 Arcane damage to the target.
    starfire = {
        id = 2912,
        cast = function() return (3.5 - (talent.starlight_wrath.rank * 0.1) - (buff.natures_grace.up and 0.5 or 0)) * haste end,
        cooldown = 0,
        gcd = "spell",

        spend = function() return (buff.clearcasting.up and 0 or 0.16) * (1 - talent.moonglow.rank * 0.03) end,
        spendType = "mana",

        startsCombat = true,
        texture = 135753,

        handler = function ()
            removeBuff( "clearcasting" )
            removeBuff( "natures_grace" )
        end,

        copy = { 2912, 8949, 8950, 8951, 9875, 9876, 25298, 26986 },
    },


    -- Swipe nearby enemies, inflicting 108 damage.  Damage increased by attack power.
    swipe_bear = {
        id = 779,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function() return (buff.clearcasting.up and 0) or (20 - talent.ferocity.rank) end,
        spendType = "rage",

        startsCombat = true,
        texture = 134296,

        handler = function ()
            removeBuff( "clearcasting" )
        end,

        copy = { 779, 780, 769, 9754, 9908, 26997 }
    },


    -- Thorns sprout from the friendly target causing 3 Nature damage to attackers when hit.  Lasts 10 min.
    thorns = {
        id = 467,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function() return (buff.clearcasting.up and 0) or 0.17 end,
        spendType = "mana",

        startsCombat = true,
        texture = 136104,

        handler = function ()
            removeBuff( "clearcasting" )
            applyBuff( "thorns" )
        end,

        copy = { 467, 782, 1075, 8914, 9756, 9910, 26992 },
    },


    -- Increases damage done by 80 for 6 sec.
    tigers_fury = {
        id = 5217,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        spend = 30,
        spendType = "energy",

        startsCombat = true,
        texture = 132242,

        handler = function ()
            applyBuff( "tigers_fury" )
        end,

        copy = { 5217, 6793, 9845, 9846 }
    },


    -- Shows the location of all nearby humanoids on the minimap.  Only one type of thing can be tracked at a time.
    track_humanoids = {
        id = 5225,
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = 0,
        spendType = "energy",

        startsCombat = true,
        texture = 132328,

        handler = function ()
        end,
    },


    -- Heals all nearby group members for 364 every 2 seconds for 8 sec.  Druid must channel to maintain the spell.
    tranquility = {
        id = 740,
        cast = 0,
        cooldown = 300,
        gcd = "spell",

        spend = function() return (buff.clearcasting.up and 0) or 0.7 end,
        spendType = "mana",

        usable = function() return buff.moonkin_form.down end,

        startsCombat = true,
        texture = 136107,

        toggle = "cooldowns",

        handler = function ()
            removeBuff( "clearcasting" )
        end,

        copy = { 740, 8918, 9862, 9863, 26983 },
    },


    -- Shapeshift into travel form, increasing movement speed by 40%.  Also protects the caster from Polymorph effects.  Only useable outdoors.    The act of shapeshifting frees the caster of Polymorph and Movement Impairing effects.
    travel_form = {
        id = 783,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            local base = set_bonus.staff_of_natural_fury == 1 and max(0, 0.13 - 200 / mana.modmax) or 0.13
            return base * (1 - (talent.natural_shapeshifter.rank * 0.1))
        end,
        spendType = "mana",

        startsCombat = true,
        texture = 132144,

        handler = function ()
            swap_form( "travel_form" )
        end,
    },


    -- Shapeshift into Tree of Life Form, increasing healing done by 20% and restricting spells to healing and utility.
    tree_of_life = {
        id = 33891,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            local base = set_bonus.staff_of_natural_fury == 1 and max(0, 0.14 - 200 / mana.modmax) or 0.14
            return base * (1 - (talent.natural_shapeshifter.rank * 0.1))
        end,
        spendType = "mana",

        talent = "tree_of_life",
        startsCombat = false,
        texture = 132145,

        handler = function ()
            swap_form( "tree_of_life" )
        end,
    },


    -- Stuns up to 5 enemies within 8 yds for 2 sec.
    war_stomp = {
        id = 20549,
        cast = 0.5,
        cooldown = 120,
        gcd = "off",

        startsCombat = true,
        texture = 132368,

        toggle = "cooldowns",

        handler = function ()
        end,
    },


    -- Causes 18 to 21 Nature damage to the target.
    wrath = {
        id = 5176,
        cast = function() return buff.natures_swiftness.up and 0 or 2 - (talent.starlight_wrath.rank * 0.1) - (buff.natures_grace.up and 0.5 or 0) end,
        cooldown = 0,
        gcd = "spell",

        spend = function() return ( buff.clearcasting.up and 0 or 0.08 ) * (1 - (talent.moonglow.rank * 0.03)) end,
        spendType = "mana",

        startsCombat = true,
        texture = 136006,

        handler = function ()
            removeBuff( "clearcasting" )
            removeBuff( "natures_grace" )
            removeBuff( "natures_swiftness")
        end,

        copy = { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912, 26984, 26985 },
    },
    
} )

-- Options
spec:RegisterOptions( {
    enabled = true,

    aoe = 3,

    gcd = 1126,

    nameplates = true,
    nameplateRange = 8,

    damage = false,
    damageExpiration = 6,

    potion = "speed",

    package = "Feral",
    usePackSelector = true
} )

-- Settings
spec:RegisterSetting( "druid_description", nil, {
    type = "description",
    name = "Adjust the settings below according to your playstyle preference.  It is always recommended that you use a simulator "..
        "to determine the optimal values for these settings for your specific character.\n\n"
} )

spec:RegisterSetting( "druid_general_header", nil, {
    type = "header",
    name = "Druid: General"
} )

spec:RegisterSetting( "druid_general_desc", nil, {
    type = "description",
    name = "Settings that apply across all forms and specializations, including combat context and preferred form.\n\n",
    width = "full",
} )

spec:RegisterSetting( "combat_mode", "dynamic_dungeon_raid", {
    type = "select",
    name = "Combat Mode",
    desc = "Controls whether recommendations are tuned for group or solo play.\n\n"
        .. "|cFFFFFFFFAlways Group:|r Always use group-tuned recommendations.\n"
        .. "|cFFFFFFFFAlways Solo:|r Always use solo-tuned recommendations.\n"
        .. "|cFFFFFFFFDynamic - Everywhere:|r Group mode when in any party or raid group.\n"
        .. "|cFFFFFFFFDynamic - Dungeon / Raid:|r Group mode only inside a 5-man or raid instance.\n"
        .. "|cFFFFFFFFDynamic - Raid Only:|r Group mode only inside a 10 or 25-man raid instance.",
    width = "full",
    values = {
        group                = "Always Group",
        solo                 = "Always Solo",
        dynamic_everywhere   = "Dynamic - Everywhere",
        dynamic_dungeon_raid = "Dynamic - Dungeon / Raid",
        dynamic_raid         = "Dynamic - Raid Only",
    },
    sorting = { "group", "solo", "dynamic_everywhere", "dynamic_dungeon_raid", "dynamic_raid" },
} )

spec:RegisterSetting( "preferred_form", "cat", {
    type = "select",
    name = "Preferred Form",
    desc = strformat( "The form to shift into before and during combat.\n\n%s: Default DPS mode.\n%s: Tank mode. Enables the full bear rotation.",
        Hekili:GetSpellLinkWithTexture( spec.abilities.cat_form.id ),
        Hekili:GetSpellLinkWithTexture( spec.abilities.dire_bear_form.id ) ),
    width = "full",
    values = {
        cat  = Hekili:GetSpellLinkWithTexture( spec.abilities.cat_form.id ),
        bear = Hekili:GetSpellLinkWithTexture( spec.abilities.dire_bear_form.id ),
    },
    sorting = { "cat", "bear" },
} )

spec:RegisterSetting( "druid_balance_header", nil, {
    type = "header",
    name = "Balance"
} )

spec:RegisterSetting( "druid_balance_desc", nil, {
    type = "description",
    name = "Settings that influence the Moonkin DPS rotation.\n\n",
    width = "full",
} )

spec:RegisterSetting( "balance_mana_management_header", nil, {
    type = "header",
    name = "Mana Management"
} )

spec:RegisterSetting( "balance_mana_management_desc", nil, {
    type = "description",
    name = "When enabled, the rotation automatically applies mana conservation steps as your mana falls "..
        "below each threshold. Steps activate in order: downrank Starfire first, then add Insect Swarm, "..
        "then drop Moonfire. Set individual thresholds to 0 to skip a step.\n\n",
    width = "full",
} )

spec:RegisterSetting( "mana_management", false, {
    type = "toggle",
    name = "Enable Mana Management",
    desc = "When enabled, the rotation adjusts automatically based on your current mana percentage "..
        "using the thresholds below.",
    width = "full",
} )

spec:RegisterSetting( "downrank_starfire_mana_pct", 50, {
    type = "range",
    name = strformat( "Downrank %s Threshold (%%)", Hekili:GetSpellLinkWithTexture( spec.abilities.starfire.id ) ),
    desc = "Below this mana percentage, an 'R6' label appears on the Starfire recommendation reminding "..
        "you to manually cast Rank 6. ~60-70 DPS loss for +90 mp5. Set to 0 to skip this step.\n\nDefault: 50",
    min = 0, max = 100, step = 1,
    width = "full",
} )

spec:RegisterSetting( "add_insect_swarm_mana_pct", 30, {
    type = "range",
    name = strformat( "Add %s Threshold (%%)", Hekili:GetSpellLinkWithTexture( spec.abilities.insect_swarm.id ) ),
    desc = strformat( "Below this mana percentage, %s is added to the standing rotation. "..
        "It is always recommended when moving regardless of this setting. "..
        "~40-70 DPS loss for ~20-40 mp5. Set to 0 to skip this step.\n\nDefault: 30",
        Hekili:GetSpellLinkWithTexture( spec.abilities.insect_swarm.id ) ),
    min = 0, max = 100, step = 1,
    width = "full",
} )

spec:RegisterSetting( "drop_moonfire_mana_pct", 10, {
    type = "range",
    name = strformat( "Drop %s Threshold (%%)", Hekili:GetSpellLinkWithTexture( spec.abilities.moonfire.id ) ),
    desc = strformat( "Below this mana percentage, %s is removed from the rotation. "..
        "With T5 4-piece, %s replaces it instead. "..
        "~110-150 DPS loss for ~106-108 mp5. Set to 0 to skip this step.\n\nDefault: 10",
        Hekili:GetSpellLinkWithTexture( spec.abilities.moonfire.id ),
        Hekili:GetSpellLinkWithTexture( spec.abilities.insect_swarm.id ) ),
    min = 0, max = 100, step = 1,
    width = "full",
} )

spec:RegisterSetting( "druid_feral_header", nil, {
    type = "header",
    name = "Feral: Cat"
} )

spec:RegisterSetting( "druid_feral_desc", nil, {
    type = "description",
    name = "Settings that influence the cat form DPS rotation, including finisher thresholds, energy management, and cooldown usage.\n\n",
    width = "full",
} )

spec:RegisterSetting( "rip_subheader", nil, {
    type = "header",
    name = strformat( "%s", Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
} )

spec:RegisterSetting( "rip_desc", nil, {
    type = "description",
    name = "Controls how and when Rip is applied and maintained as a finisher.\n\n",
    width = "full",
} )

spec:RegisterSetting( "ripweave", true, {
    type = "toggle",
    name = "Enable Ripweaving",
    desc = strformat( "Refresh %s early when sitting on high energy to avoid overcap", Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
    width = "full",
} )

spec:RegisterSetting( "ripweave_desc", nil, {
    type = "description",
    name = strformat( "Ripweaving refreshes %s before it expires when you have enough energy to avoid overcapping, squeezing out extra damage without dropping uptime.\n\n", Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
    width = "full",
} )

spec:RegisterSetting( "rip_cp", 5, {
    type = "range",
    name = strformat( "Minimum Combo Points for %s", Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
    desc = strformat( "Specify the minimum combo points for %s to be recommended\n\nDefault: 5", Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
    width = "full",
    min = 1,
    max = 5,
    step = 1,
} )

spec:RegisterSetting( "bite_subheader", nil, {
    type = "header",
    name = strformat( "%s", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ) ),
} )

spec:RegisterSetting( "bite_desc", nil, {
    type = "description",
    name = "Controls finisher priority and Ferocious Bite usage relative to Rip.\n\n",
    width = "full",
} )

spec:RegisterSetting( "bite_over_rip", false, {
    type = "toggle",
    name = strformat( "Enable %s Over %s", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ), Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
    desc = strformat( "%s as *only* finisher", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ) ),
    width = "full",
} )

spec:RegisterSetting( "biteweave", true, {
    type = "toggle",
    name = "Enable Biteweaving",
    desc = strformat( "Prefer %s first if energy is high enough to gain another CP before %s", Hekili:GetSpellLinkWithTexture( spec.abilities.shred.id ), Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ) ),
    width = "full",
} )

spec:RegisterSetting( "biteweave_desc", nil, {
    type = "description",
    name = strformat( "Biteweaving delays %s when you have enough energy to build one more combo point with %s first, improving the average energy value per Bite.\n\n", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ), Hekili:GetSpellLinkWithTexture( spec.abilities.shred.id ) ),
    width = "full",
} )

spec:RegisterSetting( "bite_cp", 5, {
    type = "range",
    name = strformat( "Minimum Combo Points for %s", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ) ),
    desc = strformat( "Specify the minimum combo points for %s. Set to 0 to disable %s.\n\nDefault: 5", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ), Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ) ),
    width = "full",
    min = 1,
    max = 5,
    step = 1,
} )

spec:RegisterSetting( "tricks_subheader", nil, {
    type = "header",
    name = "Tricks",
} )

spec:RegisterSetting( "tricks_desc", nil, {
    type = "description",
    name = "Advanced energy management techniques for specific gear or talent setups. These are disabled by default and unlikely to be relevant for most players.\n\n",
    width = "full",
} )

spec:RegisterSetting( "mangle_trick", false, {
    type = "toggle",
    name = strformat( "Enable %s Trick", Hekili:GetSpellLinkWithTexture( spec.abilities.mangle_cat.id ) ),
    desc = strformat( "Nearing a tick and in the double-%s energy window, prefer a second %s over %s (only relevant in no-Wolfshead / 2pT6 builds)",
        Hekili:GetSpellLinkWithTexture( spec.abilities.mangle_cat.id ),
        Hekili:GetSpellLinkWithTexture( spec.abilities.mangle_cat.id ),
        Hekili:GetSpellLinkWithTexture( spec.abilities.shred.id ) ),
    width = "full",
} )

spec:RegisterSetting( "rake_trick", false, {
    type = "toggle",
    name = strformat( "Enable %s Trick", Hekili:GetSpellLinkWithTexture( spec.abilities.rake.id ) ),
    desc = strformat( "Cast %s as energy dump at 35 to (mangleCost-1)", Hekili:GetSpellLinkWithTexture( spec.abilities.rake.id ) ),
    width = "full",
} )

spec:RegisterSetting( "innervate_subheader", nil, {
    type = "header",
    name = strformat( "%s", Hekili:GetSpellLinkWithTexture( spec.abilities.innervate.id ) ),
} )

spec:RegisterSetting( "innervate_desc", nil, {
    type = "description",
    name = "Controls automatic Innervate usage to recover mana while in cat form, preventing you from being unable to shift.\n\n",
    width = "full",
} )

spec:RegisterSetting( "innervate_mana_pct", 20, {
    type = "range",
    name = strformat( "%s Mana Threshold (%%)", Hekili:GetSpellLinkWithTexture( spec.abilities.innervate.id ) ),
    desc = strformat( "Recommend %s when mana drops to or below this percentage.\n\n"..
        "If set below the mana cost of Cat Form, %s will be recommended when you have enough mana for only one final shift, "..
        "protecting against being stuck in humanoid form.\n\n"..
        "Default: 20",
        Hekili:GetSpellLinkWithTexture( spec.abilities.innervate.id ),
        Hekili:GetSpellLinkWithTexture( spec.abilities.innervate.id ) ),
    min = 0,
    max = 100,
    step = 1,
    width = "full",
} )

spec:RegisterSetting( "druid_bear_header", nil, {
    type = "header",
    name = "Feral: Bear"
} )

spec:RegisterSetting( "druid_bear_desc", nil, {
    type = "description",
    name = "Settings that influence the bear form tanking rotation.\n\n",
    width = "full",
} )

spec:RegisterSetting( "bear_swipe_ap", 2700, {
    type = "range",
    name = strformat( "Minimum Attack Power for %s over %s",
        Hekili:GetSpellLinkWithTexture( spec.abilities.swipe_bear.id ),
        Hekili:GetSpellLinkWithTexture( spec.abilities.lacerate.id ) ),
    desc = strformat( "When %s is at 5 stacks and safely maintained, %s is preferred over %s only when your Attack Power is at or above this value.\n\nDefault: 2700",
        Hekili:GetSpellLinkWithTexture( spec.abilities.lacerate.id ),
        Hekili:GetSpellLinkWithTexture( spec.abilities.swipe_bear.id ),
        Hekili:GetSpellLinkWithTexture( spec.abilities.lacerate.id ) ),
    width = "full",
    min = 0,
    max = 5000,
    step = 50,
} )

if (Hekili.Version:match( "^Dev" )) then
    spec:RegisterSetting("druid_debug_header", nil, {
        type = "header",
        name = "Debug"
    })

    spec:RegisterSetting("druid_debug_description", nil, {
        type = "description",
        name = "Settings used for testing\n\n"
    })

    spec:RegisterSetting("dummy_ttd", 300, {
        type = "range",
        name = "Training Dummy Time To Die",
        desc = "Select the time to die to report when targeting a training dummy",
        width = "full",
        min = 0,
        softMax = 300,
        step = 1,
        set = function( _, val )
            Hekili.DB.profile.specs[ 11 ].settings.dummy_ttd = val
        end
    })


    spec:RegisterSetting("druid_debug_footer", nil, {
        type = "description",
        name = "\n\n"
    })
end

-- Potions
spec:RegisterOptions( { potion = "haste_potion" } )

spec:RegisterPotions( {
    -- Classic physical DPS
    mighty_rage_potion = {
        item     = 13442,
        buff     = "mighty_rage_potion",
        duration = 20,
        aura     = { id = 17528, duration = 20 },
    },

    -- TBC physical DPS (Feral)
    insane_strength_potion = {
        item     = 22828,
        buff     = "insane_strength_potion",
        duration = 15,
        aura     = { id = 28494, duration = 15 },
    },
    heroic_potion = {
        item     = 22837,
        buff     = "heroic_potion",
        duration = 15,
        aura     = { id = 28506, duration = 15 },
    },

    -- TBC spell DPS (Balance / Resto throughput)
    destruction_potion = {
        item     = 22839,
        buff     = "destruction_potion",
        duration = 15,
        aura     = { id = 28508, duration = 15 },
    },
    haste_potion = {
        item     = 22838,
        buff     = "haste_potion",
        duration = 15,
        aura     = { id = 28507, duration = 15 },
    },
} )

-- Default Packs
spec:RegisterPack( "Feral", 20260327.1, [[Hekili:TV1spUnos4Fl9fd3Ds8yth39eaBFyWIfi5q2fWd2JsMTeLBHilkirfp9cd)BF4d9GuQOK8JEcMb5sJ2IfR6REx0MYzMZV7SXhZioFfnf9405ONMmB(Shr)QZg2RjeNnjyVVH3X)Ny8E(F)3KuCK4PVgrX(IDNrZt94R4S558Wi2NJDE2KLZwmbXjlH4581zZC28sOVprrfjZtSXKuAqyeNhypwinoBsskXJU)zm7DR(L940V5sdCzVqCpeg5)(WGv3LNm6UNZdcMSlmGPV6K8KtFbInSxOPXzfBgMe6EsSGxEr40q2RsALcPXcwLHhM5gqt3xVtXN4KpItvajnL4lx3Ltimh8dtjUptWPn4t1JayMyTtFrNF0drCELqZJ9icEOyV7EQpXnJgrBtBk(7CNSoxsXX7i(cdx4osAMBqEQ0IqIjP7EDIxohaXSvZMoDedNUJWMqZzzH(Kfa8iatsdjUbcTlqebvRzsei0kFIYI1K0jPK94W4SLZqa0OVQjoqa4ypLgl2fG4VRG3LKiEwdfB0ECmUuZxVsX96n4rZyVBCB3vbD1ptq4XJfpUmMr(0718aC4MNrCdzK9z14TICTyWlnY7QI3Q5rAESR6tUrHzS3lkuSsqKGDT4MjQJIAVvL3QF6KUUkzu6i7fzctLijOZeJU2CsMEEIq3KvPYJEVWFrdcC355VAwTXuSMWoMYtXQdFwmTftIWE8iEMm80NYMu(5jzmEv4vlgz8WQi)jlAXj4eoG0hTi)2zE615kySpzpLVu4)pmENBkv5Kl5aoXLhLKRcSZtoEe65LWgbydJ3fPchfC10CHABUYoeMut(GnyRNpIVmBcMjiYnHEGKUEvgHX46KI5UkwJBR)D7IwUGRZq(O53oWRh8vgl)M4X1yEcv8iWLEMKXtG4fgDvejeRSoPpji0lSUoztc5Pf)H6ZP8vOPAP8W8NNqsga3fKnqEhgZBM99cVzr91iUhXdNjIfeMQXsPL4XwwhHuTTc1XJb3zWO0(XJ60SeIKhqdGp3pYJsJ8PhIRXbp4a7)kOkQ3yq16E5SPJa1vW9NgMuwOKYDCHXSmTCf(QUEI4jEKk))NWc9(gFHYgNSW9exg11pKSMpPWOXkeSE18PhpAzYQ77cg6c(ab)DYOZeyLaybYcg71iEMc0ILOWvm3IRyKT5ol2yf)Ij)bZviR1ZarErjv(tAp726vpo)4XXnF4SfJGGeSFXyUJYjOKYSgSlhxehxdgzK8hqtV3I6FMAjV2f1lKMN5(CiJ0HxsSSWn12RSSYPWJoxCBKsZyHXbH7EH5wuj)dLlx857haeQTG96nkS9i0fyInzEs2Bw7fjRHAUix4nR1sdUFdBSi58)KBRK080gvnvaO7hDZdDq8xDRJwgQZuCdSXXv0IqLxFUf1oVsNxMmUHfoLai7fEIQrqGqsDgfydkvrbpn6otIPFNK6YjDqgGBhqMV4macSHOAh9HHAL)8vYZwiGEsZ5zApXrvrc4rooRchx9SnxzIyDjc834miLVZg2oKEuqbGwn)t3OsdcXAdhQYv8pdfpwGeylZncCMbcvqS4XkqwcPXOh61lTCmc9oyQS7ixUccAvjzLY)JiRXD9QzDhpFE2mG22i01YcOn6SHNRNX3P5pbWbCASWl5S5Z7tOPm(WtBF60wLqoTv8TSLn50xC2i)pXVTGsU8)7RYFOcsm(5iIVZVXxHBa5txID2C3PTGJHEA7OtBbxSAy0YFWbNnTw1HXXUqMLuOMSuhdCkMBfv6ZsEA76vLQ5aMvTwMnPviYpEnIeEewibkOuiUfDz3b)weeM9XN2woG7PTl5iPJHCLBqFavdS7PpK6PThp2K2L2i9HtBrNfVVxsTTXGRnsvliSppA1(OspKaC206DxkuXMFY6M1RZRWCJbgRIUnhlq(42JOPybFe1cNtj2epD(uLz1wfQT3xdEUKe4(xTI7wtzxytVcTrhRlq9OGTG6N(HyI189ZNwYhRg4Qn0UwkNRCMch9W12lq3kgZYQwSSLsidswOvR0ysfjsSxDEGibYgZJtnM7)02puty1ZU)cHmQ)y4QzZ7liUpnXie(PY4b4XJRbTCocjwT3M5TfR8rWhiwbmW2Buz54kNbWnnOqMm79TUTsVNOm7ThQNmP6mfqvNHN7B4vSR3Oep274ydpALYgBho8mt00YwOxuXSH0tP68hw8wiBrWvkH4rF6wwqgWNBVLJnnPSjJ25P6vtS7lUDkNaqYbHT3Pb8KxTa)yPV5HZk(PmKdX357SVZ(c5eU8z2Yhq2BCPd)pI6mHdO(dYE7LHKDFg(OgkK9wfAwve6SeHEEkYEz9lGDm5D)6qu3NWR5T0q)qzIR4uRZQPUntMNvJPeSC))88K)88K)9(8Kgv5ByX(5znVyT5FwN1ekt6gnzWaphAb7mswECUkgOk0WC5zQ5CGva7d2oK65x9GTDzyVilN9Peg4rrUzNG3ENNbIK)6pb)h1BNQfoy2sTJtc2EIOBSdMj6aItHM3q7QIkweOpyXTgvkB9Rczr1PP66EE98fGAA7Rx4PTcMu55AEndvUKjAoGsk6EmL3UHNSpNsnBBC)tv1z64oOQC91cU1LBT7jwA7vqtBfrkda6SX(f4C4rCZLl36IS2mdv)YSQDoLQlFA3JgabTLsOjTS2cCMdh2yVv(fAcSOqmHNmGNuW6DsFv2oU6o1xZXQ7EF3zwL8O82TlaC7RCpC5)otJKC14IZdWAPcxh(ACz(HsAQgyX8UTRl6wYv9ZX5QE9FkdzAMuuREM3uFJnRUy)qjd23EdGvEl)n4R6iKabYdqDBF2sngxDGrGGxR8UX(tYCkoNBXB5tVXKnMud4nCsViJ5lhvVbR6Bw9krnSiXU(wpASwVvRV4eM(p84vMWWQcs70j1CUv5W4t1hiR8vgsZyx)Au1RtYiuxvdSNxokv)AKfAHOQXllvpDF7paXaUAZCx)6ubzFKpZ6bQnE1QKFlGJT5Nl2H5lzLQnvXsnpDUwsuHyKbaIz2Wze))tCXl74PT)R)7gUK)8)tSLCrsJZMnyMkV25p)]] )
spec:RegisterPack( "Restoration", 20260327.1, [[Hekili:fovWoQnmq0VfUSx620nHwQuR2l9uzpWHA6PQ1yhNjKr4yhz7uwU4V9oob2KsrDfcKzEZ8EEEEgEoFlNvjdaFtXdfREyzXNZYxMV6JFIZcN6aoRtQoi3thmYw63Fa(G1jdO1KWoPTYQehEBVtr4CwzpQdRn8Y)M48LeXfRYlOC7afFtEoN1GvvWyQGxXzBBqFuK(kJIZkhf2A6)QKKrHg9bcU26IIVdhqnMr3dNTg1K6Jz5Z6CGY2wkdV7Xp0kDh2zR3fAGDhrD19y9Jl67UBrzFDD2ESomhnRVl(0TOj0yDg)5IVDk2wWK4sPLomCAi3brUcyqJxPiXTdGeUgRHPQMhLkHZ(n48jFFMJYzhLodA27VyEN9IrxSf9Ecmk89DDwx4SXThmGdvrrWHMdqWNffrX6WyrdDeDJRGkkJgjfgiPpL4gTPgGYZO090BgbHK15(c1qI3hf)6NEiXe06F((O4ydQAMNT0CAs1OWytK)sNgvyqpXBv6usCys0VsdcUlYSDKIOi)5ePvZdvmtz6jvpRJotz4sQdUXqitFBj4sc712qw8P1TjdlfO4QPpcKZgonS8a1YEDGoUzyzcmYsnuX)gNPORn5ZsoBruC7N0rIPDTza8a9H96G1BYmnnjUlkUOXnMON056LbsPnf)FYNDjhwbsLS8n70)DKFINRWg6xQJL9jb4mMm4hIW)d]] )
spec:RegisterPack( "Balance", 20260327.1, [[Hekili:9E1YsTooq0Vf2KkudLN8acZcCwCxnxwWIRVRLSITCIQyl5ssggQkL)2Nws2ocHnjSygkGeR(0h1DR(HmAj63OKCIMIEz1IvBwSE1JrlxVCZIhrj63RPOKAs2rYE4lCsf8)Fqkj8m76Vxki5g9vIgPzjuYUgwP(NC0UasxgTA19WNa2AAg6LLlrjhy55uhuQkdL87dmvBQ5psBA3U2MkkGNZ0mbVnTKP0G4cHSn9VPhzLSiWoKIcwjS7ouQOAjntuTJO)J4)Ssi4hzCmOs1DSI4B21uue5VAutD7ZJQkrEelkW6du8BSYCp1dKaumZjzpRqhiP95b6bsBuumttRu(lwlSUN3k7OknUIWjyNmZEBEmkNwWYy6TXoSrHabB7FCplbjcjnFCALnC6vqQb2xtjJZPYxHJ6b2QZ0pfROAnJVxfniVZkZ0ZYeIYCXB8ZYIKus(7(0(9o3afYiLLy3JytAYDMS1yIWAxM1FLIPCAfJQ2U8YkQ0ENBrkt(qbHkzuCbtA58MCQ1M8w(dPsQ(0Vqf6xlsZYaNz)S53meTSXiZ)2tROC9PtdsYLIACVQdXY4fNo1h03EbS3gyBmUIMPXQ3iDH4o7ZF9Z2yL4v4ZtNMpLToB(zrK8CSpnd2W2fZgjhzs4362p8obVrb2cv(aENR)Z247NDbhE8nBIGd8t45Ta6PzkM5eDJ7iuRZ3U6HaCknrApJlj7OLX)AJ7lya)KXQZwduhij8J4EwUK1pj(aR6njrFWphgkf((jXoL8ZI7kLYf6He5NwFx27zLumys7PAv8Yqco0iLSmcN(jZ5JX4qX9oz46wNdL8kvQGv9gYatvGeiUjuHs(zvTqQH2vP3hmcjQ9zuI9BMPxaNWhVyNes5KDL0C0pqjzsOrTKrqj30MoACQFKdkXBDKgSNaQ6H1hX8jFKaAB6tTPRbq(rvJbcuV2AXD8nex93na09(GcIXbqFWhAF8oaZgFmDXEFaAJM)hhchJQWoPTPZAtN3MciMQYRn90jpPJ3mOnnUnDHdAFnyB62RqVBh5SU)q7coZyTD7DixZxNbn)RCohCFit2B16qlSQC2hFk(6u9wFBzS2Za7X26Uzxru7sgYKr7HFph29n4HsHrd9qZC7wV6HPRv6lq8iOV5oKZ))y39XQrTwck5xBUYAu4AEKMYZfQ9OhUtAqz)kFqURxgGy68ARZ1DVsxUGJOR4cRN3ZqSF955vSLJFD2X2qdYXo9d2UpNR(577AZSN6oV(jUDcgonNQHXyxf(J9D6fyO6XjMffEV3rMj1DFzBvYs3atS7LanJmbU)RRMBpDvAx64W7ADXjhFph(lNCm17VzpK6LpYBX5TDbkJ6ChsJ(GqIssiWSAZkO)9]] )

spec:RegisterPackSelector( "balance", "Balance (IV)", "|T136096:0|t Balance",
    "If you have spent more points in |T136096:0|t Balance than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab1 > max( tab2, tab3 )
    end )

spec:RegisterPackSelector( "feral", "Feral", "|T132115:0|t Feral",
    "If you have spent more points in |T132276:0|t Feral than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab2 > max( tab1, tab3 )
    end )


spec:RegisterPackSelector( "resto", "Restoration", "|T135760:0|t Resto",
    "If you have spent more points in |T135760:0|t Restoration than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab3 > max( tab1, tab2 )
    end )