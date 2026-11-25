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

    it("the band lead arms (integration design 5.4, lane B4): each its knob, bands on, never the default", function()
        local want = {
            ["bands-lead"] = { bandLead = 1 },
            ["bands-lag"] = { bandLead = -1 },
            ["bands-spend-first"] = { spendFirst = 0.05 },
            ["bands-spend-late"] = { spendFirst = -0.05 },
            ["bands-gain-first"] = { gainFirst = 0.05 },
            ["bands-health"] = { bandPower = false },
        }
        local mid = { -- (re-review H3) the order arms' extra cycle, inside the delay: no other arm has one
            ["bands-spend-first"] = 0.04,
            ["bands-spend-late"] = 0.08,
            ["bands-gain-first"] = 0.04,
        }
        for name, knobs in pairs(want) do
            assert.are.same({
                outcomes = "default",
                presence = "router",
                viewer = false,
                bands = true,
                bandKnobs = knobs,
                midPoll = mid[name],
            }, ab.ARMS[name])
        end
        for name, arm in pairs(ab.ARMS) do
            assert.are.equal(mid[name], arm.midPoll, name)
        end
        assert.is_nil(ab.ARMS.default.bands)
    end)

    -- (lane B4 re-review H4) a row no arm asserts: the default arm writes it too
    it("a recorded row is written in every arm, the default's too, and asserts nothing", function()
        -- luacheck: ignore 122 (io.open stands in: the default arm's file is every suite's, not this spec's to write)
        local arm, open = ab.arm, io.open
        local paths, wrote = {}, {}
        local fh = {}
        function fh.write(_, ...)
            wrote[#wrote + 1] = table.concat({ ... })
        end
        function fh.close() end
        finally(function()
            ab.arm, io.open = arm, open
        end)
        io.open = function(path)
            paths[#paths + 1] = path
            return fh
        end
        for _, name in ipairs({ "default", "bands" }) do
            ab.arm = function()
                return name
            end
            ab.record("power", "polls 1")
        end
        io.open = open
        assert.are.same({ ".ab/default.tsv", ".ab/bands.tsv" }, paths)
        assert.are.same({ "power\tok\tpolls 1\n", "power\tok\tpolls 1\n" }, wrote)
    end)

    -- (lane B4 re-review H1) the ruled arm: live's secret amounts and the row's lag, on both instances alike
    it("bands-taken-lag and lagged-secret: one world, secret amounts, they differ by the bands alone", function()
        local observe = { takenLag = 0.48, secretAmount = true }
        local twin = { outcomes = "default", presence = "router", viewer = false, observe = observe }
        assert.are.same(twin, ab.ARMS["lagged-secret"])
        local banded = { bands = true }
        for k, v in pairs(twin) do
            banded[k] = v
        end
        assert.are.same(banded, ab.ARMS["bands-taken-lag"])
        assert.are.same({ takenLag = 0.48 }, ab.ARMS.lagged.observe)
    end)

    it("the live-auras arms (aura audit C1): our auras hidden in combat, the CDM's only, never the default", function()
        for name, layout in pairs({ ["live-auras"] = "fixture", ["live-auras-none"] = "none" }) do
            local a = ab.ARMS[name]
            assert.are.same({
                outcomes = "default",
                presence = "router",
                viewer = true,
                layout = layout,
                observe = { secretPlayerAuras = true },
            }, a)
        end
        assert.is_nil(ab.ARMS.default.observe)
    end)

    -- (L1814, Fable batch 4 I1) the gated arm players run: the addon's defaults, every switch on
    it("the shipped arm: bands, time to die and the Cooldown Manager on; it writes its row and asserts", function()
        assert.are.same({
            outcomes = "default",
            presence = "router",
            viewer = true,
            layout = "fixture",
            bands = true,
            ttd = true,
            bandKnobs = { plateBands = true }, -- as the ttd arm (L1841)
            gate = true,
        }, ab.ARMS.shipped)
        assert.are.same(ab.providers("viewer-fixture"), ab.providers("shipped"))
        for name, arm in pairs(ab.ARMS) do -- every other arm stays record-only
            assert.are.equal(name == "shipped" or nil, arm.gate, name)
        end
        -- luacheck: ignore 122 (io.open stands in, as the recorded row's test: no suite's file is written)
        local open, wrote = io.open, {}
        local fh = {}
        function fh.write(_, ...)
            wrote[#wrote + 1] = table.concat({ ... })
        end
        function fh.close() end
        finally(function()
            io.open = open
        end)
        io.open = function()
            return fh
        end
        assert.has_no.errors(function()
            ab.check(true, "x", "fine", "shipped")
        end)
        assert.has_error(function()
            ab.check(false, "x", "line", "shipped")
        end)
        io.open = open
        assert.are.same({ "x\tok\tfine\n", "x\tMISS\tline\n" }, wrote) -- the row first, so the arm's file keeps it
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
            "viewer-rebuild",
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

    it("the bands arms (LibHiddenValues lane B1): the providers the default's, bandDrop on bands-drop only", function()
        assert.are.same({ outcomes = "default", presence = "router", viewer = false, bands = true }, ab.ARMS.bands)
        assert.are.same(ab.providers("default"), ab.providers("bands"))
        assert.are.same(ab.providers("default"), ab.providers("bands-drop"))
        assert.are.equal(20, ab.ARMS["bands-drop"].bandDrop)
        assert.is_true(ab.ARMS["bands-drop"].bands)
        assert.is_nil(ab.ARMS.default.bands)
    end)

    it("the lib-absent arm (L1805): the default's providers, no bands, both libraries missing", function()
        assert.are.same(ab.providers("default"), ab.providers("lib-absent"))
        assert.is_true(ab.ARMS["lib-absent"].libAbsent)
        assert.is_nil(ab.ARMS["lib-absent"].bands)
    end)

    it("the observer's bands firings are added events only: the rest of the stream is today's", function()
        local base = scenarios.stream({ duration = 30 }, 7)
        local with = scenarios.stream({ duration = 30, observe = { bands = true } }, 7)
        local j, firings = 0, 0
        for i = 1, with.n do
            if with.ev[i]:match("^@lhv") then
                firings = firings + 1
            else
                j = j + 1
                assert.are.same({ base.t[j], base.ev[j], base.a1[j] }, { with.t[i], with.ev[i], with.a1[i] })
            end
        end
        assert.are.equal(base.n, j)
        assert.is_true(firings > 10, firings)
    end)

    it("the world's `heals` knob heals us from the pull, so our health band rises (lane B3, L1666 b)", function()
        local s = scenarios.stream({ duration = 30, heals = { 5, 60 }, observe = { bands = true } }, 7)
        local last, rises, heals = nil, {}, {}
        for i = 1, s.n do
            if s.ev[i] == "@lhv" and s.a1[i] == "health" and s.a2[i] == "player" then
                if last and s.a4[i] > last then
                    rises[#rises + 1] = s.t[i]
                end
                last = s.a4[i]
            elseif s.ev[i] == "UNIT_COMBAT" and s.a1[i] == "player" and s.a2[i] == "HEAL" then
                heals[#heals + 1] = s.t[i]
            end
        end
        assert.are.same({ 6, 11, 16, 21, 26 }, heals) -- every 5 s from the pull at 1, before the stop at 31
        assert.are.same(heals, rises) -- each a rise of our band, and nothing else raises it
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
