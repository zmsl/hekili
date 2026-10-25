-- ForeverProbe: Hekili's belief next to the live read, one row per tracked resource (and player health).
-- /vsbars   toggle the movable panel
-- Per row: a "real" bar fed straight from UnitPower/UnitHealth (the widget methods take secrets, so the value never
-- touches Lua maths); a "model" bar for Hekili's est with its lo..hi band; text est (lo-hi) conf basis +regen; and
-- the status (combat/ooc, real read secret or plain). Belief path: Hekili.Virtual.State (Game/State/Adapter.lua:27)
-- .Tracked("resource", out), .Power(type, now), .Regen(type, now), .Health("player", now). Updates every 0.1 s.

local NAMES = { [0] = "mana", [1] = "rage", [2] = "focus", [3] = "energy", [4] = "combo", [6] = "runic" }
local W, BAR, ROW, HEALTH = 260, 14, 52, -1 -- HEALTH: the row kind for player health
local panel, rows, nrows, acc = nil, {}, 0, 0
local secret = issecretvalue or function() return false end

local function vstate()
    local v = Hekili and Hekili.Virtual and Hekili.Virtual.State
    return type(v) == "table" and type(v.Power) == "function" and v or nil
end

local function bar(parent, y, r, g, b)
    local s = CreateFrame("StatusBar", nil, parent)
    s:SetSize(W, BAR)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", 70, y)
    s:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    s:SetStatusBarColor(r, g, b)
    s:SetMinMaxValues(0, 1)
    local bg = s:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(s)
    bg:SetColorTexture(0, 0, 0, 0.5)
    s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.text:SetPoint("LEFT", s, "RIGHT", 6, 0)
    return s
end

local function addRow(kind)
    nrows = nrows + 1
    local y = -28 - (nrows - 1) * ROW
    local row = { kind = kind }
    row.name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y)
    row.name:SetText(kind == HEALTH and "health" or NAMES[kind] or ("type " .. kind))
    row.status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.real = bar(panel, y, 0.2, 0.6, 1)
    row.model = bar(panel, y - BAR - 4, 1, 0.6, 0.1)
    row.band = row.model:CreateTexture(nil, "OVERLAY")
    row.band:SetColorTexture(1, 1, 1, 0.35)
    row.band:SetHeight(BAR)
    rows[nrows] = row
end

-- The plain maximum for the model bar: the client's when it reads plain, else Hekili's own defaults (5 CP, 100).
local function plainMax(kind)
    local ok, m
    if kind == HEALTH then
        ok, m = pcall(UnitHealthMax, "player")
    else
        ok, m = pcall(UnitPowerMax, "player", kind)
    end
    if ok and not secret(m) and type(m) == "number" and m > 0 then
        return m
    end
    return kind == 4 and 5 or 100
end

local function updateRow(row, vs, now, fight)
    local kind, ok, v, m, _ = row.kind, nil, nil, nil, nil
    if kind == HEALTH then
        ok, v = pcall(UnitHealth, "player")
        _, m = pcall(UnitHealthMax, "player")
    else
        ok, v = pcall(UnitPower, "player", kind)
        _, m = pcall(UnitPowerMax, "player", kind)
    end
    -- secrets go only into the secret-accepting widget methods (AllowedWhenTainted), each under pcall
    if not (ok and pcall(row.real.SetMinMaxValues, row.real, 0, m) and pcall(row.real.SetValue, row.real, v)
        and pcall(row.real.text.SetFormattedText, row.real.text, "%d / %d", v, m)) then
        row.real.text:SetText("read failed")
    end
    row.status:SetFormattedText("%s %s", fight and "combat" or "ooc", secret(v) and "secret" or "plain")

    if not vs then
        row.model.text:SetText("no Hekili.Virtual.State")
        row.band:Hide()
        return
    end
    local max = plainMax(kind)
    local rec, rate
    if kind == HEALTH then
        max = 1 -- Hekili's health belief is a fraction
        rec, rate = vs.Health("player", now), 0
    else
        rec = vs.Power(kind, now)
        rate = vs.Regen(kind, now).est
    end
    local est, lo, hi = rec.est, rec.lo, rec.hi
    row.model:SetMinMaxValues(0, max)
    row.model:SetValue(est)
    lo, hi = math.max(0, math.min(lo, max)), math.max(0, math.min(hi, max))
    if hi > lo then
        row.band:ClearAllPoints()
        row.band:SetPoint("LEFT", row.model, "LEFT", lo / max * W, 0)
        row.band:SetWidth(math.max(1, (hi - lo) / max * W))
        row.band:Show()
    else
        row.band:Hide()
    end
    row.model.text:SetFormattedText("%.2f (%.2f-%.2f) %.2f %s %+.2f/s", est, rec.lo, rec.hi, rec.conf, rec.basis, rate)
end

local function onUpdate(_, elapsed)
    acc = acc + elapsed
    if acc < 0.1 then
        return
    end
    acc = 0
    local vs, now, fight = vstate(), GetTime(), InCombatLockdown()
    for i = 1, nrows do
        local ok, err = pcall(updateRow, rows[i], vs, now, fight)
        if not ok then
            rows[i].model.text:SetText("error: " .. tostring(err))
        end
    end
end

local function build()
    panel = CreateFrame("Frame", "ForeverProbeVsBars", UIParent, "BackdropTemplate")
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0, 0, 0, 0.8)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
    title:SetText("vsbars: real (blue) vs Hekili model (orange, white = lo..hi)")

    local vs, types, n = vstate(), {}, 0
    if vs and vs.Tracked then
        local ok, c = pcall(vs.Tracked, "resource", types)
        n = ok and c or 0
    end
    if n == 0 then -- Hekili absent or not built yet: the unit's primary power type
        types[1], n = UnitPowerType("player"), 1
        print("|cff00ff00vsbars|r no Hekili tracked resources; showing the primary power type only")
    end
    for i = 1, n do
        addRow(types[i])
    end
    addRow(HEALTH)
    panel:SetSize(W + 330, 34 + nrows * ROW)
    panel:SetScript("OnUpdate", onUpdate)
end

SLASH_VSBARS1 = "/vsbars"
SlashCmdList.VSBARS = function()
    if not panel then
        build()
    elseif panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end
