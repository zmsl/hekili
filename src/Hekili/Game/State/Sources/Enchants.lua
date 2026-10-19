-- Game/State/Sources/Enchants.lua
-- Weapon-enchant sources (C4): a player aura with `weaponEnchant = slot` (Enum.WeaponSlot: 0 main hand, 1 off hand; an
-- id-less pseudo-aura, so the walk never lists it) is read from C_Item.GetWeaponEnchantInfo(slot), out of combat only:
-- at the first poll after a build and the poll after WEAPON_ENCHANT_CHANGED, UNIT_INVENTORY_CHANGED or combat's end. An
-- enchant is a `Read` up with its time left (ms in the client's answer) and its charges as stacks; none is a `Read`
-- down. In combat our apply cast's modelled expiry stands. Unprobed (Rogue Q9): a secret answer or field reads nothing.
-- Credits: secret-value handling after Catnip's (Durts) research.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, ReadOf = VS.Obs, I.ReadOf
local Plain, Direct, Note = S.Plain, S.Direct, S.Note

-- By aura index: the weapon slot its `weaponEnchant` names (Sources/Auras.lua's walk leaves these alone); by slot: the
-- aura index (the facade's policy).
local slotOf, auraOf = {}, {}
I.enchantAura, I.enchantSlot = slotOf, auraOf
local pending = false

I.OnBuild(function(def)
    for j in pairs(slotOf) do
        slotOf[j] = nil
    end
    auraOf[0], auraOf[1] = nil, nil
    for j = 1, #def.auras do
        local slot = rawget(def.auras[j], "weaponEnchant")
        if slot == 0 or slot == 1 then
            slotOf[j], auraOf[slot] = slot, j
        end
    end
    pending = true
end)

local function enchants(api, slot)
    return api.C_Item.GetWeaponEnchantInfo(slot) -- secret: Plain by the caller, then each field
end

-- One slot's read into aura j at t; nothing when any part is secret. Allocates nothing (the client allocates its list).
local function read(api, j, slot, t)
    local ok, raw = pcall(enchants, api, slot)
    local list = ok and Plain(api, raw)
    if type(list) ~= "table" then
        Note("GetWeaponEnchantInfo", ok and S.StatusOf(api, raw) or "error")
        return
    end
    local left, charges = nil, 0
    for i = 1, #list do
        local e = Plain(api, list[i])
        if type(e) ~= "table" then
            Note("GetWeaponEnchantInfo", "secret")
            return
        end
        local has, ms, n = Plain(api, e.hasEnchant), Plain(api, e.timeLeft), Plain(api, e.charges)
        if has == nil or ms == nil or n == nil then
            Note("GetWeaponEnchantInfo", "secret")
            return
        end
        if has == true and type(ms) == "number" then
            left, charges = ms > 0 and ms / 1000 or -1, type(n) == "number" and n or 0 -- -1: up with no expiry
        end
    end
    Note("GetWeaponEnchantInfo", "readable")
    if left then
        Direct(Obs.Read, t, j, left, ReadOf.Aura + charges * I.AURA_STACK) -- a = j: unit 1, the player
    else
        Direct(Obs.Read, t, j, 0, ReadOf.Aura)
    end
end

local function changed()
    pending = true
end
S.On("WEAPON_ENCHANT_CHANGED", nil, changed)
S.On("UNIT_INVENTORY_CHANGED", "player", changed)
S.On("PLAYER_REGEN_ENABLED", nil, changed)

-- Poll 12: the slots' reads, once per change and only out of combat.
S.Poll(12, function(api, t)
    if not pending or I.inCombat or not I.built then
        return
    end
    pending = false
    for slot = 0, 1 do
        local j = auraOf[slot]
        if j then
            read(api, j, slot, t)
        end
    end
end)
