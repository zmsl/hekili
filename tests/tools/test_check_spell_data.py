"""tools/check_spell_data.py against an in-memory DB2 subset (unit-registry spec §5.5)."""
import sqlite3
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import check_spell_data as csd  # noqa: E402


def db():
    c = sqlite3.connect(":memory:")
    c.executescript(
        """
        create table SpellMisc (SpellID int, Speed real, SchoolMask int, DurationIndex int);
        create table SpellDuration (ID int, Duration int);
        create table SpellEffect (SpellID int, EffectAura int, EffectAuraPeriod int);
        insert into SpellMisc values (10, 20, 8, 0), (11, 20, 8, 0), (20, 24, 20, 0), (30, 0, 64, 1), (31, 0, 64, 2);
        insert into SpellMisc values (40, 35, 1, 0), (12, 24, 8, 0);
        insert into SpellDuration values (1, 9000), (2, 12000);
        insert into SpellEffect values (30, 3, 3000), (31, 3, 3000);
        """
    )
    return c


def row(key, ids, velocity="", school="", tick="", starts="1", expects="travel"):
    return ["C", key, ",".join(map(str, ids)), velocity, school, tick, starts, expects]


class CheckTest(unittest.TestCase):
    def test_agreeing_declarations_pass(self):
        errors, notes = csd.check([row("bolt", [10, 11], "20", "nature")], db())
        self.assertEqual([], errors)

    def test_a_velocity_off_any_rank_fails(self):
        errors, _ = csd.check([row("bolt", [10, 12], "20", "nature")], db())
        self.assertEqual(1, len(errors))

    def test_a_school_name_off_the_mask_fails_and_a_two_school_mask_says_leave_it_nil(self):
        errors, _ = csd.check([row("bolt", [10], "20", "fire"), row("ffb", [20], "24", "frost")], db())
        self.assertEqual(2, len(errors))
        self.assertIn("leave school nil", errors[1])

    def test_a_projectile_that_starts_combat_must_declare_its_velocity(self):
        errors, _ = csd.check([row("shot", [40], expects="")], db())
        self.assertEqual(1, len(errors))

    def test_an_aura_tick_time_off_the_period_is_a_note_never_a_failure(self):
        errors, notes = csd.check([row("dot", [30, 31], "", "arcane", "3", expects="instant")], db())
        self.assertEqual(([], []), (errors, notes))
        errors, notes = csd.check([row("dot", [30, 31], "", "arcane", "2", expects="instant")], db())
        self.assertEqual(([], 2), (errors, len(notes)))
        errors, notes = csd.check([row("dot", [30, 31], "", "arcane", "fn", expects="instant")], db())
        self.assertEqual(([], []), (errors, notes))

    def test_a_rank_with_no_row_is_a_note_naming_it_and_the_rest_are_still_checked(self):
        errors, notes = csd.check([row("bolt", [10, 999], "20", "nature")], db())
        self.assertEqual([], errors)
        self.assertEqual(1, len(notes))
        self.assertIn("999", notes[0])
        errors, _ = csd.check([row("bolt", [999, 10], "24", "nature")], db())
        self.assertEqual(1, len(errors))


if __name__ == "__main__":
    unittest.main()
