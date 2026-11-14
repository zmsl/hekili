<!--
Purpose: Headless tests, the class test world, make check and make gate.
Type: How-to
Audience: Lua developers
Prerequisites: [Contributing](Contributing).
-->
**Pack testing and gates** covers how a class pack is tested: the headless tests that run the whole addon without the game, the class test world the priorities fight in, and the two make targets every change passes, `make check` and `make gate`. A gate is a test that measures a pack against a reference and fails when a score falls below its floor.

Every change starts with a failing test. The tests run under busted, a Lua test framework, in a Linux shell; setting up the toolchain is described in [Contributing](Contributing).

## Headless tests

The whole addon runs headless under busted against a fake client, so the belief, the simulation and the displays can all be tested without the game. `tests/Game/harness/headless.lua` loads the addon with its content addons, in the order `tests/helpers/addons.lua` lists them. Each instance runs every file of every addon in its own Lua environment, so two instances (the addon under test and an oracle, below) keep their own state side by side. The fake client hides what the real Forever client hides. The harness is class-neutral: the character's class, spec, spells and talents come from the content, never from the harness.

Run one spec file with busted from the repository root:

```sh
.lua/bin/busted tests/Forever/druid_spec.lua
```

A file of tagged gates runs one tag with `--tags`, for example `.lua/bin/busted --tags=druid tests/Forever/loop_druid_feral_spec.lua`.

### What a class is tested by

| File | What it checks |
|---|---|
| `tests/Forever/<class>_spec.lua` | The class file's registrations (abilities, costs, cooldowns, auras, talents) against the game's spell data. The class file is loaded through a recording stand-in for Hekili (`tests/Forever/helpers/load_druid.lua`, which the other classes reuse with their own file and token; the Warrior has `load_warrior.lua`), and its handlers can be run against a stand-in state. |
| `tests/Forever/helpers/<class>_world.lua` | The class test world: the class's content for the headless loop, one entry per pack. It gives the character the instance logs in as (the build's talents), what each ability's press does in the world, and the client's usability answers. |
| `tests/Forever/loop_<class>_spec.lua` | Boot checks of the world (every ability a pack can recommend is mapped) and the short 3-fight gates, tagged `#slow`. |
| `tests/Forever/loop_<class>_<spec>_spec.lua` | One pack's 20-fight gate, one file per pack so each runs in its own process, tagged with the class's gate tag. |
| `tests/Forever/wowsims_<class>_spec.lua` | The replay gate and the leveling gate of each of the class's packs, tagged `#slow #wowsims`. |

Some specs cover every pack at once:

- `tests/Forever/packs_spec.lua` checks the generated priorities: no bare aura alias in a condition and no time-to-die limits on an ability; and, for each class in its own class list, `use_off_gcd=1` on exactly the off-GCD abilities, every setting a priority reads registered on its spec, and a spec opted into the Movement toggle exactly when its pack reads `toggle.movement`.
- `tests/Forever/wowsims_levels_spec.lua` runs `tools/check_pack_levels.lua` over every pack: each read of another ability must sit inside a guard that drops it while that ability is unlearned ([Pack translator rules](Pack-Translator-Rules), rule 6).
- `tests/Forever/make_pack_spec.lua` round-trips the packs of each class in its own class list through the share format, and checks that those class files match their `APLs/` sources.
- `tests/Forever/focus_roles_spec.lua` holds the generated packs' focus tiers in a hand-written table, so a new pack's tiers are added there by hand.
- `tests/Forever/cdm_map_spec.lua` boots each class headless and maps every entry of a Cooldown Manager export, taken from the live game client, onto the class pack, the way the addon maps it in game. An entry that maps to several auras, or to none, must be listed in the spec's `GAPS` table with a reason. The same export's talent tree is compared with the pack's talents, and every difference must be in `TALENT_GAPS`. Both lists may only shrink: a listed entry that is no longer a gap also fails, so its line is deleted when the class pack catches up.

## The replay and the loops

Two kinds of gate measure a pack.

- **The replay.** The pack runs beside wowsims's own fight, read from the checked-in log. At each of wowsims's casts it compares the addon's first recommendation with what wowsims cast. Its line reports `decisions on-GCD`, the share of those casts the addon agreed with, and the top disagreements. The same spec file runs the leveling gate: the pack plays at three levels and must raise no error, press at least once, and never sit idle longer than its limit while an on-GCD ability is usable.
- **The loops.** The pack fights seeded mobs in the class test world, twenty fights a pack. In the first run the addon drives and an oracle shadows it. The oracle is the same engine reading a client with no secrets, so it shows what perfect knowledge would pick. In the second run, on the same seeds, the oracle drives.

Each gate prints a summary line. It reports how often the addon agreed with the reference, how many presses the simulated client refused, and the addon's flicker beside the oracle's. The developer documentation (`docs/dev/layout.md`) explains every field. The [Accuracy](Accuracy) page summarises the results per specialization.

### Floors only rise

Each gate has a floor: the lowest score it accepts. A floor is set from the first clean measurement and raised whenever a change lifts the score. It is lowered only with a named, accepted cause, written beside the number. This keeps every improvement and makes any regression visible. A floor that drops is a failure, not a re-measurement. The replay floors sit in each `tests/Forever/wowsims_<class>_spec.lua`; the loops' limits sit in `tests/Forever/helpers/pack_gate.lua`.

### Flicker is an acceptance metric

Flicker is the first icon changing and changing back within a few updates. Jittery recommendations are a defect, so flicker is judged beside agreement. Every gate line prints the addon's flicker per minute beside the oracle's. Flicker has limits of its own, which work the other way round from floors: a limit only ever tightens. A change that raises a pack's flicker needs a reason. Between two equally good fixes, prefer the one that keeps the display still.

## make check and make gate

Run `make check` before every commit, and `make gate` before asking for a merge.

```sh
make check          # every commit
make check FULL=1   # the same, never skipped
make gate           # before a merge: make check, then every 20-fight loop
```

| Target | What it runs |
|---|---|
| `make check` | Lint, formatting, the type check and the test suite at once, then the syntax check, the API and boundary checks, the packs check ([Pack wowsims recipes](Pack-wowsims-Recipes#the-packs-check)), the release tools' tests and the wiki check. The test suite includes the replay and leveling gates and the 3-fight loops. |
| `make check FULL=1` | `make check` without the skip. |
| `make test` | The test suite alone: one busted process per spec file, in parallel, without the 20-fight tags. |
| `make test-fast` | The edit loop: the test suite without the `#slow` gates. |
| `make test-wowsims` | The replay and leveling gates alone. |
| `make test-<tag>` | One gate tag's 20-fight loops: `test-druid`, `test-rogue`, `test-paladin`, `test-shaman`, `test-hunter`, `test-mage`, `test-priest`, `test-warlock`. The Warrior's are `test-loop` (Arms, Fury and Protection) and `test-party`. |
| `make gate` | `make check FULL=1`, then every gate tag's 20-fight loops. |
| `make bench` | The time and memory each update costs in a headless fight. Reported, not gated. |

`make check` may skip, and prints one line when it does. It skips when its inputs match the last green check in the worktree, or when only documentation that no test reads has changed. `FULL=1` runs it all; so does any other command-line override. Use `FULL=1` before a merge and whenever in doubt.

The loops assert a CPU budget per update, which another gate's load would inflate, so `make gate` holds a machine-wide lock: one gate runs at a time per machine. Continuous integration runs the checks of `make check` (without the type check) on every push; it does not run the 20-fight loops, so `make gate` is run locally.

`make bench` matters when a change touches the update path: compare its result with a run on the base commit.

### Review and merge

Work happens on a branch from `forever`.

1. Keep `make check` green on every commit.
2. Run `make gate` before asking for a merge.
3. Have the change reviewed against the core's rules and the gate's output. A pack change's review also checks that the pack still mirrors wowsims, that every addition uses one of the allowed recipe keys, and that no floor fell.
4. Merge into `forever`. Never force-push it.

A change that moves a gate line says why in its commit message.

## See also

- [Accuracy](Accuracy)
- [Pack adding a spec or class](Pack-Adding-A-Spec-Or-Class)
- [Pack wowsims recipes](Pack-wowsims-Recipes)
- [Pack translator rules](Pack-Translator-Rules)
