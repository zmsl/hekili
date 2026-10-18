local _, ns = ...
-- UI/Styles.lua: the display style registry (display styles plan, Task 1). A style is one table per renderer; each
-- display binds one (d.style, in UI.lua's CreateDisplay) and core drives it through the members below. A style reads
-- only Hekili.Engine.Output[ id ], Output.status and its own config, never the engine's state or class tables.

ns.UI.Styles = ns.UI.Styles or {}

-- Every member a style must implement (`defaults`, its config subtable template, is optional).
local MEMBERS = {
    label = "string",
    Build = "function", -- ( d, conf ): creates or reuses its frames on d, returns the button list (may be empty)
    Draw = "function", -- ( d, conf, out, status ): on a publish (d.NewRecommendations) or the 0.25 s pulse
    Tick = "function", -- ( d, conf, out, now, elapsed ): every frame, before Draw
    OnGameEvent = "function", -- ( d, conf, event, ... ): every display event, after core's alpha/keybinding handling
    Clear = "function", -- ( d ): hide everything it shows
    Perimeter = "function", -- ( d ): left, right, top, bottom frames for config mode's backdrop (or nil)
    UpdateKeybindings = "function", -- ( d )
    Options = "function", -- ( id, conf ): the style's option tabs
}

--- Registers style `impl` as `name`, raising when a member is missing or of the wrong type.
function ns.UI.RegisterStyle( name, impl )
    for k, kind in pairs( MEMBERS ) do
        if type( impl[ k ] ) ~= kind then
            error( ( "display style '%s': %s must be a %s" ):format( tostring( name ), k, kind ), 2 )
        end
    end
    if impl.defaults ~= nil and type( impl.defaults ) ~= "table" then
        error( ( "display style '%s': defaults must be a table" ):format( tostring( name ) ), 2 )
    end
    ns.UI.Styles[ name ] = impl
end
