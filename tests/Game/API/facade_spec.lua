-- tests/Game/API/facade_spec.lua: ns.Facade (spec §7; event-facade spec §1.1): the inventory and each name's class
-- equal tools/api_inventory.txt, every name answers in its real shape, a virtual row never calls the game, a
-- passthrough is transparent, a hybrid answers the raw value unless it is secret, and the GCD numbers are bit-identical.
-- The inventory and shape cases move here from Libs/VirtualGameAPI-1.0/spec/VirtualGameAPI_spec.lua.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

local INVENTORY = "tools/api_inventory.txt"

-- The inventory's names in order and their classes ("Name<TAB>class" lines).
local function readInventory()
    local names, classes = {}, {}
    for line in io.lines(INVENTORY) do
        local name, class = line:match("^(%S+)\t(%a+)%s*$")
        if name then
            names[#names + 1] = name
            classes[name] = class
        end
    end
    return names, classes
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
    "CreateFrame",
}

describe("ns.Facade", function()
    local names, classes, ns, Facade, VS, I, api, ctl, calls, saved, powerType, answers

    local function entry(name)
        local nsName, key = name:match("^([%w_]+)%.([%w_]+)$")
        local root = Facade.Status(name) == "display" and Facade.Display or Facade
        if nsName then
            return root[nsName] and root[nsName][key]
        end
        return root[name]
    end

    setup(function()
        names, classes = readInventory()
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
        calls, answers = {}, {}
        saved = {}
        -- every name in _G records a call and answers as the client does in combat (secret) unless `answers` names
        -- a plain answer; the resolved reals answer from the fake client
        for _, n in ipairs(names) do
            local nsName, key = n:match("^([%w_]+)%.([%w_]+)$")
            local f = function(...)
                calls[#calls + 1] = n
                local a = answers[n]
                if a then
                    return a(...)
                end
                return fake.SECRET
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

    it("keeps exactly the inventory's names, each with its class, a reason and a function", function()
        assert.are.same(names, Facade.Inventory())
        local count = { passthrough = 0, hybrid = 0, virtual = 0, display = 0 }
        for _, n in ipairs(names) do
            local c = Facade.Status(n)
            assert.are.equal(classes[n], c, n)
            count[c] = count[c] + 1
            assert.is_function(entry(n), n)
            assert.is_string(Facade.Why(n), n)
        end
        assert.are.same({ passthrough = 125, hybrid = 44, virtual = 25, display = 1 }, count)
        assert.is_nil(Facade.Status("NotAGameFunction"))
    end)

    it("never calls the game for a virtual row's answer", function()
        for _, n in ipairs(names) do
            if classes[n] == "virtual" and n ~= "CreateFrame" then
                assert.has_no.errors(function()
                    entry(n)("target", 1)
                end, n)
            end
        end
        assert.are.same({}, calls)
        assert.are.same({ false, true }, { Facade.UnitInRange("party1") })
        assert.is_nil(Facade.CombatLogGetCurrentEventInfo())
        assert.is_nil(Facade.C_Spell.GetSpellLossOfControlCooldown(1))
    end)

    it("answers a display row raw from Facade.Display only, untraced (Modern spec §4, plan ruling 5)", function()
        assert.is_nil(Facade.C_Spell.GetSpellCooldownDuration)
        local n = #calls
        assert.is_true(rawequal(fake.SECRET, Facade.Display.C_Spell.GetSpellCooldownDuration(7, true)))
        assert.are.equal(n + 1, #calls)
        assert.are.equal("C_Spell.GetSpellCooldownDuration", calls[#calls])
        assert.is_nil(Facade.counts["C_Spell.GetSpellCooldownDuration"])
        assert.is_truthy(Facade.Why("C_Spell.GetSpellCooldownDuration"):find("widget", 1, true))
    end)

    it(
        "answers resources: UnitPower is est, lo (a continuous resource's fraction kept), hi; swing regen 0 in and out of combat",
        function()
            I.Sources.Direct(VS.Obs.Usable, 5, 3, 1, 0) -- spender_c usable: rage >= 10
            I.Fold(5, false)
            ctl.now = 5
            local hi = VS.Power(fs.RAGE, 5).hi -- the belief's ceiling (rage errs upward: 100 here)
            assert.are.same({ 10, 10, hi }, { Facade.UnitPower("player", fs.RAGE) }) -- est, lo, hi (border batch 2)
            assert.are.same({ 10, 10, hi }, { Facade.UnitPower("player") })
            assert.are.same({ 0 }, { Facade.UnitPower("target", fs.RAGE) })
            local power, asked = VS.Power, nil
            VS.Power = function(pt, t)
                asked = pt
                return power(pt, t)
            end
            powerType = fake.SECRET -- a secret UnitPowerType reads as power type 0, never flows on
            Facade.UnitPower("player")
            VS.Power = power
            assert.are.equal(0, asked)
            VS.Power = function()
                return { est = 98.6, lo = 31.8, hi = 99 }
            end
            -- slot 2 is lo: rage too (G4's est exception is gone), a swing's steps make it whole; slots 1 and 3 the band
            assert.are.same({ 98.6, 31, 99 }, { Facade.UnitPower("player", fs.RAGE) })
            -- the fraction stays, or a continuous resource's wait jumps by up to 1 / regen a tick
            assert.are.same({ 98.6, 31.8, 99 }, { Facade.UnitPower("player", 3) })
            -- a short answer's cap is a ceiling: the read sits a whole unit under it, any cost's (39.97's cap is 39.96)
            VS.Power = function()
                return { est = 39.99, lo = 39.99, capped = true }
            end
            assert.is_true((select(2, Facade.UnitPower("player", 3))) <= 39)
            VS.Power = function()
                return { est = 39.96, lo = 39.96, capped = true }
            end
            assert.is_true((select(2, Facade.UnitPower("player", 3))) <= 38.97)
            VS.Power = function()
                return { est = 0.49, lo = 0.49, capped = true }
            end
            assert.are.same({ 0.49, 0 }, { Facade.UnitPower("player", 3) }) -- the cap shapes lo alone (the stub has no hi)
            local regen = VS.Regen
            VS.Regen = function()
                return { est = 33 } -- a mana rate: a whole unit alone is under the 0.05 s of a shown-ready wait
            end
            VS.Power = function()
                return { est = 120.99, lo = 120.99, capped = true }
            end
            assert.is_true((121 - select(2, Facade.UnitPower("player", 3))) / 33 > 0.05)
            VS.Regen = regen
            VS.Power = function()
                return { est = 24.7, lo = 24.7, capped = true, capB = 24.39 } -- inside the ready wait: past it, no deeper
            end
            assert.are.equal(24.39, (select(2, Facade.UnitPower("player", 3))))
            VS.Power = function()
                return { est = 24.2, lo = 24.2, capped = true, capB = 24.39 } -- already under the band
            end
            assert.are.equal(24.2, (select(2, Facade.UnitPower("player", 3))))
            VS.Power = function()
                return { est = 39.99, lo = 39.99, capped = false } -- a measured fraction keeps it
            end
            assert.are.equal(39.99, (select(2, Facade.UnitPower("player", 3))))
            VS.Power = power
            -- (border batch 2) the client's pair, then the belief's: the window's end (nil for a type without one),
            -- the stepped decay's anchor, the rate of hits on the player
            assert.are.same({ 0, 0, nil, 0, 0 }, { Facade.GetPowerRegenForPowerType(fs.RAGE) }) -- out of combat too: no swings (G3)
            ctl.Fire("PLAYER_REGEN_DISABLED")
            assert.are.same({ 0, 0, nil, 0, 0 }, { Facade.GetPowerRegenForPowerType(fs.RAGE) })
            assert.are.equal(5, select("#", Facade.GetManaRegen()))
            local fsr, anchor, taken = VS.FsrUntil, VS.DecayAnchor, VS.TakenRate
            VS.FsrUntil = function(pt)
                return pt == 0 and 12.5 or nil
            end
            VS.DecayAnchor = function(pt)
                return pt == fs.RAGE and 7 or 0
            end
            VS.TakenRate = function(pt, t)
                return pt == fs.RAGE and t == 5 and 0.4 or 0 -- asked at now, never at a simulated time
            end
            assert.are.same({ 0, 0, nil, 7, 0.4 }, { Facade.GetPowerRegenForPowerType(fs.RAGE) })
            assert.are.same({ 12.5, 0, 0 }, { select(3, Facade.GetManaRegen()) })
            VS.FsrUntil, VS.DecayAnchor, VS.TakenRate = fsr, anchor, taken
            -- (border batch 2) UnitPowerMax: the client's while plain, the belief's when secret; then the pool's base
            -- power, nil until a percent-of-base cost read taught it
            assert.are.same({ 100 }, { Facade.UnitPowerMax("player", fs.RAGE) }) -- secret: the belief's declared maximum
            answers.UnitPowerMax = function()
                return 110
            end
            assert.are.same({ 110 }, { Facade.UnitPowerMax("player", fs.RAGE) })
            local base = VS.BasePower
            VS.BasePower = function(pt)
                return pt == fs.RAGE and 219 or nil
            end
            assert.are.same({ 110, 219 }, { Facade.UnitPowerMax("player", fs.RAGE) })
            assert.are.same({ 110 }, { Facade.UnitPowerMax("pet", fs.RAGE) }) -- another unit: no base
            VS.BasePower = base
            -- (border batch 2) UnitThreatSituation: the client's status while plain, nothing when secret; then the
            -- hostiles attacking someone else
            assert.are.same({ nil, 0 }, { Facade.UnitThreatSituation("player", "target") }) -- secret: no status
            answers.UnitThreatSituation = function()
                return 3
            end
            local loose = VS.LooseEnemies
            VS.LooseEnemies = function()
                return 2
            end
            assert.are.same({ 3, 2 }, { Facade.UnitThreatSituation("player", "target") })
            VS.LooseEnemies = loose
        end
    )

    it("answers health, speed, haste and stats in the real shapes", function()
        assert.are.equal(100, Facade.UnitHealth("target"))
        assert.are.equal(100, Facade.UnitHealthMax("target"))
        ctl.Fire("PLAYER_REGEN_DISABLED")
        answers.UnitHealthMax = function()
            return 624
        end
        assert.are.equal(624, Facade.UnitHealthMax("player")) -- plain in combat [probe 2026-10-16]: passed through
        answers.UnitHealthMax, I.healthMax = nil, 500 -- secret: the belief's last plain read
        assert.are.equal(500, Facade.UnitHealthMax("player"))
        local n = #calls
        Facade.UnitHealthMax("target")
        assert.are.equal(n, #calls) -- the target's is never read
        ctl.dead.nameplate4 = true
        assert.are.equal(0, Facade.UnitHealth("nameplate4"))
        assert.are.equal(100, Facade.UnitHealth("nameplate5"))
        assert.are.same({ 0, 7, 7, 4.72 }, { Facade.GetUnitSpeed("player") })
        assert.are.same({ 0, 0, 0, 0 }, { Facade.GetUnitSpeed("target") })
        assert.are.same({ 2, nil }, { Facade.UnitAttackSpeed("target") })
        -- (border batch 2) the player's main and off (slot 2 stays `off`), then the swing of each hand the game paid
        -- that the floor has not, the parry-haste pull and the swing it was taken from
        local pending, pull = VS.SwingPending, VS.SwingPull
        VS.SwingPending = function(hand)
            return hand == 1 and 7.5 or 0
        end
        VS.SwingPull = function(hand)
            return hand == 1 and 0.4 or 0, hand == 1 and 7.5 or 0
        end
        assert.are.same({ 7.5, 0, 0.4, 7.5 }, { select(3, Facade.UnitAttackSpeed("player")) })
        assert.are.equal(2, select("#", Facade.UnitAttackSpeed("target"))) -- another unit: no trailing values
        VS.SwingPending, VS.SwingPull = pending, pull
        assert.are.equal(7, select("#", Facade.UnitDamage("player")))
        -- (batch 1 review) GetShieldBlock has a row: stat("GetShieldBlock") in a pack no longer answers zeros
        assert.are.equal(0, Facade.GetShieldBlock()) -- secret: Stat()'s cache, nothing read yet
        answers.GetShieldBlock = function()
            return 31
        end
        assert.are.equal(31, Facade.GetShieldBlock())
        assert.are.equal(0, Facade.GetMeleeHaste())
        assert.are.same({ false, "", 0, 0, 0 }, { Facade.GetTotemInfo(1) })
    end)

    it("answers auras through shared AuraData tables in AuraUtil's order", function()
        I.AuraModel(1, 1, 5, 125, 1, 5, VS.Obs.CastSuccess, false)
        ctl.now = 6
        local a = Facade.C_UnitAuras.GetBuffDataByIndex("player", 1)
        assert.are.same({ fs.SPENDER_A, 125, 120, 1, "player" }, {
            a.spellId,
            a.expirationTime,
            a.duration,
            a.applications,
            a.sourceUnit,
        })
        assert.are.equal(a, Facade.C_UnitAuras.GetBuffDataByIndex("player", 1)) -- shared, not allocated per call
        assert.is_nil(Facade.C_UnitAuras.GetBuffDataByIndex("player", 2))
        assert.are.equal(fs.SPENDER_A, Facade.C_UnitAuras.GetPlayerAuraBySpellID(fs.SPENDER_A).spellId)
        local seen = 0
        Facade.AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
            seen = seen + aura.spellId
        end, true)
        assert.are.equal(fs.SPENDER_A, seen)
        local found = select(
            10,
            Facade.AuraUtil.FindAura(function(_, _, _, ...)
                return select(10, ...) == fs.SPENDER_A
            end, "player", "HELPFUL")
        )
        assert.are.equal(fs.SPENDER_A, found)
    end)

    it("C_Spell.IsSpellInRange asks by the known rank's ID; a secret answer is nil, true (read as in range)", function()
        local asked
        local function all(...)
            return { n = select("#", ...), ... }
        end
        answers["C_Spell.IsSpellInRange"] = function(id, unit)
            asked = id
            return unit == "target"
        end
        ctl.known[fs.SPENDER_C_R2] = true
        ctl.Fire("SPELLS_CHANGED")
        assert.are.same({ n = 1, true }, all(Facade.C_Spell.IsSpellInRange(fs.SPENDER_C, "target")))
        assert.are.equal(fs.SPENDER_C_R2, asked)
        assert.are.same({ n = 1, false }, all(Facade.C_Spell.IsSpellInRange(424242, "focus"))) -- untracked: its own ID
        assert.are.equal(424242, asked)
        answers["C_Spell.IsSpellInRange"] = function() end -- the client's plain nil: nil alone
        assert.are.same({ n = 1 }, all(Facade.C_Spell.IsSpellInRange(fs.SPENDER_C, "target")))
        answers["C_Spell.IsSpellInRange"] = nil -- secret
        assert.are.same({ n = 2, nil, true }, all(Facade.C_Spell.IsSpellInRange(fs.SPENDER_C, "target")))
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
            ctl.cooldown[fs.SPENDER_C] = { isActive = true, isOnGCD = true }
            local c = Facade.C_Spell.GetSpellCooldown(fs.SPENDER_C)
            assert.are.same({ gs, gd }, { c.startTime, c.duration })
            I.Sources.Direct(VS.Obs.Cooldown, t + 1.5, 0, 0, 1)
            I.Fold(t + 1.5, false)
        end
    end)

    it("answers a cooldown from the belief and the plain flag", function()
        I.CooldownModel(3, 40, 30, 10, VS.Obs.CastSuccess)
        ctl.now = 20
        ctl.cooldown[fs.SPENDER_C] = { isActive = true, isOnGCD = false }
        local c = Facade.C_Spell.GetSpellCooldown(fs.SPENDER_C)
        assert.are.same({ 10, 30, true }, { c.startTime, c.duration, c.isActive })
        assert.is_nil(Facade.C_Spell.GetSpellCharges(fs.SPENDER_C))
    end)

    it("answers a believed-ready tracked cooldown in the client's ready shape", function()
        I.CooldownModel(3, 15, 30, 5, VS.Obs.CastSuccess) -- learned length 30, ready since 15
        ctl.now = 20
        local c = Facade.C_Spell.GetSpellCooldown(fs.SPENDER_C)
        assert.are.same({ 0, 0, false }, { c.startTime, c.duration, c.isActive })
        ctl.cooldown[fs.SPENDER_C] = { isActive = true, isOnGCD = false }
        c = Facade.C_Spell.GetSpellCooldown(fs.SPENDER_C)
        assert.are.same({ 0, 0, true }, { c.startTime, c.duration, c.isActive })
    end)

    it("answers the ready shape when the plain flag says ready though the belief still runs", function()
        I.CooldownModel(3, 40, 30, 10, VS.Obs.CastSuccess)
        ctl.now = 39.6 -- the belief's expiry lags the client's by a poll
        ctl.cooldown[fs.SPENDER_C] = { isActive = false, isOnGCD = false }
        local c = Facade.C_Spell.GetSpellCooldown(fs.SPENDER_C)
        assert.are.same({ 0, 0, false }, { c.startTime, c.duration, c.isActive })
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
        assert.are.same(
            { "Casting", 10000, (10 + I.TARGET_CAST_DEFAULT) * 1000, 77, false },
            { name, s, e, bar, notKick }
        )
        assert.is_nil(Facade.UnitChannelInfo("target"))
    end)

    it("answers spells, power types and units nothing tracks in the real shapes, without an error", function()
        local c = Facade.C_Spell.GetSpellCooldown(999999)
        assert.are.same({ 0, 0, false }, { c.startTime, c.duration, c.isActive })
        assert.is_nil(Facade.C_Spell.GetSpellCharges(999999))
        assert.are.equal(0, Facade.UnitPower("player", 99))
        assert.are.same({ 0, 0, nil, 0, 0 }, { Facade.GetPowerRegenForPowerType(99) })
        assert.are.same({ 0 }, { Facade.UnitPowerMax("player", 99) }) -- secret: the belief's maximum (none); no base
        assert.is_nil(Facade.C_UnitAuras.GetPlayerAuraBySpellID(999999))
        assert.is_nil(Facade.C_UnitAuras.GetBuffDataByIndex("focus", 1))
        assert.are.equal(0, Facade.UnitSpellHaste("target"))
    end)

    it("passes a passthrough's arguments and every result through unchanged", function()
        local got
        answers.GetInstanceInfo = function(...)
            got = { ... }
            return "Map", "party", 1, "Normal", 5, 0, false, 33, 5
        end
        assert.are.same({ "Map", "party", 1, "Normal", 5, 0, false, 33, 5 }, { Facade.GetInstanceInfo("x", 2) })
        assert.are.same({ "x", 2 }, got)
        assert.are.equal(9, select("#", Facade.GetInstanceInfo()))
        assert.are.equal(fake.SECRET, Facade.UnitClass("target")) -- transparent: a secret is the trace's to count
    end)

    it("answers a hybrid's raw value while it is plain and the policy's once it is secret", function()
        answers.GetHaste = function()
            return 12.5
        end
        assert.are.equal(12.5, Facade.GetHaste())
        answers.GetHaste = nil
        assert.are.equal(0, Facade.GetHaste()) -- secret: Haste()
        answers.UnitAttackSpeed = function(unit)
            return unit == "target" and 2.4 or nil
        end
        assert.are.equal(2.4, Facade.UnitAttackSpeed("target"))
        ctl.cooldown[fs.SPENDER_C] = { startTime = 5, duration = 10, isActive = true, isOnGCD = false }
        assert.are.equal(ctl.cooldown[fs.SPENDER_C], Facade.C_Spell.GetSpellCooldown(fs.SPENDER_C)) -- plain times: the client's
        answers["C_Spell.GetSpellCharges"] = function()
            return nil -- not a charge spell
        end
        assert.is_nil(Facade.C_Spell.GetSpellCharges(fs.SPENDER_C))
        local secretTimes = { currentCharges = 1, cooldownStartTime = fake.SECRET, cooldownDuration = fake.SECRET }
        answers["C_Spell.GetSpellCharges"] = function()
            return secretTimes
        end
        local charges = VS.Charges
        VS.Charges = function() -- no fake ability has charges: a belief of two
            return { est = 2 }, { est = 0 }
        end
        local ch = Facade.C_Spell.GetSpellCharges(fs.SPENDER_C) -- secret times: Charges()
        VS.Charges = charges
        assert.are_not.equal(secretTimes, ch)
        assert.are.equal(2, ch.currentCharges)
        ctl.cooldown[fs.SPENDER_C] =
            { startTime = fake.SECRET, duration = fake.SECRET, isActive = false, isOnGCD = false }
        local cd = Facade.C_Spell.GetSpellCooldown(fs.SPENDER_C) -- secret times: the cooldown policy
        assert.are_not.equal(ctl.cooldown[fs.SPENDER_C], cd)
        assert.are.equal("number", type(cd.startTime))
        ctl.casting = { 1000, 2500 }
        assert.are.equal(1000, select(4, Facade.UnitCastingInfo("player"))) -- the player's plain cast: the client's
        ctl.casting = { fake.SECRET, fake.SECRET }
        assert.is_nil(Facade.UnitCastingInfo("player")) -- a secret player cast reads as none
    end)

    it("makes a passthrough the client lacks a virtual row answering nothing", function()
        local was = _G.HasOverrideActionBar
        _G.HasOverrideActionBar = nil
        local ns2 = load.module()
        _G.HasOverrideActionBar = was
        assert.are.equal("virtual", ns2.Facade.Status("HasOverrideActionBar"))
        assert.are.equal(0, select("#", ns2.Facade.HasOverrideActionBar()))
    end)

    it(
        "names the GCD by one constant: Forever's GCD spell, I.GCD_SPELL, and retail's GCD ID in no file an addon TOC loads",
        function()
            local retail = tostring(61303 + 1) -- retail's GCD spell, spelled so this file does not name it either
            for _, file in ipairs(require("helpers.addons").lua()) do
                local src = assert(io.open(file)):read("*a")
                assert.is_nil(src:find(retail, 1, true), file)
            end
            local spec = assert(io.open("src/Hekili/Engine/Schema/Spec/All.lua")):read("*a")
            assert.is_truthy(spec:find("global_cooldown = {\n        id = ns.GCD_SPELL,", 1, true))
            assert.are.equal(29515, I.GCD_SPELL) -- the belief's copy; the engine's is ns.GCD_SPELL (Constants.lua)
        end
    )

    it("answers empty spec slots and talent ranks in the shape upstream Hekili's code expects (decision 7)", function()
        answers["C_SpecializationInfo.GetSpecializationInfo"] = function(i)
            if i == 1 then
                return 1491, "Warrior", "", 1, "DAMAGER", 1
            end
            return 0, "", "", 0
        end
        assert.are.same(
            { 1491, "Warrior", "", 1, "DAMAGER", 1 },
            { Facade.C_SpecializationInfo.GetSpecializationInfo(1) }
        )
        assert.is_nil(Facade.C_SpecializationInfo.GetSpecializationInfo(2))
        local talent = { 0, 1011, 3 }
        local rank = VS.Talent
        VS.Talent = function(spell)
            return spell == 1011 and 2 or 0
        end
        local _, name, _, selected, _, spell, _, _, _, known, _, r = Facade.GetTalentInfoByID(talent, 1)
        local _, _, _, untaken = Facade.GetTalentInfoByID({ 0, 99999, 1 }, 1)
        VS.Talent = rank
        assert.are.same({ "", true, 1011, true, 2, false }, { name, selected, spell, known, r, untaken })
    end)

    it("aliases IsUsableSpell to C_Spell.IsSpellUsable", function()
        ctl.usable[5] = { true, false }
        assert.is_true(Facade.IsUsableSpell(5))
    end)
    -- The fake spec plus two player auras: a weapon-enchant pseudo-aura (main hand, RegisterAura's negative pseudo-ID)
    -- and a stealth aura (C4, C5); j 3 and 4.
    local ENCHANT, STEALTH = -1001, 1999
    local function buildWithEnchantAndStealth()
        local d = fs.def(fs.new(9))
        d.auras[3], d.auraIds[3] = { key = "enchant_x", id = ENCHANT, weaponEnchant = 0 }, { ENCHANT }
        d.auras[4], d.auraIds[4] = { key = "stealth_x", id = STEALTH, isStealthed = true }, { STEALTH }
        I.Build(d, 1)
    end

    it(
        "answers weapon enchants raw while plain, and from the enchant pseudo-aura once any field is secret (C4)",
        function()
            buildWithEnchantAndStealth()
            assert.are.same({}, Facade.C_Item.GetWeaponEnchantInfo(0)) -- secret, nothing believed: no enchant
            local plain = {
                { hasEnchant = true, enchantType = 0, timeLeft = 5000, charges = 0, enchantID = 7, enchantIconID = 1 },
            }
            answers["C_Item.GetWeaponEnchantInfo"] = function()
                return plain
            end
            assert.are.equal(plain, Facade.C_Item.GetWeaponEnchantInfo(0)) -- plain: the client's own table
            plain[1].timeLeft = fake.SECRET -- one secret field: the belief's answer, never the secret
            I.AuraModel(1, 3, 1, 1801, 20, 1, VS.Obs.CastSuccess, false) -- our apply cast: 30 min, 20 charges
            ctl.now = 101
            local list = Facade.C_Item.GetWeaponEnchantInfo(0)
            assert.are_not.equal(plain, list)
            assert.are.same({ true, 1700000, 20 }, { list[1].hasEnchant, list[1].timeLeft, list[1].charges })
            assert.are.equal(list, Facade.C_Item.GetWeaponEnchantInfo(0)) -- shared, not allocated per call
            assert.are.same({}, Facade.C_Item.GetWeaponEnchantInfo(1)) -- no off-hand pseudo-aura registered
            answers["C_Item.GetWeaponEnchantInfo"] = function()
                return fake.SECRET -- the whole answer secret
            end
            assert.are.equal(list, Facade.C_Item.GetWeaponEnchantInfo(0))
        end
    )

    it("answers IsStealthed raw while plain, and from the stealth aura's belief once secret (C5)", function()
        buildWithEnchantAndStealth()
        answers.IsStealthed = function()
            return true
        end
        assert.is_true(Facade.IsStealthed())
        answers.IsStealthed = nil -- secret
        assert.is_false(Facade.IsStealthed())
        I.AuraModel(1, 4, 1, math.huge, 1, 1, VS.Obs.CastSuccess, false)
        assert.is_true(Facade.IsStealthed())
    end)

    it("answers UnitCreatureFamily raw while plain and nothing once secret (C1, probe only)", function()
        answers.UnitCreatureFamily = function()
            return "Family", 1
        end
        assert.are.same({ "Family", 1 }, { Facade.UnitCreatureFamily("pet") })
        answers.UnitCreatureFamily = nil
        assert.is_nil(Facade.UnitCreatureFamily("pet")) -- never the secret
    end)

    -- The Map addon restriction (the owner's FR-1 run, 2026-11-05) hides unit identity: a secret is unknown (nil).
    it("answers UnitGUID, UnitIsUnit and UnitName raw while plain and nothing once secret (Map restriction)", function()
        answers.UnitGUID = function()
            return "Creature-1"
        end
        answers.UnitIsUnit = function()
            return false
        end
        answers.UnitName = function()
            return "Mob", "Realm"
        end
        assert.are.equal("Creature-1", Facade.UnitGUID("target"))
        assert.is_false(Facade.UnitIsUnit("targettarget", "player"))
        assert.are.same({ "Mob", "Realm" }, { Facade.UnitName("target") })
        answers.UnitGUID, answers.UnitIsUnit, answers.UnitName = nil, nil, nil -- secret
        assert.is_nil(Facade.UnitGUID("target"))
        assert.is_nil(Facade.UnitIsUnit("targettarget", "player"))
        assert.is_true(Facade.UnitIsUnit("player", "player")) -- a token is itself, secret or not
        assert.is_nil(Facade.UnitName("target"))
        for _, n in ipairs({ "UnitGUID", "UnitIsUnit", "UnitName" }) do
            assert.are.equal("hybrid", Facade.Status(n))
        end
    end)

    it("answers UnitExists raw for any unit but the pet, and the belief's for a secret pet read (C1)", function()
        answers.UnitExists = function(unit)
            return unit == "target"
        end
        assert.is_true(Facade.UnitExists("target"))
        assert.is_false(Facade.UnitExists("focus"))
        answers.UnitExists = nil -- secret
        assert.is_true(api.issecretvalue(Facade.UnitExists("target"))) -- another unit: raw, as the passthrough was
        assert.is_false(Facade.UnitExists("pet")) -- the belief's: no pet observed, never the secret
        assert.is_false(api.issecretvalue(Facade.UnitExists("pet")))
    end)

    it("answers UnitRangedDamage raw while plain and the out-of-combat cache once secret (C7, probe only)", function()
        answers.UnitRangedDamage = function()
            return 2.9, 10, 20, 0, 0, 1
        end
        -- after the client's six: the belief's next ranged shot and the ranged hand's speed (border batch 2, E6)
        local shot, shotSpeed = VS.Swing(3, ctl.now).est, VS.SwingSpeed(3, ctl.now).est
        assert.are.same({ 2.9, 10, 20, 0, 0, 1, shot, shotSpeed }, { Facade.UnitRangedDamage("player") })
        answers.UnitRangedDamage = nil
        local speed, lo, hi, _, _, _, s7, s8 = Facade.UnitRangedDamage("player") -- secret: the fake's plain read at Start
        assert.are.same({ ctl.ranged[1], ctl.ranged[2], ctl.ranged[3], shot, shotSpeed }, { speed, lo, hi, s7, s8 })
    end)

    -- range plan R2 (owner amendment 2026-11-11): LibRangeCheck feeds the belief's bracket; the row answers it for
    -- the target and the library's own answer for any other unit with a plain GUID
    it(
        "LibRangeCheck.GetRange answers the target's believed bracket, fed by the library; no upper bound and unknown read as nil",
        function()
            local RC = Facade.LibRangeCheck
            local function at(d, t)
                ctl.distance.target = d
                ctl.Tick(t)
                I.Sources.RunPolls(t)
                I.Fold(t, false)
                I.Settle(t)
                return { RC:GetRange("target") }
            end
            ctl.Fire("PLAYER_TARGET_CHANGED")
            assert.are.same({}, at(fake.SECRET, 2)) -- a target, no plain range answer yet: unknown
            assert.are.same({ 15, 20 }, at(20, 3)) -- the library double's 5 yd bracket
            assert.are.same({ 0, 5 }, at(2, 4))
            assert.are.same({ 100 }, at(150, 5)) -- past the library's last check: a lower bound only
            local n = ctl.rangeLibCalls
            assert.are.same({ 100 }, { RC:GetRange("target") }) -- the belief's answer: the library is not asked again
            assert.are.equal(n, ctl.rangeLibCalls)
            ctl.Fire("PLAYER_TARGET_CHANGED")
            assert.are.same({}, at(fake.SECRET, 6)) -- a new target, every read secret: unknown again
        end
    )

    it(
        "LibRangeCheck.GetRange asks the library for a plate with a plain GUID, never for one whose GUID is secret",
        function()
            local RC = Facade.LibRangeCheck
            answers.UnitGUID = function(unit)
                return unit == "nameplate1" and "Creature-9" or fake.SECRET
            end
            ctl.distance.nameplate1, ctl.distance.nameplate2 = 12, 12
            ctl.exists.nameplate1, ctl.exists.nameplate2 = true, true
            ctl.guid.nameplate1 = "Creature-9" -- the library's own UnitGUID read (its cache key)
            assert.are.same({ 10, 15 }, { RC:GetRange("nameplate1") })
            local n = ctl.rangeLibCalls
            assert.are.same({}, { RC:GetRange("nameplate2") }) -- the Map restriction: not asked until probe G2 (R3)
            assert.are.equal(n, ctl.rangeLibCalls)
            ctl.distance.nameplate1 = fake.SECRET -- a secret answer: nothing
            assert.are.same({}, { RC:GetRange("nameplate1") })
        end
    )

    it("RangeLib answers nothing, never an error, when the library raises on the target", function()
        ctl.distance.target = 7
        assert.are.same({ 5, 10 }, { Facade.RangeLib("target") })
        ctl.rangeLib = "raise"
        local got
        assert.has_no.errors(function()
            got = { Facade.RangeLib("target") }
        end)
        assert.are.same({}, got)
        ctl.rangeLib, ctl.distance.target = nil, fake.SECRET
        assert.are.same({}, { Facade.RangeLib("target") })
    end)

    -- the belief stamps the target's answer with its poll's time: the library's 0.1 s cache would hand a poll the
    -- previous one's answer (a Hunter replay's off-GCD row moved by it, range plan R2 round 4)
    it("RangeLib asks the library afresh for the target at each read, past its cache", function()
        ctl.distance.target = 7
        assert.are.same({ 5, 10 }, { Facade.RangeLib("target") })
        ctl.distance.target = 12 -- the same instant: a cached answer would still say 5-10
        assert.are.same({ 10, 15 }, { Facade.RangeLib("target") })
    end)
end)
