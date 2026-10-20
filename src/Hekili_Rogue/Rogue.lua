-- Hekili_Rogue/Rogue.lua
-- The Forever Rogue (Assassination, Combat and Subtlety, one spec a talent tree: Hekili:NewClass): the Rogue kit with
-- Forever's spell data (ranks, costs, cooldowns and durations from the Forever DB2 at build 1.60.1.70338, wowdb; energy
-- costs are DB2 points), Forever's Venom, Mutilate and Cutthroat, energy and combo points as the Druid's cat has them
-- (combo points plain in combat, measured), Adrenaline Rush as a regen multiplier, Stealth and Vanish from IsStealthed
-- (unprobed, so the belief also models them from our casts) and the poisons as abilities (no list recommends them
-- now). The defaults are the "<Spec> (wowsims.com)" packs, generated from wowsims/forever's Rogue APL
-- (tools/wowsims/specs/rogue_*.lua; no in-game check yet). Research: docs/research/2026-10-15-forever-rogue/research.md
-- and the class-completion research §2.
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
    20261020155,
    [[Hekili:DN1wVnUnt0Fl7lUwyd814SDdIcqV3TODBXN3VxLmTeLnRLfniPsGbc8V9oK6IfPjTLDs6wKx2vHA4zM5mdhXdCWWGVemngjWbFE0Gr3mCWObdNmjyQy7gCW0nOOvOfWdzO1W)(d01ZrIDZ6(i9roznVxeDTN0QTPuuSeP55KuXNYcMBfu(gCuW0)3F(l))F62ifwbtxsIJXfBaZJC4JB3ntSeVBw5A9tOm8dy2UzX4euEky(39x)(UzWY7MvdqoPV0H8(m6ICC)4n8(OnP8(L7Ph8h9(BonZ7kaDgkJNcrCm8mv6ncF3muCmn7BGhwH3Y7TB2pIeOBTefD)Jp9faKLcXg(T97VGiwMpxg49nm1dWecT4XJ)44bXdUEW4b9a(JrtiPa)IIeeAgV3ggUGE8NNIIXHjP5m22RGL3KNMgcRpA3VDGXV3Vp88ACmrGKV6QCooKMKeUik2Fyl2nxGrPILU33W695JwppNV8ksIF355jj9IYfILmks0lFthjI0WnusMaQFqSJZe3nXRE3GVwGymQaRaWU5DExmwbDPPaWAi8akJWndwjCDFxHr1BCvg9XSNSaxhhMIZWSfBRcL79nmkIYfEosY9qYtjr4quwCym8qvquWwgVdQAisg)o)rEEA5OK7rSIQPm1QWUi3RWmIstJHNQwMHrXB1WbfdrhkLKHdzvLn9K8o)jdorSBlYLKy1MMNsPXHj5STfBqlc2)slvSkemcZs)wNEMVUK2U3F4ObAodNZWRqhXrnpwv6LUoFvhvIRToK2AouoUqKIdHdq2AinP6HtE6G1g1G(lI)M0E5ks)61P0QgoTOK3X(jPX15wtC7CaU6LRgZDAYCxyxTrtTZHuGRSMd(JBIGUJUkHgLZl56JgidSEOf6F68UUjKflfH1MEJEm)aoJUUGiuEq93Ug1DV)yTnZY3iaE25SoW(6HDL2kHURaLcVfQZ0CUmzGzS8EWjG5P446A6s8AkJTe(kDzDTeOgRlRUNmdJGdzHQtPw6GTf1(p)zDn64FGWJWWKUtmcUHDQPW6h7RFzXXo7CnC2ZA6CD15Q15csADK4z387b7p)XLni)Nn55mWg35Wkn4Tw1nv1(P1kvTy982R9oO(8HjpD8(RflH6v62qUGrwHDEqFsZ9uvjo2Te629i0yNttJpD09394vjdwWbuYo13B2Cv0((87c8aJCmvZwvsVOSFiXBikUXKV)tqYCcCRmbM1O1VoG0N1uFvQdgQ)2OYyWeFnlpbtb5yCWPgsutHaKR0exOseE8ZknYLtkd((kzAW)R0afmnIrGKIGcM2ETqbcWXoWTuNHgWTxJKe5Xgi34l6Y0P2tfcg0CKdjrNJ8Pxr9tTPBqsax7GABiOslRTkSYLYkPdM4QNqxJIMtoBfxNVKlzODtll(73SvQWUySwQgtghFOLXrHgeRXGfDANVqnzS8TTmwAOPs)uHfjCNHgUxcrCTufNmB)OJMZMuJv((spZjD6WbTKJ10)1mmCO8tbU5myZzUUcUZtY3(GuhVGPknMY0qgmUgCRufQtSTtTOcvZH2vOwE97t(5Glsg5lIosv4BoY1v5FVqZtMrNuIzlAnpIgZwlYuLFUM4V3A9jgUuFEUYpVu9NptbOTGADhBxIe0ZxdQnrOwuHQQEMFuSQ6Pll9KtJMOaZ8lBvGvv6ozJ9lXv3Fw3D)cU8(5PCTnTpEpDS7TB9I7k638J5v0)(rvVjlaNRU2xZsGRByyOWZ6Lm(AR59F762fP691R4ju3atUnKv1T7)9(KkuTF3XkXRMFJ3XEnUX3ENvjv9y404QdL)aL6iOYiuo8rfwW0FfVIKs2nR7px(dUQEDW)8]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261020155,
    [[Hekili:DN1wVTTnu4Fl9fpl0aFnUDnikaDy36Ww3WC7RsMwIYMZYIgKujWab(3(oK6IfPjTLDswhYlTkuh(D(ox4r8doyyWxcMgJe4GppAWO3nCWObdNmjyQy7gCW0nOOvOfWdzO1W)(rohX5KmKGqZ2nR7d0h4K18Er01EsJ3MsrXsaNNtsfFklyUvS5BWrbt)7)8x(6pDdQjKbtxsIJXf7dZJoUhVz3mXs8UzLR1pHYW3Jz7MfJtq5PIDZ(4F977MbldpzGtoPVKf8(m6ICC)4n8(OnP8(LBTh8h9(honZ7kWjmugpfcJy4zQ0Pe(UzO4yA23bpScVL3B3SFejq3yHmD)Jp9faKLcXg(n97VGiwMpxY)(gM6bycCoE84pmEq8GRhmEqpiPYOjKui3JIKuN3BdddBEos4ppffJdtsZzSTxblVjpnnewF0UF7aJFRFF4514yIqLcUkNJdPjjHlII9h2IDZfyuQyP79nSEF(O1ZZ5lVIK43DEEssVOCHyjJIe9Y30rIinCdLKjGYiWDCM42jE17g81ceJrfyfa2nVZBIXkOlnfawdH7rzeUjzLW19nfgvVXvz0hYE0cCDCykodZwSTIk35ByueLl8CeK7HKNsIWHOS4Wy4HksuKTmEhu1qKm(T(J880IrzUhXkQMYqRc7IyVcZiknngEQAzggfVvdhumWoukjdhYQkB6b5T(tgCcUBJ5YKy1MMNsPXHj5STfBqJb7FPLkwfcg0S0V1HN5RltB35pC0anNHZz4vOJ4OMhRk9sxNVQJkW1whcBnhkhxisXHWbiBnKMP6HtE8G1g1i9xW)MP9YvK(1RtPvnCArjVJ9tsJRJTM425aC1lxnM70mZDHD1gn1ohsbUYAm4pUjc6o6QeAuoVmxFuImW6HwO)PZB6MqwSuewB6705894m66IeHYdQ)21OU78hRTzw(gbKNDoRdSVEyxPTsO7kqPWBH6mnNldgyglVhCcyEkoUUMUeVMYylHVGxwxlbQX6YQ7jJWi4qwO6uQLoyBS2)PpRRrh)9eEegM0DIrWnStnfw)yF9llo2zpxdN9SgoxxDUADUGKwZep7MFhy)5pUSrY)jN8CsSXDoSsdERvDtvTFATsvlwpV9AVdQpVFYJhV)AXsOELUnKlyKvyNh0N0CpvvIJDlHUDpsASZPtJpE09394vjJSGdOKDQV1S5QO99P3f4bg5yQMTQKErz)qIxrP4gt((FrsgKKaFOgZA06xti9zn1xL6GH6VoQmgzIVLLNGPGCmo4udDRPab5k9YfQeHh)Ss)C5KYGFOsMg8)knqbtJyeiOiOGPTxluGaCSdCl1zObC71ijrESbYn(IUmCQ9uHGbnh5qs05iF6fu)uB6gKjGRDKABiOslQTkSYLYkPdM4QNqxJIMtoBfxNVKlj1Exll(73S1uHDXyTunMKhVVL8OqdIvoyrN25lutYLVVLCPHMk9tfwKWDgA4EoeX1svCYO9doAoBMASMVV0ZCsNoCqlZXA6)Asdhk)uGBod2CMRlYDEs(2tsD8cMQ0ykddjzCn4wPkupX2o1IkunhAxHA51Vp5NdUizKpl6iv03CKRRY)EHMNmIoPeZw0AEenMTwKPk(CnXFV16tmCP(8CLFEP6pFIcqBrQ1n3UejONVguBIqTOcvv9m)Oyv1txw6jNgnrbM5x2QaRQ0DYg7NJRU)KU7(fC59Zt5ABAF8E8y3B36f3vPFZpMxL(3pQ6vzb4C11(swcCDdddfEwVKX3AnV)xx3UivVVCfpH6gyYTHSQUD)V3NuHQ97owjE18B8o2RXn(27SkPQhdNgxDO8hOuhbveHYHpQWcM(R4vKuYUzD)5YFWv1Rd(3p]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261020465,
    [[Hekili:DN1wVTTnu4Fl5fpj0aFnoDnikaBy36Ww3WC3RsMwIYMZYIgKujWab63(ou3SinPTSt66qEPvH8C(ox5H8d2FK)N9NfHey)pnE44BhnC8WBUDQ)mXUTy)zBrHRrlHpsrBG)Dw2crcwSlFUZt0N4Kn8(H0nUs52LqrrsSwKrseFm1FHry5BXH(Z(R)4N)7F8oEfA(ZwrIIWLQG5HwTZD5ZfRW5ZRwBqmLHFeZYNhHJrzjI85F3F(B5ZHLZN3cImYaPz5dy0Lz4brB5dqBt4dQ0Qp8h9)hon19AaFgkLNa(De8nvApcpFokkIM(nWhRX749ZN)dib6od(HZV)XpdGSsi2YVBWGLeXQSfsxFGMOUaMG7gnzYhMmmA4ndNmSpKfz0yscKNrHccnL3FlddkVaj8wKGIWbXjzm2URHL3MLKeaRpo)xpq435na(EdoIiqYTUoJJdOXXbldJ8g1bT5cmkrSYUEJA0ZdTzrgF11X0Wmoiej2ZzrwCC)WmHyfJIe9Z22tImnylLKkGkjed4uX9tDBqbS5seJrf4camlEVRIWfqxjkaSccpIsjCDNwcNZvLc1O46u6tPpBaUEwefNIzl3v7kp4PjuiLlCTeK7HKNqcXbO0OGi4JANOmBPThu9qKu(9EJDDvIrznaXkRQYqRg7YyVgZqknjc(QEzggfTtbhue4DOeskoGjlFsSudY79Mo8e(UjpxMeRvArcLgfeNX2vQGIhSFtdvSAe0CZk72eE6BxL2EWB04HkgdNXWRrhXqTpEvzfhRB1RiWvwhcBfdkhBaJFcGdsMAi1t1JM(8bRnUv6V0)BN2RwrAx3Evs1YOLL8EMpjnPj2AJBVdWvTC1A(t7m3f2vR1uBDyfykJXG3K2iOAOdhgzZrgA8ql0)07kNyYYvIGgrVv1NFeNs3uMikSqXFBBu3dEtuuMLTva55k)CS1zEGEnd9Q0rAchbkb2fQ30mUmOGzT8(WjHfj4OMA7k8gkJTcU9UQ(wbuR1Lv5tgPHWHTGItRg6Kn51EV8zET68FKWdXWeVtmkULCftJvp(3Sz5XpZ5A4mOXW5M6ZxBYeKKgpX1S4paYF(JnBL8FXjpRo2KEhwPbR1PUP62pLwP6fBM7EJ7b1N3p95J3FTCfuVs2fWfmYAS1d8tBRtDL4yVwWX5iPXENon(8r1354vjTSGfOKDQVtV5QS99L3f4cczz6MPQKArz)qI3qP4wt((FrsMtGxNjWSwT(noK6SMMNuDWq93gvgTmXxZYJ)mGEghmQgX1eWb5fCLlzncF(PcUZvtk9)E)zHmceeeK)SUZbQMSh8)fmP8Nv8Qaj4cWf0SqTSvmpumz3znjrEIgYTUBxA7glvsHqXqwijDoeQ(cYOQl9fYeWnwsTTOyPe1gPAzJRL0atTyanwlkg5S5GD(KWKU2TDS4VxzJPcZ0Z6i)mPF8(o6hLSsm6dgyUD(u3K(Y32rFPfll1tfgi1DgS6EnO11rEDYO9dwAoBNAmMVV0ZCsJoAyhZXkmcB7gw4cwa(PMgBZ5opsG7Dsv8uNBpY2G7cEIQj2UXFSav9H2Ny6)fXF8vHa5(aUYUnPNXfbI(WxBnc7jFEYG9K0o7qt6r4D2zINfXNTz)7LwD2HngPNlL0lLt6lKuAhsT29TlHw65Zl1eXudmtlQE6xpwx9uPQEY5stlat)oUAWQlDNSX(1458VO3ZFbpO)8yZ2L2h3Np2B5n(y(I0V(161P)9tXEtwaoxUUFjlb2ERHgRpJp34Rnp4)RRBxet4VCfprXBXKQHmY4D)VjO8MDZVISMgR(D8w0v7TF7nwnP1JHtRNou9JyQIqreHYGlvy(Z(f8AscjFUZpv9JYwST))(d]]
)
