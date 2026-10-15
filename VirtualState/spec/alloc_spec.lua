-- VirtualState/spec/alloc_spec.lua (spec §2, §11): 10,000 mixed events (PLAYER_SWING, UNIT_POWER_FREQUENT,
-- usability, own casts, UNIT_AURA) with a drain every tick against the fake spec, every accessor and every facade
-- policy and passthrough called, every combat-log row delivered to a subscriber: VirtualState allocates nothing.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")
local alloc = require("VirtualState.spec.helpers.alloc")

describe("zero allocation", function()
    it("allocates nothing across events, drains, accessors and facade policies", function()
        local api, ctl = fake.new()
        ctl.now = 1
        local saved = {}
        local globals = {
            GetTime = api.GetTime,
            UnitGUID = api.UnitGUID,
            CreateFrame = api.CreateFrame,
            issecretvalue = api.issecretvalue,
            UnitIsDead = api.UnitIsDead,
            UnitCastingInfo = api.UnitCastingInfo,
            UnitChannelInfo = api.UnitChannelInfo,
            UnitPowerType = function()
                return fs.RAGE
            end,
            debugprofilestop = function()
                return 0
            end,
        }
        for k, v in pairs(globals) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        saved.C_Spell = rawget(_G, "C_Spell") or false
        _G.C_Spell = api.C_Spell
        local ns = load.module()
        local VS, I, Facade = ns.VirtualState, ns.VirtualStateInternal, ns.Facade
        local h = fs.new(9)
        local state = h.State
        function state:RemoveSpellEvent()
            return false
        end
        function state:AddToHistory() end
        function state:QueueEvent() end
        function h:ForceUpdate() end -- the fake records calls; Hekili's own only sets fields
        fs.clock = api.GetTime
        ns.spendResources = fs.spend
        ns.ResourceRegenerates = function()
            return false
        end
        load.adapter(ns, h)
        local sink = I.Events.CreateFrame("Frame") -- a combat-log subscriber: the rows ride along
        local GetInfo = Facade.CombatLogGetCurrentEventInfo
        sink:SetScript("OnEvent", function()
            GetInfo()
        end)
        sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        VS.Start(api)
        VS.SpecChanged()
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SHOUT, expirationTime = 1e9, applications = 0 }
        ctl.usable[fs.REND] = { true, false }
        ctl.cooldown[fs.REND] = { isActive = false, isOnGCD = true }
        ctl.Fire("PLAYER_REGEN_DISABLED")
        local POWER = "RAGE"
        local function step(i)
            ctl.now = ctl.now + 0.1
            local k = i % 5
            if k == 0 then
                ctl.Fire("PLAYER_SWING", 2.6, 0)
            elseif k == 1 then
                ctl.Fire("UNIT_POWER_FREQUENT", "player", POWER)
            elseif k == 2 then
                ctl.Fire("SPELL_UPDATE_USABLE")
            elseif k == 3 then
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast", fs.REND)
            else
                ctl.Fire("UNIT_AURA", "player")
            end
            ctl.Tick()
            VS.Drain(ctl.now)
            local t = ctl.now
            VS.Power(fs.RAGE, t)
            VS.Regen(fs.RAGE, t)
            VS.Cooldown(fs.REND, t)
            VS.Charges(fs.REND, t)
            VS.Gcd(t)
            VS.GcdInfo(t)
            VS.Aura("player", fs.SHOUT, t)
            VS.AuraAt("target", "HARMFUL", 1, t)
            VS.AuraByInstance("player", 1, t)
            VS.AuraGen("player")
            VS.Swing(1, t)
            VS.SwingSpeed(1, t)
            VS.LastSwing(1)
            VS.Haste(t)
            VS.SpellHaste(t)
            VS.Health("player", t)
            VS.HealthMax("player")
            VS.TTD("target", t)
            VS.Totem(1, t)
            VS.TotemFacts(1)
            VS.TargetCast(t)
            VS.TargetCastFacts()
            VS.Talent(12286)
            VS.TalentGen()
            VS.Stat("UnitStat", 1)
            VS.InCombat()
            VS.Moving()
            VS.CooldownLength(fs.REND)
            VS.Count.Enemies(t)
            VS.Count.WithAura(fs.REND, t)
            VS.Count.InRange(fs.REND, t)
            Facade.UnitPower("player", fs.RAGE)
            Facade.GetPowerRegenForPowerType(fs.RAGE)
            Facade.GetManaRegen()
            Facade.UnitHealth("player")
            Facade.UnitHealth("nameplate1")
            Facade.UnitHealthMax("target")
            Facade.UnitStat("player", 1)
            Facade.GetCombatRating(10)
            Facade.UnitDamage("player")
            Facade.GetHaste()
            Facade.GetMeleeHaste()
            Facade.UnitSpellHaste("player")
            Facade.UnitAttackSpeed("player")
            Facade.GetUnitSpeed("player")
            Facade.GetTotemInfo(1)
            Facade.C_UnitAuras.GetBuffDataByIndex("player", 1)
            Facade.C_UnitAuras.GetDebuffDataByIndex("target", 1)
            Facade.C_UnitAuras.GetPlayerAuraBySpellID(fs.SHOUT)
            Facade.C_UnitAuras.GetAuraDataByAuraInstanceID("player", 1)
            Facade.C_Spell.GetSpellCooldown(fs.REND)
            Facade.C_Spell.GetSpellCooldown(29515)
            Facade.C_Spell.GetSpellCooldown(61304) -- retail's GCD spell, asked as Forever's
            Facade.C_Spell.GetSpellCharges(fs.REND)
            Facade.UnitCastingInfo("target")
            Facade.UnitChannelInfo("target")
            Facade.IsUsableSpell(fs.REND)
            Facade.GetTime() -- passthroughs
            Facade.UnitGUID("target")
            Facade.GetInstanceInfo() -- absent here: virtual, answers nothing
        end
        local ok, bytes = pcall(alloc.bytes, step, 10000)
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        fs.clock = nil
        assert.is_true(ok, tostring(bytes))
        assert.are.equal(0, bytes)
    end)
end)
