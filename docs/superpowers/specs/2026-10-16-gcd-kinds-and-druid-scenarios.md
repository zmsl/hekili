# GCD kinds in the belief, and Druid scenarios in the combat harness (design, 2026-10-16)

Status: proposed, for the user's decisions (§7). Base: forever 0e235906. Paths under `src/Hekili/` unless they start
with `tests/`, `tools/` or `docs/`. Inputs: the core leakage audit (`docs/research/2026-10-16-core-leakage-audit.md`,
item S3), the VirtualState spec (§6.2, §7.5 GCD bit-identity), the combat harness design
(`docs/superpowers/specs/2026-10-16-combat-harness-and-group-attribution.md` §3 and its §9 "As built"), the headless
recommendation loop spec (`2026-10-16-headless-recommendation-loop.md` §2.1, §7), the Druid pack spec
(`2026-10-15-forever-druid-pack.md`, checkpoints Q2, Q3, Q8, Q9, Q10), the Druid research
(`docs/research/2026-10-15-forever-druid/research.md` §2), probe session W (PR4: the GCD spell's `isActive` plain in
combat, its `startTime`/`duration` secret in combat and plain out of it) and the Forever DB2 at build 1.60.1.70338
(`wowdb`, re-queried for this design: every cat ability's `gcd_ms` is 1000, every form, Faerie Fire, Bash, Swipe,
Lacerate, Primal Bite and Demoralizing Roar 1500, Maul, Growl, Feral Charge, Dash, Prowl, Enrage and Berserk 0; Cat
Form 768 and Bear Form 5487 carry no GCD-modifying aura).

**The boundary, binding for every section.** Core (`Virtual/**`, `Engine/**`, the fork's edits to stock files) and
the harness core (`tests/Virtual/harness/**`) get generic rules read from declared fields or scenario knobs, with no
class, form, spell, aura or talent name and no spell ID beyond the GCD spell 29515. Everything Druid is in
`Forever/Classes/Druid.lua` or in `tests/Forever/**`. Each section ends with "Owns" and "Tests".

## 1. GCD kinds in the belief (audit S3)

### 1.1 Facts
- Today the belief knows one GCD length. The GCD spell's rising edge (`Families/Casts.lua:154-162`) fixes
  `I.gcdDur = I.gcdLearned > 0 and I.gcdLearned or 1.5 / haste`; the falling edge (`:163-170`) teaches `I.gcdLearned`
  from any edge in [1.0, 2.0) s (`:42`). A cast's automatic GCD model (`Families/Now.lua:309-319`) uses the same
  length. The declared `gcd` field is read only as "off or not" (`Now.lua:309`).
- The kit declares the kinds Hekili already defines: `"totem"` (Hekili's fixed 1.0 s, `State.lua:3196`) for every cat
  ability and Shifting Power, `"spell"` (1.5 s scaled by haste) for forms, caster spells and bear abilities, `"off"`.
  Stock Hekili also honours an optional per-ability `gcdTime` (`State.lua:3191`). The DB2 agrees with every
  declaration (`tests/Forever/druid_spec.lua`'s KIT pins them).
- Consequence: after cat abilities the learned length is 1.0; a Bear Form (spell, 1.5 s) cast from Cat is then
  believed to free the GCD 0.5 s early, and after caster or bear casts the first Shred is believed 0.5 s late. The
  client's falling edge corrects each one (the belief's GCD end is re-pinned at the edge), so the error lasts one GCD
  and shows as the first icon's wait.
- Edge order is not measured: an instant cast's `UNIT_SPELLCAST_SUCCEEDED` and the GCD spell's
  `SPELL_UPDATE_COOLDOWN` rising edge come in the same frame or close to it, in either order (checkpoint G3). A hard
  cast's GCD starts at its `UNIT_SPELLCAST_START` (`Now.lua:311-313` already anchors it there).
- The facade's GCD rows (`Virtual/API/Facade.lua:550-560`) answer the GCD spell and every `isOnGCD` spell from
  `VS.GcdInfo`; they need no change. `GcdInfo`'s numbers must not change between edges once read (§7.5).

### 1.2 The generic rule (core)
1. **Kind per ability, at build.** `Families/Casts.lua`'s `OnBuild` fills `A.gcdKind[a]`: 0 off (`obj.gcd == "off"`),
   2 totem (`"totem"`), 1 spell (anything else, as `State.lua:3194` defaults). A tracked extra (`track_<id>`) is 0.
   `Now.lua:309`'s `obj.gcd ~= "off"` becomes `A.gcdKind[a] > 0`.
2. **Length of a GCD opened by ability a** (`I.GcdLen(a, t)`, one function both files call, allocates nothing):
   `obj.gcdTime` when it is a number > 0 (read at the cast: Hekili's ability table evaluates a function field); else
   `I.gcdLearned[kind]` when > 0; else 1.0 for totem; else `1.5 / h` with `h = VS.Haste(t).est` (> 0 checked, as now).
   `I.gcdLearned` becomes a two-slot array `{ [1] = spell, [2] = totem }` (no per-call table).
3. **The opener.** `I.gcdOwner` (ability index, 0 none) is set when the GCD opens:
   - at the rising edge, the cast in progress (`I.castAb`, on the GCD) or the last own `CastSuccess` of an on-GCD
     ability within `GCD_EDGE` (0.1 s, UNMEASURED until G3) before the edge;
   - else, a later `CastStart`/`CastSuccess` of an on-GCD ability within `GCD_EDGE` after the edge **claims** it,
     re-fixing `I.gcdDur` (quantised) and re-pinning the GCD sample, but only while `VS.GcdInfo` has not yet answered
     this GCD (`I.gcdRead`, set by `GcdInfo` on a non-zero answer, cleared at each edge). After a read the duration
     stays (§7.5) and the falling edge corrects it, as today.
   - an off-GCD cast (Maul's success at its swing, Enrage) never owns. With no owner the provisional length is the
     last owner's kind (`I.gcdKindLast`, default spell).
4. **Learning per kind.** The falling edge teaches `I.gcdLearned[kind of the owner]` from `len = edge - start` when
   the owner has no declared `gcdTime` and `len` lies in its kind's window: spell [1.0, 2.0) as today, totem
   [0.9, 1.2) (D2; two chained 1.0 s GCDs merge into 2.0 and are rejected). An ownerless GCD teaches nothing.
5. **Snapshot.** `cast ab=... gcd=%.4f+%.4f learned=%.4f/%.4f owner=%s queued=...` (spell/totem, the owner's key).

Rationale. The kinds and `gcdTime` already exist in every Hekili class file, so no new field and nothing class-named
reaches core; the opener is the only new state, and the read guard keeps §7.5 intact. Learning per kind keeps today's
correction of haste and client latency without letting one kind's length leak into the other.

### 1.3 Adapter forwarding
None new. `def.abilities[a]` is Hekili's ability table itself (`Adapter.lua:242-253`), so `gcd` and `gcdTime` reach
`A.obj[a]` as they are; the class files declare them per ability already. The adapter test pins that a declared
`gcdTime` and each `gcd` kind are readable from `I.ab.obj` after `SpecChanged`.

### 1.4 The stock Druid-in-energy branch (`State.lua:3180-3212`)
Hekili's simulation (`state.gcd`, `mt_gcd`) already resolves `gcdTime`, `"off"` and `"totem"` before its Druid clause
(`class.file == "DRUID" and UnitPowerType("player") == Energy` at `:3198` and `:3211`), so cat abilities never reach it.
In `execute` (a press's own GCD, `Core.lua:1999`) the clause only catches spell-kind presses made in Cat (Bear Form,
Faerie Fire), forcing 1.0 s where the DB2 says 1.5 s: the simulation then frees the next bear ability 0.5 s early.
In `max`/`duration` (no ability context: `gcd.max` in cycle and time-to expressions, `State.lua:672-673, 4767`) the
clause gives the typical cat GCD, which is right.
**Proposal (D3):** named core edit **E10**: drop the Druid clause from `execute` only (the `one_sec_gcd` Rogue table
stays, stock), with a `-- Forever E10:` comment at the line and a row in `docs/forever-facade-notes.md`; leave
`max`/`duration` stock. Checkpoint G1 confirms the 1.5 s from Cat before the edit lands; a 1.0 s reading keeps the
stock line and reopens §1.2 (a form-dependent GCD would exist).

### 1.5 Owns
`Virtual/State/Families/Casts.lua` (kinds, opener, claim, per-kind learning, Snapshot), `Families/Now.lua` (the
automatic GCD by `I.GcdLen`), `State.lua` (E10), `docs/forever-facade-notes.md` (E10's row). Nothing in `Druid.lua`.

### 1.6 Tests
- `tests/Virtual/State/helpers/fake_spec.lua`: one neutral totem-kind ability (`spender_t`, the next free fixture ID)
  and one with `gcdTime = 0.8`.
- `casts_spec.lua`: a totem-kind cast opens a 1.0 s GCD with the success before the edge and after it (same t); a
  spell-kind one 1.5 / haste (haste 1.25: 1.2); a hard cast in progress owns the edge at its start; `gcdTime` 0.8 wins
  and never learns; learning per kind (totem falls at +1.02, spell at +1.43: the next totem GCD 1.02, the next spell
  1.43); an ownerless edge teaches nothing and takes the last owner's kind; a claim after a `GcdInfo` read leaves the
  duration unchanged and still learns the owner's kind; an off-GCD success inside the window does not own; the totem
  window rejects 2.0 and 0.85. The two existing GCD-learning tests (`:56-65`, `:94-110`) cast a spell-kind ability
  before their edges (ownerless edges no longer teach).
- `now_spec.lua`: the automatic GCD per kind (totem t + 1.0, spell t + 1.5 / h, `gcdTime`, the learned slot of its
  kind); after three totem casts with learned 1.0, a spell-kind cast models t + 1.5, and the next totem one t + 1.0.
- `tests/Forever/druid_spec.lua` ("in VirtualState's now context"): Shred, Shred with their edges (learned totem
  1.0), then Bear Form: `VS.GcdInfo` duration 1.5; Cat Form, then Shred: 1.0; Healing Touch's hard cast after a
  manual unshift: the GCD anchored at its start, 1.5.
- `tests/Forever/engine_load_spec.lua`: in energy, `state.gcd.execute` for `bear_form` is 1.5 x haste, for `shred`
  1.0, and `state.gcd.max` stays 1 (E10 and the kept clause).
- `alloc_spec.lua`: 1000 casts mixing kinds with edges in both orders, 0 bytes.

## 2. Harness core additions (`tests/Virtual/harness/`, class-neutral)

The Druid needs five things the harness lacks: more than one resource, regen and decay in the truth, the GCD's flag
edges, a form change that is a cast with resource rules, and crit rage. Where the headless loop spec already designed
a verb (§2.1 items 3-4: `k.usable` from content, `W.press`, `W.gain`, `W.applyAura`, `e.gcdUntil`), this design uses
it as specified there; if that plan has not landed, this plan builds those two items first, not a variant (D8).

### 2.1 Entities and behaviours
- `entities.new`: `res = { [powerType] = { cur, max } }`; `power` stays the swing-paid resource's `cur` (an alias kept
  for every existing gate). `formSpeed = { [form] = speed }` (the main hand's period in that form), `gcdUntil`.
- `behaviours.melee` knobs: `payIn` (the form whose landed swings pay `rage`; nil: always, today's behaviour; the
  `aura` gate's truth), `critRage = { main, off }` (extra on a CRITICAL landed swing: the `crit` field's truth; the
  world's truth today pays none), and press fields `gcd` (seconds, 0 off), `pt` (the cost's power type, default the
  swing-paid one), `gain = { pt, amount }`, `points = 1 | "all"` (a builder's +1 on a landed strike, a finisher's
  spend), `drain = pt` (spend what is left, after the cost), `aura = { id, duration, tick = { pt, every, amount } }`.
- A press is refused, not fired, while `e.gcdUntil > t` (the GCD truth), as the loop spec's `W.press` does.

### 2.2 The world
- Continuous regen per resource: `regen = { [pt] = perSecond }`, capped at `max`, optional `regenAfter = { s, k }`
  (the rate x k after s seconds in one form: a knob for an unmeasured in-form ramp).
- Out-of-combat decay: `decay = { pt, rate, interval, pausedBy = auraId | false }`, stepped (front-loaded, as the
  Warrior's measured rule); `pausedBy` is the truth variant the belief's `pausesDecay` is scored against.
- The GCD: an accepted on-GCD press emits `gcd` truth events (start, end = start + its `gcd` + `gcdLatency` knob,
  default 0) and records `ev.order` (1: success before the rising edge, 2: after; rolled by the behaviour, per the
  loop spec's "no RNG in observation").
- `shift` set piece / press: `{ t, form, spell, gcd, speed, dmgMult, onEnter = { [pt] = "zero" | "keep" | fn } }`: a
  cast (its success first), then the form changes: main-hand period, weapon damage (the cache stays stale, as
  `formAt` today), resources by `onEnter`. `formAt` stays as the shape-only form change.

### 2.3 The observer (every rule cites its source or is UNMEASURED with a knob)
| Client fact | Rule | Source |
|---|---|---|
| GCD flag edges | `@cooldown 29515 isActive` + `SPELL_UPDATE_COOLDOWN` at each `gcd` start and end, before or after the success by `ev.order` | PR4 (flag plain); order UNMEASURED until G3 |
| Power reads by type | `k.plainPower = { [pt] = "always" \| "ooc" \| "never" }`; default rage `"never"` (today) | Warrior PR, Druid research §2 |
| Regen read | `GetPowerRegenForPowerType(pt)` answers the true rate out of combat, secret in combat | probe W (energy 10.001 out, S in) |
| Points | a points resource with `"always"`: `UnitPower(pt)` and `GetComboPoints` answer truth after each change | gate spike; Q10 open |
| Player attack speed | `UnitAttackSpeed("player")` and `GetMeleeHaste` true out of combat only, refreshed with the damage cache (pull, stop, an out-of-combat shift) | Sources/Swing.lua; probe W PR2 |
| Forms | `@forms` (index to spell ID, the content's list) once; `@form` + `UPDATE_SHAPESHIFT_FORM` at each shift, after its success | Forms.lua; Q2 |
| Usability | `k.usable` from the content (loop spec §2.1 item 3), each rung against its own power type's truth | TDF gate spike; G7 delay knob |

### 2.4 Drive and metrics
- `drive.boot(o)`: `o.boot(ns, api, ctl)` builds the definition (default: today's fake spec), so content can boot its
  class through the adapter. Ops `@cooldown`, `@forms`, `@regen`, `@attackSpeed`, `@power` beside today's.
- `metrics`: per tracked power type, believed `est` minus truth per 10 s window (mean, max, overshoot share: `lo` above
  truth by more than the type's `overBar`); per GCD, |believed end (`GcdInfo` start + duration at the first tick after
  the edge) - true end|, and the owned / ownerless counts; points exactness (believed equals truth one poll after each
  change); per form section, credit rates and the `unknown` share (Rows.lua:417-418's stale-form path).

### 2.5 Owns and tests
Owns: `entities.lua`, `behaviours.lua`, `world.lua`, `observer.lua`, `drive.lua`, `metrics.lua`, `scenarios.lua`
(knobs only). Tests: `observer_spec.lua` gains one-event cases for each §2.3 row (GCD edges in both orders, a power
type per secrecy mode, a regen read in and out of combat, a shift's success-then-form order, an out-of-combat speed
refresh and none in combat); `world`: a refused press during the GCD, `payIn`, `critRage`, decay stepping with and
without `pausedBy`, `onEnter` rules; the existing gates re-run unchanged within §9 of the harness design (the new
draws move fights: the plan records the re-measured table at the same bounds); `alloc_spec` unchanged at 0 bytes.

## 3. Druid content (`tests/Forever/helpers/druid_world.lua`)

The content table the loop spec's §7 describes for the Warrior, for the Druid, built from the class file through
`load_druid.lua` (one source: costs, kinds and rates are read, never copied):
- **Boot:** the "Forever Druid in VirtualState's now context" setup (`druid_spec.lua:859-920`), moved into
  `tests/Forever/helpers/druid_vs.lua` and called from both that describe and `o.boot`.
- **Kinds:** each press's `gcd` from the ability's declared kind (totem 1.0, spell 1.5 at haste 1, off 0).
- **Rage (bear):** per landed white swing the `mainhand` model's `value()` (8.65), crit extra its `crit()` (8.65),
  `payIn` Bear Form; Maul a `queue` press at its `spend` (15); Enrage `gain` 10 plus `aura` 5229/25503 ticking 2 a
  second for 10 s; decay the meta's `decay()` (1.25) at `decayInterval()` (1).
- **Energy (cat):** max 100, regen 10/s, plain `"never"`; spenders at the KIT costs (Rip 30, Bite 35, Rake 40, Claw
  45, Shred 60); Shifting Power a `gain` of 40 (mana `"never"`); Bite `drain`; combo points `"always"`, builders +1 on a
  landed strike, finishers `"all"`.
- **Forms:** `@forms` in Classic's index order (Bear, Aquatic, Cat, Travel; Forms.lua maps by spell ID, so Q2's real
  order changes nothing); periods Cat 1.0 s, Bear 2.5 s (Classic, G6 confirms); Bear entry `onEnter` rage `"zero"`
  (the class's `swap_form`), Cat entry energy `"keep"` (the pack's assumption until Q3).
- `tests/boundary_spec.lua` keeps the harness core neutral: its `CORE` list gains `tests/Virtual/harness` (D7).

## 4. Scenarios

### 4.1 Solo bear (the Warrior-like rage model)
Pull in Bear (the damage and speed caches read in Bear), one hand at 2.5 s, presses every 1.5 s down a scripted
list (Primal Bite, Lacerate, Swipe, Demoralizing Roar) when the true rage covers them, Maul queued whenever rage is
at least Maul + Primal Bite, Enrage once at 20 s. It checks the `aura`-gated swing entry (rage only in Bear), the
queued strike (Maul pays its 15 at the swing, the replaced swing pays nothing, its frame gives `SPELL_DAMAGE`, no swing
row), and `crit` (a credited crit stages c = 3 once; a non-crit never does).

### 4.2 Solo cat (energy secret, combo points plain)
Pull in Cat, one hand at 1.0 s, a press every 1.0 s from a scripted list (Rake when its debuff is down, Rip at 5
points, Shred otherwise, Shifting Power when off cooldown, Faerie Fire every 40 s: a spell-kind press in Cat, the E10
case), each only if the true energy covers it. Energy is answered only through the usability ladder; the belief
regenerates at the out-of-combat regen read. Variants: `regenAfter = { 5, 1.25 }` (Feral Dedication's +25%, open in
Q3; calibration must absorb it); a `/reload` in combat (no regen read: the class file's documented shortcut, report
only, to size it). Cat white swings pay nothing: the belief's rage must stay exactly at its start through the fight.
At a 1.0 s period two main-hand swings are pending inside `PAIR_WINDOW_MS[1]` (1.5 s): pairing is reported, not gated
(no resource rides on it in Cat).

### 4.3 Shift fight (the stale caches and the form check)
Pull in Cat at 1 s, Bear at 30, Cat at 60, Bear at 90, stop at 120; a cat list in Cat, a bear list in Bear.
- **The weapon cache.** `UnitDamage` and `I.damageForm` are read out of combat in Cat (`Sources/Player.lua:66`), so
  every Bear-section white wound takes Rows.lua's `unknown` path (timing alone, `Rows.lua:417-418`); Cat sections are
  scored by amount again. Gate on the share: 0 in the pull's form, 1 in the other.
- **The swing base (finding).** `VS.SwingBase(1)` is read out of combat only (`Sources/Swing.lua:27-56`), so after a
  Cat pull it holds 1.0 s, and `bearSwing()` (`Druid.lua:144-150`) prices a bear swing at 3.46 x 1.0 = 3.46 rage, not
  8.65, until the swing-scale calibration catches up between pins. The scenario measures it; D4 proposes the class-file
  fix: the bear swing is the form's fixed 2.5 s (`BEAR_SWING = 2.5` beside `BEAR_RAGE_RATE`), checked by G6 and Q8.
- **GCD kinds** (§1): every shift is a spell-kind GCD after totem ones and the reverse; every owned GCD's believed end
  is exact (the harness has no latency by default).
- **Resources across shifts:** believed rage 0 right after each Bear entry; energy kept across Bear and back.

### 4.4 Furor ("powershifting")
Powershifting is gone on Forever (research §2.1): Furor (17056) restores, on entering Cat, 20% a rank of the energy
held on leaving it plus 10 a second spent out of it (1238181's base 40 may be a cap: unread); on entering Bear it gives
10 rage at 20% a rank. The pack models neither (`swap_form`: Bear zero, Cat keep) until Q3. The shift fight carries
the truth variants as `onEnter` functions, Furor at ranks 0 and 5: Cat entry keep / zero / Furor restore; Bear entry
zero / Furor chance. The belief is scored against each: under its matching variant the gates of §4.6 hold; under the
others the run reports the error at entry and the time until a usability pin corrects it, and asserts only the sign:
Bear Furor rage is never an overshoot (the belief says 0).

### 4.5 Enrage and the decay pause (checkpoint Q9)
The harness cannot say whether Enrage pauses the out-of-combat decay (Bloodrage does, in game); it carries both. Bear,
rage about 40 at the fight's end at 60 s, Enrage pressed at 57 s (7 s of it out of combat), 20 s observed after.
Four runs: truth `pausedBy` 25503 or false, times the declaration `pausesDecay` on the `enrage` entry or absent.
Matched pairs: believed within one decay quantum (1.25) of truth at every second. Mismatched pairs (report, sign
asserted): declared pause over a decaying truth overshoots by up to 1.25 x 7 = 8.75 rage (dangerous: `lo` above the
real rage); no declaration over a pausing truth undershoots by the same (safe). Hence D5.

### 4.6 Gates (proposed; UNMEASURED until the first run: the plan records measured values as the harness design's §9
does, and a bound tighter than measured + margin is set then)
| Scenario | n | Gate |
|---|---|---|
| Solo bear | 200 | main credits >= 94% (the Warrior's solo bar); wrong hand 0 (one hand); false wound credits 0; overshoot windows 0 (run without answers); every Maul: one `SPELL_DAMAGE`, no swing row, its cost paid once at its swing; credited crits staging c = 3 >= 94% of true crits among credited swings, c = 3 on a non-crit 0; oracle danger 0 |
| Solo cat | 200 | believed rage constant (exact); energy: mean abs error <= 10, overshoot windows (lo above truth by > 5) <= 2%; points exact one poll after each change 100%; every owned GCD's end within 0.01 s, ownerless GCDs 0 (both edge orders exercised); white pairing reported |
| Solo cat, `regenAfter` | 100 | energy mean abs error <= 15 and overshoot windows <= 5% after the first 20 s |
| Solo cat, reload in combat | 50 | report only (sizes the shortcut) |
| Shift fight | 100 | Bear-section main credits >= 85% (the `formAt` bar: timing alone); false wound credits 0; `unknown` share 0 in Cat sections, 1 in Bear; after D4, Bear-section rage overshoot windows 0 and every credited bear swing stepping 8.65; believed rage 0 after each Bear entry; GCD gate as solo cat |
| Furor variants (4.4) | 50 each | matched as shift fight; mismatched: report, Bear rage never overshoots |
| Enrage decay (4.5) | 4 x 20 | matched within 1.25 every second; mismatched report with the sign asserted |

### 4.7 Owns and tests
`tests/Forever/helpers/druid_world.lua`, `tests/Forever/helpers/druid_vs.lua`, `tests/Forever/druid_harness_spec.lua`
(the gates above, tagged `#slow`; `make test-fast` skips them), `druid_spec.lua` (its setup moved to `druid_vs.lua`),
`Druid.lua` (D4 only). `make check`'s runtime rises; split the sweep out if it passes the harness design's 20 s per
spec rule.

## 5. Implementation order
1. §1 core (Casts/Now, the fake spec, casts/now/alloc specs). 2. G1-G3 in game. 3. E10 and its engine test.
4. Loop spec §2.1 items 3-4 if absent. 5. §2 harness core with its observer and world cases. 6. §3 content and §4.1,
§4.2. 7. §4.3 with D4. 8. §4.4, §4.5 variants. Every task ends with busted, luacheck, StyLua, LuaLS and the API-read
check.

## 6. Checkpoint (user, in game)
A Druid of level 20 or more with Cat Form, ForeverProbe loaded (`VSCopy`, `/vscopy` reopens it; S = secret),
open-world mobs (no dummies). A two-line entry is a macro (the `/cast` line, then the `/run` line). Every line is
under 255 characters.

| # | Question | Line | Answer -> action |
|---|---|---|---|
| G1 | a spell-kind GCD from Cat (E10) | out of combat in Cat: `/cast Bear Form`, then `/run C_Timer.After(.1,function() local c=C_Spell.GetSpellCooldown(29515) VSCopy(c.startTime,c.duration) end)` | 1.5 -> E10 lands; 1.0 -> keep the stock line, reopen §1.2 |
| G2 | the totem and caster lengths out of combat | the G1 macro with `/cast Shifting Power` in Cat, then with `/cast [@player] Mark of the Wild` in caster form | 1.0 and 1.5 -> none; otherwise the kind's default changes |
| G3 | edge order and in-combat lengths | `/run local f=CreateFrame("Frame")f:RegisterEvent("SPELL_UPDATE_COOLDOWN")f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED","player")f:SetScript("OnEvent",function(_,e,a,_,c)VSCopy(format("%.3f",GetTime()),e,a,c,C_Spell.GetSpellCooldown(29515).isActive)end)`, then Shred x3, Bear Form, Maul, Swipe on a mob | success and rising edge within 0.1 s either way -> `GCD_EDGE` stands; wider -> the measured max + 50 ms; edge spacing 1.0 / 1.5 -> the kind windows stand |
| G4 | the belief after the build | in combat after Shreds: `/cast Bear Form`, then `/run C_Timer.After(.1,function() local s,d=Hekili.VirtualState.GcdInfo(GetTime()) VSCopy(format("%.3f %.3f",s,d)) end)`; again with `/cast Shred` after Cat Form | 1.500 and 1.000 -> none; the old learned length -> report |
| G5 | learned per kind | after G4: `/run VSCopy(Hekili.VirtualState.Snapshot():match("cast ab=[^\n]*"))` | `learned=` near 1.5/1.0 -> none |
| G6 | form speeds and the stale base (D4) | out of combat in each form: `/run VSCopy(GetShapeshiftForm(),UnitAttackSpeed("player"),GetMeleeHaste())`; after a Cat pull, in Bear in combat: `/run local V=Hekili.VirtualState VSCopy(V.SwingBase(1),issecretvalue(UnitAttackSpeed("player")),GetShapeshiftForm())` | Cat 1.0, Bear 2.5, base 1.0 in combat -> D4 confirmed; base 2.5 -> the speed read is live in combat, D4 unneeded |
| G7 | Enrage and the decay (refines Q9) | out of combat in Bear at 0 rage: `/cast Enrage`, then `/run C_Timer.After(10.5,function() VSCopy(C_Spell.IsSpellUsable("Swipe"),C_Spell.IsSpellUsable("Maul")) end)`, and watch the bar | Swipe usable (about 30) -> paused: `pausesDecay = true` on `enrage`; Maul only (about 17) -> stays absent; Enrage refused out of combat -> press it 2 s before the last mob dies and read the bar |
| G8 | resources after shifts (with Q3, Q10) | in combat after Cat -> Bear -> Cat: `/run local V,t=Hekili.VirtualState,GetTime() VSCopy(V.Power(1,t).est,V.Power(3,t).est,V.Power(4,t).est,GetComboPoints("player","target"))` against the bars | rage 0 on Bear entry, energy as the bar, points equal -> none; otherwise the Furor variant the bars show -> the matching `onEnter` becomes the class's model |

## 7. Decisions for the user
- D1 **Opener window and the read guard:** `GCD_EDGE = 0.1` s (UNMEASURED until G3); a late claim re-fixes the
  duration only before `GcdInfo`'s first read; ownerless GCDs teach nothing. Recommended: as stated (it is the only
  way to honour §7.5 without knowing the edge order).
- D2 **Does the totem kind learn?** Recommended: yes, within [0.9, 1.2), so prediction and the falling edge share the
  client's latency as the spell kind does; alternative: fixed 1.0, never learned.
- D3 **The stock Druid-in-energy branch:** recommended, named core edit E10 removing it from `execute` only (it
  misprices spell-kind presses in Cat), `max`/`duration` left stock (right for the typical cat GCD), gated on G1;
  alternatives: leave all of it (zero stock diff, the simulation's 0.5 s error on a shift from Cat stays) or remove
  both (`gcd.max` in Cat becomes 1.5).
- D4 **Bear swing price:** recommended, `Druid.lua`'s `bearSwing()` returns the form's fixed 2.5 s instead of the
  out-of-combat `SwingBase` read (stale after an in-combat shift from a Cat pull), until Q8 measures the rate.
- D5 **Enrage `pausesDecay`:** recommended, stay absent until G7/Q9: the harness shows absence errs on the safe side
  (undershoot) and a wrong declaration overshoots by up to 8.75 rage.
- D6 **Furor:** recommended, unmodelled until Q3 (Bear zero, Cat keep), its variants carried as report-only
  scenarios; G8 picks the model.
- D7 **Boundary scan of the harness core:** recommended, add `tests/Virtual/harness` to `tests/boundary_spec.lua`'s
  `CORE` (hits fixed or allow-listed with a reason in the same change).
- D8 **Harness verbs:** recommended, build the loop spec's §2.1 items 3-4 as specified there if this lands first.
- D9 **Gate bounds (§4.6):** recommended, accept as proposed and let the first run tighten each to measured + margin,
  recorded in an "As built" table.

## 8. Out of scope
Spell haste for the spell kind (the belief scales by the melee haste it measures; stock by spell haste; equal at haste
0, the learned slot absorbs a gap); a per-form damage cache (the Bear section scores on timing alone, gated at the
`formAt` bar); Feral Dedication as a declared regen entry (Q3); the Rogue `one_sec_gcd` table and Hekili's
Adrenaline Rush/Voidform floors (stock, no Forever class); Balance and Restoration scenarios (casters: the harness's
`caster` archetype is another player's); multi-target bear (Swipe across plates) and threat; the headless
"press what is recommended" loop for the Druid (the loop spec's next customer; §3's content table is shaped for it);
misses on yellow strikes and their combo points (Q10); Blood Frenzy, Natural Reaction and rage from damage taken in
Bear (the calibration absorbs them, as the class file's shortcut says).

## Decisions (accepted as recommended 2026-10-16, controller under the user's standing approval)
D1-D9 as recommended. Sequencing: this spec's plan runs AFTER the headless recommendation loop plan (it reuses that
plan's press and usability pieces, D8); the in-game checkpoint G1-G8 needs a Druid character and is the user's.

## 9. As built (2026-10-17)
Where §1-§7 and the code differ, this table rules ("Deviation n" is the plan's,
`docs/superpowers/plans/2026-10-17-gcd-kinds-and-druid-scenarios.md`).

| Topic | Spec text | As built | Source |
|---|---|---|---|
| The opener's window (§1.2 item 3) | within `GCD_EDGE` of the edge | measured from the edge's own time; the quantised `gcdStart` is up to 2^-11 s later, and an edge-first claim at an off-grid time failed against it | Deviation 2 |
| The fake spec's kinds (§1.6) | two abilities in `fake_spec` | opt-in, `fs.new(swingValue, true)`: in every fake spec they moved the adapter's tracked counts and the flag count | Deviation 1 |
| E10 (§1.4) | in energy, `execute` only | as proposed; the clause's line comments `-- Forever E10:` without a class name; `docs/forever-facade-notes.md` has the row | Task 2 |
| Resources (§2.1) | `res = { [pt] = { cur, max } }`, `power` an alias | `power` stays the swing-paid type's value (`e.pt`); `res` holds the others | Deviation 4 |
| Press fields (§2.1) | `points = 1 \| "all"` | `points = { pt, 1 \| "all" }`; `aura.tick` has named fields `{ pt, every, amount }`; `gcd = 0` is off the GCD | Deviation 5 |
| Regen (§2.2) | continuous | a "regen" gain every `regenTick` (0.1 s), capped; it runs in every form (UNMEASURED), so Furor's Cat restore equals keep | Deviation 6 |
| Shift (§2.2) | set piece / press | a press field and `W.shift` only: the shifts respect the GCD | Deviation 7 |
| The old worlds (§2.5) | the new draws move fights, re-measure | nothing moves: the GCD order has its own generator (`W.grng`), every new behaviour is knob-gated and the attack speed read is behind `k.playerSpeed`; nine streams byte-identical before and after, so the harness design's §9 tables stand | Deviation 3 |
| Boundary (D7) | `tests/Virtual/harness` in `CORE` | with its captured logs (`fixtures/`) skipped (their numbers are times and amounts), four WoW global names allow-listed, two test IDs that collided with content IDs changed | Task 3 |
| Fight counts (§4.6, §4.7) | in `make check` | a tenth of each in `make check` (`#slow`, about 19 s); the design's counts behind `make test-druid` (`#druid`, about 192 s) | Deviation 10 |
| Bear drift (§4.6) | overshoot windows 0 | windows a step over that end with the belief above the truth: 0; all windows a step over: 4 of 2400, each a window that starts with the belief 17 below the truth and a Maul's 15 clamped at 0 | Deviation 11 |
| Rage after a Bear entry (§4.6) | 0 | believed minus true at the first tick after the entry <= 1.3 (a swing landing after the entry pays both, at the calibrated scale): measured 0.84 | Deviation 12 |
| Decay, matched (§4.5) | within 1.25 every second | the change since 1.5 s after the stop (our last swings landed) within 1.25, no fight low; the plan's seed 15 losing Enrage's expiry tick (2) was fixed on `forever` by ffc300da (Auras.lua) before the patches landed | Deviation 13 |

Measured (the design's fight counts, `make test-druid`):

| Scenario (fights) | Measured | Gate |
|---|---|---|
| Solo bear (200) | main 6000/6047 (.992), wrong 0, false wounds 0; drift windows ending over 0 (raw 4/2400); danger 0; Mauls 1936: 1936 `SPELL_DAMAGE`/`SPELL_MISSED` rows, 1936 paid; crits 920, staged 920, on a non-crit 0; GCDs 2067 seen at their start, end error 0.0004 s, ownerless 0 (orders 1043 / 1024) | main >= .94, wrong 0, false 0, drift 0, danger 0, every Maul one row and paid once, staged >= 94% and 0 false, GCD |
| Solo cat (200) | rage error 0; energy mean abs 1.78, max 40.0 (the pull), over windows 0/2600; points exact 226603 of 226603 settled ticks; GCDs 8407, end error 0.0004 s, ownerless 0 (orders 4193 / 4214); white pairing at 1.0 s: main .912 | rage 0; energy mean <= 10, over <= 2%; points 100%; GCD (within 0.01 s, ownerless 0, both orders) |
| Solo cat, `regenAfter` 5 s x 1.25 (100) | energy mean abs 2.41 after 20 s, over 0/1100 | mean <= 15, over <= 5% |
| Solo cat, a /reload in combat (50) | energy mean abs 11.4, over 0/650 | report |
| Shift fight (100) | Bear sections main 1680/1719 (.977), false wounds 0 in both; timing alone: 1719/1719 in Bear, 0/4670 in Cat; Bear rage over windows 0 (lo over the truth at most 1.26), mean abs 2.92; every swing the belief paid 8.65 (before D4: every one 3.46, mean abs 3.94, entry under by up to 5.08); entry over 0.84, under -7.31; energy mean abs 0.28; GCDs 3036, ownerless 0 | Bear main >= .85; false 0; unknown 0 / 1; rage over 0 and every swing 8.65; entry over <= 1.3; GCD |
| Furor: Cat entry zero (50) | energy error at each Cat entry 99, within 5 after 35.7 s on average (the fight's end if never); energy over windows 200; Bear rage over 0, entry over 1.18 | report; Bear never over |
| Furor rank 5 (50) | Bear entry under by 10 (the truth's chance, the belief's 0), lo over the truth at most 4.99 (below a swing), over windows 0 | report; Bear never over |
| Enrage decay (4 x 20) | matched: errors 0, no fight low, in both pairs; declared over a decaying truth: up to +7.5; none over a pausing truth: down to -7.5 (six quanta: the error counts from stop + 1.5 s, so §4.5's 8.75 = 7 quanta is not reached) | matched within 1.25, none low; signs asserted (over the dangerous sign, under the safe one) |

D4 confirmed by the harness (the stale 1.0 s base priced every Bear swing at 3.46 through the shift fight); D5 stands:
a wrong `pausesDecay` overshoots, its absence undershoots.

Follow-ups (not built here):
- Furor's "Cat entry zero" variant: the energy belief sits 99 over the truth at each Cat entry (the dangerous sign) and
  only a usability flip after a spend corrects it, about 36 s on average. Open: a faster correction of an energy belief
  above the truth after a mismatched entry rule.
- The Cat /reload in combat: energy mean abs error 11.4, never over (the safe sign). Not the entry rule: with no regen
  read the belief's regen stays 0 (the class file's `shortcut:`, Druid.lua), so the error is a 10/s sawtooth between
  cost rungs; its upgrade is a regen meta field after Q3.
