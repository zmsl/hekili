-- Feed.lua: the driver (every live bar pushed every frame: the measured mode), the client events (login, target
-- change, health for death, re-layouts), the unit checks and the statistics. Every script and event handler runs
-- under pcall: an error turns the kind being fed off for the session (reason "error"), reported once.
local lib = LibStub and LibStub("LibHiddenValues-1.0", true)
if not (lib and lib.loading) then
    return
end

lib.frameSec = lib.frameSec or 1 / 60
lib.nPush = lib.nPush or 0
lib.usAvg, lib.usPeak, lib.winPeak = lib.usAvg or 0, lib.usPeak or 0, lib.winPeak or 0
lib.pushRate, lib.fireRate = lib.pushRate or 0, lib.fireRate or 0
lib.winStart, lib.winPush, lib.winFire = lib.winStart or 0, lib.winPush or 0, lib.winFire or 0

-- Re-layouts (UI scale, window size, the end of a loading screen) may fire a clip whose fill did not change (unprobed):
-- every fed source re-primes. That corrects a stray firing that came before the event or within the HOLD frames after.
local RELAYOUT = { UI_SCALE_CHANGED = true, DISPLAY_SIZE_CHANGED = true, LOADING_SCREEN_DISABLED = true }

lib.onUpdate = lib.onUpdate
    or function(_, elapsed)
        local ok, err = pcall(lib.drive, elapsed)
        if not ok then
            lib.fail(err)
        end
    end
lib.onEvent = lib.onEvent
    or function(_, event, ...)
        local ok, err = pcall(lib.event, event, ...)
        if not ok then
            lib.fail(err)
        end
    end

-- The one frame that exists before login: it waits for PLAYER_LOGIN.
if not lib.apiMissing and not lib.evf then
    lib.evf = CreateFrame("Frame")
    lib.evf:RegisterEvent("PLAYER_LOGIN")
end
if lib.evf then
    lib.evf:SetScript("OnEvent", lib.onEvent)
end

-- An error in the driver, a firing or an event: the kind being fed (all built kinds when none) is off for the session.
function lib.fail(err)
    local kind = lib.feeding
    lib.feeding = nil
    if kind then
        lib.errored[kind] = true
    else
        for k in pairs(lib.kinds) do
            lib.errored[k] = true
        end
    end
    if not lib.failReported then
        lib.failReported = true
        lib.report(err)
    end
    lib.capChanged()
end

function lib.wake()
    local drv = lib.drv
    if drv and drv:GetScript("OnUpdate") == nil then
        drv:SetScript("OnUpdate", lib.onUpdate)
    end
end

-- Login (or a load after it): the root, the driver and the pool are built, every source is rebuilt from the registry
-- and primed, and the first time the self-test runs. A newer minor loaded after login comes here too: it keeps the
-- frames and drops the decoded state (consumers see unknown, then the first band with dir 0).
-- shortcut: no in-place state migration between minors; add one only if late upgrades prove common.
function lib.realise()
    if lib.apiMissing then
        return
    end
    local first = not lib.realised
    lib.realised = true
    if not lib.root then
        local root = CreateFrame("Frame", nil, UIParent)
        root:SetSize(20, 2)
        root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        root:SetFrameStrata("BACKGROUND")
        root:EnableMouse(false)
        root:SetAlpha(0) -- alpha 0 passed the run's self-test; the bars still lay out and fire
        root:Show()
        lib.root = root
    end
    lib.drv = lib.drv or CreateFrame("Frame")
    if lib.drv:GetScript("OnUpdate") then
        lib.drv:SetScript("OnUpdate", lib.onUpdate)
    end
    for _ = #lib.barFrame + 1, lib.POOL do
        lib.newBar()
    end
    local evf = lib.evf
    evf:RegisterEvent("PLAYER_TARGET_CHANGED")
    evf:RegisterEvent("PLAYER_DEAD")
    evf:RegisterEvent("PLAYER_ALIVE")
    evf:RegisterEvent("PLAYER_UNGHOST")
    evf:RegisterUnitEvent("UNIT_HEALTH", "player", "target")
    for ev in pairs(RELAYOUT) do
        pcall(evf.RegisterEvent, evf, ev) -- the client raises on an event it does not have
    end
    lib.winStart = GetTime()
    for i = 1, #lib.sources do
        local s = lib.sources[i]
        s.active = false
        lib.sync(s)
    end
    if first then
        lib:SelfTest()
    end
end

-- Units: tokens only. A secret answer counts as "there" and "not dead": the bands carry on (the dead bar is a later
-- stage).
function lib.present(unit)
    if unit == "player" then
        return true
    end
    local e = UnitExists(unit)
    return issecretvalue(e) or e == true
end

function lib.dead(unit)
    local d = UnitIsDead(unit)
    return not issecretvalue(d) and d == true
end

local function syncUnit(unit)
    local srcs = lib.sources
    for i = 1, #srcs do
        if srcs[i].unit == unit then
            lib.sync(srcs[i])
        end
    end
end

function lib.event(event, unit)
    if event == "PLAYER_LOGIN" then
        lib.realise()
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- under the lockdown a new target cannot be told from the old one: always prime
        local srcs = lib.sources
        for i = 1, #srcs do
            local s = srcs[i]
            if s.unit == "target" then
                local was = s.active
                lib.sync(s)
                if was and s.active then
                    lib.reprime(s)
                end
            end
        end
    elseif event == "UNIT_HEALTH" then
        syncUnit(unit)
    elseif RELAYOUT[event] then
        local srcs = lib.sources
        for i = 1, #srcs do
            if srcs[i].active then
                lib.reprime(srcs[i])
            end
        end
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        syncUnit("player")
    end
end

-- Pushes every bar of a fed source once: a priming bar its low level, then the live read (the first one clears its
-- state; the last settling one ends the prime). The read's result is used once, behind issecretvalue: it is never
-- compared, kept or passed on.
function lib.feed(s)
    local read = lib.kinds[s.kind].read
    local prime, frames, curves, LOW, LIVE = lib.barPrime, lib.barFrame, lib.curves, lib.LOW, lib.SETTLE + 1
    for e, i in pairs(s.bar) do
        local p = prime[i]
        if p > LIVE then
            frames[i]:SetValue(LOW)
            prime[i] = p - 1
        else
            if p == LIVE then
                lib.barState[i] = false
            end
            if p > 0 then
                prime[i] = p - 1
            end
            if p == 1 then
                s.dirty, s.seen, s.seenFrame = true, GetTime(), lib.frameNo
            end
            local x = read(s, curves[e])
            if issecretvalue(x) or x ~= nil then
                frames[i]:SetValue(x)
            end
        end
        lib.nPush = lib.nPush + 1
    end
end

-- One frame: decode what fired last frame, step the self-test, push every fed source; then the statistics. The
-- driver unsets itself when nothing is fed, dirty or testing.
function lib.drive(elapsed)
    local t0 = debugprofilestop()
    lib.frameNo = lib.frameNo + 1
    if elapsed and elapsed > 0 then
        lib.frameSec = lib.frameSec + (elapsed - lib.frameSec) * 0.1
    end
    local srcs = lib.sources
    for k = 1, #srcs do
        local s = srcs[k]
        if s.dirty then
            s.dirty = false
            local hs = s.handles
            for j = #hs, 1, -1 do
                if hs[j] then
                    lib.decode(hs[j])
                end
            end
        end
    end
    local busy = false
    if lib.st then
        busy = true
        lib.stStep()
    end
    for k = 1, #srcs do
        local s = srcs[k]
        if s.active then
            busy = true
            lib.feeding = s.kind
            lib.feed(s)
        end
        busy = busy or s.dirty
    end
    lib.feeding = nil
    lib.stats(t0)
    if not busy then
        lib.drv:SetScript("OnUpdate", nil)
    end
end

-- Average (about one second) and peak microseconds per frame; pushes and firings per second, per one-second window.
function lib.stats(t0)
    local us = (debugprofilestop() - t0) * 1000
    lib.usAvg = lib.usAvg + (us - lib.usAvg) * 0.02
    if us > lib.winPeak then
        lib.winPeak = us
    end
    local now = GetTime()
    local dt = now - lib.winStart
    if dt >= 1 then -- also the divide guard
        lib.usPeak, lib.winPeak = lib.winPeak, 0
        lib.pushRate = (lib.nPush - lib.winPush) / dt
        lib.fireRate = (lib.nFire - lib.winFire) / dt
        lib.winStart, lib.winPush, lib.winFire = now, lib.nPush, lib.nFire
    end
end

-- bars in use, average and peak µs per frame, pushes and firings per second, desyncs, governor level (none yet: 0).
function lib:GetStats()
    return #lib.barFrame - #lib.free, lib.usAvg, lib.usPeak, lib.pushRate, lib.fireRate, lib.desyncs, 0
end

-- One row per source with a handle, in creation order: { kind =, unit =, power =, predicted =, handles =, bars =,
-- active = } (the first four are the source's key; active: fed every frame). A fresh array: a cold path.
function lib:GetSources()
    local out = {}
    for i = 1, #lib.sources do
        local s = lib.sources[i]
        if #s.handles > 0 then
            local n = 0
            for _ in pairs(s.bar) do
                n = n + 1
            end
            out[#out + 1] = {
                kind = s.kind,
                unit = s.unit,
                power = s.power,
                predicted = s.predicted,
                handles = #s.handles,
                bars = n,
                active = s.active and true or false,
            }
        end
    end
    return out
end
