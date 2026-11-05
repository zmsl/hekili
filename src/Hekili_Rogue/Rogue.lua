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
    20261105000,
    [[Hekili:TV1wVTTnu4Fl5fpj0aFjjUTlika7(6Ww3WC3RYMwIYwlYIgIuUWag(3(iPUrYqQB2PnRn9HgfrYZ1pkE45dXDI7hCN5diq33F14RE9KjJNoE8y3zK9BHUZ2c8EaSI(qmyd9))b0MLaYXfwFe9rC4g8qp0gB2S2hHa(mjTmnmI8Uy3LAfkEl0ZD2F)N)Y)8t36XLL7S1H((WSfaXEg0XThxqwdpUi)DJcqjWDWKJl8HbG0i60)U)63pUG(6JlkfqA4iMcXJsqRsHJ83Ihb2gHhLVMH0Fz4)IrX2xsLEcighrTyF6ZiM2cXhxa89rXFd9HhG7XdpU4hbeWTAScR)4DFGkK1eYw8TJgTkKSoDjZWhPmvBQmPMg8Q3EZvbJbV5T34pKg)sqbHr04lWJeIIXd3MaZcpolJa(W5brPjj7p(BpA8x5mI(8gOFibWg6YumCokiy(kpFNj6xaMabrK1Yt9YWaNlwMgemmF4HPBlxUdyZYu8A2CS4ZXlLqwNGae6SgWemA(wuymHMSOgkmMC3u7Yvtv5kqscIaVma5LIZuML(Ln4cFixf5lHQajjTdehI1y7wwxKnPYf(qm6JXh0iUbgMkmgMSA)Wi09okJ7HWeBd(zL0WrHEW5Gy)5(0hk0FwatzmAkdegJVZ5kBBj3JMN2csYsLmVQq2zUDHm9qOiF6tfVobc83ljhGp16arHXW5jfzUs)7oNPJBWS1z0SqxXIGrPXq88OWvRjzlPCOLriK)8G0K9zdizxvdwxkuX6ZTPsVwD4m3FGLbdOYvvhPsKcJKjTkXPXvTmhgQeP0yLcTpr9gZSg9CkCA3WjcV3(GXGXGxI)MI)SfEMcopd8gr0KOy1SJ8cRADAZ2Dn2ffcEQXYEgW6z8Q1B)0KBZ3akoIWwqTGHxc52z74AxK4j2F7Mz36J66T1XRB4ENjtUPt7Jp3Qlnb(aqJIkqj8XZH0v4JS3YdXdAWMQn3pGNauhIMbAyzn6OQMQFAwTynj4awCFErvDnPgfGc7QgKi4CAD36kksOSTjtpOnclmLRekivCozy283WXQd0xb(16vXJwUmuV6sks4TEwsSsfXMUEdtvA9bNRfLGSIKUdsTgYyTv8t3mm4cl5eUZRLT5DWy0MSabxd8F30vLU35APfNKULqJZnExj66kVSu(AyQWIaIOJoKSgLIzof9UA4Huy4YiOFzUDnCdkjzn9Q9553Cbj8EwwUrp1JI0NZ)sNgORoR250VWKaaFxi2ds3IA(kCctj7wC1Dsww2sAGhvWuP8Y2DQpZq3NQ15VzqUY3KscJkTBB9t)E687(brcPQtouB0WUEWJXfuT1kSxbyvc4v8YYJCUXwmB(MPhQhiUAnn7gTFoMKe(a04xgMkUMIKqDTJOS4oDrWbnhbpu76TQpbvfamifgK(vQqkoo)mK7TPtYWxavYn2goZPnNKOFsxOTObdt2sV21lctM6PvI0DoglDG)pryx13y)Ya4jCMXlqVN3qpCymTwtyIWNjl1U8rsLTZ7rvk8)E8Qsq4fq7ZsqR7SDWem9fkuifrZDyoNvzS4qF89CoSYlZW97lOrH(toTfUZ8scP57qG7S2tFHlHQyf5kiN2ZErL5K)s3z8s7zMnvhxROdHYOzZOCXzT6xYgkZbY8y0fopEAi9On7wy((ngYBcSGi5WfkvInet0HWuWutadzuPKs6cnjNvEsyg8RBjAOAX6re63v2CBVmyB10c)NIE4FsT92y35yX330daHXGIg2vob6v(6o50ckwADa6zHdXqBVTL7Mf1R8h8QTTJhQHnG6BpEJ9hV5yDFdO9nEYdOF7jS9TTSZCs0Z8vvgPfK08jZP7OPZattg3YTNgoST)MUaRkCdrT(1U)DIZMPOwYRrtHx1UKrua)eVQrV4(PVK)80X(Z5M(hEOUTv(lWpK8h2KzgQ)ud1bUHA1vuZ9ptv3lYwKwuCFVtbxRQL8BkQkXRKOzyGrjUWvlpx9ILMmUUrLuLrklp5looXuTSC2MKdSCJRrwO4svTMLgUZBVyH6SqdvLdNRxLWJATcMacvuy1OZ2i5vTaKkShuL9QtL(kt8xXBLH6HDLFiVudYFCXeXwDLzR(sT1jYTvlYeMTT(WUv3P3sHFlneCXtCMAULmJxn(fSPCHPE8EHWkYAnUf4C0P3tQvVDRxVDJuS2aASpuxBEBxFEB1POgMLPo92Pw92TE92uZEBS(YM62lhAQwoub0S6SGV0aNDL4SxGNFgHNMQMvHnjTf0(5MATpHy6ErU2la7pBaBc)MqS4kOwQ0KU0MgQXA31S6aFx5)zijUFs9VpjU5tDaqkTKSe3z)k8HWOWJlS(58)yR4d7(F]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261105000,
    [[Hekili:TV1wVTTnu4Fl5fpj0aFjjUTlikaDy36Ww3WC3RYMwI2wlYsgIuPWab(3(oK6gjdPUzN2S20hAuejpx)O4HNpe3jUF0DMpIID)WfJV41tMmE64XJDNr3Vd7oBhY7o0A4Hi0w4)FhHGiKGienio6WcRpf)jsWwYqV4T2SjVpmg5Ze4Y0Gq67JCxQv2KDyp3z)9F(l)ZpDnsuKUZ2e47JZwhM4vVgV(Wc6g8Hf5VB0Q4e894Kdl8XRqPH0dlE3F97hwaVgEsroPbJywbzus86u8i)DKrODHKr5lDi8ld)xsCK95GssqrKqWn8HNJzknGCybY3po67GhUdVNm8WIFerrxRXyS(J3)rqiBO0DKRhnADaDt6sM9pszQ2GmbBgFXBV6IvJrV5Tx5pecQjXRccHypYJz6KH7sWWIxIOoldr(45Rctts2F43E04VYze88wSFaL71NNsWZJxTA(ApFNj6xaHIrH0nYt98GvoNTmD1QH5dpmDx5YDqBxMs2WMJfFoEPu6MKyefM1aMGJNVloiIc5mWqXr0BMAxUAqLRrjjXu85RI9sjzkZs)YgCMpMRI8Lakqss3JIciASDlRZYMu5cVlk(trpOrCdmmvCeoz9(HHX36OmUxmHABWpRKgjmWdphf5p3hEOq)zbmLXGugkiICJZf22sUhKN2HsYsLmVQq2zUDHm9IJd9HNkEDcg5VxsoiFW6qHbr45jfzUs)7gNPJBWS1z0SqxXIWHPryY8WG1BOzlPCOLHXX(ZxLMSpBaj7QAW6sHkwFUnv61QdN5(dSmyavUQ6ivIuyKmPvjonUQL5WqLiLgRuO9jQ3yM1ONdWP7hor492pymym4L4VP4pBHNOGZZaVrenjkwn7ipZQwN2SDxJDbqWJnw2ZawpJxTE7NMCB(gqXre2cQfm8si3oBhx7IepX(B3m7wFuxVToEDd36mzYvDAF8PwDPj47qAuubkHpEoKUcFK9wEiEqd2uT5(b8eG6qqgOHL1OJQAQ(Pz1I1KGxXI7ZlQQRj1Oauyx1GgINd1DRROiHY2Mm9bTryHPCHqbPIZjdZM)gowDG(kWVuVkE0YLH6vxsrcV1ZsIvQi201ByQsRp4CPOeKvK0DqQ1qgRTIFyZWGZSKt4oVw2MVhhfVnlqW1a)3nDvPBDUuAXjP7OqCUX7kbRR8Ys5RHPclkkegDiDtCkH5uWD1idby4YqSFzUDdEBCsYg4A)553Cbj8EwwUrp1dq6Z5FPtd0vNv7C8xysaGFFaXddBrnFfoHPKDlU6ojllBjnWJkyQuEz7o1NzG9PAD(RgKR8TP0GWs72w)0VfMF3pisivD0HAJg2LdEmUa0wRWEfGvjGxXllpY5kBXS5BM(q9aX1BGSB4(5eAsWDyJFzyQ4Aksc11oIYI70fbh0Ce8HAxVv9jOQaGbPWG0VsfsXX5NGCVnmjdFbuj3yB4mN2CsI(jDM2Igmmzl9AxVimzQhxjs34yS0b()eHDvFJ9RdGNWzgVa9EEd9ibrqTM4eHptwQD5JKkBN3JQu4)94vLGWlG2NLGw3z3JtiWlu4vkeYDeoFwzS4ap(bo)w5Lz4(df0Oa)KtBH7mVKaiFhGCN1E6lCPGIvKRGCAp7fvMt(lDNXlTNz2GoUurhcLrZMr5IZA1VKnuMdK5XOlCE80q6rB2TW89RmK3eybrYHluQeBiMOdHPGPMagYOsjL0fAsoP8KWm4x3s0q1I1Ji0VRS52EzW2QPf(pf9W)OA7TXUZXIVVPhacJbfnSRCe0R8TDYPfuS06a0ZchIH2EBl3nlQx5p4vBBhFOg2aQV94n2F8MJ19nG234jpG(9hX232YoZrrpZ3uzKwqsZNnNUJModmnzCl3EA4W2(B6cSQWne16x7(3jozMIAjVgnfEv7sgrb8t8Qg9I7N(s(Zth7pNA6F4H62w5Va)qYFytMzO(tnuh4gQvxrn3)mvDViBrArX99ofCTQwYVPOQeVsIMHbgL4cxT8C1lwAY46gvsvgPS8KV44et1YYzBsoWYnUgzHIlv1AwA4oV9IfQtcnuvoCUEvcpQ1kyciurHvJoBJKx1cqQWEqv2Row6RmXFfVvgQh2v(H8sni)XfteB1vMT6l1whj3wTity226d7wDNElf(T0qWfpXzQ5wYmE14xWMYfM6X7fcRiR14wGtrNEpQw92TE92nsXAdOX(H6AZB76ZBRof1WSm1P3o1Q3U1R3MA2BJ1x2u3E5qt1YHkGMvNf81g4SReN9c88li80u1SkSjPTG2V0uR9zet3lY1Eby)fdyt53eIfxr1sLM0L20qnw7UMvh47k)pdjX9tQ)9jXnFWbqPqjzjUZ(v8DbHbhwy9Z5)XwXh29)(d]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261103000,
    [[Hekili:LR1AVTTnx4Fl5lEsOb(wIB7cQdWg2E36Ww3lM7(QKPLOS1ISObjvcmGH)TVd1vsgszj7MwS2V0klYZ9JoxEq8M49rVfHio27dthp91tMm(MXJh7TGVFh2BXouWdO1WdPOTW)UiBfpbZ3FCPZtKNyXBzddiBDf3BFcbfk41QS4e(7t9wzKTSD4aVf)1F(l)9pFhRKBEl2ehgIlibZcSkN7oUKVbFCz57gfrO4hX0JldXrOSe(XL)W))3pUeE9XLsSilEKqSSruY6m8OWDSrODjSrLune(XW)HrsDVg4pfLYsa9oeEMiKxm74suyij97GhEaVNn84YFcXr3zqpC(J3)rGjB48DS7gnADmFt2kHQps7QUapb1fp9T3onAm6nV92WHGxKsIIta)mkGhtszd3rXaXRq85RsqHy)OKmkD)XF7zN)Q5JGN3IdJ5iXrxNXW(KOi)1bHZNyMaghJs4BuV61XrZVAvwu0WYJhMTRM85OTRYyBe3Xj)obzC(gkbXHBnqWyI)osCkhcxGIIt5VBMBn1GixJOuchFDejiJvimhZKn4QqCUikjbeGcNEeLgZmO7ooxvCPAcFiL8u6bdSBGLRItX017hMqUFU25beg31ID2WnwsCa2hLg6hcpuj)chM2zqidfNYE38PUUkMheN2HOfHsHvvX7cZUINbessi8u1RPyu4Ef(GcbTdLeNI9PvrUA77DZNn(eQTjLw46QiAvcHe6hLr3xqGIWBo0qCQIdAAyPCRTm9Jl9y3pFY0X9qyoTknlgZHw8mUhCoFtqeLAC8ptS1ukDIor9jA5EYuchlQYaip8XHtKEpy3207bFZ7MDD7Qp4f2w7NAlNDGZO4hqT89QCJOsg7y9Ob5Yu59cjklqrdwOrTp0TXu1CPIvtMDq(NtLQDvO1Y2z5BYTVbL3ssufESbMB(CtTfjZ3bpJVQLFASrf)1z2nqRzGTo7crz0gMFJmhufKs73wvKXgB2bfFhCLtu86nC)6R(AvD(rCkzBHJixc5)22uc3p)gfIPz74GF(KJja0vpNqjncr4WrjWPq8MKXegfmMcBi8bZQeCyDSDdElHs3at3wgFlzK07fr5tAPbW3K(5LqmK)AsRNF5ZkiL5)ymladtkyF6fPRKpaJ6371hw89Mz3m8LNrl52QpT2MXJtQvcxZx)E4(9VeLKF)I9BwvSBg88GmiToLivL5PKfv9Y65vU1vo08MzhApRA9giuLS3NXPXpGT(z(mzAQccTnwDDREtEWbN2dEOv6DApa14aSWfr(5R0tPksAV8yVlCjlLZ0InQHIMccFD4yLkW9L21YIH9w4yQuAETUOwsPEJJNv2()8XdnNWxOGI3IhXugipnaBsaDJLJrubAjWJFihZOYYGE)yfCfW)NdpG3IaAmypXiVfDhMapoiyn(kXNUJsqJ6u(sVf5ZriuBqg3OjdPE2IButCXk1k6Gf8c6d2cVmGl0LSbHTFRL4MeAdkgSruhSb7GqaZSLyOUVIIq6dCe9hpcHw96ogYBi2OxW8ozDeQcHE8MlupAFZsRRx3(oNNCPZUV15ZL8zVIT9LvfoY3EgPz9bIJlaJJVrIcDaPJpBgCpvDrc033XVel223y1ad4G0FGqe6YKXDuzKGVqnZwfJKUbsYNcus6imj5gPTrgKDjg9ZNBdVCPQpqHnxRcclYQHfSvYzU(Ke6t9yt56hOknkPk)uNQzITw754UO6y7gEm5CvVF(jgi7SWJ5tcGmngCPC1CpDDeGgWCoPXEsyC6qsAl440fGCYnn9PkQRDvFB1Qf2q4PVq8CUy8CHG80bVQDD7CG5P)48Ob0JbKEYdC2MIrf6NtwnAwoZ07OvXSQO2jtN)uSY8fTZC)wAUFOd1LKg3dTTVS(cZ5RRQ35UYP3uX6Rn3EFXo6fYXBBAcnOumoqXxACL(mgTolKLErcz88zSeuGAfbjLXbnGiu3gGRhW8u(x5ICMI(F(l5QpyaOmObb1BXVIFioj(4sN)x5Flp5h79Vd]]
)
