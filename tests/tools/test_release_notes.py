"""Offline tests for tools/release_notes.py (approved-release plan): no git repository state, no network."""

import io
import json
import os
import subprocess
import sys
import unittest
import urllib.error

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
import release_notes as rn  # noqa: E402

CHANGELOG = """# Hekili Forever changelog

## Unreleased

### New
- Hunter: Beast Mastery, Marksmanship, Survival.

### Known issues

## v0.2.0

### Fixed
- Rogue loads.

## v0.1.0

First release.
"""

PLAN = """# Some plan

## Global Constraints
- x

## Open after Day 1 (2026-10-18)
- **Hunter, in game:** Auto Shot timing unverified.

### Task 3: not open
## Open after Day 2
- Mana floor off by default.
"""


def fake_git(answers):
    """A git stand-in: answers[(args...)] is the stdout; a missing key raises like a failing git."""

    def run(*args):
        if args not in answers:
            raise subprocess.CalledProcessError(128, ["git", *args])
        return answers[args]

    return run


def repo(ref="v0.3.0", prev="v0.2.0", log="--- feat(hunter): pack\nbody line\nCo-Authored-By: X <x@y>\n"):
    describe = ("describe", "--tags", "--abbrev=0", "--match", "v[0-9]*", "--exclude", "*-*", ref + "^")
    answers = {
        ("log", "--no-merges", "--format=--- %s%n%b", prev + ".." + ref if prev else ref, "--", "src"): log,
        ("show", ref + ":CHANGELOG.md"): CHANGELOG,
        ("show", ref + ":docs/superpowers/plans/p.md"): PLAN,
    }
    if prev:
        answers[describe] = prev + "\n"
        answers[("diff", "--name-only", "--diff-filter=AM", prev, ref, "--", rn.PLANS)] = "docs/superpowers/plans/p.md\n"
    return fake_git(answers)


class Section(unittest.TestCase):
    def test_reads_a_named_section_up_to_the_next(self):
        self.assertEqual(rn.section(CHANGELOG, "v0.2.0"), "### Fixed\n- Rogue loads.")
        self.assertTrue(rn.section(CHANGELOG, "Unreleased").startswith("### New\n- Hunter"))
        self.assertEqual(rn.section(CHANGELOG, "v9.9.9"), "")

    def test_does_not_match_a_heading_prefix(self):
        self.assertEqual(rn.section("## v0.1.0-rc.1\nx\n", "v0.1.0"), "")

    def test_open_after_takes_every_open_section_and_stops_at_the_next_h2(self):
        got = rn.open_after(PLAN)
        self.assertIn("## Open after Day 1 (2026-10-18)\n- **Hunter, in game:** Auto Shot", got)
        self.assertIn("## Open after Day 2\n- Mana floor", got)
        self.assertIn("### Task 3: not open", got)  # an h3 does not end the section
        self.assertNotIn("Global Constraints", got)


class Gather(unittest.TestCase):
    def test_spans_previous_tag_to_ref_and_drops_trailers(self):
        m = rn.gather("v0.3.0", repo())
        self.assertEqual(m["previous"], "v0.2.0")
        self.assertEqual(m["commits"], "--- feat(hunter): pack\nbody line")
        self.assertTrue(m["changelog"].startswith("### New"))  # no ## v0.3.0 yet: Unreleased
        self.assertIn("Auto Shot timing", m["known"])

    def test_prefers_the_tags_own_section(self):
        m = rn.gather("v0.2.0", repo(ref="v0.2.0", prev="v0.1.0"))
        self.assertEqual(m["changelog"], "### Fixed\n- Rogue loads.")

    def test_no_previous_tag_takes_all_history_and_no_plans(self):
        m = rn.gather("v0.3.0", repo(prev=None))
        self.assertIsNone(m["previous"])
        self.assertEqual(m["known"], "")


class Request(unittest.TestCase):
    def test_request_shape(self):
        req = rn.build_request(rn.gather("v0.3.0", repo()))
        self.assertEqual(req["model"], "claude-opus-5-5")
        self.assertEqual(req["system"], rn.SYSTEM)
        self.assertNotIn("thinking", req)  # Opus 5.5: adaptive by default; disabling is a 400
        self.assertNotIn("fallbacks", req)  # plain Messages API (controller ruling)
        user = req["messages"][0]["content"]
        self.assertIn("Release v0.3.0 (previous release: v0.2.0).", user)
        self.assertIn("<changelog>\n### New", user)
        self.assertIn("<commits>\n--- feat(hunter): pack", user)
        self.assertIn("<open_issues>\n## Open after Day 1", user)

    def test_house_style_is_in_the_system_prompt(self):
        for want in ("under 60 lines", "### Known issues", "### Upgrade notes", "### Core and display", "Never"):
            self.assertIn(want, rn.SYSTEM)

    def test_nothing_to_release_stops(self):
        m = {"tag": "v1", "previous": "v0", "commits": "", "changelog": "", "known": ""}
        with self.assertRaises(SystemExit):
            rn.user_message(m)


class Response:
    def __init__(self, body):
        self.raw = io.BytesIO(json.dumps(body).encode())

    def read(self, *a):
        return self.raw.read(*a)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class CallApi(unittest.TestCase):
    def call(self, body):
        seen = {}

        def opener(req, timeout):
            seen["req"], seen["timeout"] = req, timeout
            return Response(body)

        return rn.call_api({"model": "m"}, "sk-test", opener), seen

    def test_joins_text_blocks_and_skips_thinking(self):
        text, seen = self.call(
            {"stop_reason": "end_turn", "content": [{"type": "thinking", "thinking": ""}, {"type": "text", "text": " Notes "}]}
        )
        self.assertEqual(text, "Notes\n")
        req = seen["req"]
        self.assertEqual(req.full_url, rn.API_URL)
        self.assertEqual(req.get_header("X-api-key"), "sk-test")
        self.assertEqual(req.get_header("Anthropic-version"), "2023-06-01")
        self.assertEqual(json.loads(req.data), {"model": "m"})

    def test_refusal_truncation_and_empty_text_fail(self):
        for body in (
            {"stop_reason": "refusal", "content": []},
            {"stop_reason": "max_tokens", "content": [{"type": "text", "text": "half"}]},
            {"stop_reason": "end_turn", "content": [{"type": "text", "text": "  "}]},
        ):
            with self.assertRaises(SystemExit):
                self.call(body)

    def test_http_error_never_echoes_the_key(self):
        def opener(req, timeout):
            raise urllib.error.HTTPError(rn.API_URL, 401, "Unauthorized", {}, io.BytesIO(b'{"error":"bad key"}'))

        with self.assertRaises(SystemExit) as cm:
            rn.call_api({"model": "m"}, "sk-secret", opener)
        self.assertIn("401", str(cm.exception.code))
        self.assertNotIn("sk-secret", str(cm.exception.code))


if __name__ == "__main__":
    unittest.main()
