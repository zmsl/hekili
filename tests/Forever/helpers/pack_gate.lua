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
M.FLICKER = {
    ["Arms"] = { flicker = 0.3, retracted = 0.1 }, -- 0.24 / 0.17 / 0.26, 0 / 0.02 / 0
    ["Fury L60"] = { flicker = 0.9, retracted = 0.2 }, -- 0.81 / 0.70 / 0.88, 0.20 / 0.17 / 0.06
    ["Fury L24"] = { flicker = 0.8, retracted = 0.2 }, -- 0.68 / 0.75 / 0.66, 0.09 / 0.18 / 0.03
    ["Feral"] = { flicker = 1.5, retracted = 0 }, -- 1.35 / 1.4967 / 1.25, 0
    ["Balance"] = { flicker = 0.1, retracted = 0 }, -- 0.03 / 0.05 / 0.07, 0
    ["Assassination"] = { flicker = 0, retracted = 0 }, -- 0 / 0 / 0, 0
    ["Combat"] = { flicker = 0.4, retracted = 0 }, -- 0.32 / 0.02 / 0, 0
    ["Subtlety"] = { flicker = 0.4, retracted = 0 }, -- 0.18 / 0 / 0.34, 0
    ["Survival"] = { flicker = 0.1, retracted = 0 }, -- 0.05 / 0 / 0, 0
    ["Marksmanship"] = { flicker = 0, retracted = 0 }, -- 0, 0
    -- 0 -> 0.2 (Task 5, wowsims's Hunter regen in; seeds 1-20 / 21-40 / 41-60: 0 / 0.12 / 0, was 0 / 0 / 0): the new BM
    -- regen puts Arcane Shot's mana crossing 0.14 s from Hunter's Mark's refresh; lo runs ~3 mana under truth (gaps
    -- BQ/BT, G7), so the near-tie resolves both ways (fight 21); controller ruling 2026-10-29 while the owner was away
    -- (logged in hekili-open-questions.md)
    ["Beast Mastery"] = { flicker = 0.2, retracted = 0 }, -- 0 / 0.12 / 0, 0
    -- 0.1 -> 0.9 (Task 7; seeds 1-20 / 21-40 / 41-60: 0.47 / 0.88 / 0.77, was 0.04 / 0 / 0.02; oracle 0.66 / 1.23 / 1.01):
    -- wowsims's logged regen (Ret 8.25/s casting) runs the world at an empty mana pool; the oracle's flicker rose too; our
    -- extra disagreement is gap AB (lo = 0 at an empty pool vs truth ~16: Judgement vs Holy Strike); controller ruling
    -- 2026-10-30 while the owner was away
    ["Retribution"] = { flicker = 0.9, retracted = 0 }, -- 0.47 / 0.88 / 0.77, 0
    -- 0.5 -> 0.8 (Task 7; seeds 1-20 / 21-40 / 41-60: 0.54 / 0.71 / 0.49, was 0.45 / 0.03 / 0.68; oracle 0.59 / 1.81 / 1.73):
    -- wowsims's logged regen (Prot 0 casting) runs the world at an empty mana pool; the oracle's flicker rose to 0.59-1.81;
    -- our extra disagreement is gap AB (lo = 0 at an empty pool vs truth ~16: Judgement vs Holy Strike, agreement .99 ->
    -- .91); controller ruling 2026-10-30 while the owner was away. Supersedes the 2026-10-29 owner ruling (seed chaos at
    -- 41-60 after Task 4a, floor kept): that note's near-tie wobble is gap AB too; steady icons (experimental) is the
    -- player's remedy.
    ["Protection"] = { flicker = 0.8, retracted = 0 }, -- 0.54 / 0.71 / 0.49, 0 (oracle 0.59 / 1.81 / 1.73)
    -- 0.1 -> 0.2 (Task 4, wowsims's Shaman regen in): estimate pinned at the crossing floor, 3-8 mana low at ~30 mana/s;
    -- a pick ~0.23 s from its cost slips a tick (owner ruling 2026-10-29, fallback of option 2)
    ["Enhancement"] = { flicker = 0.2, retracted = 0 }, -- 0.12 / 0.07 / 0.1996, 0 (was 0.02 / 0 / 0.03)
    ["Arcane"] = { flicker = 0.1, retracted = 0 }, -- 0.02 / 0.02 / 0.03, 0
    ["Fire"] = { flicker = 0.3, retracted = 0 }, -- 0.22 / 0.13 / 0.12, 0
    -- 0.2 -> 0.3 (Task 6; seeds 1-20 / 21-40 / 41-60: 0.12 / 0.20 / 0.23, was 0.17 / 0.13 / 0.07): the world credits
    -- Evocation's mana on the 0.1 s regen tick (wowsims) instead of 1 s channel lumps; same total, every fight re-timed
    -- after its Evocation, more fights reach the existing frostfire_bolt <-> scorch pooling edge (gap BS); isolated by
    -- swapping pack and world; controller ruling 2026-10-30 while the owner was away
    ["Frostfire"] = { flicker = 0.3, retracted = 0 }, -- 0.12 / 0.20 / 0.23, 0 (oracle 0.28 / 0.20 / 0.23)
    ["Shadow"] = { flicker = 0.1, retracted = 0 }, -- 0.03 / 0.02 / 0.02, 0
    -- retracted 0.9 -> 0: 0.83 (oracle 0.63, Shoot at mana.pct<=10) before gap BD's cast bar, 0 / 0 / 0 after
    ["Smite"] = { flicker = 0.1, retracted = 0 }, -- 0.03 / 0.02 / 0.03, 0
    -- 0.1 -> 0.2 (Task 4, wowsims's Shaman regen in): estimate pinned at the crossing floor, 3-8 mana low at ~30 mana/s;
    -- a pick ~0.23 s from its cost slips a tick (owner ruling 2026-10-29, fallback of option 2)
    ["Elemental"] = { flicker = 0.2, retracted = 0 }, -- 0.15 / 0.1996 / 0.17, 0 (was 0.03 / 0.03 / 0.02)
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
    end
    ab.check(r.flicker <= r.oracleFlicker + M.FLICKER_K, label, "flicker over the oracle's + K: " .. line)
end

--- The engine's health, gated at any fight count: no error, raise, self-check miss, unlisted read or secret, CPU.
function M.health(m, r, line)
    assert.are.same({ 0, 0, 0 }, { m.errors, m.raises, m.selfCheck })
    assert.are.same({}, m.misses)
    assert.are.same({}, m.secrets) -- no facade passthrough answered a secret (the traced first fight)
    assert.is_true(r.cpuMean <= 10, line) -- D5: about 4x the measured Arms mean; p99 reported
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
