# Log 3, group (2026-10-16): the user (Undead Warrior 22, main 2.2 / off 2.5) with one party member (a Druid: Nature
# school-8 casts with a cast bar, bear-form Maul = WOUND 0 + damage frames, white glancing 1-5). Recorded by /vslog.
# Segment A (0-12272): solo. Segment B (160779-171699): both attacking the mob (target/nameplate2/softenemy).
# Segment C (174816-205518): only the party member attacking; the user idle. Then the user rejoins (205767-).
# Full dump kept in the job transcript; key rows:
162196 UNIT_COMBAT target WOUND 37 8        <- party member's Nature spell on OUR target: plain amount, school 8
163596 UNIT_COMBAT target WOUND 38 8
165116 PLAYER_SWING 2.2 0                   <- our main-hand swing
165123 UNIT_COMBAT target WOUND GLANCING 4  <- his white glancing (7 ms after our swing event: not ours)
165169 UNIT_COMBAT target MISS 0            <- his miss (53 ms after our swing: not ours, our lag is ~470 ms)
165485 UNIT_COMBAT target WOUND 50          <- our main-hand hit (369 ms after the swing)
177249 UNIT_COMBAT nameplate2 WOUND 0 / 177250 WOUND 36   <- his Maul frame (WOUND 0 + damage), no cast of ours
182099 UNIT_COMBAT nameplate2 DODGE 0       <- the mob dodging HIM (segment C, we are idle)
196683 UNIT_COMBAT nameplate2 PARRY 0       <- the mob parrying him
49873 UNIT_SPELLCA party1 S S CastBar-...   <- his cast successes: castGUID and spellID SECRET
57177 UNIT_COMBAT party1 WOUND 20           <- hits on him: plain; party1 HEAL 15-19 regen ticks plain

## Facts (measured)
1. UNIT_COMBAT on an addressable unit reports EVERY outcome on it, whoever dealt it: another player's spell hits, white
   hits, glancing blows, and the mob's dodges/parries/misses against him, all with plain amounts and school.
2. Another player's cast successes arrive with spellID and castGUID secret; damage and heals on him are plain.
3. Consequences for the pairing (Rows.lua as merged 2026-10-16):
   a. His avoids (MISS/DODGE/PARRY, amount 0) are indistinguishable from ours by amount; "avoid -> oldest pending
      swing" lets his avoid consume our pending swing, so our real hit then finds no swing and pays nothing.
   b. His physical hits inside our range (Maul 36-40 vs main 36-50) are credited to a pending swing of ours.
   c. The "3 consecutive no-fit wounds -> oldest-pending fallback" rule is triggered by his glancing 1-5 and then
      credits his hits to our swings.
4. Tells that separate his outcomes from ours: school (a white swing is school 1); the WOUND 0 + damage frame with no
   cast success of ours in that frame (someone else's on-next-swing strike); timing (our main-hand lag ~470 ms
   +-60, off ~700-1700: an outcome 7-53 ms after our swing event is not its outcome).
## Proposed group-fidelity fixes (after the Protection plan): physical-school filter for white pairing; drop the N=3
# fallback (keep the form check and the OOC cache refresh); per-hand expected-lag scoring for avoids AND wounds
# (learned median/spread; reject candidates outside the band); the WOUND-0 frame tell; measure UNIT_AURA cost in a
# party (checklist B15) in the same pass.

# G5 (2026-10-16): solo, dual wield (main 2.2 s, off 2.5 s), auto-attack only, ~88 s, several mobs. /vslog dump in log5.txt
# (rows reduced: S hand = PLAYER_SWING, W/C/B amount school = WOUND / CRITICAL / BLOCK_REDUCED on target, A = avoid).
Amount bands this session: main plain 40-56 (crits 99, 105), off plain 27-36 (crits 53-66).

## Off-hand landing: two sharp references (20 off-hand wounds)
| lag after its own off swing | lag after the previous main swing |
|---|---|
| 11 of 20 at 691-707 ms | 7 of 20 at 1686-1687 ms (one 1755) |
Rows where neither matched: 186 (landed WITH the main hit: swings 250 ms apart, both wounds in one frame at 50269),
836, 887, 986, 1154, 1319, 1453 (these are the 1686-main-reference rows seen from the off swing). Reading: the
off-hand hit lands at ~0.70 s after its swing event unless the main hand's timing pushes it to ~1.69 s after the
previous main swing event (or into the main hit's frame). Both references are sharp (tens of ms). Ruling D4: score
the off hand against BOTH references and take the better; the "wide off-hand band" was two narrow ones.
Main-hand lags: 436-556 in 17 of 22 (median 453); 157, 167, 371 short; 736, 805 long.

## Touch of the Grave proc, seen twice (37174, 68467)
`UNIT_COMBAT target WOUND 36 32` (school 32 = Shadow) and `UNIT_COMBAT player HEAL 36 1` in the SAME ms, 1-2 ms after
a PLAYER_SWING event (off at 37173; main at 68465), i.e. the proc fires on the swing event, not on the hit's landing.
No UNIT_SPELLCAST_SUCCEEDED for it: /vsgrave's cast-success channel will read 0; its heals channel is the count.
2 procs in ~88 s of combat here (cap 2.4/min). School 32 keeps it out of the white pairing.

## G5 reduced rows (t, S hand | W/C/B amount school | A)
```
0 S 1
328 S 0
699 W 28 1
699 W 56 1
2528 S 0
2529 S 1
2981 W 46 1
4215 A
4728 S 0
5095 S 1
5164 A
6414 W 32 1
6895 S 0
7331 W 44 1
7595 S 1
8581 W 29 1
8911 S 0
9432 W 50 1
10095 S 1
10798 A
11178 S 0
11631 W 56 1
12512 S 1
13215 W 35 1
13378 S 0
13934 W 47 1
15011 S 1
15595 S 0
15705 W 33 1
15752 W 48 1
24323 S 0
24656 S 1
24859 A
26009 A
26623 S 0
27059 A
27156 S 1
28310 W 33 1
28756 S 0
29293 A
29656 S 1
30442 C 66 1
31040 S 0
31476 W 51 1
32173 S 1
32876 A
33206 S 0
33644 W 45 1
34673 S 1
35376 W 30 1
35456 S 0
36192 W 45 1
37173 S 1
37174 W 36 32
37661 S 0
37864 W 34 1
38664 A
39694 S 1
39861 S 0
40028 C 105 1
40398 W 33 1
49833 S 0
50083 S 1
50269 B 45 1
50269 W 30 1
52028 S 0
52465 W 51 1
52595 S 1
53681 A
54228 S 0
54681 W 47 1
55078 S 1
55914 W 30 1
56445 S 0
56981 W 41 1
57495 S 1
58200 W 27 1
58595 S 0
59066 C 99 1
60595 S 1
60761 S 0
61298 W 29 1
61298 A
63061 S 0
63584 W 40 1
68465 S 0
68467 W 36 32
68698 S 1
68901 W 40 1
70151 W 30 1
70715 S 0
71169 W 45 1
71281 S 1
72402 A
72914 S 0
73435 A
73714 S 1
74601 C 53 1
75114 S 0
75568 W 45 1
76298 S 1
77001 W 27 1
77314 S 0
77768 W 51 1
78798 S 1
79501 W 32 1
79514 S 0
80319 W 45 1
81214 S 1
81921 W 32 1
87348 S 1
88039 C 58 1
```

# G6 (2026-10-16): the user cast Battle Shout BETWEEN two fights (not in combat): tests the OOC cache refresh, not the stale path.
Before (G5): main plain 40-56, off 27-36. After: main 48-60 (crits 69, 72, 99, 104), off 30-38. Lags unchanged: main
437-536 ms; off 707 ms after own swing or 1687 ms after the previous main swing. Touch of the Grave: 40 shadow + 40 heal,
2 ms after a main PLAYER_SWING (171089 -> 171091; 203004 -> 203105 is 101 ms: one outlier), up from 36 before the buff.
Unexplained: `WOUND 13 8` (Nature) on the target every ~1.3-2 s from the first second, no cast of ours; three in one
frame at 193596. School != 1 so not a pairing candidate. Asked the user what it is.
Still open: a buff cast IN combat (the stale-cache path).
Raw dump: in the job transcript (vslog n=451, second fight rows 171089-229713).

## Token semantics (confirmed with the user 2026-10-16)
One event fires once per unit token resolving to the same unit (target/nameplateN/softinteract; player/targettarget): dedupe by reading one token. `player PARRY/DODGE/BLOCK/WOUND` = an attack ON the player (victim-side), not our attack; the same event drives Revenge and damage-taken rage.
