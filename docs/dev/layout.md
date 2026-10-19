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
  - `src/Hekili_Warrior/`, `src/Hekili_Druid/`, `src/Hekili_Rogue/`, `src/Hekili_Paladin/`: one class pack each (the class file, its RegisterPack
    blocks written by `make packs`); `## LoadOnDemand: 1`, loaded at login by the core's `Engine/Content.lua` for the
    player's class.
    The default priorities' sources sit beside the class file in `APLs/`: one `<Pack>.simc` per priority and the
    manifest `packs.lua` (`{ spec = ..., packs = { ... } }`, no date). Edit those, then `make packs`. The date is per
    class and lives only in the class file's first RegisterPack block: `make packs` keeps it while the generated
    blocks are unchanged and sets it to today (`PACK_DATE=YYYYMMDD`, else the system date) when any of that class's
    packs changed, so a clean tree is a no-op and one class's edit re-dates only that class.
    `## Group: Hekili` nests each content addon under Hekili in the in-game addon list.

  Content reaches the engine only through the public `Hekili` object (the registration API, `State`, `Class`,
  `Client`; `tests/boundary_spec.lua`). Every TOC's `## Version` is `@project-version@`; the packager stamps the release tag into all four (one zip, one version); the core's ContentAPI
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
  Update and per UNIT_COMBAT for headless Arms over 6 fights. The Task 5 Arms lines cost the stock sim a little: "B per
  Update, direct" went from mean -1, p95 160, max 640 (05f075dd) to 7 / 206 / 640 (238d2e6f), with no rise before Task 5.
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

`make check`'s 6-fight Arms gate is two files of 3 fights (`tests/Forever/loop_warrior_spec.lua`, seeds 1-3, and
`loop_warrior_late_spec.lua`, seeds 4-6), so it prints three `Arms solo:` lines (`tests/Forever/arms_recs_spec.lua`
repeats seeds 1-3 against its every-slot fixture). Each fight seeds its own world and the
boot carries nothing between fights, so the halves play the same fights as the old single run.
After the wowsims lines (class-completion Task 5: Rend, Overpower and Slam at focus, Hamstring under Windfury, Battle
Shout at 10 s; the split's lines, forever 98e718bd, were agreement 0.968 / 0.938, cost 17.4 (oracle 17.4) / 16.8
(oracle 15.4)):

```
Arms solo: fights=3 agreement 0.977 (2265 ticks); react median 0 p90 0 never 0.030; refused per 100 [cost 25.8 (oracle 22.9)], episodes 4.37/min; dps A/B 0.918; ... [seeds 1-3]
Arms solo: fights=3 agreement 0.949 (2422 ticks); react median 0 p90 0 never 0.060; refused per 100 [casting 2.3 (oracle 2.2), cost 20.6 (oracle 22.6)], episodes 3.47/min; dps A/B 1.020; ... [seeds 4-6]
```

Seeds 1-3 pass the cost gate by 0.1 (25.8 against a 25.9 limit). Fury's Battle Shout is still `!buff.battle_shout.up`
while Arms refreshes it at 10 s, on purpose: aligning Fury is a later Fury change.

`tests/Forever/loop_druid_spec.lua` runs 3 fights a Druid pack in `make check` (seeds 1-3, the `#slow` tag) and 20 in
`make test-druid` (`#druid`), each asserting its flagged lines ran (`r.focus > 0`). Feral and Balance are gated by
`pack_gate.gate`; Guardian is reported (engine health and focus asserted, not the agreement): its first icon waits on
rage the usability ladder cannot place. The first passing run (class-completion Task 2):

```
Feral solo: fights=3 agreement 0.974 (2697 ticks); react median 0 p90 0 never 0.015; refused per 100 [], episodes 0.00/min; dps A/B 1.000; ... [seeds 1-3]
Guardian solo: fights=3 agreement 0.718 (2574 ticks); react median 0 p90 1 never 0.186; refused per 100 [cost 31.2 (oracle 19.3), gcd 3.8 (oracle 3.5)], episodes 2.68/min; dps A/B 0.955; ... [seeds 1-3] (reported)
Balance solo: fights=3 agreement 0.985 (864 ticks); react median 0 p90 1 never 0.000; refused per 100 [casting 91.2 (oracle 91.4)], episodes 8.13/min; dps A/B 0.996; ... [seeds 1-3]
```

Feral's Innervate line never fires in the loop: the feral worlds keep no mana.

`tests/Forever/loop_rogue_spec.lua` runs 3 fights a Rogue pack in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-rogue` (`#rogue`), each gated by `pack_gate.gate` and asserting its flagged lines ran (`r.focus > 0`: Slice
and Dice at tier 1 in every pack). Rupture, Garrote and Vanish's re-open are guarded by `boss|settings.trash_dots`
(default off), so the solo world (no boss) never presses them; Kick has no caster to interrupt, Expose Armor is a
setting (off) and Cutthroat needs Backstab, off by default. The first passing run (class-completion Task 7):

```
Combat solo: fights=3 agreement 0.978 (2322 ticks); react median 0 p90 0 never 0.012; refused per 100 [], episodes 0.00/min; dps A/B 1.003; ... [seeds 1-3]
Assassination solo: fights=3 agreement 0.999 (2222 ticks); react median 0 p90 0 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.015; ... [seeds 1-3]
Subtlety solo: fights=3 agreement 0.950 (2379 ticks); react median 0 p90 0 never 0.036; refused per 100 [], episodes 0.00/min; dps A/B 1.056; ... [seeds 1-3]
```

`tests/Forever/loop_paladin_spec.lua` runs 3 fights a Paladin pack in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-paladin` (`#paladin`), asserting its flagged lines ran (Retribution: the seal twist at tier 1; Protection:
Seal of Fury and Holy Shield at tier 2). The mob swings at us in both worlds: Holy Shield raises the block chance and
each block spends a charge (the world's class-neutral `taking`/`took`); our landed swing spends an Echo (`landed`); mana
runs under the five-second rule (`fsr`). Protection is gated by `pack_gate.gate`. Retribution is **reported**: its
swing-gap fillers wait for `mana.pct>=settings.*_mana` (10%, wowsims), and Hekili reads mana as the belief's lower
bound, which on a fresh boot only the usability ladder lifts, to at most Consecration's 565 of 6000 (mana is secret
even out of combat); without the floor its agreement is 0.988. The holy_shock list (Holy Shock talent) and Hammer of
Wrath's window are not exercised by the solo worlds. The first runs (class-completion Task 8):

```
Retribution solo: fights=3 agreement 0.846 (1923 ticks); react median 0 p90 1 never 0.275; refused per 100 [], episodes 0.00/min; dps A/B 1.017; ... [seeds 1-3] (reported)
Protection solo: fights=3 agreement 0.957 (2164 ticks); react median 0 p90 1 never 0.030; refused per 100 [], episodes 0.00/min; dps A/B 0.977; ... [seeds 1-3]
```

Paladin checkpoint (in game, a level 60 Paladin; provisional until answered):
- P1: the pseudo-spec ID the client reports (Constants.lua's 1501 is a placeholder), and the talent IDs (Twist of Light
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
- P9: Consecrated Ground (1310905) on the target after Consecration, its 8.6 s; Seal of Fury's absorb and Improved
  Seal of Fury's mana are unmodelled.

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

## Remotes

`origin` is the fork (github.com/zmsl/hekili). Upstream, fetch only:

```
git remote add upstream https://github.com/Hekili/hekili.git
git remote set-url --push upstream no_push
```

## In game

Each addon gets its own AddOns link, at its folder in `src/`, not at the repository root. From an elevated Windows
prompt, in the client's `Interface\AddOns` folder, remove the old link and create the six:

```
rmdir Hekili
mklink /D Hekili \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili
mklink /D Hekili_Shared \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Shared
mklink /D Hekili_Warrior \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Warrior
mklink /D Hekili_Druid \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Druid
mklink /D Hekili_Rogue \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Rogue
mklink /D Hekili_Paladin \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Paladin
```

Then restart the client fully (a moved addon is not picked up by `/reload`).
