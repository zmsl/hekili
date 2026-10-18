-- tests/Forever/bench_spec.lua (`make bench`, #bench; not in `make check`; in tests/Forever as it names the class):
-- per-Update cost of headless Arms, ours driving alone at 5 Hz, Primary only. Adapted from the codebase audit's scratch
-- specs (perf, coup, alloc; docs/research/2026-10-17-codebase-audit.md Appendix A). Pass 1 times Hekili.Update; pass 2
-- counts bytes with the GC stopped: Update run directly and, on alternate Updates, in one reused coroutine that yields
-- a sentinel after each Update as Engine/Driver.lua runs it, and each UNIT_COMBAT dispatch. Prints the table; asserts only that the fights ran.
local loop = require("Game.harness.loop")
local ww = require("Forever.helpers.warrior_world")

local FIGHTS = 6

local function stats(list)
    local s, mx = 0, 0
    for _, v in ipairs(list) do
        s, mx = s + v, math.max(mx, v)
    end
    table.sort(list)
    return s / math.max(1, #list), list[math.max(1, math.ceil(0.95 * #list))] or 0, mx
end

local function fights(L)
    for f = 1, FIGHTS do
        loop.run(L, f, {}, { { H = L.us } })
    end
end

-- Bytes allocated by fn(...) with the GC stopped.
local function bytes(fn, ...)
    collectgarbage("stop")
    local b = collectgarbage("count")
    fn(...)
    local d = (collectgarbage("count") - b) * 1024
    collectgarbage("restart")
    return d
end

describe("headless Arms per-Update cost #bench", function()
    it("prints ms per Update and bytes per Update (direct, coroutine) and per UNIT_COMBAT over 6 fights", function()
        local L = loop.new(ww)
        local H = L.us
        local hk = H.Hekili
        local upd = hk.Update

        local ms = {}
        hk.Update = function(...)
            local c0 = os.clock()
            local r = upd(...)
            ms[#ms + 1] = (os.clock() - c0) * 1000
            return r
        end
        fights(L)

        local direct, co, uc = {}, {}, {}
        local DONE = {}
        local thread = coroutine.create(function()
            while true do
                coroutine.yield(DONE, upd())
            end
        end)
        local function viaDriver()
            hk.maxFrameTime, hk.activeFrameStart = 1e9, 0 -- the Driver's frame budget, never reached here
            local ok, r
            repeat
                ok, r = coroutine.resume(thread)
                assert(ok, r)
            until r == DONE
        end
        hk.Update = function()
            if (#direct + #co) % 2 == 0 then
                co[#co + 1] = bytes(viaDriver)
            else
                direct[#direct + 1] = bytes(upd)
            end
            return true
        end
        local fire = H.Fire
        H.Fire = function(ev, ...)
            if ev == "UNIT_COMBAT" then
                uc[#uc + 1] = bytes(fire, ev, ...)
            else
                fire(ev, ...)
            end
        end
        fights(L)
        hk.Update, H.Fire = upd, fire

        local rows = {
            { "ms per Update", ms, "%8.3f" },
            { "B per Update, direct", direct, "%8.0f" },
            { "B per Update, Driver coroutine", co, "%8.0f" },
            { "B per UNIT_COMBAT", uc, "%8.1f" },
        }
        print(("\nbench (%d fights)                      n     mean      p95      max"):format(FIGHTS))
        for _, row in ipairs(rows) do
            local f = row[3]
            local mean, p95, mx = stats(row[2])
            print(("%-32s %7d " .. f .. " " .. f .. " " .. f):format(row[1], #row[2], mean, p95, mx))
        end
        assert.is_true(#ms > 1000 and #direct > 500 and #uc > 500)
    end)
end)
