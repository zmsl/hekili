<!-- Ported from TacoDogForever docs/research/2026-10-14-hekili-libraries-for-forever.md (credit: TacoDogForever), copied here because that repo is being retired. -->
# Hekili's libraries: which solve problems for Taco Dog Forever on Forever

Research, 2026-10-14. Read-only: no addon code touched. Rule applied: never reinvent what a reputable community
library or the client already provides; vendor it with its licence and a credit line (CREDITS.md).

Sources: Hekili's `embeds.xml` and `.pkgmeta` (the library list and upstream URLs); call sites grepped in
`~/src/hekili` outside `Libs/` and `.claude/`; TDF's `src/` on main (plus the `p7-display` lane for glow and
notices); the reconciliation themes in `docs/research/2026-10-12-hekili-reconciliation/`; the Forever probe results
(`2026-10-13-probe-session-W-results.md`, PR7, PR11, PR15, PR19; `2026-10-14-probe-session-O-results.md`, O10); upstream
repositories and CurseForge pages fetched 2026-10-14 (URLs in the table and the appendix).

## Facts that decide "needed"

- **Core is library-free by design.** `src/TacoDogForever` has no `LibStub` call. Libraries today live only in the
  load-on-demand `TacoDogForever_Options` (LibStub, CallbackHandler, AceGUI, AceConfig, AceDB, AceDBOptions; Ace3
  Release-r1403, CREDITS.md). A library the core needs at render time (fonts, glow) would have to be embedded in core
  or taken softly (`LibStub(name, true)`).
- **Forever has these APIs plain:** `C_Spell.IsSpellInRange` (PR7: plain in combat, `wow_api_search` flavor forever),
  `C_Timer.After`, `C_ChatInfo.SendAddonMessage`, `C_ActionBar.FindSpellActionButtons`, `AddonCompartmentFrame`,
  `MenuUtil`, `UIFrameFade*`, `ActionButtonSpellAlertManager`. Absent: `ActionButton_ShowOverlayGlow`, `EasyMenu`,
  global `GetAddOnMetadata` (PR19). Other addons already load LibStub, LibDataBroker-1.1, LibDBIcon-1.0, AceAddon-3.0
  and LibSharedMedia-3.0 on the client (PR19), so those names resolve if present, but we should not rely on it.
- **Forever has dual specialisation** at level 40 (priest and rogue compendia) but PR15's spec-switch path is untested.
- **Hekili does not call many of its libraries.** In its current sources there are zero call sites for AceTimer,
  AceEvent, AceBucket, AceComm, AceHook, AceLocale, AceTab and LibChatAnims, and only a mixin for AceConsole and
  AceSerializer. Several are embedded but unused (they appear in `embeds.xml` or `.pkgmeta`). Hekili runs its own
  frame, `C_Timer.After` and its own event dispatch. That is a good indicator that parity does not need them.

## The table

"Forever status" is the upstream's own handling of Forever (TOC 16001), Midnight (12.x) and secret values, from commit
messages, TOC lines and CurseForge flavour tags. "Last activity" is the last push or file.

| Library | Upstream + licence | Last activity; Forever / Midnight status | Hekili use (call sites) | TDF today | Recommendation |
|---|---|---|---|---|---|
| LibStub | wowace / bundled with Ace3 ([Ace3](https://github.com/WoWUIDev/Ace3)); public domain | with Ace3 (2026-10-02) | `LibStub(...)` everywhere | `Options/Libs/LibStub` | ALREADY VENDORED |
| CallbackHandler-1.0 | wowace, in Ace3; Limited BSD ([LICENSE](https://raw.githubusercontent.com/WoWUIDev/Ace3/master/LICENSE.txt)) | with Ace3 | dependency of AceConfig, LSM, LDB | `Options/Libs/CallbackHandler-1.0` | ALREADY VENDORED |
| Ace3 as a whole | [WoWUIDev/Ace3](https://github.com/WoWUIDev/Ace3), Limited BSD ("stand-alone redistribution prohibited" clause; embedding with the notice is fine) | pushed 2026-10-02. TOC lists 16001 [Ace3.toc](https://raw.githubusercontent.com/WoWUIDev/Ace3/master/Ace3.toc). Forever commits: AceDB compat 2026-09-18 and 09-25, AceGUI ColorPicker alpha 2026-10-02. Secret handling: ChatThrottleLib secret fix 2026-08-05, Heading secret text 2026-08-26 | the framework | r1403 subset vendored in Options | ALREADY VENDORED, **but refresh it now (see "Ace3 refresh")** |
| AceGUI-3.0, AceConfig-3.0 (+Dialog/Registry/Cmd), AceDB-3.0, AceDBOptions-3.0 | Ace3 | as above | Options UI (UI.lua, Options.lua, Core.lua:59-73) | `Options/Libs` (AceDB minor 33; upstream is 39) | ALREADY VENDORED; refresh |
| AceAddon-3.0 | Ace3 | as above | `Hekili.lua:5` NewAddon with mixins | `Boot.lua` frame and `ns` (no addon object) | NOT NEEDED: it only hosts mixins and lifecycle; core is library-free and Boot.lua's staged-event frame is smaller and tested |
| AceConsole-3.0 | Ace3 | as above | `RegisterChatCommand` (Core.lua:78-79), `:Print` (76 calls) | `Boot.lua` `SLASH_TACODOGFOREVER1` + `A:Slash` (App.lua:1517), `G.print` | NOT NEEDED: our parser is 40 lines and covered by tests. If T26 ever needs quoted or link-aware arguments, vendor AceConsole then for `GetArgs` only |
| AceTimer-3.0 | Ace3 | as above | **zero** direct calls; Hekili uses `C_Timer.After` (Utils.lua:329) | `Refresh/Driver.lua`, `Scheduler.lua`, `Throttle.lua`: one OnUpdate driver, zero-alloc, measured | NOT NEEDED: allocates a table per timer, and the driver is the measured scheduler |
| AceEvent-3.0 | Ace3 | as above | zero direct calls (Hekili has its own frame) | `Sources/Sources.lua` stages observations into the log in order, flushed at the start of each OnUpdate | NOT NEEDED: immediate callback dispatch would break the staged, ordered observation log |
| AceBucket-3.0 | Ace3 | as above | zero calls (listed in `.pkgmeta` only) | dirty flags + once-per-frame rebuild (Views/Glow.lua) | NOT NEEDED |
| AceHook-3.0 | Ace3 | as above | zero calls | none by design (no secure hooks; Glow is a plain child frame) | NOT NEEDED: hooks spread taint; we avoid them on purpose |
| AceLocale-3.0 | Ace3 | as above | zero calls (`.pkgmeta` only; Hekili is English strings) | English strings in code | NOT NEEDED until a localisation decision exists (no gap row). Vendor then |
| AceTab-3.0 | Ace3 | as above (fix 2026-10-02) | zero calls | none | NOT NEEDED: tab completion for slash commands has no parity row |
| AceSerializer-3.0 | Ace3 | as above; pure Lua | share strings `TableToString` (Options.lua:9433, 9462) | none (persistence is the generated `SERIAL` layout in Model/Belief/Persist.lua, a different job) | VENDOR WHEN T16 (share strings, Phase 9: 05:C1/C3-C9, 08:OP2/OP3/OP36). Taken with LibDeflate |
| AceComm-3.0 (+ChatThrottleLib) | Ace3 | as above; ChatThrottleLib secret fix 2026-08-05; `C_ChatInfo.SendAddonMessage` exists on Forever | zero calls in current Hekili sources | none | NOT NEEDED now. VENDOR WHEN a "send a pack to a friend" feature is approved (no gap row: T16 is string import/export only) |
| LibSharedMedia-3.0 | wowace (Elkano); header says LGPL v2.1, CurseForge page says "All Rights Reserved" ([CF](https://www.curseforge.com/wow/addons/libsharedmedia-3-0)); mirror [NoobTaco](https://github.com/NoobTaco/LibSharedMedia-3.0) | CF file v12.1.x updated 2026-10-10, flavours include **Forever**; already present on the client from other addons (PR19). Header predates Forever; the mainline file-access flag is the only flavour check | fonts/textures/sounds for display text and borders (UI.lua:2480-2713, Options.lua:26) | Blizzard fonts only (`GameFont*`, Render/Text.lua); no media picker | VENDOR WHEN T20 (display styling: fonts, textures, "fonts/LSM", Phase 7) in the core as an optional dependency, with the licence question below settled first |
| AceGUI-3.0-SharedMediaWidgets | wowace; customised BSD ([CF](https://www.curseforge.com/wow/addons/ace-gui-3-0-shared-media-widgets)) | r65 2020-10-19, tags for Forever/12.1.x flavours; unchanged for 6 years, so stable rather than maintained | font/texture/sound pickers in Options | none | VENDOR WHEN T20 together with LibSharedMedia (the pickers are the only way to expose it in AceConfig) |
| AceGUI-3.0_SFX-Widgets | [SFX-WoW/AceGUI-3.0_SFX-Widgets](https://github.com/SFX-WoW/AceGUI-3.0_SFX-Widgets); custom StormFX licence (standalone or modified redistribution needs written permission) | pushed 2026-10-05; "Forever: 16001" TOC commit | `SFX-Info-URL` copyable-URL widget on help pages (Options.lua:8654-8718, 24 hits) | none | NOT NEEDED: an AceConfig `input` at full width is already copyable, and the licence is restrictive. Optional polish for T19 help tabs only |
| LibSpellRange-1.0 | [ascott18](https://github.com/ascott18/LibSpellRange-1.0); **no licence** (GitHub licence null) | pushed 2024-08-19. Since 2024 it delegates straight to `C_Spell.IsSpellInRange`; old spellbook scan only for older clients; no secret-value handling | `LSR.IsSpellInRange` for out-of-range tint and checks (State.lua:5659, 7666; UI.lua:1586; Classes.lua:2130) | `C_Spell.IsSpellInRange` directly (Sources/Target.lua, Nameplates.lua), plain in combat (PR7) | NOT NEEDED: Forever has the API the library wraps; no licence |
| LibRangeCheck-3.0 | [WeakAuras/LibRangeCheck-3.0](https://github.com/WeakAuras/LibRangeCheck-3.0); MIT | pushed 2026-09-28; **"Add checks for 'Forever' on all isEra checks" 2026-09-27**; Midnight: range caching disabled for secrets 2025-12-04 | target-count radius and range (Targets.lua:463, Events.lua:1349, UI.lua:1583) | lane p5-range-libs | ALREADY VENDORED (in flight) |
| LibDataBroker-1.1 | [tekkub](https://github.com/tekkub/libdatabroker-1-1); no licence file; CF "All Rights Reserved" | pushed 2015; stable 11-line registry, no API calls | minimap launcher (Core.lua:81, 138) | lane p5-range-libs | ALREADY VENDORED (in flight); note the missing licence in CREDITS |
| LibDBIcon-1.0 | wowace (Funkeh); Ace3-style BSD ([CF](https://www.curseforge.com/wow/addons/libdbicon-1-0)) | CF v12.1.x updated 2026-10-10, flavours include **Forever** | minimap button (Core.lua:159, Options.lua:25) | lane p5-range-libs | ALREADY VENDORED (in flight) |
| LibDualSpec-1.0 | [AdiAddons/LibDualSpec-1.0](https://github.com/AdiAddons/LibDualSpec-1.0); Adirelle BSD-style, no stand-alone redistribution | pushed 2026-09-20; **"Add support for Forever" 2026-09-19** ("GetNumSpecGroups for Forever", detects `isSpecBased=false` for builds 16000-20000). Not Midnight-specific | profile per spec group (Core.lua:65-67) | AceDB profiles only; G062 re-detects spec by events | VENDOR WHEN T27 (profiles and dual spec, Phase 8, 5 rows) and after PR15's spec-switch probe. Design note below |
| LibCompress | wowace; **GPL v2** ([CF](https://www.curseforge.com/wow/addons/libcompress)) | r87 2026-10-04 | decode legacy `Hekili:` strings only (Options.lua:9424-9460); LibDeflate is the live path | none | NOT NEEDED: legacy-format reader for a share format TDF never had; GPL v2 also blocks embedding if TDF's licence differs |
| LibDeflate | [SafeteeWoW/LibDeflate](https://github.com/SafeteeWoW/LibDeflate); zlib licence | pushed 2021-05-05; pure Lua, no client API except the print/addon-channel encoders; flavour-independent | `CompressDeflate` + `EncodeForPrint` / `EncodeForWoWAddonChannel` (Options.lua:9427-9452) | none | VENDOR WHEN T16 with AceSerializer (Phase 9). Chat link and message limits on Forever are untested, so probe a paste of a long string into the edit box first |
| LibCustomGlow-1.0 | [Stanzilla/LibCustomGlow](https://github.com/Stanzilla/LibCustomGlow); MIT | pushed 2026-07-17. "bump TOC for 12.0 (Midnight) and fix the compare-with-secret error" and "12.0.0 Curve Capability" (2026-01-25); "compatibility with classic variants" (2026-01-26); "12.1 namespaced AnimateTexCoords" (2026-07-17). No Forever commit | pixel, autocast and button glow styles on Hekili's icons (UI.lua:973, 1262-1268, 18 calls) | own overlay on the action buttons (Views/Glow.lua) and gold proc border on icons (Render/Glow.lua, lane p7-display); texture `CheckButtonHilight` | VENDOR WHEN T20's "glow styles" option is scheduled (pixel/autocast/button choices). Not before: the current two glows are plain textures with no animation. Test on Forever first; `ActionButton_ShowOverlayGlow` is absent, though `ActionButtonSpellAlertManager` exists |
| LibChatAnims | wowace; Ace3-style BSD ([CF](https://www.curseforge.com/wow/addons/libchatanims)) | CF v12.1.0 2026-10-04; no Forever tag in the fetched flavour list | none. It only replaces Blizzard's `UIFrameFlash` on chat tabs so the addon isn't blamed for taint | `Views/Notify.lua` (lane 7E): own frame, own fade, `print` fallback; no chat hooks | NOT NEEDED: TDF's notices never touch chat frames |
| LibTranslit-1.0 | [Vardex/LibTranslit](https://github.com/Vardex/LibTranslit); LGPL-3.0 | pushed 2022-11-11 | one call: `formatKey` turns Cyrillic spell names into SimC keys (Utils.lua:112-117) | pack keys are spell IDs and English keys, not localised names | NOT NEEDED: the only caller derives keys from localised names, which TDF never does |
| SpellFlashCore (+BigLibTimer) | [Tga123/SpellFlashCore](https://github.com/Tga123/SpellFlashCore) fork of BigRedBrent's; CF "Public Domain" (2018 file); fork has no licence file | fork pushed 2023-11-08; the copy Hekili embeds is 2024-09-15 with a hard gate `Build < 110000 -> return` (only 3.4.x is exempted), so **it does not even load on Forever's 16001 build**. No Midnight or secret-value work. It flashes buttons found by `GetActionInfo(slot)` | the "flash" option: `LSF.Flashable`, `FlashItem` (UI.lua:1376-1399) | TDF's own overlay on the action buttons via `C_ActionBar.FindSpellActionButtons` (Views/Glow.lua), a plain child frame, no protected call | NOT NEEDED: our glow already does what flash does, and the library is gated off, unmaintained and unlicensed |
| Masque (not embedded; `LibStub("Masque", true)`, UI.lua:2903) | Masque addon (upstream not checked) | not a vendored library, an optional integration | skinning Hekili's icons | none | NOT A LIBRARY: handle under T29 (third-party integrations) if wanted; soft `LibStub("Masque", true)` only |

## Ace3 refresh (the one urgent item)

The vendored AceDB-3.0 is **minor 33**; upstream is **minor 39**. Upstream's changes since are Forever-specific:
`charKey` becomes `UnitNameUnmodified("player")` (the name with the surname) and, with regional unique names on, the
realm part is replaced by a ruleset label or dropped ([Ace3 commits](https://github.com/WoWUIDev/Ace3/commits/master):
2026-09-18 "Compatibility with WoW Forever", 09-25 "Remove realmKey from charKey in WoW Forever", 09-25 "Swap UnitName for
UnitNameUnmodified"). `Options.CharKey` (Game/Options.lua:157) builds `"<UnitName> - <GetRealmName>"` by hand, because core reads
`TacoDogForeverDB` without Ace. Today the two agree. The moment Options is refreshed to upstream AceDB, the key AceDB
writes and the key core reads would differ, so a character would silently fall back to the Default profile in core.
Refresh both in one change: update `Libs/AceDB-3.0` (and AceGUI's ColorPicker alpha fix for T20 colours, AceGUI
Heading secret text, AceDBOptions limit change) and make `Options.CharKey` mirror AceDB 39's key, with a migration of
existing `profileKeys`. A unit test over the key function (pure logic) fits the TDD rule.

## Design points for the "vendor when" items

- **LibDualSpec (T27).** `EnhanceDatabase` needs the AceDB object, which exists only after the LOD Options addon loads;
  core reads the saved layout without Ace. Either core mirrors the dual-spec switch (reading the library's namespace
  in the saved table) or Options loads at login when a character has dual spec. Decide when T27 is planned, and run the
  PR15 spec-switch probe first.
- **LibSharedMedia (T20).** The header says LGPL v2.1, the CurseForge listing says "All Rights Reserved". Take the
  licence from the file header (it is what ElvUI and others rely on), keep the header intact, credit Elkano, and ask
  the maintainer to confirm if we want certainty. Core would use it softly: `LibStub("LibSharedMedia-3.0", true)`
  and fall back to the Blizzard fonts, so a missing library never breaks rendering.
- **LibDeflate + AceSerializer (T16).** Pipeline is serialise, deflate, print-encode, prefix (`TacoDog:` rather than
  Hekili's `Hekili:` so the two don't try to read each other's strings). AceSerializer serialises with no WoW API,
  and the strings contain only plain data, never secrets.

## Order of value

1. **Ace3 refresh** (AceDB 39 plus the key change): prevents a silent profile loss, costs one small lane. Do before
   anything else is vendored into Options.
2. **LibSharedMedia-3.0 + AceGUI-3.0-SharedMediaWidgets** (T20): fonts and textures for every text and icon style row,
   and the sound picker for alerts. The biggest block of display-styling parity for two libraries.
3. **AceSerializer-3.0 + LibDeflate** (T16, Phase 9, 11 rows): share strings and pack management; nothing in the client
   or in TDF does this today.
4. **LibDualSpec-1.0** (T27, Phase 8, 5 rows): small, but Forever-ready since 2026-09-19; held for the PR15 probe and the
   core-versus-Options design point.
5. **LibCustomGlow-1.0** (T20 glow styles): only when pixel, autocast and button glow choices are wanted. The two glows we
   have are plain textures with no dependencies.
6. Everything else: not needed (AceAddon, AceConsole, AceTimer, AceEvent, AceBucket, AceHook, AceLocale, AceTab, SFX
   widgets, LibSpellRange, LibCompress, LibChatAnims, LibTranslit, SpellFlashCore), or already decided (LibRangeCheck,
   LibDataBroker, LibDBIcon, Ace3 subset). AceComm waits for a decision to build pack sending.

## Licence and credit checklist when vendoring

Add to CREDITS.md and ship the licence text in the library folder: Ace3 (Limited BSD, already there); LibSharedMedia
(LGPL v2.1 header, Elkano); AceGUI-3.0-SharedMediaWidgets (customised BSD); LibDeflate (zlib, SafeteeWoW); LibDualSpec
(BSD-style, Adirelle, no stand-alone redistribution); LibCustomGlow (MIT, Stanzilla). Already in flight and needing
credit lines: LibRangeCheck (MIT, WeakAuras fork), LibDBIcon (BSD, Funkeh), LibDataBroker (no licence file, tekkub:
note that in CREDITS).

## Appendix: what was not verified

- LibSharedMedia, LibDBIcon, LibChatAnims and LibCompress repositories live on wowace git; only the CurseForge pages
  (licence, last file, flavour tags) were readable. Forever tags came from CurseForge flavour lists. LibChatAnims'
  list did not show Forever; it is not needed anyway.
- LibCustomGlow has not been run on Forever. Its Midnight and classic-variant fixes are real, but no Forever commit.
- Chat message and link length limits on Forever were not measured (affects only T16's chat-paste route).
- The CurseForge pages for several libraries show dates that disagree between header and details ("Oct 10" versus
  "4 days ago"); dates above are the headers.
