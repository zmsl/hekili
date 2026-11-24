-- tests/Forever/finisher_miss_spec.lua (lane finisher-miss, L1810; L1763, L1764): a missed 5-point Rip, and a missed
-- Rake, through the real Feral priority, the real belief and the fake client, Hekili.Update at the real driver's cadence
-- (helpers/finisher_world.lua). Owner report L1810: "when a rip misses, it recommends ferocious bite because it thinks
-- rip is up with 5cp". A missed finisher keeps its combo points (wowsims rip.go spends them only when it lands) and gives
-- 80% of its energy back (refundOnMiss), so a Rip believed up at 5 points shows Ferocious Bite.
-- The ways the miss reaches the belief:
--   1 its own avoid row after the success (window 0);
--   2 its row logged 15 ms before the success, the ticket still COMMITTED (L1763 case a, fix A; window 0);
--   3 its row in the frame of a white swing's row: the swing's core lag band takes it (L1763 case b, Rows.lua's MELEE
--     tie); also a swing fired in the row's own frame (SAME_FRAME). Window 0 without the Cooldown Manager, the verdict's
--     W with it;
--   4 no row, the Cooldown Manager's proven item never lights (the verdict at the cast + W, the deadline wake);
--   5 no row and no Cooldown Manager (Hekili.cdmOff, or the bleed not tracked; no LibHiddenValues either): pinned as
--     today's window (the belief keeps the bleed its full duration).
-- The mirror (lane swing-avoid-fix's Feral defect): Rip LANDS and a white swing's avoid falls in its window; Rip must
-- not be refunded nor believed down (the shapes of that lane's traced seeds 2 and 8, the core band, the swing's own ms).
-- Each case's assertions are M.check's (finisher_world.lua): slot 1 past the window, the believed bleed vs the truth,
-- the energy band vs the truth, the combo points, the flicker rule. A failure prints the case's timeline.
-- Tests only: a failing case is a finding for the controller (lane report), not fixed here.
local fw = require("Forever.helpers.finisher_world")

local ACTS = { "MISS", "DODGE", "PARRY" }
local TIE = -0.471 -- a swing whose row lands 3 ms after the success (LAND 0.474): the miss's row 1 ms later, in its band

local function run(c)
    local W, T = fw.case(c)
    if c.windowW then
        c.window = W.verdictW
    end
    local fails, sum = fw.check(W, T, c)
    assert.are.same({}, W.H.errors)
    return W, T, fails, sum
end

local function expectPass(c)
    local W, T, fails = run(c)
    assert(#fails == 0, table.concat(fails, "\n") .. "\n" .. fw.timeline(W, T, c.span))
end

for _, b in ipairs({ "rip", "rake" }) do
    local name = b == "rip" and "Rip" or "Rake"
    describe("Forever Feral: a missed " .. name .. " (lane finisher-miss)", function()
        for _, act in ipairs(ACTS) do
            it(("1 %s %s, its own row 4 ms after the success: back at once (window 0)"):format(name, act), function()
                expectPass({ bleed = b, act = act, row = 0.004 })
            end)
            it(
                ("2 %s %s, its row 15 ms before the success (fix A): back at once (window 0)"):format(name, act),
                function()
                    expectPass({ bleed = b, act = act, row = -0.015 })
                end
            )
            it(
                ("3 %s %s, its row in a white swing's row frame, secret amounts, no viewer (window 0)"):format(
                    name,
                    act
                ),
                function()
                    expectPass({ bleed = b, act = act, row = 0.004, swingAt = TIE })
                end
            )
            it(
                ("3 %s %s, its row in a white swing's row frame, secret amounts, viewer proven (window W)"):format(
                    name,
                    act
                ),
                function()
                    expectPass({ bleed = b, act = act, row = 0.004, swingAt = TIE, viewer = "proven", windowW = true })
                end
            )
            it(
                ("3 %s %s, its row in a white swing's row frame, plain amounts, no viewer (window 0)"):format(name, act),
                function()
                    local c = { bleed = b, act = act, row = 0.004, swingAt = TIE, plain = true }
                    if b == "rip" then
                        return expectPass(c)
                    end
                    -- Rake has a direct hit: the swing's plain wound in Rake's own frame is its landing by timing alone
                    -- (the amount class would decide it; plain amounts are the beta arm). PINNED: Rake believed up
                    -- (ledger, lane finisher-miss-fix)
                    local W, T, fails = run(c)
                    local msg = table.concat(fails, "\n") .. "\n" .. fw.timeline(W, T)
                    local up = false
                    for _, f in ipairs(fails) do
                        up = up or f:find("the belief holds rake up", 1, true) ~= nil
                    end
                    assert(up, msg)
                end
            )
            it(
                ("3b %s %s, a swing fired 20 ms before the row (its SAME_FRAME), secret amounts (window 0)"):format(
                    name,
                    act
                ),
                function()
                    expectPass({ bleed = b, act = act, row = 0.004, swingAt = -0.016 })
                end
            )
            it(
                ("4 %s %s, no row, the viewer's proven item stays dark (window W, the verdict)"):format(name, act),
                function()
                    expectPass({ bleed = b, act = act, viewer = "proven", windowW = true })
                end
            )
        end

        -- 5: no row and no Cooldown Manager fact: nothing tells the belief, so it keeps the bleed its full duration. Not a
        -- defect of a path (there is no information); pinned as today's window so a change shows.
        for _, arm in ipairs({ { "Hekili.cdmOff", { viewer = "proven", cdmOff = true } }, { "not tracked", {} } }) do
            it(
                ("5 %s DODGE, no row, viewer %s: today's window is the bleed's full duration"):format(name, arm[1]),
                function()
                    local c = { bleed = b, act = "DODGE", span = b == "rip" and 13 or 10 }
                    for k, v in pairs(arm[2]) do
                        c[k] = v
                    end
                    local W, T, _, sum = run(c)
                    local msg = fw.timeline(W, T, c.span)
                    if b == "rip" then
                        -- Bite while the believed Rip has 3 s or more left (line 27: debuff.rip.remains>=3), Rip at its believed
                        -- expiry (12 s)
                        assert(sum.wrongLast and sum.wrongLast > 8.5 and sum.wrongLast < 9.1, msg)
                        assert(sum.back and sum.back >= 12 and sum.back < 12.6, msg)
                    else
                        assert(sum.back and sum.back >= 9 and sum.back < 9.6, msg) -- Rake back at its believed expiry (9 s)
                    end
                end
            )
        end
    end)
end

-- The controls: a bleed that lands cleanly. Rip: Shred after it (0 points), Ferocious Bite once 5 points come back at
-- +1.5 s (builders not modelled), so the finisher the owner saw is reachable from this state. Rake: Shred after it.
describe("Forever Feral: a landed bleed, no avoid anywhere (lane finisher-miss controls)", function()
    it("Rip lands: Shred, then Ferocious Bite at 5 points, Rip believed up, no refund", function()
        expectPass({ act = "WOUND", pointsAt = { 1.5, 5 }, expect = { { 0.004, "shred" }, { 1.5, "ferocious_bite" } } })
    end)
    it("Rake lands (its hit row 4 ms after): Shred, Rake believed up, no refund", function()
        expectPass({ bleed = "rake", act = "WOUND", row = 0.004, expect = { { 0.004, "shred" } } })
    end)
end)

-- The mirror: Rip lands (no row: it deals no direct damage) and our white swing's avoid comes in its window. Combo points
-- come back to 5 at +1.5 s, so slot 1 must show Ferocious Bite then, not Rip. This world's swing lag band is the
-- default (L.med 0.474, L.spr 0.060: core band 0.354-0.594; Rip's landing window med + 3 spr = 0.654): seed 8's traced
-- lag 0.409 falls inside it here (the gate had med 0.464, spr 0.023), so its shape is re-timed to lag 0.62, past the band
-- and inside Rip's window, as seed 8's was in the gate.
describe("Forever Feral: a landed Rip and a white swing's avoid in its window (lane finisher-miss mirror)", function()
    local SHAPES = {
        { "seed 2's shape: the swing 0.335 s after, its DODGE at a tail lag 0.176", 0.335, "DODGE", 0.176 },
        { "seed 8's shape (re-timed): the swing 5 ms after, its MISS at lag 0.62", 0.005, "MISS", 0.62 },
        { "the core band: the swing's MISS in Rip's frame", TIE, "MISS", 0.474 },
        { "the swing's own ms: its MISS with PLAYER_SWING 11 ms after Rip", 0.011, "MISS", 0 },
    }
    for si, s in ipairs(SHAPES) do
        -- the swing's own ms, secret: pinned below (the owner's same-frame tie ruling)
        local arms = si == #SHAPES and { { "plain amounts", { plain = true } } }
            or { { "secret amounts", {} }, { "plain amounts", { plain = true } } }
        for _, arm in ipairs(arms) do
            it(("%s, %s: Rip stays up, no refund, Bite at 5 points"):format(s[1], arm[1]), function()
                local c = {
                    act = "WOUND",
                    swingAt = s[2],
                    odd = { act = s[3], lag = s[4] },
                    pointsAt = { 1.5, 5 },
                    expect = { { 1.5, "ferocious_bite" } },
                }
                for k, v in pairs(arm[2]) do
                    c[k] = v
                end
                expectPass(c)
            end)
        end
    end
    -- F5 (owner ruling 2026-10-24: a same-frame avoid the swing refuses is the spell's): with no Cooldown Manager fact, a
    -- landed Rip is refunded and believed down when our swing misses in its own ms. PINNED as today's window: the belief
    -- holds Rip down and the energy over the truth (ledger, lane finisher-miss-fix).
    local OWN_MS = { act = "WOUND", swingAt = 0.011, odd = { act = "MISS", lag = 0 }, pointsAt = { 1.5, 5 } }
    it(
        "the swing's own ms, secret amounts, no viewer: PINNED, Rip believed down and refunded (the tie ruling)",
        function()
            local W, T, fails = run(OWN_MS)
            local msg = table.concat(fails, "\n") .. "\n" .. fw.timeline(W, T)
            assert(#fails > 0 and fails[1]:find("the belief holds rip down", 1, true), msg)
        end
    )
    -- F4b: the light (Rip's item lit since the cast) is the fact that Rip landed: the belief keeps Rip up and gives no
    -- refund. PINNED display limit: Hekili's missable hook (Engine/Schema/Spec/Abilities.lua trackMisses) still drops the
    -- cast's application at its SPELL_MISSED row, so slot 1 shows Rip at 5 points (ledger, lane finisher-miss-fix)
    local function beliefOnly(base)
        local c = { viewer = "proven", expect = { { 1.5, "ferocious_bite" } } }
        for k, v in pairs(base) do
            c[k] = v
        end
        local W, T, fails = run(c)
        local msg = table.concat(fails, "\n") .. "\n" .. fw.timeline(W, T)
        assert(#fails > 0, msg)
        for _, f in ipairs(fails) do
            assert(f:find("slot 1 shows rip", 1, true), msg)
        end
    end
    it(
        "the swing's own ms, secret amounts, viewer proven: the light keeps Rip up, no refund (slot 1 PINNED)",
        function()
            beliefOnly(OWN_MS)
        end
    )
    -- the F1 residual: a bleed's tick (a secret white wound) in the swing's core band 1 ms before the swing's own MISS in
    -- Rip's frame reads as the swing's landing, so the MISS goes to Rip. PINNED with no viewer; the light takes it back.
    local TICK =
        { act = "WOUND", swingAt = TIE, odd = { act = "MISS", lag = 0.474 }, tickAt = 0.002, pointsAt = { 1.5, 5 } }
    it("the core band with a tick 1 ms before the swing's MISS, secret, no viewer: PINNED, Rip refunded", function()
        local W, T, fails = run(TICK)
        local msg = table.concat(fails, "\n") .. "\n" .. fw.timeline(W, T)
        assert(#fails > 0 and fails[1]:find("the belief holds rip down", 1, true), msg)
    end)
    it(
        "the core band with a tick 1 ms before the swing's MISS, secret, viewer proven: Rip stays up (slot 1 PINNED)",
        function()
            beliefOnly(TICK)
        end
    )
    it("seed 2's shape, plain amounts, viewer proven (the light is the fact that Rip landed): Rip stays up", function()
        expectPass({
            act = "WOUND",
            swingAt = 0.335,
            odd = { act = "DODGE", lag = 0.176 },
            pointsAt = { 1.5, 5 },
            expect = { { 1.5, "ferocious_bite" } },
            plain = true,
            viewer = "proven",
        })
    end)
end)
