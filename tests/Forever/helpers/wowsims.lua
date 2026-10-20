-- tests/Forever/helpers/wowsims.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 3):
-- a class world's content (tests/Forever/helpers/<class>_world.lua) as a wowsims replay's and as a leveling
-- bracket's, and the two gates. `content`: the build's talents from the log header (cut to a level's points, the
-- dominant tree first), ranks above the level unknown (learn_<class>.lua, the DB2's), the abilities the world's kit
-- lacks, requirement overrides; `gate`: the replay gate (decision-point on-GCD agreement >= a floor, the engine's
-- health); `live`: the leveling gate (the pack driving the loop's own world never idles `n` GCDs while a known on-GCD
-- ability is usable, no error). Data: wowsims/forever (MIT, https://github.com/wowsims/forever).
local assert = require("luassert")
local loop = require("Game.harness.loop")
local replay = require("Game.harness.replay")
local pack_gate = require("Forever.helpers.pack_gate")

local M = {}

M.DIR = "tests/Forever/wowsims/"

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

--- The checked-in log of spec `spec`.
function M.log(spec)
    return slurp(M.DIR .. spec .. ".log")
end

--- The log header of spec `spec` (replay.parse's).
function M.header(spec)
    return replay.parse(M.log(spec)).header
end

-- wowsims's Race enum names whose client token (UnitRace's second return) is not the name without "Race".
M.RACE = { RaceUndead = "Scourge" }

--- The client race token of spec `spec`'s character (its checked-in request's `race`, e.g. "RaceOrc" -> "Orc").
function M.race(spec)
    local req = require("dkjson").decode(slurp(M.DIR .. spec .. ".json"))
    local race = req.raid.parties[1].players[1].race
    return M.RACE[race] or (race:gsub("^Race", ""))
end

--- The creature type of spec `spec`'s target (its checked-in request's first target's `mobType`, e.g.
--- "MobTypeUndead" -> "undead": `target.creature_type`'s key; "MobTypeUnknown" -> "unknown").
function M.creatureType(spec)
    local req = require("dkjson").decode(slurp(M.DIR .. spec .. ".json"))
    local t = req.encounter and req.encounter.targets and req.encounter.targets[1]
    return t and t.mobType and t.mobType:gsub("^MobType", ""):lower() or nil
end

--- Our yards from the target at the start in spec `spec`'s checked-in request (`distanceFromTarget`; wowsims's 0 when
--- unset).
function M.distance(spec)
    local req = require("dkjson").decode(slurp(M.DIR .. spec .. ".json"))
    return req.raid.parties[1].players[1].distanceFromTarget or 0
end

--- The learn levels of class `token` ({ [spellID] = level }).
function M.learn(token)
    return dofile(M.DIR .. "learn_" .. token:lower() .. ".lua")
end

local sets = {}
local function abilities(token) -- the class's ability set (every race's racials: engine.abilitySet), once a class
    if not sets[token] then
        sets[token] = require("Forever.helpers.engine").abilitySet(token).abilities
    end
    return sets[token]
end
local function racials(token, race) -- the keys of race `race`'s abilities for class `token`, sorted
    local out = {}
    for key, r in pairs(require("Forever.helpers.engine").abilitySet(token, race).racial) do
        if r == race then
            out[#out + 1] = key
        end
    end
    table.sort(out)
    return out
end
local function rankIDs(token, key)
    local a = assert(abilities(token)[key], "no ability " .. key)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
        out[#out + 1] = id
    end
    return out
end

--- Content `base` (a class world's: character, usable, resolve, uptime, gain, WORLD, OBSERVE) as pack `o.pack`'s at
--- `o.level` [60]. `o.talents` ({ { id, rank, tree } }: the build's; default the world's) are cut to the level's points
--- (one a level from 10), the dominant tree first, each talent's spell known; `o.learn` ({ [spellID] = level }) drops
--- ranks above the level (an ID it lacks counts as level 1); `o.kit` adds abilities the world's kit lacks (usable on
--- cost); `o.requires` ({ [key] = fn(W, e) -> ok, why }) replaces an ability's requirement in the usability answers
--- (it then owns the stance check too); `o.race` (a race token: `M.race(spec)`) boots the character as that race, its
--- racials known from their learn level (like `o.kit`'s). The world's mob is the character's level.
function M.content(base, o)
    local level = o.level or 60
    if o.race then
        local kit = {}
        for _, key in ipairs(o.kit or {}) do
            kit[#kit + 1] = key
        end
        for _, key in ipairs(racials(base.character().class, o.race)) do
            kit[#kit + 1] = key
        end
        o = setmetatable({ kit = kit }, { __index = o })
    end
    local C = setmetatable({ PACK = o.pack or base.PACK }, { __index = base })
    C.WORLD = setmetatable({ level = level }, { __index = base.WORLD })
    local learn = o.learn or {}
    local function learned(id)
        return type(id) ~= "number" or (learn[id] or 1) <= level
    end
    function C.character()
        local c = {}
        for k, v in pairs(base.character()) do
            c[k] = v
        end
        c.level, c.race = level, o.race or c.race
        local known = {}
        for _, id in ipairs(c.known) do
            if learned(id) then
                known[#known + 1] = id
            end
        end
        for _, key in ipairs(o.kit or {}) do
            for _, id in ipairs(rankIDs(c.class, key)) do
                if learned(id) then
                    known[#known + 1] = id
                end
            end
        end
        if o.talents then
            local points, per = math.max(0, level - 9), {}
            for _, t in ipairs(o.talents) do
                per[t[3]] = (per[t[3]] or 0) + t[2]
            end
            local dom, most = 1, -1
            for tree, n in pairs(per) do
                if n > most or (n == most and tree < dom) then
                    dom, most = tree, n
                end
            end
            local order = {}
            for _, t in ipairs(o.talents) do
                if t[3] == dom then
                    order[#order + 1] = t
                end
            end
            for _, t in ipairs(o.talents) do
                if t[3] ~= dom then
                    order[#order + 1] = t
                end
            end
            local talents = {}
            for _, t in ipairs(order) do
                local r = math.min(t[2], points)
                if r <= 0 then
                    break
                end
                talents[t[1]], points = r, points - r
                known[#known + 1] = t[1]
            end
            c.talents = talents
        end
        c.known = known
        return c
    end
    function C.usable(H)
        local token = base.character().class
        local over, out, seen = {}, {}, {}
        for key in pairs(o.requires or {}) do
            for _, id in ipairs(rankIDs(token, key)) do
                over[id] = key
            end
        end
        for _, row in ipairs(base.usable(H)) do
            if not over[row[1]] then
                out[#out + 1], seen[row[1]] = row, true
            end
        end
        local function answer(key, req)
            local cost = H.Hekili.State.action[key].cost or 0
            return function(W, e, power)
                local ok = not req or req(W, e)
                return ok and power >= cost, ok and power < cost
            end
        end
        for key, req in pairs(o.requires or {}) do
            for _, id in ipairs(rankIDs(token, key)) do
                out[#out + 1] = { id, answer(key, req) }
            end
        end
        for _, key in ipairs(o.kit or {}) do
            if not (o.requires and o.requires[key]) then
                for _, id in ipairs(rankIDs(token, key)) do
                    if not seen[id] then
                        out[#out + 1] = { id, answer(key) }
                    end
                end
            end
        end
        table.sort(out, function(x, y)
            return x[1] < y[1]
        end)
        return out
    end
    return C
end

--- The replay gate of content `C` on spec `spec`'s log: prints "<label> wowsims: <line>", asserts the engine's health
--- (pack_gate.health) and decisions on-GCD >= `floor`. `o`: replay.new's knobs over the character's forms, the
--- request's target creature type, its distance (M.distance), the content's shared category cooldowns (C.SHARED) and
--- the content WORLD's regen and fsr. Returns the
--- summary and the line.
function M.gate(label, C, spec, floor, o)
    local L = loop.new(C)
    local ro = setmetatable({
        forms = C.character().forms,
        creatureType = M.creatureType(spec),
        distance = M.distance(spec),
        shared = C.SHARED,
    }, { __index = o or {} })
    local R = replay.new(M.log(spec), L.oracle, ro)
    local m = loop.replay(L, R)
    local r, line = loop.summary(m), loop.line(m)
    print("\n" .. label .. " wowsims: " .. line)
    pack_gate.health(m, r, line)
    assert.is_true(r.decisions >= floor, line)
    return r, line
end

--- The leveling gate of content `C` (its pack drives the loop's own world at C's level, `fights` [1] fights of 120 s,
--- one instance): prints "<label> live L<level>: ..." and asserts no error, raise or unlisted read, at least one press,
--- and never idle longer than `limit` seconds [6: four GCDs] in a row with a known on-GCD ability the world would
--- accept. Idle: in combat, our GCD free, no cast in progress, no press this tick. Returns the worst idle and the line.
function M.live(label, C, limit, fights)
    limit = limit or 6
    local L = loop.new(C)
    local c = C.character()
    local known = {}
    for _, id in ipairs(c.known) do
        known[id] = true
    end
    local abilities = L.oracle.Hekili.Class.abilities
    local worst, presses, errors = 0, 0, 0
    for seed = 1, fights or 1 do
        local streak, last = 0, 0
        local run = loop.run(L, seed, {
            duration = 120,
            on = function(run, _, t)
                local us = run.us
                local pressed = run.presses > last
                last = run.presses
                local idle = t >= loop.PULL and not pressed and us.gcdUntil <= t and t >= (us.castUntil or 0)
                local usable = false
                if idle then
                    for _, row in ipairs(L.answers) do
                        local a = known[row[1]] and abilities[row[1]]
                        if a and a.gcd ~= "off" and row[2](run.W, us, us.power) then
                            usable = true
                            break
                        end
                    end
                end
                streak = (idle and usable) and streak + 1 or 0
                worst = math.max(worst, streak)
            end,
        }, { { H = L.us } })
        presses = presses + run.presses
        errors = errors + run.errors + run.raises + #run.misses
    end
    local seconds = worst * loop.TICK
    local line = ("worst idle %.1f s with a usable on-GCD ability (limit %.1f), presses %d, errors %d"):format(
        seconds,
        limit,
        presses,
        errors
    )
    print("\n" .. label .. " live L" .. c.level .. ": " .. line)
    assert.are.equal(0, errors, line)
    assert.is_true(presses > 0, line)
    assert.is_true(seconds <= limit + 1e-9, line)
    return seconds, line
end

return M
