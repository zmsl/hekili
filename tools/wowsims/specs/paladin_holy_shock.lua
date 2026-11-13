-- tools/wowsims/specs/paladin_holy_shock.lua (new packs, owner-approved 2026-11-12): Holy Shock (wowsims.com)'s
-- wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) at the pin: builds/holy_shock.siml (its talents
-- 05025210221021--0523330110130033, 23 Holy / 28 Retribution, gear holy_shock.gear.siml, Engineering and
-- Blacksmithing) in paladin_retribution.lua's player shape (Human, 100 ms, 25 yd), the list
-- ui/specs/paladin/retribution/apls/holy_shock.apl.siml. Like its sibling it carries no consumables or raid buffs.
-- Spec binding: Retribution's second pack, picked by the talents (Paladin.lua's `holy_shock` selector: Retribution the
-- most points and Holy Shock taken), as wowsims's own Retribution page picks this list (spec.ts `holyShock`).
-- Disagreements (P7; floor 0.97), decisions on-GCD 0.977 (43 of 44) top [seal_of_righteousness -> consecration 1]:
--   2.0 (log): wowsims's move_to_melee sequence (its group 4, step 4) casts the seal on the way in; ours, with that
--   sequence omitted, follows the priority, Consecration first. A deviation (below).
-- Deviations: the item swaps (precombat itemSwap, the mcp_swap group: wowsims swaps a Manual Crowd Pummeler in) are
-- omitted, so the request's gear stays on; the move_to_melee sequence of a group reference and autocast (none in the
-- log) are omitted (the pack's 14 `# Omitted:` lines); wowsims casts and logs Holy Shock as rank 3's damage row 25902
-- (the DB2's 20930 is a dummy the server turns into 25902 or the heal 25903), so the map names 25902 and the replay
-- renames it to the kit's 20930 (wowsims_paladin_spec.lua's `alias`, tests/Game/harness/replay.lua).
-- Loops (20 fights, seeds 1-20 / 21-40 / 41-60; the harness's seeded regen phase, 2026-11-13): agreement .994 / .994 /
-- .999, flicker 0.06 / 0 / 0 (oracle 0 x3), heldReady 53 / 80 / 67 (first measurement: .998 / .999 / .997, 0 x3, 65 /
-- 70 / 94).
return {
    class = "PALADIN",
    pack = "Holy Shock (wowsims.com)",
    spec = "retribution",
    name = "Holy Shock",
    talentTree = "paladin",
    apl = "ui/specs/paladin/retribution/apls/holy_shock.apl.siml",
    player = {
        race = "RaceHuman",
        class = "ClassPaladin",
        gear = "ui/specs/paladin/retribution/gear_sets/holy_shock.gear.siml",
        talentsString = "05025210221021--0523330110130033",
        specKey = "retributionPaladin",
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) },
        profession1 = "Engineering",
        profession2 = "Blacksmithing",
        reactionTimeMs = 100,
        distanceFromTarget = 25,
    },
    -- 25902: Holy Shock rank 3's damage row (DB2: 20930 is a dummy the server turns into 25902 or the heal 25903), the
    -- ID wowsims casts and logs; the kit's holy_shock (its ranks 1311606, 20473, 20929, 20930)
    map = { [25902] = "holy_shock" },
    -- by role (docs/dev/wowsims-packs.md): Hammer of Wrath's execute window 1, the seal and Consecration kept up 2
    focus = { hammer_of_wrath = 1, seal_of_righteousness = 2, consecration = 2 },
}
