-- tests/Game/harness/r6_pause_proof.lua: TEMPORARY, the proof branch only (lane 6, L1827 rows 2 and 4). Swaps the
-- belief's R.restMax for a proxy: writes go to a backing table, and every read (the row-4 out-of-combat 0 filter in
-- Sources/Power.lua and the other readers) compares the declaration-read boolean with the old name table's
-- (Engine/Sim/Constants.lua passive_regen, keyed by token). The proxy returns the real value: behaviour is unchanged.
-- Prints one line per install, "R6REST <label> reads=<n> mismatches=<m>" at each power of 2 reads (the first
-- included), and the first 5 mismatches of an install in full.
local M = {}
local n = 0
local OLD = { MANA = true, FOCUS = true, ENERGY = true, ESSENCE = true } -- passive_regen, upper-cased (Tracked.lua token)

function M.install(ns, label)
    n = n + 1
    local id = ("%s#%d"):format(tostring(label), n)
    local I = ns and ns.VirtualStateInternal
    local R = I and I.res
    io.stdout:write(("R6REST INSTALL %s %s\n"):format(id, R and R.restMax and "ok" or "NO-RES"))
    if not (R and R.restMax) then
        return
    end
    local back = {}
    for k, v in pairs(R.restMax) do
        back[k] = v
    end
    local reads, miss, nextAt = 0, 0, 1
    R.restMax = setmetatable({}, {
        __newindex = function(_, k, v)
            back[k] = v
        end,
        __index = function(_, r)
            local v = back[r]
            local old = OLD[R.token[r]] == true
            reads = reads + 1
            if (v == true) ~= old then
                miss = miss + 1
                if miss <= 5 then
                    io.stdout:write(
                        ("R6REST MISMATCH %s slot %s (%s) restMax %s old %s\n"):format(
                            id,
                            tostring(r),
                            tostring(R.token[r]),
                            tostring(v),
                            tostring(old)
                        )
                    )
                end
            end
            if reads == nextAt then
                nextAt = nextAt * 2
                io.stdout:write(("R6REST %s reads=%d mismatches=%d\n"):format(id, reads, miss))
            end
            return v
        end,
    })
end

return M
