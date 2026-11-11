local _, ns = ...
-- UI/BarGlow.lua: the action bar glow. A display's first recommendation glows the real action buttons that cast it,
-- its second (when the display shows one) glows in another colour, through LibCustomGlow's proc glow under Hekili's own
-- keys. Never Blizzard's spell alert manager: that writes addon data into Blizzard's table (taint) and collides with a
-- real proc. Styles call Update from Draw and Clear from their own Clear; the settings are the style's `barGlow` group
-- (Options/StyleOptions.lua).
--
-- The buttons come from walking the bar frames (Blizzard's keyboard bars, Forever's gamepad bars, ElvUI, Bartender,
-- Dominos) and reading each one's current action slot, so a paged or form bar follows; the ability behind a slot is the
-- keybind reader's own lookup (ns.ResolveAction, Engine/Sim/Events.lua). The map is rebuilt on a bar event (debounced);
-- Update works only when the recommendation, the map or a colour changed, and allocates nothing otherwise.

local Facade = ns.Facade
local GetActionInfo, GetMacroSpell, GetMacroItem = Facade.GetActionInfo, Facade.GetMacroSpell, Facade.GetMacroItem
local GetItemInfoInstant = Facade.C_Item.GetItemInfoInstant

local BarGlow = {}
ns.UI.BarGlow = BarGlow
BarGlow.Glower = LibStub( "LibCustomGlow-1.0" ) -- a field so a spec can record the calls

local NOW, NEXT = { 1, 0.82, 0, 1 }, { 0.3, 0.6, 1, 1 } -- the defaults' colours, for a config missing its own

local map = {}   -- ability key -> { n = count, button, ... }
local version = 0 -- bumped when a rescan changed the map
local signature, lastSignature = 0, -1

local function put( key, button )
    local list = map[ key ]
    if not list then
        list = { n = 0 }
        map[ key ] = list
    end
    list.n = list.n + 1
    list[ list.n ] = button
end

local count -- buttons mapped by the running scan, for the signature

-- One button: the action slot it holds now (an addon bar's state action, else Blizzard's `action`), the ability that
-- slot casts, and the ability's `bind` aliases (as the keybind reader keys them).
local function add( button )
    local slot = button._state_action
    if type( slot ) ~= "number" then slot = button.action end
    if type( slot ) ~= "number" then return end

    local aType, id = GetActionInfo( slot )
    if aType == "macro" and id then
        local spell = GetMacroSpell( id )
        if spell then
            aType, id = "spell", spell
        else
            local name, link = GetMacroItem( id )
            aType, id = "item", ( link or name ) and GetItemInfoInstant( link or name )
        end
    end
    if not aType or not id then return end

    local key, ability = ns.ResolveAction( aType, id )
    if not key then return end

    count = count + 1
    signature = ( signature * 31 + slot * 1009 + count + ( ability and type( ability.id ) == "number" and ability.id or 0 ) ) % 2147483647
    put( key, button )

    local bind = ability and ability.bind
    if type( bind ) == "table" then
        for _, b in ipairs( bind ) do put( b, button ) end
    elseif bind then
        put( bind, button )
    end
end

-- Frames holding a numeric `action` under `...`, down `depth` levels (Forever's gamepad bars: PageUnit's bars' buttons).
local function walk( depth, ... )
    for i = 1, select( "#", ... ) do
        local f = select( i, ... )
        if type( f.action ) == "number" then
            add( f )
        elseif depth > 0 and f.GetChildren then
            walk( depth - 1, f:GetChildren() )
        end
    end
end

local names -- every bar button's global name, built on the first scan

local function buildNames()
    names = {}
    for _, prefix in ipairs( { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
        "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" } ) do
        for i = 1, 12 do names[ #names + 1 ] = prefix .. i end
    end
    for bar = 1, 15 do
        for i = 1, 12 do names[ #names + 1 ] = "ElvUI_Bar" .. bar .. "Button" .. i end
    end
    for i = 1, 180 do names[ #names + 1 ] = "BT4Button" .. i end
end

--- Rebuilds the map from the bar frames now. A changed map bumps the version, so every display repaints its glows.
function BarGlow.Rescan()
    if not names then buildNames() end

    for _, list in pairs( map ) do
        for i = 1, list.n do list[ i ] = nil end
        list.n = 0
    end
    signature, count = 0, 0

    for i = 1, #names do
        local b = _G[ names[ i ] ]
        if b then add( b ) end
    end

    for i = 1, 14 do
        local bar = _G[ "DominosFrame" .. i ]
        local buttons = bar and bar.buttons
        if buttons then
            for b = 1, 12 do
                if buttons[ b ] then add( buttons[ b ] ) end
            end
        end
    end

    local pad = _G.GamepadMainActionBarFrame
    local unit = pad and pad.PageUnit
    if unit and unit.GetChildren then walk( 3, unit:GetChildren() ) end

    if signature ~= lastSignature then
        lastSignature = signature
        version = version + 1
    end
end

-- One glow role of a display (now or next): its Hekili-owned key, the ability and map version it last painted, the
-- colour it holds and the buttons it lit.
local function newRole( key )
    local color = { 0, 0, 0, 0 }
    return { key = key, opts = { key = key, color = color }, color = color, ability = nil, version = -1, lit = {}, n = 0 }
end

local function stopRole( role )
    local Glower = BarGlow.Glower
    for i = 1, role.n do
        Glower.ProcGlow_Stop( role.lit[ i ], role.key )
        role.lit[ i ] = nil
    end
    role.n = 0
    role.ability = nil
end

local function setRole( role, ability, c )
    local col = role.color
    if ability == nil and role.ability == nil then return end
    if ability == role.ability and role.version == version
        and col[ 1 ] == c[ 1 ] and col[ 2 ] == c[ 2 ] and col[ 3 ] == c[ 3 ] and col[ 4 ] == ( c[ 4 ] or 1 ) then return end

    stopRole( role )
    if not ability then return end

    role.ability, role.version = ability, version
    col[ 1 ], col[ 2 ], col[ 3 ], col[ 4 ] = c[ 1 ], c[ 2 ], c[ 3 ], c[ 4 ] or 1

    local list = map[ ability ]
    if not list then return end
    local Glower = BarGlow.Glower
    for i = 1, list.n do
        local b = list[ i ]
        Glower.ProcGlow_Start( b, role.opts )
        role.n = role.n + 1
        role.lit[ role.n ] = b
    end
end

local function roles( d )
    local st = d.styleState
    local s = st.barGlow
    if not s then
        s = { now = newRole( "HkBarNow" .. d.id ), next = newRole( "HkBarNext" .. d.id ) }
        st.barGlow = s
    end
    return s
end

--- From a style's Draw: glows `cfg`'s (the style's barGlow group) now and next colours on the buttons of the display's
--- first and second records. `shown` is how many records the display shows; a blank or hidden display glows nothing.
function BarGlow.Update( d, cfg, out, shown )
    local s = roles( d )
    local nowKey, nextKey
    if cfg.enabled and out.count > 0 and out.version ~= d.blankVersion then
        nowKey = out.recs[ 1 ].actionName
        if cfg.glowNext and shown > 1 and out.count > 1 then
            nextKey = out.recs[ 2 ].actionName
            if nextKey == nowKey then nextKey = nil end -- now wins
        end
    end
    setRole( s.now, nowKey, cfg.colorNow or NOW )
    setRole( s.next, nextKey, cfg.colorNext or NEXT )
end

--- Stops every glow of a display (hidden, disabled, a style switch).
function BarGlow.Clear( d )
    local s = d.styleState and d.styleState.barGlow
    if s then
        stopRole( s.now )
        stopRole( s.next )
    end
end

local pending = false
local function rescan()
    pending = false
    BarGlow.Rescan()
end

-- A bar event: one rescan after the burst (a page turn raises a slot event per button).
local function queue()
    if pending then return end
    pending = true
    C_Timer.After( 0.2, rescan )
end

for _, event in ipairs( { "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "UPDATE_MACROS",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED" } ) do
    ns.RegisterEvent( event, queue )
end
