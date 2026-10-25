-- ForeverProbe: preview candidate button frames / glows around a sample icon.
-- /atlasview            toggle the panel
-- /atlasview <spellID>  use that spell's icon as the sample (default Heroic Strike 285)
-- Each tile: a 45 px icon (square on the top row, circle-masked on the bottom row), the atlas drawn around it at
-- Blizzard's own ratio for a 45 px action button, and its name. Animated ones animate.

local SAMPLE = 285
local TILE, ICON, COLS = 150, 45, 5
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- { atlas, drawn size for a 45 px button, how }  how: "frame" (plain), "fx" (ADD, masked round, rotating),
-- "ants" (30-frame flipbook 6x5 over 1 s), "procloop" (flipbook, 6x5 rows/cols guess; stops if it looks wrong)
local CANDIDATES = {
    { "UI-HUD-RotationHelper-Active",       64, "frame" },
    { "UI-HUD-RotationHelper-Inactive",     64, "frame" },
    { "UI-HUD-RotationHelper-Active-FX",    80, "fx" },
    { "UI-HUD-RotationHelper-Highlight-2x", 90, "frame" },
    { "UI-HUD-RotationHelper-ProcAltGlow",  49, "frame" },
    { "rotationhelper_ants_flipbook",       66, "ants" },
    { "UI-HUD-ActionBar-Proc-Loop-Flipbook", 66, "procloop" },
    { "spellbook-rotationhelper-iconframe", 66, "frame" },
    { "ZoneAbility-Generic-IconBorder",     63, "frame" },
    { "generic-extrabutton",               256, "frame" },
    { "stormyellow-extrabutton",           256, "frame" },
    { "nerubian-extrabutton",              256, "frame" },
}

local panel

local function tile( parent, idx, spec, round )
    local atlas, size, how = spec[ 1 ], spec[ 2 ], spec[ 3 ]
    local f = CreateFrame( "Frame", nil, parent )
    f:SetSize( TILE, TILE )
    local col, row = ( idx - 1 ) % COLS, math.floor( ( idx - 1 ) / COLS )
    f:SetPoint( "TOPLEFT", parent, "TOPLEFT", 10 + col * TILE, -30 - row * TILE )

    local icon = f:CreateTexture( nil, "ARTWORK" )
    icon:SetSize( ICON, ICON )
    icon:SetPoint( "CENTER", f, "CENTER", 0, 8 )
    icon:SetTexture( C_Spell.GetSpellTexture( SAMPLE ) or 134400 )
    icon:SetTexCoord( 0.07, 0.93, 0.07, 0.93 )
    if round then
        local m = f:CreateMaskTexture()
        m:SetTexture( CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE" )
        m:SetAllPoints( icon )
        icon:AddMaskTexture( m )
    end

    local art = f:CreateTexture( nil, "OVERLAY" )
    art:SetPoint( "CENTER", icon, "CENTER" )
    local ok = C_Texture.GetAtlasInfo( atlas ) ~= nil
    art:SetAtlas( atlas, false )
    if size > TILE - 10 then size = TILE - 10 end -- the 256 px extra-button frames, shrunk to fit
    art:SetSize( size, size )

    if how == "fx" then
        art:SetBlendMode( "ADD" )
        art:SetAlpha( 0.6 )
        local m = f:CreateMaskTexture()
        m:SetAtlas( "UI-HUD-RotationHelper-Active-FX-Mask", false )
        m:SetSize( 64, 64 )
        m:SetPoint( "CENTER", icon, "CENTER" )
        art:AddMaskTexture( m )
        local ag = art:CreateAnimationGroup()
        ag:SetLooping( "REPEAT" )
        local r = ag:CreateAnimation( "Rotation" )
        r:SetDuration( 3 ); r:SetDegrees( -360 ); r:SetOrigin( "CENTER", 0, 0 )
        ag:Play()
    elseif how == "ants" or how == "procloop" then
        local ag = art:CreateAnimationGroup()
        ag:SetLooping( "REPEAT" )
        local fb = ag:CreateAnimation( "FlipBook" )
        fb:SetDuration( 1 ); fb:SetFlipBookRows( 6 ); fb:SetFlipBookColumns( 5 ); fb:SetFlipBookFrames( 30 )
        ag:Play()
    end

    local label = f:CreateFontString( nil, "OVERLAY", "GameFontHighlightSmall" )
    label:SetPoint( "BOTTOM", f, "BOTTOM", 0, 6 )
    label:SetWidth( TILE - 6 )
    label:SetWordWrap( true )
    label:SetText( ( ok and "" or "|cffff0000(missing)|r " ) .. atlas .. " " .. size )
    return f
end

local function build()
    local n = #CANDIDATES
    local rows = math.ceil( n / COLS )
    panel = CreateFrame( "Frame", "ForeverProbeAtlasView", UIParent, "BackdropTemplate" )
    panel:SetSize( 20 + COLS * TILE, 40 + 2 * rows * TILE )
    panel:SetPoint( "CENTER" )
    panel:SetBackdrop( { bgFile = "Interface\\Buttons\\WHITE8X8" } )
    panel:SetBackdropColor( 0.05, 0.05, 0.05, 0.9 )
    panel:SetMovable( true ); panel:EnableMouse( true )
    panel:RegisterForDrag( "LeftButton" )
    panel:SetScript( "OnDragStart", panel.StartMoving )
    panel:SetScript( "OnDragStop", panel.StopMovingOrSizing )
    panel:SetFrameStrata( "DIALOG" )
    local title = panel:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
    title:SetPoint( "TOP", 0, -8 )
    title:SetText( "Atlas preview: square icons (top block), round icons (bottom block). /atlasview to close." )
    local close = CreateFrame( "Button", nil, panel, "UIPanelCloseButton" )
    close:SetPoint( "TOPRIGHT" )
    for i, spec in ipairs( CANDIDATES ) do
        tile( panel, i, spec, false )
        tile( panel, i + rows * COLS, spec, true )
    end
end

SLASH_ATLASVIEW1 = "/atlasview"
SlashCmdList.ATLASVIEW = function( msg )
    local id = tonumber( msg )
    if id then
        SAMPLE = id
        if panel then panel:Hide(); panel = nil end
    end
    if not panel then build(); panel:Show()
    else panel:SetShown( not panel:IsShown() ) end
end
