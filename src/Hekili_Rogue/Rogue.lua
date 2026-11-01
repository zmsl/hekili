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
local L = Hekili:GetLocale("Hekili_Rogue")

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
            name = L["Assassination"],
            tree = 1,
            icon = 132292,
            role = "attack",
            package = "Assassination (wowsims.com)",
        },
        {
            key = "combat",
            name = L["Combat"],
            tree = 2,
            icon = 132090,
            role = "attack",
            package = "Combat (wowsims.com)",
        },
        {
            key = "subtlety",
            name = L["Subtlety"],
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
-- refundOnAvoid: the share of the energy an ability flagged `refundOnAvoid = true` gives back when dodged, parried or
-- missed (wowsims/forever's MissRefund, spelldata/attributes.go: 0.8 where the DB2 flags Discount Power On Miss and the
-- spell issues the refund). Not Slice and Dice, Vanish or the poisons; Gouge is flagged in the DB2 but wowsims issues
-- no refund for it (and the kit has no Gouge).
spec:RegisterResource(Enum.PowerType.Energy, {
    adrenaline_rush = { aura = "adrenaline_rush", mult = 2 },
}, nil, { refundOnAvoid = 0.8 })

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
-- precombat lines read it. Under the Potions toggle: a buff consumable (user ruling 2026-10-21, as the shared mana and
-- energy ones); with Potions off the reminder is skipped.
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
        toggle = "potions",

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
        refundOnAvoid = true, -- wowsims ambush.go; DB2 Discount Power On Miss
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
        refundOnAvoid = true, -- wowsims backstab.go; DB2 Discount Power On Miss
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
        refundOnAvoid = true, -- wowsims eviscerate.go; DB2 Discount Power On Miss
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
        expects = "debuff", -- no damage (DB2, wowsims): its ticket takes its own avoid only
        copy = rest(EXPOSE_ARMOR),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 25 - 10 * talent.improved_expose_armor.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims expose_armor.go; DB2 Discount Power On Miss
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
        refundOnAvoid = true, -- wowsims garrote.go; DB2 Discount Power On Miss
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
        refundOnAvoid = true, -- wowsims talents_subtlety.go; DB2 Discount Power On Miss
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
        refundOnAvoid = true, -- wowsims talents_subtlety.go; DB2 Discount Power On Miss
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
        refundOnAvoid = true, -- wowsims kick.go; DB2 Discount Power On Miss
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
        refundOnAvoid = true, -- wowsims talents_assassination.go; DB2 Discount Power On Miss
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
        refundOnAvoid = true, -- wowsims rupture.go; DB2 Discount Power On Miss
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
        refundOnAvoid = true, -- wowsims sinister_strike.go; DB2 Discount Power On Miss
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
        toggle = "cooldowns",

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
    20261101000,
    [[Hekili:LR1wVTTnu4Fl5fpj0aB54421G6aS7RdBDdZDVkBAjABTilAqsLcdy4F77qQlMKHuwYUPfR9LwzsEUF4HNZhs4WW3hongXXHV7MGBE5WHbddcccNY3TfhoDlk6b0k4Jm0g4F)bYMfi(H5EFG8bwYgw)iYgFXP2LsqXcoTipjL)2SWfwzkBlokC6F)N)Y)8t3fj5v401jXX4ccWSihY4UdZ5RXhMxU2GLek(rm9W8y8suEkC8V7V(9dZHLpmVMb5jdecKnGswLJheVLnaTnLnOKM(Wp6)VmsM)1a3POmwkOXXW3eH0syhMJIJjzFd8Xd4DS(hM)Jio6olAH3F823dmznNVLD3GbRs4RZxiu8bgh1h4jOAXJg96rbXb3gmkOp4)OKLjPG)ffXtizS(BP4c3ZKfPOy8SLP5u6Ud)2t2)ftgaFVbhNWrITUoNHNrwUC2QO4jdTtaJJrP816h96KLtUAr(YL9l3UF(2AYNG2SiNTwCgp5zIY581ucIdNQNGXKzBjjzCiybkkoJ)MX(1udICfIsjC81ljr5ScH5zNSExfJLIOKeqaAC6ruwcZIU75DvXHQj8HmYhY2BHD9CCuCgMUAx)uY9tm2pIW4(oSZJCJLMeHNHYINfdFuj)chMXEqidLKXEZKB891mpioTfrlcLcRQI3fMDfpJiK0y4RQLPyu8on(GIbTdLMKHNrRIC123BMmo4eQTnLw46QiArkHepBzoDxbbAc)4MwItvCWqdlLBTLzUDPh7(jdVjOdcZRrP5Wy23GNXFV35BcIO0rh)teBnLk7ysuxIw(NmLWZHQ0dYdFS)qL1b72LE37RE3SVFB9bpZ2A3uB1SdCof)aQH7RQpevYypNB1tktT1fsuvGIhy5P4zWRn2QMRuSA449Q)8gLAxfATQDwUI0(6vEkfrv4X6z)XNr1wKkF79e(Qx(5OnQ5VoZxdmEmW1l7crz1gMmsLd6cs753gvKaRp2bfF7DL3YKvR5ZQp6l115hXzKnfocPeK)2vxc3pzKgX08TCWpFY2ea6Q7tOKgHi84OuyxiEtYzcJcAtH1hUWSifhxhBxJ3qO01qxTLX3sgPSUikFslncUtotwcXs(RnTEYL3RGsM)JjSim0PG7UxuoISbg9771BwCFZUBgU5z1sUT6Q1MCEsATs4B)43dNV7LOu87xSFZPInQ3tdYG0AvIuvMNwwu1I19RCRVAO5vJ33Cw1Q1qOkD3mgNM8a2518XQ0ufeAQT66N6T5b7DAp4(gP3R5a0rhGdUiYpFHzkvrs7Lh79Hd5OCMrSrpuCSGWxgowLcCFUDTSeyUfoMQKMxRl6LuQN44jLT)FF8WWj8zkOeo9rmLbYZaQMuq3ysSHkqlb(8DsSIkldg(9vWva)VeEGWPr0eWEsqHtBpmbHCqWg8vHpThLGJQt5IHtL9riuBqgJmKHYB2ItutCXi1A6Gd8c6c2cppGl0MSbHTFRJ4McAdAgSvuhCb7GqaJDLyOpVIMq6cCeDhpcHw9YwgYpsSvVG9zYAjufc94vxOE08KLohVU5zop5qNTFQZNk5ZEeB3dRkCKF7zKM1fioUamo(kjk0cKo(KzWDu1fjqVUL3elM23A1al4G0DGqe6YWGwQmkWxONzRJrs7aj5JbkjTeMePr6QLbvxIv)85(GNuQMnu4Y1QHWIQA4aBfjZn7KWSRhxkx3av5OsQZp9UAg66PDjUl6o22HhJKRMVNFIgYol8y(OaiZrdUuUgUN22cWrWCoPXEsyCArsAd440gGCKMMzxf11UQpTE1cxi80viEoxmEUqqEAHx1TUDoW80DCEma6XcspYaNRUy0H(5KvJglzM5lAvmRkQDY05pgJmFrZm3THM7g6qTjPXFFtZlBoWSCCvZxURC6hRy9LMBVRyh9m54D1nHbukwBO4ZnUsFcJwNfYsplHmUShlbfOgrqsRDqlic1Ug46ampL)vUOMPy(N)Iu9bdaLdpqqdN(R4hsstom37Nl)B5rUD4)9]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261101000,
    [[Hekili:LR1wVTTnu4Fl5fpj0aB54421G6a0HDRdBDdZDVkBAjABTilAqsLcdy4F77qQlMKHuwYUPfR9LwzrEUF05Yhs4WWpeongXXHV)MGBE5WHbddcccNY3TfhoDlk6b0k4Hm0g4FFlJHySKmepHKDyU3hjFKLSH1pISXxC5DPeuSGHlYts5VllCHvEZ2IJcN(3)5V8p)0DivwgoDDsCmUGomlQzjE3H5814dZlF3GLek(rm9W8y8suEk)W83(x)(H5WRHNm4tEYaHwWgqjRYXdI3YgG2MYgusAF4h9)xgjZ)AqiuuglfmJy4zIqOjSdZrXXKSVdE4b8ow)dZ)rehDNfLX7pE3haMSMZ3YUBWGvj815le6)aJR6d8e054rJE9OG4GBdgf0hCQuYYKuW3JIeQoR)wkgiEbIpzrkkgpBzAoLU7WV9KZFXKbWZBWXjCPvFDodpJSC5SvrXtgANaghJs5R1V61jlNC1I8Ll7xEC)8T1KpbTzroBT4oEY7eLZ5RPeehUvpbJjZ2ssY4qmduuCg)nJ9RPge5keLs44RxsIYzfcZZoz9UkglfrjjGa040JOSeMfD3Z7QIlvt4dzKpMT3c7654Q4mmD1U(PK7NyCEeHX9DyNh5glnjcpdLfplgEOs(fomJZGqgkjJ9Mj347RzEqCAlIwekfwvfVlm7kEgriPXWtvVMIrX704dkg0ouAsgEgTkYvBFVzY4GtO22uAHRRIOfPes8SL50DfeOj8JhAjovXbdnSuU1wM5XLES7Nm8MGoimVgLMdJzFdEg)9ENVjiIshD8prS1uQCIjrDjA5FYucphQspip8X(dvEpy3U07EFZ7M99BRp4z2w7MARMDGZP4hqn89QAJOsg758OEszQ9EHevfOOblpfpd62yRAUsXQHJ3R(ZBuQDvO1Q2z5BK2xVYBPiQcpwp7nFgvBrQ8T3t4RE5NJ2OM)6m7gy0mWvNDHOSAdtgPYbDbP1(TrfjWAZoO4BVR8wMSAnFw9vFPUo)ioJSPWriLG83UMs4(jJ0iMMVLd(5toMaqx9CcL0ieHhhLcNcXBsotyuWykS(WhmlsXX1X214nekDnmXBz8TKrkVxeLpPLgbFtotwcXs(RnTEYLpRGsM)JjSimmPG7PxuUICag9V3RpS47n7Uz4lpRwYTvFATjNNKwRe(2V(9W97Ejkf)(f73CQyJ690GmiTwLivL5PLfv9Y65vU1xn08QX7BoRA1AiuLUBgJttEa78Z8XQ0ufeAAS66w928G9oThCFJ071Ca6OdWbxe5NVWmLQiP9YJ9(WLCuoZi2Ohkowq4RdhRsbUV0UwyjDOLmMQKMxRl6LuQ344jLT)FF8WWj8fkOeo9rmLbYZa)Muq3ysCJkqlbE89sCKkldg(dvWva)VeEGWPr0eWEsqHtBpmbHCqWg8vHpThLGJQt5ldNkNJqO2GmgzidLE2IButCXk1A6Gd8c6c2cppGl0MSbHTFRJ4McAdAgSvuhCb7GqaJDLyOVVIMq6cCeDhpcHw9YwgYpsSvVG9DYAjufc94vxOE08MLoxVU5Dop5sNTFRZNk5ZEfB3lRkCKF)zKM1fioUamo(gjk0cKo(SzWDu1fjqVULFjwSTV1QbwWbP7aHi0LHbTuzuGVqpZwhJK2bsYNcusAjmjsJ01idQUeR(5ZTHNuQMdu4Y1QHWIQA4aBfjZnNKWCQhxkx3av5OsQZp9PAg6Q1Ue3fDhB7WJrYvZ(5NyGSZcpMpjaYC0GlLRH7PTJaCemNtASNegNwKK2aooTbihPPzovrDTR6BRxTWfcpDfINZfJNleKNw4vDRBNdmpDhNhdGESG0JmW5AkgDOFoz1OXsMz2rRIzvrTtMo)PyL5lAN5UT0C3qhQnjn(7BAFzZfMLRRA25UYPFSI1xBU9UID0ZKJ310egqPyDGIV04k9zmADwil9SeY4YzSeuGAebjTXbTGiu7gGRdW8u(x5IAMI5F(ls1hmauo0GGgo9xXpKKMCyU3px(3YJ84W)l]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261101000,
    [[Hekili:LRvxVTTnx4Fl5gpj0aB54421GQaSHT3ToS19I5UBLmTeTTwKfniPsGbm8V9DO(YKmKYs2nTyT30klYZ3hD(4bjyCWhdMfJ44GpCJ3nVE8yVXEEEbZ472IdMTff9aAf8qgAd8VZYxWtX8DhM78e5jwYg2WiYgxX92LsqXcETipjL)(SGfgzlBloky2F9N)YF)Z3XQ4wWS1jXX4ssWSiRY5UdZ5RXhMx9Urlju8Jy6H5X4LO8u(H5)W))3pmhE9H5sSipzKqSSruYQC8O4TSrOTPSrvune(XW)HrYCVg4pfLXsb9ogEMiKxc7WCuCmj77GhEaVJn8W8FcXr3zqpC(J3)rGjR58TS7gnAvcFD(cHQps7QUapb1nEYK3oXl27wVjEdbViLSmjf8ZOiEcjJnClfdeVaX9xKIIXHltZP0Dh(TND(R8hbpVbhNWrIJUoNHdjlxgUkk2FSzcyCmkLVw9QxNS0)Qf5lxoS64H5BBi3hTzroBT4oof3jkNZxtjioCRbcgtc3ssY4q4cuuCg)DtDBOge5keLs44RxsIYzLcZXmzdUkgxiIksabOWPhrzjmd6UJZvLxQHWhYipLT3a7gy5Q4mmD1UHPK791opIW4UwSZJCJLMeHdrzXHXWd1YV0HPDgeYqjzS35FJRRI5bXPTiAzOuyv18U0SR5zeHKgdpv)AkgfVtHpOyq7qPjz4qADKRX(EN)uVtO2MuAHRRMOfPesC4YC6Uscue(XdneNQ5GMgwj3glt)4kp29(JVXRhcZPvPzXy23INXDVZ5BcIO0rh)ZeBdLsNOtuFIwUNmLWXIQmaYdFC4yP3d2Tn9EW38Uzx3U6dEHT1(P2Yzh4Ck(bulFVk3iQIXowpAqHmvEVqIYcu0GfAuhcDBmvnxQy14P7L)5ns1Uk1Az7S6nf23GQBjjQsp2aZnFM0yrY8DWZ4RA5NJ2OI)6m7gO1mWwNDHOmAd(tK5GQGuA)2QI4zSzhu8DWvoltwTMh2C1xRQZpIZiBkDefsO432Ms4E)jketZ3Yb)8jhtaORzoHkAeIWHJsHtH4njNjmkymf2q4dMfP44My7A8gcLUgMUTk(wXiP3lIYN0sJGVjdlkHyi)1Kw7F5ZkiL5)yclcdtkyF6fPRumaJ637nhw(9Mz3m8LNrl526pT2KZtsBucxZx)E4(9VeLKF)I9BwvSjdEEqgKwNsKQZ8uYIQFzZ8k36khAEZ09TNvTAneQs3fY40KhWw)mFQmn1bH2gRUPvVjp4Gt7b33k9oThGo6aSWfr(5R0tPktAV8yVlCjlLZ0InQHIJfe(6WXkvG7lTRLLa7TWXuP08gDrTKsZghpRS9)5JhAoHVqbLGzpIPmqEAa2Kc6gRaJOs0sGh)qbMrvLbd(XA4kG)VaEGGzr0eWEsqbZ6ombbCqWA8vIpDhLGJQt1ldMvmhHqTbzmrtgs9Sf3OH4YvQv0bl4f0hSfEzaxOlzdcB)wlXnj0gumyJOoyd2bHaMAlXqDFffH0h4i6pEecT61DmKFKyJEbZ7K1rOke6XBUq9O9nlTUED77CEYLo7(wNpxYN9k22xwv4i)(ZinRpqCCbyC8nsuOdiD8zZG7PQlsGEBh)sSCBFJvdmGds)bcrOlJ96OYibFHAMTkgjDdKKpfOK0ryskmsBJmi7sm6Np3gEfsvFGcBUwfewKvdlyRuWC9jj0N6XMY1pqvoQKQ8tDQMX2ATxG7IQJTB4XuWv9(5NyGSZcpMpjaYC0GRKRM7PRJaCemNtASNegNoKK2cooDbiNcttFQIMAxn3wTAHneE6lepNlgpxiipDWRAx3ohyE6popAa9yaPNIaNTPyuH(5KvJMwWm9oA1mRoQDY05pfRmFr7m3VLM7h6qDjPXDFB7lRVWCX6Q6DURD6hRy91MBVVyh9c54TnnHgukghO4lnUsFgJwNfYsViHmEXmwckqTIGKY4GgqeQBdW1dyEQ(RCrotr)p)Lc1hmauo0GGgm7xXpKKMCyUZ)R6VLNIJd(3p]]
)
