-- tools/wowsims/specs/mage_arcane.lua (wowsims packs plan, Task 12): Arcane (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/mage/dps/presets.ts:15,19,31-35
-- (ArcaneAplPreset, ArcaneTalents, DefaultOptions), :37-41 (OtherDefaults), the gear p1Arcane.gear.json (the spec's
-- default, spec.ts:82) and ui/features/settings/model/apply_defaults.ts:68,97 (spec.ts names no race: the class's
-- first, Human, ui/sim/player/classes/capabilities_auto_gen.ts:65; the reaction time the UI defaults to, 100 ms) at
-- the pin.
-- Ruling M9 (Arcane Blast): the log casts it in 1.5 s unhasted (1.128 s under the Mind Quickening Gem) and each run of
-- charges ends 15 s after its first (2.26 -> 17.26, 44.67 -> 59.67, 60.17 -> 75.17: a later Blast adds a charge without
-- refreshing it); the DB2 at 70338 says 2.5 s and 8 s, wowsims's data (build 70450, hotfix 112887) 1.5 s and 15 s. The
-- kit and the world take wowsims's (Mage.lua's header); the in-game cast bar is the check. The log prices a charge as
-- 181 x (1 + 1.75 n) (497.75, 814.5, 1131.25), the kit's spendBase floor(fraction x 1213) (500, 818, 1137, 1455).
-- Disagreements (P7; floor 0.77), decisions on-GCD 0.780 (59) top [arcane_blast -> arcane_missiles 4; arcane_blast ->
-- frostbolt 3; frostbolt -> arcane_blast 2]:
--   arcane_blast -> arcane_missiles (log 3.38, 46.17, 58.67, 79.17): translation (rule 5 ignores
--   includeReactionTime): Missile Barrage procs at the previous cast's completion and wowsims reads it after its 100 ms
--   reaction time, so one more Blast goes first; we show Missiles at once. The same read makes arcane_blast -> frostbolt
--   at 67.67 (the charges, read with the reaction time) and frostbolt -> arcane_missiles at 69.17 and 148.67: 7 of 13.
--   arcane_blast -> frostbolt (9.64, 21.67; arcane_wrath -> frostbolt at 123.47): shared gap: the belief runs about
--   1000 mana under the truth after a mana gem (the Ruby's +1109 at 3.38, the Citrine's +914 at 123.47): Hekili_Shared's
--   mana_gem has no `now` gain and the replay emits no cast for an item's use (replay.lua: "an item: its cooldown
--   only"), so the 5000-mana Blast line fails.
--   frostbolt -> arcane_blast (93.87, 132.37): central: at about 250 mana with two charges 0.4-0.9 s from fading, the
--   sim's `mana.time_to_N` reads 0 for N above its forecast's last slice (measured at 93.87: time_to_694, _818 and _819
--   all 0, time_to_500 8.5 s), so Arcane Blast at 818 reads castable; wowsims casts Frostbolt once its 260 is there.
-- Worked (P6, world and kit): Arcane Blast's cast and charges (ruling M9); Evocation's tick from wowsims's spirit regen
-- (29.13 a second; 15x, the regen pays the 16th); the worlds' character trainer-taught (no book ranks: wowsims casts
-- Frostbolt rank 10, Arcane Missiles rank 7); the world's pools and regen the logs' (6678; 29.13 a second, all of it
-- while casting under Arcane Meditation 3/3). Evocation is never clipped in this fight (mana never reaches 99% inside
-- the channel), so the belief keeping its aura after a clip does not show here.
-- autocastOtherCooldowns (rule 13, from the log's "Major cooldown used"): the Mind Quickening Gem (19339, `use_items`),
-- Presence of Mind, Arcane Power and the mana gem, off the GCD, at the top of the list.
-- Rule 12 drops Read Ley Line (1259705, a Skyborne racial; its buff 1270842): no Skyborne race pack (the Human the UI
-- defaults to never casts it). Innervate (29166, another player's) reads false (rule 4).
return {
    class = "MAGE",
    pack = "Arcane (wowsims.com)",
    spec = "arcane",
    name = "Arcane",
    talentTree = "mage",
    apl = "ui/specs/mage/dps/apls/arcane.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassMage",
        gear = "ui/specs/mage/dps/gear_sets/p1Arcane.gear.json",
        talentsString = "0552205003100311531-03-0515",
        specKey = "mage",
        options = { classOptions = { defaultMageArmor = "MageArmorMageArmor" } },
        profession1 = "Engineering",
        profession2 = "Tailoring",
        reactionTimeMs = 100,
        distanceFromTarget = 20,
    },
    map = { ["item:19339"] = "use_items" }, -- the Mind Quickening Gem (ItemSparse 19339: a trinket, InventoryType 12)
    -- Ruling M5: the kit's content picks (no retired list): Missiles on Missile Barrage, Evocation, Counterspell
    focus = { arcane_missiles = 1, evocation = 2, counterspell = 1 },
    leveling = {},
}
