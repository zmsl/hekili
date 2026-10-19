# Publishing Hekili Forever (CurseForge and GitHub) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the fork as "Hekili Forever" on CurseForge and github.com/zmsl/hekili: GPLv3 licence and attribution in place, every user-facing upstream contact link gone, the four addon folders packed into one zip by the BigWigs packager, and tagged releases uploaded by a GitHub Actions workflow.

**Architecture:** No engine or naming refactor (code keeps plain "Hekili"). Text and metadata change in the TOCs, the Options General/Getting Started/Snapshot panels, a handful of UI strings, the README and the issue templates. One busted spec (`tests/Forever/publication_spec.lua`) pins the rules that `make check` can test offline: forbidden upstream links, TOC fields, LICENSE copies, `.pkgmeta` shape, CHANGELOG present. Packaging uses `.pkgmeta` `move-folders` (the WeakAuras2 pattern) so `src/<Addon>` becomes `<Addon>/` in the zip; `make package` runs the same packager locally with `-d` (no upload) and `tools/check_package.sh` checks the zip.

**Tech Stack:** Lua 5.1, busted, BigWigs packager (`release.sh`, action `BigWigsMods/packager@v2`), GitHub Actions, bash/unzip.

**Spec:** the binding facts below (user, 2026-10-18) and `docs/research/2026-10-18-hekili-forever-rename.md` (areas for change, "Keep as is"). Line numbers in the research report are stale by about 40 lines in Options.lua; this plan cites keys and strings, grep for them.

## Binding facts (user, 2026-10-18)
- The original author approved the fork as "Hekili Forever": user-facing name and CurseForge project "Hekili Forever"; code keeps plain "Hekili" identifiers, folders, saved variables and slash commands; the Options General page clearly says Hekili Forever is a fork of the original Hekili project made with the explicit permission of the original author; every contact/Discord/WoW Interface/donation/wiki link to the old project is removed; GitHub info is github.com/zmsl/hekili; elsewhere it is clear this is not the original project.
- `## Author: defzach` in every TOC and on the CurseForge project; Notes and the project description attribute the original as "based on the original work by Hekili".
- Upstream Hekili is GPLv3 (its CurseForge page; no licence text in its repo). Obligations: LICENSE (full GPLv3) at the repo root and in `src/Hekili` (shipped); keep upstream copyright notices, add ours; a prominent "modified <date> for WoW Forever" notice (README and General page); CurseForge licence field GPLv3; the shipped Hekili logo is replaced by distinct art (the fork's taco dog icon, supplied 2026-10-18).
- CurseForge rules: credit and link the original; describe what changed, do not copy the original description; distinct name, avatar (400x400, not copyrighted art), summary, description; no game name in the project name; a changelog per uploaded file; third-party distribution toggle ON. One project ships all four folders in one zip.
- The CurseForge project exists: id `1753387`, URL https://www.curseforge.com/wow/addons/hekili-forever (user, 2026-10-18).
- Licence: GPLv3 for the entire project, per the agreement with the original author; vendored libraries keep their own licences, listed in `src/Hekili/Libs/CREDITS.md`.
- Versions: semver tags `v1.0.0`, `v1.0.1`, ...; one workflow run uploads to CurseForge and creates the GitHub release; CurseForge game version WoW Forever 1.60.1 (interface 16001).
- Releases: BigWigs packager, `@project-version@`, GitHub Actions on tags; `make check` CI stays as is.

## Global Constraints
- Do not rename anything on the research report's "Keep as is" list: folders `Hekili`, `Hekili_Shared`, `Hekili_Druid`, `Hekili_Warrior`; `package-as: Hekili`; global `Hekili`, AceAddon name `"Hekili"`; `HekiliDB`; LDB object and LibDBIcon key `"Hekili"`; `ACD` app name `"Hekili"`; `/hekili`, `/hek`; frame names `Hekili*`; `HEKILI_*` bindings; `X-Hekili-ContentAPI`; import prefix `Hekili:`; texture paths under `Interface\AddOns\Hekili\Textures\`; upstream-citing code comments and credit headers.
- User-facing name: `Hekili Forever`. Author string: `defzach`. Fork URL: `https://github.com/zmsl/hekili`. Upstream credit phrase, verbatim: `based on the original work by Hekili`.
- The only allowed link to the old project is the bare repo URL `https://github.com/Hekili/hekili` (credit), and only in README.md and `docs/publishing/README.md`; never in `src/`. The code comment at `src/Hekili/Engine/Sim/Targets.lua` (`-- https://github.com/Hekili/hekili/issues/4845`) stays and is allowlisted.
- Licence: GPL version 3 only (wording "version 3 of the License") until the author answers otherwise (open question Q1). A v3-only fork is valid whether upstream is v3-only or v3-or-later; "or later" is valid only if upstream is.
- `make check` green before every commit. Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never push tags or upload anything; the user cuts releases.

## Review Focus
1. A stale upstream link or "Discord" survives in a string the scan does not read (a locale-like table, a `.xml`, an issue template, the CurseForge description). Expect zero hits across `src/**/*.{lua,toc,xml}` (minus `Libs/`), README.md, `.github/ISSUE_TEMPLATE/*`, `docs/publishing/README.md`. Pinned by the scan in Task 1 (`publication_spec.lua`, "no upstream contact links"), whose file list comes from `git ls-files`, not a hand list.
2. The zip misses LICENSE or one of the four folders, or still holds `Hekili/src/`, `tests/`, `tools/`, `docs/`. Pinned by `tools/check_package.sh` in Task 3 (asserts each folder's TOC, `Hekili/LICENSE`, absence of dev paths) and by the `.pkgmeta` assertions in Task 1.
3. The packager rewrites TOC tokens wrongly: `@project-version@` left raw, or `## Interface: 16001` mapped to a CurseForge game version that does not exist (packager reads 16001 as classic "1.60.1"). Pinned by `check_package.sh` (no raw `@project-version@` in any packed TOC; Version equals the zip's version), by the dry-run step in Task 3 that records the game version the packager chose, and by Task 4 Step 4, which checks CurseForge's version list for 1.60.1 and sets it explicitly when the automatic mapping does not match.
4. Migration from the symlink install: extracting the zip into `AddOns\Hekili` while it is still a `mklink /D` writes through the link into the WSL working tree. Task 3's in-game check removes the four links first (exact commands); the README install section says to remove an old upstream Hekili folder too (same folder name, same `HekiliDB`, settings carry over).
5. Version mismatch between tag, TOC and changelog, or a runaway changelog: origin carries about 960 historical upstream `v*` tags. They never fire the workflow (it runs on tag pushes only, and they are already pushed), but the packager's automatic changelog runs back to the previous tag, which for `v1.0.0` is an upstream one, so it would list the fork's whole history. Pinned in Task 4: `.pkgmeta` `manual-changelog` makes the tracked CHANGELOG.md the changelog (the first release's entry is written by hand), and the workflow fails before packaging unless CHANGELOG.md has a `## <tag>` heading; `publication_spec.lua` checks every TOC's Version is `@project-version@`.

---

## File map
- Create: `LICENSE`, `src/Hekili/LICENSE` (identical GPLv3 text), `CHANGELOG.md`, `src/Hekili/Textures/HekiliForever.tga`, `docs/publishing/icon-512.png`, `tests/Forever/publication_spec.lua`, `tools/check_package.sh`, `.github/workflows/release.yml`, `docs/publishing/README.md` (CurseForge page text, release how-to, package dry run).
- Modify: the four TOCs; `src/Hekili/Hekili.lua` (header, `ns.Patrons` removed); `src/Hekili/Options/Options.lua` (General page, window title, Getting Started, Snapshot panel); `src/Hekili/Engine/Sim/Core.lua`, `src/Hekili/UI/UI.lua`, `src/Hekili/Engine/Snapshot.lua`, `src/Hekili/Engine/Sim/Events.lua`, `src/Hekili/Engine/Content.lua`, `src/Hekili/UI/Styles.lua` (strings); `README.md` (rewrite); `.github/ISSUE_TEMPLATE/*.yml`; `.pkgmeta`; `.gitignore` (stop ignoring CHANGELOG.md); `Makefile` (`package`, `package-check`); `docs/dev/layout.md` (version rule); `src/Hekili/Libs/CREDITS.md` only if Task 1's check finds a gap.

---

### Task 1: Licence, attribution and the publication spec (S)

**Files:**
- Create: `LICENSE`, `src/Hekili/LICENSE`, `tests/Forever/publication_spec.lua`
- Modify: `src/Hekili/Hekili.lua:1-2` (header)

**Interfaces:**
- Produces: `tests/Forever/publication_spec.lua` with `describe` blocks "licence", "upstream links", "readme", "tocs", "pkgmeta", "changelog", and the top-level `scan(files, upstream)` helper. Tasks 2, 2b, 3 and 4 turn their `pending` blocks into real ones by deleting the `pending(...)` line and un-commenting the body (each block's body is written here in full).

- [ ] **Step 1: Write the spec** (`tests/Forever/publication_spec.lua`). All five blocks are written now; the ones owned by later tasks start as `pending` so this task stays green.

```lua
-- tests/Forever/publication_spec.lua (publication plan, docs/superpowers/plans/2026-10-18-publication.md):
-- the offline publication rules: the GPLv3 LICENSE ships, no user-facing link to the old project survives,
-- the TOCs carry the fork's name/author/credit, .pkgmeta packs the four src/ folders, and CHANGELOG.md exists.

local function read(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a")
    f:close()
    return s
end

local function tracked(...)
    local p = assert(io.popen("git ls-files -- " .. table.concat({ ... }, " ")))
    local out = {}
    for line in p:lines() do
        out[#out + 1] = line
    end
    p:close()
    return out
end

local TOCS = {
    "src/Hekili/Hekili.toc",
    "src/Hekili_Shared/Hekili_Shared.toc",
    "src/Hekili_Druid/Hekili_Druid.toc",
    "src/Hekili_Warrior/Hekili_Warrior.toc",
}

local function field(toc, key)
    return read(toc):match("\n## " .. key .. ": ([^\r\n]*)") or read(toc):match("^## " .. key .. ": ([^\r\n]*)")
end

describe("licence", function()
    it("ships the full GPLv3 text at the root and in src/Hekili, byte-identical", function()
        local root = read("LICENSE")
        assert.truthy(root:find("GNU GENERAL PUBLIC LICENSE", 1, true))
        assert.truthy(root:find("Version 3, 29 June 2007", 1, true))
        assert.truthy(root:find("END OF TERMS AND CONDITIONS", 1, true))
        assert.are.equal(root, read("src/Hekili/LICENSE"))
    end)

    it("states the modification notice in the core's header", function()
        local head = read("src/Hekili/Hekili.lua"):sub(1, 1200)
        assert.truthy(head:find("based on the original work by Hekili", 1, true))
        assert.truthy(head:find("Modified for WoW Forever by defzach", 1, true))
        assert.truthy(head:find("GNU General Public License", 1, true))
    end)
end)

-- lowercase patterns; a hit is "path:line: text"
local FORBIDDEN = {
    "discord",
    "wowinterface",
    "patreon",
    "paypal",
    "ko%-fi",
    "curseforge%.com/wow/addons/hekili$",
    "curseforge%.com/wow/addons/hekili[^%-]",
    "hekili#0001",
}
local ALLOW = { ["src/Hekili/Engine/Sim/Targets.lua"] = "github%.com/hekili/hekili/issues/4845" }

local function scan(files, upstream)
    local hits = {}
    for _, path in ipairs(files) do
        if not path:find("/Libs/", 1, true) then
            local n = 0
            for line in (read(path) .. "\n"):gmatch("([^\n]*)\n") do
                n = n + 1
                local l = line:lower()
                if ALLOW[path] and l:find(ALLOW[path]) then l = "" end
                for _, pat in ipairs(FORBIDDEN) do
                    if l:find(pat) then hits[#hits + 1] = path .. ":" .. n .. ": " .. line end
                end
                if l:find(upstream) then hits[#hits + 1] = path .. ":" .. n .. ": " .. line end
            end
        end
    end
    return hits
end

describe("upstream links", function()
    pending("Task 2 turns this on")
    --[[ TASK 2 BODY
    it("has none in shipped files (src/: no github.com/Hekili at all)", function()
        local files = tracked("'src/*.lua'", "'src/*.toc'", "'src/*.xml'")
        assert.is_true(#files > 50)
        assert.are.same({}, scan(files, "github%.com/hekili"))
    end)

    it("has only the bare upstream repo link in issue templates and the publishing record", function()
        local files = tracked("'.github/ISSUE_TEMPLATE/*'", "docs/publishing/README.md")
        assert.is_true(#files >= 4)
        assert.are.same({}, scan(files, "github%.com/hekili/hekili/"))
    end)

    it("credits and links the original in the publishing record", function()
        local s = read("docs/publishing/README.md")
        assert.truthy(s:lower():find("based on the original work by hekili", 1, true))
        assert.truthy(s:find("https://github.com/Hekili/hekili", 1, true))
        assert.truthy(s:find("explicit permission", 1, true))
    end)

    it("puts the fork notice on the General page", function()
        local s = read("src/Hekili/Options/Options.lua")
        assert.truthy(s:find("is a fork of the original |cFFFFD100Hekili|r project", 1, true))
        assert.truthy(s:find("explicit permission of its original author", 1, true))
        assert.truthy(s:find('name = "Hekili Forever " .. Hekili.Version', 1, true))
        assert.falsy(s:find("ns.Patrons", 1, true))
    end)
    --]]
end)

describe("readme", function()
    pending("Task 2b turns this on")
    --[[ TASK 2B BODY
    it("has no old-project link but the bare upstream repo", function()
        assert.are.same({}, scan({ "README.md" }, "github%.com/hekili/hekili/"))
        assert.falsy(read("README.md"):lower():find("wiki", 1, true))
    end)

    it("credits the original, states the permission, the fork's tracker and the licence", function()
        local s = read("README.md")
        for _, want in ipairs({
            "docs/publishing/icon-512.png",
            "based on the original work by Hekili",
            "explicit permission",
            "https://github.com/Hekili/hekili",
            "https://github.com/zmsl/hekili/issues",
            "https://github.com/zmsl/hekili/releases",
            "GNU General Public License version 3",
            "Modified for WoW Forever by defzach",
            "Libs/CREDITS.md",
        }) do
            assert.truthy(s:find(want, 1, true), want)
        end
    end)
    --]]
end)

describe("tocs", function()
    pending("Task 2 turns this on")
    --[[ TASK 2 BODY
    it("name the fork, its author and the original in every TOC", function()
        for _, toc in ipairs(TOCS) do
            assert.are.equal("defzach", field(toc, "Author"), toc)
            assert.truthy(field(toc, "Title"):find("^Hekili Forever"), toc)
            assert.truthy(field(toc, "Notes"):lower():find("based on the original work by hekili", 1, true), toc)
            assert.are.equal("https://github.com/zmsl/hekili", field(toc, "X-Website"), toc)
        end
        assert.are.equal("Hekili Forever", field(TOCS[1], "Title"))
        assert.are.equal("Hekili Forever - Shared", field(TOCS[2], "Title"))
    end)

    it("keep the Keep-as-is fields", function()
        assert.are.equal("HekiliDB", field(TOCS[1], "SavedVariables"))
        for i = 2, 4 do
            assert.truthy(field(TOCS[i], "Dependencies"):find("^Hekili"), TOCS[i])
            assert.are.equal("Hekili", field(TOCS[i], "Group"), TOCS[i])
            assert.truthy(field(TOCS[i], "X-Hekili-ContentAPI"), TOCS[i])
        end
    end)
    --]]
    --[[ TASK 4 BODY
    it("let the packager stamp the version in every TOC", function()
        for _, toc in ipairs(TOCS) do
            assert.are.equal("@project-version@", field(toc, "Version"), toc)
        end
    end)
    --]]
end)

describe("pkgmeta", function()
    pending("Task 3 turns this on")
    --[[ TASK 3 BODY
    it("moves the four src/ folders to the zip root and ignores the dev tree", function()
        local s = read(".pkgmeta")
        assert.truthy(s:find("\npackage%-as: Hekili\n") or s:find("^package%-as: Hekili\n"))
        for _, a in ipairs({ "Hekili", "Hekili_Shared", "Hekili_Druid", "Hekili_Warrior" }) do
            assert.truthy(s:find("\n    Hekili/src/" .. a .. ": " .. a .. "\n", 1, true), a)
        end
        for _, p in ipairs({ "tests", "tools", "docs", "scripts", "archive", ".superpowers", ".github" }) do
            assert.truthy(s:find("\n    - " .. p .. "\n", 1, true), p)
        end
        assert.falsy(s:find("LICENSE", 1, true)) -- never ignored
        assert.falsy(s:find("externals", 1, true)) -- libraries are vendored
    end)
    --]]
end)

describe("changelog", function()
    pending("Task 4 turns this on")
    --[[ TASK 4 BODY
    it("is tracked and opens with a version heading", function()
        assert.are.same({ "CHANGELOG.md" }, tracked("CHANGELOG.md"))
        assert.truthy(read("CHANGELOG.md"):find("^# Hekili Forever changelog\n\n## v%d+%.%d+%.%d+\n"))
    end)
    --]]
end)
```

- [ ] **Step 2: Run it, expect FAIL** — `.lua/bin/busted tests/Forever/publication_spec.lua`. Expected: "licence" fails on `io.open("LICENSE")`; the rest pending.

- [ ] **Step 3: Add the licence text.**

```bash
curl -fsSL https://www.gnu.org/licenses/gpl-3.0.txt -o LICENSE
cp LICENSE src/Hekili/LICENSE
head -3 LICENSE   # expect: "                    GNU GENERAL PUBLIC LICENSE" / "Version 3, 29 June 2007"
```
Do not edit the GPL text. Upstream shipped no copyright notice in its files (grep found only third-party ones in `Game/API/Facade.lua`, `Game/Events/Rows.lua`, `Game/State/Families/Casts.lua`, `UI/Formatting.lua`); keep every existing notice untouched.

- [ ] **Step 4: Core header** — replace the first two lines of `src/Hekili/Hekili.lua` (`-- Hekili.lua` / `-- July 2024`) with the block below. No upstream URL here: the `src/` scan (Task 2) forbids `github.com/Hekili` in shipped files.

```lua
-- Hekili.lua
-- July 2024
--
-- Hekili Forever, based on the original work by Hekili and its maintainers (the original Hekili project),
-- distributed under the GNU General Public License version 3 (see LICENSE).
-- Modified for WoW Forever by defzach, from October 2026 (https://github.com/zmsl/hekili); this is a fork,
-- not the original project, made with the explicit permission of the original author.
```

- [ ] **Step 5: Libs/CREDITS.md check.** Confirm every folder under `src/Hekili/Libs/` (except `CREDITS.md`) has a row: `for d in src/Hekili/Libs/*/; do n=$(basename "$d"); grep -q "^| $n" src/Hekili/Libs/CREDITS.md || echo "missing $n"; done`. Expected: no output; if a library is missing, add its row in the existing column format (upstream, pin, licence, author credit). Then add a short section "Licence compatibility with GPLv3" under the table: the project as a whole is GPLv3 (agreement with the original author) and each library keeps its own licence; list only incompatibilities. Expected: none for the usual set (Ace3 BSD-style, LibStub public domain, LibSharedMedia LGPL-2.1, MIT libraries such as VirtualGameAPI-1.0). For each library whose row says no licence is stated (AceGUI-3.0-SharedMediaWidgets, LibSpellRange-1.0, and any other the column shows) write `licence unknown, ask or replace`, and for AceGUI-3.0_SFX-Widgets' custom licence `custom licence, check terms`. These are not release blockers.

- [ ] **Step 6: Run, expect PASS** — `.lua/bin/busted tests/Forever/publication_spec.lua` (licence green, rest pending), then `make check`.

- [ ] **Step 7: Commit**

```bash
git add LICENSE src/Hekili/LICENSE src/Hekili/Hekili.lua tests/Forever/publication_spec.lua src/Hekili/Libs/CREDITS.md
git commit -m "chore(licence): GPLv3 LICENSE at the root and in Hekili, fork notice in the core header, publication spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Rename pass (M)

**Files:**
- Modify: the four TOCs; `src/Hekili/Hekili.lua` (`ns.Patrons`); `src/Hekili/Options/Options.lua`; `src/Hekili/Engine/Sim/Core.lua`; `src/Hekili/UI/UI.lua`; `src/Hekili/Engine/Snapshot.lua`; `src/Hekili/Engine/Sim/Events.lua`; `src/Hekili/Engine/Content.lua`; `src/Hekili/UI/Styles.lua`; `.github/ISSUE_TEMPLATE/{Bug-Report-Form,Feature-Request,Recommendation-Report}.yml`; `src/Hekili/Engine/Schema/Spec.lua` (icon)
- Create: `docs/publishing/README.md` (stub with the credit paragraph; Task 5 records the page in it), `src/Hekili/Textures/HekiliForever.tga`, `docs/publishing/icon-512.png`
- Delete: `src/Hekili/Textures/{LOGO-ORANGE,LOGO-WHITE,Taco256,TACODOG}.blp`
- Test: `tests/Forever/publication_spec.lua` (enable "upstream links" and the Task 2 "tocs" body)

**Interfaces:**
- Consumes: Task 1's spec. Produces: TOC field values Task 3/4 rely on, including `## X-Curse-Project-ID: 1753387` (Step 3).

- [ ] **Step 1: Turn on the tests.** In `publication_spec.lua` delete the two `pending("Task 2 turns this on")` lines and the `--[[ TASK 2 BODY` / `--]]` markers around the Task 2 bodies. Run `.lua/bin/busted tests/Forever/publication_spec.lua`. Expected: FAIL, listing the Options.lua Discord/WoW Interface/upstream lines, the TOC fields, templates and the missing `docs/publishing/README.md`. (README.md is Task 2b's; its block stays pending here.)

- [ ] **Step 2: TOCs.** Edit the `##` header of each file (other lines unchanged; Version stays `forever-dev` until Task 4; IconTexture changes in Step 9):

`src/Hekili/Hekili.toc`
```
## Title: Hekili Forever
## Author: defzach
## Notes: Hekili Forever: a priority helper for WoW Forever, based on the original work by Hekili. A fork made with the original author's permission; not the original project.
## X-Website: https://github.com/zmsl/hekili
```
`src/Hekili_Shared/Hekili_Shared.toc`
```
## Title: Hekili Forever - Shared
## Author: defzach
## Notes: Hekili Forever's content every class shares: shared auras, consumables, items and the race packs. Based on the original work by Hekili.
## X-Website: https://github.com/zmsl/hekili
```
`src/Hekili_Druid/Hekili_Druid.toc` (Title unchanged)
```
## Author: defzach
## Notes: Hekili Forever's Druid: the class kit and its default priorities, loaded by Hekili Forever for a Druid. Based on the original work by Hekili.
## X-Website: https://github.com/zmsl/hekili
```
`src/Hekili_Warrior/Hekili_Warrior.toc`: as Druid with "Warrior". (The spec matches the credit phrase case-insensitively, so "Based ..." passes.)

- [ ] **Step 3: CurseForge id.** Add to `src/Hekili/Hekili.toc` after `## X-Website`: `## X-Curse-Project-ID: 1753387` (the packager uploads to this project). Add to the spec's Task 2 `tocs` test: `assert.are.equal("1753387", field(TOCS[1], "X-Curse-Project-ID"))`.

- [ ] **Step 4: General page** (`src/Hekili/Options/Options.lua`, the `general` group args). Replace the `supporters` entry (order 6) with:

```lua
                    forkNotice = {
                        type = "description",
                        name = "|cFF00CCFFHekili Forever|r is a fork of the original |cFFFFD100Hekili|r project, made with the "
                            .. "explicit permission of its original author. It is based on the original work by Hekili and its "
                            .. "maintainers, modified for WoW Forever by defzach from October 2026, and it is |cffff0000not|r "
                            .. "the original project: please report problems on the Hekili Forever GitHub page below, never "
                            .. "to the original Hekili authors.\n\n"
                            .. "Hekili Forever is free software under the GNU General Public License version 3; the full text "
                            .. "is in the LICENSE file in the addon folder.\n\n"
                            .. "See the |cFFFFD100Snapshots (Troubleshooting)|r section for how to report a bug.\n\n",
                        fontSize = "medium",
                        order = 6,
                        width = "full"
                    },
```
Delete `discord`, `discordSpace`, `wowi`, `faq`. Repoint:
- `curse`: `desc = "Find Hekili Forever updates on CurseForge."`, `get = function () return "https://www.curseforge.com/wow/addons/hekili-forever" end` (the scan forbids only upstream's `.../addons/hekili` slug; `hekili-forever` passes)
- `github`: `desc = "Find Hekili Forever updates on GitHub."`, `get = function () return "https://github.com/zmsl/hekili/releases" end`
- `link` ("Report Issue"): `get = function() return "https://github.com/zmsl/hekili/issues" end`
Keep `simulationcraft`. Root group: `name = "Hekili Forever " .. Hekili.Version`; general `desc = "Welcome to Hekili Forever; includes general information and essential links."`.
Delete `ns.Patrons` (its three lines) from `src/Hekili/Hekili.lua`; `grep -rn Patrons src tests` must be empty.

- [ ] **Step 5: Other option panels** (same file):
- `gettingStarted_welcome_header.name = "Welcome to Hekili Forever\n"`
- `gettingStarted_welcome_info`: `"...the most common questions we get on GitHub. \n\n"` (drop "or Discord")
- `gettingStarted_displays_info`: `"are where Hekili Forever shows you"` and `"clicking the |cFFFFD100Hekili Forever " .. Hekili.Version .. " |rtitle"` (must match the window title)
- Displays help `"Hekili has up to five built-in displays"` -> `"Hekili Forever has up to five built-in displays"`
- `issueReporting_snapshot_next_info_3`: `"...provide it in a GitHub issue report on the Hekili Forever page."`
- delete `issueReporting_snapshot_next_info_4` (Discord); `issueReporting_snapshot_next_info_5.get` -> `"https://github.com/zmsl/hekili/issues"`
- default pack `desc = "This is a package of action lists for Hekili Forever."`

- [ ] **Step 6: Other in-game text:**
- `Engine/Sim/Core.lua`: `panel.name = "Hekili Forever"`; `open:SetText( "Open Hekili Forever Options" )`
- `UI/UI.lua`: menu title `text = "Hekili Forever"` (menuData isTitle); both `AddDoubleLine( "Hekili", ...)` -> `"Hekili Forever"`; compartment `text = "Hekili Forever"`; LDB `text = "Hekili Forever"` but `LDB:NewDataObject( "Hekili", ...)` and `LDBIcon:Register( "Hekili", ...)` unchanged (keep list)
- `Engine/Snapshot.lua`: `"build: %s\n"` -> `"Hekili Forever build: %s\n"`
- `Engine/Sim/Events.lua`: `" does not have any Hekili Forever modules loaded (yet).\nWatch for updates."`
- `Engine/Content.lua`: `", this Hekili Forever for "`; `UI/Styles.lua`: `"this Hekili Forever has %d"`
Then `make test-fast`; fix any spec that asserts the old string (grep the old text in `tests/` first: `grep -rn 'Open Hekili Options\|this Hekili \|build: ' tests`).

- [ ] **Step 7: Issue templates.** In all three: `assignees:` list becomes only `  - zmsl` (drop `Hekili`, `syrifgit`); `placeholder: Hekili#0001` -> `placeholder: your-name`; "alternate contact method (i.e., Discord ID)" -> "alternate contact method". `Recommendation-Report.yml:119` link -> `[How to get a Snapshot](https://github.com/zmsl/hekili#reporting-a-problem)` (the README section from Step 8). Retail wording in Recommendation-Report: replace "Retail" with "WoW Forever" where it names the game.

- [ ] **Step 8: README** moved to Task 2b (its own reviewable task).

- [ ] **Step 9: The fork's icon.** Upstream's art (`LOGO-ORANGE.blp`, `LOGO-WHITE.blp`, `Taco256.blp`, `TACODOG.blp`) must not ship as the fork's identity. The art is ready (user, 2026-10-18; a taco dog with an infinity halo, already the CurseForge avatar): a 512x512 RGBA PNG and a 256x256 TGA made from it.

```bash
cp /home/zack/.claude/jobs/080a308e/tmp/pubplan/HekiliForever.tga src/Hekili/Textures/HekiliForever.tga
cp /home/zack/.claude/jobs/080a308e/tmp/pubplan/icon-512.png docs/publishing/icon-512.png   # README/CurseForge only, not shipped (docs/ is ignored by .pkgmeta)
```
Point every reference at it (no extension, the client resolves `.tga`):
- `src/Hekili/Hekili.toc`: `## IconTexture: Interface\AddOns\Hekili\Textures\HekiliForever`
- `src/Hekili/UI/UI.lua` compartment: `icon = "Interface\\AddOns\\Hekili\\Textures\\HekiliForever",`
- `src/Hekili/Engine/Schema/Spec.lua` (`NewSpecialization( 0, "All", ...)`, was LOGO-WHITE): `"Interface\\AddOns\\Hekili\\Textures\\HekiliForever"`
- `src/Hekili/Options/Options.lua` `welcome.image` (was Taco256): `"Interface\\AddOns\\Hekili\\Textures\\HekiliForever"`
Then `grep -rn 'LOGO-\|Taco256\|TACODOG' src tests | grep -v /Libs/` must be empty, and `git rm src/Hekili/Textures/{LOGO-ORANGE,LOGO-WHITE,Taco256,TACODOG}.blp`. Add to the spec's Task 2 `tocs` test: `assert.are.equal("Interface\\AddOns\\Hekili\\Textures\\HekiliForever", field(TOCS[1], "IconTexture"))` and `assert.truthy(io.open("src/Hekili/Textures/HekiliForever.tga"))`.

- [ ] **Step 10: `docs/publishing/README.md` stub** (Task 5 fills the rest):

```markdown
# Publishing Hekili Forever

Hekili Forever is based on the original work by Hekili (https://github.com/Hekili/hekili), published with the explicit
permission of the original author.
```

- [ ] **Step 11: Keep-as-is reaffirmed.** `git diff --stat` must not touch `.pkgmeta`'s `package-as`, any `SavedVariables`, `/hekili`/`/hek` registration, `NewAddon( "Hekili"`, `NewDataObject( "Hekili"`, `LDBIcon:Register( "Hekili"`, `ACD:Open( "Hekili" )`. Check: `git diff -U0 | grep -E '^-.*(NewAddon|NewDataObject|LDBIcon:Register|RegisterChatCommand|SavedVariables)'` is empty.

- [ ] **Step 12: Run** `.lua/bin/busted tests/Forever/publication_spec.lua` (PASS), `make check` (PASS). In game (user, `/reload` through the symlinks): the AddOns list shows "Hekili Forever" with the taco dog icon; `/hekili` window title "Hekili Forever <version>"; General page shows the taco dog image, the notice and only GitHub, CurseForge (hekili-forever), Report Issue, SimC Wiki rows; Snapshots page has no Discord row.

- [ ] **Step 13: Commit**

```bash
git add -A src .github/ISSUE_TEMPLATE docs/publishing tests/Forever/publication_spec.lua
git commit -m "feat(fork): Hekili Forever name, icon, fork notice and fork links; upstream contact links and logos removed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2b: README (M)

**Files:**
- Modify: `README.md` (replace the whole file)
- Test: `tests/Forever/publication_spec.lua` (enable "readme")

**Interfaces:**
- Consumes: `docs/publishing/icon-512.png` (Task 2 Step 9); the user's CurseForge description, verbatim HTML at `/home/zack/.claude/jobs/080a308e/tmp/pubplan/curseforge-description.html` (the controller passes this path; Task 5 stores the same text in the repo).

- [ ] **Step 1: Enable the "readme" block** (remove `pending("Task 2b turns this on")` and the `TASK 2B BODY` markers). Run `.lua/bin/busted tests/Forever/publication_spec.lua`. Expected: FAIL (upstream's README: releases/wiki/issues links, no icon, no licence line).

- [ ] **Step 2: Convert the description.** Read the HTML file whole. Convert it to Markdown keeping its sections, order and wording: `<h3>` -> `##`, the `- ...` display lines -> a Markdown list, the numbered troubleshooting items -> `1.`/`2.`/`3.` with the underlined lead-in as **bold**, `&gt;` -> `>`, `&nbsp;` dropped, links as Markdown links. The red callout (second, right after the fork paragraph) becomes a blockquote in bold: `> **This addon is not maintained by the original Hekili project. ...** [https://github.com/zmsl/hekili/issues](https://github.com/zmsl/hekili/issues)`. Do not reword it except the one typo fix "based the level 30 beta" -> "based on the level 30 beta" (tell the user).

- [ ] **Step 3: Assemble README.md** in this order:
1. `<p align="center"><img src="docs/publishing/icon-512.png" alt="Hekili Forever" width="160"></p>` then `# Hekili Forever`.
2. From the description, in its order: the fork paragraph, the red callout, What is Hekili Forever?, Supported Classes, Action Packs, Displays, Current Mode, Other Customization, Toggles, Troubleshooting.
3. GitHub-only sections:

```markdown
## Install
- **CurseForge:** install **Hekili Forever** (https://www.curseforge.com/wow/addons/hekili-forever).
- **GitHub:** download the zip from https://github.com/zmsl/hekili/releases and extract it into
  `_classic_beta_\Interface\AddOns\`. It holds four folders: `Hekili`, `Hekili_Shared`, `Hekili_Druid`, `Hekili_Warrior`.
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
Layout and conventions: `docs/dev/layout.md`. Run `make bootstrap` once, then `make check` before every commit.
Packaging and releases: `docs/publishing/README.md`.

## Credits
Based on the original work by Hekili: https://github.com/Hekili/hekili (Hekili and its maintainers). Hekili Forever is
published with the original author's explicit permission. Author: [defzach](https://github.com/zmsl).
Bundled libraries (Ace3, LibStub, LibSharedMedia-3.0, LibDBIcon-1.0, LibDataBroker-1.1 and others) belong to their
authors under their own licences; see `src/Hekili/Libs/CREDITS.md`.

## Licence
GNU General Public License version 3 (`LICENSE`), as the original Hekili. Modified for WoW Forever by defzach from
October 2026.
```
The description's own Credits line ("Based on the original work by Hekili. Author: defzach.") is replaced by the Credits section above, which keeps that wording and adds the upstream link and the libraries.

- [ ] **Step 4: Check every path and command against the tree:** `ls docs/dev/layout.md docs/publishing/README.md docs/publishing/icon-512.png src/Hekili/Libs/CREDITS.md LICENSE`; `grep -n 'bootstrap:\|^check:' Makefile`; `grep -n 'snap  *= "snapshot"' src/Hekili/Options/ChatCommands.lua`; `grep -n 'Auto Snapshot\|Snapshots (Troubleshooting)' src/Hekili/Options/Options.lua`; `grep -n 'toggles.snapshot.key' src/Hekili/Options/Options.lua`; and for each library named in Credits `ls -d src/Hekili/Libs/<name>`. Every option path the description names (`/hekili > General > Enabled`, `Displays > Primary and AOE`, `Visibility` tab, `Profiles`, `Action Packs`, `Toggles` > Mode Switch) must exist: `grep -n 'name = "Enabled"\|name = "Visibility"\|name = "Profiles"\|name = "Action Packs"\|Mode Switch' src/Hekili/Options/*.lua | head`. Report any that does not match to the user instead of changing the description's wording.

- [ ] **Step 5: Run** `.lua/bin/busted tests/Forever/publication_spec.lua` (PASS), `make check` (PASS). Preview the Markdown (GitHub renders the icon from the relative path).

- [ ] **Step 6: Commit**

```bash
git add README.md tests/Forever/publication_spec.lua
git commit -m "docs(readme): Hekili Forever README from the CurseForge description, plus install, reporting, development, credits, licence

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Packaging and the local dry run (M)

**Files:**
- Modify: `.pkgmeta`, `Makefile`, `tests/Forever/publication_spec.lua` (enable "pkgmeta")
- Create: `tools/check_package.sh`
- Modify: `docs/publishing/README.md` (dry-run section)

**Interfaces:**
- Produces: `make package` (zip in `.release/`, no upload), `make package-check` (runs `tools/check_package.sh <zip>`); Task 4's workflow runs the same `.pkgmeta`.

- [ ] **Step 1: Enable the spec block** (remove `pending("Task 3 turns this on")` and the `TASK 3 BODY` markers). Run: FAIL on the missing `move-folders` lines.

- [ ] **Step 2: `.pkgmeta`** (whole file):

```yaml
package-as: Hekili

enable-nolib-creation: no

# The four addons live in src/; move them to the zip root (src/Hekili replaces the package folder itself, so
# root files such as LICENSE do not survive: src/Hekili/LICENSE is the shipped copy).
move-folders:
    Hekili/src/Hekili: Hekili
    Hekili/src/Hekili_Shared: Hekili_Shared
    Hekili/src/Hekili_Druid: Hekili_Druid
    Hekili/src/Hekili_Warrior: Hekili_Warrior

manual-changelog:
    filename: CHANGELOG.md
    markup-type: markdown

ignore:
    - tests
    - tools
    - docs
    - scripts
    - archive
    - .superpowers
    - .github
    - .busted
    - .luacheckrc
    - .luarc.json
    - .stylua.toml
    - .styluaignore
    - Makefile
    - mise.toml
    - src/Hekili_Warrior/APLs
    - src/Hekili_Druid/APLs
```
(`VirtualState/spec` is gone from the tree; no `externals`: libraries are vendored per `Libs/CREDITS.md`. `manual-changelog` makes CHANGELOG.md the per-file changelog; Task 4 creates it. Until then the dry run warns about the missing changelog; that is expected in this task.)

- [ ] **Step 3: `tools/check_package.sh`**

```bash
#!/usr/bin/env bash
# Checks a packager zip: the four addon folders at the root, LICENSE in Hekili/, no dev paths, TOC versions stamped.
set -euo pipefail
zip=${1:?usage: check_package.sh <zip>}
list=$(unzip -Z1 "$zip")
fail=0
need() { grep -qx "$1" <<<"$list" || { echo "missing: $1"; fail=1; }; }
for a in Hekili Hekili_Shared Hekili_Druid Hekili_Warrior; do need "$a/$a.toc"; done
need Hekili/LICENSE
need Hekili/embeds.xml
for bad in '^Hekili/src/' '/tests/' '/tools/' '^Hekili/docs/' '/APLs/' '\.simc$' '^Hekili/Makefile$' '^Hekili/\.'; do
    if grep -qE "$bad" <<<"$list"; then echo "unexpected: $(grep -E "$bad" <<<"$list" | head -3)"; fail=1; fi
done
ver=$(basename "$zip" .zip); ver=${ver#Hekili-}
for a in Hekili Hekili_Shared Hekili_Druid Hekili_Warrior; do
    v=$(unzip -p "$zip" "$a/$a.toc" | tr -d '\r' | sed -n 's/^## Version: //p')
    [ "$v" = "$ver" ] || { echo "$a.toc Version '$v' != zip version '$ver'"; fail=1; }
done
[ $fail -eq 0 ] && echo "package ok: $zip"
exit $fail
```
`chmod +x tools/check_package.sh`. Self-check against a broken zip: `cd /tmp && rm -rf pk && mkdir -p pk/Hekili && echo x > pk/Hekili/Hekili.toc && (cd pk && zip -qr ../Hekili-x.zip Hekili) && bash ~/src/hekili-wt-pubplan/tools/check_package.sh /tmp/Hekili-x.zip; echo "exit $?"`. Expected: several `missing:` lines and `exit 1`.

- [ ] **Step 4: Makefile targets** (append; add `package package-check` to `.PHONY`):

```make
# The BigWigs packager run locally, no upload (-d): zip in .release/ (docs/publishing/README.md). Needs network once.
PACKAGER_REF ?= v2
package:
	@mkdir -p $(LUA_ENV)
	@test -s $(LUA_ENV)/release.sh || curl -fsSL https://raw.githubusercontent.com/BigWigsMods/packager/$(PACKAGER_REF)/release.sh -o $(LUA_ENV)/release.sh
	bash $(LUA_ENV)/release.sh -d -r .release

package-check: package
	bash tools/check_package.sh "$$(ls -t .release/Hekili-*.zip | head -1)"
```
Not part of `check` (network, and the packager needs a clean commit to version from).

- [ ] **Step 5: Dry run in WSL.** On a clean tree (`git status --short` empty): `make package-check`. Expected: `package ok: .release/Hekili-<describe>.zip`. Until Task 4 the TOC Version is still `forever-dev`, so the Version check fails with `Version 'forever-dev' != zip version ...`; that failure is expected here and goes away in Task 4. Record in the commit message: the zip name, and the packager's "Game version" line (`grep -i 'game version' ` in its output; expected classic `1.60.1`; Task 4 Step 4 confirms it against CurseForge). If `move-folders` leaves `Hekili/src/` behind or drops a folder, stop and report (do not reshape the repo).

- [ ] **Step 6: In-game zip check (user).** Back up and remove the four `mklink /D` links first, or extraction writes into the WSL repo. In an elevated Windows `cmd` in `_classic_beta_\Interface\AddOns`: `rmdir Hekili Hekili_Shared Hekili_Druid Hekili_Warrior` (rmdir on a directory link removes only the link). Extract the zip there (from `\\wsl.localhost\personal\home\zack\src\hekili-wt-pubplan\.release\`), full client restart, log in a Druid or Warrior: displays show, `/hekili` opens, General page has the notice, no Lua errors. Then delete the four extracted folders and re-create the links (`mklink /D Hekili \\wsl.localhost\personal\home\zack\src\TacoDogForever\...` per the README of the dev repo; the user's existing commands).

- [ ] **Step 7: Document** in `docs/publishing/README.md`, section "Local package dry run": the Step 5 command, that `.release/` is gitignored, that a dirty tree or no tag gives a `git describe` version (it may name an upstream tag such as `v2.5.5-...-g<hash>`; harmless for a dry run), and the Step 6 symlink warning verbatim.

- [ ] **Step 8: Run** `.lua/bin/busted tests/Forever/publication_spec.lua` (PASS) and `make check` (PASS).

- [ ] **Step 9: Commit**

```bash
git add .pkgmeta Makefile tools/check_package.sh tests/Forever/publication_spec.lua docs/publishing/README.md
git commit -m "build(package): move-folders for the src/ layout, dev-tree ignores, make package and a zip check

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Release workflow, versioning and changelog (S)

**Files:**
- Create: `.github/workflows/release.yml`, `CHANGELOG.md`
- Modify: four TOCs (`## Version`), `.gitignore`, `docs/dev/layout.md` (version rule), `docs/publishing/README.md` (release how-to), `tests/Forever/publication_spec.lua` (enable the Task 4 bodies)

**Interfaces:**
- Consumes: `.pkgmeta` (Task 3), `## X-Curse-Project-ID: 1753387` (Task 2), repo secret `CF_API_KEY` (user).
- Produces: tag scheme `vMAJOR.MINOR.PATCH` (first `v1.0.0`); CHANGELOG headings `## <tag>`.

- [ ] **Step 1: Enable the Task 4 spec bodies** (remove `pending("Task 4 turns this on")` and both `TASK 4 BODY` markers). Run: FAIL (Version `forever-dev`, no CHANGELOG.md).

- [ ] **Step 2: Versions.** In all four TOCs: `## Version: @project-version@`. `Hekili.lua` already turns the raw token into `Dev-<build> (<date>)` for symlinked checkouts. The content TOCs show the raw token in the AddOns list when unpackaged; acceptable. In `docs/dev/layout.md` replace "A class release bumps the pack addon's `## Version`" with "Every TOC's `## Version` is `@project-version@`; the packager stamps the release tag into all four (one zip, one version)".

- [ ] **Step 3: CHANGELOG.md (mandatory).** Without it the packager writes its own changelog from `git log` since the previous tag, and for `v1.0.0` the previous reachable tag is an upstream one, so it would span the fork's whole history. The tracked file (`.pkgmeta` `manual-changelog`, Task 3) is the per-file changelog CurseForge requires; the first release's entry is written by hand, as below. Remove the `CHANGELOG.md` line from `.gitignore`. Create:

```markdown
# Hekili Forever changelog

## v1.0.0

First release of Hekili Forever, based on the original work by Hekili, for the WoW Forever client.
- Druid (Feral, Balance, Guardian) and Warrior (Arms, Fury, Protection) default priorities.
- Classic and Timeline display styles.
- Fork notice and fork links (github.com/zmsl/hekili); licence GPLv3.
```

- [ ] **Step 4: `.github/workflows/release.yml`**

```yaml
# Packs a release when a vX.Y.Z tag is pushed (docs/publishing/README.md): BigWigsMods/packager uploads the zip to
# CurseForge (project from ## X-Curse-Project-ID, key CF_API_KEY) and creates the GitHub release (GITHUB_TOKEN) in the
# same run. Only tag pushes fire it: the historical upstream v* tags on origin were pushed long ago and never run it.
name: release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: write # GitHub release

jobs:
  release:
    runs-on: ubuntu-latest
    env:
      CF_API_KEY: ${{ secrets.CF_API_KEY }}
      GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: CHANGELOG has this tag
        run: grep -qx "## ${GITHUB_REF_NAME}" CHANGELOG.md || { echo "CHANGELOG.md has no '## ${GITHUB_REF_NAME}' heading"; exit 1; }
      - uses: BigWigsMods/packager@v2
```
This is the "publish directly from GitHub to CurseForge" path: one run, two destinations. `CF_API_KEY` uploads to CurseForge; `GITHUB_OAUTH` (the built-in `GITHUB_TOKEN`, hence `contents: write`) creates the GitHub release for the tag with the same zip and changelog. No Wago/WoWI ids: not used.

- [ ] **Step 4a: CurseForge game version.** The packager maps `## Interface: 16001` to the classic version name `1.60.1` and looks that name up in CurseForge's list. Confirm it exists (user, with the token from the one-time setup in Step 5):

```bash
curl -fsS -H "X-Api-Token: $CF_API_KEY" https://wow.curseforge.com/api/game/versions | jq '.[] | select(.name | test("^1\\.60")) | {id, name, gameVersionTypeID}'
curl -fsS -H "X-Api-Token: $CF_API_KEY" https://wow.curseforge.com/api/game/version-types | jq '.[] | {id, name, slug}'
```
If an entry named `1.60.1` exists under the WoW Forever version type, nothing to set. If it is missing or listed under another name, pin it in the packager step (the packager takes version names with `-g` and resolves the id itself) and record the id beside it:

```yaml
      - uses: BigWigsMods/packager@v2
        with:
          args: -g 1.60.1 # CurseForge game version id from the query above (WoW Forever 1.60.1); use the listed name
```
and pass the same `-g` in the Makefile's local run (`bash $(LUA_ENV)/release.sh -d -g 1.60.1 -r .release`) so the dry run reports what the upload will use. Record the name and id in `docs/publishing/README.md` under "CurseForge page".

- [ ] **Step 5: Release how-to** in `docs/publishing/README.md`, section "Cutting a release":
1. `make check` green on `forever`; write `## vX.Y.Z` with the changes by hand at the top of CHANGELOG.md (under the title); commit.
2. `git tag vX.Y.Z && git push origin vX.Y.Z` (push that one tag, never `--tags`).
3. Watch Actions > release: the one run uploads the zip to CurseForge project 1753387 with CHANGELOG.md as its changelog and creates the GitHub release for the tag.
One-time setup: CurseForge > API tokens > create token; GitHub repo > Settings > Secrets > Actions > `CF_API_KEY`.

- [ ] **Step 6: Run** `.lua/bin/busted tests/Forever/publication_spec.lua` (PASS), `make check` (PASS), then on a clean tree `git tag v0.0.0 && make package-check && git tag -d v0.0.0`. Expected: `package ok: .release/Hekili-v0.0.0.zip` (all four TOC Versions stamped). Never push that tag.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/release.yml CHANGELOG.md .gitignore src/*/*.toc docs/dev/layout.md docs/publishing/README.md tests/Forever/publication_spec.lua
git commit -m "build(release): packager workflow on v* tag pushes (CurseForge + GitHub release), @project-version@ in every TOC, CHANGELOG.md

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: CurseForge page record (S)

The page is already set up by the user; this task records it in the repo, it writes nothing new.

**Files:**
- Modify: `docs/publishing/README.md` (section "CurseForge page")

- [ ] **Step 1: Record the settings and the description** in `docs/publishing/README.md`, below the stub paragraph (which keeps the upstream credit link the spec checks):

````markdown
## CurseForge page

The user's settings on https://www.curseforge.com/wow/addons/hekili-forever (project 1753387), recorded 2026-10-18.
README.md derives its user-facing sections from the description below; change both together.

- **Name:** Hekili Forever
- **Summary:** <copy the summary exactly as set on the page; ask the user if it is not in the controller's brief>
- **Licence field:** GNU General Public License version 3 (GPLv3)
- **Third-party distribution:** ON
- **Avatar:** `docs/publishing/icon-512.png` (the fork's taco dog icon)
- **Game version:** WoW Forever 1.60.1 (interface 16001; see "Cutting a release")
- **Source / issues:** https://github.com/zmsl/hekili , https://github.com/zmsl/hekili/issues

### Description (verbatim HTML)

```html
<the full contents of /home/zack/.claude/jobs/080a308e/tmp/pubplan/curseforge-description.html, unchanged>
```
````
The two angle-bracket lines are instructions to the implementer, not text to commit: paste the HTML file's contents unchanged (`cat` it into the fence), and ask the controller for the summary string if it was not passed.

- [ ] **Step 2: Run** the spec (PASS: the record credits and links upstream through the stub paragraph, says "explicit permission", and holds no forbidden link).

- [ ] **Step 3: Commit**

```bash
git add docs/publishing/README.md
git commit -m "docs(publishing): record the CurseForge page settings and description

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Verification checklist and open questions (S, no code)

- [ ] **Offline** (`make check` covers): publication spec green; `grep -rniE 'discord|wowinterface|patreon|github\.com/hekili' src --include=*.lua --include=*.toc --include=*.xml | grep -v /Libs/` shows only `Targets.lua` 4845.
- [ ] **Package:** `make package-check` on a throwaway local `v0.0.0` tag (deleted after) prints `package ok`; `unzip -l` shows four top-level folders and `Hekili/LICENSE`.
- [ ] **In game from the zip** (links removed first, full restart): AddOns list titles "Hekili Forever", "Hekili Forever - Shared/Druid/Warrior", author defzach, the taco dog icon; `/hekili` title "Hekili Forever <tag>"; General page notice, GitHub/CurseForge/Report Issue/SimC rows only; Snapshots page without Discord; a snapshot starts "Hekili Forever build:"; Interface Options category "Hekili Forever"; compartment and minimap tooltips "Hekili Forever"; minimap button keeps its saved position (LDBIcon key unchanged).
- [ ] **CurseForge:** project fields as Task 5; first upload has the CHANGELOG entry as its changelog; distribution toggle ON; licence GPLv3; avatar is `docs/publishing/icon-512.png`.
- [ ] **GitHub:** repo description/website point at the CurseForge page; issue templates assign `zmsl`.
- [ ] **Merge** `forever-pubplan` work into `forever` after `/ponytail-review` (pre-approved once reviewed and checked); tag only after the merge.

Open questions for the original author:
- **Q1:** GPL "version 3 only" or "version 3 or later"? (The plan writes v3 only, valid either way.)
- **Q2:** May the README/CurseForge page quote the permission publicly (e.g. "with the permission of Hekili, <date>"), and in what words?

