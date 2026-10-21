-- Game/State/Families/Pets.lua
-- The pets family (class-completion C1): the pet unit and the capped guardians.
-- The pet unit: Sources/Pets.lua observes it (UnitExists / UnitIsDead of "pet", plain). Our summon's `now`
-- (`summonPet`, Families/Now.lua) models it up (I.PetModel) until the first observation after the summon, or for
-- CAST_GRACE when none comes: a summon whose pet never appears is down after the cast window. Our `dismissPet` models
-- it down the same way. Its power: the last plain UnitPower("pet") the source logged (VS.PetPower).
-- Guardians: a pet the content registers with a `cap` (RegisterPets) has its own guardians, one expiry per summon;
-- at the cap the soonest to expire (the oldest) gives way. Nothing observes them; they are modelled only.
-- Ported from Taco Dog Forever, the pet half of src/TacoDogForever/Model/Belief/Pets.lua (Applier Pet :36).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs

-- The pet unit: the last observation's facts (kept across builds, as the unit is); its record.
local exists, dead = false, false
local power = 0 -- the pet's power as last read plain (0: no pet)
local rec -- nil before the first build
-- Guardians by key: the cap's expiry slots (0: free) and the duration the content registered (false: none).
local slots, regDur = {}, {}

I.OnBuild(function(def, now)
    rec = I.NewBelief("pet")
    I.Sample(rec, "default", 0, now, 0)
    for k in pairs(slots) do
        slots[k], regDur[k] = nil, nil
    end
    local list = def.pets
    for i = 1, list and #list or 0 do
        local p = list[i]
        local s = {}
        for j = 1, p.cap do
            s[j] = 0
        end
        slots[p.key], regDur[p.key] = s, type(p.duration) == "number" and p.duration or false
    end
end)

-- Pet (a: the unit exists 1/0, -1 a power-only change; b: it is dead 1/0; c: its power, -1 a secret read) at t.
I.On(Obs.Pet, function(o, t)
    if o.c >= 0 then
        power = o.c
    end
    if o.a < 0 then
        return
    end
    exists, dead = o.a == 1, o.b == 1
    I.Sample(rec, "observed", (exists and not dead) and 1 or 0, t, Obs.Pet)
end)

--- Our summon of `key` at `t`: a guardian's slot expires `dur` s later (no number: the registered duration; neither
--- writes nothing); any other key models the pet unit up. Allocates nothing.
function I.PetModel(key, dur, t, event)
    local s = slots[key]
    if not s then
        I.Sample(rec, "modelled", 1, t, event)
        return
    end
    dur = type(dur) == "number" and dur or regDur[key]
    if not dur then
        return
    end
    local j = 1
    for k = 2, #s do
        if s[k] < s[j] then
            j = k -- a free slot (0) or the soonest to expire: at the cap, the oldest guardian gives way
        end
    end
    s[j] = t + dur
end

--- Our dismissal of `key` at `t`: a guardian's slots free; any other key models the pet unit down. Allocates nothing.
function I.PetDismiss(key, t, event)
    local s = slots[key]
    if not s then
        I.Sample(rec, "modelled", 0, t, event)
        return
    end
    for j = 1, #s do
        s[j] = 0
    end
end

--- (C1) The pet unit at `now`: exists, dead, whether that is our summon's or dismissal's model (no observation since
--- it, inside CAST_GRACE), and its record. Allocates nothing.
function VS.Pet(now)
    if not rec then
        return exists, dead, false, I.UNKNOWN
    end
    if rec.basis == "modelled" and now - rec.last.modelled.t <= I.CAST_GRACE then
        local up = rec.last.modelled.v == 1
        rec.est = up and 1 or 0
        return up, false, true, rec
    end
    rec.est = (exists and not dead) and 1 or 0
    return exists, dead, false, rec
end

--- (C1) The guardians of `key` up at `now` and the last one's expiry (0, 0 for none or an untracked key). Allocates
--- nothing.
function VS.PetCount(key, now)
    local s = slots[key]
    local n, last = 0, 0
    for j = 1, s and #s or 0 do
        local e = s[j]
        if e > now then
            n = n + 1
            if e > last then
                last = e
            end
        end
    end
    return n, last
end

--- The pet's power as last read plain (its own power type, UnitPower("pet")), 0 with no pet or before a read.
--- shortcut: no pet regen or spend model; UnitPower("pet") is unprobed with a pet out (SecretWhenUnitPowerRestricted
--- in the API docs; plain 0 with none, probe W PR12): model it if an in-game check finds it secret.
function VS.PetPower()
    return power
end
