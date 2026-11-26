-- lj-speed spike: per-call cost of the clocks the harness can use (run with .lj/bin/lua, JIT on and off)
local ffi = require("ffi")
ffi.cdef("typedef struct { long tv_sec; long tv_nsec; } ljs_timespec; int clock_gettime(int, ljs_timespec *);")
local osx = ffi.os == "OSX"
local C, ts = ffi.C, ffi.new("ljs_timespec")
local function gt(id)
    return function()
        C.clock_gettime(id, ts)
        return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
    end
end
local mono = gt(osx and 6 or 1)
local clocks = {
    { "os.clock", os.clock },
    { "ffi MONOTONIC", mono },
    { "ffi PROCESS_CPUTIME", gt(osx and 12 or 2) },
    { "os.time", os.time },
}
local N = 1000000
for _, c in ipairs(clocks) do
    local f, s = c[2], 0
    local t0 = mono()
    for _ = 1, N do
        s = s + f()
    end
    print(string.format("%-22s %7.3f us/call (jit %s)", c[1], (mono() - t0) / N * 1e6, tostring(jit.status())), s > 0)
end
