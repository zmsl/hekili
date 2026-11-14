# The Hekili Forever wiki's source

This folder is the source of the wiki at [github.com/zmsl/hekili/wiki](https://github.com/zmsl/hekili/wiki). Edit the
pages here, in the same branch and commit as the change they describe. The wiki itself is overwritten on every release:
edits made on GitHub's wiki editor are lost.

## How it is published

`.github/workflows/wiki.yml` runs when a final release is published. It checks out the release tag, runs
`make wiki-check`, then clones the wiki repository, copies this folder over it (everything except `README.md`,
`data/` and `.gitkeep`), fills the `{{VERSION}}` line of `_Footer.md` with the tag, and commits and pushes only if a
page changed. It never deletes a page that exists only on the wiki, never runs `git init` and never force-pushes, so
the wiki's history is kept. A wiki page therefore always describes the latest release, never unreleased work.

## Pages

- One file per page. The file name is the page name: Title-Case-With-Hyphens, no subfolders, unique. GitHub shows
  hyphens as spaces and the page name as the title, so a page has no H1.
- `_Sidebar.md` is the sidebar on every page and `_Footer.md` the footer. Add a new page to the sidebar.
- Link a page as `[text](Page-Name)` and a heading as `[text](Page-Name#heading-slug)`. Plain GitHub Markdown only:
  no `[[...]]` links and no HTML styling.
- Screenshots go in `images/` as `<Page-Name>-<n>.png` (PNG, 1x UI scale, at most 800 px wide and 500 KB), linked as
  `images/<Page-Name>-<n>.png`, with an HTML comment after the image recording the version, class and place it was
  taken.
- Each page is one type: tutorial, how-to, reference or explanation. The [Style guide](Style-Guide.md) page has the
  rules; Wikipedia's Manual of Style is the reference.

### Stubs

A page that is not written yet is a stub: an HTML comment at the top (purpose, type, audience, prerequisites), a
`TODO: the lead.` line, the full heading outline, and under each heading the facts to write up, each with the source
file it comes from (`Source:`). `TODO-SCREENSHOT:` marks a picture to take, `TODO-LINK(...)` a link to fill in and
`TODO-GENERATE:` a table that will be generated once its collector exists. Replace the bullets with prose, check each
fact against its source, and remove the comment's `Status:` line when the page is done.

## Generated tables

Some tables are written by the generator from the addon itself, so they cannot go stale by hand. A page asks for one
with a marker pair, each on its own line:

```text
<!-- GENERATED:spec-defaults-nameplate -->
<!-- /GENERATED -->
```

`make wiki-tables` fills every pair: it finds the name in `tools/wiki/manifest.lua`, runs that table's collector and
replaces only the lines between the markers (after a "Do not edit" comment). Text outside the markers is never read or
written, and running it twice changes nothing. Never edit inside a pair: run `make wiki-tables` instead.

| Part | What it is |
| --- | --- |
| `tools/wiki/gen.lua` | `write` (`make wiki-tables`) and `check` (`make wiki-check`) |
| `tools/wiki/manifest.lua` | Every table: its collector, the collector's arguments, the headers and the note under it |
| `tools/wiki/collect/*.lua` | The collectors: options, commands, expressions, specs (priorities, settings, ranges), api, accuracy |
| `tools/wiki/boot.lua` | One headless boot of the addon per class (the test harness's fake client) |
| `tools/wiki/check.lua` | The page checks |
| `data/commands.lua` | The reviewed list of chat commands: public (published) or internal |
| `data/expressions.lua` | What each expression means, written by hand |
| `data/accuracy.json` | A copy of `.accuracy/report.json` from the last batch `make accuracy` run |

The collectors read the addon the way a player's client builds it: each class addon is loaded headless and the options
tree, the class kits and the command table are read from the running code. The expression keys are the exception:
they are branches inside a function, so they come from a scan of `src/Hekili/Engine/Sim/State.lua`, with their
meanings from `data/expressions.lua`. The accuracy table reads `data/accuracy.json`, because `make accuracy` takes the
gate lock for every loop and cannot run in CI: copy `.accuracy/report.json` there after a batch accuracy run, and
update the version the Accuracy page names.

To add a table: add an entry to the manifest (a collector and its arguments, headers, and a note for any "n/a" cell),
put the marker pair in a page, and run `make wiki-tables`.

## wiki-check

`make wiki-check` runs in `make check` and in the release workflow. It fails on:

- a generated region that differs from what `make wiki-tables` would write, or a marker the manifest does not name;
- a bold option path (`**/hekili > A > *placeholder* > B**`) whose segments are not option labels, or a bold Title
  Case label that names no option or is not an English string in `src/Hekili/Locales/enUS.lua` (a lead-in ending in a
  colon or full stop, a sentence-case term and the page's bold title term are not checked);
- a chat command in code (`` `/hekili ...` ``) that is not a published command or alias;
- a command in the code that `data/commands.lua` lists neither as public nor internal, or a listed one that is gone;
- an expression key the scan finds with no entry in `data/expressions.lua`, an entry that no longer evaluates in a
  booted state, or an example that compiles in no class;
- a link to a page or heading that does not exist, or to a site other than GitHub, wowsims.com and CurseForge;
- a home-directory or Windows user path, a hidden debug switch, an internal ledger or ruling ID, or a link to a
  Claude artifact.

Open `TODO` placeholders and screenshots not yet in `images/` are warnings: they never fail the check.
