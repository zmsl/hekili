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
-- Unmodelled: the judgement debuffs on the target (no priority reads them), Seal of Fury's absorb, the seals' attack
-- speed and per-hit effects.
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
local EXORCISM_COST = { 85, 135, 180, 235, 285, 345, 85, 135, 180, 235, 285, 345 }
local HOLY_SHOCK = { 1311606, 20473, 20929, 20930 } -- rank 1 Forever-only
local HOLY_SHOCK_COST = { 160, 225, 275, 325 }
-- Four ranks, from the owner's in-game tooltips (2026-11-06; in game beats wowsims and the DB2): 100 / 150 / 195 / 240
-- mana, learned at 30 / 40 / 50 / 60. Rank 4 (1239570, build 70755) is in wowsims after our pin (041cd46cec); DB2
-- 70707's three-rank 150 / 195 / 240 ladder at 40 / 50 / 60 lacks it.
local HOLY_SHIELD = { 20925, 20927, 20928, 1239570 }
local HOLY_SHIELD_COST = { 100, 150, 195, 240 }
local RETRIBUTION_AURA = { 7294, 10298, 10299, 10300, 10301 }
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
-- hits, not the seal swap: the belief holds them from the aura read.
local SEALS = { "seal_of_command", "seal_of_righteousness", "seal_of_the_crusader", "seal_of_fury" }

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

-- The five-second rule (C3): spirit and mp5 regen per second, the declared starting point the out-of-combat read and
-- the in-combat calibration replace, as wowsims's logs measure them at 60: Retribution 13.65 spirit + 8.25 casting =
-- 21.9 outside (Reverence's share is inside the 8.25), Protection 0 while casting and 17.38 outside. Forever's Spirit regen is `6.25 + Spirit/8` a second for every class
-- (wowsims mana.go:75-76), not Classic's formula.
-- state.spec: the functions run in the state's environment (the file's `spec` is the class).
spec:RegisterResource(Enum.PowerType.Mana, nil, nil, {
    fsr = {
        spirit = function()
            return state.spec.retribution and 13.65 or 17.38
        end,
        mp5 = function()
            return state.spec.retribution and 8.25 or 0
        end,
    },
    base = 1512, -- a fraction cost is of base mana (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
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

spec:RegisterAuras({
    seal_of_command = { id = 20375, copy = rest(SEAL_OF_COMMAND), duration = 30, max_stack = 1 },
    seal_of_righteousness = { id = 20154, copy = rest(SEAL_OF_RIGHTEOUSNESS), duration = 30, max_stack = 1 },
    seal_of_the_crusader = { id = 21082, copy = rest(SEAL_OF_THE_CRUSADER), duration = 30, max_stack = 1 },
    seal_of_fury = { id = 1311649, copy = rest(SEAL_OF_FURY), duration = 30, max_stack = 1 },
    -- Unsealed Wrath's Echoes (hotfix 113554 rows: 15 s, 3 stacks): each landed melee hit stores a stack of the active
    -- seal's; a hit under another seal spends them. From the player aura read (secrecy unprobed: checkpoint).
    echo_of_command = { id = 1311703, duration = 15, max_stack = 3 },
    echo_of_righteousness = { id = 1311704, duration = 15, max_stack = 3 },
    echo_of_fury = { id = 1311701, duration = 15, max_stack = 3 },
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
})

-- Any seal up: Judgement's requirement.
-- Sanctified Judgement (1311074, Forever-only, 3 ranks: a 33/66/100% chance to return 20/40/60%): 60% of the seal's
-- base cost x (2 - its cost multiplier) at 3/3 (tests/Forever/wowsims/paladin_retribution.log:439, Seal of Command
-- up: "Gained 161.280 mana from {SpellID: 1311074}" = 210 x 1.28 x 0.6): the belief counts the refund only at 3/3,
-- a sure one.
local SEAL_BASE = {
    { "seal_of_command", SEAL_OF_COMMAND_COST, SEAL_OF_COMMAND },
    { "seal_of_righteousness", SEAL_OF_RIGHTEOUSNESS_COST, SEAL_OF_RIGHTEOUSNESS },
    { "seal_of_the_crusader", SEAL_OF_THE_CRUSADER_COST, SEAL_OF_THE_CRUSADER },
    { "seal_of_fury", SEAL_OF_FURY_COST, SEAL_OF_FURY },
}
-- A Judgement's cast effect, Judgement's and Swift Judgement's (the `now` and the `handler`, two closures so each gets
-- its own environment): the refund.
local function judgementCast()
    return function()
        if talent.sanctified_judgement.rank < 3 then
            return
        end
        for i = 1, #SEAL_BASE do
            local s = SEAL_BASE[i]
            if buff[s[1]].up then
                local mult = sealMult(talent)
                gain(byRank(s[2], s[3]) * (2 - mult) * 0.6, "mana")
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

spec:RegisterAbilities({
    seal_of_command = seal("seal_of_command", SEAL_OF_COMMAND, SEAL_OF_COMMAND_COST),
    seal_of_righteousness = seal("seal_of_righteousness", SEAL_OF_RIGHTEOUSNESS, SEAL_OF_RIGHTEOUSNESS_COST),
    seal_of_the_crusader = seal("seal_of_the_crusader", SEAL_OF_THE_CRUSADER, SEAL_OF_THE_CRUSADER_COST),
    seal_of_fury = seal("seal_of_fury", SEAL_OF_FURY, SEAL_OF_FURY_COST),

    -- Unleashes the seal up (it stays up: wowsims judgement.go, the DB2 tooltip).
    judgement = {
        id = 20271,
        cast = 0,
        -- Improved Judgement (25956, Forever DB2: aura 107 misc 11, -1000 ms a rank): 1 s shorter a rank
        cooldown = function()
            return 10 - talent.improved_judgement.rank
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
        cooldown = 15,
        gcd = "spell",

        spend = conduitCost(EXORCISM_COST, EXORCISM),
        spendType = "mana",

        startsCombat = true,
        known = knows(EXORCISM),

        -- The 879 ranks (Holy) hit only an Undead or Demon target (the DB2 tooltip; wowsims casts none at its
        -- Mechanical target); the 415068 ranks any target.
        usable_on = function()
            if knownRank(EXORCISM) < EXORCISM_ANY then
                return UNDEAD_DEMON
            end
        end,
    },

    holy_shock = {
        id = 1311606,
        copy = rest(HOLY_SHOCK),
        cast = 0,
        cooldown = 10,
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

-- The priorities, one a spec, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit
-- those (a wowsims.com pack: its recipe, tools/wowsims/specs/) and run it, never these blocks
-- (tests/Forever/paladin_spec.lua checks they match).
spec:RegisterPack(
    "Retribution (wowsims.com)",
    20261107001,
    [[Hekili:LR16VjUrq8)wYxOM2CgWxZD9IQJuQov1uDn6u99zBwSxWBX2lY76qIeY)T3z9l8RDbc5bxUVKa745XV5X6zgH9e7VzB5H4y7BngB8Hjtg)XXJNyBXFyf22AfYDjAb8Hiui83)fZJjZs4eAu6uT101msit3Lgou8OpeqrEcXnlHeWVjYEwVsMTc7AB91R)Y1F(MBVmERiTT8jEE4C(Wmxv67Y0PCFC60IZgnNgJVdhNo1dphLeWtNE9x)s6u440PnLsczKWcyJwHcqEKOr1SGrOvbSrfIqh(Ioi8GHNdklgfXcaW4bFMkuoHLof55rJ(j4dlXpW0tN(zehDzpgL2)CZ3aH4Z5RyxoA0cc3pzMahJA9Odbzc2o(c0NC9mqgEZD1bxBmDoja8)ixHvY0xfJbMNH4MUOGaN8JDcim(5IaLP4G7aJ1bXyKfryphusmk9V7W)VyoQFj4Iy8TC)FjElWH4iELiKO4q6Dyho1jehGXNtMBQDw(ZO7tdEWHbE6Ly9Lr01rB6JcjYbC0lWdRueyHvA)8eg2HoFUZcxpZjzIperI8rrEoXyXhz)Uz1jqug79UX6tg0(HUYeoD4anoDXIaSUWOfIFG2AsKhDD2bt0twTP23nGVpCJc4OcnBoRLKhCwBrxhWcys44qwxaZjHyW8pDTDFuyiogmAN1XiU)5ZPUjSIGvPAA(i6ICnZXB6eL6ejnoHJz1KrgwpUmZstUk1VSMXLsdaBOoLymY7bf80llfMKwpe9GRkec6DJho8e2HZWOaroeCrwi4bZkoqbcaWxd3hjifqw4Z1XrOzbyVbfuBXxf5ZMLmFEhQGvubNsAXcXIPjSimJvgyAWDZNamCqiz0a3Lw)HPbYdtxbbcviVwjMApGMMmqUrtg6798UP0fNisyotPrSrQnKRkSRpTRlKXHgrUYCYWFCZZB4qoOyU6e)nk5x4VvMA3kZPn5bkOEmzr7cu7WQBMRvYCwwM57)bmjtstGarSBoaYEP23xMp(EASlHfEsB69FzUHWMvxci9fw77Lh56O172kft(7K2JIxOZu9q09)SX2Ple)V70hM1MZk7Gm1NPH2uQdcDjtIywAwWyGoUXjmKhoERi7JAdXkcgvtQyQyeJgrZi898Tv3DRNBNu15wKUd400su)69U2sRhEGYug56C)WVXHGFJJf)sFHxxlQxw2xFr51enVVOtN5t0VaAxpcPVYL7eqHMrgFC9P3ZeXvCvNwoF1Cy1VwU5D01kSpfbGT1D4ygWARncjUYMjwCuJub4GBZ2ovreZ(pSTQLDkiwSqeBRkJ02YnggDoMGSToQkxfPU2CW(BzyQ06bvJUftTyZ2kl6kGnO)3)e5yo8s6D4y(19XX84lB76EAWCdNeG5Ys6(YLkfu1ZuZwpYQNhz5J66NCevSCY(aunZxLou18YwVs7wQYRsDY3dCZ60EkhoO0XJBvj7SXUUD2PQ1o192Thn3DivNvl6RU7y)xX3RaYKxEVJT79uTEVxAmxfRAHRMxhFHK7wQP3g(QJlL)OU2Pdtp3J0(shXGWXhKeo68k1AvDVE7o8awE4JC7HcFYhLw5UZfijBPHVGBn85BTHV5Y)3Vgi)ThF6Wow92XUqXxPnkUZvk(STtX3(zGY7r)2pjVHItxCPS546tKlq4KXV5Gy1itc4jFmKh5cm39nygzkw(m4pDB1CFZLnYNoR6hwHQbov6AfN3D5P9nJ1EjojBpn3ALruHT33EvB45vT91cTwV(q9ySNItHV1VxhhTYdKefv4yBVd8Uo1E2sUDrGeLW9PqC4VWljbK0PA)zXpNOmY2))d]]
)
spec:RegisterPack(
    "Protection (wowsims.com)",
    20261110000,
    [[Hekili:LwvxVPnmu0Fl9LnqRlPWw7wrJh6u106uxvLsF2jg7BiEyIJ8hJHuv(TVRdqAsiHnPYdG5(X5CVxFYnKjKNirCQfipm9IPxnzYKlWpKi72cGevqzROlXd50143pQvwGzfQ8YKrBuBmI1MaMA9yFKBLkk3J2cNqAVlNSOxGnfadr6M7V527EywrnIKOmbNd7sdmStW2SYeBguMS3wyQsd)g0LjCiL6K2YKBE8(Ye0CzslqCIqp9MWcQKYf5HVqFiTqAc3dqa(NaeA54ZrQ00CJeBeoEw5PwyktOCUk)T4HvWwtqzYTulDwpL0OFE3tiizwBHzwy4sHnZTW3fHDcDmIjw5WL0Rz8P0P8uwaow1QuHeh90QQ0euObm5fu7CTyzMfuotCQtV9Cr68Zw4stdABpWvu(JJs(DZd1Gvlw48oIPonTbaD8miegGkJvPX4Lrmt7muoOFbM(82eQ5gRkhWUFDTjeZF54lH1qU9CNbW0tJxY4ZN0meZgrQnEGa98p6SDbhuhtWQC1M8NzkLKJhA4qdRPICZxMpQhNCS79a9(lgpUvfSV1Qg8PkMZmFAfXTA8QX)b89FNrZ5X7n8MZoowxrlwy4paBxf00EMsUn2KPyR21SwQ0xS1Hd84LALlNha50fsG)mhQiRNi6q5EOfGKFOVo2nQowbnnd)rPzcdEpsIqLSX)0C7h6LcJ1uTPz3dy4XhQ28SVcjF9GchxqCqwqSikDcQXDThH6KQVZ8j9H)ZK6iKirmTWcAbLenOe6vPH8f3h7uCn48vREA0An8qIQUk9dtK)lhyS3uT5J7QbI7f1x751)wfEAzONZpDAo9YY2nZNpzcvcvFyxpqyheUeVSjQE12PuNT3U2CemW23(uX1G1ztBpWD8U4(u4DV2BUZ9yqhyZC1uaNduNntHP9DyLqkWxH9T9VHQYn5Vd]]
)

-- The hand-built lists the wowsims.com priorities replaced: a saved choice of one falls back to its spec's default.
spec:RetirePacks({ "Protection", "Retribution" })
