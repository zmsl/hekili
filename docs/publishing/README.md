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
- **Game version:** WoW Forever 1.60.1 (interface 16001; see "Cutting a release")
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

Tags are `vMAJOR.MINOR.PATCH`; the first release is `v0.1.0`.

1. `make check` green on `forever`; write `## vX.Y.Z` with the changes by hand at the top of CHANGELOG.md (under the
   title); commit.
2. `git tag vX.Y.Z && git push origin vX.Y.Z` (push that one tag, never `--tags`), for example
   `git tag v0.1.0 && git push origin v0.1.0`.
3. Watch Actions > release: the one run (`.github/workflows/release.yml`) uploads the zip to CurseForge project 1753387
   with CHANGELOG.md as its changelog and creates the GitHub release for the tag. It fails early if CHANGELOG.md has
   no `## <tag>` heading.

One-time setup (already done for zmsl/hekili): CurseForge > API tokens > create token; GitHub repo > Settings >
Secrets > Actions > `CF_API_KEY`.

The packager maps `## Interface: 16001` to the game version `1.60.1` (the dry run prints `Game version: 1.60.1`), so
the workflow pins none. Optional check that CurseForge lists that version, with the same token:

```sh
curl -fsS -H "X-Api-Token: $CF_API_KEY" https://wow.curseforge.com/api/game/versions | jq '.[] | select(.name | test("^1\\.60")) | {id, name, gameVersionTypeID}'
curl -fsS -H "X-Api-Token: $CF_API_KEY" https://wow.curseforge.com/api/game/version-types | jq '.[] | {id, name, slug}'
```

If `1.60.1` is missing or listed under another name, pin the listed name in the packager step (`with: args: -g <name>`)
and pass the same `-g` in the Makefile's `package` target.
