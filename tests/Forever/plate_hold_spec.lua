-- tests/Forever/plate_hold_spec.lua (T1 task 6, the owner's no-jitter rule): under the Map restriction the plate count
-- (token plates) publishes a rise at once and holds a fall for one forced update, so a plate that flickers in and out
-- of the client's set every update does not flap the count. Only with token plates: the GUID and damage paths drop at
-- once, as before. The call's return, Hekili:GetNumTargets(), the engine's published status and the
-- TARGET_COUNT_CHANGED hook agree.
local headless = require("Game.harness.headless")
local mw = require("Forever.helpers.map_world")

describe("the token plate count's hold (T1)", function()
    local H, hooked, t

    setup(function()
        H = mw.new("B")
        local hooks = H.Hekili.Class.hooks
        hooks.TARGET_COUNT_CHANGED = hooks.TARGET_COUNT_CHANGED or {}
        H.ns.addHook("TARGET_COUNT_CHANGED", function(...)
            hooked = H.ns.getNumberTargets()
            return ...
        end)
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        t = H.ctl.now
    end)

    before_each(function()
        for k = 1, 6 do
            if H.ctl.exists["nameplate" .. k] then
                mw.unplate(H, k)
            end
        end
        mw.platesShown(H.ctl, true)
        mw.target(H, nil)
        mw.count(H)
    end)

    -- One engine update (the forced count at Core.lua's update): its count, and the four views of it agree.
    local function update()
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.same({}, H.errors)
        local n = H.ns.getNumberTargets()
        assert.are.equal(n, H.Hekili:GetNumTargets())
        assert.are.equal(n, H.Hekili.Engine.Output.status.numTargets)
        assert.are.equal(n, hooked)
        return n
    end
    -- Plate k in (true) or out (false) of the client's set.
    local function set(k, on)
        if on and not H.ctl.exists["nameplate" .. k] then
            mw.plate(H, k)
        elseif not on and H.ctl.exists["nameplate" .. k] then
            mw.unplate(H, k)
        end
    end
    local function changes(seq)
        local n = 0
        for i = 2, #seq do
            n = n + (seq[i] ~= seq[i - 1] and 1 or 0)
        end
        return n
    end
    local PER_MIN = 60 / 0.2 -- updates a minute at this spec's 0.2 s spacing

    it("publishes a rise at once and a fall one update later", function()
        set(1, true)
        set(2, true)
        mw.target(H, 1)
        assert.are.equal(2, update())
        set(3, true)
        assert.are.equal(3, update(), "a rise at once")
        set(3, false)
        assert.are.equal(3, update(), "the fall held one update")
        assert.are.equal(2, update(), "then published")
        assert.are.equal(2, update())
    end)

    it("a plate flapping every update keeps the count high; a patrol rises and falls once a cycle", function()
        set(1, true)
        set(2, true)
        mw.target(H, 1)
        update()
        local raw, got = {}, {}
        for i = 1, 30 do
            set(3, i % 2 == 1)
            raw[i] = (i % 2 == 1) and 3 or 2
            got[i] = update()
        end
        for i = 2, 30 do
            assert.are.equal(3, got[i], "flap update " .. i)
        end
        print(
            ("\nflap: count changes %.0f/min without the hold, %.0f/min with it"):format(
                changes(raw) * PER_MIN / 30,
                changes(got) * PER_MIN / 30
            )
        )
        raw, got = {}, {}
        for i = 1, 36 do
            local inside = (i - 1) % 6 < 3 -- in 3 updates, out 3
            set(4, inside)
            raw[i] = inside and 3 or 2
            got[i] = update()
        end
        assert.are.equal(changes(raw), changes(got), "one rise and one fall a cycle")
        print(
            ("patrol: count changes %.0f/min without the hold, %.0f/min with it"):format(
                changes(raw) * PER_MIN / 36,
                changes(got) * PER_MIN / 36
            )
        )
    end)

    it("leaving token mode drops at once", function()
        set(1, true)
        set(2, true)
        set(3, true)
        mw.target(H, 1)
        assert.are.equal(3, update())
        for k = 1, 3 do
            set(k, false)
        end
        assert.are.equal(1, update(), "no token plate left: no hold")
    end)

    it("a damage-path kill with no token plates drops on the same update", function()
        mw.platesShown(H.ctl, false) -- the damage path counts
        local now = H.ctl.now
        H.ns.updateTarget("Creature-d1", now)
        H.ns.updateTarget("Creature-d2", now)
        assert.are.equal(2, update())
        H.ns.updateTarget("Creature-d2", nil)
        assert.are.equal(1, update())
        H.ns.updateTarget("Creature-d1", nil)
    end)
end)
