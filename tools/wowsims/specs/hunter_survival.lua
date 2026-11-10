-- tools/wowsims/specs/hunter_survival.lua (wowsims packs plan, Task 11): Survival (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) at e5a9cd2a2d (0.7 re-pin; the weave is upstream acc6bcb5f8's: reaction 150-350 ms, no weave window read, so no `extra`, `windowVars` or `guard`): the request is the
-- SIML build ui/specs/hunter/dps/builds/sv_weave.siml (SV Weave: talents :3, gear ../gear_sets/p1.gear.siml :4, rotation
-- ../apls/default.apl.siml :5, settings :7-14; no pet (:7, Lone Wolf)), layered over the spec's
-- defaults.siml as wowsims's siml.LoadBuild does (the recipe's `defaults`: race Orc, Engineering and Blacksmithing, the
-- consumables (flask, food, elixirs, Demonic Rune, the Major Mana and Major Frenzy potions, EZ-Thro Dynamite II, Goblin
-- Sapper Charge), Kings, Might 2 and Wisdom 2, the top ranks: R25), converted by `make wowsims-siml`
-- (tests/Forever/wowsims/hunter_survival.build.json). Raid buffs and debuffs stay unsent, as for every spec.
-- Disagreements at e5a9cd2a2d (0.7 floors step): decisions on-GCD 0.946 (92); 4 of 5 misses are Serpent Sting believed up at the cast, about 0.33 s before it lands; the 5th is the strike ordering
-- (strider_kick -> multi_shot, the walk the replay cannot forecast; CN19). The notes below are the older e2842f0a78 numbers (0.989 of 90):
--   serpent_sting -> multi_shot (125.50): price. The replay's truth is 229.8 mana when wowsims stings and 4.95 after
--   (it charged 224.9); the kit prices Serpent Sting at 250, so the belief holds it and shows Multi-Shot. The source
--   of wowsims's 10% (a talent or an item) is not identified (deferral; wowsims's value wins once found).
-- Was (old pin d33930d040): 1.000 (41) under the melee world; the old notes (percent-of-base pricing) are history.
-- Content gaps fixed (P6): Resourcefulness (440529, 2/2) cuts Raptor Strike, Mongoose Bite, Wing Clip, Immolation Trap
-- and Strider Kick 60% (wowsims's 40, 26, 32, 98 and 39.6; 30% at rank 1): before it the bite was believed short of
-- mana at every window (0.415 -> 0.659), and with Raptor Strike priced too and the world's truth under the build's
-- talents 0.659 -> 0.780. Strider Kick's DB2 mask is outside 440529's, but wowsims's log charges it 39.6: the kit
-- follows the log.
-- Lacerating Strikes (1310536) and the trap's burn (14301) are procs no key maps.
-- Multi-Shot (2643): its cast is the DB2's 500 ms; wowsims has no cast time for it (instant there). Kept: the client
-- charges the DB2's, and the `action.multi_shot.cast+...<=mainhand_remains` line reads it (in-game checkpoint).
-- Unmodelled: Resourcefulness's second effect (1242688, from 1.38 s in the log: 30 s of 50% mana regen while casting
-- after a critical strike; the kit's mana belief has no hook for it).
-- autocastOtherCooldowns (rule 13, from the log's "Major cooldown used"): Blood Fury (20572, the Orc's), Rapid Fire
-- (3045), Demonic Rune and the Major Mana Potion, each `if=time>=5` at range, at the top of the list. Unmapped
-- autocast items (no kit key; precedent: the Warlock and Enhancement recipes): 250943 Major Frenzy Potion, 10646 Goblin
-- Sapper Charge, 18588 EZ-Thro Dynamite II.
-- Omitted (tools/wowsims/dry.lua): 14 -> 13 lines at the export (20 in the pack header after the regeneration: the
-- weave's waits and moves, resetSequence, never-lines, the three unmapped items).
-- Movement (rule 19, R51): the weave's move to melee (#6) reaches the strikes, its move back (#7) and the walk in
-- (walk_in #1) the shots and cooldowns; each reached line keeps its range gate in place and its move arm goes where
-- wowsims calls the group (after the shots), so a ready shot wins over the walk in. The recipe `ranges` are the DB2's
-- (Combat Range 0-5, Hunter Range 8-35, checked with wowdb).
return {
    class = "HUNTER",
    pack = "Survival (wowsims.com)",
    spec = "survival",
    name = "Survival",
    talentTree = "hunter",
    siml = "ui/specs/hunter/dps/builds/sv_weave.siml",
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
