# Repository layout

How the layers and the engine port fit together: `docs/dev/architecture.md`.

- `src/` holds the addons exactly as WoW loads them, each in its own folder with its TOC (paths inside a TOC are
  relative to its folder); nothing else ships, and nothing dev-only goes in them. `tests/helpers/addons.lua` lists them
  in dependency order, and every headless loader, spec and tool reads their files from it:
  - `src/Hekili/`: the core (the engine, the belief, the UI and options);
  - `src/Hekili_Shared/`: the content every class shares (`Shared/`: auras, consumables, items) and the race packs
    (`Races/`); `## Dependencies: Hekili`, `## LoadOnDemand: 1`, loaded on demand by the core's `Engine/Content.lua`
    at login, first (before the class pack, and for a class with no pack too);
  - `src/Hekili_Warrior/`, `src/Hekili_Druid/`: one class pack each (the class file, its RegisterPack
    blocks written by `make packs`); `## LoadOnDemand: 1`, loaded at login by the core's `Engine/Content.lua` for the
    player's class.
    `## Group: Hekili` nests each content addon under Hekili in the in-game addon list.

  Content reaches the engine only through the public `Hekili` object (the registration API, `State`, `Class`,
  `Client`; `tests/boundary_spec.lua`). A class release bumps the pack addon's `## Version`; the core's ContentAPI
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
  - `Options/` (the options panel, chat commands and the styles' shared option builders, `StyleOptions`), `Game/` (the game as the addon knows it: `API/` the facade,
    `Events/`, `State/` the belief, VirtualState), `Libs/` (embedded, untouched) and `Textures/`.

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
  attribution gates (`solo_spec`, `group_spec`, `onus_spec`, `sweep_spec`). Its `fixtures/` are in-game /vslog dumps,
  every token row kept; `fixtures_spec` replays them and fits the observer's defaults to them. A new capture becomes a
  fixture with `lua5.1 tools/vslog_fixture.lua dump.txt "min,max,min,max" STRIKE=<id> DOT=<id>` (the weapon damage
  UnitDamage read, our strike's and DoT's spell IDs) plus a header comment; a fit outside tolerance is retuned in the
  same change. The Druid scenarios (`tests/Forever/helpers/druid_world.lua`, `druid_vs.lua`, `druid_harness_spec.lua`) run on the same
  harness, the class read from `Druid.lua`: a tenth of their fights is `#slow`, the design's counts are `#druid`, run
  only by `make test-druid` (about 190 s). `make test` runs one busted process per spec file in parallel
  (`scripts/busted_parallel.sh`; `make test-serial` is the one-process run, about 160 s); `make test-fast` skips the
  `#slow` gates. `make bench` (`tests/Forever/bench_spec.lua`, `#bench`, not in `make check`) prints ms per Update and bytes per
  Update and per UNIT_COMBAT for headless Arms over 6 fights.
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
`tools/packs/`). CI (`.github/workflows/check.yml`) runs the same checks except the type check.

`make check`'s 6-fight Arms gate is two files of 3 fights (`tests/Forever/loop_warrior_spec.lua`, seeds 1-3, and
`loop_warrior_late_spec.lua`, seeds 4-6), so it prints three `Arms solo:` lines (`tests/Forever/arms_recs_spec.lua`
repeats seeds 1-3 against its every-slot fixture). Each fight seeds its own world and the
boot carries nothing between fights, so the halves play the same fights as the old single run (4524 ticks in all).
At the split (forever 98e718bd; the single 6-fight line was agreement 0.953, never 0.073, cost 17.1 (oracle 16.4),
dps A/B 0.999):

```
Arms solo: fights=3 agreement 0.968 (2266 ticks); react median 0 p90 1 never 0.053; refused per 100 [cost 17.4 (oracle 17.4)], episodes 2.65/min; dps A/B 0.954; ... [seeds 1-3]
Arms solo: fights=3 agreement 0.938 (2258 ticks); react median 0 p90 1 never 0.095; refused per 100 [cost 16.8 (oracle 15.4)], episodes 2.52/min; dps A/B 1.044; ... [seeds 4-6]
```

A deliberate pack or APL change re-records the fixture in the same commit:
`ARMS_RECS=record .lua/bin/busted tests/Forever/arms_recs_spec.lua`.

The display style fixtures in `tests/Forever/fixtures/` re-record the same way:
`CLASSIC_DRAW=record .lua/bin/busted tests/Forever/display_style_spec.lua` (`classic_draw.lua`),
`STYLE_OPTIONS=record .lua/bin/busted tests/Forever/style_options_spec.lua` (`classic_options.lua`) and
`TIMELINE_DRAW=record .lua/bin/busted tests/Forever/display_style_spec.lua` (`timeline_draw.lua`). The classic ones
prove a refactor left classic unchanged, so they are recorded at a base commit (the one before the change) in a
temporary worktree with the spec copied in, then copied back; never re-record them in place to make a change pass. The
timeline fixture is re-recorded in place, in the commit that deliberately changes the timeline's look.

## Remotes

`origin` is the fork (github.com/zmsl/hekili). Upstream, fetch only:

```
git remote add upstream https://github.com/Hekili/hekili.git
git remote set-url --push upstream no_push
```

## In game

Each addon gets its own AddOns link, at its folder in `src/`, not at the repository root. From an elevated Windows
prompt, in the client's `Interface\AddOns` folder, remove the old link and create the four:

```
rmdir Hekili
mklink /D Hekili \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili
mklink /D Hekili_Shared \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Shared
mklink /D Hekili_Warrior \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Warrior
mklink /D Hekili_Druid \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Druid
```

Then restart the client fully (a moved addon is not picked up by `/reload`).
