-- tests/Game/harness/r6_pause_proof.lua: TEMPORARY, the proof branch only (lane 6, L1827 row 4). Wraps the belief's
-- I.RegenPaused, which Sources/Power.lua calls only on an out-of-combat regen read of 0, and compares its answer with the
-- old filter's: the slot's token is one the core's name table listed as resting at max (Engine/Sim/Constants.lua
-- passive_regen, keyed by name, not the pack's new `rest` declaration). The wrapper returns the real answer: behaviour
-- is unchanged. Prints one line per install, "R6PAUSE <label> evals=<n> mismatches=<m>" at each power of 2 evaluations
-- (the first included), and every mismatch in full.
local M = {}
local n = 0
local OLD = { MANA = true, FOCUS = true, ENERGY = true, ESSENCE = true } -- Constants.lua passive_regen, upper-cased (Tracked.lua token)

function M.install(ns, label)
    n = n + 1
    local id = ("%s#%d"):format(tostring(label), n)
    local I = ns and ns.VirtualStateInternal
    local real = I and I.RegenPaused
    io.stdout:write(("R6PAUSE INSTALL %s %s\n"):format(id, real and "ok" or "NO-REGENPAUSED"))
    if not real then
        return
    end
    local evals, miss, nextAt = 0, 0, 1
    I.RegenPaused = function(r, t)
        local p = real(r, t)
        local old = OLD[I.res.token[r]] == true
        evals = evals + 1
        if p ~= old then
            miss = miss + 1
            io.stdout:write(
                ("R6PAUSE MISMATCH %s slot %s (%s) t %.3f paused %s oldRestMax %s restMax %s\n"):format(
                    id,
                    tostring(r),
                    tostring(I.res.token[r]),
                    t,
                    tostring(p),
                    tostring(old),
                    tostring(I.res.restMax[r])
                )
            )
        end
        if evals == nextAt then
            nextAt = nextAt * 2
            io.stdout:write(("R6PAUSE %s evals=%d mismatches=%d\n"):format(id, evals, miss))
        end
        return p
    end
end

return M
