# Hekili VirtualState Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build VirtualState inside Hekili (`ns.VirtualState`, `VirtualState/`) so that a Forever Warrior on a training dummy gets recommendations: the secret-in-combat reads are answered from state carried forward from plain observations, Hekili's own registered functions teach VirtualState what each real cast did, and the 124 plain passthroughs of `Libs/VirtualGameAPI-1.0` go back to direct calls behind a stripped facade, `ns.Facade`.

**Architecture:** Sources (the only code that touches the game, through an injected `api`) log observations `{ kind, t, a, b, c }` into a 256-slot ring; once per Hekili cycle `VirtualState.Drain` (called at the top of `Hekili.Update`, after its guards) runs the polls, folds the log in order into per-family clock values, and stops at each of our own casts to apply that cast through Hekili's `state` (offset to the cast time, read before, the simulation's own spend/cooldown/handler calls, read after) and record the differences as `modelled` samples. Accessors project the clock values to the caller's `now` into preallocated Belief records; `ns.Facade` keeps only the 51 secret, partly secret or absent names and answers them from those accessors. A real Forever Warrior class file (rage with its swing model, Battle Shout, Rend, Heroic Strike) makes the exit checkpoint runnable.

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted (headless specs under `VirtualState/spec`), luacheck, lua-language-server, `lua5.1`/`luac5.1`, the vendored LibStub, LibDeflate and AceSerializer (for `tools/make_pack.lua`), the `wowdb` CLI (Forever DB2 data, already looked up for this plan).

**Spec:** `docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md` (binding). Read with it: `docs/virtualstate-kickoff-prompt.md` (the exit criterion), `docs/research/2026-10-14-virtualstate-phase2-eventing-investigation.md` and `docs/research/2026-10-14-virtualstate-phase3-event-bus-outline.md` (deferred; §10 of the latter lists the Phase 1 edits a later event bus retires), `docs/research/2026-10-14-virtualstate-inputs/*.md`, `docs/forever-facade-notes.md`, `docs/forever-cleanup.md` (§5 questions, "How to verify"). Taco Dog Forever (TDF) is `~/src/TacoDogForever` at main 7bef7b5, read only.

## How this plan was checked

Every file in this plan was written and run before the plan was saved: the ten tasks were replayed in order on a scratch copy of the worktree at 1b68c3ea, and after each task the verification block below passed with the counts this plan states (busted successes, the read check's file count, luacheck 0 warnings, LuaLS no problems). The in-game checkpoints cannot be replayed headless; they are the user's.

## Global Constraints

- Repository `~/src/hekili`; work only in the worktree `~/src/hekili/.claude/worktrees/virtualstate-phase1`, branch `virtualstate-phase1` (at 1b68c3ea = `forever` when the plan was written). Git from WSL only. Push `virtualstate-phase1` to `origin` when a checkpoint is green; never push to `forever` or `classic`; never merge; never force-push.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, naming the model that wrote the commit, as on the previous plan; the commit commands below are written for Claude Opus 5.5.
- An implementer running on another model replaces `Claude Opus 5.5` in each commit command with its own model's name before running it.
- No LICENSE or README changes, in any repository: `Libs/VirtualGameAPI-1.0/LICENSE` and `Libs/VirtualGameAPI-1.0/README.md` stay in place when the library's code is removed (Task 8). No changes to `archive/`.
- Taco Dog Forever is read only. Clean-room direction: TDF mechanics may be ported into Hekili with credit in the file header (spec §13: "Ported from Taco Dog Forever, `<path>`"); Hekili code never flows into TDF. Files carrying `Plain`, the `issecretvalue`/`pcall` handling or another secret-value technique credit Catnip (Durts) in their header.
- Secret safety (spec §4.5): no VirtualState code compares or does arithmetic on a client value without `issecretvalue()` first, none uses `a and b or c` on a possibly-secret value, every client read in `VirtualState/Sources/` goes through `Plain(api, v)` or carries a `-- secret:` comment saying why the raw value is safe (`VirtualState/spec/secrets_spec.lua` enforces it), and no secret value leaves the sources or the facade.
- Performance (spec §2): accessors, the fold, Flush, the polls and the facade policies allocate nothing; every record and array is allocated when the tracked set is built (`VirtualState.SpecChanged`); `VirtualState/spec/alloc_spec.lua` (Task 9) asserts 0 bytes over 10,000 mixed events. No closures or tables in recurring paths.
- TOC order (spec §9): `embeds.xml`; then the VirtualState files (VirtualState.lua, ObsLog.lua, Belief.lua, the family files, `Sources\Sources.lua`, the source files, Snapshot.lua, Facade.lua), all before `Hekili.lua`; then Hekili's files; then `VirtualState\Adapter.lua` after `Core.lua`.
- Phase 1 only: nothing from the Phase 2 investigation or the Phase 3 event bus, nothing listed in spec §14 (persistence, items and gear families, synthesised events, facade caching, TDF's engine, confidence in Hekili's UI, a target-health pin).
- Tools: `BUSTED=~/src/TacoDogForever/.lua/bin/busted`, `LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck`, `lua-language-server` from `~/.local/share/mise/installs/lua-language-server/latest/bin/`, `lua5.1` and `luac5.1` from the system. All commands run from the worktree root.
- Every task ends with the verification block (busted, luacheck, `tools/check_api_reads.sh`, the api-inventory diff, LuaLS `--checklevel=Error`, `luac5.1 -p` on the touched Lua files), then a commit. The block is written out in each task with that task's expected results.
- The user runs the game. A step marked **CHECKPOINT** stops execution: the orchestrator (not a subagent) pushes the branch, points the client's checkout at it with `git -C ~/src/hekili checkout --detach virtualstate-phase1` (the main checkout is clean on `forever`; detaching leaves the branch checked out only in the worktree), asks the user to run the exact lines given, and waits for the results. When the session ends, `git -C ~/src/hekili checkout forever` restores the main checkout.
- Style: VirtualState files use the TDF layout (4 spaces, no spaces inside parentheses, 120 columns); edits to Hekili's own files keep Hekili's style (spaces inside parentheses).

## Review Focus

1. **A `/reload` in combat** (no `PLAYER_REGEN_DISABLED` follows): VirtualState must start in combat, from `InCombatLockdown()` at Start, and every belief starts wide and re-anchors (spec G5). Test: Task 1, `fold_spec` "starts in combat after a /reload in combat".
2. **A spec change while observations are held or staged** (talent swap, `SPELLS_CHANGED` re-registration): their ability, aura and resource indices name the old tracked set, so applying them to the new one would corrupt it. Expected: the rebuild drops them. Test: Task 1, `fold_spec` "drops every held and staged observation when the tracked set is rebuilt".
3. **A read for something nothing tracks** (another class's spell ID, an item spell, power type 99, a `focus` unit) reaching the facade from Hekili's generic code: it must answer in the real API's shape, never raise. Test: Task 8, `facade_spec` "answers spells, power types and units nothing tracks".
4. **Many swings with no spender**: rage stops at its maximum; `est`, `lo` and `hi` stay within [0, max] however long the pull. Test: Task 4, `resources_spec` "never believes more than the maximum".
5. **The target cleared or dying mid-fight**: what was believed about it must not stay on the next target, yet a swap back to a live target restores it. Test: Task 5, `auras_spec` "forgets the target's auras when the target is cleared or dies".

## File structure

```
VirtualState/
  VirtualState.lua        Task 1  ns.VirtualState, the internal table, Obs/ReadOf/TargetCastOf, constants, the Belief
                                  record, basis, debug rings, Tracked, Track
  ObsLog.lua              Task 1  the 256-slot ring (port of TDF Model/ObsLog.lua)
  Belief.lua              Task 1  the fold: appliers per kind, advance and settle hooks, lag clamp, the tracked-set build
  Families/Player.lua     Task 1  InCombat, Moving, Health, HealthMax, SpellHaste, TTD, the stat cache, Stat
  Families/Casts.lua      Task 3  the tracked abilities, casts in progress, cooldowns, charges, the GCD, the queue
  Families/Resources.lua  Task 4  the cost ladder, pins, regen EMA, swing steps, Power, Regen
  Families/Swing.lua      Task 4  per-hand anchors and speeds, melee haste, Swing, SwingSpeed, LastSwing, Haste
  Families/Auras.lua      Task 5  per-unit auras, target memory, AuraAt order, AuraGen, Count.WithAura
  Families/TargetCast.lua Task 5  the target's cast by castBarID
  Families/Talents.lua    Task 6  ranks by registered spell ID, TalentGen
  Families/Totems.lua     Task 6  the four totem slots
  Families/Enemies.lua    Task 6  Count.Enemies, Count.InRange
  Sources/Sources.lua     Task 1  Plain, staging, Flush, polls, the event registry, the module's frame (Start), I.feed
  Sources/Player.lua      Task 1  combat, movement, spell haste, health (poll 1.5), stats
  Sources/Spellbook.lua   Task 3  known ranks, plain costs, cooldown and GCD flag edges
  Sources/Casts.lua       Task 3  our UNIT_SPELLCAST_* events, the across-reset feeds' calls, poll 3 (swing queue)
  Sources/Power.lua       Task 4  power ticks, maxima, poll 1 (readable resources), poll 2 (usability ladder)
  Sources/Swing.lua       Task 4  PLAYER_SWING, out-of-combat speeds and haste
  Sources/Auras.lua       Task 5  the C_UnitAuras walk
  Sources/Target.lua      Task 5  target swaps and memory slots, poll 4 (target death), the target's cast events
  Sources/Talents.lua     Task 6  the C_Traits walk, poll 6
  Sources/Nameplates.lua  Task 6  plate tokens, poll 5 (enemies), poll 8 (range)
  Sources/Totems.lua      Task 6  totem reads, poll 7
  Snapshot.lua            Task 1  Snapshot()
  Facade.lua              Task 8  ns.Facade (the 51 kept names)
  Adapter.lua             Task 2  (fold-only drain), rewritten in Task 9 (apply through the spec, feeds)
  spec/helpers/           Task 1  fake_api.lua, alloc.lua, load.lua, fake_spec.lua
  spec/*_spec.lua         one per task (see each task)
Forever/Warrior.lua       Task 7  the Forever Warrior class file
tools/make_pack.lua       Task 7  the share-format priority generator
```

Hekili edits outside the folder (spec §10): `Core.lua` (the drain call, Task 2), `Classes.lua` (SpecChanged call and the spec 1491 loop break, Task 2; GCD id, Task 3), `Hekili.lua` (version gates, Task 2), `UI.lua`, `Events.lua`, `Options/Options.lua` (GCD 61304 → 29515, Task 3), `Events.lua` (`ns.updateTalents`, Task 6; the `UNIT_AURA` handler, Task 9), the 15 files with facade reads (14 Hekili files plus `VirtualState/Adapter.lua`; the revert, Task 8), `embeds.xml`, `.busted`, `.luacheckrc`, `tools/api_inventory.txt`, `tools/check_api_reads.sh`, `tools/list_api_reads.sh`, `Hekili.toc`, `.pkgmeta`, `Libs/CREDITS.md` (Task 8).

## Order and checkpoints

Tasks 1 to 10 in order. CHECKPOINT 1 ends Task 2 (the module loads, Snapshot answers, and the four passthrough probes of spec §7.7 run in combat). CHECKPOINT 2 ends Task 7 (the families in game with the real Warrior class file, before the facade fold). CHECKPOINT 3 ends Task 8 (the facade fold and the passthrough revert load cleanly). Task 10 is the Phase 1 exit criterion (spec §11) plus the G2, G3, G4, G7 and G8 checks.

Deliberately not built in Phase 1 (each needs nothing for the exit criterion; do not add them, and a review should not flag them):
- `VirtualState/spec/helpers/replay.lua` (spec §11): the golden scenarios replay inline (`swing_spec`, `resources_spec`, `casts_spec`); a helper would have no other user.
- The 0.9 (on-next-swing strike) and 0.8 (swing reset) anchors (spec §6.4): assumed unneeded, because Forever is assumed to fire `PLAYER_SWING` (weight 1.0) on every swing, a Heroic Strike swing included (unprobed: CHECKPOINT 4 item 9 checks it), and the Phase 1 kit has no swing-resetting ability. If the check shows otherwise, the swing clock simply skips that swing and the next white swing re-anchors it; the 0.9 anchor then goes to the follow-up list.
- The aura `default` sample, the spec's duration at application (spec §6.3): every application Phase 1 sees is either a plain walk read (`observed`) or a handler's `applyBuff`/`applyDebuff` through the spec (`modelled`, which already carries the spec's duration).
- `Cooldown`'s `observed` origin from out-of-combat times (spec §3.2): the times are secret only in combat, but the plain ready flags (`pinned`) and our casts (`modelled`) already bound every tracked cooldown, and the facade reads the plain flags directly.
- The totem `modelled` origin from a cast that summons one (spec §6.7): the Phase 1 kit summons no totem, and spec §5.3's read-back list has no totem field.
- Bloodrage (and any aura-gated rage over time): its regen model would need the resources family to apply aura-gated `interval`/`value` entries; the controller's ruling drops it from the Phase 1 kit (spec §10 asks only for Rend, Heroic Strike and the spenders the list picks).

Ruling applied where the spec and the brief differ: the brief says tests live under `tests/`; the spec (§9, §11) puts them in `VirtualState/spec/` and points `.busted` there. The spec is binding: `VirtualState/spec/`.

---

### Task 1: The core, the fold, the sources' plumbing, the player facts, Snapshot

**Files:**
- Create: `VirtualState/VirtualState.lua`, `VirtualState/ObsLog.lua`, `VirtualState/Belief.lua`, `VirtualState/Families/Player.lua`, `VirtualState/Sources/Sources.lua`, `VirtualState/Sources/Player.lua`, `VirtualState/Snapshot.lua`
- Create (tests): `VirtualState/spec/helpers/fake_api.lua`, `VirtualState/spec/helpers/alloc.lua`, `VirtualState/spec/helpers/load.lua`, `VirtualState/spec/helpers/fake_spec.lua`, `VirtualState/spec/obslog_spec.lua`, `VirtualState/spec/record_spec.lua`, `VirtualState/spec/fold_spec.lua`, `VirtualState/spec/secrets_spec.lua`
- Modify: `Hekili.toc` (after line 10, `embeds.xml`), `.busted`, `.luacheckrc` (after `files["Constants.lua"] = { globals = stateEnv }`, the last line)

**Interfaces:**
- Consumes: nothing (first task).
- Produces (later tasks rely on these exact names):
  - `ns.VirtualState` (`VS`): `VS.Obs` (34 kinds, TDF integers), `VS.Count` (table), `VS.SetDebug(on)`, `VS.Tracked(kind, out) -> integer`, `VS.Track(t)`, `VS.Start(api)`, `VS.Snapshot() -> string`, `VS.InCombat() -> boolean`, `VS.Moving() -> boolean`, `VS.Health(unit, now) -> Belief`, `VS.HealthMax(unit) -> number`, `VS.SpellHaste(now) -> Belief`, `VS.TTD(unit, now) -> Belief`, `VS.Stat(apiName, arg) -> 7 numbers`.
  - `ns.VirtualStateInternal` (`I`): `I.ReadOf` `{ Resource = 1, Aura = 2, TargetAura = 3, Max = 4, Regen = 6, Health = 10 }`, `I.TargetCastOf`, the constants (`I.PIN_GAP` … `I.RING`), `I.NewBelief(label) -> record`, `I.Sample(rec, origin, v, t, event)`, `I.Basis(rec)`, `I.UNKNOWN`, `I.OnBuild(fn(def, now))`, `I.OnSnapshot(fn(out, now))`, `I.TRACKED[kind]`, `I.extra` (`abilities`, `auras`, `units`, `talents`), `I.ObsLog` (`New`, `Add`, `At`, `Shift`, `Clear`), `I.log`, `I.LOG_CAP`, `I.On(kind, fn(o, t, lag))`, `I.OnAdvance(fn(from, to))`, `I.OnSettle(fn(now))`, `I.Fold(upto, stopAtCast) -> kind, a, t | nil`, `I.Settle(now)`, `I.Dt(now)`, `I.Build(def, now)`, `I.clock`, `I.built`, `I.inCombat`, `I.moving`, `I.healthMax`, `I.class`, `I.api`, `I.urgent`, `I.feed`, `I.Sources` (`S.Plain(api, v)`, `S.Stage(kind, t, a, b, c) -> boolean`, `S.Direct(kind, t, a, b, c)`, `S.Flush()`, `S.Note(name, status)`, `S.StatusOf(api, raw)`, `S.Poll(order, fn(api, t))`, `S.RunPolls(t)`, `S.On(event, unit, fn(api, t, a1..a5))`, `S.OnStart(fn(api, t))`, `S.Urgent(event)`, `S.STAGE`, `S.stN`, `S.dropped`, `S.status`).
  - The `def` table `I.Build` takes: `abilities` (ability tables with `key`, `spend`, `cooldown`, `charges`, `recharge`, `gcd`, `cast`, `onNextSwing`, `startsCombat`), `abilityIds[a]` (spell IDs, rank order), `abilitySlot[a]` (resource slot or 0), `resources` (`{ key, type, token, max, rest, swing, swingValue, regen }`), `auras`, `auraIds[j]`, `talents` (`{ key, spell, max }`), `units` (`"player"`, `"target"`, …).
  - Spec helpers: `fake_api.new() -> api, ctl` (`ctl.now`, `ctl.Tick(now)`, `ctl.Fire(event, ...)`, the answer tables), `fake_api.SECRET`; `alloc.bytes(fn, n)`; `load.files()`, `load.module() -> ns`, `load.adapter(ns, hekili)`; `fake_spec.new(swingValue) -> hekili`, `fake_spec.def(hekili) -> def`, `fake_spec.fold(ns, t)`, the IDs `fake_spec.RAGE` (1), `REND` (772), `REND_R2` (6546), `STRIKE` (78), `SHOUT` (6673).

- [ ] **Step 1: Point busted at the new specs and add the test helpers**

`.busted` (whole file; the facade library's spec keeps running until Task 8 removes it):
```lua
return {
    default = { ROOT = { "Libs/VirtualGameAPI-1.0/spec", "VirtualState/spec" }, pattern = "_spec", lpath = "./?.lua", verbose = true },
}
```

`.luacheckrc`: after the last line, `files["Constants.lua"] = { globals = stateEnv }`, add:
```lua
files["VirtualState/spec/"] = { std = "+busted" }
```

`VirtualState/spec/helpers/fake_api.lua`:

```lua
-- VirtualState/spec/helpers/fake_api.lua
-- A fake WoW client for headless VirtualState specs: every source gets the client as an injected `api`, so the specs
-- hand it this one. `ctl` sets what the game would answer; `api.frame:Fire(event, ...)` delivers an event and
-- `ctl.Tick(now)` runs the frame's OnUpdate (the staged flush). Every call the zero-allocation spec makes through it
-- allocates nothing: answers come from preallocated tables.
-- The SECRET proxy is ported from Taco Dog Forever, tests/helpers/wow.lua:16-25.
local M = {}

-- A secret value, as close to the client's as Lua 5.1 allows: comparing, ordering, arithmetic, concatenation,
-- indexing, length and tostring all fail. A boolean test can't be trapped in 5.1, so secrets_spec.lua checks
-- statically that every client read goes through Plain.
local function refuse(what)
    return function()
        error("attempt to " .. what .. " a secret value", 2)
    end
end
M.SECRET = newproxy(true)
do
    local mt = getmetatable(M.SECRET)
    mt.__eq, mt.__lt, mt.__le = refuse("compare"), refuse("compare"), refuse("compare")
    mt.__add, mt.__sub, mt.__mul, mt.__div =
        refuse("do arithmetic on"), refuse("do arithmetic on"), refuse("do arithmetic on"), refuse("do arithmetic on")
    mt.__mod, mt.__pow, mt.__unm = refuse("do arithmetic on"), refuse("do arithmetic on"), refuse("negate")
    mt.__concat, mt.__len, mt.__index = refuse("concatenate"), refuse("get the length of"), refuse("index")
    mt.__tostring = refuse("convert to a string")
end
local SECRET = M.SECRET

--- A new fake client and its control table.
function M.new()
    local ctl = {
        now = 100,
        combat = false,
        class = "WARRIOR",
        power = {}, -- [powerType] = value (SECRET for a secret read)
        powerMax = {}, -- [powerType] = max
        regen = {}, -- [powerType] = { inactive, active }
        usable = {}, -- [spellID] = { ok, short }
        known = {}, -- [spellID] = true
        cooldown = {}, -- [spellID] = { isActive = bool, isOnGCD = bool, startTime = SECRET, duration = SECRET }
        current = {}, -- [spellID] = true while queued (IsCurrentSpell)
        auras = { player = { HELPFUL = {}, HARMFUL = {} }, target = { HELPFUL = {}, HARMFUL = {} } },
        auraError = {}, -- [unit] = true: GetAuraDataByIndex raises (target in combat)
        guid = { player = "Player-1", target = "Creature-1" },
        dead = {},
        exists = { player = true, target = true },
        casting = nil, -- { startMS, endMS } for UnitCastingInfo("player")
        channel = nil,
        speed = { 2.6, nil },
        meleeHaste = 0,
        spellHaste = 0,
        health = 1000,
        healthMax = 1000,
        totems = {},
        traits = nil, -- { config = id, trees = { tree }, nodes = { [node] = info }, entries = {}, defs = {} }
        inRange = {},
        handlers = {},
    }
    local api = { ctl = ctl }

    function api.issecretvalue(v)
        return v == SECRET -- rawequal semantics: the proxy's __eq only fires between two proxies
    end
    function api.GetTime()
        return ctl.now
    end
    function api.InCombatLockdown()
        return ctl.combat
    end
    function api.UnitClassBase()
        return ctl.class
    end
    function api.UnitGUID(unit)
        return ctl.guid[unit]
    end
    function api.UnitExists(unit)
        return ctl.exists[unit] == true
    end
    function api.UnitIsDead(unit)
        return ctl.dead[unit] == true
    end
    function api.UnitCanAttack()
        return true
    end
    function api.UnitPower(_, pt)
        local v = ctl.power[pt]
        if v == nil then
            return SECRET
        end
        return v
    end
    function api.UnitPowerMax(_, pt)
        return ctl.powerMax[pt] or 100
    end
    function api.GetPowerRegenForPowerType(pt)
        local r = ctl.regen[pt]
        if not r then
            return SECRET, SECRET
        end
        return r[1], r[2]
    end
    function api.UnitHealth()
        return ctl.health
    end
    function api.UnitHealthMax()
        return ctl.healthMax
    end
    function api.UnitSpellHaste()
        return ctl.spellHaste
    end
    function api.GetMeleeHaste()
        return ctl.meleeHaste
    end
    function api.UnitAttackSpeed()
        return ctl.speed[1], ctl.speed[2]
    end
    function api.GetTotemInfo(slot)
        local t = ctl.totems[slot]
        if not t then
            return false, "", 0, 0, 0
        end
        return true, t.name, t.start, t.duration, t.icon, 1, t.spell
    end
    function api.UnitCastingInfo()
        local c = ctl.casting
        if not c then
            return nil
        end
        return "Cast", "", 0, c[1], c[2]
    end
    function api.UnitChannelInfo()
        local c = ctl.channel
        if not c then
            return nil
        end
        return "Channel", "", 0, c[1], c[2]
    end
    local stats = { 0, 0, 0, 0, 0, 0, 0 }
    local function zeros()
        return stats[1], stats[2], stats[3], stats[4], stats[5], stats[6], stats[7]
    end
    api.UnitStat, api.GetSpellBonusDamage, api.UnitAttackPower, api.UnitWeaponAttackPower = zeros, zeros, zeros, zeros
    api.UnitDamage, api.UnitArmor, api.GetMasteryEffect, api.GetCritChance = zeros, zeros, zeros, zeros
    api.GetSpellCritChance, api.GetRangedCritChance, api.GetCombatRating, api.GetCombatRatingBonus =
        zeros, zeros, zeros, zeros
    api.CR_CRIT_MELEE, api.CR_HASTE_MELEE, api.CR_CRIT_TAKEN_SPELL, api.CR_MASTERY = 10, 18, 11, 26
    api.CR_VERSATILITY_DAMAGE_DONE, api.CR_VERSATILITY_DAMAGE_TAKEN = 29, 31

    local READY = { isActive = false, isOnGCD = false, startTime = SECRET, duration = SECRET }
    local COSTS = {}
    api.C_Spell = {
        IsSpellUsable = function(id)
            local u = ctl.usable[id]
            if not u then
                return false, false
            end
            return u[1], u[2]
        end,
        GetSpellCooldown = function(id)
            return ctl.cooldown[id] or READY
        end,
        IsCurrentSpell = function(id)
            return ctl.current[id] == true
        end,
        GetSpellPowerCost = function()
            return COSTS
        end,
        IsSpellInRange = function(id, unit)
            return ctl.inRange[unit] == true
        end,
    }
    api.C_SpellBook = {
        IsSpellKnown = function(id)
            return ctl.known[id] == true
        end,
    }
    api.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            if ctl.auraError[unit] then
                error("Auras cannot be accessed when secret while tainted")
            end
            local list = ctl.auras[unit] and ctl.auras[unit][filter]
            return list and list[i]
        end,
    }
    api.C_ClassTalents = {
        GetActiveConfigID = function()
            return ctl.traits and ctl.traits.config
        end,
    }
    api.C_Traits = {
        GetConfigInfo = function()
            return ctl.traits and { treeIDs = ctl.traits.trees }
        end,
        GetTreeNodes = function()
            return ctl.traits and ctl.traits.nodeIDs
        end,
        GetNodeInfo = function(_, node)
            return ctl.traits and ctl.traits.nodes[node]
        end,
        GetEntryInfo = function(_, entry)
            return ctl.traits and { definitionID = entry }
        end,
        GetDefinitionInfo = function(def)
            return ctl.traits and { spellID = ctl.traits.defs[def] }
        end,
    }

    -- The frame: records registrations; Fire delivers an event to its OnEvent, ctl.Tick runs its OnUpdate.
    function api.CreateFrame()
        local f = { events = {}, units = {}, scripts = {} }
        function f:RegisterEvent(e)
            self.events[e] = true
        end
        function f:RegisterUnitEvent(e, u1, u2)
            self.events[e] = true
            self.units[e] = { u1, u2 }
        end
        function f:SetScript(name, fn)
            self.scripts[name] = fn
        end
        function f:Fire(event, ...)
            local fn = self.scripts.OnEvent
            if fn and self.events[event] then
                fn(self, event, ...)
            end
        end
        api.frame = f
        return f
    end
    function ctl.Tick(now)
        if now then
            ctl.now = now
        end
        local fn = api.frame and api.frame.scripts.OnUpdate
        if fn then
            fn(api.frame, 0)
        end
    end
    function ctl.Fire(event, ...)
        api.frame:Fire(event, ...)
    end
    return api, ctl
end

return M
```
`VirtualState/spec/helpers/alloc.lua`:
```lua
-- VirtualState/spec/helpers/alloc.lua
-- Measures bytes allocated by a loop with the collector stopped (spec §2 zero-allocation rule).
-- Copied as is from Taco Dog Forever, tests/helpers/alloc.lua:7-33.
local M = {}

---@param fn fun(i: integer)
---@param iterations integer
---@return number bytes
function M.bytes(fn, iterations)
    for i = 1, 200 do -- warm-up: let any lazy one-time allocation happen first
        fn(i)
    end
    local function loop(n)
        for i = 1, n do
            fn(i)
        end
    end
    collectgarbage("collect")
    collectgarbage("collect")
    collectgarbage("stop")
    -- A full collection shrinks Lua's own buffers (e.g. the stack), and the first call through the same path
    -- regrows them once: a cost per GC cycle, not per call. Absorb it through the measured path itself.
    local ok, err = pcall(loop, 1)
    local before = collectgarbage("count")
    if ok then
        ok, err = pcall(loop, iterations)
    end
    local after = collectgarbage("count")
    collectgarbage("restart")
    if not ok then
        error(err, 0)
    end
    return (after - before) * 1024
end

return M
```
`VirtualState/spec/helpers/load.lua`:
```lua
-- VirtualState/spec/helpers/load.lua
-- Loads the VirtualState files headless, in Hekili.toc order, into a fresh `ns` (each spec gets its own module
-- state). Adapter.lua needs Hekili, so it loads only through `load.adapter`.
local M = {}

--- The VirtualState files Hekili.toc lists, in order, as repository-relative paths.
function M.files()
    local out = {}
    for line in io.lines("Hekili.toc") do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line:match("^VirtualState\\") then
            out[#out + 1] = (line:gsub("\\", "/"))
        end
    end
    return out
end

--- A fresh ns with every VirtualState file but Adapter.lua loaded. `before(ns)` runs first (e.g. to set fakes).
function M.module()
    local ns = {}
    for _, path in ipairs(M.files()) do
        if not path:match("Adapter%.lua$") then
            assert(loadfile(path))("Hekili", ns)
        end
    end
    return ns
end

--- Loads Adapter.lua into `ns` with `_G.Hekili` set to `hekili` (its State, Class) for the duration.
function M.adapter(ns, hekili)
    local saved = rawget(_G, "Hekili")
    _G.Hekili = hekili
    assert(loadfile("VirtualState/Adapter.lua"))("Hekili", ns)
    _G.Hekili = saved
end

return M
```
`VirtualState/spec/helpers/fake_spec.lua`:
```lua
-- VirtualState/spec/helpers/fake_spec.lua
-- A tiny fake spec provider for headless specs: a fake `state` (offset, delay, now, the resources' `actual`,
-- `cooldown`, `buff`, `debuff`, setCooldown, spendCharges, RunHandler, HandleEvent, the queue calls) and a fake
-- `class` whose abilities' `spend` and `handler` act on that fake state, plus a fake `ns.spendResources`. It drives
-- the tracked-set build and Drain's read-before / read-after diff (spec §5) without Hekili.
local M = {}

M.RAGE = 1 -- Enum.PowerType.Rage
M.REND, M.REND_R2, M.STRIKE, M.SHOUT = 772, 6546, 78, 6673

--- A fake Hekili: { State, Class, ForceUpdate, forced }, and `spendResources` for ns. `swingValue` is rage per swing.
function M.new(swingValue)
    local state = {
        offset = 0,
        delay = 0,
        now = 0,
        combat = 0,
        resets = 0,
        history = {},
        queue = {},
        removed = {},
        swings = { mh_actual = 0, oh_actual = 0 },
        player = { updated = false },
        target = { updated = false },
        gcd = { execute = 1.5 },
        rage = { actual = 0, fcount = 3 },
        buff = {},
        debuff = {},
    }
    state.cooldown = { global_cooldown = { expires = 0, duration = 0, remains = 0 } }
    local function qt()
        return state.now + state.offset + state.delay
    end
    function state.reset()
        state.resets = state.resets + 1
        state.now = M.clock and M.clock() or state.now
        state.rage.actual = 0
    end
    function state.setCooldown(key, d)
        local cd = state.cooldown[key] or {}
        cd.duration, cd.expires = d, qt() + d
        if key == "global_cooldown" then
            cd.remains = d
        end
        state.cooldown[key] = cd
    end
    function state.spendCharges(key, n)
        state.setCooldown(key, 10)
    end
    function state.applyDebuff(key, d)
        local a = state.debuff[key] or {}
        a.applied, a.expires, a.count = qt(), qt() + d, 1
        state.debuff[key] = a
    end
    function state.applyBuff(key, d)
        local a = state.buff[key] or {}
        a.applied, a.expires, a.count = qt(), qt() + d, 1
        state.buff[key] = a
    end
    local class = {
        primaryResource = "rage",
        resources = {
            rage = {
                type = M.RAGE,
                state = { regenModel = { mainhand = { swing = "mainhand", value = swingValue or 9 } } },
            },
        },
        abilities = {},
        auras = {},
        talents = { improved_rend = { 0, 12286, 3 } },
    }
    local function ability(key, t)
        t.key, t.funcs = key, {}
        t.cast, t.cooldown, t.charges, t.recharge = t.cast or 0, t.cooldown or 0, t.charges or 1, t.recharge or 0
        class.abilities[key] = t
        class.abilities[t.id] = t
    end
    ability("rend", {
        id = M.REND,
        copy = { M.REND_R2 },
        spend = 10,
        spendType = "rage",
        startsCombat = true,
        handler = function()
            state.applyDebuff("rend", 15)
        end,
    })
    ability("heroic_strike", { id = M.STRIKE, spend = 15, spendType = "rage", gcd = "off", onNextSwing = true })
    ability("battle_shout", {
        id = M.SHOUT,
        spend = 10,
        spendType = "rage",
        handler = function()
            state.applyBuff("battle_shout", 120)
        end,
    })
    class.auras.rend = { key = "rend", id = M.REND, copy = { M.REND_R2 }, duration = 15 }
    class.auras.battle_shout = { key = "battle_shout", id = M.SHOUT, duration = 120 }
    function state:RunHandler(key)
        local a = class.abilities[key]
        if a.handler then
            a.handler()
        end
    end
    function state:HandleEvent(e)
        self.handled = e.action
        local a = class.abilities[e.action]
        state.setCooldown(e.action, a.cooldown)
        M.spend(e.action)
        self:RunHandler(e.action)
    end
    function state:RemoveSpellEvent(key, real, eType)
        table.insert(self.removed, key .. ":" .. tostring(eType))
        return true
    end
    function state:RemoveSpellEvents(key)
        table.insert(self.removed, key .. ":all")
    end
    function state:QueueEvent(key, start, finish, eType)
        table.insert(self.queue, key .. ":" .. eType)
    end
    function state:AddToHistory(key, guid)
        table.insert(self.history, key)
    end
    function M.spend(key)
        local a = class.abilities[key]
        if type(a.spend) == "number" then
            state.rage.actual = math.max(0, state.rage.actual - a.spend)
        end
    end
    local hekili = { State = state, Class = class, forced = {} }
    function hekili:ForceUpdate(event)
        self.forced[#self.forced + 1] = event
    end
    return hekili
end

--- The tracked-set definition Adapter.lua would build from M.new()'s class (for family specs without the Adapter).
function M.def(hekili)
    local class = hekili.Class
    local rage = class.resources.rage
    local mh = rage.state.regenModel.mainhand
    return {
        abilities = { class.abilities.battle_shout, class.abilities.heroic_strike, class.abilities.rend },
        abilityIds = { { M.SHOUT }, { M.STRIKE }, { M.REND, M.REND_R2 } },
        abilitySlot = { 1, 1, 1 },
        resources = { { key = "rage", type = M.RAGE, token = "RAGE", max = 100, rest = 0, swing = 1, swingValue = mh.value } },
        auras = { class.auras.battle_shout, class.auras.rend },
        auraIds = { { M.SHOUT }, { M.REND, M.REND_R2 } },
        talents = { { key = "improved_rend", spell = 12286, max = 3 } },
        units = { "player", "target" },
    }
end

--- One drain without Hekili: the polls, the fold, the settle (Adapter's Drain minus the apply).
function M.fold(ns, t)
    local I = ns.VirtualStateInternal
    I.Sources.RunPolls(t)
    I.Fold(t, false)
    I.Settle(t)
end

return M
```
- [ ] **Step 2: Write the failing specs**

`VirtualState/spec/obslog_spec.lua`:

```lua
-- VirtualState/spec/obslog_spec.lua: the observation ring (spec §4.1).
local load = require("VirtualState.spec.helpers.load")
local alloc = require("VirtualState.spec.helpers.alloc")

describe("ObsLog", function()
    local ObsLog

    before_each(function()
        ObsLog = load.module().VirtualStateInternal.ObsLog
    end)

    it("refuses a capacity below 1", function()
        assert.has_error(function()
            ObsLog.New(0)
        end)
    end)

    it("keeps observations oldest first and defaults a, b, c to 0", function()
        local log = ObsLog.New(4)
        ObsLog.Add(log, 1, 10, 5)
        ObsLog.Add(log, 2, 11, 6, 7, 8)
        assert.are.equal(2, log.n)
        local o = ObsLog.At(log, 1)
        assert.are.same({ 1, 10, 5, 0, 0 }, { o.kind, o.t, o.a, o.b, o.c })
        o = ObsLog.Shift(log)
        assert.are.equal(10, o.t)
        assert.are.equal(11, ObsLog.At(log, 1).t)
    end)

    it("drops the oldest when full and counts it", function()
        local log = ObsLog.New(3)
        for i = 1, 5 do
            ObsLog.Add(log, 1, i)
        end
        assert.are.same({ 3, 2 }, { log.n, log.dropped })
        assert.are.same({ 3, 4, 5 }, { ObsLog.At(log, 1).t, ObsLog.At(log, 2).t, ObsLog.At(log, 3).t })
        ObsLog.Clear(log)
        assert.are.equal(0, log.n)
    end)

    it("allocates nothing to add and shift", function()
        local log = ObsLog.New(256)
        assert.are.equal(
            0,
            alloc.bytes(function(i)
                ObsLog.Add(log, 1, i, 2, 3, 4)
                ObsLog.Shift(log)
            end, 10000)
        )
    end)
end)
```
`VirtualState/spec/record_spec.lua`:
```lua
-- VirtualState/spec/record_spec.lua: the Belief record, basis, debug rings, Tracked and Track (spec §2, §3.4, §3.6).
local load = require("VirtualState.spec.helpers.load")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("the Belief record", function()
    local ns, VS, I

    before_each(function()
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
    end)

    it("starts unknown with every last slot at t = 0", function()
        local r = I.NewBelief("x")
        assert.are.equal("unknown", r.basis)
        for _, o in ipairs(I.ORIGINS) do
            assert.are.same({ v = 0, t = 0, event = 0 }, r.last[o])
        end
    end)

    it("takes the default only when no other origin was written, and the newest otherwise (ties O, P, M)", function()
        local r = I.NewBelief("x")
        I.Sample(r, "default", 5, 1, 0)
        assert.are.equal("default", r.basis)
        I.Sample(r, "modelled", 6, 2, 3)
        assert.are.equal("modelled", r.basis)
        I.Sample(r, "pinned", 7, 2, 1)
        assert.are.equal("pinned", r.basis)
        I.Sample(r, "observed", 8, 2, 5)
        assert.are.equal("observed", r.basis)
        I.Sample(r, "modelled", 9, 3, 3)
        assert.are.equal("modelled", r.basis)
        assert.are.same({ v = 9, t = 3, event = 3 }, r.last.modelled)
    end)

    it("keeps at most 8 samples per origin in the debug rings, only while debug is on", function()
        I.Build(fs.def(fs.new()), 1)
        local r = I.NewBelief("x")
        assert.is_nil(r.ring)
        VS.SetDebug(true)
        for i = 1, 10 do
            I.Sample(r, "pinned", i, i, 1)
        end
        local ring = r.ring.pinned
        assert.are.equal(I.RING, #ring)
        local seen = {}
        for k = 1, I.RING do
            seen[ring[k].v] = true
        end
        assert.is_nil(seen[1])
        assert.is_true(seen[10] and seen[3])
        VS.SetDebug(false)
        assert.is_nil(r.ring)
        assert.is_truthy(VS.Snapshot():find("x est=", 1, true))
    end)

    it("fills the caller's array with the tracked IDs and clears the rest", function()
        I.TRACKED.aura = { 11, 12 }
        local out = { 1, 2, 3 }
        assert.are.equal(2, VS.Tracked("aura", out))
        assert.are.same({ 11, 12 }, out)
        assert.are.equal(0, VS.Tracked("nothing", out))
        assert.are.same({}, out)
    end)

    it("collects a pack's extra IDs for the next build", function()
        VS.Track({ abilities = { 100 }, auras = { 200, 201 }, units = { "focus" }, talents = { [9] = 8 } })
        assert.are.same({ 100 }, I.extra.abilities)
        assert.are.same({ 200, 201 }, I.extra.auras)
        assert.are.same({ "focus" }, I.extra.units)
        assert.are.equal(8, I.extra.talents[9])
    end)
end)
```
`VirtualState/spec/fold_spec.lua` (its two Review Focus cases: the rebuild drops held and staged observations; a `/reload` in combat starts in combat):
```lua
-- VirtualState/spec/fold_spec.lua: the fold, the clock and the sources' plumbing (spec §4.3, §4.4, §8).
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("the fold", function()
    local ns, VS, I, S, api, ctl

    before_each(function()
        api, ctl = fake.new()
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S = I.Sources
        I.Build(fs.def(fs.new()), 100)
        VS.Start(api)
        ctl.Tick(100) -- the start's reads into the log, then an empty log
        I.ObsLog.Clear(I.log)
    end)

    it("starts the clock at the first observation and never moves it backward", function()
        I.started = false
        S.Direct(VS.Obs.Moving, 105, 0, 1)
        I.Fold(110, false)
        assert.are.equal(105, I.clock)
        I.Settle(110)
        assert.are.equal(110, I.clock)
        assert.is_true(VS.Moving())
        S.Direct(VS.Obs.Moving, 104, 0, 0) -- late: applied at the clock, with its lag
        local lagSeen
        I.On(VS.Obs.Moving, function(o, t, lag)
            lagSeen = { t, lag }
        end)
        I.Fold(111, false)
        assert.are.same({ 110, 6 }, lagSeen)
        assert.are.equal(0, I.Dt(109))
    end)

    it("stops right after an own cast and hands it back", function()
        S.Direct(VS.Obs.Moving, 101, 0, 1)
        S.Direct(VS.Obs.CastSuccess, 102, 3)
        S.Direct(VS.Obs.Moving, 103, 0, 0)
        assert.are.same({ VS.Obs.CastSuccess, 3, 102 }, { I.Fold(110, true) })
        assert.is_true(VS.Moving())
        assert.is_nil(I.Fold(110, true))
        assert.is_false(VS.Moving())
    end)

    it("stages event observations until the next frame and puts aura reads first", function()
        ctl.Fire("PLAYER_STARTED_MOVING")
        assert.are.equal(0, I.log.n)
        S.Direct(VS.Obs.Read, 100, 1, 0, I.ReadOf.Aura)
        ctl.Tick(100.1)
        assert.are.equal(2, I.log.n)
        assert.are.equal(VS.Obs.Read, I.ObsLog.At(I.log, 1).kind)
        assert.are.equal(VS.Obs.Moving, I.ObsLog.At(I.log, 2).kind)
    end)

    it("drops staged observations past the stage cap and counts them", function()
        for _ = 1, S.STAGE + 3 - S.stN do
            S.Stage(VS.Obs.Moving, 100, 0, 1)
        end
        assert.are.equal(3, S.dropped)
    end)

    it("runs the polls in order and refuses a duplicate order", function()
        local seen = {}
        S.Poll(9.5, function()
            seen[#seen + 1] = 9.5
        end)
        S.Poll(0.5, function()
            seen[#seen + 1] = 0.5
        end)
        S.RunPolls(100)
        assert.are.same({ 0.5, 9.5 }, seen)
        assert.has_error(function()
            S.Poll(1.5, function() end) -- the player's health poll
        end)
    end)

    it("passes every event argument through Plain: a secret argument arrives as nil", function()
        local got = "unset"
        S.On("UNIT_SPELL_HASTE", "player", function(_, _, a1)
            got = a1
        end)
        ctl.Fire("UNIT_SPELL_HASTE", fake.SECRET)
        assert.is_nil(got)
    end)

    it("drops every held and staged observation when the tracked set is rebuilt (their indices are the old set's)", function()
        S.Direct(VS.Obs.Moving, 101, 0, 1)
        S.Stage(VS.Obs.Moving, 101, 0, 1)
        I.Build(fs.def(fs.new()), 102)
        ctl.Tick(102)
        for i = 1, I.log.n do -- (a rebuild may log a target swap of its own, Sources/Target.lua)
            assert.are_not.equal(VS.Obs.Moving, I.ObsLog.At(I.log, i).kind)
        end
    end)

    it("starts in combat after a /reload in combat (no PLAYER_REGEN_DISABLED comes)", function()
        local api2, ctl2 = fake.new()
        ctl2.combat = true
        local ns2 = load.module()
        ns2.VirtualStateInternal.Build(fs.def(fs.new()), 1)
        ns2.VirtualState.Start(api2)
        assert.is_true(ns2.VirtualState.InCombat())
    end)

    it("knows combat from the regen events, not InCombatLockdown", function()
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.is_true(VS.InCombat())
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.is_false(VS.InCombat())
    end)
end)
```
`VirtualState/spec/secrets_spec.lua` (port of TDF `tests/game/secrets_spec.lua`, scanning `VirtualState/Sources/`):
```lua
-- VirtualState/spec/secrets_spec.lua (spec §4.5, §11): a static check that every client read in VirtualState's
-- sources goes through Plain, or says on its line (`-- secret:`) why the raw value is safe (tested with
-- issecretvalue, or handed straight to Plain by the caller); that client functions are never aliased or
-- string-indexed; and that a raw value (a `raw...` variable) is never compared before the secrecy check.
-- Ported from Taco Dog Forever, tests/game/secrets_spec.lua.
local fake = require("VirtualState.spec.helpers.fake_api")

local DIR = "VirtualState/Sources/"

local function discover()
    local out = {}
    local p = assert(io.popen("find " .. DIR .. " -name '*.lua' | sort"))
    for path in p:lines() do
        out[#out + 1] = path
    end
    p:close()
    return out
end

-- Client functions whose answers are never secret.
local NEVER_SECRET = { GetTime = true, issecretvalue = true, CreateFrame = true }

-- Every function the fake client offers (top level and in C_* namespaces), minus the never-secret ones.
local function clientReads()
    local api = fake.new()
    local names = {}
    for k, v in pairs(api) do
        if type(v) == "function" and not NEVER_SECRET[k] then
            names[#names + 1] = k
        elseif type(v) == "table" and k:match("^C_") then
            for fk, fv in pairs(v) do
                if type(fv) == "function" then
                    names[#names + 1] = fk
                end
            end
        end
    end
    table.sort(names)
    return names
end

local function code(line)
    local comment = line:match("%-%-(.*)$") or ""
    local bare = line:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"):gsub("%-%-.*$", "")
    return bare, comment
end

local function problems(path, reads)
    local out = {}
    local function flag(n, fmt, ...)
        out[#out + 1] = string.format("%s:%d: " .. fmt, path, n, ...)
    end
    local n = 0
    for line in io.lines(path) do
        n = n + 1
        local bare, comment = code(line)
        local marked = comment:find("secret:", 1, true) ~= nil
        if line:find("%[%s*[\"'][%w_]+[\"']%s*%]%s*%(") then
            flag(n, "string-indexed call")
        end
        for _, name in ipairs(reads) do
            local s, e = bare:find("api%.[%w_.]-%f[%w_]" .. name .. "%f[^%w_]")
            while s do
                local after = bare:sub(e + 1):match("^%s*(.)")
                if after == "(" then
                    if not bare:sub(1, s - 1):find("Plain%(%s*[%w_]+%s*,%s*$") and not marked then
                        flag(n, "%s read without Plain", name)
                    end
                elseif not (after == "," and bare:find("pcall(", 1, true) and marked) then
                    flag(n, "%s aliased (call it where it's read)", name)
                end
                s, e = bare:find("api%.[%w_.]-%f[%w_]" .. name .. "%f[^%w_]", e + 1)
            end
        end
        if not marked and (bare:find("%f[%w_]raw[%w_]*%s*[=~]=") or bare:find("[=~]=%s*raw[%w_]*%f[^%w_]")) then
            flag(n, "raw value compared")
        end
    end
    return out
end

describe("secret values in VirtualState's sources (spec §4.5)", function()
    local reads = clientReads()

    it("knows the client reads from the fake client", function()
        local set = {}
        for _, r in ipairs(reads) do
            set[r] = true
        end
        for _, name in ipairs({ "IsSpellUsable", "UnitPower", "GetAuraDataByIndex", "GetSpellCooldown", "UnitGUID" }) do
            assert.is_true(set[name], name)
        end
    end)

    it("finds every source file", function()
        local files = discover()
        assert.is_true(#files >= 2, tostring(#files))
    end)

    it("every client read in the sources goes through Plain or says why not", function()
        local all = {}
        for _, path in ipairs(discover()) do
            for _, p in ipairs(problems(path, reads)) do
                all[#all + 1] = p
            end
        end
        assert.are.same({}, all)
    end)

    it("catches each kind of misuse (the check checks)", function()
        local tmp = os.tmpname()
        local f = assert(io.open(tmp, "w"))
        f:write("local n = api.UnitGUID('target')\n") -- unguarded
        f:write("local get = api.C_Spell.IsSpellUsable\n") -- aliased
        f:write('local c = api["UnitPower"](1)\n') -- string-indexed
        f:write("if rawExp ~= nil then end\n") -- a raw value compared
        f:write("local ok = Plain(api, api.UnitExists('target'))\n") -- fine
        f:write("local a = api.UnitPower(1) -- secret: Plain next\n") -- fine
        f:close()
        local text = table.concat(problems(tmp, reads), "\n")
        os.remove(tmp)
        assert.is_truthy(text:find(":1: UnitGUID read without Plain", 1, true), text)
        assert.is_truthy(text:find(":2: IsSpellUsable aliased", 1, true), text)
        assert.is_truthy(text:find(":3: string-indexed call", 1, true), text)
        assert.is_truthy(text:find(":4: raw value compared", 1, true), text)
        assert.is_falsy(text:find(":5:", 1, true), text)
        assert.is_falsy(text:find(":6:", 1, true), text)
    end)

    it("Plain asks issecretvalue before touching the value", function()
        local src = io.open(DIR .. "Sources.lua"):read("*a")
        local body = src:match("function S%.Plain%(api, v%)%s*\n(.-)\nend")
        assert.are.equal("if api.issecretvalue(v) then", body:match("^%s*(.-)\n"))
    end)

    it("the fake client's secret refuses what a real one refuses", function()
        local SECRET = fake.SECRET
        for _, op in ipairs({
            function()
                return SECRET < 1
            end,
            function()
                return SECRET + 1
            end,
            function()
                return SECRET .. "x"
            end,
            function()
                return SECRET.field
            end,
            function()
                return #SECRET
            end,
            function()
                return tostring(SECRET)
            end,
        }) do
            assert.has_error(op)
        end
    end)
end)
```
- [ ] **Step 3: Run the specs to see them fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: the 9 `VirtualGameAPI-1.0` cases pass; every new spec errors (`load.module` finds no `VirtualState\` line in `Hekili.toc` yet, so `ns.VirtualStateInternal` is nil: `attempt to index ... (a nil value)`), and `secrets_spec` fails "finds every source file".

- [ ] **Step 4: Write the module files**

`VirtualState/VirtualState.lua`:

```lua
-- VirtualState/VirtualState.lua
-- VirtualState carries the game state forward from plain observations on WoW Forever and answers the reads that are
-- secret in combat (docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md). This file: the public table
-- `ns.VirtualState`, the module's internal table, the observation enum, the Belief record and the debug rings.
-- Ported from Taco Dog Forever: src/TacoDogForever/Engine/Enum.lua (Enum.Obs, Enum.ReadOf, Enum.TargetCastOf, same
-- integers) and src/TacoDogForever/Model/Belief.lua (the est/lo/hi/conf record and its constants).

local _, ns = ...

local VS = { Count = {} }
ns.VirtualState = VS

-- The module's internals, shared by the VirtualState files only. Not a public surface.
local I = {}
ns.VirtualStateInternal = I

--- Observation kinds (spec §2): TDF's Enum.Obs, same integers. The kinds Phase 1 does not log keep their integers.
VS.Obs = {
    Usable = 1, -- a: ability index; b: 1 usable / 0 not; c: 1 not usable for lack of its resource
    CastStart = 2, -- a: ability index; b: the cast's end
    CastSuccess = 3, -- a: ability index
    CastStop = 4, -- a: ability index (failed or interrupted)
    Read = 5, -- a: resource slot or aura index (c: ReadOf); b: the exact value (amount; aura time remaining)
    Cooldown = 6, -- a: ability index; b: 1 ready / 0 not (the plain isActive flag); c: 1 the GCD flag edge
    PowerTick = 7, -- a: resource slot
    TargetSwap = 8,
    CombatStart = 9,
    CombatEnd = 10,
    Group = 11, -- reserved
    TargetGone = 12,
    Known = 13, -- reserved
    Queued = 14, -- a: ability index; b: 1 queued for the next swing / 0 not
    Swing = 15, -- a: hand (1 main, 2 off); b: swing duration or speed; c: 1 swung (PLAYER_SWING), 0 a read, 2 base speed
    Haste = 16, -- b: melee multiplier (a plain read); c: 1 melee, 2 spell (b: spell haste percent)
    Moving = 17, -- b: 1 moving / 0 not
    Talent = 18, -- a: talent index; b: its rank
    Enemies = 19, -- b: live attackable plates
    Encounter = 20, -- reserved
    TargetInfo = 21, -- reserved
    PlayerInfo = 22, -- reserved
    GameError = 23, -- reserved
    ChannelStart = 24, -- a: ability index; b: the channel's end
    ChannelStop = 25, -- a: ability index
    ChannelUpdate = 26, -- a: ability index; b: the channel's new end
    CastDelay = 27, -- a: ability index; b: the cast's new end
    PackEvent = 28, -- reserved
    Pet = 29, -- reserved
    Totem = 30, -- a: slot 1-4; b: expiry (0 empty); c: 1 an out-of-combat read, 0 an update with no read
    Gear = 31, -- reserved
    ItemCooldown = 32, -- reserved
    Range = 33, -- a: plate index; b: count in range of the range spell
    TargetCast = 34, -- a: TargetCastOf; b: castBarID; c: interruptible 1 / 0 / -1 unknown
}

--- What a `Read` observation read (its `c`): TDF's Enum.ReadOf integers (5 and 7-9 reserved), plus Health = 10, a
--- VirtualState kind past TDF's range.
I.ReadOf = { Resource = 1, Aura = 2, TargetAura = 3, Max = 4, Regen = 6, Health = 10 }

--- What a `TargetCast` observation reports (its `a`): TDF's Enum.TargetCastOf integers.
I.TargetCastOf = { Start = 1, ChannelStart = 2, End = 3, Interrupted = 4, Kickable = 5 }

-- Constants (spec §6), TDF's values (src/TacoDogForever/Model/Belief.lua:39-72; Belief/Resources.lua:26;
-- Belief/Swing.lua:46).
I.PIN_GAP = 1
I.ALPHA = 0.3
I.REGEN_SPREAD = 0.1
I.REGEN_SPREAD_MIN = 0.02
I.REGEN_RATIO = 2
I.EPS = 0.01
I.CD_PROBE = 0.5
I.SNAP_HOLD = 1
I.AURA_HALF_LIFE = 10
I.CAST_GRACE = 0.5
I.TARGET_CAP = 16
I.FALSE_START = 1
I.READ_HOLD = 2
I.SWING_DECAY = 10
I.SWING_TOL = 0.15
I.RING = 8 -- debug ring slots per origin (spec §2)

I.ORIGINS = { "observed", "pinned", "modelled", "default" }

-- Every record, with its label, in creation order (Snapshot and SetDebug walk them).
I.records, I.labels = {}, {}

local function sample()
    return { v = 0, t = 0, event = 0 }
end

--- A preallocated Belief record (spec §2). Allocates; build time only. `label` names it in Snapshot().
---@param label string
---@return table
function I.NewBelief(label)
    local rec = {
        est = 0,
        lo = 0,
        hi = 0,
        conf = 0,
        basis = "unknown",
        last = { observed = sample(), pinned = sample(), modelled = sample(), default = sample() },
    }
    local n = #I.records + 1
    I.records[n], I.labels[n] = rec, label
    if I.debug then
        I.AddRing(rec)
    end
    return rec
end

--- Forgets every record (SpecChanged rebuilds them). Build time only.
function I.ClearRecords()
    I.records, I.labels = {}, {}
end

--- Writes one sample into `rec.last[origin]` (and its debug ring when debug is on), then re-derives the basis.
--- Allocates nothing.
function I.Sample(rec, origin, v, t, event)
    local s = rec.last[origin]
    s.v, s.t, s.event = v, t, event
    local ring = rec.ring
    if ring then
        local r = ring[origin]
        r.head = r.head % I.RING + 1
        local e = r[r.head]
        e.v, e.t, e.event = v, t, event
    end
    I.Basis(rec)
end

--- The basis (spec §2): the newest of observed, pinned and modelled by t (ties in that order), else default when
--- one is in force, else "unknown". Allocates nothing.
function I.Basis(rec)
    local last = rec.last
    local o, p, m = last.observed.t, last.pinned.t, last.modelled.t
    if o == 0 and p == 0 and m == 0 then
        rec.basis = last.default.t > 0 and "default" or "unknown"
    elseif o >= p and o >= m then
        rec.basis = "observed"
    elseif p >= m then
        rec.basis = "pinned"
    else
        rec.basis = "modelled"
    end
end

--- Gives a record its debug rings: per origin, RING preallocated samples and a head index.
function I.AddRing(rec)
    local ring = {}
    for k = 1, #I.ORIGINS do
        local r = { head = 0 }
        for i = 1, I.RING do
            r[i] = sample()
        end
        ring[I.ORIGINS[k]] = r
    end
    rec.ring = ring
end

--- Creates (on) or drops (off) the debug rings of every record (spec §2, §3.5). Allocates when turned on.
---@param on boolean
function VS.SetDebug(on)
    I.debug = on and true or false
    for i = 1, #I.records do
        I.records[i].ring = nil
        if on then
            I.AddRing(I.records[i])
        end
    end
end

-- The static record an accessor returns for an entity nothing tracks: unknown, conf 0.
I.UNKNOWN = {
    est = 0,
    lo = 0,
    hi = 0,
    conf = 0,
    basis = "unknown",
    last = { observed = sample(), pinned = sample(), modelled = sample(), default = sample() },
}

-- Build hooks (families allocate their arrays and records) and the snapshot writers, in registration order.
I.BUILD, I.SNAPSHOT = {}, {}

--- Registers `fn(def, now)`, run by I.Build for every family. Load time only.
function I.OnBuild(fn)
    I.BUILD[#I.BUILD + 1] = fn
end

--- Registers `fn(out)`, which appends Snapshot() lines to `out`. Load time only.
function I.OnSnapshot(fn)
    I.SNAPSHOT[#I.SNAPSHOT + 1] = fn
end

-- What VirtualState.Tracked(kind) lists, by kind: arrays the families fill at build time.
I.TRACKED = {}

--- Fills the caller's array `out` with the tracked IDs of `kind` ("ability", "aura", "resource", "unit") and returns
--- the count. Allocates nothing.
---@param kind string
---@param out table
---@return integer
function VS.Tracked(kind, out)
    local list = I.TRACKED[kind]
    local n = list and #list or 0
    for i = 1, n do
        out[i] = list[i]
    end
    for i = n + 1, #out do
        out[i] = nil
    end
    return n
end

-- The pack exception (spec §3.6): IDs a class pack adds, merged at the next build.
I.extra = { abilities = {}, auras = {}, units = {}, talents = {} }

--- Adds IDs core does not already track: `abilities` (spell IDs: cooldown flags and usability only), `auras` (spell
--- IDs, tracked on every aura unit), `units` (unit tokens walked for auras), `talents` (alias spell ID = the talent's
--- registered spell ID). They join the tracked set at the next SpecChanged. Allocates; load time only.
---@param t table
function VS.Track(t)
    for kind, list in pairs(t) do
        local into = I.extra[kind]
        if into then
            for k, v in pairs(list) do
                if type(k) == "number" and kind ~= "talents" then
                    into[#into + 1] = v
                else
                    into[k] = v
                end
            end
        end
    end
end
```
`VirtualState/ObsLog.lua`:
```lua
-- VirtualState/ObsLog.lua
-- The observation log (spec §4.1): a preallocated ring of { kind, t, a, b, c } that sources write and only Drain
-- reads, oldest first. A full ring drops its oldest observation and counts it. Adding allocates nothing.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/ObsLog.lua (New :26, Add :44, At :63, Shift :70, Clear :79).

local _, ns = ...
local I = ns.VirtualStateInternal

local ObsLog = {}
I.ObsLog = ObsLog

--- Creates a log of `cap` preallocated observations. Load time only.
---@param cap integer
---@return table
function ObsLog.New(cap)
    if type(cap) ~= "number" or cap < 1 then
        error("VirtualState: an observation log needs a capacity of at least 1", 2)
    end
    local log = { cap = cap, head = 1, n = 0, dropped = 0, obs = {} }
    for i = 1, cap do
        log.obs[i] = { kind = 0, t = 0, a = 0, b = 0, c = 0 }
    end
    return log
end

--- Records an observation (`a`, `b`, `c` default to 0).
function ObsLog.Add(log, kind, t, a, b, c)
    local cap = log.cap
    local i
    if log.n == cap then
        i = log.head
        log.head = i % cap + 1 -- nonzero: New validates cap >= 1
        log.dropped = log.dropped + 1
    else
        i = (log.head + log.n - 1) % cap + 1 -- nonzero: New validates cap >= 1
        log.n = log.n + 1
    end
    local o = log.obs[i]
    o.kind, o.t, o.a, o.b, o.c = kind, t, a or 0, b or 0, c or 0
end

--- The i-th oldest observation held (1..log.n). The record is reused: read it, don't keep it.
function ObsLog.At(log, i)
    return log.obs[(log.head + i - 2) % log.cap + 1] -- nonzero: New validates cap >= 1
end

--- Takes the oldest observation out of the log and returns it. The record is reused: read it before the next Add.
function ObsLog.Shift(log)
    local o = log.obs[log.head]
    log.head = log.head % log.cap + 1 -- nonzero: New validates cap >= 1
    log.n = log.n - 1
    return o
end

--- Forgets every observation held.
function ObsLog.Clear(log)
    log.head = 1
    log.n = 0
end

--- The log's size: TDF's App.LOG_CAP (src/TacoDogForever/Game/App.lua:26).
I.LOG_CAP = 256
I.log = ObsLog.New(I.LOG_CAP)
```
`VirtualState/Belief.lua`:
```lua
-- VirtualState/Belief.lua
-- The fold (spec §8): applies the log's observations in order on the belief clock, with the lag clamp, then settles
-- (cooldown flags, record sync). Families register appliers per observation kind, advance hooks (carry their clock
-- values forward) and settle hooks. Also the tracked-set build (spec §3.6).
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief.lua (Update :720, the clock start :723-728, the lag
-- clamp :733-736, constrain :652, sync :687); the Writer/FinalWriter/Serial parts are not ported.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local At, Shift = I.ObsLog.At, I.ObsLog.Shift
local Obs = VS.Obs
local CAST_SUCCESS, CHANNEL_START = Obs.CastSuccess, Obs.ChannelStart

local APPLY, ADVANCE, SETTLE = {}, {}, {}

--- Registers `fn(o, t, lag)` for observations of `kind` (families, at load). `o` is the reused log record.
function I.On(kind, fn)
    local list = APPLY[kind]
    if not list then
        list = {}
        APPLY[kind] = list
    end
    list[#list + 1] = fn
end

--- Registers `fn(from, to)`, run whenever the belief clock moves forward. Load time only.
function I.OnAdvance(fn)
    ADVANCE[#ADVANCE + 1] = fn
end

--- Registers `fn(now)`, run once at the end of each fold (the standing flags and the record sync). Load time only.
function I.OnSettle(fn)
    SETTLE[#SETTLE + 1] = fn
end

I.clock, I.started = 0, false

-- Moves the belief clock to t (never backward).
local function advance(t)
    local c = I.clock
    if t > c then
        for k = 1, #ADVANCE do
            ADVANCE[k](c, t)
        end
        I.clock = t
    end
end
I.Advance = advance

--- Folds the log in order (spec §5.2 steps 2 and 3.8). With `stopAtCast`, returns right after applying an own cast
--- (CastSuccess or ChannelStart) as `kind, ability, t`; otherwise folds everything stamped at or before `upto` and
--- returns nil. An observation older than the clock is applied at the clock with `lag`. Allocates nothing.
---@param upto number
---@param stopAtCast boolean
function I.Fold(upto, stopAtCast)
    local log = I.log
    if not I.started then
        -- The clock starts at the first thing heard, not at 0 (TDF Belief.lua:723-728).
        local first = log.n > 0 and At(log, 1).t or upto
        I.clock = first < upto and first or upto
        I.started = true
    end
    while log.n > 0 do
        local o = At(log, 1)
        if o.t > upto then
            break
        end
        Shift(log)
        local t, lag = o.t, 0
        if t < I.clock then
            t, lag = I.clock, I.clock - o.t
        end
        advance(t)
        local kind = o.kind
        local list = APPLY[kind]
        if list then
            for k = 1, #list do
                list[k](o, t, lag)
            end
        end
        if stopAtCast and (kind == CAST_SUCCESS or kind == CHANNEL_START) then
            return kind, o.a, t
        end
    end
    return nil
end

--- Ends a fold: the clock to `now`, then every settle hook. Allocates nothing.
function I.Settle(now)
    advance(now)
    for k = 1, #SETTLE do
        SETTLE[k](now)
    end
end

--- The time a projection uses (spec §2 "No backward projection"): 0 for a `now` before the clock.
function I.Dt(now)
    local dt = now - I.clock
    return dt > 0 and dt or 0
end

--- Rebuilds the tracked set from `def` (spec §3.6): every family allocates its arrays and records. `def` holds
--- `abilities` (Hekili ability tables), `resources`, `auras`, `talents` and `units` (see Adapter.lua). Allocates;
--- SpecChanged only.
function I.Build(def, now)
    I.ClearRecords()
    I.ObsLog.Clear(I.log) -- held observations name the old set's indices
    if I.Sources then
        I.Sources.stN = 0 -- and so do staged ones
    end
    I.started = false
    I.clock = now
    for k = 1, #I.BUILD do
        I.BUILD[k](def, now)
    end
    I.built = true
end
```
`VirtualState/Families/Player.lua`:
```lua
-- VirtualState/Families/Player.lua
-- The player family (spec §6.5): combat and movement facts, health, spell haste, the out-of-combat stat cache and the
-- default time to die. Melee haste lives with the swing family (Families/Swing.lua), which measures it.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Player.lua (Applier Haste :130, Moving :194).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs, ReadOf = VS.Obs, I.ReadOf

I.inCombat, I.moving = false, false
I.combatT = 0

--- (spec §3.1) In combat, from PLAYER_REGEN_DISABLED/ENABLED (not InCombatLockdown, which lags).
function VS.InCombat()
    return I.inCombat
end

--- (spec §3.1) Moving, from PLAYER_STARTED_MOVING/PLAYER_STOPPED_MOVING.
function VS.Moving()
    return I.moving
end

I.On(Obs.Moving, function(o)
    I.moving = o.b == 1
end)

I.On(Obs.CombatStart, function(o, t)
    I.combatT = t
end)

-- Health (player: plain reads; every other unit: the default 1.0), spell haste, time to die.
local health, otherHealth, spellHaste, ttd
I.healthMax = 0

local function decay(rec, now)
    local age = now - rec.last.observed.t
    if age < 0 then
        age = 0
    end
    rec.conf = rec.last.observed.t > 0 and 1 / (1 + age / I.AURA_HALF_LIFE) or 0 -- nonzero: 1 + age >= 1
end

I.OnBuild(function(def, now)
    health = I.NewBelief("health player")
    health.est, health.lo, health.hi = 1, 0, 1
    I.Sample(health, "default", 1, now, 0)
    otherHealth = I.NewBelief("health other")
    otherHealth.est, otherHealth.lo, otherHealth.hi = 1, 0, 1
    I.Sample(otherHealth, "default", 1, now, 0)
    spellHaste = I.NewBelief("spell haste")
    I.Sample(spellHaste, "default", 0, now, 0)
    ttd = I.NewBelief("ttd")
    ttd.est, ttd.lo, ttd.hi = 30, 0, 3600
    I.Sample(ttd, "default", 30, now, 0)
end)

I.On(Obs.Read, function(o, t)
    if o.c == ReadOf.Health then
        health.est, health.lo, health.hi = o.b, o.b, o.b
        I.Sample(health, "observed", o.b, t, Obs.Read)
    end
end)

I.On(Obs.Haste, function(o, t)
    if o.c == 2 then
        spellHaste.est, spellHaste.lo, spellHaste.hi = o.b, o.b, o.b
        I.Sample(spellHaste, "observed", o.b, t, Obs.Haste)
    end
end)

--- (spec §3.2) Health fraction 0..1: the player's last plain read (conf decaying as an aura), else default 1.0.
function VS.Health(unit, now)
    if unit == "player" then
        decay(health, now)
        return health
    end
    return otherHealth
end

--- (spec §3.1) The player's last plain maximum health; 100 for any other unit.
function VS.HealthMax(unit)
    if unit == "player" and I.healthMax > 0 then
        return I.healthMax
    end
    return 100
end

--- (spec §3.2) Spell haste percent: the last plain read, default 0.
function VS.SpellHaste(now)
    decay(spellHaste, now)
    return spellHaste
end

--- (spec §3.2) Time to die: the default 30 s (Hekili's DEFAULT_TTD), conf 0.
function VS.TTD(unit, now)
    return ttd
end

-- The stat cache (spec §6.5): the 12 stat names with the arguments Hekili reads them with (State.lua:2236-2356),
-- read out of combat; up to 7 returns each.
I.STATS = {
    { "UnitStat", 1 },
    { "UnitStat", 2 },
    { "UnitStat", 3 },
    { "UnitStat", 4 },
    { "UnitStat", 5 },
    { "GetSpellBonusDamage", 7 },
    { "UnitAttackPower" },
    { "UnitWeaponAttackPower" },
    { "UnitDamage" },
    { "UnitArmor" },
    { "GetMasteryEffect" },
    { "GetCritChance" },
    { "GetSpellCritChance" },
    { "GetRangedCritChance" },
    { "GetCombatRating", "CR_CRIT_MELEE" },
    { "GetCombatRating", "CR_HASTE_MELEE" },
    { "GetCombatRating", "CR_CRIT_TAKEN_SPELL" },
    { "GetCombatRating", "CR_MASTERY" },
    { "GetCombatRating", "CR_VERSATILITY_DAMAGE_DONE" },
    { "GetCombatRating", "CR_VERSATILITY_DAMAGE_TAKEN" },
    { "GetCombatRatingBonus", "CR_VERSATILITY_DAMAGE_DONE" },
    { "GetCombatRatingBonus", "CR_VERSATILITY_DAMAGE_TAKEN" },
}
-- statVal[i][1..7]: the cached returns; statT[i]: the read time; statIndex[name][arg or 0] = i.
I.statVal, I.statT, I.statIndex = {}, {}, {}
for i = 1, #I.STATS do
    I.statVal[i] = { 0, 0, 0, 0, 0, 0, 0 }
    I.statT[i] = 0
end

--- (spec §3.1) The returns of the last plain out-of-combat `apiName(arg)` call, in the real API's order; zeros before
--- the first read or for a call not cached. `arg` is the stat index, rating or school (nil for the unit-only calls).
--- Allocates nothing.
function VS.Stat(apiName, arg)
    local byArg = I.statIndex[apiName]
    local i = byArg and byArg[arg or 0]
    local v = i and I.statVal[i]
    if not v then
        return 0, 0, 0, 0, 0, 0, 0
    end
    return v[1], v[2], v[3], v[4], v[5], v[6], v[7]
end

I.OnSnapshot(function(out, now)
    VS.Health("player", now)
    VS.SpellHaste(now)
end)
```
`VirtualState/Sources/Sources.lua`:
```lua
-- VirtualState/Sources/Sources.lua
-- Sources (spec §4): the only VirtualState code that touches the game, and only through the injected `api` (`_G` in
-- game, a fake in tests). This file: the `Plain` secrecy gate, staging and the per-frame Flush, the polls, the event
-- registry and the module's own frame (VirtualState.Start).
-- Credits: the `Plain` gate and the issecretvalue/pcall handling follow Catnip's (Durts) secret-value research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Sources.lua (Plain :42-46, STAGE :52, Stage :540, Flush
-- :552-561, the poll loop :564-588 with Sources.Poll at :576).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Add = I.ObsLog.Add

local S = {}
I.Sources = S

-- Adapter.lua's hooks into Hekili's across-reset caches (spec §4.6), called by the own-cast and swing sources; nil
-- until Adapter.lua sets them (and in headless specs that do not).
I.feed = {}

--- A client value VirtualState may test, compare or use: the value itself, or nil if it is secret. It asks
--- `issecretvalue` before touching the value in any other way. Allocates nothing.
function S.Plain(api, v)
    if api.issecretvalue(v) then
        return nil
    end
    return v
end
local Plain = S.Plain

--- Staged observations one frame holds before the newest is dropped (and counted).
S.STAGE = 128
local stKind, stT, stA, stB, stC = {}, {}, {}, {}, {}
for i = 1, S.STAGE do
    stKind[i], stT[i], stA[i], stB[i], stC[i] = 0, 0, 0, 0, 0
end
S.stN, S.dropped = 0, 0

--- Stages one observation until the next Flush (a frame's aura reads go to the log first). False when the stage is
--- full (dropped and counted). Allocates nothing.
function S.Stage(kind, t, a, b, c)
    local n = S.stN
    if n >= S.STAGE then
        S.dropped = S.dropped + 1
        return false
    end
    n = n + 1
    S.stN = n
    stKind[n], stT[n], stA[n], stB[n], stC[n] = kind, t, a or 0, b or 0, c or 0
    return true
end

--- Straight into the log (aura reads and polls). Allocates nothing.
function S.Direct(kind, t, a, b, c)
    Add(I.log, kind, t, a, b, c)
end

--- Moves the staged observations into the log, in order. Runs at the start of each frame (the frame's OnUpdate).
function S.Flush()
    local log = I.log
    for i = 1, S.stN do
        Add(log, stKind[i], stT[i], stA[i], stB[i], stC[i])
    end
    S.stN = 0
end

-- Read statuses for Snapshot(), by read name: "readable", "secret", "nil" or "error".
S.status = {}

--- Notes what a read answered (constant strings only: allocates nothing).
function S.Note(name, status)
    S.status[name] = status
end

--- The status of a raw value: "secret", "nil" or "readable". Allocates nothing.
function S.StatusOf(api, raw)
    if api.issecretvalue(raw) then
        return "secret"
    elseif raw == nil then -- secret: issecretvalue tested on the line above
        return "nil"
    end
    return "readable"
end

-- The polls (spec §4.3), sorted by order.
local POLL_ORDER, POLL_FN, POLL_N = {}, {}, 0

--- Registers `fn(api, t)` as poll `order` (an order registers once). Load time only.
function S.Poll(order, fn)
    for i = 1, POLL_N do
        if POLL_ORDER[i] == order then
            error("VirtualState: poll order " .. tostring(order) .. " is registered twice", 2)
        end
    end
    local i = POLL_N + 1
    while i > 1 and POLL_ORDER[i - 1] > order do
        POLL_ORDER[i], POLL_FN[i] = POLL_ORDER[i - 1], POLL_FN[i - 1]
        i = i - 1
    end
    POLL_ORDER[i], POLL_FN[i] = order, fn
    POLL_N = POLL_N + 1
end

--- Runs every poll in order, each straight into the log at `t` (the drain's cut-off). Allocates nothing.
function S.RunPolls(t)
    local api = I.api
    if not api then
        return
    end
    for i = 1, POLL_N do
        POLL_FN[i](api, t)
    end
end

-- The event registry: event -> handlers, and event -> the units it is registered for (unit events).
local HANDLERS, UNITS = {}, {}

--- Registers `fn(api, t, a1, a2, a3, a4, a5)` for `event`; `unit` ("player" or "target") makes it a unit event
--- for that unit (the handler still checks a1). Every argument reaches the handler through Plain. Load time only.
function S.On(event, unit, fn)
    local list = HANDLERS[event]
    if not list then
        list = {}
        HANDLERS[event] = list
    end
    list[#list + 1] = fn
    if unit then
        local u = UNITS[event]
        if not u then
            u = {}
            UNITS[event] = u
        end
        if u[1] ~= unit and u[2] ~= unit then
            u[#u + 1] = unit
        end
    end
end

-- Start hooks: `fn(api, t)` once at VirtualState.Start, in registration order.
local STARTS = {}
function S.OnStart(fn)
    STARTS[#STARTS + 1] = fn
end

--- Asks Hekili for a sooner cycle (the urgent lane, spec §4.4). Adapter.lua sets `I.urgent`.
function S.Urgent(event)
    local f = I.urgent
    if f then
        f(event)
    end
end

function S:OnEvent(event, r1, r2, r3, r4, r5)
    local api = I.api
    local list = HANDLERS[event]
    if not list then
        return
    end
    local t = api.GetTime()
    local a1, a2, a3, a4, a5 = Plain(api, r1), Plain(api, r2), Plain(api, r3), Plain(api, r4), Plain(api, r5)
    for k = 1, #list do
        list[k](api, t, a1, a2, a3, a4, a5)
    end
end

local function onEvent(_, event, r1, r2, r3, r4, r5)
    S:OnEvent(event, r1, r2, r3, r4, r5)
end

local function onUpdate()
    S.Flush()
end

--- Once, at PLAYER_LOGIN: `api` is `_G` in game and a fake in tests. Creates the module's frame, registers the source
--- events (spec §4.2) and starts the per-frame flush. Allocates; once.
---@param api table
function VS.Start(api)
    I.api = api
    local frame = api.CreateFrame("Frame")
    S.frame = frame
    for event in pairs(HANDLERS) do
        local u = UNITS[event]
        if u then
            frame:RegisterUnitEvent(event, u[1], u[2])
        else
            frame:RegisterEvent(event)
        end
    end
    frame:SetScript("OnEvent", onEvent)
    frame:SetScript("OnUpdate", onUpdate)
    local t = api.GetTime()
    for k = 1, #STARTS do
        STARTS[k](api, t)
    end
end
```
`VirtualState/Sources/Player.lua`:
```lua
-- VirtualState/Sources/Player.lua
-- Player sources (spec §4.2): combat start and end, movement, spell haste, the player's health (poll 1.5) and the
-- out-of-combat stat cache (login, PLAYER_REGEN_ENABLED, PLAYER_EQUIPMENT_CHANGED).
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Player.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, ReadOf = VS.Obs, I.ReadOf
local Plain, Stage, Direct, Note = S.Plain, S.Stage, S.Direct, S.Note

-- One stat call, read where it is called so the secrets check sees every client read. Allocates nothing.
local function statCall(api, name, arg)
    if name == "UnitStat" then
        return api.UnitStat("player", arg) -- secret: readStat tests every return with issecretvalue
    elseif name == "GetSpellBonusDamage" then
        return api.GetSpellBonusDamage(arg) -- secret: readStat tests every return
    elseif name == "UnitAttackPower" then
        return api.UnitAttackPower("player") -- secret: readStat tests every return
    elseif name == "UnitWeaponAttackPower" then
        return api.UnitWeaponAttackPower("player") -- secret: readStat tests every return
    elseif name == "UnitDamage" then
        return api.UnitDamage("player") -- secret: readStat tests every return
    elseif name == "UnitArmor" then
        return api.UnitArmor("player") -- secret: readStat tests every return
    elseif name == "GetMasteryEffect" then
        return api.GetMasteryEffect() -- secret: readStat tests every return
    elseif name == "GetCritChance" then
        return api.GetCritChance() -- secret: readStat tests every return
    elseif name == "GetSpellCritChance" then
        return api.GetSpellCritChance("player") -- secret: readStat tests every return
    elseif name == "GetRangedCritChance" then
        return api.GetRangedCritChance() -- secret: readStat tests every return
    elseif name == "GetCombatRating" then
        return api.GetCombatRating(arg) -- secret: readStat tests every return
    elseif name == "GetCombatRatingBonus" then
        return api.GetCombatRatingBonus(arg) -- secret: readStat tests every return
    end
end

-- One stat call's returns into its cache slot, only when every return is plain. Allocates nothing.
local function readStat(api, i, t)
    local e = I.STATS[i]
    local r1, r2, r3, r4, r5, r6, r7 = statCall(api, e[1], e.arg) -- secret: tested with issecretvalue below
    if
        api.issecretvalue(r1)
        or api.issecretvalue(r2)
        or api.issecretvalue(r3)
        or api.issecretvalue(r4)
        or api.issecretvalue(r5)
        or api.issecretvalue(r6)
        or api.issecretvalue(r7)
    then
        Note("stats", "secret")
        return
    end
    local v = I.statVal[i]
    v[1], v[2], v[3], v[4] = Plain(api, r1) or 0, Plain(api, r2) or 0, Plain(api, r3) or 0, Plain(api, r4) or 0
    v[5], v[6], v[7] = Plain(api, r5) or 0, Plain(api, r6) or 0, Plain(api, r7) or 0
    I.statT[i] = t
    Note("stats", "readable")
end

local function readStats(api, t)
    if I.inCombat then
        return
    end
    for i = 1, #I.STATS do
        readStat(api, i, t)
    end
end

local function readSpellHaste(api, t, direct)
    local raw = api.UnitSpellHaste("player") -- secret: Plain next
    Note("UnitSpellHaste", S.StatusOf(api, raw))
    local v = Plain(api, raw)
    if type(v) == "number" then
        if direct then
            Direct(Obs.Haste, t, 0, v, 2)
        else
            Stage(Obs.Haste, t, 0, v, 2)
        end
    end
end

S.OnStart(function(api, t)
    -- the stat arguments: the CR_* constants as this client defines them (a missing one is skipped: zeros)
    for i, e in ipairs(I.STATS) do
        local arg = e[2]
        if type(arg) == "string" then
            arg = api[arg] -- a CR_* constant (a number), not a client function
        end
        e.arg = arg
        local byArg = I.statIndex[e[1]] or {}
        I.statIndex[e[1]] = byArg
        if arg ~= nil or e[2] == nil then
            byArg[arg or 0] = i
        end
    end
    I.inCombat = Plain(api, api.InCombatLockdown()) == true
    I.class = Plain(api, api.UnitClassBase("player"))
    readStats(api, t)
    readSpellHaste(api, t, true)
end)

S.On("PLAYER_REGEN_DISABLED", nil, function(api, t)
    I.inCombat = true
    Stage(Obs.CombatStart, t)
end)

S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    I.inCombat = false
    Stage(Obs.CombatEnd, t)
    readStats(api, t)
    readSpellHaste(api, t)
end)

S.On("PLAYER_EQUIPMENT_CHANGED", nil, function(api, t)
    readStats(api, t)
end)

S.On("PLAYER_STARTED_MOVING", nil, function(api, t)
    Stage(Obs.Moving, t, 0, 1)
end)

S.On("PLAYER_STOPPED_MOVING", nil, function(api, t)
    Stage(Obs.Moving, t, 0, 0)
end)

S.On("UNIT_SPELL_HASTE", "player", function(api, t, unit)
    if unit == "player" then
        readSpellHaste(api, t)
    end
end)

-- Poll 1.5: the player's health, when plain (unprobed on Forever, cleanup Q11), and its maximum.
S.Poll(1.5, function(api, t)
    local rawMax = api.UnitHealthMax("player") -- secret: Plain next
    local max = Plain(api, rawMax)
    if type(max) == "number" and max > 0 then
        I.healthMax = max
    end
    local raw = api.UnitHealth("player") -- secret: Plain next
    Note("UnitHealth player", S.StatusOf(api, raw))
    local v = Plain(api, raw)
    if type(v) == "number" and I.healthMax > 0 then
        Direct(Obs.Read, t, 0, v / I.healthMax, ReadOf.Health) -- nonzero: healthMax > 0 checked
    end
end)
```
`VirtualState/Snapshot.lua`:
```lua
-- VirtualState/Snapshot.lua
-- VirtualState.Snapshot() (spec §3.5): every tracked record projected to now (est, lo, hi, conf, basis, the four
-- `last` slots), the facts, the log's fill and drop counts, the read statuses per source, the drain cost and, with
-- debug on, the rings. It allocates and is for debugging only: /run print(Hekili.VirtualState.Snapshot())

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local format, concat, sort = string.format, table.concat, table.sort

local function slot(s)
    return format("%.2f@%.2f#%d", s.v, s.t, s.event)
end

--- A multi-line report of everything VirtualState believes, projected to now. Allocates.
---@return string
function VS.Snapshot()
    local api = I.api
    local now = api and api.GetTime() or I.clock
    local out = {}
    out[#out + 1] = format(
        "VirtualState t=%.2f clock=%.2f class=%s combat=%s moving=%s",
        now,
        I.clock,
        tostring(I.class),
        tostring(I.inCombat),
        tostring(I.moving)
    )
    out[#out + 1] = format(
        "log %d/%d dropped=%d stage dropped=%d drain=%.2fms casts=%d",
        I.log.n,
        I.log.cap,
        I.log.dropped,
        S.dropped,
        I.drainMs or 0,
        I.drainCasts or 0
    )
    local names = {}
    for name in pairs(S.status) do
        names[#names + 1] = name
    end
    sort(names)
    for _, name in ipairs(names) do
        out[#out + 1] = format("read %s: %s", name, S.status[name])
    end
    if not I.built then
        out[#out + 1] = "no tracked set yet (VirtualState.SpecChanged has not run)"
        return concat(out, "\n")
    end
    for k = 1, #I.SNAPSHOT do
        I.SNAPSHOT[k](out, now) -- families project their records to now and add their facts
    end
    for i = 1, #I.records do
        local r = I.records[i]
        local l = r.last
        out[#out + 1] = format(
            "%s est=%.2f lo=%.2f hi=%.2f conf=%.2f basis=%s O=%s P=%s M=%s D=%s",
            I.labels[i],
            r.est,
            r.lo,
            r.hi,
            r.conf,
            r.basis,
            slot(l.observed),
            slot(l.pinned),
            slot(l.modelled),
            slot(l.default)
        )
        if r.ring then
            for _, origin in ipairs(I.ORIGINS) do
                local ring, parts = r.ring[origin], {}
                for j = 1, I.RING do
                    if ring[j].t > 0 then
                        parts[#parts + 1] = slot(ring[j])
                    end
                end
                if #parts > 0 then
                    out[#out + 1] = format("  ring %s: %s", origin, concat(parts, " "))
                end
            end
        end
    end
    return concat(out, "\n")
end
```
- [ ] **Step 5: Add the files to the TOC**

In `Hekili.toc`, the lines
```
embeds.xml

Hekili.lua
```
become
```
embeds.xml

VirtualState\VirtualState.lua
VirtualState\ObsLog.lua
VirtualState\Belief.lua
VirtualState\Families\Player.lua
VirtualState\Sources\Sources.lua
VirtualState\Sources\Player.lua
VirtualState\Snapshot.lua

Hekili.lua
```

- [ ] **Step 6: Run the specs to see them pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `33 successes / 0 failures / 0 errors`.

- [ ] **Step 7: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [33 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 23 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [no problems found]
git status --short | grep '\.lua$' | awk '{print $2}' | xargs -r -n1 luac5.1 -p   # [no output]
```
- [ ] **Step 8: Commit**
```bash
git add .busted .luacheckrc Hekili.toc VirtualState
git commit -m "feat(virtualstate): core record, observation log, fold, sources plumbing, player facts, Snapshot

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: The adapter (fold-only drain), Hekili's call sites, the version gates, CHECKPOINT 1

**Files:**
- Create: `VirtualState/Adapter.lua` (first version; Task 9 replaces it), `VirtualState/spec/adapter_spec.lua` (first version; Task 9 replaces it)
- Modify: `Hekili.toc` (after `Core.lua`, the last line), `Core.lua:1568-1571` (the drain call), `Classes.lua:3133-3135` (spec 1491 loop break), `Classes.lua:3351-3354` (the SpecChanged call), `Hekili.lua:41-56` (version gates)

**Interfaces:**
- Consumes: Task 1's `I.Build`, `I.Fold`, `I.Settle`, `I.Sources.RunPolls`, `I.extra`, `VS.Start`, `VS.Snapshot`; Hekili's `Hekili.Class`, `Hekili:ForceUpdate(event)`, `ns.ResourceRegenerates(key)`.
- Produces: `VS.SpecChanged()`, `VS.Drain(cutoff)`, the debug handle `Hekili.VirtualState`, `I.urgent = function(event)`, `I.drainMs`, `I.drainCasts`; the tracked-set `def` built from `class.resources`, `class.abilities`, `class.auras`, `class.talents` (Task 9 keeps the same builder).

- [ ] **Step 1: Write the failing spec**

`VirtualState/spec/adapter_spec.lua`:

```lua
-- VirtualState/spec/adapter_spec.lua: Adapter.lua's first version against a fake Hekili (spec §3.6): the debug
-- handle, the tracked set built at SpecChanged, Drain's fold.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("Adapter", function()
    local ns, VS, I, api, ctl, h, saved

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        saved = {}
        for _, k in ipairs({ "LibStub", "GetTime", "CreateFrame", "debugprofilestop" }) do
            saved[k] = rawget(_G, k) or false
        end
        _G.LibStub = function()
            return { GetTime = api.GetTime }
        end
        _G.GetTime, _G.CreateFrame = api.GetTime, api.CreateFrame -- (Task 8 turns the facade read into a direct one)
        _G.debugprofilestop = function()
            return os.clock() * 1000
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        h = fs.new(9)
        ns.ResourceRegenerates = function()
            return false
        end
        load.adapter(ns, h)
        VS.Start(api)
        VS.SpecChanged()
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("sets the debug handle and builds the tracked set at SpecChanged", function()
        assert.are.equal(VS, h.VirtualState)
        assert.is_true(I.built)
        assert.is_truthy(VS.Snapshot():find("class=WARRIOR", 1, true))
    end)

    it("drains by folding the log up to the cut-off", function()
        ctl.now = 5
        ctl.Fire("PLAYER_STARTED_MOVING")
        ctl.Tick(5)
        VS.Drain(5)
        assert.is_true(VS.Moving())
        assert.are.equal(0, I.log.n)
        assert.are.equal(0, I.drainCasts)
    end)

    it("asks Hekili for a sooner cycle on the urgent lane", function()
        I.Sources.Urgent("PLAYER_SWING")
        assert.are.same({ "PLAYER_SWING" }, h.forced)
    end)
end)
```
- [ ] **Step 2: Run it to see it fail**

Run: `~/src/TacoDogForever/.lua/bin/busted VirtualState/spec/adapter_spec.lua`
Expected: errors in `before_each`: `cannot open VirtualState/Adapter.lua`.

- [ ] **Step 3: Write `VirtualState/Adapter.lua`**

The `VGA` local is temporary: until Task 8 every plain read still goes through the facade library (`tools/check_api_reads.sh` would flag a bare `GetTime`); Task 8's rewrite turns it into a direct read.

```lua
-- VirtualState/Adapter.lua
-- VirtualState's glue to Hekili (spec §3.6, §5): VirtualState.Start at PLAYER_LOGIN, the Hekili.VirtualState debug
-- handle, the urgent lane, the tracked set from the active spec's registrations (SpecChanged) and Drain. This first
-- version drains by folding only; the apply through the spec and the across-reset feeds arrive with Task 9.
-- Loads after Core.lua.

local addon, ns = ...
local VGA = LibStub( "VirtualGameAPI-1.0" )
local GetTime = VGA.GetTime
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources

local Hekili = _G[addon]
local class = Hekili.Class
local CreateFrame, debugprofilestop = CreateFrame, debugprofilestop
local insert, sort = table.insert, table.sort

local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

-- The debug handle: /run print(Hekili.VirtualState.Snapshot())
Hekili.VirtualState = VS

-- The urgent lane (spec §4.4): shortens Hekili's wait before its next cycle; never interrupts one.
I.urgent = function(event)
    Hekili:ForceUpdate(event)
end

-- Start once, at PLAYER_LOGIN, on a frame of its own.
do
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        VS.Start(_G)
    end)
end

----------------------------------------------------------------------------------------------------------------------
-- The tracked set (spec §3.6, decision 8): what `state` reads, from the active spec's registrations.

local def = {
    abilities = {},
    abilityIds = {},
    abilitySlot = {},
    resources = {},
    auras = {},
    auraIds = {},
    talents = {},
    units = {},
}

local HANDS = { mainhand = 1, offhand = 2 }

-- The spell IDs of a registration: its `id`, then its `copy` IDs (rank order), positive numbers only.
local function idsOf(obj)
    local ids = {}
    if type(obj.id) == "number" and obj.id > 0 then
        ids[1] = obj.id
    end
    local copy = obj.copy
    if type(copy) == "number" and copy > 0 then
        ids[#ids + 1] = copy
    elseif type(copy) == "table" then
        for _, v in ipairs(copy) do
            if type(v) == "number" and v > 0 then
                ids[#ids + 1] = v
            end
        end
    end
    return ids
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" then
            keys[#keys + 1] = k
        end
    end
    sort(keys)
    return keys
end

local resourceKey, auraKey = {}, {}

local function buildDef()
    for _, list in pairs(def) do
        wipe(list)
    end
    wipe(resourceKey)
    wipe(auraKey)
    local slotByKey = {}
    for _, k in ipairs(sortedKeys(class.resources)) do
        local r = class.resources[k]
        local swing, value = 0, nil
        local model = r.state and r.state.regenModel
        if model then
            for _, m in pairs(model) do
                if m.swing and HANDS[m.swing] and swing == 0 then
                    swing, value = HANDS[m.swing], m.value
                end
            end
        end
        local d = {
            key = k,
            type = r.type,
            token = k:upper(),
            max = 100,
            rest = ns.ResourceRegenerates(k) and 100 or 0,
            swing = swing,
            swingValue = value,
        }
        insert(def.resources, d)
        resourceKey[#def.resources] = k
        slotByKey[k] = #def.resources
    end
    for _, k in ipairs(sortedKeys(class.abilities)) do
        local a = class.abilities[k]
        if a.key == k and k ~= "global_cooldown" then
            local ids = idsOf(a)
            if #ids > 0 then
                insert(def.abilities, a)
                def.abilityIds[#def.abilities] = ids
                local spends = rawget(a, "spend") ~= nil or a.funcs and a.funcs.spend ~= nil
                local slot = spends and slotByKey[a.spendType or class.primaryResource] or 0
                def.abilitySlot[#def.abilities] = slot
            end
        end
    end
    for _, id in ipairs(I.extra.abilities) do
        insert(def.abilities, { key = "track_" .. id, id = id, cooldown = 0 })
        def.abilityIds[#def.abilities] = { id }
        def.abilitySlot[#def.abilities] = 0
    end
    for _, k in ipairs(sortedKeys(class.auras)) do
        local a = class.auras[k]
        if a.key == k then
            local ids = idsOf(a)
            if #ids > 0 then
                insert(def.auras, a)
                def.auraIds[#def.auras] = ids
                auraKey[#def.auras] = k
            end
        end
    end
    for _, id in ipairs(I.extra.auras) do
        insert(def.auras, { key = "track_" .. id, id = id })
        def.auraIds[#def.auras] = { id }
    end
    local seen = {}
    for _, k in ipairs(sortedKeys(class.talents)) do
        local v = class.talents[k]
        if type(v) == "table" and type(v[2]) == "number" and not seen[v[2]] then
            seen[v[2]] = true
            insert(def.talents, { key = k, spell = v[2], max = v[3] or 1 })
        end
    end
    def.units[1], def.units[2] = "player", "target"
    for _, u in ipairs(I.extra.units) do
        insert(def.units, u)
    end
end

--- Rebuilds the tracked set from the active spec (decision 8). Called from Hekili:SpecializationChanged, after every
--- registration. Allocates; SpecChanged only.
function VS.SpecChanged()
    buildDef()
    I.Build(def, GetTime())
end

--- The fold (spec §5.2 steps 1, 2 and 4 without casts), called only from Hekili.Update after its guards.
---@param cutoff number GetTime() at the drain's entry
function VS.Drain(cutoff)
    if not I.built then
        return
    end
    local t0 = debugprofilestop()
    S.RunPolls(cutoff)
    I.Fold(cutoff, false)
    I.Settle(cutoff)
    I.drainMs, I.drainCasts = debugprofilestop() - t0, 0
end
```
In `Hekili.toc`, after the last line `Core.lua`, add:
```
VirtualState\Adapter.lua
```

- [ ] **Step 4: Call the drain and SpecChanged from Hekili; break the 1491 loop; open the version gates**

`Core.lua` (in `Hekili.Update`, lines 1568-1571; spec §5.1, §10): replace
```lua
    local pack = rawget( profile.packs, packName )
    if not pack then return end

    local debug = Hekili.ActiveDebug
```
with
```lua
    local pack = rawget( profile.packs, packName )
    if not pack then return end

    -- VirtualState: fold what was observed since the last cycle and apply our casts through the spec, after the guards
    -- above and before any reset (docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md §5.1).
    ns.VirtualState.Drain( GetTime() )

    local debug = Hekili.ActiveDebug
```

`Classes.lua` (in `Hekili:SpecializationChanged`, lines 3351-3354): replace
```lua
    ns.callHook( "specializationChanged" )

    ns.updateTalents()
```
with
```lua
    ns.callHook( "specializationChanged" )

    -- VirtualState tracks what this spec registered; its talent walk runs here, before ns.updateTalents reads the ranks.
    ns.VirtualState.SpecChanged()

    ns.updateTalents()
```
(Spec §10 says "at the end"; this is after every registration and the `specializationChanged` hook, and before `ns.updateTalents`, which Task 6 points at `VirtualState.Talent`. At the very end the ranks would be read before the walk.)

`Classes.lua` (lines 3133-3135; cleanup Q7): replace
```lua
        local id, name, _, _, role, primaryStat = GetSpecializationInfo( i )

        if not id then break end
```
with
```lua
        local id, name, _, _, role, primaryStat = GetSpecializationInfo( i )

        -- Forever answers id 0 for spec slots 2 and 3 (cleanup Q7).
        if not id or id == 0 then break end
```

`Hekili.lua` (lines 41-56; cleanup Q15): replace
```lua
Hekili.IsDragonflight = function()
    return buildNum >= 100000
end

Hekili.IsTWW = function()
    return buildNum >= 110000
end

Hekili.IsMidnight = function()
    return buildNum >= 120000
end

Hekili.BuiltFor = 110200
Hekili.GameBuild = buildStr

ns.PTR = buildNum > 110200
```
with
```lua
-- Forever (interface 16001) runs the Midnight 12.x API, so the retail gates hold there (cleanup Q15).
Hekili.IsDragonflight = function()
    return true
end

Hekili.IsTWW = function()
    return true
end

Hekili.IsMidnight = function()
    return true
end

Hekili.BuiltFor = 16001
Hekili.GameBuild = buildStr

ns.PTR = false
```
`BuiltFor = 16001` also silences `Core.lua:205`'s "built for a future version" warning, so `Core.lua:205` itself needs no edit.

- [ ] **Step 5: Run the specs to see them pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `36 successes / 0 failures / 0 errors`.

- [ ] **Step 6: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [36 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 24 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [no problems found]
git status --short | grep '\.lua$' | awk '{print $2}' | xargs -r -n1 luac5.1 -p   # [no output]
```
- [ ] **Step 7: Commit**
```bash
git add Hekili.toc Core.lua Classes.lua Hekili.lua VirtualState/Adapter.lua VirtualState/spec/adapter_spec.lua
git commit -m "feat(virtualstate): adapter with a fold-only drain; drain and SpecChanged calls; spec 1491 loop break; version gates

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
- [ ] **Step 8: CHECKPOINT 1: stop and ask the user to run the following in game**

Orchestrator: `git push origin virtualstate-phase1`, then `git -C ~/src/hekili checkout --detach virtualstate-phase1`. Ask the user, on the Forever Warrior:

1. `/reload`. Expected: no Lua error, no popup. (The Warrior is still the load-only stub; no recommendations are expected.)
2. Out of combat: `/run print(Hekili.VirtualState.Snapshot())`. Expected, among the lines: `VirtualState t=… clock=… class=WARRIOR combat=false moving=false`; `log …/256 dropped=0`; `read stats: readable`; `read UnitHealth player: readable` (or `secret`: then report it, it answers cleanup Q11); `health player est=1.00 …` (or the real fraction); `ttd est=30.00 … basis=default`.
3. Walk a few steps and repeat the `/run` line while moving: `moving=true`.
4. The four passthrough probes of spec §7.7, each typed **in combat on a training dummy** (one `/run` per line):
   ```
   /run local s,d,e=C_Item.GetItemCooldown(6948) print("GetItemCooldown",issecretvalue(s),issecretvalue(d),issecretvalue(e))
   /run local a,b=C_Spell.IsSpellUsable(772) print("IsSpellUsable",issecretvalue(a),issecretvalue(b))
   /run print("UnitThreatSituation",issecretvalue(UnitThreatSituation("player","target")))
   /run print("InCombatLockdown",issecretvalue(InCombatLockdown()))
   ```
   Expected: every printed value `false`. Record the results in the task report. Any `true` changes Task 8 (its Step 2b says how).
5. Still in combat, the snapshot again: `combat=true`.

Fix what the user reports (each fix its own commit, with the verification block), then repeat the checkpoint. Continue only when the user confirms.


### Task 3: Casts, cooldowns, charges and the GCD; the spellbook and own-cast sources; GCD spell 29515

**Files:**
- Create: `VirtualState/Families/Casts.lua`, `VirtualState/Sources/Spellbook.lua`, `VirtualState/Sources/Casts.lua`, `VirtualState/spec/casts_spec.lua`
- Modify: `Hekili.toc`, `Classes.lua:2469`, `UI.lua:1493`, `UI.lua:1694`, `Events.lua:1676`, `Options/Options.lua:4042`

**Interfaces:**
- Consumes: Task 1 (`I.On`, `I.OnSettle`, `I.OnBuild`, `I.NewBelief`, `I.Sample`, `S.Stage`, `S.Direct`, `S.On`, `S.Poll`, `S.Urgent`, `I.feed`).
- Produces: `I.ab` (`n`, `key[a]`, `id[a]`, `ids[a]`, `obj[a]`, `slot[a]`, `qid[a]`, `readCost[a]` (shown, not used), `castStartT[a]`, `ch[a]`, `bySpell[spellID] -> a`), `I.CostOf(a)` (the spec's `spend`: a number, or a function called on the spot), `I.AgeConf(rec, now)`, `I.Quantise(x)`, `I.CooldownModel(a, expires, duration, t, event)`, `I.ChargesModel(a, charges, nextAt, t, event)`, `I.GcdModel(expires, t, event)`, `I.castAb`, `I.castEnd`, `I.channel`, `I.gcdStart`, `I.gcdDur`, `I.gcdLearned`, `I.queuedStrike`, `I.lastCastT`, `I.GCD_SPELL` (29515), `I.ResolveSpells(api)`, `I.sentGUID`; `VS.Cooldown(spellID, now)`, `VS.CooldownLength(spellID)`, `VS.Charges(spellID, now)`, `VS.Gcd(now)`, `VS.GcdInfo(now)`; the feed calls `I.feed.CastStart(a, start, finish, guid)`, `I.feed.CastSucceeded(a, spellID, guid)`, `I.feed.CastFailed(a)`, `I.feed.ChannelStart(a, start, finish, guid)`, `I.feed.ChannelStop(a)` (Task 9 sets them).

- [ ] **Step 1: Write the failing spec**

`VirtualState/spec/casts_spec.lua` (golden scenario 3, TDF `tests/model/belief_spec.lua:401`; the GCD bit-identity of spec §7.5; a function cost, as Heroic Strike's with Improved Heroic Strike):

```lua
-- VirtualState/spec/casts_spec.lua: cooldowns, charges and the GCD (spec §6.2, §7.5). Golden scenario 3 (TDF
-- tests/model/belief_spec.lua:401): cooldowns snap to the game's ready flags.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("casts and cooldowns", function()
    local VS, I, S, Obs, api, ctl, h
    local REND = 3

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        h = fs.new(9)
        h.Class.abilities.rend.cooldown = 30
        I.Build(fs.def(h), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    it("snaps cooldowns to the game's ready flags", function()
        I.CooldownModel(REND, 40, 30, 10, Obs.CastSuccess) -- 30 s cooldown in the model
        S.Direct(Obs.Cooldown, 20, REND, 1) -- but the game says it's ready (something reset it)
        I.Fold(20, false)
        I.Settle(20)
        assert.are.equal(20, VS.Cooldown(fs.REND, 20).est)
        assert.are.equal("pinned", VS.Cooldown(fs.REND, 20).basis)
        S.Direct(Obs.Cooldown, 21, REND, 0) -- and now it isn't, while the model thinks it is
        I.Fold(21, false)
        I.Settle(21)
        assert.are.equal(21 + I.CD_PROBE, VS.Cooldown(fs.REND, 21).est)
        assert.are.equal(VS.Cooldown(fs.REND_R2, 21), VS.Cooldown(fs.REND, 21)) -- every rank ID is the ability
        assert.is_nil(VS.Cooldown(424242, 21))
    end)

    it("learns the real length from the ready edge after our cast", function()
        assert.are.equal(30, VS.CooldownLength(fs.REND)) -- the spec's cooldown first
        I.CooldownModel(REND, 40, 30, 10, Obs.CastSuccess)
        S.Direct(Obs.Cooldown, 10.1, REND, 0)
        S.Direct(Obs.Cooldown, 35, REND, 1)
        I.Fold(35, false)
        assert.are.equal(25, VS.CooldownLength(fs.REND))
    end)

    it("logs a Cooldown only on a plain flag edge, and the GCD's edges, on the urgent lane", function()
        h.forced = {}
        I.urgent = function(e)
            h.forced[#h.forced + 1] = e
        end
        ctl.cooldown[fs.REND] = { isActive = true, isOnGCD = false }
        ctl.cooldown[29515] = { isActive = true, isOnGCD = false }
        ctl.now = 5
        ctl.Fire("SPELL_UPDATE_COOLDOWN")
        ctl.Fire("SPELL_UPDATE_COOLDOWN")
        ctl.Tick(5)
        local n = 0
        for i = 1, I.log.n do
            if I.ObsLog.At(I.log, i).kind == Obs.Cooldown then
                n = n + 1
            end
        end
        assert.are.equal(4, n) -- shout, strike ready; rend not; the GCD up (a second event repeats nothing)
        assert.are.same({ "VS_COOLDOWN" }, h.forced)
        ctl.cooldown[fs.REND] = { isActive = fake.SECRET, isOnGCD = false }
        ctl.Fire("SPELL_UPDATE_COOLDOWN") -- a secret flag is no news
        assert.are.equal(4, n + I.Sources.stN)
    end)

    it("fixes the GCD's start and duration at the rising edge, quantised so they survive Hekili's round trip", function()
        S.Direct(Obs.Cooldown, 1000.123456, 0, 1, 1)
        I.Fold(1000.2, false)
        local s, d = VS.GcdInfo(1000.2)
        assert.are.equal(s, (s + d) - d)
        assert.are.equal(s * 1024, math.floor(s * 1024))
        assert.are.same({ s, d }, { VS.GcdInfo(1000.9) }) -- unchanged between edges
        S.Direct(Obs.Cooldown, 1001.6, 0, 0, 1)
        I.Fold(1001.6, false)
        assert.are.same({ 0, 0 }, { VS.GcdInfo(1001.6) })
        assert.is_true(math.abs(I.gcdLearned - 1.477) < 0.002) -- learned from the falling edge
        for _ = 1, 2000 do
            local t = math.random() * 1e6
            local q = I.Quantise(t)
            local dq = I.Quantise(1.5 * math.random())
            assert.are.equal(q, (q + dq) - dq)
        end
    end)

    it("evaluates a function cost (a talent that lowers it) and uses it for the ladder", function()
        local rank = 2
        h.Class.abilities.heroic_strike.spend = function()
            return 15 - rank -- Improved Heroic Strike: -1 a rank
        end
        assert.are.equal(13, I.CostOf(2))
        rank = 3
        assert.are.equal(12, I.CostOf(2))
        assert.are.equal(10, I.CostOf(3)) -- a number cost
    end)

    it("models charges and recharges them by time; a spell without charges has none", function()
        assert.is_nil(VS.Charges(fs.REND, 1))
    end)
end)
```
- [ ] **Step 2: Run it to see it fail**

Run: `~/src/TacoDogForever/.lua/bin/busted VirtualState/spec/casts_spec.lua`
Expected: errors such as `attempt to call field 'CooldownModel' (a nil value)` and `attempt to index field 'ab' (a nil value)`.

- [ ] **Step 3: Write the family and the sources**

`VirtualState/Families/Casts.lua`:

```lua
-- VirtualState/Families/Casts.lua
-- The casts family (spec §6.2): the tracked abilities, our casts and channels in progress, cooldown ready times
-- snapped to the game's plain ready flags (the constrain step), charges, the GCD from its flag edges with
-- bit-identical start and duration (spec §7.5), the on-next-swing queue, and the Cooldown/Charges/Gcd accessors.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Casts.lua (step :34-78, Applier Cooldown :385,
-- Queued :391) and src/TacoDogForever/Model/Belief.lua (constrain :652-684).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs
local floor = math.floor

-- By ability index a. `obj` is the spec's ability table (Hekili's `class.abilities[key]`): VirtualState reads its
-- `spend`, `spendType`, `cooldown`, `charges`, `recharge`, `gcd`, `cast` and `onNextSwing` fields.
local A = {
    n = 0,
    key = {},
    id = {},
    ids = {},
    obj = {},
    slot = {},
    qid = {},
    readCost = {},
    ready0 = {},
    cdLen = {},
    castT = {},
    flag = {},
    charges0 = {},
    next0 = {},
    queued = {},
    castStartT = {},
    cd = {},
    ch = {},
    chNext = {},
}
I.ab = A
A.bySpell = {}

-- Unknown, not ready, ready (the plain isActive flag as last reported).
local UNKNOWN, NOT, YES = -1, 0, 1

-- The cast or channel in progress (0: none), and the GCD fixed at its rising edge.
I.castAb, I.castEnd, I.channel = 0, 0, false
I.gcdStart, I.gcdDur, I.gcdLearned = 0, 0, 0
I.queuedStrike = false
I.lastCastT = 0
local gcd

-- 2^-10 s: a start and a duration on this grid survive (start + duration) - duration exactly (spec §7.5).
local Q = 1024
local function quantise(x)
    return floor(x * Q + 0.5) / Q
end
I.Quantise = quantise

local function maxCharges(a)
    local c = A.obj[a].charges
    return type(c) == "number" and c or 1
end

I.OnBuild(function(def, now)
    for k in pairs(A.bySpell) do
        A.bySpell[k] = nil
    end
    local list = def.abilities
    A.n = #list
    for a = 1, A.n do
        local obj = list[a]
        A.key[a], A.obj[a] = obj.key, obj
        local ids = def.abilityIds[a]
        A.ids[a], A.id[a] = ids, ids[1]
        for k = 1, #ids do
            A.bySpell[ids[k]] = a
        end
        A.slot[a] = def.abilitySlot[a]
        A.qid[a], A.readCost[a] = ids[1], 0
        A.ready0[a], A.cdLen[a], A.castT[a], A.flag[a] = 0, 0, 0, UNKNOWN
        A.charges0[a], A.next0[a] = maxCharges(a), 0
        A.queued[a], A.castStartT[a] = false, 0
        A.cd[a] = I.NewBelief("cooldown " .. tostring(obj.key))
        I.Sample(A.cd[a], "default", 0, now, 0)
        if maxCharges(a) > 1 then
            A.ch[a] = I.NewBelief("charges " .. tostring(obj.key))
            A.chNext[a] = I.NewBelief("charge next " .. tostring(obj.key))
            I.Sample(A.ch[a], "default", maxCharges(a), now, 0)
        else
            A.ch[a], A.chNext[a] = false, false
        end
    end
    I.TRACKED.ability = A.id
    gcd = I.NewBelief("gcd")
    I.castAb, I.castEnd, I.channel, I.gcdStart, I.gcdDur, I.queuedStrike = 0, 0, false, 0, 0, false
end)

I.On(Obs.CastStart, function(o, t)
    I.castAb, I.castEnd, I.channel = o.a, o.b, false
    A.castStartT[o.a] = o.t
end)

I.On(Obs.CastDelay, function(o)
    if I.castAb == o.a then
        I.castEnd = o.b
    end
end)

I.On(Obs.CastSuccess, function(o)
    I.lastCastT = o.t
    if I.castAb == o.a and not I.channel then
        I.castAb = 0
    end
    if A.obj[o.a].onNextSwing then
        A.queued[o.a] = false
    end
end)

I.On(Obs.CastStop, function(o)
    if I.castAb == o.a then
        I.castAb = 0
    end
end)

I.On(Obs.ChannelStart, function(o)
    I.castAb, I.castEnd, I.channel = o.a, o.b, true
    A.castStartT[o.a] = o.t
end)

I.On(Obs.ChannelUpdate, function(o)
    if I.castAb == o.a then
        I.castEnd = o.b
    end
end)

I.On(Obs.ChannelStop, function(o)
    if I.castAb == o.a then
        I.castAb, I.channel = 0, false
    end
end)

I.On(Obs.Queued, function(o)
    A.queued[o.a] = o.b == 1
    local any = false
    for a = 1, A.n do
        if A.queued[a] then
            any = true
        end
    end
    I.queuedStrike = any
end)

-- The plain flags (spec §6.2): an ability's ready edge, or (a = 0, c = 1) the GCD's edge.
I.On(Obs.Cooldown, function(o, t)
    if o.c == 1 then
        if o.b == 1 then
            -- the GCD began: start and duration fixed until the falling edge (spec §7.5)
            local h = VS.Haste and VS.Haste(t).est or 1 -- Families/Swing.lua measures it
            local dur = I.gcdLearned > 0 and I.gcdLearned or 1.5 / (h > 0 and h or 1) -- nonzero: h > 0 checked
            I.gcdStart, I.gcdDur = quantise(o.t), quantise(dur)
            gcd.est, gcd.lo, gcd.hi = I.gcdStart + I.gcdDur, I.gcdStart + I.gcdDur, I.gcdStart + I.gcdDur
            I.Sample(gcd, "pinned", gcd.est, t, Obs.Cooldown)
        else
            if I.gcdStart > 0 and o.t > I.gcdStart then
                I.gcdLearned = quantise(o.t - I.gcdStart)
            end
            I.gcdStart, I.gcdDur = 0, 0
            gcd.est, gcd.lo, gcd.hi = o.t, o.t, o.t
            I.Sample(gcd, "pinned", o.t, t, Obs.Cooldown)
        end
        return
    end
    local a = o.a
    local was = A.flag[a]
    A.flag[a] = o.b == 1 and YES or NOT
    if o.b == 1 and was == NOT and A.castT[a] > 0 and o.t > A.castT[a] then
        A.cdLen[a] = o.t - A.castT[a] -- a ready edge after our cast teaches the real length (talents included)
    end
end)

-- The standing flags at `now` (TDF constrain): ready pulls a later ready time back to now (and restores a charge);
-- not ready pushes an earlier one to at least now + CD_PROBE.
I.OnSettle(function(now)
    for a = 1, A.n do
        local flag = A.flag[a]
        if flag == YES then
            if A.ready0[a] > now then
                A.ready0[a] = now
                I.Sample(A.cd[a], "pinned", now, now, Obs.Cooldown)
            end
            if A.ch[a] and A.charges0[a] < 1 then
                A.charges0[a] = 1
            end
        elseif flag == NOT then
            local probe = now + I.CD_PROBE
            if A.ch[a] then
                A.charges0[a] = 0
                if A.next0[a] < probe then
                    A.next0[a] = probe
                end
            elseif A.ready0[a] < probe then
                A.ready0[a] = probe
                I.Sample(A.cd[a], "pinned", probe, now, Obs.Cooldown)
            end
        end
    end
end)

--- Our own cast set ability a's cooldown (spec §5.3): ready time `expires`, length `duration`. Allocates nothing.
function I.CooldownModel(a, expires, duration, t, event)
    A.ready0[a], A.castT[a] = expires, t
    if A.cdLen[a] == 0 and duration > 0 then
        A.cdLen[a] = duration
    end
    I.Sample(A.cd[a], "modelled", expires, t, event)
end

--- Our own cast spent a charge (spec §5.3). Allocates nothing.
function I.ChargesModel(a, charges, nextAt, t, event)
    if A.ch[a] then
        A.charges0[a], A.next0[a], A.castT[a] = charges, nextAt, t
        I.Sample(A.ch[a], "modelled", charges, t, event)
        I.Sample(A.chNext[a], "modelled", nextAt, t, event)
    end
end

--- Our own cast started the GCD (spec §5.3): its end as a `modelled` sample. Allocates nothing.
function I.GcdModel(expires, t, event)
    gcd.est, gcd.lo, gcd.hi = expires, expires, expires
    I.Sample(gcd, "modelled", expires, t, event)
end

--- The cost the ladder uses for ability a: the spec's `spend` (decision 2), a number or a function bound to `state`
--- (Hekili's ability table already evaluates a function `spend` on access; a raw one is called here). The plain
--- out-of-combat read (`readCost`, Sources/Spellbook.lua) only confirms it, in Snapshot(): its units are the client's.
function I.CostOf(a)
    local c = I.ab.obj[a].spend
    if type(c) == "function" then
        c = c()
    end
    return type(c) == "number" and c or 0
end

local function ageConf(rec, now)
    local last = rec.last
    local t = last.observed.t
    if last.pinned.t > t then
        t = last.pinned.t
    end
    if last.modelled.t > t then
        t = last.modelled.t
    end
    local age = now - t
    if age < 0 then
        age = 0
    end
    rec.conf = 1 / (1 + age / I.AURA_HALF_LIFE) -- nonzero: 1 + age >= 1
end
I.AgeConf = ageConf

--- (spec §3.2) The believed ready time of a tracked spell (absolute), or nil for an untracked one.
function VS.Cooldown(spellID, now)
    local a = A.bySpell[spellID]
    if not a then
        return nil
    end
    local rec, ready = A.cd[a], A.ready0[a]
    rec.est, rec.lo, rec.hi = ready, ready, ready
    ageConf(rec, now)
    return rec
end

--- (spec §3.1) Seconds: the length learned from the last observed cooldown, else the spec's `cooldown`.
function VS.CooldownLength(spellID)
    local a = A.bySpell[spellID]
    if not a then
        return 0
    end
    if A.cdLen[a] > 0 then
        return A.cdLen[a]
    end
    local c = A.obj[a].cooldown
    return type(c) == "number" and c or 0
end

--- (spec §3.2) Two Beliefs, current charges and the next charge's time; nil for a spell without charges.
function VS.Charges(spellID, now)
    local a = A.bySpell[spellID]
    if not a or not A.ch[a] then
        return nil
    end
    local ch, nx = A.ch[a], A.chNext[a]
    local c, nextAt = A.charges0[a], A.next0[a]
    local max = maxCharges(a)
    local recharge = A.obj[a].recharge
    recharge = type(recharge) == "number" and recharge or 0
    -- recharges the model expects by now
    while c < max and nextAt > 0 and nextAt <= now do
        c = c + 1
        nextAt = c < max and nextAt + recharge or 0
    end
    ch.est, ch.lo, ch.hi = c, c, c
    nx.est, nx.lo, nx.hi = nextAt, nextAt, nextAt
    ageConf(ch, now)
    ageConf(nx, now)
    return ch, nx
end

--- (spec §3.2) The believed end of the GCD.
function VS.Gcd(now)
    ageConf(gcd, now)
    return gcd
end

--- (spec §3.1, §7.5) start, duration of the current GCD as plain numbers fixed between its edges; 0, 0 when none.
function VS.GcdInfo(now)
    if I.gcdStart > 0 and I.gcdStart + I.gcdDur > now then
        return I.gcdStart, I.gcdDur
    end
    return 0, 0
end

I.OnSnapshot(function(out, now)
    out[#out + 1] = string.format(
        "cast ab=%s end=%.2f channel=%s gcd=%.4f+%.4f learned=%.4f queued=%s",
        I.castAb > 0 and tostring(A.key[I.castAb]) or "none",
        I.castEnd,
        tostring(I.channel),
        I.gcdStart,
        I.gcdDur,
        I.gcdLearned,
        tostring(I.queuedStrike)
    )
    for a = 1, A.n do
        VS.Cooldown(A.id[a], now)
        VS.Charges(A.id[a], now)
        out[#out + 1] = string.format(
            "ability %s qid=%d cost=%s read=%s len=%.2f flag=%d",
            tostring(A.key[a]),
            A.qid[a],
            tostring(I.CostOf(a)),
            tostring(A.readCost[a]),
            VS.CooldownLength(A.id[a]),
            A.flag[a]
        )
    end
    VS.Gcd(now)
end)
```
`VirtualState/Sources/Spellbook.lua`:
```lua
-- VirtualState/Sources/Spellbook.lua
-- Spellbook sources (spec §4.2, §4.5): each tracked ability's query ID (its highest known rank) and plain cost (out
-- of combat, shown by Snapshot() to confirm the spec's), and the cooldown flag edges: SPELL_UPDATE_COOLDOWN/SPELL_UPDATE_CHARGES read C_Spell.GetSpellCooldown
-- per tracked spell and log a `Cooldown` per changed plain `isActive` flag (b: 1 ready / 0 not), and the GCD's edge
-- from the GCD spell's flag (a = 0, c = 1). Only the plain flags are used; the times are secret in combat.
-- Credits: the field-by-field secrecy test after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Spellbook.lua (ResolveRanks).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Note = S.Plain, S.Stage, S.Note

--- Forever's GCD spell (cleanup Q6).
I.GCD_SPELL = 29515

-- By ability index: the last ready flag reported (-1 none, 0 not ready, 1 ready); the GCD's (-1, 0 idle, 1 active).
local last, gcdLast = {}, -1

-- The highest known rank of each ability (rank order: its `id`, then its `copy` IDs) and, out of combat, its plain
-- cost. Out of the hot path: build, SPELLS_CHANGED.
local function resolve(api)
    local A = I.ab
    for a = 1, A.n do
        local ids, q = A.ids[a], A.ids[a][1]
        for k = 1, #ids do
            if Plain(api, api.C_SpellBook.IsSpellKnown(ids[k])) == true then
                q = ids[k]
            end
        end
        A.qid[a] = q
        if not I.inCombat and A.slot[a] > 0 then
            local raw = api.C_Spell.GetSpellPowerCost(q) -- secret: Plain next, then each field
            local costs = Plain(api, raw)
            local first = type(costs) == "table" and Plain(api, costs[1])
            local cost = type(first) == "table" and Plain(api, first.cost)
            A.readCost[a] = type(cost) == "number" and cost or 0
        end
    end
end
I.ResolveSpells = resolve

I.OnBuild(function(def)
    for a = 1, #def.abilities do
        last[a] = -1
    end
    gcdLast = -1
    if I.api then
        resolve(I.api)
    end
end)

S.OnStart(function(api)
    if I.built then
        resolve(api)
    end
end)

S.On("SPELLS_CHANGED", nil, function(api)
    if I.built then
        resolve(api)
    end
end)

-- The plain ready flag of one spell: true ready, false on cooldown, nil when unreadable. A spell on the GCD only
-- reads ready. Allocates nothing (the client allocates the info table).
local function ready(api, spellID)
    local raw = api.C_Spell.GetSpellCooldown(spellID) -- secret: Plain next, then each field
    local info = Plain(api, raw)
    if type(info) ~= "table" then
        Note("GetSpellCooldown flags", "nil")
        return nil
    end
    local active, onGcd = Plain(api, info.isActive), Plain(api, info.isOnGCD)
    if active == nil then
        Note("GetSpellCooldown flags", "secret")
        return nil
    end
    Note("GetSpellCooldown flags", "readable")
    return not active or onGcd == true, active
end

local function onCooldown(api, t)
    if not I.built then
        return
    end
    local A, edge = I.ab, false
    for a = 1, A.n do
        local r = ready(api, A.qid[a])
        if r ~= nil then
            local v = r and 1 or 0
            if v ~= last[a] then
                last[a] = v
                edge = Stage(Obs.Cooldown, t, a, v, 0) or edge
            end
        end
    end
    local _, active = ready(api, I.GCD_SPELL)
    if active ~= nil then
        local v = active and 1 or 0
        if v ~= gcdLast then
            gcdLast = v
            edge = Stage(Obs.Cooldown, t, 0, v, 1) or edge
        end
    end
    if edge then
        S.Urgent("VS_COOLDOWN")
    end
end
S.On("SPELL_UPDATE_COOLDOWN", nil, onCooldown)
S.On("SPELL_UPDATE_CHARGES", nil, onCooldown)
```
`VirtualState/Sources/Casts.lua`:
```lua
-- VirtualState/Sources/Casts.lua
-- Own-cast sources (spec §4.2, §4.6): our UNIT_SPELLCAST_* events become staged observations (urgent lane) and,
-- synchronously in the handler, feed Hekili's across-reset caches through the hooks Adapter.lua sets in `I.feed`
-- (cast history, the real queue's CAST_FINISH and channel events, their removal). Poll 3: the on-next-swing queue.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Casts.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Direct, Urgent = S.Plain, S.Stage, S.Direct, S.Urgent

I.sentGUID = nil

local function ability(spellID)
    return spellID and I.ab.bySpell[spellID]
end

S.On("UNIT_SPELLCAST_SENT", "player", function(api, t, unit)
    if unit == "player" then
        I.sentGUID = Plain(api, api.UnitGUID("target"))
    end
end)

S.On("UNIT_SPELLCAST_START", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    local _, _, _, rawStart, rawEnd = api.UnitCastingInfo("player") -- secret: both through Plain next
    local start, finish = Plain(api, rawStart), Plain(api, rawEnd)
    if type(start) == "number" and type(finish) == "number" then
        Stage(Obs.CastStart, t, a, finish / 1000)
        local f = I.feed.CastStart
        if f then
            f(a, start / 1000, finish / 1000, I.sentGUID)
        end
    end
    Urgent("UNIT_SPELLCAST_START")
end)

S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    Stage(Obs.CastSuccess, t, a)
    local f = I.feed.CastSucceeded
    if f then
        f(a, spellID, I.sentGUID or Plain(api, api.UnitGUID("target")))
    end
    I.sentGUID = nil
    Urgent("UNIT_SPELLCAST_SUCCEEDED")
end)

local function stopped(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    Stage(Obs.CastStop, t, a)
    local f = I.feed.CastFailed
    if f then
        f(a)
    end
    Urgent("UNIT_SPELLCAST_FAILED")
end
S.On("UNIT_SPELLCAST_FAILED", "player", stopped)
S.On("UNIT_SPELLCAST_INTERRUPTED", "player", stopped)

S.On("UNIT_SPELLCAST_DELAYED", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    local _, _, _, _, rawEnd = api.UnitCastingInfo("player") -- secret: Plain next
    local finish = Plain(api, rawEnd)
    if type(finish) == "number" then
        Stage(Obs.CastDelay, t, a, finish / 1000)
    end
end)

S.On("UNIT_SPELLCAST_CHANNEL_START", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    local _, _, _, rawStart, rawEnd = api.UnitChannelInfo("player") -- secret: both through Plain next
    local start, finish = Plain(api, rawStart), Plain(api, rawEnd)
    if type(start) == "number" and type(finish) == "number" then
        Stage(Obs.ChannelStart, t, a, finish / 1000)
        local f = I.feed.ChannelStart
        if f then
            f(a, start / 1000, finish / 1000, I.sentGUID or Plain(api, api.UnitGUID("target")))
        end
    end
    Urgent("UNIT_SPELLCAST_CHANNEL_START")
end)

S.On("UNIT_SPELLCAST_CHANNEL_UPDATE", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    local _, _, _, _, rawEnd = api.UnitChannelInfo("player") -- secret: Plain next
    local finish = Plain(api, rawEnd)
    if type(finish) == "number" then
        Stage(Obs.ChannelUpdate, t, a, finish / 1000)
    end
end)

S.On("UNIT_SPELLCAST_CHANNEL_STOP", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    Stage(Obs.ChannelStop, t, a)
    local f = I.feed.ChannelStop
    if f then
        f(a)
    end
    Urgent("UNIT_SPELLCAST_CHANNEL_STOP")
end)

-- By ability index: the last queued answer (-1 none).
local queued = {}
I.OnBuild(function(def)
    for a = 1, #def.abilities do
        queued[a] = -1
    end
end)

-- Poll 3: the swing queue (C_Spell.IsCurrentSpell per on-next-swing ability), on change.
S.Poll(3, function(api, t)
    local A = I.ab
    for a = 1, A.n do
        if A.obj[a].onNextSwing then
            local q = Plain(api, api.C_Spell.IsCurrentSpell(A.qid[a]))
            if q ~= nil then
                local v = q and 1 or 0
                if v ~= queued[a] then
                    queued[a] = v
                    Direct(Obs.Queued, t, a, v)
                end
            end
        end
    end
end)
```
In `Hekili.toc`: after `VirtualState\Families\Player.lua` add `VirtualState\Families\Casts.lua`; after `VirtualState\Sources\Player.lua` add the two lines `VirtualState\Sources\Spellbook.lua` and `VirtualState\Sources\Casts.lua`.

- [ ] **Step 4: GCD spell 61304 → 29515 (cleanup Q6, spec §10)**

- `Classes.lua:2469`: `        id = 61304,` becomes `        id = 29515, -- Forever's GCD spell (retail: 61304; cleanup Q6)`.
- `UI.lua:1493`: `                            start, duration = GetSpellCooldown( 61304 )` becomes `                            start, duration = GetSpellCooldown( 29515 )`.
- `UI.lua:1694`: `            local gStart = GetSpellCooldown( 61304 )` becomes `            local gStart = GetSpellCooldown( 29515 )`.
- `Events.lua:1676`: `            state.gcd.lastStart = max( state.gcd.lastStart, ( GetSpellCooldown( 61304 ) ) )` becomes the same line with `29515`.
- `Options/Options.lua:4042`: `a.id ~= 61304 and` becomes `a.id ~= 29515 and` (the options list hides the GCD pseudo-ability by this id; the spec's §10 list misses this site).

Check: `grep -n 61304 *.lua Options/*.lua Forever/*.lua` prints nothing.

- [ ] **Step 5: Run the specs to see them pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `42 successes / 0 failures / 0 errors`.

- [ ] **Step 6: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [42 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 27 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [no problems found]
git status --short | grep '\.lua$' | awk '{print $2}' | xargs -r -n1 luac5.1 -p   # [no output]
```
- [ ] **Step 7: Commit**
```bash
git add Hekili.toc Classes.lua UI.lua Events.lua Options/Options.lua VirtualState
git commit -m "feat(virtualstate): casts, cooldowns, charges and the GCD; spellbook and own-cast sources; GCD spell 29515

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Resources and swings (the cost ladder, regen, swing steps, melee haste)

**Files:**
- Create: `VirtualState/Families/Resources.lua`, `VirtualState/Families/Swing.lua`, `VirtualState/Sources/Power.lua`, `VirtualState/Sources/Swing.lua`, `VirtualState/spec/resources_spec.lua`, `VirtualState/spec/swing_spec.lua`
- Modify: `Hekili.toc`

**Interfaces:**
- Consumes: Task 1; Task 3's `I.ab`, `I.CostOf`, `I.AgeConf`, `I.queuedStrike`, `I.lastCastT`.
- Produces: `I.res` (`n`, `type[r]`, `token[r]`, `max[r]`, `rest[r]`, `swing[r]`, `swingValue[r]`, `regE/regL/regH[r]`, `scale[r]`, `spread[r]`, `readable[r]`, `power[r]`, `regen[r]`, `slotOf[powerType] -> r`, `slotOfToken[token] -> r`), `I.SwingValue(r)`, `I.Ladder(r, cost, affordable, t, lag) -> snapped`, `I.ResourceShift(r, delta, t, event)`, `I.PIN_EXACT`, `I.SwingSpeedEst(hand)`, `I.haste0`; `VS.Power(powerType, now)`, `VS.Regen(powerType, now, casting)`, `VS.Swing(hand, now)`, `VS.SwingSpeed(hand, now)`, `VS.LastSwing(hand)`, `VS.Haste(now)`; the feed call `I.feed.Swing(hand, t, duration)` (Task 9 sets it).

- [ ] **Step 1: Write the failing specs**

`VirtualState/spec/resources_spec.lua` (golden scenario 2, TDF `tests/model/belief_spec.lua:197, 568`; the Review Focus case "never believes more than the maximum"):

```lua
-- VirtualState/spec/resources_spec.lua: the resources family (spec §6.1). Golden scenario 2 (TDF
-- tests/model/belief_spec.lua:197, 568): the cost ladder bounds a resource, and regen is measured between two pins
-- net of our own spends.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

local ENERGY = 3

local function within(want, got, tol)
    assert.is_true(math.abs(want - got) <= (tol or 1e-6), ("want %s, got %s"):format(want, got))
end

describe("resources", function()
    local ns, VS, I, S, Obs

    local function boot(def)
        local api = fake.new()
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        I.Build(def, 1)
        I.api = api
    end

    local function obs(kind, t, a, b, c)
        S.Direct(kind, t, a, b, c)
    end

    describe("a continuous resource (energy, 10/s declared)", function()
        local FINISHER, BUILDER = 1, 2

        before_each(function()
            boot({
                abilities = { { key = "finisher", spend = 25 }, { key = "builder", spend = 40 } },
                abilityIds = { { 1001 }, { 1002 } },
                abilitySlot = { 1, 1 },
                resources = { { key = "energy", type = ENERGY, token = "ENERGY", max = 100, rest = 100, regen = 10 } },
                auras = {},
                auraIds = {},
                talents = {},
                units = { "player", "target" },
            })
        end)

        it("bounds a resource by the cost ladder: affordable finisher (25), unaffordable builder (40)", function()
            obs(Obs.Usable, 10, FINISHER, 1, 0)
            obs(Obs.Usable, 10, BUILDER, 0, 1)
            I.Fold(10, false)
            local e = VS.Power(ENERGY, 10)
            assert.are.equal(25, e.lo)
            within(40 - I.EPS, e.hi)
            within(40 - I.EPS, e.est) -- the estimate (100 at rest) snaps into the interval
            within(0.5 * (1 - (15 - I.EPS) / 100), e.conf) -- a snap halves the confidence for a while
            assert.are.equal("pinned", e.basis)
            within(25 + 10 * 0.9 * 2, VS.Power(ENERGY, 12).lo, 1e-6) -- then it moves with regen
        end)

        it("measures regen between two pins, net of our own spends", function()
            local function pinAt(t)
                obs(Obs.Usable, t, BUILDER, 0, 1)
                obs(Obs.Usable, t, BUILDER, 1, 0)
            end
            pinAt(10) -- 40 at 10
            I.Fold(10, false)
            I.ResourceShift(1, -40, 10, Obs.CastSuccess) -- our builder: 0 at 10
            pinAt(12) -- 40 again at 12: (40 - 40 + 40) / 2 = 20/s, exactly 2x the declared 10/s: accepted
            I.Fold(12, false)
            local rr = VS.Regen(ENERGY, 12)
            within(10 + I.ALPHA * 10, rr.est)
            assert.is_true(rr.lo < rr.est and rr.est < rr.hi)
            assert.are.equal("modelled", rr.basis)
        end)

        it("pins an exact plain read and widens a late one by the regen spread", function()
            obs(Obs.Read, 20, 1, 55, I.ReadOf.Resource)
            I.Fold(20, false)
            local e = VS.Power(ENERGY, 20)
            assert.are.same({ 55, 55, 55, "observed" }, { e.est, e.lo, e.hi, e.basis })
        end)
    end)

    describe("a swing-paid resource (rage, 9 a main-hand swing)", function()
        before_each(function()
            boot(fs.def(fs.new(9)))
        end)

        it("starts at its rest value with basis default, and moves only at swings", function()
            local r = VS.Power(fs.RAGE, 0)
            assert.are.same({ 0, "default" }, { r.est, r.basis })
            obs(Obs.Swing, 5, 1, 2.6, 1)
            I.Fold(5, false)
            r = VS.Power(fs.RAGE, 7)
            assert.are.same({ 9, "modelled" }, { r.est, r.basis })
            within(9 * (1 - I.REGEN_SPREAD), r.lo)
            assert.are.equal(100, r.hi) -- nothing bounded it from above yet
        end)

        it("never believes more than the maximum, however many swings land", function()
            for k = 1, 20 do
                obs(Obs.Swing, 5 + 2.6 * k, 1, 2.6, 1)
            end
            I.Fold(60, false)
            local r = VS.Power(fs.RAGE, 60)
            assert.are.same({ 100, 100 }, { r.est, r.hi })
            assert.is_true(r.lo <= 100)
        end)

        it("pays no swing step while an on-next-swing strike is queued", function()
            obs(Obs.Queued, 4, 2, 1) -- heroic_strike (ability 2) queued
            obs(Obs.Swing, 5, 1, 2.6, 1)
            I.Fold(5, false)
            assert.are.equal(0, VS.Power(fs.RAGE, 5).est)
        end)

        it("alternates pinned (the ladder) and modelled (a swing, a cast) and keeps lo at or above what was seen", function()
            obs(Obs.Usable, 5, 3, 1, 0) -- rend (10) usable
            obs(Obs.Usable, 5, 2, 0, 1) -- heroic strike (15) short
            I.Fold(5, false)
            local r = VS.Power(fs.RAGE, 5)
            assert.are.equal("pinned", r.basis)
            assert.is_true(r.lo >= 10 and r.hi < 15)
            I.ResourceShift(1, -10, 6, Obs.CastSuccess)
            r = VS.Power(fs.RAGE, 6)
            assert.are.equal("modelled", r.basis)
            assert.is_true(r.hi - r.lo <= 15)
        end)

        it("keeps basis default at rest when a rung bounds the interval without moving the estimate", function()
            obs(Obs.Usable, 5, 1, 0, 1) -- battle shout (10) short at 0 rage, out of combat
            I.Fold(5, false)
            local r = VS.Power(fs.RAGE, 5)
            assert.are.same({ 0, "default" }, { r.est, r.basis })
            assert.is_true(r.hi < 10)
        end)

        it("opens the interval down to rest at combat end", function()
            obs(Obs.Usable, 5, 3, 1, 0)
            obs(Obs.CombatEnd, 6)
            I.Fold(6, false)
            assert.are.equal(0, VS.Power(fs.RAGE, 6).lo)
        end)

        it("answers an untracked power type with the unknown record", function()
            local u = VS.Power(99, 1)
            assert.are.same({ 0, "unknown" }, { u.conf, u.basis })
        end)
    end)
end)
```
`VirtualState/spec/swing_spec.lua` (golden scenario 1, TDF `tests/model/swing_replay_spec.lua:96`):
```lua
-- VirtualState/spec/swing_spec.lua: swings and melee haste (spec §6.4, §6.5). Golden scenario 1 (TDF
-- tests/model/swing_replay_spec.lua:96): swing anchors within tolerance from rage steps every 2.6 s with casts
-- interleaved, without a PLAYER_SWING after the pull.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("swings", function()
    local VS, I, S, Obs

    before_each(function()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        I.Build(fs.def(fs.new(9)), 90)
        I.api = fake.new()
    end)

    it("gives swing anchors within tolerance from rage steps every 2.6 s with casts interleaved", function()
        S.Direct(Obs.Swing, 90, 1, 2.6, 0) -- the out-of-combat speed read
        S.Direct(Obs.CombatStart, 100) -- a guess at weight 0.3
        local swings = {}
        for k = 0, 7 do
            swings[#swings + 1] = 100.4 + 2.6 * k -- the true swings: one rage step each
        end
        local casts = { 103.9, 109.1, 114.7 } -- our casts: their own power ticks don't pair
        local events = {}
        for _, t in ipairs(swings) do
            events[#events + 1] = { t, Obs.PowerTick }
        end
        for _, t in ipairs(casts) do
            events[#events + 1] = { t, Obs.CastSuccess }
            events[#events + 1] = { t + 0.01, Obs.PowerTick }
        end
        table.sort(events, function(a, b)
            return a[1] < b[1]
        end)
        local checked = 0
        for _, e in ipairs(events) do
            if e[2] == Obs.PowerTick then
                S.Direct(Obs.PowerTick, e[1], 1)
            else
                S.Direct(Obs.CastSuccess, e[1], 3)
            end
            I.Fold(e[1], false)
            if e[1] >= 104 then
                local now = e[1] + 0.05
                local want
                for _, s in ipairs(swings) do
                    if s > now then
                        want = want or s
                    end
                end
                want = want or swings[#swings] + 2.6
                local got = VS.Swing(1, now)
                assert.is_true(math.abs(got.est - want) <= I.SWING_TOL, ("at %.2f: %.3f vs %.3f"):format(now, got.est, want))
                checked = checked + 1
            end
        end
        assert.is_true(checked >= 10)
        local mh = VS.Swing(1, 119)
        assert.are.equal("modelled", mh.basis)
        assert.is_true(mh.conf > 0.4, tostring(mh.conf))
    end)

    it("anchors at PLAYER_SWING with weight 1 and takes its duration as the hasted speed", function()
        I.inCombat = true -- (the Player source sets it at PLAYER_REGEN_DISABLED)
        S.Direct(Obs.Swing, 90, 1, 3.6, 2) -- base (unhasted) speed
        S.Direct(Obs.CombatStart, 99)
        S.Direct(Obs.Swing, 100, 1, 3.0, 1)
        I.Fold(100, false)
        local s = VS.Swing(1, 100)
        assert.are.same({ 103, 1, "observed" }, { s.est, s.conf, s.basis })
        assert.are.equal(3.0, VS.SwingSpeed(1, 101).est)
        assert.are.equal(100, VS.LastSwing(1))
        assert.is_true(math.abs(VS.Haste(101).est - 1.2) < 1e-9)
        assert.are.equal("modelled", VS.Haste(101).basis)
        assert.is_true(math.abs(VS.Swing(1, 106).conf - 0.4) < 1e-9) -- falls linearly over SWING_DECAY
    end)

    it("clears anchors at combat end and keeps speeds", function()
        S.Direct(Obs.Swing, 100, 1, 2.6, 1)
        S.Direct(Obs.CombatEnd, 101)
        I.Fold(101, false)
        assert.are.same({ 0, 0 }, { VS.Swing(1, 102).est, VS.Swing(1, 102).conf })
        assert.are.equal(2.6, VS.SwingSpeed(1, 102).est)
    end)
end)
```
- [ ] **Step 2: Run them to see them fail**

Run: `~/src/TacoDogForever/.lua/bin/busted VirtualState/spec/resources_spec.lua VirtualState/spec/swing_spec.lua`
Expected: errors such as `attempt to call field 'Power' (a nil value)` and `attempt to call field 'Swing' (a nil value)`.

- [ ] **Step 3: Write the families and the sources**

`VirtualState/Families/Resources.lua`:

```lua
-- VirtualState/Families/Resources.lua
-- The resources family (spec §6.1): the cost ladder (a usability report pins or bounds a resource at the ability's
-- cost), exact reads, regen calibration between pins (an EMA), swing steps for a swing-paid resource (rage), our own
-- casts' changes (Adapter.lua, spec §5.3), and the Power/Regen accessors.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Resources.lua (calibrate :117-136, pin :218-263,
-- ladder :275-315, Applier Usable :327, Reader Resource :365-372, Applier PowerTick :378) and the resource conf of
-- src/TacoDogForever/Model/Belief.lua:695-699.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs, ReadOf = VS.Obs, I.ReadOf
local abs = math.abs

--- A flip pin measures regen only when the last short report was at most this long before it (TDF Belief.PIN_EXACT).
I.PIN_EXACT = 0.15

-- Usability as observed: unknown, not usable, usable, not usable for lack of its resource.
local UNKNOWN, NOT, YES, SHORT = -1, 0, 1, 2

-- By resource slot r. `swing[r]` is the hand that pays it (1 main, 2 off; 0: continuous regen). Continuous regen is
-- per second (regE/regL/regH); a swing-paid resource's step is the spec's model value x scale (spread around it).
local R = {
    n = 0,
    type = {},
    token = {},
    max = {},
    rest = {},
    swing = {},
    swingValue = {},
    est0 = {},
    lo0 = {},
    hi0 = {},
    regE = {},
    regL = {},
    regH = {},
    decl = {},
    dev = {},
    scale = {},
    spread = {},
    pinT = {},
    pinV = {},
    pinDelta = {},
    pinValid = {},
    snapT = {},
    readT = {},
    readable = {},
    power = {},
    regen = {},
}
I.res = R
R.slotOf, R.slotOfToken = {}, {}

-- By ability index a: the last usability answer and the last short report (cost, time).
local usable, shortCost, shortT = {}, {}, {}

local function clamp(v, max)
    if v < 0 then
        return 0
    elseif v > max then
        return max
    end
    return v
end

I.OnBuild(function(def, now)
    for k in pairs(R.slotOf) do
        R.slotOf[k] = nil
    end
    for k in pairs(R.slotOfToken) do
        R.slotOfToken[k] = nil
    end
    local list = def.resources
    R.n = #list
    for r = 1, R.n do
        local d = list[r]
        R.type[r], R.token[r] = d.type, d.token
        R.slotOf[d.type], R.slotOfToken[d.token] = r, r
        R.max[r] = d.max or 100
        R.rest[r] = d.rest or 0
        R.swing[r] = d.swing or 0
        R.swingValue[r] = d.swingValue or 0
        R.est0[r], R.lo0[r], R.hi0[r] = R.rest[r], 0, R.max[r]
        local rate = d.regen or 0
        R.decl[r] = rate
        R.regE[r], R.regL[r], R.regH[r] = rate, rate * (1 - I.REGEN_SPREAD), rate * (1 + I.REGEN_SPREAD)
        R.dev[r], R.scale[r], R.spread[r] = 0, 1, I.REGEN_SPREAD
        R.pinT[r], R.pinV[r], R.pinDelta[r], R.pinValid[r] = 0, 0, 0, false
        R.snapT[r], R.readT[r], R.readable[r] = -1e9, -1e9, false
        R.power[r] = I.NewBelief("power " .. tostring(d.key))
        R.regen[r] = I.NewBelief("regen " .. tostring(d.key))
        I.Sample(R.power[r], "default", R.rest[r], now, 0)
        I.Sample(R.regen[r], "default", rate, now, 0)
    end
    I.TRACKED.resource = R.type
    for a = 1, #def.abilities do
        usable[a], shortCost[a], shortT[a] = UNKNOWN, 0, 0
    end
end)

--- The spec's per-swing value of a swing-paid slot (a number, or the model's state-bound function). Allocates nothing.
function I.SwingValue(r)
    local v = R.swingValue[r]
    if type(v) == "function" then
        v = v(I.clock)
    end
    return type(v) == "number" and v or 0
end

-- Continuous regen between pins (swing-paid slots move only at swings).
I.OnAdvance(function(from, to)
    local dt = to - from
    for r = 1, R.n do
        if R.swing[r] == 0 and R.regH[r] ~= 0 then
            local max = R.max[r]
            R.est0[r] = clamp(R.est0[r] + R.regE[r] * dt, max)
            R.lo0[r] = clamp(R.lo0[r] + R.regL[r] * dt, max)
            R.hi0[r] = clamp(R.hi0[r] + R.regH[r] * dt, max)
        end
    end
end)

-- One regen measurement m (per second, between two pins ending at t) into the slot's regen (the EMA, TDF
-- calibrate). A swing-paid slot calibrates its step scale against the spec's value per second of swinging.
local function calibrate(r, m, t)
    local ref
    if R.swing[r] > 0 then
        local speed = I.SwingSpeedEst(R.swing[r])
        ref = speed > 0 and I.SwingValue(r) / speed or 0 -- nonzero: speed > 0 checked
    else
        ref = R.decl[r]
    end
    if ref == 0 then
        return
    end
    local ratio = m / ref -- nonzero: ref ~= 0 checked
    if ratio < 1 / I.REGEN_RATIO or ratio > I.REGEN_RATIO then
        return -- noise: a missed spend, a cap
    end
    if R.swing[r] > 0 then
        local scale = R.scale[r] + I.ALPHA * (ratio - R.scale[r])
        local dev = R.dev[r] + I.ALPHA * (abs(ratio - scale) - R.dev[r])
        R.scale[r], R.dev[r] = scale, dev
        R.spread[r] = dev > I.REGEN_SPREAD_MIN and dev or I.REGEN_SPREAD_MIN
        I.Sample(R.regen[r], "modelled", scale * ref, t, Obs.Usable)
    else
        local est = R.regE[r] + I.ALPHA * (m - R.regE[r])
        local dev = R.dev[r] + I.ALPHA * (abs(m - est) - R.dev[r])
        local floor = abs(ref) * I.REGEN_SPREAD_MIN
        local spread = dev > floor and dev or floor
        R.dev[r] = dev
        R.regE[r], R.regL[r], R.regH[r] = est, est - spread, est + spread
        I.Sample(R.regen[r], "modelled", est, t, Obs.Usable)
    end
end

-- Pins slot r at t to [v, v + width]; when this pin and the previous one both measure (exact, or `mid`), the regen
-- between them is a measurement. `origin` is "pinned" (a usability flip) or "observed" (an exact read).
local function pin(r, v, width, t, origin, event, mid)
    local exact = width <= 0
    local measures = exact or mid == true
    local vm = mid and v + width / 2 or v
    local dt = t - R.pinT[r]
    if measures and R.pinValid[r] and dt >= I.PIN_GAP then
        calibrate(r, (vm - R.pinV[r] - R.pinDelta[r]) / dt, t) -- nonzero: dt >= PIN_GAP (1 s)
    end
    local max = R.max[r]
    R.est0[r], R.lo0[r], R.hi0[r] = clamp(v + width / 2, max), clamp(v, max), clamp(v + width, max)
    R.snapT[r] = -1e9 -- an anchor, not a snap
    R.pinT[r], R.pinV[r], R.pinDelta[r], R.pinValid[r] = t, vm, 0, measures
    I.Sample(R.power[r], origin, R.est0[r], t, event)
end

-- One rung of the cost ladder: the resource was at least `c` (affordable) or below it, `lag` before t. A late bound
-- is moved by the most regen could have changed it and dropped if it then conflicts. True when it moved the estimate
-- (a snap: the estimate now stands on this rung, so the caller writes a `pinned` sample).
local function ladder(r, c, affordable, t, lag)
    if lag > 0 and R.swing[r] == 0 then
        if affordable then
            c = c + R.regL[r] * lag
            if c > R.hi0[r] then
                return false
            end
        else
            c = c + R.regH[r] * lag
            if c - I.EPS < R.lo0[r] then
                return false
            end
        end
    end
    local snapped = false
    if affordable then
        if R.lo0[r] < c then
            R.lo0[r] = c
        end
        if R.est0[r] < c then
            R.est0[r], R.snapT[r], snapped = c, t, true
        end
        if R.hi0[r] < c then
            R.hi0[r] = c -- the newest bound wins
        end
    else
        local top = c - I.EPS
        if R.hi0[r] > top then
            R.hi0[r] = top
        end
        if R.est0[r] > top then
            R.est0[r], R.snapT[r], snapped = top, t, true
        end
        if R.lo0[r] > top then
            R.lo0[r] = top < 0 and 0 or top -- the newest bound wins
        end
    end
    return snapped
end
I.Ladder = ladder

I.On(Obs.Usable, function(o, t, lag)
    local a = o.a
    local now = o.b == 1 and YES or (o.c == 1 and SHORT or NOT)
    local was = usable[a]
    usable[a] = now
    local r = I.ab.slot[a]
    if r == 0 or now == NOT or R.readable[r] then
        return
    end
    local c = I.CostOf(a)
    if c <= 0 then
        return
    end
    if was == SHORT and now == YES and lag <= 0 and abs(c - shortCost[a]) <= I.EPS then
        -- It just became affordable at an unchanged cost: it crossed the cost since the last short report.
        if R.swing[r] > 0 then
            -- a swing-paid resource crosses at a swing: [c, c + one step), measured at its midpoint
            local step = I.SwingValue(r) * (R.scale[r] + R.spread[r])
            pin(r, c, step, t, "pinned", Obs.Usable, true)
        else
            local width = R.regH[r] * (t - shortT[a])
            pin(r, c, t - shortT[a] <= I.PIN_EXACT and 0 or width, t, "pinned", Obs.Usable)
        end
    elseif ladder(r, c, now == YES, t, lag) then
        I.Sample(R.power[r], "pinned", R.est0[r], t, Obs.Usable)
    end
    if now == SHORT then
        shortCost[a], shortT[a] = c, t - lag
    end
end)

I.On(Obs.Read, function(o, t, lag)
    local r, c = o.a, o.c
    if c == ReadOf.Resource then
        if I.inCombat then
            R.readable[r] = true -- plain in combat: its exact reads keep it, its spenders' answers are no rungs
        end
        if lag > 0 and R.swing[r] == 0 then
            pin(r, o.b + R.regL[r] * lag, (R.regH[r] - R.regL[r]) * lag, t, "observed", Obs.Read)
        else
            pin(r, o.b, 0, t, "observed", Obs.Read)
        end
    elseif c == ReadOf.Max then
        R.max[r] = o.b > 0 and o.b or R.max[r]
    elseif c == ReadOf.Regen and R.swing[r] == 0 then
        R.decl[r], R.readT[r] = o.b, t
        R.regE[r], R.regL[r], R.regH[r] = o.b, o.b, o.b
        I.Sample(R.regen[r], "observed", o.b, t, Obs.Read)
    end
end)

-- A landed swing pays each slot of its hand one step, unless an on-next-swing strike took that swing (spec §6.4).
I.On(Obs.Swing, function(o, t)
    if o.c ~= 1 then
        return
    end
    local hand = o.a
    for r = 1, R.n do
        if R.swing[r] == hand and not (hand == 1 and I.queuedStrike) then
            local v, max = I.SwingValue(r), R.max[r]
            local s, sp = R.scale[r], R.spread[r]
            R.est0[r] = clamp(R.est0[r] + v * s, max)
            R.lo0[r] = clamp(R.lo0[r] + v * (s - sp), max)
            R.hi0[r] = clamp(R.hi0[r] + v * (s + sp), max)
            I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.Swing)
        end
    end
end)

-- Our own cast succeeded: the game had its cost (a rung), before Adapter.lua applies the cast through the spec. An
-- on-next-swing strike is paid at its swing, so its press says nothing.
I.On(Obs.CastSuccess, function(o, t, lag)
    local a = o.a
    local r = I.ab.slot[a]
    if r == 0 or I.ab.obj[a].onNextSwing then
        return
    end
    local c = I.CostOf(a)
    if c > 0 and ladder(r, c, true, t, lag) then
        I.Sample(R.power[r], "pinned", R.est0[r], t, Obs.CastSuccess)
    end
end)

-- Out of combat a resource falls toward its rest value: the interval opens down to it (lo never over-promises).
I.On(Obs.CombatEnd, function()
    for r = 1, R.n do
        if R.rest[r] < R.lo0[r] then
            R.lo0[r] = R.rest[r]
        end
        R.pinValid[r] = false
    end
end)

--- Our own cast changed slot r by `delta` at t (spec §5.3): the interval moves by the same amount, written as a
--- `modelled` sample. Allocates nothing.
function I.ResourceShift(r, delta, t, event)
    local max = R.max[r]
    R.est0[r] = clamp(R.est0[r] + delta, max)
    R.lo0[r] = clamp(R.lo0[r] + delta, max)
    R.hi0[r] = clamp(R.hi0[r] + delta, max)
    R.pinDelta[r] = R.pinDelta[r] + delta
    I.Sample(R.power[r], "modelled", R.est0[r], t, event)
end

--- (spec §3.2) The believed amount of a power type at `now`: the clock values plus continuous regen x dt, each clamped
--- to [0, max]; conf 1 - (hi - lo) / max, halved within SNAP_HOLD of a snap. Allocates nothing.
function VS.Power(powerType, now)
    local r = R.slotOf[powerType]
    if not r then
        return I.UNKNOWN
    end
    local rec, max, dt = R.power[r], R.max[r], I.Dt(now)
    if R.swing[r] > 0 then
        dt = 0 -- a swing-paid resource moves only at swings
    end
    local est = clamp(R.est0[r] + R.regE[r] * dt, max)
    local lo = clamp(R.lo0[r] + R.regL[r] * dt, max)
    local hi = clamp(R.hi0[r] + R.regH[r] * dt, max)
    if lo > est then
        lo = est
    end
    if hi < est then
        hi = est
    end
    rec.est, rec.lo, rec.hi = est, lo, hi
    local conf = 1 - (hi - lo) / max -- nonzero: max > 0 (the default 100, or a plain read above 0)
    if now - R.snapT[r] < I.SNAP_HOLD then
        conf = conf * 0.5
    end
    rec.conf = conf
    return rec
end

--- (spec §3.2) The believed regen per second of a power type. A swing-paid resource's is its calibrated step per
--- second of swinging. `casting` selects the in-cast rate (Phase 1 has one rate). Allocates nothing.
function VS.Regen(powerType, now, casting)
    local r = R.slotOf[powerType]
    if not r then
        return I.UNKNOWN
    end
    local rec = R.regen[r]
    if R.swing[r] > 0 then
        local speed = I.SwingSpeedEst(R.swing[r])
        local per = speed > 0 and I.SwingValue(r) / speed or 0 -- nonzero: speed > 0 checked
        local s, sp = R.scale[r], R.spread[r]
        rec.est, rec.lo, rec.hi = per * s, per * (s - sp), per * (s + sp)
        rec.conf = s > 0 and 1 - sp / s or 0 -- nonzero: s > 0 checked
    else
        local est = R.regE[r]
        rec.est, rec.lo, rec.hi = est, R.regL[r], R.regH[r]
        local conf = est ~= 0 and 1 - (R.regH[r] - est) / abs(est) or 0 -- nonzero: est ~= 0 checked
        rec.conf = conf < 0 and 0 or conf
    end
    return rec
end

I.OnSnapshot(function(out, now)
    for r = 1, R.n do
        VS.Power(R.type[r], now)
        VS.Regen(R.type[r], now)
        out[#out + 1] = string.format(
            "resource %s type=%d max=%d swing=%d scale=%.2f",
            tostring(R.token[r]),
            R.type[r],
            R.max[r],
            R.swing[r],
            R.scale[r]
        )
    end
end)
```
`VirtualState/Families/Swing.lua`:
```lua
-- VirtualState/Families/Swing.lua
-- The swing family (spec §6.4) and melee haste (§6.5): per hand an anchor and a speed; the next swing is
-- anchorT + k x speed. Anchors carry weights: PLAYER_SWING 1.0, a paired rage step 0.5, combat start 0.3; conf is the
-- anchor's weight falling linearly to 0 over SWING_DECAY. The observed swing duration is the hasted speed; melee
-- haste is observed out of combat and modelled in combat as the base speed / the observed duration.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Swing.lua (weights :54, confAt :181-188, after
-- :196-205, Applier Swing :602, Listener PowerTick :656, CombatStart :710, CombatEnd :723) and Belief/Player.lua
-- (Applier Haste :130).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs
local floor = math.floor

local W_SWING, W_PAIR, W_COMBAT = 1, 0.5, 0.3

local anchorT, speed, base, last, w0, confAt = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
local swingRec, speedRec, haste = {}, {}, nil
I.haste0 = 1

I.OnBuild(function(def, now)
    for h = 1, 2 do
        swingRec[h] = I.NewBelief(h == 1 and "swing main" or "swing off")
        speedRec[h] = I.NewBelief(h == 1 and "swing speed main" or "swing speed off")
        I.Sample(speedRec[h], "default", h == 1 and 2 or 0, now, 0)
        if speed[h] == 0 and h == 1 then
            speed[h] = 2
        end
    end
    haste = I.NewBelief("haste melee")
    I.Sample(haste, "default", 1, now, 0)
end)

--- The believed speed of hand h (seconds; 0: no weapon). Allocates nothing.
function I.SwingSpeedEst(h)
    return speed[h]
end

local function anchor(h, t, w)
    anchorT[h], w0[h], confAt[h] = t, w, t
end

I.On(Obs.Swing, function(o, t)
    local h, c = o.a, o.c
    if h ~= 1 and h ~= 2 then
        return
    end
    if c == 1 then
        anchor(h, o.t, W_SWING)
        last[h] = o.t
        if o.b > 0 then
            speed[h] = o.b
            I.Sample(speedRec[h], "observed", o.b, t, Obs.Swing)
            if h == 1 and base[1] > 0 and I.inCombat then
                I.haste0 = base[1] / o.b -- nonzero: o.b > 0 checked
                I.Sample(haste, "modelled", I.haste0, t, Obs.Swing)
            end
        end
        I.Sample(swingRec[h], "observed", o.t + speed[h], t, Obs.Swing)
    elseif c == 0 then
        speed[h] = o.b
        I.Sample(speedRec[h], "observed", o.b, t, Obs.Swing)
    elseif c == 2 then
        base[h] = o.b
    end
end)

I.On(Obs.Haste, function(o, t)
    if o.c == 1 and o.b > 0 then
        I.haste0 = o.b
        I.Sample(haste, "observed", o.b, t, Obs.Haste)
    end
end)

-- The first predicted swing strictly after t (TDF after()). The caller checks speed > 0.
local function after(h, t)
    local sp, at = speed[h], anchorT[h]
    local p = at + (floor((t - at) / sp) + 1) * sp -- nonzero: callers check speed > 0
    if p <= t then
        p = p + sp
    elseif p - sp > t then
        p = p - sp
    end
    return p
end

-- A paired rage step (spec §6.4): a PowerTick of a swing-paid resource that no PLAYER_SWING and no own cast
-- explains is a landed swing when it falls one swing after the previous such tick (a pair: anchor at weight 0.5 when
-- the clock is weaker) or on a predicted swing (a confirmation: the clock re-anchors there).
local prevTick = { 0, 0 }
local OWN_TICK = 0.1 -- TDF Belief.OWN_TICK: a tick this close to our cast is the cast's own change

I.On(Obs.PowerTick, function(o, t)
    local h = I.res.swing[o.a]
    if not h or h == 0 or speed[h] <= 0 then
        return
    end
    local x = o.t
    if x - last[h] <= I.SWING_TOL or x - I.lastCastT <= OWN_TICK then
        return
    end
    local sp = speed[h]
    if anchorT[h] > 0 then
        local p = after(h, x - I.SWING_TOL)
        if p - x <= I.SWING_TOL and x - p <= I.SWING_TOL then
            anchorT[h], confAt[h] = x, x
            if w0[h] < W_PAIR then
                w0[h] = W_PAIR
            end
            I.Sample(swingRec[h], "modelled", x + sp, t, Obs.PowerTick)
            prevTick[h] = x
            return
        end
    end
    local gap = x - prevTick[h] - sp
    if prevTick[h] > 0 and gap <= I.SWING_TOL and gap >= -I.SWING_TOL then
        local age = x - confAt[h]
        local c = w0[h] * (1 - age / I.SWING_DECAY) -- nonzero: SWING_DECAY is a constant
        if anchorT[h] == 0 or c < W_PAIR then
            anchor(h, x, W_PAIR)
            I.Sample(swingRec[h], "modelled", x + sp, t, Obs.PowerTick)
        end
    end
    prevTick[h] = x
end)

I.On(Obs.CombatStart, function(o, t)
    for h = 1, 2 do
        if speed[h] > 0 and w0[h] < W_COMBAT then
            anchor(h, o.t, W_COMBAT)
            I.Sample(swingRec[h], "modelled", o.t + speed[h], t, Obs.CombatStart)
        end
    end
end)

I.On(Obs.CombatEnd, function()
    for h = 1, 2 do
        anchorT[h], w0[h], prevTick[h] = 0, 0, 0
    end
end)

--- (spec §3.2) The next swing of hand 1 (main) or 2 (off) after now.
function VS.Swing(hand, now)
    local rec = swingRec[hand]
    if not rec then
        return I.UNKNOWN
    end
    if speed[hand] > 0 and anchorT[hand] > 0 then
        local p = after(hand, now)
        rec.est, rec.lo, rec.hi = p, p, p
        local age = now - confAt[hand]
        local f = age <= 0 and 1 or 1 - age / I.SWING_DECAY -- nonzero: SWING_DECAY is a constant
        rec.conf = f > 0 and w0[hand] * f or 0
    else
        rec.est, rec.lo, rec.hi, rec.conf = 0, 0, 0, 0
    end
    return rec
end

--- (spec §3.2) The believed swing speed of a hand (seconds): PLAYER_SWING durations and out-of-combat reads.
function VS.SwingSpeed(hand, now)
    local rec = speedRec[hand]
    if not rec then
        return I.UNKNOWN
    end
    local s = speed[hand]
    rec.est, rec.lo, rec.hi = s, s, s
    I.AgeConf(rec, now)
    return rec
end

--- (spec §3.1) The absolute time of the last observed swing of a hand, 0 when none.
function VS.LastSwing(hand)
    return last[hand] or 0
end

--- (spec §3.2) The melee haste multiplier.
function VS.Haste(now)
    if not haste then
        return I.UNKNOWN
    end
    haste.est, haste.lo, haste.hi = I.haste0, I.haste0, I.haste0
    I.AgeConf(haste, now)
    return haste
end

I.OnSnapshot(function(out, now)
    for h = 1, 2 do
        VS.Swing(h, now)
        VS.SwingSpeed(h, now)
        out[#out + 1] = string.format(
            "hand %d anchor=%.2f speed=%.3f base=%.3f last=%.2f weight=%.1f",
            h,
            anchorT[h],
            speed[h],
            base[h],
            last[h],
            w0[h]
        )
    end
    VS.Haste(now)
end)
```
`VirtualState/Sources/Power.lua`:
```lua
-- VirtualState/Sources/Power.lua
-- Power sources (spec §4.2, §4.3): UNIT_POWER_FREQUENT ticks, max reads, poll 1 (readable resources, their maxima,
-- the out-of-combat regen read) and poll 2 (the usability ladder: C_Spell.IsSpellUsable per tracked spender, a
-- secret in either return being no news), plus the usability events (urgent: a flip is news).
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Power.lua (the usability ladder :64-99, Sources.Usability at :70).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, ReadOf = VS.Obs, I.ReadOf
local Plain, Stage, Direct, Note = S.Plain, S.Stage, S.Direct, S.Note

-- By ability index: the last usability answer reported (-1 none, 0 not, 1 usable, 2 short).
local last = {}

-- Asks every tracked spender (an ability whose cost is paid from a tracked resource). `onlyChanged`: report only
-- the answers that changed (the events); `direct`: into the log (the poll) rather than staged. True when any
-- answer changed. Allocates nothing.
local function usability(api, t, onlyChanged, direct)
    local A = I.ab
    local any = false
    for a = 1, A.n do
        if A.slot[a] > 0 then
            local rawOk, rawShort = api.C_Spell.IsSpellUsable(A.qid[a]) -- secret: both tested with issecretvalue next
            if api.issecretvalue(rawOk) or api.issecretvalue(rawShort) then
                Note("IsSpellUsable", "secret")
            else
                local ok, short = Plain(api, rawOk), Plain(api, rawShort)
                if ok ~= nil then
                    Note("IsSpellUsable", "readable")
                    local state = ok and 1 or (short and 2 or 0)
                    if last[a] ~= state then
                        any = true
                    end
                    if not onlyChanged or last[a] ~= state then
                        last[a] = state
                        local b, c = ok and 1 or 0, (not ok and short) and 1 or 0
                        if direct then
                            Direct(Obs.Usable, t, a, b, c)
                        else
                            Stage(Obs.Usable, t, a, b, c)
                        end
                    end
                end
            end
        end
    end
    return any
end

I.OnBuild(function(def)
    for a = 1, #def.abilities do
        last[a] = -1
    end
end)

local function onUsable(api, t)
    if I.built and usability(api, t, true, false) then
        S.Urgent("VS_USABLE")
    end
end
S.On("SPELL_UPDATE_USABLE", nil, onUsable)
S.On("ACTION_USABLE_CHANGED", nil, onUsable)

S.On("UNIT_POWER_FREQUENT", "player", function(api, t, unit, token)
    local r = unit == "player" and token and I.res.slotOfToken[token]
    if r then
        Stage(Obs.PowerTick, t, r)
    end
end)

local function readMax(api, t, direct)
    local R = I.res
    for r = 1, R.n do
        local raw = api.UnitPowerMax("player", R.type[r]) -- secret: Plain next
        local max = Plain(api, raw)
        if type(max) == "number" and max > 0 and max ~= R.max[r] then
            if direct then
                Direct(Obs.Read, t, r, max, ReadOf.Max)
            else
                Stage(Obs.Read, t, r, max, ReadOf.Max)
            end
        end
    end
end

S.On("UNIT_MAXPOWER", "player", function(api, t, unit)
    if unit == "player" then
        readMax(api, t, false)
    end
end)

S.On("UNIT_DISPLAYPOWER", "player", function(api, t, unit)
    if unit == "player" then
        readMax(api, t, false)
    end
end)

-- Poll 1: readable resources (types plain in combat, e.g. combo points), maxima, the out-of-combat regen read.
S.Poll(1, function(api, t)
    local R = I.res
    readMax(api, t, true)
    for r = 1, R.n do
        local raw = api.UnitPower("player", R.type[r]) -- secret: Plain next
        Note("UnitPower", S.StatusOf(api, raw))
        local v = Plain(api, raw)
        if type(v) == "number" then
            Direct(Obs.Read, t, r, v, ReadOf.Resource)
        end
        if not I.inCombat and R.swing[r] == 0 then
            local rawIn, rawAct = api.GetPowerRegenForPowerType(R.type[r]) -- secret: Plain next
            local act = Plain(api, rawAct)
            if Plain(api, rawIn) ~= nil and type(act) == "number" and act ~= R.regE[r] then
                Direct(Obs.Read, t, r, act, ReadOf.Regen)
            end
        end
    end
end)

-- Poll 2: the usability ladder, every answer a rung.
S.Poll(2, function(api, t)
    usability(api, t, false, true)
end)
```
`VirtualState/Sources/Swing.lua`:
```lua
-- VirtualState/Sources/Swing.lua
-- Swing sources (spec §4.2): PLAYER_SWING (payload swingDuration, swingType; plain in combat) is a `Swing` with
-- a = swingType + 1, b = the duration, c = 1, staged on the urgent lane, and synchronously feeds Hekili's
-- `state.swings.*_actual/_projected` through Adapter.lua's hook (spec §4.6). Out of combat, UNIT_ATTACK_SPEED and
-- PLAYER_EQUIPMENT_CHANGED (and login, and combat end) read both hands' speeds (c = 0), the unhasted base speeds
-- (c = 2, speed x (1 + melee haste / 100)) and the melee haste multiplier (`Haste`, c = 1).
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Swing.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Note = S.Plain, S.Stage, S.Note

S.On("PLAYER_SWING", nil, function(api, t, duration, swingType)
    if type(duration) ~= "number" or type(swingType) ~= "number" or swingType > 1 then
        return
    end
    local hand = swingType + 1
    Stage(Obs.Swing, t, hand, duration, 1)
    local f = I.feed.Swing
    if f then
        f(hand, t, duration)
    end
    S.Urgent("PLAYER_SWING")
end)

-- Both hands' speeds, base speeds and the melee haste, when plain (out of combat in practice). Allocates nothing.
local function readSpeeds(api, t)
    local rawMain, rawOff = api.UnitAttackSpeed("player") -- secret: tested with issecretvalue, read through Plain
    if api.issecretvalue(rawMain) or api.issecretvalue(rawOff) then
        Note("UnitAttackSpeed", "secret")
        return
    end
    local main, off = Plain(api, rawMain), Plain(api, rawOff)
    Note("UnitAttackSpeed", type(main) == "number" and "readable" or "nil")
    main = type(main) == "number" and main > 0 and main or 0
    off = type(off) == "number" and off > 0 and off or 0
    Stage(Obs.Swing, t, 1, main, 0)
    Stage(Obs.Swing, t, 2, off, 0)
    local p = Plain(api, api.GetMeleeHaste())
    if type(p) == "number" and p > -100 then
        local k = 1 + p / 100
        Stage(Obs.Haste, t, 0, k, 1)
        Stage(Obs.Swing, t, 1, main * k, 2)
        Stage(Obs.Swing, t, 2, off * k, 2)
    end
end

local function outOfCombat(api, t)
    if not I.inCombat then
        readSpeeds(api, t)
    end
end
S.On("UNIT_ATTACK_SPEED", "player", outOfCombat)
S.On("PLAYER_EQUIPMENT_CHANGED", nil, outOfCombat)
S.On("PLAYER_REGEN_ENABLED", nil, outOfCombat)
S.OnStart(outOfCombat)
```
In `Hekili.toc`: after `VirtualState\Families\Casts.lua` add `VirtualState\Families\Resources.lua` and `VirtualState\Families\Swing.lua`; after `VirtualState\Sources\Casts.lua` add `VirtualState\Sources\Power.lua` and `VirtualState\Sources\Swing.lua`.

- [ ] **Step 4: Run the specs to see them pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `55 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [55 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 31 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [no problems found]
git status --short | grep '\.lua$' | awk '{print $2}' | xargs -r -n1 luac5.1 -p   # [no output]
```
- [ ] **Step 6: Commit**
```bash
git add Hekili.toc VirtualState
git commit -m "feat(virtualstate): resources (cost ladder, pins, regen EMA, swing steps) and swings (anchors, speeds, melee haste)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Auras, per-target memory and the target's cast

**Files:**
- Create: `VirtualState/Families/Auras.lua`, `VirtualState/Families/TargetCast.lua`, `VirtualState/Sources/Auras.lua`, `VirtualState/Sources/Target.lua`, `VirtualState/spec/auras_spec.lua`
- Modify: `Hekili.toc`

**Interfaces:**
- Consumes: Task 1; Task 3's `I.AgeConf`.
- Produces: `I.auras` (`n` units, `nAura`, `token[u]`, `index[unit] -> u`, `id[j]`, `obj[j]`, `bySpell[spellID] -> j`, `exp0[u][j]`, `applied[u][j]`, `stacks[u][j]`, `inst[u][j]`, `harm[u][j]`, `gen[u]`), `I.AURA_UNIT` (4096), `I.AURA_STACK` (16), `I.AuraModel(u, j, applied, expires, stacks, t, event, harmful)`, `I.curSlot`, `I.WalkAuras(api, u, unit, t)` (the target swap also runs at Start and at each rebuild, so a target held at a `/reload` gets its memory slot), `I.TARGET_CAST_DEFAULT` (2); `VS.Aura(unit, spellID, now)`, `VS.AuraAt(unit, filter, i, now)`, `VS.AuraByInstance(unit, instanceID, now)`, `VS.AuraGen(unit)`, `VS.Count.WithAura(spellID, now)`, `VS.TargetCastFacts()`, `VS.TargetCast(now)`. Unit index 1 is `"player"`, 2 `"target"`.

- [ ] **Step 1: Write the failing spec**

`VirtualState/spec/auras_spec.lua` (the Review Focus case "forgets the target's auras when the target is cleared or dies"):

```lua
-- VirtualState/spec/auras_spec.lua: the auras family and source (spec §4.5, §6.3).
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("auras", function()
    local VS, I, S, Obs, ctl
    local SHOUT, REND = 1, 2 -- aura indices in fs.def

    before_each(function()
        local api
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    local function fold(t)
        ctl.Tick(t)
        I.Fold(t, false)
        I.Settle(t)
    end

    it("reads a plain walk: expiry, stacks, an invented stable instance ID, AuraGen", function()
        ctl.now = 10
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SHOUT, expirationTime = 130, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        fold(10)
        local rec, stacks, applied, inst = VS.Aura("player", fs.SHOUT, 10)
        assert.are.same({ 130, 1, 10, "observed" }, { rec.est, stacks, applied, rec.basis })
        assert.is_true(inst > 0)
        local gen = VS.AuraGen("player")
        ctl.Fire("UNIT_AURA", "player")
        fold(11)
        assert.are.equal(gen, VS.AuraGen("player")) -- nothing changed
        assert.are.equal(inst, select(4, VS.Aura("player", fs.SHOUT, 11)))
        local id, r2 = VS.AuraByInstance("player", inst, 11)
        assert.are.same({ fs.SHOUT, 130 }, { id, r2.est })
    end)

    it("in combat, counts a missing aura down only after it was seen readable in combat", function()
        ctl.now = 10
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SHOUT, expirationTime = 130, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        fold(10)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.auras.player.HELPFUL[1] = nil
        ctl.Fire("UNIT_AURA", "player")
        fold(12)
        assert.is_truthy(VS.Aura("player", fs.SHOUT, 12)) -- a miss may be the client hiding it
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SHOUT, expirationTime = 130, applications = 0 }
        ctl.Fire("UNIT_AURA", "player")
        ctl.auras.player.HELPFUL[1] = nil
        ctl.Fire("UNIT_AURA", "player")
        fold(13)
        assert.is_nil(VS.Aura("player", fs.SHOUT, 13))
    end)

    it("stops at a walk that raises or answers a secret, and logs nothing for it", function()
        ctl.now = 10
        ctl.auraError.target = true
        ctl.Fire("UNIT_AURA", "target")
        ctl.auraError.target = nil
        ctl.auras.target.HARMFUL[1] = fake.SECRET
        ctl.Fire("UNIT_AURA", "target")
        assert.are.equal(0, I.log.n)
        assert.are.equal("secret", S.status["aura walk"])
    end)

    it("orders AuraAt by applied time, filters by helpful/harmful and by est > now", function()
        I.AuraModel(2, REND, 5, 20, 1, 5, Obs.CastSuccess, true)
        I.AuraModel(1, SHOUT, 6, 126, 1, 6, Obs.CastSuccess, false)
        assert.are.equal(fs.REND, (VS.AuraAt("target", "HARMFUL", 1, 7)))
        assert.is_nil(VS.AuraAt("target", "HELPFUL", 1, 7))
        assert.are.equal(fs.SHOUT, (VS.AuraAt("player", "HELPFUL", 1, 7)))
        assert.is_nil(VS.AuraAt("target", "HARMFUL", 1, 21))
        fold(21)
        assert.is_nil(VS.Aura("target", fs.REND, 21)) -- expired by time
    end)

    it("gives a target already held at a /reload its memory slot (Start, then the first build), so its death is seen", function()
        local api2, ctl2 = fake.new()
        ctl2.now = 1
        local ns2 = load.module()
        local VS2, I2 = ns2.VirtualState, ns2.VirtualStateInternal
        VS2.Start(api2) -- PLAYER_LOGIN: a target is held (ctl2.guid.target), nothing built yet
        I2.Build(fs.def(fs.new(9)), 1) -- the first SpecChanged (PLAYER_ENTERING_WORLD); no PLAYER_TARGET_CHANGED comes
        ctl2.Tick(1)
        I2.Fold(1, false)
        assert.is_true(I2.curSlot > 0)
        I2.AuraModel(2, REND, 1, 20, 1, 1, Obs.CastSuccess, true)
        ctl2.dead.target = true
        I2.Sources.RunPolls(2)
        I2.Fold(2, false)
        assert.is_nil(VS2.Aura("target", fs.REND, 2))
    end)

    it("forgets the target's auras when the target is cleared or dies", function()
        ctl.now = 10
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(10)
        I.AuraModel(2, REND, 10, 25, 1, 10, Obs.CastSuccess, true)
        ctl.guid.target = nil
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(11)
        assert.is_nil(VS.Aura("target", fs.REND, 11))
        ctl.guid.target = "Creature-1"
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(12)
        assert.are.equal(25, VS.Aura("target", fs.REND, 12).est) -- still remembered
        ctl.dead.target = true
        ctl.Tick(13)
        I.Sources.RunPolls(13)
        I.Fold(13, false)
        assert.is_nil(VS.Aura("target", fs.REND, 13))
    end)

    it("remembers what it believed about a target across a swap back", function()
        ctl.now = 10
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(10)
        I.AuraModel(2, REND, 10, 25, 1, 10, Obs.CastSuccess, true)
        ctl.guid.target = "Creature-2"
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(11)
        assert.is_nil(VS.Aura("target", fs.REND, 11))
        assert.are.equal(1, VS.Count.WithAura(fs.REND, 11)) -- remembered on the other target
        ctl.guid.target = "Creature-1"
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(12)
        assert.are.equal(25, VS.Aura("target", fs.REND, 12).est)
    end)
end)
```
- [ ] **Step 2: Run it to see it fail**

Run: `~/src/TacoDogForever/.lua/bin/busted VirtualState/spec/auras_spec.lua`
Expected: errors such as `attempt to call field 'Aura' (a nil value)` and `attempt to call field 'AuraModel' (a nil value)`.

- [ ] **Step 3: Write the families and the sources**

`VirtualState/Families/Auras.lua`:

```lua
-- VirtualState/Families/Auras.lua
-- The auras family (spec §6.3): per unit and tracked aura, the believed expiry, stacks, applied time and an invented
-- stable instance ID; plain walk reads (observed), our casts' handler writes (modelled, Adapter.lua), expiry by time;
-- per-target memory by GUID slot (TARGET_CAP); the index order for AuraAt; AuraGen; Count.WithAura.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Auras.lua and Belief/Targets.lua (Applier TargetSwap
-- :147); the aura conf of src/TacoDogForever/Model/Belief.lua:709.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs, ReadOf = VS.Obs, I.ReadOf
local HUGE = math.huge

--- An aura Read's `a` packs the unit index and the aura index; its `c` packs ReadOf.Aura and the stacks.
I.AURA_UNIT = 4096 -- a = (unit - 1) * AURA_UNIT + aura (Hekili registers hundreds of auras)
I.AURA_STACK = 16 -- c = ReadOf.Aura + stacks * AURA_STACK

local U = {
    n = 0,
    nAura = 0,
    token = {},
    index = {},
    id = {},
    obj = {},
    bySpell = {},
    exp0 = {},
    applied = {},
    stacks = {},
    inst = {},
    harm = {},
    seq = {},
    rec = {},
    ord = {},
    ordN = {},
    gen = {},
    mem = {},
}
I.auras = U
I.nextInst = 0

-- Per-target memory (spec §6.3): TARGET_CAP slots, each a copy of the target's arrays; slot 0 is "no target".
local memExp, memApplied, memStacks, memInst = {}, {}, {}, {}
I.curSlot = 0

I.OnBuild(function(def, now)
    for k in pairs(U.bySpell) do
        U.bySpell[k] = nil
    end
    for k in pairs(U.index) do
        U.index[k] = nil
    end
    local auras, units = def.auras, def.units
    U.nAura, U.n = #auras, #units
    for j = 1, U.nAura do
        local ids = def.auraIds[j]
        U.id[j], U.obj[j] = ids[1], auras[j]
        for k = 1, #ids do
            U.bySpell[ids[k]] = j
        end
    end
    for u = 1, U.n do
        U.token[u], U.index[units[u]] = units[u], u
        local e, ap, st, ins, hm, sq, rc = {}, {}, {}, {}, {}, {}, {}
        local ord = {}
        for j = 1, U.nAura do
            e[j], ap[j], st[j], ins[j], hm[j], sq[j] = 0, 0, 0, 0, u ~= 1, 0
            rc[j] = I.NewBelief("aura " .. units[u] .. " " .. tostring(auras[j].key or U.id[j]))
            ord[j] = 0
        end
        U.exp0[u], U.applied[u], U.stacks[u], U.inst[u], U.harm[u], U.seq[u], U.rec[u] = e, ap, st, ins, hm, sq, rc
        U.ord[u], U.ordN[u], U.gen[u] = ord, 0, 0
    end
    for s = 1, I.TARGET_CAP do
        local e, ap, st, ins = {}, {}, {}, {}
        for j = 1, U.nAura do
            e[j], ap[j], st[j], ins[j] = 0, 0, 0, 0
        end
        memExp[s], memApplied[s], memStacks[s], memInst[s] = e, ap, st, ins
    end
    I.curSlot = 0
    I.TRACKED.aura = U.id
    I.TRACKED.unit = U.token
end)

-- Re-sorts unit u's index order (applied ascending, then walk order) and bumps its AuraGen. Allocates nothing.
local function changed(u)
    local ord, e, ap, sq = U.ord[u], U.exp0[u], U.applied[u], U.seq[u]
    local n = 0
    for j = 1, U.nAura do
        if e[j] > 0 then
            n = n + 1
            local k = n
            while k > 1 do
                local p = ord[k - 1]
                if ap[p] < ap[j] or ap[p] == ap[j] and sq[p] <= sq[j] then
                    break
                end
                ord[k] = p
                k = k - 1
            end
            ord[k] = j
        end
    end
    U.ordN[u] = n
    U.gen[u] = U.gen[u] + 1
end

-- Writes one aura state on unit u (expiry 0: down). A newly up aura gets a fresh instance ID and walk order.
local function set(u, j, expires, applied, stacks, t, origin, event, harmful)
    local e = U.exp0[u]
    local was, wasStacks = e[j], U.stacks[u][j]
    if expires > 0 and was == 0 then
        I.nextInst = I.nextInst + 1
        U.inst[u][j] = I.nextInst
        U.seq[u][j] = I.nextInst
    end
    if expires <= 0 then
        U.inst[u][j] = 0
        expires, applied, stacks = 0, 0, 0
    end
    e[j], U.applied[u][j], U.stacks[u][j] = expires, applied, stacks
    if harmful ~= nil then
        U.harm[u][j] = harmful
    end
    local rec = U.rec[u][j]
    rec.est, rec.lo, rec.hi = expires, expires, expires
    I.Sample(rec, origin, expires, t, event)
    if was ~= expires or wasStacks ~= stacks then
        changed(u)
    end
end

I.On(Obs.Read, function(o, t)
    local c = o.c
    if c % I.AURA_STACK ~= ReadOf.Aura then
        return
    end
    local u = (o.a - o.a % I.AURA_UNIT) / I.AURA_UNIT + 1 -- nonzero: AURA_UNIT is a constant
    local j = o.a % I.AURA_UNIT
    local stacks = (c - ReadOf.Aura) / I.AURA_STACK -- nonzero: AURA_STACK is a constant
    if o.b == 0 then
        set(u, j, 0, 0, 0, t, "observed", Obs.Read)
    else
        local expires = o.b < 0 and HUGE or o.t + o.b
        local applied = U.exp0[u][j] > 0 and U.applied[u][j] or o.t
        set(u, j, expires, applied, stacks > 0 and stacks or 1, t, "observed", Obs.Read)
    end
end)

--- Our own cast changed aura j on unit u (spec §5.3): a `modelled` expiry with its stacks and applied time.
function I.AuraModel(u, j, applied, expires, stacks, t, event, harmful)
    set(u, j, expires, applied, stacks > 0 and stacks or 1, t, "modelled", event, harmful)
end

-- Per-target memory: the target's arrays into slot s, and back.
local function save(s)
    if s == 0 or U.n < 2 then
        return
    end
    local e, ap, st, ins = U.exp0[2], U.applied[2], U.stacks[2], U.inst[2]
    for j = 1, U.nAura do
        memExp[s][j], memApplied[s][j], memStacks[s][j], memInst[s][j] = e[j], ap[j], st[j], ins[j]
    end
end

local function load(s)
    if U.n < 2 then
        return
    end
    local e, ap, st, ins = U.exp0[2], U.applied[2], U.stacks[2], U.inst[2]
    for j = 1, U.nAura do
        if s == 0 then
            e[j], ap[j], st[j], ins[j] = 0, 0, 0, 0
        else
            e[j], ap[j], st[j], ins[j] = memExp[s][j], memApplied[s][j], memStacks[s][j], memInst[s][j]
        end
        local rec = U.rec[2][j]
        rec.est, rec.lo, rec.hi = e[j], e[j], e[j]
    end
    changed(2)
end

-- TargetSwap: a is the new target's memory slot (0: none). TargetGone: forget slot a.
I.On(Obs.TargetSwap, function(o)
    save(I.curSlot)
    I.curSlot = o.a
    load(o.a)
end)

I.On(Obs.TargetGone, function(o)
    local s = o.a
    if s > 0 then
        for j = 1, U.nAura do
            memExp[s][j] = 0
        end
        if s == I.curSlot then
            load(0)
        end
    end
end)

-- Expiry by time: an aura whose expiry passed is down (an AuraGen bump lets Hekili rescan).
I.OnSettle(function(now)
    for u = 1, U.n do
        local e = U.exp0[u]
        for j = 1, U.nAura do
            if e[j] > 0 and e[j] <= now then
                set(u, j, 0, 0, 0, now, "modelled", 0)
            end
        end
    end
end)

local function proj(u, j, now)
    local rec = U.rec[u][j]
    local e = U.exp0[u][j]
    rec.est, rec.lo, rec.hi = e, e, e
    I.AgeConf(rec, now)
    return rec
end

--- (spec §3.2) Belief expiry, then stacks, applied, instanceID; nil when not believed up.
function VS.Aura(unit, spellID, now)
    local u, j = U.index[unit], U.bySpell[spellID]
    if not u or not j or U.exp0[u][j] <= now then
        return nil
    end
    return proj(u, j, now), U.stacks[u][j], U.applied[u][j], U.inst[u][j]
end

--- (spec §3.2) The i-th believed aura on `unit` matching "HELPFUL"/"HARMFUL" (applied time ascending, then walk
--- order; only auras with est > now): spellID, Belief expiry, stacks, applied, instanceID; nil past the last.
function VS.AuraAt(unit, filter, i, now)
    local u = U.index[unit]
    if not u then
        return nil
    end
    local harmful = filter == "HARMFUL"
    local ord, e, hm = U.ord[u], U.exp0[u], U.harm[u]
    local k = 0
    for n = 1, U.ordN[u] do
        local j = ord[n]
        if e[j] > now and hm[j] == harmful then
            k = k + 1
            if k == i then
                return U.id[j], proj(u, j, now), U.stacks[u][j], U.applied[u][j], U.inst[u][j]
            end
        end
    end
    return nil
end

--- (spec §3.2) spellID, Belief expiry, stacks, applied for a believed aura by its instance ID; nil when gone.
function VS.AuraByInstance(unit, instanceID, now)
    local u = U.index[unit]
    if not u or not instanceID or instanceID <= 0 then
        return nil
    end
    local ins, e = U.inst[u], U.exp0[u]
    for j = 1, U.nAura do
        if ins[j] == instanceID and e[j] > now then
            return U.id[j], proj(u, j, now), U.stacks[u][j], U.applied[u][j]
        end
    end
    return nil
end

--- (spec §3.1) Bumped whenever the unit's believed aura set changes.
function VS.AuraGen(unit)
    local u = U.index[unit]
    return u and U.gen[u] or 0
end

--- (spec §3.3) Tracked units (the target and remembered target slots) on which the aura is believed up.
function VS.Count.WithAura(spellID, now)
    local j = U.bySpell[spellID]
    if not j or U.n < 2 then
        return 0
    end
    local n = U.exp0[2][j] > now and 1 or 0
    for s = 1, I.TARGET_CAP do
        if s ~= I.curSlot and memExp[s][j] > now then
            n = n + 1
        end
    end
    return n
end

I.OnSnapshot(function(out, now)
    for u = 1, U.n do
        out[#out + 1] = string.format("auras %s gen=%d up=%d", U.token[u], U.gen[u], U.ordN[u])
        for j = 1, U.nAura do
            proj(u, j, now)
        end
    end
end)
```
`VirtualState/Families/TargetCast.lua`:
```lua
-- VirtualState/Families/TargetCast.lua
-- The target's cast (spec §6.8): `TargetCast` observations by castBarID (plain on the target; its spellID and times
-- are secret). A start sets the start and a default end; a stop, an interrupt or a new castBarID ends it; the
-- interruptible events set the flag. Conf as an aura.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Target.lua (Applier TargetCast :103).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs, Of = VS.Obs, I.TargetCastOf

--- A target cast's believed length while its end is secret (G6).
I.TARGET_CAST_DEFAULT = 2

local active, channel, bar, start, kick = false, false, 0, 0, -1
local rec

I.OnBuild(function(def, now)
    rec = I.NewBelief("target cast")
    active = false
end)

I.On(Obs.TargetCast, function(o, t)
    local of = o.a
    if of == Of.Start or of == Of.ChannelStart then
        active, channel, bar, start, kick = true, of == Of.ChannelStart, o.b, o.t, o.c
        local e = o.t + I.TARGET_CAST_DEFAULT
        rec.est, rec.lo, rec.hi = e, e, e
        I.Sample(rec, "default", e, t, Obs.TargetCast)
        I.Sample(rec, "observed", o.t, t, Obs.TargetCast)
    elseif of == Of.End or of == Of.Interrupted then
        if active and (o.b == 0 or o.b == bar) then
            active = false
            I.Sample(rec, "observed", o.t, t, Obs.TargetCast)
        end
    elseif of == Of.Kickable then
        kick = o.c
    end
end)

I.On(Obs.TargetSwap, function()
    active = false
end)

local function up(now)
    return active and start + I.TARGET_CAST_DEFAULT + I.CAST_GRACE > now
end

--- (spec §3.1) channel, castBarID, start, interruptible (1 yes, 0 no, -1 unknown); nil when the target is not casting.
function VS.TargetCastFacts()
    if not active then
        return nil
    end
    return channel, bar, start, kick
end

--- (spec §3.2) Belief end of the target's cast; nil when it is not casting.
function VS.TargetCast(now)
    if not up(now) then
        return nil
    end
    local e = start + I.TARGET_CAST_DEFAULT
    rec.est, rec.lo, rec.hi = e, e, e
    I.AgeConf(rec, now)
    return rec
end
```
`VirtualState/Sources/Auras.lua`:
```lua
-- VirtualState/Sources/Auras.lua
-- Aura sources (spec §4.5): one C_UnitAuras.GetAuraDataByIndex walk per tracked unit per UNIT_AURA, helpful then
-- harmful, each call pcall'd; the walk stops at the first error, secret or nil (in combat that is one call per
-- filter). Entries whose spellId is tracked become `Read` observations straight to the log (remaining time, stacks).
-- After a complete walk, a believed-up aura it did not find is logged down, but in combat only once that aura was
-- seen readable in combat (before that, a miss may be the client hiding it).
-- Credits: the pcall-then-issecretvalue handling and the "seen readable in combat" rule follow Catnip's (Durts)
-- secret-value research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Auras.lua (:42, :58-61, :74, :148).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, ReadOf = VS.Obs, I.ReadOf
local Plain, Direct, Note = S.Plain, S.Direct, S.Note

local SCAN = 40
local FILTERS = { "HELPFUL", "HARMFUL" }

-- By unit index and aura index: the walk serial that last found it, and whether it was seen plain in combat.
local found, seen = {}, {}
local serial = 0

I.OnBuild(function(def)
    local U = I.auras
    for u = 1, U.n do
        local f, s = {}, {}
        for j = 1, U.nAura do
            f[j], s[j] = 0, false
        end
        found[u], seen[u] = f, s
    end
end)

-- One unit's walk at t. Allocates nothing (the client allocates its aura tables).
local function walk(api, u, unit, t)
    local U = I.auras
    serial = serial + 1
    local complete = true
    for f = 1, #FILTERS do
        local filter = FILTERS[f]
        for i = 1, SCAN do
            local ok, raw = pcall(api.C_UnitAuras.GetAuraDataByIndex, unit, i, filter) -- secret: tested next
            if not ok then
                Note("aura walk", "error")
                complete = false
                break
            elseif api.issecretvalue(raw) then
                Note("aura walk", "secret")
                complete = false
                break
            end
            local data = Plain(api, raw)
            if not data then
                break
            end
            local id = Plain(api, data.spellId)
            local j = id and U.bySpell[id]
            if j then
                local exp, apps = Plain(api, data.expirationTime), Plain(api, data.applications)
                if type(exp) ~= "number" then
                    complete = false
                    Note("aura walk", "secret")
                    break
                end
                Note("aura walk", "readable")
                found[u][j] = serial
                if I.inCombat then
                    seen[u][j] = true
                end
                local stacks = type(apps) == "number" and apps or 0
                local remaining = exp > 0 and exp - t or -1
                if remaining > 0 or exp == 0 then
                    Direct(Obs.Read, t, (u - 1) * I.AURA_UNIT + j, remaining, ReadOf.Aura + stacks * I.AURA_STACK)
                    U.harm[u][j] = filter == "HARMFUL"
                end
            end
        end
        if not complete then
            break
        end
    end
    if complete then
        local e = U.exp0[u]
        for j = 1, U.nAura do
            if e[j] > 0 and found[u][j] ~= serial and (not I.inCombat or seen[u][j]) then
                Direct(Obs.Read, t, (u - 1) * I.AURA_UNIT + j, 0, ReadOf.Aura)
            end
        end
    end
end
I.WalkAuras = walk

S.On("UNIT_AURA", nil, function(api, t, unit)
    local u = unit and I.built and I.auras.index[unit]
    if u then
        if u ~= 1 and Plain(api, api.UnitExists(unit)) ~= true then
            return
        end
        walk(api, u, unit, t)
    end
end)

S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    if not I.built then
        return
    end
    local U = I.auras
    for u = 1, U.n do
        for j = 1, U.nAura do
            seen[u][j] = false
        end
    end
end)
```
`VirtualState/Sources/Target.lua`:
```lua
-- VirtualState/Sources/Target.lua
-- Target sources (spec §4.2): PLAYER_TARGET_CHANGED keeps a GUID -> memory slot map (TARGET_CAP slots, the least
-- recently used reused) and logs `TargetSwap` (a: the slot, 0 no target) straight to the log, then walks the new
-- target's auras; poll 4 logs `TargetGone` for a dead target; the target's UNIT_SPELLCAST_* events become
-- `TargetCast` observations by castBarID (plain; the spellID and castGUID are secret on the target).
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Target.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, Of = VS.Obs, I.TargetCastOf
local Plain, Stage, Direct = S.Plain, S.Stage, S.Direct

-- By memory slot: the GUID it holds ("" free) and when it was last the target.
local guid, used = {}, {}
for s = 1, I.TARGET_CAP do
    guid[s], used[s] = "", 0
end
local dead = false

local function slotFor(g, t)
    local free, oldest = 0, 1
    for s = 1, I.TARGET_CAP do
        if guid[s] == g then
            used[s] = t
            return s
        elseif guid[s] == "" and free == 0 then
            free = s
        elseif used[s] < used[oldest] then
            oldest = s
        end
    end
    local s = free > 0 and free or oldest
    if guid[s] ~= "" then
        Direct(Obs.TargetGone, t, s)
    end
    guid[s], used[s] = g, t
    return s
end

-- A target swap: the new target's memory slot, then a walk of its auras. Also at Start and at each rebuild, so a
-- target already held at a /reload gets its slot (poll 4 then sees its death, a swap away keeps what was believed).
-- No "built" guard: in game Start (PLAYER_LOGIN) comes before the first build (PLAYER_ENTERING_WORLD), and I.Build
-- runs its hooks before it marks the set built; the slot map lives here, and a swap logged before a build is cleared
-- by that build, which logs its own.
local function swap(api, t)
    local g = Plain(api, api.UnitGUID("target"))
    local s = type(g) == "string" and slotFor(g, t) or 0
    dead = false
    Direct(Obs.TargetSwap, t, s)
    if s > 0 and I.auras.n >= 2 then
        I.WalkAuras(api, 2, "target", t)
    end
end

S.On("PLAYER_TARGET_CHANGED", nil, function(api, t)
    swap(api, t)
    S.Urgent("PLAYER_TARGET_CHANGED")
end)
S.OnStart(swap)
I.OnBuild(function(def, now)
    if I.api then
        swap(I.api, now)
    end
end)

-- Poll 4: the target's death (plain UnitIsDead) forgets what we believed about it.
S.Poll(4, function(api, t)
    if I.curSlot == 0 then
        return
    end
    local d = Plain(api, api.UnitIsDead("target")) == true
    if d and not dead then
        Direct(Obs.TargetGone, t, I.curSlot)
    end
    dead = d
end)

-- `fifth`: the event carries interruptedBy before its castBarID (INTERRUPTED, CHANNEL_STOP).
local function cast(of, fifth)
    return function(api, t, unit, castGUID, spellID, a4, a5)
        if unit == "target" then
            local castBarID = fifth and a5 or a4
            local bar = type(castBarID) == "number" and castBarID or 0
            Stage(Obs.TargetCast, t, of, bar, (of == Of.Start or of == Of.ChannelStart) and -1 or 0)
        end
    end
end
S.On("UNIT_SPELLCAST_START", "target", cast(Of.Start))
S.On("UNIT_SPELLCAST_CHANNEL_START", "target", cast(Of.ChannelStart))
S.On("UNIT_SPELLCAST_STOP", "target", cast(Of.End))
S.On("UNIT_SPELLCAST_CHANNEL_STOP", "target", cast(Of.End, true))
S.On("UNIT_SPELLCAST_INTERRUPTED", "target", cast(Of.Interrupted, true))

S.On("UNIT_SPELLCAST_INTERRUPTIBLE", "target", function(api, t, unit)
    if unit == "target" then
        Stage(Obs.TargetCast, t, Of.Kickable, 0, 1)
    end
end)

S.On("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target", function(api, t, unit)
    if unit == "target" then
        Stage(Obs.TargetCast, t, Of.Kickable, 0, 0)
    end
end)
```
In `Hekili.toc`: after `VirtualState\Families\Swing.lua` add `VirtualState\Families\Auras.lua` and `VirtualState\Families\TargetCast.lua`; after `VirtualState\Sources\Swing.lua` add `VirtualState\Sources\Auras.lua` and `VirtualState\Sources\Target.lua`.

- [ ] **Step 4: Run the specs to see them pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `62 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [62 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 35 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [no problems found]
git status --short | grep '\.lua$' | awk '{print $2}' | xargs -r -n1 luac5.1 -p   # [no output]
```
- [ ] **Step 6: Commit**
```bash
git add Hekili.toc VirtualState
git commit -m "feat(virtualstate): auras (walk, instance IDs, order, AuraGen, target memory) and the target's cast

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Talents, totems, enemies; ns.updateTalents reads VirtualState.Talent

**Files:**
- Create: `VirtualState/Families/Talents.lua`, `VirtualState/Families/Totems.lua`, `VirtualState/Families/Enemies.lua`, `VirtualState/Sources/Talents.lua`, `VirtualState/Sources/Nameplates.lua`, `VirtualState/Sources/Totems.lua`, `VirtualState/spec/facts_spec.lua`
- Modify: `Hekili.toc`, `Events.lua:424-447` (`ns.updateTalents`)

**Interfaces:**
- Consumes: Tasks 1, 3, 4 (`I.ab`, `I.AgeConf`, `I.lastCastT`, the ladder through the usability poll).
- Produces: `I.talents` (`n`, `key[k]`, `spell[k]`, `max[k]`, `rank[k]`, `bySpell[spellID] -> k`), `I.SetTalentRank(k, rank) -> changed`, `I.talents.alias[spell]` (the pack's alias spells), the read status `"talent walk aliases"` (`used` / `unused`, for CHECKPOINT 2), `I.talentGen`, `I.totemSpell/totemName/totemIcon/totemStart[slot]`, `I.inRange[a]`; `VS.Talent(talentSpellID)`, `VS.TalentGen()`, `VS.Totem(slot, now)`, `VS.TotemFacts(slot)`, `VS.Count.Enemies(now)`, `VS.Count.InRange(spellID, now)`.

- [ ] **Step 1: Write the failing spec**

`VirtualState/spec/facts_spec.lua`:

```lua
-- VirtualState/spec/facts_spec.lua: the polls and the smaller families (spec §4.3, §6.5-§6.9): the usability ladder
-- poll, known ranks, talents, totems, the target's cast, enemies, health, stats.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("facts and polls", function()
    local VS, I, S, Obs, ctl

    before_each(function()
        local api
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    local function drain(t)
        ctl.Tick(t)
        S.RunPolls(t)
        I.Fold(t, false)
        I.Settle(t)
    end

    it("asks the highest known rank, and skips a secret usability answer", function()
        ctl.known[fs.REND], ctl.known[fs.REND_R2] = true, true
        ctl.Fire("SPELLS_CHANGED")
        assert.are.equal(fs.REND_R2, I.ab.qid[3])
        ctl.usable[fs.REND_R2] = { true, false }
        ctl.usable[fs.STRIKE] = { fake.SECRET, false }
        drain(5)
        local r = VS.Power(fs.RAGE, 5)
        assert.are.equal(10, r.lo) -- rend's rung; heroic strike's secret answer is no news
    end)

    it("walks the talent tree into ranks by registered spell ID, and defers a walk in combat", function()
        ctl.traits = { config = 1, trees = { 7 }, nodeIDs = { 70 }, nodes = {}, defs = { [700] = 12286 } }
        ctl.traits.nodes[70] = { entryIDs = { 700 }, activeRank = 2 }
        ctl.Fire("TRAIT_CONFIG_UPDATED")
        assert.are.equal(2, VS.Talent(12286))
        local gen = VS.TalentGen()
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.traits.nodes[70].activeRank = 3
        ctl.Fire("TRAIT_CONFIG_UPDATED")
        assert.are.equal(2, VS.Talent(12286))
        ctl.Fire("PLAYER_REGEN_ENABLED")
        drain(6)
        assert.are.same({ 3, gen + 1 }, { VS.Talent(12286), VS.TalentGen() })
        assert.are.equal(0, VS.Talent(99999))
        assert.are.equal("unused", S.status["talent walk aliases"])
    end)

    it("reads totems out of combat and takes an update in combat with no cast as a destruction", function()
        ctl.totems[1] = { name = "Totem", start = 2, duration = 30, icon = 55, spell = 1234 }
        drain(5)
        assert.are.same({ 1234, "Totem", 55, 2, 30 }, { VS.TotemFacts(1) })
        assert.are.equal(32, VS.Totem(1, 5).est)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.now = 8
        ctl.Fire("PLAYER_TOTEM_UPDATE", 1)
        drain(8)
        assert.is_nil(VS.Totem(1, 8))
        assert.is_nil(VS.TotemFacts(1))
    end)

    it("times the target's cast by castBarID", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_START", "target", fake.SECRET, fake.SECRET, 77)
        drain(10)
        assert.are.same({ false, 77, 10, -1 }, { VS.TargetCastFacts() })
        assert.are.equal(10 + I.TARGET_CAST_DEFAULT, VS.TargetCast(10.5).est)
        ctl.Fire("UNIT_SPELLCAST_INTERRUPTIBLE", "target")
        drain(10.6)
        assert.are.equal(1, select(4, VS.TargetCastFacts()))
        ctl.Fire("UNIT_SPELLCAST_INTERRUPTED", "target", fake.SECRET, fake.SECRET, "Player-1", 77)
        drain(11)
        assert.is_nil(VS.TargetCastFacts())
        assert.is_nil(VS.TargetCast(11))
    end)

    it("counts live attackable plates, default 1 without any", function()
        drain(2)
        assert.are.equal(1, VS.Count.Enemies(2).est)
        ctl.exists.nameplate1, ctl.exists.nameplate2, ctl.exists.nameplate3 = true, true, true
        ctl.dead.nameplate3 = true
        ctl.inRange.nameplate1 = true
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
        drain(3)
        local e = VS.Count.Enemies(3)
        assert.are.same({ 2, "observed" }, { e.est, e.basis })
        assert.are.equal(1, VS.Count.InRange(fs.REND, 3))
    end)

    it("reads the player's health when plain and caches the stats out of combat", function()
        ctl.health, ctl.healthMax = 500, 1000
        drain(2)
        assert.are.equal(0.5, VS.Health("player", 2).est)
        assert.are.equal(1000, VS.HealthMax("player"))
        assert.are.same({ 1, 100 }, { VS.Health("target", 2).est, VS.HealthMax("target") })
        assert.are.equal(30, VS.TTD("target", 2).est)
        assert.are.same({ 0, 0, 0, 0, 0, 0, 0 }, { VS.Stat("UnitStat", 1) })
        assert.are.same({ 0, 0, 0, 0, 0, 0, 0 }, { VS.Stat("NoSuchStat") })
    end)
end)
```
- [ ] **Step 2: Run it to see it fail**

Run: `~/src/TacoDogForever/.lua/bin/busted VirtualState/spec/facts_spec.lua`
Expected: errors such as `attempt to call field 'Talent' (a nil value)` and `attempt to call field 'TotemFacts' (a nil value)`.

- [ ] **Step 3: Write the families and the sources**

`VirtualState/Families/Talents.lua`:

```lua
-- VirtualState/Families/Talents.lua
-- The talents family (spec §6.6): ranks by the talent's registered spell ID (Hekili's `class.talents[key][2]`), from
-- one C_Traits walk per talent event (Sources/Talents.lua). Ranks are plain facts: the walk writes them at once (so
-- Hekili's ns.updateTalents reads fresh ranks) and logs a `Talent` observation per changed rank.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Talents.lua (Applier Talent :39).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal

local T = { n = 0, key = {}, spell = {}, max = {}, rank = {}, bySpell = {}, alias = {} }
I.talents = T
I.talentGen = 0

I.OnBuild(function(def)
    for k in pairs(T.bySpell) do
        T.bySpell[k] = nil
    end
    for k in pairs(T.alias) do
        T.alias[k] = nil
    end
    local list = def.talents
    T.n = #list
    for k = 1, T.n do
        local d = list[k]
        T.key[k], T.spell[k], T.max[k], T.rank[k] = d.key, d.spell, d.max or 1, 0
        T.bySpell[d.spell] = k
    end
    -- the pack's aliases (VirtualState.Track{ talents = { [rankSpell] = registeredSpell } })
    for alias, spell in pairs(I.extra.talents) do
        local k = T.bySpell[spell]
        if k then
            T.bySpell[alias], T.alias[alias] = k, true
        end
    end
end)

--- Sets talent k's rank (the walk, Sources/Talents.lua); bumps TalentGen when it changed. True when it changed.
function I.SetTalentRank(k, rank)
    if T.rank[k] ~= rank then
        T.rank[k] = rank
        I.talentGen = I.talentGen + 1
        return true
    end
    return false
end

--- (spec §3.1) The rank of the talent registered with spell ID `talentID` (0 when not taken or not tracked).
function VS.Talent(talentID)
    local k = T.bySpell[talentID]
    return k and T.rank[k] or 0
end

--- (spec §3.1) Bumped when any rank changes.
function VS.TalentGen()
    return I.talentGen
end

I.OnSnapshot(function(out)
    for k = 1, T.n do
        out[#out + 1] = string.format("talent %s spell=%d rank=%d/%d", tostring(T.key[k]), T.spell[k], T.rank[k], T.max[k])
    end
end)
```
`VirtualState/Families/Totems.lua`:
```lua
-- VirtualState/Families/Totems.lua
-- The totems family (spec §6.7): the four slots. An out-of-combat read is `observed` (with the slot's facts); a
-- PLAYER_TOTEM_UPDATE in combat with no own cast just before it is a `pinned` destruction. Conf as an aura.
-- Ported from Taco Dog Forever, the totem half of src/TacoDogForever/Model/Belief/Pets.lua (Applier Totem :57).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs

-- By slot 1-4: the believed expiry (0: empty) and the facts of the last plain read.
local exp0, rec = { 0, 0, 0, 0 }, {}
I.totemSpell, I.totemName, I.totemIcon, I.totemStart = { 0, 0, 0, 0 }, { "", "", "", "" }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }

I.OnBuild(function(def, now)
    for s = 1, 4 do
        rec[s] = I.NewBelief("totem " .. s)
        I.Sample(rec[s], "default", 0, now, 0)
    end
end)

I.On(Obs.Totem, function(o, t)
    local s = o.a
    if s < 1 or s > 4 then
        return
    end
    if o.c == 1 then
        exp0[s] = o.b
        I.Sample(rec[s], "observed", o.b, t, Obs.Totem)
    elseif o.t - I.lastCastT > I.CAST_GRACE then
        exp0[s] = 0
        I.totemSpell[s] = 0
        I.Sample(rec[s], "pinned", 0, t, Obs.Totem)
    end
end)

--- (spec §3.2) Belief expiry of totem slot 1-4; nil when empty.
function VS.Totem(slot, now)
    local r = rec[slot]
    if not r or exp0[slot] <= now then
        return nil
    end
    r.est, r.lo, r.hi = exp0[slot], exp0[slot], exp0[slot]
    I.AgeConf(r, now)
    return r
end

--- (spec §3.1) spellID, name, icon, start, duration of totem slot 1-4; nil when the slot is empty.
function VS.TotemFacts(slot)
    local e = exp0[slot]
    if not e or e <= 0 then
        return nil
    end
    return I.totemSpell[slot], I.totemName[slot], I.totemIcon[slot], I.totemStart[slot], e - I.totemStart[slot]
end
```
`VirtualState/Families/Enemies.lua`:
```lua
-- VirtualState/Families/Enemies.lua
-- Enemies (spec §6.9): the nameplate walk's count of live, attackable plates (`observed`, default 1 without plates)
-- and the range poll's counts. In Phase 1 no Hekili code reads VirtualState.Count: Hekili's enemy scan still counts
-- plates through the UnitHealth policy (spec §7.4).
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Targets.lua (Applier Enemies :184).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs

local rec
-- By ability index: plates in range of that ability's spell at the last range poll.
I.inRange = {}

I.OnBuild(function(def, now)
    rec = I.NewBelief("enemies")
    rec.est, rec.lo, rec.hi = 1, 1, 1
    I.Sample(rec, "default", 1, now, 0)
    for a = 1, #def.abilities do
        I.inRange[a] = 0
    end
end)

I.On(Obs.Enemies, function(o, t)
    local n = o.b > 0 and o.b or 1
    if rec.est ~= n or rec.last.observed.t == 0 then
        I.Sample(rec, o.b > 0 and "observed" or "default", n, t, Obs.Enemies)
    end
    rec.est, rec.lo, rec.hi = n, n, n
end)

I.On(Obs.Range, function(o)
    I.inRange[o.a] = o.b
end)

--- (spec §3.3) Belief count of enemies: the nameplate walk, default 1.
function VS.Count.Enemies(now)
    I.AgeConf(rec, now)
    return rec
end

--- (spec §3.3) Tracked enemies in range of the spell (the range poll covers the tracked attacks); 0 for any other.
function VS.Count.InRange(spellID, now)
    local a = I.ab.bySpell[spellID]
    return a and I.inRange[a] or 0
end
```
`VirtualState/Sources/Talents.lua`:
```lua
-- VirtualState/Sources/Talents.lua
-- Talent sources (spec §6.6): one C_Traits tree walk (plain and identical in combat [W PR5]; every call pcall'd and
-- every answer through Plain) at build, on TRAIT_CONFIG_UPDATED, PLAYER_TALENT_UPDATE and SPELLS_CHANGED; an event in
-- combat defers the walk to poll 6 once combat ends. Each node's rank goes to the tracked talent its entry's
-- definition spell names (directly, or through a pack alias); ranks are written at once (Families/Talents.lua) and
-- each changed rank is logged as `Talent`.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Talents.lua (the walk: eachNode, walkNode, entryTalent).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Direct, Note = S.Plain, S.Direct, S.Note

-- The walk's scratch ranks by talent index.
local walkRank = {}
-- How many entries the last walk matched through a pack alias (a rank spell) rather than the registered spell.
local aliasHits = 0
local pending = false

-- The client calls, where they are read (the secrets check sees them); `call` pcalls them and Plains the answer.
local function activeConfig(api)
    return api.C_ClassTalents.GetActiveConfigID() -- secret: through Plain by `call`
end
local function configInfo(api, cfg)
    return api.C_Traits.GetConfigInfo(cfg) -- secret: through Plain by `call`
end
local function treeNodes(api, tree)
    return api.C_Traits.GetTreeNodes(tree) -- secret: through Plain by `call`
end
local function nodeInfo(api, cfg, node)
    return api.C_Traits.GetNodeInfo(cfg, node) -- secret: through Plain by `call`
end
local function entryInfo(api, cfg, entry)
    return api.C_Traits.GetEntryInfo(cfg, entry) -- secret: through Plain by `call`
end
local function definitionInfo(api, def)
    return api.C_Traits.GetDefinitionInfo(def) -- secret: through Plain by `call`
end

local function call(api, fn, a, b)
    local ok, v = pcall(fn, api, a, b)
    if not ok then
        return nil
    end
    return Plain(api, v)
end

-- One node: its rank (activeRank, else currentRank) to the tracked talent of its active (or only) entry.
local function walkNode(api, cfg, nodeID)
    local T = I.talents
    local info = call(api, nodeInfo, cfg, nodeID)
    if type(info) ~= "table" then
        return
    end
    local entries = Plain(api, info.entryIDs)
    if type(entries) ~= "table" or #entries == 0 then
        return
    end
    local rank = Plain(api, info.activeRank)
    if type(rank) ~= "number" then
        rank = Plain(api, info.currentRank)
    end
    if type(rank) ~= "number" or rank ~= rank or rank < 0 then
        rank = 0
    end
    local active = Plain(api, info.activeEntry)
    local activeId = type(active) == "table" and Plain(api, active.entryID) or nil
    for n = 1, #entries do
        local entry = Plain(api, entries[n])
        if type(entry) == "number" then
            local e = call(api, entryInfo, cfg, entry)
            local def = type(e) == "table" and Plain(api, e.definitionID) or nil
            local d = type(def) == "number" and call(api, definitionInfo, def) or nil
            local spell = type(d) == "table" and Plain(api, d.spellID) or nil
            local k = type(spell) == "number" and T.bySpell[spell]
            if k and T.alias[spell] then
                aliasHits = aliasHits + 1
            end
            if k then
                local r = (#entries == 1 or entry == activeId) and rank or 0
                if r > T.max[k] then
                    r = T.max[k]
                end
                if r > walkRank[k] then
                    walkRank[k] = r
                end
            end
        end
    end
end

-- The walk: the active config's trees, node by node; then each changed rank written and logged. Out of combat only.
local function walk(api, t)
    local T = I.talents
    if T.n == 0 then
        return
    end
    for k = 1, T.n do
        walkRank[k] = 0
    end
    aliasHits = 0
    local cfg = call(api, activeConfig)
    local info = type(cfg) == "number" and call(api, configInfo, cfg) or nil
    local trees = type(info) == "table" and Plain(api, info.treeIDs) or nil
    if type(trees) ~= "table" then
        Note("talent walk", "nil")
        return
    end
    Note("talent walk", "readable")
    for n = 1, #trees do
        local tree = Plain(api, trees[n])
        local nodes = type(tree) == "number" and call(api, treeNodes, tree) or nil
        if type(nodes) == "table" then
            for m = 1, #nodes do
                local id = Plain(api, nodes[m])
                if type(id) == "number" then
                    walkNode(api, cfg, id)
                end
            end
        end
    end
    -- whether the pack's aliases (VirtualState.Track{ talents }) were needed: "used" or "unused" (CHECKPOINT 2)
    Note("talent walk aliases", aliasHits > 0 and "used" or "unused")
    for k = 1, T.n do
        if I.SetTalentRank(k, walkRank[k]) then
            Direct(Obs.Talent, t, k, walkRank[k])
        end
    end
end

local function request(api, t)
    if not I.built then
        return
    end
    if I.inCombat then
        pending = true
    else
        walk(api, t)
    end
end

I.OnBuild(function(def, now)
    for k = 1, #def.talents do
        walkRank[k] = 0
    end
    if I.api then
        walk(I.api, now)
    end
end)

S.OnStart(request)
S.On("TRAIT_CONFIG_UPDATED", nil, request)
S.On("PLAYER_TALENT_UPDATE", nil, request)
S.On("SPELLS_CHANGED", nil, request)

-- Poll 6: a walk deferred by combat runs once combat ends.
S.Poll(6, function(api, t)
    if pending and not I.inCombat then
        pending = false
        walk(api, t)
    end
end)
```
`VirtualState/Sources/Nameplates.lua`:
```lua
-- VirtualState/Sources/Nameplates.lua
-- Nameplate sources (spec §4.5, §6.9): the plate tokens from NAME_PLATE_UNIT_ADDED/REMOVED; poll 5 counts the live,
-- attackable plates (plain UnitExists, UnitIsDead, UnitCanAttack) into `Enemies`; poll 8 counts, per tracked attack
-- (an ability that starts combat), the plates in range of its spell (plain C_Spell.IsSpellInRange) into `Range`.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Nameplates.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Direct = S.Plain, S.Direct

local PLATES = 40
local token, index, active = {}, {}, {}
for k = 1, PLATES do
    token[k] = "nameplate" .. k
    index[token[k]] = k
    active[k] = false
end

S.On("NAME_PLATE_UNIT_ADDED", nil, function(api, t, unit)
    local k = unit and index[unit]
    if k then
        active[k] = true
    end
end)

S.On("NAME_PLATE_UNIT_REMOVED", nil, function(api, t, unit)
    local k = unit and index[unit]
    if k then
        active[k] = false
    end
end)

local function live(api, unit)
    return Plain(api, api.UnitExists(unit)) == true
        and Plain(api, api.UnitIsDead(unit)) == false
        and Plain(api, api.UnitCanAttack("player", unit)) == true
end

-- Poll 5: the enemy count.
S.Poll(5, function(api, t)
    local n = 0
    for k = 1, PLATES do
        if active[k] and live(api, token[k]) then
            n = n + 1
        end
    end
    Direct(Obs.Enemies, t, 0, n)
end)

-- Poll 8: per tracked attack, the plates in range of its spell.
S.Poll(8, function(api, t)
    local A = I.ab
    for a = 1, A.n do
        if A.obj[a].startsCombat then
            local n = 0
            for k = 1, PLATES do
                if active[k] and Plain(api, api.C_Spell.IsSpellInRange(A.qid[a], token[k])) == true then
                    n = n + 1
                end
            end
            if n ~= I.inRange[a] then
                Direct(Obs.Range, t, a, n)
            end
        end
    end
end)
```
`VirtualState/Sources/Totems.lua`:
```lua
-- VirtualState/Sources/Totems.lua
-- Totem sources (spec §4.2, §4.5): out of combat, the four slots of GetTotemInfo (on PLAYER_TOTEM_UPDATE and poll 7),
-- each an observed `Totem` (c = 1) with its facts; in combat (the read is secret) PLAYER_TOTEM_UPDATE logs the slot
-- with no read (c = 0), which the family takes as a destruction unless our cast just summoned it.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, the totem half of src/TacoDogForever/Sources/Pets.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Direct = S.Plain, S.Stage, S.Direct

-- The last plain read of each slot (its expiry; -1 before any), so a poll logs only changes.
local last = { -1, -1, -1, -1 }

local function read(api, slot, t, direct)
    local rawUp, rawName, rawStart, rawDur, rawIcon, _, rawSpell = api.GetTotemInfo(slot) -- secret: Plain next
    local up, name, start = Plain(api, rawUp), Plain(api, rawName), Plain(api, rawStart)
    local dur, icon, spell = Plain(api, rawDur), Plain(api, rawIcon), Plain(api, rawSpell)
    if up == nil then
        return
    end
    local e = 0
    if up and type(start) == "number" and type(dur) == "number" and dur > 0 then
        e = start + dur
        I.totemName[slot] = type(name) == "string" and name or ""
        I.totemIcon[slot] = type(icon) == "number" and icon or 0
        I.totemSpell[slot] = type(spell) == "number" and spell or 0
        I.totemStart[slot] = start
    end
    if e ~= last[slot] then
        last[slot] = e
        if direct then
            Direct(Obs.Totem, t, slot, e, 1)
        else
            Stage(Obs.Totem, t, slot, e, 1)
        end
    end
end

S.On("PLAYER_TOTEM_UPDATE", nil, function(api, t, slot)
    if type(slot) ~= "number" or slot < 1 or slot > 4 then
        return
    end
    if I.inCombat then
        last[slot] = -1
        Stage(Obs.Totem, t, slot, 0, 0)
    else
        read(api, slot, t, false)
    end
end)

-- Poll 7: the four slots, out of combat.
S.Poll(7, function(api, t)
    if not I.inCombat then
        for slot = 1, 4 do
            read(api, slot, t, true)
        end
    end
end)
```
In `Hekili.toc`: after `VirtualState\Families\TargetCast.lua` add `VirtualState\Families\Talents.lua`, `VirtualState\Families\Totems.lua`, `VirtualState\Families\Enemies.lua`; after `VirtualState\Sources\Target.lua` add `VirtualState\Sources\Talents.lua`, `VirtualState\Sources\Nameplates.lua`, `VirtualState\Sources\Totems.lua`. The VirtualState block of the TOC is now:
```
VirtualState\VirtualState.lua
VirtualState\ObsLog.lua
VirtualState\Belief.lua
VirtualState\Families\Player.lua
VirtualState\Families\Casts.lua
VirtualState\Families\Resources.lua
VirtualState\Families\Swing.lua
VirtualState\Families\Auras.lua
VirtualState\Families\TargetCast.lua
VirtualState\Families\Talents.lua
VirtualState\Families\Totems.lua
VirtualState\Families\Enemies.lua
VirtualState\Sources\Sources.lua
VirtualState\Sources\Player.lua
VirtualState\Sources\Spellbook.lua
VirtualState\Sources\Casts.lua
VirtualState\Sources\Power.lua
VirtualState\Sources\Swing.lua
VirtualState\Sources\Auras.lua
VirtualState\Sources\Target.lua
VirtualState\Sources\Talents.lua
VirtualState\Sources\Nameplates.lua
VirtualState\Sources\Totems.lua
VirtualState\Snapshot.lua
```

- [ ] **Step 4: `ns.updateTalents` reads the walk (spec §10, cleanup Q9)**

In `Events.lua`, replace the function from `function ns.updateTalents()` (line 424) down to, not including, its `    ResetDisabledGearAndSpells()` (line 448), that is:

```lua
function ns.updateTalents()
    for k, _ in pairs( state.talent ) do
        state.talent[ k ].enabled = false
    end

    -- local specGroup = GetSpecialization()

    for k, v in pairs( class.talents ) do
        local _, name, _, enabled, _, sID, _, _, _, _, known = GetTalentInfoByID( v, 1 )

        if not name then
            -- We probably used a spellID.
            enabled = IsPlayerSpell( v )
        end

        enabled = enabled or known

        if rawget( state.talent, k ) then
            state.talent[ k ].enabled = enabled
        else
            state.talent[ k ] = { enabled = enabled }
        end
    end

```
with:
```lua
function ns.updateTalents()
    for k, _ in pairs( state.talent ) do
        state.talent[ k ].enabled = false
    end

    -- Forever: GetTalentInfoByID is dead; ranks come from VirtualState's C_Traits walk (cleanup Q9), keyed by the
    -- talent's registered spell ID (RegisterTalents entries are { node, spell, max rank }).
    for k, v in pairs( class.talents ) do
        local rank = type( v ) == "table" and ns.VirtualState.Talent( v[ 2 ] ) or 0

        if rawget( state.talent, k ) then
            state.talent[ k ].enabled = rank > 0
            state.talent[ k ].rank = rank
        else
            state.talent[ k ] = { enabled = rank > 0, rank = rank }
        end
    end

```
The function keeps its `    ResetDisabledGearAndSpells()` and `end`. `GetTalentInfoByID` and `IsPlayerSpell` are no longer called here (their file-top aliases stay; Task 8 rewrites them).

- [ ] **Step 5: Run the specs to see them pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `68 successes / 0 failures / 0 errors`.

- [ ] **Step 6: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [68 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 41 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [no problems found]
git status --short | grep '\.lua$' | awk '{print $2}' | xargs -r -n1 luac5.1 -p   # [no output]
```
- [ ] **Step 7: Commit**
```bash
git add Hekili.toc Events.lua VirtualState
git commit -m "feat(virtualstate): talents (C_Traits walk), totems, enemies and range; ns.updateTalents reads VirtualState.Talent

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: The Forever Warrior class file and the priority generator, CHECKPOINT 2

**Files:**
- Create: `tools/make_pack.lua`
- Modify (whole file): `Forever/Warrior.lua` (today the load-only stub, `Forever/Warrior.lua:1-18`)
- Modify: `.luacheckrc` (after `files["VirtualState/spec/"] = { std = "+busted" }`)

**Interfaces:**
- Consumes: Hekili's `NewSpecialization`, `RegisterResource` (regen models with `swing`, `last`, `interval`, `stop`, `value`; shape `archive/TheWarWithin/WarriorArms.lua:36-56`), `RegisterTalents`, `RegisterAuras`, `RegisterAbilities`, `RegisterOptions`, `RegisterPack`; `ns.VirtualState.Track` (Task 1).
- Produces: the spec 1491 registrations VirtualState tracks: rage (power type 1, swing-paid by the main hand, `value = 4.5 x mainhand_speed / haste`, the unhasted speed), abilities `battle_shout` (6673 + ranks, 10 rage, GCD), `rend` (772 + ranks, 10 rage, GCD, `startsCombat`, applies debuff `rend` with the known rank's duration 9/12/15/18/21 s), `heroic_strike` (78 + ranks, `15 - talent.improved_heroic_strike.rank` rage, off GCD, `onNextSwing`); auras `battle_shout` (180 s), `rend`; 14 Arms talents; the default priority (precombat `battle_shout`; `battle_shout`, `rend,if=!debuff.rend.up`, `heroic_strike,if=rage>=30`).

Spell data is the Forever DB2 at build 1.60.1.70338 (`wowdb spell <name>`; a cost of 100 there is 10 rage): Battle Shout 6673/5242/6192/11549/11550/11551/25289 (cost 100, 180000 ms); Rend 772/6546/6547/6548/11572/11573/11574 (cost 100; 9000, 12000, 15000, 18000, 21000, 21000, 21000 ms); Heroic Strike 78/284/285/1608/11564/11565/11566/11567/25286 (cost 150; Improved Heroic Strike 12282 is a flat cost modifier of -10, -1 rage a rank: `wowdb effects 12282`); talents from `wowdb talents WARRIOR`. Rage per swing (rate x the weapon's unhasted speed, 4.5 for a two-hander) is TDF's, `src/TacoDogForever_Warrior/Warrior.lua:21-24`; the archived shape divides by `state.haste` the same way (`archive/TheWarWithin/WarriorArms.lua:54`). Bloodrage is not in the Phase 1 kit (its rage over time is an aura-gated regen model the resources family does not apply).

- [ ] **Step 1: Write the generator and check it reproduces**

`tools/make_pack.lua`:

```lua
-- tools/make_pack.lua: prints a Hekili priority in the share format RegisterPack takes ("Hekili:" + LibDeflate print
-- encoding of the AceSerializer'd package), built headless with the vendored libraries. Run from the repository root:
--   lua5.1 tools/make_pack.lua
-- Edit PACK below, run it, and paste the printed string into the class file's spec:RegisterPack( ... [[ ]] ).
_G.strbyte, _G.strchar, _G.strsub, _G.strfind, _G.format = string.byte, string.char, string.sub, string.find, string.format
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")
dofile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
local LibDeflate, Serializer = LibStub("LibDeflate"), LibStub("AceSerializer-3.0")

local function entry(action, criteria)
    return { action = action, enabled = true, criteria = criteria }
end

local DATE = 20261015
local PACK = {
    type = "package",
    name = "Warrior",
    date = DATE,
    payload = {
        spec = 1491,
        builtIn = false,
        hidden = false,
        date = DATE,
        version = DATE,
        author = "Hekili (Forever)",
        desc = "Forever Warrior for the VirtualState Phase 1 checkpoint: Battle Shout up, Rend kept up, Heroic Strike "
            .. "with spare rage.",
        profile = table.concat({
            "actions.precombat=battle_shout,if=!buff.battle_shout.up",
            "actions=battle_shout,if=!buff.battle_shout.up",
            "actions+=/rend,if=!debuff.rend.up",
            "actions+=/heroic_strike,if=rage>=30",
        }, "\n"),
        lists = {
            precombat = { entry("battle_shout", "!buff.battle_shout.up") },
            default = {
                entry("battle_shout", "!buff.battle_shout.up"),
                entry("rend", "!debuff.rend.up"),
                entry("heroic_strike", "rage>=30"),
            },
        },
    },
}

local compressed = LibDeflate:CompressDeflate(Serializer:Serialize(PACK), { level = 5 })
print("Hekili:" .. LibDeflate:EncodeForPrint(compressed))
```
Run: `lua5.1 tools/make_pack.lua`
Expected (one line; the output is deterministic):

```text
Hekili:TkvWUrnmq0VfUbIQWMwajQu4qpuv4WQkmcUn1tCM0yf3yl7jG6f)TZy3DxTlqpGekso2JFZBEVzm0cFfuditW2Z3C(7B30(oqXpgiqfqZmEVSzbFqw)ogJwFSe)rNhhkj2VAD8NwG()KJuGmW223(HwqnzhgONqrjdOU2hPFqXSEhNz9yzHNOS(B2iVIofl8L13oHj5xBwBMiZCWBx4lZ6RqMDsC1KFLZ61Wzz9xOLHSEMc7dCdf9wJaIJ2zb8pT8uwNcyuoefN1iEj6hToXDOHT(Lutisg)d9i31xRXDPsjoZo29I(1XXMJJ2SgYFExI)JWFD3BIIERahOk0Y5FdYu1b3LQgOGTO6p2DXgqjTVKG64oUZM4uDCsJ4QJLTBRJxAb7D0aC1EBkdUJ0fOmrltrlcQ)QQbwkZZqur1NqWPUPK6fptQN4UJ54Glz5tDyI8)0pvMXvEQ8G(gA26Sz9l39U8v1RHF9
```
- [ ] **Step 2: Replace `Forever/Warrior.lua`**

The `VGA` locals are temporary, as in Task 2: Task 8's rewrite turns them into direct reads. The `[[ ]]` payload is exactly the line Step 1 printed; if the printed line differs, paste the printed line.

```lua
-- Forever/Warrior.lua
-- The Forever Warrior (pseudo-spec 1491) for the VirtualState Phase 1 checkpoint (spec §10, §11): rage with its
-- main-hand swing model, Battle Shout, Rend and Heroic Strike with their costs, cooldowns, handlers and aura
-- durations, the Arms talents, and a default priority that recommends the spenders. Bloodrage is left out of Phase 1:
-- its rage over time is an aura-gated regen model VirtualState's resources family does not apply.
-- Spell data: the Forever DB2 at build 1.60.1.70338 (wowdb); a cost of 100 there is 10 rage.
-- Credits: Hekili (registration API and pack format); call shapes from archive/TheWarWithin/WarriorArms.lua:36-56.
-- Rage per swing from Taco Dog Forever's Warrior pack (src/TacoDogForever_Warrior/Warrior.lua:21-24).

local addon, ns = ...
local VGA = LibStub( "VirtualGameAPI-1.0" )
local C_SpellBook, UnitClassBase = VGA.C_SpellBook, VGA.UnitClassBase
local Hekili = _G[ addon ]

if UnitClassBase( "player" ) ~= "WARRIOR" then return end

local state = Hekili.State
local IsSpellKnown = C_SpellBook.IsSpellKnown
local floor = math.floor

local spec = Hekili:NewSpecialization( 1491, false, 135328 ) -- inv_sword_27; numeric because Options formats it with %d
if not spec then return end

-- Rank IDs, lowest first (the DB2's).
local BATTLE_SHOUT = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }
local REND = { 772, 6546, 6547, 6548, 11572, 11573, 11574 }
local REND_DURATION = { 9, 12, 15, 18, 21, 21, 21 }
local HEROIC_STRIKE = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }

local function rest( ids )
    local out = {}
    for i = 2, #ids do out[ #out + 1 ] = ids[ i ] end
    return out
end

-- The highest rank of `ids` the player knows (0: none). C_SpellBook, not the deprecation shims (cleanup Q12).
local function knownRank( ids )
    for i = #ids, 1, -1 do
        if IsSpellKnown( ids[ i ] ) then return i end
    end
    return 0
end

-- Rage a second of the main hand's unhasted weapon speed: a white swing brings rate x that speed (haste adds swings,
-- never rage per swing). shortcut: one rate (two-handed 4.5; one-handed is 3.46), upgrade with a weapon-size read when
-- a one-hander matters; VirtualState's calibration absorbs the difference meanwhile.
local RAGE_RATE = 4.5

spec:RegisterResource( Enum.PowerType.Rage, {
    mainhand = {
        swing = "mainhand",

        last = function ()
            local swing = state.swings.mainhand
            local t = state.query_time
            if state.mainhand_speed == 0 then return 0 end
            return swing + floor( ( t - swing ) / state.mainhand_speed ) * state.mainhand_speed
        end,

        interval = "mainhand_speed",

        stop = function () return state.swings.mainhand == 0 end,
        value = function () return RAGE_RATE * state.mainhand_speed / state.haste end,
    },
} )

-- Talents: { node (unused on Forever), the rank 1 spell, max rank }; VirtualState maps the trait walk's spells to them.
spec:RegisterTalents( {
    improved_heroic_strike           = { 0, 12282, 3 },
    deflection                       = { 0, 16462, 5 },
    improved_rend                    = { 0, 12286, 3 },
    improved_charge                  = { 0, 12285, 2 },
    improved_tactical_mastery        = { 0, 12295, 5 },
    improved_thunder_clap            = { 0, 12287, 3 },
    improved_overpower               = { 0, 12290, 2 },
    anger_management                 = { 0, 12296, 1 },
    deep_wounds                      = { 0, 12834, 3 },
    two_handed_weapon_specialization = { 0, 12163, 5 },
    impale                           = { 0, 16493, 2 },
    sweeping_strikes                 = { 0, 12292, 1 },
    improved_hamstring               = { 0, 12289, 3 },
    mortal_strike                    = { 0, 12294, 1 },
} )

-- The higher rank spells of each talent, in case the trait walk names a rank rather than rank 1 (spec §3.6 Track).
ns.VirtualState.Track( { talents = {
    [ 12663 ] = 12282, [ 12664 ] = 12282,
    [ 16463 ] = 16462, [ 16464 ] = 16462, [ 16465 ] = 16462, [ 16466 ] = 16462,
    [ 12658 ] = 12286, [ 12659 ] = 12286,
    [ 12697 ] = 12285,
    [ 12676 ] = 12295, [ 12677 ] = 12295, [ 12678 ] = 12295, [ 12679 ] = 12295,
    [ 12665 ] = 12287, [ 12666 ] = 12287,
    [ 12963 ] = 12290,
    [ 12849 ] = 12834, [ 12867 ] = 12834,
    [ 12711 ] = 12163, [ 12712 ] = 12163, [ 12713 ] = 12163, [ 12714 ] = 12163,
    [ 16494 ] = 16493,
    [ 12668 ] = 12289, [ 23695 ] = 12289,
} } )

spec:RegisterAuras( {
    battle_shout = {
        id = 6673,
        copy = rest( BATTLE_SHOUT ),
        duration = 180,
        max_stack = 1,
    },
    rend = {
        id = 772,
        copy = rest( REND ),
        duration = function () return REND_DURATION[ knownRank( REND ) ] or 9 end,
        tick_time = 3,
        max_stack = 1,
    },
} )

spec:RegisterAbilities( {
    battle_shout = {
        id = 6673,
        copy = rest( BATTLE_SHOUT ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = false,
        known = function () return knownRank( BATTLE_SHOUT ) > 0 end,

        handler = function ()
            applyBuff( "battle_shout" )
        end,
    },

    rend = {
        id = 772,
        copy = rest( REND ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = function () return knownRank( REND ) > 0 end,

        handler = function ()
            applyDebuff( "target", "rend" )
        end,
    },

    heroic_strike = {
        id = 78,
        copy = rest( HEROIC_STRIKE ),
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = function () return 15 - talent.improved_heroic_strike.rank end, -- Improved Heroic Strike: -1 a rank
        spendType = "rage",

        startsCombat = true,
        onNextSwing = true, -- VirtualState: paid at the main hand's next swing, which then brings no rage
        known = function () return knownRank( HEROIC_STRIKE ) > 0 end,
    },
} )

spec:RegisterOptions( { package = "Warrior" } )

-- Payload: spec 1491; precombat battle_shout; default battle_shout, rend (!debuff.rend.up), heroic_strike (rage>=30). Generated by tools/make_pack.lua (the share format RestoreDefaults decodes).
spec:RegisterPack( "Warrior", 20261015, [[Hekili:TkvWUrnmq0VfUbIQWMwajQu4qpuv4WQkmcUn1tCM0yf3yl7jG6f)TZy3DxTlqpGekso2JFZBEVzm0cFfuditW2Z3C(7B30(oqXpgiqfqZmEVSzbFqw)ogJwFSe)rNhhkj2VAD8NwG()KJuGmW223(HwqnzhgONqrjdOU2hPFqXSEhNz9yzHNOS(B2iVIofl8L13oHj5xBwBMiZCWBx4lZ6RqMDsC1KFLZ61Wzz9xOLHSEMc7dCdf9wJaIJ2zb8pT8uwNcyuoefN1iEj6hToXDOHT(Lutisg)d9i31xRXDPsjoZo29I(1XXMJJ2SgYFExI)JWFD3BIIERahOk0Y5FdYu1b3LQgOGTO6p2DXgqjTVKG64oUZM4uDCsJ4QJLTBRJxAb7D0aC1EBkdUJ0fOmrltrlcQ)QQbwkZZqur1NqWPUPK6fptQN4UJ54Glz5tDyI8)0pvMXvEQ8G(gA26Sz9l39U8v1RHF9]] )
```
`.luacheckrc`: after `files["VirtualState/spec/"] = { std = "+busted" }` add (the handlers run with `setfenv( f, state )`):
```lua
files["Forever/Warrior.lua"] = { globals = stateEnv }
```

Check: `grep -F "$(lua5.1 tools/make_pack.lua)" Forever/Warrior.lua` prints the `spec:RegisterPack` line.

- [ ] **Step 3: Verify**

The class file cannot load headless (it needs Hekili); the specs are unchanged.

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [68 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 41 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [no problems found]
git status --short | grep '\.lua$' | awk '{print $2}' | xargs -r -n1 luac5.1 -p   # [no output]
```
- [ ] **Step 4: Commit**
```bash
git add Forever/Warrior.lua tools/make_pack.lua .luacheckrc
git commit -m "feat(forever): Warrior class file with rage, Battle Shout, Rend, Heroic Strike and a default priority; tools/make_pack.lua

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
- [ ] **Step 5: CHECKPOINT 2: stop and ask the user to run the following in game**

Orchestrator: `git push origin virtualstate-phase1`, `git -C ~/src/hekili checkout --detach virtualstate-phase1`. Ask the user, on the Warrior (a level with Rend and Heroic Strike; Battle Shout at 1, Rend at 4):

1. `/reload`. Expected: no Lua error, no popup. `/hekili` opens the options; the Warrior's priority "Warrior" shows its four entries (one precombat, three default).
2. Out of combat: `/run print(Hekili.VirtualState.Snapshot())`. Expected: `class=WARRIOR`; `talent <key> spell=<id> rank=<n>/<max>` lines matching the talent pane (report any mismatch); and `read talent walk aliases: used` or `unused`. Action: `unused` means the walk names every talent by its rank 1 spell, so delete the `ns.VirtualState.Track( { talents = { … } } )` block from `Forever/Warrior.lua` (dead code) in its own commit with the verification block; `used` means keep it; `ability rend qid=<the known rank's ID> cost=10 read=<n> …` and `ability heroic_strike qid=<the known rank's ID> cost=<15 minus the Improved Heroic Strike rank> read=<n> …` (`read` is the client's plain cost, in its own units: report both, they confirm the spec's costs, the talent's reduction included); `power rage est=0.00 … basis=default`; `swing speed main est=<the weapon's speed> … basis=observed`; `read UnitPower: secret`; `read UnitAttackSpeed: readable`.
3. Attack a training dummy for 30 s **without pressing any ability**, then the snapshot again. Expected: `swing main … basis=observed` and `hand 1 … weight=1.0`; `power rage … basis=modelled` (swing steps) or `pinned` (a usability rung); `log …/256 dropped=0`.
4. Recommendations are still empty or wrong: the facade library still answers `UnitPower` with 0 until Task 8. Expected and fine.

Fix what the user reports (each fix its own commit), then repeat. Continue only when the user confirms.


### Task 8: The facade fold and the passthrough revert, CHECKPOINT 3

**Files:**
- Create: `VirtualState/Facade.lua`, `VirtualState/spec/facade_spec.lua`
- Modify (scripted): the 15 Hekili files with facade reads: `Hekili.lua`, `Utils.lua`, `MultilineEditor.lua`, `Constants.lua`, `State.lua`, `Events.lua`, `Classes.lua`, `Forever/Warrior.lua`, `Targets.lua`, `Options/DevTools.lua`, `Options/ChatCommands.lua`, `Options/Options.lua`, `UI.lua`, `Core.lua`, and `VirtualState/Adapter.lua`
- Modify: `Hekili.toc`, `embeds.xml:3`, `.busted`, `.luacheckrc:1-3` and its `read_globals`, `tools/api_inventory.txt`, `tools/check_api_reads.sh`, `tools/list_api_reads.sh`, `.pkgmeta:6`, `Libs/CREDITS.md:41`
- Delete: `Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua`, `Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.xml`, `Libs/VirtualGameAPI-1.0/spec/` (the folder's `LICENSE` and `README.md` stay: no LICENSE or README changes)

**Interfaces:**
- Consumes: every accessor of Tasks 1-6 and `I.res.slotOf`, `I.res.swing`, `I.ab.bySpell`, `I.ab.obj`, `I.GCD_SPELL`.
- Produces: `ns.Facade` with the 51 kept names (34 `virtual`, 17 `stub`), `Facade.Status(name)`, `Facade.Why(name)`, `Facade.Stubs()`, `Facade.Inventory()`, `Facade.Now()`; the facade clock reads `I.pinned` (Task 9 pins it). Every Hekili file reads plain names directly and kept names as `Facade.<name>` / `Facade.<ns>.<name>`.

- [ ] **Step 1: Write the failing spec**

`VirtualState/spec/facade_spec.lua` (the inventory and shape cases of `Libs/VirtualGameAPI-1.0/spec/VirtualGameAPI_spec.lua` move here; the Review Focus case "answers spells, power types and units nothing tracks"):

```lua
-- VirtualState/spec/facade_spec.lua: ns.Facade (spec §7): the inventory equals tools/api_inventory.txt, every kept
-- name answers in its real shape, the stubs never call the game, and the GCD numbers are bit-identical.
-- The inventory and shape cases move here from Libs/VirtualGameAPI-1.0/spec/VirtualGameAPI_spec.lua.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

local INVENTORY = "tools/api_inventory.txt"

local function readInventory()
    local names = {}
    for line in io.lines(INVENTORY) do
        line = line:gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            names[#names + 1] = line
        end
    end
    return names
end

-- The real functions Facade.lua resolves at load, from the fake client; `calls` records any call of a kept name.
local RESOLVED = {
    "GetTime",
    "issecretvalue",
    "UnitPowerType",
    "UnitIsDead",
    "C_Spell.GetSpellCooldown",
    "C_Spell.IsSpellUsable",
    "C_Spell.GetSpellInfo",
    "UnitCastingInfo",
    "UnitChannelInfo",
}

describe("ns.Facade", function()
    local names, ns, Facade, VS, I, api, ctl, calls, saved

    local function entry(name)
        local nsName, key = name:match("^([%w_]+)%.([%w_]+)$")
        if nsName then
            return Facade[nsName] and Facade[nsName][key]
        end
        return Facade[name]
    end

    setup(function()
        names = readInventory()
    end)

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        api.UnitPowerType = function()
            return fs.RAGE
        end
        api.C_Spell.GetSpellInfo = function(id)
            return { name = "Spell " .. id, iconID = 1 }
        end
        calls = {}
        saved = {}
        -- every kept name in _G records a call; the resolved reals answer from the fake client
        for _, n in ipairs(names) do
            local nsName, key = n:match("^([%w_]+)%.([%w_]+)$")
            local f = function()
                calls[#calls + 1] = n
            end
            if nsName then
                saved[nsName] = saved[nsName] or rawget(_G, nsName) or false
                _G[nsName] = _G[nsName] or {}
                _G[nsName][key] = f
            else
                saved[n] = rawget(_G, n) or false
                _G[n] = f
            end
        end
        for _, n in ipairs(RESOLVED) do
            local nsName, key = n:match("^([%w_]+)%.([%w_]+)$")
            if nsName then
                _G[nsName][key] = api[nsName][key]
            else
                saved[n] = saved[n] or rawget(_G, n) or false
                _G[n] = api[n]
            end
        end
        ns = load.module()
        Facade, VS, I = ns.Facade, ns.VirtualState, ns.VirtualStateInternal
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("keeps exactly the inventory's names, each with a status, a reason and a function", function()
        assert.are.same(names, Facade.Inventory())
        for _, n in ipairs(names) do
            local s = Facade.Status(n)
            assert.is_true(s == "virtual" or s == "stub", n .. " status is " .. tostring(s))
            assert.is_function(entry(n), n)
            assert.is_string(Facade.Why(n), n)
        end
        assert.are.equal(51, #names)
        assert.are.equal(17, #Facade.Stubs())
        assert.is_nil(Facade.Status("UnitExists"))
    end)

    it("never calls the game from a stub (absent names never reach _G)", function()
        for _, n in ipairs(Facade.Stubs()) do
            assert.has_no.errors(function()
                entry(n)("target", 1)
            end, n)
        end
        assert.are.same({}, calls)
        assert.are.same({ false, true }, { Facade.UnitInRange("party1") })
        assert.is_nil(Facade.CombatLogGetCurrentEventInfo())
        assert.is_nil(Facade.C_Spell.GetSpellLossOfControlCooldown(1))
    end)

    it("answers resources from the belief: UnitPower is floor(lo); swing-paid regen is 0 in combat", function()
        I.Sources.Direct(VS.Obs.Usable, 5, 3, 1, 0) -- rend usable: rage >= 10
        I.Fold(5, false)
        ctl.now = 5
        assert.are.equal(10, Facade.UnitPower("player", fs.RAGE))
        assert.are.equal(10, Facade.UnitPower("player"))
        assert.are.equal(0, Facade.UnitPower("target", fs.RAGE))
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.are.same({ 0, 0 }, { Facade.GetPowerRegenForPowerType(fs.RAGE) })
        assert.are.equal(2, select("#", Facade.GetManaRegen()))
    end)

    it("answers health, speed, haste and stats in the real shapes", function()
        assert.are.equal(100, Facade.UnitHealth("target"))
        assert.are.equal(100, Facade.UnitHealthMax("target"))
        ctl.dead.nameplate4 = true
        assert.are.equal(0, Facade.UnitHealth("nameplate4"))
        assert.are.equal(100, Facade.UnitHealth("nameplate5"))
        assert.are.same({ 0, 7, 7, 4.72 }, { Facade.GetUnitSpeed("player") })
        assert.are.same({ 0, 0, 0, 0 }, { Facade.GetUnitSpeed("target") })
        assert.are.same({ 2, nil }, { Facade.UnitAttackSpeed("target") })
        assert.are.equal(7, select("#", Facade.UnitDamage("player")))
        assert.are.equal(0, Facade.GetMeleeHaste())
        assert.are.same({ false, "", 0, 0, 0 }, { Facade.GetTotemInfo(1) })
    end)

    it("answers auras through shared AuraData tables in AuraUtil's order", function()
        I.AuraModel(1, 1, 5, 125, 1, 5, VS.Obs.CastSuccess, false)
        ctl.now = 6
        local a = Facade.C_UnitAuras.GetBuffDataByIndex("player", 1)
        assert.are.same({ fs.SHOUT, 125, 120, 1, "player" }, {
            a.spellId,
            a.expirationTime,
            a.duration,
            a.applications,
            a.sourceUnit,
        })
        assert.are.equal(a, Facade.C_UnitAuras.GetBuffDataByIndex("player", 1)) -- shared, not allocated per call
        assert.is_nil(Facade.C_UnitAuras.GetBuffDataByIndex("player", 2))
        assert.are.equal(fs.SHOUT, Facade.C_UnitAuras.GetPlayerAuraBySpellID(fs.SHOUT).spellId)
        local seen = 0
        Facade.AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
            seen = seen + aura.spellId
        end, true)
        assert.are.equal(fs.SHOUT, seen)
        local found = select(10, Facade.AuraUtil.FindAura(function(_, _, _, ...)
            return select(10, ...) == fs.SHOUT
        end, "player", "HELPFUL"))
        assert.are.equal(fs.SHOUT, found)
    end)

    it("returns the same two GCD numbers for the GCD spell and a GCD-locked spell, surviving the round trip", function()
        for _ = 1, 500 do
            local t = math.random() * 1e6
            I.Sources.Direct(VS.Obs.Cooldown, t, 0, 1, 1)
            I.Fold(t, false)
            ctl.now = t + 0.1
            local g = Facade.C_Spell.GetSpellCooldown(29515)
            local gs, gd = g.startTime, g.duration
            assert.are.equal(gs, (gs + gd) - gd)
            ctl.cooldown[fs.REND] = { isActive = true, isOnGCD = true }
            local c = Facade.C_Spell.GetSpellCooldown(fs.REND)
            assert.are.same({ gs, gd }, { c.startTime, c.duration })
            I.Sources.Direct(VS.Obs.Cooldown, t + 1.5, 0, 0, 1)
            I.Fold(t + 1.5, false)
        end
    end)

    it("answers a cooldown from the belief and the plain flag", function()
        I.CooldownModel(3, 40, 30, 10, VS.Obs.CastSuccess)
        ctl.now = 20
        ctl.cooldown[fs.REND] = { isActive = true, isOnGCD = false }
        local c = Facade.C_Spell.GetSpellCooldown(fs.REND)
        assert.are.same({ 10, 30, true }, { c.startTime, c.duration, c.isActive })
        assert.is_nil(Facade.C_Spell.GetSpellCharges(fs.REND))
    end)

    it("passes the player's own casts through and answers the target's from TargetCast", function()
        ctl.casting = { 1000, 2500 }
        assert.are.equal(1000, select(4, Facade.UnitCastingInfo("player")))
        assert.is_nil(Facade.UnitCastingInfo("target"))
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_START", "target", fake.SECRET, fake.SECRET, 77)
        ctl.Tick(10)
        I.Fold(10, false)
        local name, _, _, s, e, _, bar, notKick = Facade.UnitCastingInfo("target")
        assert.are.same({ "Casting", 10000, (10 + I.TARGET_CAST_DEFAULT) * 1000, 77, false }, { name, s, e, bar, notKick })
        assert.is_nil(Facade.UnitChannelInfo("target"))
    end)

    it("answers spells, power types and units nothing tracks in the real shapes, without an error", function()
        local c = Facade.C_Spell.GetSpellCooldown(999999)
        assert.are.same({ 0, 0, false }, { c.startTime, c.duration, c.isActive })
        assert.is_nil(Facade.C_Spell.GetSpellCharges(999999))
        assert.are.equal(0, Facade.UnitPower("player", 99))
        assert.are.same({ 0, 0 }, { Facade.GetPowerRegenForPowerType(99) })
        assert.is_nil(Facade.C_UnitAuras.GetPlayerAuraBySpellID(999999))
        assert.is_nil(Facade.C_UnitAuras.GetBuffDataByIndex("focus", 1))
        assert.are.equal(0, Facade.UnitSpellHaste("target"))
    end)

    it("aliases IsUsableSpell to C_Spell.IsSpellUsable", function()
        ctl.usable[5] = { true, false }
        assert.is_true(Facade.IsUsableSpell(5))
    end)
end)
```
Run: `~/src/TacoDogForever/.lua/bin/busted VirtualState/spec/facade_spec.lua`
Expected: errors: `attempt to index local 'Facade' (a nil value)` (no Facade.lua yet).

- [ ] **Step 2: Write `VirtualState/Facade.lua`**

```lua
-- VirtualState/Facade.lua
-- ns.Facade (spec §7): the game API names that are secret in combat, partly secret, or absent on WoW Forever. Each is
-- `virtual` (a policy answering from VirtualState, §7.4) or `stub` (a fixed, API-shaped result, §7.3); every other
-- game read in Hekili is a direct call. Namespaces mirror the game (Facade.UnitPower, Facade.C_Spell.GetSpellCooldown,
-- Facade.AuraUtil.ForEachAura). Query with Facade.Status(name), Facade.Why(name), Facade.Stubs(), Facade.Inventory().
-- Every policy uses now = GetTime(), or the clock Drain pins while it applies a cast (spec §5.5 R1), and returns
-- shared preallocated result tables that callers read at once and never keep or mutate.
-- Origin: Libs/VirtualGameAPI-1.0, folded into Hekili. Copyright (c) 2026 Zack Samsel. MIT licence, see
-- Libs/VirtualGameAPI-1.0/LICENSE.
-- Credits: the issecretvalue tests on the real cooldown flags follow Catnip's (Durts) secret-value research.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local floor, find, HUGE = math.floor, string.find, math.huge
local _G = _G

local Facade = {}
ns.Facade = Facade

local status, why, inventory = {}, {}, {}

local function split(name)
    local nsName, key = name:match("^([%w_]+)%.([%w_]+)$")
    if nsName then
        return nsName, key
    end
    return nil, name
end

-- The real function `name` names, or nil (absent on this client). Load time only.
local function resolve(name)
    local nsName, key = split(name)
    if nsName then
        local t = _G[nsName]
        return t and t[key]
    end
    return _G[key]
end

local function kept(name, kind, fn, reason)
    local nsName, key = split(name)
    local t = Facade
    if nsName then
        Facade[nsName] = Facade[nsName] or {}
        t = Facade[nsName]
    end
    t[key] = fn
    inventory[#inventory + 1] = name
    status[name], why[name] = kind, reason
end

local GetTime = resolve("GetTime")
local issecretvalue = resolve("issecretvalue") or function()
    return false
end
local realUnitPowerType = resolve("UnitPowerType")
local realUnitIsDead = resolve("UnitIsDead")
local realGetSpellCooldown = resolve("C_Spell.GetSpellCooldown")
local realIsSpellUsable = resolve("C_Spell.IsSpellUsable")
local realGetSpellInfo = resolve("C_Spell.GetSpellInfo")
local realUnitCastingInfo = resolve("UnitCastingInfo")
local realUnitChannelInfo = resolve("UnitChannelInfo")

-- The facade's clock: the pinned cast time during a drain, else GetTime().
local function now()
    return I.pinned or GetTime()
end
Facade.Now = now

-- Shared stub results (the original's, VirtualGameAPI-1.0.lua:77-88).
local function nothing()
    return nil
end
local function zero()
    return 0
end
local function isFalse()
    return false
end
local function inRangeUnknown()
    return false, true
end

----------------------------------------------------------------------------------------------------------------------
-- Resources [W PR16]

kept("UnitPower", "virtual", function(unit, powerType)
    if unit ~= "player" then
        return 0
    end
    if powerType == nil then
        powerType = realUnitPowerType and realUnitPowerType("player") or 0
    end
    return floor(VS.Power(powerType, now()).lo) -- lo never over-promises a spender (feasibility §D.3)
end, "secret always [W PR16]; Power().lo")

kept("GetPowerRegenForPowerType", "virtual", function(powerType)
    local r = I.res.slotOf[powerType]
    if r and I.res.swing[r] > 0 and VS.InCombat() then
        return 0, 0 -- Hekili's swing regen model adds that resource (no double count, G3)
    end
    local est = VS.Regen(powerType, now()).est
    return est, est
end, "secret in combat [W PR16]; Regen()")

kept("GetManaRegen", "virtual", function()
    local t = now()
    local inactive = VS.Regen(0, t).est
    return inactive, VS.Regen(0, t, true).est
end, "secret in combat [W PR16]; Regen(0)")

kept("UnitPartialPower", "stub", zero, "secret always [W PR16]; no Forever user")

----------------------------------------------------------------------------------------------------------------------
-- Health [W PR14]

kept("UnitHealth", "virtual", function(unit)
    if unit == "player" then
        return VS.Health("player", now()).est * VS.HealthMax("player")
    elseif unit == "target" then
        return VS.Health("target", now()).est * 100
    end
    local dead = realUnitIsDead and realUnitIsDead(unit) -- secret: tested next
    if issecretvalue(dead) or dead then
        return 0
    end
    return 100 -- keeps the enemy scan's UnitHealth( unit ) > 1 (Targets.lua:407, 484) meaningful
end, "target secret always [W PR14]; Health()")

kept("UnitHealthMax", "virtual", function(unit)
    return VS.HealthMax(unit)
end, "target secret always [W PR14]; HealthMax()")

kept("UnitGetTotalAbsorbs", "stub", zero, "target secret always [W PR14]")

----------------------------------------------------------------------------------------------------------------------
-- Stats: the out-of-combat cache [W PR2, PR4]

local STAT = "secret in combat [W PR2, PR4]; Stat()"
kept("GetCombatRating", "virtual", function(cr)
    return VS.Stat("GetCombatRating", cr)
end, STAT)
kept("GetCombatRatingBonus", "virtual", function(cr)
    return VS.Stat("GetCombatRatingBonus", cr)
end, STAT)
kept("GetCritChance", "virtual", function()
    return VS.Stat("GetCritChance")
end, STAT)
kept("GetMasteryEffect", "virtual", function()
    return VS.Stat("GetMasteryEffect")
end, STAT)
kept("GetRangedCritChance", "virtual", function()
    return VS.Stat("GetRangedCritChance")
end, STAT)
kept("GetSpellBonusDamage", "virtual", function(school)
    return VS.Stat("GetSpellBonusDamage", school)
end, STAT)
kept("GetSpellCritChance", "virtual", function()
    return VS.Stat("GetSpellCritChance")
end, STAT)
kept("UnitArmor", "virtual", function()
    return VS.Stat("UnitArmor")
end, STAT)
kept("UnitAttackPower", "virtual", function()
    return VS.Stat("UnitAttackPower")
end, STAT)
kept("UnitDamage", "virtual", function()
    return VS.Stat("UnitDamage")
end, STAT)
kept("UnitStat", "virtual", function(unit, index)
    return VS.Stat("UnitStat", index)
end, STAT)
kept("UnitWeaponAttackPower", "virtual", function()
    return VS.Stat("UnitWeaponAttackPower")
end, STAT)

----------------------------------------------------------------------------------------------------------------------
-- Haste and speed [W PR2, PR7, PR14; SU PR2]

local function meleeHaste()
    return (VS.Haste(now()).est - 1) * 100
end
kept("GetHaste", "virtual", meleeHaste, "secret in combat [W PR2, PR4]; Haste()")
kept("GetMeleeHaste", "virtual", meleeHaste, "secret in combat [W PR2, PR4]; Haste()")

kept("UnitSpellHaste", "virtual", function(unit)
    if unit ~= "player" then
        return 0
    end
    return VS.SpellHaste(now()).est
end, "secret in combat [W PR2, PR4]; SpellHaste()")

kept("UnitAttackSpeed", "virtual", function(unit)
    if unit ~= "player" then
        return 2, nil
    end
    local t = now()
    local main = VS.SwingSpeed(1, t).est
    local off = VS.SwingSpeed(2, t).est
    if off > 0 then
        return main, off
    end
    return main, nil
end, "secret in combat [SU PR2]; SwingSpeed()")

kept("GetUnitSpeed", "virtual", function(unit)
    if unit == "player" and VS.Moving() then
        return 7, 7, 7, 4.72
    elseif unit == "player" then
        return 0, 7, 7, 4.72
    end
    return 0, 0, 0, 0
end, "secret in combat [W PR14]; Moving()")

kept("UnitInRange", "stub", inRangeUnknown, "secret always [W PR7]; no signal")

----------------------------------------------------------------------------------------------------------------------
-- Totems [W PR12]

kept("GetTotemInfo", "virtual", function(slot)
    local spellID, name, icon, start = VS.TotemFacts(slot)
    local rec = spellID and VS.Totem(slot, now())
    if not rec then
        return false, "", 0, 0, 0
    end
    return true, name, start, rec.est - start, icon, 1, spellID
end, "secret in combat [W PR12]; Totem(), TotemFacts()")

----------------------------------------------------------------------------------------------------------------------
-- Auras [W §4]: one shared AuraData per index slot, one more for the by-ID and by-instance reads.

local AURA_SLOTS = 40
local POINTS = {}
local function newAura()
    return {
        name = "",
        icon = 0,
        applications = 0,
        dispelName = nil,
        duration = 0,
        expirationTime = 0,
        sourceUnit = "player",
        isStealable = false,
        nameplateShowPersonal = false,
        spellId = 0,
        canApplyAura = true,
        isBossAura = false,
        isFromPlayerOrPlayerPet = true,
        nameplateShowAll = false,
        timeMod = 1,
        auraInstanceID = 0,
        isHelpful = true,
        isHarmful = false,
        points = POINTS,
    }
end
local slots = {}
for i = 1, AURA_SLOTS do
    slots[i] = newAura()
end
local single = newAura()

-- Spell names and icons, read once per spell ID (the client allocates its info table once per ID).
local names, icons = {}, {}
local function spellName(id)
    local n = names[id]
    if n == nil then
        local info = realGetSpellInfo and realGetSpellInfo(id)
        n = info and info.name or tostring(id)
        names[id], icons[id] = n, info and info.iconID or 0
    end
    return n, icons[id]
end

local function fill(t, spellID, rec, stacks, applied, instance, harmful)
    t.name, t.icon = spellName(spellID)
    t.spellId, t.applications, t.auraInstanceID = spellID, stacks, instance
    if rec.est == HUGE then
        t.expirationTime, t.duration = 0, 0 -- no expiry, as the client says it
    else
        t.expirationTime = rec.lo -- the early bound: refresh sooner rather than late
        t.duration = rec.est - applied
    end
    t.isHarmful, t.isHelpful = harmful, not harmful
    return t
end

local function auraAt(unit, harmful, i)
    local spellID, rec, stacks, applied, instance = VS.AuraAt(unit, harmful and "HARMFUL" or "HELPFUL", i, now())
    if not spellID or i > AURA_SLOTS then
        return nil
    end
    return fill(slots[i], spellID, rec, stacks, applied, instance, harmful)
end

kept("C_UnitAuras.GetBuffDataByIndex", "virtual", function(unit, i)
    return auraAt(unit, false, i)
end, "secret in combat; errors when tainted [W §4]; AuraAt()")

kept("C_UnitAuras.GetDebuffDataByIndex", "virtual", function(unit, i)
    return auraAt(unit, true, i)
end, "secret in combat; errors when tainted [W §4]; AuraAt()")

kept("C_UnitAuras.GetPlayerAuraBySpellID", "virtual", function(spellID)
    local rec, stacks, applied, instance = VS.Aura("player", spellID, now())
    if not rec then
        return nil
    end
    return fill(single, spellID, rec, stacks, applied, instance, false)
end, "secret in combat; errors when tainted [W §4]; Aura()")

kept("C_UnitAuras.GetAuraDataByAuraInstanceID", "virtual", function(unit, instanceID)
    local spellID, rec, stacks, applied = VS.AuraByInstance(unit, instanceID, now())
    if not spellID then
        return nil
    end
    return fill(single, spellID, rec, stacks, applied, instanceID, unit ~= "player")
end, "secret in combat; errors when tainted [W §4]; AuraByInstance()")

kept("AuraUtil.ForEachAura", "virtual", function(unit, filter, maxCount, fn)
    local harmful = filter and find(filter, "HARMFUL", 1, true) ~= nil or false
    for i = 1, maxCount or AURA_SLOTS do
        local t = auraAt(unit, harmful, i)
        if not t or fn(t) then
            return
        end
    end
end, "wraps secret aura data [W §4]; AuraAt(), the shared AuraData")

-- AuraUtil.UnpackAuraData's order (without the points), for FindAura's predicate and result.
local function unpackAura(t)
    return t.name,
        t.icon,
        t.applications,
        t.dispelName,
        t.duration,
        t.expirationTime,
        t.sourceUnit,
        t.isStealable,
        t.nameplateShowPersonal,
        t.spellId,
        t.canApplyAura,
        t.isBossAura,
        t.isFromPlayerOrPlayerPet,
        t.nameplateShowAll,
        t.timeMod
end

kept("AuraUtil.FindAura", "virtual", function(predicate, unit, filter, arg1, arg2, arg3)
    local harmful = filter and find(filter, "HARMFUL", 1, true) ~= nil or false
    for i = 1, AURA_SLOTS do
        local t = auraAt(unit, harmful, i)
        if not t then
            return nil
        end
        if predicate(arg1, arg2, arg3, unpackAura(t)) then
            return unpackAura(t)
        end
    end
    return nil
end, "wraps secret aura data [W §4]; AuraAt()")

kept("C_UnitAuras.GetAuraSlots", "stub", nothing, "secret in combat [W §4]; no retained consumer")
kept("UnitAura", "stub", nothing, "absent on Forever")
kept("UnitAuraBySlot", "stub", nothing, "absent on Forever")

----------------------------------------------------------------------------------------------------------------------
-- Cooldowns [W PR4, PR11]: times secret in combat, flags plain

local CD = { startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }
local CHARGES = { currentCharges = 1, maxCharges = 1, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }

-- The real call's plain flags: isActive, isOnGCD (each nil when secret or unreadable).
local function flags(spellID)
    local info = realGetSpellCooldown and realGetSpellCooldown(spellID) -- secret: tested next, then each field
    if issecretvalue(info) or type(info) ~= "table" then
        return nil, nil
    end
    local active, onGcd = info.isActive, info.isOnGCD -- secret: each tested next
    if issecretvalue(active) then
        active = nil
    end
    if issecretvalue(onGcd) then
        onGcd = nil
    end
    return active, onGcd
end

kept("C_Spell.GetSpellCooldown", "virtual", function(spellID)
    local t = now()
    if spellID == 61304 or spellID == I.GCD_SPELL then
        local s, d = VS.GcdInfo(t)
        CD.startTime, CD.duration, CD.isActive, CD.isOnGCD = s, d, d > 0, false
        return CD
    end
    local active, onGcd = flags(spellID)
    if onGcd == true then
        -- bit-identical to the GCD's numbers, so Hekili zeroes it (State.lua:2972-2975, spec §7.5)
        local s, d = VS.GcdInfo(t)
        CD.startTime, CD.duration, CD.isActive, CD.isOnGCD = s, d, true, true
        return CD
    end
    local rec = VS.Cooldown(spellID, t)
    CD.isOnGCD = false
    if not rec then
        CD.startTime, CD.duration = 0, 0
        CD.isActive = active == true
        return CD
    end
    local len = VS.CooldownLength(spellID)
    CD.startTime, CD.duration = rec.est - len, len
    if active ~= nil then
        CD.isActive = active
    else
        CD.isActive = rec.est > t
    end
    return CD
end, "times secret in combat, flags plain [W PR4, PR11]; Cooldown(), GcdInfo()")

kept("C_Spell.GetSpellCharges", "virtual", function(spellID)
    local cur, nextAt = VS.Charges(spellID, now())
    if not cur then
        return nil
    end
    local a = I.ab.bySpell[spellID]
    local obj = I.ab.obj[a]
    local recharge = type(obj.recharge) == "number" and obj.recharge or 0
    CHARGES.currentCharges = floor(cur.est)
    CHARGES.maxCharges = type(obj.charges) == "number" and obj.charges or 1
    CHARGES.cooldownStartTime = nextAt.est > 0 and nextAt.est - recharge or 0
    CHARGES.cooldownDuration = recharge
    return CHARGES
end, "times secret in combat [W §4 cooldowns]; Charges()")

kept("C_Spell.GetSpellCastCount", "stub", zero, "flagged SecretWhenCooldownsRestricted; unprobed, unused")
kept("C_Spell.GetSpellLossOfControlCooldown", "stub", nothing, "absent on Forever")

----------------------------------------------------------------------------------------------------------------------
-- Casts: the player's own are plain [W PR9], the target's secret [W PR8]

local CAST_ICON = 136243

kept("UnitCastingInfo", "virtual", function(unit, ...)
    if unit == "player" then
        if realUnitCastingInfo then
            return realUnitCastingInfo(unit, ...)
        end
        return nil
    elseif unit ~= "target" then
        return nil
    end
    local channel, castBarID, start, kick = VS.TargetCastFacts()
    local rec = channel == false and VS.TargetCast(now())
    if not rec then
        return nil
    end
    return "Casting", "", CAST_ICON, start * 1000, rec.est * 1000, false, castBarID, kick == 0, 0
end, "player plain [W PR9]; target secret [W PR8]; TargetCast()")

kept("UnitChannelInfo", "virtual", function(unit, ...)
    if unit == "player" then
        if realUnitChannelInfo then
            return realUnitChannelInfo(unit, ...)
        end
        return nil
    elseif unit ~= "target" then
        return nil
    end
    local channel, _, start, kick = VS.TargetCastFacts()
    local rec = channel == true and VS.TargetCast(now())
    if not rec then
        return nil
    end
    return "Channeling", "", CAST_ICON, start * 1000, rec.est * 1000, false, kick == 0, 0
end, "player plain [W PR9]; target secret [W PR8]; TargetCast()")

----------------------------------------------------------------------------------------------------------------------
-- Combat log, talents, spells and items: absent on Forever, or replaced

kept("CombatLogGetCurrentEventInfo", "stub", nothing, "absent; registering CLEU is forbidden (Phases 2 and 3)")
kept("GetTalentInfoByID", "stub", nothing, "dead on Forever [W PR5]; ranks come from VirtualState.Talent")
kept("IsUsableSpell", "virtual", function(spellID)
    if realIsSpellUsable then
        return realIsSpellUsable(spellID)
    end
    return false
end, "absent on Forever; alias of C_Spell.IsSpellUsable (plain [W PR14; SU])")
kept("GetSpellBaseCooldown", "stub", nothing, "absent on Forever")
kept("GetSpellLink", "stub", nothing, "absent on Forever")
kept("IsHarmfulSpell", "stub", isFalse, "absent on Forever")
kept("IsHelpfulSpell", "stub", isFalse, "absent on Forever")
kept("IsPassiveSpell", "stub", isFalse, "absent on Forever")
kept("GetItemGem", "stub", nothing, "absent on Forever")
kept("GetItemInfo", "stub", nothing, "absent on Forever")

----------------------------------------------------------------------------------------------------------------------

table.sort(inventory)
local stubs = {}
for _, name in ipairs(inventory) do
    if status[name] == "stub" then
        stubs[#stubs + 1] = name
    end
end

function Facade.Status(name)
    return status[name]
end
function Facade.Why(name)
    return why[name]
end
function Facade.Stubs()
    return stubs
end
function Facade.Inventory()
    return inventory
end
```
In `Hekili.toc`, after `VirtualState\Snapshot.lua` add `VirtualState\Facade.lua`.

- [ ] **Step 2b: Only if CHECKPOINT 1's probes printed `true` for a name**

For each probed name that printed `true`, it joins the kept list as a `virtual` name answering the plain value or the stub shape (spec §7.7). Add the matching block to `VirtualState/Facade.lua` just before its closing `table.sort( inventory )` section, add the name to `/tmp/vs-kept.txt` in Step 3 (after the `grep` and before the rewrite, keeping it sorted), and the facade spec's counts become 52+ kept / 17 stubs:
```lua
local realGetItemCooldown = resolve("C_Item.GetItemCooldown")
kept("C_Item.GetItemCooldown", "virtual", function(item)
    local s, d, e = realGetItemCooldown(item) -- secret: each tested next
    if issecretvalue(s) or issecretvalue(d) or issecretvalue(e) then
        return 0, 0, 1
    end
    return s, d, e
end, "probed secret in combat (CHECKPOINT 1); the plain value, else ready")

local realIsSpellUsable2 = resolve("C_Spell.IsSpellUsable")
kept("C_Spell.IsSpellUsable", "virtual", function(spellID)
    local ok, short = realIsSpellUsable2(spellID) -- secret: each tested next
    if issecretvalue(ok) or issecretvalue(short) then
        return true, false
    end
    return ok, short
end, "probed secret in combat (CHECKPOINT 1); the plain value, else usable")

local realThreat = resolve("UnitThreatSituation")
kept("UnitThreatSituation", "virtual", function(unit, other)
    local v = realThreat(unit, other) -- secret: tested next
    if issecretvalue(v) then
        return nil
    end
    return v
end, "probed secret in combat (CHECKPOINT 1); the plain value, else nil")

local realLockdown = resolve("InCombatLockdown")
kept("InCombatLockdown", "virtual", function()
    local v = realLockdown() -- secret: tested next
    if issecretvalue(v) then
        return VS.InCombat()
    end
    return v
end, "probed secret in combat (CHECKPOINT 1); the plain value, else VirtualState.InCombat()")
```
Remove the name from the `.luacheckrc` block of Step 5 (a kept name stays undeclared). If every probe printed `false`, skip this step.

- [ ] **Step 3: Rewrite every facade read (spec §7.7)**

Save the one-off script as `/tmp/vs-revert.lua` (not committed):

```lua
-- One-off rewrite for VirtualState Phase 1, spec §7.7: VGA reads become direct calls, except the 51 kept names,
-- which become ns.Facade reads. Run from the repository root: lua5.1 /tmp/vs-revert.lua <kept.txt> <file>...
local keptFile = arg[1]
local KEPT, NSKIND = {}, {}
for line in io.lines(keptFile) do
    if line ~= "" then KEPT[line] = true end
end
-- A namespace whose every inventory member is kept is read through the facade as a whole (C_UnitAuras).
for line in io.lines("tools/api_inventory.txt") do
    local ns = line:match("^([%w_]+)%.")
    if ns then
        local k = KEPT[line] and "kept" or "plain"
        if NSKIND[ns] == nil or NSKIND[ns] == k then NSKIND[ns] = k else NSKIND[ns] = "mixed" end
    end
end
local SHIM = {
    HasOverrideActionBar = true, HasVehicleActionBar = true, IsActionInRange = true, IsPlayerSpell = true,
    IsSpellKnown = true, IsSpellKnownOrOverridesKnown = true, SpellIsSelfBuff = true,
}
local DOTTED = {}
for name in pairs(KEPT) do
    local ns, key = name:match("^([%w_]+)%.([%w_]+)$")
    if ns then DOTTED[#DOTTED + 1] = { ns, key } end
end
table.sort(DOTTED, function(a, b) return a[1] .. a[2] < b[1] .. b[2] end)

local function rewrite(line)
    line = line:gsub("VGA%.([%w_]+)%.([%w_]+)", function(ns, key)
        return (KEPT[ns .. "." .. key] and "Facade." or "") .. ns .. "." .. key
    end)
    line = line:gsub("VGA%.([%w_]+)", function(name)
        if NSKIND[name] then return (NSKIND[name] == "kept" and "Facade." or "") .. name end
        if KEPT[name] then return "Facade." .. name end
        if SHIM[name] then return name .. " or function() end" end
        return name
    end)
    for _, d in ipairs(DOTTED) do
        line = line:gsub("([^.%w_])" .. d[1] .. "%." .. d[2] .. "%f[^%w_]", "%1Facade." .. d[1] .. "." .. d[2])
        line = line:gsub("^" .. d[1] .. "%." .. d[2] .. "%f[^%w_]", "Facade." .. d[1] .. "." .. d[2])
    end
    return line
end

for i = 2, #arg do
    local path = arg[i]
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    local out, vgaAt, usesFacade = {}, nil, false
    for line in (text:sub(-1) == "\n" and text or text .. "\n"):gmatch("([^\n]*)\n") do
        if line:match('^local VGA = LibStub%( "VirtualGameAPI%-1%.0" %)%s*$') then
            vgaAt = #out + 1
            out[vgaAt] = line
        else
            line = rewrite(line)
            if line:find("Facade.", 1, true) then usesFacade = true end
            out[#out + 1] = line
        end
    end
    if vgaAt then
        if usesFacade then out[vgaAt] = "local Facade = ns.Facade" else table.remove(out, vgaAt) end
    end
    f = assert(io.open(path, "w"))
    f:write(table.concat(out, "\n"), text:sub(-1) == "\n" and "\n" or "")
    f:close()
    print(path, vgaAt and (usesFacade and "facade" or "direct") or "untouched")
end
```
Run, in this order (the script reads the namespace kinds from the 175-name `tools/api_inventory.txt`, so the inventory is replaced only after it ran):
```bash
grep -o '^stub( "[^"]*"' Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua | sed 's/^stub( "//; s/"$//' | sort > /tmp/vs-kept.txt
wc -l < /tmp/vs-kept.txt                                   # 51
FILES=$(grep -E '\.lua\s*$' Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//' \
  | grep -v '^VirtualState/' ; echo VirtualState/Adapter.lua)
lua5.1 /tmp/vs-revert.lua /tmp/vs-kept.txt $FILES
cp /tmp/vs-kept.txt tools/api_inventory.txt
git rm -rq Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.xml Libs/VirtualGameAPI-1.0/spec
```
Expected script output (one line per file): `Hekili.lua facade`, `Utils.lua facade`, `Formatting.lua untouched`, `MultilineEditor.lua direct`, `Constants.lua direct`, `State.lua facade`, `Events.lua facade`, `Classes.lua facade`, `Forever/Warrior.lua direct`, `Targets.lua facade`, `Options/DevTools.lua facade`, `Options/ChatCommands.lua direct`, `Options/Options.lua direct`, `UI.lua facade`, `Scripts.lua untouched`, `Core.lua direct`, `VirtualState/Adapter.lua direct`. Then `grep -rn 'VGA' --include=*.lua . | grep -v '^./archive' | grep -v '^./Libs'` prints nothing.

What the rewrite does, rule by rule (spec §7.7): line 5 `local VGA = LibStub( "VirtualGameAPI-1.0" )` becomes `local Facade = ns.Facade` in a file that reads a kept name and is deleted otherwise; `VGA.<plain>` becomes `<plain>` (so `local GetTime = VGA.GetTime` becomes `local GetTime = GetTime`); `VGA.<kept>` becomes `Facade.<kept>`; a namespace alias becomes the direct namespace, except `C_UnitAuras`, all of whose members are kept, which becomes `Facade.C_UnitAuras`; every dotted kept member anywhere (`C_Spell.GetSpellCooldown`, `C_UnitAuras.GetBuffDataByIndex`, `AuraUtil.ForEachAura`, …) becomes `Facade.<ns>.<name>`; the seven deprecation shims become `<name> or function() end` (spec §7.3; no new local, `State.lua` stays at its 200-locals cap). Examples from the replay: `State.lua:6` `local C_Item, C_LossOfControl, C_Spell = C_Item, C_LossOfControl, C_Spell`; `State.lua:11` `local IsInRaid, IsMounted, IsPlayerSpell, IsSpellKnown = IsInRaid, IsMounted, IsPlayerSpell or function() end, IsSpellKnown or function() end`; `State.lua:35` `… = ns.GetUnpackedSpellInfo, Facade.C_Spell.GetSpellCharges, Facade.C_Spell.GetSpellLossOfControlCooldown`; `Core.lua:5` `local GetFrameCPUUsage, GetTime, InCombatLockdown = GetFrameCPUUsage, GetTime, InCombatLockdown`.

- [ ] **Step 4: Embeds and busted**

`embeds.xml`: delete line 3, `	<Include file="Libs\VirtualGameAPI-1.0\VirtualGameAPI-1.0.xml"/>`.

`.busted` (whole file):
```lua
return {
    default = { ROOT = { "VirtualState/spec" }, pattern = "_spec", lpath = "./?.lua", verbose = true },
}
```

- [ ] **Step 4b: Packaging and credits no longer name the library as loaded**

`.pkgmeta` line 6, `    - Libs/VirtualGameAPI-1.0/spec`, becomes `    - VirtualState/spec` (the specs never ship).

`Libs/CREDITS.md` line 41,
```
| VirtualGameAPI-1.0 | This repository | in-repo | MIT, `LICENSE` | Hekili Forever port | Yes (written for Forever) | None |
```
becomes
```
| VirtualGameAPI-1.0 | This repository | folded into `VirtualState/Facade.lua` (VirtualState Phase 1); the folder keeps only its `LICENSE` and `README.md` and is not loaded | MIT, `LICENSE` | Hekili Forever port | Yes (written for Forever) | None |
```

- [ ] **Step 5: Lint and the read tools (spec §7.7)**

`.luacheckrc` lines 1-3 become:

```lua
-- Lint for the Forever branch. Every secret or absent game read goes through ns.Facade (VirtualState/Facade.lua; see
-- tools/check_api_reads.sh): those names (tools/api_inventory.txt) are deliberately NOT declared here, so a bare read
-- shows up as W113 "accessing undefined variable". The plain game reads are declared in read_globals below.
```
and in `read_globals`, just before the line `    -- client additions to the Lua standard tables`, insert (every reverted name; namespaces whole; the 51 kept names stay undeclared):

```lua
    -- plain game reads (spec §7.7): called directly; namespaces declared whole (their kept members are caught by
    -- tools/check_api_reads.sh's dotted grep)
    "AuraUtil", "C_AddOns", "C_ClassColor", "C_ClassTalents", "C_Item", "C_LossOfControl", "C_PetBattles",
    "C_PlayerInfo", "C_PvP", "C_SpecializationInfo", "C_Spell", "C_SpellActivationOverlay", "C_SpellBook",
    "C_Texture", "C_TooltipInfo", "C_Traits", "C_VideoOptions", "GetActionInfo", "GetBindingKey", "GetBuildInfo",
    "GetCVar", "GetClassInfo", "GetCursorInfo", "GetFrameCPUUsage", "GetFramerate", "GetInstanceInfo",
    "GetInventoryItemID", "GetNetStats", "GetNumClasses", "GetNumGroupMembers", "GetNumSubgroupMembers",
    "GetRealmName", "GetShapeshiftForm", "GetShapeshiftFormInfo", "GetSpecializationInfoByID", "GetStablePetInfo",
    "GetTime", "HasOverrideActionBar", "HasVehicleActionBar", "InCombatLockdown", "IsActionInRange", "IsInGroup",
    "IsInInstance", "IsInJailersTower", "IsInRaid", "IsMounted", "IsPlayerSpell", "IsResting", "IsSpellKnown",
    "IsSpellKnownOrOverridesKnown", "SecureCmdOptionParse", "SpellIsSelfBuff", "UnitAffectingCombat",
    "UnitCanAssist", "UnitCanAttack", "UnitClass", "UnitClassBase", "UnitClassification", "UnitCreatureType",
    "UnitEffectiveLevel", "UnitExists", "UnitFactionGroup", "UnitGUID", "UnitHasVehicleUI", "UnitInParty",
    "UnitInRaid", "UnitInVehicle", "UnitIsConnected", "UnitIsDead", "UnitIsDeadOrGhost", "UnitIsFriend", "UnitIsPVP",
    "UnitIsPlayer", "UnitIsTrivial", "UnitIsUnit", "UnitLevel", "UnitName", "UnitOnTaxi", "UnitPhaseReason",
    "UnitPowerMax", "UnitPowerType", "UnitRace", "UnitSex", "UnitThreatSituation", "UnitTokenFromGUID",
```
`tools/check_api_reads.sh` (whole file; it adds the dotted-name grep, comment-aware, outside `VirtualState/Facade.lua`):
```bash
#!/usr/bin/env bash
# Fails when a file loaded by Hekili.toc reads a game API from tools/api_inventory.txt (the names that are secret in
# combat, partly secret or absent on Forever) directly instead of through ns.Facade (VirtualState/Facade.lua). Bare
# reads come from luacheck W113 (which ignores strings and comments); _G.Name and _G["Name"] reads, and dotted reads of
# a kept namespace member (C_Spell.GetSpellCooldown: a declared namespace global hides its members from W113), come
# from grep. VirtualState/ reads the game only through its injected `api` (VirtualState/spec/secrets_spec.lua checks
# it); VirtualState/Facade.lua names every kept read in strings, so the dotted grep skips it.
set -uo pipefail
cd "$(dirname "$0")/.."
LUACHECK="${LUACHECK:-luacheck}"
command -v "$LUACHECK" >/dev/null || { echo "luacheck not found: set LUACHECK" >&2; exit 1; }
mapfile -t files < <(grep -E '\.lua\s*$' Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//')
bare=$(grep -vF '.' tools/api_inventory.txt | paste -sd'|')
dotted=$(grep -F '.' tools/api_inventory.txt | sed 's/\./\\./' | paste -sd'|')
fail=0
out=$("$LUACHECK" --no-config --std none --formatter plain --codes "${files[@]}"); rc=$?
[ $rc -ge 2 ] && { echo "luacheck failed (syntax error?)" >&2; exit 1; }
hits=$(grep -E "accessing undefined variable '($bare)'" <<<"$out")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
hits=$(grep -nE "_G(\.|\[[\"'])($bare)\b" "${files[@]}")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
# comments stripped, so a comment naming a kept read is not a read
hits=$(for f in "${files[@]}"; do
    [ "$f" = VirtualState/Facade.lua ] && continue
    sed 's/--.*$//' "$f" | grep -nE "(^|[^.[:alnum:]_])($dotted)\b" | sed "s|^|$f:|"
done)
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: no direct secret or absent game API read in ${#files[@]} loaded files"
exit $fail
```
`tools/list_api_reads.sh` (whole file; it lists `Facade.` reads in place of `VGA.` reads):
```bash
#!/usr/bin/env bash
# Lists the game API names the loaded Hekili files read: bare globals (via luacheck W113, which ignores strings and
# comments), C_* and AuraUtil namespace members (via grep), _G.Name reads, and Facade.Name / Facade.ns.Name reads
# (the secret or absent names Hekili reads through ns.Facade, VirtualState/Facade.lua).
# Usage: tools/list_api_reads.sh [file ...]   (default: every .lua in Hekili.toc minus the archived
# expansion folders)
set -euo pipefail
cd "$(dirname "$0")/.."
LUACHECK="${LUACHECK:-luacheck}"
command -v "$LUACHECK" >/dev/null || { echo "luacheck not found: set LUACHECK" >&2; exit 1; }
if [ $# -gt 0 ]; then files=("$@"); else
    mapfile -t files < <(grep -E '\.lua\s*$' Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//')
    # archived expansion folders are never redirected, so their reads are not inventoried
    mapfile -t files < <(printf '%s\n' "${files[@]}" | grep -vE '^(TheWarWithin|Dragonflight|Shadowlands|BfA|Legion|Wrath|Cataclysm|TheBurningCrusade)/')
fi
{
    "$LUACHECK" --no-config --std none --formatter plain --codes "${files[@]}" \
        | grep -oE "accessing undefined variable '[^']+'" | sed -E "s/.*'([^']+)'/\1/" || true
    grep -ohE "\b(C_[A-Za-z]+|AuraUtil)\.[A-Za-z_]+" "${files[@]}" || true
    grep -ohE "_G\.[A-Za-z_]+" "${files[@]}" | sed 's/^_G\.//' || true
    grep -ohE "\bFacade\.[A-Za-z_]+(\.[A-Za-z_]+)?" "${files[@]}" | sed 's/^Facade\.//' || true
} | sort -u
```
- [ ] **Step 6: Run the specs to see them pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `69 successes / 0 failures / 0 errors` (the 9 library cases are gone with the library; `facade_spec` adds 10).

- [ ] **Step 7: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [69 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 42 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [no problems found]
git status --short | grep '\.lua$' | awk '{print $2}' | xargs -r -n1 luac5.1 -p   # [no output]
```
Also: `git diff --stat HEAD | tail -1` reports 29 files changed (the replay: 919 insertions, 783 deletions; the library's LICENSE and README kept).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(virtualstate): fold the facade into VirtualState/Facade.lua; plain reads back to direct calls; tools enforce the kept list

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
- [ ] **Step 9: CHECKPOINT 3: stop and ask the user to run the following in game**

Orchestrator: `git push origin virtualstate-phase1`, `git -C ~/src/hekili checkout --detach virtualstate-phase1`. Ask the user:

1. `/reload`. Expected: no Lua error, no popup (the library is gone; any "attempt to call a nil value" naming a reverted name means a name absent on Forever escaped the kept list: report the line).
2. `/hekili` opens; out of combat `/run print(Hekili.VirtualState.Snapshot())` still shows `power rage est=0.00 … basis=default`.
3. `/run print(Hekili.State.cooldown.global_cooldown.duration, C_Spell.GetSpellCooldown(29515).isActive)` right after a GCD ability: a duration near 1.5, `true`.
4. On a dummy for 30 s: Hekili shows recommendations (Battle Shout once the first swings have brought 10 rage: at 0 rage out of combat it is unaffordable through `floor(lo)`; then Rend and Heroic Strike); casts are not yet applied through the spec (Task 9), so rage after a cast is corrected only by the next rung. Report what the Primary display shows.

Fix what the user reports (each fix its own commit), then repeat. Continue only when the user confirms.


### Task 9: Apply through the spec, the across-reset feeds, the UNIT_AURA edit, zero allocation

**Files:**
- Modify (whole file): `VirtualState/Adapter.lua`, `VirtualState/spec/adapter_spec.lua`
- Create: `VirtualState/spec/alloc_spec.lua`
- Modify: `Events.lua` (the `UNIT_AURA` handler, lines 1265-1325 before Task 8's rewrite; locate it by its first line)

**Interfaces:**
- Consumes: everything above; Hekili's `state` (`reset`, `offset`, `delay`, `now`, `combat`, `cooldown`, `buff`, `debuff`, `gcd.execute`, `setCooldown`, `spendCharges`, `RunHandler`, `HandleEvent`, `AddToHistory`, `QueueEvent`, `RemoveSpellEvent`, `RemoveSpellEvents`, `swings`, `player.updated`, `target.updated`, the resources' `actual`/`fcount`), `ns.spendResources`, `class.abilities`/`auras`/`resources`/`talents`.
- Produces: the final `VS.Drain(cutoff)` (spec §5.2), `I.pinned` (the facade clock during an apply), `I.Apply(kind, a, t)`, the six feeds `I.feed.CastSucceeded`, `CastStart`, `CastFailed`, `ChannelStart`, `ChannelStop`, `Swing`; Snapshot's `drain=…ms casts=N` (G7).

- [ ] **Step 1: Write the failing specs**

`VirtualState/spec/adapter_spec.lua` (whole file; besides the instant cast it applies a hard cast (CAST_FINISH queued at the start and removed on success, the GCD at the start's offset, HandleEvent at the success) and a channel (CHANNEL_FINISH and its ticks queued, cooldown, handler and spend at the start, CHANNEL_STOP removing them), headless stand-ins for G8, which the Phase 1 kit cannot run in game):

```lua
-- VirtualState/spec/adapter_spec.lua: Adapter.lua against the fake spec provider (spec §3.6, §4.6, §5): the tracked
-- set from the registrations, the across-reset feeds, and Drain's apply through the spec (the read-before /
-- read-after diff as `modelled` samples, two full resets, the offset restored, `updated` marked). The apply against
-- the real `state` is verified in game (spec §11).
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("Adapter", function()
    local ns, VS, I, api, ctl, h, state, saved

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        saved = {}
        for _, k in ipairs({ "GetTime", "UnitGUID", "CreateFrame", "debugprofilestop" }) do
            saved[k] = rawget(_G, k) or false
        end
        _G.GetTime, _G.UnitGUID, _G.CreateFrame = api.GetTime, api.UnitGUID, api.CreateFrame
        _G.debugprofilestop = function()
            return os.clock() * 1000
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        h = fs.new(9)
        state = h.State
        fs.clock = api.GetTime
        ns.spendResources = fs.spend
        ns.ResourceRegenerates = function()
            return false
        end
        load.adapter(ns, h)
        VS.Start(api)
        VS.SpecChanged()
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        fs.clock = nil
    end)

    it("builds the tracked set from the registrations", function()
        local out = {}
        assert.are.equal(3, VS.Tracked("ability", out))
        assert.are.same({ fs.SHOUT, fs.STRIKE, fs.REND }, out)
        assert.are.equal(2, VS.Tracked("aura", out))
        assert.are.equal(1, VS.Tracked("resource", out))
        assert.are.same({ fs.RAGE }, out)
        assert.are.equal(2, VS.Tracked("unit", out))
        assert.are.equal(1, I.res.swing[1]) -- the mainhand swing model makes rage swing-paid
        assert.are.equal(h.VirtualState or VS, VS)
    end)

    it("feeds the cast history and the real queue from our own cast events, and asks for a cycle", function()
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
        assert.are.same({ "rend" }, state.history)
        assert.are.same({ "rend:CAST_FINISH" }, state.removed)
        assert.are.same({ "UNIT_SPELLCAST_SUCCEEDED" }, h.forced)
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2", fs.REND)
        assert.are.same({ "rend:CAST_FINISH", "rend:CAST_FINISH" }, state.removed)
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        assert.are.same({ 1, 3.6 }, { state.swings.mh_actual, state.swings.mh_projected })
    end)

    it("applies an instant cast through the spec: modelled rage, GCD and debuff, two resets, offset restored", function()
        ctl.usable[fs.REND] = { true, false } -- rage >= 10 (the poll's rung)
        ctl.now = 4
        VS.Drain(4)
        ctl.usable[fs.REND] = nil -- no answer after the cast
        ctl.now = 5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
        ctl.Tick(5.05)
        ctl.now = 5.1
        VS.Drain(5.1)
        assert.are.equal(2, state.resets)
        assert.are.same({ 0, 0 }, { state.offset, state.delay })
        assert.is_nil(I.pinned)
        assert.are.equal(5 - 0.01, state.combat) -- rend starts combat (R2)
        local rage = VS.Power(fs.RAGE, 5.1)
        assert.are.equal("modelled", rage.basis)
        assert.are.same({ 0, 0 }, { rage.est, rage.lo }) -- 10 seen at the poll, then 10 spent
        assert.are.same({ 0, 5 }, { rage.last.modelled.v, rage.last.modelled.t })
        local rend = VS.Aura("target", fs.REND, 5.1)
        assert.are.same({ 20, "modelled" }, { rend.est, rend.basis })
        assert.is_true(state.target.updated)
        assert.are.same({ 6.5, "modelled" }, { VS.Gcd(5.1).est, VS.Gcd(5.1).basis })
        assert.are.equal(1, I.drainCasts)
    end)

    -- A test ability on the fake spec, registered under its key and its spell ID.
    local function register(key, t)
        t.key, t.funcs = key, {}
        t.charges, t.recharge = 1, 0
        h.Class.abilities[key], h.Class.abilities[t.id] = t, t
    end

    local function near(want, got)
        assert.is_true(math.abs(want - got) < 1e-6, ("want %s, got %s"):format(want, got))
    end

    it("applies a hard cast at its finish: the GCD at the start's time, CAST_FINISH through HandleEvent", function()
        register("slam_test", { id = 1464, cast = 1.5, cooldown = 0, spend = 15, spendType = "rage" })
        VS.SpecChanged()
        I.ObsLog.Clear(I.log)
        ctl.now = 10
        ctl.casting = { 10000, 11500 }
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", 1464)
        assert.are.same({ "slam_test:CAST_FINISH" }, state.queue) -- the real queue's finish, as CLEU queued it
        ctl.Tick(10.05)
        ctl.now = 11.5
        ctl.casting = nil
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 1464)
        assert.are.same({ "slam_test:CAST_FINISH" }, state.removed) -- removed on success
        ctl.Tick(11.55)
        ctl.now = 11.6
        VS.Drain(11.6)
        assert.are.equal("slam_test", state.handled) -- HandleEvent ran the finish
        near(11.5, state.cooldown.slam_test.expires) -- at the success time
        near(11.5, VS.Gcd(11.6).est) -- the GCD began at the start (10 + 1.5)
        assert.are.equal("modelled", VS.Gcd(11.6).basis)
        assert.are.same({ 0, 0, 2 }, { state.offset, state.delay, state.resets })
    end)

    it("applies a channel at its start and feeds its finish and ticks; CHANNEL_STOP removes them", function()
        local ran = false
        register("drain_test", {
            id = 5555,
            channeled = true,
            cast = 3,
            tick_time = 1,
            cooldown = 10,
            handler = function()
                ran = true
            end,
        })
        VS.SpecChanged()
        I.ObsLog.Clear(I.log)
        ctl.now = 20
        ctl.channel = { 20000, 23000 }
        ctl.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4", 5555)
        assert.are.same(
            { "drain_test:CHANNEL_FINISH", "drain_test:CHANNEL_TICK", "drain_test:CHANNEL_TICK" },
            state.queue
        )
        ctl.Tick(20.05)
        ctl.now = 20.1
        VS.Drain(20.1)
        assert.is_true(ran) -- the handler
        local cd = VS.Cooldown(5555, 20.1)
        near(30, cd.est) -- the cooldown step at the channel's start
        assert.are.equal("modelled", cd.basis)
        assert.are.same({ 0, 0, 2 }, { state.offset, state.delay, state.resets })
        ctl.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-4", 5555)
        assert.are.same({ "drain_test:all" }, state.removed)
    end)

    it("runs no reset when the log holds no own cast", function()
        ctl.now = 3
        VS.Drain(3)
        assert.are.equal(0, state.resets)
    end)
end)
```
`VirtualState/spec/alloc_spec.lua` (spec §11 "Zero allocation"):
```lua
-- VirtualState/spec/alloc_spec.lua (spec §2, §11): 10,000 mixed events (PLAYER_SWING, UNIT_POWER_FREQUENT,
-- usability, own casts, UNIT_AURA) with a drain every tick against the fake spec, every accessor and every facade
-- policy called: VirtualState allocates nothing.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")
local alloc = require("VirtualState.spec.helpers.alloc")

describe("zero allocation", function()
    it("allocates nothing across events, drains, accessors and facade policies", function()
        local api, ctl = fake.new()
        ctl.now = 1
        local saved = {}
        local globals = {
            GetTime = api.GetTime,
            UnitGUID = api.UnitGUID,
            CreateFrame = api.CreateFrame,
            issecretvalue = api.issecretvalue,
            UnitIsDead = api.UnitIsDead,
            UnitCastingInfo = api.UnitCastingInfo,
            UnitChannelInfo = api.UnitChannelInfo,
            UnitPowerType = function()
                return fs.RAGE
            end,
            debugprofilestop = function()
                return 0
            end,
        }
        for k, v in pairs(globals) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        saved.C_Spell = rawget(_G, "C_Spell") or false
        _G.C_Spell = api.C_Spell
        local ns = load.module()
        local VS, I, Facade = ns.VirtualState, ns.VirtualStateInternal, ns.Facade
        local h = fs.new(9)
        local state = h.State
        function state:RemoveSpellEvent()
            return false
        end
        function state:AddToHistory() end
        function state:QueueEvent() end
        function h:ForceUpdate() end -- the fake records calls; Hekili's own only sets fields
        fs.clock = api.GetTime
        ns.spendResources = fs.spend
        ns.ResourceRegenerates = function()
            return false
        end
        load.adapter(ns, h)
        VS.Start(api)
        VS.SpecChanged()
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SHOUT, expirationTime = 1e9, applications = 0 }
        ctl.usable[fs.REND] = { true, false }
        ctl.cooldown[fs.REND] = { isActive = false, isOnGCD = true }
        ctl.Fire("PLAYER_REGEN_DISABLED")
        local POWER = "RAGE"
        local function step(i)
            ctl.now = ctl.now + 0.1
            local k = i % 5
            if k == 0 then
                ctl.Fire("PLAYER_SWING", 2.6, 0)
            elseif k == 1 then
                ctl.Fire("UNIT_POWER_FREQUENT", "player", POWER)
            elseif k == 2 then
                ctl.Fire("SPELL_UPDATE_USABLE")
            elseif k == 3 then
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast", fs.REND)
            else
                ctl.Fire("UNIT_AURA", "player")
            end
            ctl.Tick()
            VS.Drain(ctl.now)
            local t = ctl.now
            VS.Power(fs.RAGE, t)
            VS.Regen(fs.RAGE, t)
            VS.Cooldown(fs.REND, t)
            VS.Charges(fs.REND, t)
            VS.Gcd(t)
            VS.GcdInfo(t)
            VS.Aura("player", fs.SHOUT, t)
            VS.AuraAt("target", "HARMFUL", 1, t)
            VS.AuraByInstance("player", 1, t)
            VS.AuraGen("player")
            VS.Swing(1, t)
            VS.SwingSpeed(1, t)
            VS.LastSwing(1)
            VS.Haste(t)
            VS.SpellHaste(t)
            VS.Health("player", t)
            VS.HealthMax("player")
            VS.TTD("target", t)
            VS.Totem(1, t)
            VS.TotemFacts(1)
            VS.TargetCast(t)
            VS.TargetCastFacts()
            VS.Talent(12286)
            VS.TalentGen()
            VS.Stat("UnitStat", 1)
            VS.InCombat()
            VS.Moving()
            VS.CooldownLength(fs.REND)
            VS.Count.Enemies(t)
            VS.Count.WithAura(fs.REND, t)
            VS.Count.InRange(fs.REND, t)
            Facade.UnitPower("player", fs.RAGE)
            Facade.GetPowerRegenForPowerType(fs.RAGE)
            Facade.GetManaRegen()
            Facade.UnitHealth("player")
            Facade.UnitHealth("nameplate1")
            Facade.UnitHealthMax("target")
            Facade.UnitStat("player", 1)
            Facade.GetCombatRating(10)
            Facade.UnitDamage("player")
            Facade.GetHaste()
            Facade.GetMeleeHaste()
            Facade.UnitSpellHaste("player")
            Facade.UnitAttackSpeed("player")
            Facade.GetUnitSpeed("player")
            Facade.GetTotemInfo(1)
            Facade.C_UnitAuras.GetBuffDataByIndex("player", 1)
            Facade.C_UnitAuras.GetDebuffDataByIndex("target", 1)
            Facade.C_UnitAuras.GetPlayerAuraBySpellID(fs.SHOUT)
            Facade.C_UnitAuras.GetAuraDataByAuraInstanceID("player", 1)
            Facade.C_Spell.GetSpellCooldown(fs.REND)
            Facade.C_Spell.GetSpellCooldown(29515)
            Facade.C_Spell.GetSpellCharges(fs.REND)
            Facade.UnitCastingInfo("target")
            Facade.UnitChannelInfo("target")
            Facade.IsUsableSpell(fs.REND)
        end
        local ok, bytes = pcall(alloc.bytes, step, 10000)
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        fs.clock = nil
        assert.is_true(ok, tostring(bytes))
        assert.are.equal(0, bytes)
    end)
end)
```
Run: `~/src/TacoDogForever/.lua/bin/busted VirtualState/spec/adapter_spec.lua VirtualState/spec/alloc_spec.lua`
Expected: failures: no history or queue writes (`state.history` is `{}`), `state.resets` is 0 after a cast, the rage basis is not `modelled`.

- [ ] **Step 2: Rewrite `VirtualState/Adapter.lua`**

Everything Task 2's version had (Start, the handle, the urgent lane, the tracked-set builder) stays; it adds the read-before arrays, the feeds and the apply (spec §5.2 steps 1-5, §5.3, §4.6). Whole file:

```lua
-- VirtualState/Adapter.lua
-- VirtualState's glue to Hekili (spec §3.6, §4.6, §5): VirtualState.Start at PLAYER_LOGIN, the tracked set from the
-- active spec's registrations (SpecChanged), the across-reset feeds (cast history, the real queue's cast and
-- channel events, the swing fields), and Drain: the fold plus "apply through the spec", which runs each of our real
-- casts through Hekili's own registered functions on `state` and records what changed as `modelled` samples.
-- Loads after Core.lua. The apply follows Hekili's own simulation (Core.lua:1984-2045) and keeps Hekili's credits.

local addon, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local CAST_SUCCESS, CHANNEL_START = Obs.CastSuccess, Obs.ChannelStart

local Hekili = _G[addon]
local state, class = Hekili.State, Hekili.Class
local spendResources = ns.spendResources
local GetTime, UnitGUID, CreateFrame = GetTime, UnitGUID, CreateFrame
local debugprofilestop = debugprofilestop
local insert, sort = table.insert, table.sort

local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

-- The debug handle: /run print(Hekili.VirtualState.Snapshot())
Hekili.VirtualState = VS

-- The urgent lane (spec §4.4): shortens Hekili's wait before its next cycle; never interrupts one.
I.urgent = function(event)
    Hekili:ForceUpdate(event)
end

-- Start once, at PLAYER_LOGIN, on a frame of its own.
do
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        VS.Start(_G)
    end)
end

----------------------------------------------------------------------------------------------------------------------
-- The tracked set (spec §3.6, decision 8): what `state` reads, from the active spec's registrations.

local def = {
    abilities = {},
    abilityIds = {},
    abilitySlot = {},
    resources = {},
    auras = {},
    auraIds = {},
    talents = {},
    units = {},
}

local HANDS = { mainhand = 1, offhand = 2 }

-- The spell IDs of a registration: its `id`, then its `copy` IDs (rank order), positive numbers only.
local function idsOf(obj)
    local ids = {}
    if type(obj.id) == "number" and obj.id > 0 then
        ids[1] = obj.id
    end
    local copy = obj.copy
    if type(copy) == "number" and copy > 0 then
        ids[#ids + 1] = copy
    elseif type(copy) == "table" then
        for _, v in ipairs(copy) do
            if type(v) == "number" and v > 0 then
                ids[#ids + 1] = v
            end
        end
    end
    return ids
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" then
            keys[#keys + 1] = k
        end
    end
    sort(keys)
    return keys
end

local resourceKey, auraKey = {}, {}

local function buildDef()
    for _, list in pairs(def) do
        wipe(list)
    end
    wipe(resourceKey)
    wipe(auraKey)
    local slotByKey = {}
    for _, k in ipairs(sortedKeys(class.resources)) do
        local r = class.resources[k]
        local swing, value = 0, nil
        local model = r.state and r.state.regenModel
        if model then
            for _, m in pairs(model) do
                if m.swing and HANDS[m.swing] and swing == 0 then
                    swing, value = HANDS[m.swing], m.value
                end
            end
        end
        local d = {
            key = k,
            type = r.type,
            token = k:upper(),
            max = 100,
            rest = ns.ResourceRegenerates(k) and 100 or 0,
            swing = swing,
            swingValue = value,
        }
        insert(def.resources, d)
        resourceKey[#def.resources] = k
        slotByKey[k] = #def.resources
    end
    for _, k in ipairs(sortedKeys(class.abilities)) do
        local a = class.abilities[k]
        if a.key == k and k ~= "global_cooldown" then
            local ids = idsOf(a)
            if #ids > 0 then
                insert(def.abilities, a)
                def.abilityIds[#def.abilities] = ids
                local spends = rawget(a, "spend") ~= nil or a.funcs and a.funcs.spend ~= nil
                local slot = spends and slotByKey[a.spendType or class.primaryResource] or 0
                def.abilitySlot[#def.abilities] = slot
            end
        end
    end
    for _, id in ipairs(I.extra.abilities) do
        insert(def.abilities, { key = "track_" .. id, id = id, cooldown = 0 })
        def.abilityIds[#def.abilities] = { id }
        def.abilitySlot[#def.abilities] = 0
    end
    for _, k in ipairs(sortedKeys(class.auras)) do
        local a = class.auras[k]
        if a.key == k then
            local ids = idsOf(a)
            if #ids > 0 then
                insert(def.auras, a)
                def.auraIds[#def.auras] = ids
                auraKey[#def.auras] = k
            end
        end
    end
    for _, id in ipairs(I.extra.auras) do
        insert(def.auras, { key = "track_" .. id, id = id })
        def.auraIds[#def.auras] = { id }
    end
    local seen = {}
    for _, k in ipairs(sortedKeys(class.talents)) do
        local v = class.talents[k]
        if type(v) == "table" and type(v[2]) == "number" and not seen[v[2]] then
            seen[v[2]] = true
            insert(def.talents, { key = k, spell = v[2], max = v[3] or 1 })
        end
    end
    def.units[1], def.units[2] = "player", "target"
    for _, u in ipairs(I.extra.units) do
        insert(def.units, u)
    end
end

-- Read-before arrays for the apply (spec §5.3), sized at SpecChanged.
local resBefore, cdBefore, buffExp, buffApp, buffCnt, debuffExp, debuffApp, debuffCnt = {}, {}, {}, {}, {}, {}, {}, {}
local gcdBefore = 0

--- Rebuilds the tracked set from the active spec (decision 8). Called at the end of Hekili:SpecializationChanged,
--- after every registration. Allocates; SpecChanged only.
function VS.SpecChanged()
    buildDef()
    I.Build(def, GetTime())
    for i = 1, #def.resources do
        resBefore[i] = 0
    end
    for a = 1, #def.abilities do
        cdBefore[a] = 0
    end
    for j = 1, #def.auras do
        buffExp[j], buffApp[j], buffCnt[j], debuffExp[j], debuffApp[j], debuffCnt[j] = 0, 0, 0, 0, 0, 0
    end
end

----------------------------------------------------------------------------------------------------------------------
-- Feeding Hekili's across-reset caches (spec §4.6), synchronously in VirtualState's handlers, where CLEU did it.

local function abilityOf(a)
    local key = I.ab.key[a]
    return key, key and class.abilities[key]
end

I.feed.CastSucceeded = function(a, spellID, guid)
    local key, ability = abilityOf(a)
    if not ability then
        return
    end
    state:RemoveSpellEvent(key, true, "CAST_FINISH") -- as CLEU SPELL_CAST_SUCCESS (Events.lua:1613-1614)
    state:AddToHistory(key, guid) -- the only writer of the cast history (Events.lua:912-943)
end

I.feed.CastStart = function(a, start, finish, guid)
    local key, ability = abilityOf(a)
    if ability and not ability.channeled then
        -- as CLEU SPELL_CAST_START (Events.lua:1579); UNIT_SPELLCAST_DELAYED re-queues it (Events.lua:1076-1089)
        state:QueueEvent(key, start, finish, "CAST_FINISH", guid or UnitGUID("target"), true)
    end
end

I.feed.CastFailed = function(a)
    local key, ability = abilityOf(a)
    if not ability then
        return
    end
    -- as CLEU SPELL_CAST_FAILED (Events.lua:1603-1606)
    if state:RemoveSpellEvent(key, true, "CAST_FINISH") and ability.isProjectile then
        state:RemoveSpellEvent(key, true, "PROJECTILE_IMPACT", true)
    end
end

I.feed.ChannelStart = function(a, start, finish, guid)
    local key, ability = abilityOf(a)
    if not ability then
        return
    end
    -- as CLEU SPELL_CAST_SUCCESS of a channel (Events.lua:1627-1635)
    state:QueueEvent(key, start, finish, "CHANNEL_FINISH", guid, true)
    local tickTime = ability.tick_time or (ability.aura and class.auras[ability.aura].tick_time)
    if tickTime and tickTime > 0 then
        local tick = tickTime
        while start + tick < finish do
            state:QueueEvent(key, start, start + tick, "CHANNEL_TICK", guid, true)
            tick = tick + tickTime
        end
    end
end

I.feed.ChannelStop = function(a)
    local key, ability = abilityOf(a)
    if ability then
        state:RemoveSpellEvents(key, true) -- ticks, finish, impacts (Events.lua:1609-1610)
    end
end

-- The swing fields the dead CLEU SWING_* branch wrote (Events.lua:1684-1699), read by the swing regen models.
I.feed.Swing = function(hand, t, duration)
    local sw = state.swings
    if hand == 1 then
        sw.mh_actual, sw.mh_speed, sw.mh_projected = t, duration, t + duration
    else
        sw.oh_actual, sw.oh_speed, sw.oh_projected = t, duration, t + duration
    end
end

----------------------------------------------------------------------------------------------------------------------
-- Apply through the spec (spec §5.2, §5.3).

local finishEvent = { type = "CAST_FINISH", action = "", time = 0, start = 0 }

local function field(t, k)
    return t and rawget(t, k) or 0
end

-- Step 3.5: the tracked fields before the apply. Each tracked resource's `actual` is set to the belief at the cast
-- first, so a spend is never clipped at 0 by a stale `actual` (the cast succeeded: the game had the cost).
local function readBefore(t)
    local R = I.res
    for r = 1, R.n do
        local res = rawget(state, resourceKey[r])
        if res then
            local v = VS.Power(R.type[r], t).est
            res.actual, res.fcount = v, 0
            resBefore[r] = v
        end
    end
    local A, cooldown = I.ab, state.cooldown
    for a = 1, A.n do
        cdBefore[a] = field(rawget(cooldown, A.key[a]), "expires")
    end
    gcdBefore = field(rawget(cooldown, "global_cooldown"), "expires")
    local buff, debuff = state.buff, state.debuff
    for j = 1, I.auras.nAura do
        local k = auraKey[j]
        local b, d = k and rawget(buff, k), k and rawget(debuff, k)
        buffExp[j], buffApp[j], buffCnt[j] = field(b, "expires"), field(b, "applied"), field(b, "count")
        debuffExp[j], debuffApp[j], debuffCnt[j] = field(d, "expires"), field(d, "applied"), field(d, "count")
    end
end

-- Step 3.7: what changed, as `modelled` samples at t.
local function readAfter(t, kind)
    local R = I.res
    for r = 1, R.n do
        local res = rawget(state, resourceKey[r])
        if res then
            local delta = res.actual - resBefore[r]
            if delta > 1e-6 or delta < -1e-6 then
                I.ResourceShift(r, delta, t, kind)
            end
        end
    end
    local A, cooldown = I.ab, state.cooldown
    for a = 1, A.n do
        local cd = rawget(cooldown, A.key[a])
        local e = field(cd, "expires")
        if e ~= cdBefore[a] then
            if A.ch[a] then
                I.ChargesModel(a, field(cd, "charge"), e, t, kind)
            else
                I.CooldownModel(a, e, field(cd, "duration"), t, kind)
            end
        end
    end
    local g = field(rawget(cooldown, "global_cooldown"), "expires")
    if g ~= gcdBefore then
        I.GcdModel(g, t, kind)
    end
    local buff, debuff = state.buff, state.debuff
    for j = 1, I.auras.nAura do
        local k = auraKey[j]
        if k then
            local b, d = rawget(buff, k), rawget(debuff, k)
            local be, de = field(b, "expires"), field(d, "expires")
            if be ~= buffExp[j] or field(b, "count") ~= buffCnt[j] then
                I.AuraModel(1, j, field(b, "applied"), be, field(b, "count"), t, kind, false)
            end
            if (de ~= debuffExp[j] or field(d, "count") ~= debuffCnt[j]) and I.auras.n >= 2 then
                I.AuraModel(2, j, field(d, "applied"), de, field(d, "count"), t, kind, true)
            end
        end
    end
end

local function gcdStep(ability)
    if ability.gcd ~= "off" and state.cooldown.global_cooldown.remains == 0 then
        state.setCooldown("global_cooldown", state.gcd.execute)
    end
end

local function cooldownStep(key, ability)
    if ability.charges and ability.charges > 1 and ability.recharge > 0 then
        state.spendCharges(key, 1)
    elseif ability.cooldown > 0 then
        state.setCooldown(key, ability.cooldown)
    end
end

-- Steps 3.3-3.7 for one own cast of ability index `a` at t.
local function apply(kind, a, t)
    local key = I.ab.key[a]
    local ability = key and class.abilities[key]
    if not ability or not ability.id or ability.id <= 0 then
        return false
    end
    -- 3.3: combat start (R2), the value PLAYER_REGEN_DISABLED writes (Events.lua:856-863)
    if ability.startsCombat and state.combat == 0 then
        state.combat = t - 0.01
    end
    readBefore(t)
    local now = state.now
    if kind == CHANNEL_START then
        state.offset, state.delay = t - now, 0
        gcdStep(ability)
        cooldownStep(key, ability)
        state:RunHandler(key) -- takes the channel path (State.lua:6135-6137)
        spendResources(key)
    elseif (ability.cast or 0) > 0 and not ability.channeled then
        -- a hard cast, at its finish: the GCD at its start, then the CAST_FINISH event at the finish
        local started = I.ab.castStartT[a]
        if started > 0 and started < t then
            state.offset, state.delay = started - now, 0
            gcdStep(ability)
        end
        state.offset, state.delay = t - now, 0
        finishEvent.action, finishEvent.time, finishEvent.start = key, t, started
        state:HandleEvent(finishEvent) -- charges/cooldown, spend, handler (State.lua:5921-5953)
    else
        state.offset, state.delay = t - now, 0
        gcdStep(ability)
        cooldownStep(key, ability)
        spendResources(key)
        state:RunHandler(key)
    end
    readAfter(t, kind)
    return true
end
I.Apply = apply

--- The fold plus apply through the spec (spec §5.2), called only from Hekili.Update after its guards. Allocates
--- nothing beyond what Hekili's own reset and handlers allocate.
---@param cutoff number GetTime() at the drain's entry
function VS.Drain(cutoff)
    if not I.built then
        return
    end
    local t0 = debugprofilestop()
    local genP, genT = VS.AuraGen("player"), VS.AuraGen("target")
    S.RunPolls(cutoff) -- step 1
    local applied, reset = 0, false
    while true do
        local kind, a, t = I.Fold(cutoff, true) -- steps 2 and 3.8
        if not kind then
            break
        end
        I.pinned = t -- 3.1: the facade answers at the cast's time (R1)
        if not reset then
            state.reset() -- 3.2: once, full ("Primary", State.lua:6181-6184)
            reset = true
        end
        if apply(kind, a, t) then
            applied = applied + 1
        end
    end
    -- 4: restore, unpin, settle, and one more full reset when anything was applied (R2, R3)
    state.offset, state.delay = 0, 0
    I.pinned = nil
    I.Settle(cutoff)
    if reset then
        state.reset()
    end
    -- 5: Hekili rescans a unit's auras when its believed set moved (G1)
    if VS.AuraGen("player") ~= genP then
        state.player.updated = true
    end
    if VS.AuraGen("target") ~= genT then
        state.target.updated = true
    end
    I.drainMs, I.drainCasts = debugprofilestop() - t0, applied
end
```
- [ ] **Step 3: The `UNIT_AURA` handler stops reading the secret payload (spec §10, G1)**

In `Events.lua`, replace the whole `UNIT_AURA` registration, from its first line `    RegisterUnitEvent( "UNIT_AURA", "player", "target", function( event, unit, data )` down to, not including, `    RegisterEvent( "PLAYER_TARGET_CHANGED", function( event )`, that is:

```lua
    RegisterUnitEvent( "UNIT_AURA", "player", "target", function( event, unit, data )
        local isPlayer = ( unit == "player" )
        instanceDB = isPlayer and playerInstances or targetInstances

        if data.isFullUpdate then
            wipe( instanceDB )

            ForEachAura( unit, "HELPFUL", nil, StoreInstanceInfo, true )
            ForEachAura( unit, "HARMFUL", nil, StoreInstanceInfo, true )

            state[ unit ].updated = true
            Hekili:ForceUpdate( "UNIT_AURA_FULL", true )
            return
        end

        local forceUpdateNeeded = false

        if data.addedAuras and #data.addedAuras > 0 then
            for _, aura in ipairs( data.addedAuras ) do
                local id = aura.spellId
                local model = class.auras[ id ]

                local ofConcern = aura.isBossAura or aura.isStealable or model and ( model.shared or model.used and aura.isFromPlayerOrPlayerPet )
                instanceDB[ aura.auraInstanceID ] = ofConcern

                if ofConcern then
                    forceUpdateNeeded = true
                end
            end
        end

        if data.updatedAuraInstanceIDs and #data.updatedAuraInstanceIDs > 0 then
            for _, instance in ipairs( data.updatedAuraInstanceIDs ) do
                local aura = GetAuraDataByAuraInstanceID( unit, instance )
                local ofConcern = false

                if aura then
                    local id = aura.spellId
                    local model = class.auras[ id ]

                    ofConcern = aura.isBossAura or aura.isStealable or model and ( model.shared or model.used and aura.isFromPlayerOrPlayerPet )
                    instanceDB[ instance ] = ofConcern
                end

                if ofConcern then
                    forceUpdateNeeded = true
                end
            end
        end

        if data.removedAuraInstanceIDs and #data.removedAuraInstanceIDs > 0 then
            for _, instance in ipairs( data.removedAuraInstanceIDs ) do
                if instanceDB[ instance ] then forceUpdateNeeded = true end
                instanceDB[ instance ] = nil
            end
        end

        state[ unit ].updated = true

        if forceUpdateNeeded then Hekili:ForceUpdate( "UNIT_AURA_ITER" ) end
    end )

```
with:
```lua
    -- Forever: the payload is secret in combat (a boolean test of data.isFullUpdate raises), so the handler no longer
    -- reads it; VirtualState's drain sets state[ unit ].updated when that unit's believed auras changed (spec G1).
    RegisterUnitEvent( "UNIT_AURA", "player", "target", function( event, unit )
        Hekili:ForceUpdate( event )
    end )

```
The locals above it (`playerInstances`, `targetInstances`, `instanceDB`, `StoreInstanceInfo`, `GetAuraDataByAuraInstanceID`, `ForEachAura`) stay: `PLAYER_TARGET_CHANGED` still uses them, and Phase 3 §10 retires this edit by restoring a plain payload.

- [ ] **Step 4: Run the specs to see them pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `73 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [73 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 42 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [no problems found]
git status --short | grep '\.lua$' | awk '{print $2}' | xargs -r -n1 luac5.1 -p   # [no output]
```
- [ ] **Step 6: Commit**
```bash
git add Events.lua VirtualState
git commit -m "feat(virtualstate): drain applies our casts through the spec; across-reset feeds; UNIT_AURA no longer reads its payload; zero-allocation spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: The Phase 1 exit criterion (CHECKPOINT 4) and the risk checks

**Files:**
- No code. Fixes the user's results call for are separate commits, each with the verification block.

**Interfaces:**
- Consumes: the whole branch.
- Produces: the user's confirmation of the exit criterion (spec §11, `docs/virtualstate-kickoff-prompt.md`), and the G2, G3, G4, G7, G8 observations for the Phase 2 investigation (which takes "the Snapshot logs, the G2 order probe and the G7 drain cost" as inputs).

- [ ] **Step 1: Verify and push**

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [73 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 42 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [no problems found]
git status --short | grep '\.lua$' | awk '{print $2}' | xargs -r -n1 luac5.1 -p   # [no output]
```
Then `git push origin virtualstate-phase1` and `git -C ~/src/hekili checkout --detach virtualstate-phase1`.

- [ ] **Step 2: CHECKPOINT 4 (the Phase 1 exit criterion): stop and ask the user to run the following in game**

On the Forever Warrior:

1. `/reload`. Expected: no Lua error and no popup.
2. Out of combat: `/run print(Hekili.VirtualState.Snapshot())`. Expected: `class=WARRIOR`; the `talent … rank=` lines (the talent ranks); `power rage est=0.00 … basis=default`.
3. On a training dummy for 60 s, playing the recommendations. Then, still in combat:
   - `/run print(Hekili.VirtualState.Snapshot())` once around 20 s and once around 60 s. Expected across the two: `power rage … basis=pinned` in one and `basis=modelled` in the other (it alternates), `hi - lo` at most 15, and the interval containing the rage bar's value at that moment (the user reads the bar as they press Enter);
   - `swing main … basis=observed` and `swing speed main est=` equal to the weapon's speed from its tooltip ±0.01;
   - `/run local r=Hekili.VirtualState.Aura("target",772,GetTime()) print("rend", r and r.est-GetTime())` with the target frame's Rend timer visible: within 0.2 s of the timer's remaining time (for a higher Rend rank, use its spell ID from `/run print(Hekili.VirtualState.Snapshot())`'s `ability rend qid=`);
   - Hekili recommends spenders: the Primary display shows Rend when it is down and Heroic Strike at 30 rage or more.
4. G7 (drain cost, spec §5.4): from the snapshots, the `drain=…ms casts=N` line right after a cast. Expected about 1-2 ms with `casts=1`.
5. G2 (handler order): before pulling, run these two lines (each under the 255-character chat limit):
   ```
   /run VSG=function(_,e) if e=="UNIT_SPELLCAST_SUCCEEDED" then local s=debugstack(2,4,0) print(format("%.3f",debugprofilestop()),s:find("Adapter.lua") and "VS" or s:find("Events.lua") and "HK" or s) end end
   /run hooksecurefunc(Hekili,"ForceUpdate",VSG)
   ```
   then cast Rend once. Each handler's `ForceUpdate` call is stamped with `debugprofilestop()` (spec G2) and named by the four stack lines above the hook: `HK` (Hekili's handler in Events.lua) or `VS` (VirtualState's urgent lane in Adapter.lua, called from VirtualState's handler); a line that prints a raw stack instead means neither file was in those four lines: paste it. Expected: two lines, one `HK` and one `VS`; their order is the answer. If Hekili's prints first, the one-cycle staleness of spec §8 is accepted (spec G2).
6. G3 (no double-counted rage): in combat, right after a white swing, `/run print(Hekili.State.rage.current, Hekili.VirtualState.Power(1,GetTime()).est)`. Expected: the two within one swing's rage (about 4.5 x the weapon speed) of each other.
7. G4 (passive near costs): note any moment the bar shows rage at or above 15 while Heroic Strike is not recommended at 30+; `power rage lo=… est=…` in the snapshot then tells whether `lo` (the facade's answer) held it back. Action (spec G4, "choose lo or est per resource as a facade constant"): when `lo` < 30 ≤ `est` held Heroic Strike back while the game showed it usable, change the `UnitPower` policy's return line in `VirtualState/Facade.lua`, `    return floor(VS.Power(powerType, now()).lo) -- lo never over-promises a spender (feasibility §D.3)`, to `    local b = VS.Power(powerType, now())` followed by `    return floor(powerType == 1 and b.est or b.lo) -- rage answers est (G4, CHECKPOINT 4); others lo`, as its own commit with the verification block, and repeat item 3. Otherwise keep `lo`.
8. G8 (realQueue against back-dated applies): the Phase 1 kit has no hard cast (Rend, Heroic Strike and Battle Shout are instants), so G8 cannot be exercised in game here. The hard-cast and channel apply paths and their feeds are covered headless by Task 9's adapter_spec cases. Record "G8 not exercised in game: carries to the first class file with a hard cast (for a Warrior, Slam), whose checkpoint runs it".

9. PLAYER_SWING on a Heroic Strike swing (the assumption behind skipping the 0.9 anchor, see "Deliberately not built"): before the pull, run these two lines:
   ```
   /run VSN,VSH=0,0 VSC=function(_,e,a,b,c) if e=="PLAYER_SWING" then if b==0 then VSN=VSN+1 VSL=GetTime() VSF=VSF or VSL end elseif C_Spell.GetSpellName(c)=="Heroic Strike" then VSH=VSH+1 end end
   /run local f=CreateFrame("Frame") f:RegisterEvent("PLAYER_SWING") f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED","player") f:SetScript("OnEvent",VSC)
   ```
   After the 60 s, out of combat: `/run print("swings",VSN,"expected",floor((VSL-VSF)/UnitAttackSpeed("player")+1.5),"heroic strikes",VSH)`. Expected: `swings` within 2 of `expected` with `heroic strikes` above 0: `PLAYER_SWING` fires on Heroic Strike swings too, and the assumption holds. If `swings` falls short of `expected` by about the `heroic strikes` count, the assumption is false: record it in the task report and add "the 0.9 on-next-swing strike anchor (spec §6.4)" to the follow-up list; no Phase 1 code changes.

Fix what the user reports (each fix its own commit, with the verification block; push after each green fix), then repeat the checkpoint. Phase 1 is complete when the user confirms items 1-3. Then restore the main checkout: `git -C ~/src/hekili checkout forever`. Do not merge.

