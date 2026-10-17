# Headless recommendation loop: stock Hekili pressing its own display against the harness's world (design, 2026-10-16)

Status: proposed, awaiting the user's decisions (§10). Base: forever 7bbb16ad. Paths under `src/Hekili/` unless they
start with `tests/`, `tools/` or `docs/`. Inputs: the headless spike (`tmp/headless/findings.md`, "SPIKE": GO, no src
change; its scratch `shell.lua`, `run.lua`, `loop.lua`), the combat harness design
(`docs/superpowers/specs/2026-10-16-combat-harness-and-group-attribution.md`, "H"; §3 the five layers, §9 as built),
`tests/Virtual/harness/*.lua`, `tests/Virtual/State/helpers/fake_api.lua`, `tests/Forever/helpers/{engine,load_warrior}.lua`,
`Core.lua:1547` (`Hekili.Update`) and the Arms list (`tools/packs/warrior.lua`).

**What it answers.** H §3.1's "later extension": does stock Hekili, reading Forever's secret-gated client through the
facade and VirtualState, recommend what it would recommend if it could see everything, and does pressing its first
icon play the character as well? Today every test checks the belief (VirtualState) or the class file in isolation;
nothing closes the loop through the real APL compiler, `state.reset`, the queue and a press.

**The boundary, binding for every section.** The shell, the loop, the observer and the world stay class-neutral: no
class, spell, aura, talent, stance or rotation name, no spell ID (the house rule H applies to `Virtual/**` and the harness; this repo has no scan for it,
so `headless_spec` greps the new harness files for the class tokens and the Warrior ability keys). Everything Warrior-specific (the ability-to-world mapping, the talents, the pack name, the
uptime list, the gates' Arms scenario) lives in `tests/Forever/`. Each section ends with "Owns".

## 1. The shell as a committed test helper (`tests/Virtual/harness/headless.lua`)

SPIKE's `shell.lua` (985 lines, scratch) becomes the helper, cleaned, not redesigned.

### 1.1 One instance = one environment (decision of this design)
`headless.new(o)` returns an instance `H = { env, api, ctl, ns, Hekili, frames, timers, misses, errors }`. Every Hekili
chunk (TOC Lua, embeds' `Script` lines) is loaded with `loadfile` + `setfenv(chunk, H.env)`; `H.env._G = H.env`; the
env's `loadstring` wraps the real one and `setfenv`s its result to `H.env` (Lua 5.1's `loadstring` otherwise binds the
real globals: Scripts.lua compiles the APL with it). `H.env`'s `__index` chain: the instance's own client functions
(fake_api's `api`, copied per instance: each has its own `ctl`) -> the shared read-only stubs table (§1.2) -> the Lua
standard library -> the miss counter (§1.4).

Rationale: the oracle (§4) needs **two** Hekili instances alive in lockstep in one busted process, and Hekili is
global (`Hekili`, `LibStub`, `HekiliDisplay*`, `HekiliDB`, frame names). A per-instance environment keeps each set of
globals apart and leaves the real `_G` untouched, so nothing needs restoring. The one thing shared across instances
is the string metatable's methods (`string.trim`, `string.split`, which WoW adds and Hekili calls as `s:trim()`):
idempotent additions to the real `string` table, listed in the helper's header as its only process-wide effect.
Rejected: swapping `_G` contents per cycle (thousands of keys per swap at 10 Hz) and a second Lua process (no busted).

### 1.2 Every stub in one file
The SPIKE inventory, grouped as it is there: WoW Lua aliases (`floor`, `format`, `wipe`, `strsplit`, `tostringall`,
`debugprofilestop` = `os.clock() * 1000`, `debugstack`, `hooksecurefunc`, `geterrorhandler`, `Mixin`); WoW's `xpcall`
with extra arguments (AceAddon's safecall); library reads (`GetCurrentRegion`, `C_UIFileAsset`, `Minimap`,
`ClassicExpansionAtLeast/AtMost`, `GetNumSpecGroups`, pools, font objects); Hekili's load reads (`Enum`, `LOCALIZED_CLASS_NAMES_*`,
`RAID_CLASS_COLORS`, `MAX_PLAYER_LEVEL`, `CR_*`, `INVTYPE_*`, `Item:CreateFromItemID`, `Spell:CreateFromSpellID`,
`UIParent`, `GameTooltip`, `DEFAULT_CHAT_FRAME`, `BackdropTemplateMixin`, `PixelUtil` returning numbers,
`AddonCompartmentFrame`, `C_AddOns.GetAddOnMetadata` answering the TOC's `## Version`). The **stub frame**: real event
registration and `SetScript`/`GetScript`, `Set*`/`Show`/`Create*` verbs no-op, `Get*` a stub frame except a short list of
numeric getters (`GetSize`, `GetWidth`, `GetHeight`, `GetScale`...), `Is*`/`Has*` false, `CreateFontString(name)` defining
the global name in the env. Everything here is load or UI scaffolding; **client answers that a secret could touch
belong in fake_api, not here** (§6.2), so the shell never decides what is secret.

### 1.3 Loader, clock, timers, login
- **Loader:** `Hekili.toc` in order; an `.xml` line walks its `Script`/`Include` tags; a file whose main chunk raises is
  recorded in `H.loadErrors` and the load continues. `UI/PopupSlider.xml` (XML frames) is the one skipped file, listed.
- **Clock:** `ctl.now` is the only time (`GetTime`); `C_Timer.After/NewTimer/NewTicker` queue callbacks by due time,
  run by `H.RunTimers(now)` (Targets.lua:1112, :1581, Events.lua:960 and the 5 s ticker run on it). No wall clock
  reaches Hekili except `debugprofilestop`, which only budgets frame updates the loop never uses (§2.2).
- **Character before login** (`H.character(c)`, data the content passes in): class token, level, known spells,
  talent traits, power type and max, weapon speeds, forms. VirtualState builds its spellbook at `SpecializationChanged`,
  so these are set before login.
- **Login:** `ADDON_LOADED("Hekili")` (OnInitialize, AceDB profile), `IsLoggedIn` true, `PLAYER_LOGIN` (OnEnable,
  `VS.Start(_G)`), `PLAYER_ENTERING_WORLD(true, false)`, then `H.RunTimers(now)`; then the content selects the pack
  (`profile.specs[id].package = name`). `H.errors` collects `Hekili:Error` (`ns.Error` wrapped, plus `Hekili.ErrorKeys`).
- **Cost:** boot 0.11 s CPU (SPIKE 6). One boot per instance per busted `insulate` block; fights in a block run in
  sequence on the same boot with a 30 s out-of-combat gap between them (consecutive pulls, as in game). `o.fresh`
  reboots per fight for a test that needs independence.

### 1.4 The miss counter
Every env read that falls through to the counter is recorded by phase (`load`, `login`, `run`) with its count. After
each fight the loop asserts `run` misses are a subset of `KNOWN_RUN_NILS`, each entry with its file:line and why:
`overcap` (State.lua:1386), `id` (State.lua:3766), `listName` (Core.lua:1992), `alphaCheck` (UI.lua:1121), `squawk`
(Scripts.lua:1032): upstream reads of an unset global, all nil in game too. `load` and `login` misses are asserted
against `KNOWN_LOAD_NILS` (feature probes the client answers nil, e.g. a retail-only namespace; the five facade rows
absent on Forever). A new name fails the run: a nil read at recommendation time can silently skew a condition (SPIKE
risk 10), so the stub or the allow-list must be decided by a person.

Owns: `tests/Virtual/harness/headless.lua` (new), `tests/Virtual/harness/headless_spec.lua` (new, fast).

## 2. The loop (`tests/Virtual/harness/loop.lua`)

### 2.1 Prerequisites in the harness core
1. **Incremental observer.** `observer.new(W, k)` returns `obs` with `obs.step(tEnd)`: it consumes the truth events the
   world appended since the last step and returns (into the drive's preallocated arrays) the client events at or before
   `tEnd`, in the batch order (time, then sequence); entries scheduled later (the `usableDelay`, the +1 ms strike wound)
   stay pending for the next step. `observer.observe(W, k)` stays as `new` + one `step(math.huge)`, so every existing
   gate reads the same code.
2. **No RNG in observation.** Today `observe` draws from `W.rng` twice: the same-ms avoid (`k.sameMs`) and the strike
   frame's order. Both move into the behaviours: `behaviours.melee` rolls them when it emits the swing or strike and
   records them on the truth event (`ev.sameMs = "DODGE"`, `ev.order = 1|2`); the observer only reads them. The RNG is
   then consumed by behaviours alone, so a press at tick t changes the future fight and nothing about how the past is
   observed, and batch and incremental streams of one seed are identical (a test). The existing gates' fights change
   (the world draws more per swing): the plan re-measures §9's gate table of H at the same bounds and records it.
3. **Usability from the content.** The observer's fake-spec `M.COSTS` becomes the knob `k.usable = { { spellID,
   fn(W, e) -> bool }... }` (the fake spec's list stays the default); evaluated after each truth event that changes our
   power, an aura or a target's health; a flip fires `SPELL_UPDATE_USABLE` after `k.usableDelay`, a spend at once (as
   now). The `@truth` op also records our true power for the metrics, as now.
4. **Runtime presses: `W.press(e, key, p)`.** The world's verb for "the player pressed this now". `p` is the content's
   resolved press: `{ spell, cost, cooldown, gcd, offGcd, requires = fn(W, e) -> ok, why, effect = fn(W, e) }`.
   Checked against the TRUE state in order: GCD (`e.gcdUntil`), cooldown (`e.cdUntil[key]`), cost (`e.power`),
   `requires`; a refusal returns `false, reason` (`gcd`, `cooldown`, `cost`, `requires:<why>`) and changes nothing; an
   accept spends, starts the GCD and cooldown, emits the `cast` truth event (`spell` a real ID passes through the
   observer as is) and runs `effect`, which uses only generic world verbs: `W.applyAura(dst, auraID, duration,
   stacks, maxStacks)`, `W.queueStrike(e, p)` (the existing on-next-swing path), `W.dot(e, dst, every, n, amount)`,
   `W.hit(e, dst, amount, school)` (an instant outcome rolled against the victim), `W.gain(e, amount)`. Auras expire on
   the world clock and are visible to the observer: ours on the player plain (`ctl.auras.player`, `UNIT_AURA`), the
   target's raising in combat (`auraError`, as now).
5. **Kills.** Entities take a finite `health` (`o.mobHealth`, a scenario knob); at 0 the world emits `kill`, the observer
   fires `UNIT_DIED`-equivalent client changes (target gone, `PLAYER_REGEN_ENABLED` when no attacker is left). A fight
   ends at the kill or at `duration`.

### 2.2 One tick (period `TICK = 0.2` s, 5 Hz, the in-game combat rate; `o.hz = 10` the option)
1. `W.run(t)`: behaviours advance (swings, mob hits, DoT ticks, aura expiries, the queued strike).
2. For each instance (ours, the oracle): `obs.step(t)` fires its events through the instance's `ctl` (each event at its
   own time: `ctl.now = event.t`; the `@` ops through drive.lua's `op`, exported as `drive.op` for this).
3. `ctl.now = t`; the VirtualState frame's `OnUpdate`; `H.RunTimers(t)`.
4. `Hekili.Update()` called directly under `xpcall` (a raise counts as an engine error). Never Hekili's frame update:
   it is wall-clock budgeted (`debugprofilestop`) and would make runs machine-dependent.
5. Read `ns.UI.Displays.Primary.Recommendations[1..3]` (`actionName`, `actionID`, `time`) into preallocated slots.
6. **Press policy** (`behaviours.recommended`, class-neutral): if our first icon's `time` <= `o.react` (default 0.05 s:
   shown as ready), resolve it through the content's `resolve(key, H)` (§7) and call `W.press(us, key, p)`. One attempt
   per tick, first icon only (not the first pressable one, as the SPIKE prototype did: a player presses what the big
   icon shows). A refusal is counted with its reason (§5) and the player tries again next tick if the icon stays.
   Optional `o.reaction` (default 0) delays the press by that many seconds (a human).
7. Metrics read the truth and both queues for this tick (§5).

Precombat: the fight's world starts 3 s before the pull with the target selected and in range; the policy presses
precombat recommendations (buffs) then. No positions: every target is in melee range (shortcut: movement abilities
apply their resource and aura effects and start combat; add positions when a ranged or gap-closer gate needs them).

### 2.3 Two runs per fight
- **Run A (scored):** our instance drives the world; the oracle instance shadows it on the same truth (its presses are
  not made). Agreement, reaction, flicker, refusals and engine health come from A.
- **Run B (baseline):** the same seed, a fresh world, the **oracle** instance drives it (its first icon pressed by the
  same policy). Outcome metrics (damage, time at full power, GCD idle, debuff uptime) compare A with B. The worlds
  diverge after the first different press; that is the point (what the belief's mistakes cost).

Cost (SPIKE 6 and its cost line: ~2.2 ms per `Update`): per tick A runs two instances and B one, so a 3-minute fight
at 5 Hz is 900 ticks x 3 `Update`s ≈ 6 s; at 10 Hz ≈ 12 s. Hence D1 and D2.

Owns: `tests/Virtual/harness/{observer,behaviours,world,drive,scenarios}.lua` (the five prerequisites, the policy, the
`mobHealth`/kill knobs), `tests/Virtual/harness/loop.lua` (new: `loop.fight(content, o, seed)` returns the per-fight
tallies; `loop.fights(content, o, n)` sums them).

## 3. Allocation and performance
The harness is test code and allocates (H §3.6). The loop's per-tick reads (queue slots, metric counters) use
preallocated arrays so the CPU measurement (§5) measures Hekili, not the harness. The existing 0-byte gate for
VirtualState (H `alloc_spec`) is unchanged and stays on the fake spec; Hekili's own per-cycle allocation is not gated
(stock Hekili allocates; out of scope).

## 4. The oracle: a second Hekili fed the true state
A second `headless.new` instance with the same character, booted and stepped in lockstep (§2.2), whose observer runs
with `k.plain = true`:
- power plain in combat (`ctl.power[pt]` = the true value after every truth change; no `SECRET`);
- no `auraError`: the target's auras listed as the world holds them (ours and others'), with true expiries;
- cooldowns plain (`startTime`/`duration` numbers from the world), usability answered at once (`usableDelay = 0`);
- every other read as ours (the same events, the same targets).

VirtualState in the oracle then pins on every plain read (the Resources family's `readable` path, Facade's `hybrid`
raw answers), so its belief equals the truth. **Self-check, gated:** the oracle's believed power equals the true power
at every tick of every fight, and its believed target debuffs match the world's (up and stacks). If that check fails
on some field, the plain path is not taken for it and the oracle is not an oracle: the fix is an oracle-only override
of that facade row with the raw client answer at the instance's load (a knob of `headless.new`, `o.raw = { names }`),
not a change in src. What "true" covers is D4.

The oracle is the reference, not a perfect player: its own APL choices are scored only against run B's outcomes.

Owns: `tests/Virtual/harness/observer.lua` (`k.plain`), `headless.lua` (`o.raw`), `loop.lua` (lockstep, run B).

## 5. Metrics and gates (`tests/Virtual/harness/loop.lua` tallies; `metrics.lua` style lines)

### 5.1 Metrics (in-combat ticks unless stated)
- **First-icon agreement:** share of ticks where both queues are non-empty and ours[1].actionName ==
  oracle[1].actionName. The **confusion table** (oracle's key x ours, counts) is printed in every failure message.
- **Cycles to react:** for each change of the oracle's first icon to X that lasts >= 2 ticks, the ticks until ours
  shows X; censored at the oracle's next change ("never"). Median, p90, share never.
- **Refused presses:** attempts the true world refused, by reason, per 100 attempts; and refusal episodes (consecutive
  refused ticks of one key) per minute.
- **Damage:** our true damage dealt, A / B.
- **Time at full power:** share of combat time our true power is at max (wasted gain), A and B.
- **GCD idle:** share of combat time our GCD is free and no GCD press was accepted in it, A and B.
- **Debuff uptime:** share of combat time each content-listed debuff is up on the target, A and B.
- **First-icon flicker:** A->B->A patterns of our first icon within 3 ticks, per minute; the oracle's alongside.
- **Engine health:** `Hekili:Error` count, `Update` raises, `H.loadErrors` beyond the listed XML file, `Facade.secrets`
  (filled only while tracing: one fight per scenario runs with `Hekili.ActiveDebug = true` each tick, `Hekili.Debug`
  stubbed to a counter; Update's own 0.5 s snapshot guard traces about every third tick at 5 Hz), run misses beyond
  `KNOWN_RUN_NILS`, and CPU per `Update` (`os.clock` around it: mean and p99).
- **Oracle self-check:** §4.

### 5.2 Gates (proposed; UNMEASURED until the first run, D3)
| Scenario | Fights (D2) | Gate |
|---|---|---|
| smoke: Arms solo, one 30 s fight (fast set) | 1 | 0 errors, 0 raises, misses within the lists, a press accepted, oracle self-check holds |
| Arms solo, level 60, one mob (`mobHealth` for a ~3 min kill) | 20 x 3 min | agreement >= 0.85; react median <= 1 tick, p90 <= 3, never <= 5%; refused for `gcd`/`cooldown` 0, for `cost` <= 3 per 100 attempts; damage A/B >= 0.97; full-power time and GCD idle <= B + 3 pp; each listed debuff's uptime >= B - 3 pp; flicker <= 2/min; errors 0, `Facade.secrets` empty, CPU mean <= 10 ms (D5); oracle self-check |
| Arms, party of 5, 2 others on target (H's `melee` + `caster`) | 10 x 3 min | report only (engine health gated: errors 0, misses, self-check) |

Why these numbers: our casts, cooldowns and the GCD are plain to Hekili (our `UNIT_SPELLCAST_SUCCEEDED` is plain), so a
`gcd` or `cooldown` refusal is a bug, hence 0. Rage is the only belief in the loop (secret in combat); H §9 measured the
rage belief's overshoot at 0 windows solo, so `cost` refusals should be rare, and the 0.85 agreement leaves room for
threshold decisions near a rage boundary (Heroic Strike's `rage.time_to_42`, Whirlwind's `time_to_55`), where a small
estimate error flips the first icon without costing much (that is what A/B's 0.97 checks). A first measurement that
misses a bound is a finding to diagnose (a belief bug, a mapping bug), not a reason to loosen the bound silently (D3).
Reported alongside, never gated: the confusion table's top three disagreements, `rage est - truth` at disagreement
ticks.

All harness gates are tagged `#slow` (run by `make check`, skipped by `make test-fast`); the smoke runs in both.

Owns: `tests/Virtual/harness/loop.lua` (tallies, lines), `tests/Forever/loop_warrior_spec.lua` (new: the gates).

## 6. fake_api and src fixes

### 6.1 `UnitIsUnit(a, a)`
fake_api answers `UnitIsUnit` only from `ctl.unitIs`, so `UnitIsUnit("player", "player")` is false; State.lua:5461
keeps a debuff only when its caster `UnitIsUnit(caster, "player")`, so every own debuff from an aura read is dropped
headless. The client is true for a unit and itself: `if a == b then return true end` first in fake_api's
`UnitIsUnit` (before the secret answer: the client never secrets a unit against itself; recorded as the assumption).
Test (`tests/Virtual/State/` beside fake_api's other cases, or `headless_spec`): `UnitIsUnit("player", "player")` true,
`UnitIsUnit("target", "target")` true, a `ctl.unitIs` SECRET still secret for two different tokens. The existing
specs' expectations do not read `UnitIsUnit(x, x)` (a grep in the plan's first task confirms; one that does is updated).

### 6.2 Facade-name coverage
fake_api answers about 40 of the facade's 176 names; SPIKE's shell supplied the rest. Every client function a facade
row resolves moves into fake_api (with its `ctl` field, its secret rule as the existing rows have one: in-combat
secrets as `SECRET`), so the client model is one file and the shell holds only scaffolding (§1.2). Coverage test
(`headless_spec`, fast): after boot, every row of `ns.Facade.Inventory()` resolves to a fake_api function, except the
five rows absent on Forever, named in the test with why.

### 6.3 `State.lua:416` `state.abs = safeAbs` (one line, src)
State.lua:29 localizes only `ns.safeMin, ns.safeMax`; line 416 reads `safeAbs`, an unset global (nil); line 482
(`state.abs = math.abs`, older) overwrites it, so the runtime value has always been `math.abs`. The fix deletes line
416 (behaviour unchanged; the dead nil read gone; `ns.safeAbs` stays for its other callers). Rejected: localizing
`ns.safeAbs` at :29, which line 482 would still overwrite (two assignments, one dead). Test (`headless_spec`): after
boot `Hekili.State.abs == math.abs` and `safeAbs` is not in the `load` misses; `safeAbs` is absent from
`KNOWN_LOAD_NILS`.

Owns: `tests/Virtual/State/helpers/fake_api.lua`, `src/Hekili/Engine/Sim/State.lua` (one line), `headless_spec.lua`.

## 7. Warrior content (`tests/Forever/helpers/warrior_world.lua`)
The class-neutral loop takes a `content` table; the Warrior one is test content beside `load_warrior.lua`:
- **Character:** class token, level 60, an Arms talent build (SPIKE `run.lua`'s traits: Mortal Strike, the Arms tree
  points the pack reads), known spells from the class file's ranks at that level (not "every spell known": SPIKE's
  cheat), rage max 100, a two-hand weapon (speed 3.6), stances as forms, the pack name `Arms`.
- **`resolve(key, H)`:** reads `Hekili.Class.abilities[key]` of the **oracle** instance (its state is true): `id`, the
  cost as its state resolves it (`state.action[key].cost`, so talent discounts and `offensive_cost` apply), the
  cooldown duration, `gcd` (`"off"` -> off the GCD, else 1.5 s), `onNextSwing` -> `W.queueStrike`. Costs and cooldowns are
  never copied into the mapping (one source: the class file).
- **The mapping (content only):** per ability key its `requires` and `effect` in the world's generic verbs: Sunder Armor
  (`applyAura` on the target, 5 stacks max, its duration), Heroic Strike and Cleave (`queueStrike`), Mortal Strike and
  Whirlwind (`hit` from the weapon), Execute (`requires` the target's true health < 20%; spends all rage; `hit`), Overpower
  (`requires` a target dodge within 5 s, the world's truth), Victory Rush (`requires` a kill within 20 s), Rend (`dot`),
  Hamstring, Demoralizing and Battle Shout (`applyAura`), Bloodrage (`gain` over time), Charge (`gain`, combat start),
  stances (the form, stance requirements from the ability's `buff` field). An ability the pack can recommend but the
  mapping lacks fails the run (`unmapped key`), never a silent skip.
- **Usability answers** for the observer (§2.1.3): `IsSpellUsable` per mapped spell from the true rage and `requires`
  (Execute's `execute_phase` and Overpower read these, as in game).
- **True rage per landed hit:** the content's `rage(hand, amount, flag)`, by default the class file's own model; the
  loop measures recommendations, not the rage model (its own specs do), and this circularity is stated in the file.
- **Uptime list:** `sunder_armor`, `demoralizing_shout` (Arms list: Rend only without Mortal Strike).

Owns: `tests/Forever/helpers/warrior_world.lua` (new), `tests/Forever/loop_warrior_spec.lua` (new).

## 8. What this does not test, and the checkpoint

### 8.1 Not tested
- **The renderer.** Stub frames answer nothing visual: icon textures, keybind text, the AOE/Cooldowns displays'
  layout, `UI.lua`'s alpha and glow paths. A renderer bug that hides a correct queue passes here.
- **In-game timing.** The client's event order within a frame, `OnUpdate` frequency under load, Hekili's own
  wall-clock budgeted frame update, the human's reaction (a knob, 0 by default), latency and spell queue window.
- **The client's true secrecy.** The loop is as right as fake_api's secret rules; a read that is secret in game but
  plain in fake_api passes. `Facade.secrets` catches misfiled passthroughs only.
- **Druid** (no content yet; the loop is class-neutral and a Druid content file is the next customer), multi-target
  AoE beyond the party report.

### 8.2 In-game checkpoint (user)
A replayed `/vslog` fixture is **not** feasible as a snapshot comparison: `/vslog` records swings, `UNIT_COMBAT` and our
casts only (`tools/vslog_fixture.lua`), not the usability answers, auras, talents or the queue, so a replay cannot
rebuild the state the in-game queue was computed from. Instead one static comparison, cheap and exact:

| # | Question | Line | Answer -> action |
|---|---|---|---|
| C1 | headless and in-game precombat queues agree | out of combat, Arms, no Battle Shout, a hostile target selected: `/run local t={}for i=1,3 do t[i]=tostring(Hekili_GetRecommendedAbility("Primary",i))end VSCopy(GetTime(),UnitAffectingCombat("player"),unpack(t))` and the talent export the Protection checkpoint uses | the headless queue for the same talents and buffs (`loop_warrior_spec`'s precombat case) equal -> none; different -> the character setup or pack loading differs: fix the content before trusting the gates |

No in-combat in-game checkpoint: the loop exists because in-game truth (true rage, true auras) is unreadable there.

## 9. Tests
- `tests/Virtual/harness/headless_spec.lua` (fast): boot loads every TOC file but the listed XML; login runs
  (OnInitialize, OnEnable, VS started); misses within the lists per phase; the fake clock drives a ticker; two
  instances coexist (each sees its own `ctl.now` and `Hekili`) and the real `_G` gains no Hekili global; fake_api
  coverage (§6.2); `UnitIsUnit(a, a)` (§6.1); `state.abs` (§6.3).
- `tests/Virtual/harness/observer_spec.lua` (extended): batch and incremental streams of one seed are equal; observing
  draws nothing from `W.rng` (its state before and after `observe` equal); `k.plain` answers power and target auras
  plain; content usability flips fire `SPELL_UPDATE_USABLE` after the delay.
- `tests/Virtual/harness/world` cases (in `observer_spec` or a new `press_spec.lua`, fast, fake spec): `W.press`
  refuses for `gcd`, `cooldown`, `cost`, `requires` and changes nothing; an accept spends, starts the GCD and cooldown,
  emits the cast; `applyAura` expires on the clock; a kill ends the fight.
- H's gate specs re-run at their bounds after §2.1.2 (the RNG move), their as-built table updated.
- `tests/Forever/loop_warrior_spec.lua`: the smoke (fast), C1's precombat queue (fast), the Arms solo gates and the party
  report (`#slow`); an unmapped key fails.
- `headless_spec`: no class token (`WARRIOR`, `DRUID`, ...) or mapped ability key in `headless.lua`, `loop.lua`,
  `observer.lua`, `world.lua`, `behaviours.lua` (the boundary rule in the header).
Every task ends with busted, luacheck, StyLua, LuaLS and the API-read check.

## 10. Decisions for the user (recommendation first)
- **D1 Update rate:** 5 Hz (the in-game combat rate; 6 s per 3-minute fight with run B) **recommended**; 10 Hz as the
  option for a reaction-time study (12 s per fight).
- **D2 Fights per scenario:** Arms solo 20 x 3 min (≈ 2 min of `#slow`; `make check` grows from ~108 s to ~3.5 min with
  the party report) **recommended**; alternatives 40 x 3 min (≈ 4 min, tighter statistics) or 30 x 2 min (≈ 2 min,
  less execute phase per fight). Party report 10 x 3 min.
- **D3 Agreement bound:** first-icon agreement >= 0.85 with A/B damage >= 0.97 **recommended** (agreement alone punishes
  harmless near-threshold flips); the first measurement sets each bound at min(proposal, measured - a margin) only after
  its misses are diagnosed, recorded in an as-built table.
- **D4 What the oracle sees:** a secret-free client (every API plain: power, target auras with expiries, cooldown times;
  the same events) **recommended**: the reference is "Hekili on a client without secrets", which is what Forever took
  away. Full truth (the world's internals no API shows: the mob's swing timer, exact target health without a health
  API, others' cast IDs) would score Hekili against information it never had anywhere.
- **D5 CPU per cycle:** gate the mean at <= 10 ms (about 4x the measured 2.2 ms; catches a pathological regression, not
  noise) and report p99 **recommended**; or report-only (no machine-dependent gate at all).

## 11. Out of scope
The renderer and display options; Druid and Protection content (the next customers; Protection needs H §4's hits on us,
already in the world); multi-target AoE gates; positions, movement and range; the human reaction model beyond the
`o.reaction` knob; Hekili's own allocation per cycle; replaying `/vslog` fixtures through the loop (needs a richer
capture: §8.2); tuning the APL from the loop's findings (a separate change per finding, with its own spec).

## Decisions (accepted 2026-10-16, controller under the user's standing approval)
D1 5 Hz (10 Hz optional). D2 Arms solo 20 x 3 min as a `#slow` gate; the 10-fight party report runs behind its own
`make test-party` target, NOT in `make check` (ruling: the check stays near two minutes). D3 agreement >= 0.85 with A/B
damage >= 0.97; no loosening before a miss is diagnosed. D4 the oracle sees a secret-free client. D5 mean CPU <= 10 ms
per cycle gated, p99 reported. The class-name grep in headless_spec is unnecessary once tests/boundary_spec.lua
(forever-boundary branch) is merged; use that.
