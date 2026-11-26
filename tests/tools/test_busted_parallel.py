"""Offline tests for scripts/busted_parallel.sh: the live progress lines, the unchanged end-of-run report, and the GitHub
Actions mode (groups, annotations, step summary), on a copy of the script over two tiny spec files and a fake busted."""

import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import unittest

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "busted_real_failure.txt")  # real busted, ASCII arrow
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SCRIPT = os.path.join(ROOT, "scripts", "busted_parallel.sh")

FAKE_BUSTED = """#!/usr/bin/env bash
f="${@: -1}"
if grep -q REAL "$f"; then
    cat "$FIXTURE"
    exit 1
fi
if grep -q LEAD "$f"; then
    printf '::notice::injected\\n1 success / 0 failures / 0 errors / 0 pending : 0.1 seconds\\n'
    exit 0
fi
if grep -q ZERO "$f"; then
    echo "0 successes / 0 failures / 0 errors / 0 pending : 0.000100 seconds"
    exit 0
fi
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
        path = os.path.join(self.tmp, "tests", name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as h:
            h.write(body)

    def run_script(self, github=False):
        env = {k: v for k, v in os.environ.items() if not k.startswith(("GITHUB_", "DETECT_WRITE"))}
        env.update(BUSTED=self.fake, BUSTED_JOBS="2", FIXTURE=FIXTURE, XDG_CACHE_HOME=os.path.join(self.tmp, "cache"))
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

    def test_real_busted_failure_annotation(self):
        self.spec("Forever/zz_runner_probe_spec.lua", "REAL")
        out = self.run_script(github=True).stdout
        self.assertIn(
            "::error file=tests/Forever/zz_runner_probe_spec.lua,line=3::runner probe #druid fails on purpose to test"
            " annotations: tests/Forever/zz_runner_probe_spec.lua:3: Expected objects to be equal.\n",
            out,
        )

    def test_no_history_no_eta(self):
        self.spec("a_spec.lua")
        out = self.run_script().stdout
        self.assertEqual(out.splitlines()[0], "running 1 spec files, 2 at a time")
        self.assertNotIn("left", out)

    def test_zero_test_files_are_silent_but_counted(self):
        self.spec("a_spec.lua")
        self.spec("z_spec.lua", "ZERO")
        for github in (False, True):
            out = self.run_script(github).stdout
            self.assertNotIn("z_spec", out)
            self.assertRegex(out, r"\[\d/2 done, \d running\] tests/a_spec\.lua ok")
            self.assertTrue(out.endswith("\nall files: 2 successes / 0 failures / 0 errors / 0 pending\n"))

    def test_warm_cache_eta_ignores_deleted_specs(self):
        self.spec("a_spec.lua")
        self.spec("b_spec.lua")
        key = hashlib.md5(b" ").hexdigest()[:12]
        cache = os.path.join(self.tmp, "cache", "hekili-busted")
        os.makedirs(cache)
        with open(os.path.join(cache, key), "w") as h:
            h.write("240 tests/a_spec.lua\n120 tests/b_spec.lua\n9999 tests/gone_spec.lua\n")
        out = self.run_script().stdout
        self.assertEqual(out.splitlines()[0], "running 2 spec files, 2 at a time, about 3 min")
        self.assertRegex(out, r"\[1/2 done, 1 running\] tests/\w+\.lua ok \d+m\d\ds, about [12] min left")

    def test_annotation_file_property_is_escaped(self):
        self.spec("Forever/odd,name_spec.lua", "REAL")
        self.assertIn("::error file=tests/Forever/odd%2Cname_spec.lua,line=3::", self.run_script(github=True).stdout)

    def test_leading_colons_in_group_logs_are_neutralised(self):
        self.spec("a_spec.lua", "LEAD")
        out = self.run_script(github=True).stdout
        # once in the end dump (known limit: it stays byte-identical), not in the per-file group
        self.assertEqual(out.count("\n::notice::injected\n"), 1)

    def test_local_mode_has_no_workflow_commands(self):
        self.spec("a_spec.lua")
        self.assertNotIn("::", self.run_script().stdout)


if __name__ == "__main__":
    unittest.main()
