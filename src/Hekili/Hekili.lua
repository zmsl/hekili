-- Hekili.lua
-- July 2024

local addon, ns = ...
local Facade = ns.Facade
local CreateFrame = Facade.CreateFrame
local AuraUtil, C_AddOns, C_UnitAuras = Facade.AuraUtil, Facade.C_AddOns, Facade.C_UnitAuras
local GetBuildInfo, GetFramerate, GetTime = Facade.GetBuildInfo, Facade.GetFramerate, Facade.GetTime
Hekili = LibStub("AceAddon-3.0"):NewAddon( "Hekili", "AceConsole-3.0", "AceSerializer-3.0" )
Hekili.Version = C_AddOns.GetAddOnMetadata( "Hekili", "Version" )
Hekili.Flavor = C_AddOns.GetAddOnMetadata( "Hekili", "X-Flavor" ) or "Retail"

local format = string.format
local insert, concat = table.insert, table.concat


local buildStr, _, _, buildNum = GetBuildInfo()

Hekili.CurrentBuild = buildNum

if Hekili.Version == ( "@" .. "project-version" .. "@" ) then
    Hekili.Version = format( "Dev-%s (%s)", buildStr, date( "%Y%m%d" ) )
    Hekili.IsDev = true
end

Hekili.AllowSimCImports = true

Hekili.IsRetail = function()
    return Hekili.Flavor == "Retail"
end

Hekili.IsWrath = function()
    return Hekili.Flavor == "Wrath"
end

Hekili.IsClassic = function()
    return Hekili.IsWrath()
end

Hekili.BuiltFor = 16001
Hekili.GameBuild = buildStr

ns.PTR = false
Hekili.IsPTR = ns.PTR

ns.Patrons = "|cFFFFD100Current Status|r\n\n"
    .. "If you find odd recommendations or other issues, please follow the |cFFFFD100Report Issue|r link below and submit all the necessary information to have your issue investigated.\n\n"
    .. "Please |cffff0000do not|r submit tickets for routine priority updates (i.e., from SimulationCraft). They are routinely updated."

do
    local cpuProfileDB = {}

    function Hekili:ProfileCPU( name, func )
        cpuProfileDB[ name ] = func
    end

	ns.cpuProfile = cpuProfileDB

	local frameProfileDB = {}

	function Hekili:ProfileFrame( name, f )
		frameProfileDB[ name ] = f
	end

	ns.frameProfile = frameProfileDB
end


ns.lib = {
    Format = {}
}


-- 04072017:  Let's go ahead and cache aura information to reduce overhead.
ns.auras = {
    target = {
        buff = {},
        debuff = {}
    },
    player = {
        buff = {},
        debuff = {}
    }
}

Hekili.Class = {
    specs = {},
    num = 0,

    file = "NONE",
    initialized = false,

	resources = {},
	resourceAuras = {},
    talents = {},
    pvptalents = {},
	auras = {},
	auraList = {},
    powers = {},
	gear = {},
    setBonuses = {},

	knownAuraAttributes = {},

    stateExprs = {},
    stateFuncs = {},
    stateTables = {},

	abilities = {},
	abilityByName = {},
    abilityList = {},
    itemList = {},
    itemMap = {},
    itemPack = {
        lists = {
            items = {}
        }
    },

    packs = {},

    pets = {},
    totems = {},

    potions = {},
    potionList = {},

	hooks = {},
    range = 8,
	settings = {},
    stances = {},
	toggles = {},
	variables = {},
}

Hekili.Scripts = {
    DB = {},
    Channels = {},
    PackInfo = {},
}

Hekili.State = {}

-- The game client as an addon may read it: ns.Facade (Game/API/Facade.lua) under its public name, the one engine
-- name the content addons use besides the registration API, State and Class (restructure plan, Task 8).
Hekili.Client = Facade

-- The engine's public surface, filled by the Engine/ files: Output.lua (Output, Subscribe, Unsubscribe),
-- Registry.lua (Registry, Evaluate), Snapshot.lua (Snapshot), Settings.lua (Configure, settings).
Hekili.Engine = {}

ns.hotkeys = {}
ns.keys = {}
ns.targets = {}
ns.TTD = {}

ns.UI = {
    Displays = {},
    Buttons = {}
}

ns.debug = {}
ns.snapshots = {}


function Hekili:Query( ... )
	local output = ns

	for i = 1, select( '#', ... ) do
		output = output[ select( i, ... ) ]
    end

    return output
end


function Hekili:Run( ... )
	local n = select( "#", ... )
	local fn = select( n, ... )

	local func = ns

	for i = 1, fn - 1 do
		func = func[ select( i, ... ) ]
    end

    return func( select( fn, ... ) )
end


local debug = ns.debug
local active_debug
local current_display

local lastIndent = 0

function Hekili:SetupDebug( display )
    if not self.ActiveDebug then return end
    if not display then return end

    current_display = display

    debug[ current_display ] = debug[ current_display ] or {
        log = {},
        index = 1
    }
    active_debug = debug[ current_display ]
	active_debug.index = 1

	lastIndent = 0

	local pack = self.State.system.packName

    if not pack then return end

	self:Debug( "New Recommendations for [ %s ] requested at %s ( %.2f ); using %s( %s ) priority.", display, date( "%H:%M:%S"), GetTime(), self.DB.profile.packs[ pack ].builtIn and "built-in " or "", pack )
end


function Hekili:Debug( ... )
    if not self.ActiveDebug then return end
	if not active_debug then return end

	local indent, text = ...
	local start

	if type( indent ) ~= "number" then
		indent = lastIndent
		text = ...
		start = 2
	else
		lastIndent = indent
		start = 3
	end

	local prepend = format( indent > 0 and ( "%" .. ( indent * 4 ) .. "s" ) or "%s", "" )
	text = text:gsub("\n", "\n" .. prepend )
    text = format( "%" .. ( indent > 0 and ( 4 * indent ) or "" ) .. "s", "" ) .. text

    if select( start, ... ) ~= nil then
	    active_debug.log[ active_debug.index ] = format( text, select( start, ... ) )
    else
        active_debug.log[ active_debug.index ] = text
    end
    active_debug.index = active_debug.index + 1
end





ns.Tooltip = CreateFrame( "GameTooltip", "HekiliTooltip", UIParent, "GameTooltipTemplate" )
Hekili:ProfileFrame( "HekiliTooltip", ns.Tooltip )
