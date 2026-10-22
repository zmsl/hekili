-- Game/Events/Tickets.lua
-- The ticket pool (unit-registry spec §3): one record per commit of ours, preallocated (TICKETS = 16; Rows held 8, and
-- a 2.1 s flight window plus two hands needs more). This file owns the records and their lifecycle; the matching rules
-- live in Events/Melee.lua (MELEE) and Events/Kinds.lua (every other kind); Events/Rows.lua turns payments into rows.
-- Pure: no client read. Allocates nothing after load.

local _, ns = ...
local I = ns.VirtualStateInternal

local T = {}
I.Tickets = T
T.CAP = 16
T.FREE, T.COMMITTED, T.OPEN, T.PROV = 0, 1, 2, 3
local CAP = T.CAP

-- Per ticket: state, kind (I.Expect's), x (hand for a swing, spell ID for a spell), the pinned GUID, the anchor time,
-- the window length, an off-hand swing's main reference, and a provisional avoid's LR and action ("" none).
T.state, T.kind, T.x, T.guid, T.at, T.w, T.ref, T.lr, T.avoid = {}, {}, {}, {}, {}, {}, {}, {}, {}
local state, kind, x, guid, at, w, ref, lr, avoid = T.state, T.kind, T.x, T.guid, T.at, T.w, T.ref, T.lr, T.avoid
for i = 1, CAP do
    state[i], kind[i], x[i], guid[i], at[i], w[i], ref[i], lr[i], avoid[i] = 0, 0, 0, "", 0, 0, 0, 0, ""
end

--- A free ticket, else the oldest open one (it gives way, unemitted). Allocates nothing.
function T.Slot()
    local oldest = 1
    for i = 1, CAP do
        if state[i] == 0 then
            return i
        elseif at[i] < at[oldest] then
            oldest = i
        end
    end
    return oldest
end

--- Opens a ticket of `k` for `xx` pinned to `g` ("" none) at t with window `win` s and main reference `mref`.
function T.Hold(k, xx, g, win, t, mref)
    local i = T.Slot()
    state[i], kind[i], x[i], guid[i], at[i], w[i] = T.OPEN, k, xx, g, t, win
    ref[i], lr[i], avoid[i] = mref or 0, 0, ""
    return i
end

--- Frees ticket i.
function T.Close(i)
    state[i], lr[i], avoid[i] = 0, 0, ""
end
