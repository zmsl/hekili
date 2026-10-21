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
    20261020599,
    [[Hekili:LR1wVTTnu4Fl9fpl0aFnUDjOka7(6Ww3WC3RsMwIYwlYIgKuPWag(3(oK6IjLjLLSBAhAFPvHI87Cv8CoFWEJ9EV38qeh79UjJM8QXJMmA2D35nNVBl2B(wuWJOvWdPOnW)(dKnlr8dl6)bYhyXBydciBCe7AxcbfkqAzwCc)TPElnckBloWB(F)N)Y)8t3hiXYB(64WqC(bWSalY4(dl4RXhwuS2Wicf)eMEyriocLLaB)7(RF)Wcy5dlQailEOqGSHuYQm8WWTSHOTjSHfNza8hd(xgj15gaDkkLLaACi8mriTy2HfOWqs63ap8iEhBWHf)iIJU3Gw0)pE77bqwZ5Bz3pC4Qy(6SLcfFyTT6aycQw40P3nDu4OBhnD0aW)rjrXjG)ffWJjPSbBP4C3J7Yeui2pkjJs3DdS82SKeFy9jh(Tt28lDhcpVbhgZrIxDtgd7tII8xfe6oUfNMXXOe(A7NBC15CrBwMXwFtCKB)LzrrdcY481ucIpiBBpbIe)TK4uoe)aDhNYFZmNQtdYAfIsjCSeaZBV3lcXsOl2kaSgcpHsJz1vwbC9Fr(MQo4JPKpKU3aC9SSvCkMUAxPQ8GBTnfqyChlg5rizjXbyFuAOFi8qPsK7TQ9oiQHItzVXDIJJMnk89iAE0uyALyNB7LygqijHWtLltXOWDA4GcbTdLeNI9PLHnDJ8nUZgDgD3KMlCILhAzcHe6hLr3LFann44lneXkrOMAwi3kZR(RlCBp4oEYOoiS(nknlgZ(g8mo77F5MGiuD0XFIyRoPYBQFOUeTCoBErFlQspiz8PbJvwhSBB6DVV6DZooT1h8mBRDtTvZoWzu8JOg(EvT6ubW9T(QEszQTUqIQcuu1LNG9H6qMUxV(nwJNT)K1MOClwU(RAXfRiT0Ef7srO5(UEMlinTY2uXT3j4QFrKs5Bvp3fwCOwTbR16brz0gCNQIGUGUjIeKXk81nQiJmw7dUgU3l6hfVAn3VARVsxNFcNs2K7iKsq(326y4b3PAhMMTLd(zRTma7VQNHI9kGUphLaVfIZKmMWyGwvydGpzwMGdRIPRXBiu6AOz3I4AbqkRlIUN1cdGVk9LxIyid2Kw7E9TmOKX)umladnmCMozu2NSzg9p7REz(NDM91W3EgnNBl)UAtgpoPstCmV9hG939BQuC(xTZZQInT3PrAqATkBQm9tlvQCXQ2wU15K4ZRNTV58RvRH4vYoFgNg)i26h6ZuptzKOPMTRk7BYn278UX9nE((nhLQ5fSaLit9L1tUYtFV(SahytwUvZuuspOC8sIVGCXk389)cNmlggUHJPkP(vkK(DnvtKCYL6FzezQ5j(CgE8M)eMYaHwJPNeqbzsQLYjBbE8DsQMkUP077lz7a(FjvcEZdOXGrfJ8M3Ekf84GGTGBX46Aa3EQgeipTgYkv0fMtLKYN7wtqwywOlSq8msdrBYgeoGBT4Av4LqZQnYpHnckecyMTCc9HA0esNjUO7mxiuTx1YG)XdB0vyE6TwsQHqpE9vQhnpdQ1bXBE60ZoEA7Np9ujFXdJBFSwHJ8BVGCTUqgYvWgYxjrHwWjYNmdUJQUib6Uw(LyoBagVnWaJjDNYeHUmEulvgf6n0ZSnWMshOt5JbFkTKqfP5AR5bvNJrp(Lw)tk16TwyZjRXfJQAyHfgj417UOE)p2uUUr)YrLuhpV5s(EeMHqzSvPxYqJUJTDm3ir1w59IrHpBRzxeLoFu40rQ(TTfGJK(Cwl6S090IuZg47P1e(iTV6TwuDbw1U1VYWgtqDLkOlLlORKmOw4ATRBxcDqDNpiteczGriz0Zw)m6ueD2BJMjbRETTsWkdDNnX(JXy0x1C0xWG0DJfP2K(4SVPzOnoeTCe26vZlD)hVQ6lYaqx5y65meyRdJASTySjJp38p9PoUDrmq98f84YoWehdzKPPJ)eweSfzU3XsIKQxJ3YzR1X3rHvsBut4O06qXV5gDeKwekdkQq9M)R4hJtIpSO)px8Bis(AV)7]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261020599,
    [[Hekili:LR12oUTnq0VL8IRfYcFDDs3frlqk6Tu0MwuN(QKPLOTvxzrdskhyad)T3HuxmPmPSK9UjfBEjrlf5mN5I4mZb2BO3N8MgI4yVpoAWO3mCWObtU7oVP8DBWEt3GcEeTeEibTg(33ZyiglkbXJijhM19ZKpZIwZ6fqw7i28UyckuiW5PrX8pK4n3OSzBWbEt)7)8x(NF6EKQi9MUkkmeNDomlOEnE)Hz8v4dZYxR)ccfVftpmleVaLgZpm79)1VFygSm8uf5Kg1xGcwFkzzkUF4gwF0Myw)8J2d(JE)lJK4CdOekkHfdMri8mrO0i2HzOWqsY3bp8iEhR3Hz)iIJU3ay6(hF4tGqwX5By33V)Yi(Q05c83VYwDazcyoC847gpiCWTdgpOh4uPKfrXGVhfiGoR3gkgo8Ce3DEmke7VioLs3DdS8M04yFy9rh(Tt28RD7dpVghgXLUGBszyFYIf(ldcDh2GtZ4yumFL9ZnS8CUO1ZtzRUjAHB35Plw0liLZxrjiEV0nDesK4VHeLWHWiGDCc)DtCkpnORLikLWXsbyE7DEviwk68TccwtcBrjrSQGviUUVkBtLh8XeYNt2BqCDSSvCcMUCxbuEWTYMcimUJfJ8OizXrbyFusOFi8qbiY8wvEhe1qrjS35oYXrZgf(EenlAkmTczNz7fYmGqIdHNkwMIrH70Kdkeqhkokb7tlcB6g57CNm4my3eYfoXIdnpMqc9xKs3LDaneC8LgIyfsOcmZ1BP5v915UThChoAqluw3A1MfJzFnEgN9DVCtqeQo64prTLNu5nvpuBIwoNnVORfO0bsg32BOY6GDBd3D(M3n740uFWZST2oyRMDGtP4hr189QA1PCb316R6i1P26cnQQqrvxEm2hQdz6E9Q3ynCY(twBKYTyz4x1IZxrAPDY3LIsZ8DDmxqACPTPk3oNix9lIukFR65UWIdvQnyTwpOkJ2G7yvjOROBwqcsz5(6AbYaJ1(GRH78QUlIwUI7xU13OJ5T4eY6mhHudY)2whdp4ow7W00nCWpBTLby)L9mKVxHO7YrXWBH4mjLjmgOvfwp4tM5X4WYy6k8AcLUcAeopUMliL1fr3ZAHbWxL(YlrmKbBc1UxFldkz8BJybyOHHZ0jJY(KnZO)zF5lZ(SZSVg(2ZO5CBX3vRt5rXLiXX82Fa2F7VPsX5F1opRaBCNtJ0G2Au2ur6NwQuXILTTCRZjXN3ozF95xlxbXR4D(mon6rS1p0NOEMIirDnBxw23KBSZ5DJ7R98DRpkvXlyruIm1xxn5kl996ZcCGnz5wntrj9GYXljEb5IvU57)fozyYEOqnMQK6xci97AkNi5Kl1FzezQ4j(AgE8MUftzGsRq)tmaqMK2PmYwGh)OKgQ8Bk9(Hc2oG)xsLG30aAeyuriVPnNsbpoOylYnFCDnb3CQgesECfjRurxyoLAkBUBnfzHzH2WcXZinenjBq4aU1IRvHxcnR2i)e2iOqOGj2Yj0hQrtjTM4I2ZCHaAVPHb)Jh2ORW80BnKudboE7vIJ6Nb16G41pD6zhpT5ZNEQMV4HXTpwRWr(9xqUwBid5kyd5BKOqd4e5lMb3sOlsGURHFjMXgGXBdmWys7PmrGLHdAiyuO3qpZ2aBkTGoLNc(uAiHksZ1wZdQohJE8lT(NuRvBTWMtwJlgvyyHfgPWR2Dr1(FSbU2r)YrqQlpVPs(EeMHam2Q0lzOr3X2mMBKs1w598rHpBRzxeLopjC6iHFtBb4iPpN1IolDpni1Sg(EAmHps7RARfLxGvUB9RmSXeuBPc6s5c6kjdQbUw7y7sOdQ98bzIqidmcjJE26NrNIOZEB0ePWQwBRqyfHUZMy)umg9vnh9fmiD7yrQjPpo7RBgAJdrlhHTA18c3)XRQErgaAlhtpNHaBDyuHTfJnz81M)PV0XTlIbQNVGhx2bM4yiJmnD8NWIGTiZ9owqKu1A8woBLo(oQScAJQtokToK)BUrxcslcLcfvOEt)v8JrXrhM19NZ)nejFT3)b]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261020562,
    [[Hekili:LR1AVTTnx4Fl9lEwOb(AC6AqDa2W27wh26EXC3xLmTeTTwKfniPsGbm8V9Di1nsAsBj7M2H2V0QqXZ9JoxEG9h6)r)zrio2)dJgm6UHdgnyYDJ8NX3Tf7pBlk8r0k4Hu0g4FNLTGNG57omV7ZKNzXBy9cjB8e3Bxcbfj41IS4e(7t9xyLTST4q)z)1F(l)9pFpRGB(ZwhhfHZjbZcDkN7pmNVgFyEXz9xsO4NW0dZJWlrzj8dZ)H))VFyoC8H5kSilUVqSS(uYQmC)OTS(OTjS(fu1d(JE)dJK6DdWFkkLLa6De8mriVy2H5OOis63bp8iEhR3H5)eIJU3IE09pE)hbMSMZ3YUVF)vX81zleQEFJR6b8eu3OXJF74brdUDW4b9aViLSmob8ZOqEmjL1BlfdeVaXNUibfHdwMKrP7UboEBwssaC(Od)2rx(1t7dpVbhfZrIxDtgdhqwUmyvy00HnGAghJs4RDt3Wk6MI2SiJT(MLKWmgCP4Lt7UiB5YEHzC(AkbX7LTTJGZKGTK4uoejbBaNYF3eVkUaYCfIsjCSKb2VENxfHLSU4QaJ14WtO0yMPslyx3xLFPkcFmL8C6ElSRJJRItX0v7kvLhMACPqcJ75WiRzjljoehGsJcIGhkvICVLX7GOhkoL9UPJ880SrrmarZJQctRK352EjpdjKKi4PYJPyu0on(GIaTdLeNIdOIWNGx6g57MozWz0DBAUWjws0IecjkyzgDxobAAq9lTeXk5GHAwi3kZZ81fUThMoC0GwiSUNuAomM9NWZ4TV7LBcIqvTJ)iXwrPYBmjQnrlVZMx01HQ0bsgFQ3qLZb72LE35BE3SNxt9bVW2A7uB1SdCgf)i6eFVQ2LQGXDD(QoszQDUqIQcu09f6Iha9JSvx3SI1Wj7p6SrkvXY1FvlU4ePL2P4wkcn331XEdPXv2MkF7CeF1leP0gx1ZDHnhm6n4SNpikR2W0XQCqxqh3t3LImWAVpOmCNx1Dz8Q18GQRENUo)eoLSj3riLG8VDnXWdthRrmnBlh8Zf65iNJoa0vn7qbncr0LJsG3cXBsgtyuWilSEWNolsWrvX214nekDnmeCr8TGrkNlIYN1sdHVodKftSKjBtRNE9JoOK5)umleddoCMjAuUNCOg9p)REz(NF291W3GwnNBl)(AtgpoPst8SF9hG73(kwko)R255uXg354iniTgLnvM(PLkvEy14l36Du85nt2F68RvRH4vYUagNg)i25h8tuPPmsCQHURA)BZn258UX9NK(UNokz4fCWkrM6RntUYtFV(Sap4soQUzlkPhuQls8vKlwPY3)jCYSyyjhoMQK6xPq61AQ2m5OI6FDezm8eFjdp(ZEctzGqnW)jbuqMeYPCWxGh)GecQIkL()O)SqAmyeXi)znhkHsmtG)xciH)m5ubcMZbvWqcL3TybEnr2CWheCESbNv6TlKDLKY3extqoWAOn4s8ccmrtYleoGBD4AvqQqZQTIyHlilecyIdbySMJMqAnugThldHQDxdd(1eB1vyFFUgcZHqpEZvQhNERuNRMF69vp7cRnFJ1JL8fVEU7fDfoYV)cY1Ad8ixb(iFJefAakjF2m4wQ6IeO32WVeZXhWA1alyO0Eque6YWbnuzua8qpZ2c(kTaGLpfiS0qiwKMR5ye1v9QDow94xA)pPunhTWLtwdDgv1WbUmsMBoDH5KrUuU2bitTsQZp9zOg6QtVeZgDhBZWYrYvZ27NzsSlclNpjG5uBWfYTY9msAinDyGAGGoRXEwiGAqs6jWaQXGajTpZHmQkLvDB9IhUqhQTWdDP4dDLae1axRBD7sGiQ9yezdKilOejJEUMSrh2OZwxAIKzMD5kzwzO7Sj2FkwT(Q2T(cwUUDil1K0hV9NAVARlwlxM1SVEP7VUk2xLbG2I70lziW1SggiWyDCJV0ys95oUDrOs9Yf84YzXeKHSI(u9pZfrND7trwcPKzpEh0Am7xTWkbq6u8rz0HIFxo6CqArOmOPc1F2VIFmoj(W8U)VIFNrYx7)V]]
)
