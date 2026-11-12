# Embedded libraries

Every library `embeds.xml` loads is vendored here (vendored 2026-10-14; no CurseForge packager externals).
Policy: vendor every library `embeds.xml` includes, whether or not its upstream declares Forever support.
Forever = WoW Forever client 1.60.1.70338, `## Interface: 16001`.

"Forever support upstream" is yes only when the upstream itself names Forever (a `16001` TOC line or Forever code).
A library's own `.toc` is not loaded (Hekili loads the files through `embeds.xml`), so its `## Interface` line is
evidence only. "Load gate" is any early return or branch keyed on build, interface or project ID.

The ten Ace3 folders carry Ace3's `LICENSE.txt` (BSD-style, Ace3 Development Team) copied into each folder.

| Library | Upstream | Pin | Licence | Author credit | Forever support upstream | Load gate |
|---|---|---|---|---|---|---|
| LibStub | https://github.com/WoWUIDev/Ace3 (`LibStub/`) | Ace3 tag `Release-r1403`, commit d295b12 (2026-08-12) | Public domain (file header); Ace3 `LICENSE.txt` copied | Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke | No (Ace3.toc lists 11508 ... 120007, not 16001) | None |
| CallbackHandler-1.0 | Ace3 (`CallbackHandler-1.0/`) | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceAddon-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceGUI-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None at load; `widgets/AceGUIWidget-ColorPicker.lua:16` inverts alpha when `WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE` |
| AceConsole-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceLocale-3.0 | Ace3 (`AceLocale-3.0/`) | Ace3 `Release-r1403`, d295b12 (MINOR 6; fetched 2026-10-25 from raw.githubusercontent.com/WoWUIDev/Ace3/d295b12f8b889a30e86e0e901c5494df4b149c49) | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None (reads the client's `GetLocale()` once at load, and `GAME_LOCALE`, a translator's override, when set; enGB maps to enUS) |
| AceConfig-3.0 (Registry, Cmd, Dialog) | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceSerializer-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceDB-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceDBOptions-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| LibSharedMedia-3.0 | https://repos.wowace.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0 | MINOR 12000004 (wowace trunk mirrored 2026-10-14) | LGPL v2.1 (file header; quoted in `LICENSE-NOTE.md`) | Elkano | No | None found |
| AceGUI-3.0-SharedMediaWidgets | https://repos.wowace.com/wow/ace-gui-3-0-shared-media-widgets/trunk/AceGUI-3.0-SharedMediaWidgets | DataVersion 9004, widgetVersion 13; wowace trunk mirrored 2026-10-14 (no `$Id`) | None stated upstream (no file, no header) | Yssaril | No | None |
| AceGUI-3.0_SFX-Widgets | https://github.com/SFX-WoW/AceGUI-3.0_SFX-Widgets | commit 450c923 (2026-10-05) | Custom permissive-with-conditions, `LICENSE.txt` (Copyright StormFX) | StormFX | Yes: TOC `## Interface: 11509, 16001, ...`; CHANGELOG "Forever: 16001" | None |
| LibSpellRange-1.0 | https://github.com/ascott18/LibSpellRange-1.0 | commit 49da263 (2024-08-19), TOC version 1.0.17 | None upstream (no licence file or header) | Cybeloras of Aerie Peak (ascott18) | No (TOC 100001) | Feature branch, not build-keyed: uses `C_Spell.IsSpellInRange` when present, else spellbook fallbacks |
| LibRangeCheck-3.0 | https://github.com/WeakAuras/LibRangeCheck-3.0 | v39 (upstream 3f9e454) + Hekili Forever patch: min-range spells get a within-minRange checker (createCheckerList; each patched line marked `Hekili Forever patch`); upstream PR WeakAuras/LibRangeCheck-3.0#60; our MINOR is 40 so this copy wins over a stock 39 loaded by another addon (re-vendor when #60 ships). Upstream commit 3f9e454 (2026-11-07, "Check for secret values in Forever as well"; MINOR 39; fetched 2026-11-11 from raw.githubusercontent.com/WeakAuras/LibRangeCheck-3.0/3f9e454971a011d08fc1b5c73c0a0ad4168c2f44) | MIT, `LICENSE` | The WoWUIDev Community | Yes: `isForever = interfaceVersion >= 16000 and < 20000` (main file line 59); a secret GUID keys its cache by the unit token, Forever shares the Era range tables | Branches on `GetBuildInfo` and `WOW_PROJECT_ID` (Era/Forever, TBC, Wrath, Cata, Mists, Midnight); no early return. Main file moved up from the repo's nested `LibRangeCheck-3.0/` folder (upstream `.pkgmeta` `move-folders`) |
| LibDeflate | https://github.com/SafeteeWoW/LibDeflate | commit afc3b78 (2021-05-05) | zlib, `LICENSE.txt` | Haoqian He (Safetyy) | No (TOC 80300) | None |
| LibDataBroker-1.1 | https://github.com/tekkub/libdatabroker-1-1 | commit 1a63ede (2008-07-31), MINOR 4 | None upstream (no licence file or header) | tekkub | No | None |
| LibDBIcon-1.0 | https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0 | MINOR 57 (wowace trunk mirrored 2026-10-14) | None stated upstream (no file, no header) | wowace project libdbicon-1-0 (no author named in source) | No | None found |
| LibDualSpec-1.0 | https://github.com/AdiAddons/LibDualSpec-1.0 | commit 71dcd66 (2026-09-20) | BSD-style with a no-standalone-redistribution clause (file header; quoted in `LICENSE-NOTE.md`) | Adirelle, Nebula | Yes: TOC `## Interface: 11509, 16001, ...`; Forever branches at lines 72-77 and 518 | `GetBuildInfo` 16000-20000 forces primary/secondary (dual spec) mode, then a Forever `GetProfileSpecialization` using `GetNumSpecGroups` |
| LibCustomGlow-1.0 | https://github.com/Stanzilla/LibCustomGlow | commit 4f8f5c2 (2026-07-17) | MIT, `LICENSE` | deezo, Benjamin Staneck (Stanzilla) | No (TOC 120001, 120000) | `isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` picks retail vs classic code paths (lines 16, 24, 151); no early return. Repo folder `LibCustomGlow` vendored as `LibCustomGlow-1.0` to match `embeds.xml` |
| LibTranslit-1.0 | https://github.com/Vardex/LibTranslit | commit 66a5aa7 (2022-11-11) | LGPL v3, `COPYING` + `COPYING.LESSER` | Vardex | No (TOC 100000) | None |
| VirtualGameAPI-1.0 | This repository | folded into `VirtualState/Facade.lua` (VirtualState Phase 1); the folder keeps only its `LICENSE` and `README.md` and is not loaded | MIT, `LICENSE` | Hekili Forever port | Yes (written for Forever) | None |

## Translated content

The class packs' "(wowsims.com)" priorities (the generated blocks in each `Hekili_<Class>/<Class>.lua`) are translated
from the APLs and presets of wowsims/forever (https://github.com/wowsims/forever, commit d33930d040, 2026-10-18), MIT,
Copyright (c) 2022 wowsims team. Its copyright and permission notice ships as `Hekili/LICENSE-wowsims.txt` (the
copy in `src/Hekili/`; every class pack ships in the same zip).

## Licence compatibility with GPLv3 or later

The project as a whole is GPLv3 or later (GNU General Public License, either version 3 of the License, or at your
option any later version; agreement with the original author); each library keeps its own licence. The rest
(Ace3 BSD-style, LibStub public domain, LibSharedMedia-3.0 LGPL v2.1, LibTranslit-1.0 LGPL v3, LibDeflate zlib, the
MIT libraries LibRangeCheck-3.0, LibCustomGlow-1.0 and VirtualGameAPI-1.0, and the MIT wowsims/forever translations) is compatible. Only the exceptions are
listed.

| Library | Issue |
|---|---|
| LibDualSpec-1.0 | BSD-style plus a no-standalone-redistribution clause: licence conflict, replace or remove before v0.1.0 if still bundled |
| AceGUI-3.0_SFX-Widgets | custom licence, check terms |
| AceGUI-3.0-SharedMediaWidgets | licence unstated, ask or replace |
| LibSpellRange-1.0 | licence unstated, ask or replace |
| LibDataBroker-1.1 | licence unstated, ask or replace |
| LibDBIcon-1.0 | licence unstated, ask or replace |
