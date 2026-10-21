-- tests/Forever/shaman_spec.lua: the Forever Shaman class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through the recording stand-in (helpers/load_druid.lua with Shaman.lua), its
-- handlers and `now` lines (the totem summons, Lightning Shield's charges, Maelstrom Weapon, the shocks' shared
-- cooldown, the imbues), the focus lines, and the class through the real engine (headless.lua): every `now` in
-- VirtualState's context, a summon's modelled slot read by the simulation in combat, the imbue reminder before combat.
-- What Hekili does with the rest is verified in game (the checkpoint list, docs/dev/layout.md).
local ld = require("Forever.helpers.load_druid")
local headless = require("Game.harness.headless")

local FILE = "src/Hekili_Shaman/Shaman.lua"

-- key = { spell IDs in rank order, the top rank's mana cost, cooldown, gcd }, from the DB2 (`wowdb spell <name>`;
-- Stormstrike's cost from wowsims/forever's spell data, absent from the DB2 at 70338): the
-- cooldown is the larger of RecoveryTime and CategoryRecoveryTime; gcd "spell" for 1.5 s, "totem" for 1.0 s.
local KIT = {
    lightning_bolt = { { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 }, 220, 0, "spell" },
    lightning_shield = { { 324, 325, 905, 945, 8134, 10431, 10432 }, 370, 0, "spell" },
    earth_shock = { { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, 450, 6, "spell" },
    flame_shock = { { 8050, 8052, 8053, 10447, 10448, 29228 }, 410, 6, "spell" },
    fire_nova = { { 408341, 408342, 408343, 408344, 408345 }, 520, 10, "spell" }, -- wowsims's 375 not modelled
    stormstrike = { { 17364 }, 121, 8, "spell" }, -- wowsims's data: 8% of base mana (DB2 125 flat)
    searing_totem = { { 3599, 6363, 6364, 6365, 10437, 10438 }, 170, 0, "totem" },
    flametongue_totem = { { 8227, 8249, 10526, 16387 }, 275, 0, "totem" },
    strength_of_earth_totem = { { 8075, 8160, 8161, 10442, 25361 }, 275, 0, "totem" },
    grace_of_air_totem = { { 8835, 10627, 25359 }, 310, 0, "totem" },
    mana_spring_totem = { { 5675, 10495, 10496, 10497 }, 100, 0, "totem" },
    rockbiter_weapon = { { 8017, 8018, 8019, 10399, 16314, 16315, 16316 }, 150, 0, "spell" },
    flametongue_weapon = { { 8024, 8027, 8030, 16339, 16341, 16342 }, 155, 0, "spell" },
    windfury_weapon = { { 8232, 8235, 10486, 16362 }, 165, 0, "spell" },
    frostbrand_weapon = { { 8033, 8038, 10456, 16355, 16356 }, 160, 0, "spell" },
    rage_of_the_farseer = { { 425336 }, 0, 180, "off" }, -- a Forever talent: no cost, off the GCD
}

-- Each totem's element and its ranks' durations (DB2 duration_ms).
local TOTEMS = {
    searing_totem = { "fire", { 30, 35, 40, 45, 50, 55 } },
    flametongue_totem = { "fire", { 300, 300, 300, 300 } },
    strength_of_earth_totem = { "earth", { 300, 300, 300, 300, 300 } },
    grace_of_air_totem = { "air", { 300, 300, 300 } },
    mana_spring_totem = { "water", { 300, 300, 300, 300 } },
}

local function idsOf(a)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
        out[#out + 1] = id
    end
    return out
end

-- `buff` with the stacks in `up` (a number) or up (true).
local function buffs(up)
    return setmetatable({}, {
        __index = function(_, k)
            local v = up[k]
            return { up = v ~= nil, stack = type(v) == "number" and v or (v and 1 or 0), remains = v and 10 or 0 }
        end,
    })
end

describe("Forever Shaman", function()
    local w

    before_each(function()
        w = ld.load(nil, FILE, "SHAMAN")
    end)

    it("registers the kit with the DB2's ranks, top-rank costs, cooldowns and GCDs", function()
        local n = 0
        for key, a in pairs(w.abilities) do
            n = n + 1
            local want = assert(KIT[key], "unexpected ability " .. key)
            local ids = want[1]
            for _, id in ipairs(ids) do -- the top rank known: its cost
                w.game.known[id] = false
            end
            w.game.known[ids[#ids]] = true
            local e = ld.env(w)
            assert.are.same(ids, idsOf(a), key)
            assert.are.same(
                { want[2], want[3], want[4] },
                { ld.run(a.spend, e) or 0, ld.run(a.cooldown, e), a.gcd },
                key
            )
            assert.are.equal("function", type(a.known), key)
        end
        assert.are.equal(16, n)
        assert.are.equal("SHAMAN", w.class)
        assert.is_nil(w.options)
        assert.is_nil(w.abilities.windfury_totem) -- the party's (research §4): never prompted
    end)

    it("places every DB2 talent in a tree and keeps the Forever-only ones at tree 0", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 2, 15, 16, 15 }, n)
        assert.are.same({ 0, 1223030, 1 }, w.talents.shamanistic_focus) -- wowsims's tree; not in the DB2's Talent table
        assert.are.same({ 0, 425336, 1 }, w.talents.rage_of_the_farseer)
    end)

    it(
        "declares mana under the five-second rule and no settings (the hand-built list's are retired with it)",
        function()
            assert.are.same({ 0 }, w.order)
            assert.are.same({ spirit = 17, mp5 = 2 }, w.resources[0].meta.fsr)
            assert.is_nil(next(w.settings or {}))
        end
    )

    it("registers each totem with its element and durations, and its summon fills that slot for its rank's", function()
        for key, want in pairs(TOTEMS) do
            local t = assert(w.totems[key], key)
            assert.are.same({ KIT[key][1], want[1], want[2] }, { idsOf(t), t.element, t.duration }, key)
            for r, id in ipairs(KIT[key][1]) do
                for _, other in ipairs(KIT[key][1]) do
                    w.game.known[other] = false
                end
                w.game.known[id] = true
                for _, field in ipairs({ "now", "handler" }) do
                    local got = {}
                    local e = ld.env(w)
                    e.summonTotem = function(...)
                        got[#got + 1] = { ... }
                    end
                    ld.run(w.abilities[key][field], e)
                    assert.are.same({ { key, want[1], want[2][r] } }, got, key .. " " .. r .. " " .. field)
                end
            end
        end
    end)

    it("needs a fire totem for Fire Nova, its answers a mana rung", function()
        local f = w.abilities.fire_nova
        local e = ld.env(w)
        e.totem = { fire = { up = false } }
        assert.is_false((ld.run(f.usable, e)))
        e.totem.fire.up = true
        assert.is_true((ld.run(f.usable, e)))
        assert.is_nil(f.ladder)
    end)

    it("gives Lightning Shield 3 charges, each hit that lands on us spending one", function()
        local a = w.auras.lightning_shield
        assert.are.same({ 3, 600, { WOUND = true, BLOCKED = true } }, { a.max_stack, a.duration, a.consumedBy })
        for _, field in ipairs({ "now", "handler" }) do
            local e = ld.env(w)
            local got = {}
            e.applyBuff = function(k, d, s)
                got[#got + 1] = { k, d, s }
            end
            ld.run(w.abilities.lightning_shield[field], e)
            assert.are.same({ { "lightning_shield", nil, 3 } }, got, field)
        end
    end)

    it(
        "takes 20% of Lightning Bolt's cast and cost a Maelstrom Weapon stack, five making it free; the cast spends them",
        function()
            local lb = w.abilities.lightning_bolt
            w.game.known[15208] = true
            local e = ld.env(w)
            assert.are.same({ 2.5, 220 }, { ld.run(lb.cast, e), ld.run(lb.spend, e) })
            e.buff = buffs({ maelstrom_weapon = 3 })
            local cast, spend = ld.run(lb.cast, e), ld.run(lb.spend, e)
            assert.are.same({ 1, 88 }, { math.floor(cast * 1000 + 0.5) / 1000, math.floor(spend + 0.5) })
            e.buff = buffs({ maelstrom_weapon = 5 })
            assert.are.same({ 0, 0 }, { ld.run(lb.cast, e), ld.run(lb.spend, e) })
            for _, field in ipairs({ "now", "handler" }) do
                e = ld.env(w)
                ld.run(lb[field], e)
                assert.are.same({ "maelstrom_weapon" }, e.removed, field)
            end
            assert.are.same({ 408505, 30, 5 }, {
                w.auras.maelstrom_weapon.id,
                w.auras.maelstrom_weapon.duration,
                w.auras.maelstrom_weapon.max_stack,
            })
        end
    )

    it("makes Clearcasting a charged -100% on the elemental spells", function()
        assert.are.same({
            { aura = "clearcasting", pct = -1, charges = 1, spells = { 403, 8042, 8050, 408341 } },
        }, w.costMods)
        assert.are.same({ 16246, 15 }, { w.auras.clearcasting.id, w.auras.clearcasting.duration })
    end)

    it("shares the shocks' 6 s cooldown; Flame Shock leaves its DoT", function()
        for _, case in ipairs({
            { "earth_shock", "flame_shock", {} },
            { "flame_shock", "earth_shock", { "flame_shock" } },
        }) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                local cds = {}
                e.setCooldown = function(k, v)
                    cds[#cds + 1] = { k, v }
                end
                ld.run(w.abilities[case[1]][field], e)
                assert.are.same({ { { case[2], 6 } }, case[3] }, { cds, e.applied }, case[1] .. " " .. field)
            end
        end
        local e = ld.env(w)
        assert.are.same({ 8050, 12 }, { w.auras.flame_shock.id, ld.run(w.auras.flame_shock.duration, e) })
    end)

    -- wowsims spell data, absent from DB2 (wowdb effects 16038 has none): Call of Flame's effect 2, +3000 ms a rank on
    -- Flame Shock (its talent curve 3000/6000/9000); wowsims's log of the 3/3 build: Flame Shock 21 s.
    it("lengthens Flame Shock by 3 s a rank of Call of Flame", function()
        local e = ld.env(w)
        e.talent.call_of_flame = { rank = 3, enabled = true }
        assert.are.equal(21, ld.run(w.auras.flame_shock.duration, e))
        for _, field in ipairs({ "now", "handler" }) do
            local f = ld.env(w)
            f.talent.call_of_flame = { rank = 3, enabled = true }
            f.setCooldown = function() end
            ld.run(w.abilities.flame_shock[field], f)
            assert.are.equal(21, f.durations.flame_shock, field)
        end
    end)

    -- Rank 1's value x the rank (Druid's precedent; the DB2's higher ranks carry no effects): Reverberation (16040,
    -- aura 107 misc 11, -200 ms) on the shocks, Improved Fire Nova (16086, aura 107 misc 11, -2000 ms) on Fire Nova.
    -- wowsims's log of the 5/5 and 2/2 build: shocks 5 s apart, Fire Novas 6 s apart.
    it("shortens the shocks' cooldown with Reverberation and Fire Nova's with Improved Fire Nova", function()
        local e = ld.env(w)
        e.talent.reverberation = { rank = 5, enabled = true }
        e.talent.improved_fire_nova = { rank = 2, enabled = true }
        assert.are.same({ 5, 5, 6 }, {
            ld.run(w.abilities.earth_shock.cooldown, e),
            ld.run(w.abilities.flame_shock.cooldown, e),
            ld.run(w.abilities.fire_nova.cooldown, e),
        })
        local cds = {}
        e.setCooldown = function(k, v)
            cds[#cds + 1] = { k, v }
        end
        ld.run(w.abilities.earth_shock.handler, e)
        assert.are.same({ { "flame_shock", 5 } }, cds)
    end)

    -- Shamanistic Focus (1223030, aura 108 misc 14, -45% on mask 0x90100400: the shocks and Lightning Shield); wowsims's
    -- log: Flame Shock 225.5, Lightning Shield 203.5.
    it("takes 45% off the shocks' and Lightning Shield's cost with Shamanistic Focus", function()
        for _, ids in ipairs({ KIT.flame_shock[1], KIT.earth_shock[1], KIT.lightning_shield[1] }) do
            w.game.known[ids[#ids]] = true
        end
        local e = ld.env(w)
        e.talent.shamanistic_focus = { rank = 1, enabled = true }
        assert.are.same({ 410 * 0.55, 450 * 0.55, 370 * 0.55 }, {
            ld.run(w.abilities.flame_shock.spend, e),
            ld.run(w.abilities.earth_shock.spend, e),
            ld.run(w.abilities.lightning_shield.spend, e),
        })
    end)

    -- Rage of the Farseer (425336, DB2): 25 s of +30% melee and ranged attack speed (aura 342), 180 s cooldown, a major
    -- cooldown (wowsims/forever sim/shaman/talents_enhancement.go: CooldownTypeDPS).
    it("puts Rage of the Farseer under Cooldowns, its cast giving its 25 s buff", function()
        local a = w.abilities.rage_of_the_farseer
        assert.are.same({ "cooldowns", false }, { a.toggle, a.startsCombat })
        assert.are.same({ 425336, 25, 1 }, {
            w.auras.rage_of_the_farseer.id,
            w.auras.rage_of_the_farseer.duration,
            w.auras.rage_of_the_farseer.max_stack,
        })
        for _, field in ipairs({ "now", "handler" }) do
            local e = ld.env(w)
            ld.run(a[field], e)
            assert.are.same({ "rage_of_the_farseer" }, e.applied, field)
        end
    end)

    it("models each imbue on the main hand for its 60 minutes", function()
        for _, key in ipairs({ "rockbiter_weapon", "flametongue_weapon", "windfury_weapon", "frostbrand_weapon" }) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                ld.run(w.abilities[key][field], e)
                assert.are.same({ { "main_hand_enchant" }, 3600 }, { e.applied, e.durations.main_hand_enchant }, key)
            end
        end
    end)
end)

-- The default priority, Enhancement (wowsims.com) (generated from wowsims/forever's APL), and its D1 focus tiers.
describe("Forever Shaman priorities", function()
    local packs = {}
    setup(function()
        for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", "shaman")) do
            packs[p.name] = p
        end
    end)

    local PACK = "Enhancement (wowsims.com)"

    local function line(list, action, criteria)
        for i, e in ipairs(packs[PACK].lists[list]) do
            if e.action == action and (criteria == nil or e.criteria == criteria) then
                return i, e
            end
        end
        error("no " .. action .. " if " .. tostring(criteria))
    end

    it("keeps the class file's generated block in step with APLs/", function()
        local mp = assert(loadfile("tools/make_pack.lua"))("lib")
        local f = assert(io.open(FILE))
        local src = f:read("*a")
        f:close()
        assert.are.equal(src, (mp.sync(src, mp.load("shaman"))))
    end)

    it("names only registered abilities, auras, settings and totem elements", function()
        local cls = ld.load(nil, FILE, "SHAMAN")
        local shared = { major_mana_potion = true, demonic_rune = true, blood_fury = true } -- Hekili_Shared's consumables, the Orc racial
        local kinds = { buff = cls.auras, debuff = cls.auras, cooldown = cls.abilities, settings = cls.settings }
        local elements = { fire = true, earth = true, water = true, air = true, main_hand_enchant = true }
        for list, entries in pairs(packs[PACK].lists) do
            for i, e in ipairs(entries) do
                local where = list .. " " .. i
                assert.is_true(cls.abilities[e.action] ~= nil or shared[e.action] == true, where)
                for kind, key in (e.criteria or ""):gmatch("(%a+)%.([%w_]+)") do
                    if kinds[kind] then
                        assert.is_true(kinds[kind][key] ~= nil or elements[key] == true, where .. ": " .. key)
                    elseif kind == "totem" then
                        assert.is_true(elements[key], where .. ": totem " .. key)
                    end
                end
            end
        end
    end)

    it(
        "tiers by role: Fire Nova on Clearcasting and the Maelstrom Lightning Bolt at 1, the shield and Flame Shock at 2, totems none",
        function()
            local _, fn = line("default", "fire_nova", "buff.clearcasting.up")
            local _, lb = line("default", "lightning_bolt", "buff.maelstrom_weapon.stack>=5")
            local _, goa = line("default", "grace_of_air_totem", "totem.air.remains<=0")
            local _, soe = line("default", "strength_of_earth_totem", "totem.earth.remains<=0")
            local _, st = line("default", "searing_totem", "totem.fire.remains<=0")
            local _, ls = line("default", "lightning_shield", "!buff.lightning_shield.up")
            local _, fs = line("default", "flame_shock", "!debuff.flame_shock.up")
            assert.are.same({ 1, 1, 2, 2 }, { fn.focus, lb.focus, ls.focus, fs.focus })
            assert.are.same({}, { goa.focus, soe.focus, st.focus })
            for _, e in ipairs(packs[PACK].lists.default) do
                assert.are_not.equal("windfury_totem", e.action)
            end
        end
    )

    -- wowsims's autocast (rule 13) in the log's first-use order: Blood Fury, the trinket (unmapped), Rage of the Farseer.
    it("casts Rage of the Farseer off the GCD right after Blood Fury, as wowsims's autocast does", function()
        local bf = line("default", "blood_fury")
        local i, e = line("default", "rage_of_the_farseer")
        assert.are.same({ bf + 1, nil }, { i, e.criteria })
        assert.is_truthy(e.use_off_gcd)
    end)
end)

-- Through the real engine (headless.lua): a Shaman who knows the whole kit.
describe("Forever Shaman through the engine", function()
    local H

    local function character()
        local w = ld.load(nil, FILE, "SHAMAN")
        local known = {}
        for _, a in pairs(w.abilities) do
            for _, id in ipairs(idsOf(a)) do
                known[#known + 1] = id
            end
        end
        return {
            class = "SHAMAN",
            classID = 7,
            specID = 1489,
            level = 60,
            known = known,
            talents = {},
            power = { type = 0, token = "MANA", max = 5000, value = 5000 },
            speed = { 3.6 },
        },
            w
    end

    before_each(function()
        H = headless.new({ character = character(), pack = "Enhancement (wowsims.com)" })
    end)

    it("runs every declared `now` in VirtualState's context without an error", function()
        assert.are.same({}, H.loadErrors)
        local _, w = character()
        local I = H.ns.VirtualStateInternal
        local runs0, t, n = I.nowRuns, H.ctl.now, 0
        for _, a in pairs(w.abilities) do
            if a.now then
                t, n = t + 1, n + 1
                H.ctl.now = t
                H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, a.id)
                assert.is_true(headless.cycle(H, t + 0.1))
            end
        end
        assert.are.same({ 0, n }, { I.nowErrors, I.nowRuns - runs0 }, tostring(I.nowError))
        assert.are.same({}, H.errors)
    end)

    it("answers a Searing Totem summoned in combat from the modelled slot, in the belief and the simulation", function()
        local VS, S = H.ns.VirtualState, H.Hekili.State
        local t = H.ctl.now + 1
        assert.is_true(headless.cycle(H, t))
        S.reset("Primary", true) -- at now: the cycle leaves the state after its simulated precombat totems
        assert.is_false(S.totem.fire.up) -- read out of combat: empty
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        local S0 = require("Game.State.helpers.fake_api").SECRET -- GetTotemInfo is secret in combat
        H.ctl.totems[1] = { name = S0, start = S0, duration = S0, icon = S0, spell = S0 }
        t = t + 1
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 10438)
        H.Fire("PLAYER_TOTEM_UPDATE", 1)
        assert.is_true(headless.cycle(H, t + 0.1))
        local rec = VS.Totem(1, t + 0.1)
        assert.are.same({ t + 55, "modelled" }, { rec.est, rec.basis })
        assert.is_nil(VS.Totem(4, t + 0.1))
        S.reset("Primary", true) -- the simulation at now: the slot re-read after the reset, not the first read's 0
        assert.is_true(S.totem.fire.up)
        assert.are.equal(t + 55, S.totem.fire.expires)
        assert.is_false(S.totem.air.up)
        assert.are.same({}, H.errors)
    end)

    it("recommends Rage of the Farseer in combat when ready, only with Cooldowns on", function()
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        local t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        local cds = H.Hekili.DB.profile.toggles.cooldowns
        H.Fire("PLAYER_REGEN_DISABLED")
        for _, on in ipairs({ true, false }) do
            cds.value = on
            t = t + 0.2
            assert(headless.cycle(H, t))
            assert.are.same({}, H.errors)
            local first = out.recs[1] and out.recs[1].actionName
            assert.are.equal(on, first == "rage_of_the_farseer", tostring(first))
        end
    end)
end)
