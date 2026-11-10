"""Offline tests for scripts/ab_delta.sh (cdm-verdict review M4): the per-spec A/B deltas over two .ab dirs, the
flicker (+0.3/min) and agreement gates, the -novd twin comparison and its "vacuous" mark, on throwaway .tsv files."""

import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SCRIPT = os.path.join(ROOT, "scripts", "ab_delta.sh")


def summary(label, agreement, flicker, prefix=""):
    return "%s\tok\t%sfights=20 agreement %.3f (100 ticks); react median 0; flicker %.2f/min (oracle 0.10); x\n" % (
        label,
        prefix,
        agreement,
        flicker,
    )


def fight(who, seed, stale, verdicts=None, strikes="0/0", wrong=None):
    rows = "layout\tok\t%s seed %d covered 3 overflow 0 slots 3 lag false facts 1/1 ambiguous 0" % (who, seed)
    if verdicts is not None:
        rows += " verdicts %s strikes %s" % (verdicts, strikes)
    if wrong is not None:
        rows += " wrong %s" % wrong
    rows += "\nedge\tok\t%s seed %d seeds 0/0 edges 0/0 waits 0 fires 0 downs 1 staleUp %s earlyDown 0.00/0.00" % (
        who,
        seed,
        stale,
    )
    return rows + " missed 0 long 0 errs -\n"


class Delta(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.base, self.head = os.path.join(self.tmp, "base"), os.path.join(self.tmp, "head")
        os.makedirs(self.base)
        os.makedirs(self.head)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, d, arm, text):
        with open(os.path.join(d, arm + ".tsv"), "w", encoding="utf-8") as f:
            f.write(text)

    def run_delta(self):
        p = subprocess.run([SCRIPT, self.base, self.head], capture_output=True, text=True)
        return p.returncode, p.stdout

    def test_base_to_head_deltas_pass_within_the_bounds(self):
        self.write(self.base, "viewer-mixed", summary("Feral", 0.980, 0.10) + summary("Feral", 0.980, 0.10, "flicker floor: "))
        self.write(self.head, "viewer-mixed", summary("Feral", 0.981, 0.35))
        rc, out = self.run_delta()
        self.assertEqual(rc, 0, out)
        self.assertIn("viewer-mixed\tFeral\tagreement 0.980 -> 0.981 (+0.001)\tflicker 0.10 -> 0.35 (+0.25)\n", out)

    def test_a_flicker_rise_past_0_3_or_an_agreement_fall_fails(self):
        self.write(self.base, "viewer-buffs", summary("Feral", 0.980, 0.10) + summary("Guardian", 0.900, 0.2))
        self.write(self.head, "viewer-buffs", summary("Feral", 0.980, 0.45) + summary("Guardian", 0.899, 0.2))
        rc, out = self.run_delta()
        self.assertEqual(rc, 1, out)
        self.assertIn("Feral\tagreement 0.980 -> 0.980 (+0.000)\tflicker 0.10 -> 0.45 (+0.35) FAIL flicker", out)
        self.assertIn("Guardian\tagreement 0.900 -> 0.899 (-0.001)\tflicker 0.20 -> 0.20 (+0.00) FAIL agreement", out)

    def test_a_head_log_with_failed_spec_files_fails_the_arm(self):
        rows = summary("Feral", 0.98, 0.1)
        self.write(self.base, "viewer-buffs", rows)
        self.write(self.head, "viewer-buffs", rows)
        log = os.path.join(self.head, "viewer-buffs.log")
        with open(log, "w", encoding="utf-8") as f:
            f.write("all files: 39 successes / 0 failures / 0 errors / 0 pending\n")
        self.assertEqual(self.run_delta()[0], 0)  # a clean log passes
        with open(log, "w", encoding="utf-8") as f:
            f.write("all files: 39 successes / 3 failures / 0 errors / 0 pending\n")
        rc, out = self.run_delta()
        self.assertEqual(rc, 1, out)
        self.assertIn("viewer-buffs\t-\tFAIL specs all files: 39 successes / 3 failures / 0 errors / 0 pending\n", out)
        with open(log, "w", encoding="utf-8") as f:
            f.write("all files: 39 successes / 0 failures / 1 errors / 0 pending\n")
        self.assertEqual(self.run_delta()[0], 1)
        os.remove(log)  # a missing log is not a failure (older runs)
        self.assertEqual(self.run_delta()[0], 0)

    def test_twins_sum_per_character_and_mark_vacuous(self):
        self.write(
            self.head,
            "viewer-late",
            summary("Feral", 0.97, 0.2)
            + fight("DRUID feral", 1, "1.00/2.50", "0/3", "0/1")
            + fight("DRUID feral", 2, "0.50/0.50", "1/1", "0/0")
            + fight("DRUID guardian", 1, "0.00/4.00", "0/0"),
        )
        self.write(
            self.head,
            "viewer-late-novd",
            summary("Feral", 0.97, 0.1)
            + fight("DRUID feral", 1, "2.00/9.00", "0/0")
            + fight("DRUID feral", 2, "1.00/1.00", "0/0")
            + fight("DRUID guardian", 1, "0.00/4.00", "0/0"),
        )
        rc, out = self.run_delta()
        self.assertEqual(rc, 0, out)
        title = "viewer-late (novd -> on)\t"
        self.assertIn(
            title + "DRUID feral\tfights 2 -> 2\tstaleUp 3.00/10.00 -> 1.50/3.00 (-1.50/-7.00)\tverdicts 0/0 -> 1/4"
            "\tstrikes 0/0 -> 0/1\n",
            out,
        )
        rows = {line.split("\t")[1]: line for line in out.splitlines() if line.startswith(title)}
        self.assertTrue(rows["DRUID guardian"].endswith("\tvacuous"), out)  # 0 verdicts in both twins
        self.assertNotIn("vacuous", rows["DRUID feral"])
        self.assertNotIn("viewer-late-novd (novd", out)

    def test_a_late_twin_counts_its_wrong_closes_without_failing(self):
        self.write(self.head, "viewer-late", summary("Feral", 0.97, 0.2) + fight("DRUID feral", 1, "0/1", "0/2", "0/0", "0/2"))
        self.write(self.head, "viewer-late-novd", summary("Feral", 0.97, 0.2) + fight("DRUID feral", 1, "0/1", "0/0"))
        rc, out = self.run_delta()
        self.assertEqual(rc, 0, out)  # late lights make wrong closes by design
        self.assertIn("\twrong 0/0 -> 0/2\n", out)

    def test_a_character_without_old_edge_rows_prints_staleup_na(self):
        self.write(self.base, "viewer-buffs", summary("Feral", 0.97, 0.2))
        self.write(self.head, "viewer-buffs", summary("Feral", 0.97, 0.2) + fight("DRUID feral", 1, "1.00/2.00"))
        rc, out = self.run_delta()
        self.assertEqual(rc, 0, out)
        self.assertIn("viewer-buffs\tDRUID feral\tfights 0 -> 1\tstaleUp n/a -> 1.00/2.00\tverdicts", out)

    def test_wrong_closes_sum_per_character_and_fail_a_twin(self):
        self.write(
            self.head,
            "viewer-swap",
            summary("Feral", 0.97, 0.2)
            + fight("DRUID feral", 1, "0.00/1.00", "0/3", "0/0", "0/1")
            + fight("DRUID feral", 2, "0.00/1.00", "1/2", "0/0", "1/1"),
        )
        self.write(
            self.head,
            "viewer-swap-novd",
            summary("Feral", 0.97, 0.2)
            + fight("DRUID feral", 1, "0.00/2.00", "0/0", "0/0", "0/0")
            + fight("DRUID feral", 2, "0.00/2.00", "0/0", "0/0", "0/0"),
        )
        rc, out = self.run_delta()
        self.assertEqual(rc, 1, out)
        self.assertIn("\tverdicts 0/0 -> 1/5\tstrikes 0/0 -> 0/0\twrong 0/0 -> 1/2 FAIL wrong\n", out)

    def test_a_spec_the_head_lost_fails_and_a_new_one_is_reported(self):
        self.write(self.base, "meter", summary("Arms", 0.95, 0.1))
        self.write(self.head, "meter", summary("Fury L24", 0.93, 0.1))
        rc, out = self.run_delta()
        self.assertEqual(rc, 1, out)  # a cut-short head run is never a pass (batch review Should 1)
        self.assertIn("meter\tArms\tonly in old FAIL missing\n", out)
        self.assertIn("meter\tFury L24\tonly in new\n", out)

    def test_a_spec_only_the_head_has_passes(self):
        self.write(self.base, "meter", summary("Arms", 0.95, 0.1))
        self.write(self.head, "meter", summary("Arms", 0.95, 0.1) + summary("Fury L24", 0.93, 0.1))
        rc, out = self.run_delta()
        self.assertEqual(rc, 0, out)
        self.assertIn("meter\tFury L24\tonly in new\n", out)

    def test_a_base_arm_the_head_never_wrote_fails(self):
        self.write(self.base, "meter", summary("Arms", 0.95, 0.1))
        self.write(self.base, "viewer-buffs", summary("Arms", 0.95, 0.1))
        self.write(self.head, "meter", summary("Arms", 0.95, 0.1))
        rc, out = self.run_delta()
        self.assertEqual(rc, 1, out)
        self.assertIn("viewer-buffs\t-\tonly in old FAIL missing arm\n", out)


if __name__ == "__main__":
    unittest.main()
