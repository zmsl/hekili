-- SelfTest.lua: the plain self-test (runs at login; lib:SelfTest(fn) runs it again). Three pooled bars on the
-- 25/50/75% curves are pushed plain values, one value every HOLDF frames: every change of a curve's output must fire
-- once, within MAXLAG frames, and every output must be the curve convention's (1 below the edge, 2 at or above it,
-- under whatever snapping the client does). A fourth bar is primed as a source's bar is (held low HOLD frames, then
-- fed a read through a curve that is 2 everywhere: the client's own value, secret where reads are) and must fire once,
-- inside the SETTLE window, never after: a prime's first band is the real one. About 45 frames, invisible. It proves
-- the firing mechanism, the curves and the prime's timing, not the secret path's values (the later shadow check). Until it passes the built kinds are "pending"; while a later
-- run is going the earlier verdict stands. Last file of the list: it ends the load and, after login (a late or
-- upgraded copy), realises at once.
local lib = LibStub and LibStub("LibHiddenValues-1.0", true)
if not (lib and lib.loading) then
    return
end

local EDGES = { 25, 50, 75 }
-- fractions (the curve's x scale); 0.499 sits below the 50% guard point, 0.5 on the step
local SEQ = { 1, 1, 0, 0.6, 0.3, 0.8, 0.5, 0.499, 0.24, 1 }
local HOLDF = 4 -- frames per value
local COUNT_FROM = 2 * HOLDF -- the first value settles (the bars' layout and earlier fills): firings not counted
local MAXLAG = 3 -- frames a firing may trail its change (the run: always 0)

local function finish(fail)
    local st = lib.st
    lib.st = nil
    local lines = {}
    local primeOk = st.primeIn == 1 and st.primeLate == 0
    local pass = not fail and not st.curveBad and st.maxLag <= MAXLAG and primeOk
    lib.freeBar(st.bars[#EDGES + 1])
    for k = 1, #EDGES do
        lib.freeBar(st.bars[k])
        local ok = st.changes[k] > 0 and st.fires[k] == st.changes[k]
        pass = pass and ok
        lines[#lines + 1] = string.format(
            "selftest edge %d%%: changes %d, firings %d: %s",
            EDGES[k],
            st.changes[k],
            st.fires[k],
            ok and "ok" or "FAIL"
        )
    end
    lines[#lines + 1] = string.format(
        "selftest prime: firings in the settle window %d, after it %d: %s",
        st.primeIn,
        st.primeLate,
        primeOk and "ok" or "FAIL"
    )
    lines[#lines + 1] = string.format(
        "selftest %s: curves %s, max lag %d frames%s",
        pass and "PASS" or "FAIL",
        st.curveBad and "WRONG" or "ok",
        st.maxLag,
        fail and (": " .. fail) or ""
    )
    lib.stVerdict, lib.stLines = pass, lines
    lib.capChanged() -- before the callbacks: inside them the handles are already synced to the verdict
    lib.stDone(pass, lines)
end

-- Calls and clears the waiting callbacks.
function lib.stDone(pass, lines)
    local w = lib.stWaiters
    lib.stWaiters = {}
    for i = 1, #w do
        local ok, err = pcall(w[i], pass, lines)
        if not ok then
            lib.report(err)
        end
    end
end

local function step()
    local st = lib.st
    st.frame = st.frame + 1
    local f = st.frame
    local pb = lib.barFrame[st.bars[#EDGES + 1]]
    if f <= lib.HOLD then
        pb:SetValue(lib.LOW)
    else
        local y = UnitHealthPercent("player", true, lib.stCurve)
        if issecretvalue(y) or y ~= nil then
            pb:SetValue(y)
        end
    end
    local x = SEQ[math.floor((f - 1) / HOLDF) + 1]
    if x == nil then
        if f > #SEQ * HOLDF + MAXLAG then
            finish()
        end
        return
    end
    for k = 1, #EDGES do
        local i, e = st.bars[k], EDGES[k]
        local y = lib.curves[e]:Evaluate(x)
        if y ~= ((x * 100 >= e) and 2 or 1) then
            st.curveBad = true
        end
        if f > COUNT_FROM and y ~= st.last[k] then
            st.changes[k] = st.changes[k] + 1
            st.lastCh[k] = f
        end
        st.last[k] = y
        lib.barFrame[i]:SetValue(y)
    end
end

function lib.stStep()
    local ok, err = pcall(step)
    if not ok and lib.st then
        finish(issecretvalue(err) and "error" or tostring(err))
    end
end

function lib.stFire(i)
    local st = lib.st
    if st and i == st.bars[#EDGES + 1] then
        if st.frame > lib.HOLD + 1 + lib.SETTLE then -- the live push is frame HOLD + 1
            st.primeLate = st.primeLate + 1
        elseif st.frame > lib.HOLD then
            st.primeIn = st.primeIn + 1
        end
        return
    end
    if not st or st.frame <= COUNT_FROM then
        return
    end
    for k = 1, #st.bars do
        if st.bars[k] == i then
            st.fires[k] = st.fires[k] + 1
            local lag = st.frame - (st.lastCh[k] or 0)
            if lag > st.maxLag then
                st.maxLag = lag
            end
        end
    end
end

-- fn(pass, lines) when the run ends (never from inside this call, unless the library cannot run at all).
function lib:SelfTest(fn)
    if fn then
        lib.stWaiters[#lib.stWaiters + 1] = fn
    end
    if lib.apiMissing then
        lib.stVerdict, lib.stLines = false, { "selftest FAIL: the client lacks the curve or frame API" }
        return lib.stDone(false, lib.stLines)
    end
    if lib.disabled then
        return lib.stDone(false, { "selftest not run: switched off (SetEnabled(true))" })
    end
    if lib.st or not lib.realised then
        return -- running, or runs at login
    end
    if not lib.stCurve then -- 2 everywhere: the primed bar's read is always at or above
        local c = C_CurveUtil.CreateCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, 2)
        c:AddPoint(1, 2)
        lib.stCurve = c
    end
    local st = { frame = 0, bars = {}, changes = {}, fires = {}, last = {}, lastCh = {}, maxLag = 0 }
    st.primeIn, st.primeLate = 0, 0
    for k = 1, #EDGES + 1 do
        local i = lib.allocBar(lib.ST, EDGES[k] or EDGES[1])
        if not i then
            for j = 1, #st.bars do
                lib.freeBar(st.bars[j])
            end
            if lib.stVerdict ~= nil then -- a full pool says nothing about the mechanism
                return lib.stDone(false, { "selftest not run: no free bar (the earlier verdict stands)" })
            end
            lib.stVerdict, lib.stLines = false, { "selftest FAIL: no bar could be made" }
            lib.capChanged()
            return lib.stDone(false, lib.stLines)
        end
        lib.barPrime[i] = 0
        st.bars[k], st.changes[k], st.fires[k] = i, 0, 0
    end
    -- the curve's x scale is fixed at 0-1; a plain read of the player's health (when the client gives one) checks it
    local x = UnitHealthPercent("player")
    if not issecretvalue(x) and type(x) == "number" and x > 1.0001 then
        st.curveBad = true
    end
    lib.st = st
    lib.wake()
end

-- The last completed run's verdict and lines (the array the callbacks got: read only), both nil before the first run
-- and again after SetEnabled(true) until the new run ends; and whether a run is going.
function lib:GetSelfTest()
    return lib.stVerdict, lib.stLines, lib.st ~= nil
end

lib.loading = nil
if IsLoggedIn and IsLoggedIn() then
    lib.realise()
end
