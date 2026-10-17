# Repository layout

- `src/Hekili/` is the addon exactly as WoW loads it; paths inside `Hekili.toc` are relative to it. Nothing else
  ships, and nothing dev-only goes in it. Its modules:
  - root: `Hekili.toc`, `Hekili.lua` (the addon object), `Bindings.xml`, `embeds.xml`;
  - `Engine/Sim/`: upstream's simulation (`Core`, `State`, `Scripts`, `Events`, `Targets`, `Constants`, `Utils`);
  - `Engine/Schema/`: the class/race/shared registration API (`Spec`, `Races`, `Shared`), the engine core the
    boundary spec scans;
  - `UI/`: the display and editor widgets (`UI`, `Formatting`, `MultilineEditor`, `PopupSlider`);
  - `Options/` (the options panel and chat commands), `Virtual/` (VirtualState, the event and API facades),
    `Forever/` (the class, race and shared content), `Libs/` (embedded, untouched) and `Textures/`.

  An upstream merge lands new root files at the root; re-home them by hand.
- `tests/` holds the busted specs and their helpers, mirroring the source tree: the specs for
  `src/Hekili/Virtual/State/` are in `tests/Virtual/State/`, their helpers in `tests/Virtual/State/helpers/`, and so
  on. `tests/Virtual/State/helpers/load.lua` names the addon root once (`ROOT = "src/Hekili/"`).
- `tests/Virtual/harness/` is the combat harness (combat harness design §3): a seeded model of the Forever client
  (entities, behaviours, the world, the observer, scenarios) that drives VirtualState through the fakes, with the
  attribution gates (`solo_spec`, `group_spec`, `onus_spec`, `sweep_spec`). Its `fixtures/` are in-game /vslog dumps,
  every token row kept; `fixtures_spec` replays them and fits the observer's defaults to them. A new capture becomes a
  fixture with `lua5.1 tools/vslog_fixture.lua dump.txt "min,max,min,max" STRIKE=<id> DOT=<id>` (the weapon damage
  UnitDamage read, our strike's and DoT's spell IDs) plus a header comment; a fit outside tolerance is retuned in the
  same change. The Druid scenarios (`tests/Forever/helpers/druid_world.lua`, `druid_vs.lua`, `druid_harness_spec.lua`) run on the same
  harness, the class read from `Druid.lua`: a tenth of their fights is `#slow`, the design's counts are `#druid`, run
  only by `make test-druid` (about 190 s). The gates make `busted` take about 160 s; `make test-fast` skips the
  `#slow` gates.
- `tools/`, `docs/` and `archive/` stay at the repository root, with the lint, test and type-check configs
  (`.busted`, `.luacheckrc`, `.luarc.json`). Run every tool and `busted` from the root.

## Checks

`make bootstrap` once (Lua 5.1 + busted/luacheck/luacov into `.lua/`; StyLua and LuaLS from `mise.toml`), then
`make check` before every commit. StyLua formats only our files (`.styluaignore` lists upstream Hekili, which keeps
its own style). If `fmt-check` still fails after `make fmt`, run `make fmt` again: StyLua 2.5.2 takes two passes on a
call whose argument is a long single-line table.
`tests/boundary_spec.lua` scans `Virtual/` and `Engine/Schema/` strictly, and holds each `Engine/Sim/` file to its
per-token counts in `tests/boundary_baseline.lua` (a ceiling per file, not a line lock). Regenerate the baseline with
`.lua/bin/lua tools/boundary_baseline.lua` only when removing an inherited leak, or when new content registers a key a
Sim identifier already uses (`git blame` the Sim line and say so in the commit); never to admit a leak.

## In game

The AddOns link must point at `src/Hekili`, not at the repository root. From an elevated Windows prompt, in the
client's `Interface\AddOns` folder, remove the old link and re-create it:

```
rmdir Hekili
mklink /D Hekili \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili
```

Then restart the client fully (a moved addon is not picked up by `/reload`).
