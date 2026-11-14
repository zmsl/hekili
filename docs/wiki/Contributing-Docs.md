<!--
Purpose: How the wiki is built: docs/wiki/, generated tables, wiki-check.
Type: How-to
Audience: contributors
Prerequisites: [Contributing](Contributing).
-->
This page shows how to change a page of this wiki, add a page or a generated table, and check the result before committing. The wiki's source is the `docs/wiki/` folder of the repository, published to the wiki when a release is published. The writing rules are in the [Style guide](Style-Guide), and the folder's own [README](https://github.com/zmsl/hekili/blob/forever/docs/wiki/README.md) has the full details.

## Where the pages live

- Each page is one Markdown file in `docs/wiki/`. The file name is the page name, in Title-Case-With-Hyphens, with no subfolders. GitHub shows the hyphens as spaces and the page name as the title, so a page has no level-one heading.
- `_Sidebar.md` is the sidebar on every page, and `_Footer.md` the footer.
- Screenshots are in `docs/wiki/images/`, named `<Page-Name>-<n>.png`.
- A page changes in the same branch and commit as the code it describes.

The wiki on GitHub is overwritten at every release. An edit made in GitHub's own wiki editor is lost, so edit the files in the repository.

When a final release is published, the release workflow checks out the release tag, runs `make wiki-build` and `make wiki-check`, and copies the built pages over the wiki. The footer's version line is filled with the tag. The wiki therefore always describes the latest release, never unreleased work. A page removed from the repository stays on the wiki unless its file name is listed in `docs/wiki/data/retired-pages.txt`.

## Change a page

1. Edit the file in `docs/wiki/`.
2. Check every fact against the code it describes. Where a fact cannot be checked, leave an HTML comment starting `UNVERIFIED:` beside it rather than guessing.
3. Run `make wiki-check` (see [The check](#the-check)).
4. To see the page with its generated tables filled in, run `make wiki-build` and read the copy in `build/wiki/`.
5. Commit the page with the change it describes.

## Add a page

1. Create `docs/wiki/<Page-Name>.md`.
2. Start with an HTML comment that states the page's purpose, type (tutorial, how-to, reference or explanation), audience and prerequisites, then the lead.
3. Add the page to `_Sidebar.md`, in the group it belongs to.
4. Link it from the pages that should lead to it, with the page name as the link target and no `.md` ending.
5. Run `make wiki-check`.

## Add a generated table

A generated table is written from the running addon at publish time, so it cannot go stale. In `docs/wiki/` a page holds only an empty marker pair, each marker on its own line:

```text
<!-- GENERATED:spec-defaults-nameplate -->
<!-- /GENERATED -->
```

1. Add an entry to `tools/wiki/manifest.lua`: the table's name, its collector in `tools/wiki/collect/`, the collector's arguments, the column headers, and a note that explains any "n/a" cell.
2. Put the empty marker pair in the page where the table belongs, and refer to it as "the table below".
3. Run `make wiki-build` and read the table in `build/wiki/`.

Never write a table between the markers in `docs/wiki/`. The collectors boot each class addon headless, as the game client would load it, and read the options, the class content and the chat commands from the running code. The expression tables are the exception: their keys come from a scan of `src/Hekili/Engine/Sim/State.lua`, and their meanings from the hand-written `docs/wiki/data/expressions.lua`.

The accuracy table reads `docs/wiki/data/accuracy.json`, a copy of the report of the last batch `make accuracy` run, because that run cannot happen in CI. After such a run, copy the report there and update the version the [Accuracy](Accuracy) page names.

## The check

`make wiki-check` runs as part of `make check` and in the release workflow. It fails on:

- a malformed marker, or one the manifest does not name;
- a bold options path, such as **/hekili > Priorities**, whose parts are not option labels, or a bold Title Case label that is not an option label in English;
- a chat command in code that is not a published command or alias;
- a command in the addon that `docs/wiki/data/commands.lua` lists neither as public nor as internal;
- an expression key in the scan with no meaning in `docs/wiki/data/expressions.lua`, a meaning that no longer evaluates, or an example that does not compile;
- a link to a page or heading that does not exist, or to a site other than GitHub, wowsims.com and CurseForge;
- a local file path, a hidden debug switch, an internal reference number, or a link to a private artifact.

Open TODO markers and screenshots not yet in `images/` are warnings and never fail the check. The page checks themselves are tested with `.lua/bin/busted tests/wiki_spec.lua`.

## See also

- [Style guide](Style-Guide)
- [Contributing](Contributing)
