<!--
Purpose: Clone, bootstrap, make check, branch, changelog line, translations.
Type: How-to
Audience: contributors
Prerequisites: Git, a Linux shell (WSL on Windows).
-->
This page shows how to set up a working copy of Hekili Forever, make a change, check it and get it merged. It is a short form of the repository's developer guide, [DEVELOPMENT.md](https://github.com/zmsl/hekili/blob/forever/DEVELOPMENT.md), which has the details. How the code is organised is in [Contributing architecture](Contributing-Architecture).

## Before you start

- A Linux shell. On Windows, use WSL.
- Git, `make`, Python 3 and a C compiler. The bootstrap builds Lua from source.
- mise, the tool manager the repository uses to pin its other tools.

Nothing is installed system-wide: the tools go into the working copy.

## Clone and bootstrap

1. Clone the repository on the `forever` branch and enter it:

   ```sh
   git clone -b forever https://github.com/zmsl/hekili.git
   cd hekili
   ```

2. Install the tools mise manages (StyLua, the Lua language server and Python), at the versions pinned in `mise.toml`:

   ```sh
   mise install
   ```

3. Install the Lua toolchain into `.lua/` inside the working copy: Lua 5.1, the game's version, with busted, luacheck and luacov.

   ```sh
   make bootstrap
   ```

4. Run the full check once to confirm the tree is green:

   ```sh
   make check
   ```

A new git worktree has no `.lua/` of its own: run `make bootstrap` in it.

To try the addon in the game, link each folder of `src/` into the client's AddOns folder. The script `scripts/Link-Addons.ps1` makes every link from an elevated Windows PowerShell. Restart the client after adding a folder, and type `/reload` after editing files.

## Make a change

1. Create a branch from `forever`.
2. Write a failing test first. The whole addon runs headless under busted against a fake client, so the engine, the estimates and the displays can all be tested without the game. To run one spec file:

   ```sh
   .lua/bin/busted tests/Game/State/resources_spec.lua
   ```

   `make test-fast` skips the long gates for a quick edit loop.
3. Make the change, keeping to the rules in [Contributing architecture](Contributing-Architecture#the-hard-rules).
4. Run `make check` before every commit. CI runs the same steps on every push, except the type check.
5. Before asking for a merge, run `make gate`.
6. Have the change reviewed, then merge it into `forever`. Never force-push.

### The checks

| Command | What it runs | When |
|---|---|---|
| `make check` | Lint, formatting, the type check, a syntax check of every Lua file, the headless tests with the short gates, the API and boundary checks, the packs check, the release-tool tests and `make wiki-check` | Before every commit |
| `make check FULL=1` | The same, never skipped | When in doubt, and before a merge |
| `make gate` | The full check, then every class's 20-fight loops | Before a merge |
| `make wiki-check` | The wiki page checks ([Contributing docs](Contributing-Docs)) | Part of `make check` |

`make check` may skip, and says so in one line, when nothing it tests has changed since its last green run in that working copy.

`make gate` runs under a machine-wide lock, so that only one gate runs at a time on a computer. The loops measure the processor time each update takes, and a second gate running beside them would slow every update and fail the measurement. A gate started while another runs waits for it.

A gate fails when a measured score falls below its floor, the lowest score that gate accepts. Floors only rise. A change that lowers one must name the cause, and a change that adds flicker must say why ([Testing and gates](Pack-Testing-And-Gates)).

## Changelog and translations

- **Changelog.** Every change a player can see adds one line under "Unreleased" in `CHANGELOG.md`, in the same commit. Write it for players: name the ability and say what they will see.
- **Text a player sees.** Write it as `L["English text"]`, then run `python3 tools/locales.py`, so that the translation files pick it up.
- **Priorities.** The built-in priorities are generated, never edited by hand ([APL wowsims packs explained](APL-wowsims-Packs-Explained)). Change the recipe, then run `make wowsims-packs` and `make packs`, and commit the regenerated files with the change that caused them.

## Docs

The wiki pages live in `docs/wiki/` and change in the same commit as the code they describe. A page that names an option, a command or an expression the change renames must change with it; `make wiki-check` catches most of these. See [Contributing docs](Contributing-Docs).

## See also

- [Contributing architecture](Contributing-Architecture)
- [Style guide](Style-Guide)
- [Pack overview](Pack-Overview): adding or fixing a class pack
- [Reporting a problem](Reporting-A-Problem)
