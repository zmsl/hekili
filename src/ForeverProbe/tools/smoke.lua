-- Headless smoke test for ForeverProbe under stock Lua 5.1 with a permissive fake client:
--     cd ~/src/ForeverProbe && lua5.1 tools/smoke.lua
-- It cannot emulate rendering or the client's secret semantics (comparisons on secrets don't raise here), but it
-- runs a whole session: load, start W and D, ticks in and out of combat, events, the panel, the spike, every
-- slash command, stop; then checks that no probe recorded a Lua error and that nothing in ForeverProbeDB is the
-- SECRET sentinel or a function (either would break SavedVariables). Then a session O run: every registered event
-- fired with plain, secret and nil args, the correlators, the FCT phase switch and the CVar restore.
local SECRET = setmetatable({}, { __tostring = function() return "<SECRET>" end })
local combat = false
local now = 1000
local opUsable = true -- what C_Spell.IsSpellUsable("Overpower") returns
local frames = {}
local failures = 0
local function Fail(msg)
    failures = failures + 1
    print("FAIL: " .. msg)
end

-- Globals the addon reads -------------------------------------------------------------------------
function issecretvalue(v) return v == SECRET end
function issecrettable(t) return rawget(t, "isFullUpdate") == true end -- flags the nameplate UNIT_AURA table below
function InCombatLockdown() return combat end
function GetTime() return now end
function date(fmt) return os.date(fmt) end
function debugprofilestop() return os.clock() * 1000 end
function GetFramerate() return 60 end
unpack = unpack or table.unpack
STANDARD_TEXT_FONT = "font"
Enum = { PowerType = { Mana = 0, Rage = 1, Energy = 3, ComboPoints = 4 }, LuaCurveType = { Step = 1 } }
SlashCmdList = {}
LibStub = { GetLibrary = function(_, name) if name == "LibDataBroker-1.1" then return {} end return nil end }

local Widget = {}
Widget.__index = function(_, k)
    local v = rawget(Widget, k)
    if v ~= nil then return v end
    return function() end
end
local function NewWidget()
    return setmetatable({ scripts = {}, events = {}, shown = true }, Widget)
end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:IsShown() return self.shown end
function Widget:GetScale() return 1 end
function Widget:GetLeft() return 10 end
function Widget:GetRight() return 9 end
local UNKNOWN_EVENTS = { UNIT_COMBO_POINTS = true, UNIT_HEALTH_FREQUENT = true }
function Widget:RegisterEvent(e)
    if UNKNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
    self.events[e] = true
end
function Widget:RegisterUnitEvent(e) self.events[e] = true end
function Widget:UnregisterEvent(e) self.events[e] = nil end
function Widget:UnregisterAllEvents() self.events = {} end
function Widget:CreateTexture() return NewWidget() end
function Widget:CreateFontString() return NewWidget() end
function Widget:GetCooldownTimes() return 1, 2 end
function CreateFrame(_, name, _, template)
    if template == "UIDropDownMenuTemplate" then error("unknown template " .. template) end
    local f = NewWidget()
    table.insert(frames, f)
    if name then _G[name] = f end
    return f
end
UIParent = NewWidget()

local function maybeSecret(v) if combat then return SECRET end return v end
C_Spell = {
    GetSpellInfo = function(name) if name == "Shifting Power" then return nil end return { spellID = 1000 + #name, name = name } end,
    IsCurrentSpell = function() return maybeSecret(false) end,
    IsSpellUsable = function(s) if s == "Overpower" then return opUsable, false end return true, false end,
    GetSpellCooldown = function() return { startTime = maybeSecret(0), duration = maybeSecret(0), isActive = false, isOnGCD = false, isEnabled = true, modRate = 1 } end,
    GetSpellCooldownDuration = function() return { GetRemainingDuration = function() return maybeSecret(0) end, HasStarted = function() return true end } end,
    IsSpellInRange = function() return maybeSecret(true) end,
    GetSpellPowerCost = function() return { { cost = maybeSecret(40) } } end,
    GetSpellTexture = function() return 12345 end,
    GetSpellLossOfControlCooldownInfo = function() return { startTime = 0, duration = 0, isEnabled = true } end,
}
C_CurveUtil = { CreateCurve = function() return { SetType = function() end, AddPoint = function() end, ClearPoints = function() end } end }
function UnitPowerPercent() return SECRET end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitLevel() return 60 end
function UnitPowerType() return 1, "RAGE" end
function UnitPower() return SECRET end
function UnitPowerMax() return maybeSecret(100) end
function UnitHealth() return SECRET end
function UnitHealthMax() return SECRET end
function UnitHealthPercent() return SECRET end
function UnitExists() return true end
function UnitCanAttack() return maybeSecret(true) end
function UnitAffectingCombat() return combat end
function UnitGUID() return "Creature-0-1" end
function UnitIsDead() return false end
function UnitIsUnit() return true end
function UnitName() return "Dummy" end
function UnitThreatSituation() return maybeSecret(3) end
function UnitAttackSpeed() return maybeSecret(2.4), nil, nil end
function UnitDamage() return maybeSecret(80), maybeSecret(120), 0, 0, 0, 0, 0 end
function GetBuildInfo() return "1.60.1", "70338", "2026", 16001 end
function GetComboPoints() return 0 end
function GetGameMessageInfo(i) return "ERR_" .. i end
function GetInventoryItemID(_, slot) return 100 + slot end
function GetBindingKey() return "S" end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function UIFrameFadeOut() end
C_NamePlate = { GetNamePlates = function() return { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = SECRET } } end }
C_Secrets = setmetatable({ HasSecretRestrictions = function() return false end }, { __index = function() return function() return true end end })
C_Texture = { GetAtlasInfo = function() return { file = 1, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end }
C_ActionBar = { FindSpellActionButtons = function() return { 3 } end, IsCurrentAction = function() return maybeSecret(false) end, EnableActionRangeCheck = function() end,
    IsActionInRange = function() return maybeSecret(true) end, HasRangeRequirements = function() return true end, GetSpell = function(i) return i end,
    GetActionText = function() return "" end, GetActionBarPage = function() return 1 end, GetBonusBarOffset = function() return 0 end }
C_SwingTimer = { EnableRangeCheck = function() end, IsTargetWithinSwingRange = function() return maybeSecret(true) end }
C_TooltipInfo = { GetSpellByID = function() return { lines = { { leftText = "Heroic Strike", rightText = "15 Rage", type = 0 }, SECRET } } end }
C_SpellBook = { IsSpellKnown = function(id) return id % 2 == 0 end }
C_LossOfControl = { GetActiveLossOfControlDataCount = function() return 0 end, GetActiveLossOfControlData = function() return nil end }
C_SpecializationInfo = { GetSpecialization = function() return 1 end, GetSpecializationInfo = function() return 1, "Arms", nil, nil, nil, nil, 31 end,
    GetActiveSpecGroup = function() return 1 end, GetTalentInfo = function() return { talentID = 1, name = "x", rank = 2, maxRank = 3, known = true } end,
    CanPlayerUseTalentSpecUI = function() return true, "" end, GetNumSpecializationsForClassID = function() return 3 end }
-- Talent tree stubs: node 101 bought (active entry), 102 unbought (first-entry fallback), 103 has a secret activeRank in
-- combat, 104 has a GetEntryInfo that errors. walkCalls counts GetActiveConfigID calls (one walk per combat state).
local walkCalls = 0
C_ClassTalents = { GetActiveConfigID = function() walkCalls = walkCalls + 1 return 9001 end }
local NODES = {
    [101] = { ranksPurchased = 2, activeRank = 2, maxRanks = 3, activeEntry = { entryID = 1101, rank = 2 }, entryIDs = { 1101 } },
    [102] = { ranksPurchased = 0, activeRank = 0, maxRanks = 1, entryIDs = { 1102 } },
    [103] = { ranksPurchased = 1, activeRank = "secret-in-combat", maxRanks = 1, activeEntry = { entryID = 1103 }, entryIDs = { 1103 } },
    [104] = { ranksPurchased = 1, activeRank = 1, maxRanks = 1, activeEntry = { entryID = 1104 }, entryIDs = { 1104 } },
}
C_Traits = {
    GetConfigInfo = function(cfg) return { ID = cfg, treeIDs = { 55 } } end,
    GetTreeNodes = function() return { 101, 102, 103, 104 } end,
    GetNodeInfo = function(_, id)
        local n = NODES[id]
        local out = {}
        for k, v in pairs(n) do out[k] = v end
        if out.activeRank == "secret-in-combat" then out.activeRank = maybeSecret(1) end
        return out
    end,
    GetEntryInfo = function(_, entryID)
        if entryID == 1104 then error("entry boom") end
        return { definitionID = entryID + 10000 }
    end,
    GetDefinitionInfo = function(defID) return { spellID = defID - 9000 } end,
}
C_Spell.GetSpellName = function(id) return "Talent" .. id end
function IsPlayerSpell(id) return maybeSecret(id % 2 == 1) end
C_Item = { IsEquippedItem = function() return true end, GetItemCooldown = function() return 0, 0, true end, GetItemCount = function() return 2 end,
    IsUsableItem = function() return true, false end, GetWeaponEnchantInfo = function() return { { hasEnchant = true, timeLeft = 1000, charges = 0, enchantID = 5 } } end }
C_Container = { GetItemCooldown = function() return 0, 0, 1 end }
C_SpellActivationOverlay = { IsSpellOverlayed = function() return maybeSecret(false) end }
C_PetInfo = { GetPetHappiness = function() return nil end }
-- C_Timer fake: callbacks queue and run when Tick (or FlushTimers) reaches their time.
local timers = {}
C_Timer = { After = function(sec, fn) table.insert(timers, { at = now + sec, fn = fn }) end }
local function FlushTimers()
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= now + 1e-9 then
            table.insert(due, 1, table.remove(timers, i))
        end
    end
    for _, t in ipairs(due) do t.fn() end
end
local cvars = { enableFloatingCombatText = "0" }
local setCalls = {}
C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, v)
        assert(not combat, "SetCVar called in combat")
        cvars[name] = v
        table.insert(setCalls, name .. "=" .. tostring(v))
        return true
    end,
}
C_CombatLog = { IsCombatLogRestricted = function() return maybeSecret(true) end }
C_DamageMeter = { IsDamageMeterAvailable = function() return true, "" end }
C_CombatText = { GetCurrentEventInfo = function() return SECRET, SECRET end }
function GetTotemInfo() return maybeSecret(false), "" end
UIErrorsFrame = NewWidget()
MenuUtil = { CreateContextMenu = function(_, fn) fn(nil, { CreateTitle = function() end, CreateButton = function() end }) end }

-- Load the addon in TOC order -------------------------------------------------------------------
local ns = {}
for _, file in ipairs({ "Core.lua", "Legacy.lua", "Probes.lua", "Display.lua", "Spike.lua", "SessionO.lua", "Export.lua" }) do
    local chunk, err = loadfile(file)
    if not chunk then
        Fail("load " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk("ForeverProbe", ns)
end

local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then
            f.scripts.OnEvent(f, event, ...)
        end
    end
end
local function Tick(dt, n)
    for _ = 1, n or 1 do
        now = now + dt
        for _, f in ipairs(frames) do
            if f.shown and f.scripts.OnUpdate then
                f.scripts.OnUpdate(f, dt)
            end
        end
        FlushTimers()
    end
end
local function Cmd(s)
    local ok, err = pcall(SlashCmdList.FOREVERPROBE, s)
    if not ok then
        Fail("/fprobe " .. s .. ": " .. tostring(err))
    end
end
local function Events()
    Fire("UNIT_SPELLCAST_SENT", "player", "Dummy", "guid", 78)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 78)
    Fire("PLAYER_SWING", maybeSecret(2.4), 0)
    Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
    Fire("UNIT_POWER_FREQUENT", SECRET, "RAGE")
    Fire("CURRENT_SPELL_CAST_CHANGED", false)
    Fire("UI_ERROR_MESSAGE", 402, "Out of range")
    Fire("UI_ERROR_MESSAGE", SECRET, SECRET)
    Fire("UNIT_SPELLCAST_START", "target", "g", 123)
    Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "g", 456)
    Fire("ACTION_RANGE_CHECK_UPDATE", 3, maybeSecret(true), true)
    Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 7384)
    Fire("SPELL_UPDATE_COOLDOWN")
    Fire("PLAYER_TALENT_UPDATE")
    Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    Fire("UNIT_MAXPOWER", "player", "RAGE")
    Fire("PLAYER_TARGET_CHANGED")
    Fire("UNIT_AURA", "player", SECRET)
end

local function Session(kind)
    combat = false
    Fire("ADDON_LOADED", "ForeverProbe")
    Fire("PLAYER_ENTERING_WORLD")
    Cmd("start " .. kind)
    assert(ns.session, "session did not start")
    Tick(0.25, 20)
    Events()
    combat = true
    Fire("PLAYER_REGEN_DISABLED")
    Tick(0.25, 20)
    Events()
    Cmd("spike show")
    Tick(0.016, 30)
    Cmd("spike stats")
    Cmd("spike glide")
    Tick(0.016, 5)
    Cmd("spike glide")
    Cmd("note PR20 ok: left square lit below 35")
    Cmd("alloc")
    Cmd("menu")
    Cmd("scale 0.8")
    Cmd("panel hide")
    Cmd("panel show")
    Cmd("status")
    combat = false
    Fire("PLAYER_REGEN_ENABLED")
    Tick(0.25, 4)
    local id = ns.sessionId
    Cmd("stop")
    assert(not ns.session, "session did not stop")
    local sess = ForeverProbeDB.sessions[id]
    assert(sess and sess.stopped, "session not stored")
    for key, data in pairs(sess) do
        if type(data) == "table" and data.tally then
            if data.errors then
                Fail(kind .. " " .. key .. " recorded " .. data.errors .. " errors; last: " .. tostring(data.lastErr))
            end
            if data.setupErr then
                Fail(kind .. " " .. key .. " setup error: " .. tostring(data.setupErr))
            end
            if data.n == 0 and data.title and key ~= "PR17" and key ~= "PR19" then
                Fail(kind .. " " .. key .. " took no samples")
            end
        end
    end
    return sess
end

local function Walk(t, path, seen)
    if seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
        local p = path .. "." .. tostring(k)
        if v == SECRET or k == SECRET then
            Fail("SECRET stored at " .. p)
        elseif type(v) == "function" or type(v) == "userdata" then
            Fail("unsaveable " .. type(v) .. " at " .. p)
        elseif type(v) == "table" then
            Walk(v, p, seen)
        end
    end
end

local w = Session("W")
local d = Session("D")

-- Session O ------------------------------------------------------------------------------------------------
local function SessionO()
    combat = false
    opUsable = false
    Fire("ADDON_LOADED", "ForeverProbe")
    Cmd("o")
    local o = ns.SessionO.Current()
    assert(o and o.kind == "O", "session O did not start")
    assert(cvars.enableFloatingCombatText == "1", "phase A should turn FCT on")
    Cmd("o") -- running: shows the panel and a status line
    Cmd("note O: a note with no W/D session")
    -- Out of combat: a few plain firings.
    Fire("UNIT_COMBAT", "target", "WOUND", "", 50, 1)
    Fire("COMBAT_TEXT_UPDATE", "SPELL_AURA_START")
    Fire("PLAYER_TARGET_CHANGED")
    -- Combat.
    combat = true
    Fire("PLAYER_REGEN_DISABLED")
    Tick(0.016, 1)
    Fire("PLAYER_ENTER_COMBAT")
    -- O1: target plain, player secret.
    Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 120, 1)
    Fire("UNIT_COMBAT", "player", SECRET, SECRET, SECRET, SECRET)
    Fire("UNIT_COMBAT", SECRET, SECRET, SECRET, SECRET, SECRET)
    -- O3: a landed swing (power in the same frame, after the swing), a no-power swing, a secret swing, a ranged swing.
    Fire("PLAYER_SWING", 2.4, 0)
    Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
    Tick(0.016, 1)
    Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
    Tick(0.016, 1)
    opUsable = true -- the dodge lights Overpower one frame later
    Fire("PLAYER_SWING", 2.4, 1)
    Fire("UNIT_POWER_FREQUENT", "player", "ENERGY") -- same frame, but not rage: still a no-power swing
    Tick(0.016, 7)
    Fire("UNIT_POWER_FREQUENT", "player", "RAGE") -- 0.112 s late: the swing's dtPow
    Tick(0.016, 1)
    Fire("PLAYER_SWING", SECRET, SECRET)
    Tick(0.016, 1)
    Fire("PLAYER_SWING", 3.0, 2)
    Tick(0.016, 1)
    -- O16 + O11: a player success with Overpower false before and true 0.1 s later; an Auto Shot.
    opUsable = false
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 78)
    opUsable = true
    Tick(0.05, 3)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 75)
    Tick(0.05, 3)
    -- O4 / O5: other units' casts (secret payload), our own interrupt.
    Fire("UNIT_SPELLCAST_START", "target", SECRET, SECRET, nil)
    Fire("UNIT_SPELLCAST_INTERRUPTED", "target", SECRET, SECRET, SECRET, nil)
    Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate3", SECRET, SECRET, SECRET, nil)
    Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-3", 5176, "Creature-0-2", nil)
    C_LossOfControl.GetActiveLossOfControlData = function() return { locType = "SCHOOL_INTERRUPT", lockoutSchool = 8, duration = SECRET, spellID = 1766 } end
    Fire("LOSS_OF_CONTROL_ADDED", "player", 1)
    Fire("LOSS_OF_CONTROL_ADDED", "player", SECRET)
    -- O12: a plain update table with nested arrays (a secret first element), and a secret one.
    Fire("UNIT_AURA", "player", { isFullUpdate = false, addedAuras = { SECRET }, removedAuraInstanceIDs = { 11, 12 } })
    Fire("UNIT_AURA", "target", SECRET)
    Fire("UNIT_AURA", "nameplate2", { isFullUpdate = true })
    -- O9: target health ticks every 3 s with auto-attack off (the Rend test).
    Fire("PLAYER_LEAVE_COMBAT")
    for _ = 1, 4 do
        Fire("UNIT_HEALTH", "target")
        Tick(0.5, 6)
    end
    Fire("PLAYER_ENTER_COMBAT")
    -- O6 / O7 / O8 / O10 / O13 / O15 and the unmeasured extras.
    Fire("UNIT_DIED", "Creature-0-3")
    Fire("PARTY_KILL", SECRET, SECRET)
    Fire("PLAYER_TARGET_DIED")
    Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 1)
    Fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")
    Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    Fire("NAME_PLATE_UNIT_REMOVED", SECRET)
    Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 7384)
    Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", SECRET)
    Fire("UNIT_PET", "player")
    Fire("PLAYER_TOTEM_UPDATE", 1)
    Fire("COMBO_TARGET_CHANGED")
    Fire("UNIT_THREAT_SITUATION_UPDATE", "player")
    Fire("UNIT_TARGET", "target")
    Fire("PLAYER_IN_COMBAT_CHANGED", true)
    Fire("ENCOUNTER_START", 1, "Boss", 1, 5)
    Fire("COMBAT_TEXT_UPDATE", "DODGE")
    Fire("UNIT_HEALTH", "nameplate1", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12) -- more than MAX_ARGS
    Fire("UNIT_HEALTH", "target", "a very long string ...........................................................................")
    -- 120 s of combat in phase A, then out of combat: the switch to phase B.
    Tick(0.5, 242)
    assert(o.O2.phase == "A" and cvars.enableFloatingCombatText == "1", "no switch in combat")
    combat = false
    Fire("PLAYER_REGEN_ENABLED")
    Tick(0.5, 2)
    assert(o.O2.phase == "B" and cvars.enableFloatingCombatText == "0", "phase B should turn FCT off")
    Cmd("o fct") -- already B
    combat = true
    Fire("PLAYER_REGEN_DISABLED")
    Fire("COMBAT_TEXT_UPDATE", SECRET)
    Cmd("o panel")
    Cmd("o panel")
    Cmd("o status")
    Cmd("status")
    Tick(0.5, 2)
    combat = false
    Fire("PLAYER_REGEN_ENABLED")
    Cmd("o stop")
    assert(not ns.SessionO.Current(), "session O did not stop")
    assert(o.stopped and o.summary and #o.summary == 17, "summary lines: " .. tostring(o.summary and #o.summary))
    assert(cvars.enableFloatingCombatText == "0" and setCalls[#setCalls] == "enableFloatingCombatText=0" and ForeverProbeDB.fctRestore == nil,
        "FCT restored to the original value")
    return o
end

local o = SessionO()
-- Restore safety net: a session left running across a reload.
cvars.enableFloatingCombatText = "1"
ForeverProbeDB.fctRestore = "0"
ns.SessionO.Init(ForeverProbeDB)
assert(cvars.enableFloatingCombatText == "0" and ForeverProbeDB.fctRestore == nil, "Init restores the CVar")
-- A restore pending from a stop in combat is inherited by a new session: the user's original survives.
do
    cvars.enableFloatingCombatText = "0"
    Cmd("o")
    local first = ns.SessionO.Current()
    combat = true
    Cmd("o stop")
    assert(ForeverProbeDB.fctRestore == "0" and cvars.enableFloatingCombatText == "1", "restore pending")
    Cmd("o") -- started in combat while the restore is pending
    local second = ns.SessionO.Current()
    assert(second.O2.orig == "0" and second.O2.inherited == true and second.O2.cur == "1", "pending original inherited")
    assert(first.O2.restored == "handed to the next session", "first session handed the restore over")
    combat = false
    Fire("PLAYER_REGEN_ENABLED") -- the guard no longer owns the restore
    assert(ForeverProbeDB.fctRestore == "0" and cvars.enableFloatingCombatText == "1", "guard did not restore under a running session")
    Cmd("o stop")
    assert(cvars.enableFloatingCombatText == "0" and ForeverProbeDB.fctRestore == nil and second.O2.restored == true, "second session restored the original")
end
-- A stop in combat defers the restore to PLAYER_REGEN_ENABLED.
do
    Cmd("o")
    combat = true
    Cmd("o stop")
    assert(ForeverProbeDB.fctRestore == "0", "restore deferred in combat")
    combat = false
    Fire("PLAYER_REGEN_ENABLED")
    assert(ForeverProbeDB.fctRestore == nil and cvars.enableFloatingCombatText == "0", "deferred restore ran")
end

Walk(ForeverProbeDB, "db", {})

-- Session O spot checks.
do
    local ev = o.events
    assert(o.errors == nil, "session O errors: " .. tostring(o.lastErr))
    assert(ev.UNIT_COMBO_POINTS.reg:sub(1, 2) == "E:" and ev.UNIT_COMBO_POINTS.documented == false, "unregisterable event recorded")
    assert(ev.UNIT_COMBAT.reg == "ok" and ev.UNIT_COMBAT.documented == true, "UNIT_COMBAT registered")
    for _, name in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "COMBAT_LOG_EVENT", "COMBAT_LOG_MESSAGE" }) do
        assert(ev[name] == nil, name .. " must never be registered")
    end
    local t = ev.UNIT_COMBAT.b.target
    assert(t.n == 2 and t.nC == 1 and t.args[4].P == 2 and t.args[3].samples[2] == "CRITICAL", "UNIT_COMBAT target classified")
    assert(ev.UNIT_COMBAT.b.player.args[2].S == 1 and ev.UNIT_COMBAT.b.S.n == 1, "UNIT_COMBAT player/secret buckets")
    local ua = ev.UNIT_AURA.b.player.fields[2]
    assert(ua.isFullUpdate.samples[1] == false and ua.addedAuras.samples[1] == 1 and ua.addedAuras.e1S == 1, "UNIT_AURA fields")
    assert(ua.removedAuraInstanceIDs.samples[1] == 2 and ua.removedAuraInstanceIDs.e1P == 1, "UNIT_AURA removed ids")
    assert(ev.UNIT_AURA.b.target.args[2].S == 1 and ev.UNIT_AURA.b.nameplate.n == 1, "UNIT_AURA target secret, nameplate bucket")
    assert(ev.UNIT_AURA.b.nameplate.args[2].ST == 1 and ev.UNIT_AURA.b.player.args[2].ST == nil, "issecrettable counted")
    assert(ev.UNIT_HEALTH.b.nameplate.cut == true and #ev.UNIT_HEALTH.b.nameplate.args == 10, "args capped at 10")
    assert(#ev.UNIT_HEALTH.b.target.args[2].samples[1] == 64, "strings truncated to 64")
    local loc = ev.LOSS_OF_CONTROL_ADDED.b.player
    assert(loc.readFields.loc.lockoutSchool.samples[1] == 8 and loc.readFields.loc.duration.S == 1 and loc.reads.indexSecret.S == 1, "LoC read walked")
    assert(ev.NAME_PLATE_UNIT_ADDED.b.nameplate.reads.guid.samples[1] == "Creature-0-1", "nameplate reads")
    assert(ev.COMBAT_TEXT_UPDATE.b.A.n == 2 and ev.COMBAT_TEXT_UPDATE.b.B.n == 1 and ev.COMBAT_TEXT_UPDATE.b.X == nil, "O2 phase buckets")
    assert(ev.COMBAT_TEXT_UPDATE.b.A.reads.info1.S == 2, "O2 detail read")
    local h0, h1 = o.O3.hands.h0, o.O3.hands.h1
    assert(h0.swings == 1 and h0.landed == 1 and h0.opAfterLanded.f == 1, "O3 landed swing")
    assert(h1.swings == 1 and h1.noPower == 1 and h1.opAfterNoPower.t == 1 and o.O3.opFlips == 1, "O3 no-power swing + OP flip")
    assert(o.O3.hands.hS.swings == 1 and o.O3.ringN == 4, "O3 secret hand + ring")
    local ring = o.O3.ring
    assert(ring[1].dtPow == 0 and ring[2].dtPow == 0.112 and ring[2].landed == false and ring[3].dtPow == nil, "O3 rage-only landed + dtPow: "
        .. tostring(ring[1].dtPow) .. " " .. tostring(ring[2].dtPow) .. " " .. tostring(ring[3].dtPow))
    assert(o.O9.leaveSeen == 1, "O9 leave seen after auto-attack on")
    assert(o.O11.rangedSwings == 1 and o.O11.rangedCasts == 1 and o.O11.casts[75] == 1, "O11")
    assert(o.O16.successes == 2 and o.O16.flips == 1 and o.O16.spells[78]["f>t"] == 1, "O16 flip")
    assert(o.O9.autoOff.n == 3 and o.O9.autoOff[13] == 3, "O9 3 s deltas with auto-attack off")
    assert(o.O6.n == 3 and o.O6.targetDied == 1 and o.O6.ring[2].a1 == "S", "O6 ring")
    assert(o.O14.at.start.samples[1] == true and o.O14["in"].S >= 1 and o.O14.out.P >= 1, "O14 in/out")
    local sq = o.squares
    assert(sq.O1 == "yellow" and sq.O4 == "red" and sq.O5 == "yellow" and sq.O9 == "green" and sq.O16 == "green", "squares 1")
    assert(sq.O3 == "yellow" and sq.O11 == "green" and sq.O12 == "yellow" and sq.O14 == "yellow" and sq.O15 == "green", "squares 2")
    local c = o.checklist
    assert(c.interrupt and c.dodge and c.rend and c.kill and c.combo and c.ranged, "checklist detected")
    assert(#o.notes == 1, "note reached session O")
    for _, l in ipairs(o.summary) do print("  " .. l) end
end

-- A few spot checks that the data is shaped as the runbook describes.
local function Tally(sess, pr, key)
    local t = sess[pr] and sess[pr].tally and sess[pr].tally[key]
    assert(t, pr .. "." .. key .. " missing")
    return t
end
assert(Tally(w, "PR1", "cur_hs").c.S > 0, "PR1 cur_hs should be secret in combat")
assert(Tally(w, "PR1", "cur_hs").o.P > 0, "PR1 cur_hs should be plain out of combat")
assert(Tally(w, "PR2", "as_mh").c.S > 0 and Tally(w, "PR2", "as_mh").o.P > 0, "PR2 as_mh tallies")
assert(w.PR3.anchors and w.PR3.anchorsN >= 6, "PR3 anchors ring")
assert(w.PR6.tally.unitSecret.o.P > 0, "PR6 unitSecret counted")
assert(w.PR17.msgs["402"] and w.PR17.msgs["402"].n == 2 and w.PR17.secretCount == 2, "PR17 messages")
assert(w.PR19.facts.LibStub and w.PR19.facts["lib_LibDataBroker-1.1"] == true, "PR19 facts")
assert(Tally(w, "PR10", "key_ab1").exO == "=S", "a plain string 'S' must be stored as '=S', got " .. tostring(Tally(w, "PR10", "key_ab1").exO))
assert(Tally(w, "PR10", "key_ab1").o.P > 0, "plain string tallied as P")
assert(w.DISPLAY and w.DISPLAY.pr20_secretC and w.DISPLAY.pr20_secretC > 0, "panel gate results")
assert(w.SPIKE and w.SPIKE.regions >= 90, "spike regions " .. tostring(w.SPIKE and w.SPIKE.regions))
assert(w.registration.PLAYER_SWING == "all" and w.registration.UNIT_POWER_FREQUENT == "player,target" and w.registration.UNIT_SPELLCAST_SUCCEEDED == "player,target", "event registration kinds")
assert(#w.notes == 2, "notes stored")
-- PR5 talent walk: one walk per combat state per session, secrets and errors flagged, bounded.
do
    local wo, wc = w.PR5.facts.walkO, w.PR5.facts.walkC
    assert(wo and wc, "PR5 walkO/walkC missing")
    assert(wo.combat == false and wc.combat == true, "PR5 walk combat flags")
    assert(wo.cfg == 9001 and wo.trees == 1 and wo.nodes == 4 and wc.nodes == 4, "PR5 walk counts")
    assert(wo.bought == 4 - 1 and wo.active == 3 and wc.active == 2, "PR5 walk active/bought: " .. tostring(wo.active) .. "/" .. tostring(wc.active))
    assert(wo.secret == 0 and wc.secret == 1, "PR5 walk secret nodes out/in combat")
    assert(wo.errors == 1 and wc.errors == 1, "PR5 walk errored nodes")
    assert(wo.list[1].spell == "=Talent2101" and wo.list[1].spellID == 2101 and wo.list[1].rp == 2 and wo.list[1].mr == 3, "PR5 walk node 101")
    assert(wo.list[2].fb == true and wo.list[2].spell == "=Talent2102", "PR5 walk first-entry fallback")
    assert(wc.list[3].f == "S" and wc.list[3].ar == "S", "PR5 walk secret flag")
    assert(wo.list[4].f == "E" and wo.list[4].entry:sub(1, 2) == "E:", "PR5 walk error flag")
    assert(#wo.ips == 3 and wo.ips[1].id == 2101 and wo.ips[1].isps == true and wc.ips[1].isps == "S", "PR5 IsPlayerSpell rows")
    assert(wo.gti.idx1.name == "=x" and wo.gti.g1t1c1.rank == 2, "PR5 GetTalentInfo snapshot")
    assert(wo.tries == 1 and wc.tries == 1, "PR5 walk should run once per state")
end
assert(walkCalls == 4, "two sessions x (out + in combat) walks, got " .. walkCalls)
assert(d.kind == "D" and d.spells.sh and d.spells.sp.id == false, "D session spells")
assert(ForeverProbeDB.samples and ForeverProbeDB.seq > 0, "legacy sampler ran")
print(string.format("spike: %d regions, body avg %.3f ms", w.SPIKE.regions, w.SPIKE.bodyAvgMs))
print(string.format("W probes: %d, D probes: %d", (function() local n = 0 for k, v in pairs(w) do if type(v) == "table" and v.tally then n = n + 1 end end return n end)(),
    (function() local n = 0 for k, v in pairs(d) do if type(v) == "table" and v.tally then n = n + 1 end end return n end)()))

-- Export: refused in combat; out of combat a spellbook (one plain, one secret-field item), the talent stubs above and
-- two stances, with no SECRET or function stored.
C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
C_SpellBook.GetSpellBookSkillLineInfo = function() return { name = "Arms", itemIndexOffset = 0, numSpellBookItems = 2 } end
C_SpellBook.GetSpellBookItemInfo = function(i) return { itemType = 1, name = "Spell" .. i, spellID = i == 1 and 78 or SECRET } end
C_SpellBook.GetSpellBookItemName = function(i) return "Spell" .. i, "Rank 1" end
C_Spell.GetSpellDescription = function() return string.rep("x", 200) end
function GetNumShapeshiftForms() return 2 end
function GetShapeshiftForm() return 1 end
function GetShapeshiftFormInfo(i) return 132349, i == 1, true, 2457 + i end
function UnitClassBase() return "WARRIOR", 1 end
ForeverProbeDB.export = nil
combat = true
Cmd("export")
if ForeverProbeDB.export then Fail("export ran in combat") end
combat = false
Cmd("export")
local ex = ForeverProbeDB.export
if not ex then
    Fail("export wrote nothing")
else
    Walk(ex, "export", {})
    local s1 = ex.spells[1]
    if #ex.spells ~= 2 or s1.item.spellID ~= 78 or s1.tip[1].r ~= "=15 Rage" or s1.tip[2] ~= "S" then Fail("export spells") end
    if #s1.desc ~= 201 or ex.spells[2].item.spellID ~= "S" or ex.spells[2].info ~= nil then Fail("export spell detail") end
    if s1.itemName.n ~= 2 or s1.itemName[2] ~= "=Rank 1" or s1.known ~= true then Fail("export item name / known") end
    local nodes = ex.talents.trees[1].nodes
    if #nodes ~= 4 or nodes[1].entries[1].def.spellID ~= 2101 or string.sub(nodes[4].entries[1].entry, 1, 2) ~= "E:" then Fail("export talents") end
    if ex.stances.num ~= 2 or ex.stances.forms[2][4] ~= 2459 or ex.meta.build[4] ~= 16001 then Fail("export stances / meta") end
end

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("smoke OK")
