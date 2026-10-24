-- Game/State/Sources/Sources.lua
-- Sources (spec §4): the only VirtualState code that touches the game, and only through the injected `api` (`_G` in
-- game, a fake in tests). This file: the `Plain` secrecy gate, staging and the per-frame Flush, the polls, the event
-- registry and VirtualState.Start (the frame is the event facade's, Game/Events/EventFacade.lua).
-- Credits: the `Plain` gate and the issecretvalue/pcall handling follow Catnip's (Durts) secret-value research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Sources.lua (Plain :42-46, STAGE :52, Stage :540, Flush
-- :552-561, the poll loop :564-588 with Sources.Poll at :576).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Add = I.ObsLog.Add

local S = {}
I.Sources = S

--- A client value VirtualState may test, compare or use: the value itself, or nil if it is secret. It asks
--- `issecretvalue` before touching the value in any other way. Allocates nothing.
function S.Plain(api, v)
    if api.issecretvalue(v) then
        return nil
    end
    return v
end
local Plain = S.Plain

--- Staged observations one frame holds before the newest is dropped (and counted).
S.STAGE = 128
local stKind, stT, stA, stB, stC = {}, {}, {}, {}, {}
for i = 1, S.STAGE do
    stKind[i], stT[i], stA[i], stB[i], stC[i] = 0, 0, 0, 0, 0
end
S.stN, S.dropped = 0, 0

--- Stages one observation until the next Flush (a frame's aura reads go to the log first). False when the stage is
--- full (dropped and counted). Allocates nothing.
function S.Stage(kind, t, a, b, c)
    local n = S.stN
    if n >= S.STAGE then
        S.dropped = S.dropped + 1
        return false
    end
    n = n + 1
    S.stN = n
    stKind[n], stT[n], stA[n], stB[n], stC[n] = kind, t, a or 0, b or 0, c or 0
    return true
end

--- Straight into the log (aura reads and polls). Allocates nothing.
function S.Direct(kind, t, a, b, c)
    Add(I.log, kind, t, a, b, c)
end

--- Moves the staged observations into the log, in order. Runs at the start of each frame (the frame's OnUpdate).
function S.Flush()
    local log = I.log
    for i = 1, S.stN do
        Add(log, stKind[i], stT[i], stA[i], stB[i], stC[i])
    end
    S.stN = 0
end

-- Read statuses for Snapshot(), by read name: "readable", "secret", "nil" or "error".
S.status = {}

--- Notes what a read answered (constant strings only: allocates nothing).
function S.Note(name, status)
    S.status[name] = status
end

--- The status of a raw value: "secret", "nil" or "readable". Allocates nothing.
function S.StatusOf(api, raw)
    if api.issecretvalue(raw) then
        return "secret"
    elseif raw == nil then -- secret: issecretvalue tested on the line above
        return "nil"
    end
    return "readable"
end

-- The polls (spec §4.3), sorted by order.
local POLL_ORDER, POLL_FN, POLL_N = {}, {}, 0

--- Registers `fn(api, t)` as poll `order` (an order registers once). Load time only.
function S.Poll(order, fn)
    for i = 1, POLL_N do
        if POLL_ORDER[i] == order then
            error("VirtualState: poll order " .. tostring(order) .. " is registered twice", 2)
        end
    end
    local i = POLL_N + 1
    while i > 1 and POLL_ORDER[i - 1] > order do
        POLL_ORDER[i], POLL_FN[i] = POLL_ORDER[i - 1], POLL_FN[i - 1]
        i = i - 1
    end
    POLL_ORDER[i], POLL_FN[i] = order, fn
    POLL_N = POLL_N + 1
end

--- Runs every poll in order, each straight into the log at `t` (the drain's cut-off). Allocates nothing.
function S.RunPolls(t)
    local api = I.api
    if not api then
        return
    end
    for i = 1, POLL_N do
        POLL_FN[i](api, t)
    end
end

-- The event registry: event -> handlers, and event -> the units it is registered for (unit events). The event facade
-- registers them with the client at Start.
local HANDLERS, UNITS = {}, {}
S.HANDLERS, S.UNITS = HANDLERS, UNITS

--- Registers `fn(api, t, a1, a2, a3, a4, a5)` for `event`; `unit` ("player" or "target") makes it a unit event
--- for that unit (the handler still checks a1). Every argument reaches the handler through Plain. Load time only.
function S.On(event, unit, fn)
    local list = HANDLERS[event]
    if not list then
        list = {}
        HANDLERS[event] = list
    end
    list[#list + 1] = fn
    if unit then
        local u = UNITS[event]
        if not u then
            u = {}
            UNITS[event] = u
        end
        if u[1] ~= unit and u[2] ~= unit then
            u[#u + 1] = unit
        end
    end
end

-- Events a provider owns while it is inactive: the facade does not register them with the client (spec §3.2).
S.DORMANT = {}
--- Marks `event` dormant (on) or awake; the caller then asks the facade to sync it (I.Events.Sync). Load time and
--- activation only.
function S.Dormant(event, on)
    S.DORMANT[event] = on or nil
end

-- Start hooks: `fn(api, t)` once at VirtualState.Start, in registration order.
local STARTS = {}
function S.OnStart(fn)
    STARTS[#STARTS + 1] = fn
end

--- Asks Hekili for a sooner cycle (the urgent lane, spec §4.4). Adapter.lua sets `I.urgent`.
function S.Urgent(event)
    local f = I.urgent
    if f then
        f(event)
    end
end

--- Our own cast started or succeeded, our channel ended or a swing queue changed (the display's steady icons show
--- the next set at once). Adapter.lua sets `I.acted`.
function S.Acted()
    local f = I.acted
    if f then
        f()
    end
end

--- Runs the sources for one client event. The event facade has already passed every slot through Plain.
function S.Run(api, event, a1, a2, a3, a4, a5)
    local list = HANDLERS[event]
    if not list then
        return
    end
    local t = api.GetTime()
    for k = 1, #list do
        list[k](api, t, a1, a2, a3, a4, a5)
    end
end

--- Once, at PLAYER_LOGIN: `api` is `_G` in game and a fake in tests. Adds the source events (spec §4.2) to the event
--- facade's frame, which also runs the per-frame flush. Allocates; once.
---@param api table
function VS.Start(api)
    I.api = api
    I.Events.Attach(api)
    local t = api.GetTime()
    -- read before the re-activation (Player.lua's hook reads it too late): a /reload in combat defers it to combat end
    I.inCombat = Plain(api, api.InCombatLockdown()) == true
    if I.outcomes then -- a build before Start activated its providers without an api
        if I.inCombat then
            I.restartProviders = true -- I.ApplyProviders at PLAYER_REGEN_ENABLED (decision 89: no path change mid-fight)
        else
            I.outcomes.Activate(api, t)
            I.presence.Activate(api, t, I.def, { viewer = I.presenceViewer == true })
        end
    end
    for k = 1, #STARTS do
        -- one raising hook (a client without some API) must not stop the hooks after it
        local ok, err = pcall(STARTS[k], api, t)
        if not ok then
            S.Note("start", "error")
            if api.geterrorhandler then
                api.geterrorhandler()(err)
            else
                print(err)
            end
        end
    end
end
