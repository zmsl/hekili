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
-- max rank }: Forever's tree as wowsims/forever's ui/sim/talents/trees/rogue.json lists it (tools/wowsims/talents.lua
-- writes it; tests/Forever/talent_trees_spec.lua checks it and the spec detection over it). A key is Classic's where the
-- talent exists there (code reads `talent.<key>.rank`; Setup is setup_talent), else the snake_case of the node's name.
spec:RegisterTalents({
    -- Assassination (tree 1)
    improved_gouge = { 1, 13741, 3 },
    remorseless_attacks = { 1, 14144, 2 },
    malice = { 1, 14138, 5 },
    ruthlessness = { 1, 14156, 3 },
    improved_expose_armor = { 1, 14168, 2 },
    improved_slice_and_dice = { 1, 14165, 3 },
    vigor = { 1, 14983, 2 },
    blood_splatter = { 1, 1329256, 1 },
    lethality = { 1, 14128, 2 },
    vile_poisons = { 1, 16513, 5 },
    cold_blood = { 1, 14177, 1 },
    improved_poisons = { 1, 14113, 5 },
    relentless_strikes = { 1, 14179, 5 },
    venom = { 1, 1329328, 1 }, -- Shank's 6 s poison bonus
    improved_kidney_shot = { 1, 14174, 2 },
    seal_fate = { 1, 14186, 3 },
    mutilate = { 1, 399956, 1 },
    -- Combat (tree 2)
    coup_de_grace = { 2, 14162, 3 },
    efficient_strikes = { 2, 13732, 2 },
    lightning_reflexes = { 2, 13712, 5 },
    puncturing_wounds = { 2, 1224716, 3 },
    deflection = { 2, 13713, 3 },
    precision = { 2, 13705, 3 },
    improved_sprint = { 2, 13743, 2 },
    endurance = { 2, 13742, 2 },
    riposte = { 2, 14251, 1 },
    composure = { 2, 1329265, 2 },
    improved_kick = { 2, 13754, 2 },
    flawless_execution = { 2, 1310711, 1 },
    weapon_expertise = { 2, 30919, 2 },
    aggression = { 2, 18427, 3 },
    dual_wield_specialization = { 2, 13715, 2 },
    blade_flurry = { 2, 13877, 1 },
    hack_and_slash_3 = { 2, 13960, 5 },
    flash_of_steel = { 2, 1329284, 5 }, -- Shank: +3 energy and -0.4 s cooldown a rank
    adrenaline_rush = { 2, 13750, 1 },
    -- Subtlety (tree 3)
    setup_talent = { 3, 13983, 3 },
    master_of_deception = { 3, 13958, 3 },
    opportunity = { 3, 14057, 5 },
    dirty_deeds = { 3, 14082, 2 },
    camouflage = { 3, 13975, 3 },
    improved_ambush = { 3, 14079, 3 },
    dirty_tricks = { 3, 1224782, 2 },
    initiative = { 3, 13976, 3 },
    premeditation = { 3, 14183, 1 },
    serrated_blades = { 3, 14171, 3 },
    elusiveness = { 3, 13981, 2 },
    ghostly_strike = { 3, 14278, 1 },
    quick_getaway = { 3, 1310728, 2 },
    heightened_senses = { 3, 30894, 2 },
    preparation = { 3, 14185, 1 },
    hemorrhage = { 3, 16511, 1 },
    boot_knife = { 3, 1329286, 5 }, -- Shank's chance of 2 combo points (20% a rank; not modelled)
    death_mark = { 3, 1316709, 1 },
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
    20261107004,
    [[Hekili:TVvwpUTnq4Fl7lU2Ob(AxNJfRdqVBkAtlQtFvY0su2Qww0GKA3Aad)BVKuxKCj1L9MgG68qISi5mFZ3mKA4miotC(KZcFaf68XPJN(6jtg)MXJVZzb9WEOZI9aVTG1ShIb7y)93H2TcqpTS)tONiH7id9q7gWN1HieWNlPvjHr0pe7SYOqj7HEol(ZF)N(RF4EpHSCwSj03hMUaiXZIoU)0s6g4PLzVBuacdFeIpT0hgasIyt)B(JF90s2RpTSqajHJ4kKmcJwNah5VNmcSpImkBndz)y4FtqXdEft6yqmjIHyF2ZiU2cjNwc89rXFf7HTWdKHNw(9ak4EdOO)V9HpXeYgkDp5(rJwhs3KSId8rAtDatMmObNbENN)uWu)aVHm(dJccJy8lWJgIIjd3JHP0Z8vraFOBqucgF40V8SX)65JypVd6hsb8HEvcb6IccCx75pFsXcMJd3JiuO6WVka5Lqy)ByWCymeV(WWi07NNUMHzlHzfeAHGy6BnaJrmrjT4(CWGC3JcJPm)fdRWy6dZ6DJpCvsqWWSLmmz)azj9iioKSrdtCX1)MmmKVWTXONIpAqC9Sm1NBo5JZnNb9SayA4o47NprbLm(DpaNYUCWLRWu0NdnpekYN9u(RXqG)bf5SkcH8DdsWhmyX5cv2DNj6(whQNGnuEpJsAUsRsRf2JYyPwvVILLl80fPP5Y1LQnlRQhJGFC4eP3p4OeY0M8Lh0dKcIAPmLTxYgq82udTpfeXINgUcHOUBJddGdzNUS99ZND02i3zDKBToYudJaJbRIG(wcWNFBVIngpm)TJ5e9xcGvfuk0kWNHCquym0fNWoSGtWstF24sNhjk0d6cI9D9zpK5(eBr0gHFUr(IGrjXqIBu46n0SqmBXEDyJLg61dP0hols16ofRBlKJslgjvALIZGP23onuksLXkeAxy9A9Sx6ZiUY)Q8pFHxiY5laRroAswSM((A)knA74UcCXcbpxUSJewh5RgV9ZGVnBdO8isBbngmCLYhKUJRzmXlS92oy3MTwDfF7aHXew22tUtvDjy4wGbfL74eJNfLv6YsFRWQ7vdMQ0DKMuT(qmsPMLvRHQdv)K0lvuNGd48UBMuEOo1O574xJLgbDPqtmAF5uPMWUVwwoA(qaDJ7oaEBroAhns)slF6m2Cu(DPBqsEPEGSlYj9EruxpZxK8wZkxiIS38SG2kUvm30TKESSekbNTfWYewEb4K9ugAuUyCr21I0ci7JaukeNZQ55eVbUdHXBaRRjbEwc2f3PotBmlV3n9vJrM)6bfUYGiWtrqcXf(pqVKusmtfk3Er5maftW0zefAASfCoXeOu0Ohlo2vqlgcmnj05sbuWhdjEq2(h733xAkPx5VQt(VjnwsEGNLGrH8sDSMT7zhnJ97YV(5oMpiQa3dmpDwGvho4wMPTj3B79CVsvB7LzGCOxvfFkjzPDQnA7R5jDJXd4Tm5(M1UzrydQN3NZEyU1J5f)rMpl31FLr7mJ2RiPvLca2tRuHfzB82bhZd3xVHDUq0bxcfhUT8Kx1ZfdJzFafIZMKscpQBLlkBG0H55zgC1X2EhlZn4S4riMWEHwxeIyUeIOTfPfYN94hfTXiZf68Tol8WHm3wiG)YQQSTZcX364cyH03He)oD6olYMVdLHdRQPf1aVuYzVucemDCRMoSbR0knRGHcxIA1WBtLZp3sNZTG70SGCelvkDfyNJeLsQBRM6CfmRHuuz1ymQpdL7T9LBNJNxFE4PsavvbOTwuBoOEJfVGSCuHHfPzQ6BnQ8BxmZPMA0xPq5uXBTqfII2RYbvup8kkiEfveVIsIFbkGF1vW)ZkI1QIpN3FNfEx7tckEG2uD)lA595aEY4l0ozZFtS(Y1yDtLnyF8LO2ZNv5ATwvjbbR)H6MesCXpy6Q3Pt9gOXe0xegKiCtpHnB7NLvSAUcvx82kQJD1f2T2k7wpz3vgTReAkJQNEAB2a30glCwDw4)vUKg0FHpBgDlHUiAs)QcTF)zNbVu)heqPPxQi92QkGi3RlFfBJ3LUUwt01Et8Y1CIlD3jeuDtVVKu7l0YsV5nUOrDUO5TUO19UOrL0jJx0VYMnErP7gYmJLBnieUTlbvAj1jj29gesspTEzpt1n84)2oEivsNuzPw4LP6j)lzxxWUGiD9tf5Pbg9eLTflu2iLAlhvLTq5C7HITMOimg90WkolTqdQrr26UsBBVsx7Vs9ny5s1Hfb9ylNQCZPwpR16j3OtFSmlBvuUvLuUD1uUUIkx73ZRRQYc62w9jlpv6kHFHi8o0FMABqJWhQNTwXzQQDSXyUIViDU5QJ)z70OImv4SiWytAY9zkvK2qxwAwAq0uncsOBqyNf)mCByu4PL9)XS)Rxig25Fp]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261107002,
    [[Hekili:TVvwVnUnq4Fl5fxB0aFL4DZgefGTOxBr72I6TVkzAjkBvllzqsLudy4F7LK6IKHux2zBaQZdbkIKZX3mKA43GypX(l2Z9aeO9NNoE67Mmz87hpEQ9CY(Dq757aUBaROpeb2s)9hXyaghebibXrhx0)54NXbBXdDJ3oGn59HXapMaxMees(uK9sTYgVd6Ap)p)9F6V(H7bII0E(6appy66Gy3Q149hxqwdpUi7DJ8JrWNGOJl8G(GKqYXfF8p(1JlOVM(KICscgXSc8iu8Qe4iVD4rGDH4rzlDi9pg(344ObxtvcceHdPUHh95yMsdWhxa88IJ(g6dBG7XdpU47beW9AmM()2N(cviRjKD47hnAvazDYsM9pszQdOYKAZWzGp46nfm1Z3DifurX(bHuSh4YmD8WDiiDXlbeRLHapOJFyccT)4V8IX)wRr0N3c9ciCV(6em0j233zLRN1KIfyTcGqXe41(XUjyRjxh4B1NjHyNDXbrekwtvamI8WSEx5bxM47pmBjdt2nOqou19eikaVwwpCX1)Q0jvSWnrXphDqJ46zyQWiiA1(HHXpAPmUBmMmONbdMeSf(O1ejRKck7aOuiHzC5km16Znn344qp6t5VgbbE7LKZYW4yph)e0EnECUqfJrzIUVXH6XrdP3tHKMR0Q0AH)inwQx1Ryz5cpDrkAUCDPAZWQ6rb4Ngor49doiyzkt(8B0desIAPmf9x8Aq0MuhTpbesZNgUmoM4SjkWhoKEKWMhTMDW0i3ACKBmoYunJaJaldHEgsWTUPxXgJhSUBmdOFlySYgLeSc8Owoimic6GsOhwWayHPpBCzWdhg4cDarEoE0hYcF8TikJWo3iFrWWKii2jmy1AswkMPCVoSXsX6vtPuholt14ofJBleZslgjvALItJR23mmuksPXkeAxq9AJSN7ZiUG)Y4pBHNjW5nG3iMnjkwDFFTFLoTz7Uc7IMcEQyzhbSoIxnE7NMyB2gqXre2cQnz4cKpiDhxZqIxz)TDMDB2A1v7BliictR2EYTYQlbb3a0OO8ahF8SSSYqw6B5EDVASPkdhPfvRoefuQzz16OQMQxs6LkQtW(mC3jtkpuNAuIDS7EscHoeOoeTVyPutO3xlRgnpiGS2zlaTPOgTdAHFHLpDgDos)DzyqqEPrGSlYj8EEwxp9xK8g9kNlIS38IK2kUklZ1nuESOeknotlGwjS4cqj7iuRr6IXfvxZllaVleqiquoQMxt8A42yeAnyvnfWtlWU4o1zAJ659UQVCoI17guek9dbphcXyh4)aDtsbXmviD7fPZaKCbDNruOPXgSZj6mkjn6sZJD4WIMetDc1siHc(ua2fs3)y(((ctj9k)vDY)vP5sId8IcmkKxAGvVFp7GEB)28RFULgdclS7b6NonXQdhClI0MK7n9EzuPQT9IiqUPxfJpLGSWo1gT9v)KUs7b8gMCF9AxVimzQN2NZEWY4X88FeXZYD9xq0oJO9kkAvIaWEkufwuTXDdoKNUVAn9CHW9oyckyt5jVYNlger)akeLnjPcEK3kxqBGWH55vgCjW2(alnmyp)jictFHs)acPHemVpePSVtF8Z8(sKfcT)o75UOaAylaypVfKtNZAU98SxApN)LqM4juJqrhcF3InJIfNsbSKnuGvY0u3gkTpvoTzEWnkEqUflWXTKzNBjsCDBISBMcUTHqujnjA1NgEyBpp4m7z2PzpvAqvXmSr2Mzg17mefeLJSzyqA6OfRr8ID2CNAipVsHYGI3Bak4SPlJbvquDfmvxbv1vWv9zGz9QPw)RQfRqVod3VZaURCwTueOn0UFw5DNzWF4mTrw)3QQNgfJ7Pmz1hEn4e(KOr1iBpm8DY4oKrC2px6s0PtC23ya6nHdXt3uRxZ0(zrflxQq1KQwb)Yvt4ATmUwpy3veTRaAkIQwDAB2a3uc)pjg))FviPb8()vZPBPPZZMuVPq73F2zJxOVaCtPP3Pi9wKsgrEux8QVAVJBDTmOR9m41RPbN7UgWH6MEDjH2kOuKEZBOqJ6OqZBPqR7PqJOAjdxuVXMjCrQRdIiJHlnWfUP7av6j1jj61g4ssTQEXit1nI4)2oru6ZzYsM3LjQf)l4xNXUtiC7tj5PqcKAHYMYfkBWrTSrvzRno1EByQ5gCNrTmSIZsl0GCwKPUE022E01(EuFJpoxD(GdpMQPk3DQnYAKN3gD6JHzzIP3wr1B746ToYER9751X2lhUnrpz5Psxa8ZeG3H(MuBJt4Xq1Q1kotvUtkARv8vPJkxc8VyNgHxPcdfbABEsEmtIq6w0ae5YGiPAeKqwhJSN)ZWnbHbhx0)hZ()yGpS9)(d]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261107002,
    [[Hekili:TVv2UnUnx4NLCJQnAG3s8SeenaTO9VDkAN(J6P3kzAjkBvllAqsLudy4N9srTrYqQn7mDaQZfbkIKNLVZHuh(DqCM68zNf(ak05tZMm7ntNo5TtMmZzb9WEOZI9aVTG1ShIb7y)ErYkAeKE40YbpJEMeUJmYdTBy68oeHa(PYAvsye9JXoR0kwYEONZI)43)P)8hFGKlnNfBc99Hzlbs8mQNhoTKUbEAz(7ghGWWNG4tl9HbGKi6PLF3))xpTK96tlfers44u1sgJrRtGJ93tgd2hrgNVQrS)y0FrqXdVLjFmiMeXSBF2ZOu9fsoTe47JI)g2dBHhiJoT8hauWdASJb)2h)mtiBO09KhgpEDiDtYQutFSYuhYKjZCHZbV3ZFgyMFG3igkIrbHrmCg4rdrXKr7Xq2IxbO2RIa(q3GOem(WPF5fJ)T2JzpVd6hsbPdDBcb6IccCx75BpTCb2RbymIcVna5LqSNEByG9GujGC3JcJPmyMPaym9X5w34dxLeemkFjJs2pSuom19eioKSrwpCXn4MSjvUWTXONJpQrCwgMkmgIxFyue6d2kJ7Hi0HwgmyA4o4hSNkzLmqzpaNbjPgxHcZS(ctZdHI8zpv8Ame4FqsoRIqiF3Ge8bnECHqfJr5IEGXHS4OH07zqs7vADAT0FKglZRSkxwHWZwKIMRwxM2mSklga)0OPcVF4rbltzYxEJEOqsuhLPO)s2aI3M5OdOGiw(0Ovie1DBCyaCe7iHTFWE(rtJCVXrUZ4iZ0mcmgSkc6Bib3(oRYngpA)UjPa9xdgRSrjbRaFMLdIcJHU4e2HfPaSW0NpPk4rIc9GUGyFxF2d5Hp(weLrsp3OyrWOKyiXnkC9gAEkMPCVESXsX6vtPuhopt14ofJBleZslhjtAvItJRoWmmujsPXkfAFq9gJSx6ZiUI)Y4F6cVqGZxbEJy2KOy1991b160MT7ASlwk45IL9eW6jE16TFAIT5BafhrylO2KHRq(WSDCTdjEL93Uz2DzRvFTVDGWycRA7P3lRUemClqJIkcC8XZZYQczzVL71wnyt1goYkQwDigO0WYA0rvnv)KSlv0KGdsXD3CP8ytQrj2LE3t2DyDPqDi6aXsPMYUVwEnA(qaDJ7oaEBznAh1c)clF2C2CK(7QWGG8YIa5xKt498Sol9xK8o9kNlI838IK2AUkBQRBO8yrjuzCMwaRsyXfGt2tzwJ0fJlRUMxwazFeGsH4cuTOM4nWDimEdyDdfWZkWU8o15AJ55w3mqohX(ndldLbrGNJGeIl8VHEjzGyUkKU9I0zasUGUZik10ed25uDgLKg9y5XUCyrtIPoHAlKqbFkK4bz7FmFFFHPKDL)6o5)MSCjXbErbgLYllWQ3VNFuVTFFX1p3XIbrL29q9tNLy1JdUfrAtY9oRxgvQBBVicuy61X4tfilStTvBF1pPB0EaVHjpqV21lctM6595ShTnEmp)hr8SAx)veT3iQvzrRseaAPqvyz1gVB4XI091ByNleDWLqXHBRo5v(CXWy2hqH48jjvWJ8w5sAdeomVOYGRb2UhyzHbNfpbXe2luAaqelKq49CiJ9D2JFI3dI8qOZ37SWdhYcBHaNfDGC6cwZDwK)sNf8VeMkEkZiu0HW3TsNr5IZOawYgkXkzAQ7cL2NlN2PEWDkEqHflWXTKzxyjsCDBIS7ufCFlHOkAs0Qpn8W2DEWtTN5NN9uRbvhZWgzBo1OEJHOGOCKnddsthTyTIxSlM70a551k0uO4TgGcoB6Yyqnevxdt11qvDnCvFbywVEQ1)IAXk0RNI7VZaURCwTueOl0UFr5Dp1GF)fAJS(Vv1mnkg3tzYQp(AWj8zrJQr2EsX3Pt6rgXf)CPRrNEXzFRbOVkCiE6MA9AM2plQy5sfQNu1A4xUEcxBKX1Mb7(IO9fqZqu1Qt7Yg42s4)zX4))PcjTG3)VyoDhnDE2K6nf6((ZEB8c9fGBkT9ofz3IuYikI6Ix9v7DCBQLb9TNbVEnn4s31aou32Rlj0wbLI0BFdfAvhfAFlf6CpfAfvl54I6n2mHlsDDqezmCPbUWnDhOkpPjjXU2axsQv1lgzQVre)72jIkFoxwY8UmvT4Fb)6c2DcHBFkjpfsGulu2uUqvdoAKnQABTX52Bdtn3G7mQLHvEwAPgKZIm11JU22J(23JMB8XLQZhC4XunvfUtJrwJ882QtFmmltm92jQE7gxVnr2BJFpVj2E5WTj6jRov6kGFHa8E03KgBCcpgQwTw5zQYDsrBTIVkDu5AG)f70O8kvsrrG2MNueZKiKUdnarUmiAMgbj0niSZIFgUnmk80Yb)V8)pg4d78p]]
)
