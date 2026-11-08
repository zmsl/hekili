-- tools/wowsims/specs/druid_feral.lua (wowsims packs plan, Task 7): Feral (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/druid/feralcat/presets.ts:19
-- (DefaultOptions), :31-37 (OtherDefaults), :109 (CatTalents, "Monocat") at d33930d040; the re-pin (e2842f0a78) moves the
-- APL to apls/adaptive.apl.json (presets.ts:9, :65-68 JVMES_APL "Adaptive Cat", spec.ts:79 the default rotation;
-- 2250 lines); the gear stays gear_sets/pre_raid.gear.json (presets.ts:11, spec.ts:65).
-- Replay (re-pin e2842f0a78, Movement on): decisions on-GCD 0.916 (76/83), flicker 1.33/min (oracle 0.00). The
-- request follows the preset build (Tauren, 25 yd, CatTalents); assumeBleedActive only moves wowsims's own damage for
-- Feral (no Feral line reads druid_bleed_active). The Rip line's "two Blood Frenzy points with Shifting Power" read
-- `action.shifting_power.known` under R52 until central-talents registered Shifting Power as a Forever talent (Druid.lua's
-- talent table, 1322605); it now reads `talent.shifting_power.enabled` (the build takes it: 1322605=1@2).
-- Misses (log times), none content: 21.25 shred -> rip and 39.88 shred -> faerie_fire (energy is secret: the belief's
-- lo 3.2 and 1.0 under the truth at Rip's 62 threshold and Shred's 42 cost); 140.38 shred -> rip (Rip fades in the
-- instant wowsims Shreds); 19.25 shifting_power -> shred (a not-ready flag 0.05 s before the ready pushes it to now +
-- CD_PROBE: shared); 111.89 shifting_power -> shred (mana 687 against the 684 cost: the belief's mana near cost,
-- shared); 162.38 shred -> faerie_fire (after the missed 160.88 Faerie Fire: the belief holds Faerie Fire ready about
-- 0.1 s after every cast, kit or belief undetermined; a scalar 6 clears it in scratch); 15.04 innervate -> cat_form
-- (a 0.04 s tie at the Innervate powershift, pre-existing).
-- Owner deviation R69 (2026-11-06; L86): wowsims's "Drop Prowl for this opener" drops Prowl at once solo (its Ravage
-- opener needs another druid's Faerie Fire, tag -1, never known solo). The owner: recommend the optimal opener; a
-- player who cannot get behind the target simply does not press Ravage. So the pack has no Prowl cancel line
-- (`condition = { cancel_buff = false }`): while Prowl is up and the target in range (wowsims's Ravage line, with the
-- Movement gating) Ravage is the first icon; wowsims's Faerie Fire line above it (a cast breaks Prowl) waits while
-- Prowl is up (`guard`). Prowl ends when Ravage lands or the player attacks; the list then runs as wowsims's. The
-- pre-pull Prowl and Dash stay. Not yet checked in game.
-- Content kept from the old pin: the forms', Shifting Power's and Innervate's costs are percent of base mana (1244 at
-- 60); Shredding Attacks 3 points (Shred 42); the Howling Idol (272427, aura 1291059) takes 0.5 s off Shifting Power;
-- the Wolfshead Helm (8345, aura 17768) adds energy to Shifting Power; wowsims refunds 80% of a dodged strike's energy.
-- Translation gaps: Thistle Tea (selectedConjured), potions, sapper charges, item swaps, autocastOtherCooldowns (GAP
-- 14: no class cooldown lost). Time to die is unknown on Forever (3600), so the `fight_remains` lines read a long fight
-- (API-forced).
return {
    class = "DRUID",
    pack = "Feral (wowsims.com)",
    spec = "feral",
    name = "Feral",
    talentTree = "druid",
    apl = "ui/specs/druid/feralcat/apls/adaptive.apl.json",
    player = {
        race = "RaceTauren",
        class = "ClassDruid",
        gear = "ui/specs/druid/feralcat/gear_sets/pre_raid.gear.json",
        talentsString = "050022-53200032123012124001-055",
        specKey = "feralCatDruid",
        options = { assumeBleedActive = true },
        profession1 = "Engineering",
        profession2 = "Enchanting",
        reactionTimeMs = 250,
        distanceFromTarget = 25,
    },
    executePhase = "execute_phase",
    map = {},
    -- Faerie Fire's armor reduction is an exclusive effect (one slot with Curse of Recklessness: wowsims
    -- sim/core/debuffs_generated_test.go TestGeneratedCurseOfRecklessnessAndFaerieFireDoNotStack): rule 10
    exclusive = { [9907] = true },
    -- owner deviation R69 (header): no Prowl cancel line; Prowl ends when Ravage lands or the player attacks
    condition = { cancel_buff = false },
    -- R69 too: Faerie Fire (wowsims's line above Ravage) breaks Prowl, so it waits while Prowl is up
    guard = { faerie_fire = "!action.prowl.known|!buff.prowl.up" },
    -- by role (docs/dev/wowsims-packs.md): Shred's first line (Clearcasting) at 1, not the builder; Claw's one line is
    -- wowsims's "Claw can replace Shred" builder fallback, kept at tier 1 as before (R66)
    focus = { shred = { 1, false }, claw = { 1, false }, rip = 2, rake = 2 },
    leveling = {},
}
