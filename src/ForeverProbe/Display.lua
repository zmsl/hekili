-- Display.lua: the direct display checks of the display analysis §4.1 on a small panel the user looks at:
-- PR20 descending Step curve through UnitPowerPercent, PR21 SetAlpha hides a child Cooldown's swipe, PR22 plain
-- SetCooldown in combat, PR23 Edit Mode nine-slice atlas pieces, PR24 SetGradient alpha ramp, PR28 duration
-- objects (fed by PR11), plus the halo TGA as the panel's backdrop and the PR7 range tint square.
-- Results go to ns.session.DISPLAY while a session runs (a scratch table otherwise).
local _, ns = ...
local IsSecret, Enc, ErrText, Round = ns.IsSecret, ns.Enc, ns.ErrText, ns.Round
local Display = {}
ns.Display = Display

local HALO = "Interface\\AddOns\\ForeverProbe\\Media\\halo64"
local STEP = (Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step) or 1
local THRESHOLD = { [0] = 50, [1] = 15, [3] = 35 } -- percent of max by power type: mana, rage, energy
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ICON_FALLBACK = 134400

local panel, W
local scratch = {}
local powerType = 3
local lastPowerCheck, lastCd22 = 0, 0

local function Results()
    if ns.session then
        ns.session.DISPLAY = ns.session.DISPLAY or {}
        return ns.session.DISPLAY
    end
    return scratch
end

local function Side()
    return ns.InCombat() and "C" or "O"
end

local function Bump(key)
    local r = Results()
    r[key] = (r[key] or 0) + 1
end

local function Tex(parent, layer, w, h)
    local t = parent:CreateTexture(nil, layer)
    if w then
        t:SetSize(w, h)
    end
    return t
end

local function Label(parent, text, size)
    local s = parent:CreateFontString(nil, "OVERLAY")
    s:SetFont(FONT, size or 10, "OUTLINE")
    s:SetText(text)
    return s
end

local function Color(r, g, b, a)
    if type(CreateColor) == "function" then
        return CreateColor(r, g, b, a)
    end
    return { r = r, g = g, b = b, a = a }
end

local function StepCurve(points)
    local c = C_CurveUtil.CreateCurve()
    c:SetType(STEP)
    for _, pt in ipairs(points) do
        c:AddPoint(pt[1], pt[2])
    end
    return c
end

local function Threshold()
    return THRESHOLD[powerType] or 35
end

local function RebuildCurves()
    if not W or not W.gates then
        return
    end
    local thr = Threshold()
    for _, g in ipairs(W.gates) do
        local ok, err = pcall(function()
            g.curve:ClearPoints()
            local t = g.scale == 1 and thr / 100 or thr
            if g.desc then
                g.curve:AddPoint(0, 1)
                g.curve:AddPoint(t, 0)
            else
                g.curve:AddPoint(0, 0)
                g.curve:AddPoint(t, 1)
            end
        end)
        if not ok then
            Results().pr20_curveErr = ErrText(err)
        end
    end
    if W.thrLabel then
        W.thrLabel:SetText(string.format("PR20 power type %d, threshold %d%%", powerType, thr))
    end
end

-- A spell icon for the panel (plain fileID or the fallback).
local function IconFor(role)
    local id = ns.RoleSpell and ns.RoleSpell(role)
    local f = C_Spell and C_Spell.GetSpellTexture
    if id and f then
        local ok, tex = pcall(f, id)
        if ok and not IsSecret(tex) and type(tex) == "number" then
            return tex
        end
    end
    return ICON_FALLBACK
end

local function MakeCooldown(parent)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, parent, "CooldownFrameTemplate")
    if not ok or not cd then
        cd = CreateFrame("Cooldown", nil, parent)
        Results().cooldownTemplate = ok and "nil" or ErrText(cd)
    end
    cd:SetAllPoints(parent)
    return cd
end

-- PR23: one nine-slice piece. Un-mirrored pieces use SetAtlas; mirrored corners use the atlas's own coordinates
-- flipped (the Edit Mode set ships a single corner). Each piece's outcome is recorded.
local PIECE = {
    center = "editmode-actionbar-highlight-nineslice-center",
    corner = "editmode-actionbar-highlight-nineslice-corner",
    top = "_editmode-actionbar-highlight-nineslice-edgetop",
    bottom = "_editmode-actionbar-highlight-nineslice-edgebottom",
    left = "!editmode-actionbar-highlight-nineslice-edgeleft",
    right = "!editmode-actionbar-highlight-nineslice-edgeright",
}
local function AtlasPiece(parent, name, flipX, flipY)
    local t = parent:CreateTexture(nil, "OVERLAY")
    local r = Results()
    r.pr23 = r.pr23 or {}
    local label = name .. (flipX and "_fx" or "") .. (flipY and "_fy" or "")
    local gai = C_Texture and C_Texture.GetAtlasInfo
    if not gai then
        r.pr23[label] = "-"
        t:SetColorTexture(0, 0.6, 1, 0.6)
        return t
    end
    local okI, info = pcall(gai, name)
    if not okI then
        r.pr23[label] = ErrText(info)
        t:SetColorTexture(0, 0.6, 1, 0.6)
        return t
    end
    if IsSecret(info) or type(info) ~= "table" then
        r.pr23[label] = "noinfo"
        t:SetColorTexture(0, 0.6, 1, 0.6)
        return t
    end
    if flipX or flipY then
        local ok, err = pcall(function()
            t:SetTexture(info.file or info.filename)
            local l, rr, tp, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
            if flipX then
                l, rr = rr, l
            end
            if flipY then
                tp, b = b, tp
            end
            t:SetTexCoord(l, rr, tp, b)
        end)
        r.pr23[label] = ok or ErrText(err)
    else
        local ok, err = pcall(t.SetAtlas, t, name, true)
        r.pr23[label] = ok or ErrText(err)
    end
    return t
end

local function Build()
    W = {}
    local r = Results()
    panel = CreateFrame("Frame", "ForeverProbePanel", UIParent)
    panel:SetSize(360, 250)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    panel:SetFrameStrata("HIGH")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)

    -- Halo backdrop (the chosen styling, §3.5 direction b).
    local halo = Tex(panel, "BACKGROUND")
    halo:SetPoint("TOPLEFT", panel, "TOPLEFT", -16, 16)
    halo:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 16, -16)
    local okT, errT = pcall(halo.SetTexture, halo, HALO)
    r.halo_setTexture = okT or ErrText(errT)
    local okS, errS = pcall(halo.SetTextureSliceMargins, halo, 16, 16, 16, 16)
    r.halo_sliceMargins = okS or ErrText(errS)
    halo:SetVertexColor(0, 0, 0, 0.62)
    W.halo = halo

    -- PR23 outline around the panel.
    local o = {}
    o.center = AtlasPiece(panel, PIECE.center)
    o.center:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    o.center:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    o.center:SetAlpha(0.25)
    o.tl = AtlasPiece(panel, PIECE.corner)
    o.tl:SetPoint("TOPLEFT")
    o.tr = AtlasPiece(panel, PIECE.corner, true, false)
    o.tr:SetPoint("TOPRIGHT")
    o.bl = AtlasPiece(panel, PIECE.corner, false, true)
    o.bl:SetPoint("BOTTOMLEFT")
    o.br = AtlasPiece(panel, PIECE.corner, true, true)
    o.br:SetPoint("BOTTOMRIGHT")
    for _, k in ipairs({ "tl", "tr", "bl", "br" }) do
        o[k]:SetSize(16, 16)
    end
    o.top = AtlasPiece(panel, PIECE.top)
    o.top:SetPoint("TOPLEFT", o.tl, "TOPRIGHT")
    o.top:SetPoint("BOTTOMRIGHT", o.tr, "BOTTOMLEFT")
    o.bottom = AtlasPiece(panel, PIECE.bottom)
    o.bottom:SetPoint("TOPLEFT", o.bl, "TOPRIGHT")
    o.bottom:SetPoint("BOTTOMRIGHT", o.br, "BOTTOMLEFT")
    o.left = AtlasPiece(panel, PIECE.left)
    o.left:SetPoint("TOPLEFT", o.tl, "BOTTOMLEFT")
    o.left:SetPoint("BOTTOMRIGHT", o.bl, "TOPRIGHT")
    o.right = AtlasPiece(panel, PIECE.right)
    o.right:SetPoint("TOPLEFT", o.tr, "BOTTOMLEFT")
    o.right:SetPoint("BOTTOMRIGHT", o.br, "TOPRIGHT")
    W.outline = o

    local title = Label(panel, "ForeverProbe display checks (drag to move; /fprobe panel hide)", 11)
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)

    -- PR20: four gate squares. Left pair: 0-100 scale; right pair: 0-1 scale. Exactly one of each pair should be lit.
    local y = -32
    W.thrLabel = Label(panel, "", 10)
    W.thrLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
    y = y - 14
    W.gates = {}
    local function Gate(name, x, desc, scale, color)
        -- A dim slot under each square, so a square at alpha 0 (the gate says "not lit") still shows where it sits.
        local slot = Tex(panel, "BACKGROUND", 20, 20)
        slot:SetPoint("TOPLEFT", panel, "TOPLEFT", x - 1, y + 1)
        slot:SetColorTexture(0.35, 0.35, 0.35, 0.5)
        local t = Tex(panel, "ARTWORK", 18, 18)
        t:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        t:SetColorTexture(color[1], color[2], color[3], 1)
        local curve = StepCurve({})
        table.insert(W.gates, { name = name, curve = curve, desc = desc, scale = scale, target = t })
        return t
    end
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        Gate("desc100", 14, true, 100, { 1, 0.8, 0.2 })
        Gate("asc100", 36, false, 100, { 0.2, 0.9, 0.3 })
        Gate("desc1", 80, true, 1, { 1, 0.8, 0.2 })
        Gate("asc1", 102, false, 1, { 0.2, 0.9, 0.3 })
        Label(panel, "<thr >=thr (0-100)   <thr >=thr (0-1)", 9):SetPoint("TOPLEFT", panel, "TOPLEFT", 126, y - 4)
    else
        r.pr20_curve = "-"
    end
    y = y - 26

    -- PR21: a frame holding an icon and a Cooldown; the whole frame's alpha follows the descending curve.
    local gf = CreateFrame("Frame", nil, panel)
    gf:SetSize(28, 28)
    gf:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
    local gi = Tex(gf, "ARTWORK")
    gi:SetAllPoints()
    gi:SetTexture(IconFor("melee"))
    gi:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    W.cd21 = MakeCooldown(gf)
    W.cd21:SetHideCountdownNumbers(false)
    W.gateFrame = gf
    if #W.gates > 0 then
        table.insert(W.gates, { name = "pr21", curve = W.gates[1].curve, desc = true, scale = 100, target = gf, shared = true })
    end
    Label(panel, "PR21: icon + swipe vanish together at >= thr", 9):SetPoint("LEFT", gf, "RIGHT", 6, 0)

    -- PR22: plain SetCooldown looping 10 s.
    local f22 = CreateFrame("Frame", nil, panel)
    f22:SetSize(28, 28)
    f22:SetPoint("TOPLEFT", panel, "TOPLEFT", 200, y)
    local i22 = Tex(f22, "ARTWORK")
    i22:SetAllPoints()
    i22:SetTexture(IconFor("cd"))
    i22:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    W.cd22 = MakeCooldown(f22)
    Label(panel, "PR22: 10 s loop (plain)", 9):SetPoint("LEFT", f22, "RIGHT", 6, 0)
    y = y - 36

    -- PR24: alpha ramp and colour ramp.
    local g1 = Tex(panel, "ARTWORK", 130, 14)
    g1:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
    g1:SetColorTexture(1, 1, 1, 1)
    local okG, errG = pcall(g1.SetGradient, g1, "HORIZONTAL", Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.05))
    r.pr24_alphaRamp = okG or ErrText(errG)
    local g2 = Tex(panel, "ARTWORK", 130, 14)
    g2:SetPoint("TOPLEFT", panel, "TOPLEFT", 200, y)
    g2:SetColorTexture(1, 1, 1, 1)
    local okG2, errG2 = pcall(g2.SetGradient, g2, "HORIZONTAL", Color(1, 0.2, 0.2, 1), Color(0.2, 0.4, 1, 1))
    r.pr24_colourRamp = okG2 or ErrText(errG2)
    r.pr24_createColor = type(CreateColor) == "function"
    Label(panel, "PR24: alpha ramp (left) and colour ramp (right)", 9):SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y - 16)
    y = y - 36

    -- PR28 / PR11: Cooldown from a duration object; Cooldown from (maybe secret) start/duration.
    local f28 = CreateFrame("Frame", nil, panel)
    f28:SetSize(28, 28)
    f28:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
    local i28 = Tex(f28, "ARTWORK")
    i28:SetAllPoints()
    i28:SetTexture(IconFor("cd"))
    i28:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    W.cd28 = MakeCooldown(f28)
    Label(panel, "PR28: duration object", 9):SetPoint("LEFT", f28, "RIGHT", 6, 0)
    local f11 = CreateFrame("Frame", nil, panel)
    f11:SetSize(28, 28)
    f11:SetPoint("TOPLEFT", panel, "TOPLEFT", 200, y)
    local i11 = Tex(f11, "ARTWORK")
    i11:SetAllPoints()
    i11:SetTexture(IconFor("cd"))
    i11:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    W.cd11 = MakeCooldown(f11)
    Label(panel, "PR11: secret start/dur", 9):SetPoint("LEFT", f11, "RIGHT", 6, 0)
    y = y - 36

    -- PR7: tint square.
    W.green, W.red = Color(0.2, 0.9, 0.3, 1), Color(0.9, 0.2, 0.2, 1)
    W.tint = Tex(panel, "ARTWORK", 18, 18)
    W.tint:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)
    W.tint:SetColorTexture(1, 1, 1, 1)
    Label(panel, "PR7: green = melee spell in range (SetVertexColorFromBoolean)", 9):SetPoint("LEFT", W.tint, "RIGHT", 6, 0)
    y = y - 26

    W.status = Label(panel, "", 9)
    W.status:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, y)

    RebuildCurves()
    panel:SetScript("OnUpdate", function()
        Display.Tick(GetTime())
    end)
    r.built = true
end

function Display.Tick(now)
    if not panel or not panel:IsShown() then
        return
    end
    local r = Results()
    local side = Side()
    if now - lastPowerCheck >= 2 then
        lastPowerCheck = now
        local ok, pt = pcall(UnitPowerType, "player")
        if ok and not IsSecret(pt) and type(pt) == "number" and pt ~= powerType then
            powerType = pt
            RebuildCurves()
        end
        W.status:SetText(string.format("%s | gate results: secret C %d / O %d, plain C %d / O %d", ns.InCombat() and "IN COMBAT" or "out of combat",
            r.pr20_secretC or 0, r.pr20_secretO or 0, r.pr20_plainC or 0, r.pr20_plainO or 0))
    end
    local upp = UnitPowerPercent
    if upp and W.gates then
        for _, g in ipairs(W.gates) do
            local ok, v = pcall(upp, "player", powerType, false, g.curve)
            if ok then
                if not g.shared then
                    if IsSecret(v) then
                        Bump("pr20_secret" .. side)
                    else
                        Bump("pr20_plain" .. side)
                        r["pr20_" .. g.name .. "_last" .. side] = Enc(v)
                    end
                end
                local okA, err = pcall(g.target.SetAlpha, g.target, v)
                if okA then
                    Bump((g.shared and "pr21_setAlphaOk" or "pr20_setAlphaOk") .. side)
                else
                    r[(g.shared and "pr21" or "pr20") .. "_setAlphaErr" .. side] = ErrText(err)
                end
            else
                r["pr20_err" .. side] = ErrText(v)
            end
        end
    elseif r.pr20_noAPI == nil then
        r.pr20_noAPI = upp == nil and "UnitPowerPercent absent" or "no curves"
    end
    if now - lastCd22 >= 10 then
        lastCd22 = now
        local ok, err = pcall(W.cd22.SetCooldown, W.cd22, now, 10)
        if ok then
            Bump("pr22_ok" .. side)
        else
            r["pr22_err" .. side] = ErrText(err)
        end
        local okT, s, d = pcall(W.cd22.GetCooldownTimes, W.cd22)
        if okT then
            r["pr22_times" .. side] = { Enc(s), Enc(d) }
        else
            r.pr22_timesErr = ErrText(s)
        end
        pcall(W.cd21.SetCooldown, W.cd21, now, 10)
    end
end

-- PR7: hands a (maybe secret) boolean to SetVertexColorFromBoolean. Returns true, "nil" or "E:…".
function Display.RangeTint(v)
    if not panel then
        return "nopanel"
    end
    if not IsSecret(v) and v == nil then
        return "nil"
    end
    local ok, err = pcall(W.tint.SetVertexColorFromBoolean, W.tint, v, W.green, W.red)
    if ok then
        return true
    end
    return ErrText(err)
end

-- PR28: feeds a duration object to a Cooldown.
function Display.SetDurationObject(d)
    if not panel then
        return "nopanel"
    end
    local ok, err = pcall(W.cd28.SetCooldownFromDurationObject, W.cd28, d)
    if ok then
        return true
    end
    return ErrText(err)
end

-- PR11: feeds (maybe secret) start/duration numbers to a Cooldown.
function Display.SetCooldownRaw(start, duration)
    if not panel then
        return "nopanel"
    end
    local ok, err = pcall(W.cd11.SetCooldown, W.cd11, start, duration)
    if ok then
        return true
    end
    return ErrText(err)
end

-- PR28: bytes per call of fn(...) over 200 calls (the GC is paused; everything under pcall). Returns a number or "E:…".
function Display.MeasureAlloc(verbose, fn, ...)
    if type(fn) ~= "function" then
        local f = C_Spell and C_Spell.GetSpellCooldownDuration
        local id = ns.RoleSpell and ns.RoleSpell("cd")
        if not f or not id then
            if verbose then
                ns.Print("alloc: no GetSpellCooldownDuration or no cooldown spell (start a session first)")
            end
            return "-"
        end
        return Display.MeasureAlloc(verbose, f, id)
    end
    local args = { ... }
    local n = 200
    local ok, res = pcall(function()
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, n do
            fn(unpack(args))
        end
        local after = collectgarbage("count")
        collectgarbage("restart")
        return (after - before) * 1024 / n
    end)
    local out
    if ok then
        out = Round(res)
    else
        pcall(collectgarbage, "restart")
        out = ErrText(res)
    end
    local r = Results()
    r["pr28_alloc" .. Side()] = out
    if verbose then
        ns.Print("PR28 GetSpellCooldownDuration: " .. tostring(out) .. " bytes/call (" .. (ns.InCombat() and "in combat" or "out of combat") .. ")")
    end
    return out
end

function Display.Show()
    if not panel then
        local ok, err = pcall(Build)
        if not ok then
            Results().buildErr = ErrText(err)
            ns.Print("display panel failed to build: " .. ErrText(err))
            return
        end
    end
    panel:Show()
end

function Display.Hide()
    if panel then
        panel:Hide()
    end
end

function Display.SetScale(v)
    if panel then
        panel:SetScale(v)
    end
end
