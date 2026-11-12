"""tools/gen_shared_auras.py: rows and rendering from a stand-in names.json and spell lookup."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import gen_shared_auras as g  # noqa: E402

NAMES = {"shared": {"aura": {"b": {"spellId": 2}, "a": {"spellId": 1}, "a_dup": {"spellId": 1}, "c_3": {"spellId": 3}, "d": {"spellId": 4}}}}
SPELLS = {1: (15000, 1, False), 2: (0, 0, False), 3: (30500, 3, False), 4: (0, 1, True)}


class GenSharedAuras(unittest.TestCase):
    def test_rows(self):
        rs = g.rows(NAMES, lambda sid: SPELLS[sid])
        # sorted keys, one row per id (a_dup dropped), a castable spell (d) dropped, a key ends in its id, no duration is 3600, stacks at least 1
        self.assertEqual(rs, [("a_1", 1, 15, 1), ("b_2", 2, 3600, 1), ("c_3", 3, 30.5, 3)])

    def test_render(self):
        out = g.render([("a", 1, 15, 1), ("c", 3, 30.5, 3)])
        self.assertIn('    { "a", 1, 15, 1 },\n    { "c", 3, 30.5, 3 },\n}', out)


if __name__ == "__main__":
    unittest.main()
