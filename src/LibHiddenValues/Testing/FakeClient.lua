-- Testing/FakeClient.lua: the real LibHiddenValues running on a fake client, for the library's own suite and for any
-- consumer's tests. Not in the TOC: the game never loads it. Stock Lua 5.1, no dependency.
--
--   local Fake = dofile("libs/LibHiddenValues/Testing/FakeClient.lua")  -- fresh client, library loaded, not logged in
--   local W = Fake.world
--   W.unit.target = { health = 1.0 }        -- fractions 0-1, as the client has them
--   dofile("MyAddon.lua")                    -- calls LibStub("LibHiddenValues-1.0"):Watch(...) as in the game
--   Fake.login()                             -- PLAYER_LOGIN, then frames until the self-test has finished
--   W.unit.target.health = 0.19
--   Fake.tick(2)
--   Fake.restore()                           -- puts back every global this file set
--
-- Surface: Fake.world (W.unit[token] = { health, power = { [Enum.PowerType] = fraction }, max = { [Enum.PowerType] =
-- points }, powerType, dead }; W.secret: reads return secrets, true by default, as under the map lockdown; W.combat
-- does the same; W.secretBool: UnitIsDead returns a secret; W.maxSecret: UnitPowerMax returns a secret and
-- C_Secrets.ShouldUnitPowerMaxBeSecret says so; W.locale: GetLocale, "enUS" by default), Fake.tick(n), Fake.event(name,
-- ...), Fake.advance(seconds), Fake.set(knob, value), Fake.login(), Fake.restore(), Fake.printed (every print call: the
-- library makes none). Knobs: "closed" (bars fed a secret stop firing: the leak is closed), "lag" n (firings arrive n
-- frames late), "secretlag" n (a fill set from a secret fires n frames later still), "drop" n (every nth firing is
-- lost), "stagger" n (every nth firing queued arrives one frame later than the rest: one change's firings split over
-- two frames), "snap" "left"|"right"|"nearest" (how a Step curve picks its point), "maxpoints" n (curve size limit),
-- "refuse" name (that global function raises). The Cooldown Manager (the aura kind's source): W.cdm, W.aura,
-- Fake.setAura, Fake.cdmLayout, Fake.cdmEnable, Fake.viewers, Fake.touched, Fake.hooks; see the comment above its
-- viewers. Mode B (the managed layout): W.cdm.store (the layout store string, "" by default; set, it decides the
-- placement at login), W.cdm.writes (SetLayoutData calls), W.cdm.badWrite (a write keeps other bytes), W.cdm.opacity
-- (the viewers' Edit Mode alpha at a load), W.cdm.secretStore (GetLayoutData returns a secret), W.cdm.salt (a
-- number: the encoder is not canonical, each call's bytes differ), W.cdm.unlearned ({ [cooldownID] = true }: no
-- item, left out of the learned set), W.classID (11 by default; the spec is 1), Fake.encodeLayouts(t),
-- Fake.decodeLayouts(s), and the reload (ReloadUI(), Fake.reload(), Fake.onReload: see the comment above
-- Fake.reload). The encoders are stand-ins (sorted Lua text, reversed, hex), not CBOR, Deflate or Base64.
-- loadfile(path)({ before = fn, noLoad = true }): fn runs after the fake globals exist and before the library loads.
--
-- Fidelity limits: no taint model; a secret is a table, so only arithmetic, ordering, concatenation, tostring, length,
-- indexing and calls on it raise (equality, truthiness and use as a table key do not); a firing runs after every
-- OnUpdate of its frame (the self-test's measured "lag 0"), a secret one too by default, though in game a prime's
-- secret live push fired a frame later (LHVProbe 2026-11-20; steady-state secret timing unmeasured): "secretlag" 1
-- models that; 60 frames per second; debugprofilestop is os.clock; a frame's first layout fires its OnSizeChanged
-- once; the Cooldown Manager is a sketch of the client's (its fields, hooks and event fan-out as the probes and the
-- client's code show them, not its layout rules). It tests a consumer's logic against the library's contract, not the
-- game.
local opts = ... or {}
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local root = here .. "../"

local Fake = { frames = {}, errors = {}, printed = {} }
local W = {
    unit = {
        player = {
            health = 1.0,
            power = { [0] = 1.0, [3] = 1.0 },
            max = { [0] = 2000, [1] = 100, [3] = 100 },
            powerType = 0,
        },
    },
    secret = true,
}
W.cdm = { enabled = true, available = true, catalogue = {}, bar = {}, icon = {}, essential = {}, utility = {} }
W.aura = { player = {}, target = {} }
Fake.world = W
local K = { lag = 0, secretlag = 0, drop = 0, stagger = 0, snap = "left", maxpoints = 1000 }
local clock, tickNo, loggedIn, fireCount = 1000, 0, false, 0
local saved, installed = {}, {}

local function install(name, value)
    if not installed[name] then
        installed[name] = true
        saved[name] = rawget(_G, name)
    end
    rawset(_G, name, value)
end

-- Secrets: one wrapper per plain value (memoised, so steady reads allocate nothing).
local SECRET = setmetatable({}, { __mode = "k" })
local wrapOf = {}
local function boom()
    error("operation on a secret value", 2)
end
local smt = {
    __add = boom,
    __sub = boom,
    __mul = boom,
    __div = boom,
    __mod = boom,
    __pow = boom,
    __unm = boom,
    __lt = boom,
    __le = boom,
    __concat = boom,
    __len = boom,
    __call = boom,
    __tostring = boom,
    __index = boom,
    __newindex = boom,
}
local function secret(v)
    local w = wrapOf[v]
    if not w then
        w = setmetatable({}, smt)
        SECRET[w] = v == nil and false or v
        wrapOf[v] = w
    end
    return w
end
local function isSecret(v)
    return type(v) == "table" and SECRET[v] ~= nil
end
local function unwrap(v)
    if isSecret(v) then
        return SECRET[v]
    end
    return v
end
local function hidden()
    return W.secret or W.combat
end

-- Curves
local function curveEval(c, x)
    local pts = c.pts
    if K.snap == "right" then
        for i = 1, #pts do
            if pts[i][1] >= x then
                return pts[i][2]
            end
        end
        return pts[#pts][2]
    elseif K.snap == "nearest" then
        local best, bd
        for i = 1, #pts do
            local d = math.abs(pts[i][1] - x)
            if not bd or d < bd then
                best, bd = pts[i][2], d
            end
        end
        return best
    end
    local y
    for i = 1, #pts do
        if x >= pts[i][1] then
            y = pts[i][2]
        end
    end
    return y or pts[1][2]
end
local Curve = {}
Curve.__index = Curve
function Curve:SetType(t)
    self.t = t
end
function Curve:AddPoint(x, y)
    if #self.pts >= K.maxpoints then
        error("too many curve points")
    end
    local pts = self.pts
    pts[#pts + 1] = { x, y }
    if #pts > 1 and x < pts[#pts - 1][1] then -- points added in order need no sort
        table.sort(pts, function(a, b)
            return a[1] < b[1]
        end)
    end
end
function Curve:GetPointCount()
    return #self.pts
end
function Curve:Evaluate(x)
    if isSecret(x) then
        error("a curve refuses a secret from addon code")
    end
    return curveEval(self, x)
end

local function through(x, curve)
    if x == nil then
        return nil
    end
    if curve then
        x = curveEval(curve, x)
    end
    if hidden() then
        return secret(x)
    end
    return x
end

-- Frames: a StatusBar's fill change queues the OnSizeChanged of each frame anchored to its fill texture.
local qClip, qDue, qN, qCount = {}, {}, 0, 0
local function queue(clip, extra)
    qN, qCount = qN + 1, qCount + 1
    local late = (K.stagger > 0 and qCount % K.stagger == 0) and 1 or 0
    qClip[qN], qDue[qN] = clip, tickNo + K.lag + (extra or 0) + late
end
local Frame = {}
Frame.__index = Frame
local function noop() end
for _, m in ipairs({
    "SetSize",
    "SetWidth",
    "SetHeight",
    "ClearAllPoints",
    "EnableMouse",
    "SetFrameStrata",
    "SetStatusBarTexture",
    "SetClipsChildren",
    "SetMovable",
    "RegisterForDrag",
    "SetMultiLine",
    "SetAutoFocus",
    "SetFontObject",
    "SetScrollChild",
    "SetFocus",
    "HighlightText",
    "ClearFocus",
    "StartMoving",
    "StopMovingOrSizing",
}) do
    Frame[m] = noop
end
function Frame:SetAlpha(a)
    self.alpha = a
end
function Frame:GetAlpha()
    return self.alpha or 1
end
function Frame:Show()
    self.shown = true
end
function Frame:Hide()
    self.shown = false
end
function Frame:IsShown()
    return self.shown
end
function Frame:SetShown(on)
    self.shown = on and true or false
end
function Frame:IsVisible()
    return self.shown and (self.parent == nil or self.parent:IsVisible())
end
function Frame:SetText(s)
    self.text = s
end
function Frame:SetScript(s, fn)
    self.scripts[s] = fn
end
function Frame:GetScript(s)
    return self.scripts[s]
end
function Frame:HookScript(s, fn)
    error("HookScript: the library must not hook (" .. s .. ")")
end
function Frame:RegisterEvent(e)
    self.events[e] = true
end
function Frame:RegisterUnitEvent(e, ...)
    local units = {}
    for i = 1, select("#", ...) do
        units[select(i, ...)] = true
    end
    self.events[e] = units
end
function Frame:UnregisterEvent(e)
    self.events[e] = nil
end
function Frame:UnregisterAllEvents()
    self.events = {}
end
function Frame:GetStatusBarTexture()
    self.tex = self.tex or { bar = self }
    return self.tex
end
function Frame:SetPoint(p, rel)
    if p == "BOTTOMRIGHT" and type(rel) == "table" and rel.bar then
        local deps = rel.bar.deps
        deps[#deps + 1] = self
        queue(self) -- the first layout
    end
end
function Frame:SetMinMaxValues(a, b)
    self.min, self.max = unwrap(a), unwrap(b)
end
function Frame:SetValue(v)
    local s = isSecret(v)
    v = unwrap(v)
    local r = self.max - self.min
    local fr = r > 0 and math.max(0, math.min(1, (v - self.min) / r)) or 0
    if fr ~= self.fr then
        self.fr = fr
        if not (s and K.closed) then
            for i = 1, #self.deps do
                queue(self.deps[i], s and K.secretlag or 0)
            end
        end
    end
end

local function CreateFrame(kind, name, parent)
    local f = setmetatable({ kind = kind, scripts = {}, events = {}, deps = {}, min = 0, max = 1, shown = true }, Frame)
    f.parent = parent
    if name then
        install(name, f)
    end
    Fake.frames[#Fake.frames + 1] = f
    return f
end

-- Globals
local PT = { Mana = 0, Rage = 1, Focus = 2, Energy = 3 }
install("Enum", {
    LuaCurveType = { Linear = 0, Step = 1 },
    PowerType = PT,
    CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3 },
    CompressionMethod = { Deflate = 1 },
})
install("issecretvalue", isSecret)
install("C_CurveUtil", {
    CreateCurve = function()
        return setmetatable({ pts = {} }, Curve)
    end,
})
install("CreateFrame", CreateFrame)
install("GetTime", function()
    return clock
end)
install("debugprofilestop", function()
    return os.clock() * 1000
end)
install("IsLoggedIn", function()
    return loggedIn
end)
install("geterrorhandler", function()
    return function(err)
        Fake.errors[#Fake.errors + 1] = err
    end
end)
install("print", function(...)
    local t = {}
    for i = 1, select("#", ...) do
        t[i] = tostring(select(i, ...))
    end
    Fake.printed[#Fake.printed + 1] = table.concat(t, " ")
end)
install("GetLocale", function()
    return W.locale or "enUS"
end)
install("SlashCmdList", {})
install("UIParent", CreateFrame("Frame"))
install("LibStub", nil) -- each fake client gets its own LibStub and library
install("UnitHealthPercent", function(unit, predicted, curve)
    local u = W.unit[unit]
    if not u then
        return nil
    end
    return through(u.health, curve)
end)
install("UnitPowerPercent", function(unit, pt, unmodified, curve)
    local u = W.unit[unit]
    if not u then
        return nil
    end
    return through(u.power and u.power[pt or u.powerType] or 0, curve)
end)
install("UnitPowerMax", function(unit, pt)
    local u = W.unit[unit]
    local m = u and u.max and u.max[pt or u.powerType] or 0
    if W.maxSecret then
        return secret(m)
    end
    return m
end)
install("C_Secrets", {
    ShouldUnitPowerMaxBeSecret = function()
        return W.maxSecret and true or false
    end,
})
install("UnitPowerType", function(unit)
    local u = W.unit[unit]
    return u and u.powerType or 0
end)
install("UnitExists", function(unit)
    return W.unit[unit] ~= nil
end)
install("UnitIsDead", function(unit)
    local u = W.unit[unit]
    local d = u and u.dead or false
    if W.secretBool then
        return secret(d)
    end
    return d
end)

-- The Cooldown Manager: BuffBarCooldownViewer (tracked bars), BuffIconCooldownViewer (tracked buff icons),
-- EssentialCooldownViewer and UtilityCooldownViewer (cooldowns: an item shows its linked aura's presence, no count or
-- bar is modelled), each with an item pool. W.cdm = { enabled (the cooldownViewerEnabled CVar), available, catalogue =
-- { [cooldownID] = { spellID =, overrideSpellID =, overrideTooltipSpellID =, linkedSpellIDs = {}, category = 0-8 } },
-- bar = { cooldownID, ... }, icon, essential, utility = { ... } (what the player placed, in order), secretId, secretIdx
-- (in combat a refresh writes an item's
-- cooldownID / a layout pass its layoutIndex secret), secretUnit (an item's auraDataUnit is secret while reads are;
-- unprobed), noUnit (a held item names no unit), shuffle (a layout pass hands the frames out in another order),
-- quietSwap (on PLAYER_TARGET_CHANGED an Essential or Utility item refreshes only while it holds a target aura, as the
-- client's do without a range check: one gone silent stays silent on the next target until a target UNIT_AURA) }.
-- W.aura[unit][spellID] = { stacks =, expires = GetTime() at its end, duration = } on "player" and "target": the
-- player's own auras (Fake.setAura). The viewers lay out at login and on Fake.cdmLayout(), refresh their items on
-- UNIT_AURA and PLAYER_TARGET_CHANGED, push a tracked bar's SetMinMaxValues(0, duration) and SetValue(seconds left)
-- every frame while its aura is up (an expired aura is dropped), and do nothing while hidden (Fake.cdmEnable(false):
-- the CVar off, the viewers hidden, CVAR_UPDATE); Fake.cdmData() is a data change that keeps the item counts (only the
-- viewers' RefreshData runs). The count text gets SetText(a secret number) when reads are secret,
-- else the client's string ("" for one stack or none). Fake.touched lists every call made on a Cooldown Manager frame
-- from outside the fake Cooldown Manager (its own calls and the hook bodies' frames excluded); Fake.hooks counts
-- hooksecurefunc calls.
local inBlizz = false
Fake.touched, Fake.hooks = {}, 0
local BFrame = setmetatable({}, { __index = Frame })
BFrame.__index = BFrame
for _, m in ipairs({
    "Show",
    "Hide",
    "SetShown",
    "SetAlpha",
    "SetPoint",
    "ClearAllPoints",
    "SetSize",
    "SetWidth",
    "SetHeight",
    "SetParent",
    "SetScale",
    "SetValue",
    "SetMinMaxValues",
    "SetText",
    "EnableMouse",
    "SetMouseMotionEnabled",
    "SetScript",
    "SetFrameStrata",
    "RegisterEvent",
    "UnregisterEvent",
}) do
    local base = Frame[m] or noop
    BFrame[m] = function(self, ...)
        if not inBlizz then
            Fake.touched[#Fake.touched + 1] = m
        end
        return base(self, ...)
    end
end
local function bframe(parent, kind)
    return setmetatable({
        kind = kind or "Frame",
        scripts = {},
        events = {},
        deps = {},
        min = 0,
        max = 1,
        shown = true,
        parent = parent,
    }, BFrame)
end

install("hooksecurefunc", function(t, k, fn)
    if type(t) == "string" then
        t, k, fn = _G, t, k
    end
    local orig = t[k]
    if type(orig) ~= "function" then
        error("hooksecurefunc: " .. tostring(k) .. " is not a function")
    end
    Fake.hooks = Fake.hooks + 1
    rawset(t, k, function(...)
        local a, b = orig(...)
        local was = inBlizz
        inBlizz = false
        fn(...)
        inBlizz = was
        return a, b
    end)
end)
install("InCombatLockdown", function()
    return W.combat and true or false
end)
install("C_CVar", {
    GetCVarBool = function(name)
        if name == "cooldownViewerEnabled" then
            return W.cdm.enabled and true or false
        end
    end,
})
install("C_CooldownViewer", {
    IsCooldownViewerAvailable = function()
        return W.cdm.available and true or false
    end,
    GetCooldownViewerCategorySet = function(cat, allowUnlearned)
        local out = {}
        for id, info in pairs(W.cdm.catalogue) do
            if info.category == cat and (allowUnlearned or not (W.cdm.unlearned and W.cdm.unlearned[id])) then
                out[#out + 1] = id
            end
        end
        table.sort(out)
        return out
    end,
    GetCooldownViewerCooldownInfo = function(id)
        local info = W.cdm.catalogue[id]
        if not info then
            return nil
        end
        local c = { cooldownID = id }
        for k, v in pairs(info) do
            c[k] = v
        end
        return c
    end,
    GetLayoutData = function()
        return W.cdm.secretStore and secret(W.cdm.store) or W.cdm.store
    end,
    SetLayoutData = function(data)
        if W.cdm.badWrite then -- the client keeps something else than what was written
            data = data .. "x"
        end
        W.cdm.writes = (W.cdm.writes or 0) + 1
        W.cdm.store = data
    end,
})

-- C_EncodingUtil: a deterministic stand-in for CBOR (sorted Lua source), Deflate (reversed, tagged) and Base64 (hex).
-- Each decoder returns nil for input its encoder did not make.
local function ser(v)
    local t = type(v)
    if t == "number" then
        return string.format("%.17g", v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "boolean" then
        return tostring(v)
    end
    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then
            return type(a) < type(b)
        end
        return a < b
    end)
    local out = {}
    for i = 1, #keys do
        out[i] = "[" .. ser(keys[i]) .. "]=" .. ser(v[keys[i]])
    end
    return "{" .. table.concat(out, ",") .. "}"
end
install("C_EncodingUtil", {
    SerializeCBOR = function(t)
        if W.cdm.salt then -- not canonical: each call's bytes differ (a Lua comment the decoder ignores)
            W.cdm.salt = W.cdm.salt + 1
            return "CBOR" .. ser(t) .. "--" .. W.cdm.salt
        end
        return "CBOR" .. ser(t)
    end,
    DeserializeCBOR = function(s)
        if type(s) ~= "string" or s:sub(1, 4) ~= "CBOR" then
            return nil
        end
        local fn = loadstring("return " .. s:sub(5))
        return fn and setfenv(fn, {})()
    end,
    CompressString = function(s, method)
        assert(method == 1, "deflate expected")
        return "D" .. s:reverse()
    end,
    DecompressString = function(s, method)
        assert(method == 1, "deflate expected")
        if type(s) ~= "string" or s:sub(1, 1) ~= "D" then
            return nil
        end
        return s:sub(2):reverse()
    end,
    EncodeBase64 = function(s)
        return (s:gsub(".", function(c)
            return string.format("%02x", c:byte())
        end))
    end,
    DecodeBase64 = function(s)
        if type(s) ~= "string" or s:find("[^0-9a-f]") or #s % 2 == 1 then
            return nil
        end
        return (s:gsub("..", function(h)
            return string.char(tonumber(h, 16))
        end))
    end,
})
install("UnitClass", function()
    return "Class", "CLASS", W.classID or 11
end)
install("GetSpecialization", function()
    return 1 -- Forever: one spec per class
end)

-- The layout store as the client keeps it: "1|" .. base64(deflate(cbor(t))), "" when the player never saved one.
function Fake.encodeLayouts(t)
    local E = _G.C_EncodingUtil
    return "1|" .. E.EncodeBase64(E.CompressString(E.SerializeCBOR(t), 1))
end
function Fake.decodeLayouts(s)
    if s == nil or s == "" then
        return nil
    end
    local E = _G.C_EncodingUtil
    return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(s:sub(3)), 1))
end
W.cdm.store = ""

local UNITS = { "player", "target" }
local nextAuraId = 0
local function findAura(cd)
    local info = W.cdm.catalogue[cd]
    if not info then
        return nil
    end
    for u = 1, 2 do
        local auras = W.aura[UNITS[u]]
        if auras then
            local a = auras[info.spellID] or auras[info.overrideSpellID or 0] or auras[info.overrideTooltipSpellID or 0]
            local links = info.linkedSpellIDs
            for j = 1, links and #links or 0 do
                a = a or auras[links[j]]
            end
            if a then
                return a, UNITS[u]
            end
        end
    end
end

local function refreshItem(item)
    local a, unit
    if item.cd then
        a, unit = findAura(item.cd)
    end
    item.aura = a
    if a then
        if not a.id then
            nextAuraId = nextAuraId + 1
            a.id = nextAuraId
        end
        item.auraInstanceID = hidden() and secret(a.id) or a.id
        item.auraDataUnit = (hidden() and W.cdm.secretUnit) and secret(unit) or not W.cdm.noUnit and unit or nil
    else
        item.auraInstanceID, item.auraDataUnit = nil, nil
    end
    item.on = a and unit or nil
    local n = a and a.stacks or 0
    local fs = item.Icon and item.Icon.Applications or item.Applications and item.Applications.Applications
    if fs and hidden() then
        fs:SetText(secret(n))
    elseif fs then
        fs:SetText(n > 1 and tostring(n) or "")
    end
    if item.Bar and not a then
        item.Bar:SetMinMaxValues(0, 0)
        item.Bar:SetValue(0)
    end
end

local function refresh(v) -- RefreshData
    local ids = W.cdm[v.which]
    for item in pairs(v.itemFramePool.active) do
        local cd = ids[item.idx]
        item.cd = cd
        if cd == nil then
            item.cooldownID = nil
        else
            item.cooldownID = (W.combat and W.cdm.secretId) and secret(cd) or cd
        end
        refreshItem(item)
    end
end

local function newItem(v)
    local item = bframe(v)
    v.made = v.made + 1
    item.slot = v.made
    if v.which == "bar" then
        item.Icon = bframe(item)
        item.Icon.Applications = bframe(item.Icon, "FontString")
        item.Bar = bframe(item, "StatusBar")
    elseif v.which == "icon" then
        item.Applications = bframe(item)
        item.Applications.Applications = bframe(item.Applications, "FontString")
    end
    return item
end

local function layout(v) -- RefreshLayout: release every item, acquire max(#ids, 2) again, then RefreshData
    local pool = v.itemFramePool
    local rel = {}
    for item in pairs(pool.active) do
        rel[#rel + 1] = item
    end
    table.sort(rel, function(a, b) -- the last released is acquired first: unshuffled, each frame keeps its index
        return a.slot > b.slot
    end)
    for _, item in ipairs(rel) do
        pool.active[item] = nil
        item.cooldownID, item.layoutIndex, item.idx, item.cd = nil, nil, nil, nil
        item.auraInstanceID, item.auraDataUnit, item.aura, item.on = nil, nil, nil, nil
        item:Hide()
        pool.inactive[#pool.inactive + 1] = item
    end
    if W.cdm.shuffle then
        local inactive, n = pool.inactive, #pool.inactive
        for i = 1, math.floor(n / 2) do
            inactive[i], inactive[n + 1 - i] = inactive[n + 1 - i], inactive[i]
        end
    end
    for i = 1, math.max(#W.cdm[v.which], 2) do
        local item = table.remove(pool.inactive) or newItem(v)
        pool.active[item] = true
        item.idx = i
        item.layoutIndex = (W.combat and W.cdm.secretIdx) and secret(i) or i
        v:OnAcquireItemFrame(item)
        item:Show()
    end
    v:RefreshData() -- method-dispatched, as the client does (a hook sees it)
end

local viewers = {}
local function blizz(fn, v)
    local was = inBlizz
    inBlizz = true
    fn(v)
    inBlizz = was
end
local function tickBars(v)
    if not v:IsVisible() then
        return
    end
    local now = clock
    for item in pairs(v.itemFramePool.active) do
        local a = item.aura
        if a and item.Bar then
            local left = a.expires - now
            if left <= 0 then
                for u = 1, 2 do
                    local auras = W.aura[UNITS[u]]
                    for spell, x in pairs(auras) do
                        if x == a then
                            auras[spell] = nil
                        end
                    end
                end
                for k = 1, #viewers do
                    refresh(viewers[k])
                end
            else
                item.Bar:SetMinMaxValues(0, a.duration)
                item.Bar:SetValue(hidden() and secret(left) or left)
            end
        end
    end
end
-- Placement from the stored layouts (what the client loads at login): the active layout of the player's tag, its
-- category overrides over each entry's default category; unlearned entries show no item. Only when a store was saved.
local function derive()
    local t = Fake.decodeLayouts(W.cdm.store)
    if not t then
        return
    end
    local C = _G.Enum.CooldownViewerCategory
    local tag = (W.classID or 11) * 10 + 1
    local act = t[2] and t[2][tag]
    local lay = act and act ~= 0 and t[3] and t[3][tag] and t[3][tag][act]
    local over = {}
    for cat, list in pairs(lay and lay[2] or {}) do
        for _, cd in ipairs(list) do
            over[cd] = cat
        end
    end
    local placed = { bar = {}, icon = {}, essential = {}, utility = {} }
    local list = {
        [C.TrackedBar] = placed.bar,
        [C.TrackedBuff] = placed.icon,
        [C.Essential] = placed.essential,
        [C.Utility] = placed.utility,
    }
    local ids = {}
    for cd in pairs(W.cdm.catalogue) do
        ids[#ids + 1] = cd
    end
    table.sort(ids)
    for _, cd in ipairs(ids) do
        local l = list[over[cd] or W.cdm.catalogue[cd].category]
        if l and not (W.cdm.unlearned and W.cdm.unlearned[cd]) then
            l[#l + 1] = cd
        end
    end
    for which, l in pairs(placed) do
        W.cdm[which] = l
    end
end

local function viewerEvent(v, event)
    if event == "PLAYER_LOGIN" then
        derive()
        v.shown = W.cdm.enabled and true or false
        if v.shown then
            layout(v)
        end
    elseif not v:IsVisible() then
        return
    elseif
        event == "PLAYER_TARGET_CHANGED"
        and W.cdm.quietSwap
        and (v.which == "essential" or v.which == "utility")
    then
        for item in pairs(v.itemFramePool.active) do
            if item.on == "target" then
                refreshItem(item)
            end
        end
    else
        refresh(v)
    end
end
-- The four viewers (built again by a reload), each with its item pool, in Fake.viewers in this order.
local VIEWER_NAMES = {
    bar = "BuffBarCooldownViewer",
    icon = "BuffIconCooldownViewer",
    essential = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
}
local function makeViewers()
    for k = #viewers, 1, -1 do
        viewers[k] = nil
    end
    for _, which in ipairs({ "bar", "icon", "essential", "utility" }) do
        local v = bframe(_G.UIParent)
        v.which, v.made = which, 0
        v.itemFramePool = {
            active = {},
            inactive = {},
            EnumerateActive = function(pool)
                return pairs(pool.active)
            end,
        }
        v.OnAcquireItemFrame = function() end
        v.RefreshData = function(self) -- the viewer's own: a layout pass or a data change (aura events refresh items)
            refresh(self)
        end
        v.events = { PLAYER_LOGIN = true, UNIT_AURA = true, PLAYER_TARGET_CHANGED = true }
        v.scripts.OnEvent = function(self, event)
            local was = inBlizz
            inBlizz = true
            viewerEvent(self, event)
            inBlizz = was
        end
        v.scripts.OnUpdate = function(self)
            blizz(tickBars, self)
        end
        install(VIEWER_NAMES[which], v)
        Fake.frames[#Fake.frames + 1] = v
        viewers[#viewers + 1] = v
    end
    if W.cdm.opacity then -- Edit Mode's opacity, applied as the viewers load
        for _, name in ipairs({ "Essential", "Utility", "BuffIcon", "BuffBar" }) do
            _G[name .. "CooldownViewer"].alpha = W.cdm.opacity
        end
    end
end
makeViewers()
Fake.viewers = viewers

-- A layout pass on every viewer (the player changed the layout, a full aura update, a show).
function Fake.cdmLayout()
    for k = 1, #viewers do
        if viewers[k]:IsVisible() then
            blizz(layout, viewers[k])
        end
    end
end

-- A data change that keeps each viewer's item count (a drag reorder, a swap, a change at the 2-item minimum): the
-- client calls only RefreshData, no frame is acquired and no event is sent.
function Fake.cdmData()
    for k = 1, #viewers do
        if viewers[k]:IsVisible() then
            blizz(viewers[k].RefreshData, viewers[k])
        end
    end
end

-- Sets (stacks a number) or removes (stacks nil) an aura on unit and sends UNIT_AURA.
function Fake.setAura(unit, spell, stacks, seconds)
    local auras = W.aura[unit]
    if stacks == nil then
        auras[spell] = nil
    else
        local a = auras[spell] or {}
        a.stacks, a.duration = stacks, seconds or 30
        a.expires = clock + (seconds or 30)
        auras[spell] = a
    end
    Fake.event("UNIT_AURA", unit)
end

-- The cooldownViewerEnabled CVar: the viewers show or hide (shown again: a layout pass), then CVAR_UPDATE.
function Fake.cdmEnable(on)
    W.cdm.enabled = on
    for k = 1, #viewers do
        local v = viewers[k]
        local was = v.shown
        v.shown = on and true or false
        if on and not was then
            blizz(layout, v)
        end
    end
    Fake.event("CVAR_UPDATE", "cooldownViewerEnabled", on and "1" or "0")
end

-- Driver
local sW, sH = secret(20), secret(2)
function Fake.tick(n)
    for _ = 1, n or 1 do
        if not loggedIn then
            Fake.event("PLAYER_LOGIN")
        end
        clock = clock + 1 / 60
        tickNo = tickNo + 1
        local frames = Fake.frames
        for i = 1, #frames do
            local f = frames[i]
            local fn = f.scripts.OnUpdate
            if fn then
                fn(f, 1 / 60)
            end
        end
        local n0, keep = qN, 0
        for i = 1, n0 do
            local c = qClip[i]
            if qDue[i] <= tickNo then
                fireCount = fireCount + 1
                local fn = c.scripts.OnSizeChanged
                if fn and not (K.drop > 0 and fireCount % K.drop == 0) then
                    fn(c, sW, sH)
                end
            else
                keep = keep + 1
                qClip[keep], qDue[keep] = c, qDue[i]
            end
        end
        for i = n0 + 1, qN do -- queued by a script during this pass: next frame
            keep = keep + 1
            qClip[keep], qDue[keep] = qClip[i], qDue[i]
        end
        for i = keep + 1, qN do
            qClip[i] = nil
        end
        qN = keep
    end
end

function Fake.advance(seconds)
    Fake.tick(math.floor(seconds * 60 + 0.5))
end

function Fake.event(name, ...)
    if name == "PLAYER_LOGIN" then
        loggedIn = true
    end
    local frames = Fake.frames
    for i = 1, #frames do
        local f = frames[i]
        local reg = f.events[name]
        if reg and (reg == true or reg[(...)]) and f.scripts.OnEvent then
            f.scripts.OnEvent(f, name, ...)
        end
    end
end

-- PLAYER_LOGIN, then frames until the library's self-test has a verdict (at most 120). Returns that verdict.
function Fake.login()
    if not loggedIn then
        Fake.event("PLAYER_LOGIN")
    end
    local lib = rawget(_G, "LibStub") and _G.LibStub("LibHiddenValues-1.0", true)
    for _ = 1, 120 do
        if not lib or lib.stVerdict ~= nil and not lib.st then
            break
        end
        Fake.tick(1)
    end
    return lib and lib.stVerdict
end

-- A UI reload (the consumer's ReloadUI from a click): every frame, the viewers and the library are built again and
-- login runs; only the world (W, the layout store among it), the clock and the knobs survive. Fake.onReload(Fake), when
-- set, runs after the library loaded and before login: the consumer's files loading again (hand it the store it
-- persisted). Returns the self-test verdict, as Fake.login.
function Fake.reload()
    if W.combat then
        error("the fake does not reload in combat")
    end
    loggedIn = false
    for i = 1, qN do
        qClip[i] = nil
    end
    qN = 0
    Fake.frames = {}
    install("UIParent", CreateFrame("Frame"))
    makeViewers()
    install("LibStub", nil)
    Fake.loadLibrary()
    if Fake.onReload then
        Fake.onReload(Fake)
    end
    return Fake.login()
end
install("ReloadUI", function()
    Fake.reloads = (Fake.reloads or 0) + 1
    Fake.reload()
end)

-- A secret of v (the fake's own kind), for a test to plant in a field the library reads.
Fake.secret = secret

function Fake.set(knob, value)
    if knob == "refuse" then
        install(value, function()
            error(value .. " refused")
        end)
    elseif K[knob] ~= nil or knob == "closed" then
        K[knob] = value
    else
        error("unknown knob " .. tostring(knob))
    end
end

function Fake.restore()
    for name in pairs(installed) do
        rawset(_G, name, saved[name])
    end
    installed, saved = {}, {}
end

-- The library, file by file in TOC order. minor: load it under another minor number (upgrade tests).
function Fake.loadLibrary(minor)
    for line in io.lines(root .. "LibHiddenValues.toc") do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local path = root .. line:gsub("\\", "/")
            local f = assert(io.open(path, "rb"))
            local src = f:read("*a")
            f:close()
            if minor then
                src = src:gsub('"LibHiddenValues%-1%.0", %d+', '"LibHiddenValues-1.0", ' .. minor)
            end
            assert(loadstring(src, "@" .. path))()
        end
    end
    -- Globals the library or LibStub created are restored with the rest.
    if not installed.LibStub then
        installed.LibStub, saved.LibStub = true, nil
    end
end

if opts.before then
    opts.before(Fake)
end
if not opts.noLoad then
    Fake.loadLibrary()
end
return Fake
