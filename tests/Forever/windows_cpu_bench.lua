-- tests/Forever/windows_cpu_bench.lua (windows design v6 rulings 19, 20, 24: the Phase 2 CPU numbers). Not a spec:
-- the name keeps it out of the default run, and it asserts no timing. It prints process CPU per Update (os.clock),
-- headless Arms in combat, Primary subscribed (the whole Update: every display walked where wanted).
--   BENCH=windows (both arms with an empty precombat list, so every walk reaches the default list): the synthetic priorities W09 (adjacent, and the §13 shape: open at the top, close at the bottom),
--     R03 and W05, each as window lines put on top of the shipped Arms default list against the same list without
--     them. Each arm is loaded out of combat (the belief applies the new generation at a Drain out of combat, as an
--     edit in the options does), then combat starts, a warm-up, the measured Updates. Pairs interleaved, the order
--     alternating; per-pair ratios, their median and range, restarts per slot, operations per Update. The "with"
--     arm asserts the windows are live: the operations bound is set, the belief applied operations, dropped none.
--   BENCH=arms: the shipped Arms priority alone (no window line), for a base-vs-tip comparison run from two trees.
-- Run (under the gate lock): BENCH=windows .lua/bin/busted -p windows_cpu_bench tests/Forever/windows_cpu_bench.lua
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local BENCH = os.getenv("BENCH") or "windows"
local PAIRS = tonumber(os.getenv("PAIRS") or "") or 10
local N = tonumber(os.getenv("UPDATES") or "") or 300

local function parse(H, text)
    local lines = H.Hekili:ParseActionList(text, true)
    for _, l in ipairs(lines) do
        l.enabled = true
    end
    return lines
end

local W = "actions+=/window,name=x,duration=6"
local CASES = {
    { id = "W09-adjacent", windows = W, top = "actions+=/open_window,name=x\nactions+=/close_window,name=x" },
    {
        id = "W09-top-bottom",
        windows = W,
        top = "actions+=/open_window,name=x",
        bottom = "actions+=/close_window,name=x",
    },
    {
        id = "R03",
        windows = "actions+=/window,name=a,duration=6\nactions+=/window,name=b,duration=6\nactions+=/window,name=c,duration=6",
        top = "actions+=/open_window,name=c,if=window.b.up\nactions+=/open_window,name=b,if=window.a.up\nactions+=/open_window,name=a",
    },
    { id = "W05", windows = "actions+=/window,name=x,duration=3,refresh=1", top = "actions+=/open_window,name=x" },
}

local function boot()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    H.t = H.ctl.now + 0.2
    assert(headless.cycle(H, H.t))
    H.Hekili.Engine.Subscribe("Primary", function() end)
    return H
end

local function step(H)
    H.t = H.t + 0.2
    assert(headless.cycle(H, H.t))
end

local function median(xs)
    local s = {}
    for i, v in ipairs(xs) do
        s[i] = v
    end
    table.sort(s)
    local n = #s
    return n % 2 == 1 and s[(n + 1) / 2] or (s[n / 2] + s[n / 2 + 1]) / 2
end

if BENCH == "arms" then
    describe("windows CPU bench: shipped Arms", function()
        it("ms per Update", function()
            local H = boot()
            H.Fire("PLAYER_REGEN_DISABLED")
            for _ = 1, 30 do
                step(H)
            end
            local c = os.clock()
            for _ = 1, 900 do
                step(H)
            end
            print(string.format("ARMS %s %.4f ms per Update", os.getenv("ARM") or "?", (os.clock() - c) / 900 * 1000))
        end)
    end)
    return
end

describe("windows CPU bench: W09, R03, W05", function()
    for _, case in ipairs(CASES) do
        it(case.id, function()
            local H = boot()
            local VSI = H.ns.VirtualStateInternal
            local lists = H.Hekili.DB.profile.packs[ww.PACK].lists
            -- both arms without the precombat list: the headless player presses nothing, so a precombat pick that stays
            -- ready in combat would end every walk before the default list (and its window lines) is reached
            lists.precombat = {}
            local base, windows = lists.default, parse(H, case.windows)
            local with = parse(H, case.top)
            for _, e in ipairs(base) do
                with[#with + 1] = e
            end
            for _, e in ipairs(case.bottom and parse(H, case.bottom) or {}) do
                with[#with + 1] = e
            end
            local function arm(on)
                H.Fire("PLAYER_REGEN_ENABLED")
                lists.windows = on and windows or nil
                lists.default = on and with or base
                H.Hekili:LoadScripts()
                H.Hekili:ReviewPacks()
                step(H) -- out of combat: Update applies the pack's windows, the belief builds its rows at this Drain
                step(H)
                H.Fire("PLAYER_REGEN_DISABLED")
                for _ = 1, 20 do
                    step(H)
                end
                local Q = VSI.winOps
                local applied, dropped, refused = Q.applied, Q.dropped, Q.refused
                local ops = 0
                local op = H.ns.VirtualState.WindowOp
                H.ns.VirtualState.WindowOp = function(...)
                    ops = ops + 1
                    return op(...)
                end
                local r1, r2 = 0, 0
                local c = os.clock()
                for _ = 1, N do
                    step(H)
                    local recs = H.Hekili.Engine.Output.Primary.recs
                    r1, r2 = r1 + (recs[1].restarts or 0), r2 + (recs[2] and recs[2].restarts or 0)
                end
                local ms = (os.clock() - c) / N * 1000
                H.ns.VirtualState.WindowOp = op
                if on then -- the windows are live: the bound set, operations applied, none dropped
                    assert.is_true(VSI.def.aplOpCap > 0, case.id .. ": no operations bound")
                    if os.getenv("BENCH_DEBUG") then
                        local DB = H.Hekili.Scripts.DB
                        print(
                            case.id,
                            "ops",
                            ops,
                            "applied",
                            Q.applied - applied,
                            "refused",
                            Q.refused - refused,
                            "cap",
                            VSI.def.aplOpCap,
                            "pick",
                            H.Hekili.Engine.Output.Primary.recs[1].actionName,
                            "line1",
                            tostring(DB[ww.PACK .. ":default:1"] and DB[ww.PACK .. ":default:1"].Error),
                            "action1",
                            tostring(lists.default[1].action),
                            "combat",
                            tostring(VSI.inCombat)
                        )
                    end
                    assert.is_true(ops > 0, case.id .. ": no operation sent")
                    assert.is_true(Q.applied > applied, case.id .. ": the belief applied nothing")
                    assert.are.equal(dropped, Q.dropped, case.id .. ": operations dropped")
                else
                    assert.are.equal(0, ops)
                end
                return ms, r1 / N, r2 / N, ops / N, Q.refused - refused
            end
            local ratios, sOn, sOff = {}, 0, 0
            local r1, r2, opsPer, refused
            for p = 1, PAIRS do
                local on, off
                if p % 2 == 1 then
                    off = arm(false)
                    on, r1, r2, opsPer, refused = arm(true)
                else
                    on, r1, r2, opsPer, refused = arm(true)
                    off = arm(false)
                end
                ratios[p], sOn, sOff = on / off, sOn + on, sOff + off
            end
            local lo, hi = math.huge, 0
            for _, r in ipairs(ratios) do
                lo, hi = math.min(lo, r), math.max(hi, r)
            end
            print(
                string.format(
                    "CPU %s: with %.3f ms, without %.3f ms per Update (mean of %d pairs x %d); ratio median %.3f, range %.3f-%.3f;"
                        .. " restarts per slot: slot1 %.2f slot2 %.2f; operations per Update %.2f; refused %d (last pair)",
                    case.id,
                    sOn / PAIRS,
                    sOff / PAIRS,
                    PAIRS,
                    N,
                    median(ratios),
                    lo,
                    hi,
                    r1,
                    r2,
                    opsPer,
                    refused
                )
            )
            assert.are.same({}, H.errors)
        end)
    end
end)
