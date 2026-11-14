-- tools/wiki/collect/accuracy.lua: the per-spec accuracy table from docs/wiki/data/accuracy.json, a committed copy of
-- the report `make accuracy` writes (.accuracy/report.json; tools/accuracy/report.lua), refreshed by hand after a
-- batch accuracy run. Read as the accuracy page reads it: matches wowsims = wowsims.replay, solo =
-- loop.worst.agreement, crowded target = loop.crowdedTarget39.agreement, each beside its live-like number
-- (liveLike.replay, .solo, .crowd). Each cell is "full information / live-like".
local json = require("dkjson")

local M = {}

M.DATA = "docs/wiki/data/accuracy.json"

local function load()
    local f = assert(io.open(M.DATA, "rb"))
    local s = f:read("*a")
    f:close()
    return assert(json.decode(s), M.DATA .. ": not JSON")
end

local function pair(a, b)
    if type(a) ~= "number" or type(b) ~= "number" then
        return "n/a"
    end
    return ("%.3f / %.3f"):format(a, b)
end

--- Class, spec, matches wowsims, solo, crowded target: one row per spec, in the report's order.
function M.rows()
    local specs = load().specs
    local ids = {}
    for id in pairs(specs) do
        ids[#ids + 1] = tonumber(id)
    end
    table.sort(ids)
    local rows = {}
    for _, id in ipairs(ids) do
        local s = specs[tostring(id)]
        local loop = type(s.loop) == "table" and s.loop or {}
        local live = type(s.liveLike) == "table" and s.liveLike or {}
        local w = type(s.wowsims) == "table" and s.wowsims or {}
        local name = s.spec:gsub(" L(%d+)$", " (level %1)")
        rows[#rows + 1] = {
            s.class,
            name,
            pair(w.replay, live.replay),
            pair(loop.worst and loop.worst.agreement, live.solo),
            pair(loop.crowdedTarget39 and loop.crowdedTarget39.agreement, live.crowd),
        }
    end
    return rows
end

return M
