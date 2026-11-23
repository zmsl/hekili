"""vendor.lock pins the two embedded libraries by name, folder and repository, each at a release tag (lib-repo-setup R4-6)."""

import json
import os
import unittest

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")


class VendorLock(unittest.TestCase):
    def test_entries(self):
        with open(os.path.join(ROOT, "vendor.lock"), encoding="utf-8") as f:
            libs = json.load(f)["libraries"]
        self.assertEqual(
            [(e["name"], e["path"], e["repository"]) for e in libs],
            [
                ("LibHiddenValues", "src/LibHiddenValues", "https://github.com/zmsl/LibHiddenValues"),
                ("LibTimeToDie", "src/LibTimeToDie", "https://github.com/zmsl/LibTimeToDie"),
            ],
        )
        for e in libs:
            self.assertRegex(e["tag"], r"\Av\d+\.\d+\.\d+\Z")
            self.assertRegex(e["sha"], r"\A[0-9a-f]{40}\Z")


if __name__ == "__main__":
    unittest.main()
