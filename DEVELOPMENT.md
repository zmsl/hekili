# Developing Hekili Forever

This guide takes you from a fresh clone to a merged change. It is written for two readers: a developer who has never
seen Hekili's implementation, and a priority author who wants to add or change a priority pack. It is the front door.
The detailed references stay where they are, and this guide links to them. Terms such as belief, replay, loop and
gate are defined in the [glossary](#8-glossary) at the end.

| Reference | What it holds |
| --- | --- |
| [architecture.md](docs/dev/architecture.md) | The layers, the engine's interface, the content surface, the packs |
| [layout.md](docs/dev/layout.md) | Every folder, the checks in detail, each pack's gate lines, in-game checkpoints |
| [wowsims-packs.md](docs/dev/wowsims-packs.md) | The rules for priority packs, the recipe, the translator, floors |
| [gaps.md](docs/dev/gaps.md) | Known differences from wowsims and where each must be fixed |
| [publishing/README.md](docs/publishing/README.md) | Packaging, releases and the CurseForge page |

## 1. What Hekili Forever is and how it works

Hekili Forever is a priority helper for the WoW Forever client. It shows the ability to press next and the few after
it. It never presses anything for you: it is a display, with no automation.

### Why the addon cannot simply read the game

WoW Forever runs on a modern client that hides many values from addons during combat. These include resources,
cooldown times, aura durations, target health and combat statistics. Such a value is "secret": an addon can pass it
to the game's own frames, but it cannot read it, compare it or calculate with it. The combat log is not available at
all.

Upstream Hekili read all of those values on every update, so it cannot work as written. Hekili Forever keeps
Hekili's simulation and class model, and replaces the hidden reads with a **belief**: a running estimate of the game
state.

- The belief starts from values the client still answers plainly, such as out-of-combat reads, your own casts,
  "is this spell usable" answers and cooldown flags.
- It carries those values forward with the same models the class pack registers: costs, regeneration, durations.
- Each estimate is a band (low, best guess, high) plus how it was learned: observed, pinned by an event, or modelled.
- When the client reveals something new, the belief corrects itself.

### The simulation and the display

On each update the engine copies the belief into Hekili's simulated state. It walks the active priority list, picks
the first ability whose conditions hold, advances the simulated clock past that cast, and walks the list again. That
repeated walk fills the queue of upcoming abilities.

The engine publishes the result as a set of recommendation records per display. The displays, the WeakAuras bridge
and the headless test loop all subscribe to those records. None of them reads the simulation directly.

### The layers

```mermaid
flowchart TD
    client["WoW Forever client<br/>API calls and events"]
    facade["Facade<br/>the only code that reads the client"]
    belief["Belief<br/>observed, pinned and modelled values"]
    sim["Engine<br/>the simulation walks the priority forward"]
    output["Output<br/>recommendation records per display"]
    subs["Subscribers<br/>displays, WeakAuras, headless test loop"]
    content["Content addons<br/>shared content and class packs"]
    options["Options<br/>the saved profile"]

    client --> facade
    facade -- "plain reads and events" --> belief
    belief -- "secret reads are answered from the belief" --> facade
    belief --> sim
    content -- "abilities, auras, priorities<br/>through the registration API" --> sim
    options -- "settings" --> sim
    sim --> output --> subs
```

Each layer talks only to its neighbours. Content addons reach the engine only through the public registration
interface. The architecture reference has the full picture: [docs/dev/architecture.md](docs/dev/architecture.md).

## 2. Setup

### Clone and bootstrap

The checks run in a Linux shell. On Windows, use WSL.

1. Install [mise](https://mise.jdx.dev/), Python 3, Git, `make` and a C compiler (the bootstrap builds Lua from
   source).
2. Clone the repository on the `forever` branch, install the tools mise manages, install the Lua toolchain into the
   repository, and run the full check once to confirm the tree is green:

   ```sh
   git clone -b forever https://github.com/zmsl/hekili.git
   cd hekili
   mise install
   make bootstrap
   make check
   ```

The bootstrap installs the Lua toolchain (Lua 5.1, the game's version, with busted, luacheck and luacov) into
`.lua/` inside the repository. mise installs the rest: StyLua, lua-language-server and Python. Their versions are
pinned in `mise.toml`. Nothing is installed system-wide. A new git worktree has no `.lua/` of its own: run
`make bootstrap` in it.

### What the full check covers

Run `make check` before every commit. CI runs the same steps on every push, except the type check.

- Lint (luacheck), formatting (StyLua; upstream Hekili files keep their own style), the type check
  (lua-language-server) and a syntax check of every Lua file.
- The headless test suite, one process per spec file, in parallel, including the short replay and loop gates.
- The API checks: only the facade reads the game, and the engine and the displays stay on their own sides.
- The packs check: regenerating every priority pack leaves the source tree unchanged.
- The offline tests of the release tools.

For a fast edit loop, `make test-fast` skips the long harness gates. To run one spec file:

```sh
.lua/bin/busted tests/Game/State/resources_spec.lua
```

### Link the addons into the game client

Each addon in `src/` gets its own directory link in the client's `_classic_beta_\Interface\AddOns` folder. There are
nine: `Hekili` (the core), `Hekili_Shared`, and one per class: `Hekili_Druid`, `Hekili_Hunter`, `Hekili_Mage`,
`Hekili_Paladin`, `Hekili_Rogue`, `Hekili_Shaman` and `Hekili_Warrior`.

With the clone in WSL, the script `scripts/Link-Addons.ps1` makes every link in one go from an elevated Windows
PowerShell (pass the client folder or its AddOns folder):

```powershell
powershell -ExecutionPolicy Bypass -File "\\wsl.localhost\<distro>\home\<user>\src\hekili\scripts\Link-Addons.ps1" -WowPath "C:\Program Files (x86)\World of Warcraft\_classic_beta_"
```

By hand instead, open an elevated Windows command prompt in the AddOns folder and link each addon to its folder in
the clone, one line per addon; the first two:

```bat
mklink /D Hekili \\wsl.localhost\<distro>\home\<user>\src\hekili\src\Hekili
mklink /D Hekili_Shared \\wsl.localhost\<distro>\home\<user>\src\hekili\src\Hekili_Shared
```

With the clone on Windows, link to its `src` folders instead: `mklink /D Hekili C:\path\to\hekili\src\Hekili`.

Remove any installed copy of Hekili or Hekili Forever first, as the [README's Install section](README.md#install)
says. Hekili Forever keeps the original folder name and saved settings.

After adding or moving an addon folder, restart the client fully: a reload does not pick up a new folder. After
editing files, type `/reload`. `/hekili` opens the options.

## 3. Repository map

One rule explains the shape: **the core is a generic engine, and everything about a class lives in a pack.** The
shared addon holds the content every class uses. Nothing dev-only ships. Details are in
[docs/dev/layout.md](docs/dev/layout.md).

| Folder | What it is |
| --- | --- |
| `src/Hekili/` | The core addon: the facade, the belief, the engine and simulation, the displays and the options |
| `src/Hekili_Shared/` | Content every class shares: racials, consumables, items, common auras |
| `src/Hekili_<Class>/` | One class pack per class: the class file and its generated priorities |
| `src/Hekili_<Class>/APLs/` | The priority sources and the pack manifest; dev-only, never shipped |
| `tools/wowsims/` | The wowsims exporter, the translator and one recipe per supported spec |
| `tests/Game/` | Tests of the core, and the combat harness: the simulated client the gates fight in |
| `tests/Forever/` | Tests of the engine, the packs and the displays, the class worlds and the gate specs |
| `tests/Forever/wowsims/` | Each spec's exported wowsims request and fight log, checked in |
| `tools/` | Pack generation, the API and boundary checks, the release tools |
| `docs/` | References, specs, plans and research |
| `archive/` | Upstream class files from earlier expansions, kept for reference and never loaded |

## 4. How the core is developed

### The hard rules

These rules hold for every change to the core. The checks enforce most of them.

- **The core/pack boundary.** The core names no class, spell, aura, talent, form or rotation. It works only with
  what packs declare through the registration interface. Content addons, in turn, use only the registration API,
  never the core's internals. The boundary test scans both sides. A few inherited simulation files still carry
  upstream names; each is held to a ceiling that may only fall.
- **Secret safety.** Only the facade reads the game client. Never compare a value, or calculate with it, unless it is
  known to be plain: test it with the client's secret check first, or take it from the belief.
- **No allocation on recurring paths.** Code that runs on every update or combat event creates no tables, closures or
  strings. Reuse preallocated records instead. Allocation tests cover the belief, the driver and the output.
- **The layering.** The client is read through the facade, turned into a belief, simulated by the engine and published
  to subscribers. The displays and options never read the simulation. The engine never reads the displays or the
  saved profile directly.

### Test first, headless

Every change starts with a failing test. The whole addon runs headless under busted against a fake client, so the
belief, the simulation and the displays are all testable without the game. The unit specs mirror the source tree. The
combat harness plays seeded fights against a model of the Forever client that hides what the real client hides, and
the gates run the shipped priorities in it (section 5).

`make bench` reports the time and memory each update costs in a headless fight. It is reported, not gated. Run it
when a change touches the update path, and compare it with a run on the base commit.

### Review and merge

Work happens on a branch from `forever`.

1. Keep `make check` green on every commit.
2. Run `make gate` before asking for a merge. It runs the full check, then every class's 20-fight loops.
3. Have the change reviewed against the rules above and the gate's output.
4. Merge into `forever`. Never force-push it.

A change that moves a gate line says why in its commit.

A floor that drops is a failure. It is not a re-measurement.

## 5. How priority packs are developed

### The pure-translation rule

Every default priority is generated from wowsims.com. Each supported spec has one pack, named
"&lt;Spec&gt; (wowsims.com)": wowsims/forever's own action list, translated to this addon's keys. There are no
hand-built priorities.

A pack follows wowsims as closely as the Forever client allows. A difference the client forces, such as a value it
keeps secret, is recorded with its reason. A difference with any other cause is a gap. It is fixed in the layer that
is wrong: the class kit, the translator, the harness or the core.

Each pack starts from a **recipe**: one Lua file per pack in `tools/wowsims/specs/`. The file name is the spec name
the tools take (for example `warrior_arms`), so listing that folder lists every spec. A recipe holds the wowsims build
to export (race, gear, talents, options) and the translation data, which mostly maps wowsims's spell IDs to this
addon's keys.

Only six recipe keys may add something wowsims does not carry: `leveling`, `levelingFirst`, `extra`, `requires`,
`settings` and `focus`. [docs/dev/wowsims-packs.md](docs/dev/wowsims-packs.md) gives each one's meaning, the full
recipe, the rules and the translator's behaviour.

### Regenerate

The pipeline runs from the recipe to the packs that ship. Run each step from the repository root.

1. Export the wowsims request and fight log for a spec. This needs a wowsims/forever checkout at the pinned commit and
   its command-line simulator. The pin is recorded in the exporter, and moving it is described under "wowsims packs"
   in [docs/dev/layout.md](docs/dev/layout.md). Most changes skip this step and use the checked-in log.
2. Translate every recipe into its priority source.
3. Write the generated priorities into the class files.

```sh
make wowsims-export SPEC=warrior_arms   # step 1, one spec
make wowsims-packs                      # step 2
make packs                              # step 3
```

The packs check in `make check` runs steps 2 and 3 and fails on any difference. Commit the regenerated files with the
change that caused them.

### The replay and the 20-fight loops

Two kinds of gate measure a pack.

- **The replay** runs the pack beside wowsims's own fight, from the checked-in log. At each of wowsims's casts it
  compares our first recommendation with what wowsims cast. Its line reports `decisions on-GCD`, the share of those
  casts we agreed with, and the top disagreements.
- **The loops** fight seeded mobs in the harness, twenty fights per pack. In the first run our addon drives and an
  oracle shadows it. The oracle is the same engine reading a client with no secrets, so it shows what perfect
  knowledge would pick. In the second run, on the same seeds, the oracle drives.

Each gate prints a summary line. It reports how often we agreed with the reference, how many presses the simulated
client refused, and our flicker beside the oracle's own. [docs/dev/layout.md](docs/dev/layout.md) explains the
fields and holds every pack's current lines.

`make check` runs short 3-fight versions. Each class's 20-fight loops have their own target, such as
`make test-druid`; the Makefile's gate tag list names them all. `make gate` runs every one.

### Floors only rise

Each gate has a **floor**: the lowest score it accepts. A floor is set from the first clean measurement and raised
whenever a change lifts the score. It is lowered only with a named, accepted cause, written beside the number. This
keeps every improvement and makes any regression visible.

### Flicker is an acceptance metric

Jittery recommendations are a defect, so flicker is judged beside agreement. A change that raises a pack's flicker
needs a reason, and flicker has floors of its own. Between two equally good fixes, prefer the one that keeps the
display still.

A pack change is merged like a core change (section 4). Its review also checks that the pack still mirrors wowsims,
that every addition uses one of the recipe keys above, and that no floor fell.

### Adding a class

A new class needs its own addon folder, kit, harness world, learn table, recipes, floors and docs rows, and a place
in the packager's lists. [docs/dev/wowsims-packs.md](docs/dev/wowsims-packs.md) links the per-spec procedure that
walks through each step.

### Declaring what an ability's hit looks like (`expects`)

The client gives addons no combat log. The core pays each outcome it sees on a unit (a hit, a miss, a tick) to the
cast that made it by a ticket, and a pack tells the core what to expect from each ability with plain data on the
ability, never code:

- `expects`: one of `"none"` (owes no row: a buff), `"instant"` (its row comes in the same frame), `"travel"` (a
  projectile: `velocity` in yards a second, DB2 `SpellMisc.Speed`), `"strike"` (on the next swing), `"ticks"` (a
  DoT with no direct hit), `"channel"` (opt-in, untested in game; no pack uses it). `"melee"` is the core's own.
- A ticking kind reads the aura the ability applies (`cycle`, else `aura`, else the ability's key, as the simulation
  does): its `tick_time` is the period and `floor(duration / tick_time)` the count, read at each cast (a function
  is called in Hekili's state). There are no `ticks`, `tickPeriod` or `dot` fields on the ability.
- `school`: the client's school by name, `"physical"`, `"holy"`, `"fire"`, `"nature"`, `"frost"`, `"shadow"` or
  `"arcane"` (`Hekili.SCHOOL`); leave it out when the spell's mask has no single name.
- A declared `"instant"` or `"travel"` ability whose aura has a `tick_time` and upstream's `dot = "debuff"` also
  ticks (a hit that then ticks); `"ticks"` needs the same two aura fields; `velocity` may join `"ticks"`
  (a DoT that flies).

An ability with no `expects` keeps the default: `"strike"` with `onNextSwing`, `"instant"` with `startsCombat`, else
`"none"`. A malformed declaration shows in the Snapshot's error count and falls back to the default. Check the numbers
against DB2 with `make spell-data-check` (it needs `$WOW_DB2`). The design is
[docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md](docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md).

Two dev-only targets check this layer outside `make check`:

- `make spell-data-check` reads every pack's `expects`, `velocity`, `school` and aura `tick_time` against DB2
  (`SpellMisc`, `SpellEffect`). A rank with no DB2 row is printed as a note and passes; a mismatch fails. A declared
  `velocity` must match the rank's Speed, and an ability with a Speed above 0 must declare it unless it is
  `expects = "none"` (summon_hawk) or `"ticks"`.
- `make bench-ta` times the registry and the tickets on synthetic rows and prints
  `bench-ta rows=N rows/s=R ms/row=X ms/tick=Y ms/tick-expiry=Z (floor rows/s F)`. It fails above 0.02 ms a row, above
  0.10 ms an idle tick or a tick with a full pool expiring, or below 0.8 x the rows/s floor in
  `tools/bench_ta_floor.lua` (97000, the first clean run's; it only moves up).

## 6. Checking in the game client

The headless harness models the client, but it cannot see everything. It does not know which values the real client
keeps secret in each situation, or the exact order and timing of real events. It cannot judge how the displays look
and feel in play, and it cannot confirm anything it models from an assumption rather than a measurement.

Changes in those areas need an in-game check. Forever has no target dummies, so checks happen on open-world mobs.

- **Snapshots.** Type `/hek snap` while a recommendation is wrong. Open `/hekili`, go to "Snapshots
  (Troubleshooting)", and copy the snapshot. It records the simulation's walk through the priority and why each
  entry was or was not picked.
- **The in-game ledger.** Questions that only the client can answer are tracked as a ledger, each with what to do and
  what to report. Today they are listed under "In game" in [docs/dev/layout.md](docs/dev/layout.md).
- **Probe addons.** A question about the client itself, such as whether a value is secret in combat, is answered with
  a small throwaway probe addon, not with Hekili. Its findings become facts that the belief and the harness rely on.

An in-game answer that differs from the model is a gap. Record it in [docs/dev/gaps.md](docs/dev/gaps.md).

## 7. Conventions and releases

- **Changelog.** Every change a player can see adds a line under "Unreleased" in [CHANGELOG.md](CHANGELOG.md), in the
  same commit. Write it for players, not developers.
- **Floors and flicker.** Floors only move up, unless a named cause is recorded beside the change. A change that
  raises flicker says why.
- **Versioning.** Releases are tagged `vMAJOR.MINOR.PATCH`. A pre-release adds a suffix such as `-rc.1` and ships as
  a beta. Every addon in the zip carries the same version.
- **Releasing.** Push the tag, read the draft release the workflow builds, then publish it to upload it to
  CurseForge. The procedure is in [docs/publishing/README.md](docs/publishing/README.md).

## 8. Glossary

| Term | Meaning |
| --- | --- |
| belief | The addon's running estimate of a game value it cannot read: a band, plus how it was learned |
| floor | The lowest score a gate accepts; it only rises |
| oracle | The same engine reading a client with no secrets, the reference in the loops |
| replay | A gate that runs a pack beside wowsims's own fight log and compares decisions |
| loop | A gate of seeded harness fights, ours against the oracle |
| flicker | The first icon changing and changing back within a few ticks |
| gate | A test that fails when a measured score drops below its floor; also `make gate`, the merge check |
| recipe | A spec's wowsims build and translation data, from which its pack is generated |
| kit | A class's abilities, auras and talents, shared by all its specs |
| world | The harness's model of the client and the fight that a loop or replay runs in |
| pack | A priority list (an action pack); also the class addon that ships a class's kit and packs |
| spec | One talent tree of a class, with its own settings and default pack |
