-- tools/wowsims/specs/mage_fire.lua (wowsims packs plan, Task 12): Fire (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/mage/dps/presets.ts:17,21,31-35
-- (FireAplPreset, FireTalents, DefaultOptions), :37-41 (OtherDefaults), the gear p1Arcane.gear.json (the spec's
-- default, spec.ts:82) and ui/features/settings/model/apply_defaults.ts:68,97 (spec.ts names no race: the class's
-- first, Human, ui/sim/player/classes/capabilities_auto_gen.ts:65; the reaction time the UI defaults to, 100 ms) at
-- the pin.
-- Disagreements (P7; floor 0.84), decisions on-GCD 0.841 (63) top [fire_blast -> evocation 2; fireball ->
-- arcane_missiles 2; fireball -> evocation 2] (since 0ce5d1a4; first measured 0.794, floor 0.79):
--   Was first (log 13.50, 70.41, 76.41), fire_blast -> fireball: the decision falls the instant Fire Blast's 6 s
--   cooldown ends; the standing not-ready flag pushes the ready time to now + CD_PROBE (0.5 s; Families/Casts.lua
--   OnSettle). Since 0ce5d1a4 the replay's cooldown end is the log's timestamp and these three agree; the loops still
--   show the push (central).
--   fire_blast -> evocation (44.41, 53.41; with fireball / pyroblast / arcane_missiles -> evocation at 38.91-51.91: 6
--   of 12): API-forced and a shared gap: the belief holds its lower bound (est = lo) about 1200-1800 under the truth and
--   reads Evocation's 10%: Master of Elements refunds 30% of a crit's cost (25 refunds of 45-118 in the log; crits are
--   unseen and mana is secret in combat), and the mana gem's restore is not believed (mage_arcane.lua's shared gap).
--   fireball -> evocation (45.91, 48.91): the same lower-bound belief as fire_blast -> evocation.
--   fireball -> arcane_missiles (18.01, 80.91): translation (rule 5 ignores includeReactionTime): Missile Barrage
--   procs at the Fireball's completion, read by wowsims 100 ms later (mage_arcane.lua).
-- Checked (Task 14 review): Heating Up's rule is wowsims's (talents_fire.go:184-232: a stack on a crit of Fireball,
-- Frostfire Bolt, Fire Blast or Scorch; Fire Blast one more on any hit; Pyroblast spends every stack unless Presence of
-- Mind made it instant), as the world's.
-- Worked (P6, world and kit): the replay's procs (Fireball's and Pyroblast's DoT parts are GCD-0 Casting lines {10151 /
-- 18809, Tag: 1}: the belief priced each as another cast); the worlds' character trainer-taught (wowsims casts Fireball
-- rank 11, 395 mana); the world's pools and regen the log's (6168; 29.13 a second, half of it while casting); Evocation's
-- tick (mage_arcane.lua). Evocation is never clipped in this fight.
-- Deviation (Evocation's clip): wowsims clips Evocation at >= 99% mana (its channelSpell interruptIf); the translator
-- drops channelSpell.interruptIf (tools/wowsims/apl.lua; a shared gap, reported), so the pack's line has no clip
-- condition; the world clips by wowsims's rule (mage_world.lua: any press while the belief channels it at 99%).
-- autocastOtherCooldowns (rule 13): the Mind Quickening Gem (19339, `use_items`), Combustion and the mana gem, off the
-- GCD. Rule 12 drops Read Ley Line (mage_arcane.lua); Ignite (412538) and the missiles' 10274 are procs no key maps.
return {
    class = "MAGE",
    pack = "Fire (wowsims.com)",
    spec = "fire",
    name = "Fire",
    talentTree = "mage",
    apl = "ui/specs/mage/dps/apls/deepFire.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassMage",
        gear = "ui/specs/mage/dps/gear_sets/p1Arcane.gear.json",
        talentsString = "0502205-23550000130135031-005",
        specKey = "mage",
        options = { classOptions = { defaultMageArmor = "MageArmorMageArmor" } },
        profession1 = "Engineering",
        profession2 = "Tailoring",
        reactionTimeMs = 100,
        distanceFromTarget = 20,
    },
    map = { ["item:19339"] = "use_items" }, -- the Mind Quickening Gem (ItemSparse 19339: a trinket, InventoryType 12)
    -- Ruling M5: the kit's content picks (no retired list): Pyroblast on Hot Streak, Scorch for Fire Vulnerability,
    -- Missiles on Missile Barrage, Evocation, Counterspell
    focus = { pyroblast = 1, scorch = 2, arcane_missiles = 1, evocation = 2, counterspell = 1 },
    leveling = {},
}
