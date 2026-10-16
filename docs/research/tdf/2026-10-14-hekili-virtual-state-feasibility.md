<!-- Ported from TacoDogForever docs/research/2026-10-14-hekili-virtual-state-feasibility.md (credit: TacoDogForever), copied here because that repo is being retired. -->
# Can Hekili run on Forever as is, behind a virtual game state and a virtual game API?

Date: 2026-10-14 · Research only, no code changed · Client: WoW Forever 1.60.1.70338 (interface 16001)

The question is not whether this is a nice design. It is whether the design is impossible, and if not, what exactly
breaks and what it costs. The answer is argued from Hekili's code and Forever's measured behaviour.

The proposal under review is the user's (2026-10-14), in five phases:

1. A virtual game state library fed by the observation log, publishing "real-time" events and making no forecasts.
2. A virtual game API facade over it: pass through what is readable, use state for what isn't.
3. Cleanup of everything not in Forever.
4. (3b) Shim the facade into Hekili, with a Warrior proof of concept.
5. (4) A view model so TDF's display can sit on Hekili.

The adapter layering the user drew is used as the reference shape in sections C, D and I:

```
            Addon: same calls, same events
   subscribe/get events │                 │ calls and results
 ┌── Facade layer ──────┼─────────────────┼──────────────────────────────┐
 │  Virtual Game State  │                 │  Virtual Game API             │
 │   Observation log → Log processor → Virtual state → Event queues      │
 │                                    ◄── Virtual state ── (Blocked: use state)
 │                                        Events ──► (API half)          │
 │                                        Accessible: pass through       │
 └───────────────────────────────────────────────────────────────────────┘
   observes │            pass-through calls │        (fails → use state)
 WoW game API:   Accessible  │  Secret in combat  │  Removed
```

## How to read the citations

- `Hk` is Hekili, branch `forever`: `~/src/hekili` at `36daec38`, the final retail code, TOC 110205.
- `Hk-classic` is `origin/classic` (Classic Era 1.15, TOC 11505).
- `TDF` is `~/src/TacoDogForever` at main `47e1695`.
- Probe evidence:
  - **[W]** is `docs/research/2026-10-13-probe-session-W-results.md`.
  - **[SU]** is `…-probe-results-swing-usable.md`.
  - **[O]** is `2026-10-14-probe-session-O-results.md`.
  - **[V]** is `2026-10-14-virtual-combat-log-events.md`, the 137-row virtual combat log.
- Earlier research:
  - **[R0]–[R6]** are `origin/research/forever-revival:docs/research/0N-*.md` in the Hekili repo.
  - **[Splice]** is TDF `docs/research/2026-10-12-eval-hekili-splice.md`.
  - **[Strategy]** is `…-eval-hekili-strategy.md`.
  - **[Port]** is `docs/research/2026-10-12-hekili-reconciliation/00-port-plan.md`.
- Three mechanical inventories back this document: the API call sites, the CLEU consumers, and the cleanup and UI
  surface. Helpers produced them from greps of the code. Their file:line cites were spot-checked; 30 were re-read for
  this document.

---

## 0. Verdict in brief

**Possible, but not "as is".** The facade can be built, and Hekili's simulator, APL compiler, options and display
survive mostly untouched. Three things decide the cost:

1. **The virtual state must nowcast, which needs a second class model.** On Forever, rage, cooldown remaining time and
   aura expiries are never observed in combat. They have to be carried forward from anchors (casts, swings,
   usability flips) using costs, gains, durations and talents, so a Phase 1 that "does no prediction" cannot answer
   `UnitPower` in combat.
2. **Hekili assumes every read is exact.** Its engine never asks how sure a value is, so a facade estimate becomes a
   confident pick. TDF's fuzzy/now distinction is lost unless Hekili changes.
3. **"Same calls" needs a per-file environment and about 15 edits that no facade can absorb.** Overriding the globals
   would taint Blizzard's UI. The virtual combat log must be delivered synchronously, because Hekili stamps it with
   `GetTime()`.

On effort, the shim path reaches "Warrior playable with Hekili's options" in about **100–150 lane-hours**. TDF's
remaining path is about **65–85 lane-hours** (section H).

---

## A. Hekili's read surface

### A.1 Size and shape

- **Distinct game reads.** 67 logical API groups, about 175 function names, across the engine (Hekili, Utils,
  Constants, State, Events, Classes, Targets, UI, Core, Scripts, Options) plus one class pack for contrast
  (`TheWarWithin/WarriorArms.lua`).
- **Forever status, by group (names):**

  | Status | Groups | Names |
  |---|---:|---:|
  | Plain | 28 | 58 |
  | Secret in combat (plain out of combat) | 8 | 23 |
  | Secret always | 3 | 4 |
  | Removed or non-functional | 4 | 8 |
  | Unknown (not probed) | 24 | 82 |

  "Unknown" is mostly retail systems, stats-family getters, group APIs and static metadata.
- **Lines that reference a game API.**
  - About **59 `local X = <api>` capture lines**, most of them at file tops.
  - About **680 lines that call a game global at call time** (outside comments and import lines): State 193,
    Events 128, Classes 96, Targets 90, Utils 83, UI 42, Options 30, and fewer than 10 in each other file.
  - **51 `state.X = <api>` snapshot lines** at `Hk State.lua:740-790`. They are the only game APIs that APL scripts
    and class functions can reach (see C.2).
- **No secret awareness at all.** There are 0 references to `issecretvalue` or `C_Secrets` in the whole repo.
- **What changed since [R1] (2026-10-11).**
  - [R1] counted 51 secret-returning functions from the API documentation, without probes.
  - Sessions W and O have since measured them. The secrecy model is now settled ([W] §4): resource values are secret
    always; stats, haste, cooldown times, auras and regen are secret in combat only; usability, cooldown flags,
    swings, own casts, target identity, range and talents (`C_Traits`) are plain.
  - Session O adds `UNIT_COMBAT`, deaths, `UNIT_AURA` key presence and the target's cast events with `castBarID`
    ([O] §2).
  - [Splice] (2026-10-12) asked a similar question. It predates every probe and assumed no `UNIT_COMBAT` and no
    virtual combat log.

### A.2 The critical reads (where secrets hit Hekili)

The column "Facade returns" uses four kinds:
- *passthrough*: the real call;
- *belief*: an estimate from the virtual state;
- *constant*: a fixed value;
- *unavailable*: nothing usable.

| API | Call sites | Where it sits | Forever | Facade returns |
|---|---|---|---|---|
| `UnitPower` | State 1, Events 1, Arms 1 | reset `Hk State.lua:6899` (`res.actual` for every resource); event `Hk Events.lua:1450-1452` (`newPower < lastPower`) | secret always for rage, energy and mana [W PR16; SU] | belief (or passthrough for combo points, guarded; unprobed for `UnitPower`, `GetComboPoints` plain [W §4]) |
| `GetPowerRegenForPowerType`, `GetManaRegen` | 1 each | reset `Hk State.lua:6912, 6919` | secret in combat, plain out [W PR16] | belief (the cached out-of-combat read) |
| `UnitHealth/Max("player")` | 22 / 18 across files | reset `Hk State.lua:6960-6961` | not probed for the player; secret always for the target | constant, or unavailable |
| `UnitHealth/Max("target")`, other units | (in the counts above) | per recommendation `Hk State.lua:3230-3233` (`target.health`); enemy counter `Hk Targets.lua:424, 501, 628` (`UnitHealth(unit) > 1`); TTD ticker `Hk Targets.lua:1574-1603` | **secret always** [W PR14] | unavailable → constant; the comparison sites need edits (C.5) |
| `UnitAttackSpeed` | 9 | load `Hk State.lua:202, 205`; reset `:6965`; CLEU swing handler `Hk Events.lua:1939, 1944` | secret in combat [W PR2] | belief (out-of-combat cache; the `PLAYER_SWING` duration in combat) |
| `UnitSpellHaste`, `GetMeleeHaste`, `GetHaste` | 3 | per recommendation `Hk State.lua:2714, 2717` (`state.haste`, so the GCD and every cast time) | secret in combat [W PR4] | belief (melee from the swing duration; spell from the last plain read) |
| `UnitDamage`, `UnitAttackPower`, ratings, crit, mastery | about 15 | per recommendation, lazy stat table `Hk State.lua:2606-2726` | secret in combat (the stats family, `ShouldUnitStatsBeSecret` [W PR2]) | belief (out-of-combat cache) |
| `GetUnitSpeed` | 6 | per recommendation `Hk State.lua:2221` (`moving`); enemy counter `Hk Targets.lua:482, 548, 612, 632` | secret in combat [W PR14] | belief (`IsPlayerMoving` and the `PLAYER_*_MOVING` events, plain) |
| `GetTotemInfo` | 7 | reset `Hk State.lua:6870`; per recommendation `:2759, 4630, 4665-4686` | secret in combat, even for empty slots [W PR12; O13] | belief from casts, or unavailable |
| `C_UnitAuras.Get{Buff,Debuff}DataByIndex`, `AuraUtil.*`, `UnitBuff/Debuff` | about 30 | reset `ScrapeUnitAuras` `Hk State.lua:5956-6173` (called at `:6809, 6814`); aura generators `Hk Classes.lua:2440-2660`; event `Hk Events.lua:1513-1572` | secret in combat; reads error when tainted [W §4 target auras] | belief (synthesised aura records, A.3) |
| `UNIT_AURA` payload | 1 handler | `Hk Events.lua:1517` `if data.isFullUpdate` | the table is plain, every field secret in combat, the keys visible [O12] | event facade (synthesised payload) |
| `C_Spell.GetSpellCooldown` | State 1 (feeds every `cooldown.x`), Events 1, UI 5 | per recommendation `Hk State.lua:3276` (call-time global), arithmetic at `:3325-3376`; event `Hk Events.lua:1924`; per frame `Hk UI.lua:1500, 1512, 1701, 1719` | `isActive`, `isEnabled`, `isOnGCD` plain; `startTime`, `duration`, `modRate` secret in combat [W PR4, PR11] | merged: plain flags passed through, times from belief |
| GCD spell 61304 | `Hk Classes.lua:2906`, `Hk UI.lua:1500, 1701`, `Hk Events.lua:1924` | per recommendation and per frame | **returns nil**: Forever's GCD spell is 29515 [W PR4] | edit the constant (C.5) |
| `C_Spell.GetSpellLossOfControlCooldown` | 1 | captured `Hk State.lua:22`, called `:3327` on every cooldown read | not in the Forever API (only `…Info` / `…Duration` exist) | constant `nil, nil` |
| `CombatLogGetCurrentEventInfo` and the CLEU registration | Events 1, DevTools 2, 37 pack hooks | `Hk Events.lua:2016` → `CLEU_HANDLER` `:1709-2014`; live raw registration `Hk Shadowlands/Trinkets.lua:1959` | **forbidden**: registering raises the "Blizzard UI only" popup [V §0] | virtual CLEU (section B) |
| `GetSpecialization`, `GetSpecializationInfo` | 30 | spec detection `Hk Events.lua:365-366`, `Hk Classes.lua:4092-4147` | plain, but one pseudo-spec per class (Warrior 1491) [W PR15]; retail packs are keyed 71, 72, 73 | translation |
| `GetTalentInfoByID` and friends | 3 | `Hk Events.lua:416-464` (`ns.updateTalents`) | dead: errors or nil [W PR5] | belief (the `C_Traits` walk, plain in combat) |
| `IsPlayerSpell`, `IsSpellKnown` | about 11 | `Hk State.lua:7402-7513` (`state:IsKnown`) | plain, but reports rank 1 only [W PR5] | passthrough plus rank from `C_Traits` |
| LibRangeCheck `RC:GetRange`, LibSpellRange | about 15 | `Hk State.lua:3105, 5659, 7666, 7671`; `Hk Targets.lua:463, 529`; `Hk UI.lua:1583, 1586` | spell and action range plain [W PR7]; `UnitInRange` secret always; the libraries' internals were not read (they are packager externals, missing from the checkout) | not reachable by the facade (C.2) |

**Plain and passed through:**
- `GetTime`, `InCombatLockdown` (which lags: false inside `PLAYER_REGEN_DISABLED` [W §3]);
- `UnitExists`, `UnitGUID`, `UnitIsUnit`, `UnitCanAttack`, `UnitIsDead`, `UnitLevel`, `UnitClassification`,
  `UnitThreatSituation`, `UnitAffectingCombat` [W PR14; O8];
- `UnitCastingInfo("player")` [W PR9];
- `C_Spell.IsSpellUsable`, `IsCurrentSpell`, `IsSpellOverlayed` [W PR1, PR11];
- `GetInventoryItemID`, the `C_Item` cooldown and usability reads [W PR13];
- `GetBindingKey`, `GetActionInfo` [W PR10];
- `C_LossOfControl.*` [W PR18; O5];
- `UnitPowerMax` (100 for rage) [W PR16];
- `C_Traits.*` [W PR5].

**Load-time hazards** (unprobed; a nil here aborts a file at load):
- `C_PetBattles.IsInBattle`, captured at `Hk UI.lua:43` and called at `:976`;
- `GetNumClasses` at `Hk Constants.lua:32`;
- `UnitAttackSpeed("player") > 0` at `Hk State.lua:202` during a `/reload` in combat.

### A.3 Where calls happen (what a facade is asked, and how often)

- **`state.reset()`** (`Hk State.lua:6787-7136`, once per display per update, every 0.2–0.5 s;
  `Hk UI.lua:2384-2400`) reads:
  - resources, regen, player health, swing speed and totems;
  - auras, but only if the `updated` flag is set (`:6808-6816`);
  - the player's cast through `buff.casting.generate` (`:7028`).
- **Per recommendation**, through the lazy metatables:
  - every `cooldown.x` key on its first access per reset (the `autoReset` keys at `Hk State.lua:3262-3273`;
    `mt_default_cooldown` at `:3283`);
  - stats and haste, `target.health`, `moving`, range, and the enemy counter (`ns.getNumberTargets`, once per
    update, `Hk Core.lua:1587`).
- **Event handlers:** about 56 registrations through one dispatcher (`Hk Events.lua:68, 87`).
- **Per frame:** `d:OnUpdate` in `Hk UI.lua:1108-1672`, which includes the GCD and cooldown swipe arithmetic and range
  and usability tints.
- **Tickers:** TTD every 0.5 s (`Hk Targets.lua:1603`) and the target auditor every 1 s (`:1134`).

**What it all reads exactly.** It needs four groups of data:
- **resources:** the current value and regen (`Hk State.lua:6899-6925`);
- **cooldowns:** start and duration (`Hk State.lua:3374-3376`);
- **auras:** `expirationTime` (absolute) and `duration` (`Hk State.lua:6012-6031`);
- **swings, the GCD and casts:**
  - swings come from CLEU timestamps plus `UnitAttackSpeed` (`Hk Events.lua:1931-1947`);
  - the GCD comes from spell 61304's cooldown (`Hk State.lua:3348-3351`, `:3427`);
  - casts come from `UnitCastingInfo`'s `endTimeMS` (`Hk Classes.lua:1960`).

None of these four groups is plain in combat on Forever except the player's cast.

---

## B. The virtual CLEU

### B.1 How Hekili consumes the combat log

- **One registration and one handler.** `CLEU_HANDLER` (`Hk Events.lua:1709-2014`) is registered at `:2016`.
  - It first fans every event out to the class-pack hooks (`:1711` → `ns.callHook`, `Hk Classes.lua:3882-3894`).
  - Then it filters on identity: `sourceGUID == state.GUID`, the pet's GUID, the minion table, and
    `destGUID == state.GUID` (`Hk Events.lua:1733-1735`).
  - After `:1810` only our own events (plus pets, if enabled) go further.
- **The engine never needs third-party sources**, with two exceptions:
  - the attacker's GUID for tanks (`:1929`);
  - minion damage, only when `damagePets` is on (default off, `Hk Classes.lua:52`).
- **Class packs:** 37 CLEU hook registrations in 33 `TheWarWithin/` files, none in the other expansion folders.
  - Warrior has three: Arms `:701`, Fury `:711`, Protection `:731`.
  - One raw registration is live: `Hk Shadowlands/Trinkets.lua:1959`. It raises the popup at load and goes in
    cleanup.
  - `Hk Options/DevTools.lua:452, 1208` is a dev tool.
- **Two corrections to [V] §6:**
  - It says "about 40" hooks and "none in other folders"; there are 37, plus the Shadowlands registration.
  - It omits that `AddToHistory` (`Hk Events.lua:1911`, defined `:1118-1143`) is the **only writer** of
    `lastcast`, `lastgcd`, `prev_gcd` and `realCast`. The `UNIT_SPELLCAST_SUCCEEDED` handler (`:1220-1235`) only
    calls `ForceUpdate`.

### B.2 Consumers mapped to the 137 rows

Scores are [V]'s after session O:
- **R**: reconstructable;
- **P**: partial;
- **I**: impossible.

| # | Consumer (`Hk Events.lua`) | Feeds | [V] rows | Feed | Silent misbehaviour with a partial or absent feed |
|---|---|---|---|---|---|
| E2 | Death cleanup `:1713-1729` → `ns.eliminateUnit` (`Hk Targets.lua:947-960`) | `targets`, `myTargets`, `active_dot` purge | C66, C67, C68 R (O6: 34 / 23 / 23, GUIDs plain); C69, C70, C41 P | **R** | Absent: dead units stay counted until the auditor drops them after `damageExpiration` (8 s, `Hk Targets.lua:1108-1123`) |
| E3 | Summon `:1745-1757` | `minions` | C45 P, C46 I | P | Inert unless `damagePets` is on |
| E4 | Damage taken `:1761-1806` → `ns.storeDamage` | `incoming_damage_Ns` (`Hk State.lua:2359-2411`) | C2, C4 R (O1 player WOUND and MISS); C52, C60 P; C13, M10 I | R direct, P periodic | Protection defensives never fire. They also read `health.pct`, which is secret, so a feed alone doesn't revive them. Self-damage can't be excluded (`UNIT_COMBAT` has no source) |
| E5a–c | Cast start, failed, channel end `:1819-1860` | event queue (`CAST_FINISH`, projectile) | C36, C40, C30 R | R | A phantom cast-finish stays until its time; bounded |
| **E5d** | **Cast success and history** `:1861-1912` | **`AddToHistory`: `prev_gcd`, `lastcast`, `action.x.lastCast`** | C38 R (O16: 134 successes plain) | **R** | **Absent: every `prev_gcd` test is false with no error.** Combat start by cast (`Hk State.lua:6884`) never fires. A success for a dodged strike is still recorded (O16, n = 1) |
| E5f | Projectile impact `:1916-1921` | in flight | C7 R (cast, travel, target WOUND; attribution unmeasured) | R / medium | Bounded |
| E5g | GCD anchor `:1924` (`GetSpellCooldown(61304)` on every cast event) | `state.gcd.lastStart` | — | **edit** | 61304 is nil on Forever, and the times are secret: port the line, don't feed it |
| E6 | Tank attacker `:1929-1930` | `targets` | the attacker GUID is impossible (victim-side `UNIT_COMBAT`); substitutes N20, N21, D16 | P | Protection under-counts unplated attackers |
| **E7** | **Swing timers** `:1931-1947` | `swings.mh_actual`, `oh_actual`, and the Warrior rage models (`swing = "mainhand"`, `Hk TheWarWithin/WarriorFury.lua:36-60`) | C1, C3 R (`PLAYER_SWING` plain per hand; MISS, DODGE, PARRY plain); C24 P | **R** | Absent: swing rage stops forecasting and `Hk State.lua:7160-7166` fakes a swing "now" (wrong phase). The handler re-reads `UnitAttackSpeed` (`:1939, 1944`), which is secret, so the facade must cover that read too |
| **E8a** | **Hostile debuff tracking** `:1948-1985` → `ns.trackDebuff` (`Hk Targets.lua:787-824`) | `active_dot`, ticks, `pmultiplier` | C27, C33, C30 R (cast, travel and DB2 duration); C31, C51 P; C53 I | R / P | Absent: `active_dot` is 0 and `cycle_targets` degrades. Modelled only: a dodged, resisted or dispelled DoT stays "up" unless the bus emits a compensating REMOVED (D.3) |
| E8b | Friendly HoTs `:1986-1997` | `trackDebuff` | C25 R, C54 P | P | Healers only |
| **E9** | **Damage-seen enemy counting and overkill** `:2003-2012` | `active_enemies`, `my_enemies` (`Hk Targets.lua:564-644`) | C1, C7, C9, M1–M4 R; the overkill part I; source filtering I | P | Absent: count 1 plus plates. Victim-side `UNIT_COMBAT` without a source over-counts in groups. No overkill elimination. The plate scan itself errors (`UnitHealth(unit) > 1`), so this branch carries the load |
| W1–W3 | Warrior pack hooks (Arms `:701`, Fury `:711`, Protection `:731`) | Colossus Smash early apply, Whirlwind stacks, refreshes | C38 R; C25, C26, C30 R / P | R / P | Retail spell IDs; rewritten with the pack anyway |

**Counts:** 17 engine rows plus 3 Warrior rows = 20. Of the 16 that apply: 8 R, 8 P, 0 entirely I. Impossible pieces
sit inside partial rows: overkill, the attacker's GUID, absorbed amounts and `SPELL_PERIODIC_MISSED`. The consumers
touch about 50 of the 137 rows.

### B.3 Ranked silent-misbehaviour hotspots with a partial feed

1. **Cast history (E5d).** The single most damaging gap if missing, and fully fixable from
   `UNIT_SPELLCAST_SUCCEEDED`.
2. **Enemy count (E9 + E2 + E6).** It sits at 1 without a feed and over-counts in groups with a victim-side feed. It
   stays stale for 8 s without deaths. The plate scan also needs an edit.
3. **Swing clock (E7).** Exact from `PLAYER_SWING`, but only if the facade also answers the speed re-read.
4. **Debuff tracking (E8a).** Correct on schedule. It is wrong after an unseen dodge, resist or dispel, unless
   `UNIT_COMBAT` DODGE/MISS or the `UNIT_AURA` removed key triggers a retraction.
5. **Damage taken (E4).** Revivable as numbers but useless without player health percent.

### B.4 The payload contract a synthesised event must honour

Hekili destructures the CLEU tuple positionally, so a missing or mistyped field breaks it:
- `destFlags` must be a number: `bit.band` at `:1759` raises on nil. Synthesise it from `UnitCanAttack` and
  `UnitIsFriend`, both plain.
- `destGUID` must be a string, `""` for none (`:len()` at `:1822, 1868`; `:match` at `:1721`).
- `school` must be a number (`:1804`).
- Overkill must be 0, not nil (`:2006`).
- `SWING_DAMAGE` shifts its slots: the amount is in slot 12.
- Delivery must not nest inside a pack hook: `ns.callHook` drops re-entrant calls (`Hk Classes.lua:3883`).

---

## C. The virtual state container as a facade (against the drawn layering)

### C.1 "Same calls": how Hekili's reads resolve to the facade

Hekili gets game APIs three ways:
1. **File-top locals captured at load**, about 59 lines. Examples: `Hk State.lua:18-36`, `Hk Events.lua:18-34`,
   `Hk UI.lua:21-43`, `Hk Utils.lua:13-16, 57-61`, `Hk Classes.lua:26-34`, `Hk Hekili.lua:12-15`.
2. **Call-time globals**, about 680 lines. These include the whole reset body (`UnitPower` at `Hk State.lua:6899`
   is a call-time global, not a local) and `C_Spell.GetSpellCooldown` at `:3276`.
3. **The `state.X = <api>` snapshot block** at `Hk State.lua:740-790` (51 lines).
   - Every APL script and every class-pack function is `setfenv`'d to `state` (`Hk Scripts.lua:1045, 1077, 1281`;
     `Hk Classes.lua:182, 269, 411, 418, 427`).
   - `state`'s `__index` never falls back to `_G`: an unknown key logs an error (`Hk State.lua:2577`) and
     `state._G = 0` (`:827`).
   - So class code sees only those 51 names.
   - The exceptions are pack `RegisterEvent` callbacks and CLEU hooks, which run in `_G`. `RegisterHook` skips
     `setfenv` for the CLEU hook (`Hk Classes.lua:700-702`); Arms calls `UnitPower` at `:716` in `_G`.

Four ways to make "same calls" resolve to the facade:

| Option | Covers | Lines touched | Verdict |
|---|---|---|---|
| (a) Override the globals and `C_*` table fields in `_G` before Hekili loads | all three | 0 in Hekili | **Not viable.** Any `_G` write by addon code taints that variable, and Blizzard's own UI calls `UnitPower`, `C_Spell.GetSpellCooldown` and the aura APIs. Tainted Blizzard code then also sees secrets as untouchable, which breaks the unit frames, action bars and cooldown frames. Swapping and restoring during load taints just the same. |
| (b) Mechanically rewrite the import lines to a facade table (`local UnitPower = Facade.UnitPower`) | (1) only | about 59 | **Insufficient.** It misses the about 680 call-time references, `state`'s snapshot block is a third copy, and pack `RegisterEvent` callbacks call globals directly. Making it complete means rewriting every call-time reference too. |
| (c) **Per-file environment**: one line, `setfenv(1, ns.FacadeEnv)`, after `local addon, ns = ...` in each Hekili file | (1), (2) and (3); class-pack files too | **about 16–20**: Hekili, Utils, Formatting, MultilineEditor, Constants, State, Events, Classes, Targets, Options ×2, UI, Scripts, Core, plus each class file | **Viable, and the cheapest.** See below. |
| (d) Patch `Hekili.State.UnitPower = …` from a later add-on | (3) only | 0 | Partial: the upvalue locals are out of reach |

How option (c) works:
- `ns.FacadeEnv` is `setmetatable(facadeTable, { __index = _G, __newindex = <forward to _G> })`, built by a first
  file in Hekili's TOC (after `embeds.xml`) or by a dependency add-on.
- `setfenv` is already part of Hekili's own runtime: it uses it about 40 times.
- File-top captures then read the facade at load. Call-time globals resolve through it on every call. The `state.X`
  snapshot block copies facade functions, so APL and pack code are covered with no further change.
- `__newindex` must forward to `_G`, because Hekili defines true globals (the addon object,
  `Hekili_GetRecommendedAbility`, binding strings, slash commands). Those writes happen today anyway.

What option (c) still cannot reach:
- **The embedded libraries.** LibRangeCheck, LibSpellRange and LibCustomGlow load from `embeds.xml` in their own
  chunks. Their range reads are mostly plain on Forever [W PR7], but `UnitInRange` (secret always) and whatever
  item-range checks RangeCheck uses are not covered. The libraries are not in the checkout, so this is unverified.
- **XML handlers** (`Bindings.xml`). These only call Hekili methods.

### C.2 "Same events": the event half

The drawing gives the addon events from the state half's queues. In Hekili this means three things.

**1. Hekili's own `RegisterEvent` must not reach the client for virtual events.**
- `ns.RegisterEvent` (`Hk Events.lua:158`) calls `events:RegisterEvent(event)` at `:163` on a real frame (`:46`).
  For `COMBAT_LOG_EVENT_UNFILTERED` that raises the forbidden popup.
- Inside the environment, a facade `CreateFrame` can return the real frame with an instance-level `RegisterEvent`
  that diverts virtual event names to a facade subscription. Hekili's frames are insecure, so this is legal.
- The alternative is one edit at `:163`.

**2. Payload facades for events whose payload is secret** (not just call facades):
- `UNIT_AURA` (`Hk Events.lua:1517`, `if data.isFullUpdate`: a boolean test on a secret raises [O12]);
- `UNIT_POWER_FREQUENT` (`:1450-1452`, compares `UnitPower` values; covered by the `UnitPower` facade);
- `UNIT_SPELLCAST_*` for `target` (`:1220`, which indexes `class.abilities[spellID]` with a secret `spellID`
  [O4]).

The facade either rewrites these payloads (for example, a synthetic `isFullUpdate = true` whenever the belief's aura
set changes) or drops the `target` registrations.

**3. The virtual CLEU itself.**
- Hekili's registration closure (`:2016`) calls `CombatLogGetCurrentEventInfo()` as a call-time global from
  `Events.lua`'s environment.
- The facade can define that function to return the event being delivered and then invoke the frame's `OnEvent`.
  The whole chain (`CLEU_HANDLER`, `ns.callHook` to the packs) then runs unchanged.
- **The delivery shape survives. The timing doesn't, unless it changes:**
  - **Hekili ignores the CLEU timestamp** and stamps everything with `GetTime()` at handler entry (`:1731`).
    - Swing anchors (`:1937-1945`), debuff `applied` and `last_seen` (`Hk Targets.lua:787-824`) and the history time
      (`:1122`) all take the delivery time.
    - Delivering from a queue "once per frame" shifts them by up to a frame (7–17 ms; harmless).
    - Inferred events emitted later shift them by the inference delay: an attribution window (0.1–0.5 s) or a
      retraction after a DODGE. That is a direct phase error in the swing clock and the DoT grid.
    - Two remedies: emit observed events immediately and synchronously (`PLAYER_SWING`, our successes, deaths are
      all exact at their own event), or have the facade's `GetTime` return the event's timestamp while it delivers.
  - **Ordering against Hekili's update thread.**
    - The update coroutine is started from an `OnUpdate` (`Hk UI.lua:2377-2400`) and runs `state.reset` inside it.
    - The library's "lazy processing on the first reader call" would fire *inside* that coroutine. It would then
      deliver `AddToHistory`, `trackDebuff` and swing writes in the middle of a reset, against state Hekili has
      already copied.
    - So the facade must publish from its own event handlers (the urgent lane) or from an `OnUpdate` guaranteed to
      run before Hekili's engine frame. It must never publish from within a Hekili call.
  - **Re-entrancy.** A derived event published from inside a pack hook is dropped (`Hk Classes.lua:3883`).
  - **Every Hekili CLEU consumer survives delivery from the queue**, provided four conditions hold:
    1. observed rows are delivered synchronously;
    2. inferred rows carry a back-dated clock;
    3. delivery never nests in a Hekili call;
    4. the B.4 payload contract is kept.

### C.3 "Blocked: use state", decided per call by `issecretvalue()`

Deciding per call with `issecretvalue` on the real result is cheap and adapts on its own. It is what TDF's
`Sources.Plain` does (`TDF src/TacoDogForever/Sources/Sources.lua:42`). Cases it can't decide:

| Case | Examples | What to do instead |
|---|---|---|
| **The call errors** instead of returning a secret | `C_UnitAuras.GetAuraDataByIndex` on a target in combat raises "Auras cannot be accessed when secret while tainted" ([W] §4, gate spike) | `pcall` first (TDF does, `Sources/Auras.lua:74`), or ask the plain predicate `C_Secrets.ShouldAurasBeSecret()` first |
| **The call returns nil** for "hidden" | `GetPlayerAuraBySpellID` returns nil in combat (Catnip, [W] §4), so it reads as "no aura"; `GetSpellCooldown(61304)` returns nil; `C_SwingTimer` returns nil always | No secret to test. Use the `C_Secrets.Should*BeSecret` predicates or a known-absent list |
| **A plain table with mixed fields** | `C_Spell.GetSpellCooldown`: `isActive` and `isOnGCD` plain, start and duration secret (also 520 B per call) | Test field by field and merge the plain flags with belief times |
| **Plain but wrong for Forever** | `GetSpecialization` returns pseudo-spec 1491; `IsPlayerSpell` reports rank 1 only; on-next-swing strikes are always "in range" [W PR7]; `InCombatLockdown` is false inside `PLAYER_REGEN_DISABLED` [W §3]; a `UnitIsDead` poll misses the death edge [O6] | Translation rules in the API half; `issecretvalue` can't see these |
| **The call itself has a cost** | Calling the real API just to test the result | Cache per frame; prefer the plain predicates (`ShouldUnitStatsBeSecret`, `ShouldAurasBeSecret`, `ShouldUnitPowerBeSecret`, `ShouldUnitSpellCastingBeSecret` [W PR2, PR8]) to skip the call |
| **Secret always** | `UnitPower` for rage, energy and mana; target health | No need to test; route straight to state |

### C.4 What Hekili caches, and the invariants an estimate breaks

**Per reset** (`Hk State.lua:6787-7136`), Hekili takes these as truth:
- `res.actual`, `max`, `active_regen` and `inactive_regen` → `forecastResources` (`:6896-6929`);
- player health (`:6959-6961`);
- swing speeds and the next swings (`:6964-6973`);
- totems (`:6869-6874`);
- auras, scraped into `ns.auras[unit]` records with `applied`, `expires`, `count`, `caster` and `v1`–`v3`
  (`:5956-6173`);
- the cast in progress (`:7027-7108`).

**Per first access in a reset:** each `cooldown.x` record (`:3262-3273`, `:3283-3393`).

**Across resets:**
- cast history (`AddToHistory`);
- `ns.trackDebuff`'s per-GUID table;
- `swings.*_actual`;
- the TTD samples;
- `lastPower` (`Hk Events.lua:1450`);
- `state.predictions`.

**Invariants a belief with error breaks, silently.** Hekili has no notion of confidence anywhere: no `issecretvalue`,
no intervals, no "unknown". Each read is treated as either exact or absent, and "absent" means a default:

| Read | Hekili's assumption | What an estimate does |
|---|---|---|
| Resource | `ns.hasRequiredResources`: `state[resource].current >= spend` (`:7786-7788`); `TimeToReady` and `TimeToResource` do exact arithmetic (`:3719`, `:7831`) | Recommends an unaffordable spender, or waits on rage that is already there. The game's own answer (`IsSpellUsable`, plain [SU]) is consulted only for abilities that declare `usable = <spellID>` (`:7655`) |
| Cooldown | `cooldown.x.remains` = start + duration − now (`:3374-3376`); `ready` follows | An early or late pick by the error |
| GCD | Equality trick: a spell's cooldown that equals the GCD's start and duration is zeroed (`:3348-3351`) | The facade must return *bit-identical* numbers for GCD-locked spells (when `isOnGCD` is true) or every spell looks on cooldown |
| Aura | `expires` absolute; `up` = `expires > query_time` | A refresh window or pandemic logic off by the error |
| Health | `target.health.current` defaults to 100000 when unattackable (`:3230-3233`); `pct` is computed | Unknown health becomes "full": every execute-phase line is silently false |
| TTD | `DEFAULT_TTD = 30` (`Hk Targets.lua:1184, 1372`) | Unknown becomes 30 s |
| Combo points | Exact | Fine: plain (Rogue, gate spike) |
| `UnitCastingInfo` | Exact | Fine: plain for the player [W PR9] |

**Stateless reads tolerate jumps; the across-reset caches don't.** Because Hekili re-reads everything at each reset,
a belief that jumps (a pin, a correction) is absorbed at the next reset with no special handling. That is an
advantage of the shape. The across-reset caches are the exception: a correction to a past fact (a dodged Rend) must
reach them as a compensating event (B.2 E8a, D.3).

### C.5 What no facade absorbs: edits to Hekili itself

| Edit | Where | Why |
|---|---|---|
| GCD spell 61304 → 29515 | `Hk Classes.lua:2906`; `Hk UI.lua:1500, 1701`; `Hk Events.lua:1924` | A constant, not a call (the facade *could* alias 61304, but the constant is clearer) |
| `UnitHealth(unit) > 1` in the enemy scan | `Hk Targets.lua:424, 501, 628` | A comparison on a value that is secret always. The facade can return a constant instead, but then the filter is meaningless; replace it with `not UnitIsDead` |
| TTD | `Hk Targets.lua:1279-1328, 1563-1603` | Stub it to the setting constant |
| Spec identity | `Hk Classes.lua:1369-1457, 4091-4378`; `Hk Events.lua:365` | One pseudo-spec per class (1491); Arms, Fury and Protection come from talents. [Hk-classic] already registers one spec per class (`Classic/Warrior.lua:8`, `NewSpecialization( 1 )`) with packs per role |
| Talents | `Hk Events.lua:416-464` | Rewrite to the `C_Traits` walk |
| Remove CLEU registrations | `Hk Shadowlands/Trinkets.lua:1959` (deleted in cleanup); `Hk Events.lua:2016` (divert, C.2) | The forbidden popup |
| Version gates | `Hk Hekili.lua:15, 38-52`; `Hk Core.lua:203` | Build 16001 reads as "not retail" in some checks, and `IsRetail()` stays true [R3] |
| Division by zero | about 300 `/` sites ([Splice] §2.3) | The client raises on x/0. Belief zeros (unknown max, uncalibrated regen) make them likelier |
| Load-time nils | `Hk UI.lua:43`; `Hk Constants.lua:32` | Facade stubs |

That is **about 15 edit sites in roughly 8 files**, plus the about 16–20 environment lines and the class file.

### C.6 Belief fields mapped to Hekili-shaped results (the API half's return values)

| Hekili reads | Shape it expects | Belief field | Gap |
|---|---|---|---|
| `UnitPower(p, t)` | integer current | resource `est` (or `lo`, to never over-promise) | No interval reaches Hekili |
| `UnitPowerMax` | max | passthrough (plain) | — |
| `GetPowerRegenForPowerType` → `inactive, active` | per-second rates | cached plain out-of-combat read; the calibrated rate | Hekili's swing-rage models (`swing = "mainhand"`) need the swing clock and speed instead (below) |
| `C_Spell.GetSpellCooldown(id)` | `{ startTime, duration, isEnabled, modRate, isActive, isOnGCD }` | `readyAt` and the learned length: `startTime = readyAt − duration`; flags passed through | When `isOnGCD` is true, return the GCD's numbers exactly (C.4). `modRate` is 1. Talent cooldown reductions need class data |
| GCD (61304 → 29515) | start and duration | `isActive` rising edge = start; duration = 1.5 / haste (the belief), learned from the falling edge | Haste in combat comes only from swing durations (melee) |
| `GetSpellCharges` | current, max, start, duration | charge belief | Unprobed; no Warrior use |
| `C_UnitAuras.Get{Buff,Debuff}DataByIndex(unit, i)` | AuraData: `name, icon, applications, duration, expirationTime` (absolute), `sourceUnit, spellId, timeMod, points` | the belief's aura records (applied, expires, stacks), synthesised in index order | No `points` (`v1`–`v3`: absorb and tooltip values). No other players' auras on the target. No `auraInstanceID` (it must be invented). No `isStealable` or `dispelName` |
| `GetPlayerAuraBySpellID` | AuraData or nil | the same | nil is ambiguous on Forever (C.3) |
| `UNIT_AURA` payload | update table | synthetic `isFullUpdate = true` on belief change | Hekili then rescans with `ForEachAura` (`Hk Events.lua:1517-1525`): fine |
| `UnitAttackSpeed` | mh, oh | `PLAYER_SWING` durations (exact, include haste) and the out-of-combat cache | — |
| Swings (CLEU) | `SWING_DAMAGE` / `SWING_MISSED` at landing | `PLAYER_SWING` (plain, per hand) | Outcome (MISS, DODGE) from `UNIT_COMBAT` arrives separately |
| `UnitSpellHaste`, `GetMeleeHaste` | percent | melee: base ÷ observed − 1; spell: the last plain read | Spell haste procs are invisible in combat |
| `UnitCastingInfo("player")` | name … `startTimeMS, endTimeMS` … | passthrough (plain [W PR9]) | — |
| `UnitChannelInfo` | the same | passthrough, guarded | Channels unprobed |
| `UnitHealth/Max("target")` | numbers | **none** | Secret always. A percent curve gives only a secret, and Execute usability gives only a "below 20 %" boolean |
| `UnitHealth("player")` | numbers | none (unprobed; `UNIT_COMBAT` gives deltas, not absolutes) | Defensive lines are dead |
| `GetTotemInfo` | `present, name, start, duration, icon` | from casts (totem classes) | Early totem death is a timing-only signal |
| `GetUnitSpeed("player")` | speed | `IsPlayerMoving` → 7 or 0 | — |
| `UnitDamage`, `UnitAttackPower`, ratings | numbers | out-of-combat cache | Stale under combat buffs |
| `GetTalentInfoByID` | rank, known | the `C_Traits` walk mapped to Hekili talent keys | Needs a mapping table per class |
| `GetSpecializationInfo` | retail spec ID | a translation of 1491 to the pack's spec | — |
| `CombatLogGetCurrentEventInfo` | the 22-field tuple | the queued derived event (B.4) | No source for hits on us. No overkill, absorbs or third parties |

---

## D. Calibration: who keeps the virtual state honest?

### D.1 Hekili has no correction loop, and needs none of its own

- Hekili rebuilds its picture from reads at every reset. It never corrects a model against an observation, because
  on retail it never had to.
- On Forever the reads that matter are not observable in combat (A.3), so honesty over a 3-minute fight must come
  from the state half.
- The drawing has no correction arrow: Observation log → Log processor → Virtual state is one-way. **The correction
  loop is the log processor's job.** It is TDF's belief, which pins itself to observed events:
  - usability flips pin a resource to that ability's cost, and the set of usable abilities bounds it (the cost
    ladder);
  - `PLAYER_SWING` anchors the swing clocks, and the same-frame power burst marks a landed swing;
  - `isActive` edges snap cooldowns;
  - `UNIT_COMBAT` DODGE, MISS and PARRY retract a strike's effects;
  - leaving combat and plain out-of-combat reads re-sync everything.

  (`TDF Model/Belief.lua` header; spec §6.)

### D.2 Whether the loop can live entirely in the state half

**Yes for mechanics; no for knowledge.** The loop needs to know, per class:
- what each cast costs and gains;
- what each swing pays (the rage rate × weapon speed rule);
- each aura's duration and each cooldown's length;
- what talents change.

TDF's belief gets this by running *TDF's own compiled class spec* on its virtual state ("our own casts run the
abilities' use step and handlers", `TDF Model/Belief.lua:1-10`). In the proposed layering that knowledge lives in
Hekili's class file, which the state half cannot run:
- Hekili's `spend` and `handler` functions are `setfenv`'d to the singleton `state`.
- `state` has no second instance ([Splice] §0).

So the state half needs **its own registration of class facts**. There are two ways to get it:

1. **Data-driven nowcast.**
   - Costs, durations, cooldowns and periods come from the Forever DB2 (TDF's `TacoDogForever_Data`).
   - Per-class rules come as small declarative tables: swing rates, on-next-swing strikes, proc triggers, talent
     modifiers.
   - The Hekili class file and the library both consume the same data file. This is a partial dual model: dynamic
     talent logic still lives twice.
2. **A ladder-only nowcast** (a Phase 1 that truly "makes no forecasts").
   - The resource is pinned only by usability flips and bounded by the cost ladder, with no carry-forward between
     pins.
   - It needs only the cost list, and `GetSpellPowerCost` is plain (Catnip, [R0]).
   - Hekili's own resource forecast then runs from that pinned value.
   - The error is the ladder gap: 5–15 rage for Warrior costs of 10, 15, 20, 25 and 30.
   - Cooldowns: `readyAt` = our cast time + DB2 length, snapped by the `isActive` falling edge. Talent reductions are
     unknown until the first edge.
   - Auras: cast plus DB2 duration, refreshed or retracted by `UNIT_AURA` keys and `UNIT_COMBAT`.

   This is honest and cheap, but coarse. Since Hekili can't show uncertainty, it is also invisible: the picks will
   simply be wrong more often near thresholds.

**The user's Phase 1 phrase "no future prediction" holds for the event stream.** But the virtual *state* cannot
answer `UnitPower`, `cooldown.remains` or `expirationTime` in combat without carrying values forward from anchors.
That carry-forward is prediction of the present, with provenance `modelled` ([V] §1). Phase 1 must include it.

### D.3 Does Hekili need changes to tolerate corrections?

- **Reset-time reads: no.** A jump is absorbed at the next reset (C.4).
- **Across-reset caches: yes, but through the event channel, not code.** A retraction must arrive as a compensating
  CLEU event:
  - `SPELL_AURA_REMOVED` for a debuff the bus had applied before a DODGE was observed;
  - `SPELL_MISSED` for the strike.
  - Hekili handles both (`Hk Events.lua:1982-1983`; history is not retracted, the same as retail).
  - The cast history keeps the dodged strike: retail's CLEU also logs `SPELL_CAST_SUCCESS` for a dodged ability.
- **Confidence: unreachable by Hekili without changes.** A cheap, Hekili-free use of confidence is for the facade to
  choose *which* bound to return per read type:
  - resources at `lo` (never recommend the unaffordable; the game's usability already says "now");
  - target auras' `expires` at the early bound (refresh sooner rather than late).

  Exposing confidence to the addon (fuzzy/now, the reduced-APL mode, the wait layer) needs Hekili code. One path is
  [Splice] §2.4 option (c): re-run slot 1's `TimeToReady` at the low and high bounds, about 1.2× the cost. Another is
  a view-model field (section G).

---

## E. Phase 3: cleanup size

### E.1 What goes

Figures were re-measured on `forever`, and every [R3] figure reproduced. The research branch was cut at the same
commit.

| Part | Lines | Action |
|---|---:|---|
| Whole repo Lua | 147,511 | — |
| Class and expansion folders | **104,532** (71 %) | Delete. This includes TWW 89,177 (absent classes DK, DH, Monk, Evoker 22,902; the nine Forever classes' retail spec modules 62,892), Shadowlands 6,602, BfA 5,692, Dragonflight 2,405, others 656, plus 5,305 `.simc` lines. The 62,892 retail modules are mined for APL ideas, not ported |
| Root engine | 28,587 | Keep about 24.6–25.0k. Remove about 3,700–4,000 |
| Options | 12,679 | Keep about 11.0–11.2k (`Archive.lua` 677, retail panels about 700, one-time fixes about 90) |
| `Libs/` | 1,656 (SpellFlashCore only) | **Add** the 25 packager externals: the checkout cannot load without them ([R3]; `embeds.xml:2-27`) |

Engine removals, by system:
- `Classes.lua` shared retail content: about 1,400 lines. PvP trinkets `:3439-3785`, Dragonflight and TWW potions
  `:2685-2884`, retail group buffs, about 300 of the racial lines.
- `State.lua`: about 700. Azerite and legendary `:4474-4554`; empower, `hero_tree`, `pvptalent`; the trinket
  stat-stick zoo `:412-720`, shrunk; about 277 commented-out lines.
- `Constants.lua`: about 460. `HeroTrees` `:310-552`; retail specializations `:103-300`, shrunk.
- `Events.lua`: about 330. Azerite and essence `:483-641`.
- `UI.lua`: about 300. Empowerment; SpellFlash and Masque optional.
- `Utils.lua`: about 250. Covenants `:779-870`; loadout export `:948-1092`.

**After cleanup:** about 37k Lua lines in all (engine plus Options plus UI about 36k), before any Forever class pack.

### E.2 What stays but changes behaviour

About **2,000–2,500 engine lines** are the secrecy zone. The facade reduces most of them to "unchanged text, new
data":
- cooldown metatable `Hk State.lua:3258-3535`;
- `ScrapeUnitAuras` `:5956-6173`;
- `state.reset` `:6787-7136`;
- the `UNIT_POWER`, `UNIT_AURA` and CLEU handlers;
- `Targets` CLEU and TTD (about 720);
- UI cooldown and delay arithmetic (`Hk UI.lua:1495-1516, 1700-1746`);
- spec detection (`Hk Classes.lua:4091-4378`).

The C.5 edits remain.

### E.3 `origin/classic` vs `forever` as the base

| | `origin/classic` | `forever` |
|---|---|---|
| Target | Classic Era 1.15 (TOC 11505), forked from retail in Aug 2022; diff +7,575 / −8,585 on the 8 engine files | final retail 11.2 |
| Talents | spell-ID rank ladders read with `IsPlayerSpell` (`Classic/Classes.lua:10-43`) and `GetTalentTabInfo` (`:49-51`). **Both are dead on Forever** [W PR5] | `GetTalentInfoByID` (dead). `C_Traits` appears only in loadout export. **Neither base has a working talent reader** |
| Swing-based rage | `state.swings`, swing-resource forecasting (`classic State.lua:179, 1525, 5183-5276`); Warrior rage per swing from `UnitDamage` (`Classic/Warrior.lua:14-24`), secret in combat and wrong for Forever (rage = rate × weapon speed) | **The same machinery** (`Hk State.lua:200, 1558, 1674-1680, 5712-5754`; retail Fury uses `swing = "mainhand"`) |
| API namespaces | legacy bare globals (`GetSpellInfo` ×21, `UnitBuff`, `GetSpellCooldown`, `IsUsableSpell`), about 85 sites ([Splice] §1.1) | `C_Spell`, `C_UnitAuras`, `C_SpellBook`, all present on Forever |
| Spec model | one spec per class with role packs (`Classic/Warrior.lua:8`) | spec IDs 71–73 (must change) |
| GCD spell | 29515 (`classic UI.lua:1322`) | 61304 (must change) |
| Warrior prior art | on-next-swing Heroic Strike and Cleave queueing (`:496-569`), `IsCurrentSpell` detection (`:615`), the Overpower dodge window from CLEU (`:445`), 3 APL packs | retail TWW only |

**`forever` is the better engine base.** Classic's one structural advantage, the single-spec class model, is about 90
lines of `NewSpecialization` and `SpecializationChanged` work to replicate on `forever`. Its namespace debt costs
more than that. Mine `Classic/Warrior.lua` for structure (the queueing and `should_queue` logic, settings, packs),
not code: its rage formula, talent ladders and CLEU dodge window are all wrong or dead on Forever. This agrees with
[R4] and [Splice] §1.1.

---

## F. Phase 3b: the Warrior proof of concept

### F.1 Hekili files that change

| File | Change |
|---|---|
| New facade bootstrap (first in the TOC, or a dependency add-on) | builds `ns.FacadeEnv`; the `CreateFrame` and `RegisterEvent` diversion; the `CombatLogGetCurrentEventInfo` provider |
| Every remaining engine file (about 16) | one `setfenv(1, ns.FacadeEnv)` line |
| `Classes.lua` | GCD 29515; one-spec-per-class registration and spec detection by talents |
| `Events.lua` | the `C_Traits` talent reader; the GCD anchor line `:1924`; drop the `target` unit registrations of the spellcast events, or facade their payloads |
| `Targets.lua` | the plate filter without `UnitHealth`; TTD stub |
| `UI.lua` | GCD 29515. Cooldown arithmetic works once the facade returns plain belief numbers: plain `SetCooldown` with plain numbers works in combat [W PR22] |
| `Hekili.lua`, `Core.lua` | version gates |
| Division-by-zero audit | on the reset, the resource and the cooldown paths at least |

### F.2 The Warrior class file

It is new: Hekili's `RegisterResource`, `RegisterAbilities` and `RegisterAuras` format, carrying what TDF's Warrior
pack learned. Each point below is cited to `TDF src/TacoDogForever_Warrior/Warrior.lua` unless noted.

- **Rage per swing by weapon speed.**
  - Rate × unhasted speed: 3.46 for a main-hand one-hander, 4.5 for a two-hander, 1.73 × the Dual Wield
    Specialization multiplier for the off hand (`:21-35`).
  - Hekili's resource models already take `swing = "mainhand"` / `"offhand"` with a `value` function
    (`Hk-classic Classic/Warrior.lua:42-80`; `Hk State.lua:1558`).
  - The value function must read the weapon size from gear (plain [W PR13]), not `UnitDamage`.
- **Per-hand swing clocks.** Hekili keeps `mh_actual` and `oh_actual` per hand, fed by the virtual `SWING_*` from
  `PLAYER_SWING` with its type 0 / 1 [W PR3].
- **Heroic Strike and Cleave paid at the swing**, with no main-hand rage from that swing.
  - `Hk-classic Classic/Warrior.lua:496-498` already models it (`swingSpend`, a buff until the next swing, the main
    hand paying 0 while it is up, `:58`).
  - The queued state comes from `IsCurrentSpell`, plain [W PR1].
- **Unbridled Wrath as a proc model.**
  - TDF uses an effectiveness curve beyond a 3 s close horizon (`:292-312`).
  - Hekili has no probabilistic income. The nearest is an expected-value regen term (a `regenModel` entry). That
    puts proc rage inside the near horizon, which TDF deliberately avoids.
- **Victory Rush.** A 30 s cooldown on Forever plus the 20 s Victorious window ([O] §20 item 6; `TDF src/TacoDogForever_Data/Generated/Spells.lua:1165`, spell 402927).
  Neither Hekili branch has it.
- **Reactive gates.** Overpower, Revenge, Execute and Victory Rush are gated on the game's plain usability
  (`TDF Gates.lua`, one `<key>_ready` aura per ability).
  - In Hekili: `usable = function() return IsUsableSpell(id) end` through `state.IsUsableSpell`
    (`Hk State.lua:763`), or a `reset_precast` hook writing gate auras.
  - Execute must be gated this way, because `target.health.pct` is a constant (C.4).
- **Talents.** Ranks from the `C_Traits` walk (52 nodes for the probed Warrior), mapped to Hekili talent keys.
  Forever-specific values (Improved Heroic Strike −1 per rank, Improved Slam, Improved Execute) as in TDF's
  constants (`:41-60`).
- **Stance rage retention** (10, Tactical Mastery from level 14) and the rage decay at rest (1.25 a second, from the
  plain out-of-combat regen read [W PR16]).

Size and reuse:
- **Estimated size:** about 1.2–1.8k lines. `Hk-classic Classic/Warrior.lua` is 1,781 and TDF's Warrior pack is 1,046
  (Warrior.lua 670 + Gates 137 + Protection 173 + Register 66).
- **APLs: reuse TDF's.** `TDF src/TacoDogForever_Warrior/APLs/{arms,fury,protection}.simc` (132 lines) are SimC
  dialect. They reference gate auras (`buff.execute_ready`, `buff.bloodthirst_ready`) that the Hekili class file must
  define under the same names.

### F.3 The minimal facade set to run `state.reset()` and the Warrior loop on a dummy

1. **Reset:**
   - `UnitPower` (rage belief), `UnitPowerMax`, `GetPowerRegenForPowerType` (cached);
   - `UnitHealth`/`UnitHealthMax` (constants);
   - `UnitAttackSpeed` (swing belief);
   - `GetTotemInfo` (empty);
   - `GetBuffDataByIndex` and `GetDebuffDataByIndex` (synthesised from the aura belief: Battle Shout, the stances,
     Rend, Sunder, Thunder Clap, Demoralizing Shout).
   - `UnitCastingInfo` passes through (Slam is a 1.5 s cast [W PR9]).
2. **Per recommendation:**
   - `C_Spell.GetSpellCooldown` (merged flags and times, GCD 29515), `GetSpellLossOfControlCooldown` (nil),
     `UnitSpellHaste` and `GetMeleeHaste`;
   - `GetUnitSpeed` (moving), `C_Spell.IsSpellUsable` (passthrough), range (passthrough or library).
3. **Events:**
   - the virtual CLEU (`SPELL_CAST_SUCCESS`, `SWING_*`, `SPELL_AURA_APPLIED` and `REMOVED` for our debuffs, deaths);
   - the `UNIT_AURA` payload;
   - `UNIT_POWER_FREQUENT` (comparison on facade values);
   - `PLAYER_REGEN_*` (plain).
4. **Spec and talents:** the 1491 translation; the `C_Traits` walk.

That is about 20 facade functions, 4 event facades and the CLEU provider.

### F.4 Effort for Phase 3b

The unit is the lane-hour, as in [Port] (a lane is 1–3 h of wall clock, run in parallel):

| Step | Lane-hours |
|---|---:|
| Make Hekili load on Forever: vendor 25 libraries, TOC 16001, version gates, delete content (Phase 3) | 10–14 |
| C.5 edits plus the environment lines plus spec and talents | 8–12 |
| Warrior class file in Hekili format (F.2) plus APL port | 12–20 |
| Division-by-zero audit of the hot paths | 3–5 |
| In-game debug loop: no headless harness for Hekili, so every check is in game; about 4–6 sessions of a user hour plus 2 h of fixes | 12–18 |
| **Phase 3b total** (excluding the library and the facade) | **45–69** |

---

## G. Phase 4: view model plus TDF's display

### G.1 What Hekili's UI reads

- **Writer:** `Hekili.Update` (`Hk Core.lua:1561-2237`) fills `ns.queue[display][i]` (`Hk Hekili.lua:158`). The
  display frames are `ns.UI.Displays` = `Hekili.DisplayPool` (`Hk UI.lua:889-891`), bound as `d.Recommendations`
  (`:2080, 2141`).
- **Slot fields written:**
  - identity: `index, display, pack, list, listName, action, actionName, actionID, hook, script, scriptType`;
  - presentation: `texture, caption, indicator, empower_to`;
  - timing: `wait, waitSec, time, exact_time, delay, since`;
  - other: `depth, interrupt, castStart, resource, resource_type, resources{}, keybind, keybindFrom`.

  The writes are at `Hk Core.lua:1229-1256, 1346-1392, 1974-1998, 2015-2041`.
- **Reader:** `d:OnUpdate` (`Hk UI.lua:1108-1672`), `RefreshCooldowns` (`:1700-1746`) and `CalculateAlpha`
  (`:975-1027`).
  - From a slot it reads only `actionName, caption, indicator, keybind, exact_time, texture, empower_to`
    (`:1166-1221`).
  - From `class.abilities[action]` it reads about 12 fields.
  - From the display config it makes about 148 reads.
  - Its own game reads are the GCD and cooldown swipe arithmetic (`:1495-1516, 1700-1746`), range through the
    libraries (`:1583-1586`), usability (`:1604-1606`), the overlay glow (`:1250, 1306`) and `IsCurrentSpell`
    (`:1208, 1850`).

### G.2 Where to cut the boundary

**Cut at the per-display `Recommendations` array.**
- Core publishes entries `{ key, abilityId, texture, caption, indicator, keybind, readyAt = exact_time, gcd,
  rangeSpell }` through one call that replaces `UI.NewRecommendations`, `UI.RecommendationsStr` and
  `UI:OnUpdate(1000)` (`Hk Core.lua:2174-2180, 2227-2230`).
- The UI stops touching `class`.
- Cooldown, range and usability reads move behind the same facade.

### G.3 Can TDF's `Model/ViewModel.lua` and `Views/TwoZones.lua` sit on it?

**Only in a reduced form.** TDF's view model (`TDF src/TacoDogForever/Model/ViewModel.lua:1-11`) is built from
*three* simulations (estimate, low, high). It carries:
- the slot kind: Now, Committed with an ETA range, or Fuzzy;
- a now-set;
- per-slot `why` (an `Enum.Wait` reason) and idle time;
- slot 1's spend gate (an input, an operator and a threshold, which drives the secret-gated curve in the wait layer);
- tracks of target auras that outlive the horizon;
- a ReducedApl mode flag (`Model.BLIND_AFTER`).

Hekili's queue has one simulation and none of the three-bound fields:

| TwoZones needs | From Hekili | Cost |
|---|---|---|
| Slot actions and times | `actionName`, `exact_time` | free |
| Now / Committed / Fuzzy | — | needs bound re-runs ([Splice] §2.4: about 1.2× for slot 1 only, 3× for all) |
| `why` (resource, cooldown, cast, window) | Hekili decides it inside `TimeToReady` (`Hk State.lua:7831-8000`) but does not record it | an edit there to record the binding wait |
| Spend gate (resource and threshold) | the spend of the slot's ability (`class.abilities[x].spend`) | derivable |
| Tracks | `state.debuff` records | derivable |
| ReducedApl | — | facade knowledge (no fresh usability anchor), exported |

TwoZones itself reads only the view model and calls Render for secrets (`TDF Views/TwoZones.lua:1-17`), so it ports
once an adapter fills the model. The adapter costs about 20–30 lane-hours with the slot-1 bound re-run, plus the
Hekili edits for `why`. Without the re-run, every slot is "certain", which loses the product's differentiator
([Splice] §4.2 risk 3).

---

## H. Comparison with the current TDF path

### H.1 What each phase would reuse

| Proposal phase | From TDF unchanged | From Hekili | New |
|---|---|---|---|
| 1. Virtual state library | `Sources/*.lua` (about 5.8k lines; already `Plain`-guarded and zero-alloc); `Model/ObsLog.lua`; the belief families' *rules* (`Model/Belief/*.lua`, about 4.2k); probe-derived constants; DB2 data | — | The bus (ring, cursors, masks, urgent lane, persisted tail); the belief split into processors; a data-driven class-facts registration (D.2), because TDF's belief runs TDF's compiled spec, which the library can't take along |
| 2. Virtual game API | `Sources.Plain`; the secrecy knowledge in [W] §4 | the read inventory (A) | About 20 call facades, 4 event facades, the CLEU provider, the environment and `CreateFrame` diversion, Hekili-shaped result synthesis (C.6) |
| 3. Cleanup | — | about 37k lines kept | — |
| 3b. Shim plus Warrior | Warrior knowledge and APLs (F.2) | the engine, Scripts, Core, Options, UI | The Warrior class file in Hekili format; the C.5 edits |
| 4. View model | `ViewModel.lua`, `TwoZones.lua`, Render | the queue | The adapter; Hekili edits for `why` and bounds |

### H.2 Remaining effort to "Warrior playable in game with a Hekili-equivalent options UI"

Both paths use lane-hours.

**The shim path:**

| Item | Lane-hours |
|---|---:|
| Phase 1 library: bus 10–15, processor extraction from the TDF belief 15–25, class-facts registration and Warrior facts 5–10, tests | 35–50 |
| Phase 2 facade: environment, about 20 calls, 4 event facades, CLEU provider, result synthesis, tests (the facade itself can be tested headless) | 20–30 |
| Phases 3 and 3b (F.4) | 45–69 |
| Hekili's options UI | 0 (it *is* Hekili's) |
| Phase 4 (only for TDF's display) | +20–30, optional |
| **Total, without Phase 4** | **≈ 100–150** |

**The TDF path:**

| Item | Lane-hours |
|---|---:|
| Phase 5 (targets, range, interrupts, cycling, spec switching, SimC dialect; Mage and Shadow deferred) | ≈ 28 of the 31.75 planned, lanes partly dispatched |
| Phase 7 display parity | 16.25 |
| Phase 8 options parity (the look lane already merged) | ≈ 15–19.5 |
| Phase 9 remainder (the G084 editor merged) | ≈ 6–9 |
| In-game shakedown after the gap | 6–12 |
| **Total** | **≈ 65–85** |

- "Warrior playable" alone, without options parity, is the shakedown plus fixes: Phases 0–4 are complete.
- [Port] gives the TDF numbers. The shim numbers are this document's estimates, with wider error bars: none of it
  has been tried, and Hekili has no headless harness.

### H.3 Risks

**TDF path:**
- **Nothing has loaded in game since the morning of 2026-10-14.** Many TOC lines were added since, and a full client
  restart is needed. Four phases of headless-verified code meet the client together, so the first session may find
  several integration faults at once.
- Options and display parity is still reimplementation (Phases 7–9). Every Hekili behaviour is matched by reading,
  not by copying.
- The parity scoreboard has 37 open gaps.

**Shim path:**
- **Hekili's engine assumes exact reads (C.4).** Every belief error becomes a confident wrong pick with no visible
  doubt. The fuzzy/now distinction exists only with Hekili edits plus the Phase 4 adapter.
- **A dual class model (D.2).** Hekili's class file and the library's class facts must agree. Drift is silent.
- **No headless harness.** Hekili's engine can only be verified in game. A missed secret read throws inside the
  update coroutine and blanks the display (`Hk UI.lua:2421-2432`). The facade narrows this, because the
  environment catches every call, but libraries and new reads bypass it.
- **The performance budget.** TDF measures 1.2 ms for a Fury in-combat recalculation, with allocation tests in CI.
  Hekili allocates per update (coroutine per update, `GetSpellCooldown` 520 B per call, string building) and was
  never profiled on Forever ([Splice] §3). The facade adds belief synthesis per read.
- **A frozen upstream and no licence.**
  - The README announces the project's end (`36daec38`).
  - There is no licence file on any branch ([Strategy] §1), so publishing Hekili code needs its maintainers'
    permission. Running it privately does not.
  - About 413 of the commits are the user's own, mostly on the classic line.
- **Phase 1's library has value on both paths.** The bus is already agreed as TDF's next step, so its cost is not
  unique to the shim.

---

## I. Verdict

**Possible with changes to Hekili; not possible as is.**
- The drawn layering works for the parts of Hekili that only *consume* `state`: the simulator, the APL compiler,
  Core, Scripts, the options and most of the UI. Those can run unchanged on facade values.
- It fails "as is" at three points:
  1. **The state half must nowcast** rage, cooldown remaining time and aura expiries from anchors. That needs class
     facts the library can't borrow from Hekili's singleton `state`, so either a data-driven class-facts
     registration (a partial second model) or a coarse ladder-only nowcast.
  2. **Hekili consumes every read as exact.** It has no confidence, no unknown and hard thresholds (`current >=
     spend`, `expires > query_time`, the GCD equality trick, health defaulting to full), so estimates turn into
     confident picks.
     - Corrections reach it safely only at reset or as compensating events.
     - The uncertainty that distinguishes TDF needs Hekili edits.
  3. **"Same calls, same events" needs plumbing on Hekili's side.**
     - A per-file environment (about 16–20 one-line edits) is required, because overriding globals taints
       Blizzard's UI.
     - A `RegisterEvent` diversion and a synchronous, back-dated virtual combat log are required, because Hekili
       stamps CLEU with `GetTime()` and its update thread must not see mid-reset deliveries.
     - About 15 edits no facade absorbs: the GCD spell, health comparisons, spec 1491, talents, version gates and
       the division-by-zero audit.

None of this is impossible. The proof of concept is roughly 100–150 lane-hours to a playable Warrior with Hekili's
options, against roughly 65–85 on the TDF path. It trades TDF's measured headless verification and uncertainty
display for Hekili's mature options and long tail.

---

## Appendix: open facts that would change estimates

- Player health secrecy (`UnitHealth("player")`), `UnitPower(…, ComboPoints)`, `GetShapeshiftForm`, channels, stats-
  family getters, `C_PetBattles.IsInBattle` and `GetNumClasses` presence: all unprobed (A.2).
- LibRangeCheck-3.0 and LibSpellRange internals on Forever: the libraries are not in the checkout.
- The `setfenv(1, env)` line on Forever's Lua: Hekili's runtime already relies on `setfenv` for functions. A
  `/run setfenv(1, setmetatable({}, {__index=_G})) print(UnitPower)` check settles chunk-level use.
- Whether the client fires a popup for `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` on an *insecure frame
  diverted before registration*: the diversion means the client never sees it, so no probe is needed if the
  diversion is total.
