-- tools/wowsims/specs/hunter_marksmanship.lua (wowsims packs plan, Task 11): Marksmanship (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) at e5a9cd2a2d (0.7 re-pin; the weave is upstream acc6bcb5f8's: reaction 150-350 ms, no weave window read, so no `extra`, `windowVars` or `guard`): the request is the
-- SIML build ui/specs/hunter/dps/builds/mm_weave.siml (MM Weave: talents :3, gear ../gear_sets/p1.gear.siml :4, rotation
-- ../apls/default_mm.apl.siml :5, settings :7-14; no pet (:7, Lone Wolf)), layered over the spec's
-- defaults.siml as wowsims's siml.LoadBuild does (the recipe's `defaults`: race Orc, Engineering and Blacksmithing, the
-- consumables (flask, food, elixirs, Demonic Rune, the Major Mana and Major Frenzy potions, EZ-Thro Dynamite II, Goblin
-- Sapper Charge), Kings, Might 2 and Wisdom 2, the top ranks: R25), converted by `make wowsims-siml`
-- (tests/Forever/wowsims/hunter_marksmanship.build.json). Raid buffs and debuffs stay unsent, as for every spec.
-- Disagreements below are the e2842f0a78 numbers, STALE until the 0.7 floors are re-measured (P7, after R51), decisions on-GCD 0.966 (87) top [arcane_shot ->
-- serpent_sting 2; serpent_sting -> arcane_shot 1]:
--   Serpent Sting a beat early (class B; 15.16, 140.34): the kit applies the target's dot at the cast (`now`), wowsims at the landing
--   (0.33 s later in every log); with EARLY_EXIT (0.2 s, Core.lua) a refresh due inside 0.2 s ends the list, so it
--   outranks a shot ready now. The belief has no landing hook for a kit aura (Tickets.lua anchors only the tick
--   schedule after the flight): central, a limit here (deferral).
--   serpent_sting -> arcane_shot (125.34): wowsims drinks a Major Mana Potion (13444) at 125.34 and stings at once:
--   a refill the mana belief cannot see (R50 class A).
-- Was (old pin d33930d040): 0.929 (42); its strider_kick -> wing_clip notes are history.
-- Kit fix (P6): Improved Arcane Shot (19454, 3/5 here) cuts Arcane Shot's cooldown 0.3 s a rank (wowsims's curve
-- {-300 .. -1500}; DB2 has only rank 1's row): wowsims casts it 5.1 s apart, and the 6 s kit showed Multi-Shot then
-- Arcane Shot a beat late (0.833 -> 0.881, with the swing fix in hunter_beast_mastery.lua).
-- Prices (P6): Resourcefulness 2/2 (440529) cuts Raptor Strike, Mongoose Bite, Wing Clip, Immolation Trap and Strider
-- Kick 60% (wowsims's 40, 26, 32, 98, 39.6).
-- Lacerating Strikes (1310536) and the trap's burn (14301) are procs no key maps.
-- Multi-Shot (2643): its cast is the DB2's 500 ms; wowsims has no cast time for it (instant there). Kept: the client
-- charges the DB2's, and the `action.multi_shot.cast+...<=mainhand_remains` line reads it (in-game checkpoint).
-- autocastOtherCooldowns (rule 13, from the log's "Major cooldown used"): Blood Fury (20572, the Orc's), Rapid Fire
-- (3045, from the pull: MM sets Rapid Fire at the pull), Demonic Rune and the Major Mana Potion, the others `if=time>=5`, all
-- at range, at the top of the list. Unmapped
-- autocast items (no kit key; precedent: the Warlock and Enhancement recipes): 250943 Major Frenzy Potion, 10646 Goblin
-- Sapper Charge, 18588 EZ-Thro Dynamite II.
-- Omitted (tools/wowsims/dry.lua): 14 -> 13 lines at the export (20 in the pack header after the regeneration: the
-- weave's waits and moves, resetSequence, never-lines, the three unmapped items).
-- Movement (rule 19, R51): the weave's move to melee (#6) reaches the strikes, its move back (#7) and the walk in
-- (walk_in #1: never called in MM) the shots and cooldowns; each reached line keeps its range gate in place and its move arm goes where
-- wowsims calls the group (after the shots), so a ready shot wins over the walk in. The recipe `ranges` are the DB2's
-- (Combat Range 0-5, Hunter Range 8-35, checked with wowdb).
return {
    class = "HUNTER",
    pack = "Marksmanship (wowsims.com)",
    spec = "marksmanship",
    name = "Marksmanship",
    talentTree = "hunter",
    siml = "ui/specs/hunter/dps/builds/mm_weave.siml",
    -- the spec defaults the build is layered over (race Orc, professions, consumables, player buffs: siml.LoadBuild)
    defaults = "ui/specs/hunter/dps/defaults.siml",
    map = {},
    -- by role (docs/dev/wowsims-packs.md); the melee-weave strikes rotational, Serpent Sting 1 (the user, 2026-10-21)
    focus = { raptor_strike = 1, hunters_mark = 2, serpent_sting = 1 },
    -- rule 19 (R4): the DB2's ranges (SpellMisc.RangeIndex -> SpellRange: Combat Range 0-5, Hunter Range 8-35) of the
    -- strikes and shots the APL gives no bracket, so the weave's melee move reaches the strikes and its move back the shots
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
