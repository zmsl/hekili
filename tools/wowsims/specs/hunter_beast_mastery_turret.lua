-- tools/wowsims/specs/hunter_beast_mastery_turret.lua (non-weave Hunter packs, owner 2026-11-12, ledger L661): Beast
-- Mastery Turret (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) at e5a9cd2a2d: the request is the SIML build
-- ui/specs/hunter/dps/builds/bm.siml (wowsims's "BM" build: talents :3, gear ../gear_sets/p1.gear.siml :4, rotation
-- ../apls/turret.apl.siml :5, settings :7-14; pet_type raptor (:12): the Raptor, whose casts are not scored), layered
-- over the spec's defaults.siml as wowsims's siml.LoadBuild does (as hunter_beast_mastery.lua), converted by
-- `make wowsims-siml` (tests/Forever/wowsims/hunter_beast_mastery_turret.build.json).
-- The Turret list: no melee; Hunter's Mark and Serpent Sting kept up, Arcane Shot on cooldown (Use Arcane Shot on, Use
-- Summon Hawk off), Aimed Shot (Use Aimed Shot on), Multi-Shot off, Sniper Shot the filler and the pull's opener (this
-- build has no Sniper Shot talent, so those lines stay silent), and the walk in from Pull range to the 12 yd spot.
-- Picked from the talents (Hunter.lua's selectors): Improved Arcane Shot taken, Efficiency not (the weave build's
-- Marksmanship picks are the other way round).
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
    -- rule 19 (R4): the DB2's ranges (Hunter Range 8-35; Sniper Shot 8-45) of the shots the APL gives no bracket
    ranges = {
        arcane_shot = { 8, 35 },
        aimed_shot = { 8, 35 },
        multi_shot = { 8, 35 },
        serpent_sting = { 8, 35 },
        sniper_shot = { 8, 45 },
    },
    leveling = {},
}
