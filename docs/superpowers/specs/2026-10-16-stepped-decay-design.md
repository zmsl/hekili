# Stepped, front-loaded resource decay (design, 2026-10-16)

Status: IMPLEMENTED (belief, sim entry, class data); the in-game checkpoint (§5) is the user's. Deviations:
`decayInterval` is a function in the class files (Engine/Spec.lua setfenv's every meta field); the sim entry is
generated in Adapter.lua (Spec.lua is upstream) and pauses through `last()`, not `stop()` (Hekili's forecast removes a
stopped entry for the rest of the forecast); its test is in adapter_spec, not warrior_spec.
Direction: user, 2026-10-16: "assume my theory and build it into the model instead of hacking it".
Base: forever 2dd4902a. Paths under `src/Hekili/` unless they start with `tests/`, `tools/` or `docs/`.

## 1. The observation and the theory
Out of combat a Warrior presses Bloodrage (+10 rage at once, then an aura that ticks +1 every 1 s for 10 s), casts
Battle Shout (-10), and watches the bar: it climbs 1 per second and ends at 9 when the aura drops, never 10, then
falls at the normal out-of-combat rate. The user's theory, adopted here: the tenth tick DOES land at the aura's expiry,
and decay resumes at that same instant, front-loaded: the first decay quantum is taken at the start of each one-second
window, not at its end. Tick and quantum coincide, so the bar never settles at 10. The client's Rage tooltip says
"1.25 Rage is lost every 1 sec" (Forever/Classes/Warrior.lua:226-233; measured 100 → 0 in 82.2 s).

The 2026-10-16 "tick at expiry does not fire" rule (2dd4902a: Resources.lua auraGain's `e - I.TICK_EPS` clamp and
State.lua E6 `expires <= e.next`) was a hack for the same symptom. This design REPLACES it: both edits are reverted.

## 2. Facts (code)
- Belief decay today is continuous: Families/Resources.lua:295-332 (OnAdvance: `drop = d * (to - start)`, paused while a
  tick-paying aura is up, resumes from the latest in-window expiry), `d = R.decay[r]` from `decayOf` (:78-84) which
  evaluates the class's `decay` (Adapter.lua:151 reads `r.state.meta.decay`), rest at `R.rest[r]`.
- Aura ticks: `auraGain` (:240-268) counts ticks at `ap + k*iv` inside (from, to], clamped to the expiry.
- Hekili's sim has NO decay: `forecastResources` (State.lua ~1185-1340) adds regenModel events (`value` may be negative:
  `v = max(0, min(r.max, v + value))` ~:1283) and a continuous `regen` forced to 0 when <= 0.001. The sim's out-of-combat
  clock: `state.time == 0` until combat or `StartCombat` (State.lua:1821-1825).
- The class declares the rage model in `spec:RegisterResource(Enum.PowerType.Rage, { entries }, { meta })`: the regen
  entries reach `r.state.regenModel`, the meta table (`decay`) reaches `r.state.meta` (Engine/Spec.lua:174-192).
- Combat end: Resources.lua:539-541 sets `fighting = false`; the decay loop's `fighting` return at :295.

## 3. Design
3.1 Declaration (class file, data only). The meta table keeps `decay` (units per second; function or number) and adds
`decayInterval` (seconds per quantum; default 1 when `decay` is set; `0` or nil for a continuous decay keeps today's
behaviour for resources that want it). The quantum is `decay * decayInterval`. Warrior: `decayInterval = 1`
(tooltip: "1.25 every 1 sec"). Druid bear rage: the same two fields. No other class file change.

3.2 Belief (Families/Resources.lua). Per slot: `R.decayStep[r]` (units), `R.decayIv[r]` (s), `R.decayNext[r]` (the
next quantum's time; 0 = decay inactive). Decay is ACTIVE when: not fighting, est above rest, and no tick-paying aura of
the slot is believed up (the existing R5 pause). On a transition from inactive to active at time t0 (CombatEnd, the last
tick-paying aura's expiry, a build out of combat), the first quantum is taken AT t0 (front-loaded) and `decayNext =
t0 + iv`. OnAdvance(from, to): while active and `decayNext <= to`: take a quantum at `decayNext` (est0/lo0/hi0 down by
step, never below rest, one `modelled` sample stamped at that beat), `decayNext += iv`. When decay becomes inactive
(combat start, a tick aura applied) `decayNext = 0`. Ordering inside one advance: aura ticks (auraGain) are credited
BEFORE the decay quanta of the same advance, so a tick and a quantum at the same instant resolve as tick then step
(9 + 1 - 1.25 = 8.75 at Bloodrage's end). Continuous mode (`decayInterval` nil/0) keeps the current code path.
Zero allocation: three preallocated arrays, scalar loop.

3.3 Sim (generated entry, no class code). Where the Adapter/Spec wires the resource (the cleanest site: Engine/Spec.lua
RegisterResource after `r.state.regenModel = regen`, or the Adapter's OnBuild walk), inject a regenModel entry
`__decay` for a resource whose meta has `decay` with a positive `decayInterval`: `{ interval = <iv>, value = -<step>,
last = function() return <anchor> end, stop = function() return <active?> end }`. The sim's `last()` returns the
belief's decay anchor `VS.DecayNext(pt) - iv` (so the sim's beats line up with the belief's), `stop()` is true while the
sim is in combat (`state.time > 0`) or any tick-paying aura entry of this resource is believed/simulated up (mirror R5:
iterate the resource's own regenModel entries with `aura` and test `state.buff[aura].up`). `value` may be a function
(talent-scaled: `-(decay() * iv)`). With the entry, `TimeToResource` sees rage falling out of combat and never forecasts
10 after Bloodrage. The entry's name is reserved (`__decay`) and skipped by any code that lists class entries.
Zero allocation: the entry table is built once at registration.

3.4 Revert the hack: Resources.lua `auraGain` back to counting the tick at the expiry (drop `I.TICK_EPS`); State.lua E6
back to `expires < e.next`; the resources_spec expectations back to 10 ticks; Warrior.lua's Bloodrage comments back to
"ten ticks".

## 4. Tests (tests/Virtual/State/resources_spec.lua, the existing harness)
1. Front-loaded: combat ends at t with est 50: at t the estimate is 48.75 (one quantum at once); at t+0.5 still 48.75;
   at t+1 47.5; at t+2.9 46.25 (beats at t, t+1, t+2); never below rest.
2. Bloodrage end: aura applied at t (10 ticks of 1, 10 s), est 0 at t, decay paused while up; at t+10 the tick lands
   and the first quantum fires: est = 10 - 1.25 = 8.75; at t+11 7.5.
3. Pause and re-anchor: a tick aura applied at t+3 while decaying stops the beats; its expiry at t+13 restarts with a
   quantum at t+13.
4. Continuous mode unchanged: a slot with `decayInterval` nil keeps the old numbers (the existing decay cases).
5. Combat start zeroes `decayNext`; no quantum during combat.
6. Allocation: alloc_spec extended with combat-end/advance cycles → 0 bytes.
7. Sim entry (tests/Forever/warrior_spec.lua, the regen-entry style at ~380): the Warrior's rage regenModel has a
   `__decay` entry with interval 1, value -1.25 (talent 0), `stop()` true with `time > 0` and with bloodrage up, false
   out of combat with no tick aura; `last()` returns the belief's anchor minus the interval.
8. The E6/TICK_EPS reverts: the 9-tick case becomes a 10-tick case.

## 5. Checkpoint (user, in game)
After Bloodrage + Battle Shout out of combat: no Rend countdown; the belief's rage (snapshot `power rage est`) ends the
buff at ~8.75 while the bar shows 9 (display rounding) and then steps down on a one-second beat matching the bar. If the
bar steps every 0.8 s instead, `decayInterval = 0.8` with `decay = 1.25` (quantum 1) is the correction: data, not code.

## 6. Placement
Families/Resources.lua (3.2, 3.4), Engine/Spec.lua or Adapter.lua (3.3), State.lua (3.4 revert only), Warrior.lua +
Druid.lua (`decayInterval`), resources_spec/alloc_spec/warrior_spec, docs/forever-facade-notes.md ("Periodic auras"
section rewritten: ticks land in full; decay is stepped and front-loaded).
