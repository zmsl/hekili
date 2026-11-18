<!--
Purpose: Rotation windows as they work in the released version.
Type: Reference
Audience: theorycrafters
Prerequisites: [APL overview](APL-Overview).
-->
A **rotation window** is a named span of time during a fight that a class pack registers, for a part of the rotation that the game shows no aura for, such as the few seconds in which a parry allows Riposte. A priority line reads a window with `window.<name>` expressions, and can open or close one for the rest of a walk with `open_window` and `close_window` lines. This page lists the window expressions and lines as they work in the current release. How a class pack registers a window is in [Pack windows and reactions](Pack-Windows-And-Reactions).

## What a window is

A window is registered by a class pack with `RegisterWindow`, under a name such as `hha` or `riposte`. It is either open or closed. While open it has an opening time, an end time and, for a stepped window, a current step.

- Hekili Forever opens and closes the real windows from what the game reports: each window can have a test, run on every update, and the window opens when the test becomes true. A cast the player makes can also open or close it, and combat end closes every window.
- A window lasts a fixed number of seconds, until the end of combat, or as long as a length the class pack works out at each opening. A window can also close when its test becomes false again.
- A stepped window holds a sequence of abilities. Each cast of the step that is due moves it to the next step. At the end it closes, or starts again for a window that loops.

On every update the forecast copies the windows as they stand. Lines and simulated casts change only that copy, for the rest of the walk; nothing a walk does to a window reaches the next update ([APL overview](APL-Overview#each-evaluation-stands-alone)).

## Reading a window

| Expression | Type | Meaning | Example |
|---|---|---|---|
| `window.<name>.up` | boolean | The window is open at this point of the forecast | `window.move1.up` |
| `window.<name>.down` | boolean | The window is closed | `window.hha.down` |
| `window.<name>.remains` | seconds | Time until the window ends; 0 when closed | `window.hha.remains>0` |
| `window.<name>.elapsed` | seconds | Time since the window opened; 0 when closed | `window.weave.elapsed>1` |
| `window.<name>.step` | number | The step that is due, from 1; 0 when closed or not stepped | `window.hha.step=3` |
| `window.<name>.next.<key>` | boolean | The window is open and its due step is the ability `<key>` | `window.hha.next.summon_hawk` |

From Beast Mastery Turret (wowsims.com):

```simc
actions+=/summon_hawk,if=window.hha.next.summon_hawk
```

From Retribution (wowsims.com):

```simc
actions.move_to_melee=judgement,use_off_gcd=1,if=window.move1.next.judgement&(toggle.movement&window.move1.up|action.judgement.in_range)
```

A window that never stops on a timer, one that lasts until combat ends, reads a very large `remains`.

### Edge cases

- `window.<name>` with a name the class does not register is an error: the line's condition fails to run and the walk never chooses the line. Use only the names in [Windows the class packs register](#windows-the-class-packs-register).
- A line that reads a window is rechecked at the window's opening and end times, so the forecast can show the ability at the moment the window opens.

## Opening and closing

```simc
actions+=/open_window,name=<window>[,if=<condition>]
actions+=/close_window,name=<window>[,if=<condition>]
```

- The lines are commands, run in list order like `variable` lines, with no icon. They carry only `name=` and `if=`; the window's length and refresh settings live where the window is declared. Any other option on the line is error E4 (see [Errors](#errors)).
- A true `open_window` opens a closed window. On an open window it does nothing, unless the window is declared with `refresh=1`: then it restarts the window's timer, within `max_refresh` and `max_duration`. A true `close_window` closes an open window.
- There are no edges: a condition that stays true keeps the window open, and opens it again after it runs out.
- When a line changes the window, the walk starts again from the top at the same moment, so the lines above it see the change. Each line acts at most once per recommendation slot, so the walk restarts at most once per window line. The debug snapshot lists the restarts of each slot. Its Windows section, per display, says whether Sequences is on there, shows each window as the walk started (up or closed, the step, an open sequence's options and, with `mode=wait`, the member it waits on) with its operations and opens in the last 10 seconds, and names every operation sent with the line that sent it.
- A window that lines open and close in the same recommendation slot (an `open_window` and a `close_window` line both true, or a `close_window` line against a sequence that starts again in that slot) restarts the walk for both in every recommendation. The **Warnings** page says so once per window. The fix is the opposite condition on the open line, or on the sequence line.
- If the condition does not hold yet, an `open_window` line is rechecked like any other, so it can open the window later in the forecast.
- For a window declared in the priority, the changes made by the first recommendation at the current moment are kept for the next update; everything else, and every change to a class pack's window, lasts only for the rest of the walk. Each display keeps its own copy of a window declared in the priority.
- An `open_window` or `close_window` line that names a window neither the priority nor the class declares is error E1 (see [Errors](#errors)).

As of the current release, no built-in priority opens or closes a window with a line: the built-in priorities only read windows that the class packs open.

## Declaring a window in the priority

A priority can declare its own windows in a list named `windows`. The name is reserved: the list holds only `window` entries, is never walked and cannot be called.

```simc
actions.windows+=/window,name=burst,duration=12
actions.windows+=/window,name=pool,duration=6,refresh=1,max_refresh=2,max_duration=15
```

| Option | Values | Meaning |
|---|---|---|
| `name` | a name | Required. One name per window in the priority, and not a name a class pack registers |
| `duration` | seconds or `combat` | Required. The window's length from each opening; `combat` lasts until combat ends |
| `refresh` | 0 or 1 | 1: a true `open_window` on the open window restarts its timer |
| `max_refresh` | a count | The most restarts per opening |
| `max_duration` | seconds | The longest the window stays open from its first opening |
| `reset_on_target_change` | 0 or 1 | 1: a target change closes the window |

## Sequences

A `sequence` or `strict_sequence` line declares a window named by its `name=` and holds its members as steps, in
SimC's syntax: options in the first colon-separated part, then one member per part, each with its own options. An
ability may appear more than once in a sequence, each time with its own `if=`, which is read only while that position
is due.

```
actions+=/restart_sequence,name=opener,if=window.opener.done
actions+=/sequence,name=opener,mode=continue:summon_hawk:arcane_shot,if=target.outside8
actions+=/strict_sequence,name=burst,start_on_first=1,hold_off_gcd=1:bloodrage,use_off_gcd=1:mortal_strike
```

- A plain `sequence` opens when its line is reached and its `if=` is true, shows its due member, and parks after the
  last one (`window.<name>.done` is true while parked) until `restart_sequence` or combat end. `mode=skip` (the
  default, SimC) drops a member that cannot be cast; `mode=wait` (or `wait_on_ready=1`) shows the due member and
  nothing below the line, in its list or below the lines that called it;
  `mode=continue` stays on the member and lets the list carry on.
- A `strict_sequence` opens when its line is the pick at now. By default every member must be castable then;
  `start_on_first=1` tests only the first member, within the spell queue window; `allow_skip=1` starts on the first
  member that can be cast and skips members that cannot. While it is open the display shows its members; outside lines
  marked `use_off_gcd=1` for an off-GCD ability still show unless the line says `hold_off_gcd=1`, and such a line that
  is ready shows ahead of the due member (for a later member of the sequence, pressing it ends the sequence). A member
  that cannot be cast when the GCD is ready ends it and the normal lines answer at once; so do another on-GCD cast, a
  later member cast out of order, `step_timeout=` (4 s by default) and a `close_window,name=<sequence>` line whose
  `if=` is true (read while the sequence is open, with either hold). While it is open, `open_window`,
  `close_window` and `variable` lines are still read; sequence lines (`sequence`, `strict_sequence`,
  `restart_sequence`) do nothing. With `hold_off_gcd=1` in a priority with no `open_window`, `close_window` or
  `variable` line, the normal lines are not read at all while it is open.
- An unnamed plain sequence is `default` (further ones `default_2`, ...); an unnamed strict one `strict_1`, ...
- Sequences run in Primary and AOE only. Each has a Sequences setting, on by default; where it is off, the display
  skips every sequence line as if it were not in the priority. Cooldowns, Interrupts and Defensives never run
  sequences. Free-form windows work in every display.

## Errors

| Code | Where | What |
|---|---|---|
| E1 | a line | `open_window` or `close_window` names a window neither the priority nor the class declares |
| E2 | the list | a name declared twice |
| E3 | the list | a name a class pack registers |
| E4 | a line | an option other than `name=` and `if=` on `open_window` or `close_window` |
| E5 | anywhere | a `window` entry outside the list, any other entry in it, a call of it, or an `if=` on an entry |
| E6 | the list | a missing name, a missing or non-positive `duration`, or a bad cap |
| E7 | the list | any other option on a `window` entry |

When the priority loads, each error is reported once as an error message and its entry is marked with it: the walk skips a marked line, and an entry of the `windows` list with an error declares nothing. The entry itself stays as written and switched on. An import switches each entry with an error off and lists the error in the **Import Log**.

## Windows the class packs register

| Window | Class | Covers | Read by |
|---|---|---|---|
| `hha` | Hunter | Beast Mastery's sequence of Summon Hawk, Summon Hawk, Arcane Shot, repeated for the whole fight | Beast Mastery Turret (wowsims.com) |
| `weave` | Hunter | The moment after a ranged shot in which a melee strike fits before the next shot | No built-in priority |
| `move1`, `move2` | Paladin | Retribution's opener: Judgement, then a seal, from the pull until the first melee swing | Retribution (wowsims.com) |
| `riposte` | Rogue | The 5 seconds after a parry in which Riposte can be used | The class pack, to decide when Riposte is usable |

## See also

- [Pack windows and reactions](Pack-Windows-And-Reactions)
- [APL expression reference](APL-Expression-Reference)
- [APL syntax reference](APL-Syntax-Reference#special-actions)
