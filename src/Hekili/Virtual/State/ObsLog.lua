-- Virtual/State/ObsLog.lua
-- The observation log (spec §4.1): a preallocated ring of { kind, t, a, b, c } that sources write and only Drain
-- reads, oldest first. A full ring drops its oldest observation and counts it. Adding allocates nothing.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/ObsLog.lua (New :26, Add :44, At :63, Shift :70, Clear :79).

local _, ns = ...
local I = ns.VirtualStateInternal

local ObsLog = {}
I.ObsLog = ObsLog

--- Creates a log of `cap` preallocated observations. Load time only.
---@param cap integer
---@return table
function ObsLog.New(cap)
    if type(cap) ~= "number" or cap < 1 then
        error("VirtualState: an observation log needs a capacity of at least 1", 2)
    end
    local log = { cap = cap, head = 1, n = 0, dropped = 0, obs = {} }
    for i = 1, cap do
        log.obs[i] = { kind = 0, t = 0, a = 0, b = 0, c = 0 }
    end
    return log
end

--- Records an observation (`a`, `b`, `c` default to 0).
function ObsLog.Add(log, kind, t, a, b, c)
    local cap = log.cap
    local i
    if log.n == cap then
        i = log.head
        log.head = i % cap + 1 -- nonzero: New validates cap >= 1
        log.dropped = log.dropped + 1
    else
        i = (log.head + log.n - 1) % cap + 1 -- nonzero: New validates cap >= 1
        log.n = log.n + 1
    end
    local o = log.obs[i]
    o.kind, o.t, o.a, o.b, o.c = kind, t, a or 0, b or 0, c or 0
end

--- The i-th oldest observation held (1..log.n). The record is reused: read it, don't keep it.
function ObsLog.At(log, i)
    return log.obs[(log.head + i - 2) % log.cap + 1] -- nonzero: New validates cap >= 1
end

--- Takes the oldest observation out of the log and returns it. The record is reused: read it before the next Add.
function ObsLog.Shift(log)
    local o = log.obs[log.head]
    log.head = log.head % log.cap + 1 -- nonzero: New validates cap >= 1
    log.n = log.n - 1
    return o
end

--- Forgets every observation held.
function ObsLog.Clear(log)
    log.head = 1
    log.n = 0
end

--- The log's size: TDF's App.LOG_CAP (src/TacoDogForever/Game/App.lua:26).
I.LOG_CAP = 256
I.log = ObsLog.New(I.LOG_CAP)
