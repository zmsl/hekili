-- Hekili_Rogue/Rogue.lua
-- The Forever Rogue (Assassination, Combat and Subtlety, one spec a talent tree: Hekili:NewClass): the Rogue kit with
-- Forever's spell data (ranks, costs, cooldowns and durations from the Forever DB2 at build 1.60.1.70338, wowdb; energy
-- costs are DB2 points), Forever's Venom, Mutilate and Cutthroat, energy and combo points as the Druid's cat has them
-- (combo points plain in combat, measured), Adrenaline Rush as a regen multiplier, Stealth and Vanish from IsStealthed
-- (unprobed, so the belief also models them from our casts), poisons as precombat reminders read from the weapon
-- enchants out of combat, and the default priorities (all provisional: no in-game check yet, D5). Research:
-- docs/research/2026-10-15-forever-rogue/research.md and the class-completion research §2.
-- Talents: the DB2's 51 Classic nodes and the Forever-only ones this file reads; a modifier is rank 1's value x the
-- rank (Classic's convention; only rank 1 of each is in the Forever DB2), floored at 0, except where wowsims/forever's
-- casts at the talent's last rank show the DB2 value is the whole talent's (Improved Sinister Strike, Dirty Deeds:
-- that value x rank / max rank).
-- Credits: Hekili (registration API and pack format; the `stealthed` table and the stealth-breaking runHandler hook
-- follow Hekili's Classic profile, origin/classic:Classic/Rogue.lua). wowsims/forever (MIT,
-- ui/specs/rogue/dps/apls/default.apl.json and sim/rogue/) is the reference for the priorities and the Cutthroat and
-- Preparation rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase, GetTime = Facade.UnitClassBase, Facade.GetTime
local IsSpellUsable, GetItemCount = Facade.C_Spell.IsSpellUsable, Facade.C_Item.GetItemCount

if UnitClassBase("player") ~= "ROGUE" then
    return
end

local state = Hekili.State
local max = math.max

-- The class kit and one spec a talent tree (ids the core's: Assassination 100041, Combat 100042, Subtlety 100043; the
-- client's one pseudo-spec, 1488, only keys the legacy profile the core migrates). Icons: the DB2 talent tabs'.
local spec = Hekili:NewClass("ROGUE", {
    specs = {
        {
            key = "assassination",
            name = "Assassination",
            tree = 1,
            icon = 132292,
            role = "attack",
            package = "Assassination (wowsims.com)",
        },
        { key = "combat", name = "Combat", tree = 2, icon = 132090, role = "attack", package = "Combat (wowsims.com)" },
        {
            key = "subtlety",
            name = "Subtlety",
            tree = 3,
            icon = 132320,
            role = "attack",
            package = "Subtlety (wowsims.com)",
        },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's).
local SINISTER_STRIKE = { 1752, 1757, 1758, 1759, 1760, 8621, 11293, 11294 }
local BACKSTAB = { 53, 2589, 2590, 2591, 8721, 11279, 11280, 11281, 25300 }
local EVISCERATE = { 2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300, 31016 }
local SLICE_AND_DICE = { 5171, 6774 }
local RUPTURE = { 1943, 8639, 8640, 11273, 11274, 11275 }
local EXPOSE_ARMOR = { 8647, 8649, 8650, 11197, 11198 }
local KICK = { 1766, 1767, 1768, 1769 }
local AMBUSH = { 8676, 8724, 8725, 11267, 11268, 11269 }
local GARROTE = { 703, 8631, 8632, 8633, 11289, 11290 }
local MUTILATE = { 1310707, 399956, 1241582, 1241584 }
local VANISH = { 1856, 1857, 1285372 } -- 1285372: Forever's "Rank 3" (checkpoint Q12)
local STEALTH = { 1784, 1785, 1786, 1787 }
local HEMORRHAGE = { 16511 }
local GHOSTLY_STRIKE = { 14278 }
local VENOM = { 1310703 }
local ADRENALINE_RUSH = { 13750 }
local BLADE_FLURRY = { 13877 }
local COLD_BLOOD = { 14177 }
local PREMEDITATION = { 14183 }
local PREPARATION = { 14185 }
-- The poisons' items (ItemSparse), best first.
local INSTANT_POISON = { 8928, 8927, 8926, 6950, 6949, 6947 }
local DEADLY_POISON = { 20844, 8985, 8984, 2893, 2892 }

-- Relentless Strikes (14179: 20% a combo point to restore 14181's 25 energy): only the certain part, at 5 points.
local RELENTLESS_ENERGY = 25

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

-- The finishers' durations by combo points (DB2 durations and per-point steps): Slice and Dice 6 + 3 a point,
-- Improved Slice and Dice +15% a rank (14165 aura 108 base 15); Rupture 6 + 2 a point; Venom 6 + 3 a point. Read at the
-- cast, so `now` and `handler` pass them (the auras' registered durations are the 5-point ones).
local function sndDuration(cp, rank)
    return (6 + 3 * cp) * (1 + 0.15 * rank)
end

spec:RegisterResource(Enum.PowerType.ComboPoints)
-- Adrenaline Rush (13750 aura 110 misc 3 base 100): +100% energy regen while it is up, a rate multiplier (C3b).
-- shortcut: after a /reload in combat energy's regen rate stays 0 for the rest of the fight (the Druid's Q3 note).
spec:RegisterResource(Enum.PowerType.Energy, {
    adrenaline_rush = { aura = "adrenaline_rush", mult = 2 },
})

-- Talents: { talent tree (1 Assassination, 2 Combat, 3 Subtlety: the dominant tree picks the spec), rank 1's spell,
-- max rank }: the DB2's 51 nodes (`wowdb talents ROGUE`; the tree is the DB2's Talent.TabID), keys the snake_case
-- names (Setup is setup_talent; a nameless node talent_<spell>), and the Forever-only ones by spell at tree 0 until the
-- live export (checkpoint Q1) places them.
spec:RegisterTalents({
    -- Assassination (tree 1)
    improved_eviscerate = { 1, 14162, 3 },
    remorseless_attacks = { 1, 14144, 2 },
    malice = { 1, 14138, 5 },
    ruthlessness = { 1, 14156, 3 },
    murder = { 1, 14158, 2 },
    improved_slice_and_dice = { 1, 14165, 3 },
    relentless_strikes = { 1, 14179, 1 },
    improved_expose_armor = { 1, 14168, 2 },
    lethality = { 1, 14128, 5 },
    vile_poisons = { 1, 16513, 5 },
    improved_poisons = { 1, 14113, 5 },
    cold_blood = { 1, 14177, 1 },
    improved_kidney_shot = { 1, 14174, 3 },
    seal_fate = { 1, 14186, 5 },
    vigor = { 1, 14983, 1 },
    -- Combat (tree 2)
    improved_gouge = { 2, 13741, 3 },
    improved_sinister_strike = { 2, 13732, 2 },
    lightning_reflexes = { 2, 13712, 5 },
    talent_13733 = { 2, 13733, 3 },
    deflection = { 2, 13713, 5 },
    precision = { 2, 13705, 5 },
    endurance = { 2, 13742, 2 },
    riposte = { 2, 14251, 1 },
    improved_sprint = { 2, 13743, 2 },
    improved_kick = { 2, 13754, 2 },
    hack_and_slash = { 2, 13706, 5 },
    dual_wield_specialization = { 2, 13715, 5 },
    hack_and_slash_2 = { 2, 13709, 5 },
    blade_flurry = { 2, 13877, 1 },
    hack_and_slash_3 = { 2, 13960, 5 },
    fist_weapon_specialization = { 2, 13707, 5 },
    weapon_expertise = { 2, 30919, 2 },
    aggression = { 2, 18427, 3 },
    adrenaline_rush = { 2, 13750, 1 },
    -- Subtlety (tree 3)
    master_of_deception = { 3, 13958, 5 },
    opportunity = { 3, 14057, 5 },
    sleight_of_hand = { 3, 30892, 2 },
    elusiveness = { 3, 13981, 2 },
    camouflage = { 3, 13975, 5 },
    initiative = { 3, 13976, 3 },
    ghostly_strike = { 3, 14278, 1 },
    improved_ambush = { 3, 14079, 3 },
    setup_talent = { 3, 13983, 3 },
    improved_sap = { 3, 14076, 3 },
    serrated_blades = { 3, 14171, 3 },
    heightened_senses = { 3, 30894, 2 },
    preparation = { 3, 14185, 1 },
    dirty_deeds = { 3, 14082, 2 },
    hemorrhage = { 3, 16511, 1 },
    deadliness = { 3, 30902, 5 },
    premeditation = { 3, 14183, 1 },
    -- Forever-only (tree unknown until the export)
    flawless_execution = { 0, 1310711, 1 },
    thousand_cuts = { 0, 1310721, 1 },
    cutthroat = { 0, 424980, 1 },
})

spec:RegisterAuras({
    adrenaline_rush = {
        id = 13750,
        duration = 15,
        max_stack = 1,
    },
    blade_flurry = {
        id = 13877,
        duration = 15,
        max_stack = 1,
    },
    -- One charge: the next Sinister Strike, Backstab, Ambush, Eviscerate or Mutilate crits (its cast takes it).
    cold_blood = {
        id = 14177,
        duration = 3600,
        max_stack = 1,
    },
    -- Cutthroat's proc (462707, 10 s): the next Ambush needs no Stealth. From Ambush's usability flip (reset_precast).
    cutthroat = {
        id = 462707,
        duration = 10,
        max_stack = 1,
    },
    expose_armor = {
        id = 8647,
        copy = rest(EXPOSE_ARMOR),
        duration = 30,
        max_stack = 1,
    },
    garrote = {
        id = 703,
        copy = rest(GARROTE),
        duration = 18,
        tick_time = 3,
        max_stack = 1,
    },
    ghostly_strike = {
        id = 14278,
        duration = 7,
        max_stack = 1,
    },
    hemorrhage = {
        id = 16511,
        duration = 15,
        max_stack = 1,
    },
    rupture = {
        id = 1943,
        copy = rest(RUPTURE),
        duration = 16,
        tick_time = 2,
        max_stack = 1,
    },
    slice_and_dice = {
        id = 5171,
        copy = { 6774 },
        duration = 21,
        max_stack = 1,
    },
    -- Until cancelled (DB2 -1); the IsStealthed read puts it up or down (Sources/Forms.lua, C5).
    stealth = {
        id = 1784,
        copy = rest(STEALTH),
        duration = 3600,
        max_stack = 1,
        isStealthed = true,
    },
    vanish = {
        id = 11327,
        copy = { 11329 },
        duration = 10,
        max_stack = 1,
        isStealthed = true,
    },
    venom = {
        id = 1310703,
        duration = 21,
        max_stack = 1,
    },
    -- Thousand Cuts's stacks (1310723, 10 s, 5: from Rupture's ticks): Backstab and Hemorrhage cost 3 less a stack
    -- (effect 0: aura 107 misc 14 -3, class mask 0x2000004).
    thousand_cuts = {
        id = 1310723,
        duration = 10,
        max_stack = 5,
    },
})

-- Stealth by kind (Hekili's Classic table, Forever's two auras): the APLs and Hekili's keybinding order read `.all`.
spec:RegisterStateTable(
    "stealthed",
    setmetatable({}, {
        __index = function(_, k)
            if k == "all" or k == "rogue" then
                return buff.stealth.up or buff.vanish.up
            elseif k == "remains" or k == "all_remains" or k == "rogue_remains" then
                return max(buff.stealth.remains, buff.vanish.remains)
            end
            return false
        end,
    })
)

-- An ability that starts combat breaks Stealth and Vanish in the sim (Hekili's Classic hook); Stealth's 10 s cooldown
-- starts then. Our casts' `now` write the same in the belief.
spec:RegisterHook("runHandler", function(key)
    local a = class.abilities[key]
    if (not a or a.startsCombat) and (buff.stealth.up or buff.vanish.up) then
        if buff.stealth.up then
            setCooldown("stealth", 10)
        end
        removeBuff("stealth")
        removeBuff("vanish")
    end
end)

-- Cutthroat from the plain usability read (the player aura walk is secret in combat): Ambush usable, or short only of
-- energy, while neither Stealth nor Vanish is believed up, is the proc; its 10 s from the flip's time.
local cutthroatAt, ambushOpen = 0, false
local function ambushUsable()
    local r = knownRank(AMBUSH)
    if r == 0 then
        return false
    end
    local usable, noMana = IsSpellUsable(AMBUSH[r])
    return usable == true or noMana == true
end
spec:RegisterEvent("SPELL_UPDATE_USABLE", function()
    local u = ambushUsable()
    if u ~= ambushOpen then
        ambushOpen = u
        cutthroatAt = u and GetTime() or 0
    end
end)

spec:RegisterHook("reset_precast", function()
    if
        now == query_time
        and talent.cutthroat.enabled
        and not (buff.stealth.up or buff.vanish.up)
        and ambushUsable()
    then
        if cutthroatAt > 0 and now - cutthroatAt < 10 then
            applyBuff("cutthroat", cutthroatAt + 10 - now)
        else
            applyBuff("cutthroat")
        end
    end
end)

-- A finisher needs a combo point (its `usable`; with `ladder = false` its answers are no energy rungs, C9).
local function finisherUsable()
    return combo_points.current > 0, "requires combo points"
end

-- A poison reminder (C4): the best of `items` in the bags, offered while one is there; its use enchants the weapon
-- whose pseudo-aura `slot` names (the sim models it; the belief reads it out of combat, Sources/Enchants.lua). Only
-- precombat lines read it.
local function poison(name, items, slot)
    local function best()
        for i = 1, #items do
            if GetItemCount(items[i]) > 0 then
                return items[i], true
            end
        end
        return items[#items], false
    end
    return {
        name = name,
        cast = 0,
        cooldown = 0,
        gcd = "off",

        item = best,
        items = items,
        bagItem = true,

        startsCombat = false,

        usable = function()
            local _, have = best()
            return have, "none in the bags"
        end,

        handler = function()
            applyBuff(slot)
        end,
    }
end

spec:RegisterAbilities({
    adrenaline_rush = {
        id = 13750,
        cast = 0,
        cooldown = 300,
        gcd = "totem",

        startsCombat = false,
        known = knows(ADRENALINE_RUSH),
        toggle = "cooldowns",

        now = function()
            applyBuff("adrenaline_rush")
        end,

        handler = function()
            applyBuff("adrenaline_rush")
        end,
    },

    ambush = {
        id = 8676,
        copy = rest(AMBUSH),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 60,
        spendType = "energy",

        startsCombat = true,
        known = knows(AMBUSH),

        -- In Stealth or Vanish, or with Cutthroat's proc; a dagger and being behind are the player's (settings).
        usable = function()
            return buff.stealth.up or buff.vanish.up or buff.cutthroat.up, "requires stealth"
        end,

        now = function()
            removeBuff("stealth")
            removeBuff("vanish")
            removeBuff("cutthroat")
            removeBuff("cold_blood")
        end,

        handler = function()
            removeBuff("cutthroat")
            removeBuff("cold_blood")
            gain(1, "combo_points")
        end,
    },

    backstab = {
        id = 53,
        copy = rest(BACKSTAB),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 60 - 3 * buff.thousand_cuts.stack)
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(BACKSTAB),

        now = function()
            removeBuff("cold_blood")
        end,

        handler = function()
            removeBuff("cold_blood")
            gain(1, "combo_points")
        end,
    },

    blade_flurry = {
        id = 13877,
        cast = 0,
        cooldown = 120,
        gcd = "totem",

        spend = 25,
        spendType = "energy",

        startsCombat = false,
        known = knows(BLADE_FLURRY),
        toggle = "cooldowns",

        now = function()
            applyBuff("blade_flurry")
        end,

        handler = function()
            applyBuff("blade_flurry")
        end,
    },

    cold_blood = {
        id = 14177,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        known = knows(COLD_BLOOD),
        toggle = "cooldowns",

        now = function()
            applyBuff("cold_blood")
        end,

        handler = function()
            applyBuff("cold_blood")
        end,
    },

    eviscerate = {
        id = 2098,
        copy = rest(EVISCERATE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 35 - 10 * talent.flawless_execution.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(EVISCERATE),
        ladder = false, -- a finisher: an answer short of energy may be short of combo points (C9)
        usable = finisherUsable,

        now = function()
            removeBuff("cold_blood")
            if talent.relentless_strikes.enabled and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            removeBuff("cold_blood")
            if talent.relentless_strikes.enabled and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
            spend(combo_points.current, "combo_points")
        end,
    },

    expose_armor = {
        id = 8647,
        copy = rest(EXPOSE_ARMOR),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 25 - 10 * talent.improved_expose_armor.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(EXPOSE_ARMOR),
        ladder = false,
        usable = finisherUsable,

        now = function()
            applyDebuff("target", "expose_armor")
            if talent.relentless_strikes.enabled and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            applyDebuff("target", "expose_armor")
            if talent.relentless_strikes.enabled and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
            spend(combo_points.current, "combo_points")
        end,
    },

    garrote = {
        id = 703,
        copy = rest(GARROTE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function() -- Dirty Deeds (14082: aura 107 misc 14 -20, the talent's whole)
            return max(0, 50 - 10 * talent.dirty_deeds.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(GARROTE),
        missable = true,

        usable = function()
            return buff.stealth.up or buff.vanish.up, "requires stealth"
        end,

        now = function()
            removeBuff("stealth")
            removeBuff("vanish")
            applyDebuff("target", "garrote")
        end,

        handler = function()
            applyDebuff("target", "garrote")
            gain(1, "combo_points")
        end,
    },

    ghostly_strike = {
        id = 14278,
        cast = 0,
        cooldown = 20,
        gcd = "totem",

        spend = 40,
        spendType = "energy",

        startsCombat = true,
        known = knows(GHOSTLY_STRIKE),

        now = function()
            applyBuff("ghostly_strike")
        end,

        handler = function()
            applyBuff("ghostly_strike")
            gain(1, "combo_points")
        end,
    },

    hemorrhage = {
        id = 16511,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 35 - 3 * buff.thousand_cuts.stack)
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(HEMORRHAGE),
        missable = true,

        now = function()
            applyDebuff("target", "hemorrhage")
        end,

        handler = function()
            applyDebuff("target", "hemorrhage")
            gain(1, "combo_points")
        end,
    },

    kick = {
        id = 1766,
        copy = rest(KICK),
        cast = 0,
        cooldown = 10,
        gcd = "totem",

        spend = 25,
        spendType = "energy",

        startsCombat = true,
        known = knows(KICK),
        toggle = "interrupts",
        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function()
            interrupt()
        end,
    },

    -- Both hands; +2 combo points (one effect).
    mutilate = {
        id = 1310707,
        copy = rest(MUTILATE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 60,
        spendType = "energy",

        startsCombat = true,
        known = knows(MUTILATE),

        now = function()
            removeBuff("cold_blood")
        end,

        handler = function()
            removeBuff("cold_blood")
            gain(2, "combo_points")
        end,
    },

    -- +2 combo points (14183 effect 30 base 2); its 20 s hold of them is unmodelled. Whether it needs Stealth on
    -- Forever is checkpoint Q14 (wowsims casts it in and out of stealth).
    premeditation = {
        id = 14183,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        startsCombat = false,
        known = knows(PREMEDITATION),
        toggle = "cooldowns",

        handler = function()
            gain(2, "combo_points")
        end,
    },

    -- Finishes the cooldowns of Cold Blood, Premeditation, Vanish, Ghostly Strike, Blade Flurry and Adrenaline Rush
    -- (wowsims's list: a server script, no client data).
    preparation = {
        id = 14185,
        cast = 0,
        cooldown = 600,
        gcd = "totem",

        startsCombat = false,
        known = knows(PREPARATION),
        toggle = "cooldowns",

        now = function()
            setCooldown("cold_blood", 0)
            setCooldown("premeditation", 0)
            setCooldown("vanish", 0)
            setCooldown("ghostly_strike", 0)
            setCooldown("blade_flurry", 0)
            setCooldown("adrenaline_rush", 0)
        end,

        handler = function()
            setCooldown("cold_blood", 0)
            setCooldown("premeditation", 0)
            setCooldown("vanish", 0)
            setCooldown("ghostly_strike", 0)
            setCooldown("blade_flurry", 0)
            setCooldown("adrenaline_rush", 0)
        end,
    },

    rupture = {
        id = 1943,
        copy = rest(RUPTURE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 25,
        spendType = "energy",

        startsCombat = true,
        known = knows(RUPTURE),
        missable = true,
        ladder = false,
        usable = finisherUsable,

        now = function()
            applyDebuff("target", "rupture", 6 + 2 * combo_points.current)
            if talent.relentless_strikes.enabled and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            applyDebuff("target", "rupture", 6 + 2 * combo_points.current)
            if talent.relentless_strikes.enabled and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
            spend(combo_points.current, "combo_points")
        end,
    },

    sinister_strike = {
        id = 1752,
        copy = rest(SINISTER_STRIKE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 45 - 2.5 * talent.improved_sinister_strike.rank) -- 13732's -5 is the talent's whole
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(SINISTER_STRIKE),

        now = function()
            removeBuff("cold_blood")
        end,

        handler = function()
            removeBuff("cold_blood")
            gain(1, "combo_points")
        end,
    },

    slice_and_dice = {
        id = 5171,
        copy = { 6774 },
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 25,
        spendType = "energy",

        startsCombat = false,
        known = knows(SLICE_AND_DICE),
        ladder = false,
        usable = finisherUsable,

        -- Replaces the running one (checkpoint Q8).
        now = function()
            applyBuff("slice_and_dice", sndDuration(combo_points.current, talent.improved_slice_and_dice.rank))
            if talent.relentless_strikes.enabled and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            applyBuff("slice_and_dice", sndDuration(combo_points.current, talent.improved_slice_and_dice.rank))
            if talent.relentless_strikes.enabled and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
            spend(combo_points.current, "combo_points")
        end,
    },

    stealth = {
        id = 1784,
        copy = rest(STEALTH),
        cast = 0,
        cooldown = 10,
        gcd = "off",

        startsCombat = false,
        known = knows(STEALTH),
        nobuff = "stealth",

        usable = function()
            return combat == 0, "cannot be in combat"
        end,

        now = function()
            applyBuff("stealth")
        end,

        handler = function()
            applyBuff("stealth")
        end,
    },

    vanish = {
        id = 1856,
        copy = rest(VANISH),
        cast = 0,
        cooldown = 300,
        gcd = "off",

        startsCombat = false,
        known = knows(VANISH),

        now = function()
            applyBuff("vanish")
        end,

        handler = function()
            applyBuff("vanish")
        end,
    },

    -- Forever-only (talent, level 40): poison damage +30% for 6 s + 3 a combo point.
    venom = {
        id = 1310703,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 25,
        spendType = "energy",

        startsCombat = false,
        known = knows(VENOM),
        ladder = false,
        usable = finisherUsable,

        now = function()
            applyBuff("venom", 6 + 3 * combo_points.current)
            if talent.relentless_strikes.enabled and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            applyBuff("venom", 6 + 3 * combo_points.current)
            if talent.relentless_strikes.enabled and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
            spend(combo_points.current, "combo_points")
        end,
    },
})

-- The poison reminders (no wowsims.com list recommends them yet).
spec:RegisterAbilities({
    instant_poison = poison("Instant Poison", INSTANT_POISON, "main_hand_enchant"),
    deadly_poison = poison("Deadly Poison", DEADLY_POISON, "off_hand_enchant"),
})

-- The hand-built lists this file shipped before the wowsims.com packs: a saved choice of one falls back to the spec's
-- default.
spec:RetirePacks({ "Combat", "Assassination", "Subtlety" })

-- The three priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those
-- and run it, never these blocks (tests/Forever/rogue_spec.lua checks they match). Pick one with
-- /hekili priority <name>.
spec:RegisterPack(
    "Combat (wowsims.com)",
    20261020843,
    [[Hekili:LN1wVTTnu4Fl9fpl0aFnoTnika7(6Ww3WC3RsMwIYMZYIgKujWag(3(oK6IfziTLDsqlqFPvH8WVZvE45doyyWNdMgJe4GpnAWOBgoy0G3F94GPITBWbt3GIwHwaFKHwd)7psxphj2pR7J0h5K18Er01EsP2MsrXsKMNtsfFmlyUvq5BWrbt)N)6x)3F(2ifwbtxsIJXfhaZJCOJB3ptSeVFw5A9tOm8dy2(zX4euEki(3)3)X(zWY7NvdqoPVuH8(m6ICC)4n8(OnP8(LNPh8h9(ponZ7kaDgkJNcwCm8nvQncF)muCmn77GpwH3Y7TF2pHeOBTyfD)Zp(zaKLcXg(T97VGiwMpxA49ne1dWemT4XJ)W4bXdUEW4b9G4hJMqsH4lksqOz8EBy4IWJ)8uumomjnNX2EfS8M800qy9r7)9Ni8B97dFVghtei5wxLZXH0KKWfrX(dBXP5cmkvS095gwFoF06558Lxrs87oppjPxuUqSKrrIE5B6irKgUHsYeq(dSDCM4UjE1Ng01ceJrfyfa2fVZBIXkOlffawdHhqzeUPXkHR7BkeQ(GRYOpMTZcCDCikodZwSTYuU33qOikx45WjpajpLeHdrzXHXWhvgrr0YypiRHiz878h55P5JYypIvKnLUwf2f(EfMruAAm8v1YmmkERgoOyW6qPKmCiRkTP7K35pzWjSDBwUmiwDO5PuACysoBBXb0SGdBAjJvHGHzwQ3A3ZC7YW29(dhnqtz4CgEf6ikQ51QsT015wDuoU26GBRPqz7crkoeUazRG0mupCYUNS2OgH)c7VzyVCfPE96ukvdLwKY7y)M04AFRjUDEcU6PRg9DAg5UWQAJIANnPavz1h8h3ebDfDvcnkNxgRpQHmW6LwO(PZB6MqwSuewl6n628d4m66IaHsdQ)2vRU79hRDyw(gbeND2RdKVUzxPSsO7kqPWUqEMMZLod0JL3dUbmpfhxNtxIxtzSLWR0L51sGASUm7EspmcUKfQULAPc2Mv7)8711OI)bcpcdD6orl4gYP6cRFTVEZIRD2J1WDpRUZ1v3RwNliP1wINDXVhK)8Bx2i4)SdEonSXDEAMg0wRQMQk)0kLQwSUF71Epj)8Uj7oE91ILq(kDBixWiRWoVOpP5zQYehBkHUDpsySZPdJ7oka7oYEqq945qJyKd9iRJFRzPxrX9ZVgXdeYrppB5q9u2HwiFZKaA018RIuaNat0jWSgxBQni9(u1JH9Khe(wiVzeN(sM8cMce94Gsni)McgixX2UG)j85NuSVl7bh8dveaH)xXUkyAeJaofbfmT9SSceGIDGBjdgnGBp7ljYJnqUXScs3Pwtfur0uKdYwNdXSxrMzTPAqgaU2rOTbvnnV2kLnxC2KkyIRAcD2pAk5S5YD(K5KM2nTm5F4Wwdf2P51sEEs74DT0oky3y1gSWa88PakTL33sBPbBn9BfwihEgSdFjOh2s(HsV9dokoBgASgVV07CsLoCqlJXAmlBAgo4uQa3ShSzpxxg35rM8GrQJxWuf7vPBingxnUv8n1dSTJhQcvZM2vOwoy)jFo4IiO(IWqvz(MTCDL(pqH9KE0jjV2IsZJWET10xv(NRo(hKwVJHlETNlX2lLz7ZKABlcTUTTlHC75ZU1g9wl8BvzpZhfRYE6eEpz3OjkWmFzRcSQu3jlSFjgS)et2)SgT)cMT)8if3MQlVDhBSERZ1RYoMV1xLDo0j7BX8Z5Yz(1md5A(ed(Hwhr5lnF6VYsRxeL6xVCRqnEN8yiRuNp8ZukP)AFW0kMXMdq44SgJtEqzv8GpgonMlP83vvhbLhHYHxSybt)n8kskz)SU)s5VtSA7G)p]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261020843,
    [[Hekili:LN1wVTTnu4Fl5fpl0aFnoTnikaDy36Ww3WC3RsMwIYMZYIgKujWag(3(ou3SinPSStcAbYlTkuKFNVZfE05d2BO3x9MgIeyVVmAWOBhoy0GpCZyVPITBWEt3GcwHwapKGwd)7N4CeNtsqccnz)SUprFItwZ7fqx7i382ykkuc48usS4ZjEZnInFdoWB6)8x)6)(Z3HQdP30LKWqC(5W8GMT4D7NjwI3pRyT(rug(rmB)SqCeknwSF2N(7)y)myz4jnCsj9LSG3NrxKI7hUH3hTjM3V4O9G)O3)XPjoxdgHHs4XGBecptLgLW3pdfgst(b4Hv4T8E7N9tib6odKP7F(5VcGSui2WVRF)feXY05s(3xBRoaMaNdhp(JJheo4MbJh0dcQmAejgI9Oaj1592WWWHNJeUZJrHy)O4ugB71WYBsJJ9H1hT)3pAZVZTp88ACirKfcUoLJ9Prr(lccDh2ItZfyuSyP9ZnS6CUO1Zt5lVMe52DEAuuVGuHyjJIe9s30rIi1FdLKiG0iWDCI4(jovNgS1ceJrf4mamV9oxfIZGUyRaWki8ikHW1jReUUxLVPQdUkH(uYodW1XYwXjy2ITLu5bxTnfq5chlo5bi5XKaSpkj0peEOKe5rlT3bznejHFV7ihhfFug7rS8SP01kXo33lXmGsJdHNkxMHrHBvWbfcSdftsW(SY0MQtEV7KbNG7MyUmiwEO5XuAOFukBB(buyWHxAiJvIGgnlSBL7P)6IW2dUdhnqXy4ugEfQbdv)AvHv6A9vDYCCL1b3wXGY2fIySpCbYubPEOE4KDhT2OAH)C(xpSxSI0UoDk2vnJMNY7y(M04kFRoUDocx10vT(o1JCxyvTwrT1MuGPm6dUJRJGQHUoIgKYlI1nsKbgV0c1pDUQBezXsHF1wVvLZpItORZdezwi7VT1Q7b3XkhMLUraXzR96G9x1SRyVsO7kqXWBH8mnLlDgOhlVhCdyEmoSkNUeVMYylHVGxKxlaQ26YS7j9Wa4sMF2TudvWMyT7ZVxxTk(hj8am0P7eTGRTVSUWQx7REz(1oZXA4UNr35MY7vRtfK4kM4yE7pa7)8Bxwl4)SdEwj24ohNPbR1QQPYYpLsPYfR63EJZr5N3pzxZ1xlwc5R4T(CbJScB9I(K6NPmt00ucD72qySZPdJ7AeGDn8oiO2CoulgzXoY643Px6LxC)8RrCGnzPNNPCOAk7qlK3mjGADn)UifaYzGpYJz1U2uri1(uvJHD0heElK30ItFltEEtbHECWOAkIJbcYZuINR)eE8lzkZl6b79JLcaH)ptDL30agbCkcYBA7vz5jadBb3cfmka3E1xsKhRHCTzfKUtLLYLIOyilITohHzVIkZAt1GmaCJLqBnPAkETrjB20SjnWeB1eQQFumYzRL78fZjP2TTm5F4WgdfML51sDEsE8(wYJC1ng5GbfGNVeqjx(ql5sn1AQ3kmio8muh(sipSL6dLE7hTuCwp0ymEFP35KgD4GwgJvuwwNgw0uMbUEpy9EU2i35jM8ajvXZBAM6vPBijJTg3z6nvdSTthAgQ6nTlrTyW(t(5GlsG6lIc1m6R3Y1w6)Ge2t6rNu8AlknBq9ARLVM5F264Fy3QDmSPR9Cf2EPkBFMsBBrO1o3UeXTNV6wtYBnOVnl7P)rXYSNQG3t2nAsgy6FzReSYu3jlSFjgS)et2)SgT)cMT)8ef3MQlNDnnwVX56ZYo6FRVm7COt2BX8Z5Qz(1mdzB(en9Hghr5BTE6VZsRxKK6xVCRiB8o5XqgLoF4NPuk)18GPLkJ1hGWYz1gN8GXk1b3eo1MlP43vvfHmpcLcFXI5n93WRiXK9Z6(lf)oXzV27))d]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261020732,
    [[Hekili:LN12UnUnq0VL8IRf2aFnoPBquaArVTfTBlQ3(QKPLOSzTSObjvcmGH(27qDZI0K2YojyxG8YUkuZCMRC0CG9g69fVPHib27ZJgm62Hdgn4UXJ8Mk2Ub7nDdkyfAb8qcAn8VttNlIXITzZ6(m9zoznVxaDTJuUTXuuOeR5PKyXNs8MBew(gCG30)5V(1)9NVNxIM30LKWqCHkyEGv7CF2mXsC2SYZ6hrz4NWSSzH4iuASiB2p83)r2m44SznGiL0xAwEFgDrkUF4gEF0MyE)sT6b)rV)JttCUgWNHs4XGFhcptL2JWZMHcdPjFh8Wk8wEVSz)esGU3GF09p)0xaqwkeB433V)cIyz6CPR3xtuhatWDdhp(JJheo4MbJh0dYImAejgYZOabHMW7THHbLNJeUZJrHy)O4ugB71WXBsJJ9HZhL97hi8hC7dpVghsei5RUoLJ9Prr(lccDh2cT5cmkwS0UEdR1ZfTEEkF51r0GuoiejYT780OOEbPcXsgfj6LUPJezQ)gkjravsigWjIhM4uJcyZfigJkW5ayw8oxfIZHUuuayfeEcLq46oTeUUxviuTIRsOpNSZaCDSikobZwSTYvE0vtOakx4yji3djpMeG9rjH(HWdvorr2s7Dq1drs4p4oYXrjgL1aeROQkdTkSlI9kmdO04q4PQJzyu4wfCqHG3HIjjyFMS8jXsniFWDYGt47M8CzsSsP5XuAOFukBBHckEW(xAOIvHGMBwA36Wt)1LPThDhoAGIXWPm8k0rmuZRxLwPR1x1jpWvohcBfdkhBaJF8HlsMAi1t1dNS7GZg1i9x4)nt7LNiTRtNsPAy0IsEhZ3KgxhBnXTZb4QwUAm)PzM7c7Q1AQToScmLXyWDCteun0HdJS5idmEPf6F6Cv3iYILc)ArVv1NFcNqxxKiYTq(FBBu3JUJvuMLUra55s)CK1zEGE1d9k1rAIUcum8wOEtt5YGcM1Y7b3eMhJdRRTlXRPm2s4R3L13sGACUSkFYinaUS5NFB1qNSjV29LpZRrN)teEagM4DIrXnKlFAS61)6xwC9ZCUgUdAmCUP6(16ubjU2tCml(JG8N)yZgj)xCYZQJnUZHvAWATQBQQ9tPvQ6W65U34Cq95Uj7oE)1ILq9kERpxWiRWwVWpPPovvIJTTq3Uhjn250PXDhfGDh5Dqs941qTCKf7i7J)GERxrZ9lVhXbeYYSpt1q1s2(riVBkanMA(nrjGtGn7eywJRn1oK6CQ61Xo4dcVhQBA5PVMfpVPaXpoyunkXXGdYZzHxWhfE8Z5SYlNb79JEtdyeiiiiVPTNDvfns4)Z5O5nnFFdj4cWf0SqLSLCAumz75JjrESgYn2AqA7AlvqorXqwOFDou1Ed5Q1M(czc4glP2gK3uIAJK4SXItAGjwmGgFifJC2S7oF6Dsx72ww83RSXuHzIFTK5N0pURL(rbFhJ(GboHNpPqPV89T0xAWFt9wHb6INbFXxdcJTKXOmA)OLMZMPgJ57l9oN0Odh0YCScxZMUHfwM5GFQPX2CUZJE5ENufp152dTn4oNbQAITDmtZrvFO9jM(FrmtFvOMUpGlTBD6zuEGOp81wJWEATNmypjH2w0KEegTTMsBE8zB2)EPvNDyJR75s29sz7(cP72IuRDF7si8E(mEnr51aN38QN(NhRQEQKGp5CPj5GP)nUkWQkDNSX(1yz)tST)lAD)lyF)ZJOCB6UC2DSv9nURFE1r)R(vvN9d5EpwFoxE0VLviBBQOXz04YkFT5y)nwz9IOz)2vBf5l6jvdzKo9(Fkt5AdMxrTIJS(cew0vBXY9gRIr8XWPXEjL)2RQiKhrOu4lwmVP)gEfjMKnR7Vu(BjN)AV)p]]
)
