-- tools/wowsims/specs/hunter_beast_mastery_turret.lua (non-weave Hunter packs, owner 2026-11-12, ledger L661): Beast
-- Mastery Turret (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) at ab0f00e4fc (re-pin e4ef929e54 -> ab0f00e4fc): the request is the
-- SIML build ui/specs/hunter/dps/builds/bm.siml (wowsims's "BM" build: talents :3, gear
-- ../gear_sets/prebis_turret.gear.siml :4 (Pre-BiS), rotation ../apls/turret_hawk.apl.siml :5, settings :7-14;
-- pet_type raptor (:12): the Raptor, whose casts are not scored), layered over the spec's defaults.siml as wowsims's
-- siml.LoadBuild does, converted by `make wowsims-siml` (tests/Forever/wowsims/hunter_beast_mastery_turret.build.json).
-- The hawk Turret list (upstream 65b3f51f61; owner L1154 (2): follow it): no melee; Hunter's Mark and Serpent Sting
-- kept up, then the "HHA" sequence (Summon Hawk, Summon Hawk, Arcane Shot, reset when complete: the class's `hha`
-- window, Hunter.lua), Aimed Shot, Multi-Shot off, and the walk in from Pull range (pull.apl.siml) to the 12 yd spot.
-- No Sniper Shot (the hawk list has none). The sequence's reads stay `window.hha.next.*` lines (the windows rebuild,
-- Phase 3, converts the class window later; no sequence lines here).
-- The weave build's HHA notes (the retired Beast Mastery (wowsims.com) pack, L1154): wowsims's APLActionSequence
-- advances its index only when the cast (or its queued action) fires (sim/core/apl_actions_sequences.go), so a queued
-- hawk can stall the sequence where the kit's stepped window counts each cast (an oracle quirk, re-pin R15).
-- Talents (the build's): Improved Arcane Shot taken, Efficiency not.
-- Movement (rule 19): the walk in's move reaches the shots and cooldowns, as in the weave packs.
return {
    class = "HUNTER",
    pack = "Beast Mastery Turret (wowsims.com)",
    spec = "beast_mastery",
    name = "Beast Mastery Turret",
    talentTree = "hunter",
    siml = "ui/specs/hunter/dps/builds/bm.siml",
    -- the spec defaults the build is layered over (race Orc, professions, consumables, player buffs: siml.LoadBuild)
    defaults = "ui/specs/hunter/dps/defaults.siml",
    map = {},
    -- by role (docs/dev/wowsims-packs.md): the upkeep Mark at 2, Serpent Sting at 1, as the weave packs
    focus = { hunters_mark = 2, serpent_sting = 1 },
    -- rule 19 (R4): the DB2's ranges (Hunter Range 8-35) of the shots the APL gives no bracket
    ranges = {
        arcane_shot = { 8, 35 },
        aimed_shot = { 8, 35 },
        multi_shot = { 8, 35 },
        serpent_sting = { 8, 35 },
    },
    -- below 25 (Summon Hawk's learn level) the HHA window never reaches Arcane Shot (its first step is a hawk): wowsims's
    -- own non-hawk line (`cast arcane_shot if $use_arcane_shot and not $use_summon_hawk`), keyed on Summon Hawk being
    -- known, not on the setting (R41: a real rotation shot, silent at 60; carried from the retired weave recipe); its
    -- range gate written in (rule 19 reaches APL lines only)
    leveling = { "arcane_shot,if=!action.summon_hawk.known&target.outside8" },
    -- L1059 (owner): no pet out, call it; the pet dead, revive it: both lead the lists (levelingFirst puts them first
    -- in precombat and default). A Lone Wolf Hunter wants none out.
    levelingFirst = { "call_pet,if=!pet_out&!pet.dead&!talent.lone_wolf.enabled", "revive_pet,if=pet.dead" },
}
