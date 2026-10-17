# Content addon spike (restructure plan, Task 8)

## Question

Can Forever content live in separate addons that the core loads on demand? Concretely: a `## Dependencies: Hekili`,
`## LoadOnDemand: 1` addon, loaded with `C_AddOns.LoadAddOn` during the loading phase right after Hekili's
`ADDON_LOADED` (where the core's loader now runs: `Engine/Content.lua` from `OnInitialize`, before the profile, so the
profile's defaults and `RestoreDefaults` see the class's spec and packs), registers a spec through the public
`Hekili:NewSpecialization`; does that spec exist when the core's `PLAYER_ENTERING_WORLD` handler
(`SpecializationChanged`) runs, with no Lua error?

## Design

Two throwaway addons, the core untouched (the pre-restructure core in game is fine: the spike only calls
`Hekili:NewSpecialization`):

- `src/Hekili_Forever_SpikeLoader/` (`## Dependencies: Hekili`, so it loads after Hekili and its `ADDON_LOADED`): at
  its own file load it calls `pcall(C_AddOns.LoadAddOn, "Hekili_Forever_Spike")`; a `PLAYER_LOGIN` frame then checks
  the result held.
- `src/Hekili_Forever_Spike/` (`## Dependencies: Hekili`, `## LoadOnDemand: 1`): calls
  `Hekili:NewSpecialization(999001, true, icon)` (a fake id with no Constants row); a `PLAYER_ENTERING_WORLD` frame,
  registered after the core's, reports the spec table and the active spec.

`NewSpecialization` asks `GetSpecializationInfoByID` for a non-Forever spec when `Hekili.IsRetail()`, which Forever
reports; the spike swaps `IsRetail` for the one call so the fake id takes the plain branch. The real packs register
the Forever pseudo-specs, which have Constants rows, so they never meet this.

The lines, in order, and what each proves:

1. `Hekili spike: spec registered true`, printed from inside the load: a load-on-demand addon's main chunk ran during
   the loading phase and reached the public `Hekili` object.
2. `Hekili spike: LoadAddOn at load -> true true nil`: `LoadAddOn` is callable at that moment (no "not allowed now"
   refusal, no Lua error) and the client loaded the addon (`loaded` true, no reason).
3. `Hekili spike: at PLAYER_LOGIN, IsAddOnLoaded -> true`: the load holds through login (the client did not undo or
   defer it).
4. `Hekili spike: class.specs[999001] = true activeSpec = <id>`: the spec registered during loading is in
   `Hekili.Class.specs` when `SpecializationChanged` has run; `activeSpec` is the player's own spec (the fake one is
   not the player's).

Pass: all four, with no Lua error on login and on `/reload`. Fail at 2: fall back to plain `## Dependencies` content
addons (always loaded when installed); the rest of the task is unchanged.

## Result

**Pass** for the load-phase variant (2026-10-17, the user's client, pre-restructure core 103b91b8, both spike addons
linked). The chat lines at login:

```
Hekili spike: spec registered true
Hekili spike: LoadAddOn at load -> true true nil
Hekili spike: at PLAYER_LOGIN, IsAddOnLoaded -> true true
Hekili spike: class.specs[999001] = true activeSpec = false
```

- `LoadAddOn` during the loading phase, right after Hekili's `ADDON_LOADED`, works: no refusal and no Lua error, and
  the load-on-demand addon's main chunk registered its spec through `Hekili:NewSpecialization`.
- The `PLAYER_LOGIN` fallback found the addon already loaded. `IsAddOnLoaded` returns two values (loaded or loading,
  then loaded), both true.
- The spec registered during loading is in `Hekili.Class.specs` at `PLAYER_ENTERING_WORLD`.
- `activeSpec = false` is not a failure. The spike read `Hekili.State.spec.id`, a field the old core's `state.spec`
  does not set the way the print assumed, so the line says nothing about spec activation. Activating a real pack's
  spec is covered headless: the Arms and Druid gates boot through the class pack loaded at `OnInitialize`.

## What the spike did not prove

The spike proved less than the production path needs: `LoadAddOn` called from a sibling addon's main chunk (just after
Hekili's `ADDON_LOADED`), for a load-on-demand addon whose only dependency is Hekili, already loaded. The production
path differs in two ways: `Engine/Content.lua` calls `LoadAddOn` from inside Hekili's own `ADDON_LOADED`
(`OnInitialize`), and each class pack also depends on `Hekili_Shared`. So `Hekili_Shared` is load-on-demand too and
`LoadContent` loads it explicitly before the class pack (Taco Dog Forever's pattern for its shared data addon), so no
step relies on the client loading a dependency for `LoadAddOn` mid-startup. That path is confirmed only by the user's
in-game check after the merge (`docs/dev/architecture.md`, section 7).

The fallback to plain `## Dependencies` content addons is not needed if that check passes. The spike addons are
deleted.
