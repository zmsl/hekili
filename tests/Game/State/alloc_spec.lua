-- tests/Game/State/alloc_spec.lua (spec §2, §11): 10,000 mixed events (PLAYER_SWING, UNIT_POWER_FREQUENT,
-- usability flipping on a health-gated spender, own casts, UNIT_AURA after a form swap, the target's UNIT_COMBAT (wounds
-- and provisional avoids), hits on the player paying rage through a `taken`, combat ending and starting under a stepped
-- rage decay) with a drain every tick against the fake spec, every accessor and every facade policy and passthrough
-- called, every combat-log row delivered to a subscriber: VirtualState allocates nothing.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

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
        h.Class.abilities.spender_c.healthGate = 0.2 -- a health-gated spender (Families/TargetHealth.lua)
        ctl.known[fs.SPENDER_C] = true -- known: its NOT answers can bound the target's health
        h.Class.resources.rage.state.meta = { -- a stepped decay (Families/Resources.lua): 2 at each 1 s beat
            decay = function()
                return 2
            end,
            decayInterval = function()
                return 1
            end,
        }
        h.Class.resources.rage.state.regenModel.mainhand.taken = function(kind, amount) -- rage from hits on us
            return buff.spender_a.up and amount / 10 or 1, 0.5 -- luacheck: ignore 113 (the `now` context's names)
        end
        VS.Start(api)
        VS.SpecChanged()
        local decay = h.Class.resources.rage.state.regenModel.__decay -- the sim's (Adapter.lua), called as a forecast
        local taken = h.Class.resources.rage.state.regenModel.__taken
        state.time, state.query_time = 0, 1
        ctl.guid.target = "Creature-2" -- a target never held before: its first flip learns M, then WOUNDs move it
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.auras.player.HELPFUL[1] = { spellId = fs.SPENDER_A, expirationTime = 1e9, applications = 0 }
        ctl.forms = { fs.SPENDER_A } -- a tracked form aura (Sources/Forms.lua)
        local USABLE, NOT_USABLE = { true, false }, { false, false }
        ctl.usable[fs.SPENDER_C] = USABLE
        ctl.cooldown[fs.SPENDER_C] = { isActive = false, isOnGCD = true }
        ctl.Fire("PLAYER_REGEN_DISABLED")
        local POWER = "RAGE"
        local function step(i)
            ctl.now = ctl.now + 0.1
            local k = i % 6
            if k == 0 then
                ctl.Fire("PLAYER_SWING", 2.6, 0)
            elseif k == 1 then
                ctl.Fire("UNIT_POWER_FREQUENT", "player", POWER)
            elseif k == 2 then
                ctl.usable[fs.SPENDER_C] = i % 4 == 2 and NOT_USABLE or USABLE -- every other usability event flips
                ctl.Fire("SPELL_UPDATE_USABLE")
            elseif k == 3 then
                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast", fs.SPENDER_C)
            elseif k == 4 then
                ctl.form = i % 12 == 4 and 1 or 0 -- spender_a's aura as a form: every other walk follows a form swap
                ctl.Fire("UPDATE_SHAPESHIFT_FORM")
                ctl.Fire("UNIT_AURA", "player")
            else
                local dodge = i % 12 == 5 -- an avoid at the swing's lag: provisional, SWING_MISSED at the window's close
                ctl.Fire("UNIT_COMBAT", "target", dodge and "DODGE" or "WOUND", "", dodge and 0 or 10, 1)
                ctl.Fire("UNIT_COMBAT", "player", "WOUND", i % 12 == 5 and "BLOCK" or "", 12, 1)
            end
            if i % 100 == 50 then
                ctl.Fire("PLAYER_REGEN_ENABLED") -- out of combat: the rage decays on its beats
            elseif i % 100 == 0 then
                ctl.Fire("PLAYER_REGEN_DISABLED")
            end
            ctl.Tick()
            VS.Drain(ctl.now)
            local t = ctl.now
            VS.Power(fs.RAGE, t)
            VS.DecayAnchor(fs.RAGE)
            VS.TakenRate(fs.RAGE, t)
            decay.last()
            decay.stop()
            decay.value()
            taken.last()
            taken.stop()
            taken.value()
            VS.Regen(fs.RAGE, t)
            VS.Cooldown(fs.SPENDER_C, t)
            VS.Charges(fs.SPENDER_C, t)
            VS.Gcd(t)
            VS.GcdInfo(t)
            VS.Aura("player", fs.SPENDER_A, t)
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
            VS.Health("target", t)
            VS.TTD("target", t)
            VS.Totem(1, t)
            VS.TotemFacts(1)
            VS.TargetCast(t)
            VS.TargetCastFacts()
            VS.Talent(1011)
            VS.TalentGen()
            VS.Stat("UnitStat", 1)
            VS.InCombat()
            VS.Moving()
            VS.CooldownLength(fs.SPENDER_C)
            VS.Count.Enemies(t)
            VS.Count.WithAura(fs.SPENDER_C, t)
            VS.Count.InRange(fs.SPENDER_C, t)
            Facade.UnitPower("player", fs.RAGE)
            Facade.GetPowerRegenForPowerType(fs.RAGE)
            Facade.GetManaRegen()
            Facade.UnitHealth("player")
            Facade.UnitHealth("nameplate1")
            Facade.UnitHealth("target")
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
            Facade.C_UnitAuras.GetPlayerAuraBySpellID(fs.SPENDER_A)
            Facade.C_UnitAuras.GetAuraDataByAuraInstanceID("player", 1)
            Facade.C_Spell.GetSpellCooldown(fs.SPENDER_C)
            Facade.C_Spell.GetSpellCooldown(29515)
            Facade.C_Spell.GetSpellCharges(fs.SPENDER_C)
            Facade.UnitCastingInfo("target")
            Facade.UnitChannelInfo("target")
            Facade.IsUsableSpell(fs.SPENDER_C)
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

    it(
        "allocates nothing over 1000 casts mixing GCD kinds, the GCD's rising edge before and after each success",
        function()
            local api, ctl = fake.new()
            local saved = {}
            for k, v in pairs({
                CreateFrame = api.CreateFrame,
                issecretvalue = api.issecretvalue,
                GetTime = api.GetTime,
            }) do
                saved[k] = rawget(_G, k) or false
                _G[k] = v
            end
            ctl.now = 1
            local ns = load.module()
            local VS, I = ns.VirtualState, ns.VirtualStateInternal
            I.Build(fs.def(fs.new(9, true)), 1)
            VS.Start(api)
            local IDS = { fs.SPENDER_C, fs.SPENDER_T, fs.SPENDER_U } -- spell, totem, a declared gcdTime
            local UP, DOWN = { isActive = true, isOnGCD = false }, { isActive = false, isOnGCD = false }
            local function tick()
                ctl.Tick(ctl.now)
                fs.fold(ns, ctl.now)
                VS.GcdInfo(ctl.now)
            end
            local function step(i)
                ctl.now = ctl.now + 0.5
                local id = IDS[i % 3 + 1]
                if i % 2 == 0 then
                    ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast", id)
                end
                ctl.cooldown[I.GCD_SPELL] = UP
                ctl.Fire("SPELL_UPDATE_COOLDOWN")
                if i % 2 == 1 then
                    ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast", id)
                end
                tick()
                ctl.now = ctl.now + 1.0
                ctl.cooldown[I.GCD_SPELL] = DOWN
                ctl.Fire("SPELL_UPDATE_COOLDOWN")
                tick()
            end
            local ok, bytes = pcall(alloc.bytes, step, 1000)
            for k, v in pairs(saved) do
                _G[k] = v or nil
            end
            assert.is_true(ok, tostring(bytes))
            assert.are.equal(0, bytes)
            assert.is_true(I.gcdLearned[1] > 0 and I.gcdLearned[2] > 0, "both kinds learned")
        end
    )
end)
