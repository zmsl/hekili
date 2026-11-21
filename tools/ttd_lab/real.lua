-- tools/ttd_lab/real.lua: real damage traces from the checked-in wowsims logs (tests/Forever/wowsims/*.log, 180 s, one
-- player and its pets on Target 1). A trace killed at `death` seconds: the mob's health is the damage the player
-- deals up to `death`, so the rotation's own burst, DoT ramp and execute shape are real; the fight is solo.
local R = {}

R.DIR = "tests/Forever/wowsims/"
R.DEATHS = { 20, 60, 180 }

--- Every log name, sorted (no directory walk in stock Lua: `ls`).
function R.logs()
    local names = {}
    local p = assert(io.popen("ls " .. R.DIR .. " 2>/dev/null"))
    for line in p:lines() do
        local name = line:match("^(.+)%.log$")
        if name then
            names[#names + 1] = name
        end
    end
    p:close()
    table.sort(names)
    return names
end

--- The hits on Target 1 from t >= 0: two arrays, times and amounts.
function R.hits(name)
    local ts, as = {}, {}
    for line in io.lines(R.DIR .. name .. ".log") do
        local t, amt = line:match("^%[([%d.]+)%] %[[^%]]+%] %[Target 1%] .- for ([%d.]+) damage")
        if t and tonumber(amt) > 0 then
            ts[#ts + 1], as[#as + 1] = tonumber(t), tonumber(amt)
        end
    end
    return ts, as
end

--- A fight in scenarios.lua's shape from a log's hits, the mob dying at the first hit at or after `death`.
function R.fight(ts, as, death)
    local cum = 0
    for i = 1, #ts do
        if ts[i] > death then
            break
        end
        cum = cum + as[i]
    end
    local mob = { max = cum, ht = { 0 }, hv = { 100 } }
    local own = { t = {}, a = {} }
    local done = 0
    for i = 1, #ts do
        done = done + as[i]
        own.t[#own.t + 1], own.a[#own.a + 1] = ts[i], as[i]
        local p = 100 * (1 - done / cum)
        mob.ht[#mob.ht + 1], mob.hv[#mob.hv + 1] = ts[i], math.max(0, p)
        if p <= 1e-9 then
            mob.death = ts[i]
            break
        end
    end
    return { class = "real", mobs = { mob }, plan = { { t = 0, mob = 1 } }, own = own, endT = mob.death }
end

return R
