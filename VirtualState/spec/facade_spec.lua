-- VirtualState/spec/facade_spec.lua: ns.Facade (spec §7): the inventory equals tools/api_inventory.txt, every kept
-- name answers in its real shape, the stubs never call the game, and the GCD numbers are bit-identical.
-- The inventory and shape cases move here from Libs/VirtualGameAPI-1.0/spec/VirtualGameAPI_spec.lua.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

local INVENTORY = "tools/api_inventory.txt"

local function readInventory()
    local names = {}
    for line in io.lines(INVENTORY) do
        line = line:gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            names[#names + 1] = line
        end
    end
    return names
end

-- The real functions Facade.lua resolves at load, from the fake client; `calls` records any call of a kept name.
local RESOLVED = {
    "GetTime",
    "issecretvalue",
    "UnitPowerType",
    "UnitIsDead",
    "C_Spell.GetSpellCooldown",
    "C_Spell.IsSpellUsable",
    "C_Spell.GetSpellInfo",
    "UnitCastingInfo",
    "UnitChannelInfo",
}

describe("ns.Facade", function()
    local names, ns, Facade, VS, I, api, ctl, calls, saved, powerType

    local function entry(name)
        local nsName, key = name:match("^([%w_]+)%.([%w_]+)$")
        if nsName then
            return Facade[nsName] and Facade[nsName][key]
        end
        return Facade[name]
    end

    setup(function()
        names = readInventory()
    end)

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        powerType = fs.RAGE
        api.UnitPowerType = function()
            return powerType
        end
        api.C_Spell.GetSpellInfo = function(id)
            return { name = "Spell " .. id, iconID = 1 }
        end
        calls = {}
        saved = {}
        -- every kept name in _G records a call; the resolved reals answer from the fake client
        for _, n in ipairs(names) do
            local nsName, key = n:match("^([%w_]+)%.([%w_]+)$")
            local f = function()
                calls[#calls + 1] = n
            end
            if nsName then
                saved[nsName] = saved[nsName] or rawget(_G, nsName) or false
                _G[nsName] = _G[nsName] or {}
                _G[nsName][key] = f
            else
                saved[n] = rawget(_G, n) or false
                _G[n] = f
            end
        end
        for _, n in ipairs(RESOLVED) do
            local nsName, key = n:match("^([%w_]+)%.([%w_]+)$")
            if nsName then
                _G[nsName][key] = api[nsName][key]
            else
                saved[n] = saved[n] or rawget(_G, n) or false
                _G[n] = api[n]
            end
        end
        ns = load.module()
        Facade, VS, I = ns.Facade, ns.VirtualState, ns.VirtualStateInternal
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("keeps exactly the inventory's names, each with a status, a reason and a function", function()
        assert.are.same(names, Facade.Inventory())
        for _, n in ipairs(names) do
            local s = Facade.Status(n)
            assert.is_true(s == "virtual" or s == "stub", n .. " status is " .. tostring(s))
            assert.is_function(entry(n), n)
            assert.is_string(Facade.Why(n), n)
        end
        assert.are.equal(51, #names)
        assert.are.equal(17, #Facade.Stubs())
        assert.is_nil(Facade.Status("UnitExists"))
    end)

    it("never calls the game from a stub (absent names never reach _G)", function()
        for _, n in ipairs(Facade.Stubs()) do
            assert.has_no.errors(function()
                entry(n)("target", 1)
            end, n)
        end
        assert.are.same({}, calls)
        assert.are.same({ false, true }, { Facade.UnitInRange("party1") })
        assert.is_nil(Facade.CombatLogGetCurrentEventInfo())
        assert.is_nil(Facade.C_Spell.GetSpellLossOfControlCooldown(1))
    end)

    it("answers resources from the belief: UnitPower is floor(lo); swing-paid regen is 0 in combat", function()
        I.Sources.Direct(VS.Obs.Usable, 5, 3, 1, 0) -- rend usable: rage >= 10
        I.Fold(5, false)
        ctl.now = 5
        assert.are.equal(10, Facade.UnitPower("player", fs.RAGE))
        assert.are.equal(10, Facade.UnitPower("player"))
        assert.are.equal(0, Facade.UnitPower("target", fs.RAGE))
        local power, asked = VS.Power, nil
        VS.Power = function(pt, t)
            asked = pt
            return power(pt, t)
        end
        powerType = fake.SECRET -- a secret UnitPowerType reads as power type 0, never flows on
        Facade.UnitPower("player")
        VS.Power = power
        assert.are.equal(0, asked)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.are.same({ 0, 0 }, { Facade.GetPowerRegenForPowerType(fs.RAGE) })
        assert.are.equal(2, select("#", Facade.GetManaRegen()))
    end)

    it("answers health, speed, haste and stats in the real shapes", function()
        assert.are.equal(100, Facade.UnitHealth("target"))
        assert.are.equal(100, Facade.UnitHealthMax("target"))
        ctl.dead.nameplate4 = true
        assert.are.equal(0, Facade.UnitHealth("nameplate4"))
        assert.are.equal(100, Facade.UnitHealth("nameplate5"))
        assert.are.same({ 0, 7, 7, 4.72 }, { Facade.GetUnitSpeed("player") })
        assert.are.same({ 0, 0, 0, 0 }, { Facade.GetUnitSpeed("target") })
        assert.are.same({ 2, nil }, { Facade.UnitAttackSpeed("target") })
        assert.are.equal(7, select("#", Facade.UnitDamage("player")))
        assert.are.equal(0, Facade.GetMeleeHaste())
        assert.are.same({ false, "", 0, 0, 0 }, { Facade.GetTotemInfo(1) })
    end)

    it("answers auras through shared AuraData tables in AuraUtil's order", function()
        I.AuraModel(1, 1, 5, 125, 1, 5, VS.Obs.CastSuccess, false)
        ctl.now = 6
        local a = Facade.C_UnitAuras.GetBuffDataByIndex("player", 1)
        assert.are.same({ fs.SHOUT, 125, 120, 1, "player" }, {
            a.spellId,
            a.expirationTime,
            a.duration,
            a.applications,
            a.sourceUnit,
        })
        assert.are.equal(a, Facade.C_UnitAuras.GetBuffDataByIndex("player", 1)) -- shared, not allocated per call
        assert.is_nil(Facade.C_UnitAuras.GetBuffDataByIndex("player", 2))
        assert.are.equal(fs.SHOUT, Facade.C_UnitAuras.GetPlayerAuraBySpellID(fs.SHOUT).spellId)
        local seen = 0
        Facade.AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
            seen = seen + aura.spellId
        end, true)
        assert.are.equal(fs.SHOUT, seen)
        local found = select(10, Facade.AuraUtil.FindAura(function(_, _, _, ...)
            return select(10, ...) == fs.SHOUT
        end, "player", "HELPFUL"))
        assert.are.equal(fs.SHOUT, found)
    end)

    it("returns the same two GCD numbers for the GCD spell and a GCD-locked spell, surviving the round trip", function()
        for _ = 1, 500 do
            local t = math.random() * 1e6
            I.Sources.Direct(VS.Obs.Cooldown, t, 0, 1, 1)
            I.Fold(t, false)
            ctl.now = t + 0.1
            local g = Facade.C_Spell.GetSpellCooldown(29515)
            local gs, gd = g.startTime, g.duration
            assert.are.equal(gs, (gs + gd) - gd)
            ctl.cooldown[fs.REND] = { isActive = true, isOnGCD = true }
            local c = Facade.C_Spell.GetSpellCooldown(fs.REND)
            assert.are.same({ gs, gd }, { c.startTime, c.duration })
            I.Sources.Direct(VS.Obs.Cooldown, t + 1.5, 0, 0, 1)
            I.Fold(t + 1.5, false)
        end
    end)

    it("answers a cooldown from the belief and the plain flag", function()
        I.CooldownModel(3, 40, 30, 10, VS.Obs.CastSuccess)
        ctl.now = 20
        ctl.cooldown[fs.REND] = { isActive = true, isOnGCD = false }
        local c = Facade.C_Spell.GetSpellCooldown(fs.REND)
        assert.are.same({ 10, 30, true }, { c.startTime, c.duration, c.isActive })
        assert.is_nil(Facade.C_Spell.GetSpellCharges(fs.REND))
    end)

    it("passes the player's own casts through and answers the target's from TargetCast", function()
        ctl.casting = { 1000, 2500 }
        assert.are.equal(1000, select(4, Facade.UnitCastingInfo("player")))
        assert.is_nil(Facade.UnitCastingInfo("target"))
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_START", "target", fake.SECRET, fake.SECRET, 77)
        ctl.Tick(10)
        I.Fold(10, false)
        local name, _, _, s, e, _, bar, notKick = Facade.UnitCastingInfo("target")
        assert.are.same({ "Casting", 10000, (10 + I.TARGET_CAST_DEFAULT) * 1000, 77, false }, { name, s, e, bar, notKick })
        assert.is_nil(Facade.UnitChannelInfo("target"))
    end)

    it("answers spells, power types and units nothing tracks in the real shapes, without an error", function()
        local c = Facade.C_Spell.GetSpellCooldown(999999)
        assert.are.same({ 0, 0, false }, { c.startTime, c.duration, c.isActive })
        assert.is_nil(Facade.C_Spell.GetSpellCharges(999999))
        assert.are.equal(0, Facade.UnitPower("player", 99))
        assert.are.same({ 0, 0 }, { Facade.GetPowerRegenForPowerType(99) })
        assert.is_nil(Facade.C_UnitAuras.GetPlayerAuraBySpellID(999999))
        assert.is_nil(Facade.C_UnitAuras.GetBuffDataByIndex("focus", 1))
        assert.are.equal(0, Facade.UnitSpellHaste("target"))
    end)

    it("aliases IsUsableSpell to C_Spell.IsSpellUsable", function()
        ctl.usable[5] = { true, false }
        assert.is_true(Facade.IsUsableSpell(5))
    end)
end)
