-- tools/wowsims/specs/druid_feral.lua (wowsims packs plan, Task 7): Feral (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/druid/feralcat/presets.ts:19
-- (DefaultOptions), :31-37 (OtherDefaults), :109 (CatTalents, "Monocat") at the pin.
-- Replay (P7): decisions on-GCD 0.875 (n 88). Worked:
-- - Shifting Power's 7.5 s recasts are the pre-raid set's Howling Idol (272427): its equip aura 1291059 ("Reduces the
--   cooldown of your Shifting Power ability", in the log from 0.00) is now in the kit (-0.5 s, wowsims's; the DB2 effect
--   reads -1000 ms). Checked for other cooldown modifiers: the 16 pre-raid items (only the idol's aura appears in the
--   log), no set bonus aura, and the build's talents (Improved Shifting Power 2/2, -8 s).
-- 1. shifting_power -> rake 3, 2. shifting_power -> rip 2: still 0.5 s short at wowsims's recast. The aura is up in the
--    sim's state, but the belief's cooldown for Shifting Power (a function `cooldown`) answers 8 s from the cast
--    (C_Spell.GetSpellCooldown's model, start 27.74, duration 8.0 at 35.24), and the replay gives the client no
--    cooldown for a function `cooldown` (replay.lua `tonumber(a.cooldown)`): shared layers, recorded, not worked around.
-- 3. faerie_fire -> rake 1: the energy belief. Known deviations: wowsims refunds 80% of a dodged strike's energy
--    (OtherActionRefund, 8 in the log: no fork layer models a refund) and adds the Wolfshead Helm's 5 energy to
--    Shifting Power (45 in the log).
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
