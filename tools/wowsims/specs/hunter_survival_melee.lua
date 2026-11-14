-- tools/wowsims/specs/hunter_survival_melee.lua (non-weave Hunter packs, owner 2026-11-12, ledger L661): Survival
-- Melee (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) at e5a9cd2a2d: the request is the SIML build
-- ui/specs/hunter/dps/builds/sv_melee.siml (wowsims's "SV Melee" build: talents :3, gear
-- ../gear_sets/p1_melee.gear.siml :4 (two one-handers), rotation ../apls/melee.apl.siml :5, settings :7-14 at 5 yd;
-- pet_type raptor (:12), whose casts are not scored; its own consumables :17-31, both hands sharpened), layered over
-- the spec's defaults.siml as wowsims's siml.LoadBuild does, converted by `make wowsims-siml`
-- (tests/Forever/wowsims/hunter_survival_melee.build.json).
-- The Melee list: Aspect of the Beast, Raptor Strike on every swing, Hunter's Mark kept up, the walk into melee
-- (Serpent Sting, Arcane Shot and Multi-Shot on the way in), then Mongoose Bite, Strider Kick, Immolation Trap, Summon
-- Hawk and Wing Clip. Picked from the talents (Hunter.lua's selectors): Survivalist's Discipline taken (no other
-- Hunter build of wowsims's takes it).
-- Movement (rule 19): the walk in's move reaches the shots on the way in.
return {
    class = "HUNTER",
    pack = "Survival Melee (wowsims.com)",
    spec = "survival",
    name = "Survival Melee",
    talentTree = "hunter",
    siml = "ui/specs/hunter/dps/builds/sv_melee.siml",
    -- the spec defaults the build is layered over (race Orc, professions, consumables, player buffs: siml.LoadBuild)
    defaults = "ui/specs/hunter/dps/defaults.siml",
    map = {},
    -- by role (docs/dev/wowsims-packs.md): the strikes rotational, the upkeep Mark at 2, Serpent Sting at 1, as the
    -- weave packs
    focus = { raptor_strike = 1, hunters_mark = 2, serpent_sting = 1 },
    -- rule 19 (R4): the DB2's ranges (Combat Range 0-5, Hunter Range 8-35) of the strikes and shots the APL gives no
    -- bracket
    ranges = {
        raptor_strike = { 0, 5 },
        mongoose_bite = { 0, 5 },
        strider_kick = { 0, 5 },
        wing_clip = { 0, 5 },
        arcane_shot = { 8, 35 },
        multi_shot = { 8, 35 },
        serpent_sting = { 8, 35 },
    },
    leveling = {},
}
