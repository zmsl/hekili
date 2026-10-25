-- ForeverProbe: records which rotation inputs addon code can read on WoW Forever, in and out of
-- combat. /fprobe toggles recording; samples go to ForeverProbeDB (flushed on /reload or logout).
--
-- Secret-value rules followed throughout (Midnight API):
--   * every value is passed through issecretvalue() before it is compared, indexed or stored;
--   * no `a and b or c` on anything that could be secret (that tests b's truthiness);
--   * secrets are never stored (SavedVariables can't hold them) - they're logged as "S".
-- Encoding of each logged value: "S" = secret, "nil" = nil, "E:<msg>" = the call errored,
-- "-" = API absent, otherwise the plain value (number, boolean or string).
--
-- This is the 0.1.0 sampler, kept as the "legacy" probe: it runs inside every session (started and stopped by
-- Core.lua) and writes to the top-level ForeverProbeDB.samples/events/runs as before.
local _, ns = ...

local MAX_SAMPLES = 2000
local INTERVAL = 0.25 -- seconds between timed samples
local EVENT_GAP = 0.05 -- minimum seconds between event-driven samples (cast events bypass it)

local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
local COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
local GCD_SPELL = 29515 -- Forever's GCD reference spell (Catnip SpellTiming.lua)

-- Plain boolean combat flag (never secret). The global is what Blizzard's UI calls; the
-- documented home on this API is C_RestrictedActions.
local InCombat = InCombatLockdown
if not InCombat and C_RestrictedActions then
    InCombat = C_RestrictedActions.InCombatLockdown
end

-- Short keys keep the log small; the legend is saved with the data.
local SPELLS = {
    { key = "sh", name = "Shred" },
    { key = "rp", name = "Rip" },
    { key = "fb", name = "Ferocious Bite" },
    { key = "rk", name = "Rake" },
    { key = "cl", name = "Claw" },
    { key = "tf", name = "Tiger's Fury" },
    -- Level-1 Rogue equivalents (energy + combo points), for testing without a leveled Druid.
    { key = "ss", name = "Sinister Strike" },
    { key = "ev", name = "Eviscerate" },
    -- Warrior (rage): cost-gated, DoT and proc-gated (Overpower after a dodge) usability.
    { key = "hs", name = "Heroic Strike" },
    { key = "rd", name = "Rend" },
    { key = "op", name = "Overpower" },
    { key = "tc", name = "Thunder Clap" },
}

local LEGEND = {
    seq = "sample sequence number (ring buffer; sort by this)",
    t = "GetTime() rounded to 0.01",
    ev = "what triggered the sample: 'tick' or an event name",
    c = "InCombatLockdown()",
    ac = "UnitAffectingCombat('player')",
    ["u_<sp>"] = "C_Spell.IsSpellUsable isUsable for spell <sp>",
    ["p_<sp>"] = "C_Spell.IsSpellUsable insufficientPower for spell <sp>",
    shc = "C_Spell.GetSpellPowerCost('Shred')[1].cost (Clearcasting proxy)",
    tfA = "C_Spell.GetSpellCooldown(Tiger's Fury).isActive",
    tfG = "C_Spell.GetSpellCooldown(Tiger's Fury).isOnGCD",
    gcd = "C_Spell.GetSpellCooldown(29515).isActive",
    acN = "C_AssistedCombat.GetNextCastSpell(false)",
    acA = "C_AssistedCombat.IsAvailable() isAvailable",
    acR = "C_AssistedCombat.IsAvailable() failureReason",
    acS = "C_AssistedCombat.GetActionSpell()",
    th = "UnitHealth('target')",
    thm = "UnitHealthMax('target')",
    te = "UnitExists('target')",
    tca = "UnitCanAttack('player','target')",
    en = "UnitPower('player', Energy)",
    enm = "UnitPowerMax('player', Energy)",
    upc = "UnitPower('player', ComboPoints)",
    cp = "GetComboPoints('player','target')",
    pt = "UnitPowerType('player')",
    ff = "GetShapeshiftFormID()",
    np = "#C_NamePlate.GetNamePlates()",
    nph = "nameplates whose unit UnitCanAttack('player', unit) is plainly true",
    npE = "nameplate units whose UnitCanAttack result was secret",
    sA = "C_Secrets.ShouldAurasBeSecret()",
    sC = "C_Secrets.ShouldCooldownsBeSecret()",
    sP = "C_Secrets.ShouldUnitPowerBeSecret('player', Energy)",
    sCP = "C_Secrets.ShouldUnitPowerBeSecret('player', ComboPoints)",
    sH = "C_Secrets.ShouldUnitHealthMaxBeSecret('target')",
    a1 = "event arg 1 (unit / swing duration / etc.)",
    a3 = "event spellID for UNIT_SPELLCAST_SUCCEEDED/SENT (arg 3/4), else arg 3",
    ui = "UNIT_AURA updateInfo table (S if the table is secret)",
}

local db -- ForeverProbeDB once loaded
local recording = false
local seq = 0
local lastEventSample = 0
local spellIDs = {} -- key -> spellID (or the name if it couldn't be resolved)

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- Converts any value to something safe to store and compare. Secret is checked first, so nothing
-- below it ever touches a secret.
local function Enc(value)
    if IsSecret(value) then
        return "S"
    end
    if value == nil then
        return "nil"
    end
    local kind = type(value)
    if kind == "number" or kind == "boolean" or kind == "string" then
        return value
    end
    return kind
end

local function ErrText(err)
    if IsSecret(err) then
        return "E:<secret>"
    end
    return "E:" .. string.sub(tostring(err), 1, 120)
end

-- Calls fn(...) under pcall and stores up to two encoded results in sample[k1], sample[k2].
local function Probe(sample, k1, k2, fn, ...)
    if type(fn) ~= "function" then
        sample[k1] = "-"
        return
    end
    local ok, r1, r2 = pcall(fn, ...)
    if not ok then
        sample[k1] = ErrText(r1)
        return
    end
    sample[k1] = Enc(r1)
    if k2 then
        sample[k2] = Enc(r2)
    end
end

-- Reads info[field] only when info is a plain table.
local function Field(info, field)
    if IsSecret(info) then
        return "S"
    end
    if type(info) ~= "table" then
        return Enc(info)
    end
    return Enc(info[field])
end

local function ResolveSpells()
    for _, spell in ipairs(SPELLS) do
        local id = spell.name
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spell.name)
            if ok and not IsSecret(info) and type(info) == "table" then
                local sid = info.spellID
                if not IsSecret(sid) and type(sid) == "number" then
                    id = sid
                end
            end
        end
        spellIDs[spell.key] = id
    end
end

local function Cooldown(sample, kActive, kGCD, spell)
    if not (C_Spell and C_Spell.GetSpellCooldown) then
        sample[kActive] = "-"
        return
    end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
    if not ok then
        sample[kActive] = ErrText(info)
        return
    end
    sample[kActive] = Field(info, "isActive")
    if kGCD then
        sample[kGCD] = Field(info, "isOnGCD")
    end
end

local function ShredCost(sample)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then
        sample.shc = "-"
        return
    end
    local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellIDs.sh or "Shred")
    if not ok then
        sample.shc = ErrText(costs)
        return
    end
    if IsSecret(costs) then
        sample.shc = "S"
        return
    end
    if type(costs) ~= "table" then
        sample.shc = Enc(costs)
        return
    end
    local first = costs[1]
    sample.shc = Field(first, "cost")
end

local function Nameplates(sample)
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        sample.np = "-"
        return
    end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok then
        sample.np = ErrText(plates)
        return
    end
    if IsSecret(plates) or type(plates) ~= "table" then
        sample.np = Enc(plates)
        return
    end
    sample.np = #plates
    local hostile, secret = 0, 0
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken
        if not IsSecret(unit) and type(unit) == "string" then
            local okA, canAttack = pcall(UnitCanAttack, "player", unit)
            if okA then
                if IsSecret(canAttack) then
                    secret = secret + 1
                elseif canAttack == true then
                    hostile = hostile + 1
                end
            end
        end
    end
    sample.nph = hostile
    sample.npE = secret
end

local function Store(sample)
    seq = seq + 1
    sample.seq = seq
    db.seq = seq
    db.samples[(seq - 1) % MAX_SAMPLES + 1] = sample
end

local function TakeSample(trigger, a1, a3, auraInfo)
    if not recording or not db then
        return
    end
    local now = GetTime()
    local s = { ev = trigger, t = math.floor(now * 100 + 0.5) / 100 }
    s.c = Enc(InCombat())
    Probe(s, "ac", nil, UnitAffectingCombat, "player")

    local usable = C_Spell and C_Spell.IsSpellUsable
    for _, spell in ipairs(SPELLS) do
        Probe(s, "u_" .. spell.key, "p_" .. spell.key, usable, spellIDs[spell.key])
    end
    ShredCost(s)
    Cooldown(s, "tfA", "tfG", spellIDs.tf)
    Cooldown(s, "gcd", nil, GCD_SPELL)

    local assisted = C_AssistedCombat
    if assisted then
        Probe(s, "acN", nil, assisted.GetNextCastSpell, false)
        Probe(s, "acA", "acR", assisted.IsAvailable)
        Probe(s, "acS", nil, assisted.GetActionSpell)
    else
        s.acN = "-"
    end

    Probe(s, "te", nil, UnitExists, "target")
    Probe(s, "tca", nil, UnitCanAttack, "player", "target")
    Probe(s, "th", nil, UnitHealth, "target")
    Probe(s, "thm", nil, UnitHealthMax, "target")
    Probe(s, "en", nil, UnitPower, "player", ENERGY)
    Probe(s, "enm", nil, UnitPowerMax, "player", ENERGY)
    Probe(s, "upc", nil, UnitPower, "player", COMBO)
    Probe(s, "cp", nil, GetComboPoints, "player", "target")
    Probe(s, "pt", nil, UnitPowerType, "player")
    Probe(s, "ff", nil, GetShapeshiftFormID)
    Nameplates(s)

    local secrets = C_Secrets
    if secrets then
        Probe(s, "sA", nil, secrets.ShouldAurasBeSecret)
        Probe(s, "sC", nil, secrets.ShouldCooldownsBeSecret)
        Probe(s, "sP", nil, secrets.ShouldUnitPowerBeSecret, "player", ENERGY)
        Probe(s, "sCP", nil, secrets.ShouldUnitPowerBeSecret, "player", COMBO)
        Probe(s, "sH", nil, secrets.ShouldUnitHealthMaxBeSecret, "target")
    else
        s.sA = "-"
    end

    if IsSecret(a1) or a1 ~= nil then
        s.a1 = Enc(a1)
    end
    if IsSecret(a3) or a3 ~= nil then
        s.a3 = Enc(a3)
    end
    if IsSecret(auraInfo) or auraInfo ~= nil then
        s.ui = Enc(auraInfo)
    end
    Store(s)
end

-- Per-event counters: fired at all, fired in combat, and whether payload args were secret.
local function Count(event, a1, a3)
    local e = db.events[event]
    if not e then
        e = { n = 0, nc = 0, a1S = 0, a3S = 0 }
        db.events[event] = e
    end
    e.n = e.n + 1
    if InCombat() then
        e.nc = e.nc + 1
    end
    if IsSecret(a1) then
        e.a1S = e.a1S + 1
    end
    if IsSecret(a3) then
        e.a3S = e.a3S + 1
    end
end

-- One-off facts captured when recording starts.
local function Meta()
    local m = { started = date("%Y-%m-%d %H:%M:%S") }
    local okB, version, build, _, iface = pcall(GetBuildInfo)
    if okB then
        m.build = tostring(version) .. " " .. tostring(build) .. " " .. tostring(iface)
    end
    m.spellIDs = {}
    for key, id in pairs(spellIDs) do
        m.spellIDs[key] = id
    end
    m.has = {
        issecretvalue = issecretvalue ~= nil,
        C_AssistedCombat = C_AssistedCombat ~= nil,
        C_Secrets = C_Secrets ~= nil,
        C_CurveUtil = C_CurveUtil ~= nil,
        CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo ~= nil,
        GetShapeshiftFormID = GetShapeshiftFormID ~= nil,
        GetShapeshiftForm = GetShapeshiftForm ~= nil,
        UnitPowerPercent = UnitPowerPercent ~= nil,
        UnitHealthPercent = UnitHealthPercent ~= nil,
    }
    local secrets = C_Secrets
    if secrets then
        local s = {}
        Probe(s, "hasRestrictions", nil, secrets.HasSecretRestrictions)
        Probe(s, "powerEnergy", nil, secrets.GetPowerTypeSecrecy, ENERGY)
        Probe(s, "powerCombo", nil, secrets.GetPowerTypeSecrecy, COMBO)
        for _, spell in ipairs(SPELLS) do
            local id = spellIDs[spell.key]
            Probe(s, "aura_" .. spell.key, nil, secrets.GetSpellAuraSecrecy, id)
            Probe(s, "cd_" .. spell.key, nil, secrets.GetSpellCooldownSecrecy, id)
            Probe(s, "cast_" .. spell.key, nil, secrets.GetSpellCastSecrecy, id)
        end
        m.secrecy = s -- SecrecyLevel: 0 NeverSecret, 1 AlwaysSecret, 2 ContextuallySecret
    end
    if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
        local ok, list = pcall(C_AssistedCombat.GetRotationSpells)
        if ok and not IsSecret(list) and type(list) == "table" then
            m.rotationSpells = {}
            for i, id in ipairs(list) do
                m.rotationSpells[i] = Enc(id)
            end
        else
            if ok then
                m.rotationSpells = Enc(list)
            else
                m.rotationSpells = ErrText(list)
            end
        end
    end
    m.registration = db.registration
    table.insert(db.runs, m)
    while #db.runs > 20 do
        table.remove(db.runs, 1)
    end
end

-- Frames ---------------------------------------------------------------------------------------

local ticker = CreateFrame("Frame")
local elapsedSince = 0
ticker:Hide()
ticker:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince >= INTERVAL then
        elapsedSince = 0
        TakeSample("tick")
    end
end)

-- Events that always sample (casts are what the rotation reacts to).
local ALWAYS = {
    UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_SENT = true,
    PLAYER_REGEN_DISABLED = true,
    PLAYER_REGEN_ENABLED = true,
    PLAYER_TARGET_CHANGED = true,
    ASSISTED_COMBAT_ACTION_SPELL_CAST = true,
    UPDATE_SHAPESHIFT_FORM = true,
}

local watcher = CreateFrame("Frame")

local function OnWatchedEvent(_, event, ...)
    if not recording or not db then
        return
    end
    local a1, _, a3, a4 = ...
    if event == "UNIT_SPELLCAST_SENT" then
        a3 = a4 -- SENT is (unit, target, castGUID, spellID); SUCCEEDED is (unit, castGUID, spellID)
    end
    -- Payloads are only inspected for secrecy; nothing below compares them.
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        Count(event, nil, nil)
        if CombatLogGetCurrentEventInfo and db.events[event].n <= 50 then
            local ok, _, subevent = pcall(CombatLogGetCurrentEventInfo)
            db.cleu = db.cleu or {}
            if ok then
                table.insert(db.cleu, Enc(subevent))
            else
                table.insert(db.cleu, ErrText(subevent))
            end
        end
        return
    end
    Count(event, a1, a3)
    local now = GetTime()
    if event == "UNIT_AURA" then
        local _, info = ...
        if now - lastEventSample >= EVENT_GAP then
            lastEventSample = now
            TakeSample(event, a1, nil, info)
        end
        return
    end
    if ALWAYS[event] or now - lastEventSample >= EVENT_GAP then
        lastEventSample = now
        TakeSample(event, a1, a3)
    end
end
watcher:SetScript("OnEvent", OnWatchedEvent)

-- Registers each event under pcall and records success or the error text.
local function Register(event, unit1, unit2)
    local ok, err
    if unit1 then
        ok, err = pcall(watcher.RegisterUnitEvent, watcher, event, unit1, unit2)
    else
        ok, err = pcall(watcher.RegisterEvent, watcher, event)
    end
    if ok then
        db.registration[event] = true
    else
        db.registration[event] = ErrText(err)
    end
end

local function RegisterAll()
    db.registration = {}
    -- Confirmed 2026-10-11: registering the combat log triggers Blizzard's "blocked from an action only
    -- available to the Blizzard UI" popup on Forever. Skipped unless `/fprobe cleu` re-enables the test.
    if db.testCombatLog then
        Register("COMBAT_LOG_EVENT_UNFILTERED")
    else
        db.registration.COMBAT_LOG_EVENT_UNFILTERED = "skipped: forbidden for addons (popup confirmed)"
    end
    Register("UNIT_COMBO_POINTS")
    Register("UNIT_AURA", "player", "target")
    Register("UNIT_SPELLCAST_SUCCEEDED", "player")
    Register("UNIT_SPELLCAST_SENT", "player")
    Register("UNIT_POWER_FREQUENT", "player")
    Register("SPELL_UPDATE_USABLE")
    Register("SPELL_UPDATE_COOLDOWN")
    Register("ACTIONBAR_UPDATE_USABLE")
    Register("PLAYER_SWING")
    Register("PLAYER_REGEN_DISABLED")
    Register("PLAYER_REGEN_ENABLED")
    Register("PLAYER_TARGET_CHANGED")
    Register("UPDATE_SHAPESHIFT_FORM")
    Register("NAME_PLATE_UNIT_ADDED")
    Register("NAME_PLATE_UNIT_REMOVED")
    Register("ASSISTED_COMBAT_ACTION_SPELL_CAST")
end

-- Slash command and status ---------------------------------------------------------------------

local function Print(msg)
    print("|cff33ff99ForeverProbe|r: " .. msg)
end

local function Status()
    local stored = math.min(db.seq or 0, MAX_SAMPLES)
    local combat, secretEnergy, usableReadable = 0, 0, 0
    for _, s in pairs(db.samples) do
        if s.c == true then
            combat = combat + 1
            if s.en == "S" then
                secretEnergy = secretEnergy + 1
            end
            if type(s.u_sh) == "boolean" then
                usableReadable = usableReadable + 1
            end
        end
    end
    Print(string.format("%s | %d samples (%d in combat; energy secret %d, Shred usable readable %d)",
        recording and "RECORDING" or "stopped", stored, combat, secretEnergy, usableReadable))
    local regs = {}
    for _, event in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_COMBO_POINTS" }) do
        local r = db.registration and db.registration[event]
        local fired = db.events[event] and db.events[event].n or 0
        table.insert(regs, string.format("%s reg=%s fired=%d", event, tostring(r), fired))
    end
    Print(table.concat(regs, "; "))
end

local function Start()
    ResolveSpells()
    RegisterAll()
    Meta()
    recording = true
    elapsedSince = 0
    ticker:Show()
    TakeSample("start")
    Print("recording ON (every " .. INTERVAL .. "s + events). /fprobe again to stop.")
end

local function Stop()
    recording = false
    ticker:Hide()
    watcher:UnregisterAllEvents()
    Print("recording OFF. /reload to write ForeverProbeDB to disk.")
    Status()
end


ns.Legacy = {
    Init = function(database)
        db = database
        db.samples = db.samples or {}
        db.events = db.events or {}
        db.runs = db.runs or {}
        db.registration = db.registration or {}
        db.legend = LEGEND
        db.maxSamples = MAX_SAMPLES
        seq = db.seq or 0
    end,
    Start = function()
        if db and not recording then
            Start()
        end
    end,
    Stop = function()
        if recording then
            Stop()
        end
    end,
    Status = function()
        if db then
            Status()
        end
    end,
    Clear = function()
        db.samples, db.events, db.cleu, db.seq, seq = {}, {}, nil, 0, 0
    end,
    ToggleCleu = function()
        db.testCombatLog = not db.testCombatLog
        return db.testCombatLog
    end,
    IsRecording = function()
        return recording
    end,
}
