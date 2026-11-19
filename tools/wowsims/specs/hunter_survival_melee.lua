-- tools/wowsims/specs/hunter_survival_melee.lua (non-weave Hunter packs, owner 2026-11-12, ledger L661): Survival
-- Melee (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) at ab0f00e4fc (re-pin e4ef929e54 -> ab0f00e4fc): the request is the
-- SIML build ui/specs/hunter/dps/builds/sv_melee.siml (wowsims's "SV Melee" build: talents :3, retuned again
-- 53200005001-005005-5302002300500221 (c635d67fca, #1081; owner L1396: follow), gear
-- ../gear_sets/prebis_melee.gear.siml :4 (Pre-BiS, two one-handers), rotation ../apls/melee.apl.siml :5, settings
-- :7-14 at 5 yd; pet_type raptor (:12), whose casts are not scored; its own consumables :17-31, both hands sharpened),
-- layered over the spec's defaults.siml as wowsims's siml.LoadBuild does, converted by `make wowsims-siml`
-- (tests/Forever/wowsims/hunter_survival_melee.build.json).
-- The Melee list: Aspect of the Beast, Raptor Strike on every swing, Hunter's Mark kept up, the run out for Serpent
-- Sting (Strider Kick's speed up, the Sting down, mana over 30%: the walk in's group, which stings on the way back in),
-- the walk into melee (Serpent Sting, Arcane Shot and Multi-Shot on the way in), then Mongoose Bite, Strider Kick,
-- Immolation Trap, Summon Hawk and Wing Clip. Talents (the build's): Survivalist's Discipline taken (no other Hunter
-- build of wowsims's takes it).
-- Immolation Trap is the first melee cast (c635d67fca: ahead of Mongoose Bite and Strider Kick). Lacerating Strikes
-- (1310536) is the bite's bleed (the kit applies it at the bite; no list reads it). 1265634 (an arcane hit, no cost, off the GCD) is a
-- gear proc no key maps.
-- The Major Mana Potion line is back at ab0f00e4fc (rule 13 writes one line per cooldown the log's "Major cooldown
-- used" lines name; the build's resource_pot drinks it).
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
    -- L1059 (owner): no pet out, call it; the pet dead, revive it: both lead the lists (levelingFirst puts them first
    -- in precombat and default). A Lone Wolf Hunter wants none out.
    levelingFirst = { "call_pet,if=!pet_out&!pet.dead&!talent.lone_wolf.enabled", "revive_pet,if=pet.dead" },
}
