-- tests/Forever/helpers/pack_gate.lua: the per-pack headless gate (class-completion plan, "The per-pack gate"), the
-- Arms gate's body made class-neutral: `world` is a pack's tests/Forever/helpers/<class>_world.lua (the loop's
-- content), `label` the spec name printed before " solo:". Thresholds: headless loop design §5.2 (as built: the plan's
-- Deviations 7-8, 14-15); the Arms values they were set on: helpers/arms_gate.lua.
local assert = require("luassert")
local loop = require("Game.harness.loop")

local M = {}

-- The most cost refusals per 100 attempts the oracle shadow would not have made (loop.unmatched), a plain bar.
M.UNMATCHED = 3

-- The flicker floors at 20 fights (the flicker ledger's first clean run, 2026-10-21, forever-flicker): per label the
-- first-icon flicker/min and the unjustified retracted readies/min (tests/Game/harness/flicker.lua), each the measured
-- value (beside it) rounded up to the next 0.1, 0 where it measured 0 (the loops are deterministic). A floor only
-- moves down, except with a named cause recorded beside it. Guardian is reported, not floored.
M.FLICKER = {
    ["Arms"] = { flicker = 1.4, retracted = 0.6 }, -- 1.38, 0.59
    ["Fury L60"] = { flicker = 1.8, retracted = 0.1 }, -- 1.71, 0.09
    ["Fury L24"] = { flicker = 3.4, retracted = 0.2 }, -- 3.31, 0.12
    ["Feral"] = { flicker = 2.1, retracted = 0 }, -- 2.07, 0
    ["Balance"] = { flicker = 1.7, retracted = 0 }, -- 1.63, 0
    ["Assassination"] = { flicker = 0.1, retracted = 0 }, -- 0.10, 0
    ["Combat"] = { flicker = 0.3, retracted = 0 }, -- 0.28, 0
    ["Subtlety"] = { flicker = 0.3, retracted = 0 }, -- 0.23, 0
    ["Survival"] = { flicker = 0.2, retracted = 0 }, -- 0.15, 0
    ["Marksmanship"] = { flicker = 0, retracted = 0 }, -- 0, 0
    ["Beast Mastery"] = { flicker = 0, retracted = 0 }, -- 0, 0
    ["Retribution"] = { flicker = 0.3, retracted = 0 }, -- 0.28, 0
    ["Protection"] = { flicker = 0.7, retracted = 0 }, -- 0.65, 0
    ["Enhancement"] = { flicker = 1.2, retracted = 0 }, -- 1.11, 0
}
-- Our first-icon flicker at most the oracle shadow's plus K, every gated 20-fight loop: the widest measured gap,
-- Balance's 1.36 (1.63 against 0.27), rounded up (owner's ruling: K stays). Redundant with the floors today; it
-- tightens the bar when a change lowers the oracle's own flicker.
M.FLICKER_K = 1.5

--- The flicker floors of `label` (M.FLICKER) and flicker <= oracle + FLICKER_K, reported next to react p90 and the
--- unmatched cost refusals (the line).
function M.flicker(label, r, line)
    local fl = M.FLICKER[label]
    if fl then
        assert.is_true(r.flicker <= fl.flicker, label .. " flicker floor: " .. line)
        assert.is_true(r.retracted <= fl.retracted, label .. " retracted-ready floor: " .. line)
    end
    assert.is_true(r.flicker <= r.oracleFlicker + M.FLICKER_K, label .. " flicker over the oracle's + K: " .. line)
end

--- The engine's health, gated at any fight count: no error, raise, self-check miss, unlisted read or secret, CPU.
function M.health(m, r, line)
    assert.are.same({ 0, 0, 0 }, { m.errors, m.raises, m.selfCheck })
    assert.are.same({}, m.misses)
    assert.are.same({}, m.secrets) -- no facade passthrough answered a secret (the traced first fight)
    assert.is_true(r.cpuMean <= 10, line) -- D5: about 4x the measured Arms mean; p99 reported
end

--- The engine and the first icon, gated at any fight count.
function M.gate(m, r, line)
    assert.is_true(r.agreement >= 0.85, line)
    assert.is_true(r.reactMedian <= 1 and r.reactP90 <= 3, line)
    assert.is_true((r.per100.gcd or 0) == 0 and (r.per100.cooldown or 0) == 0, line)
    -- our cost refusals the oracle shadow would not have made at that tick (loop.unmatched: the round-3 ruling); a
    -- refusal both make is the press protocol meeting the world's rage timing, kept visible in the raw rate
    assert.is_true((r.per100U.cost or 0) <= M.UNMATCHED, line)
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
        M.gate(m, r, line)
        if n >= 20 and not m.hold then -- the floors are the unheld display's
            M.flicker(label, r, line)
        end
    end
    return r, line
end

return M
