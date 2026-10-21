# Developing Hekili Forever

- **Layout and conventions:** `docs/dev/layout.md`.
- **Setup:** `make bootstrap` once (Lua 5.1, busted, luacheck and luacov into `.lua/`), then `make check` before every
  commit (lint, format, type check, tests, generated packs up to date).
- **Priorities:** each class pack's "(wowsims.com)" priorities are generated from the recipes under `tools/wowsims/`;
  `make wowsims-packs packs` regenerates them and `make gate` runs the headless replay and 20-fight loops that floor
  them (`docs/dev/wowsims-packs.md`).
- **Packaging and releases:** `docs/publishing/README.md`.
- **In-game checks still open:** `docs/dev/ingame-ledger.md`.
