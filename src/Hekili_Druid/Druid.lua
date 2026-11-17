-- Hekili_Druid/Druid.lua
-- The Forever Druid (Balance, Feral, Guardian and an idle Restoration: Hekili:NewClass): the Classic Druid kit with
-- Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build 1.60.1.70338,
-- wowdb; energy and mana costs are DB2 points, rage the DB2 cost / 10), Forever's Shifting Power, Berserk, Primal Bite
-- and Lacerate, bear rage per white swing in Bear Form only, Enrage's rage over time, Clearcasting as a cost modifier,
-- forms from the belief's Forms source, the bleeds' misses from the combat log, and the default priorities (the
-- wowsims.com packs). Design:
-- docs/superpowers/specs/2026-10-15-forever-druid-pack.md.
-- Talents: the DB2's 47 Classic nodes plus three placeholders the live export replaces (checkpoint Q1). Only rank 1 of
-- each talent is in the Forever DB2, so a modifier is rank 1's value x the rank (Classic's convention), floored at 0;
-- no cooldown or duration modifier is modelled but Improved Shifting Power's (spec D5); gear: Insect Swarm's Swarming
-- Idol and Grovekeeper Eclipse 5-piece (set_bonus, gear-aware spec).
-- Credits: Hekili (registration API and pack format); the abilities, auras, handlers and `swap_form` are ported from
-- Hekili's Classic profile (origin/classic:Classic/Druid.lua). Ported from Taco Dog Forever
-- (src/TacoDogForever_Druid/): Enrage's 10 + 2/s and Faerie Fire free in form
-- (Bear.lua), and the `form` alias over the forms (Expressions.lua's RegisterForms). The Feral, Guardian and Balance
-- (wowsims.com) priorities translate wowsims/forever's default APLs (MIT, https://github.com/wowsims/forever).

local Facade = Hekili.Client
local C_Spell, UnitClassBase = Facade.C_Spell, Facade.UnitClassBase
local L = Hekili:GetLocale("Hekili_Druid")

if UnitClassBase("player") ~= "DRUID" then
    return
end

local state = Hekili.State
local IsCurrentSpell = C_Spell.IsCurrentSpell
local floor, max, min = math.floor, math.max, math.min

-- The class kit and its specs (ids the core's: Balance 100111, Feral 100112, Guardian 100113, Restoration 100114).
-- Feral and Guardian ride the Feral Combat tree: its points pick Feral, with Thick Hide 3/3 Guardian (the selector below
-- RegisterTalents); /hekili spec guardian or feral keeps one for the tree.
local spec = Hekili:NewClass("DRUID", {
    specs = {
        {
            key = "balance",
            name = L["Balance"],
            tree = 1,
            icon = 136096,
            role = "attack",
            ranged = true,
            package = "Balance (wowsims.com)",
        },
        {
            key = "feral",
            name = L["Feral"],
            tree = 2,
            icon = 132115,
            role = "attack",
            package = "Feral (wowsims.com)",
            movement = true, -- the pack reads toggle.movement: the run into melee reaches the damage lines (R8)
        },
        {
            key = "guardian",
            name = L["Guardian"],
            tree = 2,
            icon = 132276,
            role = "tank",
            package = "Guardian (wowsims.com)",
            movement = true, -- the pack reads toggle.movement: the run into melee reaches the damage lines (R8)
        },
        { key = "restoration", name = L["Restoration"], tree = 3, icon = 136041, role = "healer", unsupported = true },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's), and the per-rank values the DB2 gives.
local CLAW = { 1082, 3029, 5201, 9849, 9850 }
local SHRED = { 5221, 6800, 8992, 9829, 9830 }
local RAKE = { 1822, 1823, 1824, 9904, 1289140 } -- 1289140: Forever's variant
local RIP = { 1079, 9492, 9493, 9752, 9894, 9896, 1289141 }
local FEROCIOUS_BITE = { 1328618, 22568, 22827, 22828, 22829, 31018, 1289142 }
local RAVAGE = { 6785, 6787, 9866, 9867 }
local POUNCE = { 9005, 9823, 9827 }
local POUNCE_BLEED = { 9007, 9824, 9826 }
local COWER = { 8998, 9000, 9892 }
local PROWL = { 5215, 6783, 9913 }
local DASH = { 1850, 9821 }
local SHIFTING_POWER = { 1322605 }
local BERSERK = { 417141 }
local CAT_FORM = { 768 }
local BEAR_FORM = { 5487, 9634 } -- Dire Bear Form is Bear Form's rank 2
local MOONKIN_FORM = { 24858 }
local TRAVEL_FORM = { 783 }
local AQUATIC_FORM = { 1066 }
local MAUL = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 }
local SWIPE = { 779, 780, 769, 9754, 9908 }
local PRIMAL_BITE = { 407995, 1238069, 1238070, 1238073 } -- Mangle, renamed
local LACERATE = { 1328617, 1328616, 414644, 1235826, 1235827 } -- hotfix 113554: the talent rank 1, rank 2 at 34
local DEMORALIZING_ROAR = { 99, 1735, 9490, 9747, 9898 }
local GROWL = { 6795 }
local BASH = { 5211, 6798, 8983 }
local BASH_STUN = { 2, 3, 4 }
local CHALLENGING_ROAR = { 5209 }
local ENRAGE = { 5229 }
local FRENZIED_REGENERATION = { 22842 }
local FERAL_CHARGE = { 1238122, 16979 } -- the trainer's spell, then the old talent's
local FAERIE_FIRE = { 770, 778, 9749, 9907 }
local FAERIE_FIRE_COST = { 55, 75, 95, 115 }
local WRATH = { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 }
local WRATH_COST = { 10, 20, 40, 50, 70, 80, 100, 120 }
local WRATH_CAST = { 1.5, 1.7, 2, 2, 2, 2, 2, 2 }
-- Eclipse's cut of Starfire's cast by talent rank (DB2 effect 2: -170/-330/-500 ms)
local ECLIPSE_CUT = { 0.17, 0.33, 0.5 }
local STARFIRE = { 2912, 8949, 8950, 8951, 9875, 9876, 25298 }
local STARFIRE_COST = { 95, 135, 180, 230, 275, 315, 340 }
local MOONFIRE = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 }
local MOONFIRE_COST = { 25, 50, 75, 105, 150, 190, 235, 280, 325, 375 }
local INSECT_SWARM = { 5570, 24974, 24975, 24976, 24977 }
local INSECT_SWARM_COST = { 45, 85, 100, 140, 160 }
local HURRICANE = { 16914, 17401, 17402 }
local HURRICANE_COST = { 880, 1180, 1495 }
local ROOTS = { 339, 1062, 5195, 5196, 9852, 9853 }
local ROOTS_COST = { 50, 65, 80, 95, 110, 125 }
local ROOTS_DURATION = { 12, 15, 18, 21, 24, 27 }
local INNERVATE = { 29166 }
local BARKSKIN = { 22812 }
local NATURES_GRASP = { 16689, 16810, 16811, 16812, 16813, 17329 }
local NATURES_GRASP_COST = { 50, 65, 80, 95, 110, 125 }
local MARK_OF_THE_WILD = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }
local MARK_OF_THE_WILD_COST = { 20, 50, 100, 160, 240, 340, 445 }
local GIFT_OF_THE_WILD = { 21849, 21850 }
local GIFT_OF_THE_WILD_COST = { 900, 1200 }
local THORNS = { 467, 782, 1075, 8914, 9756, 9910 }
local THORNS_COST = { 35, 60, 105, 170, 240, 320 }
local HEALING_TOUCH = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 }
local HEALING_TOUCH_COST = { 25, 55, 110, 190, 280, 350, 425, 520, 630, 755, 840 }
local HEALING_TOUCH_CAST = { 1.5, 2, 2.5, 3, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5 }
local REGROWTH = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 }
local REGROWTH_COST = { 70, 125, 170, 210, 250, 305, 370, 445, 525 }
local REJUVENATION = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 }
local REJUVENATION_COST = { 25, 40, 75, 105, 135, 160, 195, 235, 280, 335, 360 }
-- The manual-press Restoration kit (wowsims pin spells_auto_gen.go: cast, cost, cooldown; a cost below 1 is a percent of
-- base mana). Registered so a press costs what it costs and starts its cooldown; no priority recommends them.
local SWIFTMEND = { 18562 }
local WILD_GROWTH = { 408120, 1238214, 1238215 }
local WILD_GROWTH_COST = { 550, 755, 1050 }
local TRANQUILITY = { 740, 8918, 9862, 9863 }
local TRANQUILITY_COST = { 375, 505, 695, 925 }
local REBIRTH = { 20484, 20739, 20742, 20747, 20748 }
local HIBERNATE = { 2637, 18657, 18658 }
local HIBERNATE_COST = { 90, 120, 150 }
local HIBERNATE_DURATION = { 20, 30, 40 }
local SOOTHE_ANIMAL = { 2908, 8955, 9901 }
local SOOTHE_ANIMAL_COST = { 50, 75, 100 }
local ABOLISH_POISON = { 2893 }
local CURE_POISON = { 8946 }
local REMOVE_CURSE = { 2782 }
local REVIVE = { 1237951 }

-- Gear (gear-aware spec §4; r33 section 0): the item and set IDs the pack's set_bonus reads (wowsims/forever at
-- e2842f0a78, db.json). Registered on the kit: every tree reads the same keys.
local GEAR = {
    swarming_idol = 272430, -- 1291061: Insect Swarm +2 s (sim/druid/item_idols.go:72-80)
    -- Grovekeeper Eclipse (set 2114, sim/druid/item_sets.go:31-52): the 4 pieces the game files ship (Trousers,
    -- Grips, Shoulderpads, Stompers); the head and chest join when they ship. 5-piece 1301242: Insect Swarm +3 s.
    grovekeeper_eclipse = { 273884, 273885, 273886, 273887 },
    grovekeeper_eclipse_5pc = 1301242,
    -- Haruspex's Garb (ZG, set 479, db.json setId; sim/druid/item_sets.go:56-73): five items, the 3-piece's hidden aura
    -- 24479 makes Faerie Fire last 5 s longer.
    haruspex = { 19613, 19838, 19839, 19840, 19955 },
    haruspex_3pc = 24479,
}

-- The forms, in `buff.form`'s member order (one is up at a time).
local FORMS = { "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form" }

-- Shifting Power's energy (DB2 1322605 effect 30, base 40) and bear rage per white swing (spec §2.3, D4): the
-- two-hand rate (4.5 a second) x the form's unhasted 2.5 s swing, 11.25 a swing, and a crit doubles it (22.5: wowsims
-- 7c28cfa731 core/rage.go, from Forever combat logs; owner ruling W1 2026-11-02), until checkpoint Q8.
-- The swing is the form's fixed period, not the belief's out-of-combat base read, which holds the pull's form (1.0 s
-- after a Cat pull) through an in-combat shift (GCD kinds design D4; checkpoint G6 reads both forms' speeds).
local SHIFTING_POWER_ENERGY = 40
local BEAR_RAGE_RATE = 4.5
-- Furor's rage into Bear Form (wowsims forms.go furorRageOnEnterBear): 17057's energize, 10, at 20% a rank (17056
-- effect 1): certain at 5/5.
local FUROR_RAGE = 10
local BEAR_SWING = 2.5
-- Primal Fury ("Blood Frenzy" on Forever, DB2 16958; wowsims/forever talents_feral_combat.go): a melee crit of ours in
-- Bear Form gives 16959's 5 rage, always at 2/2 and half the time at 1/2 (wowsims's ladder): its expected rage. The
-- Cat's combo point on a builder's crit is not declared: combo points are a plain read on Forever.
local PRIMAL_FURY = 5
local function primalFury(rank)
    return PRIMAL_FURY * rank / 2
end
-- A bear strike's `onCrit` (the belief's own crit, Families/Now.lua): a closure per ability.
local function primalFuryOnCrit()
    return function()
        if buff.bear_form.up then
            gain(primalFury(talent.primal_fury.rank), "rage")
        end
    end
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
-- A helper's environment is the file's, so it keeps this local; a pack function's bare `knownRank` is its environment's.
local rankOf = state.knownRank

local function knows(ids)
    return function()
        return rankOf(ids) > 0
    end
end

-- A per-rank value at the highest known rank, else the first rank's (nothing known yet).
local function byRank(values, ids)
    return values[rankOf(ids)] or values[1]
end

-- Moonglow (16845) on its class mask's spells (Wrath, Moonfire, Starfire, Insect Swarm, Hurricane, Entangling Roots,
-- Thorns) and Improved Wrath (16814 effect 1) on Wrath: the DB2's -25% and -50% are the full ranks'. Moonglow's ranks
-- follow wowsims/forever's ladder (spells_auto_gen.go 16845: -8, -17, -25 %; its log: Moonfire 281.25 at 3/3).
local MOONGLOW = { 0.92, 0.83, 0.75 }
local function moonglow(rank)
    return MOONGLOW[rank] or 1
end

-- regen: energy's base rate a second, the belief's from the build until a plain rate read (energy is secret even out
-- of combat): wowsims/forever's 1 energy every 0.1 s (sim/core/energy.go:48-49).
-- refundOnAvoid (energy here, rage below): the share an ability flagged `refundOnAvoid = true` gives back when dodged,
-- parried or missed (wowsims/forever druid/feral.go refundOnMiss and MissRefund: 0.8 where the DB2 flags Discount
-- Power On Miss), Ferocious Bite's too (wowsims e4ef929e54 ferocious_bite.go: 80% of its 35 base energy); not Swipe,
-- Faerie Fire (Feral) or Demoralizing Roar.
-- bear_pause: no energy comes in Bear Form (wowsims forms.go pauseCatEnergy); out of Cat it comes as in Cat, so the
-- pool at a Cat entry is wowsims's stored energy plus 10 a second outside Bear, capped (Furor's share: swap_form).
spec:RegisterResource(
    Enum.PowerType.Energy,
    { bear_pause = { aura = "bear_form", mult = 0 } },
    nil,
    { regen = 10, refundOnAvoid = 0.8 }
)
spec:RegisterResource(Enum.PowerType.ComboPoints)

spec:RegisterResource(
    Enum.PowerType.Rage,
    {
        -- Rage per white swing in Bear or Dire Bear Form only (the Warrior's speed rule; Cat and caster swings add
        -- none).
        -- `aura` gates it in both layers (the belief's swing entry, spec §0.3; Hekili's forecast); `stop` too.
        -- A white crit adds one more base swing (without the two-hand factor), as wowsims's, and Primal Fury's rage:
        -- `crit`. A yellow crit's Primal Fury is the strikes' `onCrit`.
        -- NAMED GAP (owner 2026-11-07): no `taken` (rage from hits) until CN7 gives the belief its hook; the archived rule
        -- (lane-feralguardian-taken-wip.patch) lifts the Guardian replay 0.632 -> 0.923 but with replay flicker 14.65/min: land it
        -- only with CN7 + CN9, never blind.
        -- shortcut: misses, Natural Reaction and rage from damage taken are unmodelled; the belief's swing-scale
        -- calibration absorbs a steady bias. Upgrade from the combat-log rows once a non-cast `now` exists.
        mainhand = {
            swing = "mainhand",
            aura = "bear_form",

            last = function()
                local swing = state.swings.mainhand
                local t = state.query_time
                if state.mainhand_speed == 0 then
                    return 0
                end
                return swing + floor((t - swing) / state.mainhand_speed) * state.mainhand_speed
            end,

            interval = "mainhand_speed",

            stop = function()
                return state.swings.mainhand == 0 or not state.buff.bear_form.up
            end,
            value = function()
                return BEAR_RAGE_RATE * BEAR_SWING
            end,
            crit = function()
                return BEAR_RAGE_RATE * BEAR_SWING + primalFury(talent.primal_fury.rank)
            end,
        },

        -- Enrage's aura (25503): 2 rage every second for 10 s (DB2: periodic energize 20 every 1000 ms).
        -- No `pausesDecay`: whether Enrage pauses the out-of-combat decay is unverified (checkpoint Q9).
        enrage = {
            aura = "enrage",

            last = function()
                local app = state.buff.enrage.applied
                return app + floor(state.query_time - app)
            end,

            interval = 1,
            value = 2,
        },
    },
    nil,
    {
        -- Out-of-combat rage loss per second: the Warrior's measured 1.25 (its Rage tooltip), until checkpoint Q9 reads
        -- it in Bear Form.
        decay = function()
            return 1.25
        end,
        -- Stepped and front-loaded, as the Warrior's.
        decayInterval = function()
            return 1
        end,
        refundOnAvoid = 0.8, -- the Energy line's note above
    }
)

-- Reflection (17106): 17/33/50% of the spirit regen while casting by rank (wowsims's curve, e5a9cd2a2d).
local REFLECTION = { 0.17, 0.33, 0.5 }

-- Mana: secret even out of combat. A cost below 1 is a percent of base mana (DB2 PowerCostPct: the forms, Shifting
-- Power, Innervate), priced in both layers from `base`: wowsims's 1244 at 60 (its log: Shifting Power and Cat Form
-- 684 = 55%, Innervate 62 = 5%, whole mana rounded down) until the client's cost read teaches the player's own. The
-- five-second rule (C3): spirit regen a second outside it, none inside it, the declared start the out-of-combat read
-- replaces (wowsims/forever's Feral and Balance logs: 2.175 and 2.2 mana a 0.1 s tick outside it, pre-raid gear).
spec:RegisterResource(
    Enum.PowerType.Mana,
    {
        -- Innervate's regen (spirit x 5, all of it while casting) is the shared entry every mana user has
        -- (Hekili_Shared/Shared/Auras.lua), the Druid's own cast included: not declared here (it would count twice).
        -- The Serenity Field trinket's buff (item 272439; DB2 aura 1291103: aura 29 Spirit +72, 15 s; an item's buff any
        -- Druid may wear; the other classes' packs: docs/dev/gaps.md): Spirit +72 raises the spirit regen S = 6.25 +
        -- Spirit/8 by 9 a second, so the part x (S + 9) / S, Spirit the belief's out-of-combat read (druid_balance.log:
        -- 12.61 -> 17.11 a second casting at Spirit 139 and Reflection 3/3, + 0.5 x 9); 1 before that read.
        serenity_field = {
            aura = "serenity_field",
            item = 272439, -- the replay's key: wowsims logs the buff by its item
            spirit = function()
                local _, s = stat("UnitStat", 5)
                return s > 0 and 1 + 9 / (6.25 + s / 8) or 1
            end,
        },
    },
    nil,
    {
        -- the share: Reflection's rank (the belief reads it after its talent walk). shortcut: the seeds are the
        -- unreflected builds' (Feral, Guardian); a Reflection build (wowsims's Balance export, 3/3) starts from them
        -- until the out-of-combat read splits its own parts.
        fsr = {
            spirit = 22,
            mp5 = 0,
            share = function()
                return REFLECTION[talent.reflection.rank] or 0
            end,
        },
        base = 1244, -- wowsims's ExtraClassBaseStats, level 60
    }
)

-- Talents: { talent tree (1 Balance, 2 Feral Combat, 3 Restoration: the dominant tree picks the spec), rank 1's
-- spell, max rank }: Forever's tree as wowsims/forever's ui/sim/talents/trees/druid.json lists it
-- (tools/wowsims/talents.lua writes it; tests/Forever/talent_trees_spec.lua checks it and the spec detection over it). A
-- key is Classic's where the talent exists there (code reads `talent.<key>.rank`), else the snake_case of the node's
-- name.
spec:RegisterTalents({
    -- Balance (tree 1)
    improved_wrath = { 1, 16814, 5 },
    genesis = { 1, 1223081, 5 },
    moonglow = { 1, 16845, 3 },
    improved_moonfire = { 1, 16821, 2 },
    natures_majesty = { 1, 1223082, 2 },
    natures_reach = { 1, 16819, 2 },
    improved_entangling_roots = { 1, 16918, 3 },
    natures_splendor = { 1, 1223083, 1 },
    insect_swarm = { 1, 5570, 1 },
    vengeance = { 1, 16909, 5 },
    improved_starfire = { 1, 16850, 5 },
    improved_natures_grasp = { 1, 17245, 2 },
    natures_grace = { 1, 16880, 1 },
    eclipse = { 1, 408248, 3 },
    moonfury = { 1, 16896, 5 },
    moonkin_form = { 1, 24858, 1 },
    -- Feral Combat (tree 2)
    ferocity = { 2, 16934, 5 },
    furor = { 2, 17056, 5 }, -- hotfix 113554: moved to Feral Combat
    feline_swiftness = { 2, 17002, 2 },
    feral_instinct = { 2, 16947, 3 },
    brutal_impact = { 2, 16940, 2 },
    thick_hide = { 2, 16929, 3 },
    improved_shred = { 2, 16966, 3 },
    savage_fury = { 2, 16998, 2 },
    feral_charge = { 2, 1238122, 1 },
    sharpened_claws = { 2, 16942, 2 },
    predatory_strikes = { 2, 16972, 3 },
    lacerate = { 2, 1328617, 1 }, -- hotfix 113554: Lacerate's rank 1 is a talent
    predatory_discipline = { 2, 1328613, 1 }, -- hotfix 113554: Bite keeps its extra energy
    primal_fury = { 2, 16958, 2 }, -- "Blood Frenzy" on Forever
    leader_of_the_pack = { 2, 17007, 1 },
    natural_instinct = { 2, 1223242, 2 },
    rend_and_tear = { 2, 1223246, 5 },
    natural_reaction = { 2, 417051, 5 },
    primal_bite = { 2, 407995, 1 },
    shifting_power = { 2, 1322605, 1 },
    -- Restoration (tree 3)
    natures_focus = { 3, 17063, 5 },
    heart_of_the_wild = { 3, 17003, 5 }, -- hotfix 113554: moved to Restoration
    improved_healing_touch = { 3, 17069, 5 },
    reflection = { 3, 17106, 3 },
    natural_shapeshifter = { 3, 16833, 3 },
    subtlety = { 3, 17118, 3 },
    gift_of_nature = { 3, 17104, 5 },
    bloom = { 3, 1328621, 1 },
    tranquil_spirit = { 3, 24968, 5 },
    improved_rejuvenation = { 3, 17111, 3 },
    swiftmend = { 3, 18562, 1 },
    natures_swiftness = { 3, 17116, 1 },
    living_spirit = { 3, 1309631, 3 },
    improved_tranquility = { 3, 17123, 2 },
    improved_regrowth = { 3, 17074, 5 },
    wild_growth = { 3, 408120, 1 },
})

-- Spec and pack from the talents (Engine/Schema/Selectors.lua; after the Hekili classic branch's pack selectors).
-- wowsims's Guardian and Feral builds both spend 32 points in Feral Combat; only Guardian takes Thick Hide (3/3, with
-- Feral Instinct, Lacerate and Primal Bite), so Feral Combat ahead with all of Thick Hide is Guardian (one stray point
-- does not turn a Feral build). Anything else on the tree is Feral (the tree's first spec), unless the player
-- activated Guardian for it.
spec:RegisterSelector("guardian", { spec = "guardian", pack = "Guardian (wowsims.com)" }, function(tab1, tab2, tab3)
    return tab2 > tab1 and tab2 > tab3 and talent.thick_hide.rank >= 3
end)

spec:RegisterGear("swarming_idol", GEAR.swarming_idol)
spec:RegisterGear("grovekeeper_eclipse", unpack(GEAR.grovekeeper_eclipse))
spec:RegisterSetBonus("grovekeeper_eclipse_5pc", GEAR.grovekeeper_eclipse_5pc)
spec:RegisterGear("haruspex", unpack(GEAR.haruspex))
spec:RegisterSetBonus("haruspex_3pc", GEAR.haruspex_3pc)

spec:RegisterAuras({
    serenity_field = { id = 1291103, duration = 15, max_stack = 1 },
    -- The forms are one family (L727, owner: as the seals): the Cooldown Manager's Druid Forms entry says a form is up
    -- or none is, our last form cast says which; the plain shapeshift read (Game/State/Sources/Forms.lua) wins.
    aquatic_form = {
        id = 1066,
        duration = 3600,
        max_stack = 1,
        family = "forms",
    },
    barkskin = {
        id = 22812,
        duration = 15,
        max_stack = 1,
    },
    bash = {
        id = 5211,
        -- 1324487/8/90: the debuff ids the Cooldown Manager's Bash entry links
        copy = { 6798, 8983, 1324487, 1324488, 1324490 },
        duration = function()
            return (BASH_STUN[knownRank(BASH)] or 2) + 0.5 * talent.brutal_impact.rank
        end,
        max_stack = 1,
    },
    bear_form = {
        id = 5487,
        copy = { 9634 },
        duration = 3600,
        max_stack = 1,
        family = "forms",
    },
    berserk = {
        id = 417141,
        duration = 15,
        max_stack = 1,
    },
    -- The Howling Idol's equip aura (272427): "Reduces the cooldown of your Shifting Power ability" (DB2 1291059).
    howling_idol = {
        id = 1291059,
        duration = 3600,
        max_stack = 1,
    },
    -- The Grovekeeper Eclipse 5-piece's hidden aura (1301242): tracked so set_bonus.grovekeeper_eclipse_5pc reads it
    -- (both environments read the belief's record: Facade GetPlayerAuraBySpellID; gear-aware spec §2).
    grovekeeper_eclipse_5pc = {
        id = 1301242,
        duration = 3600,
        max_stack = 1,
    },
    -- The Haruspex's Garb 3-piece's hidden aura (24479): tracked so set_bonus.haruspex_3pc reads it.
    haruspex_3pc = {
        id = 24479,
        duration = 3600,
        max_stack = 1,
    },
    -- The Idol of Ferocity's equip aura (22397; wowsims e4ef929e54 sim/druid/item_idols.go, 27851 "Reduced Claw and Rake
    -- Cost"): Claw and Rake cost 2 less (the cost modifier below; class_items_test.go). The Feral pack branches on it.
    -- Not yet checked in game.
    idol_of_ferocity = {
        id = 27851,
        duration = 3600,
        max_stack = 1,
    },
    -- The Idol of the Dream's equip aura (220606; wowsims e4ef929e54 sim/druid/items.go, 446212 "Improved Rip"): Rip
    -- lasts 2 s longer, its ticks unchanged (rip below; TestIdolOfTheDreamExtendsRipWithoutChangingItsTicks). The Feral
    -- pack branches on it. Not yet checked in game.
    idol_of_the_dream = {
        id = 446212,
        duration = 3600,
        max_stack = 1,
    },
    -- The Wolfshead Helm's equip aura (8345, DB2 17768): Shifting Power +5 energy, Enrage's instant rage +50%
    -- (wowsims/forever sim/druid/items.go; its log gains the aura at 0 s and 45 energy a Shifting Power).
    wolfshead_helm = {
        id = 17768,
        duration = 3600,
        max_stack = 1,
    },
    -- Classic's alias without the other classes' bleeds.
    bleed = {
        alias = { "rake", "rip", "pounce_bleed", "lacerate" },
        aliasType = "debuff",
        aliasMode = "longest",
    },
    cat_form = {
        id = 768,
        duration = 3600,
        max_stack = 1,
        family = "forms",
    },
    challenging_roar = {
        id = 5209,
        duration = 6,
        max_stack = 1,
    },
    -- Omen of Clarity's proc (a passive on Forever): the next covered ability is free (the cost modifier below). It
    -- procs at most once per 10 s (16864's SpellAuraOptions.ProcCategoryRecovery 10000; wowsims ICDMs 10000), the ICD
    -- wowsims names by 16864.
    clearcasting = {
        id = 16870,
        duration = 15,
        max_stack = 1,
        icd = 10,
        icdSpell = 16864,
    },
    -- Poised (passive 1328829, buff 1328827; wowsims dd2fda98b9, hotfix 113351/113578): out of combat at full energy
    -- the next Claw, Rake, Shred, Ravage, Pounce, Rip, Ferocious Bite or Cower costs 10 less (the cost modifier
    -- below). Not yet checked in game.
    poised = {
        id = 1328827,
        duration = 3600,
        max_stack = 1,
    },
    dash = {
        id = 1850,
        copy = rest(DASH),
        duration = 15,
        max_stack = 1,
    },
    demoralizing_roar = {
        id = 99,
        copy = rest(DEMORALIZING_ROAR),
        duration = 30,
        max_stack = 1,
    },
    eclipse = {
        id = 408255,
        copy = { 441260, 408248 }, -- 408248: the talent's CDM item (cooldownID 199506)
        duration = 15,
        max_stack = 4,
    },
    entangling_roots = {
        id = 339,
        copy = rest(ROOTS),
        duration = function()
            return ROOTS_DURATION[knownRank(ROOTS)] or 12
        end,
        max_stack = 1,
    },
    -- The rage entry's aura: 25503 is the 10 s buff, 5229 the cast.
    enrage = {
        id = 25503,
        copy = { 5229 },
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    faerie_fire = {
        id = 770,
        copy = rest(FAERIE_FIRE),
        duration = function() -- the Haruspex's Garb 3-piece: +5 s
            return 40 + (set_bonus.haruspex_3pc > 0 and 5 or 0)
        end,
        max_stack = 1,
    },
    feral_charge_effect = {
        id = 19675,
        copy = { 414923 }, -- the Cooldown Manager's Feral Charge entry links it too
        duration = 4,
        max_stack = 1,
    },
    -- Cat or Bear Form: Faerie Fire's free cost and cooldown.
    feral_form = {
        alias = { "cat_form", "bear_form" },
        aliasType = "buff",
        aliasMode = "first",
    },
    form = {
        alias = FORMS,
        aliasType = "buff",
        aliasMode = "first",
    },
    frenzied_regeneration = {
        id = 22842,
        copy = { 22845 }, -- the buff the Cooldown Manager links
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    -- mark_of_the_wild and gift_of_the_wild are Hekili_Shared/Shared/Auras.lua's: every class carries them (L971).
    growl = {
        id = 6795,
        duration = 3,
        max_stack = 1,
    },
    hurricane = {
        id = 16914,
        -- 1278965/1278968/1278759: the debuff each rank's tick puts on the target (ranks 1-3), the IDs the viewer reports
        copy = { 17401, 17402, 1278965, 1278968, 1278759 },
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    innervate = {
        id = 29166,
        duration = 20,
        tick_time = 1,
        max_stack = 1,
    },
    insect_swarm = {
        id = 5570,
        copy = rest(INSECT_SWARM),
        duration = function() -- the one expression both environments evaluate (gear-aware spec §5)
            return 12
                + 2 * talent.natures_splendor.rank
                + (set_bonus.swarming_idol > 0 and 2 or 0)
                + (set_bonus.grovekeeper_eclipse_5pc > 0 and 3 or 0) -- Q1: the 5-piece aura, or 5 pieces worn
        end,
        tick_time = 2,
        dot = "debuff", -- Insect Swarm's schedule
        max_stack = 1,
    },
    lacerate = {
        id = 1328617,
        copy = { 1328616, 414644, 1235826, 1235827, 414647 }, -- 414647: the viewer's Lacerate (no rank text)
        duration = 15,
        tick_time = 3,
        max_stack = 5,
    },
    -- Maul queued on the next swing (C_Spell.IsCurrentSpell, applied in reset_precast), a full swing long.
    maul = {
        duration = function()
            return state.mainhand_speed
        end,
        max_stack = 1,
    },
    moonfire = {
        id = 8921,
        copy = rest(MOONFIRE),
        duration = function()
            return (knownRank(MOONFIRE) > 1 and 12 or 9) + 3 * talent.natures_splendor.rank
        end,
        tick_time = 3,
        dot = "debuff", -- upstream's aura field (Engine/Sim/State.lua:3302): Moonfire's schedule
        max_stack = 1,
    },
    moonkin_form = {
        id = 24858,
        duration = 3600,
        max_stack = 1,
        family = "forms",
    },
    natures_grace = {
        id = 16886,
        copy = { 16880 }, -- the talent's CDM item (cooldownID 199845)
        duration = 3,
        max_stack = 1,
    },
    -- The next Wrath is instant (it spends the buff; the pin's flags reach Wrath, not Starfire).
    natures_swiftness = {
        id = 17116,
        duration = 3600,
        max_stack = 1,
    },
    natures_grasp = {
        id = 16689,
        copy = rest(NATURES_GRASP),
        duration = 45,
        max_stack = 1,
    },
    pounce = {
        id = 9005,
        copy = rest(POUNCE),
        duration = function()
            return 2 + 0.5 * talent.brutal_impact.rank
        end,
        max_stack = 1,
    },
    pounce_bleed = {
        id = 9007,
        copy = rest(POUNCE_BLEED),
        duration = 18,
        tick_time = 3,
        max_stack = 1,
    },
    prowl = {
        id = 5215,
        copy = rest(PROWL),
        duration = 3600,
        max_stack = 1,
    },
    rake = {
        id = 1822,
        copy = rest(RAKE),
        duration = 9,
        tick_time = 3,
        max_stack = 1,
    },
    rip = {
        id = 1079,
        copy = rest(RIP),
        duration = function() -- the Idol of the Dream's 2 s (above)
            return buff.idol_of_the_dream.up and 14 or 12
        end,
        tick_time = 2,
        max_stack = 1,
    },
    thorns = {
        id = 467,
        copy = rest(THORNS),
        duration = 600,
        max_stack = 1,
    },
    travel_form = {
        id = 783,
        duration = 3600,
        max_stack = 1,
        family = "forms",
    },
    -- Auras the Cooldown Manager's buff entries link (cdm fixture, the owner's export): every rank, the pin's durations.
    -- Nothing reads them but the map; Wild Growth's and Abolish Poison's land on the healed ally.
    wild_growth = { id = 408120, copy = { 1238214, 1238215 }, duration = 7, max_stack = 1 },
    tranquility = { id = 740, copy = { 8918, 9862, 9863 }, duration = 10, max_stack = 1 },
    hibernate = {
        id = 2637,
        copy = { 18657, 18658 },
        duration = function()
            return HIBERNATE_DURATION[knownRank(HIBERNATE)] or 20 -- the pin: 20 / 30 / 40 s by rank
        end,
        max_stack = 1,
    },
    soothe_animal = { id = 2908, copy = { 8955, 9901 }, duration = 15, max_stack = 1 },
    abolish_poison = { id = 2893, duration = 8, max_stack = 1 },
    starfire_stun = { id = 16922, duration = 3, max_stack = 1 }, -- Improved Starfire's stun
    leader_of_the_pack = { id = 24932, duration = 3600, max_stack = 1 },
    moonkin_aura = { id = 24907, duration = 3600, max_stack = 1 },
})

-- Clearcasting (16870): aura 108 misc 14 (cost) -100% on the abilities its class masks name (15973374 / 100664659 /
-- 1024 / 142606400 against SpellClassSet 7), so the next one is free; a covered cast whose declared cost is above 0
-- takes the charge. The rank-1 IDs of the covered abilities this file registers (higher ranks resolve through each
-- ability's `copy`), from
--   select distinct o.SpellID, n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID
--     join SpellPower p on p.SpellID=o.SpellID where o.SpellClassSet=7 and (p.ManaCost>0 or p.PowerCostPct>0) and not
--     ((o.SpellClassMask_0 & 15973374)=0 and (o.SpellClassMask_1 & 100664659)=0 and (o.SpellClassMask_2 & 1024)=0
--     and (o.SpellClassMask_3 & 142606400)=0)
-- Covered but unregistered: the rune spells. Wild Growth (408120, mask word 1 bit 26) is covered. Not covered: Wrath, Faerie Fire, Cower,
-- Challenging Roar, Mark and Gift of the Wild, Shifting Power. Checkpoint Q6 confirms Primal Bite and Demoralizing Roar
-- (usable at 0 rage with Clearcasting up).
spec:RegisterCostMod({
    aura = "clearcasting",
    pct = -1,
    charges = 1,
    spells = {
        8921,
        2912,
        5570,
        16914,
        5185,
        8936,
        774,
        1082,
        1822,
        5221,
        1079,
        1328618,
        9005,
        6785,
        779,
        6807,
        1328617,
        5211,
        1238122,
        339,
        467,
        16689,
        407995,
        99,
        740,
        18562,
        408120,
    },
})

-- Poised (1328827): aura 107 misc 14 -10 flat Energy on the class mask {8622080, 536870912} against SpellClassSet 7 (the
-- eight abilities wowsims's mechanics_test names; rank-1 IDs, the ranks through each ability's `copy`); one charge.
spec:RegisterCostMod({
    aura = "poised",
    flat = -10,
    charges = 1,
    spells = { 1082, 1822, 5221, 6785, 9005, 1079, 1328618, 8998 },
})

-- The Idol of Ferocity (27851): aura 107 misc 14 -2 flat Energy on Claw and Rake (wowsims e4ef929e54
-- class_items_test.go; rank-1 IDs, the ranks through each ability's `copy`).
spec:RegisterCostMod({
    aura = "idol_of_ferocity",
    flat = -2,
    spells = { 1082, 1822 },
})

-- Nature's Grace (16886; wowsims talents_balance.go applyNaturesGrace): its 10% cast speed (effect 0) shortens every
-- spell GCD, and effect 1 cuts the GCD 10% more on its class mask's spells (these, by rank 1 ID). The wowsims Balance
-- log: 1.5 / 1.1 x 0.9 = 1.227 s on the mask, 1.364 s off it (Innervate).
-- shortcut: the cast speed is a modifier because no haste the belief reads holds the 3 s buff; upgrade if a plain
-- in-combat spell haste read is found to include it (the GCD would then take it twice).
spec:RegisterGcdMod({ aura = "natures_grace", pct = 1 / 1.1 - 1 })
spec:RegisterGcdMod({
    aura = "natures_grace",
    pct = -0.1,
    spells = { 339, 467, 770, 774, 1126, 2912, 5176, 5185, 5570, 8921, 8936, 16689, 16914, 21849 },
})

-- wowsims's druidBleedIsActive (wowsims/forever sim/druid/feral.go targetIsBleeding, apl_values.go): Rake, Rip, Lacerate
-- or Pounce's bleed on the target. Its assumeBleedActive (both requests set it) has no in-game reading: the real target.
spec:RegisterStateExpr("druid_bleed_active", function()
    return debuff.rake.up or debuff.rip.up or debuff.lacerate.up or debuff.pounce_bleed.up
end)

-- A shift (Classic's swap_form, Forever's rules): the other forms and a queued Maul go; into Bear all rage is lost,
-- then Furor's 10 at 20% a rank (wowsims forms.go): the sim from its floor, so at 5/5 only (the belief's `now` sets
-- 1-4/5's unseen roll as [0, 10]); into Cat the rage stays (wowsims's Cat Form leaves it: the decay takes it out of
-- combat) and the energy becomes Furor's 20% a rank of the pool (wowsims forms.go restoreCatEnergy; the pool is its
-- stored energy, bear_pause above): none untalented, as the owner's client showed (L586). wowsims keeps the bar on a
-- first entry with nothing stored, its pull only: the belief cannot tell one after a /reload, so every entry takes
-- the share. The forms' `now` write the same lines.
spec:RegisterStateFunction("swap_form", function(form)
    for i = 1, #FORMS do
        removeBuff(FORMS[i])
    end
    removeBuff("maul")
    if form == "bear_form" then
        spend(rage.lo, "rage") -- the sim's floor (border batch 2)
        if talent.furor.rank >= 5 then
            gain(FUROR_RAGE, "rage")
        end
    elseif form == "cat_form" then
        spend(energy.lo * (5 - talent.furor.rank) / 5, "energy") -- keeps rank / 5 of the sim's floor (border batch 2)
    end
    applyBuff(form)
end)

spec:RegisterHook("reset_precast", function()
    -- The form comes from the belief's Forms source (Game/State/Sources/Forms.lua) through the aura walk.
    local maul = knownRank(MAUL)
    if maul > 0 and IsCurrentSpell(MAUL[maul]) then
        applyBuff("maul")
    end
end)

spec:RegisterAbilities({
    aquatic_form = {
        id = 1066,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.20 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(AQUATIC_FORM),
        nobuff = "aquatic_form",

        -- what the cast did to the now-state, in the belief's context (spec §12a)
        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            applyBuff("aquatic_form")
        end,

        handler = function()
            swap_form("aquatic_form")
        end,
    },

    barkskin = {
        id = 22812,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        startsCombat = false,
        known = knows(BARKSKIN),
        toggle = "defensives",

        now = function()
            applyBuff("barkskin")
        end,

        handler = function()
            applyBuff("barkskin")
        end,
    },

    bash = {
        id = 5211,
        copy = rest(BASH),
        cast = 0,
        cooldown = function()
            return 60 - 15 * talent.brutal_impact.rank -- Brutal Impact 16940 effect 1: -15 / -30 s on Bash
        end,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims bash.go; DB2 Discount Power On Miss
        known = knows(BASH),
        form = "bear_form",

        now = function()
            applyDebuff("target", "bash", (BASH_STUN[knownRank(BASH)] or 2) + 0.5 * talent.brutal_impact.rank)
        end,

        handler = function()
            applyDebuff("target", "bash")
        end,
    },

    bear_form = {
        id = 5487,
        copy = { 9634 },
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.55 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(BEAR_FORM),
        nobuff = "bear_form",

        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            local f = talent.furor.rank -- all rage goes, then Furor's (swap_form): certain at 5/5, a roll below
            -- luacheck: push read globals resetResource (the belief's verb, Families/Now.lua: a `now` only)
            resetResource("rage", f >= 5 and FUROR_RAGE or 0, f > 0 and f < 5 and FUROR_RAGE or 0)
            -- luacheck: pop
            applyBuff("bear_form")
        end,

        handler = function()
            swap_form("bear_form")
        end,
    },

    berserk = {
        id = 417141,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        known = knows(BERSERK),
        toggle = "cooldowns",
        -- "Requires Cat Form, Bear Form, Dire Bear Form" (DB2 text): whichever is up.
        form = function()
            if buff.bear_form.up then
                return "bear_form"
            end
            return "cat_form"
        end,

        now = function()
            applyBuff("berserk")
            setCooldown("primal_bite", 0) -- Berserk removes Primal Bite's cooldown (DB2 text)
        end,

        handler = function()
            applyBuff("berserk")
            setCooldown("primal_bite", 0)
        end,
    },

    cat_form = {
        id = 768,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.55 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(CAT_FORM),
        nobuff = "cat_form",

        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            spend(energy.current * (5 - talent.furor.rank) / 5, "energy") -- Furor (swap_form)
            applyBuff("cat_form")
        end,

        handler = function()
            swap_form("cat_form")
        end,
    },

    challenging_roar = {
        id = 5209,
        expects = "debuff", -- no damage (DB2, wowsims): its ticket takes its own avoid only
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        spend = 15,
        spendType = "rage",

        startsCombat = true,
        known = knows(CHALLENGING_ROAR),
        form = "bear_form",

        now = function()
            applyDebuff("target", "challenging_roar")
        end,

        handler = function()
            applyDebuff("target", "challenging_roar")
        end,
    },

    claw = {
        id = 1082,
        copy = rest(CLAW),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 45 - talent.ferocity.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims claw.go; DB2 Discount Power On Miss
        known = knows(CLAW),
        form = "cat_form",

        handler = function()
            gain(1, "combo_points")
        end,
    },

    cower = {
        id = 8998,
        copy = rest(COWER),
        cast = 0,
        cooldown = 10,
        gcd = "totem",

        spend = 20,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims cower.go; DB2 Discount Power On Miss
        known = knows(COWER),
        form = "cat_form",
    },

    dash = {
        id = 1850,
        copy = rest(DASH),
        cast = 0,
        cooldown = 300,
        gcd = "off",

        startsCombat = false,
        known = knows(DASH),
        form = "cat_form",

        now = function()
            applyBuff("dash")
        end,

        handler = function()
            applyBuff("dash")
        end,
    },

    demoralizing_roar = {
        id = 99,
        -- it deals no damage, so its ticket pays its own avoid only, never a Maul's wound in its frame
        expects = "debuff",
        copy = rest(DEMORALIZING_ROAR),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows(DEMORALIZING_ROAR),
        form = "bear_form",

        now = function()
            applyDebuff("target", "demoralizing_roar")
        end,

        handler = function()
            applyDebuff("target", "demoralizing_roar")
        end,
    },

    -- 10 rage now (DB2 effect 30 base 100), then 2 a second for 10 s from its aura (the rage resource's entry).
    enrage = {
        id = 5229,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        startsCombat = false,
        known = knows(ENRAGE),
        form = "bear_form",

        now = function()
            gain(buff.wolfshead_helm.up and 15 or 10, "rage")
            applyBuff("enrage")
        end,

        handler = function()
            gain(buff.wolfshead_helm.up and 15 or 10, "rage")
            applyBuff("enrage")
        end,
    },

    entangling_roots = {
        id = 339,
        copy = rest(ROOTS),
        cast = function()
            return buff.natures_swiftness.up and 0 or 1.5
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(ROOTS_COST, ROOTS) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(ROOTS),
        nobuff = "feral_form",

        now = function()
            removeBuff("natures_swiftness")
            applyDebuff("target", "entangling_roots", ROOTS_DURATION[knownRank(ROOTS)] or 12)
        end,

        handler = function()
            removeBuff("natures_swiftness")
            applyDebuff("target", "entangling_roots")
        end,
    },

    faerie_fire = {
        id = 770,
        expects = "debuff", -- no damage (DB2, wowsims): its ticket takes its own avoid only
        copy = rest(FAERIE_FIRE),
        cast = 0,
        -- Free with a 6 s cooldown in Cat or Bear Form (TDF Bear.lua; checkpoint Q7 confirms).
        cooldown = function()
            return (buff.cat_form.up or buff.bear_form.up) and 6 or 0 -- not the `feral_form` alias: no belief read
        end,
        -- 1 s in Cat Form: the Cat Form passive's GCD mod (wowsims pin spells_auto_gen.go:2014, 3025 effect 4: -500 ms
        -- on this mask); the Bear Form passives (1178, 9635) carry none, so Bear keeps the spell GCD.
        gcd = function()
            return buff.cat_form.up and "totem" or "spell"
        end,

        spend = function()
            if buff.cat_form.up or buff.bear_form.up then
                return 0
            end
            return byRank(FAERIE_FIRE_COST, FAERIE_FIRE)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(FAERIE_FIRE),

        now = function()
            applyDebuff("target", "faerie_fire")
        end,

        handler = function()
            applyDebuff("target", "faerie_fire")
        end,
    },

    feral_charge = {
        id = 1238122,
        copy = { 16979 },
        cast = 0,
        cooldown = 15,
        gcd = "off",

        -- 5 in Bear Form only: the DB2 stance mask (0x91) holds Cat Form too, where a usable answer pinned the floor at
        -- 5 out of combat with the client's bar at 0 (owner 2026-11-12; the poll repeats it every pass). A cost of 0
        -- is no rage rung, and a Cat-Form charge spends no rage.
        spend = function()
            return buff.bear_form.up and 5 or 0
        end,
        spendType = "rage",

        startsCombat = true,
        known = knows(FERAL_CHARGE),
        form = "bear_form",

        now = function()
            applyDebuff("target", "feral_charge_effect")
        end,

        handler = function()
            applyDebuff("target", "feral_charge_effect")
        end,
    },

    -- Bite converts all the energy left after its cost (DB2 22568 text), Clearcasting's free Bite too.
    ferocious_bite = {
        id = 1328618, -- hotfix 113554: rank 1 at 24 (22568 now rank 2)
        copy = rest(FEROCIOUS_BITE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 35,
        spendType = "energy",
        -- max_energy=1's cap: Bite converts all the energy it has, uncapped (wowsims ferocious_bite.go
        -- `extra := CurrentEnergy()`), so the core's cost-plus-cap clamp at the pool's max means full energy
        excess_cap = function()
            return energy.max
        end,

        startsCombat = true,
        -- wowsims e4ef929e54 ferocious_bite.go refundOnMiss: 80% of the 35 base energy back on an avoid
        refundOnAvoid = true,
        known = knows(FEROCIOUS_BITE),
        form = "cat_form",

        usable = function()
            return combo_points.current > 0, "requires combo points"
        end,

        -- Predatory Discipline (hotfix 113554, wowsims ferocious_bite.go): the extra energy stays
        -- shortcut: wowsims spends the extra energy on a landed bite only; spent here at the cast, an avoided bite's
        -- extra stays spent in the belief until the next energy answer. `onLand` would idle it on live (target rows
        -- secret); upgrade once a landed hit is heard on live.
        now = function()
            if not talent.predatory_discipline.enabled then
                spend(energy.current, "energy")
            end
        end,

        handler = function()
            spend(combo_points.current, "combo_points")
            if not talent.predatory_discipline.enabled then
                spend(energy.lo, "energy") -- the sim's floor (border batch 2)
            end
        end,
    },

    -- Its rage drain is unmodelled: health is secret, and the drain stops at full health.
    frenzied_regeneration = {
        id = 22842,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        startsCombat = false,
        known = knows(FRENZIED_REGENERATION),
        toggle = "defensives",
        form = "bear_form",

        now = function()
            applyBuff("frenzied_regeneration")
        end,

        handler = function()
            applyBuff("frenzied_regeneration")
        end,
    },

    gift_of_the_wild = {
        id = 21849,
        copy = rest(GIFT_OF_THE_WILD),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(GIFT_OF_THE_WILD_COST, GIFT_OF_THE_WILD)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(GIFT_OF_THE_WILD),
        nobuff = "feral_form",

        now = function()
            applyBuff("gift_of_the_wild")
        end,

        handler = function()
            applyBuff("gift_of_the_wild")
        end,
    },

    growl = {
        id = 6795,
        expects = "debuff", -- no damage (DB2, wowsims): its ticket takes its own avoid only
        cast = 0,
        cooldown = 8,
        gcd = "off",

        startsCombat = true,
        known = knows(GROWL),
        form = "bear_form",

        now = function()
            applyDebuff("target", "growl")
        end,

        handler = function()
            applyDebuff("target", "growl")
        end,
    },

    -- No pack line: registered so a cast spends Clearcasting.
    healing_touch = {
        id = 5185,
        copy = rest(HEALING_TOUCH),
        cast = function()
            if buff.natures_swiftness.up then
                return 0
            end
            -- Naturalist 17069 effect 0: -0.1 s a rank on Healing Touch (and Wild Growth)
            return byRank(HEALING_TOUCH_CAST, HEALING_TOUCH) - 0.1 * talent.improved_healing_touch.rank
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            -- Tranquil Spirit 24968: -2% a rank on Healing Touch and Tranquility
            return byRank(HEALING_TOUCH_COST, HEALING_TOUCH) * (1 - 0.02 * talent.tranquil_spirit.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(HEALING_TOUCH),
        nobuff = "feral_form",

        now = function()
            removeBuff("natures_swiftness")
        end,

        handler = function()
            removeBuff("natures_swiftness")
        end,
    },

    hurricane = {
        id = 16914,
        copy = rest(HURRICANE),
        cast = 10,
        channeled = true,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(HURRICANE_COST, HURRICANE) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(HURRICANE),
        nobuff = "feral_form",
        aura = "hurricane",

        now = function()
            applyDebuff("target", "hurricane")
        end,

        start = function()
            applyDebuff("target", "hurricane")
        end,
    },

    innervate = {
        id = 29166,
        cast = 0,
        cooldown = 360,
        gcd = "spell",

        spend = function()
            return 0.05
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(INNERVATE),
        toggle = "cooldowns",

        -- From any other form: the client leaves it to cast (Classic's handler, swap_form( "" )); the Feral priority
        -- shifts back after it.
        -- wowsims/forever: castable in Moonkin Form; UNMEASURED on Forever (checkpoint in layout.md)
        now = function()
            for i = 1, #FORMS do
                if FORMS[i] ~= "moonkin_form" then
                    removeBuff(FORMS[i])
                end
            end
            removeBuff("maul")
            applyBuff("innervate")
        end,

        handler = function()
            for i = 1, #FORMS do
                if FORMS[i] ~= "moonkin_form" then
                    removeBuff(FORMS[i])
                end
            end
            removeBuff("maul")
            applyBuff("innervate")
        end,
    },

    insect_swarm = {
        id = 5570,
        expects = "ticks",
        school = "nature", -- its debuff dot aura: 2 s ticks over its duration (talent and gear)
        copy = rest(INSECT_SWARM),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(INSECT_SWARM_COST, INSECT_SWARM) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(INSECT_SWARM),
        nobuff = "feral_form",

        now = function()
            applyDebuff("target", "insect_swarm") -- the aura's own duration (talent and gear)
        end,

        handler = function()
            applyDebuff("target", "insect_swarm")
        end,
    },

    lacerate = {
        id = 1328617,
        copy = rest(LACERATE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        -- Shredding Attacks: -1 rage a rank, wowsims's (its log: Cost = 13 at 2/3); the DB2 text's ${$m2/-10} reads 6
        -- (m2 = -60; checkpoint Q12)
        spend = function()
            return max(0, 15 - talent.improved_shred.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims lacerate.go; DB2 Discount Power On Miss
        onCrit = primalFuryOnCrit(),
        known = knows(LACERATE),
        form = "bear_form",

        now = function()
            applyDebuff("target", "lacerate", 15, min(5, debuff.lacerate.stack + 1))
        end,

        handler = function()
            applyDebuff("target", "lacerate", 15, min(5, debuff.lacerate.stack + 1))
        end,
    },

    mark_of_the_wild = {
        id = 1126,
        copy = rest(MARK_OF_THE_WILD),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(MARK_OF_THE_WILD_COST, MARK_OF_THE_WILD)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(MARK_OF_THE_WILD),
        nobuff = "feral_form",

        now = function()
            applyBuff("mark_of_the_wild")
        end,

        handler = function()
            applyBuff("mark_of_the_wild")
        end,
    },

    maul = {
        id = 6807,
        copy = rest(MAUL),
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = function()
            return max(0, 15 - talent.ferocity.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims maul.go; DB2 Discount Power On Miss
        onCrit = primalFuryOnCrit(),
        -- The belief: paid at the main hand's next swing, which then brings no rage. Hekili's own simulation pays
        -- at the press (the Warrior's Heroic Strike alike), so the two differ by up to one swing.
        onNextSwing = true,
        known = knows(MAUL),
        form = "bear_form",

        usable = function()
            return not buff.maul.up, "Maul is already queued"
        end,

        handler = function()
            applyBuff("maul")
        end,
    },

    moonfire = {
        id = 8921,
        expects = "instant",
        school = "arcane", -- its debuff dot aura ticks every 3 s, 9 or 12 s by rank
        copy = rest(MOONFIRE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(MOONFIRE_COST, MOONFIRE) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(MOONFIRE),
        nobuff = "feral_form",

        now = function()
            local base = knownRank(MOONFIRE) > 1 and 12 or 9 -- rank 1 lasts 9 s
            applyDebuff("target", "moonfire", base + 3 * talent.natures_splendor.rank)
        end,

        handler = function()
            applyDebuff("target", "moonfire")
        end,
    },

    moonkin_form = {
        id = 24858,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.35 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(MOONKIN_FORM),
        nobuff = "moonkin_form",

        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            applyBuff("moonkin_form")
        end,

        handler = function()
            swap_form("moonkin_form")
        end,
    },

    natures_swiftness = {
        id = 17116,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = false,
        known = knows({ 17116 }),
        nobuff = "moonkin_form", -- the pin: the row bars it on Moonkin Form

        now = function()
            applyBuff("natures_swiftness")
        end,

        handler = function()
            applyBuff("natures_swiftness")
        end,
    },

    natures_grasp = {
        id = 16689,
        copy = rest(NATURES_GRASP),
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = function()
            return byRank(NATURES_GRASP_COST, NATURES_GRASP) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(NATURES_GRASP),
        nobuff = "feral_form",

        now = function()
            applyBuff("natures_grasp")
        end,

        handler = function()
            applyBuff("natures_grasp")
        end,
    },

    pounce = {
        id = 9005,
        copy = rest(POUNCE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 50,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims pounce.go; DB2 Discount Power On Miss
        known = knows(POUNCE),
        missable = "pounce_bleed",
        buff = "prowl",

        now = function()
            removeBuff("prowl")
            applyDebuff("target", "pounce", 2 + 0.5 * talent.brutal_impact.rank)
            applyDebuff("target", "pounce_bleed")
        end,

        handler = function()
            removeBuff("prowl")
            applyDebuff("target", "pounce")
            applyDebuff("target", "pounce_bleed")
            gain(1, "combo_points")
        end,
    },

    primal_bite = {
        id = 407995,
        copy = rest(PRIMAL_BITE),
        cast = 0,
        -- 6 s (DB2 category); Berserk (417141, DB2 text) "removes its cooldown": its `now` and handler end the running
        -- one and none starts while it is up (the belief evaluates this in its own context, Families/Casts.lua).
        cooldown = function()
            return buff.berserk.up and 0 or 6
        end,
        gcd = "spell",

        spend = function()
            return max(0, 20 - talent.ferocity.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims primal_bite.go; DB2 Discount Power On Miss
        onCrit = primalFuryOnCrit(),
        known = knows(PRIMAL_BITE),
        form = "bear_form",
    },

    prowl = {
        id = 5215,
        copy = rest(PROWL),
        cast = 0,
        cooldown = 10,
        gcd = "off",

        startsCombat = false,
        known = knows(PROWL),
        form = "cat_form",

        usable = function()
            return combat == 0, "cannot be in combat"
        end,

        now = function()
            applyBuff("prowl")
        end,

        handler = function()
            applyBuff("prowl")
        end,
    },

    rake = {
        id = 1822,
        copy = rest(RAKE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 40 - talent.ferocity.rank)
        end,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims rake.go; DB2 Discount Power On Miss
        known = knows(RAKE),
        -- a dodged, parried or missed cast leaves no debuff (core: Engine/Schema/Spec/Abilities.lua trackMisses)
        missable = true,
        form = "cat_form",

        now = function()
            applyDebuff("target", "rake")
        end,

        handler = function()
            applyDebuff("target", "rake")
            gain(1, "combo_points")
        end,
    },

    ravage = {
        id = 6785,
        copy = rest(RAVAGE),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 60,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims ravage.go; DB2 Discount Power On Miss
        known = knows(RAVAGE),
        buff = "prowl",

        now = function()
            removeBuff("prowl")
        end,

        handler = function()
            removeBuff("prowl")
            gain(1, "combo_points")
        end,
    },

    -- No pack line: registered so a cast spends Clearcasting.
    regrowth = {
        id = 8936,
        copy = rest(REGROWTH),
        cast = function()
            return buff.natures_swiftness.up and 0 or 2
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(REGROWTH_COST, REGROWTH)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(REGROWTH),
        nobuff = "feral_form",

        now = function()
            removeBuff("natures_swiftness")
        end,

        handler = function()
            removeBuff("natures_swiftness")
        end,
    },

    rejuvenation = {
        id = 774,
        copy = rest(REJUVENATION),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(REJUVENATION_COST, REJUVENATION)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(REJUVENATION),
        nobuff = "feral_form",
    },

    rip = {
        id = 1079,
        copy = rest(RIP),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = 30,
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims rip.go; DB2 Discount Power On Miss
        known = knows(RIP),
        missable = true,
        form = "cat_form",

        usable = function()
            return combo_points.current > 0, "requires combo points"
        end,

        now = function()
            applyDebuff("target", "rip")
        end,

        handler = function()
            applyDebuff("target", "rip")
            spend(combo_points.current, "combo_points")
        end,
    },

    -- Forever's Tiger's Fury replacement: 55% of base mana into 40 energy (DB2 1322605). No toggle: it is the core.
    shifting_power = {
        id = 1322605,
        cast = 0,
        -- spec D5; checkpoint Q4. 8 s by hotfix 113554 (wowsims 5508974417; Improved Shifting Power removed; the
        -- DB2 70707 base file still says 16). The Howling Idol's equip aura (1291059) takes 0.5 s off (DB2 1291059
        -- effect 1310233 -500 ms; wowsims sim/druid/item_idols.go and TestHowlingIdolShortensShiftingPower, both pins).
        cooldown = function()
            return buff.howling_idol.up and 7.5 or 8
        end,
        gcd = "totem",

        spend = function()
            return 0.55 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(SHIFTING_POWER),
        form = "cat_form",

        now = function()
            gain(SHIFTING_POWER_ENERGY + (buff.wolfshead_helm.up and 5 or 0), "energy")
        end,

        handler = function()
            gain(SHIFTING_POWER_ENERGY + (buff.wolfshead_helm.up and 5 or 0), "energy")
        end,
    },

    shred = {
        id = 5221,
        copy = rest(SHRED),
        cast = 0,
        cooldown = 0,
        gcd = "totem",

        spend = function()
            return max(0, 60 - 6 * talent.improved_shred.rank)
        end, -- Shredding Attacks
        spendType = "energy",

        startsCombat = true,
        refundOnAvoid = true, -- wowsims shred.go; DB2 Discount Power On Miss
        known = knows(SHRED),
        form = "cat_form",

        -- Shred needs us behind the target: the packs' Shred and Claw lines choose by `target.is_targeting_player`,
        -- `settings.behind` and Shredding Attacks (tools/wowsims/specs/druid_feral.lua, L602)
        handler = function()
            gain(1, "combo_points")
        end,
    },

    starfire = {
        id = 2912,
        expects = "instant",
        school = "arcane",
        copy = rest(STARFIRE),
        -- 3.5 s less Improved Starfire (0.1 a rank) and the Eclipse cut, then Nature's Grace's 10 % cast speed
        cast = function()
            local t = 3.5 - 0.1 * talent.improved_starfire.rank
            if buff.eclipse.up then
                t = t - (ECLIPSE_CUT[talent.eclipse.rank] or 0)
            end
            if buff.natures_grace.up then
                t = t / 1.1
            end
            return t
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(STARFIRE_COST, STARFIRE) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(STARFIRE),
        nobuff = "feral_form",

        -- Every Starfire cast spends an Eclipse charge, a missed one too (wowsims talents_balance.go applyEclipse); the
        -- belief at the cast with `removeStack` (aura audit C4).
        now = function()
            if buff.eclipse.up then
                removeStack("eclipse")
            end
        end,

        handler = function()
            if buff.eclipse.up then
                removeStack("eclipse")
            end
        end,
    },

    swipe_bear = {
        id = 779,
        copy = rest(SWIPE),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return max(0, 20 - talent.ferocity.rank)
        end,
        spendType = "rage",

        startsCombat = true,
        known = knows(SWIPE),
        form = "bear_form",
        onCrit = primalFuryOnCrit(),
    },

    thorns = {
        id = 467,
        copy = rest(THORNS),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(THORNS_COST, THORNS) * moonglow(talent.moonglow.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(THORNS),
        nobuff = "feral_form",

        now = function()
            applyBuff("thorns")
        end,

        handler = function()
            applyBuff("thorns")
        end,
    },

    travel_form = {
        id = 783,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 0.20 * (1 - 0.1 * talent.natural_shapeshifter.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(TRAVEL_FORM),
        nobuff = "travel_form",

        now = function()
            for i = 1, #FORMS do
                removeBuff(FORMS[i])
            end
            removeBuff("maul")
            applyBuff("travel_form")
        end,

        handler = function()
            swap_form("travel_form")
        end,
    },

    -- Swiftmend (consumes a Rejuvenation or Regrowth: no HoT aura in the pack, so only the press is modelled).
    swiftmend = {
        id = 18562,
        cast = 0,
        cooldown = 15,
        gcd = "spell",

        spend = 0.2,
        spendType = "mana",

        startsCombat = false,
        known = knows(SWIFTMEND),
        nobuff = "feral_form",
    },

    wild_growth = {
        id = 408120,
        copy = rest(WILD_GROWTH),
        cast = function()
            return 3 - 0.1 * talent.improved_healing_touch.rank -- Naturalist's mask holds Wild Growth
        end,
        cooldown = 6,
        gcd = "spell",

        spend = function()
            return byRank(WILD_GROWTH_COST, WILD_GROWTH)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(WILD_GROWTH),
        nobuff = "feral_form",
    },

    tranquility = {
        id = 740,
        copy = rest(TRANQUILITY),
        cast = 10,
        channeled = true,
        cooldown = function()
            return 300 * (1 - 0.3 * talent.improved_tranquility.rank) -- Improved Tranquility 17123 effect 1: -30 / -60%
        end,
        gcd = "spell",

        spend = function()
            return byRank(TRANQUILITY_COST, TRANQUILITY) * (1 - 0.02 * talent.tranquil_spirit.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(TRANQUILITY),
        nobuff = "feral_form",
    },

    rebirth = {
        id = 20484,
        copy = rest(REBIRTH),
        cast = function()
            return buff.natures_swiftness.up and 0 or 2
        end,
        cooldown = 1800,
        gcd = "spell",

        spend = 0.85,
        spendType = "mana",

        startsCombat = false,
        known = knows(REBIRTH),
        nobuff = "feral_form",

        now = function()
            removeBuff("natures_swiftness")
        end,

        handler = function()
            removeBuff("natures_swiftness")
        end,
    },

    hibernate = {
        id = 2637,
        copy = rest(HIBERNATE),
        cast = function()
            return buff.natures_swiftness.up and 0 or 1.5
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(HIBERNATE_COST, HIBERNATE)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(HIBERNATE),
        nobuff = "feral_form",

        now = function()
            removeBuff("natures_swiftness")
        end,

        handler = function()
            removeBuff("natures_swiftness")
        end,
    },

    soothe_animal = {
        id = 2908,
        copy = rest(SOOTHE_ANIMAL),
        cast = function()
            return buff.natures_swiftness.up and 0 or 1.5
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(SOOTHE_ANIMAL_COST, SOOTHE_ANIMAL)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(SOOTHE_ANIMAL),
        nobuff = "feral_form",

        now = function()
            removeBuff("natures_swiftness")
        end,

        handler = function()
            removeBuff("natures_swiftness")
        end,
    },

    abolish_poison = {
        id = 2893,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 0.16,
        spendType = "mana",

        startsCombat = false,
        known = knows(ABOLISH_POISON),
        nobuff = "feral_form",
    },

    cure_poison = {
        id = 8946,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 0.16,
        spendType = "mana",

        startsCombat = false,
        known = knows(CURE_POISON),
        nobuff = "feral_form",
    },

    remove_curse = {
        id = 2782,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 0.1,
        spendType = "mana",

        startsCombat = false,
        known = knows(REMOVE_CURSE),
        nobuff = "feral_form",
    },

    revive = {
        id = 1237951,
        cast = 10,
        cooldown = 0,
        gcd = "off", -- the pin's row has no GCD

        spend = 0.75,
        spendType = "mana",

        startsCombat = false,
        known = knows(REVIVE),
        nobuff = "feral_form",
    },

    -- Cat Form's Feral Charge (the pin's 414924: 30 s, the spell GCD, no cost, Cat stance only); the Bear Form charge
    -- above spends 5 rage.
    feral_charge_cat = {
        id = 414924,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        startsCombat = true,
        known = knows(FERAL_CHARGE),
        form = "cat_form",
    },

    wrath = {
        id = 5176,
        expects = "travel",
        velocity = 20,
        school = "nature",
        copy = rest(WRATH),
        cast = function()
            if buff.natures_swiftness.up then
                return 0
            end
            local t = byRank(WRATH_CAST, WRATH) - 0.1 * talent.improved_wrath.rank
            if buff.natures_grace.up then
                t = t / 1.1
            end
            return t
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return byRank(WRATH_COST, WRATH)
                * moonglow(talent.moonglow.rank)
                * (1 - 0.5 * talent.improved_wrath.rank / 5)
        end,
        spendType = "mana",

        startsCombat = true,
        known = knows(WRATH),
        nobuff = "feral_form",

        -- Nature's Swiftness spent (the handler's), and Eclipse's charges (R §9 open: +1 or +2 a Wrath) while the
        -- talent is known.
        now = function()
            removeBuff("natures_swiftness")
            if talent.eclipse.rank > 0 then
                addStack("eclipse", nil, 2)
            end
        end,

        handler = function()
            removeBuff("natures_swiftness")
            if talent.eclipse.rank > 0 then
                addStack("eclipse", nil, 2)
            end
        end,
    },
})

-- The setting the packs' Shred and Claw lines read (TDF's name and default): Shred as if always behind the target, the
-- target attacking us or not (L603); Guardian's is below (its imported cat lists).
local behind = {
    type = "toggle",
    name = L["Always Behind"],
    desc = L["Hekili assumes you are always behind the target. Below 2 ranks of Shredding Attacks, Claw is still preferred unless Clearcasting makes Shred free."],
    width = "full",
}
spec:RegisterSetting("behind", false, behind, "feral", "balance")

-- The maintenance debuff (tools/wowsims/apl.lua rule 15; the recipe's `maintenance`): a raid's debuff, off in game
-- (open-world mobs die before it pays off), on under the harness (`sim`: wowsims's raid boss).
local roar = {
    type = "toggle",
    name = L["Maintain Demoralizing Roar"],
    desc = L["Keep Demoralizing Roar on the target, as a raid tank does, and recast it only when it is missing (that includes the levels before " .. "Lacerate). Off: the priority never shows it, and Berserk no longer waits for it."],
    width = "full",
    sim = true,
}
spec:RegisterSetting("maintain_demoralizing_roar", false, roar, "guardian")

-- The settings the imported lists read (APLs/packs.lua: Guardian's lists in Feral's pack for Bear Form, Feral's in
-- Guardian's for Cat Form), on the importing spec's page too, below its own under a section. Each spec keeps its own
-- value: `settings.x` reads the active spec's (sharing the other spec's would need a cross-spec read in the core).
local function imported(option, name, desc)
    local o = { section = { name = name, desc = desc } }
    for k, v in pairs(option) do
        o[k] = v
    end
    return o
end
spec:RegisterSetting(
    "maintain_demoralizing_roar",
    false,
    imported(
        roar,
        L["Bear Form (Guardian)"],
        L["These settings come from the Guardian priority. They apply only while you are in Bear Form."]
    ),
    "feral"
)
spec:RegisterSetting(
    "behind",
    false,
    imported(
        behind,
        L["Cat Form (Feral)"],
        L["These settings come from the Feral priority. They apply only while you are in Cat Form."]
    ),
    "guardian"
)

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc (a wowsims.com
-- pack's from its recipe, `make wowsims-packs`); edit those and run it, never these blocks
-- (tests/Forever/druid_spec.lua checks they match). Your talents pick one (the selector); /hekili priority <name> keeps another. Restoration is deferred.
spec:RegisterPack(
    "Feral (wowsims.com)",
    20261117003,
    [[Hekili:S31wVnUUr4Fl(fxRUPoYxZMfXbOflAXw0UOOE7RwrXIownYsgsYjilmYV9dPUzkjEtxSTKnF4CwhDHCMHZLpoZiPfdw8RfZn09bl(5q1HthmyWDQQJwm3)JTGfZ3QV8v9xG)WwFd8))3bU6wF(uV3DE3ZCJx)LoBuqx0hwo6gOb65DMw()WEXZehtVTGLlM)9)7)7hF)BRqd1I5RnnmaHxpWBj5z4BF(K)AWNpfDSBx54cEd4(5tgGv67S8)8P)6)5F95tWd)5tX3)oZBrZM3TgU7mnUny2wQ7FR(wlVB1n036B(gOp8V6))9CSvUbofU62EwqI2a(Bh0uA695t6ggo2)j4pEf8Hx)pF676(6FJaP07F)JFbhK1((B9(2T3(IP)6DpJO(BZCPkWXesXGXGv3p8EWKX3DpCy)XMToU(WP5FSt31Wu3oJiaEtErsHNb6W5ZY0Z3doHaBFGlIKFFTPf6S7wTQp6s0GZ3M(722hU(46ScEYfZ1x6B6y7nBPULLw4FOHgOBqRUZq31nMRMLBi(8FgDJFz2TVP7AQ)Sfi8wEtZBT5kFt7x0268oWvZfOB8XnB35cMn4M30T2bM1RxpFDliD2FRR5gDlTv7C)Opuy)6JZg2Tt8jn3ajZ3agWreYpbNFMQIs3E96eo79HlFHu0R2oVBVpGmto2UTOlLYentTlWg4(Yh9TCEy2Krk771H(1QK6Ir0qebKMx7hWRkWXIf)XK7olmhC9iy0nnCS0CwPbvQ0mG8cAAOply8sgXaWgPpyOWHvtgxa0XGJ7hAgMEln3AzAdIhcEtaoBoej3tXhqtCNLM(F0QyJWvRw6cY(25cqo7B(w4DQKpS9cimAsU)KEiAqSH0dXPNStVcmHVhcfwqKw5SZfE5M2(ApB6d0chBntpipBBamYcxIJTzNqlFliaTL6EiAjuCESeOvxE2LMsaMC(Xztv56OTfWf3H0wIu7jTgjTJpHKDQvMjQspPNCYo1kW4apPm2W0bZukee2GDVk7bIhOmQEsXMJbQQ0SLZXwmJay(gqgbGRVZjxgrauzhbOfYDzJB1w8(qq5Q1ZhJcby0ontATaG4Pj1kzKXb5(OArKLrJA2CbROr59QCKXtnLkCQ2V6cucEbOUe7sGfA2Lw6VRPQ9SLJJH2kxG9V)qBJPXkZxwhHVfcS9Dhx)1b1Kkx1GkPVMJQiq8SSU0zZZoHG596VCNlK)9HolomcUMBJUzdqWTJoGlyJUPTh0eqHD2xpJIarg8QkNglQCAiAnHHyQhh)r775BUb8LqLYOrv5XPbzJplb0LebmoWoOBdvDLVV27fzRRtvvAU6JX(D6ZpfQ77rZSeFq4SlCUo(cyDPNpPNVYiNe2Z3iPNVRDpFxTza8YVgq4BWK7EUyAN3mtgEy1spnXJd2iYW0HJ5HuqMQ9lidTPYIT2CiBzXwp3KTSyRuJkilaRi(tVms59uzbyRdgQo8iXRSzTr(qwa2IYr19kGSaSyuKmAuZMlyfnkVxLJmglzbyB6CHWfGDOSmeYYquC5KSme1ZAfFFTT)YqGLR2YKQvHscCz2ToxhKfXzy5e8k54bXllCfdZJnXbNPEMzSWJcYWIhaIzCzEcAQp8KciRQ2dEzzj5JRrzf9)lJtkMCsgNSEwRUYItwlXefk(h7iGBDGeA09b10dgNmH(yxDMYjNRJeKWQ4lngQQ1KUPwBPSkT)mzOBzOBXKtnLEmUtf2lrf3mH0urAQiICQPGYTtv29BL2(R0srAPiICQjAPu081itytnQDwrfpPbQyYPwTbktJrbkgyMGGB1nn0qVkwnaUARm99c2VAu6aqPgiFQaK2osBh(YPlHDmrplsd23mnds3X7nuf1mjRLfkaskHpmMDW)wA)PqLvBNnQcr2ze3SrtCNAYGuYGufrojCqQMiaVcNRczuQJorkJsjJsHhLIuwsKbPKbPkICQvhKQOPjugJ6OtKYyuYyu4XOkA8OYAfYT)w5simk22m(fcGBxUwL5NBXe41RRIm5TWcOGhlGudKj93F0jsP)(Rp)9P94Vsh4AcGEvCbOpgB9IrZHD80O6Wpre6UhcAyHyGOqw9DRiOOHDJB4rGKfe)xWbO91EZv)n9xIOdsdx6rd6FW5LxGUp2aLTBGmiuA5(cWVVZoFptdWK9r)97M(RnTNWD6JbChqaDYIbV2NUWfmNDEHTlBaxl(gcsbf)HzdOSdHH1VycyTZg4PzHiGB25bGkFR0EzPbegaIhIya8RksdQUjeYFxb9G2jwaTWXkHIEliG5gtaCVidQxkP)WOjZtB9hp7AAmlT5kIgsHVa)KHFcdPpwbwfVcUzLZYDEZgM22GRssVoX7fdog9dFUBP504C2UZP1MFe53TD2iXzyesFnTAiI8wBNANwcpnvansMpM2qapVP7dkOTZsiKud4P6Nma9dSvJCfeaJY83qMdjX2OBRdHu9WGXQQDd(JTl91GhyYeLUXNSxks)ppbkqGUnXIIEaB2dZgP2L8ZYsA(F2GjmyFnKdSuBMOo9nLF0pLERAWkPe9cCjWjJzBTruH460(lyHOEm2cgQtPL15lOKehWjxKFPJdi265AYn0OACdjzhRtPJOgS(31siEcl)xZws1lGA(JE9BT1gcc1AECNLawK6kLKUBlkgCaAjKlSRZigvElGJoFBbSbRqE9H86AClmOkTmlPCligMvfyqhnSIAWL4LRrYT8vMktnEYD3pR7(Q3RM2ORDnq3YFnI1Fy2u181lQxMb7q5pXPHOvKe5FQZfSeOOKTut5il2LBlAwfPABNqAoWZVj0KXf8cstqhD2mY1HtoRKiW2vNKwss9ldoFKSmJYDVKYKh5vbva3yXEhAN6abJFQi6L19fqiqljcxWshp)WwG94rqw6lrRGuOMKZgskkeQ38jCvnB7meppfUBgoJ8qSenDG(icorCd9FM9qE(6lHX1G(PZEMewB05L1maBCG3M5VrbdDD0DX5rpGpkYGxFeT6d)pTCxoQpL7elkYDw8vWtkFMNrXmOW8stW480rK5OrV3n3c0q)bXUKyyxd3DOgp0caDKhE2tQuvmdJZi9SrFNvMaiHuwyGKihLqjPklNW09CtX9CiCPb9NOW4EJN9)s0vGO1qx0pssBmY59zD5LQ4myHMQam94ObXJJ6ekD)IHE8W9HqcY(otY(bCZeojW57ghyCGQcJXMeUJdx(bQNCZnLE4qKhd(cFAd6AocODY0HEm7Zj8XZq3BD(HJ1DNQVSMTkxZVj27NckJhYDw53OD2HkpXvODBr5jAsGnmUhBBtO9BLUj)(QclUhoSPC)uasM0UZs)S6qQ)SHEl6LeZ(za0O2yFNiJC4Aw4VcK5w6FaCp887qyd1qNK7jsfmyzxZTLnxiuETOoM5djLin7oTKOTNIwX(o949Ox19aJfE8qUk1HcDXMDd19(6xgGHJh)U7LOO9fO7QhtakhEnOObFj6iONIRyO97zsPyek6PyinDgCeHitS7LgvgCj0iYGhZmShbT8jA4Rm1QQXuSLlZP8SFl28XtXbRt)ZT8I)mNW)5l5mBPJwVlRVnMAS5LqjQwftaHQ7tVd7cpdvL3aeD9cZcKTG7KzfPl9fK90fcpmKCY5uOmTmKyidpwNMFafPkGufGUkW1q6Vxm)nGRhKTw8ZHQdNoyWG7uvhTyoAhaEl(1I5PekWd8ZbOJgHZyXFBX8qPYI5PXWUy(sx4)aL9WzqiG2l8HKaLXonkhkJnji3ObDuHjyQR11n6BEWVrK)4mKpozwa6S(GCxPiXucfJVudVC4IdYZlszdkbMWqciUaOKyWReiCQOWlpm8kIdVSaXlds8kbf)iIf)GYg8ssu1gIu1MwpQACXLJrcWljnnChvNGbwgLJK4PSDuHUFu8yaLuFTECnEQGRXeVgraB0rSjkKTIHzRgbTDKrTDWSaDBPJxCVuTqQwKxTyGkfhRjW0lRZ12dGFOCWFXCu(YzbLpjF64cK8PApbXowA5rdk2nLPyoPaFNuWgCAGbE942LbF8R12MHt5KYwpPeW50z)O5Q2BwMIsPjYqCkjJyplk7KvksTwdL1Gk3InfLXIHSrFj4i2Enc2oleUr(nytz7WgbPPmTyZXUhBk6Y6b91GvTmAQ0aiJ1BnK0aoX9Ktr5zc4zJzS4LJ0XNAinOtr5Zu71jluTyooxR2GZ6nQ(2PGSFg(NkMemRxcbuQ7(6PGmraLtd8WHU8jNr4XUBFkdBqlLJeT5oPuxAfLSOIWOkb77Nk14pnTo)PScZb5XkeVIJO7arn9mUsv4ITyXB89rE3wb)nXSPFyUYd3(WEBY0QoHPRxd1WorG7zKl949qf8RO7HsYZNJEzlgWdbVUfd2)mJSHY7L3x3ISNkwVV9WZA(OqSsuVyLuxnIkIiHmjTnrZrKhGdUzS9uYFzFUAAnpGAP4ZHbI(umYQ2YJvdH1Rw6sY(w7dnygRCbSZz)IwKNZmHkmuZYrO0rrtIpKokoh0D61Gj8DuOWkLKKXsX7JKpjCvCmCjNF3w6R(wSC8pvLVN4waBC3KWAKtDvsAKFkP7uRntuLoApd0DQ1GXboAzT5kUVhpWgT7v5ms8WUr1Hk2KmqvLQfDooJuFAXjgbkzyYyeI4CDYfsmcvoXiAHSxR9v6bb1RwpJmkces70sP1csIRUuRKtgRg1oLvjMTmMudNnygtIGRLJmMRP0HC1(vzgn5IqLj2XaRwgImK3c(HmNy1NkPROJQWPa5YTaF8jP(1NSH(vEQNidELfve)(tEC(u(Z4lqzX(eu2q1A57o(EH2b8uvLgSwjwhdZlTSqEGM9j(OWzJ7johZ(OKWR(7q2x6Du6DSkIkX9ow5ppVsVJxcEhVAZP41qDNW3Uk)9VX0CVPM99Wc4wZbUP1E5m2vtMVFU8qAitU)LMH4uzbGBs0TSaWNF6(QRaW0E6DkqCdzrHf1H7fsc4NklkCTWq1HdlUfYRnYiYIcxyoQUxcKffofjjJj1WzdMXKi4A5iJdtwu4MpBGxuyAps3Iddww2dzzpkIOsw2JAB9IV74lHYEGLv4YK(wXY3Cz2GFItuQVxii7fTOEml3IIso2t86vxvGcPEpVcptnn1yXxfKLfpwf7i78K17P(8LkG4I(nZLHvyHQ6SA1w1WeYiQclQKruRT1RRUiQ1t0tHIuQW(nreC4(J27Qz5gfgg8ZcxYK2dDastpL0JD2NInLULzsMKnSd5ND2oD6ZEngmbdY)aMnXg0XKsbzfj9jjl8hawj0bhjaiP89lQB)g0h9Jr62bzpILZ0FlP6tlwUniGhcXJq8TaI3EMKApdQ)W0cqqxg0LrBvL9KvSNjfoBwLZOhd6XOTQYo9yABhFWw(0VgPMA)HUQARQCDxvPUL3j)S(v)3xvL85bCNeqVl07stv1WOAlXTIkilNsB0qGFA(TvZ1ADewAkdqMIlEurMco6m1iET6Mdxd46z2LEE3UtKsWk)qSmelRlQk9XYSZmfBDBqqWSRGuIGzJxWS2D0zc1ugeldXY6IQY1XYABdkrOSRGuIqzJxOS2DK41fyRU6KQC6DvkmY2oWLQ3HcLZWRrcGYD5q1K8Q1t3j3Chv0MmckCfKseuyuckuali6WaueL12DoRLLolrh83DSeAZNb58V6ug3SdtM3bIo6JsJotPHxi6rN7bX)CAYXJ1O4XM0JQijt0HRblhFozZRE6)9OGi61Bm3Gi50HIbkUQQQfLPWvEWILbcQBjSh1TH(AYG2AWI5Dsg0HDYdfnK3n5ctjKoBqFjXv4BZdKif7IxL)VLZVNHfF6WQ1)7TusAfz3mUSnGO(t2kIp8t11dxcuvVOc(6eG1pH8yvBfo1Jv)z0wkXsp1vptp48NEUGZ1gclfAZaQgHEBmpJblAhI2SNKvY5gSjU(ghLmVB5D6bQ5xHJcnPNnFqw7zk0FhTpIKa0IGh99Nq)WF(1XvKVy(87MW(Jt5wA3pNOVQXq)LzsTy5m)jWVsn86NLbucE(yoH4UIO4ZIKgbs6UmvtPpohN)ch00SBrzk3elSKlPyWOH)a)l0oNi6egIA8jR2zdXyp4R8sFk4ndL8PZYOMGX3rZL)NcURyBu344jeXutetPGL9dd1xbqMHCiPcKA1VkTic6vvR6bqGuPq8L3U3JoSwcil1O1bruDspAmBEm2u4a2172LCcMr4nqPJjwnEdELxCog9QxmiXOx3aLog9ASf9QERfhurVSylwSSNrVVhX7l60X1jepPFeVDZUnF960xssJphNMFb)87]]
)
spec:RegisterPack(
    "Balance (wowsims.com)",
    20261115000,
    [[Hekili:1sv3UTjmu4NLEtxqlccP021OMkTQQP1QTQPr3TgmWHGxm2iBtZQufp77ysdLqsw100UjY54Z3ph7pdXN8ajmJAaY9tNm9mFF)tNmzcj08ufqcROPlPlWfcAj(71uovKcnXJwjxPzLA3uzPJTTN4sAMLQKAg3CRGKSxw1vqkj8MV)JBVzwYAYiHfSSmyncqNEivM1eBkWIVuZlxQGhbvtCgKtR5MM4p(TV0eJLBIFLHAMNvtTxMQML59IME0kowAnqx8pU)ulfoJrjuuHMJgpdxlTsY0nX0SmP4D4ILWtA3M4BOg6S9yLrF92hqskmMk9mpVfmtrDI19EdA1b5eDmea5xm9c40GZVWfpgvYCghprOPgMuODRuacoHAMxkLILmreIVCmlF(rj155U9R6wx1C3oaF)CVvkQPWIXU5JqeiGsgOVmOR9)s2robETa0rC2IcZ4AnejZZJwKMn3VFxmHaupIhMwolPcQBvQjIlVmyYX5wOrkOKYe6RozsFCwHZzkyCUmTwpFARLYGotz3BGHqsaKB9kkob7bw)9haTOwPyPubS7z0vZd63P2qv98LVfWOrhzOCqyCHuoRsdUGGMWHSNB1DtX6kNJhnA)DE8wDIIKU8kFNNpATWUBu1f(fKwByIfoo9Dv79BZDKqmxPXAdEYXzAJU9r(64oU8(2h9VOo56n5nsy)BCsyQIzafJsc3BEGyqLgquVOGvLoI7NxS4o5agOlX0x93i5y5lyaF9S(U5MTNxBrsy7nQDEqYo9njBqAQV)FDJTj9SdmXDPV(6Stk0YW5h0whod(phc)JPWxNIn72nZ(wh)HdmZTjwInie29HQ)RXYTf(Gh0xg0Ak0w0AtHurc)mSKXz4h2)0lF3UDBYVd]]
)
spec:RegisterPack(
    "Guardian (wowsims.com)",
    20261117003,
    [[Hekili:S3XAVTQYXFl5lUMEoxhSDSppuCKA1vT6u1EvvZPF1eSzDmnyJfGtuoYk)27S7c4Db2DXg)aSxD15Qeyz259m7mdHXDh)ZXp6yhHg)h9m7nSB3UFX0S)4hJEFfA8JRSN(I9ZWpS0Eb8))7RTdCCTx(XtTFZ)Tq3fHDM6VWaVU398TDWWAYAxVOFSC8KcbB4k00Xp(7)N)7p(9V)Cm0g)4Cxhhe9rqHtfUpF)JNIMJ(4P4RD7m)a0ROGpEYbnZETx0hp9x(3)ZpEcU8hpXaI1U3I32WBDcw76C7muGT3eKDWT2R8cV12XEvK7ROoWV15)f6V04ZW2eyVm0dqFh4N9XBRB4hpz744V8pb)WlO3d78Xt)UDK93laDA)V(XpbGmpkAv43V92NDJMVEcMcUnZsnaycynAG93M60ZUNZSPay)XIv(brW283WyAgEa8eHXSHP4N1Znmke2m0YiuagDFBURhCZjRNnRdSclyRw0z9QoGqkWFgCVXpApnY1Fz4OP2EEw0FXcdNpJLYWvJ(S7SrzbWh)J4h7tJUfZ9ixhVW23qwA61G1A06gzporcynDUDWZOpVoez5pBM1ZtDg1LaVi81J64Vok01bnqbWMyh8s4lUljp6CKTx08oRMgD)OHMTAh5)8ZEOol8FfTa4qTYc7wTVHcPoS4uNxw6)2Ynt999CGFG)EbiBN3nm2edP3aHR7YbgkWsK36LOqGl)88Oci5yKGDvuKOgrcZcql)LlYXka9mAjap8nYY17nOgHXOLb2fQHLYVjliMtd3g2Nf2UldVFeO7KUQvbUlauzIBuYstjGC3Al(ZERy0x2Zrqep)7lybt9dJaAV9nhreYZEkwIkaBsVlfvWpyTripZgf4ISM5gG4KTmxpMj5GiWH9gBL31jskHD)5z(txhoQhLUAhJ)PcJ1RAL9sHrqa7hgb(mZENukTFDIsDql8bG4(l3LpBf4BhWrYHOOi4gHDWOEe8pRCRhWu4)Ij2C3Lv(EAjBf0nJTiR))cmSpH4SCuo8n3vilCu(TMzVISGiblCrHpmQxls6vwt8qqmc6DpT889XOQ2GElGeyZePIIOXrSI9id8ztzE7fRjjioaX(4HUDgyi5zt29FlEfyKLgl4HrcdyvNe(c5Uu1aH8tfG9v7axBqHNM48RwHZDNH9yzTY)nuGfbx)8Q1biy)E12Bnc7gpY2d4fj71S1bV3boTXlylOBsUP7ciz9xb7OW5qs9K7tDHLIQPyeLzLflXlvWgb52GtF753Xb4hnOpjZcHR1GBXyCigb4P1u5Iu6tk1DwioqEqGURJVhOCybhSYYbOf82iExyOLmSb0sS(GJHcsnfUi4mY(bVB54go1DLN7suciuTbSKzpmFNJoaBg)PUrV3OidQ0QHkq20mfa5SVvBHFtL8HTPemJ6K7pThIAezO9qC6rBEjWa1EimKLI0m)1bWYHZZrsZYIcBl3qGMx6GCYMUKcBZ40Z8GJLm1oeJlu25XIHwD(zlrkbm85hgn0uPJ2gav8fS2sSAFrYiTD8jeT5Kmdm1Esp5OnNe4oINujhyARzQaeIbyFZuoGuLuMqpPm7rxttr2Y5ilPraWLnshbqLVZbxgramLhbObsDzJB1u8(uGYvJNo6ttWOzAM0ytasLMuJKqUJu7JQfrwhnQEtfYIgL3RYroFQHctNQ5RU0FWLG6sIlbzzZo1Z(nltRjE((owKrK5DRfUoZWJWdn)wiX238dIMtgmRCDdAp91CuzbLVkRt9xmXNMmFyNPRda6pcCwSfcbURIF44E0JVqsxhhn0qE1xpJSGYa8QYNURS8PEyzIe2uBf(J20oYDb6tuLYyOA8Wqs14ZIaTkcbUZGo1p1t1v1(A)wzo66qtJ6R(yIFNoQlH6M2ImlzbIItHR0XhH01E(0E(2h(uP981x757A3Z3vBfaV87be7bmvEMlP251ZIHt7w6PjEm5Gi94dhRktbDP2VGm0gQB2A9bT1nB9CJ26MTkmQGUbSLXF6LrjVhQBa7HGGoeEKu12SMiDOBa7UsrhAjGUbSmyKoAu9MkKfnkVxLJCow6gWw3PIs3a2E62qOBdXUZN0TH4WiRu7RT53gcMA1UpLATufbEFoTUshK7IZW9JXBKJgkFBHRyyEMnMCNdZoZeESKeC5dajnUSkgTWxEYsWRQ2lE5(IYhxJYk6)xhNSC8jDCYdJS6klo5bjMyPI)jpc4kFarJFoqtN(NDh(qFY7oZ(XNpefirwZxQnyvJPCtn2wzT3(Z0HU1HUlhFQUmJX3uHZsuXdtOnv0MkLHpvxYY9MQC63kD8xTLI2sPm8P6OLYUwVgDbBoGANvuXtBGwo(uJ2avQXyjAgyMGGRSX)vPDTRNdkWAMBui58QXLdaxAG8LcqB7OTDuZNUeoXK4Qi1Dt90mGFI3RPkQzkwRSSaksj8(7Kh8VHoFkcj1M5GQui50xz1Ol8KA6Gu6Gu7cFQ0bPQJj4TZ1QqhL6OJK6Ou6OuSrPkQkj6Gu6Gu7cFQrhKAxltOog1rhj1XO0XOyJrTRXJ2xRqLZ3QsersZ2gPUrakNY1QS)kBMGQzDTmBEdSbkSXckAaY0(7p6iP2F)1N)Egp(4umhL9Z7zC6C7(x3ZKmrbA9nV4CrPJJl9kaEXTZq8Ma7xXF)y5)cXT9P5F48FT7Y8XUl7NSUS7wsc149l3xDUkdDk)3FDiD6xjFtblD69CjwF)OUcY3Vx1zcY)ojhJVL5ZK8oUVc)uyBfck2Eil6ZNGeSF4l7wTnhcNsVDO183Ne46mI3CcVLCX)zVj9tmOC4ruKFjZ39Ysl6BFtY5Lay0H(UXkYW(CosY86OpG9n2mh23mesrFXRQjS8g70uZZHhMlOtrMqUlHetE1ENDDM(vmnfaDi2SXFyrjP74(lGaXCTf2lTHuFUV7DMMTi)YQPrwWfgmWOvYnBZH()5batjZNU80COUFuFZwf)oNWZdg1vLxjlSZlUe)p0(PYVdNspx1yf2c9iCjqj3P2YRqLIRxBrIa5Wz4ra3P0k78fSsNFWjNLFnKFqIf01MlP(h4dTKfENsNs1yDXRPq)fOcCTBvD4t6w9oC4T8AcbNAmVcZ6ez06k7jE3uumkrcyLYn21B0JdYXe7F(oMynw586mJSR1J5aSxCRUSJgr6Zx(osX3brbpmW4CSdNZ)08RLRltJY3SUY96XjbMaour)bzbxL6OOWbRSe61ByKSyvc(Ut(vdvCba0XEX6sX6YJ2fPeXp2GfnQi4xh3queE9HDMGM7U0zZnX9eeKF0FIW79SFhfSDuclW2hCCSPqSqbzh4UAFDDl4Vst3jDMnlZS3ik()gbAhBUPTQjbT1wcJEDkvXDjIUDw3FJA)1p1LzmbyF62PkCFQRPXdPdHaDnt9dJ(u8vWdvk(3X(s3iftzqu8qvXJNKRuk0K5zfHLKLicjjt9kZeXM3N4xvQzDaZkixIFLXwE32tvkqmdGuoXm7OWPES3Qbw9yz)(6RtQ2BEUuQA2UXKWhFfBvxmwL3yeV(stcfBnFtgPslXcLnIzc33R4CkmeSTs4yggfP2T92QdWOvd0QbQvdUMYEFBM7IhTR01G5hzj7cafWcNayazfewifTsVgn(YHbqPrdGeN8tZnQvG9Zic3fpJYLCRqlXpLOZUW94JF8vuqiaHX)rpZEd72T7xmn7p(rmFlC8ph)iE1zl(cC9)Ol(MXi54)64hP4X4h5tXdE(aqpfuIHns(zpghbOGaGIZwGfucvLltkhxofI4IQseJFKeVcReaAc9fOjK6qAFvhAoU2a2qe1(l7mYCbB)j84LNEDYnxo9zP(2OLlPowO9GvcpyejH2b2rqNu7a7mW01oW2DdQMOdS(xnoWQXkT6taDTA(LwDJudpMIBGVcdVGVdTBzCKRWYstm3YcQKha3cx(1tXgzg)mVnQCYNyPZH5Tyn7RXQChh4xPvoCPqqYdr1VHJzFfhLPYMO(LxkXOyUFB5DIKdC9QEFnv4B0CLEnylc5hixrogn3Nx(1C7wkJHfAzmggku8Xxp1S44o(UXMh3Wa1cxKwQQcxvSPwD5T)zWZTytwjOmAiZMUDhKymLwVwE7jY2QOOWYSpkly3RseNALOYJzH8nAPKlYlyjEZT0zjvdsTqNL0EPo0eZsI3XPSSuegDSCJDMmBWkzylsCEycNxPzqt1qOjlBe6zg5W6DaTlspOe9gUGPrPsJJIG5rj1ESBAknf5z2D1(k12ZXrRsZJMWbsB)NiTkosA77mPTpdLwLMkTJ4yPX76xu6Qh0KaYvLmEC4lL3GV8iHk9RJ6aRDuCraCQVk6WfGwXE7zuQQ9bCuLKoRsfoSsINwPYoUs728kDahyPJ8elXhV4BA1cTArE1IUM686P517GMzV27Ov3JJD1oex0H2zQlurqHn)FifUPZXpsMQwjkN7j2bVe(I7sU9CoY2lAowkE)OHM5RvvwKARPalgKODLQlXDtActg5QZLa2KIIaM4DPmvb8uJ9vPOIKke5cEKcqpJTpSJ1xluw1BW5NytY2tIOkvwrkAwSukJVG2PRk(Cjy3Fjc0BeDlgcG9EX4V0hmP6GfScQRBs5HoI4KN9uS4vecLE7KJcC(f1sR(PWmzf16N9V3pNB(GK8ZsKAzYrlMIsLPqGTSxkmYEkCybWFF27Ks79Rb0o3X8eMoIdAHpSbU)cNZvGVnx9U2E2kmDfb)Zk36X1W4Me2wU7YQoCQ5jQzkIQUiJ3GIIKvGpMtkHvSIExH1Z8n3vilC(o5TQz78vVwobRXNzWdbr1O39ulZeqAIQQAXgXNBmMxjlB6DSyACKeG3BknoLynpbrWOjH3TZadzpCY()BXRybKOonkw6rGYhTTgOsS9Kwch9bmPqy)zRNl7bbeXyKluvVNIszm5mKKFk(imcALWJ4VdeeOt(sqqInjPCWQ(Uc0AxoHPSpfaS9qiUXCcxSb3QXyrmkKPQ1PI(Y0jpLLS(usFz7WAJ5VZoC0zVg8G2wG8QHksAUdIBgR8syNl)BaHkNzLQZy1lhHAhf1j6q7O4CG38YGbQDuqA7wxrDOS4KPM5VoG21B6uFexME3qGvS0b3sZ8jwPWYT4YD3wEczvGxxDwDP)yfP0vCdGm(Ya6uciukPTYpL4nNSzGP2t7zaV5Kb3r80k70vkFlZyG23mvajvjVj0HkZM010uOfDokJeKqujTfeKax3lDqIY4DDWfsqctfbjAGKxJD8Ulq9QXti9JZcPzAP0yZssPUuJKsUZmEIsRsqBDmPAozinMubUwoYjDnuCoxnFvM(dUiuzsCmqY5v0KnuCoVf9rax2litrnGAp9fDu5o7q5Cf(2ZKac8C7h)0mtYF6ino0qrDEpJCHYa8kZQUR0Sk8luSmgLQxbfCj(DxG(e3qLA8WqA1)ZIdTkcfiVRDKuBQJYl1(J)wPod8qtJASwjZqtRQWSaniY(Kfkko5EQ3XEIg4jr9GhOFT7rT7XQWQkV7X(A3JA3JTAF1wvXRHwpXEGv1NGtQ5EDTa80M4EOJClAQCLCUME8bUvLRHU((nxlX)F7DTSBQdde9BHnisxuX7vW2Q(vuAUvrIiAHQuUvQvv3V9RjeG4GFm(rbBYzzlVMzSN5mEooZirnajWHKCdsGV(YDRJe4HYEaima4aedtnI7nsr4NcIH9Ic5JiwAjZlgveqmSXAKVxcaXWCIeWKcC1qjMKGql)YjIbIHdF1OoXWdL90YsppyW8by(Wetfy(WBRx6JhFlW8rTcdBtbCPvYzBoH)POOYAltIJIAAet7wusot9OtzTRzkW18BzVIN(PRbWsuLPJvPgAxNT(hPpMPemxY)WAv4evPvDv9ADfMaiQKnvar1BRxToev)GEscPScRuwtZwmwPO(NPaqs1mgz3AGpkiJscHchXkAkWLs7zal3oeWdq8aI3ai(W52u3XHZF46bqGldCziBQcNSI74YbND7KZWJbEmKnvHPhJPv8bL8XVBsDD)hCvjBQIDxvLULvfkWSoJQOmm1owtexjb4DbVlIMQBJtBjVuud2LtziUrG)(8hQBxBuryLPmiAR4SXAYuisVunY114821iuFgDQM3M1xkfEYpGLbSmBmv0XYcZmfnUmiam7ciLamR9cMzw)ZuurzawgWYSXuf7yzMwGsaLDbKsaL1EHYmRT4zdSLToPAV9UAfgv0boxpdfAVdVojaAz5q3n5L0VEusUJUPhnafUasjafALGcjvZH8D5IoQAaZ)XILF9Ncw0MDtzqUGqIgt5hqq4LQ6JsqU4Q1FtvtZpfZO8I0vz2ok4715qsQSVK7f1PBWDt1nbpPXyTV0fjoVUQn0eHZalSDXVcESS3O5MJPLHn5MJTYEOIZxZGy)8SzWl9GyhhhSh)MUVmOz1myTebp)BM6UZg(w66ugA(SbJ73VB5F8(lBxW(htMK09Wl2JtzUBcZe1yg2FmTGzZh1VR4NpeElY8bt2JJWqss)72LByX)FmBv(R5)75EpSPi7ZSI9VHN()p]]
)

-- The hand-built lists the wowsims.com packs replace (wowsims packs plan, P9): a saved choice of one falls back to the
-- spec's default.
spec:RetirePacks({ "Feral", "Guardian", "Balance" })
