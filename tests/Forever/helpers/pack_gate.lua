-- tests/Forever/helpers/pack_gate.lua: the per-pack headless gate (class-completion plan, "The per-pack gate"), the
-- Arms gate's body made class-neutral: `world` is a pack's tests/Forever/helpers/<class>_world.lua (the loop's
-- content), `label` the spec name printed before " solo:". Thresholds: headless loop design §5.2 (as built: the plan's
-- Deviations 7-8, 14-15); the Arms values they were set on: helpers/arms_gate.lua.
local assert = require("luassert")
local loop = require("Game.harness.loop")
local ab = require("Game.harness.ab")

local M = {}

-- The most cost refusals per 100 attempts the oracle shadow would not have made (loop.unmatched), a plain bar.
M.UNMATCHED = 3
-- Per label where a named cause re-based it (measured, rounded up to the next 0.1; floors only move up from here).
M.UNMATCHED_BY = {
    -- 5.8 at seeds 1-3 (was 0.5): harness corrected to the measured swing timing (2026-10-22); the world enters
    -- execute range at our swing, a landing lag before the client's rows show it
    ["Arms"] = 5.9,
}

-- The first-icon reaction bar's p90 (ticks) per label, 3 where not named (M.gate).
M.REACT_P90_BY = {}

-- The flicker floors at 20 fights: per label the first-icon flicker/min (loop.flips: an A -> B -> A over three ticks,
-- not counted when the instance pressed B at the tick it showed or the next, owner rule 2026-10-26) and the
-- unjustified retracted readies/min (tests/Game/harness/flicker.lua). A floor is the worst of seeds 1-20 / 21-40 /
-- 41-60 (beside it) rounded up to the next 0.1, 0 where all three measured 0 (parry-haste spec decision 63: the
-- loops are deterministic but a world change reorders every seeded fight). A floor only moves down, except with a
-- named cause recorded beside it. Guardian is reported (M.gate's bars and the oracle + K bar are not asserted) but
-- floored: its row below is applied on the reported branch too (gap CH).
-- Flicker re-floored on forever-gap-bd (2026-10-26): the loop's cast bar on each instance's clock (gap BD) made every
-- hard cast and channel visible, and a proc or instant shown at a cast's landing and pressed at once (show-then-press)
-- is no longer counted; every pack's flicker fell (base f09656c8e -> after, seeds 1-20: e.g. Balance 2.36 -> 0.03,
-- SM Ruin 4.81 -> 0.25, Arcane 1.50 -> 0.02, Feral 1.80 -> 1.35). Retracted floors unchanged (the counter does not
-- touch them; lowered to the same rule where they sat above it: Fury L60 0.4 -> 0.2, Smite 0.9 -> 0, Elemental and
-- Affliction 0.1 -> 0). Fury L60's retracted readies: the pre-existing swing-forecast class (a cost-gated ability shown
-- ready on a swing's forecast rage).
-- readyShort (loop.readyShort, the owner's rule dim never promote): ticks an icon was pressed as ready with the truth before
-- the press under its cost and nothing in flight, worst of seeds 1-20 / 21-40 / 41-60, a floor that only tightens; absent
-- is 0. The class left over is swing-paid rage: a forecast swing's gain shows a cost-gated ability ready (Arms, Fury, Guardian).
-- heldReady (loop.heldReady, the mirror): ticks our first icon waited past REACT while the truth covered its cost and the
-- oracle shadow showed the same icon ready; the worst of seeds 1-20 / 21-40 / 41-60 on the fix-round-4 sweep (gap CG), a
-- floor that only tightens. Agreement compares names only, so these passed it. The class left over, per family (the
-- fix-round-4 review's per-tick trace of the three head seed sets; base is identical on every pack, the floors are its
-- measurement): Hunters, one tick per episode, the first icon's wait (0.06-0.5 s) read from a floor a few units under
-- the truth at a cost crossing (gap BT's lag bias: the client answers a gain late, G7; its capped variant, the short
-- answer heard a poll ago), Arcane Shot's shared cooldown's last 0.5 s under CD_PROBE and the cost-0 waits; the icon
-- shows one poll later. Rage: Fury L24 2142 ticks in 746 episodes, 297 of them multi-tick (longest 14), 1104 ticks
-- waiting over 0.5 s (before the world's off hand paid by rank: most of it was that artefact, see Fury L24's row);
-- Heroic Strike (1801 ticks: cost 15, lo 30-33, truth 41-45) waits on the APL's own
-- `rage.lo>=40` (Fury (wowsims.com).simc :52), a condition wait on a rage floor 10-35 under truth, not a cost
-- wait; Arms sunder_armor 2.81 s (8 ticks, lo 30, truth 43.7), 175 ticks over 20 under truth. Mana: Retribution a
-- 14-tick judgement episode (2.68 s, lo 68, truth 97); Protection 43 multi-tick episodes (lo 25 under); Fire fire_blast
-- 1.6-3.8 s, lo 46-62 under truth, 124 at worst. Energy: Subtlety an 18-tick rupture episode right after Cold Blood
-- (3.6 s, cost 25, truth 38-42), UNEXPLAINED, not traced (gap CJ with Fire's and the rage floors' depths). Beast
-- Mastery's 2288 / 1929 / 2512 -> 129 / 120 / 121 and Marksmanship's 104 / 140 / 117 -> 101 / 112 / 101 were gap CG (an
-- affordable Serpent Sting held dim for up to 22 s). Limit: the metric counts the first icon only, on the seeds a pack
-- gates (1-20; the floor is the worst of three), so it would have caught Beast Mastery's regression (2288 > 129) but
-- not Marksmanship's (104 <= 112 at seeds 1-20: its Serpent Sting presses 15 -> 26 moved only 3 ticks there, the lost
-- presses hiding under another first icon or an oracle wait).
M.FLICKER = {
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.04 / 0.04 / 0.04, readyShort 0 / 0 / 0, heldReady 315 / 221 / 228):
    -- flicker 0.3 -> 0.05 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals); readyShort 173 -> 0 (C1, a resource wait inside READY reads 0.06)
    -- regen phase lane, cause harness: the indexed poll clock (ledger L606/L667; a rage world has no regen grid) (R6;
    -- seeds 1-20 / 21-40 / 41-60 flicker 0.02 / 0.04 / 0.08, retracted 0.00 / 0.00 / 0.00, readyShort 3 / 0 / 0,
    -- heldReady 271 / 237 / 240): flicker 0.05 -> 0.08, readyShort 0 -> 3, heldReady 340 -> 271
    -- flicker-085 P3 (L872 (2): a pending swing newer than the last swing row is credited one poll after it; seeds
    -- 1-20 / 21-40 / 41-60 heldReady 279 / 237 / 240): heldReady 271 -> 279, all in seed 11 (t 91-152, one per swing). A
    -- float-rounding edge in the Warrior entry's last(), floor((t - swing) / speed), used to credit a landed swing at once
    -- after a parry pull; P3 confirms it one poll later (GAP AK's ORACLE_MIN), so ours shows the oracle's icon waiting
    -- 0.12-0.20 s. Not a rage error (trace: flicker-085 report, "Trace: Arms/Fury held trips")
    -- re-pin e5a9cd2a2d -> e4ef929e54 (0.9 warrior lane, R6; with gap-as-09, avoid-refund-09 and Execute's
    -- refundNowOnAvoid; seeds 1-20 / 21-40 / 41-60 flicker 0.06 / 0.04 / 0.08, retracted 0 / 0 / 0, readyShort 1 / 0 /
    -- 0, heldReady 316 / 239 / 266): readyShort 3 -> 1; heldReady 279 -> 316, per fight (seeds 1-20, the gate's boot)
    -- only seeds 5 (4 -> 30) and 6 (8 -> 19) move: ab8ad0acc (the re-pin kit: the damage-taken rage rows and the
    -- Execute world rule, not split) moves seed 2's kill 4.8 s, so seeds 5 and 6 start on another boot clock and land on the P3 float-rounding edge
    -- above (one held tick per swing, 0.12-0.20 s; each alone on a fresh boot reads 27 / 8 before and after ab8ad0acc);
    -- seed 6 +1 more: the gap-as-09 / avoid-refund-09 merges (field off reads the same) re-times it from 126 s (a
    -- Rend wait 2.79 s, truth 11.0 against its 10)
    ["Arms"] = { flicker = 0.08, retracted = 0.1, readyShort = 1, heldReady = 316 }, -- 0.24 / 0.17 / 0.26, 0 / 0.02 / 0
    -- flickerK 0.6 (this label only): seeds 1-20 read 0.85 vs an oracle of 0.30 (gap 0.55; 21-40: 0.81 vs 0.30). W1 made the
    -- oracle quieter, 0.36 -> 0.30, while our own flicker fell to 0.85 (owner 2026-11-03)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.26 / 0.3 / 0.19, readyShort 0 / 0 / 5, heldReady 190 / 228 / 203):
    -- flicker 0.9 -> 0.31 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals); readyShort 116 -> 5 (C1, a resource wait inside READY reads 0.06); heldReady 226 -> 228 (cost crossings, lo < cost <= truth, on fights D2 re-times; C1 shows a crossing one update later)
    -- 0.7 warrior lane (R6; re-pin 4b0030a44b/e5a9cd2a2d on integ/0.7 27add4428; seeds 1-20 / 21-40 / 41-60: readyShort 20 / 3 / 9, flicker
    -- 0.16 / 0.30 / 0.30, heldReady 129 / 130 / 186, retracted 0.16 / 0.10 / -): readyShort 5 -> 20. Traced (seeds 1-20, 20 attempts; 21-40
    -- seed 40: 9): every one is a Whirlwind (25) or Bloodthirst (30) pressed as ready 0.02-4.5 rage under its cost (pre 21.2-28.3),
    -- repeated on the 1-3 ticks the first icon stayed ready before the GCD's end, with no cast or spend in flight; the shortfall is
    -- the size of one forecast off-hand swing's rage (the loop world's off hand stays at FURY_SPEED 1.9 s, recipe header). Not traced
    -- to the swing time itself: the off-hand forecast is the named class, not measured per event. heldReady/flicker keep their rows
    -- translator-2 (autoTimeToNext: the Bloodrage line), seeds 1-20 ONLY re-measured (not 21-40 / 41-60): readyShort 20 ->
    -- 26 (counter 20 -> 26), every event the class above (Bloodthirst / Whirlwind shown ready a few rage short on a
    -- forecast swing), on fights Bloodrage's rage re-times; heldReady 129 -> 150 inside its bar; retracted 0.2 -> 0.21
    -- (0.16 -> 0.20+/min, the oracle 0.26 -> 0.47): each of the six unjustified retractions (bloodthirst 3, whirlwind 3,
    -- ledger cause credit, reason cost) has one of those readyShort presses inside its ready window (traced per event)
    -- regen phase lane, cause harness: the indexed poll clock (ledger L606/L667; a rage world has no regen grid) (R6;
    -- seeds 1-20 / 21-40 / 41-60 flicker 0.24 / 0.32 / 0.40, retracted 0.20 / 0.00 / 0.00, readyShort 26 / 7 / 1,
    -- heldReady 150 / 136 / 228): flicker 0.31 -> 0.41. The 21-40 / 41-60 rise predates that lane (L757 I1, bisected
    -- on seeds 41-60: 0.30 at a9a6fff9f, 0.40 at 79feadc67): translator-2's merge above (the Bloodrage line), whose
    -- re-measure covered seeds 1-20 only
    -- 0.41 -> 0.49 (L871): wowsims's per-swing Reckless Swings (world and addon) puts the opener's rage between Death Wish's
    -- 10 and Sunder's 15. 4 of the 6 opener flips (seeds 1-20) are a cooldown near-tie at the EARLY_EXIT edge (src/Hekili/Engine/Sim/Core.lua: the EARLY_EXIT list exit and the 0.05 s clash pad);
    -- 2 involve a landed, unpaid swing. Measured .48 / .39 / .44 (seeds 1-20 / 21-40 / 41-60) after the world charge fix 8a5dfbf2a.
    -- 0.49 -> 0.56 (L880): the world's Reckless Swings aura now ends at the 4th charge as in wowsims; the truer world is more
    -- volatile (oracle flicker 0.48 -> 0.68) and ours measures 0.54 against it.
    -- re-pin e5a9cd2a2d -> e4ef929e54 (0.9 warrior lane, R6; with gap-as-09, avoid-refund-09 and Execute's
    -- refundNowOnAvoid; seeds 1-20 / 21-40 / 41-60 flicker 0.18 / 0.34 / 0.49 (oracle 0.65 / 0.61 / 0.70), retracted
    -- 0.07 / 0.04 / 0, readyShort 15 / 2 / 5, heldReady 156 / 169 / 171): tightened to the measurement, flicker 0.56 ->
    -- 0.51 (the measured worst + 0.01), readyShort 26 -> 15, heldReady 228 -> 171; retracted kept
    -- re-pin ab0f: UW 59.5% x 1 rage rolled per hit (wowsims) + HS/Cleave Reckless charge (R6, the world rolling
    -- Unbridled Wrath from its own stream, eb63112ff; seeds 1-20 / 21-40 / 41-60 flicker 0.18 / 0.30 / 0.26 (oracle
    -- 0.67 / 0.48 / 0.40), retracted 0.07 / 0.04 / 0, readyShort 2 / 6 / 5, heldReady 226 / 197 / 229): tightened to the
    -- measurement, flicker 0.51 -> 0.31 (the measured worst + 0.01), readyShort 15 -> 6; heldReady 171 -> 229: the old
    -- world paid no Unbridled Wrath while the kit credited it, so the belief ran ahead of truth; truth now pays it and
    -- the belief's floor counts no unseen proc (strikeNow's gain spread = the amount; owner: no optimistic procs), so
    -- truth covers a cost before our floor more often (lo-truth at cost -1.1 -> -1.4); retracted kept
    ["Fury L60"] = { flicker = 0.31, flickerK = 0.6, retracted = 0.21, readyShort = 6, heldReady = 229 }, -- flicker 0.18 / 0.30 / 0.26, retracted 0.07 / 0.04 / 0 (ab0f, rolled)
    -- Fury L24's flicker up with a named cause (2026-11-01): the loop client's answer for Overpower was always no (a
    -- log-only aura) while presses ran on the dodge row; it now follows the world's window, which reorders the fights.
    -- Same world without Warrior.lua's client read: 0.90 / 1.08 / 0.83. Flips are mostly not Overpower; the mechanism is untraced.
    -- readyShort 41 -> 46, heldReady 910 -> 337 (2026-11-01, the world's off hand pays Dual Wield Specialization by the
    -- character's rank: 0 at L24, the cut stops short of it, where it paid 5/5, 1.73 x 1.5, over the pack's 1.73; gap
    -- CJ's trace, about 70% of L24's Heroic Strike holds were this artefact; seeds 1-20 / 21-40 / 41-60, was 26 / 30 /
    -- 17 and 909 / 372 / 853, flicker 0.84 / 1.04 / 0.77, retracted 0.06 / 0.03 / 0.03, oracle 0.34 / 0.70 / 0.39,
    -- agreement .930 / .944 / .918, was .941 / .932 / .934): truth no longer runs ahead of the pack's swing, so a
    -- forecast swing's gain shows a cost-gated ability ready with less overpaid rage behind it. The rise is real, mean
    -- 31 -> 50 over 12 paired seed sets: the overpaid truth was masking the forecast class
    -- flickerK 0.6 (this label only, M.FLICKER_K's own rule: widest gap 0.59; gaps 0.52 / 0.38 / 0.59): the oracle's
    -- flicker read 0.66 / 0.61 / 0.41 -> 0.34 / 0.70 / 0.39 here, but over 12 paired seed sets its mean went .545 -> .458,
    -- paired change -.09 (SD .17), not significant: seed reordering, not a mechanism
    -- readyShort 46 -> 53, heldReady 337 -> 406 (re-pin e2842f0a78, lane 14, R6; seeds 1-20 / 21-40 / 41-60: 53 / 47 /
    -- 47 and 406 / 328 / 260, agreement .942 / .914 / .940, dps A/B .996 / 1.032 / .989, flicker 0.46 / 0.52 / 1.25,
    -- oracle 0.31 / 0.49 / 1.04, retracted 0.06 / 0.06 / 0.16): (1) wowsims's new order puts Heroic Strike above Rend
    -- and the Sunder fallback, so its `rage.lo>=40` wait is the first icon more often (held 120 -> 207 at seeds 1-20,
    -- 198 of them with the truth at 40-60: lo under the truth at the threshold, gap CJ's class); (2) wowsims's Rend line
    -- reads `!debuff.rend.up` (was remains<=3): a Rend MISS tied with a main-hand swing in flight is held by the swing
    -- (UNIT_COMBAT carries no spell id); gap AS gives such an avoid back when the swing's own wound arrives
    -- (Events/Rows.lua:304-309, tieHolder :56-72; reactions_spec.lua:170-192), but a physical WOUND within SAME_FRAME
    -- (0.05 s, Events/Melee.lua:28) after the tied miss pays the avoided cast's still-OPEN ticket at pass 1 (Rend has
    -- no expects and no school, Warrior.lua:1531-1555, so it accepts any wound in its frame); the guard
    -- `T.state[q] == T.OPEN` (Rows.lua:307) then fails, the give-back never fires and the Rend undo (Families/Now.lua)
    -- is lost (paying-row candidates: the old Rend's tick at +24 ms, the swing's own wound at +6 ms), so the belief
    -- keeps Rend up its full 15 s while the oracle shows it ready (51 held ticks, seeds 7 and 20; 17 and 1 in the
    -- other sets): central, exposed not caused. Smallest central fix (not this lane): in route(), for a non-avoid
    -- WOUND whose pass-1 pick p is the tieP of a PROV swing, try tieHolder first. readyShort: 44 of 53 with no swing
    -- in flight; the three traced (seed 1: Sunder, Rend, Execute) pressed 0.049 s before a main-hand swing pays (the forecast class above). Flicker 1.1 -> 1.3:
    -- seeds 41-60 read 1.25 with the oracle's own 0.39 -> 1.04 (ours over the oracle 0.21, inside flickerK): the new
    -- order re-times the fights (seed reordering, as the note above)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.2 / 0.32 / 0.49, readyShort 0 / 0 / 0, heldReady 439 / 336 / 238):
    -- flicker 1.3 -> 0.5 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals); readyShort 53 -> 0 (C1, a resource wait inside READY reads 0.06); heldReady 406 -> 439 (cost crossings, lo < cost <= truth, on fights D2 re-times; C1 shows a crossing one update later)
    -- regen phase lane, cause harness: the indexed poll clock (ledger L606/L667; a rage world has no regen grid) (R6;
    -- seeds 1-20 / 21-40 / 41-60 flicker 0.43 / 0.38 / 0.25, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0,
    -- heldReady 309 / 305 / 370): flicker 0.5 -> 0.43, heldReady 439 -> 370
    -- flicker-085 P3 (L872 (2): the opener counts the fight's first off-hand swing, newer than the combat-start
    -- anchor; seeds 1-20 / 21-40 / 41-60 heldReady 309 / 306 / 371, the same after review R3): heldReady 370 -> 371, one
    -- event, seed 58 tick 4: the forecast now equals the truth (15.05 with the off hand's rage), so ours shows the
    -- oracle's sunder_armor waiting 0.20 s for the swing's confirmation where it showed rend before (a disagreement)
    -- re-pin e5a9cd2a2d -> e4ef929e54 (0.9 warrior lane, R6; with gap-as-09, avoid-refund-09 and Execute's
    -- refundNowOnAvoid; seeds 1-20 / 21-40 / 41-60 flicker 0.20 / 0.29 / 0.27 (oracle 0.38 / 0.72 / 0.44), retracted 0
    -- / 0 / 0, readyShort 0 / 0 / 0, heldReady 377 / 282 / 364): flicker 0.43 -> 0.30 (the measured worst + 0.01);
    -- heldReady 371 -> 377 (seeds 1-20 on the gate's boot; 309 at the lane's base d17b7d45e, held ticks mostly Heroic
    -- Strike's `rage.lo>=40` wait at truth 40-41, gap CJ's class (1) above): ab8ad0acc (the re-pin kit: the
    -- damage-taken rage rows and the Execute world rule, not split) moves seed 5's kill 6.4 s, so seeds 6-20 start on
    -- another boot clock (seeds 6, 9, 14, 15, 17, 20 alone on a fresh boot read the same before and after ab8ad0acc;
    -- seed 11 alone 30 -> 14, ab8ad0acc moving that fight directly); the gap-as-09 / avoid-refund-09 merges (field off reads the same) moves seed 1, the boot's
    -- first fight, 21 -> 22 (an Execute held at 102.80)
    -- re-pin ab0f: UW 59.5% x 1 rage rolled per hit (wowsims) + HS/Cleave Reckless charge (R6, the world rolling
    -- Unbridled Wrath from its own stream, eb63112ff; seeds 1-20 / 21-40 / 41-60 flicker 0.35 / 0.26 / 0.23 (oracle
    -- 0.71 / 0.61 / 0.47), retracted 0, readyShort 0, heldReady 484 / 547 / 617; the lane's base b7c26392f read flicker
    -- 0.20 / 0.29 / 0.25, heldReady 377 / 282 / 363): flicker 0.30 -> 0.36 (the measured worst + 0.01), traced (seeds
    -- 1-20, 12 flips over 33.8 min): 7 with the oracle flipping too (5 the queued Heroic Strike cycle: pressed at w0.00,
    -- queued next poll so a long wait shows, back at the swing, e.g. seed 9 t=69.20-69.60; 2 the fight's own), 5 ours
    -- alone (3 the swing row a poll behind truth at a cost edge, e.g. seed 5 t=4.20: truth 7.79 -> 17.05 at a landed
    -- swing, lo 5.50 with the swing pending, rend shown for one poll over sunder_armor, the row lands at 4.40, lo 15.23;
    -- 2 a near-tie at the usability pin, lo 9.99 against rend's 10). Both classes pre-exist; the richer truth rage
    -- (Unbridled Wrath now paid, in 1-rage steps, plus the strike's charge) brings more Heroic Strike casts and more
    -- cost-edge crossings. heldReady 377 -> 617: the old world paid no Unbridled Wrath while the kit credited it, so
    -- the belief ran ahead of truth; truth now pays it and the belief's floor counts no unseen proc (strikeNow's gain
    -- spread = the amount; owner: no optimistic procs), so truth covers a cost before our floor (lo-truth at cost -0.9
    -- -> -1.6 / -2.1 / -2.2, est-truth +0.3 / -0.3 / -0.2): true waits of the floor
    ["Fury L24"] = { flicker = 0.36, flickerK = 0.6, retracted = 0.2, readyShort = 0, heldReady = 617 }, -- flicker 0.35 / 0.26 / 0.23, retracted 0 / 0 / 0 (ab0f, rolled)
    -- none -> floored (gap CI, 2026-10-31; seeds 1-20 / 21-40 / 41-60, measured after the Warrior world resolved every
    -- rank of a kit addition and Revenge's window reached the client (review C1: the world tests the swing's target by
    -- guid, the observer's answers see a proxy of us); oracle flicker 0.42 / 0.42 / 0.45, gap 0.32 / 0.15 / 0.12 under K;
    -- agreement 0.925 / 0.929 / 0.926, unmatched cost 1.0 / 0.6 / 0.6, cooldown 0): the swing-paid rage class
    -- (sunder_armor <-> shield_block, shield_slam <-> thunder_clap, shield_block <-> rend near-ties on a forecast swing's
    -- rage)
    -- heldReady 378 -> 383 (seeds 1-20; 377 with f1f5cf772 reversed): Blood Fury's 2 min cooldown (owner, live 2026-11-02)
    -- readyShort 203 -> 204 (seeds 1-20; 203 at its parent f9065270a): 79f79d52c's floor lift on a yes that shows a
    -- pending swing landed (GAP AK; controller ruling 2026-11-03)
    -- flicker 0.8 -> 0.7 (Task 10b, gap CQ: the not-ready flag keeps a modelled end the GCD covers; seeds 1-20 / 21-40 /
    -- 41-60 0.62 / 0.64 / 0.54, was 0.68 / 0.64 / 0.54)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.05 / 0.15 / 0.03, readyShort 0 / 0 / 0, heldReady 329 / 343 / 311):
    -- flicker 0.7 -> 0.16 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals); readyShort 204 -> 0 (C1, a resource wait inside READY reads 0.06)
    -- 0.7 warrior lane (R6; seeds 1-20 / 21-40 / 41-60: readyShort 1 / 0 / 0, flicker 0.10 / 0.02 / 0.13, heldReady 320 / 331 / 330):
    -- readyShort 0 -> 1, traced: one Shield Slam (17 rage) at 60.80 s pressed with the truth at 16.74, 0.26 short (the belief's lo
    -- above the truth at the cost edge; no cooldown involved)
    -- regen phase lane, cause harness: the indexed poll clock (ledger L606/L667; a rage world has no regen grid) (R6;
    -- seeds 1-20 / 21-40 / 41-60 flicker 0.12 / 0.00 / 0.22, retracted 0.00 / 0.00 / 0.00, readyShort 1 / 0 / 0,
    -- heldReady 321 / 333 / 342): flicker 0.16 -> 0.22, heldReady 383 -> 342
    -- 0.8.5 close (ledger L1132, measured on integ/0.8.5-w2 fa22dc2ad; seeds 1-20 / 21-40 / 41-60 heldReady 344 / 362 /
    -- 359, flicker 0.17 / 0.05 / 0.17, retracted 0 / 0 / 0, readyShort 0 / 0 / 0): heldReady 342 -> 362 (worst set);
    -- cause harness, the world made more correct (L966): accuracy-085-timing dc913a80e pays Bloodrage by Improved
    -- Bloodrage's rank (this build rank 1: 12.5 at once and 1.25 a tick, was 10 and 1, wowsims bloodrage.go), as the
    -- class file already did; ablation (that world change reverted on the same tree) 322 / 336 / 341. Then +2 at
    -- flicker-085 P3 (the opener's swing credit). Seeds 1-20 held ticks in the first 10 s 18 -> 39: the opener's
    -- Bloodrage tick now crosses Demoralizing Shout's 7 (truth 6.2 -> 7.5, t 4.2) with our lo / est / hi at 7.0, so
    -- ours waits one poll (w 1.00, to the next tick) in 12 of 20 fights: the cost-crossing class one poll late. Heroic
    -- Strike's long waits (seed 6 t 124.4-125.4, w 0.99 -> 0.19): its line needs rage.lo >= 20 while our lo sits at
    -- 17.0 (Shield Slam's cost) under the truth 21.9, so it waits for the next swing's credit (lo 27 the poll after
    -- it); the same shape is in the ablated tree (seeds 12, 15) and before the change (seeds 12, 15, 18)
    -- re-pin e5a9cd2a2d -> e4ef929e54 (0.9 warrior lane, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.12 / 0.13 / 0.07,
    -- retracted 0 / 0 / 0, readyShort 0 / 0 / 2, heldReady 351 / 270 / 327, agreement .890 / .906 / .896): flicker 0.22 ->
    -- 0.14 (the measured worst + 0.01) and heldReady 362 -> 351 tightened to the measurement (the step that moved them
    -- not split: the re-pin flip, the world follow, the mana-09 and harness-gcd-edge merges); readyShort 1 -> 2, cause:
    -- the world's main hand follows the new log, 2.35 -> 2.40 s (3becdf582; seeds 41-60 at d17b7d45e and ab8ad0acc read
    -- readyShort 0). 2.40 s is 12 polls, so a swing that lands on a poll stays there: in seed 59 (on the gate's boot) the mob's swing at 164.72 is
    -- parried and parry haste pulls our swing to 20% of 2.40 (0.48), onto the poll at 165.20, then 167.60 ... 177.20. At
    -- 170.00 (Shield Block, 10) and 177.20 (Revenge, 2; that swing misses) the swing is due at the poll's own instant:
    -- ours and the oracle both count it and show the icon at 0.00, and the loop presses before the world resolves the swing
    -- (truth 2.95 / 0.86 before the press; lo 2.13 / 1.99): a same-instant press-order tie in the harness, not a rage
    -- error (refused cost 0.1, unmatched 0.0). Seed 59 alone reads 0 (the mob's swings fall at .69, off the poll grid)
    -- re-pin ab0f: UW 59.5% x 1 rage rolled per hit (wowsims) + HS/Cleave Reckless charge (R6, the world rolling
    -- Unbridled Wrath from its own stream, eb63112ff; seeds 1-20 / 21-40 / 41-60 flicker 0.12 / 0.12 / 0.02 (oracle
    -- 0.42 / 0.50 / 0.59), retracted 0, readyShort 0 / 0 / 0, heldReady 402 / 310 / 335; the lane's base b7c26392f
    -- read 349 / 270 / 320): flicker 0.14 -> 0.13 (the measured worst + 0.01); heldReady 351 -> 402, every set up: the old world
    -- paid no Unbridled Wrath while the kit credited it (est-truth at cost +0.8), so the belief ran ahead of truth and
    -- hid held ticks; truth now pays it (est-truth +0.3 / +0.5 / +0.4) and the belief's floor counts no unseen proc
    -- (strikeNow's gain spread = the amount; owner: no optimistic procs): true waits of the floor
    ["Warrior Protection"] = { flicker = 0.13, retracted = 0.1, readyShort = 0, heldReady = 402 }, -- flicker 0.12 / 0.12 / 0.02, retracted 0 / 0 / 0 (ab0f, rolled)
    -- 1.1 -> 1.3 (gap CE; seeds 1-20 / 21-40 / 41-60: 1.20 / 1.24 / 1.10, was 0.82 / 1.05 / 0.81; oracle 1.42 / 1.70 / 1.25):
    -- the mark on a floor inside the ready wait gives back part of the near-tie gain to close dim never promote (refused
    -- 0.8 / 1.6 / 1.5 -> 0, agreement .970 / .969 / .958 -> .973 / .971 / .971); under base's 1.23 / 1.44 / 1.16 on every
    -- seed set; owner standing approval 2026-10-30
    -- heldReady 383 -> 393 (seeds 1-20; 347 with Druid.lua and druid_world as of its parent): Shifting Power's 8 s
    -- cooldown (hotfix 113554, 8b07b2d58)
    -- re-pin e2842f0a78 (lane feralguardian fix round 1; the adaptive list, Movement on, the DB2 ranges in the Feral
    -- world): seeds 1-20 / 21-40 / 41-60 flicker 0.56 / 0.89 / 0.56 (oracle 0.59 / 0.99 / 0.94), retracted 0 / 0 / 0,
    -- heldReady 236 / 263 / 283, agreement .984 / .983 / .977: flicker 1.3 -> 0.9, heldReady 393 -> 283 (the worst set)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.02 / 0 / 0.02, readyShort 0 / 0 / 0, heldReady 200 / 259 / 266):
    -- flicker 0.9 -> 0.03 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals)
    -- integ/auras 0.8 (R6; druid-fix + claw-shred; the loop world takes wowsims's Feral build: Furor 3/5 and Shredding
    -- Attacks 3/3 (log header 17056=3, 16966=3), the target not attacking the player): seeds 1-20 / 21-40 / 41-60
    -- heldReady 283 / 311 / 285, flicker 0.00 / 0.02 / 0.04 (oracle 0.80 / 0.74 / 0.67), agreement .982 / .980 / .980.
    -- heldReady 283 -> 311 (the worst set): Shred at 42 instead of 60 lands more cost crossings on a poll while the
    -- belief's energy sits one regen tick under the stepped truth, the harness clock artifact (world regen and the
    -- loop's poll clock are float running sums; held ticks at belief-minus-truth -1/-2: 236 / 254 / 221, was 202 / 208 /
    -- 186; at 0: 47 / 57 / 63, was 81 / 60 / 68): exposed, not caused. The old and the new Feral list read identically
    -- in this world. Flicker row NOT moved: the 0.04 at seeds 41-60 is two flips, (1) Shifting Power vs a Clearcasting
    -- Shred, which the oracle makes one poll earlier (Shifting Power's mana forecast trails the crossing), (2) gap AS's
    -- residual (a Rake MISS tied with a swing in flight). Over the row on that set: owner decision pending. Re-measure
    -- when the harness clock lane lands (ledger). Decided by Fable in the owner's place 2026-11-12, owner review
    -- pending (fable-decision-feral-clock.md).
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.00 / 0.02 / 0.02, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 335 / 357 / 350):
    -- heldReady 311 -> 357; flicker kept at 0.03 (the owner's hold, ledger L660 (b)). The clock lane showed the cause
    -- above is the phase of each stepped regen tick against the poll, not the float sums: the base's drift was a lottery
    -- between the belief one tick under and level; a random phase keeps some of each (L667)
    -- heldReady 357 -> 479 (R6, cause Faerie Fire 1.0 s Cat GCD (pin Cat Form passive 3025; owner in game, Rake shown
    -- ~0.5 s late); seeds 1-20 / 21-40 / 41-60 flicker 0.02 / 0 / 0, readyShort 0 / 0 / 0, heldReady 369 / 407 / 479,
    -- agreement .971 / .947 / .975, was .971 / .974 / .974): flicker under the held 0.03
    -- re-pin e5a9cd2a2d -> e4ef929e54 (repin-druid-09 round 4; seeds 1-20 / 21-40 / 41-60 flicker 0.04 / 0.00 / 0.02
    -- (oracle 0.00 / 0.02 / 0.02), retracted 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 301 / 326 / 322, agreement
    -- .977 / .980 / .972): heldReady 479 -> 326. Cause: the world plays the new Feral log's build (Blood Frenzy 2/2's
    -- combo point on a builder's crit, Predatory Discipline's Bite, Shifting Power, Ferocity 5/5's Rake 35); at seeds
    -- 1-20 the round 2 world read flicker 0.02, heldReady 426. Flicker row NOT moved: the owner's hold at 0.03 (L660
    -- (b)); seeds 1-20's 0.04 is red for the owner (both flips traced in repin-druid-09-6.md; green with steady-hold-09, ledger L1328)
    -- re-pin e4ef929e54 -> ab0f00e4fc: wowsims #1087 (repin-ab0f-druid; seeds 1-20 / 21-40 / 41-60 flicker 0.00 / 0.00 /
    -- 0.00 (oracle 0.00 / 0.02 / 0.04), retracted 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 309 / 336 / 314, agreement
    -- .981 / .989 / .982): heldReady 326 -> 336 (the worst set). Cause: #1087's flat Feral list; A/B on one tree (the tip
    -- with the e4ef Feral .simc + make packs), seeds 21-40: old list 321, new list 336
    ["Feral"] = { flicker = 0.03, retracted = 0, heldReady = 336 }, -- 0.56 / 0.89 / 0.56, 0
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 133 / 125 / 136):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.00 / 0.00 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 147 / 154 / 136):
    -- heldReady 140 -> 154
    -- Lane R2 (ledger L1082; seeds 1-20 / 21-40 / 41-60 heldReady 188 / 183 / 171, flicker 0 / 0 / 0): heldReady
    -- 154 -> 188. The world now regenerates 12.61 a second while casting (the export's Reflection 3/3 share; was 0), so
    -- the OOM phase runs Wrath to Wrath at 120 mana; each cost crossing shows one poll late (gap BT / G7: est 1-3 under
    -- the truth, one tick per episode): Wrath held ticks 144 -> 181 at seeds 1-20
    -- 0.8.5 close (ledger L1118, measured on integ/0.8.5-w2 fa22dc2ad; seeds 1-20 / 21-40 / 41-60 heldReady 200 / 184 /
    -- 180, flicker 0 / 0 / 0, retracted 0 / 0 / 0, readyShort 0 / 0 / 0): heldReady 188 -> 200. Cause harness: the
    -- integ rest window (047aa7e82 + 97ba2a8e9, fights start at the true mana) adds to the Reflection share's OOM phase
    -- above, the same cost-crossing class one poll late; reverting the rest change gives 188 (L1118). Balance-cc
    -- (021dece2f, L1119) leaves it flat (199 -> 200)
    -- re-pin e5a9cd2a2d -> e4ef929e54 (repin-druid-09 round 4; seeds 1-20 / 21-40 / 41-60 heldReady 189 / 174 / 174,
    -- flicker 0 / 0 / 0, retracted 0 / 0 / 0, readyShort 0 / 0 / 0, agreement .997 / .997 / .998): heldReady 200 -> 189,
    -- cause not proven: likely mana-09 (043d29b57: the Innervate entry's regen = 5, druid_loop_world.lua:37 / :404, and CN22's percent-cost
    -- rounding), not the re-pin (the Balance .simc changed only its header); likely, not A/B'd
    -- re-pin e4ef929e54 -> ab0f00e4fc (repin-ab0f-druid; the Balance .simc moved only its header): seeds 1-20 / 21-40 /
    -- 41-60 every cell identical (heldReady 189 / 174 / 174, flicker 0 / 0 / 0, agreement .997 / .997 / .998)
    ["Balance"] = { flicker = 0, retracted = 0, heldReady = 189 }, -- 0.03 / 0.05 / 0.07, 0
    -- none -> floored (gap CH, 2026-10-31, measured on d7b972d76 at seeds 1-20 / 21-40 / 41-60; oracle flicker 0.30 /
    -- 0.37 / 0.21): the swing-paid rage class (a forecast swing's gain shows Lacerate or Primal Bite ready; retracted
    -- is lacerate:swing/cost). Applied on the reported branch: Guardian clears M.gate's agreement (0.900 / 0.896 /
    -- 0.881), react and health, but its unmatched cost refusals read 2.3 / 2.5 / 3.5 against the plain bar 3 and its
    -- flicker sits 0.47 / 0.54 / 0.83 over the oracle's against FLICKER_K 0.5, so the gated branch would hold only at
    -- seeds 1-20; neither bar is loosened for it.
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.07 / 0.05, readyShort 0 / 0 / 0, heldReady 325 / 288 / 305):
    -- flicker 1.1 -> 0.08 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals); readyShort 190 -> 0 (C1, a resource wait inside READY reads 0.06)
    -- flicker 0.08 -> 0.23 (floors step, re-pin e5a9cd2a2d; seeds 1-20 / 21-40 / 41-60 read 0.22 / 0.14 / 0.09, retracted 0 / 0 / 0, heldReady
    -- 284 / 308 / 298; the worst + 0.01): TRACED by A/B on one tree: the old-pin Guardian pack gives 0.00 at seeds 1-20, the new adaptive list
    -- (rage-gated Primal Bite / Lacerate / Enrage lines, no rage from hits yet, CN7) 0.22; the Movement opt-in is not it (off: identical 0.22).
    -- The flicker pairs are primal_bite <-> lacerate (929 / 476 ticks), the swing-paid rage class the row already names
    -- regen phase lane, cause harness: the indexed poll clock (ledger L606/L667; a rage world has no regen grid) (R6;
    -- seeds 1-20 / 21-40 / 41-60 flicker 0.19 / 0.17 / 0.07, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0,
    -- heldReady 299 / 285 / 293): flicker 0.23 -> 0.2 (seeds 1-20's 0.1900 is rounded: the raw value sits just over
    -- 0.19), heldReady 330 -> 299
    -- flicker-085 P3 (L872 (2), the opener: the fight's first swing, newer than the combat-start anchor, is credited
    -- one poll after it; seeds 1-20 / 21-40 / 41-60 heldReady 300 / 285 / 294): heldReady 299 -> 300, one event, seed 8
    -- tick 9 (t 4.6): lacerate waiting 0.12 s on that swing's confirmation, truth 19.25 over its 15 cost
    -- 0.8.5 close (ledger L1110 / L1119, measured on integ/0.8.5-w2 fa22dc2ad; seeds 1-20 / 21-40 / 41-60 flicker 0.23
    -- / 0.09 / 0.10, retracted 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 284 / 307 / 286): flicker 0.2 -> 0.24 (the
    -- measured worst + 0.01: the line rounds to two decimals), heldReady 300 -> 307 (the worst set). Cause harness:
    -- the Druid loop world grants Clearcasting at its cast's success (owner in game, L1110; a queued Maul's at its
    -- swing, after the strike), not 0.25 s later (balance-cc 021dece2f), so the fights are re-timed. Traced flips 11 ->
    -- 13 at seeds 1-20: 10 the lacerate <-> primal_bite swing-paid rage class above, one new maul -> primal_bite -> maul
    -- (seed 6 t 122.0-122.6, both free under Clearcasting, swapped one poll at the swing); held ticks the same icons
    -- (lacerate, maul, primal_bite) spread +0..+5 a fight, no single event (balance-cc-085 report)
    -- re-pin e5a9cd2a2d -> e4ef929e54 (repin-druid-09 round 4; seeds 1-20 / 21-40 / 41-60 flicker 0.28 / 0.34 / 0.24
    -- (oracle 0.09 / 0.05 / 0.09), retracted 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 420 / 411 / 396, agreement
    -- .906 / .923 / .907): flicker 0.24 -> 0.35 (the measured worst + 0.01), heldReady 307 -> 420. Cause: the new
    -- adaptive list (its single-target Maul at rage.lo>=20, Lacerate as the filler) and the new Bear build in the world
    -- (Blood Frenzy 1/2, Feral Instinct 3/3, Thick Hide 3/3, no Furor, Ferocity 5/5: Maul 10, Primal Bite 15; a Maul
    -- crit's Primal Fury). Traced (seeds 1-20, 16 flips): maul <-> lacerate 9, maul -> primal_bite 4, the rest
    -- lacerate -> primal_bite and maul -> demoralizing_roar; seed 5 t 60.6-61.2: Maul shows on a forecast swing's rage (lo 15,
    -- maul@0.08), drops for one poll when the swing is due but not yet credited (truth 29.0, lo 15), and returns at
    -- its credit (lo 28.5): the swing-paid rage class this row already names, now on the Maul line
    -- heldReady's two causes, separated (round 5 A/B, loop.tally, on repin-druid-09 13272efff; the world's Maul-crit
    -- Primal Fury, f0b6fc018, off / on): seeds 1-20 / 21-40 / 41-60 off 423 / 423 / 402 (flicker 0.31 / 0.35 / 0.25),
    -- on 420 / 411 / 396 (0.28 / 0.34 / 0.24). The re-pin (list + build) moves it 307 -> 423 (worst, off); the world fix
    -- lowers it 3 / 12 / 6 (its truth now pays the 2.5 the kit's Maul onCrit declares). The row stays the worst on, 420.
    -- retracted 0.7 -> 0 (round 5 review M2: all three sets measured 0, the measured worst)
    -- avoid-refund-09, replay-fncd-09 and replay-flips-09 merged: every cell identical (seeds 1-20 re-run)
    -- 0.9 batch (integ/0.9 a464ca6a4; seeds 1-20 / 21-40 / 41-60 flicker 0.26 / 0.32 / 0.16, retracted 0 / 0 / 0,
    -- readyShort 0 / 0 / 0, heldReady 423 / 411 / 410, agreement .908 / .924 / .907): heldReady 420 -> 423, bisected to gap-as-09
    -- (the swing-avoid give-back, which the Druid lane did not carry), mechanism not traced (no held tick read): the
    -- Druid merge e98ef8506 reads 423, the same minus gap-as's src + harness diff 420; steady-hold-09 moves flicker 0.28 -> 0.26 (its own A/B)
    -- re-pin e4ef929e54 -> ab0f00e4fc: wowsims #1087 (repin-ab0f-druid; seeds 1-20 / 21-40 / 41-60 flicker 0.29 / 0.28 /
    -- 0.24 (oracle 0.09 / 0.04 / 0.10), retracted 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 450 / 381 / 412, agreement
    -- .900 / .912 / .914): heldReady 423 -> 450 (the worst set). Cause: #1087's Guardian list; the A/B proves the #1087
    -- list as a whole (its diff: Enrage under Lacerate's cost, no 5-stack Lacerate refresh line; the old Swipe line
    -- needs 2+ enemies, so it cannot act in the one-mob loop); A/B on one tree (the tip with the e4ef Guardian .simc +
    -- make packs), seeds 1-20: old list 423 (flicker 0.26), new list 450 (0.29). Flicker row unchanged (worst 0.29)
    ["Guardian"] = { flicker = 0.35, retracted = 0, readyShort = 0, heldReady = 450 }, -- 0.77 / 0.91 / 1.03, 0.35 / 0.54 / 0.60
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.00 / 0.00 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 159 / 156 / 150):
    -- heldReady 329 -> 159
    -- re-pin e5a9cd2a2d -> e4ef929e54 (0.9; R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0 / 0 / 0, readyShort
    -- 0 / 0 / 0, heldReady 130 / 142 / 126): unchanged. The pack is logically unchanged for this build (the dropped branch is
    -- covered by `combo_points.current=4&action.mutilate.known`) and the loop world reads no gear: three-tree A/B on seeds
    -- 21-40 (base + mana-09 without the flip / the flip alone / the tip) 142 / 142 / 142, so no re-pin move
    ["Assassination"] = { flicker = 0, retracted = 0, heldReady = 159 }, -- 0 / 0 / 0, 0
    -- 0.1 -> 0.2 (gap CE; 0.15 / 0 / 0.02, was 0.04 / 0 / 0, oracle 0.04 / 0.06 / 0.04): seeds 1-20 flips 2 (round 2)
    -- -> 7, base 15; the extra 5 are fight 8, t 23.0-24.2, sinister_strike vs slice_and_dice, no capped read in either
    -- tree, flips match base's tick for tick; Sinister Strike's entry is gated on `!(buff.slice_and_dice.remains<=2)`,
    -- inferred as an energy wait against that window; base's floor was 0.4; owner standing approval 2026-10-30
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0.04, readyShort 0 / 0 / 0, heldReady 341 / 356 / 350):
    -- flicker 0.2 -> 0.05 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.03 / 0.03 / 0.03, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 156 / 153 / 152):
    -- flicker 0.05 -> 0.03, heldReady 356 -> 156
    -- re-pin e5a9cd2a2d -> e4ef929e54 (0.9; wowsims 41976091ed; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0 / 0 / 0,
    -- readyShort 0 / 0 / 0, heldReady 155 / 160 / 152): flicker 0.03 -> 0.01 (the measured worst + 0.01), heldReady 156 -> 160 (the
    -- worst set). Cause: only the dropped 4-point Eviscerate branch acts for this build (no Serrated Blades, no Hemorrhage); A/B
    -- seeds 21-40 without the flip / the flip alone / the tip 139 / 160 / 160, 14 of 20 fights +1..+4 (4 at -1..-2): every held tick on both
    -- sides is the cost-lag class (energy.lo under the cost, truth at it, wait ~0.1 s); held Sinister Strike 113 -> 142, Eviscerate
    -- 13 -> 6: finishing at 5 points takes one more builder a cycle, so more Sinister Strike cost crossings
    ["Combat"] = { flicker = 0.01, retracted = 0, heldReady = 160 }, -- 0.15 / 0 / 0.02, 0
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 382 / 364 / 363):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.03 / 0.00 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 201 / 192 / 168):
    -- flicker 0 -> 0.03, heldReady 382 -> 201
    -- re-pin e5a9cd2a2d -> e4ef929e54 (0.9; wowsims 41976091ed; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0 / 0 / 0,
    -- readyShort 0 / 0 / 0, heldReady 194 / 239 / 197): flicker 0.03 -> 0.01; heldReady 201 -> 239 (the worst set, seed-noise rule, ledger L1245).
    -- Only the Hemorrhage term acts for this build (Death Mark shuts Eviscerate). A/B seeds 21-40 without the flip / the flip
    -- alone / the tip 197 / 239 / 239: seed 33 alone 8 -> 39, the other 19 fights +11 net. Seed 33 (traced): a Rupture pressed
    -- at t 23.0 is avoided (the world keeps the points, applies no debuff), our belief keeps the modelled Rupture for its whole
    -- duration (the known avoided-debuff class, ledger L317), so from t 34.6 at 5 points our Rupture waits 6.4 s while the
    -- oracle's (raw debuff read) shows it ready: 27 held ticks; the flip only re-times that avoid into a fight; seeds 1-20 (this gate) read 194
    ["Subtlety"] = { flicker = 0.01, retracted = 0, heldReady = 239 }, -- 0.02 / 0 / 0, 0 (gap CE)
    -- 0.1 -> 0.2 (Task 5b, gap BV: the world takes the export's Resourcefulness 2/2, so wowsims's 60% cut makes the
    -- strikes cheap; seeds 1-20 / 21-40 / 41-60: 0.20 / 0.02 / 0.07, was 0.05 / 0 / 0; oracle 2.18 / 1.68 / 2.26, was 0):
    -- no longer mana-gated, Raptor Strike comes up on its cooldown end beside Wing Clip or Strider Kick, and in its last
    -- 0.5 s the client's not-ready flag holds our ready time at now + CD_PROBE while the truth counts down, so the other
    -- shows one tick (every one of the 17 flips; Fire Blast's CD_PROBE class in layout.md); owner standing approval
    -- 2026-10-30
    -- 0.2 -> 0.3 (Task 12, the world prices Strider Kick as the pack does: 0.0581 of the class file's base mana 1720 =
    -- 99.9, x 0.4 under Resourcefulness = 39.97, wowsims's log 39.6, not 0.0581 of the world's 5000-mana pool = 290; seeds
    -- 1-20 / 21-40 / 41-60: 0.27 / 0.08 / 0.15, was 0.20 / 0.02 / 0.07; oracle 2.03 / 2.00 / 1.96, agreement 0.987 /
    -- 0.988 / 0.988, was 0.978 / 0.978 / 0.981): Strider Kick now comes up with Raptor Strike's cooldown and the same
    -- raptor_strike -> wing_clip -> raptor_strike flip rests on CD_PROBE (all 16 flips of seeds 1-20 traced, each at the
    -- tick before Raptor Strike's cooldown ends); owner standing approval 2026-10-30
    -- 0.3 / 258 -> 0.2 / 254, readyShort 1 (forever-gates fix round 1, 2026-10-31: Mongoose Bite's window reaches the
    -- client, the Hunter world tests the swing's target by guid; seeds 1-20 / 21-40 / 41-60, was 0.27 / 0.08 / 0.15 and
    -- 258 / 223 / 242 with the bite never usable): the bite's icon takes the ticks after our dodge, so the
    -- strider_kick <-> wing_clip near-ties fall (197 / 190 / 192 -> 168 / 151 / 170 pairs) and its own held ticks
    -- arrive (by key at 21-40 / 41-60: mongoose_bite 19 / 20, wing_clip 218 / 233 -> 209 / 221, raptor_strike 5 / 9
    -- -> 4 / 13)
    -- 0.2 / 254 -> 1.6 / 400, flickerK 1.5 (re-pin e2842f0a78, Task 19, R6; seeds 1-20 / 21-40 / 41-60: flicker 1.51 /
    -- 1.10 / 0.93, oracle 0.07 / 0.02 / 0.02, held 400 / 348 / 347, agreement .966 / .972 / .971, dps A/B .971 / .973 /
    -- 1.017; identical with R61 (7a8972d4c, its retries compiling)): wowsims's new Wing Clip line
    -- `(!action.strider_kick.known|cooldown.strider_kick.remains>1.5)` takes away the always-ready Wing Clip that won
    -- every near-tie of the strikes. Ablation (seeds 1-20, the generated Wing Clip line without that prefix): held 400 ->
    -- 255, flips 91 -> 16. What it exposes are two named classes: Raptor Strike's and Strider Kick's last 0.5 s under
    -- CD_PROBE (the not-ready flag holds ours at now + 0.5 while the oracle counts down; held ticks at 21-40: 52 of 348)
    -- and, at a dry pool (mana 32-41), the two strikes' near-tie at their mana crossing (costs 40 and 39.6) read from a
    -- floor a few units under the truth (gap BT; held 296 of 348; flips 79 of 91 at seeds 1-20 raptor <-> strider, 30
    -- of them beside a CD_PROBE 0.50). The oracle reads the exact pool, so the gap over it is ours. Owner FYI
    -- (R67, controller: ship the new pack with this measured limit, no pack deviation, no old-pin fallback)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.03 / 0.02 / 0.02, readyShort 0 / 1 / 1, heldReady 323 / 304 / 311):
    -- flicker 1.6 -> 0.04 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals); flickerK 1.5 dropped (its cause, the probe and the near-tie flips, gone)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.08 / 0.05 / 0.13, retracted 0.00 / 0.00 / 0.00, readyShort 1 / 1 / 1, heldReady 267 / 294 / 299):
    -- flicker 0.04 -> 0.14, heldReady 400 -> 299
    -- rest window lane (L987 addendum, L1069), cause harness: the between-fight rest keeps the five-second window
    -- (047aa7e82): fights start at the true mana, so fights are re-timed; same cost/cooldown near-tie class (seeds 1-20
    -- / 21-40 / 41-60 flicker 0.18 / 0.05 / 0.08, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 1 / 1, heldReady 280 /
    -- 280 / 276): flicker 0.14 -> 0.19
    -- flicker-085 P1 (L755 / ruling L960: a mana pool with no tick seen pads nothing; seeds 1-20 / 21-40 / 41-60
    -- heldReady 292 / 313 / 323): heldReady 299 -> 323. At the gap BT cost crossing (floor pinned at cost - 1.01,
    -- truth just over) raptor_strike's wait no longer jumps a tick, so ours shows the oracle's raptor_strike waiting
    -- 0.23 s where strider_kick showed before (agreement rises).
    -- 0.19 -> 0.03, heldReady 323 -> 314: FINAL, measured on integ/0.8.5-w2 after the Survival-moving lanes merged
    -- (Serpent Sting debuff at landing, flicker-085, timing merges; L1037/L1103; close-085 seeds 1-20 / 21-40 / 41-60
    -- flicker 0 / 0 / 0.017, heldReady 314 / 283 / 313): the worst printed + 0.01, the worst set
    -- 0.03 -> 0.09 (re-pin e5a9cd2a2d -> e4ef929e54 with mana-09's CN22, the percent cost rounded to the nearest whole
    -- before the cut; seeds 1-20 / 21-40 / 41-60 flicker 0.08 / 0.07 / 0.07, oracle 0.20 / 0.10 / 0.13, heldReady 269 /
    -- 279 / 277, readyShort 0 / 1 / 0, agreement .977 / .983 / .978): Strider Kick 0.0581 of 1720 rounds to 100, so
    -- under Resourcefulness 2/2 it costs 40 (was 39) and ties Raptor Strike's 40; a queued Raptor Strike's mana now shows
    -- Strider Kick for one poll and flips() no longer excludes it. Traced in mana-09's review round (L1210/L1212: the
    -- oracle shows the same flips, its own flicker rose 0.05 -> 0.13 with it); the measured worst + 0.01
    -- flicker 0.09 -> 0.11, heldReady 314 -> 112 (re-pin e5a9cd2a2d -> e4ef929e54, repin-hunter-09 fix round 1: the
    -- world's pool and regen from its e4ef929e54 log, 3555 mana, 12.00 mp5 + 17.50 spirit with Resourcefulness's 50%
    -- share while casting (was 5000 and spirit 15.88, no mp5: nothing while casting), so the pool sits at the strikes'
    -- 40 less often; seeds 1-20 / 21-40 / 41-60 flicker 0.08 / 0.0999 / 0.08, oracle 0.12 / 0.13 / 0.25, heldReady
    -- 112 / 102 / 76, readyShort 0 / 0 / 0, agreement .993 / .984 / .989). Flicker: the Strider Kick / Raptor Strike
    -- 40-mana tie (L1210, the oracle flips more). Held ticks traced per tick (seeds 1-20): the near-cost edge, the pool
    -- dry at a cost with our est a few mana under truth (raptor_strike 62 at 40-41, wing_clip 31, strider_kick 13,
    -- hunters_mark 5, mongoose_bite 1; cooldowns and Hunter's Mark equal in ours, the oracle and the world): the worst
    -- printed + 0.01, the worst set
    ["Survival"] = { flicker = 0.11, retracted = 0, readyShort = 1, heldReady = 112 }, -- 1.51 / 1.10 / 0.93, 0 (oracle 0.07 / 0.02 / 0.02), 400 / 348 / 347
    -- wowsims's non-weave builds (owner 2026-11-12, ledger L661), first measured (R6; seeds 1-20 / 21-40 / 41-60, steady
    -- icons on): flicker 0 / 0 / 0 each (Survival Melee's oracle 0.02 / 0.03 / 0.02, the others' 0), retracted 0,
    -- readyShort 0; heldReady the Hunter rows' cost-crossing class (the floor a few units under the truth, gap BT),
    -- not traced per tick; agreement .993 or better each set (Survival Melee .993). Re-measured after the seeded regen
    -- phase (L667, cause harness), seeds 1-20 / 21-40 / 41-60 flicker 0 each, retracted 0, readyShort 0; floors the
    -- worst of the two measurements (first, then after L667)
    -- heldReady 128 -> 132 (re-pin e5a9cd2a2d -> e4ef929e54: wowsims's hawk rotation, turret_hawk.apl.siml: Summon Hawk
    -- twice, then Arcane Shot, each 189 mana, Sniper Shot gone; seeds 1-20 / 21-40 / 41-60 heldReady 130 / 132 / 104,
    -- flicker 0 / 0 / 0, retracted 0, readyShort 0, agreement .994 / .995 / .997, refused [] (no on-cooldown Summon Hawk
    -- since its 5.4 s after an Arcane Shot). NOT traced per tick: the lines' wait counters put the held ticks on the new
    -- list's summon_hawk 61 / 60 / 54 and arcane_shot 26 / 20 / 25 (class "unknown"; the old list pressed neither), with
    -- est - truth at disagreements +19 / +34 / +33 (the opposite sign to the other Hunter rows), so the mechanism is
    -- open; the move rides the hawk rotation): the worst set
    -- heldReady 132 -> 237 (re-pin e5a9cd2a2d -> e4ef929e54, repin-hunter-09 fix round 1: the world's pool and regen
    -- from its log, 3330 mana, casting 21.15 = 12.40 mp5 + Bestial Discipline's half of 17.50 spirit (was 5000 and 7.94
    -- / 7.94), and The Beast Within in the world, every cost x0.5 for 18 s after Bestial Wrath (owner L1105); seeds
    -- 1-20 / 21-40 / 41-60 heldReady 226 / 236 / 237, flicker 0, retracted 0, readyShort 0, agreement .997 each).
    -- Traced per tick (seeds 1-60, this tip and d17b7d45e): the near-cost edge, the pool dry at the 189 cost (94.5 under
    -- The Beast Within) with our est 2-3 mana under truth, our wait 0.07-0.42 s, the oracle's 0 (summon_hawk 146 / 150 /
    -- 150, arcane_shot 69 / 73 / 74); the smaller pool puts more ticks at the edge (d17b7d45e: arcane_shot 110-118 of
    -- 118-125). The +19..+34 est - truth above was the world charging full price inside the window the belief halved.
    -- rapid_fire 11 / 13 / 13: Rapid Fire behind an Aimed Shot whose 310 is paid at the cast's end waits from the
    -- belief's floor at a fight-opening pool no read has pinned (t 8.6: lo 381.9, (100 - (lo - 310)) / 21.15 = 1.33
    -- s; the oracle's exact 430.6 covers both; central, repin-hunter-09-3): the worst set
    -- re-pin e4ef929e54 -> ab0f00e4fc (Hunter lane; seeds 1-20 / 21-40 / 41-60, retracted 0, readyShort 0 each, flicker 0
    -- but Survival's; the worst set of the three): the worlds take the new logs' pools and regen (turret builds 3750 mana
    -- and 15.40 mp5, was 3330 and 12.40: the builds' mana consumables and one gear slot; Survival Melee 3915 and 12.00,
    -- was 3270 and 12.40; Survival 3975, was 3555), Survival Melee's off hand 1.3 s and bow 2.4 s; then (fix round) the
    -- worlds' Hunter trainer-taught as wowsims's (hunter_world.lua BOOK: Serpent Sting rank 8's 230, was rank 9's 250),
    -- which re-times every pool. BM Turret 237 -> 249 (234 / 235 / 249), flicker 0 (the lane's pre-fix 0.017 a set, seed
    -- 13's aimed_shot -> arcane_shot -> aimed_shot at 9.0 s, traced: a 0.14 s Aimed-mana / Arcane-cooldown tie under the
    -- belief's lo 4 mana short; gone on the trainer-rank pool), Marksmanship Turret 213 -> 218 (218 / 218 / 211), Survival
    -- Turret 236 -> 279 (246 / 270 / 279), Survival Melee 361 -> 290 (280 / 285 / 290); Survival holds (flicker .017 /
    -- .033 / .067, oracle .133 / .200 / .283, heldReady 92 / 93 / 71, under 0.11 and 112). The held ticks, classified per
    -- tick (fix round, the worst sets): BM 41-60, 248 of 249 at truth within 5 mana of the cost, 247 shown under 0.3 s
    -- late (summon_hawk 170, arcane_shot 66, serpent_sting 9, aimed_shot 3, hunters_mark 1): the near-cost edge (the
    -- secret pool's lower bound a few mana under the truth at the crossing); Survival Turret 41-60, 263 of 279 the same
    -- edge (arcane_shot 258, hunters_mark 5), 16 rapid_fire at truth 60+ over the cost, 12 of them 3 s+ late: the unpinned
    -- fight-opening floor (repin-hunter-09-3, below)
    ["Beast Mastery Turret"] = { flicker = 0, retracted = 0, heldReady = 249 }, -- heldReady 125 / 128 / 118; after L667 121 / 111 / 127
    -- Marksmanship Turret, 0.8.5 close (ledger L1132, measured on integ/0.8.5-w2 fa22dc2ad; seeds 1-20 / 21-40 / 41-60
    -- heldReady 132 / 115 / 108, flicker 0 / 0 / 0, retracted 0 / 0 / 0, readyShort 0 / 0 / 0): heldReady 118 -> 132
    -- (the worst set). Cause harness: ladder-usable-085 cc02f47e5's between-fight rest window (fights start at the true
    -- mana, re-timed; the same cause as Balance, L1118; bisected 113 at its parent -> 132); the Hunter cost-crossing
    -- class, seeds 1-20 held ticks arcane_shot 100 -> 118, rapid_fire 4 -> 8, hunters_mark 9 -> 6, +1..+4 a fight
    -- heldReady 132 -> 213 (re-pin e5a9cd2a2d -> e4ef929e54, repin-hunter-09 fix round 1: the world's pool and regen
    -- from its log, 3330 mana, 12.40 mp5 + 17.50 spirit, Rapid Recuperation's 50% share while casting for 15 s after
    -- each Serpent Sting (was 5000 and spirit 15.88, no mp5); seeds 1-20 / 21-40 / 41-60 heldReady 201 / 204 / 213,
    -- flicker 0, retracted 0, readyShort 0, agreement .998 / .999 / .995). Traced per tick (seeds 1-20): the near-cost
    -- edge, arcane_shot 199 at mana 166-169 against its 166.32 (our est a few mana under truth, the oracle's wait 0),
    -- hunters_mark 2; the smaller pool sits at the edge more often: the worst set
    ["Marksmanship Turret"] = { flicker = 0, retracted = 0, heldReady = 218 }, -- heldReady 101 / 116 / 104; after L667 118 / 102 / 101 (116 -> 118, cause harness)
    -- heldReady 117 -> 236 (re-pin e5a9cd2a2d -> e4ef929e54, repin-hunter-09 fix round 1: the world's pool and regen
    -- from its log, 3330 mana, 12.40 mp5 + 17.50 spirit, Resourcefulness's 50% share while casting (was 5000 and
    -- spirit 15.88, no mp5); seeds 1-20 / 21-40 / 41-60 heldReady 210 / 236 / 186, flicker 0, retracted 0, readyShort
    -- 0, agreement .997 / .999 / .997). Traced per tick (seeds 1-20): the near-cost edge, arcane_shot 194 at mana
    -- 189-192 against its 189, hunters_mark 2; rapid_fire 14 = 11 + 1 + 2: 11 are Rapid Fire behind an Aimed Shot whose
    -- 310 is paid at the cast's end, waiting from the belief's floor at a fight-opening pool no read has pinned (t 8.6:
    -- lo 352.2, (100 - (lo - 310)) / 12.40 = 4.67 s; the oracle's exact 513.3 covers both; central, repin-hunter-09-3);
    -- 1 is untraced (fight 15 at t 8.80, 3.23 s at truth 101; plausibly the same unpinned floor, not shown); 2 are near-cost edge
    -- ticks (0.09 s, 0.07 s): the worst set
    ["Survival Turret"] = { flicker = 0, retracted = 0, heldReady = 279 }, -- heldReady 115 / 117 / 106; after L667 104 / 103 / 105
    -- heldReady 183 -> 361 (re-pin e5a9cd2a2d -> e4ef929e54, repin-hunter-09 fix round 1: the world's pool and regen
    -- from its log, 3270 mana, 12.40 mp5 + 16.75 spirit (was 5000 and spirit 15.88, no mp5); seeds 1-20 / 21-40 /
    -- 41-60 heldReady 346 / 342 / 361, flicker 0 (oracle 0.13 / 0 / 0.02), retracted 0, readyShort 0, agreement .992 /
    -- .995 / .996). Traced per tick (seeds 1-20): the near-cost edge, wing_clip 301 at mana 80-83 against its 80,
    -- mongoose_bite 37, hunters_mark 8 (cooldowns and Hunter's Mark equal in ours, the oracle and the world): the worst
    -- set
    ["Survival Melee"] = { flicker = 0, retracted = 0, heldReady = 290 }, -- heldReady 166 / 183 / 177; after L667 173 / 169 / 174
    -- 0.1 -> 0.9 (Task 7; seeds 1-20 / 21-40 / 41-60: 0.47 / 0.88 / 0.77, was 0.04 / 0 / 0.02; oracle 0.66 / 1.23 / 1.01):
    -- wowsims's logged regen (Ret 8.25/s casting) runs the world at an empty mana pool; the oracle's flicker rose too; our
    -- extra disagreement is gap AB (lo = 0 at an empty pool vs truth ~16: Judgement vs Holy Strike); controller ruling
    -- 2026-10-30 while the owner was away
    -- 0.9 -> 0.6 (gap CE, the facade's whole-number read gone; oracle 0 / 0.29 / 0)
    -- 0.6 -> 0.5 (decision 63's rule, gap CE, the capped read follows the fold)
    -- readyShort 1: judgement at wait 0.04 with lo 0.04 under truth, no short answer yet, the oracle showing the same wait
    -- 0.5 -> 1.2, flickerK 1.0 (this label only; re-pin e2842f0a78, Task 17, ruling R60; seeds 1-20: 1.13, oracle 0.21,
    -- gap 0.92): the Unsealed Wrath APL guards Judgement and Holy Strike 0.1 s each side of a main-hand swing; a ready
    -- time in the guard's pre-swing half is rechecked only at swing + 0.01 s (the engine's swing-clock recheck,
    -- Engine/Sim/Scripts.lua), where the other half is false, so the line drops for one tick. Our floor-paced mana wait
    -- (gap BT) slides the ready time through that half far more often than the oracle's. Probe (both rechecks, swing +
    -- 0.01 and + 0.11, lane-ret-wrap-recheck-experiment.patch): flips 59 -> 4, oracle 11 -> 1. Re-floor after R61.
    -- 1.2 -> 0.1, flickerK dropped (R61, the swing-clock `<`/`<=` guard rechecked at its window end, central-swing-recheck
    -- 6bf4474f6 + 7a8972d4c; seeds 1-20 / 21-40 / 41-60: 0.04 / 0.04 / 0.04, oracle 0.04 / 0.00 / 0.11; agreement 0.999 / 0.999 /
    -- 0.996); heldReady 271 -> 241 (230 / 241 / 227); readyShort 1 (1 / 0 / 0)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 98 / 99 / 100):
    -- flicker 0.1 -> 0 (S, steady icons on by default); readyShort 1 -> 0 (C1, a resource wait inside READY reads 0.06)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.00 / 0.00 / 0.02, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 92 / 87 / 72):
    -- flicker 0 -> 0.02, heldReady 241 -> 92
    -- re-pin e5a9cd2a2d -> e4ef929e54 (R6; seeds 1-20 / 21-40 / 41-60 flicker 0.00 / 0.02 / 0.00, retracted 0 / 0 / 0,
    -- readyShort 0 / 0 / 0, heldReady 159 / 177 / 155, agreement .997 / .991 / .987): heldReady 92 -> 177 (the worst
    -- set) in two steps, both the cost-edge lag (every held tick has the truth over the cost, lo about 2 mana under it).
    -- CN22 re-times it by Judgement 90 -> 91 (96 / 97 / 101, ledger L1210); the new log's regen (its gear lost the
    -- Soulforge pieces: 17.0 a second outside the rule, 5.1 casting, was 21.9 / 8.25) keeps the world mana-dry longer
    -- (idle 0.81 -> 0.855), so more crossings, each waited out slower (seeds 21-40 held ticks 97 -> 177, mean wait 0.124 ->
    -- 0.177 s, mean truth - lo 2.23 -> 2.05). Unsealed Wrath's 0.1 s proc cooldown is inert here (reverted: 177, the same)
    ["Retribution"] = { flicker = 0.02, retracted = 0, readyShort = 0, heldReady = 177 }, -- 0.04 / 0.04 / 0.04, 0 (oracle 0.04 / 0.00 / 0.11)
    -- 0.5 -> 0.8 (Task 7; seeds 1-20 / 21-40 / 41-60: 0.54 / 0.71 / 0.49, was 0.45 / 0.03 / 0.68; oracle 0.59 / 1.81 / 1.73):
    -- wowsims's logged regen (Prot 0 casting) runs the world at an empty mana pool; the oracle's flicker rose to 0.59-1.81;
    -- our extra disagreement is gap AB (lo = 0 at an empty pool vs truth ~16: Judgement vs Holy Strike, agreement .99 ->
    -- .91); controller ruling 2026-10-30 while the owner was away. Supersedes the 2026-10-29 owner ruling (seed chaos at
    -- 41-60 after Task 4a, floor kept): that note's near-tie wobble is gap AB too; steady icons (experimental) is the
    -- player's remedy.
    -- 0.8 -> 0.2 (gap CE, the facade's whole-number read gone): most of the flicker the two notes above blame on gap AB
    -- was that read; gap AB's agreement cost stands
    -- heldReady 252 -> 326 (seeds 1-20; 243 with Paladin.lua and paladin_world as of its parent): Swift Judgement as a
    -- second Judgement on its own 60 s cooldown (hotfix 113554, 66573cf37)
    -- re-pin e2842f0a78 (Task 12; the world's Protection takes the preset's Shieldsworn, R28: Holy Strike every 6 s):
    -- agreement 0.916 / 0.897 / 0.901 -> 1.000 / 1.000 / 1.000 (gap AB's Judgement vs Holy Strike near-tie gone with the
    -- cadence); flicker 0.2 -> 0.1 (0.02 / 0.02 / 0.02, oracle 0.00 / 0.05 / 0.03); heldReady 326 -> 296 (296 / 284 /
    -- 293, was 326 / 285 / 310)
    -- heldReady 296 -> 289 (R31, Holy Shield rank 3 costs 195, not 240: 253 / 289 / 275); agreement 1.000 / 1.000 /
    -- 1.000 -> 0.981 / 1.000 / 0.986, top judgement -> holy_strike: lo 60-83 with hi 110-133 at Judgement's 90, truth
    -- 90-115 before the press, casting regen 0; gap AB family at a 50-wide band (R39)
    -- heldReady 289 -> 296 (Holy Shield rank 4, 1239570 at 240 mana from level 60: the owner's in-game tooltips
    -- 2026-11-06; the world's level-60 Protection casts it, R31's 195 rank 3 is no longer its top rank): 296 / 284 /
    -- 293, R31's pre-change values at the same price; agreement 1.000 / 1.000 / 1.000; flicker 0.02 / 0.02 / 0.02
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 118 / 88 / 80):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.00 / 0.00 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 287 / 265 / 233):
    -- heldReady 296 -> 287
    -- re-pin e5a9cd2a2d -> e4ef929e54 (R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0 / 0 / 0, readyShort
    -- 0 / 0 / 0, heldReady 186 / 177 / 198, agreement 1.000 / 1.000 / 1.000): heldReady 287 -> 198 (the worst set). 178 /
    -- 183 / 153 with the flip and CN22 alone; the rest is the new log's regen (16.5 outside the rule, was 17.38: kit seed
    -- and world), the only later change Protection runs (no Twist of Light: Unsealed Wrath's cooldown never runs)
    -- Re-measured after the review fixes (Protection keeps its own 16.5 / 0 seed with the Holy Shock seed gated on
    -- Retribution; mana-09 e2d7b1187 merged): 186 / 177 / 198, flicker 0, retracted 0, readyShort 0: unchanged
    ["Protection"] = { flicker = 0, retracted = 0, heldReady = 198 }, -- 0.02 / 0.02 / 0.02, 0 (oracle 0.38 / 0.00 / 0.00)
    -- new pack 2026-11-12 (R6 first measurement; seeds 1-20 / 21-40 / 41-60 flicker 0.00 / 0.00 / 0.00 (oracle 0 / 0 /
    -- 0.08), retracted 0, readyShort 0 / 0 / 0, heldReady 65 / 70 / 94, agreement .998 / .999 / .997): flicker 0.01 (the
    -- measured worst + 0.01: the line rounds to two decimals), heldReady 94 (the worst set)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.06 / 0.00 / 0.00 (oracle 0 / 0 / 0), retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0,
    -- heldReady 53 / 80 / 67, agreement .994 / .994 / .999): flicker 0.01 -> 0.07 (a rise: our flips, the oracle's 0),
    -- heldReady 94 -> 80. Traced (2 flips, seeds 1-20; none in 21-40, 41-60): gap AB's class, a mana wait against a
    -- cooldown countdown at a near-tie, one regen tick from the cost. Fight 3 t 96.4: Judgement (off cooldown, its
    -- mana short until the regen tick at 96.8; truth 80.0) -> Holy Strike (0.2 s cooldown left) for one poll; fight 6 t 21.8: Exorcism (mana
    -- wait) <-> Judgement (0.4 s left). The seeded regen phase moved where the ticks fall against the costs. Core, not
    -- the pack (wowsims's own order; no pack line reads the tie)
    -- cov-hunter-paladin (controller-approved re-floor; seeds 1-20 / 21-40 / 41-60 heldReady 94 / 96 / 104, agreement
    -- .980 / .983 / .987, flicker 0.00 / 0.00 / 0.00, retracted 0 / 0 / 0, readyShort 0 / 0 / 0): heldReady 80 -> 110 (the
    -- worst set + 6). Cause: Purifying Power's game-true Exorcism cadence (2/2: 15 -> 10.05 s, pin 429144) exposes gap
    -- AB, a mana wait racing a cooldown or seal countdown with the belief 0-5 mana under truth (judgement -> holy_strike,
    -- exorcism -> seal_of_righteousness / holy_strike / judgement). Traced (now-state, seeds 1-6 and 41-60): the belief's
    -- cooldowns and seal timers match the oracle in all 307 confused ticks; only mana differs. Flicker floor unchanged
    -- re-pin e5a9cd2a2d -> e4ef929e54 (R6; seeds 1-20 / 21-40 / 41-60 flicker 0.00 / 0.00 / 0.00 (oracle 0 / 0.25 / 0),
    -- retracted 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 93 / 93 / 81, agreement .994 / .997 / .997): flicker 0.07 ->
    -- 0.01 (the measured worst + 0.01), heldReady 110 -> 93 (the worst set). 66 / 68 / 73 with the flip and CN22 alone;
    -- the rest is the world's regen from the new log, 17.59 / 7.54 (was 18.37 / 7.88). Traced, seeds 1-20: with that
    -- world reverted 66, A's line exactly; with the kit seed reverted 93, the same line (the out-of-combat read replaces
    -- a seed that differs from it); the held ticks are the cost-edge lag (truth over the cost, lo 1.6-3.1 under):
    -- holy_strike 6 -> 22, seal_of_righteousness 14 -> 32. Then the build's own seed (17.59 / 7.54, its log): 77 / 93 /
    -- 93, flicker 0 / 0 / 0, agreement .998 / .997 / .998, the worst set unchanged. Traced (fight 1, tick by tick): a seed
    -- equal to the game's rate makes the out-of-combat read no news (Sources/Power.lua skips a read equal to the
    -- belief's), so the declared spread band stays (lo 2-13 under est from the first tick) where a differing seed's read
    -- collapsed it; the seed moves which crossings hold, not the class. The regen-read band fix (89d1613b5, L1341: an
    -- equal read narrows a still-open band) and mana-09 e2d7b1187 merged: 93 / 93 / 81 (L1342), the floor holds
    ["Holy Shock"] = { flicker = 0.01, retracted = 0, readyShort = 0, heldReady = 93 },
    -- 0.1 -> 0.2 (Task 4, wowsims's Shaman regen in): estimate pinned at the crossing floor, 3-8 mana low at ~30 mana/s;
    -- a pick ~0.23 s from its cost slips a tick (owner ruling 2026-10-29, fallback of option 2)
    -- 0.2 -> 0.3 (Task 11, Mana Spring Totem's mp5 as its own entry; seeds 1-20 / 21-40 / 41-60: 0.10 / 0.25 / 0.22, was
    -- 0.12 / 0.07 / 0.1996; oracle 0.13 / 0.00 / 0.02): Task 11 re-times Enhancement's fights (the world's starting mana
    -- now truthful to the log) onto Stormstrike / Lightning Shield near-ties where the estimate sits 2-3 mana under truth
    -- at the crossing floor (Task 4's mechanism, gap BT; the swap test shows the Mana Spring entry is not involved); the
    -- one-poll-wider near-cost window (task-4c-wip.patch) fixes it but loosens Protection and Affliction instead;
    -- owner-approved standing named-cause policy, 2026-10-30 (controller ruling (b), task-4c-report.md)
    -- 0.3 -> 0.2 (decision 63's rule, gap CE; most of the Task 11 near-ties above went with the whole-number read)
    -- heldReady 230 -> 256 re-pin e2842f0a78 (lane 15, R6; seeds 1-20: 256, flicker 0.02, retracted 0; 249 at Fire
    -- Nova's DB2 520): the build's own list (Magma Totem 40 s, Windfury Totem, Fire Nova the filler at wowsims's 375,
    -- R57a) and the world's mana from the Skyborne log (6565, 12.8 / 31.25, was 5000 / 4.8 / 28.62)
    -- 0.7 re-pin (R6; seed set 1-20, steady icons on): heldReady 256 -> 152, flicker 0.00 (oracle 0.00), agreement 0.912, the
    -- mana-wait tie named at M.REACT_P90_BY (the held count fell with it)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 145 / 145 / 147):
    -- flicker 0.2 -> 0 (S, steady icons on by default)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.13 / 0.10 / 0.05, retracted 0.00 / 0.00 / 0.00, readyShort 1 / 0 / 0, heldReady 136 / 138 / 126):
    -- flicker 0 -> 0.14, readyShort 0 -> 1, heldReady 152 -> 138
    -- re-measured on 246abf322 (L757 M2): flicker 0.13 / 0.12 / 0.05, heldReady 136 / 138 / 126 (the bar is the worst
    -- set); every flip is a mana wait against Stormstrike's cooldown at the mana crossing: the tick pad, with no tick
    -- seen, jumps between nothing and a whole tick from one poll to the next (Engine/Sim/State.lua tickReach; flicker-085).
    -- With no pad at no tick seen (b97e59df0, ruling L960): flicker 0.02 / 0.03 / 0.08, heldReady 132 / 136 / 129
    -- rest window lane (L987 addendum, L1069), cause harness: the between-fight rest keeps the five-second window
    -- (047aa7e82): fights start at the true mana, so fights are re-timed; same cost/cooldown near-tie class (seeds 1-20
    -- / 21-40 / 41-60 flicker 0.20 / 0.15 / 0.07, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 1 / 0, heldReady 127 /
    -- 128 / 132): flicker 0.14 -> 0.21
    -- 0.21 -> 0.08: FINAL, measured on integ/0.8.5-w2 after the merges (close-085 seeds 1-20 / 21-40 / 41-60 flicker
    -- 0.033 / 0.05 / 0.067): the worst printed (0.07) + 0.01; the lanes' flicker-085 no-tick-pad change settled it
    -- re-pin e5a9cd2a2d -> e4ef929e54 (lane repin-shaman-09, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.00 / 0.02 / 0.00, retracted
    -- 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 146 / 128 / 130, agreement .990 / .992 / .996, react p90 0 / 0 / 0):
    -- flicker 0.08 -> 0.03 (the worst, 0.017, + 0.01), readyShort 1 -> 0, heldReady 138 -> 146 (the worst set). Cause:
    -- Stormstrike 8 s (hotfix push 113722), the world's Windfury Totem strike and the Five Thunders gear's 6250 mana /
    -- 25.75 / 12.0 re-time every fight; the held ticks are the same Flame Shock cost crossing against Stormstrike's
    -- cooldown (top flame_shock -> stormstrike 112 of 18020 ticks; at cost lo-truth -3.4, gap BT). Draw-identical A/B
    -- (the strike's outcome rolled, its row dropped; repin-shaman-09-2; mana-09 merged), one boot per arm as here: flame_shock ->
    -- stormstrike 144 / 128 / 31 with the rows, 79 / 37 / 15 without (agreement .987 / .992 / .995 vs .992 / .994 /
    -- .997; heldReady 153 / 166 / 155 vs - / 179 / 171); on a fresh boot a fight 51 / 47. The traced episodes (seed 19,
    -- fresh boot) are the gap BT tie (belief and truth agree Flame Shock down and Stormstrike's cooldown; lo 5 under the
    -- truth puts Flame Shock's cost 0.08 s past Stormstrike's ready) and no avoid row paid a Flame Shock ticket; not traced:
    -- how the rows raise the count across a boot's fights (swing-ticket payments unlogged)
    -- lane mana-09 merged (8827f860d; CN22 nearest rounding, Stormstrike 121 -> 122; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 /
    -- 0, retracted 0 / 0 / 0, readyShort 0 / 0 / 1, heldReady 153 / 166 / 155, agreement .987 / .992 / .995, react p90 0 / 0 / 0):
    -- heldReady 146 -> 166 (the worst set), readyShort 0 -> 1, flicker 0.03 -> 0.01 (the worst, 0, + 0.01). Cause: CN22 nearest
    -- rounding (Stormstrike 121 -> 122) re-times the gap-BT near tie (flame_shock -> stormstrike, our lower mana bound ~4
    -- under truth; traced seed 1 and seed 19). The one readyShort event (seed 44 t 183.00, traced on the seeds 41-60 boot:
    -- the fight's last tick, Lightning Bolt shown ready at cost 0 with 5 Maelstrom Weapon stacks; belief and world both held
    -- 5 from 182.20 (no lost decrement, no stack or consume at the 183.00 tick, so not gap CT's last-tick shape), and the
    -- press's price (content.resolve in the loop) read no stack: 220 against 58.8 mana, a refusal for cost): the harness
    -- pricing the press, not the belief
    -- react bar 8 -> 3 (owner L1205): the 0.7 mana-wait tie no longer occurs (react p90 0 on all seed sets)
    -- readyShort 1 -> 0 (re-pin batch, L1267): harness-press-price-09 prices the press with the world's current auras
    -- (loop.lua passes the world's us to content.resolve), so seed 44's last-tick Lightning Bolt reads its 5 Maelstrom
    -- Weapon stacks; A/B seeds 41-60 readyShort 1 -> 0, every other cell identical
    ["Enhancement"] = { flicker = 0.01, retracted = 0, heldReady = 166, readyShort = 0 },
    -- heldReady 134 -> 100 (re-pin e2842f0a78, the Mage fix round: seeds 1-20 / 21-40 / 41-60 100 / 100 / 95)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.02 / 0 / 0, readyShort 0 / 0 / 0, heldReady 109 / 102 / 93):
    -- flicker 0.1 -> 0.03 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals); heldReady 100 -> 109 (cost crossings, lo < cost <= truth, on fights D2 re-times; C1 shows a crossing one update later)
    -- 0.7 re-pin e5a9cd2a2d (lane mage, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0, readyShort 0 / 0 / 0, heldReady 95 / 93 / 81, agreement .990 / .987 / .984): heldReady 109 -> 95 (the Arcane Concentration channel-start roll re-timed the fights); flicker 0.03 kept (0.02 + 0.01)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.00 / 0.00 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 97 / 85 / 84):
    -- flicker 0.03 -> 0, heldReady 95 -> 97
    -- re-pin e5a9cd2a2d -> e4ef929e54 (lane mage 0.9, R6; with item-restores-09, mana-09 CN22, harness-gcd-edge-09;
    -- seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 96 / 97 / 102,
    -- agreement .989 / .988 / .990): heldReady 97 -> 102, the worst of three seed sets (96 / 97 / 102); partly traced
    -- to wowsims 5ad9515c15's Arcane Concentration chance (a sixth a roll): seeds 41-60 with the old full chance
    -- (everything else equal) read 98 (A/B, not draw-identical), already over the old floor of 97; 84 -> 98 is the
    -- changes since the regen phase lane's measurement (not separated)
    -- 0.9 batch (integ/0.9 a464ca6a4; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0 / 0 / 0, readyShort
    -- 0 / 0 / 0, heldReady 109 / 97 / 102, agreement .990 / .989 / .990): heldReady 102 -> 109. Cause regen-read-09 (an
    -- out-of-combat regen read equal to the seed narrows the band), A/B on one tree: the Paladin merge 03b05f947 (which
    -- carries it) reads 109, the same minus its Power.lua diff 96. Traced (integ-09-fixes, both arms on one tree): the
    -- world's regen is 29.13/s in and out of the five-second rule, so the boot's read (29.13, the seed) closes the band at
    -- the in-combat rate (the in-combat EMA re-opens it about 2 %); seeds 21-40 and 41-60 hold the same ticks in both
    -- arms (97 / 102; only lo and the wait's length differ, shorter with the read). Seeds 1-20 fight 1: an Arcane Wrath
    -- pressed under Arcane Power (t 18.6) lands after it; the world charges 513.5 at the press, the belief 395 at the
    -- success (L1110's rule, not checked in game for a cost-raising aura), so est runs 118.5 over truth from t 22.2 in
    -- both arms. By t 51 the old seed band's lo sat under truth and hid it; the read puts lo = est, the first decision
    -- difference is t 51.6 (arcane_blast wait 1.30 vs 5.27, oracle 4.55; Evocation pressed at 53.0 vs 54.6) and fights 2-20 run
    -- on other trajectories (per seed -2 to +3). The held ticks are the cost crossing one poll late in both arms
    ["Arcane"] = { flicker = 0, retracted = 0, heldReady = 109 }, -- 0 / 0 / 0, 0
    -- heldReady 116 -> 175 (re-pin e2842f0a78; seeds 1-20 / 21-40 / 41-60 175 / 171 / 175, the fix round): the new
    -- list runs dry onto the Scorch filler; 174 of the 175 ticks (seeds 1-20) are Scorch at its 150 cost crossing, one
    -- tick an episode, lo 141-150 against the truth's 150-152 (gap BQ)
    -- flicker 0.3 -> 0.1 (the same sweep: 0 / 0 / 0; the loops do not show gap CQ's replay flash)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 180 / 182 / 177):
    -- flicker 0.1 -> 0 (S, steady icons on by default); heldReady 175 -> 182 (cost crossings, lo < cost <= truth, on fights D2 re-times; C1 shows a crossing one update later)
    -- 0.7 re-pin e5a9cd2a2d (lane mage, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 171 / 174 / 180, agreement .995 / .994 / .997): heldReady 182 -> 180 (the Fire Arcane Concentration 5/5 stream; cost crossings as before)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.00 / 0.00 / 0.00, retracted 0.00 / 0.02 / 0.00, readyShort 1 / 1 / 0, heldReady 169 / 173 / 175):
    -- retracted 0 -> 0.02, readyShort 0 -> 1, heldReady 180 -> 175. The 21-40 / 41-60 readyShort and retracted predate
    -- that lane (L757 I1, bisected on seeds 21-40: readyShort 0 / retracted 0 at 2a65a4d79, 2 / 0.03 at 1e75b58e2, the
    -- aura-paladin-mage merge's Mage auras); the lane measured them first
    -- re-pin e5a9cd2a2d -> e4ef929e54 (lane mage 0.9, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0 / 0 /
    -- 0, readyShort 0 / 0 / 0, heldReady 172 / 170 / 175, agreement .996 / .991 / .997): floors kept (heldReady at the
    -- floor; retracted and readyShort under it, not separated)
    ["Fire"] = { flicker = 0, retracted = 0.02, heldReady = 175, readyShort = 1 }, -- 0 / 0 / 0, 0
    -- 0.2 -> 0.3 (Task 6; seeds 1-20 / 21-40 / 41-60: 0.12 / 0.20 / 0.23, was 0.17 / 0.13 / 0.07): the world credits
    -- Evocation's mana on the 0.1 s regen tick (wowsims) instead of 1 s channel lumps; same total, every fight re-timed
    -- after its Evocation, more fights reach the existing frostfire_bolt <-> scorch pooling edge (gap BS); isolated by
    -- swapping pack and world; controller ruling 2026-10-30 while the owner was away
    -- 0.2 -> 0.1 (decision 63's rule, gap CE, a short answer's cap reads a whole unit under)
    -- heldReady 124 -> 106 (re-pin e2842f0a78, the Mage fix round: 96 / 100 / 106)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0, readyShort 0 / 0 / 0, heldReady 110 / 119 / 104):
    -- flicker 0.1 -> 0.03 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals); heldReady 106 -> 119 (cost crossings, lo < cost <= truth, on fights D2 re-times; C1 shows a crossing one update later)
    -- 0.7 re-pin e5a9cd2a2d (lane mage, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0, readyShort 0 / 0 / 0, heldReady 110 / 119 / 104, agreement .919 / .898 / .930): floors unchanged (the 21-40 set is the CN8 figure, accepted: gap BS's Scorch `fire_vulnerability.remains<5` edge and the Evocation pull-lo edge, lo about 520 against truth 1190, both pre-existing)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.02 / 0.03 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 97 / 121 / 111):
    -- flicker 0.03 -> 0.04, heldReady 119 -> 121
    -- re-pin e5a9cd2a2d -> e4ef929e54 (lane mage 0.9, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0, retracted 0,
    -- readyShort 0, heldReady 109 / 109 / 113, agreement .916 / .918 / .914): floors kept (under them; not separated:
    -- seeds 41-60 read 113 with Arcane Concentration's old full chance too)
    ["Frostfire"] = { flicker = 0.04, retracted = 0, heldReady = 121 }, -- 0 / 0.02 / 0, 0 (oracle 0.05 / 0.03 / 0.68)
    -- new pack 2026-11-12 (R6 first measurement; seeds 1-20 / 21-40 / 41-60 flicker 0.00 / 0.00 / 0.00 (oracle 0 / 0 /
    -- 0), retracted 0, readyShort 0 / 0 / 0, heldReady 113 / 113 / 109, agreement .999 / .998 / .997): flicker 0.01 (the
    -- measured worst + 0.01), heldReady 113 (the worst set)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.00 / 0.00 / 0.00 (oracle 0 / 0 / 0), retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0,
    -- heldReady 112 / 111 / 109, agreement .996 / .998 / .998): heldReady 113 -> 112, flicker kept
    -- rest window lane (L987 addendum, L1069), cause harness: the between-fight rest keeps the five-second window
    -- (047aa7e82): fights start at the true mana, so fights are re-timed; same cost/cooldown near-tie class (seeds 1-20
    -- / 21-40 / 41-60 flicker 0.00 / 0.00 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 116 /
    -- 117 / 110, agreement .995 / .997 / .998): heldReady 112 -> 117
    -- re-pin e5a9cd2a2d -> e4ef929e54 (lane mage 0.9, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0,
    -- readyShort 0, heldReady 116 / 117 / 110, agreement .995 / .997 / .999): floors kept (heldReady at the floor)
    ["Frost"] = { flicker = 0.01, retracted = 0, readyShort = 0, heldReady = 117 },
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 396 / 398 / 399):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    -- Priest re-pin lane (pin e5a9cd2a2dfc, CN8 merged, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0, readyShort 0, heldReady 395 / 395 / 397):
    -- heldReady 405 -> 397 (the measured worst: the world's Shadow build now has Improved Mind Blast 4, the pack's Elune's Light and Eureka lines moved)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.02 / 0.02 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 400 / 400 / 403):
    -- flicker 0 -> 0.02, heldReady 397 -> 403
    -- flicker-085 P1 (L755 / ruling L960: a mana pool with no tick seen pads nothing; seeds 1-20 / 21-40 / 41-60
    -- heldReady 406 / 404 / 403): heldReady 403 -> 406. The fights re-time; the event kind is the same as before
    -- (mind_flay waiting 0.07-0.2 s at the mana crossing, the floor under the cost, the truth over it)
    -- re-pin e5a9cd2a2d -> e4ef929e54 (Priest lane, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0, heldReady 405 / 406 / 396):
    -- flicker 0.02 -> 0 (the worst set reads 0); heldReady 406 holds. The new log moves 3 fixture rows and one decision (85 -> 86, a mind_flay tail), no loop-world value
    ["Shadow"] = { flicker = 0, retracted = 0, heldReady = 406 }, -- flicker 0 / 0 / 0, retracted 0, heldReady 406 / 400 / 398
    -- retracted 0.9 -> 0: 0.83 (oracle 0.63, Shoot at mana.pct<=10) before gap BD's cast bar, 0 / 0 / 0 after
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0, readyShort 0 / 0 / 0, heldReady 0 / 0 / 0):
    -- flicker 0.1 -> 0.03 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals)
    -- Priest re-pin lane (pin e5a9cd2a2dfc, integ/0.7 27add4428, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.02 / 0 / 0.05, retracted 0, heldReady 0 / 0 / 0):
    -- row unchanged at 0.03: the gate's seeds (1-20) read 0.02; seeds 41-60 read 0.05, above the row, and its cause is not traced, so the row is not raised (recorded as a deferral candidate)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.02 / 0.00 / 0.02, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 0 / 0 / 0):
    -- flicker 0.03 -> 0.02
    -- re-pin e5a9cd2a2d -> e4ef929e54 (Priest lane, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0, heldReady 0 / 0 / 0):
    -- flicker 0.02 -> 0 (the worst set reads 0; the old 0.05 at seeds 41-60 is gone)
    -- 0.9 batch (integ/0.9 a464ca6a4; seeds 1-20 / 21-40 / 41-60 flicker 0.02 / 0 / 0, retracted 0 / 0 / 0, readyShort
    -- 0 / 0 / 0, heldReady 0 / 1 / 0, agreement .948 / .947 / .959): flicker 0 -> 0.02, the row before the Priest lane
    -- (0.02 passes at seeds 1-20). Not from the batch merges: the lane's own tip 12c555178 reads 0.02 / .948 at seeds 1-20
    -- in this spec, so its 0.02 -> 0 above did not reproduce; why the lane read 0 is not known.
    -- 0.9 measure lane (forever 1a83bc208; seeds 1-20 / 21-40 / 41-60 flicker 0.02 / 0 / 0, retracted 0 / 0 / 0, readyShort
    -- 0 / 0 / 0, heldReady 0 / 1 / 0, agreement .948 / .947 / .959): heldReady 0 -> 1, traced: seeds 21-40, one tick at
    -- 183.0 s, power_infusion shown 0.07 s out (past the 0.05 s react window) while the oracle shows it ready; the truth
    -- covers its 248 cost by 2.8 mana: a one-poll near-cost crossing (the belief's own mana at that tick not read)
    ["Smite"] = { flicker = 0.02, retracted = 0, heldReady = 1 }, -- flicker 0.02 / 0 / 0, retracted 0, heldReady 0 / 1 / 0
    -- 0.1 -> 0.2 (Task 4, wowsims's Shaman regen in; seeds 1-20 / 21-40 / 41-60: 0.15 / 0.1996 / 0.17, was 0.03 / 0.03 /
    -- 0.02; oracle 0.03 / 0.03 / 0.03): estimate pinned at the crossing floor, 3-8 mana low at ~30 mana/s; a pick ~0.23 s
    -- from its cost slips a tick (owner ruling 2026-10-29, fallback of option 2). After Task 11 (Mana Spring Totem's
    -- mp5 as its own entry): 0.13 / 0.17 / 0.08, oracle 0.05 / 0.07 / 0.05, floor kept
    -- 0.2 -> 0.1 (decision 63's rule, gap CE, the whole-number read gone)
    -- re-pin e2842f0a78 (Task 11; the world's regen from the Windshaper log, 5650 / 31.13 / 45.25, was 5590 / 29.75 /
    -- 42.5): heldReady 301 -> 302 (seeds 1-20 / 21-40 / 41-60: 302 / 299 / 302, was 301 / 282 / 277); readyShort
    -- 0 -> 1 (ruling R27), the one traced event: seed set 1-20, t 183.20 (the fight's last tick), Lava Burst shown
    -- ready at cost 238.5 with the truth at 103.2 and our engine's mana 198.1 (belief over the truth by ~95, still under
    -- the cost: the icon priced it lower). Cause unconfirmed (the poll's pricing was not dumped), belief-side either way,
    -- gaps.md CT: (a) the belief kept a Clearcasting the world had spent, or (b) gap CE's open first-touch-with-no-answer
    -- shape. With the old world regen 0. The other moved Elemental cells (L10 idle 0.0 -> 0.2, the dps A/B both ways,
    -- refused-for-cost 0.0 -> 0.1) move as a group with the world/log change. Flicker 0.00 / 0.00 / 0.00 (oracle
    -- 0.05 / 0.05 / 0.07): ceiling 0.1 kept
    -- re-pin 0.7 (e5a9cd2a2dfc, lane shaman, R6; seeds 1-20, steady icons on, melee-range tree): heldReady 321 -> 284 (the
    -- bar is seeds 1-20 only; flicker 0.00, readyShort 0, oracle 0.02): the new list has no Lava Burst
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 1 / 0 / 0, heldReady 285 / 301 / 321):
    -- flicker 0.1 -> 0 (S, steady icons on by default); heldReady 302 -> 321 (cost crossings, lo < cost <= truth, on fights D2 re-times; C1 shows a crossing one update later)
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.00 / 0.00 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 285 / 294 / 274):
    -- heldReady 284 -> 294
    -- 0.8.5 close (ledger L1132, measured on integ/0.8.5-w2 fa22dc2ad; seeds 1-20 / 21-40 / 41-60 heldReady 300 / 292 /
    -- 299, flicker 0 / 0 / 0, retracted 0 / 0 / 0, readyShort 0 / 0 / 0): heldReady 294 -> 300 (the worst set). Cause
    -- flicker-085 b4036d424 (P1: a mana pool with no tick seen pads nothing; bisected 275 at its parent -> 300): every
    -- mana wait is re-timed, the same cost-crossing class as above (gap BT, lo / est 2-6 under the truth at the cost,
    -- our wait 0.07-0.20 s, the oracle ready); seeds 1-20 held ticks lightning_bolt 169 -> 191, flame_shock 73 -> 80,
    -- searing_totem 33 -> 29, every fight the same length
    -- re-pin e5a9cd2a2d -> e4ef929e54 (lane repin-shaman-09, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0 / 0 /
    -- 0, readyShort 0 / 0 / 0, heldReady 300 / 292 / 299, agreement .996 / .996 / .997): readyShort 1 -> 0; heldReady
    -- 300 unchanged (the request is unchanged; the world models no Searing Totem attack, resist or item cooldown)
    -- the world's mana and regen from the e4ef929e54 log (5950 / 26.31 / 31.31 / 45.62, was 5650 / 26.13 / 31.13 /
    -- 45.25; repin-shaman-09 fix round 1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0, readyShort 0 / 0
    -- / 0, heldReady 277 / 290 / 300, agreement .997 / .997 / .997), the same after the mana-09 merge: floors unchanged
    -- heldReady 300 -> 308 re-pin e4ef929e54 -> ab0f00e4fc (lane repin-ab0f-shaman, R6; seeds 1-20 / 21-40 / 41-60
    -- flicker 0 / 0 / 0, retracted 0, readyShort 0 / 0 / 0, heldReady 288 / 308 / 297): re-pin; causes not separated
    -- by an A/B. Candidates: the world's mana 6295 and regen 13.25 / 26.85 from the new log, the Lightning Overload roll
    -- of Elemental Focus (more Clearcasting, so seeded fights reorder) and the new list (Fire Nova above Elemental
    -- Mastery, Chain Lightning only above 40% mana); the worst set is 21-40 (cost crossings, lo under the truth at the
    -- threshold, as before)
    ["Elemental"] = { flicker = 0, retracted = 0, heldReady = 308, readyShort = 0 }, -- 0.00 / 0.00 / 0.00, 0
    -- 0.4 -> 0 (Task 10, a paid channel holds the five-second rule's casting rate to its end; seeds 1-20 / 21-40 / 41-60:
    -- 0 / 0 / 0, was 0 / 0.32 / 0.02): Wrack's 6 s paid channel no longer resumes the spirit part 5 s in, so the mana
    -- estimate stops running ahead of truth at its end, where Life Tap and Wrack were a near-tie (agreement .993 -> .996
    -- on seeds 21-40); controller rule, the measured values beside the line
    -- 0.7 re-pin (e5a9cd2a2d, merged tree 27add4428+, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 0 / 0 / 0):
    -- heldReady 5 -> 0 (the rewritten list, steady icons and C1)
    -- 0.9 re-pin e5a9cd2a2d -> e4ef929e54 (R6; the new Wrack APL, the world's Wrack half points, then the world on
    -- wowsims's 35/11/5 build: instant Corruption, the Imp sacrificed, pool 6277): every cell 0 / 0 / 0 on all three
    -- sets, agreement .995 / .996 / .994; nothing moves
    ["Affliction"] = { flicker = 0, retracted = 0, heldReady = 0 }, -- 0 / 0 / 0, 0
    -- heldReady 6 -> 8 (re-pin e2842f0a78, Task 16, R6, R49; seeds 1-20 / 21-40 / 41-60: 7 / 8 / 2, flicker 0.17 / 0.17 /
    -- 0.05, oracle 0): traced at 21-40, all 8 the stand-in Siphon Life after a hard cast, ours 0.10 s vs the oracle's
    -- 0.00 (the same icon one poll late; mana est within 2 of the truth): the wait class above
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 3 / 5 / 2):
    -- flicker 0.3 -> 0 (S, steady icons on by default)
    -- 0.7 re-pin (R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 3 / 5 / 2): heldReady 8 -> 5 (the worst set)
    -- 0.8 aura lane (C8, fcceb5577: Shadow Trance is spent only by an instant Shadow Bolt, wowsims
    -- talents_affliction.go:186-190, as the loop world; agreement .979 -> .983; seeds 1-20 / 21-40 / 41-60 flicker
    -- 0.02 / 0.00 / 0.00, oracle the same, heldReady 5 / 4 / 0): flicker 0 -> 0.03 (the measured worst + 0.01: the line
    -- rounds to two decimals). Traced, the only flip in 60 fights, seed 8, ticks 823-825 (167.4-167.8 s): filler
    -- shadow_bolt@0.10 / immolate@0.20 (the GCD over, Immolate 0.2 s from its refresh line: the core's EARLY_EXIT) /
    -- shadow_bolt@0.00 from a Nightfall proc, pressed at once by ours and the oracle. Each icon is right when shown and
    -- the oracle's first icon is identical on every tick: the list plus a random proc, not the belief. The flip rule
    -- excuses a press of the middle icon only; here the pressed proc is the returning one (owner rule 2026-10-25: name it
    -- as the cause, never hide a correct icon). Reverting C8 alone restores .979 / 3 / 0.00. Decision:
    -- fable-decision-smruin.md, ledger L631
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.02 / 0.00 / 0.02, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 5 / 3 / 1):
    -- flicker 0.03 -> 0.02
    -- re-pin e4ef929e54 -> ab0f00e4fc (R6; the five Orc builds, the world's pools and regen seeds; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.017 / 0 / 0.033 (the oracle's the same), retracted 0, heldReady 2 / 1 / 1, readyShort 0): heldReady 5 -> 2
    -- flicker 0.02 -> 0.033 (seeds 41-60, the oracle's the same 0.033: the worst of the three sets)
    ["SM Ruin"] = { flicker = 0.033, retracted = 0, heldReady = 2 }, -- 0.017 / 0 / 0.033, 0
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 0 / 2 / 0):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    -- 0.7 re-pin (R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 0 / 0 / 0): heldReady 4 -> 0
    ["Demonology"] = { flicker = 0, retracted = 0, heldReady = 0 }, -- 0 / 0 / 0, 0
    -- heldReady 3 -> 6 (re-pin e2842f0a78, Task 16, R6; seeds 1-20 / 21-40 / 41-60: 6 / 6 / 6, flicker 0.03 / 0.02 /
    -- 0.02, oracle 0): traced at 1-20, each the same icon (Searing Pain 4, Life Tap, Bane of Agony) at 0.10-0.11 s vs
    -- the oracle's 0.00-0.01, mana est within 2-29 of the truth: the wait class above, more often in the new list
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 6 / 5 / 6):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    -- 0.7 re-pin (R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 6 / 5 / 6): unchanged, still ON THE BAR (the wait class above)
    -- translator-2 (the pre-pull Shadow Bolt, travel-time fold), seeds 1-20: heldReady 6 -> 7; all 7 ticks (base: all 6)
    -- are one shape, searing_pain@0.11 against the oracle's @0.01 at its ready edge (one poll), on re-timed fights
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.00 / 0.00 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 11 / 11 / 10):
    -- heldReady 7 -> 11
    -- re-pin e4ef929e54 -> ab0f00e4fc (R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, heldReady 10 / 18 / 21, readyShort 0):
    -- heldReady 11 -> 21 (traced: the held ticks are Searing Pain waiting 0.11 s at an exact Demonic Brand remains =
    -- 2.500 s boundary tie (remains<2.5); no Life Tap or mana hold; oracle flicker 0)
    ["Shadow Brand"] = { flicker = 0, retracted = 0, heldReady = 21 }, -- 0 / 0 / 0, 0
    -- the excess over the oracle (0 / 0 / 0) is at Conflagrate's and Shadowburn's cooldown ends, as Fire's Fire Blast
    -- (the not-ready flag's CD_PROBE, central). 0.4 -> 0.2 (Task 10b, gap CQ: the flag keeps a modelled end the GCD or a
    -- hard cast covers; 0.13 / 0.17 / 0.07, was 0.23 / 0.40 / 0.25; agreement .995 / .992 / .996); the rest is the probe
    -- on a free GCD, where the loops' grid puts the world's end a ulp after the tick
    -- flicker 0.2 -> 0.5 (re-pin e2842f0a78, Task 16, R6; seeds 1-20 / 21-40 / 41-60: 0.50 / 0.30 / 0.30, oracle 0;
    -- heldReady 1 / 0 / 0): gap CQ's uncovered shape (an end just past a hard cast's): traced seed 13, 49.4 s, one poll
    -- `life_tap(0.10) conflagrate(1.60)` between `conflagrate(0.50)` and `conflagrate(0.00)`, at the end of the
    -- Immolate refresh's hard cast, which the new list (`immolate,if=remains<=cast`, Conflagrate gated on Immolate up)
    -- lands on Conflagrate's cooldown end in nearly every fight (~46 s into combat; 28 of the 30 flips at 1-20 are
    -- conflagrate > incinerate / life_tap). Central (belief casts), existing; PROPOSED-warlock-5
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 0 / 0 / 2):
    -- flicker 0.5 -> 0 (S, steady icons on by default)
    -- 0.7 re-pin (R6; seeds 1-20 / 21-40 / 41-60 flicker 0.02 / 0.00 / 0.02 (one flip a set), readyShort 0 / 0 / 0, heldReady 1 / 2 / 3,
    -- oracle flicker 0.02 / 0.02 / 0.03): heldReady 8 -> 3 (the worst set). flicker 0 -> 0.03 (the measured worst + 0.01: the
    -- line rounds to two decimals). Traced, seed 1 fight 1, 16.2-16.6 s: immolate@0.00 / conflagrate@0.20 / immolate@0.10 as
    -- the first icon on consecutive polls; Conflagrate's cooldown ends at 16.6 s while Immolate sits at its refresh
    -- threshold (`immolate,if=remains<incinerate cast`), so each of the two lines is the first icon on alternate polls. The
    -- oracle's own queue shows the identical three firsts (or[] equals us[] on all three ticks), so it is the wowsims list's
    -- near-tie, not the kit or pack: a cooldown end beside a refresh threshold, which the steady-icons hold does not cover (a
    -- 3-poll swap with neither line pressed). The only flip in seeds 1-20; sets 21-40 and 41-60 read 0.00 and 0.02.
    -- regen phase lane, cause harness: seeded random regen phase per fight (ledger L667) (R6; seeds 1-20 / 21-40 /
    -- 41-60 flicker 0.02 / 0.00 / 0.00, retracted 0.00 / 0.00 / 0.00, readyShort 0 / 0 / 0, heldReady 0 / 0 / 0):
    -- flicker 0.03 -> 0.02, heldReady 3 -> 0
    -- re-pin e4ef929e54 -> ab0f00e4fc (R6; Orc build, pool 5323, Spirit 170; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0,
    -- heldReady 1 / 1 / 0, readyShort 0, agreement .999): heldReady 0 -> 1, one tick of 18020: Corruption held one 0.20 s poll
    -- at seed 15, 47.2 s (not mana; cause untraced)
    ["Destruction"] = { flicker = 0.02, retracted = 0, heldReady = 1 }, -- 0 / 0 / 0, 1
}
-- Our first-icon flicker at most the oracle shadow's plus K, every gated 20-fight loop: the widest measured gap rounded
-- up to the next 0.1. It tightens the bar when a change lowers the oracle's own flicker. 1.8 -> 0.5 (forever-gap-bd,
-- 2026-10-26, the press rule and gap BD's cast bar; every gated pack but a row's own flickerK, seeds 1-20 / 21-40 /
-- 41-60): the widest gap is
-- Fury L60 seeds 21-40, 0.70 vs 0.23 (0.466); next Protection seeds 1-20, 0.46 vs 0. Before, Balance seeds 1-20 read
-- 2.36 vs 1.23 on f09656c8e (gap 1.13: the old comment's oracle 0.65 was stale), all of it gap BD's invisible cast bar.
M.FLICKER_K = 0.5

--- The flicker floors of `label` (M.FLICKER) and, unless `reported`, flicker <= oracle + FLICKER_K, reported next to
--- react p90 and the unmatched cost refusals (the line).
function M.flicker(label, r, line, reported)
    local fl = M.FLICKER[label]
    if fl then
        ab.check(r.flicker <= fl.flicker, label, "flicker floor: " .. line)
        ab.check(r.retracted <= fl.retracted, label, "retracted-ready floor: " .. line)
        ab.check(r.readyShort <= (fl.readyShort or 0), label, "ready-while-short floor: " .. line)
        ab.check(r.heldReady <= (fl.heldReady or 0), label, "held-while-ready floor: " .. line)
    end
    if not reported then
        ab.check(
            r.flicker <= r.oracleFlicker + (fl and fl.flickerK or M.FLICKER_K),
            label,
            "flicker over the oracle's + K: " .. line
        )
    end
end

-- The CPU bar (D5), on the ratio of each tick's process CPU to the in-process calibration (loop.calibrate) re-timed
-- every loop.CAL_EVERY counted ticks (loop.ratios), not on ms: load from other processes slows both, so the bar does not
-- depend on what else runs, also when the load changes during a fight. 20-fight lines read under 0.6 quiet; load moves
-- a line by under 0.1 (Feral 3 fights: about 0.61 quiet, 0.63-0.70 under a 16-wide `make test`).
M.CPU_RATIO = 1.0
-- A one-fight line's bar (wowsims.gate's replay): headroom over a replay's ratio (0.23-0.60 quiet, about 20 calibration
-- windows a replay).
M.CPU_RATIO_ONE_FIGHT = 1.2

--- The engine's health, gated at any fight count: no error, raise, self-check miss, unlisted read or secret, CPU.
function M.health(m, r, line)
    assert.are.same({ 0, 0, 0 }, { m.errors, m.raises, m.selfCheck })
    assert.are.same({}, m.misses)
    assert.are.same({}, m.secrets) -- no facade passthrough answered a secret (the traced first fight)
    local oneFight = m.cal ~= nil and #m.cal == 1
    assert.is_true(r.cpuRatio <= (oneFight and M.CPU_RATIO_ONE_FIGHT or M.CPU_RATIO), line) -- the ms mean and p99 reported
end

--- The engine and the first icon, gated at any fight count; `label` picks a re-based unmatched bar (M.UNMATCHED_BY).
function M.gate(m, r, line, label)
    local at = label or "gate" -- loop_spec's bar checks pass no label
    ab.check(r.agreement >= 0.85, at, line)
    ab.check(r.reactMedian <= 1 and r.reactP90 <= (M.REACT_P90_BY[label] or 3), at, line)
    ab.check((r.per100.gcd or 0) == 0 and (r.per100.cooldown or 0) == 0, at, line)
    -- our cost refusals the oracle shadow would not have made at that tick (loop.unmatched: the round-3 ruling); a
    -- refusal both make is the press protocol meeting the world's rage timing, kept visible in the raw rate
    ab.check((r.per100U.cost or 0) <= (M.UNMATCHED_BY[label] or M.UNMATCHED), at, line)
    -- every other refusal the oracle would not have made is 0; `casting` is our own cast bar meeting the press protocol
    for key, n in pairs(r.per100U) do
        ab.check(key == "cost" or key == "casting" or n == 0, at, line)
    end
    M.health(m, r, line)
end

--- `n` fights of `world` on a fresh boot (seeds `seed0` + 1 ..), the `<label> solo:` line printed (`tag` appended in
--- brackets), gated; `reported`: the engine's health and the label's M.FLICKER floors only (not M.gate's bars nor the
--- oracle + K bar), " (reported)" appended. DPS A/B and never-reacts are reported, not gated. Returns the summary
--- (`r.focus`: run A's in-combat ticks whose first record has `focus` set, kept out of the line) and the line.
function M.solo(label, world, n, seed0, tag, reported)
    local m = loop.tally(loop.new(world), n, { seed0 = seed0 })
    local r, line = loop.summary(m), loop.line(m)
    print(
        "\n" .. label .. " solo: " .. line .. (tag and " [" .. tag .. "]" or "") .. (reported and " (reported)" or "")
    )
    if reported then
        M.health(m, r, line)
    else
        M.gate(m, r, line, label)
    end
    if n >= 20 and not m.hold and (m.steady == 1 or m.steady == true) then -- the floors are the shipped display's
        M.flicker(label, r, line, reported)
    end
    return r, line
end

return M
