-- Managed.lua: Mode B, the managed Cooldown Manager layout. With the player's consent (the consumer's button), the
-- library adds ONE layout of its own to the Cooldown Manager's store, named after the consumer (owner): a copy of the
-- active layout with every watched aura's entry on a tracked bar (a bar gives up, stacks and seconds left). It is
-- written raw with C_CooldownViewer.SetLayoutData and takes effect after the player reloads (the consumer calls
-- ReloadUI from its own click; the library never does). After the reload the library checks the result; while it holds
-- the four viewers sit at alpha 0 (their data keeps flowing; proven in game, ledger L1608). Restore puts the player's
-- layouts back: byte-exact when nothing else changed, else only our layout is removed.
--
-- Never called: the client's settings provider, layout manager or serializer (they taint). The store format, proven
-- in game (CDMConfigProbe route B, L1596): "1|" .. base64(deflate(cbor(t))); t[1] the save version, t[2] the active
-- layout id per tag (class ID * 10 + spec), t[3][tag][id] a layout ({ [1] order, [2] { [category] = { cooldownID, ...
-- } }, ... }), t[4][id] its name; at most 5 layouts; a new id is the largest + 1.
--
-- The library keeps no SavedVariables: the consumer's table (its SavedVariablesPerCharacter) holds the saved original
-- and the state across reloads; the consumer hands it over at every load (SetCooldownManagerStore). Its fields are
-- the library's (orig, tag, id, name, lay, prev, bars, pending, state, bad): persist the table, never edit it.
--
-- Our layout is recognised by its id, our name AND the content we wrote (name, lay), never by the id alone: the client
-- gives a new layout the largest id + 1, so a layout the player makes after deleting ours takes our id. After an
-- update, the content before it (prev) counts too until a check passes: the client may write that one back.
local lib = LibStub and LibStub("LibHiddenValues-1.0", true)
if not (lib and lib.loading) then
    return
end

local cdm = lib.cdm
local VIEWERS =
    { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local MAXL = 5 -- layouts in the store, every tag together
local CHECK = 20 -- seconds out of combat after the reload for the check to pass
local RECHECK = 30 -- frames between reads while the check waits

local mb = lib.mb or {}
lib.mb = mb
mb.mode = mb.mode or "player"
mb.told = mb.told or "player:" -- the last mode the callbacks heard ("player" with no reason is never told)

local E = lib.ERR
E.STORE_INVALID = "store-invalid"
E.CDM_COMBAT = "cdm-combat"
E.CDM_SLOTS = "cdm-slots-full"
E.CDM_API = "cdm-api"
E.CDM_UNREADABLE = "cdm-unreadable"
E.CDM_WRITE = "cdm-write-failed"
E.CDM_OWNER = "cdm-owner"
E.CDM_NOT_MANAGED = "cdm-not-managed"
E.CDM_OFF = "cdm-off"

local M = lib.MESSAGES.enUS
M["store-invalid"] = "The store must be a table your addon saves (SavedVariablesPerCharacter)."
M["cdm-combat"] = "Out of combat only: the Cooldown Manager's layouts are not changed in combat."
M["cdm-slots-full"] = "No free layout slot (5 of 5 used): delete one in the Cooldown Manager's settings."
M["cdm-api"] = "The client lacks the layout or encoding API this needs."
M["cdm-unreadable"] = "The Cooldown Manager's saved layouts cannot be read."
M["cdm-write-failed"] = "The layout write did not read back as written. The library tried to put back what was there."
M["cdm-owner"] = "Another addon manages the Cooldown Manager."
M["cdm-not-managed"] = "Nothing to restore: the Cooldown Manager is not managed."
M.player = "The player's own Cooldown Manager layout, read only."
M.managed = "Managed: the library's layout is active and the Cooldown Manager is hidden."
M.drift =
    "The library's layout is not in use: another layout is active, it was deleted, or the Cooldown Manager is off."
M.reload = "A reload is needed to finish."
M.checking = "Checking the layout after the reload."
M["check-failed"] = "The layout did not take after the reload: the player's own layout is in use."
M["restore-failed"] = "The restore did not take: the library's layout came back after the reload. Restore again."
M.switched = "Another layout is active."
M.deleted = "The library's layout was deleted."
M.update = "A watched aura has no bar yet: manage again to update the layout (a reload)."

-- Tables -----------------------------------------------------------------------------------------------------------

local function copy(t)
    if type(t) ~= "table" then
        return t
    end
    local c = {}
    for k, v in pairs(t) do
        c[k] = copy(v)
    end
    return c
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not same(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

-- The store -------------------------------------------------------------------------------------------------------

local function api()
    local CV, EU, C = C_CooldownViewer, C_EncodingUtil, Enum
    return CV
        and CV.GetLayoutData
        and CV.SetLayoutData
        and EU
        and EU.SerializeCBOR
        and EU.DeserializeCBOR
        and EU.CompressString
        and EU.DecompressString
        and EU.EncodeBase64
        and EU.DecodeBase64
        and C
        and C.CompressionMethod
        and C.CooldownViewerCategory
        and C.CooldownViewerCategory.TrackedBar
        and true
end

-- The store string as the client has it, or nil (missing, secret or failed).
local function fetch()
    local ok, s = pcall(C_CooldownViewer.GetLayoutData)
    if ok and not issecretvalue(s) and type(s) == "string" then
        return s
    end
end

local function inflate(s)
    local EU = C_EncodingUtil
    local raw = EU.DecodeBase64(s)
    return raw and EU.DeserializeCBOR(EU.DecompressString(raw, Enum.CompressionMethod.Deflate))
end

-- The layouts table of a store string ("" is no layout saved yet), or nil when it is not one.
local function decode(s)
    if s == "" then
        return { 5, {}, {}, {} }
    end
    local d = type(s) == "string" and s:find("|", 1, true)
    if not d or tonumber(s:sub(1, d - 1)) ~= 1 then
        return nil
    end
    local ok, t = pcall(inflate, s:sub(d + 1))
    if ok and type(t) == "table" and t[1] == 5 then -- another save version may mean other things: never rewritten
        return t
    end
end

local function encode(t)
    local EU = C_EncodingUtil
    return "1|" .. EU.EncodeBase64(EU.CompressString(EU.SerializeCBOR(t), Enum.CompressionMethod.Deflate))
end

-- The player's tag: class ID * 10 + spec (Forever: spec 1, one tag per character), or nil.
local function tagOf()
    local ok, _, _, classID = pcall(UnitClass, "player")
    local si = C_SpecializationInfo
    local get = si and si.GetSpecialization or GetSpecialization
    local okS, spec = pcall(get)
    if ok and okS and not issecretvalue(classID) and not issecretvalue(spec) then
        if type(classID) == "number" and type(spec) == "number" then
            return classID * 10 + spec
        end
    end
end

-- Layouts in the store (every tag) and the largest id.
local function count(t)
    local n, top = 0, 0
    for _, ls in pairs(t[3] or {}) do
        for id in pairs(ls) do
            n = n + 1
            if type(id) == "number" and id > top then
                top = id
            end
        end
    end
    return n, top
end

-- The category a layout gives a cooldownID: its override in the layout, else the default (from the catalogue).
local function placed(lay, cd)
    for cat, list in pairs(lay and lay[2] or {}) do
        for i = 1, #list do
            if list[i] == cd then
                return cat
            end
        end
    end
    return cdm.catOf and cdm.catOf[cd]
end

-- For every watched aura, its entry that is (bars) or must become (moves) a tracked bar in layout lay: aura entries
-- only (never an Essential or Utility entry: that one is the spell's cooldown). Returns how many must move.
local function want(lay, moves, bars)
    local C = Enum.CooldownViewerCategory
    local BAR, ESS, UTI = C.TrackedBar, C.Essential, C.Utility
    local seen, n = {}, 0
    local srcs = lib.sources
    for k = 1, #srcs do
        local s = srcs[k]
        local l = s.kind == "aura" and #s.handles > 0 and cdm.cds[s.spell]
        if l then
            local pick, has
            for j = 1, #l do
                local cd = l[j]
                local def = cdm.catOf and cdm.catOf[cd]
                if def ~= nil and def ~= ESS and def ~= UTI then
                    if placed(lay, cd) == BAR then
                        has = cd
                        break
                    end
                    pick = pick or cd
                end
            end
            local cd = has or pick
            if cd and not seen[cd] then
                seen[cd] = true
                if bars then
                    bars[#bars + 1] = cd
                end
                if not has then
                    n = n + 1
                    if moves then
                        moves[#moves + 1] = cd
                    end
                end
            end
        end
    end
    return n
end

-- Writes new raw; true when it reads back equal. The store as the client loaded it is noted before the first write of
-- the session: a write that brings it back needs no reload (an undo before the reload). The leftover of our own failed
-- write (st.bad) is never taken for what the client loaded.
local function write(st, new, what)
    if not lib.mbPending and not st.bad then
        mb.atLoad = fetch()
    end
    local ok = pcall(C_CooldownViewer.SetLayoutData, new)
    if not ok or fetch() ~= new then
        return false
    end
    st.bad = nil
    if new == mb.atLoad then
        lib.mbPending, st.pending = nil, nil
    else
        lib.mbPending = what
        st.pending = what == "manage" and "manage" or nil
    end
    return true
end

local function forget(st)
    st.orig, st.tag, st.id, st.name, st.lay, st.bars = nil, nil, nil, nil, nil, nil
    st.prev, st.pending, st.state, st.bad = nil, nil, nil, nil
end

-- Our layout in t, or nil: the id we wrote, under our name, holding exactly what we wrote. A layout the player made
-- that took our id (or ours after the player edited it) is theirs: never hidden, rewritten or removed.
local function mine(t, st)
    local lay = st.id and t[3] and t[3][st.tag] and t[3][st.tag][st.id]
    if lay and t[4] and t[4][st.id] == st.name and (same(lay, st.lay) or same(lay, st.prev)) then
        return lay
    end
end

-- A manage that needs no reload (the store is what this load read) and is not managed yet: check it in this load.
local function rearm(st)
    if not lib.mbPending and st.state ~= "managed" then
        st.pending, st.state, mb.spent = "manage", nil, nil
    end
end

-- The viewers ---------------------------------------------------------------------------------------------------------

-- Alpha 0 on the four viewers (each one's alpha read first and given back after); never Hide (that stops the data).
-- Read again at every pass: a viewer not at 0 (Edit Mode applied the player's opacity again) has its new alpha noted
-- and goes back to 0.
local function hide(on)
    if on then
        local saved = mb.alpha or {}
        mb.alpha = saved
        for i = 1, #VIEWERS do
            local name = VIEWERS[i]
            local v = _G[name]
            if type(v) == "table" and v.GetAlpha and v.SetAlpha then
                local ok, a = pcall(v.GetAlpha, v)
                if not ok or issecretvalue(a) or type(a) ~= "number" then
                    a = nil
                end
                if (a ~= nil and a ~= 0) or saved[name] == nil then
                    saved[name] = a or saved[name] or 1
                    pcall(v.SetAlpha, v, 0)
                end
            end
        end
    elseif mb.alpha then
        for name, a in pairs(mb.alpha) do
            local v = _G[name]
            if v then
                pcall(v.SetAlpha, v, a)
            end
        end
        mb.alpha = nil
    end
end

-- Hidden only while managed (the check passed this load) and the aura kind is ready (not off, errored, failed its
-- self-test or pending it); an update written over a managed layout keeps it hidden until the reload (the loaded
-- layout is still ours).
local function apply()
    local on = lib.capOf("aura") == "ready"
    if mb.mode == "pending" then
        on = on and lib.mbPending == "manage" and mb.alpha ~= nil
    else
        on = on and mb.mode == "managed"
    end
    hide(on)
end

-- Sets the mode; the callbacks hear a change as fn("cdm", mode, reason), never from inside a call of the API.
local function set(mode, why)
    mb.mode, mb.why = mode, why
    apply()
    if mb.quiet then
        return
    end
    local key = mode .. ":" .. (why or "")
    if key == mb.told then
        return
    end
    mb.told = key
    for _, fn in pairs(lib.capCb) do
        local ok, err = pcall(fn, "cdm", mode, why)
        if not ok then
            lib.report(err)
        end
    end
end

-- The learned cooldownIDs (a check counts only those: the client builds no item for an entry not learned).
local function learned()
    local out = {}
    for cat = 0, 8 do
        local ok, set = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, false)
        if ok and not issecretvalue(set) and type(set) == "table" then
            for n = 1, #set do
                if not issecretvalue(set[n]) and set[n] ~= nil then
                    out[set[n]] = true
                end
            end
        end
    end
    return out
end

-- After the reload: our layout is the active one and every learned entry of ours is a tracked bar item.
local function check(st)
    local t = decode(fetch())
    if not (t and mine(t, st) and t[2] and t[2][st.tag] == st.id) then
        return false
    end
    local known = learned()
    for i = 1, #(st.bars or {}) do
        local cd = st.bars[i]
        if known[cd] and cdm.placeOf[cd] ~= 1 then
            return false
        end
    end
    return true
end

-- Managed or drift, from the store (decoded only when its string changed) and the Cooldown Manager's state.
local function drift(st)
    if cdm.off then
        return "drift", "cdm-off"
    end
    local s = fetch()
    if s ~= mb.lastS then
        mb.lastS, mb.lastT = s, s and decode(s)
    end
    local t = mb.lastT
    if not t then
        return mb.mode, mb.why -- unreadable now: the last answer stands
    end
    local ours = mine(t, st)
    if not ours then
        return "drift", "deleted" -- or a layout of the player took our id: theirs
    end
    if not (t[2] and t[2][st.tag] == st.id) then
        return "drift", "switched"
    end
    if want(ours) > 0 then
        return "managed", "update"
    end
    return "managed"
end

-- The mode from the store and this load's writes. Out of combat only for anything that reads the store; in combat the
-- last answer of this load stands, and what has none yet (a check, a restore to verify, a managed store not read since
-- the load) reads pending, checking until the end of combat.
function mb.update()
    local st = lib.mbStore
    if not st then
        return set("player")
    end
    if lib.mbPending then
        return set("pending", "reload")
    end
    local fight = InCombatLockdown()
    mb.checking = nil
    if fight then
        if st.pending == "manage" or st.state == "restoring" or (st.state == "managed" and not mb.read) then
            mb.checking = true
            return set("pending", "checking")
        elseif st.state == "managed" then
            return
        end
    elseif st.state == "restoring" then -- a restore before this load: forgotten once our layout is gone
        local t = decode(fetch())
        if t then
            local ls = t[3] and t[3][st.tag]
            if st.id and ls and ls[st.id] and t[4] and t[4][st.id] == st.name then
                st.state = "unrestored" -- ours came back (the client wrote its layouts over the restore): retry
            else
                forget(st)
            end
        end
    elseif st.pending == "manage" then -- written by an earlier load (or by this one with no reload needed): the check
        if check(st) then
            st.pending, st.state, st.prev = nil, "managed", nil
        elseif (mb.spent or 0) < CHECK then -- seconds out of combat, counted by the driver
            mb.checking = true
            return set("pending", "checking")
        else
            st.pending, st.state = nil, "failed"
        end
    end
    if st.state == "managed" then
        mb.read = true
        return set(drift(st))
    end
    local why = st.state == "failed" and "check-failed" or st.state == "unrestored" and "restore-failed" or nil
    return set("player", why)
end

-- The answer an API call leaves: noted at once, told to the callbacks on the next frame.
local function settle()
    mb.quiet = true
    mb.update()
    mb.quiet = nil
    cdm.dirty = true
    lib.wake()
end

-- The API -----------------------------------------------------------------------------------------------------------

local function holds(st)
    return st ~= nil and (st.orig ~= nil or st.pending ~= nil)
end

local function claim(owner, store)
    if type(owner) ~= "string" then
        return E.OWNER_INVALID
    end
    if type(store) ~= "table" then
        return E.STORE_INVALID
    end
    if lib.mbOwner and lib.mbOwner ~= owner and lib.mbStore ~= store and holds(lib.mbStore) then
        return E.CDM_OWNER
    end
end

-- Hands the library the consumer's persisted table: call it at every load (once its SavedVariables exist). A store a
-- past load left pending is checked once the Cooldown Manager is read. true | nil, code.
function lib:SetCooldownManagerStore(owner, store)
    local err = claim(owner, store)
    if err then
        return nil, err
    end
    lib.mbOwner, lib.mbStore = owner, store
    cdm.dirty = true
    lib.wake()
    return true
end

-- Builds and writes the library's layout (a new one, or ours again: an update or a re-activation after drift) with
-- every watched aura's entry on a tracked bar. true (a reload is pending unless nothing changed) | nil, code.
function lib:ManageCooldownManager(owner, store)
    local err = claim(owner, store)
    if err then
        return nil, err
    end
    if InCombatLockdown() then
        return nil, E.CDM_COMBAT
    end
    if not api() then
        return nil, E.CDM_API
    end
    if cdm.off then
        return nil, E.CDM_OFF
    end
    local s = fetch()
    local t = s and decode(s)
    local tag = tagOf()
    if not (t and tag) then
        return nil, E.CDM_UNREADABLE
    end
    cdm.catalogue()
    local ls = t[3] and t[3][tag]
    local ours = store.tag == tag and mine(t, store) or nil
    local id, base = store.id, ours
    if not ours then
        local n, top = count(t)
        if n >= MAXL then
            return nil, E.CDM_SLOTS
        end
        id = top + 1
        local act = t[2] and t[2][tag]
        base = act and act ~= 0 and ls and ls[act] or nil
    end
    local out = copy(t)
    out[2], out[3], out[4] = out[2] or {}, out[3] or {}, out[4] or {}
    local lay = copy(base) or {}
    local moves, bars = {}, {}
    want(lay, moves, bars)
    local cats = lay[2] or {}
    local BAR = Enum.CooldownViewerCategory.TrackedBar
    for m = 1, #moves do
        for cat, list in pairs(cats) do
            for i = #list, 1, -1 do
                if list[i] == moves[m] then
                    table.remove(list, i)
                end
            end
            if #list == 0 then
                cats[cat] = nil
            end
        end
        cats[BAR] = cats[BAR] or {}
        local l = cats[BAR]
        l[#l + 1] = moves[m]
    end
    lay[2] = cats
    out[3][tag] = out[3][tag] or {}
    out[3][tag][id], out[4][id], out[2][tag] = lay, owner, id
    lib.mbOwner, lib.mbStore = owner, store
    if same(out, t) then -- ours, active, every aura on a bar already
        store.bars = bars
        rearm(store)
        settle()
        return true
    end
    local ok, new = pcall(encode, out)
    if not (ok and type(new) == "string" and same(decode(new), out)) then
        return nil, E.CDM_API
    end
    if not ours then -- none of ours in the store: a new start, the store as it is now is the original
        store.orig, store.tag = s, tag -- saved before the write
    end
    if not write(store, new, "manage") then
        pcall(C_CooldownViewer.SetLayoutData, s)
        local now = fetch()
        if now ~= s then
            store.bad = now -- what our failed write left: Restore may write the original over it, over nothing else
        elseif not ours then
            forget(store) -- put back: nothing to restore
        end
        return nil, E.CDM_WRITE
    end
    if ours and store.prev == nil then
        store.prev = ours -- an update: the content the client loaded stays ours until a check passes
    end
    store.id, store.name, store.lay, store.bars, store.state = id, owner, lay, bars, nil
    rearm(store)
    settle()
    return true
end

-- Removes the library's layout. Nothing else changed since: the saved original is written back byte for byte. The
-- player changed something (another layout edited, added or deleted): only our layout goes and the layout active
-- before it comes back (when the player switched away from ours, their choice stays). Before the reload of a manage
-- this is an undo (no reload). Layouts it cannot read or decode are never written over (cdm-unreadable), except the
-- leftover of our own failed write. The saved original stays until the next load shows the restore took.
-- true | nil, code.
function lib:RestoreCooldownManager(owner, store)
    local err = claim(owner, store)
    if err then
        return nil, err
    end
    if store.orig == nil then
        return nil, E.CDM_NOT_MANAGED
    end
    if InCombatLockdown() then
        return nil, E.CDM_COMBAT
    end
    if not api() then
        return nil, E.CDM_API
    end
    local s = fetch()
    local o = decode(store.orig)
    if s == nil or not o then
        return nil, E.CDM_UNREADABLE
    end
    local t = decode(s)
    if not t and s ~= store.bad then
        return nil, E.CDM_UNREADABLE
    end
    local out = copy(t or o) -- our own failed write's leftover: the saved original goes back raw
    local tag, id = store.tag, store.id
    if mine(out, store) then
        local ls = out[3][tag]
        ls[id] = nil
        if next(ls) == nil then
            out[3][tag] = nil
        end
        out[4][id] = nil
        if out[2] and out[2][tag] == id then
            local a = o[2] and o[2][tag]
            if a and a ~= 0 and not (out[3][tag] and out[3][tag][a]) then
                a = nil -- the layout active before is gone: the default
            end
            out[2][tag] = a
        end
    end
    local new
    if not t or same(out, o) then
        new = store.orig
    elseif not same(out, t) then
        local ok, enc = pcall(encode, out)
        if not (ok and type(enc) == "string" and same(decode(enc), out)) then
            return nil, E.CDM_API
        end
        new = enc
    end
    if new == s then
        new = nil -- equal bytes: no write
    end
    lib.mbOwner, lib.mbStore = owner, store
    if new then
        if not write(store, new, "restore") then
            pcall(C_CooldownViewer.SetLayoutData, s)
            local now = fetch()
            if now ~= s then
                store.bad = now
            end
            return nil, E.CDM_WRITE
        end
    elseif lib.mbPending == "manage" then
        lib.mbPending = nil -- the manage this load wrote is gone already: nothing waits for a reload
    end
    if lib.mbPending == "restore" then
        store.state, store.pending, store.bars = "restoring", nil, nil -- checked at the next load
    else
        forget(store)
    end
    settle()
    return true
end

-- pending, what: a write of this load needs a reload ("manage" or "restore").
function lib:IsReloadPending()
    return lib.mbPending ~= nil, lib.mbPending
end

-- "player" | "managed" | "drift" | "pending", reason (managed: nil or "update"; drift: "switched", "deleted",
-- "cdm-off"; pending: "reload" or "checking"; player: nil, "check-failed" or "restore-failed").
function lib:GetCooldownManagerMode()
    return mb.mode, mb.why
end

-- The wraps ---------------------------------------------------------------------------------------------------------

-- Every read of the Cooldown Manager (an event, a layout pass, the end of combat) answers the mode again.
local baseResolve = cdm.resolve
function cdm.resolve()
    baseResolve()
    if lib.mbStore then
        mb.update()
    end
end

-- While the check waits, the driver keeps running and reads again every RECHECK frames.
local baseDrive = lib.drive
function lib.drive(elapsed)
    baseDrive(elapsed)
    if mb.checking then
        if type(elapsed) == "number" and elapsed > 0 and not InCombatLockdown() then
            mb.spent = (mb.spent or 0) + elapsed -- the check's window pauses in combat
        end
        if lib.frameNo % RECHECK == 0 then
            cdm.dirty = true
        end
        lib.wake()
    end
end

-- The kill switch and an errored aura kind give the viewers back.
local baseCap = lib.capChanged
function lib.capChanged()
    baseCap()
    apply()
end
