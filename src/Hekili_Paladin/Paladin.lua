-- Hekili_Paladin/Paladin.lua
-- The Forever Paladin (Protection, Retribution and an idle Holy, one spec a talent tree: Hekili:NewClass): the Paladin
-- kit with Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build
-- 1.60.1.70338, wowdb; a cost percentage there is a fraction of the believed maximum, as the Druid's), the seals as
-- player auras (one at a time: a seal's `now` takes the others down), Twist of Light's Echoes, Swift
-- Judgement, Holy Shield's charges spent by blocks on us (`consumedBy`), Hammer of Wrath through the target health
-- gate, mana under the five-second rule (`fsr`), and the default priorities (the wowsims.com packs, translated from
-- wowsims/forever's APLs by tools/wowsims/; no in-game check yet). Research: the class-completion research §3.
-- Judgement does not consume the seal (wowsims/forever judgement.go and the DB2 tooltip); the in-game checkpoint asks.
-- Talents: the DB2's 44 Classic nodes and the Forever-only ones this file reads; a modifier is rank 1's value x the
-- rank, floored at 0, except where the DB2 holds the full-rank value on rank 1 (Benediction, Holy Conduit: each one's
-- comment).
-- The seven seals (Justice, Light and Wisdom too), Judgement's debuff on the target (modelled from the cast, not
-- refreshed by our hits), Templar's Bulwark and Forbearance, and the own procs the Cooldown Manager follows are
-- registered; the Justice sets' 5-piece bonuses read as set_bonus.
-- Unmodelled: Seal of Fury's absorb (the same spell id as the seal, tagged: no id of its own), the seals' attack
-- speed and per-hit effects, Reckoning's and Vengeance's gains (our own hits and crits are unseen), the Echoes'
-- gains (the belief holds them from the aura read).
-- Credits: Hekili (registration API and pack format; `mainhand_remains` follows Hekili's Classic Warrior profile,
-- origin/classic:Classic/Warrior.lua, as Hekili_Warrior/Warrior.lua has it). wowsims/forever (MIT,
-- ui/specs/paladin/*/apls/*.apl.json and sim/paladin/) is the reference for the priorities and the seal, Echo,
-- Judgement and Holy Shield rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase, IsSpellUsable = Facade.UnitClassBase, Facade.C_Spell.IsSpellUsable
local L = Hekili:GetLocale("Hekili_Paladin")

if UnitClassBase("player") ~= "PALADIN" then
    return
end

local state = Hekili.State
local max = math.max

-- The class kit and one spec a talent tree (ids the core's: Holy 100021, unsupported; Protection 100022, Retribution
-- 100023; the client's one pseudo-spec, 1486, only keys the legacy profile the core migrates). Icons: the DB2 tabs'.
local spec = Hekili:NewClass("PALADIN", {
    specs = {
        { key = "holy", name = L["Holy"], tree = 1, icon = 135920, role = "healer", unsupported = true },
        {
            key = "protection",
            name = L["Protection"],
            tree = 2,
            icon = 135893,
            role = "tank",
            package = "Protection (wowsims.com)",
        },
        {
            key = "retribution",
            name = L["Retribution"],
            tree = 3,
            icon = 135873,
            role = "attack",
            package = "Retribution (wowsims.com)",
            movement = true, -- the pack reads toggle.movement: the opener's move reaches the Judgement chain (R5/R12)
        },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's), and each rank's mana cost where it is flat.
local SEAL_OF_COMMAND = { 20375, 20915, 20918, 20919, 20920 }
local SEAL_OF_COMMAND_COST = { 65, 110, 140, 180, 210 }
local SEAL_OF_RIGHTEOUSNESS = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 }
local SEAL_OF_RIGHTEOUSNESS_COST = { 20, 20, 40, 60, 90, 120, 140, 170, 200 }
local SEAL_OF_THE_CRUSADER = { 21082, 20162, 20305, 20306, 20307, 20308 }
local SEAL_OF_THE_CRUSADER_COST = { 25, 40, 65, 90, 125, 160 }
local SEAL_OF_FURY = { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 } -- Forever's; ranks 1-2 Forever-only
local SEAL_OF_FURY_COST = { 40, 60, 90, 120, 140, 170, 200 }
-- The other three seals (wowsims's data, the pin's spells_auto_gen: Justice 13% of the base mana, Light and Wisdom flat).
local SEAL_OF_JUSTICE = { 20164 }
local SEAL_OF_JUSTICE_COST = { 0.13 }
local SEAL_OF_LIGHT = { 20165, 20347, 20348, 20349 }
local SEAL_OF_LIGHT_COST = { 110, 140, 180, 210 }
local SEAL_OF_WISDOM = { 20166, 20356, 20357 }
local SEAL_OF_WISDOM_COST = { 135, 170, 200 }
local BASE_MANA = 1512 -- a fraction cost is of base mana (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
local HAMMER_OF_WRATH = { 24275, 24274, 24239 }
local HAMMER_OF_WRATH_COST = { 295, 360, 425 }
local HOLY_STRIKE = { 679, 678, 1866, 680, 2495, 5569, 10332, 10333 }
local HOLY_STRIKE_COST = { 5, 9, 12, 14, 16, 17, 19, 20 }
local CONSECRATION = { 26573, 20116, 20922, 20923, 20924 }
local CONSECRATION_COST = { 135, 235, 320, 435, 565 }
-- The Undead/Demon ranks, then the ranks that hit any target (Retribution skill line); the highest known is cast.
local EXORCISM = { 879, 5614, 5615, 10312, 10313, 10314, 415068, 415069, 415070, 415071, 415072, 415073 }
local EXORCISM_ANY = 7 -- 415068's place in EXORCISM: the first rank that hits any target
local UNDEAD_DEMON = { "undead", "demon" }
local ANY_TYPE = { "any" } -- usable_on: a living attackable target of any type
local EXORCISM_COST = { 85, 135, 180, 235, 285, 345, 85, 135, 180, 235, 285, 345 }
local HOLY_SHOCK = { 1311606, 20473, 20929, 20930 } -- rank 1 Forever-only
local HOLY_SHOCK_COST = { 160, 225, 275, 325 }
-- Four ranks, from the owner's in-game tooltips (2026-11-06; in game beats wowsims and the DB2): 100 / 150 / 195 / 240
-- mana, learned at 30 / 40 / 50 / 60. Rank 4 (1239570, build 70755) is in wowsims after our pin (041cd46cec); DB2
-- 70707's three-rank 150 / 195 / 240 ladder at 40 / 50 / 60 lacks it.
local HOLY_SHIELD = { 20925, 20927, 20928, 1239570 }
local HOLY_SHIELD_COST = { 100, 150, 195, 240 }
local RETRIBUTION_AURA = { 7294, 10298, 10299, 10300, 10301 }
-- Lane A (coverage; the pin's sim/paladin/spell_data_auto_gen.go ladders, costs and cooldowns from its spells_auto_gen.go).
local HOLY_LIGHT = { 635, 639, 647, 1026, 1042, 3472, 10328, 10329, 25292 }
local HOLY_LIGHT_COST = { 35, 60, 110, 190, 275, 365, 465, 580, 660 }
local FLASH_OF_LIGHT = { 19750, 19939, 19940, 19941, 19942, 19943 }
local FLASH_OF_LIGHT_COST = { 35, 50, 70, 90, 115, 140 }
local LAY_ON_HANDS = { 633, 2800, 10310 }
local HOLY_WRATH = { 2812, 10318 }
local HOLY_WRATH_COST = { 645, 805 }
local HAMMER_OF_JUSTICE = { 853, 5588, 5589, 10308 }
local HAMMER_OF_JUSTICE_COST = { 30, 50, 75, 100 }
local BLESSING_OF_PROTECTION = { 1022, 5599, 10278 }
local BLESSING_OF_PROTECTION_COST = { 25, 45, 0.07 } -- rank 3 is 7% of base mana
local BLESSING_OF_SACRIFICE = { 6940, 20729 }
local BLESSING_OF_SACRIFICE_COST = { 80, 100 }
local DIVINE_SHIELD = { 642, 1020 }
local DIVINE_SHIELD_COST = { 75, 110 }
local DIVINE_PROTECTION = { 498, 5573 }
local DIVINE_PROTECTION_COST = { 15, 35 }
-- Turn Evil (talent 1328370) overrides the three Turn Undead ranks with its own (1328374, 1328373, 1328372: same costs)
local TURN_UNDEAD = { 2878, 5627, 10326, 1328374, 1328373, 1328372 }
local TURN_UNDEAD_COST = { 35, 50, 75, 35, 50, 75 }
local LIGHTS_VIGIL = { 1310911, 1311590, 1311595 }
local LIGHTS_VIGIL_COST = { 730, 1000, 1340 }
local RIGHTEOUS_FURY = { 25780, 407627 } -- 407627: the rune's (D4: registered, inert unless learned)

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

-- Usable now, or only short of mana, by the plain read (Hammer of Wrath's health gate).
local function reactive(ids)
    local r = knownRank(ids)
    if r == 0 then
        return false
    end
    local usable, noMana = IsSpellUsable(ids[r])
    return usable == true or noMana == true
end

-- The seals. Unsealed Wrath's Echoes (hotfix 113554; the talent keeps Twist of Light's 1310735) come from our landed
-- hits, not the seal swap: the `unsealed_wrath` reaction (below) stores them.
local SEALS = {
    "seal_of_command",
    "seal_of_righteousness",
    "seal_of_the_crusader",
    "seal_of_fury",
    "seal_of_justice",
    "seal_of_light",
    "seal_of_wisdom",
}

-- A seal cast's effect (the `now` and the `handler`, two closures so each gets its own environment): the other seal up
-- goes down.
local function sealCast(key)
    return function()
        for i = 1, #SEALS do
            local other = SEALS[i]
            if other ~= key and buff[other].up then
                removeBuff(other)
            end
        end
        applyBuff(key)
    end
end

-- Benediction (20101 aura 108 misc 14, the cost, base -10 on the rank-1 spell only; its class mask covers every cost
-- here but Hammer of Wrath's): 2% less a rank (wowsims's log of the 5/5 build: Seal of Command 151.2 = 210 x 0.8 x 0.9,
-- Holy Strike 18). Written out in each cost: a cost function runs in the state's environment, a helper would not.
-- Holy Conduit (1237268 aura 108 misc 14, base -40 on Consecration's, Hammer of Wrath's and Exorcism's class mask
-- bits; 2 ranks in wowsims's tree): 20% less a rank (wowsims's log of the 2/2 build: Consecration 339 of 565).
local function conduitCost(costs, ids)
    return function()
        return byRank(costs, ids) * (1 - 0.2 * talent.holy_conduit.rank) * (1 - 0.02 * talent.benediction.rank)
    end
end

-- The seals' multiplier (Unsealed Wrath has no cost cut since hotfix 113554), given the caller's `talent` (the state's:
-- a cost function runs in the state's environment, this helper in the file's).
local function sealMult(t)
    return 1 - 0.02 * t.benediction.rank
end

local function sealCost(costs, ids)
    return function()
        return byRank(costs, ids) * sealMult(talent)
    end
end

local function seal(key, ids, costs)
    return {
        id = ids[1],
        copy = rest(ids),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = sealCost(costs, ids),
        spendType = "mana",

        startsCombat = false,
        known = knows(ids),

        now = sealCast(key),
        handler = sealCast(key),
    }
end

-- A self-buff with no other effect (the auras, Righteous Fury, Divine Favor).
local function selfBuff(key, ids, extra)
    local a = {
        id = ids[1],
        copy = #ids > 1 and rest(ids) or nil,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        startsCombat = false,
        known = knows(ids),

        now = function()
            applyBuff(key)
        end,
        handler = function()
            applyBuff(key)
        end,
    }
    for k, v in pairs(extra or {}) do
        a[k] = v
    end
    return a
end

-- Reverence (1310899): 15/30% of the spirit regen while casting by rank (wowsims's curve, e5a9cd2a2d: 2 ranks).
local REVERENCE = { 0.15, 0.3 }

-- The five-second rule (C3): spirit and mp5 regen per second, the declared starting point the out-of-combat read and
-- the in-combat calibration replace, as wowsims's e4ef929e54 logs measure them at 60: Retribution 11.9 spirit + 5.1
-- casting = 17.0 outside (Reverence 2/2's share is the 5.1: the share below is the static share those parts hold; was
-- 13.65 + 8.25 before its gear lost the Soulforge pieces), Protection 0 while casting and 16.5 outside (was 17.38). Forever's Spirit regen is `6.25 + Spirit/8` a second for every class
-- (wowsims mana.go:75-76), not Classic's formula. Holy Shock known (the Holy Shock build, a Retribution spec on its own
-- gear): its own e4ef929e54 log, 2.513 a 0.1 s tick outside, 0.754 casting: 17.59 spirit + 7.54 casting (was
-- Retribution's 11.9 / 5.1).
-- state.spec: the functions run in the state's environment (the file's `spec` is the class). The core resolves them
-- at the build, before its talent walk, so the Holy Shock build is told by the spellbook (knownRank), not talent.*.
spec:RegisterResource(Enum.PowerType.Mana, nil, nil, {
    fsr = {
        spirit = function()
            if state.spec.retribution and knownRank(HOLY_SHOCK) > 0 then
                return 17.59
            end
            return state.spec.retribution and 11.9 or 16.5
        end,
        mp5 = function()
            if state.spec.retribution and knownRank(HOLY_SHOCK) > 0 then
                return 7.54
            end
            return state.spec.retribution and 5.1 or 0
        end,
        share = function() -- Reverence's rank (the belief reads it after its talent walk), never the spec
            return REVERENCE[talent.reverence.rank] or 0
        end,
    },
    base = BASE_MANA,
})

-- Talents: { talent tree (1 Holy, 2 Protection, 3 Retribution: the dominant tree picks the spec), rank 1's spell, max
-- rank }: Forever's tree as wowsims/forever's ui/sim/talents/trees/paladin.json lists it (tools/wowsims/talents.lua
-- writes it; tests/Forever/talent_trees_spec.lua checks it and the spec detection over it). A key is Classic's where the
-- talent exists there (code reads `talent.<key>.rank`), else the snake_case of the node's name.
spec:RegisterTalents({
    -- Holy (tree 1)
    spiritual_focus = { 1, 20205, 5 },
    divine_strength = { 1, 20262, 5 },
    healing_light = { 1, 20237, 3 },
    reverence = { 1, 1310899, 2 },
    improved_seals = { 1, 20224, 5 },
    purifying_power = { 1, 429144, 2 },
    divine_favor = { 1, 20216, 1 },
    illumination = { 1, 20210, 5 },
    holy_conduit = { 1, 1237268, 2 },
    divine_precision = { 1, 1310904, 2 },
    infusion_of_light = { 1, 426065, 2 },
    oath_of_light = { 1, 1328548, 1 },
    consecrated_ground = { 1, 1310905, 2 },
    holy_shock = { 1, 1311606, 1 },
    boundless_light = { 1, 1328550, 2 },
    holy_power_talent = { 1, 5923, 5 },
    lights_vigil = { 1, 1310911, 1 },
    -- Protection (tree 2)
    divine_intellect = { 2, 20257, 5 },
    redoubt = { 2, 20127, 5 },
    precision = { 2, 20189, 3 },
    guardians_favor = { 2, 20174, 2 },
    sacred_duty = { 2, 1224697, 2 },
    templars_bulwark = { 2, 1311015, 1 },
    improved_hammer_of_justice = { 2, 20487, 3 },
    shield_specialization = { 2, 20150, 2 },
    toughness = { 2, 20143, 5 },
    swift_judgement = { 2, 1310994, 1 },
    improved_righteous_fury = { 2, 20468, 3 },
    anticipation = { 2, 20096, 5 },
    stoicism = { 2, 1328546, 2 },
    holy_shield = { 2, 20925, 1 },
    reckoning = { 2, 20177, 5 },
    iron_creed = { 2, 1311034, 3 },
    shieldsworn = { 2, 1328544, 1 }, -- hotfix 113554
    -- Retribution (tree 3)
    deflection = { 3, 20060, 5 },
    benediction = { 3, 20101, 5 },
    improved_judgement = { 3, 25956, 2 },
    conviction = { 3, 20117, 3 },
    sanctified_judgement = { 3, 1311074, 3 },
    vindication = { 3, 9452, 3 },
    unyielding_faith = { 3, 9453, 2 },
    seal_of_command = { 3, 20375, 1 },
    pursuit_of_justice = { 3, 26022, 2 },
    eye_for_an_eye = { 3, 9799, 2 },
    sacred_arbiter = { 3, 1311087, 1 },
    two_handed_weapon_specialization = { 3, 20111, 3 },
    turn_evil = { 3, 1328370, 2 },
    repentance = { 3, 20066, 1 },
    vengeance = { 3, 20049, 3 },
    champion_of_the_light = { 3, 1311084, 5 }, -- hotfix 113554 (replaces Instrument of Law)
    twist_of_light = { 3, 1310735, 1 },
})

-- The Justice sets (wowsims item_sets.go; the item ids the pin's db.json ships, four pieces each so far): only the
-- 5-piece bonuses move a recommendation's timing (a hidden aura each, read through set_bonus); the 2- and 4-piece
-- bonuses are stats, nothing the belief models.
spec:RegisterGear("justice_battlegear", 273908, 273909, 273910, 273911)
spec:RegisterGear("justice_armor", 273912, 273913, 273914, 273915)
spec:RegisterGear("justice_battleplate", 273916, 273917, 273918, 273919)
spec:RegisterSetBonus("justice_battlegear_5pc", 1301702)
spec:RegisterSetBonus("justice_armor_5pc", 1301694)
spec:RegisterSetBonus("justice_battleplate_5pc", 1301697)

spec:RegisterAuras({
    justice_battlegear_5pc = { id = 1301702, duration = 3600, max_stack = 1 },
    justice_armor_5pc = { id = 1301694, duration = 3600, max_stack = 1 },
    justice_battleplate_5pc = { id = 1301697, duration = 3600, max_stack = 1 },
    -- The seals are one family (L727): the Cooldown Manager's Seals entry says a seal is up or none is, our last seal
    -- cast says which.
    seal_of_command = { id = 20375, copy = rest(SEAL_OF_COMMAND), duration = 30, max_stack = 1, family = "seals" },
    seal_of_righteousness = {
        id = 20154,
        copy = rest(SEAL_OF_RIGHTEOUSNESS),
        duration = 30,
        max_stack = 1,
        family = "seals",
    },
    seal_of_the_crusader = {
        id = 21082,
        copy = rest(SEAL_OF_THE_CRUSADER),
        duration = 30,
        max_stack = 1,
        family = "seals",
    },
    seal_of_fury = { id = 1311649, copy = rest(SEAL_OF_FURY), duration = 30, max_stack = 1, family = "seals" },
    -- Unsealed Wrath's Echoes (hotfix 113554 rows: 15 s, 3 stacks): each landed white swing stores a stack of the
    -- active seal's; a swing under another seal spends them (the `unsealed_wrath` reaction, below).
    echo_of_command = { id = 1311703, duration = 15, max_stack = 3 },
    echo_of_righteousness = { id = 1311704, duration = 15, max_stack = 3 },
    echo_of_fury = { id = 1311701, duration = 15, max_stack = 3 },
    echo_of_justice = { id = 1311705, duration = 15, max_stack = 3 },
    echo_of_light = { id = 1328198, duration = 15, max_stack = 3 },
    echo_of_wisdom = { id = 1328206, duration = 15, max_stack = 3 },
    seal_of_justice = { id = 20164, duration = 30, max_stack = 1, family = "seals" },
    seal_of_light = { id = 20165, copy = rest(SEAL_OF_LIGHT), duration = 30, max_stack = 1, family = "seals" },
    seal_of_wisdom = { id = 20166, copy = rest(SEAL_OF_WISDOM), duration = 30, max_stack = 1, family = "seals" },
    -- Holy Shield: +30% block for 10 s, 4 charges (DB2 ProcCharges), each block or partial block on us spending one.
    holy_shield = {
        id = 20925,
        copy = rest(HOLY_SHIELD),
        duration = 10,
        max_stack = 4,
        consumedBy = { BLOCK = true, BLOCKED = true },
    },
    righteous_fury = { id = 25780, copy = { 407627 }, duration = 1800, max_stack = 1 },
    retribution_aura = { id = 7294, copy = rest(RETRIBUTION_AURA), duration = 3600, max_stack = 1 },
    divine_favor = { id = 20216, duration = 3600, max_stack = 1 },
    -- Consecration's area aura on the target (1280353, DB2: 0.6 s on area enemies, refreshed by each 1 s tick; the one
    -- the client and wowsims's log show; 1310905 "Consecrated Ground" targets the caster): its 8 s and the 0.6 s tail
    -- (wowsims consecration.go), modelled from our cast (target auras are unreadable in combat).
    consecrated_ground = { id = 1280353, duration = 8.6, max_stack = 1 },

    -- Judgement's debuffs on the target (B4; wowsims judgement.go, buffs/paladin.go): 40 s (Justice's 10 s, Fury's taunt
    -- 3 s), refreshed by our landed white swings and Windfury Totem's strike, not by Holy Strike, Seal of Command or the
    -- judgements (wowsims 016f21f4cc, EV-0117; unmodelled: Judgement itself recasts every cooldown).
    judgement_of_the_crusader = {
        id = 20188,
        copy = { 20300, 20301, 20302, 20303, 21183 },
        duration = 40,
        max_stack = 1,
    },
    judgement_of_light = { id = 20185, copy = { 20344, 20345, 20346 }, duration = 40, max_stack = 1 },
    judgement_of_wisdom = { id = 20186, copy = { 20354, 20355 }, duration = 40, max_stack = 1 },
    judgement_of_justice = { id = 20184, duration = 10, max_stack = 1 },
    judgement_of_fury = { id = 20232, duration = 3, max_stack = 1 },
    -- Vindication's debuff on the target (B5, wowsims talents_retribution.go:82-121: -AP, 30 s, a proc: observed only).
    vindication = { id = 440667, duration = 30, max_stack = 1 },

    -- Templar's Bulwark's absorb (B2, 8 s) and the Forbearance it brings (60 s less Sacred Duty's 5 s a rank).
    templars_bulwark = { id = 1311015, duration = 8, max_stack = 1 },
    forbearance = { id = 25771, duration = 60, max_stack = 1 },

    -- Own procs (B3; no priority reads them, the Cooldown Manager follows their presence): Vengeance 5 stacks 30 s, a
    -- landed crit; Redoubt 5 charges 10 s, one a block; Reckoning's stored extra attacks (4, until the next swing).
    vengeance = { id = 20050, duration = 30, max_stack = 5 },
    -- (the Cooldown Manager's items link the talents' own IDs too: 20127, 20177)
    redoubt = {
        id = 20128,
        copy = { 20127 },
        duration = 10,
        max_stack = 5,
        consumedBy = { BLOCK = true, BLOCKED = true },
    },
    reckoning = { id = 1326084, copy = { 20177 }, duration = 3600, max_stack = 4 },
    -- Iron Creed's 6 s (-2/4/6% damage taken, a Holy Strike under Righteous Fury) and Shieldsworn's spell block (6 s, every
    -- Holy Strike with a shield, landed or avoided: wowsims 61607b27d7): modelled from our Holy Strikes, neither has a Cooldown Manager item.
    iron_creed = { id = 1311033, copy = { 440668 }, duration = 6, max_stack = 1 }, -- 440668: the ID the Cooldown Manager links
    shieldsworn_block = { id = 1328551, duration = 6, max_stack = 1 },

    -- The Paladin auras (B6, one up at a time), Consecration's ranks (B7: wowsims registers each rank's dot; the Cooldown
    -- Manager's item links the five and 1280345-1280349 as a self aura: needs in-game check which unit shows it), the
    -- Holy-only auras (B8, Holy is unsupported) and the blessings (item 200215 etc.: our own casts, no priority reads them).
    devotion_aura = { id = 465, copy = { 10290, 643, 10291, 1032, 10292, 10293 }, duration = 3600, max_stack = 1 },
    concentration_aura = { id = 19746, duration = 3600, max_stack = 1 },
    fire_resistance_aura = { id = 19891, copy = { 19899, 19900 }, duration = 3600, max_stack = 1 },
    frost_resistance_aura = { id = 19888, copy = { 19897, 19898 }, duration = 3600, max_stack = 1 },
    shadow_resistance_aura = { id = 19876, copy = { 19895, 19896 }, duration = 3600, max_stack = 1 },
    consecration = {
        id = 26573,
        copy = { 20116, 20922, 20923, 20924, 1280345, 1280346, 1280347, 1280348, 1280349 },
        duration = 8,
        max_stack = 1,
    },
    infusion_of_light = { id = 437063, duration = 15, max_stack = 1 },
    lights_vigil = { id = 1310909, copy = { 1311593, 1311597 }, duration = 30, max_stack = 1 },
    lights_vigil_target = { id = 1310910, copy = { 1311594, 1311599 }, duration = 30, max_stack = 1 },
    oath_of_light = { id = 1328548, duration = 300, max_stack = 1 },
    blessing_of_might = {
        id = 19740,
        copy = { 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 },
        duration = 300,
        max_stack = 1,
    },
    blessing_of_kings = { id = 20217, copy = { 25898 }, duration = 300, max_stack = 1 },
    blessing_of_wisdom = {
        id = 19742,
        copy = { 19850, 19852, 19853, 19854, 25290, 25894, 25918 },
        duration = 300,
        max_stack = 1,
    },
    blessing_of_salvation = { id = 1038, copy = { 25895 }, duration = 300, max_stack = 1 },
    blessing_of_light = { id = 19977, copy = { 19978, 19979, 25890 }, duration = 300, max_stack = 1 },
    -- The auras the abilities above apply, under the spell IDs the Cooldown Manager links (cdm/paladin.lua). One aura
    -- a Cooldown Manager item: Divine Shield's and Divine Protection's invulnerability is one (the item links both).
    hammer_of_justice = { id = 1324513, copy = { 1324515, 1324516, 1324517 }, duration = 6, max_stack = 1 },
    turn_undead = { id = 1324543, copy = { 1324545, 1324546 }, duration = 20, max_stack = 1 },
    repentance = { id = 1324538, duration = 6, max_stack = 1 },
    blessing_of_freedom = { id = 1044, duration = 10, max_stack = 1 },
    blessing_of_sacrifice = { id = 6940, copy = { 20729 }, duration = 30, max_stack = 1 },
    blessing_of_protection = { id = 1022, copy = { 5599, 10278 }, duration = 10, max_stack = 1 },
    divine_shield = { id = 642, copy = { 1020, 498, 5573 }, duration = 12, max_stack = 1 },
    voice_of_truth = { id = 1310897, duration = 6, max_stack = 1 },
    -- Librams (item_librams.go; item-level, external: the walk reads them where plain).
    holy_alacrity = { id = 449982, duration = 10, max_stack = 1 },
    tenets_of_the_silver_hand = { id = 1302545, duration = 3600, max_stack = 1 },
})

-- Purifying Power's cooldown cut by rank (429144's second curve {-17, -33} %): Exorcism and Holy Wrath.
local PURIFYING_POWER_CD = { [0] = 0, 0.17, 0.33 }

-- Any seal up: Judgement's requirement.
-- Sanctified Judgement (1311074, Forever-only, 3 ranks: a 33/66/100% chance to return 20/40/60%): 60% of the seal's
-- base cost x (2 - its cost multiplier) at 3/3 (tests/Forever/wowsims/paladin_retribution.log:439, Seal of Command
-- up: "Gained 161.280 mana from {SpellID: 1311074}" = 210 x 1.28 x 0.6); below 3/3 the belief and the forecast count
-- the mean (chance x refund), as the Rogue's Relentless Strikes.
-- The fourth field is the judgement debuff the seal puts on the target (none for Command and Righteousness: damage only).
local SEAL_BASE = {
    { "seal_of_command", SEAL_OF_COMMAND_COST, SEAL_OF_COMMAND },
    { "seal_of_righteousness", SEAL_OF_RIGHTEOUSNESS_COST, SEAL_OF_RIGHTEOUSNESS },
    { "seal_of_the_crusader", SEAL_OF_THE_CRUSADER_COST, SEAL_OF_THE_CRUSADER, "judgement_of_the_crusader" },
    { "seal_of_fury", SEAL_OF_FURY_COST, SEAL_OF_FURY, "judgement_of_fury" },
    { "seal_of_justice", SEAL_OF_JUSTICE_COST, SEAL_OF_JUSTICE, "judgement_of_justice" },
    { "seal_of_light", SEAL_OF_LIGHT_COST, SEAL_OF_LIGHT, "judgement_of_light" },
    { "seal_of_wisdom", SEAL_OF_WISDOM_COST, SEAL_OF_WISDOM, "judgement_of_wisdom" },
}
local SJ_CHANCE = { 0.33, 0.66, 1 }
local SJ_REFUND = { 0.2, 0.4, 0.6 }
-- A Judgement's cast effect, Judgement's and Swift Judgement's (the `now` and the `handler`, two closures so each gets
-- its own environment): the seal's judgement debuff, and the refund.
local function judgementCast()
    return function()
        for i = 1, #SEAL_BASE do
            local s = SEAL_BASE[i]
            if buff[s[1]].up then
                if s[4] then
                    applyDebuff("target", s[4])
                end
                local sj = talent.sanctified_judgement.rank
                if sj > 0 then
                    local mult = sealMult(talent)
                    local cost = byRank(s[2], s[3])
                    -- the mean: chance 33/66/100% x refund 20/40/60% (the talent's two curves, wowsims's spell data)
                    gain((cost < 1 and cost * BASE_MANA or cost) * (2 - mult) * SJ_CHANCE[sj] * SJ_REFUND[sj], "mana") -- Justice's is a fraction
                end
                return
            end
        end
    end
end

spec:RegisterStateExpr("seal_up", function()
    return buff.seal_of_command.up
        or buff.seal_of_righteousness.up
        or buff.seal_of_the_crusader.up
        or buff.seal_of_fury.up
        or buff.seal_of_justice.up
        or buff.seal_of_light.up
        or buff.seal_of_wisdom.up
end)

-- The time to the next main-hand swing (Hekili_Warrior/Warrior.lua's, after Hekili's Classic profile): the swing gap
-- Consecration and Exorcism wait for.
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

-- Unsealed Wrath's Echoes (wowsims talents_retribution.go applyUnsealedWrath): a landed melee hit stores a stack of the
-- active seal's Echo and spends the other Echoes (Seal of the Crusader has none: a hit under it changes nothing). The
-- reaction below runs it at our landed main-hand swing.
local ECHO_OF = {
    seal_of_command = "echo_of_command",
    seal_of_righteousness = "echo_of_righteousness",
    seal_of_fury = "echo_of_fury",
    seal_of_justice = "echo_of_justice",
    seal_of_light = "echo_of_light",
    seal_of_wisdom = "echo_of_wisdom",
}
local ECHOES = {
    "echo_of_command",
    "echo_of_righteousness",
    "echo_of_fury",
    "echo_of_justice",
    "echo_of_light",
    "echo_of_wisdom",
}
-- The Echoes at a landed main-hand swing, and only there (the Retribution log stores no Echo at a Holy Strike's hit,
-- 3.50 and 13.50). The core runs it as of the swing's time (a seal swapped before its row is not yet up).
-- Unsealed Wrath's proc cooldown, 0.1 s (1310735's ICDMs on 70938, hotfix push 114060; wowsims 8f7ad04996): every
-- proc refreshes the own Echo to its full 15 s, so one with more than 14.9 s left was stored under 0.1 s ago, and an
-- extra attack in that swing's instant (Windfury Totem's, an item's) neither stores nor spends.
-- shortcut: a proc under another seal inside those 0.1 s is not seen; upgrade if reactions get their own cooldown.
local ECHO_TIME, UNSEALED_WRATH_ICD = 15, 0.1
local function landing()
    if not talent.twist_of_light.enabled then
        return
    end
    local own
    for i = 1, #SEALS do
        if ECHO_OF[SEALS[i]] and buff[SEALS[i]].up then
            own = ECHO_OF[SEALS[i]]
        end
    end
    if not own or buff[own].remains > ECHO_TIME - UNSEALED_WRATH_ICD then
        return
    end
    for i = 1, #ECHOES do
        if ECHOES[i] == own then
            addStack(own)
        elseif buff[ECHOES[i]].up then
            removeBuff(ECHOES[i])
        end
    end
end
spec:RegisterReaction("unsealed_wrath", { who = "target", outcome = "land", hand = "main", now = landing })

-- A Holy Strike's effects, the `now` and the `handler` (two closures). A Shieldsworn Holy Strike with a shield restores
-- 4% of the maximum mana only when it lands (the Shield Specialization trigger, wowsims talents_protection.go:137-174: its
-- chance is 100% at rank 2 only; 105 at 2627 in the Protection log, none on the log's misses and dodges) and grants the
-- spell block for 6 s on every strike, avoided too (wowsims 61607b27d7); under Righteous Fury it grants Iron Creed's 6 s. `landed` (the `handler`'s: the simulation's
-- forecast) adds the mana. The belief's `now` does not: an avoid undoes only a target aura (Families/Now.lua), so a
-- gain at the cast would stay on a miss and promote a cast we cannot afford; its `onLand` (audit C10, run at a paid
-- wound or crit) adds the mana. Live that is idle until target rows are plain again (gaps.md).
local function holyStruck(landed)
    return function()
        if talent.shieldsworn.enabled and equipped.shield then
            if landed and talent.shield_specialization.rank >= 2 then
                gain(0.04 * mana.max, "mana")
            end
            applyBuff("shieldsworn_block")
        end
        if talent.iron_creed.enabled and buff.righteous_fury.up then
            applyBuff("iron_creed")
        end
    end
end

-- Holy Strike's landed hit (`onLand`): Shieldsworn's mana only (the cast's `now` has the auras).
local function holyLanded()
    return function()
        if talent.shieldsworn.enabled and equipped.shield and talent.shield_specialization.rank >= 2 then
            gain(0.04 * mana.max, "mana")
        end
    end
end

-- Forbearance's length: 60 s, 5 s shorter a rank of Sacred Duty (wowsims forbearance.go) and 10 s shorter under the
-- Justice Battleplate 5-piece (1301697); given the caller's `talent` and `set_bonus` (a cost or effect function runs in
-- the state's environment, this helper in the file's).
local function forbearanceTime(t, sb)
    return 60 - 5 * t.sacred_duty.rank - (sb.justice_battleplate_5pc > 0 and 10 or 0)
end

-- Templar's Bulwark's effects (the `now` and the `handler`): the absorb, and Forbearance.
local function templarsBulwark()
    return function()
        applyBuff("templars_bulwark")
        applyBuff("forbearance", forbearanceTime(talent, set_bonus))
    end
end

-- The coverage abilities' shared pieces (each returns a function that runs in the state's environment).
local function plainCost(costs, ids)
    return function()
        return byRank(costs, ids)
    end
end
local function benedictionCost(costs, ids)
    return function()
        return byRank(costs, ids) * (1 - 0.02 * talent.benediction.rank)
    end
end
-- Purifying Power (429144): -10% a rank on Cleanse and Purify, 8% of base mana.
local function cleanseCost()
    return function()
        return 0.08 * (1 - 0.1 * talent.purifying_power.rank) * (1 - 0.02 * talent.benediction.rank)
    end
end
local function spendsFavor()
    return function()
        removeBuff("divine_favor")
    end
end
local function drainsMana()
    return function()
        spend(mana.current, "mana")
    end
end
local function stuns(key)
    return function()
        applyDebuff("target", key)
    end
end
-- A shield: the invulnerability (one aura for both shields: the Cooldown Manager's item links both) and Forbearance.
-- Both shields share Category 37 (pin: 300 s, Sacred Duty -30 s a rank), so a press starts the other's cooldown.
local function shielded(ids, short, long, other)
    return function()
        applyBuff("divine_shield", knownRank(ids) >= 2 and long or short)
        applyBuff("forbearance", forbearanceTime(talent, set_bonus))
        setCooldown(other, 300 - 30 * talent.sacred_duty.rank)
    end
end

spec:RegisterAbilities({
    seal_of_command = seal("seal_of_command", SEAL_OF_COMMAND, SEAL_OF_COMMAND_COST),
    seal_of_righteousness = seal("seal_of_righteousness", SEAL_OF_RIGHTEOUSNESS, SEAL_OF_RIGHTEOUSNESS_COST),
    seal_of_the_crusader = seal("seal_of_the_crusader", SEAL_OF_THE_CRUSADER, SEAL_OF_THE_CRUSADER_COST),
    seal_of_fury = seal("seal_of_fury", SEAL_OF_FURY, SEAL_OF_FURY_COST),
    seal_of_justice = seal("seal_of_justice", SEAL_OF_JUSTICE, SEAL_OF_JUSTICE_COST),
    seal_of_light = seal("seal_of_light", SEAL_OF_LIGHT, SEAL_OF_LIGHT_COST),
    seal_of_wisdom = seal("seal_of_wisdom", SEAL_OF_WISDOM, SEAL_OF_WISDOM_COST),

    -- Unleashes the seal up (it stays up: wowsims judgement.go, the DB2 tooltip).
    judgement = {
        id = 20271,
        cast = 0,
        -- Improved Judgement (25956, Forever DB2: aura 107 misc 11, -1000 ms a rank): 1 s shorter a rank; the Justice
        -- Battlegear 5-piece (1301702): 0.5 s shorter
        cooldown = function()
            return 10 - talent.improved_judgement.rank - (set_bonus.justice_battlegear_5pc > 0 and 0.5 or 0)
        end,
        gcd = "off",

        spend = function()
            return 0.06 * (1 - 0.02 * talent.benediction.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 20271 }),
        ladder = false, -- also needs a seal: a short answer may be the seal (C9)

        usable = function()
            return seal_up, "requires a seal"
        end,

        now = judgementCast(),
        handler = judgementCast(),
    },

    -- Forever-only (talent; hotfix 113554, wowsims swift_judgement.go): a second Judgement on its own 60 s cooldown,
    -- free, off the GCD, no reset of Judgement's.
    swift_judgement = {
        id = 1310994,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        startsCombat = true,
        known = knows({ 1310994 }),

        usable = function()
            return seal_up, "requires a seal"
        end,

        now = judgementCast(),
        handler = judgementCast(),
    },

    -- Only at or below 20% of the target's health: the belief's target health reads the usability answer. Champion of
    -- the Light (1311084, 5 ranks; hotfix 113554, wowsims applyChampionOfTheLight): its cast 0.2 s shorter a rank.
    hammer_of_wrath = {
        id = 24275,
        expects = "travel",
        velocity = 35,
        school = "holy",
        copy = rest(HAMMER_OF_WRATH),
        cast = function()
            return max(0, 1 - 0.2 * talent.champion_of_the_light.rank)
        end,
        cooldown = 6,
        gcd = "totem",

        spend = function() -- Holy Conduit only (Benediction's mask leaves it out)
            return byRank(HAMMER_OF_WRATH_COST, HAMMER_OF_WRATH) * (1 - 0.2 * talent.holy_conduit.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(HAMMER_OF_WRATH),
        healthGate = 0.2,

        usable = function()
            return reactive(HAMMER_OF_WRATH), "requires target health under 20 percent"
        end,
    },

    holy_strike = {
        id = 679,
        copy = rest(HOLY_STRIKE),
        cast = 0,
        cooldown = function() -- Shieldsworn (1328544; hotfix 113554, wowsims holy_strike.go): 4 s off
            return talent.shieldsworn.enabled and 6 or 10
        end,
        gcd = "spell",

        spend = function()
            return byRank(HOLY_STRIKE_COST, HOLY_STRIKE) * (1 - 0.02 * talent.benediction.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(HOLY_STRIKE),

        now = holyStruck(),
        handler = holyStruck(true),
        onLand = holyLanded(),
    },

    consecration = {
        id = 26573,
        copy = rest(CONSECRATION),
        cast = 0,
        cooldown = 8,
        gcd = "spell",

        spend = conduitCost(CONSECRATION_COST, CONSECRATION),
        spendType = "mana",

        startsCombat = true,
        known = knows(CONSECRATION),

        now = function()
            applyDebuff("target", "consecrated_ground")
        end,

        handler = function()
            applyDebuff("target", "consecrated_ground")
        end,
    },

    exorcism = {
        id = 879,
        copy = rest(EXORCISM),
        cast = 0,
        cooldown = function() -- Purifying Power (429144): -17/-33% (the pin's curve; mask 1:2097152, 2:1073750016)
            return 15 * (1 - PURIFYING_POWER_CD[talent.purifying_power.rank])
        end,
        gcd = "spell",

        spend = conduitCost(EXORCISM_COST, EXORCISM),
        spendType = "mana",

        startsCombat = true,
        known = knows(EXORCISM),

        -- The 879 ranks (Holy) hit only an Undead or Demon target (the DB2 tooltip; wowsims casts none at its
        -- Mechanical target); the 415068 ranks any target, still a living attackable one (L1160).
        usable_on = function()
            if knownRank(EXORCISM) < EXORCISM_ANY then
                return UNDEAD_DEMON
            end
            return ANY_TYPE
        end,
    },

    holy_shock = {
        id = 1311606,
        copy = rest(HOLY_SHOCK),
        cast = 0,
        cooldown = function() -- the Justice Armor 5-piece (1301694): 1 s shorter
            return set_bonus.justice_armor_5pc > 0 and 9 or 10
        end,
        gcd = "spell",

        spend = function()
            return byRank(HOLY_SHOCK_COST, HOLY_SHOCK) * (1 - 0.02 * talent.benediction.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(HOLY_SHOCK),

        now = function()
            removeBuff("divine_favor")
        end,

        handler = function()
            removeBuff("divine_favor")
        end,
    },

    divine_favor = selfBuff("divine_favor", { 20216 }, {
        cooldown = 120,
        gcd = "off",
        spend = 0.04,
        spendType = "mana",
        toggle = "cooldowns",
    }),

    holy_shield = {
        id = 20925,
        copy = rest(HOLY_SHIELD),
        cast = 0,
        cooldown = 10,
        gcd = "spell",

        spend = function()
            return byRank(HOLY_SHIELD_COST, HOLY_SHIELD) * (1 - 0.02 * talent.benediction.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(HOLY_SHIELD),

        now = function()
            applyBuff("holy_shield", nil, 4)
        end,

        handler = function()
            applyBuff("holy_shield", nil, 4)
        end,
    },

    -- Templar's Bulwark (talent 1311015; wowsims templars_bulwark.go, a major cooldown the default casts at the pull): an
    -- absorb of the maximum health for 8 s and Forbearance, 110 mana, 300 s less 30 s a rank of Sacred Duty; refused
    -- under Forbearance.
    templars_bulwark = {
        id = 1311015,
        cast = 0,
        cooldown = function()
            return 300 - 30 * talent.sacred_duty.rank
        end,
        gcd = "off",

        spend = function() -- Benediction's mask names Bulwark (2:2097152)
            return 110 * (1 - 0.02 * talent.benediction.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        toggle = "cooldowns",
        known = knows({ 1311015 }),

        usable = function()
            return not buff.forbearance.up, "forbearance"
        end,

        now = templarsBulwark(),
        handler = templarsBulwark(),
    },

    -- Lane A (coverage): the heals, the blessings and shields, and the utility spells a Paladin presses (a manual press
    -- costs what it costs and starts its cooldown). Values: the pin's rows; Benediction's mask (20101) takes the stuns,
    -- cleanses, blessings, shields, Repentance and Templar's Bulwark, not the heals, Holy Wrath, Turn Undead or Light's Vigil.
    -- A heal or Holy Shock spends Divine Favor (its mask 0:2149605376: Holy Light, Flash of Light, Holy Shock).
    holy_light = {
        id = 635,
        copy = rest(HOLY_LIGHT),
        cast = 2.5,
        cooldown = 0,
        gcd = "spell",

        spend = plainCost(HOLY_LIGHT_COST, HOLY_LIGHT),
        spendType = "mana",

        startsCombat = false,
        known = knows(HOLY_LIGHT),

        now = spendsFavor(),
        handler = spendsFavor(),
    },

    flash_of_light = {
        id = 19750,
        copy = rest(FLASH_OF_LIGHT),
        cast = 1.5,
        cooldown = 0,
        gcd = "spell",

        spend = plainCost(FLASH_OF_LIGHT_COST, FLASH_OF_LIGHT),
        spendType = "mana",

        startsCombat = false,
        known = knows(FLASH_OF_LIGHT),

        now = spendsFavor(),
        handler = spendsFavor(),
    },

    -- Heals for the maximum health and drains all the mana left (wowsims lay_on_hands.go); 20 min.
    lay_on_hands = {
        id = 633,
        copy = rest(LAY_ON_HANDS),
        cast = 0,
        cooldown = 1200,
        gcd = "spell",

        startsCombat = false,
        known = knows(LAY_ON_HANDS),

        now = drainsMana(),
        handler = drainsMana(),
    },

    -- Holy Conduit's cost cut and Purifying Power's cooldown cut (neither Benediction: not in its mask); Undead and Demons.
    holy_wrath = {
        id = 2812,
        copy = rest(HOLY_WRATH),
        cast = 2,
        cooldown = function()
            return 60 * (1 - PURIFYING_POWER_CD[talent.purifying_power.rank])
        end,
        gcd = "spell",

        spend = function()
            return byRank(HOLY_WRATH_COST, HOLY_WRATH) * (1 - 0.2 * talent.holy_conduit.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(HOLY_WRATH),

        usable_on = function()
            return UNDEAD_DEMON
        end,
        range = 20, -- the radius around the caster (the pin: RadiusMax 20); checked by the range filter
        -- Self-centred: its own range answer is nil on every target (L187). A known 879 Exorcism rank (the same two
        -- types) confirms the target's type while it reads secret; a 415068 rank hits any target, so it confirms none.
        rangeSpell = function()
            local r = knownRank(EXORCISM)
            if r > 0 and r < EXORCISM_ANY then
                return EXORCISM[r]
            end
        end,
    },

    -- Improved Hammer of Justice (20487): -5 s a rank.
    hammer_of_justice = {
        id = 853,
        copy = rest(HAMMER_OF_JUSTICE),
        cast = 0,
        cooldown = function()
            return 60 - 5 * talent.improved_hammer_of_justice.rank
        end,
        gcd = "spell",

        spend = benedictionCost(HAMMER_OF_JUSTICE_COST, HAMMER_OF_JUSTICE),
        spendType = "mana",

        startsCombat = true,
        known = knows(HAMMER_OF_JUSTICE),

        now = stuns("hammer_of_justice"),
        handler = stuns("hammer_of_justice"),
    },

    -- Purifying Power (429144): -10/-20% cost.
    cleanse = {
        id = 4987,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cleanseCost(),
        spendType = "mana",

        startsCombat = false,
        known = knows({ 4987 }),
    },

    purify = {
        id = 1152,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cleanseCost(),
        spendType = "mana",

        startsCombat = false,
        known = knows({ 1152 }),
    },

    -- Guardian's Favor (20174): Freedom lasts 3 s longer a rank, Protection's cooldown is 60 s shorter a rank.
    blessing_of_freedom = {
        id = 1044,
        cast = 0,
        cooldown = 20,
        gcd = "spell",

        spend = function()
            return 0.1 * (1 - 0.02 * talent.benediction.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows({ 1044 }),

        now = function()
            applyBuff("blessing_of_freedom", 10 + 3 * talent.guardians_favor.rank)
        end,
        handler = function()
            applyBuff("blessing_of_freedom", 10 + 3 * talent.guardians_favor.rank)
        end,
    },

    blessing_of_protection = {
        id = 1022,
        copy = rest(BLESSING_OF_PROTECTION),
        cast = 0,
        cooldown = function()
            return 300 - 60 * talent.guardians_favor.rank
        end,
        gcd = "spell",

        spend = benedictionCost(BLESSING_OF_PROTECTION_COST, BLESSING_OF_PROTECTION),
        spendType = "mana",

        startsCombat = false,
        known = knows(BLESSING_OF_PROTECTION),

        usable = function()
            return not buff.forbearance.up, "forbearance"
        end,

        now = function()
            applyBuff("blessing_of_protection")
            applyBuff("forbearance", forbearanceTime(talent, set_bonus))
        end,
        handler = function()
            applyBuff("blessing_of_protection")
            applyBuff("forbearance", forbearanceTime(talent, set_bonus))
        end,
    },

    blessing_of_sacrifice = {
        id = 6940,
        copy = rest(BLESSING_OF_SACRIFICE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = benedictionCost(BLESSING_OF_SACRIFICE_COST, BLESSING_OF_SACRIFICE),
        spendType = "mana",

        startsCombat = false,
        known = knows(BLESSING_OF_SACRIFICE),

        now = function()
            applyBuff("blessing_of_sacrifice")
        end,
        handler = function()
            applyBuff("blessing_of_sacrifice")
        end,
    },

    -- Sacred Duty (1224697): -30/-60 s on both shields' cooldown; both bring Forbearance and refuse under it.
    divine_shield = {
        id = 642,
        copy = rest(DIVINE_SHIELD),
        cast = 0,
        cooldown = function()
            return 300 - 30 * talent.sacred_duty.rank
        end,
        gcd = "spell",

        spend = benedictionCost(DIVINE_SHIELD_COST, DIVINE_SHIELD),
        spendType = "mana",

        startsCombat = false,
        known = knows(DIVINE_SHIELD),

        usable = function()
            return not buff.forbearance.up, "forbearance"
        end,

        now = shielded(DIVINE_SHIELD, 10, 12, "divine_protection"),
        handler = shielded(DIVINE_SHIELD, 10, 12, "divine_protection"),
    },

    divine_protection = {
        id = 498,
        copy = rest(DIVINE_PROTECTION),
        cast = 0,
        cooldown = function()
            return 300 - 30 * talent.sacred_duty.rank
        end,
        gcd = "spell",

        spend = benedictionCost(DIVINE_PROTECTION_COST, DIVINE_PROTECTION),
        spendType = "mana",

        startsCombat = false,
        known = knows(DIVINE_PROTECTION),

        usable = function()
            return not buff.forbearance.up, "forbearance"
        end,

        now = shielded(DIVINE_PROTECTION, 6, 8, "divine_shield"),
        handler = shielded(DIVINE_PROTECTION, 6, 8, "divine_shield"),
    },

    repentance = {
        id = 20066,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = function()
            return 60 * (1 - 0.02 * talent.benediction.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 20066 }),

        now = stuns("repentance"),
        handler = stuns("repentance"),
    },

    -- Turn Evil (1328370): -0.5/-1 s cast, -5/-10 s cooldown (its three ranks override these; same costs).
    turn_undead = {
        id = 2878,
        copy = rest(TURN_UNDEAD),
        cast = function()
            return 1.5 - 0.5 * talent.turn_evil.rank
        end,
        cooldown = function()
            return 30 - 5 * talent.turn_evil.rank
        end,
        gcd = "spell",

        spend = plainCost(TURN_UNDEAD_COST, TURN_UNDEAD),
        spendType = "mana",

        startsCombat = true,
        known = knows(TURN_UNDEAD),

        now = stuns("turn_undead"),
        handler = stuns("turn_undead"),
    },

    divine_intervention = {
        id = 19752,
        cast = 0,
        cooldown = 3600,
        gcd = "spell",

        startsCombat = false,
        known = knows({ 19752 }),
    },

    -- The Holy talent (1310911): a 30 s buff on the target and the caster; its Holy Shock cooldown skip is unmodelled.
    lights_vigil = {
        id = 1310911,
        copy = rest(LIGHTS_VIGIL),
        cast = 1.5,
        cooldown = 6,
        gcd = "spell",

        spend = plainCost(LIGHTS_VIGIL_COST, LIGHTS_VIGIL),
        spendType = "mana",

        startsCombat = false,
        known = knows(LIGHTS_VIGIL),

        now = function()
            applyBuff("lights_vigil")
        end,
        handler = function()
            applyBuff("lights_vigil")
        end,
    },

    oath_of_light = {
        id = 1328548,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 0.08,
        spendType = "mana",

        startsCombat = false,
        known = knows({ 1328548 }),

        now = function()
            applyBuff("oath_of_light")
        end,
        handler = function()
            applyBuff("oath_of_light")
        end,
    },

    -- Forever-only (level 20, 180 s): pushback and mechanic immunity for 6 s; no cost row.
    voice_of_truth = {
        id = 1310897,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        known = knows({ 1310897 }),

        now = function()
            applyBuff("voice_of_truth")
        end,
        handler = function()
            applyBuff("voice_of_truth")
        end,
    },

    righteous_fury = selfBuff("righteous_fury", RIGHTEOUS_FURY, {
        spend = function()
            return 0.3 * (1 - 0.02 * talent.benediction.rank)
        end,
        spendType = "mana",
    }),
    retribution_aura = selfBuff("retribution_aura", RETRIBUTION_AURA),
})

-- Retribution's opener (re-pin rulings R15/R16; wowsims's default.apl.json "Move to melee" group at e2842f0a78): the
-- sequences move1 (Judgement, then Seal of Command) and move2 (Judgement, then Seal of Righteousness), each run once a
-- fight, at the pull, as stepped windows over their casts (the pack's `# Window:` lines; move3 folds to never). Each
-- evaluator is its sequence's condition (the header's), in combat, before the fight's first main-hand swing: the
-- swing lands on arrival in melee, where wowsims's sequence completes, so the window closes there (`close_on_false`)
-- or at its last step. No aura shows this span. (Each evaluator runs in the belief's `now` context: written in each.)
spec:RegisterWindow("move1", {
    evaluator = function()
        return talent.seal_of_command.enabled and combat > 0 and lastSwing(1) < combat
    end,
    duration = "combat",
    close_on_false = true,
    steps = { "judgement", "seal_of_command" },
})
spec:RegisterWindow("move2", {
    evaluator = function()
        return (not talent.twist_of_light.enabled or not talent.seal_of_command.enabled)
            and combat > 0
            and lastSwing(1) < combat
    end,
    duration = "combat",
    close_on_false = true,
    steps = { "judgement", "seal_of_righteousness" },
})

-- Pack from the talents (Engine/Schema/Selectors.lua; after the Hekili classic branch's pack selectors), as wowsims's
-- own Retribution page picks its APL (ui/specs/paladin/retribution/spec.ts: `holyShock` talented, the Holy Shock list):
-- Retribution ahead with Holy Shock taken (wowsims's Holy Shock build is 23/0/28) runs Holy Shock (wowsims.com); any other
-- Retribution build runs the default, Retribution (wowsims.com). A Holy-dominant build stays on Holy.
spec:RegisterSelector(
    "holy_shock",
    { spec = "retribution", pack = "Holy Shock (wowsims.com)" },
    function(tab1, tab2, tab3)
        return tab3 > tab1 and tab3 > tab2 and talent.holy_shock.rank > 0
    end
)

-- The priorities, one a spec, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit
-- those (a wowsims.com pack: its recipe, tools/wowsims/specs/) and run it, never these blocks
-- (tests/Forever/paladin_spec.lua checks they match).
spec:RegisterPack(
    "Retribution (wowsims.com)",
    20261118000,
    [[Hekili:LR16VTTnq8)wYx8K3sLLDA7YcMcqgkgwg6ckM6NLmTeLnNLenePItam0F77OEz9I02XPjUPFjXMNUh)Uhu3DW2JT)QTLhIJTVBIXKpoE84lnmmST4pUcBBTc5Uenh(qeke(7)I5XKzjCcnkDQ2A6AgjKP7sdhkE0hdOipH4MLqc43gzpRxjZwHDTT(YnF(MpD7DxfVvK2wliEE4C(Wmxv67Q0P8f40PfNnYNgJVhhNo1d7Jsc4PtV5lFoDkCC60MsjHmsybSrRqbips0OAwWi0Qa2OcrOdFrheEWWZbLfJIybay8GptfkNWsNI88Or)e8HL4hz6Pt)eIJUQhJs7FU9RGqwW5RyxnA0CcFrYmbog16rhcYeSD0mdFdd879DV8cDW1gt9jbG)h5kSsM(QymW8me30ffe4KFStaHXpxeOmfhCpySoigJmpc75GsIrP)Dh()fZr9lbxeJVL7)lXBooehXReHefhsVh7WPoH4am(CIVP2z5pJ(cAWJomWtVeRVmIUoAtFuiroGJEoEyLIalSs7NNWWouFFN5UEMJZeFiIeTaf55eJfFK97MvNarzS37m0hpO9dDTjC6WbAC685byDHrle)aT1Kip66SdgRNSAtTVpb((WnkGJk0S5SwsEWzTfDDalGjHJdzDbmNeIbZ)012xGcdXXGr7SogXxCUp1nHveSkvtZhrxKRzASPtuQtKCYjCmRMmYW6XLzwAYvP(L1mUuAayd1PeJrEpQGNEzPWK06HOhCvHqqVZy4WtyhodJce5qWfzHGhmR4afiaaFnCFKGuaz(cUoocnla7nOGAl(QiF2SeF)oubROcoL0IfIfttyrygRmW0G7Mpby4GqYObUlT(dtdKhMUgceQqETsm1EannzGCJMm0375DtPlorKWCMsJyJuBixvy3f0UUqghAe5AZXd)XnpVHd5GI5Qt83OKFH)wzQDRmN2KhOG6XKfTlqTdRUzUwjZzzzMx8dysMKMabIy3CaK9sTVVmF8d0yxcl8K207)Y8jcBwDjG0xyTVxEKRJwVBRum5VtApkEHot1drp8Zt2oDH4)DN(WS2CwzhKP(mn0MsDqOlzseZsZcgd0XnoHH8WXBfzFuBiwrWOAsftfJy0iAgHFGVT6UB9C7KQo3I0DaNMwI6xV31wA9WduMYixN7h(NCi4FYXIFPVWRRf1ll7RVO8AIM3x0PZ8X6FaAxpcPVYL7eqHMrmoU(07zI4kUQtlNVAoS6xl38o6Af2NIaW26ECmdyT1gHexzZeloQrQaCWDzBNQiIz)h2w1YofelwiITvLrAB5gdJohtq2whvLRIuxBoy)TmmvA9GQr3IPwSzBLfDfWg0)fptoMdVKEhoM3VpoMNEzBx3tdMB4Kamxws3xUuPGQEMA26rw98elFux)KJOILt2hGQz(Q0HQMx26vA3svEvQt(EGBwN2t5WbLoECRkzNn21TZovT2PU3U9O5UdP6SArF1Dh7)k(EfqM8Y7DSDVNR179sJ5QyvlC1864pi5ULA6THV64s5pQRD6W036rAFPJyq44JschDELATQUxVDhEalp8jU9qHp5xLw5UZfijBPHVGBn8B3AdFZL)VFnqE5tpDyhRE7yxO4R0gf35kf)MTtX3(zGY7r)UFtEdfNU4szZX1NixGWXgV5Gy1itc4jFmKN4cm39nytYuS8zWF(2Q5(MlpjF6SQFyfQg4uPRvCE3LN23mw7L4KS90CRvgrf2EF7vTHNx12xl0A96d1JXEkof(w)EDC0kpqsuuHJT9oW76u7zl52fbsucFbfId)fEjjGKov7pl(5eLr2()p]]
)
spec:RegisterPack(
    "Protection (wowsims.com)",
    20261118000,
    [[Hekili:Lw13VTjmq4)w6lBjADaPTRRlA5HovnTo1vnj2Zgm4JGxCWi)JLfPk(BFNjjuGazvQVK6E339DNV7ZhKzKFrczudqE8IGlUE2Sz3eeeqcnBlbsyjnDfDjEOGUg)9NkPbsnCzrv8KnYnA(ATxQC9uhYTcjL5ylXYfM7lijdsSUesrMU9HBV7(hNx2WijmNZyWUWaD6jY28QytoufV3MFMub)buvXmiJAfMQ4B)5dvXO5Q4oKy5(U0R9lPckJx4)C69PLcT)Ec8W)XdPwm9CmvkAHwGxegEw6snxxftzmzXBXdRGTAVQ47Og68bkPj)4(FHKKBmL65((l5MCBI7w43d6uKtSYPjbzbbWvzP3CPh2wvYmUaB906Qu7vQam4eQzHIVm3asRokZQ2EopBXzj2SmVU29SLvF)OGF3cFfyu8eRZre1QOTiONNrPqdurKmlchgrPkRMYa1Z0mK32uTqBKfaE7x3yc50aRlfuLokXk2qvRo3QbKLSOLPSfZAJ83w2synuyghIEdpZencqxLo5SDG9AW4TQqUP4PuPuWWdTCOG1uEH(ZlMmGtg2NCe9(GPt7ub7Bc1JOmzQvV4I6e3PfvpOoWV73CAblAVH3C2XyTLDYsk(hiDxf02EUuSnsNltxT7YAOcxX2ahyrlvsBbZdkOjcG9edQt2ai6LY9uZbb7W96y3OoAf02m8xPkLRXjoje18A37(URheCTrxVtA3tr84J17O2xHKVC4TaUk5GaIyqw6bQ1S2Xqtq9fyUyV8fgBZ82f0vVWG6jcjHPkUbuCkjCu53Rs)5kUp0R4ALZxTYR1vRLhsyTmWniW8F9iJS2kvhUpocUNvUD7x)Ff8PLWUCEZPZPts39Y8PtgqTi3bBwWi4oO6joDtyZg0tjT7UeVDpyKL8d9eOHSEl0hGUJx5p07I(Z92R2pM0r(aqDxa7duRjxIH9nyfxWXVu(19FiS2n5Fp]]
)
spec:RegisterPack(
    "Holy Shock (wowsims.com)",
    20261118000,
    [[Hekili:9AvyVTTnq0Fl9lDwyUsYPTzbbvdifbdjdzbbq5ZsIM8KfNPfniPINbc0V9D0YwMYww1biTiajm3D89osE37uYKKNtIzedK84fHxC5KjtUkmmmj2SEjKeVKqNtMHlkjlWFFNuSUolUqsNxNnALCLMVq7tLl8SHUwijmlCtR4cZ9Ljt7fz9sGMe)0npCZT3)41kWO4tRmCzzsCbNXGM9bA6q8DDDMPaQZ2AlixQGxavDgdYjvctD2np9qDgAUoRlkv8aBgOdwseegVmWjdcilf6Gcm(uTnCF8)9r8fEJr(uKsTappmCT0YpxxNrymz5VHlMdR1(1z3smKR7jVg9p3)mcsHXSuFDqWmUPOAQ9OeCqOEiMy6tMgMhgcFjNE1N9XBxLmNlWNac1MOA)Lka38uIjIseI0gZPcU2m2(wfzn8cMSPeTMpReyPKkfP(VpA))Euq)iqjAZ(D)VvSzWcO00cruRPXvAivMNNoJYIM0gGfz8pavrS))4CjTshDrh)NMzniakEzJliIX88OrJAc03AaPlvXNvyazLUe0A)5LYvLF8dtRYZprevl9ED0Op8Jr51barbli8s93IMe69XZcS2GCVm26JkLcgUORVTC8NrdIoEz79wtbNs7dsahp)SPhB3Md9ZFJR3qc455wo5aIRzg)fEjKMtErQ6wRUPU6nE5qyR7H0nQlUwjlwakBwVcFvl2w83q4o(6gIVTSpk8v7zVGuYs3Dn0Aa1Ta2Nc9VOd)W)jvuUEX(E7(79JCe62yWMln9lh6bBv2J2j0bI29QG6WPuvLMWa1Ei7Z7XW2PjpQ3359YgjXO8Og38bduSchA7CNJHeT(4MjCqjzQayjFFNckohQp2sI3qhYqIb)jE74K(WXPqY6Sf32BiC)im9tUB)EhoF8ZhSdQIBafNKe)UiaEMkGVVsGdQb(RseCavWFnYGdPd(oie6uCDWu1MwK0MVHRNMeSQ7lNOo1jBSH91ZShWvXTtj8B9jWk2Aj(YbZpBW2O(Jt37mSM7zj66WAxuABGNytIRorQUtNUryP97VgsIAWhY(v5hu05hwxCSmFt2EkNNH8Q7aa3xKbht0W6joHdq6HdYoMWEg1LS9qsQmf2Y17G5Cbh)K9)A7xKVXDY)d]]
)

-- The hand-built lists the wowsims.com priorities replaced: a saved choice of one falls back to its spec's default.
spec:RetirePacks({ "Protection", "Retribution" })
