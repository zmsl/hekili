<!--
Purpose: An annotated snapshot: the walk, why each entry was or was not picked, warnings.
Type: Explanation
Audience: players with a problem
Prerequisites: [Reporting a problem](Reporting-A-Problem).
-->
A **snapshot** is a text record of how Hekili Forever chose one set of recommendations: the character and settings it worked with, what it knew about the fight, and each priority line it tested, in order, with the reason it was or was not picked. Snapshots are taken with the **Snapshot** or **Pause** key or `/hekili snapshot`, and read on **/hekili > Snapshots (Troubleshooting)** ([Reporting a problem](Reporting-A-Problem)). This page explains how to read one.

One snapshot holds one record per display that was showing recommendations. Each record is long: a few hundred lines for a short priority.

## What a snapshot records

A record has two parts.

- **The header sections**, at the top: the version, the character, the talents, the gear, every specialization setting and toggle, the warnings, the enemies counted and the auras.
- **The walk**, below them: for each icon of the display, the priority lines that Hekili Forever tested to choose it.

The first line names the priority and the display, then each recommendation with the time it is due, in seconds from now. An excerpt from a test character, a level 60 Arms Warrior out of combat (`tests/Forever/debug_english_spec.lua` builds the same setup), shortened with `...`:

```text
[23:55:34] Arms (wowsims.com); Primary - bloodrage(0.00), battle_shout(0.00), charge(0.00), sunder_armor(1.50)
...
level: 60 (60)
class: WARRIOR
spec: arms (dominant)
...
Toggles:
    cooldowns = true
    custom1 = false
    ...
    mode = automatic
...
### Warnings ###

none

### Targets ###

detected_targets:  Nameplates are disabled.
    target       -  0 - Creature-1

### Auras ###

player_buffs:
     n  | ID      | Token          | A. Count | A. Remains | S. Count | S. Remains
    --- | ------- | -------------- | -------- | ---------- | -------- | ----------
     1  |    2457 |  battle_stance |        1 |    3600.00 |       -1 |      -1.00
```

- `spec` names the active specialization and how it was chosen: "dominant" for the tree with the most points, "stored" for your own choice, "selector" for a pick from your talents.
- `Toggles` shows each toggle's state at that moment. A toggle shown as false explains why the abilities tied to it were skipped.
- `Warnings` lists problems Hekili Forever noticed while running, and problems found in the priority when it was loaded, such as a line that tests target health, which the game hides.
- `Targets` shows how many enemies were counted and from where. Here nameplate counting was off, so only the current target counted.
- `Auras` lists each buff and debuff by its name in the priority. A remaining time of 3600 means no end time is known. <!-- UNVERIFIED: the A. columns are read from the game's aura list and the S. columns from Hekili Forever's own records (Engine/Snapshot.lua); not checked in game. -->

## The walk

After the header sections, a line such as `New Recommendations for [ Primary ] requested at ...` starts the walk. Then each icon has its own block, `RECOMMENDATION #1`, `RECOMMENDATION #2` and so on. A block lists the resources at that moment, then each priority line tested, numbered, with the list and line it came from:

```text
RECOMMENDATION #1 ( Offset: 0.00, GCD: 0.00, Casting: 0.00 ).

    Resources: rage[ 0.00 / 100.00 ]
    ...
    Processing precombat action list [ Arms (wowsims.com) - precombat ].
        1.   berserker_rage ( precombat - 1 )
        The action (berserker_rage) is unusable at (0.00 + 0.00) because required form (berserker_stance) not active.
        ...
        3.   battle_stance ( pre_pull_stance - 1 )
        The action is not ready ( 3600.00 ) before our maximum delay window ( 15.00 ) for this query.
        ...
        4.   bloodrage ( precombat - 3 )
        The action (bloodrage) is usable at (0.00 + 0.00).
         - the action is ready before the current recommendation (at +0.00 vs. +15.00).
         - this entry has no criteria to test.
        Action chosen:  bloodrage at 0.00!
```

Each entry ends in one of a few ways:

- `unusable`: the ability cannot be used at all at that moment, and the reason is given, here a missing stance.
- `not ready`: the ability will not be ready within the time this icon looks ahead. 3600 means it is not ready at any known time; here Battle Stance is already active.
- `usable`, then the line's conditions are tested.
- `Action chosen`: the first ability whose conditions pass becomes the recommendation for that icon.

The conditions are printed with each value as it was at that moment, in square brackets. From the fourth icon's block of the same snapshot:

```text
        24.  heroic_strike ( default - 25 )
        The action (heroic_strike) is usable at (0.00 + 0.00) with cost of 15 rage (have 15).
         - the action is ready before the current recommendation (at +0.00 vs. +1.50).
         - this entry's criteria FAILS: (!execute_phase[false]&rage.lo[15.00]>=90&!talent.improved_slam.enabled[false])
```

Here `rage.lo[15.00]>=90` reads: the low end of the rage estimate was 15, so the test "at least 90 rage" failed, and Heroic Strike was not chosen. A line whose conditions hold says `criteria PASSES` instead. When a recommendation looks wrong, find the line you expected to be chosen, and read which value in its conditions failed.

## Lines for the developers

Some lines in a record are written for the developers rather than for players. The `[vs]` lines, and the block of `read ...` lines just below the `New Recommendations` line, record each value Hekili Forever asked the game for, and whether the game answered it or Hekili Forever estimated it. Lines that begin with `TimeData` record how long each step took, and a `Performance` table at the end records the update rate. Keep all of them when sending a snapshot.

<!-- TODO-SCREENSHOT: a short snapshot with each section numbered -->

## See also

- [APL debugging](APL-Debugging): using snapshots to fix a custom priority
- [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)
