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

-- The pseudo-spec the client reports for a Rogue (Constants.lua's row). A placeholder until checkpoint Q1 reads it.
local ROGUE_SPEC = 1500

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
    [[Hekili:nFvxVTTnu0Fl5fphmpxlV401U4cKU1I9fcgQ2ZsIsIYIWYIcKujZag63(ouurwYH0nzDfyVylZpo3dV3Z9i6aVG)kWpLOOb3TCXYR9w49MvExf4R2xrd8RijBjBWdLKD4ZFIVlMO0dVVGts1BnUMvO(1YGyROiROjb35TAXIa)CwAk1SqQmjW)JCb9EQOjYGAt0N4BQPnrtRe87zsgVKu82MOsEteR872ac0eLKtt22eTNQ(XMi)cwcgJuM2e9Z4Xznr3MkOyBSsm(NQL5DZQYXV5v0sQqIHe4x74P0IckMmtW3HzRbtsisL8Y3(uOBI2sRafRRWG4BfttCp7reZxWFOjshUn77q59fKuSKpwuleyShyQCBHPUcy(bC8tOcKonOTcmd5iKiQ4SsfoctVcqKtlTbbdZl5CmxAn9saNpRKjvAc7ReSTyjkaLUWLotdjhSFdYdCHn4mHHPmatI51kdazKIcuf(DMUImoP8H)UIlXEVvStd6ucyevPqyUC4sxQlIkkPqnQqHdPKxIGftbNOMdVExtjzThJh4piz7KVkZOG(gzV252)8pq4f0mkQkA2Zll2F5COyf8mwbKWKefuwY5vcQb21SsPIuQcnHDwTKgYZYc3KKU2BglBDhZXwm8AYfX1zzZ3ryLH5G1His4B1Cio(TNa)3U(vPusAX(xk(618SGxAYGpfydoDtpC7R3IA2SmEsTCTx)OakABDlKOlBDZVuJu34qpnPvigA0HZtGyMwQE36vdrHSlgncThntSPPZHwzs)b1SGqtdPveVzeGBicbxrFkIx8IGCYfP02ushEiLmzAmxkp0dJsqakPC4cmKa3tqhKLmC)(mla8ze9Cqdtzr3OfQRVP4H5cQwpjF3YjtDCMmUjht5g21TO5jCP6GR0HLZTd0ECfA4otUzuYH07agk6Q7Jr)M1Rwy9qpqscCu5WLQGgIuOnm8gjjI12PHzTUP6vF2C6WnoEnp2emOD5uk6qX7n5IJDfJ6H6nV1Go1r)Yb7JF15eh3S(6ZRDU0fNKDVbiu2(canXCOnNE2ayL134D4u10RxD4irGyjWh2063OFY1dkaRKTxaHMrQlu4X7AVqceuX4LZbV)rd7aFTNvGFB9sVifG6KvMiy4mYiyWpRF1rCh651J)sn(FVdMyAUggVVaFoDGUYrG66gDhP)R8)S2KRz2Qty2ahqDrONPg)Vre9)xwJFD8gTBoQtCx7s7m2SCKO95AAQX)1oWFGj65W2Rv39doazO56quoB1rd4BC2r(fyUEKxJ3(yZaVfoomh9JhYhN(YF9nMBzRlxUtCQhs5)Do2USST5zp00gSu)h9E8EM2CMDzgm(c1wnf(8xL2MbVRao6c2pJ4z5Q1287DfUoNmlY7(RA3M9q(JuRY1Vw5xOBzfm8py6(tVM0BW)a]]
)
spec:RegisterPack(
    "Assassination",
    20261019736,
    [[Hekili:nJvwVnUnq4Fl5fxB0SEJCU6UnEbY2Uf9mOOQOpkjkPr2eMMuGKkPgWq)27msk6iwmhiBa6l2Y84B(MdoFIoWl4Vd8tzwi4MfNS4cVt8(WLNErGVDxoe4NZs2WwHpizBXpV2yygdxYSCLKMDNqXsjeIl4c7VidIhfmtoKeCJ35NCsG)AEAkuVqWKe4)tknClOlJgaEz0FPwvaLrtZ1QB5gCiM4JLrsvzex(UviDkJswdjBkJ2b2VVmYxWtWXyY0YOFeF84YO)bKQTndzxJtQYbjOn4qA8xBvPGqa4KzAADQcKfjmJ1m7JhIxz0gi3wgvKJdIFB5eP96zgCWtrauBJrsMR4sRbN9huceHpluQuI6wCowz05VRAbLrFbDUeqJXm0xpRm6oUDDz0Fuy5cCSzh39mAsCVuGgbAQpxYnwIc(wnFdoBmKPi3IJOYrFuamTesjiYvkbxUcDuLEmp7U1GSBJSyvHT2AzmHaJT)gNIZd96V8V5kdU3R1BjqNIoLbSw0mZ6V0fuQXcmb5wDzc07nkPPJ1uyJ21uwwLxDN6odFR59z1LhFJPTI46)83rZRHmqdsI9kPy3S5y5OwLXfyzklHkHmZZ1qnSl5sJLjTH1M94cdeQYYcxLKU07yE2YgMJBPMxtokUilB(wgxgUgzDiAj8B7Cm7)Rha)3U89PalvS7LIpTMNf8M6i4HaxJtZ093(Ynyo74mvsHzPx7OiuqvElKrPTM5xqi1mEAbmPQeoSUcEEsHgJZ2pT88(OW2gxywx5A12gsNJ1ktAD06fewFIBueVAaGRyATYchI4rViiNCukufsAWddjtMgRmM9TWy1meLufEmVpbULHhOgjc3UV6fG8za9CqJ60cDqlKYVP4dZ1avpz(0IjtD4t0hR21fYRzxZIMNOm29UchJ43oq7(vqW9iXMbbh7ASzJacrxVQwzaYxT0BqQCOBFFnyVQ1HHfKPJxW5n5OUIYbPkQHBhEv)0nmN6cMeSZCym1y(WSUJJaprE1rehA7Xxf0hCASDkYQtDy29Jp(ztAmW2gjI5BKQ7Kox9Jq(RwEXJ7BZCffV32UIA4HHPpkYJs3R82)WG5LNVVJbdQonnAHHMkPWQkJrJmUoT(2qWaFu4IEZLh82qcKSMQx7cYyfcl(4nvVggizX47Je857LWc8PU4b(vhHOfzrOEWkt0C015mCWNSdEhU9vbAXFbH)PoysD7M(27v05Nm0zomut)j3w6RLIWOT9iMD(dywVUdusOLP1kcdi6)VelEBulgxUGcCx4iL2t(yqb7bYieix6Sa)viF0XLHBF4zRVZb)RuyoKjVeHhc(p8mRR6eM6BZ3sjjIDEN4W77wBF64uR6fkw92Rwv5CUAWEpBEQi9tRs4sMymDI(cfv07HD1BRwhkTnOg8RPe3RG8w6MxnxvzmPmxv5dVt2ODrF6BJnMIOldo4oApd7nYTZgtG0L5AA9psdS2BRvf9W4hRWUM0H)zydxWXlb38NIuhEd(V]]
)
spec:RegisterPack(
    "Subtlety",
    20261019927,
    [[Hekili:nJvxVTTnu0Fl(fpBmp3iN4KLUOaKU1TUpqqrDFwsusuwewwuGKkzgWq)23LIsYI2K2UnTi7H6AtrEUN7h8EprEoEF2BrmsG9EC2fZU25cNBVD2nEleBkWElkqrRqlHVKJwdFUOmuKHfBKpytgfflpCyjjt8N5EHgXHxGJ8E0z(fx4TiLehJvBeZJ8w87ug(jmRkOf3QGprxwIRcgvWOpr4eAok7Tvb50Qas(pTeirvqukoAvvWgS4xGtMrIG1q5Xvb)g81jvb)APqKYOirZYIuydHzyCmhwHb)ynngNLHHNLWORRcOLahIqCbV5ipSoSKN(dWpl5OqsgrSz8BBxg2FUUvG)jis)WzYHmQkyfUa2rzX(78Jm8ACmrGeGFc)(tLfIsj)EMiaR85ukyDjmGTaQqHJ9b8AkJLcPeflcPCogE2iuvahleK8Lvb4mo(5umdpUVfNbw49qmncZGSK6jZb3MUoeIUfusUGdB5psPCrgKjwiyKvTosF7kGTlZ5WYJEhuFWfOWwoxhRJrlxkTydHgprcpnRMBjsV4WqeqxWBiaLiYCqiTuOmuckldsZ)nrMY1dFV)FlOC4SpWwlbTxiq3VLvjcmktYVDfeGdZP5GXcXaNWQaH8uJqjc55EM(mNSM)MevrQSyOP48Hp(pG5z4eieNhvNjY2mEkCPGrtizW9euKmLYNwWWkyDj5qykx4Rm7Kso2NMK4Vmk21zcjXTH5Wru8A4GWYKKPRrKC)uG1(GLG)xmfkJ(RdG)hDFtmgfNT5lfF5Eol45Qi4HaRWP5X9pU7kiNnjHgvYDD6wfGcxN38rY0wZZNjrQz94s8W6IsFvn50OsgeNf37oVpkO67IT4lpFnrIAVwcuXim3zcfzas5b44Pqf3WUWLAd(0cCoMDgaUeXyub(qeh8fb5WbX4A)PbpP3msEzFBhmcgcqjMk4J7tGNq5eUH8u35uBa4Jg9SqdvYvED1xwLedFzk01cQk53pB4il(K8JLB2L4uSRzttJGgmBTfom43wqRDhs4osSrl4av0fiMQFletIGUsX0NZBIjDE2f9pJiLaneX(q4QUkvJn356mFpd0RL(bjbJrz3l7JGEWUF99atjdlv5376mCWUlu9natnLP)npZiCzxYO5i1fHcug80PIMHt(Wfo(uCocgWgVTz)PDtlGJm(ijhBCe3nNssVrwAhS186xDSQ27CV(4f1aDhCo(yBmP9GUxTD)c1BMVDWrkmT58lvtG951dGTw2Ov3TlIRDxpSz8CxMulZCgTZAbWcQNBlxOe4yXCJjY7Cmfq3fYgB3)hCivFL4fNanwa5e9sMdA6F1lvSkhAcn81M1Elazosj37PGpd8aE9FLaobvMjGV(y9F1qZncV31k4XBHCMV3I6wlYnjaO2BNrmcepiiyXtoVFhU91m0H)mj(xAf)ZT4CNvuJI05)vw8029UZEVafesdn3IHAMZz3sFRuwySlLKzxVhZ6nwtgK6yQAkQgr))LOJVpQom3Dxg4UXskTNmK(rlRYrKy9ZwWQN8eTlxhitrcYTNzMutgJofnkGrITZfwVj(cuUSJt6hx)sQZ(9JooJ)Q02CuXnNuDZo)OXG6DXC2VnzxJVoLq9DkRkIEDKeDenrMM60Qk60YIQdn73HVRXOMoPtLZvnzDS1oFxw1y)RVkHu1g0wB9wepH5o3HyNstGnrbgZp9Kfu7d7pa44bTVz6yErC2wV39uKPr8V7kZEbEKOURS88iJkWS1kx)fpzSAR4KVYjtc5SzqTxe1zypdVckt66SzUgffgg309kPQJEq8dvcTVa5JFaVIKrQcg18(NvHxV)7p]]
)
