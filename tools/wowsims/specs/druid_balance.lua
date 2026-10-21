-- tools/wowsims/specs/druid_balance.lua (wowsims packs plan, Task 7): Balance (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/druid/balance/presets.ts:15
-- (StandardTalents, "Moonkin"), :57-61 (DefaultOptions), :95-100 (OtherDefaults) at the pin.
-- Replay (P7, Task 7b): decisions on-GCD 0.564 (n 55). Worked:
-- - Content: mana declares the five-second rule (22 a second outside it, none inside: the log's regen lines; the kit's
--   and the loop world's), Moonglow's and Improved Wrath's costs (Wrath 45, the log's), Innervate 5% of base mana (62).
-- 1. wrath -> false 14 (80-177 s, the mana floor): wowsims casts Wrath once regen reaches its 45; our belief
--    regenerates (22 a second outside the rule), but the simulation's forecast reads GetManaRegen's casting rate (the
--    mp5 part, 0) for every in-combat moment (Engine/Sim/State.lua `regen`: active_regen in combat), so no Wrath is
--    ever affordable and no icon shows. Shared gap R (not worked around): with the forecast reading the not-casting
--    rate outside the rule (a scratch edit), 0.818.
-- 2. wrath -> insect_swarm 4, 3. starfire -> moonfire 2: a DoT refresh decided a fraction of a second before the debuff
--    ends (Insect Swarm's 16 s, Moonfire's 15 s, the log's): wowsims casts the filler and refreshes after, our first
--    icon is the refresh (the replay's casts land at their completion: no cast bars; replay limit).
-- Since central fixes 12-15 (gap R closed): 0.855 (n 55), top [wrath -> insect_swarm 4; starfire -> moonfire 2;
-- starfire -> insect_swarm 1], all the DoT-refresh replay limit (2. above); LIVE L10 1.6, L40 1.4, L60 1.4 s (8.6 at
-- 60 before gap R's fix).
local object = { __jsontype = "object" } -- dkjson: an empty table as {} (UnitReference.create(), the default unit)
return {
    class = "DRUID",
    pack = "Balance (wowsims.com)",
    spec = "balance",
    name = "Balance",
    talentTree = "druid",
    apl = "ui/specs/druid/balance/apls/default.apl.json",
    player = {
        race = "RaceNightElf",
        class = "ClassDruid",
        gear = "ui/specs/druid/balance/gear_sets/prebis.gear.json",
        talentsString = "5532220115501351--505",
        specKey = "balanceDruid",
        options = { classOptions = { innervateTarget = setmetatable({}, object) } },
        profession1 = "Enchanting",
        profession2 = "Tailoring",
        distanceFromTarget = 20,
    },
    executePhase = "execute_phase",
    map = {},
    focus = { moonfire = 2, insect_swarm = 2, starfire = 1 }, -- the retired Balance list's tiers (P9.3)
    -- wowsims's sim starts in Moonkin Form (its list never casts it): the form first, once known (a talent, 40)
    levelingFirst = { "moonkin_form,if=!buff.moonkin_form.up" },
}
