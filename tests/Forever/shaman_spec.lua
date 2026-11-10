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
-- Stormstrike's, Chain Lightning's and Mana Tide Totem's costs and its Forever-only rank 4 (1325256) from wowsims/forever's
-- spell data, absent from the DB2 at 70338): the cooldown is the larger of RecoveryTime and CategoryRecoveryTime; gcd
-- "spell" for 1.5 s, "totem" for 1.0 s, "off" for none.
local KIT = {
    lightning_bolt = { { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 }, 220, 0, "spell" },
    lightning_shield = { { 324, 325, 905, 945, 8134, 10431, 10432 }, 370, 0, "spell" },
    earth_shock = { { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, 450, 6, "spell" },
    flame_shock = { { 8050, 8052, 8053, 10447, 10448, 29228 }, 410, 6, "spell" },
    fire_nova = { { 408341, 408342, 408343, 408344, 408345 }, 375, 10, "spell" }, -- the game's (owner's tooltips, every rank; DB2 520)
    stormstrike = { { 17364 }, 121, 6, "spell" }, -- wowsims's data: 8% of base mana (DB2 125 flat)
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
    chain_lightning = { { 421, 930, 2860, 10605 }, 495, 6, "spell" }, -- wowsims's (DB2 485)
    elemental_mastery = { { 16166 }, 0, 180, "off" },
    magma_totem = { { 8190, 10585, 10586, 10587 }, 650, 0, "totem" },
    windfury_totem = { { 8512, 10613, 10614 }, 250, 0, "totem" },
    mana_tide_totem = { { 16190, 17354, 17359, 1325256 }, 60, 300, "totem" },
    water_shield = { { 408510 }, 0, 0, "spell" },
    -- the totems with no rotation use (wowsims e2842f0a78; levels agree with the DB2 SpellLevels); a percent cost
    -- is of base mana 1520 as Stormstrike's (Poison/Disease Cleansing 10%, Earthbind/Grounding 6%)
    stoneskin_totem = { { 8071, 8154, 8155, 10406, 10407, 10408 }, 210, 0, "totem" },
    healing_stream_totem = { { 5394, 6375, 6377, 10462, 10463 }, 80, 0, "totem" },
    fire_resistance_totem = { { 8184, 10537, 10538 }, 180, 0, "totem" },
    frost_resistance_totem = { { 8181, 10478, 10479 }, 180, 0, "totem" },
    nature_resistance_totem = { { 10595, 10600, 10601 }, 180, 0, "totem" },
    windwall_totem = { { 15107, 15111, 15112 }, 225, 0, "totem" },
    tremor_totem = { { 8143 }, 60, 0, "totem" },
    poison_cleansing_totem = { { 8166 }, 152, 0, "totem" },
    disease_cleansing_totem = { { 8170 }, 152, 0, "totem" },
    sentry_totem = { { 6495 }, 65, 0, "totem" },
    earthbind_totem = { { 2484 }, 91, 15, "totem" },
    stoneclaw_totem = { { 5730, 6390, 6391, 6392, 10427, 10428 }, 140, 30, "totem" },
    grounding_totem = { { 8177 }, 91, 15, "totem" },
}

-- Each totem's element and its ranks' durations (DB2 duration_ms).
local TOTEMS = {
    searing_totem = { "fire", { 30, 35, 40, 45, 50, 55 } },
    flametongue_totem = { "fire", { 300, 300, 300, 300 } },
    strength_of_earth_totem = { "earth", { 300, 300, 300, 300, 300 } },
    grace_of_air_totem = { "air", { 300, 300, 300 } },
    mana_spring_totem = { "water", { 300, 300, 300, 300 } },
    magma_totem = { "fire", { 20, 20, 20, 20 } },
    windfury_totem = { "air", { 300, 300, 300 } },
    mana_tide_totem = { "water", { 13, 13, 13, 13 } },
    stoneskin_totem = { "earth", { 300, 300, 300, 300, 300, 300 } },
    healing_stream_totem = { "water", { 300, 300, 300, 300, 300 } },
    fire_resistance_totem = { "water", { 300, 300, 300 } },
    frost_resistance_totem = { "fire", { 300, 300, 300 } },
    nature_resistance_totem = { "air", { 300, 300, 300 } },
    windwall_totem = { "air", { 300, 300, 300 } },
    tremor_totem = { "earth", { 300 } },
    poison_cleansing_totem = { "water", { 300 } },
    disease_cleansing_totem = { "water", { 300 } },
    sentry_totem = { "air", { 300 } },
    earthbind_totem = { "earth", { 45 } },
    stoneclaw_totem = { "earth", { 15, 15, 15, 15, 15, 15 } },
    grounding_totem = { "air", { 45 } },
}

-- Each totem's lasting buff on the party: key, the top rank's aura, the lower ranks', duration. The `<key>_totem`
-- alias leads the copy list. Tremor, the cleansers, Sentry, Earthbind, Stoneclaw, Grounding, Searing and Magma leave none.
local TOTEM_AURAS = {
    { "stoneskin", 10405, { 8072, 8156, 8157, 10403, 10404 }, 300 },
    { "strength_of_earth", 25362, { 8076, 8162, 8163, 10441 }, 300 },
    { "grace_of_air", 25360, { 8836, 10626 }, 300 },
    { "mana_spring", 10494, { 5677, 10491, 10493 }, 300 },
    { "mana_tide", 1325257, { 16191, 17355, 17360 }, 13 },
    { "healing_stream", 10461, { 5672, 6371, 6372, 10460 }, 300 },
    { "fire_resistance", 10535, { 8185, 10534 }, 300 },
    { "frost_resistance", 10477, { 8182, 10476 }, 300 },
    { "nature_resistance", 10599, { 10596, 10598 }, 300 },
    { "windwall", 15110, { 15108, 15109 }, 300 },
    { "flametongue", 15036, { 8230, 8250, 10521 }, 300 },
    { "windfury", 10612, { 8515, 10609 }, 300 },
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
        assert.are.equal(35, n)
        assert.are.equal("SHAMAN", w.class)
        assert.is_nil(w.options)
        assert.are.equal("cooldowns", w.abilities.elemental_mastery.toggle)
    end)

    -- translator-5: Enhancement's AoE Chain Lightning reads min(mainhand_remains,offhand_remains) (wowsims's AnyAuto)
    it("times each hand's next swing; with no off-hand weapon that hand never swings", function()
        local e = ld.env(w)
        e.combat, e.now, e.query_time = 1, 0, 5
        e.nextMH, e.mainhand_speed, e.nextOH, e.offhand_speed = 1, 3.6, 0.5, 0
        assert.is_true(math.abs(ld.run(w.exprs.mainhand_remains, e) - 3.2) < 1e-9) -- 3.6 - (5 - 1) % 3.6
        assert.are.equal(3600, ld.run(w.exprs.offhand_remains, e)) -- a two-hander: wowsims's NeverExpires
        e.offhand_speed = 2
        assert.is_true(math.abs(ld.run(w.exprs.offhand_remains, e) - 1.5) < 1e-9) -- 2 - 4.5 % 2
    end)

    it("places every talent in a tree (Forever's)", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 0, 16, 18, 16 }, n) -- Forever's tree (trees/shaman.json)
        assert.are.same({ 2, 1223030, 1 }, w.talents.shamanistic_focus)
        assert.are.same({ 2, 425336, 1 }, w.talents.rage_of_the_farseer)
    end)

    it("declares no settings (the hand-built list's are retired with it)", function()
        assert.are.same({ 0 }, w.order)
        assert.is_nil(next(w.settings or {}))
    end)

    it("declares mana as wowsims's logs measure it per spec, and Improved Stormstrike's casting share", function()
        local r, e = w.resources[0], ld.env(w)
        local function seed(key)
            w.state.spec = { [key] = true } -- the pack's functions read state.spec (the file's `spec` is the class)
            return { ld.run(r.meta.fsr.spirit, e), ld.run(r.meta.fsr.mp5, e), ld.run(r.meta.fsr.share, e) or 0 }
        end
        assert.are.same({ 14.12, 26.13, 0.15 }, seed("elemental")) -- Mindfulness 3/3: 15% while casting; no totem; re-pin log
        assert.are.same({ 31.25, 12.8, 0 }, seed("enhancement")) -- re-pin log (Windshaper Skyborne)
        assert.are.same({ aura = "improved_stormstrike", share = 0.5 }, r.models.improved_stormstrike)
        assert.are.same({ 2, 1223031, 2 }, w.talents.improved_stormstrike)
        -- Mana Spring Totem's buff: 10 every 2 s at rank 4 (DB2 aura 24), +5% a rank of Restorative Totems
        local ms = r.models.mana_spring
        assert.are.equal("mana_spring", ms.aura)
        assert.are.same(
            { 10494, { "mana_spring_totem", 5677, 10491, 10493 } },
            { w.auras.mana_spring.id, w.auras.mana_spring.copy }
        )
        for _, id in ipairs({ 5675, 10495, 10496 }) do
            w.game.known[id] = false
        end
        w.game.known[10497] = true
        w.state.talent.restorative_totems = { rank = 0 }
        assert.are.equal(5, setfenv(ms.mp5, w.state)())
        w.state.talent.restorative_totems = { rank = 5 }
        assert.are.equal(6.25, setfenv(ms.mp5, w.state)())
        w.game.known[10497], w.game.known[5675] = false, true -- rank 1: 4 every 2 s
        assert.are.equal(2.5, setfenv(ms.mp5, w.state)())
        assert.are.same(1238931, w.auras.improved_stormstrike.id)
    end)

    it("declares each totem's buff under its name and its _totem alias, and no other totem buff", function()
        for _, t in ipairs(TOTEM_AURAS) do
            local key, id, lower, duration = t[1], t[2], t[3], t[4]
            local copy = { key .. "_totem" }
            for _, l in ipairs(lower) do
                copy[#copy + 1] = l
            end
            local a = w.auras[key]
            assert.are.same({ id, copy, duration, 1 }, { a.id, a.copy, a.duration, a.max_stack }, key)
        end
        for _, key in ipairs({
            "tremor",
            "poison_cleansing",
            "disease_cleansing",
            "sentry",
            "earthbind",
            "stoneclaw",
            "grounding",
            "searing",
            "magma",
        }) do
            assert.is_nil(w.auras[key], key)
            assert.is_nil(w.auras[key .. "_totem"], key)
        end
    end)

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

    -- wowsims spell data (e2842f0a78 spells_auto_gen.go: 16086 effect 3, misc 1, +10000/+20000 ms on Magma Totem):
    -- Trial by Fire (the kit's improved_fire_nova) lengthens Magma Totem; the re-pin log's 2/2 build recasts it 40 s apart.
    it("lengthens Magma Totem by 10 s a rank of Trial by Fire (improved_fire_nova)", function()
        for _, field in ipairs({ "now", "handler" }) do
            local got = {}
            local e = ld.env(w)
            e.talent.improved_fire_nova = { rank = 2, enabled = true }
            e.summonTotem = function(...)
                got[#got + 1] = { ... }
            end
            ld.run(w.abilities.magma_totem[field], e)
            assert.are.same({ { "magma_totem", "fire", 40 } }, got, field)
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

    it(
        "gives each shield 3 charges, each hit that lands on us spending one; a shield takes the other's place",
        function()
            for key, other in pairs({ lightning_shield = "water_shield", water_shield = "lightning_shield" }) do
                local a = w.auras[key]
                assert.are.same({ 3, 600, { WOUND = true, BLOCKED = true } }, { a.max_stack, a.duration, a.consumedBy })
                for _, field in ipairs({ "now", "handler" }) do
                    local e = ld.env(w)
                    local got = {}
                    e.applyBuff = function(k, d, s)
                        got[#got + 1] = { k, d, s }
                    end
                    ld.run(w.abilities[key][field], e)
                    assert.are.same({ { { key, nil, 3 } }, { other } }, { got, e.removed }, key .. " " .. field)
                end
            end
            assert.are.same({ 324, 408510 }, { w.auras.lightning_shield.id, w.auras.water_shield.id })
        end
    )

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
                assert.are.same({ "maelstrom_weapon", "revelation" }, e.removed, field)
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
            { aura = "clearcasting", pct = -1, charges = 1, spells = { 403, 421, 8042, 8050, 408341 } },
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

    -- Convection (16039, aura 108 misc 14, -2% a rank on mask 0x90100003: Lightning Bolt, Chain
    -- Lightning, the shocks; not Lightning Shield), multiplied with Shamanistic Focus (wowsims's
    -- PowerCost_Pct rows multiply).
    it("takes 2% a rank of Convection off the elemental spells' cost, not Lightning Shield's", function()
        for _, key in ipairs({ "lightning_bolt", "chain_lightning", "earth_shock", "lightning_shield" }) do
            w.game.known[KIT[key][1][#KIT[key][1]]] = true
        end
        w.game.known[29228] = true
        local e = ld.env(w)
        e.talent.convection = { rank = 5, enabled = true }
        e.talent.shamanistic_focus = { rank = 1, enabled = true }
        assert.are.same({ 220 * 0.9, 495 * 0.9, 450 * 0.9 * 0.55, 410 * 0.9 * 0.55, 370 * 0.55 }, {
            ld.run(w.abilities.lightning_bolt.spend, e),
            ld.run(w.abilities.chain_lightning.spend, e),
            ld.run(w.abilities.earth_shock.spend, e),
            ld.run(w.abilities.flame_shock.spend, e),
            ld.run(w.abilities.lightning_shield.spend, e),
        })
    end)

    -- wowsims 4b0030a44b's spell data (spells_auto_gen.go Powers), every rank; the DB2's ladders (Chain Lightning 225..485,
    -- Mana Tide Totem 10/30/60/60) are wrong (owner rule 2026-11-06: wowsims over the DB2).
    it("costs every rank of Chain Lightning and Mana Tide Totem as wowsims's spell data", function()
        local e = ld.env(w)
        for key, costs in pairs({
            chain_lightning = { 245, 360, 425, 495 },
            mana_tide_totem = { 10, 20, 30, 60 },
        }) do
            local ids, got = KIT[key][1], {}
            for i = 1, #ids do
                for _, id in ipairs(ids) do
                    w.game.known[id] = false
                end
                w.game.known[ids[i]] = true
                got[i] = ld.run(w.abilities[key].spend, e)
            end
            assert.are.same(costs, got, key)
        end
    end)

    -- Elemental Alacrity (16578, aura 107 misc 10 on Lightning Bolt and Chain Lightning): Forever's trait
    -- curve, -170/-330/-500 ms (wowsims/forever's spell data; the DB2's Talent rows: -200 ms a rank of 5). Elemental
    -- Mastery (16166, wowsims's data, absent from the DB2): -500 ms on Lightning Bolt, -100% on Chain
    -- Lightning's cooldown, 15 s, 3 min.
    it(
        "shortens the casts with Elemental Alacrity and Elemental Mastery, which also lifts Chain Lightning's cooldown",
        function()
            for _, key in ipairs({ "lightning_bolt", "chain_lightning" }) do
                w.game.known[KIT[key][1][#KIT[key][1]]] = true
            end
            local function casts(e)
                local out = {}
                for _, key in ipairs({ "lightning_bolt", "chain_lightning" }) do
                    out[#out + 1] = math.floor(ld.run(w.abilities[key].cast, e) * 1000 + 0.5) / 1000
                end
                out[#out + 1] = ld.run(w.abilities.chain_lightning.cooldown, e)
                return out
            end
            local e = ld.env(w)
            assert.are.same({ 2.5, 2, 6 }, casts(e))
            e.talent.elemental_alacrity = { rank = 3, enabled = true }
            assert.are.same({ 2, 1.5, 6 }, casts(e))
            e.buff = buffs({ elemental_mastery = true })
            assert.are.same({ 1.5, 1.5, 0 }, casts(e))
            for _, field in ipairs({ "now", "handler" }) do
                e = ld.env(w)
                ld.run(w.abilities.elemental_mastery[field], e)
                assert.are.same({ "elemental_mastery" }, e.applied, field)
            end
            assert.are.same({ 16166, 15 }, { w.auras.elemental_mastery.id, w.auras.elemental_mastery.duration })
        end
    )

    -- Revelation (1323418, the weapon enchant 8217's Shaman buff; wowsims's data): one charge, 15 s, spent by the next
    -- spell its mask names (Lightning Bolt, Chain Lightning, Earth Shock; not Flame Shock).
    it("spends Revelation on Lightning Bolt, Chain Lightning and Earth Shock", function()
        assert.are.same({ 1323418, 15, 1 }, {
            w.auras.revelation.id,
            w.auras.revelation.duration,
            w.auras.revelation.max_stack,
        })
        for key, want in pairs({
            lightning_bolt = true,
            chain_lightning = true,
            earth_shock = true,
            flame_shock = false,
        }) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                e.setCooldown = function() end
                ld.run(w.abilities[key][field], e)
                local spent = false
                for _, k in ipairs(e.removed) do
                    spent = spent or k == "revelation"
                end
                assert.are.equal(want, spent, key .. " " .. field)
            end
        end
    end)

    -- Enchant IDs: DB2 70707 SpellEffect.EffectMiscValue_0 of each rank's Effect 360, lowest rank first (weapon buffs
    -- review §1); Rockbiter rank 2's 6 read in game (probe 2026-11-05, Shaman L10). 60 minutes: the tooltip and that
    -- probe (3578906 ms left at the first read), not the effect's 1800.
    local IMBUES = {
        rockbiter_weapon = { 29, 6, 1, 503, 1663, 683, 1664 },
        flametongue_weapon = { 5, 4, 3, 523, 1665, 1666 },
        windfury_weapon = { 283, 284, 525, 1669 },
        frostbrand_weapon = { 2, 12, 524, 1667, 1668 },
    }

    it("models each imbue on the main hand for its 60 minutes, replacing the others, as its own aura", function()
        for key, ids in pairs(IMBUES) do
            local aura, a = w.auras[key], w.abilities[key]
            assert.are.same({ ids, 3600, 1 }, { aura.enchants, aura.duration, aura.max_stack }, key)
            assert.is_nil(rawget(aura, "weaponEnchant"), key)
            -- upstream retail: prompted in combat from precombat while down, never while up
            assert.are.same({ true, key }, { a.essential, a.nobuff }, key)
            local others = {}
            for k in pairs(IMBUES) do
                if k ~= key then
                    others[#others + 1] = k
                end
            end
            table.sort(others)
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                ld.run(a[field], e)
                table.sort(e.removed)
                assert.are.same(others, e.removed, key)
                assert.are.same({ { key, "main_hand_enchant" }, 3600, 3600 }, {
                    e.applied,
                    e.durations[key],
                    e.durations.main_hand_enchant,
                }, key)
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
        -- Hekili_Shared's consumables, trinkets and racials (rule 13's); the engine's own list call
        local shared = {
            major_mana_potion = true,
            demonic_rune = true,
            use_items = true,
            call_action_list = true,
            blood_fury = true,
            berserking = true,
        }
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

    -- re-pin e2842f0a78: the build's own list (Water Shield, Magma and Windfury Totems, Fire Nova the filler)
    it(
        "tiers by role: the Maelstrom Lightning Bolt at 1, Water Shield and Flame Shock at 2, Fire Nova and totems none",
        function()
            local _, ws = line("default", "water_shield")
            local _, lb = line("single_target_rotation", "lightning_bolt")
            local _, fs = line("single_target_rotation", "flame_shock")
            local _, fn = line("single_target_rotation", "fire_nova")
            assert.are.same({ 2, 1, 2 }, { ws.focus, lb.focus, fs.focus })
            assert.is_nil(fn.focus)
            for _, key in ipairs({ "windfury_totem", "strength_of_earth_totem", "mana_spring_totem", "magma_totem" }) do
                local _, t = line("default", key)
                assert.is_nil(t.focus, key)
            end
        end
    )

    -- wowsims's autocast (rule 13) in the log's first-use order: the trinket (use_items), the Manual Crowd Pummeler
    -- (unmapped: the item swap's), Rage of the Farseer.
    it("casts Rage of the Farseer off the GCD right after the trinket, as wowsims's autocast does", function()
        local ui = line("default", "use_items")
        local i, e = line("default", "rage_of_the_farseer")
        assert.are.same({ ui + 1, nil }, { i, e.criteria })
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

    it(
        "resolves each totem buff by name and by its _totem alias to one aura, and an unknown totem buff stays unknown",
        function()
            local auras = H.Hekili.Class.auras
            for _, t in ipairs(TOTEM_AURAS) do
                local a = assert(auras[t[1]], t[1])
                assert.are.equal(a, auras[t[1] .. "_totem"], t[1])
                assert.are.equal(a, auras[t[3][1]], t[1])
                assert.are.equal(t[2], a.id, t[1])
            end
            assert.is_nil(auras.tremor_totem)
        end
    )

    it("reads a totem buff through the engine by either name without an error", function()
        local S = H.Hekili.State
        for _, k in ipairs({ "stoneskin_totem", "stoneskin", "windfury_totem", "flametongue", "mana_tide_totem" }) do
            assert.is_false(S.buff[k].up, k)
        end
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

    -- Weapon buffs review §4.2: the engine's buff.<imbue> and main_hand_enchant follow the belief's reads and models
    -- (the same answer in both layers), whatever the hand's temporary layer holds.
    it("answers the imbue auras alike in the belief and the engine: reads, a cast in combat, a swap", function()
        local VS, S, auras = H.ns.VirtualState, H.Hekili.State, H.Hekili.Class.auras
        local I = H.ns.VirtualStateInternal
        for _, k in ipairs({ "rockbiter_weapon", "flametongue_weapon", "windfury_weapon", "frostbrand_weapon" }) do
            local found -- every `enchants` aura crossed Build(def) with its IDs as plain numbers
            for _, rec in ipairs(I.def.auras) do
                found = rec.key == k and rec or found
            end
            assert.are.same(auras[k].enchants, assert(found, k).enchants)
            assert.is_nil(getmetatable(found.enchants))
        end
        local function same(t, want)
            S.reset("Primary", true)
            for k, up in pairs(want) do
                local rec = VS.Aura("player", auras[k].id, t)
                assert.are.equal(up, rec ~= nil, k)
                assert.are.equal(up, S.buff[k].up, k)
                if up then
                    assert.is_true(math.abs(S.buff[k].remains - (rec.est - t)) < 0.2, k)
                end
            end
        end
        local OIL = { hasEnchant = true, enchantType = 2, timeLeft = 900000, charges = 0, enchantID = 2628 }
        local NONE = { hasEnchant = false, enchantType = 0, timeLeft = 0, charges = 0, enchantID = 0 }
        local t = H.ctl.now + 1
        H.ctl.enchants[0] = { OIL, NONE } -- an oil alone: no imbue
        H.Fire("WEAPON_ENCHANT_CHANGED")
        assert.is_true(headless.cycle(H, t))
        same(t, { main_hand_enchant = false, rockbiter_weapon = false })
        H.ctl.enchants[0] =
            { OIL, { hasEnchant = true, enchantType = 3, timeLeft = 1700000, charges = 0, enchantID = 1664 } }
        H.Fire("WEAPON_ENCHANT_CHANGED")
        t = t + 1
        assert.is_true(headless.cycle(H, t))
        same(t, { main_hand_enchant = true, rockbiter_weapon = true, flametongue_weapon = false })
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        t = t + 1
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 16342) -- Flametongue in combat: modelled, replaces
        assert.is_true(headless.cycle(H, t + 0.1))
        same(t + 0.1, { main_hand_enchant = true, rockbiter_weapon = false, flametongue_weapon = true })
        H.ctl.enchants[0] = nil -- swapped for an unenchanted weapon in combat: read
        H.Fire("WEAPON_SLOT_CHANGED", 0)
        t = t + 1
        assert.is_true(headless.cycle(H, t))
        same(t, { main_hand_enchant = false, flametongue_weapon = false })
        assert.are.same({}, H.errors)
    end)

    -- Upstream's `essential`: a precombat imbue line is prompted in combat while the imbue is down, never while up.
    it("prompts an essential precombat imbue line in combat only while the main hand has no imbue", function()
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        local pack = H.Hekili.DB.profile.packs["Enhancement (wowsims.com)"]
        local line = { enabled = true, action = "rockbiter_weapon", criteria = "!buff.main_hand_enchant.up" }
        pack.lists = { precombat = { line }, default = {} }
        H.Hekili:LoadScripts()
        H.Hekili:ReviewPacks()
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        local t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        assert.are.equal("rockbiter_weapon", out.count > 0 and out.recs[1].actionName or false)
        H.ctl.enchants[0] =
            { { hasEnchant = true, enchantType = 3, timeLeft = 1700000, charges = 0, enchantID = 1664 } }
        H.Fire("WEAPON_ENCHANT_CHANGED")
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.equal(false, out.count > 0 and out.recs[1].actionName or false)
        assert.are.same({}, H.errors)
    end)

    it("recommends Rage of the Farseer in combat when ready, only with Cooldowns on", function()
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        -- the main hand's Flametongue up (rank 6, 1666), so the pack's need-based imbue line stays silent
        H.ctl.enchants[0] =
            { { hasEnchant = true, enchantType = 3, timeLeft = 3600000, charges = 0, enchantID = 1666 } }
        H.Fire("WEAPON_ENCHANT_CHANGED")
        -- and Water Shield up, so its line (R55: while the shield is down) stays silent
        H.ctl.auras.player.HELPFUL[1] =
            { spellId = H.Hekili.Class.auras.water_shield.id, expirationTime = H.ctl.now + 600, applications = 3 }
        H.Fire("UNIT_AURA", "player")
        -- and the build's four totems standing, so their refresh lines (remains<=2) stay silent too
        local A = H.Hekili.Class.abilities
        for slot, key in ipairs({ "magma_totem", "strength_of_earth_totem", "mana_spring_totem", "windfury_totem" }) do
            H.ctl.totems[slot] = { name = "", start = H.ctl.now, duration = 120, icon = 0, spell = A[key].id }
            H.Fire("PLAYER_TOTEM_UPDATE", slot)
        end
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
