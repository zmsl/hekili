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
-- ignored (rule 5), and no decision here turns on it. autocastOtherCooldowns (rule 13): the Mind Quickening Gem
-- (`use_items`) and the mana gem, off the GCD (this build has no Combustion).
-- Focus (M5): Pyroblast on Hot Streak and Fire Blast on the Fingers of Frost read tier 1, Scorch and Evocation tier 2.
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
        talentsString = "-2355000013011503-00550003310003002",
        specKey = "mage",
        options = { classOptions = { defaultMageArmor = "MageArmorMageArmor" } },
        profession1 = "Engineering",
        profession2 = "Tailoring",
        reactionTimeMs = 100,
        distanceFromTarget = 20,
    },
    map = { ["item:19339"] = "use_items" }, -- the Mind Quickening Gem (ItemSparse 19339: a trinket, InventoryType 12)
    focus = { pyroblast = 1, scorch = 2, evocation = 2, fire_blast = 1, counterspell = 1 },
    leveling = {},
}
