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
            movement = true, -- the pack reads toggle.movement: the weave's move reaches the strikes (R5/R12)
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
            movement = true, -- the pack reads toggle.movement: the weave's move reaches the strikes (R5/R12)
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

-- The talents' cost cuts, their percents added (each a SPELLMOD_COST percent: DB2 aura 108, misc 14):
-- - Resourcefulness (440529, a Forever-only Survival talent, 2 ranks): 30% / 60% off the strikes and traps (DB2 mask
--   194: Raptor Strike and Mongoose Bite, Wing Clip, the traps). The DB2 carries only the top rank's -60; the rank-1
--   -30 is wowsims/forever's generated spell data (MIT, sim/core/spelldata/spells_auto_gen.go `440529: {{-30, -60}`).
--   Strider Kick takes it too, as wowsims's log shows (39.6), though its DB2 mask is outside 440529's.
-- - Efficiency (19416, 5 ranks): 3% a rank off the shots, stings and strikes (DB2 mask: Raptor Strike, Mongoose Bite,
--   Wing Clip, Arcane Shot, Multi-Shot, Serpent Sting, Aimed Shot, Summon Hawk, and Strider Kick since hotfix 113554
--   (wowsims: mask word 2 8192 -> 2105344); not the traps, Hunter's Mark, Rapid Fire or the aspects). The DB2 carries
--   the 5/5 -15; wowsims's data `19416: {{-3, -6, -9, -12, -15}}`. Sniper Shot takes it too, as wowsims's Marksmanship
--   logs show (321.2 of 365 under 4/5), though our DB2 mask lacks it: wowsims over the DB2.
-- wowsims's logs: 2/2 Resourcefulness pays 40 Raptor Strike, 26 Mongoose Bite, 32 Wing Clip, 98 Immolation Trap; 2/5
-- Efficiency 94 Raptor Strike, 75.2 Wing Clip, 178.6 Arcane Shot, 235 Serpent Sting.
local RESOURCEFUL = { 0.3, 0.6 }
local function discounted(price, resourceful, efficient, flat8pc)
    local priced = type(price) == "function" -- decided here: the returned function runs in the state's environment
    return function()
        local c = priced and price() or price
        if flat8pc and set_bonus.cryptstalker_8pc > 0 then
            c = c - flat8pc
        end
        local off = (resourceful and RESOURCEFUL[talent.resourcefulness.rank] or 0)
            + (efficient and 0.03 * talent.efficiency.rank or 0)
        return c * (1 - off)
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
-- category 2; 6 s each): each sets the other's. `hawk`: the cast also summons a hawk for 18 s. (A new closure for
-- each of `now` and `handler`: each runs in its own environment.)
local function shares(other, hawk)
    return function()
        setCooldown(other, 6)
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
-- the in-combat calibration replace, as wowsims's logs measure them at 60: hunter_beast_mastery 7.94 a second while
-- casting (Bestial Discipline 2/2's 50% share of 15.88) and 15.88 outside, so spirit 7.94, mp5 7.94 and share 0.5;
-- hunter_marksmanship and hunter_survival 0 while casting and 15.88 outside. Forever's Spirit regen is `6.25 + Spirit/8`
-- a second for every class (wowsims mana.go:75-76), not Classic's formula.
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
                return state.spec.beast_mastery and 7.94 or 15.88
            end,
            mp5 = function()
                return state.spec.beast_mastery and 7.94 or 0
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
-- (`duration`, under state), each written in its own layer as now() and handler() are. The forecast's window (each
-- pack's open_window line, tools/wowsims/specs/hunter_*.lua `extra`) ends at Raptor Strike's handler or that length.
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

        spend = discounted(cost(SERPENT_STING_COST, SERPENT_STING), false, true),
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

        spend = discounted(0.11, false, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(ARCANE_SHOT),

        now = shares("summon_hawk"),
        handler = shares("summon_hawk"),
    },

    -- The dive, then a hawk for 18 s (wowsims summon_hawk.go).
    summon_hawk = {
        id = 1293241,
        expects = "none", -- a summon has no damage row: a velocity would open a flight ticket that never pays
        copy = rest(SUMMON_HAWK),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = discounted(0.11, false, true),
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

        spend = discounted(cost(AIMED_SHOT_COST, AIMED_SHOT), false, true, 20),
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

        spend = discounted(0.139, false, true, 20 / BASE_MANA),
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

        spend = discounted(365, false, true), -- Efficiency, as wowsims (the cost cuts above)
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

        spend = discounted(cost(RAPTOR_STRIKE_COST, RAPTOR_STRIKE), true, true),
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

        spend = discounted(cost(MONGOOSE_BITE_COST, MONGOOSE_BITE), true, true),
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

        spend = discounted(0.0581, true, true),
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

        spend = discounted(cost(WING_CLIP_COST, WING_CLIP), true, true),
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

        spend = discounted(cost(IMMOLATION_TRAP_COST, IMMOLATION_TRAP), true, false),
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

        spend = discounted(cost(EXPLOSIVE_TRAP_COST, EXPLOSIVE_TRAP), true, false),
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

        spend = discounted(cost(FREEZING_TRAP_COST, FREEZING_TRAP), true, false),
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

        spend = discounted(cost(FROST_TRAP_COST, FROST_TRAP), true, false),
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

        spend = discounted(0.09, false, true),
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

        spend = discounted(cost(VIPER_STING_COST, VIPER_STING), false, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(VIPER_STING),
    },

    concussive_shot = {
        id = 5116,
        cast = 0,
        cooldown = 12,
        gcd = "spell",

        spend = discounted(0.08, false, true),
        spendType = "mana",

        startsCombat = true,
        known = knows({ 5116 }),
    },

    scatter_shot = {
        id = 19503,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        spend = discounted(0.08, false, true),
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

        spend = discounted(cost(COUNTERATTACK_COST, COUNTERATTACK), true, true),
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

        spend = discounted(cost(DISTRACTING_SHOT_COST, DISTRACTING_SHOT), false, true),
        spendType = "mana",

        startsCombat = true,
        known = knows(DISTRACTING_SHOT),
    },

    tranquilizing_shot = {
        id = 19801,
        cast = 0,
        cooldown = 20,
        gcd = "spell",

        spend = discounted(270, false, true),
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

        spend = discounted(cost(VOLLEY_COST, VOLLEY), false, true),
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
            return 1 - 0.2 * talent.improved_revive_pet.rank
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

-- Beast Mastery's HHA (re-pin ruling R15; wowsims's turret_hawk APL at e4ef929e54, the BM build's hawk rotation since
-- 65b3f51f61: a sequence of Summon Hawk, Summon Hawk, Arcane Shot under "Use Summon Hawk" and "Use Arcane Shot", reset
-- when complete): a stepped window that loops, open for the fight ("combat": no timer). Its evaluator is the fight
-- (`combat`), not a constant: a held true opens once ever, since combat end closes every window and keeps the last
-- evaluation. On the kit: a tree's own registration would land in the kit's table anyway (a tree reads its fields
-- through the kit), and only Beast Mastery Turret's pack reads it.
spec:RegisterWindow("hha", {
    evaluator = function()
        return combat > 0
    end,
    duration = "combat",
    steps = { "summon_hawk", "summon_hawk", "arcane_shot" },
    loop = true,
})

-- The priorities, written by `make packs` (tools/make_pack.lua) from APLs/packs.lua and APLs/*.simc; edit those and
-- run it, never this block (tests/Forever/hunter_spec.lua checks it matches). Each pack's .simc is generated from its
-- wowsims recipe (`make wowsims-packs`, tools/wowsims/specs/hunter_*.lua).
spec:RegisterPack(
    "Survival (wowsims.com)",
    20261114000,
    [[Hekili:LVvBpoQnq4Fl7xsjQBjVS7EDVvnRuRARURQDv1X2VcXbBsCdGrytIwPt53EhtcjgNqIdWEsv8LDDGzEMhp2EMHje3rUV66GrcI7lJho(dJgn6(Hdh66iElH46KG8xIMddIrrWFDYsxrxHc3m1AnBnNgXT9zr9LY9widHLynlJgk(CS7StclpH4768P)5Lx)TV8eFhCUolOymzRoeUFLg6PntfliBMU7AdcyPKvK0ntXKauwOyZ0F(V)ZntHlVzQcez0bs7YhSilwqshGt4dK0eZhWx5TMGwrSb8c7FlGFkkMhcehdJzs7r5BMIWyw83bdwsEJBVz6VIeONobpS(Rp)kaYcHiH)0GbZPIfzZKuFGMO9bmb6sEa9rF8y0yCGVn4gtzb0qWrJ8fuwm3ojLakpdjM4Jcd9siIBPbtUb(Vhlt0toWgtq4E3iqHKyHDilM4TMfgytIrZcHzXFCewF)KbahORif4vGYPLDRtJ7fHsxMBDmzwwqGT61TZsoTYiPJhiBGhSW5TaTEle5aC89uHP5Z4lppLsGsOyVaAk52mobitG3CF8Krs5fO05GkGD5um5HEcAe55jpOQojmlMW9cPZxiobaBvONgqQamlKXa7NL(w9uhwbiPlPXZRL6yselM67LcZIAbqe6FzPWwGyKxctEXAHsPTybm)m(KXMSvB76NayaxKsxQpf2IK6s5A4ajnUKTLAIjPElP(lpVKGRAoJbwygvqoVO0Oigeeb(Kheqj58cVgw988dP5IzDZ2ByRYl7LXS1XF1QYB1ZNXcXWGY3lLeHOX8Nhz)q)(9oJpGKMaNLaVOCJKIBRybOKaWkG2I5JQGHs9rWrs(cM44drLKmccztnrWZEiLnFEiXoITIebuSNLCkVafJ92n7)P9xaI3qW)GC)ypRBS27Pvi8oh9jUbn2dYmmN0VNLv(Gd4pz4xlFLNNuiYwlw(tLLTF)(6Axs6HGa9BqKNoG35QdN218jMKJOJ5tmmXxhZRCnzZ7yUMAKISJ5H0Z73XM(AfZ0XM9xtfA3yPtSY8sZZO75AZYHAmvAAThTlbQrI(wLa1lRARsHgKcRv5rZZx0Q05cbNBvBD(iHTQPm9P)14qZyWz7EW7MLoU7dVBM6uDV4DZyFZ6(rlpdCDwbHBbcP1H7qkxWZBQ(2EsddFjVj77ApP7Vu0ExxNIwCcJsHv1ukY15AA1PRamEfyFO1NQOxGPuZ700u54JKYhqAFUDvKQO5OsGV3qGvZzxc6t3Xqj0pyi0hYfBiWFWuG3NJ1qG)rdbwn3PHq)OHqFuordX)JA4RSj90nM9GjvVHRtEOy5wva0rdRe1YnOCVAJo7wZdX)ZrVQJAQrgoJnLqu1jQsrGVag6NTkWql06fqr)Gubk7JzQQ)5ID24GNhZn9tIhV54snnwzXrvsL1DPD0pywOJsfnvhw6XCi0pcUFbDFHkxcbtpPvrOY3Hhg86FAWg(4Gx(5bvtbmsp2rTZb0n8D5zY1JmwZKBDipME0(AM1Ud5X0tUv7Yr6q(mtlu2S6S6qoo96xmPgHoI7XKAFgRxJ1LQ9PJ47KUMQklSIA66qEgtFGtZQvTXTRtTQWXMwh91wvyJzzo7mTM1RR(RwHB3zCTHxvLoTd3mTkSRTMI2HDMwXtTYE3ouuVaJAKNS5eXKms3vvhjmmJuZzPKevLw0Sy)Tdh0Z)uT9AM1QvxWURQoEuzxWAxolPGEO(9lsv2fT2Nd6b0l4W56cxRZI71dDxWIV9DXRTNBc5RS(Ux2B3)389CuOz5EuFCmx9MBlo(B2yF4pU(RYEjaR(1Dp3jcmhLjwWsDD(ezjnKUzQ1VV73jq(TD)V]]
)
spec:RegisterPack(
    "Beast Mastery Turret (wowsims.com)",
    20261115000,
    [[Hekili:vB5xVTTnqa8pl5L0e0aj7S4MAd4b0ITHMG2GIPSxPeT4jlotrkqsfx)I(SVJY)Jwwkrd9P(Ifb5D)U)W7otYyYZKig1cKNUD0TFy84XtgnAejYUPeirL00v0L4cjTa)9Za1yRt(g(lO3uN8CLwd4gxTwT2WlmbPQIRDATrOOmh5fvCH9bjzrNgXucPKOV8pp98F(3Zw4GhxSLnjkNZyWwfbt6aT9S6eBouNSBVWmLgEb01jmiJwjqX)03)ADcUDDsVaR4HohZeMxjXJczLMqxCWWpfbixX13G2rtLgbgtmCTYzxUPoHYyk57WfRGnMG6K)GAPZ6WFU6Bp8mcj3AlnZcdxYT5vlCHqylrVgzIofChKn92PWK7UFAaMH1QmUaVrOPwUsAck1aQ8cQDEkviIlb7n8S5xGFJvv2lDlcyaLD5fwQaK2aHscXRvISaqsxiWO4XZy9(5HOpWFb2ZBpLULDB6YGxH6vnwNblQYYc83pOQSBLPUuo6SzX4fyCoD9wenao)mFm)8r8BhNOeGOscMybFzU9MkdGUtw8Yu28XonS8c43NpXxHfcLIfNvP3mmXXueOxXLlhO4glNkIxRP28bPHMwYr)HRHbjodkusEASgd7bPqb9FvA8swsJlvUnhKwNu0KPsRmZVDifpOQy6QeVyJXebM02Q7yFDprG2kxvGX3HcT1CjtToipNgiHFyd8o2xlQoLIvrMCLTlT8o(eTWWMD(UNY6ITN4B5Gvs1A5LwQEjwqIv1god(y9JKiCWGbfU14ub3ynnZZ3oTdx(uZ89Df8KpVFGbjAFtdUsZXmmNsI()08qSOX7H9XMjF67z6083APPxLIZLpqYVPZN1UcjhQ7giQJTJ9aAYqbDOrThqFyWG8AH7H19dK1XM7Ea9XbcYVTVhuthiQZgi0dVXJAb0RIS7PahTH)bKOMzaU6sh12v(NtT98HJyp5KdCh3WTVQEVgxFJ9ktwAW1UvypoVXdVgoFXC4A3oCa3HzqnI1Uy)nS6GhorC4Jo8h7)6mbQ7cQ3UsSJjqhYLN9SLta2)tBAsIONtRS5kn(azyfxWXhn(x7EtyZXK)7d]]
)
spec:RegisterPack(
    "Marksmanship Turret (wowsims.com)",
    20261114000,
    [[Hekili:vBzBVnnmqC8pl7nJnXustzBWQurceGyiycrkV1jUXxAm1XoYpqvFt(SZ50NsBt0cIxHQuJL9D)857U)oHerMrIzulqEA8OX3hffD7OrJiX21vajUIMTKUahiPL4)FJQxAkPstbVQoDMtRbBD6vRuRm8stqMQ8AVpRfkkZZDUJlSpkjZ7Clmvqgj(Z)8PzF8htkBHMexWzmyJFGjBqB8K6uBbuNUDUWCLg(nORtzqo1jqZF33)ADkoDDAp4C8qFmzclCslOdzvMq)rGzclldqQIRVb3fn6OapomCSYVRCtDkLXuYxGdwcRnb1PFGAPt6iAU6BpodHuyTvMjHHl42c3C)bi8etVgzIbfCh9Hm2y6ywEwaMC1QCUalf0mlxjnbvAaDEo1onJkejvG9gE(0lWNjkN9s)GagqzxEHLkaPnqOKqYkLipaK05c8u8LZy9YPHymW)nSJ3okDB7M0LjXxdB2Dgm3LNh0E(axv3ot9PCmyZtWYxsbD1genaoFTEXyK8kqNyku29g8VNsE(ebAbiCsWKi4lkS34magV5jlYytJ8Ey5LWBNExBhMlukwsUtVEyMJ5qqVKlxmiZ10kosNRHbzodkvsEwIgpedYHs6VuASMkPjvk)KdYRJ6rYvzoZ0XdPxXxAbDfwMsmwFkyJVrT99idoXzQoJIv3J6l8tJri7SzpQjIeJQqdUYjxBj4gRP5wZnxSGdFQ5w0TnpK3VtDsI31aIJ0C88XPK4)MgrIf38EyFOXSn9Dm9E(Qt8SvDYhY7j1UbUnRTLrpQBhiQdT29a6UHcAFtFpGUFGGoih6b0RhiO2cLEq9MbI6mjup8E4eETAI6w2CylAVajUr04BLqOrJEwQNkOoG9Ov2ZnQHBFIGwsWg76RH(GMSXSt7E3hchePe)V49Vg4)hLy3vPNV82HsCF27S3vEeW(FFAxQY(Y14bK6Sfkn(DBWsUGJFqZN2(9knlt(Z]]
)
spec:RegisterPack(
    "Survival Turret (wowsims.com)",
    20261114000,
    [[Hekili:vBzxpUPoqy4Fl7nB3vDfes3DB3iLk1Q2QUvTRo6q6Tgm4HGBmyK)ir5g(T3XKVijGcv9QQifSSN5XJNzEnqciZiHmQbiVmE04hdccUF0OrKqZ6kGewrtxqNJdkPf4)Hw1s(sQOoEMvPatD8nRKR08cTxQS4wN9RfskZXmXYfMNljjDIxxbPKWV(ZxM95)FIElwsyoNXGn(a60lUHtQJn5qD8258ZKkyjOQJzqg1kqZ)W)996yC664oqz5(U4q7NBlnGYNvP9DHnt7Rx6Hef3EhUdkAPwGhbgow62rUUoMYyYYxHdwaR1E1XFIAOt6isU5hppdHKBmv6j((Z5MCBIl49pX0BrMyqbpqFkLnMoMLL6HjuLmJlWupn1WLLAVkfGoNqnttPcrufyUJNn9k8zK0AU2nWJbu21xzOcO04jKLq0kPiZdkPjc8u8TZy96P(ymWxc74TJs32UjDPJkOQfn7odsSzzETN3Zw1TZuxkhd2SiS0fLtxTbrdGZxRxm6sEfOI05sZEd(7tjxorGwacBjOJe855M7SAaJ3SO5PSPbopm8c49tFOTdjcPKfLzvRhM5yoeul4LZhK5kAfhPZvWGmNbfYsEAKcpedYHc6VKkSMwsJQKUjhKxh1JKjtT6PJhsVIR0cQkSmfPnUuWgFdA77rgCIZuvkfRUh1x4MgJq2zZEutejevHACLtUQsW1gDZTKBUubh(sZTMBBEiFCN6KeURbehP445JtjH)jnIedU59W(qJzB67y688nN4zR6KlK3tQDdCBwBlJou3pquhAT7b0ddf0(M(Ea94abDqo0dO3oqqTfk9G6Dde1zsOE490j8A1e1TS5Ww0EbsyJOX1kHqdgDrQNkOoG9Ov2ZnOHBFIGwsWg76RH(GMSXSt7E3hchePe3VW9Vg4FhLy3vPlxE7qjUp7D27kpcy)VpTlvzF5A8asTMCPc)wnybxWXpO5lB)ELMLj)o]]
)
spec:RegisterPack(
    "Survival Melee (wowsims.com)",
    20261114000,
    [[Hekili:LJvupoQnq4Fl7lPjQBHK0BV2BvZj1Q2Q7Q6T6uz7Rao4bIlgBKTjrR0j(T3XeydqGnSDFQ7PvAJXEMppZ4XZ8j7VY)EFpkXa(3TE563UA1Q3SC5sFpZd5GVxojkLKGdeKm8)EfQ9S9eEz4NaoaLHZpipOzzANiz2cR4pWLeQfYTfmU5Jc)TdIUohI89(WFF39)2FDRUgvFVDmkfoQdOJU0(DBzOzhoz9CUXsfShuLHuiMuWnLH)8N)ZYqC6YWZrQG5ATcT7UcHbuU0CTR1OPAx9(GmRuoiS8fxJBJIi0C0nO4yPDBz6YqcLkfFdoifEq7ug(Red52bmN5F6J3JGSZyY1366MWm7k2A9a3EIUaXeTA4gY7IORjRPXroyqvjJzCm6tImmPq7KRau5TeZMicNhKdMRzXBUc)nqwyMzh4qbcD2vgcheghUuabhK8yhqq2YrV4podRVDJlAdS9qdEnOmSShdA6GmIkTA3PW2I4yN2Z7uKpSYeBGhn24a88lylq0h9GkegyX2a9Y95l7POeaVqa6aolzN56cnG2tCqseDZkRggwg8(n30wHTCPKgexOEyAIJbjqLYejts8mY)ivyqvqcYL2jNKwuitkyrbk0xMKcksodDcMAYIBqZsBuS0(AelJk01Asujyi(aM3ZeDaOtw0rnwpLSPNXElts4GtMCpKHPfZMxBmysJMrHBMn)Q5ZV6iSoevebZA07KgNuH8G4ldSateGvdsGfZMpVAanqbzeMq)tBw(LUZ8(nnIGj1a976(vxzxSyrFT7i9suGfDYjKIePeD8Tmd8k3xThZuqfKYIsFL7QhWAcbrCw(RC)SQo(XpXYSyhalfJnhi80aMOvzJgx9Pt9hTeZzzoJkjlltI94T2d2VVtXgDbUMiyh5q64hvddStThTbl3NJhHyflBr)wLOAk21rGo9oRHW2580j5qlNHSEy1R67Hmk0Oa9OEzJ1AldTA1WH3vrcSUpP)V47fPW4QIr89gZ4AyJGu5AVIVxLJzr0G7BpyBuPLxyf77hrStEJV9pVAADdzWnQ0qoOJl8mij8uw9jsdTrVbZHCKwDLSM8Ji1MCrBSQBXAH6nteQt0ogbOBMkqpsizeGE7eb6mQkJG3pmr8AtIzeO(Xjc1j6nJa07g9Eq3B3TsZFQn7ebfl4RwEXBz947CcS2l84MVUc1XV7(cBE887E8cBFC5(h)3I7JDHUtxKx5boBCyS6STBr(vqyOFP1MWWJDZ)kig0VRWzf6A8VETwp(rfFTJmjco(WqnCjSy3VrXLVU1T2QfJ(nhUyQ65q0VPqde9O5vjB)6(pUDN49vXmOFf8No1PVnzSVLt9RG8)hsmd3c6Y9UgGetdud8epDq8jEhi)AUGKcZoPY37dqkJZkdN)71pHw1Y()7p]]
)

-- The hand-built lists the wowsims.com packs replaced: a saved choice of one falls back to the spec's default.
spec:RetirePacks({ "BeastMastery", "Marksmanship", "Survival" })
-- The Beast Mastery and Marksmanship weave packs, whose wowsims builds are gone (upstream PR #1041; owner L1154): a
-- saved choice of one moves to the spec's default, its Turret pack, with the one-time retired notice (RestoreDefaults).
spec:RetirePacks({ "Beast Mastery (wowsims.com)", "Marksmanship (wowsims.com)" })
