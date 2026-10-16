# Repository layout

- `src/Hekili/` is the addon exactly as WoW loads it: `Hekili.toc`, the root `.lua` and `.xml` files, `Libs/`,
  `Options/`, `UI/`, `Textures/`, `Virtual/` and `Forever/`. Paths inside `Hekili.toc` are relative to it. Nothing
  else ships, and nothing dev-only goes in it.
- `tests/` holds the busted specs and their helpers, mirroring the source tree: the specs for
  `src/Hekili/Virtual/State/` are in `tests/Virtual/State/`, their helpers in `tests/Virtual/State/helpers/`, and so
  on. `tests/Virtual/State/helpers/load.lua` names the addon root once (`ROOT = "src/Hekili/"`).
- `tools/`, `docs/` and `archive/` stay at the repository root, with the lint, test and type-check configs
  (`.busted`, `.luacheckrc`, `.luarc.json`). Run every tool and `busted` from the root.

## Checks

`make bootstrap` once (Lua 5.1 + busted/luacheck/luacov into `.lua/`; StyLua and LuaLS from `mise.toml`), then
`make check` before every commit. StyLua formats only our files (`.styluaignore` lists upstream Hekili, which keeps
its own style). If `fmt-check` still fails after `make fmt`, run `make fmt` again: StyLua 2.5.2 takes two passes on a
call whose argument is a long single-line table.

## In game

The AddOns link must point at `src/Hekili`, not at the repository root. From an elevated Windows prompt, in the
client's `Interface\AddOns` folder, remove the old link and re-create it:

```
rmdir Hekili
mklink /D Hekili \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili
```

Then restart the client fully (a moved addon is not picked up by `/reload`).
