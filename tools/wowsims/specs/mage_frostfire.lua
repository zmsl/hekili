-- tools/wowsims/specs/mage_frostfire.lua (wowsims packs, Task FFB): Frostfire (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/mage/dps/presets.ts:16,20,31-35
-- (FFBAplPreset, FFBTalents, DefaultOptions), :37-41 (OtherDefaults), :84-89 (FFBBuild: the gear p1Arcane.gear.json)
-- and ui/features/settings/model/apply_defaults.ts:68,97 (no race: the class's first, Human; 100 ms reaction time) at
-- the pin.
-- Spec binding: the FFB talents are 29 Fire points to 22 Frost (0 Arcane), and our active spec is the tree with the
-- most points, so the pack is Fire's second; Fire's default stays "Fire (wowsims.com)" (wowsims's own default build,
-- spec.ts:91,102, is Arcane's and names none for Fire). Frost stays unsupported.
-- Disagreements (P7; floor 0.89), decisions on-GCD 0.891 (55) top [frostfire_bolt -> evocation 2; fire_blast ->
-- evocation 1; frostfire_bolt -> scorch 1] (log times):
--   scorch / fire_blast / pyroblast / frostfire_bolt -> evocation (34.31-41.31: 5 of 6): API-forced and a shared gap:
--   the belief's mana is about 1220 under the truth and reads Evocation's 10%: the Mana Ruby's +1056 at 9.76 is not
--   believed (mage_arcane.lua's shared gap) and Master of Elements' refunds of crits are unseen (mana is secret in
--   combat).
--   frostfire_bolt -> scorch (87.81): the cost edge: the truth 315 against Frostfire Bolt's 314.5, the belief 2 under
--   it (est 313), so Frostfire Bolt reads short and Scorch (150) goes first.
-- Worked (P6, kit and world): Frostfire Bolt's 2.5 s (Improved Fireball's mask reaches it) and 314.5 (Frost
-- Channeling's -15%); Fingers of Frost's charges (the kit's handlers spend one a damage cast; the world grants on a
-- Chill's landed hit at 15% and spends as wowsims does); the replay's procs (Frostfire Bolt's and Pyroblast's DoT parts
-- {1237313 / 18809, Tag: 1}). The log's pool and regen are the Fire build's (6168; 29.13 a second, half while casting).
-- Deviations: Evocation's clip (the translator drops channelSpell.interruptIf; mage_fire.lua); rule 12 drops Read Ley
-- Line (mage_arcane.lua); Ignite (412538) is a proc no key maps; includeReactionTime on the Fingers of Frost read is
-- ignored (rule 5), and no decision here turns on it. autocastOtherCooldowns (rule 13): the trinket
-- (`use_items`; 18820 since the re-pin, was 19339) and the mana gem, off the GCD (this build has no Combustion).
-- Focus (M5): Pyroblast on Hot Streak and Fire Blast (unless two Fingers of Frost charges are up) tier 1, Scorch and
-- Evocation tier 2.
-- Loops (20 fights, 0.958; frostfire_bolt -> scorch 680): measured (Task FFB fix round 1) as the believed mana a few
-- points under the truth while pooling for Frostfire Bolt (Master of Elements' refunds unseen, mana secret:
-- API-forced), which puts its ready time past the Scorch line's Fire Vulnerability `remains<5` edge; the modelled Fire
-- Vulnerability matched the world's to the tick (no early end). The uptime 0.96 (ours driving) against 0.99 (the
-- oracle) is Evocation at a carried fight's start: the believed lower bound reads mana.pct<=10 where the truth is
-- 16-19% (shared gap).
-- Re-pin e2842f0a78 (Task 10): the build's talents (presets.ts FFBTalents -5550000123011303-2035010311013002), the
-- new list's pre-pull Pyroblast, the gear's trinket the Talisman of Ephemeral Power (18820). Omitted 1 -> 0 (the
-- trinket, mapped).
-- Disagreements (P7; floor 0.96), decisions on-GCD 0.965 (57) top [fire_blast -> frostfire_bolt 1; fire_blast ->
-- scorch 1]: 148.90, the Citrine's +791 at the instant not believed (lo 54, truth 845: gaps.md CR);
-- 88.50, a replay limit (line position, as mage_fire.lua's 70.50): the Scorch line's
-- `debuff.fire_vulnerability.remains<5` with the debuff refreshed at 63.50 + 30, exactly 5.0 left at the log's
-- instant, read a hair under 5 at the decision's line offset (not gap BS).
-- LIVE L10 6.6, L40 0.2, L60 11.8 s (was 10.8): mana dry from about 87 s, waiting on Frostfire Bolt's 314.5 and
-- Scorch's 150 (Evocation on its cooldown counts usable); wowsims's own fight idles about 10 s at 91.6 -> 102.4.
-- Leveling (ruling R22: L10/L40 keep the 6 s bar): L10's 6.6 s is full mana with Fire Blast the only listed
-- castable line (Frostfire Bolt unlearned until L40), Fireball affordable and unlisted: the filler Fireball until
-- Frostfire Bolt.
return {
    class = "MAGE",
    pack = "Frostfire (wowsims.com)",
    spec = "fire",
    name = "Frostfire",
    talentTree = "mage",
    apl = "ui/specs/mage/dps/apls/ffb.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassMage",
        gear = "ui/specs/mage/dps/gear_sets/p1Arcane.gear.json",
        talentsString = "-5550000123011303-2035010311013002",
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
    focus = { pyroblast = 1, scorch = 2, evocation = 2, fire_blast = 1, counterspell = 1 },
    leveling = { "fireball,if=!action.frostfire_bolt.known" },
}
