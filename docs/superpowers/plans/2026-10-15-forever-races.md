# Forever Race Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Classic race has a Forever race file in the Hekili fork: its castable racials as abilities with the DB2's cooldowns and GCDs (`handler` and `now` where the cast leaves an aura), its passives as modifiers where they model to anything, `all`'s stale racial IDs replaced for the live race, Eureka!'s cost scope listed for every Gnome class, and each file inert for any other race.

**Architecture:** Race files only, through `Hekili:NewRace( token )` and `Races.lua`'s four `Register*` calls; no edit to `Races.lua`, `Classes.lua` or `Virtual/`. Task 1 amends the shipped files (`Gnome.lua`: `EUREKA_SPELLS` by class file, resolved against `Hekili.Class.file`, and Escape Artist; `NightElf.lua`: Shadowmeld 20580 over `all`'s 58984) and turns `races_spec` into a TOC-driven suite (every `Forever\Races\` line of `Hekili.toc` loads; each file registers exactly its own keys and modifier counts; every `now` runs in Families/Now.lua's strict context and allocates nothing). Tasks 2-4 add Human + Dwarf, Orc + Troll, Undead (token `Scourge`), each with its TOC lines and one override case. Task 5 is the in-game CHECKPOINT, tokens first.

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, `lua5.1`/`luac5.1`, the Forever DB2 through `~/.local/share/wow-db2/bin/wowdb` (build 1.60.1.70338).

**Spec:** `docs/superpowers/specs/2026-10-15-forever-races.md` (binding; §2 the registrations and the GCD rule, §3 the override list, §4 the Eureka! lists and their query, §5 tokens, §6 tests, §7 the checkpoint). Read with it: the research brief `/home/zack/.claude/jobs/080a308e/tmp/races/research.md` ("R §n"), `Races.lua` (the registration object, `ns.applyRace`), the event-facade spec `docs/superpowers/specs/2026-10-15-virtualstate-event-facade.md` (§12a `now`, §12b race packs), and the Druid plan `docs/superpowers/plans/2026-10-15-forever-druid-pack.md` Task 6 (the shape of a race-file task).

## How this plan was checked

Every patch below was written and run before the plan was saved, on a scratch clone of the worktree at `688dd350`: per task the spec patch applied and run red, the implementation patch, the whole verification block, a commit. Then every patch was extracted again from this markdown and the whole plan replayed from `688dd350` in a fresh copy: per task the spec patch run red, the implementation patch, the verification block, `git add` with exactly the task's commit list, a commit, and an empty `git status` after it; the counts below are that replay's. The base counts at `688dd350`: 273 busted successes, luacheck 0 warnings in 87 files, `tools/check_api_reads.sh` 54 loaded files, the inventory diff empty, LuaLS no problems. The Eureka! lists (Task 1) were re-queried from the DB2 with the query in spec §4. The CHECKPOINT (Task 5) is the user's and the orchestrator's.

## Global Constraints

- Repository `~/src/hekili`. Work only in the worktree `~/src/hekili/.claude/worktrees/forever-races`, branch `forever-races`, at the spec-and-plan docs commit on top of `688dd350` when Task 1 starts. Git from WSL only. After each task's green verification and clean review, push the branch (`git push origin forever-races`); never push to `forever`, `classic`, `forever-druid` or `virtualstate-event-facade`; never force-push. No task merges.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, naming the model that wrote the commit; an implementer on another model replaces `Claude Opus 5.5` with its own model's name.
- No LICENSE or README changes, in any repository. No changes to `archive/` or `Libs/`.
- Secret safety (event-facade spec §8): nothing compares, indexes or does arithmetic on a client value without `issecretvalue()` first, and nothing uses `a and b or c` on a possibly-secret value. Race files read no game API at all (`Hekili.Class.file` is set by `Classes.lua`; `tools/check_api_reads.sh` enforces the rest).
- `now` handlers (event-facade spec §12a): a `now` names only the context's verbs and reads (`gain`, `spend`, `applyBuff`, `applyDebuff`, `removeBuff`, `removeDebuff`, `addStack`, `setCooldown`; `talent`, `buff`, `debuff`, the resources by key, `knownRank`, `now`, `combat`, Lua's pure `min`/`max`/`floor`); no Hekili `state`, no game API, no file-local helper that reads either, no `ipairs` (Stoneform's three `removeBuff` lines are spelled inline). `now` and `handler` are two closures (one shared is refused). Task 1's strict-context cases run every race `now` through `Families/Now.lua` and require 0 errors.
- Inert registration: every race file runs for every race (the TOC loads them all); `Hekili:NewRace( token )` makes its `Register*` calls no-ops unless `token` is `state.race_token`. A file never branches on the race itself.
- Performance: no allocation in recurring paths (a cast's `now`, an ability's `buff`/`usable` read in the simulation); allocation only at load. Task 1's strict-context helper measures 1000 further casts of every race `now` at 0 bytes (`Virtual/State/spec/helpers/alloc.lua`); Stoneform's `buff` reads a file-level list with a numeric loop (`all`'s built a table per call).
- TOC order (`Hekili.toc`): each new race file right after the last `Forever\Races\` line (Task 2 after `Tauren.lua`, Task 3 after `Dwarf.lua`, Task 4 after `Troll.lua`), so every race file follows every class file (`races_spec` asserts it). Adding files to the TOC needs a client restart, not a `/reload`, before the checkpoint.
- `.luacheckrc`: `files["Forever/Races/"] = { globals = stateEnv }` already covers every new file and every name they use (`applyBuff`, `removeBuff`, `applyDebuff`, `buff`, `boss`, `solo`, `moving`); no edit. The verification block's luacheck file count grows by one per new file.
- Scope: spec §1-§8. Not: the Skyborne races (no token; spec §1), Eureka!'s damage, Touch of the Grave, any stat passive, a priority line naming a racial, any edit to `Races.lua`, `Classes.lua` or `Virtual/`.
- Tools: `BUSTED=~/src/TacoDogForever/.lua/bin/busted`, `LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck`, `LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server`, `lua5.1`, `luac5.1`, `WOWDB=~/.local/share/wow-db2/bin/wowdb`. All commands run from the worktree root.
- Every code task ends with the verification block, written out per task with its expected results, then a commit:

  ```bash
  BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
  LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
  $BUSTED                                                     # [N successes / 0 failures / 0 errors]
  $LUACHECK .                                                 # [0 warnings / 0 errors in F files]
  LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: ... in L loaded files]
  LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
    | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
  $LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
  git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
  ```
- Patches are applied with `git apply` from the worktree root, in the order given; each was generated by `git diff` in the replay.
- Style: specs use the TDF layout (4 spaces, no spaces inside parentheses); `Forever/Races/*.lua` keep Hekili's style (spaces inside parentheses), the shape of `Gnome.lua`: header (the racials with their DB2 values, what is not registered and why, "Inert for any other race (Races.lua)"), `local addon, ns = ...`, `NewRace`, abilities then their auras.
- The user runs the game. A **CHECKPOINT** task stops execution: the orchestrator (not a subagent) pushes the branch, points the client's checkout at it with `git -C ~/src/hekili checkout --detach forever-races`, asks the user to run the exact lines given, and waits. Every in-game line is under 255 characters (checked by script) and copies its answer through `VSCopy(` (ForeverProbe's copy box, `/vscopy` reopens it): the user cannot copy chat. ForeverProbe (`~/src/ForeverProbe`) is loaded. When the session ends, `git -C ~/src/hekili checkout forever`.

## Review Focus

1. **Inert for every other race.** Task 1 "lists Hekili.toc's race files after the class files, each registering only its own keys and modifiers": every race file runs for every token, so a key leaking to another race fails it; "is inert for another race" on a token no file answers (`BloodElf`).
2. **The stale `all` entries are replaced for the live race only.** One override case per task over a seeded stale entry, through `ns.applyRace` (spec §3's eight rows).
3. **Every race `now` runs in the strict context and allocates nothing.** Task 1 "runs every `now` the <token> registers in the context without an error" (one case per race file, every ability with a `now`; `I.nowErrors == 0`, the aura believed up; 1000 more casts at 0 bytes).
4. **Eureka! covers the right spells, per class, and nothing for a class without it.** Task 1 "scopes Eureka! by the loaded class": 17 / 10 / 16 / 13 / 16, a percent cost in scope, no modifier for a Druid (a `spells = nil` modifier would discount every ability).
5. **The GCD rule.** Every ability's `gcd` against spec §2 (the DB2's `gcd_ms`); Q5 confirms in game.

## File structure

```
Forever/Races/Gnome.lua           Task 1  EUREKA_SPELLS by class file; Escape Artist; header
Forever/Races/NightElf.lua        Task 1  Shadowmeld 20580 (ability and aura) over all's 58984; header
Virtual/State/spec/races_spec.lua Task 1  TOC-driven race list, OWN table, per-token now cases with the 0-byte check,
                                          Eureka! per class, Escape Artist and Shadowmeld; Tasks 2-4 one OWN row pair
                                          and one override case each
Forever/Races/Human.lua           Task 2  Will to Survive 1259718 (over all's 59752), Perception
Forever/Races/Dwarf.lua           Task 2  Stoneform 180 s on the GCD, aura 20594 (over all's 65116)
Forever/Races/Orc.lua             Task 3  Blood Fury 20572 for every class, Shatter Curse
Forever/Races/Troll.lua           Task 3  Berserking 20554 (over all's 26297), Rapid Regeneration
Forever/Races/Undead.lua          Task 4  token Scourge: Will of the Forsaken, Cannibalize (aura 20578)
Hekili.toc                        Tasks 2-4  the new race files after Forever\Races\Tauren.lua
```

## Order and checkpoints

Task 1 (the amendments and the TOC-driven spec every later task extends), Tasks 2-4 (independent new files; each extends `OWN` and the TOC), then Task 5, CHECKPOINT: Q1 (tokens) first on every character the user has, then Q2-Q9. A wrong token is a one-word fix in the file's `NewRace` argument (and `TOKEN` in the spec) after the checkpoint.

Deliberately not built (a review should not flag them): a Skyborne file; a `handler`/`now` on Will to Survive or Will of the Forsaken (nothing to write); a `usable` gate on Cannibalize (corpse) or the cleanses (Stoneform keeps `all`'s); Quick Strike and Execute 20647 in the Warrior's Eureka! list; a test of the real `Classes.lua` `all` (the spec's stand-in seeds the stale entries); removal of `all`'s stale numeric aliases.

---

### Task 1: Gnome and Night Elf amendments; the TOC-driven races spec

Spec §2 (Escape Artist, Shadowmeld), §3 (Shadowmeld's two rows), §4 (the lists), §6. `Gnome.lua` keeps Eureka! and Expansive Mind and gains `EUREKA_SPELLS` keyed by class file (the Warrior's 17 unchanged, Rogue 10, Mage 16, Warlock 13, Priest 16: rank-1 IDs from spec §4's query), one cost modifier on `EUREKA_SPELLS[ Hekili.Class.file ]` and none for a class without a list, and Escape Artist (20589, 120 s, on the GCD, aura 3 s). `NightElf.lua` registers Shadowmeld 20580 (10 s, off the GCD, `all`'s `usable` gate verbatim, aura 20580 for 3600 s) over `all`'s 58984. `Tauren.lua` is unchanged (spec §1). `races_spec.lua`: the race files come from `Hekili.toc`; `load` takes a class (default `WARRIOR`, as `Classes.lua` sets `class.file` before the race files); the inert case uses `BloodElf` (Human becomes a race in Task 2); new cases for the TOC/`OWN` table, Eureka! per class, and Escape Artist + Shadowmeld; the strict-context describe runs every `now` of every token (replacing its three fixed cases) and measures 1000 further casts at 0 bytes.

**Files:**
- Modify: `Forever/Races/Gnome.lua`, `Forever/Races/NightElf.lua`
- Test: `Virtual/State/spec/races_spec.lua`

**Interfaces:**
- Consumes: `Hekili:NewRace`, `race:RegisterCostMod` (Races.lua); `Hekili.Class.file` (Classes.lua:1476).
- Produces: `escape_artist`, `shadowmeld` (ability and aura) in `all` for their races; the Eureka! modifier's `spells` per class.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Virtual/State/spec/races_spec.lua b/Virtual/State/spec/races_spec.lua
index f17e15f0..71559fe6 100644
--- a/Virtual/State/spec/races_spec.lua
+++ b/Virtual/State/spec/races_spec.lua
@@ -1,6 +1,32 @@
--- Virtual/State/spec/races_spec.lua (event-facade spec §12b): race packs. Races.lua's `Hekili:NewRace` and the Gnome's
--- pack (Forever/Races/Gnome.lua), loaded headless against a stand-in for Hekili: inert for another race, registered for
--- the Gnome; and the simulation's half of the cost modifier on abilities built as RegisterAbility builds them.
+-- Virtual/State/spec/races_spec.lua (event-facade spec §12b): race packs. Races.lua's `Hekili:NewRace` and every race
+-- file Hekili.toc lists (Forever/Races/*.lua), loaded headless against a stand-in for Hekili: inert for another race,
+-- registered for its own, over `all`'s stale entries; and the simulation's half of the cost modifier on abilities
+-- built as RegisterAbility builds them.
+
+-- Every race file Hekili.toc lists, in its order, and the race token (UnitRace's second return) each answers to.
+local TOKEN = { Undead = "Scourge" } -- a file named otherwise than its token
+local RACES = {}
+for line in io.lines("Hekili.toc") do
+    local file = line:match("^Forever\\Races\\(%w+)%.lua")
+    if file then
+        RACES[#RACES + 1] = { file = file, token = TOKEN[file] or file }
+    end
+end
+
+-- Runs every race file, as Hekili.toc loads them.
+local function loadRaces(rns)
+    for _, r in ipairs(RACES) do
+        assert(loadfile("Forever/Races/" .. r.file .. ".lua"))("Hekili", rns)
+    end
+end
+
+-- By race file: the ability keys it registers for its own token, and its resource and cost modifiers' counts (for a
+-- Warrior).
+local OWN = {
+    Gnome = { { "escape_artist", "eureka" }, 1, 1 },
+    NightElf = { { "elunes_light", "shadowmeld" }, 0, 0 },
+    Tauren = { { "war_stomp" }, 0, 0 },
+}
 
 describe("race packs", function()
     local ns, hekili, state, all, saved
@@ -16,7 +42,7 @@ describe("race packs", function()
         end
     end
 
-    local function load(token, seed)
+    local function load(token, seed, class)
         state = {
             race_token = token,
             buff = setmetatable({}, {
@@ -43,13 +69,12 @@ describe("race packs", function()
         function all:RegisterAura(key, def)
             register(self.auras, key, def)
         end
-        hekili = { State = state, Class = { specs = { [0] = all }, abilities = {} } }
+        -- Classes.lua sets class.file before any race file runs
+        hekili = { State = state, Class = { specs = { [0] = all }, abilities = {}, file = class or "WARRIOR" } }
         _G.Hekili = hekili
         ns = {}
         assert(loadfile("Races.lua"))("Hekili", ns)
-        for _, file in ipairs({ "Gnome", "NightElf", "Tauren" }) do -- every race file runs, as Hekili.toc loads them
-            assert(loadfile("Forever/Races/" .. file .. ".lua"))("Hekili", ns)
-        end
+        loadRaces(ns)
     end
 
     -- An ability as Classes.lua's RegisterAbility builds it: function fields in `funcs`, called on access, wrapped.
@@ -83,7 +108,7 @@ describe("race packs", function()
     end)
 
     it("is inert for another race: nothing registered, no modifier", function()
-        load("Human")
+        load("BloodElf")
         assert.are.same({}, all.abilities)
         assert.are.same({}, all.auras)
         assert.are.same({ maxMods = {}, costMods = {} }, ns.raceMods)
@@ -185,6 +210,69 @@ describe("race packs", function()
         assert.is_nil(all.abilities.elunes_light or all.abilities.war_stomp)
     end)
 
+    it("lists Hekili.toc's race files after the class files, each registering only its own keys and modifiers", function()
+        local n, lastClass, firstRace = 0, 0, math.huge
+        for line in io.lines("Hekili.toc") do
+            n = n + 1
+            if line:match("^Forever\\Classes\\") then
+                lastClass = n
+            elseif line:match("^Forever\\Races\\") then
+                firstRace = math.min(firstRace, n)
+            end
+        end
+        assert.is_true(lastClass < firstRace)
+        local files, want = {}, {}
+        for _, r in ipairs(RACES) do
+            files[#files + 1] = r.file
+            load(r.token)
+            local keys = {}
+            for k in pairs(all.abilities) do
+                if type(k) == "string" then
+                    keys[#keys + 1] = k
+                end
+            end
+            table.sort(keys)
+            local own = OWN[r.file] or {}
+            local mods = hekili.RaceMods -- the table read in game (Races.lua)
+            assert.are.same(own, { keys, #mods.maxMods, #mods.costMods }, r.file)
+        end
+        for file in pairs(OWN) do
+            want[#want + 1] = file
+        end
+        table.sort(files)
+        table.sort(want)
+        assert.are.same(want, files) -- every race file is in Hekili.toc
+    end)
+
+    it("scopes Eureka! by the loaded class: 17 Warrior, 10 Rogue, 16 Mage, 13 Warlock, 16 Priest, none for a Druid", function()
+        for class, n in pairs({ WARRIOR = 17, ROGUE = 10, MAGE = 16, WARLOCK = 13, PRIEST = 16 }) do
+            load("Gnome", nil, class)
+            assert.are.same({ 1, n }, { #ns.raceMods.costMods, #ns.raceMods.costMods[1].spells }, class)
+        end
+        load("Gnome", nil, "MAGE")
+        local blast = ability("arcane_blast", { id = 400574, spend = 0.15, spendType = "mana" })
+        state.buff.eureka = { up = true, count = 3 }
+        assert.is_true(math.abs(blast.spend - 0.135) < 1e-9) -- a percent cost (ManaCost 0 in SpellPower) is in scope
+        load("Gnome", nil, "DRUID")
+        assert.are.same({ 1, 0 }, { #ns.raceMods.maxMods, #ns.raceMods.costMods })
+    end)
+
+    it("registers Escape Artist on the GCD, and Shadowmeld 20580 over `all`'s stale 58984", function()
+        load("Gnome")
+        local ea = all.abilities.escape_artist
+        assert.are.same({ 20589, 120, "spell", "defensives" }, { ea.id, ea.cooldown, ea.gcd, ea.toggle })
+        assert.are.same({ 20589, 3 }, { all.auras.escape_artist.id, all.auras.escape_artist.duration })
+        local stock = { id = 58984, cooldown = 120 }
+        load("NightElf", { shadowmeld = stock, [58984] = stock })
+        local meld = all.abilities.shadowmeld
+        assert.are.same({ 20580, 10, "off" }, { meld.id, meld.cooldown, meld.gcd })
+        assert.is_function(meld.usable) -- `all`'s boss-or-group and not-moving gate, kept
+        assert.are.same({ 20580, 3600 }, { all.auras.shadowmeld.id, all.auras.shadowmeld.duration })
+        local class = { abilities = { shadowmeld = stock }, auras = { shadowmeld = { id = 58984 } } }
+        ns.applyRace(class)
+        assert.are.same({ 20580, 20580 }, { class.abilities.shadowmeld.id, class.auras.shadowmeld.id })
+    end)
+
     it("takes a class file's spec:RegisterCostMod (Classes.lua) into the same list, for any race", function()
         load("Human")
         -- the mixin's entry as Classes.lua declares it, compiled with this `ns` as its upvalue
@@ -220,6 +308,7 @@ describe("race packs in VirtualState's now context", function()
     local vload = require("Virtual.State.spec.helpers.load")
     local fake = require("Virtual.State.spec.helpers.fake_api")
     local fs = require("Virtual.State.spec.helpers.fake_spec")
+    local alloc = require("Virtual.State.spec.helpers.alloc")
     local saved
 
     before_each(function()
@@ -245,60 +334,75 @@ describe("race packs in VirtualState's now context", function()
         function all:RegisterAura(key, def)
             self.auras[key] = def
         end
-        _G.Hekili = { State = { race_token = token }, Class = { specs = { [0] = all } } }
+        _G.Hekili = { State = { race_token = token }, Class = { specs = { [0] = all }, file = "WARRIOR" } }
         local rns = {}
         assert(loadfile("Races.lua"))("Hekili", rns)
-        for _, file in ipairs({ "Gnome", "NightElf", "Tauren" }) do
-            assert(loadfile("Forever/Races/" .. file .. ".lua"))("Hekili", rns)
-        end
+        loadRaces(rns)
         return all
     end
 
-    for _, case in ipairs({
-        { "Gnome", "eureka", 1259813, "player" },
-        { "NightElf", "elunes_light", 1259799, "player" },
-        { "Tauren", "war_stomp", 20549, "target" },
-    }) do
-        local token, key, id, unit = case[1], case[2], case[3], case[4]
-        it("runs the " .. token .. "'s `now` (" .. key .. ") in the context without an error", function()
-            local all = registrations(token)
-            local a, aura = all.abilities[key], all.auras[key]
-            local api, ctl = fake.new()
-            ctl.now = 1
-            _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue = api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
-            _G.debugprofilestop = function()
-                return 0
+    -- One cast of race ability `key` (its aura: the same key) in a fresh VirtualState: 0 errors, 1 run, the aura believed
+    -- up; then 1000 more allocate nothing.
+    local function cast(all, key)
+        local a, aura = all.abilities[key], all.auras[key]
+        local api, ctl = fake.new()
+        ctl.now = 1
+        _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue = api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
+        _G.debugprofilestop = function()
+            return 0
+        end
+        local ns = vload.module()
+        local VS, I = ns.VirtualState, ns.VirtualStateInternal
+        local h = fs.new(9)
+        h.Class.abilities[key] = {
+            key = key,
+            id = a.id,
+            copy = a.copy,
+            cast = 0,
+            cooldown = a.cooldown,
+            gcd = a.gcd,
+            charges = 1,
+            recharge = 0,
+            funcs = { now = a.now, handler = a.handler },
+        }
+        h.Class.auras[key] = { key = key, id = aura.id, copy = aura.copy, duration = aura.duration, max_stack = aura.max_stack }
+        fs.clock = api.GetTime
+        ns.spendResources = fs.spend
+        ns.ResourceRegenerates = function()
+            return false
+        end
+        vload.adapter(ns, h)
+        VS.Start(api)
+        VS.SpecChanged()
+        ctl.Tick(1)
+        ctl.now = 5
+        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", a.id)
+        ctl.Tick(5.01)
+        VS.Drain(5.02)
+        assert.are.same({ 0, 1 }, { I.nowErrors, I.nowRuns }, key .. ": " .. tostring(I.nowError))
+        assert.is_not_nil(VS.Aura("player", aura.id, 5.1) or VS.Aura("target", aura.id, 5.1), key)
+        function h:ForceUpdate() end -- the fake records each call; Hekili's own only sets fields
+        local t = 5
+        assert.are.equal(0, alloc.bytes(function() -- the same cast again, each past the cooldown
+            t = t + 200
+            ctl.now = t
+            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", a.id)
+            ctl.Tick(t + 0.01)
+            VS.Drain(t + 0.02)
+        end, 1000), key)
+    end
+
+    for _, r in ipairs(RACES) do
+        it("runs every `now` the " .. r.token .. " registers in the context without an error", function()
+            local all, n = registrations(r.token), 0
+            for key, a in pairs(all.abilities) do
+                if a.now then
+                    assert.are_not.equal(a.handler, a.now, key) -- two closures: one shared would be refused
+                    cast(all, key)
+                    n = n + 1
+                end
             end
-            local ns = vload.module()
-            local VS, I = ns.VirtualState, ns.VirtualStateInternal
-            local h = fs.new(9)
-            h.Class.abilities[key] = {
-                key = key,
-                id = a.id,
-                copy = a.copy,
-                cast = 0,
-                cooldown = a.cooldown,
-                gcd = a.gcd,
-                charges = 1,
-                recharge = 0,
-                funcs = { now = a.now, handler = a.handler },
-            }
-            h.Class.auras[key] = { key = key, id = aura.id, copy = aura.copy, duration = aura.duration, max_stack = aura.max_stack }
-            fs.clock = api.GetTime
-            ns.spendResources = fs.spend
-            ns.ResourceRegenerates = function()
-                return false
-            end
-            vload.adapter(ns, h)
-            VS.Start(api)
-            VS.SpecChanged()
-            ctl.Tick(1)
-            ctl.now = 5
-            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
-            ctl.Tick(5.01)
-            VS.Drain(5.02)
-            assert.are.same({ 0, 1 }, { I.nowErrors, I.nowRuns }, tostring(I.nowError))
-            assert.is_not_nil(VS.Aura(unit, id, 5.1))
+            assert.is_true(n > 0)
         end)
     end
 end)
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `273 successes / 2 failures / 1 error` (the TOC/`OWN` case: Gnome and Night Elf register one key fewer; Eureka! per class: no list for the Rogue; Escape Artist: nil). The three strict-context cases pass already (the shipped `now`s allocate nothing).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/Races/Gnome.lua b/Forever/Races/Gnome.lua
index 2e8f1942..ed9db32a 100644
--- a/Forever/Races/Gnome.lua
+++ b/Forever/Races/Gnome.lua
@@ -1,7 +1,9 @@
 -- Forever/Races/Gnome.lua
--- The Gnome's Forever racials (DB2 1.60.1.70338), for every class: Eureka! (15 s: the next 3 abilities in its scope
--- cost 10% less, +10% damage not modelled; 120 s, off the GCD) and Expansive Mind (+5% maximum resources: 20591
--- Priest/Mage/Warlock, 1259802 Warrior, 1259803 Rogue). Inert for any other race (Races.lua).
+-- The Gnome's Forever racials (DB2 1.60.1.70338): Eureka! (15 s: the next 3 abilities in its scope cost 10% less,
+-- +10% damage not modelled; 120 s, off the GCD; one ID per class: 1259813 Warrior, 1259812 Rogue, 1259817 Mage,
+-- 1259821 Warlock, 1259823 Priest), Expansive Mind (+5% maximum resources: 20591 Priest/Mage/Warlock, 1259802
+-- Warrior, 1259803 Rogue) and Escape Artist (20589: roots and snares removed, immune for 3 s; 120 s, on the GCD).
+-- Engineering Specialization is a profession passive. Inert for any other race (Races.lua).
 
 local addon, ns = ...
 local Hekili = _G[ addon ]
@@ -10,6 +12,34 @@ local race = Hekili:NewRace( "Gnome" )
 
 local EUREKA = { 1259812, 1259817, 1259821, 1259823 } -- the other classes' Eureka!
 
+-- Eureka!'s cost scope (its effect 0: aura 108 misc 14 -10, class masks against the class's SpellClassSet) by class
+-- file: rank-1 IDs of the class's skill-line spells the masks cover, from
+-- select distinct o.SpellID, n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID
+--   join SpellPower p on p.SpellID=o.SpellID join spell_skill k on k.spell_id=o.SpellID where o.SpellClassSet=<set>
+--   and not (((o.SpellClassMask_0 & 4294967295)&<m0>)=0 and ((o.SpellClassMask_1 & 4294967295)&<m1>)=0
+--   and ((o.SpellClassMask_2 & 4294967295)&<m2>)=0)
+-- (no ManaCost filter: a percent cost reads 0 there). Higher ranks resolve through the class's `copy` lists; an ID the
+-- loaded class does not register is absent (Races.lua, Modifiers.lua). Not listed: Rebuke 425609 (a Paladin spell in
+-- the Rogue's set), Felfire 24530 (no class), the Warrior's Quick Strike 429765 and unranked Execute 20647 (unverified).
+local EUREKA_SPELLS = {
+    -- set 4, masks 1784679630 / 5 / 1: Heroic Strike, Cleave, Slam, Execute, Overpower, Mortal Strike, Bloodthirst,
+    -- Whirlwind, Shield Slam, Revenge, Thunder Clap, Hamstring, Intercept, Mocking Blow, Pummel, Shield Bash, Spearing
+    -- Strike. Not: Rend, Sunder Armor, the shouts, Concussion Blow, Death Wish, Disarm, Retaliation, Shield Block.
+    WARRIOR = { 78, 845, 1240193, 5308, 7384, 12294, 23881, 1680, 23922, 6572, 6343, 1715, 20252, 694, 6552, 72, 1310222 },
+    -- set 8, masks 100794910 / 2097408 / 0: Ambush, Backstab, Eviscerate, Ghostly Strike, Gouge, Hemorrhage, Kick,
+    -- Mutilate, Riposte, Sinister Strike
+    ROGUE = { 8676, 53, 2098, 14278, 1776, 16511, 1766, 1310707, 14251, 1752 },
+    -- set 3, masks 549591799 / 4096 / 0: Arcane Blast, Arcane Explosion, Arcane Missiles, Blast Wave, Blizzard, Cone of
+    -- Cold, Fire Blast (both), Fireball, Flamestrike, Frost Nova, Frostbolt, Frostfire Bolt, Ice Lance, Pyroblast, Scorch
+    MAGE = { 400574, 1449, 5143, 11113, 10, 120, 2136, 400618, 133, 2120, 122, 116, 401502, 1312002, 11366, 2948 },
+    -- set 5, masks 541165 / 8650880 / 0: Conflagrate, Death Coil, Drain Life (both), Drain Soul, Hellfire, Immolate,
+    -- Rain of Fire, Searing Pain, Shadow Bolt, Shadowburn, Soul Fire, Wrack
+    WARLOCK = { 1293817, 6789, 689, 403677, 1120, 1949, 348, 5740, 5676, 686, 17877, 6353, 1316697 },
+    -- set 6, masks 150224528 / 8388614 / 0: Binding Heal, Flash Heal, Greater Heal, Heal, Holy Fire, Holy Nova, Lesser
+    -- Heal, Mana Burn, Mind Blast, Mind Flay, Penance, Prayer of Healing, Shadow Word: Death (both), Smite, Starshards
+    PRIEST = { 401937, 2061, 2060, 2054, 14914, 15237, 2050, 8129, 8092, 15407, 402174, 596, 401955, 1309595, 585, 10797 },
+}
+
 race:RegisterAbility( "eureka", {
     id = 1259813,
     copy = EUREKA,
@@ -35,20 +65,38 @@ race:RegisterAura( "eureka", {
     max_stack = 3,
 } )
 
+race:RegisterAbility( "escape_artist", {
+    id = 20589,
+    cast = 0,
+    cooldown = 120,
+    gcd = "spell",
+    startsCombat = false,
+    toggle = "defensives",
+
+    handler = function ()
+        applyBuff( "escape_artist" )
+    end,
+    now = function ()
+        applyBuff( "escape_artist" )
+    end,
+} )
+
+race:RegisterAura( "escape_artist", {
+    id = 20589,
+    duration = 3,
+    max_stack = 1,
+} )
+
 race:RegisterResourceMod( { max = 0.05 } ) -- Expansive Mind: +5% maximum resources
 
-race:RegisterCostMod( {
-    aura = "eureka",
-    pct = -0.10,
-    charges = 3,
-    -- Eureka! 1259813 effect 0: aura 108 (ADD_PCT_MODIFIER) misc 14 (cost) -10, class masks
-    -- 1784679630 / 5 / 1 / 0 against SpellClassSet 4 (Warrior). Other classes: append their IDs from
-    -- select distinct o.SpellID, n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID
-    --   join SpellPower p on p.SpellID=o.SpellID where o.SpellClassSet=<set> and p.ManaCost>0 and not
-    --   ((o.SpellClassMask_0 & 1784679630)=0 and (o.SpellClassMask_1 & 5)=0 and (o.SpellClassMask_2 & 1)=0)
-    -- Warrior: heroic_strike, cleave, slam, execute, overpower, mortal_strike, bloodthirst, whirlwind, shield_slam,
-    -- revenge, thunder_clap, hamstring, intercept, mocking_blow, pummel, shield_bash, spearing_strike (rank 1 IDs;
-    -- higher ranks resolve through the class's `copy` lists). Not: rend, sunder_armor, the shouts, concussion_blow,
-    -- death_wish, disarm, retaliation, shield_block, sweeping_strikes.
-    spells = { 78, 845, 1240193, 5308, 7384, 12294, 23881, 1680, 23922, 6572, 6343, 1715, 20252, 694, 6552, 72, 1310222 },
-} )
+-- The loaded class's scope (Classes.lua sets class.file before any race file runs); a class with no Eureka! (none
+-- exists for a Hunter, Shaman, Paladin or Druid) declares no cost modifier.
+local spells = EUREKA_SPELLS[ Hekili.Class.file ]
+if spells then
+    race:RegisterCostMod( {
+        aura = "eureka",
+        pct = -0.10,
+        charges = 3,
+        spells = spells,
+    } )
+end
diff --git a/Forever/Races/NightElf.lua b/Forever/Races/NightElf.lua
index 2f8d2a32..72097b05 100644
--- a/Forever/Races/NightElf.lua
+++ b/Forever/Races/NightElf.lua
@@ -1,8 +1,10 @@
 -- Forever/Races/NightElf.lua
--- The Night Elf's Forever racial (DB2 1.60.1.70338), for every class: Elune's Light (1259799: +10% critical strike
--- chance with spells and attacks, aura 290 base 10, for 15 s; 180 s, off the GCD). Shadowmeld stays Hekili's stock
--- racial (`all`); Quickness and Wisp Spirit are passives. No resource or cost modifier. No pack names it: a race
--- ability is absent for other races; a player adds it to a priority if wanted. Inert for any other race (Races.lua).
+-- The Night Elf's Forever racials (DB2 1.60.1.70338), for every class: Elune's Light (1259799: +10% critical strike
+-- chance with spells and attacks, aura 290 base 10, for 15 s; 180 s, off the GCD) and Shadowmeld, which replaces
+-- `all`'s stock entry (58984, absent on Forever): 20580, no cooldown of its own but a 10 s category recovery (871),
+-- off the GCD, the stealth aura 20580 until cancelled. Quickness and Wisp Spirit are passives. No resource or cost
+-- modifier. No pack names either: a race ability is absent for other races; a player adds it to a priority if wanted.
+-- Inert for any other race (Races.lua).
 
 local addon, ns = ...
 local Hekili = _G[ addon ]
@@ -31,3 +33,31 @@ race:RegisterAura( "elunes_light", {
     duration = 15,
     max_stack = 1,
 } )
+
+race:RegisterAbility( "shadowmeld", {
+    id = 20580,
+    cast = 0,
+    cooldown = 10,
+    gcd = "off",
+    startsCombat = false,
+
+    -- `all`'s gate, kept
+    usable = function ()
+        if not boss or solo then return false, "requires boss fight or group (to avoid resetting)" end
+        if moving then return false, "can't shadowmeld while moving" end
+        return true
+    end,
+
+    handler = function ()
+        applyBuff( "shadowmeld" )
+    end,
+    now = function ()
+        applyBuff( "shadowmeld" )
+    end,
+} )
+
+race:RegisterAura( "shadowmeld", {
+    id = 20580,
+    duration = 3600, -- until cancelled (DB2 -1), as `all`'s
+    max_stack = 1,
+} )
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `276 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [276 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 87 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 54 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Forever/Races/Gnome.lua Forever/Races/NightElf.lua Virtual/State/spec/races_spec.lua
git commit -m "feat(forever): Gnome Eureka! scope per class and Escape Artist; Night Elf Shadowmeld 20580 over all's 58984

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-races`

---

### Task 2: Human and Dwarf race packs

Spec §2 (Human, Dwarf), §3 (Will to Survive, Stoneform rows). `Human.lua`: Will to Survive 1259718 (180 s, on the GCD, no `handler` or `now`) over `all`'s 59752, and Perception 20600 (180 s, on the GCD, aura 20 s). `Dwarf.lua`: Stoneform 20594 at 180 s on the GCD over `all`'s 120 s off-GCD entry, its aura 20594 for 8 s over `all`'s 65116, `all`'s `buff` gate over Forever's three dispels (poison, disease, bleed) from a file-level list, the three `removeBuff` lines inline in `handler` and `now`.

**Files:**
- Create: `Forever/Races/Human.lua`, `Forever/Races/Dwarf.lua`
- Modify: `Hekili.toc` (after `Forever\Races\Tauren.lua`)
- Test: `Virtual/State/spec/races_spec.lua`

**Interfaces:**
- Consumes: `Hekili:NewRace` (Races.lua).
- Produces: `will_to_survive`, `perception`, `stoneform` and their auras in `all` for their races.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Virtual/State/spec/races_spec.lua b/Virtual/State/spec/races_spec.lua
index 71559fe6..d3b19557 100644
--- a/Virtual/State/spec/races_spec.lua
+++ b/Virtual/State/spec/races_spec.lua
@@ -26,6 +26,8 @@ local OWN = {
     Gnome = { { "escape_artist", "eureka" }, 1, 1 },
     NightElf = { { "elunes_light", "shadowmeld" }, 0, 0 },
     Tauren = { { "war_stomp" }, 0, 0 },
+    Human = { { "perception", "will_to_survive" }, 0, 0 },
+    Dwarf = { { "stoneform" }, 0, 0 },
 }
 
 describe("race packs", function()
@@ -273,6 +275,23 @@ describe("race packs", function()
         assert.are.same({ 20580, 20580 }, { class.abilities.shadowmeld.id, class.auras.shadowmeld.id })
     end)
 
+    it("registers Will to Survive 1259718 and Stoneform 20594 (180 s, on the GCD) over `all`'s stale entries", function()
+        local wts, stone = { id = 59752, gcd = "off" }, { id = 20594, cooldown = 120, gcd = "off" }
+        load("Human", { will_to_survive = wts, [59752] = wts })
+        local w = all.abilities.will_to_survive
+        assert.are.same({ 1259718, 180, "spell", "defensives" }, { w.id, w.cooldown, w.gcd, w.toggle })
+        assert.is_nil(w.handler or w.now) -- a stun removal: nothing to model beyond its cooldown and GCD
+        assert.are.same({ 20600, 180, "spell" }, { all.abilities.perception.id, all.abilities.perception.cooldown, all.abilities.perception.gcd })
+        assert.are.same({ 20600, 20 }, { all.auras.perception.id, all.auras.perception.duration })
+        load("Dwarf", { stoneform = stone, [20594] = stone })
+        local s = all.abilities.stoneform
+        assert.are.same({ 20594, 180, "spell", "defensives" }, { s.id, s.cooldown, s.gcd, s.toggle })
+        assert.are.same({ 20594, 8 }, { all.auras.stoneform.id, all.auras.stoneform.duration }) -- not 65116
+        local class = { abilities = { stoneform = stone }, auras = { stoneform = { id = 65116 } } }
+        ns.applyRace(class)
+        assert.are.same({ 180, 20594 }, { class.abilities.stoneform.cooldown, class.auras.stoneform.id })
+    end)
+
     it("takes a class file's spec:RegisterCostMod (Classes.lua) into the same list, for any race", function()
         load("Human")
         -- the mixin's entry as Classes.lua declares it, compiled with this `ns` as its upvalue
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `275 successes / 2 failures / 0 errors` (the TOC/`OWN` case: Human and Dwarf are in `OWN`, not in the TOC; the override case: nothing registered).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/Races/Dwarf.lua b/Forever/Races/Dwarf.lua
new file mode 100644
index 00000000..480c516b
--- /dev/null
+++ b/Forever/Races/Dwarf.lua
@@ -0,0 +1,55 @@
+-- Forever/Races/Dwarf.lua
+-- The Dwarf's Forever racial (DB2 1.60.1.70338), for every class: Stoneform (20594: -10% physical damage taken,
+-- removes poison, disease and bleed effects and grants immunity to them for 8 s; 180 s, on the GCD), which replaces
+-- `all`'s stock entry (120 s, off the GCD, its buff 65116 absent on Forever: the buff is 20594 itself). Kept from
+-- `all`: usable only while a dispellable effect it removes is up. Find Treasure, Mace Specialization and Big Game
+-- Hunter have no rotation effect. No resource or cost modifier. No pack names it. Inert for any other race (Races.lua).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local race = Hekili:NewRace( "Dwarf" )
+
+local CLEARS = { "dispellable_poison", "dispellable_disease", "dispellable_bleed" } -- Stoneform's dispels on Forever
+
+race:RegisterAbility( "stoneform", {
+    id = 20594,
+    cast = 0,
+    cooldown = 180,
+    gcd = "spell",
+    startsCombat = false,
+    toggle = "defensives",
+
+    -- the effect with the longest remaining time (Hekili's ability `buff`: usable only while it is up)
+    buff = function ()
+        local aura, remains = CLEARS[ 1 ], buff[ CLEARS[ 1 ] ].remains
+        for i = 2, #CLEARS do
+            local rem = buff[ CLEARS[ i ] ].remains
+            if rem > remains then
+                aura = CLEARS[ i ]
+                remains = rem
+            end
+        end
+        return aura
+    end,
+
+    handler = function ()
+        removeBuff( "dispellable_poison" )
+        removeBuff( "dispellable_disease" )
+        removeBuff( "dispellable_bleed" )
+        applyBuff( "stoneform" )
+    end,
+    -- VirtualState's now-state of the cast (event-facade spec §12a)
+    now = function ()
+        removeBuff( "dispellable_poison" )
+        removeBuff( "dispellable_disease" )
+        removeBuff( "dispellable_bleed" )
+        applyBuff( "stoneform" )
+    end,
+} )
+
+race:RegisterAura( "stoneform", {
+    id = 20594,
+    duration = 8,
+    max_stack = 1,
+} )
diff --git a/Forever/Races/Human.lua b/Forever/Races/Human.lua
new file mode 100644
index 00000000..388c2392
--- /dev/null
+++ b/Forever/Races/Human.lua
@@ -0,0 +1,44 @@
+-- Forever/Races/Human.lua
+-- The Human's Forever racials (DB2 1.60.1.70338), for every class: Will to Survive (1259718: removes stun effects;
+-- 180 s, on the GCD), which replaces `all`'s stock entry (59752, absent on Forever), and Perception (20600: stealth
+-- detection for 20 s; 180 s, on the GCD). Will to Survive leaves no aura and no resource: no `handler` or `now`, its
+-- cooldown and GCD are the declared fields'. The Human Spirit (+5% Spirit) and Sword Specialization (+2% crit with a
+-- sword) are passives on stats the game reports. No resource or cost modifier. No pack names either. Inert for any
+-- other race (Races.lua).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local race = Hekili:NewRace( "Human" )
+
+race:RegisterAbility( "will_to_survive", {
+    id = 1259718,
+    cast = 0,
+    cooldown = 180,
+    gcd = "spell",
+    startsCombat = false,
+    toggle = "defensives",
+} )
+
+race:RegisterAbility( "perception", {
+    id = 20600,
+    cast = 0,
+    cooldown = 180,
+    gcd = "spell",
+    startsCombat = false,
+    toggle = "defensives",
+
+    handler = function ()
+        applyBuff( "perception" )
+    end,
+    -- VirtualState's now-state of the cast (event-facade spec §12a)
+    now = function ()
+        applyBuff( "perception" )
+    end,
+} )
+
+race:RegisterAura( "perception", {
+    id = 20600,
+    duration = 20,
+    max_stack = 1,
+} )
diff --git a/Hekili.toc b/Hekili.toc
index 7d5efb14..eff11db9 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -57,6 +57,8 @@ Forever\Classes\Druid.lua
 Forever\Races\Gnome.lua
 Forever\Races\NightElf.lua
 Forever\Races\Tauren.lua
+Forever\Races\Human.lua
+Forever\Races\Dwarf.lua
 
 Targets.lua
 Options\DevTools.lua
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `279 successes / 0 failures / 0 errors` (the override case, and one strict-context case per new token).

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [279 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 89 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 56 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Forever/Races/Human.lua Forever/Races/Dwarf.lua Hekili.toc Virtual/State/spec/races_spec.lua
git commit -m "feat(forever): Human and Dwarf race packs: Will to Survive, Perception, Stoneform over all's stale entries

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-races`

---

### Task 3: Orc and Troll race packs

Spec §2 (Orc, Troll), §3 (Blood Fury, Berserking rows). `Orc.lua`: Blood Fury `id = 20572` for every class (no `bf_classes`, no `copy`) over `all`'s ID function, its aura 20572 for 15 s registered so the race owns it, and Shatter Curse 1299026 (180 s, on the GCD; removes `dispellable_curse`, aura 8 s). `Troll.lua`: Berserking 20554 (180 s, off the GCD) and its aura (10 s) over `all`'s 26297, and Rapid Regeneration 1260270 (180 s, off the GCD, aura 6 s).

**Files:**
- Create: `Forever/Races/Orc.lua`, `Forever/Races/Troll.lua`
- Modify: `Hekili.toc` (after `Forever\Races\Dwarf.lua`)
- Test: `Virtual/State/spec/races_spec.lua`

**Interfaces:**
- Consumes: `Hekili:NewRace` (Races.lua).
- Produces: `blood_fury`, `shatter_curse`, `berserking`, `rapid_regeneration` and their auras in `all` for their races.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Virtual/State/spec/races_spec.lua b/Virtual/State/spec/races_spec.lua
index d3b19557..e0d3806c 100644
--- a/Virtual/State/spec/races_spec.lua
+++ b/Virtual/State/spec/races_spec.lua
@@ -28,6 +28,8 @@ local OWN = {
     Tauren = { { "war_stomp" }, 0, 0 },
     Human = { { "perception", "will_to_survive" }, 0, 0 },
     Dwarf = { { "stoneform" }, 0, 0 },
+    Orc = { { "blood_fury", "shatter_curse" }, 0, 0 },
+    Troll = { { "berserking", "rapid_regeneration" }, 0, 0 },
 }
 
 describe("race packs", function()
@@ -292,6 +294,31 @@ describe("race packs", function()
         assert.are.same({ 180, 20594 }, { class.abilities.stoneform.cooldown, class.auras.stoneform.id })
     end)
 
+    it("registers Blood Fury 20572 for every class and Berserking 20554 over `all`'s stale entries", function()
+        local fury = { id = function() end, copy = { 33702, 20572, 33697 } }
+        for _, class in ipairs({ "WARRIOR", "MAGE", "SHAMAN", "DRUID" }) do
+            load("Orc", { blood_fury = fury, [33702] = fury, [20572] = fury, [33697] = fury }, class)
+            local b = all.abilities.blood_fury
+            assert.are.same({ 20572, 120, "off", "cooldowns" }, { b.id, b.cooldown, b.gcd, b.toggle }, class)
+            assert.are.equal(b, all.abilities[20572])
+        end
+        assert.are.same({ 20572, 15 }, { all.auras.blood_fury.id, all.auras.blood_fury.duration })
+        local sc = all.abilities.shatter_curse
+        assert.are.same({ 1299026, 180, "spell", "defensives" }, { sc.id, sc.cooldown, sc.gcd, sc.toggle })
+        assert.are.same({ 1299026, 8 }, { all.auras.shatter_curse.id, all.auras.shatter_curse.duration })
+        local zerk = { id = 26297 }
+        load("Troll", { berserking = zerk, [26297] = zerk })
+        local z = all.abilities.berserking
+        assert.are.same({ 20554, 180, "off", "cooldowns" }, { z.id, z.cooldown, z.gcd, z.toggle })
+        assert.are.same({ 20554, 10 }, { all.auras.berserking.id, all.auras.berserking.duration })
+        local rr = all.abilities.rapid_regeneration
+        assert.are.same({ 1260270, 180, "off", "defensives" }, { rr.id, rr.cooldown, rr.gcd, rr.toggle })
+        assert.are.same({ 1260270, 6 }, { all.auras.rapid_regeneration.id, all.auras.rapid_regeneration.duration })
+        local class = { abilities = { berserking = zerk }, auras = { berserking = { id = 26297 } } }
+        ns.applyRace(class)
+        assert.are.same({ 20554, 20554 }, { class.abilities.berserking.id, class.auras.berserking.id })
+    end)
+
     it("takes a class file's spec:RegisterCostMod (Classes.lua) into the same list, for any race", function()
         load("Human")
         -- the mixin's entry as Classes.lua declares it, compiled with this `ns` as its upvalue
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `278 successes / 2 failures / 0 errors` (the TOC/`OWN` case; the override case).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/Races/Orc.lua b/Forever/Races/Orc.lua
new file mode 100644
index 00000000..138fcbe1
--- /dev/null
+++ b/Forever/Races/Orc.lua
@@ -0,0 +1,59 @@
+-- Forever/Races/Orc.lua
+-- The Orc's Forever racials (DB2 1.60.1.70338), for every class: Blood Fury (20572: +10% attack power and spell power
+-- for 15 s; 120 s, off the GCD), one ID for every class, which replaces `all`'s stock entry (its per-class IDs 33702
+-- and 33697 are absent on Forever; its aura, 20572 for 15 s, is right but registered here too, so the race owns it),
+-- and Shatter Curse (1299026: removes curses, -15% magic damage taken and immunity to curses for 8 s; 180 s, on the
+-- GCD). Hardiness (-20% stun duration) and Axe Specialization (+1% crit with an axe) are passives. No resource or cost
+-- modifier. No pack names either. Inert for any other race (Races.lua).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local race = Hekili:NewRace( "Orc" )
+
+race:RegisterAbility( "blood_fury", {
+    id = 20572,
+    cast = 0,
+    cooldown = 120,
+    gcd = "off",
+    startsCombat = false,
+    toggle = "cooldowns",
+
+    handler = function ()
+        applyBuff( "blood_fury", 15 )
+    end,
+    -- VirtualState's now-state of the cast (event-facade spec §12a)
+    now = function ()
+        applyBuff( "blood_fury", 15 )
+    end,
+} )
+
+race:RegisterAura( "blood_fury", {
+    id = 20572,
+    duration = 15,
+    max_stack = 1,
+} )
+
+race:RegisterAbility( "shatter_curse", {
+    id = 1299026,
+    cast = 0,
+    cooldown = 180,
+    gcd = "spell",
+    startsCombat = false,
+    toggle = "defensives",
+
+    handler = function ()
+        removeBuff( "dispellable_curse" )
+        applyBuff( "shatter_curse" )
+    end,
+    now = function ()
+        removeBuff( "dispellable_curse" )
+        applyBuff( "shatter_curse" )
+    end,
+} )
+
+race:RegisterAura( "shatter_curse", {
+    id = 1299026,
+    duration = 8,
+    max_stack = 1,
+} )
diff --git a/Forever/Races/Troll.lua b/Forever/Races/Troll.lua
new file mode 100644
index 00000000..41ebca94
--- /dev/null
+++ b/Forever/Races/Troll.lua
@@ -0,0 +1,57 @@
+-- Forever/Races/Troll.lua
+-- The Troll's Forever racials (DB2 1.60.1.70338), for every class: Berserking (20554: +10% attack and casting speed
+-- for 10 s, one flat value, no health scaling; 180 s, off the GCD), which replaces `all`'s stock entry and aura
+-- (26297, absent on Forever), and Rapid Regeneration (1260270: heals 50% of maximum health over 6 s, cancelled by
+-- movement, action or damage; 180 s, off the GCD). The haste itself is the game's (Hekili reads haste); a priority
+-- reads `buff.berserking.up`. Regeneration and Beast Slaying are passives. No resource or cost modifier. No pack names
+-- either. Inert for any other race (Races.lua).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local race = Hekili:NewRace( "Troll" )
+
+race:RegisterAbility( "berserking", {
+    id = 20554,
+    cast = 0,
+    cooldown = 180,
+    gcd = "off",
+    startsCombat = false,
+    toggle = "cooldowns",
+
+    handler = function ()
+        applyBuff( "berserking" )
+    end,
+    -- VirtualState's now-state of the cast (event-facade spec §12a)
+    now = function ()
+        applyBuff( "berserking" )
+    end,
+} )
+
+race:RegisterAura( "berserking", {
+    id = 20554,
+    duration = 10,
+    max_stack = 1,
+} )
+
+race:RegisterAbility( "rapid_regeneration", {
+    id = 1260270,
+    cast = 0,
+    cooldown = 180,
+    gcd = "off",
+    startsCombat = false,
+    toggle = "defensives",
+
+    handler = function ()
+        applyBuff( "rapid_regeneration" )
+    end,
+    now = function ()
+        applyBuff( "rapid_regeneration" )
+    end,
+} )
+
+race:RegisterAura( "rapid_regeneration", {
+    id = 1260270,
+    duration = 6,
+    max_stack = 1,
+} )
diff --git a/Hekili.toc b/Hekili.toc
index eff11db9..dcb23800 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -59,6 +59,8 @@ Forever\Races\NightElf.lua
 Forever\Races\Tauren.lua
 Forever\Races\Human.lua
 Forever\Races\Dwarf.lua
+Forever\Races\Orc.lua
+Forever\Races\Troll.lua
 
 Targets.lua
 Options\DevTools.lua
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `282 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [282 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 91 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 58 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Forever/Races/Orc.lua Forever/Races/Troll.lua Hekili.toc Virtual/State/spec/races_spec.lua
git commit -m "feat(forever): Orc and Troll race packs: Blood Fury 20572 for every class, Shatter Curse, Berserking 20554, Rapid Regeneration

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-races`

---

### Task 4: Undead race pack (token `Scourge`); the Skyborne decision

Spec §1 (Skyborne: no file, the deferred note stands; nothing to build), §2 (Undead), §5. `Undead.lua` answers `Hekili:NewRace( "Scourge" )` (the retail token, assumed; Q1 confirms) and registers Will of the Forsaken 7744 (120 s, on the GCD, no `handler` or `now`) and Cannibalize 20577 (120 s, on the GCD) with its heal aura under the key `cannibalize` and ID 20578 for 10 s. Touch of the Grave is not modelled (spec §2). `races_spec`'s `TOKEN` already maps `Undead` to `Scourge` (Task 1).

**Files:**
- Create: `Forever/Races/Undead.lua`
- Modify: `Hekili.toc` (after `Forever\Races\Troll.lua`)
- Test: `Virtual/State/spec/races_spec.lua`

**Interfaces:**
- Consumes: `Hekili:NewRace` (Races.lua).
- Produces: `will_of_the_forsaken`, `cannibalize` and the `cannibalize` aura in `all` for the `Scourge` token.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Virtual/State/spec/races_spec.lua b/Virtual/State/spec/races_spec.lua
index e0d3806c..d582e290 100644
--- a/Virtual/State/spec/races_spec.lua
+++ b/Virtual/State/spec/races_spec.lua
@@ -30,6 +30,7 @@ local OWN = {
     Dwarf = { { "stoneform" }, 0, 0 },
     Orc = { { "blood_fury", "shatter_curse" }, 0, 0 },
     Troll = { { "berserking", "rapid_regeneration" }, 0, 0 },
+    Undead = { { "cannibalize", "will_of_the_forsaken" }, 0, 0 },
 }
 
 describe("race packs", function()
@@ -319,6 +320,17 @@ describe("race packs", function()
         assert.are.same({ 20554, 20554 }, { class.abilities.berserking.id, class.auras.berserking.id })
     end)
 
+    it("registers Will of the Forsaken and Cannibalize for the Scourge token, not for `Undead`", function()
+        load("Undead")
+        assert.is_nil(all.abilities.cannibalize)
+        load("Scourge")
+        local w, c = all.abilities.will_of_the_forsaken, all.abilities.cannibalize
+        assert.are.same({ 7744, 120, "spell", "defensives" }, { w.id, w.cooldown, w.gcd, w.toggle })
+        assert.is_nil(w.handler or w.now) -- nothing to model beyond its cooldown and GCD
+        assert.are.same({ 20577, 120, "spell", "defensives" }, { c.id, c.cooldown, c.gcd, c.toggle })
+        assert.are.same({ 20578, 10 }, { all.auras.cannibalize.id, all.auras.cannibalize.duration }) -- the heal's aura
+    end)
+
     it("takes a class file's spec:RegisterCostMod (Classes.lua) into the same list, for any race", function()
         load("Human")
         -- the mixin's entry as Classes.lua declares it, compiled with this `ns` as its upvalue
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `281 successes / 1 failure / 1 error` (the TOC/`OWN` case; the Undead case indexes a nil `will_of_the_forsaken`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/Races/Undead.lua b/Forever/Races/Undead.lua
new file mode 100644
index 00000000..7a9c3bcc
--- /dev/null
+++ b/Forever/Races/Undead.lua
@@ -0,0 +1,45 @@
+-- Forever/Races/Undead.lua
+-- The Undead's Forever racials (DB2 1.60.1.70338), for every class; race token "Scourge" (UnitRace's second return):
+-- Will of the Forsaken (7744: removes charm, fear and sleep, immune for 0.1 s; 120 s, on the GCD), whose cast leaves
+-- nothing to model beyond its cooldown and GCD (no `handler` or `now`), and Cannibalize (20577: heals 7% of maximum
+-- health and mana every 2 s for 10 s through its aura 20578, near a corpse; 120 s, on the GCD; whether a corpse is near
+-- is not known, a priority gates it). Touch of the Grave (1260189 Warrior/Paladin/Rogue, 1260201 Priest/Mage/Warlock: a
+-- proc that drains health) and Underwater Breathing are passives with no rotation effect. No resource or cost modifier.
+-- No pack names either. Inert for any other race (Races.lua).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local race = Hekili:NewRace( "Scourge" )
+
+race:RegisterAbility( "will_of_the_forsaken", {
+    id = 7744,
+    cast = 0,
+    cooldown = 120,
+    gcd = "spell",
+    startsCombat = false,
+    toggle = "defensives",
+} )
+
+race:RegisterAbility( "cannibalize", {
+    id = 20577,
+    cast = 0,
+    cooldown = 120,
+    gcd = "spell",
+    startsCombat = false,
+    toggle = "defensives",
+
+    handler = function ()
+        applyBuff( "cannibalize" )
+    end,
+    -- VirtualState's now-state of the cast (event-facade spec §12a)
+    now = function ()
+        applyBuff( "cannibalize" )
+    end,
+} )
+
+race:RegisterAura( "cannibalize", {
+    id = 20578,
+    duration = 10,
+    max_stack = 1,
+} )
diff --git a/Hekili.toc b/Hekili.toc
index dcb23800..7aa3aee2 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -61,6 +61,7 @@ Forever\Races\Human.lua
 Forever\Races\Dwarf.lua
 Forever\Races\Orc.lua
 Forever\Races\Troll.lua
+Forever\Races\Undead.lua
 
 Targets.lua
 Options\DevTools.lua
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `284 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [284 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 92 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 59 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Forever/Races/Undead.lua Hekili.toc Virtual/State/spec/races_spec.lua
git commit -m "feat(forever): Undead race pack (token Scourge): Will of the Forsaken and Cannibalize

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-races`

---

### Task 5: CHECKPOINT: tokens first, then the racials in game

No code. `Hekili.toc` lists five new files since the client last loaded a branch: a full client restart. ForeverProbe loaded. Run on every character the user has (at least one per race the user plays); Q1 first on each.

- [ ] **Step 1: Point the client at the branch**

```bash
git push origin forever-races
git -C ~/src/hekili checkout --detach forever-races
```

- [ ] **Step 2: Check the lines' lengths** (every line under 255 characters):

```bash
grep '^/run ' docs/superpowers/plans/2026-10-15-forever-races.md | awk 'length >= 255 { print "too long: " $0; bad = 1 } END { print NR " lines"; exit bad }'   # [9 lines]
```

- [ ] **Step 3: CHECKPOINT: stop and ask the user to run the following in game, and report each box**

```text
Q1 (tokens; first, on every character):
/run VSCopy(UnitRace("player"),select(2,UnitRace("player")),UnitClassBase("player"),Hekili.State.race_token,#Hekili.RaceMods.maxMods,#Hekili.RaceMods.costMods)
Q2 (the stale stock IDs):
/run local f=function(i) return tostring(C_Spell.GetSpellInfo(i)~=nil) end VSCopy(f(26297),f(58984),f(59752),f(65116),f(33702),f(33697))
Q3 (the race's entries over all's):
/run local a=Hekili.Class.abilities VSCopy(a.berserking.id,a.blood_fury.id,a.shadowmeld.id,a.will_to_survive.id,a.stoneform.cooldown,a.stoneform.gcd)
Q4 (after casting the race's buff racial):
/run local i=1 while true do local a=C_UnitAuras.GetAuraDataByIndex("player",i,"HELPFUL") if not a then break end VSCopy(a.spellId,a.name,a.duration) i=i+1 end
Q5 (a macro: /cast <racial> on its first line, this on the second; for each racial of the race):
/run local g=C_Spell.GetSpellCooldown(61304) VSCopy(g and g.duration,g and g.startTime,GetTime())
Q6 (Night Elf, after Shadowmeld):
/run local s=C_Spell.GetSpellCooldown(20580) VSCopy(20580,s and s.duration,s and s.startTime,GetTime())
Q7 (racials known):
/run VSCopy(UnitClass("player"),IsPlayerSpell(1260189),IsPlayerSpell(1260201),IsPlayerSpell(20554),IsPlayerSpell(1259718),IsPlayerSpell(20589))
Q8 (Blood Fury's and Wind Blessed's text):
/run VSCopy(C_Spell.GetSpellDescription(20572),C_Spell.GetSpellDescription(1259710))
Q9 (Gnome: Eureka!'s scope):
/run local e=Hekili.RaceMods.costMods[1] VSCopy(e and e.aura,e and #e.spells,Hekili.Class.file)
```

| Answer | → action |
|---|---|
| Q1 token equals the file's `NewRace` argument (spec §5) | none |
| Q1 token differs (e.g. `Undead` for `Scourge`) | a follow-up task: rename that file's `NewRace` argument and `races_spec`'s `TOKEN` entry; re-run the verification block; commit; push |
| Q1 a Skyborne token | record it in spec §1's deferred note (no file this pass) |
| Q1 Gnome counts not `1 1` on a Warrior, Rogue, Mage, Warlock or Priest; or Q9 `nil` there | **stop and report**: `Hekili.Class.file` was not set when `Gnome.lua` ran |
| Q2 all `false` | the overrides are needed as written |
| Q2 any `true` | note the ID; the override stays (the DB2 values are Forever's) |
| Q3 the own race shows spec §2's value (Troll 20554, Orc 20572, Night Elf 20580, Human 1259718, Dwarf 180 and `spell`), others `all`'s | none |
| Q3 the own race shows `all`'s stale value | **stop and report**: `ns.applyRace` did not write the race's entry |
| Q4 aura ID and duration as spec §2 | none |
| Q4 a different aura ID | a follow-up task: that aura's `id` in the race file and its spec case |
| Q5 GCD 1.5 for spec §2's `spell` racials, 0 for the `off` ones | none |
| Q5 otherwise | a follow-up task: flip that ability's `gcd` and its spec case |
| Q6 10 | none |
| Q6 another value | a follow-up task: Shadowmeld's `cooldown` |
| Q7 a `false` for the own race's racial | note it in spec §8 (race/class availability) |
| Q8 | notes only (neither is modelled) |

When the session ends: `git -C ~/src/hekili checkout forever`.

---

## Self-Review

| Spec section | Task |
|---|---|
| §1 one file per Classic race; Tauren unchanged; Skyborne deferred | Tasks 1-4; Task 4 (decision) |
| §2 registrations, GCD rule, Expansive Mind, Touch of the Grave not modelled | Tasks 1-4 |
| §3 override rule and the eight stale rows | Task 1 (Shadowmeld x2), Task 2 (Will to Survive, Stoneform x2), Task 3 (Blood Fury, Berserking x2) |
| §4 Eureka! lists keyed by class file, no modifier without a list | Task 1 |
| §5 tokens, `Scourge` | Task 4; Task 5 Q1 |
| §6 tests: inert, own keys, strict context, 0 bytes, RaceMods counts | Task 1 (and each task's `OWN` rows) |
| §7 checkpoint | Task 5 |
| §8 not modelled | the race files' headers |
