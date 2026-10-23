-- tests/Game/harness/fixtures/capture_kill.lua: the Rogue kill-events capture of 2026-10-22: PARTY_KILL, UNIT_DIED,
-- PLAYER_TARGET_DIED, the clear, a new target, the killing WOUND on softinteract 456 ms after its swing.
-- stylua: ignore
return {
    damage = { 0, 0, 0, 0 },
    rows = {
        { 0, "T", "Creature-0-6782-0-9-1508-AE12DF4C33" }, { 1179, "S", 1.6, 0 },
        { 1180, "SC", "SUCCEEDED", "player", "Cast-3-6782-0-9-1752-6C21346FB2", "HIT", false, false },
        { 1181, "B", "nameplate2", "Creature-0-6782-0-9-1508-AE12DF4C33" },
        { 1181, "U", "nameplate2", "WOUND", "", 8, 1 }, { 1181, "U", "target", "WOUND", "", 8, 1 },
        { 1568, "U", "player", "WOUND", "", 1, 1 }, { 1568, "U", "targettarget", "WOUND", "", 1, 1 },
        { 2167, "U", "nameplate2", "WOUND", "", 5, 1 }, { 2167, "U", "target", "WOUND", "", 5, 1 },
        { 2764, "S", 1.6, 0 }, { 2765, "U", "nameplate2", "WOUND", "", 5, 32 },
        { 2765, "U", "target", "WOUND", "", 5, 32 }, { 2765, "U", "player", "HEAL", "", 5, 1 },
        { 2765, "U", "targettarget", "HEAL", "", 5, 1 },
        { 2865, "SC", "SUCCEEDED", "player", "Cast-3-6782-0-9-1752-E68F88E748", "HIT", false, false },
        { 2865, "SC", "SUCCEEDED", "targettarget", "Cast-3-6782-0-9-1752-E68F88E748", "HIT", false, false },
        { 2866, "U", "nameplate2", "WOUND", "CRITICAL", 16, 1 }, { 2866, "U", "target", "WOUND", "CRITICAL", 16, 1 },
        { 3418, "U", "player", "DODGE", "", 0, 1 }, { 3418, "U", "targettarget", "DODGE", "", 0, 1 },
        { 3601, "U", "nameplate2", "WOUND", "", 4, 1 }, { 3601, "U", "target", "WOUND", "", 4, 1 },
        { 4364, "S", 1.6, 0 }, { 4364, "K", "ME", "Creature-0-6782-0-9-1508-AE12DF4C33" },
        { 4366, "D", "Creature-0-6782-0-9-1508-AE12DF4C33" }, { 4366, "TD" }, { 4368, "T", "" },
        { 4388, "T", "Creature-0-6782-0-9-1512-92D7148B28" },
        { 4820, "B", "softinteract", "Creature-0-6782-0-9-1508-AE12DF4C33" },
        { 4820, "U", "softinteract", "WOUND", "", 5, 1 }, { 5852, "T", "Creature-0-6782-0-9-1508-AE12DF4C33" },
        { 6085, "T", "" }, { 9433, "D", "Creature-0-6782-0-9-1501-2DA4917541" },
        { 11352, "D", "Creature-0-6782-0-9-1502-A7DFF4F0DF" },
    },
}
