# Headless Hekili spike (2026-10-16): GO, no src change

Stock Hekili's recommendation engine runs headless under Lua 5.1 driven by the harness's fake client. Scratch files in
this directory: `shell.lua` (every stub in one file + the TOC/XML loader + login), `run.lua` (Arms Warrior, one
cycle), `loop.lua` (closed loop, 30 s), `probe.lua`/`inv.lua`/`perf.lua`/`engine.lua`/`hp.lua`, `globals_raw.txt`,
`debug.log`. Run from ~/src/hekili with `.lua/bin/lua <file> x`.

## Findings
1. All of Hekili.toc loads (embeds, Virtual, State, Engine, Warrior, Options, UI, Core); only UI/PopupSlider.xml is
   skipped (XML frames, not on the recommendation path).
2. Login is real: ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD run AceAddon OnInitialize/OnEnable, build the
   AceDB profile, start VirtualState (VS.Start(_G)); spec 1491 activates; the real APL compiler loads Arms/Fury/Prot.
3. Entry point: `Hekili.Update()` (Core.lua:1547), a plain function; `Hekili:Yield` is a no-op outside a coroutine,
   so a direct call is one synchronous deterministic pass. Cycle: VirtualState frame OnUpdate -> due timers -> Update().
4. Queue: `ns.UI.Displays.Primary.Recommendations[i]` (actionName, actionID, time, exact_time, delay, resources,
   indicator, keybind); `Hekili_GetRecommendedAbility("Primary", 1)` works.
5. Test state (Arms, 30 rage, melee target, in combat): sunder_armor@0, heroic_strike@0, heroic_strike@7.2; every read
   through ns.Facade (trace in debug.log).
6. Press loop: 301 cycles / 30 s at ~2 ms each, 14 presses; the belief modelled the Sunder it applied and Hekili
   re-recommended it at expiry. Boot 0.11 s CPU.
7. Blockers: none. Gaps: fake_api `UnitIsUnit(a, a)` answers false (State.lua:5461 keeps a debuff only if the caster
   IsUnit player) -> add `if a == b then return true end` to fake_api; fake_api covers ~40 of 176 facade names (the
   shell supplies the rest); latent upstream bug State.lua:416 `state.abs = safeAbs` is nil (math.abs).
8. Effort to wire the real world (~3-4 days): incremental observer (observe is batch today and draws from W.rng while
   observing; ~1 d); runtime presses in the world, `W.press` (~0.5 d); a Warrior ability->world mapping in
   tests/Forever/ reading cost/cooldown/GCD from Hekili.Class.abilities (~0.5 d); secret rage (ctl.power[1] = nil)
   falls out of the observer; one boot per busted insulate block (Hekili is global; ~0.5 d); an oracle: a second
   Hekili fed the TRUE state in lockstep (~1 d).
9. Metrics: agreement with the oracle (first icon match, confusion by ability); cycles to react to a state change;
   presses the real client would refuse (short of rage, on cooldown); damage, time capped at full rage, GCD idle,
   debuff uptime; first-icon flicker; engine health (Hekili:Error count, Facade.secrets, per-cycle CPU gate).
10. Risks: stub frames hide renderer bugs (recommendations only); a new nil global read at recommendation time could
    skew silently -> assert the miss counter stays empty beyond the known upstream nils (overcap State.lua:1386, id
    :3766, listName Core.lua:1992, alphaCheck UI.lua:1121, squawk Scripts.lua:1032); prototype cheats with plain rage
    and every spell known; Hekili's frame update is wall-clock budgeted -> call Update() directly in scored runs.

## Globals the facade does not cover
- Load: WoW aliases (floor ceil max min format wipe sort strlower strupper gmatch strsplit string.trim tostringall
  date time bit debugprofilestop debugstack hooksecurefunc geterrorhandler Mixin); xpcall with extra args (AceAddon
  calls OnInitialize with self = nil otherwise); library reads (GetCurrentRegion, C_UIFileAsset, GetInventorySlotInfo,
  Minimap/GetMinimapShape, ClassicExpansionAtLeast/AtMost, GetNumSpecGroups, CreateTexturePool/CreateFramePool, font
  objects); Hekili core: Enum, LOCALIZED_CLASS_NAMES_*, RAID_CLASS_COLORS, MAX_PLAYER_LEVEL, CR_* constants,
  GlobalStrings (INVTYPE_*), Item:CreateFromItemID, Spell:CreateFromSpellID, UIParent, GameTooltip,
  DEFAULT_CHAT_FRAME, BackdropTemplateMixin, PixelUtil, C_Timer, HekiliDB; C_AddOns.GetAddOnMetadata must return the
  TOC Version (State.lua:418 indexes Hekili.Version). Five facade rows stay absent harmlessly.
- Login: AddonCompartmentFrame:RegisterAddon (Core.lua:129); PixelUtil returns numbers (UI.lua:121); frame GetSize
  numbers (UI.lua:2756); CreateFontString(name) creates the global (Options.lua:9734 HekiliNotificationText); known
  spells/talents set before login (VirtualState builds at SpecializationChanged; else fire SPELLS_CHANGED); four
  tickers pending (Targets.lua:1112, :1581, Events.lua:960, one 5 s) run on the fake clock.
- Per recommendation: GetTime, debugprofilestop, the display objects (ns.UI.Displays[name], _G["HekiliDisplay"..name]
  State.lua:6189, HekiliDisplayAOE Core.lua:1525); 8 of 424 frames register events with the fake client.
- Stub frames: real event registration and scripts; missing Set/Show/Create verbs no-op; Get* returns a stub frame,
  Is*/Has* false, a short getter list returns numbers; `Highlight` is a field (UI.lua:1211), not a verb.
- Cost: ~1800 cycles ≈ 4 s per 3-minute fight at 10 Hz; 100 fights ≈ 7 min (#slow) or 3.5 min at 5 Hz (the in-game
  combat rate).
Not checked: Druid pack, AOE with several targets, in game. Execute was recommended because the target's believed
health starts at 20% with no hits observed; real hit events feed it.
