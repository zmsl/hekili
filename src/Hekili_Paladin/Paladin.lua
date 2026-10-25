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
local HOLY_SHIELD = { 20925, 20927, 20928 }
local HOLY_SHIELD_COST = { 150, 195, 240 }
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

-- The seals, and the Echo Twist of Light leaves when each is replaced (Seal of the Crusader leaves none).
local SEALS = { "seal_of_command", "seal_of_righteousness", "seal_of_the_crusader", "seal_of_fury" }
local ECHO = {
    seal_of_command = "echo_of_command",
    seal_of_righteousness = "echo_of_righteousness",
    seal_of_fury = "echo_of_fury",
}
local ECHOES = { "echo_of_command", "echo_of_righteousness", "echo_of_fury" }

-- A seal cast's effect (the `now` and the `handler`, two closures so each gets its own environment): the other seal up
-- goes down, leaving its Echo with Twist of Light (one Echo at a time); the seal's own Echo goes down with it up.
local function sealCast(key)
    return function()
        for i = 1, #SEALS do
            local other = SEALS[i]
            if other ~= key and buff[other].up then
                removeBuff(other)
                local echo = ECHO[other]
                if echo and talent.twist_of_light.enabled then
                    for k = 1, #ECHOES do
                        if ECHOES[k] ~= echo and buff[ECHOES[k]].up then
                            removeBuff(ECHOES[k])
                        end
                    end
                    applyBuff(echo)
                end
            end
        end
        local own = ECHO[key]
        if own and buff[own].up then
            removeBuff(own)
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

-- Twist of Light (1310735 aura 108 base -20): seals cost 20% less. The seals' multiplier, given the caller's `talent`
-- (the state's: a cost function runs in the state's environment, this helper in the file's).
local function sealMult(t)
    return (1 - 0.2 * t.twist_of_light.rank) * (1 - 0.02 * t.benediction.rank)
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
-- the in-combat calibration replace. UNMEASURED: a level 60 Paladin's spirit regen ((spirit / 5 + 15) per 2 s tick at
-- about 100 spirit) and a little mp5 from gear.
spec:RegisterResource(Enum.PowerType.Mana, nil, nil, {
    fsr = { spirit = 17, mp5 = 2 },
    base = 1512, -- a fraction cost is of base mana (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
})

-- Talents: { talent tree (1 Holy, 2 Protection, 3 Retribution: the dominant tree picks the spec), rank 1's spell, max
-- rank }: the DB2's 44 nodes (`wowdb talents PALADIN`; the tree is the DB2's Talent.TabID), keys the snake_case names
-- (Holy Power is holy_power_talent; a nameless node talent_<spell>), and the Forever-only ones by spell at tree 0
-- until the live export places them.
spec:RegisterTalents({
    -- Holy (tree 1)
    divine_strength = { 1, 20262, 5 },
    divine_intellect = { 1, 20257, 5 },
    spiritual_focus = { 1, 20205, 5 },
    improved_seals = { 1, 20224, 5 },
    healing_light = { 1, 20237, 3 },
    consecration = { 1, 26573, 1 },
    talent_20234 = { 1, 20234, 2 },
    unyielding_faith = { 1, 9453, 2 },
    illumination = { 1, 20210, 5 },
    improved_blessing_of_wisdom = { 1, 20244, 2 },
    divine_favor = { 1, 20216, 1 },
    lasting_judgement = { 1, 20359, 3 },
    holy_power_talent = { 1, 5923, 5 },
    holy_shock = { 1, 20473, 1 },
    -- Protection (tree 2)
    improved_devotion_aura = { 2, 20138, 5 },
    redoubt = { 2, 20127, 5 },
    precision = { 2, 20189, 3 },
    guardians_favor = { 2, 20174, 2 },
    toughness = { 2, 20143, 5 },
    blessing_of_kings = { 2, 20217, 1 },
    improved_righteous_fury = { 2, 20468, 3 },
    shield_specialization = { 2, 20148, 3 },
    anticipation = { 2, 20096, 5 },
    improved_hammer_of_justice = { 2, 20487, 3 },
    improved_concentration_aura = { 2, 20254, 3 },
    talent_20911 = { 2, 20911, 1 },
    reckoning = { 2, 20177, 5 },
    one_handed_weapon_specialization = { 2, 20196, 5 },
    holy_shield = { 2, 20925, 1 },
    -- Retribution (tree 3)
    improved_blessing_of_might = { 3, 20042, 5 },
    benediction = { 3, 20101, 5 },
    improved_judgement = { 3, 25956, 2 },
    improved_seal_of_the_crusader = { 3, 20335, 3 },
    deflection = { 3, 20060, 5 },
    vindication = { 3, 9452, 3 },
    conviction = { 3, 20117, 5 },
    seal_of_command = { 3, 20375, 1 },
    pursuit_of_justice = { 3, 26022, 2 },
    eye_for_an_eye = { 3, 9799, 2 },
    improved_retribution_aura = { 3, 20091, 2 },
    two_handed_weapon_specialization = { 3, 20111, 3 },
    sanctity_aura = { 3, 20218, 1 },
    vengeance = { 3, 20049, 5 },
    repentance = { 3, 20066, 1 },
    -- Forever-only (tree unknown until the export)
    twist_of_light = { 0, 1310735, 1 },
    swift_judgement = { 0, 1310994, 1 },
    instrument_of_law = { 0, 1311085, 1 },
    holy_conduit = { 0, 1237268, 2 },
    sanctified_judgement = { 0, 1311074, 3 },
})

spec:RegisterAuras({
    seal_of_command = { id = 20375, copy = rest(SEAL_OF_COMMAND), duration = 30, max_stack = 1 },
    seal_of_righteousness = { id = 20154, copy = rest(SEAL_OF_RIGHTEOUSNESS), duration = 30, max_stack = 1 },
    seal_of_the_crusader = { id = 21082, copy = rest(SEAL_OF_THE_CRUSADER), duration = 30, max_stack = 1 },
    seal_of_fury = { id = 1311649, copy = rest(SEAL_OF_FURY), duration = 30, max_stack = 1 },
    -- Twist of Light's Echoes (DB2: until spent, 1 charge): our next landed melee attack spends it. The belief holds it
    -- from the replacing seal's cast until the player aura read drops it (secrecy unprobed: checkpoint).
    echo_of_command = { id = 1311703, duration = 3600, max_stack = 1 },
    echo_of_righteousness = { id = 1311704, duration = 3600, max_stack = 1 },
    echo_of_fury = { id = 1311701, duration = 3600, max_stack = 1 },
    -- Holy Shield: +30% block for 10 s, 4 charges (DB2 ProcCharges), each block or partial block on us spending one.
    holy_shield = {
        id = 20925,
        copy = rest(HOLY_SHIELD),
        duration = 10,
        max_stack = 4,
        consumedBy = { BLOCK = true, BLOCKED = true },
    },
    -- Swift Judgement's charge (1310994, until spent): the next Judgement costs nothing.
    swift_judgement = { id = 1310994, duration = 3600, max_stack = 1 },
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
-- Judgement's cast effect (the `now` and the `handler`, two closures so each gets its own environment): Swift
-- Judgement's charge goes; the refund.
local function judgementCast()
    return function()
        removeBuff("swift_judgement")
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

    -- Unleashes the seal up (it stays up: wowsims judgement.go, the DB2 tooltip); Swift Judgement's charge pays it.
    judgement = {
        id = 20271,
        cast = 0,
        -- Improved Judgement (25956, Forever DB2: aura 107 misc 11, -1000 ms a rank): 1 s shorter a rank
        cooldown = function()
            return 10 - talent.improved_judgement.rank
        end,
        gcd = "off",

        spend = function()
            return buff.swift_judgement.up and 0 or 0.06 * (1 - 0.02 * talent.benediction.rank)
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

    -- Forever-only (talent): finishes Judgement's cooldown, the next Judgement free.
    swift_judgement = {
        id = 1310994,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        startsCombat = false,
        known = knows({ 1310994 }),

        now = function()
            setCooldown("judgement", 0)
            applyBuff("swift_judgement")
        end,

        handler = function()
            setCooldown("judgement", 0)
            applyBuff("swift_judgement")
        end,
    },

    -- Only at or below 20% of the target's health: the belief's target health reads the usability answer. Instrument
    -- of Law (1311085 aura 107 base -1000): its cast 1 s shorter a rank.
    hammer_of_wrath = {
        id = 24275,
        expects = "travel",
        velocity = 35,
        school = "holy",
        copy = rest(HAMMER_OF_WRATH),
        cast = function()
            return max(0, 1 - talent.instrument_of_law.rank)
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
        cooldown = 10,
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

-- The priorities, one a spec, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit
-- those (a wowsims.com pack: its recipe, tools/wowsims/specs/) and run it, never these blocks
-- (tests/Forever/paladin_spec.lua checks they match).
spec:RegisterPack(
    "Retribution (wowsims.com)",
    20261021003,
    [[Hekili:TA1FVTjmq0pl7FYs0YmqsB3AuPsDQAADQlAAS)gWbBcUXGr2MLfPj(SVZ5heGest7MIueWD37E3Z2pzFh)F67rWAQ)0r2JUYXEKJT9yFp9QCQVxooAbEo8qgof()huTKnRqZezLH9xkwQyPkuKiDGj1vCbMyGBwbJRFiZF2rrwLtJ89((DpE39pmDICpK(EjmcHUPoQk6u9BszOoHwgU9BwXcj9xuzziHgJl46YW7((JLHWNldBIsbZYWaLvoMJjSmRAmWcNZvw6LmLoqehWzZt0i4BONuISbdHEkXzkomte4zHHdmvziMqezVfEybDLcvgEpwJNCeU1)Bp8taKeToxnXYAotNumZmowTsDaGjmcKXJVESnX(c7X2iqHLIyghwgWrgYQq5sku8mS2T2meGlK4HSy33mRiog1ocQiV8RhaW7CTuum3m0GSgejluycvUhMJfTouUfkAatttvdnpjIJdMhrCDQsa6WtfK50uAMU7usWPPuPPrlLyDYWyruHY1XWJ(BYc1kfuewPDT)t)umllbNrcGvxk59vVkPMhvdUXgnAqJEj4RcuG6SGAWxZsP3AJUSEk7MAqKsbSQthnMdtcQ1EfAgEgNs61FJQrJse1QheSEnLZ9bgCS(knGsffQmQs9Q7EduoKdTd3GjryopyZRqtu6HgJa3iiincKFZrQNnB6VfYiMk95v2rR3WD6HRlb8C1Vn9y7MP2WSitSmR3jKNT7MUz0f7pfTB(Qg01BxBVb8wh0L9GMGr5r6BDDS3RZO66zdXToNple99a7dLXmTPPRz1qz8MRJo8(01()B1w)pbXLWPyjd77Dg9BNvuly9wZAGb(A4N3oz5yTBx9v58cjW6gS1Z)y4xZPXeSQFv2vq9appVIQmWmfnUBH70ovNPv1(22cNk51XqJl6qqR5UvNB7C5mLEzNtWlYE5Cm32ZRwbBomx9)HrVudVdzxJuAYXp0HG327BZzUGnxCQXXdaKp(AaP6mcaW1DQuVs7ZNFfYCAEQJD3n(F3t9Cxi2ASuD9Lt5S0(cqnOCxxr6yUcTPw9RcDiODCHP1ehOoUqNiGY(cDbJZGRg(5T38BDy))c]]
)
spec:RegisterPack(
    "Protection (wowsims.com)",
    20261021000,
    [[Hekili:LsvtVPnqq0Fl5sBqfzBG00wu5qQIQAIsJIKZ51Ey3X4nS41A)OPCX)27SoaXyGOi1lMLzEZ7n(n7y2i2JSub4q29JtgF5OKXJsssyPU11ilTg4lHf0Hkyf98bJ2HCNux1KF(Z6NTYv2iUE1GaY1knicSn3lvUBQyZpkX2AKtmD1DxD9n3pTEhJS0sPqGVugA5VHAtBYDLyt(MyXfAd(h00KlWcWRCn5x9WDn5u4M89iXlJdYBJRbfiKvXVkFmuRSXBiiI(t0twD1GHKugOYQOxebDwhKwABYbHqx9r6WsCTnQj)AWbtpslD(VV5rIKsNR2onoEH0v6NhElI7bDaXj15Ijt(2KerYfjtsIiB1OlKkY6H2U0gvBqQ45GBMbDg5CFiCg4nWqzXSZM7lkI6NjYx3C7be8PzXweuz6ImYnZ4gVfeO5vAow2Uun7jVybUcRCd9wKqwKTGlMnAhGGcpllCzVhGBeRWBwpSqZ92zJdTY571kHS0R3kqwz)E4zjujY2e4dNDiwF9GUQWPFqUbAVp0jEPwToZwQ5lpsujQeBBPdttw9sSBy8VAdxAx1CllLMR2WD79xbusRZ2U39Y1n649T7HyfmxHc2pyPDmQqYnZFw6oRK5iwFNf1BkekDsVs5gPdnsGL()74DeUtgwARhg6As)l6P)2k6oHc4(8jW96elG6Y3gvycUV8F5nlODMgG91taB7mMf8Y0DRuhBqUTK(lLDT8tU2ESHCFVT765HKEIL42gNADW7k1uz)cxkvs6Zv)CZxJAtZ(3p]]
)

-- The hand-built lists the wowsims.com priorities replaced: a saved choice of one falls back to its spec's default.
spec:RetirePacks({ "Protection", "Retribution" })
