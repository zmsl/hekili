# ForeverProbe

A throwaway diagnostic addon for WoW Forever (Interface 16001, Midnight-style secret values). Version 0.3.0
runs the Phase 0 probes of the Taco Dog Forever port plan: PR1–PR19 (sampled API reads and event counters,
in and out of combat) and PR20–PR30 (the display analysis's in-game checks, on a check panel and a throwaway
two-zone spike frame). Session O (`/fprobe o`, new in 0.3.0) is the self-classifying combat-event probe: O1–O16
of the virtual-combat-log research. The 0.1.0 Feral sampler is kept as the "legacy" probe and still writes its
old log.

It only reads. It never compares or does arithmetic on a value before `issecretvalue()`, it logs secrets as
`"S"`, and it never divides by a value that could be zero.

## Install (link into the client)

Run this from an elevated Windows prompt (or with Developer Mode on). It creates a directory symlink in the
Forever AddOns folder:

```bat
mklink /D "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\ForeverProbe" "\\wsl.localhost\personal\home\zack\src\ForeverProbe"
```

From WSL the same command is:

```sh
cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /c mklink /D 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\ForeverProbe' '\\wsl.localhost\personal\home\zack\src\ForeverProbe'
```

Fully restart the client when the addon is new (`/reload` doesn't pick up a new addon or a new SavedVariables
name). Enable ForeverProbe in the AddOns list on the character select screen. The same holds after an update that
adds a file to the TOC (0.3.0 adds `SessionO.lua`): restart the client once, or `/fprobe o` only says that
`SessionO.lua` is not loaded. `Export.lua` (`/fprobe export`) was added the same way: restart the client once
after pulling it, or `/fprobe export` only says that `Export.lua` is not loaded.

## Commands

| Command | Effect |
|---|---|
| `/fprobe start W` / `/fprobe start D` | Start a Warrior or Druid session: arms the probes for that class, starts the legacy sampler, shows the check panel |
| `/fprobe stop` | Close the session (then `/reload` or log out to write the data) |
| `/fprobe status` | What is armed, samples and events per probe, the role spells, spike state |
| `/fprobe note <text>` | Save a remark into the session (what you saw on the panel or spike) |
| `/fprobe spike show` / `hide` / `stats` / `glide` / `reset` | The two-zone spike frame (PR25–27, 29, 30): show it, hide it, print and store its measurements, freeze/unfreeze the icons, zero the counters |
| `/fprobe panel show` / `hide` | The display-check panel (PR20–24, 28) |
| `/fprobe scale 0.8` / `1` / `1.2` | Scale the panel and the spike (halo seam check) |
| `/fprobe menu` | PR19: open a MenuUtil and a UIDropDownMenu test menu |
| `/fprobe alloc` | PR28: measure `GetSpellCooldownDuration` allocation now |
| `/fprobe on` / `off` / `clear` / `cleu` | The legacy sampler alone (0.1.0 behaviour) |
| `/fprobe wipe` | Delete all stored sessions |
| `/fprobe export` | Out of combat: dump the spellbook, the talent trees and the stances into `ForeverProbeDB.export` (overwrites the last export; then `/reload`) |
| `/fprobe o` | Start session O (or, while it runs, show its panel and a status line). Runs beside a W/D session |
| `/fprobe o stop` | End session O: restore floating combat text, print the one-screen summary (then `/reload`) |
| `/fprobe o fct` | O2: switch floating combat text off now (phase B); deferred to the end of combat |
| `/fprobe o panel` | Toggle the session O panel |
| `/fprobe o status` | One status line (also part of `/fprobe status`) |
| `/vsgrave` / `/vsgrave report` | Touch of the Grave procs and in-combat heals, combat time, procs per minute (cap 2.40), the shortest gap per channel, then the matched spell IDs, through the copy box (`Grave.lua`, always on; restart the client once after pulling it) |
| `/vsgrave reset` | Zero `ForeverProbeDB.grave` |
| `/vslog on` / `off` | Start / stop the event recorder (`Log.lua`; restart the client once after pulling it): PLAYER_SWING, UNIT_COMBAT and UNIT_SPELLCAST_SUCCEEDED for every unit token, one `<ms> <event> a b c d f` record each (secrets as `"S"`, 4000-record ring, memory only); `on` shows the last-10 frame, `off` hides it and keeps the records |
| `/vslog dump` | Every record through the copy box, oldest first, then `vslog n=<records> dropped=<n> events=<list>` |
| `/vslog clear` | Empty the buffer and reset the clock |
| `/vslog note TEXT` | Add a `<ms> NOTE TEXT` record on the same clock, e.g. `/vslog note pull at 30yd` |
| `/vslog auras [unit]` | Every HELPFUL and HARMFUL aura the client lets us read on the unit (default `target`; `targetplate` = the nameplate token naming the target), one copy-box line each (name, spellId, stacks, duration, expiration, source, dispel type, stealable, instance id; secrets as `S`) plus a summary line |
| `/vslog add UNIT_AURA` | Writes `<ms> AURA <unit> full=<bool> added=<n> updated=<n> removed=<n> first: name=.. id=.. inst=.. dur=.. exp=.. src=.. harm=..` per UNIT_AURA, the first added aura described, secrets as `S` (probe: are the counts plain in combat) |
| `/vslog plates` | One `<ms> PLATES nameplateN <unit line> combat\|ooc dead=<S\|bool> attack=<S\|bool>` record per visible plate (probe U5: plate GUID and death secrecy in combat) |
| (automatic) | Every target change writes `<ms> TARGET <name> L<level> <classification> <creature type> hp=<health>/<max> react=<reaction> player=<bool> guid=<guid>` (or `TARGET none`); `/vslog add PLAYER_FOCUS_CHANGED PLAYER_SOFT_ENEMY_CHANGED PLAYER_SOFT_INTERACT_CHANGED NAME_PLATE_UNIT_ADDED NAME_PLATE_UNIT_REMOVED` writes the same line as FOCUS, SOFTENEMY, SOFTINTERACT, `PLATE+ nameplateN` and `PLATE- nameplateN`; secret fields print `S` |
| `/vslog add EVENT [EVENT ...]` / `events` | Record more events, space-separated (kept until `/reload`) / print the list |
| `/vslog show` / `hide` | The last-10 frame alone (drag to move; position kept in `ForeverProbeDB.logPos`) |
| `/vslog auto on [probe ...]` / `off` / `status` / `dump [probe]` / `clear` | Passive launch-day probes (`swing meter cdv snap usable gate`, default all), armed across reloads and logins; each fight's records are saved to `ForeverProbeDB.auto` 6 s after combat ends and at logout (schema in `Log.lua`; `docs/launch-day.md`) |
| `/vslog gate health` / `power` / `off` | GC-T, the threshold bank (`Gate.lua`): 8 step curves (20/40/60/80% on a 0-100 and a 0-1 input) into SetAlpha, SetShown, SetAlphaFromBoolean and a clipped StatusBar; `GATE_*` records |
| `/vslog cdv target` / `poll` | CDV_TGT at each target change and the 3 frames after / toggle CDV_EDGE (item aura field changes every 0.25 s) |

## Files

- `Core.lua`: encoding, tallies, the sampling engine, event dispatch, sessions, `/fprobe`.
- `Legacy.lua`: the 0.1.0 sampler (Feral/Rogue/Warrior usability, combo points, nameplates, `C_Secrets`).
- `Probes.lua`: PR1–PR19 definitions.
- `Display.lua`: the check panel (PR20–24, 28; the PR7 tint square; the PR11 cooldown widgets).
- `Spike.lua`: the two-zone spike (PR25–27, 29, 30; halo backdrops; Edit Mode outline).
- `SessionO.lua`: session O (O1–O16): the event classifier, its correlators, its panel and `/fprobe o`.
- `Copy.lua`: the copy box (`VSCopy(...)`, `/vscopy`).
- `Grave.lua`: the Touch of the Grave proc counter (`/vsgrave`, `ForeverProbeDB.grave`).
- `Log.lua`: the event recorder and its last-10 frame (`/vslog`, `ForeverProbeDB.logPos`).
- `Gate.lua`: GC-T, the gate comparator threshold bank (driven by `/vslog gate` and `/vslog auto`).
- `Export.lua`: `/fprobe export`, the class-data dump (see "Export layout").
- `Media/halo64.tga`: the 64×64 feathered rounded-rect, generated by `tools/make_halo.py`.
- `tools/smoke.lua`: headless smoke test under stock Lua 5.1 (`lua5.1 tools/smoke.lua`).

## Where the data goes

`C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account\<ACCOUNT>\SavedVariables\ForeverProbe.lua`,
written on `/reload` or logout. Layout:

```
ForeverProbeDB.sessions["<date> <time> W|D"] = {
  kind, started, stopped, build, class, level, powerType, has = {API presence}, secretRestrictions,
  spells = { key -> {name, id|false} }, roles = { melee=, cd=, overlay=, range=, queued= },
  registration = { EVENT -> "all" | "player,target" | "E:..." }, notes = { {t, c, text} },
  PR1..PR19 = {
    title, keys (legend), n, nC (samples, in combat), errors, lastErr,
    tally = { key -> { c = {S,N,P,E,A}, o = {S,N,P,E,A}, exC, lastC, exO, lastO, err } },   -- c in combat, o out
    ring = { last 160 samples: {seq, t, ev, c, a1..a4, <keys>} },
    events = { EVENT -> { n, nC, args = { [i] = {S,N,P,ex} } } },
    facts = { one-off values }, anchors/msgs (PR3, PR17)
  },
  PR5.facts.walkO / walkC = the C_ClassTalents/C_Traits talent walk, once out of combat (first sample) and once in
    combat (first sample after PLAYER_REGEN_DISABLED): { at, combat, restr, cfg, trees, nodes, active, bought, secret,
    errors, truncated, tries, list = { {id, rp, ar, mr, en, def, spellID, spell, fb, f} }, gti = {idx1, idx2, g1t1c1},
    ips = { {id, rp, isps} x3 } }   -- rp ranksPurchased, ar activeRank, mr maxRanks, f "S"/"E"/"SE" = a secret / an errored call
  DISPLAY = { panel results: halo_*, pr20_*, pr21_*, pr22_*, pr23 = {piece -> ok}, pr24_*, pr28_alloc* },
  SPIKE = { regions, frames, bodyAvgMs, bodyMaxMs, fpsShown, fpsHidden, maxGapPx, avgGapPx, buildMs, buildKB, errors },
}
```

Value codes: `"S"` secret, `"nil"`, `"E:<msg>"` the call errored, `"-"` the API is absent, `"=text"` a plain
string, otherwise the plain number or boolean. Tally codes: S secret, N nil, P plain, E error, A absent.

The 0.1.0 log stays at the top level: `samples`, `events`, `runs`, `registration`, `legend`.

## Export layout

`/fprobe export` (out of combat; refused in combat) overwrites `ForeverProbeDB.export`. Every client call runs
under `pcall`. Values use the Core encoding (`"S"`, `"nil"`, `"E:<msg>"`, `"-"`, `"=text"`, number, boolean) except
that strings are not cut at 80 characters, and a returned table is copied whole, every field encoded the same way
(a secret table is `"S"`; a secret key appears as `["<secretKey>"] = true`; nesting deeper than 6 is `"<deep>"`).
`{n, ...}` holds every return of a multi-return call.

```
ForeverProbeDB.export = {
  meta = { when, version, time, level, class, build = {n, version, build, date, interface},
           spec (GetSpecialization), specInfo (C_SpecializationInfo.GetSpecialization) },
  numSkillLines,
  skillLines = { [i] = { info = GetSpellBookSkillLineInfo(i) } },          -- name, itemIndexOffset, numSpellBookItems, offSpecID
  spells = { { index, line,                                                -- spellbook slot, skill line
      item = GetSpellBookItemInfo(index, Player),                          -- itemType, name, subName, spellID, actionID, isPassive, ...
      itemName = {n, name, subName},                                       -- GetSpellBookItemName
      -- only when item.spellID is a plain number:
      info = C_Spell.GetSpellInfo, desc = GetSpellDescription,
      tip = { {l = leftText, r = rightText}, ... },                       -- C_TooltipInfo.GetSpellByID lines (stance, cost, cd, range, rank)
      cost = GetSpellPowerCost, charges = GetSpellCharges, cd = GetSpellCooldown, passive = IsSpellPassive,
      override = GetOverrideSpell, known = C_SpellBook.IsSpellKnown, knownOrBook = IsSpellKnownOrInSpellBook,
      isPlayerSpell = IsPlayerSpell } },
  talents = { configID, configInfo = C_Traits.GetConfigInfo,
    trees = { { id, info = GetTreeInfo(cfg, id),
      nodes = { { id, node = GetNodeInfo(cfg, id),                         -- ranks, entryIDs, activeEntry, visibleEdges, ...
        entries = { { id, entry = GetEntryInfo, def = GetDefinitionInfo,   -- definitionID; spellID, overrideName, ...
                      info, desc, tip } } } } } } },                       -- the definition spell, as for spells ("Rank x/y")
  stances = { current = GetShapeshiftForm(), num = GetNumShapeshiftForms(),
              forms = { [i] = {n, icon, active, castable, spellID} } },   -- GetShapeshiftFormInfo(i)
}
```

## Reading the results

For every PR the question is "which keys are `P` in combat (`tally[key].c.P`) and which are `S`". The runbook
in TacoDogForever (`docs/research/2026-10-13-port-probes-runbook.md`) maps each probe to the gap it decides.

## Session O: combat events (O1–O16)

The sixteen one-line probes of TacoDogForever `docs/research/2026-10-14-virtual-combat-log-events.md` §5 in one
session. `/fprobe o` registers every candidate event at once (each `RegisterEvent` under `pcall`), classifies every
argument of every firing automatically, and stores the result in the session record. Nothing is per-probe: fight,
tick the panel's checklist, `/fprobe o stop`, `/reload`. It never registers `COMBAT_LOG_EVENT_UNFILTERED`,
`COMBAT_LOG_EVENT` or `COMBAT_LOG_MESSAGE` (forbidden-action popup).

Floating combat text (O2): the session saves your `enableFloatingCombatText` value, turns it **on** (phase A),
and after 120 s of combat in phase A turns it **off** (phase B) at the next out-of-combat moment, announcing it on
screen. `/fprobe o fct` forces the switch. The original value comes back on `/fprobe o stop`, on logout/reload,
and, if the client crashed, at the next load. The CVar is never set in combat.

| Id | Question | Events / correlator | Square |
|---|---|---|---|
| O1 | Is `UNIT_COMBAT` plain for target and player (event, flags, amount, school)? | `UNIT_COMBAT` buckets player, target, S | payload args 2–5 |
| O2 | Is `COMBAT_TEXT_UPDATE`'s type plain, and does it need FCT on? | `COMBAT_TEXT_UPDATE` bucket A (FCT on) / B (off) / X (CVar unknown), + read `C_CombatText.GetCurrentEventInfo` | type + reads |
| O3 | Does `PLAYER_SWING` fire on avoided swings; is "no rage event in the swing's frame" an avoided swing? | `PLAYER_SWING` + a player `UNIT_POWER_FREQUENT` with token `RAGE` only (energy, mana and other tokens are ignored) in the same frame = landed; each ring entry's `dtPow` is the time from the swing to the first player rage event, kept if it is at most 0.5 s (0 = same frame, absent = none within 0.5 s), so a latency-delayed rage event is told apart from an avoided swing (rage from being hit just after an avoided swing can also fill it: read `dtPow` together with `op` and the floating text); Overpower usable one frame later | `PLAYER_SWING` args |
| O4 | Do other units' casts fire, with plain castGUID / spellID / interruptedBy? | `UNIT_SPELLCAST_START/SUCCEEDED/INTERRUPTED/STOP/FAILED/DELAYED/CHANNEL_*/INTERRUPTIBLE/NOT_INTERRUPTIBLE`, non-player buckets | payload args |
| O5 | Our own interrupt: `interruptedBy` plain; loss of control data | player `UNIT_SPELLCAST_INTERRUPTED`, `LOSS_OF_CONTROL_ADDED` + `C_LossOfControl.GetActiveLossOfControlData(index)` walked | args + reads |
| O6 | Do `UNIT_DIED` / `PARTY_KILL` / `PLAYER_TARGET_DIED` register and fire with plain GUIDs; Victory Rush on our kill? | the three events + ring `{t, ev, a1, a2, dead = UnitIsDead("target"), vr = Victory Rush usable}` | args |
| O7 | Do the damage-meter events fire in combat with a plain type? | `DAMAGE_METER_COMBAT_SESSION_UPDATED`, `DAMAGE_METER_CURRENT_SESSION_UPDATED` + `C_DamageMeter.IsDamageMeterAvailable()` | args + reads |
| O8 | Is a mob's death observable through its plate? | `NAME_PLATE_UNIT_ADDED/REMOVED` + `UnitGUID` / `UnitIsDead` / `UnitCanAttack("player", token)` | args + reads |
| O9 | Does `UNIT_HEALTH("target")` fire on each DoT tick (3 s cadence with auto-attack off)? | `UNIT_HEALTH` target; inter-arrival histogram | fired = green |
| O10 | Does the overlay glow fire with a plain spell ID? | `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` | args |
| O11 | Ranged: does `PLAYER_SWING` report swing type 2; does each shot fire `UNIT_SPELLCAST_SUCCEEDED`? | swing type 2 count; player successes of Auto Shot / Shoot / Throw (75, 5019, 2480, 7918, 7919, 2764, 3018) | green = a type-2 swing; yellow = shots seen but no type-2 swing; red = no type-2 swing or shot, and some swing types were secret |
| O12 | What is plain in `UNIT_AURA`'s update table? | `UNIT_AURA` player / target / S, the table walked one level | args + fields |
| O13 | Pets and totems: which events fire, what is plain? | `UNIT_PET`, `PLAYER_TOTEM_UPDATE`, `PET_ATTACK_START/STOP`, `UNIT_HAPPINESS` + `UnitExists("pet")`, `UnitGUID("pet")`, `GetTotemInfo(1)` | args + reads |
| O14 | Does `C_CombatLog.IsCombatLogRestricted()` answer plainly in and out of combat? | sampled at start, `PLAYER_REGEN_DISABLED`, one frame later (`afterDisabled`), `PLAYER_REGEN_ENABLED`; `in` / `out` split by `InCombatLockdown()` at the sample, so the `regenDisabled` sample lands in `out` (the flag is still false inside that event) and `in` comes from `afterDisabled` | green = plain answers; dark = API absent |
| O15 | Does `COMBO_TARGET_CHANGED` fire on a target swap; is `GetComboPoints` plain? | `COMBO_TARGET_CHANGED` + `GetComboPoints("player", "target")` | args + reads |
| O16 | Does `UNIT_SPELLCAST_SUCCEEDED` fire for a dodged ability (Overpower false → true 0.1 s later)? | player successes, Overpower usable at the event and 0.1 s later, per spell ID | green = plain after-reads |

Square colours (recomputed every 0.5 s): **grey** registered, nothing fired yet; **green** fired and every
non-nil argument / read / walked field was plain (an event with no payload is green once it fires); **red** fired
and all of them were secret; **yellow** mixed; **dark** every event of the probe failed to register (or, O14, the
API is absent). For unit events argument 1 (the unit token) is left out of the colour; a secret token is the `S`
bucket and counts as secret. A read skipped because its input was secret (a secret nameplate token,
`reads.tokenSkipped`; a secret loss-of-control index, `reads.indexSecret`) counts as secret. O11, O14 and O16 use
their own rules (see the table): O11 green = a type-2 swing, yellow = shots seen but no type-2 swing, red = only
secret swing types; O14 green / red / yellow from the restriction answers, dark if the API is absent; O16 green =
the 0.1 s after-reads were plain, red = all secret.

Panel checklist (each line turns green when the session detects it): interrupt a casting mob once (a non-player
`UNIT_SPELLCAST_INTERRUPTED`); get dodged, by fighting a higher-level mob (an O16 flip, or an O3 swing with no rage
event and Overpower usable after it); apply Rend (or any DoT) then stop auto-attack for 10 s (3 target-health
deltas with auto-attack off, counted only after a `PLAYER_LEAVE_COMBAT` that followed auto-attack being on); kill one mob (`PLAYER_TARGET_DIED`, or `UnitIsDead("target")` turning true); swap
targets with combo points (Druid / Rogue only, `COMBO_TARGET_CHANGED`); optional: a ranged shot (O11).

Also classified (no square): `UNIT_POWER_UPDATE`, `PLAYER_DEAD`, `UNIT_HEALTH_FREQUENT`, `UNIT_COMBO_POINTS`,
`UNIT_THREAT_LIST_UPDATE`, `UNIT_THREAT_SITUATION_UPDATE`, `UNIT_ABSORB_AMOUNT_CHANGED`,
`UNIT_HEAL_ABSORB_AMOUNT_CHANGED`, `UNIT_HEAL_PREDICTION`, `UNIT_TARGET`, `PLAYER_TARGET_CHANGED`,
`PLAYER_REGEN_DISABLED/ENABLED`, `PLAYER_ENTER_COMBAT/LEAVE_COMBAT`, `PLAYER_IN_COMBAT_CHANGED`,
`UPDATE_SHAPESHIFT_FORM`, `ENCOUNTER_START/END`, `MIRROR_TIMER_START/STOP`, `RESURRECT_REQUEST`,
`UPDATE_INVENTORY_DURABILITY`, `PLAYER_SWING_RANGE_UPDATE`. `UNIT_HEALTH_FREQUENT` and `UNIT_COMBO_POINTS` are not in the Forever API docs
(listed in `absent`); they are still tried, so their `reg` shows the client's answer.

### Session O SavedVariables layout

```
ForeverProbeDB.sessions["<date> <time> O"] = {
  kind = "O", started, stopped, version, build, class, level, has = { API presence },
  absent = { event names not in the Forever API docs (still tried) },
  notes = { {t, c, text} },                       -- /fprobe note writes here while session O runs
  errors, lastErr,                                -- handler errors (should be absent)
  squares = { O1..O16 -> "grey"|"green"|"red"|"yellow"|"dark" },   -- final colours
  checklist = { interrupt, dodge, rend, kill, combo, ranged = true when detected },
  summary = { the 17 lines printed by /fprobe o stop },
  events = { EVENT -> {
    reg = "ok" | "E:<message>",                   -- RegisterEvent under pcall
    documented = true|false, unit = true|false,   -- unit: arg 1 is a unit token and firings are bucketed by it
    n,                                            -- firings, all buckets
    b = { bucket -> rec } } },                    -- bucket: player, target, pet, nameplate, party, raid, other,
                                                  --   S (secret token); "all" for non-unit events;
                                                  --   COMBAT_TEXT_UPDATE: A (FCT on), B (FCT off), X (CVar unknown)
  rec = { n, nC (in combat), firstT, lastT, cut (more than 10 args seen),
    args = { [i] = slot },                        -- argument positions 1..10
    fields = { [i] = { name -> slot } },          -- a plain table argument walked one level (<= 12 string keys)
    reads = { name -> slot },                     -- extra reads at firing time (see the O table)
    readFields = { name -> { name -> slot } } },  -- a plain table read walked one level (the LoC data)
  slot = { S, N, P,                               -- counts: secret, nil, plain
    types = { luaType -> n },                     -- plain values only
    samples = { <= 8 distinct plain values },     -- raw values: numbers rounded to 0.001 (nan / inf appear as the
                                                  --   strings "=nan", "=inf", "=-inf"), strings cut to 64 chars;
                                                  --   for a table-valued field, the sample is its length (#);
                                                  --   a secret table-valued field only counts S (no length taken)
    e1S, e1P,                                     -- table-valued field: its [1] was secret / plain
    ST,                                           -- plain tables that issecrettable() flagged
    api = "-", E, err },                          -- reads: absent API; error count and first message
  -- walked tables may also hold "#" (array length), "<more>" (fields beyond 12), "<secretKey>", "<walkErr>"
  O2 = { orig (the user's CVar value) | cvarErr, cur, phase "A"|"B", aCombat (in-combat s in phase A), setA, setB,
         switchedAt, switchCombatS, force, announced, inherited (took over a pending restore),
         restored (true | "=<readback>" | "E:.." | "-" | "deferred" | "handed to the next session") },
         -- setA / setB / restored: true when the CVar read back as the value set; cur is the read-back value
  O3 = { hands = { h0|h1|h2|hS|hX -> { swings, landed, noPower,
           opAfterLanded = codes, opAfterNoPower = codes } },   -- Overpower usable one frame after the swing
         opFlips (false -> true between swing checks), noPowerOpTrue, dropped,
         ring = { last 40: {seq, t, hand, dur, landed, op, dtPow} }, ringHead, ringN },
         -- landed: a player RAGE event in the swing's frame; dtPow: s from the swing to the first player RAGE
         -- event if <= 0.5 s (absent = none); op: a code letter (see codes)
  O6 = { n, deadSeen (UnitIsDead("target") turned true), targetDied, ring = { last 20: {seq, t, ev, a1, a2, dead, vr} }, ringHead },
         -- vr: Victory Rush usable as a code letter (see codes)
  O9 = { binWidth = 0.25, leaveSeen, all = { n, [1..25] }, autoOff = { n, [1..25] } },   -- target UNIT_HEALTH deltas
         -- in combat, rounded to the ms; bin i covers [(i-1)*0.25, i*0.25) s, bin 25 is >= 6 s; autoOff = while
         -- auto-attack was off, after leaveSeen (PLAYER_LEAVE_COMBAT following auto-attack on) is > 0
  O11 = { rangedSwings, rangedCasts, casts = { spellID -> n } },
  O14 = { at = { start|regenDisabled|afterDisabled|regenEnabled -> slot }, ["in"] = slot, out = slot, api },
  O16 = { successes, before = codes, after = codes, flips, dropped, nSpells,
          spells = { spellID|"S"|"other" -> { n, flips, ["<before>><after>"] = n } } },
}
codes = { t = true, f = false, S = secret, N = nil, E = error, A = API absent }   -- counts of each outcome
```

Value encoding inside the session O record: `samples` hold raw plain values (no `=` prefix: a secret never reaches
a sample; only nan / inf numbers appear as `"=nan"` / `"=inf"` / `"=-inf"`). The O6 ring's `a1`, `a2`, `dead` and
the O3 ring's `dur` use the Core encoding (`"S"`, `"nil"`, `"=text"`, number); the O3 ring's `op` and the O6 ring's
`vr` are code letters (`t`, `f`, `S`, `N`, `E`, `A`).

A session O left running across a `/reload` or a logout (no `/fprobe o stop`) has no `stopped` and no `summary`;
its `squares` and `checklist` are from the last 0.5 s tick before the reload. The floating-combat-text value is
still restored (at logout, or at the next load).
