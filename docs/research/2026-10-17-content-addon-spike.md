# Content addon spike (restructure plan, Task 8)

## Question

Can Forever content live in separate addons that the core loads on demand? Concretely: a `## Dependencies: Hekili`,
`## LoadOnDemand: 1` addon, loaded with `C_AddOns.LoadAddOn` at `PLAYER_LOGIN` (the moment the core's `OnEnable` runs,
`Core.lua`), registers a spec through the public `Hekili:NewSpecialization`; does that spec exist when the core's
`PLAYER_ENTERING_WORLD` handler (`SpecializationChanged`) runs, with no Lua error and no `OnInitialize` ordering
problem?

## Design

Two throwaway addons, the core untouched (the pre-restructure core in game is fine: the spike only calls
`Hekili:NewSpecialization`):

- `src/Hekili_Forever_SpikeLoader/` (`## Dependencies: Hekili`): its own frame on `PLAYER_LOGIN` calls
  `pcall(C_AddOns.LoadAddOn, "Hekili_Forever_Spike")` and prints `Hekili spike: LoadAddOn -> <ok> <loaded> <reason>`.
- `src/Hekili_Forever_Spike/` (`## Dependencies: Hekili`, `## LoadOnDemand: 1`): calls
  `Hekili:NewSpecialization(999001, true, icon)` (a fake id with no Constants row) and prints
  `Hekili spike: spec registered <ok>`; then, on a `PLAYER_ENTERING_WORLD` frame registered after the core's, prints
  `Hekili spike: class.specs[999001] = <bool> activeSpec = <id>`.

`NewSpecialization` asks `GetSpecializationInfoByID` for a non-Forever spec when `Hekili.IsRetail()`, which Forever
reports; the spike swaps `IsRetail` for the one call so the fake id takes the plain branch. The real packs register
the Forever pseudo-specs, which have Constants rows, so they never meet this.

Pass: `LoadAddOn -> true true`, `spec registered true`, `class.specs[999001] = true`, and `activeSpec` the player's
own spec (the fake spec is not the player's, so it is registered but not active), with no Lua error on login and on
`/reload`. Fail: fall back to plain `## Dependencies` content addons (always loaded when installed); the rest of the
task is unchanged.

## Result

Pending (user).
