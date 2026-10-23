-- Game/State/Sources/Outcomes/Default.lua
-- The Default Outcomes provider (providers spec §2.1): no evidence beyond the rows; every consumer runs today's path
-- (the swing's LR at its row, the recovery spec's expectation at its lost close).

local _, ns = ...
local I = ns.VirtualStateInternal

local P = { name = "default", SWING_DELAY = 0, ROW_DELAY = 0 }
function P.Activate() end
function P.Deactivate() end
function P.SwingOutcome()
    return I.UNDECIDED
end
function P.RowOwner()
    return I.UNDECIDED
end
function P.EnemyHitAt()
    return nil
end
function P.Audit()
    return nil
end
I.OUTCOMES.default = P
I.outcomes = P -- answers before the first build (a row or a tick before SpecChanged)
