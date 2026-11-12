-- tools/wowsims/specs/hunter_marksmanship_turret.lua (non-weave Hunter packs, owner 2026-11-12, ledger L661):
-- Marksmanship Turret (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) at e5a9cd2a2d: the request is the SIML build
-- ui/specs/hunter/dps/builds/mm.siml (wowsims's "MM" build: talents :3, gear ../gear_sets/p1.gear.siml :4, rotation
-- ../apls/turret.apl.siml :5, settings :8-14; no pet (:7, Lone Wolf)), layered over the spec's defaults.siml as
-- wowsims's siml.LoadBuild does (as hunter_marksmanship.lua), converted by `make wowsims-siml`
-- (tests/Forever/wowsims/hunter_marksmanship_turret.build.json).
-- The Turret list: no melee; Hunter's Mark and Serpent Sting kept up, Arcane Shot on cooldown, Aimed Shot, Multi-Shot
-- off, Sniper Shot (this build's 41-point talent) the filler and the pull's opener, and the walk in from Pull range to
-- the 12 yd spot. Picked from the talents (Hunter.lua's selectors): Sniper Shot taken.
-- Movement (rule 19): the walk in's move reaches the shots and cooldowns, as in the weave packs.
return {
    class = "HUNTER",
    pack = "Marksmanship Turret (wowsims.com)",
    spec = "marksmanship",
    name = "Marksmanship Turret",
    talentTree = "hunter",
    siml = "ui/specs/hunter/dps/builds/mm.siml",
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
