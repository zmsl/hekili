-- tools/wowsims/specs/shaman_enhancement.lua (wowsims packs plan, Task 10): Enhancement (wowsims.com)'s
-- wowsims/forever request and translation.
-- Values from wowsims/forever (MIT) ui/specs/shaman/enhancement/presets.ts:14-23 (DefaultGear: the Testing build's
-- gear; StandardTalents 053503102-053030031005112251, the build's own talentsString) and builds/testing.build.json at
-- the pin; the rotation is apls/default.apl.json (the presets' default), which replaces the build's.
-- Disagreements worked (P7, decisions on-GCD 0.761 of 88; first clean run 0.557):
-- 1. "* -> flame_shock" (was 19 of 35): content gap, fixed in the kit. Call of Flame: wowsims spell data, absent from
--    DB2 (wowdb effects 16038 has none): +3 s a rank on Flame Shock (21 s at 3/3, the log's). IN-GAME CHECK: Flame
--    Shock duration with Call of Flame: 21 s?
-- 2. "fire_nova -> earth_shock" (8; was 13, then 4 after fix 9 sent the shocks' shared and talent cooldowns):
--    shared gap (secret-mana belief). The belief credits no restore from a heard Major Mana Potion (17531, DB2 1800)
--    or Demonic Rune (16666, 1200), so from the first potion it sits about 2000 under the truth; above the costliest
--    usable rung (now Fire Nova's 375, was 520) it learns nothing more, so the filler's mana.pct>10 (553) reads false
--    where wowsims (truth 800-2700) casts it.
-- 3. "stormstrike -> earth_shock" (3) and "stormstrike -> lightning_bolt" (3): replay limit (wowsims casts on the
--    instant a cooldown ends; the decision sits a hair before it, our cooldown not yet over; mana is no factor).
-- Kit fixes (P6): Reverberation (shocks 5 s), Improved Fire Nova (6 s), Shamanistic Focus (-45% on the shocks and
-- Lightning Shield), from wowdb; Call of Flame (+3 s a rank on Flame Shock) and Stormstrike's cost (8% of base mana,
-- 121 at 60; the DB2's 125), wowsims spell data absent from DB2 (in-game checks). Each matches the log.
-- Fire Nova costs wowsims's 375 (its spell data; the log's 15 casts; the DB2's 520), priced in the belief since fix 6.
-- Known deviations: of wowsims's autocast cooldowns (rule 13) only Blood Fury translates; the trinket
-- 249469, Rage of the Farseer 425336 (not in the kit), the Goblin Sapper Charge 10646 and the EZ-Thro Dark Bomb 260817
-- stay unmapped; mana is secret in combat, so the potion (mana.pct<80), Demonic Rune (<70) and the Fire Nova filler
-- (>10) read the belief's estimate.
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
    -- before Stormstrike (learned at 40): Lightning Bolt fills while the shocks wait; silent from 40, and so at 60,
    -- where wowsims casts it only at five Maelstrom Weapon stacks
    leveling = { "lightning_bolt,if=!action.stormstrike.known" },
}
