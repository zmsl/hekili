-- Forever/Warrior.lua
-- Load-only stub for the Forever Warrior (pseudo-spec 1491): registers the spec, its rage resource and an empty
-- default priority so the engine initializes and runs. No abilities and no real APL; Phase 3b replaces this file.
-- Credits: Hekili (registration API and pack format); call shapes from the retail Warrior modules in archive/.

local addon, ns = ...
local VGA = LibStub( "VirtualGameAPI-1.0" )
local UnitClassBase = VGA.UnitClassBase
local Hekili = _G[ addon ]

if UnitClassBase( "player" ) ~= "WARRIOR" then return end

local spec = Hekili:NewSpecialization( 1491, false, 135328 ) -- inv_sword_27; numeric because Options formats it with %d
if not spec then return end

spec:RegisterResource( Enum.PowerType.Rage )

spec:RegisterOptions( { package = "Warrior" } )

-- Payload: spec 1491, lists { precombat = {}, default = {} }. The share format is required (RestoreDefaults decodes it
-- with DeserializeActionPack); generated headless with the vendored LibDeflate and AceSerializer.
spec:RegisterPack( "Warrior", 20261014, [[Hekili:LbzqRnmmmu4Fm9Y6HvA6kd225n2gJYapy3ewXwzXuh7GTYGCX)2NCtPmOxcskV33twqd8fOSitWHDB3DFZ2M9GINhjqnIMJ4psrahKVFJPKlMQZN9r0wn2o588BbO9Ag5rYahA2)qdO6DwlTOIYgq9Hy)2yWpx0zEQTO7IPIM7PI(LyI(LKUZXTPOFEyKfLJ1whp)ur)zpMfT3jorRnF2AIqFrhd0gzhtXoNx26vRUM5sQpw0HOaWWUyqymtCrFZf0RlVdkXvw(7)FxExMZNoAuho5zPKR5rM4qlU0kdWjUVESELo68ob8LLOM96tIG)(d]] )
