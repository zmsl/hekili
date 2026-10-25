-- Core.lua: shared helpers, the session store, the sampling engine, event dispatch and /fprobe.
--
-- Secret-value rules (Midnight API) followed in every file of this addon:
--   * every client value goes through IsSecret() before it is compared, indexed, concatenated or stored;
--   * no `a and b or c` on anything that could be secret (that truth-tests b);
--   * secrets are never stored (SavedVariables can't hold them): they are logged as "S";
--   * nothing divides or takes a modulo by a value that could be 0 (the client raises on x/0).
--
-- Encoding of every logged value: "S" secret, "nil" nil, "E:<msg>" the call errored, "-" the API is absent,
-- "=<text>" a plain string, otherwise the plain number (rounded to 0.001) or boolean.
local ADDON_NAME, ns = ...

ns.VERSION = "0.3.0"
local RING = 160 -- samples kept per probe per session (ring buffer; sort by seq)
local SESSIONS_KEPT = 4 -- older sessions are dropped
local EVENT_GAP = 0.1 -- min seconds between event-driven samples of one probe (unless `always`)
local DEFAULT_INTERVAL = 0.5

local db -- ForeverProbeDB
local defs = {} -- registered probe definitions, in registration order
local active = {} -- running probe objects
local byEvent = {} -- event -> list of running probe objects
ns.defs = defs
ns.spell = {} -- short key -> spellID, resolved at session start
ns.session = nil

-- Plain combat flag (never secret).
local InCombatFn = InCombatLockdown
if not InCombatFn and C_RestrictedActions then
    InCombatFn = C_RestrictedActions.InCombatLockdown
end
function ns.InCombat()
    return InCombatFn ~= nil and InCombatFn() == true
end

local function Print(msg)
    print("|cff33ff99ForeverProbe|r: " .. tostring(msg))
end
ns.Print = Print

-- Encoding -------------------------------------------------------------------------------------

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end
ns.IsSecret = IsSecret

local function Round(n)
    if n ~= n or n == math.huge or n == -math.huge then
        return n
    end
    return math.floor(n * 1000 + 0.5) / 1000
end
ns.Round = Round

local function Enc(v)
    if IsSecret(v) then
        return "S"
    end
    if v == nil then
        return "nil"
    end
    local k = type(v)
    if k == "number" then
        if v ~= v then
            return "=nan"
        elseif v == math.huge then
            return "=inf"
        elseif v == -math.huge then
            return "=-inf"
        end
        return Round(v)
    elseif k == "boolean" then
        return v
    elseif k == "string" then
        return "=" .. string.sub(v, 1, 80)
    end
    return "<" .. k .. ">"
end
ns.Enc = Enc

local function ErrText(err)
    if IsSecret(err) then
        return "E:<secret>"
    end
    return "E:" .. string.sub(tostring(err), 1, 120)
end
ns.ErrText = ErrText

-- Classifies an encoded value: S secret, N nil, A absent API, E error, P plain.
local function Code(e)
    if e == "S" then
        return "S"
    elseif e == "nil" then
        return "N"
    elseif e == "-" then
        return "A"
    elseif type(e) == "string" and string.sub(e, 1, 2) == "E:" then
        return "E"
    end
    return "P"
end
ns.Code = Code

-- Looks a global up by name (legacy APIs that may not exist on this client).
function ns.G(name)
    return _G[name]
end

-- Probe objects ----------------------------------------------------------------------------------

local ProbeMT = {}
ProbeMT.__index = ProbeMT

local function NewTally()
    return { c = { S = 0, N = 0, P = 0, E = 0, A = 0 }, o = { S = 0, N = 0, P = 0, E = 0, A = 0 } }
end

-- Counts one encoded value under `key`, split by in/out of combat; keeps the first and last plain example.
function ProbeMT:Tally(key, e)
    local t = self.data.tally[key]
    if not t then
        t = NewTally()
        self.data.tally[key] = t
    end
    local side = self.inCombat and t.c or t.o
    local code = Code(e)
    side[code] = side[code] + 1
    if code == "P" then
        if self.inCombat then
            if t.exC == nil then
                t.exC = e
            end
            t.lastC = e
        else
            if t.exO == nil then
                t.exO = e
            end
            t.lastO = e
        end
    elseif code == "E" then
        t.err = e
    end
end

-- Encodes `value` into the current sample under `key` and tallies it.
function ProbeMT:Rec(key, value)
    local e = Enc(value)
    if self.s then
        self.s[key] = e
    end
    self:Tally(key, e)
    return e
end

function ProbeMT:Absent(key)
    if self.s then
        self.s[key] = "-"
    end
    self:Tally(key, "-")
end

-- Calls fn(...) under pcall and records its returns under `keys` (a string, or a list where `false` skips
-- a position). An error is recorded under the first key.
function ProbeMT:Call(keys, fn, ...)
    if type(keys) == "string" then
        keys = { keys }
    end
    if type(fn) ~= "function" then
        for _, k in ipairs(keys) do
            if k then
                self:Absent(k)
            end
        end
        return
    end
    local res = { pcall(fn, ...) }
    if not res[1] then
        for _, k in ipairs(keys) do
            if k then
                local e = ErrText(res[2])
                if self.s then
                    self.s[k] = e
                end
                self:Tally(k, e)
                return
            end
        end
        return
    end
    for i, k in ipairs(keys) do
        if k then
            self:Rec(k, res[i + 1])
        end
    end
end

-- Records tbl[field] for each field under prefix..field; a secret or missing table marks every field.
function ProbeMT:Fields(prefix, tbl, fields)
    if IsSecret(tbl) then
        for _, f in ipairs(fields) do
            self:Rec(prefix .. f, tbl)
        end
        return
    end
    if type(tbl) ~= "table" then
        for _, f in ipairs(fields) do
            self:Rec(prefix .. f, nil)
        end
        return
    end
    for _, f in ipairs(fields) do
        self:Rec(prefix .. f, tbl[f])
    end
end

-- pcall(fn, ...) expecting a table; records its fields.
function ProbeMT:CallFields(prefix, fields, fn, ...)
    if type(fn) ~= "function" then
        for _, f in ipairs(fields) do
            self:Absent(prefix .. f)
        end
        return
    end
    local ok, tbl = pcall(fn, ...)
    if not ok then
        local e = ErrText(tbl)
        for _, f in ipairs(fields) do
            if self.s then
                self.s[prefix .. f] = e
            end
            self:Tally(prefix .. f, e)
        end
        return
    end
    self:Fields(prefix, tbl, fields)
end

-- One-off facts (session-level, not per sample).
function ProbeMT:Fact(key, value)
    self.data.facts[key] = Enc(value)
end

function ProbeMT:FactCall(keys, fn, ...)
    if type(keys) == "string" then
        keys = { keys }
    end
    if type(fn) ~= "function" then
        for _, k in ipairs(keys) do
            if k then
                self.data.facts[k] = "-"
            end
        end
        return
    end
    local res = { pcall(fn, ...) }
    if not res[1] then
        for _, k in ipairs(keys) do
            if k then
                self.data.facts[k] = ErrText(res[2])
                return
            end
        end
        return
    end
    for i, k in ipairs(keys) do
        if k then
            self.data.facts[k] = Enc(res[i + 1])
        end
    end
end

-- Pushes a record into a named ring of `cap` entries on the probe's session data.
function ProbeMT:Push(name, rec, cap)
    local d = self.data
    local list = d[name]
    if not list then
        list = {}
        d[name] = list
        d[name .. "N"] = 0
        d[name .. "Head"] = 0
    end
    local n = d[name .. "N"] + 1
    d[name .. "N"] = n
    rec.seq = n
    local head = d[name .. "Head"] % cap + 1
    d[name .. "Head"] = head
    list[head] = rec
end

-- Sampling -------------------------------------------------------------------------------------

local function TakeSample(p, trigger, ...)
    local now = GetTime()
    p.inCombat = ns.InCombat()
    local s = { t = Round(now), ev = trigger, c = p.inCombat }
    p.s = s
    local nargs = select("#", ...)
    for i = 1, math.min(nargs, 4) do
        local v = select(i, ...)
        if IsSecret(v) or v ~= nil then
            s["a" .. i] = Enc(v)
        end
    end
    local ok, err = pcall(p.def.sample, p)
    if not ok then
        s.err = ErrText(err)
        p.data.errors = (p.data.errors or 0) + 1
        p.data.lastErr = s.err
    end
    local d = p.data
    d.n = d.n + 1
    if p.inCombat then
        d.nC = d.nC + 1
    end
    d.head = d.head % RING + 1
    s.seq = d.n
    d.ring[d.head] = s
    p.s = nil
end

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function()
    local now = GetTime()
    for _, p in ipairs(active) do
        if p.def.sample and now >= p.nextAt then
            p.nextAt = now + p.interval
            TakeSample(p, "tick")
        end
    end
end)

-- Events ---------------------------------------------------------------------------------------

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, ...)
    if not ns.session then
        return
    end
    local list = byEvent[event]
    if not list then
        return
    end
    local inCombat = ns.InCombat()
    local now = GetTime()
    local nargs = select("#", ...)
    for _, p in ipairs(list) do
        local d = p.data
        local e = d.events[event]
        if not e then
            e = { n = 0, nC = 0, args = {} }
            d.events[event] = e
        end
        e.n = e.n + 1
        if inCombat then
            e.nC = e.nC + 1
        end
        for i = 1, math.min(nargs, 5) do
            local v = select(i, ...)
            local enc = Enc(v)
            local code = Code(enc)
            local a = e.args[i]
            if not a then
                a = { S = 0, N = 0, P = 0 }
                e.args[i] = a
            end
            a[code] = (a[code] or 0) + 1
            if code == "P" and a.ex == nil then
                a.ex = enc
            end
        end
        local def = p.def
        local pass = true
        if def.unitFilter then
            local unit = ...
            pass = (not IsSecret(unit)) and unit == def.unitFilter
        end
        if pass then
            if def.onEvent then
                local ok, err = pcall(def.onEvent, p, event, ...)
                if not ok then
                    d.errors = (d.errors or 0) + 1
                    d.lastErr = ErrText(err)
                end
            end
            local so = def.sampleOn
            if so and so[event] and def.sample then
                if (def.always and def.always[event]) or now - p.lastEvent >= EVENT_GAP then
                    p.lastEvent = now
                    TakeSample(p, event, ...)
                end
            end
        end
    end
end)

local function RegisterEvents(sess)
    for k in pairs(byEvent) do
        byEvent[k] = nil
    end
    local wanted = {}
    local function Want(event, p, unit)
        local w = wanted[event]
        if not w then
            w = { plain = false }
            wanted[event] = w
        end
        if not unit then
            w.plain = true
        end
        local list = byEvent[event]
        if not list then
            list = {}
            byEvent[event] = list
        end
        table.insert(list, p)
    end
    for _, p in ipairs(active) do
        for _, ev in ipairs(p.def.events or {}) do
            Want(ev, p, false)
        end
        for _, ev in ipairs(p.def.unitEvents or {}) do
            Want(ev, p, true)
        end
    end
    sess.registration = {}
    for event, w in pairs(wanted) do
        local ok, err
        if w.plain then
            ok, err = pcall(watcher.RegisterEvent, watcher, event)
        else
            ok, err = pcall(watcher.RegisterUnitEvent, watcher, event, "player", "target")
        end
        if ok then
            sess.registration[event] = w.plain and "all" or "player,target"
        else
            sess.registration[event] = ErrText(err)
        end
    end
end

-- Registration of probe definitions (Probes.lua) ---------------------------------------------------

function ns.Register(def)
    table.insert(defs, def)
end

-- Spell resolution -----------------------------------------------------------------------------

local SPELLS = {
    W = {
        hs = "Heroic Strike", cl = "Cleave", rd = "Rend", op = "Overpower", ex = "Execute", rv = "Revenge",
        ch = "Charge", br = "Bloodrage", bs = "Battle Shout", tc = "Thunder Clap", sa = "Sunder Armor",
        ww = "Whirlwind", ms = "Mortal Strike", bt = "Bloodthirst", pm = "Pummel", sb = "Shield Bash",
        hm = "Hamstring", bz = "Berserker Rage", dw = "Death Wish", ds = "Defensive Stance",
    },
    D = {
        sh = "Shred", rp = "Rip", rk = "Rake", cw = "Claw", fb = "Ferocious Bite", tf = "Tiger's Fury",
        ml = "Maul", sw = "Swipe", en = "Enrage", ds = "Dash", hu = "Hurricane", tq = "Tranquility",
        wr = "Wrath", mf = "Moonfire", sf = "Starfire", cf = "Cat Form", bf = "Bear Form", db = "Dire Bear Form",
        sp = "Shifting Power", ff = "Faerie Fire (Feral)", rg = "Regrowth", rj = "Rejuvenation", ba = "Bash",
        -- Rogue stand-ins for a Druid-less test: energy and combo points.
        ss = "Sinister Strike", ev = "Eviscerate",
    },
}
ns.SPELL_NAMES = SPELLS

-- Role spells each session uses: the first key that resolves wins.
local ROLES = {
    W = { melee = { "rd", "hm", "hs" }, cd = { "br", "bz", "dw" }, overlay = { "op", "ex", "rv", "hs" }, range = { "hs", "ch", "rd" }, queued = { "hs", "cl" } },
    D = { melee = { "cw", "rk", "sh", "ss" }, cd = { "tf", "en", "ds", "sp", "hu" }, overlay = { "sh", "rp", "fb", "rk", "ss" }, range = { "cw", "rk", "wr", "mf", "ss" }, queued = { "ml" } },
}

local function ResolveSpells(kind, sess)
    for k in pairs(ns.spell) do
        ns.spell[k] = nil
    end
    sess.spells = {}
    local gsi = C_Spell and C_Spell.GetSpellInfo
    for key, name in pairs(SPELLS[kind]) do
        local id
        if gsi then
            local ok, info = pcall(gsi, name)
            if ok and not IsSecret(info) and type(info) == "table" then
                local sid = info.spellID
                if not IsSecret(sid) and type(sid) == "number" then
                    id = sid
                end
            end
        end
        ns.spell[key] = id
        sess.spells[key] = { name = name, id = id or false }
    end
    ns.spell.at = 6603 -- Attack (auto attack), the IsCurrentSpell control
    sess.spells.at = { name = "Attack", id = 6603 }
    ns.role = {}
    for role, keys in pairs(ROLES[kind]) do
        for _, key in ipairs(keys) do
            if ns.spell[key] then
                ns.role[role] = key
                break
            end
        end
    end
    ns.role.overlayList = ROLES[kind].overlay
    ns.role.rangeList = ROLES[kind].range
    ns.role.queuedList = ROLES[kind].queued
    sess.roles = {}
    for role, key in pairs(ns.role) do
        if type(key) == "string" then
            sess.roles[role] = key
        end
    end
end

function ns.RoleSpell(role)
    local key = ns.role and ns.role[role]
    if key then
        return ns.spell[key], key
    end
    return nil, nil
end

-- Sessions -------------------------------------------------------------------------------------

local function GuessKind()
    local ok, _, class = pcall(UnitClass, "player")
    if ok and not IsSecret(class) and class == "DRUID" then
        return "D"
    elseif ok and not IsSecret(class) and class == "ROGUE" then
        return "D"
    end
    return "W"
end

local function PruneSessions()
    local keys = {}
    for k in pairs(db.sessions) do
        table.insert(keys, k)
    end
    table.sort(keys)
    while #keys > SESSIONS_KEPT do
        db.sessions[table.remove(keys, 1)] = nil
    end
end
ns.PruneSessions = PruneSessions

function ns.Start(kind)
    if ns.session then
        Print("a session is already running (" .. ns.sessionId .. "); /fprobe stop first")
        return
    end
    if kind ~= "W" and kind ~= "D" then
        kind = GuessKind()
    end
    local id = date("%Y-%m-%d %H:%M:%S") .. " " .. kind
    while db.sessions[id] do
        id = id .. "+"
    end
    local sess = { kind = kind, started = id, version = ns.VERSION, notes = {} }
    local okB, version, build, _, iface = pcall(GetBuildInfo)
    if okB then
        sess.build = tostring(version) .. " " .. tostring(build) .. " " .. tostring(iface)
    end
    local okC, _, class = pcall(UnitClass, "player")
    sess.class = okC and Enc(class) or "E"
    local okL, level = pcall(UnitLevel, "player")
    sess.level = okL and Enc(level) or "E"
    local okP, pt, token = pcall(UnitPowerType, "player")
    if okP then
        sess.powerType, sess.powerToken = Enc(pt), Enc(token)
        if not IsSecret(pt) and type(pt) == "number" then
            ns.powerType = pt
        end
    end
    sess.has = {
        issecretvalue = issecretvalue ~= nil,
        C_Secrets = C_Secrets ~= nil,
        C_CurveUtil = C_CurveUtil ~= nil,
        C_SwingTimer = C_SwingTimer ~= nil,
        C_SpellActivationOverlay = C_SpellActivationOverlay ~= nil,
        C_SpecializationInfo = C_SpecializationInfo ~= nil,
        C_Engraving = C_Engraving ~= nil,
        C_LossOfControl = C_LossOfControl ~= nil,
        C_TooltipInfo = C_TooltipInfo ~= nil,
        C_KeyBindings = C_KeyBindings ~= nil,
        C_PetInfo = C_PetInfo ~= nil,
        UnitPowerPercent = UnitPowerPercent ~= nil,
    }
    if C_Secrets and C_Secrets.HasSecretRestrictions then
        local ok, v = pcall(C_Secrets.HasSecretRestrictions)
        if ok then
            sess.secretRestrictions = Enc(v)
        else
            sess.secretRestrictions = ErrText(v)
        end
    end
    db.sessions[id] = sess
    PruneSessions()
    ns.session, ns.sessionId = sess, id
    ResolveSpells(kind, sess)

    for _, def in ipairs(defs) do
        local on = def.sessions.any or def.sessions[kind]
        if on then
            local data = { title = def.title, keys = def.keys, n = 0, nC = 0, head = 0, ring = {}, tally = {}, events = {}, facts = {} }
            sess[def.id] = data
            local p = setmetatable({ def = def, data = data, interval = def.interval or DEFAULT_INTERVAL, nextAt = 0, lastEvent = 0, inCombat = false }, ProbeMT)
            table.insert(active, p)
            if def.setup then
                local ok, err = pcall(def.setup, p)
                if not ok then
                    data.setupErr = ErrText(err)
                end
            end
        end
    end
    RegisterEvents(sess)
    if ns.Legacy then
        ns.Legacy.Start()
    end
    if ns.Display then
        ns.Display.Show()
    end
    if ns.Spike then
        ns.Spike.SetMeasuring(true)
    end
    ticker:Show()
    Print(string.format("session %s started: %d probes armed. /fprobe status | /fprobe stop", id, #active))
end

function ns.Stop()
    if not ns.session then
        Print("no session running")
        return
    end
    for _, p in ipairs(active) do
        if p.def.teardown then
            pcall(p.def.teardown, p)
        end
    end
    watcher:UnregisterAllEvents()
    for k in pairs(byEvent) do
        byEvent[k] = nil
    end
    for i = #active, 1, -1 do
        active[i] = nil
    end
    ticker:Hide()
    if ns.Legacy then
        ns.Legacy.Stop()
    end
    if ns.Spike then
        ns.Spike.Stats(true)
        ns.Spike.SetMeasuring(false)
        ns.Spike.Hide()
    end
    if ns.Display then
        ns.Display.Hide()
    end
    ns.session.stopped = date("%Y-%m-%d %H:%M:%S")
    Print("session " .. ns.sessionId .. " closed. /reload (or log out) to write ForeverProbeDB to disk.")
    ns.session, ns.sessionId = nil, nil
end

function ns.Note(text)
    local oNotes = ns.SessionO and ns.SessionO.Notes()
    if not ns.session and not oNotes then
        Print("no session running; notes need one")
        return
    end
    local t, c, body = date("%H:%M:%S"), ns.InCombat(), string.sub(text, 1, 200)
    if ns.session then
        table.insert(ns.session.notes, { t = t, c = c, text = body })
    end
    if oNotes then
        table.insert(oNotes, { t = t, c = c, text = body })
    end
    Print("noted: " .. text)
end

local function Status()
    if not ns.session then
        Print("no session running. /fprobe start W (Warrior) or /fprobe start D (Druid)")
    else
        Print(string.format("session %s | %d probes armed | %s", ns.sessionId, #active, ns.InCombat() and "IN COMBAT" or "out of combat"))
        for _, p in ipairs(active) do
            local d = p.data
            local evN = 0
            for _, e in pairs(d.events) do
                evN = evN + e.n
            end
            local extra = ""
            if d.errors then
                extra = " |cffff6060errors " .. d.errors .. "|r"
            end
            Print(string.format("  %s %s: %d samples (%d in combat), %d events%s", p.def.id, p.def.title, d.n, d.nC, evN, extra))
        end
        local roles = {}
        for role, key in pairs(ns.role or {}) do
            if type(key) == "string" then
                table.insert(roles, role .. "=" .. key)
            end
        end
        table.sort(roles)
        Print("  roles: " .. table.concat(roles, " "))
    end
    if ns.Legacy then
        ns.Legacy.Status()
    end
    if ns.Spike then
        ns.Spike.Status()
    end
    if ns.SessionO then
        Print(ns.SessionO.StatusLine())
    end
end

local function Help()
    Print("v" .. ns.VERSION .. " commands:")
    print("  /fprobe start W|D     start a Warrior or Druid session (arms the matching probes, shows the check panel)")
    print("  /fprobe stop          close the session (then /reload to save)")
    print("  /fprobe status        what is armed and how much was sampled")
    print("  /fprobe o             session O: combat-event classifier, O1-O16 squares + checklist (runs beside W/D)")
    print("  /fprobe o stop        end session O, restore floating combat text, print the summary")
    print("  /fprobe o fct         O2: switch floating combat text off now (phase B; deferred to out of combat)")
    print("  /fprobe o panel       toggle the session O panel")
    print("  /fprobe o status      one status line for session O")
    print("  /fprobe export        dump spellbook, talent trees and stances to ForeverProbeDB.export (out of combat)")
    print("  /fprobe note <text>   save a remark into the session (e.g. 'PR20 ok: left square lit under 35')")
    print("  /fprobe spike show|hide|stats|glide|reset   the two-zone spike frame (PR25-27, 29, 30)")
    print("  /fprobe panel show|hide                     the display-check panel (PR20-24, 28)")
    print("  /fprobe scale 0.8|1|1.2                      scale panel + spike (halo seam check)")
    print("  /fprobe menu          PR19: open a MenuUtil/UIDropDownMenu test menu")
    print("  /fprobe alloc         PR28: measure GetSpellCooldownDuration allocation now")
    print("  /fprobe on|off|clear|cleu   the legacy sampler (0.1.0 behaviour)")
end

SLASH_FOREVERPROBE1 = "/fprobe"
SlashCmdList.FOREVERPROBE = function(msg)
    if not db then
        Print("not loaded yet")
        return
    end
    msg = msg or ""
    local cmd, rest = string.match(msg, "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    if cmd == "" or cmd == "help" then
        Help()
        Status()
    elseif cmd == "start" or cmd == "on" then
        ns.Start(string.upper(string.sub(rest, 1, 1)))
    elseif cmd == "stop" or cmd == "off" then
        ns.Stop()
    elseif cmd == "status" then
        Status()
    elseif cmd == "note" then
        ns.Note(rest)
    elseif cmd == "export" then
        if ns.Export then
            ns.Export()
        else
            Print("Export.lua not loaded: restart the client (a new file in the TOC needs a full restart, not /reload)")
        end
    elseif cmd == "o" then
        if ns.SessionO then
            ns.SessionO.Command(rest)
        else
            Print("SessionO.lua not loaded: restart the client (a new file in the TOC needs a full restart, not /reload)")
        end
    elseif cmd == "spike" then
        if ns.Spike then
            ns.Spike.Command(string.lower(rest))
        end
    elseif cmd == "panel" then
        if ns.Display then
            if string.lower(rest) == "hide" then
                ns.Display.Hide()
            else
                ns.Display.Show()
            end
        end
    elseif cmd == "scale" then
        local v = tonumber(rest)
        if not v or v < 0.5 or v > 2 then
            Print("usage: /fprobe scale 0.8|1|1.2")
        else
            if ns.Display then
                ns.Display.SetScale(v)
            end
            if ns.Spike then
                ns.Spike.SetScale(v)
            end
            if ns.session then
                ns.Note("scale set to " .. v)
            end
            Print("scale " .. v)
        end
    elseif cmd == "menu" then
        if ns.MenuTest then
            ns.MenuTest()
        end
    elseif cmd == "alloc" then
        if ns.Display then
            ns.Display.MeasureAlloc(true)
        end
    elseif cmd == "clear" then
        if ns.Legacy then
            ns.Legacy.Clear()
        end
        Print("legacy log cleared")
    elseif cmd == "wipe" then
        if ns.session then
            Print("stop the session first")
        else
            db.sessions = {}
            Print("all sessions wiped")
        end
    elseif cmd == "cleu" then
        if ns.Legacy then
            Print("combat-log registration test " .. (ns.Legacy.ToggleCleu() and "ON (next start)" or "OFF"))
        end
    else
        Help()
    end
end

-- Loading ---------------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        ForeverProbeDB = ForeverProbeDB or {}
        db = ForeverProbeDB
        db.sessions = db.sessions or {}
        db.version = ns.VERSION
        ns.db = db
        if ns.Legacy then
            ns.Legacy.Init(db)
        end
        if ns.SessionO then
            ns.SessionO.Init(db)
        end
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        Print("loaded v" .. ns.VERSION .. ". /fprobe start W (Warrior) or /fprobe start D (Druid); /fprobe o (combat events); /fprobe for help.")
    end
end)
