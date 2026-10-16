# Forever Shared Content Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The shared `all` spec holds only what exists and is observable on Forever: the engine (`Classes.lua`, renamed `Engine/Spec.lua`) keeps the mixin, `all`'s creation with the keys core reads by name, and SpecializationChanged's merge; shared game content moves to `Forever/Shared/{Auras,Consumables,Items}.lua` through a new `Hekili:NewShared()`; retail's dead lusts, lockouts, racials, target reads, potions and helpers are dropped, with a test that no priority, class, race, engine or shared file names a dropped key; and the GCD is asked as Forever's own spell (one constant) at every core site, the facade's 61304 remap gone.

**Architecture:** Task 1 is mechanical: `git mv` of `Classes.lua` to `Engine/Spec.lua` and `Races.lua` to `Engine/Races.lua` (every path, comment and the TOC follow) and `Engine/Shared.lua`, whose `Hekili:NewShared()` returns an always-live object with the race object's four calls writing into `all` and `ns.raceMods`. Task 2 names the GCD by `I.GCD_SPELL` (29515, `Virtual/State/Sources/Spellbook.lua`) at the five core sites as `ns.VirtualStateInternal.GCD_SPELL`, deletes the facade's remap, and turns `C_Spell.GetSpellInfo`/`GetSpellTexture` into passthroughs. Task 3 moves the external player auras (lust with the 1245940 candidate, Power Infusion at Forever's 15 s, the seven loss-of-control generators, the dispellable debuffs with `dispellable_magic`'s target half dropped) and four id-less stubs for the keys State.lua reads by name into `Forever/Shared/Auras.lua`, and drops the rest of `all`'s auras and racials. Task 4 moves the `potion` verb and auras (no retail default item) and a Forever Healthstone into `Consumables.lua`, and removes Core.lua's `tempered_potion` fallback (named core edit E1). Task 5 moves `use_items`, the trinket and main-hand slot actions, `null_cooldown` and `class.trinkets` into `Items.lua` and drops the dead item-settings helpers. Task 6 is the in-game checkpoint.

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, `lua5.1`/`luac5.1`, the Forever DB2 through `~/.local/share/wow-db2/bin/wowdb` (build 1.60.1.70338).

**Spec:** `docs/superpowers/specs/2026-10-15-forever-shared-content.md` (binding; §2 the rule, §4 the per-family tables, §5 the GCD constant, §6 named core edits E1/E2, §7 the checkpoint Q0-Q8, §9 not modelled). Read with it: `docs/dev/layout.md` (the repository layout), the race spec `docs/superpowers/specs/2026-10-15-forever-races.md` (the race object and the `now` convention this pass reuses), the event-facade spec `docs/superpowers/specs/2026-10-15-virtualstate-event-facade.md` (decision 7, reversed here for the GCD only).

## How this plan was checked

Every patch below was written and run before the plan was saved, in a scratch clone of the worktree at `a414b73c` (`forever-shared`: the standard-layout commit): Tasks 1 to 5 in order, each spec patch applied and run red, then the implementation patch and the whole verification block. Then every patch was extracted again from this markdown and the whole plan replayed from `a414b73c` in a fresh clone: per task the spec patch run red, the implementation patch, the verification block, `git add` with exactly the task's file list, a commit, and an empty `git status` after it; the counts below are that replay's. The base counts at `a414b73c`: 286 busted successes, luacheck 0 warnings in 92 files, `tools/check_api_reads.sh` 59 loaded files, the inventory diff empty, LuaLS no problems. The Healthstone items, their spells and Power Infusion's 15 s were re-read from the DB2 (`wowdb "SELECT ID, Display_lang FROM ItemSparse WHERE Display_lang LIKE '%Healthstone%'"`, `wowdb spell 10060`, `wowdb spell 1245940`). The in-game checkpoint (Task 6) is the user's.

## Global Constraints

- Repository `~/src/hekili`. Work only in the worktree `~/src/hekili/.claude/worktrees/forever-shared`, branch `forever-shared`, at the spec and plan's docs commit (on `a414b73c`) when Task 1 starts. Git from WSL only. After each task's green verification and clean review, push the branch (`git push origin forever-shared`); never push to `forever`, `classic` or any other branch; never force-push. No task merges.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, naming the model that wrote the commit; an implementer on another model replaces `Claude Opus 5.5` with its own model's name.
- No LICENSE or README changes, in any repository. No changes to `archive/` or `src/Hekili/Libs/`.
- Layout (`docs/dev/layout.md`): the addon is `src/Hekili/` (paths in `Hekili.toc` are relative to it), specs mirror it under `tests/`, `tools/` and `docs/` at the root; every tool and `busted` run from the worktree root.
- Secret safety (event-facade spec §8): nothing compares, indexes or does arithmetic on a client value without `issecretvalue()` first, and nothing uses `a and b or c` on a possibly-secret value. Shared content reads the game only through `ns.Facade` (`tools/check_api_reads.sh` enforces it). Moved generators keep their reads (loss of control plain [W PR12, PR18], the player's debuff walk plain); the one new read, `C_Item.GetItemCount` in the Healthstone pick, is plain [W PR13]. A dropped generator that compared a possibly secret value (`all_absorbs`) is not replaced.
- `now` handlers (event-facade spec §12a, the race packs' convention): a `now` only where the cast changes more than its cost, cooldown and GCD. No shared action gets one (spec §4.3: item actions carry no spell ID the belief sees, and a Healthstone's heal is untracked health).
- Performance: no allocation in recurring paths. The Healthstone pick walks a 15-item constant with a numeric `for` (no table, no closure per call); nothing else this plan adds runs per recommendation.
- Moved code is moved verbatim (generators, slot actions, `use_items`, `class.trinkets`); the only rewrites are the ones the spec names (`dispellable_magic`, the `potion` action's default, the Healthstone).
- TOC order (`Hekili.toc`): `Engine\Races.lua` where `Races.lua` was; `Engine\Spec.lua` where `Classes.lua` was, then `Engine\Shared.lua` (Task 1), `Forever\Shared\Auras.lua` (Task 3), `Forever\Shared\Consumables.lua` (Task 4), `Forever\Shared\Items.lua` (Task 5), all before `Forever\Classes\Warrior.lua`, so every race file still loads after every shared file. Moved and added files need a full client restart, not a `/reload`, before the checkpoint.
- Scope: the spec's §3-§8. Not: Forever potions, flasks or food; trinket effects; a lust lockout; target dispels; absorbs; spell range; State.lua edits for the stubbed keys (spec §4.1); the race files' wording; `Options/DevTools.lua`.
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
- Patches are applied with `git apply` from the worktree root, in the order given; each was generated by `git diff` in the replay (Task 1's carries two renames, which `git apply` performs).
- Style: specs and `tools/` use the TDF layout (4 spaces, no spaces inside parentheses); Hekili's own files (`src/Hekili/Engine/*.lua`, `Core.lua`, `UI.lua`, `Events.lua`, `Options/Options.lua`, `Forever/**/*.lua`) keep Hekili's style (spaces inside parentheses); `Virtual/` keeps the TDF layout.
- The user runs the game. A **CHECKPOINT** task stops execution: the orchestrator (not a subagent) pushes the branch, points the client's checkout at it with `git -C ~/src/hekili checkout --detach forever-shared`, asks the user to run the exact lines given, and waits. Every in-game line is under 255 characters (checked by script) and copies its answer through `VSCopy(` (ForeverProbe's copy box, `/vscopy` reopens it; a secret prints `S`): the user cannot copy chat. ForeverProbe (`~/src/ForeverProbe`) is loaded. The AddOns link points at `src/Hekili` (`docs/dev/layout.md`). When the session ends, `git -C ~/src/hekili checkout forever`.

## Review Focus

1. **Task 1 changes no behaviour.** Two `git mv` and comment paths; `Engine/Shared.lua` is loaded but unused until Task 3. Test: the busted count stays 286; `races_spec` reads both moved files by their new paths.
2. **Nothing names a dropped key, and nothing given up is lost.** Task 3 "leaves no dropped key in a priority, a class, race, engine or shared file, and no stub outside its own" (Tasks 4 and 5 extend its list) and "leaves each key `all` gave up registered by its class or race file".
3. **The GCD is one number.** Task 2 "names the GCD by one constant": no file the TOC loads says 61304, `global_cooldown`'s `id` is the constant; the facade counts follow.
4. **No new secret read.** The moved generators are verbatim; `dispellable_magic` reads only the player's debuffs (Task 3's case calls it as a buff with a `UnitBuff` that raises); `all_absorbs` (an unguarded compare on a total unprobed in combat) is gone.
5. **The core still finds every key it reads by name.** `casting`, `movement`, `unknown_buff`, `global_cooldown`, the APL verbs stay in `Engine/Spec.lua`; `bloodlust`, `power_infusion`, the four stubs (Task 3), `potion`/`fake_potion`/`healthstone` (Task 4), `use_items`, `trinket1/2`, `main_hand`, `null_cooldown`, `class.trinkets` (Task 5) each have a registry case.
6. **The shared content loses to the class and to the race.** `NewShared` records no ownership (Task 3's first case), and every shared file loads before the race files (TOC order).

## File structure

```
src/Hekili/Engine/Spec.lua            Task 1  renamed from Classes.lua (header); Task 2 global_cooldown's id; Task 3 auras and
                                              racials out; Task 4 potions and Healthstone out; Task 5 items out, banner
src/Hekili/Engine/Races.lua           Task 1  renamed from Races.lua (header, comment paths)
src/Hekili/Engine/Shared.lua          Task 1  Hekili:NewShared(): RegisterAbility, RegisterAura, RegisterResourceMod, RegisterCostMod
src/Hekili/Forever/Shared/Auras.lua   Task 3  stubs, lust, Power Infusion, loss of control, dispellable debuffs
src/Hekili/Forever/Shared/Consumables.lua  Task 4  fake_potion, the potion alias and verb, the Healthstone
src/Hekili/Forever/Shared/Items.lua   Task 5  use_items, trinket1/2, main_hand, null_cooldown, class.trinkets
src/Hekili/Hekili.toc                 Tasks 1, 3, 4, 5  the Engine and Shared entries
src/Hekili/Core.lua                   Task 4  E1: the potion verb's tempered_potion fallback
src/Hekili/UI.lua, Events.lua, Options/Options.lua  Task 2  E2: the GCD constant
src/Hekili/Virtual/API/Facade.lua     Task 2  the 61304 remap rows out; GetSpellInfo/GetSpellTexture passthroughs
src/Hekili/Virtual/State/Sources/Spellbook.lua  Task 2  I.GCD_SPELL's comment
tools/api_inventory.txt               Task 2  the two classes
.luacheckrc                           Task 1  Engine/Spec.lua's entry; Task 3 Forever/Shared/
tests/Forever/shared_spec.lua         Tasks 3-5  NewShared, the three registries, the key test
tests/Virtual/API/facade_spec.lua     Task 2  the GCD constant case; decision 7's case; the counts
tests/Virtual/State/alloc_spec.lua    Task 2  the 61304 call out
tests/Virtual/State/races_spec.lua, modifiers_spec.lua, tests/Virtual/Events/cleu_rows_spec.lua,
tests/Forever/druid_spec.lua          Task 1  paths and comments (druid_spec's again in Task 5)
src/Hekili/State.lua, Forever/Races/*.lua, Virtual/State/Adapter.lua, Families/Casts.lua, Families/Modifiers.lua
                                      Task 1  comment paths only
```

## Order and checkpoints

Task 1 (the rename, so later patches name the new paths), Task 2 (the GCD, independent of the content), Tasks 3-5 (one shared file each, the key test growing with each), then Task 6, CHECKPOINT: Q0 confirms the load after a full client restart, Q1 (the aura fields) first because its answer can drop a family, then Q2-Q8. An answer that changes code is its own commit with the verification block.

Deliberately not built (a review should not flag them): the State.lua edits that would remove the stubbed reads (spec §4.1 chose stubs); a Forever potion list; a `now` on an item action; a fix of `incapacitated`'s locType; the race headers' "replaces `all`'s stock entry" wording; `Options/DevTools.lua`'s template text.

---
### Task 1: The engine rename and `Hekili:NewShared` (mechanical; counts unchanged)

Spec §3. `src/Hekili/Classes.lua` becomes `src/Hekili/Engine/Spec.lua` and `src/Hekili/Races.lua` becomes `src/Hekili/Engine/Races.lua` (renames with their headers and the paths in comments), `Hekili.toc` lists them in their old places and `Engine\Shared.lua` right after `Engine\Spec.lua`, `.luacheckrc` moves `Classes.lua`'s entry, and every comment and path that named the two files follows (`races_spec` opens both by path). `Engine/Shared.lua` adds `Hekili:NewShared()`: the race object's four calls, always live, into `all` and `ns.raceMods`, with no ownership record (a class wins the merge, a race pack's `ns.applyRace` wins over both). Nothing calls it until Task 3, whose first spec case covers it. No behaviour changes: the count stays 286.

**Files:**
- Rename: `src/Hekili/Classes.lua` → `src/Hekili/Engine/Spec.lua` (header), `src/Hekili/Races.lua` → `src/Hekili/Engine/Races.lua` (header, comment paths)
- Create: `src/Hekili/Engine/Shared.lua`
- Modify: `src/Hekili/Hekili.toc`, `.luacheckrc`, comment paths in `src/Hekili/State.lua`, `src/Hekili/Forever/Races/*.lua`, `src/Hekili/Virtual/State/Adapter.lua`, `Families/Casts.lua`, `Families/Modifiers.lua`
- Test: `tests/Virtual/State/races_spec.lua` (paths), `modifiers_spec.lua`, `tests/Virtual/Events/cleu_rows_spec.lua`, `tests/Forever/druid_spec.lua` (comments)

**Interfaces:**
- Consumes: `Hekili.Class.specs[ 0 ]` (`all`), `ns.raceMods`, `ns.RegisterCostMod` (Engine/Races.lua).
- Produces: `Hekili:NewShared()` → `{ RegisterAbility( key, def ), RegisterAura( key, def ), RegisterResourceMod( { max = pct } ), RegisterCostMod( def ) }`.

- [ ] **Step 1: Apply the rename and `Engine/Shared.lua`**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/.luacheckrc b/.luacheckrc
index 55e046ae..26606f59 100644
--- a/.luacheckrc
+++ b/.luacheckrc
@@ -78,7 +78,7 @@ local stateEnv = {
     "next_ation", "name", "listName", "id", "event", "boss", "alphaCheck", "abilitty", "display", "args", "v", "p",
     "val", "treeToString", "QueueRebuildUI",
 }
-files["src/Hekili/Classes.lua"] = { globals = stateEnv }
+files["src/Hekili/Engine/Spec.lua"] = { globals = stateEnv }
 files["src/Hekili/State.lua"] = { globals = stateEnv }
 files["src/Hekili/Scripts.lua"] = { globals = stateEnv }
 files["src/Hekili/Core.lua"] = { globals = stateEnv }
diff --git a/src/Hekili/Races.lua b/src/Hekili/Engine/Races.lua
similarity index 92%
rename from src/Hekili/Races.lua
rename to src/Hekili/Engine/Races.lua
index 9f550144..a0b67be5 100644
--- a/src/Hekili/Races.lua
+++ b/src/Hekili/Engine/Races.lua
@@ -1,11 +1,11 @@
--- Races.lua
+-- Engine/Races.lua
 -- Race packs (event-facade spec §12b). `Hekili:NewRace( token )` returns a registration object a race file
 -- (Forever/Races/<Race>.lua) uses like a spec: RegisterAbility, RegisterAura, RegisterResourceMod, RegisterCostMod
 -- (a class file declares its own cost modifiers with spec:RegisterCostMod, into the same list).
 -- Registrations count only when the token is the player's race (`state.race_token`, UnitRace's locale-free second
 -- return); otherwise they are accepted and inert, so every race file runs unconditionally and loads headless.
 -- Abilities and auras go to the shared `all` spec (over `all`'s own entry for the same key), and ns.applyRace writes
--- them over the class's after Classes.lua's merge (which takes the class first and only adds missing keys), so a race
+-- them over the class's after Engine/Spec.lua's merge (which takes the class first and only adds missing keys), so a race
 -- registration wins a key clash with the class and with `all`. Resource and cost modifiers go to `ns.raceMods`, one
 -- declaration read by two layers:
 -- VirtualState's belief (Virtual/State/Families/Modifiers.lua, through Adapter.lua) and Hekili's simulation (below).
@@ -33,7 +33,7 @@ local function own( kind, key )
     end
 end
 
---- Classes.lua's SpecializationChanged, after merging the specs: the race's abilities and auras win over the class's.
+--- Engine/Spec.lua's SpecializationChanged, after merging the specs: the race's abilities and auras win over the class's.
 function ns.applyRace( class )
     local spec = all()
     for kind, keys in pairs( owned ) do
@@ -70,7 +70,7 @@ end
 --- { aura = key, pct = n | flat = n, charges = k | nil, spells = { spell IDs } | nil }: an ability whose spell ID (or
 --- one of its `copy` ranks) is listed (every ability paid from the resource when `spells` is nil) costs less while the
 --- aura is up; with charges, each such cast whose declared cost is above 0 takes a stack. Also a class file's
---- `spec:RegisterCostMod` (Classes.lua): the class file has returned for any other class, so its append is the player's.
+--- `spec:RegisterCostMod` (Engine/Spec.lua): the class file has returned for any other class, so its append is the player's.
 function ns.RegisterCostMod( def )
     mods.costMods[ #mods.costMods + 1 ] = def
 end
@@ -147,7 +147,7 @@ function M.Spend( base, key )
     end
 end
 
---- Classes.lua's RegisterAbility: the ability's `spend` answers through the modifiers; `baseSpend` keeps the declared
+--- Engine/Spec.lua's RegisterAbility: the ability's `spend` answers through the modifiers; `baseSpend` keeps the declared
 --- cost (VirtualState's belief applies the same modifiers to it itself).
 -- shortcut: a spend set later (by an ability's onLoad) skips this wrap; no ability does today, wrap there if one does.
 function M.Wrap( a )
diff --git a/src/Hekili/Engine/Shared.lua b/src/Hekili/Engine/Shared.lua
new file mode 100644
index 00000000..c0865a5d
--- /dev/null
+++ b/src/Hekili/Engine/Shared.lua
@@ -0,0 +1,39 @@
+-- Engine/Shared.lua
+-- Shared content (shared-content spec §3). `Hekili:NewShared()` returns a registration object the content files
+-- (Forever/Shared/<File>.lua) use like a race pack's (Engine/Races.lua): RegisterAbility, RegisterAura,
+-- RegisterResourceMod, RegisterCostMod. Always live, for every class and race, into the shared `all` spec, whose entries
+-- the class's own win in the merge (Engine/Spec.lua) and a race pack's replace (ns.applyRace).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local function all()
+    return Hekili.Class.specs[ 0 ]
+end
+
+local Shared = {}
+Shared.__index = Shared
+
+function Shared:RegisterAbility( key, def )
+    all():RegisterAbility( key, def )
+end
+
+function Shared:RegisterAura( key, def )
+    all():RegisterAura( key, def )
+end
+
+--- { max = pct }: every resource the loaded class registered gets pct more maximum (the race object's signature).
+function Shared:RegisterResourceMod( def )
+    if type( def.max ) == "number" then
+        local m = ns.raceMods.maxMods
+        m[ #m + 1 ] = { pct = def.max }
+    end
+end
+
+function Shared:RegisterCostMod( def )
+    ns.RegisterCostMod( def )
+end
+
+function Hekili:NewShared()
+    return setmetatable( {}, Shared )
+end
diff --git a/src/Hekili/Classes.lua b/src/Hekili/Engine/Spec.lua
similarity index 99%
rename from src/Hekili/Classes.lua
rename to src/Hekili/Engine/Spec.lua
index f9c3f52e..9f9fcec7 100644
--- a/src/Hekili/Classes.lua
+++ b/src/Hekili/Engine/Spec.lua
@@ -1,5 +1,7 @@
--- Classes.lua
--- January 2025
+-- Engine/Spec.lua
+-- The spec engine (was Classes.lua): the spec mixin and its Register* API, the shared `all` spec and the keys core reads
+-- by name, and SpecializationChanged's merge. Game content shared by every class lives in Forever/Shared/*.lua
+-- (registered through Engine/Shared.lua) and the race packs.
 
 local addon, ns = ...
 local Facade = ns.Facade
@@ -793,7 +795,7 @@ local HekiliSpecMixin = {
             end
         end
 
-        -- The race packs' cost modifiers in the simulation (Races.lua, event-facade spec §12b).
+        -- The race packs' cost modifiers in the simulation (Engine/Races.lua, event-facade spec §12b).
         ns.costMods.Wrap( a )
 
         if ( a.velocity or a.flightTime ) and a.impact and a.isProjectile == nil then
@@ -1075,7 +1077,7 @@ local HekiliSpecMixin = {
     end,
 
     -- A class's cost modifier (a proc that makes the next abilities cheaper, e.g. Clearcasting): the race object's
-    -- RegisterCostMod signature, into the list both VirtualState's belief and the simulation read (Races.lua).
+    -- RegisterCostMod signature, into the list both VirtualState's belief and the simulation read (Engine/Races.lua).
     RegisterCostMod = function( self, def )
         ns.RegisterCostMod( def )
     end,
@@ -3338,7 +3340,7 @@ function Hekili:SpecializationChanged()
         end
     end
 
-    -- The race pack's abilities and auras win a key clash with the class's and `all`'s (Races.lua, spec §12b).
+    -- The race pack's abilities and auras win a key clash with the class's and `all`'s (Engine/Races.lua, spec §12b).
     ns.applyRace( class )
 
     for k in pairs( class.abilityList ) do
diff --git a/src/Hekili/Forever/Races/Dwarf.lua b/src/Hekili/Forever/Races/Dwarf.lua
index 4be717dc..2106b880 100644
--- a/src/Hekili/Forever/Races/Dwarf.lua
+++ b/src/Hekili/Forever/Races/Dwarf.lua
@@ -5,7 +5,7 @@
 -- `all`: usable only while a dispellable effect it removes is up. No `dispellable_bleed` aura exists in `all`: the gate
 -- covers poison and disease until one does (the bleed lines stay, as Forever's real dispel). Find Treasure, Mace
 -- Specialization and Big Game Hunter have no rotation effect. No resource or cost modifier. No pack names it. Inert for
--- any other race (Races.lua).
+-- any other race (Engine/Races.lua).
 
 local addon, ns = ...
 local Hekili = _G[ addon ]
diff --git a/src/Hekili/Forever/Races/Gnome.lua b/src/Hekili/Forever/Races/Gnome.lua
index 2e12dbdf..411db500 100644
--- a/src/Hekili/Forever/Races/Gnome.lua
+++ b/src/Hekili/Forever/Races/Gnome.lua
@@ -3,7 +3,7 @@
 -- +10% damage not modelled; 120 s, off the GCD; one ID per class: 1259813 Warrior, 1259812 Rogue, 1259817 Mage,
 -- 1259821 Warlock, 1259823 Priest), Expansive Mind (+5% maximum resources: 20591 Priest/Mage/Warlock, 1259802
 -- Warrior, 1259803 Rogue) and Escape Artist (20589: roots and snares removed, immune for 3 s; 120 s, on the GCD).
--- Engineering Specialization is a profession passive. Inert for any other race (Races.lua).
+-- Engineering Specialization is a profession passive. Inert for any other race (Engine/Races.lua).
 
 local addon, ns = ...
 local Hekili = _G[ addon ]
@@ -19,7 +19,7 @@ local EUREKA = { 1259812, 1259817, 1259821, 1259823 } -- the other classes' Eure
 --   and not (((o.SpellClassMask_0 & 4294967295)&<m0>)=0 and ((o.SpellClassMask_1 & 4294967295)&<m1>)=0
 --   and ((o.SpellClassMask_2 & 4294967295)&<m2>)=0)
 -- (no ManaCost filter: a percent cost reads 0 there). Higher ranks resolve through the class's `copy` lists; an ID the
--- loaded class does not register is absent (Races.lua, Modifiers.lua). Not listed: Rebuke 425609 (a Paladin spell in
+-- loaded class does not register is absent (Engine/Races.lua, Modifiers.lua). Not listed: Rebuke 425609 (a Paladin spell in
 -- the Rogue's set), Felfire 24530 (no class), the Warrior's Execute 20647 (the triggered damage: no GCD, no rank; the
 -- cast is 5308's ranks).
 local EUREKA_SPELLS = {
@@ -93,7 +93,7 @@ race:RegisterAura( "escape_artist", {
 
 race:RegisterResourceMod( { max = 0.05 } ) -- Expansive Mind: +5% maximum resources
 
--- The loaded class's scope (Classes.lua sets class.file before any race file runs); a class with no Eureka! (none
+-- The loaded class's scope (Engine/Spec.lua sets class.file before any race file runs); a class with no Eureka! (none
 -- exists for a Hunter, Shaman, Paladin or Druid) declares no cost modifier.
 local spells = EUREKA_SPELLS[ Hekili.Class.file ]
 if spells then
diff --git a/src/Hekili/Forever/Races/Human.lua b/src/Hekili/Forever/Races/Human.lua
index 388c2392..ca68dead 100644
--- a/src/Hekili/Forever/Races/Human.lua
+++ b/src/Hekili/Forever/Races/Human.lua
@@ -4,7 +4,7 @@
 -- detection for 20 s; 180 s, on the GCD). Will to Survive leaves no aura and no resource: no `handler` or `now`, its
 -- cooldown and GCD are the declared fields'. The Human Spirit (+5% Spirit) and Sword Specialization (+2% crit with a
 -- sword) are passives on stats the game reports. No resource or cost modifier. No pack names either. Inert for any
--- other race (Races.lua).
+-- other race (Engine/Races.lua).
 
 local addon, ns = ...
 local Hekili = _G[ addon ]
diff --git a/src/Hekili/Forever/Races/NightElf.lua b/src/Hekili/Forever/Races/NightElf.lua
index 72097b05..79873790 100644
--- a/src/Hekili/Forever/Races/NightElf.lua
+++ b/src/Hekili/Forever/Races/NightElf.lua
@@ -4,7 +4,7 @@
 -- `all`'s stock entry (58984, absent on Forever): 20580, no cooldown of its own but a 10 s category recovery (871),
 -- off the GCD, the stealth aura 20580 until cancelled. Quickness and Wisp Spirit are passives. No resource or cost
 -- modifier. No pack names either: a race ability is absent for other races; a player adds it to a priority if wanted.
--- Inert for any other race (Races.lua).
+-- Inert for any other race (Engine/Races.lua).
 
 local addon, ns = ...
 local Hekili = _G[ addon ]
diff --git a/src/Hekili/Forever/Races/Orc.lua b/src/Hekili/Forever/Races/Orc.lua
index 138fcbe1..23afc80c 100644
--- a/src/Hekili/Forever/Races/Orc.lua
+++ b/src/Hekili/Forever/Races/Orc.lua
@@ -4,7 +4,7 @@
 -- and 33697 are absent on Forever; its aura, 20572 for 15 s, is right but registered here too, so the race owns it),
 -- and Shatter Curse (1299026: removes curses, -15% magic damage taken and immunity to curses for 8 s; 180 s, on the
 -- GCD). Hardiness (-20% stun duration) and Axe Specialization (+1% crit with an axe) are passives. No resource or cost
--- modifier. No pack names either. Inert for any other race (Races.lua).
+-- modifier. No pack names either. Inert for any other race (Engine/Races.lua).
 
 local addon, ns = ...
 local Hekili = _G[ addon ]
diff --git a/src/Hekili/Forever/Races/Tauren.lua b/src/Hekili/Forever/Races/Tauren.lua
index 451969f2..db10ed77 100644
--- a/src/Hekili/Forever/Races/Tauren.lua
+++ b/src/Hekili/Forever/Races/Tauren.lua
@@ -2,7 +2,7 @@
 -- The Tauren's castable racial on Forever (DB2 1.60.1.70338), for every class: War Stomp (20549: stuns up to 5 enemies
 -- within 8 yards for 2 s; 0.5 s cast, 120 s, off the GCD), which Hekili's stock racials (`all`) lack. Plainsrunning
 -- (1259918, Forever's movement-speed ramp), Endurance and Cultivation have no cast, cost, maximum or rotation effect:
--- nothing to register. No pack names it. Inert for any other race (Races.lua).
+-- nothing to register. No pack names it. Inert for any other race (Engine/Races.lua).
 
 local addon, ns = ...
 local Hekili = _G[ addon ]
diff --git a/src/Hekili/Forever/Races/Troll.lua b/src/Hekili/Forever/Races/Troll.lua
index bdb5d1df..f777991f 100644
--- a/src/Hekili/Forever/Races/Troll.lua
+++ b/src/Hekili/Forever/Races/Troll.lua
@@ -5,7 +5,7 @@
 -- SPELL_ATTR1_IS_SELF_CHANNELLED, broken by movement, action or damage; 180 s, off the GCD), registered as a 6 s
 -- channel so the simulation does not recommend breaking it. The haste itself is the game's (Hekili reads haste); a
 -- priority reads `buff.berserking.up`. Regeneration and Beast Slaying are passives. No resource or cost modifier. No
--- pack names either. Inert for any other race (Races.lua).
+-- pack names either. Inert for any other race (Engine/Races.lua).
 
 local addon, ns = ...
 local Hekili = _G[ addon ]
diff --git a/src/Hekili/Forever/Races/Undead.lua b/src/Hekili/Forever/Races/Undead.lua
index 44d129b1..19ca92fa 100644
--- a/src/Hekili/Forever/Races/Undead.lua
+++ b/src/Hekili/Forever/Races/Undead.lua
@@ -6,7 +6,7 @@
 -- on the GCD), registered as a 10 s channel so the simulation does not recommend breaking it; whether a corpse is near
 -- is not known, a priority gates it. Touch of the Grave (1260189 Warrior/Paladin/Rogue, 1260201 Priest/Mage/Warlock: a
 -- proc that drains health) and Underwater Breathing are passives with no rotation effect. No resource or cost modifier.
--- No pack names either. Inert for any other race (Races.lua).
+-- No pack names either. Inert for any other race (Engine/Races.lua).
 
 local addon, ns = ...
 local Hekili = _G[ addon ]
diff --git a/src/Hekili/Hekili.toc b/src/Hekili/Hekili.toc
index 7aa3aee2..a2ecb589 100644
--- a/src/Hekili/Hekili.toc
+++ b/src/Hekili/Hekili.toc
@@ -48,10 +48,11 @@ Formatting.lua
 MultilineEditor.lua
 Constants.lua
 State.lua
-Races.lua
+Engine\Races.lua
 Events.lua
 
-Classes.lua
+Engine\Spec.lua
+Engine\Shared.lua
 Forever\Classes\Warrior.lua
 Forever\Classes\Druid.lua
 Forever\Races\Gnome.lua
diff --git a/src/Hekili/State.lua b/src/Hekili/State.lua
index ada3b348..2e2d7a15 100644
--- a/src/Hekili/State.lua
+++ b/src/Hekili/State.lua
@@ -510,7 +510,7 @@ end
 
 state.combat = 0
 state.faction = Facade.UnitFactionGroup( "player" )
--- The race token (UnitRace's second return), the same on every client language: race packs match it (Races.lua), and
+-- The race token (UnitRace's second return), the same on every client language: race packs match it (Engine/Races.lua), and
 -- race.gnome, race.troll ... hold beside the localized key.
 local raceName
 raceName, state.race_token = Facade.UnitRace( "player" )
@@ -6634,7 +6634,7 @@ ns.spendResources = function( ability )
             cost = ( cost * state[ resource ].modmax )
         end
 
-        -- a charged cost modifier's buff loses a stack when the declared cost is above 0, even at a discounted 0 (Races.lua)
+        -- a charged cost modifier's buff loses a stack when the declared cost is above 0, even at a discounted 0 (Engine/Races.lua)
         ns.costMods.Spend( action.baseSpend, ability )
 
         if cost ~= 0 then
diff --git a/src/Hekili/Virtual/State/Adapter.lua b/src/Hekili/Virtual/State/Adapter.lua
index 39ad9620..b2a7f165 100644
--- a/src/Hekili/Virtual/State/Adapter.lua
+++ b/src/Hekili/Virtual/State/Adapter.lua
@@ -152,7 +152,7 @@ local function buildDef()
         }
         insert(def.resources, d)
         slotByKey[k] = #def.resources
-        -- the race pack's resource and cost modifiers (Races.lua, event-facade spec §12b): every resource of the class,
+        -- the race pack's resource and cost modifiers (Engine/Races.lua, event-facade spec §12b): every resource of the class,
         -- but a maximum modifier never scales a point resource (combo points, runes, ...)
         local race = ns.raceMods
         if race then
diff --git a/src/Hekili/Virtual/State/Families/Casts.lua b/src/Hekili/Virtual/State/Families/Casts.lua
index 3de4f4c3..cb9038fa 100644
--- a/src/Hekili/Virtual/State/Families/Casts.lua
+++ b/src/Hekili/Virtual/State/Families/Casts.lua
@@ -251,7 +251,7 @@ end
 --- of its resource's believed maximum, as Hekili's simulation prices it (State.lua's spend). Allocates nothing.
 function I.BaseCostOf(a)
     local obj = I.ab.obj[a]
-    local c = obj.baseSpend -- the declared cost before the simulation's modifiers (Races.lua)
+    local c = obj.baseSpend -- the declared cost before the simulation's modifiers (Engine/Races.lua)
     if c == nil then
         c = obj.spend
     end
diff --git a/src/Hekili/Virtual/State/Families/Modifiers.lua b/src/Hekili/Virtual/State/Families/Modifiers.lua
index d8e93392..ecc8401d 100644
--- a/src/Hekili/Virtual/State/Families/Modifiers.lua
+++ b/src/Hekili/Virtual/State/Families/Modifiers.lua
@@ -1,6 +1,6 @@
 -- Virtual/State/Families/Modifiers.lua
 -- Declarative resource modifiers (event-facade spec §12b): two fields of a resource definition, filled by the race
--- packs (Races.lua, through Adapter.lua) and open to talents and class auras alike.
+-- packs (Engine/Races.lua, through Adapter.lua) and open to talents and class auras alike.
 -- - `maxMods`: { { pct = n, when = fn|nil }, ... }; the maximum is the declared `max` (a number or a state-bound
 --   function, default 100) x the product of (1 + pct) over the modifiers whose `when` holds. Families/Resources.lua's
 --   one maximum evaluator applies it (at the build, seeding the interval, and at each CombatEnd) until a plain maximum
diff --git a/tests/Forever/druid_spec.lua b/tests/Forever/druid_spec.lua
index 7ec72726..c683b676 100644
--- a/tests/Forever/druid_spec.lua
+++ b/tests/Forever/druid_spec.lua
@@ -628,7 +628,7 @@ describe("Forever Druid", function()
     it("writes priorities that name only registered abilities, auras, talents, settings and lists", function()
         local packs = assert(loadfile("tools/make_pack.lua"))("lists", "druid")
         local secretToken = require("Virtual.State.helpers.load").module().VirtualState.AplSecretToken
-        local shared = { use_items = true } -- Hekili's `all` (Classes.lua's use_items)
+        local shared = { use_items = true } -- Hekili's `all` (Engine/Spec.lua's use_items)
         local kinds = {
             buff = w.auras,
             debuff = w.auras,
diff --git a/tests/Virtual/Events/cleu_rows_spec.lua b/tests/Virtual/Events/cleu_rows_spec.lua
index 25bcb07c..e2a24dad 100644
--- a/tests/Virtual/Events/cleu_rows_spec.lua
+++ b/tests/Virtual/Events/cleu_rows_spec.lua
@@ -10,7 +10,7 @@ local fs = require("Virtual.State.helpers.fake_spec")
 describe("the synthesized combat log", function()
     local api, ctl, ns, VS, I, L, Facade, saved, got, order, cleu
 
-    -- ns.callHook's rebuild (Classes.lua:2858-2877): load_args into a wiped table, then unpack( vars ).
+    -- ns.callHook's rebuild (Engine/Spec.lua:2858-2877): load_args into a wiped table, then unpack( vars ).
     local function viaCallHook(...)
         local vars = {}
         for i = 1, select("#", ...) do
diff --git a/tests/Virtual/State/modifiers_spec.lua b/tests/Virtual/State/modifiers_spec.lua
index 4fc10360..6cf61928 100644
--- a/tests/Virtual/State/modifiers_spec.lua
+++ b/tests/Virtual/State/modifiers_spec.lua
@@ -1,5 +1,5 @@
 -- tests/Virtual/State/modifiers_spec.lua (event-facade spec §12b): the resource definition's `maxMods` and `costMods`,
--- as a race pack declares them (Races.lua's ns.raceMods: Expansive Mind, Eureka!), through the adapter.
+-- as a race pack declares them (Engine/Races.lua's ns.raceMods: Expansive Mind, Eureka!), through the adapter.
 local load = require("Virtual.State.helpers.load")
 local fake = require("Virtual.State.helpers.fake_api")
 local fs = require("Virtual.State.helpers.fake_spec")
@@ -37,7 +37,7 @@ describe("resource modifiers", function()
             return false
         end
         h.Class.auras.eureka = { key = "eureka", id = EUREKA, duration = 15 }
-        -- the Gnome race pack's declarations (Forever/Races/Gnome.lua through Races.lua), as Adapter.lua reads them
+        -- the Gnome race pack's declarations (Forever/Races/Gnome.lua through Engine/Races.lua), as Adapter.lua reads them
         ns.raceMods = {
             maxMods = { { pct = 0.05 } },
             costMods = { { aura = "eureka", pct = -0.10, charges = 3, spells = { fs.STRIKE, 999999 } } },
diff --git a/tests/Virtual/State/races_spec.lua b/tests/Virtual/State/races_spec.lua
index 35aeb08b..2853366f 100644
--- a/tests/Virtual/State/races_spec.lua
+++ b/tests/Virtual/State/races_spec.lua
@@ -1,4 +1,4 @@
--- tests/Virtual/State/races_spec.lua (event-facade spec §12b): race packs. Races.lua's `Hekili:NewRace` and every race
+-- tests/Virtual/State/races_spec.lua (event-facade spec §12b): race packs. Engine/Races.lua's `Hekili:NewRace` and every race
 -- file Hekili.toc lists (Forever/Races/*.lua), loaded headless against a stand-in for Hekili: inert for another race,
 -- registered for its own, over `all`'s stale entries; and the simulation's half of the cost modifier on abilities
 -- built as RegisterAbility builds them.
@@ -57,8 +57,8 @@ describe("race packs", function()
             }),
             removeStack = removeStack,
         }
-        all = { abilities = seed or {}, auras = {} } -- `seed`: what Classes.lua's `all` already registered
-        -- as Classes.lua's RegisterAbility/RegisterAura: the entry under its key, its id and every `copy` alias
+        all = { abilities = seed or {}, auras = {} } -- `seed`: what Engine/Spec.lua's `all` already registered
+        -- as Engine/Spec.lua's RegisterAbility/RegisterAura: the entry under its key, its id and every `copy` alias
         local function register(t, key, def)
             t[key] = def
             if def.id then
@@ -74,15 +74,15 @@ describe("race packs", function()
         function all:RegisterAura(key, def)
             register(self.auras, key, def)
         end
-        -- Classes.lua sets class.file before any race file runs
+        -- Engine/Spec.lua sets class.file before any race file runs
         hekili = { State = state, Class = { specs = { [0] = all }, abilities = {}, file = class or "WARRIOR" } }
         _G.Hekili = hekili
         ns = {}
-        assert(loadfile("src/Hekili/Races.lua"))("Hekili", ns)
+        assert(loadfile("src/Hekili/Engine/Races.lua"))("Hekili", ns)
         loadRaces(ns)
     end
 
-    -- An ability as Classes.lua's RegisterAbility builds it: function fields in `funcs`, called on access, wrapped.
+    -- An ability as Engine/Spec.lua's RegisterAbility builds it: function fields in `funcs`, called on access, wrapped.
     local function ability(key, data)
         local a = setmetatable({ funcs = {} }, {
             __index = function(t, k)
@@ -135,7 +135,7 @@ describe("race packs", function()
         })
     end)
 
-    it("writes the race's abilities and auras over the class's after Classes.lua's merge, aliases too", function()
+    it("writes the race's abilities and auras over the class's after Engine/Spec.lua's merge, aliases too", function()
         load("Gnome")
         local own = { id = 2 }
         local class = { abilities = { eureka = own, [1259812] = own, [1] = own }, auras = { eureka = { id = 2 } } }
@@ -238,7 +238,7 @@ describe("race packs", function()
             end
             table.sort(keys)
             local own = OWN[r.file] or {}
-            local mods = hekili.RaceMods -- the table read in game (Races.lua)
+            local mods = hekili.RaceMods -- the table read in game (Engine/Races.lua)
             assert.are.same(own, { keys, #mods.maxMods, #mods.costMods }, r.file)
         end
         for file in pairs(OWN) do
@@ -333,10 +333,10 @@ describe("race packs", function()
         assert.are.same({ 20578, 10 }, { all.auras.cannibalize.id, all.auras.cannibalize.duration }) -- the heal's aura
     end)
 
-    it("takes a class file's spec:RegisterCostMod (Classes.lua) into the same list, for any race", function()
+    it("takes a class file's spec:RegisterCostMod (Engine/Spec.lua) into the same list, for any race", function()
         load("Human")
-        -- the mixin's entry as Classes.lua declares it, compiled with this `ns` as its upvalue
-        local src = assert(io.open("src/Hekili/Classes.lua")):read("*a")
+        -- the mixin's entry as Engine/Spec.lua declares it, compiled with this `ns` as its upvalue
+        local src = assert(io.open("src/Hekili/Engine/Spec.lua")):read("*a")
         local entry = assert(src:match("\n(    RegisterCostMod = function%( self, def %).-\n    end,)\n"))
         local mixin = assert(loadstring("local ns = ...\nreturn {\n" .. entry .. "\n}"))(ns)
         local def = { aura = "clearcasting", pct = -1, charges = 1, spells = { 5221 } }
@@ -385,7 +385,7 @@ describe("race packs in VirtualState's now context", function()
         fs.clock = nil
     end)
 
-    -- What the race files register into `all` for the player's race `token` (Races.lua against a stand-in Hekili).
+    -- What the race files register into `all` for the player's race `token` (Engine/Races.lua against a stand-in Hekili).
     local function registrations(token)
         local all = { abilities = {}, auras = {} }
         function all:RegisterAbility(key, def)
@@ -396,7 +396,7 @@ describe("race packs in VirtualState's now context", function()
         end
         _G.Hekili = { State = { race_token = token }, Class = { specs = { [0] = all }, file = "WARRIOR" } }
         local rns = {}
-        assert(loadfile("src/Hekili/Races.lua"))("Hekili", rns)
+        assert(loadfile("src/Hekili/Engine/Races.lua"))("Hekili", rns)
         loadRaces(rns)
         return all
     end
```

- [ ] **Step 2: Run the specs (unchanged)**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `286 successes / 0 failures / 0 errors` (the base; `races_spec` reads `src/Hekili/Engine/Races.lua` and `src/Hekili/Engine/Spec.lua`).

- [ ] **Step 3: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [286 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 93 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 60 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 4: Commit**

```bash
git add .luacheckrc src/Hekili/Classes.lua src/Hekili/Races.lua src/Hekili/Engine src/Hekili/Hekili.toc src/Hekili/State.lua src/Hekili/Forever/Races src/Hekili/Virtual/State/Adapter.lua src/Hekili/Virtual/State/Families/Casts.lua src/Hekili/Virtual/State/Families/Modifiers.lua tests/Forever/druid_spec.lua tests/Virtual/Events/cleu_rows_spec.lua tests/Virtual/State/modifiers_spec.lua tests/Virtual/State/races_spec.lua
git commit -m "refactor(engine): Classes.lua to Engine/Spec.lua, Races.lua to Engine/Races.lua; Hekili:NewShared (shared-content spec §3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                          # [empty]
```

- [ ] **Step 5: Push** (orchestrator, after this task's review is clean): `git push origin forever-shared`

---
### Task 2: The GCD constant and the remap removal

Spec §5, named core edit E2. `I.GCD_SPELL` (29515) is the one name for Forever's GCD spell. The five core sites read it as `ns.VirtualStateInternal.GCD_SPELL` (populated before Hekili.lua loads: the `Virtual\` files come first in the TOC): `global_cooldown`'s `id` (Engine/Spec.lua), `UI.lua`'s two `GetSpellCooldown( 61304 )`, `Events.lua`'s, and `Options/Options.lua`'s ability-list filter. The facade's `cooldownPolicy` and `C_Spell.GetSpellCooldown` answer 29515 only; `C_Spell.GetSpellInfo` and `C_Spell.GetSpellTexture`, hybrid only to remap, become passthrough rows (inventory classes and the facade spec's counts follow: 123/26/27). `global_cooldown` stays engine content (spec §4.5); the adapter already skips it by key, so its new positive ID is not tracked.

**Files:**
- Modify: `src/Hekili/Engine/Spec.lua` (`global_cooldown`), `src/Hekili/UI.lua` (two sites), `src/Hekili/Events.lua`, `src/Hekili/Options/Options.lua`, `src/Hekili/Virtual/API/Facade.lua` (policy, GetSpellCooldown row, the two remap rows into `PASSTHROUGH`), `src/Hekili/Virtual/State/Sources/Spellbook.lua` (comment), `tools/api_inventory.txt`
- Test: `tests/Virtual/API/facade_spec.lua`, `tests/Virtual/State/alloc_spec.lua`

**Interfaces:**
- Consumes: `I.GCD_SPELL` (`ns.VirtualStateInternal.GCD_SPELL`).
- Produces: no 61304 in any file the TOC loads; `Facade.Status("C_Spell.GetSpellInfo") == "passthrough"`, likewise `GetSpellTexture`.

- [ ] **Step 1: Write the failing spec**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/tests/Virtual/API/facade_spec.lua b/tests/Virtual/API/facade_spec.lua
index 08987e62..49dbed85 100644
--- a/tests/Virtual/API/facade_spec.lua
+++ b/tests/Virtual/API/facade_spec.lua
@@ -328,18 +328,20 @@ describe("ns.Facade", function()
         assert.are.equal(0, select("#", ns2.Facade.HasOverrideActionBar()))
     end)
 
-    it("answers Forever's GCD spell, empty spec slots and talent ranks in retail's shape (decision 7)", function()
-        local g = Facade.C_Spell.GetSpellCooldown(61304)
-        local f = Facade.C_Spell.GetSpellCooldown(29515)
-        assert.are.same({ f.startTime, f.duration }, { g.startTime, g.duration })
-        assert.are.equal("Spell 29515", Facade.C_Spell.GetSpellInfo(61304).name)
-        local asked
-        answers["C_Spell.GetSpellTexture"] = function(id)
-            asked = id
-            return 1
+    it("names the GCD by one constant: Forever's GCD spell, I.GCD_SPELL, and 61304 in no file the TOC loads", function()
+        for line in io.lines("src/Hekili/Hekili.toc") do
+            local file = line:match("^([%w_\\]+%.lua)%s*$")
+            if file then
+                local src = assert(io.open("src/Hekili/" .. file:gsub("\\", "/"))):read("*a")
+                assert.is_nil(src:find("61304", 1, true), file)
+            end
         end
-        Facade.C_Spell.GetSpellTexture(61304)
-        assert.are.equal(29515, asked)
+        local spec = assert(io.open("src/Hekili/Engine/Spec.lua")):read("*a")
+        assert.is_truthy(spec:find("global_cooldown = {\n        id = ns.VirtualStateInternal.GCD_SPELL,", 1, true))
+        assert.are.equal(29515, I.GCD_SPELL)
+    end)
+
+    it("answers empty spec slots and talent ranks in retail's shape (decision 7)", function()
         answers["C_SpecializationInfo.GetSpecializationInfo"] = function(i)
             if i == 1 then
                 return 1491, "Warrior", "", 1, "DAMAGER", 1
diff --git a/tests/Virtual/State/alloc_spec.lua b/tests/Virtual/State/alloc_spec.lua
index 39b5c621..9fece526 100644
--- a/tests/Virtual/State/alloc_spec.lua
+++ b/tests/Virtual/State/alloc_spec.lua
@@ -130,7 +130,6 @@ describe("zero allocation", function()
             Facade.C_UnitAuras.GetAuraDataByAuraInstanceID("player", 1)
             Facade.C_Spell.GetSpellCooldown(fs.REND)
             Facade.C_Spell.GetSpellCooldown(29515)
-            Facade.C_Spell.GetSpellCooldown(61304) -- retail's GCD spell, asked as Forever's
             Facade.C_Spell.GetSpellCharges(fs.REND)
             Facade.UnitCastingInfo("target")
             Facade.UnitChannelInfo("target")
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `286 successes / 1 failure / 0 errors` (`facade_spec` "names the GCD by one constant ...": `Virtual\API\Facade.lua` names 61304).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/src/Hekili/Engine/Spec.lua b/src/Hekili/Engine/Spec.lua
index 9f9fcec7..ebaa81ff 100644
--- a/src/Hekili/Engine/Spec.lua
+++ b/src/Hekili/Engine/Spec.lua
@@ -2477,7 +2477,7 @@ end
 
 all:RegisterAbilities( {
     global_cooldown = {
-        id = 61304,
+        id = ns.VirtualStateInternal.GCD_SPELL,
         cast = 0,
         cooldown = 0,
         gcd = "spell",
diff --git a/src/Hekili/Events.lua b/src/Hekili/Events.lua
index 272199e7..ae6571a8 100644
--- a/src/Hekili/Events.lua
+++ b/src/Hekili/Events.lua
@@ -1676,7 +1676,7 @@ local function CLEU_HANDLER( event, timestamp, subtype, hideCaster, sourceGUID,
                 end
             end
 
-            state.gcd.lastStart = max( state.gcd.lastStart, ( GetSpellCooldown( 61304 ) ) )
+            state.gcd.lastStart = max( state.gcd.lastStart, ( GetSpellCooldown( ns.VirtualStateInternal.GCD_SPELL ) ) )
             -- if subtype ~= "SPELL_DAMAGE" then Hekili:ForceUpdate( subtype, true ) end
         end
     end
diff --git a/src/Hekili/Options/Options.lua b/src/Hekili/Options/Options.lua
index 72eec609..f60d0b8d 100644
--- a/src/Hekili/Options/Options.lua
+++ b/src/Hekili/Options/Options.lua
@@ -4040,7 +4040,7 @@ self:ForceUpdate( "SPEC_PACKAGE_CHANGED" )
 
         for k, v in pairs( class.abilityList ) do
             local a = class.abilities[ k ]
-            if a and a.id and ( a.id > 0 or a.id < -100 ) and a.id ~= 61304 and not a.item then
+            if a and a.id and ( a.id > 0 or a.id < -100 ) and a.id ~= ns.VirtualStateInternal.GCD_SPELL and not a.item then
                 abilities[ v ] = k
             end
         end
diff --git a/src/Hekili/UI.lua b/src/Hekili/UI.lua
index c5b5b147..5d5b55a3 100644
--- a/src/Hekili/UI.lua
+++ b/src/Hekili/UI.lua
@@ -1491,7 +1491,7 @@ do
                         local start, duration = 0, 0
 
                         if a.gcd ~= "off" then
-                            start, duration = GetSpellCooldown( 61304 )
+                            start, duration = GetSpellCooldown( ns.VirtualStateInternal.GCD_SPELL )
                             if start > 0 then earliest_time = start + duration - now end
                         end
 
@@ -1692,7 +1692,7 @@ do
         end
 
         function d:RefreshCooldowns( event )
-            local gStart = GetSpellCooldown( 61304 )
+            local gStart = GetSpellCooldown( ns.VirtualStateInternal.GCD_SPELL )
             local cStart = ( select( 4, UnitCastingInfo( "player" ) ) or select( 4, UnitChannelInfo( "player" ) ) or 0 ) / 1000
 
             local now = GetTime()
diff --git a/src/Hekili/Virtual/API/Facade.lua b/src/Hekili/Virtual/API/Facade.lua
index ce987af2..debbff69 100644
--- a/src/Hekili/Virtual/API/Facade.lua
+++ b/src/Hekili/Virtual/API/Facade.lua
@@ -525,7 +525,7 @@ end
 
 local function cooldownPolicy(spellID)
     local t = now()
-    if spellID == 61304 or spellID == I.GCD_SPELL then
+    if spellID == I.GCD_SPELL then
         local s, d = VS.GcdInfo(t)
         CD.startTime, CD.duration, CD.isActive, CD.isOnGCD = s, d, d > 0, false
         return CD
@@ -561,9 +561,6 @@ local function cooldownPolicy(spellID)
     return CD
 end
 kept("C_Spell.GetSpellCooldown", "hybrid", function(spellID)
-    if spellID == 61304 then
-        spellID = I.GCD_SPELL -- retail's GCD spell asked as Forever's (decision 7)
-    end
     local info = realGetSpellCooldown and realGetSpellCooldown(spellID)
     if plainTimes(info, "startTime", "duration") then
         return info
@@ -687,25 +684,11 @@ kept("GetTime", "hybrid", function()
 end, "plain [W]; a back-dated combat-log row's observed time while it is delivered")
 
 ----------------------------------------------------------------------------------------------------------------------
--- Forever's answers in retail's shape (event-facade decision 7): the GCD spell, an empty specialization slot
+-- Forever's answers in retail's shape (event-facade decision 7): an empty specialization slot. Hekili asks the GCD as
+-- Forever's own spell, I.GCD_SPELL (shared-content spec §5).
 
-local realGetSpellTexture = resolve("C_Spell.GetSpellTexture")
 local realGetSpecializationInfo = resolve("C_SpecializationInfo.GetSpecializationInfo")
 
-kept("C_Spell.GetSpellInfo", "hybrid", function(spellID, ...)
-    if spellID == 61304 then
-        spellID = I.GCD_SPELL
-    end
-    return realGetSpellInfo(spellID, ...)
-end, "unprobed; retail's GCD spell 61304 asked as Forever's 29515")
-
-kept("C_Spell.GetSpellTexture", "hybrid", function(spellID, ...)
-    if spellID == 61304 then
-        spellID = I.GCD_SPELL
-    end
-    return realGetSpellTexture(spellID, ...)
-end, "unprobed; retail's GCD spell 61304 asked as Forever's 29515")
-
 local function noEmptySlot(id, ...)
     if not issecretvalue(id) and id == 0 then
         return nil -- Forever answers id 0 for an empty slot; retail answers nothing
@@ -751,7 +734,9 @@ local PASSTHROUGH = {
     { "C_SpecializationInfo.GetSpecialization", "plain [W PR15]" },
     { "C_SpecializationInfo.GetTalentInfo", "unprobed" },
     { "C_Spell.GetSpellDescription", "unprobed" },
+    { "C_Spell.GetSpellInfo", "unprobed" },
     { "C_Spell.GetSpellPowerCost", "plain [W §4]" },
+    { "C_Spell.GetSpellTexture", "unprobed" },
     { "C_Spell.IsCurrentSpell", "plain [W PR1]" },
     { "C_Spell.IsSpellDataCached", "unprobed" },
     { "C_Spell.IsSpellHarmful", "unprobed" },
diff --git a/src/Hekili/Virtual/State/Sources/Spellbook.lua b/src/Hekili/Virtual/State/Sources/Spellbook.lua
index 2a54a9b3..1c9f54e9 100644
--- a/src/Hekili/Virtual/State/Sources/Spellbook.lua
+++ b/src/Hekili/Virtual/State/Sources/Spellbook.lua
@@ -12,7 +12,7 @@ local S = I.Sources
 local Obs = VS.Obs
 local Plain, Stage, Note = S.Plain, S.Stage, S.Note
 
---- Forever's GCD spell (cleanup Q6).
+--- Forever's GCD spell (cleanup Q6): the one constant core and the facade ask the GCD by (shared-content spec §5).
 I.GCD_SPELL = 29515
 
 -- By ability index: the last ready flag reported (-1 none, 0 not ready, 1 ready); the GCD's (-1, 0 idle, 1 active).
diff --git a/tests/Virtual/API/facade_spec.lua b/tests/Virtual/API/facade_spec.lua
index 49dbed85..2197e088 100644
--- a/tests/Virtual/API/facade_spec.lua
+++ b/tests/Virtual/API/facade_spec.lua
@@ -116,7 +116,7 @@ describe("ns.Facade", function()
             assert.is_function(entry(n), n)
             assert.is_string(Facade.Why(n), n)
         end
-        assert.are.same({ passthrough = 121, hybrid = 28, virtual = 27 }, count)
+        assert.are.same({ passthrough = 123, hybrid = 26, virtual = 27 }, count)
         assert.is_nil(Facade.Status("NotAGameFunction"))
     end)
 
diff --git a/tools/api_inventory.txt b/tools/api_inventory.txt
index 635e0d98..d28267b4 100644
--- a/tools/api_inventory.txt
+++ b/tools/api_inventory.txt
@@ -29,10 +29,10 @@ C_Spell.GetSpellCastCount	virtual
 C_Spell.GetSpellCharges	hybrid
 C_Spell.GetSpellCooldown	hybrid
 C_Spell.GetSpellDescription	passthrough
-C_Spell.GetSpellInfo	hybrid
+C_Spell.GetSpellInfo	passthrough
 C_Spell.GetSpellLossOfControlCooldown	virtual
 C_Spell.GetSpellPowerCost	passthrough
-C_Spell.GetSpellTexture	hybrid
+C_Spell.GetSpellTexture	passthrough
 C_Spell.IsCurrentSpell	passthrough
 C_Spell.IsSpellDataCached	passthrough
 C_Spell.IsSpellHarmful	passthrough
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `287 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [287 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 93 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 60 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Engine/Spec.lua src/Hekili/UI.lua src/Hekili/Events.lua src/Hekili/Options/Options.lua src/Hekili/Virtual/API/Facade.lua src/Hekili/Virtual/State/Sources/Spellbook.lua tools/api_inventory.txt tests/Virtual/API/facade_spec.lua tests/Virtual/State/alloc_spec.lua
git commit -m "refactor(gcd): Forever's GCD spell by one constant at the five core sites; the facade's 61304 remap goes (shared-content spec §5, E2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                          # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-shared`

---
### Task 3: `Forever/Shared/Auras.lua`, the dead tree out of the engine, the key test

Spec §4.1, §4.2. `Forever/Shared/Auras.lua` registers through `Hekili:NewShared()`: the four id-less stubs core reads by name (`voidbinding`, `voidform`, `shadowform`, `adrenaline_rush`; stubs rather than State.lua edits, spec §4.1), `bloodlust` as an alias of one member, `bloodlust_actual` 1245940 (checkpoint Q2), `power_infusion` 10060 at 15 s, the seven loss-of-control generators and `dispellable_curse`/`_poison`/`_disease`/`reversible_magic` verbatim, and `dispellable_magic` as `reversible_magic`'s generator (the target half dropped, rule R4). `Engine/Spec.lua`'s `all:RegisterAuras` keeps `casting`, `movement`, `unknown_buff`; the lusts, lockouts, `mark_of_the_wild`, `battle_shout`, the racial auras, `out_of_range`, `stealable_magic`, `dispellable_enrage` and `all_absorbs` go, and so do the racial abilities (`berserking`, `bf_classes` and `blood_fury`, `will_to_survive`, `shadowmeld`, `stoneform`) and the locals only they read (`LSR`, the loss-of-control reads, `UnitBuff`/`UnitDebuff`, `UnitGetTotalAbsorbs`). Every name removed from Spec.lua keeps another reader, so the API inventory is unchanged.

`tests/Forever/shared_spec.lua` loads `Engine/Races.lua`, `Engine/Shared.lua` and the shared files `Hekili.toc` lists against a stand-in `all` (as `races_spec` does), and greps every `tools/packs/*.lua`, `src/Hekili/Engine/*.lua` and `src/Hekili/Forever/**/*.lua` for the dropped keys.

**Files:**
- Create: `src/Hekili/Forever/Shared/Auras.lua`
- Modify: `src/Hekili/Engine/Spec.lua` (the auras block, the racial abilities, unused locals), `src/Hekili/Hekili.toc` (after `Engine\Shared.lua`), `.luacheckrc` (`Forever/Shared/`)
- Test: `tests/Forever/shared_spec.lua` (new)

**Interfaces:**
- Consumes: `Hekili:NewShared()` (Task 1), `ns.Facade.C_LossOfControl`, `ns.UnitDebuff`.
- Produces: in `all`: the 19 aura keys of spec §4.1's "Shared/Auras" rows, `sapped`/`slowed` copies; the drop list of the key test.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/tests/Forever/shared_spec.lua b/tests/Forever/shared_spec.lua
new file mode 100644
index 00000000..3004702b
--- /dev/null
+++ b/tests/Forever/shared_spec.lua
@@ -0,0 +1,212 @@
+-- tests/Forever/shared_spec.lua (shared-content spec §3, §4, §8): Engine/Shared.lua's `Hekili:NewShared` and the shared
+-- content files Hekili.toc lists (Forever/Shared/*.lua), loaded headless against a stand-in for Hekili's `all`; and no
+-- priority, class, race, engine or shared file names a key the pass dropped, nor one it stubbed outside its stub.
+
+-- Every shared content file Hekili.toc lists, in its order.
+local SHARED = {}
+for line in io.lines("src/Hekili/Hekili.toc") do
+    local file = line:match("^Forever\\Shared\\(%w+)%.lua")
+    if file then
+        SHARED[#SHARED + 1] = file
+    end
+end
+
+-- Keys the pass removed from `all` (spec §4): absent on Forever, or unobservable in combat on the target.
+local DROPPED = {
+    "ancient_hysteria",
+    "heroism",
+    "time_warp",
+    "netherwinds",
+    "primal_rage",
+    "drums_of_deathly_ferocity",
+    "fury_of_the_aspects",
+    "harriers_cry",
+    "exhaustion",
+    "insanity",
+    "temporal_displacement",
+    "fatigued",
+    "sated",
+    "sated_actual",
+    "out_of_range",
+    "stealable_magic",
+    "dispellable_enrage",
+    "all_absorbs",
+    "unravel_absorb",
+}
+-- Keys core reads by name (State.lua): id-less stubs in Forever/Shared/Auras.lua, never up.
+local STUBS = { "voidbinding", "voidform", "shadowform", "adrenaline_rush" }
+-- Keys `all` gave up to the class or race file that registers them.
+local OWNERS = {
+    mark_of_the_wild = "Forever/Classes/Druid.lua",
+    battle_shout = "Forever/Classes/Warrior.lua",
+    berserking = "Forever/Races/Troll.lua",
+    blood_fury = "Forever/Races/Orc.lua",
+    shadowmeld = "Forever/Races/NightElf.lua",
+    will_to_survive = "Forever/Races/Human.lua",
+    stoneform = "Forever/Races/Dwarf.lua",
+}
+
+local function read(path)
+    local f = assert(io.open(path))
+    local s = f:read("*a")
+    f:close()
+    return s
+end
+
+-- Whether `src` names `key` as a whole word (an APL token, a table key, a string).
+local function names(src, key)
+    return src:find("%f[%w_]" .. key .. "%f[^%w_]") ~= nil
+end
+
+describe("shared content", function()
+    local all, ns, saved, debuffs
+
+    -- Runs Engine/Races.lua, Engine/Shared.lua and the named shared files (default: every one Hekili.toc lists) against
+    -- a stand-in `all` that registers as Engine/Spec.lua's RegisterAbility/RegisterAura: under the key, its id and
+    -- every `copy` alias.
+    local function load(files)
+        all = { abilities = {}, auras = {}, keys = { abilities = {}, auras = {} } }
+        local function register(t, key, def)
+            table.insert(all.keys[t == all.abilities and "abilities" or "auras"], key)
+            t[key] = def
+            if def.id then
+                t[def.id] = def
+            end
+            for _, c in ipairs(type(def.copy) == "table" and def.copy or { def.copy }) do
+                t[c] = def
+            end
+        end
+        function all:RegisterAbility(key, def)
+            register(self.abilities, key, def)
+        end
+        function all:RegisterAura(key, def)
+            register(self.auras, key, def)
+        end
+        _G.Hekili = { State = { race_token = "BloodElf" }, Class = { specs = { [0] = all }, file = "WARRIOR" } }
+        debuffs = {}
+        ns = {
+            Facade = {
+                C_LossOfControl = {
+                    GetActiveLossOfControlData = function() end,
+                    GetActiveLossOfControlDataCount = function()
+                        return 0
+                    end,
+                },
+            },
+            -- the player's debuffs by index: name, icon, count, dispel type, duration, expiration
+            UnitDebuff = function(unit, i)
+                local d = unit == "player" and debuffs[i]
+                if d then
+                    return d[1], nil, d[2], d[3], d[4], d[5]
+                end
+            end,
+            UnitBuff = function()
+                error("a shared aura reads the target's buffs")
+            end,
+        }
+        assert(loadfile("src/Hekili/Engine/Races.lua"))("Hekili", ns)
+        assert(loadfile("src/Hekili/Engine/Shared.lua"))("Hekili", ns)
+        for _, f in ipairs(files or SHARED) do
+            assert(loadfile("src/Hekili/Forever/Shared/" .. f .. ".lua"))("Hekili", ns)
+        end
+    end
+
+    -- The keys registered into `all`'s `kind`, sorted.
+    local function keys(kind)
+        local out = { unpack(all.keys[kind]) }
+        table.sort(out)
+        return out
+    end
+
+    before_each(function()
+        saved = rawget(_G, "Hekili") or false
+    end)
+
+    after_each(function()
+        _G.Hekili = saved or nil
+    end)
+
+    it("writes every registration into `all`, for any race, and the modifiers into the race packs' lists", function()
+        load({})
+        local shared = _G.Hekili:NewShared()
+        local a, b = { id = 1 }, { id = 2 }
+        shared:RegisterAbility("x", a)
+        shared:RegisterAura("x", b)
+        shared:RegisterResourceMod({ max = 0.05 })
+        local def = { aura = "x", pct = -0.1 }
+        shared:RegisterCostMod(def)
+        assert.are.same({ a, b }, { all.abilities.x, all.auras.x })
+        assert.are.same({ { pct = 0.05 } }, ns.raceMods.maxMods)
+        assert.are.equal(def, ns.raceMods.costMods[1])
+    end)
+
+    it("registers exactly Forever's shared auras: the external ones on the player and the stubs core reads", function()
+        load({ "Auras" })
+        assert.are.same({
+            "adrenaline_rush",
+            "bloodlust",
+            "bloodlust_actual",
+            "disoriented",
+            "dispellable_curse",
+            "dispellable_disease",
+            "dispellable_magic",
+            "dispellable_poison",
+            "feared",
+            "incapacitated",
+            "loss_of_control",
+            "power_infusion",
+            "reversible_magic",
+            "rooted",
+            "shadowform",
+            "snared",
+            "stunned",
+            "voidbinding",
+            "voidform",
+        }, keys("auras"))
+        assert.are.same({ all.auras.incapacitated, all.auras.snared }, { all.auras.sapped, all.auras.slowed })
+        assert.are.same({ 10060, 15 }, { all.auras.power_infusion.id, all.auras.power_infusion.duration })
+        assert.are.same({ "bloodlust_actual" }, all.auras.bloodlust.alias)
+        assert.are.same({ 1245940, "player" }, { all.auras.bloodlust_actual.id, all.auras.bloodlust_actual.shared })
+        for _, k in ipairs(STUBS) do
+            assert.are.same({}, all.auras[k], k) -- no id: never found on a unit, so never up
+        end
+    end)
+
+    it("reads dispellable magic from the player's debuffs only, as a buff or a debuff", function()
+        load({ "Auras" })
+        debuffs[1] = { "Curse of Agony", 1, "Curse", 24, 30 }
+        debuffs[2] = { "Polymorph", 0, "Magic", 10, 20 }
+        for _, kind in ipairs({ "buff", "debuff" }) do
+            local t = {}
+            all.auras.dispellable_magic.generate(t, kind)
+            assert.are.same({ 1, 20, 10, "nobody" }, { t.count, t.expires, t.applied, t.caster }, kind)
+        end
+    end)
+
+    it("leaves no dropped key in a priority, a class, race, engine or shared file, and no stub outside its own", function()
+        local ls = assert(io.popen("find src/Hekili/Engine src/Hekili/Forever tools/packs -name '*.lua' | sort"))
+        local n = 0
+        for path in ls:lines() do
+            local src = read(path)
+            for _, k in ipairs(DROPPED) do
+                assert.is_false(names(src, k), path .. ": " .. k)
+            end
+            if path ~= "src/Hekili/Forever/Shared/Auras.lua" then
+                for _, k in ipairs(STUBS) do
+                    assert.is_false(names(src, k), path .. ": " .. k)
+                end
+            end
+            n = n + 1
+        end
+        ls:close()
+        assert.is_true(n > 10)
+    end)
+
+    it("leaves each key `all` gave up registered by its class or race file", function()
+        local spec = read("src/Hekili/Engine/Spec.lua")
+        for k, owner in pairs(OWNERS) do
+            assert.is_true(names(read("src/Hekili/" .. owner), k), owner .. ": " .. k)
+            assert.is_false(names(spec, k), "Engine/Spec.lua: " .. k)
+        end
+    end)
+end)
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `288 successes / 4 failures / 0 errors` (`shared_spec`: "registers exactly Forever's shared auras ..." and "reads dispellable magic ...": no `Forever/Shared/Auras.lua`; "leaves no dropped key ...": `Engine/Spec.lua` names `ancient_hysteria`; "leaves each key `all` gave up ...": `Engine/Spec.lua` names `battle_shout`. The `NewShared` case passes on Task 1's file).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/.luacheckrc b/.luacheckrc
index 26606f59..d30bbb20 100644
--- a/.luacheckrc
+++ b/.luacheckrc
@@ -119,3 +119,4 @@ for _, k in ipairs(stateEnv) do
 end
 files["src/Hekili/Forever/Classes/Druid.lua"] = { globals = druidEnv }
 files["src/Hekili/Forever/Races/"] = { globals = stateEnv }
+files["src/Hekili/Forever/Shared/"] = { globals = stateEnv }
diff --git a/src/Hekili/Engine/Spec.lua b/src/Hekili/Engine/Spec.lua
index ebaa81ff..48edc60d 100644
--- a/src/Hekili/Engine/Spec.lua
+++ b/src/Hekili/Engine/Spec.lua
@@ -5,10 +5,10 @@
 
 local addon, ns = ...
 local Facade = ns.Facade
-local C_Item, C_LossOfControl, C_SpecializationInfo, C_Spell = Facade.C_Item, Facade.C_LossOfControl, Facade.C_SpecializationInfo, Facade.C_Spell
+local C_Item, C_SpecializationInfo, C_Spell = Facade.C_Item, Facade.C_SpecializationInfo, Facade.C_Spell
 local GetSpecializationInfoByID, GetTime, InCombatLockdown, UnitAttackSpeed = Facade.GetSpecializationInfoByID, Facade.GetTime, Facade.InCombatLockdown, Facade.UnitAttackSpeed
 local UnitCanAttack, UnitCastingInfo, UnitChannelInfo, UnitClassBase = Facade.UnitCanAttack, Facade.UnitCastingInfo, Facade.UnitChannelInfo, Facade.UnitClassBase
-local UnitGUID, UnitGetTotalAbsorbs = Facade.UnitGUID, Facade.UnitGetTotalAbsorbs
+local UnitGUID = Facade.UnitGUID
 local Hekili = _G[ addon ]
 
 local class = Hekili.Class
@@ -24,21 +24,16 @@ local RegisterUnitEvent = ns.RegisterUnitEvent
 
 local getSpecializationKey = ns.getSpecializationKey
 
-local LSR = LibStub( "SpellRange-1.0" )
-
 local insert, wipe = table.insert, table.wipe
 
 local mt_resource = ns.metatables.mt_resource
 
-local GetActiveLossOfControlData, GetActiveLossOfControlDataCount = C_LossOfControl.GetActiveLossOfControlData, C_LossOfControl.GetActiveLossOfControlDataCount
 local GetItemCooldown = C_Item.GetItemCooldown
 local GetSpellDescription, GetSpellTexture = C_Spell.GetSpellDescription, C_Spell.GetSpellTexture
 local GetSpecialization, GetSpecializationInfo = C_SpecializationInfo.GetSpecialization, C_SpecializationInfo.GetSpecializationInfo
 local GetItemSpell, GetItemCount, IsUsableItem = C_Item.GetItemSpell, C_Item.GetItemCount, C_Item.IsUsableItem
 local GetSpellInfo = C_Spell.GetSpellInfo
 
-local UnitBuff, UnitDebuff = ns.UnitBuff, ns.UnitDebuff
-
 local specTemplate = {
     enabled = true,
 
@@ -1485,169 +1480,6 @@ local all = Hekili:NewSpecialization( 0, "All", "Interface\\Addons\\Hekili\\Text
 ---@diagnostic disable-next-line: need-check-nil
 all:RegisterAuras( {
 
-    -- Retail M+ aura kept because State.lua's GCD maths reads debuff.voidbinding.
-    voidbinding = {
-        id = 462661,
-        duration = 30,
-        max_stack = 1,
-        shared = "player"
-    },
-    -- Can be used in GCD calculation.
-    shadowform = {
-        id = 232698,
-        duration = 3600,
-        max_stack = 1,
-    },
-
-    voidform = {
-        id = 194249,
-        duration = 15,
-        max_stack = 1,
-    },
-
-    adrenaline_rush = {
-        id = 13750,
-        duration = 20,
-        max_stack = 1,
-    },
-
-    -- Bloodlusts
-    ancient_hysteria = {
-        id = 90355,
-        shared = "player", -- use anyone's buff on the player, not just player's.
-        duration = 40,
-        max_stack = 1,
-    },
-
-    heroism = {
-        id = 32182,
-        shared = "player", -- use anyone's buff on the player, not just player's.
-        duration = 40,
-        max_stack = 1,
-    },
-
-    time_warp = {
-        id = 80353,
-        shared = "player", -- use anyone's buff on the player, not just player's.
-        duration = 40,
-        max_stack = 1,
-    },
-
-    netherwinds = {
-        id = 160452,
-        shared = "player", -- use anyone's buff on the player, not just player's.
-        duration = 40,
-        max_stack = 1,
-    },
-
-    primal_rage = {
-        id = 264667,
-        shared = "player", -- use anyone's buff on the player, not just player's.
-        duration = 40,
-        max_stack = 1,
-    },
-
-    drums_of_deathly_ferocity = {
-        id = 309658,
-        shared = "player", -- use anyone's buff on the player, not just player's.
-        duration = 40,
-        max_stack = 1,
-    },
-
-    bloodlust = {
-        alias = { "ancient_hysteria", "bloodlust_actual", "drums_of_deathly_ferocity", "fury_of_the_aspects", "heroism", "netherwinds", "primal_rage", "time_warp", "harriers_cry" },
-        aliasMode = "first",
-        aliasType = "buff",
-        duration = 3600,
-    },
-
-    bloodlust_actual = {
-        id = 2825,
-        duration = 40,
-        shared = "player",
-        max_stack = 1,
-    },
-
-    exhaustion = {
-        id = 57723,
-        duration = 600,
-        shared = "player",
-        max_stack = 1,
-        copy = 390435
-    },
-
-    insanity = {
-        id = 95809,
-        duration = 600,
-        shared = "player",
-        max_stack = 1
-    },
-
-    temporal_displacement = {
-        id = 80354,
-        duration = 600,
-        shared = "player",
-        max_stack = 1
-    },
-
-    fury_of_the_aspects = {
-        id = 390386,
-        duration = 40,
-        max_stack = 1,
-        shared = "player",
-    },
-
-    harriers_cry = {
-        id = 466904,
-        duration = 40,
-        max_stack = 1,
-        shared = "player"
-    },
-
-    mark_of_the_wild = {
-        id = 1126,
-        duration = 3600,
-        max_stack = 1,
-        shared = "player",
-    },
-
-    fatigued = {
-        id = 264689,
-        duration = 600,
-        shared = "player",
-        max_stack = 1
-    },
-
-    sated = {
-        alias = { "exhaustion", "fatigued", "insanity", "sated_actual", "temporal_displacement" },
-        aliasMode = "first",
-        aliasType = "debuff",
-        duration = 3600,
-    },
-
-    sated_actual = {
-        id = 57724,
-        duration = 600,
-        shared = "player",
-        max_stack = 1,
-    },
-
-    power_infusion = {
-        id = 10060,
-        duration = 20,
-        max_stack = 1,
-        shared = "player",
-        dot = "buff"
-    },
-
-    battle_shout = {
-        id = 6673,
-        duration = 3600,
-        max_stack = 1,
-        shared = "player",
-        dot = "buff"
-    },
-
     casting = {
         name = "Casting",
         generate = function( t, auraType )
@@ -1757,572 +1589,6 @@ all:RegisterAuras( {
 
     -- Why do we have this, again?
     unknown_buff = {},
-
-    berserking = {
-        id = 26297,
-        duration = 10,
-    },
-
-    blood_fury = {
-        id = 20572,
-        duration = 15,
-    },
-
-    shadowmeld = {
-        id = 58984,
-        duration = 3600,
-    },
-
-    out_of_range = {
-        generate = function ( oor )
-            oor.rangeSpell = rawget( oor, "rangeSpell" ) or settings.spec.rangeChecker or class.specs[ state.spec.id ].ranges[ 1 ]
-
-            if LSR.IsSpellInRange( class.abilities[ oor.rangeSpell ].name, "target" ) ~= 1 then
-                oor.count = 1
-                oor.applied = query_time
-                oor.expires = query_time + 3600
-                oor.caster = "player"
-                oor.v1 = oor.rangeSpell
-                return
-            end
-
-            oor.count = 0
-            oor.applied = 0
-            oor.expires = 0
-            oor.caster = "nobody"
-        end,
-    },
-
-    loss_of_control = {
-        duration = 10,
-        generate = function( t )
-            local max_events = GetActiveLossOfControlDataCount()
-
-            if max_events > 0 then
-                local spell, start, duration, remains = 0, 0, 0, 0
-
-                for i = 1, max_events do
-                    local event = GetActiveLossOfControlData( i )
-
-                    if event and event.lockoutSchool == 0 and event.startTime and event.startTime > 0 and event.timeRemaining and event.timeRemaining > 0 and event.timeRemaining > remains then
-                        spell = event.spellID
-                        start = event.startTime
-                        duration = event.duration
-                        remains = event.timeRemaining
-                    end
-                end
-
-                if start + duration > query_time then
-                    t.count = 1
-                    t.expires = start + duration
-                    t.applied = start
-                    t.duration = duration
-                    t.caster = "anybody"
-                    t.v1 = spell
-                    return
-                end
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.duration = 10
-            t.caster = "nobody"
-            t.v1 = 0
-        end,
-    },
-
-    disoriented = {  -- Disorients (e.g., Polymorph, Dragon’s Breath, Blind)
-        duration = 10,
-        generate = function( t )
-            local max_events = GetActiveLossOfControlDataCount()
-
-            if max_events > 0 then
-                local spell, start, duration, remains = 0, 0, 0, 0
-
-                for i = 1, max_events do
-                    local event = GetActiveLossOfControlData( i )
-
-                    if event and event.locType == "CONFUSE"
-                        and event.startTime and event.startTime > 0
-                        and event.timeRemaining and event.timeRemaining > 0
-                        and event.timeRemaining > remains then
-
-                        spell = event.spellID
-                        start = event.startTime
-                        duration = event.duration
-                        remains = event.timeRemaining
-                    end
-                end
-
-                if start + duration > query_time then
-                    t.count = 1
-                    t.expires = start + duration
-                    t.applied = start
-                    t.duration = duration
-                    t.caster = "anybody"
-                    t.v1 = spell
-                    return
-                end
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.duration = 10
-            t.caster = "nobody"
-            t.v1 = 0
-        end,
-    },
-
-    feared = {
-        duration = 10,
-        generate = function( t )
-            local max_events = GetActiveLossOfControlDataCount()
-
-            if max_events > 0 then
-                local spell, start, duration, remains = 0, 0, 0, 0
-
-                for i = 1, max_events do
-                    local event = GetActiveLossOfControlData( i )
-
-                    if event and ( event.locType == "FEAR" or event.locType == "FEAR_MECHANIC" or event.locType == "HORROR" )
-                        and event.startTime and event.startTime > 0
-                        and event.timeRemaining and event.timeRemaining > 0
-                        and event.timeRemaining > remains then
-
-                        spell = event.spellID
-                        start = event.startTime
-                        duration = event.duration
-                        remains = event.timeRemaining
-                    end
-                end
-
-                if start + duration > query_time then
-                    t.count = 1
-                    t.expires = start + duration
-                    t.applied = start
-                    t.duration = duration
-                    t.caster = "anybody"
-                    t.v1 = spell
-                    return
-                end
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.duration = 10
-            t.caster = "nobody"
-            t.v1 = 0
-        end,
-    },
-
-    incapacitated = {  -- Effects like Sap, Freezing Trap, Gouge
-        duration = 10,
-        generate = function( t )
-            local max_events = GetActiveLossOfControlDataCount()
-
-            if max_events > 0 then
-                local spell, start, duration, remains = 0, 0, 0, 0
-
-                for i = 1, max_events do
-                    local event = GetActiveLossOfControlData( i )
-
-                    if event and event.locType == "STUN"
-                        and event.startTime and event.startTime > 0
-                        and event.timeRemaining and event.timeRemaining > 0
-                        and event.timeRemaining > remains then
-
-                        spell = event.spellID
-                        start = event.startTime
-                        duration = event.duration
-                        remains = event.timeRemaining
-                    end
-                end
-
-                if start + duration > query_time then
-                    t.count = 1
-                    t.expires = start + duration
-                    t.applied = start
-                    t.duration = duration
-                    t.caster = "anybody"
-                    t.v1 = spell
-                    return
-                end
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.duration = 10
-            t.caster = "nobody"
-            t.v1 = 0
-        end,
-        copy = "sapped"
-    },
-
-    rooted = {
-        duration = 10,
-        generate = function( t )
-            local max_events = GetActiveLossOfControlDataCount()
-
-            if max_events > 0 then
-                local spell, start, duration, remains = 0, 0, 0, 0
-
-                for i = 1, max_events do
-                    local event = GetActiveLossOfControlData( i )
-
-                    if event and event.locType == "ROOT" and event.startTime and event.startTime > 0 and event.timeRemaining and event.timeRemaining > 0 and event.timeRemaining > remains then
-                        spell = event.spellID
-                        start = event.startTime
-                        duration = event.duration
-                        remains = event.timeRemaining
-                    end
-                end
-
-                if start + duration > query_time then
-                    t.count = 1
-                    t.expires = start + duration
-                    t.applied = start
-                    t.duration = duration
-                    t.caster = "anybody"
-                    t.v1 = spell
-                    return
-                end
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.duration = 10
-            t.caster = "nobody"
-            t.v1 = 0
-        end,
-    },
-
-    snared = {
-        duration = 10,
-        generate = function( t )
-            local max_events = GetActiveLossOfControlDataCount()
-
-            if max_events > 0 then
-                local spell, start, duration, remains = 0, 0, 0, 0
-
-                for i = 1, max_events do
-                    local event = GetActiveLossOfControlData( i )
-
-                    if event and event.locType == "SNARE" and event.startTime and event.startTime > 0 and event.timeRemaining and event.timeRemaining > 0 and event.timeRemaining > remains then
-                        spell = event.spellID
-                        start = event.startTime
-                        duration = event.duration
-                        remains = event.timeRemaining
-                    end
-                end
-
-                if start + duration > query_time then
-                    t.count = 1
-                    t.expires = start + duration
-                    t.applied = start
-                    t.duration = duration
-                    t.caster = "anybody"
-                    t.v1 = spell
-                    return
-                end
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.duration = 10
-            t.caster = "nobody"
-            t.v1 = 0
-        end,
-        copy = "slowed"
-    },
-
-    stunned = {  -- Shorter stuns (e.g., Kidney Shot, Cheap Shot, Bash)
-        duration = 10,
-        generate = function( t )
-            local max_events = GetActiveLossOfControlDataCount()
-
-            if max_events > 0 then
-                local spell, start, duration, remains = 0, 0, 0, 0
-
-                for i = 1, max_events do
-                    local event = GetActiveLossOfControlData( i )
-
-                    if event and event.locType == "STUN_MECHANIC"
-                        and event.startTime and event.startTime > 0
-                        and event.timeRemaining and event.timeRemaining > 0
-                        and event.timeRemaining > remains then
-
-                        spell = event.spellID
-                        start = event.startTime
-                        duration = event.duration
-                        remains = event.timeRemaining
-                    end
-                end
-
-                if start + duration > query_time then
-                    t.count = 1
-                    t.expires = start + duration
-                    t.applied = start
-                    t.duration = duration
-                    t.caster = "anybody"
-                    t.v1 = spell
-                    return
-                end
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.duration = 10
-            t.caster = "nobody"
-            t.v1 = 0
-        end,
-    },
-
-    dispellable_curse = {
-        generate = function( t )
-            local i = 1
-            local name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
-
-            while( name ) do
-                if debuffType == "Curse" then break end
-
-                i = i + 1
-                name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
-            end
-
-            if name then
-                t.count = count > 0 and count or 1
-                t.expires = expirationTime > 0 and expirationTime or query_time + 5
-                t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
-                t.caster = "nobody"
-                return
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.caster = "nobody"
-        end,
-    },
-
-    dispellable_poison = {
-        generate = function( t )
-            local i = 1
-            local name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
-
-            while( name ) do
-                if debuffType == "Poison" then break end
-
-                i = i + 1
-                name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
-            end
-
-            if name then
-                t.count = count > 0 and count or 1
-                t.expires = expirationTime > 0 and expirationTime or query_time + 5
-                t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
-                t.caster = "nobody"
-                return
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.caster = "nobody"
-        end,
-    },
-
-    dispellable_disease = {
-        generate = function( t )
-            local i = 1
-            local name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
-
-            while( name ) do
-                if debuffType == "Disease" then break end
-
-                i = i + 1
-                name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
-            end
-
-            if name then
-                t.count = count > 0 and count or 1
-                t.expires = expirationTime > 0 and expirationTime or query_time + 5
-                t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
-                t.caster = "nobody"
-                return
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.caster = "nobody"
-        end,
-    },
-
-    dispellable_magic = {
-        generate = function( t, auraType )
-            if auraType == "buff" then
-                local i = 1
-                local name, _, count, debuffType, duration, expirationTime, _, canDispel = UnitBuff( "target", i )
-
-                while( name ) do
-                    if debuffType == "Magic" and canDispel then break end
-
-                    i = i + 1
-                    name, _, count, debuffType, duration, expirationTime, _, canDispel = UnitBuff( "target", i )
-                end
-
-                if canDispel then
-                    t.count = count > 0 and count or 1
-                    t.expires = expirationTime > 0 and expirationTime or query_time + 5
-                    t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
-                    t.caster = "nobody"
-                    return
-                end
-
-            else
-                local i = 1
-                local name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
-
-                while( name ) do
-                    if debuffType == "Magic" then break end
-
-                    i = i + 1
-                    name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
-                end
-
-                if name then
-                    t.count = count > 0 and count or 1
-                    t.expires = expirationTime > 0 and expirationTime or query_time + 5
-                    t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
-                    t.caster = "nobody"
-                    return
-                end
-
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.caster = "nobody"
-        end,
-    },
-
-    stealable_magic = {
-        generate = function( t )
-            if UnitCanAttack( "player", "target" ) then
-                local i = 1
-                local name, _, count, debuffType, duration, expirationTime, _, canDispel = UnitBuff( "target", i )
-
-                while( name ) do
-                    if debuffType == "Magic" and canDispel then break end
-
-                    i = i + 1
-                    name, _, count, debuffType, duration, expirationTime, _, canDispel = UnitBuff( "target", i )
-                end
-
-                if canDispel then
-                    t.count = count > 0 and count or 1
-                    t.expires = expirationTime > 0 and expirationTime or query_time + 5
-                    t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
-                    t.caster = "nobody"
-                    return
-                end
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.caster = "nobody"
-        end,
-    },
-
-    reversible_magic = {
-        generate = function( t )
-            local i = 1
-            local name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
-
-            while( name ) do
-                if debuffType == "Magic" then break end
-
-                i = i + 1
-                name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
-            end
-
-            if name then
-                t.count = count > 0 and count or 1
-                t.expires = expirationTime > 0 and expirationTime or query_time + 5
-                t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
-                t.caster = "nobody"
-                return
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.caster = "nobody"
-        end,
-    },
-
-    dispellable_enrage = {
-        generate = function( t )
-            if UnitCanAttack( "player", "target" ) then
-                local i = 1
-                local name, _, count, debuffType, duration, expirationTime, _, canDispel = UnitBuff( "target", i )
-
-                while( name ) do
-                    if debuffType == "" and canDispel then break end
-
-                    i = i + 1
-                    name, _, count, debuffType, duration, expirationTime, _, canDispel = UnitBuff( "target", i )
-                end
-
-                if canDispel then
-                    t.count = count > 0 and count or 1
-                    t.expires = expirationTime > 0 and expirationTime or query_time + 5
-                    t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
-                    t.caster = "nobody"
-                    return
-                end
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.caster = "nobody"
-        end,
-    },
-
-    all_absorbs = {
-        duration = 15,
-        max_stack = 1,
-        -- TODO: Check if function works.
-        generate = function( t, auraType )
-            local unit = auraType == "debuff" and "target" or "player"
-            local amount = UnitGetTotalAbsorbs( unit )
-
-            if amount > 0 then
-                -- t.name = ABSORB
-                t.count = 1
-                t.expires = now + 10
-                t.applied = now - 5
-                t.caster = unit
-                return
-            end
-
-            t.count = 0
-            t.expires = 0
-            t.applied = 0
-            t.caster = "nobody"
-        end,
-        copy = "unravel_absorb"
-    },
 } )
 
 do
@@ -2485,120 +1751,10 @@ all:RegisterAbilities( {
         unlisted = true,
         known = function () return true end,
     },
-
-    berserking = {
-        id = 26297,
-        cast = 0,
-        cooldown = 180,
-        gcd = "off",
-
-        toggle = "cooldowns",
-
-        -- usable = function () return race.troll end,
-        handler = function ()
-            applyBuff( "berserking" )
-        end,
-    },
 } )
 
 
--- Blood Fury spell IDs vary by class (whether you need AP/Int/both).
-local bf_classes = {
-    HUNTER = 20572,
-    MAGE = 33702,
-    ROGUE = 20572,
-    SHAMAN = 33697,
-    WARLOCK = 33702,
-    WARRIOR = 20572,
-    PRIEST = 33702
-}
-
 all:RegisterAbilities( {
-    blood_fury = {
-        id = function () return bf_classes[ class.file ] or 20572 end,
-        cast = 0,
-        cooldown = 120,
-        gcd = "off",
-
-        toggle = "cooldowns",
-
-        -- usable = function () return race.orc end,
-        handler = function ()
-            applyBuff( "blood_fury", 15 )
-        end,
-
-        copy = { 33702, 20572, 33697 },
-    },
-
-    will_to_survive = {
-        id = 59752,
-        cast = 0,
-        cooldown = 180,
-        gcd = "off",
-
-        toggle = "defensives",
-    },
-
-    shadowmeld = {
-        id = 58984,
-        cast = 0,
-        cooldown = 120,
-        gcd = "off",
-
-        usable = function ()
-            if not boss or solo then return false, "requires boss fight or group (to avoid resetting)" end
-            if moving then return false, "can't shadowmeld while moving" end
-            return true
-        end,
-
-        handler = function ()
-            applyBuff( "shadowmeld" )
-        end,
-    },
-
-
-    stoneform = {
-        id = 20594,
-        cast = 0,
-        cooldown = 120,
-        gcd = "off",
-
-        toggle = "defensives",
-
-        buff = function()
-            local aura, remains = "dispellable_poison", buff.dispellable_poison.remains
-
-            for _, effect in pairs( { "dispellable_disease", "dispellable_curse", "dispellable_magic", "dispellable_bleed" } ) do
-                local rem = buff[ effect ].remains
-                if rem > remains then
-                    aura = effect
-                    remains = rem
-                end
-            end
-
-            return aura
-        end,
-
-        handler = function ()
-            removeBuff( "dispellable_poison" )
-            removeBuff( "dispellable_disease" )
-            removeBuff( "dispellable_curse" )
-            removeBuff( "dispellable_magic" )
-            removeBuff( "dispellable_bleed" )
-
-            applyBuff( "stoneform" )
-        end,
-
-        auras = {
-            stoneform = {
-                id = 65116,
-                duration = 8,
-                max_stack = 1
-            }
-        }
-    },
-
-
     -- INTERNAL HANDLERS
     call_action_list = {
         name = "|cff00ccff[Call Action List]|r",
diff --git a/src/Hekili/Forever/Shared/Auras.lua b/src/Hekili/Forever/Shared/Auras.lua
new file mode 100644
index 00000000..c963ecd1
--- /dev/null
+++ b/src/Hekili/Forever/Shared/Auras.lua
@@ -0,0 +1,455 @@
+-- Forever/Shared/Auras.lua
+-- The auras every class shares on Forever (shared-content spec §4.1), through Engine/Shared.lua into `all`: auras others
+-- put on the player, which the player's aura walk reads in combat (lust, Power Infusion, loss of control, dispellable
+-- debuffs), and four id-less stubs for the keys core still reads by name. Retail's other lusts and lockouts, the
+-- target-side reads (a target's auras are secret in combat) and the absorbs were dropped (spec §4.1); class buffs live in
+-- their class files and racials in the race packs.
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local C_LossOfControl = ns.Facade.C_LossOfControl
+local GetActiveLossOfControlData, GetActiveLossOfControlDataCount = C_LossOfControl.GetActiveLossOfControlData, C_LossOfControl.GetActiveLossOfControlDataCount
+local UnitDebuff = ns.UnitDebuff
+
+local shared = Hekili:NewShared()
+
+local auras = {
+    -- Core reads these by name (State.lua: the cooldown read, `prowling`, the GCD's length); none exists on Forever, so
+    -- each is a stub with no ID, never up. Smaller than the core edit removing the reads (spec §4.1).
+    voidbinding = {},
+    voidform = {},
+    shadowform = {},
+    adrenaline_rush = {},
+
+    -- State.lua's cooldowns toggle override reads buff.bloodlust.up. Forever's one haste "Bloodlust" (DB2: 3 s cast, no
+    -- duration, no class): kept until the checkpoint shows what a Shaman's lust puts on the player (spec §7 Q1).
+    bloodlust = {
+        alias = { "bloodlust_actual" },
+        aliasMode = "first",
+        aliasType = "buff",
+        duration = 3600,
+    },
+
+    bloodlust_actual = {
+        id = 1245940,
+        duration = 3600, -- until cancelled (DB2 -1); the player walk reads the real expiry
+        shared = "player",
+        max_stack = 1,
+    },
+
+    -- Another Priest's on the player (State.lua's infusion toggle); 15 s on Forever (DB2).
+    power_infusion = {
+        id = 10060,
+        duration = 15,
+        max_stack = 1,
+        shared = "player",
+        dot = "buff"
+    },
+
+    loss_of_control = {
+        duration = 10,
+        generate = function( t )
+            local max_events = GetActiveLossOfControlDataCount()
+
+            if max_events > 0 then
+                local spell, start, duration, remains = 0, 0, 0, 0
+
+                for i = 1, max_events do
+                    local event = GetActiveLossOfControlData( i )
+
+                    if event and event.lockoutSchool == 0 and event.startTime and event.startTime > 0 and event.timeRemaining and event.timeRemaining > 0 and event.timeRemaining > remains then
+                        spell = event.spellID
+                        start = event.startTime
+                        duration = event.duration
+                        remains = event.timeRemaining
+                    end
+                end
+
+                if start + duration > query_time then
+                    t.count = 1
+                    t.expires = start + duration
+                    t.applied = start
+                    t.duration = duration
+                    t.caster = "anybody"
+                    t.v1 = spell
+                    return
+                end
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.duration = 10
+            t.caster = "nobody"
+            t.v1 = 0
+        end,
+    },
+
+    disoriented = {  -- Disorients (e.g., Polymorph, Dragon’s Breath, Blind)
+        duration = 10,
+        generate = function( t )
+            local max_events = GetActiveLossOfControlDataCount()
+
+            if max_events > 0 then
+                local spell, start, duration, remains = 0, 0, 0, 0
+
+                for i = 1, max_events do
+                    local event = GetActiveLossOfControlData( i )
+
+                    if event and event.locType == "CONFUSE"
+                        and event.startTime and event.startTime > 0
+                        and event.timeRemaining and event.timeRemaining > 0
+                        and event.timeRemaining > remains then
+
+                        spell = event.spellID
+                        start = event.startTime
+                        duration = event.duration
+                        remains = event.timeRemaining
+                    end
+                end
+
+                if start + duration > query_time then
+                    t.count = 1
+                    t.expires = start + duration
+                    t.applied = start
+                    t.duration = duration
+                    t.caster = "anybody"
+                    t.v1 = spell
+                    return
+                end
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.duration = 10
+            t.caster = "nobody"
+            t.v1 = 0
+        end,
+    },
+
+    feared = {
+        duration = 10,
+        generate = function( t )
+            local max_events = GetActiveLossOfControlDataCount()
+
+            if max_events > 0 then
+                local spell, start, duration, remains = 0, 0, 0, 0
+
+                for i = 1, max_events do
+                    local event = GetActiveLossOfControlData( i )
+
+                    if event and ( event.locType == "FEAR" or event.locType == "FEAR_MECHANIC" or event.locType == "HORROR" )
+                        and event.startTime and event.startTime > 0
+                        and event.timeRemaining and event.timeRemaining > 0
+                        and event.timeRemaining > remains then
+
+                        spell = event.spellID
+                        start = event.startTime
+                        duration = event.duration
+                        remains = event.timeRemaining
+                    end
+                end
+
+                if start + duration > query_time then
+                    t.count = 1
+                    t.expires = start + duration
+                    t.applied = start
+                    t.duration = duration
+                    t.caster = "anybody"
+                    t.v1 = spell
+                    return
+                end
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.duration = 10
+            t.caster = "nobody"
+            t.v1 = 0
+        end,
+    },
+
+    incapacitated = {  -- Effects like Sap, Freezing Trap, Gouge
+        duration = 10,
+        generate = function( t )
+            local max_events = GetActiveLossOfControlDataCount()
+
+            if max_events > 0 then
+                local spell, start, duration, remains = 0, 0, 0, 0
+
+                for i = 1, max_events do
+                    local event = GetActiveLossOfControlData( i )
+
+                    if event and event.locType == "STUN"
+                        and event.startTime and event.startTime > 0
+                        and event.timeRemaining and event.timeRemaining > 0
+                        and event.timeRemaining > remains then
+
+                        spell = event.spellID
+                        start = event.startTime
+                        duration = event.duration
+                        remains = event.timeRemaining
+                    end
+                end
+
+                if start + duration > query_time then
+                    t.count = 1
+                    t.expires = start + duration
+                    t.applied = start
+                    t.duration = duration
+                    t.caster = "anybody"
+                    t.v1 = spell
+                    return
+                end
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.duration = 10
+            t.caster = "nobody"
+            t.v1 = 0
+        end,
+        copy = "sapped"
+    },
+
+    rooted = {
+        duration = 10,
+        generate = function( t )
+            local max_events = GetActiveLossOfControlDataCount()
+
+            if max_events > 0 then
+                local spell, start, duration, remains = 0, 0, 0, 0
+
+                for i = 1, max_events do
+                    local event = GetActiveLossOfControlData( i )
+
+                    if event and event.locType == "ROOT" and event.startTime and event.startTime > 0 and event.timeRemaining and event.timeRemaining > 0 and event.timeRemaining > remains then
+                        spell = event.spellID
+                        start = event.startTime
+                        duration = event.duration
+                        remains = event.timeRemaining
+                    end
+                end
+
+                if start + duration > query_time then
+                    t.count = 1
+                    t.expires = start + duration
+                    t.applied = start
+                    t.duration = duration
+                    t.caster = "anybody"
+                    t.v1 = spell
+                    return
+                end
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.duration = 10
+            t.caster = "nobody"
+            t.v1 = 0
+        end,
+    },
+
+    snared = {
+        duration = 10,
+        generate = function( t )
+            local max_events = GetActiveLossOfControlDataCount()
+
+            if max_events > 0 then
+                local spell, start, duration, remains = 0, 0, 0, 0
+
+                for i = 1, max_events do
+                    local event = GetActiveLossOfControlData( i )
+
+                    if event and event.locType == "SNARE" and event.startTime and event.startTime > 0 and event.timeRemaining and event.timeRemaining > 0 and event.timeRemaining > remains then
+                        spell = event.spellID
+                        start = event.startTime
+                        duration = event.duration
+                        remains = event.timeRemaining
+                    end
+                end
+
+                if start + duration > query_time then
+                    t.count = 1
+                    t.expires = start + duration
+                    t.applied = start
+                    t.duration = duration
+                    t.caster = "anybody"
+                    t.v1 = spell
+                    return
+                end
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.duration = 10
+            t.caster = "nobody"
+            t.v1 = 0
+        end,
+        copy = "slowed"
+    },
+
+    stunned = {  -- Shorter stuns (e.g., Kidney Shot, Cheap Shot, Bash)
+        duration = 10,
+        generate = function( t )
+            local max_events = GetActiveLossOfControlDataCount()
+
+            if max_events > 0 then
+                local spell, start, duration, remains = 0, 0, 0, 0
+
+                for i = 1, max_events do
+                    local event = GetActiveLossOfControlData( i )
+
+                    if event and event.locType == "STUN_MECHANIC"
+                        and event.startTime and event.startTime > 0
+                        and event.timeRemaining and event.timeRemaining > 0
+                        and event.timeRemaining > remains then
+
+                        spell = event.spellID
+                        start = event.startTime
+                        duration = event.duration
+                        remains = event.timeRemaining
+                    end
+                end
+
+                if start + duration > query_time then
+                    t.count = 1
+                    t.expires = start + duration
+                    t.applied = start
+                    t.duration = duration
+                    t.caster = "anybody"
+                    t.v1 = spell
+                    return
+                end
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.duration = 10
+            t.caster = "nobody"
+            t.v1 = 0
+        end,
+    },
+
+    dispellable_curse = {
+        generate = function( t )
+            local i = 1
+            local name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
+
+            while( name ) do
+                if debuffType == "Curse" then break end
+
+                i = i + 1
+                name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
+            end
+
+            if name then
+                t.count = count > 0 and count or 1
+                t.expires = expirationTime > 0 and expirationTime or query_time + 5
+                t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
+                t.caster = "nobody"
+                return
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.caster = "nobody"
+        end,
+    },
+
+    dispellable_poison = {
+        generate = function( t )
+            local i = 1
+            local name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
+
+            while( name ) do
+                if debuffType == "Poison" then break end
+
+                i = i + 1
+                name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
+            end
+
+            if name then
+                t.count = count > 0 and count or 1
+                t.expires = expirationTime > 0 and expirationTime or query_time + 5
+                t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
+                t.caster = "nobody"
+                return
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.caster = "nobody"
+        end,
+    },
+
+    dispellable_disease = {
+        generate = function( t )
+            local i = 1
+            local name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
+
+            while( name ) do
+                if debuffType == "Disease" then break end
+
+                i = i + 1
+                name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
+            end
+
+            if name then
+                t.count = count > 0 and count or 1
+                t.expires = expirationTime > 0 and expirationTime or query_time + 5
+                t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
+                t.caster = "nobody"
+                return
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.caster = "nobody"
+        end,
+    },
+
+    reversible_magic = {
+        generate = function( t )
+            local i = 1
+            local name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
+
+            while( name ) do
+                if debuffType == "Magic" then break end
+
+                i = i + 1
+                name, _, count, debuffType, duration, expirationTime = UnitDebuff( "player", i, "RAID" )
+            end
+
+            if name then
+                t.count = count > 0 and count or 1
+                t.expires = expirationTime > 0 and expirationTime or query_time + 5
+                t.applied = expirationTime > 0 and ( expirationTime - duration ) or query_time
+                t.caster = "nobody"
+                return
+            end
+
+            t.count = 0
+            t.expires = 0
+            t.applied = 0
+            t.caster = "nobody"
+        end,
+    },
+}
+
+-- The player's magic debuffs only, as reversible_magic: a target's buffs are secret in combat (spec §4.1, rule 4).
+auras.dispellable_magic = { generate = auras.reversible_magic.generate }
+
+for key, def in pairs( auras ) do
+    shared:RegisterAura( key, def )
+end
diff --git a/src/Hekili/Hekili.toc b/src/Hekili/Hekili.toc
index a2ecb589..4e4e2726 100644
--- a/src/Hekili/Hekili.toc
+++ b/src/Hekili/Hekili.toc
@@ -53,6 +53,7 @@ Events.lua
 
 Engine\Spec.lua
 Engine\Shared.lua
+Forever\Shared\Auras.lua
 Forever\Classes\Warrior.lua
 Forever\Classes\Druid.lua
 Forever\Races\Gnome.lua
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `292 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [292 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 95 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 61 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add .luacheckrc src/Hekili/Engine/Spec.lua src/Hekili/Forever/Shared/Auras.lua src/Hekili/Hekili.toc tests/Forever/shared_spec.lua
git commit -m "feat(shared): Forever/Shared/Auras.lua; retail's lusts, lockouts, racials and target reads leave all (shared-content spec §4.1, §4.2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                          # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-shared`

---
### Task 4: `Forever/Shared/Consumables.lua` and Core.lua's potion fallback

Spec §4.3, named core edit E1. `Consumables.lua` registers `fake_potion` and the `potion` alias (State.lua mirrors a potion's aura to it), the `potion` verb (copy `potion_default`) without retail's default item 191387: its `item` answers only a chosen potion's, and it is unusable while no Forever potion is registered; and `healthstone` from the 15 Forever Healthstone items, highest heal first, its `item` the best one in the bags (Minor when none, for the keybind and icon lookups), 120 s (Q5), off the GCD, its `usable` gate kept without `talent.pact_of_gluttony`, its `readyTime` dropped (State.lua reads an item action's cooldown through `GetItemCooldown( item )`). Neither has a `now` (spec §4.3). The empty `exp_potions` loop and its `reset_precast` hook go. In `Core.lua` the `potion` verb no longer falls back to `"tempered_potion"`: no chosen potion gives `wait`, as before.

**Files:**
- Create: `src/Hekili/Forever/Shared/Consumables.lua`
- Modify: `src/Hekili/Engine/Spec.lua` (the potion block, `healthstone`, unused locals), `src/Hekili/Core.lua` (E1), `src/Hekili/Hekili.toc` (after `Forever\Shared\Auras.lua`)
- Test: `tests/Forever/shared_spec.lua`

**Interfaces:**
- Consumes: `Hekili:NewShared()`, `ns.Facade.C_Item.GetItemCount`/`IsUsableItem`.
- Produces: in `all`: `potion` (and `potion_default`), `healthstone`, auras `fake_potion`, `potion`.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/tests/Forever/shared_spec.lua b/tests/Forever/shared_spec.lua
index 3004702b..517a653c 100644
--- a/tests/Forever/shared_spec.lua
+++ b/tests/Forever/shared_spec.lua
@@ -32,6 +32,11 @@ local DROPPED = {
     "dispellable_enrage",
     "all_absorbs",
     "unravel_absorb",
+    -- retail's consumables: Tempered Potion, Pact of Gluttony's Healthstone and talent
+    "tempered_potion",
+    "191387",
+    "224464",
+    "pact_of_gluttony",
 }
 -- Keys core reads by name (State.lua): id-less stubs in Forever/Shared/Auras.lua, never up.
 local STUBS = { "voidbinding", "voidform", "shadowform", "adrenaline_rush" }
@@ -59,7 +64,7 @@ local function names(src, key)
 end
 
 describe("shared content", function()
-    local all, ns, saved, debuffs
+    local all, ns, saved, debuffs, bags
 
     -- Runs Engine/Races.lua, Engine/Shared.lua and the named shared files (default: every one Hekili.toc lists) against
     -- a stand-in `all` that registers as Engine/Spec.lua's RegisterAbility/RegisterAura: under the key, its id and
@@ -83,9 +88,17 @@ describe("shared content", function()
             register(self.auras, key, def)
         end
         _G.Hekili = { State = { race_token = "BloodElf" }, Class = { specs = { [0] = all }, file = "WARRIOR" } }
-        debuffs = {}
+        debuffs, bags = {}, {}
         ns = {
             Facade = {
+                C_Item = {
+                    GetItemCount = function(id)
+                        return bags[id] or 0
+                    end,
+                    IsUsableItem = function()
+                        return true
+                    end,
+                },
                 C_LossOfControl = {
                     GetActiveLossOfControlData = function() end,
                     GetActiveLossOfControlDataCount = function()
@@ -183,6 +196,29 @@ describe("shared content", function()
         end
     end)
 
+    it("registers the potion action and auras core reads, and the Healthstone from Forever's items only", function()
+        load({ "Consumables" })
+        assert.are.same({ "healthstone", "potion" }, keys("abilities"))
+        assert.are.same({ "fake_potion", "potion" }, keys("auras"))
+        assert.are.equal(all.abilities.potion, all.abilities.potion_default)
+        assert.are.same({ "fake_potion" }, all.auras.potion.alias)
+        assert.are.same(
+            { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 },
+            all.abilities.healthstone.items
+        )
+        assert.are.same({ 120, "off" }, { all.abilities.healthstone.cooldown, all.abilities.healthstone.gcd })
+        assert.is_nil(all.abilities.healthstone.now or all.abilities.potion.now) -- item actions: no cast the belief sees
+        assert.is_false(names(read("src/Hekili/Core.lua"), "tempered_potion")) -- the `potion` verb's old fallback
+    end)
+
+    it("uses the best Healthstone in the bags, and the Minor one when there is none", function()
+        load({ "Consumables" })
+        local item = all.abilities.healthstone.item
+        assert.are.equal(5512, item())
+        bags[5509], bags[19007] = 1, 2
+        assert.are.equal(5509, item())
+    end)
+
     it("leaves no dropped key in a priority, a class, race, engine or shared file, and no stub outside its own", function()
         local ls = assert(io.popen("find src/Hekili/Engine src/Hekili/Forever tools/packs -name '*.lua' | sort"))
         local n = 0
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `291 successes / 3 failures / 0 errors` (`shared_spec`: "registers the potion action ..." and "uses the best Healthstone ...": no `Forever/Shared/Consumables.lua`; "leaves no dropped key ...": `Engine/Spec.lua` names `191387`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/src/Hekili/Core.lua b/src/Hekili/Core.lua
index 033d2f3d..f4494edb 100644
--- a/src/Hekili/Core.lua
+++ b/src/Hekili/Core.lua
@@ -822,15 +822,14 @@ function Hekili:GetPredictionFromAPL( dispName, packName, listName, slot, action
                     elseif action == "potion" then
                         local usePotion = entry.potion or spec.potion
                         if not usePotion or not class.abilities[ usePotion ] then usePotion = class.specs[ specID ].options.potion end
-                        if not usePotion or not class.abilities[ usePotion ] then usePotion = "tempered_potion" end
 
-                        if not class.abilities[ usePotion ] then
+                        if not usePotion or not class.abilities[ usePotion ] then
                             action = nil
                             ability = nil
                             state.this_action = "wait"
                             state.this_list = listName
                         else
-                            action = class.abilities[ usePotion ] and class.abilities[ usePotion ].key or "tempered_potion"
+                            action = class.abilities[ usePotion ].key
                             ability = class.abilities[ action ]
                             state.this_action = action
                             state.this_list = listName
diff --git a/src/Hekili/Engine/Spec.lua b/src/Hekili/Engine/Spec.lua
index 48edc60d..c90404e0 100644
--- a/src/Hekili/Engine/Spec.lua
+++ b/src/Hekili/Engine/Spec.lua
@@ -28,10 +28,9 @@ local insert, wipe = table.insert, table.wipe
 
 local mt_resource = ns.metatables.mt_resource
 
-local GetItemCooldown = C_Item.GetItemCooldown
 local GetSpellDescription, GetSpellTexture = C_Spell.GetSpellDescription, C_Spell.GetSpellTexture
 local GetSpecialization, GetSpecializationInfo = C_SpecializationInfo.GetSpecialization, C_SpecializationInfo.GetSpecializationInfo
-local GetItemSpell, GetItemCount, IsUsableItem = C_Item.GetItemSpell, C_Item.GetItemCount, C_Item.IsUsableItem
+local GetItemSpell = C_Item.GetItemSpell
 local GetSpellInfo = C_Spell.GetSpellInfo
 
 local specTemplate = {
@@ -1591,156 +1590,6 @@ all:RegisterAuras( {
     unknown_buff = {},
 } )
 
-do
-    -- Forever potions arrive with the class files.
-    local exp_potions = {}
-
----@diagnostic disable-next-line: need-check-nil
-    all:RegisterAura( "fake_potion", {
-        duration = 30,
-        max_stack = 1,
-    } )
-
-    local first_potion, first_potion_key
-    local potion_items = {}
-
-    all:RegisterHook( "reset_precast", function ()
-        wipe( potion_items )
-        for _, potion in ipairs( exp_potions ) do
-            for _, item in ipairs( potion.items ) do
-                if GetItemCount( item, false ) > 0 then
-                    potion_items[ potion.name ] = item
-                    break
-                end
-            end
-        end
-    end )
-
-    all:RegisterAura( "potion", {
-        alias = { "fake_potion" },
-        aliasMode = "first",
-        aliasType = "buff",
-        duration = 30
-    } )
-
-    local GetItemInfo = C_Item.GetItemInfo
-
-    for _, potion in ipairs( exp_potions ) do
-        local potionItem = Item:CreateFromItemID( potion.items[ #potion.items ] )
-
-        -- all:RegisterAbility( potion.name, {} ) -- Create stub.
-
-        potionItem:ContinueOnItemLoad( function()
-            all:RegisterAbility( potion.name, {
-                name = potionItem:GetItemName(),
-                listName = potionItem:GetItemLink(),
-                cast = 0,
-                cooldown = 300,
-                gcd = "off",
-
-                startsCombat = false,
-                toggle = "potions",
-
-                item = function ()
-                    return potion_items[ potion.name ] or potion.items[ #potion.items ]
-                end,
-                items = potion.items,
-                bagItem = true,
-                texture = potionItem:GetItemIcon(),
-
-                handler = function ()
-                    applyBuff( potion.name )
-                end,
-            } )
-
-            class.abilities[ potion.name ] = all.abilities[ potion.name ]
-
-            class.potions[ potion.name ] = {
-                name = potionItem:GetItemName(),
-                link = potionItem:GetItemLink(),
-                item = potion.items[ #potion.items ]
-            }
-
-            class.potionList[ potion.name ] = "|T" .. potionItem:GetItemIcon() .. ":0|t |cff00ccff[" .. potionItem:GetItemName() .. "]|r"
-
-            for i, item in ipairs( potion.items ) do
-                if not first_potion then
-                    first_potion_key = potion.name
-                    first_potion = item
-                end
-
-                local each_potion = Item:CreateFromItemID( item )
-
-                if not each_potion:IsItemEmpty() then
-                    each_potion:ContinueOnItemLoad( function()
-                        local _, spell = GetItemSpell( item )
-
-                        if not spell then Hekili:Error( "No spell found for item %d.", item ) return false end
-
-                        if not all.auras[ potion.name ] then
-                            all:RegisterAura( potion.name, {
-                                id = spell,
-                                duration = 30,
-                                max_stack = 1,
-                                copy = { spell }
-                            } )
-
-                            class.auras[ spell ] = all.auras[ potion.name ]
-                        else
-                            local existing = all.auras[ potion.name ]
-                            if not existing.copy then existing.copy = {} end
-                            insert( existing.copy, spell )
-                            all.auras[ spell ] = all.auras[ potion.name ]
-                            class.auras[ spell ] = all.auras[ potion.name ]
-                        end
-
-                        return true
-                    end )
-                else
-                    Hekili:Error( "Item %d is empty.", item )
-                end
-            end
-        end )
-    end
-
-    all:RegisterAbility( "potion", {
-        name = "Potion",
-        listName = '|T136243:0|t |cff00ccff[Potion]|r',
-        cast = 0,
-        cooldown = 300,
-        gcd = "off",
-
-        startsCombat = false,
-        toggle = "potions",
-
-        consumable = function() return state.args.potion or settings.potion or first_potion_key end,
-        item = function()
-            if state.args.potion and class.abilities[ state.args.potion ] then return class.abilities[ state.args.potion ].item end
-            if spec.potion and class.abilities[ spec.potion ] then return class.abilities[ spec.potion ].item end
-            if first_potion and class.abilities[ first_potion ] then return class.abilities[ first_potion ].item end
-            return 191387
-        end,
-        bagItem = true,
-
-        handler = function ()
-            local use = all.abilities.potion
-            use = use and use.consumable
-
-            if use and use ~= "global_cooldown" then
-                class.abilities[ use ].handler()
-                setCooldown( use, action[ use ].cooldown )
-            end
-        end,
-
-        usable = function ()
-            return potion_items[ all.abilities.potion.item ], "no valid potions found in inventory"
-        end,
-
-        copy = "potion_default"
-    } )
-end
-
-
 all:RegisterAbilities( {
     global_cooldown = {
         id = ns.VirtualStateInternal.GCD_SPELL,
@@ -1818,38 +1667,6 @@ all:RegisterAbilities( {
         essential = true,
     },
 
-    healthstone = {
-        name = "Healthstone",
-        listName = "|T538745:0|t |cff00ccff[Healthstone]|r",
-        cast = 0,
-        cooldown = function () return time > 0 and 3600 or 60 end,
-        gcd = "off",
-
-        item = function() return talent.pact_of_gluttony.enabled and 224464 or 5512 end,
-        items = { 224464, 5512 },
-        bagItem = true,
-
-        startsCombat = false,
-        texture = function() return talent.pact_of_gluttony.enabled and 538744 or 538745 end,
-
-        usable = function ()
-            local item = talent.pact_of_gluttony.enabled and 224464 or 5512
-            if GetItemCount( item ) == 0 then return false, "requires healthstone in bags"
-            elseif not IsUsableItem( item ) then return false, "healthstone on CD"
-            elseif health.current >= health.max then return false, "must be damaged" end
-            return true
-        end,
-
-        readyTime = function ()
-            local start, duration = GetItemCooldown( talent.pact_of_gluttony.enabled and 224464 or 5512 )
-            return max( 0, start + duration - query_time )
-        end,
-
-        handler = function ()
-            gain( 0.25 * health.max, "health" )
-        end,
-    },
-
     cancel_buff = {
         name = "|cff00ccff[Cancel Buff]|r",
         listName = '|T136243:0|t |cff00ccff[Cancel Buff]|r',
diff --git a/src/Hekili/Forever/Shared/Consumables.lua b/src/Hekili/Forever/Shared/Consumables.lua
new file mode 100644
index 00000000..3008ff91
--- /dev/null
+++ b/src/Hekili/Forever/Shared/Consumables.lua
@@ -0,0 +1,103 @@
+-- Forever/Shared/Consumables.lua
+-- The consumables every class shares on Forever (shared-content spec §4.3), through Engine/Shared.lua into `all`: the
+-- `potion` action and auras core reads by name, and the Healthstone from Forever's items (DB2 1.60.1.70338: the five
+-- ranks and their Improved Healthstone variants). No Forever potion, flask or food is registered: the default
+-- priorities leave consumables out, and retail's (Tempered Potion, Pact of Gluttony's Healthstone) do not exist here.
+-- Neither action has a `now`: VirtualState sees only spell casts (an item action has no spell ID), and a Healthstone's
+-- heal is health, which the belief does not track (spec §4.3).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local C_Item = ns.Facade.C_Item
+local GetItemCount, IsUsableItem = C_Item.GetItemCount, C_Item.IsUsableItem
+
+local class = Hekili.Class
+
+local shared = Hekili:NewShared()
+
+-- State.lua's applyBuff mirrors a potion's aura to `potion`; with no Forever potion registered, `fake_potion` is the
+-- alias's only member.
+shared:RegisterAura( "fake_potion", {
+    duration = 30,
+    max_stack = 1,
+} )
+
+shared:RegisterAura( "potion", {
+    alias = { "fake_potion" },
+    aliasMode = "first",
+    aliasType = "buff",
+    duration = 30
+} )
+
+-- The APL verb `potion` (Core.lua resolves it to the chosen potion's action): an item only once a potion is chosen.
+shared:RegisterAbility( "potion", {
+    name = "Potion",
+    listName = '|T136243:0|t |cff00ccff[Potion]|r',
+    cast = 0,
+    cooldown = 300,
+    gcd = "off",
+
+    startsCombat = false,
+    toggle = "potions",
+
+    consumable = function() return state.args.potion or settings.potion end,
+    item = function()
+        if state.args.potion and class.abilities[ state.args.potion ] then return class.abilities[ state.args.potion ].item end
+        if spec.potion and class.abilities[ spec.potion ] then return class.abilities[ spec.potion ].item end
+    end,
+    bagItem = true,
+
+    handler = function ()
+        local use = class.specs[ 0 ].abilities.potion
+        use = use and use.consumable
+
+        if use and use ~= "global_cooldown" then
+            class.abilities[ use ].handler()
+            setCooldown( use, action[ use ].cooldown )
+        end
+    end,
+
+    usable = function ()
+        return false, "no Forever potion is registered"
+    end,
+
+    copy = "potion_default"
+} )
+
+-- Highest heal first: Major, Greater, Healthstone, Lesser, Minor; each as Improved Healthstone 2/2, 1/2, then plain.
+local HEALTHSTONES = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 }
+
+-- The best Healthstone in the bags (Minor when none: the keybind and icon lookups need an item).
+local function healthstone()
+    for i = 1, #HEALTHSTONES do
+        if GetItemCount( HEALTHSTONES[ i ] ) > 0 then return HEALTHSTONES[ i ] end
+    end
+    return HEALTHSTONES[ #HEALTHSTONES ]
+end
+
+shared:RegisterAbility( "healthstone", {
+    name = "Healthstone",
+    listName = "|T538745:0|t |cff00ccff[Healthstone]|r",
+    cast = 0,
+    cooldown = 120, -- Classic's shared Healthstone cooldown; the item's own is read in game (spec §7 Q5)
+    gcd = "off",
+
+    item = healthstone,
+    items = HEALTHSTONES,
+    bagItem = true,
+
+    startsCombat = false,
+
+    usable = function ()
+        local item = healthstone()
+        if GetItemCount( item ) == 0 then return false, "requires healthstone in bags"
+        elseif not IsUsableItem( item ) then return false, "healthstone on CD"
+        elseif health.current >= health.max then return false, "must be damaged" end
+        return true
+    end,
+
+    handler = function ()
+        gain( 0.25 * health.max, "health" )
+    end,
+} )
diff --git a/src/Hekili/Hekili.toc b/src/Hekili/Hekili.toc
index 4e4e2726..84016aa2 100644
--- a/src/Hekili/Hekili.toc
+++ b/src/Hekili/Hekili.toc
@@ -54,6 +54,7 @@ Events.lua
 Engine\Spec.lua
 Engine\Shared.lua
 Forever\Shared\Auras.lua
+Forever\Shared\Consumables.lua
 Forever\Classes\Warrior.lua
 Forever\Classes\Druid.lua
 Forever\Races\Gnome.lua
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `294 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [294 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 96 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 62 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Core.lua src/Hekili/Engine/Spec.lua src/Hekili/Forever/Shared/Consumables.lua src/Hekili/Hekili.toc tests/Forever/shared_spec.lua
git commit -m "feat(shared): Forever/Shared/Consumables.lua: the potion verb without a retail default, Forever's Healthstones; Core.lua's tempered_potion fallback goes (shared-content spec §4.3, E1)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                          # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-shared`

---
### Task 5: `Forever/Shared/Items.lua`

Spec §4.4. `Items.lua` registers `use_items` and, verbatim, `null_cooldown`, `trinket1`/`trinket2`/`main_hand` with their `actual_*` copies (Events.lua rebinds them on an equipment change), and sets `class.trinkets` with its `[0]` fallback (State.lua's per-item buff map; empty, no retail trinket ID was registered). The unlisted `unusable_trinket`, `setUsableItemCooldown`, `class.itemSettings`, `addItemSettings` and the commented `addUsableItem` (no reader, no caller) go. `Engine/Spec.lua`'s `all` now holds only the engine keys (spec §4.5), and its banner says so; `druid_spec`'s comment names `use_items`' new home.

**Files:**
- Create: `src/Hekili/Forever/Shared/Items.lua`
- Modify: `src/Hekili/Engine/Spec.lua` (the slot actions, the Use Items block, the item-settings helpers, `class.trinkets`, the banner), `src/Hekili/Hekili.toc` (after `Forever\Shared\Consumables.lua`), `tests/Forever/druid_spec.lua` (comment)
- Test: `tests/Forever/shared_spec.lua`

**Interfaces:**
- Consumes: `Hekili:NewShared()`, `Hekili.Class`, the client's `INVTYPE_WEAPONMAINHAND`.
- Produces: in `all`: `use_items`, `trinket1`, `trinket2`, `main_hand` (and `actual_*`), `null_cooldown`; `class.trinkets`.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/tests/Forever/shared_spec.lua b/tests/Forever/shared_spec.lua
index 517a653c..4dfc6b18 100644
--- a/tests/Forever/shared_spec.lua
+++ b/tests/Forever/shared_spec.lua
@@ -32,6 +32,7 @@ local DROPPED = {
     "dispellable_enrage",
     "all_absorbs",
     "unravel_absorb",
+    "unusable_trinket",
     -- retail's consumables: Tempered Potion, Pact of Gluttony's Healthstone and talent
     "tempered_potion",
     "191387",
@@ -132,11 +133,12 @@ describe("shared content", function()
     end
 
     before_each(function()
-        saved = rawget(_G, "Hekili") or false
+        saved = { rawget(_G, "Hekili") or false, rawget(_G, "INVTYPE_WEAPONMAINHAND") or false }
+        _G.INVTYPE_WEAPONMAINHAND = "Main Hand" -- the client's global string, read at load
     end)
 
     after_each(function()
-        _G.Hekili = saved or nil
+        _G.Hekili, _G.INVTYPE_WEAPONMAINHAND = saved[1] or nil, saved[2] or nil
     end)
 
     it("writes every registration into `all`, for any race, and the modifiers into the race packs' lists", function()
@@ -219,6 +221,27 @@ describe("shared content", function()
         assert.are.equal(5509, item())
     end)
 
+    it("registers use_items, the slots Events.lua rebinds and an empty trinket map", function()
+        load({ "Items" })
+        assert.are.same({ "main_hand", "null_cooldown", "trinket1", "trinket2", "use_items" }, keys("abilities"))
+        local a = all.abilities
+        assert.are.same({ a.trinket1, a.trinket2, a.main_hand }, { a.actual_trinket1, a.actual_trinket2, a.actual_main_hand })
+        assert.are.same({ "|cff00ccff[Main Hand]|r", false }, { a.main_hand.name, a.main_hand.usable })
+        assert.are.same({}, _G.Hekili.Class.trinkets[12345])
+    end)
+
+    it("registers each shared key in one file only, every file Hekili.toc lists", function()
+        load()
+        assert.are.same({ "Auras", "Consumables", "Items" }, SHARED)
+        for _, kind in ipairs({ "abilities", "auras" }) do
+            local seen = {}
+            for _, k in ipairs(all.keys[kind]) do
+                assert.is_nil(seen[k], kind .. ": " .. k)
+                seen[k] = true
+            end
+        end
+    end)
+
     it("leaves no dropped key in a priority, a class, race, engine or shared file, and no stub outside its own", function()
         local ls = assert(io.popen("find src/Hekili/Engine src/Hekili/Forever tools/packs -name '*.lua' | sort"))
         local n = 0
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `293 successes / 3 failures / 0 errors` (`shared_spec`: "registers use_items ...": no `Forever/Shared/Items.lua`; "registers each shared key in one file only ...": the TOC lists two shared files; "leaves no dropped key ...": `Engine/Spec.lua` names `unusable_trinket`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/src/Hekili/Engine/Spec.lua b/src/Hekili/Engine/Spec.lua
index c90404e0..57e508bd 100644
--- a/src/Hekili/Engine/Spec.lua
+++ b/src/Hekili/Engine/Spec.lua
@@ -1472,9 +1472,9 @@ end
 class.file = UnitClassBase( "player" )
 local all = Hekili:NewSpecialization( 0, "All", "Interface\\Addons\\Hekili\\Textures\\LOGO-WHITE.blp" )
 
-------------------------------
--- SHARED SPELLS/BUFFS/ETC. --
-------------------------------
+------------------------------------------------------------------------------------------------------------------------
+-- The `all` spec's engine keys: what core reads by name (the cast and movement auras, the GCD, the APL verbs). Shared game
+-- content (auras, consumables, items) is in Forever/Shared/*.lua, racials in the race packs.
 
 ---@diagnostic disable-next-line: need-check-nil
 all:RegisterAuras( {
@@ -1706,85 +1706,10 @@ all:RegisterAbilities( {
 
             removeBuff( args.buff_name )
         end,
-    },
-
-    null_cooldown = {
-        name = "|cff00ccff[Null Cooldown]|r",
-        listName = "|T136243:0|t |cff00ccff[Null Cooldown]|r",
-        cast = 0,
-        cooldown = 0.001,
-        gcd = "off",
-
-        startsCombat = false,
-
-        unlisted = true
-    },
-
-    trinket1 = {
-        name = "|cff00ccff[Trinket #1]|r",
-        listName = "|T136243:0|t |cff00ccff[Trinket #1]|r",
-        cast = 0,
-        cooldown = 600,
-        gcd = "off",
-
-        usable = false,
-
-        copy = "actual_trinket1",
-    },
-
-    trinket2 = {
-        name = "|cff00ccff[Trinket #2]|r",
-        listName = "|T136243:0|t |cff00ccff[Trinket #2]|r",
-        cast = 0,
-        cooldown = 600,
-        gcd = "off",
-
-        usable = false,
-
-        copy = "actual_trinket2",
-    },
-
-    main_hand = {
-        name = "|cff00ccff[" .. INVTYPE_WEAPONMAINHAND .. "]|r",
-        listName = "|T136243:0|t |cff00ccff[" .. INVTYPE_WEAPONMAINHAND .. "]|r",
-        cast = 0,
-        cooldown = 600,
-        gcd = "off",
-
-        usable = false,
-
-        copy = "actual_main_hand",
     }
 } )
 
 
--- Use Items
-do
-    -- Should handle trinkets/items internally.
-    -- 1.  Check APLs and don't try to recommend items that have their own APL entries.
-    -- 2.  Respect item preferences registered in spec options.
-
-    all:RegisterAbility( "use_items", {
-        name = "Use Items",
-        listName = "|T136243:0|t |cff00ccff[Use Items]|r",
-        cast = 0,
-        cooldown = 120,
-        gcd = "off",
-    } )
-
-    all:RegisterAbility( "unusable_trinket", {
-        name = "Unusable Trinket",
-        listName = "|T136240:0|t |cff00ccff[Unusable Trinket]|r",
-        cast = 0,
-        cooldown = 180,
-        gcd = "off",
-
-        usable = false,
-        unlisted = true
-    } )
-end
-
-
 ns.addToggle = function( name, default, optionName, optionDesc )
 
     table.insert( class.toggles, {
@@ -1920,89 +1845,6 @@ ns.modifyElement = modifyElement
 
 
 
-local function setUsableItemCooldown( cd )
-    state.setCooldown( "usable_items", cd or 10 )
-end
-
-
--- For Trinket Settings.
-class.itemSettings = {}
-
-local function addItemSettings( key, itemID, options )
-
-    options = options or {}
-
-    --[[ options.icon = {
-        type = "description",
-        name = function () return select( 2, GetItemInfo( itemID ) ) or format( "[%d]", itemID )  end,
-        order = 1,
-        image = function ()
-            local tex = select( 10, GetItemInfo( itemID ) )
-            if tex then
-                return tex, 50, 50
-            end
-            return nil
-        end,
-        imageCoords = { 0.1, 0.9, 0.1, 0.9 },
-        width = "full",
-        fontSize = "large"
-    } ]]
-
-    options.disabled = {
-        type = "toggle",
-        name = function () return format( "Disable %s via |cff00ccff[Use Items]|r", select( 2, GetItemInfo( itemID ) ) or ( "[" .. itemID .. "]" ) ) end,
-        desc = function( info )
-            local output = "If disabled, the addon will not recommend this item via the |cff00ccff[Use Items]|r action.  " ..
-                "You can still manually include the item in your action lists with your own tailored criteria."
-            return output
-        end,
-        order = 25,
-        width = "full"
-    }
-
-    options.minimum = {
-        type = "range",
-        name = "Minimum Targets",
-        desc = "The addon will only recommend this trinket (via |cff00ccff[Use Items]|r) when there are at least this many targets available to hit.",
-        order = 26,
-        width = "full",
-        min = 1,
-        max = 10,
-        step = 1
-    }
-
-    options.maximum = {
-        type = "range",
-        name = "Maximum Targets",
-        desc = "The addon will only recommend this trinket (via |cff00ccff[Use Items]|r) when there are no more than this many targets detected.\n\n" ..
-            "This setting is ignored if set to 0.",
-        order = 27,
-        width = "full",
-        min = 0,
-        max = 10,
-        step = 1
-    }
-
-    class.itemSettings[ itemID ] = {
-        key = key,
-        name = function () return select( 2, GetItemInfo( itemID ) ) or ( "[" .. itemID .. "]" ) end,
-        item = itemID,
-        options = options,
-    }
-
-end
-
-
---[[ local function addUsableItem( key, id )
-    class.items = class.items or {}
-    class.items[ key ] = id
-
-    addGearSet( key, id )
-    addItemSettings( key, id )
-end
-ns.addUsableItem = addUsableItem ]]
-
-
 function Hekili:GetAbilityInfo( index )
 
     local ability = class.abilities[ index ]
@@ -2388,16 +2230,3 @@ do
         end )
     end
 end
-
-
-class.trinkets = {
-    [0] = { -- for when nothing is equipped.
-    },
-}
-
-
-setmetatable( class.trinkets, {
-    __index = function( t, k )
-    return t[0]
-end
-} )
diff --git a/src/Hekili/Forever/Shared/Items.lua b/src/Hekili/Forever/Shared/Items.lua
new file mode 100644
index 00000000..8dc97dc6
--- /dev/null
+++ b/src/Hekili/Forever/Shared/Items.lua
@@ -0,0 +1,90 @@
+-- Forever/Shared/Items.lua
+-- The equipped-item actions every class shares (shared-content spec §4.4), through Engine/Shared.lua into `all`:
+-- `use_items` (the APL verb Core.lua expands into the equipped trinkets) and the slots Events.lua rebinds on an equipment
+-- change (trinket1, trinket2, main_hand; null_cooldown while a slot has no on-use), and class.trinkets, State.lua's
+-- per-item buff map (empty: no Forever trinket is modelled). Hekili's unused item-settings helpers and its unlisted
+-- unusable-trinket stub were dropped.
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local class = Hekili.Class
+
+local shared = Hekili:NewShared()
+
+-- Should handle trinkets/items internally.
+-- 1.  Check APLs and don't try to recommend items that have their own APL entries.
+-- 2.  Respect item preferences registered in spec options.
+
+shared:RegisterAbility( "use_items", {
+    name = "Use Items",
+    listName = "|T136243:0|t |cff00ccff[Use Items]|r",
+    cast = 0,
+    cooldown = 120,
+    gcd = "off",
+} )
+
+local items = {
+    null_cooldown = {
+        name = "|cff00ccff[Null Cooldown]|r",
+        listName = "|T136243:0|t |cff00ccff[Null Cooldown]|r",
+        cast = 0,
+        cooldown = 0.001,
+        gcd = "off",
+
+        startsCombat = false,
+
+        unlisted = true
+    },
+
+    trinket1 = {
+        name = "|cff00ccff[Trinket #1]|r",
+        listName = "|T136243:0|t |cff00ccff[Trinket #1]|r",
+        cast = 0,
+        cooldown = 600,
+        gcd = "off",
+
+        usable = false,
+
+        copy = "actual_trinket1",
+    },
+
+    trinket2 = {
+        name = "|cff00ccff[Trinket #2]|r",
+        listName = "|T136243:0|t |cff00ccff[Trinket #2]|r",
+        cast = 0,
+        cooldown = 600,
+        gcd = "off",
+
+        usable = false,
+
+        copy = "actual_trinket2",
+    },
+
+    main_hand = {
+        name = "|cff00ccff[" .. INVTYPE_WEAPONMAINHAND .. "]|r",
+        listName = "|T136243:0|t |cff00ccff[" .. INVTYPE_WEAPONMAINHAND .. "]|r",
+        cast = 0,
+        cooldown = 600,
+        gcd = "off",
+
+        usable = false,
+
+        copy = "actual_main_hand",
+    },
+}
+
+for key, def in pairs( items ) do
+    shared:RegisterAbility( key, def )
+end
+
+class.trinkets = {
+    [0] = { -- for when nothing is equipped.
+    },
+}
+
+setmetatable( class.trinkets, {
+    __index = function( t, k )
+    return t[0]
+end
+} )
diff --git a/src/Hekili/Hekili.toc b/src/Hekili/Hekili.toc
index 84016aa2..d6cd43c9 100644
--- a/src/Hekili/Hekili.toc
+++ b/src/Hekili/Hekili.toc
@@ -55,6 +55,7 @@ Engine\Spec.lua
 Engine\Shared.lua
 Forever\Shared\Auras.lua
 Forever\Shared\Consumables.lua
+Forever\Shared\Items.lua
 Forever\Classes\Warrior.lua
 Forever\Classes\Druid.lua
 Forever\Races\Gnome.lua
diff --git a/tests/Forever/druid_spec.lua b/tests/Forever/druid_spec.lua
index c683b676..0f808dba 100644
--- a/tests/Forever/druid_spec.lua
+++ b/tests/Forever/druid_spec.lua
@@ -628,7 +628,7 @@ describe("Forever Druid", function()
     it("writes priorities that name only registered abilities, auras, talents, settings and lists", function()
         local packs = assert(loadfile("tools/make_pack.lua"))("lists", "druid")
         local secretToken = require("Virtual.State.helpers.load").module().VirtualState.AplSecretToken
-        local shared = { use_items = true } -- Hekili's `all` (Engine/Spec.lua's use_items)
+        local shared = { use_items = true } -- Hekili's `all` (Forever/Shared/Items.lua's use_items)
         local kinds = {
             buff = w.auras,
             debuff = w.auras,
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `296 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [296 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 97 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 63 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Engine/Spec.lua src/Hekili/Forever/Shared/Items.lua src/Hekili/Hekili.toc tests/Forever/druid_spec.lua tests/Forever/shared_spec.lua
git commit -m "feat(shared): Forever/Shared/Items.lua: use_items, the slot actions, null_cooldown, class.trinkets; the dead item-settings helpers go (shared-content spec §4.4)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                          # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-shared`

---
### Task 6: CHECKPOINT: shared content in game (Q0-Q8)

Spec §7. No code unless an answer calls for it; an answer that changes code is its own commit with the verification block (and, for a drop, the key joins `shared_spec`'s list). The user plays any class at a training dummy, ForeverProbe loaded, the client on the branch Task 5 pushed. New and moved files are in the TOC: a full client restart, not a `/reload`. Q0 first (the load); Q1 next (the research's question 4, the aura entry fields: its answer can drop a family); then Q2-Q8 in any order (Q2/Q3 need a Shaman's lust, Q6/Q8 a Night Elf, Q7 an absorb).

- [ ] **Step 1: Point the client at the branch**

```bash
git push origin forever-shared
git -C ~/src/hekili checkout --detach forever-shared
```

Then a full client restart (the AddOns link points at `src/Hekili`, `docs/dev/layout.md`).

- [ ] **Step 2: CHECKPOINT: stop and ask the user to run the following in game, and report each answer**

| # | R | Question | Line | Answer → action |
|---|---|---|---|---|
| Q0 | - | the shared files load | `/run local a=Hekili.Class.specs[0] VSCopy(a.auras.loss_of_control~=nil,a.abilities.healthstone~=nil,a.abilities.use_items~=nil,Hekili.Class.abilities.global_cooldown.id)` | `true true true 29515` → none; else stop and report the error |
| Q1 | 4 | are `sourceUnit`, `isFromPlayerOrPlayerPet`, `dispelName` plain on the player's entries in combat | in combat with a buff and a debuff: `/run local a,b=C_UnitAuras.GetAuraDataByIndex("player",1,"HELPFUL"),C_UnitAuras.GetAuraDataByIndex("player",1,"HARMFUL") VSCopy(a and a.sourceUnit,a and a.isFromPlayerOrPlayerPet,b and b.spellId,b and b.dispelName)` | plain → none; `dispelName` `S` → drop `dispellable_*` and `reversible_magic` from Shared/Auras (and Stoneform's gate in Dwarf.lua), keys to the drop list; source fields `S` → none (no shared aura reads them), recorded |
| Q2 | 1 | the aura a Shaman's lust puts on the player | with it up: `/run for i=1,40 do local a=C_UnitAuras.GetAuraDataByIndex("player",i,"HELPFUL") if not a then break end VSCopy(i,a.spellId,a.name,a.duration) end` | 1245940 → none; another ID → `bloodlust_actual.id` and its duration; no lust on Forever → `bloodlust_actual` dropped, `bloodlust` an id-less stub |
| Q3 | 2 | a lockout debuff after the lust | within a minute: the same walk with `"HARMFUL"` | none → none; an ID → a `sated` aura in Shared/Auras (it leaves the drop list) |
| Q4 | 3 | the GCD constant answers | right after a GCD ability: `/run local c=C_Spell.GetSpellCooldown(29515) VSCopy(c and c.startTime,c and c.duration,GetTime(),Hekili.State.cooldown.global_cooldown.duration)` | a 1.5 (1.0 in Cat) duration, `S` in combat with Hekili's number plain → none; nil → stop: `I.GCD_SPELL` is wrong |
| Q5 | 5 | an item cooldown in combat, and the Healthstone's length | after a Healthstone in combat: `/run for _,i in ipairs({19013,19012,9421,19011,19010,5510,19009,19008,5509,19007,19006,5511,19005,19004,5512}) do if C_Item.GetItemCount(i)>0 then VSCopy(i,C_Item.GetItemCooldown(i)) end end` | plain, 120 → none; another length → `cooldown`; `S` → stop and report: State.lua's item cooldown read needs a hybrid facade row (outside this pass) |
| Q6 | 6 | Shadowmeld's aura ID | while Shadowmelded: `/run for i=1,40 do local a=C_UnitAuras.GetAuraDataByIndex("player",i,"HELPFUL") if not a then break end if a.name=="Shadowmeld" then VSCopy(a.spellId) end end` | 20580 → none; another → NightElf.lua's aura `id` |
| Q7 | 7 | the absorb total in combat | under an absorb: `/run VSCopy(UnitGetTotalAbsorbs("player"))` | either → none (`all_absorbs` stays dropped: no reader); recorded for a revival |
| Q8 | 8 | Shadowmeld's owner | as a Night Elf: `/run local s=Hekili.Class.abilities.shadowmeld VSCopy(s and s.id,s and s.cooldown)` | `20580 10` → none (closed by `forever-races`: the race pack owns it, R2); else report |

Known limits (say them with the results): no Forever potion is registered, so the `potion` verb waits; trinket effects are not modelled (`class.trinkets` is empty); target-side dispels, purges, enrage removal and absorbs are gone (rule R4); the four stubbed keys are never up (spec §4.1).

Fix what the user reports, then repeat the affected items. Continue only when the user confirms. Then `git push origin forever-shared`. When the session ends: `git -C ~/src/hekili checkout forever`.

---

## Self-Review

**1. Coverage of the spec**

| Spec | Task |
|---|---|
| §3 the rename, `Hekili:NewShared` | 1 (the object's four calls tested in 3) |
| §4.1 auras: stubs, lust, Power Infusion, loss of control, dispels; drops | 3 |
| §4.2 racials out of `all` | 3 |
| §4.3 consumables, no `now`; E1 | 4 |
| §4.4 items, dead helpers | 5 |
| §4.5 engine keys stay | 3-5 (what is left in `Engine/Spec.lua`; the banner in 5) |
| §5 the GCD constant, the facade rows; E2 | 2 |
| §7 checkpoint | 6 |
| §8 tests | 2-5 |

**2. Placeholder scan:** no "TBD", "TODO", "implement later" or "similar to Task N"; Tasks 1-5 are `git apply` patches generated by the replay and every command has its replay output.

**3. Names across tasks:** `Hekili:NewShared`, `Engine/Spec.lua`, `Engine/Races.lua`, `Engine/Shared.lua`, `Forever/Shared/{Auras,Consumables,Items}.lua`, `ns.VirtualStateInternal.GCD_SPELL`/`I.GCD_SPELL`, `bloodlust_actual`, `HEALTHSTONES`, `shared_spec`'s `DROPPED`/`STUBS`/`OWNERS`, the commit list per task, are spelled the same in every task and checkpoint line.

**4. Review Focus:** each line has its pinned test in the owning task (Tasks 1-5).

**Concerns for the orchestrator:** (a) The stubs keep four dead keys in `all` (spec §4.1 chose them over five State.lua hunks); the key test keeps them out of every priority, class and race file. (b) `bloodlust_actual` 1245940 is a guess from the DB2 (a 3 s cast, no duration, no class): Q2 decides it. (c) The `potion` verb is inert until a Forever potion list exists; no default priority uses it. (d) Q1 (`dispelName` secret in combat) or Q5 (an item cooldown secret in combat) would each need work outside this pass: dropping the dispellable family and Stoneform's gate, or a hybrid `C_Item.GetItemCooldown` facade row. (e) Task 2 reverses event-facade decision 7 for the GCD (the spec slot and talent read stay in the facade).
