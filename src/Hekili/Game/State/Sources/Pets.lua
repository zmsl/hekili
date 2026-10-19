-- Game/State/Sources/Pets.lua
-- The pet unit's source (class-completion C1): UnitExists and UnitIsDead of "pet", plain in combat [W PR14; gate spike],
-- each through Plain first. UNIT_PET (player) always stages a `Pet` observation, which overrides our summon's model
-- (Families/Pets.lua); poll 13 logs one only when the answer changed (a death, a pet that appeared or left), so a
-- summon whose pet has not appeared yet is not overridden by the same "no pet" again. A secret answer is no news, and
-- the next plain one logs.
-- Ported from Taco Dog Forever, the pet half of src/TacoDogForever/Sources/Pets.lua (readPet, poll 7).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Direct = S.Plain, S.Stage, S.Direct

-- The last answer logged (exists 1/0, dead 1/0; -1 before any, or after a secret one).
local lastA, lastB = -1, -1

local function read(api, t, event)
    local e = Plain(api, api.UnitExists("pet")) -- secret: Plain first
    local d = e and Plain(api, api.UnitIsDead("pet")) -- secret: Plain first; no unit: not dead
    if e == nil or d == nil then
        lastA = -1
        return
    end
    local a, b = e and 1 or 0, d and 1 or 0
    if event then
        Stage(Obs.Pet, t, a, b)
    elseif a ~= lastA or b ~= lastB then
        Direct(Obs.Pet, t, a, b)
    else
        return
    end
    lastA, lastB = a, b
end

S.On("UNIT_PET", "player", function(api, t, unit)
    if unit == "player" then
        read(api, t, true)
    end
end)

-- Poll 13: the pet unit, logged on a change. Allocates nothing.
S.Poll(13, function(api, t)
    read(api, t, false)
end)
