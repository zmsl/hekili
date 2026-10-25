-- Gate.lua: GC-T, the gate comparator as a threshold bank (hekili docs/dev/ingame-ledger.md, row GC-T).
-- Driven by Log.lua: /vslog gate health|power|off (and /vslog auto, one fight each). Records through Log.lua's emit:
--   GATE_START <mode>                    the bank starts (frames are built once, on the first start);
--   GATE_VAL raw=<bool> curve=<bool>     issecretvalue of the raw percent and of a curve result, once per start;
--   GATE_CALL <method> ok|err <message>  the first result of each call and every change between ok and err
--                                        (SetAlpha, SetShown, SetAlphaFromBoolean, SetValue, read);
--   GATE_HOOK <widget> OnShow|OnHide|OnSizeChanged [w= h=]   any hook that fires while the bank runs;
--   GATE_SIG <widget> <sig>              a widget's getter signature, on the first sweep and whenever it changes:
--                                        shown/visible/alpha/effectiveAlpha[/value/fillW/clipW/clipR]/u (OnUpdate ran
--                                        since the last sweep) or - ; a secret read prints S;
--   GATE_SUM <method> ok=<n> err=<n>     at stop.
-- Widgets: for each scale (curve input 0-100 and 0-1, the client's scale is unconfirmed) and each threshold 20/40/60/80,
-- a<t>/<s> (SetAlpha of a step curve 0 below, 1 at or above), s<t>/<s> (SetShown of it), b<t>/<s>
-- (SetAlphaFromBoolean of it), bar<t>/<s> (a StatusBar over [t - eps, t] fed the raw percent) and clip<t>/<s> (a child
-- of the bar, clipped by it, anchored to the fill texture's right edge: the EllesmereUI comparator shape).
-- Any plain value in a GATE_SIG line that changes as health or power crosses a threshold is the finding.
-- SAFETY: only the probe's own frames are touched; every call on a secret is pcalled; a secret is never compared.
local _, ns = ...

local isSecret = issecretvalue or function() return false end
local format = string.format
local STEP = (Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step) or 1
local THRESHOLDS = { 20, 40, 60, 80 }
local SCALES = { 100, 1 }
local READ_EVERY = 5 -- frames between getter sweeps
local SIZE = 18

local Gate = {}
ns.Gate = Gate

local root, emit, stamp
local cells, widgets = {}, {}
local mode -- nil (off), "health" or "power"
local frames, valDone = 0, false
local stats = {} -- method -> { ok = n, err = n, last = true|false|nil }
local METHODS = { "read", "SetAlpha", "SetShown", "SetAlphaFromBoolean", "SetValue" }

local function str(v)
    if isSecret(v) then return "S" end
    return tostring(v)
end

local function val(name, v)
    return " " .. name .. "=" .. str(v)
end

local function note(method, ok, err)
    local s = stats[method]
    if ok then s.ok = s.ok + 1 else s.err = s.err + 1 end
    if s.last ~= ok then
        s.last = ok
        emit(format("%d GATE_CALL %s %s%s", stamp(), method, ok and "ok" or "err",
            ok and "" or (" " .. (isSecret(err) and "secret" or tostring(err)))))
    end
end

-- The source percent through a curve (nil = raw), or nil after a failed read.
local function read(curve)
    local ok, v
    if mode == "health" then
        ok, v = pcall(UnitHealthPercent, "target", true, curve)
    else
        ok, v = pcall(UnitPowerPercent, "player", nil, false, curve)
    end
    note("read", ok, v)
    if not ok then return nil end
    return v
end

local function try(method, w, v)
    local ok, err = pcall(w[method], w, v)
    note(method, ok, err)
end

local function getter(w, method)
    if type(w[method]) ~= "function" then return "n/a" end
    local ok, v = pcall(w[method], w)
    if not ok then return "err" end
    return str(v)
end

local function sweep()
    for i = 1, #widgets do
        local w = widgets[i]
        local f = w.frame
        local sig = getter(f, "IsShown") .. "/" .. getter(f, "IsVisible") .. "/" .. getter(f, "GetAlpha") .. "/"
            .. getter(f, "GetEffectiveAlpha")
        if w.bar then
            sig = sig .. "/" .. getter(f, "GetValue") .. "/" .. getter(w.fill, "GetWidth")
        elseif w.clip then
            sig = sig .. "/" .. getter(f, "GetWidth") .. "/" .. getter(f, "GetRight")
        end
        sig = sig .. "/" .. (w.upd and "u" or "-")
        w.upd = false
        if sig ~= w.sig then
            w.sig = sig
            emit(format("%d GATE_SIG %s %s", stamp(), w.label, sig))
        end
    end
end

local function drive()
    frames = frames + 1
    local raw = read(nil)
    for i = 1, #cells do
        local c = cells[i]
        local v = read(c.curve)
        if not valDone then
            valDone = true
            emit(format("%d GATE_VAL raw=%s curve=%s", stamp(), tostring(isSecret(raw)), tostring(isSecret(v))))
        end
        if isSecret(v) or v ~= nil then
            try("SetAlpha", c.a, v)
            try("SetShown", c.s, v)
            try("SetAlphaFromBoolean", c.b, v)
        end
        if isSecret(raw) or raw ~= nil then try("SetValue", c.bar, raw) end
    end
    if frames % READ_EVERY == 0 then sweep() end
end

local function hook(w)
    local f = w.frame
    local label = w.label
    f:HookScript("OnShow", function()
        if mode then emit(format("%d GATE_HOOK %s OnShow", stamp(), label)) end
    end)
    f:HookScript("OnHide", function()
        if mode then emit(format("%d GATE_HOOK %s OnHide", stamp(), label)) end
    end)
    f:HookScript("OnSizeChanged", function(_, width, height)
        if mode then emit(format("%d GATE_HOOK %s OnSizeChanged", stamp(), label) .. val("w", width) .. val("h", height)) end
    end)
    f:HookScript("OnUpdate", function() w.upd = true end)
    widgets[#widgets + 1] = w
end

local function square(col, row, r, g, b)
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(SIZE, SIZE)
    f:SetPoint("TOPLEFT", 4 + (col - 1) * (SIZE + 4), -16 - (row - 1) * (SIZE + 4))
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, 1)
    return f
end

local function build()
    root = CreateFrame("Frame", "ForeverProbeGateFrame", UIParent)
    root:SetSize(4 + #THRESHOLDS * #SCALES * (SIZE + 4), 20 + 4 * (SIZE + 4))
    root:SetPoint("CENTER", 0, 220)
    local bg = root:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 4, -2)
    title:SetText("GC-T rows: SetAlpha, SetShown, FromBoolean, bar; 20-80 x100 | 20-80 x1")
    root:Hide()
    local col = 0
    for _, scale in ipairs(SCALES) do
        for _, t in ipairs(THRESHOLDS) do
            col = col + 1
            local thr = t * scale / 100
            local curve = C_CurveUtil.CreateCurve()
            curve:SetType(STEP)
            curve:AddPoint(0, 0)
            curve:AddPoint(thr, 1)
            local tag = format("%d/%d", t, scale == 100 and 100 or 1)
            local c = { curve = curve }
            c.a = square(col, 1, 1, 0.8, 0.2)
            c.s = square(col, 2, 0.2, 0.9, 0.3)
            c.b = square(col, 3, 0.3, 0.6, 1)
            local bar = CreateFrame("StatusBar", nil, root)
            bar:SetSize(SIZE, SIZE)
            bar:SetPoint("TOPLEFT", 4 + (col - 1) * (SIZE + 4), -16 - 3 * (SIZE + 4))
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            bar:SetStatusBarColor(1, 0.3, 0.3, 1)
            bar:SetMinMaxValues(thr - scale / 1000, thr)
            bar:SetValue(thr - scale / 1000)
            bar:SetClipsChildren(true)
            local fill = bar:GetStatusBarTexture()
            local clip = CreateFrame("Frame", nil, bar)
            clip:SetPoint("TOPLEFT", bar, "TOPLEFT")
            clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
            c.bar = bar
            cells[#cells + 1] = c
            hook({ label = "a" .. tag, frame = c.a })
            hook({ label = "s" .. tag, frame = c.s })
            hook({ label = "b" .. tag, frame = c.b })
            hook({ label = "bar" .. tag, frame = bar, bar = true, fill = fill })
            hook({ label = "clip" .. tag, frame = clip, clip = true })
        end
    end
end

--- Starts the bank on "health" (the target) or "power" (the player's primary power); emitFn/stampFn are Log.lua's.
function Gate.Start(m, emitFn, stampFn)
    emit, stamp = emitFn, stampFn
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and UnitHealthPercent and UnitPowerPercent) then
        return emit(format("%d GATE_ERR no curve API", stamp()))
    end
    if mode then Gate.Stop() end
    if not root then
        local ok, err = pcall(build)
        if not ok then return emit(format("%d GATE_ERR build %s", stamp(), tostring(err))) end
    end
    for _, m2 in ipairs(METHODS) do stats[m2] = { ok = 0, err = 0 } end
    for i = 1, #widgets do widgets[i].sig = nil end
    frames, valDone = 0, false
    root:Show() -- before mode is set, so the children's OnShow from this show stays quiet
    mode = m
    emit(format("%d GATE_START %s combat=%s", stamp(), m, tostring(InCombatLockdown())))
    root:SetScript("OnUpdate", drive)
end

function Gate.Stop()
    if not mode then return end
    local m = mode
    mode = nil -- first, so the OnHide hooks of the root's hide stay quiet
    root:SetScript("OnUpdate", nil)
    root:Hide()
    for _, m2 in ipairs(METHODS) do
        emit(format("%d GATE_SUM %s %s ok=%d err=%d frames=%d", stamp(), m, m2, stats[m2].ok, stats[m2].err, frames))
    end
end

function Gate.Running()
    return mode ~= nil
end
