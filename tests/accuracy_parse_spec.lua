-- tools/accuracy/parse.lua on sample lines in the formats the gates print: a changed format must fail loudly here
-- (and in `make accuracy`), not leave blank cells.
local parse = require("tools.accuracy.parse")

local LOOP = "fights=20 agreement 0.926 (45678 ticks); react median 0 p90 1 never 0.012; ready while short 12; held while ready 340; "
    .. "refused per 100 [cooldown 0.4 (oracle 0.4, unmatched 0.0), cost 5.2 (oracle 4.0, unmatched 1.3)], episodes 2.00/min; "
    .. "dps A/B 0.998; full 0.1/0.1 idle 0.5/0.5; uptime [x 0.90/0.90]; flicker 0.74/min (oracle 0.42); "
    .. "errors 0 raises 0 self-check 0; cpu mean 3.12 p99 5.01 ms ratio 1.123 (calibration 2.78 ms) bytes 1234 per Update; top [a 1]; power est-truth at disagreements 0.1"

describe("tools/accuracy/parse.lua", function()
    it("reads a loop line", function()
        local r = parse.loop(LOOP)
        assert.are.same(
            { 0.926, 45678, 12, 340, 0.998, 0.74, 0.42, 3.12, 1.123, 2.78, 1234, 5.2, 0.4, 1.3 },
            {
                r.agreement,
                r.ticks,
                r.readyShort,
                r.heldReady,
                r.dps,
                r.flicker,
                r.oracleFlicker,
                r.cpuMs,
                r.ratio,
                r.calibration,
                r.bytes,
                r.cost,
                r.cooldown,
                r.unmatched,
            }
        )
        assert.are.equal(0, parse.loop((LOOP:gsub("%[cooldown.-%], episodes", "[], episodes"))).cost)
    end)
    it("reads the wowsims lines", function()
        assert.are.equal(
            0.955,
            parse.replay("fights=1 agreement 0.9 (9 ticks); decisions on-GCD 0.955 (150) top [a 1]").agreement
        )
        local t = parse.ready(
            "ready on-GCD 83 timed 83 never 3 scope 2; |b| median 0.000 p90 0.100; early 17 late 0; real 11 (early 6 late 5) median 0.700; absorbed []"
        )
        assert.are.same({ 0.7, 3 }, { t.median, t.never })
        assert.are.equal(
            1.8,
            parse.live("worst idle 1.8 s with a usable on-GCD ability (limit 6.0), presses 55, errors 0").idle
        )
        assert.are.equal(2.5, parse.live("median worst idle 2.5 s over 30 fresh fights (limit 6.0), worst 4.0 s").idle)
    end)
    it("classifies printed lines and fails loudly on a changed format", function()
        assert.are.same({ "loop", { "Arms", "2", "x" } }, { parse.classify("ACC loop\tArms\t2\tx") })
        assert.are.same(
            { "timing", { "A (wowsims.com)", "b" } },
            { parse.classify("A (wowsims.com) wowsims timing: b") }
        )
        assert.are.same({ "live", { "A (wowsims.com)", "40", "b" } }, { parse.classify("A (wowsims.com) live L40: b") })
        assert.is_nil(parse.classify("something else"))
        assert.has_error(function()
            parse.loop((LOOP:gsub("held while ready", "held-while-ready")))
        end)
        assert.has_error(function()
            parse.replay("agreement 0.9")
        end)
    end)
end)
