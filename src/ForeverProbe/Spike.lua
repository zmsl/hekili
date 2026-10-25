-- Spike.lua: the throwaway two-zone spike frame for PR25-PR27, PR29 and PR30 (display analysis §4.1 checks
-- 6-8, 10, 11) and the feathered-halo seam check (§3.5). Built once on `/fprobe spike show`: a NOW cell (56
-- units) and a NEXT ruler (264 x 40 units) with 8 gliding 20-unit icons, stems, window bars, caps, a marker, a
-- cooldown sweep on a 20-unit icon, the halo backdrops and the Edit Mode outline. About 100 regions.
--
-- Measured: build time and memory (PR25), the OnUpdate body in ms via debugprofilestop() (PR26), GetFramerate()
-- with the spike shown vs hidden (PR26), and the gap between a window bar's right edge and its icon read in the
-- same frame the icon moved (PR27). PR29 (icon strip as bar colour) and PR30 (sweep legibility) are eyeballed.
local _, ns = ...
local IsSecret, ErrText, Round = ns.IsSecret, ns.ErrText, ns.Round
local Spike = {}
ns.Spike = Spike

local NOW, GAP, RULER_W, RULER_H, ICON, HORIZON = 56, 12, 264, 40, 20, 10
local PPS = RULER_W / HORIZON -- units per second along the ruler (constant divisor)
local N_ICONS = 8
local HALO = "Interface\\AddOns\\ForeverProbe\\Media\\halo64"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ICON_FALLBACK = 134400
local OUTLINE = {
    corner = "editmode-actionbar-highlight-nineslice-corner",
    top = "_editmode-actionbar-highlight-nineslice-edgetop",
    bottom = "_editmode-actionbar-highlight-nineslice-edgebottom",
    left = "!editmode-actionbar-highlight-nineslice-edgeleft",
    right = "!editmode-actionbar-highlight-nineslice-edgeright",
}

local root, ruler, nowCell, nowLine, marker, nowCd
local icons = {}
local regions = 0
local glide = true
local measuring = false
local nextCd = 0
local stats
local errors = {}

local function ResetStats()
    stats = { frames = 0, bodyMs = 0, bodyMax = 0, fpsShownN = 0, fpsShownSum = 0, fpsHiddenN = 0, fpsHiddenSum = 0,
        maxGap = 0, gapSum = 0, gapN = 0, buildMs = 0, buildKB = 0 }
end
ResetStats()

local function Tex(parent, layer, w, h)
    regions = regions + 1
    local t = parent:CreateTexture(nil, layer)
    if w then
        t:SetSize(w, h)
    end
    return t
end

local function Frame(parent, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    return f
end

local function Cooldown(parent)
    regions = regions + 1
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, parent, "CooldownFrameTemplate")
    if not ok or not cd then
        cd = CreateFrame("Cooldown", nil, parent)
    end
    cd:SetAllPoints(parent)
    return cd
end

local function Text(parent, size)
    regions = regions + 1
    local s = parent:CreateFontString(nil, "OVERLAY")
    s:SetFont(FONT, size, "OUTLINE")
    return s
end

local function Halo(parent, w, h)
    local t = Tex(parent, "BACKGROUND", w, h)
    local ok, err = pcall(t.SetTexture, t, HALO)
    if not ok then
        errors.haloTexture = ErrText(err)
    end
    local okS, errS = pcall(t.SetTextureSliceMargins, t, 16, 16, 16, 16)
    if not okS then
        errors.haloSlice = ErrText(errS)
    end
    t:SetVertexColor(0, 0, 0, 0.62)
    return t
end

local function Atlas(parent, name)
    local t = Tex(parent, "OVERLAY")
    local ok, err = pcall(t.SetAtlas, t, name, true)
    if not ok then
        errors["atlas_" .. name] = ErrText(err)
        t:SetColorTexture(0, 0.6, 1, 0.6)
    end
    return t
end

-- Icon file IDs for the session's spells, plain or the fallback.
local function Icons()
    local out = {}
    local list = (ns.role and ns.role.overlayList) or {}
    local f = C_Spell and C_Spell.GetSpellTexture
    for _, key in ipairs(list) do
        local id = ns.spell[key]
        if id and f then
            local ok, tex = pcall(f, id)
            if ok and not IsSecret(tex) and type(tex) == "number" then
                table.insert(out, tex)
            end
        end
    end
    if #out == 0 then
        out[1] = ICON_FALLBACK
    end
    return out
end

local function Build()
    collectgarbage("collect")
    local t0 = debugprofilestop()
    local kb0 = collectgarbage("count")
    regions = 0
    local texList = Icons()
    local function IconTex(i)
        return texList[(i - 1) % #texList + 1]
    end

    root = CreateFrame("Frame", "ForeverProbeSpike", UIParent)
    root:SetSize(NOW + GAP + RULER_W + ICON, NOW + 40)
    root:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    root:SetMovable(true)
    root:EnableMouse(true)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", root.StartMoving)
    root:SetScript("OnDragStop", root.StopMovingOrSizing)
    root:SetClampedToScreen(true)

    -- NOW cell ---------------------------------------------------------------------------------
    nowCell = Frame(root, NOW, NOW)
    nowCell:SetPoint("LEFT", root, "LEFT", 0, 12)
    local nowHalo = Halo(nowCell, NOW + 32, NOW + 32)
    nowHalo:SetPoint("CENTER")
    local nowBorder = Tex(nowCell, "BORDER")
    nowBorder:SetAllPoints()
    nowBorder:SetColorTexture(0.25, 0.25, 0.25, 1)
    local nowIcon = Tex(nowCell, "ARTWORK")
    nowIcon:SetPoint("TOPLEFT", 1, -1)
    nowIcon:SetPoint("BOTTOMRIGHT", -1, 1)
    nowIcon:SetTexture(IconTex(1))
    nowIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local e = Tex(nowCell, "OVERLAY")
        e:SetPoint(side[1])
        e:SetPoint(side[2])
        if side[3] then
            e:SetWidth(side[3])
        else
            e:SetHeight(side[4])
        end
        e:SetColorTexture(1, 0.8, 0.2, 0.9)
    end
    local veil = Tex(nowCell, "OVERLAY")
    veil:SetAllPoints(nowIcon)
    veil:SetColorTexture(0, 0, 0, 0.35)
    nowCd = Cooldown(nowCell)
    nowCd:SetHideCountdownNumbers(false)
    local eta = Text(nowCell, 14)
    eta:SetPoint("BOTTOM", nowCell, "BOTTOM", 0, 2)
    eta:SetText("1.2")
    for _, c in ipairs({ { "TOPLEFT", 4, 1 }, { "TOPLEFT", 1, 4 }, { "TOPRIGHT", 4, 1 }, { "TOPRIGHT", 1, 4 }, { "BOTTOMLEFT", 4, 1 }, { "BOTTOMLEFT", 1, 4 }, { "BOTTOMRIGHT", 4, 1 }, { "BOTTOMRIGHT", 1, 4 } }) do
        local b = Tex(nowCell, "OVERLAY", c[2], c[3])
        b:SetPoint(c[1], nowCell, c[1], 0, 0)
        b:SetColorTexture(1, 1, 1, 0.9)
    end
    marker = Tex(nowCell, "OVERLAY", 2, NOW)
    marker:SetPoint("LEFT", nowCell, "LEFT", 0, 0)
    marker:SetColorTexture(1, 0.8, 0.2, 1)

    -- NEXT ruler -------------------------------------------------------------------------------
    ruler = Frame(root, RULER_W + ICON, RULER_H)
    ruler:SetPoint("LEFT", nowCell, "RIGHT", GAP, 0)
    local haloSolid = Halo(ruler, RULER_W / 2 + 16, RULER_H + 32)
    haloSolid:SetPoint("LEFT", ruler, "LEFT", -16, 0)
    local haloFade = Halo(ruler, RULER_W / 2 + ICON + 16, RULER_H + 32)
    haloFade:SetPoint("LEFT", haloSolid, "RIGHT", 0, 0)
    if type(CreateColor) == "function" then
        local ok, err = pcall(haloFade.SetGradient, haloFade, "HORIZONTAL", CreateColor(0, 0, 0, 0.62), CreateColor(0, 0, 0, 0.08))
        if not ok then
            errors.haloGradient = ErrText(err)
        end
    else
        errors.haloGradient = "no CreateColor"
    end
    local baseline = Tex(ruler, "ARTWORK", RULER_W, 1)
    baseline:SetPoint("BOTTOMLEFT", ruler, "BOTTOMLEFT", 0, 6)
    baseline:SetColorTexture(1, 1, 1, 0.35)
    for i = 1, HORIZON do
        local big = (i % 5 == 0)
        local tick = Tex(ruler, "ARTWORK", 1, big and 6 or 3)
        tick:SetPoint("BOTTOM", baseline, "BOTTOMLEFT", i * PPS, 0)
        tick:SetColorTexture(1, 1, 1, big and 0.6 or 0.35)
    end
    nowLine = Tex(ruler, "ARTWORK", 1, RULER_H)
    nowLine:SetPoint("LEFT", ruler, "LEFT", 0, 0)
    nowLine:SetColorTexture(1, 1, 1, 0.8)
    local notch = Tex(ruler, "ARTWORK", 5, 3)
    notch:SetPoint("BOTTOM", baseline, "BOTTOMLEFT", 0, -3)
    notch:SetColorTexture(1, 1, 1, 0.8)
    local overflow = Tex(ruler, "ARTWORK", 24, 2)
    overflow:SetPoint("RIGHT", ruler, "RIGHT", -8, 10)
    overflow:SetColorTexture(1, 1, 1, 0.6)
    local arrow = Tex(ruler, "ARTWORK", 6, 6)
    arrow:SetPoint("LEFT", overflow, "RIGHT", 0, 0)
    arrow:SetColorTexture(1, 1, 1, 0.6)
    local badge = Text(ruler, 10)
    badge:SetPoint("TOPRIGHT", ruler, "TOPRIGHT", -2, -2)
    badge:SetText("+3")
    -- Config outline (Edit Mode pieces) around the ruler.
    local o = {}
    o.tl = Atlas(ruler, OUTLINE.corner)
    o.tl:SetPoint("TOPLEFT", ruler, "TOPLEFT", -6, 6)
    o.tr = Atlas(ruler, OUTLINE.corner)
    o.tr:SetPoint("TOPRIGHT", ruler, "TOPRIGHT", 6, 6)
    o.bl = Atlas(ruler, OUTLINE.corner)
    o.bl:SetPoint("BOTTOMLEFT", ruler, "BOTTOMLEFT", -6, -6)
    o.br = Atlas(ruler, OUTLINE.corner)
    o.br:SetPoint("BOTTOMRIGHT", ruler, "BOTTOMRIGHT", 6, -6)
    for _, k in ipairs({ "tl", "tr", "bl", "br" }) do
        o[k]:SetSize(16, 16)
    end
    o.top = Atlas(ruler, OUTLINE.top)
    o.top:SetPoint("TOPLEFT", o.tl, "TOPRIGHT")
    o.top:SetPoint("BOTTOMRIGHT", o.tr, "BOTTOMLEFT")
    o.bottom = Atlas(ruler, OUTLINE.bottom)
    o.bottom:SetPoint("TOPLEFT", o.bl, "TOPRIGHT")
    o.bottom:SetPoint("BOTTOMRIGHT", o.br, "BOTTOMLEFT")
    o.left = Atlas(ruler, OUTLINE.left)
    o.left:SetPoint("TOPLEFT", o.tl, "BOTTOMLEFT")
    o.left:SetPoint("BOTTOMRIGHT", o.bl, "TOPRIGHT")
    o.right = Atlas(ruler, OUTLINE.right)
    o.right:SetPoint("TOPLEFT", o.tr, "BOTTOMLEFT")
    o.right:SetPoint("BOTTOMRIGHT", o.br, "TOPRIGHT")

    -- Lane icons ---------------------------------------------------------------------------------
    for i = 1, N_ICONS do
        local f = Frame(ruler, ICON, ICON)
        f:SetPoint("CENTER", ruler, "LEFT", 0, 6)
        local border = Tex(f, "BORDER")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0.6, 0.6, 0.6, 1)
        local tex = Tex(f, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(IconTex(i))
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local stem = Tex(ruler, "ARTWORK", 1, 1)
        stem:SetPoint("TOP", f, "BOTTOM", 0, 0)
        stem:SetPoint("BOTTOM", baseline, "TOP", 0, 0)
        stem:SetColorTexture(1, 1, 1, 0.5)
        -- Window bar from the now line to the icon, coloured by the icon's own strip (PR29); shown for icons 1-3.
        local bar = Tex(ruler, "ARTWORK", 1, 2)
        bar:SetPoint("LEFT", nowLine, "RIGHT", 0, -8)
        bar:SetPoint("RIGHT", f, "LEFT", -1, -8)
        bar:SetTexture(IconTex(i))
        bar:SetTexCoord(0.10, 0.90, 0.45, 0.55)
        local cap = Tex(ruler, "OVERLAY", 2, 6)
        cap:SetPoint("RIGHT", f, "LEFT", 0, -8)
        cap:SetColorTexture(1, 1, 1, 0.9)
        if i > 3 then
            bar:Hide()
            cap:Hide()
        end
        local fade = Tex(f, "OVERLAY")
        fade:SetAllPoints()
        fade:SetColorTexture(0, 0, 0, i >= 6 and 0.45 or 0)
        local range = Tex(f, "OVERLAY", ICON, 2)
        range:SetPoint("TOP", f, "BOTTOM", 0, -1)
        range:SetColorTexture(0.9, 0.2, 0.2, i == 4 and 0.9 or 0)
        local cd = Cooldown(f)
        cd:SetHideCountdownNumbers(true)
        pcall(cd.SetDrawEdge, cd, true)
        pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.8)
        icons[i] = { f = f, bar = bar, cap = cap, cd = cd, phase = (i - 1) * (HORIZON / N_ICONS) }
    end

    -- PR29 row: the plain icon beside its 100 x 2 strip, for the four session spells.
    local y = -NOW - 6
    for i = 1, math.min(4, #texList) do
        local ic = Tex(root, "ARTWORK", 14, 14)
        ic:SetPoint("TOPLEFT", root, "TOPLEFT", (i - 1) * 90, y)
        ic:SetTexture(texList[i])
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local strip = Tex(root, "ARTWORK", 68, 2)
        strip:SetPoint("LEFT", ic, "RIGHT", 4, 0)
        strip:SetTexture(texList[i])
        strip:SetTexCoord(0.10, 0.90, 0.45, 0.55)
    end

    root:SetScript("OnUpdate", function()
        local t0b = debugprofilestop()
        local now = GetTime()
        if glide then
            for i = 1, N_ICONS do
                local ic = icons[i]
                local t = HORIZON - ((now + ic.phase) % HORIZON)
                ic.f:SetPoint("CENTER", ruler, "LEFT", t * PPS, 6)
            end
            marker:SetPoint("LEFT", nowCell, "LEFT", (math.sin(now * 2) * 0.5 + 0.5) * (NOW - 2), 0)
            local ic = icons[1]
            local br, fl = ic.bar:GetRight(), ic.f:GetLeft()
            if br and fl then
                local gap = math.abs((fl - 1) - br)
                if gap > stats.maxGap then
                    stats.maxGap = gap
                end
                stats.gapSum = stats.gapSum + gap
                stats.gapN = stats.gapN + 1
            end
        end
        if now >= nextCd then
            nextCd = now + 6
            icons[2].cd:SetCooldown(now, 6)
            nowCd:SetCooldown(now, 6)
        end
        local dt = debugprofilestop() - t0b
        stats.frames = stats.frames + 1
        stats.bodyMs = stats.bodyMs + dt
        if dt > stats.bodyMax then
            stats.bodyMax = dt
        end
    end)

    stats.buildMs = Round(debugprofilestop() - t0)
    stats.buildKB = Round(collectgarbage("count") - kb0)
    stats.regions = regions
end

-- FPS sampler: runs during a session, once a second, shown and hidden.
local sampler = CreateFrame("Frame")
sampler:Hide()
local sinceFps = 0
sampler:SetScript("OnUpdate", function(_, elapsed)
    sinceFps = sinceFps + elapsed
    if sinceFps < 1 then
        return
    end
    sinceFps = 0
    local fps = GetFramerate()
    if root and root:IsShown() then
        stats.fpsShownN = stats.fpsShownN + 1
        stats.fpsShownSum = stats.fpsShownSum + fps
    else
        stats.fpsHiddenN = stats.fpsHiddenN + 1
        stats.fpsHiddenSum = stats.fpsHiddenSum + fps
    end
end)

function Spike.SetMeasuring(on)
    measuring = on
    if on then
        sampler:Show()
    else
        sampler:Hide()
    end
end

function Spike.Show()
    if not root then
        local ok, err = pcall(Build)
        if not ok then
            errors.build = ErrText(err)
            ns.Print("spike failed to build: " .. ErrText(err))
            return
        end
    end
    root:Show()
    ns.Print(string.format("spike shown: %d regions, built in %s ms, %s KB. /fprobe spike stats when done.", stats.regions or 0, tostring(stats.buildMs), tostring(stats.buildKB)))
end

function Spike.Hide()
    if root then
        root:Hide()
    end
end

function Spike.SetScale(v)
    if root then
        root:SetScale(v)
    end
end

-- Prints the measurements and stores them in the session (SPIKE).
function Spike.Stats(quiet)
    local s = {
        regions = stats.regions or 0,
        frames = stats.frames,
        bodyAvgMs = stats.frames > 0 and Round(stats.bodyMs / stats.frames) or 0,
        bodyMaxMs = Round(stats.bodyMax),
        fpsShown = stats.fpsShownN > 0 and Round(stats.fpsShownSum / stats.fpsShownN) or 0,
        fpsShownSamples = stats.fpsShownN,
        fpsHidden = stats.fpsHiddenN > 0 and Round(stats.fpsHiddenSum / stats.fpsHiddenN) or 0,
        fpsHiddenSamples = stats.fpsHiddenN,
        maxGapPx = Round(stats.maxGap),
        avgGapPx = stats.gapN > 0 and Round(stats.gapSum / stats.gapN) or 0,
        buildMs = stats.buildMs,
        buildKB = stats.buildKB,
        glide = glide,
        scale = root and Round(root:GetScale()) or 1,
        shown = root ~= nil and root:IsShown(),
        errors = errors,
    }
    if ns.session then
        ns.session.SPIKE = s
    end
    if not quiet then
        ns.Print(string.format("spike: %d regions | OnUpdate avg %.3f ms, max %.3f ms over %d frames | fps shown %.1f (%d s) vs hidden %.1f (%d s) | bar gap max %.2f avg %.3f px | build %s ms %s KB",
            s.regions, s.bodyAvgMs, s.bodyMaxMs, s.frames, s.fpsShown, s.fpsShownSamples, s.fpsHidden, s.fpsHiddenSamples, s.maxGapPx, s.avgGapPx, tostring(s.buildMs), tostring(s.buildKB)))
        for k, v in pairs(errors) do
            ns.Print("  spike error " .. k .. ": " .. tostring(v))
        end
    end
    return s
end

function Spike.Status()
    if root then
        ns.Print(string.format("spike %s, %d regions, glide %s, measuring %s", root:IsShown() and "shown" or "hidden", stats.regions or 0, tostring(glide), tostring(measuring)))
    end
end

function Spike.Command(arg)
    if arg == "show" then
        Spike.Show()
    elseif arg == "hide" then
        Spike.Hide()
    elseif arg == "stats" then
        Spike.Stats(false)
    elseif arg == "glide" then
        glide = not glide
        ns.Print("spike glide " .. (glide and "ON" or "OFF (icons frozen; measures the static cost)"))
    elseif arg == "reset" then
        local r = stats.regions
        local b, k = stats.buildMs, stats.buildKB
        ResetStats()
        stats.regions, stats.buildMs, stats.buildKB = r, b, k
        ns.Print("spike stats reset")
    else
        ns.Print("usage: /fprobe spike show|hide|stats|glide|reset")
    end
end
