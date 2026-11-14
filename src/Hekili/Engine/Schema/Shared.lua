-- Engine/Schema/Shared.lua
-- Shared content (shared-content spec §3). `Hekili:NewShared()` returns a registration object the content files
-- (Hekili_Shared/Shared/<File>.lua) use like a race pack's (Engine/Schema/Races.lua): RegisterAbility, RegisterAura,
-- RegisterResourceMod, RegisterCostMod, RegisterRegenMod, and RegisterStateExpr. Always live, for every class and race, into the shared
-- `all` spec, whose entries the class's own win in the merge (Engine/Schema/Spec/Activation.lua) and a race pack's replace
-- (ns.applyRace).

local addon, ns = ...
local Hekili = _G[addon]

local function all()
    return Hekili.Class.specs[0]
end

local Shared = {}
Shared.__index = Shared

function Shared:RegisterAbility(key, def)
    all():RegisterAbility(key, def)
end

function Shared:RegisterAura(key, def)
    all():RegisterAura(key, def)
end

function Shared:RegisterStateExpr(key, func)
    all():RegisterStateExpr(key, func)
end

--- { max = pct }: every resource the loaded class registered gets pct more maximum (the race object's signature).
function Shared:RegisterResourceMod(def)
    if type(def.max) == "number" then
        -- ns.raceMods comes from Engine\Races.lua, which Hekili.toc loads before this file (line 51 before 55).
        local m = ns.raceMods.maxMods
        m[#m + 1] = { pct = def.max }
    end
end

function Shared:RegisterCostMod(def)
    ns.RegisterCostMod(def)
end

--- A regen entry on resource `def.resource` while the player's aura `def.aura` is up, for every class that has the
--- resource (the race object's RegisterRegenMod signature: Races.lua, read by Tracked.lua).
function Shared:RegisterRegenMod(def)
    if type(def.resource) == "string" and type(def.aura) == "string" then
        local m = ns.raceMods.regenMods
        m[#m + 1] = def
    end
end

function Hekili:NewShared()
    return setmetatable({}, Shared)
end
