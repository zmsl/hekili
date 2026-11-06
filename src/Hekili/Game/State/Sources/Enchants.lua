-- Game/State/Sources/Enchants.lua
-- Weapon-enchant sources (C4), read from C_Item.GetWeaponEnchantInfo(slot) (Enum.WeaponSlot: 0 main hand, 1 off hand):
-- a list per slot, one entry per enchant layer (Forever: a temporary layer, enchantType 2, for stones and oils; an imbue
-- layer for imbues, poisons and the like), matched by contents, never by position. Two kinds of id-less player aura
-- (so the walk never lists them):
-- - `weaponEnchant = slot`: the slot's pseudo-aura, up while that slot carries an enchant of any layer but the
--   temporary one;
-- - `enchants = { enchant IDs }`: up while either slot carries one of its IDs.
-- An enchant is a `Read` up with its time left (ms in the client's answer) and its charges as stacks; none is a `Read`
-- down. Read at the first poll after a build and the poll after WEAPON_ENCHANT_CHANGED or WEAPON_SLOT_CHANGED (in combat
-- too: plain in combat, probe 2026-11-05, Shaman L10, open world and a dungeon), or UNIT_INVENTORY_CHANGED or combat's
-- end (out of combat: UNIT_INVENTORY_CHANGED also fires on durability). Between reads our apply cast's model stands.
-- A secret answer or field reads nothing, and while either slot is unread no `enchants` aura is taken down (unknown is
-- never missing). A 0 time left (the client's first seconds after login) is unknown too: that aura keeps its belief
-- until the next read.
-- Credits: secret-value handling after Catnip's (Durts) research.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, ReadOf = VS.Obs, I.ReadOf
local Plain, Direct, Note = S.Plain, S.Direct, S.Note

-- By aura index: its weapon slot, or true for an `enchants` aura (Sources/Auras.lua's walk leaves these alone); by
-- slot: the slot's pseudo-aura index (the facade's policy); by enchant ID: its `enchants` aura index.
local slotOf, auraOf, byEnchant = {}, {}, {}
I.enchantAura, I.enchantSlot = slotOf, auraOf
-- Every aura index above, and per read (preallocated, cleared per read): its finding (nil unread, false down, true
-- unknown, or its time left in seconds) and its charges.
local watched, found, stacksOf = { n = 0 }, {}, {}
local pending = false

I.OnBuild(function(def)
    for j in pairs(slotOf) do
        slotOf[j], found[j], stacksOf[j] = nil, nil, nil
    end
    for id in pairs(byEnchant) do
        byEnchant[id] = nil
    end
    auraOf[0], auraOf[1], watched.n = nil, nil, 0
    for j = 1, #def.auras do
        local slot, ids = rawget(def.auras[j], "weaponEnchant"), rawget(def.auras[j], "enchants")
        if slot == 0 or slot == 1 then
            slotOf[j], auraOf[slot] = slot, j
        elseif type(ids) == "table" then
            slotOf[j] = true
            for k = 1, #ids do
                byEnchant[ids[k]] = j
            end
        end
        if slotOf[j] ~= nil then
            watched.n = watched.n + 1
            watched[watched.n] = j
        end
    end
    pending = true
end)

local function enchants(api, slot)
    return api.C_Item.GetWeaponEnchantInfo(slot) -- secret: Plain by the caller, then each field
end

-- True when every entry and every field the read uses is plain.
local function plainList(api, list)
    for i = 1, #list do
        local e = Plain(api, list[i])
        if
            type(e) ~= "table"
            or Plain(api, e.hasEnchant) == nil
            or Plain(api, e.timeLeft) == nil
            or Plain(api, e.charges) == nil
            or Plain(api, e.enchantType) == nil
            or Plain(api, e.enchantID) == nil
        then
            return false
        end
    end
    return true
end

-- Aura j seen with `left` (seconds, or true: unknown) and `n` charges: unknown wins, else the longer.
local function see(j, left, n)
    local f = found[j]
    if f == true then
        return
    end
    if left == true or not f or left > f then
        found[j], stacksOf[j] = left, n
    end
end

-- One slot's list into `found`; false (nothing written) when the answer or any field is secret. Allocates nothing (the
-- client allocates its list).
local function readSlot(api, slot)
    local ok, raw = pcall(enchants, api, slot)
    local list = ok and Plain(api, raw)
    if type(list) ~= "table" then
        Note("GetWeaponEnchantInfo", ok and S.StatusOf(api, raw) or "error")
        return false
    end
    if not plainList(api, list) then
        Note("GetWeaponEnchantInfo", "secret")
        return false
    end
    Note("GetWeaponEnchantInfo", "readable")
    local alias = auraOf[slot]
    if alias then
        found[alias] = false
    end
    for i = 1, #list do
        local e = list[i] -- every field plain (plainList)
        local ms = e.timeLeft
        if e.hasEnchant == true and type(ms) == "number" then
            local left, n = true, type(e.charges) == "number" and e.charges or 0
            if ms > 0 then
                left = ms / 1000
            end
            local j = byEnchant[e.enchantID]
            if j then
                see(j, left, n)
            end
            if alias and e.enchantType ~= 2 then -- the temporary layer (a stone, an oil) is not the slot's
                see(alias, left, n)
            end
        end
    end
    return true
end

local function changed()
    pending = true
end
local function outOfCombat()
    if not I.inCombat then
        pending = true
    end
end
S.On("WEAPON_ENCHANT_CHANGED", nil, changed)
S.On("WEAPON_SLOT_CHANGED", nil, changed)
S.On("UNIT_INVENTORY_CHANGED", "player", outOfCombat)
S.On("PLAYER_REGEN_ENABLED", nil, changed)

-- Poll 12: both slots' reads, once per change (a burst of events is one read).
S.Poll(12, function(api, t)
    if not pending or not I.built then
        return
    end
    pending = false
    local n = watched.n
    if n == 0 then
        return
    end
    for k = 1, n do
        found[watched[k]] = nil
    end
    local all = readSlot(api, 0)
    all = readSlot(api, 1) and all
    for k = 1, n do
        local j = watched[k]
        local f = found[j]
        if f == nil and all and slotOf[j] == true then
            f = false -- an `enchants` aura no slot carries
        end
        if f == false then
            Direct(Obs.Read, t, j, 0, ReadOf.Aura)
        elseif f ~= nil and f ~= true then
            Direct(Obs.Read, t, j, f, ReadOf.Aura + stacksOf[j] * I.AURA_STACK) -- a = j: unit 1, the player
        end
    end
end)
