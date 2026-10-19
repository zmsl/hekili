-- Hekili_Shared/Shared/Auras.lua
-- The auras every class shares on Forever (shared-content spec §4.1), through Engine/Schema/Shared.lua into `all`: auras others
-- put on the player, which the player's aura walk reads in combat (lust, Power Infusion, loss of control, dispellable
-- debuffs), the per-school lockouts, and four id-less stubs for the keys core still reads by name. Retail's other lusts
-- and lockouts, the target-side reads (a target's auras are secret in combat) and the absorbs were dropped (spec §4.1);
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
local SCHOOLS = { physical = 1, holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64 }
local floor = math.floor
for school, bit in pairs(SCHOOLS) do
    shared:RegisterStateExpr("locked_out_" .. school, function()
        for i = 1, GetActiveLossOfControlDataCount() do
            local event = GetActiveLossOfControlData(i)
            local mask, start, duration =
                event and event.lockoutSchool, event and event.startTime, event and event.duration
            if mask and start and duration and floor(mask / bit) % 2 == 1 and start + duration > query_time then
                return true
            end
        end
        return false
    end)
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

    -- Weapon enchants (C4): poisons, imbues, stones, oils. Id-less pseudo-auras read out of combat from
    -- C_Item.GetWeaponEnchantInfo, the charges as stacks; a pack's apply ability `applyBuff`s one to model it in combat.
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

    loss_of_control = {
        duration = 10,
        generate = function(t)
            local max_events = GetActiveLossOfControlDataCount()

            if max_events > 0 then
                local spell, start, duration, remains = 0, 0, 0, 0

                for i = 1, max_events do
                    local event = GetActiveLossOfControlData(i)

                    if
                        event
                        and event.lockoutSchool == 0
                        and event.startTime
                        and event.startTime > 0
                        and event.timeRemaining
                        and event.timeRemaining > 0
                        and event.timeRemaining > remains
                    then
                        spell = event.spellID
                        start = event.startTime
                        duration = event.duration
                        remains = event.timeRemaining
                    end
                end

                if start + duration > query_time then
                    t.count = 1
                    t.expires = start + duration
                    t.applied = start
                    t.duration = duration
                    t.caster = "anybody"
                    t.v1 = spell
                    return
                end
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.duration = 10
            t.caster = "nobody"
            t.v1 = 0
        end,
    },

    disoriented = { -- Disorients (e.g., Polymorph, Dragon’s Breath, Blind)
        duration = 10,
        generate = function(t)
            local max_events = GetActiveLossOfControlDataCount()

            if max_events > 0 then
                local spell, start, duration, remains = 0, 0, 0, 0

                for i = 1, max_events do
                    local event = GetActiveLossOfControlData(i)

                    if
                        event
                        and event.locType == "CONFUSE"
                        and event.startTime
                        and event.startTime > 0
                        and event.timeRemaining
                        and event.timeRemaining > 0
                        and event.timeRemaining > remains
                    then
                        spell = event.spellID
                        start = event.startTime
                        duration = event.duration
                        remains = event.timeRemaining
                    end
                end

                if start + duration > query_time then
                    t.count = 1
                    t.expires = start + duration
                    t.applied = start
                    t.duration = duration
                    t.caster = "anybody"
                    t.v1 = spell
                    return
                end
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.duration = 10
            t.caster = "nobody"
            t.v1 = 0
        end,
    },

    feared = {
        duration = 10,
        generate = function(t)
            local max_events = GetActiveLossOfControlDataCount()

            if max_events > 0 then
                local spell, start, duration, remains = 0, 0, 0, 0

                for i = 1, max_events do
                    local event = GetActiveLossOfControlData(i)

                    if
                        event
                        and (event.locType == "FEAR" or event.locType == "FEAR_MECHANIC" or event.locType == "HORROR")
                        and event.startTime
                        and event.startTime > 0
                        and event.timeRemaining
                        and event.timeRemaining > 0
                        and event.timeRemaining > remains
                    then
                        spell = event.spellID
                        start = event.startTime
                        duration = event.duration
                        remains = event.timeRemaining
                    end
                end

                if start + duration > query_time then
                    t.count = 1
                    t.expires = start + duration
                    t.applied = start
                    t.duration = duration
                    t.caster = "anybody"
                    t.v1 = spell
                    return
                end
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.duration = 10
            t.caster = "nobody"
            t.v1 = 0
        end,
    },

    incapacitated = { -- Effects like Sap, Freezing Trap, Gouge
        duration = 10,
        generate = function(t)
            local max_events = GetActiveLossOfControlDataCount()

            if max_events > 0 then
                local spell, start, duration, remains = 0, 0, 0, 0

                for i = 1, max_events do
                    local event = GetActiveLossOfControlData(i)

                    if
                        event
                        and event.locType == "STUN"
                        and event.startTime
                        and event.startTime > 0
                        and event.timeRemaining
                        and event.timeRemaining > 0
                        and event.timeRemaining > remains
                    then
                        spell = event.spellID
                        start = event.startTime
                        duration = event.duration
                        remains = event.timeRemaining
                    end
                end

                if start + duration > query_time then
                    t.count = 1
                    t.expires = start + duration
                    t.applied = start
                    t.duration = duration
                    t.caster = "anybody"
                    t.v1 = spell
                    return
                end
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.duration = 10
            t.caster = "nobody"
            t.v1 = 0
        end,
        copy = "sapped",
    },

    rooted = {
        duration = 10,
        generate = function(t)
            local max_events = GetActiveLossOfControlDataCount()

            if max_events > 0 then
                local spell, start, duration, remains = 0, 0, 0, 0

                for i = 1, max_events do
                    local event = GetActiveLossOfControlData(i)

                    if
                        event
                        and event.locType == "ROOT"
                        and event.startTime
                        and event.startTime > 0
                        and event.timeRemaining
                        and event.timeRemaining > 0
                        and event.timeRemaining > remains
                    then
                        spell = event.spellID
                        start = event.startTime
                        duration = event.duration
                        remains = event.timeRemaining
                    end
                end

                if start + duration > query_time then
                    t.count = 1
                    t.expires = start + duration
                    t.applied = start
                    t.duration = duration
                    t.caster = "anybody"
                    t.v1 = spell
                    return
                end
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.duration = 10
            t.caster = "nobody"
            t.v1 = 0
        end,
    },

    snared = {
        duration = 10,
        generate = function(t)
            local max_events = GetActiveLossOfControlDataCount()

            if max_events > 0 then
                local spell, start, duration, remains = 0, 0, 0, 0

                for i = 1, max_events do
                    local event = GetActiveLossOfControlData(i)

                    if
                        event
                        and event.locType == "SNARE"
                        and event.startTime
                        and event.startTime > 0
                        and event.timeRemaining
                        and event.timeRemaining > 0
                        and event.timeRemaining > remains
                    then
                        spell = event.spellID
                        start = event.startTime
                        duration = event.duration
                        remains = event.timeRemaining
                    end
                end

                if start + duration > query_time then
                    t.count = 1
                    t.expires = start + duration
                    t.applied = start
                    t.duration = duration
                    t.caster = "anybody"
                    t.v1 = spell
                    return
                end
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.duration = 10
            t.caster = "nobody"
            t.v1 = 0
        end,
        copy = "slowed",
    },

    stunned = { -- Shorter stuns (e.g., Kidney Shot, Cheap Shot, Bash)
        duration = 10,
        generate = function(t)
            local max_events = GetActiveLossOfControlDataCount()

            if max_events > 0 then
                local spell, start, duration, remains = 0, 0, 0, 0

                for i = 1, max_events do
                    local event = GetActiveLossOfControlData(i)

                    if
                        event
                        and event.locType == "STUN_MECHANIC"
                        and event.startTime
                        and event.startTime > 0
                        and event.timeRemaining
                        and event.timeRemaining > 0
                        and event.timeRemaining > remains
                    then
                        spell = event.spellID
                        start = event.startTime
                        duration = event.duration
                        remains = event.timeRemaining
                    end
                end

                if start + duration > query_time then
                    t.count = 1
                    t.expires = start + duration
                    t.applied = start
                    t.duration = duration
                    t.caster = "anybody"
                    t.v1 = spell
                    return
                end
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.duration = 10
            t.caster = "nobody"
            t.v1 = 0
        end,
    },

    dispellable_curse = {
        generate = function(t)
            local i = 1
            local name, _, count, debuffType, duration, expirationTime = UnitDebuff("player", i, "RAID")

            while name do
                if debuffType == "Curse" then
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
        end,
    },

    dispellable_poison = {
        generate = function(t)
            local i = 1
            local name, _, count, debuffType, duration, expirationTime = UnitDebuff("player", i, "RAID")

            while name do
                if debuffType == "Poison" then
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
        end,
    },

    dispellable_disease = {
        generate = function(t)
            local i = 1
            local name, _, count, debuffType, duration, expirationTime = UnitDebuff("player", i, "RAID")

            while name do
                if debuffType == "Disease" then
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
        end,
    },

    reversible_magic = {
        generate = function(t)
            local i = 1
            local name, _, count, debuffType, duration, expirationTime = UnitDebuff("player", i, "RAID")

            while name do
                if debuffType == "Magic" then
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
        end,
    },
}

-- The player's magic debuffs only, as reversible_magic: a target's buffs are secret in combat (spec §4.1, rule 4).
auras.dispellable_magic = { generate = auras.reversible_magic.generate }

for key, def in pairs(auras) do
    shared:RegisterAura(key, def)
end
