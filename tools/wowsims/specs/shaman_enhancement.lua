-- tools/wowsims/specs/shaman_enhancement.lua (wowsims packs plan, Task 10): Enhancement (wowsims.com)'s
-- wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/shaman/enhancement/presets.ts:14-23 (DefaultGear: the Testing build's
-- gear; StandardTalents 053503102-053030031005112251, the build's own talentsString) and builds/testing.build.json at
-- the pin; the rotation is apls/default.apl.json (the presets' default), which replaces the build's.
-- Disagreements worked (P7, decisions on-GCD 0.807 of 88; first clean run 0.557):
-- 1. "* -> flame_shock" (was 19 of 35): content gap, fixed in the kit. Call of Flame: wowsims spell data, absent from
--    DB2 (wowdb effects 16038 has none): +3 s a rank on Flame Shock (21 s at 3/3, the log's). IN-GAME CHECK: Flame
--    Shock duration with Call of Flame: 21 s?
-- 2. "fire_nova -> earth_shock" (4; was 13): replay limit, fixed centrally (fix 9: the replay sends the shocks' shared
--    category and the talent-modified cooldowns, C.SHARED); 4 left. Core gap behind them too (GAP V): after a refill
--    it cannot see (here the potions and runes), the secret-mana belief pins at the dearest usable cost (lo = hi), so
--    from the first potion it sits about 2000 under the truth.
-- 3. "stormstrike -> earth_shock" (3) and "stormstrike -> lightning_bolt" (3): replay limit (wowsims casts on the
--    instant a cooldown ends; the decision sits a hair before it, our cooldown not yet over; mana is no factor).
-- Kit fixes (P6): Reverberation (shocks 5 s), Improved Fire Nova (6 s), Shamanistic Focus (-45% on the shocks and
-- Lightning Shield), from wowdb; Call of Flame (+3 s a rank on Flame Shock) and Stormstrike's cost (8% of base mana,
-- 121 at 60; the DB2's 125), wowsims spell data absent from DB2 (in-game checks). Each matches the log.
-- Known deviations: Fire Nova costs the DB2's 520, not wowsims's 375 (its spell data; the log's 15 casts): after a
-- refill it cannot see, the secret-mana belief pins at the dearest usable cost (lo = hi), and at 375 that pin (450)
-- sits under the Fire Nova filler's 10% (500 of the solo world's 5000 mana; 553 of the 5530 in wowsims's fight and
-- the replay), so the solo loop gate falls to 0.886 (GAP V, reported). Also: of
-- wowsims's autocast cooldowns (rule 13) Blood Fury and Rage of the Farseer 425336 (the kit's, by its ID) translate;
-- the trinket 249469, the Goblin Sapper Charge 10646 and the EZ-Thro Dark Bomb 260817 stay unmapped; mana is secret
-- in combat, so the potion (mana.pct<80), Demonic Rune (<70) and the Fire Nova filler (>10) read the belief's estimate.
return {
    class = "SHAMAN",
    pack = "Enhancement (wowsims.com)",
    spec = "enhancement",
    name = "Enhancement",
    talentTree = "shaman",
    build = "ui/specs/shaman/enhancement/builds/testing.build.json",
    apl = "ui/specs/shaman/enhancement/apls/default.apl.json",
    map = { OtherActionResourcePotion = "major_mana_potion" }, -- the build's resourcePotId 13444, Major Mana Potion
    focus = { -- by role (docs/dev/wowsims-packs.md); the totems none (the user, 2026-10-21)
        fire_nova = { 1, false }, -- on Clearcasting; the mana filler none
        lightning_shield = 2,
        lightning_bolt = 1,
        flame_shock = 2,
    },
    -- before Stormstrike (learned at 40): Lightning Bolt fills while the shocks wait; silent from 40, and so at 60,
    -- where wowsims casts it only at five Maelstrom Weapon stacks
    leveling = { "lightning_bolt,if=!action.stormstrike.known" },
}
