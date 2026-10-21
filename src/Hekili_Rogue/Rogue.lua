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
    20261021001,
    [[Hekili:LR16VQTnu8)w6xye1R45LBxVQ5kT3RtBDtJUVMGjXazeIr2ouHeI)23XopWoyhsGEBNA)sBUo(8(KZJFcVHEV3BAiIJ9E3ObJEy4GrdhmyO3u((TyVPBrbRrlHhsqBG)9hiBMJ4hN19dKpWI2W6fq24iU1(yckuWP5PrX83M4n3itzBXbEt)7)8x(NF6XajV8MUkkmeNraMfyrgpECgFf(4S8Z6VGqX7W0JZcXlqPXW1)U)63podo(4SsgKg1xiqwFkzzkUF4wwF02yw)CA6b)rV)LrsCUd4ofLWIbnoeEMiKwe74muyij5BGhwJ3Z6DC2pI4OhnOfD)J3(EGjR48TSh73FzeFv6CHI3VYvDaEcQw44XVE8GWb3py8GEG)Jswefd(xuapIKW6TLIZCpUZJrHy)fXPu6(7GJ3Mgh7dNp64VD2LFPBF45n4Wios8Q7szyFYIf(ldcDh2aQzCmkMVYoDdlPZfTzEkB1DrlC7opDXIEbPC(kkbX7LUTJGJe)TKOeoe)aDhNWFZeNsQbzTerPeowYaZxVZlcXswNFvGXACyhkjIvvzfSR7lYUujHRtiFi5Gb21XYvXjy6Y9fQYtUvUuaHXDSyKNyjloka7Jsc9dHhkuImVvL3brnuuc7nUJCC0SrHVhrZIMctRG3z2EbpdiK4q4PIJPyu4En(GcbTdfhLG9PfHnDJ8nUtgCbD3KMlCIfenpMqc9xKs3NrGMgC6LgIyfCOIAMl3sZR6RZDBp5oC0GwiSU1knlgZHA8moh6E9MGiuDYXFMylPu5nvjQnrlNlMx01IQ0bsg31BOY5GDBtV78vVB2XPP(GNzBTDQTA2boLIxJQ57v1Ut5mUR1x1rktTZfsuvGIUU8ySp0hYuD9QvSgo5WzNnsPkwM(RAX5NiT0o53srOz(UoMBinU02u5BNZ4REHiL23QEURS5qLEdw71dIYOn4owLd6c6UfKGuwUVUwfzGXEFqz4oVO7IOLR4(Lx9bDDEhoHSjZriLG8VTnXWtUJ1iMMULd(5C9CK1rha6kNDiNgHi6YrXWBH4njLjmkyKfwp4tN5X4WYy7k8gcLUcg6np(MZiLZfr5lAPbWxN(YIjgYKnP1U3(Odkz(7IybyyWHlmrJY9Kd1O)5F5lZ(8ZSVg(g0O5CFX3xBs5rXLAIJ5R)eC)2xXsX5FZopRk24oNhPbP1OSPI0pTuPIdlhF5ENZIpVAYH6ZVwUcIxX79zCA0AS1p4NOstrKOUHUlB)BYn25YUXd1sF36Jsv8cwyLit9LvtUYsFV9Sah4swQUzkkPhuovK4lixSsLV)x4KzrWsoCmvj1VuH0R1uUzYzf1)YiYuXt85m84nDhMYaHwbXNyqbzsiMYaDbE8DsiNYRu699fOEa)VesbVPb0iWOIqEtBo0cECqWw4B(A7AmU5qoi484kCwPJUWCkLu2(3AcYccdTbnINr4iAs2GWbCVfxRc(eAwTrCkSbuHqatSLtOVCJMqAnagThbdHQ9qdd(Ni2ORW8wCneCdHE8QBupQFxuRlKx)wQxCn1MVN65s(Qxk3(6Tch53Ef5ATbuKBavKVsIcnaBKpzgClvDrc0RB4xIzOcySAGbKtAp0jcDz4GgQmkWCONzBavLwaRYhdCvAiWksZ12WdQohJE8RT)NuQvhTWMtwdtgv1WcAmsMxD6IQZ)yt5AhmmNusD(5nvINIWmekJTo9sKA0DSndbhjxR2E)ctIDvi48rbcNtgCUClDpJKgsthg4e8px0yViWpnijTgKFAm0ps7R6qgLLYkVTEXdByc1wqHUwuHUryHAGR1UUDnad1EKHmbnKbSHKrpBt2Odw0fRlnrYSQD5kywrO7Ij2FmwO(M2O(kwPUD4j1K0hNd1TnTX1PLlZwTVEH7)uvSVidaTfTPNZqGTznQG7IXXn(CJe1N642vHf1ZxWJlNftqgYiMtN(rTi6SBEkYciLQ2J3cTvM97KWkaqQo(Om6q(VchDoiTiuk0uH6n9xXRJIJooR7pN)Rks(AV)l]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261021001,
    [[Hekili:LR1wVTTnu4Fl9fpl0aFnUDnioaDy36Ww3WC3RsMwI2wlYIgKuPWag(3(oK6IjPjLLSBAhAFPvHIN7hDU8b7p0)d(ZIqCS)7hny0Rgoy0Wbdg6pJVBl2F2wu4JOvWdPOnW)(wgdXyXPiEmj9W8UFK8rw8gwVqYgpXL3LqqrcgUiloH)Uu)fw5nBlo0F2F)N)Y)8t3HuzP)S1Xrr4C6WSW6L4DhMZxJpmV4S(lju8ty6H5r4LOSe(H5V9V(9dZHJHNm4twCFHwW6tjRYW9J2Y6J2MW6xqAp4p69VmsQ3nGqOOuwcygrWZeHqJzhMJIIiPFh8WJ4DSEhM)Jio6olkt3)4DFayYAoFl7U(9xfZxNTqO)9nUQhWtqNJgp(nJhen42bJh0dCQuYY4eW3JcfQoR3wkgiEbIpDrckchSmjJs3DdC82SKKa48rh(TtU8lN2hEEdokMlDb3KXWbKLldwfgnDydOMXXOe(A30nSIUPOnlYyRVjE50UlYwUSxygNVMsq8EzB7i4ijyljoLdHrq3XP87N4vrniRvikLWXsgy)6DErewY6IRcmwJdpHsJzMkRGDDFr(LQi8XuYht3BHDDCCvCkMUAxPQ8WuJlfsyCphg5rwYsIdXbO0OGi4HsLi3Bz8oiQHItz3pDKNNMnk89iAE0uyAL8o32l5ziHKebpvEmfJI2PXhueODOK4uCaTmSPBK3pDYGZO720CHtSKOfjesuWYm6UCc00GJV0seRKdgQzHCRmpZxx42Ey6WrdAHW6wR0Cym7RXZ4TV7LBcIq1rh)jITIsL3ysuBIwENnVORdvPdKm(uVHkNd2Tl9UZ38UzpVM6dEMT12P2Qzh4mk(runFVQ2DQGXDD(QoszQDUqIQcu01LNGdG(q2QRBwXA4K9NC2iLQy56VQfxCI0s7uClfHM776yVH04kBtLVDoHV6fIuAFR65UWMdg9gC2RheLvBy6yvoOlOBwscZyf(6AvKbw79bLH78IUlJxTMhuD1xPRZpHtjBYDesji)Bxtm8W0XAetZ2Yb)CHEoY5OdaDvZouqJqeD5Oe4Tq8MKXegfmYcRh8PZIeCuvSDnEdHsxddexeFlyKY5IO8zT0q4RZazXelzY206Px)Odkz(pfZcXWGdNzIgL7jhQr)Z)QxM)5NDFn8nOvZ52YVV2KXJtQ0ep7x)b4(TVILIZ)QDEovSXDonsdsRrztLPFAPsLhwn(YTENeFE9K91NFTAneVs2fW404hXo)GFIknLrI6g6UQ9Vn3yNZ7g3xl9DRpkz4fCWkrM6lntUYtFV(Sap4soQUzlkPhuowK4RixSsLV)x4KHn8Hg2yQsQFLcPxRPAZKtkQ)1rKXWt8Lm84p7jmLbc1agOeqbzs4NYbDbE89s4OkQu6)dLOEa)Vesb)zH0yWOIr(ZAo0c(CqWo4BXA7AmU5qoi48ydoR0rxyovskF)Bnb5aHH2GgXZiCenjBq4aU1HRvbFcnR2kofUaQqiGjUYj0xUrtiTgaJ2JGHq1Evdd(hj2QRW(wCneCdHE86RupQFxuNlKx)wQNDn1MVN6Ps(Ixk396Tch53Fb5ATbuKRavKVrIcnaBKpBgClvDrc0BA4xI5OcyTAGfKtAp0jcDz4GgQmkWCONzBbvLwaRYNcCvAiWksZ11WdQohRE8lT)NuQMJw4YjRHjJQA4angjZnNUWC(hxkx7GH5OsQZp)zs8ueMHqzC1PxIuJUJTzi4i5Qz79Zmj2fHGZNeiCoAWfYTY9msAinDyGJW)CwJ9Sa)0GK0Aq(PXq)iTpZHmQkLvDB9IhUWeQTGcDPOcDLWc1axRBD7sagQ9idzdAilydjJEUMSrhSOZwxAIKzMD5kzwzO7Sj2FkwO(Q2O(cwPUD4j1K0hV91TnT11PLlZA2xV09FSk2xLbG2I20ZziW1Sgg4UyDCJV0ir95oUDryr98f84YzXeKHSI50XFulIo72NISesjZE8oO1y2VJcReaP64JYOdf)kC05G0IqzqtfQ)SFf)yCs8H5D)5IFvrYx7)F)]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261021000,
    [[Hekili:LR1wVTTnu4Fl5fpl0aBz7401G4aSHDRdBDd1DVkzAjABTilAqsLcdy4F77qDZK0KYs2jTdPV0QqXZ9Jox(G9g49jVPHio27ddDhE7a3HdCDD9MY3Ub7nDdk4r0s4He0A4FNMoNhJ5B3pR7NjFMfTM1lGS2rCVTXeuOGxZtJI5VpXBUr2Y2Gd8M(X)6x)NF(owb38MUkkmeNtcMfyvo3TFgFfE)SIZ6VGqXpHP7NfIxGsJ57N9d)9FSFgC8(zsSinQVqSS(uYYuC)WnS(OnXS(fu1d(JE)lJK4CnWFkkHfd6Di8mriVi2(zOWqsY3bp8iElR3(z)eIJUZGE09pF)NaMSIZ3WURF)Lr8vPZfQEFTR6a8eu3WrJE3i3q3BCh52d8IuYIOyWpJc4rKewVnumq8CeFY8yui2FrCkLU9A44nPXX(W5d3)7hD53mPp88ACyehjE11PmSpzXc)LbHtg0aQzCmkMVYoDdQOBcA98u2QRJwmP780fl6fKY5ROeeVx6Mocos83qIs4qee0DCc)(XovudYAjIsjCCgdmF9oxfIZyDXvbgRWHNqjrmDLvWUUxLFPkcFmH85KDgyxhlxfNGPl3wQkpmr7sbeg3XIrEGLS4OaSpkj0peEOujY9wAVdIAOOe29tg64OyJcFpIMhnfMwjVZT9sEgqiXHWtLhtXOWTk8bfcAhkokb7tldBQg59tg7EcD3KMlCILenpMqc9xKs3MtGIgC4LgIyLCqtnlKBL5P)6c32dtgm0TfcRBTsZIXSRgpJZUUNVjicvhC8hj2kkLEJorTjA5CY8IUwuLoqY4t9giDoy3207oFZ7MDCAQp4f2wBNAlNDGtP4hr189QC3Pcg316R6KjtLZfsuwGIUUq3BFOpKP666vSgmE3rNnuQkwU(lBXfNKzPDkULKqZ9DDm3qAuLTjZ3ohXx1crsTVL9CNzZbTEdw71dIYOnmzKmhuf01libPScFDTkIRXEFqz4ox1Dr0YvC)QRERQo)eoHSo3rKjHS)22edpmzKcX00nCWpRONwORA2HcAeIOlhfdVfI3KuMWOGrwy9GpDMhJdRITRWRju6ky43I4BbJKoxeLpPLgaFD6NvmXqMSjTEYLp6GuM)trSamm4WjMOr6Ezd1O(5F1lZ)8ZSVg(g0O5Ct53xRt5rXvAIJ5R)aC)2xXsY5FXopRk2OohhPbP1OSPY0pLuPYdRgF5gNJIpVD8U6ZVwUcIxXB9zCA0JyRFWpwMMYirDdDx1(3KBSZPDJ7QL(U1hL08cwyLit9n6jx5PVxEwGdCjlv3mfLudkhks8kYflv57)fozweSKdhtLs9Rui1AnvBMCur9xhrgnpXxZWJ30NWugiunCFIbfKLb1uoOlWJFid6PIkLE)yjQhW)NbPG30aAeyuriVPnhAbpoiyl8TyTDfg3CiheCEKgNL6OlmNkjLV)TIGSGWqBqJ4feoIMKniCa3yX1kHpHIvBeNcBavieWyB5eQl3OiKwdGr7rWqOA32WG)bIn6kmVfxdb3qOhV9c1J63f16c51VL6jxtT57PESKp7LYTVERWr(9NrUwBaf5cqf5BKOqdWg5lMb3svxKa9Ug(LyoQagRgya5K2dDIqxg42qLrcMd1mBdOQ0cyvEoWvPHaRKzU2gEq25y0JFU9)YKQ(Of2CYkyYiRgwqJjJ56txOp)JnLRDWWCqjv5N30m8ueMHqzS1PpdPgvhBZqWjJR6T3pXKyNfcoplq4CWGlKRM7PPddCa(NtASNe4NgKKwdYpng6Nm7tFiJQszv3wT4HnmHAlOqNlQqxiSqnW1Ax3ohGHApYqMGgYa2qzrpBt2Ocw0jRlnoJz6D5kzwzO7Kj2phluFrBuFgRu3o8KAs6JZU62M2460zlZQ3xV09FOk2RYaqBrB6LmeyBwdnCxmoUXxBKO(sh3olSOE5cE8SzXeKHmI50HFulcCJmpfzjKs694TqR2SFhewjas1XhPrhk(v4OYHmlcLcnvOEt)n8JrXr7N19xk(vfL9AV)7p]]
)
