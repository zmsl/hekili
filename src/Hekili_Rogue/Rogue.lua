-- Hekili_Rogue/Rogue.lua
-- The Forever Rogue (one pseudo-spec, ROGUE_SPEC below; Combat, Assassination and Subtlety are talent builds, one pack
-- each): the Rogue kit with Forever's spell data (ranks, costs, cooldowns and durations from the Forever DB2 at build
-- 1.60.1.70338, wowdb; energy costs are DB2 points), Forever's Venom, Mutilate and Cutthroat, energy and combo points
-- as the Druid's cat has them (combo points plain in combat, measured), Adrenaline Rush as a regen multiplier, Stealth
-- and Vanish from IsStealthed (unprobed, so the belief also models them from our casts), poisons as precombat
-- reminders read from the weapon enchants out of combat, and the default priorities (all provisional: no in-game
-- check yet, D5). Research: docs/research/2026-10-15-forever-rogue/research.md and the class-completion research §2.
-- Talents: only those this file reads; a modifier is rank 1's value x the rank (Classic's convention; only rank 1 of
-- each is in the Forever DB2), floored at 0.
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

-- The pseudo-spec the client reports for a Rogue (Constants.lua's row): 1488, read in game 2026-10-19
-- (C_SpecializationInfo.GetSpecializationInfo(1)). The ids run alphabetically by class from Druid 1483 to Warrior 1491.
local ROGUE_SPEC = 1488

local spec = Hekili:NewSpecialization(ROGUE_SPEC, false, 132292) -- ability_rogue_eviscerate
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

-- Talents: { node (unused on Forever), rank 1's spell, max rank } (`wowdb talents ROGUE`; Forever-only ones by spell),
-- only those this file reads, until the live export (checkpoint Q1) lists the tree.
spec:RegisterTalents({
    improved_sinister_strike = { 0, 13732, 2 },
    improved_slice_and_dice = { 0, 14165, 3 },
    relentless_strikes = { 0, 14179, 1 },
    improved_expose_armor = { 0, 14168, 2 },
    -- Forever-only
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
})

spec:RegisterSetting("poisons", true, {
    type = "toggle",
    name = "Poison Reminders",
    desc = "When enabled, Instant Poison (main hand) and Deadly Poison (off hand) are shown before combat when a "
        .. "weapon has no enchant.",
    width = "full",
})

spec:RegisterOptions({ package = "Combat" })

-- The three priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those
-- and run it, never these blocks (tests/Forever/rogue_spec.lua checks they match). Pick one with
-- /hekili priority <name>. All three are provisional (their descriptions say why).
spec:RegisterPack(
    "Combat",
    20261019514,
    [[Hekili:nFvxVTTnu0Fl5fpBmp3ip700U4cKU1I9fcgQ2ZsIsIYMWYIcKuj1ag63(ouurwYH0nDzfyVylZpo3dV3Z9i6aVG)oWpLOOb3n)Y5x5DP3Bw6TiWxTVKg4xss2swJhki7WN)mFxmrPhEFoNKQ3ACflx9BfbXwrrwstcUZBX1xh4VHLMsnlKktc8)ixqVNkQJmOwh9j(6kAD04sb)EMKXli5VToQGxhXk(H1Ga1rjBOjBRJ2tv)uDKFolbJrksRJ(f8406OBtfuSnwbg)tvYnTZQ2GFZlPfuHedjWV2XtP55umzMGVdZwbMKqKk5K3(uORJ2slbfRkXG4BfttCp7reZNZFOoshU17Br595KuSKpMxjeyShyQn2ctvjW8d44NqfiDAqBjygYriruYzfkCegVaqSHwydcgMxY5yU0k6eaNpRGjvAc7ReSTyjkaLUWLovdjhSFnYdCHn4mHHPmatI5vkdazK8Cuf(dMUImmP8HpxYLyV3k2PbDmbmIQuimt6V056IOIsYvdku4qk5fiyXuWjQ5WR31yswZX4b(ds2o5RYmkOVt2PDU9V(teEbnJIQIM98I89tMbfRGNXYHeMKOGYsoRuqnWUIvivKcvOjStRK0qEww46K0vEtzzRAzo2IHxJUiUklB2ocRiCdyDiIe(wndIJF)jW)9REvkLKMV)RfF9AEwWlnzWNcSbN2P7V9vBrnBAgpPsUYRBuafTPUfs0LT25NRrQDCONg1iedn6WzjqmtluVB1Y(Oq2fJgHMJMj200zqRmQ7GAwqOPH0kI3maW1eHGROpfXl(QGC0fP0MuslEiLmACmxkp0bJsqakPC4c0Na3tqhKLmC3(mla8za9Cqdtzr3OfQRVP4HzcQwpjF38rJDCMmUjht5g21UOzjCP6GR0HLZTd0ECfA4otUzqYH05agkAR7dr)MvlV06HUNKe4O2axQCAisH2WWBGKiwBNgM14MQx9zZP934W18ytqV2LtPOdfV3Olo2vmOhQZ8wd6yh9lhSp(IZjoUz1vNx7mXfNKTVbiu28canXCOnhF2ayL134D4u10RxE4irGyjWh2063OFY1dYbRKnxaHMrQYv4X7AUqceuX4LZbV)rd7aFTNvGFt9sVifG6KvMiy4mYiyWVOF1rC7751H)Cn()OdMyAU6hVxGpNoqlCeO2Ur3r6)k)pRn5AMT8eM1Zbuxe6yQX)Bar))L143gVr7MJ6e3vU0odnlhiAFUMMA8FTd87zIEoS9A0Dx7aK(MR9r5SvhnGVXzh5lWC9iVgU9HMbEx64WC0pUpFC6l)T3yUHTUC5oXPUpL)35y7YY2MNDFtBWs9F07X7zAZz2LzWWluB1u4lFvABg8Uc4Gly)mINLRwBZV3v4ADYSiV7UQDt2d5psLAJ(1k)kDllNH)bt7F61KEd(Np]]
)
spec:RegisterPack(
    "Assassination",
    20261019736,
    [[Hekili:nJ12UnUnq0VL8IRnQxVrox3TXlq22TOxdkQw0hLeLeLnHPjfiPIRbm03ENrsrsmwmobzdqFXwMxoZzUW5i6aVGVg4Nsm0G7MF68l9o17dxD2Lb(MD50a)CsYAYs4bbzd85TAnrRzcIHjf4S74sskIqCbJB(vrq8GGPZPjb35D(1xh4VILMsRxivNe4)Zsf9EQQmYc8YO)wUSGwgnoxjVNPHHi8pwgjKLrmX7wc0PmkzfnzDz0oQ5hkJ85SeymIiTm6NGhNwg9puHCtZqMvWKYCQGQ0Wqk4xBKPuoNctMPW1jlawKq0g9KpEiELrRP5MYOICyq4BddjTxpZadEgaGCtmqYCjty0WS)OKdi8zUuMIu3aZrkJU4DvlOm6lGZLqvqmd81ZlJ2YmRkJ(ZcdJdJnzA3ZGjH9IbAaOX(mbtBqk4BuS1WSX0mj6wmavg4JCkrjOPie5sjNjwcoQunKNTDfv0TrsSSWuBTmcNdX2FNHXzBV(l)BUud79w1ge0XGtPPgdyMj9x6Cm1yOeo6wDzcW71sHUJ1yyd31yswLxTvUvZ2OFFwD5X3PBRiU9V(dW8kAgvrfi7Lc(UjZGYrLmJXHYuscwcPNLRO1WUGj0gIWewB2PfAAOmllCzs6cVPSSfnmh2snVgDsCrw2SneMiCfW6qWsW3Mzq2)3oa(VFX7tPKu(Uxk(4AEwWRRJGhcCnont3F7lwd5SPzYKc9cV2rbOOv5TqcM2AMFoIuZ4Pf0rvLWH1vWZskuqC28Pfx0hfYM4c9QkxR2200zqTYOwhTEbH1N4geXBSaCjrPKg6HiEYlcYrNKsRcjn4bHKrJJLA9(wymkcGsQeoM3Na3tGdudeHB3x9ca(yrph0OoTGh0cX8Bk8WmffRN0FA(OXo8j8JL76c51SRzrZsKAZExHJb8BhO9Wkq4EIyJvWXScA2WPHGRxvRyH8nl8SsL2U9d1G9QwTdlathUGZB0jDfLwPkSHBhEv)0nmN5cMeOZCym2y(WSUJJahjV6iItB7Xxf0Ton2ofA1Xom7(Hh)8rngytJeXS1c5wHZv)eK)Mfx(0(2exrXhSTROgCyy8tI8G09gV9poyE1f77yGv1PUrlmuxjfwvzmyKX1P13gcg4dcx4BU8O3gIdKvx9Ax0msb3apEx1RHrfKy49rc(8dsyb(yx8a)QJq4ImaupALjkg46mcm4r7G3HBFvGw8NJ4FMdMu3UPV9EfD(rdDUdd10FYTL(wPimyBpKzx8iM1R7aMeAzATIGfr))LyXBJAXWYfyG7shP0EYhwfShiJGGCLZc8xH8rhxS3U9zRRDW)kfMdzYlr4bH)dpZ6QoHP(28TusczN3Po8(U12Noo1QEHIvV9QvvoNRgSpWMJfPpUkHlzIH0j6luurVh3vVTA1wAZQg8BPe3RG8g8MxnxvziPmxv523jBWUOh)2ydPi6YGw3r7zyVbUD2qcKUmxtR)bAG1EBTQOhe)ifMvOo8VqxZ4m4sWn)Pi1H3G)7d]]
)
spec:RegisterPack(
    "Subtlety",
    20261019927,
    [[Hekili:nJ1wVTTnu4Fl(fpBmp3iN7DrbiDRBDxqqrDFwsusuwewwuGKkzgWq)23HI6UjTDBAr6d11MI878DUWZ5lYXY5ZoldrcSZJloBXvwNzD7TlU2zPyBg2zzgkynAf8Lu0g4ZL5(IeSyR8bBtOOq5H9ZjjI)k1Xxlo8mCGZJwxCZnolJjHHy1gX8aNL)bLHFcZk8QXTW7t0v54cVjzm6teoHMIsEBHxkTWJK(lRasu4feJdwx4Tfl(v4KjKaynuAyH3VdFDwH3VLleXmksuTSig2GFcghYHvyWp2qdXjjy4zrm6McpAoWHaexWRoYdB8Z5X)e8ZCoYNKqeBN(26LH9N23kW)eePFynBFgv4TgNb7ipB4o)idVbhseib4NWV)uEMixYVNjcWkFoMcwxcdylGku4yFaVHYyXqkrXcFkNJHNnbv4XXcbjDvHhoHJFogZWt7AXfGfEpetdWmilPEYLGBt34dr3mkjvWHT8NXuUibYelfmY6AhPRDfW2L5Cy5jVdQp4cKFnNlJ1HOvRKwSIqtNjHNMuYTiPxSFicOl4neGsezoWNMlugkcLKaP5)Hit59dFV))YOC4SpW2ibTtiOVFlRseyuIKFTfeGdZPPGX8XaNWQaH8utqrc55EM(mNSH)MivrQSyOQ48Hp(VG5z4iieNguMjs2oDoCPGrJijW9euGmLYNNXWkyTjPqykv4Qm7SCo2Lgf5Uki02AgjYUI5Wru8A8i)8OO5BqKu3yG1UGLG)xmhkJ(79G)NTFtigfMS9lfF5Eoj45Qi4(aRWP6XDpU9AiNnlIgKZTTAwfGcxM3CrY0w1ZxirQA9WC84YIsxvn58GCgeNf3BFzxuqL3fRXxE(sIeuFTeOIwyUthkYaKYdWHZHkUXnHl1gCPz4um7eaCfIXOc8(io6lcYXJcXL(tfEsVzI8Y(UgyemeGsivWN2LapHsjCn5PMZP2aWNE0Zanujx51vxzvsi8L5qxlOQKF)IXtm4tYpwTTnXPyx1MMhany2zkCOXVnGw9oKWDGytVGdurNHyQ(Tqmja6kfsFoTkM04zN19mIyc0qe7cHRYQ0ES5oBRlhyGoT03ljOnkBFExe6hS7wFpsxYWqv(92wJh1EHQRbyQPmDV5PhHZBsgvhPSiuGsGNoxunCYfUWXNJtrWa2WDv7pUzAbCKPhi5yIJ4M5us6nXq7GD6x)Idv1EN9vhUOgO7OtXhRJj1h0(IDdluV(YDJoqHPjNFLAcSlVCaSXYME1DTr8E319Rgp3Kj7LzoH2z1aya1tTLlucCOyU2e5Dw6cOTHSPM9)r7t1xjEXjqJfqorNK5OQ(xDsfRtHMqJFTzTZsqMJuY9af8jGhWl)ReWrO8eb81hl)RgQUr48UAbpolLZ8Dww2ArUjba1GDgWiq8GGGfp68(wC7QzOb)fs8p3i(NAXzRvuJI6Z)lm4P17T1EVafesdDPbdvnNZSL(wPSqBxkjZUAaZ6mwtgKAyQAkApI(JLOJVpQo03Dxg4U2qkTJmKUrlJYrKyDJbS6ipP3LR9KPib52tmt2tgtFkQvaJeBRZmEt8fOCPLt9pE)lPwd7hDyg)vPT5GIBoQ6Mw)OYG97IznSnztJVgLqDDkJkIEDKeDanr6M6uRk64YIkdnd7W30ySNoPJLZvnzTm1oVnRQT)1xLqQsdAQTEnIhXCN6qSJPjWKOaT5NoYck9HHdaoCq7BMoMxeNn17DGISEe)7UYSxGhjk7klppsRcmtTY7)IN0wTLD0x5KoHCMmyVxe1jypnVckD66mzUkffAg308kPkJEq8dLdTVa5JFaVMKqk8Mu9(NvHxN)p]]
)
