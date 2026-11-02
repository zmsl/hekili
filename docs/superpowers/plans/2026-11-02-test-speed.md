# Test Speed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `make check` and `make gate` faster without changing a single test result: a stamped check, a
docs-only skip, split spec files, a cheaper harness boot, collector tuning, and two busted flags tried on their merits.

**Architecture:** The skips live in one bash script (`scripts/check_stamp.sh`) that `make check` consults and
`make check-full` (which `make gate` now depends on) never consults. Every speed change to the test run goes through
`scripts/busted_parallel.sh`'s `run_one` or the test harness, never through shipped code. Every task is measured on its
own against the Task 1 baseline and kept only if its results are identical and it gains time.

**Tech Stack:** GNU make, bash, Lua 5.1 with busted 2.3.0 (`.lua/`), Python 3 unittest (`make tools-test`), git.

**Spec:** `docs/superpowers/specs/2026-11-02-test-speed-design.md`

## Global Constraints

- Test infrastructure only: nothing shipped changes. No edit under `src/`, no TOC, no `.pkgmeta` (2026-11-03 freeze).
- `make check` may skip (stamp or docs-only), for mid-work runs. `make gate`, `make gate-ab`, `make accuracy`, the rig,
  packaging and anything a merge or tag relies on always run in full: `make gate` runs check with skipping off.
- `make check FULL=1` forces a full run. Every skip prints one line saying it skipped and why.
- A shortcut that can't prove its inputs are unchanged runs in full.
- The stamp lives in the worktree's own git dir, never shared between worktrees, and is written only after a clean exit
  of every check part; a killed or failing run leaves no stamp.
- CHANGELOG.md, README.md and docs/publishing/ are never "docs only"; neither is code, TOC, XML, config, fixtures or
  anything under tests/, tools/, scripts/, src/ or .github/.
- Splits change no test's behaviour, seeds, names or assertions.
- Collector settings never reach a test that measures bytes or counts unless its bytes are shown identical.
- Every gate result line and agreement line identical to base; `~/src/hekili-rig/run.sh` output identical; no floor moves.
- Gate lock: `make gate`, `make gate-ab`, `make accuracy` and `~/src/hekili-rig/run.sh` take `/tmp/hekili-gate.lock`
  themselves; never wrap them. Every other busted run (including `make check`, `make test*`, single files) runs under
  `flock /tmp/hekili-gate.lock`. A timing batch holds the lock for the whole batch. A gate can't run inside an outer
  hold (it would wait on itself): before each gate or rig timing, `pgrep -c busted` must print 0, and the step records
  `uptime`'s load average with the time.
- Kill by PID only, never `pkill -f`.
- Lua 5.1 for test code; bash and the existing tools for the rest. `make check` before every commit.
- Commit trailer on every commit, exactly: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Results file: `docs/superpowers/plans/2026-11-02-test-speed-results.md`. Raw logs: `~/src/hekili-speed-runs/<task>/`.
  Results are always diffed against Task 1's base; a task's gain is measured against the previous task's kept state.
  A gain smaller than Task 1's run-to-run spread (gate1 vs gate2, check1 vs check2) counts as none.

## Review Focus

- A file edited while a check runs: the check tested mixed inputs, so it must leave no stamp (Task 2,
  `test_change_during_run_writes_no_stamp`).
- Staging or unstaging alone (content unchanged): `packs-check` and `api-check` use `git diff --exit-code`, which reads
  the index, so the result can differ; it must not skip (Task 2, `test_staging_only_runs`).
- A deleted or renamed tracked file, or an exec bit flip: must not skip (Task 2, `test_deleted_file_runs`,
  `test_exec_bit_runs`).
- A green check in one worktree must not skip a sibling worktree on the same commit (Task 2,
  `test_stamp_is_per_worktree`).
- A check interrupted between its start and its end (Ctrl-C, OOM, usage limit) must leave nothing that later lets a run
  skip (Task 2, `test_abandoned_begin_leaves_no_stamp`).

---

## File Structure

- Create `scripts/check_stamp.sh`: the manifest, the stamp and the docs-only classifier (Tasks 2-3).
- Create `scripts/results.sh`: a log's result lines with run-to-run noise stripped, sorted (Task 1).
- Create `tests/tools/test_check_stamp.py`: the false-green tests (Tasks 2-3).
- Modify `Makefile`: `check` (consults the stamp), new `check-full`, `gate: check-full` (Task 2); header comment (Task 9).
- Modify `scripts/busted_parallel.sh` `run_one`: collector helper (Task 6), flags (Tasks 7-8), if kept.
- Create `tests/helpers/gc.lua` (Task 6, if kept).
- Split files (Task 4): `tests/Forever/helpers/druid_harness_gates.lua`, `tests/Forever/druid_harness_gates_a_spec.lua`,
  `tests/Forever/druid_harness_gates_b_spec.lua`, `tests/Forever/loop_shaman_enhancement_spec.lua`,
  `tests/Forever/loop_shaman_elemental_spec.lua`, `tests/Forever/loop_warrior_party_spec.lua`,
  `tests/Game/harness/detect_more_cells.lua`, `tests/Game/harness/detect_more_b_spec.lua`.
- Modify `tests/Game/harness/headless.lua` `loadLua`/`loadXml` (Task 5, if kept).
- Modify `DEVELOPMENT.md` (Task 9).

---

### Task 1: Baseline timings and the results extractor

**Files:**
- Create: `scripts/results.sh`
- Create: `docs/superpowers/plans/2026-11-02-test-speed-results.md`

**Interfaces:**
- Produces: `scripts/results.sh LOG...` → stdout, sorted: every line of the logs except make's own lines (`^make`,
  `make\[`), the runner's `== <file>` headers, busted progress lines (only `●◼✱⊝` characters) and busted's per-file
  summary lines (` : [0-9.]+ seconds$`); kept lines have `; cpu mean [^;]*per Update` removed (the rig's own strip).
  The runner's `all files:` total stays. Exit 0.
- Produces: `~/src/hekili-speed-runs/base/{check1,check2,gate1,gate2}.log`, `base.results` (gate), `base-check.results`,
  `its.tsv` (per-`it` seconds for split candidates), rig output `/tmp/border-out/speed-base.txt` copied to
  `~/src/hekili-speed-runs/base/rig.txt`.

- [ ] **Step 1: Bootstrap the worktree** — `cd /home/zack/src/hekili-wt-speed && make bootstrap`; expect `.lua/bin/busted` to exist.
- [ ] **Step 2: Write `scripts/results.sh`** per the Interfaces block (`set -euo pipefail`, grep -v/sed/sort; `chmod +x`).
- [ ] **Step 3: Time two full checks in one lock hold**

```bash
mkdir -p ~/src/hekili-speed-runs/base && cd /home/zack/src/hekili-wt-speed
flock /tmp/hekili-gate.lock bash -c 'for i in 1 2; do uptime; /usr/bin/time -f "wall %e" make check >~/src/hekili-speed-runs/base/check$i.log 2>&1; tail -1 ~/src/hekili-speed-runs/base/check$i.log; done'
```
Expected: both green (`all files:` line, 0 failures), two `wall` lines.

- [ ] **Step 4: Time two gates, unwrapped, back to back** — before each: `pgrep -c busted` prints 0; then
  `uptime; /usr/bin/time -f "wall %e" make gate >~/src/hekili-speed-runs/base/gate$i.log 2>&1` for i in 1 2. Expected: green.
- [ ] **Step 5: Prove the extractor is noise-free**

Run: `diff <(scripts/results.sh ~/src/hekili-speed-runs/base/gate1.log) <(scripts/results.sh ~/src/hekili-speed-runs/base/gate2.log)` and the same for check1/check2.
Expected: no output. If a field differs (a timing, a calibration), add its strip to `results.sh`, name it in the
results file, rerun the diff until empty. Then save `results.sh gate1.log > base.results` and `results.sh check1.log > base-check.results`.

- [ ] **Step 6: Run the rig on the base tree** — `pgrep -c busted` prints 0; `ls /tmp/border-cmp/cmp_spec.lua` (if missing:
  `mkdir -p /tmp/border-cmp && cp ~/src/hekili-rig/*.lua /tmp/border-cmp/`); `~/src/hekili-rig/run.sh /home/zack/src/hekili-wt-speed speed-base`; copy `/tmp/border-out/speed-base.txt` to `base/rig.txt`.
- [ ] **Step 7: Time each `it` of the split candidates in one lock hold** — for each candidate and each `it` name, run
  `/usr/bin/time -f %e .lua/bin/busted --tags=<tag> --filter='<exact it name>' <file>` and append `file<TAB>tag<TAB>it<TAB>seconds`
  to `its.tsv`. Candidates: `tests/Forever/druid_harness_spec.lua` (#druid: bear, cat, regenAfter, reload, shift, furor,
  decay), `tests/Forever/loop_shaman_spec.lua` (#shaman: Enhancement, Elemental), `tests/Forever/loop_warrior_spec.lua`
  (#loop and #party), `tests/Game/harness/detect_more_spec.lua` (#slow, one row per kind, `--filter='^<kind> in '`, plus K16, K17).
- [ ] **Step 8: Write the results file** — header (base commit `git rev-parse --short HEAD`, nproc 16, MemTotal, the
  extractor's strips), a "Baseline" table (check wall ×2, gate wall ×2, gate CPU sum = sum of the per-file seconds, the
  top 10 files per tier with seconds, sum/jobs per tier: gate jobs 14, check jobs 16), the `its.tsv` table, and an empty
  "Per task" table with columns `task | metric | before | after | results identical | rig identical | kept`.
  Note in it: the gate is CPU-bound (2026-11-01: sum 8962 s / 14 = 640 s, above its slowest file, 479 s), so for the
  gate only CPU cuts (Tasks 5-8) can pay; the check is bound by `detect_more_spec.lua` (265 s vs 3931 s / 16 = 246 s).
- [ ] **Step 9: `make check`, then commit** — `git add scripts/results.sh docs/superpowers/plans/2026-11-02-test-speed-results.md && git commit -m "test: speed baseline and the results extractor"` with the trailer.

---

### Task 2: The stamped check

**Files:**
- Create: `scripts/check_stamp.sh`
- Modify: `Makefile` (`check`, new `check-full`, `gate`, `.PHONY`)
- Test: `tests/tools/test_check_stamp.py`

**Interfaces:**
- Produces: `scripts/check_stamp.sh manifest` → stdout, the inputs, one per line, sorted:
  - `I <mode> <blob> <stage>\t<path>`: the real index (`git ls-files -s`);
  - `W <mode> <blob>\t<path>`: the working tree, from a throwaway index (`cp "$(git rev-parse --git-path index)"` to a
    mktemp file, `GIT_INDEX_FILE=<tmp> git add -A`, `git ls-files -s`; covers unstaged edits, deletions, exec bits and
    untracked files git doesn't ignore);
  - `T <name> <value>`: toolchain: `md5sum` of every file under `.lua/bin/`, `ls .lua/lib/luarocks/rocks-5.1/*/`
    (rock versions), `stylua --version`, `lua-language-server --version`, `python3 -V` (`missing` when a tool is
    absent), and an md5 of `find <dir> -type f -printf '%P %s %T@\n' | sort` for each `workspace.library` directory in
    `.luarc.json` (when present);
  - `E <NAME>=<value>` or `E <NAME> unset`, for each name in the script's one `ENV_VARS="..."` line:
    `HEKILI_AB DETECT_WRITE HEKILI_LOOP_HOLD HEKILI_LOOP_STEADY ARMS_RECS ENUS_GOLDEN TIMING STYLE_OPTIONS CLASSIC_DRAW
    TIMELINE_DRAW PACK_DATE WOWSIMS WOWSIMS_CLI WOWDB HOME BUSTED BUSTED_JOBS LUA_INIT LUA_PATH LUA_CPATH`.
- Produces: `scripts/check_stamp.sh begin START` → writes the manifest to START.
- Produces: `scripts/check_stamp.sh write START` → if `manifest` now equals START's content, moves it to the stamp,
  else prints `check: inputs changed during the run; no stamp` and leaves none; removes START; exit 0.
- Produces: `scripts/check_stamp.sh test` → exit 0 after printing exactly one line
  `check: skipped, inputs unchanged since the last green check; FULL=1 runs it` when the stamp equals `manifest`;
  else exit 1, printing nothing.
- Stamp path: `$(git rev-parse --absolute-git-dir)/hekili-check-stamp` (in a linked worktree, that is its own
  `.git/worktrees/<name>/`).
- Makefile:
  ```make
  STAMP_START := $(shell mktemp -u /tmp/hekili-check-start.XXXXXX)
  check:
  	@if [ -z "$(FULL)" ] && scripts/check_stamp.sh test; then :; else $(MAKE) check-full; fi
  check-full:
  	@scripts/check_stamp.sh begin $(STAMP_START)
  	$(MAKE) -j4 -Otarget lint fmt-check typecheck test
  	$(MAKE) syntax api-check packs-check tools-test
  	@scripts/check_stamp.sh write $(STAMP_START)
  gate: check-full
  ```
  The `begin` and `write` lines hold no `$(MAKE)`, so `make -n` never runs them (a line with `$(MAKE)` runs even under
  `-n`; a stamp written by a dry run would be a false green). make stops at the first failing line, so `write` runs only
  after both stages pass. shortcut: a failed or killed run leaves its start manifest in /tmp; harmless, `write` is the
  only reader.

- [ ] **Step 1: Write the failing tests** in `tests/tools/test_check_stamp.py`. A `setUp` builds a temp git repo:
  `src/Hekili/a.lua`, `src/Hekili/Hekili.toc`, `tests/x_spec.lua`, `README.md`, `CHANGELOG.md`,
  `docs/publishing/README.md`, `docs/dev/notes.md`, `DEVELOPMENT.md`, `.gitignore` (`.lua/` and `.ab/`),
  `.lua/bin/busted` (text `v1`), and a copy of `scripts/check_stamp.sh`; one commit. Helpers: `stamp()` runs `begin <tmp>`
  then `write <tmp>`; `skips(env=None)` returns `test`'s exit code == 0 (the env starts from `os.environ` with every
  `ENV_VARS` name removed, then `env` applied). Each test below stamps first, then mutates, then asserts:
  - `test_fresh_repo_runs`: no stamp → `skips()` is False.
  - `test_unchanged_skips_with_one_line`: `skips()` True; stdout is exactly one line starting `check: skipped,`.
  - `test_lua_edit_runs`, `test_toc_edit_runs`, `test_test_file_edit_runs`: append a line to `a.lua` / the TOC / `x_spec.lua` → False.
  - `test_untracked_file_runs`: create `src/Hekili/b.lua` → False. `test_ignored_file_skips`: create `.ab/x.tsv` → True.
  - `test_deleted_file_runs`: delete `a.lua` → False. `test_exec_bit_runs`: `chmod +x a.lua` → False.
  - `test_staging_only_runs`: edit `a.lua`, stamp, `git add a.lua` (content unchanged) → False.
  - `test_env_var_runs`: `skips({"DETECT_WRITE": "1"})` → False; and `skips({"DETECT_WRITE": ""})` → False (set-empty ≠ unset).
  - `test_toolchain_runs`: rewrite `.lua/bin/busted` to `v2` → False.
  - `test_change_during_run_writes_no_stamp`: in a fresh repo, `begin`, edit `a.lua`, `write` → stdout contains `no stamp`; `skips()` False.
  - `test_abandoned_begin_leaves_no_stamp`: in a fresh repo, `begin` with no `write` → `skips()` False.
  - `test_stamp_is_per_worktree`: `git worktree add ../wt`; stamp the main tree; `test` run in `../wt` → exit 1.
  - `test_env_list_covers_every_getenv`: in the real repo, every `NAME` matched by `os.getenv("NAME")`,
    `os.environ.get("NAME"` or `os.environ["NAME"]` under `tests/`, `tools/`, `scripts/` (`*.lua`, `*.py`, `*.sh`)
    is in the script's `ENV_VARS` line, except `ANTHROPIC_API_KEY` and `CF_API_KEY` (release-only tools, mocked in their tests).
  - `test_gate_never_consults_the_stamp`: read the real `Makefile` (never `make -n`: it would run `$(MAKE)` lines):
    the `gate:` rule's prerequisites are exactly `check-full`, and the `check-full:` recipe does not contain
    `check_stamp.sh test`.
- [ ] **Step 2: Run them to see them fail** — `flock /tmp/hekili-gate.lock python3 -m unittest discover -s tests/tools -t tests/tools -p 'test_check_stamp.py' -v`; expected: errors (no script).
- [ ] **Step 3: Write `scripts/check_stamp.sh`** per the Interfaces (`set -euo pipefail`; `cd "$(git rev-parse --show-toplevel)"`; `chmod +x`).
- [ ] **Step 4: Change the Makefile** per the Interfaces; add `check-full` to `.PHONY`.
- [ ] **Step 5: Run the tests** (Step 2's command); expected: all pass.
- [ ] **Step 6: Prove it on the real tree** — under one lock hold: `make check FULL=1` (green, writes
  `$(git rev-parse --absolute-git-dir)/hekili-check-stamp`); `/usr/bin/time -f "wall %e" make check` prints the skip
  line; `make check FULL=1` again prints no skip line and runs the stages; `DETECT_WRITE=0 make check` starts the
  stages (stop it by PID once `lint` starts; no source edit, nothing under `src/` is touched); a plain `make check`
  still skips (the stamp is the last green one and the inputs match it).
- [ ] **Step 7: Record** in the results file: skipped check wall vs Task 1's full check wall; `results.sh` of the
  FULL=1 log diffed against `base-check.results` (expected: no output).
- [ ] **Step 8: Commit** — `git add scripts/check_stamp.sh Makefile tests/tools/test_check_stamp.py docs/superpowers/plans/2026-11-02-test-speed-results.md && git commit -m "test: make check skips when its inputs match the last green run"` with the trailer.

---

### Task 3: The docs-only skip

**Files:**
- Modify: `scripts/check_stamp.sh`
- Test: `tests/tools/test_check_stamp.py`

**Interfaces:**
- Consumes: Task 2's `manifest`, stamp path and `test`.
- Produces: `scripts/check_stamp.sh classify PATH` → exit 0 when PATH is docs only: it matches `docs/*` but not
  `docs/publishing/*`, or it is a root-level `*.md` other than `README.md` and `CHANGELOG.md`; else exit 1.
- Produces: `test` also exits 0 when the stamp's `T` and `E` lines equal the manifest's and every path in an `I` or `W`
  line present on one side only (added, removed or changed) classifies docs only; it prints exactly one line
  `check: skipped, only docs no test reads changed since the last green check: <first path> (+N more); FULL=1 runs it`
  (`(+N more)` only when N > 0). The stamp is not rewritten by a skip.

- [ ] **Step 1: Write the failing tests** (Task 2's fixture):
  - `test_unread_doc_edit_skips`: edit `docs/dev/notes.md` and `DEVELOPMENT.md` → True; the line names `DEVELOPMENT.md (+1 more)`.
  - `test_new_and_deleted_unread_docs_skip`: add `docs/dev/new.md`, delete `docs/dev/notes.md` → True.
  - `test_read_docs_run`: each of `README.md`, `CHANGELOG.md`, `docs/publishing/README.md` edited alone → False.
  - `test_docs_in_code_dirs_run`: each of `tests/notes.md`, `tools/notes.md`, `src/Hekili/Libs/CREDITS.md` added alone → False.
  - `test_doc_and_code_runs`: edit `docs/dev/notes.md` and `a.lua` → False.
  - `test_doc_and_env_runs`: edit `docs/dev/notes.md`, `skips({"TIMING": "record"})` → False.
  - `test_docs_read_by_tests_are_never_docs_only`: in the real repo, for every string literal matching
    `["']([^"' ]*\.md|docs/[^"' ]*)["']` in `tests/`, `tools/`, `scripts/` (`*.lua` with trailing `--...` stripped,
    `*.py` and `*.sh` with trailing `#...` stripped, comment-only lines skipped) that names a tracked file,
    `classify` exits 1. (Today: `README.md`, `CHANGELOG.md`, `docs/publishing/README.md`, `src/Hekili/Libs/CREDITS.md`.)
- [ ] **Step 2: Run them to see the docs-only ones fail** (Task 2 Step 2's command).
- [ ] **Step 3: Implement `classify` and the docs-only branch of `test`** (`comm -3` of the stamp's and the manifest's `I`/`W` lines gives the changed paths).
- [ ] **Step 4: Run the tests** — expected: all pass, Task 2's included.
- [ ] **Step 5: Prove it on the real tree** — under one lock hold: `make check FULL=1`; append a line to
  `docs/dev/gaps.md`; `/usr/bin/time -f "wall %e" make check` prints the docs-only line; `git checkout docs/dev/gaps.md`;
  append to `README.md`; `make check` runs in full (stop by PID after the first busted line); `git checkout README.md`.
- [ ] **Step 6: Record** the docs-only check wall in the results file.
- [ ] **Step 7: `make check FULL=1`, commit** — `git commit -m "test: make check skips a change to docs no test reads"` with the trailer.

---

### Task 4: Split the longest files

**Files:**
- Create: `tests/Forever/helpers/druid_harness_gates.lua`, `tests/Forever/druid_harness_gates_a_spec.lua`,
  `tests/Forever/druid_harness_gates_b_spec.lua`, `tests/Forever/loop_shaman_enhancement_spec.lua`,
  `tests/Forever/loop_shaman_elemental_spec.lua`, `tests/Forever/loop_warrior_party_spec.lua`,
  `tests/Game/harness/detect_more_cells.lua`, `tests/Game/harness/detect_more_b_spec.lua`
- Modify: `tests/Forever/druid_harness_spec.lua`, `tests/Forever/loop_shaman_spec.lua`,
  `tests/Forever/loop_warrior_spec.lua`, `tests/Game/harness/detect_more_spec.lua`

**Interfaces:**
- Consumes: `its.tsv` and `scripts/results.sh` (Task 1).
- Produces: `require("Forever.helpers.druid_harness_gates")` → `{ GATES = <the file's GATES table, unchanged> }` plus
  whatever local the remaining `druid_harness_spec.lua` describes use, moved verbatim. `druid_harness_spec.lua` keeps
  the usability and `#slow` describes; the `#druid` describe's seven names go to `_a` and `_b` (same describe string,
  same `it` names, `GATES[name](1)`), split into two groups of near-equal summed `its.tsv` seconds.
- Produces: `require("Game.harness.detect_more_cells").run(kind, band)` → the current `it` body of the kind×band loop,
  moved verbatim. `detect_more_spec.lua` keeps the kinds list's first part, `detect_more_b_spec.lua` the rest plus
  K16/K17, chosen so the two files' summed seconds are near equal; both keep the describe string `detection suite K10-K19 #slow`.
- The Shaman and the Warrior party files follow `tests/Forever/loop_druid_feral_spec.lua`'s pattern: a header comment
  naming where they were split from, the describe moved verbatim (one pack each for Shaman: the loop becomes its body
  with `name` fixed).
- A file stays whole when it has one `it` (the single 20-fight gates: Feral, Protection, the Warlock packs, Shadow,
  Fury, alts_seed3): splitting it would change its assertions. Record each such file and its time.

- [ ] **Step 1: Record the test names before** — `flock /tmp/hekili-gate.lock .lua/bin/busted --list --tags=loop,party,druid,rogue,paladin,shaman,hunter,mage,priest,warlock 2>&1 | sed 's/^[^:]*:[0-9]*: //' | sort >~/src/hekili-speed-runs/split/names-gate.before`, and the same with `--exclude-tags=party,loop,druid,rogue,paladin,shaman,hunter,mage,priest,warlock,bench` into `names-check.before`. (busted `--list` prints `file:line: name`; the sed drops the location, which moves.)
- [ ] **Step 2: Do the four splits** per the Interfaces. Move code; change no line inside a moved body.
- [ ] **Step 3: Same names after** — rerun Step 1 into `.after`; `diff` each pair. Expected: no output.
- [ ] **Step 4: Results identical** — under one lock hold, `/usr/bin/time -f "wall %e" make check FULL=1 >check.log`;
  then (unwrapped, quiet) `/usr/bin/time -f "wall %e" make gate >gate.log`. `diff <(scripts/results.sh check.log) base-check.results` and
  the gate against `base.results`. Expected: no output for both (the `all files:` totals included).
- [ ] **Step 5: Record** check wall, gate wall and the new top-5 files per tier. Keep a split only if its tier's wall
  dropped; revert a split that gained nothing and say so in the results file.
- [ ] **Step 6: Commit** — `git commit -m "test: split the longest spec files so the parallel runner can share them"` with the trailer.

---

### Task 5: Boot and harness profile

**Files:**
- Modify: `tests/Game/harness/headless.lua` (`loadLua`, `loadXml` inside `M.new`)
- Test: `tests/Game/harness/headless_spec.lua`

**Interfaces:**
- Produces (only if Step 2 shows boot ≥ 5% of a heavy file's CPU): a module-level `local CHUNKS = {}` in
  `headless.lua`: `loadLua` uses `CHUNKS[path]` or `loadfile(path)` (a load error is never cached and still lands in
  `H.loadErrors`), then `setfenv(f, env)` per boot as today; `loadXml` caches the comment-stripped body per path the
  same way (a missing file still records `path .. ": missing"`). Lua 5.1 closures take the env of the function that
  creates them, so each boot's functions keep that boot's env.

- [ ] **Step 1: Profile** — a scratch helper outside the repo, `~/src/hekili-speed-runs/boot/boot_profile.lua`, wraps
  `require("Game.harness.headless").new` with `os.clock()` accounting and prints `boot <calls> <seconds>` at exit
  (`busted.subscribe({ "exit" }, ...)`). Under one lock hold, run `.lua/bin/busted --helper=<that file> --tags=<tag> <file>`
  for `tests/Forever/loop_warrior_fury_spec.lua` (#loop), `tests/Forever/loop_warlock_demonology_spec.lua` (#warlock),
  `tests/Forever/druid_harness_spec.lua` (#druid) and `tests/Game/harness/detect_more_spec.lua` (#slow). Record calls,
  boot seconds and the file's total in the results file.
- [ ] **Step 2: Decide** — boot < 5% of total in every profiled file: record "dropped: boot is N%" and skip to Step 7's
  commit of the results file alone.
- [ ] **Step 3: Write the failing test** in `headless_spec.lua`: `it("two boots in one process keep their own state and envs", ...)`:
  `H1 = headless.new()`, `H2 = headless.new()`; `assert.are_not.equal(H1.Hekili, H2.Hekili)`; for every function value
  `fn` in `H2.Hekili` (`pairs`), `assert.are.equal(H2.env, getfenv(fn))`, and the same for H1 with `H1.env`;
  `assert.are.same({}, H2.loadErrors)`. (It passes today; it pins the cache's safety. The red step is the profile.)
- [ ] **Step 4: Implement the cache** per the Interfaces.
- [ ] **Step 5: Run** `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Game/harness/headless_spec.lua`; expected: pass.
  Rerun Step 1's profile; record the new boot seconds.
- [ ] **Step 6: Results identical** — Task 4 Step 4's check and gate runs and diffs (no output), then the rig (quiet):
  `~/src/hekili-rig/run.sh /home/zack/src/hekili-wt-speed speed-boot` and
  `diff /tmp/border-out/speed-boot.txt ~/src/hekili-speed-runs/base/rig.txt` → no output. Any difference: revert, record why.
- [ ] **Step 7: Record and commit** — gate CPU sum and walls before/after; `git commit -m "test: the headless harness compiles each addon file once per process"` (or `"docs: boot profile, no cut"`) with the trailer.

---

### Task 6: Collector tuning

**Files:**
- Create: `tests/helpers/gc.lua`
- Modify: `scripts/busted_parallel.sh` (`run_one`)

**Interfaces:**
- Produces: `tests/helpers/gc.lua`: `collectgarbage("setpause", PAUSE)` and `collectgarbage("setstepmul", STEPMUL)`,
  the two constants set from Step 2's winner.
- Produces: `run_one` adds `--helper=tests/helpers/gc.lua` unless `grep -qE 'collectgarbage|helpers[./]alloc' "$f"`
  (the files that measure bytes or counts directly run with the stock collector). The loop gates' `bytes N per Update`
  is counted with the collector stopped (`tests/Game/harness/loop.lua`), so they take the helper only if Step 4 shows
  every `bytes` field identical.

- [ ] **Step 1: Write the helper and the `run_one` change** with `PAUSE`/`STEPMUL` read from `HEKILI_GC_PAUSE`/`HEKILI_GC_STEPMUL` for this task's trials only.
- [ ] **Step 2: Trial** — under one lock hold, `make test-warlock` and `make test-druid` (the heaviest tags) with
  (pause, stepmul) = (200, 200) stock, (400, 200), (1000, 200), (400, 400): record each run's CPU sum and the peak RSS
  of `tests/Forever/druid_harness_spec.lua` alone (`/usr/bin/time -f %M .lua/bin/busted --helper=tests/helpers/gc.lua --tags=druid <file>`).
  The winner is the lowest CPU sum whose peak RSS × 14 stays under 12 GB (half of MemTotal). No gain over stock: revert, record, commit the results file only.
- [ ] **Step 3: Pin the winner** as constants in `gc.lua`; drop the env reads.
- [ ] **Step 4: Results and bytes identical** — Task 4 Step 4's check and gate runs and diffs (no output); then
  `diff <(grep -ohE '^[^;]+ solo: fights=[0-9]+|bytes [0-9.]+ per Update' base/gate1.log) <(... gate.log)` → no output.
  A bytes difference: exempt the loop gates (`run_one` also skips the helper for `tests/Forever/loop_*_spec.lua`), rerun Step 2's best for the gain that remains, record it.
- [ ] **Step 5: `make check FULL=1`, record, commit** — `git commit -m "test: a lazier collector for test processes that measure no bytes"` with the trailer.

---

### Task 7: Try `--no-auto-insulate`

**Files:**
- Modify: `scripts/busted_parallel.sh` (`run_one`'s busted line)

**Interfaces:**
- Produces (if kept): `run_one` runs `"$BUSTED" --no-auto-insulate "$@" "$f"`. The runner gives each file its own
  process, so insulation guards nothing across files there; `make test-serial` and `make test-fast` keep insulation.

- [ ] **Step 1: Leak baseline** — a scratch helper `~/src/hekili-speed-runs/insulate/leaks.lua` subscribes to
  `{ "file", "start" }` and `{ "file", "end" }`, snapshots the keys of `_G` and `package.loaded` at start and prints
  `leak <file> <kind> <name>` for each key new at end. Under the lock:
  `.lua/bin/busted --helper=<it> --exclude-tags=party,loop,druid,rogue,paladin,shaman,hunter,mage,priest,warlock,bench >leaks.base`
  (the `.busted` roots in one process, stock insulation), and the same with `--tags=loop,party,druid,rogue,paladin,shaman,hunter,mage,priest,warlock` into `leaks-gate.base`.
- [ ] **Step 2: Add the flag**; under the lock run both Step 1 runs again with `--no-auto-insulate` into `leaks.flag`
  and `leaks-gate.flag`. Expected: neither diff against its `.base` shows a new name. A new name: drop the flag, record the name.
- [ ] **Step 3: Results identical and timed** — Task 4 Step 4's runs and diffs (no output). Record check and gate
  wall and CPU sum. No gain beyond Task 1's run-to-run spread (gate1 vs gate2): revert, record "dropped: no gain".
- [ ] **Step 4: Commit** — kept: `git commit -m "test: the parallel runner skips busted's per-file insulation"`; dropped: commit the results file alone. Trailer on both.

---

### Task 8: Try `--lazy`

**Files:**
- Modify: `scripts/busted_parallel.sh` (`run_one`'s busted line)

**Interfaces:**
- Produces (if kept): `run_one` adds `--lazy` (`setup`/`teardown` become lazy: a block whose tests are all filtered out
  by tags never runs its `setup`). 23 spec files use `setup(`, one `teardown(`.

- [ ] **Step 1: Leaks** — Task 7 Step 1 and 2 with `--lazy` (plus Task 7's flag if kept) into `leaks.lazy`; no new name, or drop.
- [ ] **Step 2: Names identical** — Task 4 Step 1's `--list` runs with `--lazy` against the `.after` files: no output.
- [ ] **Step 3: Results identical and timed** — as Task 7 Step 3.
- [ ] **Step 4: Commit** — kept: `git commit -m "test: the parallel runner uses lazy setup"`; dropped: the results file alone. Trailer on both.

---

### Task 9: Docs and the final verification

**Files:**
- Modify: `DEVELOPMENT.md` ("What the full check covers" and "Review and merge")
- Modify: `Makefile` (the comment above `check` and `gate`)
- Modify: `docs/superpowers/plans/2026-11-02-test-speed-results.md`

- [ ] **Step 1: DEVELOPMENT.md** — under "What the full check covers": `make check` skips when its inputs match the
  last green check in this worktree (tracked and untracked files, the index, the toolchain, the env vars tests read),
  or when only docs no test reads changed (not README.md, CHANGELOG.md, docs/publishing/ or any doc under src/, tests/,
  tools/); each skip prints one line; `make check FULL=1` runs it all. Under "Review and merge" item 2: `make gate`
  never skips (it runs `make check-full`); neither do `gate-ab`, `accuracy`, the rig or packaging. Name any kept
  runner change (collector, flags) in one line each.
- [ ] **Step 2: Makefile comments** for `check`, `check-full` and `gate` in the file's existing one-comment-per-target style.
- [ ] **Step 3: Final verification** — under the lock, `make check FULL=1` (green); quiet, `make gate` (green);
  results diffs against `base.results` and `base-check.results` (no output); the rig (`speed-final`) diffed against
  `base/rig.txt` (no output). Then `make check` prints the skip line.
- [ ] **Step 4: Results summary** — a closing table: each part, kept or dropped, gain on check wall and gate wall
  against Task 1, and the reason for each drop.
- [ ] **Step 5: Commit** — `git commit -m "docs: the check's skips, FULL=1 and the gate rule"` with the trailer.
