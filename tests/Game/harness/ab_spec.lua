-- tests/Game/harness/ab_spec.lua (providers spec §4): the A/B arm and the measured shapes.
local ab = require("Game.harness.ab")
local scenarios = require("Game.harness.scenarios")

describe("the A/B harness", function()
    it("the default arm asserts, a provider arm records", function()
        assert.has_error(function()
            ab.check(false, "x", "line", "default")
        end)
        assert.has_no.errors(function()
            ab.check(false, "x", "line", "abspec") -- its own file: the gate arms' .ab/meter.tsv stays clean
        end)
    end)

    it("four viewer arms (cdm-default decision 110), each with its layout; the default arm unchanged", function()
        assert.are.same({ outcomes = "default", presence = "router", viewer = false }, ab.ARMS.default)
        for _, layout in ipairs({ "none", "buffs", "fixture", "mixed" }) do
            local a = ab.ARMS["viewer-" .. layout]
            assert.are.same({ outcomes = "default", presence = "router", viewer = true, layout = layout }, a)
            assert.are.same(
                { outcomes = "default", presence = "router", viewer = true },
                ab.providers("viewer-" .. layout)
            )
        end
        assert.is_nil(ab.ARMS.viewer) -- the layout-less arm is viewer-none now
    end)

    it("the verdict arms (verdict spec §5), each with edgestats and a -novd twin that differs only by novd", function()
        local names = {
            "viewer-reshuffle",
            "viewer-nonland",
            "secret-viewer-buffs",
            "secret-viewer-mixed",
            "viewer-swap",
            "viewer-late",
            "viewer-recast",
            "viewer-swap-dark",
        }
        assert.are.same(names, ab.VERDICT)
        for _, name in ipairs(names) do
            local a, off = ab.ARMS[name], ab.ARMS[name .. "-novd"]
            assert.is_true(a.viewer and a.edge)
            assert.is_nil(a.novd)
            local twin = { novd = true }
            for k, v in pairs(a) do
                twin[k] = v
            end
            assert.are.same(twin, off)
            assert.are.same({ outcomes = "default", presence = "router", viewer = true }, ab.providers(name))
        end
        assert.is_true(ab.ARMS["viewer-reshuffle"].reshuffle and ab.ARMS["viewer-swap"].reshuffle)
        assert.is_false(ab.ARMS["viewer-nonland"].world.auraOnAvoid)
        assert.are.same({ 4, 8 }, ab.ARMS["viewer-swap"].world.swapEvery)
        assert.is_true(ab.ARMS["secret-viewer-mixed"].observe.secretAmount)
        assert.are.same({ 0.1, 1.2, 1.8 }, ab.ARMS["viewer-late"].world.lateLight) -- late past W (1.0)
        local recast, nonland = ab.ARMS["viewer-recast"].world, ab.ARMS["viewer-nonland"].world
        assert.is_true(recast.recast)
        assert.are.same(nonland.mobAvoid, recast.mobAvoid) -- the non-landing world
        local dark, swap = ab.ARMS["viewer-swap-dark"], ab.ARMS["viewer-swap"]
        assert.is_true(dark.reshuffleDark)
        assert.is_nil(swap.reshuffleDark) -- every older arm keeps the atomic reshuffle
        assert.are.same(swap.world, dark.world)
    end)

    it("the secret arm makes UNIT_COMBAT's amount secret (live), never on the plain oracle", function()
        assert.are.same({ secretAmount = true }, ab.ARMS.secret.observe)
        assert.are.same({ outcomes = "default", presence = "router", viewer = false }, ab.providers("secret"))
        local o = { duration = 10, observe = { secretAmount = true } }
        assert.is_true(scenarios.stream(o, 7).secretAmount)
        o.observe.plain = true
        assert.is_false(scenarios.stream(o, 7).secretAmount)
        assert.is_false(scenarios.stream({ duration = 10 }, 7).secretAmount)
    end)

    local function count(s, ev)
        local n = 0
        for i = 1, s.n do
            n = n + (s.ev[i] == ev and 1 or 0)
        end
        return n
    end

    it("meter shapes only add events: the rest of the stream is today's", function()
        local o = { duration = 30, observe = { meter = false, takenLag = 0 } } -- explicit: a provider arm sets them
        local base = scenarios.stream(o, 7)
        o.observe = { meter = true, takenLag = 0 }
        local with = scenarios.stream(o, 7)
        assert.is_true(count(with, "DAMAGE_METER_COMBAT_SESSION_UPDATED") > 0)
        local j = 0
        for i = 1, with.n do
            if with.ev[i] ~= "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
                j = j + 1
                assert.are.same({ base.t[j], base.ev[j], base.a1[j] }, { with.t[i], with.ev[i], with.a1[i] })
            end
        end
        assert.are.equal(base.n, j)
    end)

    it("a hit swing of ours groups 0-11 ms after PLAYER_SWING; an avoid never", function()
        local s, W = scenarios.stream({ duration = 60, meter = true }, 11)
        for _, ev in ipairs(W.truth) do
            if ev.kind == "swing" and ev.ours then
                local got = false
                for i = 1, s.n do
                    if s.ev[i] == "DAMAGE_METER_COMBAT_SESSION_UPDATED" and s.a1[i] == 0 then
                        local d = s.t[i] - ev.t
                        got = got or (d >= 0 and d <= 0.011 + 1e-9) -- float: t + 11 / 1000 - t can exceed 0.011
                    end
                end
                assert.are.equal(ev.act == "WOUND", got)
            end
        end
    end)
end)
