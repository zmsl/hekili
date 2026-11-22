"""Offline test for tools/accuracy/run.sh (lane B4 re-review M3): the rows its passes record leave a gate-ab's .ab
files as they were, on a throwaway tree with a stand-in busted."""

import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BUSTED = '#!/bin/sh\nmkdir -p .ab\necho "power row" >> ".ab/${HEKILI_AB:-default}.tsv"\n'


class Run(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.tmp, "tools", "accuracy"))
        shutil.copy(os.path.join(ROOT, "tools", "accuracy", "run.sh"), os.path.join(self.tmp, "tools", "accuracy"))
        os.makedirs(os.path.join(self.tmp, "tests", "Forever"))
        for name, body in (("loop_x_spec.lua", "solo(1)\n"), ("wowsims_x_spec.lua", "ws.gate(1)\n")):
            with open(os.path.join(self.tmp, "tests", "Forever", name), "w") as f:
                f.write(body)
        self.busted = os.path.join(self.tmp, "busted")
        with open(self.busted, "w") as f:
            f.write(BUSTED)
        os.chmod(self.busted, 0o755)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_passes(self):
        script = os.path.join(self.tmp, "tools", "accuracy", "run.sh")
        env = dict(os.environ, BUSTED=self.busted)
        env.pop("ACC_LIVE_ARM", None)
        subprocess.run(["sh", script], env=env, check=True, capture_output=True)
        left = {}
        for name in ("default.tsv", "live-auras-none.tsv"):
            path = os.path.join(self.tmp, ".ab", name)
            if os.path.exists(path):
                with open(path) as f:
                    left[name] = f.read()
        return left

    def test_its_own_rows_go(self):
        self.assertEqual({}, self.run_passes())

    def test_gate_ab_rows_stay(self):
        os.makedirs(os.path.join(self.tmp, ".ab"))
        had = {"default.tsv": "gate-ab default\n", "live-auras-none.tsv": "gate-ab arm\n"}
        for name, body in had.items():
            with open(os.path.join(self.tmp, ".ab", name), "w") as f:
                f.write(body)
        self.assertEqual(had, self.run_passes())


if __name__ == "__main__":
    unittest.main()
