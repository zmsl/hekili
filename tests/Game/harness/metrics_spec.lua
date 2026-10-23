-- tests/Game/harness/metrics_spec.lua (GCD kinds design §2.4): the per-type power error, the GCD match, the
-- timing-alone share and the crit staging, on hand-made captures and truth (class-neutral: bare power types).
local world = require("Game.harness.world")
local entities = require("Game.harness.entities")
local metrics = require("Game.harness.metrics")

describe("the harness metrics", function()
    local W, us
    local POOL = 3

    before_each(function()
        W = world.new(1)
        us = W.add(entities.new({ guid = "Player-1", res = { [POOL] = { cur = 50, max = 100 } } }))
    end)

    local function ticks(list) -- { { t, est, lo } }
        local r = { n = #list, t = {}, est = {}, lo = {} }
        for k, x in ipairs(list) do
            r.t[k], r.est[k], r.lo[k] = x[1], x[2], x[3]
        end
        return r
    end

    it(
        "scores a tracked type's belief against its truth: mean and max error, overshoot windows, settled exactness",
        function()
            W.t = 1
            W.emit({ kind = "gain", src = us, pt = POOL, cost = 20 }) -- 30 from 1 s
            W.t = 12
            W.emit({ kind = "gain", src = us, pt = POOL, rage = 10 }) -- 40 from 12 s
            W.t = 20 -- the world's end: a tick after it is not scored
            local c = {
                trk = {
                    [POOL] = ticks({ { 0.5, 50, 50 }, { 1.1, 50, 30 }, { 2, 30, 30 }, { 12.1, 40, 46 }, { 25, 0, 0 } }),
                },
            }
            local p = metrics.power(c, W, POOL, 5)
            assert.are.same({ 4, 20, 2, 1 }, { p.n, p.maxAbs, p.windows, p.over }) -- 46 over 40 by 6: the second window
            assert.are.equal(5, p.meanAbs)
            assert.are.equal(1, p.exact) -- 1.1 and 12.1 are inside the settle time: 0.5 and 2 count, both exact
            assert.are.equal(2, p.settled)
        end
    )

    it("matches each believed GCD to the press that opened it, its end error and its opener", function()
        W.t = 5
        W.emit({ kind = "cast", src = us, spell = 1, gcd = 1.0 })
        W.t = 7
        W.emit({ kind = "cast", src = us, spell = 2, gcd = 1.5 })
        local c = { gcdN = 3, gcdS = { 5.0005, 7, 20 }, gcdE = { 6.0005, 8.5, 21 }, gcdOwned = { 1, 0, 0 } }
        local g = metrics.gcd(c, W)
        assert.are.same({ 2, 2, 1, 1, 1 }, { g.n, g.seen, g.owned, g.ownerless, g.extra })
        assert.is_true(math.abs(g.errMax - 0.0005) < 1e-9)
    end)

    it("counts our white wounds scored on timing alone, and the crits staged among the credited", function()
        local s =
            { n = 3, ev = {}, src = { 1, 1, 2 }, hand = { 1, 1, 0 }, a1 = {}, a3 = { "", "CRITICAL", "" }, a4 = {} }
        s.t = { 1, 2, 3 }
        for i = 1, 3 do
            s.ev[i], s.a1[i], s.a4[i] = "UNIT_COMBAT", "target", 30
        end
        local c = { unk = { 0, 1, 1 }, crHand = { 1, 1, 0 }, crit3 = { 0, 1, 0 } }
        assert.are.same({ 2, 1 }, { metrics.unknown(c, s) })
        assert.are.same({ 1, 0 }, {
            metrics.unknown(c, s, function(t)
                return t < 1.5
            end),
        })
        assert.are.same({ 1, 1, 0 }, { metrics.crits(c, s) })
    end)

    it("recovery: a false credit replaced, re-pinned, neutral or unrecovered; wash: own swaps' net error", function()
        local m = metrics.newTickets()
        metrics.recoverRow(m, 10.0, 10.3, 0, false) -- replaced 300 ms later
        metrics.recoverRow(m, 11.0, 0, 11.5, false) -- re-pinned by a verdict 500 ms later
        metrics.recoverRow(m, 12.0, 0, 0, true) -- neutral: it staged nothing
        metrics.recoverRow(m, 13.0, 0, 0, false) -- unrecovered
        assert.are.equal(0.75, metrics.recovered100(m) / 100) -- 3 of 4 (a share: integers here read as spell IDs)
        assert.are.same({ 300, 500 }, { math.floor(m.recoverMs[1] + 0.5), math.floor(m.recoverMs[2] + 0.5) })
        assert.are.equal(300, math.floor(metrics.recoverMedian(m) + 0.5)) -- the lower middle of an even count
        metrics.washFight(m, { 9, -9, 4 }) -- signed per-swap rage errors of one fight
        metrics.washFight(m, {})
        assert.are.equal(2, metrics.wash(m)) -- mean absolute net per fight: (|4| + 0) / 2
        assert.are.equal(11, m.washGross / m.washFights) -- 9 + 9 + 4 over 2 fights
    end)
end)
