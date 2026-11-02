# Test speed: design (2026-11-02)

Owner: "plan for the community norm that matches hekili and hand roll it if you have to. docs only skip yes, split
longest files yes, boot harness yes, collector tuning yes, the others yes" (the others: the tree-hash stamp,
`--no-auto-insulate`, `--lazy`).

## Why

A full `make gate` is 197 spec files, about 9,000 CPU-seconds, 14 at a time on this 16-core machine: roughly 11 minutes
of wall time, bounded below by the slowest files (479 s and 402 s in the 2026-11-01 gate logs). One run at a time holds
`/tmp/hekili-gate.lock`, so agents queue. `make gate` runs `make check` first, so an agent that just ran check pays for
it twice, and docs-only commits pay for a full check.

## The norm (binding)

Build systems with cached tests (Bazel, Gradle, Nx, Turborepo) and CI path filters (GitHub Actions `paths-ignore`)
share one rule: shortcuts are for development runs; the merge and release gate always runs everything, uncached. Here:

- `make check` may skip (stamp or docs-only), for mid-work runs.
- `make gate`, `make gate-ab`, `make accuracy`, the rig, packaging and anything a merge or tag relies on always run in
  full: `make gate` runs check with skipping off.
- `make check FULL=1` forces a full run. Every skip prints one line saying it skipped and why.
- A shortcut that can't prove its inputs are unchanged runs in full. A false green is the failure this design exists to
  prevent; a redundant run is merely slow.

## Parts

1. **Stamp (cached check).** After a fully green `make check`, write a key of every input: the tracked files' content
   (staged and unstaged), untracked files git doesn't ignore, the `.lua` toolchain (busted, luacheck, stylua and the Lua
   build, by version or hash), and the environment variables tests read (find them with a grep of `os.getenv` under
   tests/ and tools/; e.g. HEKILI_AB, ENUS_GOLDEN, DETECT_WRITE, TEST_EXCLUDE, GATE_TAGS). A rerun with the same key
   skips. The stamp lives in the worktree's own git dir, never shared between worktrees, and is written only after a
   clean exit of every check part; a killed or failing run leaves no stamp.
2. **Docs-only skip.** When every change since the last stamp is a doc that no test or tool reads, check skips. The
   set of docs tests read is found, not guessed (at least CHANGELOG.md and README.md: tests/Forever/publication_spec.lua,
   tests/tools/test_release_notes.py); those are never "docs only". Code, TOC, XML, config, fixtures and anything
   under tests/ or tools/ is never docs only.
3. **Split the longest files.** Break the slowest spec files so the parallel runner can share them, without changing
   any test's behaviour, seeds or assertions. Aim: no file far above sum/jobs. Gate results must stay identical.
4. **Boot/harness profile.** Measure what each file spends booting the addon and the harness; cut repeated work only
   where results stay identical (for example sharing a loaded, read-only build within a file).
5. **Collector tuning.** Garbage collector settings for test processes only; never for allocation tests
   (tests that measure bytes or counts must see the same collector as before, or be exempt).
6. **`--no-auto-insulate`, `--lazy`.** Try each; keep only if the whole suite and the gate results stay identical and
   a leak check (a global or package.loaded diff before and after each file) finds nothing new. Otherwise drop it and
   say why.

## Acceptance

- Every gate RESULT and agreement line identical to base (the rig, `~/src/hekili-rig/run.sh`, identical too); no floor
  moves; make check and make gate green.
- Each part measured on its own, before and after, on a quiet machine (wall time of make check, make gate); a part with
  no gain or any result difference is dropped and reported.
- A test proves each skip can't hide a change: an edit to a Lua file, a TOC, a test, a test-read doc, an env var, the
  toolchain, and an untracked file each defeat the stamp; a docs-only edit to an unread doc skips; `make gate` never
  skips.
- DEVELOPMENT.md documents the skips, FULL=1 and the gate rule.

## Constraints

Test infrastructure only: nothing shipped changes (the 2026-11-03 freeze covers player code). The gate lock rules stay as
they are. Kill by PID only. Lua 5.1 for test code; bash and the existing tools for the rest.
