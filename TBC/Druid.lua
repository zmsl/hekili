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

spec:RegisterStateExpr("combat_mode_solo", function()
    return settings.combat_mode == "solo"
end)

spec:RegisterStateExpr("combat_mode_group", function()
    return settings.combat_mode == "group"
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
    spend( (buff.clearcasting.up and 0) or ((15 - talent.ferocity.rank) * ((buff.berserk.up and 0.5) or 1)), "rage" )
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
        alias = { "aquatic_form", "cat_form", "bear_form", "dire_bear_form", "moonkin_form", "travel_form"  },
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
        duration = 12,
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

        spend = 0.13,
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

        spend = function() return 0.35 * (1 - (talent.natural_shapeshifter.rank * 0.1)) end,
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
        applyDebuff( "target", "lacerate" )
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

        spend = function() return 0.35 * (1 - (talent.natural_shapeshifter.rank * 0.1)) end,
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
            gain(20 + (talent.improved_enrage.rank * 5), "rage" )
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

        spend = function() return ((buff.clearcasting.up and 0 or 0.21) * (1 - talent.moonglow.rank * 0.03)) * (buff.moonkin_form.up and 0.5 or 1) end,
        spendType = "mana",

        startsCombat = true,
        texture = 136096,

        handler = function ()
            removeBuff( "clearcasting" )
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

        spend = 0.22,
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

        handler = function ()
            removeBuff( "clearcasting" )
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
        cast = function() return (3.5 - (talent.improved_starfire.rank * 0.1) - (buff.natures_grace.up and 0.5 or 0)) * haste end,
        cooldown = 0,
        gcd = "spell",

        spend = function() return (buff.clearcasting.up and 0 or 0.16) * (1 - talent.moonglow.rank * 0.03) end,
        spendType = "mana",

        startsCombat = true,
        texture = 135753,

        handler = function ()
            removeBuff( "clearcasting" )
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

        spend = 0.13,
        spendType = "mana",

        startsCombat = true,
        texture = 132144,

        handler = function ()
            swap_form( "travel_form" )
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

spec:RegisterSetting( "innervate_enabled", true, {
    type = "toggle",
    name = strformat( "Use %s", Hekili:GetSpellLinkWithTexture( spec.abilities.innervate.id ) ),
    desc = strformat( "If unchecked, %s will not be recommended.", Hekili:GetSpellLinkWithTexture( spec.abilities.innervate.id ) ),
    width = "1",
} )

spec:RegisterSetting( "innervate_threshold", 20, {
    type = "range",
    name = strformat( "Mana threshold for %s", Hekili:GetSpellLinkWithTexture( spec.abilities.innervate.id ) ),
    desc = strformat( "If set to zero or more, %s will be recommended when reaching that mana percentage. Setting to -1 will disable the use of %s.\n\n" ..
        "Default: 20", Hekili:GetSpellLinkWithTexture( spec.abilities.innervate.id ), Hekili:GetSpellLinkWithTexture( spec.abilities.innervate.id ) ),
    width = "double",
    min = 0,
    max = 100,
    step = 1
} )

spec:RegisterSetting( "druid_feral_header", nil, {
    type = "header",
    name = "Feral: General"
} )

spec:RegisterSetting( "combat_mode", "group", {
    type = "select",
    name = "Combat Mode",
    desc = "When Group mode is active, recommendations will be tuned for group damage. When Solo mode is active, recommendations will be tuned for solo / open world play.",
    width = "full",
    values = {
        group = "Group",
        solo = "Solo"
    },
    sorting = { "group", "solo" }
} )

spec:RegisterSetting( "powershift_enabled", true, {
    type = "toggle",
    name = "Use Powershifting",
    desc = "If unchecked, Powershifting will not be recommended.",
    width = "1",
} )

spec:RegisterSetting( "powershift_time", 1, {
    type = "range",
    name = "Minimum Powershift energy tick time",
    desc = "Specify the minimum energy tick time allowed to weave powershifting into the rotation",
    width = "double",
    min = 0,
    max = 2,
    step = 0.1,
} )

spec:RegisterSetting( "rip_enabled", false, {
    type = "toggle",
    name = strformat( "Use %s", Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
    desc = strformat( "If unchecked, %s will not be recommended.", Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
    width = "1",
} )

spec:RegisterSetting( "rip_cp", 5, {
    type = "range",
    name = strformat( "Minimum Combo Points for %s", Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
    desc = strformat( "Specify the minimum combo points for %s to be recommended\n\n"..
        "Default: 0", Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ), Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
    width = "double",
    min = 1,
    max = 5,
    step = 1,
} )

spec:RegisterSetting( "bite_enabled", true, {
    type = "toggle",
    name = strformat( "Use %s", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ) ),
    desc = strformat( "If unchecked, %s will not be recommended.", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ) ),
    width = "1",
} )

spec:RegisterSetting( "bite_cp", 5, {
    type = "range",
    name = strformat( "Minimum Combo Points for %s", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ) ),
    desc = strformat( "Specify the minimum combo points for %s. Set to 0 to disable %s.\n\n"..
        "Default: 0", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ), Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ) ),
    width = "double",
    min = 1,
    max = 5,
    step = 1,
} )

spec:RegisterSetting( "bite_line2", nil, {
    type = "description",
    name = "",
    width = "1"
} )

spec:RegisterSetting( "bite_time", 0, {
    type = "range",
    name = strformat( "Minimum time left on %s for %s", Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ), Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ) ),
    desc = strformat( "If set above zero, %s will not be recommended unless %s has this much time remaining.\n\n" ..
        "Default: 4", Hekili:GetSpellLinkWithTexture( spec.abilities.ferocious_bite.id ), Hekili:GetSpellLinkWithTexture( spec.abilities.rip.id ) ),
    width = "double",
    min = 0,
    softMax = 14,
    step = 1
} )

spec:RegisterSetting( "claw_trick_enabled", true, {
    type = "toggle",
    name = strformat( "Use %s trick", Hekili:GetSpellLinkWithTexture( spec.abilities.claw.id ) ),
    desc = strformat( "If unchecked, %s trick during %s logic will not be recommended.", Hekili:GetSpellLinkWithTexture( spec.abilities.claw.id ), Hekili:GetSpellLinkWithTexture( spec.abilities.shred.id ) ),
    width = "full",
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

-- Default Packs
spec:RegisterPack( "Feral", 20241120.4, [[Hekili:TZv3Vnkoq8)w4fer32CH0pUEsj9HtRoPDFyVtkNUhHqatlQemYy2OEQI)2p)bymG5JSjPztlV0TbpE8m)MFZmM0rRLP1)yTYZbdS(28zZVX0CU5uZ53C3TMwRWVedSwf74(SZJKFjYzl5N)ja5esF6lHqhp6UtGPixYkwR2KgeI)sK1gLQ8MBiYgdCT(Mjr5pf45b4IcsCP7ogb9dcjkYXfhaJsMgefbqFNOiBiYo5PaF8VS8xfp8tb(ltayCq0JYIcIC2ec805kPCHPphb3fPV1jYzASlEXYYTGFcbsEcg6PJXEpmp7RDAaBajyBQASJHuX6rCMKO0iqpY56GT9HOTzFTuqKt0JapYI4GhbOeB)u0lu3gq2)JVm1nfHar4LMZMPJDqpcWtHP4KapWTk0HVdafaS9dqKFqdIun5b2K67pTXAtrGTobrjlmNR3ug5vREWZLn)yeWfUDJdhgqpBd9jynWExqOh9W1sJ11y6(rcgiV600y1Qb)eefLKVz1IuaKmH4wo5tmnk2arS0eGDagSnPuUIDkF6ej5H5EfRoVOX5Z5E5bTf58tHYCHjyz1j4nhOE6aokfICo28pzhgKG)envF5gGdIUl2MOFqLx76eg2CRCsxVNa12sGHq6PWJF2BHEa2Zg0MHqUFzidjpuwwigUJK3qZWe1fmilAVbgLMmDhm0p5jGJ3sZxFf7es27uskgertAEE5Tt0RQwvq9KbzNXjY5fuSKfHtd)eLgc99TF0LyfLXi6AvscY3tYUGyGDrKbrQllmV7M1q6gP1Ywrb4tT7GyQ6me4g5bcaJgyGeoDqeorbetf1LKhNxLG8rkfLwiDPH5SjtuEGeJb6gattS3eWRKxE20NugTA55vpnPpLxzsYaz7dhSfm51xBrBAQC8jt6Z1z6WnwTl6g6SRoCtORVPOn)8siT38A224HL3DTkXFphBKaevlqJzSCW8mDMG8loupug3EXVMT3Bc(lmNPqFfmJtc1yYb6aNiRs3ihzO0aBmKqhCF(bvvWz8efoHGFRDYmXl5maIEhMK6geFEb1LjBPbyCvt3yro8OzOTxwEzmxQue5mR)qZB15x4kK0oZ1jHQkI1OKj3SQ1iB4sHnOPkkFGvRgJ(xmr)g59ZVx)ycM6Ah1yJc5Usvlmv7vL3sQYzODmnqse7yQUdXF)jKVvLoixA40uXOFiixdk8XLkWzIdqreLrGJY98gRCEPu504JuLt13pCSY5BhFRk88ESY5fXlJ2Ao5rL7(HQoAZYOkBIw8TdngzVKJS6QsXn1fQGgMTXiYtl0KQVPovFt)VX3NAKUC2OlcfuRJWitzpW7(8RFMzkQ(slMu52OO3H3pAKEVhKK(8Rlp6T27D(9EE9FRvFN8zc1xmOtZMET1QDoOiQ8wR(Y2yictUaX67ZwZZsYwtttsMM9vRvSFJobv8XLG8BFJnow54N1FyTYfrIxOah6dLdizRxMT2C2SS16zRRn7pfdqL1kPXgYctmYwvEoc26yaLTEb54MZoTMYQsQAJfuPn14miwg2AvZsgDdhIGsJj)ID85)bCRn9xSLkMamI1sWqftbg3(XK)9HS1swUqubwwSs9r)r2MjYETSSI56PMq3iluXiMuvgmnq57Kg2d2OLTMfIKguPsvlM7PUzeDQJCVSW16ubfZmKa6fm4fIWuLjQPdyTaMovhyzSHCs3o0tsryJS97AD7S9kppvLkOw3uEjcB(Gxs3bvX)wnfxE4v)oERS58kmKTFFR2fTyR8eynmZQyKxO6(37cYmQhoEGK(PQ2QCESbtK6ZRfV6x26xFLwOP2CBXw82S1tuWaOhPkkar6H7TqilaBoRLarF7poHNllgAXEZMZzZf8oftlPmhU6Gw2BAU8M5Jx5ELyRK9JlrQo9ndjgG0nhyERQE)1in8()fytL7riveFjJgzoJrjKJZbXDdo1B5s10DxxQa231x3GLSdkF1RcYDNR30HAEtNAiI46QmNLMF05jO1g(pPi)zarH8RNwbBRoogn6VXrUQna7SEBEsR0azjX7cD2X5CSsK9LmXqW85RuoTjnK3CmFAmPAPt2H8WxYUQWDZKCqXCA24canVau9M8IsQxW5oJe)cIFLGpJRQkEhN0D0UETi6nTNnWM)kUBDFXUZa5sf)QZcRNhBSGaR4nfzvbA7TfR4E)aHRoV47zhn(yLUloX9zxCGGHJlKHXCv1cKFLAWyHYabNjODairD6DT7(iSwvlBElBZ8xBS2W8vl9wCZPoB6pYQhz1hrwTMAUzx9UB)L4hPNJ0ZJo9SLcRZVVWroHHtHfCYpgv74Q2Uqv7AQpulVDKrHmNqNkNnDApKJhY9oopQnIC9IZNRA3dh6L0VsmCzlXDbiuebALDy0Y7E9d8Yj1)oPh7to2N8KKFlcyJ9jhA1(jd5L2mg7s(XQlPIGXypY(6rkvc6T(R)R9)STN9oSdOCyFRFWP9JnzpILhQWWB0Hv1xJxF)H)hzNJSZ3i2jtG2QoBYwvCanh1)g)vLBoMhJC7rU9pJCBHQRDZJHnysQV1HzNtsXi5FK8FCj)AdG)B04vvRt8ox8YHhBqVXV4YbvdOZPh8CH1J1a2RD9oRgG2yzGFKYafWY(EfIdRccF0mDsaE)vu())bNT(Z)9kIP8L)LQ4u6yhBT6Za))ZX9jM8w)p]] )

spec:RegisterPackSelector( "balance", "Balance (IV)", "|T136096:0|t Balance",
    "If you have spent more points in |T136096:0|t Balance than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab1 > max( tab2, tab3 )
    end )

spec:RegisterPackSelector( "feral", "Feral", "|T132115:0|t Feral",
    "If you have spent more points in |T132276:0|t Feral than in any other tree and have not taken Thick Hide, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab2 > max( tab1, tab3 ) and talent.thick_hide.rank == 0
    end )
