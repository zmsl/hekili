<p align="center"><img src="https://raw.githubusercontent.com/zmsl/hekili/forever/docs/publishing/icon-512.png" alt="Hekili Forever" width="160"></p>

# Hekili Forever

[![Discord](https://img.shields.io/discord/1561791635220725912?logo=discord&logoColor=white&label=Discord&color=5865F2)](https://discord.gg/JaC6W4Pkur)

Hekili Forever is a fork of the Hekili priority helper, rebuilt for WoW Forever. It is based on the original work by Hekili and is published with the original author's explicit permission.

> <span style="color:#e03e2d">**This addon is not maintained by the original Hekili project. Please do not report Hekili Forever issues to the original project. Bugs, questions and requests go to the GitHub issue tracker:**</span> [https://github.com/zmsl/hekili/issues](https://github.com/zmsl/hekili/issues)
>
> **Help and feedback: the Hekili Forever Discord:** [https://discord.gg/JaC6W4Pkur](https://discord.gg/JaC6W4Pkur)

## What is Hekili Forever?
Hekili Forever is a priority helper that can make recommendations several steps into the future. It collects information about the game's current state, uses a SimulationCraft-style action priority list to recommend the next ability, then advances the game state and makes the next prediction.

## Supported Classes
Hekili Forever is currently in rapid development based on the level 30 beta. Druid (Feral, Guardian, Balance), Warrior (Arms, Fury, Protection), Rogue (Combat, Assassination, Subtlety), Paladin (Retribution, Protection), Shaman (Enhancement, Elemental), Hunter (Beast Mastery, Marksmanship, Survival), Mage (Arcane, Fire), Priest (Shadow, Discipline with Smite) and Warlock (Affliction, Demonology, Destruction) are the current focus and are tuned for level 60 content, but are subject to rapid change after launch.

## Action Packs
Action Packs are shareable instructions that direct the addon how to make recommendations. They use action priority lists similar to SimulationCraft, with Forever-specific lines written for this ruleset. Action Packs only work for specializations the addon supports. View and edit them under /hekili > Priorities.

## Displays
Each display can use the classic Hekili look, a row of icons for the next recommendations, or the new Timeline style:

- A round Focus circle for the ability that deserves your attention, with a countdown until it is ready and a gold ring when it is time to press it.
- A Next box for the ability to press right now, with its keybind.
- A lane where upcoming abilities sit by time, so you can see what is coming and when.
- When the addon cannot be sure of your resource, the lane can show the alternative picks stacked together in priority order.
- Ruler styles for the lane, a quiet mode out of combat so nothing bounces while you are not fighting, and optional gold ring and frame art.

Pack authors can mark lines as "focus" abilities, such as a buff to refresh or a proc to use, so they appear in the Focus circle ahead of time rather than only when they reach the top of the list.

## Current Mode
The Current Mode: Automatic setting adjusts your display to the number of enemies the addon detects. For fights where you want to focus one enemy, switch to Single-Target to force the primary display to assume one target; the AOE display then appears alongside with the multi-target recommendations. Bind a key for Display Mode under /hekili > Toggles > Display Control so you can flip it mid-fight.

## Other Customization
You can change the direction of your recommendation queue, its alignment and spacing, the number of icons shown, the primary and queued icon sizes, fonts and font sizes, and Blizzard's overlay glow on the first recommendation. Visibility and transparency can be set separately for PvE and PvP, and displays can be given conditions in the same syntax the action lists use.

## Toggles
Cooldowns, Minor Cooldowns, Defensives, Interrupts and Potions can each be switched on and off with a keybind, so the recommendations follow what you actually want to use right now.

## Troubleshooting
1. **Nothing is showing**: Go to /hekili > General and make sure Enabled is checked. If it has unchecked itself, the addon may have hit an error and shut itself off; collect the error with BugSack/BugGrabber and submit it on GitHub.
2. **Still nothing**: Check /hekili > Displays > Primary and AOE, and the alpha settings on the Visibility tab. If a default display is the problem, try a new profile and see whether the displays appear.
3. **Old data**: If you have used Hekili before, reset your profile under /hekili > Profiles and reload your UI.

## Install
- **CurseForge:** install **Hekili Forever** (https://www.curseforge.com/wow/addons/hekili-forever).
- **GitHub:** download the zip from https://github.com/zmsl/hekili/releases and extract it into
  `_classic_beta_\Interface\AddOns\`. It holds eleven folders: `Hekili`, `Hekili_Shared`, `Hekili_Druid`,
  `Hekili_Warrior`, `Hekili_Rogue`, `Hekili_Paladin`, `Hekili_Shaman`, `Hekili_Hunter`, `Hekili_Mage`,
  `Hekili_Priest`, `Hekili_Warlock`.
- Remove any old `Hekili` folder first. Hekili Forever keeps the original's folder name and saved settings (`HekiliDB`),
  so your settings carry over. `/hekili` opens the options.

## Reporting a problem
Open an issue at https://github.com/zmsl/hekili/issues.
- **Lua errors:** install BugSack and BugGrabber, reproduce the error, and paste BugSack's text into the issue.
- **A wrong recommendation:** take a snapshot while it is happening: type `/hek snap` (or press the snapshot keybind,
  set under `/hekili` > Toggles; or the pause keybind; or tick **Auto Snapshot** to get one when the addon fails to
  recommend anything). Then open `/hekili` > **Snapshots (Troubleshooting)**, pick the snapshot from the dropdown,
  click the text box, press Ctrl+A and Ctrl+C, and paste it into the issue (or a paste site, with the link in the issue).

## Development
See [DEVELOPMENT.md](https://github.com/zmsl/hekili/blob/forever/DEVELOPMENT.md).

## Credits
Based on the original work by Hekili: https://github.com/Hekili/hekili (Hekili and its maintainers). Hekili Forever is
published with the original author's explicit permission. Author: [defzach](https://github.com/zmsl).
Bundled libraries (Ace3, LibStub, LibSharedMedia-3.0, LibDBIcon-1.0, LibDataBroker-1.1 and others) belong to their
authors under [their own licences](https://github.com/zmsl/hekili/blob/forever/src/Hekili/Libs/CREDITS.md).

## Licence
[GNU General Public License version 3 or later](https://github.com/zmsl/hekili/blob/forever/LICENSE): either version 3 of the License, or (at your option) any
later version. Modified for WoW Forever by defzach from October 2026.
