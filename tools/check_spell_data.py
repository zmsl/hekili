#!/usr/bin/env python3
"""The DB2 check of the packs' declared outcomes (unit-registry spec §5.5). Dev-only: `make spell-data-check`.

Reads tools/check_spell_data.lua's tab-separated lines on stdin (class, key, ids, velocity, school, tick_time,
startsCombat, expects) and $WOW_DB2 (default ~/.local/share/wow-db2/forever/current.sqlite). Fails when a declared
velocity differs from SpellMisc.Speed on any listed rank; when a declared school's name differs from SchoolMask's on
any listed rank (a mask with no single name: the pack leaves `school` nil); when an ability that starts combat has
Speed > 0 on its first rank and declares no velocity (a "ticks" or "none" ability's velocity is optional). A rank with no SpellMisc row is a note. A ticking aura's
tick_time that differs from a rank's periodic damage EffectAuraPeriod is a note (an aura may be rank-generic).
"""
import os
import sqlite3
import sys

SCHOOL = {"physical": 1, "holy": 2, "fire": 4, "nature": 8, "frost": 16, "shadow": 32, "arcane": 64}
NAME = {v: k for k, v in SCHOOL.items()}


def misc(db, sid):
    return db.execute("select Speed, SchoolMask from SpellMisc where SpellID = ?", (sid,)).fetchone()


def periodic(db, sid):
    r = db.execute("select EffectAuraPeriod from SpellEffect where SpellID = ? and EffectAura = 3", (sid,)).fetchone()
    return r[0] if r else 0


def check(rows, db):
    errors, notes = [], []
    for cls, key, ids, velocity, school, tick, starts, expects in rows:
        ranks = [int(i) for i in ids.split(",") if i]
        where = f"{cls} {key}"
        data = [(sid, misc(db, sid)) for sid in ranks]
        for sid, m in data:
            if not m:  # a finding to report, not a failure: DB2 gaps must not block `make check` later
                notes.append(f"{where}: rank {sid} has no SpellMisc row in this DB2 build")
        data = [(sid, m) for sid, m in data if m]
        if not data:
            continue
        for sid, (speed, mask) in data:
            if velocity and float(velocity) != speed:
                errors.append(f"{where}: velocity {velocity} but SpellMisc {sid} Speed {speed:g}")
            if school:
                name = NAME.get(mask)
                if name is None:
                    errors.append(f"{where}: SchoolMask {mask} of {sid} has no single name: leave school nil")
                elif name != school:
                    errors.append(f"{where}: school {school} but SpellMisc {sid} SchoolMask {mask} ({name})")
        first_speed = data[0][1][0]
        if starts == "1" and first_speed > 0 and not velocity and expects not in ("ticks", "none"):
            errors.append(f"{where}: Speed {first_speed:g} on {data[0][0]} but no velocity declared")
        if tick and tick != "fn":
            for sid, _ in data:
                p = periodic(db, sid)
                if p and float(tick) * 1000 != p:
                    notes.append(f"{where}: aura tick_time {tick} s but {sid} EffectAuraPeriod {p} ms")
    return errors, notes


def main():
    path = os.environ.get("WOW_DB2", os.path.expanduser("~/.local/share/wow-db2/forever/current.sqlite"))
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    rows = [line.rstrip("\n").split("\t") for line in sys.stdin if line.strip()]
    errors, notes = check(rows, db)
    for n in notes:
        print("note: " + n)
    for e in errors:
        print("FAIL: " + e)
    print(f"spell-data-check: {len(rows)} abilities, {len(errors)} failures, {len(notes)} notes")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
