# What must change for the fork to ship as "Hekili Forever"

Date 2026-10-18. Branch `forever-rename-research` from `origin/forever` 302c1d1c. Read-only scan; this file is the only
change.

## Stipulations (from the original author, binding)

1. User-facing name is "Hekili Forever"; CurseForge entry "Hekili Forever".
2. Code may keep plain "Hekili" (globals, folders, saved variables, slash commands). No naming refactor.
3. The Options General page states clearly that Hekili Forever is a fork of the original Hekili project, made with the
   explicit permission of its original author.
4. Remove (or repoint to a fork equivalent) every contact, Discord, WoW Interface, Patreon/donation, Wago/CurseForge
   id, issue-tracker or other link to the old project.
5. GitHub info points at the fork, github.com/zmsl/hekili.
6. Anywhere else it should be clear this is not the original project.

## Method

`grep -rn -i` over the whole worktree (excluding `.git`, `src/Hekili/Libs/` third-party code and `archive/`) for:
discord, wowinterface/wowi, curseforge/curse.com, patreon, paypal, ko-fi, wago, hekili.com/.io, github.com, twitter/x,
email addresses, "issue", "support", "donat", "author", "supporter", "patron"; every `"...Hekili..."` Lua string
literal in `src/` (163 literals, filtered down to the user-visible ones); every `##` line of the four shipped TOCs;
`.pkgmeta`, `.github/`, `README.md`, `Makefile`, `Bindings.xml`, licence files. No web lookups.

Findings that are none: no `## X-Website`, `## X-Curse-Project-ID`, `## X-WoWI-ID`, `## X-Wago-ID` lines remain (the
cleanup plan removed them); no `FUNDING.yml` (already gone); no Patreon, PayPal, Ko-fi, Twitter/X or hekili.com hits;
no email address that points at the old project (the only emails are the MIT credit in `UI/Formatting.lua`, keep).

## Findings by area

Stipulation column: the number from the list above. Action: remove / repoint / reword / keep (stip. 2).

### A. TOC metadata (7 hits)

| file:line | says | stip. | action |
|---|---|---|---|
| src/Hekili/Hekili.toc:3 | `## Title: Hekili` | 1, 6 | reword: `## Title: Hekili Forever` (this is the name in the AddOns list) |
| src/Hekili/Hekili.toc:4 | `## Author: Hekili` | 6 | reword: `## Author: zmsl (fork of Hekili by Hekili, with permission)` or `## Author: zmsl` plus an `## X-Credits: Original Hekili by Hekili and its maintainers` line |
| src/Hekili/Hekili.toc:6 | `## Notes: Priority helper based on SimulationCraft action lists.` | 6 | reword: `Hekili Forever: a priority helper for WoW Forever. A fork of Hekili, made with the original author's permission.` |
| src/Hekili/Hekili.toc:2 | `## Version: forever-dev` | packaging | repoint: `@project-version@` so the packager stamps releases (Hekili.lua:21 already turns the raw token into `Dev-<build> (<date>)` for unpackaged checkouts) |
| src/Hekili_Shared/Hekili_Shared.toc:3 | `## Title: Hekili Forever` | 1 | reword: `Hekili Forever - Shared`; once the core is titled "Hekili Forever" the two would show the same name |
| src/Hekili_{Shared,Druid,Warrior}.toc:4 | `## Author: Hekili` (3 files) | 6 | reword as the core |
| src/Hekili_{Shared,Druid,Warrior}.toc:5 | `Notes: Hekili's Forever ...`, "Loaded by Hekili for a Druid/Warrior" | 1 | reword: "Hekili Forever's shared content ..." / "... Loaded by Hekili Forever for a Druid." |

Keep: `## Dependencies: Hekili, Hekili_Shared`, `## Group: Hekili`, `## SavedVariables: HekiliDB`,
`## X-Hekili-ContentAPI`, `## IconTexture` path (stip. 2). Titles "Hekili Forever - Druid/Warrior" are already right.

### B. Options General page (11 hits, all src/Hekili/Options/Options.lua unless noted)

| file:line | says | stip. | action |
|---|---|---|---|
| Options.lua:6958 | root group `name = "Hekili " .. Hekili.Version` (the window title) | 1 | reword: `"Hekili Forever " .. Hekili.Version` |
| Options.lua:6968 | `desc = "Welcome to Hekili; ..."` | 1 | reword: "Welcome to Hekili Forever; ..." |
| Options.lua:7005-7013 `supporters` + src/Hekili/Hekili.lua:46-48 `ns.Patrons` | "THANK YOU TO OUR SUPPORTERS!" and "follow the Report Issue link ... do not submit tickets for routine priority updates (i.e., from SimulationCraft)" | 4, 6 | remove the supporters heading and the Patrons text (they thank upstream's Patreon backers and describe upstream's SimC update cadence); replace with the fork notice (section "Fork notice" below) |
| Options.lua:7016-7031 `discord` | `https://discord.gg/3cCTFxM`, "Join the Hekili Discord server" | 4 | remove (no fork Discord) together with `discordSpace` |
| Options.lua:7034-7043 `github` | `https://github.com/Hekili/hekili/releases` | 5 | repoint: `https://github.com/zmsl/hekili/releases` |
| Options.lua:7044-7053 `curse` | `https://www.curseforge.com/wow/addons/hekili` | 4 | repoint to the new "Hekili Forever" CurseForge URL once the project exists; remove until then |
| Options.lua:7054-7063 `wowi` | `wowinterface.com/downloads/info24608-HekiliPriorityHelper.html` | 4 | remove |
| Options.lua:7071-7079 `link` "Report Issue" | `http://github.com/Hekili/hekili/issues` | 4, 5 | repoint: `https://github.com/zmsl/hekili/issues` |
| Options.lua:7080-7088 `faq` "Help" | `https://github.com/Hekili/hekili/wiki/Frequently-Asked-Questions` | 4 | remove, or repoint to a fork README/wiki section if one is written |
| Options.lua:7089-7097 `simulationcraft` | SimC wiki | - | keep (third party, not the old project); optional, Forever APLs are not SimC's |
| Options.lua:6994-7003 `welcome` image `Textures\Taco256` | upstream's taco logo | 6 | keep (asset path, stip. 2); optional: a fork logo later |

### C. Other option panels (8 hits, Options.lua)

| file:line | says | stip. | action |
|---|---|---|---|
| 7110 | header "Welcome to Hekili" (Getting Started) | 1 | reword: "Welcome to Hekili Forever" |
| 7116 | "...most common questions we get on Github or Discord" | 4, 6 | reword: "...on GitHub" (drop Discord; "we" is now the fork) |
| 7149 | "Displays are where Hekili shows you..." | 1 | reword to "Hekili Forever" (nice to have; generic "the addon" also fine) |
| 7152 | "clicking the Hekili <version> title" | 1 | reword: must match the new window title "Hekili Forever <version>" (must, or the instruction is wrong) |
| 7376 | "provide it where appropriate, whether Discord or in a GitHub issue report" | 4 | reword: "in a GitHub issue report" |
| 7381-7388 `issueReporting_snapshot_next_info_4` | Discord link `discord.gg/3cCTFxM` | 4 | remove |
| 7390-7397 `issueReporting_snapshot_next_info_5` | `http://github.com/Hekili/hekili/issues` | 4, 5 | repoint: `https://github.com/zmsl/hekili/issues` |
| 1718 | "Hekili has up to five built-in displays" | 1 | reword (nice to have) |

`Options.lua:234` ("This is a package of action lists for Hekili.") is the default pack description saved into
profiles: keep, or reword to "Hekili Forever"; harmless either way.

### D. Other in-game text (9 hits)

| file:line | says | stip. | action |
|---|---|---|---|
| src/Hekili/Engine/Sim/Core.lua:37 | Blizzard Interface Options category `panel.name = "Hekili"` | 1 | reword: "Hekili Forever" |
| src/Hekili/Engine/Sim/Core.lua:43 | button "Open Hekili Options Panel" | 1 | reword: "Open Hekili Forever Options" |
| src/Hekili/Engine/Sim/Core.lua:92 | "This version of Hekili is for a future version of WoW" | 1 | reword (nice to have) |
| src/Hekili/UI/UI.lua:855, :883 | compartment and LDB tooltip header `AddDoubleLine( "Hekili", ... )` | 1 | reword: "Hekili Forever" |
| src/Hekili/UI/UI.lua:866 | addon compartment `text = "Hekili"` | 1 | reword: "Hekili Forever" |
| src/Hekili/UI/UI.lua:876, :878 | LDB object name and `text = "Hekili"` | 1 | object NAME keep (stip. 2: LibDBIcon saved position is keyed by it, Options.lua:7660-7662 too); `text` may become "Hekili Forever" |
| src/Hekili/Engine/Sim/Events.lua:1021, :1024 | "does not have any Hekili modules loaded", "Hekili is designed for use in ..." | 1 | reword (nice to have) |
| src/Hekili/Engine/Content.lua:65 | "this Hekili for content API" | 1 | nice to have: "this Hekili Forever" |
| src/Hekili/UI/Styles.lua:33 | "this Hekili has %d" | 1 | nice to have |
| src/Hekili/Engine/Snapshot.lua:536-557 | snapshot header `build: <Hekili.Version>` | 6 | reword: prefix "Hekili Forever " so a pasted snapshot cannot be mistaken for an upstream one (and filed upstream) |

The chat prefix of `Hekili:Print` comes from AceConsole and the addon object name "Hekili" (Hekili.lua:9): keep
(stip. 2). Bindings.xml is fully commented out: nothing shows.

### E. README and docs (13 hits)

`README.md` is still upstream's: a "Goodbye" notice (lines 1-8, "The Hekili Project on Retail WoW has ended ...",
a note "From Syrif") then "Old Readme below". Every link points at the old project:

| file:line | says | stip. | action |
|---|---|---|---|
| README.md:1-8 | upstream's end-of-project notice | 6 | remove |
| README.md:14, :63 | `github.com/Hekili/hekili/releases/latest` | 5 | repoint to zmsl/hekili |
| README.md:67-70 | install via CurseForge/Wago/WowUp/CurseBreaker | 4 | reword: CurseForge "Hekili Forever" only, plus GitHub releases |
| README.md:83, :88, :105 | upstream wiki (snapshot how-to, Wiki, Developer Stuff) | 4 | remove or repoint to fork docs |
| README.md:84, :107, :108 | upstream issues/new, pulls, issues | 4, 5 | repoint to zmsl/hekili |
| README.md:97 | "Maintained by Hekili, Syrif, Nerien" | 6 | reword: "Hekili Forever is maintained by zmsl. It is a fork of Hekili (by Hekili, Syrif, Nerien and contributors), made with the original author's permission." |
| README.md:12 etc. | "supports all DPS and Tank specializations", Retail feature text | 6 | reword: Forever, Druid and Warrior so far |

Rewrite the README rather than patch it (M). `docs/dev/layout.md:117-120` already names the fork as `origin` and
upstream fetch-only: keep. `src/Hekili/Engine/Sim/Targets.lua:444` (`-- github.com/Hekili/hekili/issues/4845`) is a
code comment citing an upstream bug: keep. `docs/research`, `docs/superpowers` are dev-only and not shipped (ignored
by `.pkgmeta`): no change.

### F. Packaging and CI (6 hits)

| file:line | says | stip. | action |
|---|---|---|---|
| .pkgmeta:1 | `package-as: Hekili` | 1 | keep the folder name (stip. 2); the CurseForge project title is set on the site, not here |
| .pkgmeta (whole) | no `move-folders`; the four addons live in `src/`, so a BigWigs packager run today zips one `Hekili/` folder holding `src/Hekili/...` (unloadable) and none of Hekili_Shared/Druid/Warrior as separate addons | packaging | must: add `move-folders:` `Hekili/src/Hekili: Hekili`, `Hekili/src/Hekili_Shared: Hekili_Shared`, `Hekili/src/Hekili_Druid: Hekili_Druid`, `Hekili/src/Hekili_Warrior: Hekili_Warrior` (stale, as known) |
| .pkgmeta:7 | ignore `VirtualState/spec` (path no longer exists) | packaging | remove; add `tests`, `scripts`, `archive`, `Makefile`, `mise.toml`, `.github`, `.stylua.toml`, `.styluaignore` |
| .pkgmeta | no `## X-Curse-Project-ID` in any TOC and no release workflow | packaging | add the new project id to `Hekili.toc` once CurseForge assigns it, and a tag-triggered `BigWigsMods/packager` workflow with `CF_API_KEY` |
| all four TOCs:2 | `## Version: forever-dev` | packaging | `@project-version@` (see A); the content packs keep their own versions per docs/dev/layout.md:24 if that scheme stays |
| .github/workflows/check.yml | `make check` minus typecheck | - | keep, nothing upstream |

### G. Issue templates (9 hits)

| file:line | says | stip. | action |
|---|---|---|---|
| .github/ISSUE_TEMPLATE/Bug-Report-Form.yml:8, Feature-Request.yml:6, Recommendation-Report.yml:6 | `assignees: - Hekili` (auto-assigns upstream's GitHub user) | 4, 5 | repoint: `- zmsl` |
| Bug-Report-Form.yml:89, Feature-Request.yml:45, Recommendation-Report.yml:152 | `placeholder: Hekili#0001` and "alternate contact (i.e., Discord ID)" | 4 | reword placeholder to a neutral `name#0000` (nice to have) |
| Recommendation-Report.yml:119 | `github.com/Hekili/hekili/wiki/Report-An-Issue#how-do-i-get-a-snapshot` | 4 | repoint to a fork doc or inline the steps (Bug-Report-Form.yml:47-55 already lists them) |
| Recommendation-Report.yml body | asks for retail detail (Retail specs/talents) | 6 | nice to have: Forever wording |
| config.yml:4, the three `existing, open ticket` links | already `github.com/zmsl/hekili/issues` | 5 | keep |

### H. Licence and credits (4 hits)

- There is no LICENSE file at the repo root, and none in upstream's history (`git log --all -- LICENSE` finds only
  third-party library licences). Upstream Hekili ships no licence in its repository, so by default all rights are
  reserved; the author's explicit permission (the stipulations above) is the fork's legal basis, and no licence text
  of upstream's dictates an attribution form. Upstream's CurseForge listing licence was not checked (no web lookup).
- Proposed: add `LICENSE.md` (or a section in the README) that states: "Hekili Forever is a fork of Hekili
  (github.com/Hekili/hekili) by Hekili and its maintainers, published with the original author's permission. The
  original code remains theirs; Forever-specific code is (c) 2026 Zack Samsel." Ask the author whether they want
  any licence applied to the fork (must decide before release; the audit item 12 is still open).
- Credits already in code: `UI/Styles/Classic.lua:5`, `UI/Styles/Timeline.lua:11-13`, `UI/Resolve.lua:5`,
  `Options/StyleOptions.lua:3` credit "Hekili's authors and maintainers": keep.
- `src/Hekili/Libs/CREDITS.md` and the per-library LICENSE files cover vendored libraries; `Libs/VirtualGameAPI-1.0/
  LICENSE` is MIT (c) 2026 Zack Samsel: keep. `UI/Formatting.lua:10-51` MIT notice (Kristofer Karlsson et al.): keep.

## Fork notice on the General page

Where: `src/Hekili/Options/Options.lua:7005-7014`, the `supporters` description (order 6), which today renders
"THANK YOU TO OUR SUPPORTERS!" plus `ns.Patrons` (`src/Hekili/Hekili.lua:46-48`). Replace both in place, so the
notice sits directly under the logo (order 5) and above the links, the first text a user reads.

Proposed wording (keep the existing gold/blue colour codes):

> |cFF00CCFFHekili Forever|r is a fork of the original **Hekili** addon (by Hekili and its maintainers), adapted for
> WoW Forever. It is made with the explicit permission of Hekili's original author, but it is not the original
> project: please report problems with Hekili Forever on the fork's GitHub page below, not to the original Hekili
> authors.
>
> See the |cFFFFD100Snapshots (Troubleshooting)|r section for how to report a bug.

Then the link rows: GitHub (zmsl/hekili/releases), CurseForge (Hekili Forever, once it exists), Report Issue
(zmsl/hekili/issues), SimC Wiki (optional).

Content TOCs: yes, Hekili_Shared needs a new Title ("Hekili Forever - Shared", to avoid sharing the core's name), and
all three need new `## Author` and reworded `## Notes` (section A). Druid and Warrior Titles are already correct.

## Keep as is (stipulation 2; do not rename later)

- Addon folders and TOC file names: `Hekili`, `Hekili_Shared`, `Hekili_Druid`, `Hekili_Warrior`; `.pkgmeta`
  `package-as: Hekili`; `## Dependencies`, `## Group: Hekili`.
- Global `Hekili` and the AceAddon name `"Hekili"` (Hekili.lua:9), and with it the AceConsole chat prefix and
  `GetAddOnMetadata("Hekili", ...)` (Hekili.lua:10).
- SavedVariables `HekiliDB`; LDB data object and LibDBIcon key `"Hekili"` (UI.lua:876, :898; Options.lua:7660-7662);
  `ACD.OpenFrames["Hekili"]` (UI.lua:310) and the options table registration name.
- Slash commands `/hekili`, `/hek` (Core.lua:63-64).
- Frame names `HekiliDisplay*`, `HekiliNotification*`, `HekiliTooltip`, `HekiliMenu`, `HekiliEngine`,
  `HekiliDummyPanel`, `HekiliOptionsButton`, `HekiliSpec*`; AceGUI widget `HekiliCustomEditor`; globals
  `Hekili_OnAddonCompartment*`; binding names `HEKILI_*`.
- TOC field `X-Hekili-ContentAPI` and the tests that read it (tests/Forever/content_spec.lua).
- Import/export string prefix `Hekili:` and texture paths `Interface\AddOns\Hekili\Textures\...`.
- Code comments citing upstream (Targets.lua:444) and the credit headers.

## Prioritised change list

Must before release:

1. Options General page: fork notice replaces supporters/Patrons; remove Discord, WoW Interface, FAQ; repoint
   GitHub and Report Issue to zmsl/hekili; CurseForge to the new project or removed (B). **S**
2. Window title, Getting Started header and the "click the title" line (Options.lua:6958, 7110, 7152), Snapshot
   panel Discord removal and issue link (7376-7397) (B, C). **S**
3. TOCs: core Title "Hekili Forever", Shared Title "Hekili Forever - Shared", Author and Notes in all four (A). **S**
4. Issue templates: `assignees: Hekili` to `zmsl`, wiki link (G). **S**
5. README rewrite: drop the Goodbye notice, fork statement and credits, fork links only (E). **M**
6. Packaging: `.pkgmeta` `move-folders` and ignore list, `@project-version@`, CurseForge project id, release
   workflow (F). **M**
7. LICENSE / attribution file and the author's answer on a licence (H). **S** (plus the decision)
8. Interface Options category name, compartment/LDB tooltip text, snapshot header "Hekili Forever" (D). **S**

Nice to have:

- Remaining "Hekili" wording in notices and help text (Options.lua:1718, 7149; Core.lua:92; Events.lua:1021, 1024;
  Content.lua:65; Styles.lua:33) (C, D). **S**
- Issue template placeholders and retail wording (G). **S**
- A fork logo instead of the taco/orange logo (A, B). **S** (art)

Estimates per group: A S, B S, C S, D S, E M, F M, G S, H S. Total about a day, most of it packaging and the README.

## Not determined

- The licence on upstream's CurseForge listing (not fetched). The repository itself has never had one.
- Whether the packager output actually loads with the proposed `move-folders` (needs a dry run of the BigWigs
  packager; not run).
- The CurseForge project id and URL for "Hekili Forever" (project not created yet).
