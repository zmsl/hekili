-- tools/accuracy/parse.lua: the line parsers of `make accuracy`. They read the lines the gates print (loop.line,
-- the wowsims replay, ready-time and live lines) and fail loudly (error) on a missing field, so a changed format
-- breaks the run and tests/accuracy_parse_spec.lua instead of leaving blank cells.
local M = {}

local function need(line, pat, what)
    local a, b, c, d = line:match(pat)
    if a == nil then
        error(("accuracy parse: no %s in: %s"):format(what, line:sub(1, 120)), 0)
    end
    return tonumber(a), b and tonumber(b), c and tonumber(c), d and tonumber(d)
end

--- A loop.line: the metrics of one 20-fight seed set.
function M.loop(line)
    local r = {}
    r.agreement, r.ticks = need(line, "agreement ([%d.]+) %((%d+) ticks%)", "agreement")
    r.readyShort = need(line, "ready while short (%d+)", "ready while short")
    r.heldReady = need(line, "held while ready (%d+)", "held while ready")
    r.dps = need(line, "dps A/B ([%d.]+);", "dps A/B")
    r.flicker, r.oracleFlicker = need(line, "flicker ([%d.]+)/min %(oracle ([%d.]+)%)", "flicker")
    local p99
    r.cpuMs, p99, r.ratio, r.calibration =
        need(line, "cpu mean ([%d.]+) p99 ([%d.]+) ms ratio ([%d.]+) %(calibration ([%d.]+) ms%)", "cpu")
    assert(p99)
    r.bytes = need(line, "bytes ([%d.]+) per Update", "bytes")
    local refused = line:match("refused per 100 %[(.-)%], episodes")
    if refused == nil then
        error("accuracy parse: no refusals in: " .. line:sub(1, 120), 0)
    end
    r.cost, r.cooldown, r.unmatched = 0, 0, 0 -- a kind absent from the list was never refused
    for why, n, _, u in refused:gmatch("(%w+) ([%d.]+) %(oracle ([%d.]+), unmatched ([%d.]+)%)") do
        if why == "cost" then
            r.cost, r.unmatched = tonumber(n), tonumber(u)
        elseif why == "cooldown" then
            r.cooldown = tonumber(n)
        end
    end
    return r
end

--- A wowsims replay line: decisions on-GCD, the share of wowsims's decisions our first icon matched, unrounded: the
--- matched count is the one that prints as the 3-decimal share of the printed total (unique below 500 decisions).
function M.replay(line)
    local share, n = need(line, "decisions on%-GCD ([%d.]+) %((%d+)%)", "decisions on-GCD")
    return { agreement = n > 0 and n < 500 and math.floor(share * n + 0.5) / n or share }
end

--- wrap.lua's unrounded loop agreement field "<agreed>/<ticks>" as a number; nil for nil.
function M.ratio(s)
    local a, b = (s or ""):match("^(%d+)/(%d+)$")
    return a and tonumber(a) / math.max(1, tonumber(b)) or nil
end

--- A wowsims ready-time line: the real (cost-window-free) median in seconds and the decisions never ready.
function M.ready(line)
    local never = need(line, "never (%d+) scope", "never")
    local median = need(line, "real %d+ %(early %d+ late %d+%) median ([%d.]+);", "real median")
    return { median = median, never = never }
end

--- A live (leveling) line: the worst idle seconds with a usable ability (the median line's first number is its median).
function M.live(line)
    return { idle = need(line, "idle ([%d.]+) s", "idle") }
end

--- One output line to (kind, fields...) or nil: "ACC ..." tab lines, and "<label> wowsims[ timing]:" / "live L<n>:".
function M.classify(line)
    local kind, rest = line:match("^ACC ([%w%-]+)\t(.*)$")
    if kind then
        local f = {}
        for x in (rest .. "\t"):gmatch("(.-)\t") do
            f[#f + 1] = x
        end
        return kind, f
    end
    local label, body = line:match("^(.-) wowsims timing: (.*)$")
    if label then
        return "timing", { label, body }
    end
    label, body = line:match("^(.-) wowsims: (.*)$")
    if label then
        return "replay", { label, body }
    end
    local level
    label, level, body = line:match("^(.-) live L(%d+): (.*)$")
    if label then
        return "live", { label, level, body }
    end
end

return M
