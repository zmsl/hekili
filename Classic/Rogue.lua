if UnitClassBase( 'player' ) ~= 'ROGUE' then return end

local addon, ns = ...
local Hekili = _G[ addon ]
local class, state = Hekili.Class, Hekili.State

local spec = Hekili:NewSpecialization( 4 )


-- TODO:  Check gains from Cold Blood, Seal Fate; i.e., guaranteed crits.


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
spec:RegisterTalents( {
    adrenaline_rush            = {   205, 1, 13750 },
    blade_flurry               = {   223, 1, 13877 },
    camouflage                 = {   244, 3, 13975, 14062, 14063 },
    cold_blood                 = {   280, 1, 14177 },
    deflection                 = {   187, 5, 13713, 13853, 13854, 13855, 13856 },
    dirty_deeds                = {   265, 2, 14082, 14083 },
    dual_wield_specialization  = {   221, 5, 13715, 13848, 13849, 13851, 13852 },
    elusiveness                = {   247, 2, 13981, 14066 },
    endurance                  = {   204, 2, 13742, 13872 },
    ghostly_strike             = {   303, 1, 14278 },
    hemorrhage                 = {   681, 1, 16511 },
    improved_ambush            = {   263, 3, 14079, 14080, 14081 },
    improved_eviscerate        = {   276, 3, 14162, 14163, 14164 },
    improved_gouge             = {   203, 3, 13741, 13793, 13792 },
    improved_kick              = {   206, 2, 13754, 13867 },
    improved_kidney_shot       = {   279, 3, 14174, 14175, 14176 },
    improved_poisons           = {   268, 5, 14113, 14114, 14115, 14116, 14117 },
    improved_sinister_strike   = {   201, 2, 13732, 13863 },
    improved_slice_and_dice    = {   207, 3, 14165, 14166, 14167 },
    improved_sprint            = {   222, 2, 13743, 13875 },
    initiative                 = {   245, 3, 13976, 13979, 13980 },
    lethality                  = {   269, 5, 14128, 14132, 14135, 14136, 14137 },
    lightning_reflexes         = {   186, 5, 13712, 13788, 13789, 13790, 13791 },
    mace_specialization        = {   184, 5, 13709, 13800, 13801, 13802, 13803 },
    malice                     = {   270, 5, 14138, 14139, 14140, 14141, 14142 },
    master_of_deception        = {   241, 5, 13958, 13970, 13971, 13972, 13973 },
    murder                     = {   274, 2, 14158, 14159 },
    opportunity                = {   261, 5, 14057, 14072, 14073, 14074, 14075 },
    precision                  = {   181, 5, 13705, 13832, 13843, 13844, 13845 },
    premeditation              = {   381, 1, 14183 },
    preparation                = {   284, 1, 14185 },
    remorseless_attacks        = {   272, 2, 14144, 14148 },
    riposte                    = {   301, 1, 14251 },
    ruthlessness               = {   273, 3, 14156, 14160, 14161 },
    seal_fate                  = {   283, 5, 14186, 14190, 14193, 14194, 14195 },
    serrated_blades            = {   682, 3, 14171, 14172, 14173 },
    setup                      = {   246, 3, 13983, 14070, 14071 },
    sleight_of_hand            = {   1700, 2, 30892, 30893 },
    vigor                      = {   382, 1, 14983 },
    vile_poisons               = {   682, 5, 16513, 16514, 16515, 16516, 16517 },
} )



-- Glyphs
spec:RegisterGlyphs( {
    [56808] = "adrenaline_rush",
    [56813] = "ambush",
    [56800] = "backstab",
    [56818] = "blade_flurry",
    [58039] = "blurred_speed",
    [63269] = "cloak_of_shadows",
    [56820] = "crippling_poison",
    [56806] = "deadly_throw",
    [58032] = "distract",
    [64199] = "envenom",
    [56799] = "evasion",
    [56802] = "eviscerate",
    [56803] = "expose_armor",
    [63254] = "fan_of_knives",
    [56804] = "feint",
    [56812] = "garrote",
    [56814] = "ghostly_strike",
    [56809] = "gouge",
    [56807] = "hemorrhage",
    [63249] = "hunger_for_blood",
    [63252] = "killing_spree",
    [63268] = "mutilate",
    [58027] = "pick_lock",
    [58017] = "pick_pocket",
    [56819] = "preparation",
    [56801] = "rupture",
    [58033] = "safe_fall",
    [56798] = "sap",
    [63253] = "shadow_dance",
    [56821] = "sinister_strike",
    [56810] = "slice_and_dice",
    [56811] = "sprint",
    [63256] = "tricks_of_the_trade",
    [58038] = "vanish",
    [56805] = "vigor",
} )


spec:RegisterAuras( {
    -- Energy regeneration increased by $s1%.
    adrenaline_rush = {
        id = 13750,
        duration = 15,
        max_stack = 1,
    },
    -- Attack speed increased by $s1%. Weapon attacks strike an additional nearby opponent.
    blade_flurry = {
        id = 13877,
        duration = 15,
        max_stack = 1,
    },
    -- Disoriented.
    blind = {
        id = 2094,
        duration = 10,
        max_stack = 1,
    },
    -- Stunned.
    cheap_shot = {
        id = 1833,
        duration = 4,
        max_stack = 1,
    },
    -- Increases chance to resist spells by $s1%.
    cloak_of_shadows = {
        id = 31224,
        duration = 5,
        max_stack = 1,
    },
    -- Critical strike chance of your next offensive ability increased by $s1%.
    cold_blood = {
        id = 14177,
        duration = 3600,
        max_stack = 1,
    },
    deadly_poison = {
        id = 2818,
        duration = 12,
        max_stack = 5,
        copy = { 2819, 11353, 11354, 25349 },
    },
    -- Detecting traps.
    detect_traps = {
        id = 2836,
        duration = 3600,
        max_stack = 1,
    },
    -- Dodge chance increased by $s1%.
    evasion = {
        id = 5277,
        duration = 15,
        max_stack = 1,
    },
    -- $s1 damage every $t1 seconds.
    garrote = {
        id = 703,
        duration = 18,
        tick_time = 3,
        max_stack = 1,
        copy = { 8631, 8632, 8633, 11289, 11290 },
    },
    -- Silenced.
    garrote_silence = {
        id = 1330,
        duration = 3,
        max_stack = 1,
    },
    -- Dodge chance increased by $s2%.
    ghostly_strike = {
        id = 14278,
        duration = 7,
        max_stack = 1,
    },
    -- Incapacitated.
    gouge = {
        id = 1776,
        duration = function() return 4 + 0.5 * talent.improved_gouge.rank end,
        max_stack = 1,
    },
    -- Increases damage taken by $s3.
    hemorrhage = {
        id = 16511,
        duration = 15,
        max_stack = 1,
        copy = { 17347, 17348 },
    },
    -- Stunned.
    kidney_shot = {
        id = 8643,
        duration = function() return 1 + combo_points.current end,
        max_stack = 1,
        copy = { 408 },
    },
    -- Causes damage every $t1 seconds.
    rupture = {
        id = 1943,
        duration = function() return 6 + (2 * combo_points.current) end,
        tick_time = 2,
        max_stack = 1,
        copy = { 8639, 8640, 11273, 11274 },
    },
    -- Sapped.
    sap = {
        id = 6770,
        duration = 45,
        max_stack = 1,
        copy = { 2070, 11297 },
    },
    -- Melee attack speed increased by $s2%.
    slice_and_dice = {
        id = 5171,
        duration = function() return 6 + (3 * combo_points.current) + (3 * talent.improved_slice_and_dice.rank) end,
        max_stack = 1,
    },
    -- Movement speed increased by $w1%.
    sprint = {
        id = 2983,
        duration = 15,
        max_stack = 1,
    },
    -- Stealthed. Movement slowed by $s3%.
    stealth = {
        id = 1784,
        duration = 3600,
        max_stack = 1,
    },
    -- Critical strike chance for your next offensive ability increased by $s1%.
    remorseless = {
        id = 14143,
        duration = 20,
        max_stack = 1,
        copy = { 14143, 14149 },
    },
    -- Melee attack speed slowed by $s2%.
    riposte = {
        id = 14251,
        duration = 30,
        max_stack = 1,
    },
    vanish = {
        id = 1856,
        duration = 10,
        max_stack = 1,
    },
} )



spec:RegisterStateExpr( "cp_max_spend", function ()
    return combo_points.max
end )


local stealth = {
    rogue   = { "stealth", "vanish" },
    mantle  = { "stealth", "vanish" },
    all     = { "stealth", "vanish", "shadowmeld" }
}


local enchant_ids = {
    [7]   = "deadly",
    [8]   = "deadly",
    [323] = "instant",
    [324] = "instant",
    [325] = "instant",
    [35]  = "mind",
    [22]  = "crippling",
    [703] = "wound",
    [704] = "wound",
    [705] = "wound",
    [706] = "wound",
}



spec:RegisterStateTable( "stealthed", setmetatable( {}, {
    __index = function( t, k )
        if k == "rogue" then
            return buff.stealth.up or buff.vanish.up
        elseif k == "rogue_remains" then
            return max( buff.stealth.remains, buff.vanish.remains )

        elseif k == "mantle" then
            return buff.stealth.up or buff.vanish.up
        elseif k == "mantle_remains" then
            return max( buff.stealth.remains, buff.vanish.remains )

        elseif k == "all" then
            return buff.stealth.up or buff.vanish.up or buff.shadowmeld.up
        elseif k == "remains" or k == "all_remains" then
            return max( buff.stealth.remains, buff.vanish.remains, buff.shadowmeld.remains )
        end

        return false
    end
} ) )



spec:RegisterHook( "spend", function( amt, resource )
    if resource == "combo_points" and math.random(100) <= talent.relentless_strikes.rank * 20 then
        gain( 25, "energy" )
    end
end )



-- We need to break stealth when we start combat from an ability.
spec:RegisterHook( "runHandler", function( action )
    local a = class.abilities[ action ]

    -- If stealthed and starting combat, break stealth and apply relevant cooldowns or buffs.
    if stealthed.all and ( not a or a.startsCombat ) then
        if buff.stealth.up then
            setCooldown( "stealth", 10 ) -- Stealth cooldown after breaking.
        end

        -- Remove stealth-related buffs when combat begins.
        removeBuff( "stealth" )
        removeBuff( "shadowmeld" )
        removeBuff( "vanish" )
    end

    -- Remove other buffs that should not persist once combat begins.
    if ( not a or a.startsCombat ) then
        if buff.cold_blood.up then removeBuff( "cold_blood" ) end
    end
end )



spec:RegisterHook( "reset_precast", function()
    -- Retrieve main-hand and off-hand weapon enchant info.
    local mh, mh_expires, _, mh_id, oh, oh_expires, _, oh_id = GetWeaponEnchantInfo()



end )



-- Abilities
spec:RegisterAbilities( {
    -- Increases your Energy regeneration rate by 100% for 15 sec.
    adrenaline_rush = {
        id = 13750,
        cast = 0,
        cooldown = 300, -- Adjusted for Classic's 5-minute cooldown.
        gcd = "spell", -- Default GCD type for abilities in Classic.
    
        talent = "adrenaline_rush",
        startsCombat = false,
        texture = 136206,
    
        toggle = "cooldowns",
    
        handler = function ()
            applyBuff( "adrenaline_rush" )
            energy.regen = energy.regen * 2 -- Doubles energy regeneration during the buff.
        end,
    },
    


    -- Ambush the target, causing 275% weapon damage plus 509 to the target.  Must be stealthed and behind the target.  Requires a dagger in the main hand.  Awards 2 combo points.
    ambush = {
        id = 8676,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD.
    
        spend = 60, -- Fixed energy cost for Ambush in Classic.
        spendType = "energy",
    
        startsCombat = true,
        texture = 132282,
    
        usable = function() return stealthed.all, "must be in stealth" end,
    
        handler = function ()
            -- Gain combo points based on the rank of the Initiative talent.
            if talent.initiative.rank > 0 then
                gain( talent.initiative.rank == 3 and 3 or 2, "combo_points" )
            end
            removeBuff( "remorseless" ) -- Remove Remorseless Attacks buff if active.
        end,
    
        -- Classic ranks of Ambush.
        copy = { 8676, 8724, 8725, 11267, 11268, 11269 },
    },
    


    -- Backstab the target, causing 150% weapon damage plus 255 to the target.  Must be behind the target.  Requires a dagger in the main hand.  Awards 1 combo point.
    backstab = {
        id = 53,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD.
    
        spend = 60, -- Fixed energy cost for Backstab in Classic.
        spendType = "energy",
    
        startsCombat = true,
        texture = 132090,
    
        usable = function() return stealthed.all, "must be behind the target" end, -- Classic requires being behind the target.
    
        handler = function ()
            gain( 1, "combo_points" ) -- Generate 1 combo point on use.
            removeBuff( "remorseless" ) -- Remove Remorseless Attacks buff if active.
        end,
    
        -- Classic ranks of Backstab.
        copy = { 53, 2589, 2590, 2591, 8721, 11279, 11280, 11281 },
    },
    


    -- Increases your attack speed by 20%.  In addition, attacks strike an additional nearby opponent.  Lasts 15 sec.
    blade_flurry = {
        id = 13877,
        cast = 0,
        cooldown = 120, -- Classic cooldown remains 120 seconds.
        gcd = "spell", -- Updated for Classic GCD.
    
        spend = 25, -- Fixed energy cost for Blade Flurry in Classic.
        spendType = "energy",
    
        talent = "blade_flurry",
        startsCombat = false,
        texture = 132350,
    
        toggle = "cooldowns",
    
        handler = function ()
            applyBuff( "blade_flurry" ) -- Apply Blade Flurry buff.
        end,
    },
    


    -- Blinds the target, causing it to wander disoriented for up to 10 sec.  Any damage caused will remove the effect.
    blind = {
        id = 2094,
        cast = 0,
        cooldown = 300, -- Fixed cooldown of 5 minutes in Classic.
        gcd = "spell", -- Updated for Classic GCD.
    
        spend = 30, -- Fixed energy cost for Blind in Classic.
        spendType = "energy",
    
        startsCombat = true,
        texture = 136175,
    
        toggle = "interrupts",
    
        handler = function ()
            applyDebuff( "target", "blind" ) -- Apply the Blind debuff to the target.
        end,
    },
    


    -- Stuns the target for 4 sec.  Must be stealthed.  Awards 2 combo points.
    cheap_shot = {
        id = 1833,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD.
    
        spend = 60, -- Fixed energy cost for Cheap Shot in Classic.
        spendType = "energy",
    
        startsCombat = true,
        texture = 132092,
    
        usable = function() return stealthed.all, "must be in stealth" end,
    
        handler = function ()
            applyDebuff( "target", "cheap_shot" ) -- Apply Cheap Shot debuff to the target.
            if talent.initiative.rank > 0 then
                gain( talent.initiative.rank == 3 and 3 or 2, "combo_points" ) -- Generate additional combo points based on Initiative rank.
            else
                gain( 2, "combo_points" ) -- Default combo points gained.
            end
        end,
    },
    


    -- Instantly removes all existing harmful spell effects and increases your chance to resist all spells by 90% for 5 sec.  Does not remove effects that prevent you from using Cloak of Shadows.
    -- cloak_of_shadows = {
    --     id = 31224,
    --     cast = 0,
    --     cooldown = function() return 180 - 15 * talent.elusiveness.rank end,
    --     gcd = "totem",

    --     startsCombat = false,
    --     texture = 136177,

    --     toggle = "defensives",

    --     buff = "dispellable_magic",

    --     handler = function ()
    --         removeBuff( "dispellable_magic" )
    --         applyBuff( "cloak_of_shadows" )
    --     end,
    -- },


    -- When activated, increases the critical strike chance of your next offensive ability by 100%.
    cold_blood = {
        id = 14177,
        cast = 0,
        cooldown = 180, -- Fixed 3-minute cooldown in Classic.
        gcd = "off", -- No GCD for Cold Blood.
    
        talent = "cold_blood", -- Associated with the Cold Blood talent.
        startsCombat = false,
        texture = 135988,
    
        toggle = "cooldowns",
    
        nobuff = "cold_blood", -- Only usable if Cold Blood buff is not already active.
    
        handler = function ()
            applyBuff( "cold_blood" ) -- Apply the Cold Blood buff.
        end,
    }
    ,


    -- Finishing move that reduces the movement of the target by 50% for 6 sec and causes increased thrown weapon damage:     1 point  : 223 - 245 damage     2 points: 365 - 387 damage     3 points: 507 - 529 damage     4 points: 649 - 671 damage     5 points: 791 - 813 damage
    -- deadly_throw = {
    --     id = 26679,
    --     cast = 0,
    --     cooldown = 0,
    --     gcd = "totem",

    --     spend = 35,
    --     spendType = "energy",

    --     startsCombat = true,
    --     texture = 135430,

    --     usable = function() return combo_points.current > 0, "requires combo_points" end,

    --     handler = function ()
    --         applyDebuff( "target", "deadly_throw" )
    --         spend( combo_points.current, "combo_points" )
    --         if talent.throwing_specialization.rank == 2 then interrupt() end
    --     end,

    --     copy = { 26679, 48673, 48674 },
    -- },


    -- Disarm the enemy, removing all weapons, shield or other equipment carried for 10 sec.
    -- dismantle = {
    --     id = 51722,
    --     cast = 0,
    --     cooldown = 60,
    --     gcd = "totem",

    --     spend = 25,
    --     spendType = "energy",

    --     startsCombat = true,
    --     texture = 236272,

    --     toggle = "cooldowns",

    --     handler = function ()
    --         applyDebuff( "target", "dismantle" )
    --     end,
    -- },


    -- Throws a distraction, attracting the attention of all nearby monsters for 10 seconds.  Does not break stealth.
    distract = {
        id = 1725,
        cast = 0,
        cooldown = 30, -- Fixed cooldown of 30 seconds in Classic.
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 30, -- Fixed energy cost for Distract in Classic.
        spendType = "energy",
    
        startsCombat = false, -- Does not initiate combat.
        texture = 132289,
    
        handler = function ()
            -- No special handling needed for Distract in Classic.
        end,
    },
    


    -- Finishing move that consumes your Deadly Poison doses on the target and deals instant poison damage.  Following the Envenom attack you have an additional 15% chance to apply Deadly Poison and a 75% increased frequency of applying Instant Poison for 1 sec plus an additional 1 sec per combo point.  One dose is consumed for each combo point:    1 dose:  180 damage    2 doses: 361 damage    3 doses: 541 damage    4 doses: 722 damage    5 doses: 902 damage
    -- envenom = {
    --     id = 32645,
    --     cast = 0,
    --     cooldown = 0,
    --     gcd = "totem",

    --     spend = 35,
    --     spendType = "energy",

    --     startsCombat = true,
    --     texture = 132287,

    --     usable = function()
    --         if combo_points.current == 0 then
    --             return false, "requires combo_points"
    --         end

    --         if not debuff.deadly_poison.up then
    --             return false, "requires deadly_poison debuff"
    --         end

    --         return true
    --     end,

    --     handler = function ()
    --         if not ( glyph.envenom.enabled or talent.master_poisoner.rank == 3 ) then
    --             removeDebuffStack( "target", "deadly_poison", combo_points.current )
    --         end

    --         if talent.cut_to_the_chase.rank == 5 and buff.slice_and_dice.up then
    --             buff.slice_and_dice.expires = query_time + buff.slice_and_dice.duration
    --         end

    --         spend( combo_points.current, "combo_points" )
    --     end,

    --     copy = { 32645, 32684, 57992, 57993 },
    -- },


    -- Increases the rogue's dodge chance by 50% and reduces the chance ranged attacks hit the rogue by 25%.  Lasts 15 sec.
    evasion = {
        id = 5277,
        cast = 0,
        cooldown = 300, -- Updated cooldown for Classic WoW (5 minutes).
        gcd = "off",
    
        spend = 0,
        spendType = "energy",
    
        startsCombat = false,
        texture = 136205,
    
        toggle = "defensives",
    
        handler = function ()
            applyBuff( "evasion" )
        end,
    
        copy = { 5277 }, -- Removed additional ranks as Classic only has the base rank (5277).
    },
    


    -- Finishing move that causes damage per combo point:     1 point  : 256-391 damage     2 points: 452-602 damage     3 points: 648-813 damage     4 points: 845-1024 damage     5 points: 1040-1235 damage
    eviscerate = {
        id = 2098,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 35,
        spendType = "energy",
    
        startsCombat = true,
        texture = 132292,
    
        usable = function() return combo_points.current > 0, "requires combo_points" end,
    
        handler = function ()
            -- Removed Wrath-specific logic for Cut to the Chase talent, as it does not exist in Classic.
    
            spend( combo_points.current, "combo_points" )
        end,
    
        copy = { 2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300 }, -- Removed Wrath-specific ranks.
    },
    


    -- Finishing move that exposes the target, reducing armor by 20% and lasting longer per combo point:     1 point  : 6 sec.     2 points: 12 sec.     3 points: 18 sec.     4 points: 24 sec.     5 points: 30 sec.
    expose_armor = {
        id = 8647,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 25, -- Removed Wrath-specific talent Improved Expose Armor logic, as it does not exist in Classic.
        spendType = "energy",
    
        startsCombat = true,
        texture = 132354,
    
        usable = function() return combo_points.current > 0, "requires combo_points" end,
    
        handler = function ()
            spend( combo_points.current, "combo_points" )
        end,
    },
    


    -- Instantly throw both weapons at all targets within 8 yards, causing 105% weapon damage with daggers, and 70% weapon damage with all other weapons.
    -- fan_of_knives = {
    --     id = 51723,
    --     cast = 0,
    --     cooldown = 0,
    --     gcd = "totem",

    --     spend = 50,
    --     spendType = "energy",

    --     startsCombat = true,
    --     texture = 236273,

    --     handler = function ()
    --     end,
    -- },


    -- Performs a feint, causing no damage but lowering your threat by a large amount, making the enemy less likely to attack you.
    feint = {
        id = 1966,
        cast = 0,
        cooldown = 10,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 20, -- Removed glyph logic, as glyphs do not exist in Classic.
        spendType = "energy",
    
        startsCombat = false,
        texture = 132294,
    
        handler = function ()
            applyBuff( "feint" )
        end,
    
        copy = { 1966, 6768, 8637, 11303 }, -- Removed Wrath-specific ranks.
    },
    

    -- Garrote the enemy, silencing them for 3 sec causing 768 damage over 18 sec, increased by attack power.  Must be stealthed and behind the target.  Awards 1 combo point.
    garrote = {
        id = 703,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 50, -- Removed Wrath-specific talent Dirty Deeds logic, as it does not exist in Classic.
        spendType = "energy",
    
        startsCombat = true,
        texture = 132297,
    
        usable = function() return stealthed.all, "must be in stealth" end,
    
        handler = function ()
            applyDebuff( "target", "garrote" )
            gain( talent.initiative.rank > 0 and talent.initiative.rank or 1, "combo_points" ) -- Adjusted for Classic Initiative logic.
        end,
    
        copy = { 703, 8631, 8632, 8633, 11289, 11290 }, -- Removed Wrath-specific ranks.
    },
    


    -- Increases dodge by 15% for 7-11 seconds.
    ghostly_strike = {
        id = 14278,
        cast = 0,
        cooldown = 20, -- Removed glyph logic, as glyphs do not exist in Classic.
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 40,
        spendType = "energy",
    
        talent = "ghostly_strike",
        startsCombat = true,
        texture = 136136,
    
        handler = function ()
            applyBuff( "ghostly_strike" )
            gain( 1, "combo_points" )
            removeBuff( "remorseless" )
        end,
    },
    


    -- Causes 79 damage, incapacitating the opponent for 4 sec, and turns off your attack.  Target must be facing you.  Any damage caused will revive the target.  Awards 1 combo point.
    gouge = {
        id = 1776,
        cast = 0,
        cooldown = 10,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 45, -- Removed glyph logic, as glyphs do not exist in Classic.
        spendType = "energy",
    
        startsCombat = true,
        texture = 132155,
    
        handler = function ()
            applyDebuff( "target", "gouge" )
            gain( 1, "combo_points" )
        end,
    },
    


    -- An instant strike that deals 110% weapon damage (160% if a dagger is equipped) and causes the target to hemorrhage, increasing any Physical damage dealt to the target by up to 13.  Lasts 10 charges or 15 sec.  Awards 1 combo point.
    hemorrhage = {
        id = 16511,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 35, -- Removed Wrath-specific talent Slaughter from the Shadows logic, as it does not exist in Classic.
        spendType = "energy",
    
        talent = "hemorrhage",
        startsCombat = true,
        texture = 136168,
    
        handler = function ()
            applyDebuff( "target", "hemorrhage", nil, 10 )
            gain( 1, "combo_points" )
            removeBuff( "remorseless" )
        end,
    
        copy = { 16511, 17347, 17348 } -- Removed Wrath-specific ranks.
    },
    


    -- Enrages you, increasing all damage caused by 5%.  Requires a bleed effect to be active on the target.  Lasts 1 min.
    -- hunger_for_blood = {
    --     id = 63848,
    --     cast = 0,
    --     cooldown = 0,
    --     gcd = "totem",

    --     spend = 15,
    --     spendType = "energy",

    --     talent = "hunger_for_blood",
    --     startsCombat = true,
    --     texture = 236276,

    --     usable = function()
    --         return debuff.bleed.up
    --     end,

    --     handler = function ()
    --         applyBuff( "hunger_for_blood" )
    --     end,
    -- },


    -- A quick kick that interrupts spellcasting and prevents any spell in that school from being cast for 5 sec.
    kick = {
        id = 1766,
        cast = 0,
        cooldown = 10,
        gcd = "off",
    
        spend = 25,
        spendType = "energy",
    
        startsCombat = true,
        texture = 132219,
    
        toggle = "interrupts",
    
        debuff = "casting",
    
        handler = function ()
            interrupt()
            -- Removed Improved Kick logic, as it does not apply a silence in Classic WoW.
        end,
    },
    


    -- Finishing move that stuns the target.  Lasts longer per combo point:     1 point  : 2 seconds     2 points: 3 seconds     3 points: 4 seconds     4 points: 5 seconds     5 points: 6 seconds
    kidney_shot = {
        id = 408,
        cast = 0,
        cooldown = 20,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 25,
        spendType = "energy",
    
        startsCombat = true,
        texture = 132298,
    
        usable = function() return combo_points.current > 0, "requires combo_points" end,
    
        handler = function ()
            applyDebuff( "target", "kidney_shot" )
            spend( combo_points.current, "combo_points" )
        end,
    
        copy = { 408 }, -- Removed additional rank as only the base rank exists in Classic WoW.
    },
    


    -- Step through the shadows from enemy to enemy within 10 yards, attacking an enemy every .5 secs with both weapons until 5 assaults are made, and increasing all damage done by 20% for the duration.  Can hit the same target multiple times.  Cannot hit invisible or stealthed targets.
    -- killing_spree = {
    --     id = 51690,
    --     cast = 0,
    --     cooldown = function() return glyph.killing_spree.enabled and 75 or 120 end,
    --     gcd = "totem",

    --     spend = 0,
    --     spendType = "energy",

    --     talent = "killing_spree",
    --     startsCombat = true,
    --     texture = 236277,

    --     toggle = "cooldowns",

    --     handler = function ()
    --         applyBuff( "killing_spree" )
    --         setCooldown( "global_cooldown", 2.5 )
    --     end,
    -- },


    -- Instantly attacks with both weapons for 100% weapon damage plus an additional 44 with each weapon.  Damage is increased by 20% against Poisoned targets.  Awards 2 combo points.
    -- mutilate = {
    --     id = 1329,
    --     cast = 0,
    --     cooldown = 0,
    --     gcd = "totem",

    --     spend = function() return glyph.mutilate.enabled and 55 or 60 end,
    --     spendType = "energy",

    --     talent = "mutilate",
    --     startsCombat = true,
    --     texture = 132304,

    --     handler = function ()
    --         gain( 2, "combo_points" )
    --         removeBuff( "remorseless" )
    --     end,

    --     copy = { 1329, 34411, 34412, 34413, 48663, 48666 },
    -- },


    -- When used, adds 2 combo points to your target.  You must add to or use those combo points within 20 sec or the combo points are lost.
    premeditation = {
        id = 14183,
        cast = 0,
        cooldown = 120, -- Updated cooldown to match Classic WoW (2 minutes).
        gcd = "off",
    
        spend = 0,
        spendType = "energy",
    
        talent = "premeditation",
        startsCombat = false,
        texture = 136183,
    
        usable = function() return stealthed.all, "must be in stealth" end,
    
        handler = function ()
            gain( 2, "combo_points" )
        end,
    },
    


    -- When activated, this ability immediately finishes the cooldown on your Evasion, Sprint, Vanish, Cold Blood and Shadowstep abilities.
    preparation = {
        id = 14185,
        cast = 0,
        cooldown = 600, -- Fixed cooldown for Classic WoW (10 minutes).
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        talent = "preparation",
        startsCombat = false,
        texture = 136121,
    
        toggle = "cooldowns",
    
        handler = function ()
            setCooldown( "evasion", 0 )
            setCooldown( "sprint", 0 )
            setCooldown( "vanish", 0 )
            setCooldown( "cold_blood", 0 )
            -- Removed shadowstep reset, as shadowstep does not exist in Classic.
            -- Removed glyph logic, as glyphs do not exist in Classic.
        end,
    },
    

    -- A strike that becomes active after parrying an opponent's attack.  This attack deals 150% weapon damage and slows their melee attack speed by 20% for 30 sec.  Awards 1 combo point.
    riposte = {
        id = 14251,
        cast = 0,
        cooldown = 6,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 10,
        spendType = "energy",
    
        talent = "riposte",
        startsCombat = true,
        texture = 132336,
    
        handler = function ()
            applyDebuff( "target", "riposte" )
            gain( 1, "combo_points" )
        end,
    },
    


    -- Finishing move that causes damage over time, increased by your attack power.  Lasts longer per combo point:     1 point  : 346 damage over 8 secs     2 points: 505 damage over 10 secs     3 points: 685 damage over 12 secs     4 points: 887 damage over 14 secs     5 points: 1111 damage over 16 secs
    rupture = {
        id = 1943,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 25,
        spendType = "energy",
    
        startsCombat = true,
        texture = 132302,
    
        usable = function() return combo_points.current > 0, "requires combo_points" end,
    
        handler = function ()
            applyDebuff( "target", "rupture" )
            spend( combo_points.current, "combo_points" )
        end,
    
        copy = { 1943, 8639, 8640, 11273, 11274, 11275 }, -- Removed Wrath-specific ranks.
    },
    


    -- Incapacitates the target for up to 45 sec.  Must be stealthed.  Only works on Humanoids that are not in combat.  Any damage caused will revive the target.  Only 1 target may be sapped at a time.
    sap = {
        id = 2070,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 65, -- Removed Dirty Tricks logic, as it does not reduce energy cost in Classic.
        spendType = "energy",
    
        startsCombat = true,
        texture = 132310,
    
        usable = function() return stealthed.all, "must be in stealth" end,
    
        handler = function ()
            applyDebuff( "target", "sap" )
        end,
    
        copy = { 2070, 6770, 11297 }, -- Removed Wrath-specific ranks.
    },
    

    -- Enter the Shadow Dance for 6 sec, allowing the use of Sap, Garrote, Ambush, Cheap Shot, Premeditation, Pickpocket and Disarm Trap regardless of being stealthed.
    -- shadow_dance = {
    --     id = 51713,
    --     cast = 0,
    --     cooldown = 60,
    --     gcd = "off",

    --     talent = "shadow_dance",
    --     startsCombat = false,
    --     texture = 236279,

    --     toggle = "cooldowns",

    --     handler = function ()
    --         applyBuff( "shadow_dance" )
    --     end,
    -- },


    -- Attempts to step through the shadows and reappear behind your enemy and increases movement speed by 70% for 3 sec.  The damage of your next ability is increased by 20% and the threat caused is reduced by 50%.  Lasts 10 sec.
    -- shadowstep = {
    --     id = 36554,
    --     cast = 0,
    --     cooldown = function() return 30 - 5 * talent.filthy_tricks.rank end,
    --     gcd = "off",

    --     spend = function() return 10 - 5 * talent.filthy_tricks.rank end,
    --     spendType = "energy",

    --     talent = "shadowstep",
    --     startsCombat = true,
    --     texture = 132303,

    --     handler = function ()
    --         applyBuff( "shadowstep_sprint" )
    --         applyBuff( "shadowstep" )
    --         setDistance( 7.5 )
    --     end,
    -- },


    -- Performs an instant off-hand weapon attack that automatically applies the poison from your off-hand weapon to the target.  Slower weapons require more Energy.  Neither Shiv nor the poison it applies can be a critical strike.  Awards 1 combo point.
    shiv = {
        id = 5938,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 40, -- TODO: Cost is based on weapon speed.
        spendType = "energy",

        startsCombat = true,
        texture = 135428,

        handler = function ()
            -- TODO: Apply offhand poison.
            gain( 1, "combo_points" )
        end,
    },


    -- An instant strike that causes 98 damage in addition to 100% of your normal weapon damage.  Awards 1 combo point.
    sinister_strike = {
        id = 1752,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = function()
            if talent.improved_sinister_strike.rank == 2 then return 40 end
            if talent.improved_sinister_strike.rank == 1 then return 42 end
            return 45
        end,
        spendType = "energy",
    
        startsCombat = true,
        texture = 136189,
    
        handler = function ()
            gain( 1, "combo_points" )
            removeBuff( "remorseless" )
        end,
    
        copy = { 1752, 1757, 1758, 1759, 1760, 8621, 11293, 11294 }, -- Removed Wrath-specific ranks.
    },
    


    -- Finishing move that increases melee attack speed by 40%.  Lasts longer per combo point:     1 point  : 9 seconds     2 points: 12 seconds     3 points: 15 seconds     4 points: 18 seconds     5 points: 21 seconds
    slice_and_dice = {
        id = 5171,
        cast = 0,
        cooldown = 0,
        gcd = "spell", -- Updated for Classic GCD conventions.
    
        spend = 25,
        spendType = "energy",
    
        startsCombat = true,
        texture = 132306,
    
        usable = function() return combo_points.current > 0, "requires combo_points" end,
    
        handler = function ()
            applyBuff( "slice_and_dice" )
            spend( combo_points.current, "combo_points" )
        end,
    
        copy = { 5171 }, -- Removed Wrath-specific ranks.
    },
    


    -- Increases the rogue's movement speed by 70% for 15 sec.  Does not break stealth.
    sprint = {
        id = 2983,
        cast = 0,
        cooldown = 300, -- Updated cooldown to match Classic WoW (5 minutes).
        gcd = "off",
    
        startsCombat = false,
        texture = 132307,
    
        toggle = "interrupts",
    
        handler = function ()
            applyBuff( "sprint" )
        end,
    
        copy = { 2983 }, -- Removed additional ranks as Classic WoW only has the base rank.
    },
    


    -- Allows the rogue to sneak around, but reduces your speed by 30%.  Lasts until cancelled.
    stealth = {
        id = 1784,
        cast = 0,
        cooldown = 10, -- Removed talent-based cooldown reduction, as it does not exist in Classic.
        gcd = "off",
    
        startsCombat = false,
        texture = 132320,
    
        usable = function() return time == 0, "cannot be in combat" end,
    
        handler = function ()
            applyBuff( "stealth" )
        end,
    },
    


    -- The current party or raid member becomes the target of your Tricks of the Trade.  The threat caused by your next damaging attack and all actions taken for 6 sec afterwards will be transferred to the target.  In addition, all damage caused by the target is increased by 15% during this time.
    -- tricks_of_the_trade = {
    --     id = 57934,
    --     cast = 0,
    --     cooldown = function() return 30 - 5 * talent.filthy_tricks.rank end,
    --     gcd = "totem",

    --     spend = function() return 15 - 5 * talent.filthy_tricks.rank end,
    --     spendType = "energy",

    --     startsCombat = false,
    --     texture = 236283,

    --     handler = function ()
    --         applyBuff( "tricks_of_the_trade" )
    --     end,
    -- },


    -- Allows the rogue to vanish from sight, entering an improved stealth mode for 10 sec.  Also breaks movement impairing effects.  More effective than Vanish (Rank 2).
    vanish = {
        id = 1856,
        cast = 0,
        cooldown = 300, -- Updated cooldown to match Classic WoW (5 minutes). Removed talent-based cooldown reduction, as it does not exist in Classic.
        gcd = "off",
    
        spend = 0,
        spendType = "energy",
    
        startsCombat = true,
        texture = 132331,
    
        toggle = "cooldowns",
    
        handler = function ()
            applyBuff( "stealth" )
        end,
    
        copy = { 1856 }, -- Removed additional ranks, as Classic WoW only has the base rank.
    },
} )
    

spec:RegisterSetting("rogue_description", nil, {
    type = "description",
    name = "Adjust the settings below according to your playstyle preference. It is always recommended that you use a simulator "..
        "to determine the optimal values for these settings for your specific character."
})

spec:RegisterSetting("rogue_description_footer", nil, {
    type = "description",
    name = "\n\n"
})

spec:RegisterSetting("rogue_general", nil, {
    type = "header",
    name = "General"
})

spec:RegisterSetting("rogue_general_description", nil, {
    type = "description",
    name = "General settings will change the parameters used in the core rotation.\n\n"
})

spec:RegisterSetting("maintain_expose", false, {
    type = "toggle",
    name = "Maintain Expose Armor",
    desc = "When enabled, expose armor will be recommended when there is no major armor debuff up on the boss",
    width = "full",
    set = function( _, val )
        Hekili.DB.profile.specs[ 4 ].settings.maintain_expose = val
    end
})

spec:RegisterSetting("rogue_general_footer", nil, {
    type = "description",
    name = "\n\n"
})


spec:RegisterOptions( {
    enabled = true,

    aoe = 3,

    nameplates = true,
    nameplateRange = 8,

    damage = false,
    damageExpiration = 6,

    package = "Assassination",
    usePackSelector = true
} )


spec:RegisterPack( "Assassination", 20230126, [[Hekili:DwvtVnUnq0Fl7LGw01YXFTTDBCaArrbsoKdRs7LILMuuJLimfPajLvDpWF7Dgz7yPDTst7fBzQ38EZm8nJzZypZsZfbG908BNVC2S5ltMTyXQzRyPHd1alTwi3jkWhmIk8ZF27fEVYickRjY)MwBBitMuu8Te0dARiNO0BBCseEziu7)40PTTTjk5Hj7bLXNiTvtXaNi1exYPoBrdmjV2pPEpmXzdDSprAT6CBRXprKP0QGc8S0SgLo8GHLDT8E5Cu6AqYEAjQTkphoce8sw6ZLkFKx7uwNkCiYPFLj8qEK3utftOeI8uqOJ8FdPoY)vrrb4I8pr5xKx0OYXV2ABmymuepGL0FqLeY0bkwTwzsWoHZUvPX6xiPkXNu7aSOZeH1(akqOm(y8XtV87wpDNsU79QTRdcxbesKcFqzk6JquL14ljmNiat7EVodVL8brgb4DxfHxRKWgHjFto(aHlRz72KHhNqT7BOm1UP2Qmb)9RNpinYDGrGfjSXH5ZyPqFgUB1G0qzuy(524do1o4Fb8xLZ9XUE1nxReCqLaVrUBrFMG9kVeC4T6xZYGIqlYHnB1no3bcj9M9WgWavO77(zVsV4AWpMG9jnPP(TMxS09GZJa784lUD28pWsBfodAn8xSZDoTJU5kfnAwe5(M6ARlqEv0(wG5JtjrdUtz2bbFsKJE3WXG6CMvGjNgecLc8yaf(WGrfJu3Gtr4RuOXY9r0(YNe5)5V7bIjOY)53h5TLkzzF0cZHlQg5glr(FvJxyQG(cV50tNM)ol6pHtyUZY88rkI8zFMinV)rZ7PCRsR7vrNOmCgAx3O7ittvg4iH9ABij(4dvudJoyoQG842nnAvXM1JS0UN62vcBfn6a(4tD7orhqMgYz)clvIPn2Nf4MZbJXN3cWsPXCwaVohnYxgDt62jEj0JZ)uWlgn43HvZyXFE6Kyy5Omm2kHi)MiVV7mYVFn2QUW)WGivwrQ8s6pCwPV8i0pmAcnuZ7I8vxVK(()xm8flJiI(H3iry1VQRR8kRG6KBXR1J(X)dQDHNllnioMD7OKmCDeENHdq96F9wl1r04g6Rr0LQ)l2Vn(TojY4E)3CjhO)G90)N(YG4ln5JtadDyDXiAcLwhl9tLqZF3De7Fc]] )

spec:RegisterPack( "Combat", 20230211, [[Hekili:vsvtZnUnm0)n5sxl)vCBNTX(q7PKd5WQ0EPZstksyloMIudjLv9oz4V9fqEDLuMypzVKqdb(EapWhyZzVWYvIiWEEXSf3pF(I7ZMVC19ZMZYJNQbwETqEqShpyfv4F)lxvHisHpzCcfD9GRXlXpvgJ1HppDABBBMwEAYrqBdzsx10wx7ePrecA5uVBFdmrvhMuFeM4Drru7StKoNr5ATHjIcTrh1qGLx0OnXhTSI3TgrMRbj7z8qPwPGZ5bbjl)LsDiXR9ANxhpL40VkebqL4n1oBIhlHepV15XiFHQOeFFJwH)BNRXIbPKEeBI)HAc8Yii5GXOTzSCJoedDchSt0yI4XN7esWkkmGI9NSCjsm41cugf(9qmtkcrTDplxiPgMLFqlpWIypD1Bw0SBxwWOLWwHvTvHhYinkXVlXrDTWTT2PTrS(2SoXx0J94lrSS8QSmgieNvD4)EK7HkrNC8qIV8wSD)vzJUZrylyHkCeJfEIpVNVcJqbB3zA8(tzn1j(RVsD65NgJ)6)xlecZ6lgHYJeJdkyRVjusvZQFQQPhQH8r48RFqn8HpKgsJSHIO2IpRa)2q0Rp0PI)2hKpcPv9ibh1bj4jddcYVtGCnsgGEKrUApipBWF5CGJGpq3KCElNTyoQoTcVfFih6DzUDAdC2KvPrtUDFIhAQRD(i5N8O3cvyVwI(oV2EaIHSeh9xXZxQJ0kWQi)zSuGHbK4tJCWwPPrrZiqJMx)NtpL4ts8)9VdaHeuf(6Ns82sTSCy2c7PEwtCRJa))QXzIoA6XvrN(XAHlK(h4wa)fAE5me47JVsGQggAXaMB1gZGo6hqgVKANA0fY2uvaEI4GXfZsp9yfjyua0qCEGL4DRAWpIJWMyPZZY)sj08nAs1P6xgTHFz9uAHYN07wpEHt6P(mg)uKY9ARyUB4lSnRxCBugM86v3DJN9pSCisVXRsqn2rUz(DV3EHxF9M7e2mF2qwgMY7rXOEBSb5Tn3d3S52SEu317dFlmBwV6gK258yFp]] )


spec:RegisterPackSelector( "assassination", "Assassination", "|T132292:0|t Assassination",
    "If you have spent more points in |T132292:0|t Assassination than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab1 > max( tab2, tab3 )
    end )

spec:RegisterPackSelector( "combat", "Combat", "|T132090:0|t Combat",
    "If you have spent more points in |T132090:0|t Combat than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab2 > max( tab1, tab3 )
    end )

spec:RegisterPackSelector( "subtlety", nil, "|T132320:0|t Subtlety",
    "If you have spent more points in |T132320:0|t Subtlety than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab3 > max( tab1, tab2 )
    end )