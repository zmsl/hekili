-- Game/State/Sources/Pets.lua
-- The pet unit's source (class-completion C1): UnitExists and UnitIsDead of "pet", plain in combat [W PR14; gate spike],
-- each through Plain first, and the pet's power (UnitPower("pet"), plain 0 with no pet [W PR12]; unprobed with one). UNIT_PET (player) always stages a `Pet` observation, which overrides our summon's model
-- (Families/Pets.lua); poll 13 logs one only when the answer changed (a death, a pet that appeared or left), so a
-- summon whose pet has not appeared yet is not overridden by the same "no pet" again. A secret answer is no news, and
-- the next plain one logs.
-- Ported from Taco Dog Forever, the pet half of src/TacoDogForever/Sources/Pets.lua (readPet, poll 7).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Direct = S.Plain, S.Stage, S.Direct

-- The last answer logged (exists 1/0, dead 1/0; -1 before any, or after a secret one; the power, -1 secret).
local lastA, lastB, lastC = -1, -1, -1

local function read(api, t, event)
    local e = Plain(api, api.UnitExists("pet")) -- secret: Plain first
    local d = e and Plain(api, api.UnitIsDead("pet")) -- secret: Plain first; no unit: not dead
    if e == nil or d == nil then
        lastA = -1
        return
    end
    local a, b, c = e and 1 or 0, d and 1 or 0, 0
    if e then
        local p = Plain(api, api.UnitPower("pet")) -- secret: Plain first
        c = type(p) == "number" and p or -1
    end
    if event then
        Stage(Obs.Pet, t, a, b, c)
    elseif a ~= lastA or b ~= lastB or c ~= lastC then
        Direct(Obs.Pet, t, a, b, c)
    else
        return
    end
    lastA, lastB, lastC = a, b, c
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
