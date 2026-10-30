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
  - `src/ForeverProbe/`: the dev-only in-game probe addon (its own conventions; outside `tests/helpers/addons.lua`, lint, format, typecheck and the boundary checks), never packaged (`.pkgmeta` ignores it, `tools/check_package.sh` and `tests/Forever/publication_spec.lua` fail on it); delete it when the addon is stable. In game it is linked like the others (`mklink /D ForeverProbe \\wsl.localhost\personal\home\zack\src\hekili\src\ForeverProbe`), its saved variables live at `_forever_/WTF/.../SavedVariables/ForeverProbe.lua`, and its launch-day kit `src/ForeverProbe/docs/launch-day.md` travels with it.

  Content reaches the engine only through the public `Hekili` object (the registration API, `State`, `Class`,
  `Client`, and `Hekili:GetLocale` for its text; `tests/boundary_spec.lua`). Every TOC's `## Version` is `@project-version@`; the packager stamps the release tag into every one (one zip, one version); the core's ContentAPI
  (`CONTENT_API` in `Engine/Content.lua`, matched against each content TOC's `## X-Hekili-ContentAPI`) bumps only when
  the Schema or the content surface changes. The core's modules:
  - root: `Hekili.toc`, `Hekili.lua` (the addon object), `Bindings.xml`, `embeds.xml`;
  - `Engine/Sim/`: upstream's simulation (`Core`, `State`, `Scripts`, `Events`, `Targets`, `Constants`, `Utils`);
  - `Engine/Schema/`: the class/race/shared registration API (`Spec`, `Races`, `Shared`, `Threat`), the engine core the
    boundary spec scans;
  - `UI/`: the display core and editor widgets (`UI`, `Formatting`, `MultilineEditor`, `PopupSlider`), the display
    style registry (`Styles`), the shared "what to show" (`Resolve`) and the styles themselves (`Styles/Classic`,
    `Styles/Timeline`); architecture §7;
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
  and copies its scalars (`enabled`, `autoSnapshot`, `screenshot`), so a setter that writes one of those calls it again.
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
`scripts/busted_parallel.sh`: one busted process per spec file, each file's output in path order (files that ran no
test skipped), then the summed counts. `make test` and `make test-<tag>` run `$(nproc)` files at a time; `make gate`
runs all seven tags in one call capped at `nproc - 2` for the whole gate (`BUSTED_JOBS`), under the machine-wide
`flock /tmp/hekili-gate.lock`. So each 20-fight pack is its own file (`tests/Forever/loop_<class>_<pack>_spec.lua`;
the class's `loop_<class>_spec.lua` keeps the boot checks and the 3-fight `#slow` gates), and the gate is bounded by
its slowest file: `druid_harness_spec.lua`'s seven `#druid` scenarios (345 s under the gate's load), then
`loop_warrior_spec.lua` (#loop and #party, 292 s) and Feral (303 s); `make gate` 694 s, `make check` 263 s here. One
spec file at one tag: `.lua/bin/busted --tags=druid tests/Forever/loop_druid_feral_spec.lua`.
`make gate-ab` (the gate once per providers arm, provider arms recorded in `.ab/`, never failed) and `make cdv-coverage`
(the Cooldown Manager coverage report, dev-only) are described in `docs/dev/providers-ab.md`, with the two
experimental options and their Snapshot audit lines.
The CPU budget (`pack_gate.health`, `r.cpuMean <= 10` ms, p99 reported) is process CPU time (`os.clock` around each
Update in `tests/Game/harness/loop.lua`), so other processes waiting for a core do not count; shared cores (SMT,
cache) still raise it: Arms reads 4.1 ms alone, wall clock the same, and 6.1-6.7 ms in `make check`'s 16-wide run.

`make check`'s 6-fight Arms gate is two files of 3 fights (`tests/Forever/loop_warrior_spec.lua`, seeds 1-3, and
`loop_warrior_late_spec.lua`, seeds 4-6), so it prints three `Arms solo:` lines (`tests/Forever/arms_recs_spec.lua`
repeats seeds 1-3 against its every-slot fixture). Each fight seeds its own world and the
boot carries nothing between fights, so the halves play the same fights as the old single run.
The gate runs Arms (wowsims.com), the Arms default since the wowsims packs plan's Warrior swap (the hand-built Arms,
Fury and Protection lists retired), on the world's wowsims build (Spearing Strike and Berserker Rage in the kit). Its
lines (central fix 23, the pre-pull guards; 20 fights: agreement 0.966, flicker 1.51/min, oracle 1.07):

```
Arms solo: fights=3 agreement 0.966 (2466 ticks); react median 0 p90 0 never 0.019; refused per 100 [cost 16.0 (oracle 21.9, unmatched 0.5)], episodes 3.65/min; dps A/B 1.022; ... [seeds 1-3]
Arms solo: fights=3 agreement 0.985 (2487 ticks); react median 0 p90 0 never 0.050; refused per 100 [cost 16.3 (oracle 16.0, unmatched 0.0)], episodes 3.62/min; dps A/B 1.000; ... [seeds 4-6]
Arms solo: fights=20 agreement 0.966 (16858 ticks); react median 0 p90 0 never 0.038; refused per 100 [cost 13.3 (oracle 18.2, unmatched 1.0)], episodes 2.78/min; dps A/B 0.975; ...
Arms party: fights=10 agreement 0.975 (4432 ticks); react median 0 p90 0 never 0.005; refused per 100 [cost 4.6 (oracle 12.5, unmatched 0.0)], episodes 0.88/min; dps A/B 1.008; ...
```

`make test-loop` also runs Fury (wowsims.com) 20 fights at level 60 and 24 (`loop_warrior_fury_spec.lua`,
`loop_warrior_fury24_spec.lua`, `helpers/fury_gate.lua`): Arms never waits on Heroic Strike (`rage>=90`), Fury does
(`rage.current>=40`), so its flicker/min is the on-next-swing strike's jitter gate (central fix 21: L60 agreement 0.934,
flicker 1.71/min, oracle 0.56; L24 0.908, 3.31/min, oracle 2.16).

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
`FLICKER_K` (1.5): redundant with the floors today, it tightens the bar when a change lowers the oracle's own flicker.
`HEKILI_LOOP_HOLD=1 make test-<tag>` runs the display-side hold experiment (`; hold on`, floors not applied); as
expected it turns the Arms 20-fight gate red (agreement, unmatched cost refusals) and the Fury gates and two leveling
gates red (react p90, idle). `HEKILI_LOOP_HOLD=3` (or `o.steady`) turns on the shipped steady icons instead (the
spec's experimental `steadyIcons`, off by default, measured as hold3 in the flicker design study; `; steady icons on`,
floors not applied): the loop then reads the held output itself, not a harness copy. `HEKILI_LOOP_STEADY=N` (or
`o.steady = N`) sets the updates to hold (1 to 3; `; steady icons on (hold N)` for N above 1).

Before the pull it shows Bloodrage and Battle Shout only (no positions headless, so no Charge). Seeds 1-3 used to show
casting refusals (7.0 per 100, the oracle's 0.5): presses during Slam's 1.5 s cast while the world's client sent only
a cast's success; since fix 22 the world sends the cast's start too, and the refusals are gone (gap BD records the
cast-boundary flicker that replaced them).

`tests/Forever/loop_druid_spec.lua` runs 3 fights a Druid pack in `make check` (seeds 1-3, the `#slow` tag) and 20 in
`make test-druid` (`#druid`), each asserting its flagged lines ran (`r.focus > 0`). Every Druid spec runs its
wowsims.com default (wowsims packs plan, Tasks 7b and 7g; the hand-built lists retired); Feral and Balance are gated by
`pack_gate.gate`, Guardian is reported (engine health and focus asserted, not the agreement): its first icon waits on
rage the usability ladder cannot place. Current lines (forever b0a5f8ee, central fix 22):

```
Feral solo: fights=3 agreement 0.924 (2336 ticks); react median 0 p90 0 never 0.031; refused per 100 [], episodes 0.00/min; dps A/B 1.049; ... [seeds 1-3]
Guardian solo: fights=3 agreement 0.899 (2631 ticks); react median 0 p90 1 never 0.019; refused per 100 [cost 8.1 (oracle 8.8, unmatched 0.0)], episodes 1.71/min; dps A/B 1.003; ...
Balance solo: fights=3 agreement 0.961 (2705 ticks); react median 0 p90 1 never 0.009; refused per 100 [casting 73.7 (oracle 70.7, unmatched 5.0), cost 0.6 (oracle 2.5, unmatched 0.0)], episodes 9.21/min; dps A/B 0.920; ... [seeds 1-3]
Feral solo: fights=20 agreement 0.941 (16304 ticks); react median 0 p90 0 never 0.043; refused per 100 [cost 1.4 (oracle 2.3, unmatched 1.1)], episodes 0.05/min; dps A/B 1.024; ...
Guardian solo: fights=20 agreement 0.850 (17957 ticks); react median 0 p90 1 never 0.018; refused per 100 [cost 25.1 (oracle 11.6, unmatched 15.2)], episodes 4.26/min; dps A/B 1.011; ...
Balance solo: fights=20 agreement 0.980 (17833 ticks); react median 0 p90 1 never 0.019; refused per 100 [casting 72.3 (oracle 70.7, unmatched 8.5), cost 0.9 (oracle 2.9, unmatched 0.4)], episodes 9.76/min; dps A/B 0.980; ...
```

The Feral and Balance worlds keep the wowsims logs' mana pools and five-second rule (22 a second outside it).

`tests/Forever/loop_rogue_spec.lua` runs 3 fights a Rogue spec in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-rogue` (`#rogue`), each on its "<Spec> (wowsims.com)" pack (wowsims packs plan, Task 8), gated by
`pack_gate.gate` and asserting its flagged lines ran (`r.focus > 0`: Slice and Dice at tier 1 in every pack). The
worlds carry the wowsims.com builds' abilities and talents (Subtlety Hemo has no Ghostly Strike); the replay and
leveling gates are `tests/Forever/wowsims_rogue_spec.lua`. The lines (the forever gate on 51a0b1ac, central fixes 1-17):

```
Combat solo: fights=3 agreement 0.991 (2158 ticks); react median 0 p90 0 never 0.000; refused per 100 [requires:in combat 1.3 (oracle 1.3, unmatched 0.0)], episodes 0.28/min; dps A/B 1.023; ... [seeds 1-3]
Assassination solo: fights=3 agreement 0.991 (2373 ticks); react median 0 p90 0 never 0.040; refused per 100 [requires:in combat 1.7 (oracle 2.5, unmatched 0.0)], episodes 0.25/min; dps A/B 0.973; ... [seeds 1-3]
Subtlety solo: fights=3 agreement 0.974 (2041 ticks); react median 0 p90 0 never 0.063; refused per 100 [requires:in combat 1.9 (oracle 1.2, unmatched 0.0)], episodes 0.44/min; dps A/B 0.969; ... [seeds 1-3]
Combat solo: fights=20 agreement 0.992 (14181 ticks); react median 0 p90 0 never 0.000; refused per 100 [requires:in combat 0.8 (oracle 1.3, unmatched 0.0)], episodes 0.17/min; dps A/B 0.999; ...
Assassination solo: fights=20 agreement 0.996 (15402 ticks); react median 0 p90 0 never 0.007; refused per 100 [requires:in combat 1.7 (oracle 1.7, unmatched 0.0)], episodes 0.25/min; dps A/B 1.000; ...
Subtlety solo: fights=20 agreement 0.973 (13157 ticks); react median 0 p90 0 never 0.037; refused per 100 [requires:in combat 1.5 (oracle 1.4, unmatched 0.0)], episodes 0.36/min; dps A/B 1.000; ...
```

`tests/Forever/loop_paladin_spec.lua` runs 3 fights a Paladin pack in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-paladin` (`#paladin`), asserting its flagged lines ran (Retribution: the seal twist at tier 1; Protection:
Seal of Fury and Holy Shield at tier 2). The mob swings at us in both worlds: Holy Shield raises the block chance and
each block spends a charge (the world's class-neutral `taking`/`took`); our landed swing spends an Echo (`landed`); mana
runs under the five-second rule (`fsr`: wowsims's logs, Retribution 13.65 spirit / 8.25 mp5, Protection 17.38 / 0, an empty pool; Task 7 floors Retribution 0.9 and Protection 0.8, gap AB). Both packs are gated by `pack_gate.gate`; both are wowsims.com packs since the
wowsims packs plan, Task 9 (the hand-built lists retired). Retribution (wowsims.com)'s swing-gap fillers carry
wowsims's own `mana.pct>=10`, judged on the secret-mana belief; each fight starts with the mana the last one left,
regenerated through the 30 s gap (GAP X, closed: the 20-fight line was 0.911, never 0.226, while fights restarted at
full mana). The holy_shock list is gone with the hand-built Retribution list; Hammer of Wrath's window is not
exercised by the solo worlds. The runs (central fixes 1-23):

```
Retribution solo: fights=3 agreement 0.999 (2371 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.018; ... [seeds 1-3]
Protection solo: fights=3 agreement 0.998 (2418 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.993; ... [seeds 1-3]
Retribution solo: fights=20 agreement 0.999 (17049 ticks); react median 0 p90 0 never 0.000; refused per 100 [cost 1.5 (oracle 11.1, unmatched 0.0)], episodes 0.16/min; dps A/B 1.026; ...
Protection solo: fights=20 agreement 0.990 (17589 ticks); react median 0 p90 0 never 0.000; refused per 100 [cost 0.9 (oracle 9.1, unmatched 0.0)], episodes 0.10/min; dps A/B 1.022; ...
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
wowsims's logs measure it per spec (Mana Spring and Mindfulness inside Elemental's, Improved Stormstrike's casting share
in Enhancement's), UNMEASURED pool, no Water Shield or potions), so most in-combat ticks show no icon on either side.
The imbues are not in the solo world's kit (it has no weapon enchant read). The world's costs are each rank's (DB2),
with Shamanistic Focus when the build has it, Stormstrike's 121 (wowsims/forever's), and the shocks' cooldown and Flame
Shock's duration from the booted talents. The lines below run Enhancement (wowsims.com) (wowsims packs plan, Task 10,
the forever gate on 51a0b1ac: Fire Nova at the DB2's 520). `tests/Forever/wowsims_shaman_spec.lua` replays wowsims's
own fight (floor 0.98; 0.989 of 88 with Rage of the Farseer, held) and runs the levels 10, 40 and 60 (40 pending: GAP AB, the secret-mana floor's last mana).
Elemental (wowsims.com) (Task 14) runs the same gates on the Elemental world (20 yd, wowsims's 5590 mana and regen:
29.75 a second casting, 42.5 more outside the five-second rule): replay floor 0.93 (0.937 of 95), live L10 0.0,
L40 0.0, L60 5.0 s (LIVE60 5.0), flicker floor 0.6. The lines:

```
Enhancement solo: fights=3 agreement 1.000 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [cost 1.1 (oracle 11.9, unmatched 0.0)], episodes 0.11/min; dps A/B 0.964; ... [seeds 1-3]
Enhancement solo: fights=20 agreement 0.998 (18040 ticks); react median 0 p90 0 never 0.000; refused per 100 [cost 1.3 (oracle 14.6, unmatched 0.0)], episodes 0.12/min; dps A/B 1.014; ... flicker 1.13/min (oracle 1.10); ... top [stormstrike -> rage_of_the_farseer 44; rage_of_the_farseer -> stormstrike 1]; ...
Elemental solo: fights=3 agreement 0.993 (2706 ticks); react median 0 p90 1 never 0.000; refused per 100 [casting 59.6 (oracle 56.5, unmatched 0.5)], episodes 10.86/min; dps A/B 1.025; ... [seeds 1-3]
Elemental solo: fights=20 agreement 0.996 (18040 ticks); react median 0 p90 0 never 0.001; refused per 100 [casting 58.6 (oracle 54.8, unmatched 0.5), cost 0.0 (oracle 5.0, unmatched 0.0)], episodes 9.38/min; dps A/B 0.998; ... flicker 0.55/min (oracle 0.17); ...
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
the character's Resourcefulness and Efficiency (the leveling brackets; the replay's builds). Their mana regen is wowsims's logs' (Beast Mastery 7.94 casting / 15.88 outside; Marksmanship and Survival 0 / 15.88, Resourcefulness adding half the 15.88 while casting for 30 s, rolled on a landed ability at the crit rate counted in the logs; the loop worlds apply no cost cut, gap BV). Raptor Strike's cooldown
starts at its swing (class-neutral: a queued strike's cooldown). Each fight's fresh world gets the pack's aspect at the
pull (the character keeps a permanent buff between fights). Neither side dies (shaman_world's workaround for the loop's
missing kill). The kit's ranges are DB2's (`RANGE`: Hunter Range 8-35, Combat Range 0-5). "The Hunter at range, then
in melee" runs Survival at 25 yd, then 5 yd: its four `target.within5` lines stay shut while the bracket reads [8, 35],
open at [0, 5], and the bracket holds when every read goes secret. Mana is secret in combat, so the belief holds its
lower bound and the worlds idle 0.820 (Beast Mastery, Marksmanship) and 0.711 (Survival) of the time at 3 fights. The
lines (the forever gate on 51a0b1ac, central fixes 1-17; the hand-built lists' were 0.983/0.986/0.945 at 3 fights):

```
Beast Mastery solo: fights=3 agreement 1.000 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.997; ... [seeds 1-3]
Marksmanship solo: fights=3 agreement 1.000 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.997; ... [seeds 1-3]
Survival solo: fights=3 agreement 0.996 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.991; ... [seeds 1-3]
Beast Mastery solo: fights=20 agreement 1.000 (18040 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.012; ...
Marksmanship solo: fights=20 agreement 1.000 (18040 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.012; ...
Survival solo: fights=20 agreement 0.999 (18040 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.003; ...
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
  30 yards: about 2.5 / 0 / 5 / true / false in melee, 21.5 / 8 / 35 / false / true at 11 yd; and
  `C_Spell.GetSpellInfo(14268).maxRange` (Wing Clip) reads 5, not 0.
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
reported). The lines (on 0ce5d1a4 + Task 12 and its lane review fixes; Frostfire's on 3e104ce9 + Task FFB):

```
Arcane solo: fights=3 agreement 0.987 (2706 ticks); react median 0 p90 1 never 0.000; refused per 100 [casting 79.7 (oracle 78.3, unmatched 0.9), cost 2.2 (oracle 4.3, unmatched 0.2)], episodes 12.20/min; dps A/B 1.136; ... [seeds 1-3]
Fire solo: fights=3 agreement 0.993 (2706 ticks); react median 0 p90 1 never 0.000; refused per 100 [casting 68.4 (oracle 68.8, unmatched 0.6), cost 9.8 (oracle 9.3, unmatched 1.9)], episodes 6.21/min; dps A/B 1.030; ... [seeds 1-3]
Arcane solo: fights=20 agreement 0.994 (18040 ticks); react median 0 p90 1 never 0.000; refused per 100 [casting 77.2 (oracle 77.5, unmatched 0.7), cost 4.6 (oracle 4.8, unmatched 0.6)], episodes 10.83/min; dps A/B 1.025; ...
Fire solo: fights=20 agreement 0.992 (18040 ticks); react median 0 p90 0 never 0.009; refused per 100 [casting 68.0 (oracle 66.8, unmatched 0.7), cost 10.3 (oracle 12.3, unmatched 1.3)], episodes 5.77/min; dps A/B 1.018; ...
Frostfire solo: fights=3 agreement 0.992 (2706 ticks); react median 0 p90 0 never 0.022; refused per 100 [casting 74.8 (oracle 75.0, unmatched 1.6)], episodes 6.43/min; dps A/B 1.026; ... [seeds 1-3]
Frostfire solo: fights=20 agreement 0.958 (18040 ticks); react median 0 p90 1 never 0.034; refused per 100 [casting 75.0 (oracle 73.5, unmatched 1.7), cost 0.3 (oracle 2.8, unmatched 0.1)], episodes 5.44/min; dps A/B 0.986; ...
```

`tests/Forever/loop_priest_spec.lua` runs 3 fights of each Priest pack in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-priest` (`#priest`, `loop_priest_shadow_spec.lua`, `loop_priest_smite_spec.lua`), gated by `pack_gate.solo`
and asserting that some focus line ran (Shadow Word: Pain, Devouring Plague and Holy Fire upkeep at tier 2, Inner Focus
at tier 1: ruling P5). The packs are Shadow (wowsims.com) on Shadow and Smite (wowsims.com) on Discipline (the Smite
build's dominant tree; Holy unsupported), Task 14 of the wowsims packs plan, from wowsims/forever's two Priest builds
(`ui/specs/priest/dps/builds/testing.build.json`, `smite_testing.build.json`); their replay and leveling gates
`tests/Forever/wowsims_priest_spec.lua`. The worlds (`tests/Forever/helpers/priest_world.lua`) cast at 20 yd with cast
bars and channels (Mind Flay, Penance, the wand's Shoot as one shot a wand speed long); Shadow starts in Shadowform; the
pools and regen are the logs' (Shadow 4711, Smite 6151). Flicker floors (pack_gate `FLICKER`): Shadow 0.3 (0.27, oracle
0.15), Smite 0.5 (0.45, oracle 0.12; retracted 0.9 from 0.83, oracle 0.63: the wand's Shoot at the 10% mana edge). The
lines (on 30e92574 + Task 14):

```
Shadow solo: fights=3 agreement 0.996 (2706 ticks); react median 0 p90 1 never 0.000; refused per 100 [casting 59.5 (oracle 58.7, unmatched 2.0)], episodes 6.10/min; dps A/B 1.000; ... [seeds 1-3]
Smite solo: fights=3 agreement 0.973 (2706 ticks); react median 0 p90 1 never 0.007; refused per 100 [casting 83.8 (oracle 83.9, unmatched 2.4)], episodes 43.90/min; dps A/B 1.065; ... [seeds 1-3]
Shadow solo: fights=20 agreement 0.993 (18040 ticks); react median 0 p90 2 never 0.000; refused per 100 [casting 48.4 (oracle 46.4, unmatched 3.4)], episodes 3.39/min; dps A/B 1.001; ...
Smite solo: fights=20 agreement 0.972 (18040 ticks); react median 0 p90 1 never 0.002; refused per 100 [casting 84.1 (oracle 84.2, unmatched 2.3)], episodes 44.28/min; dps A/B 0.988; ...
```

`tests/Forever/loop_warlock_spec.lua` runs 3 fights of each Warlock pack in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-warlock` (`#warlock`, `loop_warlock_<pack>_spec.lua`), gated by `pack_gate.solo` and asserting that some
focus line ran (the DoTs, Banes, curses and Searing Pain's brand upkeep at tier 2; Shadow Bolt on Shadow Trance and
Soul Fire on Decimation at tier 1). The packs are Affliction, SM Ruin (Affliction's second), Demonology, Shadow Brand
(Demonology's second) and Destruction (wowsims.com), Task 13 of the wowsims packs plan, from wowsims/forever's five
Warlock builds; their replay and leveling gates `tests/Forever/wowsims_warlock_spec.lua`. The worlds
(`tests/Forever/helpers/warlock_world.lua`) cast at 25 yd with cast bars and channels, the build's demon out from the
pull (its mana and regen from the logs), the Soul Shards in the bags; the pools are the logs' (5353, Demonology's 6156).
Flicker floors (pack_gate `FLICKER`, 20 fights, K 1.6): Affliction 1.6 (1.60, oracle 1.60), SM Ruin 4.9 (4.81, oracle
4.66), Demonology 3.4 (3.36, oracle 3.38), Shadow Brand 2.9 (2.81, oracle 2.69), Destruction 4.6 (4.51, oracle 3.38),
retracted 0 each. The lines (the end-of-lane gate, on 06eec227 + Task 13):

```
Affliction solo: fights=3 agreement 0.997 (2706 ticks); react median 0 p90 0 never 0.005; refused per 100 [casting 76.9 (oracle 76.3, unmatched 0.2)], episodes 9.76/min; dps A/B 0.996; ... [seeds 1-3]
SM Ruin solo: fights=3 agreement 0.995 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 66.7 (oracle 66.5, unmatched 0.4)], episodes 12.97/min; dps A/B 0.999; ... [seeds 1-3]
Demonology solo: fights=3 agreement 0.998 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 3.4 (oracle 3.4, unmatched 0.0)], episodes 1.33/min; dps A/B 1.000; ... [seeds 1-3]
Shadow Brand solo: fights=3 agreement 0.999 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 60.0 (oracle 60.0, unmatched 0.1)], episodes 11.86/min; dps A/B 1.000; ... [seeds 1-3]
Destruction solo: fights=3 agreement 0.989 (2706 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 41.7 (oracle 41.5, unmatched 0.2)], episodes 10.31/min; dps A/B 0.992; ... [seeds 1-3]
Affliction solo: fights=20 agreement 0.995 (18040 ticks); react median 0 p90 0 never 0.001; refused per 100 [casting 77.4 (oracle 77.5, unmatched 0.3)], episodes 9.84/min; dps A/B 1.012; ...
SM Ruin solo: fights=20 agreement 0.996 (18040 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 65.9 (oracle 65.8, unmatched 0.3)], episodes 12.46/min; dps A/B 0.998; ...
Demonology solo: fights=20 agreement 0.998 (18040 ticks); react median 0 p90 0 never 0.001; refused per 100 [casting 3.2 (oracle 3.3, unmatched 0.0)], episodes 1.23/min; dps A/B 1.001; ...
Shadow Brand solo: fights=20 agreement 0.998 (18040 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 59.6 (oracle 59.4, unmatched 0.2)], episodes 12.17/min; dps A/B 0.992; ...
Destruction solo: fights=20 agreement 0.987 (18040 ticks); react median 0 p90 0 never 0.000; refused per 100 [casting 41.3 (oracle 41.6, unmatched 0.7)], episodes 10.19/min; dps A/B 1.006; ...
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
- **The pin.** `M.PIN` in `tools/wowsims/export.lua` (d33930d04030c3f556582f31949f1f22c17da0e4) is the wowsims/forever
  commit every request and log comes from (`tests/Forever/wowsims_pin_spec.lua`); the export refuses a checkout at
  another commit. To move it: check the checkout out at the new commit, bump `M.PIN`, `make wowsims-cli`, re-export
  every recipe, `make wowsims-packs && make packs`, and re-measure every floor and LIVE60 (each move named in the
  floor's comment).
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
- **The leveling rule** (user, 2026-10-19): wowsims is the oracle, so the pack's own idle at 60 (LIVE60) is correct;
  every bracket's limit is `max(6 s, LIVE60)`, and a lower bracket over it gets a recipe `leveling` filler that is
  silent at 60, never a higher limit.
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

Every pack's current lines (the forever gate on 51a0b1ac; the replay's `agreement` counts ticks, the gate reads
`decisions on-GCD`; Measured re-read on forever-readytime, where the replay's cooldown ends at its log timestamp:
Retribution 0.877 -> 0.912, Guardian 0.782 -> 0.808, Enhancement 0.909 -> 0.989, Warrior Protection 0.904 -> 0.979,
their floors ratcheted to 0.91, 0.80, 0.98 and 0.97). The Ready columns are each replay's `wowsims timing` line (the
headless loop design §12): the shown offset |b| over the timed in-scope on-GCD decisions, the real ones outside every
tolerance (the floored median and count, `ws.READY`), and the decisions whose key never showed first. Balance's,
Feral's, Warrior Protection's and Combat's median floors rose in review round 1 (0.32 -> 0.71, 0.11 -> 0.26, 0.15 ->
0.50, 0.20 -> 0.28) from the metric alone: the cost class now counts a crossing up to one tick before the cast, and an
on-GCD decision's walk back is no longer cut by an off-GCD decision's poll; behaviour is unchanged. The Rogue
decisions left real (0.26-0.30 s from the crossing: G7 + one tick + the tick phase) stay real by the specified window
and are the harness's G7 measure until G7 is captured in game. "Limit" is what the spec file gates every bracket at,
`max(6, LIVE60)` with the spec's LIVE60 constant in brackets; "Worst idle" is the measurement at each level, in seconds
(the Arms, Fury, Guardian,
Retribution, Paladin Protection and Survival idles re-measured in the final review fixes, on-GCD presses only):

| Pack | Replay floor | Measured (decisions) | Limit (LIVE60 constant) | Worst idle (measured) | Ready \|b\| median / p90 | Ready real (median, count) | Never shown | Ready floor |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Arms (wowsims.com) | 0.91 | 0.910 (67) | 9.2 (9.2) | L10 5.6, L40 5.6, L60 9.2 | 0.000 / 0.200 | 0.800, 6 | 6 | 0.80, 6 |
| Fury (wowsims.com) | 0.93 | 0.933 (60) | 6.8 (6.8); 7.6 below 60 (FURY_LIVE_LEVELING) | L10 7.6, L40 2.4, L60 6.8 | 0.190 / 1.490 | 0.480, 32 | 11 | 0.48, 32 |
| Protection (wowsims.com), Warrior | 0.97 | 0.979 (94) | 6 (5.4) | L10 5.6, L40 5.4, L60 5.4 | 0.000 / 0.030 | 0.500, 5 | 2 | 0.50, 5 |
| Feral (wowsims.com) | 0.95 | 0.955 (88) | 6 (4.2) | L20 4.0, L40 3.8, L60 3.8 | 0.000 / 0.160 | 0.260, 4 | 4 | 0.26, 4 |
| Guardian (wowsims.com) | 0.80 | 0.808 (78) | 10.0 (10.0) | L10 10.0, L40 9.6, L60 8.4 | 0.440 / 2.500 | 0.540, 40 | 12 | 0.54, 40 |
| Balance (wowsims.com) | 0.85 | 0.855 (55) | 6 (1.4) | L10 1.6, L40 1.4, L60 1.4 | 0.010 / 0.780 | 0.710, 17 | 5 | 0.71, 17 |
| Assassination (wowsims.com) | 0.98 | 0.982 (57) | 6 (5.0) | L10 5.2, L40 5.0, L60 5.0 | 0.180 / 0.270 | 0.200, 30 | 1 | 0.20, 30 |
| Combat (wowsims.com) | 0.95 | 0.972 (71) | 6 (4.8) | L10 5.6, L40 4.8, L60 4.0 | 0.150 / 0.280 | 0.280, 16 | 2 | 0.28, 16 |
| Subtlety (wowsims.com) | 0.98 | 0.988 (82) | 6 (3.8) | L10 5.6, L40 4.6, L60 4.2 | 0.150 / 0.240 | 0.200, 45 | 1 | 0.20, 45 |
| Retribution (wowsims.com) | 0.91 | 0.912 (57) | 8.4 (8.4) | L10 4.4, L40 7.0, L60 2.8 | 0.000 / 0.110 | 0.250, 1 | 5 | 0.25, 1 |
| Protection (wowsims.com), Paladin | 0.62 | 0.625 (48) | 17.8 (17.8) | L10 8.6, L40 11.0, L60 11.8 | 0.000 / 1.040 | 0.540, 12 | 18 | 0.54, 12 |
| Enhancement (wowsims.com) | 0.98 | 0.989 (88) | 8.0 (8.0) | L10 1.6, L40 pending (GAP AB), L60 8.0 | 0.000 / 0.000 | 0.960, 3 | 1 | 0.96, 3 |
| Beast Mastery (wowsims.com) | 1.00 | 1.000 (27) | 6 (5.4) | L10 4.6, L40 4.6, L60 5.4 | 0.000 / 0.320 | 0.320, 5 | 0 | 0.32, 5 |
| Marksmanship (wowsims.com) | 0.92 | 0.929 (42) | 12.8 (12.8) | L10 4.6, L40 3.6, L60 12.8 | 0.000 / 0.150 | 0.150, 8 | 3 | 0.15, 8 |
| Survival (wowsims.com) | 0.97 | 0.976 (41) | 6 (0) | L10 4.6, L40 0.2, L60 0.2 | 0.000 / 0.360 | 0.140, 10 | 1 | 0.14, 10 |
| Arcane (wowsims.com) | 0.81 | 0.814 (59) | 6 (0) | L10 0.0, L40 0.0, L60 0.0 | 0.100 / 0.970 | 0.450, 21 | 11 | 0.47, 21 |
| Fire (wowsims.com) | 0.82 | 0.825 (63) | 12.6 (12.6) | L10 0.0, L40 0.2, L60 12.6 | 0.130 / 1.610 | 0.370, 30 | 11 | 0.37, 31 |
| Frostfire (wowsims.com) | 0.89 | 0.891 (55) | 10.8 (10.8) | L10 5.6, L40 0.2, L60 10.8 | 0.300 / 1.010 | 0.380, 31 | 6 | 0.38, 31 |
| Shadow (wowsims.com) | 1.00 | 1.000 (85) | 6 (1.8) | L10 0.0, L40 0.0, L60 1.8 | 0.000 / 1.600 | 1.500, 36 | 0 | 1.50, 36 |
| Smite (wowsims.com) | 0.93 | 0.932 (44) | 6 (0.2) | L10 0.0, L40 0.2, L60 0.2 | 0.400 / 3.100 | 0.500, 27 | 3 | 0.50, 27 |
| Elemental (wowsims.com) | 0.93 | 0.937 (95) | 6 (5.0) | L10 0.0, L40 0.0, L60 5.0 (Lava Burst r4 and Elemental Mastery learned at 1: not in the DB2) | 0.380 / 0.980 | 0.480, 54 | 6 | 0.48, 54 |
| Affliction (wowsims.com) | 0.87 | 0.877 (81) | 6 (0.2) | L10 0.2, L40 0.2, L60 0.2 | 0.000 / 1.000 | 1.000, 21 | 10 | 1.00, 21 |
| SM Ruin (wowsims.com) | 0.70 | 0.702 (94) | 6 (0.2) | L10 0.0, L40 0.0, L60 0.2 | 0.000 / 1.000 | 0.900, 18 | 28 | 0.90, 18 |
| Demonology (wowsims.com) | 0.77 | 0.776 (116) | 6 (0.2) | L10 0.2, L40 0.2, L60 0.2 | 0.000 / 0.000 | 0.100, 3 | 26 | 0.10, 3 |
| Shadow Brand (wowsims.com) | 0.73 | 0.735 (98) | 6 (0.2) | L10 0.0, L40 0.0, L60 0.2 | 0.000 / 1.000 | 0.900, 16 | 26 | 0.90, 16 |
| Destruction (wowsims.com) | 0.74 | 0.743 (109) | 6 (0.2) | L10 0.2, L40 0.2, L60 0.2 | 0.000 / 0.400 | 0.400, 17 | 28 | 0.40, 17 |

A LIVE60 constant above today's L60 measurement is an earlier measurement the spec keeps (Combat 4.8 vs 4.0,
Retribution 8.4 vs 2.8 by ruling P6, Paladin Protection 17.8 vs 11.8 from the untanked fight); limits are not lowered
in this task. Fury's 7.6 s below 60 and Guardian's 10.0 are leveling measurements above the L60 one
(docs/dev/wowsims-packs.md's recorded exceptions). LIVE60s above
6 s are wowsims's own play: Arms pools rage for Heroic Strike, Guardian waits on rage, Retribution and
Marksmanship spend themselves out of mana as wowsims's own fights do (ruling P6), Paladin Protection waits on mana
(the old untanked fight's 17.8 s), Enhancement's spending runs the mana out from 90 s, Fire's by 85 s (then waits on
Fire Blast's 340; Evocation on its 8-minute cooldown counts as usable), Frostfire's by about 80 s (then waits on
Frostfire Bolt's 314.5 and Fire Blast's 340).

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
  Read Ley Line (a Skyborne racial) dropped (rule 12: no Skyborne race pack); Master of Elements' refunds unbelieved
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
