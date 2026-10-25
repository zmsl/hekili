-- Copy.lua: a copy box for output that cannot be selected in chat.
--   VSCopy(...)      prints its arguments like print() and appends the line to the box (never opens it);
--   /vscopy          opens the box with the text selected (Ctrl+C copies; Escape closes it);
--   /vscopy clear    empties it.
-- Secret values are written as "S" (they cannot be concatenated or stored).
local ADDON_NAME, ns = ...

local isSecret = issecretvalue or function() return false end
local lines = {}
local frame, edit

local function build()
    frame = CreateFrame("Frame", "ForeverProbeCopyFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(760, 440)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.TitleText then frame.TitleText:SetText("ForeverProbe copy box: Ctrl+A, Ctrl+C") end

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(700)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() frame:Hide() end)
    scroll:SetScrollChild(edit)
    tinsert(UISpecialFrames, "ForeverProbeCopyFrame")
end

local function show()
    if not frame then build() end
    edit:SetText(table.concat(lines, "\n"))
    frame:Show()
    edit:SetFocus()
    edit:HighlightText()
end

function VSCopy(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        local v = select(i, ...)
        if isSecret(v) then parts[i] = "S" else parts[i] = tostring(v) end
    end
    local line = table.concat(parts, " ")
    lines[#lines + 1] = line
    print(line)
    if frame and frame:IsShown() then edit:SetText(table.concat(lines, "\n")) end
end

SLASH_VSCOPY1 = "/vscopy"
SlashCmdList.VSCOPY = function(msg)
    if msg == "clear" then
        wipe(lines)
        if frame then edit:SetText("") end
        print("vscopy: cleared")
    else
        show()
    end
end
