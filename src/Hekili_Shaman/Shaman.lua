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
-- by Elemental Mastery), Elemental Mastery, Magma, Windfury and Mana Tide Totems (Windfury Totem only for a
-- pack that casts it, as that list's pre-pull does), Water Shield (one shield at a time), Convection's and Elemental
-- Alacrity's cuts, Clearcasting on Chain Lightning, Revelation's charge (Lava Burst is gone from the game).
-- Also unmodelled: Mana Tide's mana, Water Shield's mana, Revelation's proc (the weapon enchant's; the player aura read
-- answers it), Lightning Overload, Mindfulness (mana regen while casting: Elemental's `fsr.share`, below, carries it;
-- Improved Stormstrike's casting share is the mana entry below).
-- From wowsims/forever's spell data, absent from the Forever DB2 at 70338 (in-game checks): Call of Flame's +3 s a
-- rank on Flame Shock, Stormstrike's cost, Mana Tide Totem's rank 4 (1325256), Elemental
-- Mastery, Revelation, Elemental Alacrity's Forever ranks. Also from it: Fire Nova's costs (the DB2's are wrong: R57a),
-- Chain Lightning's and Mana Tide Totem's costs (owner rule 2026-11-06: wowsims over the DB2).
-- Credits: Hekili (registration API, pack format and `summonTotem`'s signature, State.lua). wowsims/forever (MIT,
-- ui/specs/shaman/enhancement/apls/default.apl.json and sim/shaman/) is the reference for the priorities and the totem,
-- Fire Nova, Maelstrom Weapon and Clearcasting rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase = Facade.UnitClassBase
local L = Hekili:GetLocale("Hekili_Shaman")

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
-- The owner's in-game tooltips (2026-11-06), every rank: 65 / 120 / 210 / 290 / 375 mana at levels 12 / 22 / 32 / 42 /
-- 52 (rank 5 first, R57a); wowsims/forever's spell data (e2842f0a78, 408341-408345 Powers) agrees. The DB2's 95, 170,
-- 280, 395, 520 are wrong.
local FIRE_NOVA_COST = { 65, 120, 210, 290, 375 }
local ROCKBITER_WEAPON = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 }
local ROCKBITER_WEAPON_COST = { 15, 25, 50, 75, 100, 125, 150 }
local FLAMETONGUE_WEAPON = { 8024, 8027, 8030, 16339, 16341, 16342 }
local FLAMETONGUE_WEAPON_COST = { 30, 55, 80, 105, 130, 155 }
local WINDFURY_WEAPON = { 8232, 8235, 10486, 16362 }
local WINDFURY_WEAPON_COST = { 90, 115, 140, 165 }
local FROSTBRAND_WEAPON = { 8033, 8038, 10456, 16355, 16356 }
local FROSTBRAND_WEAPON_COST = { 60, 85, 110, 135, 160 }
local CHAIN_LIGHTNING = { 421, 930, 2860, 10605 }
-- Chain Lightning's costs: wowsims 4b0030a44b's spell data (spells_auto_gen.go Powers), every rank (re-pin 0.7: up from
-- 145/200/250/315; the Elemental log's 445.5 is rank 4's 495 x 0.9 Convection). Lava Burst is gone from the game
-- (owner, 2026-11-07; the sim dropped it at 4fe09d45b7).
local CHAIN_LIGHTNING_COST = { 245, 360, 425, 495 }
-- Elemental Alacrity (16578, aura 107 misc 10 on Lightning Bolt and Chain Lightning) by rank: Forever's
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
    -- 5 minutes (category 591); rank 4 (1325256) is Forever's. Costs: wowsims e2842f0a78's spell data, every rank
    -- (the DB2's 10/30/60 for ranks 1-3 are wrong).
    mana_tide_totem = {
        element = "water",
        ids = { 16190, 17354, 17359, 1325256 },
        cost = { 10, 20, 30, 60 },
        duration = { 13, 13, 13, 13 },
        cooldown = 300,
    },
    -- The totems below are prompted by no pack; they exist for the player's own priorities. Ids, costs, levels and
    -- durations are wowsims e2842f0a78's (levels agree with the DB2 SpellLevels). Elements come from the pin's
    -- SummonProperties slots (the summon effect's Misc2: fire 63, earth 81, water 82, air 83).
    stoneskin_totem = {
        element = "earth",
        ids = { 8071, 8154, 8155, 10406, 10407, 10408 },
        cost = { 30, 60, 90, 115, 160, 210 },
        duration = { 300, 300, 300, 300, 300, 300 },
    },
    healing_stream_totem = {
        element = "water",
        ids = { 5394, 6375, 6377, 10462, 10463 },
        cost = { 40, 50, 60, 70, 80 },
        duration = { 300, 300, 300, 300, 300 },
    },
    fire_resistance_totem = {
        element = "water",
        ids = { 8184, 10537, 10538 },
        cost = { 75, 120, 180 },
        duration = { 300, 300, 300 },
    },
    frost_resistance_totem = {
        element = "fire",
        ids = { 8181, 10478, 10479 },
        cost = { 75, 120, 180 },
        duration = { 300, 300, 300 },
    },
    nature_resistance_totem = {
        element = "air",
        ids = { 10595, 10600, 10601 },
        cost = { 75, 120, 180 },
        duration = { 300, 300, 300 },
    },
    windwall_totem = {
        element = "air",
        ids = { 15107, 15111, 15112 },
        cost = { 115, 170, 225 },
        duration = { 300, 300, 300 },
    },
    tremor_totem = { element = "earth", ids = { 8143 }, cost = { 60 }, duration = { 300 } },
    -- 10% of base mana (wowsims's CostPct). -- shortcut: the flat level-60 value (base mana 1520), less below 60; upgrade when the engine has percent-of-level-base-mana costs or after the launch in-game cost check
    poison_cleansing_totem = { element = "water", ids = { 8166 }, cost = { 152 }, duration = { 300 } },
    disease_cleansing_totem = { element = "water", ids = { 8170 }, cost = { 152 }, duration = { 300 } },
    sentry_totem = { element = "air", ids = { 6495 }, cost = { 65 }, duration = { 300 } },
    -- 6% of base mana, 45 s, 15 s cooldown. -- shortcut: the flat level-60 value (base mana 1520), less below 60; upgrade when the engine has percent-of-level-base-mana costs or after the launch in-game cost check
    earthbind_totem = { element = "earth", ids = { 2484 }, cost = { 91 }, duration = { 45 }, cooldown = 15 },
    stoneclaw_totem = {
        element = "earth",
        ids = { 5730, 6390, 6391, 6392, 10427, 10428 },
        cost = { 15, 30, 55, 75, 105, 140 },
        duration = { 15, 15, 15, 15, 15, 15 },
        cooldown = 30,
    },
    -- 6% of base mana, 45 s, 15 s cooldown. -- shortcut: the flat level-60 value (base mana 1520), less below 60; upgrade when the engine has percent-of-level-base-mana costs or after the launch in-game cost check
    grounding_totem = { element = "air", ids = { 8177 }, cost = { 91 }, duration = { 45 }, cooldown = 15 },
}

-- Mana Spring's buff on us (DB2 aura 24), mana every 2 s by totem rank.
local MANA_SPRING = { 4, 6, 8, 10 }

local function rest(ids)
    local out = {}
    for i = 2, #ids do
        out[#out + 1] = ids[i]
    end
    return out
end

-- The highest known rank of a rank list, from the belief's spellbook: the same answer in the sim's `state`
-- environment and in a `now` handler's (event-facade spec §12a).
-- A helper's environment is the file's, so it keeps this local; a pack function's bare `knownRank` is its environment's.
local rankOf = state.knownRank

local function knows(ids)
    return function()
        return rankOf(ids) > 0
    end
end

local function byRank(values, ids)
    return values[rankOf(ids)] or values[1]
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
        local d = byRank(t.duration, t.ids)
        if key == "magma_totem" then -- Trial by Fire (16086 effect 3, wowsims spell data): +10 s a rank
            d = d + 10 * talent.improved_fire_nova.rank
        end
        summonTotem(key, t.element, d)
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

-- The weapon imbues: one per main hand (wowsims models the main hand only), so each replaces the others.
local IMBUES = { "rockbiter_weapon", "flametongue_weapon", "windfury_weapon", "frostbrand_weapon" }

-- A weapon imbue on the main hand: 60 minutes (DB2 tooltip; probe 2026-11-05: 3578906 ms left at the first read), its
-- own aura (`enchants`) and the shared main_hand_enchant (C4), read from the client in combat too. Upstream retail's
-- `essential` (a precombat line is prompted in combat while it is down) and `nobuff` (never while its own is up). The
-- `now` and the `handler` are two closures, so each gets its own environment (as the totems' summon).
local function imbue(ids, costs, key)
    local function apply()
        return function()
            for i = 1, #IMBUES do
                if IMBUES[i] ~= key then
                    removeBuff(IMBUES[i])
                end
            end
            applyBuff(key, 3600)
            applyBuff("main_hand_enchant", 3600)
        end
    end
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
        essential = true,
        nobuff = key,

        now = apply(),
        handler = apply(),
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

-- A rank's cost with Convection (16039, aura 108 misc 14: -2% a rank on mask 0x90100003: Lightning
-- Bolt, Chain Lightning, the shocks) when `convection`, and Shamanistic Focus (1223030, aura 108 misc 14:
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

-- A `now` or `handler` that spends Revelation (one charge: the next Lightning Bolt or Chain Lightning).
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
-- the in-combat calibration replace, as wowsims's logs measure them at 60: shaman_elemental 31.13 a second while casting
-- (Mana Spring Totem, Mindfulness 3/3's 15% share and gear) and 45.25 outside the rule, so spirit 14.12 (the outside
-- rate less the casting one) and mp5 31.13 (the e2842f0a78 log, Windshaper Skyborne; was 29.75 / 42.5 as a Troll);
-- shaman_enhancement 17.8 / 49.05, so spirit 31.25 and mp5 17.8 (the e2842f0a78 log, Windshaper Skyborne; was 9.8 /
-- 38.42 as an Orc). Forever's
-- Spirit regen is `6.25 + Spirit/8` a second for every class (wowsims mana.go:75-76), not Classic's formula.
-- The seeds' mp5 is the rate without the totem's buff (the logs' casting rate a tick before it: 2.613 a tick in
-- shaman_elemental.log before -2.0 s, 1.280 in shaman_enhancement.log before -3.0 s), so 26.13 and 12.8; the totem's
-- own entry (below) adds its mp5 while the buff is up, as wowsims models it (totems.go:105-109).
-- Improved Stormstrike (1238931, DB2 aura 134 = 50): +50% of Spirit regen while casting for 15 s.
-- Mana Spring (DB2 aura 24, 4/6/8/10 every 2 s by rank, +5% a rank of Restorative Totems 16187): mp5 = value / 2.
-- state.spec: the functions run in the state's environment (the file's `spec` is the class).
spec:RegisterResource(
    Enum.PowerType.Mana,
    {
        improved_stormstrike = { aura = "improved_stormstrike", share = 0.5 },
        mana_spring = {
            aura = "mana_spring",
            mp5 = function()
                local ranks = TOTEMS.mana_spring_totem.ids
                return (MANA_SPRING[knownRank(ranks)] or MANA_SPRING[1])
                    / 2
                    * (1 + 0.05 * talent.restorative_totems.rank)
            end,
        },
    },
    nil,
    {
        fsr = {
            spirit = function()
                return state.spec.elemental and 14.12 or 31.25
            end,
            mp5 = function()
                return state.spec.elemental and 26.13 or 12.8
            end,
            share = function()
                return state.spec.elemental and 0.15 or 0
            end,
        },
        base = 1520, -- a fraction cost is of base mana (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
    }
)

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
    -- The weapon imbues (id-less): up while a weapon carries one of the rank's enchant IDs (DB2 70707, Effect 360's
    -- misc value, lowest rank first; Rockbiter rank 2's 6 read in game, 2026-11-05), read from the client.
    rockbiter_weapon = { enchants = { 29, 6, 1, 503, 1663, 683, 1664 }, duration = 3600, max_stack = 1 },
    flametongue_weapon = { enchants = { 5, 4, 3, 523, 1665, 1666 }, duration = 3600, max_stack = 1 },
    windfury_weapon = { enchants = { 283, 284, 525, 1669 }, duration = 3600, max_stack = 1 },
    frostbrand_weapon = { enchants = { 2, 12, 524, 1667, 1668 }, duration = 3600, max_stack = 1 },
    -- Improved Stormstrike (DB2 1238931): Stormstrike's 15 s buff, +50% Spirit regen while casting (the mana entry).
    improved_stormstrike = { id = 1238931, duration = 15, max_stack = 1 },
    -- The totems' buffs on us (wowsims e2842f0a78's ids, ranks 1..n; copy leads with the `<name>_totem` alias), read like
    -- any aura: observed out of combat, not applied by the summon. Mana Spring's is up while its water totem stands
    -- (the mana entry). Tremor, the cleansers, Sentry, Earthbind, Stoneclaw, Grounding, Searing and Magma leave none.
    mana_spring = { id = 10494, copy = { "mana_spring_totem", 5677, 10491, 10493 }, duration = 300, max_stack = 1 },
    stoneskin = {
        id = 10405,
        copy = { "stoneskin_totem", 8072, 8156, 8157, 10403, 10404 },
        duration = 300,
        max_stack = 1,
    },
    strength_of_earth = {
        id = 25362,
        copy = { "strength_of_earth_totem", 8076, 8162, 8163, 10441 },
        duration = 300,
        max_stack = 1,
    },
    grace_of_air = { id = 25360, copy = { "grace_of_air_totem", 8836, 10626 }, duration = 300, max_stack = 1 },
    -- Mana Tide's 13 s buff (rank 4, 1325257, is Forever's)
    mana_tide = { id = 1325257, copy = { "mana_tide_totem", 16191, 17355, 17360 }, duration = 13, max_stack = 1 },
    healing_stream = {
        id = 10461,
        copy = { "healing_stream_totem", 5672, 6371, 6372, 10460 },
        duration = 300,
        max_stack = 1,
    },
    fire_resistance = {
        id = 10535,
        copy = { "fire_resistance_totem", 8185, 10534 },
        duration = 300,
        max_stack = 1,
    },
    frost_resistance = {
        id = 10477,
        copy = { "frost_resistance_totem", 8182, 10476 },
        duration = 300,
        max_stack = 1,
    },
    nature_resistance = {
        id = 10599,
        copy = { "nature_resistance_totem", 10596, 10598 },
        duration = 300,
        max_stack = 1,
    },
    windwall = { id = 15110, copy = { "windwall_totem", 15108, 15109 }, duration = 300, max_stack = 1 },
    -- the party's proc-trigger auras (the 1 s attack-power buff Windfury's proc applies is not declared)
    flametongue = {
        id = 15036,
        copy = { "flametongue_totem", 8230, 8250, 10521 },
        duration = 300,
        max_stack = 1,
    },
    windfury = { id = 10612, copy = { "windfury_totem", 8515, 10609 }, duration = 300, max_stack = 1 },
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
-- SpellClassSet 11); the registered ones: Lightning Bolt, Chain Lightning,
-- Earth Shock, Flame Shock, Fire Nova (rank 1 IDs, the others through each ability's `copy`). Covered but
-- unregistered: Frost Shock, the rune shocks.
spec:RegisterCostMod({
    aura = "clearcasting",
    pct = -1,
    charges = 1,
    spells = { 403, 421, 8042, 8050, 408341 },
})

spec:RegisterAbilities({
    -- Maelstrom Weapon (408505 aura 108 base -20, two effects on Lightning Bolt's class mask): each stack takes 20% off
    -- its cast time and cost; five make it instant and free. Elemental Alacrity and Elemental Mastery's flat cuts come
    -- off the cast first; Convection's -2% a rank off the cost.
    lightning_bolt = {
        id = 403,
        expects = "travel",
        velocity = 20,
        school = "nature",
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
        cooldown = 6, -- wowsims 4b0030a44b (was 8)
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
        -- without it the believed lower bound never reaches 375 (checkpoint: no totem answers not usable, not short)

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
    stoneskin_totem = totemAbility("stoneskin_totem"),
    healing_stream_totem = totemAbility("healing_stream_totem"),
    fire_resistance_totem = totemAbility("fire_resistance_totem"),
    frost_resistance_totem = totemAbility("frost_resistance_totem"),
    nature_resistance_totem = totemAbility("nature_resistance_totem"),
    windwall_totem = totemAbility("windwall_totem"),
    tremor_totem = totemAbility("tremor_totem"),
    poison_cleansing_totem = totemAbility("poison_cleansing_totem"),
    disease_cleansing_totem = totemAbility("disease_cleansing_totem"),
    sentry_totem = totemAbility("sentry_totem"),
    earthbind_totem = totemAbility("earthbind_totem"),
    stoneclaw_totem = totemAbility("stoneclaw_totem"),
    grounding_totem = totemAbility("grounding_totem"),

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

    rockbiter_weapon = imbue(ROCKBITER_WEAPON, ROCKBITER_WEAPON_COST, "rockbiter_weapon"),
    flametongue_weapon = imbue(FLAMETONGUE_WEAPON, FLAMETONGUE_WEAPON_COST, "flametongue_weapon"),
    windfury_weapon = imbue(WINDFURY_WEAPON, WINDFURY_WEAPON_COST, "windfury_weapon"),
    frostbrand_weapon = imbue(FROSTBRAND_WEAPON, FROSTBRAND_WEAPON_COST, "frostbrand_weapon"),
})

-- Talents: { talent tree (1 Elemental, 2 Enhancement, 3 Restoration: the dominant tree picks the spec), rank 1's
-- spell, max rank }: Forever's tree as wowsims/forever's ui/sim/talents/trees/shaman.json lists it
-- (tools/wowsims/talents.lua writes it; tests/Forever/talent_trees_spec.lua checks it and the spec detection over it). A
-- key is Classic's where the talent exists there (code reads `talent.<key>.rank`), else the snake_case of the node's
-- name. Reverberation and Improved Fire Nova shorten cooldowns; Shamanistic Focus cuts the shocks' and Lightning
-- Shield's cost.
spec:RegisterTalents({
    -- Elemental (tree 1)
    convection = { 1, 16039, 5 },
    concussion = { 1, 16035, 5 },
    elemental_devastation = { 1, 30160, 3 },
    reverberation = { 1, 16040, 5 },
    elemental_alacrity = { 1, 16578, 3 },
    call_of_flame = { 1, 16038, 3 },
    elemental_focus = { 1, 16164, 1 },
    elemental_warding = { 1, 28996, 3 },
    improved_fire_nova = { 1, 16086, 2 },
    eye_of_the_storm = { 1, 29062, 3 },
    earthbound = { 1, 1222988, 1 },
    elemental_reach = { 1, 28999, 2 },
    call_of_thunder = { 1, 16120, 1 },
    lightning_overload = { 1, 408438, 3 },
    elemental_fury = { 1, 16089, 5 },
    talent_16166 = { 1, 16166, 1 },
    -- Enhancement (tree 2)
    earths_grasp = { 2, 16043, 2 },
    thundering_strikes = { 2, 16255, 5 },
    ancestral_knowledge = { 2, 17485, 5 },
    guardian_totems = { 2, 16258, 2 },
    mental_dexterity = { 2, 415140, 3 },
    improved_lightning_shield = { 2, 16261, 3 },
    elemental_weapons = { 2, 16266, 3 },
    shamanistic_focus = { 2, 1223030, 1 },
    anticipation = { 2, 16254, 3 },
    toughness = { 2, 16252, 5 },
    flurry = { 2, 16256, 5 },
    stormstrike = { 2, 17364, 1 },
    improved_ghost_wolf = { 2, 16262, 2 },
    spirit_weapons = { 2, 16268, 1 },
    mental_quickness = { 2, 30812, 2 },
    improved_stormstrike = { 2, 1223031, 2 }, -- wowsims's tree (spell_data_auto_gen.go:238); the DB2 names the spell only
    maelstrom_weapon = { 2, 408498, 5 },
    rage_of_the_farseer = { 2, 425336, 1 },
    -- Restoration (tree 3)
    improved_healing_wave = { 3, 16182, 5 },
    tidal_focus = { 3, 16179, 5 },
    mindfulness = { 3, 1223033, 3 },
    natural_grace = { 3, 29187, 3 },
    totemic_focus = { 3, 16173, 5 },
    improved_reincarnation = { 3, 16184, 2 },
    ancestral_healing = { 3, 16176, 3 },
    healing_focus = { 3, 16181, 3 },
    water_shield = { 3, 408510, 1 },
    tidal_mastery = { 3, 16194, 5 },
    restorative_totems = { 3, 16187, 5 },
    mana_tide_totem = { 3, 16190, 1 },
    healing_way = { 3, 29206, 3 },
    natures_swiftness = { 3, 16188, 1 },
    purification = { 3, 16178, 5 },
    riptide = { 3, 408521, 1 },
})

-- The time to each hand's next swing (Hekili_Warrior/Warrior.lua's, after Hekili's Classic profile): Enhancement's AoE
-- Chain Lightning reads wowsims's AnyAuto, the earlier hand (translator-5); a Shaman has no ranged auto. With no
-- off-hand weapon that hand never swings: 3600 s, so min() takes the main hand.
spec:RegisterStateExpr("mainhand_remains", function()
    -- out of combat no swing runs (nextMH is 0): anchor it at this evaluation, or its phase free-runs with the clock
    local mh = (nextMH == 0 and combat == 0) and now or nextMH
    if now == query_time then
        local real = mh - now
        return real > 0 and real or 0
    end
    if query_time <= mh then
        return mh - query_time
    end
    if mainhand_speed <= 0 then
        return 0
    end -- no swing speed read yet
    return mainhand_speed - (query_time - mh) % mainhand_speed
end)

spec:RegisterStateExpr("offhand_remains", function()
    if offhand_speed <= 0 then
        return 3600 -- no off-hand weapon: that hand never swings (wowsims's NeverExpires)
    end
    local oh = (nextOH == 0 and combat == 0) and now or nextOH
    if now == query_time then
        local real = oh - now
        return real > 0 and real or 0
    end
    if query_time <= oh then
        return oh - query_time
    end
    return offhand_speed - (query_time - oh) % offhand_speed
end)

-- The priority, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and run
-- it, never this block (tests/Forever/shaman_spec.lua checks it matches).
spec:RegisterPack(
    "Elemental (wowsims.com)",
    20261107001,
    [[Hekili:TEv7UTTnu0NL(NmBSa9HxttBqvbYW2qBXAWau)TKPfVYI1sKcKujWab6zFxkBlRVOIxxqacOe59CU3d59i6i)OVhfsjAi6HvERENVV3TEE(rH69LquyjjzhzloGtkW))N5qbW1K861lEs8KIvOCseflnlCFUGqnGTPILR)cpAZK4QkHKOWWpF)3U)H7Gt4ffMXOu4qqGkXov3vVwNb1Rp(o3uHeEeK1RPqkPkxxV(()5VRxJVUEDxmQyUgQvUQmsbH72sTRjFPkxnO0m(wNMhD(HsWxEnYLKWv5yzqXXcd3mv9AcLk4)coyhSx5uV(piAYDtKtl(2x(ocsMwxQUZ1DltNvTXugUdw6setm1HBiFiHUISIMM4GIQuKYYrDNKOzcUYPucyWBi6GNWusgRYyqo9AwAWB2uLM609TovL1FDuG)AGRslb(wDwSingisCGwOHIguAg508wRX)eJttRK7hfgHjTgek5KyvPev4rX1K12txmBMkQuMeWGUYeZJqmWHcgOc8TX)2cYfIXNoJrqb5hczCt2xkmV66kfGkxA82eAGVblZKoLj64CXhFVxBOiPuOqWzjXYkomFC32lUg60mkCoH7U4B6T4)BNeWamjcdHv1pL6UKrA(IHQ8vDeqjuqyC1hd8w2Vk6j5lgkYxaeTnP4oGclO9JvXfV5WYDsZrlkSIfj7C2XfpXFMcnsr3jQk7H)MCHGgBom)AdmivGChQHVYaNKH6uCoBBMMBqFkH95fDoT8PG36DvlLJe0JeF4qZ4zr2x2JFZUvmx8iXWS12gZcpxdxNksQubRmHmrfEEVV3wFJZu349N(GydEgtu0L2uIdeSwPkEJixpSvALN91w)1Oq0AwHto4By5mLw18DZdFZbh(qZ3rboztoqJ(9OWoB7MjpAHhfoYqjkmrITJsgXmzxRKinY7fcBxRgBiEBdI)2aepNy9mDSbYnnG8wlG012PlctAkza6MlS(AnTmb9olS3Z2Ql9xQ9Lb8BTQpT2zZaTvBnd0V)cl2r9H9i0U9Hf)dd1F4cP(SJ4)Fo99UusBDlFfiDyJ4jsg4Co7E4Z)ewOZ7H2KAdBMpLATMQDtQH5udcdBEpV8znw7q155Xhm(Qgpgd0dBPNR7zcp3oNEp7C3sXHSFyZ(Pi677AZ5zvJZJVTM)bGy(lS9gGt5q)t7zzBB0YfR7Hz)lypNFC)RzpbihUU9CUXJU09eOC6Y3tzg)I(QVWvXNZR2ID6lCX8OJBSKkDMqgf(zyhlNH)qR)64VJQz6O)9d]]
)
spec:RegisterPack(
    "Enhancement (wowsims.com)",
    20261110000,
    [[Hekili:DJ13VTTnq4)w2lzXybY)OlnTbvbidBdTdRbdW9zjtlDYI1uKgKuXWVO)23rAxlkkrfJ1T8WYdj6h39Dh59Dh)IsMN8LKL5enK80IzlE785ZNH)KSuFyhKSChjBlzdEbNuH)(34LeEgubCDZQR3l2ROvQOmr1eJPhycsUbU11uM(t8K1dISAhKLSC5hF8Zp(09qlIjllP55Wr3av2yH7(Mv6sOz1PNnTqiHNbzZQCOGuZqZF8V(ZMv4JBw1fLA6utcOMQkjve(uNeyQjVZvt1Gst5BIS3g9vLGp5gmEscxXWLtoETWeFQQzfjpxW)r8ITWbvuZQFLOj3pqED9N)0xqqk16DQ7NoDdvxwV2SuM6z6eetmpHBjVplFbzrErweU5kffugwbizAQGRI2jb051eDCbdlnAbFtnKUhi7e8BOfX)W66IIOkcLNIRV8uGNH)vhvVR5p6HXpfpvkY2UMQb5fHXv)WrmI6h8OTCXE(WbzpXeavjfy5TbW9PbZV9uEErT8qQwOHkRZ2RIiuzqNW6ljvTtIfZE(zJAqpvAjW3OltffParIx47V9PJe5nvKE(uqLGRl)ZRD)hwXSz)xfYu7U3oH5H3uRaCROiDtwE8CtKmVmAxMoLj(W7M56Couj40Suznhg3V764xhYrHiRwfV4LjjdsnAzgsWSzO(q8cxpgP66wCh25bjvUCQqU1Hr4qig2(1mHip1SU6Uj2XgqQa5wmtcBJ5filPsf2ejoH3SvGtutliiKGmSXzegl94TPmQsFJ5KHyfMdmivtKBaDQuOjwAdUqnM(mGmrOIcQlblIagbHh6GaJUPuZnLI1cM2sxoXZvAHScl00TG)iPHt2JnJifd7RC5F5GLa6822k2Sxculz7CICbw7TGoMh2oNR1egEif2Ddmeor13AFbozndYV6uVV3BvA8i84BNCbX(yRGDjEbwB4UPCXZKwBDRCX4KhQPSEA94UeaM98wcw8zKmjvFicpCD7dXV5Qkk)AZMRD81P95BqIO79tE4un2lerzeLEYWPZlNWgl(UyaEGnyD3ZMxHQTxe7uJtwIcou4l8uOz6fvgHCUoJ3)KvS4Pmi5x(MAKKLEfc8bsZjtusYYxLAEIgxbbYTZLDJrVXZO28C0ISdATVhVXuVmrgr(NdeEhAGXSBdMaFNv82i2LuDolNBc)BdKLo0c0m0PHB7hId8V3wyOkO3wy4A4RYwyOcD3TWEf6HOJAZEM9)xzSMR(k2CxZHL8n2wQV4XldXxue5qLhhLeM145uONit3COR8YH22dbRR8ZqiE3SXBfhuYzBiCFrxgCO2RUsuDd1qsvniDxWEHbLU2hsFjSgqFxaq7jPTpC(sBnW9(GWDwQBFG8K8AWz(SlS22Qj26MFdtq3olt26MFpri3oRC261LsRhqmT1FF(B7(IXtxfYohR6Pp(4jZPh)wmbMqBIvyMD3y9WLgRo6amrier3FWPtp1Prh90LFCo45)55)hpjC45hV0yNroYj8yLoFCKXooA0wFVpvYyt4UG5sEF4KXMYfycs3pJIL4GuhsTUuitw(rylLrBwD9VF6lPzFDYF)]]
)

-- The hand-built Enhancement list, replaced by Enhancement (wowsims.com): a saved choice of it falls back to the default.
spec:RetirePacks({ "Enhancement" })
