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
            IsStealthed = api.IsStealthed,
            UnitRangedDamage = api.UnitRangedDamage,
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
        saved.C_Item = rawget(_G, "C_Item") or false
        _G.C_Item = api.C_Item
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
        load.schema(ns, h)
        I.Prof.on = true -- the in-game CPU profiling path allocates nothing either
        local sink = I.Events.CreateFrame("Frame") -- a combat-log subscriber: the rows ride along
        local GetInfo = Facade.CombatLogGetCurrentEventInfo
        sink:SetScript("OnEvent", function()
            GetInfo()
        end)
        sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        -- a weapon-enchant pseudo-aura and a stealth aura (Sources/Enchants.lua, Sources/Forms.lua)
        h.Class.auras.enchant_x = { key = "enchant_x", id = -7, weaponEnchant = 0 }
        h.Class.auras.enchant_y = { key = "enchant_y", id = -8, enchants = { 7, 8 } } -- an `enchants` aura
        h.Class.auras.stealth_x = { key = "stealth_x", id = 1999, isStealthed = true }
        local ENCHANTED = {
            { hasEnchant = true, enchantType = 2, timeLeft = 900000, charges = 0, enchantID = 2628 },
            { hasEnchant = true, enchantType = 3, timeLeft = 1800000, charges = 20, enchantID = 7 },
        }
        local STEALTHS = { true, false, fake.SECRET }
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
        ns.BuildTracked()
        local tracked = {} -- both enchant auras crossed Build(def) (Engine/Schema/Tracked.lua) and are read
        for j, slot in pairs(I.enchantAura) do
            tracked[I.def.auras[j].key] = slot
        end
        assert.are.same({ enchant_x = 0, enchant_y = true }, tracked)
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
                ctl.stealthed = STEALTHS[i % 3 + 1] -- plain both ways and secret
                ctl.Fire("UPDATE_STEALTH")
                ctl.enchants[0] = i % 8 == 4 and fake.SECRET or ENCHANTED
                ctl.Fire("WEAPON_ENCHANT_CHANGED") -- read in combat too
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
            VS.Count.WithAura(fs.SPENDER_C, t)
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
            Facade.IsStealthed()
            Facade.C_Item.GetWeaponEnchantInfo(0)
            Facade.C_Item.GetWeaponEnchantInfo(1)
            Facade.UnitCreatureFamily("pet")
            Facade.UnitRangedDamage("player")
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

    -- The sweep (cdm-default §3.2, plan Task 3b): the item fields are written directly (ctl.ViewerAura logs its writes,
    -- the fake's allocation, not the leaf's).
    local function hold(item, on, unit)
        item.auraInstanceID, item.auraDataUnit = on and fake.SECRET or nil, on and (unit or "player") or nil
    end

    it("the sweep over a 40-slot layout with changes allocates nothing (cdm-default §3.2)", function()
        local api, ctl = fake.new()
        ctl.now = 1
        ctl.viewer.sets[2] = { 501, 502, 503, 504 }
        ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
        ctl.viewer.infos[502] = { spellID = fs.SPENDER_C }
        ctl.viewer.infos[503] = { spellID = 9999 } -- unmapped
        ctl.viewer.infos[504] = { spellID = 9998, linkedSpellIDs = { fs.SPENDER_A, 9997 } } -- ambiguous (counted)
        local items = {}
        for n = 1, 40 do
            local v = fake.VIEWERS[n % 4 + 1]
            if n % 10 == 0 then
                ctl.ViewerChild(v)
            else
                items[#items + 1] = ctl.ViewerItem(v, n, 500 + n % 4 + 1)
            end
        end
        local ns = load.module()
        local I = ns.VirtualStateInternal
        local def = fs.def(fs.new(9))
        def.providers = { presence = "router", viewer = true }
        I.Build(def, 1)
        ns.VirtualState.Start(api)
        local R = I.presence
        local n = 0
        R.onEdge = function()
            n = n + 1
        end
        local U = I.auras -- records up, so a silence that passes the seen rule is live (Task 3c)
        for u = 1, 2 do
            for j = 1, 2 do
                U.exp0[u][j], U.applied[u][j] = 1e6, 1
            end
        end
        local t = 1
        local ok, bytes = pcall(alloc.bytes, function(i)
            t = t + 0.1
            ctl.now = t
            for k = 1, #items, 3 do -- a third of the slots change at every sweep, some for the target
                hold(items[k], i % 2 == 1, k % 6 == 1 and "target" or "player")
            end
            ctl.viewer.shown.BuffBarCooldownViewer = i % 5 ~= 0 -- and a viewer hides now and then
            if i % 7 == 0 then -- a re-point to the other aura and back (a seen-rule reset)
                items[2].cooldownID = items[2].cooldownID == 501 and 502 or 501
            end
            if i % 11 == 0 then -- a record closes and opens again (the gate)
                U.exp0[1][2] = U.exp0[1][2] > 0 and 0 or 1e6
            end
            if i % 13 == 0 then -- a target switch: settle and reset
                ctl.Fire("PLAYER_TARGET_CHANGED")
            end
            R.Sweep(t)
            R.Presence(1, 1)
            R.Presence(2, 2)
        end, 100)
        assert.is_true(ok, tostring(bytes))
        assert.are.equal(0, bytes)
        assert.is_true(n > 100, "the changes are edges")
    end)

    it("allocates nothing over 100 sweeps and edges through the leaf and the router (providers spec §2.5)", function()
        local api, ctl = fake.new()
        ctl.now = 1
        ctl.viewer.sets[2] = { 501 }
        ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
        local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 501)
        local ns = load.module()
        local I = ns.VirtualStateInternal
        local def = fs.def(fs.new(9))
        I.Build(def, 1)
        local R = I.PRESENCE.router
        R.Activate(api, 1, def, { viewer = true })
        local n = 0
        R.onEdge = function()
            n = n + 1
        end
        I.auras.exp0[1][1], I.auras.applied[1][1] = 1e6, 1 -- the record up: the item's silence is live (seen rule)
        local t = 1
        local ok, bytes = pcall(alloc.bytes, function(i)
            t = t + 0.1
            hold(item, i % 2 == 1)
            R.Sweep(t)
            R.Presence(1, 1)
            R.Presence(2, 2)
        end, 100)
        assert.is_true(ok, tostring(bytes))
        assert.are.equal(0, bytes)
        assert.is_true(n > 100, "every call an edge")
    end)

    it(
        "the sweep, poll 15 and the fold allocate nothing with proof, dark starts, verdicts, strikes and suspensions",
        function()
            local api, ctl = fake.new()
            ctl.now = 1
            ctl.viewer.sets[2] = { 502 }
            ctl.viewer.infos[502] = { spellID = fs.SPENDER_C }
            local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            local ns = load.module()
            local VS, I = ns.VirtualState, ns.VirtualStateInternal
            local S, Q = I.Sources, I.PRESENCE.viewer
            local def = fs.def(fs.new(9))
            def.providers = { presence = "router", viewer = true }
            I.Build(def, 1)
            VS.Start(api)
            ctl.now = 10
            ctl.Fire("PLAYER_TARGET_CHANGED")
            I.Fold(10, false)
            ctl.Fire("PLAYER_REGEN_DISABLED")
            ctl.auras.target.HARMFUL[1] = fake.SECRET -- the target walk secret: only the reduced facts speak
            ctl.Fire("UNIT_AURA", "target")
            local REND, k = 2, I.AURA_UNIT + 2
            local t, maxDark, cycle, maxSince = 10, 0, 0, 0
            -- a 12-poll cycle at 0.25 s: our cast (dark: dodged), the verdict at +1.0 (its close names the application,
            -- counted at the fold), and every second cycle a late light at +1.5 (a strike) and dark again at +2.0 (rule 1
            -- closes the CDM open). The cycle without a light leaves a silent verdict, so the next one's verdict suspends
            -- the proof and its light re-proves it (review M3); the strikes reset each cycle so the item is never retired
            local ok, bytes = pcall(alloc.bytes, function(i)
                t = t + 0.25
                ctl.now = t
                local p = i % 12
                if p == 0 then
                    cycle = cycle + 1
                    Q.strikes[502] = 0
                    I.AuraModel(2, REND, t, t + 15, 1, t, ns.VirtualState.Obs.CastSuccess, true)
                    I.AuraOurs(2, REND, 0)
                elseif p == 6 and cycle % 2 == 0 then
                    hold(item, true, "target")
                elseif p == 8 then
                    hold(item, false)
                end
                S.RunPolls(t)
                I.Fold(t, false)
                I.Settle(t)
                local _, _, _, _, _, _, nd, since = Q.Counts(REND, 2)
                maxDark = nd > maxDark and nd or maxDark
                maxSince = since > maxSince and since or maxSince
            end, 240)
            assert.is_true(ok, tostring(bytes))
            assert.are.equal(0, bytes)
            assert.is_true(I.auraVerdict.n[k] > 20, "verdicts " .. I.auraVerdict.n[k])
            assert.is_true(I.auraVerdict.strikes[k] > 10, "strikes " .. I.auraVerdict.strikes[k])
            assert.is_true(Q.suspended > 10, "suspensions " .. Q.suspended)
            assert.are.equal(1, maxDark)
            assert.is_true(maxSince > 10, "the dark's start moved")
        end
    )

    it(
        "allocates nothing over 1000 meter events, 100 swings and their ticks with the Meter (providers spec §2.2)",
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
            local d = fs.def(fs.new(9))
            d.providers = { outcomes = "meter" }
            I.Build(d, 1)
            VS.Start(api)
            ctl.guid.target = "Creature-2"
            ctl.Fire("PLAYER_TARGET_CHANGED")
            ctl.combat = true
            ctl.Fire("PLAYER_REGEN_DISABLED")
            local asked = 0
            local P = I.outcomes
            local own = P.RowOwner
            P.RowOwner = function(...) -- counts the audit's asks (one shared function: no closure per call)
                asked = asked + 1
                return own(...)
            end
            -- per step: 10 meter events (a damage group, its duplicate set, taken groups), one swing with its rows
            local TY, SID = { 0, 1, 10, 0, 1, 10, 7, 7, 2, 7 }, { 200, 200, 200, 0, 0, 0, 200, 0, 200, 200 }
            local function step(i)
                ctl.now = ctl.now + 0.26
                local t = ctl.now
                ctl.Fire("PLAYER_SWING", 2.6, 0)
                for k = 1, 10 do
                    ctl.Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", TY[k], SID[k])
                end
                ctl.now = t + 0.008
                ctl.Tick()
                ctl.now = t + 0.02
                ctl.Tick()
                ctl.Fire("UNIT_COMBAT", "target", i % 7 == 3 and "DODGE" or "WOUND", "", i % 7 == 3 and 0 or 10, 1)
                ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 12, 1)
                ctl.now = t + 0.04
                ctl.Tick()
            end
            local ok, bytes = pcall(alloc.bytes, step, 100)
            for k, v in pairs(saved) do
                _G[k] = v or nil
            end
            P.RowOwner = own
            assert.is_true(ok, tostring(bytes))
            assert.are.equal(0, bytes)
            assert.is_true(asked > 100, "the audit asked RowOwner")
            assert.is_true(I.Log.fight.swingsTick + I.Log.fight.swingsAvoid > 100, "the swings were told")
        end
    )
end)
