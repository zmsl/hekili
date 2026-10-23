# Can the client's damage meter (`C_DamageMeter`) help our beliefs?

Date 2026-10-23. Branch `forever-damagemeter-research` from `forever` 093313ae. Docs only; no addon code changes.
Question (owner): can `C_DamageMeter` help attribution of our own outcomes, resource estimates or enemy counting?
Revised the same day with three in-game captures (section 3); the first version's verdict (no in-combat use) is
withdrawn.

Sources: the Forever generated docs `Blizzard_APIDocumentationGenerated/DamageMeterDocumentation.lua` [DM:line] and
`DamageMeterConstantsDocumentation.lua`; Blizzard's `Blizzard_DamageMeter` addon (Forever UI source); ForeverMeter
(`dldvlpr-addons-wow/threatMeter`, `ForeverMeter.lua`, read 2026-10-23) [FM:line]; the ForeverProbe O capture of
2026-10-14 (row N49 of `docs/research/tdf/2026-10-14-virtual-combat-log-events.md`) [MEAS O7]; and the `/vslog meter`
captures of 2026-10-23 [CAP A/B/C] (ForeverProbe b7922ea, `Log.lua`; owner pastes, solo Fury Warrior L25 (Forsaken)
at Bael'dun; condensed copy `damagemeter-solo-2026-10-23.log` in the session's captures folder). Times are ms.

## 0. Verdict

`DAMAGE_METER_COMBAT_SESSION_UPDATED` is a plain, per-event announcement of **our own** damage, healing and damage
taken, at the server's resolution time, in any crowd. Every getter is still secret in combat, but the event needs no
getter: its `(type, sessionID)` arguments are plain, and the session is per player. A type-0 (DamageDone) group fires
0-11 ms after each `PLAYER_SWING` that hits and never for one that misses, dodges or is parried (99 swings, 0
exceptions), while the white swing's own `UNIT_COMBAT` row typically comes 0.1-1.45 s later; instants and DoT ticks fire
a group in the frame of their row. Other players', pets' and NPCs' damage on our target, and others' heals, fire nothing
(capture B session 167: seven foreign rows on our Rifleman, no group; capture A: a foreign fire row, no group). Type 7
(DamageTaken) fires for each hit on us, 0.39-0.57 s before a mob's melee row, and never for our dodge, parry or a miss.
So the event gives the ticket model three things it cannot get elsewhere: a swing's hit-or-avoid at the swing (Task 9b:
rage credited at the swing, amount corrected by the row), a count of our own damage events against which a surplus row
is foreign (crowd precision), and the mobs' hit times on us early (Attackers). After combat the getters read plain on
the first try and the totals equal the sum of our rows exactly in four fights (923, 3739, 873, 973), a free ground truth
for amount bands and recall audits. The API works with the Damage Meter disabled in the game options. Build it as a
`Sources/` event consumer feeding a preallocated tick ring (section 7); read the getters only out of combat.

## 1. Captures

| Capture | Sessions | Setting | Content |
|---|---|---|---|
| A (691 rows) | 163, 164 | meter on | fight 1: one Bael'dun Soldier, 6.8 s; fight 2: Soldiers and Riflemen, 50 s; in-combat reads (types 0, 7, duration), REGEN watch, out-of-combat reads (types 0, 10) |
| B (1228 rows incl. A) | 165, 166, 167 | meter **disabled** in options | 165 solo; 166 others fighting other mobs nearby; 167 other players and a pet hitting our target; in-combat type 10, out-of-combat type 10 |
| C (154 rows) | 168 | meter on | clean solo fight, REGEN watch |

Each damage group is several events in one or two ms: types 0, 10 (EnemyDamageTaken) and usually 1 (Dps; missing from
some groups in B and C) for the session id, and again for session id 0. Heals give types 2
and 3; hits on us give type 7. `DAMAGE_METER_CURRENT_SESSION_UPDATED` (no args) starts a new session id 8-10 ms after
the opening cast of each fight (22721 to 22731, 57868 to 57876, 19933 to 19942, 300139 to 300148).

## 2. Fight 1, swing to tick to row (capture A, session 163)

White rows paired first in, first out: the avoid rows fall exactly where the tickless swings are, here and in capture C.

| Swing (hand) | Type-0 group | Group - swing | Our row (white unless noted) | Row - group | Row - swing |
|---|---|---|---|---|---|
| 23248 (MH) | none | | MISS 24081 | | 833 |
| 23449 (OH) | 23454 | 5 | WOUND 44 at 24901 | 1447 | 1452 |
| 24756 (MH) | 24764 | 8 | CRIT 163 at 25290 | 526 | 534 |
| 24974 (OH) | none | | DODGE 25290 | | 316 |
| 26209 (MH) | 26217 | 8 | CRIT 129 at 26596; same group: Touch of the Grave 89 school 32 at 26211 (-6) | 379 | 387 |
| 26456 (OH) | 26460 | 4 | BLOCK_REDUCED 39 at 27563 | 1103 | 1107 |
| (Rend 6547 tick, cast 24224) | 27237 | | CRIT 37 at 27236 (nameplate1; `target` 27237) | -1 | |
| 27703 (MH) | 27704 | 1 | CRIT 125 at 28241 | 537 | 538 |
| 27999 (OH) | 28004 | 5 | CRIT 85 at 29172 | 1168 | 1173 |
| 29233 (MH) | 29244 | 11 | CRIT 151 at 29366 (nameplate1 only, after `TARGET none` 29239); same group: Firebolt 23267 61 school 4 at 29234 | 122 | 133 |

Eight groups for ten damage rows: a group is a server batch, not a row. The proc (26211) and the weapon proc Firebolt
(29234) share their swing's group; the Rend tick has its own. The heal half of Touch of the Grave (player HEAL 89 at
26320) fired types 2 and 3 at 26322. Sum of our rows: 44+163+89+129+37+39+125+85+61+151 = 923 = the meter total.

## 3. Measured

**Swings.** All 99 swings in A, B and C (51, 38, 10): a type-0 group within 0-11 ms of `PLAYER_SWING` exactly when the
swing hit; the 15 tickless swings match the 15 avoid rows on our target (MISS, DODGE, PARRY), including a Heroic Strike
dodged at 104055.
Row lag behind the group: 122-1447 ms in A, 0.66-1.37 s in C (connection-dependent; base §3.3.2 already treats it as
learned).

**Instants and procs** (Heroic Strike, Overpower, Execute, Victory Rush, Firebolt, Touch of the Grave): the row comes
in the cast's frame and the group 3-14 ms after it (Overpower 26122 to 26126, Execute 27675 to 27688 in C). A Heroic
Strike also logs a zero `WOUND 0` row 1 ms before its real row (91090, 92598, 95585 `BLOCK 0`).

**Periodic damage** (Rend ticks: 27236, 61462, 64589, 103853, 106908 in A; 26847 in C): a group 1-2 ms after the
row, or merged into a coincident swing's group (306391, 309451 in B; 23886 in C). Confirmation only, no early timing.

**Kills.** Groups are not tied to the `target` token: fight 1's last group came 5 ms after `TARGET none`, and the
killing blows' rows land later on `nameplateN` or `softinteract` only.

**Damage taken (type 7).** 23 type-7 groups in A, each paired with a hit on the player. Ten rows came 389-565 ms after
the group (fight 1: 24235 to 24651 WOUND 27, 28235 to 28638 WOUND 24), presumably melee; two at 50 and 148 ms; the rest
within 5 ms either side (fight 2 had Riflemen; shots or spells, unidentified); self-damage (Bloodrage at 100354) also
ticks. No group for any DODGE, PARRY or MISS on the player (26610, 59913, 61887, 63094, 72110, 75365, 84342). One player
WOUND (95453) had no group of its own (possibly merged into 95053's).

**Crowd.** Capture B session 167: our first target (a Rifleman) took 56 school 32, 58 s32, 11 s1, 64 s1, 130 s2, 128
s2, 33 s32 and 354 s32 from other players and a pet between 300447 and 302601; we swung once (300676, group 300677).
The meter's out-of-combat type-10 read gives our Rifleman damage as 64: the one group owned exactly one row (64 at
301065, 388 ms after the group) and the other seven, including the school-1 11 at 300978, are foreign. Our Soldier
damage (809) equals the sum of our rows on its plate (nameplate6). Session 166: groups only at our swings while others
fought nearby. Capture A fight 2: a foreign 8 school 4 on nameplate3 (83405) fired no group, and the meter total 3739
equals our rows (3747) minus that row. Others' heals (277137, 296404, 310210) fired no type 2.

**Getters in combat** (A and B): session `totalAmount`, `maxAmount`, `durationSeconds`, every source's GUID, name,
totals, `sourceDisplayType`, death time, every spell's `spellID`, amounts and name: secret. Plain: `#combatSources`
(1 for types 0 and 7; 2 for type 10 = enemy creature types we damaged), `#combatSpells` (1 to 4, growing with our
spells), `isLocalPlayer`, `classFilename`, the type-7 details' `unitClassFilename` and `classification`.
`combatSpellDetails` is one struct, not a list. Type 10's `creatureID` is secret in combat.
`GetSessionDurationSeconds(1)` is plain in combat (14 at 71879, 5 at 283446).

**Getters out of combat.** At `PLAYER_REGEN_ENABLED` the total read plain on the first try (0 ms; A, C): 923 and 973
(C: 47+62+88+44+63+18+53+67+60+69+81+18+182+77+44). Per-spell totals with plain spellIDs (fight 2: Auto Attack 6603
2561 of 3739, Heroic Strike 1608 411, Execute 20647 265, Touch of the Grave 1260198 178, Firebolt 23267 109, Rend 6547
92, Overpower 7384 79, Victory Rush 402927 44); overkill 0 throughout. The meter's spell ID is the damage effect's,
not the cast's (Execute cast 5308, meter 20647). Type 10 lists one source per creature type, `guid` nil (3376 Bael'dun
Soldier 1896, 3377 Rifleman 1843), after those mobs died; not per GUID. Its session `totalAmount` (2050) did not equal
the sum of its sources (3739) in fight 2 but did in session 167 (873 = 809 + 64): unexplained, use the per-source rows.

**Disabled option.** With the Damage Meter turned off in the game options (B) every event, in-combat read and
out-of-combat read behaved the same. The API is not gated by the player's UI setting.

## 4. API inventory

Functions (all in `C_DamageMeter`; the MCP listing shows `secretArguments` but drops `SecretWhenInCombat`, so the
secrecy column quotes the raw doc):

| Function | Args | Returns | Secrecy (raw doc) | Blizzard UI use |
|---|---|---|---|---|
| `GetCombatSessionFromType` | sessionType (Overall 0, Current 1, Expired 2), type (`DamageMeterType`) | `DamageMeterCombatSession` | `SecretWhenInCombat = true`, `SecretArguments = "AllowedWhenUntainted"` [DM:41-42] | `DamageMeterSessionWindow.lua:571`, rebuilt into a data provider on each update |
| `GetCombatSessionFromID` | sessionID, type | `DamageMeterCombatSession` | `SecretWhenInCombat = true`, `SecretArguments = "AllowedWhenUntainted"` [DM:23-24] | `DamageMeterSessionWindow.lua:576` |
| `GetCombatSessionSourceFromType` | sessionType, type, sourceGUID?, sourceCreatureID? | `DamageMeterCombatSessionSource` (per-spell list) | `SecretWhenInCombat = true`, `SecretArguments = "AllowedWhenUntainted"` [DM:79-80] | `DamageMeterSourceWindow.lua:161` (the click-through breakdown) |
| `GetCombatSessionSourceFromID` | sessionID, type, sourceGUID?, sourceCreatureID? | same | `SecretWhenInCombat = true`, `SecretArguments = "AllowedWhenUntainted"` [DM:59-60] | `DamageMeterSourceWindow.lua:166` |
| `GetSessionDurationSeconds` | sessionType | number? | `SecretArguments = "AllowedWhenUntainted"` only [DM:99]; no `SecretWhenInCombat` | `DamageMeterSessionWindow.lua:294`, every frame while the in-combat timer shows |
| `GetAvailableCombatSessions` | none | list of {sessionID, name, durationSeconds?} | none documented | `DamageMeterSessionWindow.lua:417` (session menu) |
| `IsDamageMeterAvailable` | none | isAvailable, failureReason | none; measured plain [MEAS O7] | `DamageMeter.lua:175` (with the `damageMeterEnabled` CVar) |
| `ResetAllCombatSessions` | none | none | none | `DamageMeterSessionWindow.lua:507` |

Events: `DAMAGE_METER_COMBAT_SESSION_UPDATED (type, sessionID)`, `DAMAGE_METER_CURRENT_SESSION_UPDATED`,
`DAMAGE_METER_RESET` [DM:133-153]. No `SESSION_EXPIRED` on 1.60 [FM:1685]. Measured: 2034 COMBAT_SESSION_UPDATED in one
O session (2028 in combat), both args plain every time, types seen 0, 1, 2, 3, 5, 7, 10 [MEAS O7]; per-event
semantics in section 3.

Structures and field-level secrecy [DM:157-244]:

| Structure | Fields | Field annotations |
|---|---|---|
| `DamageMeterCombatSession` | combatSources (list), maxAmount, totalAmount, durationSeconds? | none |
| `DamageMeterCombatSource` | sourceGUID?, sourceCreatureID?, name, classFilename, specIconID, totalAmount, amountPerSecond, isLocalPlayer, deathRecapID, deathTimeSeconds, classification, sourceDisplayType (None/Ally/Enemy), factionGroup? | `sourceGUID` and `name`: `ConditionalSecret = true`; `classFilename`, `specIconID`, `isLocalPlayer`, `deathRecapID`, `classification`: `NeverSecret = true` |
| `DamageMeterCombatSessionSource` | combatSpells (list), maxAmount, totalAmount | none |
| `DamageMeterCombatSpell` | spellID, totalAmount, amountPerSecond, creatureName, overkillAmount, isAvoidable, isDeadly, combatSpellDetails | none |
| `DamageMeterCombatSpellUnitDetails` | unitName, unitClassFilename, classification, isPet, isMob, amount, specIconID | `unitClassFilename`, `classification`, `specIconID`: `NeverSecret = true` |

`DamageMeterType`: DamageDone 0, Dps 1, HealingDone 2, Hps 3, Absorbs 4, Interrupts 5, Dispels 6, DamageTaken 7,
AvoidableDamageTaken 8, Deaths 9, EnemyDamageTaken 10. `DamageMeterOverrideType` includes `RedirectSourceToOwner`
(pets fold into their owner).

What is absent from the getters: no per-event record, no timestamps (only session duration and a death time), no hit,
crit or miss counts, no target GUID (only `unitName`), no threat, no resource. The per-event signal is the update
event itself (section 3).

Blizzard's own UI reads only these getters, rebuilds a fresh data provider per update, and compares
`combatSource.totalAmount ~= sourceWindow:GetTotalAmount()` (`DamageMeterSessionWindow.lua:629`): legal for it because
untainted code may compare secrets; an addon may not.

## 5. What ForeverMeter does

- Reads `GetCombatSessionFromType(0|1, type)` / `FromID` per window [FM:470-477] and
  `GetCombatSessionSourceFromType/FromID(…, guid)` for the per-spell breakdown [FM:480-487];
  `GetSessionDurationSeconds` as a duration fallback [FM:490-497]; `GetAvailableCombatSessions` for the session menu;
  `IsDamageMeterAvailable` for the title; `ResetAllCombatSessions` on reset [FM:1156]. Types 0, 2, 4, 5, 6, 7, 9 plus
  8 and 10 when the enum has them [FM:22-40].
- Cadence: registers the three events but only sets `needsRedraw`; an OnUpdate redraws at most every `db.refresh`
  (default 0.2 s) [FM:1638-1669, 1734], and keeps polling 3 s after `PLAYER_REGEN_ENABLED` because "amounts can stay
  secret a short moment after combat" [FM:1715]. Also redraws on `ADDON_RESTRICTION_STATE_CHANGED`.
- Secrets: its header states that in combat names, amounts and GUIDs are secret: displayable through `SetText`,
  `SetValue`, `string.format`, never compared, added or passed back to the API [FM:4-7]. It tests
  `issecretvalue(list[1].totalAmount)` once per list and, if secret, keeps the server's order, skips sorting, percent
  and per-spell comparison [FM:546-561, 975]. It finds the local player in combat by `isLocalPlayer` ("never secret")
  [FM:981-984]; another player's `sourceGUID` is used only when plain (own GUID via `UnitGUID("player")`)
  [FM:1009-1016]. `/fm report` refuses in combat [FM:1213]. Threat comes from `UnitDetailedThreatSituation`, not the
  meter, and errors out when its values are secret (boss targets) [FM:566-612].

## 6. Mapping to beliefs

How we consume outcomes today: `Game/Events/Rows.lua` turns `UNIT_COMBAT` (victim-side: unit, action, flag, amount,
school; no source, no spell) into rows; `Game/Events/Tickets.lua` opens a ticket per commit and pays it from those rows
by kind, school, window and learned amount band; `Game/State/Families/Resources.lua` steps rage from credited swings.
The open gaps: K16's raid cold start (unit-registry spec §6), crowd precision (`docs/dev/gaps.md:65`), Task 9b
(crediting an uncredited swing's rage; the attribution-recovery plan's ASSUMED state guesses it from a lag timeout).

| Belief / gap | What the meter gives | What it does not |
|---|---|---|
| Swing outcome (MELEE tickets, 9b) | Hit or avoid at the swing: a type-0 group within 15 ms of `PLAYER_SWING`, 0.1-1.45 s before the row. Rage for a hit can be credited at the swing (an estimate from the learned band), the row corrects the amount; no group means no rage and an avoid row is owed | Crit, block or glance (only the row says), the amount, which hand when both swing in one frame |
| Spell outcome (FRAME, STRIKE tickets) | Hit or avoid for an instant: a group 3-14 ms after the row; none for a dodge | Nothing earlier than the row for instants |
| Projectiles (FLIGHT) | Expected: a group at the landing, a second timing anchor for the learned lag | Unmeasured (no caster capture) |
| DoT ticks (TICKS) | A group per tick of ours, in the row's frame | Early timing |
| Foreign rows (crowd precision, K16) | Each group owes at least one own row; a row in a group's frame is ours; a delayed school-1 row is ours only while a hit swing is owed; every other row on our victims is foreign. Holds solo and in a crowd (section 3) | Which of two candidate rows is ours when both fit (300978 vs 301065): the amount band decides |
| Attackers (mob swing clock), parry-haste | Type-7 groups: the mobs' hits on us 0.39-0.57 s before the melee row, plus self-damage | The source mob; avoids on us (no group); which hits are melee |
| Healing on us | Types 2 and 3 for our own heals and procs only | Others' heals |
| Amount bands, recall audit, taken rate | After combat, plain on the first try: our total per damage spell ID, per creature type (type 10), damage taken (type 7) per spell; exact against our rows | The first fight's bands; per-target or per-GUID splits |
| Enemy counting | In combat `#combatSources` of type 10 = creature types we have damaged (plain, cumulative) | A live count of engaged enemies or GUIDs |
| Threat, resources | Nothing | Everything |

## 7. How the ticket model would consume it

- **Source.** A `Game/State/Sources/Meter.lua` registers `DAMAGE_METER_COMBAT_SESSION_UPDATED` through the event
  facade, ignores sessionID 0 (the duplicate set), and keeps types 0, 2 and 7. Events of one type within 3 ms are one
  group (29244/29245). It writes a preallocated ring (`TICKS` = 32: arrays of time and type, an integer head); no
  getter is called.
- **Swings.** A MELEE ticket whose `PLAYER_SWING` has a type-0 group in `[swing, swing + 15 ms]` is marked hit at once
  (rage estimate from the band: `Obs.Swing` "assumed" becomes evidence-driven rather than lag-timeout-driven); with no
  group by 15 ms it is marked avoid and pays the next MISS/DODGE/PARRY row. The decision waits one frame, since the
  group trails the swing by up to 11 ms. A missed swing in the same frame as a DoT tick or proc of ours would read as a
  hit; the row still settles it.
- **Spells.** An instant's FRAME ticket is confirmed by a group in its frame. A FLIGHT ticket's group at the landing (if
  the caster probe confirms it) pins the lag sample.
- **Foreign rows.** In each window, rows on our victims beyond what the open groups and owed swing tickets cover are
  foreign; Rows sends them to `background()` without spending a ticket.
- **Attackers.** A type-7 group opens a "hit on us due" mark 0.4-0.6 s ahead of the melee row; a group with a row in
  its frame is a ranged or spell hit. Avoids on us stay row-only.
- **After combat.** At `PLAYER_REGEN_ENABLED`, one read per type (0, 7, 10) in Sources, each value checked with
  `issecretvalue()` and the read dropped if any is secret, feeding band seeds and a debug recall audit.

Secret safety: the event's arguments are plain and carry no secret; the only getter reads happen out of combat in
`Sources/`, guarded field by field, never passing a value back as an argument. No `a and b or c` on a meter field.
Allocation: events only in combat, written into fixed arrays; the getters build fresh tables (session, sources,
spells), so they run once per fight out of combat, never per event or poll. Volume: about 6-12 events per hit (2034 in
one O session [MEAS O7]); the handler must return after one integer compare for discarded ones.

## 8. Open questions and probes

1. **Projectiles.** Caster capture (Druid Wrath at max range): is the group at the landing (server resolution) or the
   cast? Same `/vslog` sequence as below.
2. **Party and raid members.** Answered for strangers and their pets (no groups; capture B). Expected the same for party
   members (the session is per player); confirm once with the sequence below. Our own pet: does it fold in
   (`RedirectSourceToOwner`)? Needs a pet class.
3. **Instances and encounters.** Repeat capture C inside an instance; log `ADDON_RESTRICTION_STATE_CHANGED`.
4. **Type 10 session total** (2050 vs 3739 in fight 2): which number is it?
5. **Dual-wield frames.** Both hands in one frame (63189/63191, 64656/64657) gave one group each; a frame with one hit
   and one avoid has not been seen.

### Party probe (`/vslog`, ForeverProbe b7922ea)

Partner in your party, then repeat with the partner not grouped. Open-world mob, no target dummies.

```
/vslog clear
/vslog meter events
/vslog meter watch
/vslog on
/vslog note phase1 me alone
  (pull, swing ~5 s)
/vslog note phase2 partner joins
  (partner hits the same target; partner's pet too if any; ~5 s)
/vslog meter
/vslog meter 10
/vslog note phase3 partner alone
  (stop attacking, /stopattack; partner keeps hitting ~5 s)
  (finish the mob; wait for REGEN)
/vslog meter
/vslog meter 10
/vslog dump
```

Read: groups only at our swings in all phases (party is per player) or also during phase 3 (group-wide);
`#combatSources` in the in-combat `/vslog meter` (1 or 2).
