-- tests/Forever/windows_spec.lua (re-pin design §3a, decision 11; plan Task 8a): RegisterWindow's and RegisterReaction's
-- checks at load and their plain records in Build(def) (Engine/Schema/Spec.lua, Tracked.lua). The belief's edges: tests/Game/State/windows_spec.lua.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local function boot()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    return H
end

describe("RegisterWindow", function()
    local H, kit
    before_each(function()
        H = boot()
        kit = H.Hekili.Class.kit
    end)

    -- two abilities the belief tracks (the build's first two: the class's, sorted; passives come after them)
    local function steps()
        local def = H.ns.VirtualStateInternal.def
        return { def.abilities[2].key, def.abilities[1].key }
    end

    it("hands a plain record to Build(def), steps as ability indexes", function()
        local keys = steps()
        local ev = function()
            return false
        end
        kit:RegisterWindow("test_window", { evaluator = ev, duration = 6, steps = keys, strict = true })
        H.Hekili:SpecializationChanged()
        local def = H.ns.VirtualStateInternal.def
        local rec
        for w = 1, #def.windows do
            if def.windows[w].key == "test_window" then
                rec = def.windows[w]
            end
        end
        assert.is_truthy(rec)
        assert.are.equal(6, rec.duration)
        assert.are.equal("stay", rec.on_deviation)
        assert.is_true(rec.strict)
        assert.is_false(rec.loop)
        for k, key in ipairs(keys) do
            assert.are.equal(key, def.abilities[rec.steps[k]].key)
        end
        assert.is_nil(getmetatable(rec))
    end)

    it("raises at load on a second name, a bad field or an unregistered step key", function()
        kit:RegisterWindow("twice", { duration = 6 })
        assert.has_error(function()
            kit:RegisterWindow("twice", { duration = 6 })
        end)
        assert.has_error(function()
            kit:RegisterWindow("no_duration", {})
        end)
        assert.has_error(function()
            kit:RegisterWindow("bad_eval", { duration = 6, evaluator = 1 })
        end)
        assert.has_error(function()
            kit:RegisterWindow("bad_dev", { duration = 6, steps = steps(), on_deviation = "wander" })
        end)
        assert.has_error(function()
            kit:RegisterWindow("bad_step", { duration = 6, steps = { "no_such_ability" } })
        end)
        assert.has_error(function() -- spec 0's windows merge beside the spec's
            H.Hekili.Class.specs[0]:RegisterWindow("twice", { duration = 6 })
        end)
    end)
end)

describe("RegisterReaction", function()
    local H, kit
    before_each(function()
        H = boot()
        kit = H.Hekili.Class.kit
    end)

    it("hands a plain record to Build(def), never an ability (no index, no options row)", function()
        local f = function()
            openWindow("w") -- luacheck: ignore 113 (the `now` context's verb)
        end
        kit:RegisterReaction("test_reaction", { who = "target", outcome = "dodge", now = f })
        H.Hekili:SpecializationChanged()
        local def = H.ns.VirtualStateInternal.def
        local rec
        for k = 1, #def.reactions do
            if def.reactions[k].key == "test_reaction" then
                rec = def.reactions[k]
            end
        end
        assert.is_truthy(rec)
        assert.are.same({ "target", "dodge" }, { rec.who, rec.outcome })
        assert.are.equal("function", type(rec.now))
        assert.is_nil(getmetatable(rec))
        for a = 1, #def.abilities do
            assert.are_not.equal("test_reaction", def.abilities[a].key)
        end
        assert.is_nil(H.Hekili.Class.abilities.test_reaction)
        assert.is_truthy(H.Hekili.Class.reactions.test_reaction)
    end)

    it("raises at load on a second name, a bad who or outcome, or a now that is no function", function()
        local f = function() end
        kit:RegisterReaction("twice", { who = "player", outcome = "parry", now = f })
        assert.has_error(function()
            kit:RegisterReaction("twice", { who = "player", outcome = "parry", now = f })
        end)
        assert.has_error(function()
            kit:RegisterReaction("bad_who", { who = "pet", outcome = "parry", now = f })
        end)
        assert.has_error(function()
            kit:RegisterReaction("bad_outcome", { who = "player", outcome = "glance", now = f })
        end)
        assert.has_error(function()
            kit:RegisterReaction("bad_now", { who = "player", outcome = "parry" })
        end)
        assert.has_error(function() -- spec 0's reactions merge beside the spec's
            H.Hekili.Class.specs[0]:RegisterReaction("twice", { who = "player", outcome = "parry", now = f })
        end)
    end)
end)

-- The core side (re-pin design §3a "The core (forecast only)"; plan Task 8a): `state.window.<name>` copied from
-- Facade.Window at every reset, the `open_window`/`close_window` lines, `openWindow`/`closeWindow` for handlers and the
-- forecast's steps; nothing survives the cycle and nothing is written back to the belief.
describe("the core's windows", function()
    local H, S, VS

    -- Boots, registers `windows` (name -> RegisterWindow data) and a test clock (seconds to a swing 1.2 s ahead of
    -- `now`, as mainhand_remains reads a projected swing), targets a mob and runs one cycle.
    local function core(windows)
        H = boot()
        local kit = H.Hekili.Class.kit
        for name, data in pairs(windows) do
            kit:RegisterWindow(name, data)
        end
        kit:RegisterStateExpr("test_swing_remains", function()
            local v = 1.2 - (query_time - now) -- luacheck: ignore 113 (state's fields: the expression runs under state)
            return v > 0 and v or 0
        end)
        H.Hekili:SpecializationChanged()
        S, VS = H.Hekili.State, H.ns.VirtualState
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert(headless.cycle(H, H.ctl.now + 0.2))
    end

    -- Loads `apl` (simc lines) as the pack's default list and runs one cycle; returns the Primary display's slots.
    local function run(apl)
        local lines, warnings = H.Hekili:ParseActionList(apl)
        assert.are.same({}, warnings or {})
        for _, l in ipairs(lines) do
            l.enabled = true
        end
        H.Hekili.DB.profile.packs[ww.PACK].lists = { precombat = {}, default = lines }
        H.Hekili:LoadScripts()
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        assert(headless.cycle(H, H.ctl.now + 0.2))
        assert.are.same({}, H.errors)
        return H.Hekili.Engine.Output.Primary.recs
    end

    local function near(want, got)
        assert.is_true(math.abs(want - got) < 0.02, tostring(got))
    end

    it("mirrors Facade.Window at reset, and a cycle's change is gone at the next reset", function()
        core({ w = { duration = 6 }, v = { duration = 6 } })
        VS.Window = function(name)
            if name == "w" then
                return true, S.now - 1, S.now + 5, 2, 0
            end
            return false, 0, 0, 0, 0
        end
        S.reset("Primary")
        assert.is_true(S.window.w.up)
        near(5, S.window.w.remains)
        near(1, S.window.w.elapsed)
        assert.are.equal(0, S.window.w.step)
        assert.is_false(S.window.v.up)
        assert.are.same({ 0, 0 }, { S.window.v.remains, S.window.v.elapsed })
        S.closeWindow("w")
        S.openWindow("v")
        assert.is_false(S.window.w.up)
        assert.is_true(S.window.v.up)
        S.reset("Primary")
        assert.is_true(S.window.w.up)
        assert.is_false(S.window.v.up)
    end)

    it("answers .up, .remains and .elapsed at an advanced query_time", function()
        core({ w = { duration = 6 } })
        S.reset("Primary")
        S.openWindow("w")
        S.advance(2)
        assert.is_true(S.window.w.up)
        near(4, S.window.w.remains)
        near(2, S.window.w.elapsed)
        S.advance(4.5)
        assert.is_false(S.window.w.up)
        assert.are.same({ 0, 0 }, { S.window.w.remains, S.window.w.elapsed })
    end)

    it("restarts with refresh within max_refresh, and duration= overrides the registered one", function()
        core({ w = { duration = 6, max_refresh = 1 }, d = { duration = 6 } })
        S.reset("Primary")
        S.openWindow("w")
        S.advance(1)
        S.openWindow("w", nil, true) -- the line's refresh=1
        near(6, S.window.w.remains)
        S.advance(1)
        S.openWindow("w", nil, true) -- max_refresh = 1: refused
        near(5, S.window.w.remains)
        S.openWindow("d", 2)
        near(2, S.window.d.remains)
        S.closeWindow("d")
        S.closeWindow("d") -- a close acts only on an open window
        assert.is_false(S.window.d.up)
    end)

    it("opens from a handler in the forecast only, never in the belief", function()
        core({ w = { duration = 6 } })
        local ab = H.Hekili.Class.abilities.bloodrage
        local handler = ab.handler
        ab.handler = setfenv(function()
            openWindow("w") -- luacheck: ignore 113 (state's verb: handlers run under state)
        end, S)
        S.reset("Primary")
        S:RunHandler("bloodrage")
        assert.is_true(S.window.w.up)
        ab.handler = handler
        assert.is_false((VS.Window("w")))
        S.reset("Primary")
        assert.is_false(S.window.w.up)
    end)

    it("runs open_window lines in list order: a line above the open reads it down", function()
        core({ w = { duration = 6 } })
        local recs = run("actions+=/bloodrage,if=window.w.up\nactions+=/open_window,name=w\nactions+=/berserker_stance")
        assert.are.equal("berserker_stance", recs[1] and recs[1].actionName)
        recs = run("actions+=/open_window,name=w\nactions+=/bloodrage,if=window.w.up\nactions+=/berserker_stance")
        assert.are.equal("bloodrage", recs[1] and recs[1].actionName)
        assert.is_false((VS.Window("w"))) -- never written back
    end)

    it("closes with close_window", function()
        core({ w = { duration = 6 } })
        local recs = run(
            "actions+=/open_window,name=w\nactions+=/close_window,name=w\nactions+=/bloodrage,if=window.w.up\nactions+=/berserker_stance"
        )
        assert.are.equal("berserker_stance", recs[1] and recs[1].actionName)
    end)

    it("opens once on a held condition, even with refresh=1, across the cycle's slots", function()
        core({ w = { duration = 6 } })
        local opens, lines = 0, 0
        local openWindow, line = S.openWindow, S.WindowLine
        S.openWindow = function(...)
            opens = opens + 1
            return openWindow(...)
        end
        S.WindowLine = function(...)
            lines = lines + 1
            return line(...)
        end
        run("actions+=/open_window,name=w,if=1,refresh=1\nactions+=/berserker_stance\nactions+=/bloodrage")
        S.openWindow, S.WindowLine = openWindow, line
        assert.is_true(lines >= 2, tostring(lines)) -- the line ran at every slot of the cycle
        assert.are.equal(1, opens)
    end)

    it("fails ParseActionList with the line for a window no spec registered", function()
        core({ w = { duration = 6 } })
        local lines, warnings =
            H.Hekili:ParseActionList("actions+=/open_window,name=w\nactions+=/close_window,name=nope")
        assert.are.equal("w", lines[1].window_name)
        assert.are.equal(1, #warnings)
        assert.is_truthy(warnings[1]:find("Line 2", 1, true))
        assert.is_false(lines[2].enabled)
    end)

    it("turns an open_window line's true-in-t into a delayed recommendation (recheck, the decreasing clock)", function()
        core({ w = { duration = 6 } })
        local recs = run("actions+=/open_window,name=w,if=test_swing_remains<0.5\nactions+=/bloodrage,if=window.w.up")
        assert.are.equal("bloodrage", recs[1] and recs[1].actionName)
        near(0.7, recs[1].wait)
    end)

    describe("steps (forecast)", function()
        local function stepped(data, step)
            data.duration, data.steps = 6, data.steps or { "bloodrage", "berserker_stance", "battle_stance" }
            core({ w = data })
            VS.Window = function(name)
                if name == "w" then
                    return true, S.now - 1, S.now + 5, 0, step or 1
                end
                return false, 0, 0, 0, 0
            end
            S.reset("Primary")
        end

        it("reads next.<key> for the copied due step; a simulated cast advances it in the cycle only", function()
            stepped({})
            assert.are.same(
                { 1, true, false },
                { S.window.w.step, S.window.w.next.bloodrage, S.window.w.next.berserker_stance }
            )
            S:RunHandler("bloodrage")
            assert.are.same(
                { 2, false, true },
                { S.window.w.step, S.window.w.next.bloodrage, S.window.w.next.berserker_stance }
            )
            S.reset("Primary")
            assert.are.same({ 1, true }, { S.window.w.step, S.window.w.next.bloodrage })
        end)

        it("closes after the last step, or returns to step 1 with loop", function()
            stepped({}, 3)
            S:RunHandler("battle_stance")
            assert.is_false(S.window.w.up)
            stepped({ loop = true }, 3)
            S:RunHandler("battle_stance")
            assert.are.same({ true, 1 }, { S.window.w.up, S.window.w.step })
        end)

        it("applies on_deviation to a simulated cast of a later step", function()
            stepped({})
            S:RunHandler("berserker_stance")
            assert.are.equal(1, S.window.w.step) -- stay
            stepped({ on_deviation = "skip" })
            S:RunHandler("berserker_stance")
            assert.are.equal(3, S.window.w.step)
            stepped({ on_deviation = "end" })
            S:RunHandler("berserker_stance")
            assert.is_false(S.window.w.up)
        end)

        it(
            "ends a strict window at an unrelated on-GCD cast, never an off-GCD one; a non-strict one ignores both",
            function()
                stepped({ strict = true, steps = { "bloodrage", "berserker_stance" } })
                S:RunHandler("battle_stance") -- off the GCD
                assert.is_true(S.window.w.up)
                S:RunHandler("battle_shout") -- on the GCD
                assert.is_false(S.window.w.up)
                stepped({ steps = { "bloodrage", "berserker_stance" } })
                S:RunHandler("battle_stance")
                S:RunHandler("battle_shout")
                assert.are.same({ true, 1 }, { S.window.w.up, S.window.w.step })
            end
        )
    end)

    it("allocates nothing copying, reading and changing windows", function()
        core({ w = { duration = 6, steps = { "bloodrage", "berserker_stance" } }, v = { duration = 6 } })
        local copy = S.CopyWindows
        local function once()
            copy()
            S.openWindow("v")
            local _ = S.window.v.up, S.window.v.remains, S.window.v.elapsed, S.window.w.step, S.window.w.next.bloodrage
            S.closeWindow("v")
        end
        once()
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do
            once()
        end
        local after = collectgarbage("count")
        collectgarbage("restart")
        assert.are.equal(before, after)
    end)
end)
