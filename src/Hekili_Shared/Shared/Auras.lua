-- Hekili_Shared/Shared/Auras.lua
-- The auras every class shares on Forever (shared-content spec §4.1), through Engine/Schema/Shared.lua into `all`: auras others
-- put on the player, which the player's aura walk reads in combat (lust, Power Infusion, dispellable
-- debuffs), the per-school lockouts, and four id-less stubs for the keys core still reads by name. Lusts and lockouts
-- Forever's DB2 lacks, the target-side reads (a target's auras are secret in combat, but Thunderfury's slow, which a priority names) and the absorbs are left out (spec §4.1);
-- class buffs live in their class files and racials in the race packs.

local Client = Hekili.Client
local C_LossOfControl = Client.C_LossOfControl
local GetActiveLossOfControlData, GetActiveLossOfControlDataCount =
    C_LossOfControl.GetActiveLossOfControlData, C_LossOfControl.GetActiveLossOfControlDataCount
local GetDebuffDataByIndex, UnpackAuraData = Client.C_UnitAuras.GetDebuffDataByIndex, Client.AuraUtil.UnpackAuraData

-- The classic UnitDebuff over the client's aura rows (Engine/Sim/Utils.lua's, which content does not reach).
local function UnitDebuff(unit, index, filter)
    return UnpackAuraData(GetDebuffDataByIndex(unit, index, filter))
end

local shared = Hekili:NewShared()

-- Per school, whether an interrupt has it locked out at the query time (C10): `locked_out_fire` and so on, from
-- C_LossOfControl (plain); a lockout's `lockoutSchool` is the mask of the schools it locks (0: no school).
local SCHOOLS = Hekili.SCHOOL
local floor = math.floor
for school, mask in pairs(SCHOOLS) do
    -- shortcut: allocates a table per active lockout per read (C_LossOfControl.GetActiveLossOfControlData); upgrade before a caster APL reads locked_out_* in combat
    shared:RegisterStateExpr("locked_out_" .. school, function()
        for i = 1, GetActiveLossOfControlDataCount() do
            local event = GetActiveLossOfControlData(i)
            local locks, start, duration =
                event and event.lockoutSchool, event and event.startTime, event and event.duration
            if locks and start and duration and floor(locks / mask) % 2 == 1 and start + duration > query_time then
                return true
            end
        end
        return false
    end)
end

-- The player's first debuff of one dispel type (the RAID filter: ones the player could dispel), as an aura.
local function dispellable(dispelType)
    return function(t)
        local i = 1
        local name, _, count, debuffType, duration, expirationTime = UnitDebuff("player", i, "RAID")

        while name do
            if debuffType == dispelType then
                break
            end

            i = i + 1
            name, _, count, debuffType, duration, expirationTime = UnitDebuff("player", i, "RAID")
        end

        if name then
            t.count = count > 0 and count or 1
            t.expires = expirationTime > 0 and expirationTime or query_time + 5
            t.applied = expirationTime > 0 and (expirationTime - duration) or query_time
            t.caster = "nobody"
            return
        end

        t.count = 0
        t.expires = 0
        t.applied = 0
        t.caster = "nobody"
    end
end

local auras = {
    -- Core reads these by name (State.lua: the cooldown read, `prowling`, the GCD's length); none exists on Forever, so
    -- each is a stub with no ID, never up. Smaller than the core edit removing the reads (spec §4.1).
    voidbinding = {},
    voidform = {},
    shadowform = {},
    adrenaline_rush = {},

    -- State.lua's cooldowns toggle override reads buff.bloodlust.up. Forever's one haste "Bloodlust" (DB2: 3 s cast, no
    -- duration, no class): kept until the checkpoint shows what a Shaman's lust puts on the player (spec §7 Q2).
    bloodlust = {
        alias = { "bloodlust_actual" },
        aliasMode = "first",
        aliasType = "buff",
        duration = 3600,
    },

    bloodlust_actual = {
        id = 1245940,
        duration = 3600, -- until cancelled (DB2 -1); the player walk reads the real expiry
        shared = "player",
        max_stack = 1,
    },

    -- Weapon enchants (C4): the hand's imbue layer (Shaman imbues, probed; poisons, Firestone, Spellstone and scrolls of
    -- imbue inferred from the DB2's effect), never its temporary layer (stones and oils, inferred). Id-less pseudo-auras read from C_Item.GetWeaponEnchantInfo, in combat too, the
    -- charges as stacks; a pack's apply ability `applyBuff`s one to model it between reads. A single imbue or poison
    -- is its pack's own `enchants` aura (buff.windfury_weapon, buff.deadly_poison).
    main_hand_enchant = {
        weaponEnchant = 0,
        duration = 3600,
        max_stack = 1,
    },
    off_hand_enchant = {
        weaponEnchant = 1,
        duration = 3600,
        max_stack = 1,
    },

    -- Another Priest's on the player (State.lua's infusion toggle); 15 s on Forever (DB2).
    power_infusion = {
        id = 10060,
        duration = 15,
        max_stack = 1,
        shared = "player",
        dot = "buff",
    },

    -- Thunderfury's slow (the weapon's proc; no cast of ours applies it, so it reads up only from the client: a target's
    -- auras are secret in combat, hence down there): registered so the wowsims priorities' `!debuff.thunderfury.up` term translates.
    thunderfury = {
        id = 27648,
        duration = 12,
        max_stack = 1,
        shared = "target",
    },

    dispellable_curse = { generate = dispellable("Curse") },
    dispellable_poison = { generate = dispellable("Poison") },
    dispellable_disease = { generate = dispellable("Disease") },
    reversible_magic = { generate = dispellable("Magic") },
}

-- The weapon enchant 8217's proc buff (wowsims enchants.go revelationBuffs), one id per class group, 15 s, one charge: the
-- mage, priest, druid, hunter and paladin ones (the Warlock's and Shaman's are their packs' own `revelation`).
for _, id in ipairs({ 1248808, 1323377, 1323400, 1323410, 1323419 }) do
    auras["revelation_" .. id] = { id = id, duration = 15, max_stack = 1 }
end

-- The player's magic debuffs only, as reversible_magic: a target's buffs are secret in combat (spec §4.1, rule 4).
auras.dispellable_magic = { generate = auras.reversible_magic.generate }

for key, def in pairs(auras) do
    shared:RegisterAura(key, def)
end
