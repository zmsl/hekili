if UnitClassBase( 'player' ) ~= 'WARRIOR' then return end

local addon, ns = ...
local Hekili = _G[ addon ]
local class, state = Hekili.Class, Hekili.State
local FindUnitDebuffByID = ns.FindUnitDebuffByID
local IsCurrentSpell = _G.IsCurrentSpell
local spec = Hekili:NewSpecialization( 1 )

local function swingSpend(action)
    return type(action.swingSpend) == "function" and action.swingSpend() or action.swingSpend
end

local function rage_amount( isOffhand )
    local d
    if isOffhand then d = select( 3, UnitDamage( "player" ) ) * 0.7
    else d = UnitDamage( "player" ) * 0.7 end

    local c = ( state.level > 70 and 1.4139 or 1 ) * ( 0.0091107836 * ( state.level ^ 2 ) + 3.225598133 * state.level + 4.2652911 )
    local f = isOffhand and 1.75 or 3.5
    local s = isOffhand and ( select( 2, UnitAttackSpeed( "player" ) ) or 2.5 ) or UnitAttackSpeed( "player" )

    return min( ( 15 * d ) / ( 4 * c ) + ( f * s * 0.5 ), 15 * d / c ) * ( state.talent.endless_rage.enabled and 1.25 or 1 ) * ( state.buff.defensive_stance.up and 0.95 or 1 )
end

spec:RegisterResource( Enum.PowerType.Rage, {

    bloodrage = {
        aura = "bloodrage",

        last = function ()
            local app = state.buff.bloodrage.applied
            local t = state.query_time

            return app + floor( t - app )
        end,

        interval = 1,
        value = 1
    },

    mainhand = {
        swing = "mainhand",

        last = function ()
            local swing = state.combat == 0 and state.now or state.swings.mainhand
            local t = state.query_time

            return swing + ( floor( ( t - swing ) / state.swings.mainhand_speed ) * state.swings.mainhand_speed )
        end,

        interval = "mainhand_speed",

        stop = function ()
            return state.combat == 0 and state.swings.mainhand == 0 or state.query_time - state.now > 30
        end,
        value = function( now )
            return state.buff.heroic_strike.expires < now and state.buff.cleave.expires < now and rage_amount() or 0
        end,
    },

    offhand = {
        swing = "offhand",

        last = function ()
            local swing = state.combat == 0 and state.now or state.swings.offhand
            local t = state.query_time

            return swing + ( floor( ( t - swing ) / state.swings.offhand_speed ) * state.swings.offhand_speed )
        end,

        interval = "offhand_speed",

        stop = function ()
            return state.combat == 0 and state.swings.offhand == 0 or state.query_time - state.now > 30
        end,
        value = function( now )
            return rage_amount( true ) or 0
        end,
    },
} )

-- Talents
spec:RegisterTalents( {
    improved_heroic_strike = { 70, 3, 12282, 12663, 12664 },
    deflection = { 71, 5, 16462, 16463, 16464, 16465, 16466 },
    improved_rend = { 72, 3, 772, 6546, 6547, 6548, 11572, 11573, 11574, 12659 },
    improved_charge = { 73, 2, 12285, 12697 },
    tactical_mastery = { 74, 5, 12295, 12676, 12677, 12678, 12679 },
    improved_thunder_clap = { 75, 3, 12287, 12665, 12666 },
    improved_overpower = { 76, 2, 12290, 12963 },
    anger_management = { 77, 1, 12296 },
    deep_wounds = { 78, 3, 12834, 12849, 12867 },
    two_handed_weapon_specialization = { 79, 5, 12163, 12711, 12712, 12713, 12714 },
    impale = { 80, 2, 16493, 16494 },
    axe_specialization = { 81, 5, 12785, 12700, 12781, 12783, 12784 },
    sweeping_strikes = { 82, 1, 12292 },
    mace_specialization = { 83, 5, 12704, 12284, 12701, 12702, 12703 },
    sword_specialization = { 84, 5, 12815, 12281, 12812, 12813, 12814 },
    polearm_specialization = { 85, 5, 12833, 12165, 12830, 12831, 12832 },
    improved_hamstring = { 86, 3, 23695, 12289, 12668 },
    mortal_strike = { 87, 1, 12294, 21551, 21552, 21553 },
    booming_voice = { 88, 5, 12838, 12321, 12835, 12836, 12837 },
    cruelty = { 89, 5, 12856, 12320, 12852, 12853, 12855 },
    improved_demoralizing_shout = { 90, 5, 12879, 12324, 12876, 12877, 12878 },
    unbridled_wrath = { 91, 5, 13002, 12322, 12999, 13000, 13001 },
    improved_cleave = { 92, 3, 20496, 12329, 12950 },
    piercing_howl = { 93, 1, 12323 },
    blood_craze = { 94, 3, 16492, 16487, 16489 },
    improved_battle_shout = { 95, 5, 12861, 12318, 12857, 12858, 12860 },
    dual_wield_specialization = { 96, 5, 23588, 23584, 23585, 23586, 23587 },
    improved_execute = { 97, 2, 20503, 20502 },
    enrage = { 98, 5, 13048, 12317, 13045, 13046, 13047 },
    improved_slam = { 99, 5, 20499, 12330, 12862, 20497, 20498 },
    death_wish = { 100, 1, 12328 },
    improved_intercept = { 101, 2, 20505, 20504 },
    improved_berserker_rage = { 102, 2, 20501, 20500 },
    flurry = { 103, 5, 12974, 12319, 12971, 12972, 12973 },
    bloodthirst = { 104, 1, 23881, 23892, 23893, 23894 },
    shield_specialization = { 105, 5, 12727, 12298, 12724, 12725, 12726 },
    anticipation = { 106, 5, 12753, 12297, 12750, 12751, 12752 },
    improved_bloodrage = { 107, 2, 12818, 12301 },
    toughness = { 108, 5, 12764, 12299, 12761, 12762, 12763 },
    iron_will = { 109, 5, 12962, 12300, 12959, 12960, 12961 },
    last_stand = { 110, 1, 12975 },
    improved_shield_block = { 111, 3, 12945, 12307, 12944 },
    improved_revenge = { 112, 3, 12800, 12797, 12799 },
    defiance = { 113, 5, 12792, 12303, 12788, 12789, 12791 },
    improved_sunder_armor = { 114, 3, 12810, 12308, 12811 },
    improved_disarm = { 115, 3, 12807, 12313, 12804 },
    improved_taunt = { 116, 2, 12765, 12302 },
    improved_shield_wall = { 117, 2, 12803, 12312 },
    concussion_blow = { 118, 1, 12809 },
    improved_shield_bash = { 119, 2, 12958, 12311 },
    one_handed_weapon_specialization = { 120, 5, 16542, 16538, 16539, 16540, 16541 },
    shield_slam = { 121, 1, 23922, 23923, 23924, 23925 },
} )

-- Auras
spec:RegisterAuras( {
    my_battle_shout = {
        duration = function() return 120 * ( 1 + talent.booming_voice.rank * 0.1 ) end,
        max_stack = 1,
        generate = function( t )
            for i, id in ipairs( class.auras.battle_shout.copy ) do
                local name, _, count, _, duration, expires, caster = FindUnitBuffByID( "player", id, "PLAYER" )

                if name then
                    t.name = name
                    t.count = 1
                    t.expires = expires
                    t.applied = expires - duration
                    t.caster = caster
                    return
                end
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    battle_stance = {
        id = 2457,
        duration = 3600,
        max_stack = 1,
    },
    -- Immune to Fear, Sap and Incapacitate effects.  Generating extra rage when taking damage.
    berserker_rage = {
        id = 18499,
        duration = 10,
        max_stack = 1,
    },
    berserker_stance = { -- TODO: Check Aura (https://wowhead.com/wotlk/spell=2458)
        id = 2458,
        duration = 3600,
        max_stack = 1,
    },
    -- Regenerates $o1% of your total Health over $d.
    blood_craze = {
        id = 16491,
        duration = 6,
        tick_time = 1,
        max_stack = 1,
        copy = { 16491, 16490, 16488 },
    },
    -- Generating $/10;s1 Rage per second.
    bloodrage = {
        id = 29131,
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    -- Taunted.
    challenging_shout = {
        id = 1161,
        duration = 6,
        max_stack = 1,
    },
    -- Stunned.
    charge_stun = {
        id = 7922,
        duration = 1,
        max_stack = 1,
    },
    cleave = {
        duration = function () return swings.mainhand_speed end,
        max_stack = 1,
    },
    -- Stunned.
    concussion_blow = {
        id = 12809,
        duration = 5,
        max_stack = 1,
    },
    -- Increases physical damage by $s1%.  Increases all damage taken by $s3%.
    death_wish = {
        id = 12328,
        duration = 30,
        max_stack = 1,
    },
    defensive_stance = {
        id = 71,
        duration = 3600,
        max_stack = 1,
    },
    deep_wound = {
        id = 23255,
        duration = 12,
        max_stack = 1,
        copy = { 23255, 23256 }
    },
    -- Disarmed!
    disarm = {
        id = 676,
        duration = function() return 10 + talent.improved_disarm.rank end,
        max_stack = 1,
    },
    -- Physical damage increased by $s1%.
    enrage = {
        id = 12880,
        duration = 12,
        max_stack = 1,
        copy = { 12880, 14201, 14202, 14203, 14204 },
    },
    -- Attack speed increased by $s1%.
    flurry = {
        id = 12966,
        duration = 15,
        max_stack = 1,
        copy = { 12966, 12967, 12968, 12969, 12970 },
    },
    -- Movement slowed by $s1%.
    hamstring = {
        id = 1715,
        duration = 15,
        max_stack = 1,
    },
    heroic_strike = {
        duration = function () return swings.mainhand_speed end,
        max_stack = 1,
    },
    -- Immobilized.
    improved_hamstring = {
        id = 12668,
        duration = 5,
        max_stack = 1,
        copy = { 12668, 12289 },
    },
    -- Stunned.
    intercept_stun = {
        id = 20253,
        duration = 3,
        max_stack = 1,
        copy = { 20253, 20614, 20615 },
    },
    -- Cowering in fear.
    intimidating_shout = {
        id = 20511,
        duration = 8,
        max_stack = 1,
        copy = { 20511, 5246 },
    },
    last_stand = {
        id = 12976,
        duration = 20,
        max_stack = 1,
    },
    -- Taunted.
    mocking_blow = {
        id = 694,
        duration = 6,
        max_stack = 1,
        copy = { 694, 7400, 7402, 20559, 20560 },
    },
    -- Healing effects reduced by $s1%.
    mortal_strike = {
        id = 12294,
        duration = 10,
        max_stack = 1,
        copy = { 12294, 21551, 21552, 21553 },
    },
    -- Allows the use of Overpower.
    overpower_ready = {
        duration = 6,
        max_stack = 1,
    },
    -- Dazed.
    piercing_howl = {
        id = 12323,
        duration = 6,
        max_stack = 1,
    },
    -- Special ability attacks have an additional $s1% chance to critically hit but all damage taken is increased by $s2%.
    recklessness = {
        id = 1719,
        duration = 15,
        max_stack = 1,
    },
    -- Bleeding for $s1 plus a percentage of weapon damage every $t1 seconds.  If used while the victim is above $s2% health, Rend does $s3% more damage.
    rend = {
        id = 772,
        duration = 21,
        tick_time = 3,
        max_stack = 1,
        copy = { 772, 6546, 6547, 6548, 11572, 11573, 11574 },
    },
    -- Counterattacking all melee attacks.
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
    revenge_usable = {
        duration = 5,
        max_stack = 1,
    },
    shield_bash_silenced = {
        id = 18498,
        duration = 3,
        max_stack = 1,
    },
    -- Block chance and block value increased by $s1%.
    shield_block = {
        id = 2565,
        duration = function() return talent.improved_shield_block.enabled and 7 or 5 end,
        max_stack = 1,
    },
    -- All damage taken reduced by $s1%.
    shield_wall = {
        id = 871,
        duration = function() return 10 + ( talent.improved_shield_wall.rank == 2 and 5 or talent.improved_shield_wall.rank == 1 and 2 or 0 ) end,
        max_stack = 1,
    },
    -- Your next $n melee attacks strike an additional nearby opponent.
    sweeping_strikes = {
        id = 12328,
        duration = 30,
        max_stack = 5,
    },
    -- Taunted.
    taunt = {
        id = 355,
        duration = 3,
        max_stack = 1,
    },
    -- Attack speed reduced by $s2%.
    thunder_clap = {
        id = 6343,
        duration = 30,
        max_stack = 1,
        shared = "target",
        copy = { 6343, 8198, 8204, 8205, 11580, 11581, 13532 },
    },
    -- Aliases / polybuffs.
    stance = {
        alias = { "battle_stance", "defensive_stance", "berserker_stance" },
        aliasMode = "first",
        aliasType = "buff",
    },
    shout = {
        alias = { "my_battle_shout" },
        aliasMode = "first",
        aliasType = "buff"
    },
    windfury = {
        id = 8512,
        duration = 120,
        max_stack = 1,
        copy = { 8512, 10613, 10614 }
    }
} )

local enemy_revenge_trigger = 0
local enemy_dodged = 0
local enemy_dodged_target
local last_overpower = 0
local last_overpower_target

local misses = {
    DODGE = true,
    PARRY = true,
    BLOCK = true
}

-- Combat log handlers
local attack_events = {
    SPELL_CAST_SUCCESS = true
}

local application_events = {
    SPELL_AURA_APPLIED      = true,
    SPELL_AURA_APPLIED_DOSE = true,
    SPELL_AURA_REFRESH      = true,
}

local removal_events = {
    SPELL_AURA_REMOVED      = true,
    SPELL_AURA_BROKEN       = true,
    SPELL_AURA_BROKEN_SPELL = true,
}

local death_events = {
    UNIT_DIED               = true,
    UNIT_DESTROYED          = true,
    UNIT_DISSIPATES         = true,
    PARTY_KILL              = true,
    SPELL_INSTAKILL         = true,
}

local tick_events = {
    SPELL_PERIODIC_DAMAGE   = true
}

spec:RegisterEvent( "COMBAT_LOG_EVENT_UNFILTERED", function()
    local _, subtype, _,  sourceGUID, sourceName, _, _, destGUID, destName, destFlags, _, actionType, _, _, spellMissType, _, _, critical = CombatLogGetCurrentEventInfo()

    if sourceGUID == state.GUID and subtype:match( "_MISSED$" ) and ( actionType == "DODGE" or spellMissType == "DODGE" ) then
        enemy_dodged = GetTime()
        enemy_dodged_target = destGUID
    elseif destGUID == state.GUID and subtype:match( "_MISSED$" ) and misses[ actionType ] then
        enemy_revenge_trigger = GetTime()
    elseif sourceGUID == state.GUID and subtype == "SPELL_CAST_SUCCESS" then
        if actionType == class.abilities.overpower.id then
            last_overpower = GetTime()
            last_overpower_target = destGUID
        end
    end
end )

local avg_rage_amount = rage_amount()+rage_amount(true)
spec:RegisterStateExpr("rage_gain", function()
    return avg_rage_amount+(buff.bloodrage.up and 1 or 0)
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

spec:RegisterStateFunction( "swap_stance", function( stance )
    removeBuff( "battle_stance" )
    removeBuff( "defensive_stance" )
    removeBuff( "berserker_stance" )

    local swap = rage.current - ( 5 * talent.tactical_mastery.rank )
    if swap > 0 then
        spend( swap, "rage" )
    end

    if stance then applyBuff( stance )
    else applyBuff( "stance" ) end
end )

local finish_heroic_strike = setfenv( function()
    spend( swingSpend(action.heroic_strike), "rage" )
end, state )

spec:RegisterStateFunction( "start_heroic_strike", function()
    applyBuff( "heroic_strike", swings.time_to_next_mainhand )
    state:QueueAuraExpiration( "heroic_strike", finish_heroic_strike, buff.heroic_strike.expires )
end )

local finish_cleave = setfenv( function()
    spend( swingSpend(action.cleave), "rage" )
end, state )

spec:RegisterStateFunction( "start_cleave", function()
    applyBuff( "cleave", swings.time_to_next_mainhand )
    state:QueueAuraExpiration( "cleave", finish_cleave, buff.cleave.expires )
end )

local should_queue_events = {
    { time = 0, spend = 0, priority = 1, name = "" },
    { time = 0, spend = 0, priority = 2, name = "" },
    { time = 0, spend = 0, priority = 3, name = "" }
}
spec:RegisterStateFunction( "should_queue", function(queue_cost)
    Hekili:Debug("Checking if we should queue for "..tostring(queue_cost).." at rage "..tostring(rage.current))

    local primary_action = IsSpellKnown( class.abilities.mortal_strike.id ) and "MS" or "BT"
    local primary_ttr = query_time + (primary_action == "MS" and cooldown.mortal_strike.remains or cooldown.bloodthirst.remains)
    local primary_spend = primary_action == "MS" and action.mortal_strike.cost or action.bloodthirst.cost
    local primary_name = primary_action == "MS" and "Mortal Strike" or "Bloodthirst"
    for i, event in ipairs(should_queue_events) do
        if i == 1 then
            event.time = primary_ttr
            event.spend = primary_spend
            event.name = primary_name
            Hekili:Debug("Set "..tostring(event.name).." at "..tostring(event.time).." for "..tostring(event.spend))
        elseif i == 2 then
            event.time = query_time + cooldown.whirlwind.remains
            event.spend = action.whirlwind.cost
            event.name = "Whirlwind"
            Hekili:Debug("Set "..tostring(event.name).." at "..tostring(event.time).." for "..tostring(event.spend))
        elseif i == 3 then
            event.time = query_time + mainhand_remains
            event.spend = queue_cost
            event.name = "Swing"
            Hekili:Debug("Set "..tostring(event.name).." at "..tostring(event.time).." for "..tostring(event.spend))
        end
    end

    table.sort(should_queue_events, function(a, b)
        if a.time == b.time then
            return a.priority < b.priority
        else
            return a.time < b.time
        end
    end)

    local spent_rage = 0
    for i, event in ipairs(should_queue_events) do
        spent_rage = spent_rage + event.spend

        Hekili:Debug("Evaluating "..tostring(event.name).." at "..tostring(event.time).." for "..tostring(event.spend).." (total spent: "..tostring(spent_rage)..")")

        local next_event = should_queue_events[i + 1]
        if next_event then
            local required_rage = next_event.spend + spent_rage
            local time_to_rage = query_time + state:TimeToResource(rage, required_rage)

            Hekili:Debug("Next event is "..tostring(next_event.name).." at "..tostring(next_event.time).." for "..tostring(next_event.spend).." (required rage: "..tostring(required_rage)..", time to rage: "..tostring(time_to_rage)..")")
            if time_to_rage > next_event.time then
                Hekili:Debug("Failed due to requiring "..tostring(next_event.spend).." for "..tostring(next_event.name).." at "..tostring(next_event.time).." but gaining it at "..tostring(time_to_rage))
                return false
            end
        end
    end

    return true
end)
spec:RegisterStateExpr( "should_hs", function()
    return should_queue( swingSpend(action.heroic_strike) )
end)
spec:RegisterStateExpr( "should_cleave", function()
    return should_queue( swingSpend(action.cleave) )
end)
spec:RegisterStateExpr( "ww_breakpoint", function()
    if not settings.adaptive_ww_enabled or not main_hand.speed or not main_hand.damage.avg then
        return settings.ww_min_enemies
    end

    local baseAP, posBuff, negBuff = UnitAttackPower("player")
    local ap = baseAP + posBuff + negBuff
    local avgWeaponDamage = main_hand.damage.avg
    local speed = main_hand.speed

    -- Bloodthirst DPR
    local bt_cost = action.bloodthirst.cost
    local bt_damage = 0.45 * ap
    local bt_dpr = bt_damage / bt_cost

    -- Whirlwind DPR (per target)
    local ww_cost = action.whirlwind.cost
    local ap_contribution = ap * (speed / 14)
    local ww_damage = avgWeaponDamage + ap_contribution
    local ww_dpr = ww_damage / ww_cost

    -- Break-even target count
    local requiredTargets = math.ceil(bt_dpr / ww_dpr)

    --print(string.format("AP: %d", ap))
    --print(string.format("Weapon Speed: %.2f | Avg Damage: %.1f", speed, avgWeaponDamage))
    --print(string.format("Bloodthirst DPR: %.2f", bt_dpr))
    --print(string.format("Whirlwind DPR (per target): %.2f", ww_dpr))
    --print(string.format("WW beats BT at ≥ %d targets", requiredTargets))
    return requiredTargets
end)

spec:RegisterHook( "reset_precast", function()
    local form = GetShapeshiftForm()
    if form == 1 then applyBuff( "battle_stance" )
    elseif form == 2 then applyBuff( "defensive_stance" )
    elseif form == 3 then applyBuff( "berserker_stance" )
    else removeBuff( "stance" ) end

    if IsCurrentSpell( class.abilities.heroic_strike.id ) then
        start_heroic_strike()
        Hekili:Debug( "Starting Heroic Strike, next swing in %.2f...", buff.heroic_strike.remains )
    end

    if IsCurrentSpell( class.abilities.cleave.id ) then
        start_cleave()
        Hekili:Debug( "Starting Cleave, next swing in %.2f...", buff.cleave.remains )
    end

    if now == query_time then
        if IsSpellKnown( class.abilities.overpower.id ) then
            if enemy_dodged > 0 and query_time - enemy_dodged < 6 and target.unit and target.unit == enemy_dodged_target and (last_overpower == 0 or enemy_dodged - last_overpower > 5) then
                applyBuff( "overpower_ready", enemy_dodged + 5 - now )
            elseif IsUsableSpell( class.abilities.overpower.id ) then
                applyBuff( "overpower_ready" )
            end
        end
        if IsUsableSpell( class.abilities.revenge.id ) then
            if enemy_revenge_trigger > 0 and now - enemy_revenge_trigger < 5 then
                applyBuff( "revenge_usable", enemy_revenge_trigger + 5 - now )
            else
                applyBuff( "revenge_usable" )
            end
        end
    end

    setCooldown("auto_attack", class.abilities.auto_attack.cooldown)
end )

-- Abilities
spec:RegisterAbilities( {

    auto_attack = {
        id = 6603,
        cast = 0,
        cooldown = 9,
        gcd = "off",

        startsCombat = true,
        texture = 135274,

        usable = function()
            return query_time - now >= 10
        end,

        handler = function()
        end
    },

    -- The warrior shouts, increasing attack power of all raid and party members within 30 yards by 550.  Lasts 2 min.
    battle_shout = {
        id = 6673,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = false,
        texture = 132333,

        usable = function()
        end,


        handler = function( rank )
            applyBuff( "battle_shout" )
            applyBuff( "my_battle_shout" )
            applyBuff( "shout" )
        end,

        copy = { 6673, 25289, 11551, 11550, 11549, 6192, 5242 }
    },


    -- A balanced combat stance that increases the armor penetration of all of your attacks by 10%.
    battle_stance = {
        id = 2457,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        spend = 0,
        spendType = "rage",

        startsCombat = false,
        texture = 132349,

        nobuff = "battle_stance",

        timeToReady = function () return max(cooldown.berserker_stance.remains, cooldown.battle_stance.remains, cooldown.defensive_stance.remains) end,

        handler = function()
            swap_stance( "battle_stance" )
        end
    },


    -- The warrior enters a berserker rage, removing and granting immunity to Fear, Sap and Incapacitate effects and generating extra rage when taking damage.  Lasts 10 sec.
    berserker_rage = {
        id = 18499,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        spend = 0,
        spendType = "rage",

        startsCombat = false,
        texture = 136009,

        buff = "berserker_stance",

        handler = function()
            applyBuff( "berserker_rage" )
            if talent.improved_berserker_rage.enabled then
                gain( 5 * talent.improved_berserker_rage.rank, "rage" )
            end
        end
    },


    -- An aggressive stance.  Critical hit chance is increased by 3% and all damage taken is increased by 5%.
    berserker_stance = {
        id = 2458,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        spend = 0,
        spendType = "rage",

        startsCombat = false,
        texture = 132275,

        nobuff = "berserker_stance",

        timeToReady = function () return max(cooldown.berserker_stance.remains, cooldown.battle_stance.remains, cooldown.defensive_stance.remains) end,

        handler = function()
            swap_stance( "berserker_stance" )
        end
    },


    -- Generates 20 rage at the cost of health, and then generates an additional 10 rage over 10 sec.
    bloodrage = {
        id = 2687,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        spend = 0.2,
        spendType = "health",

        startsCombat = true,
        texture = 132277,

        toggle = "cooldowns",

        handler = function()
            gain( 10 + (talent.improved_bloodrage.rank == 1 and 2 or talent.improved_bloodrage.rank == 2 and 5 or 0), "rage" )
            applyBuff( "bloodrage" )
        end
    },


    -- Instantly attack the target causing 1092 damage.  In addition, the next 3 successful melee attacks will restore 1% of max health.  This effect lasts 8 sec.  Damage is based on your attack power.
    bloodthirst = {
        id = 23881,
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 30,
        spendType = "rage",

        talent = "bloodthirst",
        startsCombat = true,
        texture = 136012,

        handler = function( rank )
            applyBuff( "bloodthirst", nil, 5 )
        end,

        copy = { 23881, 23894, 23892, 23893 }
    },


    -- Forces all enemies within 10 yards to focus attacks on you for 6 sec.
    challenging_shout = {
        id = 1161,
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        texture = 132091,

        toggle = "defensives",

        handler = function()
            applyDebuff( "target", "challenging_shout" )
        end
    },


    -- Charge an enemy, generate 15 rage, and stun it for 1.50 sec.  Cannot be used in combat.
    charge = {
        id = 11578,
        cast = 0,
        cooldown = 15,
        gcd = "off",

        spend = 0,
        spendType = "rage",

        startsCombat = true,
        texture = 132337,

        buff = "battle_stance",
        usable = function()
            return (not combat) and target.minR >= 8 and target.minR <= 25, "cannot be in combat; target must be outside your deadzone"
        end,

        handler = function( rank )
            setDistance( 7 )
            if not target.is_boss then applyDebuff( "target", "charge_stun" ) end
            gain( 15 + (3 * talent.improved_charge.rank), "rage")
        end,

        copy = { 100, 11578, 6178 }
    },

    -- On next attack...
    cleave = {
        id = 845,
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = 0,
        swingSpend = 20,
        spendType = "rage",

        startsCombat = true,
        texture = 132338,

        nobuff = "cleave",

        usable = function()
            return (not buff.heroic_strike.up) and (not buff.cleave.up) and (rage.current >= swingSpend(action.cleave))
        end,

        handler = function( rank )
            start_cleave()
        end,

        copy = { 845, 7369, 11608, 11609, 20569 }
    },


    -- Stuns the opponent for 5 sec and deals 830 damage (based on attack power).
    concussion_blow = {
        id = 12809,
        cast = 0,
        cooldown = 45,
        gcd = "spell",

        spend = 15,
        spendType = "rage",

        talent = "concussion_blow",
        startsCombat = true,
        texture = 132325,

        handler = function()
            applyDebuff( "target", "concussion_blow" )
        end
    },


    -- When activated you become enraged, increasing your physical damage by 20% but increasing all damage taken by 5%.  Lasts 30 sec.
    death_wish = {
        id = 12292,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        talent = "death_wish",
        startsCombat = true,
        texture = 136146,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "death_wish" )
            applyBuff( "enrage" )
        end,
    },


    -- A defensive combat stance.  Decreases damage taken by 10% and damage caused by 5%.  Increases threat generated.
    defensive_stance = {
        id = 71,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        spend = 0,
        spendType = "rage",

        startsCombat = false,
        texture = 132341,

        nobuff = "defensive_stance",

        timeToReady = function () return max(cooldown.berserker_stance.remains, cooldown.battle_stance.remains, cooldown.defensive_stance.remains) end,

        handler = function()
            swap_stance( "defensive_stance" )
        end
    },


    -- Reduces the melee attack power of all enemies within 10 yards by 411 for 30 sec.
    demoralizing_shout = {
        id = 1160,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        texture = 132366,

        handler = function( rank )
            applyDebuff( "target", "demoralizing_shout" )
            active_dot.demoralizing_shout = active_enemies
        end,

        copy = { 1160, 6190, 11554, 11555, 11556 }
    },


    -- Disarm the enemy's main hand and ranged weapons for 10 sec.
    disarm = {
        id = 676,
        cast = 0,
        cooldown = 10,
        gcd = "spell",

        spend = 20,
        spendType = "rage",

        startsCombat = true,
        texture = 132343,

        toggle = "cooldowns",

        buff = "defensive_stance",

        handler = function ()
            applyDebuff( "target", "disarm" )
        end,
    },


    -- Attempt to finish off a wounded foe, causing 1892 damage and converting each extra point of rage into 38 additional damage (up to a maximum cost of 30 rage).  Only usable on enemies that have less than 20% health.
    execute = {
        id = 5308,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return ( talent.improved_execute.rank == 2 and 10 or talent.improved_execute.rank == 1 and 13 or 15 )
        end,
        spendType = "rage",

        startsCombat = true,
        texture = 135358,

        usable = function() return target.health.pct < 20, "requires target health under 20 percent" end,

        handler = function( rank )
            spend( rage.current, "rage" )
        end,

        copy = { 5308, 20658, 20660, 20661, 20662 }
    },


    -- Maims the enemy, reducing movement speed by 50% for 15 sec.
    hamstring = {
        id = 1715,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        texture = 132316,

        nobuff = "defensive_stance",

        handler = function( rank )
            applyDebuff( "target", "hamstring" )
        end,

        copy = { 1715, 7372, 7373 }
    },


    -- On next attack...
    heroic_strike = {
        id = 78,
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = 0,
        swingSpend = function()
            return 15 - talent.improved_heroic_strike.rank
        end,
        spendType = "rage",

        startsCombat = true,
        texture = 132282,

        nobuff = "heroic_strike",

        usable = function()
            return (not buff.heroic_strike.up) and (not buff.cleave.up) and (rage.current >= swingSpend(action.heroic_strike))
        end,

        handler = function( rank )
            start_heroic_strike()
        end,

        copy = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }
    },


    -- Charge an enemy, causing 262 damage (based on attack power) and stunning it for 3 sec.
    intercept = {
        id = 20252,
        cast = 0,
        cooldown = function() return 30 - 5 * talent.improved_intercept.rank end,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        texture = 132307,

        buff = "berserker_stance",

        handler = function( rank )
            setDistance( 7 )
            applyDebuff( "target", "intercept_stun" )
        end,

        copy = { 20252, 20616, 20617 }
    },


    -- The warrior shouts, causing up to 5 enemies within 8 yards to cower in fear.  The targeted enemy will be unable to move while cowering.  Lasts 8 sec.
    intimidating_shout = {
        id = 5246,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 25,
        spendType = "rage",

        startsCombat = true,
        texture = 132154,

        toggle = "cooldowns",

        handler = function()
            applyDebuff( "target", "intimidating_shout" )
        end
    },


    -- When activated, this ability temporarily grants you 30% of your maximum health for 20 sec.  After the effect expires, the health is lost.
    last_stand = {
        id = 12975,
        cast = 0,
        cooldown = 600,
        gcd = "off",

        talent = "last_stand",
        startsCombat = false,
        texture = 135871,

        toggle = "defensives",

        handler = function()
            applyBuff( "last_stand" )
            health.max = health.max * 1.3
            gain( health.current * 0.3, "health" )
        end
    },


    -- A mocking attack that causes a moderate amount of threat and forces the target to focus attacks on you for 6 sec.  If the target is tauntable, also deals weapon damage.
    mocking_blow = {
        id = 694,
        cast = 0,
        cooldown = 120,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        texture = 132350,

        toggle = "cooldowns",

        buff = "battle_stance",

        handler = function( rank )
            applyDebuff( "target", "mocking_blow" )
        end,

        copy = { 694, 7400, 7402, 20559, 20560 }
    },


    -- A vicious strike that deals weapon damage plus 85 and wounds the target, reducing the effectiveness of any healing by 50% for 10 sec.
    mortal_strike = {
        id = 12294,
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 30,
        spendType = "rage",

        talent = "mortal_strike",
        startsCombat = true,
        texture = 132355,

        handler = function( rank )
            applyDebuff( "target", "mortal_strike" )
        end,

        copy = { 12294, 21551, 21552, 21553 }
    },


    -- Instantly overpower the enemy, causing weapon damage.  Only useable after the target dodges.  The Overpower cannot be blocked, dodged or parried.
    overpower = {
        id = 7384,
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        texture = 132223,

        buff = "battle_stance",

        usable = function()
            return buff.overpower_ready.up, "only usable after dodging"
        end,

        handler = function( rank )
            removeBuff( "overpower_ready" )
        end,

        copy = { 7384, 7887, 11584, 11585 }
    },


    -- Causes all enemies within 10 yards to be Dazed, reducing movement speed by 50% for 6 sec.
    piercing_howl = {
        id = 12323,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        talent = "piercing_howl",
        startsCombat = true,
        texture = 136147,

        handler = function()
            applyDebuff( "target", "piercing_howl" )
        end
    },


    -- Pummel the target, interrupting spellcasting and preventing any spell in that school from being cast for 4 sec.
    pummel = {
        id = 6552,
        cast = 0,
        cooldown = 10,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        texture = 132938,

        buff = "berserker_stance",
        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function( rank )
            interrupt()
        end,

        copy = { 6552, 6554 }
    },


    -- Your next 3 special ability attacks have an additional 100% to critically hit but all damage taken is increased by 20%.  Lasts 12 sec.
    recklessness = {
        id = 1719,
        cast = 0,
        cooldown = 1800,
        gcd = "spell",

        spend = 0,
        spendType = "rage",

        startsCombat = false,
        texture = 132109,

        toggle = "cooldowns",

        buff = "berserker_stance",

        handler = function ()
            applyBuff( "recklessness" )
        end,
    },


    -- Wounds the target causing them to bleed for 380 damage plus an additional 780 (based on weapon damage) over 15 sec.  If used while your target is above 75% health, Rend does 35% more damage.
    rend = {
        id = 772,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        texture = 132155,

        nobuff = "berserker_stance",

        handler = function( rank )
            applyDebuff( "target", "rend" )
        end,

        copy = { 772, 6546, 6547, 6548, 11572, 11573, 11574 }
    },


    -- Instantly counterattack any enemy that strikes you in melee for 12 sec.  Melee attacks made from behind cannot be counterattacked.  A maximum of 20 attacks will cause retaliation.
    retaliation = {
        id = 20230,
        cast = 0,
        cooldown = 1800,
        gcd = "spell",

        spend = 0,
        spendType = "rage",

        startsCombat = false,
        texture = 132336,

        toggle = "cooldowns",

        buff = "battle_stance",

        handler = function()
            applyBuff( "retaliation" )
        end
    },


    -- Instantly counterattack an enemy for 2313 to 2675 damage.   Revenge is only usable after the warrior blocks, dodges or parries an attack.
    revenge = {
        id = 6572,
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        texture = 132353,

        buff = function()
            if buff.revenge_usable.up then return "defensive_stance" end
            return "revenge_usable"
        end,

        handler = function( rank )
            removeBuff( "revenge_usable" )
        end,

        copy = { 6572, 6574, 7379, 11600, 11601, 25288 }
    },

    -- Bash the target with your shield dazing them and interrupting spellcasting, which prevents any spell in that school from being cast for 6 sec.
    shield_bash = {
        id = 72,
        cast = 0,
        cooldown = 12,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        texture = 132357,

        toggle = "interrupts",

        buff = function() return buff.battle_stance.up and "battle_stance" or "defensive_stance" end,
        equipped = "shield",
        readyTime = state.timeToInterrupt,
        debuff = "casting",

        handler = function( rank )
            interrupt()
            if talent.improved_shield_bash.rank == 2 then
                applyDebuff( "target", "improved_shield_bash" )
            end
        end,

        copy = { 72, 1671, 1672 }
    },


    -- Increases your chance to block and block value by 100% for 10 sec.
    shield_block = {
        id = 2565,
        cast = 0,
        cooldown = 5,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        equipped = "shield",
        startsCombat = false,
        texture = 132110,

        buff = "defensive_stance",

        handler = function()
            applyBuff( "shield_block" )
        end
    },


    -- Slam the target with your shield, causing 990 to 1040 damage, modified by your shield block value, and dispels 1 magic effect on the target.  Also causes a high amount of threat.
    shield_slam = {
        id = 23922,
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 20,
        spendType = "rage",

        startsCombat = true,
        texture = 134951,

        equipped = "shield",

        handler = function( rank )
        end,

        copy = { 23922, 23923, 23924, 23925 }
    },


    -- Reduces all damage taken by 60% for 12 sec.
    shield_wall = {
        id = 871,
        cast = 0,
        cooldown = 1800,
        gcd = "off",

        spend = 0,
        spendType = "rage",

        equipped = "shield",
        startsCombat = false,
        texture = 132362,

        toggle = "defensives",

        buff = "defensive_stance",

        handler = function()
            applyBuff( "shield_wall" )
        end
    },

    -- Slams the opponent, causing weapon damage plus 250.
    slam = {
        id = 1464,
        cast = function()
            return 1.5 - 0.1 * talent.improved_slam.rank
        end,
        cooldown = 0,
        gcd = "spell",

        spend = 15,
        spendType = "rage",

        startsCombat = true,
        texture = 132340,

        handler = function ()
        end,

        copy = { 1464, 8820, 11604, 11605 }
    },


    -- Sunders the target's armor, reducing it by 4% per Sunder Armor and causes a high amount of threat.  Threat increased by attack power.  Can be applied up to 5 times.  Lasts 30 sec.
    sunder_armor = {
        id = 7386,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function() return 15 - talent.improved_sunder_armor.rank end,
        spendType = "rage",

        startsCombat = true,
        texture = 132363,

        handler = function( rank )
            applyDebuff( "target", "sunder_armor", nil, min( 5, debuff.sunder_armor.stack + 1 ) )
        end,

        copy = { 7386, 7405, 8380, 11596, 11597 }
    },


    -- Your next 5 melee attacks strike an additional nearby opponent.
    sweeping_strikes = {
        id = 12328,
        cast = 0,
        cooldown = 30,
        gcd = "off",

        spend = 30,
        spendType = "rage",

        talent = "sweeping_strikes",
        startsCombat = false,
        texture = 132306,

        buff = "battle_stance",

        handler = function()
            applyBuff( "sweeping_strikes", nil, 5 )
        end
    },


    -- Taunts the target to attack you, but has no effect if the target is already attacking you.
    taunt = {
        id = 355,
        cast = 0,
        cooldown = function() return 10 - talent.improved_taunt.rank end,
        gcd = "off",

        startsCombat = true,
        texture = 136080,

        buff = "defensive_stance",

        handler = function()
            applyDebuff( "target", "taunt" )
        end
    },


    -- Blasts nearby enemies increasing the time between their attacks by 10% for 30 sec and doing 300 damage to them.  Damage increased by attack power.  This ability causes additional threat.
    thunder_clap = {
        id = 6343,
        cast = 0,
        cooldown = 4,
        gcd = "spell",

        spend = function() return 20 - ( talent.improved_thunder_clap.rank == 3 and 4 or talent.improved_thunder_clap.rank == 2 and 2 or talent.improved_thunder_clap.rank == 1 and 1 or 0 ) end,
        spendType = "rage",

        startsCombat = true,
        texture = 136105,

        buff = "battle_stance",

        handler = function( rank )
            applyDebuff( "target", "thunder_clap" )
            active_dot.thunder_clap = min( active_enemies, 4 + active_dot.thunder_clap )
        end,

        copy = { 6343, 8198, 8204, 8205, 11580, 11581 }
    },


    -- In a whirlwind of steel you attack up to 4 enemies within 8 yards, causing weapon damage from both melee weapons to each enemy.
    whirlwind = {
        id = 1680,
        cast = 0,
        cooldown = 10,
        gcd = "spell",

        spend = 25,
        spendType = "rage",

        startsCombat = true,
        texture = 132369,

        buff = "berserker_stance",

        handler = function()
        end
    },
} )

spec:RegisterSetting("warrior_description", nil, {
    type = "description",
    name = "Adjust the settings below according to your playstyle preference. It is always recommended that you use a simulator "..
        "to determine the optimal values for these settings for your specific character."
})

spec:RegisterSetting("warrior_description_footer", nil, {
    type = "description",
    name = "\n\n"
})

spec:RegisterSetting("general_header", nil, {
    type = "header",
    name = "General"
})

spec:RegisterSetting("queueing_threshold", 40, {
    type = "range",
    name = "Queue Rage Threshold",
    desc = "Select the rage threshold after which heroic strike / cleave will be recommended",
    width = "full",
    min = 0,
    softMax = 100,
    step = 1
})

spec:RegisterSetting("execute_queueing_enabled", true, {
    type = "toggle",
    name = "Queue During Execute",
    desc = "When enabled, recommendations will alwas queue heroic strike or cleave during the execute phase",
    width = "full"
})

spec:RegisterSetting("adaptive_queueing_enabled", true, {
    type = "toggle",
    name = "Use Queue Prediction",
    desc = "When enabled, recommendations will use swing timers and rage calculations to determine if heroic strike or cleave should be queued",
    width = "full"
})

spec:RegisterSetting("ww_min_enemies", 2, {
    type = "range",
    name = "Minimum Enemies For Whirlwind",
    desc = "Select the minimum number of enemies before recommending Whirlwind over Bloodthirst",
    width = "full",
    min = 0,
    softMax = 4,
    step = 1
})
spec:RegisterSetting("adaptive_ww_enabled", false, {
    type = "toggle",
    name = "Use Whirlwind DPR Calculation",
    desc = "When enabled, recommendations will use Whirlwind over Bloodthirst based on real-time DPR calculations",
    width = "full"
})

spec:RegisterSetting("ww_cd_diff", 1.5, {
    type = "range",
    name = "Whirlwind Cooldown Differential",
    desc = "Select the remaining time on Bloodthirst before Whirlwind can be recommended",
    width = "full",
    min = 0,
    softMax = 2,
    step = 0.1
})

spec:RegisterSetting("overpower_enabled", true, {
    type = "toggle",
    name = "Use Overpower",
    desc = "When enabled, recommendations will include Overpower",
    width = "full"
})

spec:RegisterSetting("overpower_threshold", 45, {
    type = "range",
    name = "Maximum Rage for Overpower",
    desc = "Select the maximum rage allowed for Overpower recommendations",
    width = "full",
    min = 1,
    max = 100,
    step = 1
})

spec:RegisterSetting("hamstring_threshold", 80, {
    type = "range",
    name = "Hamstring Rage Threshold",
    desc = "Select the rage threshold after which Hamstring will be recommended",
    width = "full",
    min = 0,
    softMax = 100,
    step = 1
})

spec:RegisterSetting("hamstring_cd_diff", 1.5, {
    type = "range",
    name = "Hamstring Cooldown Differential",
    desc = "Select the remaining time on Bloodthirst and Whirlwind before Hamstring can be recommended",
    width = "full",
    min = 0,
    softMax = 2,
    step = 0.1
})

spec:RegisterSetting("general_footer", nil, {
    type = "description",
    name = "\n\n\n"
})

spec:RegisterSetting("debuffs_header", nil, {
    type = "header",
    name = "Debuffs"
})

spec:RegisterSetting("debuffs_description", nil, {
    type = "description",
    name = "Debuffs settings will change which debuffs are recommended"
})

spec:RegisterSetting("debuff_sunder_enabled", true, {
    type = "toggle",
    name = "Maintain Sunder Armor",
    desc = "When enabled, recommendations will include sunder armor",
    width = "full"
})

spec:RegisterSetting("debuff_sunder_max_stack", 1, {
    type = "range",
    name = "Max Sunders",
    desc = "Select the maximum number of sunder armor stacks for sunder recommendations",
    width = "full",
    min = 1,
    max = 5,
    step = 1
})

spec:RegisterSetting("debuff_sunder_min_level", 61, {
    type = "range",
    name = "Minimum Sunder Level",
    desc = "Select the minimum target level before recommending Sunder Armor",
    width = "full",
    min = 0,
    max = 63,
    step = 1
})

spec:RegisterSetting("debuff_demoshout_enabled", false, {
    type = "toggle",
    name = "Maintain Demoralizing Shout",
    desc = "When enabled, recommendations will include demoralizing shout",
    width = "full"
})

spec:RegisterSetting("debuffs_footer", nil, {
    type = "description",
    name = "\n\n\n"
})


spec:RegisterOptions( {
    enabled = true,

    aoe = 2,

    gcd = 6673,

    nameplates = true,
    nameplateRange = 8,

    damage = false,
    damageExpiration = 6,

    potion = "",

    package = "Fury",
    usePackSelector = true
} )


spec:RegisterPack( "Arms", 20250324.1, [[Hekili:TJvZUnUnq4NLCXibjv12joB3wBd0EQBoKEWPOhkwjXirBrekrvsQ44cd(S3Hu)rzrT2jiBVSlqqSm5mFZmFC0mJP)e)h8xfJKy)7NoE6SXxp9gVjZMDZ0p4VsUlh7Vkhf9eAd8qgkf()VYtf6f3rzOyTYcwbpc2WF1JfeQ8tz(p6aXXZMndKnhh5F)e)vjK4yCPKyrujQQW)cX5egxfMR)Gi3PcxR)6VJFIqjGv5S1ekyluKKWYexU4hffzXyEaINY4xrwVqGLss2gHxm(XI1RdQ2hNHEKIJhvUQNTwEcjeHZhqXu0lbgbgDwLU4xYzcCLUf5JKi(gS0JIFgtxoK9tjzbgju3167XyaceL8VGcbIewH0veOLYSztqu7j91h8hBdeHO0GYVgqjc5v6JWfrmgnMTntOTwxV)2RTvNxK1xB8l4Ocj2s3emIkt8YJKZxmD8rbGZKi9sQ7Ae1RcuqLemNrIakNtEcFvbq0mGd2efVyI2KAfEgdmboLGflMm68ZpRHWqXOCZ2)tbUaRjLAgRoK9actIOvW7XXPisMy5coKG7jjP4ajl4MP73FcyQjCACqI4I97p3jvmQbLQ4RhixCHloiIIrpF0GF5xLGF24xtWx6PV7eq1t2zi1znFtNIyrcFJMJyXaSNX8C2wm35UBtiC6wswSdsPTe72TMkZvBaU47bxzJEuCqmz96tIV6YXZM)LTZLomJBIQJ6UFJcLQ3nBJMSo5WRrRAZ3YmnS)jPMjWJk4CCMCz72YeogYHOXo95hPmwSwtTpBJW8po2TciPKIB7ZEMvVYoYH5cm)jOPn03plYX7ydQzLfgwT2K9MS3MJFtl92L5yu8o98fDyNfLMTvoViMq2rM5oSrdv6Vcwtaiygo7MjtMoXdghBlINPvXF1djeHE(lZGwQq9xsjcbSPkuuKNd5evdLTbERHtIuH6tRNWsHNkuf(jzPsCCelnfdd)edsKGGLHrm47SNTJKfrlG5)GTisOQ(pdf8d)bv4F)NcSgjCQ4ZxPcHKPOeBPrz7ATQkmJPb)LCkjIiPT4gRFsBCCRr)fvi47vM5HsiuHt(Sg0y7LMAz5Tek1kIQGuwlQHnmlLvKczpAdlOmPN6UpLQjm9cxdwWC0Pc1JcbK1D(RmpPNHUojcE(EZe5wjpM5LRss8)n)vrqCaepQCk42YAQWfqKOchPcp383zGBC0Qog5)YVYRcxciFq)pv4(9Nm(n9bvHxuQi4E96gOcNd2bMG0OYX6kyG6I6Fka8lkSNkWxc53VzEC5)B84SXVfESSJ6xrUS0aAs8AnjwVCt9eBEee6gTqNgZUWYB628TjwEFPBhDjFvu(bnLbE9429YbmRfd30GuZFZSj5oyEarF7Ge9XCPourVoWDzZEnVpj1TBbzEfYrJCR3wR3uhwFyWWQlOa1)XXTy0mbGgJFAqmG8PIClTSgdqR4hp5Yehc0bZjObBY4xhADF9S3mbMThyUaxK(I6MmhmFGdzN70UooP6muJVMYwvvg57nREZfy)EZQ3pUCGMv1jPDQGk1334Aubv2K86KKBCcN3IOXph8Me7(U1a3MObIZAq5G7u0SR9nZDqf4bUBX2G32RAsVoPiT3TnEGN68ohBnC)TBoySmFZr3b3pPTJ1p8V96YjMdkVi6MRX01ii1w4GBG0Hb6Ng2Xk1Pr1TPpfByPEZG9MCVCZVHaQO2l77r7AdioW(cbUUGlOjQqMahLR(Jc(UcZs()3p]] )

spec:RegisterPack( "Fury", 20250324.1, [[Hekili:TJ1sVnUnq4Fl(IrcAQQTtC2nT2(qpu0KdPhCk6HIvsmsJIimLOkjvCCrG(TVd1tkzjBNTz7LDbwSrMCEXV5f5yp1(b71(efyF)SjZMp5Yzxzn9MPF8Qz2Rv7sa71jeVnKNWpIjr4))BPID6f3X4eFnZsEQWd3WE9JPuM62y7h7rItUz(hqAtap77NAVoK67dfucsVcPM5(xeHGYfzUj6)qv4sb6F(7WgkJAVMrLkPwNcUIOO8y877Zpbqm5rg4B)R2R9qgbbLyVM4POpdoqmerbzM7Ym3PzUJZCpl)FJYCLGsrJFsAr8jj5e)pPqkGl5ukXC694CMpFBS1Jmo3xfsfsLLaIi0yuSRq5kqeYsrJahf35QzzUV(6jlDzipL57eII68cgrJtrepbkRqGWuHwjEQm3fOEMnPGLkjdVaEPQ(emkQZlGaeMwhcco1ZrQe0nOVkvco8GaNN881aOcDvNmkU6)juC(KVeu0JbKNHVIizHc6dcVudHvKXFgej8TGWevrIU60X5Lgw32Tor04QnBuZwefzBPX(Azp30ama5oMW1dAcVN(stt3Z3XNge8M8NTJfMJoTJP1VuZAa08ddctVbTesI05C4zRgdmnZAf(MyphA8sfciwLNp2qMkuayMaZ3i1VAt9H6JdEOAlueSVzsNGjnfAzCZHIFstm4IOumWrNzQ0moDYjZjiKGydiWkwKyVEt3MoCH)CP1o9UoFSvq2JPbbgBjaI)oRsw7GYOBPW6AO3YJlv9q7IE1BTRjNJrLkpGHCvRZrdec3Z2nHo9b5dHA6Abff6(ERZtSG)3BD(EHKNyRZQa0wDTu6BkgqszQdh4wBu(Go)YrMg73jPVyhRYDiIiUWcty820oZTTaIiV4usurIyPuGxs44XPqkLPPLWgdEgyDkO3rOyl9CQAo8Mw1HdU6ktFiINxQT1HTXs17lim6)Q9q5e2QYX(Bx7y6v97FiV(sdxnHXCk(HJ(w7f3D3P4jevrZYdFHObJ(AuJinEqTufgvDXidDCkSx)eJ8yVeb4XJWQROKYxalRl17A8gh8(derS2LyV(HqQu)mgEaLHPu6FerLsCtmyinjHluLVT5jS6GG6Hrnyp6nGsAL5M5ERQGPC1gbymb6ovHeCzeW1VvQ5js0ypwQVU(cqvy1QFo7Um3FmZ9V)tjOLeej)0fzUyddVqtQjX7A0AMBmxl8xsyupQI1ixF9xALdnk9xYCrBVunpuicS22N0c13CPzgAElLXmorLIuvrAoAKVuCAeEbaTILmUYk7UBJ0aMEHlR6cN5M)yqCtTZjhMR8RYFy5pzMgDbny5HllmEWsclow5GXJ6VqWyZ8JvdP)6caz31y77Nj23jyV09AlP3eDtf0n58cDe)Y6SsT2AB9xFPj7DYAk4UmBZG3M82flXoghtav5ByuvfPvnwqwA1e(cJgilNQvz7gTlNo(SZgD8MFJpuB1vl7CXKxF9eKy9fso)1xpRxGy8rBBE(59Hafnpp2rF1xHJ(8jVLJEHD(UF8l)Ym6OkI5B4Wddi4BY4dJZF9dT6D36xl1dKS0CMagtzPxbzahhxr)3bAttRCeaNey3z6jloKwE7Mq)5GvZzqFYprrU38ngp8OroiBMpaFvpJdzyFPMtTfBkHf3mPFgmgOrU)1OVAl66m(I9ZkhKtZ3V3lBnji7nsJXdmoJ2OZYc12zmgTOzrp6OgkhpQ9GlgpAGrwySrNHvKQcXx3S(psf7sZVoT9N)d]] )

spec:RegisterPack( "Protection", 20241121.1, [[Hekili:1fzqVnkmqu4Fl5svR2k2cH2Q9qVuTxsoKwjx1EBkg7HGvbBl7Hnk7b)BVgilHnkrrkAa)EFE49Gu4nGj5ecBYUllpnnlnjnB59zpamAVfbMLl(IVnoO5TX)F1ziuqkJU)O9ngUShH305eXJbwzNQHwPHYZXnp)xrTwuaBsbwTskXrLOx0B26mvQMih(Wv4tSouyAl50pE6NLngJ0f3LBvvpTOSRQkjEa1GF6RnDusNnS(S(MjAW6LekQ5Ur6u)aLen4vs8XRo88ofvR0z3hwpbiARZJFQiS1p)LwZyg9h057h6JHLXyihy74oTsV1dSvTwJJqzOilum6nu0O8KpjSogcDuTXbSFJv)LlQJzl3JYx0ZBHqXhCNtzCHIRx9(naBW(qRIv8UgkoUzOL5hATP1fyOMx2Gs4zGIl4Cr)B9NRG67NdP1e1JcycxeRtXb2IqX5QNJ4NQYPl(sC(pxZW1BC5fnEs)fkUkuCshEe7yTp8bo(d((p]] )



spec:RegisterPackSelector( "arms", "Arms", "|T132292:0|t Arms",
    "If you have spent more points in |T132292:0|t Arms than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab1 > max( tab2, tab3 )
    end )

spec:RegisterPackSelector( "fury", "Fury", "|T132347:0|t Fury",
    "If you have spent more points in |T132347:0|t Fury than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab2 > max( tab1, tab3 )
    end )

spec:RegisterPackSelector( "protection", "Protection", "|T134952:0|t Protection",
    "If you have spent more points in |T134952:0|t Protection than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab3 > max( tab1, tab2 )
    end )
