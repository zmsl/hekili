-- Grave.lua: counts Touch of the Grave procs (the Undead racial; "Call of the Grave" to players) per combat minute.
-- Always on from load: event registration only, nothing per frame. New file: restart the client once after pulling.
--   /vsgrave [report]  prints the counts, combat time and procs per minute through VSCopy, then the matched spell IDs;
--   /vsgrave reset     zeroes ForeverProbeDB.grave (an open combat segment restarts now).
-- Two channels, since whether the proc fires UNIT_SPELLCAST_SUCCEEDED is unverified:
--   procs: player cast-successes of 1260189 / 1260198 / 1260201, or of any spell whose name contains "Grave";
--   heals: player UNIT_COMBAT "HEAL" events in combat (a solo Undead Warrior is healed in combat only by the proc).
-- Live patch notes: 20% proc chance (30% for casters), 25 s internal cooldown, so the rate caps at 2.40 per minute.
-- procGap / healGap: the shortest interval between two consecutive counts on that channel (nil until two exist);
-- a heals gap well under 25 s means another heal source is mixed in, a procs gap near 25 s confirms the cooldown.
-- Forever has no combat log; every event argument goes through issecretvalue() first and a secret one is ignored.
local ADDON_NAME, ns = ... -- luacheck: ignore (the shared file header)

local isSecret = issecretvalue or function() return false end
local PROC_IDS = { [1260189] = true, [1260198] = true, [1260201] = true }
local EMPTY = { procs = 0, heals = 0, secs = 0, ids = {} }
local segStart -- GetTime() when the open combat segment began, nil out of combat
local lastProc, lastHeal -- GetTime() of the previous count per channel (not persisted: a /reload starts fresh)

-- ForeverProbeDB.grave, created on first write (not cached: /fprobe wipe or a reload may replace ForeverProbeDB).
local function state()
    ForeverProbeDB = ForeverProbeDB or {}
    local g = ForeverProbeDB.grave
    if not g then
        g = { procs = 0, heals = 0, secs = 0, ids = {} }
        ForeverProbeDB.grave = g
    end
    return g
end

local function isProc(spellID)
    if PROC_IDS[spellID] then return true end
    local name = C_Spell.GetSpellName(spellID)
    return not isSecret(name) and type(name) == "string" and name:find("Grave", 1, true) ~= nil
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, unit, a2, a3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if isSecret(unit) or unit ~= "player" or isSecret(a3) or type(a3) ~= "number" then return end
        if isProc(a3) then
            local g = state()
            g.procs = g.procs + 1
            g.ids[a3] = (g.ids[a3] or 0) + 1
            local now = GetTime()
            if lastProc and (not g.procGap or now - lastProc < g.procGap) then g.procGap = now - lastProc end
            lastProc = now
        end
    elseif event == "UNIT_COMBAT" then
        if segStart and not isSecret(unit) and unit == "player" and not isSecret(a2) and a2 == "HEAL" then
            local g = state()
            g.heals = g.heals + 1
            local now = GetTime()
            if lastHeal and (not g.healGap or now - lastHeal < g.healGap) then g.healGap = now - lastHeal end
            lastHeal = now
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if not segStart then segStart = GetTime() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if segStart then
            local g = state()
            g.secs = g.secs + (GetTime() - segStart)
            segStart = nil
        end
    elseif event == "PLAYER_LOGIN" then
        if not segStart and UnitAffectingCombat("player") then segStart = GetTime() end
    end
end)
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
frame:RegisterUnitEvent("UNIT_COMBAT", "player")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_LOGIN")

local function ppm(n, secs)
    if secs < 1 then return "n/a" end
    return string.format("%.2f", n / (secs / 60))
end

local function gap(v)
    if v then return string.format("%.1fs", v) end
    return "-"
end

local function report()
    local g = (ForeverProbeDB and ForeverProbeDB.grave) or EMPTY
    local secs = g.secs
    if segStart then secs = secs + (GetTime() - segStart) end -- the open segment, left open
    VSCopy(string.format("grave: procs=%d heals=%d combat=%02d:%02d ppm(procs)=%s ppm(heals)=%s cap=2.40",
        g.procs, g.heals,
        math.floor(secs / 60), math.floor(secs % 60), ppm(g.procs, secs), ppm(g.heals, secs)))
    VSCopy(string.format("grave gaps: procs=%s heals=%s", gap(g.procGap), gap(g.healGap)))
    local keys = {}
    for id in pairs(g.ids) do keys[#keys + 1] = id end
    table.sort(keys)
    if #keys == 0 then
        VSCopy("grave ids: none")
        return
    end
    local line = "grave ids: "
    for i = 1, #keys do
        local part = keys[i] .. "=" .. g.ids[keys[i]]
        if i > 1 then
            if #line + #part > 240 then -- keep each copy-box line under 255 chars
                VSCopy(line)
                line = "grave ids: " .. part
            else
                line = line .. ", " .. part
            end
        else
            line = line .. part
        end
    end
    VSCopy(line)
end

SLASH_VSGRAVE1 = "/vsgrave"
SlashCmdList.VSGRAVE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "report" then
        report()
    elseif msg == "reset" then
        local g = state()
        g.procs, g.heals, g.secs, g.ids, g.procGap, g.healGap = 0, 0, 0, {}, nil, nil
        lastProc, lastHeal = nil, nil
        if segStart then segStart = GetTime() end -- keep the segment open, counted from the reset
        print("vsgrave: reset")
    else
        print("vsgrave: /vsgrave [report] | reset")
    end
end
