local _, ns = ...
-- UI/Styles/Timeline.lua: the timeline display style (display styles plan, Task 4). Record 1 in a "now" circle, record 2
-- in a "next" box, records 3.. on a lane (or a focus record in the circle, record 1 in the box and the rest on the lane:
-- `roles`, timeline focus plan Task 2) at ( exact_time - GetTime() ) * pxPerSec (a second row for a pick within
-- rowGap of the one before, hidden past the horizon), ETA text, a resource-gate mark (the record's simulated resource
-- below its cost), a cooldown-wait frame (the pick waits past the previous pick's busy time with the resource there),
-- the ruler, and the alternatives Core fills for a style that asks (recs[ 1 .. 2 ].alts).
-- Its primitives (the prebuilt ETA labels, the cell's cropped texture and border, the veil and the gold wait frame, the
-- sweep re-set only when it moved, the lane's glide) are ported from Taco Dog Forever (Render/Render.lua and
-- Views/TwoZones.lua, by Taco Dog Forever's authors). What it shares with classic (keybinds, captions, indicators, target
-- count, glow and cast highlight, flash, range and usability, the delay's fade) follows Hekili's classic renderer
-- (UI/Styles/Classic.lua, by Hekili's authors and maintainers). Its config is displays[ id ].timeline; its frames and
-- scratch live on d.styleFrames.timeline (d.styleState is shared by every style a display binds).

local Facade = ns.Facade
local CreateFrame = Facade.CreateFrame
local C_Item, C_Spell = Facade.C_Item, Facade.C_Spell
local GetTime = Facade.GetTime
local UnitCastingInfo, UnitChannelInfo = Facade.UnitCastingInfo, Facade.UnitChannelInfo
local IsCurrentItem, IsCurrentSpell = C_Item.IsCurrentItem, C_Spell.IsCurrentSpell
local GetItemCooldown = C_Item.GetItemCooldown

local GetSpellCooldown = function( spellID )
    local info = C_Spell.GetSpellCooldown( spellID )
    if info then return info.startTime, info.duration, info.isEnabled, info.modRate end
    return 0, 0, false, 0
end

local Registry = Hekili.Engine.Registry
local Status = Hekili.Engine.Output.status
local SO = ns.StyleOptions
local flashEvents = ns.UI.FlashEvents
local Button_OnMouseDown, Button_OnMouseUp = ns.UI.Button_OnMouseDown, ns.UI.Button_OnMouseUp
local LSM = LibStub( "LibSharedMedia-3.0", true )
local Glower = LibStub( "LibCustomGlow-1.0" )

local exp, floor, ceil, abs = math.exp, math.floor, math.ceil, math.abs
local mmax, mmin = math.max, math.min

local SLOTS = 10 -- Output's records per display
local MAX_TICKS = 31 -- the ruler's ticks for the horizon's maximum (30 s)
local LANE_GAP = 4 -- between the next box and the lane's t = 0
local SWIPE_EPS = 0.1 -- TDF Render.SWIPE_EPS: the sweep is re-set when its end moves this much (seconds)
local MOVE_EPS = 0.25 -- a lane icon is re-anchored when it moved this many pixels
local CROP = 0.08 -- TDF Render.NewCell's texture crop
local GOLD = { 1, 0.8, 0.1 } -- TDF Render.GOLD, the wait frame
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CYCLE, CANCEL = "Interface\\Addons\\Hekili\\Textures\\Cycle", "Interface\\Addons\\Hekili\\Textures\\Cancel"

-- TDF Render.ETA: labels in 0.1 s steps up to 10 s, built once ("" for none, "10+" past); whole seconds for "int".
local ETA, ETA_INT = {}, {}
for k = 0, 100 do
    ETA[ k ] = k == 0 and "" or string.format( "%.1f", k / 10 )
    ETA_INT[ k ] = k == 0 and "" or tostring( ceil( k / 10 ) )
end
ETA[ 101 ], ETA_INT[ 101 ] = "10+", "10+"

local function etaStep( t )
    if t <= 0.05 then return 0 end
    local k = floor( t * 10 + 0.5 )
    if k > 100 then return 101 end
    return k
end

-- Its icon zones for the shared option builders: cell 1, cell 2, the lane (the alternatives use the lane's text).
local ZONES = { "now", "next", "lane" }
local SHARED = { "border", "range", "glow", "flash", "captions", "indicators", "targets", "delays", "keybindings" }

-- Per zone (1 now, 2 next, 3 lane) the shared groups' field names (StyleOptions: a later zone prefixes its own).
local function zkey( z, field )
    if z == 1 then return field end
    return ZONES[ z ] .. field:sub( 1, 1 ):upper() .. field:sub( 2 )
end

local Timeline = {
    label = "Timeline",
    defaults = SO.defaults( SHARED, ZONES ),
    needs = { alts = true },
}

-- Per display (core asks on each alpha check): no alternative passes for a display that hides them.
local NO_NEEDS = {}
function Timeline.NeedsFor( _, conf )
    return conf.timeline.alts.enabled and Timeline.needs or NO_NEEDS
end

do
    local d = Timeline.defaults
    d.horizon = 10
    d.pxPerSec = 24
    d.laneHeight = 56
    d.laneIconSize = 20
    d.rows = 2
    d.rowGap = 24
    d.direction = "RIGHT"
    d.nowSize = 48
    d.nextSize = 48
    d.nextOffset = 60
    d.eta = { enabled = true, font = "Friz Quadrata TT", size = 16, style = "THICKOUTLINE", color = { 1, 1, 1, 1 }, format = "0.1" } -- the font is STANDARD_TEXT_FONT's
    d.laneEta = { enabled = false, fontSize = 10 }
    d.sweep = { mode = "extend" }
    d.gate = { style = "veil", color = { 0, 0, 0, 0.55 } }
    d.ruler = { ticks = true, majorEvery = 5 }
    d.laneAlpha = 0.95
    d.laneDim = 0.6
    d.glide = 0.08
    d.alts = { enabled = true, max = 2, size = 16, spacing = 2, zones = "both" }
    d.focusEnabled = true
    d.focusHorizon = 10 -- clamped to the lane's horizon where it is used
    d.focusColor = { GOLD[ 1 ], GOLD[ 2 ], GOLD[ 3 ], 1 }
end

local function track( T, region, label )
    local n = #T.widgets + 1
    T.widgets[ n ], T.labels[ n ] = region, label
    return region
end

-- Anchors `f` at ( x, y ) from the display's start corner (the left one, or the right one for direction LEFT).
local function place( T, f, x, y )
    f:ClearAllPoints()
    f:SetPoint( T.pt, T.d, T.pt, T.sx * x * T.s, -y * T.s )
end

local function newCell( d, T, i )
    local name = "Hekili_" .. d.id .. "_TL" .. i
    local L = "C" .. i
    local b = track( T, CreateFrame( "Button", name, d ), L )
    b.display, b.index = d.id, i
    b.Border = track( T, b:CreateTexture( nil, "BACKGROUND" ), L .. ".Border" )
    b.Texture = track( T, b:CreateTexture( nil, "ARTWORK" ), L .. ".Texture" )
    b.Texture:SetPoint( "TOPLEFT", b, "TOPLEFT", 0, 0 )
    b.Texture:SetPoint( "BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0 )
    b.Texture:SetTexCoord( CROP, 1 - CROP, CROP, 1 - CROP )
    if i == 1 then -- the circle: the texture, its ring and the sweep masked round
        b.Mask = b:CreateMaskTexture()
        b.Mask:SetTexture( CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE" )
        b.Mask:SetAllPoints( b )
        b.Texture:AddMaskTexture( b.Mask )
        b.RingMask = b:CreateMaskTexture()
        b.RingMask:SetTexture( CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE" )
        b.RingMask:SetAllPoints( b.Border )
        b.Border:AddMaskTexture( b.RingMask )
        b.Ring = track( T, b:CreateTexture( nil, "BACKGROUND", nil, 1 ), L .. ".Ring" ) -- the focus ring, over the border
        b.FocusMask = b:CreateMaskTexture()
        b.FocusMask:SetTexture( CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE" )
        b.FocusMask:SetAllPoints( b.Ring )
        b.Ring:AddMaskTexture( b.FocusMask )
    end
    if i <= 2 then
        b.Cooldown = track( T, CreateFrame( "Cooldown", name .. "_Cooldown", b, "CooldownFrameTemplate" ), L .. ".Cooldown" )
        b.Cooldown:SetAllPoints( b )
        b.Cooldown:SetDrawBling( false )
        b.Cooldown:SetDrawEdge( false )
        if i == 1 then
            b.Cooldown:SetSwipeTexture( CIRCLE )
            b.Cooldown:SetUseCircularEdge( true )
        end
        b.cdStart, b.cdEnd = -1, -1
        b.Alts = {}
        for k = 1, 2 do
            b.Alts[ k ] = track( T, b:CreateTexture( nil, "ARTWORK" ), L .. ".Alt" .. k )
            b.Alts[ k ]:SetTexCoord( CROP, 1 - CROP, CROP, 1 - CROP )
        end
    end
    -- TDF Render.NewWait's top layer: above the sweep, the veil, the gold frame, the marks and the texts
    local top = track( T, CreateFrame( "Frame", nil, b ), L .. ".Top" )
    b.Top = top
    top:SetAllPoints( b )
    b.Veil = track( T, top:CreateTexture( nil, "ARTWORK" ), L .. ".Veil" )
    b.Veil:SetAllPoints( b.Texture )
    if i == 1 then b.Veil:AddMaskTexture( b.Mask ) end
    b.Marker = track( T, top:CreateTexture( nil, "OVERLAY" ), L .. ".Marker" )
    b.Marker:SetPoint( "BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1 )
    b.Edges = {}
    for k = 1, 4 do
        local e = track( T, top:CreateTexture( nil, "OVERLAY" ), L .. ".Edge" .. k )
        e:SetColorTexture( GOLD[ 1 ], GOLD[ 2 ], GOLD[ 3 ], 1 )
        b.Edges[ k ] = e
    end
    b.Edges[ 1 ]:SetPoint( "TOPLEFT", b, "TOPLEFT", 0, 0 )
    b.Edges[ 1 ]:SetPoint( "TOPRIGHT", b, "TOPRIGHT", 0, 0 )
    b.Edges[ 1 ]:SetHeight( 2 )
    b.Edges[ 2 ]:SetPoint( "BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0 )
    b.Edges[ 2 ]:SetPoint( "BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0 )
    b.Edges[ 2 ]:SetHeight( 2 )
    b.Edges[ 3 ]:SetPoint( "TOPLEFT", b, "TOPLEFT", 0, 0 )
    b.Edges[ 3 ]:SetPoint( "BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0 )
    b.Edges[ 3 ]:SetWidth( 2 )
    b.Edges[ 4 ]:SetPoint( "TOPRIGHT", b, "TOPRIGHT", 0, 0 )
    b.Edges[ 4 ]:SetPoint( "BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0 )
    b.Edges[ 4 ]:SetWidth( 2 )
    b.Icon = track( T, top:CreateTexture( nil, "OVERLAY" ), L .. ".Icon" )
    b.Eta = track( T, top:CreateFontString( name .. "_ETA", "OVERLAY" ), L .. ".Eta" )
    b.Keybinding = track( T, top:CreateFontString( name .. "_KB", "OVERLAY" ), L .. ".Keybinding" )
    b.Caption = track( T, top:CreateFontString( name .. "_Caption", "OVERLAY" ), L .. ".Caption" )
    if i <= 2 then -- either may draw the press record (roles)
        b.Targets = track( T, top:CreateFontString( name .. "_Targets", "OVERLAY" ), L .. ".Targets" )
        b.Highlight = track( T, top:CreateTexture( nil, "OVERLAY" ), L .. ".Highlight" )
        b.Highlight:SetTexture( "Interface\\Buttons\\ButtonHilight-Square" )
        b.Highlight:SetAllPoints( b )
        b.Highlight:SetBlendMode( "ADD" )
    end
    if i == 1 then
        b.Overlay = track( T, top:CreateTexture( nil, "OVERLAY" ), L .. ".Overlay" )
        b.Overlay:SetAllPoints( b )
        b.Overlay:SetAtlas( "creditsscreen-assets-buttons-pause" )
    end
    b.glowColor = { 0, 0, 0, 0 }
    b.glowing = false
    b.etaK = -1

    b:SetScript( "OnMouseDown", Button_OnMouseDown )
    b:SetScript( "OnMouseUp", Button_OnMouseUp )
    b:SetScript( "OnEnter", function()
        if Hekili.Pause and T.has and b.Recommendation then Hekili:ShowDiagnosticTooltip( b.Recommendation ) end
    end )
    b:SetScript( "OnLeave", function() HekiliTooltip:Hide() end )
    Hekili:ProfileFrame( name, b )
    b:EnableMouse( false )
    b:SetMovable( false )
    return b
end

local function setFont( fs, font, size, style, color )
    fs:SetFont( LSM:Fetch( "font", font ), size, style )
    if color then fs:SetTextColor( color[ 1 ], color[ 2 ], color[ 3 ], color[ 4 ] ) end
    fs:SetWordWrap( false )
end

local function justifyH( anchor )
    return anchor:match( "RIGHT" ) and "RIGHT" or ( anchor:match( "LEFT" ) and "LEFT" or "CENTER" )
end

-- A cell's texts, marks and border from the config (Build only).
-- Shows what Clear hid and a drawn cell keeps up (its texture, texts, sweep and border) and the ruler: from Build, and
-- from the first publish after a Clear (core clears on every unsubscribe, e.g. when the display's alpha drops to 0).
local function reveal( T, tl )
    for i = 1, SLOTS do
        local b = T.cells[ i ]
        b.Border:SetShown( tl.border.enabled )
        b.Texture:Show()
        b.Top:Show()
        if b.Cooldown then b.Cooldown:Show() end
        b.Eta:Show()
        b.Keybinding:Show()
        b.Caption:Show()
        if b.Targets then b.Targets:Show() end
    end
    T.base:Show()
    for k = 1, MAX_TICKS do T.ticks[ k ]:SetShown( tl.ruler.ticks and k - 1 <= tl.horizon ) end
    T.cleared = false
end

local function dress( T, b, i, size, tl )
    local z = i < 3 and i or 3
    local kb, cap, ind, eta = tl.keybindings, tl.captions, tl.indicators, tl.eta
    b:SetSize( size * T.s, size * T.s )

    local th = tl.border.thickness or 1
    b.Border:ClearAllPoints()
    b.Border:SetPoint( "TOPLEFT", b, "TOPLEFT", -th, th )
    b.Border:SetPoint( "BOTTOMRIGHT", b, "BOTTOMRIGHT", th, -th )
    if b.Ring then
        local rt, fc = mmax( 2, th ), tl.focusColor
        b.Ring:ClearAllPoints()
        b.Ring:SetPoint( "TOPLEFT", b, "TOPLEFT", -rt, rt )
        b.Ring:SetPoint( "BOTTOMRIGHT", b, "BOTTOMRIGHT", rt, -rt )
        b.Ring:SetColorTexture( fc[ 1 ], fc[ 2 ], fc[ 3 ], fc[ 4 ] )
        b.Ring:Hide()
    end
    if tl.border.coloring == "custom" then
        local c = tl.border.color
        b.Border:SetColorTexture( c[ 1 ], c[ 2 ], c[ 3 ], c[ 4 ] )
    else
        local r, g, bl = RAID_CLASS_COLORS[ Registry.ClassFile() ]:GetRGB()
        b.Border:SetColorTexture( r, g, bl, 1 )
    end

    local gc = tl.gate.color
    b.Veil:SetColorTexture( gc[ 1 ], gc[ 2 ], gc[ 3 ], gc[ 4 ] )
    b.Veil:Hide()
    b.Marker:SetColorTexture( gc[ 1 ], gc[ 2 ], gc[ 3 ], 1 )
    b.Marker:SetSize( mmax( 4, size / 5 ), mmax( 4, size / 5 ) )
    b.Marker:Hide()
    for k = 1, 4 do b.Edges[ k ]:Hide() end

    local w, h = ind[ zkey( z, "width" ) ], ind[ zkey( z, "height" ) ]
    b.Icon:SetSize( w, h )
    local izoom = 1 - ( ind[ zkey( z, "zoom" ) ] or 0 ) / 200
    if ind[ zkey( z, "keepAspectRatio" ) ] and w ~= h then
        local big = mmax( w, h )
        local hw, hh = 0.5 * izoom * w / big, 0.5 * izoom * h / big
        b.Icon:SetTexCoord( 0.5 - hw, 0.5 + hw, 0.5 - hh, 0.5 + hh )
    else
        b.Icon:SetTexCoord( 0, 1, 0, 1 )
    end
    b.Icon:ClearAllPoints()
    b.Icon:SetPoint( ind.anchor, b, ind.anchor, ind.x, ind.y )
    b.Icon:Hide()

    local ca = cap[ zkey( z, "anchor" ) ]
    setFont( b.Caption, cap.font, cap.fontSize, cap.fontStyle, cap.color )
    b.Caption:ClearAllPoints()
    b.Caption:SetPoint( ca, b, ca, cap[ zkey( z, "x" ) ], cap[ zkey( z, "y" ) ] )
    b.Caption:SetJustifyH( cap[ zkey( z, "align" ) ] or "CENTER" )
    b.Caption:SetText( nil )

    setFont( b.Keybinding, kb[ zkey( z, "font" ) ], kb[ zkey( z, "fontSize" ) ], kb[ zkey( z, "fontStyle" ) ], kb[ zkey( z, "color" ) ] )
    b.Keybinding:ClearAllPoints()
    b.Keybinding:SetPoint( kb.anchor, b, kb.anchor, kb.x, kb.y )
    b.Keybinding:SetJustifyH( justifyH( kb.anchor ) )
    b.Keybinding:SetText( nil )

    setFont( b.Eta, eta.font, z == 3 and tl.laneEta.fontSize or eta.size, eta.style, eta.color )
    b.Eta:ClearAllPoints()
    if z == 3 then b.Eta:SetPoint( "TOP", b, "BOTTOM", 0, -1 ) else b.Eta:SetPoint( "BOTTOM", b, "BOTTOM", 0, 2 ) end
    b.Eta:SetText( "" )
    b.etaK = -1

    if b.Targets then
        local tg = tl.targets
        setFont( b.Targets, tg.font, tg.fontSize, tg.fontStyle, tg.color )
        b.Targets:ClearAllPoints()
        b.Targets:SetPoint( tg.anchor, b, tg.anchor, tg.x, tg.y )
        b.Targets:SetJustifyH( justifyH( tg.anchor ) )
        b.Targets:SetText( nil )
        b.Highlight:Hide()
    end
    if b.Overlay then b.Overlay:Hide() end

    if b.Alts then
        local a = tl.alts
        for k = 1, 2 do
            local t = b.Alts[ k ]
            t:SetSize( a.size * T.s, a.size * T.s )
            t:ClearAllPoints()
            t:SetPoint( "TOPLEFT", b, "BOTTOMLEFT", ( k - 1 ) * ( a.size + a.spacing ) * T.s, -a.spacing * T.s )
            t:Hide()
        end
    end
end

--- Builds (or reuses) the cells, the lane's ruler and the layout on `d`, sizes `d` and returns the ten cells (record i's
--- cell is button i: config mode, the tooltip and the movers use them).
function Timeline.Build( d, conf )
    local tl, st = conf.timeline, d.styleState
    local T = d.styleFrames.timeline
    if not T then
        T = { widgets = {}, labels = {}, cells = {}, ticks = {}, at = {}, x = {}, row = {}, inLane = {}, want = {}, dim = {}, rec = {} }
        d.styleFrames.timeline = T
        T.d = d
        for i = 1, SLOTS do T.cells[ i ] = newCell( d, T, i ) end
        T.base = track( T, d:CreateTexture( nil, "ARTWORK" ), "Ruler.Base" )
        for k = 1, MAX_TICKS do T.ticks[ k ] = track( T, d:CreateTexture( nil, "ARTWORK" ), "Ruler.Tick" .. k ) end
        T.flashOn = function() st.flashReady = true end
    end
    st.flashTimer = st.flashTimer or 0

    local s = Hekili:GetScale()
    local left = tl.direction == "LEFT"
    T.s, T.pt, T.sx = s, left and "TOPRIGHT" or "TOPLEFT", left and -1 or 1
    local nowS, nextS, laneH, iconS = tl.nowSize, tl.nextSize, tl.laneHeight, tl.laneIconSize
    local band = mmax( nowS, nextS, laneH )
    local extra = tl.alts.enabled and ( tl.alts.size + tl.alts.spacing ) or 0
    T.laneX0 = tl.nextOffset + nextS + LANE_GAP
    T.laneLength = tl.horizon * tl.pxPerSec
    T.laneTop = ( band - laneH ) / 2
    T.rowTop1 = T.laneTop + laneH - ( tl.rows >= 2 and 2 or 1 ) * iconS
    T.rowTop2 = T.rowTop1 + iconS
    d:SetSize( s * ( T.laneX0 + T.laneLength + iconS / 2 ), s * ( band + extra ) )

    for i = 1, SLOTS do
        local b = T.cells[ i ]
        local size = i == 1 and nowS or ( i == 2 and nextS or iconS )
        dress( T, b, i, size, tl )
        if i == 1 then place( T, b, 0, ( band - nowS ) / 2 )
        elseif i == 2 then place( T, b, tl.nextOffset, ( band - nextS ) / 2 ) end
        b:SetAlpha( i < 3 and 1 or tl.laneAlpha )
        if b.glowing then b:glowStop() end
        b.glowing = false
        b:Hide()
        b.Action, b.Ability, b.ExactTime, b.Recommendation = nil, nil, nil, nil
        T.inLane[ i ], T.want[ i ], T.x[ i ], T.row[ i ] = false, false, -1, 1
    end
    for i = 1, SLOTS do T.rec[ i ] = i end
    T.press, T.focused = 1, false
    T.has, T.paused = false, false

    -- the ruler: a baseline over the lane's rows and a tick a second (taller every majorEvery)
    local baseY = T.rowTop1 - 7
    T.base:SetColorTexture( 1, 1, 1, 0.5 )
    T.base:SetSize( T.laneLength * s, s )
    place( T, T.base, T.laneX0, baseY )
    for k = 1, MAX_TICKS do
        local t = T.ticks[ k ]
        local sec = k - 1
        if tl.ruler.ticks and sec <= tl.horizon then
            local major = sec % mmax( 1, tl.ruler.majorEvery ) == 0
            local h = major and 6 or 3
            t:SetColorTexture( 1, 1, 1, major and 0.8 or 0.5 )
            t:SetSize( s, h * s )
            place( T, t, T.laneX0 + sec * tl.pxPerSec, baseY - h )
        end
    end
    reveal( T, tl )

    if st.flashReady == nil then C_Timer.After( 3, T.flashOn ) end

    local out = Hekili.Engine.Output[ d.id ]
    if out and out.count > 0 then d.NewRecommendations = true end -- redraw what is published with the new layout

    return T.cells
end

-- The ETA of cell `b` for a wait of `t` seconds; its text is set only when the label changes.
local function showEta( b, t, int )
    local k = etaStep( t )
    if k ~= b.etaK then
        b.etaK = k
        b.Eta:SetText( int and ETA_INT[ k ] or ETA[ k ] )
    end
end

-- Moves the lane's cells toward their times (TDF's glide) and hides those past the horizon.
local function moveLane( T, tl, now, elapsed )
    local px, glide, cells = tl.pxPerSec, tl.glide, T.cells
    local keep = glide > 0 and exp( -elapsed / glide ) or 0
    local laneEta, int = tl.laneEta.enabled, tl.eta.format == "int"
    for i = 3, SLOTS do
        if T.want[ i ] then
            local b, target = cells[ i ], cells[ i ].ExactTime
            local at = target + ( T.at[ i ] - target ) * keep
            T.at[ i ] = at
            local t = at - now
            if t < 0 then t = 0 end
            local x = t * px
            local inLane = x <= T.laneLength
            if inLane ~= T.inLane[ i ] then
                T.inLane[ i ] = inLane
                b:SetShown( inLane )
            end
            if inLane and abs( x - T.x[ i ] ) >= MOVE_EPS then
                T.x[ i ] = x
                place( T, b, T.laneX0 + x - tl.laneIconSize / 2, T.row[ i ] == 2 and T.rowTop2 or T.rowTop1 )
            end
            if laneEta then showEta( b, target - now, int ) end
        end
    end
end

local function glowOn( b, g )
    local c = b.glowColor
    if g.coloring == "class" then
        c[ 1 ], c[ 2 ], c[ 3 ], c[ 4 ] = RAID_CLASS_COLORS[ Registry.ClassFile() ]:GetRGBA()
    elseif g.coloring == "custom" then
        c[ 1 ], c[ 2 ], c[ 3 ], c[ 4 ] = g.color[ 1 ], g.color[ 2 ], g.color[ 3 ], g.color[ 4 ]
    else
        c[ 1 ], c[ 2 ], c[ 3 ], c[ 4 ] = 0.95, 0.95, 0.32, 1
    end
    if g.mode == "default" then
        Glower.ButtonGlow_Start( b, c )
        b.glowStop = Glower.ButtonGlow_Stop
    elseif g.mode == "autocast" then
        Glower.AutoCastGlow_Start( b, c )
        b.glowStop = Glower.AutoCastGlow_Stop
    elseif g.mode == "pixel" then
        Glower.PixelGlow_Start( b, c )
        b.glowStop = Glower.PixelGlow_Stop
    end
    b.glowing = true
end

local function glowOff( b )
    if b.glowing then
        if b.glowStop then b:glowStop() end
        b.glowing = false
    end
end

local function highlight( b, tl, ability, exact )
    local id = ability and ( ability.item or ability.actionID )
    local isItem = ability and ability.item ~= nil
    b.Highlight:SetShown( tl.glow.highlight and id ~= nil and ( isItem and IsCurrentItem( id ) or IsCurrentSpell( id ) ) and exact > GetTime() or false )
end

-- The zone rule, on a publish: T.rec[ c ] is the record cell c draws, T.press the cell drawing record 1 (every "key to
-- press" affordance goes there), T.focused whether cell 1 draws a focus record. The focus record is the earliest record
-- 2.. flagged `focus` due within the focus horizon (never past the lane's): it takes the now circle, record 1 the next
-- box and the lane the rest in order. Else cell c draws record c.
local function roles( T, tl, recs, count, now )
    local map, f = T.rec, 0
    if tl.focusEnabled then
        local h = mmin( tl.focusHorizon, tl.horizon )
        for i = 2, count do
            local r = recs[ i ]
            if r.focus and r.exact_time and r.exact_time - now <= h then
                f = i
                break
            end
        end
    end
    if f == 0 then
        for c = 1, SLOTS do map[ c ] = c end
        T.press, T.focused = 1, false
    else
        map[ 1 ], map[ 2 ] = f, 1
        local c = 3
        for i = 2, SLOTS do
            if i ~= f then
                map[ c ] = i
                c = c + 1
            end
        end
        T.press, T.focused = 2, true
    end
end

-- A publish: what each cell shows until the next one.
local function assign( d, T, tl, conf, out, now )
    local cells, recs = T.cells, out.recs
    roles( T, tl, recs, out.count, now )
    cells[ 1 ].Ring:SetShown( T.focused )
    if out.count == 0 or out.version == d.blankVersion then
        for i = 1, SLOTS do
            local b = cells[ i ]
            b:Hide()
            glowOff( b )
            b.Action, b.Ability, b.ExactTime = nil, nil, nil
            T.want[ i ], T.inLane[ i ] = false, false
        end
        T.has = false
        return
    end
    T.has = true
    if T.cleared then reveal( T, tl ) end
    local suppress = tl.flash.enabled and tl.flash.suppress
    local kb, cap, ind, a = tl.keybindings, tl.captions, tl.indicators, tl.alts
    local px, abilities = tl.pxPerSec, Registry.Abilities()
    local gated1 -- the first pick short of its resource: the picks after it may slip (dimmed)

    for c = 1, SLOTS do
        local i = T.rec[ c ] -- record i, drawn by cell c
        local b, r = cells[ c ], recs[ i ]
        b.Recommendation = r
        local action, exact = r.actionName, r.exact_time
        local ability = action and r or nil
        if ability and ability.actionID < 0 and ability.actionID > -100 and action ~= "cancel_buff" or exact == nil then ability = nil end

        if ability then
            local queued = i > 1
            b.Texture:SetTexture( r.texture )
            local indicator = r.indicator
            if ind.enabled and indicator and ( not queued or ind.queued ) then
                if indicator == "cycle" then b.Icon:SetTexture( CYCLE ) end
                if indicator == "cancel" then b.Icon:SetTexture( CANCEL ) end
                b.Icon:Show()
            else
                b.Icon:Hide()
            end
            if ( r.caption and cap.enabled or abilities[ action ].caption ) and ( not queued or cap.queued ) then
                b.Caption:SetText( r.caption )
            else
                b.Caption:SetText( nil )
            end
            b.Keybinding:SetText( kb.enabled and ( not queued or kb.queued and c ~= 1 ) and r.keybind or nil ) -- none on a focus

            -- the gate: the resource at the start of the pick's wait below its cost; else a wait past the previous
            -- pick's busy time is a cooldown's (record 1's from the live delay, at Draw)
            local rt = r.resource_type
            local have = rt and r.resources[ rt ]
            local gated = have ~= nil and have < r.cost
            local style = tl.gate.style
            b.gated = gated
            b.Veil:SetShown( gated and style == "veil" )
            b.Marker:SetShown( gated and style == "marker" )
            b.Texture:SetAlpha( gated and style == "alpha" and 1 - tl.gate.color[ 4 ] or 1 )
            local wait = false
            if queued then
                local p = recs[ i - 1 ]
                wait = not gated and p.exact_time ~= nil and exact - ( p.exact_time + p.busy ) > 0.1
            end
            for k = 1, 4 do b.Edges[ k ]:SetShown( wait ) end
            if gated and not ( gated1 and gated1 < i ) then gated1 = i end -- cells 1-2 may draw records out of order

            if b.Alts then
                local show = a.enabled and ( a.zones == "both" or a.zones == ( c == 1 and "now" or "next" ) )
                local list = r.alts
                for k = 1, 2 do
                    local t = b.Alts[ k ]
                    if show and k <= list.n and k <= a.max then
                        t:SetTexture( list[ k ].texture )
                        t:Show()
                    else
                        t:Hide()
                    end
                end
            end

            if c >= 3 then
                -- the gap to the lane's previous pick (not r.since: the focus record between them is not on the lane)
                T.row[ c ] = ( tl.rows >= 2 and c > 3 and T.row[ c - 1 ] == 1 and ( exact - cells[ c - 1 ].ExactTime ) * px < tl.rowGap ) and 2 or 1
                if not T.want[ c ] or not b.Action then T.at[ c ] = exact end -- newly on the lane: no glide
                T.want[ c ] = not suppress
                T.x[ c ] = -1
                if suppress and T.inLane[ c ] then
                    T.inLane[ c ] = false
                    b:Hide()
                end
                b:SetAlpha( gated1 and gated1 < i and tl.laneDim or tl.laneAlpha )
            else
                b:SetShown( not suppress )
                if i == 1 then
                    highlight( b, tl, ability, exact )
                else
                    b.Highlight:Hide()
                    b.Targets:SetText( nil ) -- Draw sets the press cell's
                end
            end
            b.etaK = -1
        else
            b:Hide()
            glowOff( b )
            T.want[ c ], T.inLane[ c ] = false, false
            T.row[ c ] = 0 -- no row: the next pick has nothing here to dodge
        end

        b.Action = action
        b.Text = r.caption
        b.Indicator = r.indicator
        b.Keybind = r.keybind
        b.Ability = ability
        b.ExactTime = exact
    end
    moveLane( T, tl, now, 0 )
end

-- Cell `b`'s sweep (now and next): the spell's cooldown, record 1's stretched to its time in mode extend, re-set only
-- when its start changed or its end moved (TDF Render.SetSwipe).
local lastGcdStart = 0
local function sweep( b, i, tl, now )
    local cd, ability, mode = b.Cooldown, b.Ability, tl.sweep.mode
    local start, duration, enabled, modRate = 0, 0, 1, 1
    if mode ~= "off" then
        if ability.item then
            start, duration, enabled, modRate = GetItemCooldown( ability.item )
        else
            start, duration, enabled, modRate = GetSpellCooldown( ability.actionID )
        end
        if i == 1 and mode == "extend" and b.ExactTime > mmax( now, start + duration ) then
            local gStart = GetSpellCooldown( Registry.GCD_SPELL )
            if gStart > lastGcdStart then lastGcdStart = gStart end
            local cStart = ( select( 4, UnitCastingInfo( "player" ) ) or select( 4, UnitChannelInfo( "player" ) ) or 0 ) / 1000
            start = ( start > 0 and start ) or ( cStart > 0 and cStart ) or ( gStart > 0 and gStart ) or mmax( lastGcdStart, Status.combatStart )
            duration = b.ExactTime - start
        elseif enabled == 0 or enabled == false then
            start, duration, modRate = 0, 0, 1
        end
    end
    local finish = start + duration
    if start ~= b.cdStart or abs( finish - b.cdEnd ) >= SWIPE_EPS then
        b.cdStart, b.cdEnd = start, finish
        cd:SetCooldown( start, duration, modRate )
    end
end

--- Every frame: the pause overlay, the ETAs and the lane's motion (from exact_time and the clock; d.resolved is
--- refreshed only on drawing frames).
function Timeline.Tick( d, conf, out, now, elapsed )
    local T = d.styleFrames.timeline
    T.elapsed = elapsed
    local paused = Hekili.Pause and true or false
    if paused ~= T.paused then
        T.paused = paused
        T.cells[ 1 ].Overlay:SetShown( paused )
    end
    if not T.has then return end
    local tl = conf.timeline
    local int = tl.eta.format == "int"
    if tl.eta.enabled then
        for i = 1, 2 do
            local b = T.cells[ i ]
            if b.Ability then showEta( b, b.ExactTime - now, int ) end
        end
    end
    moveLane( T, tl, now, elapsed )
end

--- On a publish (d.NewRecommendations, which Draw consumes) or the 0.25 s pulse: the cells, then range, usability,
--- the delay's fade, glow, the target count, the sweeps and the flash from d.resolved.
function Timeline.Draw( d, conf, out, status )
    local T, st, tl = d.styleFrames.timeline, d.styleState, conf.timeline
    local now = GetTime()
    local fresh = d.NewRecommendations
    if fresh then
        d.NewRecommendations = nil
        assign( d, T, tl, conf, out, now )
    end
    if not T.has then return end
    if fresh then -- the sweeps, as classic's on a publish
        for i = 1, 2 do
            if T.cells[ i ].Ability then sweep( T.cells[ i ], i, tl, now ) end
        end
    end

    local range, delays, glow, press = tl.range, tl.delays, tl.glow, T.press
    for c = 1, 2 do
        local b, r = T.cells[ c ], d.resolved[ T.rec[ c ] ]
        local i = c == press and 1 or 2 -- record 1, or a queued one
        if b.Ability then
            local far = range.enabled and ( range.type == "melee" and not r.inMelee or range.type == "ability" and not r.inRange )
            local unusable, desat = not r.usable, false
            if i == 1 and r.desaturate then
                if delays.fade then unusable = true end
                if delays.desaturate then desat = true end
            end
            if far then b.Texture:SetVertexColor( 1, 0, 0, 1 )
            elseif unusable then b.Texture:SetVertexColor( 0.4, 0.4, 0.4, 1 )
            else b.Texture:SetVertexColor( 1, 1, 1, 1 ) end
            b.Texture:SetDesaturated( desat or far or false )

            if glow.enabled and ( i == 1 or glow.queued ) and r.glow then
                if not b.glowing then glowOn( b, glow ) end
            else
                glowOff( b )
            end
            if i == 1 then
                local wait = not b.gated and r.desaturate
                for k = 1, 4 do b.Edges[ k ]:SetShown( wait ) end
            end
        end
    end

    local b = T.cells[ press ]
    if tl.targets.enabled then
        local r = d.resolved[ 1 ]
        local detected, shown = r.detected, r.targets
        if r.single or shown > 1 then
            local color = detected < shown and "|cFFFF0000" or ( shown < detected and "|cFF00C0FF" or "" )
            b.Targets:SetText( color .. shown .. "|r" )
        else
            b.Targets:SetText( nil )
        end
    else
        b.Targets:SetText( nil )
    end

    ns.UI.FlashRecommendation( st, tl.flash, b.Action, T.elapsed or 0 )
end

function Timeline.OnGameEvent( d, conf, event, ... )
    local T, st, tl = d.styleFrames.timeline, d.styleState, conf.timeline
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local glow = tl.glow
        if glow.enabled then
            local show, id = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", ...
            for c = 1, 2 do
                local b = T.cells[ c ]
                local a = b.Ability
                if c ~= T.press and not glow.queued then -- glows only on the press cell
                elseif show and a and a.actionID == id and not b.glowing then glowOn( b, glow )
                elseif not show and b.glowing and ( not a or a.actionID == id ) then glowOff( b ) end
            end
        end
    elseif event == "CURRENT_SPELL_CAST_CHANGED" then
        local b = T.cells[ T.press ]
        highlight( b, tl, b.Ability, b.ExactTime or 0 )
    end
    if flashEvents[ event ] then
        st.flashReady = false
        C_Timer.After( 3, T.flashOn )
    end
end

function Timeline.UpdateKeybindings( d )
    local T = d.styleFrames.timeline
    local conf = Hekili.DB.profile.displays[ d.id ]
    local kb = conf.timeline.keybindings
    if not kb.enabled then return end
    for c, b in ipairs( T.cells ) do
        local a, i = b.Action, T.rec[ c ]
        if a then
            b.Keybind, b.KeybindFrom = Hekili:GetBindingForAction( a, conf, i )
            b.Keybinding:SetText( ( i == 1 or kb.queued and not ( c == 1 and T.focused ) ) and b.Keybind or nil )
        else
            b.Keybinding:SetText( nil )
        end
    end
end

--- Hides every frame and region it built (unsubscribe, Deactivate, a style switch).
function Timeline.Clear( d )
    local T = d.styleFrames.timeline
    if not T then return end
    for _, b in ipairs( T.cells ) do
        glowOff( b )
        b.Action, b.Ability, b.ExactTime = nil, nil, nil
    end
    for i = 1, SLOTS do T.want[ i ], T.inLane[ i ] = false, false end
    for _, w in ipairs( T.widgets ) do w:Hide() end
    T.cleared = true
    T.has, T.paused = false, false
end

--- The display frame itself: Build sizes it to the timeline.
function Timeline.Perimeter( d )
    return d, d, d, d
end

local function optRange( name, desc, min, max, step, order, width )
    return { type = "range", name = name, desc = desc, min = min, max = max, step = step, order = order, width = width or 1.49 }
end

local function optToggle( name, desc, order, width )
    return { type = "toggle", name = name, desc = desc, order = order, width = width or 1.49 }
end

local function optSelect( name, desc, values, order, width )
    return { type = "select", name = name, desc = desc, values = values, order = order, width = width or 1.49 }
end

local function section( name, order, args )
    return { type = "group", inline = true, name = name, order = order, args = args }
end

--- The Layout tab (its own keys, in inline sections whose keys are not config keys), then the shared groups in
--- classic's order. A nested group keyed like a config subtable (eta, alts) holds that subtable's options.
function Timeline.Options( id, conf )
    local P = ns.UI.DisplayOptionParts
    local fe = P.fontElements
    local etaFont = {
        enabled = optToggle( "Show ETA", "Show the seconds until the now and next picks should be used.", 1 ),
        format = optSelect( "Format", "Tenths of a second, or whole seconds.", { [ "0.1" ] = "0.1 s", int = "Whole seconds" }, 2 ),
        font = ns.tableCopy( fe.font ),
        style = ns.tableCopy( fe.fontStyle ),
        size = ns.tableCopy( fe.fontSize ),
        color = ns.tableCopy( fe.color ),
    }
    etaFont.font.order, etaFont.style.order, etaFont.size.order, etaFont.color.order = 3, 4, 5, 6

    local layout = {
        sec_now = section( "Now", 1, {
            nowSize = optRange( "Size", "The diameter of the now circle (the first recommendation).", 16, 200, 1, 1 ),
            eta = section( "ETA", 2, etaFont ),
            sweep = section( "Sweep", 3, {
                mode = optSelect( "Cooldown Sweep", "Extend: the sweep runs until the pick should be used. Cooldown: the ability's own cooldown. Off: none.",
                    { extend = "Extend", gcd = "Cooldown", off = "Off" }, 1 ),
            } ),
        } ),
        sec_next = section( "Next", 2, {
            nextSize = optRange( "Size", "The size of the next box (the second recommendation).", 16, 200, 1, 1 ),
            nextOffset = optRange( "Offset", "Where the next box starts, from the display's start edge.", 0, 300, 1, 2 ),
        } ),
        sec_lane = section( "Lane", 3, {
            horizon = optRange( "Horizon", "Seconds the lane shows; later picks are hidden.", 2, 30, 1, 1 ),
            pxPerSec = optRange( "Pixels per Second", "How far apart picks one second apart sit.", 4, 100, 1, 2 ),
            laneHeight = optRange( "Height", "The lane's height.", 20, 200, 1, 3 ),
            laneIconSize = optRange( "Icon Size", "The size of the picks on the lane.", 8, 64, 1, 4 ),
            rows = optRange( "Rows", "With two rows, a pick close to the one before it hangs on the second row.", 1, 2, 1, 5 ),
            rowGap = optRange( "Row Gap", "Picks closer than this many pixels to the one before them take the second row.", 0, 100, 1, 6 ),
            direction = optSelect( "Direction", "Which way time runs.", { RIGHT = "Left to Right", LEFT = "Right to Left" }, 7 ),
            laneAlpha = optRange( "Opacity", "The opacity of the picks on the lane.", 0, 1, 0.05, 8 ),
            laneDim = optRange( "Dimmed Opacity", "The opacity of the picks after one short of its resource (they may slip).", 0, 1, 0.05, 9 ),
            glide = optRange( "Glide", "Seconds a lane pick takes to settle on a new predicted time (0: jump).", 0, 1, 0.01, 10 ),
            laneEta = section( "ETA", 11, {
                enabled = optToggle( "Show ETA", "Show the seconds under each pick on the lane.", 1 ),
                fontSize = optRange( "Size", "The lane ETA's font size.", 6, 32, 1, 2 ),
            } ),
            ruler = section( "Ruler", 12, {
                ticks = optToggle( "Ticks", "A tick each second along the lane.", 1 ),
                majorEvery = optRange( "Major Tick Every", "Seconds between the taller ticks.", 1, 10, 1, 2 ),
            } ),
            gate = section( "Resource Gate", 13, {
                style = optSelect( "Mark", "How a pick short of its resource is marked.", { veil = "Veil", alpha = "Fade", marker = "Corner Mark" }, 1 ),
                color = { type = "color", name = "Color", hasAlpha = true, order = 2, width = 1.49 },
            } ),
        } ),
        sec_focus = section( "Focus", 5, {
            focusEnabled = optToggle( "Focus Abilities", "An ability marked focus=1 in the priority takes the now circle with a countdown when it comes up within the focus horizon; what to press now moves to the next box.", 1 ),
            focusHorizon = optRange( "Focus Horizon", "Seconds ahead a focus ability takes the now circle (never past the lane's horizon).", 1, 30, 1, 2 ),
            focusColor = { type = "color", name = "Ring Color", desc = "The now circle's ring while it shows a focus ability.", hasAlpha = true, order = 3, width = 1.49 },
        } ),
        sec_alts = section( "Alternatives", 4, {
            alts = section( "Alternative Picks", 1, {
                enabled = optToggle( "Show Alternatives", "Show what the rotation would pick instead if the gating resource came in lower or higher than expected.", 1 ),
                zones = optSelect( "Show On", "Which cells show their alternatives.", { now = "Now", next = "Next", both = "Both" }, 2 ),
                max = optRange( "Count", "How many alternatives each cell shows.", 1, 2, 1, 3 ),
                size = optRange( "Size", "The alternatives' icon size.", 8, 48, 1, 4 ),
                spacing = optRange( "Spacing", "The gap between the cell and its alternatives, and between them.", 0, 20, 1, 5 ),
            } ),
        } ),
    }

    return {
        layout = { type = "group", name = "Layout", desc = "The now circle, the next box, the lane and the alternatives.", order = 1, args = layout },
        keybindings = SO.keybindings( "timeline", ZONES, 7, id, conf ),
        border = SO.border( "timeline", ZONES, 4, id, conf ),
        range = SO.range( "timeline", ZONES, 5, id, conf ),
        glow = SO.glow( "timeline", ZONES, 6, id, conf ),
        flash = SO.flash( "timeline", ZONES, 8, id, conf ),
        captions = SO.captions( "timeline", ZONES, 9, id, conf ),
        targets = SO.targets( "timeline", ZONES, 10, id, conf ),
        delays = SO.delays( "timeline", ZONES, 11, id, conf ),
        indicators = SO.indicators( "timeline", ZONES, 11, id, conf ),
    }
end

Timeline.api = Hekili.DisplayStyleAPI
Hekili:RegisterDisplayStyle( "timeline", Timeline )
