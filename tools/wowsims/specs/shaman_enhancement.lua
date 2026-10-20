-- tools/wowsims/specs/shaman_enhancement.lua (wowsims packs plan, Task 10): Enhancement (wowsims.com)'s
-- wowsims/forever request and translation.
-- Values from wowsims/forever (MIT) ui/specs/shaman/enhancement/presets.ts:14-23 (DefaultGear: the Testing build's
-- gear; StandardTalents 053503102-053030031005112251, the build's own talentsString) and builds/testing.build.json at
-- the pin; the rotation is apls/default.apl.json (the presets' default), which replaces the build's.
-- Disagreements worked (P7, decisions on-GCD 0.602 of 88; was 0.557 before the kit fixes):
-- 1. "* -> flame_shock" (19 of 35): content gap, API-forced deviation. wowsims's Flame Shock lasts 21 s with Call of
--    Flame 3/3 (its spell data: 16038 effect 2, +9000 ms); the Forever DB2 at 1.60.1.70338 has no such effect, and the
--    target's auras are unreadable in combat, so the belief keeps the DB2's 12 s and asks for Flame Shock 9 s early.
--    Not modelled (values only from wowdb): an in-game checkpoint. Modelling it measured 0.76.
-- 2. "fire_nova -> earth_shock" (5): replay limit. The replay's cast carries only the cast spell's own IDs and a
--    numeric cooldown, so the shocks' shared category (and a talent-shortened, function cooldown) never reaches the
--    client's cooldown answers: we offer Earth Shock just after a Flame Shock.
-- 3. "stormstrike -> lightning_bolt" (3) and other Stormstrike boundaries: replay limit (wowsims casts Stormstrike on
--    the instant its 8 s ends; the decision sits a hair before it, our cooldown not yet over).
-- Kit fixes (P6, values from wowdb): Reverberation (shocks 5 s), Improved Fire Nova (6 s), Shamanistic Focus (-45% on
-- the shocks and Lightning Shield), each matching the log's intervals and costs.
-- Known deviations: wowsims's autocastOtherCooldowns (Blood Fury, Rage of the Farseer 425336, the trinket 249469) is
-- omitted (central GAP 14), as is the Goblin Sapper Charge 10646; mana is secret in combat, so the potion
-- (mana.pct<80), Demonic Rune (<70) and the Fire Nova filler (>10) read the belief's low-biased estimate.
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
