-- Engine/Shared.lua
-- Shared content (shared-content spec §3). `Hekili:NewShared()` returns a registration object the content files
-- (Forever/Shared/<File>.lua) use like a race pack's (Engine/Races.lua): RegisterAbility, RegisterAura,
-- RegisterResourceMod, RegisterCostMod. Always live, for every class and race, into the shared `all` spec, whose entries
-- the class's own win in the merge (Engine/Spec.lua) and a race pack's replace (ns.applyRace).

local addon, ns = ...
local Hekili = _G[ addon ]

local function all()
    return Hekili.Class.specs[ 0 ]
end

local Shared = {}
Shared.__index = Shared

function Shared:RegisterAbility( key, def )
    all():RegisterAbility( key, def )
end

function Shared:RegisterAura( key, def )
    all():RegisterAura( key, def )
end

--- { max = pct }: every resource the loaded class registered gets pct more maximum (the race object's signature).
function Shared:RegisterResourceMod( def )
    if type( def.max ) == "number" then
        local m = ns.raceMods.maxMods
        m[ #m + 1 ] = { pct = def.max }
    end
end

function Shared:RegisterCostMod( def )
    ns.RegisterCostMod( def )
end

function Hekili:NewShared()
    return setmetatable( {}, Shared )
end
