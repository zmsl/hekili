-- Cdm.lua: the Cooldown Manager reader behind the aura kind (Mode A: read-only). The client shows the player's chosen
-- auras on its Cooldown Manager; this file finds the items that show a watched aura and forwards what the client
-- writes into them to the aura kind's bars (Kinds/Aura.lua). It never shows, hides, fades, moves or refreshes
-- anything of the Cooldown Manager's and never calls its provider: it reads fields with rawget, enumerates the item
-- pools and post-hooks (hooksecurefunc, nothing replaced) three things, each once:
--   - a viewer's OnAcquireItemFrame (a new or reused item frame: hook it, read the layout again);
--   - an item's count FontString SetText: the stack count (a plain string out of combat, "" for one stack or none; a
--     secret number in combat; AuraBandProbe 0.2.0/0.2.1 on tracked bars, icons share the code);
--   - a tracked bar's StatusBar SetValue: the seconds left, every frame while the aura is up (secret in combat).
-- Presence is the item's auraInstanceID: nil when the aura is absent, set (secret in combat) when up (proven).
-- Identity: the catalogue (every cooldownID of categories 0-8 and the spells it names) is read out of combat only;
-- an item's cooldownID is read when it is used, so a reshuffle of the pooled frames (in combat too) is followed. A
-- secret cooldownID falls back to the item's layoutIndex in the order last read plain (inferred, unprobed); both
-- secret: that item is lost until the layout reads plain again (the end of combat).
-- Hook bodies and event handlers run under pcall; an error turns the aura kind off for the session (reason "error").
local lib = LibStub and LibStub("LibHiddenValues-1.0", true)
if not (lib and lib.loading) then
    return
end

-- 1 the Tracked Bars viewer, 2 the Tracked Buffs icons: a lower index outranks a higher one.
local VIEWERS = { "BuffBarCooldownViewer", "BuffIconCooldownViewer" }
local CATS = 8 -- Enum.CooldownViewerCategory: Essential 0 ... EquipSlotTracked 8

local cdm = lib.cdm or {}
lib.cdm = cdm
cdm.viewers = cdm.viewers or {} -- index -> viewer frame, once seen
cdm.vIndex = cdm.vIndex or {} -- viewer frame -> index
cdm.viewerOf = cdm.viewerOf or {} -- item frame -> its viewer's index (pool frames never change viewer)
cdm.itemOf = cdm.itemOf or {} -- a hooked FontString or StatusBar -> its item frame
cdm.hooked = cdm.hooked or {} -- item frame -> true once its widgets are hooked
cdm.order = cdm.order or { {}, {} } -- index -> layoutIndex -> cooldownID, as last read plain
cdm.byCd = cdm.byCd or {} -- cooldownID -> the item frame showing it now
cdm.placeOf = cdm.placeOf or {} -- cooldownID -> the index of the viewer showing it
cdm.cds = cdm.cds or {} -- spellID -> { cooldownID, ... }: the catalogue, read out of combat
cdm.stacksOn = cdm.stacksOn or {} -- cooldownID -> { source, ... } fed by its count text
cdm.leftOn = cdm.leftOn or {} -- cooldownID -> { source, ... } fed by its bar
cdm.nText, cdm.nValue, cdm.nRefused, cdm.nScan = cdm.nText or 0, cdm.nValue or 0, cdm.nRefused or 0, cdm.nScan or 0
cdm.dirty = true
cdm.off = cdm.off or false

-- Hook dispatchers: installed once per widget, they call through lib so a newer minor replaces the bodies.
lib.onCdmText = lib.onCdmText
    or function(fs, text)
        local ok, err = pcall(lib.cdmText, fs, text)
        if not ok then
            lib.cdmFail(err)
        end
    end
lib.onCdmValue = lib.onCdmValue
    or function(bar, v)
        local ok, err = pcall(lib.cdmValue, bar, v)
        if not ok then
            lib.cdmFail(err)
        end
    end
lib.onCdmAcquire = lib.onCdmAcquire
    or function(viewer, item)
        local ok, err = pcall(lib.cdmAcquire, viewer, item)
        if not ok then
            lib.cdmFail(err)
        end
    end

-- An error in a hook, an event or the resolve: the aura kind is off for the session (the others carry on).
function lib.cdmFail(err)
    lib.feeding = "aura"
    lib.fail(err)
end

local function child(t, a, b)
    local x = rawget(t, a)
    return type(x) == "table" and rawget(x, b) or nil
end

-- The viewer frame of index k, its acquire hook installed the first time it is seen.
function cdm.viewer(k)
    local v = cdm.viewers[k]
    if not v then
        v = _G[VIEWERS[k]]
        if type(v) ~= "table" or type(v.OnAcquireItemFrame) ~= "function" then
            return nil
        end
        cdm.viewers[k], cdm.vIndex[v] = v, k
        hooksecurefunc(v, "OnAcquireItemFrame", lib.onCdmAcquire)
    end
    return v
end

-- Hooks an item frame's count text and (a tracked bar) its bar, once.
function cdm.hook(item, k)
    if cdm.hooked[item] then
        return
    end
    cdm.hooked[item], cdm.viewerOf[item] = true, k
    local fs = child(item, "Applications", "Applications") or child(item, "Icon", "Applications")
    if fs then
        cdm.itemOf[fs] = item
        hooksecurefunc(fs, "SetText", lib.onCdmText)
    end
    local bar = rawget(item, "Bar")
    if type(bar) == "table" then
        cdm.itemOf[bar] = item
        hooksecurefunc(bar, "SetValue", lib.onCdmValue)
    end
end

-- The cooldownID an item shows now (plain), or nil.
function cdm.idOf(item)
    local id = rawget(item, "cooldownID")
    if not issecretvalue(id) then
        return id
    end
    local idx = rawget(item, "layoutIndex")
    if issecretvalue(idx) or idx == nil then
        return nil
    end
    local k = cdm.viewerOf[item]
    return k and cdm.order[k][idx]
end

-- Whether an item's data flows: its viewer is visible (a hidden viewer unregisters its events) and not in Edit Mode
-- (placeholder data; the field name is read from the client's code, unprobed).
function cdm.live(item)
    local v = cdm.viewers[cdm.viewerOf[item]]
    if not v then
        return false
    end
    local editing = rawget(v, "isEditing")
    if not issecretvalue(editing) and editing then
        return false
    end
    local vis = v:IsVisible()
    return issecretvalue(vis) or vis == true
end

-- Reads every active item of both viewers: hooks new frames, maps cooldownID -> item (any time, in combat too).
function cdm.scan()
    cdm.nScan, cdm.scanFrame = cdm.nScan + 1, lib.frameNo
    local byCd, placeOf = cdm.byCd, cdm.placeOf
    for cd in pairs(byCd) do
        byCd[cd], placeOf[cd] = nil, nil
    end
    local lost = 0
    for k = 1, #VIEWERS do
        local v = cdm.viewer(k)
        local pool = v and rawget(v, "itemFramePool")
        if pool then
            local order = cdm.order[k]
            for item in pool:EnumerateActive() do
                cdm.hook(item, k)
                local id, idx = rawget(item, "cooldownID"), rawget(item, "layoutIndex")
                if not issecretvalue(id) and not issecretvalue(idx) and id ~= nil and idx ~= nil then
                    order[idx] = id
                end
                local cd = cdm.idOf(item)
                if cd ~= nil and byCd[cd] == nil then
                    byCd[cd], placeOf[cd] = item, k
                elseif cd == nil and issecretvalue(id) then
                    lost = lost + 1 -- shows something, but which is secret
                end
            end
        end
    end
    cdm.lost = lost
end

local function note(cds, id, spell)
    if not issecretvalue(spell) and type(spell) == "number" and spell > 0 then
        local l = cds[spell]
        if not l then
            l = {}
            cds[spell] = l
        end
        if l[#l] ~= id then
            l[#l + 1] = id
        end
    end
end

-- The catalogue: every cooldownID the Cooldown Manager can show, by each spell it names (its spell, override,
-- tooltip override and linked spells). Out of combat only (in-combat secrecy of these reads is unprobed).
function cdm.catalogue()
    local CV = C_CooldownViewer
    local cds = {}
    for cat = 0, CATS do
        local ok, set = pcall(CV.GetCooldownViewerCategorySet, cat, true)
        if ok and not issecretvalue(set) and type(set) == "table" then
            for n = 1, #set do
                local id = set[n]
                if not issecretvalue(id) and id ~= nil then
                    local okI, info = pcall(CV.GetCooldownViewerCooldownInfo, id)
                    if okI and not issecretvalue(info) and type(info) == "table" then
                        note(cds, id, info.spellID)
                        note(cds, id, info.overrideSpellID)
                        note(cds, id, info.overrideTooltipSpellID)
                        local links = info.linkedSpellIDs
                        if not issecretvalue(links) and type(links) == "table" then
                            for j = 1, #links do
                                note(cds, id, links[j])
                            end
                        end
                    end
                end
            end
        end
    end
    cdm.cds, cdm.cataloged = cds, true
end

-- cdm-off: the cooldownViewerEnabled CVar is 0, the client says the viewer is not available, or neither viewer
-- exists. A secret or failed answer counts as on. A change re-syncs every kind (Kinds/Aura.lua reads cdm.off).
function cdm.checkOff()
    local off = false
    if C_CVar and C_CVar.GetCVarBool then
        local ok, on = pcall(C_CVar.GetCVarBool, "cooldownViewerEnabled")
        off = ok and not issecretvalue(on) and on == false
    end
    local ok, avail = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
    if ok and not issecretvalue(avail) and avail == false then
        off = true
    end
    if not (cdm.viewer(1) or cdm.viewer(2)) then
        off = true
    end
    if off ~= cdm.off then
        cdm.off = off
        lib.capChanged()
    end
end

-- The capability of an aura watch (spell, what) from the last reads: state, reason, cooldownID, viewer index.
function cdm.statusOf(spell, what)
    if not cdm.cataloged then
        return "pending"
    end
    local l = cdm.cds[spell]
    local cd, k
    for j = 1, l and #l or 0 do
        local p = cdm.placeOf[l[j]]
        if p and (not k or p < k) then
            cd, k = l[j], p
        end
    end
    if not cd then
        return "unavailable", l and "cdm-not-tracked" or "not-in-cdm"
    end
    if what == "left" and k == 2 then
        return "unavailable", "cdm-icon-only", cd, k
    end
    return "ready", nil, cd, k
end

local function clear(lists)
    for _, l in pairs(lists) do
        for j = #l, 1, -1 do
            l[j] = nil
        end
    end
end

local function relist(lists, cd, s)
    local l = lists[cd]
    if not l then
        l = {}
        lists[cd] = l
    end
    l[#l + 1] = s
end

-- Places every aura source from the last reads; a source whose answer changed is re-synced and its owners' capability
-- callbacks get (kind, state, reason, handle).
function cdm.place()
    local changed = false
    local srcs = lib.sources
    for n = 1, #srcs do
        local s = srcs[n]
        if s.kind == "aura" then
            local state, why, cd, k = cdm.statusOf(s.spell, s.what)
            if state == "ready" then
                state = nil
            end
            if cd ~= s.cd or k ~= s.place or state ~= s.cap or why ~= s.why or not s.placed then
                s.cd, s.place, s.cap, s.why, s.placed, s.moved = cd, k, state, why, true, true
                changed = true
            end
        end
    end
    if not changed then
        return
    end
    clear(cdm.stacksOn)
    clear(cdm.leftOn)
    for n = 1, #srcs do
        local s = srcs[n]
        if s.kind == "aura" and s.cd and not s.cap then
            if s.what == "stacks" then
                relist(cdm.stacksOn, s.cd, s)
            elseif s.what == "left" then
                relist(cdm.leftOn, s.cd, s)
            end
        end
    end
    for n = 1, #srcs do
        local s = srcs[n]
        if s.moved then
            s.moved = nil
            lib.sync(s)
            lib.auraTell(s)
        end
    end
end

-- Reads the Cooldown Manager again: its on/off state, the catalogue (out of combat), the items, then every source.
function cdm.resolve()
    cdm.dirty = false
    if not C_CooldownViewer then
        return -- capability "api"
    end
    cdm.checkOff()
    if cdm.off then
        return
    end
    if not InCombatLockdown() then
        cdm.catalogue()
    end
    cdm.scan()
    if cdm.lost == 0 then -- an item whose identity is secret may show any aura: the last answers stand
        cdm.place()
    end
end

-- A viewer acquired an item frame (a layout pass, in combat too). Its cooldownID is set later in the same pass, so
-- this only hooks the frame and asks for a read on the next frame.
function lib.cdmAcquire(viewer, item)
    local k = cdm.vIndex[viewer]
    if k then
        cdm.hook(item, k)
    end
    cdm.dirty = true
    lib.wake()
end

-- Pushes one value to every started bar of a source (a bar holding low for its priming drops it); a pushed bar now
-- follows the client (lib.barFed). A secret is passed on and never kept; a value a bar refuses (an unexpected shape)
-- is counted and dropped.
function lib.cdmPush(s, v)
    local prime, frames, fed = lib.barPrime, lib.barFrame, lib.barFed
    for _, i in pairs(s.bar) do
        if prime[i] == 0 then
            local f = frames[i]
            if pcall(f.SetValue, f, v) then
                if not fed[i] then
                    fed[i], s.dirty = true, true -- its band can be told now, also when the push changed nothing
                end
            else
                cdm.nRefused = cdm.nRefused + 1
            end
        end
    end
end

-- The count text of an item: "" (one stack or none) and plain digits out of combat, a secret number in combat.
function lib.cdmText(fs, text)
    local item = cdm.itemOf[fs]
    local id = item and cdm.idOf(item)
    local l = id ~= nil and cdm.stacksOn[id]
    if not l or #l == 0 then
        return
    end
    cdm.nText = cdm.nText + 1
    if not issecretvalue(text) then
        text = tonumber(text) or 0
    end
    for j = 1, #l do
        lib.cdmPush(l[j], text)
    end
end

-- A tracked bar's value: the seconds left (plain out of combat, secret in combat).
function lib.cdmValue(bar, v)
    local item = cdm.itemOf[bar]
    local id = item and cdm.idOf(item)
    local l = id ~= nil and cdm.leftOn[id]
    if not l or #l == 0 then
        return
    end
    cdm.nValue = cdm.nValue + 1
    for j = 1, #l do
        lib.cdmPush(l[j], v)
    end
end

-- Events that change what the Cooldown Manager shows or whether it runs (each registered under pcall: the client
-- raises on an event it does not have). CVAR_UPDATE only for the CVar the viewers follow.
cdm.EVENTS = {
    COOLDOWN_VIEWER_DATA_LOADED = true,
    COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED = true,
    COOLDOWN_VIEWER_TABLE_HOTFIXED = true,
    PLAYER_REGEN_ENABLED = true,
    PLAYER_LEVEL_CHANGED = true,
    CVAR_UPDATE = true,
}
if lib.evf then
    for ev in pairs(cdm.EVENTS) do
        pcall(lib.evf.RegisterEvent, lib.evf, ev)
    end
end

function lib.cdmEvent(event, arg)
    if event == "CVAR_UPDATE" and arg ~= "cooldownViewerEnabled" then
        return
    end
    cdm.dirty = true
    lib.wake()
end
