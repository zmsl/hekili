"""Offline tests for tools/changelog_release.py: no git repository state, no network."""

import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
import changelog_release as cr  # noqa: E402

AT_TAG = """# Hekili Forever changelog

## Unreleased

### New
- Hunter: Beast Mastery, Marksmanship and Survival default priorities. Sniper
  Shot first.

### Changed

### Fixed
- Rogue loads.

### Known issues

### Upgrade notes

## v0.1.0

First release.
"""

# forever at publish time: one line merged after the tag
NOW = AT_TAG.replace("- Rogue loads.\n", "- Rogue loads.\n- Paladin loads.\n")

BODY = "Hunters arrive.\n\n### Hunter\n- New priorities.\n"

FRESH = """## Unreleased

### New

### Changed

### Fixed
- Paladin loads.

### Known issues

### Upgrade notes

## v0.2.0

_Released 2026-10-19_

Hunters arrive.

### Hunter
- New priorities.

## v0.1.0
"""


class Rewrite(unittest.TestCase):
    def test_inserts_the_release_and_resets_unreleased(self):
        got = cr.rewrite(NOW, "v0.2.0", BODY, cr.unreleased(AT_TAG)[2], "2026-10-19")
        self.assertTrue(got.startswith("# Hekili Forever changelog\n\n"))
        self.assertIn(FRESH, got)
        self.assertTrue(got.endswith("## v0.1.0\n\nFirst release.\n"))

    def test_edited_wrapped_entry_stays_whole(self):
        now = NOW.replace("  Shot first.", "  Shot first (configurable).")
        got = cr.rewrite(now, "v0.2.0", BODY, cr.unreleased(AT_TAG)[2], "2026-10-19")
        self.assertIn("### New\n- Hunter: Beast Mastery, Marksmanship and Survival default priorities. Sniper\n"
                      "  Shot first (configurable).\n\n### Changed", got)

    def test_unchanged_wrapped_entry_ships(self):
        got = cr.rewrite(NOW, "v0.2.0", BODY, cr.unreleased(AT_TAG)[2], "2026-10-19")
        self.assertNotIn("Shot first", got)

    def test_new_entry_repeating_a_shipped_one_is_kept(self):
        now = NOW.replace("- Rogue loads.\n", "- Rogue loads.\n- Rogue loads.\n")
        got = cr.rewrite(now, "v0.2.0", BODY, cr.unreleased(AT_TAG)[2], "2026-10-19")
        self.assertIn("### Fixed\n- Rogue loads.\n- Paladin loads.\n\n### Known issues", got)

    def test_trailing_whitespace_body(self):
        got = cr.rewrite(NOW, "v0.2.0", BODY + "  \n\n\t\n", cr.unreleased(AT_TAG)[2], "2026-10-19")
        self.assertIn(FRESH, got)

    def test_no_unreleased_is_refused(self):
        with self.assertRaises(SystemExit) as cm:
            cr.rewrite("# c\n\n## v0.1.0\n\nx\n", "v0.2.0", BODY, "", "2026-10-19")
        self.assertEqual(cm.exception.code, 2)

    def test_released_already_matches_a_dated_heading_only(self):
        self.assertTrue(cr.released_already("## v0.2.0 (2026-10-19)\n", "v0.2.0"))
        self.assertFalse(cr.released_already("## v0.2.0-rc.1\n", "v0.2.0"))
        self.assertFalse(cr.released_already("## v0.2.0.1\n", "v0.2.0"))

    def test_crlf_body(self):
        got = cr.rewrite(NOW, "v0.2.0", BODY.replace("\n", "\r\n"), cr.unreleased(AT_TAG)[2], "2026-10-19")
        self.assertIn(FRESH, got)

    def test_heading_order(self):
        got = cr.rewrite(NOW, "v0.2.0", BODY, cr.unreleased(AT_TAG)[2], "2026-10-19")
        heads = [line for line in got.split("\n") if line.startswith("## ") or line.startswith("### ")][:7]
        self.assertEqual(heads, ["## Unreleased"] + ["### " + h for h in cr.HEADINGS] + ["## v0.2.0"])

    def test_idempotent(self):
        once = cr.rewrite(NOW, "v0.2.0", BODY, cr.unreleased(AT_TAG)[2], "2026-10-19")
        self.assertEqual(cr.rewrite(once, "v0.2.0", BODY, "", "2026-10-20"), once)

    def test_refusals(self):
        for tag, body in (("v0.2.0", " \n"), ("v0.2.0-rc.1", BODY), ("v0.2.0", "## Hunter\n- x\n")):
            with self.assertRaises(SystemExit) as cm:
                cr.rewrite(NOW, tag, body, "", "2026-10-19")
            self.assertEqual(cm.exception.code, 2)


class Main(unittest.TestCase):
    def files(self, changelog):
        d = tempfile.mkdtemp()
        body, path = os.path.join(d, "body.md"), os.path.join(d, "CHANGELOG.md")
        with open(body, "w") as f:
            f.write(BODY)
        with open(path, "w") as f:
            f.write(changelog)
        return body, path

    def test_reads_the_tags_changelog_and_writes_the_file(self):
        body, path = self.files(NOW)
        seen = []

        def run(args, **kw):
            seen.append(args)
            return subprocess.CompletedProcess(args, 0, AT_TAG, "")

        self.assertEqual(cr.main(["x", "v0.2.0", body, path], run), 0)
        self.assertEqual(seen, [["git", "show", "v0.2.0:CHANGELOG.md"]])
        with open(path) as f:
            got = f.read()
        self.assertIn("- Paladin loads.\n\n### Known issues", got)
        self.assertNotIn("Rogue loads", got)
        self.assertEqual(cr.main(["x", "v0.2.0", body, path], None), 0)  # second run: no git call, no change
        with open(path) as f:
            self.assertEqual(f.read(), got)

    def test_crlf_changelog(self):
        body, path = self.files(NOW.replace("\n", "\r\n"))
        run = lambda a, **kw: subprocess.CompletedProcess(a, 0, AT_TAG.replace("\n", "\r\n"), "")  # noqa: E731
        self.assertEqual(cr.main(["x", "v0.2.0", body, path], run), 0)
        with open(path) as f:
            self.assertIn(FRESH, f.read())

    def test_refuses_without_the_tag(self):
        body, path = self.files(NOW)
        with self.assertRaises(SystemExit) as cm:
            cr.main(["x", "v0.2.0", body, path], lambda a, **kw: subprocess.CompletedProcess(a, 128, "", "bad"))
        self.assertEqual(cm.exception.code, 2)
        with open(path) as f:
            self.assertEqual(f.read(), NOW)


if __name__ == "__main__":
    unittest.main()
