# Audit first wave: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Each cluster is one task,
> one branch, one review with regression analysis. Source: `docs/research/2026-10-17-codebase-audit.md` (the audit;
> item numbers below are its ranked-list numbers). User direction (2026-10-17): work the list in priority order,
> clustering like changes, with extra analysis per change so no regression lands.

**Goal:** land the audit's first-day set and the measured performance items without changing any recommendation.

**Spec:** the audit report. **Gate for every cluster:** `make check` green; `make test-loop`'s `Arms solo:` line
byte-identical to the base (timings aside); `make test-party` and `make test-druid` green; `make bench` numbers
recorded before and after in the task report.

## Global Constraints
- No recommendation may change: the gate line is the proof; Cluster C adds a first-icon sequence comparison.
- Zero allocation in recurring paths; new specs assert it where a cluster claims it.
- Upstream files edited only where the audit names the line; every such edit listed in the commit body.
- Commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Task 1: Cluster A, test and repo infrastructure (items 1, 18, 3, 11, tooling for bench)
- Parallel gates: `make test` runs busted one spec file per process (`xargs -P` or a pattern rule; keep one summary
  line per file and a final pass/fail), `make -j` safe; split `tests/Game/harness/loop_warrior_spec.lua`'s 6-fight
  gate into two 3-fight files that print the same `Arms solo:` line shape (the base line is recorded before the split
  and both halves' lines are recorded as the new baseline in `docs/dev/layout.md`); run the suite twice to prove no
  order dependence. Target: `make check` under 90 s on this machine.
- `make packs-check`: runs `make packs` then `git diff --exit-code src`; added to `check`.
- `make bench`: a `#bench`-tagged spec under `tests/Game/harness/` adapted from the audit's scratch specs
  (`~/.claude/jobs/080a308e/tmp/audit-perf/perf_spec.lua`, `coup_spec.lua`, `alloc_spec.lua`): prints ms per Update
  (mean/p95/max over 6 fights), bytes per Update direct and through the Driver's coroutine path, bytes per
  UNIT_COMBAT; not in `check`; the numbers it prints at base go into the task report as the baseline.
- CI: `.github/workflows/check.yml`: ubuntu-latest, cache `.lua/` keyed on `scripts/bootstrap.sh`, `jdx/mise-action`,
  `make bootstrap`, then lint, fmt-check, test, syntax, api-check, packs-check (typecheck stays local; say why in a
  comment). Verify the YAML with a local parser; it runs on the push.
- Fork identity: `.github/FUNDING.yml` removed; `.github/ISSUE_TEMPLATE/config.yml` links point at
  github.com/zmsl/hekili; `docs/dev/layout.md` gains the `upstream` remote line (`git remote add upstream
  https://github.com/Hekili/hekili.git` with `no_push`) and the one-spec command and `.lua/` sharing note.
- Regression analysis: test count identical before and after (693), both gate lines, `make check` wall time before
  and after, suite run twice.

## Task 2: Cluster B, fork-side allocation (items 2, 7, 8, 20)
- `Engine/Driver.lua`: one engine coroutine reused across refreshes (`while true do Hekili.Update(); yield(DONE) end`),
  recreated after an error or when `Engine/Snapshot.lua` drops it; every `coroutine.status(...) == "dead"` test
  updated. Spec: drive N Updates through the real OnUpdate (the headless frame) and assert 0 B per Update after warm-up.
- `Engine/Sim/Core.lua` PopStack: return non-run entries to the pool (one line); assert 0 B from AddToStack over an
  Update in the same spec.
- Debug strings: the per-entry `Yield(...)` message, the "Recommendations finished" string and `ThreadStatus` built
  only under `ActiveDebug` (keep `scriptID`); the `eventsTriggered` write in `ForceUpdate` removed; `Utils.lua`
  `IsSpellDisabled` caches `false` for a nil tooltip answer.
- Dead code: `Registry.SetBonus`, `I.FALSE_START`, `I.READ_HOLD`, `L.MED0`/`L.SPR0`, `I.Advance`, `I.Ladder`,
  `I.ResolveSpells`, `I.GCD_EDGE` exports, the empty `ns.checkImports` call, `IsDragonflight`/`IsTWW`/`IsMidnight`,
  the dead expansion filter in `list_api_reads.sh`; each deletion justified by a grep in the commit body.
- Regression analysis: gate line, `make bench` before/after (expect bytes per Update via the Driver path to 0 and ms
  within noise), the new 0 B spec, test-druid/party.

## Task 3: Cluster C, upstream performance edits (items 5, 6, 9, 17)
- `State.lua`: per-prediction memo of `state:IsKnown` and `state:IsDisabled` (revive Core.lua's dormant
  `knownCache`/`disabledCache`, wiped at `ResetSpellCaches`), the cooldown metatable reads routed through them;
  `query_time` answered first in `mt_state.__index`.
- `Targets.lua`: `storeDamage`/`storeHealing` become fixed ring buffers summed on read in `damageInLast`/the healing
  equivalent; a spec pins the 1 s / 5 s / 10 s sums against the old implementation on a recorded sequence.
- `UI/UI.lua:1183`: `if alphaCheck then` → the intended `self.alphaCheck <= 0` check (read upstream's intent from the
  surrounding timer code); the lint exemption for `alphaCheck` removed; in-game check: a combat-only display still
  appears at pull and hides after.
- `Engine/Schema/Spec.lua`: the threat table moves to `Engine/Schema/Threat.lua` registered on `all`.
- Regression analysis: gate line; a first-icon sequence test: record `recs[1].actionName` per Update over the 6-fight
  gate at base into a fixture, assert identical after (the audit's seq_none/seq_k technique); `make bench`
  before/after (expect about -10% ms); test-druid, test-party; the ring-buffer spec; `check_engine_reads.sh` clean.

## Deferred to the user
- Items 10 and 12 (packaging, README, LICENSE): need the licence decision and the CurseForge project; a draft
  `.pkgmeta` and README can be prepared on request.
- Items 13-16, 19, 21-23: later waves.
