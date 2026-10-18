-- tests/Forever/helpers/alts.lua (display styles plan, Task 3c): widens the belief band the alternative passes read.
local M = {}

--- `VS.Power` answers with the high bound raised by 40 (capped at 100): in the Arms fights rage's band is otherwise
--- zero, so no pass would run. The low bound (all the client facade's UnitPower reads, so the main records) and the
--- estimate are unchanged. One preallocated answer: nothing is allocated per call.
function M.widen(VS)
    local power, fake = VS.Power, { est = 0, lo = 0, hi = 0, conf = 0 }
    VS.Power = function(pt, now)
        local r = power(pt, now)
        fake.est, fake.lo, fake.hi, fake.conf = r.est, r.lo, math.min(100, r.hi + 40), r.conf
        return fake
    end
end

return M
