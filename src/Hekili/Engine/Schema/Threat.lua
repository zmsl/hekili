-- Engine/Schema/Threat.lua: the `threat` state table on the `all` pseudo-spec (moved from Engine/Schema/Spec.lua).

local addon, ns = ...
local Facade = ns.Facade
local UnitCanAttack, UnitExists, UnitIsUnit = Facade.UnitCanAttack, Facade.UnitExists, Facade.UnitIsUnit
local UnitThreatSituation, issecretvalue = Facade.UnitThreatSituation, Facade.issecretvalue
local Hekili = _G[addon]

local all = Hekili.Class.specs[0]

-- Threat (tank design §2), read on demand through the facade's plain rows, a secret answer as 0 or false:
-- `situation` UnitThreatSituation( "player", "target" ) (0-3); `on_me` the hostile target attacks us; `lost` the
-- hostile target attacks someone else (a friendly or secret UnitCanAttack: neither); `loose` the hostiles attacking
-- someone else (VirtualState.LooseEnemies). No caching, no allocation. Every name is upvalued: Register's
-- setfenv( __index, state ) leaves upvalues alone.
local LooseEnemies = ns.VirtualState.LooseEnemies

local function plain(v)
    if issecretvalue(v) then
        return nil
    end
    return v
end

all:RegisterStateTable(
    "threat",
    setmetatable({}, {
        __index = function(t, k)
            if k == "situation" then
                return plain(UnitThreatSituation("player", "target")) or 0
            elseif k == "on_me" then
                return plain(UnitCanAttack("player", "target")) == true
                    and plain(UnitIsUnit("targettarget", "player")) == true
            elseif k == "lost" then
                return plain(UnitCanAttack("player", "target")) == true
                    and plain(UnitExists("targettarget")) == true
                    and plain(UnitIsUnit("targettarget", "player")) == false
            elseif k == "loose" then
                return LooseEnemies()
            end
        end,
    })
)
