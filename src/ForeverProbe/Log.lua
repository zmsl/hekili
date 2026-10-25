-- Log.lua: an on/off event recorder (/vslog) with a live view of the last 10 records.
-- New file: restart the client once after pulling (a /reload does not load a file new to the TOC).
--   /vslog on          start recording (and show the frame); /vslog off stops it (records kept, frame hidden);
--   /vslog dump        every record through VSCopy, oldest first, then "vslog n=<records> dropped=<n> events=<list>";
--   /vslog clear       empty the buffer and reset the clock;
--   /vslog add EVENT [EVENT ...]   register more events (kept until /reload); /vslog events prints the list;
--   /vslog note TEXT   add a "<ms> NOTE TEXT" record (an annotation on the same clock as the events);
--   /vslog auras [unit] every HELPFUL and HARMFUL aura the client lets us read on the unit (default target;
--                      "targetplate" = the nameplate token that names the target), one
--                      copy-box line each: name, spellId, stacks, duration, expiration, source, dispel type, stealable,
--                      instance id (secrets as S), then a summary line; not recorded in the ring;
--   /vslog plates      one "<ms> PLATES nameplateN <unit line> combat|ooc dead=<S|bool> attack=<S|bool>" record per
--                      visible plate (U5: whether plate GUIDs and death are plain in combat);
--   /vslog meter [type] one C_DamageMeter read of the Current session (default 0 DamageDone): METER, METER_SRC (<=8),
--                      METER_SPELLS and METER_SPELL (<=12, our source); "/vslog meter watch" records METER_PLAIN after the
--                      next PLAYER_REGEN_ENABLED; "events" adds the DAMAGE_METER_* events; "dur" GetSessionDurationSeconds;
--   /vslog cdv [sub]   Cooldown Manager probe (rawget + widget getters only): CDV status (availability, CVar, ids
--                      per category); "ids" CDV_ID per cooldown id (out of combat, every id and linked id); "frames"
--                      CDV_FRAME per viewer item; "aura" CDV_AURA/CDV_DUR for plain auraInstanceIDs; "watch"
--                      OnShow/OnHide -> CDV_SHOW/HIDE; "target" CDV_TGT (target items' auraInstanceID and auraDataUnit
--                      at each PLAYER_TARGET_CHANGED and the 3 frames after, until /reload); "poll" toggles CDV_EDGE
--                      (every 0.25 s, an item whose auraInstanceID, auraDataUnit or shown state changed);
--   /vslog gate health|power|off  GC-T, the threshold bank (Gate.lua): GATE_* records;
--   /vslog auto on [probe ...]|off|status|dump [probe]|clear   passive probes saved to ForeverProbeDB.auto (see Auto);
--   /vslog show|hide   the frame alone (drag to move; position kept in ForeverProbeDB.logPos).
-- Default events: PLAYER_SWING, UNIT_COMBAT, UNIT_SPELLCAST_SUCCEEDED, every unit token (duplicates expected), and
-- PLAYER_TARGET_CHANGED, written as a TARGET line describing the new target (see DESCRIBE / unitLine).
-- PH-NI: a player UNIT_SPELLCAST_SUCCEEDED and a target UNIT_COMBAT within 50 ms of each other (either order) add
-- "<ms> PAIR cast=<spellID> dt=<row - cast ms> row=<the row's record>".
-- Record: "<ms> <event> a b c d f" (UNIT_SPELLCAST_X printed as SC_X), ms from debugprofilestop() relative to the first record; a secret
-- argument is "S", anything else tostring(). Ring buffer of 4000 (oldest dropped and counted). Memory only.
-- Hekili snapshots: each one (keybind or /hekili snapshot) adds, to the ring and to the snapshot's "## External"
-- block, one "vsbars" line per Hekili-tracked resource plus player health: game time, the belief's est (lo-hi) conf
-- basis +regen/s (VsBars.lua's text) and whether the live read is secret or plain (never the live value itself).
local ADDON_NAME, ns = ... -- luacheck: ignore (the shared file header)

local isSecret = issecretvalue or function() return false end
local format = string.format
local MAX, SHOWN = 4000, 10
local events = { "PLAYER_SWING", "UNIT_COMBAT", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_TARGET_CHANGED" }
local short = {} -- event -> its printed name, built once per event so the handler allocates only the record
local records = {}
local n, pos, dropped = 0, 1, 0 -- records held, next write slot, records overwritten
local t0 -- debugprofilestop() of the first record, nil until then
local recording = false
local frame, view = nil, {}
local meterCommand -- defined after the recorder (it records through push)
local autoSkip, autoAfter -- the auto probes' recorder hooks, defined with them (nil until then)
local auto -- the armed probe set while /vslog auto runs, else nil
local seq, flushed = 0, 0 -- records pushed since the last clear, and the last one auto saved
local PAIR_MS = 50
local lastCast, lastCastId, lastRow, lastRowRec = -1e9, nil, -1e9, nil

local function str(v)
    if isSecret(v) then return "S" end
    return tostring(v)
end

local function refresh()
    if not frame or not frame:IsShown() then return end
    for i = SHOWN, 1, -1 do
        local back = SHOWN - i
        if back < n then
            view[i]:SetText(records[(pos - 2 - back) % MAX + 1])
        else
            view[i]:SetText("")
        end
    end
end

local function savePosition(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    ForeverProbeDB = ForeverProbeDB or {}
    ForeverProbeDB.logPos = { point, relPoint, x, y }
end

local function build()
    frame = CreateFrame("Frame", "ForeverProbeLogFrame", UIParent)
    frame:SetSize(520, SHOWN * 14 + 8)
    local pos0 = ForeverProbeDB and ForeverProbeDB.logPos
    if pos0 then
        frame:SetPoint(pos0[1], UIParent, pos0[2], pos0[3], pos0[4])
    else
        frame:SetPoint("CENTER", 0, -200)
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

    for i = 1, SHOWN do -- the client ships no monospace font; the chat font it is
        local s = frame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
        s:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 14)
        s:SetWidth(508)
        s:SetJustifyH("LEFT")
        s:SetWordWrap(false)
        view[i] = s
    end
    frame:Hide()
end

local function show()
    if not frame then build() end
    frame:Show()
    refresh()
end

local function push(rec)
    if n == MAX then dropped = dropped + 1 else n = n + 1 end
    seq = seq + 1
    records[pos] = rec
    pos = pos % MAX + 1
    refresh()
end

-- UNIT_AURA (once added): "<ms> AURA <unit> full=<bool> added=<n> updated=<n> removed=<n> first: name=.. id=.. inst=.. dur=..
-- exp=.. src=.. harm=.." with the first added aura's fields, secrets as S (probe: do the counts stay plain in combat).
-- Unit lines: PLAYER_TARGET_CHANGED (and, once added, FOCUS, SOFT_ENEMY, SOFT_INTERACT and the plate events) write
-- "<ms> <LABEL> <name> L<level> <classification> <creature type> hp=<health>/<max> react=<reaction> player=<bool>
-- guid=<guid>", or "<ms> <LABEL> none"; a plate line carries its token after the label; any secret field prints "S".
local function unitLine(now, label, token)
    if not UnitExists(token) then return format("%d %s none", now - t0, label) end
    local function get(fn, ...)
        local ok, v = pcall(fn, ...)
        return ok and str(v) or "err"
    end
    return format("%d %s %s L%s %s %s hp=%s/%s react=%s player=%s guid=%s", now - t0, label,
        get(UnitName, token), get(UnitLevel, token), get(UnitClassification, token),
        get(UnitCreatureType, token), get(UnitHealth, token), get(UnitHealthMax, token),
        get(UnitReaction, token, "player"), get(UnitIsPlayer, token), get(UnitGUID, token))
end

-- Events answered with a unit line instead of their raw arguments: the label and the token to describe (a function of
-- the first argument for the plate events, whose payload is the token).
local DESCRIBE = {
    PLAYER_TARGET_CHANGED = { "TARGET", "target" },
    PLAYER_FOCUS_CHANGED = { "FOCUS", "focus" },
    PLAYER_SOFT_ENEMY_CHANGED = { "SOFTENEMY", "softenemy" },
    PLAYER_SOFT_INTERACT_CHANGED = { "SOFTINTERACT", "softinteract" },
    NAME_PLATE_UNIT_ADDED = { "PLATE+", function(a) return a end },
    NAME_PLATE_UNIT_REMOVED = { "PLATE-", function(a) return a end },
}

local recorder = CreateFrame("Frame")
recorder:SetScript("OnEvent", function(_, event, a, b, c, d, f)
    local now = debugprofilestop()
    if not t0 then t0 = now end
    if auto and autoSkip(event, now, a, b) then return end
    if event == "UNIT_AURA" then -- the update table: counts plain or not, and which fields of an added aura are secret
        local info = b
        if type(info) ~= "table" then
            return push(format("%d AURA %s info=%s", now - t0, str(a), str(info)))
        end
        local added, updated, removed = info.addedAuras, info.updatedAuraInstanceIDs, info.removedAuraInstanceIDs
        local function n(x)
            if isSecret(x) then return "S" end
            return type(x) == "table" and tostring(#x) or tostring(x)
        end
        local first = type(added) == "table" and not isSecret(added) and added[1] or nil
        local detail = ""
        if type(first) == "table" then
            detail = format(" first: name=%s id=%s inst=%s dur=%s exp=%s src=%s harm=%s", str(first.name), str(first.spellId),
                str(first.auraInstanceID), str(first.duration), str(first.expirationTime), str(first.sourceUnit), str(first.isHarmful))
        end
        return push(format("%d AURA %s full=%s added=%s updated=%s removed=%s%s", now - t0, str(a), str(info.isFullUpdate),
            n(added), n(updated), n(removed), detail))
    end
    local desc = DESCRIBE[event] -- not `d`: that is the event's fourth argument
    if desc then
        local token = type(desc[2]) == "function" and desc[2](a) or desc[2]
        if type(token) ~= "string" then token = "none" end
        push(unitLine(now, desc[1] .. (type(desc[2]) == "function" and (" " .. token) or ""), token))
    else
        local rec = format("%d %s %s %s %s %s %s", now - t0, short[event], str(a), str(b), str(c), str(d), str(f))
        push(rec)
        local unit = not isSecret(a) and a
        if event == "UNIT_COMBAT" and unit == "target" then
            lastRow, lastRowRec = now, rec
            if now - lastCast <= PAIR_MS then
                push(format("%d PAIR cast=%s dt=%d row=%s", now - t0, str(lastCastId), now - lastCast, rec):sub(1, 250))
            end
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
            lastCast, lastCastId = now, c
            if now - lastRow <= PAIR_MS then
                push(format("%d PAIR cast=%s dt=%d row=%s", now - t0, str(c), lastRow - now, lastRowRec):sub(1, 250))
            end
        end
    end
    if auto then autoAfter(event, now, a) end
end)

local function register(event)
    local ok, err = pcall(recorder.RegisterEvent, recorder, event)
    if ok then short[event] = (event:gsub("^UNIT_SPELLCAST_", "SC_")) end
    return ok, err
end

local function start(quiet)
    if recording then return end
    recording = true
    for i = 1, #events do
        local ok, err = register(events[i])
        if not ok then print("vslog: cannot register " .. events[i] .. ": " .. tostring(err)) end
    end
    if not quiet then show() end
    print("vslog: recording " .. table.concat(events, ","))
end

local function stop()
    recording = false
    recorder:UnregisterAllEvents()
    if frame then frame:Hide() end
    print(format("vslog: stopped, %d records", n))
end

local function addEvents(text)
    for event in text:upper():gmatch("%S+") do
        local have = false
        for i = 1, #events do
            if events[i] == event then have = true end
        end
        if have then
            print("vslog: already have " .. event)
        else
            local ok, err = register(event)
            if not ok then
                print("vslog: cannot register " .. event .. ": " .. tostring(err))
            else
                if not recording then recorder:UnregisterEvent(event) end -- registered only to validate the name
                events[#events + 1] = event
                print("vslog: added " .. event)
            end
        end
    end
end

-- /vslog meter (DamageMeter probe, docs/research/2026-10-23-damagemeter-api.md in the hekili repo, probes 3-6).
-- Every value is "name=value" when plain and "name=secret" when secret; a secret is never compared, formatted or
-- measured. Every API call is pcalled; a failure records "METER_ERR <message>" (or "METER_ERR secret").
local SESSION_CURRENT = 1 -- Enum.DamageMeterSessionType.Current
local METER_DAMAGE_DONE = 0 -- Enum.DamageMeterType.DamageDone (7 DamageTaken, 10 EnemyDamageTaken)
local MAX_SOURCES, MAX_SPELLS, LINE = 8, 12, 250

local function stamp()
    local now = debugprofilestop()
    if not t0 then t0 = now end
    return now - t0
end

-- Records a line, split into "+"-prefixed continuation records so each stays under the copy box's 255 characters.
local function emit(line)
    push(line:sub(1, LINE))
    for i = LINE + 1, #line, LINE - 1 do push("+" .. line:sub(i, i + LINE - 2)) end
end

local function val(name, v)
    if isSecret(v) then return " " .. name .. "=secret" end
    return " " .. name .. "=" .. tostring(v)
end

-- "#name=N" for a list field: secret table, secret length, missing, or the plain length.
local function len(name, t)
    if isSecret(t) then return " #" .. name .. "=secret(table)" end
    if type(t) ~= "table" then return " #" .. name .. "=" .. type(t) end
    local ok, l = pcall(function() return #t end)
    if not ok then return " #" .. name .. "=err" end
    if isSecret(l) then return " #" .. name .. "=secret" end
    return " #" .. name .. "=" .. l
end

local function meterErr(where, err)
    emit(format("%d METER_ERR %s %s", stamp(), where, isSecret(err) and "secret" or tostring(err)))
end

local function call(where, fn, ...)
    local ok, r = pcall(fn, ...)
    if not ok then meterErr(where, r) return nil end
    return r, true
end

-- combatSpellDetails: documented as one DamageMeterCombatSpellUnitDetails, possibly a list; record which and the first.
local function detailsShape(d)
    if isSecret(d) then return " details=secret" end
    if type(d) ~= "table" then return " details=" .. type(d) end
    local first, shape = d, "struct"
    local d1 = d[1]
    if isSecret(d1) or d1 ~= nil then first, shape = d1, "list" end
    local out = " details=" .. shape .. (shape == "list" and len("details", d) or "")
    if isSecret(first) or type(first) ~= "table" then return out .. " first=" .. (isSecret(first) and "secret" or type(first)) end
    return out .. val("unitName", first.unitName) .. val("amount", first.amount) .. val("unitClass", first.unitClassFilename)
        .. val("classification", first.classification) .. val("isPet", first.isPet) .. val("isMob", first.isMob)
end

local function meterSpells(meterType, src)
    local guid = src.sourceGUID
    if isSecret(guid) or type(guid) ~= "string" then guid = UnitGUID("player") end -- never pass a secret back
    if isSecret(guid) then return emit(format("%d METER_SPELLS skipped guid=secret", stamp())) end
    local ss = call("source", C_DamageMeter.GetCombatSessionSourceFromType, SESSION_CURRENT, meterType, guid)
    if ss == nil then return end
    if isSecret(ss) or type(ss) ~= "table" then
        return emit(format("%d METER_SPELLS sessionSource=%s", stamp(), isSecret(ss) and "secret" or type(ss)))
    end
    local spells = ss.combatSpells
    emit(format("%d METER_SPELLS", stamp()) .. val("totalAmount", ss.totalAmount) .. val("maxAmount", ss.maxAmount)
        .. len("combatSpells", spells))
    if isSecret(spells) or type(spells) ~= "table" then return end
    for i = 1, MAX_SPELLS do
        local sp = spells[i]
        if not isSecret(sp) and sp == nil then break end
        if isSecret(sp) or type(sp) ~= "table" then
            emit(format("%d METER_SPELL i=%d entry=%s", stamp(), i, isSecret(sp) and "secret" or type(sp)))
        else
            emit(format("%d METER_SPELL i=%d", stamp(), i) .. val("spellID", sp.spellID) .. val("amount", sp.totalAmount)
                .. val("aps", sp.amountPerSecond) .. val("overkill", sp.overkillAmount) .. val("name", sp.creatureName)
                .. detailsShape(sp.combatSpellDetails))
        end
    end
end

local function meterRead(meterType)
    local combat = InCombatLockdown() and "combat" or "ooc"
    local s = call("session", C_DamageMeter.GetCombatSessionFromType, SESSION_CURRENT, meterType)
    if isSecret(s) or type(s) ~= "table" then
        return emit(format("%d METER type=%d %s session=%s", stamp(), meterType, combat, isSecret(s) and "secret" or type(s)))
    end
    local sources = s.combatSources
    emit(format("%d METER type=%d %s", stamp(), meterType, combat) .. val("totalAmount", s.totalAmount)
        .. val("maxAmount", s.maxAmount) .. val("durationSeconds", s.durationSeconds) .. len("combatSources", sources))
    if isSecret(sources) or type(sources) ~= "table" then return end
    local ours
    for i = 1, MAX_SOURCES do
        local src = sources[i]
        if not isSecret(src) and src == nil then break end
        if isSecret(src) or type(src) ~= "table" then
            emit(format("%d METER_SRC i=%d entry=%s", stamp(), i, isSecret(src) and "secret" or type(src)))
        else
            emit(format("%d METER_SRC i=%d", stamp(), i) .. val("isLocalPlayer", src.isLocalPlayer)
                .. val("class", src.classFilename) .. val("classification", src.classification)
                .. val("display", src.sourceDisplayType) .. val("creatureID", src.sourceCreatureID)
                .. val("guid", src.sourceGUID) .. val("name", src.name) .. val("total", src.totalAmount)
                .. val("aps", src.amountPerSecond) .. val("deathTime", src.deathTimeSeconds))
            if not isSecret(src.isLocalPlayer) and src.isLocalPlayer == true then ours = src end
        end
    end
    if ours then meterSpells(meterType, ours) else emit(format("%d METER_SPELLS none (no plain isLocalPlayer source)", stamp())) end
end

-- Our DamageDone source's totalAmount: "plain", "secret", or nil when the read fails or finds no local-player source.
local function ourTotal()
    local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, SESSION_CURRENT, METER_DAMAGE_DONE)
    if not ok or isSecret(s) or type(s) ~= "table" or isSecret(s.combatSources) or type(s.combatSources) ~= "table" then return end
    for _, src in ipairs(s.combatSources) do
        if not isSecret(src) and type(src) == "table" and not isSecret(src.isLocalPlayer) and src.isLocalPlayer == true then
            local v = src.totalAmount
            if isSecret(v) then return "secret" end
            return "plain", v
        end
    end
end

local watcher, ticker = CreateFrame("Frame"), nil
watcher:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local regen, tries = debugprofilestop(), 0
    emit(format("%d METER_WATCH regen", stamp()))
    local function try()
        tries = tries + 1
        local state, v = ourTotal()
        local since = debugprofilestop() - regen
        if state == "plain" then
            emit(format("%d METER_PLAIN %d total=%s tries=%d", stamp(), since, tostring(v), tries))
        elseif since >= 5000 then
            emit(format("%d METER_PLAIN none tries=%d last=%s", stamp(), tries, state or "noread"))
        else
            return
        end
        if ticker then ticker:Cancel() ticker = nil end
        return true
    end
    if try() then return end
    ticker = C_Timer.NewTicker(0.25, try, 21)
end)

meterCommand = function(arg)
    if not C_DamageMeter then return print("vslog: no C_DamageMeter on this client") end
    local sub = arg:lower()
    if sub == "watch" then
        if ticker then ticker:Cancel() ticker = nil end
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        emit(format("%d METER_WATCH armed", stamp()))
        print("vslog: meter watch armed for the next PLAYER_REGEN_ENABLED")
    elseif sub == "events" then
        addEvents("DAMAGE_METER_COMBAT_SESSION_UPDATED DAMAGE_METER_CURRENT_SESSION_UPDATED DAMAGE_METER_RESET"
            .. " ADDON_RESTRICTION_STATE_CHANGED") -- DM-I: the instance restriction state next to the groups
    elseif sub == "dur" then
        local d, ok = call("dur", C_DamageMeter.GetSessionDurationSeconds, SESSION_CURRENT)
        if ok then
            emit(format("%d METER_DUR %s", stamp(), InCombatLockdown() and "combat" or "ooc") .. val("durationSeconds", d))
        end
    else
        local t = sub == "" and METER_DAMAGE_DONE or tonumber(arg) or (Enum.DamageMeterType and Enum.DamageMeterType[arg])
        if type(t) ~= "number" then return print("vslog: /vslog meter [type number|DamageDone|DamageTaken|EnemyDamageTaken...] | watch | events | dur") end
        meterRead(t)
        print("vslog: meter type " .. t .. " recorded")
    end
end

-- /vslog cdv (Cooldown Manager probe, docs/research/2026-10-23-cooldown-manager-api.md in the hekili repo, section 5).
-- SAFETY: the viewers' item frames are read with rawget and the widget getters (IsShown, GetCooldownTimes, GetValue,
-- GetText) only; none of the viewer's own methods is called and nothing is written into its tables, so its secure
-- combat refresh never runs on a table our tainted code touched. Values print as in /vslog meter (name=value|secret).
local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local hooked = {} -- item frame -> true once HookScript'd (hooks persist until /reload)

local function cdvErr(where, err)
    emit(format("%d CDV_ERR %s %s", stamp(), where, isSecret(err) and "secret" or tostring(err)))
end

-- pcall(fn, ...) returning up to two results, or nil after a CDV_ERR record.
local function cdvCall(where, fn, ...)
    if type(fn) ~= "function" then return cdvErr(where, "n/a") end
    local ok, a, b = pcall(fn, ...)
    if not ok then return cdvErr(where, a) end
    return a, b
end

-- rawget a chain of keys; nil (never an error) when a link is secret or not a table.
local function raw(t, k1, k2)
    if isSecret(t) or type(t) ~= "table" then return nil end
    local v = rawget(t, k1)
    if k2 == nil then return v end
    return raw(v, k2)
end

-- " name=<method result>" for a widget child; "name=none" when the child is missing.
local function widget(name, w, method, idx)
    if isSecret(w) or (type(w) ~= "table" and type(w) ~= "userdata") or type(w[method]) ~= "function" then
        return " " .. name .. "=none"
    end
    local ok, a, b = pcall(w[method], w)
    if not ok then return " " .. name .. "=err" end
    if idx == 2 then return val(name, a) .. val(name .. "Dur", b) end
    return val(name, a)
end

local function cdvStatus()
    local avail, reason = cdvCall("avail", C_CooldownViewer.IsCooldownViewerAvailable)
    local cvar = cdvCall("cvar", (C_CVar and C_CVar.GetCVar) or GetCVar, "cooldownViewerEnabled")
    local line = format("%d CDV", stamp()) .. val("avail", avail) .. val("reason", reason) .. val("cvar", cvar)
        .. val("combat", InCombatLockdown())
    for c = 0, 8 do
        line = line .. len("c" .. c, cdvCall("cat" .. c, C_CooldownViewer.GetCooldownViewerCategorySet, c, false))
            .. len("c" .. c .. "all", cdvCall("cat" .. c, C_CooldownViewer.GetCooldownViewerCategorySet, c, true))
    end
    emit(line)
end

local function cdvIds()
    if InCombatLockdown() then return emit(format("%d CDV_ERR in-combat", stamp())) end
    local S = C_Secrets or {}
    for c = 0, 8 do
        local ids = cdvCall("cat" .. c, C_CooldownViewer.GetCooldownViewerCategorySet, c, true)
        if isSecret(ids) then emit(format("%d CDV_ID c=%d ids=secret", stamp(), c)) end
        for j = 1, (not isSecret(ids) and type(ids) == "table") and #ids or 0 do
            local id = ids[j]
            local line = format("%d CDV_ID c=%d", stamp(), c) .. val("id", id)
            local info = not isSecret(id) and cdvCall("info", C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
            if isSecret(info) or type(info) ~= "table" then
                line = line .. " info=" .. (isSecret(info) and "secret" or tostring(info))
            else
                local sid = info.spellID
                line = line .. val("spellID", sid) .. val("override", info.overrideSpellID)
                    .. val("overrideTooltip", info.overrideTooltipSpellID) .. val("spellCategoryID", info.spellCategoryID)
                    .. len("linked", info.linkedSpellIDs) .. val("selfAura", info.selfAura) .. val("hasAura", info.hasAura)
                    .. val("charges", info.charges) .. val("isKnown", info.isKnown) .. val("isInvisible", info.isInvisible)
                    .. val("flags", info.flags) .. val("category", info.category) .. val("equipSlot", info.equipSlot)
                    .. val("buffSlot", info.buffSlot)
                local linked = info.linkedSpellIDs
                if not isSecret(linked) and type(linked) == "table" then
                    for k = 1, #linked do line = line .. val("linked" .. k, linked[k]) end
                end
                if isSecret(sid) or sid == nil then
                    line = line .. " cdSecrecy=n/a auraSecrecy=n/a"
                else
                    line = line .. (S.GetSpellCooldownSecrecy and val("cdSecrecy", cdvCall("cdSecrecy", S.GetSpellCooldownSecrecy, sid)) or " cdSecrecy=n/a")
                        .. (S.GetSpellAuraSecrecy and val("auraSecrecy", cdvCall("auraSecrecy", S.GetSpellAuraSecrecy, sid)) or " auraSecrecy=n/a")
                end
            end
            emit(line)
        end
    end
end

-- Calls fn(viewerName, k, item, arg) for each active item frame (layoutIndex set) of each viewer; quiet skips the
-- "missing" records (the periodic callers).
local function eachItem(fn, arg, quiet)
    for _, name in ipairs(VIEWERS) do
        local v = _G[name]
        if type(v) ~= "table" or type(v.GetChildren) ~= "function" then
            if not quiet then emit(format("%d CDV_FRAME viewer=%s missing", stamp(), name)) end
        else
            local kids = { pcall(v.GetChildren, v) }
            if not kids[1] then cdvErr("children " .. name, kids[2]) end
            local k = 0
            for i = 2, kids[1] and #kids or 0 do
                local item = kids[i]
                local li = raw(item, "layoutIndex")
                if isSecret(li) or li ~= nil then
                    k = k + 1
                    fn(name, k, item, arg)
                end
            end
        end
    end
end

local function itemFrame(name, k, item)
    local okS, shown = pcall(item.IsShown, item)
    emit(format("%d CDV_FRAME viewer=%s i=%d", stamp(), name, k) .. (okS and val("shown", shown) or " shown=err")
        .. val("isActive", raw(item, "isActive")) .. val("auraInstanceID", raw(item, "auraInstanceID"))
        .. val("auraSpellID", raw(item, "auraSpellID")) .. val("auraDataUnit", raw(item, "auraDataUnit"))
        .. val("cooldownIsActive", raw(item, "cooldownIsActive")) .. val("isOnGCD", raw(item, "isOnGCD"))
        .. val("cooldownID", raw(item, "cooldownID")) .. val("spellID", raw(item, "cooldownInfo", "spellID"))
        .. val("overrideSpellID", raw(item, "cooldownInfo", "overrideSpellID")) .. val("layout", raw(item, "layoutIndex"))
        .. widget("cd", raw(item, "Cooldown"), "GetCooldownTimes", 2) .. widget("cdShown", raw(item, "Cooldown"), "IsShown")
        .. widget("bar", raw(item, "Bar"), "GetValue")
        .. widget("charges", raw(item, "ChargeCount", "Current"), "GetText")
        .. widget("stacks", raw(item, "Applications", "Applications"), "GetText") -- BuffIcon items
        .. widget("barStacks", raw(item, "Icon", "Applications"), "GetText")) -- BuffBar items
end

local AURA_FIELDS = { "name", "spellId", "applications", "duration", "expirationTime", "sourceUnit", "isHarmful",
    "isHelpful", "isFromPlayerOrPlayerPet", "charges", "maxCharges", "dispelName", "timeMod", "icon" }

local function itemAura(name, k, item)
    local id = raw(item, "auraInstanceID")
    if isSecret(id) or id == nil then return end
    local unit = raw(item, "auraDataUnit")
    if isSecret(unit) or type(unit) ~= "string" then unit = "player" end
    local head = format("%d CDV_AURA viewer=%s i=%d unit=%s id=%s", stamp(), name, k, unit, tostring(id))
    local a = cdvCall("auraData", C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
    if isSecret(a) or type(a) ~= "table" then
        emit(head .. " data=" .. (isSecret(a) and "secret" or tostring(a)))
    else
        local line = head
        for _, f in ipairs(AURA_FIELDS) do line = line .. val(f, a[f]) end
        emit(line)
    end
    local d = cdvCall("auraDuration", C_UnitAuras.GetAuraDuration, unit, id)
    if isSecret(d) or type(d) ~= "table" and type(d) ~= "userdata" then
        return emit(format("%d CDV_DUR viewer=%s i=%d duration=%s", stamp(), name, k, isSecret(d) and "secret" or type(d)))
    end
    emit(format("%d CDV_DUR viewer=%s i=%d", stamp(), name, k) .. widget("hasSecret", d, "HasSecretValues")
        .. widget("remaining", d, "GetRemainingDuration"))
end

local function itemWatch(name, k, item)
    if hooked[item] then return end
    local okP, prot = pcall(item.IsProtected, item)
    if not okP or isSecret(prot) or prot then
        return emit(format("%d CDV_WATCH unsafe viewer=%s i=%d", stamp(), name, k))
    end
    local function on(label)
        return function(self)
            emit(format("%d %s viewer=%s i=%d", stamp(), label, name, k) .. val("cooldownID", raw(self, "cooldownID"))
                .. val("spellID", raw(self, "cooldownInfo", "spellID")) .. val("auraInstanceID", raw(self, "auraInstanceID")))
        end
    end
    local ok, err = pcall(item.HookScript, item, "OnShow", on("CDV_SHOW"))
    if ok then ok, err = pcall(item.HookScript, item, "OnHide", on("CDV_HIDE")) end
    if not ok then return cdvErr("hook " .. name, err) end
    hooked[item] = true
    emit(format("%d CDV_WATCH hooked viewer=%s i=%d", stamp(), name, k))
end

-- CDM-O: a target item (auraDataUnit "target", or secret) at frame f after PLAYER_TARGET_CHANGED.
local function itemTarget(name, k, item, f)
    local unit = raw(item, "auraDataUnit")
    if not isSecret(unit) and unit ~= "target" then return end
    emit(format("%d CDV_TGT f=%d viewer=%s i=%d", stamp(), f, name, k) .. val("auraInstanceID", raw(item, "auraInstanceID"))
        .. val("auraDataUnit", unit) .. val("spellID", raw(item, "cooldownInfo", "spellID")))
end

local tgtFrame, tgtF = CreateFrame("Frame"), 0
tgtFrame:Hide()
tgtFrame:SetScript("OnUpdate", function(self)
    tgtF = tgtF + 1
    eachItem(itemTarget, tgtF, true)
    if tgtF >= 3 then self:Hide() end
end)

local function targetChanged()
    eachItem(itemTarget, 0, true)
    tgtF = 0
    tgtFrame:Show()
end

local cdvTgtWatch = CreateFrame("Frame")
cdvTgtWatch:SetScript("OnEvent", function() if not auto then targetChanged() end end) -- auto calls it itself

-- CDM-E: every item's auraInstanceID, auraDataUnit and shown state, recorded on change.
local edge = {} -- item -> its last signature
local function itemPoll(name, k, item)
    local okS, shown = pcall(item.IsShown, item)
    local sig = str(raw(item, "auraInstanceID")) .. "/" .. str(raw(item, "auraDataUnit")) .. "/" .. (okS and str(shown) or "err")
    if edge[item] ~= sig then
        edge[item] = sig
        emit(format("%d CDV_EDGE viewer=%s i=%d %s", stamp(), name, k, sig) .. val("spellID", raw(item, "cooldownInfo", "spellID")))
    end
end
local pollTicker
local function cdvPoll(on)
    if pollTicker then pollTicker:Cancel() pollTicker = nil end
    if on then pollTicker = C_Timer.NewTicker(0.25, function() eachItem(itemPoll, nil, true) end) end
end

local function cdvCommand(arg)
    if not C_CooldownViewer then return emit(format("%d CDV avail=n/a (no C_CooldownViewer)", stamp())) end
    local sub = arg:lower()
    if sub == "" then
        cdvStatus()
    elseif sub == "ids" then
        cdvIds()
    elseif sub == "frames" then
        eachItem(itemFrame)
    elseif sub == "aura" then
        eachItem(itemAura)
    elseif sub == "watch" then
        eachItem(itemWatch)
    elseif sub == "target" then
        cdvTgtWatch:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif sub == "poll" then
        cdvPoll(not pollTicker)
        return print("vslog: cdv poll " .. (pollTicker and "on" or "off"))
    else
        return print("vslog: /vslog cdv [ids|frames|aura|watch|target|poll]")
    end
    print("vslog: cdv " .. (sub == "" and "status" or sub) .. " recorded")
end

-- /vslog auto: passive probes, armed across reloads and logins (ForeverProbeDB.auto.armed), that save each fight's
-- records to ForeverProbeDB.auto (the game writes it at /reload and logout). Probes and the ledger rows they serve:
--   swing   PLAYER_SWING, UNIT_COMBAT (player, target, pet, and nameplate tokens except WOUND rows), our own casts, PAIR,
--           TARGET and PLATE+/- lines, combat start and end, HCOMBAT (Hekili's state.combat and the VirtualState line at
--           combat start and one frame later): PHS1, PH-MP, PH-ED, PH-NI, U13, U14, U15, U16-U18;
--   meter   the DAMAGE_METER_* and ADDON_RESTRICTION_STATE_CHANGED events, one meter read 3 s into each fight,
--           METER_PLAIN after it, meter 0 and 10 six seconds after: DM-P, DM-PET, DM-FL, DM-I;
--   cdv     CDV status and OnShow/OnHide hooks at each world entry, the uncapped ids once per session, CDV_EDGE in combat,
--           CDV_TGT at each target change, CDV_FRAME 2 s into each fight: CDM-E, CDM-O, CDM-P, CDM-I, CDM-R, CDM-C;
--   snap    Hekili.Virtual.State.Snapshot() six seconds after each fight, one SNAP record per line: U16-U18, PH-NI, DM-M;
--   usable  (Warrior) USABLE at each change of IsSpellUsable(Execute) in combat, with ms since the last swing and the last
--           target row: U12;
--   gate    GC-T for the session's first fight (health, from the first target row in combat) and its second (power).
-- FIGHT start/end and WORLD records carry the context: party size, instance type, shown and hostile plates.
-- Saved 6 s after combat ends (or at the next pull, logout, or /vslog auto off): ForeverProbeDB.auto =
--   { armed = { <probe> = true }, total = <lines held>, order = { { <session>, <probe> } per saved fight, oldest first },
--     sessions = { [<name>-<realm>-<build>-<YYYYmmdd-HHMMSS>] = { name, realm, build, class, login = time(),
--       probes = { [<probe>] = { { t = time(), reason = "fight"|"logout"|"off", lost = <ring drops>, cut = <over cap>,
--         lines = { "<ms> KIND ...", ... } }, ... } } } } }
-- FIGHT, NOTE, TARGET and WORLD lines go to every probe saved in that flush. Past LIMIT lines the oldest fight goes.
-- Lines are the ring's strings: a secret is always "S" or "secret", never stored.
local PROBES = { "swing", "meter", "cdv", "snap", "usable", "gate" }
local LIMIT, FIGHT_CAP = 22000, 4000 -- about 1.7 MB at 75 bytes a line
local AUTO_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }
local METER_EVENTS = { "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET",
    "ADDON_RESTRICTION_STATE_CHANGED" }
local SHARED = { FIGHT = true, NOTE = true, TARGET = true, WORLD = true }
local PLATE, PLATE_SET = {}, {}
for i = 1, 40 do
    PLATE[i] = "nameplate" .. i
    PLATE_SET[PLATE[i]] = true
end
local sessionKey, sessionMeta
local inCombat, endPending, endGen, fightGen, gateStage, idsDone = false, false, 0, 0, 0, false
local lastSwing = -1e9
local EXECUTE -- the Warrior's Execute (localised name, or the rank 1 id), nil when usable is not armed

local function autoDB()
    ForeverProbeDB = ForeverProbeDB or {}
    local A = ForeverProbeDB.auto
    if type(A) ~= "table" then
        A = {}
        ForeverProbeDB.auto = A
    end
    A.sessions, A.order, A.total = A.sessions or {}, A.order or {}, A.total or 0
    return A
end

local function context()
    local okG, group = pcall(GetNumGroupMembers)
    local okI, _, inst = pcall(IsInInstance)
    local plates, hostile = 0, 0
    for i = 1, 40 do
        local e = UnitExists(PLATE[i])
        if not isSecret(e) and e then
            plates = plates + 1
            local ok, can = pcall(UnitCanAttack, "player", PLATE[i])
            if ok and not isSecret(can) and can then hostile = hostile + 1 end
        end
    end
    return format("party=%s inst=%s plates=%d hostile=%d", okG and str(group) or "err", okI and str(inst) or "err",
        plates, hostile)
end

local function probeOf(kind)
    if kind:find("^METER") or kind:find("^DAMAGE_METER") or kind == "ADDON_RESTRICTION_STATE_CHANGED" then return "meter" end
    if kind:find("^CDV") then return "cdv" end
    if kind:find("^GATE") then return "gate" end
    if kind == "SNAP" or kind == "vsbars" then return "snap" end
    if kind == "USABLE" then return "usable" end
    return "swing"
end

-- Saves the records pushed since the last flush, one fight entry per probe that recorded any.
local function flush(reason)
    if not sessionKey or seq <= flushed then
        flushed = seq
        return
    end
    local A = autoDB()
    local S = A.sessions[sessionKey]
    if not S then
        S = sessionMeta
        S.probes = {}
        A.sessions[sessionKey] = S
    end
    local from, lost = flushed + 1, 0
    if seq - flushed > n then lost, from = seq - flushed - n, seq - n + 1 end
    flushed = seq
    local buckets, shared, probe = {}, {}, "swing"
    for q = from, seq do
        local rec = records[(q - 1) % MAX + 1]
        if rec:sub(1, 1) ~= "+" then -- a "+" line continues the line before it
            local kind = rec:match("^%S+ (%S+)") or ""
            probe = not SHARED[kind] and probeOf(kind) or nil
        end
        if probe == nil then
            shared[#shared + 1] = rec
            for _, b in pairs(buckets) do b[#b + 1] = rec end
        else
            local b = buckets[probe]
            if not b then
                b = {}
                for i = 1, #shared do b[i] = shared[i] end
                buckets[probe] = b
            end
            b[#b + 1] = rec
        end
    end
    local saved, total = {}, 0
    for _, name in ipairs(PROBES) do
        local b = buckets[name]
        if b then
            local cut = math.max(0, #b - FIGHT_CAP)
            for i = #b, FIGHT_CAP + 1, -1 do b[i] = nil end
            S.probes[name] = S.probes[name] or {}
            local list = S.probes[name]
            list[#list + 1] = { t = time(), reason = reason, lost = lost, cut = cut, lines = b }
            A.order[#A.order + 1] = { sessionKey, name }
            A.total, total = A.total + #b, total + #b
            saved[#saved + 1] = name
        end
    end
    while A.total > LIMIT and #A.order > 1 do
        local o = table.remove(A.order, 1)
        local sess = A.sessions[o[1]]
        local list = sess and sess.probes and sess.probes[o[2]]
        local f = list and table.remove(list, 1)
        if f then A.total = A.total - #f.lines end
        if list and #list == 0 then
            sess.probes[o[2]] = nil
            if next(sess.probes) == nil and o[1] ~= sessionKey then A.sessions[o[1]] = nil end
        end
    end
    if total > 0 then print(format("ForeverProbe: saved %d records for %s", total, table.concat(saved, ","))) end
end

local function vsSnapshot()
    local vs = Hekili and Hekili.Virtual and Hekili.Virtual.State
    if type(vs) ~= "table" or type(vs.Snapshot) ~= "function" then return nil, "no Hekili.Virtual.State.Snapshot" end
    local ok, text = pcall(vs.Snapshot)
    if not ok then return nil, tostring(text) end
    if isSecret(text) or type(text) ~= "string" then return nil, "not a string" end
    return text
end

-- PH-ED: Hekili's state.combat (rawget, no metamethods) and the VirtualState line (combat=...) at combat start.
local function hcombat(label)
    local st, v = Hekili and Hekili.State, nil
    if type(st) == "table" then v = rawget(st, "combat") end
    local line = format("%d HCOMBAT %s state.combat=%s now=%.3f", stamp(), label, str(v), GetTime())
    if label == "next" then
        local text = vsSnapshot()
        if text then line = line .. " | " .. text:match("^[^\n]*") end
    end
    emit(line)
end
local function hcombatNext() hcombat("next") end

local function snapshot()
    local text, err = vsSnapshot()
    if not text then return emit(format("%d SNAP none %s", stamp(), err)) end
    for line in text:gmatch("[^\n]+") do emit(format("%d SNAP %s", stamp(), line)) end
end

-- U12: IsSpellUsable(Execute) every frame in combat, a record on each change (no allocation between changes).
local usableFrame, usableLast = CreateFrame("Frame"), -1
usableFrame:Hide()
usableFrame:SetScript("OnUpdate", function()
    local ok, u, p = pcall(C_Spell.IsSpellUsable, EXECUTE)
    local s
    if not ok then
        s = 9
    elseif isSecret(u) or isSecret(p) then
        s = 8
    else
        s = (u and 2 or 0) + (p and 1 or 0)
    end
    if s ~= usableLast then
        usableLast = s
        local now = debugprofilestop()
        push(format("%d USABLE execute=%s power=%s swing+%d row+%d", stamp(), ok and str(u) or "err", ok and str(p) or "err",
            now - lastSwing, now - lastRow))
    end
end)

local function finish()
    if not endPending then return end
    endPending = false
    if auto.meter and C_DamageMeter then
        meterRead(METER_DAMAGE_DONE)
        meterRead(10) -- EnemyDamageTaken
    end
    if auto.snap then snapshot() end
    if auto.cdv and C_CooldownViewer and not InCombatLockdown() then eachItem(itemWatch, nil, true) end
    flush("fight")
end

local function fightStart(now)
    if endPending then finish() end
    inCombat = true
    fightGen = fightGen + 1
    local g = fightGen
    push(format("%d FIGHT start %s", now - t0, context()))
    if auto.swing then
        hcombat("event")
        C_Timer.After(0, hcombatNext)
    end
    if auto.meter and C_DamageMeter then
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED") -- METER_PLAIN after this fight
        C_Timer.After(3, function() if g == fightGen and inCombat then meterRead(METER_DAMAGE_DONE) end end)
    end
    if auto.cdv and C_CooldownViewer then
        cdvPoll(true)
        C_Timer.After(2, function() if g == fightGen and inCombat then eachItem(itemFrame) end end)
    end
    if EXECUTE then
        usableLast = -1
        usableFrame:Show()
    end
end

local function fightEnd(now)
    inCombat = false
    push(format("%d FIGHT end %s", now - t0, context()))
    if auto.cdv then cdvPoll(false) end
    usableFrame:Hide()
    if ns.Gate and ns.Gate.Running() then
        ns.Gate.Stop()
        gateStage = gateStage + 1
    end
    endPending = true
    endGen = endGen + 1
    local g = endGen
    C_Timer.After(6, function() if g == endGen then finish() end end)
end

-- true drops the event (auto keeps one row per hit: no duplicate tokens, no party casts, no plate WOUND rows).
autoSkip = function(event, now, a, b)
    if event == "PLAYER_SWING" then
        lastSwing = now
    elseif event == "UNIT_COMBAT" then
        if isSecret(a) or a == "player" or a == "target" or a == "pet" then return false end
        if PLATE_SET[a] then return not isSecret(b) and b == "WOUND" end
        return true
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        return isSecret(a) or a ~= "player"
    end
    return false
end

autoAfter = function(event, now, a)
    if event == "PLAYER_REGEN_DISABLED" then
        fightStart(now)
    elseif event == "PLAYER_REGEN_ENABLED" then
        fightEnd(now)
    elseif event == "PLAYER_TARGET_CHANGED" then
        if auto.cdv and C_CooldownViewer then targetChanged() end
    elseif event == "UNIT_COMBAT" and auto.gate and inCombat and gateStage < 2 and ns.Gate and not ns.Gate.Running()
        and not isSecret(a) and a == "target" then
        ns.Gate.Start(gateStage == 0 and "health" or "power", emit, stamp)
        if not ns.Gate.Running() then gateStage = 2 end -- no curve API: do not retry on every row
    end
end

local function worldCdv()
    if not auto or not auto.cdv or not C_CooldownViewer or InCombatLockdown() then return end
    cdvStatus()
    if not idsDone then
        idsDone = true
        cdvIds()
    end
    eachItem(itemWatch, nil, true)
end

local function want(list)
    for _, e in ipairs(list) do
        local have = false
        for i = 1, #events do
            if events[i] == e then have = true end
        end
        if not have then
            events[#events + 1] = e
            if recording then register(e) end
        end
    end
end

local autoFrame = CreateFrame("Frame")

local function autoStart()
    local A = autoDB()
    auto = A.armed
    local name, realm = UnitName("player"), GetRealmName()
    local _, buildNo = GetBuildInfo()
    local _, class = UnitClass("player")
    sessionKey = format("%s-%s-%s-%s", str(name), str(realm), str(buildNo), date("%Y%m%d-%H%M%S"))
    sessionMeta = { name = str(name), realm = str(realm), build = str(buildNo), class = str(class), login = time() }
    flushed = seq -- records from before arming are not saved
    inCombat = InCombatLockdown() and true or false
    want(AUTO_EVENTS)
    if auto.meter then want(METER_EVENTS) end
    EXECUTE = nil
    if auto.usable and class == "WARRIOR" then
        local info = C_Spell.GetSpellInfo(5308)
        EXECUTE = 5308
        if type(info) == "table" and not isSecret(info.name) and type(info.name) == "string" then EXECUTE = info.name end
    end
    start(true)
    autoFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    autoFrame:RegisterEvent("PLAYER_LOGOUT")
    local names = {}
    for _, p in ipairs(PROBES) do
        if auto[p] then names[#names + 1] = p end
    end
    print("vslog auto: armed " .. table.concat(names, ",") .. " (session " .. sessionKey .. ")")
end

local function autoStop()
    if not auto then return end
    flush("off")
    if ns.Gate then ns.Gate.Stop() end
    cdvPoll(false)
    usableFrame:Hide()
    auto, sessionKey, EXECUTE = nil, nil, nil
    autoFrame:UnregisterAllEvents()
    autoFrame:RegisterEvent("PLAYER_LOGIN")
    stop()
end

autoFrame:RegisterEvent("PLAYER_LOGIN")
autoFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local A = ForeverProbeDB and ForeverProbeDB.auto
        if type(A) == "table" and type(A.armed) == "table" and next(A.armed) then autoStart() end
    elseif not auto then
        return
    elseif event == "PLAYER_LOGOUT" then
        if endPending then finish() else flush("logout") end
    elseif event == "PLAYER_ENTERING_WORLD" then
        push(format("%d WORLD %s", stamp(), context()))
        C_Timer.After(2, worldCdv)
    end
end)

local function autoCommand(arg)
    local sub, rest = arg:match("^(%S*)%s*(.-)$")
    sub = sub:lower()
    local A = autoDB()
    if sub == "on" then
        local armed = {}
        for p in (rest == "" and table.concat(PROBES, " ") or rest:lower()):gmatch("%S+") do
            local known = false
            for _, q in ipairs(PROBES) do
                if q == p then known = true end
            end
            if known then armed[p] = true else print("vslog auto: unknown probe " .. p) end
        end
        if not next(armed) then return end
        autoStop()
        A.armed = armed
        autoStart()
        worldCdv()
    elseif sub == "off" then
        autoStop()
        A.armed = nil
        print("vslog auto: off")
    elseif sub == "status" then
        local S = sessionKey and A.sessions[sessionKey]
        local parts = {}
        for _, p in ipairs(PROBES) do
            local list = S and S.probes and S.probes[p]
            if list then
                local l = 0
                for _, f in ipairs(list) do l = l + #f.lines end
                parts[#parts + 1] = format("%s=%d/%d", p, #list, l)
            end
        end
        local sessions = 0
        for _ in pairs(A.sessions) do sessions = sessions + 1 end
        print(format("vslog auto: %s session=%s recording=%s pending=%d saved(fights/lines) %s; db %d/%d lines, %d sessions",
            auto and "armed" or "off", tostring(sessionKey), tostring(recording), seq - flushed,
            #parts > 0 and table.concat(parts, " ") or "none", A.total, LIMIT, sessions))
    elseif sub == "dump" then
        local S = sessionKey and A.sessions[sessionKey]
        if not S or not S.probes then return print("vslog auto: nothing saved in this session") end
        for _, p in ipairs(PROBES) do
            if (rest == "" or rest:lower() == p) and S.probes[p] then
                for i, f in ipairs(S.probes[p]) do
                    VSCopy(format("== %s fight %d at %s reason=%s lost=%d cut=%d lines=%d", p, i, date("%H:%M:%S", f.t),
                        f.reason, f.lost, f.cut, #f.lines))
                    for _, line in ipairs(f.lines) do VSCopy(line) end
                end
            end
        end
    elseif sub == "clear" then
        A.sessions, A.order, A.total = {}, {}, 0
        print("vslog auto: saved records cleared")
    else
        print("vslog: /vslog auto on [swing meter cdv snap usable gate] | off | status | dump [probe] | clear")
    end
end

SLASH_VSLOG1 = "/vslog"
SlashCmdList.VSLOG = function(msg)
    local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "on" then
        start()
    elseif cmd == "off" then
        stop()
    elseif cmd == "dump" then
        local first = (n < MAX) and 1 or pos
        for i = 0, n - 1 do VSCopy(records[(first - 1 + i) % MAX + 1]) end
        VSCopy(format("vslog n=%d dropped=%d events=%s", n, dropped, table.concat(events, ",")))
    elseif cmd == "clear" then
        wipe(records)
        n, pos, dropped, t0, seq, flushed = 0, 1, 0, nil, 0, 0
        refresh()
        print("vslog: cleared")
    elseif cmd == "add" and arg ~= "" then
        addEvents(arg)
    elseif cmd == "meter" then
        meterCommand(arg)
    elseif cmd == "cdv" then
        cdvCommand(arg)
    elseif cmd == "gate" then -- GC-T (Gate.lua)
        local m = arg:lower()
        if not ns.Gate then return print("vslog: Gate.lua not loaded (restart the client once)") end
        if m == "off" then
            ns.Gate.Stop()
        elseif m == "health" or m == "power" then
            ns.Gate.Start(m, emit, stamp)
        else
            return print("vslog: /vslog gate health|power|off")
        end
        print("vslog: gate " .. m)
    elseif cmd == "auto" then
        autoCommand(arg)
    elseif cmd == "plates" then -- U5: every visible plate's unit line plus the plain/secret state of its GUID and death
        local now = debugprofilestop()
        if not t0 then t0 = now end
        local combat = InCombatLockdown() and "combat" or "ooc"
        local shown = 0
        for i = 1, 40 do
            local token = "nameplate" .. i
            if UnitExists(token) then
                shown = shown + 1
                local okD, dead = pcall(UnitIsDead, token)
                local okA, att = pcall(UnitCanAttack, "player", token)
                push(format("%s %s dead=%s attack=%s", unitLine(now, "PLATES " .. token, token), combat,
                    okD and str(dead) or "err", okA and str(att) or "err"))
            end
        end
        print(format("vslog: %d plates logged (%s)", shown, combat))
    elseif cmd == "auras" then -- the auras the client lets us see on a unit, one copy-box line each
        local unit = arg ~= "" and arg or "target"
        if unit == "targetplate" then -- the nameplate token that names our target, if one is shown
            unit = nil
            for i = 1, 40 do
                local token = "nameplate" .. i
                local ok, same = pcall(UnitIsUnit, "target", token)
                if ok and same == true then unit = token break end
            end
            if not unit then return print("vslog: the target has no nameplate (or UnitIsUnit is secret)") end
            print("vslog: target plate is " .. unit)
        end
        if not UnitExists(unit) then return print("vslog: no unit " .. unit) end
        local combat = InCombatLockdown() and "combat" or "ooc"
        local total = 0
        for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
            local i = 0
            while true do
                i = i + 1
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
                if not ok or not a then
                    if not ok then VSCopy(format("%s %s #%d err=%s", unit, filter, i, tostring(a))) end
                    break
                end
                total = total + 1
                VSCopy(format("%s %s #%d name=%s id=%s stacks=%s dur=%s exp=%s src=%s dispel=%s steal=%s inst=%s", unit, filter, i,
                    str(a.name), str(a.spellId), str(a.applications), str(a.duration), str(a.expirationTime),
                    str(a.sourceUnit), str(a.dispelName), str(a.isStealable), str(a.auraInstanceID)))
            end
        end
        VSCopy(format("%s auras=%d %s now=%.3f guid=%s", unit, total, combat, GetTime(), str(UnitGUID(unit))))
        print(format("vslog: %d auras on %s copied (%s)", total, unit, combat))
    elseif cmd == "note" and arg ~= "" then
        local now = debugprofilestop()
        if not t0 then t0 = now end
        push(format("%d NOTE %s", now - t0, arg))
    elseif cmd == "events" then
        print("vslog events: " .. table.concat(events, ","))
    elseif cmd == "show" then
        show()
    elseif cmd == "hide" then
        if frame then frame:Hide() end
    else
        print("vslog: /vslog on | off | dump | clear | add EVENT [EVENT ...] | note TEXT | plates | meter [type|watch|events|dur] | cdv [ids|frames|aura|watch|target|poll] | gate health|power|off | auto on|off|status|dump|clear | auras [unit] | events | show | hide")
    end
end

-- Hekili snapshot subscriber (Hekili:RegisterSnapshotListener, central fix 20).
local NAMES = { [0] = "mana", [1] = "rage", [2] = "focus", [3] = "energy", [4] = "combo", [6] = "runic" }
local HEALTH = -1

local function beliefLine(vs, kind, now)
    local rec, rate, ok, v
    if kind == HEALTH then
        rec, rate = vs.Health("player", now), 0
        ok, v = pcall(UnitHealth, "player")
    else
        rec, rate = vs.Power(kind, now), vs.Regen(kind, now).est
        ok, v = pcall(UnitPower, "player", kind)
    end
    local read = not ok and "failed" or isSecret(v) and "secret" or "plain" -- v itself is never formatted
    local name = kind == HEALTH and "health" or NAMES[kind] or ("type " .. kind)
    return format("%.3f vsbars %s %.2f (%.2f-%.2f) %.2f %s %+.2f/s %s %s", now, name, rec.est, rec.lo, rec.hi,
        rec.conf, tostring(rec.basis):sub(1, 40), rate, InCombatLockdown() and "combat" or "ooc", read)
end

local function onSnapshot(index)
    local vs = Hekili and Hekili.Virtual and Hekili.Virtual.State
    if type(vs) ~= "table" or type(vs.Power) ~= "function" then return "vsbars: no Hekili.Virtual.State" end
    local kinds, now = {}, GetTime()
    local okT, c = pcall(vs.Tracked, "resource", kinds)
    local count = okT and c or 0
    kinds[count + 1] = HEALTH
    local lines = { format("%.3f vsbars snapshot %d", now, index) }
    for i = 1, count + 1 do
        local ok, line = pcall(beliefLine, vs, kinds[i], now)
        lines[#lines + 1] = ok and line or ("vsbars error: " .. tostring(line)):sub(1, 200)
    end
    for i = 1, #lines do push(lines[i]) end
    return table.concat(lines, "\n")
end

local function subscribe()
    if Hekili and Hekili.RegisterSnapshotListener then
        Hekili:RegisterSnapshotListener(onSnapshot)
        return true
    end
end

if not subscribe() then
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:SetScript("OnEvent", function(self, _, name)
        if name == "Hekili" then
            if not subscribe() then print("vslog: this Hekili has no RegisterSnapshotListener") end
            self:UnregisterAllEvents()
        end
    end)
end
