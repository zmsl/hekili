-- Hekili_Hunter/Hunter.lua
-- The Forever Hunter (Beast Mastery, Marksmanship and Survival, one spec a talent tree: Hekili:NewClass): the Hunter
-- kit with Forever's spell data (ranks, costs, cooldowns, cast times and durations from the Forever DB2 at build
-- 1.60.1.70338, wowdb), mana under the five-second rule (the Forever Hunter spends mana, never focus), Auto Shot as the
-- ranged clock's anchor (`rangedSwing`, C7), Summon Hawk's guardians (two at most, 18 s each: RegisterPets `cap`, C1),
-- the shared cooldowns (Arcane Shot and Summon Hawk; Aimed Shot and Multi-Shot), Raptor Strike on the next swing,
-- Mongoose Bite's window from the plain usability read, Immolation Trap, Resourcefulness's cheaper strikes and traps,
-- the time to the next main-hand swing (`mainhand_remains`, the weave's Multi-Shot gap), and the default priorities
-- (the wowsims.com packs: the Turret lists are the default, the Melee Weave and Survival Melee are picked by hand; no in-game check yet).
-- Research: docs/research/2026-10-15-forever-hunter/research.md and the class-completion research §5.
-- Unmodelled: ranged haste on the auto-shot clock and Rapid Fire's +40% melee haste on the main-hand swing (Rapid Fire,
-- Quick Shots; their haste on Aimed, Multi and Sniper Shot's casts is modelled; the core's aura field `swingHaste`
-- (C5) can carry both, not set here yet: one multiplier for every hand), Quick Shots itself (nothing applies it: its
-- Deadly Aspects roll is unobservable, and whether the player aura or the Cooldown Manager shows it in combat is unprobed), the pet and its abilities (D6), Aspect of the Viper and the other runes no priority names,
-- Improved Aimed Shot's +2 s cast, Sniper Shot's range buff, Expose Prey's own Mongoose Bite window (the usability read
-- covers it), Resourcefulness's second effect (1242688: the 30 s aura follows a crit, which only the client's aura read
-- shows, out of combat or through the Cooldown Manager; its `share` entry is in the mana model) and Rapid Killing's buff
-- (a kill proc nothing here reads).
-- Credits: Hekili (registration API and pack format; the on-next-swing queue read follows the Warrior's Heroic Strike).
-- wowsims/forever (MIT, ui/specs/hunter/dps/apls/default.apl.json, the Melee Weave, and sim/hunter/) is the source of
-- the priorities (tools/wowsims/specs/hunter_*.lua) and the reference for the Summon Hawk, Sniper Shot, Raptor Strike
-- and Mongoose Bite rules; no code is copied.

local Facade = Hekili.Client
local UnitClassBase, GetTime = Facade.UnitClassBase, Facade.GetTime
local IsSpellUsable, IsCurrentSpell = Facade.C_Spell.IsSpellUsable, Facade.C_Spell.IsCurrentSpell
local UnitExists, UnitIsDead = Facade.UnitExists, Facade.UnitIsDead
local L = Hekili:GetLocale("Hekili_Hunter")

if UnitClassBase("player") ~= "HUNTER" then
    return
end

local state = Hekili.State

-- The class kit and one spec a talent tree (ids the core's: Beast Mastery 100031, Marksmanship 100032, Survival
-- 100033; the client's one pseudo-spec, 1484, only keys the legacy profile the core migrates). Icons: the DB2 tabs'.
local spec = Hekili:NewClass("HUNTER", {
    specs = {
        {
            key = "beast_mastery",
            name = L["Beast Mastery"],
            tree = 1,
            icon = 132164,
            role = "attack",
            ranged = true,
            nameplateRange = 35, -- Auto Shot reaches 35 yd
            package = "Beast Mastery Turret (wowsims.com)", -- the default (owner 2026-11-13, L859)
        },
        {
            key = "marksmanship",
            name = L["Marksmanship"],
            tree = 2,
            icon = 132222,
            role = "attack",
            ranged = true,
            nameplateRange = 35, -- Auto Shot reaches 35 yd
            package = "Marksmanship Turret (wowsims.com)", -- the default (owner 2026-11-13, L859)
        },
        {
            key = "survival",
            name = L["Survival"],
            tree = 3,
            icon = 132215,
            role = "attack",
            ranged = true,
            nameplateRange = 35, -- Auto Shot reaches 35 yd
            package = "Survival Turret (wowsims.com)", -- the default (owner 2026-11-13, L859); the weave is picked by hand
            formerPackages = { ["Survival (wowsims.com)"] = true }, -- the weave was the default: a profile that never picked moves
            movement = true, -- the pack reads toggle.movement: the weave's move reaches the strikes (R5/R12)
        },
    },
})
if not spec then
    return
end

-- Rank IDs, lowest first (the DB2's; a Forever-only row where it adds a rank), and each rank's mana cost.
-- Arcane Shot and Summon Hawk cost 11% of base mana at every rank (wowsims e4ef929e54's spell data, CostPct 11; their
-- logs pay 189 at 60): a fraction of the mana meta's `base`, as Multi-Shot.
local ARCANE_SHOT = { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 }
local AIMED_SHOT = { 19434, 20900, 20901, 20902, 20903, 20904 }
local AIMED_SHOT_COST = { 75, 115, 160, 210, 260, 310 }
local SERPENT_STING = { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 }
local SERPENT_STING_COST = { 15, 30, 50, 80, 115, 150, 190, 230, 250 }
local HUNTERS_MARK = { 1130, 14323, 14324, 14325, 1213268 } -- 1213268: Forever's rank 4 row
local HUNTERS_MARK_COST = { 15, 30, 45, 60, 60 }
local SNIPER_SHOT = { 1310687, 1310785, 1310786 } -- Forever-only (D4)
local SUMMON_HAWK = { 1293241, 1293525, 1293526, 1293527 } -- Forever-only (D4)
local RAPTOR_STRIKE = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 }
local RAPTOR_STRIKE_COST = { 10, 25, 35, 45, 55, 70, 85, 100 }
local MONGOOSE_BITE = { 1495, 14269, 14270, 14271 }
local MONGOOSE_BITE_COST = { 30, 40, 50, 65 }
local WING_CLIP = { 2974, 1310180, 14267, 14268 } -- 1310180: Forever's level 12 row
local WING_CLIP_COST = { 40, 40, 60, 80 }
local ASPECT_OF_THE_HAWK = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 }
local ASPECT_OF_THE_HAWK_COST = { 20, 35, 50, 70, 90, 110, 120 }
local ASPECT_OF_THE_BEAST = { 13161, 1299445, 1299446, 1299447 } -- ranks 2-4 Forever-only (D4)
local ASPECT_OF_THE_BEAST_COST = { 50, 70, 90, 110 }
local ASPECT_OF_THE_CHEETAH = { 5118 }
local ASPECT_OF_THE_CHEETAH_COST = { 40 }
local BASE_MANA = 1720 -- a fraction cost is of this (wowsims's ExtraClassBaseStats, level 60; Spec.lua)
-- Cryptstalker Armor (set 530, wowsims sim/hunter/item_sets.go; items from its db.json): the 2-piece's hidden aura
-- 28755 makes Rapid Fire last 4 s longer, the 8-piece's 28751 takes 20 mana off Multi-Shot and Aimed Shot.
local CRYPTSTALKER = { 22436, 22437, 22438, 22439, 22440, 22441, 22442, 22443, 23067 }
local IMMOLATION_TRAP = { 13795, 14302, 14303, 14304, 14305 }
local IMMOLATION_TRAP_COST = { 50, 90, 135, 190, 245 }
-- Lane A (coverage; the pin's sim/hunter/spell_data_auto_gen.go ladders, costs and cooldowns from its spells_auto_gen.go):
-- every other ability a Hunter presses. A percent cost is a fraction of BASE_MANA. Forever's own Freezing Trap rows
-- (1324500-2, as the Cooldown Manager links them) lead, the classic rows follow with the same costs.
local EXPLOSIVE_TRAP = { 13813, 14316, 14317 }
local EXPLOSIVE_TRAP_COST = { 275, 395, 520 }
local FREEZING_TRAP = { 1324500, 1324501, 1324502, 1499, 14310, 14311 }
local FREEZING_TRAP_COST = { 50, 75, 100, 50, 75, 100 }
local FROST_TRAP = { 13809 }
local FROST_TRAP_COST = { 60 }
local VIPER_STING = { 3034, 14279, 14280 }
local VIPER_STING_COST = { 135, 175, 215 }
local COUNTERATTACK = { 19306, 1242634, 20909, 20910 }
local COUNTERATTACK_COST = { 30, 45, 65, 85 }
local DISENGAGE = { 781, 14272, 14273 }
local DISENGAGE_COST = { 50, 100, 150 }
local DISTRACTING_SHOT = { 20736, 14274, 15629, 15630, 15631, 15632 }
local DISTRACTING_SHOT_COST = { 20, 30, 50, 70, 90, 110 }
local VOLLEY = { 1510, 14294, 14295 }
local VOLLEY_COST = { 350, 420, 490 }
local SCARE_BEAST = { 1513, 14326, 14327 }
local SCARE_BEAST_COST = { 35, 50, 75 }
local TRUESHOT_AURA = { 1299346, 1299348, 19506, 20905, 20906 }
local TRUESHOT_AURA_COST = { 180, 245, 325, 425, 525 }
local MEND_PET = { 136, 3111, 3661, 3662, 13542, 13543, 13544 }
local MEND_PET_COST = { 50, 90, 155, 225, 300, 385, 480 }
local ASPECT_OF_THE_WILD = { 20043, 20190 }
local ASPECT_OF_THE_WILD_COST = { 90, 115 }
local CALL_PET, REVIVE_PET = { 883 }, { 982 }

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

local function cost(costs, ids)
    return function()
        return costs[knownRank(ids)] or costs[1]
    end
end

-- The talents' cost cuts, each a talent-gated cost modifier (a SPELLMOD_COST percent: DB2 aura 108, misc 14), so both
-- layers cut the whole price, unrounded (a percent-of-base cost is rounded to the whole mana first: wowsims
-- e4ef929e54 mana.go, then spell.go's ApplyCostModifiers; MM Turret Arcane Shot 189 x 0.88 = 166.32 in its log). Two
-- rows multiply, as in game (wowsims spell_mod.go SpellMod_PowerCost_Pct): 2/2 and 2/5 make Raptor Strike 100 x 0.4 x
-- 0.94 = 37.6 (no wowsims log takes both talents).
-- - Resourcefulness (440529, a Forever-only Survival talent, 2 ranks): 30% / 60% off the strikes and traps (DB2 mask
--   194: Raptor Strike and Mongoose Bite, Wing Clip, the traps, Counterattack). The DB2 carries only the top rank's
--   -60; the rank-1 -30 is wowsims/forever's generated spell data (MIT, sim/core/spelldata/spells_auto_gen.go
--   `440529: {{-30, -60}`). Strider Kick takes it too, as wowsims's log shows (39.6), though its DB2 mask is outside
--   440529's.
-- - Efficiency (19416, 5 ranks): 3% a rank off the shots, stings and strikes (DB2 mask: Raptor Strike, Mongoose Bite,
--   Wing Clip, Arcane Shot, Multi-Shot, Serpent Sting, Aimed Shot, Summon Hawk, and Strider Kick since hotfix 113554
--   (wowsims: mask word 2 8192 -> 2105344); not the traps, Hunter's Mark, Rapid Fire or the aspects). The DB2 carries
--   the 5/5 -15; wowsims's data `19416: {{-3, -6, -9, -12, -15}}`. Sniper Shot takes it too, as wowsims's Marksmanship
--   logs show (321.2 of 365 under 4/5), though our DB2 mask lacks it: wowsims over the DB2.
-- wowsims's logs: 2/2 Resourcefulness pays 40 Raptor Strike, 26 Mongoose Bite, 32 Wing Clip, 98 Immolation Trap; 2/5
-- Efficiency 94 Raptor Strike, 75.2 Wing Clip, 178.6 Arcane Shot, 235 Serpent Sting.
-- Improved Revive Pet's -20% a rank on Revive Pet (100% of base): the base is rounded whole, then cut unrounded
-- (wowsims mana.go newManaCost, then spell.go ApplyCostModifiers; L1793 item 1).
spec:RegisterCostMod({ talent = "improved_revive_pet", pct = { -0.2, -0.4 }, spells = { 982 } })
spec:RegisterCostMod({
    talent = "resourcefulness",
    pct = { -0.3, -0.6 },
    spells = {
        RAPTOR_STRIKE[1],
        MONGOOSE_BITE[1],
        1317257, -- Strider Kick
        WING_CLIP[1],
        IMMOLATION_TRAP[1],
        EXPLOSIVE_TRAP[1],
        FREEZING_TRAP[1],
        FROST_TRAP[1],
        COUNTERATTACK[1],
    },
})
spec:RegisterCostMod({
    talent = "efficiency",
    pct = { -0.03, -0.06, -0.09, -0.12, -0.15 },
    spells = {
        SERPENT_STING[1],
        ARCANE_SHOT[1],
        SUMMON_HAWK[1],
        AIMED_SHOT[1],
        2643, -- Multi-Shot
        SNIPER_SHOT[1],
        RAPTOR_STRIKE[1],
        MONGOOSE_BITE[1],
        1317257, -- Strider Kick
        WING_CLIP[1],
        3043, -- Scorpid Sting
        VIPER_STING[1],
        5116, -- Concussive Shot
        19503, -- Scatter Shot
        COUNTERATTACK[1],
        DISTRACTING_SHOT[1],
        19801, -- Tranquilizing Shot
        VOLLEY[1],
    },
})

-- Aimed Shot's and Multi-Shot's price with the Cryptstalker 8-piece's flat 20 off (before the talents' percents: wowsims
-- adds a flat cut to the base first, spell.go ApplyCostModifiers).
local function crypt8(price, flat)
    local priced = type(price) == "function" -- decided here: the returned function runs in the state's environment
    return function()
        local c = priced and price() or price
        if set_bonus.cryptstalker_8pc > 0 then
            c = c - flat
        end
        return c
    end
end

-- A shot's cast time under Rapid Fire's +40% and Quick Shots' +30% ranged haste (DB2 3045 and 6150 aura 140), which
-- the engine's spell haste (stale in combat) does not see.
local function rangedCast(base)
    return function()
        return base / ((buff.rapid_fire.up and 1.4 or 1) * (buff.quick_shots.up and 1.3 or 1))
    end
end

-- One aspect at a time (wowsims aspects.go): each removes every other.
local ASPECTS = {
    "aspect_of_the_hawk",
    "aspect_of_the_beast",
    "aspect_of_the_cheetah",
    "aspect_of_the_monkey",
    "aspect_of_the_pack",
    "aspect_of_the_wild",
    "aspect_of_the_viper",
}
local function aspectEffect(key)
    return function()
        for i = 1, #ASPECTS do
            if ASPECTS[i] ~= key then
                removeBuff(ASPECTS[i])
            end
        end
        applyBuff(key)
    end
end

local function aspect(key, ids, costs)
    return {
        id = ids[1],
        copy = rest(ids),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(costs, ids),
        spendType = "mana",

        startsCombat = false,
        known = knows(ids),

        now = aspectEffect(key),
        handler = aspectEffect(key),
    }
end

-- Two abilities on one category cooldown (DB2: Arcane Shot and Summon Hawk category 1173, Aimed Shot and Multi-Shot
-- category 2; 6 s each): each sets the other's. `hawk`: the cast also summons a hawk for 18 s. `improved`: Improved
-- Arcane Shot's -0.3 s a rank shortens the recovery the cast puts on its partner too (wowsims's
-- hunter_beast_mastery_turret.log, 2/5: Summon Hawk 5.4 s after an Arcane Shot at the earliest, 8 pairs; Arcane Shot
-- 6.0 s after a Summon Hawk). (A new closure for each of `now` and `handler`: each runs in its own environment.)
local function shares(other, hawk, improved)
    return function()
        setCooldown(other, improved and 6 - 0.3 * talent.improved_arcane_shot.rank or 6)
        if hawk then
            summonPet("hawk", 18)
        end
    end
end

-- A `now` or `handler` that applies `key`: debuff on the target (`debuff` true) or buff on us.
local function applies(key, debuff)
    return function()
        if debuff then
            applyDebuff("target", key)
        else
            applyBuff(key)
        end
    end
end

-- The traps share one 30 s category cooldown (DB2 SpellCooldowns: Immolation, Explosive, Freezing and Frost Trap), which
-- Survivalist's Discipline (1310496: curve {-20, -40} %, mask every trap placement and Deterrence) shortens, as does
-- Deterrence's own 300 s. `base` is the unshortened cooldown.
local function trapCooldown(base)
    base = base or 30
    return function()
        return base * (1 - 0.2 * talent.survivalists_discipline.rank)
    end
end
local TRAPS = { "immolation_trap", "explosive_trap", "freezing_trap", "frost_trap" }
local function trapCast(me)
    return function()
        local cd = 30 * (1 - 0.2 * talent.survivalists_discipline.rank)
        for i = 1, #TRAPS do
            if TRAPS[i] ~= me then
                setCooldown(TRAPS[i], cd)
            end
        end
        if me == "immolation_trap" then
            applyDebuff("target", "immolation_trap")
        end
    end
end
-- Serpent Sting's dot, and Rapid Recuperation's buff when talented (wowsims grants it on a landed sting; no damage
-- needed). shortcut: no landed signal reaches a sting on live, and an avoid undoes only target auras
-- (Families/Now.lua),
-- so a missed sting keeps the buff in the belief: 15 s of +50% spirit regen while casting the game did not give, ready
-- while short; the player aura read where plain (not under the Map restriction) corrects it, upgrade with a landed
-- signal for a sting. A new function each call: an ability's `now` must not be its handler (Families/Now.lua).
local function stings()
    return function()
        applyDebuff("target", "serpent_sting")
        if talent.rapid_recuperation.rank > 0 then
            applyBuff("rapid_recuperation")
        end
    end
end

-- Mongoose Bite spends its window; with Lacerating Strikes (1310533) it bleeds the target (1310536, 21 s), a new bite
-- replacing the bleed on a new timer (wowsims e4ef929e54, 774fc188dd). shortcut: the bleed starts at the cast, so a
-- missed bite keeps it in the belief (no landed signal reaches a melee hit on live; no list reads it); upgrade with a
-- landed signal if a list reads the bleed. A new function each call: an ability's `now` must not be its handler.
local function bites()
    return function()
        removeBuff("defensive_state")
        if talent.lacerating_strikes.rank > 0 then
            applyDebuff("target", "lacerating_strikes")
        end
    end
end

-- Resourcefulness at 2/2 (100% chance; the owner's rule assumes no lower rank's roll): a melee or ranged ability's crit
-- (wowsims talents_survival.go: proc flags 0x110 and a crit; never a white swing or Auto Shot). The crit reaches the
-- belief by kind, flag and school, its amount secret on live (Game/Events/Rows.lua, D1).
local function resourceful()
    if talent.resourcefulness.rank >= 2 then
        applyBuff("resourcefulness")
    end
end

-- Bestial Discipline (19590): 25/50% of the spirit regen while casting by rank (its effect 2, wowsims's curve).
local BESTIAL_DISCIPLINE = { 0.25, 0.5 }

-- The five-second rule (C3): spirit and mp5 regen per second, the declared starting point the out-of-combat read and
-- the in-combat calibration replace, as wowsims's turret logs measure them at 60 (ab0f00e4fc, Pre-BiS turret gear):
-- 1.540 a tick casting with no share (mp5 15.40 a second), 3.290 outside (Spirit regen 32.90 - 15.40 = 17.50), so
-- Marksmanship and Survival spirit 17.50, mp5 15.40; Beast Mastery under Bestial Discipline 2/2's 50% share 24.15
-- casting (15.40 + 0.5 x 17.50: the log's 2.415) and 32.90 outside, so spirit 8.75, mp5 24.15 and share 0.5. Forever's
-- Spirit regen is `6.25 + Spirit/8` a second for every class (wowsims mana.go:75-76), not Classic's formula.
-- Resourcefulness (1242688, DB2 aura 134): +50% of Spirit regen while casting, opened by a melee or ranged ability's
-- crit at 2/2 (the abilities' `onCrit`, below).
-- Rapid Recuperation (1242512): 25/50% by rank, opened at a Serpent Sting's cast (wowsims
-- talents_marksmanship.go:183-230; the sting's `shortcut:` above names the missed-sting over-count).
-- shortcut: wowsims also grants it at 50/100% when Rapid Killing (a kill proc the belief does not open) is spent, one aura ID for both; that source is unmodelled (the sting's share holds);
-- upgrade with Rapid Killing's kill reaction and a second share if a build relies on it.
-- state.spec: the functions run in the state's environment (the file's `spec` is the class).
spec:RegisterResource(
    Enum.PowerType.Mana,
    {
        resourcefulness = { aura = "resourcefulness", share = 0.5 },
        rapid_recuperation = {
            aura = "rapid_recuperation",
            share = function()
                return 0.25 * talent.rapid_recuperation.rank
            end,
        },
    },
    nil,
    {
        fsr = {
            spirit = function()
                return state.spec.beast_mastery and 8.75 or 17.5
            end,
            mp5 = function()
                return state.spec.beast_mastery and 24.15 or 15.4
            end,
            share = function() -- Bestial Discipline's rank (the belief reads it after its talent walk), never the spec
                return BESTIAL_DISCIPLINE[talent.bestial_discipline.rank] or 0
            end,
        },
        base = BASE_MANA, -- a fraction cost is of base mana (Spec.lua)
    }
)

-- Summon Hawk's guardians (C1): 2 up at most (DB2 1293527 effect 3), 18 s each (1293248's duration); the oldest gives
-- way to a third.
-- shortcut: the APLs' pet.hawk.count is the belief's count at query_time; summons the simulation predicts are not
-- counted (the shared 6 s cooldown blocks a second summon in the lookahead), count them if a pack needs it.
spec:RegisterPets({
    hawk = { spell = "summon_hawk", duration = 18, cap = 2 },
})

-- The pet unit out and alive (UnitExists / UnitIsDead of "pet", plain in combat: W PR14). Not `pet.up`: the
-- simulation's also counts Summon Hawk's guardians its forecast summons. A plain function too: `usable` runs in the
-- belief's context as well, which has no `pet_out`.
local function petOut()
    return UnitExists("pet") == true and not UnitIsDead("pet")
end
spec:RegisterStateExpr("pet_out", petOut)

-- The Beast Within (1223758, Forever; L1058): while the pet is under our Bestial Wrath we rage too, +10% damage (no
-- read: the addon models no damage) and every mana cost -50% (DB2: A_DUMMY 10 and -50 on the caster, no class mask;
-- the pin has no row, wowsims omits it). A passive with no skill line nor tree node: taken as Bestial Wrath's own
-- (unprobed: IsPlayerSpell(1223758) on a Bestial Wrath Hunter, and a shot's cost under it).
spec:RegisterCostMod({ aura = "bestial_wrath", pct = -0.5 })

spec:RegisterGear("cryptstalker", unpack(CRYPTSTALKER))
spec:RegisterSetBonus("cryptstalker_2pc", 28755)
spec:RegisterSetBonus("cryptstalker_8pc", 28751)

spec:RegisterAuras({
    aspect_of_the_hawk = { id = 13165, copy = rest(ASPECT_OF_THE_HAWK), duration = 3600, max_stack = 1 },
    aspect_of_the_beast = { id = 13161, copy = rest(ASPECT_OF_THE_BEAST), duration = 3600, max_stack = 1 },
    -- Bestial Wrath's 18 s (19574's duration), on us from our cast: the buff is the pet's (no walk of ours finds it)
    bestial_wrath = { id = 19574, duration = 18, max_stack = 1 },
    rapid_fire = {
        id = 3045,
        duration = function() -- the Cryptstalker 2-piece: +4 s
            return 15 + (set_bonus.cryptstalker_2pc > 0 and 4 or 0)
        end,
        max_stack = 1,
    },
    -- Aspect of the Cheetah (5118; no APL casts it: for display and custom priorities) and the Dazed it proc'd when
    -- struck (15571: 4 s, -70% speed), and the set's hidden auras (tracked so set_bonus reads them).
    aspect_of_the_cheetah = { id = 5118, duration = 3600, max_stack = 1 },
    dazed = { id = 15571, duration = 4, max_stack = 1 },
    cryptstalker_2pc = { id = 28755, duration = 3600, max_stack = 1 },
    cryptstalker_8pc = { id = 28751, duration = 3600, max_stack = 1 },
    -- Aspect of the Hawk's proc (Deadly Aspects) on an Auto Shot: +30% ranged haste.
    quick_shots = { id = 6150, duration = 12, max_stack = 1 },
    -- Resourcefulness (talent 440529): a melee or ranged ability's crit gives +50% Spirit regen while casting (the mana
    -- entry; opened at 2/2 by the abilities' `onCrit`). Rapid Recuperation (talent 1223987): 25/50% by rank at a Serpent
    -- Sting (its `now`), or 50/100% spending Rapid Killing (unmodelled: the mana entry's note).
    resourcefulness = { id = 1242688, duration = 30, max_stack = 1 },
    rapid_recuperation = { id = 1242512, duration = 15, max_stack = 1 },
    -- Rapid Killing's buff (415407, a kill proc: +20% on the next Shot, 20 s, one charge), Sniper Shot's (1310786: 10 s,
    -- three charges, +10 yd range on the Shots), Expose Prey's Mongoose Bite window (1310726: 10 s, one charge), Strider
    -- Kick's speed (1317257, 3 s), Lacerating Strikes' bleed and Immolation Trap's burn (target debuffs, from our casts):
    -- registered as the pin states them (wowsims sim/hunter). The kick's speed (Survival Melee's run out for the Sting
    -- reads it), the bleed and the burn have handlers; the rest no list reads.
    rapid_killing = { id = 415407, duration = 20, max_stack = 1 },
    sniper_shot = { id = 1310786, copy = { 1310687, 1310785 }, duration = 10, max_stack = 3 }, -- the Cooldown Manager links all three
    expose_prey = { id = 1310726, duration = 10, max_stack = 1 },
    strider_kick = { id = 1317257, duration = 3, max_stack = 1 },
    lacerating_strikes = { id = 1310536, duration = 21, tick_time = 3, dot = "debuff", max_stack = 1 },
    immolation_trap = {
        id = 14301,
        copy = { 13797, 14298, 14299, 14300 },
        duration = 15,
        dot = "debuff",
        max_stack = 1,
        -- off the Cooldown Manager (cdm-facts fix round 1 I3): the `now` writes it at the placement, it lands when the
        -- trap is sprung, so a verdict at cast + W0 would close a trap that fires later
        cdm = false,
    },
    -- The auras the abilities below apply, under the spell IDs the Cooldown Manager links (cdm/hunter.lua); durations from
    -- the pin's rows (Freezing Trap's by rank, Deterrence's 10 s, Trueshot Aura's 30 min), the Forever-only ones as the
    -- pin's talents state them. None is applied by a handler but Deterrence's and Trueshot Aura's: a trap's effect lands
    -- when its target springs it, the rest are the target's.
    freezing_trap = { id = 3355, copy = { 14308, 14309, 1324500, 1324501, 1324502 }, duration = 20, max_stack = 1 },
    frost_trap = { id = 13810, duration = 30, max_stack = 1 },
    scare_beast = { id = 1324506, copy = { 1324507, 1324510 }, duration = 20, max_stack = 1 },
    intimidation = { id = 1324494, duration = 3, max_stack = 1 }, -- the pet's stun
    scatter_shot = { id = 1324499, duration = 4, max_stack = 1 },
    deterrence = { id = 19263, duration = 10, max_stack = 1 },
    entrapment = { id = 19185, duration = 4, max_stack = 1 },
    improved_concussive_shot = { id = 1324511, duration = 3, max_stack = 1 },
    frenzy = { id = 19621, duration = 8, max_stack = 1 }, -- the pet's haste
    trueshot_aura = { id = 1299346, copy = rest(TRUESHOT_AURA), duration = 1800, max_stack = 1 },
    aspect_of_the_monkey = { id = 13163, duration = 3600, max_stack = 1 },
    aspect_of_the_pack = { id = 13159, duration = 3600, max_stack = 1 },
    aspect_of_the_wild = { id = 20043, copy = { 20190 }, duration = 3600, max_stack = 1 },
    aspect_of_the_viper = { id = 415423, duration = 3600, max_stack = 1 },
    -- Mongoose Bite's window after we dodge (Defensive State, 5 s), timed from the plain usability flip (reset_precast).
    defensive_state = { id = 5302, duration = 5, max_stack = 1 },
    -- Raptor Strike queued on the next main-hand swing (C_Spell.IsCurrentSpell, applied in reset_precast).
    raptor_strike = {
        duration = function() -- until the swing that takes it (R13); out of combat no swing runs: a whole one
            -- shortcut: in combat out of melee mainhand_remains is 0 too (the swing stays due), so a strike queued there
            -- also lasts a whole swing; upgrade if the replay shows a strike queued out of melee mattering
            local r = state.mainhand_remains
            return r > 0 and r or state.mainhand_speed
        end,
        max_stack = 1,
    },
    -- The target's debuffs, modelled from our casts (target auras are unreadable in combat).
    serpent_sting = {
        id = 1978,
        copy = rest(SERPENT_STING),
        duration = 15,
        tick_time = 3,
        dot = "debuff",
        max_stack = 1,
    },
    hunters_mark = { id = 1130, copy = rest(HUNTERS_MARK), duration = 120, max_stack = 1 },
})

-- Mongoose Bite's window from the plain usability read (the player aura walk may be secret in combat; the Rogue's
-- Cutthroat precedent): usable, or short only of mana, is the window; its 5 s from the flip's time.
local biteAt, biteOpen = 0, false
local function biteUsable()
    local r = knownRank(MONGOOSE_BITE)
    if r == 0 then
        return false
    end
    local usable, noMana = IsSpellUsable(MONGOOSE_BITE[r])
    return usable == true or noMana == true
end
spec:RegisterEvent("SPELL_UPDATE_USABLE", function()
    local u = biteUsable()
    if u ~= biteOpen then
        biteOpen = u
        biteAt = u and GetTime() or 0
    end
end)

spec:RegisterHook("reset_precast", function()
    local r = knownRank(RAPTOR_STRIKE)
    if r > 0 and IsCurrentSpell(RAPTOR_STRIKE[r]) then
        applyBuff("raptor_strike")
    end
    if now == query_time and biteUsable() then
        if biteAt > 0 and now - biteAt < 5 then
            applyBuff("defensive_state", biteAt + 5 - now)
        else
            applyBuff("defensive_state")
        end
    end
end)

-- The time to the next main-hand swing (Hekili_Warrior/Warrior.lua's, after Hekili's Classic profile): wowsims's Melee
-- Weave casts Multi-Shot only when it ends before the walk in to that swing.
spec:RegisterStateExpr("mainhand_remains", function()
    -- out of combat no swing runs (nextMH is 0): anchor it at this evaluation, or its phase free-runs with the clock
    local mh = (nextMH == 0 and combat == 0) and now or nextMH
    if now == query_time then
        local real = mh - now
        return real > 0 and real or 0
    end
    if query_time <= mh then
        return mh - query_time
    end
    -- past a due swing out of melee none comes: wowsims's timer stays due (0) until the walk in lands one
    if not target.within5 then
        return 0
    end
    if mainhand_speed <= 0 then
        return 0
    end -- no swing speed read yet
    return mainhand_speed - (query_time - mh) % mainhand_speed
end)

-- The ranged auto-shot clock (C7): the next Auto Shot and the ranged speed, from the belief's hand 3 (Engine/Sim/
-- State.lua's swings.ranged_*), anchored like mainhand_remains; shots fire from range, so a due one repeats.
spec:RegisterStateExpr("ranged_speed", function()
    return swings.ranged_speed
end)

spec:RegisterStateExpr("ranged_remains", function()
    local r = swings.ranged_projected
    if r == 0 then
        return 0 -- no shot believed yet: no clock, and no wrap (a wrap would forecast a weave open before any shot)
    end
    if now == query_time then
        local real = r - now
        return real > 0 and real or 0
    end
    if query_time <= r then
        return r - query_time
    end
    local speed = swings.ranged_speed
    if speed <= 0 then
        return 0
    end -- no ranged speed read yet (the client raises on x % 0)
    return speed - (query_time - r) % speed
end)

-- The weave window (re-pin design §3a, decision 11; R17: timing only, no walk time): from an Auto Shot whose next
-- main-hand swing comes before the next shot, until that swing or the next shot, whichever comes first (controller
-- ruling, 8b-2 fix round 2): the span a strike can be queued for the swing between two shots (no aura shows it).
-- Opens: the shot's own now() (its observed cast success closes the last shot's span and opens this one when it fits)
-- and the evaluator's false->true edge (the same test). Closes: the evaluator, true from the shot while the main hand
-- has not swung since it and for one ranged speed at most, turns false at the swing or a speed after the shot
-- (`close_on_false`); the next shot's now(); Raptor Strike's now() and handler(). On the shot's own Drain the
-- evaluator answers what the shot's now() decided (`weaveShot`), so a window the shot opened has a true evaluation
-- before its close edge and one it did not open gets no edge. The ranged speed is UnitRangedDamage's (the belief's
-- stat read; the now context has no ranged clock speed). A due main-hand swing (none comes out of melee) counts as
-- before the shot. Its length (owner 2026-11-04) is 1.2 x the ranged shot time at each open, a liberal cap since the
-- window mostly closes on its own: in the belief the evaluator's read (`now_duration`), in the forecast ranged_speed's
-- (`duration`, under state), each written in its own layer as now() and handler() are. The forecast's window (the
-- belief's, copied at each reset; no pack line opens it) ends at Raptor Strike's handler or that length.
-- (The evaluator and the shot's now() run in the belief's now context: the test is written in each.)
local weaveShot = 0 -- the shot's now(): 1 it opened the window, 2 it did not; the evaluator reads it once (an upvalue)
local weaveCombat = 0 -- the evaluator's last `combat`: its fall to 0 (combat end) clears a weaveShot left unread
spec:RegisterWindow("weave", {
    evaluator = function()
        if combat == 0 and weaveCombat > 0 then
            weaveShot = 0
        end
        weaveCombat = combat
        if weaveShot > 0 then
            local opened = weaveShot == 1
            weaveShot = 0
            return opened
        end
        local shot, last, rs = lastSwing(3), lastSwing(1), stat("UnitRangedDamage")
        return shot > 0
            and rs > 0
            and mainhand_speed > 0
            and now - shot < rs
            and last < shot
            and last + mainhand_speed <= shot + rs
    end,
    close_on_false = true,
    duration = function()
        return 1.2 * swings.ranged_speed -- ranged_speed's read
    end,
    now_duration = function()
        return 1.2 * stat("UnitRangedDamage")
    end,
})

spec:RegisterAbilities({
    -- The ranged auto attack: its success is the ranged hand's shot (C7; whether Forever sends it per shot is a
    -- checkpoint). Never recommended.
    auto_shot = {
        id = 75,
        expects = "travel",
        velocity = 40,
        school = "physical",
        cast = 0,
        cooldown = 0,
        gcd = "off",
        rangedSwing = true,

        startsCombat = true,
        known = knows({ 75 }),

        -- the shot ends the last shot's weave and opens its own when it fits (the weave window above)
        now = function()
            closeWindow("weave")
            local last, rs = lastSwing(1), stat("UnitRangedDamage")
            weaveShot = 2
            if rs > 0 and mainhand_speed > 0 and last < now and last + mainhand_speed <= now + rs then
                openWindow("weave")
                weaveShot = 1
            end
        end,
    },

    hunters_mark = {
        id = 1130,
        copy = rest(HUNTERS_MARK),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(HUNTERS_MARK_COST, HUNTERS_MARK),
        spendType = "mana",

        startsCombat = false,
        known = knows(HUNTERS_MARK),

        now = applies("hunters_mark", true),
        handler = applies("hunters_mark", true),
    },

    aspect_of_the_hawk = aspect("aspect_of_the_hawk", ASPECT_OF_THE_HAWK, ASPECT_OF_THE_HAWK_COST),
    aspect_of_the_beast = aspect("aspect_of_the_beast", ASPECT_OF_THE_BEAST, ASPECT_OF_THE_BEAST_COST),
    aspect_of_the_cheetah = aspect("aspect_of_the_cheetah", ASPECT_OF_THE_CHEETAH, ASPECT_OF_THE_CHEETAH_COST),
    aspect_of_the_monkey = aspect("aspect_of_the_monkey", { 13163 }, { 20 }),
    aspect_of_the_pack = aspect("aspect_of_the_pack", { 13159 }, { 100 }),
    aspect_of_the_wild = aspect("aspect_of_the_wild", ASPECT_OF_THE_WILD, ASPECT_OF_THE_WILD_COST),
    aspect_of_the_viper = aspect("aspect_of_the_viper", { 415423 }, { 0 }), -- a rune: no cost row

    rapid_fire = {
        id = 3045,
        cast = 0,
        cooldown = function() -- Rapid Killing's curve {-60, -120} s by rank (talents_marksmanship.go:100)
            return 300 - 60 * talent.rapid_killing.rank
        end,
        gcd = "off",

        spend = 100,
        spendType = "mana",

        toggle = "cooldowns",
        startsCombat = false,
        known = knows({ 3045 }),

        now = applies("rapid_fire"),
        handler = applies("rapid_fire"),
    },

    -- the Beast Mastery talent (2 min, off the GCD; 12% of base mana: the pin's row CostPct 12, wowsims's SpellConfig
    -- charges it, the DB2 had it free); its 18 s rage is the pet's, The Beast Within's on us (the cost mod above); only
    -- with the pet out (wowsims talents_beast_mastery.go:136-138)
    bestial_wrath = {
        id = 19574,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        spend = 0.12,
        spendType = "mana",

        toggle = "cooldowns",
        startsCombat = false,
        known = knows({ 19574 }),
        usable = function()
            return petOut(), "no pet out"
        end,

        now = applies("bestial_wrath"),
        handler = applies("bestial_wrath"),
    },

    serpent_sting = {
        id = 1978,
        expects = "ticks",
        school = "nature",
        velocity = 40, -- its debuff dot aura: 3 s over 15 s
        startsAtLanding = true, -- the DoT starts at its landing (wowsims WaitTravelTime; L482)
        copy = rest(SERPENT_STING),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(SERPENT_STING_COST, SERPENT_STING),
        spendType = "mana",

        startsCombat = true,
        known = knows(SERPENT_STING),

        now = stings(),
        handler = stings(),
    },

    arcane_shot = {
        id = 3044,
        onCrit = resourceful, -- Resourcefulness at 2/2
        expects = "travel",
        velocity = 40,
        school = "arcane",
        copy = rest(ARCANE_SHOT),
        cast = 0,
        -- Improved Arcane Shot (19454): -0.3 s a rank (wowsims's curve; DB2 has only rank 1's row)
        cooldown = function()
            return 6 - 0.3 * talent.improved_arcane_shot.rank
        end,
        gcd = "spell",

        spend = 0.11,
        spendType = "mana",

        startsCombat = true,
        known = knows(ARCANE_SHOT),

        now = shares("summon_hawk", false, true),
        handler = shares("summon_hawk", false, true),
    },

    -- The dive, then a hawk for 18 s (wowsims summon_hawk.go).
    summon_hawk = {
        id = 1293241,
        expects = "none", -- a summon has no damage row: a velocity would open a flight ticket that never pays
        copy = rest(SUMMON_HAWK),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 0.11,
        spendType = "mana",

        startsCombat = true,
        known = knows(SUMMON_HAWK),

        now = shares("arcane_shot", true),
        handler = shares("arcane_shot", true),
    },

    aimed_shot = {
        id = 19434,
        onCrit = resourceful, -- Resourcefulness at 2/2
        expects = "travel",
        velocity = 40,
        school = "physical",
        copy = rest(AIMED_SHOT),
        cast = rangedCast(2),
        cooldown = 6,
        gcd = "spell",

        spend = crypt8(cost(AIMED_SHOT_COST, AIMED_SHOT), 20),
        spendType = "mana",

        startsCombat = true,
        known = knows(AIMED_SHOT),

        now = shares("multi_shot"),
        handler = shares("multi_shot"),
    },

    -- 13.9% of base mana (DB2 PowerCostPct): a fraction of the mana meta's `base`.
    multi_shot = {
        id = 2643,
        onCrit = resourceful, -- Resourcefulness at 2/2
        expects = "travel",
        velocity = 30,
        school = "physical", -- pays the pinned target's row only
        cast = rangedCast(0.5),
        cooldown = 6,
        gcd = "spell",

        spend = crypt8(0.139, 20 / BASE_MANA),
        spendType = "mana",

        startsCombat = true,
        known = knows({ 2643 }),

        now = shares("aimed_shot"),
        handler = shares("aimed_shot"),
    },

    sniper_shot = {
        id = 1310687,
        onCrit = resourceful, -- Resourcefulness at 2/2
        expects = "travel",
        velocity = 60,
        school = "physical",
        copy = rest(SNIPER_SHOT),
        cast = rangedCast(4),
        cooldown = 15,
        gcd = "spell",

        spend = 365, -- Efficiency cuts it too, as wowsims (the talents' cost cuts above)
        spendType = "mana",

        startsCombat = true,
        known = knows(SNIPER_SHOT),
    },

    -- On the next main-hand swing (wowsims raptor_strike.go), paid there; its 6 s category cooldown.
    raptor_strike = {
        id = 2973,
        onCrit = resourceful, -- Resourcefulness at 2/2
        copy = rest(RAPTOR_STRIKE),
        cast = 0,
        cooldown = 6,
        gcd = "off",

        spend = cost(RAPTOR_STRIKE_COST, RAPTOR_STRIKE),
        spendType = "mana",

        startsCombat = true,
        onNextSwing = true,
        known = knows(RAPTOR_STRIKE),

        usable = function()
            return not buff.raptor_strike.up, "a strike is already queued"
        end,

        -- the weave's strike ends its window: in the belief at the real cast, in the forecast at the simulated one
        -- (written apart: the owner's rule, never one function for both)
        now = function()
            closeWindow("weave")
        end,

        handler = function()
            applyBuff("raptor_strike")
            closeWindow("weave")
        end,
    },

    mongoose_bite = {
        id = 1495,
        onCrit = resourceful, -- Resourcefulness at 2/2
        copy = rest(MONGOOSE_BITE),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = cost(MONGOOSE_BITE_COST, MONGOOSE_BITE),
        spendType = "mana",

        startsCombat = true,
        known = knows(MONGOOSE_BITE),

        usable = function()
            return buff.defensive_state.up, "only usable after dodging"
        end,

        now = bites(),
        handler = bites(),
    },

    -- Forever-only (D4): 5.81% of base mana (DB2 PowerCostPct): a fraction of the mana meta's `base`. Its speed (1317257,
    -- 3 s) comes with every kick, hit or miss (wowsims talents_survival.go).
    strider_kick = {
        id = 1317257,
        onCrit = resourceful, -- Resourcefulness at 2/2
        cast = 0,
        cooldown = 8,
        gcd = "spell",

        spend = 0.0581,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 1317257 }),

        now = applies("strider_kick"),
        handler = applies("strider_kick"),
    },

    wing_clip = {
        id = 2974,
        onCrit = resourceful, -- Resourcefulness at 2/2
        copy = rest(WING_CLIP),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(WING_CLIP_COST, WING_CLIP),
        spendType = "mana",

        startsCombat = true,
        known = knows(WING_CLIP),
    },

    -- wowsims's Melee Weave lays it in melee range (its burn on the target is the trap's triggered spell, unmodelled);
    -- the 30 s is its category cooldown (DB2 SpellCooldowns).
    immolation_trap = {
        id = 13795,
        copy = rest(IMMOLATION_TRAP),
        cast = 0,
        cooldown = trapCooldown(),
        gcd = "spell",

        spend = cost(IMMOLATION_TRAP_COST, IMMOLATION_TRAP),
        spendType = "mana",

        startsCombat = false,
        known = knows(IMMOLATION_TRAP),

        now = trapCast("immolation_trap"),
        handler = trapCast("immolation_trap"),
    },

    -- Lane A (coverage): the other traps (one 30 s category cooldown, Survivalist's Discipline cuts it), the stings, the
    -- shots and the utility the pin carries (spells_auto_gen.go rows; sim/hunter ladders). Resourcefulness's mask takes
    -- the traps and Counterattack, Efficiency's the stings, Concussive, Scatter, Distracting, Tranquilizing, Volley and
    -- Counterattack. No priority casts them: registered so a manual press costs mana and starts its cooldown.
    explosive_trap = {
        id = 13813,
        copy = rest(EXPLOSIVE_TRAP),
        cast = 0,
        cooldown = trapCooldown(),
        gcd = "spell",

        spend = cost(EXPLOSIVE_TRAP_COST, EXPLOSIVE_TRAP),
        spendType = "mana",

        startsCombat = false,
        known = knows(EXPLOSIVE_TRAP),

        now = trapCast("explosive_trap"),
        handler = trapCast("explosive_trap"),
    },

    freezing_trap = {
        id = 1324500,
        copy = rest(FREEZING_TRAP),
        cast = 0,
        cooldown = trapCooldown(),
        gcd = "spell",

        spend = cost(FREEZING_TRAP_COST, FREEZING_TRAP),
        spendType = "mana",

        startsCombat = false,
        known = knows(FREEZING_TRAP),

        now = trapCast("freezing_trap"),
        handler = trapCast("freezing_trap"),
    },

    frost_trap = {
        id = 13809,
        cast = 0,
        cooldown = trapCooldown(),
        gcd = "spell",

        spend = cost(FROST_TRAP_COST, FROST_TRAP),
        spendType = "mana",

        startsCombat = false,
        known = knows(FROST_TRAP),

        now = trapCast("frost_trap"),
        handler = trapCast("frost_trap"),
    },

    scorpid_sting = {
        id = 3043,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 0.09,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 3043 }),
    },

    -- Improved Stings (1310661): -2 s a rank.
    viper_sting = {
        id = 3034,
        copy = rest(VIPER_STING),
        cast = 0,
        cooldown = function()
            return 15 - 2 * talent.improved_stings.rank
        end,
        gcd = "spell",

        spend = cost(VIPER_STING_COST, VIPER_STING),
        spendType = "mana",

        startsCombat = true,
        known = knows(VIPER_STING),
    },

    concussive_shot = {
        id = 5116,
        cast = 0,
        cooldown = 12,
        gcd = "spell",

        spend = 0.08,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 5116 }),
    },

    scatter_shot = {
        id = 19503,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        spend = 0.08,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 19503 }),
    },

    -- The pet's stun: 8% of base mana, 60 s (no talent mask touches its price).
    intimidation = {
        id = 19577,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = 0.08,
        spendType = "mana",

        startsCombat = false,
        known = knows({ 19577 }),
    },

    -- Usable after a parry (like Mongoose Bite's window; no window is modelled: the usability read decides).
    counterattack = {
        id = 19306,
        copy = rest(COUNTERATTACK),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = cost(COUNTERATTACK_COST, COUNTERATTACK),
        spendType = "mana",

        startsCombat = true,
        known = knows(COUNTERATTACK),
    },

    -- Survivalist's Discipline (1310496): -20/-40% cooldown; off the GCD, no cost.
    deterrence = {
        id = 19263,
        cast = 0,
        cooldown = trapCooldown(300),
        gcd = "off",

        startsCombat = false,
        known = knows({ 19263 }),
        toggle = "defensives",

        now = applies("deterrence"),
        handler = applies("deterrence"),
    },

    disengage = {
        id = 781,
        copy = rest(DISENGAGE),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = cost(DISENGAGE_COST, DISENGAGE),
        spendType = "mana",

        startsCombat = false,
        known = knows(DISENGAGE),
    },

    feign_death = {
        id = 5384,
        cast = 0,
        cooldown = 30,
        gcd = "off",

        spend = 80,
        spendType = "mana",

        startsCombat = false,
        known = knows({ 5384 }),
    },

    flare = {
        id = 1543,
        cast = 0,
        cooldown = 15,
        gcd = "spell",

        spend = 50,
        spendType = "mana",

        startsCombat = false,
        known = knows({ 1543 }),
    },

    distracting_shot = {
        id = 20736,
        copy = rest(DISTRACTING_SHOT),
        cast = 0,
        cooldown = 8,
        gcd = "spell",

        spend = cost(DISTRACTING_SHOT_COST, DISTRACTING_SHOT),
        spendType = "mana",

        startsCombat = true,
        known = knows(DISTRACTING_SHOT),
    },

    tranquilizing_shot = {
        id = 19801,
        cast = 0,
        cooldown = 20,
        gcd = "spell",

        spend = 270,
        spendType = "mana",

        startsCombat = true,
        known = knows({ 19801 }),
    },

    -- A 6 s channel, a tick a second.
    volley = {
        id = 1510,
        copy = rest(VOLLEY),
        cast = 6,
        channeled = true,
        tick_time = 1,
        cooldown = 0,
        gcd = "spell",

        spend = cost(VOLLEY_COST, VOLLEY),
        spendType = "mana",

        startsCombat = true,
        known = knows(VOLLEY),
    },

    scare_beast = {
        id = 1513,
        copy = rest(SCARE_BEAST),
        cast = 1.5,
        cooldown = 30,
        gcd = "spell",

        spend = cost(SCARE_BEAST_COST, SCARE_BEAST),
        spendType = "mana",

        startsCombat = true,
        known = knows(SCARE_BEAST),
    },

    -- Raid ranged attack power; the ranged-power half is no resource, the 30 min aura is for display.
    trueshot_aura = {
        id = 1299346,
        copy = rest(TRUESHOT_AURA),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = cost(TRUESHOT_AURA_COST, TRUESHOT_AURA),
        spendType = "mana",

        startsCombat = false,
        known = knows(TRUESHOT_AURA),

        now = applies("trueshot_aura"),
        handler = applies("trueshot_aura"),
    },

    -- A 5 s channel on the pet; Improved Mend Pet (19572): -10% cost a rank.
    mend_pet = {
        id = 136,
        copy = rest(MEND_PET),
        cast = 5,
        channeled = true,
        tick_time = 1,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return (MEND_PET_COST[knownRank(MEND_PET)] or MEND_PET_COST[1]) * (1 - 0.1 * talent.improved_mend_pet.rank)
        end,
        spendType = "mana",

        startsCombat = false,
        known = knows(MEND_PET),
    },

    -- L1059 (owner): the pet's calls, each only while the client calls it usable (IsSpellUsable, plain: no tamed pet,
    -- no corpse, the pet already out answer no; unprobed). The pin's rows: Call Pet (883) free and instant; Revive Pet
    -- (982) 100% of base mana and a 10 s cast, Improved Revive Pet (24443) -3 s and -20% a rank (its curve
    -- {-3000, -6000} ms, {-20, -40}%).
    -- shortcut: neither brings a pet into the forecast (pet_out reads the client), so the queue may show it twice while
    -- none is out; summon one in the handlers if that matters.
    call_pet = {
        id = 883,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        startsCombat = false,
        known = knows(CALL_PET),
        usable = function()
            return knownRank(CALL_PET) > 0 and IsSpellUsable(883) == true, "not usable"
        end,
    },
    revive_pet = {
        id = 982,
        cast = function()
            return 10 - 3 * talent.improved_revive_pet.rank
        end,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            return 1
        end,
        spendBase = true,
        spendType = "mana",

        startsCombat = false,
        known = knows(REVIVE_PET),
        usable = function()
            if knownRank(REVIVE_PET) == 0 then
                return false, "not usable"
            end
            local usable, noMana = IsSpellUsable(982)
            return usable == true or noMana == true, "not usable"
        end,
    },
})

-- Talents: { talent tree (1 Beast Mastery, 2 Marksmanship, 3 Survival: the dominant tree picks the spec), rank 1's
-- spell, max rank }: Forever's tree as wowsims/forever's ui/sim/talents/trees/hunter.json lists it (tools/wowsims/talents.lua
-- writes it; tests/Forever/talent_trees_spec.lua checks it and the spec detection over it). A key is Classic's where the
-- talent exists there (code reads `talent.<key>.rank`), else the snake_case of the node's name. The costs read Efficiency
-- and Resourcefulness.
spec:RegisterTalents({
    -- Beast Mastery (tree 1)
    deadly_aspects = { 1, 19552, 5 },
    endurance_training = { 1, 19583, 5 },
    focused_fire = { 1, 1223755, 2 },
    improved_aspect_of_the_monkey = { 1, 19549, 3 },
    improved_revive_pet = { 1, 24443, 2 },
    pathfinding = { 1, 19559, 2 },
    bestial_swiftness = { 1, 19596, 1 },
    unleashed_fury = { 1, 19616, 5 },
    improved_mend_pet = { 1, 19572, 2 },
    ferocity = { 1, 19598, 5 },
    summon_hawk = { 1, 1293241, 1 },
    spirit_bond = { 1, 19578, 2 },
    intimidation = { 1, 19577, 1 },
    bestial_discipline = { 1, 19590, 2 },
    frenzy = { 1, 19621, 5 },
    bestial_wrath = { 1, 19574, 1 },
    -- Marksmanship (tree 2)
    hawk_eye = { 2, 19498, 3 },
    improved_concussive_shot = { 2, 19407, 5 },
    lethal_attacks = { 2, 19426, 5 },
    improved_stings = { 2, 1310661, 3 },
    efficiency = { 2, 19416, 5 },
    careful_aim = { 2, 1223984, 5 },
    rapid_killing = { 2, 415405, 2 },
    improved_arcane_shot = { 2, 19454, 5 },
    lone_wolf = { 2, 415370, 1 },
    trueshot_aura = { 2, 1299346, 1 },
    mortal_shots = { 2, 19485, 5 },
    rapid_recuperation = { 2, 1223987, 2 }, -- wowsims's Marksmanship (spell_data_auto_gen.go:401); the DB2 names the spell only
    barrage = { 2, 19461, 3 },
    scatter_shot = { 2, 19503, 1 },
    ranged_weapon_specialization = { 2, 19507, 5 },
    sniper_shot = { 2, 1310687, 1 },
    -- Survival (tree 3)
    improved_tracking = { 3, 24293, 5 },
    deflection = { 3, 19295, 5 },
    entrapment = { 3, 19184, 5 },
    savage_strikes = { 3, 19159, 2 },
    survivalist = { 3, 19255, 5 },
    improved_wing_clip = { 3, 19228, 3 },
    clever_traps = { 3, 19239, 2 },
    surefooted = { 3, 19290, 3 },
    deterrence = { 3, 19263, 1 },
    survival_tactics = { 3, 19376, 2 },
    predators_edge = { 3, 1310627, 5 },
    counterattack = { 3, 19306, 1 },
    resourcefulness = { 3, 440529, 2 },
    expose_prey = { 3, 1310532, 2 },
    survivalists_discipline = { 3, 1310496, 2 },
    strider_kick = { 3, 1317257, 1 },
    lightning_reflexes = { 3, 19168, 5 },
    lacerating_strikes = { 3, 1310533, 1 },
})

-- Beast Mastery's HHA (re-pin ruling R15; wowsims's turret_hawk APL): Summon Hawk, Summon Hawk, Arcane Shot, reset when
-- complete, is the Beast Mastery Turret pack's own APL sequence (windows design v6 10.2, Phase 3 Part B, L1374); this
-- file registered it as a looping Lua window until then.

-- (L1808, owner "Setting per line") the health threshold of the packs' Deterrence (35%) lines (the recipes'
-- `extra`, the def-int-beyond-wowsims review's defaults): a 1-100 slider on every spec
spec:RegisterSetting("deterrence_health", 35, spec:HealthOption("deterrence"))

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and
-- run it, never this block (tests/Forever/hunter_spec.lua checks it matches). Each pack's .simc is generated from its
-- wowsims recipe (`make wowsims-packs`, tools/wowsims/specs/hunter_*.lua).
spec:RegisterPack(
    "Survival (wowsims.com)",
    20261123001,
    [[Hekili:LV17poQnq0)w2VKMOUL8RDVUD1LvQvTv3v1EQ6Y1VcXbmb3ayKTjrR0P83EhtcjgdK4eypPk(YDSW4388y7zEmOyp2(l2Z9qcS9NMmAY7gpEY0rJgBpx8Ac2EEcYDnAfCrmkc(35PSnKnOWDl6VLULtI4wU0Obs7EnKI8KyTmLek(yS9YkHLNGDTN)H)5tF53(8Z8dWzppG45H3pgm3Twh98UfIa8UfhU3qFkdVbZ2TWd7Jsdf7w8Z)9FUBbC7DluGiLmu6x(WG0ybMn0lHpustp(q(gNTy0gSfGx4G7b8zOyEiqCp4AQ0Fe(UfippA83bxSg)k3A3IFfjqpxbp6)xF8laibcrc)5HdxrebPlLuFOMPdamb6IwoYF0i8d(Upn1ccJmQpjec0ixbHgZTsyyyWlrIzUOWqNeS4EI)S7G)3HMk6jVWYdJ86DNafIJfwH0ySZwAOVfogTmeMf)rjS((zdboq2GZXlhLQTDFqJ7eHyRZ8UhEzQVVL69TstQEWizGhiRVdSW5eG2UhImak)mvyA(m(YZtWcpmmjy4yx89PCmqgFNvUEZglTpaJcfbwRJPBJ7D4psCfVFghleK4vCRtJ2z)ZvHE)D4cGG3c2kdVgWbZCsOY7CR4FcHkCbdLq8C8jSkOVaXwbrtyjHt8Wp2tqIWVm7r1HJdtJXCNqYQarfaSFa90asfGLHuk4)u2R32WHnNy2AykEtd3dhrJjUoS0Qw(maGi0)szWPJyuTlsgGsHtF(u3u(SjMCkC)6NayaxWiR1Nc7rsDPClKRIexW3Yr6HzoRjURpVLqOAfLcEyjrGpVPKOikKFvULdY1MCEJ3k3G6gsYmR)D7FGLkV2Vd)R9R9r9CP0qp4IIpJHJqKy(lJTECWGENjgGzjqAgikk3iPe2YxakyaScOTy(KkyiMlconZdOIYhIkyzeunJyIHN9qkD1QqSveDdocOyV(YPCak2Z5WS)9hVbKkg79dY9J96Fx)JrAfcFiqxXdiXoqrZv4b963p7It4pB0xlENxMLBYEpw8VkA7Gbd0hDbRhbgmObzE6arNRoDAxlMysnIowmXWcFDSOY1unVJfAUHsKDSiKED)o20xtmthB2Fnk0URVoXkYlTiJEKRnLd1yQ0uThTlbUHc9TkbUTQQTkfAqjSwLhnVErRsNlKCUv915Ze2QUY03(xJdnJbNT7bVzEQC3hEZCvvDV4nZzFZ6(rlpdSNVbs3cesR5)HeUGN99g23UE4YpL99ho05w7FjVZ32ZZ7(lCfdwvzeK98RPlW2cW51G9PUcRIEoMYrovBKkhFKu(isN6)RksxU3RL6BS0PpyOtvAm8151YDuw62hVc3EQFXxVNl1RzPZFNHo)KikvhxtxOLa)JgcSQ4OcqxDRzLq)KHqFs0JHa)tMc8rXmgc84rgISQkftXw)eCDyxs(HPoq)ySscHQBcUYEwLhyppRSNmTGev9J4L2vDOzWhh24ZU78uT2m01plNBPAw4Z4tje6NlpghvR2Dbm0pELJHwzSlGI(zPCuowFsD8NRovJluvMB6hglV54snOxzXr1sL1DPF0pBMpgf1J1Nz6PSQr6hcpUGEuu4LqW0JA1KT8n4fVV(38UHV69LF3B1Qat0ZDCZLb6gXUSyMPIFUq9ToueZuLBxOWDhkIzQOZlkiPdfZmvRSzcT6qboD9lMOrOJeEmr7ZeDnwxs7thj2jdn1jlSgnDDNiZutFLtZ0Q24wJQQkCQP6OVwvHnMLzSZunRxN(R2HBgRn8Qu60oCZuvyxRMI2HDMQ45MQE3ouuxGXnuNS5eXKkstRRJegwrQ5SusI6klAwU)2Hd61FQ3FnZB3uxWEOUoEuBxWAxolPqDFFH67Iw7ZH6(oeNRlCTpl0tDNZIV9DXRTNBc5VCId)MdS)FZ3ukFKf7rD5CU6n3wu(lfDm9hx)xurbaR)xDrwqeyokveqz2Z)aEnjKSBr)F)WpxLShB)Fp]]
)
spec:RegisterPack(
    "Beast Mastery Turret (wowsims.com)",
    20261125000,
    [[Hekili:vFzBpoQnqC8pl3B2ER6kiz3BVUnQuPEQTQ3PERQkBFRbh8qWngm12Cr7B4ZEhdeWHh0YE9vvrkXXEMFZ4hM)giBjprczudqE82n3((TBV9(nB2qcnpxcKWsAYr6bSrbnh)(davBQJ)m(nOEUo(PkLcWoE7j5jnpx7LiZV261ZcjLzjVVIlmFSGSF2GOlHes4V9xp(0V8N72BHhL3YMeMXzmO1rqNSYyVRo2Kb1XD95NkvWxavDmdsPvc08F6p(96yS764fbwX9TjM2pRQahYNvQ9TZdg(tUhYvC9nyCu0cTaNtmST0gxUUoMYyYIVbBCeEw7vh)ZudD3m5ZB)8hFcHKzmL6D((h4MSQ92PG)itVgzIjfD)M0nBG3LM8WDE4kSsMYf4ocnXWLfAVsfGoVNAcsOcrujyUHNg8g83izL5kBdpgqzx9gdvafgpHSaIojfPEqbDVaNfFAcRVnWhZb(xGZ8otzEBBxU04wO6yt0zW(Q0up3(9QkN3zQDjht20iCdmkJEQfrdGPJ5I5)(m(LNNOfmaNekOibUPsdyYKgDiHfS1AFgqfMmVJfYtfx19NYeZpeObJHxCq7n4Du74UOB7rBWe8RHTJ7lahnlQuA75RL)aHzcbiQkaDKGFiZmnagEo8Jb376WEHuYIsRupVoZXtpG6iMdR0CTHtfrNuut2Q8qrl5y(WvZS(pJ5mixwWtIuvZTHnJd50)wQWZ)f0f3gMXRlQNsLjv6GBxtDf6kUCvIN5J02DWoF3667fgmYzfU(rv4yW)u1CE3k(hKLrTaoXlyYtE4)8qLo4YGo2(CjdcsKfyqQGD6Q8C75hS(9I2uvcfp6QZKgxCuCfHnT3bJBMpTJ45WR7OmofoGLXOwGMZGhQ)ejeLt1OXJUesW1gDZTGT3rGnFS5wXozcYholZscpl1GTuCCXNtjHVgjhIbd(cShKGCPFMP1Z7g5PZHiBk3tAqSXL0lxOprKYg03TYG6Oc96I6u5lByV)ve2bXPxFKNiSzd(7xzWDf(CdDxXSf13TsudsIla6H1cQxSCbqF)Qb5iJUaRTBwjSbf2LinUKB5d3dIVlXACj2sSMOlVeWXvEov)Zlg7Ca1zasyJuSvdWsDCP1uQJLPhWEXi9C32WDCTtRMDu7ZWJ6YUAoxk17MdJu6BipUWyzYdeXhVUu3lQ2p(GGDVO4cJDN7yo6)e7Nq7DmyA3DjttwoUMR33(BuAmBCf1CHWDpzTx10Mx9pC7)FUpz(JSV8z9zULOFTCYJUFbWLF8Es32lTYKjv4ljch5co(It)A37f1mm5F)d]]
)
spec:RegisterPack(
    "Marksmanship Turret (wowsims.com)",
    20261123001,
    [[Hekili:vF53VTTnqC8)w6lznybswjTDDbZdydBdRdRbftzVsjkXtwCMIuGKQg5f93(okBlrRFGOK90qaIziV7ZD8i)EMHerEKeZOwG8WTBU9drr3E3MnrKy7t1ajUMMVNUdhiPv4V)mvV3urLMsEDB6JnAnyBtF7b1bdVYeKRQU25ZtcfL54M1Wf2pjjzZgctnKtI)9)(Hh)1)6(kp0K4soJbh9dm5RkW33MAlH20tZfwO0WxbDBkdkOnc08F6l)zBkoDB6c4A4HUCYew2iTGoKvBcDBbMjSQkaPkU(gmkA0rbUDy4yLlQCtBkLXuYVbhShEYe0M(lul9(zYM3(5p9icP0ARn3hgUJBlBYCBGWrMEnYetkA2MInBG3vK)X7cWIRwvWf4rbn3YvstqTgqNZO2T5uHiPgS3Wl2(g8ZevJ9k3Gagqzx9glvasBGqjHKdkrraiPzcCx8hty9TBdXCG)v4mVZuM32JLltI7mSl6miRPOiWF(GM65DM6k5yYwKGhFjL0dhr0by6AlIXi51GoXuQS9g8FVK88fc0cgG7sniZHBAmaMTfj7YzBJC2xcuHTmyVuDqE1P)Oo3(dBnG1YL7mbdENCCDF0hNXyXe81W2Z9fGJMLuRCZ8A5pqyMqaIgjyse8DL2PbWYRGFC779DitOuSKIg9tRZC86fO3J5WQmxtR5iDUEMQ5mMZGkLKNNOBMR8pJdv0)rPXR7s6If1z86c5tHkVXS921iJC36bDnEdoX4opo5BKVVxyWiNP6CkEX4cjJBAmdztM9c9fjgBqzWvg1rxWnwt3xOCSNlo8HUVG5KUI8ZNBCrIpRnXrAoU)4us8lrJsSyWxG9GM1N(zMopVBKNENtUuUN0G60N0ZRmMOQDb9DRmOEY2xwuNQ3DH99VGWoOMF5rEsNaxW)WkdUFNc)qFsV4q9DRe1qpKfa9X1cQV7YcG((vcAOVZcGI2Sss(TKwI1yf3sSM0TAjGJLzEc25Br5DNYBbsCxdkNS1rDSeCk1XnVgWEXk9CJ64owLD2hV2DD2nww0BxF)VoZgFbUpfgAisC)e3)AK))01B(tPN)4DMEz9vVjpz7cGl)SU56uTuTg3G0gBPsJ)7dWEUGJVR(3o9S5ULj)7p]]
)
spec:RegisterPack(
    "Survival Turret (wowsims.com)",
    20261123001,
    [[Hekili:vF53VTTnqC8)w6lznybs2jnzDb1dydRdRdBbdtEVsjAXtwSMMuGKYg(f93EpkBlrRFGiN90qaIziV7ZD8i)EMHmNSKeXOwG8Y9ZU)P5ZV)HzZMtIShkasubnDdDnoqs3I)oQuVJVJkQswwQ1GTk597v7n8TMGu12BD2FqOOmhZvLCH9lsYQbXBkGus0V)VVS8Z)ZZMtyjr5Cgdo6dysF1a(CvInhQsonxyMsd7aDvcdYOLc08F(V)ZQeC6QKbqvYdD5HjmVuAbDiRWe6sBMj0SlajkU9omcAQ0iWTadhRCrKBQsOmMs(D4GnWbtqvYVsT0NhitE)F9LLiKCRTW8Cy4AUnVCLl5d7y6TitmPORMLnBg8HS0p(qawq1QmUal90ulxjnbfAaDEf1UiLkeXfG9oE2I3HFgRkT34geWak7M3zPcqAdekjeVxjYcajDLa3f)rpwF)Iqmh47GZ8otzyBpwUmXBP6n1rNbRkZYc8NpOSyyNPUsoMSzX4rxCoD)re1a6V2OymsEbOJn5kBJb)3ljVEHaTGb4UudYu4UsdGzBw86u2I5o7ZbQWMhSrQ2lV50FuKA)0cdyTC5AtqR3Xhx3h9XzmwmbFlS9CFe4OzXfk3mVv(TegieGOucMybFDUTFaS8TWpT4rFhwjukwCwP(W0mhVEb6nyomjZ10cosNRhOAoG5myRsYtJ1Ldv(hWHT0VQ041DjD0I6aEDH8jtLwAwC)uKrUB9GUaVbhBCNhN8DUVVxyqhNP6ukEX4cjJBAmdz9M9c9fjcBqzWv60fxWnwt9xGCSFlo8L6Vq5KUI8lNBCrIoRnXrAoU)4us01Orjwm4JWUvZ6t)mtNNp0XtVZjxk3qQvD6t61vg9u1UG(Hjgupz71f1(6DxyF8kcBRA(6JCVobUG)0edUFNc)qFsV4q9dtevBpKra9XPcQP7YiG(XjcQTVZiGMpBIK8BjngRUkUXy1RB1ya7kZ8eSd3IY7oL3cKO6guozRJAxjyFQDBE1I9IvA4oVMBxv2zF8A3vBxxzrJDn9)QnR7f4MuOTHiX9tuZRr()txVHpLE9J3b6L1u969KTlao(Z6gQt1y1ACdslT5kn(VmaB4co(U6F70ZMRxM8T)]]
)
spec:RegisterPack(
    "Survival Melee (wowsims.com)",
    20261123001,
    [[Hekili:LJ12UnUnq0VL8IRnAQ8LSz72G1bOfTf7w0nOOk9vjtlnYMvuIcKu2ial83EhQlwu3SL9(utqaIPjN5mx0mdpwoZDE2X2NOaNNwmBX7NpFXDZMn3Xw9sc4yNq8cjBWfXKi8)2PID0De2HvFbyaCy14989sAK0YJhnrl(lmoXxd56ukt95yN1DIUmb8CS)0)80Z)2F)GSavh7TuFFixhq6Do79WHvQT4Mf7nnGlGDG4WkFiGKYuhw9Z)1FEyfU9HvTrkLov7fYPBtJvGyQFICQ2P9LtL7CJ0szHWYMClAgbjwYWWWhxZ1MLkpSI47ZJ)oCri8I06WQFLOip0H7m(lF(zeKTkvI8HPt3qvBtxRJGPneDcIj61K1ZcMndExG3hUZctQcEaLHzFINIYJLwjcavEnrT0JWyUjG6wAWYBWpD5PQr6fw(aXF0nkcdIvwmEm4UNZcSGyYAggf)rlS((LtrFGUdkXReLULnpPjDJiIWmR7dRtdcSm33knPBLj6ep6SbU4Zp31arMhbzi0XHMa9ThZNpsrj8bmmeqShCBQeqVjWDJN)Y5A53ceMARvymFF8OIVK4P(4sjOu04nsRkTDZp3e68DKk0bVgSnuVhWrXCt46DUw8RqOdtaS0yq6YOB2QABafncEC59MkSMX5(UbPIxgM4y9dicrFyqI7dr8yQNRiTR8zhkiiju0DOIHjEe5F5cSEoM0BsTBJOq1KkbnSPDc4EPYcnjIny13ECKanUga1AWY1yXqA0qvZ6qY)k(uc7T0dVxUNWcDPXzwLVzddSI47GiSxz04X3KlUL2F9bHBi1lmVi5RzwR2(PjtgvPbisqmWifFGvOsPpw)mTA60OUEZLXF8UztUMmwtFVifItbKOlEp6zvHdr4rW2e5wUQW164aASloEFdGb14Sf(UciIqJLFC5SVwFNhxwkcoLc8)H6FRUStMmPP21KEgkqTmawhVHZXaFnvbVYJvZcQx5H6E90upgn5vECE(Xo1dvtDPrrCKFLwvKRvYP7k6DMzRIQ(LmfniE5gzFy)pQ6wBRIiAzTPBMJO6B8xli0uHQEs21XrinwAXPo2ifrjkqdU06CTut5UqnC5tzS6li(48lo2Ecm5jOeh7(CUs6Li3CZtCSZcmnIk0UnGTufJOql2D9iwv04O)ZUGNExoCPkLS9QfcxaRVt51vSanrVeZUceJBL0U8rKQ47zI055A1INO2OVBGg1Gi4Lz12mi1M9(lWSv8dVCl3IBP24VFGg3K7PPPlyGPH6hhiuvSs7bOpmuGoYxThG(PbcKjt2EGA(SbIvfj3(qQzhxFi1I)BFa2SnZqQAtsngPCk3VImyg6nBfBprRbJyJkwJdoA8fzO2SxZWNVeoYxdj5HZsUX0qJRyZh(7M)Yzkh)RJRMnZNiUUmcixodKVrkiNNdY1vp1CIZXYDt6gVYtC68qZXLhzbyum)gin0CyFzA4iJW3a5GM3t1AaEz8D5dKw08ERsaAq8pt2(4c2FRz97x0y0hNVElRBdrFSyn(TdzY18oKtx600ok9l4T4vJ()hIWDF165VtUd6TLq1X79TgIN4Ld7u87jiPQTCHJ9NGqkJEy14FV49QNDSZ)9d]]
)

-- The hand-built lists the wowsims.com packs replaced: a saved choice of one falls back to the spec's default.
spec:RetirePacks({ "BeastMastery", "Marksmanship", "Survival" })
-- The Beast Mastery and Marksmanship weave packs, whose wowsims builds are gone (upstream PR #1041; owner L1154): a
-- saved choice of one moves to the spec's default, its Turret pack, with the one-time retired notice (RestoreDefaults).
spec:RetirePacks({ "Beast Mastery (wowsims.com)", "Marksmanship (wowsims.com)" })
