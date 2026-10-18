local _, ns = ...
-- UI/Styles/Classic.lua: the classic display style, Hekili's stock renderer (one icon button per recommendation:
-- texture, caption, keybind, indicator, glow, flash, target count, delay, range/usable/desaturate, cooldown spiral),
-- moved verbatim out of UI/UI.lua's CreateDisplay and CreateButton behind the style interface (display styles plan,
-- Task 1). Hekili code by Hekili's authors and maintainers. Its per-display scratch lives on d.styleState, its buttons
-- on d.styleFrames.classic (Build returns them; core stores them as d.Buttons = ns.UI.Buttons[ d.id ] while classic is
-- bound). Its option tabs (Options) moved out of Options/Options.lua's newDisplayOption (Task 2).

local Facade = ns.Facade
local CreateFrame = Facade.CreateFrame
local C_Item, C_Spell = Facade.C_Item, Facade.C_Spell
local C_SpellActivationOverlay = Facade.C_SpellActivationOverlay
local GetTime, InCombatLockdown, UnitCanAttack = Facade.GetTime, Facade.InCombatLockdown, Facade.UnitCanAttack
local UnitCastingInfo, UnitChannelInfo = Facade.UnitCastingInfo, Facade.UnitChannelInfo

local Registry = Hekili.Engine.Registry
local Status = Hekili.Engine.Output.status

local frameStratas = ns.FrameStratas
local getInverseDirection = ns.getInverseDirection

local IsCurrentItem = C_Item.IsCurrentItem
local IsUsableItem = C_Item.IsUsableItem
local IsCurrentSpell = C_Spell.IsCurrentSpell
local GetItemCooldown = C_Item.GetItemCooldown
local IsUsableSpell = C_Spell.IsSpellUsable
local IsSpellOverlayed = C_SpellActivationOverlay.IsSpellOverlayed

local GetSpellCooldown = function( spellID )
    local spellCooldownInfo = Facade.C_Spell.GetSpellCooldown( spellID )
    if spellCooldownInfo then
        return spellCooldownInfo.startTime, spellCooldownInfo.duration, spellCooldownInfo.isEnabled, spellCooldownInfo.modRate
    end
    return 0, 0, false, 0
end

local format = string.format

local dPool = ns.UI.Displays
local flashEvents = ns.UI.FlashEvents
local Button_OnMouseDown, Button_OnMouseUp = ns.UI.Button_OnMouseDown, ns.UI.Button_OnMouseUp
local pulseRange = TOOLTIP_UPDATE_TIME

local LRC = LibStub( "LibRangeCheck-3.0" )
local LSF = SpellFlashCore
local catchFlash, lastFramesFlashed = nil, {}

if LSF then
    hooksecurefunc( LSF, "FlashFrame", function( frame )
        local flash = frame and frame.SpellFlashCoreAddonFlashFrame

        -- We need to know what flashed so we can force it to stop flashing when the recommendation changes.
        if catchFlash and flash then
            lastFramesFlashed[ flash ] = 1
        end
    end )
end

local LSR = LibStub("SpellRange-1.0")
local lastGcdStart = 0
local Glower = LibStub("LibCustomGlow-1.0")

-- Classic's config is its own subtable, displays[ id ].classic (Task 2b; moved out of Options.lua's displayTemplate).
local Classic = {
    label = "Classic",
    defaults = {
        primaryWidth = 50,
        primaryHeight = 50,

        keepAspectRatio = true,
        zoom = 30,

        queue = {
            anchor = 'RIGHT',
            direction = 'RIGHT',
            style = 'RIGHT',
            alignment = 'CENTER',

            width = 50,
            height = 50,

            -- offset = 5, -- deprecated.
            offsetX = 5,
            offsetY = 0,
            spacing = 5,

            elvuiCooldown = false,

            --[[ font = ElvUI and 'PT Sans Narrow' or 'Arial Narrow',
            fontSize = 12,
            fontStyle = "OUTLINE" ]]
        },

        border = {
            enabled = true,
            thickness = 1,
            fit = false,
            coloring = 'custom',
            color = { 0, 0, 0, 1 },
        },

        range = {
            enabled = true,
            type = 'ability',
        },

        glow = {
            enabled = false,
            queued = false,
            mode = "autocast",
            coloring = "default",
            color = { 0.95, 0.95, 0.32, 1 },

            highlight = true
        },

        flash = {
            enabled = false,
            color = { 255/255, 215/255, 0, 1 }, -- gold.
            blink = false,
            suppress = false,
            combat = false,

            size = 240,
            brightness = 100,
            speed = 0.4,

            fixedSize = false,
            fixedBrightness = false
        },

        captions = {
            enabled = false,
            queued = false,

            align = "CENTER",
            anchor = "BOTTOM",
            x = 0,
            y = 0,

            font = ElvUI and 'PT Sans Narrow' or 'Arial Narrow',
            fontSize = 12,
            fontStyle = "OUTLINE",

            color = { 1, 1, 1, 1 },
        },

        indicators = {
            enabled = true,
            queued = true,

            anchor = "RIGHT",
            x = 0,
            y = 0,

            width = 20,
            height = 20,
            zoom = 30,
            keepAspectRatio = true,
        },

        targets = {
            enabled = true,

            font = ElvUI and 'PT Sans Narrow' or 'Arial Narrow',
            fontSize = 12,
            fontStyle = "OUTLINE",

            anchor = "BOTTOMRIGHT",
            x = 0,
            y = 0,

            color = { 1, 1, 1, 1 },
        },

        delays = {
            type = "__NA",
            fade = false,
            extend = true,
            elvuiCooldowns = false,

            font = ElvUI and 'PT Sans Narrow' or 'Arial Narrow',
            fontSize = 12,
            fontStyle = "OUTLINE",

            anchor = "TOPLEFT",
            x = 0,
            y = 0,

            color = { 1, 1, 1, 1 },
        },

        keybindings = {
            enabled = true,
            queued = true,

            font = ElvUI and "PT Sans Narrow" or "Arial Narrow",
            fontSize = 12,
            fontStyle = "OUTLINE",

            lowercase = false,

            separateQueueStyle = false,

            queuedFont = ElvUI and "PT Sans Narrow" or "Arial Narrow",
            queuedFontSize = 12,
            queuedFontStyle = "OUTLINE",

            queuedLowercase = false,

            anchor = "TOPRIGHT",
            x = 1,
            y = -1,

            cPortOverride = true,
            cPortZoom = 0.6,

            color = { 1, 1, 1, 1 },
            queuedColor = { 1, 1, 1, 1 },
        },
    },
}

local LSM = LibStub("LibSharedMedia-3.0", true)

local function CreateButton( dispID, id )
    local self = Hekili
    local d = dPool[ dispID ]
    if not d then
        return
    end
    local st = d.styleState

    local conf = rawget( self.DB.profile.displays, dispID )
    if not conf then return end

    local bName = "Hekili_" .. dispID .. "_B" .. id
    local b = d.styleFrames.classic[ id ] or CreateFrame( "Button", bName, d )

    Hekili:ProfileFrame( bName, b )

    b.display = dispID
    b.index = id

    local scale = self:GetScale()

    local borderOffset = 0

    if conf.classic.border.enabled and conf.classic.border.fit then
        borderOffset = 2
    end

    if id == 1 then
        b:SetHeight( scale * ( ( conf.classic.primaryHeight or 50 ) - borderOffset ) )
        b:SetWidth( scale * ( ( conf.classic.primaryWidth or 50 ) - borderOffset  ) )
    else
        b:SetHeight( scale * ( ( conf.classic.queue.height or 30 ) - borderOffset  ) )
        b:SetWidth( scale * ( ( conf.classic.queue.width or 50 ) - borderOffset  ) )
    end

    -- Texture
    if not b.Texture then
        b.Texture = b:CreateTexture( nil, "ARTWORK" )
        b.Texture:SetTexture( "Interface\\ICONS\\Spell_Nature_BloodLust" )
        b.Texture:SetAllPoints( b )
    end

    b.texCoords = b.texCoords or {}
    local zoom = 1 - ( ( conf.classic.zoom or 0) / 200 )

    if conf.classic.keepAspectRatio then
        local biggest = id == 1 and max( conf.classic.primaryHeight, conf.classic.primaryWidth ) or max( conf.classic.queue.height, conf.classic.queue.width )
        local height = 0.5 * zoom * ( id == 1 and conf.classic.primaryHeight or conf.classic.queue.height ) / biggest
        local width = 0.5 * zoom * ( id == 1 and conf.classic.primaryWidth or conf.classic.queue.width ) / biggest

        b.texCoords[1] = 0.5 - width
        b.texCoords[2] = 0.5 + width
        b.texCoords[3] = 0.5 - height
        b.texCoords[4] = 0.5 + height

        b.Texture:SetTexCoord( unpack( b.texCoords ) )
    else
        local zoom = zoom / 2

        b.texCoords[1] = 0.5 - zoom
        b.texCoords[2] = 0.5 + zoom
        b.texCoords[3] = 0.5 - zoom
        b.texCoords[4] = 0.5 + zoom

        b.Texture:SetTexCoord( unpack( b.texCoords ) )
    end


    -- Initialize glow/noop if button has not yet been glowed.
    b.glowing = b.glowing or false
    b.glowStop = b.glowStop or function () end


    -- Indicator Icons.
    b.Icon = b.Icon or b:CreateTexture( nil, "OVERLAY" )
    b.Icon:SetSize( conf.classic.indicators.width or 20, conf.classic.indicators.height or 20 )

    local zoom = 1 - ( ( conf.classic.indicators.zoom or 0) / 200 )

    if conf.classic.indicators.keepAspectRatio and conf.classic.indicators.height ~= conf.classic.indicators.width then
        local biggest = max( conf.classic.indicators.height or 20, conf.classic.indicators.width or 20 )
        local height = 0.5 * zoom * ( conf.classic.indicators.height or 20 ) / biggest
        local width = 0.5 * zoom * ( conf.classic.indicators.width or 20 ) / biggest

        b.Icon:SetTexCoord( 0.5 - width, 0.5 + width, 0.5 - height, 0.5 + height )
    else
        b.Icon:SetTexCoord( 0, 1, 0, 1 )
    end

    local iconAnchor = conf.classic.indicators.anchor or "RIGHT"

    b.Icon:ClearAllPoints()
    b.Icon:SetPoint( iconAnchor, b, iconAnchor, conf.classic.indicators.x or 0, conf.classic.indicators.y or 0 )
    b.Icon:Hide()


    -- Caption Text.
    b.Caption = b.Caption or b:CreateFontString( bName .. "_Caption", "OVERLAY" )

    local captionFont = conf.classic.captions.font or conf.font
    b.Caption:SetFont( LSM:Fetch("font", captionFont), conf.classic.captions.fontSize or 12, conf.classic.captions.fontStyle or "OUTLINE" )

    local capAnchor = conf.classic.captions.anchor or "BOTTOM"
    b.Caption:ClearAllPoints()
    b.Caption:SetPoint( capAnchor, b, capAnchor, conf.classic.captions.x or 0, conf.classic.captions.y or 0 )
    b.Caption:SetHeight( b:GetHeight() / 2 )
    b.Caption:SetJustifyV( capAnchor:match("RIGHT") and "RIGHT" or ( capAnchor:match( "LEFT" ) and "LEFT" or "MIDDLE" ) )
    b.Caption:SetJustifyH( conf.classic.captions.align or "CENTER" )
    b.Caption:SetTextColor( unpack( conf.classic.captions.color ) )
    b.Caption:SetWordWrap( false )

    local capText = b.Caption:GetText()
    b.Caption:SetText( nil )
    b.Caption:SetText( capText )


    -- Keybinding Text
    b.Keybinding = b.Keybinding or b:CreateFontString(bName .. "_KB", "OVERLAY")

    local queued = id > 1 and conf.classic.keybindings.separateQueueStyle
    local kbFont = queued and conf.classic.keybindings.queuedFont or conf.classic.keybindings.font or conf.font

    b.Keybinding:SetFont( LSM:Fetch("font", kbFont), queued and conf.classic.keybindings.queuedFontSize or conf.classic.keybindings.fontSize or 12, queued and conf.classic.keybindings.queuedFontStyle or conf.classic.keybindings.fontStyle or "OUTLINE" )

    local kbAnchor = conf.classic.keybindings.anchor or "TOPRIGHT"
    b.Keybinding:ClearAllPoints()
    b.Keybinding:SetPoint( kbAnchor, b, kbAnchor, conf.classic.keybindings.x or 0, conf.classic.keybindings.y or 0 )
    b.Keybinding:SetHeight( b:GetHeight() / 2 )
    b.Keybinding:SetJustifyH( kbAnchor:match("RIGHT") and "RIGHT" or ( kbAnchor:match( "LEFT" ) and "LEFT" or "CENTER" ) )
    b.Keybinding:SetJustifyV( kbAnchor:match("TOP") and "TOP" or ( kbAnchor:match( "BOTTOM" ) and "BOTTOM" or "MIDDLE" ) )
    b.Keybinding:SetTextColor( unpack( queued and conf.classic.keybindings.queuedColor or conf.classic.keybindings.color ) )
    b.Keybinding:SetWordWrap( false )

    local kbText = b.Keybinding:GetText()
    b.Keybinding:SetText( nil )
    b.Keybinding:SetText( kbText )

    -- Cooldown Wheel
    if not b.Cooldown then
        b.Cooldown = CreateFrame( "Cooldown", bName .. "_Cooldown", b, "CooldownFrameTemplate" )
    end
    b.Cooldown:ClearAllPoints()
    b.Cooldown:SetAllPoints( b )
    b.Cooldown:SetFrameStrata( b:GetFrameStrata() )
    b.Cooldown:SetFrameLevel( b:GetFrameLevel() + 1 )
    b.Cooldown:SetDrawBling( false )
    b.Cooldown:SetDrawEdge( false )

    b.Cooldown.noCooldownCount = conf.hideOmniCC

    if _G["ElvUI"] and not b.isRegisteredCooldown and ( ( id == 1 and conf.elvuiCooldown ) or ( id > 1 and conf.classic.queue.elvuiCooldown ) ) then
        local E = unpack( ElvUI )

        local cd = b.Cooldown.CooldownSettings or {}
        cd.font = E.Libs.LSM:Fetch( "font", E.db.cooldown.fonts.font )
        cd.fontSize = E.db.cooldown.fonts.fontSize
        cd.fontOutline = E.db.cooldown.fonts.fontOutline
        b.Cooldown.CooldownSettings = cd

        E:RegisterCooldown( b.Cooldown )
        st.forceElvUpdate = true
    end

    -- Backdrop (for borders)
    b.Backdrop = b.Backdrop or Mixin( CreateFrame("Frame", bName .. "_Backdrop", b ), BackdropTemplateMixin )
    b.Backdrop:ClearAllPoints()
    b.Backdrop:SetWidth( b:GetWidth() + ( conf.classic.border.thickness and ( 2 * conf.classic.border.thickness ) or 2 ) )
    b.Backdrop:SetHeight( b:GetHeight() + ( conf.classic.border.thickness and ( 2 * conf.classic.border.thickness ) or 2 ) )

    local framelevel = b:GetFrameLevel()
    if framelevel > 0 then
        -- b.Backdrop:SetFrameStrata( "MEDIUM" )
        b.Backdrop:SetFrameLevel( framelevel - 1 )
    else
        local lowerStrata = frameStratas[ b:GetFrameStrata() ]
        lowerStrata = frameStratas[ lowerStrata - 1 ]
        b.Backdrop:SetFrameStrata( lowerStrata or "LOW" )
    end

    b.Backdrop:SetPoint( "CENTER", b, "CENTER" )
    b.Backdrop:Hide()

    if conf.classic.border.enabled then
        b.Backdrop:SetBackdrop( {
            bgFile = nil,
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            tileSize = 0,
            edgeSize = conf.classic.border.thickness or 1,
            insets = { left = -1, right = -1, top = -1, bottom = -1 }
        } )
        if conf.classic.border.coloring == 'custom' then
            b.Backdrop:SetBackdropBorderColor( unpack( conf.classic.border.color ) )
        else
            b.Backdrop:SetBackdropBorderColor( RAID_CLASS_COLORS[ Registry.ClassFile() ]:GetRGBA() )
        end
        b.Backdrop:Show()
    else
        b.Backdrop:SetBackdrop( nil )
        b.Backdrop:SetBackdropColor( 0, 0, 0, 0 )
        b.Backdrop:Hide()
    end


    -- Primary Icon Stuff
    if id == 1 then
        -- Anchoring stuff for the queue.
        b:ClearAllPoints()
        b:SetPoint( "CENTER", d, "CENTER" )

        -- Highlight
        if not b.Highlight then
            b.Highlight = b:CreateTexture( nil, "OVERLAY" )
            b.Highlight:SetTexture( "Interface\\Buttons\\ButtonHilight-Square" )
            b.Highlight:SetAllPoints( b )
            b.Highlight:SetBlendMode( "ADD" )
            b.Highlight:Hide()
        end

        -- Target Counter
        b.Targets = b.Targets or b:CreateFontString( bName .. "_Targets", "OVERLAY" )

        local tarFont = conf.classic.targets.font or conf.font
        b.Targets:SetFont( LSM:Fetch( "font", tarFont ), conf.classic.targets.fontSize or 12, conf.classic.targets.fontStyle or "OUTLINE" )

        local tarAnchor = conf.classic.targets.anchor or "BOTTOM"
        b.Targets:ClearAllPoints()
        b.Targets:SetPoint( tarAnchor, b, tarAnchor, conf.classic.targets.x or 0, conf.classic.targets.y or 0 )
        b.Targets:SetHeight( b:GetHeight() / 2 )
        b.Targets:SetJustifyH( tarAnchor:match("RIGHT") and "RIGHT" or ( tarAnchor:match( "LEFT" ) and "LEFT" or "CENTER" ) )
        b.Targets:SetJustifyV( tarAnchor:match("TOP") and "TOP" or ( tarAnchor:match( "BOTTOM" ) and "BOTTOM" or "MIDDLE" ) )
        b.Targets:SetTextColor( unpack( conf.classic.targets.color ) )
        b.Targets:SetWordWrap( false )

        local tText = b.Targets:GetText()
        b.Targets:SetText( nil )
        b.Targets:SetText( tText )

        -- Aura Counter
        -- Disabled for Now
        --[[ b.Auras = b.Auras or b:CreateFontString(bName .. "_Auras", "OVERLAY")

        local auraFont = conf.auraFont or (ElvUI and "PT Sans Narrow" or "Arial Narrow")
        b.Auras:SetFont(LSM:Fetch("font", auraFont), conf.auraFontSize or 12, conf.auraFontStyle or "OUTLINE")
        b.Auras:SetSize(b:GetWidth(), b:GetHeight() / 2)

        local auraAnchor = conf.auraAnchor or "BOTTOM"
        b.Auras:ClearAllPoints()
        b.Auras:SetPoint(auraAnchor, b, auraAnchor, conf.xOffsetAuras or 0, conf.yOffsetAuras or 0)

        b.Auras:SetJustifyH(
            auraAnchor:match("RIGHT") and "RIGHT" or (auraAnchor:match("LEFT") and "LEFT" or "CENTER")
        )
        b.Auras:SetJustifyV(
            auraAnchor:match("TOP") and "TOP" or (auraAnchor:match("BOTTOM") and "BOTTOM" or "MIDDLE")
        )
        b.Auras:SetTextColor(1, 1, 1, 1) ]]


        -- Delay Counter
        b.DelayText = b.DelayText or b:CreateFontString( bName .. "_DelayText", "OVERLAY" )

        local delayFont = conf.classic.delays.font or conf.font
        b.DelayText:SetFont( LSM:Fetch("font", delayFont), conf.classic.delays.fontSize or 12, conf.classic.delays.fontStyle or "OUTLINE" )

        local delayAnchor = conf.classic.delays.anchor or "TOPLEFT"
        b.DelayText:ClearAllPoints()
        b.DelayText:SetPoint( delayAnchor, b, delayAnchor, conf.classic.delays.x, conf.classic.delays.y or 0 )
        b.DelayText:SetHeight( b:GetHeight() / 2 )

        b.DelayText:SetJustifyH( delayAnchor:match( "RIGHT" ) and "RIGHT" or ( delayAnchor:match( "LEFT" ) and "LEFT" or "CENTER") )
        b.DelayText:SetJustifyV( delayAnchor:match( "TOP" ) and "TOP" or ( delayAnchor:match( "BOTTOM" ) and "BOTTOM" or "MIDDLE") )
        b.DelayText:SetTextColor( unpack( conf.classic.delays.color ) )

        local dText = b.DelayText:GetText()
        b.DelayText:SetText( nil )
        b.DelayText:SetText( dText )


        -- Delay Icon
        b.DelayIcon = b.DelayIcon or b:CreateTexture( bName .. "_DelayIcon", "OVERLAY" )
        b.DelayIcon:SetSize( min( 20, max( 10, b:GetSize() / 3 ) ), min( 20, max( 10, b:GetSize() / 3 ) ) )
        b.DelayIcon:SetTexture( "Interface\\FriendsFrame\\StatusIcon-Online" )
        b.DelayIcon:SetDesaturated( true )
        b.DelayIcon:SetVertexColor( 1, 0, 0, 1 )

        b.DelayIcon:ClearAllPoints()
        b.DelayIcon:SetPoint( delayAnchor, b, delayAnchor, conf.classic.delays.x or 0, conf.classic.delays.y or 0 )
        b.DelayIcon:Hide()

        -- Overlay (for Pause)
        b.Overlay = b.Overlay or b:CreateTexture( nil, "OVERLAY" )
        b.Overlay:SetAllPoints( b )
        b.Overlay:SetAtlas( "creditsscreen-assets-buttons-pause" )
        b.Overlay:SetVertexColor( 1, 1, 1, 1 )
        -- b.Overlay:SetTexCoord( unpack( b.texCoords ) )
        b.Overlay:Hide()

    elseif id == 2 then
        -- Anchoring for the remainder.
        local queueAnchor = conf.classic.queue.anchor or "RIGHT"
        local qOffsetX = ( conf.classic.queue.offsetX or 5 )
        local qOffsetY = ( conf.classic.queue.offsetY or 0 )

        b:ClearAllPoints()

        if queueAnchor:sub( 1, 5 ) == "RIGHT" then
            local dir, align = "RIGHT", queueAnchor:sub(6)
            b:SetPoint( align .. getInverseDirection(dir), "Hekili_" .. dispID .. "_B1", align .. dir, ( borderOffset + qOffsetX ) * scale, qOffsetY * scale )
        elseif queueAnchor:sub( 1, 4 ) == "LEFT" then
            local dir, align = "LEFT", queueAnchor:sub(5)
            b:SetPoint( align .. getInverseDirection(dir), "Hekili_" .. dispID .. "_B1", align .. dir, -1 * ( borderOffset + qOffsetX ) * scale, qOffsetY * scale )
        elseif queueAnchor:sub( 1, 3)  == "TOP" then
            local dir, align = "TOP", queueAnchor:sub(4)
            b:SetPoint( getInverseDirection(dir) .. align, "Hekili_" .. dispID .. "_B1", dir .. align, 0, ( borderOffset + qOffsetY ) * scale )
        else -- BOTTOM
            local dir, align = "BOTTOM", queueAnchor:sub(7)
            b:SetPoint( getInverseDirection(dir) .. align, "Hekili_" .. dispID .. "_B1", dir .. align, 0, -1 * ( borderOffset + qOffsetY ) * scale )
        end
    else
        local queueDirection = conf.classic.queue.direction or "RIGHT"
        local btnSpacing = borderOffset + ( conf.classic.queue.spacing or 5 )

        b:ClearAllPoints()

        if queueDirection == "RIGHT" then
            b:SetPoint( getInverseDirection(queueDirection), "Hekili_" .. dispID .. "_B" .. id - 1, queueDirection, btnSpacing * scale, 0 )
        elseif queueDirection == "LEFT" then
            b:SetPoint( getInverseDirection(queueDirection), "Hekili_" .. dispID .. "_B" .. id - 1, queueDirection, -1 * btnSpacing * scale, 0 )
        elseif queueDirection == "TOP" then
            b:SetPoint( getInverseDirection(queueDirection), "Hekili_" .. dispID .. "_B" .. id - 1, queueDirection, 0, btnSpacing * scale )
        else -- BOTTOM
            b:SetPoint( getInverseDirection(queueDirection), "Hekili_" .. dispID .. "_B" .. id - 1, queueDirection, 0, -1 * btnSpacing * scale )
        end
    end


    -- Mover Stuff.
    b:SetScript( "OnMouseDown", Button_OnMouseDown )
    b:SetScript( "OnMouseUp", Button_OnMouseUp )

    b:SetScript( "OnEnter", function( self )
        local H = Hekili

        --[[ if H.Config then
            Tooltip:SetOwner( self, "ANCHOR_TOPRIGHT" )
            Tooltip:SetBackdropColor( 0, 0, 0, 0.8 )

            Tooltip:SetText( "Hekili: " .. dispID  )
            Tooltip:AddLine( "Left-click and hold to move.", 1, 1, 1 )
            Tooltip:Show()
            self:SetMovable( true )

        else ]]
        if ( H.Pause and st.HasRecommendations and b.Recommendation ) then
            H:ShowDiagnosticTooltip( b.Recommendation )
        end
    end )

    b:SetScript( "OnLeave", function(self)
        HekiliTooltip:Hide()
    end )

    Hekili:ProfileFrame( bName, b )

    b:EnableMouse( false )
    b:SetMovable( false )

    return b
end

-- The cooldown spirals of the drawn buttons (was d:RefreshCooldowns).
local function RefreshCooldowns( self, out )
    local gStart = GetSpellCooldown( Registry.GCD_SPELL )
    -- The last GCD start seen, what the stock engine kept from the combat log (gcd.lastStart), for the extend below.
    if gStart > lastGcdStart then lastGcdStart = gStart end
    local cStart = ( select( 4, UnitCastingInfo( "player" ) ) or select( 4, UnitChannelInfo( "player" ) ) or 0 ) / 1000

    local now = GetTime()
    local conf = Hekili.DB.profile.displays[ self.id ]

    for i = 1, out.count do
        local rec = out.recs[ i ]
        local button = self.Buttons[ i ]

        if button.Action and button.Action == rec.actionName then
            local cd = button.Cooldown
            local ability = button.Ability

            local start, duration, enabled, modRate = 0, 0, 1, 1

            if ability.item then
                start, duration, enabled, modRate = GetItemCooldown( ability.item )
            else
                start, duration, enabled, modRate = GetSpellCooldown( ability.actionID )
            end

            if i == 1 and conf.classic.delays.extend and rec.exact_time > max( now, start + duration ) then
                start = ( start > 0 and start ) or ( cStart > 0 and cStart ) or ( gStart > 0 and gStart ) or max( lastGcdStart, Status.combatStart )
                duration = rec.exact_time - start

            elseif enabled and enabled == 0 then
                start = 0
                duration = 0
                modRate = 1
            end

            if cd.lastStart ~= start or cd.lastDuration ~= duration then
                cd:SetCooldown( start, duration, modRate )
                cd.lastStart = start
                cd.lastDuration = duration
            end
        end
    end
end

--- Builds (or reuses) the ten buttons on `d` and returns them; core stores the list as ns.UI.Buttons[ d.id ].
function Classic.Build( d, conf )
    local self, id, st = Hekili, d.id, d.styleState
    local scale, border = self:GetScale(), 2
    d:SetSize( scale * ( border + ( conf.classic.primaryWidth or 50 ) ), scale * ( border + ( conf.classic.primaryHeight or 50 ) ) )
    d.styleFrames.classic = d.styleFrames.classic or {}
    local buttons = d.styleFrames.classic
    st.delayTimer, st.flashTimer, st.rangeTimer = st.delayTimer or 0, st.flashTimer or 0, st.rangeTimer or 0

    local out = Hekili.Engine.Output[ id ]

    for i = 1, 10 do
        buttons[ i ] = CreateButton( id, i )
        buttons[ i ]:Hide()

        if self:IsDisplayActive( id ) and i <= conf.numIcons then
            if out and i <= out.count then
                buttons[ i ]:Show()
            end
        end

        if ns.UI.MasqueGroup then
            ns.UI.MasqueGroup:AddButton( buttons[i], { Icon = buttons[ i ].Texture, Cooldown = buttons[ i ].Cooldown } )
        end
    end

    if st.forceElvUpdate then
        local E = _G.ElvUI and ElvUI[1]
        E:UpdateCooldownOverride( 'global' )
        st.forceElvUpdate = nil
    end

    if st.flashReady == nil then
        C_Timer.After( 3, function()
            st.flashReady = true
        end )
    end

    return buttons
end

function Classic.UpdateKeybindings( d )
    local self = d
    local conf = Hekili.DB.profile.displays[ self.id ]

    if conf.classic.keybindings and conf.classic.keybindings.enabled then
        for i, b in ipairs( self.Buttons ) do
            local a = b.Action

            if a then
                b.Keybind, b.KeybindFrom = Hekili:GetBindingForAction( a, conf, i )

                if i == 1 or conf.classic.keybindings.queued then
                    b.Keybinding:SetText( b.Keybind )
                else
                    b.Keybinding:SetText( nil )
                end
            else
                b.Keybinding:SetText( nil )
            end
        end
    end
end


--- Every frame, before Draw: the pause overlay; keeps the frame's elapsed for Draw's timers.
function Classic.Tick( d, conf, out, now, elapsed )
    local self, st = d, d.styleState
    st.elapsed = elapsed

    if not self.id == "Primary" and not ( self.Buttons[ 1 ] and self.Buttons[ 1 ].Action ) and not ( st.HasRecommendations or not self.NewRecommendations ) then
        return
    end

    if Hekili.Pause and not st.paused then
        self.Buttons[ 1 ].Overlay:Show()
        st.paused = true
    elseif not Hekili.Pause and st.paused then
        self.Buttons[ 1 ].Overlay:Hide()
        st.paused = false
    end
end

--- On a publish (d.NewRecommendations, which Draw consumes) or the 0.25 s pulse: the buttons, glow, flash, target
--- count, delay and range/usable/desaturate.
function Classic.Draw( d, conf, out, status )
    local self, st = d, d.styleState
    local elapsed = st.elapsed
    local init = debugprofilestop()
    local profile = Hekili.DB.profile
    local fullUpdate = true -- core calls Draw only on a full update (a publish or the pulse)

    local madeUpdate = false

    local now = GetTime()

    if self.NewRecommendations then
        self.NewRecommendations = nil
        madeUpdate = true

        local alpha = self.alpha

        if out.count == 0 or out.version == self.blankVersion then
            for i, b in ipairs( self.Buttons ) do
                b:Hide()
                b.Action = nil
            end
            st.HasRecommendations = false

        else
            st.HasRecommendations = true

            -- Records past out.count hold no action (Begin cleared them), so their buttons hide.
            for i, b in ipairs( self.Buttons ) do
                b.Recommendation = out.recs[ i ]

                local action = b.Recommendation.actionName
                local caption = b.Recommendation.caption
                local indicator = b.Recommendation.indicator
                local keybind = b.Recommendation.keybind
                local exact_time = b.Recommendation.exact_time

                -- The published record is the button's ability: actionID, item, offGCD, texture (Core resolved it).
                local ability = action and b.Recommendation or nil

                if ability and ability.actionID < 0 and ability.actionID > -100 and action ~= "cancel_buff" or exact_time == nil then ability = nil end

                if ability then
                    if ( conf.classic.flash.enabled and conf.classic.flash.suppress ) then b:Hide()
                    else b:Show() end

                    --[[ if i == 1 then
                        -- print( "Changing", GetTime() )
                    end ]]

                    local image = ability.texture -- texture to be shown on the button for the current action

                    if action ~= b.lastAction or image ~= b.lastImage or self.NewRecommendations or not b.Image then
                        b.Image = image
                        b.Texture:SetTexture( b.Image )
                        b.Texture:SetTexCoord( unpack( b.texCoords ) )
                        b.lastAction = action
                        b.lastImage = image
                    end

                    b.Texture:Show()

                    if i == 1 then
                        if conf.classic.glow.highlight then
                            local id = ability.item or ability.actionID
                            local isItem = ability.item ~= nil

                            if id and ( isItem and IsCurrentItem( id ) or IsCurrentSpell( id ) ) and exact_time > GetTime() then
                                b.Highlight:Show()
                            else
                                b.Highlight:Hide()
                            end

                        elseif b.Highlight:IsShown() then
                            b.Highlight:Hide()
                        end
                    end


                    if conf.classic.indicators.enabled and indicator then
                        if indicator == "cycle" then
                            b.Icon:SetTexture("Interface\\Addons\\Hekili\\Textures\\Cycle")
                        end
                        if indicator == "cancel" then
                            b.Icon:SetTexture("Interface\\Addons\\Hekili\\Textures\\Cancel")
                        end
                        b.Icon:Show()
                    else
                        b.Icon:Hide()
                    end

                    if ( caption and conf.classic.captions.enabled or Registry.Abilities()[ action ].caption ) and ( i == 1 or conf.classic.captions.queued ) then
                        b.Caption:SetText( caption )
                    else
                        b.Caption:SetText(nil)
                    end

                    if conf.classic.keybindings.enabled and ( i == 1 or conf.classic.keybindings.queued ) then
                        b.Keybinding:SetText( keybind )
                    else
                        b.Keybinding:SetText(nil)
                    end

                    if conf.classic.glow.enabled and ( i == 1 or conf.classic.glow.queued ) and IsSpellOverlayed( ability.actionID ) then
                        b.glowColor = b.glowColor or {}

                        if conf.classic.glow.coloring == "class" then
                            b.glowColor[1], b.glowColor[2], b.glowColor[3], b.glowColor[4] = RAID_CLASS_COLORS[ Registry.ClassFile() ]:GetRGBA()
                        elseif conf.classic.glow.coloring == "custom" then
                            b.glowColor[1], b.glowColor[2], b.glowColor[3], b.glowColor[4] = unpack(conf.classic.glow.color)
                        else
                            b.glowColor[1], b.glowColor[2], b.glowColor[3], b.glowColor[4] = 0.95, 0.95, 0.32, 1
                        end

                        if conf.classic.glow.mode == "default" then
                            Glower.ButtonGlow_Start( b, b.glowColor )
                            b.glowStop = Glower.ButtonGlow_Stop
                        elseif conf.classic.glow.mode == "autocast" then
                            Glower.AutoCastGlow_Start( b, b.glowColor )
                            b.glowStop = Glower.AutoCastGlow_Stop
                        elseif conf.classic.glow.mode == "pixel" then
                            Glower.PixelGlow_Start( b, b.glowColor )
                            b.glowStop = Glower.PixelGlow_Stop
                        end

                        b.glowing = true
                    elseif b.glowing then
                        if b.glowStop then b:glowStop() end
                        b.glowing = false
                    end

                else
                    b:Hide()
                end

                b.Action = action
                b.Text = caption
                b.Indicator = indicator
                b.Keybind = keybind
                -- The published record is reused between publishes (Output.Begin clears it); this redraw on
                -- NewRecommendations runs before any reuse.
                b.Ability = ability
                b.ExactTime = exact_time
            end

            RefreshCooldowns( self, out )
        end
    end

    local postRecs = debugprofilestop()

    if st.HasRecommendations then
        if fullUpdate and conf.classic.glow.enabled then
            madeUpdate = true

            for i, b in ipairs( self.Buttons ) do
                if not b.Action then break end

                local a = b.Ability

                if i == 1 or conf.classic.glow.queued then
                    local glowing = a.actionID > 0 and IsSpellOverlayed( a.actionID )

                    if glowing and not b.glowing then
                        b.glowColor = b.glowColor or {}

                        if conf.classic.glow.coloring == "class" then
                            b.glowColor[1], b.glowColor[2], b.glowColor[3], b.glowColor[4] = RAID_CLASS_COLORS[ Registry.ClassFile() ]:GetRGBA()
                        elseif conf.classic.glow.coloring == "custom" then
                            b.glowColor[1], b.glowColor[2], b.glowColor[3], b.glowColor[4] = unpack(conf.classic.glow.color)
                        else
                            b.glowColor[1], b.glowColor[2], b.glowColor[3], b.glowColor[4] = 0.95, 0.95, 0.32, 1
                        end

                        if conf.classic.glow.mode == "default" then
                            Glower.ButtonGlow_Start( b, b.glowColor )
                            b.glowStop = Glower.ButtonGlow_Stop
                        elseif conf.classic.glow.mode == "autocast" then
                            Glower.AutoCastGlow_Start( b, b.glowColor )
                            b.glowStop = Glower.AutoCastGlow_Stop
                        elseif conf.classic.glow.mode == "pixel" then
                            Glower.PixelGlow_Start( b, b.glowColor )
                            b.glowStop = Glower.PixelGlow_Stop
                        end

                        b.glowing = true
                    elseif not glowing and b.glowing then
                        b:glowStop()
                        b.glowing = false
                    end
                else
                    if b.glowing then
                        b:glowStop()
                        b.glowing = false
                    end
                end
            end
        end

        local postGlow = debugprofilestop()

        if st.flashReady and conf.classic.flash.enabled and LSF and ( InCombatLockdown() or not conf.classic.flash.combat ) then
            st.flashTimer = st.flashTimer - elapsed
            st.flashWarnings = st.flashWarnings or {}
            st.lastFlashFrames = st.lastFlashFrames or {}

            local a = self.Buttons[ 1 ].Action
            local changed = st.lastFlash ~= a

            if a and ( fullUpdate or changed ) then
                madeUpdate = true

                if changed then
                    for frame in pairs( st.lastFlashFrames ) do
                        frame:Hide()
                        frame.flashDuration = 0
                        st.lastFlashFrames[ frame ] = nil
                    end
                end

                st.flashTimer = conf.classic.flash.speed or 0.4

                local ability = Registry.Abilities()[ a ]

                st.flashColor = st.flashColor or {}
                st.flashColor.r, st.flashColor.g, st.flashColor.b = unpack( conf.classic.flash.color )

                catchFlash = GetTime()
                table.wipe( lastFramesFlashed )

                if ability.item then
                    local iname = LSF.ItemName( ability.item )
                    if LSF.Flashable( iname ) then
                        LSF.FlashItem( iname, st.flashColor, conf.classic.flash.size, conf.classic.flash.brightness, conf.classic.flash.blink, nil, profile.flashTexture, conf.classic.flash.fixedSize, conf.classic.flash.fixedBrightness )
                    elseif conf.classic.flash.suppress and not st.flashWarnings[ iname ] then
                        st.flashWarnings[ iname ] = true
                        -- Hekili:Error( "|cffff0000WARNING|r - Could not flash recommended item '" .. iname .. "' (" .. self.id .. ")." )
                    end
                else
                    local aFlash = ability.flash
                    if aFlash then
                        local flashable = false

                        if type( aFlash ) == "table" then
                            local lastSpell
                            for _, spell in ipairs( aFlash ) do
                                lastSpell = spell
                                if LSF.Flashable( spell ) then
                                    flashable = true
                                    break
                                end
                            end
                            aFlash = lastSpell
                        else
                            flashable = LSF.Flashable( aFlash )
                        end

                        if flashable then
                            LSF.FlashAction( aFlash, st.flashColor, conf.classic.flash.size, conf.classic.flash.brightness, conf.classic.flash.blink, nil, profile.flashTexture, conf.classic.flash.fixedSize, conf.classic.flash.fixedBrightness )
                        elseif conf.classic.flash.suppress and not st.flashWarnings[ aFlash ] then
                            st.flashWarnings[ aFlash ] = true
                            -- Hekili:Error( "|cffff0000WARNING|r - Could not flash recommended action '" .. aFlash .. "' (" .. self.id .. ")." )
                        end
                    else
                        local id = ability.known

                        if id == nil or type( id ) ~= "number" then
                            id = ability.id
                        end

                        local sname = LSF.SpellName( id )

                        if sname then
                            if LSF.Flashable( sname ) then
                                LSF.FlashAction( sname, st.flashColor, conf.classic.flash.size, conf.classic.flash.brightness, conf.classic.flash.blink, nil, profile.flashTexture, conf.classic.flash.fixedSize, conf.classic.flash.fixedBrightness )
                            elseif not st.flashWarnings[ sname ] then
                                st.flashWarnings[ sname ] = true
                                -- Hekili:Error( "|cffff0000WARNING|r - Could not flash recommended ability '" .. sname .. "' (" .. self.id .. ")." )
                            end
                        end
                    end
                end

                catchFlash = nil
                for frame, status in pairs( lastFramesFlashed ) do
                    if status ~= 0 then
                        st.lastFlashFrames[ frame ] = 1
                        if frame.texture ~= profile.flashTexture then
                            frame.FlashTexture:SetTexture( profile.flashTexture )
                            frame.texture = profile.flashTexture
                        end
                    end
                end
                st.lastFlash = a
            end
        end

        local postFlash = debugprofilestop()

        if fullUpdate then
            local b = self.Buttons[ 1 ]

            if conf.classic.targets.enabled then
                madeUpdate = true

                local tMin, tMax = 0, 0
                local mode = profile.toggles.mode.value
                local spec = Status.specID and profile.specs[ Status.specID ]

                if self.id == 'Primary' then
                    if ( mode == 'dual' or mode == 'single' or mode == 'reactive' ) then tMax = 1
                    elseif mode == 'aoe' then tMin = spec and spec.aoe or 3 end
                elseif self.id == 'AOE' then tMin = spec and spec.aoe or 3 end

                local detected = Status.numTargets
                local shown = detected

                if tMin > 0 then
                    shown = max(tMin, shown)
                end
                if tMax > 0 then
                    shown = min(tMax, shown)
                end

                if tMax == 1 or shown > 1 then
                    local color = detected < shown and "|cFFFF0000" or ( shown < detected and "|cFF00C0FF" or "" )
                    b.Targets:SetText( color .. shown .. "|r")
                    b.targetShown = true
                else
                    b.Targets:SetText(nil)
                    b.targetShown = false
                end
            elseif b.targetShown then
                madeUpdate = true
                b.Targets:SetText(nil)
            end
        end

        local postTargets = debugprofilestop()

        st.delayTimer = st.delayTimer - elapsed

        if fullUpdate and self.Buttons[ 1 ].ExactTime then
            madeUpdate = true

            local b = self.Buttons[ 1 ]
            local a = b.Ability

            local delay = b.ExactTime - now
            local earliest_time = 0

            if delay > 0 then
                local start, duration = 0, 0

                if not a.offGCD then
                    start, duration = GetSpellCooldown( Registry.GCD_SPELL )
                    if start > 0 then earliest_time = start + duration - now end
                end

                start, duration = select( 4, UnitCastingInfo( "player" ) )
                if start and start > 0 then earliest_time = max( ( start / 1000 ) + ( duration / 1000 ) - now, earliest_time ) end

                local rStart, rDuration = 0, 0
                if a.item then
                    rStart, rDuration = C_Item.GetItemCooldown( a.item )
                else
                    local def = Registry.Abilities()[ b.Action ]
                    if def.cooldown > 0 or def.spendType ~= "runes" then
                        rStart, rDuration = GetSpellCooldown( a.actionID )
                    end
                end
                if rStart > 0 then earliest_time = max( earliest_time, rStart + rDuration - now ) end
            end

            if conf.classic.delays.type == "TEXT" then
                if st.delayIconShown then
                    b.DelayIcon:Hide()
                    st.delayIconShown = false
                end

                if delay > earliest_time + 0.05 then
                    b.DelayText:SetText( format( "%.1f", delay ) )
                    st.delayTextShown = true
                else
                    b.DelayText:SetText( nil )
                    st.delayTextShown = false
                end

            elseif conf.classic.delays.type == "ICON" then
                if st.delayTextShown then
                    b.DelayText:SetText(nil)
                    st.delayTextShown = false
                end

                if delay > earliest_time + 0.05 then
                    b.DelayIcon:Show()
                    b.DelayIcon:SetAlpha( self.alpha )

                    st.delayIconShown = true

                    if delay < 0.5 then
                        b.DelayIcon:SetVertexColor( 0.0, 1.0, 0.0, 1.0 )
                    elseif delay < 1.5 then
                        b.DelayIcon:SetVertexColor( 1.0, 1.0, 0.0, 1.0 )
                    else
                        b.DelayIcon:SetVertexColor( 1.0, 0.0, 0.0, 1.0 )
                    end
                else
                    b.DelayIcon:Hide()
                    b.delayIconShown = false

                end
            else
                if st.delayTextShown then
                    b.DelayText:SetText( nil )
                    st.delayTextShown = false
                end
                if st.delayIconShown then
                    b.DelayIcon:Hide()
                    st.delayIconShown = false
                end
            end

            b.EarliestTime = earliest_time
        end

        st.rangeTimer = st.rangeTimer - elapsed
        if fullUpdate or st.rangeTimer < 0 then
            madeUpdate = true

            for i, b in ipairs( self.Buttons ) do
                local a = b.Ability

                if a and a.actionID then
                    local def = Registry.Abilities()[ b.Action ]
                    local outOfRange = false
                    local desaturated = false

                    if conf.classic.range.enabled and UnitCanAttack( "player", "target" ) then
                        if conf.classic.range.type == "melee" then
                            outOfRange = ( LRC:GetRange( "target" ) or 10 ) > 7
                        elseif conf.classic.range.type == "ability" then
                            local name = def.rangeSpell or def.itemSpellName or def.actualName or def.name
                            if name then outOfRange = LSR.IsSpellInRange( name, "target" ) == 0 end
                        end
                    end

                    if outOfRange and not b.outOfRange then
                        b.Texture:SetVertexColor(1.0, 0.0, 0.0, 1.0)
                        b.outOfRange = true
                        desaturated = true
                    elseif b.outOfRange and not outOfRange then
                        b.Texture:SetVertexColor(1.0, 1.0, 1.0, 1.0)
                        b.outOfRange = false
                        desaturated = false
                    end

                    if not b.outOfRange then
                        local _, unusable

                        if def.itemCd or a.item then
                            unusable = not IsUsableItem( def.itemCd or a.item )
                        else
                            _, unusable = IsUsableSpell( def.actualName or def.name )
                        end

                        if i == 1 and ( conf.classic.delays.fade or conf.classic.delays.desaturate ) then
                            local delay = b.ExactTime and ( b.ExactTime - now ) or 0
                            local earliest_time = b.EarliestTime or delay
                            if delay > earliest_time + 0.05 then
                                if conf.classic.delays.fade then unusable = true end
                                if conf.classic.delays.desaturate then desaturated = true end
                            end
                        end

                        if unusable and not b.unusable then
                            b.Texture:SetVertexColor(0.4, 0.4, 0.4, 1.0)
                            b.unusable = true
                        elseif b.unusable and not unusable then
                            b.Texture:SetVertexColor(1.0, 1.0, 1.0, 1.0)
                            b.unusable = false
                        end
                    end

                    if desaturated and not b.desaturated then
                        b.Texture:SetDesaturated(true)
                        b.desaturated = true
                    elseif b.desaturated and not desaturated then
                        b.Texture:SetDesaturated(false)
                        b.desaturated = false
                    end
                end
            end

            st.rangeTimer = pulseRange
        end

        local postRange = debugprofilestop()
        local finish = debugprofilestop()

        if madeUpdate then
            if st.updateTime then
                local newTime = st.updateTime * st.updateCount + ( finish - init )
                st.updateCount = st.updateCount + 1
                st.updateTime = newTime / st.updateCount

                st.updateMax = max( st.updateMax, finish - init )
                st.postRecs = max( st.postRecs, postRecs - init )
                st.postGlow = max( st.postGlow, postGlow - postRecs )
                st.postRange = max( st.postRange, postRange - postGlow )
                st.postFlash = max( st.postFlash, postFlash - postRange )
                st.postTargets = max( st.postTargets, postTargets - postFlash )
                st.postDelay = max( st.postDelay, finish - postTargets )
            else
                st.updateCount = 1
                st.updateTime = finish - init
                st.updateMax = finish - init

                st.postRecs = postRecs - init
                st.postGlow = postGlow - postRecs
                st.postRange = postRange - postGlow
                st.postFlash = postFlash - postRange
                st.postTargets = postTargets - postFlash
                st.postDelay = finish - postTargets
            end
        end
    end
end

function Classic.OnGameEvent( d, conf, event, ... )
    local self, st = d, d.styleState

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        if conf.classic.glow.enabled then
            for i, b in ipairs( self.Buttons ) do
                if i > 1 and not conf.classic.glow.queued then
                    break
                end

                if not b.Action then
                    break
                end

                local a = b.Ability

                if not b.glowing and a and a.actionID == ... then
                    b.glowColor = b.glowColor or {}

                    if conf.classic.glow.coloring == "class" then
                        b.glowColor[1], b.glowColor[2], b.glowColor[3], b.glowColor[4] = RAID_CLASS_COLORS[ Registry.ClassFile() ]:GetRGBA()
                    elseif conf.classic.glow.coloring == "custom" then
                        b.glowColor[1], b.glowColor[2], b.glowColor[3], b.glowColor[4] = unpack(conf.classic.glow.color)
                    else
                        b.glowColor[1], b.glowColor[2], b.glowColor[3], b.glowColor[4] = 0.95, 0.95, 0.32, 1
                    end

                    if conf.classic.glow.mode == "default" then
                        Glower.ButtonGlow_Start( b, b.glowColor )
                        b.glowStop = Glower.ButtonGlow_Stop
                    elseif conf.classic.glow.mode == "autocast" then
                        Glower.AutoCastGlow_Start( b, b.glowColor )
                        b.glowStop = Glower.AutoCastGlow_Stop
                    elseif conf.classic.glow.mode == "pixel" then
                        Glower.PixelGlow_Start( b, b.glowColor )
                        b.glowStop = Glower.PixelGlow_Stop
                    end

                    b.glowing = true
                end
            end
        end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if conf.classic.glow.enabled then
            for i, b in ipairs(self.Buttons) do
                if i > 1 and not conf.classic.glow.queued then
                    break
                end

                if not b.Action then
                    break
                end

                local a = b.Ability

                if b.glowing and ( not a or a.actionID == ... ) then
                    b:glowStop()
                    b.glowing = false
                end
            end
        end
    end

    if flashEvents[ event ] then
        st.flashReady = false
        C_Timer.After( 3, function()
            st.flashReady = true
        end )
    end

    if event == "CURRENT_SPELL_CAST_CHANGED" then
        local b = self.Buttons[ 1 ]

        if conf.classic.glow.highlight then
            local ability = b.Ability
            local isItem, id = false, ability and ability.actionID

            if id and id < 0 then
                isItem = true
                id = ability.item
            end

            if id and ( isItem and IsCurrentItem( id ) or IsCurrentSpell( id ) ) then --  and b.ExactTime > GetTime() then
                b.Highlight:Show()
            else
                b.Highlight:Hide()
            end
        elseif b.Highlight:IsShown() then
            b.Highlight:Hide()
        end
    end
end

--- Hides every button and forgets what it showed (unsubscribe, Deactivate, a style switch). Its own frames, not
--- d.Buttons, which a switch hands to the next style.
function Classic.Clear( d )
    for _, b in ipairs( d.styleFrames.classic ) do
        b:Hide()
        b.Action = nil
    end
    d.styleState.HasRecommendations = false
end

--- The outermost buttons (left, right, top, bottom) for config mode's backdrop.
function Classic.Perimeter( d )
    local self = d
    local left, right, top, bottom
    local lPos, rPos, tPos, bPos

    for i = 1, self.numIcons do
        local button = self.Buttons[ i ]

        if i == 1 then
            lPos = button:GetLeft()
            rPos = button:GetRight()
            tPos = button:GetTop()
            bPos = button:GetBottom()

            left = button
            right = button
            top = button
            bottom = button
        else
            if button:GetLeft() < lPos then
                lPos = button:GetLeft()
                left = button
            end

            if button:GetRight() > rPos then
                rPos = button:GetRight()
                right = button
            end

            if button:GetTop() > tPos then
                tPos = button:GetTop()
                top = button
            end

            if button:GetBottom() < bPos then
                bPos = button:GetBottom()
                bottom = button
            end
        end
    end

    return left, right, top, bottom
end

-- Classic's option tabs, moved verbatim out of Options/Options.lua's newDisplayOption (Task 2). `name` and `data` were
-- its upvalues (the display id and its config); the rest of what they read comes from Options.lua through
-- ns.UI.DisplayOptionParts. Core puts them in one group keyed `classic` (hidden unless the display is classic), so their
-- profile path is display → classic → tab key → option (Task 2b); `layout` holds what was classic's part of `main`.
function Classic.Options( id, conf )
    local name, data = id, conf
    local P = ns.UI.DisplayOptionParts
    local ClassColor, NewFeature, fontElements, fontStyles = P.ClassColor, P.NewFeature, P.fontElements, P.fontStyles
    local anchorPositions, realAnchorPositions, rangeIcon = P.anchorPositions, P.realAnchorPositions, P.rangeIcon
    local SF, tableCopy = SpellFlashCore, ns.tableCopy

    return {
        layout = {
            type = "group",
            name = "Icons",
            desc = "Icon size, shape and the queue's layout.",
            order = 1,

            args = {
                primaryIcon = {
                    type = "group",
                    name = "Primary Icon",
                    inline = true,
                    order = 15,
                    args = {
                        primaryWidth = {
                            type = "range",
                            name = "Width",
                            desc = "Specify the width of the primary icon for " .. ( name == "Multi" and "each display." or ( "your " .. name .. " Display." ) ),
                            min = 10,
                            max = 500,
                            step = 1,

                            width = 1.49,
                            order = 1,
                        },

                        primaryHeight = {
                            type = "range",
                            name = "Height",
                            desc = "Specify the height of the primary icon for " .. ( name == "Multi" and "each display." or ( "your " .. name .. " Display." ) ),
                            min = 10,
                            max = 500,
                            step = 1,

                            width = 1.49,
                            order = 2,
                        },

                        spacer01 = {
                            type = "description",
                            name = " ",
                            width = "full",
                            order = 3
                        },

                        zoom = {
                            type = "range",
                            name = "Icon Zoom",
                            desc = "Select the zoom percentage for the icon textures in this display. (Roughly 30% will trim off the default Blizzard borders.)",
                            min = 0,
                            softMax = 100,
                            max = 200,
                            step = 1,

                            width = 1.49,
                            order = 4,
                        },

                        keepAspectRatio = {
                            type = "toggle",
                            name = "Keep Aspect Ratio",
                            desc = "If your primary or queued icons are not square, checking this option will prevent the icon textures from being " ..
                                "stretched and distorted, trimming some of the texture instead.",
                            disabled = function( info, val )
                                return not ( data.classic.primaryHeight ~= data.classic.primaryWidth or ( data.numIcons > 1 and data.classic.queue.height ~= data.classic.queue.width ) )
                            end,
                            width = 1.49,
                            order = 5,
                        },
                    },
                },

                queuedElvuiCooldown = {
                    type = "toggle",
                    name = "Apply ElvUI Cooldown Style to Queued Icons",
                    desc = "If ElvUI is installed, you can apply the ElvUI cooldown style to your queued icons.\n\nDisabling this setting requires you to reload your UI (|cFFFFD100/reload|r).",
                    width = "full",
                    order = 23,
                    get = function( info )
                        return Hekili.DB.profile.displays[ name ].classic.queue.elvuiCooldown
                    end,
                    set = function( info, val )
                        Hekili.DB.profile.displays[ name ].classic.queue.elvuiCooldown = val
                    end,
                    hidden = function () return _G["ElvUI"] == nil end,
                },

                iconSizeGroup = {
                    type = "group",
                    inline = true,
                    name = "Queued Icon Size",
                    order = 21,
                    args = {
                        width = {
                            type = 'range',
                            name = 'Width',
                            desc = "Select the width of the queued icons.",
                            min = 10,
                            max = 500,
                            step = 1,
                            bigStep = 1,
                            order = 10,
                            width = 1.49,
                            get = function( info )
                                return Hekili.DB.profile.displays[ name ].classic.queue.width
                            end,
                            set = function( info, val )
                                Hekili.DB.profile.displays[ name ].classic.queue.width = val
                            end,
                        },

                        height = {
                            type = 'range',
                            name = 'Height',
                            desc = "Select the height of the queued icons.",
                            min = 10,
                            max = 500,
                            step = 1,
                            bigStep = 1,
                            order = 11,
                            width = 1.49,
                            get = function( info )
                                return Hekili.DB.profile.displays[ name ].classic.queue.height
                            end,
                            set = function( info, val )
                                Hekili.DB.profile.displays[ name ].classic.queue.height = val
                            end,
                        },
                    }
                },

                anchorGroup = {
                    type = "group",
                    inline = true,
                    name = "Queued Icon Positioning",
                    order = 22,
                    args = {
                        anchor = {
                            type = 'select',
                            name = 'Anchor To',
                            desc = "Select the point on the primary icon to which the queued icons will attach.",
                            values = anchorPositions,
                            width = 1.49,
                            order = 1,
                            get = function( info )
                                return Hekili.DB.profile.displays[ name ].classic.queue.anchor
                            end,
                            set = function( info, val )
                                Hekili.DB.profile.displays[ name ].classic.queue.anchor = val
                                Hekili:BuildUI()
                            end,
                        },

                        direction = {
                            type = 'select',
                            name = 'Grow Direction',
                            desc = "Select the direction for the icon queue.\n\n"
                                .. "This option generally matches Anchor To selection, but you can specify another direction to make a creative layout.",
                            values = {
                                TOP = 'Up',
                                BOTTOM = 'Down',
                                LEFT = 'Left',
                                RIGHT = 'Right'
                            },
                            width = 1.49,
                            order = 1.1,
                            get = function( info )
                                return Hekili.DB.profile.displays[ name ].classic.queue.direction
                            end,
                            set = function( info, val )
                                Hekili.DB.profile.displays[ name ].classic.queue.direction = val
                                Hekili:BuildUI()
                            end,
                        },

                        spacer01 = {
                            type = "description",
                            name = " ",
                            order = 1.2,
                            width = "full",
                        },

                        offsetX = {
                            type = 'range',
                            name = 'X Offset',
                            desc = "Specify the horizontal offset (in pixels) for the queue, in relation to the anchor point on the primary icon for this display.\n\n"
                                .. "Positive numbers move the queue to the right, negative numbers move it to the left.",
                            min = -100,
                            max = 500,
                            step = 1,
                            width = 1.49,
                            order = 2,
                            get = function( info )
                                return Hekili.DB.profile.displays[ name ].classic.queue.offsetX
                            end,
                            set = function( info, val )
                                Hekili.DB.profile.displays[ name ].classic.queue.offsetX = val
                                Hekili:BuildUI()
                            end,
                        },

                        offsetY = {
                            type = 'range',
                            name = 'Y Offset',
                            desc = "Specify the vertical offset (in pixels) for the queue, in relation to the anchor point on the primary icon for this display.\n\n"
                                .. "Positive numbers move the queue up, negative numbers move it down.",
                            min = -100,
                            max = 500,
                            step = 1,
                            width = 1.49,
                            order = 2.1,
                            get = function( info )
                                return Hekili.DB.profile.displays[ name ].classic.queue.offsetY
                            end,
                            set = function( info, val )
                                Hekili.DB.profile.displays[ name ].classic.queue.offsetY = val
                                Hekili:BuildUI()
                            end,
                        },

                        spacer02 = {
                            type = "description",
                            name = " ",
                            order = 2.2,
                            width = "full",
                        },

                        spacing = {
                            type = 'range',
                            name = 'Icon Spacing',
                            desc = "Select the number of pixels between icons in the queue.",
                            softMin = ( data.classic.queue.direction == "LEFT" or data.classic.queue.direction == "RIGHT" ) and -data.classic.queue.width or -data.classic.queue.height,
                            softMax = ( data.classic.queue.direction == "LEFT" or data.classic.queue.direction == "RIGHT" ) and data.classic.queue.width or data.classic.queue.height,
                            min = -500,
                            max = 500,
                            step = 1,
                            order = 3,
                            width = 2.98,
                            get = function( info )
                                return Hekili.DB.profile.displays[ name ].classic.queue.spacing
                            end,
                            set = function( info, val )
                                Hekili.DB.profile.displays[ name ].classic.queue.spacing = val
                                Hekili:BuildUI()
                            end,
                        },
                    }
                },
            },
        },

        keybindings = {
            type = "group",
            name = "Keybinds",
            desc = "Options for keybinding text on displayed icons.",
            order = 7,

            args = {
                enabled = {
                    type = "toggle",
                    name = "Enabled",
                    order = 1,
                    width = 1.49,
                },

                queued = {
                    type = "toggle",
                    name = "Enabled for Queued Icons",
                    order = 2,
                    width = 1.49,
                    disabled = function () return data.classic.keybindings.enabled == false end,
                },

                pos = {
                    type = "group",
                    inline = true,
                    name = function( info ) rangeIcon( info )
return "Position" end,
                    order = 3,
                    args = {
                        anchor = {
                            type = "select",
                            name = 'Anchor Point',
                            order = 2,
                            width = 1,
                            values = realAnchorPositions
                        },

                        x = {
                            type = "range",
                            name = "X Offset",
                            order = 3,
                            width = 0.99,
                            min = -max( data.classic.primaryWidth, data.classic.queue.width ),
                            max = max( data.classic.primaryWidth, data.classic.queue.width ),
                            disabled = function( info )
                                return false
                            end,
                            step = 1,
                        },

                        y = {
                            type = "range",
                            name = "Y Offset",
                            order = 4,
                            width = 0.99,
                            min = -max( data.classic.primaryHeight, data.classic.queue.height ),
                            max = max( data.classic.primaryHeight, data.classic.queue.height ),
                            step = 1,
                        }
                    }
                },

                textStyle = {
                    type = "group",
                    inline = true,
                    name = "Font and Style",
                    order = 5,
                    args = tableCopy( fontElements ),
                },

                lowercase = {
                    type = "toggle",
                    name = "Use Lowercase",
                    order = 5.1,
                    width = "full",
                },

                separateQueueStyle = {
                    type = "toggle",
                    name = "Use Different Settings for Queue",
                    order = 6,
                    width = "full",
                },

                queuedTextStyle = {
                    type = "group",
                    inline = true,
                    name = "Queued Font and Style",
                    order = 7,
                    hidden = function () return not data.classic.keybindings.separateQueueStyle end,
                    args = {
                        queuedFont = {
                            type = "select",
                            name = "Font",
                            order = 1,
                            width = 1.49,
                            dialogControl = 'LSM30_Font',
                            values = LSM:HashTable("font"),
                        },

                        queuedFontStyle = {
                            type = "select",
                            name = "Style",
                            order = 2,
                            values = fontStyles,
                            width = 1.49
                        },

                        break01 = {
                            type = "description",
                            name = " ",
                            width = "full",
                            order = 2.1
                        },

                        queuedFontSize = {
                            type = "range",
                            name = "Size",
                            order = 3,
                            min = 8,
                            max = 64,
                            step = 1,
                            width = 1.49
                        },

                        queuedColor = {
                            type = "color",
                            name = "Color",
                            order = 4,
                            width = 1.49
                        }
                    },
                },

                queuedLowercase = {
                    type = "toggle",
                    name = "Use Lowercase in Queue",
                    order = 7.1,
                    width = 1.49,
                    hidden = function () return not data.classic.keybindings.separateQueueStyle end,
                },

                cPort = {
                    name = "ConsolePort",
                    type = "group",
                    inline = true,
                    order = 4,
                    args = {
                        cPortOverride = {
                            type = "toggle",
                            name = "Use ConsolePort Buttons",
                            order = 6,
                            width = 1.49,
                        },

                        cPortZoom = {
                            type = "range",
                            name = "ConsolePort Button Zoom",
                            desc = "The ConsolePort button textures generally have a significant amount of blank padding around them. " ..
                                "Zooming in removes some of this padding to help the buttons fit on the icon.  The default is |cFFFFD1000.6|r.",
                            order = 7,
                            min = 0,
                            max = 1,
                            step = 0.01,
                            width = 1.49,
                        },
                    },
                    disabled = function() return ConsolePort == nil end,
                },

            }
        },

        border = {
            type = "group",
            name = "Border",
            desc = "Enable/disable or set the color for icon borders.\n\n" ..
                "You may want to disable this if you use Masque or other tools to skin your Hekili icons.",
            order = 4,

            args = {
                enabled = {
                    type = "toggle",
                    name = "Enabled",
                    desc = "If enabled, each icon in this display will have a thin border.",
                    order = 1,
                    width = "full",
                },

                thickness = {
                    type = "range",
                    name = "Border Thickness",
                    desc = "Determines the thickness (width) of the border.  Default is 1.",
                    softMin = 1,
                    softMax = 20,
                    step = 1,
                    order = 2,
                    width = 1.49,
                },

                fit = {
                    type = "toggle",
                    name = "Border Inside",
                    desc = "If enabled, when borders are enabled, the button's border will fit inside the button (instead of around it).",
                    order = 2.5,
                    width = 1.49
                },

                break01 = {
                    type = "description",
                    name = " ",
                    width = "full",
                    order = 2.6
                },

                coloring = {
                    type = "select",
                    name = "Coloring Mode",
                    desc = "Specify whether to use Class or Custom color borders.\n\nClass-colored borders will automatically change to match the class you are playing.",
                    width = 1.49,
                    order = 3,
                    values = {
                        class = format( "Class |A:WhiteCircle-RaidBlips:16:16:0:0:%d:%d:%d|a #%s", ClassColor.r * 255, ClassColor.g * 255, ClassColor.b * 255, ClassColor:GenerateHexColor():sub( 3, 8 ) ),
                        custom = "Specify a Custom Color"
                    },
                    disabled = function() return data.classic.border.enabled == false end,
                },

                color = {
                    type = "color",
                    name = "Custom Color",
                    desc = "When borders are enabled and the Coloring Mode is set to |cFFFFD100Custom Color|r, the border will use this color.",
                    order = 4,
                    width = 1.49,
                    disabled = function () return data.classic.border.enabled == false or data.classic.border.coloring ~= "custom" end,
                }
            }
        },

        range = {
            type = "group",
            name = "Range",
            desc = "Preferences for range-check warnings, if desired.",
            order = 5,
            args = {
                enabled = {
                    type = "toggle",
                    name = "Enabled",
                    desc = "If enabled, the addon will provide a red warning highlight when you are not in range of your enemy.",
                    width = 1.49,
                    order = 1,
                },

                type = {
                    type = "select",
                    name = 'Range Checking',
                    desc = "Select the kind of range checking and range coloring to be used by this display.\n\n" ..
                        "|cFFFFD100Ability|r - Each ability is highlighted in red if that ability is out of range.\n\n" ..
                        "|cFFFFD100Melee|r - All abilities are highlighted in red if you are out of melee range.\n\n" ..
                        "|cFFFFD100Exclude|r - If an ability is not in-range, it will not be recommended.",
                    values = {
                        ability = "Per Ability",
                        melee = "Melee Range",
                        xclude = "Exclude Out-of-Range"
                    },
                    width = 1.49,
                    order = 2,
                    disabled = function () return data.classic.range.enabled == false end,
                }
            }
        },

        glow = {
            type = "group",
            name = "Glows",
            desc = "Preferences for Blizzard action button glows (not SpellFlash).",
            order = 6,
            args = {
                enabled = {
                    type = "toggle",
                    name = "Enable Overlay Glow",
                    desc = "If enabled, when the ability for the first icon has an active glow (or overlay), it will also glow in this display.",
                    width = 1.49,
                    order = 1,
                },

                queued = {
                    type = "toggle",
                    name = "Enabled for Queued Icons",
                    desc = "If enabled, abilities that have active glows (or overlays) will also glow in your queue.\n\n" ..
                        "This may not be ideal, the glow may no longer be correct by that point in the future.",
                    width = 1.49,
                    order = 2,
                    disabled = function() return data.classic.glow.enabled == false end,
                },

                break01 = {
                    type = "description",
                    name = " ",
                    order = 2.1,
                    width = "full"
                },

                mode = {
                    type = "select",
                    name = "Glow Style",
                    desc = "Select the glow style for your display.",
                    width = 1,
                    order = 3,
                    values = {
                        default = "Default Button Glow",
                        autocast = "AutoCast Shine",
                        pixel = "Pixel Glow",
                    },
                    disabled = function() return data.classic.glow.enabled == false end,
                },

                coloring = {
                    type = "select",
                    name = "Coloring Mode",
                    desc = "Select the coloring mode for this glow effect.\n\nClass-colored borders will automatically change to match the class you are playing.",
                    width = 0.99,
                    order = 4,
                    values = {
                        default = "Use Default Color",
                        class = format( "Class |A:WhiteCircle-RaidBlips:16:16:0:0:%d:%d:%d|a #%s", ClassColor.r * 255, ClassColor.g * 255, ClassColor.b * 255, ClassColor:GenerateHexColor():sub( 3, 8 ) ),
                        custom = "Specify a Custom Color"
                    },
                    disabled = function() return data.classic.glow.enabled == false end,
                },

                color = {
                    type = "color",
                    name = "Glow Color",
                    desc = "Select the custom glow color for your display.",
                    width = 0.99,
                    order = 5,
                    disabled = function() return data.classic.glow.coloring ~= "custom" end,
                },

                break02 = {
                    type = "description",
                    name = " ",
                    order = 10,
                    width = "full",
                },

                highlight = {
                    type = "toggle",
                    name = "Enable Action Highlight",
                    desc = "If enabled, the addon will apply the default highlight when the first recommended item/ability is currently queued.",
                    width = "full",
                    order = 11
                },
            },
        },

        flash = {
            type = "group",
            name = "SpellFlash",
            desc = function ()
                if SF then
                    return "If enabled, the addon can highlight abilities on your action bars when they are recommended for use."
                end
                return "This feature requires the SpellFlashCore addon or library to function properly."
            end,
            order = 8,
            args = {
                warning = {
                    type = "description",
                    name = "These settings are unavailable because the SpellFlashCore addon / library is not installed or is disabled.",
                    order = 0,
                    fontSize = "medium",
                    width = "full",
                    hidden = function () return SF ~= nil end,
                },

                enabled = {
                    type = "toggle",
                    name = "Enabled",
                    desc = "If enabled, the addon will place a colorful glow on the first recommended ability for this display.",

                    width = 1.49,
                    order = 1,
                    hidden = function () return SF == nil end,
                },

                color = {
                    type = "color",
                    name = "Color",
                    desc = "Specify a glow color for the SpellFlash highlight.",
                    order = 2,
                    width = 1.49,
                    hidden = function () return SF == nil end,
                },

                break00 = {
                    type = "description",
                    name = " ",
                    order = 2.1,
                    width = "full",
                    hidden = function () return SF == nil end,
                },

                sample = {
                    type = "description",
                    name = "",
                    image = function() return Hekili.DB.profile.flashTexture end,
                    order = 3,
                    width = 0.3,
                    hidden = function () return SF == nil end,
                },

                flashTexture = {
                    type = "select",
                    name = "Texture",
                    icon =  function() return data.classic.flash.texture or "Interface\\Cooldown\\star4" end,
                    desc = "Your selection will override the SpellFlash texture for all displays' flashes.",
                    order = 3.1,
                    width = 1.19,
                    values = {
                        ["Interface\\AddOns\\Hekili\\Textures\\MonoCircle2"] = "Monochrome Circle Thin",
                        ["Interface\\AddOns\\Hekili\\Textures\\MonoCircle5"] = "Monochrome Circle Thick",
                        ["Interface\\Cooldown\\ping4"] = "Circle",
                        ["Interface\\Cooldown\\star4"] = "Star (Default)",
                        ["Interface\\Cooldown\\starburst"] = "Starburst",
                        ["Interface\\Masks\\CircleMaskScalable"] = "Filled Circle",
                        ["Interface\\Masks\\SquareMask"] = "Filled Square",
                        ["Interface\\Soulbinds\\SoulbindsConduitCollectionsIconMask"] = "Filled Octagon",
                        ["Interface\\Soulbinds\\SoulbindsConduitPendingAnimationMask"] = "Octagon Outline",
                        ["Interface\\Soulbinds\\SoulbindsEnhancedConduitMask"] = "Octagon Thick",
                    },
                    get = function()
                        return Hekili.DB.profile.flashTexture
                    end,
                    set = function( _, val )
                        Hekili.DB.profile.flashTexture = val
                    end,
                    hidden = function () return SF == nil end,
                },

                speed = {
                    type = "range",
                    name = "Speed",
                    desc = "Specify how frequently the flash should restart.  The default is |cFFFFD1000.4s|r.",
                    min = 0.1,
                    max = 2,
                    step = 0.1,
                    order = 3.2,
                    width = 1.49,
                    hidden = function () return SF == nil end,
                },

                break01 = {
                    type = "description",
                    name = " ",
                    order = 4,
                    width = "full",
                    hidden = function () return SF == nil end,
                },

                size = {
                    type = "range",
                    name = "Flash Size",
                    desc = "Specify the size of the SpellFlash glow.  The default size is |cFFFFD100240|r.",
                    order = 5,
                    min = 0,
                    max = 240 * 8,
                    step = 1,
                    width = 1.49,
                    hidden = function () return SF == nil end,
                },

                fixedSize = {
                    type = "toggle",
                    name = "Fixed Size",
                    desc = "If checked, the SpellFlash pulse (grow and shrink) animation will be suppressed.",
                    order = 6,
                    width = 1.49,
                    hidden = function () return SF == nil end,
                },

                break02 = {
                    type = "description",
                    name = " ",
                    order = 7,
                    width = "full",
                    hidden = function () return SF == nil end,
                },

                brightness = {
                    type = "range",
                    name = "Flash Brightness",
                    desc = "Specify the brightness of the SpellFlash glow.  The default brightness is |cFFFFD100100|r.",
                    order = 8,
                    min = 0,
                    max = 100,
                    step = 1,
                    width = 1.49,
                    hidden = function () return SF == nil end,
                },

                fixedBrightness = {
                    type = "toggle",
                    name = "Fixed Brightness",
                    desc = "If checked, the SpellFlash glow will not dim/brighten.",
                    order = 9,
                    width = 1.49,
                    hidden = function () return SF == nil end,
                },

                break03 = {
                    type = "description",
                    name = " ",
                    order = 10,
                    width = "full",
                    hidden = function () return SF == nil end,
                },

                combat = {
                    type = "toggle",
                    name = "Combat Only",
                    desc = "If checked, the addon will only create flashes when you are in combat.",
                    order = 11,
                    width = "full",
                    hidden = function () return SF == nil end,
                },

                suppress = {
                    type = "toggle",
                    name = "Hide Display",
                    desc = "If checked, the addon will not show this display and will make recommendations via SpellFlash only.",
                    order = 12,
                    width = "full",
                    hidden = function () return SF == nil end,
                },

                blink = {
                    type = "toggle",
                    name = "Button Blink",
                    desc = "If enabled, the whole action button will fade in and out.  The default is |cFFFF0000disabled|r.",
                    order = 13,
                    width = "full",
                    hidden = function () return SF == nil end,
                },
            },
        },

        captions = {
            type = "group",
            name = "Captions",
            desc = "Captions are brief descriptions sometimes (rarely) used in action lists to describe why the action is shown.",
            order = 9,
            args = {
                enabled = {
                    type = "toggle",
                    name = "Enabled",
                    desc = "If enabled, when the first ability shown has a descriptive caption, the caption will be shown.",
                    order = 1,
                    width = 1.49,
                },

                queued = {
                    type = "toggle",
                    name = "Enabled for Queued Icons",
                    desc = "If enabled, descriptive captions will be shown for queued abilities, if appropriate.",
                    order = 2,
                    width = 1.49,
                    disabled = function () return data.classic.captions.enabled == false end,
                },

                position = {
                    type = "group",
                    inline = true,
                    name = function( info ) rangeIcon( info ); return "Position" end,
                    order = 3,
                    args = {
                        anchor = {
                            type = "select",
                            name = 'Anchor Point',
                            order = 1,
                            width = 1,
                            values = {
                                TOP = 'Top',
                                BOTTOM = 'Bottom',
                            }
                        },

                        x = {
                            type = "range",
                            name = "X Offset",
                            order = 2,
                            width = 0.99,
                            step = 1,
                        },

                        y = {
                            type = "range",
                            name = "Y Offset",
                            order = 3,
                            width = 0.99,
                            step = 1,
                        },

                        break01 = {
                            type = "description",
                            name = " ",
                            order = 3.1,
                            width = "full",
                        },

                        align = {
                            type = "select",
                            name = "Alignment",
                            order = 4,
                            width = 1.49,
                            values = {
                                LEFT = "Left",
                                RIGHT = "Right",
                                CENTER = "Center"
                            },
                        },
                    }
                },

                textStyle = {
                    type = "group",
                    inline = true,
                    name = "Text",
                    order = 4,
                    args = tableCopy( fontElements ),
                },
            }
        },

        targets = {
            type = "group",
            name = "Targets",
            desc = "A target count indicator can be shown on the display's first recommendation.",
            order = 10,
            args = {
                enabled = {
                    type = "toggle",
                    name = "Enabled",
                    desc = "If enabled, the addon will show the number of active (or virtual) targets for this display.",
                    order = 1,
                    width = "full",
                },

                pos = {
                    type = "group",
                    inline = true,
                    name = function( info ) rangeIcon( info )
return "Position" end,
                    order = 2,
                    args = {
                        anchor = {
                            type = "select",
                            name = "Anchor To",
                            values = realAnchorPositions,
                            order = 1,
                            width = 1,
                        },

                        x = {
                            type = "range",
                            name = "X Offset",
                            min = -max( data.classic.primaryWidth, data.classic.queue.width ),
                            max = max( data.classic.primaryWidth, data.classic.queue.width ),
                            step = 1,
                            order = 2,
                            width = 0.99,
                        },

                        y = {
                            type = "range",
                            name = "Y Offset",
                            min = -max( data.classic.primaryHeight, data.classic.queue.height ),
                            max = max( data.classic.primaryHeight, data.classic.queue.height ),
                            step = 1,
                            order = 2,
                            width = 0.99,
                        }
                    }
                },

                textStyle = {
                    type = "group",
                    inline = true,
                    name = "Text",
                    order = 3,
                    args = tableCopy( fontElements ),
                },
            }
        },

        delays = {
            type = "group",
            name = "Delays",
            desc = "When an ability is recommended some time in the future, a colored indicator or countdown timer can " ..
                "communicate that there is a delay.",
            order = 11,
            args = {
                extend = {
                    type = "toggle",
                    name = "Extend Spiral",
                    desc = "If checked, the primary icon's cooldown spiral will continue until the ability should be used.",
                    width = 1.49,
                    order = 1,
                },

                fade = {
                    type = "toggle",
                    name = "Fade as Unusable",
                    desc = "Fade the primary icon when you should wait before using the ability, similar to when an ability is lacking required resources.",
                    width = 1.49,
                    order = 1.1
                },

                desaturate = {
                    type = "toggle",
                    name = format( "%s Desaturate", NewFeature ),
                    desc = "Desaturate the primary icon when you should wait before using the ability.",
                    width = 1.49,
                    order = 1.15
                },

                break01 = {
                    type = "description",
                    name = " ",
                    order = 1.2,
                    width = "full",
                },

                type = {
                    type = "select",
                    name = "Indicator",
                    desc = "Specify the type of indicator to use when you should wait before casting the ability.",
                    values = {
                        __NA = "No Indicator",
                        ICON = "Show Icon (Color)",
                        TEXT = "Show Text (Countdown)",
                    },
                    width = 1.49,
                    order = 2,
                },

                pos = {
                    type = "group",
                    inline = true,
                    name = function( info ) rangeIcon( info )
return "Position" end,
                    order = 3,
                    args = {
                        anchor = {
                            type = "select",
                            name = 'Anchor Point',
                            order = 2,
                            width = 1,
                            values = realAnchorPositions
                        },

                        x = {
                            type = "range",
                            name = "X Offset",
                            order = 3,
                            width = 0.99,
                            min = -max( data.classic.primaryWidth, data.classic.queue.width ),
                            max = max( data.classic.primaryWidth, data.classic.queue.width ),
                            step = 1,
                        },

                        y = {
                            type = "range",
                            name = "Y Offset",
                            order = 4,
                            width = 0.99,
                            min = -max( data.classic.primaryHeight, data.classic.queue.height ),
                            max = max( data.classic.primaryHeight, data.classic.queue.height ),
                            step = 1,
                        }
                    },
                    disabled = function () return data.classic.delays.type == "__NA" end,
                },

                textStyle = {
                    type = "group",
                    inline = true,
                    name = "Text",
                    order = 4,
                    args = tableCopy( fontElements ),
                    disabled = function () return data.classic.delays.type ~= "TEXT" end,
                },
            }
        },

        indicators = {
            type = "group",
            name = "Indicators",
            desc = "Indicators are small icons that can indicate target-swapping or (rarely) cancelling auras.",
            order = 11,
            args = {
                enabled = {
                    type = "toggle",
                    name = "Enabled",
                    desc = "If enabled, small indicators for target-swapping, aura-cancellation, etc. may appear on your primary icon.",
                    order = 1,
                    width = 1.49,
                },

                queued = {
                    type = "toggle",
                    name = "Enabled for Queued Icons",
                    desc = "If enabled, these indicators will appear on queued icons as well as the primary icon, when appropriate.",
                    order = 2,
                    width = 1.49,
                    disabled = function () return data.classic.indicators.enabled == false end,
                },

                size = {
                    type = "group",
                    inline = true,
                    name = "Appearance",
                    order = 1.5,
                    args = {
                        width = {
                            type = "range",
                            name = "Width",
                            desc = "Specify the width of indicator icons.",
                            min = 8,
                            max = 100,
                            step = 1,
                            width = 1.49,
                            order = 1,
                        },

                        height = {
                            type = "range",
                            name = "Height",
                            desc = "Specify the height of indicator icons.",
                            min = 8,
                            max = 100,
                            step = 1,
                            width = 1.49,
                            order = 2,
                        },

                        spacer01 = {
                            type = "description",
                            name = " ",
                            width = "full",
                            order = 3
                        },

                        zoom = {
                            type = "range",
                            name = "Icon Zoom",
                            desc = "Select the zoom percentage for indicator icon textures. (Roughly 30% will trim off the default Blizzard borders.)",
                            min = 0,
                            softMax = 100,
                            max = 200,
                            step = 1,
                            width = 1.49,
                            order = 4,
                        },

                        keepAspectRatio = {
                            type = "toggle",
                            name = "Keep Aspect Ratio",
                            desc = "When enabled, indicator icons will maintain their original aspect ratio when resized.",
                            width = 1.49,
                            order = 5,
                        },
                    }
                },

                pos = {
                    type = "group",
                    inline = true,
                    name = function( info ) rangeIcon( info )
return "Position" end,
                    order = 2,
                    args = {
                        anchor = {
                            type = "select",
                            name = "Anchor To",
                            values = realAnchorPositions,
                            order = 1,
                            width = 1,
                        },

                        x = {
                            type = "range",
                            name = "X Offset",
                            min = -max( data.classic.primaryWidth, data.classic.queue.width ),
                            max = max( data.classic.primaryWidth, data.classic.queue.width ),
                            step = 1,
                            order = 2,
                            width = 0.99,
                        },

                        y = {
                            type = "range",
                            name = "Y Offset",
                            min = -max( data.classic.primaryHeight, data.classic.queue.height ),
                            max = max( data.classic.primaryHeight, data.classic.queue.height ),
                            step = 1,
                            order = 2,
                            width = 0.99,
                        }
                    }
                },
            }
        },
    }
end

Classic.api = Hekili.DisplayStyleAPI
Hekili:RegisterDisplayStyle( "classic", Classic )
