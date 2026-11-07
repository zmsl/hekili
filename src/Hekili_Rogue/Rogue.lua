-- Hekili_Rogue/Rogue.lua
-- The Forever Rogue (Assassination, Combat and Subtlety, one spec a talent tree: Hekili:NewClass): the Rogue kit with
-- Forever's spell data (ranks, costs, cooldowns and durations from the Forever DB2 at build 1.60.1.70338, wowdb; energy
-- costs are DB2 points), Forever's Shank, Death Mark and Mutilate, energy and combo points as the Druid's cat has them
-- (combo points plain in combat, measured), Adrenaline Rush as a regen multiplier, Stealth and Vanish from IsStealthed
-- (unprobed, so the belief also models them from our casts) and the poisons as abilities (no list recommends them
-- now). The defaults are the "<Spec> (wowsims.com)" packs, generated from wowsims/forever's Rogue APL
-- (tools/wowsims/specs/rogue_*.lua; no in-game check yet). Research: docs/research/2026-10-15-forever-rogue/research.md
-- and the class-completion research §2.
-- Talents: the DB2's Classic nodes and the Forever-only ones this file reads, as the 0.7 re-pin's rework left them
-- (wowsims/forever at 4b0030a44b: Venom, Cutthroat, Thousand Cuts, Murder gone as they were; Shank, Death Mark, Boot
-- Knife, Flash of Steel, Composure, Blood Splatter, Quick Getaway new; Improved Sinister Strike is Efficient Strikes,
-- Improved Eviscerate Coup de Grace). A modifier is the rank curve wowsims/forever's spell store states (the
-- generatedCurves of sim/core/spelldata/spells_auto_gen.go), else rank 1's value x the rank.
-- Credits: Hekili (registration API and pack format; the `stealthed` table and the stealth-breaking runHandler hook
-- follow Hekili's Classic profile, origin/classic:Classic/Rogue.lua). wowsims/forever (MIT,
-- ui/specs/rogue/dps/apls/default.apl.json and sim/rogue/) is the reference for the priorities and the Ghostly Strike
-- and Preparation rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase = Facade.UnitClassBase
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
local MUTILATE = { 399956, 1241582, 1241584 } -- 1310707 (the talent rank 1) left at the 0.7 re-pin
local SHANK = { 1329283, 1329549 } -- levels 24, 44
local DEATH_MARK = { 1316709, 1325756, 1325757, 1325758 } -- levels 40, 48, 56, 60
local VANISH = { 1856, 1857, 1285372 } -- 1285372: Forever's "Rank 3" (checkpoint Q12)
local STEALTH = { 1784, 1785, 1786, 1787 }
local HEMORRHAGE = { 16511 }
local GHOSTLY_STRIKE = { 14278 }
local ADRENALINE_RUSH = { 13750 }
local BLADE_FLURRY = { 13877 }
local COLD_BLOOD = { 14177 }
local PREMEDITATION = { 14183 }
local PREPARATION = { 14185 }
-- The poisons' items (ItemSparse), best first.
local INSTANT_POISON = { 8928, 8927, 8926, 6950, 6949, 6947 }
local DEADLY_POISON = { 20844, 8985, 8984, 2893, 2892 }

-- Relentless Strikes (14179, 4% a rank a combo point to restore 14181's 25 energy): only the certain part, 5 ranks at
-- 5 points (the rank curve {4, 8, 12, 16, 20}).
local RELENTLESS_ENERGY = 25

-- Improved Expose Armor (14168): the energy curve {-5, -10} by rank (the old rank x 10 priced rank 2 at 5, not 15).
local IMPROVED_EXPOSE_ARMOR = { [0] = 0, 5, 10 }
-- Efficient Strikes (13732, Sinister Strike and Hemorrhage): the rank curve {-3, -5}, by rank.
local EFFICIENT_STRIKES = { [0] = 0, 3, 5 }

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
-- Improved Slice and Dice +15% a rank (14165 aura 108 base 15); Rupture 6 + 2 a point. Read at the
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
-- max rank }: the DB2's nodes with wowsims/forever's 4b0030a44b max ranks (`Talent(id, max)` of sim/rogue/
-- spell_data_auto_gen.go) and trees (the `=rank@tree` of its logs' talents header) where it states them, keys the
-- snake_case names (Setup is setup_talent; a nameless node talent_<spell>), and the Forever-only ones by spell at
-- tree 0 until the live export (checkpoint Q1) places them.
spec:RegisterTalents({
    -- Assassination (tree 1)
    remorseless_attacks = { 1, 14144, 2 },
    malice = { 1, 14138, 5 },
    ruthlessness = { 1, 14156, 3 },
    improved_slice_and_dice = { 1, 14165, 3 },
    relentless_strikes = { 1, 14179, 5 },
    improved_expose_armor = { 1, 14168, 2 },
    lethality = { 1, 14128, 2 },
    vile_poisons = { 1, 16513, 5 },
    improved_poisons = { 1, 14113, 5 },
    cold_blood = { 1, 14177, 1 },
    improved_kidney_shot = { 1, 14174, 2 },
    seal_fate = { 1, 14186, 3 },
    vigor = { 1, 14983, 2 },
    blood_splatter = { 1, 1329256, 1 },
    venom = { 1, 1329328, 1 }, -- Shank's 6 s poison bonus
    -- Combat (tree 2)
    coup_de_grace = { 2, 14162, 3 },
    efficient_strikes = { 2, 13732, 2 },
    improved_gouge = { 2, 13741, 3 },
    lightning_reflexes = { 2, 13712, 5 },
    talent_13733 = { 2, 13733, 3 },
    deflection = { 2, 13713, 3 },
    precision = { 2, 13705, 3 },
    endurance = { 2, 13742, 2 },
    composure = { 2, 1329265, 2 },
    riposte = { 2, 14251, 1 },
    improved_sprint = { 2, 13743, 2 },
    improved_kick = { 2, 13754, 2 },
    hack_and_slash = { 2, 13706, 5 },
    dual_wield_specialization = { 2, 13715, 2 },
    hack_and_slash_2 = { 2, 13709, 5 },
    blade_flurry = { 2, 13877, 1 },
    hack_and_slash_3 = { 2, 13960, 5 },
    flash_of_steel = { 2, 1329284, 5 }, -- Shank: +3 energy and -0.4 s cooldown a rank
    fist_weapon_specialization = { 2, 13707, 5 },
    weapon_expertise = { 2, 30919, 2 },
    aggression = { 2, 18427, 3 },
    adrenaline_rush = { 2, 13750, 1 },
    -- Subtlety (tree 3)
    master_of_deception = { 3, 13958, 3 },
    opportunity = { 3, 14057, 5 },
    sleight_of_hand = { 3, 30892, 2 },
    elusiveness = { 3, 13981, 2 },
    camouflage = { 3, 13975, 3 },
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
    boot_knife = { 3, 1329286, 5 }, -- Shank's chance of 2 combo points (20% a rank; not modelled)
    quick_getaway = { 3, 1310728, 2 },
    death_mark = { 3, 1316709, 1 },
    -- Forever-only (tree unknown until the export)
    flawless_execution = { 2, 1310711, 1 },
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
    -- Death Mark (rank 4 1325758, 6 s): the mark's payout lands when it ends.
    death_mark = {
        id = 1325758,
        copy = { 1316709, 1325756, 1325757 },
        duration = 6,
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
    -- The next Ambush or Garrote needs no Stealth (1329326, 7 s, one charge): Ghostly Strike's landing gives it, either
    -- cast takes it (wowsims talents_subtlety.go). From our cast's `now`, as the strike's own buff.
    ghostly_strike_next = {
        id = 1329326,
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
    -- Venom (talent 1329328): Shank gives +30% poison damage for 6 s.
    venom = {
        id = 1310703,
        duration = 6,
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

-- Riposte's window (L138; the Forever client answers Riposte as usable only inside the 5 s a parry opens): the client's
-- usability flip is the evaluator, its false->true edge opens the window, the flip back (Riposte cast, or the 5 s)
-- closes it. The belief owns the span, so it forecasts and survives a rebuild. (Runs in the belief's `now` context.)
local function riposteUsable()
    local r = knownRank(RIPOSTE)
    if r == 0 then
        return false
    end
    local usable, noMana = IsSpellUsable(RIPOSTE[r])
    return usable == true or noMana == true
end
spec:RegisterWindow("riposte", {
    evaluator = riposteUsable,
    duration = 5,
    close_on_false = true,
})

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

        -- In Stealth or Vanish, or after a Ghostly Strike; a dagger and being behind are the player's (settings).
        usable = function()
            return buff.stealth.up or buff.vanish.up or buff.ghostly_strike_next.up, "requires stealth"
        end,

        now = function()
            removeBuff("stealth")
            removeBuff("vanish")
            removeBuff("ghostly_strike_next")
            removeBuff("cold_blood")
        end,

        handler = function()
            removeBuff("ghostly_strike_next")
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

        spend = 60,
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
            return max(0, 35 - 15 * talent.flawless_execution.rank) -- 1310711's -15 (4b0030a44b; the log's 20)
        end,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims eviscerate.go; DB2 Discount Power On Miss
        known = knows(EVISCERATE),
        ladder = false, -- a finisher: an answer short of energy may be short of combo points (C9)
        usable = finisherUsable,

        now = function()
            removeBuff("cold_blood")
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            removeBuff("cold_blood")
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
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
            return max(0, 25 - IMPROVED_EXPOSE_ARMOR[talent.improved_expose_armor.rank]) -- the curve {-5, -10}
        end,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims expose_armor.go; DB2 Discount Power On Miss
        known = knows(EXPOSE_ARMOR),
        ladder = false,
        usable = finisherUsable,

        now = function()
            applyDebuff("target", "expose_armor")
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            applyDebuff("target", "expose_armor")
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
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
            return buff.stealth.up or buff.vanish.up or buff.ghostly_strike_next.up, "requires stealth"
        end,

        now = function()
            removeBuff("stealth")
            removeBuff("vanish")
            removeBuff("ghostly_strike_next")
            applyDebuff("target", "garrote")
        end,

        handler = function()
            removeBuff("ghostly_strike_next")
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
            applyBuff("ghostly_strike_next")
        end,

        handler = function()
            applyBuff("ghostly_strike")
            applyBuff("ghostly_strike_next")
            gain(1, "combo_points")
        end,
    },

    hemorrhage = {
        id = 16511,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 35 - EFFICIENT_STRIKES[talent.efficient_strikes.rank]) -- the log's 30 at rank 2
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
    -- 6 s). Usable only in the 5 s window after a parry (window.riposte, from the client's usability answer). On the
    -- Combat priority, in the window (owner R70).
    riposte = {
        id = 14251,
        cast = 0,
        cooldown = 6,
        gcd = "off",

        spend = 10,
        spendType = "energy",

        startsCombat = true,
        known = knows(RIPOSTE),
        usable = function()
            return window.riposte.up, "needs a parry in the last 5 s"
        end,

        now = function()
            closeWindow("riposte")
        end,

        handler = function()
            closeWindow("riposte")
        end,
    },

    -- Both hands; +2 combo points (one effect).
    mutilate = {
        id = 399956,
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

    -- Finishes the cooldowns of Cold Blood, Premeditation, Vanish, Ghostly Strike, Blade Flurry, Adrenaline Rush and Riposte
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
            setCooldown("riposte", 0)
        end,

        handler = function()
            setCooldown("cold_blood", 0)
            setCooldown("premeditation", 0)
            setCooldown("vanish", 0)
            setCooldown("ghostly_strike", 0)
            setCooldown("blade_flurry", 0)
            setCooldown("adrenaline_rush", 0)
            setCooldown("riposte", 0)
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
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            applyDebuff("target", "rupture", 6 + 2 * combo_points.current)
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
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
            return max(0, 45 - EFFICIENT_STRIKES[talent.efficient_strikes.rank])
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
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            applyBuff("slice_and_dice", sndDuration(combo_points.current, talent.improved_slice_and_dice.rank))
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
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

    -- Forever-only (levels 24 and 44, 5 energy, 10 s): an off-hand strike that gives 15 (rank 1) or 25 (rank 2) energy
    -- and 3 more a Flash of Steel rank, which also shortens its cooldown 0.4 s a rank; with Venom it gives the poison
    -- bonus. No combo point: wowsims's Shank is no builder (Boot Knife's 2-point chance is not modelled).
    shank = {
        id = 1329283,
        copy = { 1329549 },
        cast = 0,
        cooldown = function()
            return 10 - 0.4 * talent.flash_of_steel.rank
        end,
        gcd = "totem",

        spend = 5,
        spendType = "energy",

        startsCombat = true,
        known = knows(SHANK),

        now = function()
            gain((knownRank(SHANK) >= 2 and 25 or 15) + 3 * talent.flash_of_steel.rank, "energy")
            if talent.venom.enabled then
                applyBuff("venom")
            end
        end,

        handler = function()
            gain((knownRank(SHANK) >= 2 and 25 or 15) + 3 * talent.flash_of_steel.rank, "energy")
            if talent.venom.enabled then
                applyBuff("venom")
            end
        end,
    },

    -- Subtlety's finisher (talent, levels 40/48/56/60: 25 energy, 1 combo point at least, 10 s): a 6 s mark that deals a
    -- share of what the rogue deals the target when it ends (the payout is not modelled).
    death_mark = {
        id = 1316709,
        copy = rest(DEATH_MARK),
        cast = 0,
        cooldown = 10,
        gcd = "totem",

        spend = 25,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims death_mark.go IssueRefund on a miss
        known = knows(DEATH_MARK),
        missable = true,
        ladder = false,
        usable = finisherUsable,

        now = function()
            applyDebuff("target", "death_mark")
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            applyDebuff("target", "death_mark")
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
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
    20261107003,
    [[Hekili:TV12oUTnt4NL9gxB0aFypKKUyDaA7FpKI(3wu3ERKPLOSvTSObj1U1ag(zVJOorYLuNwVPbOoxKilsoZ38ndPgodIZmN)WzHpIJD(LRNE9BNnB67Mo9gNf8d7Xol2J82IwdpeJ2b)93s2TcXpTC4tKNyH7yJ9i7gLoRdreKFQKwLegX)ySZkJcLTh75S43)1F4p)U79eYYzXMqFFC2cWmpl64(tl5BWNwM)Ujbek(rm90sFCakjcM(x)B)8PLWRpTSuajHtsviBcLSobpXFpBcAFeBs(Agd)y8FXiXJEdiDkkMfbi2hEMKQTq2PLiFFs8xapSfFGn(0Y)hIJU3akg())4FaczdNVND)KjRd5BswLc8jAtDeitaA3UcOJPOBVDf(6Xa)rjbHra)I84HKy249uCg9mFveYh7geLqPho9tpB8VC(e45Dy)qokDO3KWWUKGa31E(ZNvUG50W9eghRo8BciEjm4FddMJJX01hghr(W8S1moFjGvW4Lcc03AeLsarjT4HPGH4UNegZb)fGvCm)H7gCLpEvsqW48Lmoz)izj9ikoKTrdtPIB4v5yOyHBJjpfF0G4gyzQp3Ckgp1CgnWcG5H7WFy(mfuc87EenJDtbxHcZqFb08iKiF4PIxtXi)dkYzveH47gKqpyWIleQS7ox0dTo0abBO8EGsAVsRtRL2JYyzw1GYLvi8SfPP5Q1LPnlRAaqWpoEM07hDuczAt(8d6rsbrDuMY2lBdkEBMHoKJIG4PXRieU724Wa8y40LTFy(DhTnYTwh5gRJCTHrWXOvryFlb4ZVzq5gJhM)(PPe9NdGvfuk0kYhqokkmg7stGdlsjyPPF30kNhlk0d7II9D9HhYDFITiAJKEUrXIWrjXyMBu46n88qmBXE9yJLg61dP0hops16ofRBlKJslhjtAvIZGPo0onujsLXkfAFy9g9SN7ZiUW)Q8F6cptKZNbwJC0KSyn991H1A02XDn4ccbFPCzpjSEYxTE7NbFB(gq5rK2cAmy4cLpkBhx7yIxz7TBWUlBT6l(2HcJzq22ZUvvDju8wKbfv44eJNhLv5YYERWQh0aMQ1DKLuT(qaP0WYA0q1HQFs2LkAsWbP8UBUuEOj1O57sVglpc7YXMy0HYPsndUVwEoA(yeFJ7oeDBzoAhns)sl)67G5O87k3GK8Y8a5xKt69IOUbMVi5nMvUqe5V5zbT1CR4ut3s6XYsOcC2waKjS8cOj75aAuUyCz21I0cy7JqCoMwWQf5eVbVJqPBqRBibEib7Y7uNRnWYhC1q1yK5VDuPRmic9ueMXCX)n2ljJeZvHYTxuodqXemDgrPMMAbNZmbkfn6bXXUcAXqGPjHoxkGc)yiZdd7FSFFFPPKDL)6o5)QSyj5bEwcgLYlZXA2UV7OzSFBX1p3b(GOsCpY80HaRECWTmtBtU3m45EL622lZafqVUk(urYs7uB12xZt6kJhWBzYdnRDZIWguFzFo7H5wpMx8hz(SAx)fgT3m6GYKwvka4aTsfwMTX7hDSiCF9g4CHOdUmonCB1jVQNlggdFaftZNKscpQBLllBG0H5fzgCXX2Dhl4gCw8iMYGxO1fHiWLWeTTiRq(WJ)IOng5UqNVXzHhneCBHO0xwxLTDwi(wxQawi9DiXVZMUZI857WbCyvnDOg4vso)LsGa0XnA6WgSYQ0ScgkDjQvdVlvo)Lw68ul4wnlOaXsLsxb2firPK62QPEQcURLuuv1ymQpdL7T7LBpfpV9LHNAbuDfG2ArTtb17S4fKLJkmSintvFRvLF7SzonuJ(AfAkv8EluHOO9QCqn1dVMcIxtfXRPK4NHc4xFf8)KIyTQ4NY7FLfEx7tckEGUuD)ZA59tb8SPNPDYM)MyZLRX6MkBW(4RrTNFrLR1AvLeeS(hQBtiXz)GPlENE1BGwtqFwyqIWn9e2STFwwXQ5kuFXBRPo21xy3gRSBZKDFz0(sOzmQE6PDzdCBBSWlQZc)NYL0I(l8jZO7i0frt6xvO77p7n4L6)GakT9sfz3wvbefED5RyB8U0n1AI(2BIxVMtCU7oHGQB79LKAFHww6TVXfTQZfTV1fDU3fTQKo58I(v2SXlkD3qMzSCRbHWTDjOklPjjb3Bqij906L9m13WJ)D74HujDYKLAHxUwp5Fj76m2fePRFQipnWONOSTyHQgP0y5OQTfkV0EOyRjkcJrpnSYZsl1GAuKTUR012R03(R0CdwoxDyrqp2YPQWCA0ZATEYT60hlZYwfL7ujL7wnLBQOYn(98MQQSGUTvFYQtLUq4NjcVh9NPXg0i8H6zRvEMQAhBmMR4RsNBU44F2onUitLuwezSjnf(mLksBOllTlniEMgrj8neQZIFeVnmk80YHFF()1led78pp]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261107001,
    [[Hekili:TV12UnUnt4NLCJQnAGpK4KnniAb2I2)2TOD7pQ3ERKPLOSvTSOHivsnGHF2lj1jsgsDYoBxG6CrGIi5C4Bgsn8BqCM68zN5(ac05t3m5M7NoDY7MmzQZCY(DqN57aEBaROped2s)9hWyaghgdiHO4Jlg8c6fC4w8ip02HSjVpcb8zcCzAye5JXol1kB8oONZ8)43)P)8hFeiksN5Rd99HzRdI9QxJpECbzn84I83noaLaFgMCCHpmaKgroU4d))F94c6RPpPiN0WXmRapobTkfo2FhEmyxeEC(shr)Jr)fgfp8AQssaX4iQB4tFgXuAi(4cGVpk(BOpSbUhp64IFaqapQXyg8BF8ZuHSMq2HFC84vHK1Plz2)yLPoKktQnpB5Kj3obmB2s4nJOGAckimII9apMPJhTlbsx8saXEzeWh6geLMKS)4V8QX)w7X0N3c9djCV(6um0ffe4UYZ3EA5cSxbssqe41biVuS90RddShWKaYDhkmMqXAQcGXKNUZ6kF4Y0GGr5lzu6UHLYHQUNbXH41Y6HlUbxLnPYfUjg9s8bnIZYWuHXWKv7hfHEVTY4EimzOLbdMeUf(E7Pswjfu2bsYGeMXvOWmRVW08qOiF6tfVobc83ljNLriKVBqAYEnECHqfJr5IEGXHS4OH07Pqs7vADAT0FKglZRSkxwHWZwKIMRwxM2mSklka)8OPcVF4bbltzYNFJEOqsuhLPO)IxdI3K5OdiGiA(0OLieXDtCyaCe9iHnV3(UdMgzMXrU14i3Ozeymyze03qcU9TwLBmEY(HjmG(RbJv2OKGvGp1YbrHXq3Ku6Hfmawy63nPk4HJc9GUGyFxF6d5Hp(weLryNBuSiyuAme7gfUAnjpfZuUxp2yPy9QPuQdNNPACNIXTfIzPLJKjTkXPXvhyggQeP0yLcTpOEJr2Z9zexWFz8NTWZe48vG3iMnjkwDFFDqToTz7Ug7IMcEQyzpbSEIxTE7NMyB(gqXre2cQnz4cKpmBhx7qI3y)TBMDx2A1x7BlimgtR2E6mz1LMa3a0OOIahF88SSQqw2B5ETvd2uTHJSIQvhIcknSSgDuvt1pn7sfnj4agU7MlLNAsnkXo2DpjrqxcuhIoqSuQP07RLxJMpeqw7UfKSPSgTdAHFHLFZD05i93vHbb5LfbYViNW75zDw6Vi5T6voxe5V5vjT1CvwMRBO8yrjuzCMwaTsyXfKKUJqTgPlgxwDnVSa8UiaHatkq1IAIxd3Isswdw1qb80cSlVtDU2OEU1vdKZrSVFyzOmic8seeJDH)n0lndeZvH0TxKodqYf0DgrPMMyWoNQZOK0Ohnp2LdlAsm1juBHek4ZHypiD)J577lmLSR8x3j)xLLljoWRkWOuEzbw9(9Dh0B7ZkU(5wAmiQ0UhQF60eRECWTisBsU3A96OsDB7frGctVogFQazHDQTA7R(jDL2d4nm5b61UEryYupTpN9KTXJ55)iINv76VGO9grTklAvIaqlfQclR24HHhks3xTMEUq0ExmjjCt1jVYNlggt)akmjFssf8iVvUK2aHdZlQm4sGT7bwAyWz(ZWem9fk9diIgsW8(qKX(o9XpX7lrEi057DM7LesdBHaN5DGC6cwZDMN)sN58VeYepHAek6q47wSzuU4mkGLSHsSsMM6UqP9PYPnZdUvXdkSyboULm7clrIRBtKDZuWSwcrv0KOvFA4HT78GZSN7on7PwdQoMHnY2mZOU3ququoYMHbPPJwSwXl2zZDAG88AfkdkENbOGZMUmgudr11WuDnuvxdx1NbM1RNA9VOwSc96mC)bd4UYz1srGUq7(zL3DMb)DNPnY6)wvZ0OyCpLjR(WBbNWNenQgz7HHVtN0JmIZ(5sxIo9IZ(wdqFv4q80n161mTFwuXYLkupPQ1WVC9eU2iJRnd29fr7lGMHOQvN2LnWTLW)tIX))tfsAbV)FXC6oA68Sj1Bk099N924f6la3uA7DkYUfPKrue1fV6R2742uld6BpdE7AAW5URbCOUTxxsOTckfP3(gk0Qok0(wk05Ek0kQwYXf1BSzcxK66GiYy4sdCHB6oqvEstsIETbUKuRQxmYuFJi(3Ttev(CUSK5DzQAX)c(1zS7ec3(usEkKaPwOSPCHQgC0iBu12AJtT3gMAUb3zuldR8S0sniNfzQRhDTTh9TVhn34JZvNp4WJPAQkCNgJSg55TvN(yywMy6Ttu92nUEBIS3g)EEtS9YHBt0twDQ0fa)mb49OVjn24eEmuTATYZuL7KI2AfFt6OYLa)R2Pr4vQWqrG2MNueZKiKUdnarUmisMgbPK1OeN5)mCtyu4Xfd(F5)FmWh25F(d]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261107001,
    [[Hekili:TVvwVnUnq4Fl5fvB0aFK4KnniAbArV2I2Tf1BFvY0su2Qww0qKkPgWW)2lj1fjdPUSZ2fOopeOisohFZqQHFdIZuNp5m3hqGoF8Mj3C)0PtE3KjtDMt2Vd6mFhWBdyf9HyWw6VNNUKebj7pUyWlOxWHBXJ8qBhYM3(ieWNjRLPHrKpe7SuRyX7GEoZ)ZF)N(RF4rCU0CMVo03hMTei2ZOEE84cYA4Xf5VBCakb(mm54cFyainICCX3(h)6Xf0xFCHGisdhZulECcAvkCS)o8yWUi848vnI(hJ(BmkE41u5NaIXru72N(mIPVq8XfaFFu8xrFydCpE0XfFpGaEuJDm43(WNOcznHSd)44XRcjRtxYm9XktDivMuZD2YjtUDcy2SLWBgrrXeuqyefNbEKqumE0UeiDXlbe7LraFOBquAsY(J)YRg)RThtFEl0pKaydDDkg6IccCx55BpTCb2Rajjic86aKxk2E61Hb2dysa5UdfgtOWmvbWyYt3zDLpCzAqWO8LmkD3Ws5qv3ZG4q8Az9Wf3GRYMu5c3eJEj(GgXzzyQWyyYQ9JIqV3wzCpeMm0YGbtc3cFV9ujRKck7ajzqcZ4kuyM1xyAEiuKp9PIxNab(7LKZYieY3ninzVgpUqOIXOCrpW4qwC0q69uiP9kToTw6psJL5vwLlRq4zlsrZvRltBgwLffGFE0uH3p8GGLPm5ZVrpuijQJYu0FXRbXBYC0beqenFA0seI4UjomaoIEKWM3BF3btJmZ4i3ACKB0mcmgSmc6Bib3(wRYngpz)Wegq)LGXkBusWkWNA5GOWyOBsk9Wcgalm97Muf8WrHEqxqSVRp9H8WhFlIYiSZnkwemkngIDJcxTMKNIzk3RhBSuSE1uk1HZZunUtX42cXS0YrYKwL404QdmddvIuASsH2huVXi75(mIl4Vm(Zw4zcC(cWBeZMefRUVVoOwN2SDxJDrtbpvSSNawpXRwV9ttSnFdO4icBb1MmCbYhMTJRDiXBS)2nZUlBT6R9TfegJPvBpDMS6stGBaAuurGJpEEwwvil7TCV2QbBQ2Wrwr1QdrbLgwwJoQQP6NMDPIMeCad3DZLYtnPgLyh7UN07W6sG6q0bILsnLEFT8A08HaYA3TGKnL1ODql8lS8BUJohP)UkmiiVSiq(f5eEppRZs)fjVvVY5Ii)nVkPTMRYYCDdLhlkHkJZ0cOvclUGK0DeQ1iDX4YQR5LfG3fbieysbQwut8A4wusYAWQgkGNwGD5DQZ1g1ZTUAGCoI99dldLbrGxIGySl8FGEPzGyUkKU9I0zasUGUZik10ed25uDgLKg9O5XUCyrtIPoHAlKqbFoe7bP7FmFFFHPKDL)6o5)QSCjXbEvbgLYllWQ3VV7GEBFwX1p3sJbrL29q9tNMy1JdUfrAtY9wRxhvQBBVicuy61X4tfilStTvBF1pPR0EaVHjpqV21lctM6P95SNSnEmp)hr8SAx)feT3iQvzrRseaAPqvyz1gpm8qr6(Q10ZfI27IjjHBQo5v(CXWy6hqHj5tsQGh5TYL0giCyErLbxcSDpWsddoZFgMGPVqPbar0qcM3ZHm23Pp(rEpiYdHoFNZCVKqAyle4mVdKtxWAUZ88x6mN)LqM4juJqrhcF3InJYfNrbSKnuIvY0u3fkTpvoTzEWTkEqHflWXTKzxyjsCDBISBMcM1siQIMeT6tdpSDNhCM9C3Pzp1Aq1XmSr2Mzg19gIcIYr2mminD0I1kEXoBUtdKNxRqzqX7mafC20LXGAiQUgMQRHQ6A4Q(mWSE9uR)z1IvOxNH7pya3voRwkc0fA3pR8UZm4V5mTrw)3QAMgfJ7Pmz1hEl4e(KOr1iBpm8D6KEKrC2px6s0PxC23Aa6lchINUPwVMP9ZIkwUuH6jvTg(LRNW1gzCTzWUViAFb0mevT60USbUTe(Fsm())Qqsl49)ZMt3rtNNnPEtHUV)S3gVqFb4MsBVtr2TiLmIIOU4vF1Eh3MAzqF7zWBxtdo3DnGd1T96scTvqPi923qHw1rH23sHo3tHwr1soUOEJnt4IuxhergdxAGlCt3bQYtAss0RnWLKAv9IrM6BeX)TDIOYNZLLmVltvl(xWVoJDNq42NsYtHei1cLnLlu1GJgzJQ2wBCQ92WuZn4oJAzyLNLwQb5SitD9ORT9OV99O5gFCU68bhEmvtvH70yK1ipVT60hdZYetVDIQ3UX1BtK9243ZBITxoCBIEYQtLUa4NjaVh9nPXgNWJHQvRvEMQCNu0wR4BshvUe4F1oncVsfgkc028KIyMeH0DObiYLbrY0iiLSgL4m)NHBcJcpUyWpM))XaFyN)9]]
)
