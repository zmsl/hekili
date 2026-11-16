-- tests/Game/State/windows_matrix_spec.lua (windows design v6 §13, Phase 1): the windows matrix's belief columns. Each
-- case is a timeline over the kit (helpers/windows_matrix.lua) whose operations are scripted (the core's columns and
-- its sent operations join in Phase 2); the runner asserts every key's up, step, expiry, open time and refreshes on
-- every tick, the replay invariant after every tick that sent operations, and that a second run of the timeline
-- allocates nothing in Drain and WindowOp. Ids follow §13 where a named case has a belief part (OP* are the
-- operations' own cases from §12's Phase 1 list).
local mx = require("Game.State.helpers.windows_matrix")
local alloc = require("Game.State.helpers.alloc")

local HUGE = math.huge
local C = mx.CLOSED

local CASES = {
    {
        id = "OP1",
        what = "OPEN on a closed row, then on an open one (a fresh open, operations are writes); expiry closes it",
        apl = { x = { duration = 3 } },
        timeline = {
            { t = 2, ops = { { "x", "OPEN", 3 } } },
            { t = 2.2, expect = { x = { up = true, openedAt = 2, expiresAt = 5 } }, ops = { { "x", "OPEN", 4 } } },
            { t = 2.4, expect = { x = { openedAt = 2.2, expiresAt = 6.2 } } },
            { t = 6.2, expect = { x = C } },
        },
    },
    {
        id = "OP2",
        what = "REFRESH: on a closed row an OPEN; on an open one the expiry restarts, past max_refresh, max_duration bounding",
        apl = { x = { duration = 3, refresh = true, max_refresh = 0, max_duration = 4 } },
        timeline = {
            { t = 2, ops = { { "x", "REFRESH", 3 } } },
            { t = 2.2, expect = { x = { up = true, openedAt = 2, expiresAt = 5 } }, ops = { { "x", "REFRESH", 3 } } },
            { t = 2.4, expect = { x = { expiresAt = 5.2, refreshes = 1 } } },
            { t = 3.5, ops = { { "x", "REFRESH", 3 } } },
            { t = 3.7, expect = { x = { expiresAt = 6, refreshes = 2 } } },
        },
    },
    {
        id = "OP3",
        what = "CLOSE on a closed and an open row; STEP on a closed row writes nothing and is dropped",
        apl = { x = { steps = { "filler", "nuke" } } },
        timeline = {
            { t = 2, ops = { { "x", "CLOSE" } } },
            { t = 2.2, counts = { applied = 1, dropped = 0 }, ops = { { "x", "OPEN", HUGE } } },
            {
                t = 2.4,
                expect = { x = { up = true, step = 1, openedAt = 2.2, expiresAt = HUGE } },
                ops = { { "x", "CLOSE" } },
            },
            { t = 2.6, expect = { x = C }, ops = { { "x", "STEP", 2 } } },
            { t = 2.8, counts = { applied = 3, dropped = 1 } },
        },
    },
    {
        id = "W09/W10/W11",
        what = "a list replays in order: OPEN, CLOSE ends closed; CLOSE, OPEN ends open; OPEN, CLOSE, OPEN ends open",
        apl = { x = { duration = 5 } },
        timeline = {
            { t = 2, ops = { { "x", "OPEN", 5 }, { "x", "CLOSE" } } },
            { t = 2.2, ops = { { "x", "CLOSE" }, { "x", "OPEN", 5 } } },
            {
                t = 2.4,
                expect = { x = { up = true, openedAt = 2.2, expiresAt = 7.2 } },
                ops = { { "x", "OPEN", 5 }, { "x", "CLOSE" }, { "x", "OPEN", 5 } },
            },
            { t = 2.6, expect = { x = { openedAt = 2.4, expiresAt = 7.4 } } },
        },
    },
    {
        id = "S09",
        what = "an operation and a cast in one Drain apply in time order, the cast logged before the operation",
        apl = { x = { steps = { "burst", "nuke" }, strict = true } },
        timeline = {
            { t = 2, ops = { { "x", "OPEN", HUGE } }, castAfter = "burst" },
            { t = 2.2, diff = true, expect = { x = { up = true, step = 2, openedAt = 2, expiresAt = HUGE } } },
        },
    },
    {
        id = "OP5",
        what = "OPEN on a window that expires after T: a fresh open at T (the belief still had it up)",
        apl = { x = { duration = 1 } },
        timeline = {
            { t = 2, ops = { { "x", "OPEN", 1 } } },
            { t = 2.2, expect = { x = { up = true, openedAt = 2, expiresAt = 3 } } },
            { t = 2.8, ops = { { "x", "OPEN", 2 } } },
            { t = 3.2, expect = { x = { openedAt = 2.8, expiresAt = 4.8 } } },
        },
    },
    {
        id = "OP6",
        what = "an unknown key, a Lua window's key and an operation over the buffer's bound are dropped and counted",
        apl = { x = { duration = 3 } },
        luaw = {},
        cap = 2,
        timeline = {
            { t = 2, ops = { { "nope", "OPEN", 3 }, { "luaw", "OPEN", 3 }, { "x", "OPEN", 3 } } },
            { t = 2.2, diff = true, counts = { applied = 0, dropped = 3, lastDrop = "luaw" } },
        },
    },
    {
        id = "D04",
        what = "one cast advances every open key of a sequence",
        apl = { x = { steps = { "filler", "nuke" } } },
        displays = { "Primary", "AOE", "Cooldowns" },
        keys = { "x", "x#AOE", "x#Cooldowns" },
        timeline = {
            { t = 2, ops = { { "x", "OPEN", HUGE }, { "x#AOE", "OPEN", HUGE }, { "x#Cooldowns", "OPEN", HUGE } } },
            {
                t = 2.2,
                expect = {
                    x = { up = true, step = 1, openedAt = 2, expiresAt = HUGE },
                    ["x#AOE"] = { up = true, step = 1, openedAt = 2, expiresAt = HUGE },
                    ["x#Cooldowns"] = { up = true, step = 1, openedAt = 2, expiresAt = HUGE },
                },
            },
            {
                t = 2.4,
                cast = "filler",
                expect = { x = { step = 2 }, ["x#AOE"] = { step = 2 }, ["x#Cooldowns"] = { step = 2 } },
            },
        },
    },
    {
        id = "S10",
        what = "a stray first-step cast opens nothing (no evaluator; L773)",
        apl = { x = { steps = { "burst", "nuke" }, strict = true } },
        timeline = {
            { t = 2, cast = "burst" },
            { t = 2.2, cast = "nuke" },
        },
    },
    {
        id = "S01/S06/S07",
        what = "strict: the due step advances, an off-GCD cast not due keeps it, the last step closes, another on-GCD cast ends it",
        apl = { x = { steps = { "burst", "nuke" }, strict = true } },
        timeline = {
            { t = 2, ops = { { "x", "OPEN", HUGE } } },
            { t = 2.2, expect = { x = { up = true, step = 1, openedAt = 2, expiresAt = HUGE } } },
            { t = 2.4, cast = "burst", expect = { x = { step = 2 } } },
            { t = 2.6, cast = "burst" },
            { t = 2.8, cast = "nuke", expect = { x = C } },
            { t = 3, ops = { { "x", "OPEN", HUGE } } },
            { t = 3.2, expect = { x = { up = true, step = 1, openedAt = 3, expiresAt = HUGE } } },
            { t = 3.4, cast = "filler", expect = { x = C } },
        },
    },
    {
        id = "S08/P25",
        what = "step_timeout: 4 s by default, written 2 s, restarted by an advance; a Lua strict window has none",
        apl = {
            x = { steps = { "burst", "nuke" }, strict = true },
            y = { steps = { "burst", "nuke" }, strict = true, step_timeout = 2 },
        },
        luaw = { strict = true, steps = { "burst", "nuke" }, duration = 30 },
        timeline = {
            {
                t = 2,
                flag = { luaw = true },
                expect = { luaw = { up = true, step = 1, openedAt = 2, expiresAt = 32 } },
                ops = { { "x", "OPEN", HUGE }, { "y", "OPEN", HUGE } },
            },
            {
                t = 2.2,
                expect = {
                    x = { up = true, step = 1, openedAt = 2, expiresAt = HUGE },
                    y = { up = true, step = 1, openedAt = 2, expiresAt = HUGE },
                },
            },
            { t = 3.9 },
            { t = 4, expect = { y = C } },
            { t = 5, cast = "burst", expect = { x = { step = 2 }, luaw = { step = 2 } } },
            { t = 6 },
            { t = 8.9 },
            { t = 9, expect = { x = C } },
            { t = 20 },
        },
    },
    {
        id = "S11",
        what = "the first and second member in one frame: open, advance twice and close in one Drain",
        apl = { x = { steps = { "stance", "nuke" }, strict = true } },
        timeline = {
            { t = 2, ops = { { "x", "OPEN", HUGE } } },
            { t = 2.2, cast = { "stance", "nuke" }, counts = { applied = 1 } },
        },
    },
    {
        id = "S17/S18/S22",
        what = "a plain sequence parks past its last step; STEP 1 restarts it, a burn-out STEP parks it; combat end closes",
        apl = { x = { steps = { "filler", "nuke", "dot" } } },
        timeline = {
            { t = 2, combat = "start", ops = { { "x", "OPEN", HUGE } } },
            { t = 2.2, expect = { x = { up = true, step = 1, openedAt = 2, expiresAt = HUGE } } },
            { t = 2.4, cast = "filler", expect = { x = { step = 2 } } },
            { t = 2.6, cast = "nuke", expect = { x = { step = 3 } } },
            { t = 2.8, cast = "dot", expect = { x = { step = 4 } } },
            { t = 3, cast = "filler" },
            { t = 3.2, ops = { { "x", "STEP", 1 } } },
            { t = 3.4, expect = { x = { step = 1 } }, ops = { { "x", "STEP", 4 } } },
            { t = 3.6, expect = { x = { step = 4 } } },
            { t = 4, combat = "end", expect = { x = C } },
        },
    },
    {
        id = "S20/P11",
        what = "a target swap: unwritten keeps the row; reset_on_target_change closes plain, parked, strict and list rows; Map too",
        apl = {
            a = { steps = { "filler", "nuke", "dot" } },
            b = { steps = { "filler", "nuke", "dot" }, reset_on_target_change = true },
            c = { steps = { "burst", "nuke" }, strict = true, reset_on_target_change = true },
            d = { duration = 10, reset_on_target_change = true },
            e = { steps = { "filler" }, reset_on_target_change = true },
        },
        timeline = {
            {
                t = 2,
                ops = {
                    { "a", "OPEN", HUGE },
                    { "b", "OPEN", HUGE },
                    { "c", "OPEN", HUGE },
                    { "d", "OPEN", 10 },
                    { "e", "OPEN", HUGE },
                },
            },
            {
                t = 2.2,
                expect = {
                    a = { up = true, step = 1, openedAt = 2, expiresAt = HUGE },
                    b = { up = true, step = 1, openedAt = 2, expiresAt = HUGE },
                    c = { up = true, step = 1, openedAt = 2, expiresAt = HUGE },
                    d = { up = true, openedAt = 2, expiresAt = 12 },
                    e = { up = true, step = 1, openedAt = 2, expiresAt = HUGE },
                },
            },
            { t = 2.3, cast = "filler", expect = { a = { step = 2 }, b = { step = 2 }, c = C, e = { step = 2 } } },
            { t = 2.4, swap = "plain", expect = { b = C, d = C, e = C } },
            { t = 2.6, ops = { { "b", "OPEN", HUGE }, { "c", "OPEN", HUGE } } },
            {
                t = 2.8,
                expect = {
                    b = { up = true, step = 1, openedAt = 2.6, expiresAt = HUGE },
                    c = { up = true, step = 1, openedAt = 2.6, expiresAt = HUGE },
                },
            },
            { t = 3, swap = "map", expect = { b = C, c = C } },
        },
    },
    {
        id = "P12",
        what = "a Lua window with reset_on_target_change: closed by the swap, reopened at step 1 by a still-true evaluator",
        luaw = { steps = { "filler", "nuke" }, reset_on_target_change = true },
        timeline = {
            {
                t = 2,
                flag = { luaw = true },
                expect = { luaw = { up = true, step = 1, openedAt = 2, expiresAt = 32 } },
            },
            { t = 2.2, cast = "filler", expect = { luaw = { step = 2 } } },
            { t = 2.4, swap = "plain", expect = { luaw = { step = 1, openedAt = 2.4, expiresAt = 32.4 } } },
            { t = 2.6, cast = "filler", flag = { luaw = false }, expect = { luaw = { step = 2 } } },
            { t = 2.8, swap = "map", expect = { luaw = C } },
            { t = 3 },
        },
    },
    {
        id = "P12-unwritten",
        what = "a Lua window without the field: a swap changes nothing",
        luaw = { steps = { "filler", "nuke" } },
        timeline = {
            {
                t = 2,
                flag = { luaw = true },
                expect = { luaw = { up = true, step = 1, openedAt = 2, expiresAt = 32 } },
            },
            { t = 2.2, cast = "filler", expect = { luaw = { step = 2 } } },
            { t = 2.4, swap = "plain" },
            { t = 2.6, swap = "map" },
        },
    },
    {
        id = "W17",
        what = "a real cast's closeWindow on an APL key closes it in the fold",
        apl = { x = { duration = 10 } },
        timeline = {
            { t = 2, ops = { { "x", "OPEN", 10 } } },
            { t = 2.2, expect = { x = { up = true, openedAt = 2, expiresAt = 12 } } },
            { t = 2.4, cast = "closer", expect = { x = C } },
        },
    },
    {
        id = "W07",
        what = "duration=combat: no expiry, closed at combat end",
        apl = { x = {} },
        timeline = {
            { t = 2, combat = "start", ops = { { "x", "OPEN", HUGE } } },
            { t = 2.2, expect = { x = { up = true, openedAt = 2, expiresAt = HUGE } } },
            { t = 50 },
            { t = 50.2, combat = "end", expect = { x = C } },
        },
    },
    {
        id = "L01",
        what = "an edit in combat: the new key reads down and its operations are dropped; applied at combat end",
        apl = { x = {} },
        keys = { "x", "z" },
        timeline = {
            { t = 2, combat = "start", ops = { { "x", "OPEN", HUGE } } },
            { t = 2.2, expect = { x = { up = true, openedAt = 2, expiresAt = HUGE } } },
            { t = 2.4, edit = { x = {}, z = { duration = 5 } }, ops = { { "z", "OPEN", 5 } } },
            { t = 2.6, diff = true, counts = { applied = 1, dropped = 1 } },
            { t = 2.8, combat = "end", expect = { x = C }, ops = { { "z", "OPEN", 5 } } },
            { t = 3, expect = { z = { up = true, openedAt = 2.8, expiresAt = 7.8 } } },
        },
    },
    {
        id = "L02",
        what = "a new generation out of combat: the old key is gone (down, its operations dropped), the new one closed",
        apl = { x = { duration = 5 } },
        keys = { "x", "y" },
        timeline = {
            { t = 2, ops = { { "x", "OPEN", 5 } } },
            { t = 2.2, expect = { x = { up = true, openedAt = 2, expiresAt = 7 } } },
            { t = 2.4, edit = { y = { duration = 5 } }, expect = { x = C }, ops = { { "x", "OPEN", 5 } } },
            { t = 2.6, diff = true, counts = { applied = 1, dropped = 1 } },
        },
    },
}

describe("windows matrix (belief columns)", function()
    for _, case in ipairs(CASES) do
        it(case.id .. ": " .. case.what, function()
            mx.run(case)
        end)
    end

    it("1000 Drains and 2000 operations allocate nothing", function()
        local env = mx.setup({ apl = { x = { steps = { "filler", "nuke" } } } })
        local key = mx.key({}, "x")
        local t = 2
        local ok, bytes = pcall(alloc.bytes, function(i)
            t = t + 0.2
            env.VS.WindowOp(key, i % 3 == 0 and mx.OP.CLOSE or mx.OP.OPEN, 5)
            env.VS.WindowOp(key, mx.OP.STEP, 2)
            env.VS.Drain(t)
        end, 1000)
        mx.teardown(env)
        assert(ok, bytes)
        assert.are.equal(0, bytes)
    end)

    -- L10, L11: the operations the belief logs (the core's trace, SetLog) replayed into a belief alone, with the same
    -- casts, give the same window states at every tick, and twice the same
    it(
        "L10/L11: a belief-only replay of the logged operations reproduces every tick's states, deterministically",
        function()
            local case = {
                apl = {
                    x = { steps = { "burst", "nuke" }, strict = true },
                    y = { duration = 3 },
                    z = { steps = { "filler", "nuke", "dot" } },
                },
            }
            local script = {
                { t = 2, ops = { { "x", "OPEN", HUGE }, { "y", "OPEN", 3 }, { "y", "CLOSE" }, { "z", "OPEN", HUGE } } },
                { t = 2.2, cast = "burst", ops = { { "y", "OPEN", 3 }, { "y", "CLOSE" }, { "y", "OPEN", 3 } } },
                { t = 2.4, cast = "filler", ops = { { "z", "STEP", 3 }, { "nope", "OPEN", 1 } } },
                { t = 2.6, cast = "nuke", ops = { { "x", "OPEN", HUGE } } },
                { t = 2.8, cast = "burst", ops = { { "z", "STEP", 1 } } },
                { t = 3 },
                { t = 6 },
            }
            local function play(env, feed)
                local states = {}
                for i, k in ipairs(script) do
                    if k.cast then
                        env.ctl.now = k.t - 0.05
                        env.ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", mx.IDS[k.cast])
                    end
                    env.ctl.now = k.t
                    env.ctl.Tick(k.t)
                    env.VS.Drain(k.t)
                    states[i] = {}
                    for _, name in ipairs({ "x", "y", "z" }) do
                        states[i][name] = { env.ns.Facade.Window(mx.key(case, name)) }
                    end
                    for _, o in ipairs(feed(i, k)) do
                        env.VS.WindowOp(o[1], o[2], o[3])
                    end
                end
                return states
            end
            local lines = {}
            local env = mx.setup(case)
            env.VS.SetLog({
                active = function()
                    return true
                end,
                write = function(fmt, ...)
                    local ok, s = pcall(string.format, fmt, ...)
                    if ok and s:find("^%[vs%] windowop") then
                        lines[#lines + 1] = s
                    end
                end,
            })
            local recorded = play(env, function(_, k)
                local out = {}
                for j, o in ipairs(k.ops or {}) do
                    out[j] = { mx.key(case, o[1]), mx.OP[o[2]], o[3] }
                end
                return out
            end)
            mx.teardown(env)
            -- each line: "[vs] windowop <applied|dropped> <key> <OP> <arg> t=<the stamp: the sending tick's cut-off>"
            local logged = {}
            for _, s in ipairs(lines) do
                local key, op, arg, at = s:match("^%[vs%] windowop %a+ (%S+) (%u+) (%S+) t=([%d.]+)$")
                assert(key, s)
                logged[#logged + 1] = { key, mx.OP[op], arg == "inf" and HUGE or tonumber(arg), tonumber(at) }
            end
            assert.are.equal(11, #logged) -- every operation sent before the last Drain
            local function replay()
                local e = mx.setup(case)
                local states = play(e, function(_, k)
                    local out = {}
                    for _, o in ipairs(logged) do
                        if math.abs(o[4] - k.t) < 1e-6 then
                            out[#out + 1] = o
                        end
                    end
                    return out
                end)
                mx.teardown(e)
                return states
            end
            assert.are.same(recorded, replay())
            assert.are.same(recorded, replay())
        end
    )
end)
