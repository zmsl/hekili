-- tests/Game/harness/fixtures/capture_ticks.lua: the druid DoT capture of 2026-10-22 (echoes trimmed): an arcane
-- instant with 3 s ticks (DOTI), a recast resetting the schedule, a kill by the direct hit (no death events recorded).
-- stylua: ignore
return {
    damage = { 0, 0, 0, 0 },
    rows = {
        { 0, "T", "Creature-0-4621-1-7-2955-C057713E6D" },
        { 1998, "SC", "SENT", "player", "Cast-3-4621-1-7-8921-F3CA1C696F", "DOTI", "Plainstrider" },
        { 1998, "SC", "SUCCEEDED", "player", "Cast-3-4621-1-7-8921-F3CA1C696F", "DOTI", false, false },
        { 2000, "B", "nameplate1", "Creature-0-4621-1-7-2955-C057713E6D" },
        { 2000, "U", "nameplate1", "WOUND", "", 9, 64 }, { 2000, "U", "target", "WOUND", "", 9, 64 },
        { 2000, "B", "softenemy", "Creature-0-4621-1-7-2955-C057713E6D" },
        { 2000, "U", "softenemy", "WOUND", "", 9, 64 }, { 2002, "E", "PLAYER_REGEN_DISABLED" },
        { 5036, "U", "target", "WOUND", "", 4, 64 }, { 8020, "U", "target", "WOUND", "", 4, 64 },
        { 11070, "U", "target", "WOUND", "", 4, 64 },
        { 11787, "SC", "SENT", "player", "Cast-3-4621-1-7-8921-E814422B83", "DOTI", "Plainstrider" },
        { 11788, "SC", "SUCCEEDED", "player", "Cast-3-4621-1-7-8921-E814422B83", "DOTI", false, false },
        { 11788, "U", "target", "WOUND", "", 8, 64 }, { 12209, "U", "player", "WOUND", "", 2, 1 },
        { 14309, "U", "player", "WOUND", "", 1, 1 }, { 14755, "U", "target", "WOUND", "", 4, 64 },
        { 17722, "U", "target", "WOUND", "", 4, 64 }, { 20755, "U", "target", "WOUND", "", 4, 64 },
        { 21922, "SC", "SENT", "player", "Cast-3-4621-1-7-8921-0E324C44C9", "DOTI", "Plainstrider" },
        { 21923, "SC", "SUCCEEDED", "player", "Cast-3-4621-1-7-8921-0E324C44C9", "DOTI", false, false },
        { 21924, "U", "target", "WOUND", "", 8, 64 }, { 21926, "T", "" },
        { 22194, "P-", "nameplate1", "Creature-0-4621-1-7-2955-C057713E6D" }, { 22527, "E", "PLAYER_REGEN_ENABLED" },
    },
}
