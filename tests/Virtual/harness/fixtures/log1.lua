-- tests/Virtual/harness/fixtures/log1.lua: log 1 of docs/research/2026-10-16-swing-outcome-pairing.md (2026-10-16),
-- every token row as /vslog recorded it (ms since the first event). Solo, level 22, dual wield (main 2.2 s, off 2.5 s),
-- one mob: two on-next-swing strike frames (4330, 6532), a DoT cast at 2844 (its tick, WOUND 13, at 5847), the
-- unexplained WOUND 30 + CRITICAL 90 frame at 2463, hits on us (player, then targettarget). `damage`: UnitDamage's min
-- and max per hand (the research doc).
-- Rows: { ms, "S", duration, swingType } PLAYER_SWING; { ms, "U", unit, action, flag, amount, school } UNIT_COMBAT;
-- { ms, "C", unit, spell } UNIT_SPELLCAST_SUCCEEDED (spell: "STRIKE" on-next-swing, "DOT", "OTHER", "SECRET").
-- stylua: ignore
return {
    damage = { 36, 50, 24, 32 },
    rows = {
        { 0, "C", "player", "OTHER" }, { 771, "S", 2.2, 0 }, { 1006, "C", "player", "OTHER" }, { 1008, "S", 2.5, 1 },
        { 1297, "U", "player", "PARRY", "", 0, 1 }, { 1297, "U", "targettarget", "PARRY", "", 0, 1 },
        { 1345, "C", "player", "OTHER" }, { 1345, "C", "targettarget", "OTHER" },
        { 1762, "U", "nameplate1", "WOUND", "", 49, 1 }, { 1762, "U", "target", "WOUND", "", 49, 1 },
        { 2110, "S", 2.2, 0 }, { 2111, "U", "nameplate1", "MISS", "", 0, 1 },
        { 2111, "U", "target", "MISS", "", 0, 1 }, { 2463, "U", "nameplate1", "WOUND", "", 30, 1 },
        { 2463, "U", "target", "WOUND", "", 30, 1 }, { 2463, "U", "nameplate1", "WOUND", "CRITICAL", 90, 1 },
        { 2463, "U", "target", "WOUND", "CRITICAL", 90, 1 }, { 2663, "U", "player", "WOUND", "", 12, 1 },
        { 2663, "U", "targettarget", "WOUND", "", 12, 1 }, { 2844, "C", "player", "DOT" },
        { 2844, "C", "targettarget", "DOT" }, { 3593, "S", 2.5, 1 }, { 3897, "U", "player", "WOUND", "", 13, 1 },
        { 3897, "U", "targettarget", "WOUND", "", 13, 1 }, { 4297, "U", "nameplate1", "WOUND", "", 29, 1 },
        { 4297, "U", "target", "WOUND", "", 29, 1 }, { 4328, "C", "player", "OTHER" },
        { 4329, "C", "targettarget", "OTHER" }, { 4330, "C", "player", "STRIKE" },
        { 4330, "C", "targettarget", "STRIKE" }, { 4330, "U", "nameplate1", "WOUND", "", 0, 1 },
        { 4330, "U", "target", "WOUND", "", 0, 1 }, { 4330, "S", 2.2, 0 },
        { 4331, "U", "nameplate1", "WOUND", "", 77, 1 }, { 4331, "U", "target", "WOUND", "", 77, 1 },
        { 5318, "U", "player", "WOUND", "", 13, 1 }, { 5318, "U", "targettarget", "WOUND", "", 13, 1 },
        { 5847, "U", "nameplate1", "WOUND", "", 13, 1 }, { 5847, "U", "target", "WOUND", "", 13, 1 },
        { 6015, "S", 2.5, 1 }, { 6531, "C", "player", "STRIKE" }, { 6532, "C", "targettarget", "STRIKE" },
        { 6532, "U", "nameplate1", "WOUND", "", 0, 1 }, { 6532, "U", "target", "WOUND", "", 0, 1 },
        { 6532, "S", 2.2, 0 }, { 6532, "U", "nameplate1", "WOUND", "", 84, 1 },
        { 6532, "U", "target", "WOUND", "", 84, 1 }, { 6619, "U", "player", "WOUND", "", 13, 1 },
        { 6619, "U", "targettarget", "WOUND", "", 13, 1 }, { 7017, "U", "nameplate1", "WOUND", "", 33, 1 },
        { 7017, "U", "target", "WOUND", "", 33, 1 }, { 8614, "S", 2.5, 1 },
        { 9305, "U", "target", "WOUND", "", 30, 1 }, { 9305, "U", "softinteract", "WOUND", "", 30, 1 },
    },
}
