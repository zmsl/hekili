-- Game/State/Families/Windows.lua
-- Rotation windows (re-pin design §3a, decision 11): spans the client shows no aura for, owned by the belief. Each
-- window's evaluator (RegisterWindow, Engine/Schema/Spec.lua; `def.windows`) is bound into the `now` context
-- (Families/Now.lua) and runs once per Drain after the fold (I.RunWindows). Edges: false->true opens a closed window, or
-- with `refresh` restarts an open one (counted once per edge against `max_refresh`, bounded by `max_duration` from the
-- first open); a condition held true does nothing; true->false closes only with `close_on_false`; a close acts only on
-- an open window; an open ends at its expiry and at combat end (the last evaluations kept, so a held condition needs a
-- new edge). A stepped window advances on our observed cast of its due step's ability (I.WindowCast, from the cast
-- fold); a later step's cast follows `on_deviation`; with `strict`, any other on-GCD cast ends it. The core reads it
-- only through Facade.Window (VS.Window). Everything preallocated at Build; nothing allocated per Drain or per cast.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs
local A = I.ab

local STAY, SKIP, END = 1, 2, 3
local DEV = { stay = STAY, skip = SKIP, ["end"] = END }
local NONE = {} -- a hand-built def may carry no `windows`

-- By window index: the declaration, then the state.
local W = {
    n = 0,
    byKey = {},
    eval = {}, -- the evaluator bound to the `now` context, or false
    dur = {},
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
    raised = {}, -- the evaluator raised: it reads false and is not run again (counted once, as I.Eval)
}
I.win = W

local function close(w)
    W.up[w], W.openedAt[w], W.expiresAt[w], W.refreshes[w], W.step[w] = false, 0, 0, 0, 0
end

-- The edge rules' open: a closed window opens at t; an open one restarts with `refresh` within its caps.
local function open(w, t)
    if W.up[w] and W.expiresAt[w] <= t then
        close(w) -- expired, not yet closed (expiry is applied after the fold): a fresh open, not a refresh
    end
    local e = t + W.dur[w]
    if not W.up[w] then
        W.up[w], W.openedAt[w], W.refreshes[w] = true, t, 0
        W.step[w] = W.nSteps[w] > 0 and 1 or 0
    elseif W.refresh[w] and (W.maxRef[w] < 0 or W.refreshes[w] < W.maxRef[w]) then
        W.refreshes[w] = W.refreshes[w] + 1
    else
        return
    end
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

-- Past step s of window w: the next step, or after the last a close (step 1 with `loop`).
local function advance(w, s)
    if s < W.nSteps[w] then
        W.step[w] = s + 1
    elseif W.loop[w] then
        W.step[w] = 1
    else
        close(w)
    end
end

--- Our cast of ability a (Families/Now.lua's cast fold, every own CastSuccess): each up stepped window's due step
--- advances; a later step's cast follows `on_deviation`; a strict window ends at any other on-GCD cast. One lookup read
--- per stepped window. Allocates nothing.
function I.WindowCast(a, t)
    for w = 1, W.n do
        if W.up[w] and W.expiresAt[w] <= t then
            close(w)
        end
        local steps = W.steps[w]
        if steps and W.up[w] then
            local due = W.step[w]
            if steps[due] == a then
                advance(w, due)
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
                    local d = W.dev[w]
                    if d == SKIP then
                        advance(w, later)
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
        if W.up[w] and W.expiresAt[w] <= t then
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

--- (Facade.Window) Window `name`: up, the open's time, its expiry, its refreshes and its step (0 unstepped); false, 0,
--- 0, 0, 0 for a closed or unknown name. Plain values. Allocates nothing.
function VS.Window(name)
    local w = W.byKey[name]
    if not w or not W.up[w] then
        return false, 0, 0, 0, 0
    end
    return true, W.openedAt[w], W.expiresAt[w], W.refreshes[w], W.step[w]
end

I.OnBuild(function(def)
    for k in pairs(W.byKey) do
        W.byKey[k] = nil
    end
    local list = def.windows or NONE
    W.n = #list
    for w = 1, W.n do
        local d = list[w]
        W.byKey[d.key] = w
        local f = d.evaluator
        W.eval[w] = type(f) == "function" and setfenv(f, I.nowCtx) or false
        W.dur[w] = type(d.duration) == "number" and d.duration or 0
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
        W.loop[w] = d.loop == true
        W.dev[w] = DEV[d.on_deviation] or STAY
        W.strict[w] = d.strict == true
        W.last[w], W.raised[w] = false, false
        close(w)
    end
end)
