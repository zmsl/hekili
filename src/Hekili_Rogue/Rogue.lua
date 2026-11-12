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
-- Composure (1329265, the rank curve {-5, -10}): joins Poised's own discount, on the abilities the buff names (wowsims
-- poised.go). The -10 is the cost modifier below; this is the talent's part, a cost step the abilities' `spend` takes
-- while the aura is up (`buff` and `talent` are the caller's: the sim's state or the belief's).
local COMPOSURE = { [0] = 0, 5, 10 }
local function poised(buff, talent, cost)
    if buff.poised.up then
        cost = cost - COMPOSURE[talent.composure.rank]
    end
    return max(0, cost)
end

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
-- regen: energy's base rate a second, the belief's from the build until a plain rate read (energy is secret even out
-- of combat): wowsims/forever's 1 energy every 0.1 s (sim/core/energy.go:48-49).
-- refundOnAvoid: the share of the energy an ability flagged `refundOnAvoid = true` gives back when dodged, parried or
-- missed (wowsims/forever's MissRefund, spelldata/attributes.go: 0.8 where the DB2 flags Discount Power On Miss and the
-- spell issues the refund). Not Slice and Dice, Vanish or the poisons; Gouge is flagged in the DB2 but wowsims issues
-- no refund for it (and the kit has no Gouge).
spec:RegisterResource(Enum.PowerType.Energy, {
    adrenaline_rush = { aura = "adrenaline_rush", mult = 2 },
}, nil, { regen = 10, refundOnAvoid = 0.8 })

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
    boot_knife = { 3, 1329286, 5 }, -- Shank's chance of 2 combo points (20% a rank): the certain 5/5 part only
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
    -- Remorseless (14143, the talent 14144's buff: 20 s, one charge, +40% crit on the strikes the pin's mask names): a
    -- kill opens it and no event here ties a death to our kill, so only a client or Cooldown Manager read shows it.
    remorseless = {
        id = 14143,
        duration = 20,
        max_stack = 1,
    },
    -- Slice and Dice (5171) and Blade Flurry (13877) each give +20% melee haste (A_MOD_MELEE_HASTE_3, pin spell rows):
    -- unmodelled: the core's aura field `swingHaste` (C5) would rescale the swing clock, not set here yet (attack speed
    -- is secret in combat).
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
    -- Poised (passive 1328825, buff 1328826; wowsims poised.go): out of combat at full energy the next Ambush, Backstab,
    -- Blade Flurry, Eviscerate, Expose Armor, Garrote, Ghostly Strike, Hemorrhage, Kick, Mutilate, Riposte, Rupture,
    -- Sinister Strike or Slice and Dice costs 10 less (the cost modifier below; Composure adds to it in `spend`). One
    -- charge. Read from the client out of combat (the player aura walk), carried by the belief in combat. Not yet
    -- checked in game (the Druid's Poised is the same shape).
    poised = {
        id = 1328826,
        duration = 3600,
        max_stack = 1,
    },
    -- Venom (talent 1329328): Shank gives +30% poison damage for 6 s.
    venom = {
        id = 1310703,
        duration = 6,
        max_stack = 1,
    },
})

-- Poised's discount: aura 107 misc 14 -10 flat Energy on the class mask {255727518, 2099456, 67108864} against
-- SpellClassSet 8, read off the pin's class flags (the kit's rank-1 IDs, the ranks through each ability's `copy`;
-- Shank, Death Mark, Vanish and Premeditation are not in it); one charge.
spec:RegisterCostMod({
    aura = "poised",
    flat = -10,
    charges = 1,
    spells = { 8676, 53, 13877, 2098, 8647, 703, 14278, 16511, 1766, 399956, 14251, 1943, 1752, 5171 },
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

        spend = function()
            return poised(buff, talent, 60)
        end,
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

        spend = function()
            return poised(buff, talent, 60)
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

        spend = function()
            return poised(buff, talent, 25)
        end,
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
            return poised(buff, talent, max(0, 35 - 15 * talent.flawless_execution.rank)) -- 1310711's -15 (4b0030a44b; the log's 20)
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
            return poised(buff, talent, max(0, 25 - IMPROVED_EXPOSE_ARMOR[talent.improved_expose_armor.rank])) -- the curve {-5, -10}
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
            return poised(buff, talent, max(0, 50 - 10 * talent.dirty_deeds.rank))
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

        spend = function()
            return poised(buff, talent, 40)
        end,
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
            return poised(buff, talent, max(0, 35 - EFFICIENT_STRIKES[talent.efficient_strikes.rank])) -- the log's 30 at rank 2
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

        spend = function()
            return poised(buff, talent, 25)
        end,
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

        spend = function()
            return poised(buff, talent, 10)
        end,
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

        spend = function()
            return poised(buff, talent, 60)
        end,
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

        spend = function()
            return poised(buff, talent, 25)
        end,
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
            return poised(buff, talent, max(0, 45 - EFFICIENT_STRIKES[talent.efficient_strikes.rank]))
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

        spend = function()
            return poised(buff, talent, 25)
        end,
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
    -- bonus. No combo point of its own (wowsims's Shank is no builder); Boot Knife at 5/5 gives 2 for certain (the log:
    -- 17 of 17 Shanks), ranks 1-4 are a chance that is not modelled.
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
            if talent.boot_knife.rank >= 5 then
                gain(2, "combo_points")
            end
        end,

        handler = function()
            gain((knownRank(SHANK) >= 2 and 25 or 15) + 3 * talent.flash_of_steel.rank, "energy")
            if talent.venom.enabled then
                applyBuff("venom")
            end
            if talent.boot_knife.rank >= 5 then
                gain(2, "combo_points")
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
    20261110000,
    [[Hekili:TVvBVTTnx0Fl5lA2yf2XoXDTbrbyBp7LoSNUH5UVkzAjkBollAqsLmdy4F7JI6ftYqQ3StxbwYhAvejV3dpxsQlVheVjEFYBEiGb9(40RN(2jtMCn)hV5S97GEZ3bc2awXFibSL)VFpE7sa74IbpHFII2shfG3omRx7JXGWmlTmffZ(qI3sJgLUdg4n)p(TF6p)H7ce2YB(AuyimFaqAGfFC3XfS1WJlkE34imb(iKCCrimcKgZ7(3(7)6Xf8xFCrLbsrJZCiDmbVkfooChDmyxmDCXygX)Lr)ffNm8nCRtaj0yoId5pJZ8gIECbimeN8v8h2a3thDCX)dWa3zafd()F4tCJSMX2rVB84vi260LzaFSwxhYTjhAWzG3heofmnmkyeN)i4iumNFbbmeoHoAhbMtpUlJbHq)O4ucz)XF5zT)1UJ5pVfgIyGSMEtkf6JJI8xfe6oPAaUe0omLbvB(nr4Guk))rrUWeiz1(rX4hCZhZOIHWNfuwLH4(BfGqWCtjn4bzGb7VdJsy84fhRWe29ZCUkeUmnkAuXqgLUBOSLEeKGOR1WuM5gCvbgkh4Me8tjhmyohlD95tNY2ZModDSaygAl8b3jkOKZV7aKC2ndCLomh9LqlaJJd5pv(AceeUxXolJX4q)OuYEdZ4sJkhUlm9aRn5iydL3ZPK27068A18rPT8zLt1WknE(G088PXL7nlJYHtWpoAI07hEqczAD(Yd6HslI6OnvMVqcfs2Gswvt4LgJcG(GKq)q(dfEqef1ArBNcDniztoloGbI5lwhTeJz(BsqrWr8JU28G7Sd2A5wRTCJ1wMAOfycyzmm0YUh3BCQ21DV77Uolk(LayvbLcTcc5iheJsG(Ku(jrzeSu3NDTtVICoLdcgNMaP(XOvRzfRFTTWUh7A1qV(6v9Ml2gyDBO19CYBbQAj3ANmNHP6a70WjtQ0wLr7dR3yK9sFa0R8Vk)NnWle58fWSrE1KSznD6(GAN02XDn4IVe8C5YEsy9KVA92pdX2InGYTiTf04IHxP8H574Aht8cpF7gS7YwR(IVTaucLNk)KBvDxkbUbyWrLbor7fRYofYYFRyw70aMQnCKNXUEtCsPHH14evhQHP53yPjdhLX7(fw5(MCJwSl7oYSyOpdAIrhiNk1e(LblYrlecyR93ciBQYr7Gr6xA4tNX7JYVFkmizV8iqXTeLEVyvNJ5BPEJzNlmrXBE2I2AUYD2u3s6XYw4e4SnaEMWYdGKUJXrJYTURYUwKwaDxmGXGKswTmN41WTycznyvdjWZtWU6c7fEJpZDUAG6Ae33oSkugfdEkgsP(W)ggKMtIfUq52lkNbOmfmDgrLNU2coNycukEmGVo2xqlgwyAYOUslOGpIObq((h7ftqQl51tOUt(VkFTKCdplbJk7LhynpVNDWm2VT8UTB5XG4kCp0C35lS6Xb3YmTn7EJZZJk1TTxPQsR58y8EFkJG2aRROsvyxTIpA1gQcd3QY0LuuR8G8jcT6ycZD6kJFiXsNhy27MnHnOEEF28ExRFor8JmFE60Lxz0EZOovjhRSM2X8A6hCF3WdLBRu33uT1s98xuc)d1qI8MRRmEKrv5jK(OrzgiVgy7EGLhg8M)iKq5VqtkKyEiHk0Ejxnc(JFuOftri0778Mhqq8WgcK9Y6kpV3CX3uZmWCPV3j(98U7nVO)EmooS6Moui)twU4LsGG7JB08HnyLxUCfmy5a(Uu()ZT()zZGB1MbLiwspafyxIefDbSjmqMdM1sk6uvFm6pd1SU7AgKHN3EE4Pwavxv0Twz(mq9nwIcY2rfgwSMPQ81QY8DXMoni0qTgnJkExBJpvkryC9IXu(SDz9m)(ElHaHOeQCFn17VMc(xtf)RPK)xabkQxHIpRiwtLImEFY1wiETVfPec6I8fxu9leiw)dy99ieZFmU56rzD3SnyF4LO46Nv9OTw2mbbR)P72SK4IFI4RrNEj(rRjOViMqILBTnlozhR(rN6RoDnfQV(kx3yPRBMS7lJ2xcnNrTLvzB2a3wLtolPt(pviPfcO8zBs3rOlwn12RqyF)zVbVKalcO02BpKFnzfqug1LVBVXlX3K2l9v8Lxo1xU0YViOA97ezJQL0Nrln92RmtRKMP9AZ0zXzAvTKk4L2Ebjf5BKzglxBqyCB3c60mPjlXV4GO6l6P1lhzQxrN)DL0rQws52sTIptTx9QlPmps3)uXEAGrprzBRfoPuuJ1bRwnIoxrISPsKyYONgw1zPvEqDvKn5J6Q(r9vaPMvq6sjHKGESLtLATXBm(AxBP6exsGa9VdxIGscTt(wP(0T68pl9YwX07u107w50BQE6nMrrtfuxq365Aus3Nox8vc)cr49qAQg1MsedTvyxnXQmMT6lIOvVg4F2onMixPmweyuFQYyMsX4niWu7seJL7rqkBnM4n)NHBqXOJlg8Jf)PZiA27Fo]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261110000,
    [[Hekili:TVvxVnUTs0Fl5fvB0a74K4T7gefGTO92UfTBVOE7RsMwIYM1YIgKuj1ag(3EPO(WKmK6l7Snan(HfkIKZCMZmKA4my9M49fVzHag07ZxF11VBYKjxX)5nJTBl0B2wqWAWs(djGn8)9JukGsrjagcNCy(GNWprrBOJcWBgMn5DXyqyMaxKIIzFkXBHrzt3cd8M9h)(p9N)4Dazr6nBfkmeMVoinOEnE3H5SvWdZlE34imb(iKCyEimcKgZom)J))F9WC(R5pPjNu04muqhtWltHJd3shd2gthxS0r8)y0FrXjdVKReciHgZnJq(Z4mLIOhMdcdXjFd)H1WD0rhM)dag4odGzWV9PVWfYkgBl9UXJxIyRsxKH)XAtDixMCmdNc(qq41GRdJcgXjvcocfZ5Eqqg0PJ2sG8fVaWCxedcH(rXPeYUd)YZg)BDhZFEdmeXew9LPuOpokYFzqO7KQf4Ueqiyg8YiCqk1DYLOi3bzsa7VfJsyCUMRayc7(PoxecxKgfnQyjJs3oSsoC19iibrxPQhH4gCr(KQw46e8tj7niohltfMajl3nkg)GR24bykBOJfaZqBGp4orbLCszlGKtjzGRuH5OVeAbyCCi)PYxtGGWDkYzrmgh6hLs2zWIlfQSpQq0dSoKJGnuEpNsAVsRtRv2JYy5wLt1YkfE(I008X1LRnlRYHtWpoAI07hUxczAt(8d6HsbrDuMk2lKqHK1OKL14EPXOaOpij0pK)qHgeErTr02PqxbswNZIdyGyEW6OfymZFDckcoIFEZ6hCNU32i3ADKBSoY1ggbMaweddTS7X9gNQDD37((RY8IVgaRkOuOvqih5Gyuc0NKYpjkJGLM(0RC6LNZPCrW40ei1pgTCfRi(1wGDp21QHE94v9Hl2gyDBO19CYBbQgjxAhfNbtDGDA4OivgRsO9H1B0ZEUpa6n(xL)Zw4zICEfynYrtYI10P7dQ1OTJ7AWfpe8u5YEsy9KVA92pd(2InGYJiTf0yWWBu(W8DCTJjEHT3Ub7US1QV4BdaLq5PYp5wv1LsGRbguuPJtmEru2rxw(BfwTtdyQw3rEg76dXjLgwwJgQoudtZVXstcokJ39lKY9nPgnFx2fBzXqFg0eJoqovQj8ldwKJwieWw5VbqwxLJ2EJ0V0YVEkFok)9r3GK8Y9af3su69IOohZ3s9gZkxiII38SG2AUNCMPBj9yzjCeC2wapty5fqs3Y4Or5w3vzxlslGUngWyqsjRwMt8k4gmHScSSHe45jyxDH9cTXTCNlgOgJ4(UHvUYOyWtXqk1h(3WG0CsSqfk3Er5maftW0zevA6kl4CIjqPOXaECSVGwmeyAsOUsbuWhr0aiF)J9IjinL86ju3j)xKhljpWZsWOsE5owZ2909MX(TL3TDd3hexH7HMNopWQhhClZ02K7nop3Ru32Ezgy5kopgVZNYiO1W6kQuf2vR4JwTHQWWTQmDjf1kniFIqRoMW8KUW4hsSm5bM1UzrydQN2NnV316Nte)K5ZJNU8gJ2Bg1Pk5yLyAhZX0p4((H7l3wPUVPARL65VOe(hQHe5nxxy8iJQYti9rJYmqEZX2Dhl3n4n7riHYFHwtnI5UeQOzk5TqG)4NfnxPWf699EZciiUBdb8M1HkSxw6FVzfV0BM4lUzINXbHMoK((y2mQwCEDSvWGLtE7sD5p1cZNzb3OzbLiwQq9kWUejkfS3wf7ZuWTTKIowogJ6ZqXK7EX8ZWZ0tdp1cO6kVT1sMNbQ3zXlilhvyyrAMk)wRQ)2zZCAOda1k0mQ47AR)PQfbgJxmMlMTBrNP33BXfi6wGk3xtH4RPs81uk(AQf)zOZb136GVQiwR9bz8(hSW7AFJqXd0L2kCw7RqgGNCvBJqB4eeZFKS56ezDZSnyV)LOO3NuDITwolbbR)L72esC2pq8nVtVAkrRjOxfgKiCRTjXjRy1V5uFvJRPa61xr5glPCZKDFz0(sO5mQTKkBZg422rJtQLg)NYL0IgB8vZO7i0frtT9ge23F2BWl14dbuA7LhYV(Qcik96Y3524LRBQNi9TPiVCDf5C3webvRFLiBuTuFt0YsV9DmPvTmP99mPZnnPv14PGxA79JuARImZy5wdcHB7sqhTKMKe)EdcjPNwVSNP(oT8VBRwoAZfYsRGp6j)lzxNX2ViD9tf5Pbg9eLTflCSdonwgSA7DZP28gBDVrym6PHvDwALguJIS1wNU2xN(2yNM7SZ5Q1oc6XwovQ1SUr)R9E(uxtFeiq)7WLiOKq7KUvQBCRo)ZYSSvK7ovL7UvM7MQZDJzu0uHUf0TEUgL09XZfFJWpteEpAzuJ9ms4dTvxxTMizmB1xKMj9MJ)z70yICLYyrGX(gv6ZuQfFh69JAIySCncszRWeVz)mCnkgDy(G)xX)pued79pd]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261110000,
    [[Hekili:TV1wVTTnu4Fl5fnBSa74K4U2GOaSHDRdBDdZDVkzAjkBollAqsLmdy4F7JI6Ijzi1n70fGf)qHIi558XVZHuNlOEt8(S3Sqad69PRV663nzYKR4)8MX2Tf6nBliynyj)HeWg()olDblgY2Dy(GNWprrBOJcWBgMnVDXyqyMSwKIIzFmXBHrXs3cd8M9N)(p9x)WD0cP5nBfkmeMVeinWQEU7WC2k4H5fVBCeMaFesompegbsJzhM)T)XVEyo)1hMljIu04m1shtWltHJd3shd2gthxSQr8)y0FtXjdVKlFciHgZXDi)zCM(q0dZbHH4KVI)WA4o6OdZ)EadCNbCm43(4N5czfJTLE34XlrSvPlYG(yTPoKltoCHtbFii8AW1HrbJ4SibhHI58miGHWj0rBjq(IxayUlIbHq)O4ucz3HF5zJ)1UJ5pVbgIyGSHUmLc9Xrr(ldcDNuTa3LacbZGxgHdsPUtUef5oitcy)TyucJtZCfaty3p15Iq4I0OOrflzu62HvYHRUhbji6kv9ie3GlYNu1cxNGFkzVbX5yzQWeiz5UrX4hC1gpatzdDSaygAd8b3jkOKtkBbKCkjdCLkmh9LqlaJJd5pv(AceeUtrolIX4q)OuYod74sHkBJke9aRd5iydL3ZPK2R060A1(rzS8DLt1YkfE(I008X1LRnlRYHtWpoAI07hUxczAt(8d6HsorDuMk7xiHcjRrjlRX8sJrbqFqsOFi)HcniSIAJODsHUcKSoNfhWaXCN1rlWyM)6eueCe)(M1p4oDVTrU16i3yDKRnmcmbSiggA50J7novN6U399xLzfFnawvqPqRGqoYbXOeOpjLFtugbln9Px50llNt5IGXPjqQFmA5kwH)Rnh7ECQvd96(R6dxCmW6XqRN5KpcunsU0okodB1b2PHJIuzSkH2hwVrl75(cO34Fv(pBHNjY5vWUr2BswSMUDFqTBA74UgCXDbpvUSNewp5RwF8ZGTT4aO8ishbn6m8gLpm)ex7yIx49B3GDxoA1x8TbGsO8q5NCRQ6sjW1adkQ0WjgVWl7Ojl)TIDTtdyQwZrEe76dXjLgwwJBuDOgMMNXstcokJ39lKY9nPgnBxwIT8eK9zqtm6a5qPMWtgSigTqiGTYFdGSUkgT9gPFPLF9u(Cu(7JMbj5LBbkYsu69cVohZzPEJzLlerXBEMtBn5jNT1TeESSeocoBlGhjS8ciPBzC0OK1Dv01IWcOBJbmgKuYQLXeVcUbtiRalBiaEEa2vjSxOn(o35IbQ(iUVByLPmkg8umKs9H)dminNeluHs2lk3bOSfmDhrLMUYcoNycukAmG7h7lOfdoMMeQRKdf8renaYp)yVycstjVEc1DZ)f5(sYd8SamQKxUH18(E6EZy)2YCB3WTbXv4EO5PZDS6Xf3YmTn5EJZZTk1DSxMbwUIZJX78PmcAnSUIkvHD1k(OvBOkmCRktxsrTsdY3i0QRjmpPlm(HeltEGzTBwe2G6P9zZ7DT(5eXpz(84TlVXO9MrDQcowXN2XSp9dUVF4(YJvQNBQoAPE)lkH)HAir(W1fgVYOQ8esF0OmcK3mSD3WYndEZEesO8xO1fJyUjHkACsEle4p(jrJukmHEFN3SacIB2qaVzDOc7LL(3BwXl9Mj(IBM4zCqOPdPVpMnJQfNxhBfmy5M3Uux(tTW8z7GB02bLiwQq9kWUejkfS3wf7ZuWTTKIowogJ6ZqXK7EX8ZWZ0tdp1cO6kVT1sMNbQ3zXkilhvyyrAMk)wRQ)2zB70qhaQvOzuX30w7tvlcm6VymwmBzrNP33BXei6wGk3xtH4RPs81uk(AQf)zOZb136GVOiwR9bz8(hSW7AFJqXc0L2kCw7RqgGNCvB9qB4geZFKS56ez9WSnyV)LOO3NuDITwolbbR)L724sC2Vq8nRtVAkrRjOxfBiH7wBdItwXQFZP(Qgxtb0RVIYnws5Mj7(YO9LqZzuBbv2MdWTTJgNuln(FLjPfn24l2MUJqx4n12miSF(S3GxQXhcO02KhYtFvbeLwD5CUnMCDt9ePVnf5LRRiN72IiOA9uISr1s9nrlk923XKw1YK23ZKo30KwvJNcEPT5hP0wfzMXswdcHBljOJ7KMKepVbHK0dRx2YuFNw(VTvlh3ZfYsRGp6b)lTVoJTFrk9tf5Pbg9aLT5lCSdonwgSA7DZP28gBDVrSz0ddR6U0knO6fzRToDTVo9TXon3zNZvRDe0JTyQuRzDJ2x798PUM(iqG(3HlrqjH2jDRu34wD)NLzzRi3DQk3DRm3nvN7gJOOPcDlOB9ynkP7J3l(gHFMi8E0YOg7zKWgARUUAnrYy0QVint6nd)ZoPXeXkLXIaJ9nQ0MPul(o07h1aXy5AeKYwHjEZ(z4Aum6W8b)yX)pued79V]]
)
