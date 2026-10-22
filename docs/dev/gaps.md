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
| BI | A cost out of the forecast's horizon read as ready: the sim's resource slices are reused between passes, and `state:TimeToResource` read `forecast[i + 1]` past `fcount`, a stale pass's slice (in the past, at or above the amount), so the time to it came back negative and the cost wait vanished. Fire's Pyroblast showed ready at about 40 of its 440 mana for about 0.8 s, then dropped with no event (27 times in 20 fights; a retracted ready in the one-focus display); Arcane Blast likewise | core sim (`Engine/Sim/State.lua` TimeToResource) | closed by central fix 26: the next slice only below `fcount` (tests/Game/harness/fsr_forecast_spec.lua). Fire 20 fights: cost refusals 10.3 -> 0.1 per 100, agreement 0.992 -> 0.994; Arcane 4.6 -> 0.4, flicker 1.43 -> 1.33/min; replay floors Fire 0.84 -> 0.82 (a false agreement on a Mana Citrine's Pyroblast), Arcane 0.77 -> 0.81 | none |
| BL | Cast a specific rank: wowsims's ActionID `rank` (`castSpell.spellId.rank`, and on the `dotIsActive` / `spellCanCast` / `spellTimeToReady` / `spellChanneledTicks` reads) is ignored by rule 5 (`tools/wowsims/apl.lua`), so a down-ranked cast reads as the top rank and its own-rank DoT as the top rank's. 51 ranked casts in 10 ui/specs files; true down-ranks: Smite 2 (Holy Fire 15265 r5, Smite 1004 r5), Elemental 1 (Lightning Bolt r8), Rogue 2 (Vanish r2), Arms and Fury 1 each (Charge r3) | translator (+ kit rank keys) | open; costs Smite 3 of 44 decisions (holy_fire -> smite below 20% mana; the recipe translates at the top rank by owner ruling) | Priest Smite |
| BM | Next-ready during a channel: an action other than the one being channeled passes `channelPass` (`Engine/Sim/Core.lua` ~:972) and is timed by `state:TimeToReady` (`Engine/Sim/State.lua` ~:7200), which has no channel term; only the queued-event loop (~:1792) waits a channel out. Should be max(GCD end, cooldown, channel end); today max(GCD end, cooldown). Beside BD (cast-boundary flicker) | core sim | open; Shadow's ready 1.5 s early after each Mind Flay (`M.READY` priest_shadow { 1.50, 36 }), Arcane Missiles about 0.9 s; decisions unaffected | Priest Shadow, Mage Arcane |
| BN | `channelSpell.interruptIf` dropped: the translator keeps a channel's cast but not its `interruptIf` (the engine has `interrupt_if`), so a clip condition is lost | translator | open; Mage's Evocation clip at >= 99% mana (the world clips by wowsims's rule); Priest's Mind Flay MF3 (ticks == 3) is its natural end, so no Priest decision moves | Mage, Priest |
| BO | Fury (wowsims.com) at level 30 idles 14-28 s per seed (scratch runs, seeds 1-8, before the leveling Hamstring): from 30 the list holds Berserker Stance with no Bloodthirst or Whirlwind, so nothing is on the GCD. The forever-l40 Hamstring (out of Battle Stance) fills it (mean 2.65 s), but 30 is not a gated bracket (10/40/60), so nothing pins it | harness (leveling brackets) | open; fixed in passing, unpinned | none |
| BP | The L40 bracket lacks Mortal Strike and Bloodthirst only because `tests/Forever/helpers/wowsims.lua` `content` cuts talents to 31 points (level - 9), dominant tree first, short of the 31-point strike. A real level 40 player who took it never sees the leveling Hamstring (its `!action.<strike>.known` guard makes it silent), so the L40 fillers and their idle numbers describe a 31-point character only | harness (talent cut) | open; by design of the cut | none |
| BJ | A pooled line blinked at its threshold: a `>=` recheck runs at `resource.timeTo( X )` (Scripts.lua ConvertTimeComparison, no 0.01 nudge for `>=`/`<=`), and `tickReach` (Engine/Sim/State.lua) pads to the next tick from the slice's tick phase, which for a slice on a tick comes out 0 or a hair under the tick through GetTime's rounding; the latter padded about 1e-11 s, under the clock's own rounding of `base_delay + step`, so the forecast at the recheck read X minus about 1e-11 and the line failed (in game: Assassination's `sinister_strike,if=...energy.current>=75` at Recheck #3 read 75.00 NOT MET, then 76.00 MET two seconds later, so the third slot alternated with nothing; headless: 2352 of 128916 reads at a time_to_X answer were under X in the Assassination 20 fights, every one from the regen branch with a pad under 1e-6 s) | core sim (`Engine/Sim/State.lua` tickReach) | closed by central fix 29: the tick pad is at least 1e-6 s, so the forecast at a time_to_X answer reads at least X (tests/Game/harness/fsr_forecast_spec.lua). Snapping to the tick after instead moved Feral 2.12 -> 2.81 and Balance 2.51 -> 2.88 flicker/min, over their floors. Rogue 20 fights: Assassination agreement 0.996 -> 1.000, flicker 0.10 -> 0.00/min (floor 0.1 -> 0); Subtlety 0.973 -> 0.978, 0.23 -> 0.18 (floor 0.3 -> 0.2); Combat unchanged; Druid and Warrior loops unchanged. Replays: Assassination agreement 0.951 -> 0.956, flicker 2.00 -> 0.33/min; Combat 0.942 -> 0.944; Subtlety 0.927 -> 0.930; two timing rows' predicted offset moved (Feral shred 26.74 -0.04 -> -0.03; Combat cold_blood 7.80 none -> 0.304), no shown offset or verdict | none |

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
| Pet power model | `VS.PetPower` is the last plain `UnitPower("pet")`; no regen or spend model. UnitPower is `SecretWhenUnitPowerRestricted` and unprobed with a pet out (plain 0 with none, W PR12); if the Warlock checkpoint finds it secret, the pet's mana freezes at its last out-of-combat read | core belief (pets) | Warlock in-game Q3 |
| Reagent prediction | A reagent count (Soul Shards) is read live through `C_Item.GetItemCount`; the sim does not predict a shard spend within one recommendation pass, so a second shard spender in the queue reads the count before the first | core sim | Warlock (pack) |
| Replay bags | The replay world starts from the content's bags (`WORLD.bags`) and does not read the log's (wowsims's 32 shards); the pet's power is read since central fix 31 | harness replay | Warlock replay gate |
| Travel time | An aura consumed when the hit lands, not at the end of the cast (Elemental's Revelation is spent on landing), so the belief spends it a travel time early; 2 Elemental replay decisions, and Mage has the same issue. Also (Warlock lane's G6): a projectile's crit lands past `CAST_WINDOW` (`Events/Rows.lua`'s no-`velocity` shortcut), so its `onCrit` never runs (Shadow Bolt's Shadow Vulnerability). Central fix 32, with a design | core belief + harness replay | Elemental, Mage, Warlock |
| Potion mana refill | The mana belief does not believe a mana potion's or Demonic Rune's refill (lo up to 2286 under the truth in Elemental's replay); GAP AB/V family, 1 Elemental decision | core belief (mana) | Elemental, other mana users |

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
Fix 28 (the Warlock lane's translator gaps): T2, rule 8's "N%" is N/100 except as a direct operand of a comparison
with a percent read (Demonology's "Execute at" in `math`; no shipped line moved, every "%" in the 18 requests is such
an operand); T1, `min` / `max` values (rule 6: a term that may be nil as `(<known>&<term>)`, which the engine's
min/max skip; the level checker takes it); T4, rule 16's candidate terms carry their known test, so the Warlock packs
pass `tools/check_pack_levels.lua` without an exception; T5, `multidot` as the single-target cast (rule 17; only the
Elemental testing build uses it at the pin). T3, `currentMana` of the pet (rule 5's other source unit), closed by
fix 27 (`pet.mana`).
Fix 27 (Warlock K15's shared gaps): the exporter's `gear` for a build with none; the pet's power in belief, facade
(`UnitPower("pet")` raw while plain) and sim (`pet.mana`), and the translator's Pet resource reads; `dismissPet` in the
belief and the engine stub's `pet`/`dismissPet` (content API 9); the harness's bag counts (`reagent`, `item`), pet unit
and its power, and stats (`WORLD.bags`, `WORLD.pet`, `WORLD.stats`). Open from it: the three rows above (pet power
model, reagent prediction, replay pet and bags).
Fix 31 (the Warlock lane's shared gaps G1-G5): G1, the debug printer (`Engine/Sim/Scripts.lua` generateDebugPrint)
read words inside a quoted literal as terms, so `settings.<key>='<candidate>'` raised "Unknown key" on every debug
evaluation (snapshots); it now skips quoted literals, and a double-quoted candidate stays literal in the resource
rewrite too. G2, the observer took the pet events' `power` (the pet's mana) as ours on a plain client: the world's pet
events carry `petPower`. G3, a fight ending mid-cast left the cast's start standing as the next instant cast's GCD
anchor: the world ends our cast (INTERRUPTED, STOP) or channel at a kill of its target and at the stop. G4, a target's
outcome names no source, so an unmapped item's miss (the Affliction log's Ez-Thro Dynamite II) was credited to our
pending Corruption: an unmapped cast of ours makes an avoid or crit within `L.UNMAPPED_WINDOW` (2 s, unmeasured), past
our cast's own frame, nobody's, as two pending casts do, and the replay emits an unmapped item's use as our cast (the
frame clause keeps the Shadow replay's opener miss, items used in the same frame, our Shadow Word: Pain's). G5, the replay reads our
pet's power lines into the world's pet (the Demonology and Shadow Brand `pet.mana<N` lines). G6 (projectile travel) is
the Travel time row above. Gates on the tree (no Warlock pack yet): every replay line and `make test-loop` unchanged;
five leveling lines gained one press (Arcane L10 41 -> 42, Fire L10 42 -> 43, Shadow L40 56 -> 57, Smite L10 62 -> 63,
L60 77 -> 78), G3's: the press in the kill's tick is no longer refused "casting" by the dead target's cast.
Cancelled: fix 19 (a harness-vs-in-game default for Sunder; players use Hekili's own per-ability toggles).
