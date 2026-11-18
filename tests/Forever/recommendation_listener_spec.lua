-- tests/Forever/recommendation_listener_spec.lua: Hekili:RegisterRecommendationListener, the public recommendation
-- update for addons that are not WeakAuras (src/Hekili/Integrations/Recommendations.lua). Stock Hekili headless as Arms:
-- every publish of the five displays calls each listener with (display, payload), the WeakAuras event's payload; a
-- listener that raises is reported once and stops nothing; a publish allocates nothing; an outside Engine.Subscribe
-- caller cannot push out Hekili's own subscribers.
local alloc = require("Game.State.helpers.alloc")
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("recommendation listeners (headless Arms)", function()
    local H, hk, Out, added

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        hk = H.Hekili
        Out = H.ns.Output
        assert(headless.cycle(H, H.ctl.now + 0.2))
        added = {}
    end)

    after_each(function()
        for i = 1, #added do
            hk:UnregisterRecommendationListener(added[i])
        end
        H.env.WeakAuras = nil
    end)

    local function listen(fn)
        added[#added + 1] = fn
        return hk:RegisterRecommendationListener(fn)
    end

    -- One publish of `names` into `display`.
    local function pub(display, names)
        local s = Out.Begin(display)
        for i = 1, #names do
            s[i].actionName, s[i].actionID = names[i], i
        end
        Out.Publish(display, #names)
    end

    it("calls each listener with (display, payload) on every publish of the five displays, never status", function()
        local got = {}
        assert.is_true(listen(function(...)
            got[#got + 1] = { n = select("#", ...), ... }
        end))
        for _, d in ipairs({ "Interrupts", "Defensives", "Cooldowns", "Primary", "AOE" }) do
            pub(d, { "a", "b" })
            local c = got[#got]
            assert.are.equal(2, c.n, d)
            assert.are.equal(d, c[1])
            local p = c[2]
            assert.are.equal("a", p[1].actionName, d)
            assert.are.equal("b", p[2].actionName, d)
            assert.are.equal(1, p.actionID, d) -- the payload's own fields read record 1
            assert.is_nil(p[3].actionName, d)
            assert.are_not.equal(Out[d].recs[1], p[1], d) -- a copy, not the engine's record
        end
        local n = #got
        Out.Publish("status", 1)
        assert.are.equal(n, #got)
        pub("Primary", {})
        assert.are.equal("Primary", got[#got][1])
        assert.is_nil(got[#got][2].actionName) -- an empty publish still calls, with every entry empty
        assert.are.same({}, H.errors)
    end)

    it("registering the same fn twice is one listener; unregistering stops it; a non-function raises", function()
        local calls = 0
        local function fn()
            calls = calls + 1
        end
        assert.is_true(listen(fn))
        assert.is_true(listen(fn))
        pub("Primary", { "a" })
        assert.are.equal(1, calls)
        hk:UnregisterRecommendationListener(fn)
        hk:UnregisterRecommendationListener(fn) -- not registered: ignored
        pub("Primary", { "a" })
        assert.are.equal(1, calls)
        assert.has_error(function()
            hk:RegisterRecommendationListener("fn")
        end)
    end)

    it("a listener that raises is reported once through the error handler; others and the display still run", function()
        local before, after, display = 0, 0, 0
        assert.is_true(listen(function()
            before = before + 1
        end))
        assert.is_true(listen(function()
            error("listener bug")
        end))
        assert.is_true(listen(function()
            after = after + 1
        end))
        assert.is_true(hk.Engine.Subscribe("Primary", function()
            display = display + 1
        end))
        for _ = 1, 3 do
            pub("Primary", { "a" })
        end
        assert.are.equal(3, before)
        assert.are.equal(3, after)
        assert.are.equal(3, display)
        assert.are.equal(1, #H.errors)
        assert.truthy(H.errors[1]:find("listener bug", 1, true))
    end)

    it("a listener that unregisters itself mid-publish does not skip the next one", function()
        local self, nextCalls = nil, 0
        self = function()
            hk:UnregisterRecommendationListener(self)
        end
        listen(self)
        listen(function()
            nextCalls = nextCalls + 1
        end)
        pub("Primary", { "a" })
        assert.are.equal(1, nextCalls)
        pub("Primary", { "a" })
        assert.are.equal(2, nextCalls)
    end)

    it("a listener's error is reported again after it is unregistered and registered again", function()
        local function bad()
            error("listener bug")
        end
        listen(bad)
        pub("Primary", { "a" })
        hk:UnregisterRecommendationListener(bad)
        listen(bad)
        pub("Primary", { "a" })
        assert.are.equal(2, #H.errors)
    end)

    it("an erroring listener, once unregistered, is not kept alive by the error report", function()
        local weak = setmetatable({}, { __mode = "k" })
        local bad = function()
            error("listener bug")
        end
        weak[bad] = true
        assert.is_true(hk:RegisterRecommendationListener(bad)) -- not through listen(): `added` would hold it
        pub("Primary", { "a" })
        assert.are.equal(1, #H.errors)
        hk:UnregisterRecommendationListener(bad)
        bad = nil -- luacheck: ignore 311
        collectgarbage()
        collectgarbage()
        assert.is_nil(next(weak))
    end)

    it("with 16 in use, a register inside a callback after an unregister there takes the freed slot", function()
        local victim, newcomer, ok = nil, nil, nil
        local newCalls, counts = 0, {}
        listen(function()
            if ok == nil then
                hk:UnregisterRecommendationListener(victim)
                ok = hk:RegisterRecommendationListener(newcomer)
            end
        end)
        victim = function()
            error("unregistered before its turn")
        end
        listen(victim)
        for i = 3, 16 do
            assert.is_true(listen(function()
                counts[i] = (counts[i] or 0) + 1
            end))
        end
        newcomer = function()
            newCalls = newCalls + 1
        end
        added[#added + 1] = newcomer
        pub("Primary", { "a" })
        assert.is_true(ok)
        assert.are.equal(0, newCalls) -- called from the next update on
        pub("Primary", { "a" })
        assert.are.equal(1, newCalls)
        for i = 3, 16 do
            assert.are.equal(2, counts[i], i) -- nobody skipped
        end
        assert.are.same({}, H.errors)
        assert.is_false(listen(function() end)) -- 16 again: a 17th is refused
    end)

    it("WeakAuras and a listener receive the same payload table", function()
        local scanned, got
        H.env.WeakAuras = {
            ScanEvents = function(_, display, _, _, _, p)
                if display == "Primary" then
                    scanned = p
                end
            end,
        }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        listen(function(display, p)
            if display == "Primary" then
                got = p
            end
        end)
        pub("Primary", { "a" })
        assert.is_table(got)
        assert.are.equal(scanned, got)
    end)

    it("a listener before PLAYER_ENTERING_WORLD, then WeakAuras: one subscription, one call and one scan", function()
        local calls, scans = 0, 0
        listen(function(display)
            if display == "Primary" then
                calls = calls + 1
            end
        end)
        local subs = hk.Engine.Output.Primary.subs.n
        H.env.WeakAuras = {
            ScanEvents = function(_, display)
                if display == "Primary" then
                    scans = scans + 1
                end
            end,
        }
        H.Fire("PLAYER_ENTERING_WORLD", false, false)
        assert.are.equal(subs, hk.Engine.Output.Primary.subs.n)
        pub("Primary", { "a" })
        assert.are.equal(1, calls)
        assert.are.equal(1, scans)
        assert.are.same({}, H.errors)
    end)

    it("takes 16 listeners and refuses the 17th", function()
        for i = 1, 16 do
            assert.is_true(listen(function() end), i)
        end
        assert.is_false(listen(function() end))
    end)

    it("allocates nothing over 1000 publishes with two listeners", function()
        local n = 0
        listen(function()
            n = n + 1
        end)
        listen(function(_, p)
            n = n + (p.actionID or 0)
        end)
        pub("Primary", { "a", "b" }) -- the first publish sizes the payload's tables
        local fill = { "a", "b" }
        local bytes = alloc.bytes(function(r)
            local s = Out.Begin("Primary")
            for i = 1, 2 do
                s[i].actionName, s[i].actionID = fill[i], r
            end
            Out.Publish("Primary", 2)
        end, 1000)
        assert.are.equal(0, bytes)
        assert.is_true(n >= 2000)
    end)

    it("an outside Engine.Subscribe caller filling its slots first cannot push out the glow or the bridge", function()
        local Engine = hk.Engine
        local o = Engine.Output.Primary
        local cfg, BG = hk.DB.profile.barGlow, H.ns.UI.BarGlow
        cfg.enabled, cfg.follow = false, "Primary"
        BG.Apply() -- the glow off: it holds no slot
        local taken = 0
        while Engine.Subscribe("Primary", function() end) do
            taken = taken + 1
        end
        assert.are.equal(4, taken)
        cfg.enabled = true
        BG.Apply()
        local glow, listeners = false, 0
        for i = 1, o.subs.n do
            glow = glow or o.subs[i] == BG.OnPublish
        end
        assert.is_true(glow, "the action bar glow lost its slot")
        listen(function()
            listeners = listeners + 1
        end)
        pub("Primary", { "a" })
        assert.are.equal(1, listeners)
    end)
end)
