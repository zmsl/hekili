-- Hekili_Paladin/Paladin.lua
-- The Forever Paladin (one pseudo-spec, PALADIN_SPEC below; Retribution and Protection are talent builds, one pack
-- each): the Paladin kit with Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever
-- DB2 at build 1.60.1.70338, wowdb; a cost percentage there is a fraction of the believed maximum, as the Druid's),
-- the seals as player auras (one at a time: a seal's `now` takes the others down), Twist of Light's Echoes, Swift
-- Judgement, Holy Shield's charges spent by blocks on us (`consumedBy`), Hammer of Wrath through the target health
-- gate, mana under the five-second rule (`fsr`), and the default priorities (all provisional: no in-game check yet,
-- D5). Research: the class-completion research §3.
-- Judgement does not consume the seal (wowsims/forever judgement.go and the DB2 tooltip); the in-game checkpoint asks.
-- Talents: only those this file reads; a modifier is rank 1's value x the rank, floored at 0.
-- Unmodelled: the judgement debuffs on the target (no priority reads them), Seal of Fury's absorb, the seals' attack
-- speed and per-hit effects, Exorcism's Undead/Demon restriction (the 879 ranks; the 415068 ranks hit any target).
-- Credits: Hekili (registration API and pack format; `mainhand_remains` follows Hekili's Classic Warrior profile,
-- origin/classic:Classic/Warrior.lua, as Hekili_Warrior/Warrior.lua has it). wowsims/forever (MIT,
-- ui/specs/paladin/*/apls/*.apl.json and sim/paladin/) is the reference for the priorities and the seal, Echo,
-- Judgement and Holy Shield rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase, IsSpellUsable = Facade.UnitClassBase, Facade.C_Spell.IsSpellUsable

if UnitClassBase("player") ~= "PALADIN" then
    return
end

local state = Hekili.State
local max = math.max

-- The pseudo-spec the client reports for a Paladin (Constants.lua's row). A placeholder until the checkpoint reads it.
local PALADIN_SPEC = 1501

local spec = Hekili:NewSpecialization(PALADIN_SPEC, false, 135963) -- spell_holy_sealofmight
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

-- Twist of Light (1310735 aura 108 base -20): seals cost 20% less.
local function sealCost(costs, ids)
    return function()
        return byRank(costs, ids) * (1 - 0.2 * talent.twist_of_light.rank)
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
})

-- Talents: { node (unused on Forever), rank 1's spell, max rank } (`wowdb talents PALADIN`; Forever-only ones by
-- spell), only those this file reads, until the live export lists the tree.
spec:RegisterTalents({
    holy_shock = { 0, 20473, 1 },
    holy_shield = { 0, 20925, 1 },
    seal_of_command = { 0, 20375, 1 },
    -- Forever-only
    twist_of_light = { 0, 1310735, 1 },
    swift_judgement = { 0, 1310994, 1 },
    instrument_of_law = { 0, 1311085, 1 },
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
    -- Consecration's mark on the target (1310905): its 8 s and the area's 0.6 s tail (wowsims consecration.go),
    -- modelled from our cast (target auras are unreadable in combat).
    consecrated_ground = { id = 1310905, duration = 8.6, max_stack = 1 },
})

-- Any seal up: Judgement's requirement.
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
        cooldown = 10,
        gcd = "off",

        spend = function()
            return buff.swift_judgement.up and 0 or 0.06
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 20271 }),
        ladder = false, -- also needs a seal: a short answer may be the seal (C9)

        usable = function()
            return seal_up, "requires a seal"
        end,

        now = function()
            removeBuff("swift_judgement")
        end,

        handler = function()
            removeBuff("swift_judgement")
        end,
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
        copy = rest(HAMMER_OF_WRATH),
        cast = function()
            return max(0, 1 - talent.instrument_of_law.rank)
        end,
        cooldown = 6,
        gcd = "totem",

        spend = function()
            return byRank(HAMMER_OF_WRATH_COST, HAMMER_OF_WRATH)
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
            return byRank(HOLY_STRIKE_COST, HOLY_STRIKE)
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

        spend = function()
            return byRank(CONSECRATION_COST, CONSECRATION)
        end,
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

        spend = function()
            return byRank(EXORCISM_COST, EXORCISM)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(EXORCISM),
    },

    holy_shock = {
        id = 1311606,
        copy = rest(HOLY_SHOCK),
        cast = 0,
        cooldown = 10,
        gcd = "spell",

        spend = function()
            return byRank(HOLY_SHOCK_COST, HOLY_SHOCK)
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
            return byRank(HOLY_SHIELD_COST, HOLY_SHIELD)
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

    righteous_fury = selfBuff("righteous_fury", RIGHTEOUS_FURY, { spend = 0.3, spendType = "mana" }),
    retribution_aura = selfBuff("retribution_aura", RETRIBUTION_AURA),
})

-- The mana floors of Retribution's swing-gap fillers (D7: a fraction of the maximum, one setting a line; wowsims's 10%).
-- Mana is secret even out of combat, so Hekili reads the belief's lower bound against them (the in-game checkpoint).
spec:RegisterSetting("consecration_mana", 10, {
    type = "range",
    name = "Consecration Mana Floor",
    desc = "Consecration is used in the swing gap only while your mana is at least this percent of its maximum.",
    min = 0,
    max = 100,
    step = 1,
    width = "full",
})

spec:RegisterSetting("exorcism_mana", 10, {
    type = "range",
    name = "Exorcism Mana Floor",
    desc = "Exorcism is used in the swing gap only while your mana is at least this percent of its maximum.",
    min = 0,
    max = 100,
    step = 1,
    width = "full",
})

spec:RegisterOptions({ package = "Retribution" })

-- The two priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those
-- and run it, never these blocks (tests/Forever/paladin_spec.lua checks they match). Pick one with
-- /hekili priority <name>. Both are provisional (their descriptions say why).
spec:RegisterPack(
    "Retribution",
    20261019682,
    [[Hekili:TEvBVTTnq4Fl7lznyEQ2Elz9f4cSv0HUGIGIQcSVrjAQtwCrs0GKkU5l63(UJskMswY21BFXGM8UN7TNJhfBb7RSWeUfy3VC(YBxmFXRV9vlzH2N2cSWTCXd8n4IsEb(7xaRwUUYkvL0zpLR4jK(RRK52)QKTEuOmBbb7(f3mFblmtMKanccgbl8pvA4rqxh7bDD8N558ejU4fB1QhLgCtE(BQJlv1XYYFEd6m1XImq8qD8tG9T1X2mChdWZnZQJ)GitbM6yEzsD8DvjBGcO0(J4oqAkiS1XKrEwfuqnUSqLa55aQsQwvGYuHULGBSMRFJhmnkluQ8e1Us0AFKxuqrGkTo(V1CBg5JTWdFdevwCXozjkoAjuFRKeFbPQk)P64qmYFaM1QYx3jn2g0(KCtMTZhTn7)Iq3)OJFVQOWfIUF2V)xi1avLPemu6a4c0N2LbOxjTTIlTMMevB0tbZ1d9V3RknGaJjxvXP3h(MslKMcVG0Gb3M64n8T(6VKmPmNsS8sEDCoLjFlLjOmKtX2Wptr1rlphZUZA9m0BqvAIyEQLaCNANrwyEzAdLHkN9in)(N)efTAif0qPaOcv(txhGmvTkf9ewixqIAc2QbHQyn3UsVhHiELMptMU6hwxLMgm8KGQT13Daa)0QxsLNivAKOPC4qWT3Puq3RonMAR0vOXDRJOKXmQnCvgM2ImuwJuQjVfSFZaOKVM4XDOGM8F6yVZQmaA70OnIKvl8fjZrJj)AhrINLQevMbI4SHJT6V9WeqRMEoNJ7sIKtHCNdEvtIgqsON6yEU9Gb46xaMmlEH2Uhih6bdp(yrpvhpHPhwMpkN47hlHxxBBczjbvbxwMHUyKgOLM3Ti4MROMZGTc77wzaRfBKnb(6h5AE9ahA7)VeG70TpOEu3vNIN6j7GaDcrofRUV0txfop6WaBps7sFjsKpklHOu(JkD)iMmA3mg)E72m8Q5xLaoF65CaKeTrRQ63NmMd1DXXfaqxbS(owiEfmnxEWSE6wkd9KG96H)7E3RmA5SS)Gf6fR0HTxmZcFU(ZSiWduQti)Yoj3VmHCdQ9SqxXNShQ0VoHsJwJrBQL4qijNfECQab9nt5p75dKy3EM5eFsIVJC50dY6)2rDsxDZZwNcTxnbADeggvqrus5v52Xie7n1KZZ2J6GPInSUOMNO65)JqHolE3)R8Pbf9HCJdI7ZAC1zmQ8qgD7z9D7HKWlZF(ohFEYUnFpCkI6bHLxl65nZ8ye3tFnW5BJxpzo(ChCEWe5jUmSlXTKm7I5)NTBVb2J0v7Bpl9o72h5owh(ZnVdEx9H3ToYlVp24GJre8Qct1vF6k9EqCrjVYMr3e)r4bzUe)(K2VH9A3XS)n]]
)
spec:RegisterPack(
    "Protection",
    20261019065,
    [[Hekili:nw1wZnnpq0Fl8eTdL0KaTFCzYdW3qP0HPthepRyz5voIOyLrxAiV4F7SRtSJQJ7Lx6OU7zpA15SRdFc)3CwHia8BNoE6Ltgp5JJV8colSDnWzRfYLIs8qLyf(37C2aidABfLARXkkOYZJAt4hv88bzYVgK8BNCX4jC2cDrbSdi4LC2vwhCp4QZoWmEwyefA8WjRD271EmOW8P6SkBDMU6TLyRuNjxaYL1zBHWNRZclWiEqy8NvNDT1STodVkWu8ApHu4kb8GOQOo7MyrjScQcukqPWlToJU1ooqGo84kBbymawIYzxHyIyBkf(qltnfKBSYL(Dme9NID5V0LlcGnIbVk6WojhuwIqPDvUiCwslSNi2gTkKegHWA6dRQLJLWAerC9(ksFI7UBP1AkSBWtceyqtA6uKO)3w5bPtqkBI2yjTJQRlp9q)UZgRkoal40lb8F)2FToP2JIWjcvGOEJDJxVYFUAN)rAzQd(L7(jwMduGdQKaDvMTNochACwL2GtsIgK(rRDWoDzMRv3MRWN8zA1SxLhvQrpm(iudU5OIFZSZDa2T5rkXCr0jsiOxMhLcY8NBv9U)0OPLo7pD(v0dic18szXSjDaigjND(lby6vRSYOF20NVfWcLj(BA8fOdo3t(mrtb0WJ8GzpVSXR7X2(QOXQ2U440ntfPHH2XJB4mCyG2x79jaJgxBA(qdOertapEBZhEGkroUJX)kNLOnuY9tiCwN6XdiRVWI6j8uPVRxPsNghL1coBqroHRKeCwJSqncs577rzBfPMcH7Ihb3btkTDEkZIy7YNMnY8EyB(Fpzbn2jb7dpcSw7LtYiRBHzipSTKhUZESwF0o9qEBhz92FhGUJ3WhYXh2qFU5GWU3TigwyDC21WsTrJFjC)pDDAtA()o]]
)
