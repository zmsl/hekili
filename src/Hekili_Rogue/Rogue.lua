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
            fillWindow = "energy", -- the forecast window reaches a full energy bar's regen (upstream Hekili's)
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
    gcd = "totem", -- the Rogue's own GCD (a wait, gcd.max of an off-GCD ability): the 1 s of its strikes
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

-- Relentless Strikes (14179, rank curve {4, 8, 12, 16, 20} % a combo point to restore 14181's 25 energy; wowsims
-- rogue.go ApplyFinisher: chance x points, one proc): the expected energy, since energy is secret and the belief cannot
-- see which finisher proc'd. `talent` and `gain` are the caller's: the sim's state or the belief's.
local RELENTLESS_ENERGY = 25
local function relentless(talent, points, gain)
    local energy = RELENTLESS_ENERGY * math.min(1, 0.04 * talent.relentless_strikes.rank * points)
    if energy > 0 then
        gain(energy, "energy")
    end
end

-- Improved Expose Armor (14168): the energy curve {-5, -10} by rank (the old rank x 10 priced rank 2 at 5, not 15).
local IMPROVED_EXPOSE_ARMOR = { [0] = 0, 5, 10 }
-- Efficient Strikes (13732, Sinister Strike and Hemorrhage): the rank curve {-3, -5}, by rank.
local EFFICIENT_STRIKES = { [0] = 0, 3, 5 }
-- Composure (1329265, the rank curve {-5, -10}): joins Poised's own discount, on the abilities the buff names (wowsims
-- poised.go). The -10 is the cost modifier below; this is the talent's part, a cost step the abilities' `spend` takes
-- while the aura is up (`buff` and `talent` are the caller's: the sim's state or the belief's). `mult`: a percent cost
-- talent's factor (Dirty Tricks). wowsims applies the flat modifiers before the percent ones (core/spell.go:1056-1058),
-- while the core's Poised -10 lands after `spend`, so with Poised up `spend` returns (cost - Composure - 10) x mult + 10.
local COMPOSURE = { [0] = 0, 5, 10 }
local function poised(buff, talent, cost, mult)
    mult = mult or 1
    if buff.poised.up then
        return max(0, (cost - COMPOSURE[talent.composure.rank] - 10) * mult + 10)
    end
    return max(0, cost * mult)
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
-- no refund for it, so its registration below leaves `refundOnAvoid` off.
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
        copy = { 14144 }, -- the Cooldown Manager's entry links the talent's id
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
        copy = { 11329, 1856, 1857 }, -- the Cooldown Manager's Vanish entries link the spell ids 1856 and 1857
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
    -- Sprint (2983, ranks 8696 and 11305; the buff is the spell) and Evasion (5277): 15 s, off the GCD.
    sprint = {
        id = 2983,
        copy = { 8696, 11305 },
        duration = 15,
        max_stack = 1,
    },
    evasion = {
        id = 5277,
        duration = 15,
        max_stack = 1,
    },
    -- Auras the Cooldown Manager's buff entries link (cdm fixture, the owner's export): the abilities' own ids and
    -- Forever's debuff ids, every rank. Effects on the target or no stated effect: durations are the DB2's, nothing reads them.
    distract = { id = 1725, duration = 10, max_stack = 1 },
    feint = { id = 1966, copy = { 6768, 8637, 11303, 25302 }, duration = 1, max_stack = 1 },
    cheap_shot = { id = 1833, duration = 4, max_stack = 1 },
    blind = { id = 1324477, copy = { 2094 }, duration = 10, max_stack = 1 },
    gouge = { id = 1324481, copy = { 1776, 1777, 8629, 11285, 11286 }, duration = 4, max_stack = 1 },
    kidney_shot = { id = 1324474, copy = { 1324475, 408, 8643 }, duration = 6, max_stack = 1 },
    sap = { id = 1324482, copy = { 1324483, 1324484 }, duration = 45, max_stack = 1 },
    silenced_kick = { id = 1324485, duration = 3, max_stack = 1 },
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
    -- ... and Feint, Gouge, Kidney Shot, Cheap Shot, Sap, Blind and Distract (mask bits 27, 3, 21, 10, 7, 24, 12)
    spells = {
        8676,
        53,
        13877,
        2098,
        8647,
        703,
        14278,
        16511,
        1766,
        399956,
        14251,
        1943,
        1752,
        5171,
        1966,
        1776,
        408,
        1833,
        6770,
        2094,
        1725,
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
            setCooldown("stealth", 10 - 2 * talent.camouflage.rank)
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

-- A finisher needs a combo point (its `usable`; with `ladder = false` its short answers are no energy rungs, C9).
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

-- Preparation's reset set (owner, ledger L854: Forever's Preparation finishes the cooldown of every other Rogue
-- ability, as the Classic tooltip says; wowsims's list is narrower): every Rogue ability this file registers with a
-- cooldown, from the two Rogue tables below (not the poisons, racials or items, registered elsewhere). Load time only.
local PREPARATION_RESETS = {}
local function rogue(abilities)
    for key, a in pairs(abilities) do
        if key ~= "preparation" and a.cooldown ~= 0 then
            PREPARATION_RESETS[#PREPARATION_RESETS + 1] = key
        end
    end
    table.sort(PREPARATION_RESETS)
    return abilities
end

spec:RegisterAbilities(rogue({
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
            relentless(talent, combo_points.current, gain)
        end,

        handler = function()
            removeBuff("cold_blood")
            relentless(talent, combo_points.current, gain)
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
            relentless(talent, combo_points.current, gain)
        end,

        handler = function()
            applyDebuff("target", "expose_armor")
            relentless(talent, combo_points.current, gain)
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
        onAvoid = function() -- the next-Garrote buff is the landing's: a dodge, parry or miss gives none
            removeBuff("ghostly_strike_next")
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

    -- Finishes the cooldowns of every other Rogue ability (PREPARATION_RESETS, above; owner, ledger L854). `resets`
    -- names the set for the harness world.
    preparation = {
        id = 14185,
        cast = 0,
        cooldown = 600,
        gcd = "totem",

        startsCombat = false,
        known = knows(PREPARATION),
        toggle = "cooldowns",
        resets = PREPARATION_RESETS,

        now = function()
            for i = 1, #PREPARATION_RESETS do
                setCooldown(PREPARATION_RESETS[i], 0)
            end
        end,

        handler = function()
            for i = 1, #PREPARATION_RESETS do
                setCooldown(PREPARATION_RESETS[i], 0)
            end
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
            relentless(talent, combo_points.current, gain)
        end,

        handler = function()
            applyDebuff("target", "rupture", 6 + 2 * combo_points.current + 6 * talent.blood_splatter.rank)
            relentless(talent, combo_points.current, gain)
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
            relentless(talent, combo_points.current, gain)
        end,

        handler = function()
            applyBuff("slice_and_dice", sndDuration(combo_points.current, talent.improved_slice_and_dice.rank))
            relentless(talent, combo_points.current, gain)
            spend(combo_points.current, "combo_points")
        end,
    },

    stealth = {
        id = 1784,
        copy = rest(STEALTH),
        cast = 0,
        cooldown = function()
            return 10 - 2 * talent.camouflage.rank -- Camouflage 13975's second effect: -2 / -4 / -6 s on Stealth's mask
        end,
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
        cooldown = function()
            return 300 - 45 * talent.elusiveness.rank -- Elusiveness 13981: -45 / -90 s, on Vanish and Blind
        end,
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
            relentless(talent, combo_points.current, gain)
        end,

        handler = function()
            applyDebuff("target", "death_mark")
            relentless(talent, combo_points.current, gain)
            spend(combo_points.current, "combo_points")
        end,
    },
}))

-- The manual-press abilities (registered so a press costs what it costs and starts its cooldown; no priority
-- recommends them; costs, cooldowns and GCDs from the pin's spells_auto_gen.go). The ones that strike break Stealth and
-- Vanish as the opener does.
local FEINT = { 1966, 6768, 8637, 11303, 25302 }
local GOUGE = { 1776, 1777, 8629, 11285, 11286 }
local KIDNEY_SHOT = { 408, 8643 }
local CHEAP_SHOT = { 1833 }
local SAP = { 6770, 2070, 11297 }
local BLIND = { 2094 }
local EVASION = { 5277 }
local SPRINT = { 2983, 8696, 11305 }
local DISTRACT = { 1725 }
local REDIRECT = { 438040 } -- unverified on Forever: `known` hides it where the spellbook has no such spell

spec:RegisterAbilities(rogue({
    -- 20 energy, 10 s; wowsims refunds a dodged or parried one (feint.go).
    feint = {
        id = 1966,
        copy = rest(FEINT),
        cast = 0,
        cooldown = 10,
        gcd = "totem",

        spend = function()
            return poised(buff, talent, 20)
        end,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true,
        known = knows(FEINT),

        now = function()
            removeBuff("stealth")
            removeBuff("vanish")
        end,
    },

    -- 45 energy, 10 s, +1 combo point (the pin's Energize effect).
    gouge = {
        id = 1776,
        copy = rest(GOUGE),
        cast = 0,
        cooldown = 10,
        gcd = "totem",

        spend = function()
            return poised(buff, talent, 45)
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(GOUGE),

        now = function()
            removeBuff("stealth")
            removeBuff("vanish")
        end,

        handler = function()
            gain(1, "combo_points")
        end,
    },

    -- A finisher: 25 energy and every combo point, 20 s; in Relentless Strikes's mask.
    kidney_shot = {
        id = 408,
        copy = rest(KIDNEY_SHOT),
        cast = 0,
        cooldown = 20,
        gcd = "totem",

        spend = function()
            return poised(buff, talent, 25)
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(KIDNEY_SHOT),
        ladder = false,
        usable = finisherUsable,

        now = function()
            removeBuff("stealth")
            removeBuff("vanish")
            relentless(talent, combo_points.current, gain)
        end,

        handler = function()
            relentless(talent, combo_points.current, gain)
            spend(combo_points.current, "combo_points")
        end,
    },

    -- The Stealth opener: 60 energy (Dirty Deeds -10 a rank), +2 combo points.
    cheap_shot = {
        id = 1833,
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return poised(buff, talent, max(0, 60 - 10 * talent.dirty_deeds.rank))
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(CHEAP_SHOT),

        usable = function()
            return buff.stealth.up or buff.vanish.up, "requires stealth"
        end,

        now = function()
            removeBuff("stealth")
            removeBuff("vanish")
        end,

        handler = function()
            gain(2, "combo_points")
        end,
    },

    -- 65 energy (Dirty Tricks -25% a rank), from Stealth.
    sap = {
        id = 6770,
        copy = rest(SAP),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return poised(buff, talent, 65, 1 - 0.25 * talent.dirty_tricks.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(SAP),

        usable = function()
            return buff.stealth.up or buff.vanish.up, "requires stealth"
        end,

        now = function()
            removeBuff("stealth")
            removeBuff("vanish")
        end,
    },

    -- 30 energy (Dirty Tricks -25% a rank), 300 s (Elusiveness -45 s a rank); a Blinding Powder is the client's to check.
    blind = {
        id = 2094,
        cast = 0,
        cooldown = function()
            return 300 - 45 * talent.elusiveness.rank
        end,
        gcd = "totem",

        spend = function()
            return poised(buff, talent, 30, 1 - 0.25 * talent.dirty_tricks.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        known = knows(BLIND),

        now = function()
            removeBuff("stealth")
            removeBuff("vanish")
        end,
    },

    -- 15 s, 300 s (Endurance -30% a rank), off the GCD; no energy.
    evasion = {
        id = 5277,
        cast = 0,
        cooldown = function()
            return 300 * (1 - 0.3 * talent.endurance.rank)
        end,
        gcd = "off",

        startsCombat = false,
        known = knows(EVASION),

        now = function()
            applyBuff("evasion")
        end,

        handler = function()
            applyBuff("evasion")
        end,
    },

    sprint = {
        id = 2983,
        copy = rest(SPRINT),
        cast = 0,
        cooldown = function()
            return 300 * (1 - 0.3 * talent.endurance.rank)
        end,
        gcd = "off",

        startsCombat = false,
        known = knows(SPRINT),

        now = function()
            applyBuff("sprint")
        end,

        handler = function()
            applyBuff("sprint")
        end,
    },

    -- 30 energy, 30 s, a 1.5 s GCD; keeps Stealth.
    distract = {
        id = 1725,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        spend = function()
            return poised(buff, talent, 30)
        end,
        spendType = "energy",

        startsCombat = false,
        known = knows(DISTRACT),
    },

    -- 10 s, off the GCD, no energy; the points move to a new target, so the player's own count is unchanged.
    redirect = {
        id = 438040,
        cast = 0,
        cooldown = 10,
        gcd = "off",

        startsCombat = false,
        known = knows(REDIRECT),
    },
}))

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
    20261118000,
    [[Hekili:TV12UnUnt4NLCJRn6cFijE30GOa02)Eyl6)2I6T3kzAjkBvllAqsLudy4N9ssDWKmK6KD2gG69IDLfjN5B(MHudNbR7e3p7olaqHUF66Xx)(jtMC34XJDNr3Tf6oBlWFnyj7HeWg2F)9Onla0dZ7)m6zs0gYqF0Mb8zTlgbc4sArAum9JjUlmkuYwOV7S)43(P)8hU3xil3zRIccGzlas8TOJ7pmNUcEyE(7gfIWWNG4dZdGHG0y20)2F)xpmN96dZlfqA0iUcjJWOLPWrbBjJaBJjJYxZq2pg(xeuYG3XKogKqIzioG9mIRTiYH5GGauYxXEynChz4H5)pafCVbu0)))XpZeYkkDl5(rJwgrxLUGd8rAtDatMmObwmoC8y4TH(3DZqg)HrHrXm(f4tJqjKHBXWm6Xzrmia6fgNIX7o8lVy8V2ze75nWGikGp07sjqpuyO3s)aNjLlWbhTfrOq1HFxiYpLW(3OqhyceVC3Wy0JozRzy(sywbHwkiM(wcWyetuslUphmiVTOOekZFXWkmH(W0ExfaxKggomFjdt3oqwspbsIiR0WexC9VkhdflCDc65K9gexplt9LMtX4CZzqplaMgTb(OZefuY43TaCg7YbxHcZqFb08rO4a2tfVgdbb7uKZIyekWlmfVZGfxiuz3DUO7BDOEc2q59mkP5kTkTwApkJLzv9kxwHWZwKMMpUUmTzzv9ye8tdNi9(b7LqM2Kp)GEGuqulLPI9cXeiEDuYYkCVK4iFOhijWlG9qUgeErTr02PqwbswNXI9PGywW6Wfie1BDsuiCi7OR1p6mDVTrU16i3yDKRnmcmbSiggyz3JZn9k319GZDJ5EX3cGvfuk0kiGHCqCuc0dNYojItWstF64EDYZ1RyrW40eiXloA5kAE8RTa7oSRvd96XR6dNVnW62qR75K3cuosM0okodMAF70WrrQmwPq7cRxRN9CFa0f(xL)5l8mroVbSg5OjzXA609(vA02XDf4IfcEQCzhjSoYxnE7NbFB(gq5rK2cAmy4cLpiBhxZyIxz7TDWUnBT6k(2aIsiSu5NCRQ6sXW1adkQWXjgppk7Oll7TcRUxnyQs3rwg76dXiLAwwTgQoudsZUXsDcoKZ7E5s5H6uJMVJFhzAm0JcnXO9LtLAc7YG55Ofab0vEBa41L5OT3i9lT8RNYMJYVp6gKKxMhi)wIsVxe11Z8TuVXSYfIi)nViOTIRCZnDlPhllHJGZ2cyzclVaC6wkdnk36Um7ArAbKTXakfIly1ICIxb3GW4vGL1Kaplb7YlSNRnML37Q(QXioVFqPRmmg8CmKq8G)n0pnJeZvHYTxuodqXemDgrPMgBbNtmbkfn6ZIJ9e0IHattc1rkGc(ueXhY2)yVycstjREcvDY)vzXsYd8IemkLxMJ1SDpDVzSFBXDB3W8bXL4EG5PZ9ZVK9Qy7jZ4YhJDbxog5ul7UWKYiTIDqfHnzBH0ILkpt(gTDtlxXOW4DEekoAnSQ6jvYYQf7rRSqLM1TQ6PGDAKgKpmOrNqyEsxz8BiwMCFZA3SiSb1t7lMp4y9ljI)iZNhpy5cJ2zgTxzEXkX09mht)OZDd2xSBuDFt5MrPtR(WuvpgjkH9fBiwER2vgp7OSofsF9OivKlU527MzUb3zpbXe2l06jsmZLqenHjRTeSh)KOPm5ou3VZDMpoI52Ia8xwvD6DNj(4kxaZK(WN43zt3Dw(8DPmCyvnTOI(hLC(lLabth3OPdBWkRU5kyWYX9TPpaNAJa4wWTAwqbILAmGcSlqIsdcS1HaUcM2qk6y5FmQpdfVU9npGJN3FA4Psavv50TwIEoO(GfVGSCuHHfPzQCFnQEFNnZPMoouPq5uXDn1)u2scJXlgV0UTBTZ173yXfi6oHk3xrH)ROY)vu6)kQ9)zOtfv3QIVOiwRDfCEFYyleV23IuCbTPpgN1gziqS(hW66riM)yC9fMY6UzBWE)Rrv2pPctBT(zccw)t3njK4SFI4fVtN6csJjO3egKiCRPzXjRy1p6uDzQROI9vxc7ARHD9KDxz0UsOzmQTSkBYg4M2cLtQhk)NYL0GoP8fZOBj0frtn9ke23F2zWl1PfbuA6ThYUMScik86Y3T34L4RRjmDTlmVETH5C3hgbvRFNiBuTuJA0stV5TOPr9OP5nPP1DPPr1skNxA6fKu6JJmZy5AdcHB7wqhTK6Ke7IdIQVONwVSNP6w78VBVDKQLuMSuR4Z12RE15SFps3)urEAGrprzBXchBzuT1bRYMfDQDlYw7IegJEAyLNLwQb1OiB9rQTns6lwNK6qRKeeJTSPuRrETEw79yQQMmjqG(xGlqqbv2kDRuz6gDYNLzzRm6TQo6TRq61vj9AZLOUsPlOB9SmkO7JNiEHWpteEhArvD9OsVjvcxQTk8Q11kJPT(Q09QlXbVyJhvK0eNfbgBuvHptPQ8g60uZYiJMPrqkDfc7o7NHRJIJomV)pM)FMgXWU)Zp]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261118000,
    [[Hekili:TVv2UnUnx4NLCJRnAGxsINjnikatr7F7u0o9h1tVvY0su2SwwYGKkPgWWp7LKAXKmKAZothG6CrGIi5z57CouNfe3jUF2DwaGcD)0nJV5DtMm5(XJh7oJUBl0D2wG)AWs2dXGnSF)bcbqiOyafLeFyE)xsEHG2qg6NSzaFZ7IsabCcUiffr)yS7cJ0MSf67o7p(9F6p)XhaYK0D2kuqam7CqIF1C8HdZPRGhMN)UrHjy4Zq8H5bWqqAe9W8p8))1dZzVM9KgDsrJ4sbzeozzkCuWwYiW2iYO8JoK9hd)lss8GRzmbdIjrm1iG9CcNPiYH5GGGK4VH9WA4oYWdZ)baf8GbHP)V9XpZiYkkDl5HrJwIORsxWL)rABDaJMmzgSyC44XW7c9V)2HmqfNeIIyypWNl6KHBXq2HxaOolIabqVWOumE3HF5vR)ToJypVbgGOcT(6uc0ljm0BPFGZKYd4SeGXju41Hj(PeNjxJcD6ZPqI32eumLH1mgaJPpoT3vbWfPHHdZpYW0TdkPdJDpdIrKvQ8rqU(xLTPYdUoo5L49gixplBfgdXl3nmk5jhT19ti0b9SiWu0g4totuKsgOSfGZGeUWvWWmPVq08tsIcypv8AmeeStHolIssc8ctX7mOXfev2gLt6(wxQNanuEpdsAotRIRL6JYAzAvVYJvq8SdPX5JNlJBwovpga)8WjsVFWEjjtBZNFHEGKtulPPI(cXeiEnkEzfMxseYh6bId8cypKZbHvuBfTifYkq86muSpfeXCwhUijH6TogfchYUVz9tot3BBL7SUYTwx5gdRaJblIGbwIECUTxzu3Jo3pMBf)AqyvfkfyfeWKCqekg6Htz3eXbyPTpDCVoz56vCiyuAmK4fHwUIM7)AZXUdrTAsVU)Q(Y5HbwddTgZjhcuUsg1osodQAF7WWrsQSwjr7cQxRL9CFb0f8xf)5h8mboFfOnYEtYK10T79RuPTl3vixmxWtfl7iG1r8QXHFgST5bGYRifcA0z4cKpilIRziXBS(2oXUnHwDv(2aqXewQ8tUtLDPy4AGbgvy4eRN7LD0KL9wHw3RgzQsZrwg76lXaLAowTkQUOgKMvXsDeoKJ7E5u5X6yJMTJxylnc6rHMq0(YPsnHvmyEoAbqaDL3gaEDzoA7nc)sh)MPS9O83hnds0lZcKxLO07fED9mxL6TMzUGe5V5voTvuNmx1TKESmfokC2oalty5dGt3szsJsv3LzxlslGSncqPqCbQwKt8k4MemEfyznjWZsWUSG9CUX08Ex1x1hX5DdknLHrGxIGeIh8VH(PzGyoluQEr5oafvW0DeLCASf5CIjHsHJ(m)ypbSyWX0erDKCOGpJi(qw8J9MjiTLS(ju1n)xL5ljVWRsWOKEzgwZ6909ML97kQTDdZgevk3dmVDUD(1OxfHNmLlFnwbUCzKdTSAHjLEAfrqfUnzHqA(sL3jFRw00YvmimANhHIrRHv1pPsuwTzpATfQuTUtLpfOtJ4G8Lbn6gcZB6kJFdXYM7BM7MjHnr90(I5Jow)sI4hz884flxq0oJO9kZlwXNUNzF6NCUFW(IOr14MYGrPBRE)uvlgbfZ(InelhQDLX7ok7tH0xpksf5IzU9MzMzWD2ZqmH9cTPBeXmjeXuvYMLa7XpjMYsUb197DN5JrmZgc4oRfTAVygaUZYFP7mXNE5KNYecnEi9Hs(okpCwdTvKbl3d3Mg0FQDONRb3QPbfsSuh7ve7cjrPZ92ADpNb31qi6yFzmYpdDvU9D1Nlptpn5PsbQQ(CBT35CH6DwScY0rvmSqnt9HRrnI7SPo1mkGkjkhkEFtTpLZkWO)IXQPTvonNV3BXeigBGk2xrh5ROL8v0t(kAk)zyecvpdHVOsS2Ce44(3zb31(gHIfOnZx4SoGbUapzCt9qR5geZFKS(ggzny2MyV)TO73NudJT2xlbaR)L7M4sC2Vq8I1PttNOXa0xfkKWDRPjXjZy1V5uD7JROt6v3A5A7TC9GDxr0UcOziQTKkBsaCthTXjnBJ)tzsAWeo(IP0Tu0fEtnTcc7XNDw4LMaIquAAXdzLVQiefwD5AUnwCDDdhPRth5TB8iN75JiGA9sISb1sdqrll9Mp6Kgn7KMp8Kwp9Kg1JNCCPP1hPmFfzKXsvdcIBRiOJAsDuIv3GGs6P1lBzQEKl)7oZLJ6CoT0A4JEY)s61zComsLFQqpnHrprzB(chhLtTTbRYH4CQtXX2yCekJEAyL3LwYbvViBZ3PTd45l2eE6WiEeaJTSPu7DDTww7Z(PQH)iKa9VaxibfqzR4TshJB0nFw2LT2B3Q(B3UgCxxhURnxI6AXTaU1ZYOaUpEJ4fa)mb4Dy0r1n7i9HhjmP2AWR20KmM26BYuLU4h8QapQiPjokcmoaPcBMst5BXqGuZiJMXrqkDvc2D2pdxJIqhM3))L)FMIyz3)5p]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261118000,
    [[Hekili:TV1wVTTnu4Fl5fnBSaFjjUnlikaBy36Ww3WC3RsMwIYsZYsgKujZag(3(iPUysgsDZoDfyUpu4ksEU8DohYZfuNPoFYzUpGaD(4ntU5DtNo9(jtM4mNSBl0z(wG3AWk6psaBO)98SLKyiz3HfdEj9fC0g8iV0ndz7BxCkWNrRLzrXKpK4SulzXBHEoZ)ZF)N(RF4bCb1CMhg57dZpce7zKppCybjeEyrX3ghKIGpdrhw4ddazXKdl(2)4xpSG(5dleirw0ygBXJrPRYGJ93Ihd2gJhxCQr0)XO)gNMm8Ak9rGeCmvU9P)oLXVi8HfaF)0KVI(J1WD4rhw89ac4bnYXGF7dFIsKqczl(HXJxfrcZwYe9XkBDiLMuXfSCsWKjW7c8U)2ruueLgeftXzGhjknbpAlcsp8saXEzmWh6geNHq7o8lVA9V2Em93BG(reaBPRZWq30Ga3vE(2tRoG9kacLsGxhK6LHTNEDuG9agfsD3MgLqOWmLbWeYJZSUYhUmliyuXrgLTDyfDOS7zqseouMpCYn4Q8nvDW1jPVKSxd5SmSvyceTA3O40NSvw3lftgAzqGjrBGpzpvskPGYwakhsycxjdZL(srZlnn2N(RYpJGa)Ds0zzCAQVBqgANgnUKOI2OcspW4swC0q67uiP9mToUwPpsRLRvwvhRK45hsHZhpxo3mCklka)8OPcFF4EbjtzZNFHEOGtuhPPK(cryiADuYQAmV44ipOliX31N(JcoWTIkROePGdbjRZrXbeqm1zD0Y0uI76KOa4i69nRFYE2EtRCNXvU14k3Ozfycyzm03q0J9TwvrDpAF)eMv8lbHvwOKGvGpvYbXrjqxug9MigalS9ztS6LLZQ8qW4Sei2noAviPW)1KJDpIAvKEv)v1LlcdmggAmMtmeOALCQDKCAu1bMHHJKuATkI2huVrl75(cOl4Vm(Zo4zcC(cqBe9MejRUB3huRsBwURrUOUGNkw2taRN4vRd)0yBlcafxrieuRZWfiFyEex7qI3y9TBIDxcT6R8TbeLGPPYp9oz2LHGRbAyuPHJVEHx2rtw(x5ATvdYuTMJ8m2vxIcknCSgvuvr1plVILMiCad3DlOYJnXgfBhRWwAbYUeOoeDGyQutPfdwKJMpeqcD3aqRRYrBVw4x443mJUhP)9rZGa9YTafvjk8DUxNL(QuVvpZ5KO4lVYPTM6KzQUH0JfPWrHZ0bOzclEau2wcvAKQ6Uk7AEAb4TXacbIkr1YCIdHBsrOqWQgsGNMGDvb7fCJQ5wxnq2hX(DdRmLbXGxIHySl8FGEz5GyblKQEr6oajvq3DevCAIb5CQoHsIJEu)yxoSOXXuhrTfCOGphH9G04hZntqyl59tOUB(Vk3xsCHxLGrf9YnS617z71l73vwB7gQniUsUhQF7m78RrVAcpPkxXA0cCzYidAP1cJR80kJGkDBYdHu8LQUt(wLOPvHuimENlMGIwdRRFsvOSCZEuAluLADNmFkrNwXbXldA1ne630vAFdXWMhON76jHjr90EX8rBJVKW)JiEE8ILliAVruRQ8IL8PT07t)K99d3xgnkh3ufmkCB17NjBXWrj0xSHiXqTR0E3rvFkeE9OmvKlM5UBMPMbN5pdry6hugNrm1KG5tqjFwc0F(r(evkmOoFNZCpue1SfbCM3HwTxodaN5fF0zo)Pxg5juHqHhcpuY2r1HZBOTKmy4E4U0G(tTd9mn4wfnOuIf6yVKyxkjsDU3uR7zm4Uwcrh7lJw(PPRYDVR(m5z2Pjp1kq11NBJ9oNjuVZGvqKoYIHbQPRpCTQrCNn1PHrbulrzqX7BR9PAwbA9x0wnTPYPz89EdMa(ydKX(A6iFnTKVMEYxtt5pdJqO(zi8zvIvMJad3)gd4UYBeswGUmFHZ6agyc80jT1dTHBq0)izZnmYyWSjXE)Br3VpPggBSVwCaw9L724sC2Vq8I1PxtNO1a0xeke3DRTjXjYy53CQV9X10j96BTCJ9wUzWUViAFb0Ce1usLTjaUTJ24KMTX)RmjTychF2u6ok6CVP2wbH54ZEl8ctaHlkTT4H8YxLeIsRUyn3AlUUPHJ03PJ82nEKZ98r4qTAjrMGAHbOOKLE7hDsRMDs7hEsNNEsR6XtbU026JKMVIiYyOQboXnve0rnPjkrRBGtj106fTm1pYL)BN5YrDUGwkn8rn5Fb96mohgHYpLONIWOMOSjFHJJYPX2Gv7qCo1P4yAmoCLrnnSQ7sR4GSxKP5701b88zBcp9yepCGXu2uY9UUrlR5z)u3WF4sG6lWLsqju2jEl1X4wDZNHDzQ92DQ)2DRb3n1H7gZLOPwCZHB1SmkH7J3iEbWptaEpgDutZosD4rCtQPg8QmnjTPT(MmvPl(bVkWJWtAIHIaTdqQ0Mj1u(omei5mYi5CeKrctroZ)z46O4Odlg8Jf)ptHVSZ)c]]
)
