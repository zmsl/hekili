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
-- Improved Slice and Dice +15% a rank (14165 aura 108 base 15); Rupture 6 + 2 a point. Blood Splatter (1329256: duration
-- +6000 ms on Rupture's class mask, +9000 ms on Garrote's) adds 6 s to Rupture and 9 s to Garrote. Read at the
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
            applyDebuff("target", "garrote", 18 + 9 * talent.blood_splatter.rank)
        end,

        handler = function()
            removeBuff("ghostly_strike_next")
            applyDebuff("target", "garrote", 18 + 9 * talent.blood_splatter.rank)
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
            applyDebuff("target", "rupture", 6 + 2 * combo_points.current + 6 * talent.blood_splatter.rank)
            if talent.relentless_strikes.rank >= 5 and combo_points.current >= 5 then
                gain(RELENTLESS_ENERGY, "energy")
            end
        end,

        handler = function()
            applyDebuff("target", "rupture", 6 + 2 * combo_points.current + 6 * talent.blood_splatter.rank)
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
    20261108000,
    [[Hekili:TV12UnUnt4NLCJRn6cFkXBZgefG2(3dBr)BlQBVvY0su2Qww0GKkPgWWp7LK6Gjzi1j7SDbQ3l2vwKCMV5BgsnCgSUtC)d35bak09xMoE67Nmz89Jhp2DoD)oO78Da)nGvShsaBz)93I2UeqpUO)lOxirBjd9rBhWN1(yeiGlPLPrX0pM4U0Oqj7G(UZ)9F9h(ZV7bFHSCNVokiaMTaiX3IoE44c6A4Xf5VBuicdFgIpUiagcsJzt)R)TF(4c2RpUOuaPrJ4kKmcJwLchfSJmcSlMmkFndz)y4FrqjdEht6yqcjMH4a2ZiU2IihxaccqjFb7HnW9KHhx8)auWdgqr)))h)dMqwtP7ipmA0Qi660LCGpsBQdyYKbn4mWh8dMcMge6pKXFyuyumJFb(0iucz4ommJECwgdcGEHXPy8(J)0Rg)lDgXEElmiIc4d9Uuc0dfg6TYpWzs5cCWr7qekuD43fI8tjS)nk0bMaXR2pmg9Kt2AgMVeMvqOLcIPVvamgXeL0I7ZbdYBhkkHY8xmSctOpoR3nbWLPHHdZxYW0DdKL0ZGKiYAnmXfx)BYXqXc3KGEj5GbX1ZYuFT5umo3Cg0ZcGPrBHp5mrbLm(DhaNXUCWvOWm0xanFekoG9uXRXqqWEf5SmgHc8ctX7nyXfcv2DNl6(whQNGnuEpJsAUsRsRL2JYyzwvVYLvi8SfPP5tRltBwwvpgb)8WjsVFWbjKPn5lpOhife1szkBVK1GKnzgAFkiMfpnCjcr92KefchYoDzZtoZoyBK7SoYTwhzQHrGjGLXWalb4o32RCJXJo3pMt0FoawvqPqRGagYbXrjqpCk7Wcobln9zJp58iXr(qpqsGxa7HC3NylI2i8Znkwemonbs8IJwTMMhIzl2RdBS0qVEiL(W5rQw3PyDBHCuA5izs7K4myQ9TtdNePYyLcTlSETE2l9zex5Fv(NVWle58zG1ihnjlwtFFTFLgTDCxbUyHGNlx2rcRJ8vJ3(zW3MVbuEePTGgdgUs5dY2X1mM4n2EBhSBZwRUIVTGOeclB7j3PQUumCdWGIkCCIXZJYo5YYERWQ7vdMQ0DKLuT(qmsPMLvRHQd1G0SlvuNGd58UxUuESo1O574xJLgd9OqtmAF5uPMWUVwEoAbqaDT3waEtzoAhms)slF6m2Cu(9j3GK8Y8a5xKt69IOUEMVi5TMvUqe5V5vbTvCRyUPBj9yzjCcC2walty5fGt3rzOr5IXLzxlslGSlgqPqCbRwKt8A4wegVgSQMe4zjyxEN6CTXS8E30xngX59dkDLHXGxIHeIh8VH(PzKyUkuU9IYzakMGPZik10yl4CIjqPOrFwCSNGwmeyAsOosbuWNJi(q2(h733xAkzx5VQt(VjlwsEGxLGrP8YCSMT7zhmJ97kU(5wMpiUe3dmpDwGvho4wMPTj3B79AVsvB7vk8ZAgpgV3JqXrBGvv3NsSRwugTY3uIH7uz6ckQrAq(eHgDmH5jDJXpKyzY9nRDZIWgupVpB(OJ1pNi(JmFE60LRmANz0ELjhRet3ZCm9to3p4qX2k19nLBTup)nkH9HAiwEZ1ngpYOS8esF0OidKRo227yzUb35pdXe2l06wrmZLqeThjRHbSh)fr7sYDHUFJ7CFCeZTfb4VSQkO7ox8nvUaMl99oXVZMU78857sz4WQAArT2pj58xkbcMoUvth2GvwfTvWGLd4Btf6p3s0ZTG70SGcelvYEfyxGeLs3BR29CfmRHu0PQ(yuFgkRC7lRphpV)8WtLaQQcDBT45Cq9vw8cYYrfgwKMPQ81OY8DXmNA6fqLcLtf3BHkenhqLdQOU7vu49kQ8EfLE)c0OGQ7uWNueR1TaoV)bl8U2Neu8aTPlcx02iWb8KXxODYM)My9LfY6MkBW(WBrnUpRYcBT6vccw)d1njK4IFW0vVtN6brJjOplmir4MEcB22plRy1CfQUiXvuV8QlGCTvqUEYURmAxj0mgvp902SbUPnW4S6GX)PCjnOpgFYm6wcDr0K(vfA)(ZodEP(CiGstVur2TvvarHxx(k2gVlDDTaPR9a5TRjix6UGiO6MEFjP2KOLLEZBqsJ6qsZBrsR7rsJkPtoVOFLnB8IsxuKzgl3AqiCBxc6KLuNKy3Bqij906L9mv3yL)D7SIujDYKLAHxMQN8VKDDb72I01pvKNgy0tu2wSWPg2uB5OQSvnNBVAS1SgHXONgw5zPLAqnkYwxCABBC6AFCQVroxQo5iOhB5uPwI6A9V2BXtv94rGaBLSRGqBLUvktCJo)ZYSSvt7wvu72vv76kRDTzuuxDTf0TEUgf09PZfVs4xicVdDiQ2wej8H6jXuEQUApJmMT6BsVJU64F1onQixjolcm2MOcFMsnXn0NNMLigntJGu6Ae2D(pc3efhDCr)Vp))KjIHD)N)]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261108000,
    [[Hekili:TV12UnUnt4NLCJRnAGpKeVnBqua2I2)2TOD7pQ3ERKPLOSzTSKbjvsnGHF2lj1btYqQt2z7cuNlcuejNdFZqQHFdI7e3p7olaqHUF6MX38UjtgF)4XJDNr3Tf6oBlWFnyj7HyWg2V)aHaieumGIsIpmV)ljVqqBid9t2mGp5DrjGaUaxKIIOFm2DHrzt2c9DN9h)(p9N)4dazr6oBfkiaMToiXVAn(WH50vWdZZF3OWem8zi(W8ayiinIEy(h())6H5SxZEstoPOrCRGmcNSmfokylzeyBezu(shY(JH)fjjEW1mLGbXKiMBeWEoHRue5WCqqqs83WEynChz4H5)aGcEWGX0)3(4NzczfLUL8WOrlr0vPl42)iTPoGjtMndNcEVFWnGBcc9hYavCsikIH9aFUPtgUfdzlEbG6Sicea9cJsX4Dh(Lxn(36mI98gyaIk86RtjqVKWqVL(botkxGZsagNqHxhM4NsCMCnk0PpxcjEBtqXugwZuamM(40ExfaxKggomFjdt3oOuom19migrwPQhH46Fv2Kkx464KxI3BqC9SmvymeVC3WOKNC0g3pHqh0ZIbtrBGp5mrXkzGYwaods4gxHcZS(ctZpjjkG9uXRXqqWof5SikjjWlmfVZGhxiu5yuUO7BDOEc0q59miP5kTkTw6pkJL5v9kxwHWZwKMMpUUmTzzv9ya8ZdNi9(b7LSmTjF(n6bsjrTuMY(lzfiEDMJ2NcIy5tdxKKq9whJcHdzhjS(jNP7TnYDwh5wRJCJHrGXGfrWalj4o32RCJXJo3pMd0FnySQgLcSccywoicfd9WPSdl4aS00No(yWJeH8HEG4aVa2d5HpXweTr4NBuSiyuAmK4fHwUIMNIzl3RdBS0SE9uk9HZZuTUtX62c5S0YrYK2rXzWv7BhgoksLXkfAxq9AJSN7ZiUG)Q4pFHNjW5RaVroBswSM((A)kDA72Df2flf8uXYocyDeVA82pdX28nGYJiTf0yYWfiFq2oUMHeVX(B7m72S1QR23gakMWQ2EYDQQlfdxdmOOIaNy88SSJHSS3k86E1ytvgoYkQwFigOuZYQ1r1n1G0SlvuNGd54UxUuESo1Of7439Kgb9OqtiAF5sPMWUVwEnAbqaDL3gaEDznA7nc)sl)MPS5O83hddsYllcKFroP3lY66z(IK3Aw5crK)MxL0wXvz5UULYJLLWrJZ2cyvclVaC6wkZAuUyCz11IYciBJaukexGQf1eVcUjbJxbwwtb8ScSlVtDU2yEEVR6RMJ48UbLHYWiWlrqcXd(3q)0mqmxfk3Er5mafxW0zeLAASf7CIjJsrJ(S8ypbSyiX0KqDKsOGpJi(q2(h733xAkzx5VQt(VklxsEGxvGrP8YcSM97P7nB73vC9ZnSyquPDpW80zjwD4GBzK2MCVT3RJkvTTxgbwUIHJr78iumAnSkEFkTDvsz0OVP0gUtfPlGOgPb5teA0XeMN0vg)qILj33S2nlcBM6P9zZhDS(5eXpY45XtxUGODgr7vwCSsoDpZ50p5C)G9fBRu33uU1s98xum7d1qS8MRRmEKrj9esF0OOcKlb22hyzHb3zpdXe2l067qelKqe97iJLF2JFs0)J8qO737oZhJyHneWDwlibVGDE3z5V0DM4lUCXtzgHMoK((iFgLloJQzfBWYjVTH68tL7CUhCRMhuyXsCPRy2fwIcN62ivNRG7AieDKogJ6ZaFVTNVDU9m90SNknOQyG2kR2CJ6DwIcYYr1mSint0V1i(3oBUtnK0xPq5qX3zbkeS2RIbvqiEfmIxbL4vWj(zGb)QPW)lQfRrJph3V3cURDwTseOn07Fw53NBWV)mTr283QQNUgR7PSz17Fl4E(KOR1kRsC8DY4oKrC2px6s0Pt9gOXa0xfoKiDtVEnB7NLvSAPcvtEBf8yxnXU1YSB9GDxr0UcOziQE1PTzdCtBSWj1zH)tfsAq)f(I50T00fzt63uO97p7SXl1)bHP007uKDlsfJOiQlF1xJ3XTUwt01Et821CIZD3jeqDtVUKu7l0ksV5nUOrDUO5TUO19UOruTKJl63yZgUO0DdzKXYLgec32DGo6j1jj21gessVQE5it1n84F3oEC0NZLLkVlt0l(xYVoJDbr62NkYtJei9cLTLlCSrk1YgvLTq5u7HITMOiCg9YWkplTudQzr26UsBBVsx7Vs9ny5C1Hfb8yRMkvQJRn(AV1lv17fHfyJXUcaTv6wH(2gD(NLzzJR5wr2C7yBUo6MRTII64Bwa361Aua3hpx8cGFMa8o05MABDJigQxet5P6Q9YXy1QVj905sG)v70OIAL4OiWy7BkIzkuI3IwWOwigntJGu6QeS7SFgUgfHomV))l))ydXWU)Zp]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261108000,
    [[Hekili:TV12UnUnq0VL8IQnAGVKeVnBquaArVTfTBlQ3(QKPLOSvTSKbjvsnGH)2lj1nsgsDZoBxG68qGIi5mdpZqQzodIZuNp5m3hqGoF8Mj38UPtNC)KjtCMt2Vd6mFhWBdyf9HyWw6VNNUKebj7pUyWljVGd3Ih5LSDiBE7Jsa(mzTmnmI8HyNLAflEh0Zz(F(7)0F9dpGZLMZ81H((WSLaXEg1ZdhxqwdpUi)DJdsqWNHOJl8HbG0iYXfF7F8RhxqF9XfcIinCmtT4XOKvPWX(7WJb7IWJZx1i6Fm6VXjXdVMkFeighrTBF6Zjm9fIpUa47Ne)v0h2a3JhDCX3diGh0yhd(Tp8jQqwti7WpmE8QqY60LmtFSYuhsLj1CHZaV3Z)gWn(bEJOOikjimIIZapsysmE0oeKU4LaI9YiGp0nikfH2F8xE14FT9y6ZBH(HeaBORtXq3KGa3vE(2tlxG9kacLqGxhK4LITNEDyG9aMesC3LegtOWmvbWyYJZSUYhUmniyu(sgLUByPCOQ7zqCiETSE4IBWvztQCHBItEj(GgXzzyQWyiA1(rrjpzRmUxcMm0YGbtc3cFYEQKvsbLDaugKWmUcfMz9fMMxssKp9PIxJGa)9sYzzusIVBqkAVMDCHqf9r5IEGXHS4OH07Pqs7vADATC)inw2UYQCzfcpBrkAUADzAZWQSOa8ZJMk8(HheSmLjF(n6HcbrDuMI7x8Aq8MSn6aciIgpnAzscXDtCyaCe9kHnpzp7GPrUZ4i3ACKB0mcmgSmc6Bia3(wRYdgpAF)egq)LGXkBusWkWNA5GOWyOlkLEzbdGfM(SjvopCuOh0fe776tFi39XpIOmc7EJIfbJsJHy3OWvRj5HyMI96XblfRxnKsD48ivJNumESqmkTCKmPvjonB1bMHHkrknwPq7dQ3ON9CFhXf8xg)zl8mboFbSBeJMefRUVVoO2nTz7Ug7IgcEQyzpbSEIxT(4NgFB(bqXreocQny4cKpm7ex7qI349B3m7UC0QV23wqymMMT907KvxkcUbOrrfoo(45rzvUSS3Y31wnyt16oYsQwDikO0WYACJQAQ(Pzfv0KGdy4UBUuESj1O47y1EsRH1La1HOdetLAkTET8C08HaYA3Ta0MYC0oOf(fw(nZOZr6VRCdcYlZdKxiNW75rDw6lK8w9kNlI838QG2AkLLT1nKESOeQmotlGMjS4cqP7iuRrQW4YSR5PfG3fbieiQavlYjEnCBccTgSQHe4PjyxwtDU2O7CRRgihJy)UHLUYGiWlrqm2f(pqV0mqmxfsvViDhG0wq3DeLAAIb7CQoJssJE04yxoSOjWuNqTfcOGphI9G0ZpMR3xykzL8x3n)xLfljoWRsWOuEzow977zh0B73vu(5wQpiQ0UhQF60aRECXTisBsU3A9AVsDh7frGvRP4y0ExmbfUbwhVpL2UmPmk03uAd3jJ0fquR0G4ncT6Ac9t6kTFiXWKhOx76fHjt90(S5J2g)Cc)hr8S62LliAVruRYKJLIPT0ht)K99dpuCSs(Ct5rl57FdJPFOgIepCDL2RmkPNq4JgfzGCXX2Dhl1n4m)zictFHsJgIOUemV3gzS8tF8J8EDK7cD(oN5EOqQBle4mVdKGxWoVZ88x6mN)fxM4juJqrhcFFKnJYfNr1SKny4M3UqD(PYDoBhCRYoOWIf4sxYSlSejo1nrQotb31siQIogT6tdFVDNVDM9m70SNAnO6yG2iR2mJ6Dg8cIYr2mminD0V1k(3oBBNgiPVwHYGIVXauWzTxgdQHq8AyeVgkXRHt8Zad(1tH)NvlwHgFgUFVbCx5UAjpqxO3)SYVpZGF)z6GS(Vv1mDngptzYQp8wW98jrxRrwLy470j9iI4SFV0fVtV6nqRbOVi2q8Wn181mDEwuXYPkup5T1WJD9e72iZUnd29fr7lGMHOQzN2LdWTTXcNuNf(FLlPf9x4Z2MUJMopAsTsHUF(S3gVq)h4MsBRPiRksjJOWRlw6R2ACBQ1e9T3eVDnN4C3Dcou32YLeAFHss6TVXfTQZfTV1fDU3fTIQLCCrTInt4Iu3nergdfnWfUPAGQ2jnjjAzdCjPMvVONP(gE8FBhpQ2Z5YsM3LPQj)lSVoJDbrO6tj5PqcKAIYMIfQAKsJSrvBluo1EOyQjk8nJAAyL3LwQb5OitDxPRTxPV9xP5gSCU6WchEmLtLm1Xn6Fn36L669c3cmXyxbG2jDlrFBRU)ZWSmX1CNiBUBSn3eDZnMrrt8nZHB1CnkG7Q7fVa4NjaVhDUPXw3W9HQjXuERUCVC0MT6BspDU44F1jncpxjgkc02(McFMeL4DOfmYjIrY0iiLSob5m)NHBcJcpUyWpM)FSbFyN)9p]]
)
