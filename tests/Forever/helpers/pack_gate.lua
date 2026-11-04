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
    ["Arms"] = { flicker = 0.3, retracted = 0.1, readyShort = 173, heldReady = 340 }, -- 0.24 / 0.17 / 0.26, 0 / 0.02 / 0
    -- flickerK 0.6 (this label only): seeds 1-20 read 0.85 vs an oracle of 0.30 (gap 0.55; 21-40: 0.81 vs 0.30). W1 made the
    -- oracle quieter, 0.36 -> 0.30, while our own flicker fell to 0.85 (owner 2026-11-03)
    ["Fury L60"] = { flicker = 0.9, flickerK = 0.6, retracted = 0.2, readyShort = 116, heldReady = 226 }, -- 0.85 / 0.84 / 0.54, 0.07 / 0.00 / 0.06
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
    ["Fury L24"] = { flicker = 1.1, flickerK = 0.6, retracted = 0.2, readyShort = 46, heldReady = 337 }, -- 0.86 / 1.08 / 0.98, 0.09 / 0.17 / 0.06; 36 / 38 / 46, 337 / 332 / 313
    -- none -> floored (gap CI, 2026-10-31; seeds 1-20 / 21-40 / 41-60, measured after the Warrior world resolved every
    -- rank of a kit addition and Revenge's window reached the client (review C1: the world tests the swing's target by
    -- guid, the observer's answers see a proxy of us); oracle flicker 0.42 / 0.42 / 0.45, gap 0.32 / 0.15 / 0.12 under K;
    -- agreement 0.925 / 0.929 / 0.926, unmatched cost 1.0 / 0.6 / 0.6, cooldown 0): the swing-paid rage class
    -- (sunder_armor <-> shield_block, shield_slam <-> thunder_clap, shield_block <-> rend near-ties on a forecast swing's
    -- rage)
    -- heldReady 378 -> 383 (seeds 1-20; 377 with f1f5cf772 reversed): Blood Fury's 2 min cooldown (owner, live 2026-11-02)
    -- readyShort 203 -> 204 (seeds 1-20; 203 at its parent f9065270a): 79f79d52c's floor lift on a yes that shows a
    -- pending swing landed (GAP AK; controller ruling 2026-11-03)
    ["Warrior Protection"] = { flicker = 0.8, retracted = 0.1, readyShort = 204, heldReady = 383 }, -- 0.74 / 0.57 / 0.57, 0 / 0.03 / 0.02
    -- 1.1 -> 1.3 (gap CE; seeds 1-20 / 21-40 / 41-60: 1.20 / 1.24 / 1.10, was 0.82 / 1.05 / 0.81; oracle 1.42 / 1.70 / 1.25):
    -- the mark on a floor inside the ready wait gives back part of the near-tie gain to close dim never promote (refused
    -- 0.8 / 1.6 / 1.5 -> 0, agreement .970 / .969 / .958 -> .973 / .971 / .971); under base's 1.23 / 1.44 / 1.16 on every
    -- seed set; owner standing approval 2026-10-30
    -- heldReady 383 -> 393 (seeds 1-20; 347 with Druid.lua and druid_world as of its parent): Shifting Power's 8 s
    -- cooldown (hotfix 113554, 8b07b2d58)
    ["Feral"] = { flicker = 1.3, retracted = 0, heldReady = 393 }, -- 1.20 / 1.24 / 1.10, 0
    ["Balance"] = { flicker = 0.1, retracted = 0, heldReady = 140 }, -- 0.03 / 0.05 / 0.07, 0
    -- none -> floored (gap CH, 2026-10-31, measured on d7b972d76 at seeds 1-20 / 21-40 / 41-60; oracle flicker 0.30 /
    -- 0.37 / 0.21): the swing-paid rage class (a forecast swing's gain shows Lacerate or Primal Bite ready; retracted
    -- is lacerate:swing/cost). Applied on the reported branch: Guardian clears M.gate's agreement (0.900 / 0.896 /
    -- 0.881), react and health, but its unmatched cost refusals read 2.3 / 2.5 / 3.5 against the plain bar 3 and its
    -- flicker sits 0.47 / 0.54 / 0.83 over the oracle's against FLICKER_K 0.5, so the gated branch would hold only at
    -- seeds 1-20; neither bar is loosened for it.
    ["Guardian"] = { flicker = 1.1, retracted = 0.7, readyShort = 190, heldReady = 330 }, -- 0.77 / 0.91 / 1.03, 0.35 / 0.54 / 0.60
    ["Assassination"] = { flicker = 0, retracted = 0, heldReady = 329 }, -- 0 / 0 / 0, 0
    -- 0.1 -> 0.2 (gap CE; 0.15 / 0 / 0.02, was 0.04 / 0 / 0, oracle 0.04 / 0.06 / 0.04): seeds 1-20 flips 2 (round 2)
    -- -> 7, base 15; the extra 5 are fight 8, t 23.0-24.2, sinister_strike vs slice_and_dice, no capped read in either
    -- tree, flips match base's tick for tick; Sinister Strike's entry is gated on `!(buff.slice_and_dice.remains<=2)`,
    -- inferred as an energy wait against that window; base's floor was 0.4; owner standing approval 2026-10-30
    ["Combat"] = { flicker = 0.2, retracted = 0, heldReady = 356 }, -- 0.15 / 0 / 0.02, 0
    ["Subtlety"] = { flicker = 0.1, retracted = 0, heldReady = 382 }, -- 0.02 / 0 / 0, 0 (gap CE)
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
    ["Survival"] = { flicker = 0.2, retracted = 0, readyShort = 1, heldReady = 254 }, -- 0.15 / 0.07 / 0.15, 0 (oracle 1.71 / 1.46 / 1.61), 249 / 232 / 254
    ["Marksmanship"] = { flicker = 0, retracted = 0, heldReady = 112 }, -- 0, 0
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
    ["Beast Mastery"] = { flicker = 0, retracted = 0, heldReady = 127 }, -- 0 / 0 / 0, 0 (gap CE)
    -- 0.1 -> 0.9 (Task 7; seeds 1-20 / 21-40 / 41-60: 0.47 / 0.88 / 0.77, was 0.04 / 0 / 0.02; oracle 0.66 / 1.23 / 1.01):
    -- wowsims's logged regen (Ret 8.25/s casting) runs the world at an empty mana pool; the oracle's flicker rose too; our
    -- extra disagreement is gap AB (lo = 0 at an empty pool vs truth ~16: Judgement vs Holy Strike); controller ruling
    -- 2026-10-30 while the owner was away
    -- 0.9 -> 0.6 (gap CE, the facade's whole-number read gone; oracle 0 / 0.29 / 0)
    -- 0.6 -> 0.5 (decision 63's rule, gap CE, the capped read follows the fold)
    -- readyShort 1: judgement at wait 0.04 with lo 0.04 under truth, no short answer yet, the oracle showing the same wait
    ["Retribution"] = { flicker = 0.5, retracted = 0, readyShort = 1, heldReady = 271 }, -- 0.29 / 0.47 / 0.40, 0 (oracle 0.53 / 0.22 / 0.02)
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
    ["Protection"] = { flicker = 0.2, retracted = 0, heldReady = 326 }, -- 0.10 / 0.17 / 0.12, 0 (oracle 0.07 / 0 / 0.07)
    -- 0.1 -> 0.2 (Task 4, wowsims's Shaman regen in): estimate pinned at the crossing floor, 3-8 mana low at ~30 mana/s;
    -- a pick ~0.23 s from its cost slips a tick (owner ruling 2026-10-29, fallback of option 2)
    -- 0.2 -> 0.3 (Task 11, Mana Spring Totem's mp5 as its own entry; seeds 1-20 / 21-40 / 41-60: 0.10 / 0.25 / 0.22, was
    -- 0.12 / 0.07 / 0.1996; oracle 0.13 / 0.00 / 0.02): Task 11 re-times Enhancement's fights (the world's starting mana
    -- now truthful to the log) onto Stormstrike / Lightning Shield near-ties where the estimate sits 2-3 mana under truth
    -- at the crossing floor (Task 4's mechanism, gap BT; the swap test shows the Mana Spring entry is not involved); the
    -- one-poll-wider near-cost window (task-4c-wip.patch) fixes it but loosens Protection and Affliction instead;
    -- owner-approved standing named-cause policy, 2026-10-30 (controller ruling (b), task-4c-report.md)
    -- 0.3 -> 0.2 (decision 63's rule, gap CE; most of the Task 11 near-ties above went with the whole-number read)
    ["Enhancement"] = { flicker = 0.2, retracted = 0, heldReady = 230 }, -- 0.13 / 0.13 / 0.13, 0 (oracle 0.03 / 0 / 0.02)
    -- heldReady 134 -> 105 (re-pin e2842f0a78, the Mage fix round: seeds 1-20 / 21-40 / 41-60 104 / 98 / 105)
    ["Arcane"] = { flicker = 0.1, retracted = 0, heldReady = 105 }, -- 0.02 / 0 / 0.02, 0
    -- heldReady 116 -> 175 (re-pin e2842f0a78; seeds 1-20 / 21-40 / 41-60 175 / 171 / 172, the fix round): the new
    -- list runs dry onto the Scorch filler; 174 of the 175 ticks (seeds 1-20) are Scorch at its 150 cost crossing, one
    -- tick an episode, lo 141-150 against the truth's 150-152 (gap BQ)
    -- flicker 0.3 -> 0.1 (the same sweep: 0 / 0 / 0; the loops do not show gap CQ's replay flash)
    ["Fire"] = { flicker = 0.1, retracted = 0, heldReady = 175 }, -- 0 / 0 / 0, 0
    -- 0.2 -> 0.3 (Task 6; seeds 1-20 / 21-40 / 41-60: 0.12 / 0.20 / 0.23, was 0.17 / 0.13 / 0.07): the world credits
    -- Evocation's mana on the 0.1 s regen tick (wowsims) instead of 1 s channel lumps; same total, every fight re-timed
    -- after its Evocation, more fights reach the existing frostfire_bolt <-> scorch pooling edge (gap BS); isolated by
    -- swapping pack and world; controller ruling 2026-10-30 while the owner was away
    -- 0.2 -> 0.1 (decision 63's rule, gap CE, a short answer's cap reads a whole unit under)
    -- heldReady 124 -> 112 (re-pin e2842f0a78, the Mage fix round: 112 / 110 / 97)
    ["Frostfire"] = { flicker = 0.1, retracted = 0, heldReady = 112 }, -- 0.02 / 0.03 / 0.03, 0 (oracle 0.03 / 0.02 / 0.07)
    ["Shadow"] = { flicker = 0.1, retracted = 0, heldReady = 405 }, -- 0.03 / 0.02 / 0.02, 0
    -- retracted 0.9 -> 0: 0.83 (oracle 0.63, Shoot at mana.pct<=10) before gap BD's cast bar, 0 / 0 / 0 after
    ["Smite"] = { flicker = 0.1, retracted = 0, heldReady = 0 }, -- 0.03 / 0.02 / 0.03, 0
    -- 0.1 -> 0.2 (Task 4, wowsims's Shaman regen in; seeds 1-20 / 21-40 / 41-60: 0.15 / 0.1996 / 0.17, was 0.03 / 0.03 /
    -- 0.02; oracle 0.03 / 0.03 / 0.03): estimate pinned at the crossing floor, 3-8 mana low at ~30 mana/s; a pick ~0.23 s
    -- from its cost slips a tick (owner ruling 2026-10-29, fallback of option 2). After Task 11 (Mana Spring Totem's
    -- mp5 as its own entry): 0.13 / 0.17 / 0.08, oracle 0.05 / 0.07 / 0.05, floor kept
    -- 0.2 -> 0.1 (decision 63's rule, gap CE, the whole-number read gone)
    ["Elemental"] = { flicker = 0.1, retracted = 0, heldReady = 301 }, -- 0.02 / 0.03 / 0.10, 0 (oracle 0.05 / 0.07 / 0.05)
    -- 0.4 -> 0 (Task 10, a paid channel holds the five-second rule's casting rate to its end; seeds 1-20 / 21-40 / 41-60:
    -- 0 / 0 / 0, was 0 / 0.32 / 0.02): Wrack's 6 s paid channel no longer resumes the spirit part 5 s in, so the mana
    -- estimate stops running ahead of truth at its end, where Life Tap and Wrack were a near-tie (agreement .993 -> .996
    -- on seeds 21-40); controller rule, the measured values beside the line
    ["Affliction"] = { flicker = 0, retracted = 0, heldReady = 5 }, -- 0 / 0 / 0, 0
    ["SM Ruin"] = { flicker = 0.3, retracted = 0, heldReady = 6 }, -- 0.25 / 0.12 / 0.27, 0
    ["Demonology"] = { flicker = 0.1, retracted = 0, heldReady = 4 }, -- 0.02 / 0.05 / 0, 0
    ["Shadow Brand"] = { flicker = 0.1, retracted = 0, heldReady = 3 }, -- 0.03 / 0.02 / 0.02, 0
    -- the excess over the oracle (0 / 0 / 0) is at Conflagrate's and Shadowburn's cooldown ends, as Fire's Fire Blast
    -- (the not-ready flag's CD_PROBE, central)
    ["Destruction"] = { flicker = 0.4, retracted = 0, heldReady = 8 }, -- 0.23 / 0.3991 / 0.25, 0
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
    ab.check(r.reactMedian <= 1 and r.reactP90 <= 3, at, line)
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
    if n >= 20 and not m.hold and not m.steady then -- the floors are the unheld display's
        M.flicker(label, r, line, reported)
    end
    return r, line
end

return M
