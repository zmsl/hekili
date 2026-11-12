# Writing a wowsims.com pack

How a class's default priorities are made: each spec's priority is wowsims/forever's own APL (MIT,
https://github.com/wowsims/forever), translated to this addon's keys and gated against wowsims's own fight. The
pipeline, the pin, the gates and every pack's current numbers are in `docs/dev/layout.md` ("wowsims packs"); the
step-by-step procedure the lanes ran is the plan's "per-spec procedure" (P1-P10,
`docs/superpowers/plans/2026-10-19-wowsims-packs.md`). This page is what a pack author needs to know beside them.
What only the game can answer (the in-game checkpoints and the long-term items) is in `docs/dev/ingame-ledger.md`.

Each spec has its own pin (`tools/wowsims/export.lua` `M.SPEC_PIN`, read by `M.pin(spec)`): the wowsims/forever
commit its recipe, request and log come from, `OLD` (e2842f0a78, the 11-02 re-pin) or `NEW` (e5a9cd2a2d, the 0.7
re-pin; moved from 4b0030a44b on 2026-11-07, CN18) while the pin moves ("Moving the pin" below;
`tests/Forever/wowsims_pin_spec.lua` checks every log's header against its spec's pin). `export.lua export <spec>`,
`siml <spec>` and `rerun <spec>` refuse a checkout not at the spec's pin and use that checkout's oracle CLI (`make wowsims-sim-cli WOWSIMS=<checkout>`). A recipe's `siml` (a .siml build in the checkout) is converted
first by `export.lua siml <spec>` (`make wowsims-siml SPEC=<spec>`) to `tests/Forever/wowsims/<spec>.build.json`, which
the request reads as its build.

Request edits the new sim needed (2026-11-02), none changing what an APL entry does:
- `greaterBlessingOfWisdom` / `greaterBlessingOfMight` `true` -> `2` (upstream made them a rank state; 2 = the old top
  rank), in the 9 requests that set them. At the re-pin the builds carry `1`, which is rank 1 (25894 / 25782), so
  `M.request` sends any greater blessing a build sets as `2`, the top rank (ruling R25).
- Talent strings re-encoded by spell ID on the new trees (7 requests: Feral, Guardian, Arcane, Fire, Frostfire,
  Protection and Retribution Paladin): ranks clamped to the new maximum points, talents removed upstream dropped, no
  point reassigned (Fire's Critical Mass 5 -> 3).
- Warrior Fury and Arms: Whirlwind's `{spellId 1680, tag 1}` -> `tag 14` (upstream tags hand-split spells by item slot;
  Fury 4 refs, Arms 2).
- Guardian: Lacerate (now a talent, 1328617) gets 1 point, taken from removed Berserk (417141); Primal Bite rank 4
  1238073 (removed upstream) -> 1238070, the new top rank.
- Left as they are: hunter `petAggression`, the encounter's `executeProportion25/45/90` (dropped from `M.ENCOUNTER` at
  the re-pin; the checked-in requests keep them until re-exported) and Shadow's hidden
  `dotExpectedDps` entry, which the proto silently drops without changing the sim.

### Moving the pin

The 0.7 re-pin moves every spec from `OLD` to `NEW` one class lane at a time (central need CN1). One-time setup, by
the coordinator, before the class lanes start (only one build per checkout, never while a lane exports from it):
`git -C ~/src/wowsims-forever worktree add --detach ~/src/wowsims-pin-e5a9cd2a2d e5a9cd2a2dfc9e29e63fd6ec1fc7245ad4b44664`
(never change ~/src/wowsims-forever's own HEAD), then `GOPROXY=off make wowsims-sim-cli WOWSIMS=$HOME/src/wowsims-pin-e5a9cd2a2d`
(offline; Go, protoc and protoc-gen-go on PATH; about 2 minutes). The `OLD` oracle stays in ~/src/wowsims-upstream.

A class lane flips a spec, the flip and the new log in one commit (the pin spec checks each log against its line):
1. Change the spec's own line in `M.SPEC_PIN` from `OLD` to `NEW` (the one line of `export.lua` a class lane edits;
   the blank lines between entries keep two lanes' flips from conflicting: leave them).
2. Fix the recipe for `NEW` (paths, talent string, options from that commit's presets) and re-export:
   `WOWSIMS=$HOME/src/wowsims-pin-e5a9cd2a2d .lua/bin/lua tools/wowsims/export.lua export <spec>`.
3. `make wowsims-packs && make packs`, then the spec's replay and gates, floors by R6.
A spec flipped while `NEW` was 4b0030a44b fails the pin spec once `NEW` names e5a9cd2a2d: re-export it from
~/src/wowsims-pin-e5a9cd2a2d (step 2; the CN18 drift report says what moves per spec).
A flip always uses `export`, never `rerun`: requests carry no pin, only the log header does, so `rerun` would give a new log on the old request (old APL and talents) and still pass the pin spec.
A spec still at `OLD` keeps exporting and re-running against ~/src/wowsims-upstream (pass `WOWSIMS=$HOME/src/wowsims-upstream`: the default `WOWSIMS`, ~/src/wowsims-forever, is at neither pin, so leaving it out is refused, not wrong); `dry.lua` uses one `WOWSIMS` for every spec, so once the pins are mixed the specs on the other pin print `error`; untouched. When every line says
`NEW`, the coordinator collapses the pin: `NEW` becomes the only commit, `OLD` and `tools/wowsims/sim-pin/e2842f0a784d/`
go, and `M.SPEC_PIN`'s entries all name one pin (the state the pin spec then checks).

### Oracle patches

`make wowsims-sim-cli` (`tools/wowsims/sim-pin/build.sh`) builds a checkout's oracle with the patch set of its pin,
`tools/wowsims/sim-pin/<first 12 hex of the pin>/`, then restores the checkout; it refuses a checkout at no pin of
`export.lua`'s. Drop a patch from a set only with evidence that its reason is gone (rebuild without it and compare the
replays).
- Item db (`leftover_db.go`; `OLD` only): the 28 items the requests wore that upstream's live-cache db regen
  (3e9de3f83b) dropped go back in leftover_db.bin, read from d33930d040's db (871, 5267, 10136, 10246, 10247, 10251,
  10253, 10255, 10271, 11904, 13001, 13002, 13015, 13022, 13070, 13072, 13077, 13096, 13116, 14332, 14978, 14979,
  271928, 271948, 272411, 272414, 272415, 284716: not in the live client's cache; their procs are upstream's, so Flurry
  Axe 871 has no extra attacks). Not in the `NEW` set: at e5a9cd2a2d (item db 70862) every item the checked-in
  requests wear (186) and every gear-set JSON item (181) is in the db; 7 of the 28 are still absent (871, 11904, 13002,
  13015, 13070, 13072, 13116) and nothing wears them. A re-export whose gear the `NEW` db lacks fails in wowsimcli: bring it back then.
- No cast-end pick (`no-cast-end-pick.patch`; both sets, re-cut for `NEW`): upstream 1435e39a74 (#640) picks a
  hardcast's next cast at the cast's end, before it lands (its "Queueing up" lines), so an APL without upstream's later
  `not(Spell Is Casting)` guards recasts on a proc or stack the landing cast just spent (a second Pyroblast on spent
  Heating Up). Hekili's next icon is computed with the cast landed, which is the right play. The patch makes the pick,
  its landed aura reads and its mana-after-cast off (a constant, not a switch). It changes only logs with a hardcast
  (the casters, Arms' Slam). Upstream still picks at the cast end at e5a9cd2a2d (sim/core/gcd.go pickAtCastEnd), so the
  `NEW` set keeps it; only the readLanding hunk moved (sim/core/apl_values_aura.go:43): upstream added a channel-clip
  lookahead branch (`endedChannel`) before it, which is not the pick and stays unpatched.
- Darkmantle set ID (`darkmantle-set-512.patch`; both sets): upstream dba41b7ac3 (#677) re-registered the Darkmantle
  Armor reissue under set 1676 (sim/common/forever/items_sets.go), but its db gives the pieces (22003-22009) setId 512,
  so a rogue wearing them got no 2/4/6-piece bonus (Rogue Armor Energize 27788 and the 14049 / 18679 procs gone). Still
  so at e5a9cd2a2d. Likely an upstream bug (report it); the patch registers it as 512. Changes only the three rogue
  logs. Drop it when upstream's set and db IDs agree.

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
  `distanceFromTarget`, `inFrontOfTarget`. Or `build`: a preset build file whose `player` is taken whole (Feral), with `gear` (a gear-set
  JSON path) replacing its equipment; a build file with no equipment (Warlock's) needs `gear`, or the export stops
  (wowsimcli crashes on a player without equipment).
- Or `siml`: a .siml build path in the checkout (the Hunters' `builds/*_weave.siml`), an export path key like `apl`
  and `build`. `export.lua siml <spec>` converts it to the checked-in `tests/Forever/wowsims/<spec>.build.json`, whose
  `player` (talents, gear, options, rotation) is taken whole; no `player`, `build` or `apl` beside it.
- `apl` is optional when the build carries the rotation (Enhancement's `testing.build.json`, every `siml` build).
- `apl`, `gear`, `player.gear` and `build` may each end in `.siml` (upstream's `default.apl.siml`, `default.gear.siml`,
  a whole build): `M.request` reads it through `siml parse -json` of the CLI of the checkout at the spec's pin
  (`WOWSIMS_CLI`, else `$WOWSIMS/wowsimcli-sim-pin`), which gives the APL, the equipment or the build as the JSON file
  would; a `.siml` `build` takes `defaults` like `siml`. The CLI's directory must be a checkout at `M.pin(spec)`, or the
  export stops naming spec, pin and path (the `OLD` CLI cannot parse `NEW`'s Paladin siml: flip the spec first).
  `M.simlParse` (the parse) and `M.simlBuild` (a `siml` build over its `defaults`) are shared with `drift.lua`, which
  parses with `WOWSIMS_NEW_CLI` instead.
- `tank = true` and `healingModel = { hps, cadenceSeconds, ... }` for a tank spec: the player becomes the raid's tank
  and gets the preset's incoming healing, as wowsims's UI does (apply_defaults.ts). Without them the target swings at
  no one (GAP AE: the first Protection and Guardian floors were set on fights with no incoming melee).
- `vars` (`{ [variable name] = "<const>" }`): the APL `valueVariables` a build's simple rotation writes over the raw
  APL (upstream's `simpleRotation`, e.g. the Rogues' `'Use Backstab': String(simple.useBackstab)`, spec.ts:195;
  ruling R29). The request carries them, so the pack follows. Only the named variables change; a name the APL lacks raises.

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
  Clearcasting) and Victory Rush (its kill window; a recipe `extra` line, so `victory_rush,focus=1` in the line itself).
  The Warrior rage dumps Heroic Strike and Cleave are always tier 2, every line of them (owner ruling 2026-10-22,
  superseding the 2026-10-21 `{ 1, 2 }` form).
  Tier 2 is upkeep: DoTs, debuffs, buffs, seals and shields kept up (not totems) (Rend, Rake, Rip, Moonfire,
  Scorch for Fire Vulnerability, Hunter's Mark, Demoralizing Roar, Flame Shock). Cooldowns, consumables, defensives,
  movement and pre-pull lines carry none (the translator drops a tier on a `prepull_at` line). A line whose role is
  arguable (the Twist of Light seals) keeps its tier until the user rules; the recipe says
  so. `tests/Forever/focus_roles_spec.lua` holds every pack's tiers.
- `requires` (`{ [action or group snake name] = talent key }`): entries written for a talent build run only once the
  talent is taken (Retribution's Twist of Light lines; Warrior's Berserker Rage, the user's ruling below). Not added
  when the condition already has the talent test as a top-level `&` term. A key naming no APL entry is an error (CN12; an omitted entry still matches).
- `guard` (`{ [action or group snake name] = SimC expression }`): one `&(<expression>)` term appended to each such
  entry's condition, in every list (rule 16's select lines too); a key naming no APL entry (an action, a group, or a
  move entry `"<list> #<n>"`) is an error (CN12: an upstream rename would drop it silently; an omitted entry still
  matches). A deviation from wowsims, so only on the user's ruling, named in the recipe and under "Deviations by
  ruling" below.
- `windowVars` (`{ [variable name] = window }`): an APL variable that times "since the last shot or swing", read from
  the kit's registered window instead (rule 10: `window.<w>.up&window.<w>.elapsed<op>x`; the hunters' "Just shot"
  from `weave`). A name the APL's variables lack is an error (CN12).
- `condition` (`{ [action] = SimC expression }`): replaces the APL's condition of each cast line of that action, in
  every list (`requires` and `guard` still apply; an error when no line casts it). A deviation from wowsims, so only on
  the user's ruling, named in the recipe and under "Deviations by ruling" below (Balance's Innervate, R20a). A
  `cancelAura` line is addressed as `cancel_buff`, and `condition = { cancel_buff = false }` omits that line (listed in
  the `# Omitted:` header as "the recipe's condition is false"; R69a, Feral's Ravage opener). The key `cancel_buff` is shared by every `cancelAura` line, so `condition = { cancel_buff = false }` omits all of them
  in a recipe that has several.
- `notes` (`{ "<sentence>", ... }`): player-facing lines added to the pack's in-game description (what the toggles
  hide, what a player gates by hand).
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
- `leveling` (lines appended to `actions`): a real rotation ability a lower level casts for a genuine need (its buff
  or seal down or about to expire, a debuff missing, a stack low, a resource to spend), each silent at 60; never a
  recast of a still-active buff to fill an idle window (owner policy R41, below).
- `levelingFirst` (lines put first in `actions`): a form the sim starts in and the APL never casts (Balance's Moonkin
  Form), which a trailing line would never reach; silent while the form is up. They lead a non-empty precombat list
  too, so a pre-pull cast never shows before the form.
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
- `prepullSkip` (`{ "<action>", ... }`): omits that action's `actions.precombat` lines, each listed in the header
  (the translator errors when there is none). Only under an owner ruling against a wowsims pre-pull cast, named in the
  recipe comment: Retribution's "the pre-pull must not twist; one starter seal, Seal of the Crusader" (2026-10-21)
  drops its -3 s Seal of Command.

The autocast context: rule 13 reads the spec's exported log (`tests/Forever/wowsims/<spec>.log`, its "Major cooldown
used" lines), so `make wowsims-packs` needs the checked-in log; a re-export can move those lines.

Replay knobs are not recipe fields: the spec file passes them to `ws.gate` (`tests/Forever/helpers/wowsims.lua`;
`ws.replayOptions(C, spec, o)` builds the gate's set): `forms`, `hidden` (auras the client cannot see, in the truth
only), `procs` (`{ [id or "id:tag"] = true }`: neither a decision nor a cast), `totems` (`{ [key] = { slot, duration
} }`), `speed`, `regen`, `fsr`, `pull`, and from the request `creatureType` and `distance`
(`tests/Game/harness/replay.lua` `M.new`).

## The translator's rules

`tools/wowsims/apl.lua`'s header is the authority; one line each here, with what each leaves out:

1. One line per entry; `prepullActions` -> `actions.precombat`, in wowsims's `doAtValue` order (earliest first); groups
   -> called lists; variables inlined. Omits a prepull entry with no constant `doAtValue` or one after the pull (a time folds from
   constants, `math`, the kit's base cast time and its unhasted GCD, each a `# Deviation:` line, and a spell's travel
   time: the request's `distanceFromTarget` over the kit's `velocity`, its `flightTime` if it has one, 0 with neither, as
   wowsims's distance over missile speed; translator-2: the Warlocks' Shadow Bolt / Soul Fire opener: a hardcast with
   no aura of its own gets no guard, so in game it shows until cast and the pre-pull line after it waits). Each
   pre-pull cast (precombat and the lists only it calls) gets a guard against recasting, a mechanical derivation from
   its ability's handler (recorded once): its own aura `!buff.<key>.up` / `!debuff.<key>.up` (none when the aura's
   duration is at most the cooldown: Bloodrage), its totem `!totem.<element>.up`, else none (Charge); a mutually
   exclusive group's first line (seals: each handler removes the other's aura) by every member's aura. A handler that
   raises gives no guard and a header note.
2. Omitted (and listed in the `# Omitted:` header): hidden entries, conditions folding to false, nodes the fork
   lacks (`sequence`, `resetSequence`, `schedule`, `itemSwap`, `move`, `wait`, `sequenceIsComplete`, ...), an entry
   whose own action is unmapped, a call of an empty group, a cast aimed at another target (`target` Target with an
   index above 0, never read as the current one; aura audit C7).
3. An all-empty group is an ON/OFF switch: `settings.wowsims_<name>`, its wowsims default; the header lists it only
   when an emitted line reads it (ruling L14), and the class registers exactly those (with the recipe's `settings`).
4. `auraIsKnown`: a talent's `enabled`, an ability's `known`, else `true` (a gear or enchant aura too, worn or not:
   the branch then rests on the aura's read, Warlock Revelation); another unit's or player's aura is false; an ID
   nothing resolves is false with a header note (`auraIsKnown of the unresolved aura <id> folds false`). A recipe's
   `knownAs = { [aura ID] = talent key }` makes that aura's `auraIsKnown` the talent's `enabled` (a build's "X known"
   variable on a talent's own aura).
5. Keys from the character's ability set (kit, shared, every race): `map`, `auras`, then the set (an ability's key
   reads as an aura only where the kit registers an aura under it, else rule 12's nil: Enhancement's Stormstrike
   debuff 17364). Ignores
   `includeReactionTime`, `rank` and tags.
6. The leveling guard: a read of an unlearned ability is wowsims's nil and drops its term, as wowsims's nil
   propagation does; `tools/check_pack_levels.lua` checks every pack for it. `min` / `max` values are the engine's
   `min(...)` / `max(...)` with each term that may be nil as `(<known>&<term>)` (false, which they skip).
8. Constants: Go durations in seconds; `"N%"` as N against a percent read (`mana.pct`, `health.pct` run 0-100), N/100
   anywhere else (in `math`, against any other read), as wowsims reads it; a percent read inside `math`, `min` or
   `max` is unsupported (its 0-100 scale would leak).
7. `focus`, `use_off_gcd=1` for an off-GCD ability, `leveling` and `extra` lines, `prepullSkip`, `requires`, `guard`,
   `condition`; an `and`/`or` writes a repeated term once.
9. `auraIcdIsReady`: `buff.<key>.icd_ready` for an aura declaring `icd`; else unsupported.
10. `auraShouldRefresh` only for `exclusive` auras; `cancelAura`; `autoSwingTime`; `remainingTime` as
    `fight_remains` (API-forced: unknown, 3600 s, on Forever; the replay world answers the log's time to its end,
    R42, a replay-world assumption: loops and live keep the game's unknown); `multipleCdUsages` without a base spell
    as wowsims's test on it (`alignCdEnd`: `fight_remains<=D|fight_remains>CD+D/2`, D the spell's buff), else true.
11. `unitDistance` against a whole number as `target.within<N>`/`outside<N>` (API-forced: a bracket from range
    checks, never yards; unknown never blocks).
12. An unresolvable read drops only its branch (a deviation when wowsims has the aura or spell and the fork does not;
    each such ID is listed).
13. `autocastOtherCooldowns` / `castAllStatBuffCooldowns`: one line per cooldown the log shows wowsims using (an
    off-GCD one shown as soon as ready: a documented deviation). `autocastOtherCooldowns` also takes every racial
    cooldown the class can have (not only the sampled race's; defensive ones for a tank only), each inert for another
    race. Not modelled: explosives' after-GCD timing; trinkets and explosives of other gear (one sampled gear set); an
    unmapped item is listed, not written.
14. `strictSequence`: consecutive lines behind `prev.1`. Deviations: nothing else is held off between members, a later
    member re-reads the sequence's condition, an outside cast of a member opens the next.
15. `maintenance`: the action's lines behind its setting; other lines' reads of its aura as "up or disabled"; an
    absence read stays. Not a wowsims rule: the in-game default (off) is ours, the harness runs wowsims's (on).
16. `select`: an option-selected cast as one line a candidate under its choice setting's term; its "active" value as
    the selected candidate's debuff (false with none selected, as wowsims; another candidate's term behind its known
    test, so an unlearned one reads down and the level checker sees its guard); its "is" value as the
    setting term. Unsupported: an "is" with no field (protojson's zero value) or an unknown option value.
17. `multidot`: the DoT's cast while its DoT has at most `maxOverlap` left, on the current target only (`maxDots` is
    a `# Deviation:` header line per entry; no `cycle_targets`: other targets' DoTs are not readable on Forever).

The second translator lane (0.7): `spellIsChanneling` is `action.<key>.channeling` for a kit ability declared
`channeled`, false for any other (CN14: Affliction's Siphon Life line); `frontOfTarget` and `targetIsMobType` fold to
the request's constants, `inFrontOfTarget` (absent: false, behind the target) and the encounter target's `mobType`
(absent: unknown, so every type test is false), each a `# Deviation:` line where its entry emits, since the client gives
no facing and the target's creature type is not read (CN16: Subtlety's Ghostly Strike, Fury's Dragonkin/Giant Spearing
Strike weave, which folds false on the Mechanical target); `autoTimeToNext` MeleeAuto is `min(mainhand_remains,
offhand_remains)` and AnyAuto adds `ranged_remains` where the kit registers it (translator-5: Fury's Bloodrage,
Enhancement's AoE Chain Lightning; a hand with no weapon reads 3600 s, never; a kit without both hand
clocks leaves the entry unsupported). The weave's `wait` rows stay omitted (CN19): a `wait X if C` holds wowsims's
rotation for X, but the engine already times each line at its own ready moment, so a hold for the GCD (weave #2) is
what it does anyway, and a hold for Strider Kick (weave #3) only matters against a line below it in wowsims's order
that is ready sooner: those are the move arms of weave #4/#5 (with the Movement toggle on), which rule 19 places at
the weave call, where its held-gate carry (lines whose entry comes after the call) does not reach; a hold would need
that carry extended. The display difference
the re-pin triage found (Immolation Trap shown where wowsims kicks, repin-triage-report.md case 1) is not reproduced
by a hold: the trap's own line ranks above the weave, so its cause is untraced (the walk-in Hekili does not forecast is
the candidate); a deferral, revisited with a traced tick.

Upstream's newer values (CN4): the "on all/any targets" aura and DoT reads are the current target's, each a
`# Deviation:` line; of the current target, "is active" is true, "time until active" 0 and "time until it dies"
`fight_remains`; `numActiveAdds`, `remainingCastTime` and another target unit are unsupported.

`spellExpectedDpet` stays unsupported (CN5, L84). wowsims computes it from the spell's own damage formula, at the
fight's remaining time (sim/core/apl_values_spell.go `GetFloat`, upstream 4b0030a44b):
- the expected initial and tick damage, which needs coefficients, spell power, the target's modifiers and crit;
- the hasted cast and travel time;
- the ticks that land before the fight ends: 0 once the cast would land after the end.
None of these is available to Hekili. The kits model no damage (the drift report's "the kit does not model damage",
per spec). Damage and attack speed are secret in combat on Forever (probe 2026-10-13). The fight's
remaining time is unknown in game (`fight_remains` 3600, gap AN). So a translated DPET would be a constant guess
dressed as wowsims's value. The entries stay omitted, and a spec that needs their effect keeps a recipe stand-in by
owner ruling:
- SM Ruin's DoT lines (R49): cast each DoT when it is down or within its cast time of falling. They keep the DoTs that
  wowsims's DPET keeps up, but not its "stop refreshing in the last seconds", which needs the fight's end.
- At upstream 4b0030a44b, Shadow's preset un-hides its Starshards line (`spellExpectedDpet(Starshards) >
  spellExpectedDpet(Mind Flay)` with Mind Blast at least 4 s away). Its re-export gets a new `# Omitted: default #11:
  spellExpectedDpet`. Whether it needs a stand-in is the Priest lane's question for the owner.

Any node the translator does not handle is unsupported (rule 2): a new wowsims node omits its entry rather than
mistranslating it.

## Deviations by ruling

Each is the user's ruling, recorded with its reason; the recipe header names the replay decisions it moves.
- Warrior Arms and Fury, Berserker Rage (2026-10-21): "should be guarded by a check on Improved Berserker Rage > 0
  ... only use precombat / combat if talented for the rage gain": `requires = { berserker_rage =
  "improved_berserker_rage" }`. The wowsims builds lack the talent, so wowsims's pre-pull Berserker Rage at -4.5 is a
  disagreement (one decision each; floors 0.89 and 0.91).
- Warrior Fury, the Battle Stance swap in overpower_weaving (2026-10-21): "guard against recommending battle stance if
  there won't be enough time or rage to cast overpower". wowsims's condition (Overpower: Can Cast and `gcd = 0`)
  checks only the rage before the swap (5 to 100); below Tactical Mastery (level 14, Overpower 12) the swap keeps no
  rage, and nothing compares Overpower's 5 s cooldown with the 5 s window. `guard = { battle_stance =
  "!action.overpower.known|(stance_rage_kept>=action.overpower.cost&cooldown.overpower.remains<buff.overpower_ready.remains)" }`
  (`stance_rage_kept`: the kit's state expression for the rage a swap keeps; Tactical Mastery is a passive no priority
  reads).
- Druid Balance, Innervate (owner R20a, 2026-11-04): wowsims's `(fight_remains>380&mana<70%)|(mana<40%&fight_remains>30)`
  keeps only its low-mana branch: the fight's length is unknown in game (gap AN: `fight_remains` reads 3600), so
  "fight > 380 s" cannot be known and the long-fight branch would fire under 70% mana in every fight.
  `condition = { innervate = "mana.pct_lo<40&fight_remains>30" }`.
- Druid Feral, the Ravage opener (owner R69, 2026-11-06): "We should have it cast Ravage if we're prowling up to a mob"
  and "the player can make the decision to not ravage if they can't get behind. We're recommending the optimal
  ability." wowsims's 'Drop Prowl for this opener' folds to always-true solo (its Ravage opener needs another druid's
  Faerie Fire, tag -1), so Prowl would be cancelled at once and Ravage never shown. `condition = { cancel_buff = false }`
  omits the cancel line and `guard = { faerie_fire = "!action.prowl.known|!buff.prowl.up" }` keeps Faerie Fire (which
  breaks Prowl) behind Ravage while Prowled. No 'behind the target' signal and no fallback timer: Ravage stays the
  first icon while Prowl is up and the target is in range; Prowl ends when Ravage lands or the player attacks. The
  replay and loop worlds do not know Prowl or Ravage, so they do not see the deviation (unit-tested in druid_spec).
- Druid Feral (and Guardian's imported Cat lines), Claw vs Shred (owner, 2026-11-11, L597-L603): solo, the mob attacks
  the player, who cannot be behind it, and Claw out-damages Shred per energy below 2 ranks of Shredding Attacks (Claw
  r2 140% + 39 for 40 energy with Ferocity, Shred r2 200% + 32 for 60, -6 a rank; both free under Clearcasting, where
  Shred wins). `guard = { shred = "(settings.behind|!target.is_targeting_player)&(talent.improved_shred.rank>=2|buff.clearcasting.up)" }`
  on every Shred line; `condition = { claw = ... }` is wowsims's translated Claw condition with `!action.shred.ready`
  replaced by `(!settings.behind&target.is_targeting_player|talent.improved_shred.rank<2&!buff.clearcasting.up)` and
  `energy.lo>=action.shred.cost` by `energy.lo>=action.claw.cost` (no recipe key edits part of a line, so the rest is
  the generated text, re-copied on a re-pin). `target.is_targeting_player` is the core's
  UnitIsUnit("targettarget", "player"), false when secret or unknown (assume behind); `settings.behind` is the class's
  "Always Behind" option. The replay world answers that the target attacks someone else (wowsims stands behind;
  replay knob `notTargeted`) and the build has 3/3, so the replay is unchanged; the loops' mob attacks the player.
- Rogue Combat, Riposte (owner R70, 2026-11-06: "add it to the apl and make it focus=1"). A recipe `extra` line before
  Garrote (the first line left once the new pin's APL dropped its Ambush opener: re-anchored, L143):
  `riposte,use_off_gcd=1,focus=1,if=energy.lo>=action.riposte.cost`. The 5 s parry window is the kit's registered window
  `riposte` (Rogue.lua, evaluator = the client's usability answer: L138 migrated), which Riposte's own `usable` reads, so
  the line carries no window term (a recipe `extra` line cannot name a kit window: the translator treats `window.X` as a
  sequence's). wowsims never plays it (no parry on us in its fight; at 4b0030a44b the Combat SS build does not take the
  talent), so it moves no replay or loop number. Not checked in game.
- Priest Shadow, Starshards (owner 2026-11-07: Starshards by user preference replaces spellExpectedDpet default #11): upstream's
  default #11 casts Starshards when its expected damage per execution time beats Mind Flay's and Mind Blast is 4 s or more from
  ready; the translator cannot compute the first term (CN5). A recipe `extra` line before Mind Flay,
  `starshards,if=settings.prefer_starshards&(!action.mind_blast.known|cooldown.mind_blast.remains>=4)`, with the class setting `prefer_starshards` (off by
  default, no `sim` default, so the default pack and every number are as before). Only matters when Starshards is known (the
  Night Elf racial). The Human replay and loops never cast it. Not checked in game.

## Pack notes

What players read in a pack's description (the recipe's `notes`), and why. Warrior (the user's rulings, 2026-10-21):
- The kit's toggles: Cooldowns hides Death Wish, Sweeping Strikes and Recklessness (Arms and Fury; Recklessness also
  behind its `wowsims_recklessness` pack setting, off by default) and the racials; Defensives hides Healthstone and
  Disarm (no Warrior pack line casts Disarm) and, in Protection, Shield Wall, Last Stand, Stoneform and Shatter Curse;
  Potions hides none in Warrior. Bloodrage, Intimidating Shout and Mocking Blow are under no toggle.
- Protection's defensive lines (Last Stand, Shield Wall, Stoneform, Shatter Curse, Healthstone) wait on a health
  threshold, and the client hides player health in combat, so they never fire there: API-forced, players press them
  by hand.
- Protection's Demoralizing Shout (off unless Maintain Demoralizing Shout is on, rule 15) and Thunder Clap: a player
  keeps them for bosses with the per-ability Boss Encounter Only option or the Custom 1 toggle (no code change; the
  user approved the audit's proposal).
- Rend is used on every target, boss or not; Death Wish stays under Cooldowns; Sunder Armor is unchanged (the
  in-game ledger, docs/dev/ingame-ledger.md, holds its Boss Encounter Only question).

Casters and Hunter (unit-registry spec §5.4, 2026-10-22): each projectile, DoT and shot declares `expects` with its
DB2 `velocity` and `school` (checked by `make spell-data-check`). Their outcomes now pay their own casts (a projectile's
landing up to `rMax / velocity + 0.15` s after its success), so `SPELL_DAMAGE` rows reach Hekili's enemy tracker for
the first time (`ns.updateTarget`, `Engine/Sim/Events.lua:1735-1743`). Expected: the replay floors of Balance,
Affliction, Destruction, Demonology, Arcane, Fire, Frostfire, Elemental, Shadow, Smite and the three Hunter specs rise
or hold (crits now run `onCrit`, misses refund); an AoE line's target count may read higher, each such move named in
the gate's report. The melee packs keep their default types but for their non-damaging instants (2026-10-25): each
declares `expects = "debuff"` (avoids only; unit-registry spec §5.4's table).

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
- The limit is 6 s at the lower brackets (10, 20, 40) and `max(6 s, LIVE60)` at 60 (re-pin ruling R22), LIVE60 the
  pack's own worst idle at 60 rounded up to 0.1 s. wowsims is the oracle: its idle at 60 (pooling, running out of mana)
  is correct and never "fixed"; a lower bracket never borrows it.
- Fillers are never added for filling's sake (owner policy R41, 2026-11-05; it replaces "a lower bracket over the
  limit gets a recipe `leveling` filler, never a higher limit"). A `leveling` or `extra` line is a real ability a
  player normally uses in that rotation, cast for a genuine need, silent at 60 (`!action.<a level-60 ability>.known`);
  a recast of a still-active buff or seal to occupy an idle window is forbidden, and no line is added to pass this
  gate. An idle window with nothing useful to cast is correct: that bracket gets a measured per-bracket limit with the
  named cause `nothing useful to cast: <what is cooling / what is up>` in the spec comment (owner FYI), never where a
  real rotation ability was castable. Paladin: Retribution and Protection L10 8.6 s (Holy Strike and Judgement
  cooling, the seal up), Protection L40 8.4 s (out of mana). The 60 line and the floor must not move.
- Recorded exceptions from before R41. Fury below Bloodthirst
  (`FURY_LIVE[10] = 7.6` in `tests/Forever/wowsims_warrior_spec.lua`, the owner's call): its leveling Sunder
  Armor filler stops at five stacks since central fix 18, so the recipe's own idle at L10 (in Battle Stance, pooling
  for Heroic Strike) returns; it was 2.6 s while Sunder at five stacks filled the gaps.
- The second recorded exception (final review fix 3, the owner's call): the gate counted every press as ending an idle
  stretch until then, so an off-GCD press (Heroic Strike, Bloodrage, Maul) hid the on-GCD idle around it. Counting
  on-GCD presses only, Guardian's LIVE60 became 10.0 (its L10), a lower bracket's measurement above its own L60. Arms
  (L40 11.2) and Fury (L40 8.6) took a leveling Hamstring instead (2026-10-21), removed by R41 (2026-11-05: not a
  rotation ability, no need): their L10/L40 idles are measured limits with the named cause, `ARMS_LIVE` / `FURY_LIVE`.
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
reads) is UNMEASURED: in-game checkpoint on a class with a channel. A fight's end stops a cast in progress (central fix
31, `W.endCasts`): when our target dies, and when the loop leaves the world after its last tick, a hard cast ends with UnitCastingInfo empty,
UNIT_SPELLCAST_INTERRUPTED and UNIT_SPELLCAST_STOP (no success), and a channel with its CHANNEL_STOP, so no stale cast
start outlives the fight. That order is UNMEASURED (in-game ledger CS1): the client may fire FAILED instead of
INTERRUPTED when the target dies; the belief handles either. An unmapped item's use in a replay log is still our cast
to the client: a success of spell
`replay.UNMAPPED_SPELL` (0, no ability's), which `Events/Rows.lua` reads as "an outcome now may be that item's".

## Talent tables (spec detection)

Spec detection counts the live rank of every node a kit REGISTERS (`spec:RegisterTalents`, `ns.TreePoints`), so a missing or
mis-filed node moves a build's points between trees. The kits' tables follow Forever's tree, `ui/sim/talents/trees/<class>.json`
at the pin (generated from the game files; checked against one Warrior `/fprobe export` of 2026-10-15 only, so a fresh export
per class would confirm it). Copies live in `tests/Forever/fixtures/talent_trees/`.

- `WOWSIMS_TREES=<dir> .lua/bin/lua tools/wowsims/talents.lua all|<class> [--write]` prints or rewrites each kit's table: tree
  = the JSON's order, a spell id the kit has keeps its name (code reads `talent.<name>.rank`), a row named like an unmatched
  node is that node under its new id, other new nodes are snake_case(fancyName), rows the tree lacks are dropped unless
  `M.KEEP` (in the generator) lists them because code reads them. `--write` also refreshes the fixtures. Re-run it on a re-pin.
- `tests/Forever/talent_trees_spec.lua`: every node registered with its tree and max rank, every `talent.<name>` the kit and its
  packs read is registered, and for every recipe's talent string (decoded as `export.lua`'s `M.talents`) the counted points per
  tree equal the string's own. A pack line that reads a talent its own build does not take (a wowsims line gated on a
  talent) is not an error: the translation keeps the sim's condition.
