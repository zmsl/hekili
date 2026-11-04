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
-- Since central fix 22 (the replay's cast bars: limit 2. gone): 0.909 (n 55), top [wrath -> insect_swarm 3;
-- starfire -> insect_swarm 1; wrath -> starfire 1]; LIVE L10 0.0, L40 0.0, L60 0.0 s. Mana: wowsims dips to 133 at
-- 41 s (Innervate at 41.18 s) and sits at the floor from ~73 s; ours dips to 57 at 48.4 s and from ~83 s, casting
-- slower: our world's Starfire is 3.5 s against wowsims's 2.5 s (the kit's Eclipse charge, unmodelled: gaps.md BE).
-- Re-pin e2842f0a78 (Task 10): the build's talents (presets.ts StandardTalents 5232220115501351--5053: Genesis 5 -> 2,
-- Reflection 3/3), the APL's pre-pull Wrath, Innervate at `(fight_remains>380&mana<70%)|(mana<40%&fight_remains>30)`,
-- Starfire rank 6 (9876, in the kit's copy) and its Eclipse/executing guard. Omitted 2 -> 2 (the two trinkets).
-- Disagreements (P7; floor 0.86), decisions on-GCD 0.861 (79) top [starfire -> innervate 3; wrath -> innervate 3;
-- wrath -> insect_swarm 2]:
--   * -> innervate (log 10.45-22.59: 8 of the 11 misses, the top's 6 and 2 more; with them 76/79 = 0.962, over the
--     0.909 base, so the drop is this line's alone): API-forced, gap AN: fight_remains reads
--     3600, so the `fight_remains>380&mana.pct_lo<70` branch holds once mana dips under 70% (the truth from 11.82 s;
--     10.45 s at 67.9% truth after Starfire's cost, 2756 -> 2520 of 3709); wowsims casts it at 24.86 s on the 40% branch.
--   wrath -> insect_swarm (36.73, 52.73): Insect Swarm lasts 16 s in wowsims's log (21.09 -> 37.09, 38.23 -> 54.23;
--     the old log's too) against the kit's 14 s (the DB2's 12 s + Nature's Splendor's 2000 ms effect, mask 2097152 =
--     Insect Swarm's; wowsims's own spell data says the same, so its 16 s is a sim-side extension): our belief shows
--     the refresh 2 s early (already in the base's top, wrath -> insect_swarm 3). Kept on the DB2 until an in-game
--     check (owner).
--   Next (1): wrath -> starfire 55.73: the kit's Wrath grants Eclipse at its cast end; the 52.73 Wrath missed (no proc).
--   LIVE L10 0.2, L40 0.2, L60 0.2 s. The ready-time row (tests/Forever/helpers/wowsims.lua M.READY) 17 -> 22 real:
--   the new log's 79 decisions (42 Wraths, was 28 of 55), 17 of the 22 a Wrath at the mana floor (cost class).
-- Owner deviation R20a (2026-11-04): Innervate keeps only wowsims's low-mana branch, `condition = { innervate =
-- "mana.pct_lo<40&fight_remains>30" }` (apl.lua rule 7): the fight's length is unknown in game (gap AN), so "fight >
-- 380 s" can't be known, and the long-fight branch showed Innervate under 70% mana in every fight.
-- Disagreements (P7; floor 0.93), decisions on-GCD 0.937 (79) top [wrath -> insect_swarm 3; wrath -> starfire 2]
-- (the 8 Innervate misses gone; the rest were behind them):
--   wrath -> insect_swarm (19.59, 36.73, 52.73): Insect Swarm's 16 s (4.23 -> 20.23 in the log too), above.
--   wrath -> starfire (11.82, 55.73): wowsims's Wrath that missed (the 10.45 cast, Miss at 12.82; the 52.73 cast, Miss
--     at 55.23) grants no Eclipse; the kit grants it at every Wrath's cast end, so we show Starfire. The hit roll can't
--     be forecast: a replay limit.
--   LIVE L10 0.2, L40 0.2, L60 0.2 s; ready-time median 0.260 (22 real), the M.READY ceiling 0.71 -> 0.26.
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
        talentsString = "5232220115501351--5053",
        specKey = "balanceDruid",
        options = { classOptions = { innervateTarget = setmetatable({}, object) } },
        profession1 = "Enchanting",
        profession2 = "Tailoring",
        distanceFromTarget = 20,
    },
    executePhase = "execute_phase",
    map = {},
    focus = { moonfire = 2, insect_swarm = 2, starfire = 1 }, -- by role (docs/dev/wowsims-packs.md); Starfire on Eclipse 1
    -- wowsims's sim starts in Moonkin Form (its list never casts it): the form first, once known (a talent, 40)
    levelingFirst = { "moonkin_form,if=!buff.moonkin_form.up" },
    -- owner R20a: wowsims's low-mana branch only (the fight's length is unknown in game, gap AN)
    condition = { innervate = "mana.pct_lo<40&fight_remains>30" },
}
