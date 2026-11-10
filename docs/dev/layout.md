# Repository layout

How the layers and the engine port fit together: `docs/dev/architecture.md`.

- `src/` holds the addons exactly as WoW loads them, each in its own folder with its TOC (paths inside a TOC are
  relative to its folder); nothing else ships, and nothing dev-only goes in them except each class pack's `APLs/` (below), which no TOC lists
  and `.pkgmeta` ignores. `tests/helpers/addons.lua` lists them
  in dependency order, and every headless loader, spec and tool reads their files from it:
  - `src/Hekili/`: the core (the engine, the belief, the UI and options);
  - `src/Hekili_Shared/`: the content every class shares (`Shared/`: auras, consumables, items) and the race packs
    (`Races/`); `## Dependencies: Hekili`, `## LoadOnDemand: 1`, loaded on demand by the core's `Engine/Content.lua`
    at login, first (before the class pack, and for a class with no pack too);
  - `src/Hekili_Warrior/`, `src/Hekili_Druid/`, `src/Hekili_Rogue/`, `src/Hekili_Paladin/`, `src/Hekili_Shaman/`,
    `src/Hekili_Hunter/`, `src/Hekili_Mage/`, `src/Hekili_Priest/`, `src/Hekili_Warlock/`: one class pack each (the
    class file, its RegisterPack blocks written by `make packs`) and `Locales/` (its string table, AceLocale-3.0 app
    `Hekili_<Class>`: `enUS.lua`, generated, and one file per language, listed in its TOC before the class file); `## LoadOnDemand: 1`, loaded at login by the core's
    `Engine/Content.lua` for the player's class.
    The default priorities' sources sit beside the class file in `APLs/`: one `<Pack>.simc` per priority and the
    manifest `packs.lua` (`{ class = "<TOKEN>", packs = { ... }, specs = { [<Pack>] = <spec key> } }`, no date). Edit those, then `make packs`. The date is per
    class and lives only in the class file's first RegisterPack block: `make packs` keeps it while the generated
    blocks are unchanged and sets it to today (`PACK_DATE=YYYYMMDD`, else the system date) when any of that class's
    packs changed, so a clean tree is a no-op and one class's edit re-dates only that class.
    `## Group: Hekili` nests each content addon under Hekili in the in-game addon list.
  - The in-game probe addon (ForeverProbe) lives in its own repo, `~/src/ForeverProbe`, not here; it is linked into the client from there, and `.pkgmeta`, `tools/check_package.sh` and `tests/Forever/publication_spec.lua` still fail if anything named ForeverProbe would ship.

  Content reaches the engine only through the public `Hekili` object (the registration API, `State`, `Class`,
  `Client`, and `Hekili:GetLocale` for its text; `tests/boundary_spec.lua`). Every TOC's `## Version` is `@project-version@`; the packager stamps the release tag into every one (one zip, one version); the core's ContentAPI
  (`CONTENT_API` in `Engine/Content.lua`, matched against each content TOC's `## X-Hekili-ContentAPI`) bumps only when
  the Schema or the content surface changes. The core's modules:
  - root: `Hekili.toc`, `Hekili.lua` (the addon object), `embeds.xml`;
  - `Engine/Sim/`: upstream's simulation (`Core`, `State`, `Scripts`, `Events`, `Targets`, `Constants`, `Utils`);
  - `Engine/Schema/`: the class/race/shared registration API (`Spec`, `Races`, `Shared`, `Threat`), the engine core the
    boundary spec scans. `Spec.lua` is the spec API's head and the files of `Spec/` add to it (load order matters: all
    of `Spec/` is Spec.lua's slot in `Hekili.toc`, and `Spec/All.lua` builds spec 0 at load and copies the mixin then, so
    every file that adds mixin methods loads before it):
    - `Trees.lua`: talent-tree arithmetic, spec ids, migration and share keys (pure);
    - `Selectors.lua`: the active-spec and pack pick: selectors, precedence, `PickSpec` (pure);
    - `Tracked.lua`: the build's def for the belief (`Build(def)`);
    - `Spec.lua`: the mixin table (`ns.SpecMixin`), the small Register* methods (talents, selectors, packs, windows,
      reactions, options, state expressions, hooks, pets, totems, settings), `ns.SCHOOL`, `specTemplate`, `ns.callHook`;
    - `Spec/Regen.lua`: RegisterResource and the sim's generated regen entries;
    - `Spec/Auras.lua`: RegisterAura(s), RegisterPower(s);
    - `Spec/Abilities.lua`: RegisterAbility(ies), missable DoTs;
    - `Spec/Kits.lua`: spec records: `NewClass` (the class kit), `NewSpecialization` (spec 0), `GetSpecialization`;
    - `Spec/All.lua`: spec 0 (`all`): the engine keys core reads by name;
    - `Spec/Packs.lua`: built-in packs into the profile: `DefaultPackage`, `RestoreDefaults`, `RestoreDefault`;
    - `Spec/Activation.lua`: the spec switch: `SpecializationChanged`'s merge, spec choice, the login/zone events;
    - `Races.lua`, `Shared.lua`, `Threat.lua`: race packs, shared content, threat;
  - `UI/`: the display core and editor widgets (`UI`, `Formatting`, `MultilineEditor`, `PopupSlider`), the display
    style registry (`Styles`), the shared "what to show" (`Resolve`), the styles themselves (`Styles/Classic`,
    `Styles/Timeline`) and the Modern layer (`Truth`, the only reader of `Facade.Display`); architecture §7;
  - `Integrations/`: bridges to other addons that subscribe to the engine like the UI does (`WeakAuras`);
  - `Locales/`: the core's string table, AceLocale-3.0 app `Hekili`: `enUS.lua` (generated), one file per language
    (`zhCN`), then `Locales.lua` (`ns.L`); kept in step with the code by `tools/locales.py`; architecture §9;
  - `Options/` (the options panel, chat commands and the styles' shared option builders, `StyleOptions`), `Game/` (the game as the addon knows it: `API/` the facade,
    `Events/`, `State/` the belief, VirtualState), `Libs/` (embedded, untouched; `CREDITS.md` pins each, AceLocale-3.0
    among them) and `Textures/`.

  An upstream merge lands new root files at the root; re-home them by hand.
  The profile port (restructure Task 6) edited ~70 upstream lines in `Engine/` (each `Hekili.DB.profile` read became
  `Hekili.Engine.settings`): merge-friction cost on every upstream merge. Contract: `Engine.Configure(profile)` (called by
  `Options/Profile.lua` at load and on each AceDB profile change) hands the engine the profile's subtables by reference
  and copies its scalars (`enabled`, `screenshot`), so a setter that writes one of those calls it again.
  The audit's first wave (plan `docs/superpowers/plans/2026-10-17-audit-first-wave.md`) edited these upstream files,
  each a merge-friction point:
  - `Engine/Sim/Core.lua`: checkImports removed; PopStack and GetNextPrediction pool stack entries; the Yield and
    ThreadStatus strings are built only under debug; ResetSpellCaches wipes `ns.SpellCaches`.
  - `Engine/Sim/State.lua`: query_time first in mt_state; IsKnown split into computeKnown and a per-id memo (returns
    false, not nil); IsDisabled split into a cached disabledPrefix and a live tail (the reason order changed);
    state.reset wipes the spell caches.
  - `Engine/Sim/Targets.lua`: storeDamage/storeHealing are 128-entry rings; sanitizeDamageAndHealing removed.
  - `Engine/Sim/Utils.lua`: IsSpellDisabled caches a false answer.
  - `Engine/Sim/Events.lua`: the checkImports call removed.
  - `UI/UI.lua:1183`: the per-frame alphaCheck fixed (`self.alphaCheck <= 0`).
  - `Options/Options.lua`: the checkImports call removed; FireToggle, SetAbilityOption, SetItemOption and SetToggle
    wipe the spell caches.
  - `Options/Profile.lua`: the checkImports call removed.
  - `Engine/Schema/Spec.lua`: the threat block moved out to `Engine/Schema/Threat.lua`.
- `tests/` holds the busted specs and their helpers, mirroring the source tree: the specs for
  `src/Hekili/Game/State/` are in `tests/Game/State/`, their helpers in `tests/Game/State/helpers/`, and so
  on. `tests/Game/State/helpers/load.lua` names the addon root once (`ROOT = "src/Hekili/"`).
- `tests/Game/harness/` is the combat harness (combat harness design §3): a seeded model of the Forever client
  (entities, behaviours, the world, the observer, scenarios) that drives VirtualState through the fakes, with the
  attribution gates (`solo_spec`, `group_spec`, `onus_spec`, `sweep_spec`). The world has one position, our yards to
  our target (`W.distance`: the `distance` scenario knob, `W.moveTo`; none by default, every range check in range):
  the observer's `@distance` makes the fake client's `C_Spell.IsSpellInRange` answer against each spell's range (a
  content's `character.ranges`, else 0-5), our white swings stop out of reach (5 yd) and a press with a `range` is
  refused outside it; the wowsims replay starts at the request's `distanceFromTarget` and steps on the log's Movement
  aura stacks. Its `fixtures/` are in-game /vslog dumps,
  every token row kept; `fixtures_spec` replays them and fits the observer's defaults to them. A new capture becomes a
  fixture with `lua5.1 tools/vslog_fixture.lua dump.txt "min,max,min,max" STRIKE=<id> DOT=<id>` (the weapon damage
  UnitDamage read, our strike's and DoT's spell IDs) plus a header comment; a fit outside tolerance is retuned in the
  same change. The Druid scenarios (`tests/Forever/helpers/druid_world.lua`, `druid_vs.lua`, `druid_harness_spec.lua`) run on the same
  harness, the class read from `Druid.lua`: a tenth of their fights is `#slow`, the design's counts are `#druid`, run
  only by `make test-druid` and `make gate`. `make test` runs one busted process per spec file in parallel
  (`scripts/busted_parallel.sh`; `make test-serial` is the one-process run, about 160 s); `make test-fast` skips the
  `#slow` gates. `make bench` (`tests/Forever/bench_spec.lua`, `#bench`, not in `make check`) prints ms per Update and bytes per
  Update and per UNIT_COMBAT for headless Arms over 6 fights. The Task 5 Arms lines cost the stock sim a little: "B per
  Update, direct" went from mean -1, p95 160, max 640 (05f075dd) to 7 / 206 / 640 (238d2e6f), with no rise before Task 5.
- The wowsims tools (`tools/wowsims/apl.lua`, `export.lua`, `tools/check_pack_levels.lua`) and the wowsims gates
  (`tests/Forever/helpers/wowsims.lua`) read one ability set: `tests/Forever/helpers/engine.lua`'s
  `abilitySet(token, race)`, the abilities and auras the engine holds after SpecializationChanged (the class kit's,
  then Hekili_Shared's and the engine's own for missing keys, a race pack's over both), every race's racials when
  `race` is nil. So the translator's keys, off-GCD flags and talent links, the learn table, the leveling check's
  ability keys and the gates' racials all agree with the engine. The replay (`tests/Game/harness/replay.lua`) maps
  the log through the booted instance's own `Hekili.Class`, booted as the request's race (`wowsims.race(spec)`).
- `tools/`, `docs/` and `archive/` stay at the repository root, with the lint, test and type-check configs
  (`.busted`, `.luacheckrc`, `.luarc.json`). Run every tool and `busted` from the root.

## Checks

`make bootstrap` once (Lua 5.1 + busted/luacheck/luacov into `.lua/`; StyLua and LuaLS from `mise.toml`), then
`make check` before every commit. A new worktree has no `.lua/`: copy or symlink `.lua/` from another worktree, or
run `make bootstrap`. One spec: `.lua/bin/busted tests/Game/State/resources_spec.lua`.
StyLua formats only our files (`.styluaignore` lists upstream Hekili, which keeps
its own style). If `fmt-check` still fails after `make fmt`, run `make fmt` again: StyLua 2.5.2 takes two passes on a
call whose argument is a long single-line table.
`tests/boundary_spec.lua` scans `Game/` and `Engine/Schema/` strictly, and holds each `Engine/Sim/` file to its
per-token counts in `tests/boundary_baseline.lua` (a ceiling per file, not a line lock). Regenerate the baseline with
`.lua/bin/lua tools/boundary_baseline.lua` only when removing an inherited leak, or when new content registers a key a
Sim identifier already uses (`git blame` the Sim line and say so in the commit); never to admit a leak.
`make check` also runs `packs-check` (`make packs`, then `git diff --exit-code src`: the RegisterPack blocks match
`src/Hekili_<Class>/APLs/`). CI (`.github/workflows/check.yml`) runs the same checks except the type check.

The shape (central fix 17): `make check` runs lint, fmt-check, typecheck and test at once (`make -j4 -Otarget`, each
check's output kept whole), then syntax, api-check, packs-check and tools-test in order; one exit code. `make test`,
`make test-<tag>` (loop, party, druid, rogue, paladin, shaman, hunter) and `make gate` all go through
`scripts/busted_parallel.sh`: one busted process per spec file, started longest first by the previous run's busted
times for the same arguments (`~/.cache/hekili-busted/`; a file with no time first, so a first run with no cache
gets no ordering gain, and a cache it cannot use, unwritable or no `$HOME`, means path order, never a failed run), each file's output in path order
(files that ran no test skipped), then the summed counts. Path order started `tests/Game/harness/detect_more_spec.lua`
(220 s) about 155 s in: `make test` 361 s before the longest-first start and the slow specs' split
(`alts_spec.lua` one seed a file, the Warlock 3-fight gates one pack a file), 229 s after (2026-10-30, under the lock, the alts spec's two-fight tally included). `make test` and `make test-<tag>` run `$(nproc)` files at a time; `make gate`
runs all seven tags in one call capped at `nproc - 2` for the whole gate (`BUSTED_JOBS`), under the machine-wide
`flock /tmp/hekili-gate.lock`. So each 20-fight pack is its own file (`tests/Forever/loop_<class>_<pack>_spec.lua`;
the class's `loop_<class>_spec.lua` keeps the boot checks and the 3-fight `#slow` gates), and the gate is bounded by
its slowest file: `druid_harness_spec.lua`'s seven `#druid` scenarios (345 s under the gate's load), then
`loop_warrior_spec.lua` (#loop and #party, 292 s) and Feral (303 s); `make gate` 694 s, `make check` 246 s here. One
spec file at one tag: `.lua/bin/busted --tags=druid tests/Forever/loop_druid_feral_spec.lua`.
`make gate-ab` (the gate once per providers arm, provider arms recorded in `.ab/`, never failed) and `make cdv-coverage`
(the Cooldown Manager coverage report, dev-only) are described in `docs/dev/providers-ab.md`, with the two
experimental options and their Snapshot audit lines.
The CPU budget (`pack_gate.health`) is process CPU time (`os.clock` around each Update in
`tests/Game/harness/loop.lua`; a traced fight, every tally's first, adds no sample: its debug pass formats a line per
APL entry, Feral 3-fight 6.25 / 27.55 -> 4.47 / 6.80 ms mean / p99 when it left the metric), so other processes
waiting for a core do not count; shared cores (SMT, cache) still raise it: Arms read 4.1 ms alone and 6.1-6.7 ms in
`make check`'s 16-wide run. So the bar is on a ratio: each tick's ms over `loop.calibrate`'s (a fixed pure-Lua
workload, about 7 ms alone, timed once per counted fight in the same process), `r.cpuRatio <= pack_gate.CPU_RATIO`
(1.0, 20-fight lines stay under 0.6; `pack_gate.CPU_RATIO_ONE_FIGHT` 1.2 for a one-fight line, a replay, whose single calibration moves the whole ratio: Feral's replay reads median 0.50, p90 0.81, worst 0.909; the bar began at 1.4, the old 10 ms bar on a quiet run, 10 / ~7 ms; Arms reads 0.555), the ms mean and p99 reported beside it. Under a 16-wide `make test` Feral's 3-fight mean
rose 4.25 -> 5.82 ms while its ratio moved 0.634 -> 0.494 (Arms 3.78 -> 5.92 ms, 0.624 -> 0.547). Each line also reports
`bytes N per Update` (`collectgarbage("count")` around every 8th counted cycle, the collector stopped for that cycle:
a running sweep makes the delta negative), a noisy indicator rather than a measurement (it can still read slightly
negative: a sample's cycle can free what it did not allocate), not gated: every pack allocates a little per Update (gaps.md CD; only Arms has an allocation test).

`make check`'s 6-fight Arms gate is two files of 3 fights (`tests/Forever/loop_warrior_spec.lua`, seeds 1-3, and
`loop_warrior_late_spec.lua`, seeds 4-6), so it prints three `Arms solo:` lines (`tests/Forever/arms_recs_spec.lua`
repeats seeds 1-3 against its every-slot fixture). Each fight seeds its own world and the
boot carries nothing between fights, so the halves play the same fights as the old single run.
The gate runs Arms (wowsims.com), the Arms default since the wowsims packs plan's Warrior swap (the hand-built Arms,
Fury and Protection lists retired), on the world's wowsims build (Spearing Strike and Berserker Rage in the kit). Its
lines (the mana regen plan's gate on 0ce56d64f; central fix 23, the pre-pull guards, read 20 fights: agreement 0.966, flicker 1.51/min, oracle 1.07):

```
Arms solo: fights=3 agreement 0.967 (2399 ticks); react median 0 p90 1 never 0.032; refused per 100 [cost 10.9 (oracle 13.8, unmatched 3.6)], episodes 1.75/min; dps A/B 0.984; ... [seeds 1-3]
Arms solo: fights=3 agreement 0.976 (2452 ticks); react median 0 p90 1 never 0.009; refused per 100 [cost 14.4 (oracle 19.9, unmatched 0.0)], episodes 3.18/min; dps A/B 1.014; ... [seeds 4-6]
Arms solo: fights=20 agreement 0.957 (15575 ticks); react median 0 p90 1 never 0.036; ready while short 0; held while ready 285; refused per 100 [], episodes 0.00/min; dps A/B 0.995; ...
Arms party: fights=10 agreement 0.942 (4293 ticks); react median 0 p90 0 never 0.036; refused per 100 [cost 2.7 (oracle 4.5, unmatched 0.0), requires:no dodge 1.7 (oracle 1.7, unmatched 0.0)], episodes 0.63/min; dps A/B 0.942; ...
```

`make test-loop` also runs Fury (wowsims.com) 20 fights at level 60 and 24 (`loop_warrior_fury_spec.lua`,
`loop_warrior_fury24_spec.lua`, `helpers/fury_gate.lua`): Arms never waits on Heroic Strike (`rage>=90`), Fury does
(`rage.current>=40`), so its flicker/min is the on-next-swing strike's jitter gate (central fix 21: L60 agreement 0.934,
flicker 1.71/min, oracle 0.56; L24 0.908, 3.31/min, oracle 2.16), and Protection (wowsims.com) 20 fights at level 60
(`loop_warrior_protection_spec.lua`, `helpers/protection_gate.lua`; gap CI, 2026-10-31: agreement 0.925, flicker
0.74/min, oracle 0.42; about 3 min a file, under the gate's slowest).

The flicker columns (the flicker ledger, `tests/Game/harness/flicker.lua`; what counts and the cause classes: the
headless loop design §5.1). `flicker X/min (oracle Y)` stays where it was (the first icon's A->B->A within 3 ticks,
unchanged); the ledger's fields come last on every line (after a replay's decision fields, before `; hold on`), for
run A over every displayed slot (queue positions 1-3 and the focus entry): `dips` and `flashes` per minute (our
presses' left out), `top [cause n; cause n]` over them, `p90 length` (ticks), `retracted R/min (oracle R')` (ready, then
waiting again within 1 s, no justifying event) with its top `ability:cause/reason`, `justified` (those with an event),
`waits W/min (oracle W')` with its top `ability:cause`, `floor jitter` (lo crossing a slot's cost while est stays above
it) and `at cost lo-truth m/p90 est-truth m/p90 (n)` (the band's gap at cost-gated decisions). The 20-fight Arms
line's tail (forever-flicker):

```
... dips 11.28 flashes 2.59; top [swing 381; unknown 225]; p90 length 3 ticks; retracted 0.02/min (oracle 0.05) [sunder_armor:unknown/cost 1] justified 8.95; waits 15.97/min (oracle 7.00) [sunder_armor:swing 225; rend:swing 114]; floor jitter 0; at cost lo-truth -0.6/16.9 est-truth 1.1/15.1 (2426)
```

`waits` counts any jump of the same icon's wait above its countdown by more than a poll, a wider definition than the
Heroic Strike report's snap-back (a countdown at most 0.3 s from done jumping up at least 0.4 s): Fury L24's focus-slot
Heroic Strike reads 5.7/min here against that report's 0.97/min; the two are not comparable. A replay line adds
`decision flips N (per 100)` (our first on-GCD icon changed between the tick's poll and wowsims's decision, with no
cast, spend, avoid or aura change of ours between) and `retracted confirmed by wowsims` (a retraction of an ability
wowsims cast within a tick). `pack_gate.FLICKER` floors each gated 20-fight loop's flicker and retracted readies (the
measured value rounded up to the next 0.1, 0 where it measured 0; only ever down) and bars flicker <= oracle +
`FLICKER_K` (0.5): redundant with the floors today, it tightens the bar when a change lowers the oracle's own flicker.
`HEKILI_LOOP_HOLD=1 make test-<tag>` runs the display-side hold experiment (`; hold on`, floors not applied); as
expected it turns the Arms 20-fight gate red (agreement, unmatched cost refusals) and the Fury gates and two leveling
gates red (react p90, idle). The shipped steady icons (always on for players, hold 1; no setting) are on in every
loop and replay on our instance (`; steady icons on`; the oracle shadow stays plain; the harness sets the instance's
`Output.steady`/`Output.hold`): the loop reads the held output itself, not a harness copy, and the floors are measured
on it. `HEKILI_LOOP_STEADY=N` (or
`o.steady = N`) sets the updates to hold (1 to 3; `; steady icons on (hold N)` for N above 1, floors not applied);
`HEKILI_LOOP_STEADY=0` turns them off (floors not applied).

Before the pull it shows Bloodrage and Battle Shout only (no positions headless, so no Charge). Seeds 1-3 used to show
casting refusals (7.0 per 100, the oracle's 0.5): presses during Slam's 1.5 s cast while the world's client sent only
a cast's success; since fix 22 the world sends the cast's start too, and the refusals are gone (gap BD records the
cast-boundary flicker that replaced them).

`tests/Forever/loop_druid_spec.lua` runs 3 fights a Druid pack in `make check` (seeds 1-3, the `#slow` tag) and 20 in
`make test-druid` (`#druid`), each asserting its flagged lines ran (`r.focus > 0`). Every Druid spec runs its
wowsims.com default (wowsims packs plan, Tasks 7b and 7g; the hand-built lists retired); Feral and Balance are gated by
`pack_gate.gate`, Guardian is reported (engine health and focus asserted, not the agreement, the unmatched bar or the
oracle + K bar: unmatched 3.5 and a 0.83 gap at seeds 41-60) but floored (its `M.FLICKER` row: flicker 1.1, retracted
0.7, ready-while-short 190, held-while-ready 330; gap CH): its first icon waits on rage the usability ladder cannot
place. Current lines (the mana regen plan's gate on 0ce56d64f):

```
Feral solo: fights=3 agreement 0.942 (2370 ticks); react median 0 p90 0 never 0.014; refused per 100 [], episodes 0.00/min; dps A/B 1.063; ... [seeds 1-3]
Guardian solo: fights=3 agreement 0.915 (2566 ticks); react median 0 p90 1 never 0.007; refused per 100 [cost 7.3 (oracle 8.3, unmatched 0.0)], episodes 1.64/min; dps A/B 0.987; ...
Balance solo: fights=3 agreement 1.000 (2611 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 5.3 (oracle 4.8, unmatched 0.0)], episodes 0.57/min; dps A/B 1.013; ... [seeds 1-3]
Feral solo: fights=20 agreement 0.980 (16632 ticks); react median 0 p90 0 never 0.007; ready while short 0; held while ready 200; refused per 100 [], episodes 0.00/min; dps A/B 1.001; ...
Guardian solo: fights=20 agreement 0.890 (17354 ticks); react median 0 p90 1 never 0.023; ready while short 0; held while ready 284; refused per 100 [], episodes 0.00/min; dps A/B 0.992; ...
Balance solo: fights=20 agreement 1.000 (17520 ticks); react median 0 p90 0 never 0.000; ready while short 0; held while ready 133; refused per 100 [casting 4.9 (oracle 4.7, unmatched 0.0)], episodes 0.48/min; dps A/B 1.028; ...
```

The Feral and Balance worlds keep the wowsims logs' mana pools and five-second rule (22 a second outside it).

`tests/Forever/loop_rogue_spec.lua` runs 3 fights a Rogue spec in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-rogue` (`#rogue`), each on its "<Spec> (wowsims.com)" pack (wowsims packs plan, Task 8), gated by
`pack_gate.gate` and asserting its flagged lines ran (`r.focus > 0`: Slice and Dice at tier 1 in every pack). The
worlds carry the wowsims.com builds' abilities and talents (Subtlety Hemo has no Ghostly Strike); the replay and
leveling gates are `tests/Forever/wowsims_rogue_spec.lua`. The lines (the mana regen plan's gate on 0ce56d64f):

```
Combat solo: fights=3 agreement 0.991 (2237 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.927; ... [seeds 1-3]
Assassination solo: fights=3 agreement 1.000 (2282 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.010; ... [seeds 1-3]
Subtlety solo: fights=3 agreement 0.991 (2043 ticks); react median 0 p90 0 never 0.011; refused per 100 [], episodes 0.00/min; dps A/B 0.979; ... [seeds 1-3]
Combat solo: fights=20 agreement 0.993 (10043 ticks); react median 0 p90 0 never 0.005; ready while short 0; held while ready 175; refused per 100 [], episodes 0.00/min; dps A/B 1.025; ...
Assassination solo: fights=20 agreement 0.989 (10460 ticks); react median 0 p90 0 never 0.014; ready while short 0; held while ready 189; refused per 100 [], episodes 0.00/min; dps A/B 0.973; ...
Subtlety solo: fights=20 agreement 0.986 (10526 ticks); react median 0 p90 0 never 0.009; ready while short 0; held while ready 182; refused per 100 [], episodes 0.00/min; dps A/B 1.000; ...
```

`tests/Forever/loop_paladin_spec.lua` runs 3 fights a Paladin pack in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-paladin` (`#paladin`), asserting its flagged lines ran (Retribution: the seal twist at tier 1; Protection:
Seal of Fury and Holy Shield at tier 2). The mob swings at us in both worlds: Holy Shield raises the block chance and
each block spends a charge (the world's class-neutral `taking`/`took`); our landed swing spends an Echo (`landed`); mana
runs under the five-second rule (`fsr`: wowsims's logs, Retribution 13.65 spirit / 8.25 mp5, Protection 17.38 / 0, an
empty pool; Task 7 floored Retribution 0.9 and Protection 0.8 for gap AB, 0.6 and 0.2 since gap CE). Both packs are gated by `pack_gate.gate`; both
are wowsims.com packs since the wowsims packs plan, Task 9 (the hand-built lists retired). Retribution (wowsims.com)'s
swing-gap fillers carry wowsims's own `mana.pct>=10`, judged on the secret-mana belief; each fight starts with the mana
the last one left, regenerated through the 30 s gap (GAP X, closed: the 20-fight line was 0.911, never 0.226, while
fights restarted at full mana). The holy_shock list is gone with the hand-built Retribution list; Hammer of Wrath's
window is not exercised by the solo worlds. The runs (the mana regen plan's gate on 0ce56d64f):

```
Retribution solo: fights=3 agreement 0.994 (2174 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.997; ... [seeds 1-3]
Protection solo: fights=3 agreement 0.933 (2519 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.982; ... [seeds 1-3]
Retribution solo: fights=20 agreement 0.999 (15566 ticks); react median 0 p90 0 never 0.000; ready while short 0; held while ready 98; refused per 100 [], episodes 0.00/min; dps A/B 0.994; ...
Protection solo: fights=20 agreement 1.000 (17459 ticks); react median 0 p90 0 never 0.000; ready while short 0; held while ready 118; refused per 100 [], episodes 0.00/min; dps A/B 0.986; ...
```

Paladin checkpoint (in game, a level 60 Paladin; provisional until answered):
- P1: the client's pseudo-spec id (assumed 1486; only the legacy profile migration reads it) and the talent tree the
  dominant-tree pick chooses for your build (Snapshot `spec:` line), and the talent IDs (Twist of Light
  1310735, Swift Judgement 1310994, Instrument of Law 1311085, Holy Shock 20473, Holy Shield 20925).
- P2: are the seal auras (20375.., 20154.., 21082.., 1311649..) and the Echoes (1311703, 1311704, 1311701) readable on
  the player in combat, or secret (then the belief holds an Echo until the next seal: check the twist still advances)?
- P3: does an Echo drop on our next landed white swing only, or on any melee hit (Holy Strike, a miss)?
- P4: Judgement and the seal: does Judgement leave the seal up (modelled as wowsims judgement.go: not consumed)? Is
  Judgement unusable (IsSpellUsable false, false) without a seal, and with Swift Judgement's charge is it free?
- P5: Hammer of Wrath's usability edge: does IsSpellUsable flip at exactly 20% target health (the `healthGate`), and
  is its cast 1 s (0 with Instrument of Law: DB2 rank 1 -1000 ms, wowsims says 0.5 s a rank)?
- P6: Holy Shield's charges: 4 stacks on the player aura, one spent per BLOCK and per partial block (BLOCKED) in
  UNIT_COMBAT, and the aura readable in combat?
- P7: mana: UnitPower(mana) secret out of combat on a Paladin too; GetPowerRegenForPowerType(0)'s two returns out of
  combat (not casting = spirit + mp5, casting = mp5, as the belief now reads them); a cost percentage (Judgement 6%,
  Righteous Fury 30%) is of base mana in the DB2, priced here as of the maximum.
- P8: Exorcism: which ranks a Paladin learns (879.. Undead/Demon only, or 415068.. any target), and whether
  IsSpellUsable answers false on a beast for the 879 ranks.
- P9: Consecrated Ground (1280353, the aura the class file reads; wowsims logs it, not the APL's 1310905) on the
  target after Consecration, its 8.6 s; Seal of Fury's absorb and Improved Seal of Fury's mana are unmodelled.
- P10: Judgement's cooldown with Improved Judgement (modelled 10 s less 1 s a rank: 8 s at 2/2), and the costs at
  partial ranks of Benediction (2% less a rank) and Holy Conduit (20% less a rank; Consecration, Exorcism, Hammer of
  Wrath): the DB2 holds the full-rank value on rank 1 (ruling P5), so check a 1-rank cost in the spellbook tooltip.
- P11: Sanctified Judgement at 3/3: does every Judgement return 60% of the seal's base cost (the belief gains it, e.g.
  161 mana for Seal of Command at 0.72), or is the refund chance-based or another amount (then the bound over-reads)?
- P12: Retribution (wowsims.com)'s `use_items` line: is the equipped on-use trinket suggested, off the GCD, when ready?
- P13: Protection (wowsims.com)'s precombat order: Retribution Aura (10 s before the pull), then Seal of the Crusader
  at 1.5 s, then Seal of Fury in combat; and no Righteous Fury suggestion (ruling P11).

`tests/Forever/loop_shaman_spec.lua` runs 3 fights of each Shaman pack (Enhancement and Elemental (wowsims.com)) in
`make check` (seeds 1-3, `#slow`) and 20 in
`make test-shaman` (`#shaman`), gated by `pack_gate.gate` and asserting its flagged lines ran (Lightning Bolt at 5
Maelstrom Weapon and Fire Nova on Clearcasting at tier 1; Strength of Earth, Lightning Shield and Flame Shock at tier
2). The world keeps the totem slots (`W.summonTotem`, class-neutral: a slot and an expiry), secret in combat; the summon's
`now` (`summonTotem`, content API 4) writes the slot's modelled expiry, which the in-combat GetTotemInfo answers. The
mob swings at us and each hit that lands spends a Lightning Shield charge; our landed melee stacks Maelstrom Weapon; an
elemental spell rolls Clearcasting (10%); the shocks share a cooldown (6 s, 0.2 s less a rank of Reverberation); Rage
of the Farseer (the build's talent, in the kit) gives its 25 s buff, its +30% attack speed not modelled. Neither side dies: a kill by our last press
ends the loop before the client sees it, so the next fight's prepull would be believed in combat and its totem slots
never read (a harness quirk every pack shares). The world runs out of mana about 35 s in (idle about 0.69: regen as
wowsims's logs measure it per spec (Mindfulness inside Elemental's, Improved Stormstrike's casting share in
Enhancement's; Mana Spring Totem's 5 a second as its own aura entry (10494) while the water totem stands, in both),
UNMEASURED pool, no Water Shield or potions), so most in-combat ticks show no icon on either side.
The imbues are not in the solo world's kit (it has no weapon enchant read). The world's costs are each rank's (DB2),
with Shamanistic Focus when the build has it, Stormstrike's 121 (wowsims/forever's), and the shocks' cooldown and Flame
Shock's duration from the booted talents. The lines below run Enhancement (wowsims.com) (wowsims packs plan, Task 10,
the forever gate on 51a0b1ac: Fire Nova at the DB2's 520). `tests/Forever/wowsims_shaman_spec.lua` replays wowsims's
own fight (floor 0.96, the table below) and runs the levels 10, 40 and 60 (40 pending: GAP AB, the secret-mana floor's last mana).
Elemental (wowsims.com) (Task 14) runs the same gates on the Elemental world (20 yd, wowsims's 5650 mana and regen:
26.13 a second casting without Mana Spring Totem's buff, 31.13 with it, 45.25 outside the five-second rule; re-pin
e2842f0a78): replay floor 0.89 (the table below), live L10 0.2,
L40 0.0, L60 5.0 s (LIVE60 5.0), flicker floor 0.6. The lines:

```
Enhancement solo: fights=3 agreement 0.997 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.027; ... [seeds 1-3]
Enhancement solo: fights=20 agreement 0.912 (18040 ticks); react median 0 p90 8 never 0.016; ready while short 0; held while ready 152; refused per 100 [], episodes 0.00/min; dps A/B 0.996; ...
Elemental solo: fights=3 agreement 0.985 (2706 ticks); react median 0 p90 1 never 0.000; refused per 100 [casting 4.2 (oracle 3.8, unmatched 0.0)], episodes 0.67/min; dps A/B 0.990; ... [seeds 1-3]
Elemental solo: fights=20 agreement 0.993 (18040 ticks); react median 0 p90 1 never 0.013; ready while short 0; held while ready 284; refused per 100 [casting 0.5 (oracle 0.2, unmatched 0.0)], episodes 0.07/min; dps A/B 0.997; ...
```

Shaman checkpoint (in game, a level 60 Shaman; provisional until answered):
- S1: the client's pseudo-spec id (assumed 1489; only the legacy profile migration reads it) and the talent tree the
  dominant-tree pick chooses for your build (Snapshot `spec:` line).
- S2: totem slot order: GetTotemInfo(1..4) out of combat is fire, earth, water, air (as Hekili's `totem.<element>`
  and `summonTotem` assume)? Searing Totem's duration (55 s at rank 6) and the 300 s totems' read back as such?
- S3: PLAYER_TOTEM_UPDATE in combat: does it fire for our own summon (and for the replaced totem), and does it arrive
  within 0.5 s of UNIT_SPELLCAST_SUCCEEDED (I.CAST_GRACE; later, the belief drops the summon as a destruction)? Does it
  fire at a totem's natural expiry and when the totem is killed? Is GetTotemInfo secret in combat (all returns)?
- S4: Maelstrom Weapon (408505) visibility: is the player aura and its stack count readable in combat? Is 408498 a
  learnable rune on Forever (else its lines stay inert)? Five stacks: Lightning Bolt instant and free?
- S5: Clearcasting (16246) after an elemental spell: readable in combat; one charge, spent by the next Lightning Bolt,
  shock or Fire Nova (the cost modifier's list)?
- S6: Fire Nova (408341..408345): IsSpellUsable without a fire totem answers (false, false), not short of mana (its
  answers are a mana rung)? Its cooldown (10 s, 6 s with Improved Fire Nova 2/2), and does it leave the totem up?
- S7: Lightning Shield (324..10432): 3 charges on the player aura, one spent per hit that lands (WOUND and partial block
  in UNIT_COMBAT), readable in combat?
- S8: the shocks' shared cooldown: after Earth Shock, does Flame Shock read on cooldown (category 19: 6 s, 5 s with
  Reverberation 5/5), and the reverse?
- S9: the imbues: C_Item.GetWeaponEnchantInfo out of combat after Rockbiter (60 minutes), so main_hand_enchant reads up
  (the imbue reminder setting is retired with the hand-built list); the dual-wield off hand (not modelled).
- S10: mana: UnitPower(mana) secret out of combat on a Shaman too; GetPowerRegenForPowerType(0)'s two returns; the
  Flame Shock DoT (12 s, 21 s with Call of Flame 3/3; 3 s ticks) on the target modelled from our cast.
- S11: wowsims/forever's spell data against the client: Flame Shock lasts 21 s with Call of Flame 3/3? Stormstrike
  costs 121 (8% of base mana) or the DB2's 125? Fire Nova costs 375 (wowsims) or the DB2's 520 (the kit's)?
  Shamanistic Focus takes 45% off the shocks and Lightning Shield?
- S12: Rage of the Farseer (425336, the talent): its buff readable in combat (25 s, +30% attack speed), its 180 s
  cooldown read plain in combat, off the GCD; Enhancement shows it right after Blood Fury with Cooldowns on?
- S13 (Elemental kit, wowsims/forever's data absent from the DB2 at 70338): Lava Burst rank 4 (1326047: 265 mana,
  2.5 s, 10 s) and Mana Tide Totem rank 4 (1325256: 60 mana, 13 s, 5 min) in the spellbook at 60? Elemental Mastery
  (16166): off the GCD, 3 min, 15 s, lasts its 15 s (not spent by the next cast), takes 0.5 s off Lightning Bolt and
  Lava Burst and lifts Chain Lightning's 6 s cooldown? Elemental Alacrity at 3/3: Lightning Bolt 2.0 s, Chain
  Lightning 1.5 s (Forever's -170/-330/-500 ms, not the DB2's -200 a rank)? Convection 5/5: -10% on Lightning Bolt,
  Chain Lightning, Lava Burst and the shocks? Clearcasting makes Chain Lightning and Lava Burst free? Revelation
  (1323418): readable in combat, spent by the next Lightning Bolt, Chain Lightning, Lava Burst or Earth Shock? Water
  Shield (408510) and Lightning Shield replace each other, 3 globes?

`tests/Forever/loop_hunter_spec.lua` runs 3 fights of each Hunter pack in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-hunter` (`#hunter`), gated by `pack_gate.gate` and asserting that some focus line ran (`r.focus > 0`: Beast
Mastery and Marksmanship flag Hunter's Mark and Serpent Sting at tier 2; Survival flags Raptor Strike and Mongoose Bite
at tier 1 and Hunter's Mark at tier 2). The packs are the
wowsims.com ones (Beast Mastery, Marksmanship and Survival (wowsims.com), Task 11 of the wowsims packs plan:
wowsims/forever's Melee Weave), and their replay and leveling gates are `tests/Forever/wowsims_hunter_spec.lua`. Each
pack opens with wowsims's automatic Blood Fury and Rapid Fire (translator rule 13, from 5 s, off the GCD). The Beast
Mastery and Marksmanship worlds stand at 11 yd (the weave's range: the shots in their band, Raptor Strike and the melee
lines out of reach) and shoot Auto Shots on the harness's ranged hand (`W.startRanged`), Quick Shots procs off them
under Aspect of the Hawk (10%); they run the same pack text and kit, so their lines match. The Survival world sets no
distance (every check in range), swings a two-hander and keeps the pack's Aspect of the Hawk up. Its Mongoose Bite
window never opens: our dodge is meant to open it for 5 s, but `dodged()` in `tests/Forever/helpers/hunter_world.lua`
reads `W.t`/`W.truth`, which a batched list answer sees at the finished world. Each world prices the known rank under
the character's Resourcefulness and Efficiency (the leveling brackets; the replay's builds). Their mana regen is wowsims's logs' (Beast Mastery 7.94 casting / 15.88 outside; Marksmanship and Survival 0 / 15.88, Resourcefulness adding half the 15.88 while casting for 30 s, rolled on a landed ability at the crit rate counted in the logs; the Marksmanship and Survival loop worlds take the exports' Resourcefulness 2/2, so its cost cut applies there too, gap BV). Raptor Strike's cooldown
starts at its swing (class-neutral: a queued strike's cooldown). Each fight's fresh world gets the pack's aspect at the
pull (the character keeps a permanent buff between fights). Neither side dies (shaman_world's workaround for the loop's
missing kill). The kit's ranges are DB2's (`RANGE`: Hunter Range 8-35, Combat Range 0-5). "The Hunter at range, then
in melee" runs Survival at 25 yd, then 5 yd: its four `target.within5` lines stay shut while the bracket reads [8, 35],
open at [0, 5], and the bracket holds when every read goes secret. Mana is secret in combat, so the belief holds its
lower bound and the worlds idle 0.823 (Beast Mastery), 0.844 (Marksmanship) and 0.394 (Survival, whose strikes the Resourcefulness cut makes cheap) of the time at 3 fights. The
lines (the mana regen plan's gate on 0ce56d64f; the hand-built lists' were 0.983/0.986/0.945 at 3 fights):

```
Beast Mastery solo: fights=3 agreement 0.996 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.994; ... [seeds 1-3]
Marksmanship solo: fights=3 agreement 1.000 (2503 ticks); react median 0 p90 1 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.000; ... [seeds 1-3]
Survival solo: fights=3 agreement 0.976 (2706 ticks); react median 0 p90 1 never 0.008; refused per 100 [], episodes 0.00/min; dps A/B 0.968; ... [seeds 1-3]
Beast Mastery solo: fights=20 agreement 0.996 (16722 ticks); react median 0 p90 1 never 0.004; ready while short 0; held while ready 151; refused per 100 [cost 0.0 (oracle 13.8, unmatched 0.0)], episodes 0.00/min; dps A/B 0.994; ...
Marksmanship solo: fights=20 agreement 1.000 (16624 ticks); react median 0 p90 1 never 0.000; ready while short 0; held while ready 111; refused per 100 [], episodes 0.00/min; dps A/B 1.000; ...
Survival solo: fights=20 agreement 0.958 (18040 ticks); react median 0 p90 1 never 0.007; ready while short 0; held while ready 323; refused per 100 [cost 0.0 (oracle 0.4, unmatched 0.0)], episodes 0.00/min; dps A/B 1.013; ...
```

Hunter checkpoint (in game, a level 60 Hunter with a ranged weapon and a pet; provisional until answered): the Hunter
research's §7 questions (`docs/research/2026-10-15-forever-hunter/research.md`), plus:
- H1: the client's pseudo-spec id (assumed 1484; only the legacy profile migration reads it) and the talent tree the
  dominant-tree pick chooses for your build (Snapshot `spec:` line).
- H2 (Q1, C7-3): UnitRangedDamage("player") plain out of combat, and secret in combat? Its first return feeds the
  ranged hand's speed.
- H3 (Q2, C7-1): PLAYER_SWING with swingType 2 for each Auto Shot, and its duration the hasted ranged speed (the better
  anchor, already wired)?
- H4 (C7-2): UNIT_SPELLCAST_SUCCEEDED for Auto Shot (75) on every shot, at the release? The modelled clock assumes it.
- H5 (C7-4): ranged haste (quiver, Rapid Fire, Quick Shots) in UnitRangedDamage's speed out of combat, and the clock's
  drift in combat under Rapid Fire.
- H6 (Q3, Q6): C_Spell.IsSpellInRange(75, "target") at 4, 10 and 40 yards, in and out of combat (the target's range
  bracket reads it; the packs have no deadzone guard of their own); plain or secret in combat? Raptor Strike (on the
  next swing) in range at any distance, like Heroic Strike?
- H14 (gap 13): `/run local r=Hekili.State.target VSCopy(r.distance,r.minR,r.maxR,r.within5,r.outside8)` at 3, 11 and
  30 yards: about 2.5 / 0 / 5 / true / false in melee, 21.5 / 8 / 35 / false / true at 11 yd. Measured
  2026-11-07 (Warrior ForeverProbe dump): the live client reads `C_Spell.GetSpellInfo(<melee strike>).maxRange` 0 (Mortal
  Strike, Rend, Hamstring, Overpower, Slam, Revenge, Sunder Armor, Shield Bash) while `C_Spell.IsSpellInRange` answers
  plain true/false; and the owner's Druid check (2026-11-07, level 22): Claw, Shred and Swipe read 0 and answer true in
  melee, false at about 20 yd; Demoralizing Roar and Cat Form read 0 and answer nil at both. The belief reads a hostile
  (`startsCombat`) spell's 0 as a 5 yd check whose nil answer is skipped (Sources/Spellbook.lua, 0.6.2). Still to
  confirm: Wing Clip (14268) and Mongoose Bite read 0 the same, and the other classes' self-centred hostile spells
  (Thunder Clap, Hellfire, Consecration, Holy Nova, Fire Nova) answer nil, not true, at 20 yd.
- H7 (Q4): Multi-Shot's and Strider Kick's actual costs (DB2 13.9% and 5.81% of base mana, priced here as of the
  maximum); UnitPower(mana) secret out of combat on a Hunter too; GetPowerRegenForPowerType(0)'s two returns.
- H8 (Q5): Rapid Fire (3045) and Quick Shots (6150) readable on the player in combat (Aimed, Multi and Sniper Shot's
  hasted casts)?
- H9 (Q9): Sniper Shot (1310687..), Summon Hawk (1293241..), Strider Kick (1317257) and Aspect of the Beast's Forever
  ranks (1299445..) learnable (else their lines stay inert)?
- H10 (C1, CAST_GRACE): Summon Hawk: two hawks at most, 18 s each, the oldest replaced by a third; is a hawk a `pet`
  unit (UNIT_PET) at all? If the Hunter's pet unit is summoned (Call Pet), does UNIT_PET arrive within 0.5 s of
  UNIT_SPELLCAST_SUCCEEDED (I.CAST_GRACE)?
- H11: Arcane Shot and Summon Hawk share a 6 s cooldown (category 1173), Aimed Shot and Multi-Shot another (category 2)?
- H12 (Q14): Mongoose Bite usable only for 5 s after a dodge (Defensive State 5302) and for 10 s of Expose Prey
  (1310726, the talent's proc), by IsSpellUsable; Raptor Strike queued (IsCurrentSpell) and its 6 s cooldown from the
  swing that takes it?
- H13 (Q8): Hunter's Mark and Serpent Sting on the target unreadable in combat (modelled from our casts)?
- H15: Multi-Shot's cast: 0.5 s (DB2 2643, kept) or instant (wowsims)? The weave line reads it against the swing
  (live since central fix 11's division).
- H16: Immolation Trap's 30 s category cooldown (DB2 SpellCooldowns).
- H17: `mainhand_remains` against the real main-hand swing (the weave's Multi-Shot gap); past a due swing out
  of melee it reads 0 (wowsims's due timer), not a swing a period later.
- H18: Resourcefulness (440529) and Efficiency (19416) reported as talents at their ranks, and the prices they give:
  Mongoose Bite, Wing Clip, Immolation Trap and Strider Kick 30% / 60% off; Raptor Strike under both (wowsims's log 40
  at 2/2 Resourcefulness, 94 at 2/5 Efficiency).
- H19: `target.within5` through the weave (in and out of melee each swing): the melee lines open and shut in time?
- H20: a saved BeastMastery, Marksmanship or Survival choice falls back to the spec's wowsims.com pack.
- H21: Rapid Fire and Blood Fury recommended from 5 s into a fight, off the GCD (rule 13's automatic cooldowns).

`tests/Forever/loop_mage_spec.lua` runs 3 fights of each Mage pack in `make check` (seeds 1-3, `#slow`) and 20 in `make
test-mage` (`#mage`, `loop_mage_arcane_spec.lua`, `loop_mage_fire_spec.lua`, `loop_mage_frostfire_spec.lua`), gated by
`pack_gate.solo` and asserting that some focus line ran (Arcane: Missiles on Missile Barrage at tier 1, Evocation at
tier 2; Fire also Pyroblast on Heating Up at tier 1 and Scorch at tier 2: ruling M5; Frostfire Pyroblast and Fire Blast
(unless two Fingers of Frost charges are up) at tier 1, Scorch and Evocation at tier 2). The packs are Arcane and Fire
(wowsims.com) (Task 12 of the wowsims packs plan) and Frostfire (wowsims.com) (Task FFB: Fire's second pack, its talents
29 Fire points to 22 Frost; Frost unsupported), their replay and leveling gates `tests/Forever/wowsims_mage_spec.lua`.
The worlds (`tests/Forever/helpers/mage_world.lua`) cast at 25 yd with cast bars and channels (Arcane Missiles,
Evocation: any press at 99% mana clips it); the character is trainer-taught (no book ranks, as wowsims's), its pool and
regen are the logs' (Arcane 6678, Fire 6168; 29.13 a second outside the five-second rule, all of it while casting for
Arcane, half for Fire and Frostfire; Evocation's mana is that regen's aura entry, spirit x 16 and all of it while
casting, 466 a second as wowsims's logs, its channel ticks gaining nothing). Flicker floors (pack_gate `FLICKER`): Arcane 1.7 (1.66, oracle 1.46; 1.5 since the
lane review's Arcane Power fix measured 1.43, oracle 1.41), Fire 1.3 (1.21, oracle 0.40), Frostfire 0.3 (0.30, oracle
0.38; 0.2 after the flicker counter, back to 0.3 in the mana-regen plan's Task 6: 0.12 / 0.20 / 0.23, Evocation's
mana on the 0.1 s regen tick re-times the fights onto gap BS's frostfire_bolt <-> scorch edge), retracted 0 each. Fire's excess over its oracle is Fire Blast's cooldown end (fire_blast > fireball > fire_blast,
7 of 10 flickers in 3 fights: the not-ready flag's CD_PROBE push, central); the Scorch line's Fire Vulnerability edge is
a candidate. Frostfire's 20-fight agreement (0.958) is lowest where its mana runs dry: pooling for Frostfire Bolt, the
believed mana a few points under the truth (Master of Elements' refunds unseen) puts Frostfire Bolt's ready time past
the Scorch line's Fire Vulnerability `remains<5` edge, so ours shows Scorch where the oracle shows Frostfire Bolt
(API-forced; the modelled Fire Vulnerability measured equal to the world's, no early end). Fire's and Frostfire's uptime
0.96 (ours driving) against 0.99 (the oracle) is an Evocation at a carried fight's start: the believed mana's lower
bound reads `mana.pct<=10` where the truth is 16-19%, and the 8 s channel delays the first Scorch (shared gap,
reported). The lines (the mana regen plan's gate on 0ce56d64f):

```
Arcane solo: fights=3 agreement 0.984 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 1.4 (oracle 1.3, unmatched 0.0)], episodes 0.22/min; dps A/B 0.948; ... [seeds 1-3]
Fire solo: fights=3 agreement 0.999 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 7.1 (oracle 8.1, unmatched 0.0)], episodes 1.00/min; dps A/B 0.964; ... [seeds 1-3]
Arcane solo: fights=20 agreement 0.990 (18040 ticks); react median 0 p90 0 never 0.005; ready while short 0; held while ready 95; refused per 100 [casting 0.9 (oracle 2.2, unmatched 0.0)], episodes 0.13/min; dps A/B 0.977; ...
Fire solo: fights=20 agreement 0.995 (18040 ticks); react median 0 p90 0 never 0.000; ready while short 0; held while ready 171; refused per 100 [casting 1.3 (oracle 2.3, unmatched 0.0)], episodes 0.20/min; dps A/B 1.002; ...
Frostfire solo: fights=3 agreement 0.947 (2706 ticks); react median 0 p90 0 never 0.093; refused per 100 [], episodes 0.00/min; dps A/B 1.026; ... [seeds 1-3]
Frostfire solo: fights=20 agreement 0.919 (18040 ticks); react median 0 p90 0 never 0.005; ready while short 0; held while ready 110; refused per 100 [casting 1.1 (oracle 2.8, unmatched 0.0)], episodes 0.12/min; dps A/B 0.975; ...
```

`tests/Forever/loop_priest_spec.lua` runs 3 fights of each Priest pack in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-priest` (`#priest`, `loop_priest_shadow_spec.lua`, `loop_priest_smite_spec.lua`), gated by `pack_gate.solo`
and asserting that some focus line ran (Shadow Word: Pain, Devouring Plague and Holy Fire upkeep at tier 2, Inner Focus
at tier 1: ruling P5). The packs are Shadow (wowsims.com) on Shadow and Smite (wowsims.com) on Discipline (the Smite
build's dominant tree; Holy unsupported), Task 14 of the wowsims packs plan, from wowsims/forever's two Priest builds
(`ui/specs/priest/dps/builds/testing.build.json`, `smite_testing.build.json`); their replay and leveling gates
`tests/Forever/wowsims_priest_spec.lua`. The worlds (`tests/Forever/helpers/priest_world.lua`) cast at 20 yd with cast
bars and channels (Mind Flay, Penance, the wand's Shoot as one shot a wand speed long); Shadow starts in Shadowform; the
pools and regen are the logs' (Shadow 4711, Smite 6151; Shadow's regen without Dark Inspiration, its Spirit x 1.15 an
aura on the pull, each landed Mind Blast and each full Mind Flay: mana-regen Task 8, every line within its floor).
Flicker floors (pack_gate `FLICKER`): Shadow 0.1 (0.03 / 0.02 / 0.02 over seeds 1-20 / 21-40 / 41-60, oracle 0), Smite
0.1 (0.03 / 0.02 / 0.03, oracle 0), retracted 0 each. The lines (the mana regen plan's gate on 0ce56d64f):

```
Shadow solo: fights=3 agreement 0.993 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 6.7 (oracle 6.3, unmatched 0.0)], episodes 1.44/min; dps A/B 0.987; ... [seeds 1-3]
Smite solo: fights=3 agreement 0.958 (2706 ticks); react median 0 p90 0 never 0.007; refused per 100 [casting 27.1 (oracle 27.3, unmatched 0.8)], episodes 14.75/min; dps A/B 1.025; ... [seeds 1-3]
Shadow solo: fights=20 agreement 0.999 (18040 ticks); react median 0 p90 0 never 0.003; ready while short 0; held while ready 396; refused per 100 [casting 7.1 (oracle 7.1, unmatched 0.0)], episodes 1.46/min; dps A/B 0.999; ...
Smite solo: fights=20 agreement 0.936 (18040 ticks); react median 0 p90 1 never 0.017; ready while short 0; held while ready 0; refused per 100 [casting 27.7 (oracle 27.7, unmatched 1.2)], episodes 15.57/min; dps A/B 1.003; ...
```

`tests/Forever/loop_warlock_<pack>_spec.lua` runs 3 fights of its Warlock pack in `make check` (seeds 1-3, `#slow`) and
20 in `make test-warlock` (`#warlock`), gated by `pack_gate.solo` and asserting that some
focus line ran (the DoTs, Banes, curses and Searing Pain's brand upkeep at tier 2; Shadow Bolt on Shadow Trance and
Soul Fire on Decimation at tier 1). The packs are Affliction, SM Ruin (Affliction's second), Demonology, Shadow Brand
(Demonology's second) and Destruction (wowsims.com), Task 13 of the wowsims packs plan, from wowsims/forever's five
Warlock builds; their replay and leveling gates `tests/Forever/wowsims_warlock_spec.lua`. The worlds
(`tests/Forever/helpers/warlock_world.lua`) cast at 25 yd with cast bars and channels, the build's demon out from the
pull (its mana and regen from the logs), the Soul Shards in the bags; the pools are the logs' (5353, Demonology's 6156).
Flicker floors (pack_gate `FLICKER`, 20 fights): Affliction 0 (0 / 0 / 0 over seeds 1-20 / 21-40 / 41-60, oracle 0;
0.4 -> 0 on the mana-regen plan's Task 10: Wrack's 6 s paid channel holds the casting rate to its end), SM Ruin 0.3,
Demonology 0.1, Shadow Brand 0.1, Destruction 0.4 (their measured values beside them in pack_gate), retracted 0 each.
The lines (the mana regen plan's gate on 0ce56d64f):

```
Affliction solo: fights=3 agreement 1.000 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 3.6 (oracle 3.6, unmatched 0.0)], episodes 1.00/min; dps A/B 1.000; ... [seeds 1-3]
SM Ruin solo: fights=3 agreement 0.992 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.976; ... [seeds 1-3]
Demonology solo: fights=3 agreement 0.997 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 3.4 (oracle 3.4, unmatched 0.0)], episodes 1.33/min; dps A/B 0.993; ... [seeds 1-3]
Shadow Brand solo: fights=3 agreement 0.996 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 3.4 (oracle 3.4, unmatched 0.0)], episodes 1.11/min; dps A/B 1.000; ... [seeds 1-3]
Destruction solo: fights=3 agreement 0.980 (2706 ticks); react median 0 p90 0 never 0.003; refused per 100 [casting 12.2 (oracle 12.1, unmatched 0.6)], episodes 4.77/min; dps A/B 1.028; ... [seeds 1-3]
Affliction solo: fights=20 agreement 0.995 (18040 ticks); react median 0 p90 0 never 0.001; ready while short 0; held while ready 0; refused per 100 [casting 11.4 (oracle 11.1, unmatched 0.0)], episodes 2.44/min; dps A/B 0.991; ...
SM Ruin solo: fights=20 agreement 0.979 (18040 ticks); react median 0 p90 0 never 0.001; ready while short 0; held while ready 3; refused per 100 [], episodes 0.00/min; dps A/B 0.995; ...
Demonology solo: fights=20 agreement 0.953 (18040 ticks); react median 0 p90 0 never 0.000; ready while short 0; held while ready 0; refused per 100 [casting 4.2 (oracle 4.2, unmatched 0.3)], episodes 1.63/min; dps A/B 1.002; ...
Shadow Brand solo: fights=20 agreement 0.987 (18040 ticks); react median 0 p90 0 never 0.000; ready while short 0; held while ready 7; refused per 100 [casting 4.5 (oracle 4.1, unmatched 0.0)], episodes 1.48/min; dps A/B 0.995; ...
Destruction solo: fights=20 agreement 0.987 (18040 ticks); react median 0 p90 0 never 0.002; ready while short 0; held while ready 1; refused per 100 [casting 9.2 (oracle 9.0, unmatched 0.2)], episodes 3.49/min; dps A/B 1.008; ...
```

Priest checkpoints (a level 60 Priest; the `Hekili_Priest` mklink first):
- Pr1: Devouring Plague's cooldown 24 s and Shadow Word: Death's 18 s (wowsims's newer data; the DB2 at 70338 says 60 s
  and 15 s): the action bar's cooldown after a cast.
- Pr2: the wand's Shoot: what the client shows for auto-repeat Shoot (a channel, UnitChannelInfo, a success per shot);
  Smite's Shoot line at 10% mana and the next spell after it.
- Pr3: Shadowform read plain in and out of combat (GetShapeshiftForm); Mind Blast 175 mana in form.
- Pr4: Mind Flay's and Penance's channel info and tick timing; the next icon during a Mind Flay channel (ready at the
  GCD's end inside the channel, as the replay shows, or at the channel's end?).
- Pr5: Inner Focus then Mind Flay: does Mind Flay show right after Inner Focus (`prev.1.inner_focus`, PV1)?
- Pr6: Holy Fire and Smite below 20% mana: wowsims casts rank 5 of each (shared gap "cast a specific rank"); the pack
  shows the top rank.

Core checkpoints (R1 measured: rage at the swing; G7, O1, O2, M1, PH1, E1 and the rest) are in
`docs/dev/ingame-ledger.md`.

A deliberate pack or APL change re-records the fixture in the same commit:
`ARMS_RECS=record .lua/bin/busted tests/Forever/arms_recs_spec.lua`.

The display style fixtures in `tests/Forever/fixtures/` have their own record modes:
`CLASSIC_DRAW=record .lua/bin/busted tests/Forever/display_style_spec.lua` (`classic_draw.lua`),
`STYLE_OPTIONS=record .lua/bin/busted tests/Forever/style_options_spec.lua` (`classic_options.lua`) and
`TIMELINE_DRAW=record .lua/bin/busted tests/Forever/display_style_spec.lua` (`timeline_draw.lua`). The classic ones
prove a refactor left classic unchanged, so run their command at a base commit (the one before the change) in a
temporary worktree with the spec copied in, then copy the fixture back; never run it on the changed tree to make a
change pass. The
timeline fixture is re-recorded in place, in the commit that deliberately changes the timeline's look.

### wowsims packs

Every default priority is a wowsims.com pack (`"<Spec> (wowsims.com)"`): wowsims/forever's own APL translated to the
fork's keys and gated against wowsims's own fight (the plan: `docs/superpowers/plans/2026-10-19-wowsims-packs.md`;
the author's guide, the user's binding rules and the translator's rules: `docs/dev/wowsims-packs.md`; the open gaps:
`docs/dev/gaps.md`).

- **Pipeline.** A recipe `tools/wowsims/specs/<class>_<spec>.lua` -> `make wowsims-export SPEC=<class>_<spec>` (the
  request `tests/Forever/wowsims/<spec>.json` and wowsims's debug log `<spec>.log`, both checked in) ->
  `make wowsims-packs` (every recipe's `src/Hekili_<Class>/APLs/<Pack>.simc` from its checked-in request and log; no
  checkout needed, so `packs-check` runs it) -> `make packs` (the RegisterPack blocks). `make wowsims-learn
  CLASS=<TOKEN>` writes the class's learn levels (`tests/Forever/wowsims/learn_<class>.lua`, from wowdb).
- **The pin.** Per spec: `M.SPEC_PIN` in `tools/wowsims/export.lua` (`M.pin(spec)`) names the wowsims/forever
  commit each spec's recipe, request and log come from (OLD e2842f0a78 or NEW e5a9cd2a2d while the 0.7 re-pin moves
  them; `tests/Forever/wowsims_pin_spec.lua`); the export refuses a checkout at another commit. To move a spec: the
  flip procedure in `docs/dev/wowsims-packs.md` ("Moving the pin"), then `make wowsims-packs && make packs` and
  re-measure its floors and LIVE60 (each move named in the floor's comment).
- **`make wowsims-cli`** builds wowsimcli in the checkout (`WOWSIMS`, default `~/src/wowsims-forever`): Go, `protoc`
  and `protoc-gen-go` on PATH.
- **The gates** (`tests/Forever/wowsims_<class>_spec.lua`, tagged `#slow #wowsims`): `make check` runs them in its
  `#slow` tier, `make test-wowsims` alone. Per pack: the replay gate (`ws.gate`: the pack against wowsims's own fight,
  `decisions on-GCD` at least the floor, the engine's health) and the leveling gate (`ws.live` at three levels: no
  error, raise or unlisted read, at least one press, never idle longer than the limit with a usable on-GCD ability).
  `tests/Forever/wowsims_levels_spec.lua` runs `tools/check_pack_levels.lua` over every pack (the leveling rule's
  static check: every read of another ability sits inside a guard that drops it while that ability is unlearned).
- **Floors** are the measured `decisions on-GCD`, truncated to two decimals, from the first clean run; raised when
  content improves, never lowered except with a named cause recorded beside the number.
- **The leveling rule** (user, 2026-10-19; re-pin R22; owner policy R41, 2026-11-05): wowsims is the oracle, so the
  pack's own idle at 60 (LIVE60) is correct and L60's limit is `max(6 s, LIVE60)`; the lower brackets keep the 6 s bar.
  A recipe `leveling` or `extra` line is only a real rotation ability cast for a genuine need, never a filler to pass
  the bar. An idle window with nothing useful to cast is correct: that bracket gets a measured per-bracket limit with
  the named cause `nothing useful to cast: <what is cooling / what is up>`.
- **The replay's limits** (`tests/Game/harness/replay.lua`): no cast bars (casts at their completion, zero lag), no
  regen ticks (powers are the log's after-values), the target's swings not replayed (the tank exports log them since
  central fix 13; GAP AH), a white swing's outcome one landing lag after its swing (its rage at the swing), the execute
  phase by time (the last 20% of the fight), our own health not replayed (reads full), one weapon. Auras show their
  real durations (the log's to a natural fade, the declared one to an early removal). A cooldown ends at its cast's log
  timestamp plus the cooldown (the ready-time ruling).
- **CI.** `.github/workflows/check.yml` runs `make check`'s checks (not the type check), so the replay and leveling
  gates and the 3-fight loop lines run in CI; the 20-fight gates (`#loop`, `#party` and the class tags) do not.
  `make gate` (local only, under a machine-wide lock) is the merge gate: `make check` then every 20-fight loop; a change
  touching no `src/` file merges on `make check` alone (loop lines cannot move).

Every pack's current floors, as the specs in the tree set them (0.7, pins e5a9cd2a2d; the replay's `agreement`
counts ticks, the gate reads `decisions on-GCD`). The Ready column is each replay's `wowsims timing` floor
(`ws.READY` in `tests/Forever/helpers/wowsims.lua`, the floored median and count of the real decisions outside every
tolerance, named cause beside each). The live idle limits (`LIVE60` and the L10/L40 brackets, `max(6, LIVE60)` at 60)
sit in each `tests/Forever/wowsims_<class>_spec.lua` with their causes, the loop floors in
`tests/Forever/helpers/pack_gate.lua` (`M.FLICKER`: flicker, retracted, readyShort and heldReady per pack); the measured values come from
`make test-wowsims` and `make gate` and are not copied here, because a copy goes stale at the next pin. The solo
lines above are the integ/0.7 gate log (38daebe33, default arm); the table's floors change only with a named cause
beside the number (DEVELOPMENT.md).

| Pack | Replay floor (decisions on-GCD) | Ready floor (median s, count) |
| --- | --- | --- |
| Arms (wowsims.com) | 0.88 | 1.81, 2 |
| Fury (wowsims.com) | 0.86 | 0.42, 14 |
| Protection (wowsims.com), Warrior | 0.92 | 0.37, 4 |
| Feral (wowsims.com) | 0.96 | 0.40, 10 |
| Guardian (wowsims.com) | 0.63 | 1.76, 55 |
| Balance (wowsims.com) | 0.97 | 0.26, 22 |
| Assassination (wowsims.com) | 0.97 | 0.20, 35 |
| Combat (wowsims.com) | 0.99 | 0.24, 21 |
| Subtlety (wowsims.com) | 0.98 | 0.17, 40 |
| Retribution (wowsims.com) | 0.93 | 0.10, 7 |
| Protection (wowsims.com), Paladin | 0.95 | 0.43, 1 |
| Enhancement (wowsims.com) | 0.96 | 0.38, 34 |
| Elemental (wowsims.com) | 0.89 | 2.20, 3 |
| Beast Mastery (wowsims.com) | 0.95 | 0.46, 28 |
| Marksmanship (wowsims.com) | 0.98 | 0.32, 22 |
| Survival (wowsims.com) | 0.94 | 0.29, 22 |
| Arcane (wowsims.com) | 0.95 | 0.76, 9 |
| Fire (wowsims.com) | 0.96 | 0.45, 10 |
| Frostfire (wowsims.com) | 0.96 | 0.42, 9 |
| Shadow (wowsims.com) | 1.00 | 1.50, 36 |
| Smite (wowsims.com) | 0.93 | 0.70, 11 |
| Affliction (wowsims.com) | 0.83 | 0.00, 0 |
| SM Ruin (wowsims.com) | 0.78 | 0.20, 8 |
| Demonology (wowsims.com) | 0.87 | 0.00, 0 |
| Shadow Brand (wowsims.com) | 0.71 | 0.20, 1 |
| Destruction (wowsims.com) | 0.90 | 0.00, 0 |

Recorded deviations (each one's reason in the named file):
- Every pack (API-forced, `tools/wowsims/apl.lua` rules 10, 11, 13): `fight_remains` answers unknown (target health
  is secret), distance is a bracket from range checks, an off-GCD automatic cooldown shows as soon as it is ready; the
  sim does not predict avoidance (wowsims rolls it); our own health reads full while secret; mana is a bounded belief
  where the client keeps it secret.
- Warrior (`tools/wowsims/specs/warrior_*.lua`): Stance Dance and Recklessness keep wowsims's defaults (off); the
  Protection replay's top disagreements are replay limits (the decision instant at a cooldown's end, an exact tie at
  the GCD's length, Shatter Curse at 50% health).
- Druid (`druid_*.lua`, `Druid.lua`): Lacerate's cost per Shredding Attacks rank from the wowsims log (13), not the
  DB2's 6 a rank (ruling: wowsims is the oracle); Primal Fury at 1/2 an average, not wowsims's 50% roll.
- Rogue (`rogue_*.lua`, `rogue_world.lua`): the energy floor seeded from `floor(lo)` and an unknown regen tick phase
  (GAP Y); Improved Sinister Strike at 1/2 scaled from the whole talent's DB2 value.
- Paladin (`paladin_*.lua`): Benediction and Holy Conduit partial ranks from wowsims's per-rank curves (the DB2 holds
  rank 1 only); mana from blocks and hits not modelled (GAP AG).
- Shaman (`shaman_enhancement.lua`, `Shaman.lua`): Fire Nova at the DB2's 520 where wowsims has 375 (retry now that GAP V
  is fixed); Flame Shock 21 s with Call of Flame from wowsims's spell data (the DB2 shows no such effect).
- Hunter (`hunter_*.lua`, `Hunter.lua`): Multi-Shot keeps the DB2's 0.5 s cast (wowsims: instant); Resourcefulness rank
  1 from wowsims's data (30%); percent-of-base costs on each class's level-60 base mana; Beast Mastery and Marksmanship
  run one wowsims APL, so their lines match.
- Mage (`mage_*.lua`, `Mage.lua`, `mage_world.lua`): Arcane Blast's 1.5 s cast and 15 s charges from wowsims's data and
  log over the DB2's 2.5 s and 8 s (ruling M9; the charges' price floor(fraction x 1213), wowsims's 181 x (1 + 1.75 n));
  Read Ley Line a High Order Skyborne racial (unknown for the exports' Human); Master of Elements' refunds unbelieved
  (crits unseen, mana secret); the worlds' Mage is trainer-taught (no book ranks), as wowsims's; wowsims clips
  Evocation at >= 99% mana (interruptIf), the translator drops channelSpell.interruptIf (shared gap, reported), the
  world clips by wowsims's rule. Frostfire: Fingers of Frost's grant (a Chill's 15% roll) is unseen, so the sim spends
  a charge on every damage cast (wowsims: none on the cast that granted them); the worlds' crits ignore Shatter (the
  harness's one crit rate); the world grants Fingers of Frost at Frostfire Bolt's cast end, wowsims at its hit about
  0.8 s later (the harness has no travel time: a shared limit); `includeReactionTime` on the Fingers of Frost read
  ignored (rule 5).
- Warlock (`warlock_*.lua`, `Warlock.lua`, `warlock_world.lua`): `fight_remains` reads 3600 s, so the end-of-fight
  Bane of Agony and Amplify Curse lines never fire and Bane of Doom goes up whenever it is down (API-forced, rule 10;
  wowsims switches in a fight's last minute: most of SM Ruin's, Demonology's, Shadow Brand's and Destruction's replay
  disagreements); the target's Shadow Vulnerability and Demonic Brand charges are unreadable (the brand kept its full
  10 s; Shadow Bolt's `onCrit` models Shadow Vulnerability, but the bolt's outcome lands about 1 s after its success,
  past Events/Rows.lua's cast window, so a DoT tick's crit in its frame can set it: a known deviation until central fix
  32's travel time); wowsims's pet-spell costs (115, 160) kept verbatim (ruling W7); before
  Incinerate (40) Destruction, and below Searing Pain (18) Demonology, fall through to Life Tap; before the Demonic
  Brand talent both Demonology packs lead with Searing Pain.
- Priest (`priest_*.lua`, `Priest.lua`, `priest_world.lua`): Devouring Plague 24 s and Shadow Word: Death 18 s from
  wowsims's data and log over the DB2's 60 s and 15 s (ruling M9's precedent); Smite's down-ranked Holy Fire and Smite
  (rank 5 below 20% mana) at the top rank (rule 5 ignores `rank`: shared gap, owner ruling); Mind Flay's interruptIf
  dropped (its third tick is the channel's end); the wand's Shoot one shot a wand speed long; Shadow's ready times sit
  1.5 s early after each Mind Flay (the next icon ready at the GCD's end inside the channel).

CPU and memory, release to release (`r.cpuMean`/p99 of the 3- and 20-fight lines, process CPU ms per Update; `make
bench`'s bytes per Update; both measured on this machine one run after the other, so compare the columns, not the
absolute numbers with other tables):

| 3-fight line (seeds 1-3 unless named) | v0.1.1-rc.1 (hand-built lists) cpu mean / p99 ms | now (wowsims.com packs) cpu mean / p99 ms |
| --- | --- | --- |
| Arms seeds 1-3 | 3.68 / 13.38 | 4.04 / 13.69 |
| Arms seeds 4-6 | 3.33 / 10.81 | 3.66 / 11.87 |
| Feral | 2.76 / 10.55 | 4.99 / 19.20 |
| Guardian | 2.49 / 8.92 | 2.22 / 9.11 |
| Balance | 1.61 / 7.26 | 2.05 / 8.45 |
| Assassination | 2.64 / 9.39 | 2.46 / 7.74 |
| Combat | 2.51 / 8.96 | 2.64 / 8.62 |
| Subtlety | 3.14 / 11.66 | 2.61 / 9.03 |
| Retribution | 1.33 / 4.41 | 1.86 / 6.55 |
| Protection (Paladin) | 1.28 / 4.05 | 1.54 / 5.76 |
| Enhancement | 1.16 / 4.29 | 2.11 / 6.77 |
| Beast Mastery | 1.06 / 3.95 | 1.63 / 5.66 |
| Marksmanship | 1.00 / 3.91 | 1.65 / 6.22 |
| Survival | 0.94 / 3.92 | 1.80 / 6.52 |

| `make bench` (headless Arms, 6 fights, need off) | v0.1.1-rc.1 | now |
| --- | --- | --- |
| ms per Update, mean / p95 / max | 2.595 / 3.520 / 10.925 (n 4631) | 2.812 / 3.886 / 12.670 (n 5285) |
| B per Update, direct, mean / p95 / max | 6 / 206 / 640 | 2 / 80 / 240 |
| B per Update, Driver coroutine, mean / p95 / max | 20 / 206 / 7424 | 19 / 80 / 7674 |
| B per UNIT_COMBAT, mean / p95 / max | 28.7 / 80.0 / 504.0 | 29.5 / 80.0 / 504.0 |

Every line stays under the 10 ms mean bar. Between the two the packs changed (hand-built -> translated) and the
belief gained work (outcomes, swing credits, the range bracket, mana bounds); the runs do not separate the two. Feral
rises most (2.76 -> 4.99 ms), the mana specs about half again, Assassination and Subtlety fall. The bench's bytes per
Update fell (direct p95 206 -> 80), its time per Update rose 8% over more Updates (n 4631 -> 5285). The 20-fight lines
were not re-run at v0.1.1-rc.1 (the 3-fight lines are the like-for-like set `make check` runs).

## Remotes

`origin` is the fork (github.com/zmsl/hekili). Upstream, fetch only:

```
git remote add upstream https://github.com/Hekili/hekili.git
git remote set-url --push upstream no_push
```

## In game

Each addon gets its own AddOns link, at its folder in `src/`, not at the repository root. From an elevated Windows
prompt, in the client's `Interface\AddOns` folder, remove the old link and create the eleven:

```
rmdir Hekili
mklink /D Hekili \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili
mklink /D Hekili_Shared \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Shared
mklink /D Hekili_Warrior \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Warrior
mklink /D Hekili_Druid \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Druid
mklink /D Hekili_Rogue \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Rogue
mklink /D Hekili_Paladin \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Paladin
mklink /D Hekili_Shaman \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Shaman
mklink /D Hekili_Hunter \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Hunter
mklink /D Hekili_Mage \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Mage
mklink /D Hekili_Priest \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Priest
mklink /D Hekili_Warlock \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Warlock
```

Then restart the client fully (a moved addon is not picked up by `/reload`).

### Specs (one spec per talent tree; `/reload` after the update, no client restart)

The client reports one pseudo-spec per class, so each class pack registers a spec per talent tree and the active spec
follows the tree with the most points: the spec activated for that tree, else its first spec.
1. **Rogue:** `/hekili` shows Assassination, Combat and Subtlety nodes with their icons; Subtlety's page has "Backstab
   Builder", Combat's does not; the shared preferences ("Bleeds on Trash", "Vanish to Re-open") are on all three.
2. **First login after the update (any class):** the active spec is the tree with the most points (Snapshot:
   `spec: <key> (dominant)` on the first pass, `(stored)` after a `/reload`); the old thresholds (e.g. "Bleeds on Trash"
   if you changed it) appear in every supported spec of the class; your previous priority choice is kept.
3. **Override:** press "Activate Subtlety" on Subtlety's page (or `/hekili spec subtlety`); the displays switch to its
   priority, the page shows the gold "Active" marker, the tree lists Subtlety first with a gold highlight; `/reload`
   keeps it; a respec into another tree switches to that tree's spec, and back restores Subtlety.
4. **Priorities:** each priority sits under its spec's node in the tree (the Warrior's Arms, Fury, Protection);
   exporting Fury and importing it on the same character binds it to Fury.
5. **Druid:** Feral is selected for a Feral build; `/hekili spec guardian` switches to the bear priority; choosing
   Restoration hides the displays, its page says "No priorities on Forever for Restoration", and no "modules loaded"
   warning appears when casting. Is the client's Druid pseudo-spec 1483 (assumed; it now only keys the legacy
   migration, as Hunter 1484, Paladin 1486, Rogue 1488 and Shaman 1489 do)?
6. **Warrior:** Arms, Fury and Protection run their "(wowsims.com)" defaults; Arms's page carries Stance Dance and
   Recklessness, Fury's Rend Weave and Recklessness, Protection's none. The DB2
   puts Improved Slam (12862) on Fury and Improved Thunder Clap (12287) on Arms: does the client's talent frame agree?
   (They count toward those trees' points.)
7. **Paladin and Shaman:** a Paladin with mostly Holy points, or a Shaman with mostly Restoration points,
   lands on an idle unsupported spec (no displays) until you pick another with `/hekili spec` or the dropdown.
8. Report the Snapshot's first lines (`VSCopy`) for each character if anything differs.

### Checkpoints (in game; consolidated from the wowsims packs plan's lanes and fixes)

The checkpoint list moved to `docs/dev/ingame-ledger.md` (one table: id, what to look for, why it matters,
status), with the long-term in-game items. The Paladin (P1-P13), Shaman (S1-S11) and Hunter (H1-H21) checkpoints are with
their gate lines above.

`make accuracy` (dev-only, not part of gate or check; `tools/accuracy/`): every loop and wowsims spec file runs once under the
gate lock (`run.sh`, nproc - 2 jobs, `wrap.lua` as a busted helper so the specs' own helpers print structured lines)
and `report.lua` writes `.accuracy/report.json` and `.accuracy/report.md` (gitignored): per spec the three seed sets
(1-20, 21-40, 41-60) and their worst, the wowsims replay agreement and floor, ready-time median and misses, live idle per
level, cpu/calibration/bytes, and a reported-only "crowded target (39 others)" run beside the solo one. `none` = expected
but not printed, `n/a` = no wowsims preset. The line parsers are `tools/accuracy/parse.lua`, tested by `tests/accuracy_parse_spec.lua`.
