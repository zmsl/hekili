# Launch-day probe kit (WoW Forever, 2026-11-04)

The open launch-day rows of `hekili/docs/dev/ingame-ledger.md`, one line each.

## Once per character

1. Full client restart (`Gate.lua` is new to the TOC), then `/vslog auto on`. The probes stay armed across `/reload` and
   later logins (`ForeverProbeDB.auto.armed`), so arm once per account. Chat prints `vslog auto: armed ...`.
2. Play normally. Six seconds after each fight, chat prints `ForeverProbe: saved N records for <probes>`.
3. `/reload` or log out to write the file. The controller reads
   `/mnt/c/Program Files (x86)/World of Warcraft/_forever_/WTF/Account/<account>/SavedVariables/ForeverProbe.lua`.
   There is nothing to paste for the auto rows. `/vslog auto status` shows what has been saved, and `/vslog auto dump [probe]`
   copies it into the copy box if the file cannot be read.
4. Hekili should be loaded, so the `snap` probe saves its Snapshot after each fight (the `tickets`, `providers` and
   `presence` lines).

Kinds: **auto** runs while you play. **situation** is also auto, but only records when you set the situation up
(FIGHT lines carry `party=`, `inst=`, `plates=` and `hostile=`, so the controller can filter fights later). **manual**
needs a command.

## Probes

| Id | Kind | Class | Where | What to do | Paste back |
|----|------|-------|-------|------------|------------|
| GC-T | auto (first two fights of each login) + manual | any | open-world mob | Auto: the session's first fight runs the bank on target health from your first hit, and the second fight runs it on your power. Manual repeat: `/vslog gate health`, kill a mob from full health, `/vslog gate off`, `/vslog gate power`, fight until your power has crossed 20/40/60/80, `/vslog gate off`, `/vslog dump`. Watch the bank (top centre): a square that blinks as health crosses a line is the visible gate; the finding is any `GATE_HOOK`, or a `GATE_SIG` that reads plain and changes | the manual dump only (copy box) |
| DM-B | not scripted | - | - | waits for GC-T: script it only if GC-T shows a plain StatusBar read | - |
| PHS1 | situation | (a) any melee; (b) Warrior (Parry; not a bear) | open-world mob | (a) melee a mob from the front until it has parried about ten swings, including one parried Sunder Armor; (b) tank a mob (let it hit you from the front) until you have parried about ten times. `/vslog note a` and `/vslog note b` mark the phases | nothing (auto `swing`) |
| PH-MP | situation | Warrior (Cleave or Sweeping Strikes) | two open-world mobs | pull two mobs and keep them both in front of you while you Cleave. Rows carry the `nameplateN` token and `PLATE+` maps it to a GUID. Each mob's next swing cannot be told apart in the WOUND rows on you (see Gaps) | nothing |
| PH-ED | auto | any melee | open-world mobs | normal play covers the first swing and `HCOMBAT` (Hekili's `state.combat` against VirtualState `combat=`); for a parry before the first swing, open on a mob that is already facing you | nothing |
| PH-NI | situation | Warrior (Sunder Armor, or a shout with Heroic Strike queued) or Druid (Faerie Fire next to Maul) | open-world mob | press the instant just as a white hit or Maul lands, about ten times. `PAIR` records any cast and target row that come within 50 ms, and the snap Snapshot has the `tickets` line | nothing |
| U12 | auto | Warrior | open-world mob | fight mobs down to below 20% with white swings. `USABLE` records each Execute flip with the ms since the last swing (`swing+`) and since the last target row (`row+`) | nothing |
| U13 | situation | Druid (Nature's Reach) | open-world mob | cast Wrath at maximum range (36 yd), a series of casts on one mob | nothing |
| U14 | auto | any (melee and caster) | open-world mobs | ten solo kills. Compare the last target row or `PLATE-` against `PLAYER_REGEN_ENABLED` | nothing |
| U15 | situation | Warrior (dual wield, Fury) | open-world mob; then a party with a Hunter | dual-wield solo kills, then the same with a party Hunter's pet on your mob | nothing |
| U16 | situation | any; a party with a caster of your school | five-man dungeon | run the dungeon. The other caster's rows on your target, and the snap `tickets` line | nothing |
| U17 | situation | Warrior (Fury) | five-man dungeon | run the dungeon as Fury (snap `tickets`: lost, assumed, confirmed, refunded) | nothing |
| U18 | situation | any | five-man dungeon | the same run (snap `replaced` and `tentative`) | nothing |
| DM-P | situation | any melee | five-man dungeon or open-world party | turn Hekili's "damage meter" option on out of combat, then pull 100+ of your swings in a party | nothing |
| DM-M | manual | any | open-world mob | `/reload`, turn the "damage meter" option on out of combat, do one solo pull (the snap probe saves the Snapshot); turn the option off and do another pull | nothing (snap saves both `providers` lines) |
| DM-PET | situation | **Hunter or Warlock** (not Warrior or Druid) | open-world mob | solo pulls with your pet attacking | nothing |
| DM-FL | situation | Druid | open-world mob | Wrath at maximum range (the same fights as U13) | nothing |
| DM-I | situation | any | dungeon | any dungeon fight (`ADDON_RESTRICTION_STATE_CHANGED` and the meter events are recorded) | nothing |
| CDM-T | manual + auto | any (a DoT and a proc: Warrior Rend, Druid Moonfire) | open-world mob | `/console taintLog 1`; turn the Cooldown Manager on in the game options and Hekili's "Cooldown Manager" option on out of combat; do a pull; `/reload` | `Logs/taint.log` (the controller reads it from the client folder); snap saves the `presence` lines |
| CDM-E | auto | Warrior (Rend, Death Wish on an Essential item) | open-world mob | cast Rend or Death Wish and let it run out. `CDV_EDGE` records each item's `auraInstanceID` changes in combat | nothing |
| CDM-R | auto | Warrior | anywhere, out of combat | the uncapped `CDV_ID` list (every id and linked id, categories 0-8) is saved at the first world entry of each session. Manual: `/vslog cdv ids` then `/vslog dump` | nothing |
| CDM-O | situation | any (Warrior Rend, Druid Moonfire) | two open-world mobs | turn the Cooldown Manager option on; put your debuff on mob A only, then target B, then A. `CDV_TGT` records frames 0-3 after each target change | nothing |
| CDM-P | situation | any; a party with another Warrior (Battle Shout) or a Priest (Fortitude) | party | let the partner buff you, then cast your own copy and let theirs replace it. `CDV_SHOW`, `CDV_HIDE` and `CDV_EDGE` | nothing |
| CDM-I | situation | any | dungeon, including a boss | enter a dungeon and fight a boss. `CDV` status is saved at each world entry and `CDV_FRAME` 2 s into each fight | nothing |
| CDM-C | auto | every class: Warrior and Druid here; **other classes need their own characters** | anywhere, out of combat | log in once on each class. The `CDV_ID` list is saved each session | nothing |

## Gaps (what the kit cannot script)

- DM-B: it depends on GC-T's result, and no plan uses it yet.
- PH-MP: each mob's next swing. A WOUND row on the player does not name its source, so with two mobs on you their swings
  can only be told apart by the timing.
- CDM-T: turning on the taint log and the game options are your steps (no addon may change them). The taint log is the
  game's file.
- DM-M: Hekili's option toggle is yours to set. The probe only saves the Snapshot after each fight.
- The GC-T auto run adds the bank's per-frame work (8 curves, 32 pcalls, a getter sweep every 5 frames) to the session's
  first two fights, so leave those two fights out of the swing timing analysis.
