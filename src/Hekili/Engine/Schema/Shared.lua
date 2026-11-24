-- Engine/Schema/Shared.lua
-- Shared content (shared-content spec §3). `Hekili:NewShared()` returns a registration object the content files
-- (Hekili_Shared/Shared/<File>.lua) use like a race pack's (Engine/Schema/Races.lua): RegisterAbility, RegisterAura,
-- RegisterResourceMod, RegisterCostMod, RegisterRegenMod, RegisterStateExpr and RegisterTtdLines. Always live, for
-- every class and race, into the shared `all` spec, whose entries the class's own win in the merge (Engine/Schema/Spec/Activation.lua) and a race pack's replace
-- (ns.applyRace).

local addon, ns = ...
local Hekili = _G[addon]
local L = ns.L -- top level: tools/locales.py reads a file's strings only with this line (the locales load first)

local function all()
    return Hekili.Class.specs[0]
end

-- [class token] = pct: Shared:RegisterTtdLines' table, read by the time-to-die hints (Engine/Sim/Targets.lua). Held
-- here, so content registers without the simulation loaded.
ns.ttdLines = {}

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

--- { [class token] = pct }: each class's default execute line, no talents (lane B8, owner L1658): the core hints the
--- highest line present in the group to the time-to-die library (Engine/Sim/Targets.lua). A later call adds or replaces.
function Shared:RegisterTtdLines(def)
    for token, pct in pairs(def) do
        if type(token) == "string" and type(pct) == "number" then
            ns.ttdLines[token] = pct
        end
    end
end

-- { key, value, option }: Shared:RegisterSetting's settings, registered on every spec of the class when its kit is
-- built (Spec/Kits.lua NewClass: the shared content loads before the class pack).
ns.sharedSettings = {}

--- (L1808) A spec setting every pack may read (a line the translator emits in every pack: the Healthstone's): kept
--- here and registered on each of the class's specs, as the kit's own RegisterSetting with no spec list.
function Shared:RegisterSetting(key, value, option)
    local s = ns.sharedSettings
    s[#s + 1] = { key, value, option }
end

--- (L1808, owner "Setting per line") A defensive line's player-health threshold setting's option (RegisterSetting's
--- `option`; spec:HealthOption and shared:HealthOption): a 1-100 slider, read by the line as `settings.<key>`; its
--- name and text name ability `ability` (the client's name, read when the options open; the key until it loads). A
--- fresh table each call (load only). The registry is read when the options ask, not here.
function ns.HealthOption(ability)
    local function label()
        local a = Hekili.Class.abilities[ability]
        return a and a.name or ability
    end
    return {
        type = "range",
        min = 1,
        max = 100,
        step = 1,
        width = "full",
        name = function()
            return string.format(L["%s: at or below this health (%%)"], label())
        end,
        desc = function()
            return string.format(
                L["The priority shows %s in the Defensives display once your health is at or below this percentage, and only while Hekili can read your health in combat."],
                label()
            )
        end,
    }
end

--- ns.HealthOption, for a shared line's setting.
function Shared:HealthOption(ability)
    return ns.HealthOption(ability)
end

function Hekili:NewShared()
    return setmetatable({}, Shared)
end
