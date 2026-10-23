# Can the client's damage meter (`C_DamageMeter`) help our beliefs?

Date 2026-10-23. Branch `forever-damagemeter-research` from `forever` 093313ae. Docs only; no addon code changes.
Question (owner): can `C_DamageMeter` help attribution of our own outcomes, resource estimates or enemy counting?

Sources: the Forever generated docs `Blizzard_APIDocumentationGenerated/DamageMeterDocumentation.lua` [DM:line] and
`DamageMeterConstantsDocumentation.lua`; Blizzard's `Blizzard_DamageMeter` addon (Forever UI source); ForeverMeter
(`dldvlpr-addons-wow/threatMeter`, `ForeverMeter.lua`, read 2026-10-23) [FM:line]; the ForeverProbe O capture of
2026-10-14 (`~/src/ForeverProbe/results/ForeverProbe-2026-10-14-O.lua`, row N49 of
`docs/research/tdf/2026-10-14-virtual-combat-log-events.md`) [MEAS O7].

## 1. API inventory

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
O session (2028 in combat), both args plain every time, types seen 0, 1, 2, 3, 5, 7, 10 [MEAS O7].

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
(pets fold into their owner). Note `combatSpellDetails` is documented as one struct, not a list; probe it.

What is absent: no per-event record, no timestamps (only session duration and a death time), no hit, crit or miss
counts, no target GUID (only `unitName`), no threat, no resource.

Blizzard's own UI reads only these getters, rebuilds a fresh data provider per update, and compares
`combatSource.totalAmount ~= sourceWindow:GetTotalAmount()` (`DamageMeterSessionWindow.lua:629`): legal for it because
untainted code may compare secrets; an addon may not.

## 2. What ForeverMeter does

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

## 3. Our beliefs against the API

How we consume outcomes today: `Game/Events/Rows.lua` turns `UNIT_COMBAT` (victim-side: unit, action, flag, amount,
school; no source, no spell) into rows; `Game/Events/Tickets.lua` opens a ticket per commit and pays it from those
rows by kind, school, window and learned amount band; `Game/State/Families/Resources.lua` steps rage from credited
swings and calibrates regen between pins. The gaps: K16's raid cold start (others' same-school rows pay our bolt
tickets before any amount band is learned, unit-registry spec §6, line 805), crowd precision (`docs/dev/gaps.md:65`),
Task 9b (crediting an uncredited swing's rage, recovery spec §0).

| Belief / gap | What the meter could give | What stays impossible |
|---|---|---|
| Per-row attribution (tickets, Rows) | Nothing in combat: every amount, spellID and target name is under a `SecretWhenInCombat` getter; the update event carries only (type, sessionID) | Pairing a `UNIT_COMBAT` row with a source: the meter has no per-event data or timestamps |
| K16 cold start (amount band before 3 clean wounds) | After a fight (plain): our `totalAmount` per spellID, overkill, and per-target amounts. With our own success count per spell, total / casts seeds a band centre for the *next* fight, unbiased by misattribution (it is the server's truth, not our credits). Persisting it covers a /reload or relog | The first fight of a session. No hit count, so total / casts mixes misses and crits; a seed, not a band |
| Labelling foreign rows (crowd precision) | In combat at most ordinal facts, if table lengths are plain (unmeasured): `#combatSources` > 1 for DamageDone means another group member (pets folded in) has dealt damage this session; our rank via `isLocalPlayer` | Which row is foreign, per target or per moment: amounts and `unitName` are secret, and the session is cumulative |
| Recall / false credit audit | After a fight: per-spell meter total vs the sum our tickets paid for that spell, a free per-fight ground truth (a debug readout or harness calibration from real play) | In-combat correction |
| Rage / energy (Resources) | After a fight: DamageTaken (type 7) total for the player vs our credited `taken` gains, to audit the learned taken rate | Any in-combat resource read; the meter has no resource data |
| Enemy counting (Enemies) | EnemyDamageTaken (type 10) sources out of combat, or `#combatSources` in combat if plain: enemies damaged this session, cumulative, dead ones included | A live count of engaged enemies |
| Threat | None (`DamageMeterType` has no threat; ForeverMeter uses `UnitDetailedThreatSituation`) | Everything |
| Timing pulse | `DAMAGE_METER_COMBAT_SESSION_UPDATED` fires in combat with a plain type (2028 in one session [MEAS O7]): a "someone in the group did type N" tick | Who, how much, which target; batching delay unmeasured |

Cost: each getter builds fresh tables (the session, every source, every spell). That breaks the no-allocation rule in
a recurring path, so any use must be a one-shot read out of combat (`PLAYER_REGEN_ENABLED` plus a short retry while
the first amount is still secret), never per event or per poll. The update event itself is cheap but fired 2028 times in one O session's combat [MEAS O7].

## 4. Secret-safety constraints

- The read would be a `Sources/` concern (`Game/State/Sources/`), the only layer that may see a secret. It must test
  `issecretvalue()` on each field before any comparison, arithmetic, sort or table key, and drop the whole read if
  any amount is secret (ForeverMeter's one-flag rule [FM:975] is not enough for us: test each value we use).
- No `a and b or c` on a meter field. `#list` and `isLocalPlayer` are the only in-combat reads we could rely on, and
  only after a probe shows them plain.
- Passing a secret back as an argument (a secret `sourceGUID`) is `AllowedWhenUntainted`: forbidden to us. Use
  `UnitGUID("player")` or `sourceCreatureID`.
- Values may stay secret for a moment after combat [FM:1715] and possibly under encounter or instance restrictions
  (`ADDON_RESTRICTION_STATE_CHANGED`); the docs do not say. Plain out of combat is the documented case only.

## 5. Probe list (ForeverProbe, `/vslog` recorder)

The docs under-report secrecy; confirm before any design. Open-world mobs only (no target dummies on Forever).

1. `/vslog add DAMAGE_METER_COMBAT_SESSION_UPDATED DAMAGE_METER_CURRENT_SESSION_UPDATED DAMAGE_METER_RESET`, solo
   melee and solo caster fight: event ms against our `UNIT_COMBAT` rows; is a type-0 tick within one frame of each of
   our hits (batching delay, one tick per hit or per throttle)?
2. Same in a party next to another player: does a type-0 tick fire for their hits too (it should; confirms the
   pulse is group-wide, not ours)?
3. In combat, one read per second of `GetCombatSessionFromType(1, 0)`: `issecretvalue` of `totalAmount`,
   `maxAmount`, `durationSeconds`, and per source of `totalAmount`, `amountPerSecond`, `sourceGUID`, `name`,
   `sourceCreatureID`, `sourceDisplayType`, `deathTimeSeconds`; is `#combatSources` plain; is `isLocalPlayer` plain
   (doc: NeverSecret).
4. In combat, `GetCombatSessionSourceFromType(1, 0, UnitGUID("player"))`: `#combatSpells` plain? `spellID`,
   `totalAmount`, `overkillAmount`, `creatureName` secret? Is `combatSpellDetails` a struct or a list, and is
   `unitName` / `amount` secret?
5. `GetSessionDurationSeconds(1)` in combat: plain (no `SecretWhenInCombat` in the doc)?
6. After `PLAYER_REGEN_ENABLED`: ms until `totalAmount` first reads plain (ForeverMeter waits up to 3 s).
7. Type 10 (EnemyDamageTaken) out of combat after a 3-mob pull: one source per mob? `sourceCreatureID` and GUID
   plain? Dead mobs listed?
8. Out of combat, our per-spell `totalAmount` against the sum of our logged `UNIT_COMBAT` WOUND amounts for that
   spell (solo): equal (same server numbers) or off (absorbs, overkill)?
9. Inside an instance or a scripted encounter, if one is reachable: repeat 3 and 6, and log
   `ADDON_RESTRICTION_STATE_CHANGED`.

## 6. Verdict

`C_DamageMeter` cannot help in-combat attribution, resource estimates or enemy counting: every getter is documented
`SecretWhenInCombat`, the data is aggregated per session with no per-event records, timestamps, hit counts, target
GUIDs, threat or resources, and its only plain in-combat signal is an update event that names a meter type, not a
source or target. What it does offer is a free, unbiased ground truth once combat ends: our damage per spell (and per
target name) and damage taken, which can seed the next fight's amount bands (a partial answer to K16's cold start,
for every fight but the first) and audit our tickets' recall and false credit from real play. Two in-combat ordinals
(the source count and our rank) might be plain and would hint that others are hitting, but they are cumulative and
untargeted, so they cannot fix crowd precision. Worth one probe session (section 5); worth building only as an
out-of-combat calibration read in `Sources/`, and only if the probe confirms the post-combat values come back plain
within a second or two.
