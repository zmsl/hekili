-- UI.lua
-- Dynamic UI Elements

local addon, ns = ...
local Facade = ns.Facade
local CreateFrame = Facade.CreateFrame
local C_Item, C_PetBattles, C_SpecializationInfo, C_Spell = Facade.C_Item, Facade.C_PetBattles, Facade.C_SpecializationInfo, Facade.C_Spell
local C_SpellActivationOverlay, C_VideoOptions = Facade.C_SpellActivationOverlay, Facade.C_VideoOptions
local GetFramerate, GetTime, HasOverrideActionBar, HasVehicleActionBar = Facade.GetFramerate, Facade.GetTime, Facade.HasOverrideActionBar, Facade.HasVehicleActionBar
local InCombatLockdown, IsInInstance, IsMounted, UnitCanAttack = Facade.InCombatLockdown, Facade.IsInInstance, Facade.IsMounted, Facade.UnitCanAttack
local UnitCastingInfo, UnitChannelInfo, UnitClass, UnitExists = Facade.UnitCastingInfo, Facade.UnitChannelInfo, Facade.UnitClass, Facade.UnitExists
local UnitHasVehicleUI, UnitIsDead, UnitOnTaxi = Facade.UnitHasVehicleUI, Facade.UnitIsDead, Facade.UnitOnTaxi
local Hekili = _G[ addon ]

local Registry = Hekili.Engine.Registry
local Published = Hekili.Engine.Output -- the published displays (the port), indexed by display id
local Status = Published.status

local FindUnitBuffByID, FindUnitDebuffByID = ns.FindUnitBuffByID, ns.FindUnitDebuffByID

-- Atlas/Textures
local AddTexString, GetTexString, AtlasToString, GetAtlasFile, GetAtlasCoords = ns.AddTexString, ns.GetTexString, ns.AtlasToString, ns.GetAtlasFile, ns.GetAtlasCoords

local frameStratas = ns.FrameStratas
local getInverseDirection = ns.getInverseDirection
local multiUnpack = ns.multiUnpack
local orderedPairs = ns.orderedPairs
local round = ns.round

local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo

local floor, format, insert = math.floor, string.format, table.insert

local HasVehicleActionBar, HasOverrideActionBar, IsInPetBattle, UnitHasVehicleUI, UnitOnTaxi = HasVehicleActionBar, HasOverrideActionBar, C_PetBattles.IsInBattle, UnitHasVehicleUI, UnitOnTaxi
local Tooltip = ns.Tooltip

local Masque, MasqueGroup
local _

function Hekili:GetScale()
    return PixelUtil.GetNearestPixelSize( 1, PixelUtil.GetPixelToUIUnitFactor(), 1 )
end


local movementData = {}

local function startScreenMovement(frame)
    movementData.origX,movementData.origY = select( 4, frame:GetPoint() )
    frame:StartMoving()
    movementData.fromX, movementData.fromY = select( 4, frame:GetPoint() )
    frame.Moving = true
end

local function stopScreenMovement(frame)
    local resolution = C_VideoOptions.GetCurrentGameWindowSize()
    local scrW, scrH = resolution.x, resolution.y

    local scale, pScale = Hekili:GetScale(), UIParent:GetScale()

    scrW = scrW / ( scale * pScale )
    scrH = scrH / ( scale * pScale )

    local limitX = ( scrW - frame:GetWidth() ) / 2
    local limitY = ( scrH - frame:GetHeight() ) / 2

    movementData.toX, movementData.toY = select( 4, frame:GetPoint() )
    frame:StopMovingOrSizing()
    frame.Moving = false
    frame:ClearAllPoints()
    frame:SetPoint( "CENTER", nil, "CENTER",
        max(-limitX, min(limitX, movementData.origX + (movementData.toX - movementData.fromX))),
        max(-limitY, min(limitY, movementData.origY + (movementData.toY - movementData.fromY))) )
    Hekili:SaveCoordinates()
end

local function Mover_OnMouseUp(self, btn)
    local obj = self.moveObj or self

    if (btn == "LeftButton" and obj.Moving) then
        stopScreenMovement(obj)
        Hekili:SaveCoordinates()
    elseif btn == "RightButton" then
        if obj:GetName() == "HekiliNotification" then
            LibStub( "AceConfigDialog-3.0" ):SelectGroup( "Hekili", "displays", "nPanel" )
            return
        elseif obj and obj.id then
            LibStub( "AceConfigDialog-3.0" ):SelectGroup( "Hekili", "displays", obj.id )
            return
        end
    end
end

local function Mover_OnMouseDown( self, btn )
    local obj = self.moveObj or self

    if Hekili.Config and btn == "LeftButton" and not obj.Moving then
        startScreenMovement(obj)
    end
end

local function Button_OnMouseUp( self, btn )
    local display = self.display
    local mover = _G[ "HekiliDisplay" .. display ]

    if (btn == "LeftButton" and mover.Moving) then
        stopScreenMovement(mover)

    elseif (btn == "RightButton") then
        if mover.Moving then
            stopScreenMovement(mover)
        end
        local mouseInteract = Hekili.Pause or Hekili.Config
        for i = 1, #ns.UI.Buttons do
            for j = 1, #ns.UI.Buttons[i] do
                ns.UI.Buttons[i][j]:EnableMouse(mouseInteract)
            end
        end
        ns.UI.Notification:EnableMouse( Hekili.Config )
        -- Hekili:SetOption( { "locked" }, true )
        GameTooltip:Hide()

    end

    Hekili:SaveCoordinates()
end

local function Button_OnMouseDown(self, btn)
    local display = self.display
    local mover = _G[ "HekiliDisplay" .. display ]

    if Hekili.Config and btn == "LeftButton" and not mover.Moving then
        startScreenMovement(mover)
    end
end

-- The mover handlers a style sets on its buttons (UI/Styles/Classic.lua).
ns.UI.Button_OnMouseUp, ns.UI.Button_OnMouseDown = Button_OnMouseUp, Button_OnMouseDown

function ns.StartConfiguration( external )
    Hekili.Config = true

    local scaleFactor = Hekili:GetScale()
    local ccolor = RAID_CLASS_COLORS[ select( 2, UnitClass( "player" ) ) ]

    -- Notification Panel
    ns.UI.Notification.Mover = ns.UI.Notification.Mover or CreateFrame( "Frame", "HekiliNotificationMover", ns.UI.Notification, "BackdropTemplate" )
    ns.UI.Notification.Mover:SetAllPoints( HekiliNotification )
    ns.UI.Notification.Mover:SetBackdrop( {
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    } )

    ns.UI.Notification.Mover:SetBackdropColor( 0, 0, 0, .8 )
    ns.UI.Notification.Mover:SetBackdropBorderColor( ccolor.r, ccolor.g, ccolor.b, 1 )
    ns.UI.Notification.Mover:Show()

    local f = ns.UI.Notification.Mover

    if not f.Header then
        f.Header = f:CreateFontString( "HekiliNotificationHeader", "OVERLAY", "GameFontNormal" )
        local path = f.Header:GetFont()
        f.Header:SetFont( path, 18, "OUTLINE" )
    end
    f.Header:SetAllPoints( HekiliNotificationMover )
    f.Header:SetText( "Notifications" )
    f.Header:SetJustifyH( "CENTER" )
    f.Header:Show()

    if HekiliNotificationMover:GetFrameLevel() > HekiliNotification:GetFrameLevel() then
        local orig = HekiliNotificationMover:GetFrameLevel()
        HekiliNotification:SetFrameLevel(orig)
        HekiliNotificationMover:SetFrameLevel(orig-1)
    end

    ns.UI.Notification:EnableMouse( true )
    ns.UI.Notification:SetMovable( true )

    HekiliNotification:SetScript( "OnMouseDown", Mover_OnMouseDown )
    HekiliNotification:SetScript( "OnMouseUp", Mover_OnMouseUp )
    HekiliNotification:SetScript( "OnEnter", function( self )
        local H = Hekili

        if H.Config then
            Tooltip:SetOwner( self, "ANCHOR_TOPRIGHT" )

            Tooltip:SetText( "Hekili: Notifications" )
            Tooltip:AddLine( "Left-click and hold to move.", 1, 1, 1 )
            Tooltip:AddLine( "Right-click to open Notification panel settings.", 1, 1, 1 )
            Tooltip:Show()
        end
    end )
    HekiliNotification:SetScript( "OnLeave", function(self)
        Tooltip:Hide()
    end )

    Hekili:ProfileFrame( "NotificationFrame", HekiliNotification )

    for i, v in pairs( ns.UI.Displays ) do
        if v.Backdrop then
            v.Backdrop:Hide()
        end

        if v.Header then
            v.Header:Hide()
        end

        if ns.UI.Buttons[ i ][ 1 ] and Hekili.DB.profile.displays[ i ] then
            -- if not Hekili:IsDisplayActive( i ) then v:Show() end

            v.Backdrop = v.Backdrop or CreateFrame( "Frame", v:GetName().. "_Backdrop", UIParent, "BackdropTemplate" )
            v.Backdrop:ClearAllPoints()

            if not v:IsAnchoringRestricted() then
                v:EnableMouse( true )
                v:SetMovable( true )

                for id, btn in ipairs( ns.UI.Buttons[ i ] ) do
                    btn:EnableMouse( false )
                end

                local left, right, top, bottom = v.style.Perimeter( v )
                if left and right and top and bottom then
                    v.Backdrop:SetPoint( "LEFT", left, "LEFT", -2, 0 )
                    v.Backdrop:SetPoint( "RIGHT", right, "RIGHT", 2, 0 )
                    v.Backdrop:SetPoint( "TOP", top, "TOP", 0, 2 )
                    v.Backdrop:SetPoint( "BOTTOM", bottom, "BOTTOM", 0, -2 )
                else
                    v.Backdrop:SetWidth( v:GetWidth() + 2 )
                    v.Backdrop:SetHeight( v:GetHeight() + 2 )
                    v.Backdrop:SetPoint( "CENTER", v, "CENTER" )
                end
            end

            v.Backdrop:SetFrameStrata( v:GetFrameStrata() )
            v.Backdrop:SetFrameLevel( v:GetFrameLevel() + 1 )

            v.Backdrop.moveObj = v

            v.Backdrop:SetBackdrop( {
                bgFile = "Interface/Buttons/WHITE8X8",
                edgeFile = "Interface/Buttons/WHITE8X8",
                tile = false,
                tileSize = 0,
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            } )

            local ccolor = RAID_CLASS_COLORS[ select(2, UnitClass("player")) ]

            if Hekili:IsDisplayActive( v.id, true ) then
                v.Backdrop:SetBackdropBorderColor( ccolor.r, ccolor.g, ccolor.b, 1 )
            else
                v.Backdrop:SetBackdropBorderColor( 0.5, 0.5, 0.5, 0.5 )
            end
            v.Backdrop:SetBackdropColor( 0, 0, 0, 0.8 )
            v.Backdrop:Show()

            v.Backdrop:SetScript( "OnMouseDown", Mover_OnMouseDown )
            v.Backdrop:SetScript( "OnMouseUp", Mover_OnMouseUp )
            v.Backdrop:SetScript( "OnEnter", function( self )
                local H = Hekili

                if H.Config then
                    Tooltip:SetOwner( self, "ANCHOR_TOPRIGHT" )

                    Tooltip:SetText( "Hekili: " .. i )
                    Tooltip:AddLine( "Left-click and hold to move.", 1, 1, 1 )
                    Tooltip:AddLine( "Right-click to open " .. i .. " display settings.", 1, 1, 1 )
                    if not H:IsDisplayActive( i, true ) then Tooltip:AddLine( "This display is not currently active.", 0.5, 0.5, 0.5 ) end
                    Tooltip:Show()
                end
            end )
            v.Backdrop:SetScript( "OnLeave", function( self )
                Tooltip:Hide()
            end )
            v:Show()

            if not v.Header then
                v.Header = v.Backdrop:CreateFontString( "HekiliDisplay" .. i .. "Header", "OVERLAY", "GameFontNormal" )
                local path = v.Header:GetFont()
                v.Header:SetFont( path, 18, "OUTLINE" )
            end
            v.Header:ClearAllPoints()
            v.Header:SetAllPoints( v.Backdrop )

            if i == "Defensives" then v.Header:SetText( AtlasToString( "nameplates-InterruptShield" ) )
            elseif i == "Interrupts" then v.Header:SetText( AtlasToString( "voicechat-icon-speaker-mute" ) )
            elseif i == "Cooldowns" then v.Header:SetText( AtlasToString( "chromietime-32x32" ) )
            else v.Header:SetText( i ) end

            v.Header:SetJustifyH("CENTER")
            v.Header:Show()
        else
            v:Hide()
        end
    end

    if not external then
        if not Hekili.OptionsReady then Hekili:RefreshOptions() end

        local ACD = LibStub( "AceConfigDialog-3.0" )
        ACD:SetDefaultSize( "Hekili", 800, 608 )
        ACD:Open( "Hekili" )

        local oFrame = ACD.OpenFrames["Hekili"].frame
        oFrame:SetResizeBounds( 800, 120 )

        ns.OnHideFrame = ns.OnHideFrame or CreateFrame( "Frame" )
        ns.OnHideFrame:SetParent( oFrame )
        ns.OnHideFrame:SetScript( "OnHide", function(self)
            ns.StopConfiguration()
            self:SetScript( "OnHide", nil )
            self:SetParent( nil )
            if not InCombatLockdown() then
                collectgarbage()
                Hekili:UpdateDisplayVisibility()
            else
                C_Timer.After( 0, function() Hekili:UpdateDisplayVisibility() end )
            end
        end )

        if not ns.OnHideFrame.firstTime then
            ACD:SelectGroup( "Hekili", "packs" )
            ACD:SelectGroup( "Hekili", "displays" )
            ACD:SelectGroup( "Hekili", "displays", "Multi" )
            ACD:SelectGroup( "Hekili", "general" )
            ns.OnHideFrame.firstTime = true
        end

        Hekili:ProfileFrame( "CloseOptionsFrame", ns.OnHideFrame )
    end

    Hekili:UpdateDisplayVisibility()
end

function Hekili:OpenConfiguration()
    ns.StartConfiguration()
end

function ns.StopConfiguration()
    Hekili.Config = false

    local scaleFactor = Hekili:GetScale()
    local mouseInteract = Hekili.Pause

    for id, display in pairs( Hekili.DisplayPool ) do
        display:EnableMouse( false )
        if not display:IsAnchoringRestricted() then display:SetMovable( true ) end

        -- v:SetBackdrop( nil )
        if display.Header then
            display.Header:Hide()
        end
        if display.Backdrop then
            display.Backdrop:Hide()
        end

        for i, btn in ipairs( display.Buttons ) do
            btn:EnableMouse( mouseInteract )
            btn:SetMovable( false )
        end
    end

    HekiliNotification:EnableMouse( false )
    HekiliNotification:SetMovable( false )
    HekiliNotification.Mover:Hide()
    -- HekiliNotification.Mover.Header:Hide()
end

local function MasqueUpdate( Addon, Group, SkinID, Gloss, Backdrop, Colors, Disabled )
    if Disabled then
        for dispID, display in ipairs( ns.UI.Buttons ) do
            for btnID, button in ipairs( display ) do
                button.__MSQ_NormalTexture:Hide()
                button.Texture:SetAllPoints( button )
            end
        end
    end
end


do
    ns.UI.Menu = ns.UI.Menu or CreateFrame( "Frame", "HekiliMenu", UIParent, "UIDropDownMenuTemplate" )
    local menu = ns.UI.Menu

    Hekili:ProfileFrame( "HekiliMenu", menu )

    menu.info = {}

    menu.AddButton = UIDropDownMenu_AddButton
    menu.AddSeparator = UIDropDownMenu_AddSeparator

    local function SetDisplayMode( mode )
        Hekili.DB.profile.toggles.mode.value = mode
        if WeakAuras and WeakAuras.ScanEvents then WeakAuras.ScanEvents( "HEKILI_TOGGLE", "mode", mode ) end
        if ns.UI.Minimap then ns.UI.Minimap:RefreshDataText() end

        Hekili:UpdateDisplayVisibility()
        Hekili:ForceUpdate( "HEKILI_TOGGLE", true )
    end

    local function IsDisplayMode( p, mode )
        return Hekili.DB.profile.toggles.mode.value == mode
    end

    local menuData = {
        {
            isTitle = 1,
            text = "Hekili",
            notCheckable = 1,
        },

        {
            text = "Enable",
            func = function () Hekili:Toggle() end,
            checked = function () return Hekili.DB.profile.enabled end,
        },

        {
            text = "Pause",
            func = function () return Hekili:TogglePause() end,
            checked = function () return Hekili.Pause end,
        },

        {
            isSeparator = 1,
        },

        {
            isTitle = 1,
            text = "Display Mode",
            notCheckable = 1,
        },

        {
            text = "Auto",
            func = function () SetDisplayMode( "automatic" ) end,
            checked = function () return IsDisplayMode( p, "automatic" ) end,
        },

        {
            text = "Single",
            func = function () SetDisplayMode( "single" ) end,
            checked = function () return IsDisplayMode( p, "single" ) end,
        },

        {
            text = "AOE",
            func = function () SetDisplayMode( "aoe" ) end,
            checked = function () return IsDisplayMode( p, "aoe" ) end,
        },

        {
            text = "Dual",
            func = function () SetDisplayMode( "dual" ) end,
            checked = function () return IsDisplayMode( p, "dual" ) end,
        },

        {
            text = "Reactive",
            func = function () SetDisplayMode( "reactive" ) end,
            checked = function () return IsDisplayMode( p, "reactive" ) end,
        },

        {
            isSeparator = 1,
        },

        {
            isTitle = 1,
            text = "Toggles",
            notCheckable = 1,
        },

        {
            text = "Cooldowns",
            func = function() Hekili:FireToggle( "cooldowns" ); ns.UI.Minimap:RefreshDataText() end,
            checked = function () return Hekili.DB.profile.toggles.cooldowns.value end,
        },

        {
            text = "Minor CDs",
            func = function() Hekili:FireToggle( "essences" ); ns.UI.Minimap:RefreshDataText() end,
            checked = function () return Hekili.DB.profile.toggles.essences.value end,
        },

        {
            text = "Interrupts",
            func = function() Hekili:FireToggle( "interrupts" ); ns.UI.Minimap:RefreshDataText() end,
            checked = function () return Hekili.DB.profile.toggles.interrupts.value end,
        },

        {
            text = "Defensives",
            func = function() Hekili:FireToggle( "defensives" ); ns.UI.Minimap:RefreshDataText() end,
            checked = function () return Hekili.DB.profile.toggles.defensives.value end,
        },

        {
            text = "Potions",
            func = function() Hekili:FireToggle( "potions" ); ns.UI.Minimap:RefreshDataText() end,
            checked = function () return Hekili.DB.profile.toggles.potions.value end,
        }
    }

    local specsParsed = false
    menu.args = {}

    UIDropDownMenu_SetDisplayMode( menu, "MENU" )

    function menu:initialize( level, list )
        if not level and not list then
            return
        end

        if level == 1 then
            if not specsParsed then
                -- Add specialization toggles where applicable.
                for i, spec in pairs( Registry.Specs() ) do
                    if i > 0 then
                        insert( menuData, {
                            isSeparator = 1,
                            hidden = function () return Status.specID ~= i end,
                        } )
                        insert( menuData, {
                            isTitle = 1,
                            text = spec.name,
                            notCheckable = 1,
                            hidden = function () return Status.specID ~= i end,
                        } )
                        insert( menuData, {
                            text = "|TInterface\\Addons\\Hekili\\Textures\\Cycle:0|t Recommend Target Swaps",
                            tooltipTitle = "|TInterface\\Addons\\Hekili\\Textures\\Cycle:0|t Recommend Target Swaps",
                            tooltipText = "If checked, the |TInterface\\Addons\\Hekili\\Textures\\Cycle:0|t indicator may be displayed which means you should use the ability on a different target.",
                            tooltipOnButton = true,
                            func = function ()
                                local spec = rawget( Hekili.DB.profile.specs, i )
                                if spec then
                                    spec.cycle = not spec.cycle
                                    if Hekili.DB.profile.notifications.enabled then
                                        Hekili:Notify( "Recommend Target Swaps: " .. ( spec.cycle and "ON" or "OFF" ) )
                                    else
                                        Hekili:Print( "Recommend Target Swaps: " .. ( spec.cycle and " |cFF00FF00ENABLED|r." or " |cFFFF0000DISABLED|r." ) )
                                    end
                                end
                            end,
                            checked = function ()
                                local spec = rawget( Hekili.DB.profile.specs, i )
                                return spec.cycle
                            end,
                            hidden = function () return Status.specID ~= i end,
                        } )

                        local potionMenu = {
                            text = "|T967533:0|t Preferred Potion",
                            tooltipTitle = "|T967533:0|t Preferred Potion",
                            tooltipText = "Select the potion you would like to use when the |cFFFFD100Potions|r toggle is enabled.",
                            tooltipOnButton = true,
                            hasArrow = true,
                            menuList = {},
                            notCheckable = true,
                            hidden = function () return Status.specID ~= i end,
                        }

                        for k, v in orderedPairs( Registry.PotionList() ) do
                            insert( potionMenu.menuList, {
                                text = v,
                                func = function ()
                                    Hekili.DB.profile.specs[ Status.specID ].potion = k
                                    for _, display in pairs( Hekili.DisplayPool ) do
                                        display:OnEvent( "HEKILI_MENU" )
                                    end
                                end,
                                checked = function ()
                                    return Hekili.DB.profile.specs[ Status.specID ].potion == k
                                end,
                            } )
                        end

                        insert( menuData, potionMenu )

                        -- Check for Toggles.
                        for n, setting in pairs( spec.settings ) do
                            if setting.info and ( not setting.info.arg or setting.info.arg() ) then
                                if setting.info.type == "toggle" then
                                    local name = type( setting.info.name ) == "function" and setting.info.name() or setting.info.name
                                    local submenu
                                    submenu = {
                                        text = name,
                                        tooltipTitle = name,
                                        tooltipText = type( setting.info.desc ) == "function" and setting.info.desc() or setting.info.desc,
                                        tooltipOnButton = true,
                                        func = function ()
                                            menu.args[1] = setting.name
                                            setting.info.set( menu.args, not setting.info.get( menu.args ) )

                                            local nm = type( setting.info.name ) == "function" and setting.info.name() or setting.info.name

                                            if Hekili.DB.profile.notifications.enabled then
                                                Hekili:Notify( nm .. ": " .. ( setting.info.get( menu.args ) and "ON" or "OFF" ) )
                                            else
                                                Hekili:Print( nm .. ": " .. ( setting.info.get( menu.args ) and " |cFF00FF00ENABLED|r." or " |cFFFF0000DISABLED|r." ) )
                                            end

                                            submenu.text = nm
                                            submenu.tooltipTitle = nm
                                            submenu.tooltipText = type( setting.info.desc ) == "function" and setting.info.desc() or setting.info.desc
                                        end,
                                        checked = function ()
                                            menu.args[1] = setting.name
                                            return setting.info.get( menu.args )
                                        end,
                                        hidden = function () return Status.specID ~= i end,
                                    }
                                    insert( menuData, submenu )

                                elseif setting.info.type == "select" then
                                    local name = type( setting.info.name ) == "function" and setting.info.name() or setting.info.name
                                    local submenu
                                    submenu = {
                                        text = name,
                                        tooltipTitle = name,
                                        tooltipText = type( setting.info.desc ) == "function" and setting.info.desc() or setting.info.desc,
                                        tooltipOnButton = true,
                                        hasArrow = true,
                                        menuList = {},
                                        notCheckable = true,
                                        hidden = function () return Status.specID ~= i end,
                                    }

                                    local values = setting.info.values
                                    if type( values ) == "function" then values = values() end

                                    if values then
                                        if setting.info.sorting then
                                            for _, k in orderedPairs( setting.info.sorting ) do
                                                local v = values[ k ]
                                                insert( submenu.menuList, {
                                                    text = v,
                                                    func = function ()
                                                        menu.args[1] = setting.name
                                                        setting.info.set( menu.args, k )

                                                        local nm = type( setting.info.name ) == "function" and setting.info.name() or setting.info.name
                                                        submenu.text = nm
                                                        submenu.tooltipTitle = nm
                                                        submenu.tooltipText = type( setting.info.desc ) == "function" and setting.info.desc() or setting.info.desc

                                                        for k, v in pairs( Hekili.DisplayPool ) do
                                                            v:OnEvent( "HEKILI_MENU" )
                                                        end
                                                    end,
                                                    checked = function ()
                                                        menu.args[1] = setting.name
                                                        return setting.info.get( menu.args ) == k
                                                    end,
                                                    hidden = function () return Status.specID ~= i end,
                                                } )
                                            end
                                        else
                                            for k, v in orderedPairs( values ) do
                                                insert( submenu.menuList, {
                                                    text = v,
                                                    func = function ()
                                                        menu.args[1] = setting.name
                                                        setting.info.set( menu.args, k )

                                                        local nm = type( setting.info.name ) == "function" and setting.info.name() or setting.info.name
                                                        submenu.text = nm
                                                        submenu.tooltipTitle = nm
                                                        submenu.tooltipText = type( setting.info.desc ) == "function" and setting.info.desc() or setting.info.desc

                                                        for k, v in pairs( Hekili.DisplayPool ) do
                                                            v:OnEvent( "HEKILI_MENU" )
                                                        end
                                                    end,
                                                    checked = function ()
                                                        menu.args[1] = setting.name
                                                        return setting.info.get( menu.args ) == k
                                                    end,
                                                    hidden = function () return Status.specID ~= i end,
                                                } )
                                            end
                                        end
                                    end

                                    insert( menuData, submenu )

                                elseif setting.info.type == "range" and type( setting.info.max or setting.info.softMax ) == "number" then -- no numeric ceiling: no slider

                                    local submenu = {
                                        text = type( setting.info.name ) == "function" and setting.info.name() or setting.info.name,
                                        tooltipTitle = type( setting.info.name ) == "function" and setting.info.name() or setting.info.name,
                                        tooltipText = type( setting.info.desc ) == "function" and setting.info.desc() or setting.info.desc,
                                        tooltipOnButton = true,
                                        notCheckable = true,
                                        hidden = function () return Status.specID ~= i end,
                                        hasArrow = true,
                                        menuList = {}
                                    }

                                    local slider = {
                                        text = type( setting.info.name ) == "function" and setting.info.name() or setting.info.name,
                                        tooltipTitle = type( setting.info.name ) == "function" and setting.info.name() or setting.info.name,
                                        tooltipText = type( setting.info.desc ) == "function" and setting.info.desc() or setting.info.desc,
                                        tooltipOnButton = true,
                                        notCheckable = true,
                                        hidden = function () return Status.specID ~= i end,
                                    }
                                    local cn = "HekiliSpec" .. i .. "Option" .. n
                                    local cf = CreateFrame( "Frame", cn, UIParent, "HekiliPopupDropdownRangeTemplate" )

                                    cf.Slider:SetAccessorFunction( function()
                                        menu.args[1] = setting.name
                                        return setting.info.get( menu.args )
                                    end )

                                    cf.Slider:SetMutatorFunction( function( val )
                                        menu.args[1] = setting.name
                                        return setting.info.set( menu.args, val )
                                    end )

                                    cf.Slider:SetMinMaxValues( setting.info.min or setting.info.softMin or 0, setting.info.max or setting.info.softMax )
                                    cf.Slider:SetValueStep( setting.info.step or 1 )
                                    cf.Slider:SetObeyStepOnDrag( true )

                                    cf.Slider:SetScript( "OnEnter", function( self )
                                        local tooltip = GetAppropriateTooltip()
                                        tooltip:SetOwner( cf.Slider, "ANCHOR_RIGHT", 0, 2 )
                                        GameTooltip_SetTitle( tooltip, slider.tooltipTitle )
                                        GameTooltip_AddNormalLine( tooltip, slider.tooltipText, true )
                                        tooltip:Show()
                                    end )

                                    cf.Slider:SetScript( "OnLeave", function( self )
                                        GameTooltip:Hide()
                                    end )

                                    slider.customFrame = cf

                                    insert( submenu.menuList, slider )

                                    --[[ local low, high, step = setting.info.min, setting.info.max, setting.info.step
                                    local fractional, factor = step < 1, 1 / step

                                    if fractional then
                                        low = low * factor
                                        high = high * factor
                                        step = step * factor
                                    end

                                    if ceil( ( high - low ) / step ) > 20 then
                                        step = ceil( ( high - low ) / 20 )
                                        if step % ( setting.info.step or 1 ) ~= 0 then
                                            step = step - ( step % ( setting.info.step or 1 ) )
                                        end
                                    end

                                    for j = low, high, step do
                                        local actual = j / factor
                                        insert( submenu.menuList, {
                                            text = tostring( actual ),
                                            func = function ()
                                                menu.args[1] = setting.name
                                                setting.info.set( menu.args, actual )

                                                local name = type( setting.info.name ) == "function" and setting.info.name() or setting.info.name

                                                if Hekili.DB.profile.notifications.enabled then
                                                    Hekili:Notify( name .. " set to |cFF00FF00" .. actual .. "|r." )
                                                else
                                                    Hekili:Print( name .. " set to |cFF00FF00" .. actual .. "|r." )
                                                end
                                            end,
                                            checked = function ()
                                                menu.args[1] = setting.name
                                                return setting.info.get( menu.args ) == actual
                                            end,
                                            hidden = function () return Status.specID ~= i end,
                                        } )
                                    end ]]

                                    insert( menuData, submenu )
                                end
                            end
                        end
                    end
                end
                specsParsed = true
            end
        end

        local use = list or menuData
        local classic = Hekili.IsClassic()

        for i, data in ipairs( use ) do
            data.classicChecks = classic

            if not data.hidden or ( type( data.hidden ) == 'function' and not data.hidden() ) then
                if data.isSeparator then
                    menu.AddSeparator( level )
                else
                    menu.AddButton( data, level )
                end
            end
        end
    end
end


-- The addon compartment entry, the LDB data object and the minimap button (Core's OnInitialize calls this where
-- it built them before, so the order is unchanged).
function Hekili:CreateLaunchers()
    local LDB = LibStub( "LibDataBroker-1.1", true )
    local LDBIcon = LDB and LibStub( "LibDBIcon-1.0", true )

    Hekili_OnAddonCompartmentClick = function( btn, arg1, arg2, checked, button )
        button = button or arg1
        if button == "RightButton" then ns.StartConfiguration()
        else
            ToggleDropDownMenu( 1, nil, ns.UI.Menu, "cursor", 8, 5 )
        end
        GameTooltip:Hide()
    end

    local function GetDataText()
        local p = Hekili.DB.profile
        local m = p.toggles.mode.value
        local color = "FFFFD100"

        if p.toggles.essences.override then
            -- Don't show Essences here if it's overridden by CDs anyway?
            return format( "|c%s%s|r %sCD|r %sInt|r %sDef|r", color,
                m == "single" and "ST" or ( m == "aoe" and "AOE" or ( m == "dual" and "Dual" or ( m == "reactive" and "React" or "Auto" ) ) ),
                p.toggles.cooldowns.value and "|cFF00FF00" or "|cFFFF0000",
                p.toggles.interrupts.value and "|cFF00FF00" or "|cFFFF0000",
                p.toggles.defensives.value and "|cFF00FF00" or "|cFFFF0000" )
        else
            return format( "|c%s%s|r %sCD|r %smCD|r %sInt|r",
                color,
                m == "single" and "ST" or ( m == "aoe" and "AOE" or ( m == "dual" and "Dual" or ( m == "reactive" and "React" or "Auto" ) ) ),
                p.toggles.cooldowns.value and "|cFF00FF00" or "|cFFFF0000",
                p.toggles.essences.value and "|cFF00FF00" or "|cFFFF0000",
                p.toggles.interrupts.value and "|cFF00FF00" or "|cFFFF0000" )
        end
    end

    Hekili_OnAddonCompartmentEnter = function( addonName, button )
        GameTooltip:SetOwner( AddonCompartmentFrame )
        GameTooltip:AddDoubleLine( "Hekili", GetDataText() )
        GameTooltip:AddLine( "|cFFFFFFFFLeft-click to make quick adjustments.|r" )
        GameTooltip:AddLine( "|cFFFFFFFFRight-click to open the options interface.|r" )
        GameTooltip:Show()
    end

    Hekili_OnAddonCompartmentLeave = function( addonName, button )
        GameTooltip:Hide()
    end

    AddonCompartmentFrame:RegisterAddon({
        text = "Hekili",
        icon = "Interface\\AddOns\\Hekili\\Textures\\LOGO-ORANGE.blp",
        registerForAnyClick = true,
        notCheckable = true,
        func = Hekili_OnAddonCompartmentClick,
        funcOnEnter = Hekili_OnAddonCompartmentEnter,
        funcOnLeave = Hekili_OnAddonCompartmentLeave
    } )

    if LDB then
        ns.UI.Minimap = ns.UI.Minimap or LDB:NewDataObject( "Hekili", {
            type = "data source",
            text = "Hekili",
            icon = "Interface\\ICONS\\spell_nature_bloodlust",
            OnClick = Hekili_OnAddonCompartmentClick,
            OnEnter = function( self )
                GameTooltip:SetOwner( self )
                GameTooltip:AddDoubleLine( "Hekili", ns.UI.Minimap.text )
                GameTooltip:AddLine( "|cFFFFFFFFLeft-click to make quick adjustments.|r" )
                GameTooltip:AddLine( "|cFFFFFFFFRight-click to open the options interface.|r" )
                GameTooltip:Show()
            end,
            OnLeave = Hekili_OnAddonCompartmentLeave
        } )

        function ns.UI.Minimap:RefreshDataText()
            self.text = GetDataText()
        end

        ns.UI.Minimap:RefreshDataText()

        if LDBIcon then
            LDBIcon:Register( "Hekili", ns.UI.Minimap, self.DB.profile.iconStore )
        end
    end
end





do
    ns.UI.Displays = ns.UI.Displays or {}
    local dPool = ns.UI.Displays
    Hekili.DisplayPool = dPool

    -- Every display's subscriber to the engine's publishes (Engine/Output.lua), one function so a rebuilt display
    -- resubscribes the same one; the draw happens on the display's next OnUpdate.
    local function onPublish( name )
        dPool[ name ].NewRecommendations = true
    end

    -- A custom display has no engine output: it draws this empty one (stock gave it an empty queue).
    local noOutput = { version = 0, count = 0, recs = {} }

    -- Unsubscribed: hide the icons and draw nothing until the next publish, so a re-shown display starts blank
    -- (stock cleared every queue each cycle) instead of showing the set it last drew.
    local function unsubscribe( d )
        local out = Published[ d.id ]
        if out then Hekili.Engine.Unsubscribe( d.id, d.OnPublish ) end
        d.blankVersion = ( out or noOutput ).version
        d.style.Clear( d )
    end

    local alphaUpdateEvents = {
        PET_BATTLE_OPENING_START = 1,
        PET_BATTLE_CLOSE = 1,
        BARBER_SHOP_OPEN = 1,
        BARBER_SHOP_CLOSE = 1,

        PLAYER_GAINS_VEHICLE_DATA = 1,
        PLAYER_LOSES_VEHICLE_DATA = 1,
        UNIT_ENTERING_VEHICLE = 1,
        UNIT_ENTERED_VEHICLE = 1,
        UNIT_EXITED_VEHICLE = 1,
        UNIT_EXITING_VEHICLE = 1,
        VEHICLE_ANGLE_SHOW = 1,
        VEHICLE_UPDATE = 1,
        UPDATE_VEHICLE_ACTIONBAR = 1,
        UPDATE_OVERRIDE_ACTIONBAR = 1,
        CLIENT_SCENE_OPENED = 1,
        CLIENT_SCENE_CLOSED = 1,
        -- UNIT_FLAGS = 1,

        PLAYER_TARGET_CHANGED = 1,

        PLAYER_ENTERING_WORLD = 1,
        PLAYER_REGEN_ENABLED = 1,
        PLAYER_REGEN_DISABLED = 1,

        ACTIVE_TALENT_GROUP_CHANGED = 1,

        ZONE_CHANGED = 1,
        ZONE_CHANGED_INDOORS = 1,
        ZONE_CHANGED_NEW_AREA = 1,

        PLAYER_CONTROL_LOST = 1,
        PLAYER_CONTROL_GAINED = 1,

        PLAYER_MOUNT_DISPLAY_CHANGED = 1,
        UPDATE_ALL_UI_WIDGETS = 1,
    }

    local kbEvents = {
        -- ACTIONBAR_SLOT_CHANGED = 1,
        ACTIONBAR_PAGE_CHANGED = 1,
        ACTIONBAR_UPDATE_STATE = 1,
        SPELLS_CHANGED = 1,
        UPDATE_SHAPESHIFT_FORM = 1,
    }

    local flashEvents = {
        -- This unregisters flash frames in SpellFlash.
        ACTIONBAR_SHOWGRID = 1,

        -- These re-register flash frames in SpellFlash (after 0.5 - 1.0s).
        ACTIONBAR_HIDEGRID = 1,
        LEARNED_SPELL_IN_SKILL_LINE = 1,
        CHARACTER_POINTS_CHANGED = 1,
        ACTIVE_TALENT_GROUP_CHANGED = 1,
        UPDATE_MACROS = 1,
        VEHICLE_UPDATE = 1,
    }
    ns.UI.FlashEvents = flashEvents -- the display registers them; classic's OnGameEvent pauses its flash on them

    -- Opportunity for Performance Preference, maybe.
    local pulseDisplay = 0.25
    local function CalculateAlpha( id )
        if IsInPetBattle() or Hekili.Barber or Hekili.ClientScene or UnitHasVehicleUI( "player" ) or HasVehicleActionBar() or HasOverrideActionBar() or UnitOnTaxi( "player" ) or not Hekili:IsDisplayActive( id ) then
            return 0
        end

        local prof = Hekili.DB.profile
        local conf = prof.displays[ id ]
        local spec = Status.specID and prof.specs[ Status.specID ]
        local aoe  = spec and spec.aoe or 3

        local _, zoneType = IsInInstance()

        if not conf.enabled then
            return 0

        elseif id == "AOE" and Hekili:GetToggleState( "mode" ) == "reactive" and Hekili:GetNumTargets() < aoe then
            return 0

        elseif zoneType == "pvp" or zoneType == "arena" then
            if not conf.visibility.advanced then return conf.visibility.pvp.alpha end

            if conf.visibility.pvp.hideMounted and IsMounted() then return 0 end

            if conf.visibility.pvp.combatTarget > 0 and Status.combat and UnitExists( "target" ) and not UnitIsDead( "target" ) and UnitCanAttack( "player", "target" ) then
                return conf.visibility.pvp.combatTarget
            elseif conf.visibility.pvp.combat > 0 and Status.combat then
                return conf.visibility.pvp.combat
            elseif conf.visibility.pvp.target > 0 and UnitExists( "target" ) and not UnitIsDead( "target" ) and UnitCanAttack( "player", "target" ) then
                return conf.visibility.pvp.target
            elseif conf.visibility.pvp.always > 0 then
                return conf.visibility.pvp.always
            end

            return 0
        end

        if not conf.visibility.advanced then return conf.visibility.pve.alpha end

        if conf.visibility.pve.hideMounted and IsMounted() then return 0 end

        if conf.visibility.pve.combatTarget > 0 and Status.combat and UnitExists( "target" ) and not UnitIsDead( "target" ) and UnitCanAttack( "player", "target" ) then
            return conf.visibility.pve.combatTarget
        elseif conf.visibility.pve.combat > 0 and Status.combat then
            return conf.visibility.pve.combat
        elseif conf.visibility.pve.target > 0 and UnitExists( "target" ) and not UnitIsDead( "target" ) and UnitCanAttack( "player", "target" ) then
            return conf.visibility.pve.target
        elseif conf.visibility.pve.always > 0 then
            return conf.visibility.pve.always
        end

        return 0
    end

    local numDisplays = 0

    -- The engine raises TARGET_COUNT_CHANGED (Targets.lua); registered on the all-specs spec so a spec change, which
    -- rebuilds the spec hooks without rebuilding the UI, keeps it.
    Registry.Specs()[ 0 ]:RegisterHook( "TARGET_COUNT_CHANGED", function()
        if Hekili:GetToggleState( "mode" ) == "reactive" then HekiliDisplayAOE:UpdateAlpha() end
    end, true )

    -- Visibility reads the spec and combat from Engine.Output.status, which the engine publishes from its next update
    -- (after PLAYER_REGEN_* or a spec change ran UpdateAlpha/UpdateDisplayVisibility): redo them when either moves.
    local seenSpec, seenCombat
    Hekili.Engine.Subscribe( "status", function( _, _, st )
        if st.specID ~= seenSpec then
            seenSpec, seenCombat = st.specID, st.combat
            Hekili:UpdateDisplayVisibility()
        elseif st.combat ~= seenCombat then
            seenCombat = st.combat
            for _, d in pairs( dPool ) do d:UpdateAlpha() end
        end
    end, true )

    -- Binds the display's style and builds it; the list it returns is the display's buttons (ns.UI.Buttons[ id ]).
    -- No style named (a profile older than styles) draws classic; an unknown name draws classic and says so. A switch
    -- clears the old style first, so nothing it drew stays on screen.
    local function bindStyle( d, conf )
        local style = ns.UI.Styles[ conf.style ]
        if not style then
            if conf.style ~= nil then
                Hekili:Notify( "Display " .. d.id .. ": unknown style '" .. tostring( conf.style ) .. "', drawn as classic." )
            end
            style = ns.UI.Styles.classic
        end
        if d.style and d.style ~= style then d.style.Clear( d ) end
        d.style = style
        d.styleState = d.styleState or {} -- per-display scratch, owned by the style
        d.styleFrames = d.styleFrames or {} -- per style name, the frames it built (WoW cannot free frames)
        ns.UI.Buttons[ d.id ] = d.style.Build( d, conf )
        d.Buttons = ns.UI.Buttons[ d.id ]
    end

    function Hekili:CreateDisplay( id )
        local conf = rawget( self.DB.profile.displays, id )
        if not conf then return end

        if not dPool[ id ] then
            numDisplays = numDisplays + 1
            dPool[ id ] = CreateFrame( "Frame", "HekiliDisplay" .. id, UIParent )
            dPool[ id ].index = numDisplays

            Hekili:ProfileFrame( "HekiliDisplay" .. id, dPool[ id ] )
        end
        local d = dPool[ id ]

        d.id = id
        d.alpha = 0
        d.numIcons = conf.numIcons
        d.firstForce = 0

        local scale = self:GetScale()
        local border = 2

        d:SetSize( scale * ( border + ( conf.primaryWidth or 50 ) ), scale * ( border + ( conf.primaryHeight or 50 ) ) )
        --[[ d:SetIgnoreParentScale( true )
        d:SetScale( UIParent:GetScale() ) ]]
        d:ClearAllPoints()

        d:SetPoint( "CENTER", UIParent, "CENTER", conf.x or 0, conf.y or -225 )
        d:SetParent( UIParent )

        d:SetFrameStrata( conf.frameStrata or "MEDIUM" )
        d:SetFrameLevel( conf.frameLevel or ( 10 * d.index ) )

        if not d:IsAnchoringRestricted() then
            d:SetClampedToScreen( true )
            d:EnableMouse( false )
            d:SetMovable( true )
        end

        d.OnPublish = onPublish


        function d:OnUpdate( elapsed )
            local out = Published[ self.id ] or noOutput
            if not Hekili.PLAYER_ENTERING_WORLD then
                return
            end

            local profile = Hekili.DB.profile
            local conf = profile.displays[ self.id ]

            self.timer = ( self.timer or 0 ) - elapsed
            self.alphaCheck = self.alphaCheck - elapsed

            if self.alphaCheck <= 0 then
                self.alphaCheck = 0.5
                self:UpdateAlpha()
            end

            local style = self.style
            style.Tick( self, conf, out, GetTime(), elapsed )

            if self.NewRecommendations or self.timer < 0 then
                self.timer = pulseDisplay
                style.Draw( self, conf, out, Status )
            end
        end

        Hekili:ProfileCPU( "HekiliDisplay" .. id .. ":OnUpdate", d.OnUpdate )

        function d:UpdateAlpha()
            if not self.Active then
                self:SetAlpha( 0 )
                self:Hide()
                self.alpha = 0
                unsubscribe( self )
                return
            end

            local preAlpha = self.alpha or 0
            local newAlpha = CalculateAlpha( self.id )

            if preAlpha > 0 and newAlpha == 0 then
                -- self:Deactivate()
                self:SetAlpha( 0 )
                self.alphaCheck = 0.5
            else
                if preAlpha == 0 and newAlpha > 0 then
                    Hekili:ForceUpdate( "DISPLAY_ALPHA_CHANGED:" .. d.id .. ":" .. preAlpha .. ":" .. newAlpha .. ":" .. GetTime() )
                end
                self:SetAlpha( newAlpha )
                self:Show()
            end

            self.alpha = newAlpha

            -- Subscribed (the engine computes this display) exactly while Active and visible.
            if newAlpha == 0 then unsubscribe( self )
            elseif Published[ self.id ] then Hekili.Engine.Subscribe( self.id, self.OnPublish ) end
        end

        function d:OnEvent( event, ... )
            local conf = Hekili.DB.profile.displays[ self.id ]

            local init = debugprofilestop()

            if kbEvents[ event ] then
                self.style.UpdateKeybindings( self )

            elseif alphaUpdateEvents[ event ] then
                if event == "CLIENT_SCENE_OPENED" then
                    if ... == 1 then -- Minigame.
                        Hekili.ClientScene = true
                    end
                elseif event == "CLIENT_SCENE_CLOSED" then
                    Hekili.ClientScene = nil
                end

                self:UpdateAlpha()

            end

            self.style.OnGameEvent( self, conf, event, ... )

            local finish = debugprofilestop()

            if self.eventTime then
                local newTime = self.eventTime * self.eventCount + finish - init
                self.eventCount = self.eventCount + 1
                self.eventTime = newTime / self.eventCount

                if finish - init > self.eventMax then
                    self.eventMax = finish - init
                    self.eventMaxType = event
                end
            else
                self.eventCount = 1
                self.eventTime = finish - init
                self.eventMax = finish - init
                self.eventMaxType = event
            end
        end

        Hekili:ProfileCPU( "HekiliDisplay" .. id .. ":OnEvent", d.OnEvent )

        function d:Activate()
            if not self.Active then
                self.Active = true

                self.NewRecommendations = true

                self.alphaCheck = 0
                self.auraTimer = 0
                self.glowTimer = 0
                self.recTimer = 0
                self.refreshTimer = 0
                self.targetTimer = 0

                self.lastUpdate = 0

                self:SetScript( "OnUpdate", self.OnUpdate )
                self:SetScript( "OnEvent", self.OnEvent )

                if not self.Initialized then
                    -- Update Cooldown Wheels.
                    -- self:RegisterEvent( "ACTIONBAR_UPDATE_USABLE" )
                    -- self:RegisterEvent( "ACTIONBAR_UPDATE_COOLDOWN" )
                    -- self:RegisterEvent( "SPELL_UPDATE_COOLDOWN" )
                    -- self:RegisterEvent( "SPELL_UPDATE_USABLE" )

                    -- Show/Hide Overlay Glows.
                    self:RegisterEvent( "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" )
                    self:RegisterEvent( "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" )

                    -- Recalculate Alpha/Visibility.
                    for e in pairs( alphaUpdateEvents ) do
                        self:RegisterEvent( e )
                    end

                    -- Recheck spell displays if spells have changed.
                    self:RegisterEvent( "SPELLS_CHANGED" )
                    self:RegisterEvent( "CURRENT_SPELL_CAST_CHANGED" )

                    -- Update keybindings.
                    for k in pairs( kbEvents ) do
                        self:RegisterEvent( k )
                    end

                    for k in pairs( flashEvents ) do
                        self:RegisterEvent( k )
                    end

                    self.Initialized = true
                end

                -- Hekili:ProcessHooks( self.id )
            end
        end

        function d:Deactivate()
            self.Active = false

            self:SetScript( "OnUpdate", nil )
            self:SetScript( "OnEvent", nil )

            self.style.Clear( self )
        end


        bindStyle( d, conf )
    end


    function Hekili:CreateCustomDisplay( id )
        local conf = rawget( self.DB.profile.displays, id )
        if not conf then return end

        dPool[ id ] = dPool[ id ] or CreateFrame( "Frame", "HekiliDisplay" .. id, UIParent )
        local d = dPool[ id ]
        self:ProfileFrame( "HekiliDisplay" .. id, d )

        d.id = id

        local scale = self:GetScale()
        local border = 2

        d:SetSize( scale * ( border + conf.primaryWidth ), scale * (border + conf.primaryHeight ) )
        d:SetPoint( "CENTER", nil, "CENTER", conf.x, conf.y )
        d:SetFrameStrata( "MEDIUM" )
        d:SetClampedToScreen( true )
        d:EnableMouse( false )
        d:SetMovable( true )

        d.Activate = HekiliDisplayPrimary.Activate
        d.Deactivate = HekiliDisplayPrimary.Deactivate
        d.UpdateAlpha = HekiliDisplayPrimary.UpdateAlpha

        bindStyle( d, conf )
    end

    local dispActive = {}
    local listActive = {}
    local actsActive = {}

    function Hekili:UpdateDisplayVisibility()
        local profile = self.DB.profile
        local displays = ns.UI.Displays

        for key in pairs( dispActive ) do
            dispActive[ key ] = nil
        end

        for list in pairs( listActive ) do
            listActive[ list ] = nil
        end

        for a in pairs( actsActive ) do
            actsActive[ a ] = nil
        end

        local specEnabled = GetSpecialization()
        specEnabled = specEnabled and GetSpecializationInfo( specEnabled )

        if Registry.Specs()[ specEnabled ] then
            specEnabled = specEnabled and rawget( profile.specs, specEnabled )
            specEnabled = specEnabled and rawget( specEnabled, "enabled" ) or false
        else
            specEnabled = false
        end

        if profile.enabled and specEnabled then
            for i, display in pairs( profile.displays ) do
                if display.enabled then
                    if i == 'AOE' then
                        dispActive[i] = ( profile.toggles.mode.value == 'dual' or profile.toggles.mode.value == "reactive" ) and 1 or nil
                    elseif i == 'Interrupts' then
                        dispActive[i] = ( profile.toggles.interrupts.value and profile.toggles.interrupts.separate ) and 1 or nil
                    elseif i == 'Defensives' then
                        dispActive[i] = ( profile.toggles.defensives.value and profile.toggles.defensives.separate ) and 1 or nil
                    elseif i == 'Cooldowns' then
                        dispActive[i] = ( profile.toggles.cooldowns.value and profile.toggles.cooldowns.separate ) and 1 or nil
                    else
                        dispActive[i] = 1
                    end

                    if dispActive[i] == nil and self.Config then
                        dispActive[i] = 2
                    end

                    if dispActive[i] and displays[i] then
                        if not displays[i].Active then displays[i]:Activate() end
                        displays[i].NewRecommendations = true
                    end
                else
                    if displays[i] and displays[i].Active then
                        displays[i]:Deactivate()
                    end
                end
            end

            for packName, pack in pairs( profile.packs ) do
                if pack.spec == 0 or pack.spec == Status.specID then
                    for listName, list in pairs( pack.lists ) do
                        listActive[ packName .. ":" .. listName ] = true

                        -- NYI:  We can cache if abilities are disabled here as well to reduce checking in ProcessHooks.
                        for a, entry in ipairs( list ) do
                            if entry.enabled and entry.action then
                                actsActive[ packName .. ":" .. listName .. ":" .. a ] = true
                            end
                        end
                    end
                end
            end
        else
            for _, display in pairs( displays ) do
                if display.Active then
                    display:Deactivate()
                end
            end
        end

        for i, d in pairs( displays ) do
            d:UpdateAlpha()
        end
    end

    function Hekili:ReviewPacks()
        local profile = self.DB.profile

        for list in pairs( listActive ) do
            listActive[ list ] = nil
        end

        for a in pairs( actsActive ) do
            actsActive[ a ] = nil
        end

        for packName, pack in pairs( profile.packs ) do
            if pack.spec == 0 or pack.spec == Status.specID then
                for listName, list in pairs( pack.lists ) do
                    listActive[ packName .. ":" .. listName ] = true

                    -- NYI:  We can cache if abilities are disabled here as well to reduce checking in ProcessHooks.
                    for a, entry in ipairs( list ) do
                        if entry.enabled and entry.action and Registry.Abilities()[ entry.action ] then
                            actsActive[ packName .. ":" .. listName .. ":" .. a ] = true
                        end
                    end
                end
            end
        end
    end

    function Hekili:IsDisplayActive( display, config )
        if config then
            return dispActive[ display ] == 1
        end
        return dispActive[display] ~= nil
    end

    function Hekili:IsListActive( pack, list )
        return pack == "UseItems" or ( listActive[ pack .. ":" .. list ] == true )
    end

    function Hekili:IsActionActive( pack, list, action )
        return pack == "UseItems" or ( actsActive[ pack .. ":" .. list .. ":" .. action ] == true )
    end

    function Hekili:DumpActionActive()
        DevTools_Dump( actsActive )
    end
end

-- Builds and maintains the visible UI elements.
-- Buttons (as frames) are never deleted, but should get reused effectively.

local builtIns = {
    "Primary", "AOE", "Cooldowns", "Interrupts", "Defensives"
}

function Hekili:BuildUI()
    if not Masque then
        Masque = LibStub( "Masque", true )

        if Masque then
            Masque:Register( addon, MasqueUpdate, self )
            MasqueGroup = Masque:Group( addon )
            ns.UI.MasqueGroup = MasqueGroup -- classic's Build adds its buttons
        end
    end

    local LSM = LibStub( "LibSharedMedia-3.0" )

    ns.UI.Keyhandler = ns.UI.Keyhandler or CreateFrame( "Button", "Hekili_Keyhandler", UIParent )
    ns.UI.Keyhandler:RegisterForClicks( "AnyDown" )
    ns.UI.Keyhandler:SetScript( "OnClick", function( self, button, down )
        Hekili:FireToggle( button )
    end )
    Hekili:ProfileFrame( "KeyhandlerFrame", ns.UI.Keyhandler )

    local scaleFactor = self:GetScale()
    local mouseInteract = self.Pause

    -- Notification Panel
    local notif = self.DB.profile.notifications

    local f = ns.UI.Notification or CreateFrame( "Frame", "HekiliNotification", UIParent )
    Hekili:ProfileFrame( "HekiliNotification", f )

    f:SetSize( notif.width * scaleFactor, notif.height * scaleFactor )
    f:SetClampedToScreen( true )
    f:ClearAllPoints()
    f:SetPoint("CENTER", nil, "CENTER", notif.x, notif.y )

    f.Text = f.Text or f:CreateFontString( "HekiliNotificationText", "OVERLAY" )
    f.Text:SetAllPoints( f )
    f.Text:SetFont( LSM:Fetch( "font", notif.font ), notif.fontSize * scaleFactor, notif.fontStyle )
    f.Text:SetJustifyV("MIDDLE")
    f.Text:SetJustifyH("CENTER")
    f.Text:SetTextColor(1, 1, 1, 1)

    if not notif.enabled then f:Hide()
    else f.Text:SetText(nil); f:Show() end

    ns.UI.Notification = f
    -- End Notification Panel

    -- Displays
    for disp in pairs( self.DB.profile.displays ) do
        self:CreateDisplay( disp )
    end

    --if Hekili.Config then ns.StartConfiguration() end
    if MasqueGroup then
        MasqueGroup:ReSkin()
    end

    -- Check for a display that has been removed.
    for display, buttons in ipairs(ns.UI.Buttons) do
        if not Hekili.DB.profile.displays[display] then
            for i, _ in ipairs(buttons) do
                buttons[i]:Hide()
            end
        end
    end

    if Hekili.Config then
        ns.StartConfiguration(true)
    end
end

local T = ns.lib.Format.Tokens
local SyntaxColors = {}

function ns.primeTooltipColors()
    T = ns.lib.Format.Tokens
    --- Assigns a color to multiple tokens at once.
    local function Color(Code, ...)
        for Index = 1, select("#", ...) do
            SyntaxColors[select(Index, ...)] = Code
        end
    end
    Color( "|cffB266FF", T.KEYWORD ) -- Reserved Words

    Color( "|cffffffff", T.LEFTCURLY, T.RIGHTCURLY, T.LEFTBRACKET, T.RIGHTBRACKET, T.LEFTPAREN, T.RIGHTPAREN )

    Color( "|cffFF66FF", T.UNKNOWN,
        T.ADD,
        T.SUBTRACT,
        T.MULTIPLY,
        T.DIVIDE,
        T.POWER,
        T.MODULUS,
        T.CONCAT,
        T.VARARG,
        T.ASSIGNMENT,
        T.PERIOD,
        T.COMMA,
        T.SEMICOLON,
        T.COLON,
        T.SIZE,
        T.EQUALITY,
        T.NOTEQUAL,
        T.LT,
        T.LTE,
        T.GT,
        T.GTE )

    Color( "|cFFB2FF66", multiUnpack(ns.keys, ns.attr) )

    Color( "|cffFFFF00", T.NUMBER )
    Color( "|cff888888", T.STRING, T.STRING_LONG )
    Color( "|cff55cc55", T.COMMENT_SHORT, T.COMMENT_LONG )
    Color( "|cff55ddcc", -- Minimal standard Lua functions
        "assert",
        "error",
        "ipairs",
        "next",
        "pairs",
        "pcall",
        "print",
        "select",
        "tonumber",
        "tostring",
        "type",
        "unpack",
        -- Libraries
        "bit",
        "coroutine",
        "math",
        "string",
        "table"
    )
    Color( "|cffddaaff", -- Some of WoW's aliases for standard Lua functions
        -- math
        "abs",
        "ceil",
        "floor",
        "max",
        "min",
        -- string
        "format",
        "gsub",
        "strbyte",
        "strchar",
        "strconcat",
        "strfind",
        "strjoin",
        "strlower",
        "strmatch",
        "strrep",
        "strrev",
        "strsplit",
        "strsub",
        "strtrim",
        "strupper",
        "tostringall",
        -- table
        "sort",
        "tinsert",
        "tremove",
        "wipe" )
end


local SpaceLeft = {"(%()"}
local SpaceRight = {"(%))"}
local DoubleSpace = {"(!=)", "(~=)", "(>=*)", "(<=*)", "(&)", "(||)", "(+)", "(*)", "(-)", "(/)"}


local function Format(Code)
    for Index = 1, #SpaceLeft do
        Code = Code:gsub("%s-" .. SpaceLeft[Index] .. "%s-", " %1")
    end

    for Index = 1, #SpaceRight do
        Code = Code:gsub("%s-" .. SpaceRight[Index] .. "%s-", "%1 ")
    end

    for Index = 1, #DoubleSpace do
        Code = Code:gsub("%s-" .. DoubleSpace[Index] .. "%s-", " %1 ")
    end

    Code = Code:gsub("([^<>~!])(=+)", "%1 %2 ")
    Code = Code:gsub("%s+", " "):trim()
    return Code
end


local key_cache = setmetatable( {}, {
    __index = function( t, k )
        t[k] = k:gsub( "(%S+)%[(%d+)]", "%1.%2" )
        return t[k]
    end
})


function Hekili:ShowDiagnosticTooltip( q )
    if not q.actionName or not q.name then return end

    local tt = HekiliTooltip
    local fmt = ns.lib.Format

    tt:SetOwner( UIParent, "ANCHOR_CURSOR" )
    tt:SetText( q.name )
    tt:AddDoubleLine( q.listName .. " #" .. q.action, "+" .. ns.formatValue(round(q.time or 0, 2)), 1, 1, 1, 1, 1, 1 )

    if q.resources and q.resources[q.resource_type] then
        tt:AddDoubleLine(q.resource_type, ns.formatValue(q.resources[q.resource_type]), 1, 1, 1, 1, 1, 1)
    end

    if q.HookHeader or (q.HookScript and q.HookScript ~= "") then
        if q.HookHeader then
            tt:AddLine(" ")
            tt:AddLine(q.HookHeader)
        else
            tt:AddLine(" ")
            tt:AddLine("Hook Criteria")
        end

        if q.HookScript and q.HookScript ~= "" then
            local Text = Format(q.HookScript)
            tt:AddLine(fmt.FormatCode(Text, 0, SyntaxColors), 1, 1, 1, 1)
        end

        if q.HookElements then
            local applied = false
            for k, v in orderedPairs(q.HookElements) do
                if not applied then
                    tt:AddLine(" ")
                    tt:AddLine("Values")
                    applied = true
                end
                if not key_cache[k]:find( "safebool" ) and not key_cache[k]:find( "safenum" ) and not key_cache[k]:find( "ceil" ) and not key_cache[k]:find( "floor" ) then
                    tt:AddDoubleLine( key_cache[ k ], ns.formatValue(v), 1, 1, 1, 1, 1, 1)
                end
            end
        end
    end

    if q.ReadyScript and q.ReadyScript ~= "" then
        tt:AddLine(" ")
        tt:AddLine("Time Script")

        tt:AddLine(fmt.FormatCode(q.ReadyScript, 0, SyntaxColors), 1, 1, 1, 1)

        if q.ReadyElements then
            tt:AddLine("Values")
            for k, v in orderedPairs(q.ReadyElements) do
                if not key_cache[k]:find( "safebool" ) and not key_cache[k]:find( "safenum" ) and not key_cache[k]:find( "ceil" ) and not key_cache[k]:find( "floor" ) then
                    tt:AddDoubleLine( key_cache[ k ], ns.formatValue(v), 1, 1, 1, 1, 1, 1)
                end
            end
        end
    end

    if q.ActScript and q.ActScript ~= "" then
        tt:AddLine(" ")
        tt:AddLine("Action Criteria")

        tt:AddLine(fmt.FormatCode(q.ActScript, 0, SyntaxColors), 1, 1, 1, 1)

        if q.ActElements then
            tt:AddLine(" ")
            tt:AddLine("Values")
            for k, v in orderedPairs(q.ActElements) do
                if not key_cache[k]:find( "safebool" ) and not key_cache[k]:find( "safenum" ) and not key_cache[k]:find( "ceil" ) and not key_cache[k]:find( "floor" ) then
                    tt:AddDoubleLine( key_cache[ k ], ns.formatValue(v), 1, 1, 1, 1, 1, 1)
                end
            end
        end
    end

    if q.pack and q.listName and q.action then
        local entry = rawget( self.DB.profile.packs, q.pack )
        entry = entry and entry.lists[ q.listName ]
        entry = entry and entry[ q.action ]

        if entry and entry.description and entry.description:len() > 0 then
            tt:AddLine( " " )
            tt:AddLine( entry.description, 0, 0.7, 1, true )
        end
    end

    tt:SetMinimumWidth( 400 )
    tt:Show()
end

function Hekili:SaveCoordinates()
    for i in pairs(Hekili.DB.profile.displays) do
        local display = ns.UI.Displays[i]
        if display then
            local rel, x, y = select( 3, display:GetPoint() )

            self.DB.profile.displays[i].rel = "CENTER"
            self.DB.profile.displays[i].x = x
            self.DB.profile.displays[i].y = y
        end
    end

    self.DB.profile.notifications.x, self.DB.profile.notifications.y = select( 4, HekiliNotification:GetPoint() )
end
