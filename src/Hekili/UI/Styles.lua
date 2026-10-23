local _, ns = ...
local L = ns.L
-- UI/Styles.lua: the display style registry (display styles plan, Task 1). A style is one table per renderer; each
-- display binds one (d.style, in UI.lua's CreateDisplay) and core drives it through the members below. A style reads
-- only Hekili.Engine.Output[ id ], Output.status and its own config, never the engine's state or class tables.

ns.UI.Styles = ns.UI.Styles or {}

-- Every member a style must implement (`defaults`, its config subtable template, is optional; so is `needs`, what it
-- asks the engine to compute beyond the records: `needs.alts` fills recs[1..2].alts, the picks at the gating
-- resource's belief bounds; or `NeedsFor( id, conf )`, which core then asks instead, returning such a table per display).
local MEMBERS = {
    label = "string",
    Build = "function", -- ( d, conf ): creates or reuses its frames on d, returns the button list (may be empty)
    Draw = "function", -- ( d, conf, out, status ): on a publish (d.NewRecommendations) or the 0.25 s pulse
    Tick = "function", -- ( d, conf, out, now, elapsed ): every frame, before Draw
    OnGameEvent = "function", -- ( d, conf, event, ... ): every display event, after core's alpha/keybinding handling
    Clear = "function", -- ( d ): hide everything it shows
    Perimeter = "function", -- ( d ): left, right, top, bottom frames for config mode's backdrop (or nil)
    UpdateKeybindings = "function", -- ( d )
    Options = "function", -- ( id, conf ): the style's option tabs, new tables each call (core sets each tab's `hidden`)
}

-- The version of the style interface below. A style declares the one it was written for as `api`.
Hekili.DisplayStyleAPI = 1

--- Public: registers display style `impl` as `name` for any addon (built-in styles use it too). Refused with one
--- Notify (returns false) when `impl.api` is not Hekili.DisplayStyleAPI or `name` is a core display field or tab;
--- raises when a member is missing. Registered after Hekili's DB exists, its defaults reach every display; after
--- the displays exist, a rebuild binds it where the profile names it.
function Hekili:RegisterDisplayStyle( name, impl )
    local api = type( impl ) == "table" and impl.api or nil
    if api ~= Hekili.DisplayStyleAPI then
        self:Notify( L["Display style '%s' targets style API %s, this Hekili Forever has %d; not registered."]:format( tostring( name ), tostring( api ), Hekili.DisplayStyleAPI ) )
        return false
    end
    if ns.UI.StyleNameTaken( name ) then
        self:Notify( L["Display style '%s' not registered: the name is a core display setting."]:format( tostring( name ) ) )
        return false
    end
    ns.UI.RegisterStyle( name, impl )
    if self.DB then ns.UI.LateStyleDefaults() end
    if next( ns.UI.Displays ) then ns.UI.QueueRebuildUI() end
    return true
end

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
    if impl.needs ~= nil and type( impl.needs ) ~= "table" then
        error( ( "display style '%s': needs must be a table" ):format( tostring( name ) ), 2 )
    end
    if impl.NeedsFor ~= nil and type( impl.NeedsFor ) ~= "function" then
        error( ( "display style '%s': NeedsFor must be a function" ):format( tostring( name ) ), 2 )
    end
    ns.UI.Styles[ name ] = impl
end
