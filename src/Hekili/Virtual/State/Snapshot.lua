-- Virtual/State/Snapshot.lua
-- VirtualState.Snapshot() (spec §3.5): every tracked record projected to now (est, lo, hi, conf, basis, the four
-- `last` slots), the facts, the log's fill and drop counts, the read statuses per source, the drain cost and, with
-- debug on, the rings. It allocates and is for debugging only: /run print(Hekili.Virtual.State.Snapshot())

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local format, concat, sort = string.format, table.concat, table.sort

local function slot(s)
    return format("%.2f@%.2f#%d", s.v, s.t, s.event)
end

--- A multi-line report of everything VirtualState believes, projected to now. Allocates.
---@return string
function VS.Snapshot()
    local api = I.api
    local now = api and api.GetTime() or I.clock
    local out = {}
    out[#out + 1] = format(
        "VirtualState t=%.2f clock=%.2f class=%s combat=%s moving=%s",
        now,
        I.clock,
        tostring(I.class),
        tostring(I.inCombat),
        tostring(I.moving)
    )
    out[#out + 1] = format(
        "log %d/%d dropped=%d stage dropped=%d drain=%.2fms casts=%d errors=%d now=%d",
        I.log.n,
        I.log.cap,
        I.log.dropped,
        S.dropped,
        I.drainMs or 0,
        I.drainCasts or 0,
        I.nowErrors or 0,
        I.nowRuns or 0
    )
    if I.nowError ~= nil then
        out[#out] = out[#out] .. " error=" .. tostring(I.nowError)
    end
    local names = {}
    for name in pairs(S.status) do
        names[#names + 1] = name
    end
    sort(names)
    for _, name in ipairs(names) do
        out[#out + 1] = format("read %s: %s", name, S.status[name])
    end
    if not I.built then
        out[#out + 1] = "no tracked set yet (VirtualState.SpecChanged has not run)"
        return concat(out, "\n")
    end
    for k = 1, #I.SNAPSHOT do
        I.SNAPSHOT[k](out, now) -- families project their records to now and add their facts
    end
    for i = 1, #I.records do
        local r = I.records[i]
        local l = r.last
        out[#out + 1] = format(
            "%s est=%.2f lo=%.2f hi=%.2f conf=%.2f basis=%s O=%s P=%s M=%s D=%s",
            I.labels[i],
            r.est,
            r.lo,
            r.hi,
            r.conf,
            r.basis,
            slot(l.observed),
            slot(l.pinned),
            slot(l.modelled),
            slot(l.default)
        )
        if r.ring then
            for _, origin in ipairs(I.ORIGINS) do
                local ring, parts = r.ring[origin], {}
                for j = 1, I.RING do
                    if ring[j].t > 0 then
                        parts[#parts + 1] = slot(ring[j])
                    end
                end
                if #parts > 0 then
                    out[#out + 1] = format("  ring %s: %s", origin, concat(parts, " "))
                end
            end
        end
    end
    return concat(out, "\n")
end
