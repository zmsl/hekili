-- Game/State/Families/Windows.lua
-- Rotation windows (re-pin design §3a, decision 11): spans the client shows no aura for, owned by the belief. Each
-- window's evaluator (RegisterWindow, Engine/Schema/Spec.lua; `def.windows`) is bound into the `now` context
-- (Families/Now.lua) and runs once per Drain after the fold (I.RunWindows). Edges: false->true opens a closed window, or
-- with `refresh` restarts an open one (counted once per edge against `max_refresh`, bounded by `max_duration` from the
-- first open; the length is the declaration's seconds, none for "combat", or its `now_duration` run in the `now`
-- context at that open or refresh, a raise counted and a non-positive, secret or non-number answer opening nothing); a
-- condition held true does nothing; true->false closes only with `close_on_false`; a close acts only on
-- an open window; an open ends at its expiry and at combat end (the last evaluations kept, so a held condition needs a
-- new edge). A stepped window advances on our observed cast of its due step's ability (I.WindowCast, from the cast
-- fold); a later step's cast follows `on_deviation`; with `strict`, any other on-GCD cast ends it. The core reads it
-- only through Facade.Window (VS.Window). Everything preallocated at Build; nothing allocated per Drain or per cast.
-- APL rows (windows design v6 §5-§8, v6.1): `def.aplWindows`, one row per key after the Lua rows, with no evaluator.
-- The core's display passes send the author's operations by key (VS.WindowOp: OPEN, CLOSE, STEP); Drain replays them
-- first, stamped with the previous cut-off: OPEN by the row's declared refresh rule, CLOSE and STEP as writes. A plain
-- sequence (steps, not strict) parks past its last step (step = steps + 1) until a STEP or combat end; a strict one
-- closes after its last step and when its `step_timeout` (default 4 s, restarted at each advance) runs out.
-- `reset_on_target_change` (any row, Lua ones too): a target swap closes the row, and a Lua row also forgets its
-- evaluator's last value, so a still-true evaluator reopens it at step 1 in the same Drain. A new `def.aplGen`
-- rebuilds the APL rows and the buffer only, at the next Drain out of combat (in combat too while there is no APL row).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs
local A = I.ab

local STAY, SKIP, END = 1, 2, 3
local DEV = { stay = STAY, skip = SKIP, ["end"] = END }
local NONE = {} -- a hand-built def may carry no `windows`
local STEP_TIMEOUT = 4 -- a strict APL row's default step_timeout (ruling 24)

-- By window index: the declaration, then the state.
local W = {
    n = 0,
    byKey = {},
    key = {}, -- by window index: its name
    eval = {}, -- the evaluator bound to the `now` context, or false
    dur = {}, -- seconds (math.huge: "combat")
    durFn = {}, -- `now_duration` bound to the `now` context, or false
    refresh = {},
    maxDur = {}, -- 0: no cap
    maxRef = {}, -- -1: no cap
    cof = {}, -- close_on_false
    steps = {}, -- ability indexes, or false
    nSteps = {},
    lastAt = {}, -- by ability index: its last step position in the window (0: not in it)
    loop = {},
    dev = {},
    strict = {},
    up = {},
    openedAt = {},
    expiresAt = {},
    refreshes = {},
    step = {},
    last = {}, -- the last evaluation
    devAb = {}, -- the snapshot's last deviation: the cast's ability index (0 none), its time and the due step it met
    devAt = {},
    devDue = {},
    raised = {}, -- the evaluator raised: it reads false and is not run again (counted once, as I.Eval)
    nLua = 0, -- rows 1..nLua: the Lua windows (def.windows); nLua+1..n: the APL rows (def.aplWindows)
    gen = nil, -- the def.aplGen the APL rows were built from
    rtc = {}, -- reset_on_target_change
    park = {}, -- an APL plain sequence: past its last step it stays up at step nSteps + 1
    timeout = {}, -- a strict APL row's step_timeout (s); 0: none
    deadline = {}, -- when the due step's time runs out (math.huge: none)
}
I.win = W

-- The operations buffer (design §5): VS.WindowOp fills it between two Drains, the next Drain's head replays it. Sized
-- at the build by `def.aplOpCap` (the compiler's exact bound, §5.5); over it an operation is dropped and counted.
local OPEN, CLOSE, STEP = 1, 2, 3
local OPNAME = { "OPEN", "CLOSE", "STEP" }
local Q = { n = 0, cap = 0, key = {}, op = {}, arg = {}, applied = 0, refused = 0, dropped = 0, lastDrop = "" }
I.winOps = Q

local function close(w)
    W.up[w], W.openedAt[w], W.expiresAt[w], W.refreshes[w], W.step[w] = false, 0, 0, 0, 0
    W.deadline[w] = math.huge
end

-- Window w has run out at t: its expiry, or a strict APL row's step deadline.
local function lapsed(w, t)
    return W.expiresAt[w] <= t or W.deadline[w] <= t
end

-- A fresh open of w at t for d seconds (capped by max_duration): up, step 1 when stepped, the step deadline started.
local function fresh(w, t, d)
    local e, cap = t + d, W.maxDur[w] > 0 and t + W.maxDur[w] or math.huge
    W.up[w], W.openedAt[w], W.refreshes[w] = true, t, 0
    W.expiresAt[w] = e < cap and e or cap
    W.step[w] = W.nSteps[w] > 0 and 1 or 0
    W.deadline[w] = W.timeout[w] > 0 and t + W.timeout[w] or math.huge
end

-- Window w's length for an open at t: its seconds, or its `now_duration`'s plain positive answer (0: none).
local function length(w, t)
    local f = W.durFn[w]
    if not f then
        return W.dur[w]
    end
    local ok, v = I.Guard(f, t)
    if not ok then
        return 0
    end
    local api = I.api
    if api and api.issecretvalue(v) then
        return 0 -- secret: never compared
    end
    if type(v) ~= "number" or not (v > 0) then
        return 0
    end
    return v
end

-- The edge rules' open: a closed window opens at t; an open one restarts with `refresh` within its caps.
local function open(w, t)
    if W.up[w] and lapsed(w, t) then
        close(w) -- expired, not yet closed (expiry is applied after the fold): a fresh open, not a refresh
    end
    local isFresh = not W.up[w]
    if not isFresh and not (W.refresh[w] and (W.maxRef[w] < 0 or W.refreshes[w] < W.maxRef[w])) then
        return
    end
    local d = length(w, t)
    if d <= 0 then
        return
    end
    if isFresh then
        fresh(w, t, d)
        return
    end
    local e = t + d
    W.refreshes[w] = W.refreshes[w] + 1
    local cap = W.maxDur[w] > 0 and W.openedAt[w] + W.maxDur[w] or e
    W.expiresAt[w] = e < cap and e or cap
end

--- The `now` verbs (Families/Now.lua): open or close window `name` at t. Allocates nothing.
function I.WindowOpen(name, t)
    local w = W.byKey[name]
    if w then
        open(w, t)
    end
end
function I.WindowClose(name)
    local w = W.byKey[name]
    if w and W.up[w] then
        close(w)
    end
end

-- Past step s of window w at t: the next step, or after the last a close (step 1 with `loop`; a plain APL sequence
-- parks at nSteps + 1). A strict APL row's step deadline restarts.
local function advance(w, s, t)
    if s < W.nSteps[w] then
        W.step[w] = s + 1
    elseif W.loop[w] then
        W.step[w] = 1
    elseif W.park[w] then
        W.step[w] = W.nSteps[w] + 1
    else
        close(w)
        return
    end
    if W.timeout[w] > 0 then
        W.deadline[w] = t + W.timeout[w]
    end
end

--- Our cast of ability a (Families/Now.lua's cast fold, every own CastSuccess): each up stepped window's due step
--- advances; a later step's cast follows `on_deviation`; a strict window ends at any other on-GCD cast. One lookup read
--- per stepped window. Allocates nothing.
function I.WindowCast(a, t)
    for w = 1, W.n do
        if W.up[w] and lapsed(w, t) then
            close(w)
        end
        local steps = W.steps[w]
        if steps and W.up[w] then
            local due = W.step[w]
            if steps[due] == a then
                advance(w, due, t)
            else
                local later = 0
                if W.lastAt[w][a] > due then -- the first of its steps after the due one
                    for k = due + 1, W.nSteps[w] do
                        if later == 0 and steps[k] == a then
                            later = k
                        end
                    end
                end
                if later > 0 then
                    W.devAb[w], W.devAt[w], W.devDue[w] = a, t, due
                    local d = W.dev[w]
                    if d == SKIP then
                        advance(w, later, t)
                    elseif d == END then
                        close(w)
                    end
                elseif W.strict[w] and A.gcdKind[a] > 0 then
                    close(w)
                end
            end
        end
    end
end

--- Drain's windows step, after the fold (Sources/Sources.lua VS.Drain): the expiries at t, then each evaluator once at
--- t and its edge. Allocates nothing.
function I.RunWindows(t)
    for w = 1, W.n do
        if W.up[w] and lapsed(w, t) then
            close(w)
        end
        local f = W.eval[w]
        if f then
            local v, ok = I.NowEval(f, t, W.raised[w])
            W.raised[w] = not ok
            local was = W.last[w]
            W.last[w] = v
            if v and not was then
                open(w, t)
            elseif was and not v and W.cof[w] and W.up[w] then
                close(w)
            end
        end
    end
end

I.On(Obs.CombatEnd, function()
    for w = 1, W.n do
        close(w)
    end
end)

I.On(Obs.CombatStart, function()
    Q.applied, Q.refused, Q.dropped, Q.lastDrop = 0, 0, 0, "" -- the snapshot's counts are since combat start
end)

-- A target swap (a re-selection too; under Map by plate index, no GUID read) resets each row declared with it. Also
-- logged for a cleared target and by VS.Start / every Build (Sources/Target.lua): harmless, declare() closed every row.
I.On(Obs.TargetSwap, function()
    for w = 1, W.n do
        if W.rtc[w] then
            if W.up[w] then
                close(w)
            end
            W.last[w] = false -- a Lua row: a still-true evaluator is a new edge at this Drain's RunWindows
        end
    end
end)

-- One operation on APL row w at t (L1165): "applied", "refused" (an OPEN the refresh rule refuses, L1182) or
-- "dropped". OPEN: a closed or run-out row opens fresh for its declared duration (none: dropped); an open one restarts
-- its expiry only with `refresh`, below `max_refresh` and below openedAt + `max_duration`. CLOSE: down. STEP: the due
-- step `arg` (1..steps + 1) on an up stepped row, as a write. tests/Game/State/helpers/windows_matrix.lua M.apply is
-- its oracle.
local function write(w, op, arg, t)
    if op == OPEN then
        local d = W.dur[w]
        if not (d > 0) then
            return "dropped"
        end
        if W.up[w] and lapsed(w, t) then
            close(w)
        end
        if not W.up[w] then
            fresh(w, t, d)
            return "applied"
        end
        local cap = W.maxDur[w] > 0 and W.openedAt[w] + W.maxDur[w] or math.huge
        if not (W.refresh[w] and (W.maxRef[w] < 0 or W.refreshes[w] < W.maxRef[w]) and W.expiresAt[w] < cap) then
            return "refused"
        end
        local e = t + d
        W.expiresAt[w], W.refreshes[w] = e < cap and e or cap, W.refreshes[w] + 1
        return "applied"
    elseif op == CLOSE then
        if W.up[w] then
            close(w)
        end
        return "applied"
    elseif op == STEP then
        local n = W.nSteps[w]
        if not W.up[w] or n == 0 or type(arg) ~= "number" or arg < 1 or arg > n + 1 or arg % 1 ~= 0 then
            return "dropped"
        end
        W.step[w] = arg
        if W.timeout[w] > 0 then
            W.deadline[w] = t + W.timeout[w]
        end
        return "applied"
    end
    return "dropped"
end

-- One `[vs] windowop` trace line while the core's trace is open: `word` applied, refused or dropped (replayed), overflow
-- (dropped at send, over the bound) or discarded (waiting at a full Build); a replay skips the last two.
local function trace(word, key, op, arg, t)
    local h = I.logger
    if h and h.active() then
        pcall(
            h.write,
            "[vs] windowop %s %s %s %s t=%.3f",
            word,
            tostring(key),
            OPNAME[op] or tostring(op),
            tostring(arg),
            t
        )
    end
end

--- (windows design v6 §5.1, v6.1; the owner-approved crossing) The core's operation `op` on APL window `key`: 1 OPEN,
--- 2 CLOSE, 3 STEP (arg: the step). Buffered as three plain values; the next Drain replays them in order before
--- anything else. Allocates nothing.
function VS.WindowOp(key, op, arg)
    local n = Q.n + 1
    if n > Q.cap then
        Q.dropped, Q.lastDrop = Q.dropped + 1, key
        trace("overflow", key, op, arg or 0, I.clock)
        return
    end
    Q.key[n], Q.op[n], Q.arg[n], Q.n = key, op, arg or 0, n
end

-- Builds rows nLua+1.. from `def.aplWindows` and sizes the buffer (allocates; a build or a generation change only).
-- Operations still waiting (a full Build: a generation change replays them first) are discarded: counted dropped.
local declare
local function applyApl(def)
    for i = 1, Q.n do
        Q.dropped, Q.lastDrop = Q.dropped + 1, Q.key[i]
        trace("discarded", Q.key[i], Q.op[i], Q.arg[i], I.clock)
        Q.key[i] = false
    end
    for w = W.nLua + 1, W.n do
        W.byKey[W.key[w]] = nil
    end
    local list = def.aplWindows or NONE
    W.n = W.nLua + #list
    for k = 1, #list do
        declare(W.nLua + k, list[k], true)
    end
    local cap = type(def.aplOpCap) == "number" and def.aplOpCap or 0
    for i = Q.cap + 1, cap do
        Q.key[i], Q.op[i], Q.arg[i] = false, 0, 0
    end
    Q.cap, Q.n, W.gen = cap, 0, def.aplGen
end

--- Drain's first windows step (Sources/Sources.lua VS.Drain, after the flush): the buffered operations in order at
--- the previous cut-off (the belief clock), each logged while the core's trace is open, an unknown key (or a Lua
--- window's) dropped and counted; then a new `def.aplGen`, out of combat. Allocates nothing but that rebuild.
function I.WindowOps()
    local t = I.clock
    for i = 1, Q.n do
        local key, op, arg = Q.key[i], Q.op[i], Q.arg[i]
        local w = W.byKey[key]
        local word = w ~= nil and w > W.nLua and write(w, op, arg, t) or "dropped"
        if word == "applied" then
            Q.applied = Q.applied + 1
        elseif word == "refused" then
            Q.refused = Q.refused + 1
        else
            Q.dropped, Q.lastDrop = Q.dropped + 1, key
        end
        trace(word, key, op, arg, t)
        Q.key[i] = false -- drop the reference
    end
    Q.n = 0
    local def = I.def
    -- in combat only while no APL row exists yet (a /reload or login in combat: the scripts, and so the active pack's
    -- windows, load after the Build), so nothing open is lost; otherwise at the first Drain out of combat
    if def and def.aplGen ~= W.gen and (not I.inCombat or W.n == W.nLua) then
        applyApl(def)
    end
end

I.OnSnapshot(function(out)
    for w = 1, W.n do
        local a = W.devAb[w]
        out[#out + 1] = string.format(
            "window %s up=%s step=%d/%d opened=%.2f expires=%.2f refreshes=%d eval=%s combat=%.2f dev=%s@%.2f due=%d",
            W.key[w],
            tostring(W.up[w]),
            W.step[w],
            W.nSteps[w],
            W.openedAt[w],
            W.expiresAt[w],
            W.refreshes[w],
            tostring(W.last[w]),
            I.combatT,
            a > 0 and tostring(A.key[a]) or "none",
            W.devAt[w],
            W.devDue[w]
        )
    end
    out[#out + 1] = string.format(
        "windowops applied=%d refused=%d dropped=%d lastDrop=%s pending=%d cap=%d gen=%s",
        Q.applied,
        Q.refused,
        Q.dropped,
        tostring(Q.lastDrop),
        Q.n,
        Q.cap,
        tostring(W.gen)
    )
end)

--- (Facade.Window) Window `name`: up, the open's time, its expiry, its refreshes and its step (0 unstepped); false, 0,
--- 0, 0, 0 for a closed or unknown name. Plain values. Allocates nothing.
function VS.Window(name)
    local w = W.byKey[name]
    if not w or not W.up[w] then
        return false, 0, 0, 0, 0
    end
    return true, W.openedAt[w], W.expiresAt[w], W.refreshes[w], W.step[w]
end

-- Row w from record d: a Lua window's (RegisterWindow's) or, with `apl`, an APL window's (no evaluator; steps as ability
-- indexes; `strict`, `reset_on_target_change`, `step_timeout`).
function declare(w, d, apl)
    W.byKey[d.key], W.key[w] = w, d.key
    local f = not apl and d.evaluator
    W.eval[w] = type(f) == "function" and setfenv(f, I.nowCtx) or false
    W.dur[w] = d.duration == "combat" and math.huge or type(d.duration) == "number" and d.duration or 0
    local nd = not apl and d.now_duration
    W.durFn[w] = type(nd) == "function" and setfenv(nd, I.nowCtx) or false
    W.refresh[w] = d.refresh == true
    W.maxDur[w] = type(d.max_duration) == "number" and d.max_duration or 0
    W.maxRef[w] = type(d.max_refresh) == "number" and d.max_refresh or -1
    W.cof[w] = d.close_on_false == true
    local steps = type(d.steps) == "table" and #d.steps > 0 and d.steps or false
    W.steps[w], W.nSteps[w] = steps, steps and #steps or 0
    local lastAt = W.lastAt[w] or {}
    for a = 1, A.n do
        lastAt[a] = 0
    end
    for k = 1, W.nSteps[w] do
        if steps[k] > 0 then
            lastAt[steps[k]] = k
        end
    end
    W.lastAt[w] = lastAt
    W.loop[w] = not apl and d.loop == true
    W.dev[w] = DEV[d.on_deviation] or STAY
    W.strict[w] = d.strict == true
    W.rtc[w] = d.reset_on_target_change == true
    W.park[w] = apl and steps ~= false and not W.strict[w]
    local st = d.step_timeout
    W.timeout[w] = apl and W.strict[w] and (type(st) == "number" and st > 0 and st or STEP_TIMEOUT) or 0
    W.last[w], W.raised[w] = false, false
    W.devAb[w], W.devAt[w], W.devDue[w] = 0, 0, 0
    close(w)
end

I.OnBuild(function(def)
    for k in pairs(W.byKey) do
        W.byKey[k] = nil
    end
    local list = def.windows or NONE
    W.nLua, W.n = #list, #list
    for w = 1, W.nLua do
        declare(w, list[w], false)
    end
    applyApl(def)
end)
