# Swing/outcome pairing, measured in game

Log 2 (2026-10-16, Undead Warrior 22, auto-attack only, six mobs, 368 events). The log at the end holds the
deduplicated target rows: nameplate1/targettarget/softinteract duplicates removed, hits on the player removed.

Method: a wound is assigned a hand by amount (main 36-50, off 24-32; CRITICAL halved), then paired with the most recent
unpaired PLAYER_SWING of that hand; an avoid (MISS/DODGE/PARRY, amount 0) with the most recent unpaired swing of either
hand; swings expire unpaired after 3 s.

| hand | hits | lag after PLAYER_SWING (ms) |
|---|---|---|
| main (swingType 0, 2.2 s) | 34 | 435-552 in 31 (median 474); 134, 869, 1237, 1287 |
| off (swingType 1, 2.5 s) | 31 | 694-1070 in 22 (median 953); up to 1686 |

Avoids: 16, lag 0-1887 ms; three at 0-1 ms (same frame as the swing event). Orphan wounds (no unpaired swing): 4 of 69,
each after an avoid had consumed that hand's swing (the avoid probably belonged to the other hand). Swings never
paired: 2 of 71.

Facts for the design:
1. The outcome always FOLLOWS its swing event. Lag ~0.45 s main, ~0.7-1.7 s off. The 0.2 s PAIR_WINDOW pairs almost
   nothing; every swing is emitted as SWING_DAMAGE 0 and the real wound dropped.
2. Hands are independent and stagger; the off-hand lag varies within a fight.
3. Amount identifies the hand (ranges from UnitDamage's per-hand min/max, cached out of combat; crit x2; glancing
   lower; BLOCK_REDUCED lower). Rend ticks (13) and procs fall outside both ranges.
4. Avoids carry no amount: ambiguous between hands when both are pending.
5. The belief (Sources/Swing.lua) stages a landed swing on EVERY PLAYER_SWING: misses and avoids pay rage; the
   learned scale 0.92 is the avoid rate.
6. Parry haste: a parry on us pulls the next main-hand swing forward (log 1: 771 -> 2110, 1.34 s on a 2.2 s weapon).

## Log 2 (deduplicated target rows; ms since the first event; event, args)

```
     0 UNIT_SPELLCA player Cast-3-4615-1-2-100-9787CB10B8 100 nil nil
   998 PLAYER_SWING 2.2000000476837 0 nil nil nil
  1296 PLAYER_SWING 2.5 1 nil nil nil
  1472 UNIT_COMBAT target WOUND  40 1
  2695 UNIT_COMBAT target WOUND  31 1
  3158 PLAYER_SWING 2.2000000476837 0 nil nil nil
  3612 UNIT_COMBAT target WOUND  41 1
  3775 PLAYER_SWING 2.5 1 nil nil nil
  4844 UNIT_COMBAT target WOUND  30 1
  5404 PLAYER_SWING 2.2000000476837 0 nil nil nil
  5841 UNIT_COMBAT target WOUND  43 1
  6289 PLAYER_SWING 2.5 1 nil nil nil
  7091 UNIT_COMBAT target WOUND  31 1
  7556 PLAYER_SWING 2.2000000476837 0 nil nil nil
  7992 UNIT_COMBAT target WOUND  49 1
  8788 PLAYER_SWING 2.5 1 nil nil nil
  9491 UNIT_COMBAT target DODGE  0 1
  9788 PLAYER_SWING 2.2000000476837 0 nil nil nil
 10308 UNIT_COMBAT target WOUND  49 1
 11221 PLAYER_SWING 2.5 1 nil nil nil
 11924 UNIT_COMBAT target WOUND  28 1
 11988 PLAYER_SWING 2.2000000476837 0 nil nil nil
 12122 UNIT_COMBAT target WOUND CRITICAL 91 1
 17786 UNIT_SPELLCA player Cast-3-4615-1-2-100-F0433CDF77 100 nil nil
 18518 PLAYER_SWING 2.5 1 nil nil nil
 18785 PLAYER_SWING 2.2000000476837 0 nil nil nil
 19221 UNIT_COMBAT target WOUND  30 1
 19221 UNIT_COMBAT target MISS  0 1
 21085 PLAYER_SWING 2.2000000476837 0 nil nil nil
 21085 PLAYER_SWING 2.5 1 nil nil nil
 21521 UNIT_COMBAT target WOUND  45 1
 22771 UNIT_COMBAT target WOUND  25 1
 23251 PLAYER_SWING 2.2000000476837 0 nil nil nil
 23635 PLAYER_SWING 2.5 1 nil nil nil
 23788 UNIT_COMBAT target WOUND BLOCK_REDUCED 48 1
 24938 UNIT_COMBAT target WOUND  26 1
 25401 PLAYER_SWING 2.2000000476837 0 nil nil nil
 25938 UNIT_COMBAT target WOUND  42 1
 26118 PLAYER_SWING 2.5 1 nil nil nil
 27088 UNIT_COMBAT target WOUND CRITICAL 56 1
 27685 PLAYER_SWING 2.2000000476837 0 nil nil nil
 28138 UNIT_COMBAT target WOUND  39 1
 28635 PLAYER_SWING 2.5 1 nil nil nil
 29371 UNIT_COMBAT target WOUND  25 1
 29835 PLAYER_SWING 2.2000000476837 0 nil nil nil
 30271 UNIT_COMBAT target WOUND  48 1
 31051 PLAYER_SWING 2.5 1 nil nil nil
 31755 UNIT_COMBAT target WOUND  31 1
 32069 PLAYER_SWING 2.2000000476837 0 nil nil nil
 32505 UNIT_COMBAT target WOUND  43 1
 33651 PLAYER_SWING 2.5 1 nil nil nil
 38086 UNIT_SPELLCA player Cast-3-4615-1-2-100-894D9E50C6 100 nil nil
 38935 PLAYER_SWING 2.5 1 nil nil nil
 39086 PLAYER_SWING 2.2000000476837 0 nil nil nil
 39638 UNIT_COMBAT target WOUND  29 1
 39638 UNIT_COMBAT target WOUND  49 1
 41368 PLAYER_SWING 2.2000000476837 0 nil nil nil
 41369 PLAYER_SWING 2.5 1 nil nil nil
 41905 UNIT_COMBAT target WOUND  48 1
 43055 UNIT_COMBAT target WOUND  28 1
 43585 PLAYER_SWING 2.2000000476837 0 nil nil nil
 43935 PLAYER_SWING 2.5 1 nil nil nil
 44122 UNIT_COMBAT target WOUND  50 1
 45272 UNIT_COMBAT target WOUND  30 1
 45785 PLAYER_SWING 2.2000000476837 0 nil nil nil
 46323 UNIT_COMBAT target WOUND  45 1
 46452 PLAYER_SWING 2.5 1 nil nil nil
 47472 UNIT_COMBAT target WOUND  27 1
 48002 PLAYER_SWING 2.2000000476837 0 nil nil nil
 48522 UNIT_COMBAT target WOUND CRITICAL 97 1
 48885 PLAYER_SWING 2.5 1 nil nil nil
 49689 UNIT_COMBAT target WOUND  30 1
 50202 PLAYER_SWING 2.2000000476837 0 nil nil nil
 50638 UNIT_COMBAT target WOUND  45 1
 51452 PLAYER_SWING 2.5 1 nil nil nil
 52146 UNIT_COMBAT softinteract WOUND CRITICAL 48 1
 58607 UNIT_SPELLCA player Cast-3-4615-1-2-100-53CAABE763 100 nil nil
 59592 PLAYER_SWING 2.5 1 nil nil nil
 59891 PLAYER_SWING 2.2000000476837 0 nil nil nil
 59891 UNIT_COMBAT target MISS  0 1
 60294 UNIT_COMBAT target WOUND  28 1
 61095 UNIT_COMBAT target WOUND  48 1
 62091 PLAYER_SWING 2.2000000476837 0 nil nil nil
 62091 PLAYER_SWING 2.5 1 nil nil nil
 62628 UNIT_COMBAT target WOUND  49 1
 63777 UNIT_COMBAT target WOUND  26 1
 64291 PLAYER_SWING 2.2000000476837 0 nil nil nil
 64641 PLAYER_SWING 2.5 1 nil nil nil
 64728 UNIT_COMBAT target WOUND CRITICAL 100 1
 65978 UNIT_COMBAT target WOUND  28 1
 66508 PLAYER_SWING 2.2000000476837 0 nil nil nil
 66944 UNIT_COMBAT target WOUND  38 1
 67141 PLAYER_SWING 2.5 1 nil nil nil
 68194 UNIT_COMBAT target WOUND  26 1
 68708 PLAYER_SWING 2.2000000476837 0 nil nil nil
 69178 UNIT_COMBAT target WOUND  50 1
 69641 PLAYER_SWING 2.5 1 nil nil nil
 70395 UNIT_COMBAT target WOUND  31 1
 70909 PLAYER_SWING 2.2000000476837 0 nil nil nil
 71433 UNIT_COMBAT softinteract WOUND  41 1
 74361 UNIT_SPELLCA player Cast-3-4615-1-2-100-232C607212 100 nil nil
 75361 PLAYER_SWING 2.2000000476837 0 nil nil nil
 75611 PLAYER_SWING 2.5 1 nil nil nil
 75897 UNIT_COMBAT target WOUND  42 1
 76694 PLAYER_SWING 2.2000000476837 0 nil nil nil
 77048 UNIT_COMBAT target WOUND  29 1
 77781 UNIT_COMBAT target MISS  0 1
 78061 PLAYER_SWING 2.5 1 nil nil nil
 78862 PLAYER_SWING 2.2000000476837 0 nil nil nil
 79014 UNIT_COMBAT target WOUND  27 1
 79731 UNIT_COMBAT target WOUND CRITICAL 89 1
 80628 PLAYER_SWING 2.5 1 nil nil nil
 81111 PLAYER_SWING 2.2000000476837 0 nil nil nil
 81331 UNIT_COMBAT target WOUND  30 1
 82048 UNIT_COMBAT target MISS  0 1
 83128 PLAYER_SWING 2.5 1 nil nil nil
 83311 PLAYER_SWING 2.2000000476837 0 nil nil nil
 83831 UNIT_COMBAT target WOUND  27 1
 84548 UNIT_COMBAT target WOUND  49 1
 85511 PLAYER_SWING 2.2000000476837 0 nil nil nil
 85611 PLAYER_SWING 2.5 1 nil nil nil
 85611 UNIT_COMBAT target MISS  0 1
 85948 UNIT_COMBAT target PARRY  0 1
 87198 UNIT_COMBAT target WOUND  27 1
 87728 PLAYER_SWING 2.2000000476837 0 nil nil nil
 88128 PLAYER_SWING 2.5 1 nil nil nil
 88247 UNIT_COMBAT target PARRY  0 1
 89415 UNIT_COMBAT target WOUND  31 1
 89928 PLAYER_SWING 2.2000000476837 0 nil nil nil
 90381 UNIT_COMBAT target WOUND  45 1
 90611 PLAYER_SWING 2.5 1 nil nil nil
 91614 UNIT_COMBAT target WOUND  28 1
 92128 PLAYER_SWING 2.2000000476837 0 nil nil nil
 92582 UNIT_COMBAT softinteract WOUND  47 1
 95362 UNIT_SPELLCA player Cast-3-4615-1-2-100-2A3FB1736E 100 nil nil
 96178 PLAYER_SWING 2.2000000476837 0 nil nil nil
 96495 PLAYER_SWING 2.5 1 nil nil nil
 96715 UNIT_COMBAT target WOUND  41 1
 97864 UNIT_COMBAT target DODGE  0 1
 98462 PLAYER_SWING 2.2000000476837 0 nil nil nil
 98915 UNIT_COMBAT target WOUND  39 1
 98995 PLAYER_SWING 2.5 1 nil nil nil
 99778 PLAYER_SWING 2.2000000476837 0 nil nil nil
100148 UNIT_COMBAT target PARRY  0 1
100882 UNIT_COMBAT target MISS  0 1
101512 PLAYER_SWING 2.5 1 nil nil nil
101928 PLAYER_SWING 2.2000000476837 0 nil nil nil
102215 UNIT_COMBAT target DODGE  0 1
102934 UNIT_COMBAT target MISS  0 1
103962 PLAYER_SWING 2.5 1 nil nil nil
104128 PLAYER_SWING 2.2000000476837 0 nil nil nil
104665 UNIT_COMBAT target WOUND CRITICAL 55 1
105415 UNIT_COMBAT target WOUND  39 1
106379 PLAYER_SWING 2.2000000476837 0 nil nil nil
106512 PLAYER_SWING 2.5 1 nil nil nil
106833 UNIT_COMBAT target WOUND  47 1
108065 UNIT_COMBAT target MISS  0 1
108595 PLAYER_SWING 2.2000000476837 0 nil nil nil
109012 PLAYER_SWING 2.5 1 nil nil nil
109132 UNIT_COMBAT target WOUND  41 1
110282 UNIT_COMBAT target WOUND  31 1
110795 PLAYER_SWING 2.2000000476837 0 nil nil nil
110796 UNIT_COMBAT target MISS  0 1
111232 UNIT_COMBAT target WOUND  50 1
111512 PLAYER_SWING 2.5 1 nil nil nil
112482 UNIT_COMBAT target WOUND  30 1
113012 PLAYER_SWING 2.2000000476837 0 nil nil nil
113447 UNIT_COMBAT target WOUND  42 1
114012 PLAYER_SWING 2.5 1 nil nil nil
114714 UNIT_COMBAT target WOUND  29 1
116212 PLAYER_SWING 2.2000000476837 0 nil nil nil
116478 PLAYER_SWING 2.5 1 nil nil nil
116581 UNIT_COMBAT nameplate1 WOUND CRITICAL 52 1
116734 UNIT_COMBAT nameplate1 MISS  0 1
```

Fixtures: logs 1 and 2 are harness fixtures, every token row kept (`tests/Virtual/harness/fixtures/log1.lua`,
`log2.lua`); the pairing they measured is now a score (combat harness design, §1).
