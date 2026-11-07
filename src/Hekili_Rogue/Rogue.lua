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
local RIPOSTE = { 14251 }
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
    -- The poisons (id-less): up while either weapon carries one of the ranks' enchant IDs (DB2 70707, Effect 360's misc
    -- value, lowest rank first), read from the client; 30 minutes (the effect's 1800 s; in-game check L37).
    instant_poison = { enchants = { 323, 324, 325, 623, 624, 625 }, duration = 1800, max_stack = 1 },
    deadly_poison = { enchants = { 7, 8, 626, 627, 2630 }, duration = 1800, max_stack = 1 },
    crippling_poison = { enchants = { 22, 603 }, duration = 1800, max_stack = 1 },
    mind_numbing_poison = { enchants = { 35, 23, 643 }, duration = 1800, max_stack = 1 },
    wound_poison = { enchants = { 703, 704, 705, 706 }, duration = 1800, max_stack = 1 },
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
    -- Riposte's window: the game opens it for 5 s after a parry and answers Riposte as usable only inside it. From the
    -- plain usability read like Cutthroat's (the player aura walk is secret in combat); the way Warrior's Overpower and
    -- Revenge windows are modelled.
    riposte_usable = {
        duration = 5,
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
local riposteAt, riposteOpen = 0, false
local function riposteUsable()
    local r = knownRank(RIPOSTE)
    if r == 0 then
        return false
    end
    local usable, noMana = IsSpellUsable(RIPOSTE[r])
    return usable == true or noMana == true
end
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
    local p = riposteUsable()
    if p ~= riposteOpen then
        riposteOpen = p
        riposteAt = p and GetTime() or 0
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

    -- Riposte's 5 s from the parry (the usability flip's time), else its window with no known end.
    if now == query_time and riposteUsable() then
        if riposteAt > 0 and now - riposteAt < 5 then
            applyBuff("riposte_usable", riposteAt + 5 - now)
        else
            applyBuff("riposte_usable")
        end
    end
end)

-- A finisher needs a combo point (its `usable`; with `ladder = false` its answers are no energy rungs, C9).
local function finisherUsable()
    return combo_points.current > 0, "requires combo points"
end

-- A poison reminder (C4): the best of `items` in the bags, offered while one is there; its use (a 3 s cast, DB2) puts
-- its own aura `key` and the pseudo-aura `slot` names up for 30 minutes in the sim. The belief has no `now` for it (an
-- id-less item use never reaches Build(def)): it reads the client (Sources/Enchants.lua), in combat too. Upstream
-- retail's `essential` and `nobuff`: a precombat line is prompted in combat while the poison is down. Under the Potions
-- toggle: a buff consumable (user ruling 2026-10-21, as the shared mana and energy ones); with Potions off the
-- reminder is skipped.
local function poison(name, items, slot, key)
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
        cast = 3,
        cooldown = 0,
        gcd = "off",

        item = best,
        items = items,
        bagItem = true,

        startsCombat = false,
        toggle = "potions",
        essential = true,
        nobuff = key,

        usable = function()
            local _, have = best()
            return have, "none in the bags"
        end,

        handler = function()
            applyBuff(key, 1800)
            applyBuff(slot, 1800)
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

    -- Combat talent (DB2 14251: 10 energy, 6 s cooldown, off the global cooldown, 5 yd, a strike that also disarms for
    -- 6 s). Usable only in the 5 s window after a parry (buff.riposte_usable, from the client's usability answer, as
    -- Warrior's Revenge). On no built-in priority (L91): a custom priority adds `riposte` itself.
    riposte = {
        id = 14251,
        cast = 0,
        cooldown = 6,
        gcd = "off",

        spend = 10,
        spendType = "energy",

        startsCombat = true,
        known = knows(RIPOSTE),
        buff = "riposte_usable",

        handler = function()
            removeBuff("riposte_usable")
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
    instant_poison = poison("Instant Poison", INSTANT_POISON, "main_hand_enchant", "instant_poison"),
    deadly_poison = poison("Deadly Poison", DEADLY_POISON, "off_hand_enchant", "deadly_poison"),
})

-- The hand-built lists this file shipped before the wowsims.com packs: a saved choice of one falls back to the spec's
-- default.
spec:RetirePacks({ "Combat", "Assassination", "Subtlety" })

-- The three priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those
-- and run it, never these blocks (tests/Forever/rogue_spec.lua checks they match). Pick one with
-- /hekili priority <name>.
spec:RegisterPack(
    "Combat (wowsims.com)",
    20261107000,
    [[Hekili:TR12UnUnq0VL8IRn6cFjx2DBqua69UfTBlQ3(QKPLOTzJSOHivsnqG)27qQBKkK6MDAxG69HnkIKZCMZqsnZbXDM7NCNhG4y3pE50lF7SztF30PtDNZ3Vd7oFhY)b0A4Hi0w4))w62Li(HfdFI(eJSLn2NUDKyw7dPOaHLwMqc5FiYDPrJY2H9DN)h)2p(NF)T(sB5oFdjiaNUamZ3IpU9Wc(g8HfzVBYkAm(rC8Hfb4vOKqy6F9V)lhwaV(WIcdKqMiCiBsmDDcEsWo2e0Uq2KS1mg(LX)fJgn6nG1JrrSqaXbWZuH3iSdlqbb0OVaE4b8E24dl(oehDRbum8x)WNaJSHZ3XUDYK1e(MKLcGpPYuhb2eG21lNo9QPORVEj(YXa)ftxrcb(f5Zj0i24DX4u6Xzzika7TkmjoE)HF(fJ)LotGN3IdiCKyO3KWWE0vR8w7h4mRyboXKDughRp8Bwr9tyWpjRCwMSA14Sz5LWqldXJt2nahHJxVFCi9ENutLphi4y8c7dWynkoMcEqXMdfyK6TJsI4qAecbCe)UBgCraw6USLa(zKQLEefryBQavH5gErggYx4dr0NIE2G5gyzQVmCYhxeoJgybWCYw89oZ0qjq77qXPKUaC5omf95qZNsddGNYFDmgfSxZoldP0aVvjX7neX5gvDxqMPhADObs2q79aL0ENwNxlIhTXsJQbfll34PlQINlxxQ3SSQbab)44zkVF0ZkiRYKp9GEKYMOoAt14ffa7HqHKiSxCcSRweYf7cVZ5MPLEHfs8XEOOaVa4Hm)iZLvgrSbpFr4WKimZlKSEdpJlSrs9yhqf0xn2RoCgLAnLAn)PsNfJKATsZziuhANgknP2yfgTpSEJz2t9M5Z8Vo)lw4jIC(miAu3nPAwtFiyyTbTDCxdUGTGhlx2tcRN8vRp(zi3MDauDeLJGg3mCMYhLEIRDmXRC82ny3LJw9fFBrKiguw4SR1Dxsm(bKbhLN4KJNTlRmLL(wzupObmvB6iT6VQdbKsdlRXaTkudssR(TjdVsW7Ezw5UMCtLCNOnmEi2JJnXOQvsn7MNnYWkt5YBg9S(VoWClkxz2usMn7nVyxwnTHjWQr)4CLQfIt2XbJR1bfhfctC8g8wAC8gOt8XaPb9MfySvL7DUQO5QmRjAI7IH65aN3c1pMz5vHONcXmMh(VX(jPXCQh0Io9ZyAq00zWcpn1coNzcuAE0h2N4jRgXqI3KrDUr5YXhjmFmS)0EJFktjT3V6Uz9I0uV6aV4d4f2ZkcV3b2JAe6xN3gYwifewa7rMN(9W87(9IQeTn7E1G6tk5WRUU7l5rLZoT6aL5jDHX7iTm5HM9UztydQh3xeUZX6nLY)PYNLNRpZO9Mrhuu3NMypdQiluXhSF)ONZV9B9g4OF4EpgpM8qXDR65igjc(geooBsA1mOFCTOZBLRRZ)465eB3tSqAWD(J4yg8IkcjhcPeMu56uTCHh)Ouj7SuO734o3pMaPncsikDpe30DU8RCc7ox5lqYFpD6UZZMVlhGNvV3bzqlTC2lvab4JRQ4dBWkvSrnmuKP0feTlINESQNkIGRReb5iwrnvnyNJenvvTjRQWb30skQuNdJ(ZGIFDxXvbEE7XHNAbuDAqAvxtbOENLSGQD0HHfRzsxRwjS1jlCAqM2AnQGkEVfQOYnwASrx0V9KkGRaWF1jAdL5BSBUFCR5wBO(5xdXfpk94SkBGGFNnTh7io5NpoND6L4VTMG(SiGKB3Qw1ITZZQow)tw1RoxncvwVYDnkDxZKDFz0(sOPmA1kX6Yb42QC8rjD8)RsjTqa5)1c6ocD5UP2wZT9ZN9g8kcmlHs1INTcfzVuAGipRR2aOXo9As75(k(8RN6ZNA5NLuDBBJqrFA97t0vMUvst3wTPBLabzXrBB)qt9A1iXIU1sJxTncL4))sDRvApp1w6nrpRAj)kW(eQLDjk0TxfW02Y5lLdVrPfQvi8JvjCBsHlLaXwPZLEOrWl0iVRIK3xvYBwM8UOtUKbQwnxodKd5gJFRQc2Qt9wMLnDb7KWGDtzWMKgSXV71K2Gs62wPEL37CMWpreEpuzVrz2L5WQfyvCTPUU7gRP6vr)9Zj(xCsJlRqi9p5ytsTNNZ0eq0GO4TR8dEQhrj8n0y35)e(bsi5WIH)q2Fd1YHD)Np]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261107000,
    [[Hekili:TR12UnUnq0VL8IRnAGVKB72GOaSf92w0UTOE7RsMwIYMn0IgIuj1ag(BVK6kjdPUzN2fOEFyHSi5mN5mKuZCqCN5(z35bag09txn9Q7MnB67MoDQ7C2UTq35Bb(pbwXFicSH))FGsbukkcWqKOdlg(c5fkAdDSpzZiXK3HjGaHbxMGWSpg5U0OTPBH(UZ)JF7h)ZV)EGSjDNVgfeaZwhK6xVhV)Wc2A4Hf5VBsijg(mm(WIayiibZoS4d)(VCyb)18N0StcAIaf0jXKvjWjbBPtaBX0j5lDm)hJ)lkjA0LCNedIOyEyeWFMiCkIEybiiGe9v8hEcUJo(WIVdWa3Bamd)1p(zUrwZyBP3pzYkeBDYsb(NOn1rCBYX8nlNo96PGBUzj8QXCsnMeIWCUh4lGoD82yiFXlbmNLyqa0leNehV7Wp)QX)ANj8N3adqS0O(Yek0Jeg6TYpWzw5cCwbIJjm4LHe)eQZSlrHodfwG4TLGIyCUM7aye7HBhCraCzsy448Lmoz7Os7WD3ZGieDTQFsn3WlYMu5cFkI8s0EdMBGLPcJGXR2ngtE0rBCFcLnAGfaZqBGp6mtbLCszlioJseGRWHzOVaA(ecoG)uXRJHGGDk2zjMqc8ctI3ziIlmQCok30dTo0Gu2q59CkP9oToVwgpkJLfvdkxwHXZwKMNRwxM3SSQbCc(5XZKE)O9sitBYNEqpsAtuhTPC8cc47Hayue0loHVRweYL7cFW52PvEHIr(qpquGxa)HC)KMl1grSbVyrqCseK6HrRwZY5cBKup2bOHE9yxF4Ck1Ak1A(tMolhjZAvMZqOo0onuzsLXknAFy9gZSN6nZN5Fv(xSWte58fq0iVBs2SM(qWWAdA74UgCX3cESCzpjSEYxT(4NHCB(bq5rKocACZWzkFu2jU2XeVXXB3GDxoA1x8TbGIO8YcNDJQ7sIHpbm4OIex6457YQszzVnnQh0aMQnDKv9N(qCsPHL1yGQd1GKSQFBYWHcE3l3kp0KB0YDIMKyyOhdAIrLRKA2T7nYWst5QBhTx9Ndm3IY1MnvkZM)MxTlRMMKey1OFCUw2cXjBzCJR0bfdG5tC8A4gsC8AEp0J5K2smmWyRkp6CDzZv5wJd0bxmunh4ChV(XClhIbVGHuQh8VH(jzXCMhuIo1Zykq00zWspn1coNzcukE0NVpXlTAedjEtg15wPlhFgr9H89N2B8tAkz9(v3nRxKL6Lh4vFaV0Ewr4Jo89OgH(nfTHSHNcWLWEK5P)iF(D)ErzI2MDVEq9jLc4vx39v8O0zNwDGY8KUW4DKwM8qZE3SjSb1J7lcp4y9MY0)jZNvNRpZO9Mrhuw3NIypd0KfQ8d2VF0(IB)wTMF0hVZJYIrpvE3QAoIII4FdcgNpjLAgupUw25T011fFC9CIT7jwEAWD(ZWyk)fAA)I5PeAQMZzkTYF8tPAqNNcD)w35(XiEAdbCN3bHilui1DE(lDNN(XoH5zCqO5dPpnjMr5IZK7tbdLCLQKKDr(YJv)sreCTweuGyj9mvGDbsu010MWMchCtlPOkLgm6pdAU1Dnpf452Jdp1cO6ub0QYIcqDNLSGSDuHHfRzszPwjT0jlCAqO0AnQGkENfQq7odf2OlkOEsLqva43FI2qz(oZM7i2AU1gQ3)wiV3rPiM1g3f8730JneN8JhNto9s91wtqFreqIDBZM2YJZYow9lw1lpwnkfwV0znQDwZKDFz0(sOzmQEHyD5aCBLU9O0U9)vPKwOG7)AbDhHE6UP2wYT9ZN9g8sk8Mcf9ANTcL0MzuarrwxUdmJTA1K4V9v933o5Fp16)Ms1TTlcjbIvVprvA4wPnCBfhUvDONhhTT7df5JLJelchNAC9UiKI))lfoUkQYTLAp0Z0R4xc2NqXKRqHQ90atBRMVsp6gvwOwLOpwPOTPfDAWyR05kp0i4fIu3vvQ7Rm1nRtDxeQovFg9Q5kyGci3y8BvwUwDQ3YSSjmxNuMRBsZ1K2Cn(DVMeNlLUTvQx19oNj8teH3dzUBuN70COEbwLxBQk8TXAQEtea)CI)vN0yPviK9xKRjTUlYzk6h2b9Qvl)GL5rqcBnj2D(pbFcHrhwm8hY)tmoDy3)5p]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261107000,
    [[Hekili:TR12UnUnq0VL8IQnAGSvCC2TbrbOf92w0UDr92xLmTeLTAOLmiPsQbm83Ej1vsfsDZoTlq9(WczrYzoZziPM5G4y58zNf(ak05J3m9M7SSM(UPtN6SGUFh0zXoG3tG1ShIaBz))IKvueKU)4YrVe)cjClX0lE7y(82JIb(CBTkjer)qKZkLMLSd65S4p(9F6p)H7j5wZzXMqFFy2sGepT(5(JlPBGhxM)UjbXy4Zq8XL(WaqcIEC53(PF94s2RpUuWejHt4ULmbhVoboXFhzcyhImjFvMSFy(xK4OXxZSpgerqmC7ZEoM7VqYXLaF)4OVI9WtW9eZJl)EafCVcCm63(WNzgzdLUJC)KjRdPBswXH(KAtDmZMm4E7QPtNnfC7TRG3yYyrCCqiIXZapAyCeXChgYw8ka1Efc4dDdqjy8(J)YRg)RTNWEEl0pKc4dDDcb6ghe4U2Z32QCb2RbyCmfEDqSxcX266Wa7rCle7UlomIYOzMdGr0hMBCLpCvsqGz(smt2nU0om39mikKSr2pPMB0vztQCHpff)s0bfMZqZuHrq869MO4hTRnUxmHo2qdGPHBHpABjHsgPSdGZOeo4kCyg6lGMxCmYN9uXRXqG)Ej7Scfh77gKG3RiIlmQyok30J0oKrkBi9EgL0DN2KxlJhPXYIkJYLvy8SfvZZvRlZBAwLbJGF20s49JpiGSAt(8d6XcBI6PnfJxGpBpeafgbDXjSD18qUCx4d2ZNw5fck0d6cI8D9zpK7N0CzTr4BWlweeLebjUOW1BO5CHosAa7aQH(6XE9HZPuTPuT5pr6SCKmRvzofH6i90qLjLgR0OdH1BnZEU3mFH)L5F(cptKZxarJ4UjrZQ6dbJAmO1J7gWfBl4PYLdKWgiF15JFkYT5hafhr4iOYndxO8XzN46gt8ghV9d295O1qX3wqyeHvwO1TYUlbdFcOWrfjU0XZ3LvLYYEBAuB0cMAmDKv9x9HyKsllR1aTou9tYQ(TndhW5D3CR8qBUPwUJ3KeRzlxkufJkwjL18dkzyHPCZ8XhK)PH6wuMP2uPmB(BE1USgAsIJvL(XEMOfWj7OmJl1bffGyt0CdCBmgVH1VSjJ0wHG(kBv5r7zLnxLBngqnUAKCoW(ow9J5woabEbbjex4Fd9sYI5mpifDYNXKGOQZGLEAQgCAPcusE0JTpXnTAefjEvg1EUWLJphs8GS9N6B8tykz9(10nRxLL6fh4vFaV0EAr4J2S9OkH(TfTHSLLcqLWES6P)iB(9)ErrIwNDNz0CsPaEn1DFfpkC2PthOupPRuEhPMjpsT3vBcDq90(IWd2AVPm9FI8z156lm6GzuJY6(Ke7XOMSqLFW(9JpuC736nSJ(O9Ueko8PY7wLZrKWi23GG48jjvZG8X1YoVfUUU4JRxsS9pXYsdolEgIjSxutSxelLqs1xotPv2JFmvV58uOZ35SWdhYsBHaNf9qiYcfsDwK)sNfPFSJBEkde18HWNM4ZOCXzY9jHHsUswsY(iF5PQFjpcMvlckqSGEMsWUajs6AQtytUdUTJuuLsdk9Ncn36VMNC8m)0WtJaQjva1QSihu3PjliAhzyOXAQuwQtslD2cNwekTrJYPI3PHkQDNHeB0hfupRsOYb87ptBOuFNz7DeRn3Qd1hElK37KuetBJ7C(9BgWgIZ(XJljNbP(ANjOVici(UnRPD84SOJL)IvZYJ1GsHnlDwRAN1ozpugDOeAgJwVqS(CaURs3EsA3()QushuW9FTGUNqpD3uxl5w)5ZbdEbfEtHs9AN1cL0MzKarrwxSdmLTA1M4Vdv933o5Fp36)Ms1DTlcbbILVprwA4oPnCxfhUtDONhhDT7dj5JfJenchNA86Drie))xkCCvuLBl5EOTQxXVaSpJIjxHcz7vdmDTA(k9OBvzHgvI(uLIwNw0PbJUsNR8qRGNlsDFvPEOYu3Uo19rO6u9zQxnxbdua5wJFTYY1Pt9AMLoH56LYC9tAU20MR1V71M4CP0TUs9QU35cHFMi8biZDR6CNMdRxGv51MYcFRSMQ3ebWVK4F1jnAAfcz)f5QsR7ICMK(H9qVA5YpOzEeKq3eJDw8ZWNcrHhxo6hZ)tmoDyN)5d]]
)
