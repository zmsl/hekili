local _, ns = ...
-- Options/StyleOptions.lua: the option tabs every display style can offer for its own config subtable (display
-- styles plan, Task 3d). They are classic's tabs (written by Hekili's authors and maintainers, moved here out of
-- UI/Styles/Classic.lua), turned into builders: `SO.<group>( styleKey, zones, order, id, conf )` returns the tab for
-- displays[ id ][ styleKey ][ group ], where `zones` names the style's icon zones in order. The first zone uses the
-- plain fields (`font`); every later zone gets its own copy of the per-zone blocks, its fields prefixed with the zone
-- name (`nextFont`). `zones.legacy = true` (classic's alone) marks the later zones as classic's queue: they get only
-- the copies classic always had (the keybinding font and case, behind `separateQueueStyle`) and share every other
-- block with the primary icon. Keybinding case is per zone only there (the engine honours it only through that toggle).
-- `SO.defaults( groups, zones )` returns the matching config subtables. Public as Hekili.StyleOptions for external
-- styles. Options a builder leaves out because only classic's layout gives them meaning (border.fit, the delay
-- indicator, keepAspectRatio on the icon) stay in Classic.lua.

local SO = {}
ns.StyleOptions = SO
Hekili.StyleOptions = SO

local max = math.max

local function title( zone )
    return zone:sub( 1, 1 ):upper() .. zone:sub( 2 )
end

-- The config field `field` for zone `i`: zone 1 is the plain field, later zones prefix it (queued -> queuedFont).
local function key( i, zone, field )
    if i == 1 then return field end
    return zone .. title( field )
end

-- A style's later zones have their own blocks, unless the zones are classic's legacy queue (zones.legacy).
local function own( zones )
    return not zones.legacy
end

-- shortcut: offset bounds come from classic's icon sizes; a style without them gets +-100 until it says its own.
local function spanW( s )
    return max( s.primaryWidth or 100, s.queue and s.queue.width or 0 )
end

local function spanH( s )
    return max( s.primaryHeight or 100, s.queue and s.queue.height or 0 )
end

-- fontElements with every field renamed for zone `i` (break01 is a description, not a field).
local function fontBlock( i, zone )
    local args = {}
    for k, v in pairs( ns.UI.DisplayOptionParts.fontElements ) do
        args[ k == "break01" and k or key( i, zone, k ) ] = ns.tableCopy( v )
    end
    return args
end

local function classColorName()
    local ClassColor = ns.UI.DisplayOptionParts.ClassColor
    return format( "Class |A:WhiteCircle-RaidBlips:16:16:0:0:%d:%d:%d|a #%s", ClassColor.r * 255, ClassColor.g * 255, ClassColor.b * 255, ClassColor:GenerateHexColor():sub( 3, 8 ) )
end

-- Per-zone fields of each group, copied for a later zone in SO.defaults.
local ZONED = {
    keybindings = { "font", "fontSize", "fontStyle", "color" },
    captions = { "anchor", "x", "y", "align" },
    indicators = { "width", "height", "zoom", "keepAspectRatio" },
}

local function base()
    local font = ElvUI and "PT Sans Narrow" or "Arial Narrow"
    return {
        border = {
            enabled = true,
            thickness = 1,
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

            font = font,
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

            font = font,
            fontSize = 12,
            fontStyle = "OUTLINE",

            anchor = "BOTTOMRIGHT",
            x = 0,
            y = 0,

            color = { 1, 1, 1, 1 },
        },

        delays = {
            fade = false,
        },

        keybindings = {
            enabled = true,
            queued = true,

            font = font,
            fontSize = 12,
            fontStyle = "OUTLINE",

            lowercase = false,

            anchor = "TOPRIGHT",
            x = 1,
            y = -1,

            cPortOverride = true,
            cPortZoom = 0.6,

            color = { 1, 1, 1, 1 },
        },
    }
end

--- The default subtables of `groups` (names from the builders below) for a style with `zones`, new tables each call.
function SO.defaults( groups, zones )
    local all, out = base(), {}
    for _, g in ipairs( groups ) do
        local t = all[ g ]
        if not t then error( ( "style options: no shared group '%s'" ):format( tostring( g ) ), 2 ) end
        local fields = ZONED[ g ]
        if fields then
            for i = 2, #zones do
                local zone = zones[ i ]
                if own( zones ) or g == "keybindings" then
                    for _, f in ipairs( fields ) do
                        local v = t[ f ]
                        t[ key( i, zone, f ) ] = type( v ) == "table" and { unpack( v ) } or v
                    end
                end
                if g == "keybindings" and not own( zones ) then
                    t.separateQueueStyle, t[ key( i, zone, "lowercase" ) ] = false, t.lowercase
                end
            end
        end
        out[ g ] = t
    end
    return out
end

--- The icon size group of `zone` (fields `<zone>Width`, `<zone>Height`) and the shared texture zoom.
function SO.icon( zone, order, id )
    return {
        type = "group",
        name = title( zone ) .. " Icon",
        inline = true,
        order = order,
        args = {
            [ zone .. "Width" ] = {
                type = "range",
                name = "Width",
                desc = "Specify the width of the " .. zone .. " icon for " .. ( id == "Multi" and "each display." or ( "your " .. id .. " Display." ) ),
                min = 10,
                max = 500,
                step = 1,

                width = 1.49,
                order = 1,
            },

            [ zone .. "Height" ] = {
                type = "range",
                name = "Height",
                desc = "Specify the height of the " .. zone .. " icon for " .. ( id == "Multi" and "each display." or ( "your " .. id .. " Display." ) ),
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
        },
    }
end

function SO.keybindings( styleKey, zones, order, id, conf )
    local P = ns.UI.DisplayOptionParts
    local s = conf[ styleKey ]
    local args = {
        enabled = {
            type = "toggle",
            name = "Enabled",
            order = 1,
            width = 1.49,
        },

        pos = {
            type = "group",
            inline = true,
            name = function( info ) P.rangeIcon( info )
return "Position" end,
            order = 3,
            args = {
                anchor = {
                    type = "select",
                    name = 'Anchor Point',
                    order = 2,
                    width = 1,
                    values = P.realAnchorPositions
                },

                x = {
                    type = "range",
                    name = "X Offset",
                    order = 3,
                    width = 0.99,
                    min = -spanW( s ),
                    max = spanW( s ),
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
                    min = -spanH( s ),
                    max = spanH( s ),
                    step = 1,
                }
            }
        },

        textStyle = {
            type = "group",
            inline = true,
            name = "Font and Style",
            order = 5,
            args = fontBlock( 1, zones[ 1 ] ),
        },

        lowercase = {
            type = "toggle",
            name = "Use Lowercase",
            order = 5.1,
            width = "full",
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

    if #zones > 1 then
        args.queued = {
            type = "toggle",
            name = "Enabled for Queued Icons",
            order = 2,
            width = 1.49,
            disabled = function () return conf[ styleKey ].keybindings.enabled == false end,
        }
    end

    for i = 2, #zones do
        local zone = zones[ i ]
        local hidden
        if not own( zones ) then
            hidden = function () return not conf[ styleKey ].keybindings.separateQueueStyle end
            args.separateQueueStyle = {
                type = "toggle",
                name = "Use Different Settings for Queue",
                order = 6,
                width = "full",
            }
        end

        args[ key( i, zone, "textStyle" ) ] = {
            type = "group",
            inline = true,
            name = title( zone ) .. " Font and Style",
            order = 5 + i,
            hidden = hidden,
            args = fontBlock( i, zone ),
        }

        if not own( zones ) then
            args[ key( i, zone, "lowercase" ) ] = {
                type = "toggle",
                name = "Use Lowercase in Queue",
                order = 5 + i + 0.1,
                width = 1.49,
                hidden = hidden,
            }
        end
    end

    return {
        type = "group",
        name = "Keybinds",
        desc = "Options for keybinding text on displayed icons.",
        order = order,
        args = args,
    }
end

function SO.border( styleKey, zones, order, id, conf )
    return {
        type = "group",
        name = "Border",
        desc = "Enable/disable or set the color for icon borders.\n\n" ..
            "You may want to disable this if you use Masque or other tools to skin your Hekili icons.",
        order = order,

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
                    class = classColorName(),
                    custom = "Specify a Custom Color"
                },
                disabled = function() return conf[ styleKey ].border.enabled == false end,
            },

            color = {
                type = "color",
                name = "Custom Color",
                desc = "When borders are enabled and the Coloring Mode is set to |cFFFFD100Custom Color|r, the border will use this color.",
                order = 4,
                width = 1.49,
                disabled = function () return conf[ styleKey ].border.enabled == false or conf[ styleKey ].border.coloring ~= "custom" end,
            }
        }
    }
end

function SO.range( styleKey, zones, order, id, conf )
    return {
        type = "group",
        name = "Range",
        desc = "Preferences for range-check warnings, if desired.",
        order = order,
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
                disabled = function () return conf[ styleKey ].range.enabled == false end,
            }
        }
    }
end

function SO.glow( styleKey, zones, order, id, conf )
    local args = {
        enabled = {
            type = "toggle",
            name = "Enable Overlay Glow",
            desc = "If enabled, when the ability for the first icon has an active glow (or overlay), it will also glow in this display.",
            width = 1.49,
            order = 1,
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
            disabled = function() return conf[ styleKey ].glow.enabled == false end,
        },

        coloring = {
            type = "select",
            name = "Coloring Mode",
            desc = "Select the coloring mode for this glow effect.\n\nClass-colored borders will automatically change to match the class you are playing.",
            width = 0.99,
            order = 4,
            values = {
                default = "Use Default Color",
                class = classColorName(),
                custom = "Specify a Custom Color"
            },
            disabled = function() return conf[ styleKey ].glow.enabled == false end,
        },

        color = {
            type = "color",
            name = "Glow Color",
            desc = "Select the custom glow color for your display.",
            width = 0.99,
            order = 5,
            disabled = function() return conf[ styleKey ].glow.coloring ~= "custom" end,
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
    }

    if #zones > 1 then
        args.queued = {
            type = "toggle",
            name = "Enabled for Queued Icons",
            desc = "If enabled, abilities that have active glows (or overlays) will also glow in your queue.\n\n" ..
                "This may not be ideal, the glow may no longer be correct by that point in the future.",
            width = 1.49,
            order = 2,
            disabled = function() return conf[ styleKey ].glow.enabled == false end,
        }
    end

    return {
        type = "group",
        name = "Glows",
        desc = "Preferences for Blizzard action button glows (not SpellFlash).",
        order = order,
        args = args,
    }
end

function SO.flash( styleKey, zones, order, id, conf )
    local SF = SpellFlashCore
    return {
        type = "group",
        name = "SpellFlash",
        desc = function ()
            if SF then
                return "If enabled, the addon can highlight abilities on your action bars when they are recommended for use."
            end
            return "This feature requires the SpellFlashCore addon or library to function properly."
        end,
        order = order,
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
                icon =  function() return conf[ styleKey ].flash.texture or "Interface\\Cooldown\\star4" end,
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
    }
end

function SO.captions( styleKey, zones, order, id, conf )
    local P = ns.UI.DisplayOptionParts
    local s = conf[ styleKey ]
    local args = {
        enabled = {
            type = "toggle",
            name = "Enabled",
            desc = "If enabled, when the first ability shown has a descriptive caption, the caption will be shown.",
            order = 1,
            width = 1.49,
        },

        textStyle = {
            type = "group",
            inline = true,
            name = "Text",
            order = 4,
            args = fontBlock( 1, zones[ 1 ] ),
        },
    }

    if #zones > 1 then
        args.queued = {
            type = "toggle",
            name = "Enabled for Queued Icons",
            desc = "If enabled, descriptive captions will be shown for queued abilities, if appropriate.",
            order = 2,
            width = 1.49,
            disabled = function () return conf[ styleKey ].captions.enabled == false end,
        }
    end

    for i = 1, #zones do
        local zone = zones[ i ]
        if i == 1 or own( zones ) then
            local x = {
                type = "range",
                name = "X Offset",
                order = 2,
                width = 0.99,
                step = 1,
            }
            local y = {
                type = "range",
                name = "Y Offset",
                order = 3,
                width = 0.99,
                step = 1,
            }
            if i > 1 then -- the first zone's bounds come from rangeIcon, like classic's
                x.min, x.max, y.min, y.max = -spanW( s ), spanW( s ), -spanH( s ), spanH( s )
            end
            args[ key( i, zone, "position" ) ] = {
                type = "group",
                inline = true,
                name = i == 1 and function( info ) P.rangeIcon( info ); return "Position" end or ( title( zone ) .. " Position" ),
                order = 3 + ( i - 1 ) * 0.1,
                args = {
                    [ key( i, zone, "anchor" ) ] = {
                        type = "select",
                        name = 'Anchor Point',
                        order = 1,
                        width = 1,
                        values = {
                            TOP = 'Top',
                            BOTTOM = 'Bottom',
                        }
                    },

                    [ key( i, zone, "x" ) ] = x,

                    [ key( i, zone, "y" ) ] = y,

                    break01 = {
                        type = "description",
                        name = " ",
                        order = 3.1,
                        width = "full",
                    },

                    [ key( i, zone, "align" ) ] = {
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
            }
        end
    end

    return {
        type = "group",
        name = "Captions",
        desc = "Captions are brief descriptions sometimes (rarely) used in action lists to describe why the action is shown.",
        order = order,
        args = args,
    }
end

function SO.targets( styleKey, zones, order, id, conf )
    local P = ns.UI.DisplayOptionParts
    local s = conf[ styleKey ]
    return {
        type = "group",
        name = "Targets",
        desc = "A target count indicator can be shown on the display's first recommendation.",
        order = order,
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
                name = function( info ) P.rangeIcon( info )
return "Position" end,
                order = 2,
                args = {
                    anchor = {
                        type = "select",
                        name = "Anchor To",
                        values = P.realAnchorPositions,
                        order = 1,
                        width = 1,
                    },

                    x = {
                        type = "range",
                        name = "X Offset",
                        min = -spanW( s ),
                        max = spanW( s ),
                        step = 1,
                        order = 2,
                        width = 0.99,
                    },

                    y = {
                        type = "range",
                        name = "Y Offset",
                        min = -spanH( s ),
                        max = spanH( s ),
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
                args = fontBlock( 1, zones[ 1 ] ),
            },
        }
    }
end

-- Only what any style can do with a wait (dim or desaturate the first icon); classic adds its delay indicator.
function SO.delays( styleKey, zones, order, id, conf )
    return {
        type = "group",
        name = "Delays",
        desc = "When an ability is recommended some time in the future, a colored indicator or countdown timer can " ..
            "communicate that there is a delay.",
        order = order,
        args = {
            fade = {
                type = "toggle",
                name = "Fade as Unusable",
                desc = "Fade the primary icon when you should wait before using the ability, similar to when an ability is lacking required resources.",
                width = 1.49,
                order = 1.1
            },

            desaturate = {
                type = "toggle",
                name = format( "%s Desaturate", ns.UI.DisplayOptionParts.NewFeature ),
                desc = "Desaturate the primary icon when you should wait before using the ability.",
                width = 1.49,
                order = 1.15
            },
        }
    }
end

function SO.indicators( styleKey, zones, order, id, conf )
    local P = ns.UI.DisplayOptionParts
    local s = conf[ styleKey ]
    local args = {
        enabled = {
            type = "toggle",
            name = "Enabled",
            desc = "If enabled, small indicators for target-swapping, aura-cancellation, etc. may appear on your primary icon.",
            order = 1,
            width = 1.49,
        },

        pos = {
            type = "group",
            inline = true,
            name = function( info ) P.rangeIcon( info )
return "Position" end,
            order = 2,
            args = {
                anchor = {
                    type = "select",
                    name = "Anchor To",
                    values = P.realAnchorPositions,
                    order = 1,
                    width = 1,
                },

                x = {
                    type = "range",
                    name = "X Offset",
                    min = -spanW( s ),
                    max = spanW( s ),
                    step = 1,
                    order = 2,
                    width = 0.99,
                },

                y = {
                    type = "range",
                    name = "Y Offset",
                    min = -spanH( s ),
                    max = spanH( s ),
                    step = 1,
                    order = 2,
                    width = 0.99,
                }
            }
        },
    }

    if #zones > 1 then
        args.queued = {
            type = "toggle",
            name = "Enabled for Queued Icons",
            desc = "If enabled, these indicators will appear on queued icons as well as the primary icon, when appropriate.",
            order = 2,
            width = 1.49,
            disabled = function () return conf[ styleKey ].indicators.enabled == false end,
        }
    end

    for i = 1, #zones do
        local zone = zones[ i ]
        if i == 1 or own( zones ) then
            args[ key( i, zone, "size" ) ] = {
                type = "group",
                inline = true,
                name = i == 1 and "Appearance" or ( title( zone ) .. " Appearance" ),
                order = 1.5 + ( i - 1 ) * 0.01,
                args = {
                    [ key( i, zone, "width" ) ] = {
                        type = "range",
                        name = "Width",
                        desc = "Specify the width of indicator icons.",
                        min = 8,
                        max = 100,
                        step = 1,
                        width = 1.49,
                        order = 1,
                    },

                    [ key( i, zone, "height" ) ] = {
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

                    [ key( i, zone, "zoom" ) ] = {
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

                    [ key( i, zone, "keepAspectRatio" ) ] = {
                        type = "toggle",
                        name = "Keep Aspect Ratio",
                        desc = "When enabled, indicator icons will maintain their original aspect ratio when resized.",
                        width = 1.49,
                        order = 5,
                    },
                }
            }
        end
    end

    return {
        type = "group",
        name = "Indicators",
        desc = "Indicators are small icons that can indicate target-swapping or (rarely) cancelling auras.",
        order = order,
        args = args,
    }
end
