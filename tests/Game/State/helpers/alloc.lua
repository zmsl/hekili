-- tests/Game/State/helpers/alloc.lua
-- Measures bytes allocated by a loop with the collector stopped (spec §2 zero-allocation rule).
-- Copied as is from Taco Dog Forever, tests/helpers/alloc.lua:7-33.
local M = {}

---@param fn fun(i: integer)
---@param iterations integer
---@return number bytes
function M.bytes(fn, iterations)
    for i = 1, 200 do -- warm-up: let any lazy one-time allocation happen first
        fn(i)
    end
    local function loop(n)
        for i = 1, n do
            fn(i)
        end
    end
    collectgarbage("collect")
    collectgarbage("collect")
    collectgarbage("stop")
    -- A full collection shrinks Lua's own buffers (e.g. the stack), and the first call through the same path
    -- regrows them once: a cost per GC cycle, not per call. Absorb it through the measured path itself.
    local ok, err = pcall(loop, 1)
    local before = collectgarbage("count")
    if ok then
        ok, err = pcall(loop, iterations)
    end
    local after = collectgarbage("count")
    collectgarbage("restart")
    if not ok then
        error(err, 0)
    end
    return (after - before) * 1024
end

return M
