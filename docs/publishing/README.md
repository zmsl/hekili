# Publishing Hekili Forever

Hekili Forever is based on the original work by Hekili (https://github.com/Hekili/hekili), published with the
explicit permission of the original author.

## CurseForge page

The user's settings on https://www.curseforge.com/wow/addons/hekili-forever (project 1753387), recorded 2026-10-18.
README.md derives its user-facing sections from the description below; change both together.

- **Name:** Hekili Forever
- **Summary:** A priority helper that shows your next abilities on the WoW Forever client.
- **Licence field:** GNU General Public License version 3 or later (GPLv3+). If the page offers only "GPLv3", that is
  the option selected; the project text (LICENSE, file headers) is version 3 or later.
- **Third-party distribution:** ON
- **Avatar:** `docs/publishing/icon-512.png` (the fork's taco dog icon)
- **Game version:** WoW Forever 1.60.1 (interface 16001; CurseForge type 88568; pinned in tools/cf_upload.py)
- **Source / issues:** https://github.com/zmsl/hekili , https://github.com/zmsl/hekili/issues

### Description (verbatim HTML)

```html
Hekili Forever is a fork of the Hekili priority helper, rebuilt for WoW Forever. It is based on the original work by Hekili and is published with the original author's explicit permission.### <span style="color:#e03e2d"><strong>This addon is not maintained by the original Hekili project. Please do not report Hekili Forever issues to the original project. Bugs, questions and requests go to the GitHub issue tracker:</strong></span> [https://github.com/zmsl/hekili/issues](https://github.com/zmsl/hekili/issues)<div><h3>What is Hekili Forever?</h3><div>Hekili Forever is a priority helper that can make recommendations several steps into the future. It collects information about the game's current state, uses a SimulationCraft-style action priority list to recommend the next ability, then advances the game state and makes the next prediction.</div><div>&nbsp;</div><h3>Supported Classes</h3><div>Hekili Forever is currently in rapid development based the level 30 beta.&nbsp;Druid (Feral, Guardian, Balance) and Warrior (Arms, Fury, Protection) are the current focus and are tuned for level 60 content, but are subject to rapid change after launch.</div><div>&nbsp;</div><div><h3>Action Packs</h3><div><div>Action Packs are shareable instructions that direct the addon how to make recommendations. They use action priority lists similar to SimulationCraft, with Forever-specific lines written for this ruleset. Action Packs only work for specializations the addon supports. View and edit them under /hekili &gt; Action Packs.</div><div>&nbsp;</div><div><h3>Displays</h3><div><div><div>Each display can use the classic Hekili look, a row of icons for the next recommendations, or the new Timeline style:</div><br><div>- A round Focus circle for the ability that deserves your attention, with a countdown until it is ready and a gold ring when it is time to press it.</div><div>- A Next box for the ability to press right now, with its keybind.</div><div>- A lane where upcoming abilities sit by time, so you can see what is coming and when.</div><div>- When the addon cannot be sure of your resource, the lane can show the alternative picks stacked together in priority order.</div><div>- Ruler styles for the lane, a quiet mode out of combat so nothing bounces while you are not fighting, and optional gold ring and frame art.</div><br><div>Pack authors can mark lines as "focus" abilities, such as a buff to refresh or a proc to use, so they appear in the Focus circle ahead of time rather than only when they reach the top of the list.</div><div>&nbsp;</div></div></div></div></div></div><h3>Current Mode</h3><div><div>The Current Mode: Auto setting adjusts your display to the number of enemies the addon detects. For fights where you want to focus one enemy, switch to Single Target to force the primary display to assume one target; the AOE display then appears alongside with the multi-target recommendations. Bind a key for Mode Switch under /hekili &gt; Toggles so you can flip it mid-fight.</div><div>&nbsp;</div><div><h3>Other Customization</h3><div><div>You can change the direction of your recommendation queue, its alignment and spacing, the number of icons shown, the primary and queued icon sizes, fonts and font sizes, and Blizzard's overlay glow on the first recommendation. Visibility and transparency can be set separately for PvE and PvP, and displays can be given conditions in the same syntax the action lists use.</div><div>&nbsp;</div><div><h3>Toggles</h3><div><div>Cooldowns, Minor Cooldowns, Defensives, Interrupts and Potions can each be switched on and off with a keybind, so the recommendations follow what you actually want to use right now.</div><div>&nbsp;</div><div><h3>Troubleshooting</h3><div><div><div>1. <span style="text-decoration:underline">Nothing is showing</span>: Go to /hekili &gt; General and make sure Enabled is checked. If it has unchecked itself, the addon may have hit an error and shut itself off; collect the error with BugSack/BugGrabber and submit it on GitHub.</div><div>2. <span style="text-decoration:underline">Still nothing</span>: Check /hekili &gt; Displays &gt; Primary and AOE, and the alpha settings on the Visibility tab. If a default display is the problem, try a new profile and see whether the displays appear.</div>3. <span style="text-decoration:underline">Old data</span>:&nbsp;If you have used Hekili before, reset your profile under /hekili &gt; Profiles and reload your UI.</div><div>&nbsp;</div><div><h3>Credits</h3><div><div><div>Based on the original work by Hekili. Author: <a href="https://github.com/zmsl" target="_blank" rel="nofollow">defzach</a>.</div></div></div></div></div></div></div></div></div></div></div></div>
```

To fix on the page (the record above is verbatim; README.md already uses the fixed names):

- "based the level 30 beta" -> "based on the level 30 beta".
- "/hekili > Action Packs" -> "/hekili > Priorities".
- "Mode Switch under /hekili > Toggles" -> "Display Mode under /hekili > Toggles > Display Control".
- "Auto" / "Single Target" -> "Automatic" / "Single-Target".
- If the description gains licence wording, make it version 3 or later.

## Local package dry run

On a clean tree (`git status --short` empty), run:

```sh
make package-check
```

`make package` downloads the BigWigs packager (`release.sh`, once, into `.lua/`) and runs it with `-d`, so nothing is
uploaded; the zip lands in `.release/`, which is gitignored. `make package-check` then runs `tools/check_package.sh` on
the newest zip: the four addon folders at the zip root, `Hekili/LICENSE`, no dev paths, and every TOC `## Version`
equal to the project version (the zip name without its -forever suffix). Neither target is part of `make check` (they
need the network and a clean commit).
Run them from a plain clone: in a git worktree (`.git` is a file) the packager stops with `No Git, SVN, or Hg
checkout found`.

The packager versions the zip from `git describe`. On a dirty tree, or with no release tag (the first one will be
`v0.1.0`), that is a describe string; it may name an upstream tag such as `v2.5.5-...-g<hash>`, which is harmless for a
dry run.

To try the zip in game, back up and remove the four `mklink /D` links first, or extraction writes into the WSL repo. In
an elevated Windows `cmd` in `_classic_beta_\Interface\AddOns`: `rmdir Hekili Hekili_Shared Hekili_Druid
Hekili_Warrior` (rmdir on a directory link removes only the link). Extract the zip there (from
`\\wsl.localhost\personal\home\zack\src\hekili\.release\`), full client restart, log in a Druid or Warrior: displays
show, `/hekili` opens, General page has the notice, no Lua errors. Then delete the four extracted folders and re-create
the links, one per addon: `mklink /D <Addon> \\wsl.localhost\personal\home\zack\src\hekili\src\<Addon>`.

## Cutting a release

**Standing rule for implementer briefs:** a commit that changes what a player sees adds its line under
`## Unreleased` in CHANGELOG.md (New / Changed / Fixed / Known issues / Upgrade notes) in the same commit.

A release is three steps: tag, read the draft, publish. Nothing reaches players before step 3. **A tag without a
published release is not released**: it has a draft on GitHub and nothing on CurseForge.

Tags are `vMAJOR.MINOR.PATCH`; a pre-release adds a suffix with a `-` (`v0.2.0-rc.1`, `v0.2.0-beta.1`) and goes to
CurseForge as a beta file.

1. **Tag.** On `forever` with `make check` green: `git tag vX.Y.Z && git push origin vX.Y.Z` (that one tag, never
   `--tags`). CHANGELOG.md is not touched by hand.
2. **Read the draft.** Actions > release (`.github/workflows/release.yml`) builds the zip with the BigWigs packager
   (no upload), writes the notes with `tools/release_notes.py` and creates a draft release with the zip attached
   (`Hekili-<tag>-forever.zip`; a pre-release for a `-` tag). The notes come from the changelog's Unreleased section
   (or the tag's own section once publish has written it), the commits under `src/` since the previous release
   (pre-release tags are skipped, so a final release covers its release candidates) and the "Open after" sections of
   plans changed since then. Open
   Releases > the draft > Edit: fix anything that reads like a developer note, keep it player-facing, never leave the
   body empty.
3. **Publish.** Press Publish release (tick "Set as a pre-release" only if it already is one). Actions > publish
   (`.github/workflows/publish.yml`) uploads the attached zip to CurseForge project 1753387 with the release body as
   the markdown changelog, the tag as the file name and game version 1.60.1; the Discord webhook posts the release.
   For a final release its changelog job then writes `## vX.Y.Z` (the published notes, dated) into CHANGELOG.md on
   `forever` with `tools/changelog_release.py` and resets Unreleased to the five empty headings, keeping lines merged
   after the tag; it commits as github-actions[bot] (`docs(changelog): vX.Y.Z released [skip ci]`) and pushes. So the
   file is never edited by hand for a release; a pre-release leaves it alone. The push to `forever` from a workflow is
   the user's decision (2026-10-19), overriding the approved-release plan's "no pushes to forever from workflows".

Edits after publishing reach GitHub only: fix the CurseForge changelog by hand on the file's page. Unpublishing or
deleting a release does not remove the CurseForge file.

To preview the notes without releasing: Actions > release > Run workflow, pick the branch or tag, keep `dry_run`
ticked. It builds the zip and prints the notes in the log (one Anthropic API call). Run from a tag with `dry_run`
unticked, it creates the draft (use this when a tag's run failed after the push, for example an API outage).

### Failure modes

- **Release run fails:** no draft exists. Read the log: `release_notes:` lines name the cause (missing key, API
  error, refusal, no changes since the last release). Fix it and re-run the job, or run the workflow on the tag with
  `dry_run` unticked. If a draft for the tag already exists, delete the draft first.
- **Publish run fails:** the release is public on GitHub (and the Discord webhook has posted it) but not on
  CurseForge. `cf_upload:` lines name the cause. Re-run the failed job once the cause is fixed
  (Actions > publish > Re-run). A re-run replays the original event, so it reuses the release body as it was when
  published; when the cause is the body (for example `cf_upload: the release body is empty`), edit the release, set it
  back to a draft and publish again, which makes the Discord webhook post again.
- **The changelog commit fails** (a push race with another merge, or a `changelog_release:` refusal): CurseForge
  already has the file. Re-run the publish job's changelog job (Actions > publish > Re-run failed jobs); it starts from
  the current `forever` and does nothing if the section is already there. Or locally on an up-to-date `forever`: save
  the release body to a file, `python3 tools/changelog_release.py vX.Y.Z body.md`, then commit and push.
- **CurseForge rejects a duplicate display name:** a tag can be uploaded once. To re-ship, cut a new tag (the next
  patch or `-rc.N`).
- **CurseForge daily upload limit:** the upload fails with a limit error; re-run the publish job the next day.
- **Game version missing:** `cf_upload: 0 CurseForge game versions named 1.60.1` means CurseForge has no such
  version under type 88568. When the client's `## Interface` changes, update `GAME_VERSION` in
  `tools/cf_upload.py`; list the versions with the curl below.

### One-time setup

- **Secrets** (GitHub repo > Settings > Secrets and variables > Actions): `CF_API_KEY` (CurseForge > API tokens; used
  only by publish.yml) and `ANTHROPIC_API_KEY` (console.anthropic.com > API keys; used only by release.yml). Actions
  masks both in logs; the tools never print a request or a header.
- **Discord webhook** (the user): in the channel's settings > Integrations, create a Discord webhook and copy its URL.
  Then GitHub repo > Settings > Webhooks > Add webhook: Payload URL is that Discord webhook URL with `/github`
  appended, content type `application/json`, "Let me select individual events", tick Releases only (untick Pushes).
  The Discord webhook posts each published release; the rehearsal confirms it stays quiet for drafts.

The CurseForge game version, with the same token:

```sh
curl -fsS -H "X-Api-Token: $CF_API_KEY" https://wow.curseforge.com/api/game/versions | jq '.[] | select(.name | test("^1\\.60")) | {id, name, gameVersionTypeID}'
```

### Rehearsal

Run once by the session owner (Fable) after this pipeline merges, before the next real release; the SDD controller
does not push tags. The controller decides, and tells the user, whether the rehearsal release stays as a public beta
or is deleted (step 5).

1. Secrets and the Discord webhook are set up (above). Optional: Actions > release > Run workflow on `forever` with
   `dry_run` ticked; the log ends with the notes.
2. `git tag v0.1.1-rc.1 && git push origin v0.1.1-rc.1`. Actions > release goes green. Releases shows a draft
   pre-release `v0.1.1-rc.1` with `Hekili-v0.1.1-rc.1-forever.zip` attached. Read the notes: player language, one
   section per class then core and display, a Known issues list, under 60 lines, no file or task names. Nothing on
   CurseForge; no post from the Discord webhook.
3. Edit the notes if needed and publish. Actions > publish goes green (log: `cf_upload: v0.1.1-rc.1 (beta) uploaded
   as CurseForge file <id>`).
4. CurseForge project > Files shows `v0.1.1-rc.1`, type Beta, game version 1.60.1, its changelog equal to the release
   body. The Discord webhook has posted the release once.
5. Then, per the controller's decision: keep it as the public beta, or delete it: the file on CurseForge
   (Files > the file > Delete), then `gh release delete v0.1.1-rc.1 --cleanup-tag --yes` and
   `git tag -d v0.1.1-rc.1`.
