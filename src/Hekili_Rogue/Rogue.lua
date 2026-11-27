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
-- rogue.go:107-114 ApplyFinisher: chance x points, one proc, only on a landed finisher): the energy only when the chance
-- is 100% (rank 5 at 5 points). A lower chance is a random resource proc, never an expected gain (owner L1397,
-- 2026-11-25): the reads find a proc that came, and the belief's `mayGain` keeps its regen pins from learning one as
-- regen (L1832, cp-fact-4). The belief takes the gain back when the finisher is avoided (its `now`'s gain,
-- Families/Now.lua undo). `talent`, `gain` and `mayGain` are the caller's: the sim's state or the belief's (a
-- `handler` passes no `mayGain`: the sim books nothing).
local RELENTLESS_ENERGY = 25
local function relentless(talent, points, gain, mayGain)
    local chance = talent.relentless_strikes.rank * points -- 4% x rank x points, in integers of 4%
    if chance >= 25 then
        gain(RELENTLESS_ENERGY, "energy")
    elseif chance > 0 and mayGain then
        mayGain(RELENTLESS_ENERGY, "energy")
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

-- Combo points: a count the game binds to the target (only the current target's is usable), not a pool.
spec:RegisterResource(Enum.PowerType.ComboPoints, nil, nil, { onTarget = true, points = true })
-- Adrenaline Rush (13750 aura 110 misc 3 base 100): +100% energy regen while it is up, a rate multiplier (C3b).
-- regen: energy's base rate a second, the belief's from the build until a plain rate read (energy is secret even out
-- of combat): wowsims/forever's 1 energy every 0.1 s (sim/core/energy.go:48-49).
-- refundOnAvoid: the share of the energy an ability flagged `refundOnAvoid = true` gives back when dodged, parried or
-- missed (wowsims/forever's MissRefund, spelldata/attributes.go: 0.8 where the DB2 flags Discount Power On Miss and the
-- spell issues the refund). Not Slice and Dice, Vanish or the poisons; Gouge is flagged in the DB2 but wowsims issues
-- no refund for it, so its registration below leaves `refundOnAvoid` off.
spec:RegisterResource(Enum.PowerType.Energy, {
    adrenaline_rush = { aura = "adrenaline_rush", mult = 2 },
}, nil, { regen = 10, rest = "max", refundOnAvoid = 0.8 }) -- rest: energy rests full out of combat

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
            gain(1, "combo_points")
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
            gain(1, "combo_points")
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
        cooldownAfter = "cold_blood", -- cooldown on event (attribute 0x02000000): it starts when the aura ends
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
            relentless(talent, combo_points.current, gain, mayGain)
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
            relentless(talent, combo_points.current, gain, mayGain)
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
            gain(1, "combo_points")
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
            gain(1, "combo_points")
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
            gain(1, "combo_points")
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
            gain(2, "combo_points")
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
            relentless(talent, combo_points.current, gain, mayGain)
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
            gain(1, "combo_points")
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
            relentless(talent, combo_points.current, gain, mayGain)
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
        cooldownAfter = "stealth", -- cooldown on event (attribute 0x02000000): it starts when the aura ends
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
            relentless(talent, combo_points.current, gain, mayGain)
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

        -- (L1832 review M7) its point is the handler's only: no `now` gain, so no point fact (the rows decide its
        -- avoid; it refunds nothing); wowsims has no cast for it, so no parity gap
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
            relentless(talent, combo_points.current, gain, mayGain)
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

        -- (L1832 review M7) as Gouge: its points are the handler's only, no point fact; wowsims has no cast for it
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
        toggle = "defensives",

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

-- (L1808, owner "Setting per line") the health threshold of the packs' Evasion line (the recipes' `extra`, the
-- def-int-beyond-wowsims review's default, 50%): a 1-100 slider on every spec
spec:RegisterSetting("evasion_health", 50, spec:HealthOption("evasion"))

-- The hand-built lists this file shipped before the wowsims.com packs: a saved choice of one falls back to the spec's
-- default.
spec:RetirePacks({ "Combat", "Assassination", "Subtlety" })

-- The three priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those
-- and run it, never these blocks (tests/Forever/rogue_spec.lua checks they match). Pick one with
-- /hekili priority <name>.
spec:RegisterPack(
    "Combat (wowsims.com)",
    20261126000,
    [[Hekili:T31wVnUTs4Fl5fxl0fY25YUzdIcqpT9C6w0UTOE7RsMwI2whllzisLTbWW)2l1DsAsDZkUkO8LfoIKZmKZ3WH3(WAoZ8lMZDayO5NVE61VF2SRF)0PtnNJFzp0C(EG9wWAYp8b7i)73hSBjaFCX4Vg8vK7oKUDWoT4A9IxaWjwslJC9WFY3CPqHI2dTnN)h)2)7p)XhStKL58nUooW0gar2s0XdhxG3apUi7BtwfecFggECHdCfiYJu9V73)LJliF(4Icbe5ojwHOjHbRJGtC2JMa27HMK1gDYFO))rb(AVJi9qGpYJyXoKFheRnx0XfahNa)VH8JTWxq6hx8dam4bbwX4F9tFHiKny8E0dtMS2fVjAzSHpHRQAezsmnWYPRMofE7k77VrNm(fgSY1Jm(cSXUb(i99HW0HhJLEahO1kVOWWxo(ZNu(3AmH87DqhxmiUO3fHGwbRwzT22XywrdmGpdqNu87CxzSbc8WB036h8v)rz)XEB8Jgiig76VgPN1uR0clejrZPFbHd8HDrWunxIWjvZAFWP9RMl)sjiqfHU7dqyEBFvGDekvhqFy46x09cEYiTv6znH4AryArTgeggqefvJhh7HciA31htaXehi0h)4DJUYbUmA1k9SMOhTxJwspd8DrBoT)oE8vz2qEdt66heiUrsQ6PDN8YJ7oAJKyWy3DWNmMXyLeq3EqykKl24YvyQ1NBA2bbEoKFL)5qiW5fg5S0liWXAvu4lc6X5cLogit0JLw0OKrdMVtgsAUsRsRf9hMYs7vJkAwUWtBeNMlBxQ2K0QrKb4N1Nr9DTduwgxL7FJwJce1szY0FHHiy4wsuyfUxKNRn0c47y5q(rMgs8ICLWfPCYGzxe4izdQ0AcTb4Vn1Fngd8iHf6ldcWwB9Dxb1jzo2(KXDhKvYTsl5gPLCTGsG(GLEqhjXPg3mQi((rJ7NgJxgcglRrfdRYX8WOq4wqoe(kbFTeNL91muBrLboK(E8S8qRWOI5DgxvPPZpWxebjCqSDvPSkSp(Ij5KbU(ON47aorPtAQPvJvUYD9gSvMyESo9OPjX8z)MJlk1RqNk4JtzIQ40qcQNYhE30rNxCg0lYhIS8I7FzgPSqqfyzOdwAwMuXd8vyMP(njOIrsZdsNwQOKuPvkob4VXYXMuGk6YkeAxcfuW6HoSw0CG99k1ubfSbfXnSNgCga9gvi(apeN2xlAVjvA2hKdMQaSqS9ZfG3ruChbXku8qhfxvIkbZcMLQIUeQKvcN2ufhOPXgju5iXRC)TDMTk8DGh(wxsOUcAshpmMn7wfgyWJbsQQaVViXl0)8k7E6BprF7iui8bocp(QuXEqlmuemFm9Plo7UrxLDwYoqaEJ1oq42IZswSbr18RVJuhM)U0XsjVuFA29Mr99SKMcpE9BeR8erK9fvo33cOXkUU8y8OS7wr5wh2U1YWyzEXNmUv5fh4EXWO9ysTzEgffxIzYXxI27bWyyyEsH8RECdCxqy4gW6AUN0NiXY5pzImTrg)hfFvPHRHy94h7GfoGSlk4JgVxRiD0kpWx9GiKf8VG2rP9RC9OqvdBuf7EJzaxI27CUfAmvccAgbUW2ziiffmyOddSjAYkzwebldvKN2GA5JWNDr2qsxu(JPIQkPVNQQoMQRsx5iDbQ7n4naiQ0jNMCs8me3DqmG62CnUJKcXRamPjU6X5QeNwsRITjrC)zLHGHXgAmOh4arfPmZhkYZ)LowWLuS4uKUrTRMHpSC9gYmoEVyHWHUBHv98tl8cSVnuUxrArITBvo)bVZpFYKg52zCwcnaUZ0qCLUsSFwIhPBqfwt98on8hnK7x1uZWn8b5LBWtbZ7mmFuXTdZm7)iXZ()KX9AhYxmbBgMI1sq5W(WDQWObFyeY13fHHH0RuiF4MDrPfplxQJwjFyrf71(ypvSXWm2WC(ZWWygUXXvrpsCckHCKP0fK8ZpNqwYSP(m)pMZPohH4cZ4VhPkPCMZCUDOljyZfyoVE(QXs0otmXEAO6Oysx7u5PuWlwT30c1wsWU2R5tiNxSYVLt5LcTA24zop5C9smqzgCw9JvZDsvtl4TxPKZ(iLrq0X7B44yk74ySbj7sRnS97CP7xCp4dC9GClMI(FmMDULWqdqz8amwb33WHOY3USq9jGIAftk0ykcgBpF88SNknOIrH2qeVyJA2ujUbAbXAhseNOhREJET69w)PgIfwPqtglA6uWLupuiIr4lPt2tPlrX8tgxRtOtQskzOsSb(zMZTHeckYIaQG7Fvq(Vky)xf0)RhiRy1Sv8IAXNfJf746266c3U0RCR3x6w7w7g3I3sIj4xWqEmbNszIoAdHgRns91JrJkW0LgmXVSWUM)xIJPIorQJvcUzK0C0mzm7l(Dv5JOxRJXlkS)ah7ZVDLMmrAVVqtvGtNOgzJhGgeDi1mbd7zc432V0J5IctWU1Nk7thQG3yvtKQAzsv9XbDfS3vSUcSpWb78hbvo4UjP9Akhlplsw(VQOLgq1YlwNULMUkqFyhO30Z2vEwToJRYUo92titfk5cJsUM)S2LIssegd(qKQf6)E1DF9TNQoj3AhLkkyyhf00BzHIBNCx)qZz1PyRLJwNnNxNTMyNI1p3turbzh6q2M(yjyiaknOTxO(PYVFP97YUt0Y4)6CYTMzOkN8L2jl)vbvh)qFZrquf46scUkFByP(A2xW11v8mXeDoa529Rk1rvaK)raiSUAoCstFQFLCqT2NCyLSp9CPFA)W)ufs8sIeJXzYEqMLoF2CJYONAB5N6LLGQfJtVwmuvbCV0axz3YclTIQDsr5eyT)yWQcCCPbh8NmFo4iFwOwbly9LcTnUZ2rsTKX)ijoSocM4m3Z8og6xoivRXRIe63iHBK9s)l39QkwONIf6axyRJmSNhByRD4rfT1ZrB83YrE0ghjzfEjWVkKLvfIQsx92jacNCzkXaCGq2XMhoXWqQwqRv2BQbNQrqeEtqO58FcU11Z94IX)3S)N1mPyZ)o]]
)
spec:RegisterPack(
    "Assassination (wowsims.com)",
    20261126000,
    [[Hekili:T31wVnoUv4Fl5fxl0aFj32zgefGzr72of7UTOE2xLmTeLTQLLmePsAam8V9sQBMKHu3SIhfu(sGSi55CipFhEOi5hI1CRVBTWfGHw)(nZU5H5ZV5HzZMzTa)6EO1I9aNTG1Khcb7i)9RieaH8dby)OWJlh)s0li)DOjor7mOv(1GiGlvGRs8dWFl0ALuzJ2dDSw8V)N)T)4V(faRiTwSX31fM1oiYPAn(LJlXBGhxM)UPErXWNHXhx6c9ajb4Jl)6)6xpUK8AYtcYjXFk1kqtJJwNaN6UhnfSpannVPti)yY)bffACnrjXGquaPB4sEoIQuF0XLax3OW)e5HTWxrtoU8VaWGViXyg)BF77eHSbJ3J(Y0PR9XBswrT)Pcv1GitIndwnZB2m4DEoF62jKb14ip)aYypWHA6Oj7JHKgVcGnxfaCH2EbjXXVE8F8MY)ZMtjpVd66Jt71xNGG2rEE2RDCnNx2at4Za0Bk(AFpZnqqaEZKTHrVeok)h7DWpAIGySF4A0K8MANvyPijAo7niCuiSlcMP5keoPA27JEB)Q5Y)KeKOI1G44im8AViNeuMuhthwJinXpetaGKrDyi(X7hDLlCvIN3K8MmjzVbRKEge6J28wJC84RYQuzdtT3dse3ifvfgcJx)6KGONmfk3jcHngPWGX(7GpzoNZkjiL9G4mCc14kuyM1xyAorrbUKNkEDme4(kNCwfef5A7Le)QKECHqzbU5IESYIgLoAW9EYqsZvAvATS)WvwwVAuzZkeEwJe08P2LPnfTAeza(5jZzEVXbgltOY9VrBWaIAPm56VWyemElj0Pc3lkW3bAdcDTDjpKRHuVOqjcrkOnGWTzJIJXGacyDYQOiS92qFp4eYKWBFY8(dQk5oLLCRYsUrsjWqWQaORIOhZBhvg19O5NMr9IdbJL3OOo7cKimjgUfuaSUsYBp59ZFBowQSYaxsFNoHj0ooPC2GXvvAwuRyreh(b52vLYQ0(elMKEd4hIEsSd4MKnvMHrnwPN)6ny7CX8yD6XWqH5Z)oxFuMxHDc6ppJdRlOHuupJp8(zJ6u40Os)Bqsiezhq7F5gPQzB0GLHoyPz53KpWxHzM53uMdsfEHnzrzjzs7K4KG)gRgBYaQylRuODjuqdRh6WAzZb23RFshuWhuqBypn4ma6n6q8bEioRVw2xmuPzFqnyQcWcX2pxaEhrXDeeRrXdDuCvjQKmlyEQk2syswjDAtDCGHbFKqLJeVZ932z26W3bE4BDjH6kOjB8WC(870yGbpgiTQs8(YeVu)Z7S7PV9e9TJqJWh4iC6PsIdG2yOmy(y2DxC(9JUkFVKDHa8g7DG4TL7LSCdIP53CpPoC)(KJLrEz(08tZI595jnLU963kx5PIi)n6CUFeqJvCYZu8OQZwr7wh2U1tHXQ8IpzEN2loW9IXj7XKAZD5gkpeZ0TVeTpaGXW4IKcfh94g4UO44nG11CoPprILlUid5AJm(pIEuPXRH4j0RGGnoI8vuWhnFWOmDKxa4Laiczd)VqNKS(vHE0OQHnQI)BJ5axY(25cl0CMce0CcCHVZqqkAyWqhg4q0KD6SiswgQmpTjZYhHp7JCGKUO6R4etvYULtvTnvxLTYr2c0NBWhaq0jNCwYj5ZqC)b5aQ7k04oskKGsWKH8QtZvjpTKrfFMeX9NxgcgtnukOh4crLPmlgkkY)LnwiKuSCxKUv)vndFy56nKzCcE1gHJ93cR6sHw6f4VXMc3TZYeB3PD(dENFXKjnYTZ5SKAac7PH8kDLC)Scps3Gk8M65TB4pAQ2VAONHB4dYp9bEAyENH5JkpDyUz)hjF2)Nm)KXHIftWNHPCTemoSF6EDy0Gpmc5h6JWWy2vkumCZVO0YRLlZwRumSOJ9AFSNo2yygByT4zymLSycCbmGeNGs5GygZ7ip(7PCsmFQpRF2AbZ(iqlmNkCKQKr)mRfoX(KGnFG1I6P(fpN1SWe7PHQJHuATtLVLnBu1EBlu7jUQ1En)gEUrv(Dck)KqBbn3ozJ5V0Ar6U(rnFIoUVHDWmYKXzdk(8P2qoUZLDC0EWdc9GclMHTCCMDHLWXAov0MJQGFQHdrNUuXs1NegDvgT2yg1rTNpDE2tLgu5OqB4Tg1O(ScVaRC4ndfst2LiVr3I8ER7udn8QuO0HI5ZAQdQKOEsbmsVHBQUIBPkwCo5cfLsAp(r)k4dxfeIRcgXvbL46bc8vnd(UOw8zXIVoUwMUUyMl9Qz69LZ0U1ZiSGM0ycXfouetiOuUOJ2qYVFGS8tdMU0GPMUCW6s9QWXurNiZXQmlOkefx2Q(IZtvEXYn6y8Ig7pWX(IFnstMiT3xKNoWPt0fSXdqdIoKEMGH9mbnDpdyXe8FHtL9PdvWLQQjxuTSlQ(4GUc27kwxd2h4GDvBVuts71uEhEwep8)RIwAa9dVyD6wA66a9HDGEt3Mx1z16mUk)iMBpjf1OKlnkPPB(EMW4WhYuTu)37U7RV9u1j5w7O0rbd7OaXt7rvuadFhfo(HMZ0r5wRavhBoxhBnzhLRFHRTHgYoWHS300dLJJuKSG2EHoKA)(L2VR6mrpf)xNtU1SLu7KV0ozXd5Jnvt1CM8dhPj1GRlj4QC6ICFn)LN6gXZdKb3jBFakS73v6uQbi)qai8UAbCI4zNPAXhN4LzT32VkzK55sjZ(HtMAK4LejsXzINmtbU6KZNp3OkkB2woBEzjTz5407fRn1a3lnWv1PSWt1MANuunPo7pwDQbhxAWH4oZxaokMfQvWcEFPuBtyVDuulvCYrHdRJGjbZ9mpJH(Lxo1A86iHEosq80hkIeo91R6yHEkwOd8dTocIEEmeT2HhD0wphTPItlcehv6Ha)UqGuDiQoD1hNaiC6HPqb4aPmgTiCIJIyTGQN8NudotJGe8MOyRf)D4w)a)Jlh)l5)JBmTyR)h]]
)
spec:RegisterPack(
    "Subtlety (wowsims.com)",
    20261126000,
    [[Hekili:T3vwVnUnq4Fl5fxl0aFKRMUikaTOxBr72I6TVkzAjABvllzisLTgWW)2lP1fjdPUSIxTO8Lfo8yMHC(gouK8dR1uRpAnZfGHwF4Mj38W0P38WKjtSMH3VdAnBhWzdyf5hbGTK)Dw8cSpeV)48HFk8tiVTOroHBnOTBVFiWLkRfXE(43hyTqQyr7GowZ(R)4N)7F8DOuPznBTNRlmPlqKJs98UJZXRHhNNw24LHrWxGrhN7cxcI9XhN)D)5VDCoP4JZzerS3yQArJJcxfdh7UdngSZhnoTxJi)XO)bfgyCnr(rGaKpXUDj)oKQpp0X5ax3WGVI8JnW9OrhN)dam4DsSJH)(7)iriRX4DO3nE8kp864futFSqtniYKyUGftwozc8ULopE7iYSyu4spFY8mWb7fgGgTlcs68ca2CHpWfAV0pokA)XF9v1)1MJj)El01ddOvDDmcAhUCP9khxZP5DWe(ca9QQV2BP5AiWhVE0MGWpfmi9p25GFYebXyVGvOrPD1oPYCrs0CsjiCyaSncMP7keoPz27cF94Q(YVqcsuXkquuigE9YqNyuIuhsNwdjDXlatWEKzDya(P7hCLlCr8YLJs7YO4DgSs6fqGhA9RnYHdVkPr5D8K9EqI4gOOPWay0Q9J8dF2uOENqe2yGcdg7Tf(S5uoRKGu2bIsWjuJltHjwFMP5eg67s(vwXrqG7Eo5SWpm01EzC0EjJ4mHYcCtf9qLvn40Sbx5KPK6R0Y0A(4HRUKr1G8ULj8KojO5I(LOnf9Aazc(Lrtzk34aJLj04U3OnyarnuMCJxyecgTHe6uI7f575aTbbU2UKFKQHtErHAeIuqRbbBsMfhIb(eW6OfHHy7nbElHJilcV5zZ7pOQM7uwZTkR5gj1adal8HUkIEmVDqEu3tMpoH6f7dglVrrD2ziryCeCdidyDLKsl8(PLMILYBmWLm2PlycTJIZxnyyz1Me1kwfXHFqUDvQSYTpXQjP3aEbONfhaUXjlLzyuHvU0B1ASDQyEQk9yyOW85lZ1dL4vyxG(BNWH1f0WjupJp8(jdAv40GC)RFCaez7thFPgPQvB0GL(oyPE53KpXxIzM43uMdsfEHnzrEnjsRqCsWFdvJnzavS1Ll02ekOH19DyTS1a769pPdk4dkODSJMC6bJgDiEppeN1xl7lgk1SpOgmvcyHy7NlaVLO4wcI1O4(okUSevswfmnvfBnmjRKUSPooWWGpsO0zI34XBZmBD4Bpp8TQKqTf0KmFyoD6DAmqVhdCQPs8(YeVu)ZBS7PR9eDTJqJW75iC6TsI9H2yOmy(q2txC69dUk9SKDHa8A7TGOn5NLSCdIP73CpPnC)DHJLrEj(00BZIP80KMspE9BLR8tIiTeDo3VeqJLCZZu8OQ7wr7w73U1IWyvEXNnVt7f75EXO4DysR5ECd5xI5PJVeTZhGXWOSKczx94A42WOO1GvvCpPptILZEidPAJm)pGEvPrRG4r0NGGnoK8vuWNmFWipD0sFWN8HiKn8FHoXjJRm9Orv9Buf)3gZbUK9TZzwO5efiOPe4c)GHGu0WG(omWHOj7tRIizBOY80MmBFe(IhYbsgIQFItmnj5vov2XuDvYohzRqFVbFbaIkCYjjNKVcX9hKdOUltJBjPq8ZbtgYBonxL80sgL8zse3FADiye1qPGEGleLNYmBQil)xYCHqsX8tr6w9x10)HLRwtwXXFVnch5Tbw2Jcn3lW)InfEBN5j2Ut7879o)SftQLBNZzj1aeotd5n6k5(zfEK2bv4n1Z70WFYuTF1qVcx)hKx8bEAyERH5dYVDyUv)hiF1)NnF04q2Mj4ZWKVxcgh23CVomQ3hgH8c8qyye7ofYMU53uA(ZYL5OvYMw0XEnp2thB0pJnSM9cmIswmbY)5tItqN4BycZ7i)8dN4Fy6sFwFV1mMZrGwzkv4injH(zwZCI8ibBEaRzvt9lEoRzHj2tnvhdP0AMkFnB2OQ92gO2cUQ1Cn)kEUrv(DckVqOnGMBf2yAHwZoDQFuZNOJ7R5amHmzC2GIpFQjKJ7CzhhDe8GWiiZIzylhNzNzjCSMtfT5Ok4BQ5uuXJkwQ(KWOR8O1AZOoQ9845zpLAq5ZcnH3AuJ6Bv4fyLdVzOqAYEe516vK3zdNkOHxPcLovmDsDDq5e1tkGr6lCt1tC7KIfxtotrNiTh)SFj8HRecXvcJ4kHsCDab(kNbFxul(SyXxl3ltB3mZLE3mD(2zA2(ze2qZPycXnoKftiOuUOJMqYVpJS8tdMU0GP6UDWQs9QWXuYGiXXQmlOkefx2QUIZtL(WYnAz8Ig73ZX(IFnsDwiTZ3KNoWPv0fS2tq9IbKELG(9kb19mdyXe8FHtPJPdLWLQYjxuLSlQ64G2c2Blwxd275GDvhVuDs7vxEhEwep8)vrl1G(HxSbDdnDDGE)oqVUhZR6SATgxLEfZnNKIAuYLgLu3dFpryC4dzQwQ)7n3911EQQKCJDu6OG(DuG4T9OkkGHVJcx)q9z6OCRvGQJ1NRJnMSJY1VWZ2qdz75q2BQ7LYXrkswqBNqhsTF)s73vDNOfX)v5KBmBj1o5lTtw8s(yt1uoNj)IJ0KAW1LeCLVCrQVM)XtDJ49bYG7KDoaz29BkDk1aKplaeExTaor8UZuT5JcEzw5R9RugzEUuYSB4KPgjEjrIuCM4nZKHRkC(85gvrzZMYzZllPnZNNERyTPg4EPbUQULfEQ2u5IIQj1z3XQtn44sdoepz(mWr2QqncwW7lLABcNTJIwPItokCyTemjyUN5Dm0T8YPsJxhj0XrcI3(qwKqXxVQJf6OyHwWp0Qii65Xq0kNE0rBDC0MkoTiqCuPxc8Bcbs1HO60vF5eaHpDzkuaoqkJrZcN4OiwdO6j)n1Gt0iigVomYA2Va3457DC(WFk9)4gpvT1)9]]
)
