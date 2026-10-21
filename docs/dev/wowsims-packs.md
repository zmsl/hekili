# Writing a wowsims.com pack

How a class's default priorities are made: each spec's priority is wowsims/forever's own APL (MIT,
https://github.com/wowsims/forever), translated to this addon's keys and gated against wowsims's own fight. The
pipeline, the pin, the gates and every pack's current numbers are in `docs/dev/layout.md` ("wowsims packs"); the
step-by-step procedure the lanes ran is the plan's "per-spec procedure" (P1-P10,
`docs/superpowers/plans/2026-10-19-wowsims-packs.md`). This page is what a pack author needs to know beside them.

## The rules (the user's; binding)

- Every priority is wowsims-built: `"<Spec> (wowsims.com)"`, generated from a recipe. The hand-built lists are gone
  (each class file's `spec:RetirePacks({ ... })`); no work goes into hand-built rotations. A spec with no wowsims APL
  at the pin has no priority until the user decides otherwise.
- Match wowsims as closely as the Forever API allows. A difference the API forces (a secret value, a read the client
  does not give) is an API-forced deviation, recorded with its reason where it lives (the translator rule, the kit
  line, the recipe header); a difference with any other cause is a gap and is fixed in the layer that is wrong.
- Replay floors only move up. A floor goes down only with a named cause recorded in the spec file beside it (a
  measured, accepted change in the world or the export, e.g. Paladin Protection's tanked re-export, central fix 13).
- "We don't want jittery recommendations where we can help it": flicker (the first icon changing and changing back)
  is an acceptance metric beside agreement. Every gate line prints `flicker X/min (oracle Y)`; a change that raises a
  pack's flicker needs a reason, and a display-side hold beats a belief that flashes. Anti-flicker mechanisms (a
  display hold, an addon reaction time) are experimental and off until play-tested.
- Players gate optional lines (Sunder Armor, ...) with Hekili's own per-ability toggles (Custom 1/2, Boss Encounter
  Only, Disable). A pack carries wowsims's defaults, with one exception: the maintenance debuffs. The user's ruling
  (2026-10-21): "We should have maintenance debuffs as toggles on the pack for warrior and druid. That way we can
  default them to false in game, but override to true in the harness for accuracy measurements. That way Berserk can
  say 'if up or disabled'." Open-world mobs die before a raid debuff pays off, so in game it is off; the harness runs
  wowsims's raid boss, so there it is on and the gates still measure wowsims's own list. The recipe's `maintenance`
  (rule 15) names them; each is a setting with two defaults (`default` in game, `sim` under the harness: below).
  The kits put the abilities a player may not want under Hekili's native Cooldowns or Defensives toggle
  (`toggle = ...` on the ability: Sweeping Strikes and Vanish under Cooldowns, Healthstone under Defensives); a
  toggle off skips the line and the list falls through. Buff and resource consumables (Major Mana Potion, Demonic
  Rune, Thistle Tea, Mana Gem; Rogue's poisons) go under the Potions toggle, health ones under Defensives (user, 2026-10-21). The
  harness runs a fresh profile: Cooldowns and Defensives on, Potions off (Hekili's default); no harness world puts a
  consumable in the bags, so no gated line moves.

## The recipe

`tools/wowsims/specs/<class>_<spec>.lua` returns one table. Its header comment names the wowsims files and lines the
values come from and holds the P7 classification (below). `tools/wowsims/export.lua` reads the request fields;
`tools/wowsims/apl.lua` (`M.context`) the translation fields.

Request (export):
- `class` (`"WARRIOR"`), `pack` (`"Arms (wowsims.com)"`), `spec` (the spec key, `"arms"`), `name` (the wowsims spec
  name in the header), `talentTree` (the wowsims tree file), `apl` (the APL JSON path in the checkout).
- `player`: `race`, `class`, `gear` (a gear-set JSON path), `talentsString`, `specKey`, `options` (the spec's
  `DefaultOptions` in protojson: enum values by name), `profession1`/`profession2`, `reactionTimeMs`,
  `distanceFromTarget`. Or `build`: a preset build file whose `player` is taken whole (Feral).
- `tank = true` and `healingModel = { hps, cadenceSeconds, ... }` for a tank spec: the player becomes the raid's tank
  and gets the preset's incoming healing, as wowsims's UI does (apply_defaults.ts). Without them the target swings at
  no one (GAP AE: the first Protection and Guardian floors were set on fights with no incoming melee).

Translation:
- `map` (`{ [spell ID or "item:<id>"] = key }`): a wowsims ID the kit holds under another ID (an effect ID, a rank the
  kit does not list, a trinket as `use_items`). It maps casts and aura reads alike.
- `auras` (`{ [aura ID] = key }`): an aura wowsims keys by an ability's own spell ID, where `map` would also turn that
  ability's casts (Revenge rank 6, 25288, read as the window aura `revenge_usable`).
- `focus` (`{ [action] = tier or { tiers in order } }`, `false` for an untiered occurrence): the display's now-circle
  tier, by the line's role (the user's rule, 2026-10-21; it replaces the retired lists' tiers of P9.3). Rotational
  lines, the spec's core strikes, builders, fillers and finishers (Mortal Strike, Slam, Execute, Bloodthirst,
  Whirlwind, Sinister Strike, Mutilate, Eviscerate, Primal Bite, Wrath, Fireball, Arcane Blast, the Hunter shots and
  melee-weave strikes),
  carry none. Tier 1 is a reactive or windowed line the player must catch: proc-, position- or stance-gated
  (Overpower, Revenge, Pyroblast on Heating Up, Arcane Missiles on Missile Barrage, Shred on
  Clearcasting), and an off-GCD queued strike, with a second line of a rage dump at 2 (`heroic_strike = { 1, 2 }`).
  Tier 2 is upkeep: DoTs, debuffs, buffs, seals and shields kept up (not totems) (Rend, Rake, Rip, Moonfire,
  Scorch for Fire Vulnerability, Hunter's Mark, Demoralizing Roar, Flame Shock). Cooldowns, consumables, defensives,
  movement and pre-pull lines carry none (the translator drops a tier on a `prepull_at` line). A line whose role is
  arguable (the Twist of Light seals) keeps its tier until the user rules; the recipe says
  so. `tests/Forever/focus_roles_spec.lua` holds every pack's tiers.
- `requires` (`{ [action or group snake name] = talent key }`): entries written for a talent build run only once the
  talent is taken (Retribution's Twist of Light lines).
- `maintenance` (`{ [action] = setting key }`, rule 15): a raid debuff kept up (Protection's Demoralizing Shout, Arms's
  Thunder Clap, Guardian's Demoralizing Roar; a key needs a cast line in that spec's pack, else the translator errors,
  so a spec without one, Fury for Thunder Clap, neither names nor registers it). The action's lines (its leveling lines too) take `settings.<key>&`;
  every other line that waits on its aura (`debuff.<action>.up`, `.remains>`) reads it as "up or disabled"
  (`|!settings.<key>`). The class registers the key with `default = false` and `sim = true` (the option field
  `sim`: the harness's default, `Engine.SettingDefault`; loop.new boots in the "sim" scenario, a direct
  `headless.new` in game), one key per debuff, on the specs that cast it.
- `select` (`{ [wowsims action] = { setting = "<key>", option = "<classOptions field>", candidates = { [option value] =
  "<action key>" | false }, active = "<value name>", is = "<value name>" } }`, rule 16): a cast whose spell a class
  option picks (wowsims/forever d33930d040's `castWarlockAssignedCurse`, its option `curseOptions`). The option becomes
  a choice setting read as `settings.<key>='<snake of the option value>'`; the action is one line a candidate (none
  for a `false` one, e.g. NoCurse); `active` names the value "the selected spell's debuff is up" (false while a
  `false` candidate is selected, as wowsims's IsActive with no spell), `is` the value
  "the option is X". The build's option value (the request's `<spec>.options.classOptions`) is the default in game and
  in the harness; the header lists it (`# Setting <key> (choice of <option>: ...), default <value> ...`) and the class
  registers the key as an AceConfig `select` with those candidate keys, `default` and `sim` both the build's. A
  `select` entry the APL never uses is an error.
- `exclusive` (`{ [spell ID] = true }`): the auras wowsims gives an exclusive effect (rule 10's
  `auraShouldRefresh`); neither the DB2 nor the APL says which, so the recipe lists them from wowsims's class code.
- `executePhase` (the key the kit's execute read answers, `"execute_phase"`): wowsims's `isExecutePhase` E20.
- `leveling` (lines appended to `actions`): the fillers a lower level needs, each silent at 60 (below).
- `levelingFirst` (lines put first in `actions`): a form the sim starts in and the APL never casts (Balance's Moonkin
  Form), which a trailing line would never reach; silent while the form is up.
- `extra` (`{ { before = "<action>", line = "<simc line>" } }`): a line put just before the first `actions` line of
  `before` (the translator errors when there is none). Only for content wowsims cannot model, never to tune a
  wowsims line, and each use names its reason in the recipe comment. The user's ruling (2026-10-21), for Warrior's
  Victory Rush: "This isn't something from wowsims, but needs to be added since it won't affect wowsims accuracy
  (wowsims never goes mob to mob so VR isn't ever a thing). Should be used just above bloodthirst (since it's a mini
  bloodthirst)."
- `settings` (`{ <key> = { default = <bool>, desc = "<text>" } }`): a pack setting a recipe line reads as
  `settings.<key>`, listed in the header (`# Setting <key> (<desc>), default <bool>.`) after the ON/OFF groups when a
  line reads it; the class registers it beside the `wowsims_*` ones. For a recipe line a player may want to turn
  off. (Guardian's leveling Demoralizing Roar had `demoralizing_roar_filler`; it is now governed by rule 15's
  `maintain_demoralizing_roar`, below. Faerie Fire, free, has none.)

The autocast context: rule 13 reads the spec's exported log (`tests/Forever/wowsims/<spec>.log`, its "Major cooldown
used" lines), so `make wowsims-packs` needs the checked-in log; a re-export can move those lines.

Replay knobs are not recipe fields: the spec file passes them to `ws.gate` (`tests/Forever/helpers/wowsims.lua`;
`ws.replayOptions(C, spec, o)` builds the gate's set): `forms`, `hidden` (auras the client cannot see, in the truth
only), `procs` (`{ [id or "id:tag"] = true }`: neither a decision nor a cast), `totems` (`{ [key] = { slot, duration
} }`), `speed`, `regen`, `fsr`, `pull`, and from the request `creatureType` and `distance`
(`tests/Game/harness/replay.lua` `M.new`).

## The translator's rules

`tools/wowsims/apl.lua`'s header is the authority; one line each here, with what each leaves out:

1. One line per entry; `prepullActions` -> `actions.precombat`, ordered by `doAtValue` with `prepull_at`; groups ->
   called lists; variables inlined. Omits a prepull entry with no constant `doAtValue` or one after the pull.
2. Omitted (and listed in the `# Omitted:` header): hidden entries, conditions folding to false, nodes the fork
   lacks (`sequence`, `resetSequence`, `schedule`, `itemSwap`, `move`, `wait`, `sequenceIsComplete`, ...), an entry
   whose own action is unmapped, a call of an empty group.
3. An all-empty group is an ON/OFF switch: `settings.wowsims_<name>`, its wowsims default; the header lists it only
   when an emitted line reads it (ruling L14), and the class registers exactly those (with the recipe's `settings`).
4. `auraIsKnown`: a talent's `enabled`, an ability's `known`, else `true`; another unit's or player's aura is false.
5. Keys from the character's ability set (kit, shared, every race): `map`, `auras`, then the set. Ignores
   `includeReactionTime`, `rank` and tags.
6. The leveling guard: a read of an unlearned ability is wowsims's nil and drops its term, as wowsims's nil
   propagation does; `tools/check_pack_levels.lua` checks every pack for it. `min` / `max` values are the engine's
   `min(...)` / `max(...)` with each term that may be nil as `(<known>&<term>)` (false, which they skip).
7. `focus`, `use_off_gcd=1` for an off-GCD ability, `leveling` and `extra` lines, `requires`.
8. Constants: Go durations in seconds; `"N%"` as N against a percent read (`mana.pct`, `health.pct` run 0-100), N/100
   anywhere else (in `math`, against any other read), as wowsims reads it.
9. `auraIcdIsReady`: `buff.<key>.icd_ready` for an aura declaring `icd`; else unsupported.
10. `auraShouldRefresh` only for `exclusive` auras; `cancelAura`; `autoSwingTime`; `remainingTime` as
    `fight_remains` (API-forced: unknown, 3600 s, on Forever).
11. `unitDistance` against a whole number as `target.within<N>`/`outside<N>` (API-forced: a bracket from range
    checks, never yards; unknown never blocks).
12. An unresolvable read drops only its branch (a deviation when wowsims has the aura or spell and the fork does not;
    each such ID is listed).
13. `autocastOtherCooldowns` / `castAllStatBuffCooldowns`: one line per cooldown the log shows wowsims using (an
    off-GCD one shown as soon as ready: a documented deviation). Not modelled: explosives' after-GCD timing; an
    unmapped item is listed, not written.
14. `strictSequence`: consecutive lines behind `prev.1`. Deviations: nothing else is held off between members, a later
    member re-reads the sequence's condition, an outside cast of a member opens the next.
15. `maintenance`: the action's lines behind its setting; other lines' reads of its aura as "up or disabled"; an
    absence read stays. Not a wowsims rule: the in-game default (off) is ours, the harness runs wowsims's (on).
16. `select`: an option-selected cast as one line a candidate under its choice setting's term; its "active" value as
    the selected candidate's debuff (false with none selected, as wowsims; another candidate's term behind its known
    test, so an unlearned one reads down and the level checker sees its guard); its "is" value as the
    setting term. Unsupported: an "is" with no field (protojson's zero value) or an unknown option value.

Any node the translator does not handle is unsupported (rule 2): a new wowsims node omits its entry rather than
mistranslating it.

## Classifying a disagreement (P7)

Run the replay gate with the floor at 0 and read the `wowsims:` line's `decisions on-GCD X (n) top [...]`. Work the top
three once each and record each in the recipe header under "Disagreements (P7; floor F)": the pair wowsims -> ours,
its time in the log, and one class:
- **kit**: the class file models the ability differently (a cost, a cooldown, a talent, a proc window): fix the kit
  with a test, values from `wowdb` (wowsims's spell data where the DB2 lacks a rank, by ruling).
- **world**: the replay or loop world is not the client (`tests/Game/harness/`): a replay limit (below) is named as
  one; anything else is a harness fix.
- **central**: the translator, the engine or the belief is wrong: a GAP in `docs/dev/gaps.md`, fixed centrally,
  never worked around in a lane.
- **API-forced deviation**: the client cannot tell us what wowsims knows; say which read and why.

Also list what was worked and fixed ("Worked: ...") so the next author does not redo it.

## Re-flooring

The floor is the measured `decisions on-GCD` truncated to two decimals, on the first clean run. Raise it when a change
lifts it (each central fix re-floors every pack it lifted: `test(wowsims): re-floor ...` commits). Lower it only with
the cause in a comment beside the number. Each spec file keeps the measured value and its history in that comment.

## Level brackets and liveness

`ws.live` runs the pack on the loop's own world at a level (the class's learn table from DB2, the build's talents
taken in dominant-tree order) and fails on an error, a raise, an unlisted read, no press, or an idle stretch (in
combat, the GCD free, a known on-GCD ability the world would accept, no on-GCD press: an off-GCD press such as Heroic
Strike or Maul does not end it) longer than the limit.
- Brackets: 10, 40 and 60 (Feral 20, 40, 60: Cat Form at 20).
- The limit is `max(6 s, LIVE60)`, LIVE60 the pack's own worst idle at 60 rounded up to 0.1 s. wowsims is the oracle:
  its idle at 60 (pooling, running out of mana) is correct and never "fixed".
- A lower bracket over the limit gets a recipe `leveling` filler, silent at 60 (`!action.<a level-60 ability>.known`),
  never a higher limit; the 60 line and the floor must not move. The recorded exception: Fury below Bloodthirst
  (`FURY_LIVE_LEVELING = 7.4` in `tests/Forever/wowsims_warrior_spec.lua`, the owner's call): its leveling Sunder
  Armor filler stops at five stacks since central fix 18, so the recipe's own idle before that filler (7.4 s)
  returns; it was 2.6 s while Sunder at five stacks filled the gaps.
- The second recorded exception (final review fix 3, the owner's call): the gate counted every press as ending an idle
  stretch until then, so an off-GCD press (Heroic Strike, Bloodrage, Maul) hid the on-GCD idle around it. Counting
  on-GCD presses only, Arms's LIVE60 became 11.2 (its L40), Fury's FURY_LIVE_LEVELING 8.6 (its L40) and Guardian's
  10.0 (its L10), each a lower bracket's measurement above the pack's own L60.
- Limits of the check: one seed, no buffs; the talent order approximates how a player levels; an ID the DB2 lacks
  counts as learned at 1; levels between the brackets are not sampled (Guardian 25-41).

## Casts and channels in the worlds

A content's resolved press (`W.press`, `tests/Game/harness/world.lua`) may carry `cast` (a hard cast: the client sees
UnitCastingInfo and UNIT_SPELLCAST_START at the press with the GCD's flag, then the success and UNIT_SPELLCAST_STOP at
its end) or `channel = { length, tick, gain = { pt, amount }, effect = fn(W, e, p, n) }` (UnitChannelInfo, then
UNIT_SPELLCAST_CHANNEL_START, then the success at the start, with the cost; a tick every `tick` s, its gain and effect;
UNIT_SPELLCAST_CHANNEL_STOP at the end). Other presses are refused "casting" while either runs; a press with `clip = true`
stops a running channel first (wowsims's `interruptIf`: the content sets it when its translation would break the
channel). The replay feeds the same events from the log: a Casting line with a cast time opens the bar, and a completed
cast of an ability the kit declares `channeled` runs until its aura's next fade (a clip, on either unit), else for the
kit's `cast`. The client's order at a channel's start (UnitChannelInfo before the success, which the engine's queue
reads) is UNMEASURED: in-game checkpoint on a class with a channel.
