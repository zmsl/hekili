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
    20261115002,
    [[Hekili:S3vBpokYr4Fl(loMCtWVnEUBxTEKI0QeTNsIIYC5Rg3gAB3zWGfGNrELL)TNQbmdG5npGbA7sR2vZa0DxpvvD1v9qVnZgo7pM9IgXHo7FnAWONgoC4Kbdgn7fN9BPZEzlr9vYk4hmiBG)9VrTi6hN37DZ3TzBSLvn3iXFO96MenEhTyht35hgZwKyFAVLQo7LV)F(V)47FDjVRM9YAMMg175P2QjpcF94CN10JZ9Vw)LMw03OwhNRrxs2P7CC(F9F)poohU8X5NA)owF(Oz3xZAhtRV7OPsC6t2QB3NOr26WEJkd)M8)Z20q6byiSig26GqRb)SjFiz2hNt00mn(tWp8kDVT8X5FN4q(AcIsV)5p(dOtw74S1(R97VI5SE3cU03p2Jkb9jiX0hPl)YOVqN84V(fOB)XMTMwoWW833rS0yeJyQaOr2(AHfucmE6mBhByaPgoulUi)(AMo)U7wUuM)ikW4TrE3wzW(yzUeU5SxiQomtd7PQeDDfVFrH3rpWTUt5T6b2YPN1fh)D)g(lt7VKqTyuLLmlk)z71Z7wYHUU8RgMVB0vJ62rHVHfDdHzy)TPdK62RJFlbP7DDV2COJBt8UYUTssD7KPWyrEdCo9KJK6UO9w3EoMRwPtL3y(gDdO466qSwrDKn35yZ0Oto4)7VdgpMXKChEWFY9YUcG3JE6sWtw5dh4dBQYm3zRSG54J6ayhmWHqEiHrQ7s2Q1okbwGHDb3QfMkBnzgoGp2ollqeFE6OQxnr13zqTbhnqaEyNnvXC5sLvQAth6IbFae(P89GQAbjz3(rkEDJTI9AyM0hE1VrvOg0nmQ90rGSq0brqMTb8NEJQ59WYqmJxFEqx)BU1ITHORSCN1EV7aQZQxFMhmwVFHfttH3Dkl0nn1uwc22FU33J5mO1PeylJB2q4(AGYG22Kg4XfWpDC73pD8N0pDCPSGnVFACCFnqzRWp1MzadIpA9wA8SzJhId7kw4KJhvyQ9A2shqYGf8ENA5R8txBLPzasFbK3IV0BQd00bDbnG1Q9Y6MFB6KXsh6LQjKNZu4hMld(cquSbzzr02lb9vw4lt01iGdShU9otZuhsrqbs2vrdWIxUufalXududYcDQMuoqnOFPqblMw7v0y2QST6md6PUiVbimmhX17rWHxABo7fky4zTeudYbX0aC2878NH3PuXWouaLrBk8hgHOfbdmcr9l2rTatYpcHu6ze5sFYR0hwAQUdYilkjk5pNUJp9o8(WtTLHkn95)xBnwuApE(rXDUxuGK0SVwIkxyNBfvd)KuEtFygWKX3io0lCUJQPPUgCl5GoWB6QFbnUtXz)eahxJTHyq4t3h(4GbDD)LTQokWfGP)DpDZEre9)mK7q3vQAHOBnCCJXd8hivDO0jvInxzWhRO4F6Wjza)ZRAhRW6ssGQrahM)ulcgy(t1VyJvyHriehyGriQFXUkRW68CKQZAUAXk5eRL5wajpMDndj6qCFwfHRHalz4sYiOrahMqqlcgycb1VyJLmGriehyGriQFXUAkzWvQQZ6dsF6)1wHHVtMAxLlStTk47K50SN7PIPIVHcXQPUKKLAeWH5k1IGbMRu9l2y1uyecXbgyeI6xSlt1uXZiQolNQfRsVxEDljy(VNRha3Iwyfc14utC9)2fsUjw)hRqaJq0MHbgHO(f7QScH6ylAjcVqaHXNfF5rOVYNuUffhJCEPxfke29zDVUwcSi3ljh2gbCykSTiyGPWw)InwKlgHqCGbgHO(f7QPixxPQ6ROvi1O3FVfStw)7PIb4NgCtdos44aoRtjo(v9oyvbtS6AUE78dO0yNdDN16feRxTFLzWF21uIUZAo0)20NgC(zAxVyD2hNcUHLbFlsG(pY9oLrqSJdVZeRSp1v9h1ICORwJYSB9RmykJfDf3tGWVBm96OjnQisnSij5LeCm26EFFDzmN7EbNwY(rv4NJVNu7Ds7wFiWHVLV8Mv7CfeyMucpGQPTJxwLxpbsNOYTGPinb31tu4nSbTQXpvRpnox8HADdIHtA0Ol07lWbQBi(z8lz7quH11G40XVta0s685SgHMgDJj0m2p5lgAzsScJrBQdFLbBzUS6a)v5Shhen4p(O7S7g2cwR48CGgAcvOO0jm5S(eYZKr73zBPkNoS4JD0UYtpY9e3xbsvbcK7D3AvRwSjgnO8SHStp2ciEsM3cj(bkbn5GSccNEK7ucp7LU0q5jsz02tJ(FX)j4YQxi6NtYB0p4DJAEtvD6AOtvbgTFuG8X5hi(eNll7XpAhptWSBzW7WbkMWmiD(UNwyC4aPm67KY74Jh)dPp9pTdF0DCXldCfEy3Y)4jKq2oX(qnK5zXC4(tJyV(8UlRwh54KEQxnAX(giKkrs5ukwVpDBlFvCDtR0ZqzqvGk0s6t4qOjBwST(n(uv8WfcQC6jPS5HRbvbfPZlRE6XIQN4Nr8zPM6Ld9Rh65W2q)Li1Tk98tU8Ygxa6MKa4wIVR)AB0w1l5Y0dkL)5PFzWjE4Y4H46JwR)yV84RozDqgrykjrsxv4g1QK3lFqaqXVoX13kvBuKob52(6k2rSmtgGVDHAxSJybE09TlKXMii38OIhPpJokVxuzrwnz4GISCIhSo0l1CKUxJOp52iI(GSJOlGOtyFZAN7Cj84y8eP831fLqElV4EboscZYP55jjKa5r393t5wHfxnQDJISwn68Okx58JEk10JeF3LXtUfCxccjKFCHc4q8zdRCvrBzjNdjXSy6PctI5yKetKeZ70sEV9jXmCgv5MKrMZZBNS5mbzZ5En)zb1gHS50EWbYMZLIOQ2cGS5GS5imOazZPMu03xS5ecoPgy4Zgu5QI1YYrbYLtX0tixovJTk)GQixocB02BdUCEc3qAThXg3qAnTyJBinKctbhfpHuywfaQkIMKhXtIioqkmVuev1waKctKctHbfzTAesHzfQOVnPWmDaLxKHupP5kGVu5oL6(SI8vvhxwkbrQtlMEcPoTASv5hmhPovyJYFBqDk()L3wKyJuN20InsDksDQGJcC3FwjaQkIMKhHxIioqQtVuev1waK6uK6uHbf4U)SMu03IuNkLYbxi)CtnYGGFxIYnkzTdUBG1AXV6iTcKi(CjGFxIWieTCyGriQFXoQf4Y(UefpHipmh9SCUWtPtLkWcGXdrXq0pOmF73YmhoOBJCATFbICsPXl1Tto(WPh56ABRZYfT1iv4e(RRyxI3unUPmWnLrX0tTLdy9oOdl6Wwe9uBXHTL6UMpVM4UiQYxT)QcxCxeHjzE9eBCxe10InUlIWDrKGJcCxevjaQkIMK3E)qeXbUlIUuev1waCxefHAnC1O2mkWDrunPOVj3frL1J4Zgx5Qc3YYohYIzX0tfMfZ2Y)xirA3rh2cPNAloSTu318teaPDxyZq42N29W1aKBAXzopVDY)i(nS4UTIpb1gH8p2EWbY)4LIOQ2cG8pI8pkmOa5FSMu03z8pgcpPgz4Zgv5Qc2YssbsMtX0tchzoi7JOdBH0tTfh2wQ7A(PbGSpkS5hCBW(i(vxPfj24M(TPfBCt)IKUl4Oa)QRujaQkIMKhvPIioU5jD))ZENr72Mabrr)w8lwGCuADBAvEOUFa9NOYnH0AvRMkJRQIeQF7fdTjljEzxGXWoRpVLGmWENzyy95YIfxrsNba6oq3vJk4xDLrkqhPq35NDfHcYdLjiSt9loPo2PZ6D9k16uR7xCIxoi4tW5kvP4WNaE5GeqdB8jyQh24ta(eOCvWdNVicsIUjUO7QrDGpbDvrsNbWNGgKk4UrHSk4HZFKc0XOpbdTGOVTvoPQDOW5aIPFXjVHygka7d0Yv3TvbIPA73g)qmnNrLZjz0615HjnhEvlC2o)zLMJGMt4OdO50vfjDgaAoqZrnQaAoJuG(8IMJHCS2yOVnvoPADOmkGLJFXjy5itUYDtvy5O2UTXblhw46b0WMhiTPEyZdKgimvUkyHRlIGKOBIlWtAuhGWSRks6maimbHPAublC9rkqhNimzDRlumEOibbDQFXjqNktUYDZCqNQ2U8Xb6uwlVb0Wg0Pt9Wg0PGov5QGN(treKeDtCb8sJ6a0PDvrsNbaDkOtvJk4P)CKc0Xi600)t3jpB)HJy(LFj7BB(XTfZ2VE3xZkhR5FU(VQoDBx)q2UNqKDeHugfkow(pn9pFQM3u(L5LBAB2)oUlw9QDB(5f3D)n)kF1BUyZDRs8hUwILPyFvRqZ8HBRTV9sHL50xmlXfkU5pjS6TxRQgBQ8gm3(q68g46(4QKRxS0GnR5EN8yQDXYxNw(rB8zU5(89lmW8D4)RVDqRLIgzGTR)DZXz1w8AyASV2gLvFeBdYdfMZmqsw2e5zNWRBTQA93Z6Bz1JN2YJXlpVVVTtBvGSJNpxfogx((I0B)jZwrwU379jTFL)HoSHyiXjVTHiuELIsblfSEfNcLc2aTC19m5X3S(m)WPtU4BMkOZedU2GVztWWgFZW3mLRc8ntebjr3exUDOrDGVzDvrsNbW3SSB5Urkrf4B2ifOJrFZMBTEyzryI8XSy7DHkZMNHwQTfNXX(ocF4k77YHYmLETKvPQZlQoQCERh3V1DJwShiCXX6ZbFOXjVThiuwwnuWsbRxXPqPGnqlxDpdB8ZkiNLWFzVZGRKyqyyO1soU9FdUxZCiXgWbKGFdSpKrl481eNKTc6AVojZZ6(dxh(8MV()5Ac2NXH(XIsX09ia7RJoaSFRkQ6Daa7dyFBubG9NuHgW(jpZywsbW(E5cbS)Vk6PlCHsQUuPY8hF06KDusXWIHnvDsfdRO214(RbRVx9iSDy95lJHqlBEnvw9YMxtfsZYCvWxgJseufNMeLbHJ6G0SAvrvVdqAw3HRXTrsRc(YymPcnPzL8mJzjfsZYlx4rLM1ZAk6g3L9fN5kagsN6z8nHxzDiZQYMoeTLCu33i93BhzUYlkgnhjYBlxDkDEBQmw4iGymSPQtQyyf1Ug)iReqC532)PYD7ciM5yOqlBciE1lBciMaInxf86owIGQ40KOy9CuheqCRkQ6Daci(h0ACBKYQGx3XjvO3XaIh2r075kFQChLohumZvNstXuLxZfWUJHnvDsfdRO214gba7UTDiS)y3V)maHTf)6)NRj)rg3Ah7t8z6Ee8h1rhWFSvfv9oa8hH)OnQa(JtQqFy8hVPNhpzO3tv(uXokKcG5KRozhmhOpIHnvDsfdRO2142aG(OT9hSh0hzQqj0YMF0VREzZp6xGUBUkyQqvIGQ40KiuPoQdGU3QIQEhaO7aD3gvWuHAsf6nf6UHJVgrHrnitqyNMRozh70RU9R41XRNRoXWbHCcovQs7robmCqeAztobREztobNwob)ZoND7KWabrHFw8ojsWquVtEb8LWGyrjHijumgti(SB5hdftB3TDNwMz73DesOSNzMD62VZUn6iZWMZxebjr3ex0DTOoWNG6QiPZa4tWzKk4UrAwfS587OaDm6tqOfenTTsRQ2qHZbet)ItEdXula7vA5Q72QaX0S9BJFiM5xrLZfzu58CDsZHx1c921pB0Ce0C0JoGMtDvK0zaO5anhZOcO50rb6(fnNCYP0gdnTPsRQ1qzualh)ItWYrMCL7MQWYXSDBJdwoCW1v0WMnK2LEyZgsdeMgxfCW1frqs0nXf4jlQdqywxfjDgaeMGW0mQGdUEhfOJteMCU1fkghksqqN6xCc0PYKRC3mh0PMTlFCGoLZYRIg2Go9spSbDkOtnUky3FkIGKOBIlGxwuhGoTUks6maOtbDQzub7(ZokqhJOtpc3PSIIXB1j3N8vCpOvWn)JVuvKMl6bfE8(QbmB0juLkvBoZQq5C3PzwxNMSz3fmD0ljVV4Jx3E1MPRFljBOM(8HpT)FB50VtwFAIyb6iliSTOgRdg8Ztha5Mokn7RwMC86EZKBNTC6xdNVA2NPtgpCX8j7qj6l36kJO5kT)76L9xnA2Q0nnNu8Es3n(x3Qzz)dBylsiXjVTfrlVItPGLcwVItAPGvPLRUFYc8XZwlmcF8mbTOyWfj8X7cmSXhp8XZ4QaF8erqs0nXL7lwuh4JxDvK0za8XlpCnUBKQvb(41rb6y0hpSWR1hKyHxp0cVaB0I9a6fhRpx8qJtEBpGwoMpuWsbRxXjTuWQ0Yv3RWg)SS1Qe6v(zL)HRD(8MvopxNG951ZEVfLIrZra2xp6aW(1vrsNbaSpG9nJkaSFhfObSVN9m6kPayFBvfcy)Zvuz3WfkP6LkLpx8qJtMJsQ5ky)L9oJYwIbbHHUwMpF7)n473oNZ0cQunrV7adsr6nvAYncsyZfNSlHv0014(RbRVx9iSDy95p1HqlBUMkREzZ1ub3Smxf8N6Oebvr1KipiCuh4MvRkQ6DaCZ6kCnonsAvWFQJjfOXnRK1mMLuWnlVYcpk3SUxtrN4US)aoFcGH0PEgFt4rwhYSQSPdrBjh19js)9ujZvEqXO(iHFB5ItP9BtLXchgetcBQ4KkjSIMUg)kRyqC5N2)QYD7miM5yOqlBmiE1lBmigdInxfCDhlrqvunjYwph1bge3QIQEhadI)cTgNgPSk46ooPa9oAq8Wze9wx5vL7O05GIzU4uAkMQCnxa7ojSPItQKWkA6ACJaGD32oe2FS7xFhGW2IF85Cn5pY4w7yFJpt3JG)Oo6a(JTQOQ3bG)i8hTrfWFCsb6dJ)4f9CBLHERQ8QIDuifaZjxCYoyoqFKe2uXjvsyfnDnUnaOpAB)b7b9rMkucTS5J(D1lB(OFb6U5QGPcvjcQIQjrOsDuhaDVvfv9oaq3b6UnQGPc1Kc0Bk0DdhFnIcJAqMGWonxCYo2PF6oFLCDY1ZfNy4GGpbNkvP9WNagoicTSXNGvVSXNa8jWCvWhNFjcQIQjr0DDuh4tqRkQ6Da8j4lsfCAKYQGpo)jfO3rFcgnHO3YkVQAhfohqmZfNsdXufG9IMUgxwfiM2wVD)HyETJQWMmE85CnP5WOw4y7F209OFsZ5F258TLgggim(NL9gH9Mb(V3TVlYukQWqH1bIW(WB72C0PTnjnxtVl937K5qVNNC5A6VljgJcc0C8lEJpCdirYKqqGMd0CmJkGMtIm65fnNgYPZcddTOYOQ1yzualh)8jy5iZyL7IQWYXSvBZdwoCW1vuyZgsBQdB2qAGW04QGdUUicsIQjUapzrDacZqvK0JaGWeeMMrfCW1tKrNNim5CRlKhhlsqqN6Npb6uzgRCxmh0PMTkFEGoLZYRIcBqNo1HnOtbDQXvb7(treKevtCb8YI6a0PHQiPhbaDkOtnJky3FMiJohrNEgUtxjf3EqNCFAMX9Owb38h(s9rAUTxuy9d9dy2OtO6uQ2CMvRY5(ltTQN)uPS2HfF(tpfRh)O6VV3KLV8nB8hOYgll2xRGYvpx827FuRSDVwuznLpD6NoQUTB(Uy3HUDT13DtR16x2X)2g56)g(B381Qx(SC)YRFL))9RREUt)myg2uBjwkvFiwutuzMfMAwGvd(zG0MpAZNF(KwUYExqcljS(4tAjHvPPRUFtz6lT4pTFuLl9LMfzoEHn9LEQdB6ln9L24QG(slIGKOAIRUjArDqFPdvrspcqFPVcTgpnsZQG(sNiJol7lDSzedTUYOk3yPZbft)8jVPyQLtxdy3jH1lFsljSknD19cba7UzxHq(JDV57a4CzX9opxN8h5wrF2(gFgDmc(J6rhWFmufj9ia8hH)Ozub8htKrpZ4p2qpDwzyOvvgvXglKcG54NpzoyoqFKewV8jTKWQ00v3lda6JMD9b5b9rUh)vuyZM(DQdB20VaD34QG7XFreKevtCHk1I6aO7HQiPhba6oq3nJk4E8prgDMcDNlYFHm5yzcc7u)8jZXoDri5R)WoNDR0WabrHFB8glvkQ3zFb8LqkLwrOqbtfVr8z3w)bIAtMzZojzMnF9(KUNzMmzZ3z39FV9TRxB)MOZmhsTUU4K6ADoCqWNGPkvPYWNaoCqC0WgFcg7Hn(eGpbbxfS48nrqw0nrIUBe1b(eKQISodGpb)IubVnYZQGfN)afOlrFcYTGORTv6v1MlCoGyQloPgIPxa270Yv52QaXmS9BlFiM1NrL4KmA95CFsZHJAHj78NdAocAo(rhqZjvfzDgaAoqZjmQaAoduGEArZPMCASXqxBQ0RAnxgfWYrxCcwo2KRKBQclNW2TTmy5Wgx3rdBwqAJ9WMfKgimdUkyJRBIGSOBIe4PiQdqyMQISodactqyggvWgxFGc0Ljct236gfJZfjiOt1fNaDQn5k5M5GonSD5ld0PSxED0Wg0PJ9Wg0PGon4QGv)PjcYIUjsaVIOoaDAQkY6maOtbDAyubR(ZbkqxIOt)(373)flOQ5vhVT728WHvp)4MdxU8Q17w96ST7x)s1YfZEA7Yt0i0I(Qv5wBi9Z974F1817Ro0DytFclRZxDVMc0h2GSAoXj1Kv9YPKifSuWQko5LcwNwUkp5eSciSZAbRa6hLBXhCwcGOXkGryyJvayfqWvbwbyIGSOBIea3iQdScivfzDgaRaWkGWOcScyGc0LOvax0y9WI38jYN6fB36vMn)bTuBR38Z9nc3DtZxYPYSG(SuJsnMpuDw5CTI33k3Of7b8lown38CJtQThWl7uakyPGvvCYlfSoTCvEg24NvSMLWKYpR6FCT43B26Z5(eSpNWZtwukbnhbyF)Oda7NQISodayFa7hgvay)bkq7lW(FWENrjjXGGarplZN79)cU)MPQjbIq0UnVlWw0ilAETYmQkaS)Kdsa7dy)FROZ2WfkP6sLkZF8Q5j7OKsblfSPYtQuWkA5A85RbRVxNry7W6ZW(xOWMNPYQdBEMk4ML5QGH9FlcQJUjrEq4OoWnR7QOUxbWnRJW1y3iPvbd7)jLOXnRK9mMLuWnlVQcFvUzDUMI2XDz)iA8jagYG6P(IWLSoKjQS5eI2soA4DK(7QwMRCJIQ(iHFB5YtP9BtLXchgetbBQ8KkfSIwUg)jRyqC772)OYD7miM5yOqHngeV6WgdIXGyZvbp3XweuhDtIS1ZrDGbX3vrDVcGbXFHwJDJuwf8ChNuIEhniUCfXO9vEu5wLohumZLNstXuLN5cy3PGnvEsLcwrlxJpiay3T9ec7p29JFdq4XIV8)Z1K)iJBTx7x8z6Ae8h1rhWF8UkQ7va4pc)rBub8hNuI(LXF8GEoTZWODvEuXwfsbWCYLNSdMd0hPGnvEsLcwrlxJpga0hT98b7b9rMkucf2CPFxDyZL(fO7MRcMkuTiOo6MeHk1rDa097QOUxba6oq3TrfmvOMuIEtHUB44Rruyufzcc70C5j7yN(z46vQ1PwpxEIHdc(e8wPkTh(eWWbrOWgFcwDyJpb4tG5QGlNFlcQJUjr0DDuh4tWDvu3Ra4tWxKky3iLvbxo)jLO3rFcQwqmABLhvTvHZbeZC5P0qm7cy))SZz3knmqqy0NfVrO3uW)URVlsvcQqXcnfeH(WBsBTSvZMD3KjjZS5CNul68nZStM9m7gGycetRvVn)Hy62rvWMmADDUoP5WRAHzB)Zgngbnh9OdO5KQIKocanhO5ygvanNrYrpVO54ihVfg6ArLbvR9LrbSCIZpblhzIvHlQclhZwTnpy5WfxxrMnhiTP2S5aPbctJRcU46IiijQMec8Kf1bimtvrshbaHjimnJk4IRpso68eHj3BDH8X9fjiOtJZpb6uzIvHlMd6uZwLppqNYD5vrMnOtNAZg0PGo14QGt)PicsIQjHaEzrDa60uvK0raqNc6uZOco9NJKJohrNEgUJVKI7oOtUpUzCpPvWn)HVuBKMBAJcRESDaZgDbLxPAZvwnkNhUS0QE9tLYAgw85p9KTE8JQ)(rtw(Y305pqLBSSyFTckx(sX7F8zTY29wrLRP85t)0r1Tz93f7o43RT6(BBSw)cp)BDY1)183S(RLVUTC)IR3Y))(1vp3PDgmDBPTeTs1gIf1yvMPXuZcSQZpdKX8Xy(IZpPLxzV3qcljSX4N0scRstxdVtzMlT4pTFqLlZLMMmhoZM5sp1MnZLM5sBCvWCPfrqsunj00eTOoyU0PQiPJamx6RqRXtJ0SkyU0JKJolNlDFZi6ADLbvU9LohumJZpfnftTC7Aa7ojSr5N0scRstxd3iay3nBhc5p2D39aeST4wxNRt(J8wrF2UJpJgJG)OE0b8htvrshbG)i8hnJkG)4i5ONz8hD0J3kdDTQYGk2(cPayoX5NmhmhOpscBu(jTKWQ001WTba9rZ2FqEqFK3J)kYS5q)o1Mnh6xGUBCvW7XFreKevtcHk1I6aO7PQiPJaaDVxq3)HDod(nTHHcJ)3sVerxRyjSgobx6XDOxYoBugKvfjw7ejTsTh6F7ZqGcSfWoXVe8Z(RxQkOg5VV3lp)Yp7ytDbZnb9QJ7(ZgbO7eA0ok0DCq(tKjBktqWovpFIDStVQ15Rixh5665t4WbbRtGVsvYnwNaC4GyrdBSobx6HnwNaSobmxfyZ5tIGOOAIk6UCuhyDcAQIOocG1j4isfy2iBwfyZ53tgTlUobMMq02YkDQAnfohGyQNpPnetBbyVLMUQUSkGyY26TUpeZd7OsztgN9(C7KMdoQf82(NzAmc0CShDaAonvruhbanhqZHnQa0C6jJ2VO5CGCozHH2wuPt1QPmkalh98jWYHMyL6IQGLdBR26gSCWlUUfnSXgs7spSXgsdimzUkWlUojcIIQjQapXrDaeMnvruhbactGWKnQaV469Kr7MimX7TorESPibb6u98jGoLMyL6I5aDkBRY7gOtX7YRfnSb60l9WgOtb6uMRcS7pjrquunrfWloQdGoTPkI6iaqNc0PSrfy3F2tgTlIoD7pF89kwqfdlKx2LzZktx9yw5nt)A(tY)1xtlZUn)xth0eSxpVCH8Rg(5fyOS45I3cQsH2mGYFxQ(1Pg)o9Pu5GBs0DHHbB(J)mVCM8dIJVoy3xo4igwFrEZBWJZxSdu1ePd(PkNm9BHb1NRE0fr2pFSu7IKxZwviLL4HrHJghfffhgosKSmVOSq8drYrMI8dEiA9NU12f3lsQCfrsLP)8lfZ(zEzMiz(k5VwLNksAn)m2HkwBgO1Yk(KWITv6C6CXn2QQfxC3C2pEgGXEeXy1ZNwHm2wZk9wcdJdRckmxgvqJDpQXUa0Y4DPyig0NJ7AbhBWZ1(Fv874hnAd6y1ZRSLDmGhx7JR7cL2dvuANHYZvWh7q8J56DkST3gL5sSuj7jiBWuTyojlxgNDoPAkT0XTkn(0DkX)uM1yKDGuM)zl4AAorBlU0PY1yUDaXP2wL(ionElXceNaXjJR86diopSfl19CC2B3TvqpXa0Jh3untJsa0Jfjea6PXkI6qaa9aqpCsga0t)51(gONd0Z(b8FzVZGStvOyWWRfh6uT2thy3cVLGRIo0fFv670kCasUCZfscFZlNM)KWpXpJxgypSuRLMk2QzxaMh1PkW8yw9s2Efmpb23njyEENnzZtXnBY22h3SjBa4mfw7a40ebzHNIiuQikeaCwSISUeaGtaCgjzm7ZKaWPP56Sc4SIttYQooj3rNNKQ5fcAv1PkqRAw9s2yh0QcgvE2XpjOv5hjSRIBqRU9XnOvbTAkS2bTQjcYcpfrCyruiGwTyfzDja0QGwnsYGDhD9Y1PeT6XBFD7FNM4OtS))gDhDIpZcAALudwBUE2FL11pVCwaQZXE)1pJI)hcdsMDhjMvVuTBH(sWtGFOZtDP(Gpm3F1RGwssaSHFUlxX95ZBPlzMDVUVIimkkO6IrH7KsomkUiBu0nP05fCitR)o8jjhQqU3V3xp9pvTV(rx4)2GWV3aD6JZXgW)4dJY5BIN29Q116z7r9tyX98noUR472MT5GT5OGT5Wph57hOVL(w1Pk)0360UwzgOSfsJDzv(0)Mkx2cjM7SPXnBH02h3SfsSfsPWANTqYebzHNI4MJerHWwivSISUeWwinG8gptY1YGTqA9Y15ClKQUPyPUlnvVvdUdgNQtv6zC6NFPLWMN(2i2360Uw5jdGn)yxwqgzypWM)1pBG8WYZE7UxjuY7yJ98NgmOvjiu6iHaHYIvK1LaiucHYijdiuUE56DhHYxe0K(dl1BPPQTA4fW5rDQkICEGpj9TrSV1PDTYZfaFYXUSGmWqs4tYlhgxf3S7WBFCZUddz(uyTdzEteKfEkI0uJOqGmFXkY6saK5HmFKKbVCywVCDAjZZBhgZYZvdme2QQtvrKT6Hf32slVtA5)MDoF6TnbcII)zjxSazPQ62e3COTh6hGCHEEROo0wRg1izOQks8HVa2XzHam8NXWmlVBjwS2ZB2HHLFpw0rjpEvKqD3kKlMb2ju3WuYQCCe7eWRIerf3WoH5pUHDcWobNO1oStGfbXrpfseWAuiWoHERiUNcGDcviyGRjjAzGh0)Plx7K2jm6AIH2C5Ik3rZTdio7CQQ7ioLdvFHw1s3GfiovCN3LaIt7LyrVMJwpDxQGEWB0HL8IQv6Sea9iiHaqp9wrCpfaqpa0JMKba9mD56LgOhl90y7HH2A5Ik2rZUayE6CQcyEyB(IU9kW8O4(UocMhSX4fvCJNKT5pUXtYgaC6eT2bGtweeh9uiHsPrHaaN9wrCpfaaNaWPMKb2y8txU2vbCI9fpBP5rZleOv7CQcOvzB(IUXoqRs0OsYD8De0QytclQ4gOvN)4gOvbAvNO1oqRYIG4ONcjomnkeGwT3kI7PaGwfOv1KmWZo60LRDs0Q(pZ8jokj)Bm(nFp6x7)Z9PPxLeE4NrzbB83o(xf)Epe(u0HxONvJsYsdpZhRCjGVVj4ihktqXHBc(XJ7(BS5UnMeZD3y(Qj4KsmFXeS7W(KOd7dnbE9adNxdl)(6wPR1jmVnD7nPPnSI)SCOhf2UvViUJF(jLv6ZYU2Z9p5VQeAVp)jVBxVXIMBPH7DEcF9M36NDSLoODpgNS2cjy()F6sfTwHAnr8q4)QeQfFuNIu7b3uGwCmnfN5vSxzrWmR9sLFXBTl2YoKZLAVlVuBlpLANdHWFh96yyBPqi7qkhdFOsmu5mJHfsufBwTbEvbXW5(wqUEWJ(I23Rh5o41XitvD3Rd58crf1TOUvJ1TcTQL(oeGhD1nm6vzoFYfE0Pe6poH)qWJUzjUHhDWJoNO1o8OJfbXrpfsFv0OqGhD9wrCpfap6kZEdxts2YaE0nD5AN0JUvnwrSjVCzGDoMkTS9gXsYPcXP022Pi1DhdF86wgtEPMspHQzTQZZSQvpVVlx6LUHlCqaoi0DheKZU8b1TOUvJ1TcTQLED3W5R6gMKx2WcZ5l778M(wrB90DPY)hVF3xYSwu6Se4)liHa()9wrCpfa()G))jz8F27m6ijgeggATCFE9FdUZ93EzsWqWbKCEfaZGaTgNNsyTqgW)FDR1W)V7khRslW)3oNi8)pkPRo7fkQqr1rkQ4BX36OVvuxBCx3q))SHPCtd1J(p)TFi18MV7L9pV57EHCVkrPDY9kfbLrnLWSkCuiK71Wkk7TaY96)S34mjTLb)TFSU1AY9Q7khRslK7LDoXxwUxxlQOdFB6yIkw3260ES)HAUnKKBQO53hAZarNPLnDm6ltPBF20VTQCUZtmMoSjYLR7LQ(ZLtN7JoYtgFRJ(wrDTXpnl5jF2WM80)hvU1lpzUhfLAEtEY7FEtEYKNCjkTtEYPiOmQPeMbOJcH8KhwrzVfqEYhiVXzssld(okx3ADjZtEEtXDRU8O6DAWDW4S7LQ(zCQZ3mdS5X36OVvuxBCNbWM)SHzsldVb28F)SbXnl38N7QsOKB6T38tdA6UeekfsiqOCyfL9waekHqPtYacLRBT(1rO8lbDz9H7wB5rv70WlGZt3lvoY5b(K4BD03kQRnUVa4tE2WmPHHIWNK7IkPM38UdV)5nV7WqMVeL2HmFkckJAkH0uDuiqMFyfL9waK5HmVtYG7IQ1TwxwY8wEF5ikLQzbgcB1UxQCKT6p322ILhl)awEUksIEALWMzioHZgMjD5uK4e4QirQ5nXjS)5nXjqCcLO0oXjKIGYOMsicyhfcXjmSIYElG4eoqWGZKKwg8I(VU16wXj8H9oB6jHbccd)BXBYfsm(r8GN8hGxWZRPcnkjenPTjgt4hVacHcPT722TlZS95MxkoVZm7W2N3UffjJtTtO39eDD4YGk3EZTdeNoNQChXPCO6l0Uw7dybXPIN8ogqCwElw23ZrJl3LkOhEJomM3uTsRsa6rqcbqpTwr(UeaOha9OjzaONWLRhBGEkPNAhp01rldQy7n7cW84CQcmpEREzF8kyEu8C3ibZdhmErf38KSD5JBEs2aWzumAhaNErq(yMIvOuAuia4S1kY3LaaCcGtnjdoy8HlxhRao5CX7T0CV5fcAvNtvGw1B1l7d2bTQLbvsEIFKGwLdjSOIBqRE5JBqRcA1Oy0oOv9IG8XmfR4W0OqaTARvKVlbGwf0QAsg8SJgUCDuIwDpYN6AlUzBpthhFekb9W9IfNZzyNAefDv32Wt3zHaTsxvvVw15YRk1ZThxEDDEAX2pW8PVN(5YVwSE9vfjzFKUjwZF7))A3)Uvj)MMDC5yfcztw4a95thWozIPW8YJMxnZ2hVMNnZMNTSinBzIz2wYIodZUXezPM6dFGRs(z68VZl6o74D0V78vpOf3wK3WVKEMQC3Ve58svL(w6B1yFRq7ATFxg4ZxvxMK3Fe(8PecsrHht4Z3fjUXNp85lkgTJpFErq(yMIvVz0OqWNVwRiFxcWNVtzVX3jjBzGpFHlxhL(8HfFbikXIVXPfF9DGloiGdcU7GGCoPq03sFRg7BfAxR99DJZxvDzsEBdJmNVkFN32Vv0gxUlv()8oIFmZArPvj4)liHa))wRiFxcG)p8)1KmG)F4Y1W)35jhHslW)xDDIW))Cjv339cfvOOQrkQ03sFRg7BfAxR9DDd9)QUmjVPH4J(p)0HiQ4MZ9YGh3)XENrjjXGGarpl7N79)co1(x2Psevqdn(oawLnYGKxNWyUV57EbFVkrPD89kebfrnftVkuui471Wkk6Ja896)S34oPCld(RdzFXA89Q7kh7sl47LCzIhMVxplkRlFBMXyvSUDQt71(hQ52qsMur(phAZajpBlz6yuxMstF30VTQC(M3y42Sj8LR7qv)(YLN5rh(jtERI5TjnR1(PzXp57wMZB)xQCRNFYmhft1(g)KF)9n(jJFYLO0o(jhIGIOMIPhGkke8tEyff9ra(j)f5nUtk1YGVJY9fRlPFY(tkMT6Ys1RBWDW4S7qv)moZZ3mdS5jVvX82KM1A3zaS5VBzI0YWjWM)6Zgy3SCZFUNvcLmP3o5Ngu0tjiuMiHaHYHvu0hbqOecLkjdiuUVy9XrO8IGES(WS1wwQADdVaopDhQuKZd8jjVvX82KM1A3xa8jVBzI0Wqr4tYSOkv7BE3HF)9nV7WqMVeL2HmFickIAkM0uvuiqMFyff9raK5HmVsYGzr1(I1LLmVKZlNKsPYlWqyR2DOsr2Q)mDAlP8KYpqkpJIeRNwXSzgSt4ULjsxofXobgfjPAFJDcV)(g7eWoHsuAh7ecrqrutXebSIcb7egwrrFeGDcFrWG7KsTm4f9FFX6sANG7CIzlUSu56MBhio7ou1pIZ8q1pPzT2fybXPWvEpbeNxBXYUNJM)CpRGEyIoCYnvl6PeGEsKqa0ZWkk6Jaa9aOhLKbGE2xSEbGE(WENFR08abXrFw6nc9Mc(VVR67IuLGku(eAkic(WBtSwI1Sz2nzsYmBp3j1U68B2zNm5m7MmhYiAqpn0tW0d9n1YOk2bZUampr7QaZJAZxYPxbZJJZ7MjyE4GXBk7MDY28B3St2aWzwKAhaNQiinYPicLYJcbaNjRiTNcaWjao9Km4GXpD(6CfWjNlE1CZdMxiOvJ2vbAv1MVKtSdAvHevwoJFMGwLdjSPSBqRo)2nOvbTAwKAh0QQiinYPiIdZJcb0QjRiTNcaTkOv9KmyVJoD(6SeT6rKpHclUUkMPNPpMkb9V7nloNZWo1jk62UTH13jqG2PRQcRvFU8Qv9C7P1x1lIoiTaWKp(XFBT1Fw9iIN98PVAJ)ev(YYI9vYOC1JfV86)RK3UNlo4FkF47FQwIB38rXUp)mSVB9nx1AI)LH(h3iQ)hjSDZ7RE6TY9l)nnG)8RpCvOU5Z0Vf5AuCvN4xSJz5MIv9loREFfrAjiTemHwcANNBWliUL42ODv2jU1OrTY3inTYUTHnWR(pQYLwztDNJQDtRSNF7MwztRSZIu70kBveKg5ueB)OhfcTYozfP9uaTY(mYBCnjtldAL905RZZwzp4GI(MDzu17Gb3bJZODvXZ40ohxhyZtCRhJBnAuRCLbWMVTH5KsgUeyZ38EdKlwUZL7wLqjpO2VKVBqNolbHsdjeiuMSI0EkacLqO0tYacLtNV(IJqzdbfm)qFZTmQQDWWlGZt0UkpY5b(Ke36X4wJg1kxxa8jBByoPGHmHpjVHbmLDZEhE(TB27WqMplsTdzEveKg5uePP6rHaz(KvK2tbqMhY8Esg8ggy681zlzEEfdOMFEWadHTA0UkpYwDrVdBjKNq(ec55rrI0DRiwmdTtOTH5KQCYK2jy5hfjFXoNDR0WabrHFB8sHI)acELpa9M41lukkuqOqBeVXhEB1kekjz2nzYMz2851gDpZm5KnFNKmCTxgOSjoHzzDtCceNqryTtCcQiin8uera7rHqCcjRiTBbeNWvem4AsMwg8G(NVADrgNWONjgQ5YKk3rZTdeNrxQIhXPDO6B0PwzdwqC6yN3LaIZMBXsEph9E6Uvb9Wx0HL8MQDAxcqpgsia6jzfPDlaqpa6XtYaqp5RwV0a90qpDApmuRLjvSJMDbyEIUubMh16xY2RG5XX(UfcMhEX4n16MNKT5FDZtYgaolcRDaCQIG0WtrekLhfcaotwrA3caWjao9Km4fJpF16sfWjVx8QvMhnVqqRgDPc0QQ1VKn2bTQGrLLD8le0Q8scBQ1nOvN)1nOvbTAryTdAvveKgEkI4W8OqaTAYks7waOvbTQNKbp7O5RwxKOvV8tO6pcrHQTFS5Rq1773(5XW6vH6W6NcVgQU8Vi8YPFJd7QF7WUnHQZ0kIgqwVAVX67))GNwh3UD)X6HZJ6xIAd(ON0(rc1nyWoYsv8myTZhQrMBzU1JZTgDQvENlKDqBhMt2sdzhmvsxJ7kTi4wt2bZY6MSdi7GIWANSdurqA4PiY71JcHSdswrA3ci7aYoWtYGSdYxTUiZo4MoNiwDECzGoh5slp(Gzj5CfXPV77jyVT7y45775yopQ50tO6wR(8mRw1ZDXCPxzdxsqGeeIpbb782hWClZTECU1OtTY77MKVA7WS82gwyjF18oVLVv0EpD3Q8)57o9sM1It7sW)3qcb()jRiTBbW)h()EsgW)pF1A4)hTZrU0c8)D3Ki8)VwsDDTxOOUSOO(d7D2LKddcdd(SSpU3)lyN9TUDsX8JdrY8DaygeOAC(ucTkuuX3IV1rFROU24UUH()vdt5MgQh9F(7iqQ5nF3lp)8MV7fY9QeL2j3Rueug1ucZQWrHqUxdROS3ci3R)ZEJZK0wg83rW(wRj3RURCSlTqUx25epSCV(UOIo8TPJjQyDBRt7X(hQ52qsMurRVp0MbIotlB6y0xMstF20VTQC(KNySCytKlx3lv9NlNo3hDKNm(wh9TI6AJFAwYt(QHT4P)3QCRxEYCpkk18M8KF(5n5jtEYLO0o5jNIGYOMsygGokeYtEyfL9wa5j)b5notsAzW3r5(wRlzEYRBkMT6YTQ3Lb3bJZUxQ6NXPoFZmWMhFRJ(wrDTXDgaB(RgMjTmCcS5F)zdIBwU5p3vLqj30BN8tdA6UeekfsiqOCyfL9waekHqPtYacL7BT(4iu(MG(A9HzRTCRQDz4fW5P7Lkh58aFs8To6Bf11g3xa8jVAyM0Wqr4tYDrLuZBE3HF(5nV7WqMVeL2HmFkckJAkH0uDuiqMFyfL9waK5HmVtYG7IQ9TwxwY8wEF5ikLQvbgcB1UxQCKT6ptBBXYJLFalpxfjrpTsyZmeNWvdZKUCksCcCvKi18M4eE(5nXjqCcLO0oXjKIGYOMsicyhfcXjmSIYElG4e(GGbNjjTm4f9FFR1LmoHL9eZwC5wL7YC7aXz3lv9J4uhQ(I6AJlWcItJR8EcioFVfR4EoA(ZDvb9iXn6Wl27SBLggiik8ZI3i0Bk4Vx13fPkbvOOqtbrOp82KwlXA2S7MmzZmB(UtQn6CMz2t28njTQSZyoSPAJwLa0JIecGEIwrsxca0dGESKma0t6Y1Znqpn0Jt7H(ATmQIDWSlaZtWPkW8iw9YV9kyEmSVBMG5HhmEvf3CNSn9Xn3jBa4mlS2bWPicscpfVqPSOqaWz0ks6saaobWPLKbpy8PlxNRao55IxS08G5fcA1GtvGwvS6LFJDqR6XOsZo(zcAvEiHvvCdA1PpUbTkOvZcRDqRkIGKWtXlomlkeqRgTIKUeaAvqRAjzW9oA6Y1zjA1tiFC1wCtvptpTpsLGE8b1IZ5cStDIIUTlBy19EiqB0vvU1QnxE1QEU786R6frhKMdyYNE5JrB9RvFeHZE(8BTXFIQCzzXUkzuU85I3E)Jk5T91Id5NYNo(t1sCZ6Vl2UFV7C3QBVUvJ)fU(h3OR)xjSz9xlF5ZYDl(lnG)9RpCwOU5Z0Vf5sS5QoXVONWYmBw1U4S69zezKGmsWigjOE(Cd(k6BPVn4uLE6BvAxR)lKMrz32HnWZ(pQYLrzZ(oh14Mrzp9XnJYMrzNfw7mkBreKeEkEh)OffcJYoAfjDjGrzFb5noNKQLbJYoD568Cu2dUPOVUlJQEhm4oyCgCQkCgN65X1b2803AX(wL216FNbWMVTdZiBzyoWMV51g4FZYDUCxRek5dQ958vdA0QeekvKqGqz0ks6saekHqPLKbektxUE2rOSHGC6p0xVLrvTdgEbCEcovzropWNK(wl23Q0Uw)7la(KTDygzddzcFs(ggqvXn37WtFCZ9omK5ZcRDiZlIGKWtXlnvlkeiZhTIKUeazEiZBjzW3WaPlxNTK51YxXa)WoxD72O6aHFwYnrjhPtu(P58Ju6EX(aS3KZ1GCtCsqLewboTQv9H)mgmGbS5VqiaDwPTQngmZ3mJhpZ3yIknPENX6k03v98ntyiYTAPvv9rUvhvB3w0LhD5RGlp(vrsrvRuyYmy7euDB9KSCgiTta)QiPtj3y7eE8Yn2obSDcdIq7y7eAea1eXukKc4(iqW2juze10MaSDcPyWa3tQtdd8G(3E66bz7eUzFI6gC5Uc3BM3oKIZsRQkpfNDhw97OETfhGfP4Shh597afNYPyvCoh5UCVRs0d(n6W35KQ7PwjKONoeqqIEQmIAAtas0ds0tFcgirpTNU(7grps4rB4H6gA5Uc2BM7cKMNsRQqAEAm7vXHxrAE6XXDhi08GVy8Dk5gpjBpE5gpjBibNdIq7ibNncGAIykfskvFeiibNvgrnTjaj4ej4Spbd8fJV901dvcoX3l(gtnFZ8fIuRwAvfsTAJzVkoWosTAbbQ6Yr8hiuRIVKWDk5gPw9Xl3i1Qi1QdIq7i1QncGAIykfshwFeii1QvgrnTjaPwfPwTpbd8SJ2E66bj1QI)zSnGHiJT7SjVBS9GZUREg)AHbd(XCJ)ZyR4zy8Z4l16cmRVryu4UCTyuxlIX2jvIZmh79WyZIMPzqy29FmoWrZxOT(e0qC)NZKleaaBw8085J9)JFVJzcFW61thho4Ke0F9hWQ8Xh3TpKIRnGwostS55vZhR2JoXKafaSEkOhygBFbUmqxaQf1ke(4(OtwHe8iIgcMFUsDjFkU6rbl1btqe5tQ0nXiUhPSzoxzEw7PRJFeGvf852DIpUSmat5kDsfX9vVxTUip)NOeB2jUgCdSOD8eMZXJ20zNbVYZGdgND0ecqmnMYcqOLnYoMyqFtjpQJyUE3IDY6IVU8xpLp8fplQ91luptBU5qWBz7kPr6qzjjLAFTg1(bOUVpTGf5U0JCNoIy9LkBWY1TmWa5(VY3eeszm9Ilj8XKETeesxCvIyHVa3DOHAKUHKew5XeYAU3OVOalDvCf7C8yISNVJYKnzh3sQtGIgoqA43zRAwJ9x9TAP8u)BDEQeWKtnpy5sv5binCYMhipqSxrBJzay)JgGfAosU)Kq6JSvqa)0FKhJSd2ph2yj9ir4CvBJZW9KxYr8)QbX7PNDGjZ6tEYbUoW2vsq3JY47W5nJdbg8FZmxoVntJc1qzgv2k3YWpf(1MtI0QxfBOOiKqBccFjxxYdEVB9BQPFkgPxe(g1e2b5SfL)Lj849UxT2Bc3oS3sWOTSTWhglRYAUwv6s6OKoRijPse8g0PZZDRb9BOOztJG8gxmZVGb9UEIN)FkUIZKR2bBC8JN1UbxBBQJReitUcHwCUC7RQFsRQwRYvYyv08Z4r3oa)otvk4XpRSPBhxBdX22m4pGu58GzK)tZlKZurY9HzMxHDjR)2KXAfN3TdTpbLle8rqnsthRU(bDj77sEZFJFvfKL45K8XK1RkLtv2aYAeS0obX6EwMsJcjuiUMWMto0MwUFzXox9YShXKQu6AIse388cnN)JLnOMTSjSxIIMQLiuMIH0LIz2vEPxbfVhhSfxour9djIsYW)IQWJ1dRsbgwAgChEbsrEjCMpmZIZ84CRiGMZG3vLWPpEXfY)GFNqsioo7n9R09J8slTn1lABY693)iq1KB(PvAHWQU1cHvzxiOnB2QzXxDtw82DLWQsTsqB(XTPIP1xkKw3Omd8sPjgLjOWxFLw3CpqGhuRRnvaJGSolrOVC4eojv9PS250jHY0oMsNTsE99rIq81RMM)bJCAIRMlfcrivdjIkNOmnlrFVhFa4Ba0fBaNl9v96Ahu)bhc7vp1KmaoWEbRYlX688BlArbZ(62EnlWafvW6Ibk6CqzyeOyDXbkMQIGT6D2bMmk8vyH8knqr1pvIPoTbRuCa06Pq5PKNSeUHkj586Qm4B5blXeu8Csejk53ou1u1Jys9NIiUhapmN4ZyuyhVxmFAKjuhZ9Q6cnRuvqJfuHfu9OdMH5j11GYWipjSGkmqrNhh)F7C2Kdccedf(6WjWJGXtHrwqcenHe8NLE2LGMOzgyWOoP9jF7zrBD6J(9MIiuyrC7nGQevXPB7ZDrk8hxzovgZhPRwXOqRCCjNbUkNncpCScBaEtBas6aWVzd3EXLH5)kukcwgTKBf0WtfSoqJ6oqsFlEUjZLhRt4CWWHwSjaBcSwTJP)DxQO7loXMaekKkpqOWI42B2eizrK7DnAM5fhWv4Q9dpb8ew3lZycElv(pgtaEcekCFEGqHfXTo8et31N7Ae3DNbfDDBO4kW(wIShFbHGKbsMXDZmPL7sfDFXaiziuivEGqHfXnizZxJajZGIUUnuGK9zizr)PUasgizg3nZKwUlv09fdGKHqHu5bcfwe36GK54IiBDx0mZlnGIEKIYZNQB7Xd2uTV5qZ1DfRB7QUu1D)b2E7p]]
)
spec:RegisterPack(
    "Balance (wowsims.com)",
    20261115000,
    [[Hekili:1sv3UTjmu4NLEtxqlccP021OMkTQQP1QTQPr3TgmWHGxm2iBtZQufp77ysdLqsw100UjY54Z3ph7pdXN8ajmJAaY9tNm9mFF)tNmzcj08ufqcROPlPlWfcAj(71uovKcnXJwjxPzLA3uzPJTTN4sAMLQKAg3CRGKSxw1vqkj8MV)JBVzwYAYiHfSSmyncqNEivM1eBkWIVuZlxQGhbvtCgKtR5MM4p(TV0eJLBIFLHAMNvtTxMQML59IME0kowAnqx8pU)ulfoJrjuuHMJgpdxlTsY0nX0SmP4D4ILWtA3M4BOg6S9yLrF92hqskmMk9mpVfmtrDI19EdA1b5eDmea5xm9c40GZVWfpgvYCghprOPgMuODRuacoHAMxkLILmreIVCmlF(rj155U9R6wx1C3oaF)CVvkQPWIXU5JqeiGsgOVmOR9)s2robETa0rC2IcZ4AnejZZJwKMn3VFxmHaupIhMwolPcQBvQjIlVmyYX5wOrkOKYe6RozsFCwHZzkyCUmTwpFARLYGotz3BGHqsaKB9kkob7bw)9haTOwPyPubS7z0vZd63P2qv98LVfWOrhzOCqyCHuoRsdUGGMWHSNB1DtX6kNJhnA)DE8wDIIKU8kFNNpATWUBu1f(fKwByIfoo9Dv79BZDKqmxPXAdEYXzAJU9r(64oU8(2h9VOo56n5nsy)BCsyQIzafJsc3BEGyqLgquVOGvLoI7NxS4o5agOlX0x93i5y5lyaF9S(U5MTNxBrsy7nQDEqYo9njBqAQV)FDJTj9SdmXDPV(6Stk0YW5h0whod(phc)JPWxNIn72nZ(wh)HdmZTjwInie29HQ)RXYTf(Gh0xg0Ak0w0AtHurc)mSKXz4h2)0lF3UDBYVd]]
)
spec:RegisterPack(
    "Guardian (wowsims.com)",
    20261115002,
    [[Hekili:S3vBpokYr4FlZxCmzN4xhpxUvlJuKwLtBusuuM7(QzAdn2Dgmyb4zKxnY)2t1aMbWMxSbJ72U0PB1Sq)s9uv1vx1d92Z0Ht)9PpBq8Pt)3Jgm6XHdhozWGrtF2FZk60Nxr0FLmh(bBYs4p)T1exdgXE7lDF35Dp2sVE6olv4TBJLdXGpwZwZS8)H90zhCy9wr1N(83)V)Xp((xNhnAtFEbZWGg2fQNEUZZx3(I)c62xIEwFthx6Bu3TVyqnjRT83(YF7)8p3(c84TVKyiwZ6ZNwV(gURzg9nPUeRzuIBFYklV(edYkF2B0EWFR3)ZZXw5EyACj2EwG4Ba)SdFAzEBFHyy4y)NGF4v6gVEBF57eFYxpG409F9JFhgKf((R8(A)(Zz(lwpJJG(zAQcmMGutNq(vDJrKrgM6WW(JLRCC9HP5VZL0m6aOhErQbDEFTyE(EWKrT9PUCX99fml4LZwBA2dAHgmvl7TEvpWi56ycVB6ZeDFMJTNQoXYsl8VOXhN75wz4P(3ZmvZoaB)hrD7lQ95AVGNZBy37cAA8ZG2Q05UI6EGfqtFbXDo9(1EunhttT56gQddgpF(Z975S23JzqNuYGnJ4(Q3Rm7GUUGsS8x0BLU)3uFCqNU(oZNBr7T05n6sqd1j7y3P7DHJuVKYuVxTDE3(dDhhld4hs)oxkXyJIYhrJ07GXLzprPePKAT2M6bA55l8paKJeIKTkuieiiy6sT)jJAO5sNtTHXJ)ISA9rteijMA7soOhwS(oObrAA41W8SKWS9(Mk47e3QvUSLGOmJ5VRPXayVx9P8N8vrIFr9lqqSC(2bAGUJNpG9U3DgfilIo3IMJ0e)2qrH3rHXiBsOUmQMjZLMY2M45rkjdAW4K8fFAVfjiTtDFVPJ(Ap1rH4QBK8hBmwVQt2h55dBy)KkeZm7BIr6yrcPg0LoWGW(jZEUMRdXnfK9O((Wl86XfDF4)12R9GKc)xey37TjTVTlSlb3jwlMm()bwy3IYCXIS37Svun(U8FUm7nQgStWsg17j1rDcsVsBMff2Ji8TTRo)uwujmI3sib2m7ufkOr7yffrg0ZdkkAF(Es5SpqW6JNg2BIsb9D3S)xIAbxyd3l4j1C3WsKm(5QDdDdYvFw0WYFOA2DFo5nF(ueCE3ksdeo3HpbsQo1mdGYL8gp9M0a4ZENUZ7BmYylYQrZoB7ub85BpLsThDWg7OZCw79zmXyqfppjWvI5wPJjpFzTy15qWxF5mhTvoWUgWeS2fYC1hw5uFLqXPXhjVvjl(JCEZTsnTrAHD1tZBbu)xSt4NHMHiZW6olyw7Xwc(dVbHNdABpOi3xFAqNOxg58BU2Dt4Bafw91yvrYxSzMlSZbFiGTpCCm0cQ1yZH2ObqZD1aof8YweQNbGf3322moUChWXIPd44tZbCCTStxghWSq9maSlMdOhKTVfncGb7oT3kRpYI0Akp7TGw1BbZKxRcSPZ70OmKlqHuOMoSyLQV9xUtK6GoCIAMVHxkV6KXbCiKBBvs1yUmejaPXwCgyfIVcr3fbCG9iy0zgowW22A(lOAgawctFPcyjJAGAtGsDmukbQXJl1G474UrZG5PZwzXSP7gIYMGKWCexVNchHzo5VrQGrO1ssniFiNgG9wFx(k87QvmSpQGYqKc)HrieiyGriAFXoTfys5rikjROaokEndJBvFD9DrCMWhJqvxbQ18JbCU1APPF4PhK31FPbYHwbkiQCPD9vAn8JkvzjeZgwu(g5OzflM)04biCzBeLMbl1z)eaixRTKyt4l7h(WGbDc(lR091GhaHb6S7LDtj()zihISF00eXpgpyh3PwuIRoXJRq4ZvADG6WYQTA)YYXQToMKPUiGdZLsGGbMlv7l2y1wyec5bgyeI2xSB6QT2ppP2S(lbwrFW6AUgqYdLx)WbDkUDROiWGGLpCmzhCrahMCGabdm5G2xSXYhWieYdmWieTVy3CLpeizTzTc5hc4CR0WVvtRRYL2LxhX3Qz3kOBTcRYEScXkRoMeNUiGdZBsGGbM3u7l2yLvyec5bgyeI2xSRBLvzZkQnlTsGvR3sFgMd4cCRxBaEmUWQfAXLOyUaIfsUkYfaRwaJqiYWaJq0(IDtxTqBCmUKHpuG043IFuj0x5eLBzXXOcFmSkfg72Tg4alcwW7XKp7fbCy6ScemW0zBFXgl4fJqipWaJq0(IDZvWBGK18v3kLA1BZVo2opGBTcda1l)okL4RUIFbTU)vjA6R(1C6m)c0M4TiDVt32uxoEQHUqPVLvp5Q47EY9T(ozDYBLHsNJX55q3sSjUuIDzRI68UGmWdInQpQuCQcxqvqvg86QNEOQ6j(fBzrQPULKHiKGiBj9lPwsP80JbPoMva6CibiicuG)QiAR6E4iiXrzEs9xhSlvHcAexFiS(JDllL6dRdkictn3N7Sc30wLYQpscqXVmjW3kxBeM(Dlk2PSmtgGfa16IDklWdbfavapNLMhv2i9fmqLXLsv2nz4GQSDsiS(OBU5iDRgrFY1re9bfhrxcrN0w4)(oxspogprPCIHRH8wFX9iCKKMTtlZtskbYdbFcI6TdlUBKyJII2nA)OkN58JEm30JKF3LXtUgCxIdjuECHk4qCQHvoROTUKZHKywn9uLjXCmsIjsI5nAjVx)KyMmJQstYOW15IjBotq2CUvZFwsTriBoIdoq2Cowe10waKnhKnhPbfiBoTKI(2InNeWj3adNAqLZkwRlhfixovtpHC50m2QYdQIC5iTrBVo4Y5r8aPjoInEG0U0InEG0qkmLCu8isHztaOMiAszepjJ4aPW8yrutBbqkmrkmLguu0UrifMnOI(6KcZ8buzrgY9YWOc(s17I04uf5ZQoUUucIuNwn9esDAZyRkpyosDQ0gL)6G6u8FlVcKyJuNEPfBK6uK6ujhf4P)SrautenPmcVKrCGuNESiQPTai1Pi1PsdkWt)zlPOVgPovPGlVWVO2p9eHxF6LgPS1b3vW(T4LJSqGe5Npb86thJqi4WaJq0(IDAlWXF9PNnPOqCN(oDUYlRZLsWkGZpsJJ0351F7VwAUCWqhDPVpmkvUkl2hkLEfiuzX(Y5hb7CBZlYvvyKkCH)5vSRXxTgpGg4b0OA6jr5Yw)o0HfDyRIEsuCyfu31Y54eprrn(U9Nv4INOimjZZNyJNOOlTyJNOi8efj5OaprrncGAIOjLDoqKrCGNOOJfrnTfaprrPOwd3nsKrbEIIAjf9v5jkQUEeNACLZkCRl7CilMvtpvzwmfL)DrI0UJoSvspjkoScQ7A5jcG0UlTziC9t7EYAaknT4cxNlM8pI)(S4MTIpj1gH8pko4a5F8yrutBbq(hr(hLguG8p2sk6Bm(htGNCJmCQrvoRGTUKuGK5un9K0rMdY(i6Wwj9KO4WkOURLNgaY(O0MFW1b7J4VbweiXgp0VxAXgp0ViP7sokWFdS0iaQjIMugvPYioqs3pwe10wGd5j9)zVZODBAyOWWpl9MQe1jGcd0UGYdaVeOYAguTkgQPi0KI4zN0eOZzRU2jXn5CC)UBlQjX)hFYXUF)2PQuiaD)YE0iGUhWaDKcDNFcwcuqUVmbHDQFXj1XoDsNZxjxNCD)It8YbbFcUuPkfh(eWlheb1SXNGXUzJpb4tGYvblo)GiOqunXfDxnQd8jOTkk09a4tqdsfmAKKvblo)bkqhJ(e03eIUww5SQ2(cNdiM(fN8gIPua2l00v3LvbIPAR3g)qmnNrLZjzCYNZLjnhEvlCXo)zL2hbnh5OdO50wff6EaO5anh1OcO5mqb6llAogYXAHHUwu5SQ1(YOawo(fNGLty6RCxufwoQTABCWYHnUUGA2SG0g7MnlinqyQCvWgxpickevtCbEsJ6aeMTvrHUhaeMGWunQGnU(afOJteMSV1dumUVibbDQFXjqNgM(k3fZbDQARYhhOtzV8kOMnOth7MnOtbDQYvbR(ZGiOqunXfWlnQdqN2wff6EaqNc6u1Ocw9NduGogrNM(F6o5z72FfZF1xZ((6FSQyYULB)wwzBn)l1)v1TBZYhZ2(eISJiKYOqXX6)tt)ZNR5nLxXhlV8WBY(31E2IxVD9pV6UhU9x5lE7vRVBrI)a2sSmn7Rpj4mFy3A7BWuyzE9ftsCHJB6tcR(41QQXHkhKz1JPtBGS7tlsUz2Cd(SMNDYHU3zZFtA5hTXN52hY3nZa13()VEiHtMoA0dSz5VB2oRoIxntJZ1wRS6JyRrUp5CIbwYYcjp7gEJZmRL3N11uRd36YRXlV3FW1TUkG2Y7PReiJhLFr3C3P0wrzUZN9zT2L)HoSKOpXjVTKqkVErjHLewVItsjHvOPRUNvpEO1L5joEYfp0ubPMyWbh8qBeA24HgEOPCvGhAbrqHOAIlNp0OoWdT2QOq3dGhAzRy0iLOc8qBGc0XOhAtTMpmVqMiFmt2EVuz28m0sNAJACSVJWhV2(PSpntPplzvQ68HQJkN35X4TUl0I9aYfhRpx8(gN82EaPSfBiHLewVItsjHvOPRUNHn(zPRzjin)S(l7DgCLedcddTwYXT)BW9AMdj2aoGe8BG5HmAaYxbNHvbTgDa7FGOumDocW(6Oda73QIQEgaW(a23gvay)jvObSFY1mMLuaSVxUqa7)RIEAdxOKQlvQm)4JwNSJskgwmSPQtQyyf1UgF(AW671ze2oS(8vYqOHnxtLvpS5AQqAwMRc(kzuIGQy1KOmiCuhKMvRkQ6zasZ6oCn2nsAvWxjJjvOjnRKRzmlPqAwE5cpQ0SEwtr74USV(mxbWq6upJpj8kRdzgv2CcrBjh19os)92sMRCJIrZrI82YvNsN3MkTfocigdBQ6KkgwrTRXpYkbex(U9FQC3UaIPpgk0WMaIx9WMaIjGyZvbx3XseufRMefRNJ6GaIBvrvpdqaX)GwJDJuwfCDhNuHEhdiEyhrVRR8PYDu6CqXmxDknftvUMlGDhdBQ6KkgwrTRXheaS72EcH9h7(9Nbi8yXV()Cn5ps7w7yFIptNJG)Oo6a(JTQOQNbG)i8hTrfWFCsf6dJ)4n984kd9UQYNk2rHuamNC1j7G5a9rmSPQtQyyf1UgFmaOpA75d2d6J0vOeAyZl97Qh28s)c0DZvbDfQseufRMeHk1rDa09wvu1ZaaDhO72Oc6kutQqVPq3nS91ikmQbzcc70C1j7yNE1TFfVoE9C1jAoiKtWPsvApYjGMdIqdBYjy1dBYjGCcevf)ZoND7KWabrHFw8ojsWquVtEb8LWGyrjHijumgti(SB5hdftB3TDNwMz73DesOSNzMD62VZU1xvWMZxebjr3ex0DTOoWNG6QiPZa4tWzKk4UrAwfS587OaDm6tqOfenTTsRQ2qHZbet)ItEdXula7vA5Q72QaX0S9BJFiM5xrLZfzu58CDsZHx1c921pB0Ce0C0JoGMtDvK0zaO5anhZOcO50rb6(fnNCYP0gdnTPsRQ1qzualh)ItWYrMCL7MQWYXSDBJdwoCW1v0WMnK2LEyZgsdeMgxfCW1frqs0nXf4jlQdqywxfjDgaeMGW0mQGdUEhfOJteMCU1fkghksqqN6xCc0PYKRC3mh0PMTlFCGoLZYRIg2Go9spSbDkOtnUky3FkIGKOBIlGxwuhGoTUks6maOtbDQzub7(ZokqhJOtpc3PSIIXB1j3N8vCpOvWn)JVuvKMl6bfE8(QbmB0juLkvBoZQq5C3PzwxNMSz3fmD0ljVV4Jx3E1MPRFljBOM(8HpT)FB50VtwFAIyb6iliSTOgRdg8Ztha5MUh8CA2xVm541(Mj3oB50VgoF1SptNmE4I5t2Ht0x21vgvZvE)31l7VA0SvPBAoT490UB8VUvZ0(h2WAKqItEBnIwEnNsblfSEfN0sbRslxD)0f4LNTwCeE5zcIrXGts4L3fyyJxE4LNXvbE5jIGKOBIlhySOoWlV6QiPZa4LxE4AC3ivRc8YRJc0XOxEyJxRpiXgVEOnEb2Of7b0lowFU4HgN82EaTCuFOGLcwVItAPGvPLRUxHn(zzRvj0R8Zk)dx785nRCEUob7ZRO9ElkfJMJaSVE0bG9RRIKodayFa7Bgvay)okqdyFp7z0vsbW(2QkeW(NROYUHlus1lvkFU4HgNmhLukyBJc2FzVZGRCyyqGO1soU9FdUxDoedwGLMr63a5Pbrq4)yH7jeK5hVACYUewrtxJ7VgS(E1JW2H1NVwhcTS5AQS6LnxtfCZYCvWxRJweuhvtI8GWrDGBwpvrDVdGBwxHRXPrsRc(ADmPanUzLSMXSKcUz5vw4r5M1V1u0jUl7RGZNayidQN6Bc3Y6qMvLnDiAl5OHpr6V7kzUYdkQ6Je(TLloL2VnvglCyqmjSPItQKWkA6A8JSIbXTFA)Rk3TZGyMJHcTSXG4vVSXGymi2CvW1DSfb1r1KiB9Cuhyq8tvu37ayq8xO140iLvbx3XjfO3rdIlNrmADLxvUvPZbfZCXP0umv5AUa2DsytfNujHv0014gba7UTDiS)y3V(maHTfF7)Z1K)iJBTJ9j(mDpc(J6Od4p(uf19oa8hH)OnQa(JtkqFy8hVONFwzy0QkVQyRcPayo5It2bZb6JKWMkoPscROPRXTba9rB7pypOpYuHsOLnV0VREzZl9lq3nxfmvOArqDunjcvQJ6aO7pvrDVda0DGUBJkyQqnPa9McD3WXxJOWOkYee2P5It2Xo9ZW5RKRtUEU4edhe8j4uPkTh(eWWbrOLn(eS6Ln(eGpbMRcE58BrqDunjIURJ6aFcEQI6EhaFc(IubNgPSk4LZFsb6D0NGQjeJww5vvBv4CaXmxCknetva2lA6ACzvGyAB929hI51oQcBY42)NRjnhg1chB)ZMUh5lnN)zNZ3wAyyGW4Fw2Be2Bg4)E3(UitPOcdfwhic7dVTBZrN22K0Cn9U0FVtMd9EEYLRP)UKanNqJ34d3asKmjeeO5anhZOcO5KiJEErZPHC6SWWqlQmQAnwgfWYXpFcwoYmw5UOkSCmB128GLdhCDff2SH0M6WMnKgimnUk4GRlIGKOAIlWtwuhGWmufj9iaimbHPzubhC9ez05jcto36c5XXIee0P(5tGovMXk3fZbDQzRYNhOt5S8QOWg0PtDyd6uqNACvWU)uebjr1exaVSOoaDAOks6raqNc6uZOc29NjYOZr0PNH70vsXTh0j3NMzCpQvWn)HVuFKMB7ffw)q)aMn6eQoLQnNz1QCU)YuR65pvkRDyXN)0tX6XpQ(77nz5lFZg)bQSXYI91kOC1ZfV9(h1kB3Rfvwt5tN(PJQB7MVl2DOBxB9D30AT(LD8VTrU(VH)2nFT6Lpl3V86x5)F)6QN70pdMHn1wILs1hIf1evMzHPMfy1GFgiT5J285NpPLRS3fKWscRp(KwsyvA6Q73uM(sl(t7hv5sFPzrMJxytFPN6WM(stFPnUkOV0IiijQM4QBIwuh0x6qvK0Ja0x6RqRXtJ0SkOV0jYOZY(shBgXqRRmQYnw6CqX0pFYBkMA501a2Dsy9YN0scRstxDVqaWUB2viK)y3B(oaoxwCVZZ1j)rUv0NTVXNrhJG)OE0b8hdvrspca)r4pAgva)Xez0Zm(Jn0tNvggAvLrvSXcPayo(5tMdMd0hjH1lFsljSknD19YaG(OzxFqEqFK7XFff2SPFN6WMn9lq3nUk4E8xebjr1exOsTOoa6EOks6raGUd0DZOcUh)tKrNPq35I8xitowMGWo1pFYCStxm48vTMR)d7C2Tsddeef(TXBSOuuVZ(c4lHukTIqHcMkEJ4ZU9hfIstMjzNSzMnFER009mZSt38D2DtohsTUU4K6ADUCqWNGPkvPYWNaUCqC0WgFcg7Hn(eGpbbxfS58nrqw0nrIUBe1b(e0vfzDgaFc(dPc(1ipRc2C(zkqxI(eKAbrFBRmOQnv4CaXuxCsnetVaS3PLRYTvbIzy73w(qmRVIkXfz068CFsZHRAHj76NdAocAo(rhqZPRkY6ma0CGMtyub0CYuGEArZPMCASXqFBQmOAnvgfWYrxCcwo2KRKBQclNW2TTmy5Wbx3rdB2qAJ9WMnKgimdUk4GRBIGSOBIe4PiQdqy2vfzDgaeMGWmmQGdUEMc0Ljcto36gfJtfjiOt1fNaDQn5k5M5GonSD5ld0PCwED0Wg0PJ9Wg0PGon4QGD)PjcYIUjsaVIOoaDAxvK1zaqNc60WOc29NzkqxIOt)5VVE6mlOQtSRQo8O3U(59lF7L17VEXTR2U8JzB2T69QfZN96MfhjsOf)vRsU2W63N3HVQBwTRAF)boDcywV)0dAAqFyd6QPeNutx1l3uIuWsbRQ4KxkyDA5Q8cuWoGWUYfSdyyuUfV0zjaJg7agHHn2bGDabxfyhGjcYIUjsqCJOoWoGUQiRZayha2begvGDazkqxI2bCvJ1dZ)0NiFQxS9Gxz28p0sTTNZV07i849n)rowMf05snk1yoP6IY5of)ERCJwShWV4y18WtnoP2EaVCAbOGLcwvXjVuW60Yv5vyJFwXAvctk)SQ)Y1IVVzRZZ9jyFULNNSOucAocW((rha2VRkY6maG9bSFyubG9ZuGgW(k7zC(F(n7DgCLedcddTwMJB)3G71Kdj2agqI8BG9HmAnKVs8mFPayFVCHa2)UIE6axOKQlvQm)XhTozhLumSyytvNuXWkQDn((1G13R7iCCy9zG)l0YMptLDVS5ZuH0SmxfmW)lrqv0njkdch1bPz1QIQEhG0SUcxJtJKwfmW)xuHM0Ss2ZyvsH0S8Yf(PsZ6znfDI72(H04xamKo1Z4BcVY6qMvLn3q0wYrDFI0FV1YCNhumAosK3wU6u682uzSWraXyytvNuXWkQDn(rwjG4YpTFQY94ciM5yOqlBciE3lBciMaInxf85owIGQOBsuSEoQdciUvfv9oabeFdTgNgPSk4ZDCrf6tmG4HDe92xzQYDu6CqXmxDknftv(mxa7og2u1jvmSIAxJViay3T9gcNp29Rpdq41IF9)Z1K)iJBTp7t8z6Ee8h1rhWFSvfv9oa8hH)OnQa(JlQq)X4pErpp2zO3UktvSJcPayo5Qt2bZb6JyytvNuXWkQDn(AaqF027hCg0hzQqj0YMx63DVS5L(fO7MRcMkuLiOk6MeHk1rDa09wvu17aaDhO72OcMkulQqFOq3nC81ikmQbzcc70C1j7yN(RB)kED865QtmCqiNGVkvPZiNagoicTSjNGDVSjNaYjWCvWlNFjcQIUjr0DDuhKtqRkQ6DaYj4gPconszvWlN)Ik0NyobJAi6TTYuv7OW5aIzU6uAiMQaSF621)zNZUvAyGGWOplEJqVPG)DxFxKQeuHIfAkic9H3K2AzRMn7UjtsMzZ5oPw05BMzNm7z2nDlwfUSkqmnB928hIPBhvbBYO1156KMdVQfMT9pB0ye0C0JoGMtQks6ia0CGMJzub0Cgjh98IMJJC8wyORfvguT2xgfWYjo)eSCKjwfUOkSCmB128GLdxCDfz2CG0MAZMdKgimnUk4IRlIGKOAsiWtwuhGWmvfjDeaeMGW0mQGlU(i5OZteMCV1fYh3xKGGono)eOtLjwfUyoOtnBv(8aDk3Lxfz2GoDQnBqNc6uJRco9NIiijQMec4Lf1bOttvrshbaDkOtnJk40Foso6CeD6z4o(skU7Go5(4MX9Kwb38h(sTrAUPnkS6X2bmB0fuELQnxz1OCE4YsR61pvkRzyXN)0t26XpQ(7hnz5lFtN)avUXYI91kOC5lfV)XN1kB3BfvUMYNp9thv3M1FxS7GFV2Q7VTXA9l88V1jx)xZFZ6Vw(62Y9lUEl))7xx9CN2zW0TL2s0kvBiwuJvzMgtnlWQo)mqgZhJ5lo)KwEL9EdjSKWgJFsljSknDn8oLzU0I)0(bvUmxAAYC4mBMl9uB2mxAMlTXvbZLwebjr1Kqtt0I6G5sNQIKocWCPVcTgpnsZQG5spso6SCU09nJOR1vgu52x6CqXmo)u0um1YTRbS7KWgLFsljSknDnCJaGD3SDiK)y3D3dqW2IBDDUo5pYBf9z7o(mAmc(J6rhWFmvfjDea(JWF0mQa(JJKJEMXF0rpERm01QkdQy7lKcG5eNFYCWCG(ijSr5N0scRstxd3ga0hnB)b5b9rEp(RiZMd97uB2COFb6UXvbVh)frqsunjeQulQdGUNQIKoca098g6(pSZvqZPjqu4FlEXj26KcAjNKl9ypKl0ZWqu0YuJ2bizM0XP)27BbcrSOaYQSV1VCliS(((23(579Ta3m)AemDxIeTMA6oEr(ljsUREccVtBgpXoVthC25Rixh56nJNWlheSpb3QUkPh7taE5GOqHn2NG(oSX(eG9jG5Oa3C(sbqYqnPo3D5ioW(e0wej7zaSpbLCQa)AKkJcCZ5FLiADCFc6AcX5kRCrrBxnNdMy2mEQXMyQkg2ROPR1lRctmzRER(BI5(vuvBrgNCDUA6MdEvlCZw)mtNJGBoQdoGBoTfrYEgaU5a3CydkGBoxjI(2YnN9GZrfgoxrLlkw7QhfWlNMXtWlh5mxvVOk8YHTQT6Hxo4bxxHcBCdP13HnUH0GfMmhf4bxxkasgQj1z8ehXbSWSTis2ZaWctyHjBqbEW1VseTEAHjEU1Leh3vlbH1PnJNG1PYzUQEXCyDkBv51dRtXZYRcf2W60(oSH1PW6uMJcC3Fkfajd1K6m8IJ4awN2wej7zayDkSoLnOa39NxjIwhTon)V)(9mVGIt9UkMg61bEj(rRcs(S9xc3qx(R(jbJdxAFxBS(A76f0hDFXaCpjGU4THzPrPbv4FigqKE8S)gFkaNz(vdJHP)ZVNN4rhWYA0W3)W7k5J1NOfWdxnFX7MvnJyXcKoZEQXWQZxlniun9w7HFI(fvT7Nyp3F9AVSd7Tomoz8g)NdSfaS4Ce8XHWUIHIOWNOii9msPWSWQ4yPK1a5mqf2xs5LB)i1iYFvqk7kwh3WVQGnIRA8lXbu(0spIOTnfFRvC5UoVgeftJG7JtmM8GPPPLHXexhbVf7(dxhXzpnpJk27NV9uu4c64pAk(W8G09BUozXHRt5mC66JctcIc9DDoTmst0WQo9TI83tjwUxEM10r7oP3HJkD2IOipeoyDC6IJrIbRbAmh)xR7b8Pbv9r4Csk1Z8(h(y(IPtj74VXwzRYBW68txnrDIz762gqcHIwm7cHcLdk6HqHv9cfJCtO6QosLsr()kOC9rTyD9G33XxAqYBsJLu6bL0NNxRdqjD73DDwUD(lXIKakty6rYek6Y6Cth4t)AenKK1uXe0ubAQq1wcJAfunOOh1kGMkGqHYJdiu0hXnxBQ44AaxAg7)k0MVl)QS7hLK057YRYC8dOTSg2ww6mb6kdDL13lHrXwkhu47VgGUYGqbRWbek6J4gDL1wgdDL1dKoFxE19UY(h7DfUBAdde(zz)PQ9pvWyW2K22RseveOrcktdOvBkp8ljoqStIpBSneBNV)waN77UZNV7RX3z6gQqSQSzOQmuvMFTfgjB5DqjCpnavLHafbfoqGIHqUd1QY8yvkEb8gR1u87Z3yOlvtWDHHk)lC6c2Qxy3(yBXY2O4Q(l8Q0ZB3AVuN)bRwE4vXVptAOQOz9YcHinzD2FeTp1whUpwSBiX)bn6TNAAGtm8uBufHOIahVVCJOS07skUIp84X9B2Sn95DfE)7k8JFGvt3Z7pD8q2Q05551)HpYo(A2Bv2kPUSND)6AL4Cmn7r(fz2HQ4a7pDi5LmZ3Qi4s(JFovsF26ZgQVMt7ixlMPBp9w6HKTLYsTtZ1)0UOy4xTwBgwi18jEhf74y)EAsXg8DzPhkcSsKn7V4U)PDIi)KjkXQ7(xs5DMS))JWfO6RMGQUWIklDv4I4dDkMzVCYjLFZKx2UF)QK1foO)7VLQHVn8QbPLm4ERF9RPDbU)Uj4UfSNnSo1TjuRavtNycS6IlBmN3wV623J3(9QNk7C47OE4M7w35knxcCzN3tb8p1z)CEEBvHleyHR2plTPUjWXj7nsy7JGPWvRhAZtGiBOlxIDXeIQESkUP8uj4O7YA09M)sAoQs5Tx9g7(13xAS6CWb4UhC3p0vkdk58nOehuYbU7rGcVhhiqXqi3G7ENRsb39JvU7fRgKI7CcoBjoEJ2Ct0rav8BT3tXGrGH2Z2HENbgshcgKN5pGAbDwCRvv9ogm6vvvYCfLI6rf57Ltmimgrtcd19ju2OWWx9khTDo9ftuxYtaad2WWi(MggHF20S2HmQO5Ul3c2GZdedl6x3DI4tSsQijrNJvQgjgQpxPEMyGHIrNyIZJKq7tueApaHxWwsFpUxbpqMn)jn491cb2E59kCLcMZvv6lfKiPzYyyXrT4mjphgKNj1tOLBCQslKNPu47YuoEmIaxMwJwyB9jmn4YnfUwZBhO4uBvL(uCA9O(fuCckod4iVJbko5tXsDohKB39vIEMdIEgXjvhOwjq0Jhbeq0ZvJixBcarpGONqcgGON7NUESr0dhEKgEW0ql3uWAn3fGMhTvvGMhNzVuhEf08eWXDJeAEwG3KnFsUXBY2Wl34nzdeCgfH2bbNobqUiMIssPcrGacoVAe5Atai4eeCgsWG8mjqWPt11XkbNYrKQ4d5sBwgA4pj)hRKzvqTkOwfuR6o7L6a7GAvfbQ85i(rc1Q4sc7vYnOwD4LBqTkOwnkcTdQvDcGCrmfL0HfIabuRE1iY1MaqTkOwnKGbE3rVF66OKAvYwmQ4JrVwNyPwqhxjTjwJYN9cS0QheZ)TNOQ3RsSzrj1Vde(IGtGrpw2tGseq2aAg7iqriGdeOyiKBrBGUnJDzTGBgQTDWakL5qjW9)S3z4rsmiiu4Az7IR4sXFZE)YlJrubna(vazgEi7lKpz1s5ED9F9C7wg8NM3RH)LCV1Fx)HDT(9)Ebw1UM(zZSvV03SK1pHfwaloUvSv3mChmChdmCh(5eG)d1Tu32DQYp1ToTQvgjkdLuTht5B)xQCzOKOVZLg3musVFCZqjXqjLcRDgkjteKfEkIdssefcdL0WkY6LagkPBK34DsUwgmus7lxNZHssDrXSUllvVQb3bJZUtv9Z40p)XlHnp1TrSU1PvTYDgaB(ApwqAz4eyZx(TbYnl38N7ELqjx5gN8xdg0vjiu6iHaHYHvK1lbqOecLrsgqOCF56JJqzHGE0FywVLLQw1WlGZt3PQiY5b(Ku3gX6wNw1k3xa8jR9ybPHHKWNK7kgxf3m7WVFCZSddz(uyTdzEteKfEkI0uJOqGm)WkY6LaiZdz(ijdURy2xUoTK55YIXS8SAGHWwT7uvezR(z6Ywk5PKFGsEoksK(AfXMzy7eQ9ybPlNKSDcCuK4Q4MTt49JB2ob2oHuyTZ2jyIGSWtrebCefcBNWWkY6La2oHBem4DsUwgmO)7lxNYTtqDnXSMllvUQ52bIZUtv9J40pu9DAvRSbliodSZ7jG4SSfl5EoA(ZDVc6Ht0HtUP6GUkbOhhjea9mSISEjaqpa6jsYaqp7lxFAGEk0ZJ2dZATSuXQMDbyE6ovbMhZwVKTxbZtG9DtcMh(JX7Q4Mjz79JBMKnaCMcRDaCAIGSWtrekvefIrao)L9oJ6TnHHIc)BPVebkstlBTz9HT9W(b0xyp7jwkBnAvRtattvIF8dijTaf7RbCH71582wuC79yFY1MVtHWeRKy2xL0ljsLaaNN97jbaNoDU2xbCI7lENnnpzEHaTQ1tvaTQZwVOBSd0QenQ4ChFpbTkUjHzvDd0QlFDd0QaTQx0AhOvDIGCrpfsCysuiaT6GvKRxcaAvGwvsYa)TJoFZ1EjA1WtmFYsYR(jM9MVNC3(FFBrXf5XP)mPSyZ(2H)v9VV7JFmj9z6z9OKYPHt8XABbcdvr)4HD)ntDZgvU6MRuFvfDS0vFrfDGrLkkD)Fur7s3NNKUpwffmaiCbAo89LgzRzfKxDxCtrHMZ7xodgqbTB1ZI7WRFuzTETYDEU9XWvTa795pfC96nny52A4bpTCVEZBdlFVTEt7EilFDdGGv))JBuy0F2yH4(4)1PuRFjRQ0MdwxHw)E0vNv(1lAWVSS5sNFJx3WQ9UkR2wDwT4FLmAV2t1q5pKxweB7wdFqtnuphp2IGYF14Z9VWdmEqV1OQh9OFvB0nG5oeUXeNQSpCd(8eqf(w4BLOVLPUw6ljaHY13WOpy5YjxekNqW94fbcHq5wK6gHYHq58Iw7iuoNiix0tHmifjkeek3GvKRxcqOCTzVH9K4TmqOCZ3CTxgk3kToInv2Lr25yU0Y2RyljNoeNkmDRH03vm8XlnmMkRMq)aLETkZpz1REEVnB9s3WfjiGeeSpbb(CB9aFl8Ts03Yuxl95UrYx9nmoFSHZSKVAEL30xkQXpUZv()4b6(5mRfHUkb()msiG))GvKRxca)FW)xsYa8)NV5AW)36ohZLwa)FX5eb))Uss3EVGIkOOkrkQW3cFRe9Tm11sFQBq)VVHX5dn4F0)X3ZhSQUX99YYx34(Eb5E5fT2rUxorqUONczwfsuii3RbRixVeGCVAZEd7jXBzGVNpMV5AK7L1DoMlTGCVeNt8ml3l9IIAZxJogQM1MToMhBfQzZqsgPIM(6Gzgi8PSeZjgLltPrV3uOPoNl5ogtoSjKlN1tv2NlhFEE0H8KHVvI(wM6APVAwKNCFdBI7()Qkx)lpz8CuKv1nYtE5RBKNmYt2lATpZ5j)F25mkjjgeei6zzV)xY93utLzavIPB8Dasv2aPd5H6oKhZtwiHW8KhwrvNcyEYFqEJVjjTm4CuUVyDlNN86ffZ6U8O6DzWDW4mDOkpJtDoZmWMN6whRBfTQnUZayZF3JzsldNaB(R)BqCZY)81DvjuYn92j)3GMMLGqPqcbcLdROQtbqOecLojdiuUVy9XrO8IG(Q)WSElpQAxgEbCEshQCKZd8jPU1X6wrRAJ7la(K39yM0Wqt4tYDrLuRB27WV)6M9omK5BH1oK5lrqv4Pest1rHaz(Hvu1PaiZdzENKb3fv7lw3wY8wEF5ikLQvbgcB10HkhzR(30LTuYtj)aL8CvKe93kHnZW4eU7XmPlNMmobUksKADZ4eE)1nJtGXj0cRDgNqjcQcpLqeWokegNWWkQ6uaJt4dcg8njPLbB0)9fRB54ewUMywZLhvUlZTdeNPdv5rCQdvFrRAJnybXPXoVNaIZRTyf3ZXpFDxvqpCJoCYnvBAwcqpcjea9mSIQofaOha94Kma0Z(I1NgONl65R2dZAT8OIDz2fG5jDOcmpLLVITxbZJX(UnbZdhmEPw3St2E)1n7KnaC2cRDaCwIGQWtjekLJcbaNdROQtba4eaNojdoy87lw3vaNCU4llmVmVqqRMoubA1YYxXg7GwnWOszh)MGwLdjSuRBqR((RBqRcAvfS2)N9oB2PXHHIc)Sm7MUbj0mGMfSIha2ewhuOebvQIrQjsiK6dpjfQ6pkX2j215ED(2GyJB9X(KRT)onj(kd(TJggbfIAkwXHPrHaA1bROqpfaAvqRQjzWVD04nwNKOv)b5tF2IRB9mJS8rSe0T3iwCoNHDYik6Uo2WD)1cbALEvv)AvNxE1PE(ZHlV(DvzD7hy1vpx(2Q3Fz72FvxS51YM(A1tF)F7(6wx8z5Mdxo2HqAgf2tF(0cSlwKxN)W)YFmp7N(B(95zFZ9npB56IpA(7Mv1LBwvKN1Yz0z02ghwpYIV)dS576QL)VQE8KK3XcF0T(IovpGXnspXZHk3tpropIvX3IVvJ(wH6ATFMds9RRMj5DlrQFkHNusK4eP(nj9Bs9Ju)sIs7K6xqeuiQPynPgnkes9BWkk0tbK63PS3ynjzlds9lEJ1jzQFe4xe6Le438mWpFl4sccKGG7jiiN7Bi8T4B1OVvOUw777MKV6QzsEBdZSKVo(K32pkQXl3Lk)FEIXpNzTO0zj4)liHa))bROqpfa)F4)Rjza))4nwd)FNRCelTa)F15eH))5sQV1EHIkuu1ifv8T4B1OVvOUw776g6)D1mjVPH0J(pVirev)M77LPVFZ99c5ELeL2j3RGiOqutXAwfAuiK71GvuONci3RtzVXAsYwg8IejEJ1K7LZvoILwi3l15eNz5E1VOST4RrhJTI1MToMBBlQzZqsgPI8FEWmde50TuZog1ltPrV20ctvoNYvm8oSjYLZ5Hk3ZLtopp6ipz8TA03kuxR9tZsEYD1mpx9)Ik30lpzEokkQ(n5jp99BYtM8KtIs7KNCqeuiQPyndqnkeYtEWkk0tbKN8zK3ynjrldUpkJ3yDsMNS)MIXwD5IQxVb3bJtNhQCNXPCUNzGnp(wn6BfQR1(odGnFxntjBzyoWM)4ZgyFZYgVC)IrO8l25SBLggiik8ZI3i0Bk4Vx13fPkbvOOqtbrOp82KwlXA2SB2DsYmB(UtQn6EMz2t28nB2ejuYj92C(PbnAwccLksiqOS3ks6uaekHqPLKbekhVy9SJqzdb50FiwVLbvTjdVaopbhQSiNh4tsDRfRBvAvR)1faFY2UmJSGHmHpjNfvQACZEhE6h3S3HHmFwyTdzEreKeEkEPPArHaz(ERiPtbqMhY8wsgCwunEX6SLmVjpVCukLQubgcB1GdvwKT6vrx2sjpL89OKNJIeFpTI3fZq7eA7YmYQCYK2jWrrIQg30oHPFCt7eODczH1oTtqebjHNIxeWwui0oHERiPtb0oHliyW9KuTmyJ(pEX6SSDcjxteR5YGk3K52bIZGdvHJ4upu9vAvRFdwqCAyN35aIZMlXY)Ao6C6Uwb9Wj6WCEr1gnlbOhfjea90BfjDkaqpa6XsYaqpJxSEUb6PHECApeR1YGk2KzxaMNGdvG5rS8LF7vW8yyF3mbZdVy8QACZozB6h3St2aWzwyTdGtreKeEkEHszrHaGZERiPtba4eaNwsg8IXpEX6CfWjVx8IfMtMxiOvdoubAvXYx(n2bTQhJkn74NjOv5LewvJBqRo9JBqRcA1SWAh0QIiij8u8IdZIcb0Q9wrsNcaTkOvTKmyVJoEX6SeT6jKpUklUPQMjs7JXsqp(GAX5Cb2Porr32JnS6EpeOn6Sk3A1MtVAvp3DE(v9KOdsZbm5tF8XrB9NvFfHZE(8xTXFIQyzzXUkzuU85I3E)Jk5T91IdXNYNo(t1sCZ6Vl2UFV7y3QBVUvJ)fU(h3OQ)xjSz9xlF5ZYDl(lnG)9RpCxOU5Ze3KCjwCvN4x0ZWYmlw1U4SI(oI0sqD1sWFyVZ2KyqyqGONLE)VK9VoDSs(Ge3L8oaotwar8TXO4wcQZ5g8hQBPUT5qLo1TIw1g)I0yL9Dx2Kp9FPYfRSzUZLUUXk73FDJv2yLDjATJv2PiOm6PeA)OJcbRS7wrzNcWk7FiVXZKKwgyL9(I110k7PlkgT7Ys170G7GXzZHQ2zCQZNRdS5PU1X6wrRAJNma283DzMmYWjWM)67gepS8J3URkHsoO2p53g00SeekfsiqOSBfLDkacLqO0jzaHY9fRpocLxe0F7pmAVLLQ2PHxaNNMdvoY5b(Ku36yDROvTXZfaFY7UmtgyOi8j5pmGuRB27WV)6M9omK5lrRDiZNIGYONsinvhfcK57wrzNcGmpK5Dsg8hgyFX6YsMNFXaPfNNgyiSvBou5iB1pdx2sjpL8DuYZrrs0BReomd2jC3LzYuofXoboksKADJDcV)6g7eWoHs0Ah7esrqz0tjebSJcb7e6wrzNcWoHFiyWZKKwgSr)3xSUK2jmDnXOnxwQCNMBhioBou1oItDO6lAvBCdwqCACN3taX51rSIN54XB3vf0dNOdN8q1MMLa0JqcbqpDROStba6bqpojda9SVy9Pb65IE(B7HrBTSuXon7cW80COcmpPLVIBVcMhJ77wemp8HXl16MDY27VUzNSbGZs0AhaNPiOm6PecLYrHaGZUvu2PaaCcGtNKbFy8pfR)YENnR0aXqrHFBeCJqXFabx5dq3mUoqPOqbHcTvCJp82rRqTKj3mZCBM7n9ZfUlAo3CMBY8D6mv3ADTc4KNlE1kZJMxiOvZUubAv1wVKBSdAvHgvwUJFLGwLhsytnVbT60pVbTkOvRIw7GwvfbPrpfrCyEuiGwT3ks7LaqRcAvpjd(SJwUADvIw9WpHM3wV8JTH5Zc7cZFm8sO5WF0WZHMFPhfAw((Ip3)7nR296MvlcnT0kYgqwsTF087V)G7)FDZY1B3nCEu)quBWJ(SUE0J6gmyhzPkFgS25f1i(w8TE03AuxR8jxi7GydZjhPHSdoxsxJ7kTk4wt2btY8MSdi7GQO1ozhOIG0ONIiVxpkeYoO3ks7LaYoGSd8Kmi7GYvRRYSdUQthXSw7Ya7CukT8W9MLKZjeN(k1NG9y3XWt3LymTwnNEbv3A1Nxzfvp3MZwVYnCjbbsqi)eeSZtFa(w8TE03AuxR85Uj5RydZYhB4cl5RJVZB5Bfn5L7wL)pV3PVKzT40vj4)BiHa))ERiTxcG)p8)9KmG)F5Q1W)p7ohLslW)3Dor4)FQK6AVxOOcfvpsrfFl(wp6BnQRv(u3q)p2WS8HgQp6)81rGPM38CVm9ZBEUxi3RQO1o5EPIG0ONIywfEuiK7vVvK2lbK71)zVXEs2wg81rq5Q1K7v2DokLwi3l35eVWY9QBrjT5BshJuZ60wN0JTf1CAijdurJFDinde7mTCZjg9ltPbV301P6CoL7ym6WMixUSlv5NlNDEF0rEY4B9OV1OUw57ML8KJnSrU7)zvU1xEY8Eu0uZBYtE6N3KNm5jxfT2jpzveKg9ueZa0JcH8K7TI0EjG8KpH8g7jzAzWZrz5Q1vyEYFZoNrjjXGGarpl79)sU)MAQmdO2XqJVdqQYgiDipuvuumR7YJQ3Lb3bJZ0HQ8moRZzMb28u36yDBrRAJ7ma2839yM0YWjWM)6)ge3S8pFDVQek5ME7K)BqtZsqOSqcbcLdRi1PaiucHsNKbek3xS(4iuErqF1FywVLhvTldVaopPdvoY5b(Ku36yDBrRAJ7la(K39yM0Wqt4tYDrvPw3S3HF)1n7DyiZ3cRDiZlrqk8ucPP6OqGm)WksDkaY8qM3jzWDr1(I1TLmVL3xofLs1QadHTA6qLJSv)B6Ywk5PKFGsEUksI(BLWMzyCc39yM0LttgNaxfjLADZ4eE)1nJtGXj0cRDgNGebPWtjebSJcHXjmSIuNcyCcFqWGVjvAzWg9FFX6wooHLRjM1C5rL7YC7aXz6qvEeN1HQFrRAJnybXPXoVNaIZRTyf3ZXpFDVQGE4gD4KBQ20SeGEkKqa0ZWksDkaqpa6XjzaON9fRpnqpx0ZxThM1A5rf7YSlaZt6qfyEKLVITxbZJX(UnbZdhm(sTUzNS9(RB2jBa4Sfw7a4uIGu4PecLYrHaGZHvK6uaaobWPtYGdg)(I1DfWjNlEzH5L5fcA10HkqRklFfBSdA1aJQk743e0QCiHl16g0QV)6g0QGwTfw7GwvIGu4PeIdZrHaA1HvK6uaOvbTQtYG9o6(I1jqR(p7D2TsZdeeg(APNi0tk4pFEuVxKQe8tOOqJGi0lEBs1smMK9VjjZS55mP2O77SZozYZ72TwqgToZrpJ8PV0IRRYzIS8XujO7)NAX50c70GOO76Xg2ENdc0gDvv)A1MlV6up3Ez9v9IOtsRhyYF)YNhT1Vw9v4p75lV1g)jQILLfVxjJYnpw8)xETsEhEU4u8P8HZ)uTe3V7ZIdhp2FSB7nx1zH)199pUrw)psy)Up280BLVV(30a(ZV(0DHgMptClYLO5QbXVONHLzAw1U4SI(oIyjiwcgGLG65CdEf5TK36DOsp5TknR19dsJv2DDzjE3)rvUyLn9DoQJBSYE(h3yLnwzNfL2XkBreKe1uCA)OffcwzhSIKEkaRSBrEJ7jPAzGv2txSopTYo5KIyRUmQ6nzWDW407qL)mo1ZhxhyZtERfZBvAwR7odGnFxxMrAzyjWMV5Zg4Uz5bxURvcLCqTVKFAqJolbHsfjeiugSIKEkacLqO0sYacLtxSEXrOSHG6T(qS1wgv1Mm8c484DOYICEGpj5TwmVvPzTU7la(KDDzgPHHmHpjFddOQXn7D45FCZEhgY8zrPDiZlIGKOMItAQwuiqMpyfj9uaK5HmVLKbFddmDX6SLmpFfdiwCozGHWw17qLfzRUk60ws5jLpGuEoksC90koBMb7e66YmsxozIDcCuKOQXn2jm)JBSta7eYIs7yNGicsIAkoraBrHGDcbRiPNcWoHwem4EsQwgSr)NUyDwANqY5eXwCzuLBYC7aXP3Hk)rCQhQ(knR1DbwqCA4kVlbeNnBXYDphdUCxRGE4eDyj3uTrNLa0JIecGEcwrspfaOha9yjzaONPlwV0a90qp9wEi2slJQytMDbyE8oubMhXMVCxEfmpgUUBMG5Hpy8QACZozB(h3z0oz7R25QR32egk6VL8ckmPHYhL9Hu6EypmTN6lzpdZfCsScjuzCAvRM2V9DnyCWemK0stcmxPwPwd23Z5E812hi18MS9AQj2tomP5dgF7aO2OMsJMs1fbIXGZtgrTDkWyWPXGZUemmFW4pFCDF1GtZNl(wJMFZ(fASw9OPkJ1QTw(Q5c7gRvBOq11Cf)EI1QMpKWxvXTXA1lFCBSw1yTAVO0UXA1wbqTrnLgTdRlceJ1QNmIA7uGXAvJ1QDjyyE3rpFCDV0AvXxEZxehSlX7UXEm4hJ8(L3CrV69DV5z2h5nNSf6NhrmS38akHHPeK38HNKlzXrHqBoYEYbkSg(SvM0knmjVaCcxXSbTfbH8SX3mAKv6V8qaZh(dUU2w5nouXWRpaZRTwgeMBQ1mGxLyF2TthzvTgwPtGT87Ad8aZBEiEbAxedOdGzu5K9eqzyUNVcqrr(z)IFejb6q(p93I2WzqeFiUBIgU(Eict7rfUol8LTLsQdoiaGUDkVB3LGbPWcFGr4aOyhXq0LyMt8owcje7wvVidfqkbc9Gv8BPyScdZn6IEeDDYAYwLXCfgfXwXZIZGsfwdzXlxgHD2aZf2aYARYb1EZtlgb5QlPwsPXu5eVwNOVEIWwr26ARHMCBGMeJpoA3wCcKdbzIWb1lE0l56IbxP0ZN0KEwahk9fcubIIxYNFGe61kZvtCV8GfWYNBivjZvBPO8HUCTGHYRsu9(E42ZtOd01ubauSnr8x7nMgkqPNkUIG4eMy)(VJXuekGNE1fqYMZIg(DEPt1711PjYsk6VOtrJaza2FbHIRuvuOD1hbsXg2RuUc4baSFvdyZZAQiDOarYCkSWw5)ucdfa7ubQ3xUfj2NEfG98TJmP2TJeI3edda5f(wHOXiQcFKGz8L3tC44IbF7FW1ZFQAdYPTdATOC4CZjntkL3psoPuOAqvRKvrnMZkWQwOpw3UGsEI8a2NVFNdNv)i2hw7AdbZ)FSSviDhj0hUFyvTSwp35mnqB6jnj(shXQISYBVRyKkwjb4(r1UoLELNMvWY2e(yN0ZBPx2kg)pkUInWg1Zwf7B3QD12RajX(tADWMzYvgCOKs)U6PFTeE9j1Mgtw65s8N6NHKe)vpFpfMxXrem5koo0pDVJpx1rIKtAvoEAPfPQ50ZhJfecy38rnRZRJchj0DQD9Vma2kxnpkeHqPdHl1ahJbb69B7cGVEGZTaoNKs96SaP7Gdr(QJMs6bpK6Sz5hX886TcSPIz)5T9QfAkuCczxtHIRoO0pku42CHc76m5LIw)Q9sF4G8xItOtCQ61ltHt1xe49MYkNQ7mAu7spxGB6WvoursL1omYL2nW7kAJYIJpP8ebNiFAsvu)6)ThiiC8y0o2Qy4qT)eVMer(7Vh(Jyk(rmn7c8(3]]
)

-- The hand-built lists the wowsims.com packs replace (wowsims packs plan, P9): a saved choice of one falls back to the
-- spec's default.
spec:RetirePacks({ "Feral", "Guardian", "Balance" })
