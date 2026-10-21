# Gap register

The open gaps the wowsims packs plan's lanes and central fixes found (the overnight run of 2026-10-19/20), so the next
session composes fixes from one list. A gap is fixed in the layer that is wrong, cohesively across that domain
(belief, sim, facade, harness, tests, docs), never worked around in a lane. Status is as of forever 932479ce (central
fixes 1-18 merged), from the morning notes, the six lane reports and the tree's own `GAP` references; "not re-checked"
means the tree says nothing either way. Layers: **core** (`src/Hekili/`: belief = `Game/State/`, sim =
`Engine/Sim/`), **kit** (a class file), **translator** (`tools/wowsims/apl.lua`), **harness** (`tests/Game/harness/`:
replay and loop world), **tools**.

## Open

| Id | Mechanism | Layer | Status | Waiting |
| --- | --- | --- | --- | --- |
| L | A one-frame staging lag: the truth has paid a cast whose success folds a frame later, after a usable rung raised the floor (lo 20 vs truth 6.2 at 5.2 s); inflates lo-over-truth wherever a usable rung lands in a cast's frame | core belief (event staging order) | open, not dispatched | none named |
| Q | The 200-fight bear gate (`make gate` only) reads danger=2: float ties at exactly 15 rage (Maul's cost) count as "floor above truth"; compare with an epsilon at the cost boundary | harness metric (`tests/Forever/druid_harness_spec.lua`) | open, not re-checked | the bear gate |
| K | After each GC cycle an Update rebuilds 3-7 KB (coroutine stack, collected interned strings), which suggests string building in the refresh path; the allocation test cannot see interned strings | core (refresh path) | open: hunt the source | none |
| Y | Energy: the loop world's 0.1 s regen tick at a press's instant orders after the press, and `TimeToResource` pads a full tick while the phase is unknown; about 170 of Subtlety's 284 Slice and Dice splits (counterfactual lo = truth: 284 -> 27) | harness world + core sim | open | Rogue Subtlety (raise its loop floor after) |
| AB | Secret-mana belief precision: within 1-3 mana at near-ties (Holy Shield ready 0.13 s apart), and sub-1-mana cost refusals (ours 0.9 vs oracle 4.2 per 100); mana's one-tick padding (`tick_rate` 0.1) with an unknown phase | core belief (mana) | open; needs the in-game UNIT_POWER_FREQUENT-for-mana capture (C3 in layout.md) | Shaman L40 bracket (pending), Enhancement replay 0.909 -> recover, Retribution |
| AG | Mana returned by blocks and hits (Improved Seal of Fury, Shield Specialization) is not modelled | kit (Paladin) | open | Paladin Protection replay (floor 0.62) |
| AH | The replay does not replay the target's swings (the tank exports log them since central fix 13): nothing hit-driven (Revenge's window, blocks, rage from damage taken) is checked against wowsims | harness replay | open | Warrior and Paladin Protection, Guardian |
| AM | Target-health brackets from an Execute-style `IsSpellUsable` (<20/25/35%), borrowed from NAG | core belief (target health) | open, design | execute phases, Guardian |
| AN | A learned time to die from observed target health drops where plain, shared across the group; until then `fight_remains` answers unknown (API-forced, `docs/dev/architecture.md` §6, §8) | core belief + sim | open, design | every `remainingTime` line |
| AO / AP | Our own DoTs checked against the target's nameplate aura frames. PROBE FIRST (ForeverProbe, ~1 h): are the nameplate aura frames' shown state and textures plain in combat? | core source | open; probe | caster lanes (Warlock, Shadow Priest) |
| AQ | Aura regen is a fixed number (`Families/Resources.lua` :377-381, :429), so Improved Bloodrage's 1.5 rage/s at 2/2 cannot be modelled (forcing it left Arms agreement unchanged) | core belief | open | Warrior |
| AR | A white crit and one of our casts in the same frame lose the crit's extra rage (Resources.lua ~:759, :1093-1146; belief 0.00 vs truth 4.88 for 1.6 s, Fury 69.51 s); suspected, not proven at line level | core belief | open | Warrior Fury |
| AS | A missed Sunder Armor just after our own swing is not attributed to the cast (`Events/Rows.lua` :157, :478; stacks re-read only on an aura change): the belief counts 4 stacks, the client 3 (Fury 89.82 s) | core belief (outcomes) | open | Warrior |

Unnumbered, from the lane reports (give one an id when it is dispatched):

| Gap | Mechanism | Layer | Waiting |
| --- | --- | --- | --- |
| Same-frame avoid | An avoided strike pairs with nothing when another cast of ours lands in the same frame (UNIT_COMBAT carries no spell), so that Maul's refund is lost; the bear harness keeps a narrow tolerance until it is exact (Druid L17) | core belief (`Events/Rows.lua`) | Guardian |
| Replay swing outcome | The replay delivers a white swing's outcome one landing lag (`M.LAND`) after the log's timestamp, rage at the swing; ruling (user + owner): deliver it at the log's own time if every replay line holds or rises. Guardian's top two disagreement classes | harness replay | Guardian |
| `equipped` in the belief | The belief's cost context has no `equipped`, so the Howling Idol and Wolfshead Helm stay aura reads | core belief (`Families/Now.lua`) | Druid |
| One-weapon replay | The replay world has one weapon, so the belief reads the off-hand period as 2.1 s (truth 1.9 s) | harness replay | Fury |
| Unmapped autocasts | Four automatic cooldowns wowsims uses stay unmapped in Enhancement: trinket 249469, Rage of the Farseer 425336, explosives 10646 and 260817 (GAP 14's residue) | recipe map / kit | Shaman |
| Fire Nova 375 | GAP V is fixed (central fix 13: a usable answer above the believed top is a bound, never a pin); retry Fire Nova at wowsims's 375, re-floor, then un-pend L40 | kit (Shaman) | Shaman |
| `shockCooldown()` | `Shaman.lua` shockEffect repeats the Reverberation formula: `shockCooldown()` raises outside the handler's state environment; a setfenv-aware helper | kit / core helper | Shaman |
| Mongoose window | `tests/Forever/helpers/hunter_world.lua` `dodged()` reads `W.t`/`W.truth`, which a batched answer sees at the finished world, so the loop's Mongoose Bite window never opens | harness world | Hunter Survival |
| Base mana below 60 | Percent-of-base costs (GAP H, closed by central fix 14) use each class's level-60 base mana (`base` in the mana meta) at every level | kit | lower-level Paladin, Shaman, Hunter, Druid prices |
| Levels CLI | `tools/check_pack_levels.lua` run directly exits 1 on two negated aura reads in the Paladin packs; the spec path is class-aware, the CLI is not | tools | none |
| Pack version | `make_pack`'s version can go down within a day (regenerating twice), so Spec.lua prints "reverted" at login; make it monotonic | tools | none |
| `mainhand_remains` | Copied into the Warrior, Hunter and Paladin kits; one generic core swing field | core | none |
| ICD sentinel | An `icd` aura first seen already up gets `applied = now - icd`; one with no duration or tick_time would see the sentinel in State.lua's fallback: wants a `shortcut:` note | core sim | none |
| Range filter default | wowsims never casts an out-of-range spell; the fork shows such lines unless the player enables the range filter. Default it on? | UX (user decision) | the user |
| Explosives timing | Rule 13 does not model wowsims casting explosives just after a GCD | translator | none |

## Closed (for reference)

1-4, 9 and the unresolved-aura branch drop (central fixes 1 and 9: one ability set, rules 4-8 and 12); 5-8 (fix 2:
precombat-less lists, proc ICDs, every race registered, time to die loads clean); 10-12 (fix 3: the pull window,
`prepull_at`, creature types); 13 (fix 4: the range bracket); A, F (fix 5/5b: the guard checker, `requires`); B, B2, C
(fix 6: same-instant swings, mana regen in the fake and replay); D (fix 7: outcomes and refunds); E (fix 8: the mana
belief); G, 14 (fix 9/9b: replay cooldowns, rule 13); I, J (fix 10); P (fix 11: division as `/`); R, S (fix 12:
the five-second-rule forecast, secret health reads full); M, N, O, U, V, W, AA, AE, AF (fix 13: function cooldowns,
replay removals and restarts, `level` in the cost context, the usable bound, cast-timed effects, the log's pool
maxima, tank exports, the aura-only map); X (the loop's pools carried through the gap between fights); H (fix 14:
percent of base mana); T, AJ, AK (fix 15: Primal Fury's `onCrit`, `shared = "target"`, swing rage at PLAYER_SWING);
AC (the swing-scale window, `Families/Resources.lua` SWING_STEPS); AD (fix 16: precombat-called lists); Z (rule 14,
`strictSequence`); fix 18 (the Arms/Fury leveling Sunder filler's stack guard).
Cancelled: fix 19 (a harness-vs-in-game default for Sunder; players use Hekili's own per-ability toggles).
