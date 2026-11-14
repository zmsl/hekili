"""Offline tests for scripts/check_stamp.sh (test-speed plan, Task 2): `make check` skips only when every input matches
the last green run, in a throwaway git repository; and the real tree's env list and Makefile wiring."""

import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SCRIPT = os.path.join(ROOT, "scripts", "check_stamp.sh")
SKIP_LINE = "check: skipped, inputs unchanged since the last green check; FULL=1 runs it"
DOCS_LINE = "check: skipped, only docs no test reads changed since the last green check: %s; FULL=1 runs it"


def env_vars():
    with open(SCRIPT, encoding="utf-8") as f:
        return re.search(r'^ENV_VARS="([^"]*)"$', f.read(), re.M).group(1).split()


class Stamp(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.repo = os.path.join(self.tmp, "repo")
        files = {
            "src/Hekili/a.lua": "local a = 1\n",
            "src/Hekili/Hekili.toc": "## Interface: 16001\na.lua\n",
            "tests/x_spec.lua": "it('x', function() end)\n",
            "README.md": "readme\n",
            "CHANGELOG.md": "changelog\n",
            "docs/publishing/README.md": "publishing\n",
            "docs/dev/notes.md": "notes\n",
            "DEVELOPMENT.md": "dev\n",
            ".gitignore": ".lua/\n.ab/\n",
            ".gitattributes": "* text=auto\n",
            ".lua/bin/busted": "v1",
        }
        for path, text in files.items():
            self.write(path, text)
        os.makedirs(os.path.join(self.repo, "scripts"))
        shutil.copy2(SCRIPT, os.path.join(self.repo, "scripts", "check_stamp.sh"))
        self.git("init", "-q")
        self.git("add", "-A")
        self.git("-c", "user.name=test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def path(self, rel):
        return os.path.join(self.repo, rel)

    def write(self, rel, text, mode="w"):
        os.makedirs(os.path.dirname(self.path(rel)), exist_ok=True)
        with open(self.path(rel), mode, newline="") as f:
            f.write(text)

    def env(self, extra=None):
        # every ENV_VARS name removed (PATH kept, HOME pinned), the same for stamp() and skips() (ruling S11)
        names = set(env_vars())
        env = {k: v for k, v in os.environ.items() if k not in names and not k.startswith("GIT_")}
        env["PATH"] = os.environ["PATH"]
        env["HOME"] = self.tmp
        env.update(extra or {})
        return env

    def git(self, *args, cwd=None):
        subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.env(), check=True, capture_output=True)

    def run_script(self, *args, env=None, cwd=None):
        return subprocess.run(
            ["bash", "scripts/check_stamp.sh", *args],
            cwd=cwd or self.repo,
            env=self.env(env),
            capture_output=True,
            text=True,
        )

    def stamp(self):
        start = os.path.join(self.tmp, "start")
        self.assertEqual(self.run_script("begin", start).returncode, 0)
        r = self.run_script("write", start)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def skips(self, env=None, cwd=None):
        self.last = self.run_script("test", env=env, cwd=cwd)
        return self.last.returncode == 0

    def test_fresh_repo_runs(self):
        self.assertFalse(self.skips())
        self.assertEqual(self.last.stdout, "")

    def test_unchanged_skips_with_one_line(self):
        self.stamp()
        self.assertTrue(self.skips())
        self.assertEqual(self.last.stdout, SKIP_LINE + "\n")
        self.assertTrue(self.last.stdout.startswith("check: skipped,"))

    def test_lua_edit_runs(self):
        self.stamp()
        self.write("src/Hekili/a.lua", "local b = 2\n", "a")
        self.assertFalse(self.skips())

    def test_toc_edit_runs(self):
        self.stamp()
        self.write("src/Hekili/Hekili.toc", "b.lua\n", "a")
        self.assertFalse(self.skips())

    def test_test_file_edit_runs(self):
        self.stamp()
        self.write("tests/x_spec.lua", "-- more\n", "a")
        self.assertFalse(self.skips())

    def test_line_ending_edit_runs(self):  # ruling S3: raw bytes, not git's normalised blob
        self.stamp()
        self.write("src/Hekili/a.lua", "local a = 1\r\n")
        self.assertFalse(self.skips())

    def test_untracked_file_runs(self):
        self.stamp()
        self.write("src/Hekili/b.lua", "local b = 2\n")
        self.assertFalse(self.skips())

    def test_ignored_file_skips(self):
        self.stamp()
        self.write(".ab/x.tsv", "1\n")
        self.assertTrue(self.skips())

    def test_ignored_lua_file_runs(self):  # ruling S4: luacheck and stylua read it
        self.stamp()
        self.write(".ab/x.lua", "local x = 1\n")
        self.assertFalse(self.skips())

    def test_nested_repo_never_hides_a_later_edit(self):  # fix round 1: a dir entry once cut every later hash
        self.write("src/Hekili/c.lua", "local c = 3\n")
        self.git("add", "src/Hekili/c.lua")
        self.write("src/Hekili/b/inner.lua", "local i = 1\n")
        self.git("init", "-q", cwd=self.path("src/Hekili/b"))
        self.stamp()
        self.assertTrue(self.skips())
        self.write("src/Hekili/c.lua", "local d = 4\n", "a")
        self.assertFalse(self.skips())
        self.write("src/Hekili/c.lua", "local c = 3\n")
        self.assertTrue(self.skips())
        self.write("src/Hekili/b/inner.lua", "local j = 2\n", "a")
        self.assertFalse(self.skips())

    @unittest.skipIf(os.geteuid() == 0, "root reads a mode-000 file")
    def test_unreadable_file_runs(self):
        self.stamp()
        self.write("src/Hekili/z.lua", "local z = 1\n")
        os.chmod(self.path("src/Hekili/z.lua"), 0)
        self.assertFalse(self.skips())
        self.assertEqual(self.last.stdout, "")
        self.assertNotEqual(self.run_script("manifest").returncode, 0)

    def test_deleted_file_runs(self):
        self.stamp()
        os.remove(self.path("src/Hekili/a.lua"))
        self.assertFalse(self.skips())

    def test_exec_bit_runs(self):
        self.stamp()
        os.chmod(self.path("src/Hekili/a.lua"), 0o755)
        self.assertFalse(self.skips())

    def test_staging_only_runs(self):
        self.write("src/Hekili/a.lua", "local b = 2\n", "a")
        self.stamp()
        self.git("add", "src/Hekili/a.lua")
        self.assertFalse(self.skips())

    def test_env_var_runs(self):
        self.stamp()
        self.assertFalse(self.skips({"DETECT_WRITE": "1"}))
        self.assertFalse(self.skips({"DETECT_WRITE": ""}))
        self.assertTrue(self.skips())

    def test_toolchain_runs(self):
        self.stamp()
        self.write(".lua/bin/busted", "v2")
        self.assertFalse(self.skips())

    def test_change_during_run_writes_no_stamp(self):
        start = os.path.join(self.tmp, "start")
        self.run_script("begin", start)
        self.write("src/Hekili/a.lua", "local b = 2\n", "a")
        r = self.run_script("write", start)
        self.assertEqual(r.returncode, 0)
        self.assertIn("no stamp", r.stdout)
        self.assertFalse(os.path.exists(start))
        self.assertFalse(self.skips())

    def test_abandoned_begin_leaves_no_stamp(self):
        self.run_script("begin", os.path.join(self.tmp, "start"))
        self.assertFalse(self.skips())

    def test_stamp_is_per_worktree(self):
        wt = os.path.join(self.tmp, "wt")
        self.git("worktree", "add", "-q", wt)
        shutil.copytree(self.path(".lua"), os.path.join(wt, ".lua"))  # same toolchain (ruling S11)
        main = self.run_script("manifest")
        other = self.run_script("manifest", cwd=wt)
        self.assertEqual(main.returncode, 0, main.stderr)
        self.assertEqual(main.stdout, other.stdout)  # identical inputs: only the stamp's place differs
        self.stamp()
        self.assertTrue(self.skips())
        self.assertFalse(self.skips(cwd=wt))

    # Task 3: the docs-only skip (ruling S5)
    def test_unread_doc_edit_skips(self):
        self.stamp()
        self.write("docs/dev/notes.md", "more\n", "a")
        self.write("DEVELOPMENT.md", "more\n", "a")
        self.assertTrue(self.skips())
        self.assertEqual(self.last.stdout, DOCS_LINE % "DEVELOPMENT.md (+1 more)" + "\n")

    def test_one_doc_edit_names_it_alone(self):
        self.stamp()
        self.write("docs/dev/notes.md", "more\n", "a")
        self.assertTrue(self.skips())
        self.assertEqual(self.last.stdout, DOCS_LINE % "docs/dev/notes.md" + "\n")

    def test_new_and_deleted_unread_docs_skip(self):
        self.stamp()
        self.write("docs/dev/new.md", "new\n")
        os.remove(self.path("docs/dev/notes.md"))
        self.assertTrue(self.skips())

    def test_staged_doc_skips(self):  # the I line changes too; still a doc
        self.stamp()
        self.write("docs/dev/notes.md", "more\n", "a")
        self.git("add", "docs/dev/notes.md")
        self.assertTrue(self.skips())

    def test_docs_skip_keeps_the_stamp(self):
        self.stamp()
        with open(self.stamp_path(), "rb") as f:
            before = f.read()
        self.write("docs/dev/notes.md", "more\n", "a")
        self.assertTrue(self.skips())
        with open(self.stamp_path(), "rb") as f:
            self.assertEqual(f.read(), before)

    def test_read_docs_run(self):
        for rel in ("README.md", "CHANGELOG.md", "docs/publishing/README.md"):
            with self.subTest(rel=rel):
                self.stamp()
                self.write(rel, "more\n", "a")
                self.assertFalse(self.skips())
                self.assertEqual(self.last.stdout, "")
                self.git("checkout", "--", rel)

    def test_docs_in_code_dirs_run(self):
        for rel in ("tests/notes.md", "tools/notes.md", "src/Hekili/Libs/CREDITS.md"):
            with self.subTest(rel=rel):
                self.stamp()
                self.write(rel, "notes\n")
                self.assertFalse(self.skips())
                os.remove(self.path(rel))

    def test_non_md_under_docs_runs(self):  # ruling S5: only *.md counts as docs
        for rel in ("docs/dev/x.lua", "docs/dev/data.json", "docs/dev/notes.MD"):
            with self.subTest(rel=rel):
                self.stamp()
                self.write(rel, "x\n")
                self.assertFalse(self.skips())
                os.remove(self.path(rel))

    def test_doc_and_code_runs(self):
        self.stamp()
        self.write("docs/dev/notes.md", "more\n", "a")
        self.write("src/Hekili/a.lua", "local b = 2\n", "a")
        self.assertFalse(self.skips())

    def test_doc_and_env_runs(self):
        self.stamp()
        self.write("docs/dev/notes.md", "more\n", "a")
        self.assertFalse(self.skips({"TIMING": "record"}))

    def test_doc_and_toolchain_runs(self):
        self.stamp()
        self.write("docs/dev/notes.md", "more\n", "a")
        self.write(".lua/bin/busted", "v2")
        self.assertFalse(self.skips())

    def stamp_path(self):
        out = subprocess.run(
            ["git", "rev-parse", "--absolute-git-dir"], cwd=self.repo, env=self.env(), capture_output=True, text=True
        )
        return os.path.join(out.stdout.strip(), "hekili-check-stamp")


def repo_files(*exts):
    out = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "--", "tests", "tools", "scripts"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split("\n")
    return [p for p in out if p.endswith(exts) and os.path.isfile(os.path.join(ROOT, p))]


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


# Names a check part may read that are not inputs, each with its reason.
NOT_INPUTS = {
    "ANTHROPIC_API_KEY": "release-only tool, mocked in its tests",
    "CF_API_KEY": "release-only tool, mocked in its tests",
    "XDG_CACHE_HOME": "scripts/busted_parallel.sh's run-order cache: order only",
    "GATE_TAGS": "tools/accuracy/run.sh: make accuracy, not check",
    "WOWSIMS_NEW": "tools/wowsims/drift.lua: a dev-only report, not check",
    "WOWSIMS_NEW_TREE": "tools/wowsims/drift.lua: a dev-only report, not check",
    "WOWSIMS_NEW_CLI": "tools/wowsims/drift.lua: a dev-only report, not check",
    "LUACHECK": "set by the Makefile on api-check's line (a := variable)",
    "FULL": "only forces a full run",
    "MAKE": "make itself",
}
# Files that read an environment variable by a computed name, with the names they read (all in ENV_VARS).
DYNAMIC_READS = {"tools/wowsims/export.lua": "env(name): WOWSIMS, WOWSIMS_CLI, WOWDB"}
SHELL_READ = re.compile(r"\$\{?([A-Za-z_]\w*)")
SHELL_SET = re.compile(r"(?:^|[\s;(&|])(?:local\s+|export\s+)?([A-Za-z_]\w*)=(?!\"?\$\{\1[:}-])")
SHELL_BIND = re.compile(r"\b(?:for|mapfile\s+-t|read\s+-r|local)\s+([A-Za-z_]\w*(?:\s+[A-Za-z_]\w*)*)")
CHECK_PARTS = "check check-full lint fmt-check typecheck test syntax api-check packs-check wowsims-packs packs tools-test"


def shell_reads(text):
    """Variable names a shell text reads that it never binds itself."""
    bound = set(SHELL_SET.findall(text))
    for words in SHELL_BIND.findall(text):
        bound.update(w for w in words.split() if "=" not in w)
    awk = set(re.findall(r"\$(NF|NR)\b", text))  # awk fields inside the scripts' awk programs
    return set(SHELL_READ.findall(text)) - bound - awk


def recipes(makefile, targets):
    """The recipe lines of the named Makefile targets."""
    out, current = [], None
    for line in makefile.split("\n"):
        if line.startswith("\t"):
            if current in targets:
                out.append(line)
        elif line.strip() and not line.startswith("#"):
            m = re.match(r"^([\w.-]+):(?!=)", line)
            current = m.group(1) if m else None
    return out


class Repository(unittest.TestCase):
    def test_env_list_covers_every_getenv(self):
        listed = set(env_vars())
        missing = []
        for rel in repo_files(".lua", ".py", ".sh"):
            text = read(rel)
            names = set()
            for m in re.finditer(r"""os\.(?:getenv\(|environ\.get\(|environ\[)\s*(["']?)(\w*)""", text):
                if m.group(1):
                    names.add(m.group(2))
                elif rel not in DYNAMIC_READS:
                    missing.append("%s: computed name %s" % (rel, m.group(0)))
            if rel.endswith(".sh"):
                names |= shell_reads(text)
            missing += ["%s: %s" % (rel, n) for n in sorted(names - listed - set(NOT_INPUTS))]
        makefile = read("Makefile")
        lines = "\n".join(recipes(makefile, set(CHECK_PARTS.split())))
        defined = set(re.findall(r"^(\w+)\s*:?=", makefile, re.M))  # ?= stays out: the environment can set it
        names = shell_reads(lines.replace("$$", "$").replace("$(", "("))
        names |= set(re.findall(r"\$\(([A-Z_]+)\)", lines)) - defined
        missing += ["Makefile: %s" % n for n in sorted(names - listed - set(NOT_INPUTS))]
        self.assertEqual(missing, [])

    def test_gate_never_consults_the_stamp(self):
        makefile = read("Makefile")
        gate = re.search(r"^gate:(.*)$", makefile, re.M).group(1).split()
        self.assertEqual(gate, ["check-full"])
        full = recipes(makefile, {"check-full"})
        self.assertTrue(full)
        self.assertFalse([l for l in full if "check_stamp.sh test" in l])

    def test_overrides_and_ignored_errors_never_skip_or_stamp(self):  # rulings S1, S2
        makefile = read("Makefile")
        for line in recipes(makefile, {"check", "check-full"}):
            if "check_stamp.sh" in line:
                self.assertIn("$(STAMP_OFF)", line)
        rule = re.search(r"^STAMP_OFF :=.*$", makefile, re.M).group(0)
        env = {k: v for k, v in os.environ.items() if k not in ("MAKEFLAGS", "MFLAGS", "MAKELEVEL", "MAKEOVERRIDES")}
        tmp = tempfile.mkdtemp()
        try:
            mk = os.path.join(tmp, "M")
            with open(mk, "w") as f:
                f.write(rule + "\nshow:\n\t@echo '[$(STAMP_OFF)]'\nsub:\n\t@$(MAKE) -s -f M show\n")
            for args, off in [
                ([], False),
                (["FULL=1"], False),
                (["-k"], False),
                (["-j2"], False),
                (["TEST_EXCLUDE=--tags=x"], True),
                (["BUSTED=x"], True),
                (["-i"], True),
                (["--ignore-errors"], True),
                (["-e"], True),
                (["-i", "FULL=1"], True),
            ]:
                for target in ("show", "sub"):
                    out = subprocess.run(
                        ["make", "-s", "--no-print-directory", "-f", "M", target, *args],
                        cwd=tmp,
                        env=env,
                        capture_output=True,
                        text=True,
                        check=True,
                    ).stdout.strip()
                    self.assertEqual(out != "[]", off, (args, target, out))
        finally:
            shutil.rmtree(tmp)

    def test_docs_read_by_tests_are_never_docs_only(self):  # ruling S5's guard
        literal = re.compile(r"""["']([^"' ]*\.md|docs/[^"' ]*)["']""")
        tracked = set(
            subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split("\n")
        )
        named = set()
        for rel in repo_files(".lua", ".py", ".sh"):
            if rel == "tests/tools/test_check_stamp.py":
                continue  # its literals name the temp repo's fixture files, not the real tree's
            comment = "--" if rel.endswith(".lua") else "#"
            for line in read(rel).split("\n"):
                code = line.split(comment, 1)[0]
                if not code.strip():
                    continue
                for m in literal.finditer(code):
                    path = m.group(1).rsplit(":", 1)[-1]  # "v0.2.0:CHANGELOG.md" names CHANGELOG.md
                    if path in tracked:
                        named.add(path)
        self.assertTrue(
            {"README.md", "CHANGELOG.md", "docs/publishing/README.md", "src/Hekili/Libs/CREDITS.md"} <= named, named
        )
        docs_only = []
        for path in sorted(named):
            r = subprocess.run(["bash", SCRIPT, "classify", path], cwd=ROOT, capture_output=True, text=True)
            if r.returncode != 1:
                docs_only.append("%s: exit %d %s" % (path, r.returncode, r.stderr))
        self.assertEqual(docs_only, [])

    def test_classify(self):
        for path, code in [
            ("docs/dev/gaps.md", 0),
            ("docs/superpowers/plans/x.md", 0),
            ("DEVELOPMENT.md", 0),
            ("README.md", 1),
            ("CHANGELOG.md", 1),
            ("docs/publishing/README.md", 1),
            ("docs/publishing/x.md", 1),
            ("docs/wiki/Home.md", 1),
            ("docs/wiki/data/expressions.lua", 1),
            ("docs/dev/x.png", 1),
            ("docs", 1),
            ("src/Hekili/Libs/CREDITS.md", 1),
            ("tests/x.md", 1),
            ('"docs/dev/\\303\\251.md"', 1),
        ]:
            r = subprocess.run(["bash", SCRIPT, "classify", path], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(r.returncode, code, path)


if __name__ == "__main__":
    unittest.main()
