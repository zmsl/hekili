-- Slash.lua: /lhv, the diagnostic command (a slash command needs no TOC, so it works embedded too), and the copy box
-- (chat cannot be copied in the client). Last file of the list: it ends the load and, after login (a late or upgraded
-- copy), realises at once.
--   /lhv                                   version, bars, capability per kind
--   /lhv selftest | test                   the self-test now, PASS / FAIL lines
--   /lhv stats                             GetStats, and one line per source
--   /lhv watch <kind> <unit> [edges...] [mana|energy|rage]   an ad-hoc watch printing every sink call
--   /lhv watch off                         releases the ad-hoc watches
--   /lhv copy                              everything /lhv printed this session, in a box to copy from
--   /lhv off | on                          the kill switch for this session
local lib = LibStub and LibStub("LibHiddenValues-1.0", true)
if not (lib and lib.loading) then
    return
end

local format = string.format
local OWNER = "/lhv"
local TITLE = "LibHiddenValues: Ctrl+A, Ctrl+C" -- English only: a developer tool
local ORDER =
    { "health", "power", "cooldown", "charges", "cast", "totem", "loc", "bool", "aura", "threat", "absorb", "meter" }
local POWER = { mana = "Mana", energy = "Energy", rage = "Rage", focus = "Focus" }

lib.log = lib.log or {}

function lib.say(msg)
    local log = lib.log
    log[#log + 1] = msg
    if #log > 500 then
        table.remove(log, 1)
    end
    print("|cff66ccffLibHiddenValues|r: " .. msg)
end
local say = lib.say

local function capText(kind)
    local _, state, reason = lib:IsAvailable(kind)
    return reason and (state .. " (" .. reason .. ")") or state
end

local function status()
    local major, minor = lib:GetVersion()
    say(
        format(
            "%s minor %d; bars %d in use, %d made; %.1f us per frame",
            major,
            minor,
            (lib:GetStats()),
            #lib.barFrame,
            lib.usAvg
        )
    )
    local others = {}
    for i = 3, #ORDER do
        local _, _, reason = lib:IsAvailable(ORDER[i])
        others[#others + 1] = reason == "unproven" and ORDER[i] or (ORDER[i] .. " " .. capText(ORDER[i]))
    end
    say("not built yet (unproven): " .. table.concat(others, ", "))
    say(format("health %s; power %s", capText("health"), capText("power")))
end

local function stats()
    local bars, us, peak, push, fire, desync, level = lib:GetStats()
    say(
        format(
            "bars %d, %.1f us per frame (peak %.1f), %.0f pushes/s, %.1f firings/s, desyncs %d, level %d",
            bars,
            us,
            peak,
            push,
            fire,
            desync,
            level
        )
    )
    for i = 1, #lib.sources do
        local s = lib.sources[i]
        if #s.handles > 0 then
            local n = 0
            for _ in pairs(s.bar) do
                n = n + 1
            end
            say(
                format(
                    "%s %s: %d handles, %d bars, %s",
                    s.kind,
                    s.unit,
                    #s.handles,
                    n,
                    s.active and "fed every frame" or "not fed"
                )
            )
        end
    end
end

local function watch(args)
    if args[2] == "off" then
        lib:ReleaseAll(OWNER)
        return say("ad-hoc watches released")
    end
    local spec = { kind = args[2], unit = args[3], edges = {} }
    for i = 4, #args do
        local n = tonumber(args[i])
        if n then
            spec.edges[#spec.edges + 1] = n
        elseif POWER[args[i]] and Enum and Enum.PowerType then
            spec.power = Enum.PowerType[POWER[args[i]]]
        end
    end
    local label = tostring(args[2]) .. " " .. tostring(args[3])
    local h, err = lib:Watch(OWNER, spec, function(handle, lo, hi, dir, t, q)
        if lo == nil then
            say(format("%s unknown (%s)", label, tostring((handle:State()))))
        else
            say(format("%s %g-%g dir %d q %d t %.3f", label, lo, hi, dir, q, t))
        end
    end)
    if not h then
        return say(err .. "; usage: /lhv watch <health|power> <player|target> <edges...> [mana|energy]")
    end
    say(format("watching %s: %s", label, tostring((h:State()))))
end

local frame, edit
local function copy()
    if not frame then
        frame = CreateFrame("Frame", "LibHiddenValuesCopyFrame", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(760, 440)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        if frame.TitleText then
            frame.TitleText:SetText(TITLE)
        end
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(700)
        edit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            frame:Hide()
        end)
        scroll:SetScrollChild(edit)
        table.insert(UISpecialFrames, "LibHiddenValuesCopyFrame")
    end
    edit:SetText(table.concat(lib.log, "\n"))
    frame:Show()
    edit:SetFocus()
    edit:HighlightText()
end

function lib.slash(msg)
    local args = {}
    for w in tostring(msg or ""):lower():gmatch("%S+") do
        args[#args + 1] = w
    end
    local cmd = args[1] or ""
    if cmd == "" then
        status()
    elseif cmd == "selftest" or cmd == "test" then
        say("self-test running")
        lib:SelfTest(function(_, lines)
            for i = 1, #lines do
                say(lines[i])
            end
        end)
    elseif cmd == "stats" then
        stats()
    elseif cmd == "watch" then
        watch(args)
    elseif cmd == "copy" then
        copy()
    elseif cmd == "off" then
        lib:SetEnabled(false)
        say("off for this session (/lhv on)")
    elseif cmd == "on" then
        lib:SetEnabled(true)
        say("on: pending until the self-test passes")
    else
        say("/lhv [selftest | stats | watch <kind> <unit> <edges...> | watch off | copy | off | on]")
    end
end

SLASH_LIBHIDDENVALUES1 = "/lhv"
SlashCmdList.LIBHIDDENVALUES = function(msg)
    lib.slash(msg)
end

lib.loading = nil
if IsLoggedIn and IsLoggedIn() then
    lib.realise()
end
