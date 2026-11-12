-- tools/accuracy/report.lua: the report half of `make accuracy`. Reads .accuracy/raw/*.txt (tools/accuracy/run.sh),
-- writes .accuracy/report.json and .accuracy/report.md. A spec is a (class, name) found in any printed line; its
-- class comes from the spec file's name, its name from the gate's label. "none" = expected but not printed (a loop
-- that was not run, a replay whose line is missing); "n/a" = no wowsims preset for the spec (no tests/Forever/wowsims
-- request for it). Usage: lua tools/accuracy/report.lua [dir]
local parse = dofile((arg[0]:match("^(.*)/[^/]*$") or ".") .. "/parse.lua")
local dir = arg[1] or ".accuracy"

local function snake(s)
    return (s:lower():gsub("%s+", "_"))
end
local function key(label, class) -- "Warrior Protection" and "Protection (wowsims.com)" name the same spec in their class
    label = label:gsub(" %(wowsims%.com%)$", ""):gsub("^" .. class .. " ", ""):gsub(" L60$", "")
    return label
end
local function exists(path)
    local f = io.open(path)
    if f then
        f:close()
    end
    return f ~= nil
end

-- Two passes over the same spec files (run.sh): raw/ is the default world (auras served as truth, "full information"),
-- raw-live/ the same specs under the live-auras arm (our own auras hidden in combat, "live-like"); the second pass
-- is optional (a report from an older run has none).
local function load(rawDir)
    local specs, order = {}, {}
    local function spec(class, label)
        local k = class .. "/" .. key(label, class)
        if not specs[k] then
            specs[k] = { class = class, name = key(label, class), loop = {}, live = {} }
            order[#order + 1] = k
        end
        return specs[k]
    end
    local p = io.popen("ls " .. rawDir .. " 2>/dev/null")
    for name in p:lines() do
        local kind, rest = name:match("^(%a+)%.(.*)%.txt$")
        local class = (rest:match("^loop_(%a+)") or rest:match("^wowsims_(%a+)") or "?"):gsub("^%l", string.upper)
        for line in io.lines(rawDir .. "/" .. name) do
            local what, f = parse.classify(line)
            if what == "loop" then
                local r = parse.loop(f[3])
                r.agreement = parse.ratio(f[4]) or r.agreement
                spec(class, f[1]).loop[tonumber(f[2])] = r
            elseif what == "crowd" then
                spec(class, f[1]).crowd = parse.loop(f[3])
                spec(class, f[1]).crowdRatio = tonumber(f[4])
            elseif what == "floor" then
                spec(class, f[1]).replayFloor = tonumber(f[3])
                spec(class, f[1]).preset = f[2]
            elseif what == "replay" then
                spec(class, f[1]).replay = parse.replay(f[2])
            elseif what == "ready-floor" then
                spec(class, f[1]).readyFloor = { median = tonumber(f[3]), count = tonumber(f[4]) }
            elseif what == "timing" then
                spec(class, f[1]).ready = parse.ready(f[2])
            elseif what == "live" then
                spec(class, f[1]).live[tonumber(f[2])] = parse.live(f[3]).idle
            end
        end
    end
    p:close()
    return specs, order
end
local specs, order = load(dir .. "/raw")
local liveSpecs = load(dir .. "/raw-live")

-- worst of the seed sets: the lowest agreement and dps, the highest of everything else
local LOWEST = { agreement = true, dps = true }
local METRICS = { "agreement", "flicker", "readyShort", "heldReady", "dps", "cost", "cooldown", "unmatched" }
local function worst(sets)
    local w
    for s = 1, 3 do
        local r = sets[s]
        if r then
            w = w or {}
            for _, m in ipairs(METRICS) do
                local a, b = w[m], r[m]
                if a == nil or (LOWEST[m] and b < a) or (not LOWEST[m] and b > a) then
                    w[m] = b
                    if m == "flicker" then
                        w.oracleFlicker = r.oracleFlicker -- the worst set's own, not another set's
                    end
                end
            end
        end
    end
    return w
end

local liveArm = "unknown" -- run.sh writes the arm of the live pass beside raw-live/
do
    local f = io.open(dir .. "/live-arm")
    if f then
        liveArm = f:read("*l") or liveArm
        f:close()
    end
end
local list = {}
for _, k in ipairs(order) do
    local s = specs[k]
    s.hasPreset = s.preset ~= nil or exists(("tests/Forever/wowsims/%s_%s.json"):format(s.class:lower(), snake(s.name)))
    s.worst = worst(s.loop)
    local l = liveSpecs[k] -- live-like figures: replay, solo (worst seed set), crowd; "none" where the arm printed nothing
    if l then
        s.liveLike = {
            replay = l.replay and l.replay.agreement or "none",
            solo = l.loop[1] and l.loop[2] and l.loop[3] and worst(l.loop).agreement or "none",
            crowd = l.crowd and l.crowd.agreement or "none",
            arm = liveArm,
        }
    end
    s.once = s.loop[1] -- cpu, calibration and bytes: the first seed set's
    list[#list + 1] = s
end
table.sort(list, function(a, b)
    return a.class ~= b.class and a.class < b.class or (a.class == b.class and a.name < b.name)
end)

local function num(x, f)
    return x == nil and "none" or (f or "%.3f"):format(x)
end

local json = {}
local function enc(v, ind)
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        local out = {}
        for _, k in ipairs(keys) do
            out[#out + 1] = ind .. "  " .. ("%q"):format(tostring(k)) .. ": " .. enc(v[k], ind .. "  ")
        end
        return #out == 0 and "{}" or "{\n" .. table.concat(out, ",\n") .. "\n" .. ind .. "}"
    elseif t == "number" then
        return ("%.6g"):format(v)
    end
    return ("%q"):format(tostring(v))
end

local md = {
    "# Accuracy (generated by `make accuracy`)",
    "",
    "Replay: wowsims decisions on-GCD matched (floor). Ready: median seconds of real (cost-window-free) ready-time misses, never-ready count. Live: worst idle seconds per level. Loop columns are the worst of seeds 1-20 / 21-40 / 41-60 (the oracle flicker is the worst set's own); cpu ms, cal ratio and bytes are seeds 1-20 only. `none` = expected, not printed; `n/a` = no wowsims preset.",
    "",
    "| Spec | Replay (floor) | Ready med (floor) / never | Live idle | Agree | Flicker (oracle) | Rdy short | Held rdy | dps A/B | Refused cost/cd/unmatched | cpu ms | cal ratio | bytes |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
}
local md2 = {
    "",
    "## Per seed set",
    "",
    "| Spec | Seeds | Agree | Flicker (oracle) | Rdy short | Held rdy | dps A/B | Cost/cd/unmatched |",
    "|---|---|---|---|---|---|---|---|",
}
for _, s in ipairs(list) do
    local nameText = s.class .. " " .. s.name
    local replay, ready, live
    if not s.hasPreset then
        replay, ready, live = "n/a", "n/a", "n/a"
    else
        replay = s.replay and (num(s.replay.agreement) .. " (" .. num(s.replayFloor, "%.2f") .. ")") or "none"
        ready = s.ready
                and (num(s.ready.median, "%.2f") .. " (" .. num(s.readyFloor and s.readyFloor.median, "%.2f") .. ") / " .. s.ready.never)
            or "none"
        local lv, lvl = {}, {}
        for level in pairs(s.live) do
            lvl[#lvl + 1] = level
        end
        table.sort(lvl)
        for _, level in ipairs(lvl) do
            lv[#lv + 1] = ("L%d %.1f"):format(level, s.live[level])
        end
        live = #lv > 0 and table.concat(lv, ", ") or "none"
    end
    local w, o = s.worst, s.once
    if not (s.loop[1] and s.loop[2] and s.loop[3]) then -- a spec file that timed out or died
        w = nil
        io.stderr:write(
            ("accuracy: WARNING %s: loop seed sets missing (%d of 3), shown as none\n"):format(
                nameText,
                (s.loop[1] and 1 or 0) + (s.loop[2] and 1 or 0) + (s.loop[3] and 1 or 0)
            )
        )
    end
    if w then
        md[#md + 1] = ("| %s | %s | %s | %s | %.3f | %.2f (%.2f) | %d | %d | %.3f | %.1f/%.1f/%.1f | %.2f | %.2f | %.0f |"):format(
            nameText,
            replay,
            ready,
            live,
            w.agreement,
            w.flicker,
            w.oracleFlicker,
            w.readyShort,
            w.heldReady,
            w.dps,
            w.cost,
            w.cooldown,
            w.unmatched,
            o.cpuMs,
            o.ratio,
            o.bytes
        )
        for set = 1, 3 do
            local r = s.loop[set]
            md2[#md2 + 1] = ("| %s | %d-%d | %.3f | %.2f (%.2f) | %d | %d | %.3f | %.1f/%.1f/%.1f |"):format(
                nameText,
                set * 20 - 19,
                set * 20,
                r.agreement,
                r.flicker,
                r.oracleFlicker,
                r.readyShort,
                r.heldReady,
                r.dps,
                r.cost,
                r.cooldown,
                r.unmatched
            )
        end
    else
        md[#md + 1] = ("| %s | %s | %s | %s | none | none | none | none | none | none | none | none | none |"):format(
            nameText,
            replay,
            ready,
            live
        )
    end
    json[#json + 1] = {
        class = s.class,
        spec = s.name,
        wowsims = s.hasPreset and {
            replay = s.replay and s.replay.agreement or "none",
            replayFloor = s.replayFloor or "none",
            readyMedian = s.ready and s.ready.median or "none",
            readyFloor = s.readyFloor and s.readyFloor.median or "none",
            readyNever = s.ready and s.ready.never or "none",
            liveIdle = next(s.live) and s.live or "none",
        } or "n/a",
        liveLike = s.liveLike or "none", -- the same figures with our auras hidden in combat (raw-live/); "none" = no live pass
        loop = w and {
            seeds = { s.loop[1], s.loop[2], s.loop[3] },
            worst = w,
            crowdedTarget39 = s.crowd or "none",
            crowdTickRatio = s.crowdRatio or "none",
            once = { cpuMs = o.cpuMs, ratio = o.ratio, calibration = o.calibration, bytes = o.bytes },
        } or "none",
    }
end
local CROWD = "crowded target (39 others)"
local md3 = {
    "",
    "## " .. CROWD .. ", seeds 1-20, beside the same seeds solo (reported only, no gate)",
    "",
    "| Spec | Run | Ticks (crowd/solo) | Agree | Flicker (oracle) | Rdy short | dps A/B |",
    "|---|---|---|---|---|---|---|",
}
for _, s in ipairs(list) do
    for _, row in ipairs({ { "solo", s.loop[1] }, { CROWD, s.crowd, s.crowdRatio and ("%.2f"):format(s.crowdRatio) } }) do
        local r = row[2]
        md3[#md3 + 1] = r
                and ("| %s %s | %s | %d%s | %.3f | %.2f (%.2f) | %d | %.3f |"):format(
                    s.class,
                    s.name,
                    row[1],
                    r.ticks,
                    row[3] and (" (" .. row[3] .. ")") or "",
                    r.agreement,
                    r.flicker,
                    r.oracleFlicker,
                    r.readyShort,
                    r.dps
                )
            or ("| %s %s | %s | none | none | none | none | none |"):format(s.class, s.name, row[1])
    end
end
local md4 = {
    "",
    "## Two numbers per spec: full information and live-like",
    "",
    "Full information: the harness serves our auras as truth. Live-like: the same specs with our own auras hidden in combat, as on the live client, under harness arm `"
        .. liveArm
        .. "` (`live-auras-none` = no Cooldown Manager item, so no hidden aura is seen at all: the lower bound; `live-auras` = the class's real layout, classes without one print none). Solo = worst of the three seed sets; crowd = 39 others, seeds 1-20.",
    "",
    "| Spec | Replay full | Replay live-like | Solo full | Solo live-like | Crowd full | Crowd live-like |",
    "|---|---|---|---|---|---|---|",
}
for _, s in ipairs(list) do
    local l = s.liveLike or {}
    local function n(x)
        return num(type(x) == "number" and x or nil)
    end
    local solo = s.loop[1] and s.loop[2] and s.loop[3] and s.worst.agreement or nil
    md4[#md4 + 1] = ("| %s %s | %s | %s | %s | %s | %s | %s |"):format(
        s.class,
        s.name,
        n(s.hasPreset and s.replay and s.replay.agreement or nil),
        n(l.replay),
        n(solo),
        n(l.solo),
        n(s.crowd and s.crowd.agreement),
        n(l.crowd)
    )
end
for _, l in ipairs(md4) do
    md[#md + 1] = l
end
for _, l in ipairs(md2) do
    md[#md + 1] = l
end
for _, l in ipairs(md3) do
    md[#md + 1] = l
end

local f = assert(io.open(dir .. "/report.json", "w"))
f:write(enc({ specs = json }, ""), "\n")
f:close()
f = assert(io.open(dir .. "/report.md", "w"))
f:write(table.concat(md, "\n"), "\n")
f:close()
print(("accuracy: %d specs -> %s/report.json, %s/report.md"):format(#list, dir, dir))
