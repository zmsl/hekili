-- tools/accuracy/report.lua on a small fixture run: report.json keeps its keys and gains `liveLike` (the raw-live/
-- pass, auras hidden as on live) beside replay, solo (loop.worst.agreement) and crowd (loop.crowdedTarget39.agreement).
local function loopLine(agree)
    return ("fights=20 agreement %s (1000 ticks); react median 0 p90 1 never 0.012; ready while short 1; held while ready 2; "):format(
        agree
    ) .. "refused per 100 [], episodes 2.00/min; dps A/B 0.998; flicker 0.74/min (oracle 0.42); " .. "cpu mean 3.12 p99 5.01 ms ratio 1.123 (calibration 2.78 ms) bytes 1234 per Update"
end

local function sh(cmd)
    local p = assert(io.popen(cmd .. " 2>&1"))
    local out = p:read("*a")
    p:close()
    return out
end

local function write(path, lines)
    local f = assert(io.open(path, "w"))
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
end

local function raw(dir, solo, crowd, replay)
    local lines = {}
    for set = 1, 3 do
        lines[#lines + 1] = ("ACC loop\tFury\t%d\t%s\t%s"):format(set, loopLine(solo), solo * 1000 .. "/1000")
    end
    lines[#lines + 1] = ("ACC crowd\tFury\t1\t%s\t1.000\t1000"):format(loopLine(crowd))
    if replay then
        lines[#lines + 1] = "ACC floor\tFury (wowsims.com)\tfury\t0.5"
        lines[#lines + 1] = "Fury (wowsims.com) wowsims: fights=1 agreement 0.9 (9 ticks); decisions on-GCD "
            .. replay
            .. " (150) top [a 1]"
    end
    write(dir .. "/loop.loop_warrior_fury.txt", lines)
end

describe("tools/accuracy/report.lua", function()
    local dir = os.tmpname()
    setup(function()
        sh(("rm -f %s && mkdir -p %s/raw %s/raw-live"):format(dir, dir, dir))
        raw(dir .. "/raw", 0.9, 0.8, "0.900")
        raw(dir .. "/raw-live", 0.7, 0.6, "0.700")
    end)
    teardown(function()
        sh("rm -rf " .. dir)
    end)

    it("writes the live-like figures beside the full ones and keeps the old keys", function()
        local out = sh((".lua/bin/lua tools/accuracy/report.lua %s"):format(dir))
        assert.is_truthy(out:find("1 specs", 1, true), out)
        local f = assert(io.open(dir .. "/report.json"))
        local json = f:read("*a")
        f:close()
        -- the old keys, unchanged
        assert.is_truthy(json:find('"crowdedTarget39"', 1, true))
        assert.is_truthy(json:find('"replay": 0.9', 1, true))
        assert.is_truthy(json:find('"worst"', 1, true))
        -- the new block
        local live = json:match('"liveLike": (%b{})')
        assert.is_truthy(live, json)
        assert.is_truthy(live:find('"replay": 0.7', 1, true), live)
        assert.is_truthy(live:find('"solo": 0.7', 1, true), live)
        assert.is_truthy(live:find('"crowd": 0.6', 1, true), live)
        f = assert(io.open(dir .. "/report.md"))
        local md = f:read("*a")
        f:close()
        assert.is_truthy(md:find("| Warrior Fury | 0.900 | 0.700 | 0.900 | 0.700 | 0.800 | 0.600 |", 1, true), md)
    end)

    it("says none when there is no live pass", function()
        sh("rm -rf " .. dir .. "/raw-live")
        sh((".lua/bin/lua tools/accuracy/report.lua %s"):format(dir))
        local f = assert(io.open(dir .. "/report.json"))
        local json = f:read("*a")
        f:close()
        assert.is_truthy(json:find('"liveLike": "none"', 1, true), json)
    end)
end)
