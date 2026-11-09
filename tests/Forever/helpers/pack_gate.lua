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
M.REACT_P90_BY = {
    -- 3 -> 8 (0.7 re-pin, R6, owner ruling option b, reversible; seeds 1-20 reactP90 8, agreement 0.912, was 0 / 0.963 before
    -- CN8): a mana-wait tie. Flame Shock costs 410; the oracle's exact mana reaches it at the instant Stormstrike's
    -- cooldown ends (it shows Flame Shock first by priority), our conservative lower bound runs 2-4 mana under the
    -- truth (259.0 true vs 256.7 believed), so our Flame Shock is 0.04 s late and Stormstrike shows during the wait; at
    -- the edge both press Flame Shock (no cast lost). CN8's world queue window re-times the fights so the tie recurs about
    -- once per ~47 s cycle. The owner's "dim, never promote" rule losing a tie to an exact oracle, by design
    ["Enhancement"] = 8,
}

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
    ["Arms"] = { flicker = 0.05, retracted = 0.1, readyShort = 0, heldReady = 340 }, -- 0.24 / 0.17 / 0.26, 0 / 0.02 / 0
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
    ["Fury L60"] = { flicker = 0.31, flickerK = 0.6, retracted = 0.21, readyShort = 26, heldReady = 228 }, -- 0.85 / 0.84 / 0.54, 0.07 / 0.00 / 0.06
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
    ["Fury L24"] = { flicker = 0.5, flickerK = 0.6, retracted = 0.2, readyShort = 0, heldReady = 439 }, -- 0.46 / 0.52 / 1.25, 0.06 / 0.06 / 0.16; 53 / 47 / 47, 406 / 328 / 260
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
    ["Warrior Protection"] = { flicker = 0.16, retracted = 0.1, readyShort = 1, heldReady = 383 }, -- 0.62 / 0.64 / 0.54, 0 / 0.03 / 0.02
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
    ["Feral"] = { flicker = 0.03, retracted = 0, heldReady = 283 }, -- 0.56 / 0.89 / 0.56, 0
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 133 / 125 / 136):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    ["Balance"] = { flicker = 0, retracted = 0, heldReady = 140 }, -- 0.03 / 0.05 / 0.07, 0
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
    ["Guardian"] = { flicker = 0.23, retracted = 0.7, readyShort = 0, heldReady = 330 }, -- 0.77 / 0.91 / 1.03, 0.35 / 0.54 / 0.60
    ["Assassination"] = { flicker = 0, retracted = 0, heldReady = 329 }, -- 0 / 0 / 0, 0
    -- 0.1 -> 0.2 (gap CE; 0.15 / 0 / 0.02, was 0.04 / 0 / 0, oracle 0.04 / 0.06 / 0.04): seeds 1-20 flips 2 (round 2)
    -- -> 7, base 15; the extra 5 are fight 8, t 23.0-24.2, sinister_strike vs slice_and_dice, no capped read in either
    -- tree, flips match base's tick for tick; Sinister Strike's entry is gated on `!(buff.slice_and_dice.remains<=2)`,
    -- inferred as an energy wait against that window; base's floor was 0.4; owner standing approval 2026-10-30
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0.04, readyShort 0 / 0 / 0, heldReady 341 / 356 / 350):
    -- flicker 0.2 -> 0.05 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals)
    ["Combat"] = { flicker = 0.05, retracted = 0, heldReady = 356 }, -- 0.15 / 0 / 0.02, 0
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 382 / 364 / 363):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    ["Subtlety"] = { flicker = 0, retracted = 0, heldReady = 382 }, -- 0.02 / 0 / 0, 0 (gap CE)
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
    ["Survival"] = { flicker = 0.04, retracted = 0, readyShort = 1, heldReady = 400 }, -- 1.51 / 1.10 / 0.93, 0 (oracle 0.07 / 0.02 / 0.02), 400 / 348 / 347
    -- 0 / 112 -> 0.1 / 116 (re-pin e2842f0a78, Task 19, R6; seeds 1-20 / 21-40 / 41-60: flicker 0.02 / 0.02 / 0, oracle
    -- 0 / 0 / 0, held 116 / 110 / 106, agreement 1.000 each; identical with R61 7a8972d4c): the flip (one a set) is
    -- multi_shot@0.50 -> serpent_sting@0.40 -> multi_shot@0 (seed 1, 48.4-48.8 s): Multi-Shot's last 0.5 s under
    -- CD_PROBE (central, Fire Blast's class); held, seeds 1-20: arcane_shot 109 (105 at its mana crossing with the pool
    -- under 400, gap BT; 4 CD_PROBE), hunters_mark 7: the row's existing classes, the re-timed fights
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 111 / 108 / 109):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    ["Marksmanship"] = { flicker = 0, retracted = 0, heldReady = 116 }, -- 0.02 / 0.02 / 0, 0
    -- 0 -> 0.2 (Task 5, wowsims's Hunter regen in; seeds 1-20 / 21-40 / 41-60: 0 / 0.12 / 0, was 0 / 0 / 0): the new BM
    -- regen puts Arcane Shot's mana crossing 0.14 s from Hunter's Mark's refresh; lo runs ~3 mana under truth (gaps
    -- BQ/BT, G7), so the near-tie resolves both ways (fight 21); controller ruling 2026-10-29 while the owner was away
    -- (logged in hekili-open-questions.md); the oracle's own 0.02 / 0 / 0 (agreement 0.998 / 0.996 / 0.999)
    -- heldReady 129 (gap CG, the world's Multi-Shot priced as the pack's: 2288 / 1929 / 2512 -> 129 / 120 / 121; Serpent
    -- Sting presses seeds 1-20 29 -> 28; agreement 1.000 / 0.995 / 1.000 -> 0.998 / 0.997 / 0.999: the re-timed fights
    -- 13+16 / 2+5+13+16 / 8+19 start on a drained pool with the floor at Aspect of the Hawk's 120 while the truth is
    -- 155-186, so Rapid Fire's cooldown shows before Arcane Shot's mana crossing for ~5 s, 38-46 ticks a set; no press is
    -- lost, Arcane Shot lands on the oracle's tick. Not new: 4e111189f (before Part B, the world at 695) shows the same
    -- rapid_fire vs arcane_shot at t 3.6-7.6, agreement .998 / .996, its first rows those of head's seed 20 fight 2 (truth
    -- 180.41, lo 120); head's dip is base's 1.000 going away, not a new class)
    -- 129 -> 127 (fix round 5, gap CG's audit: the BM world takes the export's Efficiency 2/5, so its shots and Sting cost
    -- the log's 178.6 / 235 / 224.66 instead of 190 / 250 / 239; seeds 1-20 / 21-40 / 41-60: 126 / 127 / 124, was 129 /
    -- 120 / 121; agreement 1.000 / .999 / .996, was .998 / .997 / .999; flicker and readyShort 0; Arcane Shot presses
    -- seeds 1-20 243 -> 258, Serpent Sting 28 -> 28. The drained-pool shape above moves with the fights: now seeds 1-20
    -- fights 5 / 8 / 11 / 14 / 17 / 20 one tick each at t 3.6 (truth 179, lo 120), seeds 21-40 fights 3 / 6 / 9 / 12 / 15 /
    -- 18 1-3 ticks, seeds 41-60 fights 2 / 5 / 8 / 11 14-21 ticks at t 3.6-7.6, truth 146-179; replay, M.READY and LIVE60
    -- unmoved, the replay takes the log header's talents already)
    -- 0 / 127 -> 0.1 / 156 (re-pin e2842f0a78, Task 19, R6; seeds 1-20 / 21-40 / 41-60: flicker 0 / 0.03 / 0, oracle 0
    -- / 0 / 0, held 156 / 153 / 154, agreement .996 / .993 / .993, dps A/B .987 / .988 / .988; identical with R61 (7a8972d4c)
    -- merged): wowsims's HHA sequence (`summon_hawk, summon_hawk, arcane_shot`) casts Arcane Shot every third step, so
    -- Multi-Shot is the dry pool's spender and the cost-crossing hold (gap BT, the floor a few units under the truth:
    -- pool 224-226 at its 224.66) moves onto it: multi_shot 137 of 156 held ticks at seeds 1-20, one a crossing, 7-8 a
    -- fight; ablation (Arcane Shot without the HHA term): 156 -> 129, multi_shot's ticks gone. The two flips (seed 21,
    -- 112.4-116.2 s) are Hunter's Mark's expiry against Summon Hawk's mana crossing at an empty pool (61-122 mana), both
    -- 4-8 s away and 0.3 s apart, the lo lag reordering them (gap BT; the row's earlier Arcane Shot vs Mark class)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 151 / 149 / 146):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    ["Beast Mastery"] = { flicker = 0, retracted = 0, heldReady = 156 }, -- 0 / 0.03 / 0, 0 (gap CE)
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
    ["Retribution"] = { flicker = 0, retracted = 0, readyShort = 0, heldReady = 241 }, -- 0.04 / 0.04 / 0.04, 0 (oracle 0.04 / 0.00 / 0.11)
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
    ["Protection"] = { flicker = 0, retracted = 0, heldReady = 296 }, -- 0.02 / 0.02 / 0.02, 0 (oracle 0.38 / 0.00 / 0.00)
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
    ["Enhancement"] = { flicker = 0, retracted = 0, heldReady = 152 }, -- heldReady ON THE BAR (= seeds 1-20): re-measure at integration; the flicker figures here (0.13 x3) are stale, see the history above (L104)
    -- heldReady 134 -> 100 (re-pin e2842f0a78, the Mage fix round: seeds 1-20 / 21-40 / 41-60 100 / 100 / 95)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.02 / 0 / 0, readyShort 0 / 0 / 0, heldReady 109 / 102 / 93):
    -- flicker 0.1 -> 0.03 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals); heldReady 100 -> 109 (cost crossings, lo < cost <= truth, on fights D2 re-times; C1 shows a crossing one update later)
    -- 0.7 re-pin e5a9cd2a2d (lane mage, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0, readyShort 0 / 0 / 0, heldReady 95 / 93 / 81, agreement .990 / .987 / .984): heldReady 109 -> 95 (the Arcane Concentration channel-start roll re-timed the fights); flicker 0.03 kept (0.02 + 0.01)
    ["Arcane"] = { flicker = 0.03, retracted = 0, heldReady = 95 }, -- 0 / 0.02 / 0, 0
    -- heldReady 116 -> 175 (re-pin e2842f0a78; seeds 1-20 / 21-40 / 41-60 175 / 171 / 175, the fix round): the new
    -- list runs dry onto the Scorch filler; 174 of the 175 ticks (seeds 1-20) are Scorch at its 150 cost crossing, one
    -- tick an episode, lo 141-150 against the truth's 150-152 (gap BQ)
    -- flicker 0.3 -> 0.1 (the same sweep: 0 / 0 / 0; the loops do not show gap CQ's replay flash)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 180 / 182 / 177):
    -- flicker 0.1 -> 0 (S, steady icons on by default); heldReady 175 -> 182 (cost crossings, lo < cost <= truth, on fights D2 re-times; C1 shows a crossing one update later)
    -- 0.7 re-pin e5a9cd2a2d (lane mage, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 171 / 174 / 180, agreement .995 / .994 / .997): heldReady 182 -> 180 (the Fire Arcane Concentration 5/5 stream; cost crossings as before)
    ["Fire"] = { flicker = 0, retracted = 0, heldReady = 180 }, -- 0 / 0 / 0, 0
    -- 0.2 -> 0.3 (Task 6; seeds 1-20 / 21-40 / 41-60: 0.12 / 0.20 / 0.23, was 0.17 / 0.13 / 0.07): the world credits
    -- Evocation's mana on the 0.1 s regen tick (wowsims) instead of 1 s channel lumps; same total, every fight re-timed
    -- after its Evocation, more fights reach the existing frostfire_bolt <-> scorch pooling edge (gap BS); isolated by
    -- swapping pack and world; controller ruling 2026-10-30 while the owner was away
    -- 0.2 -> 0.1 (decision 63's rule, gap CE, a short answer's cap reads a whole unit under)
    -- heldReady 124 -> 106 (re-pin e2842f0a78, the Mage fix round: 96 / 100 / 106)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0, readyShort 0 / 0 / 0, heldReady 110 / 119 / 104):
    -- flicker 0.1 -> 0.03 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals); heldReady 106 -> 119 (cost crossings, lo < cost <= truth, on fights D2 re-times; C1 shows a crossing one update later)
    -- 0.7 re-pin e5a9cd2a2d (lane mage, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0, readyShort 0 / 0 / 0, heldReady 110 / 119 / 104, agreement .919 / .898 / .930): floors unchanged (the 21-40 set is the CN8 figure, accepted: gap BS's Scorch `fire_vulnerability.remains<5` edge and the Evocation pull-lo edge, lo about 520 against truth 1190, both pre-existing)
    ["Frostfire"] = { flicker = 0.03, retracted = 0, heldReady = 119 }, -- 0 / 0.02 / 0, 0 (oracle 0.05 / 0.03 / 0.68)
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 396 / 398 / 399):
    -- flicker 0.1 -> 0 (S, steady icons on by default)
    -- Priest re-pin lane (pin e5a9cd2a2dfc, CN8 merged, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, retracted 0, readyShort 0, heldReady 395 / 395 / 397):
    -- heldReady 405 -> 397 (the measured worst: the world's Shadow build now has Improved Mind Blast 4, the pack's Elune's Light and Eureka lines moved)
    ["Shadow"] = { flicker = 0, retracted = 0, heldReady = 397 }, -- 0 / 0 / 0, 0
    -- retracted 0.9 -> 0: 0.83 (oracle 0.63, Shoot at mana.pct<=10) before gap BD's cast bar, 0 / 0 / 0 after
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0.02 / 0, readyShort 0 / 0 / 0, heldReady 0 / 0 / 0):
    -- flicker 0.1 -> 0.03 (S, steady icons on by default; the measured worst + 0.01: the line rounds to two decimals)
    -- Priest re-pin lane (pin e5a9cd2a2dfc, integ/0.7 27add4428, R6; seeds 1-20 / 21-40 / 41-60 flicker 0.02 / 0 / 0.05, retracted 0, heldReady 0 / 0 / 0):
    -- row unchanged at 0.03: the gate's seeds (1-20) read 0.02; seeds 41-60 read 0.05, above the row, and its cause is not traced, so the row is not raised (recorded as a deferral candidate)
    ["Smite"] = { flicker = 0.03, retracted = 0, heldReady = 0 }, -- 0.02 / 0 / 0.05, 0
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
    ["Elemental"] = { flicker = 0, retracted = 0, heldReady = 284, readyShort = 1 }, -- 0.00 / 0.00 / 0.00, 0 (oracle 0.05 / 0.05 / 0.07)
    -- 0.4 -> 0 (Task 10, a paid channel holds the five-second rule's casting rate to its end; seeds 1-20 / 21-40 / 41-60:
    -- 0 / 0 / 0, was 0 / 0.32 / 0.02): Wrack's 6 s paid channel no longer resumes the spirit part 5 s in, so the mana
    -- estimate stops running ahead of truth at its end, where Life Tap and Wrack were a near-tie (agreement .993 -> .996
    -- on seeds 21-40); controller rule, the measured values beside the line
    -- 0.7 re-pin (e5a9cd2a2d, merged tree 27add4428+, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 0 / 0 / 0):
    -- heldReady 5 -> 0 (the rewritten list, steady icons and C1)
    ["Affliction"] = { flicker = 0, retracted = 0, heldReady = 0 }, -- 0 / 0 / 0, 0
    -- heldReady 6 -> 8 (re-pin e2842f0a78, Task 16, R6, R49; seeds 1-20 / 21-40 / 41-60: 7 / 8 / 2, flicker 0.17 / 0.17 /
    -- 0.05, oracle 0): traced at 21-40, all 8 the stand-in Siphon Life after a hard cast, ours 0.10 s vs the oracle's
    -- 0.00 (the same icon one poll late; mana est within 2 of the truth): the wait class above
    -- CN8 (D2 + S + C1, R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 3 / 5 / 2):
    -- flicker 0.3 -> 0 (S, steady icons on by default)
    -- 0.7 re-pin (R6; seeds 1-20 / 21-40 / 41-60 flicker 0 / 0 / 0, readyShort 0 / 0 / 0, heldReady 3 / 5 / 2): heldReady 8 -> 5 (the worst set)
    ["SM Ruin"] = { flicker = 0, retracted = 0, heldReady = 5 }, -- 0 / 0 / 0, 0
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
    ["Shadow Brand"] = { flicker = 0, retracted = 0, heldReady = 7 }, -- 0 / 0 / 0, 0
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
    ["Destruction"] = { flicker = 0.03, retracted = 0, heldReady = 3 }, -- 0.02 / 0.00 / 0.02, 0
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

-- The CPU bar (D5), on the ratio of each tick's process CPU to the in-process calibration timed once per fight
-- (loop.calibrate), not on ms: load from other processes slows both, so the bar stops depending on what else runs. Set
-- to the old 10 ms bar on a quiet run, so it did not loosen: 10 ms / the ~7 ms calibration = 1.4. Measured: Arms 20
-- fights alone 3.96 ms, ratio 0.555 (2026-10-30, under the lock); under a 16-wide `make test` beside it: Feral 3 fights
-- 4.25 -> 5.82 ms, ratio 0.634 -> 0.494; Arms 3 fights 3.78 -> 5.92 ms, ratio 0.624 -> 0.547 (the calibration slows a
-- little more than the engine, so load lowers the ratio: the safe direction). 1.4 -> 1.0 (2026-11-01, the pre-launch perf
-- work left room: 20-fight lines stay under 0.6).
M.CPU_RATIO = 1.0
-- A one-fight line's bar (wowsims.gate's replay): one calibration per fight, so a single slow or fast calibration moves
-- the whole line's ratio, where a many-fight line averages them. Feral replay alone: median 0.50, p90 0.81; worst 0.893
-- at 16-wide, 0.909 at 24-wide.
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
