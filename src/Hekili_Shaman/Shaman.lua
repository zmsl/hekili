-- Hekili_Shaman/Shaman.lua
-- The Forever Shaman (Elemental and Enhancement, Restoration idle, one spec a talent tree: Hekili:NewClass): the
-- Shaman kit with Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build
-- 1.60.1.70338, wowdb), the totems on the sim side (C6: `RegisterTotems` with each one's element and duration; the
-- summon's `now` writes the slot's modelled expiry, which Families/Totems.lua answers in combat), Lightning Shield's
-- charges spent by hits on us (`consumedBy`), Maelstrom Weapon's stacks on Lightning Bolt, Clearcasting as a charged
-- cost modifier, the shocks' shared cooldown, Reverberation, Improved Fire Nova and Shamanistic Focus, the weapon
-- imbues (C4's main_hand_enchant), Rage of the Farseer (a talent under the Cooldowns toggle: its 25 s buff), mana
-- under the five-second rule (`fsr`), and the default priority, Enhancement (wowsims.com), translated from
-- wowsims/forever's APL (tools/wowsims/specs/shaman_enhancement.lua). Research: the class-completion research §4.
-- Unmodelled: Stormstrike's debuff (no priority reads it), the totems' effects, Flametongue and Windfury Weapon's
-- procs, Windfury Totem (the party's: never prompted), Improved Lightning Shield's extra charges, Rage of the Farseer's
-- +30% attack speed (nothing reads swing timing for mana).
-- The Elemental kit (class-completion Task 17; its priority Elemental (wowsims.com)): what wowsims/forever's
-- Elemental list casts (ui/specs/shaman/elemental/builds/testing.build.json): Chain Lightning (its 6 s cooldown lifted
-- by Elemental Mastery), Lava Burst, Elemental Mastery, Magma, Windfury and Mana Tide Totems (Windfury Totem only for a
-- pack that casts it, as that list's pre-pull does), Water Shield (one shield at a time), Convection's and Elemental
-- Alacrity's cuts, Clearcasting on Chain Lightning and Lava Burst, Revelation's charge.
-- Also unmodelled: Mana Tide's mana, Water Shield's mana, Revelation's proc (the weapon enchant's; the player aura read
-- answers it), Lightning Overload, Mindfulness (mana regen while casting: the `fsr` meta has no casting share; the
-- out-of-combat regen read's casting rate carries it).
-- From wowsims/forever's spell data, absent from the Forever DB2 at 70338 (in-game checks): Call of Flame's +3 s a
-- rank on Flame Shock, Stormstrike's cost, Lava Burst's and Mana Tide Totem's rank 4 (1326047, 1325256), Elemental
-- Mastery, Revelation, Elemental Alacrity's Forever ranks. Fire Nova's (375 there) is not modelled (FIRE_NOVA_COST
-- says why).
-- Credits: Hekili (registration API, pack format and `summonTotem`'s signature, State.lua). wowsims/forever (MIT,
-- ui/specs/shaman/enhancement/apls/default.apl.json and sim/shaman/) is the reference for the priorities and the totem,
-- Fire Nova, Maelstrom Weapon and Clearcasting rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase = Facade.UnitClassBase
local L = Hekili.L

if UnitClassBase("player") ~= "SHAMAN" then
    return
end

local state = Hekili.State
local max = math.max

-- The class kit and one spec a talent tree (ids the core's: Elemental 100071, Enhancement 100072, Restoration 100073,
-- unsupported; the client's one pseudo-spec, 1489, only keys the legacy profile the core migrates). Icons: the DB2
-- talent tabs'.
local spec = Hekili:NewClass("SHAMAN", {
    specs = {
        {
            key = "elemental",
            name = L["Elemental"],
            tree = 1,
            icon = 136048,
            role = "attack",
            ranged = true,
            package = "Elemental (wowsims.com)",
        },
        {
            key = "enhancement",
            name = L["Enhancement"],
            tree = 2,
            icon = 136051,
            role = "attack",
            package = "Enhancement (wowsims.com)",
        },
        { key = "restoration", name = L["Restoration"], tree = 3, icon = 136052, role = "healer", unsupported = true },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's), and each rank's mana cost.
local LIGHTNING_BOLT = { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 }
local LIGHTNING_BOLT_COST = { 15, 30, 45, 60, 85, 110, 135, 160, 190, 220 }
local LIGHTNING_BOLT_CAST = { 1.5, 2, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5 }
local LIGHTNING_SHIELD = { 324, 325, 905, 945, 8134, 10431, 10432 }
local LIGHTNING_SHIELD_COST = { 45, 80, 125, 180, 240, 305, 370 }
local EARTH_SHOCK = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }
local EARTH_SHOCK_COST = { 30, 50, 85, 145, 240, 345, 450 }
local FLAME_SHOCK = { 8050, 8052, 8053, 10447, 10448, 29228 }
local FLAME_SHOCK_COST = { 55, 95, 160, 250, 345, 410 }
local FIRE_NOVA = { 408341, 408342, 408343, 408344, 408345 } -- Forever's spell (no totem): from the fire totem up
-- The DB2's. wowsims/forever's spell data says 65, 120, 210, 290, 375 (its log: 375): not modelled, because the
-- secret-mana belief pins itself at the dearest usable cost after an unseen refill, and at 375 that pin (Earth Shock's
-- 450) sits under the 10% Fire Nova filler (500 of the solo world's 5000 mana; 553 of 5530 in wowsims's fight), so the
-- solo gate falls to 0.89 (GAP V). IN-GAME CHECK: Fire Nova's cost.
local FIRE_NOVA_COST = { 95, 170, 280, 395, 520 }
local ROCKBITER_WEAPON = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 }
local ROCKBITER_WEAPON_COST = { 15, 25, 50, 75, 100, 125, 150 }
local FLAMETONGUE_WEAPON = { 8024, 8027, 8030, 16339, 16341, 16342 }
local FLAMETONGUE_WEAPON_COST = { 30, 55, 80, 105, 130, 155 }
local WINDFURY_WEAPON = { 8232, 8235, 10486, 16362 }
local WINDFURY_WEAPON_COST = { 90, 115, 140, 165 }
local FROSTBRAND_WEAPON = { 8033, 8038, 10456, 16355, 16356 }
local FROSTBRAND_WEAPON_COST = { 60, 85, 110, 135, 160 }
local CHAIN_LIGHTNING = { 421, 930, 2860, 10605 }
local CHAIN_LIGHTNING_COST = { 225, 305, 390, 485 }
-- Rank 4 (1326047) is Forever's, absent from the DB2 at 70338: wowsims/forever's spell data (265 mana, 2.5 s, 10 s).
local LAVA_BURST = { 408490, 1238299, 1238300, 1326047 }
local LAVA_BURST_COST = { 165, 230, 265, 265 }
-- Elemental Alacrity (16578, aura 107 misc 10 on Lightning Bolt, Chain Lightning and Lava Burst) by rank: Forever's
-- trait curve, -170/-330/-500 ms (wowsims/forever's spell data; the DB2's Talent rows say -200 ms a rank of 5).
-- IN-GAME CHECK: Lightning Bolt's cast at 3/3: 2.0 s?
local ALACRITY = { 0.17, 0.33, 0.5 }

-- The totems this file summons: element (the slot Hekili's `totem.<element>` reads), ranks, costs, and each rank's
-- duration in seconds (DB2), and a cooldown where it has one.
local TOTEMS = {
    searing_totem = {
        element = "fire",
        ids = { 3599, 6363, 6364, 6365, 10437, 10438 },
        cost = { 25, 45, 75, 110, 145, 170 },
        duration = { 30, 35, 40, 45, 50, 55 },
    },
    flametongue_totem = {
        element = "fire",
        ids = { 8227, 8249, 10526, 16387 },
        cost = { 90, 140, 200, 275 },
        duration = { 300, 300, 300, 300 },
    },
    strength_of_earth_totem = {
        element = "earth",
        ids = { 8075, 8160, 8161, 10442, 25361 },
        cost = { 25, 65, 125, 225, 275 },
        duration = { 300, 300, 300, 300, 300 },
    },
    grace_of_air_totem = {
        element = "air",
        ids = { 8835, 10627, 25359 },
        cost = { 155, 250, 310 },
        duration = { 300, 300, 300 },
    },
    mana_spring_totem = {
        element = "water",
        ids = { 5675, 10495, 10496, 10497 },
        cost = { 40, 60, 80, 100 },
        duration = { 300, 300, 300, 300 },
    },
    magma_totem = {
        element = "fire",
        ids = { 8190, 10585, 10586, 10587 },
        cost = { 230, 360, 500, 650 },
        duration = { 20, 20, 20, 20 },
    },
    -- the party's melee: prompted only by a pack that casts it (wowsims's Elemental pre-pull)
    windfury_totem = {
        element = "air",
        ids = { 8512, 10613, 10614 },
        cost = { 115, 175, 250 },
        duration = { 300, 300, 300 },
    },
    -- 5 minutes (category 591); rank 4 (1325256) is Forever's: wowsims/forever's spell data (60 mana, 13 s, 300 s).
    mana_tide_totem = {
        element = "water",
        ids = { 16190, 17354, 17359, 1325256 },
        cost = { 10, 30, 60, 60 },
        duration = { 13, 13, 13, 13 },
        cooldown = 300,
    },
}

local function rest(ids)
    local out = {}
    for i = 2, #ids do
        out[#out + 1] = ids[i]
    end
    return out
end

-- The highest known rank of a rank list, from the belief's spellbook: the same answer in the sim's `state`
-- environment and in a `now` handler's (event-facade spec §12a).
local knownRank = state.knownRank

local function knows(ids)
    return function()
        return knownRank(ids) > 0
    end
end

local function byRank(values, ids)
    return values[knownRank(ids)] or values[1]
end

local function cost(costs, ids)
    return function()
        return byRank(costs, ids)
    end
end

-- A totem: its summon (the `now` and the `handler`, two closures so each gets its own environment) fills its element's
-- slot for the known rank's duration, with Hekili's summonTotem(name, element, duration).
local function summon(key)
    local t = TOTEMS[key]
    return function()
        summonTotem(key, t.element, byRank(t.duration, t.ids))
    end
end

local function totemAbility(key)
    local t = TOTEMS[key]
    return {
        id = t.ids[1],
        copy = rest(t.ids),
        cast = 0,
        cooldown = t.cooldown or 0,
        gcd = "totem",

        spend = cost(t.cost, t.ids),
        spendType = "mana",

        startsCombat = false,
        known = knows(t.ids),

        now = summon(key),
        handler = summon(key),
    }
end

-- A weapon imbue on the main hand: 60 minutes (DB2 tooltip), the shared main_hand_enchant pseudo-aura (C4), read out of
-- combat.
local function imbue(ids, costs)
    return {
        id = ids[1],
        copy = rest(ids),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(costs, ids),
        spendType = "mana",

        startsCombat = false,
        known = knows(ids),

        now = function()
            applyBuff("main_hand_enchant", 3600)
        end,
        handler = function()
            applyBuff("main_hand_enchant", 3600)
        end,
    }
end

-- The shocks' shared 6 s cooldown (DB2 category 19), Reverberation (16040, aura 107 misc 11: rank 1's -200 ms x the
-- rank) taking 1 s off at 5/5: each sets the other's; Flame Shock leaves its DoT, Earth Shock spends Revelation.
local function shockCooldown()
    return 6 - 0.2 * talent.reverberation.rank
end

local function shockEffect(other, debuffKey)
    return function()
        -- shockCooldown's formula, repeated: called from here it runs outside the handler's state environment (no
        -- `talent`)
        setCooldown(other, 6 - 0.2 * talent.reverberation.rank)
        if debuffKey then
            -- the aura's duration, explicit for `now`
            applyDebuff("target", debuffKey, 12 + 3 * talent.call_of_flame.rank)
        else
            removeBuff("revelation") -- Earth Shock: Revelation's mask has it, not Flame Shock
        end
    end
end

-- A rank's cost with Convection (16039, aura 108 misc 14: -2% a rank on mask 0x90100003 and Lava Burst's: Lightning
-- Bolt, Chain Lightning, the shocks, Lava Burst) when `convection`, and Shamanistic Focus (1223030, aura 108 misc 14:
-- -45% on mask 0x90100400: the shocks and Lightning Shield) when `focus`, multiplied (wowsims's PowerCost_Pct rows).
local function costed(costs, ids, convection, focus)
    return function()
        local c = byRank(costs, ids)
        if convection then
            c = c * (1 - 0.02 * talent.convection.rank)
        end
        if focus then
            c = c * (1 - 0.45 * talent.shamanistic_focus.rank)
        end
        return c
    end
end

-- A `now` or `handler` that spends Revelation (one charge: the next Lightning Bolt, Chain Lightning or Lava Burst).
local function revealed()
    return function()
        removeBuff("revelation")
    end
end

-- A shield's `now` or `handler`: its 3 charges, the other shield gone (one shield at a time).
local function shield(key, other)
    return function()
        removeBuff(other)
        applyBuff(key, nil, 3)
    end
end

local function shock(other, ids, costs, debuffKey)
    return {
        id = ids[1],
        copy = rest(ids),
        cast = 0,
        cooldown = shockCooldown,
        gcd = "spell",

        spend = costed(costs, ids, true, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(ids),

        now = shockEffect(other, debuffKey),
        handler = shockEffect(other, debuffKey),
    }
end

-- The five-second rule (C3): spirit and mp5 regen per second, the declared starting point the out-of-combat read and
-- the in-combat calibration replace. UNMEASURED: a level 60 Shaman's spirit regen and a little mp5 from gear.
spec:RegisterResource(Enum.PowerType.Mana, nil, nil, {
    fsr = { spirit = 17, mp5 = 2 },
    base = 1520, -- a fraction cost is of base mana (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
})

-- The totems (C6): each one's element and duration with its ranks, for `totem.<key>`.
local registered = {}
for key, t in pairs(TOTEMS) do
    registered[key] = { id = t.ids[1], copy = rest(t.ids), element = t.element, duration = t.duration }
end
spec:RegisterTotems(registered)

spec:RegisterAuras({
    -- 3 charges (DB2 ProcCharges), each hit that lands on us spending one.
    lightning_shield = {
        id = 324,
        copy = rest(LIGHTNING_SHIELD),
        duration = 600,
        max_stack = 3,
        consumedBy = { WOUND = true, BLOCKED = true },
    },
    -- Water Shield (408510, Forever's): 3 globes (wowsims's ProcCharges), each hit on us spending one (a spell crit's
    -- too: not modelled); their mana not modelled.
    water_shield = { id = 408510, duration = 600, max_stack = 3, consumedBy = { WOUND = true, BLOCKED = true } },
    -- Elemental Mastery (16166; wowsims's data, absent from the DB2): 15 s, not spent by a cast (wowsims: the tooltip's
    -- "Lasts"; its TODO: in game).
    elemental_mastery = { id = 16166, duration = 15, max_stack = 1 },
    -- Revelation (1323418; wowsims's data): the weapon enchant's (8217) Shaman buff, one charge, 15 s.
    revelation = { id = 1323418, duration = 15, max_stack = 1 },
    -- Maelstrom Weapon (408498, a rune: D4, inert until learned): our melee hits stack it to 5, Lightning Bolt spends it.
    maelstrom_weapon = { id = 408505, duration = 30, max_stack = 5 },
    -- Elemental Focus's Clearcasting (16246): the next elemental damage spell costs nothing (1 charge, 15 s).
    clearcasting = { id = 16246, duration = 15, max_stack = 1 },
    -- The target's DoT, modelled from our cast (target auras are unreadable in combat).
    -- Call of Flame: wowsims spell data, absent from DB2 (wowdb effects 16038 has none): +3 s a rank (its effect 2,
    -- 3000/6000/9000). IN-GAME CHECK: Flame Shock duration with Call of Flame: 21 s?
    flame_shock = {
        id = 8050,
        copy = rest(FLAME_SHOCK),
        duration = function()
            return 12 + 3 * talent.call_of_flame.rank
        end,
        tick_time = 3,
        max_stack = 1,
    },
    -- Rage of the Farseer (425336): +30% melee and ranged attack speed (DB2 aura 342) for 25 s; nothing reads it here.
    rage_of_the_farseer = { id = 425336, duration = 25, max_stack = 1 },
})

-- Clearcasting (16246): aura 108 misc 14 (cost) -100% on the spells its class mask names (-1743781885 / 4096 against
-- SpellClassSet 11, and Lava Burst's 4096 in the second word); the registered ones: Lightning Bolt, Chain Lightning,
-- Earth Shock, Flame Shock, Fire Nova, Lava Burst (rank 1 IDs, the others through each ability's `copy`). Covered but
-- unregistered: Frost Shock, the rune shocks.
spec:RegisterCostMod({
    aura = "clearcasting",
    pct = -1,
    charges = 1,
    spells = { 403, 421, 8042, 8050, 408341, 408490 },
})

spec:RegisterAbilities({
    -- Maelstrom Weapon (408505 aura 108 base -20, two effects on Lightning Bolt's class mask): each stack takes 20% off
    -- its cast time and cost; five make it instant and free. Elemental Alacrity and Elemental Mastery's flat cuts come
    -- off the cast first; Convection's -2% a rank off the cost.
    lightning_bolt = {
        id = 403,
        copy = rest(LIGHTNING_BOLT),
        cast = function()
            local t = byRank(LIGHTNING_BOLT_CAST, LIGHTNING_BOLT) - (ALACRITY[talent.elemental_alacrity.rank] or 0)
            if buff.elemental_mastery.up then
                t = t - 0.5
            end
            return max(0, t) * max(0, 1 - 0.2 * buff.maelstrom_weapon.stack)
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(LIGHTNING_BOLT_COST, LIGHTNING_BOLT)
                * max(0, 1 - 0.2 * buff.maelstrom_weapon.stack)
                * (1 - 0.02 * talent.convection.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(LIGHTNING_BOLT),

        now = function()
            removeBuff("maelstrom_weapon")
            removeBuff("revelation")
        end,
        handler = function()
            removeBuff("maelstrom_weapon")
            removeBuff("revelation")
        end,
    },

    -- 2 s, 6 s apart (category 85), Elemental Mastery taking the whole cooldown off (16166 effect 1, -100%).
    chain_lightning = {
        id = 421,
        copy = rest(CHAIN_LIGHTNING),
        cast = function()
            return 2 - (ALACRITY[talent.elemental_alacrity.rank] or 0)
        end,
        cooldown = function()
            return buff.elemental_mastery.up and 0 or 6
        end,
        gcd = "spell",

        spend = costed(CHAIN_LIGHTNING_COST, CHAIN_LIGHTNING, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(CHAIN_LIGHTNING),

        now = revealed(),
        handler = revealed(),
    },

    -- 2.5 s, 10 s apart (category 1224); Elemental Mastery takes 0.5 s off the cast (16166 effect 0, -500 ms).
    lava_burst = {
        id = 408490,
        copy = rest(LAVA_BURST),
        cast = function()
            local t = 2.5 - (ALACRITY[talent.elemental_alacrity.rank] or 0)
            if buff.elemental_mastery.up then
                t = t - 0.5
            end
            return t
        end,
        cooldown = 10,
        gcd = "spell",

        spend = costed(LAVA_BURST_COST, LAVA_BURST, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(LAVA_BURST),

        now = revealed(),
        handler = revealed(),
    },

    -- 3 minutes, off the GCD (wowsims's data: no GCD), under the Cooldowns toggle.
    elemental_mastery = {
        id = 16166,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows({ 16166 }),

        now = function()
            applyBuff("elemental_mastery")
        end,
        handler = function()
            applyBuff("elemental_mastery")
        end,
    },

    lightning_shield = {
        id = 324,
        copy = rest(LIGHTNING_SHIELD),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = costed(LIGHTNING_SHIELD_COST, LIGHTNING_SHIELD, false, true),
        spendType = "mana",

        startsCombat = false,
        known = knows(LIGHTNING_SHIELD),

        now = shield("lightning_shield", "water_shield"),
        handler = shield("lightning_shield", "water_shield"),
    },

    -- No cost (DB2 408510: none).
    water_shield = {
        id = 408510,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        startsCombat = false,
        known = knows({ 408510 }),

        now = shield("water_shield", "lightning_shield"),
        handler = shield("water_shield", "lightning_shield"),
    },

    stormstrike = {
        id = 17364,
        cast = 0,
        cooldown = 8,
        gcd = "spell",

        -- wowsims spell data, absent from DB2 (wowdb spell 17364 costs 125 flat): 8% of base mana, 121 at level 60
        -- (its log). shortcut: 121 at every level; below 60 it is less. IN-GAME CHECK: Stormstrike's cost.
        spend = 121,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 17364 }),
    },

    earth_shock = shock("flame_shock", EARTH_SHOCK, EARTH_SHOCK_COST),
    flame_shock = shock("earth_shock", FLAME_SHOCK, FLAME_SHOCK_COST, "flame_shock"),

    -- Hits around the fire totem up (wowsims fire_totems.go): unusable without one; its 10 s cooldown is DB2 category 35,
    -- Improved Fire Nova (16086, aura 107 misc 11: rank 1's -2000 ms x the rank) taking 4 s off at 2/2.
    fire_nova = {
        id = 408341,
        copy = rest(FIRE_NOVA),
        cast = 0,
        cooldown = function()
            return 10 - 2 * talent.improved_fire_nova.rank
        end,
        gcd = "spell",

        spend = cost(FIRE_NOVA_COST, FIRE_NOVA),
        spendType = "mana",

        startsCombat = true,
        known = knows(FIRE_NOVA),
        -- its usability answer is a mana rung (the ladder) although it also needs a fire totem: the costliest spell, so
        -- without it the believed lower bound never reaches 520 (checkpoint: no totem answers not usable, not short)

        usable = function()
            return totem.fire.up, "requires a fire totem"
        end,
    },

    searing_totem = totemAbility("searing_totem"),
    flametongue_totem = totemAbility("flametongue_totem"),
    strength_of_earth_totem = totemAbility("strength_of_earth_totem"),
    grace_of_air_totem = totemAbility("grace_of_air_totem"),
    mana_spring_totem = totemAbility("mana_spring_totem"),
    magma_totem = totemAbility("magma_totem"),
    windfury_totem = totemAbility("windfury_totem"),
    mana_tide_totem = totemAbility("mana_tide_totem"),

    -- A Forever talent (DB2: no cost, off the GCD, 180 s); wowsims/forever casts it as a DPS major cooldown.
    rage_of_the_farseer = {
        id = 425336,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows({ 425336 }),

        now = function()
            applyBuff("rage_of_the_farseer")
        end,
        handler = function()
            applyBuff("rage_of_the_farseer")
        end,
    },

    rockbiter_weapon = imbue(ROCKBITER_WEAPON, ROCKBITER_WEAPON_COST),
    flametongue_weapon = imbue(FLAMETONGUE_WEAPON, FLAMETONGUE_WEAPON_COST),
    windfury_weapon = imbue(WINDFURY_WEAPON, WINDFURY_WEAPON_COST),
    frostbrand_weapon = imbue(FROSTBRAND_WEAPON, FROSTBRAND_WEAPON_COST),
})

-- Talents: { talent tree (1 Elemental, 2 Enhancement, 3 Restoration: the dominant tree picks the spec), rank 1's spell,
-- max rank }: the DB2's 46 nodes (`wowdb talents SHAMAN`; the tree is the DB2's Talent.TabID), keys the snake_case
-- names (a nameless node talent_<spell>), then Shamanistic Focus at tree 0. Reverberation and Improved Fire Nova
-- shorten cooldowns; Shamanistic Focus cuts the shocks' and Lightning Shield's cost.
spec:RegisterTalents({
    -- Elemental (tree 1)
    convection = { 1, 16039, 5 },
    concussion = { 1, 16035, 5 },
    earths_grasp = { 1, 16043, 2 },
    elemental_warding = { 1, 28996, 3 },
    call_of_flame = { 1, 16038, 3 },
    elemental_focus = { 1, 16164, 1 },
    reverberation = { 1, 16040, 5 },
    talent_16041 = { 1, 16041, 5 },
    improved_fire_nova = { 1, 16086, 2 },
    eye_of_the_storm = { 1, 29062, 3 },
    elemental_devastation = { 1, 30160, 3 },
    elemental_reach = { 1, 28999, 2 },
    elemental_fury = { 1, 16089, 1 },
    elemental_alacrity = { 1, 16578, 5 },
    talent_16166 = { 1, 16166, 1 },
    -- Enhancement (tree 2)
    ancestral_knowledge = { 2, 17485, 5 },
    shield_specialization = { 2, 16253, 5 },
    guardian_totems = { 2, 16258, 2 },
    thundering_strikes = { 2, 16255, 5 },
    improved_ghost_wolf = { 2, 16262, 2 },
    improved_lightning_shield = { 2, 16261, 3 },
    enhancing_totems = { 2, 16259, 2 },
    two_handed_axes_and_maces = { 2, 16269, 1 },
    anticipation = { 2, 16254, 5 },
    flurry = { 2, 16256, 5 },
    toughness = { 2, 16252, 5 },
    improved_weapon_totems = { 2, 29192, 2 },
    elemental_weapons = { 2, 16266, 3 },
    spirit_weapons = { 2, 16268, 1 },
    weapon_mastery = { 2, 29082, 5 },
    stormstrike = { 2, 17364, 1 },
    -- Forever-only (wowsims/forever's tree; not in the DB2's Talent table at 70338: checkpoint)
    shamanistic_focus = { 0, 1223030, 1 },
    rage_of_the_farseer = { 0, 425336, 1 },
    -- Restoration (tree 3)
    improved_healing_wave = { 3, 16182, 5 },
    tidal_focus = { 3, 16179, 5 },
    improved_reincarnation = { 3, 16184, 2 },
    ancestral_healing = { 3, 16176, 3 },
    totemic_focus = { 3, 16173, 5 },
    natures_guidance = { 3, 16180, 3 },
    healing_focus = { 3, 16181, 5 },
    totemic_mastery = { 3, 16189, 1 },
    natural_grace = { 3, 29187, 3 },
    restorative_totems = { 3, 16187, 5 },
    tidal_mastery = { 3, 16194, 5 },
    healing_way = { 3, 29206, 3 },
    natures_swiftness = { 3, 16188, 1 },
    purification = { 3, 16178, 5 },
    mana_tide_totem = { 3, 16190, 1 },
})

-- The priority, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and run
-- it, never this block (tests/Forever/shaman_spec.lua checks it matches).
spec:RegisterPack(
    "Elemental (wowsims.com)",
    20261021001,
    [[Hekili:DAzBVTTnqC8pl9nDjyb6b7MM2G6bKHTI2I1GbO(AkrjEYI1sKcKuXWad6Z(osNONSuSrracOe1)F3Xt6)5Jes(bjIrna5XvbREFyWQWGGqsK5qnqIQPz7OBXfcAf())UeQaHHw2MC1E5EnVs7LjRU2(GhkLuMfwAdV08vbjDwU6AiJef9Lh((dpEp8cpsubNXGJIaD2YH6(2etb0M8898ZLk4jq1MWGCAtPPn5H)9FAtWB3MmKrd33gATVUGwrf(DH23MVmTVb0gUyRN7sVFQLIRVbJLIk0L4XGHRL2yZ1Tjugtk(nCXo4G2Rn5VOg69ZKtx99V(desHXuRV33Fl3u0KApg(tE0RrMyQZwV(JRdybVlyDGhwuvYCEjw3PzgUuO9QvakoLA2ShtjvSUGdLSB45BEtAtEU3W761u3(Tte(7B81gfi2AkIL5XavHlmsdu5O4w55U7I63ZfS8g1HtKr5QffHLCASUwHv4t05Y6LtxmBMtvoxbOO3A18eedcOId6nHlf)Tv0lKXF0Zytf9NsvSl7RL2BDtJgWkxE82m2Mqll7ME1zMp9HGoDyezqLuWZIvnc4veD3irPGsdQD45DSKHpJlzmCg0FC6OD7iANu6UAAX6TdQdkOIYf6pTj46XHBuL7QP1QlaHDVyH8jQfWI1A8bZkq5XL8TfgHTgCMhVK(enoTrPnUm7nh3XlVeBwHUaz2oVDc5EX)XaN9y4gn1JtX(TUjxM1O3SYYCgH9NXH6pAKgQ39A2P26WXwi2uBWh5wrV0dc)atJEGdl)sVRMeNklnJENVky5hS9BKiS9Ig3CsF4sU2OD9(p23ex(O73cabnTeyK)KeniBSB(CBis0jMcsuMIJhao1UzNDGyWGEHmhAxMf3DoCRVqC9gjRQ3nrv)bzKvA24ERlU3UaHrwSH6VuRMf(7xm96SEVc6fTGw03Ta6ol5qWt5Ab8HfamXQEomFCbm9w4rNWLTYl4LTXimysq6b(Q(4bvL(9XlS2y7hWw0tTg9Op1I3ZBqxHoEUYr4LAloPfHt9uxqx1CK5F2pNx5(CoCjhXec2)I6(D056r8IWHJEmmWZoyYCng6CuZpEYiMJhtzU(cDP1OHvMbYXHwoBtIHJUmdLxgH5xQvXzgO5xOdXzgVH88lwAJPqQirFb2Xl544QF(5PrDBt()d]]
)
spec:RegisterPack(
    "Enhancement (wowsims.com)",
    20261021003,
    [[Hekili:vAv0UXjou0VL9PnrBeWmtBstuMiLv7w1wTnALipBgdCbChWgzB6O8cF79AMjdgJjk9LrES95479475IjRiptIZPAG806O1xVkA9QOOnKy9lTajULMTNwId40g83)Lxr5zqdW197U4G4GI1OcYenxA26l1cAUHU0owT(RCsQxMvTqgjo(lp(9hF6oyKrsCflphocduzV1XDx)oDf0V70CHfcj8tq2VlhkOD142F8))V(D4097MYshl0eaQqvfTHYdTcGqABTk8edb4Fc(HsWV8k8SKuUQgtLCCSWC2mv)oAEUG)N4G9WlQG(D)dvtVZtmDX3)6ZijvADR6UWWsMUQl1KgHoB9sKtmgZ3S52nr5rFiAtuakSsrbRgvFAMMj4QGwjGGtP6TLsAgKiksOmzIwOHMRyfB)JHrb4CbDT9FBgS)AByrnEFQf8YoygUcMeweOslbEPUYCOavIdCHpm7I4rjNMOALmE5mKhqbEsiVTH(dHmzatRWm1vDkt(wKuMLVDLbRzXG2m99Fk6mo8CYHgbNLLi74WBa6MjGsRfI8KIo5ltHyVhjAhmjpw(LuqLkaKlVz)3pJxpsOHY4Q73ojmEdn2wI9d2C7LWf)KEvHiRtDmFt7kkcYQrCzuLg1EBvgbvZkR0CZDIQIb15NWUE4YzaS7oCiqHup5k1QuAPKuiBWmLTh8hjPIA9SCOHc1iirtYbG2k4bkn2H6HTFCIeykUX4uKTFsIKddCyTStwCuShwXVKAv68WQO3iUnh3XfdSs0G9CXbE)3iXOzxHl60zSMP0QH(Xh7bHdFAO)mWPP1qo5VjXw1AMfp1uGepZQqIZKm0qXOMfpBsiA8qFNCABI8s3nd0T5Ds3O9YG6dVtuEmCg4F0b(RBFULZoY9z9mSD9cSTGvCoLUwsdP34q6igF(XXd9C9go0u(AKdKUpTiDlArh50DXZuV2q9TlL(2265jTJ92W0QOfvYZ2GH95wx7iolA09Lsgl3uTALBjULy5TnGL6po)urALBD(RiSABmSp3kBp3RZ9sy)KbWlvx7MTwj0snAq(0MNpC6RV(6M8(CntEqHVgit0o7Nv4HLtpVWxJJFdxNZJn81qzSZOZto8WZRp9yqYqrJ2PRess8xG9SAg(eUpF6fAdlt(1p]]
)

-- The hand-built Enhancement list, replaced by Enhancement (wowsims.com): a saved choice of it falls back to the default.
spec:RetirePacks({ "Enhancement" })
