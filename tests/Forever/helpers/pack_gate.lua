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

-- The flicker floors at 20 fights: per label the first-icon flicker/min and the unjustified retracted readies/min
-- (tests/Game/harness/flicker.lua), each the measured value (beside it) rounded up to the next 0.1, 0 where it measured
-- 0 (the loops are deterministic). A floor only moves down, except with a named cause recorded beside it. Guardian is
-- reported, not floored. Re-measured on fix 22's truth resolve (forever b0a5f8ee: a press resolved from the truth
-- instance, hard casts and channels in the world), which moved Arms 1.38 -> 1.57, Feral 2.07 -> 2.12, Balance
-- 1.63 -> 2.51 and Protection 0.65 -> 0.31; the hard casts' starts now justify a retraction (Arms's Slam 0.59 -> 0.02).
-- Parry-haste spec decision 63: the world models parry haste; its swing reschedule reorders every seeded fight, so a
-- floor that failed in any seed set (1-20 / 21-40 / 41-60), or improved in all three, is the worst of the three rounded
-- up to the next 0.1 (the "1 / 2 / 3" beside it). Fury L60 retracted 0.4: the pre-existing swing-forecast class (a
-- cost-gated ability shown ready on a swing's forecast rage; oracle 0.09/min over the 60 fights).
M.FLICKER = {
    ["Arms"] = { flicker = 1.5, retracted = 0.1 }, -- 1.43 / 1.21 / 1.43, 0 / 0.02 / 0 (decision 63)
    -- 1.69, 0.09 with the user's Berserker Rage ruling on fix 23's pre-pull guards (before fix 23 the ruling's phase
    -- shift measured 1.44, 0.13: one more Execute retracted at a swing); 1.71, 0.09 before the ruling
    ["Fury L60"] = { flicker = 1.9, retracted = 0.4 }, -- 1.77 / 1.57 / 1.88, 0.33 / 0.17 / 0.03 (decision 63)
    ["Fury L24"] = { flicker = 2.9, retracted = 0.2 }, -- 2.86 / 2.75 / 2.54, 0.12 / 0.06 / 0.03 (decision 63)
    ["Feral"] = { flicker = 2.0, retracted = 0 }, -- 1.91 / 1.75 / 1.48, 0 (decision 63)
    ["Balance"] = { flicker = 2.4, retracted = 0 }, -- 2.32 / 2.22 / 2.00, 0 (decision 63)
    ["Assassination"] = { flicker = 0.1, retracted = 0 }, -- 0 / 0 / 0.02, 0 (decision 63; fix 29 had 0)
    ["Combat"] = { flicker = 0.4, retracted = 0 }, -- 0.38 / 0.13 / 0.13, 0 (decision 63)
    ["Subtlety"] = { flicker = 0.4, retracted = 0 }, -- 0.20 / 0.04 / 0.38, 0 (decision 63)
    ["Survival"] = { flicker = 0.2, retracted = 0 }, -- 0.15, 0
    ["Marksmanship"] = { flicker = 0, retracted = 0 }, -- 0, 0
    ["Beast Mastery"] = { flicker = 0, retracted = 0 }, -- 0, 0
    -- fix 23's pre-pull guards re-seal before every pull, so the combat twist spends more mana and near an empty pool
    -- our rounded waits trade places with Holy Strike (near-tie wobble of the mana belief, gap AB); steady icons
    -- (experimental) is the player's remedy; the oracle reads 0.03 and 0.12
    -- (Protection; Retribution measured 0.57 with its pre-pull Seal of Command, 0.19 since prepullSkip drops it)
    -- 0.21, 0 (was 0.19): harness corrected to the measured swing timing (2026-10-22); 0.19 at fix 23 with prepullSkip
    ["Retribution"] = { flicker = 0.5, retracted = 0 }, -- 0.46 / 0.29 / 0.23, 0 (decision 63; oracle 0.35 / 0.29 / 0.20)
    ["Protection"] = { flicker = 0.6, retracted = 0 }, -- 0.58, 0 (was 0.31: fix 23, above)
    ["Enhancement"] = { flicker = 1.3, retracted = 0 }, -- 1.21 / 1.03 / 1.03, 0 (decision 63)
    -- flicker 1.4 -> 1.5: parry off for casters (3cfdb4cec) reshuffles the dice (oracle too); owner ruling 2026-10-26
    ["Arcane"] = { flicker = 1.5, retracted = 0 }, -- 1.33 / 1.18 / 1.26, 0 (decision 63)
    ["Fire"] = { flicker = 1.3, retracted = 0 }, -- 1.21, 0
    ["Frostfire"] = { flicker = 0.3, retracted = 0 }, -- 0.30, 0 (oracle 0.38; Task FFB, M13)
    ["Shadow"] = { flicker = 0.3, retracted = 0 }, -- 0.27, 0 (oracle 0.15; Priest lane, Task 14)
    ["Smite"] = { flicker = 0.5, retracted = 0.9 }, -- 0.45, 0.83 (oracle 0.12, 0.63): Shoot at mana.pct<=10; candidate GAP AB
    -- flicker 0.6 -> 0.7: parry off for casters (3cfdb4cec) reshuffles the dice (oracle too); owner ruling 2026-10-26
    ["Elemental"] = { flicker = 0.7, retracted = 0.1 }, -- 0.53 / 0.37 / 0.52, 0 / 0 / 0.02 (decision 63)
    -- 1.60, 0 (oracle 1.60; Warlock lane, Task 13, on 06eec227): no headroom, the floor is the measurement rounded up
    -- to 0.1 and 1.60 is on it (Frostfire's 0.30 precedent)
    -- retracted 0 -> 0.1: parry off for casters (3cfdb4cec) reshuffles the dice (oracle too); owner ruling 2026-10-26
    ["Affliction"] = { flicker = 1.8, retracted = 0.1 }, -- 1.60 / 1.71 / 1.45, 0 (decision 63)
    ["SM Ruin"] = { flicker = 5.1, retracted = 0 }, -- 4.81 / 5.02 / 4.61, 0 (decision 63)
    ["Demonology"] = { flicker = 3.4, retracted = 0 }, -- 3.36, 0 (oracle 3.38)
    -- flicker 3.0 -> 3.4: parry off for casters (3cfdb4cec) reshuffles the dice (oracle too); owner ruling 2026-10-26
    ["Shadow Brand"] = { flicker = 3.4, retracted = 0 }, -- 2.81 / 2.89 / 2.98, 0 (decision 63)
    -- 4.51, 0 (oracle 3.38): the excess is at Conflagrate's and Shadowburn's cooldown ends (the loop's top pairs
    -- conflagrate -> incinerate 102, conflagrate -> shadowburn 27; dips by class cooldown 134), as Fire's Fire Blast
    -- (the not-ready flag's CD_PROBE, central); not measured flicker by flicker
    ["Destruction"] = { flicker = 4.6, retracted = 0 },
}
-- Our first-icon flicker at most the oracle shadow's plus K, every gated 20-fight loop: the widest measured gap rounded
-- up to the next 0.1. Redundant with the floors today; it tightens the bar when a change lowers the oracle's own
-- flicker. 1.5 (Balance 1.63 vs 0.27) -> 1.6: re-measured on fix 22's truth resolve, Balance 2.51 vs 0.99 (1.52).
M.FLICKER_K = 1.7 -- decision 63: Balance 2.32 vs 0.69 (1.63) on seeds 1-20

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
