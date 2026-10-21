# Gap register

The open gaps the wowsims packs plan's lanes and central fixes found (the overnight run of 2026-10-19/20), so the next
session composes fixes from one list. A gap is fixed in the layer that is wrong, cohesively across that domain
(belief, sim, facade, harness, tests, docs), never worked around in a lane. Status is as of forever afc84eb2
(2026-10-21), from the morning notes, the six lane reports and the tree's own `GAP` references; "not re-checked" means
the tree says nothing either way. Layers: **core** (`src/Hekili/`: belief = `Game/State/`, sim = `Engine/Sim/`), **kit**
(a class file), **translator** (`tools/wowsims/apl.lua`), **harness** (`tests/Game/harness/`: replay and loop world),
**tools**.

## Open

| Id | Mechanism | Layer | Status | Waiting |
| --- | --- | --- | --- | --- |
| Y | Energy: the loop world's 0.1 s regen tick at a press's instant orders after the press, and `TimeToResource` pads a full tick while the phase is unknown; about 170 of Subtlety's 284 Slice and Dice splits (counterfactual lo = truth: 284 -> 27) | harness world + core sim | open. Ready time (forever-readytime review): the replays' steady +0.19-0.20 s on Combat and Assassination is G7 (the observer's unmeasured `usableDelay`: the usable answer is still "no" at the cast's tick, the belief clamps to cost - 0.01, the engine forecasts the next tick), not Y; with G7 = 0 their real decisions go 28 -> 0 and 47 -> 0, Subtlety's 60 -> 35 at 0.12-0.15 s, "slack": those 35 are Y's tick-phase pad | Rogue Subtlety (raise its loop floor after) |
| AG | Mana returned by blocks and hits (Improved Seal of Fury, Shield Specialization) is not modelled | kit (Paladin) | open | Paladin Protection replay (floor 0.62) |
| AH | The replay does not replay the target's swings (the tank exports log them since central fix 13): nothing hit-driven (Revenge's window, blocks, rage from damage taken) is checked against wowsims | harness replay | open | Warrior and Paladin Protection, Guardian |
| AM | Target-health brackets from an Execute-style `IsSpellUsable` (<20/25/35%), borrowed from NAG | core belief (target health) | open, design | execute phases, Guardian |
| AN | A learned time to die from observed target health drops where plain, shared across the group; until then `fight_remains` answers unknown (API-forced, `docs/dev/architecture.md` §6, §8) | core belief + sim | open, design | every `remainingTime` line |
| AQ | Aura regen is a fixed number (`Families/Resources.lua` :377-381, :429), so Improved Bloodrage's 1.5 rage/s at 2/2 cannot be modelled (forcing it left Arms agreement unchanged) | core belief | open | Warrior |
| AR | A white crit and one of our casts in the same frame lose the crit's extra rage (Resources.lua ~:759, :1093-1146; belief 0.00 vs truth 4.88 for 1.6 s, Fury 69.51 s); suspected, not proven at line level | core belief | open | Warrior Fury |
| AS | A missed Sunder Armor just after our own swing is not attributed to the cast (`Events/Rows.lua` :157, :478; stacks re-read only on an aura change): the belief counts 4 stacks, the client 3 (Fury 89.82 s) | core belief (outcomes) | open | Warrior |
| AY | The rest assumption: a slot that rests at its maximum (mana, energy) is believed full at a build (`Families/Resources.lua` :298-299 `assume`/`over`, :1432 lo = lo0 + over), and the facade's `UnitPower` returns that lo (`API/Facade.lua` :244-247). A build mid-combat or after a fight (`/reload`, a spec or talent swap, a login with partial mana) puts the floor at max until a short answer, an exact read or a pin's top below it ends it, so `mana.pct`, `energy.deficit`, time-to-X and "can I afford B after A" read full meanwhile. Deliberate (fix 6), unmeasured, and the one place lo may sit above the truth by design. Fix: assume only for an out-of-combat build whose PLAYER_REGEN_ENABLED is older than the pool's time to fill, else `assume = false` | core belief (resources) | open; severity medium (seconds of wrong recommendations after a mid-combat `/reload`; the floor rule broken) | none |
| AZ | est for the on-next-swing pooling threshold only (second specimen, 19% of HS waits): Fury's `rage.current>=40` reads the floor, and where est >= 40 > lo the truth is >= 40 89% of the time; a core expression (the resource's estimate) the pack's line reads instead, never a cost check (whole-engine est fails the refusal bar: Arms 8.1 per 100) | core sim + kit (Warrior) | built on forever-gap-az with the held-pool guard; PARKED 2026-10-21: Fury L60 flicker 1.71 -> 2.44 and 1.90 -> 2.42/min over the 2.0 bar, the extra flicker is mostly not near-ties; input to the flicker design study after v0.3.0 | Fury L24 loop |
| BD | Cast-boundary flicker, two mechanisms: (1) mid-cast the next cast is priced affordable at the cast's end, and after the success its wait jumps 0 -> 2-8 s (the forecast does not see the in-progress cast's cost, nor the five-second rule starting at its success); (2) a DoT-refresh pick computed from the cast's end flips at the end tick (wrath -> insect_swarm -> wrath 0.2 s before Wrath completes, both instances). Balance 20-fight 1.63 -> 2.51/min (oracle 0.27 -> 0.99), Arms 1.38 -> 1.57 (oracle 0.94 -> 1.10) on central fix 22; the old harness hid it (no UNIT_SPELLCAST_START) | core sim (forecast across a cast in progress) | open, priority under the no-jitter rule | none named |
| BE | Balance's Starfire is 3.5 s in the kit against wowsims's 2.5 s (the kit's Eclipse charge, unmodelled), so our world casts slower: wowsims dips to 133 mana at 41 s (Innervate at 41.18 s) and sits at the floor from ~73 s; ours dips to 57 at 48.4 s and from ~83 s | kit (Druid) | open | Balance |
| BF | Belief gaps the truthful harness shows once a press resolves from the current state (central fix 22 round 2): Feral's 20-fight line moves the wrong way (agreement 0.942 -> 0.941, flicker 1.70 -> 2.12/min, oracle 1.52 -> 1.72) and Guardian's cost refusals rise 19.8 -> 25.1 per 100 (unmatched 9.9 -> 15.2): our belief, not the world, now explains them | core belief (energy, rage) | open, priority under the no-jitter rule | Feral, Guardian (AQ-AS, AV, AW) |
| BH | Arms's first Slam is shown ready 0.88 s early: `{ 15.080, "slam", "gcd", "on", -0.880, -0.080, "early" }` (tests/Forever/fixtures/timing_warrior_arms.lua): the icon reads ready during Spearing Strike's GCD on Slam's first cast; suspected Slam's `cast` / `gcdTime` functions (Improved Slam's 1.0 s) in the engine's GCD forecast | core sim (kit functions) | open, not dispatched | none |

Unnumbered, from the lane reports (give one an id when it is dispatched):

| Gap | Mechanism | Layer | Waiting |
| --- | --- | --- | --- |
| Same-frame avoid | An avoided strike pairs with nothing when another cast of ours lands in the same frame (UNIT_COMBAT carries no spell), so that Maul's refund is lost; the bear harness keeps a narrow tolerance until it is exact (Druid L17) | core belief (`Events/Rows.lua`) | Guardian |
| Replay swing outcome | The replay delivers a white swing's outcome one landing lag (`M.LAND`) after the log's timestamp, rage at the swing; ruling (user + owner): deliver it at the log's own time if every replay line holds or rises. Guardian's top two disagreement classes | harness replay | Guardian |
| `equipped` in the belief | The belief's cost context has no `equipped`, so the Howling Idol and Wolfshead Helm stay aura reads | core belief (`Families/Now.lua`) | Druid |
| One-weapon replay | The replay world has one weapon, so the belief reads the off-hand period as 2.1 s (truth 1.9 s) | harness replay | Fury |
| Unmapped autocasts | Three automatic cooldowns wowsims uses stay unmapped in Enhancement: trinket 249469, explosives 10646 and 260817 (Rage of the Farseer 425336 is in the kit since forever-farseer) (GAP 14's residue) | recipe map / kit | Shaman |
| Fire Nova 375 | GAP V is fixed (central fix 13: a usable answer above the believed top is a bound, never a pin); retry Fire Nova at wowsims's 375, re-floor, then un-pend L40 | kit (Shaman) | Shaman |
| `shockCooldown()` | `Shaman.lua` shockEffect repeats the Reverberation formula: `shockCooldown()` raises outside the handler's state environment; a setfenv-aware helper | kit / core helper | Shaman |
| Mongoose window | `tests/Forever/helpers/hunter_world.lua` `dodged()` reads `W.t`/`W.truth`, which a batched answer sees at the finished world, so the loop's Mongoose Bite window never opens | harness world | Hunter Survival |
| Base mana below 60 | Percent-of-base costs (GAP H, closed by central fix 14) use each class's level-60 base mana (`base` in the mana meta) at every level | kit | lower-level Paladin, Shaman, Hunter, Druid prices |
| `mainhand_remains` | Copied into the Warrior, Hunter and Paladin kits; one generic core swing field | core | none |

## In game (on the in-game ledger, not a register item)

- AB: secret-mana belief precision at near-ties; needs the UNIT_POWER_FREQUENT-for-mana capture (checkpoint M1,
  `docs/dev/layout.md`).
- AO / AP: our own DoTs from the target's nameplate aura frames; the nameplate aura probe (ForeverProbe) first.
- AX's residue: a foreign avoid landing in our cast's landing window (partly fixed by final review fix 4); a group
  fight with `/vslog` (O1, O2).
- `prev.1` from real casts: that the client's real casts fill `prev.1` as the harness does (PV1).

## Decided (user, 2026-10-21)

- Range filter: stays in the tint mode by default (out-of-range abilities shown in red); the exclude mode is each
  display's own Range setting (user ruling 2026-10-21).
- AY: to be built as a carry-over belief snapshot in saved variables (central fix, after v0.3.0).
- BD and BF: explained to the user, priority pending.
- AM / AN: a predictive time-to-die design is being drafted (design agent); AM and AN stay open pending it.

## Ignored (user ruling 2026-10-21: will not fix unless a gate moves)

- Q: the bear gate's float ties at exactly Maul's 15 rage count as "floor above truth".
- K: an Update after each GC cycle rebuilds 3-7 KB (suspected string building in the refresh path).
- L: a one-frame staging lag between a paid cast and its success's fold.
- BG: the Marksmanship and Beast Mastery loops are byte-identical (or merge the two Hunter loops to save gate time).
- ICD sentinel: an `icd` aura first seen up gets `applied = now - icd`; wants a `shortcut:` note.
- Items by list name: a pack's items register by list name, so a precombat-called list's use-item counts as in-combat.
- Stale recipe headers: the recipes' header numbers are history; the spec files hold the gates.
- Explosives timing: rule 13 does not model explosives cast just after a GCD.
- `use_items` toggle: a toggle on the internal `use_items` action is inert; each item's own ability carries it.
- Same-timestamp expiry: the replay judges a fade sharing a cast's timestamp a removal.
- Levels CLI: `tools/check_pack_levels.lua` run directly is not class-aware (exits 1 on the Paladin packs).
- Rule 14 deviation: a cast between two `strictSequence` members replaces `prev.1`; not listed in rule 14's deviations.

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
`strictSequence`); fix 18 (the Arms/Fury leveling Sunder filler's stack guard); the precombat-group `prepull_at` loss
(final review fix 5: a group the prepull calls gives its casts the caller's `prepull_at`, rule 1; Arms's and Fury's
Pre-pull: Move and Arms's Pre-pull: Stance no longer show on every out-of-combat refresh).
AT (forever-readytime: the replay read the class's auras with `pairs` while a computed duration grew the table, so
Arms's Rend never reached the replay's target; a snapshot now, no line moved). AK revisited (fix 21: a pending swing ends only on a rung above the floor, its credit or one landing lag, at most 1 s;
Fury L24 agreement 0.893 -> 0.908, unmatched cost 1.8 -> 1.2 per 100, flicker 4.35 -> 3.31/min, Heroic Strike
snap-backs 4.77 -> 0.84/min (oracle 1.44), lateness median 3 / p90 9 polls; Arms unchanged).
BB (central fix 22: `spendBase = true` prices a percent-of-base cost at any magnitude; the Mage kit declares it on
arcane_blast). BC (central fix 22: the harness's channel and cast bars; the start order is Mage checkpoint M4).
Pack version (central fix 24, f0ce3610: `make_pack`'s version is monotonic).
BA (the Delete Priority and Specialization guards read `Hekili.Version:sub(1, 3) ~= "Dev"`: a built-in priority shows
no Delete button outside a Dev build).
Fix 25 (the Warlock lane's option-selected cast, `castWarlockAssignedCurse`: choice settings in the core, rule 16's
`select`; the Warlock recipe entry and class setting are the lane's).
Cancelled: fix 19 (a harness-vs-in-game default for Sunder; players use Hekili's own per-ability toggles).
