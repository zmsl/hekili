-- Game/State/Sources/Presence/Default.lua
-- The Default AuraPresence provider (providers spec §2.3): covers nothing; the belief's modelled timers stand.

local _, ns = ...
local I = ns.VirtualStateInternal

local Q = { name = "default", scope = nil, covered = 0, onEdge = nil } -- l10n: verbatim
function Q.Activate() end
function Q.Deactivate() end
function Q.Presence()
    return I.UNDECIDED
end
function Q.Sweep() end
--- nLive, nUp, nNone, nStale, tUp, tNone: no evidence.
function Q.Counts()
    return 0, 0, 0, 0, 0, 0
end
function Q.Mappable()
    return false
end
I.PRESENCE.default = Q
I.presence = Q -- answers before the first build
