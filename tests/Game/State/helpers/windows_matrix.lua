-- tests/Game/State/helpers/windows_matrix.lua (windows design v6 §13): the test kit and the table-driven runner of the
-- windows matrix, belief-only (Phase 1). A case declares APL windows by plain name (keys `kit:<name>#<display>`), an
-- optional Lua window `luaw` whose evaluator reads M.flags.luaw, and a timeline of ticks. Each tick: flags, then the
-- scripted events just before it (combat, target swap, casts), an optional edit (a new def.aplWindows generation),
-- the Drain at t, then the asserted belief columns (per key: up, step, expiresAt; openedAt, refreshes when a case
-- names them), then the operations this tick's pass sends (VS.WindowOp), replayed at the next Drain. Every field
-- of every key is compared on every tick (an unlisted field must be unchanged), so a surprise fails; the first
-- differing tick is the error, as a row diff. The replay invariant runs on every tick that follows sent operations
-- with no scripted event in between: the belief equals the copy those operations describe. Phase 2 replaces the
-- scripted `ops` with the engine's and asserts them as a column.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

local M = {}

M.PACK = "kit"
M.OP = { OPEN = 1, CLOSE = 2, STEP = 3 }
-- the kit (§13): on-GCD filler, nuke, dot; off-GCD burst, stance; a cooldown the Cooldowns display owns; one whose
-- real cast closes the Primary copy of APL window `x` (W17)
M.IDS = { filler = 4001, nuke = 4002, burst = 4003, stance = 4004, dot = 4005, classcd = 4006, closer = 4007 }
M.OFF = { burst = true, stance = true }
M.flags = { luaw = false }
M.CLOSED = { up = false, step = 0, expiresAt = 0, openedAt = 0, refreshes = 0 }

--- `name` or `name#Display` (Primary by default) -> the APL key; `luaw` and any other Lua name as they are.
function M.key(case, name)
    if case.luaw and name == "luaw" then
        return name
    end
    local plain, display = name:match("^([^#]+)#?(.*)$")
    return M.PACK .. ":" .. plain .. "#" .. (display ~= "" and display or "Primary")
end

local GLOBALS = { "GetTime", "UnitGUID", "CreateFrame", "issecretvalue", "debugprofilestop" }

--- A fresh belief with the kit, `case.luaw` registered and `case.apl` applied as generation 1. Returns the env.
function M.setup(case)
    local api, ctl = fake.new()
    ctl.now = 1
    local saved = {}
    for _, k in ipairs(GLOBALS) do
        saved[k] = rawget(_G, k) or false
    end
    _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue =
        api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
    _G.debugprofilestop = function()
        return 0
    end
    local ns = load.module()
    local VS, I = ns.VirtualState, ns.VirtualStateInternal
    local h = fs.new(9)
    fs.clock = api.GetTime
    ns.spendResources = fs.spend
    ns.ResourceRegenerates = function()
        return false
    end
    load.schema(ns, h)
    for key, id in pairs(M.IDS) do
        local t = { id = id, key = key, cast = 0, cooldown = 0, charges = 1, recharge = 0, funcs = {} }
        t.gcd = M.OFF[key] and "off" or nil
        if key == "closer" then
            t.funcs.now = function()
                closeWindow(M.PACK .. ":x#Primary") -- luacheck: ignore 113 (the now context's verb)
            end
        end
        h.Class.abilities[key], h.Class.abilities[id] = t, t
    end
    M.flags.luaw = false
    if case.luaw then
        local d = { key = "luaw", on_deviation = "stay" }
        for k, v in pairs(case.luaw) do
            d[k] = v
        end
        d.duration = d.duration or 30
        d.evaluator = function()
            return M.flags.luaw
        end
        h.Class.windows = { luaw = d }
    end
    VS.Start(api)
    ns.BuildTracked()
    ctl.Tick(1)
    I.ObsLog.Clear(I.log)
    local env = { api = api, ctl = ctl, ns = ns, VS = VS, I = I, saved = saved, case = case, gen = 0, guid = 0 }
    M.edit(env, case.apl or {}, case.displays, case.cap)
    ctl.now = 1.5
    ctl.Tick(1.5)
    VS.Drain(1.5)
    return env
end

function M.teardown(env)
    for k, v in pairs(env.saved) do
        _G[k] = v or nil
    end
    fs.clock = nil
end

--- The build's APL records for `apl` (name -> declaration; `steps` as kit keys) in each of `displays` (Primary), as
--- the compiler writes them: steps as ability indexes, a new generation, the buffer's bound. `duration` defaults to
--- "combat" (`false` writes none). `env.recs`: the records in effect by plain name, the oracle's declarations.
function M.edit(env, apl, displays, cap)
    local I = env.I
    local index = {}
    for a = 1, I.ab.n do
        index[I.ab.key[a]] = a
    end
    local list, recs = {}, {}
    local names = {}
    for name in pairs(apl) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, d in ipairs(displays or { "Primary" }) do
        for _, name in ipairs(names) do
            local rec = { key = M.PACK .. ":" .. name .. "#" .. d, duration = "combat" }
            for k, v in pairs(apl[name]) do
                rec[k] = v
            end
            if rec.steps then
                local steps = {}
                for i, s in ipairs(rec.steps) do
                    steps[i] = assert(index[s], s)
                end
                rec.steps = steps
            end
            list[#list + 1] = rec
            recs[name] = recs[name] or rec
        end
    end
    env.recs = recs
    env.gen = env.gen + 1
    I.def.aplWindows, I.def.aplGen, I.def.aplOpCap = list, env.gen, cap or 16
end

-- The belief's columns for `key`.
local function read(env, key)
    local up, openedAt, expiresAt, refreshes, step = env.ns.Facade.Window(key)
    return { up = up, step = step, expiresAt = expiresAt, openedAt = openedAt, refreshes = refreshes }
end

local FIELDS = { "up", "step", "expiresAt", "openedAt", "refreshes" }

local function same(a, b)
    return a == b or type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-9
end

--- (L1165 forecast == apply) The oracle: operation `code` (M.OP) with `arg` applied at T, as the belief applies it, to
--- state `s` (the FIELDS) of a row whose record is `decl` (read as the belief reads it: `duration` seconds or "combat",
--- else none; `refresh == true`). OPEN with no positive duration changes nothing (the belief drops it); else it opens
--- a closed or run-out row for the duration (capped by max_duration); on an up row it restarts the timer only when
--- `refresh` and `max_refresh` / `max_duration` leave room (refreshes + 1), else nothing.
--- CLOSE closes; STEP sets the step on an up stepped row (1..steps + 1). Pure: Phase 2 asserts the core's forecast
--- against it. A strict row's step deadline is not a Facade.Window field: the oracle does not model it.
function M.apply(s, code, arg, decl, T)
    local d = decl.duration == "combat" and math.huge or type(decl.duration) == "number" and decl.duration or 0
    local maxDur = type(decl.max_duration) == "number" and decl.max_duration or 0
    local maxRef = type(decl.max_refresh) == "number" and decl.max_refresh or -1
    local nSteps = type(decl.steps) == "table" and #decl.steps or 0
    if code == M.OP.OPEN then
        if not (d > 0) then
            return
        end
        if s.up and s.expiresAt <= T then
            for _, f in ipairs(FIELDS) do
                s[f] = M.CLOSED[f]
            end
        end
        if not s.up then
            s.up, s.openedAt, s.refreshes = true, T, 0
            s.expiresAt = math.min(T + d, maxDur > 0 and T + maxDur or math.huge)
            s.step = nSteps > 0 and 1 or 0
        else
            local cap = maxDur > 0 and s.openedAt + maxDur or math.huge
            if decl.refresh == true and (maxRef < 0 or s.refreshes < maxRef) and s.expiresAt < cap then
                s.expiresAt, s.refreshes = math.min(T + d, cap), s.refreshes + 1
            end
        end
    elseif code == M.OP.CLOSE then
        for _, f in ipairs(FIELDS) do
            s[f] = M.CLOSED[f]
        end
    elseif code == M.OP.STEP and s.up and nSteps > 0 and arg >= 1 and arg <= nSteps + 1 and arg % 1 == 0 then
        s.step = arg
    end
end

-- The copy the scripted operations describe (§13 replay invariant): `ops` applied by the oracle onto `seed` at T,
-- then expiry at t.
local function model(seed, ops, T, t, decl)
    local s = {}
    for _, f in ipairs(FIELDS) do
        s[f] = seed[f]
    end
    for _, o in ipairs(ops) do
        M.apply(s, M.OP[o[2]] or o[2], o[3], decl or {}, T)
    end
    if s.up and s.expiresAt <= t then
        for _, f in ipairs(FIELDS) do
            s[f] = M.CLOSED[f]
        end
    end
    return s
end

-- The scripted events before tick `k` at t (shifted by `dt` on the allocation run).
local function events(env, k, t)
    local ctl, case = env.ctl, env.case
    if k.flag then
        for name, v in pairs(k.flag) do
            M.flags[name] = v
        end
    end
    ctl.now = t - 0.05
    if k.combat == "start" then
        ctl.Fire("PLAYER_REGEN_DISABLED")
    elseif k.combat == "end" then
        ctl.Fire("PLAYER_REGEN_ENABLED")
    end
    if k.swap then
        env.guid = env.guid + 1
        ctl.guid.target = k.swap == "map" and fake.SECRET or ("Creature-" .. env.guid)
        ctl.Fire("PLAYER_TARGET_CHANGED")
    end
    local casts = type(k.cast) == "table" and k.cast or { k.cast }
    for i, c in ipairs(casts) do
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. i, M.IDS[c])
    end
    if k.edit then
        M.edit(env, k.edit, case.displays, case.cap)
    end
end

local function send(env, ops)
    for _, o in ipairs(ops or {}) do
        env.VS.WindowOp(M.key(env.case, o[1]), M.OP[o[2]] or o[2], o[3])
    end
end

--- Plays `case.timeline`; raises at the first differing tick with a row diff.
function M.run(case)
    local env = M.setup(case)
    local ok, err = pcall(function()
        local want, keys, names = {}, {}, case.keys
        if not names then -- every declared window's Primary key, and the Lua window
            names = {}
            for name in pairs(case.apl or {}) do
                names[#names + 1] = name
            end
            table.sort(names)
            if case.luaw then
                names[#names + 1] = "luaw"
            end
        end
        for _, name in ipairs(names) do
            keys[#keys + 1] = name
            want[name] = {}
            for _, f in ipairs(FIELDS) do
                want[name][f] = M.CLOSED[f]
            end
        end
        local sent, sentT, seed = nil, 0, {}
        for i, k in ipairs(case.timeline) do
            events(env, k, k.t)
            env.ctl.now = k.t
            env.ctl.Tick(k.t)
            env.VS.Drain(k.t)
            local rows = {}
            for name, fields in pairs(k.expect or {}) do
                for f, v in pairs(fields) do
                    want[name][f] = v
                end
            end
            for _, name in ipairs(keys) do
                local got = read(env, M.key(case, name))
                for _, f in ipairs(FIELDS) do
                    if not same(got[f], want[name][f]) then
                        rows[#rows + 1] =
                            string.format("  %s.%s want %s got %s", name, f, tostring(want[name][f]), tostring(got[f]))
                    end
                end
                -- the replay invariant: no event between the sending pass and this Drain
                local quiet = not (k.cast or k.swap or k.combat or k.edit or k.diff)
                if sent and quiet and sent[name] then
                    local m = model(seed[name], sent[name], sentT, k.t, env.recs[name:match("^[^#]+")])
                    for _, f in ipairs(FIELDS) do
                        if not same(got[f], m[f]) then
                            rows[#rows + 1] = string.format(
                                "  replay invariant %s.%s copy %s belief %s",
                                name,
                                f,
                                tostring(m[f]),
                                tostring(got[f])
                            )
                        end
                    end
                end
                seed[name] = got
            end
            if k.counts then
                local Q = env.I.winOps
                for f, v in pairs(k.counts) do
                    if Q[f] ~= v then
                        rows[#rows + 1] = string.format("  counts.%s want %s got %s", f, tostring(v), tostring(Q[f]))
                    end
                end
            end
            if #rows > 0 then
                error(string.format("%s tick %d (t=%.2f):\n%s", case.id, i, k.t, table.concat(rows, "\n")), 0)
            end
            if k.castAfter then -- heard while this tick's passes still run: logged before their operations
                env.ctl.now = k.t + 0.01
                env.ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-after", M.IDS[k.castAfter])
            end
            sent, sentT = nil, k.t
            if k.ops then
                sent = {}
                for _, o in ipairs(k.ops) do
                    sent[o[1]] = sent[o[1]] or {}
                    table.insert(sent[o[1]], o)
                end
            end
            send(env, k.ops)
        end
        -- the allocation run (§13): the same timeline again, 1000 s later; Drain and WindowOp allocate nothing (the
        -- edit ticks' rebuild exempt; the first Drain absorbs a stack regrowth)
        local dt, bytes = 1000, 0
        local pre = {} -- the keys built before the measured calls
        for i, k in ipairs(case.timeline) do
            pre[i] = {}
            for j, o in ipairs(k.ops or {}) do
                pre[i][j] = { M.key(case, o[1]), M.OP[o[2]] or o[2], o[3] }
            end
        end
        collectgarbage("collect")
        collectgarbage("stop")
        for i, k in ipairs(case.timeline) do
            local t = k.t + dt
            events(env, k, t)
            env.ctl.now = t
            env.ctl.Tick(t)
            local ops = pre[i]
            local before = collectgarbage("count")
            env.VS.Drain(t)
            if k.castAfter then
                if i > 1 and not k.edit then
                    bytes = bytes + (collectgarbage("count") - before) * 1024
                end
                env.ctl.now = t + 0.01
                env.ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-after", M.IDS[k.castAfter])
                before = collectgarbage("count")
            end
            for j = 1, #ops do
                env.VS.WindowOp(ops[j][1], ops[j][2], ops[j][3])
            end
            if i > 1 and not k.edit then
                bytes = bytes + (collectgarbage("count") - before) * 1024
            end
        end
        collectgarbage("restart")
        if bytes > 0 then
            error(string.format("%s: Drain and WindowOp allocated %d bytes on the second run", case.id, bytes), 0)
        end
    end)
    collectgarbage("restart")
    M.teardown(env)
    if not ok then
        error(err, 0)
    end
end

return M
