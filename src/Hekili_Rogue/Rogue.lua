-- Hekili_Rogue/Rogue.lua
-- The Forever Rogue (Assassination, Combat and Subtlety, one spec a talent tree: Hekili:NewClass): the Rogue kit with
-- Forever's spell data (ranks, costs, cooldowns and durations from the Forever DB2 at build 1.60.1.70338, wowdb; energy
-- costs are DB2 points), Forever's Venom, Mutilate and Cutthroat, energy and combo points as the Druid's cat has them
-- (combo points plain in combat, measured), Adrenaline Rush as a regen multiplier, Stealth and Vanish from IsStealthed
-- (unprobed, so the belief also models them from our casts), poisons as precombat reminders read from the weapon
-- enchants out of combat, and the default priorities (all provisional: no in-game check yet, D5). Research:
-- docs/research/2026-10-15-forever-rogue/research.md and the class-completion research §2.
-- Talents: the DB2's 51 Classic nodes and the Forever-only ones this file reads; a modifier is rank 1's value x the
-- rank (Classic's convention; only rank 1 of each is in the Forever DB2), floored at 0.
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
            package = "Assassination",
        },
        { key = "combat", name = "Combat", tree = 2, icon = 132090, role = "attack", package = "Combat" },
        { key = "subtlety", name = "Subtlety", tree = 3, icon = 132320, role = "attack", package = "Subtlety" },
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

-- Expose Armor holds the other finishers while it is due (wowsims's "Expose - Prevent Other Finishers").
spec:RegisterStateExpr("expose_due", function()
    return settings.expose_armor and knownRank(EXPOSE_ARMOR) > 0 and debuff.expose_armor.remains <= 16
end)

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

        spend = 60, -- Thousand Cuts's -3 a stack unmodelled (its stacks come from Rupture's ticks)
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

        spend = 50,
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

        spend = 35,
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
            return max(0, 45 - 5 * talent.improved_sinister_strike.rank)
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

-- The settings the priorities read (wowsims's variables and defaults where it has them).
spec:RegisterAbilities({
    instant_poison = poison("Instant Poison", INSTANT_POISON, "main_hand_enchant"),
    deadly_poison = poison("Deadly Poison", DEADLY_POISON, "off_hand_enchant"),
})

spec:RegisterSetting("trash_dots", false, {
    type = "toggle",
    name = "Bleeds on Trash",
    desc = "When enabled, Rupture and Garrote (and Vanish to re-open with Garrote) are used on targets that are not "
        .. "bosses. Off by default: short fights end before a bleed pays for itself.",
    width = "full",
})

spec:RegisterSetting("expose_armor", false, {
    type = "toggle",
    name = "Maintain Expose Armor",
    desc = "When enabled, Expose Armor is kept on the target at 5 combo points, ahead of the other finishers.",
    width = "full",
})

spec:RegisterSetting("vanish", true, {
    type = "toggle",
    name = "Vanish to Re-open",
    desc = "When enabled, Vanish is used in combat to open again with Garrote or Ambush.",
    width = "full",
})

spec:RegisterSetting("ambush_opener", false, {
    type = "toggle",
    name = "Ambush Opener",
    desc = "When enabled, Ambush opens from Stealth and Vanish instead of Garrote (needs a dagger and to stand behind).",
    width = "full",
})

spec:RegisterSetting("backstab", false, {
    type = "toggle",
    name = "Backstab Builder",
    desc = "When enabled, Backstab is the builder and Hemorrhage is kept up (needs a dagger and to stand behind).",
    width = "full",
}, "subtlety")

spec:RegisterSetting("poisons", true, {
    type = "toggle",
    name = "Poison Reminders",
    desc = "When enabled, Instant Poison (main hand) and Deadly Poison (off hand) are shown before combat when a "
        .. "weapon has no enchant.",
    width = "full",
})

-- The three priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those
-- and run it, never these blocks (tests/Forever/rogue_spec.lua checks they match). Pick one with
-- /hekili priority <name>. All three are provisional (their descriptions say why).
spec:RegisterPack(
    "Combat",
    20261019514,
    [[Hekili:nFvxVTTnu0Fl5fpBmp3iV401S4cKULUpr7q02RsIsIYMWYIcKujZag63(ouurwYH0jDDfyVylZpo3dV3Z9i6aVG)mWpLOObFy(5ZV07CV3SW7IaF1UsAGFjjzdzfEOGSfF(d8TXeLE4D5CsQERXvSC1VueeBffzjnjW)Up(t)1TxL0U51S0uQzdujM99Cb9EQOoYGED0D8vv06OXLc(9mjJxqYVQoQGxhXk(MvGi1rjRPjBQJ2rvFFDKFolbJrksRJ(r8406OBsfuSnwbg)Uk562zvRXV5L0cQqIHe4xB5P08CkMmtW3IzRatsisLCYvpf66On0sqXQsmi(wX0e3ZEeX858hQJ0HB1UwuExojfl595vcbg7bMATTWuvcmVfh)eQaPvdAlaZqocjIsoRqHJW4laeRPf2GGH5LCoMlTIobW5ZkysLMW(kbBdwIcqPlGPt1qYb7xH8axydotyykdWKyELYaqgjphvHFJPRidtk3(3LCj27nITAqhtaJOkfcZK(lDUUiQOKC1GcfoKsEbcwmfCIAo86DnMK1CmEG)GKTv(QmJc6RKDANB(JFhHxqZOOQOzpViF3Kzq5k4zSCiLjjkOSKZkfudSlzfsfPqfAc70kjnKNLfUkjDP3uw2YwMJTy41OZIRYYMTLWkcxdwhIiHVvZG44xFc8F9YxLsjP57(uXxVMxe8stg8PaBWPD6(BF5guZMMXtQKl96gfqrBQBHeDzRD(5AKAhh6PrncXqJoCwceZ0c1BxUOpkKTXOrO5OzInnDg0kJ6oOMfeAAiTI41daCfri4k6tr8SpjihDwkTjL0IhsjJghZLY9DWOeeGskhUa9jW9e0bzjd3TpZcaFgqph0Wuw0nAH66BkEyMGQ1tY3oF0yhNjJBYHuUHDTlAwcxQ27kDy5C7aThxHgUtKBgKCiDoGHI26(q0VE5IZTEO7jjboQ1WLkNgIuOnm8gijI12PHznUP6vFYCA)noCnp2e0RD5yk6qX7n6SdDfd6H6mV1Go2r)YE7JFXPehxV8YtRDM4ItY23aekBEbGMyo0MJpzaSY6R92FSA61l2FGiqSe4dBA9B0p6Ac5GvYMlIqZiv5k84hAUyceuX4LZbV7rd7aFTNvGFt9sVifG6OvMiy4mYiyWN1V6aU9986WFUg)V1btmnx9J3NHpNoqx4iqTDJUJ0)v(FwBY1mBXrmRNdOUi0XuJ)3aI()lRXVmEJ2nh1jUlDPDgAwoq0(snn14)Ah43Ze9uy71O7(ohG03CTpkNS6Ob8no7i)mmxpWRHBFOzG35oomh8J7ZhN(YF5nMByRlxUJCQ7t5)Do2USST5z330gSu)h(E8EM2CMDzgm8c1wnfE(RsBZG3vahCb7xq8SC1AB(9UcxRtMf5D3vTBYEi)rQuR1Vw5NPBy5m8pyA)tVM0BW)m]]
)
spec:RegisterPack(
    "Assassination",
    20261019736,
    [[Hekili:nJ12UnUnq0VL8IRdQxVXo36MgVazBtV3TfRB7JsIwAKnHPjfiPsQbc03ENrsrsmwmobjbOVylZlN5mx4CeDWKG)kyEcZcbFE6rtpBYrt(W5hFwWC72miyEglEnBj(GKTb)8kJHzmCjZYvsA2TcflHqyroxy)zzWIEbZKbXbZ)YF8J)91xWCXyfpjbQ2hyWf9dknCdOlICSvr0xulZHIOHzA1nCdoetCrrKuveXLVBjYUIO4vq86IOTG9BlIMl4X4ymzsr03JpoQi6FaPAt9q2v4KQmqcAdoKg)1gvcieaozQMwNkhzrmZynhEXU4veTgYSfr5z4G43wor6jDmdo4XiaQnlqsMP4sRbN97uceHpjuQeI6wCowr0PVRCbfrxJoxmOXqi6RNueDl3UQi63ZTCbo2HJAFgnjUxkUJanCoxYnwIcZTA(AC2fqQICloIkh9rbW0siHGitPeC5s0rv6(8SBxbY2nYwOYTvwlLjeyS9x5uC21RV(FZugCVxP3qGoeDkdyTOzoS7sNsPglWeKB1MjqV3OKMwwtHnAxdzPLE1TQBn8nM3NwvE8vMMkIR(ZFdnVgsbnij2RKIThogRo1QuUaRAzXujKzCMgQGDgxASmPnSYSJYnqOknnCzCYSjJ4PZQzoULkEn4Gf5PPJ3W4YWviRdrlHFBhJz)Fzh4)6zVpbyjITpx8P18KG3ufb3f4kCQNU72NTgZzJsvX5MztAgfHckZBHmkTvp)ucP6XtYHbLLWHvvWJJZ1yC2(XzN2ff2Mf5MvLUwLTHKXyTYGghTAbHvN46fXlDaCjtRvwyxep4zb5GdsGYqsnEyizWWfkJ5UgySAgIsIcpM3La3WWdu9eHB2x1cq(4qpp0OkTqh0cP8Bc(Wynq1tMpoDWqp(e9XYTTH8k2vVOXXkJ9oFHJE8BpOD)ki4EKyJtWXUcB2iGq01lRvCq(YztCsLUU991GDQwDdlit7VGBYGdAlkDsvud3w8k)PFyo2hmXyN5WfuJ5DZ6EocSN8QNio00JVmO7CASzkYQd9y276F8tguBGn1seJxlv3k9U6hH8xo7Sh33o0xu8EB7lQHhgg(Oi3lDVCYDpmyE(P31YaNQttTwyOPukSSYO3iJVtRVnemyokCrV5YdE5ibswt5BHbPSCHfF8ZLVvgizlW3hj4t3lHfmN6IhmV8ieTilc1dwzSMJUoNHdU3o4T42vfOb)Pe(h7HjvTB6AVxqNFYqN4Xq19N8BPxlfHEB7rm70hWSoDhOKqdtRueCi6)VelEBul6xUGcCN5jL2r(WPGDhzecKZ9wG)cKpA5I72DpB9nE4FPcZUm55i8qW)HNyDvRWuxB(wkjrSBYrE8(212LoE1QEMIvV9QvLoNVgS3ZM9fP3VkHpzI(0j6kuusVh2vVPA1vAZPg81uI7fqElDZR6RQ0NuMVQC37K1Bx09FBS(ue9zqN7O9eSxp3oRpbsFMRU1FpnWAUTwz0dJFSC7ksh(NG1CbhVeC9Fksv4n4)c]]
)
spec:RegisterPack(
    "Subtlety",
    20261019927,
    [[Hekili:nJ1wVTTnu4Fl(fpBSm3iNBlzrbiDlRDxqxrC3RsIsIYIW0IcKuj1ag63(ouuswYM02TPfzpuxBkE(oFNl8WViphVp5nlgjXEFy6PtV05uNRVE6vEZKRYXEZYrrlqZHVKHwcFoRiusXYvQhSIYqXkJdliu5FK5fAehrooYB2J)Z7(3hUr0AEkjogRnblGN)7mo(jmVmOXdLbpYMxGldgLZzpreewgIEtzqgRmGK9tZb6ugeLIJwugScl)fWskjcwdLfxg8BWxpPm4xlKYuodjRxwMcBiKIXXcyfo8JLSymLIHNLWzlldyfahIqcPO2K7xgwis)b4NfcuiHsKRgFtZYW(Z67f4FsIkoCozxgvgSaNd7OiF7D(roEjoMirsioHF)yrUSqXVNjsWlFkLbExbd4lGkmWS3JxY48uO4OzritiWWZgHkdeyPKKnVmatf4NtXC84UECk4HhGCAeMd1l9tUacB2Yqi7MZizsbSL3LYeskujMj5Kfnbsx)kHTRQ(WYJEl0PiKOWgoxLRJrZNR8ynHgFIcEgTIBjQOy3ueqxiAiaLiQAqiRqQDucIsHY8FruL8(PVh(Cota2EpFPc0oPG(XTQlrIruf)20qabSGLboledCcRtekRgHsKk7EM9SGSu8MeDtQQzOU58(p(3G754eifNfvvjORgpboEWzjekCIbfPkPIj5CSgwxsgKMYK(A3EsHa7Zss8Nhf76CcjXTM5GjAEnCqyrsYKLisMFkWAFWtW)lNaTr)5oW)JUVjgJIPR(sXxTNJcEHodUlWACQFCxZDxa1StsyrfcxN2vbOWv1nFKQSv)8PkKQxpUapSQP0x3tojQGd5z5DUx0ffu1zXg8v2xrKOMJLavmcZTMqrLG0raoEc0XnSnDP3GplhNH5hbGZrCotI3fXbFrqoCqmUkEQXtfnJuh2x3cJKJauIzsX4Ue4jugryOo1ANEdaF6rpl0qxCvhx9vDjXWxMatTGUsXDthoYsmP(y(Qnfon7Q30KiyaZABPddXTf0A2HcU9KB6LCGo6CexpVfYjrWuPy2Zz15K2i70U2itjWarSpKUQ6s7XMBDDUylh0zK(ofbJzz3Z6Iq)KD3(7bMkgw6YVZ1z4GnhO66aU(wMUN8mJWzTfJAtQAcLik80jY6lN8HdCIj4meCbB8669N2EBbyY49uCSXrC79uk6nYY4G1Mx)8911ER7L7VPgO7GJjgBYjng6E(6TBuV6I1d2tJPTGFU(gyFr1fWwBB613TjJ37SEy91ZTvYEvMJyCwdawq9yh5cTa7lNBSqERJPe6Mu2y7X)GDP6ReVeeyWciNOtXCq98RoLIfzWqOHV2S2BgiZrj5ElT8uicev)9c4eubvcF9dv)9d1Ni8EBJGhVzQ789MvnArTjja1w7mItG8bbblEW773GBxndT4pvH)zwX)yBo34f9vr95)5wI0M9UXFVafekhDHfhvFpNDp9TszHXPukMD5wmRZ1AQKult13I2JO))s0X3hvhMNURsCxzPK2rgs3SLv5ikS(zly1rEsVdx7itrbY1hzLSNmM(u0Oagf2oNA9K4lq5Ygo138(hsD2EE0(z8xL2M9kU5GQB2eh1oS)umNTht2o4Rvju3GYQIOxhjr7rtKPBDAufDyzrvPMTNW3oySNoPdvZ1dzDSnoFtv148RVkHuvo02y9gepG7o2lXoKMaBIcmwF6ilOkg2(cG9N0(MPJ5fXzBZE3srwpI)Dxz2liIKvtLv2JmQaZ2O8(V4jJDB5h8vozsiNnh27frDe(ZWRGYKUoBURwrHHRBAFLuvzpi)HkGXxG8X3JxqOKYGr1V)zD617)o]]
)
