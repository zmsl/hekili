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
-- named cause recorded beside it. Guardian is reported, not floored.
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
M.FLICKER = {
    ["Arms"] = { flicker = 0.3, retracted = 0.1, readyShort = 173 }, -- 0.24 / 0.17 / 0.26, 0 / 0.02 / 0
    ["Fury L60"] = { flicker = 0.9, retracted = 0.2, readyShort = 116 }, -- 0.81 / 0.70 / 0.88, 0.20 / 0.17 / 0.06
    ["Fury L24"] = { flicker = 0.8, retracted = 0.2, readyShort = 41 }, -- 0.68 / 0.75 / 0.66, 0.09 / 0.18 / 0.03
    -- 1.1 -> 1.3 (gap CE; seeds 1-20 / 21-40 / 41-60: 1.20 / 1.24 / 1.10, was 0.82 / 1.05 / 0.81; oracle 1.42 / 1.70 / 1.25):
    -- the mark on a floor inside the ready wait gives back part of the near-tie gain to close dim never promote (refused
    -- 0.8 / 1.6 / 1.5 -> 0, agreement .970 / .969 / .958 -> .973 / .971 / .971); still under base's 1.23 / 1.44 / 1.16
    -- but for seeds 21-40's 1.24 > 1.05; owner standing approval 2026-10-30
    ["Feral"] = { flicker = 1.3, retracted = 0 }, -- 1.20 / 1.24 / 1.10, 0
    ["Balance"] = { flicker = 0.1, retracted = 0 }, -- 0.03 / 0.05 / 0.07, 0
    ["Assassination"] = { flicker = 0, retracted = 0 }, -- 0 / 0 / 0, 0
    -- 0.1 -> 0.2 (gap CE; 0.15 / 0 / 0.02, was 0.04 / 0 / 0, oracle 0.04 / 0.06 / 0.04; fights re-timed by the mark on a
    -- floor inside the ready wait, as Feral, flips not traced one by one); owner standing approval 2026-10-30
    ["Combat"] = { flicker = 0.2, retracted = 0 }, -- 0.15 / 0 / 0.02, 0
    ["Subtlety"] = { flicker = 0.1, retracted = 0 }, -- 0.02 / 0 / 0, 0 (gap CE)
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
    ["Survival"] = { flicker = 0.3, retracted = 0 }, -- 0.27 / 0.08 / 0.15, 0 (oracle 2.03 / 2.00 / 1.96, gap CE)
    ["Marksmanship"] = { flicker = 0, retracted = 0 }, -- 0, 0
    -- 0 -> 0.2 (Task 5, wowsims's Hunter regen in; seeds 1-20 / 21-40 / 41-60: 0 / 0.12 / 0, was 0 / 0 / 0): the new BM
    -- regen puts Arcane Shot's mana crossing 0.14 s from Hunter's Mark's refresh; lo runs ~3 mana under truth (gaps
    -- BQ/BT, G7), so the near-tie resolves both ways (fight 21); controller ruling 2026-10-29 while the owner was away
    -- (logged in hekili-open-questions.md); the oracle's own 0.02 / 0 / 0 (agreement 0.998 / 0.996 / 0.999)
    ["Beast Mastery"] = { flicker = 0, retracted = 0 }, -- 0 / 0 / 0, 0 (gap CE)
    -- 0.1 -> 0.9 (Task 7; seeds 1-20 / 21-40 / 41-60: 0.47 / 0.88 / 0.77, was 0.04 / 0 / 0.02; oracle 0.66 / 1.23 / 1.01):
    -- wowsims's logged regen (Ret 8.25/s casting) runs the world at an empty mana pool; the oracle's flicker rose too; our
    -- extra disagreement is gap AB (lo = 0 at an empty pool vs truth ~16: Judgement vs Holy Strike); controller ruling
    -- 2026-10-30 while the owner was away
    -- 0.9 -> 0.6 (gap CE, the facade's whole-number read gone; oracle 0 / 0.29 / 0)
    -- 0.6 -> 0.5 (decision 63's rule, gap CE, the capped read follows the fold)
    -- readyShort 1: judgement at wait 0.04 with lo 0.04 under truth, no short answer yet, the oracle showing the same wait
    ["Retribution"] = { flicker = 0.5, retracted = 0, readyShort = 1 }, -- 0.29 / 0.47 / 0.40, 0 (oracle 0.53 / 0.22 / 0.02)
    -- 0.5 -> 0.8 (Task 7; seeds 1-20 / 21-40 / 41-60: 0.54 / 0.71 / 0.49, was 0.45 / 0.03 / 0.68; oracle 0.59 / 1.81 / 1.73):
    -- wowsims's logged regen (Prot 0 casting) runs the world at an empty mana pool; the oracle's flicker rose to 0.59-1.81;
    -- our extra disagreement is gap AB (lo = 0 at an empty pool vs truth ~16: Judgement vs Holy Strike, agreement .99 ->
    -- .91); controller ruling 2026-10-30 while the owner was away. Supersedes the 2026-10-29 owner ruling (seed chaos at
    -- 41-60 after Task 4a, floor kept): that note's near-tie wobble is gap AB too; steady icons (experimental) is the
    -- player's remedy.
    -- 0.8 -> 0.2 (gap CE, the facade's whole-number read gone): most of the flicker the two notes above blame on gap AB
    -- was that read; gap AB's agreement cost stands
    ["Protection"] = { flicker = 0.2, retracted = 0 }, -- 0.10 / 0.17 / 0.12, 0 (oracle 0.07 / 0 / 0.07)
    -- 0.1 -> 0.2 (Task 4, wowsims's Shaman regen in): estimate pinned at the crossing floor, 3-8 mana low at ~30 mana/s;
    -- a pick ~0.23 s from its cost slips a tick (owner ruling 2026-10-29, fallback of option 2)
    -- 0.2 -> 0.3 (Task 11, Mana Spring Totem's mp5 as its own entry; seeds 1-20 / 21-40 / 41-60: 0.10 / 0.25 / 0.22, was
    -- 0.12 / 0.07 / 0.1996; oracle 0.13 / 0.00 / 0.02): Task 11 re-times Enhancement's fights (the world's starting mana
    -- now truthful to the log) onto Stormstrike / Lightning Shield near-ties where the estimate sits 2-3 mana under truth
    -- at the crossing floor (Task 4's mechanism, gap BT; the swap test shows the Mana Spring entry is not involved); the
    -- one-poll-wider near-cost window (task-4c-wip.patch) fixes it but loosens Protection and Affliction instead;
    -- owner-approved standing named-cause policy, 2026-10-30 (controller ruling (b), task-4c-report.md)
    -- 0.3 -> 0.2 (decision 63's rule, gap CE; most of the Task 11 near-ties above went with the whole-number read)
    ["Enhancement"] = { flicker = 0.2, retracted = 0 }, -- 0.13 / 0.13 / 0.13, 0 (oracle 0.03 / 0 / 0.02)
    ["Arcane"] = { flicker = 0.1, retracted = 0 }, -- 0.02 / 0 / 0, 0
    ["Fire"] = { flicker = 0.3, retracted = 0 }, -- 0.22 / 0.13 / 0.12, 0
    -- 0.2 -> 0.3 (Task 6; seeds 1-20 / 21-40 / 41-60: 0.12 / 0.20 / 0.23, was 0.17 / 0.13 / 0.07): the world credits
    -- Evocation's mana on the 0.1 s regen tick (wowsims) instead of 1 s channel lumps; same total, every fight re-timed
    -- after its Evocation, more fights reach the existing frostfire_bolt <-> scorch pooling edge (gap BS); isolated by
    -- swapping pack and world; controller ruling 2026-10-30 while the owner was away
    -- 0.2 -> 0.1 (decision 63's rule, gap CE, a short answer's cap reads a whole unit under)
    ["Frostfire"] = { flicker = 0.1, retracted = 0 }, -- 0.05 / 0.03 / 0, 0 (oracle 0.13 / 0.13 / 0.10)
    ["Shadow"] = { flicker = 0.1, retracted = 0 }, -- 0.03 / 0.02 / 0.02, 0
    -- retracted 0.9 -> 0: 0.83 (oracle 0.63, Shoot at mana.pct<=10) before gap BD's cast bar, 0 / 0 / 0 after
    ["Smite"] = { flicker = 0.1, retracted = 0 }, -- 0.03 / 0.02 / 0.03, 0
    -- 0.1 -> 0.2 (Task 4, wowsims's Shaman regen in; seeds 1-20 / 21-40 / 41-60: 0.15 / 0.1996 / 0.17, was 0.03 / 0.03 /
    -- 0.02; oracle 0.03 / 0.03 / 0.03): estimate pinned at the crossing floor, 3-8 mana low at ~30 mana/s; a pick ~0.23 s
    -- from its cost slips a tick (owner ruling 2026-10-29, fallback of option 2). After Task 11 (Mana Spring Totem's
    -- mp5 as its own entry): 0.13 / 0.17 / 0.08, oracle 0.05 / 0.07 / 0.05, floor kept
    -- 0.2 -> 0.1 (decision 63's rule, gap CE, the whole-number read gone)
    ["Elemental"] = { flicker = 0.1, retracted = 0 }, -- 0.02 / 0.03 / 0.10, 0 (oracle 0.05 / 0.07 / 0.05)
    -- 0.4 -> 0 (Task 10, a paid channel holds the five-second rule's casting rate to its end; seeds 1-20 / 21-40 / 41-60:
    -- 0 / 0 / 0, was 0 / 0.32 / 0.02): Wrack's 6 s paid channel no longer resumes the spirit part 5 s in, so the mana
    -- estimate stops running ahead of truth at its end, where Life Tap and Wrack were a near-tie (agreement .993 -> .996
    -- on seeds 21-40); controller rule, the measured values beside the line
    ["Affliction"] = { flicker = 0, retracted = 0 }, -- 0 / 0 / 0, 0
    ["SM Ruin"] = { flicker = 0.3, retracted = 0 }, -- 0.25 / 0.12 / 0.27, 0
    ["Demonology"] = { flicker = 0.1, retracted = 0 }, -- 0.02 / 0.05 / 0, 0
    ["Shadow Brand"] = { flicker = 0.1, retracted = 0 }, -- 0.03 / 0.02 / 0.02, 0
    -- the excess over the oracle (0 / 0 / 0) is at Conflagrate's and Shadowburn's cooldown ends, as Fire's Fire Blast
    -- (the not-ready flag's CD_PROBE, central)
    ["Destruction"] = { flicker = 0.4, retracted = 0 }, -- 0.23 / 0.3991 / 0.25, 0
}
-- Our first-icon flicker at most the oracle shadow's plus K, every gated 20-fight loop: the widest measured gap rounded
-- up to the next 0.1. It tightens the bar when a change lowers the oracle's own flicker. 1.8 -> 0.5 (forever-gap-bd,
-- 2026-10-26, the press rule and gap BD's cast bar; every gated pack, seeds 1-20 / 21-40 / 41-60): the widest gap is
-- Fury L60 seeds 21-40, 0.70 vs 0.23 (0.466); next Protection seeds 1-20, 0.46 vs 0. Before, Balance seeds 1-20 read
-- 2.36 vs 1.23 on f09656c8e (gap 1.13: the old comment's oracle 0.65 was stale), all of it gap BD's invisible cast bar.
M.FLICKER_K = 0.5

--- The flicker floors of `label` (M.FLICKER) and flicker <= oracle + FLICKER_K, reported next to react p90 and the
--- unmatched cost refusals (the line).
function M.flicker(label, r, line)
    local fl = M.FLICKER[label]
    if fl then
        ab.check(r.flicker <= fl.flicker, label, "flicker floor: " .. line)
        ab.check(r.retracted <= fl.retracted, label, "retracted-ready floor: " .. line)
        ab.check(r.readyShort <= (fl.readyShort or 0), label, "ready-while-short floor: " .. line)
    end
    ab.check(r.flicker <= r.oracleFlicker + M.FLICKER_K, label, "flicker over the oracle's + K: " .. line)
end

-- The CPU bar (D5), on the ratio of each tick's process CPU to the in-process calibration timed once per fight
-- (loop.calibrate), not on ms: load from other processes slows both, so the bar stops depending on what else runs. Set
-- to the old 10 ms bar on a quiet run, so it did not loosen: 10 ms / the ~7 ms calibration = 1.4. Measured: Arms 20
-- fights alone 3.96 ms, ratio 0.555 (2026-10-30, under the lock); under a 16-wide `make test` beside it: Feral 3 fights
-- 4.25 -> 5.82 ms, ratio 0.634 -> 0.494; Arms 3 fights 3.78 -> 5.92 ms, ratio 0.624 -> 0.547 (the calibration slows a
-- little more than the engine, so load lowers the ratio: the safe direction).
M.CPU_RATIO = 1.4

--- The engine's health, gated at any fight count: no error, raise, self-check miss, unlisted read or secret, CPU.
function M.health(m, r, line)
    assert.are.same({ 0, 0, 0 }, { m.errors, m.raises, m.selfCheck })
    assert.are.same({}, m.misses)
    assert.are.same({}, m.secrets) -- no facade passthrough answered a secret (the traced first fight)
    assert.is_true(r.cpuRatio <= M.CPU_RATIO, line) -- the ms mean and p99 reported
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
    M.health(m, r, line)
end

--- `n` fights of `world` on a fresh boot (seeds `seed0` + 1 ..), the `<label> solo:` line printed (`tag` appended in
--- brackets), gated; `reported`: the engine's health only, " (reported)" appended. DPS A/B and never-reacts are
--- reported, not gated. Returns the summary (`r.focus`: run A's in-combat ticks whose first record has `focus` set,
--- kept out of the line) and the line.
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
        if n >= 20 and not m.hold and not m.steady then -- the floors are the unheld display's
            M.flicker(label, r, line)
        end
    end
    return r, line
end

return M
