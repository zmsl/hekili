-- VirtualState/EventFacade.lua
-- The event facade (event-facade spec §2): VirtualState's frame is the only frame registered with the client. Every
-- frame Hekili makes comes from Facade.CreateFrame, whose event methods subscribe to this layer instead of the client;
-- the layer registers the union of its subscribers and VirtualState's sources, runs the sources first, then calls
-- each subscriber's current OnEvent script with the event in the game's own shape (secret slots nil; UNIT_AURA's
-- payload the layer's own full update). COMBAT_LOG_EVENT_UNFILTERED is never registered with the client.
-- Credits: the Plain gate on every payload slot follows Catnip's (Durts) secret-value research.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain
local _G = _G

local E = {}
I.Events = E

-- The client table: `_G` in game; a spec sets its CreateFrame (and issecretvalue) to the fake's before loading.
local client = _G
local realCreateFrame = client.CreateFrame

-- Events the client never sees: COMBAT_LOG_EVENT_UNFILTERED is the layer's own log (spec §2.2; registering it on an
-- addon frame is forbidden on Forever), FRAME_UPDATE is Hekili's OnUpdate.
local NEVER = { COMBAT_LOG_EVENT_UNFILTERED = true, FRAME_UPDATE = true }

-- UNIT_AURA's payload for the units VirtualState believes (spec §2.5): always a full update, preallocated. Other units
-- get nil (their table has secret fields in combat and the layer has no beliefs for them).
local AURA_INFO = { player = { isFullUpdate = true }, target = { isFullUpdate = true } }

-- Subscriptions by event: parallel arrays, `false` in `f` for a removed one (reused by the next subscription).
local SUB = {}
E.STUB = {} -- events the client refused at registration: never delivered
E.delivered, E.errors, E.lastError = 0, 0, nil
E.depth = 0 -- deliveries in progress (nested client events): a freed slot is not reused while one runs

E.frame = nil

-- The client registration for `e`: the union of the sources' units (once Start has set I.api) and the subscribers'.
-- One or two units register per unit, anything more or a general subscriber registers the event. Not recurring.
local any, general, un1, un2
local function add(u)
    any = true
    if u == nil then
        general = true
    elseif u ~= un1 and u ~= un2 then
        if un1 == nil then
            un1 = u
        elseif un2 == nil then
            un2 = u
        else
            general = true
        end
    end
end

local function sync(e)
    local frame = E.frame
    if NEVER[e] or E.STUB[e] or not frame then
        return
    end
    any, general, un1, un2 = false, false, nil, nil
    if I.api and S.HANDLERS[e] then
        local su = S.UNITS[e]
        if su then
            for k = 1, #su do
                add(su[k])
            end
        else
            add(nil)
        end
    end
    local list = SUB[e]
    if list then
        for k = 1, list.n do
            if list.f[k] then
                add(list.u1[k])
                if list.u2[k] then
                    add(list.u2[k])
                end
            end
        end
    end
    frame:UnregisterEvent(e)
    if not any then
        return
    end
    local ok, res
    if general then
        ok, res = pcall(frame.RegisterEvent, frame, e)
    else
        ok, res = pcall(frame.RegisterUnitEvent, frame, e, un1, un2)
    end
    if not ok or res == false then -- the client raises for an unknown event, or returns false
        E.STUB[e] = true
    end
end

--- Subscribes `frame` to `e` (for one or two units, or every unit). Load time and rare runtime registrations only.
function E.Subscribe(frame, e, u1, u2)
    local list = SUB[e]
    if not list then
        list = { n = 0, f = {}, u1 = {}, u2 = {} }
        SUB[e] = list
    end
    local free
    for k = 1, list.n do
        local f = list.f[k]
        if f == frame then
            free = k
            break
        elseif not f and not free and E.depth == 0 then
            free = k
        end
    end
    if not free then
        free = list.n + 1
        list.n = free
    end
    list.f[free], list.u1[free], list.u2[free] = frame, u1, u2
    sync(e)
    return not E.STUB[e]
end

--- Ends `frame`'s subscription to `e`; the client registration drops what no one needs any more.
function E.Unsubscribe(frame, e)
    local list = SUB[e]
    if not list then
        return
    end
    local changed = false
    for k = 1, list.n do
        if list.f[k] == frame then
            list.f[k], list.u1[k], list.u2[k] = false, nil, nil
            changed = true
        end
    end
    if changed then -- UnregisterAllEvents walks every event: only the ones this frame had touch the client
        sync(e)
    end
end

function E.IsSubscribed(frame, e)
    local list = SUB[e]
    if list then
        for k = 1, list.n do
            if list.f[k] == frame then
                return true
            end
        end
    end
    return false
end

-- The event methods every facade frame gets: shared functions, no closure per frame.
local function register(self, e)
    return E.Subscribe(self, e)
end
local function registerUnit(self, e, u1, u2)
    return E.Subscribe(self, e, u1, u2)
end
local function unregister(self, e)
    E.Unsubscribe(self, e)
end
local function unregisterAll(self)
    for e in pairs(SUB) do
        E.Unsubscribe(self, e)
    end
end
local function isRegistered(self, e)
    return E.IsSubscribed(self, e)
end

--- Facade.CreateFrame: the client's frame with its event methods shadowed by the layer's (spec §2.1).
function E.CreateFrame(...)
    local f = realCreateFrame(...)
    f.RegisterEvent, f.RegisterUnitEvent, f.UnregisterEvent = register, registerUnit, unregister
    f.UnregisterAllEvents, f.IsEventRegistered = unregisterAll, isRegistered
    return f
end

-- Calls every subscriber of `event` whose units match, in subscription order, through its current OnEvent script; a
-- raising handler is reported and the loop goes on. Allocates nothing.
local function deliver(event, a1, a2, a3, a4, a5, a6, a7, a8)
    local list = SUB[event]
    if not list then
        return
    end
    E.depth = E.depth + 1
    for k = 1, list.n do -- a subscription made during this delivery is appended and starts with the next event
        local f = list.f[k]
        if f then
            local u = list.u1[k]
            if u == nil or (a1 ~= nil and (u == a1 or list.u2[k] == a1)) then -- a nil unit matches only general
                local fn = f:GetScript("OnEvent")
                if fn then
                    E.delivered = E.delivered + 1
                    local ok, err
                    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                        ok, err = pcall(fn, f, event) -- no payload, as the client delivers it
                    else
                        ok, err = pcall(fn, f, event, a1, a2, a3, a4, a5, a6, a7, a8)
                    end
                    if not ok then
                        E.errors, E.lastError = E.errors + 1, err
                        local handler = client.geterrorhandler
                        if handler then
                            handler()(err)
                        end
                    end
                end
            end
        end
    end
    E.depth = E.depth - 1
end
E.Deliver = deliver

-- One client event: (1) the sources (once Start has run), (2) the payload, (3) every matching subscriber, (4) the
-- combat-log rows it completed (CombatLog.lua). Each slot is gated into a local, so a nested client event is
-- delivered in its own call with its own values. Allocates nothing.
local function onEvent(_, event, r1, r2, r3, r4, r5, r6, r7, r8)
    local api = I.api or client
    local a1, a2, a3, a4 = Plain(api, r1), Plain(api, r2), Plain(api, r3), Plain(api, r4)
    local a5, a6, a7, a8 = Plain(api, r5), Plain(api, r6), Plain(api, r7), Plain(api, r8)
    if I.api then
        S.Run(api, event, a1, a2, a3, a4, a5)
    end
    local h = I.hekili -- the trace (§5): one line per event while Hekili makes a snapshot
    if h and h.ActiveDebug then
        pcall(h.Debug, h, "[vs] event %s(%s, %s, %s)", event, tostring(a1), tostring(a2), tostring(a3))
    end
    if event == "UNIT_AURA" then
        a2 = AURA_INFO[a1]
    end
    deliver(event, a1, a2, a3, a4, a5, a6, a7, a8)
    I.Log.Deliver()
end

local function onUpdate()
    S.Flush()
    local api = I.api
    if api then
        I.Log.Tick(api.GetTime()) -- closes pairing windows (deferred rows)
    end
    I.Log.Deliver()
end

local function makeFrame(createFrame)
    local frame = createFrame("Frame")
    E.frame = frame
    frame:SetScript("OnEvent", onEvent)
    frame:SetScript("OnUpdate", onUpdate)
    for e in pairs(SUB) do
        sync(e)
    end
end

-- In game the frame exists from load, so the events before login (VARIABLES_LOADED, PLAYER_LOGIN) reach Hekili.
if realCreateFrame then
    makeFrame(realCreateFrame)
end

--- VirtualState.Start's half: the frame (from `api` when the client had none at load: a headless spec), then the
--- sources' registrations added to it. Once.
function E.Attach(api)
    if not E.frame then
        realCreateFrame = realCreateFrame or api.CreateFrame
        makeFrame(api.CreateFrame)
    end
    for e in pairs(S.HANDLERS) do
        sync(e)
    end
end

--- Snapshot's lines: delivery counts, handler errors, refused events. Allocates (debugging only).
I.OnSnapshot(function(out)
    local stubs = {}
    for e in pairs(E.STUB) do
        stubs[#stubs + 1] = e
    end
    table.sort(stubs)
    out[#out + 1] = string.format(
        "events delivered=%d errors=%d stubs=[%s]%s",
        E.delivered,
        E.errors,
        table.concat(stubs, " "),
        E.lastError and (" last error=" .. tostring(E.lastError)) or ""
    )
end)
