-- tests/Forever/fixtures/dungeon_map_reads.lua (T1, plate count plan v2 §3 task 2): every client read the plate enemy
-- count (Engine/Sim/Targets.lua, token plates) makes on a nameplate token under the Map restriction, in a dungeon in
-- combat: "measured" plain (owner, n=1, 2026-11-05 FR-1 and the dungeon probe), "measured-lib" (probe G2, forced Map,
-- open world), or "assumed" (unmeasured: the count reads it through a secrecy guard, and map_restriction_spec's
-- pessimistic case answers it secret).
return {
    { read = 'UnitExists("nameplateN")', status = "measured" },
    { read = 'UnitCanAttack("player", "nameplateN")', status = "measured" },
    { read = 'UnitIsUnit("target", "nameplateN")', status = "measured" },
    { read = "NAME_PLATE_UNIT_ADDED / REMOVED token", status = "measured" },
    { read = 'LibRangeCheck GetRange("nameplateN")', status = "measured-lib" },
    { read = 'UnitIsFriend("player", "nameplateN")', status = "assumed" },
    { read = 'UnitIsDead("nameplateN")', status = "assumed" },
    { read = 'UnitIsPlayer("nameplateN")', status = "assumed" },
    { read = 'UnitInParty / UnitInRaid("nameplateN")', status = "assumed" },
    { read = 'UnitIsPVP("player")', status = "assumed" },
    { read = 'IsActionInRange(slot, "nameplateN") (pet-based detection)', status = "assumed" },
    { read = 'UnitGUID / UnitName("nameplateN")', status = "measured", note = "secret: the count never needs them" },
}
