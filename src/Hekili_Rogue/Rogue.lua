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
    20261021003,
    [[Hekili:LR1wVTTnu4Fl5fpj0aFnoDnioa7(6Ww3WC3RsMwIYwZYIgKuUWag(3(oK6IfLjLLStAhsFPvHKNZ57CHKh(b7mW5Jot9rCSZhg2F49d6pCq)(JCMY3Tb7mDdYBfAb8rmAn8V)az9Ce)WmRpr(elCnRRhzTTyv7IiiFHMMNegXFFSZCTkLTb75m9V)ZF5F(Ph8K6Yz6YqFFCQayMNbB8WHz8L4dZYgRxaHI3IPhM5JdqjrWY)U)63pmdg(WScfKe2tyqwpkzrcUN)gwp0MiwVmz6c)r3)LrITVf0offZIae7dFtewlKDygY3Ne)nWhRW7yDpm7hrC0dAqH1F8(pckzjNVH9qVElc5ltMlaEVkl1g0jan)rJE3O((9VR)O(DH4hLeegbXxKhpKeZ6UHItdptMhH8XUbrju6Ud)2jZ)Mj9GVxJ9d5iXu3MWWUKGa3fE(tgOxaghJI4lvx6THbtUzEsqq3SP7MSPq8jO1ZtylfRXsUgVeoFjLG4WQ6iumXDdjmMdjlaO4y(JJTlKgm5ceLs44BdiEjSuJzPxSo34JLMiteWakAAlkoKPb7ww3KUOcbxft(u8EnQRJHLIJX0f7YHYttQSipcJBBWzpQswuOh2ff776dFKdI0OwL5G8gkmM94KH22k(iKS2GOP5tHRLR7uFpxNEesKp8v(WumYFNIEq(a6qrHXyxAE6t1jFCY4(Nb76qUiiMl08icX3niHUlvafeCCsnzSCnubMz2TW9QoDwy7Pjdg2VfgZQwRzWz2xtKXEV1L7cIu1Xa)jMTqYsZuvO2KTSpBDHLbO0bkg32DqPXb)2eU78vFy22UPXGxyFTDWUC1boHIxHQz)A5RKYuSLXP6iTPY4clw2GIRA5ryx4EhDNRx9eRbJ3FYydlDkwk(l7XzJi90ozRQKrtJDD0FH0OcFRSE7CIEvpi6O3Qe5UWlhQC3GPB7fMsRpmzuznOAiLRKRfi91E3hCmCNBSccxSK7wS07vX8wCmzDAGqAb5FBQZHNMmsryAYgoeNpBRdGCf9oKjJWewCuemlKVjjmHtbTUW6cBDMhH9lYTlXRju6sOt3S8BMIknUilFwp1d2D6kpmrtLSoup56BDOuL)2qMhgAC4mD0uADYMAu3(xmz62p9XAypOw35U89xRt4HrfiXw)YFcwF7pXQuW)QdEgb2OoNMPbR1OQP8YpLsP8blAF5o7tYpVD8(6RVwSeYxr7CzCA4kSXn8JlltEMOUMUlU(xxySZ5dJ7RvER6ZsvIcguLOs9nvlUslFV(QaByrgoDtxwsnPC8qIxrH4sN89)IGmleEKdhtlv6xai1ZAkEzYjhQ)6iZujs8Lm94mDlMYaJwHMNiaGmjVsPmTaF(bjptzNu6895uDa)VKAbNPE0qWPcrotBofdoCWWv0Bj90CggocNSbDMk73qaBWgJQyJs3TlwrHWPVexbdg4AOn8s8csmrtQlebG7mK8kXuHIxRLXctuwimWytvhQpZrXiTMkJ2ZLHaA33WK)rH1gk0)EUgsZHahV9kXr9Vk14tZR)9QN9bRn)fRNA5l(55MFORiq(TxqTwBOh5k4h5RKSqdyj5ZMd3sOlkGExd3jMYpG2td0WHs7jrrGLb9Biykr4HALTg(vAbblphmS0qkwKURP2ikhC0gXV07)KwTAtgMcYkSZuggg4LrQ8QDxuTtitGRDeYCeKQ6tTtNbMUPxYzJAGTzC5i1A1R3pttAxexoplK5C0HZSBLWttBg4irqN1zplfqnOiTgoGAmjqs)RAtgfhLvSA1dpmXouBPh6s5h6kjiQbHwZy7sOiQ9CePJKinSejZEM6SrL2OZEU0yPYQElxUYYtDNTW(54P1x1BRVGhx3oMLAs5J9(6ExT2hwlFwB171Zd)hpf7vzcOT8o9sMcm1Rrfgy02UXxAoP(CN3UiwPE5sECzVycXq1Y(KsBJAytQzn61ckIY(11uUMP6p7gj8bhaLa3HqDM(R4vHrHhMz9Zz)gIKt78Fp]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261021003,
    [[Hekili:LR12oUTnq0VL9fxjKf(Y61jnlIxGu0BPOnTOo9vztlrBRAzrdsQnWag(BVdPUysAszj7SjfjVKOLKZmN5cjhEGdge8HGjrioo4931)UxoO)Dd63FyWe(UT4GjBrHRrlHpsrBG)9TmgIXItr8ys6HzEFK8rw8gw3qYgFXI3LqqrcfoploH)U0G5w1nBlomyYF)N)Y)8tpGuvzWKvXrr4C5WSW6T4dhMXxHpmRySEliu8ty6Hzr4fOSe(HzV9V(9dZGHHVm0twCpbky9OKLz4ErBz9qBty9keTl8hD)xgj1)wWiuuklbCJi4BIWOXSdZqrrK0Vd(ynEhR7Hz)iIJEWcy8(J39bqjR48TSh61BzmFv2Cb(7zSuFqNaMJgo81d7h1)((d73fcQuYI4ei2JcfqN1DlfdcphXhppbfHNUijJs3D43oz(xmUh89gCumx613MXWtjlwmDzy04b2fGXXOe(k9LEB8IX3mpBXIUft3nBBL4JrBMNXwjwJNCnHzC(kkbXHv1rOyY0TK4uoKZaGIt5VzKFL0GjxIOuchF7csygl3yE2fRZnryPjkebmGMMEcLgZSGDpVBYxuLGRtjFmDVf11XXsXPy6YDLq5XXglkKW4(oC2JQKLehINIsJMgbFucI8OMXCqEdfNYEZ478918rizTfrZZNcxRu35(EPodjKKi4RYHPyu0on9GIa0HsItXtPLPpDN8nJh1)my3gYfbXsHMNqirtxKr3LlGgcooPLmwPgmGzHDRCpZPlcBpoEWD9BHX8Q1AoCM91ez837D5UGivDmWFIzRKuzgtHAt2Y)S1fEoGshOy8PUdugh8Bx4UZ38HzF)MgdEM912bB1QdCgfVgvZ(v1RKkuSNZP6iTP24clQAqXvT8e8u4EhBNRBEI1Gr7pzS7uoflh)QECXispTtXQumAESRJ9lKgw5BQ6TZj6v)GOJERwK7cVCW4Ubx32lmLvFy8qvnOBiTRKRfi9TE3hCmCNB8weVCfFA1sFPoMFcNs2KhiKwq(3U6C4XXd1eMMTLdX5Z26aixvVdfYimHhhLaZc5Bsgt4uqRlSUWwN5j4OQC7k8gcLUc6cUi)wOiLXfz5Z6PHWUZPYdtSujBd1JV(whuQ8FkMfIHghothnkRt2uJ(2)QjZ3(zpwd7bT6o3xU)AtgpoPcj(2x(JW6B)jwkb)Ro45eyd7CAMgSwJQMkl)0kLkhSQ9L79pj)8Qr7RV(A5kiFLSBkJtJxJDUHFKQmLzI6A6U66FBHXoNpmUVw59QplzefCOkrL6lmlUYlFV(QaFyrooDZwwspPC8qIVIcXkN89)IGm8SE4cBmvP0Vcq6N1u9YKtou)RJmJrK4lz6jyYtykdmQb3pjaazsoNYzAb(89soOkoPm4hkP6a(Fj1cbtcPXGtfJcM0Ckgc4GHn0RIEAoddhHtXGbtK9BiGnyJHg2q5UDXkQeo)L4AyWbxdTHxINrIjAsDHiaCVJKNctfAETvglCrzHWaJCvDO)mhnJ0AQmApxgcO9YgM8pkS1qH93Z1qAoe44vxjoQ)vPoFAE9Vx9SpyT5Vy9ulFXpp39dDfbYV)cQ1Ad9ixb)iFJKfAaljF2C4wcDrb0RB4oXC(bSEAGfouApjkcSmOFdbJcHh6v2w4xPfeS8PGHLgsXI0DD1gHAWXAe)sV)tAvZMmCfK1yNrfgo4LrQCZUlm7eYf4AhHmhbPU(070zGRB6LC2OhyBgxosTAE9(zAs7I4Y5tczohD4c7AeEAAZahjc6So7zPaQbfP1WbuJjbs6FMnzuDuw1Q1p8Wf7qTLEOlLFORKGOgeADJTlHIO2ZrKnsISWsKm75QZgDAJo75sJKkZ8wUsLvM6oBH9NINwFvVT(cECD7ywQjLp(7R7D1wFyT8zTM3Rxg(pEk2xLjG2Y70ZzkWvVggmWyTDJV0Cs95oVDrSs98L84YEXeIHQL9jT2gTWMuZA0Rfuev8RRrTMX8NDJe(GdGYG7qObt(v864K4dZ8(5IFdrYPd(V)]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261021002,
    [[Hekili:LR12oUTnt4NL9gxjKf(46KMfXlqlA)BtrB6pQtVv20s02Qww0GKYlmGHF27qQdMuMuhSZMuKCtIwsoZ8nhi5WpyVbEF0BAaIJ9(WW(dF9G(dh0V)qVP8d7WEt3H83GwbFeJ2c)70Kf8im)WP5optEMfUL11NS1vSUdreuGqxlscJ4Vp2BHr1Y2H99M(x)5V83)8JSmT5nDDyqaovemZ3QDE80C(A8P5zJ1BjHI3JPNMhGxIsI4NM)d))F)0Cy4tZvursypHzz9OKvj4Eb7y9q7Iy9YKQl8hD)hgj29Eq)uumlcWDa8nryVq2P5OGas83bFSbFG1908FcXrpAaho)X7)iOK1C(o2J96TkKVozHa69kTuxqNaCdgn6TJ6h0)H(J63fIIuYYWiioJ85HKyw3Dumi8ceFYIiuaE2YOek9WPF7I5F1KEW3BXbHCKyQ7ty4zKLlNTYpyYaZcW4yueFT(sVpC5K7wKSCz3SP7MSRq8jOTlsyRfRXrUg)eoFnLG4WQ6iumz2osymhsxaqXX83n2TqAWKRqukHJVFjXpHLAmhZI15UaS0ezIagqtt7rXHmdy3X5U0fvi4MyYZXhnOUowwkogtxDihkpnP0I8jmURfN9SkzrH(4zO4GzbWh5GinQvAoiVHcJzVBYqxxnFesw7q008PW1Y1DQVNRtFcjka(kFykgfCqtpOaaDOOWy8mAE6t3jF3KX9Rb7MqUiiMl0Iicjy2Ye6Hub0qW5jnKXY1qjyMz3c3R80zHTNMmyy)wymNkTMfN5yfrg3JoxVlisvNd8xy2cjvMPSqTjB5wBDHJfO0bkg33DGY4GFBd3D(Mpm7620yWlSV2oyRwDGtO4nOk2VQELuMIDSovhPn1gxyrvdkUQfUYEgCVJPZ1lFI1GXhVySHkNILIFvpoBePN2jBvkgnn21X8fsJk8nv925c9QFq0zVvlYDLxou6UbB32lmLrFyYivnOBiTRKRei9nE3hCmCN7CwgUAnFwXsFToM3JJjBtdesli)BBDo80KrActt2XH4CTToaYv07qMmct4WrrWSq(MKWeof06cRlS1zreoOi3UgVLqPRHoEZYVzkszCrwUwp1h2DotEyIHkztOEYT36GsL)(qMpgACOMoAuwNSPg9T)ftMU9ZCSg2dA0DEiF)12eEyubsCnV8NG13(tSuc(3CWZkWg15YmnyTgvnLx(PvkLpyr7lp4Er(5nJpwD91Q1q(k6WmgNgUbBDd)yvzYZev10DX1)McJDQpmESs5DQolvkkyrvIk1xvU4kT892RcCHfz50ntzj9KY5dj(kkeRCY3)jcYSq4roCmvP0Vaq6N1u8YKlou)RJmtPiXxY0J309ykdmAjYEIaaYK8lLY0c85hK8nLDsP3pMt1b8)sQf8M6tdbNke5nT5um4XbdxsVk6P5mmCgozd6nv2VHa2GngvYgk3TlwrHWPVexddw4AOn8s8csmrtQlebGhSK8uyQqZRnYyHnklegySTQd9N5OzKwtLr75YqaTx3WK)zHngkm)EUgsZHahV5gXr1Vk16tZR(9Q1(G1M)I1lT8v)8C7p0vei)(ROwRn0JCd8J8nswObSK8zZHBj0ffqVTH7et5hW4Pbg4qP9KOiWYG(nemkeEOxzBGFLwqWYNcgwAifls31wBeQbhJr8R9(pPvl3KHTGSg7mQWWcVmsLxU7IYDczdCTJqMZGuxF6D6mW2n9soB0dSnJlhPwlF9EnnPDvC58jHmNZoCMDlfEAAZaNjcQwNTwkGAqrAfCa1ysGK(x5MmkokRy16hEyJDO2sp01Yp0nsqudcT2X21qru75iYejrgyjsM9S1zJoTr1EU0yPYkFlxUYYtD1wy)P4P130BRVIhx3oMLAs5J7XQExTXhwlFwB571Zd)Npf7RYeqB5D6LmfyRxJsmWySDJV0Cs95oVDvSs9YL84YEXeIHQK9jT2gnWMuZA0RfueL9RRrTMP8p7gj8bhaLa3Hq9M(R4nHrHNM78)Y(nejN27Fd]]
)
