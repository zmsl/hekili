-- tools/wowsims/specs/druid_feral.lua (wowsims packs plan, Task 7): Feral (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/druid/feralcat/presets.ts:19
-- (DefaultOptions), :31-37 (OtherDefaults), :109 (CatTalents, "Monocat") at the pin.
-- Replay (P7): decisions on-GCD 0.909 (n 88), after central fix 6 gave the replay the log's mana pool and regen.
-- Worked (Task 7b):
-- - Content: the forms', Shifting Power's and Innervate's costs are percent of base mana, 1244 at 60 (the log's 684,
--   684 and 62), not of the maximum (2674: 1203 believed): right per the goal (wowsims prices them so); Shredding
--   Attacks has 3 points (Shred 42 at 3/3, the log's; the DB2 node lists 2 rank spells); mana declares the five-second rule (22 a second outside it, none inside:
--   the log's regen lines; 0.920 without it, one decision more, but the belief then regenerates nothing in combat).
--   The world's usability now reads the kept mana pool (it said mana-free).
-- - Shifting Power's 7.5 s recasts are the pre-raid set's Howling Idol (272427): its equip aura 1291059 is in the kit
--   (-0.5 s, wowsims's; the DB2 effect reads -1000 ms). Other cooldown modifiers checked: none.
-- 1. shred -> shifting_power 2: at 41.24 the belief reads Shifting Power's function `cooldown` as 0 at the cast
--    (shared gap, not worked around); at 143.74 the mana belief sits a mana over the truth at the 684 cost (the
--    belief, shared; at 107.74 the opposite: shifting_power -> rake 1).
-- 2. faerie_fire -> rake 1 (45.74), 3. faerie_fire -> shred 1 (38.74): the same function-`cooldown` gap: the belief
--    believes Shifting Power ready, so "Faerie Fire for Omen" (Shifting Power >= 1 s away) fails. A scalar 7.5 s
--    cooldown (scratch) clears all three cooldown cases.
-- Also: ferocious_bite -> rake 1 (177.99): "Bite at the end" reads the fight's last 3 s; time to die is not modelled
--    on Forever (API-forced, below); innervate -> cat_form 1; shred -> rake 1 (73.99).
--    Known deviations: wowsims refunds 80% of a dodged strike's energy (OtherActionRefund, 8 in the log: central fix
--    7's) and adds the Wolfshead Helm's 5 energy to Shifting Power (45 in the log).
-- Translation gaps: the Berserk group's two strictSequence entries (Berserk then Rake or Shred; Berserk is cast once
-- in 180 s), Thistle Tea (selectedConjured), the potion, sapper charges, autocastOtherCooldowns (GAP 14: this spec loses
-- no class cooldown to it; wowsims casts no other cooldown in the log). Time to die is unknown on Forever (3600), so the
-- `fight_remains` lines read a long fight (API-forced).
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
    focus = { shred = 1, claw = 1, rip = 1, rake = 2, innervate = 2 }, -- the retired Feral list's tiers (P9.3)
    leveling = {},
}
