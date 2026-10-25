-- Calib.lua: live readout of the Hekili fork's believed rage, with pass/fail marks to judge it against the bar.
--   /vsmark            toggles the frame (drag to move; position kept in ForeverProbeDB.calibPos);
--   /vsmark <number>   records a mark with that bar value (same as typing it in the box and pressing Enter);
--   /vsmark pass|fail  records a verdict;
--   /vsmark clear      empties ForeverProbeDB.marks;
--   /vsmark dump       prints every mark through VSCopy, then the mean and max of |delta| over marks with a bar value;
--   /vsmark rate       prints the bar change per second between consecutive marks with a bar value, then overall.
-- Secret values are written as "S" and never used in arithmetic.
local ADDON_NAME, ns = ... -- luacheck: ignore (the shared file header)

local isSecret = issecretvalue or function() return false end
local frame, label, box
local elapsedSinceUpdate = 0
local UPDATE_INTERVAL = 0.1

-- The believed rage record, or nil when Hekili or its VirtualState is absent or the call fails.
local function readRage()
    local vs = Hekili and Hekili.VirtualState
    if type(vs) ~= "table" or type(vs.Power) ~= "function" then return nil end
    local ok, rec = pcall(vs.Power, 1, GetTime())
    if ok and type(rec) == "table" then return rec end
    return nil
end

-- A plain number, or nil (secret, absent or non-number, such as I.UNKNOWN).
local function plainNumber(v)
    if isSecret(v) or type(v) ~= "number" then return nil end
    return v
end

local function fmt(v)
    if isSecret(v) then return "S" end
    if type(v) == "number" then return string.format("%.1f", v) end
    return "n/a"
end

local function fmtText(v)
    if isSecret(v) then return "S" end
    if v == nil then return "-" end
    return tostring(v)
end

local function combatText(combat)
    if combat == 1 then return "combat" end
    return "ooc"
end

local function inCombat()
    if UnitAffectingCombat("player") then return 1 end
    return 0
end

local function markLine(i, m)
    local delta = "-"
    if m.est and m.bar then delta = string.format("%.1f", m.est - m.bar) end
    local bar = "-"
    if m.bar then bar = string.format("%.1f", m.bar) end
    return string.format("mark #%d est=%s bar=%s delta=%s %s %s", i, fmt(m.est), bar, delta, m.verdict,
        combatText(m.combat))
end

local function addMark(verdict, bar)
    ForeverProbeDB.marks = ForeverProbeDB.marks or {}
    local marks = ForeverProbeDB.marks
    local rec = readRage() or {}
    local m = {
        t = GetTime(),
        est = plainNumber(rec.est),
        lo = plainNumber(rec.lo),
        hi = plainNumber(rec.hi),
        basis = fmtText(rec.basis),
        combat = inCombat(),
        bar = plainNumber(bar),
        verdict = verdict,
    }
    marks[#marks + 1] = m
    VSCopy(markLine(#marks, m))
end

local function dump()
    local marks = ForeverProbeDB.marks or {}
    local sum, max, n = 0, 0, 0
    for i = 1, #marks do
        local m = marks[i]
        VSCopy(markLine(i, m))
        if m.est and m.bar then
            local d = math.abs(m.est - m.bar)
            sum, n = sum + d, n + 1
            if d > max then max = d end
        end
    end
    if n > 0 then
        VSCopy(string.format("vsmark: %d marks, %d with bar: mean |delta|=%.2f max |delta|=%.2f",
            #marks, n, sum / n, max))
    else
        VSCopy(string.format("vsmark: %d marks, none with bar", #marks))
    end
end

-- Rage change per second between consecutive marks that have a bar value (pairs with dt <= 0 are skipped).
local function rate()
    local marks = ForeverProbeDB.marks or {}
    local first, prev, prevIndex, last
    for i = 1, #marks do
        local m = marks[i]
        if m.bar then
            if prev then
                local dt = m.t - prev.t
                if dt > 0 then
                    local dbar = m.bar - prev.bar
                    VSCopy(string.format("rate %d->%d dt=%.1f dbar=%.1f rate=%.2f", prevIndex, i, dt, dbar, dbar / dt))
                end
            end
            first = first or m
            prev, prevIndex, last = m, i, m
        end
    end
    if first and last.t > first.t then
        VSCopy(string.format("overall rate=%.2f", (last.bar - first.bar) / (last.t - first.t)))
    else
        VSCopy("overall rate=n/a (fewer than two bar marks apart in time)")
    end
end

local function onUpdate(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate < UPDATE_INTERVAL then return end
    elapsedSinceUpdate = 0
    local rec = readRage()
    if rec then
        label:SetText(string.format("rage est=%s [%s-%s] %s %s", fmt(rec.est), fmt(rec.lo), fmt(rec.hi),
            fmtText(rec.basis), combatText(inCombat())))
    else
        label:SetText("rage est=n/a (no Hekili.VirtualState)")
    end
end

local function commitBox()
    local bar = tonumber(box:GetText())
    addMark("bar", bar)
    box:SetText("")
    box:ClearFocus()
end

local function savePosition(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    ForeverProbeDB.calibPos = { point, relPoint, x, y }
end

local function makeButton(text, verdict, xOffset)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(50, 22)
    b:SetPoint("BOTTOMLEFT", xOffset, 6)
    b:SetText(text)
    b:SetScript("OnClick", function() addMark(verdict, nil) end)
end

local function build()
    frame = CreateFrame("Frame", "ForeverProbeCalibFrame", UIParent)
    frame:SetSize(220, 70)
    local pos = ForeverProbeDB.calibPos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER", 0, 280) -- above the copy box
    end
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", savePosition)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)

    label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 6, -8)
    label:SetPoint("TOPRIGHT", -6, -8)
    label:SetJustifyH("LEFT")

    makeButton("pass", "pass", 6)
    makeButton("fail", "fail", 60)

    box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetSize(40, 20)
    box:SetPoint("BOTTOMLEFT", 124, 7)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetScript("OnEnterPressed", commitBox)
    box:SetScript("OnEscapePressed", box.ClearFocus)

    frame:SetScript("OnUpdate", onUpdate)
end

SLASH_VSMARK1 = "/vsmark"
SlashCmdList.VSMARK = function(msg)
    msg = strtrim(msg or "")
    local bar = tonumber(msg)
    if bar then
        addMark("bar", bar)
    elseif msg == "pass" or msg == "fail" then
        addMark(msg, nil)
    elseif msg == "clear" then
        ForeverProbeDB.marks = {}
        print("vsmark: cleared")
    elseif msg == "dump" then
        dump()
    elseif msg == "rate" then
        rate()
    elseif not frame then
        build()
    else
        frame:SetShown(not frame:IsShown())
    end
end
