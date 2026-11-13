-- tools/wowsims/specs/mage_frost.lua (new packs, owner-approved 2026-11-12): Frost (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) at the pin: ui/specs/mage/dps/apls/frost.apl.json,
-- the Frost Incin talents 203205-5-053500011121331251 (presets.ts FrostIncinTalents; sim/mage/mage_test.go
-- FrostTalents: 15 Arcane, 5 Fire, 31 Frost), the gear p1Arcane.gear.json, Human (apply_defaults.ts: the class's
-- first), 100 ms reaction time, 28 yd.
-- Disagreements (P7; floor 0.93), decisions on-GCD 0.934 (57 of 61) top [frostbolt -> cone_of_cold 3; cone_of_cold ->
-- frostbolt 1] (log times):
--   frostbolt -> cone_of_cold (13.0, 43.5, 86.0): the kit adds Winter's Chill's stack at the Frostbolt's cast end,
--   wowsims at its hit 0.3 s later (13.30, 43.80, 86.30), so the belief reads 5/5 one bolt early (at 13.0 it also counts
--   the 8.29 miss, which the client does not show). A gap: an impact-time stack would close it (Mage.lua `chilled`).
--   cone_of_cold -> frostbolt (145.7): wowsims's mana gem at the same instant, its mana not believed at the instant (lo
--   914 under the truth): the shared gap CR (mage_frostfire.lua's 148.90).
-- Deviations: Blink (pre-pull #3) is omitted, its time an aura duration the translator does not fold, so Blink is not
-- registered; Winter's Chill's 20% a rank roll is unseen, so ranks 1-4 add a stack on every Frostbolt as rank 5 does
-- (the kit's shortcut; this build is 5/5); the kit declares Fire's regen starting point for Frost (Mage Armor's half
-- while casting, 14.56 mp5), which the out-of-combat read and the in-combat calibration replace, where the world runs
-- the log's pool (6348).
-- Loops (20 fights, seeds 1-20 / 21-40 / 41-60; the harness's seeded regen phase, 2026-11-13): agreement .996 / .998 /
-- .998, flicker 0 x3, heldReady 112 / 111 / 109.
return {
    class = "MAGE",
    pack = "Frost (wowsims.com)",
    spec = "frost",
    name = "Frost",
    talentTree = "mage",
    apl = "ui/specs/mage/dps/apls/frost.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassMage",
        gear = "ui/specs/mage/dps/gear_sets/p1Arcane.gear.json",
        talentsString = "203205-5-053500011121331251",
        specKey = "mage",
        options = { classOptions = { defaultMageArmor = "MageArmorMageArmor" } },
        profession1 = "Engineering",
        profession2 = "Tailoring",
        reactionTimeMs = 100,
        distanceFromTarget = 28,
    },
    -- the Talisman of Ephemeral Power (ItemSparse 18820: a trinket, InventoryType 12)
    map = { ["item:18820"] = "use_items" },
    -- by role (docs/dev/wowsims-packs.md): Cone of Cold on five Winter's Chill stacks and Ice Lance on a Fingers of
    -- Frost charge are windows to catch (1); Ice Barrier, kept up for Frigid Power, is upkeep (2)
    focus = { cone_of_cold = 1, ice_lance = 1, ice_barrier = 2 },
}
