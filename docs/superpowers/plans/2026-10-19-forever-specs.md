# Per-Spec Structure on Forever Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Run after Day 5 merges into `forever` (Hunter pack, CONTENT_API 5) and before Day 6.** Branch from that `forever`.
> Every line number below is from `forever` 149d286f and may have drifted by Day 5: grep for the quoted anchor text.

**Goal:** On Forever, every class pack shows one spec per talent tree (its own priority, settings and preferences, as
upstream Hekili does), the active spec is the character's stored choice, else the dominant talent tree, and packs
declare a class instead of hardcoding the client's pseudo-spec id.

**Architecture:** A pack calls `Hekili:NewClass(token, { specs = {...} })`: the core builds one *kit* (the class's
abilities, auras, talents and hooks, registered once) and one spec object per entry whose missing fields fall through
to the kit (`setmetatable(spec, { __index = kit })`), with ids of our own (`100000 + client class id x 10 + slot`). The
pure rules (ids, tree points, the pick, the hint, share keys, the migration) live in a new
`Engine/Schema/Trees.lua`; `SpecializationChanged` asks it which spec is active, merges only that spec plus `all`, and
after the talent walk settles the choice (stores the dominant tree once, migrates the legacy profile once). Options
lists the kit's specs; packs bind to a spec by a share key (`"WARRIOR:arms"`) that export strings carry.

**Tech Stack:** Lua 5.1 (WoW), busted headless harness (`tests/Game/harness/headless.lua`, `tests/Forever/helpers/engine.lua`),
`tools/make_pack.lua`, `wowdb talents <CLASS>` for the talent trees.

**Spec:** the approved outline (user decisions 2026-10-19, binding), reproduced in "Decisions" below; the per-pack gate
and the pack checklist of `docs/superpowers/plans/2026-10-18-class-completion.md`.

## Decisions (user, 2026-10-19; binding)
- Active spec: the stored choice for the character wins; when none is stored, the dominant talent tree (most points)
  is selected and stored. A dropdown on the class page overrides it. A respec does not silently switch; when the
  dominant tree differs from the stored choice, the class page says so (the first-login case stores the dominant).
- Spec set: every class gets its three talent trees. Healing trees appear as "no priorities on Forever" (engine idle,
  no displays) so a Holy paladin sees why nothing shows.
- Timing: after Day 5 merges, before Day 6, so Mage, Warlock, Priest and Elemental are written per-spec from the start
  and the five existing packs (Warrior, Druid, Rogue, Paladin, Shaman) plus Day 5's Hunter are converted once.
- Migration: existing per-class settings and preferences are copied to every spec of the class once; pack selections
  map 1:1 where the pack name is a tree (Arms->Arms...), the previous class-level choice otherwise.

## Resolved open items (plan writer)
- **Id scheme.** `id = 100000 + classID * 10 + slot`, `classID` the client's `UnitClass("player")` third return (fixed
  by Blizzard), `slot` 0 for the kit and 1..n for the specs in the pack's `NewClass` order. Never 1483-1491, never a
  retail id (all < 1500). No class name enters the core: the class id comes from the client.

  | Class (id) | kit | specs |
  |---|---|---|
  | Warrior (1) | 100010 | Arms 100011, Fury 100012, Protection 100013 |
  | Paladin (2) | 100020 | Holy 100021 (no priorities), Protection 100022, Retribution 100023 |
  | Hunter (3) | 100030 | Beast Mastery 100031, Marksmanship 100032, Survival 100033 |
  | Rogue (4) | 100040 | Assassination 100041, Combat 100042, Subtlety 100043 |
  | Priest (5, Day 7) | 100050 | Discipline 100051 (no priorities), Holy 100052 (the Smite pack), Shadow 100053 |
  | Shaman (7) | 100070 | Elemental 100071 (no priorities until Day 7), Enhancement 100072, Restoration 100073 (no priorities) |
  | Mage (8, Day 6) | 100080 | Arcane 100081, Fire 100082, Frost 100083 |
  | Warlock (9, Day 7) | 100090 | Affliction 100091, Demonology 100092, Destruction 100093 |
  | Druid (11) | 100110 | Balance 100111, Feral 100112, Guardian 100113, Restoration 100114 (no priorities) |

  The Druid gets four specs: Feral and Guardian share the Feral Combat tree (tree 2); the dominant tree 2 picks Feral
  (the first spec on it), Guardian is chosen by the dropdown or `/hekili spec guardian`.
- **`NewSpecialization`.** Stays only for the core's spec 0 (`all`). Content uses `NewClass`; Task 6 removes the
  Forever pseudo-spec branch and the Constants rows, and `tests/boundary_spec.lua`'s content allowlist swaps
  `NewSpecialization` for `NewClass`. No plug-in pack needs the old call (all content packs are ours).
- **Talent tree per talent.** Read from the pack's own DB2-derived data, no facade change: the first field of each
  `RegisterTalents` entry (`{ node, spell, max }`, "node (unused on Forever)") becomes the talent tree index (1-3, 0
  unknown). The facade already answers each talent's rank from the C_Traits walk (`GetTalentInfoByID`'s 12th return,
  `Game/API/Facade.lua` "GetTalentInfoByID"), so the dominant tree is the sum of ranks per tree over the kit's
  registered talents. That needs every talent of all three trees registered: Warrior and Druid already register them
  (grouped by tree in comments); Rogue, Paladin, Shaman and Hunter get full blocks from `wowdb talents <CLASS>` in
  Task 6. Forever-only talents not in the DB2 stay tree 0 (counted nowhere). The Warrior export
  (`docs/research/2026-10-16-warrior-talent-dump.md`, and the trait walk's single tree 1117 with three posX column
  bands) confirms one C_Traits tree per class, so the walk itself cannot give the tab; the column bands are not used:
  the DB2's `Talent.TabID` and `TalentTab.OrderIndex` give every class's tab membership and order (see Spec icons).

## Global Constraints
- `make check` green before every commit. Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Gate lines identical except timings.** Before Task 1, record the base (Step 0 of Task 1). After every task that
  touches a pack, the harness or `SpecializationChanged`, every ` solo: ` line from `make check` (3 fights) and from
  `make test-druid test-rogue test-paladin test-shaman test-hunter` (20 fights) is byte-identical to the base once the
  `cpu mean X p99 Y ms; ` field is removed. The base at the time of writing: Arms 0.977/0.949/0.977 (3-fight) and 0.960
  (20), Feral 0.974, Guardian 0.718 (reported), Balance 0.992, Retribution 0.988, Protection 0.957, Combat 0.978,
  Assassination 0.999, Subtlety 0.950, Enhancement 0.999, plus Day 5's Beast Mastery, Marksmanship and Survival lines;
  the recorded file wins over these numbers. A changed line is a bug: stop and use superpowers:systematic-debugging;
  never re-baseline.
- Fixtures untouched: `tests/Forever/fixtures/classic_draw.lua`, `timeline_draw.lua`, `arms_recs_seeds1-3.lua`,
  `classic_options.lua`.
- Boundary (`tests/boundary_spec.lua`): no class, spell, aura, talent or form name in `src/Hekili/Game/**`,
  `src/Hekili/Engine/Schema/**` (including the new `Trees.lua`) or `tests/Game/harness/**`. Class names, spec keys and
  ids live in the packs and `tests/Forever/**`.
- Layering (`tools/check_engine_reads.sh`): Engine code never names the AceDB profile (`Hekili.DB`, `.profile`): it
  reads `Hekili.Engine.settings`. Options, ChatCommands and UI never read `class.`/`state.`/`Hekili.Class`: they go
  through `Hekili.Engine.Registry` and `Hekili.Engine.Output.status`.
- Simulation unchanged: `state.role` and `state.spec.primaryStat` keep coming from the client's pseudo-spec answer
  (the harness answers DAMAGER/strength for every class). A spec's `role` is display metadata only. Changing that is a
  separate, gated behaviour change.
- No new tables, closures or string building in recurring paths (Update, UNIT_COMBAT, polls). Spec changes, talent
  events, options and chat are not recurring.
- The content surface changes (`NewClass`, the `RegisterTalents` tree field, `RegisterSetting`'s spec keys): Task 1
  bumps `CONTENT_API` 5 -> 6 in `src/Hekili/Engine/Content.lua` and every content TOC's `## X-Hekili-ContentAPI`
  together (`tests/Forever/content_spec.lua`).
- StyLua formats our files (`Trees.lua`, `Registry.lua`, `Settings.lua`, `Content.lua`, packs, tests); upstream files
  (`Spec.lua`, `Options/`, `UI/`, `Engine/Sim/`, `Snapshot.lua`) keep upstream spacing (`.styluaignore`).
- Credits: no new third-party code. Spec icons are FileDataIDs checked with the `wow` MCP icon search (listed below).

## Review Focus
1. **A character with no talents (level < 10) gets a spec and no error**: the first supported spec, nothing stored,
   and the first points spent choose and store the dominant tree. Pinned by Task 2 "no talents" (`spec_choice_spec`)
   and the pure `PickSpec` cases in Task 1 (`trees_spec`).
2. **The stored choice survives /reload and a respec, and the hint does not loop**: a second boot from the first one's
   `HekiliDB` keeps the choice; a talent event with a stored choice runs no spec change; `GetSpecHint` names the
   dominant spec. Pinned by Task 2 "stored choice" (`spec_choice_spec`).
3. **Migration is idempotent and never drops a pack selection or a threshold**: legacy `specs[1491]` thresholds land
   in every Warrior spec, a custom pack choice stays the active spec's, a second pass changes nothing. Pinned by Task 4
   (`trees_spec` "MigrateTrees", `spec_choice_spec` "migration").
4. **A healing tree leaves the engine idle with no "no modules loaded" warning**: Holy/Restoration specs have no
   package, `enabled = false`, `class.initialized` true, a cycle raises nothing, and their options node is the notice.
   Pinned by Task 5 (Druid Restoration) and Task 6 (Paladin Holy) in `spec_choice_spec`.
5. **Every solo gate line identical except timings after the id change.** Pinned by the gate step of Tasks 2, 3, 5
   and 6 (diff against `/tmp/specs/solo-base.txt`).

---

## File map
- Create: `src/Hekili/Engine/Schema/Trees.lua`, `tests/Forever/trees_spec.lua`, `tests/Forever/spec_choice_spec.lua`.
- Modify (core): `src/Hekili/Hekili.toc` (Trees.lua), `src/Hekili/Hekili.lua` (Class.kit, Class.specByShare),
  `src/Hekili/Engine/Schema/Spec.lua` (NewClass, mixin, SpecializationChanged, SetSpecChoice, GetSpecHint, PEW),
  `src/Hekili/Engine/Registry.lua` (Kit, SpecFromShare, SpecShareKey), `src/Hekili/Engine/Settings.lua`
  (specChoice, specMigrated), `src/Hekili/Engine/Content.lua` (CONTENT_API 6), `src/Hekili/Engine/Sim/Events.lua`
  (CheckForTalentUpdate), `src/Hekili/Engine/Sim/Constants.lua` (Task 6: Forever rows removed),
  `src/Hekili/Engine/Snapshot.lua` (spec line), `src/Hekili/UI/UI.lua` (display visibility),
  `src/Hekili/Options/Options.lua` (defaults, EmbedSpecOptions, GetCurrentSpec, Priorities order, packSpec label,
  Serialize/DeserializeActionPack), `src/Hekili/Options/ChatCommands.lua` (`/hekili spec`).
- Modify (packs): `src/Hekili_{Warrior,Druid,Rogue,Paladin,Shaman,Hunter}/<Class>.lua` and `APLs/packs.lua`, every
  content TOC's ContentAPI, `tools/make_pack.lua`.
- Modify (tests): `tests/Game/harness/headless.lua`, `tests/Forever/helpers/{engine,load_warrior,load_druid}.lua`, the
  worlds `tests/Forever/helpers/{warrior,druid_loop,rogue,paladin,shaman,hunter}_world.lua`,
  `tests/boundary_spec.lua`, `tests/Forever/{content,settings,make_pack,packs,warrior,fury,druid,engine_load,rogue,paladin,shaman,hunter,output,registry}_spec.lua` as each task says.
- Docs (Task 7): `docs/dev/layout.md`, `docs/dev/architecture.md` §3 and §6 (this repo's pack author guide; there is
  no `docs/class-packs/` in the Hekili fork), `docs/superpowers/plans/2026-10-18-class-completion.md` Days 6-7.

## Spec icons and tab order (the Forever DB2, authoritative)
Every spec's icon is its talent tab's own icon, `TalentTab.SpellIconID` in the Forever DB2 (`wowdb "select Name_lang,
OrderIndex, SpellIconID from TalentTab where ClassMask = <2^(classID-1)> order by OrderIndex"`), so the options tree
shows what the client's talent frame shows. FileDataIDs (icon names from `wow_icon_search`), in the client's tab order
(`OrderIndex` 0, 1, 2 = tree 1, 2, 3; `wowdb talents CLASS` lists tabs in that order):
- Warrior: Arms 132292 (ability_rogue_eviscerate), Fury 132347 (ability_warrior_innerrage), Protection 134952 (inv_shield_06).
- Paladin: Holy 135920 (spell_holy_holybolt), Protection 135893 (spell_holy_devotionaura), Retribution 135873 (spell_holy_auraoflight).
- Hunter: Beast Mastery 132164 (ability_hunter_beasttaming), Marksmanship 132222 (ability_marksmanship), Survival 132215 (ability_hunter_swiftstrike).
- Rogue: Assassination 132292 (ability_rogue_eviscerate), Combat 132090 (ability_backstab), Subtlety 132320 (ability_stealth).
- Priest: Discipline 135987 (spell_holy_wordfortitude), Holy 237542 (spell_holy_guardianspirit), Shadow 136207 (spell_shadow_shadowwordpain).
- Shaman: Elemental 136048 (spell_nature_lightning), Enhancement 136051 (spell_nature_lightningshield), Restoration 136052 (spell_nature_magicimmunity).
- Mage: Arcane 135932 (spell_holy_magicalsentry), Fire 135810 (spell_fire_firebolt02), Frost 135846 (spell_frost_frostbolt02).
- Warlock: Affliction 136145 (spell_shadow_deathcoil), Demonology 136172 (spell_shadow_metamorphosis), Destruction 136186 (spell_shadow_rainoffire).
- Druid: Balance 136096 (spell_nature_starfall), Feral Combat 132276 (ability_racial_bearform), Restoration 136041
  (spell_nature_healingtouch). The two specs on the Feral Combat tree split the art: Feral 132115 (ability_druid_catform),
  Guardian 132276 (the tab's bear).

The talent-to-tab link is `Talent.TabID` and the tab order `TalentTab.OrderIndex`, both in the DB2; no client read and
no assumption about the C_Traits layout is needed for the dominant tree, for any class.

## The gate commands (every task that says "Gate")
```bash
mkdir -p /tmp/specs
make check 2>&1 | tee /tmp/specs/check-$TASK.log | grep ' solo: fights=' \
  | sed -E 's/cpu mean [0-9.]+ p99 [0-9.]+ ms; //' | sort > /tmp/specs/solo-$TASK.txt
make test-druid test-rogue test-paladin test-shaman test-hunter 2>&1 | grep ' solo: fights=' \
  | sed -E 's/cpu mean [0-9.]+ p99 [0-9.]+ ms; //' | sort >> /tmp/specs/solo-$TASK.txt
diff /tmp/specs/solo-base.txt /tmp/specs/solo-$TASK.txt && echo "gate lines identical"
```
Expected: `make check` exit 0 and `gate lines identical`.

---

### Task 1: core registry: ids, NewClass, the kit's shared settings (M)

**Files:**
- Create: `src/Hekili/Engine/Schema/Trees.lua`, `tests/Forever/trees_spec.lua`
- Modify: `src/Hekili/Hekili.toc` (before `Engine\Schema\Spec.lua`), `src/Hekili/Hekili.lua` (`Hekili.Class`),
  `src/Hekili/Engine/Schema/Spec.lua` (NewSpecialization ~l.1456, RegisterSetting ~l.1285, RegisterOptions ~l.1151,
  RegisterEvent/RegisterUnitEvent ~l.1160, RegisterAura's class copy ~l.398), `src/Hekili/Engine/Registry.lua`,
  `src/Hekili/Engine/Content.lua`, every `src/Hekili_*/Hekili_*.toc`, `tests/Forever/helpers/engine.lua`,
  `tests/Forever/content_spec.lua`, `tests/boundary_spec.lua`

**Interfaces:**
- Produces (Trees.lua, on `ns`): `ns.TreeSpecID(classID, slot) -> number`; `ns.TreePoints(talents, rankOf) -> {p1,p2,p3}`
  (preallocated, reused); `ns.DominantTree(points) -> 1|2|3|nil`; `ns.PickSpec(kit, storedKey, rankOf) -> spec, source`
  (`source` "stored" | "dominant" | "default"); `ns.SpecHint(kit, storedKey, rankOf) -> spec|nil`;
  `ns.SpecShareKey(spec) -> "TOKEN:key"|nil`; `ns.SpecFromShare(v, byShare, legacyID, activeID) -> id|string|nil`;
  `ns.ResolvePackSpecs(packs, byShare)`. (`ns.MigrateTrees` is added in Task 4.)
- Produces (Spec.lua): `Hekili:NewClass(token, def) -> kit|nil`. `def.specs[i] = { key, name, tree, icon, role,
  ranged, package, unsupported }`. The kit: `kit.id`, `kit.token`, `kit.trees` (ordered specs), `kit.specs[key]`,
  `kit.talents` etc. A spec: own `id, key, name, texture, role, tree, slot, unsupported, melee, kit, settings, options`;
  everything else through `__index = kit`. `class.kit` (false when none), `class.specByShare["TOKEN:key"] = id`.
- Produces (mixin): `kit:RegisterSetting(key, value, option, ...)`: `...` are spec keys; none = every supported spec;
  each spec gets its own shallow copy of `option`. `kit:RegisterOptions(o)`: every spec's options, `package` excepted.
- Produces: `Hekili.Engine.Registry.Kit() -> kit|nil`.

- [ ] **Step 0: Record the gate base** (before any edit, on the fresh branch):

```bash
mkdir -p /tmp/specs
make check 2>&1 | grep ' solo: fights=' | sed -E 's/cpu mean [0-9.]+ p99 [0-9.]+ ms; //' | sort > /tmp/specs/solo-base.txt
make test-druid test-rogue test-paladin test-shaman test-hunter 2>&1 | grep ' solo: fights=' \
  | sed -E 's/cpu mean [0-9.]+ p99 [0-9.]+ ms; //' | sort >> /tmp/specs/solo-base.txt
wc -l /tmp/specs/solo-base.txt
```
Expected: about 30 lines (each 3-fight and 20-fight line of every pack, Arms three times).

- [ ] **Step 1: Write the failing pure spec** `tests/Forever/trees_spec.lua`:

```lua
-- tests/Forever/trees_spec.lua (per-spec plan, docs/superpowers/plans/2026-10-19-forever-specs.md): the pure rules of
-- src/Hekili/Engine/Schema/Trees.lua (ids, points per talent tree, the active-spec pick, the hint, share keys), and
-- Hekili:NewClass on the engine headless (tests/Forever/helpers/engine.lua).

local function trees()
    local ns = {}
    assert(loadfile("src/Hekili/Engine/Schema/Trees.lua"))("Hekili", ns)
    return ns
end

-- A kit as NewClass builds it, without the engine: { key, tree, unsupported } per spec.
local function kit(list, talents)
    local k = { token = "TEST", trees = {}, specs = {}, talents = talents }
    for i, d in ipairs(list) do
        local s = { id = 100050 + i, key = d[1], name = d[1], tree = d[2], unsupported = d[3], options = {} }
        k.trees[i], k.specs[d[1]] = s, s
    end
    return k
end
local TALENTS = { a = { 1, 101, 5 }, b = { 2, 201, 5 }, c = { 3, 301, 5 }, d = { 0, 401, 1 } }
local K = kit({ { "one", 1 }, { "two", 2 }, { "two_b", 2 }, { "heal", 3, true } }, TALENTS)
local function ranks(r)
    return function(t)
        return r[t[2]] or 0
    end
end

describe("Trees.lua", function()
    local T = trees()

    it("numbers a class's kit and specs 100000 + class id x 10 + slot", function()
        assert.are.equal(100010, T.TreeSpecID(1, 0))
        assert.are.equal(100042, T.TreeSpecID(4, 2))
        assert.are.equal(100114, T.TreeSpecID(11, 4))
    end)

    it("sums ranks per tree, tree 0 nowhere, into one reused table", function()
        local p = T.TreePoints(TALENTS, ranks({ [101] = 3, [201] = 5, [401] = 1 }))
        assert.are.same({ 3, 5, 0 }, p)
        assert.are.equal(p, T.TreePoints(TALENTS, ranks({})))
        assert.are.same({ 0, 0, 0 }, p)
    end)

    it("names a dominant tree only for a unique maximum above zero", function()
        assert.is_nil(T.DominantTree({ 0, 0, 0 }))
        assert.are.equal(2, T.DominantTree({ 3, 5, 0 }))
        assert.is_nil(T.DominantTree({ 5, 5, 0 }))
        assert.are.equal(3, T.DominantTree({ 0, 0, 1 }))
    end)

    describe("PickSpec", function()
        it("takes a stored choice that names a spec, whatever the talents", function()
            local s, source = T.PickSpec(K, "two_b", ranks({ [101] = 31 }))
            assert.are.same({ "two_b", "stored" }, { s.key, source })
        end)
        it("ignores a stored key the kit does not have", function()
            local s, source = T.PickSpec(K, "gone", ranks({ [201] = 5 }))
            assert.are.same({ "two", "dominant" }, { s.key, source })
        end)
        it("picks the first spec on the dominant tree, a healing tree too", function()
            assert.are.equal("two", (T.PickSpec(K, nil, ranks({ [201] = 5, [101] = 1 }))).key)
            assert.are.equal("heal", (T.PickSpec(K, nil, ranks({ [301] = 5 }))).key)
        end)
        it("falls back to the first supported spec with no points (level < 10) or a tie, not to be stored", function()
            local s, source = T.PickSpec(K, nil, ranks({}))
            assert.are.same({ "one", "default" }, { s.key, source })
            s, source = T.PickSpec(K, nil, ranks({ [101] = 2, [201] = 2 }))
            assert.are.same({ "one", "default" }, { s.key, source })
            local H = kit({ { "heal", 1, true }, { "dps", 2 } }, TALENTS)
            assert.are.equal("dps", (T.PickSpec(H, nil, ranks({}))).key)
        end)
    end)

    it("hints the dominant spec only when it is on another tree than the stored choice", function()
        assert.are.equal("two", T.SpecHint(K, "one", ranks({ [201] = 5 })).key)
        assert.is_nil(T.SpecHint(K, "two_b", ranks({ [201] = 5 }))) -- same tree
        assert.is_nil(T.SpecHint(K, "one", ranks({ [101] = 5 })))
        assert.is_nil(T.SpecHint(K, nil, ranks({ [201] = 5 })))
        assert.is_nil(T.SpecHint(K, "one", ranks({ [101] = 2, [201] = 2 })))
    end)

    it("carries a spec as TOKEN:key in shares and reads it back", function()
        local two = K.trees[2]
        two.kit = K
        assert.are.equal("TEST:two", T.SpecShareKey(two))
        assert.is_nil(T.SpecShareKey(K))
        assert.is_nil(T.SpecShareKey(nil))
        local by = { ["TEST:two"] = 100052 }
        assert.are.equal(100052, T.SpecFromShare("TEST:two", by, 1491, 100051))
        assert.are.equal("OTHER:x", T.SpecFromShare("OTHER:x", by, 1491, 100051)) -- another class's: kept
        assert.are.equal(100051, T.SpecFromShare(1491, by, 1491, 100051)) -- the legacy pseudo-spec: the active spec
        assert.are.equal(100052, T.SpecFromShare(100052, by, 1491, 100051))
        assert.is_nil(T.SpecFromShare(nil, by, 1491, 100051))
        local packs = { A = { spec = "TEST:two" }, B = { spec = "OTHER:x" }, C = { spec = 7 } }
        T.ResolvePackSpecs(packs, by)
        assert.are.same({ 100052, "OTHER:x", 7 }, { packs.A.spec, packs.B.spec, packs.C.spec })
    end)
end)

describe("Hekili:NewClass (the engine headless)", function()
    local engine = require("Forever.helpers.engine")
    local DEF = {
        specs = {
            { key = "one", name = "One", tree = 1, icon = 11, role = "attack", package = "One" },
            { key = "two", name = "Two", tree = 2, icon = 12, role = "tank", package = "Two", ranged = true },
            { key = "heal", name = "Heal", tree = 3, icon = 13, role = "healer", unsupported = true },
        },
    }
    local function names(settings)
        local out = {}
        for i, s in ipairs(settings) do
            out[i] = s.name
        end
        return out
    end

    it("registers the kit at slot 0 and a spec per entry, each spec reading the kit's registrations", function()
        local env = engine.load("WARRIOR")
        local kit = env.Hekili:NewClass("WARRIOR", DEF)
        assert.are.equal(100010, kit.id)
        assert.are.equal(kit, env.class.kit)
        local one, two, heal = kit.specs.one, kit.specs.two, kit.specs.heal
        assert.are.same({ 100011, 100012, 100013 }, { one.id, two.id, heal.id })
        assert.are.same({ one, two, heal }, kit.trees)
        assert.are.equal(two, env.class.specs[100012])
        assert.are.equal(kit.abilities, two.abilities)
        assert.are.equal(kit.talents, heal.talents)
        assert.are_not.equal(kit.settings, two.settings)
        assert.are.same({ "Two", 12, "tank", 2, false }, { two.options.package, two.texture, two.role, two.tree, two.melee })
        assert.is_false(heal.options.enabled)
        assert.is_nil(one.options.enabled)
        assert.are.equal(100012, env.class.specByShare["WARRIOR:two"])
        assert.is_nil(env.Hekili:NewClass("DRUID", DEF)) -- not the player's class
    end)

    it("fans a kit setting out to the supported specs or the named ones, each with its own option table", function()
        local env = engine.load("WARRIOR")
        local kit = env.Hekili:NewClass("WARRIOR", DEF)
        local opt = { type = "range", name = "N", min = 0, max = 9 }
        kit:RegisterSetting("n_shared", 3, opt)
        kit:RegisterSetting("n_two", 4, { type = "toggle", name = "T" }, "two")
        local one, two, heal = kit.specs.one, kit.specs.two, kit.specs.heal
        assert.are.same({ "n_shared" }, names(one.settings))
        assert.are.same({ "n_shared", "n_two" }, names(two.settings))
        assert.are.same({}, names(heal.settings))
        assert.are_not.equal(one.settings[1].info, two.settings[1].info)
        assert.is_nil(opt.get) -- the caller's table is copied, not filled
        assert.has_error(function()
            kit:RegisterSetting("x", 1, {}, "nope")
        end)
    end)

    it("applies kit options to every spec but keeps each spec's package", function()
        local env = engine.load("WARRIOR")
        local kit = env.Hekili:NewClass("WARRIOR", DEF)
        kit:RegisterOptions({ potion = "p", package = "Other" })
        assert.are.same({ "p", "One" }, { kit.specs.one.options.potion, kit.specs.one.options.package })
        assert.is_nil(kit.specs.heal.options.package)
    end)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `.lua/bin/busted tests/Forever/trees_spec.lua`
Expected: FAIL, `cannot open src/Hekili/Engine/Schema/Trees.lua`.

- [ ] **Step 3: Create `src/Hekili/Engine/Schema/Trees.lua`**

```lua
-- Engine/Schema/Trees.lua
-- Specs per talent tree on Forever (per-spec plan, docs/superpowers/plans/2026-10-19-forever-specs.md). The client
-- reports one pseudo-spec per class, so a class pack registers one kit and a spec per tree (Hekili:NewClass,
-- Spec.lua) with ids of our own, and the active spec is the character's stored choice, else the dominant talent tree
-- (stored once), else the first supported spec. Pure functions over a kit and the settings tables; Spec.lua, Registry
-- and Options call them.

local _, ns = ...

local ID_BASE = 100000 -- above every retail spec id and Forever's pseudo-specs (1483-1491)

--- The id of slot `slot` (0: the kit; 1..n: its specs in NewClass order) of the class with client class id `classID`.
function ns.TreeSpecID(classID, slot)
    return ID_BASE + classID * 10 + slot
end

local points = { 0, 0, 0 }

--- Points spent per talent tree: `talents` is a kit's RegisterTalents table ({ tree, spell, max rank } per key),
--- `rankOf(entry)` an entry's rank. Fills and returns one reused table { [1..3] }; tree 0 (unknown) counts nowhere.
function ns.TreePoints(talents, rankOf)
    points[1], points[2], points[3] = 0, 0, 0
    for _, t in pairs(talents) do
        local tree = t[1]
        if tree == 1 or tree == 2 or tree == 3 then
            points[tree] = points[tree] + (rankOf(t) or 0)
        end
    end
    return points
end

--- The tree holding the most points: nil when no tree has any or the most is shared (a tie).
function ns.DominantTree(p)
    local best, at, ties = 0, nil, 0
    for tree = 1, 3 do
        local v = p[tree]
        if v > best then
            best, at, ties = v, tree, 1
        elseif v == best and v > 0 then
            ties = ties + 1
        end
    end
    if ties == 1 then
        return at
    end
    return nil
end

local function firstOn(kit, tree)
    for _, s in ipairs(kit.trees) do
        if s.tree == tree then
            return s
        end
    end
end

local function firstSupported(kit)
    for _, s in ipairs(kit.trees) do
        if not s.unsupported then
            return s
        end
    end
    return kit.trees[1]
end

--- The active spec of `kit`: the stored choice (`stored`, a spec key) when the kit has it ("stored"); else the first
--- spec on the dominant tree ("dominant": the caller stores it); else the first supported spec ("default": no points
--- yet or a tie; not stored, so the first points spent decide). Returns the spec and the source.
function ns.PickSpec(kit, stored, rankOf)
    local s = stored and kit.specs[stored]
    if s then
        return s, "stored"
    end
    local tree = ns.DominantTree(ns.TreePoints(kit.talents, rankOf))
    s = tree and firstOn(kit, tree)
    if s then
        return s, "dominant"
    end
    return firstSupported(kit), "default"
end

--- The spec the talents favor when it is on another tree than the stored choice (the class page's hint), else nil.
function ns.SpecHint(kit, stored, rankOf)
    local s = stored and kit.specs[stored]
    if not s then
        return nil
    end
    local tree = ns.DominantTree(ns.TreePoints(kit.talents, rankOf))
    if tree and tree ~= s.tree then
        return firstOn(kit, tree)
    end
    return nil
end

--- A spec's key in export strings, "<CLASS TOKEN>:<spec key>" ("WARRIOR:arms"); nil for a kit or a spec outside one.
function ns.SpecShareKey(spec)
    local kit = spec and rawget(spec, "kit")
    if kit then
        return kit.token .. ":" .. spec.key
    end
    return nil
end

--- A pack payload's `spec` as this session's spec id: a share key through `byShare` (another class's: kept as the
--- string, resolved when that class logs in); the class's legacy pseudo-spec id (`legacyID`) as the active spec
--- (`activeID`); anything else as is.
function ns.SpecFromShare(v, byShare, legacyID, activeID)
    if type(v) == "string" then
        return byShare[v] or v
    end
    if v ~= nil and v == legacyID and activeID then
        return activeID
    end
    return v
end

--- Rebinds every pack whose `spec` is a share key this class registered (an import made on another character).
function ns.ResolvePackSpecs(packs, byShare)
    for _, p in pairs(packs) do
        if type(p) == "table" and type(p.spec) == "string" and byShare[p.spec] then
            p.spec = byShare[p.spec]
        end
    end
end
```

- [ ] **Step 4: List it in the TOC.** In `src/Hekili/Hekili.toc`, insert `Engine\Schema\Trees.lua` on the line before
  `Engine\Schema\Spec.lua`.

- [ ] **Step 5: `Hekili.Class` fields.** In `src/Hekili/Hekili.lua`, in `Hekili.Class = { specs = {}, num = 0, ...`,
  after `specs = {},` add:

```lua
    kit = false, -- the class pack's kit (Hekili:NewClass; Engine/Schema/Trees.lua); false: no class pack
    specByShare = {}, -- "<CLASS>:<spec key>" -> spec id, the share key export strings carry
```

  In `tests/Forever/helpers/engine.lua` `M.load`, add `"specByShare",` to the list of `class[k] = {}` names and,
  after `class.itemPack = ...`, `class.kit = false`. In the same file's `ns.Facade = { ... }` (~l.194) add the read
  NewClass makes, with the client class ids the packs use:

```lua
        UnitClass = function()
            local ids = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
            return classToken, classToken, ids[classToken]
        end,
```

- [ ] **Step 6: `NewClass` and the spec builder** in `src/Hekili/Engine/Schema/Spec.lua`.
  At the top, extend the facade locals:

```lua
local UnitClass, UnitGUID = Facade.UnitClass, Facade.UnitGUID
```
  (replacing `local UnitGUID = Facade.UnitGUID`).

  Replace `function Hekili:NewSpecialization( specID, isRanged, icon )` ... `return spec` / `end` (~l.1456-1546)
  with the builder, NewSpecialization on it, and NewClass. The builder's table literal is the existing one
  verbatim (`resources = {}` ... `variables = {}`), with `key = key` in place of `key = token`:

```lua
local function buildSpec( id, key, name, texture, role, pClass, melee )
    local spec = class.specs[ id ] or {
        id = id,
        key = key,
        name = name,
        texture = texture,
        role = role,
        class = pClass,
        melee = melee,

        -- (the existing fields, unchanged: resources ... variables)
    }

    class.num = class.num + 1

    for k, func in pairs( HekiliSpecMixin ) do
        spec[ k ] = func
    end

    class.specs[ id ] = spec
    return spec
end

function Hekili:NewSpecialization( specID, isRanged, icon )
    -- (the existing body down to `local token = getSpecializationKey( id )`, unchanged)
    return buildSpec( id, token, name, texture, role, pClass, not isRanged )
end

--- (per-spec plan) A class pack's entry point. Returns the class kit: every Register* call on it (abilities, auras,
--- talents as { tree (1-3, 0 unknown), spell, max rank }, resources, hooks, packs, settings) is the class's, read by
--- each of its specs. `def.specs` lists the specs in order, each { key, name, tree (the talent tree it rides), icon,
--- role ("attack"|"tank"|"healer": shown, not simulated), ranged, package (its default priority), unsupported (true: no
--- priorities on Forever; the engine idles and the options page says so) }. Ids are ours: ns.TreeSpecID(client class
--- id, slot), the kit at slot 0. Nil when `token` is not the player's class.
function Hekili:NewClass( token, def )
    local _, playerToken, classID = UnitClass( "player" )
    if token ~= playerToken or type( classID ) ~= "number" or type( def ) ~= "table" or type( def.specs ) ~= "table" then return end

    class.initialized = true
    local kit = buildSpec( ns.TreeSpecID( classID, 0 ), "kit", token, nil, nil, token, true )
    kit.token, kit.trees, kit.specs = token, {}, {}

    for slot, d in ipairs( def.specs ) do
        local id = ns.TreeSpecID( classID, slot )
        local s = setmetatable( {
            id = id,
            key = d.key,
            name = d.name,
            texture = d.icon,
            role = d.role,
            tree = d.tree or 0,
            slot = slot,
            unsupported = d.unsupported or nil,
            melee = not d.ranged,
            kit = kit,
            settings = {},
            options = { package = d.package },
        }, { __index = kit } )
        if d.unsupported then s.options.enabled = false end -- no priorities: no displays

        class.specs[ id ] = s
        kit.trees[ slot ] = s
        kit.specs[ d.key ] = s
        class.specByShare[ token .. ":" .. d.key ] = id
    end

    class.kit = kit
    return kit
end
```
  (Mixin functions copied onto the kit reach every spec through `__index`; each spec's own `settings` and `options`
  keep RegisterSetting's per-spec values and the profile defaults per spec.)

- [ ] **Step 7: The kit-aware mixin** in `HekiliSpecMixin`:
  - `RegisterSetting` (~l.1285): insert at the top of the function body:

```lua
        local trees = rawget( self, "trees" )
        if trees then -- the kit: every supported spec (or the specs named after `option`), each with its own option table
            local only = select( "#", ... ) > 0 and { ... } or nil
            for _, k in ipairs( only or {} ) do
                if not self.specs[ k ] then error( "RegisterSetting " .. key .. ": no spec " .. tostring( k ), 2 ) end
            end
            for _, s in ipairs( trees ) do
                local wanted = not only and not s.unsupported
                for _, k in ipairs( only or {} ) do if k == s.key then wanted = true end end
                if wanted then
                    local o = {}
                    for k, v in pairs( option ) do o[ k ] = v end
                    s:RegisterSetting( key, value, o )
                end
            end
            return
        end
```
    and change its signature to `RegisterSetting = function( self, key, value, option, ... )`.
  - `RegisterOptions` (~l.1151):

```lua
    RegisterOptions = function( self, options )
        local trees = rawget( self, "trees" )
        if trees then -- the kit: every spec's options, but each spec keeps its own package (NewClass)
            for _, s in ipairs( trees ) do
                for k, v in pairs( options ) do
                    if k ~= "package" and s.options[ k ] == nil then s.options[ k ] = v end
                end
            end
            return
        end
        self.options = options
    end,
```
  - `RegisterEvent` and `RegisterUnitEvent` (~l.1160-1170): replace each `if state.spec.id == self.id then func( ... ) end`
    with `if state.spec.id == self.id or state.spec.kitID == self.id then func( ... ) end` (a kit's handler runs for
    any of its specs; `state.spec.kitID` is set by Task 2, nil until then, so nothing changes yet).
  - RegisterAura's class copy (~l.398): replace `if GetSpecializationInfo( GetSpecialization() or 0 ) == self.id then`
    with `if state.spec.id == self.id or state.spec.kitID == self.id then`.

- [ ] **Step 8: `Registry.Kit`.** In `src/Hekili/Engine/Registry.lua`, inside the `-- stylua: ignore start` block add:

```lua
function Registry.Kit() return class.kit or nil end
```

- [ ] **Step 9: ContentAPI 6.** In `src/Hekili/Engine/Content.lua` add the history line and bump:

```lua
-- 6 (2026-10-2x): Hekili:NewClass (one kit, one spec per talent tree, ids of the core's), RegisterTalents' first field
-- is the talent tree, kit:RegisterSetting's trailing spec keys (per-spec plan).
local CONTENT_API = 6
```
  Set `## X-Hekili-ContentAPI: 6` in every `src/Hekili_*/Hekili_*.toc` (Shared, Warrior, Druid, Rogue, Paladin, Shaman,
  Hunter). In `tests/Forever/content_spec.lua` change the current-version literals to 6: the expected
  `addons.meta(name)["X-Hekili-ContentAPI"]` value and `"\nlocal CONTENT_API = 5\n"`. Its mismatch case sets a pack's
  metadata to an older version (`"4"` before Day 5, `"5"` after); set it to `"5"` so it stays a mismatch.

- [ ] **Step 10: The content allowlist.** In `tests/boundary_spec.lua`, add `NewClass = true` to `PUBLIC`
  (NewSpecialization stays until Task 6).

- [ ] **Step 11: Run the spec and the whole suite**

Run: `.lua/bin/busted tests/Forever/trees_spec.lua tests/Forever/content_spec.lua tests/boundary_spec.lua && make check`
Expected: PASS; no pack calls NewClass yet, so the gate lines cannot move (run the gate commands anyway with
`TASK=1`: `gate lines identical`).

- [ ] **Step 12: Commit**

```bash
git add src/Hekili/Engine/Schema/Trees.lua src/Hekili/Hekili.toc src/Hekili/Hekili.lua src/Hekili/Engine/Schema/Spec.lua \
  src/Hekili/Engine/Registry.lua src/Hekili/Engine/Content.lua src/Hekili_*/Hekili_*.toc tests/Forever/trees_spec.lua \
  tests/Forever/helpers/engine.lua tests/Forever/content_spec.lua tests/boundary_spec.lua
git commit -m "feat(specs): a class kit and one spec per talent tree with core ids (Hekili:NewClass, Trees.lua)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: spec selection, and Warrior on NewClass (L)

The selection can only be exercised on a converted pack, so Warrior converts here (all its settings shared, as
today; Task 3 splits them).

**Files:**
- Create: `tests/Forever/spec_choice_spec.lua`
- Modify: `src/Hekili/Engine/Schema/Spec.lua` (SpecializationChanged ~l.1949-2040 and after `ns.updateTalents()`
  ~l.2232, PEW ~l.2250; new `ns.CharKey`, `talentRank`, `Hekili:SettleSpecChoice`, `Hekili:SetSpecChoice`,
  `Hekili:GetSpecHint`), `src/Hekili/Engine/Settings.lua`, `src/Hekili/Engine/Registry.lua`,
  `src/Hekili/Engine/Sim/Events.lua` (CheckForTalentUpdate ~l.371), `src/Hekili/UI/UI.lua` (~l.1343),
  `src/Hekili/Engine/Snapshot.lua` (~l.447, 560), `src/Hekili/Options/Options.lua` (defaults ~l.368, GetCurrentSpec
  ~l.2603, DeserializeActionPack ~l.7770), `tools/make_pack.lua` (`load`), `tests/Game/harness/headless.lua`
  (~l.978), `tests/Forever/helpers/{load_warrior,load_druid,warrior_world}.lua`,
  `src/Hekili_Warrior/Warrior.lua`, `src/Hekili_Warrior/APLs/packs.lua`,
  `tests/Forever/{settings,warrior,fury,make_pack}_spec.lua`

**Interfaces:**
- Consumes: Task 1's `ns.PickSpec`, `ns.SpecHint`, `ns.SpecFromShare`, `ns.ResolvePackSpecs`, `class.kit`,
  `class.specByShare`.
- Produces: `state.spec.clientID` (the client's pseudo-spec id), `state.spec.kitID`, `state.spec.source`;
  `ns.CharKey() -> "Name-Realm"`; `Hekili:SetSpecChoice(keyOrPrefix) -> spec|nil` (stores, sets
  `PendingSpecializationChange`); `Hekili:GetSpecHint() -> spec|nil`; `Hekili:SettleSpecChoice(clientID)`;
  `Hekili.Engine.settings.specChoice[charKey] = specKey`, `settings.specMigrated[token]` (used in Task 4);
  `Registry.SpecFromShare(v) -> id|v`; manifest shape `{ class = "WARRIOR", packs = {...}, specs = { Arms = "arms", ... } }`;
  pack payload `spec = "WARRIOR:arms"`.
- Warrior ids for tests: Arms 100011, Fury 100012, Protection 100013; client pseudo-spec 1491.

- [ ] **Step 1: Write the failing spec** `tests/Forever/spec_choice_spec.lua`:

```lua
-- tests/Forever/spec_choice_spec.lua (per-spec plan, docs/superpowers/plans/2026-10-19-forever-specs.md): the active
-- spec on Forever, stock Hekili headless: the stored choice for the character, else the dominant talent tree (stored
-- once), else the first supported spec; a respec only hints. Review focus 1 and 2 (no talents; the choice across a
-- /reload and a respec, no loop).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local ARMS, FURY, PROT = 100011, 100012, 100013
local CHAR = "Player-Realm" -- the fake client's UnitName("player") .. "-" .. GetRealmName()
local FURY_TALENTS = { [23881] = 1, [12319] = 5 } -- Bloodthirst, Flurry

-- The harness's C_Traits answer for a talent build (tests/Game/harness/headless.lua's login shape).
local function traits(talents)
    local tr = { config = 1, trees = { 1 }, nodeIDs = {}, nodes = {}, defs = {} }
    for spell, rank in pairs(talents) do
        local n = #tr.nodeIDs + 1
        tr.nodeIDs[n], tr.nodes[n], tr.defs[n] = n, { entryIDs = { n }, activeRank = rank }, spell
    end
    return tr
end

local function boot(o)
    o = o or {}
    local c = ww.character()
    c.talents = o.talents or c.talents
    c.level = o.level or c.level
    local H = headless.new({ character = c, saved = o.saved, pack = o.pack })
    assert.are.same({}, H.loadErrors)
    return H
end

-- The event frame's OnUpdate (the harness does not run it): a pending spec change runs; at most 2 passes.
local function settle(H)
    for _ = 1, 2 do
        if not H.Hekili.PendingSpecializationChange then
            return
        end
        H.Hekili:SpecializationChanged()
    end
    assert.is_false(H.Hekili.PendingSpecializationChange, "the spec change did not settle")
end

describe("the active spec (headless Warrior)", function()
    it("picks the dominant tree on first login and stores it", function()
        local H = boot()
        settle(H)
        assert.are.equal(ARMS, H.Hekili.State.spec.id)
        assert.are.equal(1491, H.Hekili.State.spec.clientID)
        assert.are.equal("arms", H.Hekili.DB.profile.specChoice[CHAR])
        assert.are.equal("arms", H.Hekili.Engine.Output.status.specKey)
        assert.is_truthy(H.Hekili:GenerateProfile():find("\nspec: arms (", 1, true))
        local f = boot({ talents = FURY_TALENTS })
        settle(f)
        assert.are.equal(FURY, f.Hekili.State.spec.id)
        assert.are.equal("fury", f.Hekili.DB.profile.specChoice[CHAR])
    end)

    it("binds each built-in priority to its spec and makes it that spec's package", function()
        local H = boot()
        local p = H.Hekili.DB.profile
        assert.are.same({ ARMS, FURY, PROT }, { p.packs.Arms.spec, p.packs.Fury.spec, p.packs.Protection.spec })
        assert.are.same({ "Arms", "Fury", "Protection" }, { p.specs[ARMS].package, p.specs[FURY].package, p.specs[PROT].package })
    end)

    it("gives a character with no talents (level 5) the first spec, stores nothing, then follows its first points", function()
        local H = boot({ talents = {}, level = 5 })
        settle(H)
        assert.are.equal(ARMS, H.Hekili.State.spec.id)
        assert.are.equal("default", H.Hekili.State.spec.source)
        assert.is_nil(H.Hekili.DB.profile.specChoice[CHAR])
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        assert.are.same({}, H.errors)
        H.ctl.traits = traits(FURY_TALENTS)
        H.Fire("PLAYER_TALENT_UPDATE")
        assert.is_true(H.Hekili.PendingSpecializationChange)
        settle(H)
        assert.are.equal(FURY, H.Hekili.State.spec.id)
        assert.are.equal("fury", H.Hekili.DB.profile.specChoice[CHAR])
    end)

    it("keeps a stored choice across a /reload and a respec, hints the dominant spec, and runs no extra pass", function()
        local H1 = boot()
        settle(H1)
        assert.are.equal("fury", H1.Hekili:SetSpecChoice("fu").key) -- a prefix
        settle(H1)
        assert.are.equal(FURY, H1.Hekili.State.spec.id)
        local H = boot({ saved = H1.env.HekiliDB }) -- Arms talents, Fury stored
        settle(H)
        assert.are.equal(FURY, H.Hekili.State.spec.id)
        assert.are.equal("stored", H.Hekili.State.spec.source)
        assert.are.equal("arms", H.Hekili:GetSpecHint().key)
        local passes, change = 0, H.Hekili.SpecializationChanged
        H.Hekili.SpecializationChanged = function(...)
            passes = passes + 1
            return change(...)
        end
        H.ctl.traits = traits({ [12294] = 1, [12296] = 1, [12834] = 3 }) -- a respec deeper into Arms
        H.Fire("PLAYER_TALENT_UPDATE")
        assert.is_false(H.Hekili.PendingSpecializationChange)
        settle(H)
        assert.are.equal(0, passes)
        assert.are.equal(FURY, H.Hekili.State.spec.id)
        assert.are.equal("arms", H.Hekili:GetSpecHint().key)
        assert.is_nil(H.Hekili:SetSpecChoice("nope"))
        assert.is_nil(H.Hekili:SetSpecChoice("")) -- every key is a prefix of "": ambiguous
    end)

    it("selects the spec of the priority a harness instance asks for", function()
        local H = boot({ pack = "Protection" })
        assert.are.equal(PROT, H.Hekili.State.spec.id)
        assert.are.equal("Protection", H.Hekili.DB.profile.specs[PROT].package)
    end)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `.lua/bin/busted tests/Forever/spec_choice_spec.lua`
Expected: FAIL (`state.spec.id` is 1491; `specChoice` nil).

- [ ] **Step 3: The settings tables.** `src/Hekili/Engine/Settings.lua`: add `specChoice = false,` and
  `specMigrated = false,` to the by-reference block of `settings`, and in `Engine.Configure`:

```lua
    settings.specChoice = profile.specChoice
    settings.specMigrated = profile.specMigrated
```
  `src/Hekili/Options/Options.lua` defaults (~l.368), after the `specs = { ... },` entry:

```lua
                specChoice = {}, -- [ "Name-Realm" ] = spec key: each character's active spec (per-spec plan)
                specMigrated = {}, -- [ class token ] = true: the legacy pseudo-spec profile was copied to the specs
```
  `tests/Forever/settings_spec.lua`: add `"specChoice", "specMigrated"` to `SUBTABLES`. In "keeps a saved spec setting
  ..." replace `[1491]` by `[100011]` (both the saved table and the two `p.specs[...]` reads): Arms is the spec the
  Arms character gets.

- [ ] **Step 4: Selection in `Spec.lua`.** Near the other locals at the top add:

```lua
local GetRealmName, GetTalentInfoByID, UnitName = Facade.GetRealmName, Facade.GetTalentInfoByID, Facade.UnitName

-- A RegisterTalents entry's rank: the facade answers the C_Traits walk's rank as GetTalentInfoByID's 12th return.
local function talentRank( t )
    return ( select( 12, GetTalentInfoByID( t ) ) ) or 0
end

--- The key a character's spec choice is stored under: "Name-Realm".
function ns.CharKey()
    return ( UnitName( "player" ) or "?" ) .. "-" .. ( GetRealmName() or "?" )
end
```

  In `SpecializationChanged`, replace the head

```lua
function Hekili:SpecializationChanged()
    local currentSpec = GetSpecialization()
    local currentID = GetSpecializationInfo( currentSpec )

    if currentID == nil then
        self.PendingSpecializationChange = true
        return
    end
```
  with

```lua
function Hekili:SpecializationChanged()
    local currentSpec = GetSpecialization()
    if currentSpec == 5 then currentSpec = 1 end -- no specialization: the first
    -- Forever's one pseudo-spec per class: its id keys the legacy profile; its role and primary stat stay the
    -- simulation's (a spec's role is shown, not simulated: per-spec plan).
    local clientID, clientName, _, _, clientRole, clientStat = GetSpecializationInfo( currentSpec )

    if clientID == nil then
        self.PendingSpecializationChange = true
        return
    end

    -- The class pack's spec: the stored choice, else the dominant tree (Engine/Schema/Trees.lua). The ranks may be the
    -- last walk's here; SettleSpecChoice re-picks after this pass's walk.
    local kit = class.kit
    local tree, source
    if kit then tree, source = ns.PickSpec( kit, Hekili.Engine.settings.specChoice[ ns.CharKey() ], talentRank ) end
    local currentID = tree and tree.id or clientID
```
  and replace the block from `    local specs = {}` through `    insert( specs, 0 )` (the "If the player does not have
  a specialization" branch and the `for i = 1, 4 do` loop) with:

```lua
    local specs = { currentID, 0 }

    state.spec.id = currentID
    state.spec.name = tree and tree.name or clientName
    state.spec.key = tree and tree.key or getSpecializationKey( currentID )
    state.spec.clientID = clientID
    state.spec.kitID = kit and kit.id or currentID
    state.spec.source = source or "client"

    for k in pairs( state.role ) do
        state.role[ k ] = false
    end

    if clientRole == "DAMAGER" then
        state.role.attack = true
    elseif clientRole == "TANK" then
        state.role.tank = true
    else
        state.role.healer = true
    end

    if clientStat == 1 then
        state.spec.primaryStat = "strength"
    elseif clientStat == 2 then
        state.spec.primaryStat = "agility"
    else
        state.spec.primaryStat = "intellect"
    end

    state.spec[ state.spec.key ] = true
```
  After `    ns.updateTalents()` (below `ns.VirtualState.SpecChanged()`) add:

```lua
    if kit then self:SettleSpecChoice( clientID ) end
```
  After the end of `SpecializationChanged`, add:

```lua
--- (per-spec plan) After a spec change's talent walk: share keys of imported packs resolved, the dominant tree stored on
--- a character with no choice yet, and one more pass when this pass's pick (made on the last walk's ranks) was not it.
--- A stored choice never moves here: a respec only shows the hint (GetSpecHint).
function Hekili:SettleSpecChoice( clientID )
    local kit, settings = class.kit, Hekili.Engine.settings
    local key = ns.CharKey()
    local pick, source = ns.PickSpec( kit, settings.specChoice[ key ], talentRank )
    ns.ResolvePackSpecs( settings.packs, class.specByShare )
    if source == "dominant" then settings.specChoice[ key ] = pick.key end
    if pick.id ~= state.spec.id then self.PendingSpecializationChange = true end
end

--- Stores this character's spec choice and switches to it at the next frame: `key` is a spec key, or a prefix of one
--- spec's key or name (case-insensitive). Returns the spec, or nil when no spec or more than one matches.
function Hekili:SetSpecChoice( key )
    local kit = class.kit
    if not kit or type( key ) ~= "string" then return end
    key = key:lower()
    local s = kit.specs[ key ]
    if not s then
        for _, t in ipairs( kit.trees ) do
            if t.key:sub( 1, #key ) == key or t.name:lower():sub( 1, #key ) == key then
                if s then return end -- ambiguous
                s = t
            end
        end
    end
    if not s then return end
    Hekili.Engine.settings.specChoice[ ns.CharKey() ] = s.key
    self.PendingSpecializationChange = true
    return s
end

--- The spec the talents favor when it differs from this character's stored choice (the class page's hint), or nil.
function Hekili:GetSpecHint()
    local kit = class.kit
    if not kit then return end
    return ns.SpecHint( kit, Hekili.Engine.settings.specChoice[ ns.CharKey() ], talentRank )
end
```
  In the `PLAYER_ENTERING_WORLD` handler near the end of the file (~l.2257), replace
  `if currentID ~= state.spec.id then` with `if currentID ~= state.spec.clientID then`.

- [ ] **Step 5: Talent events** (`src/Hekili/Engine/Sim/Events.lua` ~l.371): replace `CheckForTalentUpdate`'s body:

```lua
    local function CheckForTalentUpdate( event )
        local specialization = GetSpecialization()
        local specID = specialization and GetSpecializationInfo( specialization )

        if specID and specID ~= state.spec.clientID then
            Hekili.PendingSpecializationChange = true
        elseif class.kit and not Hekili.Engine.settings.specChoice[ ns.CharKey() ] then
            -- no stored choice yet (no points, or a tie): the next pass picks the dominant tree and stores it
            Hekili.PendingSpecializationChange = true
        end
    end
```

- [ ] **Step 6: The readers of the client's spec.**
  - `src/Hekili/UI/UI.lua` (~l.1343): replace
    `local specEnabled = GetSpecialization()` / `specEnabled = specEnabled and GetSpecializationInfo( specEnabled )`
    with `local specEnabled = Status.specID`.
  - `src/Hekili/Options/Options.lua` `GetCurrentSpec` (~l.2603): `activeSpec = activeSpec or Status.specID`.
  - `src/Hekili/Engine/Snapshot.lua` `GenerateProfile`: after `local spec = s.spec.key` add
    `if spec and s.spec.source then spec = spec .. " (" .. s.spec.source .. ")" end`.

- [ ] **Step 7: Share keys for the built-in packs.** `src/Hekili/Engine/Registry.lua`, after `Registry.Kit`:

```lua
--- A pack payload's `spec` (a share key "WARRIOR:arms", a legacy pseudo-spec id or an id) as this session's spec id.
function Registry.SpecFromShare(v)
    return ns.SpecFromShare(v, class.specByShare, state.spec.clientID, state.spec.id)
end
```
  `src/Hekili/Options/Options.lua` `DeserializeActionPack` (~l.7770): after `serial.payload.builtIn = false` add
  `serial.payload.spec = Registry.SpecFromShare( serial.payload.spec )` (RestoreDefaults and the importer both read
  packs through it).

- [ ] **Step 8: Manifests carry spec keys.** `tools/make_pack.lua` `load`: replace `p.spec = def.spec` with

```lua
        if def.class then -- per-spec manifests: { class = "WARRIOR", packs = {...}, specs = { Arms = "arms", ... } }
            local key = def.specs and def.specs[name]
            if not key then
                error(root .. "packs.lua: pack " .. name .. " has no spec key", 0)
            end
            p.spec = def.class .. ":" .. key
        else
            p.spec = def.spec -- the pseudo-spec manifests, until Task 6 converts the last of them
        end
```
  and in the file header comment replace `({ spec, packs = { "<Pack>", ... } } in block order)` with
  `({ class, packs = { "<Pack>", ... } in block order, specs = { [<Pack>] = <spec key> } })`. In
  `tests/Forever/make_pack_spec.lua` add to `describe("tools/make_pack.lua", ...)`:

```lua
    it("binds each pack to its spec's share key from the manifest", function()
        local by = {}
        for _, p in ipairs(mp.load("warrior")) do
            by[p.name] = mp.decode(mp.encode(p)).spec
        end
        assert.are.same({ Arms = "WARRIOR:arms", Fury = "WARRIOR:fury", Protection = "WARRIOR:protection" }, by)
    end)
```

- [ ] **Step 9: The harness asks for the pack's spec.** `tests/Game/harness/headless.lua` (~l.978), replace

```lua
    if hk and o.pack and ctl.specID then
        rawget(hk.DB.profile.specs, ctl.specID).package = o.pack
    end
```
  with

```lua
    if hk and o.pack and ctl.specID then
        -- the priority's spec becomes the character's choice (a class on NewClass), then the priority its package
        local pack = rawget(hk.DB.profile.packs, o.pack)
        local s = pack and hk.Engine.Registry.Specs()[pack.spec]
        if s and s.id ~= hk.State.spec.id and hk:SetSpecChoice(s.key) then
            hk:SpecializationChanged()
        end
        local sp = rawget(hk.DB.profile.specs, hk.State.spec.id)
        if sp then
            sp.package = o.pack
        end
    end
```
  and update the `o.character` doc line: `specID` is the client's pseudo-spec id; the spec comes from `o.pack`.

- [ ] **Step 10: The recording loaders.** In both `tests/Forever/helpers/load_warrior.lua` and `load_druid.lua`, beside
  `function hekili:NewSpecialization(id)` add

```lua
    function hekili:NewClass(token, def)
        w.class, w.def = token, def
        return spec
    end
```
  and where `w.settings` is built from `reg.RegisterSetting`, record the spec keys:
  `w.settings[call[1]] = { default = call[2], option = call[3], specs = call[4] and { unpack(call, 4) } or nil }`.
  Update both files' doc lines: `w.class`, `w.def` (NewClass's), `w.settings[key].specs` (nil: every spec).

- [ ] **Step 11: Convert Warrior.** `src/Hekili_Warrior/Warrior.lua`:
  - Header line 2: `-- The Forever Warrior (pseudo-spec 1491): ...` -> `-- The Forever Warrior (Arms, Fury and Protection, one spec a talent tree: Hekili:NewClass): ...`.
  - Replace `local spec = Hekili:NewSpecialization(1491, false, 135328) -- inv_sword_27; numeric because Options formats it with %d` with

```lua
-- The class kit and one spec a talent tree (ids the core's: Arms 100011, Fury 100012, Protection 100013; the client's
-- one pseudo-spec, 1491, only keys the legacy profile the core migrates). Icons are numeric: Options formats them with %d.
local spec = Hekili:NewClass("WARRIOR", {
    specs = {
        { key = "arms", name = "Arms", tree = 1, icon = 132355, role = "attack", package = "Arms" },
        { key = "fury", name = "Fury", tree = 2, icon = 132347, role = "attack", package = "Fury" },
        { key = "protection", name = "Protection", tree = 3, icon = 132341, role = "tank", package = "Protection" },
    },
})
```
  - The talents comment (~l.320): `-- Talents: { node (unused on Forever), the definition spell, max rank }: ...` ->
    `-- Talents: { talent tree (1 Arms, 2 Fury, 3 Protection: the dominant tree picks the spec), the definition spell, max rank }: ...`.
  - The tree field, by the block's tree headers (Forever-only lines sit inside their tree's section):

```bash
awk -v trees='Arms|Fury|Protection' '
/^spec:RegisterTalents\(\{/ { inb = 1 }
inb && /^\}\)/ { inb = 0 }
inb && match($0, "^    -- (" trees ") \\(") { t++ }
inb { sub(/= \{ 0, /, "= { " t ", ") }
{ print }' src/Hekili_Warrior/Warrior.lua > /tmp/specs/w.lua && mv /tmp/specs/w.lua src/Hekili_Warrior/Warrior.lua
grep -c '= { [123], ' src/Hekili_Warrior/Warrior.lua   # 52
grep -c '= { 0, ' src/Hekili_Warrior/Warrior.lua       # 0
```
  - Delete `spec:RegisterOptions({ package = "Arms" })` (each spec's package is in NewClass).
  - `src/Hekili_Warrior/APLs/packs.lua`: `return { spec = 1491, packs = { "Arms", "Fury", "Protection" } }` ->

```lua
return {
    class = "WARRIOR",
    packs = { "Arms", "Fury", "Protection" },
    specs = { Arms = "arms", Fury = "fury", Protection = "protection" },
}
```
  - `make packs` (the three blocks' payload spec changes, so the class date moves to today and every saved built-in
    pack reloads with its spec).

- [ ] **Step 12: The Warrior tests.**
  - `tests/Forever/helpers/warrior_world.lua`: `M.SPEC, M.CLASS_ID, M.PACK = 1491, 1, "Arms"` ->

```lua
-- M.SPEC: the Arms spec's id (Hekili:NewClass); M.CLIENT_SPEC: the client's pseudo-spec the character reports.
M.SPEC, M.CLIENT_SPEC, M.CLASS_ID, M.PACK = 100011, 1491, 1, "Arms"
```
    and in `character()` `specID = M.SPEC` -> `specID = M.CLIENT_SPEC`.
  - `tests/Forever/fury_spec.lua` ~l.32: `H.Hekili.DB.profile.specs[ww.SPEC].settings[name] = value` ->
    `H.Hekili.DB.profile.specs[H.Hekili.State.spec.id].settings[name] = value` (the Fury spec).
  - `tests/Forever/warrior_spec.lua` ~l.668: `assert.are.same({ package = "Arms" }, w.options)` ->

```lua
        assert.is_nil(w.options) -- each spec's package is NewClass's
        assert.are.equal("WARRIOR", w.class)
        local keys = {}
        for i, s in ipairs(w.def.specs) do
            keys[i] = s.key .. "=" .. tostring(s.package) .. "@" .. s.tree
        end
        assert.are.same({ "arms=Arms@1", "fury=Fury@2", "protection=Protection@3" }, keys)
```
    and ~l.693 `assert.are.same({ 1491, { "Arms", "Fury", "Protection" } }, { def.spec, def.packs })` ->
    `assert.are.same({ "WARRIOR", { "Arms", "Fury", "Protection" } }, { def.class, def.packs })`.
  - Add to `warrior_spec.lua` (with the RegisterTalents checks, or at the end of its main describe):

```lua
    it("places every registered talent in a tree, 17 Arms, 17 Fury and 18 Protection", function()
        local n = { 0, 0, 0 }
        for key, t in pairs(require("Forever.helpers.load_warrior").load().talents) do
            assert.is_true(t[1] >= 1 and t[1] <= 3, key)
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ 17, 17, 18 }, n)
    end)
```
    (17/17/18 counted on 149d286f with the awk below, the Forever-only lines inside their section; the Druid's block
    counts `{ [0] = 3, 16, 16, 15 }` the same way, for Task 5's equivalent test in `druid_spec.lua`.)

- [ ] **Step 13: Run the specs, then the gate**

Run: `.lua/bin/busted tests/Forever/spec_choice_spec.lua tests/Forever/settings_spec.lua tests/Forever/warrior_spec.lua tests/Forever/fury_spec.lua tests/Forever/make_pack_spec.lua`
Expected: PASS. Then the gate commands with `TASK=2`: `make check` exit 0 and `gate lines identical` (Arms: the
character's talents pick Arms; the harness's Fury run selects the Fury spec, whose settings are the kit's shared ones).

- [ ] **Step 14: Commit**

```bash
git add -A src/Hekili src/Hekili_Warrior tools/make_pack.lua tests
git commit -m "feat(specs): the active spec is the stored choice, else the dominant tree; Warrior on NewClass

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: options per spec, preferences split, `/hekili spec` (M)

**Files:**
- Modify: `src/Hekili/Options/Options.lua` (EmbedSpecOptions ~l.3404-3972, Priorities list ~l.4554, packSpec label
  ~l.4372), `src/Hekili/Options/ChatCommands.lua`, `src/Hekili_Warrior/Warrior.lua` (RegisterSetting calls),
  `tests/Forever/spec_choice_spec.lua`, `tests/Forever/packs_spec.lua`

**Interfaces:**
- Consumes: `Registry.Kit()`, `Hekili:SetSpecChoice`, `Hekili:GetSpecHint`, `Status.specKey`, `kit:RegisterSetting(key, value, option, ...)`.
- Produces: options nodes `Hekili.Options.plugins.specializations[<spec key>]` for each spec of the kit, each with
  `args.core.args.activeSpec` (select) and `args.core.args.specHint` (description); an unsupported spec's node holds
  only `notice`, `activeSpec`, `specHint`. Chat: `/hekili spec [name]`.

- [ ] **Step 1: Write the failing specs.** Append to `tests/Forever/spec_choice_spec.lua`:

```lua
describe("the spec options and /hekili spec (headless Warrior)", function()
    it("shows one node per spec with its own preferences, and the dropdown and the command set the choice", function()
        local H = boot()
        settle(H)
        H.Hekili:EmbedSpecOptions()
        local nodes = H.Hekili.Options.plugins.specializations
        assert.are.same({ 132355, 132347, 132341 }, { nodes.arms.icon, nodes.fury.icon, nodes.protection.icon })
        local prefs = function(key)
            return nodes[key].args.core.plugins.settings
        end
        assert.is_not_nil(prefs("arms").ww_min_enemies)
        assert.is_nil(prefs("arms").hs_threshold)
        assert.is_not_nil(prefs("fury").hs_threshold)
        assert.is_nil(prefs("fury").prot_cleave_rage)
        assert.is_not_nil(prefs("protection").prot_cleave_rage)
        assert.is_not_nil(prefs("protection").debuff_demoshout_enabled) -- shared by all three
        local pick = nodes.arms.args.core.args.activeSpec
        assert.are.same({ arms = "Arms", fury = "Fury", protection = "Protection" }, pick.values())
        assert.are.equal("arms", pick.get())
        pick.set(nil, "fury")
        settle(H)
        assert.are.equal(FURY, H.Hekili.State.spec.id)
        assert.are.equal("fury", H.Hekili.DB.profile.specChoice[CHAR])
        assert.is_true(nodes.arms.args.core.args.specHint.hidden() == false) -- Arms talents, Fury chosen
        H.Hekili:CmdLine("spec prot")
        settle(H)
        assert.are.equal(PROT, H.Hekili.State.spec.id)
    end)

    it("orders the Priorities list by spec", function()
        local H = boot()
        settle(H)
        H.Hekili:EmbedPackOptions() -- builds the Priorities tree into Hekili.Options.args.packs
        local packages = H.Hekili.Options.args.packs.plugins.packages
        local order = {}
        for _, name in ipairs({ "Arms", "Fury", "Protection" }) do
            order[#order + 1] = packages[name].order
        end
        assert.is_true(order[1] < order[2] and order[2] < order[3])
    end)
end)
```

  Append to `tests/Forever/packs_spec.lua`'s main describe (after the `use_off_gcd` loop):

```lua
    for class, load in pairs(LOADS) do
        it("registers every setting a priority reads on that priority's spec (" .. class .. ")", function()
            local w = load()
            local hits = {}
            for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", class)) do
                local key = type(p.spec) == "string" and p.spec:match(":(.+)$") -- nil: a pseudo-spec manifest
                for name in p.simc:gmatch("settings%.([%w_]+)") do
                    local s = w.settings[name]
                    local on = s ~= nil and (not s.specs or not key)
                    for _, k in ipairs(s and s.specs or {}) do
                        on = on or k == key
                    end
                    if not on then
                        hits[#hits + 1] = p.name .. ": settings." .. name
                    end
                end
            end
            table.sort(hits)
            assert.are.same({}, hits)
        end)
    end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted tests/Forever/spec_choice_spec.lua tests/Forever/packs_spec.lua`
Expected: FAIL (`nodes.arms` nil: the nodes are keyed by the client's pseudo-spec; `prefs("arms").hs_threshold` set).

- [ ] **Step 3: `EmbedSpecOptions` over the kit.** In `src/Hekili/Options/Options.lua`:
  - Before `function Hekili:EmbedSpecOptions( db )` (inside the same `do` block) add the two shared option tables:

```lua
    -- (per-spec plan) On every spec's page: the active spec (stored per character; the dominant talent tree until one
    -- is chosen) and the hint when the talents favor another.
    local activeSpecOption = {
        type = "select",
        name = "Active Specialization",
        desc = "The specialization Hekili Forever recommends for on this character. Your choice is kept until you change it "
            .. "(also |cFFFFD100/hekili spec name|r); with no choice yet, the talent tree with the most points is chosen once.",
        order = -2,
        width = 1.5,
        values = function()
            local v, kit = {}, Registry.Kit()
            for _, s in ipairs( kit and kit.trees or {} ) do v[ s.key ] = s.name end
            return v
        end,
        get = function() return Status.specKey end,
        set = function( _, val ) Hekili:SetSpecChoice( val ) end,
    }
    local specHintOption = {
        type = "description",
        name = function()
            local h = Hekili:GetSpecHint()
            return h and ( "Your talents favor |cFFFFD100" .. h.name .. "|r; the active specialization stays your choice until you pick another above." ) or ""
        end,
        fontSize = "medium",
        order = -1,
        width = "full",
        hidden = function() return Hekili:GetSpecHint() == nil end,
    }
```
  - In `EmbedSpecOptions`, replace the loop head

```lua
        local i = 1

        while( true ) do
            local id, name, description, texture, role = GetSpecializationInfo( i )

            if not id or id == 0 then break end
```
  with

```lua
        local kit = Registry.Kit()
        local trees = kit and kit.trees
        local i = 1

        while( true ) do
            local id, name, description, texture, role
            local tree = trees and trees[ i ]
            if trees then
                if not tree then break end
                id, name, texture, role = tree.id, tree.name, tree.texture, tree.role
            else
                id, name, description, texture, role = GetSpecializationInfo( i )
                if not id or id == 0 then break end
            end
```
  - `local sName = lower( name )` -> `local sName = tree and tree.key or lower( name )`.
  - Just before `db.plugins.specializations[ sName ] = options` insert:

```lua
                if tree then
                    options.args.core.args.activeSpec = activeSpecOption
                    options.args.core.args.specHint = specHintOption
                    if tree.unsupported then -- no priorities on Forever: the page says why nothing shows
                        options.args = {
                            core = {
                                type = "group",
                                name = "Specialization Settings",
                                order = 1,
                                args = {
                                    notice = {
                                        type = "description",
                                        name = "No priorities on Forever for " .. name .. ": Hekili Forever recommends nothing while this specialization is active.",
                                        fontSize = "medium",
                                        order = 0,
                                        width = "full",
                                    },
                                    activeSpec = activeSpecOption,
                                    specHint = specHintOption,
                                },
                            },
                        }
                    end
                end
```
- [ ] **Step 4: Priorities list by spec** (~l.4554): replace the loop header

```lua
        for pack, data in orderedPairs( self.DB.profile.packs ) do
            if data.spec and Registry.Specs()[ data.spec ] and not data.hidden then
```
  with

```lua
        -- by spec (its slot in the class), then by name (per-spec plan)
        local ordered = {}
        for pack, data in pairs( self.DB.profile.packs ) do
            if data.spec and Registry.Specs()[ data.spec ] and not data.hidden then ordered[ #ordered + 1 ] = pack end
        end
        table.sort( ordered, function( a, b )
            local sa = Registry.Specs()[ self.DB.profile.packs[ a ].spec ].slot or 0
            local sb = Registry.Specs()[ self.DB.profile.packs[ b ].spec ].slot or 0
            if sa ~= sb then return sa < sb end
            return a < b
        end )

        for _, pack in ipairs( ordered ) do
            local data = self.DB.profile.packs[ pack ]
            if data.spec and Registry.Specs()[ data.spec ] and not data.hidden then
```
  (the body and both `end`s unchanged).
  - The import's spec label (~l.4372): replace
    `get = function () return select( 2, GetSpecializationInfoByID( shareDB.imported.payload.spec or 0 ) ) or "No Specialization Set" end,`
    with
    `get = function () local s = Registry.Specs()[ shareDB.imported.payload.spec or 0 ]; return s and s.name or "No Specialization Set" end,`.

- [ ] **Step 5: `/hekili spec`.** `src/Hekili/Options/ChatCommands.lua`: add `spec = function () self:HandleSpecCommand( args ) end,`
  to `commandHandlers`, and after `HandlePriorityCommand`:

```lua
-- (per-spec plan) `/hekili spec [name]`: chooses this character's specialization (a key or a prefix of a name), or
-- lists them, the current one marked, with the talent hint.
function Hekili:HandleSpecCommand( args )
    local kit = Hekili.Engine.Registry.Kit()
    if not kit then
        self:Print( "No specializations: your class has no Hekili Forever pack." )
        return true
    end

    if args[2] then
        local name = table.concat( args, " ", 2 )
        local s = self:SetSpecChoice( name )
        if s then
            self:Print( format( "Specialization set to |cFFFFD100%s|r.", s.name ) )
            return true
        end
        self:Print( format( "No single specialization matches '%s'.", name ) )
    end

    local out = "Use |cFFFFD100/hekili spec name|r to choose your specialization. They are:"
    for _, s in ipairs( kit.trees ) do
        out = format( "%s\n - |cFFFFD100%s|r%s%s", out, s.key, s.id == Status.specID and " |cFF00FF00(current)|r" or "",
            s.unsupported and " (no priorities on Forever)" or "" )
    end
    local hint = self:GetSpecHint()
    if hint then out = format( "%s\nYour talents favor |cFFFFD100%s|r.", out, hint.name ) end
    self:Print( out )
    return true
end
```

- [ ] **Step 6: Split the Warrior preferences.** In `src/Hekili_Warrior/Warrior.lua` give each `spec:RegisterSetting`
  the specs whose priority reads it (from the `.simc` files) as trailing arguments after the option table:
  - `"arms"`: `adaptive_queueing_enabled`, `execute_queueing_enabled`, `ww_min_enemies`, `ww_cd_diff`,
    `hamstring_threshold`, `hamstring_cd_diff`;
  - `"arms", "fury"`: `debuff_sunder_enabled`, `debuff_sunder_max_stack`, `debuff_sunder_min_level`;
  - `"fury"`: `maintain_thunder_clap`, `rage_cap_threshold`, `hs_threshold`, `cleave_threshold`;
  - `"protection"`: `prot_heroic_strike_rage`, `prot_cleave_rage`, `challenging_shout_loose`;
  - none (all three): `debuff_demoshout_enabled`.
  The pattern, e.g.:

```lua
spec:RegisterSetting("hs_threshold", 40, {
    type = "range",
    name = "Fury: Heroic Strike Rage",
    desc = "The Fury priority recommends Heroic Strike on one target at or above this much rage.",
    width = "full",
    min = 0,
    max = 100,
    step = 1,
}, "fury")
```
  Drop the now-redundant `Fury: ` / `Protection: ` name prefixes only if the option tests do not pin them (grep
  `"Fury: ` in tests first; leave them when in doubt). Update the comment above the settings: "Each preference shows on
  the specs whose priority reads it (the trailing spec keys; none: every spec)."

- [ ] **Step 7: Run the specs, then the gate**

Run: `.lua/bin/busted tests/Forever/spec_choice_spec.lua tests/Forever/packs_spec.lua tests/Forever/style_options_spec.lua`
Expected: PASS. Gate commands with `TASK=3`: `gate lines identical` (each Warrior run reads its spec's settings, same
defaults).

- [ ] **Step 8: Commit**

```bash
git add src/Hekili/Options src/Hekili_Warrior/Warrior.lua tests/Forever/spec_choice_spec.lua tests/Forever/packs_spec.lua
git commit -m "feat(options): one page per spec with its own preferences, the active-spec dropdown and /hekili spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: profile migration, export and import by spec key (S)

**Files:**
- Modify: `src/Hekili/Engine/Schema/Trees.lua` (`ns.MigrateTrees`), `src/Hekili/Engine/Schema/Spec.lua`
  (`SettleSpecChoice`), `src/Hekili/Engine/Registry.lua` (`SpecShareKey`), `src/Hekili/Options/Options.lua`
  (`SerializeActionPack` ~l.7754, `Hekili.SerializeActionPack`), `tests/Forever/trees_spec.lua`,
  `tests/Forever/spec_choice_spec.lua`

**Interfaces:**
- Consumes: Task 2's `settings.specMigrated`, `state.spec.clientID`, `SettleSpecChoice`.
- Produces: `ns.MigrateTrees(specs, packs, done, kit, legacyID, active) -> boolean`; `Registry.SpecShareKey(id) -> string|nil`;
  `Hekili.SerializeActionPack(name) -> "Hekili:..."` (its payload `spec` is the share key).

- [ ] **Step 1: Write the failing specs.** Append to `tests/Forever/trees_spec.lua`'s `describe("Trees.lua", ...)`:

```lua
    describe("MigrateTrees", function()
        local function fresh()
            local specs = {
                [1491] = {
                    enabled = true,
                    aoe = 3,
                    package = "Mine",
                    settings = { hs_threshold = 55, ww_min_enemies = 4 },
                    abilities = { rend = { disabled = true } },
                },
            }
            for _, s in ipairs(K.trees) do
                specs[s.id] = { settings = {} }
                s.options.package = s.unsupported and nil or (s.key:gsub("^%l", string.upper))
            end
            local packs = { Mine = { spec = 1491, builtIn = false }, One = { spec = 100051, builtIn = true } }
            return specs, packs, {}
        end

        it("copies every legacy field to each supported spec, keeps the legacy table, and keeps a custom choice", function()
            local specs, packs, done = fresh()
            local active = K.specs.two
            assert.is_true(T.MigrateTrees(specs, packs, done, K, 1491, active))
            for _, key in ipairs({ "one", "two", "two_b" }) do
                local s = specs[K.specs[key].id]
                assert.are.same({ 3, 55, 4, true }, { s.aoe, s.settings.hs_threshold, s.settings.ww_min_enemies, s.abilities.rend.disabled })
            end
            assert.are_not.equal(specs[1491].settings, specs[K.specs.one.id].settings) -- deep copies
            assert.is_nil(specs[K.specs.heal.id].aoe) -- a spec with no priorities keeps its defaults
            assert.are.same({ "One", "Mine", "Two_b" }, {
                specs[K.specs.one.id].package,
                specs[active.id].package, -- the user's custom pick stays on the active spec
                specs[K.specs.two_b.id].package,
            })
            assert.are.equal(active.id, packs.Mine.spec)
            assert.are.equal(100051, packs.One.spec)
            assert.are.equal(55, specs[1491].settings.hs_threshold) -- kept for one release
            assert.is_true(done.TEST)
        end)

        it("runs once: a second pass changes nothing the user changed since", function()
            local specs, packs, done = fresh()
            T.MigrateTrees(specs, packs, done, K, 1491, K.specs.one)
            specs[K.specs.one.id].settings.hs_threshold = 60
            assert.is_false(T.MigrateTrees(specs, packs, done, K, 1491, K.specs.one))
            assert.are.equal(60, specs[K.specs.one.id].settings.hs_threshold)
        end)

        it("maps a built-in legacy choice 1:1 by spec and marks a class with no legacy profile as done", function()
            local specs, packs, done = fresh()
            specs[1491].package = "One"
            T.MigrateTrees(specs, packs, done, K, 1491, K.specs.two)
            assert.are.same({ "One", "Two" }, { specs[K.specs.one.id].package, specs[K.specs.two.id].package })
            local none = {}
            assert.is_true(T.MigrateTrees({}, {}, none, K, 1483, K.specs.one))
            assert.is_true(none.TEST)
        end)
    end)
```
  Append to `tests/Forever/spec_choice_spec.lua`:

```lua
describe("the legacy profile and shares (headless Warrior)", function()
    local mp = assert(loadfile("tools/make_pack.lua"))("lib")

    it("migrates the pseudo-spec profile once, keeping thresholds and a custom priority", function()
        local saved = {
            profiles = {
                Default = {
                    specs = { [1491] = { package = "Mine", settings = { hs_threshold = 55, ww_min_enemies = 4 } } },
                    packs = { Mine = { spec = 1491, builtIn = false, lists = { default = {} } } },
                },
            },
        }
        local H = boot({ saved = saved })
        settle(H)
        local p = H.Hekili.DB.profile
        assert.are.same({ 55, 55, 55 }, { p.specs[ARMS].settings.hs_threshold, p.specs[FURY].settings.hs_threshold, p.specs[PROT].settings.hs_threshold })
        assert.are.equal(4, p.specs[ARMS].settings.ww_min_enemies)
        assert.are.same({ "Mine", "Fury", "Protection" }, { p.specs[ARMS].package, p.specs[FURY].package, p.specs[PROT].package })
        assert.are.equal(ARMS, p.packs.Mine.spec)
        assert.is_true(p.specMigrated.WARRIOR)
        p.specs[ARMS].settings.ww_min_enemies = 2
        H.Hekili:SpecializationChanged()
        assert.are.equal(2, p.specs[ARMS].settings.ww_min_enemies)
        assert.are.equal(55, p.specs[1491].settings.hs_threshold)
    end)

    it("exports the spec as its share key and imports keys and legacy ids as this session's spec", function()
        local H = boot()
        settle(H)
        local str = H.Hekili.SerializeActionPack("Fury")
        assert.are.equal("WARRIOR:fury", mp.decode(str).spec)
        assert.are.equal(FURY, H.Hekili.DeserializeActionPack(str).payload.spec)
        local legacy = mp.encode({ name = "Old", version = 1, spec = 1491, desc = "", simc = "", lists = {} })
        assert.are.equal(ARMS, H.Hekili.DeserializeActionPack(legacy).payload.spec)
        local other = mp.encode({ name = "Ret", version = 1, spec = "PALADIN:retribution", desc = "", simc = "", lists = {} })
        assert.are.equal("PALADIN:retribution", H.Hekili.DeserializeActionPack(other).payload.spec)
    end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted tests/Forever/trees_spec.lua tests/Forever/spec_choice_spec.lua`
Expected: FAIL (`MigrateTrees` nil; `SerializeActionPack` nil).

- [ ] **Step 3: `ns.MigrateTrees`** in `Trees.lua` (after `ResolvePackSpecs`):

```lua
local function copy(v)
    if type(v) ~= "table" then
        return v
    end
    local t = {}
    for k, x in pairs(v) do
        t[k] = copy(x)
    end
    return t
end

--- Once per class (`done[kit.token]`), the legacy pseudo-spec profile `specs[legacyID]` (the client's id; kept for one
--- release) is copied into every supported spec of `kit`: each field (settings, thresholds, toggles, ability and item
--- options) but `package`; each spec's package becomes its default priority (Arms -> Arms); the legacy choice, when it
--- was a custom priority (not built in), stays the choice of `active` (the spec this login picked), and every custom
--- priority bound to the legacy id is rebound to `active`. Returns true when it ran.
function ns.MigrateTrees(specs, packs, done, kit, legacyID, active)
    if done[kit.token] then
        return false
    end
    done[kit.token] = true
    local old = legacyID and rawget(specs, legacyID)
    if type(old) ~= "table" then
        return true
    end
    for _, s in ipairs(kit.trees) do
        if not s.unsupported then
            local dst = specs[s.id]
            if not dst then
                dst = {}
                specs[s.id] = dst
            end
            for k, v in pairs(old) do
                if k ~= "package" then
                    dst[k] = copy(v)
                end
            end
            dst.package = s.options.package
        end
    end
    local chosen = old.package and rawget(packs, old.package)
    if chosen and not chosen.builtIn and active then
        specs[active.id].package = old.package
    end
    for _, p in pairs(packs) do
        if type(p) == "table" and p.spec == legacyID and not p.builtIn and active then
            p.spec = active.id
        end
    end
    return true
end
```

- [ ] **Step 4: Call it.** In `Spec.lua` `SettleSpecChoice`, after the `local pick, source = ...` line:

```lua
    ns.MigrateTrees( settings.specs, settings.packs, settings.specMigrated, kit, clientID, pick )
```

- [ ] **Step 5: Export by share key.** `Registry.lua`:

```lua
--- The share key ("WARRIOR:arms") export strings carry for spec `id`, or nil (a spec outside a class kit).
function Registry.SpecShareKey(id)
    return ns.SpecShareKey(class.specs[id])
end
```
  `Options.lua` `SerializeActionPack`: after `serial.payload.builtIn = false` add
  `serial.payload.spec = Registry.SpecShareKey( pack.spec ) or pack.spec`; after the function add
  `Hekili.SerializeActionPack = SerializeActionPack` (beside `Hekili.DeserializeActionPack`).

- [ ] **Step 6: Run the specs and the gate**

Run: `.lua/bin/busted tests/Forever/trees_spec.lua tests/Forever/spec_choice_spec.lua tests/Forever/settings_spec.lua`
Expected: PASS. Gate with `TASK=4`: `gate lines identical`.

- [ ] **Step 7: Commit**

```bash
git add src/Hekili/Engine/Schema/Trees.lua src/Hekili/Engine/Schema/Spec.lua src/Hekili/Engine/Registry.lua \
  src/Hekili/Options/Options.lua tests/Forever/trees_spec.lua tests/Forever/spec_choice_spec.lua
git commit -m "feat(specs): one-time copy of the pseudo-spec profile to every spec; shares carry the spec key

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Druid on NewClass (M)

**Files:**
- Modify: `src/Hekili_Druid/Druid.lua`, `src/Hekili_Druid/APLs/packs.lua`,
  `tests/Forever/helpers/druid_loop_world.lua`, `tests/Forever/{druid,engine_load,known_cache}_spec.lua` (as found),
  `tests/Forever/spec_choice_spec.lua`

**Interfaces:**
- Consumes: Tasks 1-4. Druid ids: Balance 100111, Feral 100112, Guardian 100113, Restoration 100114 (unsupported);
  the client's Druid pseudo-spec is 1483 (Constants' 1499 was a placeholder that never matched in game).

- [ ] **Step 1: Write the failing spec** (review focus 4 on a healing tree). Append to `spec_choice_spec.lua`:

```lua
describe("a Druid (headless)", function()
    local dw = require("Forever.helpers.druid_loop_world")
    local BALANCE, FERAL, GUARDIAN, RESTO = 100111, 100112, 100113, 100114

    it("gives Feral and Guardian their own specs on one tree, Feral by the talents and Guardian by choice", function()
        local H = headless.new({ character = dw.Feral.character(), pack = "Feral" })
        assert.are.same({}, H.loadErrors)
        settle(H)
        assert.are.equal(FERAL, H.Hekili.State.spec.id)
        local G = headless.new({ character = dw.Guardian.character(), pack = "Guardian" })
        assert.are.equal(GUARDIAN, G.Hekili.State.spec.id)
        assert.are.equal("guardian", G.Hekili.DB.profile.specChoice[CHAR])
        local p = G.Hekili.DB.profile
        assert.are.same({ BALANCE, FERAL, GUARDIAN }, { p.packs.Balance.spec, p.packs.Feral.spec, p.packs.Guardian.spec })
    end)

    it("leaves Restoration idle: no priority, no displays, its page the notice, no warning", function()
        local H = headless.new({ character = dw.Feral.character() })
        assert.are.same({}, H.loadErrors)
        settle(H)
        assert.is_not_nil(H.Hekili:SetSpecChoice("resto"))
        settle(H)
        assert.are.equal(RESTO, H.Hekili.State.spec.id)
        local p = H.Hekili.DB.profile
        assert.is_nil(rawget(p.specs[RESTO], "package"))
        assert.is_false(p.specs[RESTO].enabled)
        assert.is_true(H.Hekili.Class.initialized) -- the "no modules loaded" notice's guard
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        assert.are.same({}, H.errors)
        H.Hekili:EmbedSpecOptions()
        local node = H.Hekili.Options.plugins.specializations.restoration
        assert.is_not_nil(node.args.core.args.notice)
        assert.is_nil(node.args.core.args.enabled)
    end)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `.lua/bin/busted tests/Forever/spec_choice_spec.lua`
Expected: FAIL (the Druid registers pseudo-spec 1499).

- [ ] **Step 3: Convert `Druid.lua`.**
  - Replace `local DRUID_SPEC = 1499` and `local spec = Hekili:NewSpecialization(DRUID_SPEC, false, 132115) -- ability_druid_catform` (and the `DRUID_SPEC` comment) with

```lua
-- The class kit and its specs (ids the core's: Balance 100111, Feral 100112, Guardian 100113, Restoration 100114).
-- Feral and Guardian ride the Feral Combat tree: its points pick Feral; Guardian is chosen (/hekili spec guardian).
local spec = Hekili:NewClass("DRUID", {
    specs = {
        { key = "balance", name = "Balance", tree = 1, icon = 136096, role = "attack", ranged = true, package = "Balance" },
        { key = "feral", name = "Feral", tree = 2, icon = 132115, role = "attack", package = "Feral" },
        { key = "guardian", name = "Guardian", tree = 2, icon = 132276, role = "tank", package = "Guardian" },
        { key = "restoration", name = "Restoration", tree = 3, icon = 136041, role = "healer", unsupported = true },
    },
})
```
    Any other use of `DRUID_SPEC` in the file: grep it; replace by nothing (the core knows the ids).
  - Tree field: the awk of Task 2 Step 11 with `trees='Balance|Feral Combat|Restoration'`, plus the placeholder rule
    (the Forever-only placeholders' tree is unknown until the export):

```bash
awk -v trees='Balance|Feral Combat|Restoration' '
/^spec:RegisterTalents\(\{/ { inb = 1 }
inb && /^\}\)/ { inb = 0 }
inb && match($0, "^    -- (" trees ") \\(") { t++ }
inb && /^    -- Forever-only placeholders/ { t = 0 }
inb { sub(/= \{ 0, /, "= { " t ", ") }
{ print }' src/Hekili_Druid/Druid.lua > /tmp/specs/d.lua && mv /tmp/specs/d.lua src/Hekili_Druid/Druid.lua
```
    and update its talents comment the same way as the Warrior's.
  - Delete `spec:RegisterOptions({ package = "Feral" })`.
  - Settings' spec keys (from the `.simc` files and the Lua reads): `rip_cp`, `behind`: none (the class Lua reads
    them; every spec); `bite_finisher`, `feral_innervate_mana`: `"feral"`; `buffs`, `innervate`: `"feral", "balance"`;
    `dump_rage`, `use_enrage`, `lacerate_refresh`: `"guardian"`; `moonkin`, `trash_dots`, `starfire_filler`,
    `hurricane_targets`, `balance_innervate_mana`: `"balance"`.
  - `APLs/packs.lua`: `return { spec = 1499, packs = { "Feral", "Guardian", "Balance" } }` ->

```lua
return {
    class = "DRUID",
    packs = { "Feral", "Guardian", "Balance" },
    specs = { Feral = "feral", Guardian = "guardian", Balance = "balance" },
}
```
  - `make packs`.

- [ ] **Step 4: The Druid tests.**
  - `tests/Forever/helpers/druid_loop_world.lua`: `M.SPEC, M.CLASS_ID = 1499, 11` ->
    `M.CLIENT_SPEC, M.CLASS_ID = 1483, 11 -- the client's Druid pseudo-spec` and `specID = M.SPEC` ->
    `specID = M.CLIENT_SPEC`; in `content(name)` add `C.SPEC = ({ Balance = 100111, Feral = 100112, Guardian = 100113 })[name]`.
  - `tests/Forever/druid_spec.lua`: ~l.768 `assert.are.equal(w.specID, dofile("src/Hekili_Druid/APLs/packs.lua").spec)` ->
    `assert.are.equal(w.class, dofile("src/Hekili_Druid/APLs/packs.lua").class)`; ~l.813 `assert.are.equal(1499, w.specID)` ->
    `assert.are.equal("DRUID", w.class)`; ~l.832 `assert.are.same({ package = "Feral" }, w.options)` ->
    `assert.is_nil(w.options)`; ~l.871 `spec = env.class.specs[1499]` -> `spec = env.class.kit`.
  - `tests/Forever/engine_load_spec.lua` ~l.192 `specID = 1499,` -> `specID = 1483,`.
  - grep `1499` in `tests/` and fix any other reader the same way.
  - Add to `druid_spec.lua` (its recording load `w`):

```lua
    it("places each talent in its tree, the Forever-only placeholders at tree 0", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 3, 16, 16, 15 }, n)
    end)
```

- [ ] **Step 5: Run the specs, then the gate**

Run: `.lua/bin/busted tests/Forever/spec_choice_spec.lua tests/Forever/druid_spec.lua tests/Forever/engine_load_spec.lua tests/Forever/packs_spec.lua`
Expected: PASS. Gate with `TASK=5`: `gate lines identical` (Feral, Guardian (reported), Balance unchanged).

- [ ] **Step 6: Commit**

```bash
git add src/Hekili_Druid tests
git commit -m "feat(druid): Balance, Feral, Guardian and Restoration specs on NewClass

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Rogue, Paladin, Shaman and Hunter on NewClass; the pseudo-spec path removed (M)

**Files:**
- Modify: `src/Hekili_{Rogue,Paladin,Shaman,Hunter}/<Class>.lua` and `APLs/packs.lua`,
  `tests/Forever/helpers/{rogue,paladin,shaman,hunter}_world.lua`, `tests/Forever/{rogue,paladin,shaman,hunter}_spec.lua`,
  `tests/Forever/spec_choice_spec.lua`, `src/Hekili/Engine/Sim/Constants.lua`, `src/Hekili/Engine/Schema/Spec.lua`
  (NewSpecialization), `tools/make_pack.lua`, `tests/Forever/make_pack_spec.lua`,
  `tests/Forever/helpers/{load_warrior,load_druid}.lua`, `tests/boundary_spec.lua`

**Interfaces:**
- Consumes: Tasks 1-5. Ids: Rogue 100041-100043, Paladin 100021 (Holy, unsupported) - 100023, Shaman 100071
  (Elemental, unsupported until Day 7), 100072, 100073 (Restoration, unsupported), Hunter 100031-100033. Client
  pseudo-specs (for the worlds' `CLIENT_SPEC`): Paladin 1486, Rogue 1488, Shaman 1489, Hunter 1484.

- [ ] **Step 1: Write the failing spec** (review focus 4 on Paladin Holy; the Rogue spec per pack). Append to `spec_choice_spec.lua`:

```lua
describe("Rogue and Paladin specs (headless)", function()
    it("selects each Rogue pack's spec", function()
        local rw = require("Forever.helpers.rogue_world")
        for name, id in pairs({ Assassination = 100041, Combat = 100042, Subtlety = 100043 }) do
            local H = headless.new({ character = rw[name].character(), pack = name })
            assert.are.same({}, H.loadErrors)
            assert.are.equal(id, H.Hekili.State.spec.id, name)
        end
    end)

    it("leaves a Holy paladin idle with the notice and no warning", function()
        local pw = require("Forever.helpers.paladin_world")
        local H = headless.new({ character = pw.Retribution.character() })
        assert.are.same({}, H.loadErrors)
        settle(H)
        assert.are.equal("holy", H.Hekili:SetSpecChoice("holy").key)
        settle(H)
        assert.are.equal(100021, H.Hekili.State.spec.id)
        assert.is_nil(rawget(H.Hekili.DB.profile.specs[100021], "package"))
        assert.is_false(H.Hekili.DB.profile.specs[100021].enabled)
        assert.is_true(H.Hekili.Class.initialized)
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        assert.are.same({}, H.errors)
        H.Hekili:EmbedSpecOptions()
        assert.is_not_nil(H.Hekili.Options.plugins.specializations.holy.args.core.args.notice)
    end)
end)
```
  (`paladin_world`'s per-pack table: use its actual export, `pw.Retribution` or `pw.content("Retribution")`; read
  the world file's last lines.)

- [ ] **Step 2: Run it to verify it fails**

Run: `.lua/bin/busted tests/Forever/spec_choice_spec.lua`
Expected: FAIL.

- [ ] **Step 3: Full talent blocks from the DB2.** Write `/tmp/specs/talent_block.sh` (a one-off, not committed):

```sh
#!/bin/sh
# talent_block.sh CLASS: a RegisterTalents body from `wowdb talents CLASS`: { tree, rank-1 spell, max rank }, trees
# numbered in wowdb's order (the client's tab order), keys snake_case of the name (repeats get _2, _3; a talent with no
# name in the DB2 gets talent_<spell>: nothing reads these keys but the dominant-tree count).
~/.local/share/wow-db2/bin/wowdb talents "$1" | awk -F'\t' '
NR == 1 { next }
{
    if ($3 != tab) { tab = $3; t++; printf "    -- %s (tree %d)\n", tab, t }
    max = 0; for (i = 7; i <= 11; i++) if ($i + 0 > 0) max++
    key = tolower($6); gsub(/-/, " ", key); gsub(/[^a-z0-9 ]/, "", key); gsub(/ +/, "_", key)
    if (key == "") key = "talent_" $7
    if (++seen[key] > 1) key = key "_" seen[key]
    printf "    %s = { %d, %s, %d },\n", key, t, $7, max
}'
```
  Expected counts: Rogue 51 (Assassination 15, Combat 19, Subtlety 17), Paladin 44, Shaman 46, Hunter 46; each tab
  header printed once. For each class replace the `spec:RegisterTalents({ ... })` block body with the script's output,
  then append the class's existing Forever-only entries under `    -- Forever-only (tree unknown until the export)`
  with tree 0 (`= { 0, ... }`, as they are now): Rogue `flawless_execution`, `thousand_cuts`, `cutthroat`; Paladin
  `twist_of_light`, `swift_judgement`, `instrument_of_law`. Every key the file registered before must still be there
  (Rogue `improved_sinister_strike`, `improved_slice_and_dice`, `relentless_strikes`, `improved_expose_armor`; Paladin
  `holy_shock`, `holy_shield`, `seal_of_command`: the script produces these names). Shaman and Hunter registered none:
  their block is new (`spec:RegisterTalents({` ... `})` after the abilities). Rename Rogue's `setup` to
  `setup_talent`: `setup` is an identifier in the harness core (`tests/Game/harness/world_spec.lua`) and
  `tests/boundary_spec.lua` would flag it. After the edit run `.lua/bin/busted tests/boundary_spec.lua`; rename any
  other flagged one-word talent key the same way (`<key>_talent`).

- [ ] **Step 4: NewClass per class** (the Warrior pattern; delete each `<CLASS>_SPEC` local, its comment and the
  class's `spec:RegisterOptions({ package = ... })`):

```lua
-- Rogue.lua
local spec = Hekili:NewClass("ROGUE", {
    specs = {
        { key = "assassination", name = "Assassination", tree = 1, icon = 132292, role = "attack", package = "Assassination" },
        { key = "combat", name = "Combat", tree = 2, icon = 132090, role = "attack", package = "Combat" },
        { key = "subtlety", name = "Subtlety", tree = 3, icon = 132320, role = "attack", package = "Subtlety" },
    },
})

-- Paladin.lua
local spec = Hekili:NewClass("PALADIN", {
    specs = {
        { key = "holy", name = "Holy", tree = 1, icon = 135920, role = "healer", unsupported = true },
        { key = "protection", name = "Protection", tree = 2, icon = 135893, role = "tank", package = "Protection" },
        { key = "retribution", name = "Retribution", tree = 3, icon = 135873, role = "attack", package = "Retribution" },
    },
})

-- Shaman.lua (Elemental gets its priority on Day 7, class-completion Task 17: it drops `unsupported` and adds package)
local spec = Hekili:NewClass("SHAMAN", {
    specs = {
        { key = "elemental", name = "Elemental", tree = 1, icon = 136048, role = "attack", ranged = true, unsupported = true },
        { key = "enhancement", name = "Enhancement", tree = 2, icon = 136051, role = "attack", package = "Enhancement" },
        { key = "restoration", name = "Restoration", tree = 3, icon = 136052, role = "healer", unsupported = true },
    },
})

-- Hunter.lua
local spec = Hekili:NewClass("HUNTER", {
    specs = {
        { key = "beast_mastery", name = "Beast Mastery", tree = 1, icon = 132164, role = "attack", ranged = true, package = "BeastMastery" },
        { key = "marksmanship", name = "Marksmanship", tree = 2, icon = 132222, role = "attack", ranged = true, package = "Marksmanship" },
        { key = "survival", name = "Survival", tree = 3, icon = 132215, role = "attack", ranged = true, package = "Survival" },
    },
})
```
  Settings' spec keys: Rogue `backstab` -> `"subtlety"`, the others (`trash_dots`, `expose_armor`, `vanish`,
  `ambush_opener`, `poisons`) none; Paladin `consecration_mana`, `exorcism_mana` -> `"retribution"`; Shaman `imbue`
  and the three `manaSetting` lines -> `"enhancement"` (give `manaSetting` a trailing `...` passed to
  `spec:RegisterSetting(key, 0, {...}, ...)`); Hunter `arcane_shot_mana` -> `"beast_mastery", "marksmanship"`,
  `wing_clip_mana` -> `"survival"` (the same `manaSetting(..., ...)` change). Each header comment's "pseudo-spec"
  wording becomes the NewClass one.
  Manifests:

```lua
-- Rogue
return { class = "ROGUE", packs = { "Combat", "Assassination", "Subtlety" }, specs = { Combat = "combat", Assassination = "assassination", Subtlety = "subtlety" } }
-- Paladin
return { class = "PALADIN", packs = { "Retribution", "Protection" }, specs = { Retribution = "retribution", Protection = "protection" } }
-- Shaman
return { class = "SHAMAN", packs = { "Enhancement" }, specs = { Enhancement = "enhancement" } }
-- Hunter
return { class = "HUNTER", packs = { "BeastMastery", "Marksmanship", "Survival" }, specs = { BeastMastery = "beast_mastery", Marksmanship = "marksmanship", Survival = "survival" } }
```
  (StyLua will wrap them.) `make packs`.

- [ ] **Step 5: The class tests and worlds.** For each of `rogue_world`, `paladin_world`, `shaman_world`,
  `hunter_world`: `M.SPEC, M.CLASS_ID = <pseudo>, <id>` -> `M.CLIENT_SPEC, M.CLASS_ID = <pseudo>, <id>`,
  `specID = M.SPEC` -> `specID = M.CLIENT_SPEC`, and in the per-pack `content(name)` `C.SPEC = <that pack's spec id>`.
  In `rogue_spec.lua` (~l.77-78), `paladin_spec.lua` (~l.90-91), `shaman_spec.lua` (~l.82-83), `hunter_spec.lua`
  (~l.73-74): `assert.are.equal(<pseudo>, w.specID)` -> `assert.are.equal("<CLASS>", w.class)` and
  `assert.are.same({ package = "<Pack>" }, w.options)` -> `assert.is_nil(w.options)`; their direct `specID = <pseudo>`
  characters (~l.292-311) stay (they are the client's id). Add to each class spec, as for the Warrior:

```lua
    it("places every DB2 talent in a tree and keeps the Forever-only ones at tree 0", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same(EXPECTED, n)
    end)
```
  (`w` is the spec file's recording load.) `EXPECTED` per class (wowdb per-tab counts plus the Forever-only lines):
  Rogue `{ [0] = 3, 15, 19, 17 }`, Paladin `{ [0] = 3, 14, 15, 15 }`, Shaman `{ [0] = 0, 15, 16, 15 }`, Hunter
  `{ [0] = 0, 16, 14, 16 }` (Day 5's Hunter may register Forever-only talents by then: add them at tree 0 and count
  them in `[0]`).

- [ ] **Step 6: Remove the pseudo-spec path.**
  - `src/Hekili/Engine/Sim/Constants.lua`: delete every `ns.Specializations` row with a `forever = ...` field (1484,
    1486, 1488, 1489, 1491, 1499) and their comments. (Counts only fall: `tests/boundary_baseline.lua` needs no
    regeneration.)
  - `Spec.lua` `NewSpecialization`: delete the `local forever = ...` line, its comment and the
    `if forever then ... elseif` branch, leaving `if Hekili.IsForever() and specID > 0 then ... else ... end`; its doc:
    "Spec 0 (`all`) only; class packs call Hekili:NewClass".
  - `tools/make_pack.lua`: delete the `else p.spec = def.spec` branch; a manifest without `class` errors
    `packs.lua: no class`. `tests/Forever/make_pack_spec.lua` ~l.100: the scratch manifest
    `'return { spec = 1, packs = { "Bad" } }\n'` -> `'return { class = "ZZZ", packs = { "Bad" }, specs = { Bad = "bad" } }\n'`;
    add `hunter = "Hunter"` to its `CLASSES` if Day 5 has not.
  - `load_warrior.lua`, `load_druid.lua`: delete `function hekili:NewSpecialization(id)` and the `w.specID` doc.
  - `tests/boundary_spec.lua` `PUBLIC`: delete `NewSpecialization = true`.
  - grep: `grep -rn "NewSpecialization\|_SPEC\b\|w.specID" src/Hekili_* tests` must print nothing (NewSpecialization
    stays only in `Spec.lua`).

- [ ] **Step 7: Run the specs, then the gate**

Run: `.lua/bin/busted tests/Forever/spec_choice_spec.lua tests/Forever/rogue_spec.lua tests/Forever/paladin_spec.lua tests/Forever/shaman_spec.lua tests/Forever/hunter_spec.lua tests/Forever/make_pack_spec.lua tests/Forever/packs_spec.lua tests/boundary_spec.lua`
Expected: PASS. Gate with `TASK=6`: `gate lines identical` (Combat, Assassination, Subtlety, Retribution,
Protection, Enhancement, Beast Mastery, Marksmanship, Survival unchanged).

- [ ] **Step 8: Commit**

```bash
git add -A src tools tests
git commit -m "feat(packs): Rogue, Paladin, Shaman and Hunter specs per talent tree; the pseudo-spec path removed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: docs (S)

**Files:**
- Modify: `docs/dev/layout.md`, `docs/dev/architecture.md`, `docs/superpowers/plans/2026-10-18-class-completion.md`

- [ ] **Step 1: `docs/dev/layout.md`.** The manifest sentence `(`{ spec = ..., packs = { ... } }`, no date)` ->
  `(`{ class = "<TOKEN>", packs = { ... }, specs = { [<Pack>] = <spec key> } }`, no date)`. The Paladin P1 and Shaman
  S1 checkpoint lines: the pseudo-spec id no longer selects anything; ask instead "the client's pseudo-spec id (only
  the legacy profile migration reads it) and the talent tree the dominant-tree pick chooses for your build (Snapshot
  `spec:` line)". Add the in-game "Specs" checklist below to the "In game" section.
- [ ] **Step 2: `docs/dev/architecture.md` §3** (the content surface): replace the `Hekili:NewSpecialization(id, ...)`
  bullet with `Hekili:NewClass(token, { specs = {...} })` (the kit, the spec fields, the ids, `RegisterTalents`'
  tree field, `kit:RegisterSetting(key, value, option, ...)`'s spec keys, `unsupported`), the allowlist line ~l.152
  (`NewClass/NewShared/NewRace`), and a paragraph "Active spec": stored choice per character
  (`profile.specChoice["Name-Realm"]`), else the dominant tree stored once, else the first supported spec; respec
  hint; `/hekili spec`; the one-time migration (`profile.specMigrated`); share keys in exports. §6 (the pack
  pipeline): the manifest's `class` and `specs`, payload `spec = "<TOKEN>:<key>"`.
- [ ] **Step 3: The class-completion plan, Days 6-7**, each task written per spec:
  - Task 14 Mage: `Hekili:NewClass("MAGE", { specs = { arcane (tree 1, 100081), fire (2, 100082), frost (3, 100083) } })`,
    every talent from `wowdb talents MAGE` with its tree (the Task 6 script), preferences with spec keys, manifest
    `{ class = "MAGE", packs = { "Arcane", "Fire", "Frost" }, specs = {...} }`, the gate per spec's pack.
  - Task 15 Warlock: affliction/demonology/destruction (100091-100093), same pattern.
  - Task 16 Priest: discipline (100051, `unsupported`), holy (100052, package `Smite`: the Smite build rides the Holy
    tree), shadow (100053, package `Shadow`); manifest `specs = { Shadow = "shadow", Smite = "holy" }`.
  - Task 17 Elemental: drop `unsupported` from Shaman's elemental entry, add `package = "Elemental"`, manifest
    `Elemental = "elemental"`, its preferences with `"elemental"` (and `imbue` shared if Elemental reads it).
  - The checklist "New addon": `NewClass` with all three trees (healing trees `unsupported`), full talent block.
- [ ] **Step 4: Verify and commit**

Run: `make check`
Expected: PASS.

```bash
git add docs
git commit -m "docs: specs per talent tree (NewClass, the active spec, migration); Days 6-7 written per spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] Whole-branch review (superpowers:requesting-code-review / `/ponytail-review`) against this plan, the Decisions and
  the Review Focus; fix findings in the owning task's files.
- [ ] `make check` green; the gate commands with `TASK=final`: `gate lines identical`; `make bench` reported (the
  Update path is untouched: expect no change).
- [ ] `tests/Forever/fixtures/{classic_draw,timeline_draw,arms_recs_seeds1-3,classic_options}.lua` unchanged:
  `git diff --stat origin/forever -- tests/Forever/fixtures` prints nothing.

### In game (user: Warrior, Rogue and Druid characters; full client restart not needed, `/reload` after the update)
1. **Rogue:** `/hekili` shows Assassination, Combat and Subtlety nodes with their icons; Subtlety's page has "Backstab
   Builder", Combat's does not; shared preferences ("Bleeds on Trash", "Vanish to Re-open") on all three.
2. **First login after the update (any of the three):** the active spec is the tree with the most points (Snapshot:
   `spec: <key> (dominant)` on the first pass, `(stored)` after a `/reload`); the old Rogue thresholds (e.g. "Bleeds on
   Trash" if you changed it) appear in all three Rogue specs; your previous priority choice is kept.
3. **Override:** pick another spec in "Active Specialization" (or `/hekili spec subtlety`); the displays switch to its
   priority; `/reload` keeps it; `/hekili spec` lists the specs with "(current)" and, when your talents favor another
   tree, "Your talents favor X". The page shows the same hint. No repeated chat or lag on talent changes.
4. **Priorities list:** grouped by spec (the Warrior's Arms, Fury, Protection in that order), each with its spec icon;
   exporting Fury and importing it on the same character binds it to Fury.
5. **Druid:** Feral selected for a Feral build; `/hekili spec guardian` switches to the bear priority; choosing
   Restoration hides the displays, its page says "No priorities on Forever for Restoration", and no "modules loaded"
   warning appears when casting.
6. **Warrior:** Arms/Fury/Protection recommendations as before; Fury's page carries the Fury thresholds only.
7. Report the Snapshot's first lines (`VSCopy`) for each character if anything differs.

## Self-review (done while writing)
- Decisions: stored choice wins (Task 2 `PickSpec` "stored"); dominant stored on first selection (`SettleSpecChoice`);
  dropdown and command (Task 3); respec hint, no switch (Task 2 test, `CheckForTalentUpdate`); three trees per class,
  healing trees as notices (Tasks 3, 5, 6); Druid gets four (documented above); migration copies settings to every
  spec, packs 1:1, previous custom choice kept on the active spec (Task 4: the outline's "previous class-level choice
  otherwise" applied to a custom pack, so no selection is dropped); exports carry the spec key (Task 4).
- Names used across tasks: `ns.PickSpec`, `ns.SpecHint`, `ns.TreePoints`, `ns.DominantTree`, `ns.TreeSpecID`,
  `ns.SpecShareKey`, `ns.SpecFromShare`, `ns.ResolvePackSpecs`, `ns.MigrateTrees`, `ns.CharKey`,
  `Hekili:NewClass`, `Hekili:SetSpecChoice`, `Hekili:GetSpecHint`, `Hekili:SettleSpecChoice`, `Registry.Kit`,
  `Registry.SpecFromShare`, `Registry.SpecShareKey`, `state.spec.clientID/kitID/source`,
  `settings.specChoice/specMigrated`.
- Known limit: `Options/DevTools.lua` still reads the client's spec for its generated text (cosmetic, not migrated).
