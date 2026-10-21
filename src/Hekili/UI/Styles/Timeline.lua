local _, ns = ...
-- UI/Styles/Timeline.lua: the timeline display style (display styles plan, Task 4). Record 1 in a "now" circle, record 2
-- in a "next" box, records 3.. on a lane (or a focus record in the circle, record 1 in the box and the rest on the lane:
-- `roles`, timeline focus plan Task 2) at laneX0 + max( 0, exact_time - GetTime() ) * pxPerSec (out of combat with
-- oocPinned, time - recs[ 1 ].time in place of exact_time - GetTime(); a second row for a pick within rowGap of the one
-- before, hidden past the horizon), ETA text, a resource-gate mark (the record's simulated resource
-- below its cost),
-- the ruler, and the alternatives Core fills for a style that asks (recs[ 1 .. 2 ].alts).
-- Its primitives (the prebuilt ETA labels, the cell's cropped texture and border, the veil, the
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
    return 0, 0, false, 1
end

local Registry = Hekili.Engine.Registry
local SO = ns.StyleOptions
local flashEvents = ns.UI.FlashEvents
local Button_OnMouseDown, Button_OnMouseUp = ns.UI.Button_OnMouseDown, ns.UI.Button_OnMouseUp
local LSM = LibStub( "LibSharedMedia-3.0", true )
local Glower = LibStub( "LibCustomGlow-1.0" )

local exp, floor, ceil, abs = math.exp, math.floor, math.ceil, math.abs
local mmax, mmin = math.max, math.min

local SLOTS = 10 -- Output's records per display
local MAX_TICKS = 31 -- the ruler's ticks for the horizon's maximum (30 s)
local SWIPE_EPS = 0.1 -- TDF Render.SWIPE_EPS: the sweep is re-set when its end moves this much (seconds)
local READY_EPS = 0.05 -- a wait this close to its time is due: its ETA hides and a flagged record 1 turns ready
local MOVE_EPS = 0.25 -- a lane icon is re-anchored when it moved this many pixels
local CROP = 0.08 -- TDF Render.NewCell's texture crop
local GOLD = { 1, 0.8, 0.1 } -- TDF Render.GOLD
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8X8" -- tinted with SetVertexColor: a mask does not apply to a SetColorTexture fill
local GOLD_RING, GOLD_FRAME = "Interface\\AddOns\\Hekili\\Textures\\GoldRing", "Interface\\AddOns\\Hekili\\Textures\\GoldFrame"
local GOLD_RING_IN, GOLD_FRAME_IN = 0.737, 0.691 -- the art's inner opening, a fraction of its width
local CYCLE, CANCEL = "Interface\\Addons\\Hekili\\Textures\\Cycle", "Interface\\Addons\\Hekili\\Textures\\Cancel"

-- TDF Render.ETA: labels in 0.1 s steps up to 10 s, built once ("" for none, "10+" past); whole seconds for "int".
local ETA, ETA_INT = {}, {}
for k = 0, 100 do
    ETA[ k ] = k == 0 and "" or string.format( "%.1f", k / 10 )
    ETA_INT[ k ] = k == 0 and "" or tostring( ceil( k / 10 ) )
end
ETA[ 101 ], ETA_INT[ 101 ] = "10+", "10+"

local function etaStep( t )
    if t <= READY_EPS then return 0 end
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
    d.gap = 12 -- now circle -> next box -> lane; replaces nextOffset (60 = 48 + 12), see Options.lua migrateDisplay
    d.eta = { enabled = true, font = "Friz Quadrata TT", size = 16, style = "THICKOUTLINE", color = { 1, 1, 1, 1 }, format = "0.1" } -- the font is STANDARD_TEXT_FONT's
    d.laneEta = { enabled = false, fontSize = 10 }
    d.sweep = { mode = "extend" }
    d.gate = { style = "veil", color = { 0, 0, 0, 0.55 } }
    d.ruler = { ticks = true, majorEvery = 5 }
    d.rulerStyle = "ruler" -- ruler (baseline and ticks), dots, lines (no baseline) or center (one line, no ticks)
    d.rulerColor = { 1, 1, 1 }
    d.rulerAlphaCombat = 0.5
    d.rulerAlphaOOC = 0.25
    d.laneAlpha = 0.95
    d.laneDim = 0.6
    d.glide = 0.08
    d.oocPinned = true -- out of combat the lane and ETAs on press-relative times (rec.time - recs[ 1 ].time), Task 2c
    d.oocTimers = false -- out of combat no sweeps and no ETAs (T.quiet)
    d.alts = { enabled = true, max = 2, size = 16, spacing = 2, zones = "both" }
    d.focusEnabled = true
    d.nowFallback = "empty" -- no focus record: the now circle stays empty (or "press": record 1 there, record 2 next)
    d.focusHorizon = 10 -- clamped to the lane's horizon where it is used
    d.focusColor = { GOLD[ 1 ], GOLD[ 2 ], GOLD[ 3 ], 1 } -- the focus ability is the press (ready)
    d.focusPendingColor = { 1, 1, 1, 0.35 } -- the focus ability still counting down
    d.focusReadyStyle = "ring" -- a ready focus ability: the ring in focusColor, a glow in it ("glow") or the Gold Ring art ("gold")
    d.nextFrame = "none" -- the next box's frame: the colour border, or the Gold Frame art over the icon ("gold")
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
        b.Border:AddMaskTexture( b.RingMask ) -- anchored to b in dress, with the Border's insets
        -- the focus ring: a disc over the border and under the round icon, so a ring of its thickness shows
        b.Ring = track( T, b:CreateTexture( nil, "BACKGROUND", nil, 1 ), L .. ".Ring" )
        b.FocusMask = b:CreateMaskTexture()
        b.FocusMask:SetTexture( CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE" )
        b.Ring:AddMaskTexture( b.FocusMask ) -- anchored to b in dress, with the Ring's insets
    end
    if i <= 2 then
        b.Cooldown = track( T, CreateFrame( "Cooldown", name .. "_Cooldown", b, "CooldownFrameTemplate" ), L .. ".Cooldown" )
        b.Cooldown:SetAllPoints( b )
        b.Cooldown:SetDrawBling( false )
        b.Cooldown:SetDrawEdge( false )
        b.Cooldown:SetHideCountdownNumbers( true ) -- the ETA text is the countdown
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
    if i == 1 then
        b.Veil:AddMaskTexture( b.Mask )
        -- focusReadyStyle "gold": fixed-colour ring art with a transparent centre, above the icon (sized in dress)
        b.Gold = top:CreateTexture( nil, "OVERLAY", nil, -1 )
        b.Gold:SetTexture( GOLD_RING )
        b.Gold:SetPoint( "CENTER", b, "CENTER", 0, 0 )
    end
    if i == 2 then -- nextFrame "gold": decoration above the icon, in place of the colour border
        b.Frame = top:CreateTexture( nil, "OVERLAY", nil, -1 )
        b.Frame:SetTexture( GOLD_FRAME )
        b.Frame:SetPoint( "CENTER", b, "CENTER", 0, 0 )
    end
    b.Marker = track( T, top:CreateTexture( nil, "OVERLAY" ), L .. ".Marker" )
    b.Marker:SetPoint( "BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1 )
    b.Icon = track( T, top:CreateTexture( nil, "OVERLAY" ), L .. ".Icon" )
    b.Eta = track( T, top:CreateFontString( name .. "_ETA", "OVERLAY" ), L .. ".Eta" )
    b.Keybinding = track( T, top:CreateFontString( name .. "_KB", "OVERLAY" ), L .. ".Keybinding" )
    b.Caption = track( T, top:CreateFontString( name .. "_Caption", "OVERLAY" ), L .. ".Caption" )
    if i <= 2 then -- either may draw the press record (roles)
        b.Targets = track( T, top:CreateFontString( name .. "_Targets", "OVERLAY" ), L .. ".Targets" )
        b.Highlight = track( T, top:CreateTexture( nil, "OVERLAY" ), L .. ".Highlight" )
        b.Highlight:SetTexture( "Interface\\Buttons\\ButtonHilight-Square" )
        b.Highlight:SetAllPoints( b )
        if i == 1 then b.Highlight:AddMaskTexture( b.Mask ) end -- the cast highlight is square art; round it on the circle
        b.Highlight:SetBlendMode( "ADD" )
    end
    if i <= 2 then -- the pause overlay, on the press record's cell
        b.Overlay = track( T, top:CreateTexture( nil, "OVERLAY" ), L .. ".Overlay" )
        b.Overlay:SetAllPoints( b )
        b.Overlay:SetAtlas( "creditsscreen-assets-buttons-pause" )
    end
    b.glowColor = { 0, 0, 0, 0 }
    b.glowing, b.readyGlow = false, false
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

-- The now circle's ready glow (focusReadyStyle "glow"), keyed apart from the press glow on the same cell.
local function readyGlow( b, on, c )
    if on == b.readyGlow then return end
    b.readyGlow = on
    if on then Glower.AutoCastGlow_Start( b, c, nil, nil, nil, nil, nil, "focus" )
    else Glower.AutoCastGlow_Stop( b, "focus" ) end
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
        b.Border:SetShown( tl.border.enabled and not ( b.Frame and tl.nextFrame == "gold" ) )
        b.Texture:Show()
        b.Top:Show()
        if b.Cooldown then b.Cooldown:Show() end
        b.Eta:SetShown( not T.quiet )
        b.Keybinding:Show()
        b.Caption:Show()
        if b.Targets then b.Targets:Show() end
    end
    T.base:SetShown( T.baseOn )
    for k = 1, MAX_TICKS do T.ticks[ k ]:SetShown( T.ticksOn and k - 1 <= tl.horizon ) end
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
        b.Ring:SetTexture( WHITE )
        b.Ring:SetVertexColor( fc[ 1 ], fc[ 2 ], fc[ 3 ], fc[ 4 ] )
        b.Ring:Hide()
        -- each mask on the cell frame with its texture's insets (a mask anchored to the texture it masks drew square)
        b.RingMask:ClearAllPoints()
        b.RingMask:SetPoint( "TOPLEFT", b, "TOPLEFT", -th, th )
        b.RingMask:SetPoint( "BOTTOMRIGHT", b, "BOTTOMRIGHT", th, -th )
        b.FocusMask:ClearAllPoints()
        b.FocusMask:SetPoint( "TOPLEFT", b, "TOPLEFT", -rt, rt )
        b.FocusMask:SetPoint( "BOTTOMRIGHT", b, "BOTTOMRIGHT", rt, -rt )
        b.Gold:SetSize( size * T.s / GOLD_RING_IN, size * T.s / GOLD_RING_IN ) -- its opening fits the cell
        b.Gold:Hide()
    end
    if b.Frame then
        b.Frame:SetSize( size * T.s / GOLD_FRAME_IN, size * T.s / GOLD_FRAME_IN )
        b.Frame:SetShown( tl.nextFrame == "gold" )
    end
    b.Border:SetTexture( WHITE )
    if tl.border.coloring == "custom" then
        local c = tl.border.color
        b.Border:SetVertexColor( c[ 1 ], c[ 2 ], c[ 3 ], c[ 4 ] )
    else
        local r, g, bl = RAID_CLASS_COLORS[ Registry.ClassFile() ]:GetRGB()
        b.Border:SetVertexColor( r, g, bl, 1 )
    end

    local gc = tl.gate.color
    b.Veil:SetTexture( WHITE )
    b.Veil:SetVertexColor( gc[ 1 ], gc[ 2 ], gc[ 3 ], gc[ 4 ] )
    b.Veil:Hide()
    b.Marker:SetColorTexture( gc[ 1 ], gc[ 2 ], gc[ 3 ], 1 )
    b.Marker:SetSize( mmax( 4, size / 5 ), mmax( 4, size / 5 ) )
    b.Marker:Hide()

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

--- Builds (or reuses) the cells, the lane's ruler and the layout on `d`, sizes `d` and returns the ten cells (the record
--- cell c draws is T.rec[ c ], see `roles`: config mode, the tooltip and the movers use them).
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
    local nextX = nowS + tl.gap
    -- the lane's t = 0 and the ruler's first mark; an icon is centred on its time, so half an icon on keeps the t = 0
    -- icon's left edge one gap past the next box
    T.laneX0 = nextX + nextS + tl.gap + iconS / 2
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
        elseif i == 2 then place( T, b, nextX, ( band - nextS ) / 2 ) end
        b:SetAlpha( i < 3 and 1 or tl.laneAlpha )
        if b.glowing then b:glowStop() end
        b.glowing = false
        readyGlow( b, false )
        b:Hide()
        b.Action, b.Ability, b.ExactTime, b.Key, b.Recommendation, b.cdAction = nil, nil, nil, nil, nil, nil
        T.inLane[ i ], T.want[ i ], T.x[ i ], T.row[ i ] = false, false, -1, 1
    end
    for i = 1, SLOTS do T.rec[ i ] = i end
    T.press, T.focused, T.ready, T.extend2 = 1, false, true, false
    T.has, T.paused = false, 0

    -- the ruler, from one pool (T.base, T.ticks): a baseline over the lane's rows and a tick a second (taller every
    -- majorEvery); dots or short lines a second and no baseline; or one line through the rows' middle and no ticks
    local style, rc, px = tl.rulerStyle, tl.rulerColor, tl.pxPerSec
    local baseY = T.rowTop1 - 7
    T.baseOn = style == "ruler" or style == "center"
    T.ticksOn = style ~= "center" and tl.ruler.ticks
    T.base:SetColorTexture( rc[ 1 ], rc[ 2 ], rc[ 3 ], 1 )
    T.base:SetSize( T.laneLength * s, s )
    -- center: through the middle of row 1 (the lane proper; row 2 is the stacked alternatives), whatever the row count
    place( T, T.base, T.laneX0, style == "center" and T.rowTop1 + ( iconS - 1 ) / 2 or baseY )
    for k = 1, MAX_TICKS do
        local t = T.ticks[ k ]
        local sec = k - 1
        if T.ticksOn and sec <= tl.horizon then
            local w, h = 1, 4 -- lines
            if style == "ruler" then h = sec % mmax( 1, tl.ruler.majorEvery ) == 0 and 6 or 3
            elseif style == "dots" then w, h = 2, 2 end
            t:SetColorTexture( rc[ 1 ], rc[ 2 ], rc[ 3 ], 1 )
            t:SetSize( w * s, h * s )
            place( T, t, T.laneX0 + sec * px, baseY - h )
        end
    end
    T.combat, T.quiet = nil, nil -- the ruler's alpha and the quiet state are set on the next Draw
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

-- Moves the lane's cells toward their times (TDF's glide) and hides those past the horizon. `now` is the clock the
-- cells' Key is on: GetTime(), or 0 when pinned (Keys press-relative).
local function moveLane( T, tl, now, elapsed )
    local px, glide, cells = tl.pxPerSec, tl.glide, T.cells
    local keep = glide > 0 and exp( -elapsed / glide ) or 0
    local laneEta, int = tl.laneEta.enabled and not T.quiet, tl.eta.format == "int"
    for i = 3, SLOTS do
        if T.want[ i ] then
            local b, target = cells[ i ], cells[ i ].Key
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

-- The zone rule, on a publish: T.rec[ c ] is the record cell c draws (0: none), T.press the cell drawing record 1
-- (every "key to press" affordance goes there), T.focused whether cell 1 draws a focus record, T.ready whether that is
-- record 1 and its time has come (the gold ring; else the pending one), T.extend2 whether cell 2's sweep is extended (to its record's time whenever it holds one). With focusEnabled a
-- record is flagged when `focus` is a tier (N >= 1, 1 highest); the focus record is, among the flagged records due
-- within the focus horizon (never past the lane's; record 1 always), the lowest tier, then the soonest. It alone takes
-- the now circle (else empty); one focus per display (user rule 2026-10-21): the next box takes the first record other
-- than it, flagged or not, and the lane every other record in order. nowFallback "press" keeps the earlier rule:
-- record 1 never counts, a focus record takes the now circle and record 1 the next box, else cell c draws record c.
-- The one-focus reading (user rule 2026-10-21): true, the best tier wins (a tie: the soonest); false, the queue's first
-- flagged record within the horizon, whatever its tier. Flip here only (tests/Game/harness/loop.lua mirrors it).
local FOCUS_BEST_TIER = true

local function flagged( r )
    local n = r.focus
    return type( n ) == "number" and n >= 1
end

local function roles( T, tl, recs, count, now )
    local map, f, press = T.rec, 0, tl.nowFallback == "press"
    if tl.focusEnabled then
        local h, best = mmin( tl.focusHorizon, tl.horizon ), 0
        for i = press and 2 or 1, count do
            local r = recs[ i ]
            if flagged( r ) and ( best == 0 or FOCUS_BEST_TIER and r.focus < best ) then -- strict: a tie keeps the sooner
                local t = r.exact_time and r.exact_time - now
                if T.pinned and t then t = r.time and r.time - T.pressTime end
                if i == 1 or t and t <= h then -- record 1 is the press: always within the horizon
                    f, best = i, r.focus
                    if best == 1 then break end
                end
            end
        end
    end
    if press then
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
        T.ready, T.readyAt, T.extend2 = true, nil, f ~= 0
        return
    end
    local n = 0
    -- the next box: record 2 when record 1 is the focus (none if it is the only one), else record 1 (none if no records);
    -- one focus, so other flagged records keep their place
    if count > 0 then n = f == 1 and ( count > 1 and 2 or 0 ) or 1 end
    map[ 1 ], map[ 2 ] = f, n
    local c = 3
    for i = 1, SLOTS do
        if i ~= f and i ~= n and c <= SLOTS then
            map[ c ] = i
            c = c + 1
        end
    end
    for k = c, SLOTS do map[ k ] = 0 end
    T.press = f == 1 and 1 or 2 -- record 1 is the focus record or else the next box's
    T.focused, T.extend2 = f ~= 0, n ~= 0
    -- a flagged record 1 is ready once its time has come (Tick flips it then); until then the pending look
    local r1 = recs[ 1 ]
    T.readyAt = f == 1 and ( T.pinned and r1.time and r1.time - T.pressTime or r1.exact_time ) or nil
    T.ready = f == 1 and now >= ( T.readyAt or now ) - READY_EPS
end

-- The now circle's focus look from T.ready: the ring's colour, the ready glow or the Gold Ring's colour and fade.
local function focusLook( T, tl, blank )
    local cells = T.cells
    local look = tl.focusReadyStyle
    local ring, glow = cells[ 1 ].Ring, T.focused and T.ready and look == "glow" and not blank
    local gold, art = T.focused and look == "gold", cells[ 1 ].Gold
    ring:SetShown( T.focused and not glow and not gold )
    readyGlow( cells[ 1 ], glow, tl.focusColor )
    art:SetShown( gold )
    if gold then
        art:SetDesaturated( not T.ready )
        art:SetAlpha( T.ready and 1 or 0.5 )
    end
    if T.focused then
        local fc = T.ready and tl.focusColor or tl.focusPendingColor
        ring:SetVertexColor( fc[ 1 ], fc[ 2 ], fc[ 3 ], fc[ 4 ] )
    end
end

local NONE = {} -- record 0: an empty cell

-- A publish: what each cell shows until the next one.
local function assign( d, T, tl, conf, out, now, combat )
    local cells, recs = T.cells, out.recs
    -- pinned: each cell's Key is press-relative (r.time - recs[ 1 ].time) on the clock 0, else exact_time on GetTime()
    local pinned = tl.oocPinned and not combat and out.count > 0 and recs[ 1 ].time ~= nil
    local reset = pinned ~= T.pinned -- the lane's glide positions are on the other clock
    T.pinned = pinned
    T.pressTime = pinned and recs[ 1 ].time or 0
    if pinned then now = 0 end
    T.clock = now
    roles( T, tl, recs, out.count, now )
    local blank = out.count == 0 or out.version == d.blankVersion
    focusLook( T, tl, blank )
    if blank then
        for i = 1, SLOTS do
            local b = cells[ i ]
            b:Hide()
            glowOff( b )
            b.Action, b.Ability, b.ExactTime, b.Key, b.cdAction = nil, nil, nil, nil, nil
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
        local b, r = cells[ c ], recs[ i ] or NONE
        b.Recommendation = recs[ i ]
        local action, exact = r.actionName, r.exact_time
        local key = exact
        if pinned and exact then key = r.time - T.pressTime end
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

            -- the gate: the resource at the start of the pick's wait below its cost
            local rt = r.resource_type
            local have = rt and r.resources[ rt ]
            local gated = have ~= nil and have < r.cost
            local style = tl.gate.style
            b.gated = gated
            b.Veil:SetShown( gated and style == "veil" )
            b.Marker:SetShown( gated and style == "marker" )
            b.Texture:SetAlpha( gated and style == "alpha" and 1 - tl.gate.color[ 4 ] or 1 )
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
                T.row[ c ] = ( tl.rows >= 2 and c > 3 and T.row[ c - 1 ] == 1 and ( key - cells[ c - 1 ].Key ) * px < tl.rowGap ) and 2 or 1
                if reset or not T.want[ c ] or not b.Action then T.at[ c ] = key end -- newly on the lane: no glide
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

        if not ability then b.cdAction = nil end -- no wait here: the sweep's held start goes
        b.Action = action
        b.Text = r.caption
        b.Indicator = r.indicator
        b.Keybind = r.keybind
        b.Ability = ability
        b.ExactTime = exact
        b.Key = key
    end
    moveLane( T, tl, now, 0 )
end

-- Cell `b`'s sweep (now and next): the spell's cooldown, stretched to its time in mode extend when `extend` (the now
-- circle, or the next box whenever it holds a record), re-set only when its start changed or its end moved (TDF
-- Render.SetSwipe). With nothing running the stretch starts when the ability's wait began (its first draw here), so
-- the swipe shows the remaining fraction of its countdown, not of the time since 0 or a stale GCD; once held, that
-- start wins over a cast's or a GCD's, so a long wait does not restart its swipe every GCD.
local function sweep( b, extend, tl, now )
    local cd, ability, mode = b.Cooldown, b.Ability, tl.sweep.mode
    local held = b.cdAction == b.Action and b.cdStart > 0 and now < b.cdEnd -- records are pooled: key on the action
    b.cdAction = b.Action
    local start, duration, enabled, modRate = 0, 0, 1, 1
    if mode ~= "off" then
        if ability.item then
            start, duration, enabled, modRate = GetItemCooldown( ability.item )
        else
            start, duration, enabled, modRate = GetSpellCooldown( ability.actionID )
        end
        if extend and mode == "extend" and b.ExactTime > mmax( now, start + duration ) then
            local gStart = GetSpellCooldown( Registry.GCD_SPELL )
            local cStart = ( select( 4, UnitCastingInfo( "player" ) ) or select( 4, UnitChannelInfo( "player" ) ) or 0 ) / 1000
            start = ( start > 0 and start ) or ( held and b.cdStart ) or ( cStart > 0 and cStart ) or ( gStart > 0 and gStart ) or now
            duration, modRate = b.ExactTime - start, 1 -- a wall-clock stretch: the spell's modRate would rescale it
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
    local paused = Hekili.Pause and T.press or 0 -- the cell showing the pause overlay, or 0
    if paused ~= T.paused then
        T.paused = paused
        T.cells[ 1 ].Overlay:SetShown( paused == 1 )
        T.cells[ 2 ].Overlay:SetShown( paused == 2 )
    end
    if not T.has then return end
    local tl = conf.timeline
    if T.pinned then now = T.clock end -- still between publishes
    if not T.ready and T.readyAt and now >= T.readyAt - READY_EPS then -- a flagged record 1's time has come
        T.ready = true
        focusLook( T, tl, false )
    end
    local int = tl.eta.format == "int"
    if tl.eta.enabled and not T.quiet then
        for i = 1, 2 do
            local b = T.cells[ i ]
            if b.Ability then showEta( b, b.Key - now, int ) end
        end
    end
    moveLane( T, tl, now, elapsed )
end

--- On a publish (d.NewRecommendations, which Draw consumes) or the 0.25 s pulse: the cells, then range, usability,
--- the delay's fade, glow, the target count, the sweeps and the flash from d.resolved.
function Timeline.Draw( d, conf, out, status )
    local T, st, tl = d.styleFrames.timeline, d.styleState, conf.timeline
    local now = GetTime()
    local combat = status.combat
    if combat ~= T.combat then -- the ruler's alpha, on a combat flip only
        T.combat = combat
        local a = combat and tl.rulerAlphaCombat or tl.rulerAlphaOOC
        T.base:SetAlpha( a )
        for k = 1, MAX_TICKS do T.ticks[ k ]:SetAlpha( a ) end
        if tl.oocPinned then d.NewRecommendations = true end -- re-assign on the other clock
    end
    local quiet = not combat and not tl.oocTimers -- out of combat: no sweeps, no ETAs
    if quiet ~= T.quiet then -- on a flip only: the ETAs hide or show, the sweeps clear or come back on this publish
        T.quiet = quiet
        for i = 1, SLOTS do
            local b = T.cells[ i ]
            b.Eta:SetShown( not quiet )
            if quiet and b.Cooldown then
                b.Cooldown:SetCooldown( 0, 0 )
                b.cdStart, b.cdEnd, b.cdAction = -1, -1, nil -- the held start goes: combat starts the sweep fresh
            end
        end
        d.NewRecommendations = true
    end
    local fresh = d.NewRecommendations
    if fresh then
        d.NewRecommendations = nil
        assign( d, T, tl, conf, out, now, combat )
    end
    if not T.has then return end
    if fresh and not quiet then -- the sweeps, as classic's on a publish
        for i = 1, 2 do
            if T.cells[ i ].Ability then sweep( T.cells[ i ], i == 1 or T.extend2, tl, now ) end
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
        readyGlow( b, false )
        b.Action, b.Ability, b.ExactTime, b.Key, b.cdAction = nil, nil, nil, nil, nil
    end
    for i = 1, SLOTS do T.want[ i ], T.inLane[ i ] = false, false end
    for _, w in ipairs( T.widgets ) do w:Hide() end
    T.cleared = true
    T.has, T.paused = false, 0
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

-- The zone (1 now, 2 next, 3 lane) of a shared builder's option key: a later zone's blocks carry its prefix (nextFont,
-- laneTextStyle), the queued toggles go to the next box, the rest (every zone's common settings) to the now circle.
local function zoneOf( k )
    if k == "queued" then return 2 end
    for z = 2, #ZONES do
        if k:match( "^" .. ZONES[ z ] .. "%u" ) then return z end
    end
    return 1
end

-- Zone z's part of every shared group, inline after the zone's layout fields (a group with nothing there is left out).
local function zoneGroups( args, z, id, conf )
    for n, g in ipairs( SHARED ) do
        local grp = SO[ g ]( "timeline", ZONES, 10 + n, id, conf )
        for k in pairs( grp.args ) do
            if zoneOf( k ) ~= z then grp.args[ k ] = nil end
        end
        if next( grp.args ) then
            grp.inline = true
            args[ g ] = grp
        end
    end
    return args
end

local function tab( name, desc, order, args )
    return { type = "group", name = name, desc = desc, order = order, args = args }
end

--- Four tabs, keyed so no key is a config key (option keys stay flat in displays[ id ].timeline; a nested group keyed
--- like a config subtable, eta or alts, holds that subtable's options): Now, Next and Lane hold the zone's layout then
--- its part of the shared groups; Timeline the lane's time axis, the ruler and the focus zone.
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

    local now = zoneGroups( {
        nowSize = optRange( "Size", "The diameter of the now circle (a focus ability coming up).", 16, 200, 1, 1 ),
        nowFallback = optSelect( "Without Focus", "Empty: the now circle holds only focus abilities (gold once ready to press) and the next box what to press. First Recommendation: the earlier layout, what to press in the now circle unless a focus ability is coming up.",
            { empty = "Empty", press = "First Recommendation" }, 4 ),
        focusPendingColor = { type = "color", name = "Pending Ring Color", desc = "The now circle's ring while a focus ability counts down (the Timeline tab's Ring Color once it is ready).", hasAlpha = true, order = 5, width = 1.49 },
        focusReadyStyle = optSelect( "Ready Look", "How the now circle shows a focus ability that is ready to press: the ring in the Timeline tab's Ring Color, or a glow in it, or the Gold Ring art (full colour when ready, grey and half faded while pending; fixed-colour art, so the ring colours do not apply to it).",
            { ring = "Ring", glow = "Glow", gold = "Gold Ring" }, 6 ),
        eta = section( "ETA", 2, etaFont ),
        sweep = section( "Sweep", 3, {
            mode = optSelect( "Cooldown Sweep", "Extend: the sweep runs until the pick should be used. Cooldown: the ability's own cooldown. Off: none.",
                { extend = "Extend", gcd = "Cooldown", off = "Off" }, 1 ),
        } ),
    }, 1, id, conf )

    local nextBox = zoneGroups( {
        nextSize = optRange( "Size", "The size of the next box (what to press now).", 16, 200, 1, 1 ),
        nextFrame = optSelect( "Frame", "None: the colour border (the Border options). Gold Frame: the gold frame art over the icon, in place of the border.",
            { none = "None", gold = "Gold Frame" }, 2.5 ),
        gap = optRange( "Gap", "The space between the now circle and the next box, and between the next box and the lane.", 0, 100, 1, 2 ),
        alts = section( "Alternatives", 3, {
            enabled = optToggle( "Show Alternatives", "Show what the rotation would pick instead if the gating resource came in lower or higher than expected.", 1 ),
            zones = optSelect( "Show On", "Which cells show their alternatives: the now circle (a focus ability, or the first recommendation when Without Focus is that), the next box, or both.", { now = "Now", next = "Next", both = "Both" }, 2 ),
            max = optRange( "Count", "How many alternatives each cell shows.", 1, 2, 1, 3 ),
            size = optRange( "Size", "The alternatives' icon size.", 8, 48, 1, 4 ),
            spacing = optRange( "Spacing", "The gap between the cell and its alternatives, and between them.", 0, 20, 1, 5 ),
        } ),
    }, 2, id, conf )

    local lane = zoneGroups( {
        laneIconSize = optRange( "Icon Size", "The size of the picks on the lane.", 8, 64, 1, 1 ),
        laneEta = section( "ETA", 2, {
            enabled = optToggle( "Show ETA", "Show the seconds under each pick on the lane.", 1 ),
            fontSize = optRange( "Size", "The lane ETA's font size.", 6, 32, 1, 2 ),
        } ),
        gate = section( "Resource Gate", 3, {
            style = optSelect( "Mark", "How a pick short of its resource is marked.", { veil = "Veil", alpha = "Fade", marker = "Corner Mark" }, 1 ),
            color = { type = "color", name = "Color", hasAlpha = true, order = 2, width = 1.49 },
        } ),
    }, 3, id, conf )

    local timeline = {
        sec_lane = section( "Lane", 1, {
            horizon = optRange( "Horizon", "Seconds the lane shows; later picks are hidden.", 2, 30, 1, 1 ),
            pxPerSec = optRange( "Pixels per Second", "How far apart picks one second apart sit.", 4, 100, 1, 2 ),
            direction = optSelect( "Direction", "Which way time runs.", { RIGHT = "Left to Right", LEFT = "Right to Left" }, 3 ),
            rows = optRange( "Rows", "With two rows, a pick close to the one before it hangs on the second row.", 1, 2, 1, 4 ),
            rowGap = optRange( "Row Gap", "Picks closer than this many pixels to the one before them take the second row.", 0, 100, 1, 5 ),
            laneHeight = optRange( "Height", "The lane's height.", 20, 200, 1, 6 ),
            laneAlpha = optRange( "Opacity", "The opacity of the picks on the lane.", 0, 1, 0.05, 7 ),
            laneDim = optRange( "Dimmed Opacity", "The opacity of the picks after one short of its resource (they may slip).", 0, 1, 0.05, 8 ),
            glide = optRange( "Glide", "Seconds a lane pick takes to settle on a new predicted time (0: jump).", 0, 1, 0.01, 9 ),
            oocPinned = optToggle( "Pin out of Combat", "Out of combat the lane and the countdowns hold still between updates, timed from the first recommendation; in combat they follow the clock.", 10 ),
            oocTimers = optToggle( "Timers Out of Combat", "Show the cooldown sweeps and the countdown numbers out of combat. Off: the now circle, the next box and the lane show no sweep and no numbers until combat starts.", 11 ),
        } ),
        sec_ruler = section( "Ruler", 2, {
            rulerStyle = optSelect( "Style", "Ruler: a baseline and a tick each second. Dots or Lines: a dot or a short line each second. Center: one line through the lane.",
                { ruler = "Ruler", dots = "Dots", lines = "Lines", center = "Center" }, 1 ),
            rulerColor = { type = "color", name = "Color", desc = "The ruler's color.", order = 2, width = 1.49 },
            rulerAlphaCombat = optRange( "Opacity in Combat", "The ruler's opacity in combat.", 0, 1, 0.05, 3 ),
            rulerAlphaOOC = optRange( "Opacity out of Combat", "The ruler's opacity out of combat.", 0, 1, 0.05, 4 ),
            ruler = section( "Ticks", 5, {
                ticks = optToggle( "Ticks", "A mark each second along the lane (not with the Center style).", 1 ),
                majorEvery = optRange( "Major Tick Every", "Seconds between the taller ticks (the Ruler style).", 1, 10, 1, 2 ),
            } ),
        } ),
        sec_focus = section( "Focus", 3, {
            focusEnabled = optToggle( "Focus Abilities", "An ability marked focus=N in the priority (a tier, 1 highest) takes the now circle with a countdown when it comes up within the focus horizon; the lowest tier wins, then the soonest.", 1 ),
            focusHorizon = optRange( "Focus Horizon", "Seconds ahead a focus ability takes the now circle (never past the lane's horizon).", 1, 30, 1, 2 ),
            focusColor = { type = "color", name = "Ring Color", desc = "The now circle's ring when the focus ability is ready to press.", hasAlpha = true, order = 3, width = 1.49 },
        } ),
    }

    return {
        tab_now = tab( "Now", "The now circle: a focus ability coming up.", 1, now ),
        tab_next = tab( "Next", "The next box and the alternatives.", 2, nextBox ),
        tab_lane = tab( "Lane", "The picks on the lane.", 3, lane ),
        tab_timeline = tab( "Timeline", "The lane's time axis, the ruler and the focus zone.", 4, timeline ),
    }
end

Timeline.api = Hekili.DisplayStyleAPI
Hekili:RegisterDisplayStyle( "timeline", Timeline )
