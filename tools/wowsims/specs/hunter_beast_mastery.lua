-- tools/wowsims/specs/hunter_beast_mastery.lua (wowsims packs plan, Task 11): Beast Mastery (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) at e5a9cd2a2d (0.7 re-pin; the weave is upstream acc6bcb5f8's: reaction 150-350 ms, no weave window read, so no `extra`, `windowVars` or `guard`): the request is the
-- SIML build ui/specs/hunter/dps/builds/bm_weave.siml (BM Weave: talents :3, gear ../gear_sets/p1.gear.siml :4, rotation
-- ../apls/default_hawks.apl.siml :5, settings :7-14; pet_type raptor (:12): the Raptor, whose casts are not
-- scored), layered over the spec's defaults.siml as wowsims's siml.LoadBuild does (the recipe's `defaults`: race Orc, Engineering and Blacksmithing, the
-- consumables (flask, food, elixirs, Demonic Rune, the Major Mana and Major Frenzy potions, EZ-Thro Dynamite II, Goblin
-- Sapper Charge), Kings, Might 2 and Wisdom 2, the top ranks: R25), converted by `make wowsims-siml`
-- (tests/Forever/wowsims/hunter_beast_mastery.build.json). Raid buffs and debuffs stay unsent, as for every spec.
-- Owner policy (2026-11-11): replace wowsims's atomic Hawk/Hawk/Arcane sequence with the live priority: maintain two
-- hawks, choose Aimed Shot for one target or Multi-Shot for a group, then use Arcane Shot when its separate cooldown is
-- ready. Summon Hawk shares its cooldown with Arcane Shot; Aimed Shot shares its cooldown with Multi-Shot.
-- Disagreements below are the e2842f0a78 numbers, STALE until the 0.7 floors are re-measured (P7, after R51), decisions
-- on-GCD 0.929 (70); the old HHA sequence disagreements no longer describe this owner policy.
--   Serpent Sting a beat early (class B; 31.37, 47.71): the kit applies the target's dot at the cast (`now`), wowsims at the landing
--   (0.33 s later in every log); with EARLY_EXIT (0.2 s, Core.lua) a refresh due inside 0.2 s ends the list, so it
--   outranks a shot ready now. The belief has no landing hook for a kit aura (Tickets.lua anchors only the tick
--   schedule after the flight): central, a limit here (deferral).
-- Was (old pin d33930d040): 1.000 (27); the old disagreement notes (percent-of-base pricing) are history.
-- Kit fix (P6): past a due swing out of melee, `mainhand_remains` reads 0 (wowsims's timer stays due until the walk
-- in lands one), not a swing a period later; the phantom swing let Multi-Shot win projected ties at 11 yd (loop gate).
-- Content gap fixed (P6): Efficiency (19416, 2/5 here) cuts the shots', stings' and strikes' prices 3% a rank (wowsims's
-- 94 Raptor Strike, 75.2 Wing Clip, 178.6 Arcane Shot, 235 Serpent Sting, 224.66 Multi-Shot); before it the client
-- (the world's truth) and the belief priced them at full cost (0.741 -> 0.815).
-- Lacerating Strikes (1310536) and the trap's burn (14301) are procs no key maps.
-- Multi-Shot (2643): its cast is the DB2's 500 ms; wowsims has no cast time for it (instant there). Kept: the client
-- charges the DB2's, and the `action.multi_shot.cast+...<=mainhand_remains` line reads it (in-game checkpoint).
-- autocastOtherCooldowns (rule 13, from the log's "Major cooldown used"): Blood Fury (20572, the Orc's), Rapid Fire
-- (3045), Bestial Wrath (19574, the talent: a kit ability since the re-pin), Demonic Rune and the Major Mana Potion,
-- each `if=time>=5` at range, at the top of the list. Unmapped autocast items (no kit key; precedent: the Warlock and
-- Enhancement recipes): 250943 Major Frenzy Potion, 10646 Goblin Sapper Charge, 18588 EZ-Thro Dynamite II.
-- Omitted (tools/wowsims/dry.lua): 15 -> 14 lines at the export (20 in the pack header after the regeneration: the
-- weave's waits and moves, resetSequence, never-lines, the three unmapped items).
-- Movement (rule 19, R51): the weave's move to melee (#6) reaches the strikes, its move back (#7) and the walk in
-- (walk_in #1) the shots and cooldowns; each reached line keeps its range gate in place and its move arm goes where
-- wowsims calls the group (after the shots), so a ready shot wins over the walk in. The recipe `ranges` are the DB2's
-- (Combat Range 0-5, Hunter Range 8-35, checked with wowdb).
return {
    class = "HUNTER",
    pack = "Beast Mastery (wowsims.com)",
    spec = "beast_mastery",
    name = "Beast Mastery",
    talentTree = "hunter",
    siml = "ui/specs/hunter/dps/builds/bm_weave.siml",
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
        aimed_shot = { 8, 35 },
        multi_shot = { 8, 35 },
        serpent_sting = { 8, 35 },
    },
    -- The upstream HHA sequence is atomic, so omitting Summon Hawk rejects that sequence as a whole. Arcane Shot's
    -- condition also omits its separate upstream fallback; the explicit lines below implement the owner priority.
    condition = {
        summon_hawk = false,
        arcane_shot = false,
        aimed_shot = false,
    },
    guard = {
        multi_shot = "active_enemies>1",
    },
    extra = {
        { before = "multi_shot", line = "summon_hawk,if=action.summon_hawk.known&pet.hawk.count<2" },
        { before = "multi_shot", line = "aimed_shot,if=active_enemies=1&target.outside8" },
        { before = "call_action_list", line = "arcane_shot,if=target.outside8" },
    },
    -- A normal action line needs no explicit cooldown expression: the engine skips it until the ability is usable.
    leveling = {},
}
