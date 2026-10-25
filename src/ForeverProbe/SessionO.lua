-- SessionO.lua: session O, the self-classifying combat-event probe (probes O1-O16 of the TacoDogForever research
-- doc docs/research/2026-10-14-virtual-combat-log-events.md §5) folded into one session that needs no per-probe
-- action: one frame registers every candidate event up front (each under pcall), every firing is counted and every
-- argument classified (secret / nil / plain, the Lua type, up to 8 distinct plain samples; plain tables walked one
-- level), and small correlators answer the probes that need logic (O2, O3, O6, O9, O11, O14, O16).
--
-- Runs independently of /fprobe start W|D (own frames, own session record "<date> <time> O"). The secret rules of
-- Core.lua apply: issecretvalue() first, before any type(), compare, #, index or concatenation of a client value;
-- secrets are never stored; nothing divides by a value that could be 0. The per-firing path is allocation-light:
-- records are created once per (event, unit bucket), samples are capped, no closures or key strings per firing.
local _, ns = ...
local IsSecret, Enc, ErrText, Round, Print = ns.IsSecret, ns.Enc, ns.ErrText, ns.Round, ns.Print

local SessionO = {}
ns.SessionO = SessionO

local MAX_ARGS = 10 -- argument positions classified per firing
local MAX_SAMPLES = 8 -- distinct plain samples kept per slot
local MAX_FIELDS = 12 -- named fields kept per walked table
local MAX_STR = 64 -- string samples are truncated to this
local TICK = 0.5 -- square / panel / FCT recompute period (s)
local FCT_CVAR = "enableFloatingCombatText"
local FCT_COMBAT_SECONDS = 120 -- in-combat seconds of phase A before the switch to phase B
local SWING_RING = 40
local SWING_PENDING = 8
local DTPOW_CAP = 0.5 -- O3: a player RAGE event up to this long after a swing is stored as the swing's dtPow
local DEATH_RING = 20
local O16_SLOTS = 8
local O16_MAX_SPELLS = 16
local O16_DELAY = 0.1
local HIST_STEP = 0.25 -- O9 histogram bin width (s); bins 1..24 cover 0-6 s, bin 25 is the overflow
local HIST_BINS = 24

-- Event table ------------------------------------------------------------------------------------------------
-- { name, documented, unitFirst }: documented = listed by the wow MCP Forever API docs (wow_api_event_search,
-- flavor forever, checked 2026-10-14); a doc gap is not proof, so undocumented names are still tried under pcall.
-- unitFirst = arg 1 is a unit token: firings are bucketed by it. Never listed (forbidden-action popup, measured):
-- COMBAT_LOG_EVENT_UNFILTERED, COMBAT_LOG_EVENT, COMBAT_LOG_MESSAGE.
local EVENTS = {
    { "UNIT_COMBAT", true, true }, -- O1
    { "COMBAT_TEXT_UPDATE", true, false }, -- O2 (bucketed by FCT phase instead)
    { "PLAYER_SWING", true, false }, -- O3, O11
    { "PLAYER_SWING_RANGE_UPDATE", true, false }, -- extra (measured inert in session W)
    { "UNIT_POWER_FREQUENT", true, true }, -- O3 correlator
    { "UNIT_POWER_UPDATE", true, true },
    { "UNIT_SPELLCAST_START", true, true }, -- O4
    { "UNIT_SPELLCAST_SUCCEEDED", true, true }, -- O4, O11, O16
    { "UNIT_SPELLCAST_INTERRUPTED", true, true }, -- O4, O5
    { "UNIT_SPELLCAST_STOP", true, true }, -- O4
    { "UNIT_SPELLCAST_FAILED", true, true }, -- O4
    { "UNIT_SPELLCAST_DELAYED", true, true }, -- O4
    { "UNIT_SPELLCAST_CHANNEL_START", true, true }, -- O4
    { "UNIT_SPELLCAST_CHANNEL_UPDATE", true, true }, -- O4
    { "UNIT_SPELLCAST_CHANNEL_STOP", true, true }, -- O4
    { "UNIT_SPELLCAST_INTERRUPTIBLE", true, true }, -- O4
    { "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", true, true }, -- O4
    { "LOSS_OF_CONTROL_ADDED", true, true }, -- O5
    { "UNIT_DIED", true, false }, -- O6 (arg 1 is a GUID, not a token)
    { "PARTY_KILL", true, false }, -- O6
    { "PLAYER_TARGET_DIED", true, false }, -- O6
    { "PLAYER_DEAD", true, false },
    { "DAMAGE_METER_COMBAT_SESSION_UPDATED", true, false }, -- O7
    { "DAMAGE_METER_CURRENT_SESSION_UPDATED", true, false }, -- O7
    { "NAME_PLATE_UNIT_ADDED", true, true }, -- O8
    { "NAME_PLATE_UNIT_REMOVED", true, true }, -- O8
    { "UNIT_HEALTH", true, true }, -- O9
    { "UNIT_HEALTH_FREQUENT", false, true }, -- research N17: removed as in retail; confirms the doc gap
    { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", true, false }, -- O10
    { "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", true, false }, -- O10
    { "UNIT_AURA", true, true }, -- O12
    { "UNIT_PET", true, true }, -- O13
    { "PLAYER_TOTEM_UPDATE", true, false }, -- O13
    { "PET_ATTACK_START", true, false }, -- O13
    { "PET_ATTACK_STOP", true, false }, -- O13
    { "UNIT_HAPPINESS", true, true }, -- O13
    { "COMBO_TARGET_CHANGED", true, false }, -- O15
    { "UNIT_COMBO_POINTS", false, true }, -- research N14: register error measured in the gate spike
    { "UNIT_THREAT_LIST_UPDATE", true, true },
    { "UNIT_THREAT_SITUATION_UPDATE", true, true },
    { "UNIT_ABSORB_AMOUNT_CHANGED", true, true },
    { "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", true, true },
    { "UNIT_HEAL_PREDICTION", true, true },
    { "UNIT_TARGET", true, true },
    { "PLAYER_TARGET_CHANGED", true, false }, -- O9 clock reset
    { "PLAYER_REGEN_DISABLED", true, false }, -- O14
    { "PLAYER_REGEN_ENABLED", true, false }, -- O14
    { "PLAYER_ENTER_COMBAT", true, false }, -- auto-attack on (O9)
    { "PLAYER_LEAVE_COMBAT", true, false }, -- auto-attack off (O9)
    { "PLAYER_IN_COMBAT_CHANGED", true, false },
    { "UPDATE_SHAPESHIFT_FORM", true, false },
    { "ENCOUNTER_START", true, false },
    { "ENCOUNTER_END", true, false },
    { "MIRROR_TIMER_START", true, false },
    { "MIRROR_TIMER_STOP", true, false },
    { "RESURRECT_REQUEST", true, false },
    { "UPDATE_INVENTORY_DURABILITY", true, false },
}

-- Probe squares: which (event, bucket) records decide each colour. only / except filter the unit buckets.
local PLAYER = { player = true }
local PT = { player = true, target = true, S = true }
local TARGET = { target = true, S = true }
local NOTPLAYER = { player = true }
local PROBES = {
    { id = "O1", label = "UNIT_COMBAT target/player", parts = { { "UNIT_COMBAT", only = PT } } },
    { id = "O2", label = "COMBAT_TEXT_UPDATE (FCT on, then off)", parts = { { "COMBAT_TEXT_UPDATE" } } },
    { id = "O3", label = "swing vs same-frame power, Overpower", parts = { { "PLAYER_SWING" } } },
    { id = "O4", label = "other units' casts", parts = {
        { "UNIT_SPELLCAST_START", except = NOTPLAYER }, { "UNIT_SPELLCAST_SUCCEEDED", except = NOTPLAYER },
        { "UNIT_SPELLCAST_INTERRUPTED", except = NOTPLAYER }, { "UNIT_SPELLCAST_STOP", except = NOTPLAYER },
        { "UNIT_SPELLCAST_FAILED", except = NOTPLAYER }, { "UNIT_SPELLCAST_DELAYED", except = NOTPLAYER },
        { "UNIT_SPELLCAST_CHANNEL_START", except = NOTPLAYER }, { "UNIT_SPELLCAST_CHANNEL_UPDATE", except = NOTPLAYER },
        { "UNIT_SPELLCAST_CHANNEL_STOP", except = NOTPLAYER }, { "UNIT_SPELLCAST_INTERRUPTIBLE", except = NOTPLAYER },
        { "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", except = NOTPLAYER } } },
    { id = "O5", label = "our interrupt + loss of control", parts = { { "UNIT_SPELLCAST_INTERRUPTED", only = PLAYER }, { "LOSS_OF_CONTROL_ADDED" } } },
    { id = "O6", label = "deaths (UNIT_DIED, PARTY_KILL, PLAYER_TARGET_DIED)", parts = { { "UNIT_DIED" }, { "PARTY_KILL" }, { "PLAYER_TARGET_DIED" } } },
    { id = "O7", label = "damage meter events", parts = { { "DAMAGE_METER_COMBAT_SESSION_UPDATED" }, { "DAMAGE_METER_CURRENT_SESSION_UPDATED" } } },
    { id = "O8", label = "nameplate add/remove", parts = { { "NAME_PLATE_UNIT_ADDED" }, { "NAME_PLATE_UNIT_REMOVED" } } },
    { id = "O9", label = "UNIT_HEALTH target cadence", parts = { { "UNIT_HEALTH", only = TARGET } } },
    { id = "O10", label = "overlay glow show/hide", parts = { { "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" }, { "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" } } },
    { id = "O11", label = "ranged swing type / shots", corr = true, parts = { { "PLAYER_SWING" }, { "UNIT_SPELLCAST_SUCCEEDED", only = PLAYER } } },
    { id = "O12", label = "UNIT_AURA update table", parts = { { "UNIT_AURA", only = PT } } },
    { id = "O13", label = "pet / totem events", parts = { { "UNIT_PET" }, { "PLAYER_TOTEM_UPDATE" }, { "PET_ATTACK_START" }, { "PET_ATTACK_STOP" }, { "UNIT_HAPPINESS" } } },
    { id = "O14", label = "IsCombatLogRestricted", corr = true },
    { id = "O15", label = "COMBO_TARGET_CHANGED", parts = { { "COMBO_TARGET_CHANGED" } } },
    { id = "O16", label = "cast success then Overpower", corr = true, parts = { { "UNIT_SPELLCAST_SUCCEEDED", only = PLAYER } } },
}

-- Auto Shot, Shoot (wand), Shoot Bow/Gun/Crossbow, Throw, Shoot: the per-shot casts O11 looks for.
local RANGED = { [75] = true, [5019] = true, [2480] = true, [7918] = true, [7919] = true, [2764] = true, [3018] = true }
local HAND = { [0] = "h0", [1] = "h1", [2] = "h2" }
local CODES = { "t", "f", "S", "N", "E", "A" }
local COMBO = {} -- COMBO[before][after] = "before>after", precomputed so the O16 path builds no strings
for _, b in ipairs(CODES) do
    COMBO[b] = {}
    for _, a in ipairs(CODES) do
        COMBO[b][a] = b .. ">" .. a
    end
end
local TYPE_TAG = { ["function"] = "<function>", userdata = "<userdata>", thread = "<thread>" }

local db -- ForeverProbeDB
local sess -- the running session record
local evs -- sess.events
local o2, o3, o6, o9, o11, o14, o16 -- correlator records of the running session
local classToken
local frame = CreateFrame("Frame") -- event classifier
local driver = CreateFrame("Frame") -- throttled squares, panel and FCT phase
driver:Hide()
local guard = CreateFrame("Frame") -- CVar restore safety net (logout, deferred out of combat)

-- Runtime state (not saved).
local lastPowerT = -1
local autoAttack = false
local lastHpT = 0
local lastDead = false
local lastOp = "N"
local pendT, pendH, pendD, pendL, pendDt = {}, {}, {}, {}, {}
local pendN = 0
local qUsed, qSpell, qBefore, qDue = {}, {}, {}, {}
local acc = 0

-- Classification ---------------------------------------------------------------------------------------------

-- Counts a plain table that issecrettable() flags (its accesses produce secrets) under slot.ST.
local function SecretTable(slot, v)
    if type(issecrettable) ~= "function" then
        return
    end
    local ok, st = pcall(issecrettable, v)
    if ok and not IsSecret(st) and st == true then
        slot.ST = (slot.ST or 0) + 1
    end
end

local function NewSlot()
    return { S = 0, N = 0, P = 0, types = {}, samples = {} }
end

local function GetSlot(t, k)
    local s = t[k]
    if not s then
        s = NewSlot()
        t[k] = s
    end
    return s
end

local function NewCodes()
    return { t = 0, f = 0, S = 0, N = 0, E = 0, A = 0 }
end

-- Stores a plain value as a sample if it is new and the slot has room. Numbers go through Enc (rounded; nan/inf
-- as strings), strings are truncated; a string is only built when a new sample is stored.
local function AddSample(slot, k, v)
    local samples = slot.samples
    local n = #samples
    if n >= MAX_SAMPLES then
        return
    end
    if k == "number" then
        v = Enc(v)
    elseif k == "string" then
        if #v > MAX_STR then
            -- A long string already stored (as its 64-char prefix) is found without building the prefix.
            for i = 1, n do
                local sv = samples[i]
                if type(sv) == "string" and #sv == MAX_STR and string.find(v, sv, 1, true) == 1 then
                    return
                end
            end
            v = string.sub(v, 1, MAX_STR)
        end
    elseif k ~= "boolean" then
        v = TYPE_TAG[k] or "<?>"
    end
    for i = 1, n do
        if samples[i] == v then
            return
        end
    end
    samples[n + 1] = v
end

-- A field of a walked table: a nested table is not walked; its length is the sample, and its first element's
-- secrecy is counted (e1S / e1P).
local function ClassifyField(slot, v)
    if IsSecret(v) then
        slot.S = slot.S + 1
        return
    end
    if v == nil then
        slot.N = slot.N + 1
        return
    end
    slot.P = slot.P + 1
    local k = type(v)
    local types = slot.types
    types[k] = (types[k] or 0) + 1
    if k == "table" then
        SecretTable(slot, v)
        AddSample(slot, "number", #v)
        local e1 = v[1]
        if IsSecret(e1) then
            slot.e1S = (slot.e1S or 0) + 1
        elseif e1 ~= nil then
            slot.e1P = (slot.e1P or 0) + 1
        end
    else
        AddSample(slot, k, v)
    end
end

local nFields = setmetatable({}, { __mode = "k" }) -- field table -> named fields kept (runtime only)

local function WalkInto(f, tbl)
    for k, v in pairs(tbl) do
        if IsSecret(k) then
            ClassifyField(GetSlot(f, "<secretKey>"), v)
        elseif type(k) == "string" then
            local s = f[k]
            if not s then
                local n = nFields[f] or 0
                if n < MAX_FIELDS then
                    s = NewSlot()
                    f[k] = s
                    nFields[f] = n + 1
                end
            end
            if s then
                ClassifyField(s, v)
            else
                local more = GetSlot(f, "<more>")
                more.P = more.P + 1
            end
        end
    end
    local len = #tbl
    if len > 0 then
        ClassifyField(GetSlot(f, "#"), len)
    end
end

-- Walks a plain table one level into holder[key] (a name -> slot map), under pcall.
local function WalkTable(holder, key, tbl)
    local f = holder[key]
    if not f then
        f = {}
        holder[key] = f
    end
    local ok, err = pcall(WalkInto, f, tbl)
    if not ok then
        local e = GetSlot(f, "<walkErr>")
        e.E = (e.E or 0) + 1
        e.err = e.err or ErrText(err)
    end
end

-- The classification rule for an argument or a read: S secret, N nil, else P + type + sample; plain tables are
-- walked into holder[key].
local function Classify(slot, v, holder, key)
    if IsSecret(v) then
        slot.S = slot.S + 1
        return
    end
    if v == nil then
        slot.N = slot.N + 1
        return
    end
    slot.P = slot.P + 1
    local k = type(v)
    local types = slot.types
    types[k] = (types[k] or 0) + 1
    if k == "table" then
        SecretTable(slot, v)
        if holder then
            WalkTable(holder, key, v)
        end
    else
        AddSample(slot, k, v)
    end
end

-- Calls fn(...) under pcall and classifies its first (and optionally second) return into rec.reads.
-- An absent API marks the slot api = "-"; an error counts E and keeps the first message.
local function Read(rec, name, name2, fn, ...)
    local slot = GetSlot(rec.reads, name)
    if type(fn) ~= "function" then
        slot.api = "-"
        return nil
    end
    local ok, v, v2 = pcall(fn, ...)
    if not ok then
        slot.E = (slot.E or 0) + 1
        slot.err = slot.err or ErrText(v)
        return nil
    end
    Classify(slot, v, rec.readFields, name)
    if name2 then
        Classify(GetSlot(rec.reads, name2), v2, rec.readFields, name2)
    end
    return v
end

local function NewRec(now)
    local t = Round(now)
    return { n = 0, nC = 0, firstT = t, lastT = t, args = {}, fields = {}, reads = {}, readFields = {} }
end

local function Bucket(u)
    if IsSecret(u) then
        return "S"
    end
    if type(u) ~= "string" then
        return "other"
    end
    if u == "player" or u == "target" or u == "pet" then
        return u
    end
    if string.find(u, "^nameplate") then
        return "nameplate"
    elseif string.find(u, "^party") then
        return "party"
    elseif string.find(u, "^raid") then
        return "raid"
    end
    return "other"
end

-- A usability read encoded as one code: t true, f false, S secret, N nil, E error, A absent API.
local function UsableCode(name)
    local f = C_Spell and C_Spell.IsSpellUsable
    if type(f) ~= "function" then
        return "A"
    end
    local ok, v = pcall(f, name)
    if not ok then
        return "E"
    end
    if IsSecret(v) then
        return "S"
    end
    if v == nil then
        return "N"
    elseif v == true then
        return "t"
    end
    return "f"
end

local function DeadNow()
    if type(UnitIsDead) ~= "function" then
        return false
    end
    local ok, v = pcall(UnitIsDead, "target")
    return ok and not IsSecret(v) and v == true
end

-- FCT (O2) -----------------------------------------------------------------------------------------------------

local function GetFct()
    local f = (C_CVar and C_CVar.GetCVar) or GetCVar
    if type(f) ~= "function" then
        return nil, "-"
    end
    local ok, v = pcall(f, FCT_CVAR)
    if not ok then
        return nil, ErrText(v)
    end
    if IsSecret(v) or type(v) ~= "string" then
        return nil, Enc(v)
    end
    return v
end

-- Sets the CVar and reads it back: returns true (the read-back matches), "=<readback>" (it does not), "E:.." or
-- "-", plus the read-back value (nil if unreadable).
local function SetFct(v)
    local f = (C_CVar and C_CVar.SetCVar) or SetCVar
    if type(f) ~= "function" then
        return "-", nil
    end
    local ok, err = pcall(f, FCT_CVAR, v)
    if not ok then
        return ErrText(err), (GetFct())
    end
    local back = GetFct()
    if back == v then
        return true, back
    end
    return "=" .. tostring(back), back
end

-- Restores the user's original FCT value (db.fctRestore); deferred to PLAYER_REGEN_ENABLED in combat.
local function RestoreFct()
    if not db or db.fctRestore == nil then
        return nil
    end
    if ns.InCombat() then
        guard:RegisterEvent("PLAYER_REGEN_ENABLED")
        if o2 then
            o2.restored = "deferred"
        end
        return "deferred"
    end
    local r, back = SetFct(db.fctRestore)
    db.fctRestore = nil
    guard:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if o2 then
        o2.restored = r
        o2.cur = back
    end
    return r
end

guard:RegisterEvent("PLAYER_LOGOUT")
guard:SetScript("OnEvent", function()
    RestoreFct()
end)

local function Announce(msg)
    Print(msg)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, 1, 0.82, 0)
    elseif RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, { r = 1, g = 0.82, b = 0 })
    end
    if o2 then
        o2.announced = msg
    end
end

local function FctBucket()
    if o2.phase == "A" and o2.cur == "1" then
        return "A"
    elseif o2.phase == "B" and o2.cur == "0" then
        return "B"
    end
    return "X"
end

-- Out of combat only: applies a deferred phase-A set, and switches to phase B once phase A has had its combat time
-- (or /fprobe o fct asked for it).
local function FctTick(inC)
    if inC or o2.orig == nil then
        return
    end
    if o2.pendingA then
        o2.pendingA = nil
        o2.setA, o2.cur = SetFct("1")
    end
    if o2.phase == "A" and (o2.aCombat >= FCT_COMBAT_SECONDS or o2.force) then
        o2.setB, o2.cur = SetFct("0")
        o2.phase = "B"
        o2.switchedAt = Round(GetTime())
        o2.switchCombatS = Round(o2.aCombat)
        Announce("ForeverProbe session O: floating combat text is now OFF (O2 phase B). Keep fighting the same way.")
    end
end

-- Correlators ----------------------------------------------------------------------------------------------------

local function NewHand()
    return { swings = 0, landed = 0, noPower = 0, opAfterLanded = NewCodes(), opAfterNoPower = NewCodes() }
end

-- One frame after a batch of swings: Overpower usability, landed or not, the ring.
local function SwingCheck()
    if not sess then
        pendN = 0
        return
    end
    local op = UsableCode("Overpower")
    for i = 1, pendN do
        local hk = pendH[i]
        local h = o3.hands[hk]
        if pendL[i] then
            h.landed = h.landed + 1
            h.opAfterLanded[op] = h.opAfterLanded[op] + 1
        else
            h.noPower = h.noPower + 1
            h.opAfterNoPower[op] = h.opAfterNoPower[op] + 1
            if op == "t" then
                o3.noPowerOpTrue = o3.noPowerOpTrue + 1
            end
        end
        local head = o3.ringHead % SWING_RING + 1
        o3.ringHead = head
        o3.ringN = o3.ringN + 1
        local r = o3.ring[head]
        if not r then
            r = {}
            o3.ring[head] = r
        end
        r.seq, r.t, r.hand, r.dur, r.landed, r.op, r.dtPow = o3.ringN, pendT[i], hk, pendD[i], pendL[i], op, pendDt[i]
    end
    pendN = 0
    if lastOp == "f" and op == "t" then
        o3.opFlips = o3.opFlips + 1
    end
    lastOp = op
end

local function OnSwing(now, dur, hand)
    local hk
    if IsSecret(hand) then
        hk = "hS"
    else
        hk = HAND[hand] or "hX"
    end
    if not o3.hands[hk] then
        o3.hands[hk] = NewHand()
    end
    o3.hands[hk].swings = o3.hands[hk].swings + 1
    if hk == "h2" then
        o11.rangedSwings = o11.rangedSwings + 1
    end
    if pendN >= SWING_PENDING then
        o3.dropped = o3.dropped + 1
        return
    end
    pendN = pendN + 1
    pendT[pendN] = Round(now)
    pendH[pendN] = hk
    pendD[pendN] = Enc(dur)
    pendL[pendN] = lastPowerT == now
    if lastPowerT == now then
        pendDt[pendN] = 0
    else
        pendDt[pendN] = nil
    end
    if pendN == 1 then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, SwingCheck)
        else
            SwingCheck()
        end
    end
end

-- A player RAGE event: marks swings of this frame as landed, and fills dtPow (swing -> first rage event, capped at
-- DTPOW_CAP) on pending swings and on the last few ring entries, so a latency-delayed rage event is told apart from
-- an avoided swing (dtPow absent).
local function OnPlayerRage(now)
    lastPowerT = now
    local t = Round(now)
    for i = 1, pendN do
        if pendT[i] == t then
            pendL[i] = true
        end
        if pendDt[i] == nil and t - pendT[i] <= DTPOW_CAP then
            pendDt[i] = Round(t - pendT[i])
        end
    end
    local head, ring = o3.ringHead, o3.ring
    for k = 0, 3 do
        if k >= o3.ringN then
            break
        end
        local r = ring[(head - 1 - k) % SWING_RING + 1]
        if not r or t - r.t > DTPOW_CAP then
            break
        end
        if r.dtPow == nil then
            r.dtPow = Round(t - r.t)
        end
    end
end

local function O16Check()
    if not sess then
        return
    end
    local now = GetTime()
    local op
    for i = 1, O16_SLOTS do
        if qUsed[i] and qDue[i] <= now + 0.02 then
            qUsed[i] = false
            if not op then
                op = UsableCode("Overpower")
            end
            local b = qBefore[i]
            local s = o16.spells[qSpell[i]]
            s.n = s.n + 1
            local combo = COMBO[b][op]
            s[combo] = (s[combo] or 0) + 1
            o16.after[op] = o16.after[op] + 1
            if b == "f" and op == "t" then
                o16.flips = o16.flips + 1
                s.flips = (s.flips or 0) + 1
            end
        end
    end
end

local function OnPlayerSuccess(spellID)
    local key
    if IsSecret(spellID) then
        key = "S"
    elseif type(spellID) == "number" then
        key = spellID
        if RANGED[spellID] then
            o11.rangedCasts = o11.rangedCasts + 1
            o11.casts[spellID] = (o11.casts[spellID] or 0) + 1
        end
    else
        key = "other"
    end
    if not o16.spells[key] then
        if o16.nSpells >= O16_MAX_SPELLS then
            key = "other"
        end
        if not o16.spells[key] then
            o16.spells[key] = { n = 0 }
            o16.nSpells = o16.nSpells + 1
        end
    end
    o16.successes = o16.successes + 1
    local before = UsableCode("Overpower")
    o16.before[before] = o16.before[before] + 1
    local slot
    for i = 1, O16_SLOTS do
        if not qUsed[i] then
            slot = i
            break
        end
    end
    if not slot then
        o16.dropped = o16.dropped + 1
        return
    end
    qUsed[slot], qSpell[slot], qBefore[slot], qDue[slot] = true, key, before, GetTime() + O16_DELAY
    if C_Timer and C_Timer.After then
        C_Timer.After(O16_DELAY, O16Check)
    else
        qUsed[slot] = false
    end
end

local function OnTargetHealth(now, inC)
    if lastHpT > 0 and inC then
        local d = Round(now - lastHpT) -- to the ms, so a 3.000 s delta is not binned as 2.9999
        local bin = math.floor(d / HIST_STEP) + 1
        if bin > HIST_BINS then
            bin = HIST_BINS + 1
        elseif bin < 1 then
            bin = 1
        end
        local all = o9.all
        all[bin] = all[bin] + 1
        all.n = all.n + 1
        if not autoAttack and o9.leaveSeen > 0 then
            local off = o9.autoOff
            off[bin] = off[bin] + 1
            off.n = off.n + 1
        end
    end
    lastHpT = now
    local dead = DeadNow()
    if dead and not lastDead then
        o6.deadSeen = o6.deadSeen + 1
    end
    lastDead = dead
end

local function OnDeath(now, event, a1, a2)
    o6.n = o6.n + 1
    local head = o6.ringHead % DEATH_RING + 1
    o6.ringHead = head
    local r = o6.ring[head]
    if not r then
        r = {}
        o6.ring[head] = r
    end
    local okD, dead = false, nil
    if type(UnitIsDead) == "function" then
        okD, dead = pcall(UnitIsDead, "target")
    end
    r.seq, r.t, r.ev, r.a1, r.a2 = o6.n, Round(now), event, Enc(a1), Enc(a2)
    if okD then
        r.dead = Enc(dead)
    else
        r.dead = type(UnitIsDead) == "function" and "E" or "-"
    end
    r.vr = UsableCode("Victory Rush")
    if event == "PLAYER_TARGET_DIED" then
        o6.targetDied = o6.targetDied + 1
    end
end

local function O14Sample(moment)
    local f = C_CombatLog and C_CombatLog.IsCombatLogRestricted
    local at = GetSlot(o14.at, moment)
    local side = GetSlot(o14, ns.InCombat() and "in" or "out")
    if type(f) ~= "function" then
        at.api, side.api, o14.api = "-", "-", "-"
        return
    end
    local ok, v = pcall(f)
    if not ok then
        at.E = (at.E or 0) + 1
        at.err = at.err or ErrText(v)
        return
    end
    Classify(at, v)
    Classify(side, v)
end

local function O14After()
    if sess then
        O14Sample("afterDisabled")
    end
end

-- Extra reads at firing time, classified into rec.reads (tables walked into rec.readFields).
local EXTRA = {}
local function PlateReads(rec, u)
    if IsSecret(u) or type(u) ~= "string" then
        local s = GetSlot(rec.reads, "tokenSkipped")
        s.S = s.S + 1
        return
    end
    Read(rec, "guid", nil, UnitGUID, u)
    Read(rec, "dead", nil, UnitIsDead, u)
    Read(rec, "canAttack", nil, UnitCanAttack, "player", u)
end
EXTRA.NAME_PLATE_UNIT_ADDED = PlateReads
EXTRA.NAME_PLATE_UNIT_REMOVED = PlateReads
EXTRA.LOSS_OF_CONTROL_ADDED = function(rec, _, index)
    if IsSecret(index) then
        local s = GetSlot(rec.reads, "indexSecret")
        s.S = s.S + 1
        return
    end
    Read(rec, "loc", nil, C_LossOfControl and C_LossOfControl.GetActiveLossOfControlData, index)
end
local function ComboReads(rec)
    Read(rec, "cp", nil, GetComboPoints, "player", "target")
end
EXTRA.COMBO_TARGET_CHANGED = ComboReads
EXTRA.UNIT_COMBO_POINTS = ComboReads
local function MeterReads(rec)
    Read(rec, "available", "reason", C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable)
end
EXTRA.DAMAGE_METER_COMBAT_SESSION_UPDATED = MeterReads
EXTRA.DAMAGE_METER_CURRENT_SESSION_UPDATED = MeterReads
local function PetReads(rec)
    Read(rec, "petExists", nil, UnitExists, "pet")
    Read(rec, "petGUID", nil, UnitGUID, "pet")
    Read(rec, "totem1", nil, GetTotemInfo, 1)
end
EXTRA.UNIT_PET = PetReads
EXTRA.PLAYER_TOTEM_UPDATE = PetReads
EXTRA.PET_ATTACK_START = PetReads
EXTRA.PET_ATTACK_STOP = PetReads
EXTRA.UNIT_HAPPINESS = PetReads
EXTRA.COMBAT_TEXT_UPDATE = function(rec)
    Read(rec, "info1", "info2", C_CombatText and C_CombatText.GetCurrentEventInfo)
end

-- Correlator hooks: fn(now, inCombat, ...event args).
local CORR = {}
CORR.PLAYER_SWING = function(now, _, dur, hand)
    OnSwing(now, dur, hand)
end
CORR.UNIT_POWER_FREQUENT = function(now, _, u, powerToken)
    if not IsSecret(u) and u == "player" and not IsSecret(powerToken) and powerToken == "RAGE" then
        OnPlayerRage(now)
    end
end
CORR.UNIT_SPELLCAST_SUCCEEDED = function(_, _, u, _, spellID)
    if not IsSecret(u) and u == "player" then
        OnPlayerSuccess(spellID)
    end
end
CORR.UNIT_HEALTH = function(now, inC, u)
    if not IsSecret(u) and u == "target" then
        OnTargetHealth(now, inC)
    end
end
CORR.PLAYER_TARGET_CHANGED = function()
    lastHpT = 0
    lastDead = DeadNow()
end
CORR.PLAYER_ENTER_COMBAT = function()
    autoAttack = true
end
CORR.PLAYER_LEAVE_COMBAT = function()
    if autoAttack then
        o9.leaveSeen = o9.leaveSeen + 1
    end
    autoAttack = false
end
CORR.PLAYER_REGEN_DISABLED = function()
    lastHpT = 0
    O14Sample("regenDisabled")
    if C_Timer and C_Timer.After then
        C_Timer.After(0, O14After)
    end
end
CORR.PLAYER_REGEN_ENABLED = function()
    O14Sample("regenEnabled")
end
local function DeathHook(event)
    return function(now, _, a1, a2)
        OnDeath(now, event, a1, a2)
    end
end
CORR.UNIT_DIED = DeathHook("UNIT_DIED")
CORR.PARTY_KILL = DeathHook("PARTY_KILL")
CORR.PLAYER_TARGET_DIED = DeathHook("PLAYER_TARGET_DIED")

local function Err(where, err)
    sess.errors = (sess.errors or 0) + 1
    sess.lastErr = where .. " " .. ErrText(err)
end

-- The classifier ---------------------------------------------------------------------------------------------------

frame:SetScript("OnEvent", function(_, event, ...)
    if not sess then
        return
    end
    local ev = evs[event]
    if not ev then
        return
    end
    local now = GetTime()
    local inC = ns.InCombat()
    local bucket
    if event == "COMBAT_TEXT_UPDATE" then
        bucket = FctBucket()
    elseif ev.unit then
        bucket = Bucket((...))
    else
        bucket = "all"
    end
    local rec = ev.b[bucket]
    if not rec then
        rec = NewRec(now)
        ev.b[bucket] = rec
    end
    ev.n = ev.n + 1
    rec.n = rec.n + 1
    if inC then
        rec.nC = rec.nC + 1
    end
    rec.lastT = Round(now)
    local nargs = select("#", ...)
    if nargs > MAX_ARGS then
        nargs = MAX_ARGS
        rec.cut = true
    end
    local args = rec.args
    for i = 1, nargs do
        local slot = args[i]
        if not slot then
            slot = NewSlot()
            args[i] = slot
        end
        Classify(slot, (select(i, ...)), rec.fields, i)
    end
    local x = EXTRA[event]
    if x then
        local ok, err = pcall(x, rec, ...)
        if not ok then
            Err(event, err)
        end
    end
    local c = CORR[event]
    if c then
        local ok, err = pcall(c, now, inC, ...)
        if not ok then
            Err(event, err)
        end
    end
end)

-- Squares ----------------------------------------------------------------------------------------------------------

local function SumSlot(slot, acc2)
    acc2.S = acc2.S + slot.S
    acc2.P = acc2.P + slot.P
end

local function SumFieldMap(map, acc2)
    for _, f in pairs(map) do
        for _, slot in pairs(f) do
            SumSlot(slot, acc2)
        end
    end
end

local sums = { S = 0, P = 0 } -- reused by every recompute

local function PartsColour(parts)
    local anyReg, n = false, 0
    sums.S, sums.P = 0, 0
    for _, part in ipairs(parts) do
        local ev = evs[part[1]]
        if ev then
            if ev.reg == "ok" then
                anyReg = true
            end
            local only, except = part.only, part.except
            for bucket, rec in pairs(ev.b) do
                if (not only or only[bucket]) and (not except or not except[bucket]) then
                    n = n + rec.n
                    if bucket == "S" then
                        sums.S = sums.S + rec.n
                    end
                    -- arg 1 of a unit event is the token (its secrecy is the "S" bucket); the payload decides.
                    for i = ev.unit and 2 or 1, #rec.args do
                        SumSlot(rec.args[i], sums)
                    end
                    SumFieldMap(rec.fields, sums)
                    for _, slot in pairs(rec.reads) do
                        SumSlot(slot, sums)
                    end
                    SumFieldMap(rec.readFields, sums)
                end
            end
        end
    end
    if not anyReg then
        return "dark"
    elseif n == 0 then
        return "grey"
    elseif sums.S == 0 then
        return "green"
    elseif sums.P == 0 then
        return "red"
    end
    return "yellow"
end

local function AnyReg(parts)
    for _, part in ipairs(parts) do
        local ev = evs[part[1]]
        if ev and ev.reg == "ok" then
            return true
        end
    end
    return false
end

local function ProbeColour(p)
    if p.id == "O14" then
        if o14.api == "-" then
            return "dark"
        end
        local s = sums
        s.S, s.P = 0, 0
        for _, slot in pairs(o14.at) do
            SumSlot(slot, s)
        end
        if s.P > 0 and s.S > 0 then
            return "yellow"
        elseif s.P > 0 then
            return "green"
        elseif s.S > 0 then
            return "red"
        end
        return "grey"
    elseif p.id == "O11" then
        if not AnyReg(p.parts) then
            return "dark"
        elseif o11.rangedSwings > 0 then
            return "green"
        elseif o11.rangedCasts > 0 then
            return "yellow"
        elseif o3.hands.hS then
            return "red"
        end
        return "grey"
    elseif p.id == "O16" then
        if not AnyReg(p.parts) then
            return "dark"
        end
        local a = o16.after
        local plain = a.t + a.f
        if plain > 0 and a.S > 0 then
            return "yellow"
        elseif plain > 0 then
            return "green"
        elseif a.S > 0 then
            return "red"
        end
        return "grey"
    end
    return PartsColour(p.parts)
end

local function EventFired(name, exceptPlayer)
    local ev = evs[name]
    if not ev then
        return false
    end
    for bucket, rec in pairs(ev.b) do
        if rec.n > 0 and (not exceptPlayer or bucket ~= "player") then
            return true
        end
    end
    return false
end

local function UpdateChecklist()
    local c = sess.checklist
    if EventFired("UNIT_SPELLCAST_INTERRUPTED", true) then
        c.interrupt = true
    end
    if o16.flips > 0 or o3.noPowerOpTrue > 0 then
        c.dodge = true
    end
    if o9.autoOff.n >= 3 then
        c.rend = true
    end
    if o6.targetDied > 0 or o6.deadSeen > 0 then
        c.kill = true
    end
    if EventFired("COMBO_TARGET_CHANGED") then
        c.combo = true
    end
    if o11.rangedSwings + o11.rangedCasts > 0 then
        c.ranged = true
    end
end

-- Panel ------------------------------------------------------------------------------------------------------------

local COLOURS = {
    dark = { 0.1, 0.1, 0.1 }, grey = { 0.5, 0.5, 0.5 }, green = { 0.2, 0.85, 0.3 },
    red = { 0.9, 0.2, 0.2 }, yellow = { 0.95, 0.8, 0.2 },
}
local CHECKLIST = {
    { key = "interrupt", text = "Interrupt a casting mob once (O4)" },
    { key = "dodge", text = "Get dodged: fight a higher-level mob (O3, O16)" },
    { key = "rend", text = "Apply Rend (or a DoT), then stop auto-attack 10 s (O9)" },
    { key = "kill", text = "Kill one mob (O6, O8)" },
    { key = "combo", text = "Swap targets with combo points (O15)", druidRogue = true },
    { key = "ranged", text = "Optional: a ranged shot, if the class has one (O11)" },
}
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TITLE = "ForeverProbe session O: combat events (/fprobe o stop)"
local panel, W

local function Label(parent, text, size)
    local s = parent:CreateFontString(nil, "OVERLAY")
    s:SetFont(FONT, size or 10, "OUTLINE")
    s:SetText(text)
    return s
end

local function Build()
    W = { squares = {}, shown = {}, lines = {} }
    panel = CreateFrame("Frame", "ForeverProbeSessionO", UIParent)
    panel:SetSize(330, 244)
    panel:SetPoint("CENTER", UIParent, "CENTER", -380, 120)
    panel:SetFrameStrata("HIGH")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    W.title = Label(panel, TITLE, 11)
    W.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
    W.phase = Label(panel, "", 9)
    W.phase:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -24)
    for i, p in ipairs(PROBES) do
        local row = math.floor((i - 1) / 8)
        local col = (i - 1) % 8
        local x, y = 12 + col * 39, -42 - row * 36
        local slot = panel:CreateTexture(nil, "BACKGROUND")
        slot:SetSize(20, 20)
        slot:SetPoint("TOPLEFT", panel, "TOPLEFT", x - 1, y + 1)
        slot:SetColorTexture(0.35, 0.35, 0.35, 0.5)
        local t = panel:CreateTexture(nil, "ARTWORK")
        t:SetSize(18, 18)
        t:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        t:SetColorTexture(0.5, 0.5, 0.5, 1)
        W.squares[i] = t
        Label(panel, p.id, 9):SetPoint("TOPLEFT", panel, "TOPLEFT", x, y - 20)
    end
    local legend = Label(panel, "grey not fired | green plain | red secret | yellow mixed | dark unregisterable", 8)
    legend:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -114)
    local legend2 = Label(panel, "O11 yellow: shots seen, no type-2 swing | O11 red: only secret swing types", 8)
    legend2:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -126)
    for i, item in ipairs(CHECKLIST) do
        local l = Label(panel, "- " .. item.text, 9)
        l:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -140 - (i - 1) * 14)
        W.lines[i] = l
    end
    W.announce = Label(panel, "", 9)
    W.announce:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -140 - #CHECKLIST * 14)
end

local function UpdatePanel()
    if not panel or not panel:IsShown() or not sess then
        return
    end
    for i, p in ipairs(PROBES) do
        local col = sess.squares[p.id]
        if W.shown[i] ~= col then
            W.shown[i] = col
            local c = COLOURS[col] or COLOURS.grey
            W.squares[i]:SetColorTexture(c[1], c[2], c[3], 1)
        end
    end
    local secs = math.floor(o2.aCombat)
    local key = o2.phase .. tostring(o2.cur) .. secs .. (sess.stopped and "s" or "")
    if W.phaseKey ~= key then
        W.phaseKey = key
        W.phase:SetText(string.format("O2 floating combat text %s, phase %s | in-combat seconds in phase A: %d/%d%s",
            tostring(o2.cur), o2.phase, secs, FCT_COMBAT_SECONDS, sess.stopped and " | STOPPED" or ""))
    end
    for i, item in ipairs(CHECKLIST) do
        local done = sess.checklist[item.key] == true
        local na = item.druidRogue and classToken ~= "DRUID" and classToken ~= "ROGUE"
        local state = na and "na" or (done and "done" or "todo")
        if W.lines[i].state ~= state then
            W.lines[i].state = state
            if state == "na" then
                W.lines[i]:SetTextColor(0.45, 0.45, 0.45)
            elseif state == "done" then
                W.lines[i]:SetTextColor(0.3, 0.95, 0.4)
            else
                W.lines[i]:SetTextColor(1, 1, 1)
            end
        end
    end
    if o2.announced and W.announceText ~= o2.announced then
        W.announceText = o2.announced
        W.announce:SetText("|cffffd100" .. o2.announced .. "|r")
    end
end

local function ShowPanel()
    if not panel then
        local ok, err = pcall(Build)
        if not ok then
            Print("session O panel failed to build: " .. ErrText(err))
            if sess then
                sess.panelErr = ErrText(err)
            end
            return
        end
    end
    panel:Show()
    UpdatePanel()
end

local function Tick()
    local inC = ns.InCombat()
    FctTick(inC)
    for _, p in ipairs(PROBES) do
        sess.squares[p.id] = ProbeColour(p)
    end
    UpdateChecklist()
    UpdatePanel()
end

driver:SetScript("OnUpdate", function(_, elapsed)
    if not sess then
        return
    end
    if o2.phase == "A" and o2.cur == "1" and ns.InCombat() then
        o2.aCombat = o2.aCombat + elapsed
    end
    acc = acc + elapsed
    if acc < TICK then
        return
    end
    acc = 0
    local ok, err = pcall(Tick)
    if not ok then
        Err("tick", err)
    end
end)

-- Summary ----------------------------------------------------------------------------------------------------------

-- Per argument position across the matching buckets: P all plain, S all secret, M mixed, - nil only.
local function Pattern(ev, part)
    local S, P = {}, {}
    local max = 0
    for bucket, rec in pairs(ev.b) do
        if (not part.only or part.only[bucket]) and (not part.except or not part.except[bucket]) then
            for i, slot in ipairs(rec.args) do
                S[i] = (S[i] or 0) + slot.S
                P[i] = (P[i] or 0) + slot.P
                if i > max then
                    max = i
                end
            end
        end
    end
    local out = {}
    for i = 1, max do
        local s, p = S[i] or 0, P[i] or 0
        out[i] = (s > 0 and p > 0 and "M") or (s > 0 and "S") or (p > 0 and "P") or "-"
    end
    return table.concat(out)
end

local function PartsFact(parts)
    local bits = {}
    for _, part in ipairs(parts) do
        local ev = evs[part[1]]
        if ev then
            local n = 0
            for bucket, rec in pairs(ev.b) do
                if (not part.only or part.only[bucket]) and (not part.except or not part.except[bucket]) then
                    n = n + rec.n
                end
            end
            if ev.reg ~= "ok" then
                table.insert(bits, part[1] .. " reg " .. string.sub(tostring(ev.reg), 1, 40))
            elseif n > 0 then
                table.insert(bits, string.format("%s %d [%s]", part[1], n, Pattern(ev, part)))
            end
        end
    end
    if #bits == 0 then
        return "not fired"
    end
    return table.concat(bits, "; ")
end

local function HistMode(h)
    local best, bi = 0, nil
    for i = 1, HIST_BINS + 1 do
        if h[i] > best then
            best, bi = h[i], i
        end
    end
    if not bi then
        return "-"
    elseif bi > HIST_BINS then
        return ">6 s"
    end
    return string.format("%.2f-%.2f s", (bi - 1) * HIST_STEP, bi * HIST_STEP)
end

local function Fact(p)
    if p.id == "O3" then
        local bits = {}
        for hk, h in pairs(o3.hands) do
            table.insert(bits, string.format("%s %d (landed %d, no power %d)", hk, h.swings, h.landed, h.noPower))
        end
        table.sort(bits)
        return string.format("%s; OP flips %d, OP after no-power %d", #bits > 0 and table.concat(bits, ", ") or "no swings",
            o3.opFlips, o3.noPowerOpTrue)
    elseif p.id == "O2" then
        local b = evs.COMBAT_TEXT_UPDATE.b
        return string.format("%s | FCT on (A) %d, off (B) %d, unknown (X) %d | cvar was %s", PartsFact(p.parts), b.A and b.A.n or 0,
            b.B and b.B.n or 0, b.X and b.X.n or 0, tostring(o2.orig or o2.cvarErr))
    elseif p.id == "O6" then
        return PartsFact(p.parts) .. string.format(" | target dead seen %d", o6.deadSeen)
    elseif p.id == "O9" then
        return string.format("%s | deltas %d (mode %s), auto-attack off %d (mode %s)", PartsFact(p.parts), o9.all.n, HistMode(o9.all),
            o9.autoOff.n, HistMode(o9.autoOff))
    elseif p.id == "O11" then
        return string.format("ranged swings %d, ranged casts %d", o11.rangedSwings, o11.rangedCasts)
    elseif p.id == "O14" then
        local i, o = o14["in"], o14.out
        return string.format("in combat P%d S%d %s | out P%d S%d %s", i and i.P or 0, i and i.S or 0, i and tostring(i.samples[1]) or "",
            o and o.P or 0, o and o.S or 0, o and tostring(o.samples[1]) or "")
    elseif p.id == "O16" then
        local a = o16.after
        return string.format("player successes %d; OP after: t%d f%d S%d N%d; flips %d", o16.successes, a.t, a.f, a.S, a.N, o16.flips)
    end
    return PartsFact(p.parts)
end

local function Summary()
    local lines = {}
    local nEv, nFail, nFired = 0, 0, 0
    for _, ev in pairs(evs) do
        nEv = nEv + 1
        if ev.reg ~= "ok" then
            nFail = nFail + 1
        end
        if ev.n > 0 then
            nFired = nFired + 1
        end
    end
    table.insert(lines, string.format("session O %s: %d events, %d unregisterable, %d fired; errors %d", sess.started, nEv, nFail, nFired, sess.errors or 0))
    for _, p in ipairs(PROBES) do
        local ok, fact = pcall(Fact, p)
        if not ok then
            fact = ErrText(fact)
        end
        table.insert(lines, string.format("%s %s: %s", p.id, string.upper(sess.squares[p.id] or "?"), string.sub(fact, 1, 220)))
    end
    return lines
end

-- Sessions ---------------------------------------------------------------------------------------------------------

local function NewHist()
    local h = { n = 0 }
    for i = 1, HIST_BINS + 1 do
        h[i] = 0
    end
    return h
end

local function StatusLine()
    if not sess then
        return "session O not running (/fprobe o to start)"
    end
    local fired, fails = 0, 0
    for _, ev in pairs(evs) do
        if ev.n > 0 then
            fired = fired + 1
        end
        if ev.reg ~= "ok" then
            fails = fails + 1
        end
    end
    return string.format("session O %s running | %d events fired, %d unregisterable | FCT phase %s (%s) | %s", sess.started, fired, fails,
        o2.phase, tostring(o2.cur), ns.InCombat() and "IN COMBAT" or "out of combat")
end
SessionO.StatusLine = StatusLine

function SessionO.Start()
    if sess then
        ShowPanel()
        Print(StatusLine())
        return
    end
    local id = date("%Y-%m-%d %H:%M:%S") .. " O"
    while db.sessions[id] do
        id = id .. "+"
    end
    local okC, _, class = pcall(UnitClass, "player")
    classToken = (okC and not IsSecret(class) and type(class) == "string") and class or nil
    sess = { kind = "O", started = id, version = ns.VERSION, notes = {}, events = {}, absent = {}, squares = {}, checklist = {} }
    sess.class = okC and Enc(class) or "E"
    local okL, level = pcall(UnitLevel, "player")
    sess.level = okL and Enc(level) or "E"
    local okB, version, build, _, iface = pcall(GetBuildInfo)
    if okB then
        sess.build = tostring(version) .. " " .. tostring(build) .. " " .. tostring(iface)
    end
    sess.has = {
        issecretvalue = issecretvalue ~= nil, C_Timer = C_Timer ~= nil, C_CVar = C_CVar ~= nil,
        C_CombatLog = C_CombatLog ~= nil, C_CombatText = C_CombatText ~= nil, C_DamageMeter = C_DamageMeter ~= nil,
        C_LossOfControl = C_LossOfControl ~= nil, GetComboPoints = GetComboPoints ~= nil, GetTotemInfo = GetTotemInfo ~= nil,
    }
    evs = sess.events
    if o2 and o2.restored == "deferred" then
        o2.restored = "handed to the next session"
    end
    o2 = { phase = "A", aCombat = 0 }
    o3 = { hands = {}, opFlips = 0, noPowerOpTrue = 0, dropped = 0, ring = {}, ringHead = 0, ringN = 0 }
    o6 = { n = 0, deadSeen = 0, targetDied = 0, ring = {}, ringHead = 0 }
    o9 = { all = NewHist(), autoOff = NewHist(), binWidth = HIST_STEP, leaveSeen = 0 }
    o11 = { rangedSwings = 0, rangedCasts = 0, casts = {} }
    o14 = { at = {} }
    o16 = { successes = 0, before = NewCodes(), after = NewCodes(), flips = 0, dropped = 0, spells = {}, nSpells = 0 }
    sess.O2, sess.O3, sess.O6, sess.O9, sess.O11, sess.O14, sess.O16 = o2, o3, o6, o9, o11, o14, o16
    db.sessions[id] = sess
    if ns.PruneSessions then
        ns.PruneSessions()
    end

    -- Runtime state.
    lastPowerT, lastHpT, pendN, acc = -1, 0, 0, 0
    lastOp = UsableCode("Overpower")
    lastDead = DeadNow()
    for i = 1, O16_SLOTS do
        qUsed[i] = false
    end
    autoAttack = false
    local isc = C_Spell and C_Spell.IsCurrentSpell
    if type(isc) == "function" then
        local ok, v = pcall(isc, 6603)
        autoAttack = ok and not IsSecret(v) and v == true
    end

    -- Register every event, each under pcall.
    local nOk = 0
    for _, e in ipairs(EVENTS) do
        local name = e[1]
        local ok, err = pcall(frame.RegisterEvent, frame, name)
        if ok then
            nOk = nOk + 1
        end
        evs[name] = { reg = ok and "ok" or ErrText(err), documented = e[2], unit = e[3], n = 0, b = {} }
        if not e[2] then
            table.insert(sess.absent, name)
        end
    end

    -- O2: remember the user's FCT value, then phase A (FCT on). A restore still pending from an earlier session
    -- (stopped in combat, or left running across a reload in combat) holds the user's real original: keep it, and
    -- this session owns the restore from now on.
    local cur, why = GetFct()
    local orig = cur
    if db.fctRestore ~= nil then
        orig = db.fctRestore
        o2.inherited = true
        guard:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    o2.orig, o2.cvarErr, o2.cur = orig, why, cur
    if orig ~= nil then
        db.fctRestore = orig
        if cur ~= "1" then
            if ns.InCombat() then
                o2.pendingA = true
            else
                o2.setA, o2.cur = SetFct("1")
            end
        end
    end

    O14Sample("start")
    driver:Show()
    Tick()
    if W and W.title then
        W.title:SetText(TITLE)
        W.announce:SetText("")
        W.announceText = nil
    end
    ShowPanel()
    Print(string.format("session O %s started: %d events armed, %d unregisterable. Floating combat text is ON (O2 phase A); "
        .. "after %d s of combat it turns OFF at the next out-of-combat moment. /fprobe o stop when the checklist is done.",
        id, nOk, #EVENTS - nOk, FCT_COMBAT_SECONDS))
end

function SessionO.Stop()
    if not sess then
        Print("session O is not running")
        return
    end
    frame:UnregisterAllEvents()
    driver:Hide()
    local ok, err = pcall(Tick)
    if not ok then
        Err("tick", err)
    end
    RestoreFct()
    sess.stopped = date("%Y-%m-%d %H:%M:%S")
    local lines = Summary()
    sess.summary = lines
    for _, l in ipairs(lines) do
        print(l)
    end
    UpdatePanel()
    if W and W.title then
        W.title:SetText("ForeverProbe session O: STOPPED (/fprobe o panel hides this)")
    end
    Print("session O closed. /reload (or log out) to write ForeverProbeDB to disk.")
    sess, evs = nil, nil
    pendN = 0
end

function SessionO.Command(rest)
    rest = string.lower(rest or "")
    if rest == "" or rest == "start" then
        SessionO.Start()
    elseif rest == "stop" then
        SessionO.Stop()
    elseif rest == "fct" then
        if not sess then
            Print("session O is not running")
        elseif o2.phase == "B" then
            Print("O2 is already in phase B (floating combat text off)")
        elseif o2.orig == nil then
            Print("O2: the CVar could not be read (" .. tostring(o2.cvarErr) .. "); nothing to switch")
        else
            o2.force = true
            if ns.InCombat() then
                Print("O2: switching floating combat text off when this combat ends")
            else
                FctTick(false)
            end
        end
    elseif rest == "panel" then
        if panel and panel:IsShown() then
            panel:Hide()
        else
            ShowPanel()
        end
    elseif rest == "status" then
        Print(StatusLine())
    else
        Print("usage: /fprobe o | o stop | o fct | o panel | o status")
    end
end

-- The running session's notes table (Core's /fprobe note writes here too), or nil.
function SessionO.Notes()
    return sess and sess.notes
end

-- For the headless smoke test.
function SessionO.Current()
    return sess
end

-- Called from Core's loader once ForeverProbeDB is set: restores the FCT CVar if a session was left running across
-- a reload or a crash (db.fctRestore is still set).
function SessionO.Init(d)
    db = d
    if db.fctRestore ~= nil then
        RestoreFct()
    end
end
