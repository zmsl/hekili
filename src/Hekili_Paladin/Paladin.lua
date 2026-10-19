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
local PALADIN_SPEC = 1486 -- alphabetical pseudo-spec ids (Rogue 1488, Warrior 1491 read in game); confirm at P1

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

-- The mana floors of Retribution's swing-gap fillers (D7: a percent of the maximum, one setting a line; wowsims uses
-- 10). Off by default: mana is secret and the floor is judged on the belief's low-biased lower bound, which starts at 0
-- on a fresh boot and climbs with regen, so a floor line becomes usable only after a warm-up (minutes out of combat);
-- the usability answers still refuse a filler at a real lack of mana.
spec:RegisterSetting("consecration_mana", 0, {
    type = "range",
    name = "Consecration Mana Floor",
    desc = "Consecration is used in the swing gap only while your mana is at least this percent of its maximum. 0 turns the floor off.",
    min = 0,
    max = 100,
    step = 1,
    width = "full",
})

spec:RegisterSetting("exorcism_mana", 0, {
    type = "range",
    name = "Exorcism Mana Floor",
    desc = "Exorcism is used in the swing gap only while your mana is at least this percent of its maximum. 0 turns the floor off.",
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
    [[Hekili:TE1xVTTnq8pl7LSAmp3yV2S0w4cSv0HUGIGIQcS3Oen1jlUijAqsfh)I(SV7OKIPKLSD96lg0K3F(D3974rXMZ(gliMBb29lUEXnZVE(BU52fSa7Unalydx8aFnUOGNJ)(vWQLRkTsvbD2UmfpM0FvPmZ(3fSvdAkZgqWUF(RU9gwqQmogQfemcwWFP0WJGUkYZ0vrFHNXJL4IxSrREuAWn5zVTkQqvfjl(11iyQIePG4HQODG9Dvr2uChdWZmtRI(OivbMQiErCv0DLXRHCOW(Z4oqsciSvrKtEwfuqnUmxfdzzaQsIwLJYuIWsWnwZK36zMALfkvwSABb6TpXZZPiqLuf9pAUnLWyJ5HNarPfxSvwGIJEc13kjXNtQQY2vffGr(dW0gv(2wPXwBTplxNABXOTE)xe4(hD8hu55Uq09Z(9)kPgOknfGHshaxGyABkGOsABexAn1jQMONcMj9X3hufgqGXKRQ407JpP0cPj3linyWTUkAnFJV(lqSIhlXLik5ywntP0Mg3zaRf1IGNkbX8kmpedj8Ym7K3rPlkn6SEtokvrfBlpdlbtBGpc5QOS60cpXsEDRARrMBEzsnVIQ5Dyw)Xx(m5tnKaAOqau1mB3KziDwRsKzijNlirnZ2ObHkFf3UuV3cH8snFQmz5pTQmjzw)tMvUP6UdmWVS8LunmuLekQRzol427ukO7umhsTL6s05U1HuYyk1RUmftBHgkRrkvN3MTFZzqbFfr2BTc6Y)TLIpT0aOVtcxlIxo3xKuhxNW1wIPpnrjkn9eX5dhL2F7(jGgn9aNJGtIKrHClaVQordit1tDmp3Cqp76xagnlEH(UJroeb9p(yrpvhpHR7xMpkN473wcVw7MeYcYu5CzrkcXqnqlnVF(SxFf1apBJW((LT9TZ81p01G7zCO5sIlXWT621OEu3LNIN6jBVaDerofRUR0Jxfop6qpFpq7sxjILpklGWe(JkD3iMCA7Gi)E7Mm8YRVkgCy65CaehUwRk72NmeGAV44cmqBbS6owaEfmn8U3dcOBPm07g2Rh(V7DpfPHZY(twGxSsh2CXml456pZIgUNsTc5x2j5(TrKRxTNf4k(K)qLE1iknyng9PwIdHKCwWXPcKPF9y4zpFGe7MZmN4ts8bYLtpiV)7hfKU6MNVoL1UDeR1syyubnO5vadri27QrNNT3Q9MkwZ6cRFhRh(hGcDw8UFO8PEf9(CJdI7ZAC1zmQ8qgDZzDHDFs4LHNVZXNNSBZhHJrupiS8ArpVzMhJ4E6RboFF8MrZXN7GZdMipYLHTjUfKBNF9)B)2zG9aD1((ZsVZU5rUd1H)CZBV3vF4DRd8Y7Jno4yebVQWyD1NUsV3iUOKxAtPBI)e8GmtIFFsZh6oXDm7)(]]
)
spec:RegisterPack(
    "Protection",
    20261019065,
    [[Hekili:nwv3YPnpq0NLEvtMMsc0eAA7WfTDAAAMVHjZN61cllVYOIWYJ(juUXp7DxdgumKFUjJYUN9OvNZUg(q(V5Scra4thDXOXdVy4NUy8vCwyDnWz1c5crjEOsSe)79oBaKbTTIsT2yffu55rTj8RkE(rzYxds(0HxE9yoBUUOa2ae8so7gRdEaCnz7zgplmIcnE4KAN9bThdkmFUjRY2KPREFj2knzY5GCrt2Ai8LMSWCmIheg)znz3AnRBYWRcmfV1tifUsapiQkAYUlwuclHQaLcuk8sBYOBDhhiqhECPTamgalr5SlrmrSnLcFOJP2cYnw5c)ggI(tXU8)1LZdGnIbVj6WojhuwIqPDzUiCwslSLi2kTkKegHWA7dRQJJfqnIiwVTI0N4M7wATMc7k8Kabg0KMocj672kpiDcszt0glPDuD7Ytp0F6SXQI9Wco9ca)3F8xRtQ9OiCIqfiQxzx51l9NR24FKwM6GF9()dlZbkWbvsGUkZ6thGdnoRsBWjjrls)GAhSrxM460Tzk8jFMwn5n5rLAWJJpa1G7oO43n5ChGDBEKsmteDIec6L5jPGm)zwvV7pnAAPt(Zo)k6beHAwPSyYWDaigjND2Rby6vRSYOFYOxUfWcLj(BA85OdoZt(mrtb0YJCVzpRS1R7X22QOXQUU4W0TtfPHHUXJ74mCyG2x79jaJgxBA)qdOertapoT9dpqLih3X4FJZs0gk52jeoBN6XdiRVYI6j8uPFOxPsNghL1co7OICcxjj4SwzHAeKYl7rzxfPMcH7QNa3EtkTDEoZIyB8ZZgzEpUn)4ZwqRDsWU(jG1zVCsgz7wyoMh2vYJ3zpuRpyN(yE7oY6T)Ee6oCd)yo(Xn0xAoiS5DlIH5whNDlSqB04xc3(txN2MM)V)]]
)
