-- tools/ttd_lab/rng.lua: a seeded Park-Miller generator (exact in doubles), so every table reproduces on any Lua 5.1.
local R = {}
R.__index = R

function R.new(seed)
    return setmetatable({ s = (math.floor(seed) % 2147483646) + 1 }, R)
end

--- Uniform in (0, 1).
function R:next()
    self.s = (self.s * 16807) % 2147483647
    return self.s / 2147483647
end

function R:uni(a, b)
    return a + (b - a) * self:next()
end

--- Integer in [a, b].
function R:int(a, b)
    return math.min(b, a + math.floor((b - a + 1) * self:next()))
end

return R
