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
  - `src/Hekili_Warrior/`, `src/Hekili_Druid/`, `src/Hekili_Rogue/`, `src/Hekili_Paladin/`, `src/Hekili_Shaman/`,
    `src/Hekili_Hunter/`: one class pack each (the class file, its RegisterPack
    blocks written by `make packs`); `## LoadOnDemand: 1`, loaded at login by the core's `Engine/Content.lua` for the
    player's class.
    The default priorities' sources sit beside the class file in `APLs/`: one `<Pack>.simc` per priority and the
    manifest `packs.lua` (`{ class = "<TOKEN>", packs = { ... }, specs = { [<Pack>] = <spec key> } }`, no date). Edit those, then `make packs`. The date is per
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
  attribution gates (`solo_spec`, `group_spec`, `onus_spec`, `sweep_spec`). The world has one position, our yards to
  our target (`W.distance`: the `distance` scenario knob, `W.moveTo`; none by default, every range check in range):
  the observer's `@distance` makes the fake client's `C_Spell.IsSpellInRange` answer against each spell's range (a
  content's `character.ranges`, else 0-5), our white swings stop out of reach (5 yd) and a press with a `range` is
  refused outside it; the wowsims replay starts at the request's `distanceFromTarget` and steps on the log's Movement
  aura stacks. Its `fixtures/` are in-game /vslog dumps,
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
- The wowsims tools (`tools/wowsims/apl.lua`, `export.lua`, `tools/check_pack_levels.lua`) and the wowsims gates
  (`tests/Forever/helpers/wowsims.lua`) read one ability set: `tests/Forever/helpers/engine.lua`'s
  `abilitySet(token, race)`, the abilities and auras the engine holds after SpecializationChanged (the class kit's,
  then Hekili_Shared's and the engine's own for missing keys, a race pack's over both), every race's racials when
  `race` is nil. So the translator's keys, off-GCD flags and talent links, the learn table, the leveling check's
  ability keys and the gates' racials all agree with the engine. The replay (`tests/Game/harness/replay.lua`) maps
  the log through the booted instance's own `Hekili.Class`, booted as the request's race (`wowsims.race(spec)`).
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
The gate runs Arms (wowsims.com), the Arms default since the wowsims packs plan's Warrior swap (the hand-built Arms,
Fury and Protection lists retired), on the world's wowsims build (Spearing Strike and Berserker Rage in the kit). Its
lines (the swap, on trunk 824901c4 plus the Warrior lane; 20 fights: agreement 0.964, flicker 1.38/min):

```
Arms solo: fights=3 agreement 0.973 (2660 ticks); react median 0 p90 0 never 0.018; refused per 100 [casting 7.0 (oracle 0.5, unmatched 0.0), cost 17.0 (oracle 16.2, unmatched 0.0)], episodes 4.40/min; dps A/B 0.982; ... [seeds 1-3]
Arms solo: fights=3 agreement 0.985 (2501 ticks); react median 0 p90 0 never 0.049; refused per 100 [cost 16.1 (oracle 15.8, unmatched 0.0)], episodes 3.60/min; dps A/B 0.998; ... [seeds 4-6]
```

Before the pull it shows Bloodrage and Battle Shout only (no positions headless, so no Charge).

`tests/Forever/loop_druid_spec.lua` runs 3 fights a Druid pack in `make check` (seeds 1-3, the `#slow` tag) and 20 in
`make test-druid` (`#druid`), each asserting its flagged lines ran (`r.focus > 0`). Feral and Balance run their
wowsims.com defaults (wowsims packs plan, Task 7b; the hand-built lists retired) and are gated by `pack_gate.gate`;
Guardian keeps its hand-built list and is reported (engine health and focus asserted, not the agreement): its first
icon waits on rage the usability ladder cannot place. Current lines (Task 7b):

```
Feral solo: fights=3 agreement 0.911 (2541 ticks); react median 0 p90 0 never 0.030; refused per 100 [], episodes 0.00/min; dps A/B 1.055; ... [seeds 1-3]
Guardian solo: fights=3 agreement 0.714 (2694 ticks); react median 0 p90 1 never 0.140; refused per 100 [cost 19.9 (oracle 22.6)], episodes 3.23/min; dps A/B 1.002; ... [seeds 1-3] (reported)
Balance solo: fights=3 agreement 0.988 (1416 ticks); react median 0 p90 1 never 0.000; refused per 100 [casting 88.6 (oracle 89.4)], episodes 10.73/min; dps A/B 0.904; ... [seeds 1-3]
```

The Feral and Balance worlds keep the wowsims logs' mana pools and five-second rule (22 a second outside it).

`tests/Forever/loop_rogue_spec.lua` runs 3 fights a Rogue spec in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-rogue` (`#rogue`), each on its "<Spec> (wowsims.com)" pack (wowsims packs plan, Task 8), gated by
`pack_gate.gate` and asserting its flagged lines ran (`r.focus > 0`: Slice and Dice at tier 1 in every pack). The
worlds carry the wowsims.com builds' abilities and talents (Subtlety Hemo has no Ghostly Strike); the replay and
leveling gates are `tests/Forever/wowsims_rogue_spec.lua`. The lines since the swap:

```
Combat solo: fights=3 agreement 0.999 (2226 ticks); react median 0 p90 0 never 0.000; refused per 100 [requires:in combat 0.7 (oracle 2.0)], episodes 0.13/min; dps A/B 1.037; ... [seeds 1-3]
Assassination solo: fights=3 agreement 0.993 (2437 ticks); react median 0 p90 0 never 0.022; refused per 100 [requires:in combat 1.8 (oracle 1.8)], episodes 0.25/min; dps A/B 0.990; ... [seeds 1-3]
Subtlety solo: fights=3 agreement 0.967 (2192 ticks); react median 0 p90 0 never 0.073; refused per 100 [requires:in combat 1.3 (oracle 0.6)], episodes 0.27/min; dps A/B 0.999; ... [seeds 1-3]
```

`tests/Forever/loop_paladin_spec.lua` runs 3 fights a Paladin pack in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-paladin` (`#paladin`), asserting its flagged lines ran (Retribution: the seal twist at tier 1; Protection:
Seal of Fury and Holy Shield at tier 2). The mob swings at us in both worlds: Holy Shield raises the block chance and
each block spends a charge (the world's class-neutral `taking`/`took`); our landed swing spends an Echo (`landed`); mana
runs under the five-second rule (`fsr`). Both packs are gated by `pack_gate.gate`; both are wowsims.com packs since the
wowsims packs plan, Task 9 (the hand-built lists retired). Retribution (wowsims.com)'s swing-gap fillers carry
wowsims's own `mana.pct>=10`, judged on the secret-mana belief: in the solo worlds' later fights (each starts at full
mana 30 s after the last, which no regen fills) the belief rightly carries the drained pool, so the fillers wait where
the oracle, reading the truth, casts them (the Retribution lines' consecration disagreements; GAP X: loop fights
restart at full mana after a dry fight, so the Retribution 20-fight line's 0.911, never 0.226 is harness-caused and
recovers after GAP X). The
holy_shock list is gone with the hand-built Retribution list; Hammer of Wrath's window is not exercised by the solo
worlds. The runs (the rebased base of the wowsims packs plan, Task 9 resume 3):

```
Retribution solo: fights=3 agreement 0.924 (2572 ticks); react median 0 p90 0 never 0.188; refused per 100 [], episodes 0.00/min; dps A/B 0.865; ... [seeds 1-3]
Protection solo: fights=3 agreement 0.988 (2431 ticks); react median 0 p90 1 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.011; ... [seeds 1-3]
Retribution solo: fights=20 agreement 0.911 (17477 ticks); react median 0 p90 0 never 0.226; refused per 100 [], episodes 0.00/min; dps A/B 0.883; ...
Protection solo: fights=20 agreement 0.989 (17185 ticks); react median 0 p90 1 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.985; ...
```

Paladin checkpoint (in game, a level 60 Paladin; provisional until answered):
- P1: the client's pseudo-spec id (assumed 1486; only the legacy profile migration reads it) and the talent tree the
  dominant-tree pick chooses for your build (Snapshot `spec:` line), and the talent IDs (Twist of Light
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
- P9: Consecrated Ground (1280353, the aura the class file reads; wowsims logs it, not the APL's 1310905) on the
  target after Consecration, its 8.6 s; Seal of Fury's absorb and Improved Seal of Fury's mana are unmodelled.
- P10: Judgement's cooldown with Improved Judgement (modelled 10 s less 1 s a rank: 8 s at 2/2), and the costs at
  partial ranks of Benediction (2% less a rank) and Holy Conduit (20% less a rank; Consecration, Exorcism, Hammer of
  Wrath): the DB2 holds the full-rank value on rank 1 (ruling P5), so check a 1-rank cost in the spellbook tooltip.
- P11: Sanctified Judgement at 3/3: does every Judgement return 60% of the seal's base cost (the belief gains it, e.g.
  161 mana for Seal of Command at 0.72), or is the refund chance-based or another amount (then the bound over-reads)?
- P12: Retribution (wowsims.com)'s `use_items` line: is the equipped on-use trinket suggested, off the GCD, when ready?
- P13: Protection (wowsims.com)'s precombat order: Retribution Aura (10 s before the pull), then Seal of the Crusader
  at 1.5 s, then Seal of Fury in combat; and no Righteous Fury suggestion (ruling P11).

`tests/Forever/loop_shaman_spec.lua` runs 3 Enhancement fights on Enhancement (wowsims.com), the default priority, in
`make check` (seeds 1-3, `#slow`) and 20 in
`make test-shaman` (`#shaman`), gated by `pack_gate.gate` and asserting its flagged lines ran (Lightning Bolt at 5
Maelstrom Weapon and Fire Nova on Clearcasting at tier 1; Strength of Earth, Lightning Shield and Flame Shock at tier
2). The world keeps the totem slots (`W.summonTotem`, class-neutral: a slot and an expiry), secret in combat; the summon's
`now` (`summonTotem`, content API 4) writes the slot's modelled expiry, which the in-combat GetTotemInfo answers. The
mob swings at us and each hit that lands spends a Lightning Shield charge; our landed melee stacks Maelstrom Weapon; an
elemental spell rolls Clearcasting (10%); the shocks share a cooldown (6 s, 0.2 s less a rank of Reverberation). Neither side dies: a kill by our last press
ends the loop before the client sees it, so the next fight's prepull would be believed in combat and its totem slots
never read (a harness quirk every pack shares). The world runs out of mana about 35 s in (idle about 0.68: UNMEASURED
pool and regen, no Mana Spring regen, Water Shield or potions), so most in-combat ticks show no icon on either side.
The imbues are not in the solo world's kit (it has no weapon enchant read). The world's costs are each rank's (DB2),
with Shamanistic Focus when the build has it, Stormstrike's 121 (wowsims/forever's), and the shocks' cooldown and Flame
Shock's duration from the booted talents. The lines below run Enhancement (wowsims.com) (wowsims packs plan, Task 10,
state R2 on origin/forever 3aa63c96: Fire Nova at the DB2's 520). `tests/Forever/wowsims_shaman_spec.lua` replays wowsims's own fight
(floor 0.80) and runs the levels 10, 40 and 60 (40 pending: GAP W, the five-second window opened late):

```
Enhancement solo: fights=3 agreement 0.999 (1151 ticks); react median 0 p90 1 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.011; ... [seeds 1-3]
Enhancement solo: fights=20 agreement 0.996 (7350 ticks); react median 0 p90 1 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.001; ...
```

Shaman checkpoint (in game, a level 60 Shaman; provisional until answered):
- S1: the client's pseudo-spec id (assumed 1489; only the legacy profile migration reads it) and the talent tree the
  dominant-tree pick chooses for your build (Snapshot `spec:` line).
- S2: totem slot order: GetTotemInfo(1..4) out of combat is fire, earth, water, air (as Hekili's `totem.<element>`
  and `summonTotem` assume)? Searing Totem's duration (55 s at rank 6) and the 300 s totems' read back as such?
- S3: PLAYER_TOTEM_UPDATE in combat: does it fire for our own summon (and for the replaced totem), and does it arrive
  within 0.5 s of UNIT_SPELLCAST_SUCCEEDED (I.CAST_GRACE; later, the belief drops the summon as a destruction)? Does it
  fire at a totem's natural expiry and when the totem is killed? Is GetTotemInfo secret in combat (all returns)?
- S4: Maelstrom Weapon (408505) visibility: is the player aura and its stack count readable in combat? Is 408498 a
  learnable rune on Forever (else its lines stay inert)? Five stacks: Lightning Bolt instant and free?
- S5: Clearcasting (16246) after an elemental spell: readable in combat; one charge, spent by the next Lightning Bolt,
  shock or Fire Nova (the cost modifier's list)?
- S6: Fire Nova (408341..408345): IsSpellUsable without a fire totem answers (false, false), not short of mana (its
  answers are a mana rung)? Its cooldown (10 s, 6 s with Improved Fire Nova 2/2), and does it leave the totem up?
- S7: Lightning Shield (324..10432): 3 charges on the player aura, one spent per hit that lands (WOUND and partial block
  in UNIT_COMBAT), readable in combat?
- S8: the shocks' shared cooldown: after Earth Shock, does Flame Shock read on cooldown (category 19: 6 s, 5 s with
  Reverberation 5/5), and the reverse?
- S9: the imbues: C_Item.GetWeaponEnchantInfo out of combat after Rockbiter (60 minutes), so main_hand_enchant reads up
  (the imbue reminder setting is retired with the hand-built list); the dual-wield off hand (not modelled).
- S10: mana: UnitPower(mana) secret out of combat on a Shaman too; GetPowerRegenForPowerType(0)'s two returns; the
  Flame Shock DoT (12 s, 21 s with Call of Flame 3/3; 3 s ticks) on the target modelled from our cast.
- S11: wowsims/forever's spell data against the client: Flame Shock lasts 21 s with Call of Flame 3/3? Stormstrike
  costs 121 (8% of base mana) or the DB2's 125? Fire Nova costs 375 (wowsims) or the DB2's 520 (the kit's)?
  Shamanistic Focus takes 45% off the shocks and Lightning Shield?

`tests/Forever/loop_hunter_spec.lua` runs 3 fights of each Hunter pack in `make check` (seeds 1-3, `#slow`) and 20 in
`make test-hunter` (`#hunter`), gated by `pack_gate.gate` and asserting that some focus line ran (`r.focus > 0`: Beast
Mastery and Marksmanship flag Hunter's Mark and Serpent Sting at tier 2; Survival flags Raptor Strike and Mongoose Bite
at tier 1 and Hunter's Mark at tier 2). The packs are the
wowsims.com ones (Beast Mastery, Marksmanship and Survival (wowsims.com), Task 11 of the wowsims packs plan:
wowsims/forever's Melee Weave), and their replay and leveling gates are `tests/Forever/wowsims_hunter_spec.lua`. Each
pack opens with wowsims's automatic Blood Fury and Rapid Fire (translator rule 13, from 5 s, off the GCD). The Beast
Mastery and Marksmanship worlds stand at 11 yd (the weave's range: the shots in their band, Raptor Strike and the melee
lines out of reach) and shoot Auto Shots on the harness's ranged hand (`W.startRanged`), Quick Shots procs off them
under Aspect of the Hawk (10%); they run the same pack text and kit, so their lines match. The Survival world sets no
distance (every check in range), swings a two-hander and keeps the pack's Aspect of the Hawk up. Its Mongoose Bite
window never opens: our dodge is meant to open it for 5 s, but `dodged()` in `tests/Forever/helpers/hunter_world.lua`
reads `W.t`/`W.truth`, which a batched list answer sees at the finished world. Each world prices the known rank under
the character's Resourcefulness and Efficiency (the leveling brackets; the replay's builds). Raptor Strike's cooldown
starts at its swing (class-neutral: a queued strike's cooldown). Each fight's fresh world gets the pack's aspect at the
pull (the character keeps a permanent buff between fights). Neither side dies (shaman_world's workaround for the loop's
missing kill). The kit's ranges are DB2's (`RANGE`: Hunter Range 8-35, Combat Range 0-5). "The Hunter at range, then
in melee" runs Survival at 25 yd, then 5 yd: its four `target.within5` lines stay shut while the bracket reads [8, 35],
open at [0, 5], and the bracket holds when every read goes secret. Mana is secret in combat, so the belief holds its
lower bound and the worlds idle 0.730 (Beast Mastery, Marksmanship) and 0.562 (Survival) of the time. The lines
(gate 11fix11, after central fixes 6 and 11) after the swap (wowsims packs plan, Task 11; the hand-built lists' were
0.983/0.986/0.945 at 3 fights):

```
Beast Mastery solo: fights=3 agreement 0.999 (1905 ticks); react median 0 p90 1 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.034; ... [seeds 1-3]
Marksmanship solo: fights=3 agreement 0.999 (1905 ticks); react median 0 p90 1 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.034; ... [seeds 1-3]
Survival solo: fights=3 agreement 0.976 (1393 ticks); react median 1 p90 1 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 0.988; ... [seeds 1-3]
Beast Mastery solo: fights=20 agreement 1.000 (12675 ticks); react median 0 p90 1 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.007; ...
Marksmanship solo: fights=20 agreement 1.000 (12675 ticks); react median 0 p90 1 never 0.000; refused per 100 [], episodes 0.00/min; dps A/B 1.007; ...
Survival solo: fights=20 agreement 0.976 (9328 ticks); react median 1 p90 2 never 0.008; refused per 100 [], episodes 0.00/min; dps A/B 1.018; ...
```

Hunter checkpoint (in game, a level 60 Hunter with a ranged weapon and a pet; provisional until answered): the Hunter
research's §7 questions (`docs/research/2026-10-15-forever-hunter/research.md`), plus:
- H1: the client's pseudo-spec id (assumed 1484; only the legacy profile migration reads it) and the talent tree the
  dominant-tree pick chooses for your build (Snapshot `spec:` line).
- H2 (Q1, C7-3): UnitRangedDamage("player") plain out of combat, and secret in combat? Its first return feeds the
  ranged hand's speed.
- H3 (Q2, C7-1): PLAYER_SWING with swingType 2 for each Auto Shot, and its duration the hasted ranged speed (the better
  anchor, already wired)?
- H4 (C7-2): UNIT_SPELLCAST_SUCCEEDED for Auto Shot (75) on every shot, at the release? The modelled clock assumes it.
- H5 (C7-4): ranged haste (quiver, Rapid Fire, Quick Shots) in UnitRangedDamage's speed out of combat, and the clock's
  drift in combat under Rapid Fire.
- H6 (Q3, Q6): C_Spell.IsSpellInRange(75, "target") at 4, 10 and 40 yards, in and out of combat (the target's range
  bracket reads it; the packs have no deadzone guard of their own); plain or secret in combat? Raptor Strike (on the
  next swing) in range at any distance, like Heroic Strike?
- H14 (gap 13): `/run local r=Hekili.State.target VSCopy(r.distance,r.minR,r.maxR,r.within5,r.outside8)` at 3, 11 and
  30 yards: about 2.5 / 0 / 5 / true / false in melee, 21.5 / 8 / 35 / false / true at 11 yd; and
  `C_Spell.GetSpellInfo(14268).maxRange` (Wing Clip) reads 5, not 0.
- H7 (Q4): Multi-Shot's and Strider Kick's actual costs (DB2 13.9% and 5.81% of base mana, priced here as of the
  maximum); UnitPower(mana) secret out of combat on a Hunter too; GetPowerRegenForPowerType(0)'s two returns.
- H8 (Q5): Rapid Fire (3045) and Quick Shots (6150) readable on the player in combat (Aimed, Multi and Sniper Shot's
  hasted casts)?
- H9 (Q9): Sniper Shot (1310687..), Summon Hawk (1293241..), Strider Kick (1317257) and Aspect of the Beast's Forever
  ranks (1299445..) learnable (else their lines stay inert)?
- H10 (C1, CAST_GRACE): Summon Hawk: two hawks at most, 18 s each, the oldest replaced by a third; is a hawk a `pet`
  unit (UNIT_PET) at all? If the Hunter's pet unit is summoned (Call Pet), does UNIT_PET arrive within 0.5 s of
  UNIT_SPELLCAST_SUCCEEDED (I.CAST_GRACE)?
- H11: Arcane Shot and Summon Hawk share a 6 s cooldown (category 1173), Aimed Shot and Multi-Shot another (category 2)?
- H12 (Q14): Mongoose Bite usable only for 5 s after a dodge (Defensive State 5302) and for 10 s of Expose Prey
  (1310726, the talent's proc), by IsSpellUsable; Raptor Strike queued (IsCurrentSpell) and its 6 s cooldown from the
  swing that takes it?
- H13 (Q8): Hunter's Mark and Serpent Sting on the target unreadable in combat (modelled from our casts)?
- H15: Multi-Shot's cast: 0.5 s (DB2 2643, kept) or instant (wowsims)? The weave line reads it against the swing
  (live since central fix 11's division).
- H16: Immolation Trap's 30 s category cooldown (DB2 SpellCooldowns).
- H17: `mainhand_remains` against the real main-hand swing (the weave's Multi-Shot gap); past a due swing out
  of melee it reads 0 (wowsims's due timer), not a swing a period later.
- H18: Resourcefulness (440529) and Efficiency (19416) reported as talents at their ranks, and the prices they give:
  Mongoose Bite, Wing Clip, Immolation Trap and Strider Kick 30% / 60% off; Raptor Strike under both (wowsims's log 40
  at 2/2 Resourcefulness, 94 at 2/5 Efficiency).
- H19: `target.within5` through the weave (in and out of melee each swing): the melee lines open and shut in time?
- H20: a saved BeastMastery, Marksmanship or Survival choice falls back to the spec's wowsims.com pack.
- H21: Rapid Fire and Blood Fury recommended from 5 s into a fight, off the GCD (rule 13's automatic cooldowns).

Core checkpoint (in game, any rage user; provisional until answered):
- R1 (the swing rung lift, `Families/Resources.lua` `owe`): when does a white swing's rage arrive, at PLAYER_SWING or with
  its wound on the target about 0.47 s later? Log `UNIT_POWER_FREQUENT` "RAGE" (and `UnitPower("player", 1)` out of
  combat) with PLAYER_SWING and the target's UNIT_COMBAT in one capture. The belief and the wowsims replay take it as in
  at the swing; if it comes with the wound, the lift goes and the replay's rage lands with its wound.

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
prompt, in the client's `Interface\AddOns` folder, remove the old link and create the eight:

```
rmdir Hekili
mklink /D Hekili \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili
mklink /D Hekili_Shared \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Shared
mklink /D Hekili_Warrior \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Warrior
mklink /D Hekili_Druid \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Druid
mklink /D Hekili_Rogue \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Rogue
mklink /D Hekili_Paladin \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Paladin
mklink /D Hekili_Shaman \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Shaman
mklink /D Hekili_Hunter \\wsl.localhost\personal\home\zack\src\hekili\src\Hekili_Hunter
```

Then restart the client fully (a moved addon is not picked up by `/reload`).

### Specs (one spec per talent tree; `/reload` after the update, no client restart)

The client reports one pseudo-spec per class, so each class pack registers a spec per talent tree and the active spec
follows the tree with the most points: the spec activated for that tree, else its first spec.
1. **Rogue:** `/hekili` shows Assassination, Combat and Subtlety nodes with their icons; Subtlety's page has "Backstab
   Builder", Combat's does not; the shared preferences ("Bleeds on Trash", "Vanish to Re-open") are on all three.
2. **First login after the update (any class):** the active spec is the tree with the most points (Snapshot:
   `spec: <key> (dominant)` on the first pass, `(stored)` after a `/reload`); the old thresholds (e.g. "Bleeds on Trash"
   if you changed it) appear in every supported spec of the class; your previous priority choice is kept.
3. **Override:** press "Activate Subtlety" on Subtlety's page (or `/hekili spec subtlety`); the displays switch to its
   priority, the page shows the gold "Active" marker, the tree lists Subtlety first with a gold highlight; `/reload`
   keeps it; a respec into another tree switches to that tree's spec, and back restores Subtlety.
4. **Priorities:** each priority sits under its spec's node in the tree (the Warrior's Arms, Fury, Protection);
   exporting Fury and importing it on the same character binds it to Fury.
5. **Druid:** Feral is selected for a Feral build; `/hekili spec guardian` switches to the bear priority; choosing
   Restoration hides the displays, its page says "No priorities on Forever for Restoration", and no "modules loaded"
   warning appears when casting. Is the client's Druid pseudo-spec 1483 (assumed; it now only keys the legacy
   migration, as Hunter 1484, Paladin 1486, Rogue 1488 and Shaman 1489 do)?
6. **Warrior:** Arms, Fury and Protection run their "(wowsims.com)" defaults; Arms's page carries Stance Dance and
   Recklessness, Fury's Rend Weave and Recklessness, Protection's none. The DB2
   puts Improved Slam (12862) on Fury and Improved Thunder Clap (12287) on Arms: does the client's talent frame agree?
   (They count toward those trees' points.)
7. **Paladin and Shaman:** a Paladin with mostly Holy points, or a Shaman with mostly Elemental or Restoration points,
   lands on an idle unsupported spec (no displays) until you pick another with `/hekili spec` or the dropdown.
8. Report the Snapshot's first lines (`VSCopy`) for each character if anything differs.
