-- tests/Virtual/harness/rng.lua (harness design §3.1): a seeded generator that gives the same stream on every machine.
-- Lua 5.1's math.random is the C library's (it differs between machines), and Lua 5.1 has no bit operators for a
-- xorshift: this is the Park-Miller minimal standard generator (multiplier 48271, modulus 2^31 - 1), exact in doubles.
local M = {}

--- A generator seeded with `seed` (any integer). `next()` in [0, 1), `int(a, b)` in [a, b], `chance(p)`,
--- `normal(mu, sd)` (Box-Muller), `pick(list)`.
function M.new(seed)
    local s = (math.floor(seed or 1) % 2147483646) + 1
    local r = {}
    function r.next()
        s = s * 48271 % 2147483647
        return (s - 1) / 2147483646
    end
    function r.int(a, b)
        return a + math.floor(r.next() * (b - a + 1))
    end
    function r.chance(p)
        return r.next() < p
    end
    function r.normal(mu, sd)
        local u = 1 - r.next()
        return mu + sd * math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * r.next())
    end
    function r.pick(list)
        return list[r.int(1, #list)]
    end
    for _ = 1, 10 do -- the first draws of nearby seeds are close: discard them
        r.next()
    end
    return r
end

return M
