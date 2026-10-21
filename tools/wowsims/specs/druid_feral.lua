-- tools/wowsims/specs/druid_feral.lua (wowsims packs plan, Task 7): Feral (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/druid/feralcat/presets.ts:19
-- (DefaultOptions), :31-37 (OtherDefaults), :109 (CatTalents, "Monocat") at the pin.
-- Replay (P7): decisions on-GCD 0.898 (n 88; 0.909 before the lane fix round's Howling Idol -1 s), after central fix 6
-- gave the replay the log's mana pool and regen.
-- Temporary workaround for shared GAP U (Now.lua's context has no `level`): the kit's `ofBaseMana` caches the
-- simulation's last level so the belief prices the same cost; remove it when GAP U lands.
-- Worked (Task 7b):
-- - Content: the forms', Shifting Power's and Innervate's costs are percent of base mana, 1244 at 60 (the log's 684,
--   684 and 62), not of the maximum (2674: 1203 believed): right per the goal (wowsims prices them so); Shredding
--   Attacks has 3 points (Shred 42 at 3/3, the log's; the DB2 node lists 2 rank spells); mana declares the
--   five-second rule (22 a second outside it, none inside: the log's regen lines; 0.920 without it, one decision
--   more, but the belief then regenerates nothing in combat).
--   The world's usability now reads the kept mana pool (it said mana-free).
-- - The pre-raid set's Howling Idol (272427): its equip aura 1291059 takes 1 s off Shifting Power (DB2 -1000 ms,
--   wowsims's TestHowlingIdolShortensShiftingPower); the log's 7.5 s recasts are 7 s plus the 250 ms reaction twice.
--   Other cooldown modifiers checked: none. The 1 s costs one decision (lane fix round), a second faerie_fire ->
--   shred (113.74, log time): Shifting Power, cast at 107.74, is exactly 1.000 s from ready, so wowsims's "Shifting
--   Power >= 1 s away" holds on the tie; ours reads it just under (a timing tie, not a content error; at -0.5 s the
--   margin was 1.5 s).
-- - The Wolfshead Helm (8345): its equip aura 17768 (the log gains it at 0 s) adds 5 energy to Shifting Power (45 in
--   the log) and half again to Enrage's instant rage (wowsims sim/druid/items.go): in the kit. No decision moved.
-- 1. shred -> shifting_power 2: at 41.24 the belief reads Shifting Power's function `cooldown` as 0 at the cast
--    (shared gap, not worked around); at 143.74 the mana belief sits a mana over the truth at the 684 cost (the
--    belief, shared; at 107.74 the opposite: shifting_power -> rake 1).
-- 2. faerie_fire -> rake 1 (45.74), 3. faerie_fire -> shred 1 (38.74): the same function-`cooldown` gap: the belief
--    believes Shifting Power ready, so "Faerie Fire for Omen" (Shifting Power >= 1 s away) fails. A scalar 7.5 s
--    cooldown (scratch) clears all three cooldown cases.
-- Also: ferocious_bite -> rake 1 (177.99): "Bite at the end" reads the fight's last 3 s; time to die is not modelled
--    on Forever (API-forced, below); innervate -> cat_form 1; shred -> rake 1 (73.99).
--    Known deviation: wowsims refunds 80% of a dodged strike's energy (OtherActionRefund, 8 in the log: central fix
--    7's).
-- The Berserk group's two strictSequence entries (Berserk then Rake or Shred; Berserk is cast once in 180 s) are rule
-- 14's lines since central fix 13: both open on `prev.1.berserk`, so each later member keeps its own sequence's terms
-- (Rake now, or not) to stay apart. Translation gaps: Thistle Tea (selectedConjured), the potion, sapper charges, autocastOtherCooldowns (GAP 14: this spec
-- loses no class cooldown to it; wowsims casts no other cooldown in the log). Time to die is unknown on Forever (3600),
-- so the `fight_remains` lines read a long fight (API-forced).
return {
    class = "DRUID",
    pack = "Feral (wowsims.com)",
    spec = "feral",
    name = "Feral",
    talentTree = "druid",
    apl = "ui/specs/druid/feralcat/apls/default.apl.json",
    player = {
        race = "RaceNightElf",
        class = "ClassDruid",
        gear = "ui/specs/druid/feralcat/gear_sets/pre_raid.gear.json",
        talentsString = "050022-55000032021031212051-054",
        specKey = "feralCatDruid",
        options = { assumeBleedActive = true },
        profession1 = "Engineering",
        profession2 = "Enchanting",
        reactionTimeMs = 250,
        distanceFromTarget = 0,
    },
    executePhase = "execute_phase",
    map = {},
    -- by role (docs/dev/wowsims-packs.md): Shred and Claw on Clearcasting (the first of each), not as builders
    focus = { shred = { 1, false }, claw = { 1, false }, rip = 2, rake = 2 },
    leveling = {},
}
