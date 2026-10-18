-- tests/Forever/display_resolve_spec.lua (display styles plan, Task 3): ns.UI.Resolve, the "what to show" every style
-- reads (range, usable, the delay's wait, the clamped target count, the overlay glow), fills d.resolved[ i ] before
-- the display's Draw, from game APIs, without allocating once warm, even while the clock (and so the delay) moves.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

local overlayed = {}
local fakeNew = fake.new
fake.new = function(...)
    local api, ctl = fakeNew(...)
    api.C_SpellActivationOverlay.IsSpellOverlayed = function(id)
        return overlayed[id] == true
    end
    return api, ctl
end

local SET = { { "mortal_strike", 1.0 }, { "overpower", 1.5 } }

local function boot()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(headless.cycle(H, H.ctl.now + 0.2))
    local conf = H.Hekili.DB.profile.displays.Primary.classic
    conf.delays.type, conf.delays.desaturate = "TEXT", true -- the delay text: the string the moving clock changes
    return H, rawget(H.env, "HekiliDisplayPrimary")
end

local function publish(H)
    local abilities = H.Hekili.Engine.Registry.Abilities()
    local s = H.ns.Output.Begin("Primary")
    for i, e in ipairs(SET) do
        local r = s[i]
        r.actionName, r.actionID, r.texture = e[1], abilities[e[1]].id, "tex" .. i
        r.time, r.exact_time = e[2], H.ctl.now + e[2]
    end
    H.ns.Output.Publish("Primary", #SET)
end

local function frame(H, d, dt)
    H.ctl.now = H.ctl.now + dt
    d.__scripts.OnUpdate(d, dt)
end

describe("the shared resolve", function()
    after_each(function()
        for k in pairs(overlayed) do
            overlayed[k] = nil
        end
    end)

    it("fills every published record's range, usable, delay, targets and glow before the draw", function()
        local H, d = boot()
        overlayed[H.Hekili.Engine.Registry.Abilities().overpower.id] = true
        publish(H)
        frame(H, d, 0.2)
        local r1, r2 = d.resolved[1], d.resolved[2]
        assert.is_false(r1.glow)
        assert.is_true(r2.glow)
        assert.is_true(r1.inRange)
        assert.is_true(r1.usable)
        assert.are.near(0.8, r1.delay, 1e-9)
        assert.are.near(1.3, r2.delay, 1e-9)
        assert.is_true(r1.desaturate) -- 0.8 s to wait, nothing (GCD, cast, cooldown) explains it
        assert.are.equal(1, r1.targets)
        H.ctl.inRange.target = false
        frame(H, d, 0.3) -- past the 0.25 s pulse
        assert.is_false(d.resolved[1].inRange)
        assert.are.same({}, H.errors)
    end)

    it("allocates nothing over 1,000 display frames of a moving clock after the first publish", function()
        local H, d = boot()
        publish(H)
        for _ = 1, 3 do
            frame(H, d, 0.2)
        end
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do
            frame(H, d, 0.001) -- 1 s: the delay text counts 0.4 down to nothing
        end
        local bytes = (collectgarbage("count") - before) * 1024
        collectgarbage("restart")
        assert.are.same({}, H.errors)
        assert.are.equal(0, bytes)
    end)
end)
