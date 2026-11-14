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

From Beast Mastery (wowsims.com):

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
actions+=/open_window,name=<window>[,refresh=1][,duration=<seconds>][,if=<condition>]
actions+=/close_window,name=<window>[,if=<condition>]
```

- The lines run in list order, like `variable` lines, and show no icon.
- `open_window` opens the window at the point of the forecast where its condition first holds, and opens it only once per walk while the condition keeps holding. If the condition does not hold yet, the line is rechecked like any other, so it can open the window later in the forecast.
- `duration=` replaces the registered length for this opening.
- `refresh=1` lets the line restart a window that is already open, within the caps the class pack sets. Without it, a line does not restart an open window unless the class pack's registration allows it.
- `close_window` closes the window when its condition holds and the window is open.
- The importer switches a line off, with an "Unknown window" warning in the **Import Log**, when the class registers no window of that name. The editor's **Window Name** field offers only registered names.

As of the current release, no built-in priority opens or closes a window with a line: the built-in priorities only read windows that the class packs open.

## Windows the class packs register

| Window | Class | Covers | Read by |
|---|---|---|---|
| `hha` | Hunter | Beast Mastery's sequence of Summon Hawk, Summon Hawk, Arcane Shot, repeated for the whole fight | Beast Mastery (wowsims.com) |
| `weave` | Hunter | The moment after a ranged shot in which a melee strike fits before the next shot | No built-in priority |
| `move1`, `move2` | Paladin | Retribution's opener: Judgement, then a seal, from the pull until the first melee swing | Retribution (wowsims.com) |
| `riposte` | Rogue | The 5 seconds after a parry in which Riposte can be used | The class pack, to decide when Riposte is usable |

## See also

- [Pack windows and reactions](Pack-Windows-And-Reactions)
- [APL expression reference](APL-Expression-Reference)
- [APL syntax reference](APL-Syntax-Reference#special-actions)
