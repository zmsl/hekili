-- Game/State/Families/Expect.lua
-- Each ability's declared outcome (unit-registry spec §5): `expects`, a plain string from a fixed set, each mapped to
-- one engine kind whose matching and closing rule lives once in Game/Events/Kinds.lua and Melee.lua; the fields that
-- kind reads (`velocity`, `school` by name), compiled at each build into per-ability
-- arrays the ticket pool reads by ability index. A ticking kind's period and count are its aura's: the aura resolved as
-- the simulation resolves it (`cycle`, else `aura`, else the ability's key: Engine/Sim/State.lua:676), its declared
-- `tick_time` and floor(`duration` / `tick_time`), read at the commit (X.Tick) in Hekili's own state when the pack
-- wrote a function. Declared: the pack's own value, before the haste wrapper RegisterAura installs (Engine/Schema/
-- Spec.lua keeps it as `base_tick_time`), as Families/Casts.lua reads `declaredSpend`. A declared instant or travel
-- ability also ticks when that aura is upstream's debuff dot (`dot = "debuff"`, the field mt_dot reads). An absent
-- `expects` takes today's behaviour: "strike" with `onNextSwing`, "instant" with `startsCombat`, else "none", with
-- school ANY unless the ability names one (CHANNEL is opt-in). A malformed declaration is counted once in
-- I.nowErrors (Snapshot's error line) and takes the default. Pure: no client read.

local _, ns = ...
local I = ns.VirtualStateInternal
local A = I.ab

local X = {}
I.Expect = X
X.NONE, X.FRAME, X.FLIGHT, X.MELEE, X.STRIKE, X.TICKS, X.CHANNEL, X.UNMAPPED = 0, 1, 2, 3, 4, 5, 6, 7
X.ANY = -1 -- school: any WOUND or avoid pays, never lost (a default type on an ability with no `school`)
X.KIND = { none = 0, instant = 1, travel = 2, melee = 3, strike = 4, ticks = 5, channel = 6 }

A.expKind, A.expDeclared, A.velocity, A.school, A.tickAura, A.ticking = {}, {}, {}, {}, {}, {}

-- Aura `au`'s declared field: `base` (where RegisterAura moves a wrapped one), else `k`, each on the aura or in its
-- `funcs`; rawget only, so neither the haste wrapper nor the aura's onLoad (a client read) runs.
local function declared(au, base, k)
    local f = rawget(au, "funcs")
    f = type(f) == "table" and f or nil
    local v = rawget(au, base)
    if v == nil and f then
        v = rawget(f, base)
    end
    if v == nil then
        v = rawget(au, k)
    end
    if v == nil and f then
        v = rawget(f, k)
    end
    return v
end

-- The aura ability `obj` (key `key`) applies, resolved as the simulation does, when it declares a tick_time (a number
-- above 0 or a function); else nil.
local function tickAura(obj, key, byKey)
    local name = rawget(obj, "cycle") or rawget(obj, "aura") or key
    local au = type(name) == "string" and byKey[name] or nil
    local tt = au and declared(au, "base_tick_time", "tick_time")
    if type(tt) == "function" or (type(tt) == "number" and tt > 0) then
        return au
    end
end

-- A declared number now: the pack's function called as the simulation calls it (bound to Hekili's `state` by
-- RegisterAura; a raising one answers nil).
local function num(v)
    if type(v) == "function" then
        local ok, r = pcall(v)
        v = ok and r or nil
    end
    return type(v) == "number" and v > 0 and v or nil
end

--- Ticking ability a's period and tick count now (its aura's declared tick_time and floor(duration / tick_time));
--- 0, 0 when it does not tick or the aura cannot answer. Called at a commit; allocates nothing of its own.
---@param a integer
---@return number period
---@return integer count
function X.Tick(a)
    local au = A.tickAura[a]
    if not au then
        return 0, 0
    end
    local tt, d = num(declared(au, "base_tick_time", "tick_time")), num(declared(au, "duration", "duration"))
    if not (tt and d) then
        return 0, 0
    end
    return tt, math.floor(d / tt + 1e-6)
end

local function default(obj)
    if obj.onNextSwing then
        return X.STRIKE
    elseif obj.startsCombat then
        return X.FRAME
    end
    return X.NONE
end

-- Why `obj`'s declaration `e` of kind `k` (nil: an unknown string) with school mask `s` (nil: none or unknown) and a
-- ticking aura `au` (nil: none) is malformed, or nil (spec §5.3).
local function malformed(obj, e, k, s, au)
    local v = obj.velocity
    if k == nil then
        return "unknown expects " .. tostring(e)
    elseif k == X.MELEE then
        return "expects melee is the engine's own"
    elseif v ~= nil and type(v) ~= "number" then
        return "velocity is not a number"
    elseif obj.school ~= nil and not s then
        return "unknown school " .. tostring(obj.school)
    elseif k == X.FLIGHT and not v then
        return "travel needs velocity"
    elseif k == X.TICKS and not (au and rawget(au, "dot") == "debuff") then
        return 'ticks needs an aura with tick_time and dot = "debuff"'
    elseif k == X.CHANNEL and not au then
        return "channel needs an aura with tick_time"
    elseif k == X.STRIKE and not obj.onNextSwing then
        return "strike needs onNextSwing"
    end
end
X.Malformed = malformed -- the pack check (tests/Forever/expects_spec.lua) runs the build's own rule

I.OnBuild(function(def)
    local SCHOOL = ns.SCHOOL
    local byKey = {} -- once a build
    for j = 1, #(def.auras or {}) do
        local au = def.auras[j]
        if type(au) == "table" and au.key then
            byKey[au.key] = au
        end
    end
    for a = 1, A.n do
        local obj = def.abilities[a]
        local e = rawget(obj, "expects")
        local s = type(obj.school) == "string" and SCHOOL[obj.school] or nil
        local au = tickAura(obj, A.key[a], byKey)
        local kind, school, isDeclared = default(obj), X.ANY, false
        A.velocity[a] = 0
        if e == nil then
            if s then
                school = s -- a default type whose ability names its school checks it
            elseif obj.school ~= nil then
                I.nowErrors = I.nowErrors + 1
                I.nowError = "expects: " .. tostring(A.key[a]) .. " unknown school " .. tostring(obj.school)
            end
        else
            local k = type(e) == "string" and X.KIND[e] or nil
            local why = malformed(obj, e, k, s, au)
            if why then
                I.nowErrors, I.nowError = I.nowErrors + 1, "expects: " .. tostring(A.key[a]) .. " " .. why
            else
                kind, school, isDeclared = k, s or 0, true
                A.velocity[a] = obj.velocity or 0
            end
        end
        local direct = isDeclared and (kind == X.FRAME or kind == X.FLIGHT) and au and rawget(au, "dot") == "debuff"
        local ticks = kind == X.TICKS or kind == X.CHANNEL or direct == true
        A.expKind[a], A.school[a], A.expDeclared[a] = kind, school, isDeclared
        A.tickAura[a], A.ticking[a] = ticks and au or false, ticks
    end
end)
