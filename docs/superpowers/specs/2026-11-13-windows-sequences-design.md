# Windows and sequences: design v6, final (2026-11-13)

Self-contained. This is the build reference for the 0.9 lanes. It supersedes windows-design-v5-2026-11-13.md (v1
research and v2-v5 are kept as written). It implements every owner ruling in ~/src/hekili-deferrals.md L773-L839;
L821-L839 are the ones that changed v5, and L844-L845 settle the two items this document first raised in section
14.2. No design question is open. Section 14 lists the readings this document had to make and what the builders
must check in code.

Read-only research: nothing was run. Code claims are from reading worktree hekili-wt-integ-085 (97ea40b3b), paths
relative to it; SimC claims from /tmp/simc-seq-research/sequence.cpp and player.cpp; wowsims claims from the pin
e5a9cd2a2d, sim/core/apl_actions_sequences.go (written "seq.go" below). Confidence: [H] read in code, [M] inferred,
[L] judgement.

What changed from v5, in one paragraph. The plain-sequence option is `mode=skip|wait|continue` (`wait_on_ready=1`
is an alias for `mode=wait` and keeps SimC's exact meaning; the wowsims translator writes `mode=continue`). The
restart cap is gone: the fired mark bounds restarts, and it now resets per slot, so forecasts model windows
opening and closing. Window lines carry only `name=` and `if=` for every window, Lua-registered ones included. The
per-step deadline is 4 s with a `step_timeout=` option. A sequence's start line also bypasses the separate-toggle
filter in Primary and AOE. `reset_on_target_change` is built for Lua windows too. Hunter `hha` and Paladin
`move1` / `move2` move from Lua windows to APL sequences in Phase 3, as real-world tests beside Warrior Arms.

## v6.1 amendment (owner, L1165, 2026-11-16)

Owner: "The window is registered with the behavior in belief, so the core open signals should be enough." The
operations from the core to the belief carry only the author's intent: OPEN, CLOSE and STEP. There is no REFRESH
operation. The belief holds each APL window's declaration (`duration`, `refresh`, `max_refresh`, `max_duration`) and
applies the refresh rule itself when an OPEN lands on a window that is already open at the operation's stamp: if the
window is declared `refresh=1`, its refreshes are below `max_refresh` and its expiry is below openedAt +
`max_duration`, the timer restarts at the stamp for the declared duration (capped at openedAt + `max_duration`) and
refreshes go up by one; otherwise nothing changes. An OPEN on a closed or run-out window is a fresh open for the
declared duration; OPEN carries no argument. CLOSE and STEP stay writes. The core keeps the same rule only as a
forecast for its own pass: it decides whether the copy changed, so whether the walk restarts (ruling 19) and what
later lines and slots see. One pure statement of the rule serves both sides as the test oracle
(tests/Game/State/helpers/windows_matrix.lua `M.apply`): the belief's replay is asserted against it in Phase 1, the
core's forecast in Phase 2 (W05, W06, R09). Sections 0 (rulings 18, 19), 1 (rules 7, 8), 4.2, 4.3, 5.1, 5.4, 11, 12
and 13 below read with this amendment. Settled with it (L1180-L1182): an OPEN the rule refuses is traced and counted
as `refused`; the core sends nothing for a refusal its forecast makes; the refresh is refused once the expiry sits at
the `max_duration` cap (APL windows only; Lua windows keep their rule); every APL record carries a positive duration
or `combat` (a sequence's is `combat`); OP5 is the one named carve-out of forecast == apply (5.4); a strict sequence
record carries `on_deviation = "end"` (rule 17). Owner ruling L1226 (2026-11-16): a new APL window set is applied in combat only when the belief has no APL window yet; any change to existing windows waits for combat end (section 9, L01-first and L01 in section 13).

## 0. Decided

Each line is a ruling, with the owner's words where the ledger quotes them. Rows 1-17 stood in v5; rows 18-34 are
the answers to v5's questions 7-16 and derived rules D1-D8; rows 35-36 answer the two items v6 raised.

| # | Ruling | Owner's words | Ledger |
|---|---|---|---|
| 1 | A Lua window with steps must have an evaluator; no window opens on a cast of its first step | "Assuming that we want the window opened whenever the first item in the step sequence is a BIG misjudgement in most of the cases" | L773 |
| 2 | A press advances a sequence; it never opens a window | "The press isnt what opens a window though right? The press advances a sequence, but the window is open already from the condition" | L776 |
| 3 | All window state lives in the belief; displays push one way | "all window state should live in belief. The display simulation only pushes one way to open/close/etc. but the belief state is then pushed back to core" | L778 |
| 4 | A strict sequence opens when its line is the one chosen at now, in that display's pass | (ruling 1 of L779) | L779 |
| 5 | Be explicit in the priority; nothing is inferred from the abilities | "lean to be explicit in the apl rather than having inherent knowledge packaged in the items" | L781 |
| 6 | Strict sequences carry a name like plain ones | "give strict sequences names just to be consistent" | L782 |
| 7 | APL window lines are commands; no edge logic; no guardrails | "These are tools for APL pack authors and dont need guardrails against bad APL design." | L795 |
| 8 | Anonymous windows are declared once in the `windows` list | "Approved given the precombat precedent of having a specifically named actions list" | L796 |
| 9 | Q1, cross-display: the display that is in a sequence shows its members whatever its filter | "force the ability into the display that is in a sequence. Cooldowns/defensives/interrupts can continue to function as they are and the player can decide what to do" | L806 |
| 10 | A "Sequences" setting for Primary and AOE, on by default; Cooldowns, Interrupts and Defensives never sequence and have no such setting; sequences only | "Yes freeform windows will still work"; "Never: remove the option" | L808, L809, L1315 |
| 11 | Q2: a strict sequence may start on its first step due within the spell queue window. Since ruling 14 this is the `start_on_first=1` option, not the default | "we defaulted to wowsims for our sequence decisions already" | L810, L815 |
| 12 | Q4: a plain sequence's window opens on its condition. Strict keeps open-on-chosen | "when it is reached and evals to true and time=now" | L812 |
| 13 | Q5: imports add no options. The Actions tab shows effective values including defaults, and every window and sequence parameter is visible and editable there | (ruling, L813) | L813 |
| 14 | Reversal: SimC's sequence behaviour is the default; the wowsims translator writes the wowsims behaviour on every sequence it emits | "keeps Hekili consistent with how it was initially written" | L815 |
| 15 | Q6: a finished plain sequence parks until `restart_sequence` or combat end. SimC and wowsims agree | (settled, L818) | L814, L818 |
| 16 | Target changes do not reset windows or sequences by default; an option resets them. Supersedes L816 and L780 (2). Extended to Lua windows by row 33 | "because of potential sequences with target swap recommendations" | L817 |
| 17 | Naming: SimC's native option names where they exist; Hekili-only options named in SimC's style | "simc is the spec we're writing against. Anything that is unique to hekili will come up with a name schemed on simc semantics" | L818 |
| 18 | Q7 yes: operations are writes; the belief does not judge caps again on replay. Amended by v6.1 (L1165): CLOSE and STEP are writes; an OPEN on an open window is judged by the belief's declared refresh rule | (yes) | L821, L1165 |
| 19 | Q8 yes: a granted refresh restarts the walk like an open or a close; its cost is measured in Phase 2 | (yes) | L821 |
| 20 | Q9: the fired mark resets per slot. Each line acts at most once per slot; only slot 1 sends operations | "so that future predictions can model windows opening/closing correctly" | L822 |
| 21 | Q10, uniform rule: `open_window` / `close_window` lines carry only `name=` and `if=` for every window, Lua-registered or list-declared. Attributes live only in the declaration (`RegisterWindow` / `actions.windows`). An attribute on a line is a compile error. No shipped line changes (no shipped priority or recipe has such a line) | (ruling) | L824, L831 |
| 22 | Q11 yes: `windows` is a reserved list name; a release note says so | (yes) | L825 |
| 23 | Q12 yes: `open_window` / `close_window` may name a sequence | (yes) | L825 |
| 24 | Q13: no restart cap. The per-slot fired mark bounds restarts by the number of window lines; restarts per slot are shown in the snapshot and debug output; the CPU gate is in Phase 2. The per-step deadline is 4 s, with a SimC-style option `step_timeout=` | (ruling) | L826, L827 |
| 25 | Q14 yes: when a sequence is evaluated in Primary or AOE, its start line also bypasses the separate-toggle filter, overriding the ability's display category | (yes) | L827 |
| 26 | Q15: one plain-sequence option, `mode=skip\|wait\|continue`. skip (default) = SimC. wait = SimC's `wait_on_ready=1`, which is accepted as an alias. continue = stay on the step and let the list carry on = wowsims; the translator writes it | "unready ... horrible ... how about just mode?" | L829, L830 |
| 27 | Q16: the default strict start keeps SimC's rule, every step castable now, with no queue-window tolerance. `start_on_first=1` carries the queue window. Missed first presses are measured in Phase 3 | (per recommendation) | L832 |
| 28 | D1 + D2: the default `mode=skip` follows SimC exactly. An active plain sequence whose due step cannot be cast when its turn comes drops that step for this run; it burns out only if every remaining step is uncastable; `restart_sequence` or a new fight resets; an inactive line (`if=` false) skips nothing. "Ready" is judged at the moment the player can next act, the GCD end | (approved) | L834 |
| 29 | D3 yes: the default strict hold lets lines marked `use_off_gcd=1` through; `hold_off_gcd=1` holds them too | (yes) | L839 |
| 30 | D4 yes: no `loop` shorthand on sequence lines. A loop is `restart_sequence,name=x,if=window.x.done`; `window.<seq>.done` reads the parked state | (yes) | L839 |
| 31 | D5 yes: an unnamed plain sequence is `default`; further unnamed ones get generated names | (yes) | L839 |
| 32 | D6 replaced: Hunter `hha` and Paladin `move1` / `move2` move to APL sequences in Phase 3 as the real-world tests beside Warrior Arms, floors re-measured with the move. Hunter `weave` and Rogue `riposte` stay Lua-led (they track observed game events: Auto Shot and swing timing, a usability flip) | (owner, replaces D6) | L836 |
| 33 | D7: `reset_on_target_change` is built in 0.9 for Lua windows too (a `RegisterWindow` field), beside sequences and `actions.windows` declarations; default off everywhere | "yes build target change option with 0.9" | L837 |
| 34 | D8 yes: v4's option names `unready=`, `start=`, `off_gcd=`, `target_change=` are compile error E7 | (yes) | L838 |
| 35 | Sequences hold cast steps only. wowsims `move` and `wait` steps stay folded into the next cast's condition (translator rule 19) | "no move steps go into hekili" | L844 |
| 36 | Two optional ability fields, set by the pack in its ability registration, used only in a strict sequence's start test for members after the first: `sequence_ignore = { "form", ... }` (normal readiness with the named gates skipped) and `sequence_ready` (a handler that replaces readiness there, and may call the normal test). The first member and every step of a running sequence use normal readiness; with `start_on_first=1` the fields change nothing. The Arms migration uses the first: Overpower `{ "form" }`, Rend `{ "nobuff" }` | "useful for a replacement ready, or having sequence_ready add conditions by return ready() and xyz = true" | L845 |

Superseded and no longer in force: L780 (1) hold everything as the default (now `hold_off_gcd=1`); L780 (2) and
L816 (target change ends or resets by default); L781's wowsims defaults and value names; L810 as a default (now
`start_on_first=1`); L822's "+ the hard cap" (dropped by L827); v5's `wait_on_ready=1` with the wowsims meaning
(now `mode=continue`); v5's D6 (hha and the Paladin moves stay Lua) and D7 (no Lua field); L808's opt-in Sequences
setting for Cooldowns, Interrupts and Defensives (L1315: they never sequence).

### 0.1 What the two simulators do, as read in source

| Behaviour | SimC | wowsims |
|---|---|---|
| Plain: the due step is not ready | Skipped for good. The step counter moves past every unready step while the line is being tested (sequence.cpp:150-165). If no later step is ready the counter reaches the end and the sequence is finished [H] | Stays on the step. The line is not ready and the list carries on below (seq.go:63-68) [H] |
| Plain with `wait_on_ready=1` | Stays on the step, the line counts as ready, the actor waits and nothing below the line is walked (sequence.cpp:95-108, 157-164) [H] | no such option |
| Plain: finished | Never ready again (sequence.cpp:147) until `restart_sequence`, which sets the step to the first, once until a step has run (sequence.cpp:354-359; player.cpp:9637-9695) [H] | Same: not ready at the end (seq.go:65); reset is ready while the step is not the first (seq.go:121-126) [H] |
| Strict: start | Every step `ready()` at that moment (sequence.cpp:253-268). With `allow_skip=1`: at least one step ready (269-275) [H] | The GCD is within the spell queue window and the first step is ready (seq.go:178-191) [H] |
| Strict: what is held | The actor's foreground pick is the sequence instead of the priority list (player.cpp:7365-7369). The off-GCD and cast-while-casting lists (lines marked `use_off_gcd=1`, player.cpp:4339-4341, 14219-14226) are picked from without any test of the strict sequence, so they still run [H for the absence: `strict_sequence` is read only at player.cpp:6658, 7280-7284, 7365-7369] | The sequence takes the rotation (seq.go:192-195); nothing else runs. One exception: a major cooldown may go ahead of a step queued behind a hardcast (seq.go:274-287) [H] |
| Strict: the due step is not ready | The sequence is cancelled (sequence.cpp:295-306). With `allow_skip=1`: unready steps are skipped; past the last, it is over (313-351) [H] | With the GCD ready and the step not: the sequence gives the rotation back (seq.go:263-267) [H] |
| Target change | Nothing | Nothing |
| Names | `sequence`: `name=`, else `default`; `restart_sequence` without a name restarts `default` (sequence.cpp:55, 62-66; player.cpp:9645). `strict_sequence`: `name=` for logs (sequence.cpp:205) | plain sequences named, strict unnamed |
| Where options go | In the first colon-separated token, before the steps: `sequence,name=x,wait_on_ready=1:a:b` (sequence.cpp:61-73, 201-209) | proto fields |


`wait_on_ready=1` and wowsims's "wait" are not the same thing: both stay on the step; SimC also stops the list
below. That is why ruling 26 has three values: `mode=wait` is SimC's, `mode=continue` is wowsims's.

## 1. Rules at a glance

1. Every window's state lives in the belief. The core keeps nothing between updates.
2. A window is declared in one of three places: in the class file (Lua, `RegisterWindow`, with an evaluator), in
   the priority's `windows` list (`window,name=X,duration=...`), or by a `sequence` / `strict_sequence` line, which
   declares its own. `windows` is a reserved list name.
3. A window used by `open_window` or `close_window` must be declared exactly once. An undeclared name, a second
   declaration, or a declared name the class already registers in Lua is a compile error.
4. `open_window` and `close_window` lines carry only `name=` and `if=`, for every window, Lua-registered ones
   included. Length, refresh and reset settings live only in the declaration. Anything else on the line is a
   compile error. The name may be a sequence's.
5. APL window lines are commands, run in list order. A true `open_window` opens the window; if it is already open
   nothing happens, unless the window is declared `refresh=1`, which restarts its timer within `max_refresh` and
   `max_duration`. A true `close_window` closes it.
6. There are no edges for APL windows. A condition that stays true keeps the window open, and reopens it after it
   expires. A line that is not reached does nothing.
7. After a line changes the window (open, close, granted refresh, step change), the walk starts again from the top
   with time unchanged, so lines above see the change in the same decision. Each line can act once per slot: the
   fired mark is cleared at the start of every slot. There is no restart cap; restarts per slot cannot exceed the
   number of window lines.
8. Only slot 1's walk at time = now talks to the belief. It sends the ordered list of operations that changed the
   window (OPEN, CLOSE, and for sequences STEP). The belief replays them, in order, at the start of its next
   update: CLOSE and STEP as writes, OPEN by the window's declared refresh rule (v6.1). Forecast slots act on the
   copy and never send anything.
9. Each display has its own copy of every APL window, under its own key (`<pack>:<name>#<display>`). The belief sees
   separate windows and knows nothing about displays or priority lines. Lua windows are one shared instance.
10. Lua windows keep their evaluator and edge rules (a rise opens, a fall closes only with `close_on_false`). New
    in 0.9: the optional field `reset_on_target_change`, default off.
11. A press never opens a window. Presses (observed casts) advance the steps of a sequence that is already open.
12. A strict sequence opens when its line is the one chosen at now. By default (SimC) the line can be chosen only
    when every member can be cast now, with no tolerance. With `start_on_first=1` (wowsims) it can be chosen when
    its first member is due within the spell queue window. While it is open, that display shows no on-GCD line
    outside it. Lines marked `use_off_gcd=1` are still shown (SimC), unless the sequence says `hold_off_gcd=1`
    (wowsims). A step not pressed within `step_timeout` (4 s) closes it.
13. A plain sequence opens when its line is reached at now and its condition is true. `mode=` says what happens
    when the due member cannot be cast: `skip` (default, SimC) drops that member for this run, and burns the
    sequence out only if no remaining member can be cast; `wait` (SimC's `wait_on_ready=1`) shows the member with
    its countdown and recommends nothing below the line; `continue` (wowsims) stays on the member and lets the list
    carry on. A line whose `if=` is false shows and skips nothing.
14. After its last step a plain sequence parks: it stays up with no step due until `restart_sequence` or combat
    end. `window.<seq>.done` is true while it is parked. There is no `loop` option on sequence lines; a loop is
    `restart_sequence,name=x,if=window.x.done`.
15. "Can be cast" is judged at the moment the player can next act: the end of the GCD or cast for an on-GCD
    member, now for an off-GCD one.
16. Sequence behaviour is written on the line. What a line does not say is SimC's behaviour. Option names are
    SimC's where SimC has one (`name=`, `wait_on_ready=1`, `allow_skip=1`, `restart_sequence`) and SimC-styled
    where it has none (`mode=`, `start_on_first=1`, `hold_off_gcd=1`, `step_timeout=`, `reset_on_target_change=1`).
    Nothing is inferred from the abilities. An import adds nothing to a line. The wowsims translator writes the
    wowsims settings on every sequence it emits. An option an entry does not take is a compile error.
17. A window also closes at its duration, at `max_duration`, at combat end, on a `closeWindow` from a real cast,
    and (strict) on any other on-GCD cast, on a later member's cast out of order (on or off the GCD), or at the step
    deadline. A target change closes nothing, unless the
    window's declaration (sequence line, `windows` entry or `RegisterWindow`) says `reset_on_target_change`.
18. Sequences run in Primary and AOE only. While a sequence's window is up there, the display shows the
    sequence's members even when the "toggle shown separately" test would hide them, and the start line skips that
    test too, so a sequence that begins with a separated cooldown starts there. A toggle that is switched off still
    disables the member. Cooldowns, Interrupts and Defensives carry on as they are.
19. Primary and AOE each have a "Sequences" setting, on by default. Where it is off, sequences do not exist for
    that display: no keys, and its pass skips sequence lines as if they were not in the priority. Cooldowns,
    Interrupts and Defensives never sequence and have no such setting (L1315). Free-form windows work in every
    display.
20. An unnamed plain sequence is `default`, as in SimC; further unnamed sequences and every unnamed strict one get
    generated names.
21. These are tools for pack authors. The engine does not protect against a priority that opens and closes a
    window every pass; it shows it in the snapshot instead, with the restarts per slot.
22. Every parameter of a sequence line, a `windows` declaration and an open or close line is visible and editable
    on the Actions tab, shown with its effective value, defaults included.
23. A step is a cast. Moves and waits are never steps. In the default strict start test, a member after the
    first may be judged with some of its gates skipped (`sequence_ignore`) or by its own handler
    (`sequence_ready`), both declared by the pack on the ability. This is how a sequence whose first member
    enables its second (a stance, a buff) can start without `start_on_first=1`.

## 2. Two kinds of window

| | Lua-led | APL-led |
|---|---|---|
| Declared | `spec:RegisterWindow` (Engine/Schema/Spec.lua:434) | the `windows` list, or a sequence line |
| What drives it | an evaluator the belief runs every Drain, with edge rules (Families/Windows.lua:164-182) | operations replayed from the display's now pass; no evaluator |
| Instances | one | one per display, each its own key (five fixed displays, Engine/Sim/Core.lua:1384-1390) |
| Registered | SpecializationChanged (Schema/Spec/Activation.lua:336) | at script load, applied out of combat, or in combat when the belief has no APL window yet (section 9) |
| Steps | require an evaluator (L773) | a sequence's members |
| Target change | nothing, unless `reset_on_target_change = true` | nothing, unless `reset_on_target_change=1` |

- `RegisterWindow` raises when `steps` is given without `evaluator` (L773). The shipped stepped windows all have one
  (Hunter.lua:832, Paladin.lua:812 and 820). [H] Those three (`hha`, `move1`, `move2`) become APL sequences in
  Phase 3 (ruling 32); `weave` (Hunter.lua:420) and `riposte` (Rogue.lua:380) stay Lua windows.
- Inside the belief an APL-led window is an ordinary row with no evaluator, the owner's "compiled into Lua windows
  with no evaluator". The belief has no notion of "APL window", "display" or "line": it has rows by key, some with an
  evaluator and some without, plus an operations list addressed by key.
- APL-led records travel in a separate list (`def.aplWindows`) only so they can be re-applied without a full rebuild
  (section 9) and so they skip RegisterWindow's checks.

## 3. Declarations

3.1 Anonymous windows (L795, L796). A compile-time-only named list, like `precombat` is a named list:

```
actions.windows+=/window,name=burst,duration=12
actions.windows+=/window,name=pool,duration=6,refresh=1,max_refresh=2,max_duration=15
```

- `name` and `duration` are required. `duration` is seconds (positive) or `combat`. `refresh` (0/1, default 0),
  `max_duration` (seconds) and `max_refresh` (count) are optional and mean what they mean in RegisterWindow
  (Spec.lua:425-433). `reset_on_target_change=1` is optional (section 8). No function durations, no
  `close_on_false`, no steps here.
- The list is never walked and cannot be called. SimC imports simply lack it. The name is reserved (ruling 22): a
  user's existing ordinary list called `windows` gets E5 on load; the release notes say so.
- "Before use": lists are stored by name, so text order is not kept after import. The compiler reads the
  `windows` list before every other list; a line naming a window that the list does not hold is "used before
  declared".

3.2 Lines. `open_window,name=W[,if=]` and `close_window,name=W[,if=]`. Nothing else, whatever kind of window W is
(ruling 21): a list-declared window, a sequence (ruling 23) or a class's Lua window. A bare line is true when
reached.

3.3 Sequences self-declare. `sequence,name=x:a:b:c` and `strict_sequence,name=x:a:b` declare window `x` with their
members as steps. Options go where SimC puts them, in the first token before the steps:
`strict_sequence,name=x,start_on_first=1,if=cond:a:b,if=own`. A member may carry its own options after a comma.

The full option table (rulings 17, 24, 26, 33). "=1" flags are off unless written, as `wait_on_ready` is in SimC.
"The translator" is the wowsims translator, tools/wowsims/apl.lua.

| Option | Applies to | SimC native or Hekili | Default (unwritten) | Written | The wowsims translator writes |
|---|---|---|---|---|---|
| `name=<n>` | `sequence`, `strict_sequence`, `restart_sequence`; `window`, `open_window`, `close_window` (required there) | SimC native | first unnamed `sequence` and a bare `restart_sequence`: `default`, as in SimC. Further unnamed sequences and every unnamed `strict_sequence`: a generated name | the window's name | always. Strict: a generated name, `<first member>_<last member>`. Plain: the snake form of the wowsims name |
| `if=<cond>` | every entry except `window` | SimC native | true when reached | the entry's condition. On a sequence line: the sequence's own; on a member: the member's own | the node's condition |
| `mode=skip\|wait\|continue` | `sequence` | Hekili, SimC style | `skip` (SimC): an active sequence whose due member cannot be cast drops that member for this run; with no remaining member castable it burns out (parks) | `wait`: stays on the due member, shows it with its countdown, nothing below the line is recommended (SimC `wait_on_ready=1`). `continue`: stays on the due member, the line is not ready, the list carries on below (wowsims) | `mode=continue` on every `sequence` |
| `wait_on_ready=1` | `sequence` | SimC native | 0 | an alias for `mode=wait`. The editor shows `mode=wait`; the text is kept as written. Written together with `mode=`: E7 | never |
| `allow_skip=1` | `strict_sequence` | SimC native | 0: a due member that cannot be cast ends the sequence | starts when any member can be cast; a due member that cannot be cast is skipped; past the last, the sequence ends | never (wowsims has no such behaviour) |
| `start_on_first=1` | `strict_sequence` | Hekili, SimC style | 0: the line can be chosen only when every member can be cast now, due at delay 0 | the line can be chosen when its first member is due within the spell queue window; later members are not tested | `start_on_first=1` on every `strict_sequence` |
| `hold_off_gcd=1` | `strict_sequence` | Hekili, SimC style | 0: while open, outside lines marked `use_off_gcd=1` are still shown | while open, nothing outside the sequence is shown | `hold_off_gcd=1` on every `strict_sequence` |
| `step_timeout=<seconds>` | `strict_sequence` | Hekili, SimC style | 4: the window closes when the due step has not been cast for 4 s; the timer restarts at each advance | that many seconds, positive | never (the 4 s default stands) |
| `reset_on_target_change=1` | `sequence`, `strict_sequence`, `window` declaration; as the field `reset_on_target_change = true` in `RegisterWindow` | Hekili, SimC style | 0 everywhere: a target change changes nothing | a target change closes the window; a sequence is back to not started, a parked one too | never (wowsims does not reset on a target change) |
| `duration=<seconds>\|combat` | `window` declaration (required) | Hekili (L796) | none: missing is E6 | the window's length | only where a pack declares a window (none does) |
| `refresh=1` | `window` declaration | Hekili (L796) | 0: a true open line on an open window does nothing | a true open line on an open window restarts its timer | as above |
| `max_duration=<seconds>` | `window` declaration | Hekili (L796) | no cap | total span from the first open | as above |
| `max_refresh=<count>` | `window` declaration | Hekili (L796) | no cap | number of refreshes per open | as above |
| `restart_sequence,name=<n>[,if=]` | its own line | SimC native | | step 1 when true and the sequence is up at any other step, parked included. On a closed window: nothing | one line per wowsims `resetSequence` |
| `window.<seq>.done` | a condition read | Hekili, SimC style | | true while a plain sequence is parked (up, step past the last member). False for a strict sequence, a closed window, a free-form window | for wowsims `sequenceIsComplete` |
| member options (`use_off_gcd=1`, `focus=`, `cycle_targets=1`, `if=`, ...) | each member, after its comma | SimC native / existing | as for an ordinary line | as for an ordinary line | the ones the `prev.1` chain carries today |

- Replaced, never shipped: v4's `unready=wait|skip`, `start=first|all`, `off_gcd=hold|allow`,
  `target_change=end|continue`. A line that carries one gets error E7 (ruling 34).
- "Can be cast", "ready" (ruling 28; one meaning for the skip, the all-members start, the `allow_skip` start and
  the give-up): the member is usable, off cooldown, affordable and its own `if=` is true at the moment the player
  can next act, that is at the end of the current GCD or cast for an on-GCD member and at now for an off-GCD one.
  This is the moment SimC tests at (its ready event). Tested at now with the GCD still running, every on-GCD
  member would read "not ready" and a default plain sequence would skip itself to the end.
- The default strict start and D2 together: the line is due at delay 0, so the GCD is ready and "the moment the
  player can next act" is now. Later members are tested at that same moment; the GCD the first member will start
  is not counted against them, as it is not in SimC (`ready()` does not look at the GCD).
- `allow_skip=1` with `start_on_first=1`: the start follows `start_on_first`; skipping applies after the start.
- Sequence windows have no `duration=`: a plain sequence lasts the fight ("combat": it ends by parking, by
  `restart_sequence`, by a close line or at combat end); a strict one lasts until its last step, a give-up, a
  deviation or `step_timeout` on any step.
- Unnamed sequences (ruling 31): the first unnamed `sequence` of a priority is `default`; further unnamed
  sequences, and every unnamed `strict_sequence`, get generated names (`default_2`, `strict_1`, ...), kept with
  the line so that they are stable.
- `hold_off_gcd` default (ruling 29, SimC's exact reach): only lines marked `use_off_gcd=1` whose ability is off
  the GCD pass. A zero-GCD ability on a line without the mark waits for the GCD in Hekili as it does in SimC
  (Engine/Sim/State.lua:7531-7536) and is held like any other line.

3.4 Compile errors. An error disables the offending line, is listed with the priority's warnings (the import and
editor path, Options.lua:8611), and fails the build for shipped packs.

| # | Error |
|---|---|
| E1 | `open_window` / `close_window` names a window that is not declared in the `windows` list, not a sequence of this priority and not a class (Lua) window |
| E2 | a name declared twice: two `window` entries, two sequences, or a `window` entry and a sequence (one namespace per priority) |
| E3 | a declared name (list or sequence) that a class already registers in Lua, in any spec of the class (the `knownWindow` scan, Options.lua:8485-8491) |
| E4 | an `open_window` / `close_window` line that carries anything besides `name=` and `if=`, whatever kind of window it names (ruling 21) |
| E5 | a `window` entry outside the `windows` list; any other entry inside it; `call_action_list` / `run_action_list,name=windows`; `if=` on a `window` entry. A user's old ordinary list called `windows` lands here (ruling 22, release note) |
| E6 | a declaration with a missing or non-positive `duration`, bad caps, or a non-positive `step_timeout` |
| E7 | an option that the entry does not take: any option on a `sequence`, `strict_sequence` or `window` entry outside the table in 3.3 (v4's `unready=`, `start=`, `off_gcd=`, `target_change=` included); a `mode=` value other than `skip`, `wait`, `continue`; `mode=` or `wait_on_ready` on a strict sequence; `mode=` together with `wait_on_ready`; `allow_skip` / `start_on_first` / `hold_off_gcd` / `step_timeout` on a plain one |

3.5 Lines naming a Lua window (ruling 21). The same form as every other window line: `name=` and `if=` only. The
window's length and refresh settings are the ones `RegisterWindow` holds. Today's code accepts `duration=` and
`refresh=1` on such a line (Core.lua:544-578, State.lua:1696-1713); that is removed, and the line gets E4.
- No shipped priority or recipe has an `open_window` or `close_window` line [H: grep of the packs and of
  tools/wowsims/specs]. The Hunter `weave` window opens from Raptor Strike's handler (Hunter.lua:470); `hha`,
  `move1`, `move2` and `riposte` open from evaluators. v5's "the Hunter packs' weave line" was wrong, and the
  comment at Hunter.lua:416 that mentions "the pack's open_window line" is stale: fix it in Phase 2.
- What such a line does is unchanged: it acts on the display's copy only (forecast), restarts the walk when it
  changes the copy, and sends nothing. The belief's row follows the evaluator. The fired mark is the same per-slot
  mark as for APL windows. The drift guard (tests/Forever/helpers/wowsims.lua:590) covers them.

3.6 Ability fields for the strict start test (ruling 36). SimC's start rule, "every member can be cast now", cannot
pass for a sequence whose first member enables a later one: `battle_stance:overpower` out of Battle Stance. Two
optional fields on the ability, written by the pack where it registers its abilities, tell the start test how to
judge such a member.

| Field | On | Type | Default | Meaning | Used by |
|---|---|---|---|---|---|
| `sequence_ignore` | an ability record (`RegisterAbilities`) | a list of gate names: `"form"`, `"noform"`, `"buff"`, `"nobuff"` | none: no gate is skipped | in a strict sequence's start test, this member's normal readiness with the named gates skipped | Warrior: Overpower `{ "form" }`, Rend `{ "nobuff" }` |
| `sequence_ready` | an ability record | a function with no arguments, in the ability-function environment, like `usable` | none: the start test uses `ready()` | in a strict sequence's start test, replaces this member's readiness; a true result is "can be cast" | no shipped ability in 0.9 |

- Where they apply, and only there: the start test of a `strict_sequence` line without `start_on_first=1` (the
  all-members test, and the any-member test of `allow_skip=1`), for members after the first.
- Where they never apply: the first member; any step once the sequence is open (the hidden list, the give-up and
  the `allow_skip` skip use normal readiness: by then the first member has been cast and the real gate is the
  truth); plain sequences; ordinary lines; a line with `start_on_first=1`, which does not test later members at
  all. So they change nothing in any shipped pack line: the translator writes `start_on_first=1` on all 18.
- The gates are the ones the core already applies from the ability's own fields (Engine/Sim/State.lua): `form`,
  `noform` and `buff` in the usable test (7402-7419), `nobuff` as a wait in the time-to-ready (7597). Skipping a
  gate means that test is not made for this one judgement. Everything else stays: known, toggles, the ability's
  own `usable` function, cooldown, cost, range, and the member's own `if=`.
- A name outside the four raises at registration, as a wrong `on_deviation` does for a window. A gate named but
  absent from the ability is not an error (a talent may add the field).
- `sequence_ready` reaches the normal test as `ready()`: a function in the same environment the handler runs in,
  valid only during the handler's call, returning true when this member can be cast by the normal start test
  with `sequence_ignore` already applied. So the owner's two uses read:

```
sequence_ready = function() return ready() and buff.flurry.down end   -- the normal test plus a condition
sequence_ready = function() return rage.current >= 5 end              -- a replacement
```

- How the two combine: `sequence_ignore` narrows the normal test; `sequence_ready`, when present, is the test,
  and `ready()` inside it is the narrowed normal test. With only `sequence_ignore`, the test is `ready()`. With
  neither, it is normal readiness, as before. The member's own `if=` is and-ed outside either, always.
- Timing is unchanged (ruling 28): the judgement is made for the moment the player can next act.
- Core stays generic (the core-generic rule): the core knows four gate kinds, which are fields it already reads;
  it knows no stance, form or buff by name. The pack says which of an ability's gates a sequence may look past.
  The priority stays explicit too (ruling 5): the fields do nothing unless a strict line is written without
  `start_on_first=1`.

## 4. The pass: lines as commands

4.1 The working copy. At each display's reset the core seeds its copy from the belief (`state.CopyWindows`,
State.lua:1686-1691). For an APL-led window with plain name `burst`, display `Primary` reads
`Facade.Window("<pack>:burst#Primary")`. `Facade.Window(name)` keeps its one-argument form (Game/API/Facade.lua:1369);
v3's `display` argument is not added. The core holds one row per APL window and a prebuilt table of keys per
display, so no string is built per cycle. Priority text keeps reading `window.burst.up`.

4.2 What a line does, at the line's time, for an APL-led window:

| Line | Copy closed | Copy open |
|---|---|---|
| `open_window`, true | open with the declared duration: operation OPEN | declared `refresh=1` and within `max_refresh` / `max_duration`: restart the timer, operation OPEN (the belief applies the same rule). Otherwise nothing |
| `close_window`, true | nothing | close: operation CLOSE |
| either, false or not reached | nothing | nothing |

The copy's open and close are the existing ones (`state.openWindow`, `state.closeWindow`, State.lua:1696-1706), whose
caps are the belief's written again, with one difference: `state.openWindow` counts a refresh at the `max_duration`
cap, where the belief refuses it for an APL window. Phase 2 gives the copy's open a per-kind branch (APL windows
refuse there; Lua windows keep that rule, L1182). The reference for an APL window's OPEN is the oracle `M.apply` in
tests/Game/State/helpers/windows_matrix.lua.

4.3 Restart. After any line that actually changed the copy (an open, a granted refresh, a close or a sequence's STEP), the
slot's walk restarts from the top with time unchanged (wowsims re-picks from the top after every executed action,
sim/core/apl.go loop near line 552 with a 1000-pass guard [H]).

- A restart drops the partial pick, `state.delay`, the Stack and Block lists (as Core.lua:1536-1537) and
  `state.nearAction` (Core.lua:780, 1110), and unwinds nested lists with a flag like `stop` (Core.lua:639). No tables.
- Fired mark, per slot (ruling 20). `WIN.lineLast` (State.lua:1600, 1709-1713: one boolean per line, today cleared
  at each reset, 1690) becomes "this line already changed the copy in this slot", for open lines, close lines,
  `restart_sequence` lines and the lines a sequence generates. It is cleared at the start of every slot's walk,
  not once per cycle, so a line that acted in slot 1 can act again in slot 2 and the forecast shows a window
  opening, closing and reopening as the priority would drive it. Within a slot a marked line does nothing more.
  Without the mark the owner's example below would loop.
- No restart cap (ruling 24). Every restart follows a line that just took its mark, so restarts per slot are at
  most the number of window lines in the priority (generated sequence lines and the strict give-up check
  included), a number fixed at compile time. Nothing is truncated. The count of restarts per slot goes into the
  snapshot and the debug output (section 15). Phase 2's CPU gate measures the cost; if it is ever too high the
  answer is a warning to the author, never a silent stop.
- A granted refresh restarts the walk like an open or a close (ruling 19).
- It applies at every slot and to future-dated opens (an open line that passes only at a recheck time opens the
  copy at that time, as today, Core.lua:555-566, and `state.WindowRecheck`, State.lua:1717-1725, gives a higher line
  its countdown).
- Lines on Lua windows restart the walk the same way when they change the copy, and use the same mark (3.5).

4.4 The owner's example, `open_window` at the top and `close_window` at the bottom, both true:

| Walk | What happens |
|---|---|
| 1 | top line opens the copy: OPEN, marked, restart |
| 2 | top line is marked: nothing. Lines in between see the window up. If one of them is a ready pick, the walk ends there and the window stays open. Otherwise the bottom line closes the copy: CLOSE, marked, restart |
| 3 | both lines are marked: nothing. Lines in between see the window down. The pass ends with the window closed |

The belief receives OPEN then CLOSE and ends closed too. The same happens in slot 2 and later slots (the mark is
cleared per slot; nothing is sent from them), and on the next pass, and the next: see section 15.

4.5 Level, not edge. Nothing remembers a line's previous value between passes. If the copy is closed (the window
expired, was closed by a cast, or combat ended) and an open line is true, it opens again. A bare `open_window`
reached every pass is a window that is always open. A held-true line on a `refresh=1` window restarts the timer
every pass until `max_refresh` or `max_duration` stops it.

## 5. The crossing: operations by key

5.1 What is sent. Only from the main slot loop (Core.lua:1562), slot 1, `state.offset == 0`, the line evaluated at
delay 0 (not inside the recheck loop). Each change to the copy appends one operation:

| Operation | Argument | Belief's replay |
|---|---|---|
| OPEN | none | closed or run out at T: window up, opened at T, expires at T + the declared duration (capped by `max_duration`), refreshes 0, step 1 if stepped. Open at T: the declared refresh rule (v6.1): declared `refresh=1`, refreshes below `max_refresh` and expiry below openedAt + `max_duration`: expires at T + the declared duration, capped at openedAt + `max_duration`, refreshes + 1; otherwise nothing |
| CLOSE | none | window down |
| STEP | step number | sequences only: step set to that number (section 6) |

One call, `ns.VirtualState.WindowOp(key, op, arg)`, writing three plain values into a preallocated buffer. It
replaces v3's two calls. `key` is the compiled per-display string. There is no display, no line, no time argument.
The alternatives probe also resets state (Core.lua:1392-1419) and sends nothing. [M]

5.2 Stamp. Operations waiting in the buffer are stamped with the cutoff of the Drain that preceded them
(Core.lua:1492), which the belief already has; the emission time is not used, because the Update coroutine yields
across frames (Core.lua:516-523).

5.3 Replay. `VS.Drain` (Game/State/Sources/Sources.lua:211-228) becomes: Flush, **window operations**, RunPolls,
Fold, Settle, RunWindows, DeliverAuraDeltas. Operations go first and not through the observation fold because
`I.Fold` applies in arrival order and clamps old stamps to the clock (Game/State/Belief.lua:62-72): a cast heard
while the cycle was still running would otherwise be applied before the open that should have preceded it. All
operations carry the previous cutoff, so "operations, then newer observations" is true time order. Each applied
operation is written to the log (SetLog) so a recording replays the belief without the core. [H for the fold, M for
the fix]

5.4 CLOSE and STEP are writes (ruling 18); OPEN is judged by the declared refresh rule (v6.1). The copy was seeded
from the same belief state that the replay meets: the belief changes only inside Drain, and the operations are
applied before anything else in the next one, so the core's forecast of the rule and the belief's apply agree. The
one place the two can differ is a window that expired between T and the display's own "now": the copy saw it
closed and opened it fresh; the belief at T still has it up, so the OPEN is a refresh where `refresh=1` allows one
and nothing where it does not. A window without `refresh=1` then runs out at that Drain and a still-true open line
opens it again at the next pass; if that line is false on the next pass, the open is lost (L1180: accepted, no
channel change). This is the matrix's one named carve-out of forecast == apply (OP5). An OPEN the rule refuses is
traced and counted as `refused` (L1182). An operation for an unknown key (an edit in combat) is dropped and counted.

5.5 Buffer size. Exact, not a guess: a line fires at most once per slot and only slot 1 sends, so one display sends at most (window
lines + sequence-generated lines) operations per pass. The buffer is sized as the sum of that over the displays (sequence lines count only where Sequences is on,
section 7) when the windows are
applied. Nothing is allocated per Drain or per operation.

5.6 Border. tools/check_border.sh accepts `WindowOp` beside Drain, Build and SetLog, and its sentence "writes
nothing back" changes. `Facade.Window` stays the only window read.

5.7 What the belief still does by itself, as for any window: expiry, `max_duration`, combat end closing all
(Windows.lua:184-188), `closeWindow` from an ability's `now()` on an observed cast (Families/Now.lua:487-491), steps
advancing on observed casts (Windows.lua:128-160), strict deviation (another on-GCD cast ends a strict window, and
a later member's cast out of order ends it through the record's `on_deviation = "end"`, L1181),
`step_timeout`, and the target-swap reset for rows declared with it (section 8).

## 6. Sequences on the operations model

A sequence compiles into a self-declared window (one key per display that has Sequences on, section 7), generated
lines at the sequence line's position, and (strict only) a hidden list.

| Piece | How it works |
|---|---|
| start, strict | OPEN, sent when slot 1 is final (the slot-filling block near Core.lua:1895-1917), if the sequence line is the slot-1 pick and due now. Rechecks and early exit are already in the answer. No restart: the pick stands. The copy opens at once so slots 2+ show the next members through `state.WindowCast` (State.lua:1729-1754) |
| start test, default | compiled into the line's condition: every member can be cast (3.3's meaning). "Due now" is delay 0, with no tolerance (ruling 27). A member after the first is judged through its `sequence_ignore` / `sequence_ready` where the ability has them (3.6); that needs one engine read, "this member's start-test readiness" |
| start test, `start_on_first=1` | only the first member is tested, and "due now" is within NOW_TOL = the spell queue window (rulings 11, 27) |
| start test, `allow_skip=1` | compiled into the condition: at least one member can be cast (members after the first through 3.6's fields). The first member shown is the first that can, by normal readiness |
| start, plain | a generated open line with the sequence's condition, at the sequence's position: reached at now and true, it sends OPEN (ruling 12). It restarts the walk like any open line |
| steps | belief rule: the observed cast of the due member advances it. Unchanged |
| end of a strict sequence | after the last step the window closes. Chosen again later, it opens again |
| end of a plain sequence | the window parks: it stays up at step = members + 1, no member due, until `restart_sequence` or combat end (ruling 15) |
| give-up (strict, default) | CLOSE: after the hold's walk of the normal lists (a due member's `if=` may read a variable that walk defines), if the hold is active, the GCD is ready and the due member cannot be cast, the copy closes. The CLOSE restarts the walk unheld (one counted restart, section 14.3; a close restarts the walk, ruling 19) and the normal lists answer in the same slot. Once per slot (it takes a mark like a line). SimC cancels at the same point (sequence.cpp:295-306), wowsims gives the rotation back (seq.go:263-267) |
| skip (strict, `allow_skip=1`) | STEP in place of that CLOSE: the copy moves to the first later member that can be cast; if there is none, CLOSE. The STEP restarts the walk as the CLOSE does (4.3; one counted restart, once per slot): the outside lines are read again at the new step, then the members answer. The STEP sent with an `allow_skip` start is part of the start and restarts nothing |
| `mode=skip` (plain, default) | STEP: a generated line at the sequence's position, under the sequence's condition. When it is reached with the due member not castable at the player's next moment to act, it moves the copy to the first later member that is; the dropped member is not offered again in this run. No later member castable: STEP to members + 1, the sequence is burnt out, which is the parked state (SimC runs off the end, sequence.cpp:150-167; ruling 28). Not reached, or the sequence's `if=` false: nothing is skipped |
| `mode=wait` (plain) | no skip line. The due member's generated line is taken as the pick even when the member is not ready, shown with the time until it is; the walk ends there, so nothing below the sequence line is recommended, in its list or below the `call_action_list` / `run_action_list` lines that reached it (SimC: the line counts as ready and the actor waits, sequence.cpp:95-108, 157-164; every caller returns it). Lines above the sequence line are untouched |
| `mode=continue` (plain) | no skip line. The due member's generated line is simply not ready and the list carries on below (wowsims, seq.go:63-68) |
| `restart_sequence,name=x,if=` | STEP 1 when true and the window is up at any other step (parked included). On a closed window: nothing. Restarts the walk |
| `reset_on_target_change=1` | belief rule on `Obs.TargetSwap` (section 8): a window property, closes the window. Unwritten: the swap does nothing |
| `window.<seq>.done` | a read on the copy: up and step = members + 1. One more key in the existing window read (State.lua:1643-1651) |
| `step_timeout` (strict) | belief rule, a window property: the timer restarts at each advance; when it runs out the window closes. Default 4 s (ruling 24) |

Parking (ruling 15). A wowsims or SimC plain sequence runs once until reset (sequence.cpp:145-167; seq.go:63-68,
124-126). With level semantics a finished sequence whose condition is still true would reopen on the very next
pass and loop. Parking needs no new state and no new facade value: the window is simply still open, so its open
line does nothing; `sequenceIsComplete` reads "step is past the last member"; `restart_sequence` is STEP 1; combat
end closes it. A plain sequence closed early (a close line, a target change with the reset option) is closed, not
parked, and its open line starts it again from step 1. `window.x.up` is true while parked; `window.x.done` is the
test for it. "In progress" is `window.x.up&!window.x.done`.

The loop (ruling 30), written as SimC and wowsims write it:

```
actions+=/restart_sequence,name=x,if=window.x.done
actions+=/sequence,name=x:a:b:c
```

The restart line sends STEP 1 and restarts the walk, so the first member is due again in the same pass.
`restart_sequence` is level like everything else: held true, it sends the sequence back to step 1 in every slot in
which the step is not 1. wowsims's reset action behaves the same way. [M]

A plain sequence's generated lines, in order at the sequence's position, all under the sequence's condition
(SimC: a sequence whose `if=` is false is not ready and does nothing):
1. the open line (OPEN when the copy is closed);
2. with `mode=skip` only, the skip line (STEP);
3. one line per member, in order; the line of position K is
   `<member>,if=window.<w>.step=K&<the member's own condition>`. Only the due position's line can pass, so an
   ability that appears twice is judged by the condition written at the due position (SimC and wowsims judge the
   due step's action only). With `mode=wait` the due member's line is accepted with its wait.

Other lines of the priority may read `window.<w>.next.<member>` too; it is true at every position that holds that
ability; `window.<w>.step` tells positions apart. A cast advances the step whichever line recommended it. This is how one member can be offered at several list positions (the `hha` conversion, section
10).

In the pass:
- Hold: at the top of each slot's walk the engine checks whether a strict APL window is up in this display's copy.
  If so it walks the normal lists first, then runs the give-up, then walks that window's hidden list. From the
  normal lists the default hold takes window lines (with the `call_action_list` / `run_action_list` / `variable`
  lines that reach them) and entries marked `use_off_gcd=1` whose ability is off the GCD (SimC, ruling 29); such an
  off-GCD line that is ready shows ahead of the due member, and the member takes the next slot. With
  `hold_off_gcd=1` it takes window and variable lines only (wowsims): no ability line outside the sequence is shown;
  when the priority has no `open_window`, `close_window` or `variable` line (enabled or not, in any list) the normal
  lists are not walked at all. A close line aborts the sequence at once (ruling 23, S24); variables exist before the
  members' conditions read them. Sequence lines (`sequence`, `strict_sequence`, `restart_sequence`) do nothing under a
  hold: no other sequence starts, steps or restarts meanwhile (both simulators agree, 0.1; a plain sequence below
  opens on the first pass after the hold). `open_window` / `close_window` lines naming a sequence still act (ruling
  23: explicit commands). Decided for the owner (Fable, ledger L1270, on L1249's condition): the walk of the normal
  lists under a hold, its skip under `hold_off_gcd=1`, and this order. The order departs from SimC on one tie: SimC
  picks the member when the actor is ready and runs an off-GCD line only while it waits for its next ready
  (player.cpp:6792-6838, 7365-7369); here a ready outside off-GCD line is shown first even when the member is
  castable now. The presses are the same two and the line is off the GCD; the built order is the quieter one (the GCD
  ending moves nothing). Consequence (L1181's fourth case): an outside `use_off_gcd=1` line for a later member of the
  held sequence takes slot 1 whenever it is ready, and pressing it ends the sequence; the author's to manage (ruling
  7). An engine check, not a generated line, so it does not depend on `run_action_list` blocking. `precombat` gets
  the same check.
- Hidden list lines: the line of position K is `<member>,if=window.<w>.step=K&<the member's own condition>`. The
  sequence's condition is not re-read once a strict sequence is open.
- A plain sequence has no hold.
- `open_window` / `close_window` on a sequence's name are allowed (ruling 23): a close line is a way to abort a
  sequence; an open line on a strict sequence starts its hold without the line being chosen; an open line on a
  plain sequence opens it at step 1 wherever that line sits.

## 7. Pools, displays and keys

- Belief rows: Lua windows, then one row per (APL window, display) under its key. The belief does not know they
  are related. Preallocated when applied.
- Each display's pass seeds from, and sends operations to, its own keys only.
- A display that is not walked (off, hidden, not wanted: Core.lua:1531) sends nothing; its open windows still
  advance on casts and end by duration, deadline, combat end, or a target change where the reset is asked for.
- An observed cast advances every open stepped window, so one cast moves the same sequence in every display where
  it is open.
- Cross-display, decided (ruling 9, L806): "Yes, force the ability into the display that is in a
  sequence. Cooldowns/defensives/interrupts can continue to function as they are and the player can decide what to
  do."
  - Rule: sequences run only in Primary and AOE (L1315), whose display filter is "none"; what hides an ability
    there is the "this toggle is shown separately" test (Engine/Sim/State.lua, IsDisabled's prefix). While a
    sequence's window is up in a display's copy, that display's compiler-generated sequence lines (a strict
    sequence's hidden list; a plain sequence's in-place member lines) skip that test, so a sequence running in
    Primary shows a later member that is a separated cooldown. A toggle that is switched off still disables the
    member (the strict give-up then closes the sequence).
  - Mechanism: generated lines carry a compile-time mark; the walk sets `state.seqBypass` around a marked line's
    evaluation, and IsDisabled neither reads nor writes its cache for such a line.
  - Nothing is shared between displays: no second key, no extra operations. v4's first draft proposed `+` keys;
    they are dropped. A display in which the sequence was not chosen does not open it and is not held.
  - The start line (ruling 25): in Primary and AOE, a sequence's start line (the strict sequence line with its
    first member; a plain sequence's first member line) also skips the "toggle shown separately" test, with no
    window up yet. So a sequence that begins with a separated cooldown is chosen, shown and started in Primary,
    overriding the ability's display category. A switched-off toggle still disables it.
  - Displays may disagree about what is next. Each runs its own pass with its own target count and filter
    (Core.lua:1383-1390; State.lua:6505-6524: Primary clamps to one target in single, dual and reactive modes, AOE
    forces at least the AoE threshold, Cooldowns, Interrupts and Defensives use the real count and their toggle).
    The player decides.
- The "Sequences" setting of Primary and AOE (owner, L808-L809, L1315).
  - On by default. Stored with the display's other options in the profile and shown on the display's options
    page. Cooldowns, Interrupts and Defensives never sequence and have no such setting; a value an older profile
    stored for them is ignored.
  - Off means sequences do not exist for that display. The compiler makes no sequence keys for it, and its pass
    skips every sequence line: the `sequence` / `strict_sequence` line and everything generated from it (start,
    members, skip), with no evaluation, as if the lines were not in the priority. No hold, no operations.
  - Same reading (14.3): in an off display `restart_sequence` lines and `open_window` / `close_window` lines
    that name a sequence are skipped too, and `window.<sequence>.up` reads false (there is no key).
  - Sequences only. Free-form windows (`actions.windows`, `open_window`, `close_window`) keep one key in every
    display and work everywhere (owner: "Yes freeform windows will still work").
  - Sequences run in Primary and AOE, and the bypass above shows a separated cooldown member there; a sequence
    led by a separated cooldown is chosen and started there (ruling 25, D02).
  - Changing the setting is a registration change: it goes through the same generation bump as a priority edit
    (section 9), at once out of combat, else at combat end (in combat at once only while the belief has no APL window yet).
  - With Cooldowns shown separately, a sequence whose first member is a separated cooldown starts in Primary
    through the start-line exception above, and is skipped in Cooldowns.

## 8. Target change

By default a target change does nothing to any window or sequence (ruling 16: "because of potential sequences with
target swap recommendations"; SimC and wowsims do nothing either). A member with `cycle_targets=1` can therefore ask
for a swap in the middle of its own sequence.

`reset_on_target_change` makes one window reset. It is a property of the declaration, in all four places
(ruling 33), default off in each:

| Where | Written as |
|---|---|
| `sequence` line | `reset_on_target_change=1` in the first token |
| `strict_sequence` line | the same |
| `actions.windows` entry | `window,name=x,duration=...,reset_on_target_change=1` |
| Lua window | `reset_on_target_change = true` in the `RegisterWindow` table (Engine/Schema/Spec.lua:434); checked there to be a boolean or nil |

What the reset does: `Obs.TargetSwap` closes the window's row in the belief. One rule in Families/Windows.lua for
every row that has the property, whatever declared it.
- An APL-led window is level, so nothing more is needed: a plain sequence whose condition still holds opens again
  at step 1 on the next pass (a parked one too); a free-form window opens again if an open line is true; a strict
  sequence opens again when its line is next chosen.
- A Lua window is edge-driven, so the swap also forgets the evaluator's last value. An evaluator that is still
  true then counts as a rise and opens the window again, at step 1, in the same Drain (the swap is folded before
  RunWindows). Without this a held-true evaluator would leave the window closed for the rest of the fight. This
  is a reading, listed in section 14.
- No shipped class sets the field in 0.9. `weave` and `riposte` stay as they are.

`Obs.TargetSwap` is staged on PLAYER_TARGET_CHANGED and already works under the Map restriction by plate index when
the GUID is secret (Game/State/Sources/Target.lua:3, 23, 104, 132; swap serial at 58). No GUID is read. Re-selecting
the same enemy counts as a change.

## 9. Compile-time registration

- One compiler, in the addon: `scripts:LoadScripts` (Engine/Sim/Scripts.lua:1737-1772) runs at login and after every
  edit for every pack of the class. The build tools (tools/wowsims/apl.lua, tools/make_pack.lua) only write
  `sequence` / `strict_sequence` lines, and where a pack wants one, the `windows` list, into the .simc.
- Order: read the `windows` list; collect sequence lines; check E1-E7; make the keys; generate the lines and
  hidden lists.
- Keys: `<pack key>:<name>#<display>`, for each list-declared window in each of the five displays, and for each
  sequence in each display that has Sequences on (two per sequence with the defaults). Generated
  sequence lines are marked for the filter exception (section 7). Saved priorities, the editor, export strings, debug lines (Core.lua:569) and snapshots
  use plain names; a key is never saved. Two priorities may both declare `burst`; their keys differ by pack.
- Syntax: SimC's `strict_sequence,name=x:a,if=...:b` has commas inside colon-separated members;
  `Hekili:ParseActionList` (Options/Options.lua:8492) splits on commas. Parser work. The `window` entry is ordinary
  comma syntax.
- `knownWindow` (Options.lua:8485-8491, used at 8611) must accept names the priority declares, or import disables
  those lines; it is also where E1 and E3 are raised.
- The editor shows `windows` as a named list like `precombat`; it cannot be renamed, deleted while lines use it,
  or called. Its fields are in section 12, Phase 5.
- `mode=` is a core matter only (which lines are generated and how the due member's line is judged); the belief
  record does not carry it.
- Imports (ruling 13): a pasted priority is kept as written. Nothing is added to a sequence line, whatever its
  source; an unwritten option is SimC's behaviour. `wait_on_ready` is already a known entry field, marked not
  implemented (Options/Options.lua:237); it becomes real for `sequence` entries only, as the alias of `mode=wait`,
  and an imported line keeps it as written.
- Members must be abilities the belief tracks (Spec.lua:461; Schema/Tracked.lua:400-410). Items, `potion`, trinket
  slots, pet commands, `wait`: rejected at parse with a warning. An unlearned member is dropped when applied.
- No rebuild: belief windows are built only at SpecializationChanged (Tracked.lua:437-442). Follow
  `Hekili:CdmSwitchChanged` (Tracked.lua:427-435): LoadScripts writes the active pack's window records (key,
  duration (a sequence's: `combat`; OPEN carries none, v6.1), refresh, caps, steps, strict, `allow_skip`,
  `reset_on_target_change`, `step_timeout`, `on_deviation`: `"end"` on a strict sequence's record, none on a plain
  one, L1181) into `def.aplWindows`, bumps a generation, and the belief rebuilds only those rows and the operations buffer at its next Drain out of combat, else at combat
  end; in combat the one exception is a belief with no APL window yet (a /reload in combat, an in-combat switch from a
  pack without windows), which applies the new set at once (owner, L1226). `state:BuildWindows` (State.lua:1662) re-runs with it.
- Edits or pack switches in combat apply at combat end, except onto a belief with no APL window yet (L1226); until then an unknown key reads "down"
  (Families/Now.lua:538-541 in the belief; `VS.Window` already returns false for an unknown name, Windows.lua:193-198)
  and its operations are dropped and counted.

## 10. The translator: wowsims behaviour, written out

Ruling 14: the wowsims translator (tools/wowsims/apl.lua) does not rely on defaults. Every sequence it writes
carries the wowsims settings. Nothing else in the build writes them, and no shipped pack needs a `windows` list.

| wowsims node | Line written | Options always written | Never written |
|---|---|---|---|
| `strictSequence` (rule 14, apl.lua:170-186, 1783-1870) | one `strict_sequence` line at its list position, in place of the `prev.1` chain | `name=<generated>`, `start_on_first=1`, `hold_off_gcd=1` | `allow_skip`, `step_timeout`, `reset_on_target_change` |
| `sequence` (rule 14b, apl.lua:1402, 1905-1964) | one `sequence` line at its list position, plus reader lines where rule 19 places a member elsewhere | `name=<snake of its name>`, `mode=continue` | `wait_on_ready`, `reset_on_target_change` |
| `resetSequence` | `restart_sequence,name=<n>,if=<its condition>` | | |
| `sequenceIsComplete` | `window.<n>.done` | | |
| `move` / `wait` members of a sequence | no step and no line; their gate goes into the next cast member's own `if=` (rule 19, decision 9, as today) | | |

### 10.1 Strict sequences: 18 lines in nine packs

Generated strict names are `<first member>_<last member>`, unique in every shipped pack. The form of a line:

```
actions+=/strict_sequence,name=battle_stance_overpower,start_on_first=1,hold_off_gcd=1,if=<the sequence's condition>:battle_stance,use_off_gcd=1:overpower,focus=1,if=<overpower's own condition>
```

18 lines, 8 shapes. Each gets exactly `start_on_first=1,hold_off_gcd=1` and its name; conditions and member
options are the ones the `prev.1` chain carries today.

| Pack | List | `name=` | Members | Lines |
|---|---|---|---|---|
| Rogue Assassination, Combat, Subtlety (each) | default | `blood_fury_blade_flurry` | blood_fury (use_off_gcd=1) : blade_flurry | 3 |
| | default | `blood_fury_adrenaline_rush` | blood_fury (use_off_gcd=1) : adrenaline_rush | 3 |
| | default | `elunes_light_adrenaline_rush` | elunes_light (use_off_gcd=1) : adrenaline_rush | 3 |
| Mage Arcane | default | `presence_of_mind_arcane_wrath` | presence_of_mind (use_off_gcd=1) : arcane_wrath | 1 |
| Mage Arcane, Fire, Frostfire (each) | evocation | `read_ley_line_evocation` | read_ley_line : evocation (Frostfire: focus=2) | 3 |
| Priest Shadow | default | `inner_focus_mind_flay` | inner_focus : mind_flay | 1 |
| Warrior Arms | default | `battle_stance_overpower` | battle_stance (use_off_gcd=1) : overpower (focus=1) | 1 |
| Warrior Arms | default | `battle_stance_rend` | battle_stance (use_off_gcd=1) : rend (focus=2) | 1 |
| Warrior Fury | default | `battle_stance_rend` | battle_stance (use_off_gcd=1, focus=1) : rend (focus=2) | 1 |
| Warrior Fury | overpower_weaving | `battle_stance_overpower` | battle_stance (use_off_gcd=1, focus=1) : overpower (focus=1) | 1 |

- With the two options the lines behave as wowsims does, so the Phase 3 probe and the floors are about the move
  from `prev.1` chains to windows, not about the SimC defaults.
- Without them (a hand-written or SimC line) the same sequence would start only when both members can be cast and
  would let `use_off_gcd=1` lines through.
- Two sequences sharing a first member are told apart by which line was chosen, so rule 14's residual-terms
  workaround (apl.lua:177-182) goes.
- Not modelled: wowsims lets a major cooldown go ahead of a step queued behind a hardcast (seq.go:274-287).
  `hold_off_gcd=1` holds it. Phase 3 will show whether it matters.
- The Warrior class file gains `sequence_ignore = { "form" }` on Overpower and `sequence_ignore = { "nobuff" }` on
  Rend (ruling 36). The shipped lines carry `start_on_first=1`, so the fields do nothing for them; they exist so
  that the same lines with the flag removed (Phase 3's arm, a hand-written SimC-style line) can start.
- With ruling 25 the lines that begin with a cooldown (blood_fury, elunes_light, presence_of_mind, inner_focus)
  start in Primary and AOE for players who show Cooldowns separately.

### 10.2 Hunter `hha` (ruling 32)

wowsims (ui/specs/hunter/dps/apls/default.apl.siml:26-27):

```
reset_sequence("HHA") if hawk_and_arcane and sequence("HHA").is_complete
sequence "HHA" [cast summon_hawk, cast summon_hawk, cast arcane_shot] if hawk_and_arcane
```

Today (0.8.5): the class registers a looping Lua window (Hekili_Hunter/Hunter.lua:832, evaluator `combat > 0`,
`duration = "combat"`, `loop = true`), the pack has the header line `# Window: hha: ...`, and the members are
in-place lines: `summon_hawk,if=window.hha.next.summon_hawk` (pack line 43) and three range-gated `arcane_shot`
lines at different list positions (44, 54, 64).

In Phase 3 the translator writes, in the Beast Mastery pack:

```
actions+=/restart_sequence,name=hha,if=window.hha.done
actions+=/sequence,name=hha,mode=continue:summon_hawk:summon_hawk:arcane_shot,if=target.outside8
...
actions+=/arcane_shot,if=window.hha.next.arcane_shot&toggle.movement&<the gate of today's line 54>
...
actions+=/arcane_shot,if=window.hha.next.arcane_shot&toggle.movement&<the gate of today's line 64>
```

- The two lines sit where line 43 sits today. The sequence has no `if=` (the pack folds `hawk_and_arcane` to
  true today, as the header's "evaluator true" shows); a bare sequence opens when reached.
- v5 said one sequence line cannot place `arcane_shot` at three positions. It does not have to: the member's own
  `if=` carries the first gate (today's line 44), and the other two stay ordinary reader lines at their positions
  (section 6). A cast of Arcane Shot advances the step whichever line showed it.
- In the same change: `RegisterWindow("hha", ...)` and the `# Window: hha` header are removed (otherwise E3), and
  rule 14b's `sequenceIsComplete` becomes `window.<n>.done`.
- What differs from the Lua window, and why the floors are re-measured: the loop restarts on the pass after the
  third cast is observed (up to one update later) instead of inside the belief at the cast; the sequence opens
  when its line is first reached at now, not at combat start; there is one `hha` per display with Sequences on
  (Primary and AOE), each advanced by the same casts; while parked nothing is due.

### 10.3 Paladin `move1` / `move2` (ruling 32)

wowsims (ui/specs/paladin/retribution/apls/default.apl.siml, group "Move to melee"):

```
sequence "move1" [move $melee_range, wait until spell(judgement).in_range, cast judgement, wait input_delay,
                  cast seal_of_command, wait until spell(holy_strike).in_range] if <cond1> and not sequence("move1").is_complete
sequence "move2" [move ..., wait until ..., cast judgement, wait input_delay, cast seal_of_righteousness,
                  wait until ...] if <cond2> and not sequence("move2").is_complete
```

Today: two Lua windows (Hekili_Paladin/Paladin.lua:812, 820), steps `judgement` then the seal, `duration =
"combat"`, `close_on_false`, the evaluator being the sequence's condition plus "in combat, before the fight's
first main-hand swing" (`combat > 0 and lastSwing(1) < combat`); member lines in the `move_to_melee` list (pack
lines 32-35); other lines read `window.move1.up|window.move2.up` as "the opener is running".

In Phase 3 the translator writes, in the Retribution pack's `move_to_melee` list:

```
actions.move_to_melee=sequence,name=move1,mode=continue,if=<cond1>&<before the first main-hand swing>&!window.move1.done:judgement,use_off_gcd=1,if=toggle.movement|action.judgement.in_range:seal_of_command,focus=1,if=talent.twist_of_light.enabled
actions.move_to_melee+=/close_window,name=move1,if=window.move1.up&!window.move1.done&!<before the first main-hand swing>
actions.move_to_melee+=/sequence,name=move2,mode=continue,if=<cond2>&...:judgement,...:seal_of_righteousness,...
actions.move_to_melee+=/close_window,name=move2,if=...
```

- The `move` and `wait` steps give no step, as today (rule 19): the belief advances steps on observed casts only,
  and a move is not one. Their gates are in the members' own conditions. Decided (ruling 35): "no move steps go into hekili".
- The evaluator's "before the first swing" term must be written as an APL condition. The close line replaces
  `close_on_false` for the case where the player reaches melee before finishing (Q12 allows a close line on a
  sequence); because the same term is in the sequence's condition, the closed sequence does not reopen.
- Readers of `window.move1.up|window.move2.up` become "in progress":
  `window.move1.up&!window.move1.done|window.move2.up&!window.move2.done` (pack lines 19-27), because a parked
  sequence stays up.
- `RegisterWindow("move1")`, `("move2")` and the two header lines are removed in the same change.
- The Holy Shock pack's "move to melee" sequences follow the same rule when a lane reaches them.

`weave` (Hunter) and `riposte` (Rogue) stay Lua windows: they follow observed game events, not a priority.

## 11. Diagrams to draw

1. Data flow. Boxes: Game, Belief (one Windows store whose rows are labelled by key: a few plain Lua names with an
   evaluator beside them, and groups such as `pack:burst#Primary`, `pack:burst#AOE`, `pack:burst#Cooldowns`), Core,
   five display passes, Priority, Compiler, Class file. Arrows: Game -> Belief (observed casts, target swaps); Class
   file -> Belief (Lua registration with evaluator); Priority -> Compiler -> Belief (records by key); each display
   pass -> Belief, one way, labelled "operations for my keys, in order: OPEN / CLOSE / STEP"; Belief ->
   each display pass, labelled "state of my keys, read at the start of the next pass". Note on the belief: "knows
   keys only: no displays, no lines". Mark the operations arrow as the only new crossing.
2. Operations replay (replaces v3's edge state machine). Two lanes on one time axis. Top lane, a display's pass at
   now: the copy seeded closed, then the walk with three marks, "line 1 true: OPEN", "restart", "line 9 true:
   CLOSE", "restart", "pass ends", and beside it the growing list [OPEN burst#Primary, CLOSE burst#Primary].
   Bottom lane, the belief: Drain N (cutoff T), then Drain N+1 drawn as a row of steps "Flush | replay operations
   stamped T | polls | fold newer observations | settle | Lua evaluators | deliver". An arrow carries the list from
   the top lane into the "replay" step. A small inset: the same list with an observed cast arriving during the pass,
   showing the cast folded after the replay.
3. In-pass restart. A list drawn top to bottom three times side by side (walk 1, 2, 3): `open_window` at the top,
   two reader lines in the middle, `close_window` at the bottom. Walk 1 stops at the top line (opens, tick mark,
   arrow back to the top). Walk 2 skips the ticked line, readers see "up", the bottom line closes (tick, arrow back).
   Walk 3 skips both ticked lines, readers see "down", the pass ends closed. Notes: time not advanced; a ticked line
   acts once per slot (ticks are cleared at the next slot); no cap, restarts are at most the number of window
   lines; a ready pick in the middle of walk 2 would end the pass with the window open.
4. A strict sequence's life on a timeline with update ticks every 0.2 s. Events: line chosen at now (pass N) ->
   OPEN sent under this display's key -> belief opens at Drain N+1 -> hold begins in that display -> player presses
   step 1 (observed cast, step advances, deadline restarts) -> step 2 shown -> pressed -> window closes, hold ends.
   Side branches: due step not castable (give-up CLOSE from the pass), other on-GCD cast (strict end), target change
   (only with `reset_on_target_change=1`), `step_timeout` (4 s), combat end. Label the start with both tests: default
   "every member castable now", `start_on_first=1` "first member due within the queue window". A second, shorter strip for a plain sequence: opens on its condition, drops an unready member (STEP) under the default `mode=skip`, ends parked with `done` true, then `restart_sequence` sending STEP 1.
5. Compile-time registration. Left: the priority text, with the `windows` list at the top (`window,name=burst,...`),
   an `open_window,name=burst,if=...` line and a `strict_sequence,name=opener:...` line. Middle: the compiler, drawn
   as steps: read the `windows` list; collect sequences; check (a red side box listing undeclared, duplicate, class
   name clash); make keys; generate lines and the hidden list. Right: a fan-out from `burst` to five keys
   (`pack:burst#Primary` ... `#Interrupts`), then the generation bump and the belief applying it out of combat or at
   combat end (at once in combat if it has no APL window yet). Below: export and the editor showing only plain names.

## 12. Phased plan

Phase 0, docs: fix design §3a lines 355-357 (the wowsims strict start at the pin is "first step ready", not "every
step"), and say there that SimC is the default reference (ruling 14); record v6 as the build reference; the
explainer page; draft the release notes (`windows` is a reserved list name; a display in a sequence can show
abilities outside its category; the Sequences setting).

Phase 1, belief: APL rows by key from `def.aplWindows`, the operations buffer and `WindowOp`, Drain order, the three
operations (CLOSE and STEP as writes, OPEN by the declared refresh rule, v6.1), park at the end of a plain
sequence, `reset_on_target_change` for every row that has it (APL rows and Lua windows, with the `RegisterWindow` field and its check), `step_timeout` (default 4 s),
RegisterWindow's steps-need-an-evaluator check (L773), the generation-bump apply, operation logging, counters
(applied, dropped).
- Tests (tests/Game/State/windows_spec.lua and neighbours): each operation on an open and on a closed window;
  a list replayed in order (OPEN, CLOSE ends closed; CLOSE, OPEN ends open); an operation and a cast in one Drain
  apply in time order even when the cast was logged first; OPEN on a window that expired after T; an OPEN on an
  open window refreshed by the declared rule and refused past `max_refresh` and at `max_duration`, asserted against
  the forecast == apply oracle (W05, W06, R09); unknown key dropped and counted; a cast advances
  every open key; a stray first-step cast does nothing; park and STEP 1; target swap with and without the reset
  under a secret GUID, on an APL row and on a Lua window (closed, then reopened by a still-true evaluator);
  deadline restart on advance, default and `step_timeout=`; apply deferred in combat; 1000 Drains and 1000
  operations allocate nothing; tests/Game/API/border_check_spec.lua accepts exactly the one new call; a log replay
  reproduces the window states.
- Gate: fast checks. The matrix runner and its test kit (section 13) are built here with the belief-only columns
  asserted first; the core columns join in Phase 2.

Phase 2, core and compiler: the reserved `windows` list, errors E1-E7, keys, sequence syntax in the parser with
the options of 3.3 (SimC defaults, `mode=`, the `wait_on_ready` alias, `step_timeout=`), generated lines and
hidden lists; the `done` read; per-display seeding by key; lines as commands with the per-slot fired mark on
open, close and restart lines; the uniform line form (E4 for Lua windows too, the line-level `duration=` /
`refresh=1` path removed); operations sent at now only; the restart with no cap and the restarts-per-slot count;
chosen detection with NOW_TOL; the per-display Sequences setting (keys only where on, sequence lines skipped where
off); the filter bypass for marked lines and, in Primary and AOE, the start line's separate-toggle bypass; the
hold, its `use_off_gcd=1` pass-through and `hold_off_gcd=1`; the three start tests, with the ability fields `sequence_ignore` and `sequence_ready` and the `ready()` accessor
(3.6; registration checks in Engine/Schema, the read in the core); give-up, the strict skip and
the three plain modes; the translator's rule 14 writing `start_on_first=1,hold_off_gcd=1` and rule 14b writing
`mode=continue` (a build-tool test asserts them on every line); nothing sent from the alternatives probe;
snapshot and debug lines (section 15). The shipped packs are not regenerated in this phase.
- Tests: the matrix's core columns; a true line at a recheck time sends nothing; a ready pick between open and
  close ends the pass open; restarts equal the number of lines that fired, in slot 1 and in slot 2; nested lists;
  a held-true open on an open window causes no restart and no operation; tests/Forever/driver_alloc_spec.lua.
- Gate, CPU (rulings 19, 20, 24): (a) every shipped pack's CPU ratio and flicker unchanged, since no shipped
  priority has a window line yet and the only new per-slot cost is the hold check and the mark reset; (b) three
  synthetic priorities from the matrix measured against the same priorities without their window lines: W09
  (flapping pair, two restarts per slot), R03 (chain of three) and W05 (held-true refresh), reported as CPU ratio
  and restarts per slot. The numbers are recorded; a ratio the controller finds too high is raised with the owner
  as a warning proposal, never fixed with a cap.

Phase 3, real-world tests (rulings 27, 32). Three conversions, each in its own lane, each measured against its
0.8.5 form on the same seeds: both accuracy numbers, flicker per minute, CPU ratio, operations per minute per key,
restarts per slot.
- Warrior Arms, strict: the new rule 14 against its `prev.1` chains. Extra count: first-member casts that found
  their window closed. Also run with Cooldowns shown separately. The lane adds `sequence_ignore` to Overpower (`{ "form" }`) and Rend
  (`{ "nobuff" }`) in the Warrior class file (ruling 36). One extra arm with `start_on_first=1` removed: with
  those fields the default start can pass out of Battle Stance, so the arm measures what ruling 27 asked for,
  starts per minute against the main arm and first presses that found the window closed. A second arm of the same
  kind, harness only and shipping nothing, on Rogue Combat's `blood_fury:blade_flurry`, whose members do not
  depend on each other and need no field.
- Hunter Beast Mastery, plain loop: `hha` as `sequence,mode=continue` + `restart_sequence,if=window.hha.done`
  (10.2), the Lua window removed. Extra counts: loops per minute against the Lua window's, and time spent parked.
- Paladin Retribution, plain once-per-fight: `move1` / `move2` as sequences with a close line (10.3), the Lua
  windows removed. Extra counts: fights where the opener ran, finished, or was closed by the first swing, against
  the Lua windows'.
- Floors are re-measured with each move and re-floored with the cause named (the move to an APL sequence). A lane
  whose numbers are worse than its 0.8.5 form does not merge; its trace goes to the controller.

Phase 4, rollout: Fury, Rogue x3, Mage x3, Shadow, only if the Arms probe is at least equal. Re-floor each with
the cause named.

Phase 5, editor and in game. The editor part is ruling 13, building on the 0.8.5 label and icon fields of the
Actions tab (Options/Options.lua, the entry fields near 6311-6450). Every parameter of the table in 3.3 has a
field:

| Entry kind | Fields on the Actions tab |
|---|---|
| `sequence` | Name; Steps (an ordered list, each step an ability with its own options and `if=`); Mode (skip / wait / continue); Reset on target change; `if=` |
| `strict_sequence` | Name; Steps; Allow skip; Start on first step; Hold off-GCD lines; Step timeout (seconds); Reset on target change; `if=` |
| `restart_sequence` | Sequence, picked from the priority's sequence names; `if=` |
| `window` (in the `windows` list) | Name; Duration (seconds or "combat"); Refresh; Max duration; Max refreshes; Reset on target change |
| `open_window`, `close_window` | Window, picked from the declared names (list, sequences, class windows); `if=`. Nothing else, for any kind of window |

- Every field shows its effective value. An unwritten flag shows unchecked with "default (SimC)" beside it; Mode
  shows "skip, default (SimC)"; Step timeout shows "4, default"; a generated name shows as the name. Editing a
  field writes the option; setting it back to the default removes it from the line, so an export stays as short as
  the import was.
- A line imported with `wait_on_ready=1` shows Mode = wait. Its text is kept until Mode is edited; then `mode=` is
  written and `wait_on_ready` removed.
- The translator's lines show their flags (`start_on_first`, `hold_off_gcd` checked; Mode = continue), which is
  how a player sees that a pack follows wowsims.
- A picker cannot produce E1; renaming a declaration renames its uses. For a class (Lua) window the picker shows
  the registration's length and reset setting read-only.
- The two ability fields are pack code, not priority text: the Actions tab does not edit them. Where a strict
  line has `start_on_first` unchecked and a later member's ability carries one, the step shows a read-only note
  ("start test ignores: form" / "start test: custom").
- The `windows` list shows as a named list like `precombat`; it cannot be renamed, deleted while lines use it, or
  called.

In game: the per-display Sequences setting and its defaults, a sequence that begins with a cooldown starting in
Primary with Cooldowns shown separately, the `windows` list, import and export with plain names and unchanged
option text, the same name in two priorities, edit in combat, spellbook change re-apply, the snapshot text with
restarts per slot, the three converted packs on an open-world mob.

Harness gates: the drift guard keeps its meaning for Lua windows. APL windows are excluded from it and get two
checks: after every Drain, each key's belief state equals the state the sending pass left in its copy (the replay
invariant, section 13), and no APL window is ever up without a logged OPEN.

## 13. Test matrix

Owner: "a comprehensive set of different apl variants to make sure that all permutations of this system can be unit
tested". The existing tests are hand-written `it()` blocks per layer; this adds one table-driven spec over small
fixture priorities.

### How a case is written

- Fixtures: `tests/Forever/fixtures/windows/<id>.simc` (proposed location), each a priority of 3-10 lines over a
  small test kit: `filler` (on-GCD, always ready), `nuke` (on-GCD, cooldown), `burst` (off-GCD, cooldown), `stance`
  (off-GCD, no cooldown), `dot` (on-GCD, target debuff), a test-kit Lua window `luaw` with an evaluator reading a
  test flag, and one class cooldown that the Cooldowns display owns.
- Timeline: a Lua table beside the fixture. Each entry is a tick (0.2 s apart unless stated) with optional scripted
  events before it: `cast=<key>`, `flag=<name>:<bool>`, `target_swap`, `combat=start|end`, `display=<name>:on|off`,
  `edit=<fixture id>`, `cd=<key>:<seconds>`.
- Asserted at every tick, for every display that is on (unlisted fields must be unchanged from the previous tick,
  so a surprise fails):
  1. belief, per key: `up`, `step`, `expiresAt`;
  2. operations sent by this tick's pass, per display, as an ordered list (`OPEN burst`, `CLOSE burst`);
  3. forecast copy after each asserted slot: per window `up`, `step`; restarts in that slot (slot 1 always; later
     slots where the case names them);
  4. published records: slot 1 action and whether it is ready; slot 2 where the case is about the queue.
- Replay invariant, checked by the runner on every case and every tick, not written per case: after the next
  Drain, the belief's state for each key equals the copy's state at the end of the slot-1 now walk that sent the
  operations, except where a scripted cast, target swap or expiry falls in between (then the case lists the
  expected difference). One named carve-out (L1180): OP5, a window that runs out between the stamp and the pass's
  now, where the copy opened it fresh and the belief judged the OPEN as still open (5.4).
- Compile cases have no timeline: they assert the error list (code and line) and which lines are disabled.
- One runner (`tests/Forever/windows_matrix_spec.lua`, proposed) loads each fixture into the headless engine plus
  belief, plays the timeline, and prints the first differing tick as a row diff.
- Allocation: every case runs its timeline a second time after warm-up under the allocation counter used by
  tests/Forever/driver_alloc_spec.lua and must allocate nothing in Drain, `WindowOp`, the walk and the restart. Cases
  that apply a new window set (L group) are exempt only at the apply tick.

### Axes

| Axis | Values |
|---|---|
| A window kind | Lua-led, APL-led (list-declared), APL-led (sequence) |
| B declaration | valid; undeclared; duplicate in the list; list entry and sequence share a name; clash with a class name; an attribute on a line naming an APL window; an attribute on a line naming a Lua window; wrong entry in the list; `window` outside the list; bad duration |
| C declared settings | plain; `refresh=1`; `refresh=1,max_refresh=`; `refresh=1,max_duration=`; `duration=combat` |
| D lines on one window | open only; open + close; two opens; two opens + close; close only |
| E order | open above close; close above open; open, close, open |
| F condition shape over time | true once; held true; toggling every tick; true only at a recheck time |
| G what sits between | nothing; a reader line; a ready pick (early exit); a `call_action_list` whose condition is false |
| H restart chain | 0; 1; 2; 5; every window line of a 12-line priority firing; inside a nested list |
| I sequence kind | none, plain, strict |
| J options, each unwritten (SimC) and written | `mode=` skip / wait / continue and the `wait_on_ready=1` alias; `allow_skip`; `start_on_first`; `hold_off_gcd`; `step_timeout=`; `reset_on_target_change` (sequence, list declaration, Lua field); `name=` given or defaulted; the ability fields `sequence_ignore` (each gate) and `sequence_ready` |
| K press timing | normal (after the open is replayed); within the same Drain as the operation; before the line is chosen; first and second member in one frame (macro) |
| L displays and keys | Primary only; two displays with different conditions; Cooldowns separate; display toggled mid-fight |
| M lifecycle | precombat; combat start; combat end; edit in combat; pack switch; spec switch |
| N target | no swap; swap with a plain GUID; swap under Map (plate index); `cycle_targets` on a member |
| O naming | plain; same plain name in two priorities; export/import round trip |
| Q slot | slot 1 (sends); slot 2 and later (copy only, fired mark cleared) |

Removed since v5: the restart-cap values of axis H ("equal to the cap", "over the cap") and case R04; the
`wait_on_ready` meaning "list continues". Removed since v3: `close_on_false`, the reach axis as an edge input, the
armed and re-arm cases, the Lua twin mirror.

### Reduction

- Exhaustive blocks (every combination):
  1. C x F for one open line: 5 x 4 = 20 cases. Level semantics, refresh and caps, reopen after expiry.
  2. D x E x G where the combination exists (open + close and two opens + close have orders; the others do not):
     (2 x 3 + 3) x 4 = 36 cases. Operation order and the end state of the pass.
  3. H x Q: 6 x 2 = 12 cases. Restart count equals the lines that fired; the per-slot mark; slot 2 sends nothing
     and its lines fire again.
  4. B: 10 values x {editor load, import} = 20 compile cases.
  5. I(strict) x J(start_on_first, hold_off_gcd, allow_skip) x K: 2 x 2 x 2 x 4 = 32 cases; I(plain) x
     J(mode: skip, wait, continue) x K: 3 x 4 = 12 cases. Every option value appears against every press timing.
  6. {plain, strict, list-declared window, Lua window} x reset_on_target_change x N: 4 x 2 x 4 = 32 cases.
- Pairwise for everything else: each remaining pair of axis values appears in at least one case (L and M against
  A, C, D, I; O against A and I; `step_timeout` against K). About 30 more cases.
- Contrast pair instead of a mirror: one fixture runs the same flag through `luaw` (edge) and an APL window (level)
  and asserts where they must differ: held true after expiry (Lua stays closed, APL reopens) and a fall (Lua with
  `close_on_false` closes, APL stays until a close line or expiry).

About 212 fixtures (v5 had about 190; the third mode, the Lua reset, the Lua-line compile case and the ability
fields add 21). The
named cases below must exist whatever the reduction produces. Fixtures for sequences come in two families, named
in the file: `simc-*` write no option and so test the defaults, `wowsims-*` carry the translator's flags. Every
option has at least one pair of fixtures that differ only in that option (group P).

### Named cases

Group C, compile (no timeline):

| id | Priority shape | What it proves |
|---|---|---|
| C01 | `open_window,name=x`, no declaration | E1; line disabled; rest of the priority loads |
| C02 | two `window,name=x` entries | E2 on the second |
| C03 | `window,name=x` and `sequence,name=x:...` | E2 |
| C04 | `window,name=luaw` (a class window) | E3; lines naming `luaw` stay forecast-only on the class window |
| C05 | `open_window,name=x,duration=3` on a list-declared window, on a sequence and on the class window `luaw` | E4, three times (ruling 21) |
| C11 | a priority with an ordinary list named `windows` holding `filler` | E5 on each entry (ruling 22); the rest loads |
| C06 | `filler` inside the `windows` list; `window,name=y` in `default`; `call_action_list,name=windows` | E5, three times |
| C07 | `window,name=x` with no duration; `duration=0`; `max_refresh=-1` | E6 |
| C08 | a SimC import with sequences and no `windows` list | no error; sequences self-declare |
| C09 | valid list, two windows, five displays | ten keys, each `<pack>:<name>#<display>`; none in the saved pack or export |
| C10 | every shipped pack | compiles with no window error (build gate) |

Group W, free-form windows (unit only unless marked):

| id | Priority shape | What it proves |
|---|---|---|
| W01 | bare `open_window`, reached every tick, duration 3 | OPEN on the first pass; nothing while open; OPEN again on the pass after expiry (level) |
| W02 | `open_window,if=flag`, flag true for one tick | one OPEN; stays open to its duration after the flag falls |
| W03 | W02 with a `close_window,if=!flag` line | CLOSE on the tick the flag falls: the author's replacement for close_on_false |
| W04 | open line inside a list whose call goes false | no operation while not reached; window runs to its duration |
| W05 | declared `refresh=1`, flag held true | the timer restarts every pass (OPEN, belief and forecast agree); with `max_refresh=2` the third is refused and nothing is sent |
| W06 | declared `refresh=1,max_duration=8` | span capped from the first open; at the cap the refresh is refused and nothing is sent |
| W07 | `duration=combat` | no expiry; closes at combat end; reopens next fight only by a line |
| W08 | two open lines for one window, both true | one OPEN, from the upper line; the lower finds it open |
| W09 | open top, close bottom, both true (the owner's example) | operations OPEN, CLOSE; two restarts; ends closed in copy and belief; same again next tick |
| W10 | close top, open bottom, both true | walk 1 opens, walk 2 closes, walk 3 both marked: OPEN, CLOSE; ends closed |
| W11 | open, close, open (three lines, all true) | the second open fires in walk 3: OPEN, CLOSE, OPEN; ends open |
| W12 | W09 with a ready `filler` between the lines | walk 2 ends at `filler`; only OPEN is sent; window stays open |
| W13 | open line true only at a recheck time (+0.5 s) | copy opens future-dated, a reader gets a countdown, nothing sent, belief closed |
| W14 | open line true only at slot 2's time | copy opens in slot 2; nothing sent |
| W15 | display off for five ticks while the flag toggles | nothing sent; the open window ends by its duration |
| W16 | Lua window `luaw` with an `open_window,name=luaw,if=flag` line | forecast-only, with the registered duration; nothing sent; belief follows the evaluator; drift guard counts it |
| W17 | real cast whose `now()` calls `closeWindow` on an APL key, open line held true | closes in the fold; the next pass sends OPEN again (level; documents it) |
| W18 | contrast pair: `luaw` and an APL window on the same flag | they differ exactly where edge and level differ |
| W19 | open line below an early-exit pick that alternates ready / not ready | line acts only on passes that reach it; no state is kept about the others (harness too) |

Group R, restart and the fired mark (unit only). There are no cap tests: there is no cap.

| id | Priority shape | What it proves |
|---|---|---|
| R01 | reader on top, open at bottom | slot 1 is the reader; one restart; next tick zero restarts and no operation (window already open) |
| R02 | open on top, reader below | one restart (the copy changed), the reader is picked on walk 2 |
| R03 | chain: three windows, each opened by a line reading the previous | three restarts; three OPENs in chain order |
| R04 | a 12-line priority in which every one of its 8 window lines fires in one slot | exactly 8 restarts, 8 operations, nothing truncated; the snapshot shows "restarts: 8"; same result every run |
| R05 | open line inside a called list, reader in the caller above the call | restart unwinds the nested list |
| R06 | two lines whose conditions read each other's window (`open A if !B`, `open B if !A`, with closes) | ends within the fired-mark bound (at most 4 restarts); deterministic end state asserted |
| R07 | R01 with a near-cost pick held before the restart | `state.nearAction` cleared; pick is the reader |
| R08 | W09 run 1000 ticks | no allocation; two operations and two restarts in slot 1 per tick, constant |
| R09 | a refresh granted on a held-true line | one restart per slot while refreshes remain; none after `max_refresh` |
| R10 | W09, slots 1 to 3 asserted | each slot: the mark is clear at its start, the pair fires again (open, close, two restarts), the copy ends closed; only slot 1's two operations are sent |
| R11 | `open_window,if=flag` where the flag's forecast turns true at slot 2's time; a `close_window` true at slot 3's time | slot 1: closed, nothing sent; slot 2: the copy opens, readers see it up; slot 3: the copy closes. The forecast models the window opening and closing (ruling 20) |
| R12 | a line that fired in slot 1 and whose condition is still true in slot 2, window closed again by an expiry between the slots | it fires again in slot 2 (copy only). Under the old per-cycle mark it would not |
| R13 | restart counts in the snapshot and debug text during R03 and R10 | "restarts: 3" for the slot; per-slot counts listed; plain names |

Group S, sequences (unit; marked ones also harness):

| id | Shape and timeline | What it proves |
|---|---|---|
| S01 | strict `burst:nuke`, pressed in order, normal timing | chosen: OPEN after slot 1 is final; belief opens next Drain; hold; step 2; closes after the last |
| S02 | S01, a filler line above becomes ready while open | hold: slot 1 stays the due member |
| S03 | S01 with an outside `burst2,use_off_gcd=1` line; unwritten, then `hold_off_gcd=1` | shown, then hidden |
| S04 | S01, `nuke` put on cooldown after open | give-up CLOSE; the normal list answers in the same walk |
| S05 | default start with `nuke` on cooldown | line never chosen; nothing sent |
| S06 | S01, `filler` cast after step 1 | strict deviation closes (belief rule, no operation) |
| S07 | S01, `burst` cast again (off-GCD, not due) after step 1 | stays open |
| S08 | S01, nothing pressed | `step_timeout` closes at 4 s; chosen again on the next pass: OPEN again (level; the latch repeats) |
| S09 | S01, `burst` cast in the same Drain as the OPEN, cast logged first | advances (operations before the fold). Harness |
| S10 | S01, `burst` cast one tick before the line is ever chosen | no window; step 2 not shown by the sequence. Harness: risk 15.6's count |
| S11 | S01 with `stance:nuke`, both casts in one frame | open, advance twice, close in one Drain. Harness |
| S12 | `start_on_first=1`, line due in 0.3 s (inside NOW_TOL) and in 0.6 s (outside) | OPEN at 0.3, nothing at 0.6. Unwritten: nothing at either |
| S13 | two strict sequences sharing `burst` | only the chosen one's key gets OPEN |
| S14 | plain `filler:nuke:dot`, `mode=continue`, `nuke` on cooldown at step 2 | stays at step 2; list continues below; no STEP. With `mode=wait`: stays, `nuke` is slot 1 with its countdown, nothing below is shown |
| S15 | S14 unwritten (the default) | STEP 3 sent once; belief at step 3; `nuke` is not offered again |
| S16 | S15 with `nuke` and `dot` both unready | STEP 4: parked, `done` true (SimC runs off the end) |
| S17 | plain sequence finished, condition still true | parked: up, step 4, `done` true, no member due, no OPEN sent |
| S18 | S17 then `restart_sequence,if=flag` true for one tick | STEP 1; sequence runs again |
| S19 | `restart_sequence` held true | STEP 1 on every pass where the step is not 1 (documents level) |
| S20 | plain and strict, target swap mid-way, unwritten and `reset_on_target_change=1`, plain GUID and Map | unwritten keeps the step; the flag closes (plain: not parked, reopens at step 1 if its condition holds) |
| S21 | a member with `cycle_targets=1` and a swap made to follow it | unwritten: the sequence carries on to its next member (the reason for ruling 16). With the flag: closed by the swap its own line asked for |
| S22 | combat ends at step 2; a parked sequence at combat end | both closed; next fight starts fresh |
| S23 | strict sequence in `precombat`, combat starts at step 2 | stays open across combat start; hold applies in precombat's walk |
| S24 | `close_window,name=<strict sequence>` true at step 2 | CLOSE; hold ends in the same pass after the restart |

Group D, displays and keys (unit; D02 also harness):

| id | Shape | What it proves |
|---|---|---|
| D01 | Primary and AOE both on, flag true for one target count only | OPEN under one display's key only; the other key stays closed; each display reads its own |
| D02 | Cooldowns separate, AOE on, a `sequences` value stored for Cooldowns by an older profile; strict `classcd:nuke`, and plain `classcd:filler` | Primary and AOE start it through ruling 25 (D14): OPEN on each key, two holds, one cast advances both (D11), `nuke` / `filler` shown at step 2; Cooldowns sends nothing, has no key and shows no member |
| D03 | display turned off at step 2, on again later | its key advanced by casts meanwhile; no stale hold beyond the deadline |
| D04 | one cast with the sequence open under several keys (the core makes two, Primary and AOE; the belief matrix uses three) | all advance |
| D05 | the belief's API and log during D01 | only key strings appear; no display number, no line number (the ruling-1 check) |
| D06 | D14 after the window closes (the last step, a give-up or a `close_window` line) | window closed: `classcd` is hidden from Primary again by the separate-toggle test on the next pass |
| D07 | Cooldowns separate; strict `nuke:classcd` chosen in Primary | Primary shows `classcd` at step 2 (the separate-toggle test bypassed); Cooldowns may show it too through its normal list |
| D08 | D07 with the cooldowns toggle switched off | `classcd` stays disabled; give-up CLOSE; no bypass of an off toggle |
| D10 | a non-generated `burst2,use_off_gcd=1` line the display filters (a separated cooldown in Primary), walked while the window is up (default hold) | still filtered: the exception is for marked lines only |
| D11 | Primary and AOE both choose the same strict sequence | two keys open, two independent holds; one cast advances both |
| D12 | a fresh profile, one sequence and one list-declared window; and a `sequences` value stored for the other three | Sequences on for Primary and AOE; two sequence keys, five window keys; the stored values add no key |
| D13 | Cooldowns separate, strict `nuke:classcd` | runs in Primary; Cooldowns' pass skips the line (no evaluation, no key, no hold) and recommends as today |
| D14 | Cooldowns separate, strict `classcd:nuke` | starts in Primary: the start line skips the separate-toggle test (ruling 25) and `classcd` is shown there; Cooldowns' pass skips the line |
| D15 | Cooldowns (no sequences there); `open_window,name=burst` reached there | free-form window still opens under Cooldowns' key |
| D16 | Sequences off in a display; `restart_sequence`, `close_window,name=<seq>`, a reader of `window.<seq>.up` | the two lines are skipped; the reader sees false |
| D17 | Primary's setting switched on in combat, and off out of combat | on: the key at once in the compile, the belief's row at combat end; off: key and row removed at once, an open sequence there is gone |
| D18 | D14 with the cooldowns toggle switched off | never chosen: an off toggle is not bypassed |
| D19 | Cooldowns separate, plain `classcd:filler`, and AOE on | `classcd` is shown in Primary and in AOE as the due first member; each display's key opens and advances on the one cast |

Group P, option pairs: each case is a set of fixtures that differ in one option only (unit only; P18 is a
build-tool test):

| id | Shape | Unwritten (SimC) | Written |
|---|---|---|---|
| P01 | plain `filler:nuke:dot`, `nuke` unready at step 2; `mode` | skip: STEP 3; `nuke` is dropped for this run | `wait`: stays at step 2, slot 1 is `nuke` with its countdown, a ready `filler2` line below is not recommended, a line above still is. `continue`: stays at step 2, `filler2` below is recommended, `nuke` is shown once ready |
| P02 | P01 with `nuke` short of its resource for one tick only | STEP 3 on that tick (documents how sharp the default is) | `wait`, `continue`: no STEP |
| P03 | plain, the due member is on-GCD and the GCD is running, otherwise ready | no STEP: "ready" is judged for the end of the GCD (ruling 28) | same in every mode |
| P04 | strict `burst:nuke`, `nuke` on cooldown; `start_on_first` | never chosen | chosen; at step 2 the give-up CLOSE |
| P05 | strict, both castable, GCD ends in 0.3 s; `start_on_first` | nothing until the GCD is ready (delay 0, no tolerance), then OPEN | OPEN at once (inside the queue window) |
| P06 | strict open, outside line `burst2,use_off_gcd=1` ready; `hold_off_gcd` | `burst2` shown | not shown |
| P07 | P06 with an outside zero-GCD line that lacks `use_off_gcd=1` | held | held |
| P08 | strict `burst:nuke:dot`, `nuke` goes on cooldown at step 2; `allow_skip` | give-up CLOSE | STEP 3, `dot` shown; none castable: CLOSE |
| P09 | strict `burst:nuke`, only `nuke` castable; `allow_skip` | never chosen | chosen, opens at step 2 |
| P10 | `allow_skip=1` with `start_on_first=1` | n/a | starts on the first member within the queue window; skips after that |
| P11 | plain, strict, parked plain and a list-declared window, target swap; `reset_on_target_change` | nothing changes | closed; plain reopens at step 1 if its condition holds; the declared window reopens only by a line |
| P12 | P11's swap with a Lua window `luaw` open at step 2, evaluator still true; the `RegisterWindow` field | unchanged, step 2 | closed by the swap and reopened at step 1 in the same Drain; with the evaluator false at the swap: stays closed. Under Map (plate index) too |
| P13 | the HHA shape: `restart_sequence,name=x,if=window.x.done` above `sequence,name=x:a:b:c` | runs a, b, c, parks, then STEP 1 and a is due again in that pass; three loops asserted | same with `mode=continue` |
| P14 | `window.x.done` on a strict sequence, a closed plain one, a free-form window and a parked one | false, false, false, true | |
| P15 | unnamed `sequence:a:b` with a bare `restart_sequence` | both are `default` | `name=x` on both: the same |
| P16 | two unnamed plain sequences and an unnamed strict one | `default`, `default_2`, `strict_1`; stable across reload and export | |
| P17 | a line carrying `unready=skip`, `start=all`, `off_gcd=allow` or `target_change=end`; `mode=hold`; `mode=wait` on a strict line; `wait_on_ready=1` on a strict line; `mode=continue,wait_on_ready=1`; `step_timeout=2` on a plain line | E7 each, line disabled | |
| P18 | the translator run on every recipe | every `strict_sequence` carries a name, `start_on_first=1` and `hold_off_gcd=1`; every `sequence` a name and `mode=continue`; none carries `allow_skip`, `wait_on_ready`, `step_timeout` or `reset_on_target_change`; 18 strict lines in nine packs | |
| P19 | a SimC text with `sequence,name=opener:a:b`, `sequence,name=w,wait_on_ready=1:a:b` and `strict_sequence,name=burst:c:d` imported, exported | the lines come back byte for byte; nothing added (ruling 13); behaviour is P01's and P04's unwritten column, and P01's `wait` column for `w` | |
| P20 | the editor's view of P19's lines and of a translator line | every field of section 12's table shown with its effective value; unwritten flags unchecked "default (SimC)"; Mode "skip, default (SimC)", "wait" for the alias line, "continue" for the translator's; Step timeout "4, default"; checking and unchecking a flag leaves the text as it was | |
| P21 | plain default, due member unready, the sequence's `if=` false for three ticks, then true | no STEP while the line is inactive (ruling 28: an inactive line skips nothing) | STEP on the first tick it is active |
| P22 | plain default, `nuke` dropped at step 2, ready again two ticks later; then `restart_sequence`; then a new fight | not offered again in this run | offered again after the restart, and after combat end and a new start |
| P23 | plain default `filler:nuke:dot` at step 2 with `nuke` and `dot` both uncastable, and with only `nuke` uncastable | both: STEP 4, burnt out, `done` true. One: STEP 3, not burnt out | |
| P24 | `sequence,name=x,wait_on_ready=1:a:b` beside `sequence,name=y,mode=wait:a:b` on the same timeline | identical behaviour, tick for tick | |
| P25 | strict `burst:nuke`, nothing pressed; `step_timeout` | closes at 4.0 s; pressed at 3 s: the timer restarts, closes at 7.0 s | `step_timeout=2`: closes at 2.0 s. `step_timeout=0`: E6 |
| P26 | `open_window,name=luaw,if=flag` and `open_window,name=luaw,duration=3,if=flag` | first: the copy opens with the registered duration, one restart, nothing sent, the belief follows the evaluator | second: E4, line disabled (ruling 21) |
| P27 | `open_window,name=burst,refresh=1` and `close_window,name=burst,duration=1` on a list-declared window | E4 each | |
| P28 | strict `stance:nuke`, default start; `nuke` gated in turn by `form`, `noform`, `buff`, `nobuff`, the gate failing until `stance` is cast; `sequence_ignore` naming that gate (four fixture pairs) | no field: never chosen | field: chosen with every other test passing; a second gate that is not named still blocks |
| P29 | P28 (`form`), `nuke` also on cooldown | never chosen | never chosen: only the named gate is skipped |
| P30 | strict `stance:nuke`, `nuke` with `sequence_ready` returning a test flag and never calling `ready()`; `nuke` on cooldown | n/a | chosen exactly when the flag is true, cooldown or not (a replacement); the member's own `if=` false still blocks |
| P31 | P28 (`form`) with `sequence_ready = function() return ready() and flag end` | n/a | chosen only when the gate-skipped normal test passes and the flag is true; flag true with `nuke` on cooldown: not chosen |
| P32 | P28 to P31 with `start_on_first=1` on the line | chosen on the first member within the queue window | identical with and without the fields; `sequence_ready` is never called |
| P33 | strict `nuke:filler` where `nuke`, the first member, has `sequence_ignore = { "form" }` and its form is missing; and `sequence_ready` returning true on it | never chosen: the first member uses normal readiness; the handler is not called | |
| P34 | P28 (`form`) chosen and open, then `stance` is cancelled before `nuke` is pressed; the same under `allow_skip=1` with a third member | give-up CLOSE (running steps use normal readiness: the real gate) | `allow_skip=1`: STEP past `nuke` by normal readiness |
| P35 | registration: `sequence_ignore = { "stance" }`, `sequence_ignore = "form"`, `sequence_ready = true` | each raises at load with the ability's name | |
| P36 | a plain sequence and an ordinary line using an ability that has both fields | no effect; the handler is not called | |

Group G, real-world gates (harness and replay; Phase 3):

| id | Pack | What is compared | Passes when |
|---|---|---|---|
| G01 | Warrior Arms, rule 14 as `strict_sequence` | the 0.8.5 `prev.1` chains, same seeds: both accuracy numbers, flicker per minute, CPU ratio, operations per minute per key, restarts per slot, first-member casts that found their window closed | at least equal on accuracy and flicker; CPU ratio within the Phase 2 gate; floors re-measured |
| G02 | G01 with Cooldowns shown separately | the same | the same; sequences run in Primary |
| G03 | G01 with `start_on_first=1` removed (ruling 27), Overpower and Rend carrying `sequence_ignore` (ruling 36) | starts per minute and first presses that found the window closed, against G01 | the sequences start (starts per minute within reach of G01's); the missed-press count is reported to the owner, who decides from it |
| G04 | Hunter Beast Mastery, `hha` as an APL sequence (10.2) | the 0.8.5 Lua window, same seeds: the numbers of G01 plus HHA loops per minute and time parked | at least equal; floors re-measured with the cause named |
| G05 | Paladin Retribution, `move1` / `move2` as APL sequences (10.3) | the 0.8.5 Lua windows, same seeds: the numbers of G01 plus openers run, finished, closed by the first swing | at least equal; floors re-measured with the cause named |
| G06 | the three converted packs | generated text | no `# Window:` header, no `RegisterWindow` for `hha`, `move1`, `move2`; every sequence line has `mode=continue`; C10 passes |
| G08 | Rogue Combat `blood_fury:blade_flurry` as a strict sequence, with and without `start_on_first=1`; harness only, nothing shipped | starts per minute and missed first presses, both arms | reported beside G03 |
| G07 | one recorded fight each of G01, G04, G05 | belief-only replay from the log, operations included | same window states at every tick, twice |

Group L, lifecycle, naming and replay (unit only):

| id | Shape | What it proves |
|---|---|---|
| L01-first | /reload in combat, or a switch in combat from a pack without windows | the belief has no APL window yet: the set applies at once, operations land, nothing dropped |
| L01 | edit in combat adds a window | reads "down", operations dropped and counted, applied at combat end, allocation only there |
| L02 | pack switch out of combat | old keys gone, new keys closed |
| L03 | spec switch | full rebuild; Lua windows per spec; no APL key survives |
| L04 | two priorities both declare `burst` | distinct keys; only the active pack's applied |
| L05 | export then import | plain names and the `windows` list in the string; identical behaviour on the W09 timeline |
| L06 | snapshot and debug text during W09 and S01 | plain names, per display: windows, operations in order with their line, restarts per slot; no key suffix shown to the user except in the belief section |
| L07 | unknown member (an item) and an unlearned member | parse warning and line disabled; unlearned dropped at apply |
| L08 | Lua `RegisterWindow` with steps and no evaluator | raises at load |
| L09 | border check | exactly the one new call accepted |
| L10 | belief-only replay of a recorded W09, W11 and S09 log | same window states at every tick; operations read from the log, in order, at the Drain head |
| L11 | the same recording replayed twice | identical (determinism) |

### Unit versus harness

- Unit only: groups C, W (except W19), R, L, P, D01, D03-D08, D10-D19, and S except S09-S11. They are deterministic rules.
  S01-S13 and S22-S24 are written twice where the start or the hold matters to them, as `simc-*` and `wowsims-*`.
- Also a harness loop or replay gate (the outcome depends on reaction time, update cadence and the simulated
  player): W19, S09, S10, S11, D02, and group G (Arms, `hha`, the Paladin moves). The harness reports first-member casts that found
  their window closed, operations per minute per key, and flicker per minute.
- Replay determinism: one recorded harness fight per group S is replayed through the belief alone from its log
  (operations included) and must end every tick in the same window states.

## 14. Nothing open; contradictions, readings, unchecked code

### 14.1 Open questions

None. Every question of v2-v5 (Q1-Q16) and every derived rule (D1-D8) has an owner ruling, listed in section 0.

### 14.2 Contradictions found

None open. The first issue of v6 listed two; the owner has ruled on both (L844, L845).

1. Paladin "sequences with move steps" (L836) against "a step is a cast". Ruled (35): "no move steps go into
   hekili". Sequences hold cast steps only; the translator keeps folding wowsims `move` and `wait` steps into the
   next cast's condition (rule 19). Section 10.3 is written that way.
2. The Arms arm without `start_on_first=1` (L832) could never start, because Overpower and Rend need what Battle
   Stance gives. Ruled (36): two ability fields for the strict start test, `sequence_ignore` and
   `sequence_ready` (3.6). Arms uses `sequence_ignore`; the arm now measures. Rogue Combat's
   `blood_fury:blade_flurry` stays as a second, harness-only arm (G08).
3. D02 (carried from v4) against ruling 25: 25 wins; the row is rewritten (Fable for the owner, ledger L1270). In
   v4/v5 Primary's separate-toggle test hid the cooldown, so Primary could not choose the line; ruling 25 removed
   that test for the start line. Cooldowns never sequences (L1315), so the row covers Primary and AOE.

Found while folding ruling 36 in: nothing that contradicts an earlier ruling. Two things were looked at:
- Ruling 5 ("explicit in the apl rather than having inherent knowledge packaged in the items") and ruling 36
  (fields on the ability). They do not collide: the fields describe the ability's own gates, they do nothing
  until a priority writes a strict line without `start_on_first=1`, and the core still knows no stance by name.
  It is worth one sentence in the author guide, because it is the one place where a sequence's behaviour depends
  on something that is not on its line.
- Ruling 28 (one meaning of "can be cast" for the start, the skip and the give-up) and ruling 36 (a different
  judgement in the start test only). Ruling 36 is the later one and says so in terms; 3.3's "one meaning" now has
  this one stated exception.

Checked and found consistent, for the record:
- Ruling 27 ("castable now, no tolerance") and ruling 28 ("ready at the moment the player can next act"): at
  delay 0 the two moments are the same (3.3).
- Ruling 20's ledger text says "+ the hard cap"; ruling 24 came later and drops the cap.
- Ruling 21 says "no shipped line changes" while v5 named the Hunter packs as shipped `open_window` users. The
  packs and recipes have no such line [H]; v5 was wrong, and Phase 2's gate is rewritten accordingly (section 12).
- Ruling 16 ("Lua-led windows unaffected") and ruling 33 (a Lua field): the field is off by default, so Lua
  windows are unaffected unless a class asks.
- Ruling 10 (off = no evaluation in that display) and ruling 25 (start in Primary / AOE): 25 applies only where
  Sequences is on.

### 14.3 Readings this document made

Small points the rulings imply but do not spell out. Each is the narrowest reading; none changes a ruling.
- L837 is recorded as a controller reading ("If the owner meant APL-only, flip"). The Lua field is one check in
  `RegisterWindow` and one property on the row; flipping means deleting the field.
- A Lua window's reset also forgets the evaluator's last value, so a still-true evaluator reopens it (section 8).
  Without it "reset" would mean "closed for the rest of the fight" for the common held-true evaluator.
- `step_timeout=` applies to `strict_sequence` only, as the per-step deadline did in v5; a non-positive value is
  E6. A plain sequence has no deadline.
- `mode=` together with `wait_on_ready` on one line is E7, rather than one silently winning.
- `mode=wait` leaves lines above the sequence line alone and stops the walk at the due member; that is "block the
  list below" (L829).
- A plain sequence's generated lines all sit under the sequence's condition, so a false `if=` shows nothing and
  skips nothing (ruling 28's "an inactive line skips nothing", SimC's rule).
- The strict give-up takes a per-slot mark like a line, so that "restarts are bounded by the number of window
  lines" holds for it too.
- Ruling 25 names Primary and AOE. Those are the displays the "toggle shown separately" test hides abilities
  from, and the only displays that sequence (L1315).
- In a display with Sequences off, `restart_sequence` and open or close lines naming a sequence are skipped, and
  `window.<sequence>.up` and `.done` read false (carried from v5, section 7).
- The `hha` conversion keeps Arcane Shot at its three list positions through reader lines (10.2) instead of
  merging the three gates into one member condition, so that the pack's order does not change.
- `sequence_ready` is a no-argument function in the ability-function environment, as `usable` is, and reaches
  the normal test through `ready()`, which exists only during its call (the ruling left the mechanism to this
  document). `sequence_ignore` accepts exactly the four gate names the ruling's line references cover; a wrong
  name raises at registration.
- The two fields also apply to the any-member start test of `allow_skip=1`, for members after the first; the
  ruling says "a strict sequence's start test" without naming the variant.
- "By lines" in L1205 includes a sequence's own line: a strict sequence's chosen OPEN and a plain sequence's open
  line count as the open of the flapping pair (Fable for the owner, L1286).
- v6's "one line per distinct member" is read as one line per position, keyed on `window.<w>.step=K`, so a
  repeated member's own `if=` is read only at its position (Fable for the owner, L1290).
- G03 passes when the sequences start; the missed-press number is reported, since no ruling sets a threshold.
- Phase 2's CPU gate is defined in section 12 (shipped packs unchanged, three synthetic priorities measured); the
  rulings say only that the gate is in Phase 2.

### 14.4 Not checked in code

For the builders. None is an owner question; each names the phase that must settle it.
- Phase 1: whether `A.gcdKind[a] > 0` (Windows.lua:154) and `ability.gcd ~= "off"` (State.lua:1748) ever disagree;
  whether an on-next-swing queue is an on-GCD cast for strict deviation.
- Phase 1: whether a second Drain can run before all five display passes of a cycle have finished (5.4 assumes
  not; the Update coroutine yields across frames, Core.lua:516-523).
- Phase 1: where a Lua window keeps its evaluator's last value, and whether clearing it on a swap is one
  assignment (section 8).
- Phase 2: whether a slot-1 line is always evaluated at delay 0 outside the recheck loop (if not, "at now" needs
  the delay test in 5.1 as written); whether the alternatives probe is the only reset outside the display passes.
- Phase 2: whether the core can ask "castable at the end of the GCD" for a member that is not the line being
  walked without a second state advance (the skip, the all-members start and `allow_skip` need it). [M]
- Phase 2: how a line is accepted as the pick with a wait when its ability is not ready (`mode=wait`): whether
  the existing delay and recheck path can carry it or the walk needs a flag.
- Phase 2: every place `WIN.lineLast` is cleared today (State.lua:1690) and whether a per-slot clear reaches the
  slot loop without an allocation; whether `state.WindowRecheck` (State.lua:1717-1725) depends on the per-cycle
  lifetime.
- Phase 2: whether `mode` or `step_timeout` collide with an existing entry field in the Actions tab or the script
  compiler. A grep of Options.lua found `mode` only in display-mode options and `wait_on_ready` only as a "not
  implemented" entry default (Options.lua:237); Scripts.lua was not read for it.
- Phase 2: the exact lines of the "toggle shown separately" tests (State.lua:7205, 7303) and that they apply only
  to Primary and AOE.
- Phase 2: SimC's `player_t::interrupt` cancelling a strict sequence (player.cpp:7280-7284) has no counterpart
  here beyond the give-up.
- Phase 2: the exact shape of the four gates (State.lua 7402-7419 and near 7597 were read only in part): whether
  `form` / `noform` / `buff` can be skipped inside the usable test without a second code path, and whether the
  `nobuff` wait can be left out of the time-to-ready for one judgement; how ability functions get their
  environment (`ability.funcs.usable( self, ability )`, State.lua:7323) so that `ready()` can be put in it without
  an allocation per call.
- Phase 3: that Overpower's stance requirement is its `form` field and Rend's blocker is a `nobuff` field in the
  Warrior class file (the owner named the gates; the file was not read), and whether Fury's two lines need the
  same fields.
- Phase 3: an APL expression for "before the fight's first main-hand swing" (the Lua evaluators use
  `lastSwing(1) < combat`); if none exists the Paladin lane adds one generic read.
- Phase 3: whether tests or tools besides the packs name `hha`, `move1` or `move2` as class windows
  (tests/Forever/hunter_spec.lua, paladin_spec.lua, the `# Window:` header parser in tools/wowsims/apl.lua).
- Phase 3: whether the Holy Shock pack's "move to melee" sequences are translated today, and how.
- Phase 5: whether the Actions tab's entry model can show a list of steps, each with its own options, without a
  new widget.

## 15. Risks, and how an author sees them

1. Flapping. A priority whose open and close conditions are both true (W09) opens and closes the window in every
   slot of every pass, five passes a second, for ever. Readers between the two lines see it up, readers elsewhere
   see it down, and the belief ends every update closed. This is by design (L795). A cost and a surprise, not a
   fault. The one-time warning (L1205) covers a window opened and closed by lines in one slot, and a sequence closed
   by a `close_window` line and started again in the same slot (strict: chosen again; plain: its open line); engine
   closes and STEPs do not count.
2. A window that never closes. A bare or held-true `open_window` reopens the window the moment it expires, so its
   duration means little, and `refresh=1` burns through `max_refresh` in under a second of held truth. Authors used
   to SimC's or the Lua windows' edges will meet this first. The guide must say "level" in its first paragraph.
3. Operation volume. Bounded per pass by the number of window lines (the fired mark; only slot 1 sends), so the
   buffer cannot overflow, but a flapping priority writes two log entries per display per update. Recordings grow;
   the fold does not slow down. Phase 3 reports operations per minute per key.
4. Restart cost, now without a cap and in every slot. Each change re-walks the list from the top. A flapping pair
   costs two extra walks per slot; a chain of n windows costs n; with the per-slot mark the same lines can fire
   again in each forecast slot. The worst case is (window lines) x (slots) extra walks per display per update. It
   is bounded and fixed at compile time, but it is the author's to pay. Phase 2 measures it; the snapshot shows it.
5. Determinism of replay. It rests on three things: the copy is seeded from exactly the state the replay meets
   (true only while the belief changes nowhere but in Drain, and one Drain precedes all five passes); operations are
   writes or, for OPEN, the one declared refresh rule both sides apply (ruling 18, v6.1); and the log holds them
   at the Drain head in order. If any breaks, belief and copy drift
   silently, because nothing compares them in play. The harness check "belief equals the sending copy after every
   Drain" (section 12) and L10/L11 are the guard. Belief-only replays must feed the logged operations.
6. A press before the window is open. The belief opens one Drain after the pass (up to 0.2 s,
   Engine/Driver.lua:159). With `start_on_first=1` (every shipped line) NOW_TOL is the queue window and the
   sequence is open during the icon's last 0.4 s of countdown; under the default start it opens only once the GCD
   is ready, after a queued press may already have landed (ruling 27 keeps this and measures it); an off-GCD first
   member that appears with no countdown and is pressed within one update is still missed, where today's `prev.1`
   chain is not. Phase 3 counts it. [M]
7. The latch repeats. A chosen strict sequence that is never pressed closes at `step_timeout` and, being level,
   is chosen and opened again on the next pass: one OPEN per 4 s.
8. Forecast slots differ from what is sent. With the per-slot mark the copy in slots 2 and later can open and
   close windows the belief never hears about; that is the point of ruling 20. An author reading the snapshot
   must look at slot 1's operations to know what the belief received.
9. A reserved list name (ruling 22): a user's old list called `windows` gets E5 on load. Release note.
10. Displays disagree (ruling 9). Primary and AOE each run their own pass with their own target count, so one
    can be held in a strict sequence while the other recommends from its normal list; pressing the other's on-GCD
    pick is a strict deviation and ends the sequence. Cooldowns never sequences, so a member can also appear in
    Cooldowns through its normal list while Primary shows it (D07). Accepted by the ruling ("the player can
    decide"); the snapshot's per-display Windows section shows which display is in which sequence and step.
11. A display shows abilities outside its category (rulings 9, 25): a separated cooldown in Primary or AOE, both
    as a later member and as a sequence's first member. Expected by the rulings, new
    to users; one line in the release notes. The exception is narrow: marked lines, toggle not switched off (D06,
    D08, D10).
12. A cooldown that exists only as a sequence's first member is not shown in the Cooldowns display: Cooldowns
    never sequences, so the sequence line is skipped there. It shows in Primary instead (ruling 25). The
    snapshot's per-display Windows section says "Sequences: off" for such a display.
13. The default skip is sharp. A plain sequence with `mode=skip` drops a member that is uncastable for a single
    pass (short of energy by one point, P02) and does not offer it again in that run; with nothing castable it
    burns out on the spot. This is SimC's behaviour and a known surprise there too. The snapshot names every STEP
    with the member it dropped.
14. Two families of behaviour in one addon. A translator pack and a hand-written line with the same members act
    differently, by design. The Actions tab showing the flags (ruling 13) and the snapshot printing each open
    sequence's effective options are the only places a player can see why.
15. A target change does not end a sequence. A strict sequence whose later member needs the old target keeps the
    hold until the give-up (the member cannot be cast), `step_timeout`, or a cast outside it. Authors who want the
    reset write `reset_on_target_change=1`.
16. `mode=wait` can stall a display. A waited member that never becomes castable (a talent the player lacks, a
    range gate) blocks everything below the line for as long as the sequence's condition holds. SimC's behaviour;
    the snapshot shows "waiting on <member>".
17. The Phase 3 conversions move shipped behaviour. `hha` restarts its loop one update later than the Lua window
    and opens when first reached, not at combat start; the Paladin opener depends on a close line and an "in
    progress" read that the translator must write everywhere the old `.up` was read. A missed reader keeps a
    parked sequence looking "up" for the rest of the fight. G04-G06 are the guard.
18. The default strict start cannot begin a sequence whose later member is enabled by its first (a stance, a buff
    the first member applies) unless the pack marks that member's ability with `sequence_ignore` or
    `sequence_ready` (3.6), or the line says `start_on_first=1`. An imported SimC line over abilities without the
    fields simply never starts; the snapshot names the member that failed the start test.
19. A start test that looks past a gate can be wrong. `sequence_ignore` says "assume the first member will lift
    this gate". If it does not (the stance swap fails, the buff is consumed), the sequence opens, the second member
    cannot be cast and the give-up closes it: one wasted recommendation of the first member, repeated while the
    line's condition holds. A `sequence_ready` handler that never calls `ready()` skips every normal test and is
    the pack author's to get right. Both are pack code, invisible in the priority text except for the editor's
    read-only note.

How a pack author sees it. No new debug option; all of this goes in the existing debug output and snapshot, in plain
names:
- The existing per-line debug text (Core.lua:569) gains the outcome: "open_window burst: PASS at +0.00, opened,
  restart 1" / "already open" / "already fired this slot" / "PASS at +0.50, forecast only".
- A snapshot section per display, "Windows": "Sequences: on/off"; each window's state and step as seeded; the
  operations slot 1 sent in order with the line that sent each; the restarts in each slot (ruling 24); each open
  sequence's effective options (mode, flags, step timeout) and, for `mode=wait`, the member waited on.
- Two rolling numbers per window: operations in the last 10 s and opens in the last 10 s. A flapping window reads
  "burst: 100 operations / 10 s" at a glance; a looping one reads "50 opens / 10 s". Kept as plain counters in the
  core's debug data, not in the belief.
- A belief section listing keys (the only place the `#display` suffix is shown), operations applied and dropped
  since combat start, and the last drop's key.
- Compile errors E1-E7 appear with the priority's existing warnings, with the line number and the plain name.
