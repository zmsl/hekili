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
-- Surface: Fake.world (W.unit[token] = { health, power = { [Enum.PowerType] = fraction }, powerType, dead };
-- W.secret: reads return secrets, true by default, as under the map lockdown; W.combat does the same; W.secretBool:
-- UnitIsDead returns a secret), Fake.tick(n), Fake.event(name, ...), Fake.advance(seconds), Fake.set(knob, value),
-- Fake.login(), Fake.restore(), Fake.printed (every print call: the library makes none). Knobs: "closed" (bars fed a secret stop firing: the leak is closed),
-- "lag" n (firings arrive n frames late), "drop" n (every nth firing is lost), "snap" "left"|"right"|"nearest" (how a
-- Step curve picks its point), "maxpoints" n (curve size limit), "refuse" name (that global function raises).
-- loadfile(path)({ before = fn, noLoad = true }): fn runs after the fake globals exist and before the library loads.
--
-- Fidelity limits: no taint model; a secret is a table, so only arithmetic, ordering, concatenation, tostring, length,
-- indexing and calls on it raise (equality, truthiness and use as a table key do not); a firing runs after every
-- OnUpdate of its frame (the measured "lag 0"); 60 frames per second; debugprofilestop is os.clock; a frame's first
-- layout fires its OnSizeChanged once. It tests a consumer's logic against the library's contract, not the game.
local opts = ... or {}
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local root = here .. "../"

local Fake = { frames = {}, errors = {}, printed = {} }
local W = { unit = { player = { health = 1.0, power = { [0] = 1.0, [3] = 1.0 }, powerType = 0 } }, secret = true }
Fake.world = W
local K = { lag = 0, drop = 0, snap = "left", maxpoints = 1000 }
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
    self.pts[#self.pts + 1] = { x, y }
    table.sort(self.pts, function(a, b)
        return a[1] < b[1]
    end)
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
local qClip, qDue, qN = {}, {}, 0
local function queue(clip)
    qN = qN + 1
    qClip[qN], qDue[qN] = clip, tickNo + K.lag
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
function Frame:Show()
    self.shown = true
end
function Frame:Hide()
    self.shown = false
end
function Frame:IsShown()
    return self.shown
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
                queue(self.deps[i])
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
install("Enum", { LuaCurveType = { Linear = 0, Step = 1 }, PowerType = PT })
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
