-- tools/wowsims/specs/shaman_enhancement.lua (wowsims packs plan, Task 10): Enhancement (wowsims.com)'s
-- wowsims/forever request and translation.
-- Values from wowsims/forever (MIT) ui/specs/shaman/enhancement/presets.ts:14-23 (DefaultGear: the Testing build's
-- gear; StandardTalents 053503102-053030031005112251, the build's own talentsString) and builds/testing.build.json at
-- the pin; the rotation is apls/default.apl.json (the presets' default), which replaces the build's.
-- Disagreements worked (P7, decisions on-GCD 0.750 of 88; first clean run 0.557):
-- 1. "* -> flame_shock" (was 19 of 35): content gap, fixed in the kit. Call of Flame: wowsims spell data, absent from
--    DB2 (wowdb effects 16038 has none): +3 s a rank on Flame Shock (21 s at 3/3, the log's). IN-GAME CHECK: Flame
--    Shock duration with Call of Flame: 21 s?
-- 2. "fire_nova -> earth_shock" (8): replay limit. The replay's cast carries only the cast spell's own IDs and a
--    numeric cooldown, so the shocks' shared category (and a talent-shortened, function cooldown) never reaches the
--    client's cooldown answers: we offer Earth Shock just after a Flame Shock.
-- 3. "stormstrike -> earth_shock" (5) and "stormstrike -> lightning_bolt" (3): replay limit (wowsims casts Stormstrike
--    on the instant its 8 s ends; the decision sits a hair before it, our cooldown not yet over).
-- Kit fixes (P6): Reverberation (shocks 5 s), Improved Fire Nova (6 s), Shamanistic Focus (-45% on the shocks and
-- Lightning Shield), from wowdb; Call of Flame (+3 s a rank on Flame Shock) and Stormstrike's cost (8% of base mana,
-- 121 at 60; the DB2's 125), wowsims spell data absent from DB2 (in-game checks). Each matches the log.
-- Known deviations: Fire Nova costs the DB2's 520, not wowsims's 375 (its spell data; the log's 15 casts): at 375 the
-- secret-mana belief's lower bound stays under the cost while the truth is over it, and the solo loop gate falls to
-- 0.72 (a core gap, reported). Also: wowsims's autocastOtherCooldowns (Blood Fury, Rage of the Farseer 425336, the
-- trinket 249469) is omitted (central GAP 14), as is the Goblin Sapper Charge 10646; mana is secret in combat, so the
-- potion (mana.pct<80), Demonic Rune (<70) and the Fire Nova filler (>10) read the belief's low-biased estimate.
return {
    class = "SHAMAN",
    pack = "Enhancement (wowsims.com)",
    spec = "enhancement",
    name = "Enhancement",
    talentTree = "shaman",
    build = "ui/specs/shaman/enhancement/builds/testing.build.json",
    apl = "ui/specs/shaman/enhancement/apls/default.apl.json",
    map = { OtherActionResourcePotion = "major_mana_potion" }, -- the build's resourcePotId 13444, Major Mana Potion
    -- the retired Enhancement list's tiers (P9.3)
    focus = {
        grace_of_air_totem = 2,
        strength_of_earth_totem = 2,
        fire_nova = 1,
        lightning_shield = 2,
        searing_totem = 2,
        lightning_bolt = 1,
        flame_shock = 2,
    },
    -- below 60 (Improved Fire Nova, the build's last talent, comes at 59-60): Lightning Bolt fills while the shocks and
    -- Stormstrike wait; silent at 60, where wowsims casts it only at five Maelstrom Weapon stacks
    leveling = { "lightning_bolt,if=!action.stormstrike.known" },
}
