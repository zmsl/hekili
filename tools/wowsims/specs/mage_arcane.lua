-- tools/wowsims/specs/mage_arcane.lua (wowsims packs plan, Task 12): Arcane (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/mage/dps/presets.ts:15,19,31-35
-- (ArcaneAplPreset, ArcaneTalents, DefaultOptions), :37-41 (OtherDefaults), the gear p1Arcane.gear.json (the spec's
-- default, spec.ts:82) and ui/features/settings/model/apply_defaults.ts:68,97 (spec.ts names no race: the class's
-- first, Human, ui/sim/player/classes/capabilities_auto_gen.ts:65; the reaction time the UI defaults to, 100 ms) at
-- the pin.
-- Ruling M9 (Arcane Blast): the log casts it in 1.5 s unhasted (1.128 s under the Mind Quickening Gem, the old
-- gear's trinket) and each run of charges ends 15 s after its first (2.26 -> 17.26, 44.67 -> 59.67, 60.17 -> 75.17:
-- a later Blast adds a charge without refreshing it); the DB2 at 70338 says 2.5 s and 8 s, wowsims's data (build
-- 70450, hotfix 112887) 1.5 s and 15 s. The kit and the world take wowsims's (Mage.lua's header); the in-game cast
-- bar is the check. The log prices a charge as 181 x (1 + n) since hotfix 113554 (was 1 + 1.75 n), the kit's
-- spendBase floor(fraction x 1213) (363, 545, 727, 909).
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
-- Worked (P6, world and kit): Arcane Blast's cast and charges (ruling M9); Arcane Power's +30% on Arcane Wrath too
-- (the log's 513.5 = 395 x 1.3 at 0.00 and 9.64; replay unchanged at 0.780); Evocation's tick from wowsims's spirit regen
-- (29.13 a second; 15x, the regen pays the 16th); the worlds' character trainer-taught (no book ranks: wowsims casts
-- Frostbolt rank 10, Arcane Missiles rank 7); the world's pools and regen the logs' (6678; 29.13 a second, all of it
-- while casting under Arcane Meditation 3/3). Evocation is never clipped in this fight (mana never reaches 99% inside
-- the channel), so the belief keeping its aura after a clip does not show here.
-- autocastOtherCooldowns (rule 13, from the log's "Major cooldown used"): the trinket (`use_items`; 18820 since the
-- re-pin, was 19339), Presence of Mind, Arcane Power and the mana gem, off the GCD, at the top of the list.
-- Deviation (Evocation's clip): wowsims clips Evocation at >= 99% mana (its channelSpell interruptIf); the translator
-- drops channelSpell.interruptIf (tools/wowsims/apl.lua; a shared gap, reported), so the pack's line has no clip
-- condition; the world clips by wowsims's rule (mage_world.lua: any press while the belief channels it at 99%).
-- Read Ley Line (1259705) and its Energized (1270842) resolve to the High Order Skyborne race file; the Human the UI
-- defaults to never knows it. Innervate (29166, another player's) reads false (rule 4).
-- Re-pin e2842f0a78 (Task 10): the build's talents (presets.ts ArcaneTalents 050205223101311531-5500003-003, "Deep
-- Arcane" upstream; the pack name kept), the new list (pre-pull Read Ley Line and Arcane Wrath, Fire Blast, no
-- Frostbolt), the gear's trinket the Talisman of Ephemeral Power (18820). Omitted 1 -> 0 (the trinket, mapped).
-- Disagreements (P7; floor 0.96), decisions on-GCD 0.966 (58) top [arcane_wrath -> evocation 1; arcane_wrath ->
-- fire_blast 1]: both the mana gem's restore not believed (gaps.md CR): 34.50, lo 595 against the truth's
-- 836 (8.6% against 12.1%, the 10% Evocation line; the Mana Ruby's +1040 at 13.00); 133.00, the Citrine's +843 at
-- the instant (lo 93, truth 963). Worked (world): the kit list gains fire_blast (mage_world.lua).
-- Flicker (replay 0.67 -> 1.33/min): the belief's cooldown probe push (CD_PROBE, Families/Casts.lua) freezes a
-- cooldown's believed wait at 0.50 at its end, so the filler shows one poll (arcane_wrath 0.50, 0.50 -> arcane_blast
-- at 17.8 and 59.4; fire_blast -> arcane_blast at 142.4): central, gaps.md CQ, Task 10b (ruling R21). At the fix's
-- base (2007a9567) the replay's four flips were 121.0, 142.4 / 142.6 and 182.8, none of them Arcane Wrath's; the fix
-- leaves all four (142.4: Fire Blast's end 0.1 s past the GCD's, outside the fix's cover), 1.33/min, ceiling 1.4.
-- LIVE L10 4.8, L40 6.4, L60 10.0 s: the list has no cheap filler, so mana runs dry by about 90 s and it waits on Fire
-- Blast's 340 (Evocation on its cooldown counts usable); wowsims's own fight idles 96.40 -> 104.70 -> 114.40.
-- Leveling (ruling R22: L10/L40 keep the 6 s bar): L40's 6.4 s is 108.8-116.8, mana dry (60-230), Frostbolt
-- affordable and unlisted. The filler Frostbolt (the old list's, simc line `frostbolt,if=!talent.arcane_instability.
-- enabled`) is keyed to the talent, not the level: it shows whenever Arcane Instability is not taken, at 60 too (every
-- kit ability is known at 40 and at 60, so the guard is a talent's, as Retribution's); wowsims's build takes it.
-- Re-pin 4b0030a44b (0.7 lane mage): Read Ley Line's pre-pull time is now the hasted GCD (901c5b8cfd), translated by
-- the CN4 rule with the kit's unhasted GCD (the deviation line in the pack); Clearcasting is spent by Arcane Missiles
-- only when Missile Barrage is not up, and each landed missile rolls Arcane Concentration under a 1 s ICD (ef6fb99ee1;
-- the world, mage_world.lua; the kit's rule is the cost mod's `unless`, CN11).
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
        talentsString = "050205223101311531-5500003-003",
        specKey = "mage",
        options = { classOptions = { defaultMageArmor = "MageArmorMageArmor" } },
        profession1 = "Engineering",
        profession2 = "Tailoring",
        reactionTimeMs = 100,
        distanceFromTarget = 20,
    },
    -- the Talisman of Ephemeral Power (ItemSparse 18820: a trinket, InventoryType 12; the re-pin gear, was the Mind
    -- Quickening Gem 19339)
    map = { ["item:18820"] = "use_items" },
    focus = { arcane_missiles = 1 }, -- by role (docs/dev/wowsims-packs.md)
    leveling = { "frostbolt,if=!talent.arcane_instability.enabled" },
}
