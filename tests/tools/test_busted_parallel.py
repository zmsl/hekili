"""Offline tests for scripts/busted_parallel.sh: the live progress lines, the unchanged end-of-run report, and the GitHub
Actions mode (groups, annotations, step summary), on a copy of the script over two tiny spec files and a fake busted."""

import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SCRIPT = os.path.join(ROOT, "scripts", "busted_parallel.sh")

FAKE_BUSTED = """#!/usr/bin/env bash
f="${@: -1}"
if grep -q FAIL "$f"; then
    printf 'Failure → %s @ 7\\nsome test\\n%s:9: Expected objects to be equal.\\n' "$f" "$f"
    echo "1 success / 1 failure / 0 errors / 0 pending : 0.5 seconds"
    exit 1
fi
echo "2 successes / 0 failures / 0 errors / 0 pending : 0.25 seconds"
"""


class BustedParallel(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        os.makedirs(os.path.join(self.tmp, "scripts"))
        os.makedirs(os.path.join(self.tmp, "tests"))
        shutil.copy(SCRIPT, os.path.join(self.tmp, "scripts"))
        self.fake = os.path.join(self.tmp, "fake_busted")
        with open(self.fake, "w") as h:
            h.write(FAKE_BUSTED)
        os.chmod(self.fake, 0o755)
        self.summary = os.path.join(self.tmp, "summary.md")

    def spec(self, name, body=""):
        with open(os.path.join(self.tmp, "tests", name), "w") as h:
            h.write(body)

    def run_script(self, github=False):
        env = {k: v for k, v in os.environ.items() if not k.startswith(("GITHUB_", "DETECT_WRITE"))}
        env.update(BUSTED=self.fake, BUSTED_JOBS="2", XDG_CACHE_HOME=os.path.join(self.tmp, "cache"))
        if github:
            env.update(GITHUB_ACTIONS="true", GITHUB_STEP_SUMMARY=self.summary)
        return subprocess.run(
            ["bash", os.path.join(self.tmp, "scripts", "busted_parallel.sh")],
            capture_output=True, text=True, env=env, timeout=60,
        )

    def test_progress_and_unchanged_report(self):
        self.spec("a_spec.lua")
        self.spec("b_spec.lua")
        r = self.run_script()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        lines = r.stdout.splitlines()
        self.assertEqual(lines[0], "running 2 spec files, 2 at a time")
        prog = [re.match(r"\[(\d)/2 done, \d running\] (tests/\w+\.lua) ok \d+m\d\ds", ln) for ln in lines[1:3]]
        self.assertTrue(all(prog), lines)
        self.assertEqual(sorted(m.group(2) for m in prog), ["tests/a_spec.lua", "tests/b_spec.lua"])
        self.assertEqual(sorted(m.group(1) for m in prog), ["1", "2"])
        ok = "2 successes / 0 failures / 0 errors / 0 pending : 0.25 seconds"
        self.assertEqual(
            lines[3:],
            ["== tests/a_spec.lua (rc=0)", ok, "== tests/b_spec.lua (rc=0)", ok, "",
             "all files: 4 successes / 0 failures / 0 errors / 0 pending"],
        )

    def test_failure_prints_fail_and_exits_1(self):
        self.spec("a_spec.lua")
        self.spec("b_spec.lua", "FAIL")
        r = self.run_script()
        self.assertEqual(r.returncode, 1)
        self.assertRegex(r.stdout, r"\] tests/b_spec\.lua FAIL ")
        self.assertRegex(r.stdout, r"\] tests/a_spec\.lua ok ")
        self.assertIn("== tests/b_spec.lua (rc=1)\n", r.stdout)
        self.assertTrue(r.stdout.endswith("all files: 3 successes / 1 failures / 0 errors / 0 pending\nFAILED: tests/b_spec.lua\n"))

    def test_github_mode(self):
        self.spec("a_spec.lua")
        self.spec("b_spec.lua", "FAIL")
        r = self.run_script(github=True)
        self.assertEqual(r.returncode, 1)
        out = r.stdout
        self.assertEqual(out.count("::group::"), 3)  # a file each, plus the full output
        self.assertEqual(out.count("::endgroup::"), 3)
        self.assertIn("::group::Full per-file output (path order)\n", out)
        self.assertIn("::error file=tests/b_spec.lua,line=9::some test: tests/b_spec.lua:9: Expected objects to be equal.\n", out)
        tail = out.split("::endgroup::\n")[-1]  # after the last group: totals and FAILED, ungrouped
        self.assertEqual(
            tail, "\nall files: 3 successes / 1 failures / 0 errors / 0 pending\nFAILED: tests/b_spec.lua\n"
        )
        with open(self.summary) as h:
            md = h.read()
        self.assertIn("| tests/b_spec.lua | FAIL |", md)
        self.assertIn("| tests/a_spec.lua | ok |", md)
        self.assertIn("Slowest files:", md)
        self.assertIn("FAILED: tests/b_spec.lua", md)

    def test_local_mode_has_no_workflow_commands(self):
        self.spec("a_spec.lua")
        self.assertNotIn("::", self.run_script().stdout)


if __name__ == "__main__":
    unittest.main()
