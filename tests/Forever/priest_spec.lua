-- tests/Forever/priest_spec.lua: the Forever Priest class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb; the talents' per-rank values and the Forever-only nodes from wowsims/forever's data), loaded
-- headless through the recording stand-in (helpers/load_druid.lua with Priest.lua): the specs, the kit, the talents,
-- mana and Dark Sacrifice's, the channels, the cast times, the talents' costs and durations, the cost modifiers, the
-- lockouts; and the class through the real engine (headless.lua): every `now` in VirtualState's context, Shadowform as
-- a form and the cost modifiers in the belief and the simulation. What Hekili does with the rest is verified in game
-- (docs/dev/layout.md).
local ld = require("Forever.helpers.load_druid")
local headless = require("Game.harness.headless")

local FILE = "src/Hekili_Priest/Priest.lua"

-- key = { spell IDs in rank order, the top rank's mana cost (no talent, no aura), cooldown, gcd }, from the DB2
-- (`wowdb spell <name>`): the cooldown is the larger of RecoveryTime and CategoryRecoveryTime; a percent-of-base cost
-- (PowerCostPct) as the fraction the class file declares.
local KIT = {
    shadow_word_pain = { { 589, 594, 970, 992, 2767, 10892, 10893, 10894 }, 470, 0, "spell" },
    mind_blast = { { 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947 }, 350, 8, "spell" },
    mind_flay = { { 15407, 17311, 17312, 17313, 17314, 18807 }, 205, 0, "spell" },
    devouring_plague = { { 2944, 19276, 19277, 19278, 19279, 19280 }, 985, 24, "spell" }, -- wowsims's 24 s (DB2 60)
    shadow_word_death = { { 1309595, 1309633, 1309635, 1309636 }, 340, 18, "spell" }, -- wowsims's 18 s (DB2 15)
    vampiric_embrace = { { 15286 }, 40, 60, "spell" },
    shadowform = { { 15473 }, 0.4, 1.5, "spell" },
    shadowguard = { { 18137, 19308, 19309, 19310, 19311, 19312 }, 250, 0, "spell" },
    dark_sacrifice = { { 1277324, 1277325, 1277326, 1277327, 1277328 }, 0, 600, "spell" },
    starshards = { { 10797, 19296, 19299, 19302, 19303, 19304, 19305 }, 350, 30, "spell" },
    smite = { { 585, 591, 598, 984, 1004, 6060, 10933, 10934 }, 280, 0, "spell" },
    holy_fire = { { 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261 }, 255, 0, "spell" },
    penance = { { 402174, 1240720, 1240721, 1316995 }, 385, 12, "spell" },
    holy_nova = { { 15237, 15430, 15431, 27799, 27800, 27801 }, 750, 0, "spell" },
    power_word_shield = { { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 }, 500, 4, "spell" },
    inner_fire = { { 588, 7128, 602, 1006, 10951, 10952 }, 315, 0, "spell" },
    inner_focus = { { 14751 }, 0, 180, "off" },
    power_infusion = { { 10060 }, 0.2, 180, "off" },
    shoot = { { 5019 }, 0, 0, "off" },
}

local function idsOf(a)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
        out[#out + 1] = id
    end
    return out
end

local function near(x)
    return math.floor(x * 10000 + 0.5) / 10000
end

describe("Forever Priest", function()
    local w

    before_each(function()
        w = ld.load(nil, FILE, "PRIEST")
    end)

    it("declares Discipline and Shadow on trees 1 and 3 with their wowsims.com packs, Holy unsupported", function()
        assert.are.equal("PRIEST", w.class)
        local out = {}
        for _, s in ipairs(w.def.specs) do
            out[#out + 1] = { s.key, s.tree, s.role, s.ranged or false, s.unsupported or false, s.package or false }
        end
        assert.are.same({
            { "discipline", 1, "attack", true, false, "Smite (wowsims.com)" },
            { "holy", 2, "healer", false, true, false },
            { "shadow", 3, "attack", true, false, "Shadow (wowsims.com)" },
        }, out)
        assert.is_nil(w.options)
    end)

    it("registers the kit with the DB2's ranks, top-rank costs, cooldowns and GCDs", function()
        local n = 0
        for key, a in pairs(w.abilities) do
            n = n + 1
            local want = assert(KIT[key], "unexpected ability " .. key)
            local ids = want[1]
            for _, id in ipairs(ids) do
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
        assert.are.equal(19, n)
        for _, key in ipairs({ "inner_focus", "power_infusion", "dark_sacrifice" }) do
            assert.are.equal("cooldowns", w.abilities[key].toggle, key)
        end
        assert.are.equal("defensives", w.abilities.power_word_shield.toggle)
    end)

    it("places every DB2 talent in its tree and the Forever-only ones in wowsims's", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        -- the DB2's 15 / 16 / 16, and 7 / 3 / 4 Forever-only nodes
        assert.are.same({ [0] = 0, 22, 19, 20 }, n)
        assert.are.same({ 1, 402174, 1 }, w.talents.penance)
        assert.are.same({ 3, 1309950, 2 }, w.talents.devouring_contagion)
    end)

    it("declares mana per spec as wowsims's logs, base 1376, Dark Inspiration's Spirit and Dark Sacrifice's", function()
        assert.are.same({ 0 }, w.order)
        local r, e = w.resources[0], ld.env(w)
        local function seed(key)
            w.state.spec = { [key] = true } -- the pack's functions read state.spec (the file's `spec` is the class)
            return { ld.run(r.meta.fsr.spirit, e), ld.run(r.meta.fsr.mp5, e), ld.run(r.meta.fsr.share, e) or 0 }
        end
        assert.are.same({ 14.79, 26.88, 0.5 }, seed("shadow")) -- Meditation's 50%, before Dark Inspiration
        assert.are.same({ 20.12, 35.73, 0 }, seed("discipline")) -- the Smite build's
        assert.are.equal(1376, r.meta.base)
        -- the regen functions read the file's `state` (the stand-in's w.state): Spirit is UnitStat(5)'s second return
        local di, ds = r.models.dark_inspiration, r.models.dark_sacrifice
        assert.are.equal("dark_inspiration", di.aura)
        w.state.stat = function()
            return 0, 187
        end
        assert.is_true(math.abs(di.spirit() - (1 + 0.15 * 23.375 / 29.625)) < 1e-6) -- Spirit x 1.15 (+15% of 187/8)
        assert.are.same({ "dark_sacrifice", 3, 320 + 187 / 5 }, { ds.aura, ds.interval, ds.value() })
        w.state.stat = function()
            return 0, 0
        end
        assert.are.same({ 1, 320 }, { di.spirit(), ds.value() }) -- before the first stat read: inert, never NaN
        w.state.query_time, w.state.buff.dark_sacrifice = 17.4, { applied = 10.2 }
        assert.is_true(math.abs(ds.last() - 16.2) < 1e-9) -- the last 3 s tick since the aura's application
    end)

    it("channels Mind Flay (3 s), Starshards (6 s), Penance (2 s), a tick a second, and Shoot a wand speed", function()
        local A, out, ranged = w.abilities, {}, 0
        w.state.stat = function(name) -- the belief's stat read (Families/Player.lua VS.Stat)
            return name == "UnitRangedDamage" and ranged or 0
        end
        local e = ld.env(w)
        e.haste = 1
        for _, key in ipairs({ "mind_flay", "starshards", "penance", "shoot" }) do
            local a = A[key]
            out[#out + 1] = { key, a.channeled, ld.run(a.cast, e), ld.run(a.tick_time, e) }
            assert.is_nil(a.handler, key) -- a channel's handler never runs in Hekili's simulation
            for _, field in ipairs({ "now", "start" }) do
                local f = ld.env(w)
                ld.run(a[field], f)
                assert.are.same({ key }, f.applied, key .. field)
            end
        end
        assert.are.same({
            { "mind_flay", true, 3, 1 },
            { "starshards", true, 6, 1 },
            { "penance", true, 2, 1 },
            { "shoot", true, 1.2, 1.2 }, -- the Smite build's wand before a ranged read
        }, out)
        ranged, e.haste = 1.5, 0.8
        assert.are.same(
            { 1.5, 2.4, 0.8 },
            { ld.run(A.shoot.cast, e), near(ld.run(A.mind_flay.cast, e)), ld.run(A.mind_flay.tick_time, e) }
        )
        assert.are.equal(3, w.auras.mind_flay.duration)
        -- Shoot's target aura lasts its one shot, a wand speed (the world's), never the 3600 s of a lasting aura
        assert.are.equal(1.2, w.auras.shoot.duration)
        for _, r in ipairs({ 0, 1.5 }) do
            ranged = r
            for _, field in ipairs({ "now", "start" }) do
                local f = ld.env(w)
                ld.run(A.shoot[field], f)
                assert.are.equal(r > 0 and r or 1.2, f.durations.shoot, field)
            end
        end
    end)

    it("times the hard casts: Mind Blast 1.5 s, Smite by rank, Holy Fire 3.5 s; Divine Fury -0.1 s a rank", function()
        local A = w.abilities
        w.game.known[10934] = true
        local e = ld.env(w)
        e.haste = 1
        assert.are.same(
            { 1.5, 2.5, 3.5 },
            { ld.run(A.mind_blast.cast, e), ld.run(A.smite.cast, e), ld.run(A.holy_fire.cast, e) }
        )
        e.talent.divine_fury = { rank = 5 }
        assert.are.same({ 2, 3 }, { near(ld.run(A.smite.cast, e)), near(ld.run(A.holy_fire.cast, e)) })
        w.game.known[10934], w.game.known[585] = false, true
        assert.are.equal(1, near(ld.run(A.smite.cast, e))) -- rank 1's 1.5 s
        e.haste = 0.8
        assert.are.equal(0.8, near(ld.run(A.smite.cast, e)))
        for _, key in ipairs({ "shadow_word_pain", "devouring_plague", "shadow_word_death", "holy_nova" }) do
            assert.are.equal(0, A[key].cast, key)
        end
    end)

    it("cuts costs by Mental Agility (3 / 7 / 10%) on its mask and Devouring Contagion (25 / 50%)", function()
        local A = w.abilities
        for _, id in ipairs({ 10934, 15261, 10894, 19280, 10947, 1316995 }) do
            w.game.known[id] = true
        end
        local e = ld.env(w)
        e.talent.mental_agility = { rank = 3 }
        -- wowsims's Smite log: Smite 252, Holy Fire 229.5, Shadow Word: Pain 423; Mind Blast and Penance outside it
        assert.are.same({ 252, 229.5, 423, 0.18, 350, 385 }, {
            near(ld.run(A.smite.spend, e)),
            near(ld.run(A.holy_fire.spend, e)),
            near(ld.run(A.shadow_word_pain.spend, e)),
            near(ld.run(A.power_infusion.spend, e)),
            ld.run(A.mind_blast.spend, e),
            ld.run(A.penance.spend, e),
        })
        local dp = {}
        for rank = 1, 3 do
            e.talent.mental_agility = { rank = rank }
            dp[#dp + 1] = near(ld.run(A.devouring_plague.spend, e))
        end
        assert.are.same({ 955.45, 916.05, 886.5 }, dp)
        e.talent.mental_agility = { rank = 0 }
        e.talent.devouring_contagion = { rank = 2 }
        assert.are.equal(492.5, ld.run(A.devouring_plague.spend, e)) -- wowsims's Shadow log: 246.25 in Shadowform
        e.talent.mental_agility = { rank = 5 } -- past wowsims's three: its last
        assert.are.equal(0.36, near(ld.run(A.shadowform.spend, e)))
    end)

    it(
        "shortens Mind Blast's cooldown by Improved Mind Blast and lengthens Shadow Word: Pain's by its talent",
        function()
            local e, mb, out = ld.env(w), w.abilities.mind_blast, {}
            for rank = 0, 5 do
                e.talent.improved_mind_blast = { rank = rank }
                out[#out + 1] = ld.run(mb.cooldown, e)
            end
            assert.are.same({ 8, 7.5, 7, 6.5, 6, 5.5 }, out)
            local swp = w.abilities.shadow_word_pain
            for rank = 0, 2 do
                for _, field in ipairs({ "now", "handler" }) do
                    local f = ld.env(w)
                    f.talent.improved_shadow_word_pain = { rank = rank }
                    ld.run(swp[field], f)
                    assert.are.same(
                        { { "shadow_word_pain" }, 18 + 3 * rank },
                        { f.applied, f.durations.shadow_word_pain }
                    )
                    assert.are.equal(18 + 3 * rank, ld.run(w.auras.shadow_word_pain.duration, f))
                end
            end
        end
    )

    it("puts the DoTs on the target from the casts, and the self buffs with their charges", function()
        local A = w.abilities
        for key, aura in pairs({ devouring_plague = 24, holy_fire = 10, vampiric_embrace = 30 }) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                ld.run(A[key][field], e)
                assert.are.same({ key }, e.applied, key .. field)
            end
            assert.are.equal(aura, w.auras[key].duration, key)
        end
        for key, n in pairs({ shadowguard = 3, inner_fire = 20 }) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                ld.run(A[key][field], e)
                assert.are.same({ key }, e.applied, key .. field)
            end
            assert.are.equal(n, w.auras[key].max_stack, key)
        end
        assert.are.same({ 15473, "shadowform" }, { w.auras.shadowform.id, A.shadowform.nobuff })
        assert.are.same({ 1284536, 10 }, { w.auras.holy_purpose.id, w.auras.holy_purpose.duration })
        assert.is_nil(w.auras.power_infusion) -- Hekili_Shared's (`shared = "player"`)
    end)

    it("declares Shadowform, Inner Focus and Holy Purpose as cost modifiers on the DB2 masks' spells", function()
        local by = {}
        for _, m in ipairs(w.costMods) do
            local spells = {}
            for _, id in ipairs(m.spells) do
                spells[#spells + 1] = id
            end
            table.sort(spells)
            by[m.aura] = { m.pct, m.charges or false, spells }
        end
        assert.are.same({
            shadowform = { -0.5, false, { 589, 2944, 8092, 15286, 15407, 15473, 18137, 1309595 } },
            inner_focus = {
                -1,
                1,
                {
                    17,
                    585,
                    588,
                    589,
                    2944,
                    8092,
                    10060,
                    10797,
                    14914,
                    15237,
                    15286,
                    15407,
                    15473,
                    18137,
                    402174,
                    1309595,
                },
            },
            holy_purpose = { -1, 1, { 15237 } },
        }, by)
    end)

    it("refuses each spell while an interrupt has its school locked out", function()
        local SCHOOL = {
            shadow_word_pain = "shadow",
            mind_blast = "shadow",
            mind_flay = "shadow",
            devouring_plague = "shadow",
            shadow_word_death = "shadow",
            vampiric_embrace = "shadow",
            dark_sacrifice = "shadow",
            starshards = "arcane",
            smite = "holy",
            holy_fire = "holy",
            penance = "holy",
            holy_nova = "holy",
        }
        for key, school in pairs(SCHOOL) do
            local e = ld.env(w)
            assert.is_true((ld.run(w.abilities[key].usable, e)), key)
            e["locked_out_" .. school] = true
            assert.is_false((ld.run(w.abilities[key].usable, e)), key)
        end
    end)
end)

-- Through the real engine (headless.lua): a Priest who knows the whole kit.
describe("Forever Priest through the engine", function()
    local function character(o)
        local w = ld.load(nil, FILE, "PRIEST")
        local known = {}
        for _, a in pairs(w.abilities) do
            for _, id in ipairs(idsOf(a)) do
                known[#known + 1] = id
            end
        end
        return {
            class = "PRIEST",
            classID = 5,
            specID = 1487,
            level = 60,
            known = known,
            talents = {},
            power = { type = 0, token = "MANA", max = 6000, value = 6000 },
            speed = { 3 },
            forms = o and o.forms,
            form = o and o.form,
        },
            w
    end

    it(
        "loads the kit on our spec ids and runs every declared `now` in VirtualState's context without an error",
        function()
            local H = headless.new({ character = character() })
            assert.are.same({}, H.loadErrors)
            local specs = H.Hekili.Class.specs
            assert.are.same(
                { "discipline", "holy", "shadow", true },
                { specs[100051].key, specs[100052].key, specs[100053].key, specs[100052].unsupported }
            )
            assert.are.equal(15473, H.Hekili.Class.auras.shadowform.id) -- the class's, over Hekili_Shared's id-less stub
            local _, w = character()
            local I = H.ns.VirtualStateInternal
            local runs0, t, n = I.nowRuns, H.ctl.now, 0
            for _, a in pairs(w.abilities) do
                if a.now then
                    t, n = t + 1, n + 1
                    H.ctl.now = t
                    H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, a.id)
                    assert.is_true(headless.cycle(H, t + 0.1))
                    H.ns.VirtualState.Drain(t + 0.1) -- no priority yet: Hekili.Update idles before its drain
                end
            end
            assert.are.same({ 0, n }, { I.nowErrors, I.nowRuns - runs0 }, tostring(I.nowError))
            assert.are.same({}, H.errors)
        end
    )

    -- Shadowform is a form (core's form reads), and its -50% reaches Mind Blast in both layers; Inner Focus's charge
    -- makes the next one free and is spent by it.
    it(
        "halves the Shadow costs in Shadowform and frees the spell after Inner Focus, in the belief and the sim",
        function()
            local H = headless.new({ character = character({ forms = { 15473 }, form = 1 }) })
            local I, VS, S = H.ns.VirtualStateInternal, H.ns.VirtualState, H.Hekili.State
            local mb, smite = I.ab.bySpell[8092], I.ab.bySpell[585]
            local function at(t)
                assert.is_true(headless.cycle(H, t))
                VS.Drain(t)
                S.reset("Primary", true)
            end
            local t = H.ctl.now + 1
            at(t)
            assert.are.same(
                { true, 175, 175, 280, 280 },
                { S.buff.shadowform.up, I.CostOf(mb), S.action.mind_blast.cost, I.CostOf(smite), S.action.smite.cost }
            )
            t = t + 1
            H.ctl.now = t
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-IF", 14751)
            at(t + 0.1)
            assert.are.same({ true, 0, 0 }, { S.buff.inner_focus.up, I.CostOf(mb), S.action.mind_blast.cost })
            t = t + 1
            H.ctl.now = t
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-MB", 10947)
            at(t + 0.1)
            assert.are.same({ false, 175 }, { S.buff.inner_focus.up, I.CostOf(mb) })
            assert.are.same({}, H.errors)
        end
    )
end)

-- The priorities: the wowsims.com packs (generated from wowsims/forever's Priest builds by `make wowsims-packs`).
describe("Forever Priest priorities", function()
    it("keeps the class file's generated blocks in step with APLs/", function()
        local mp = assert(loadfile("tools/make_pack.lua"))("lib")
        local f = assert(io.open(FILE))
        local src = f:read("*a")
        f:close()
        assert.are.equal(src, (mp.sync(src, mp.load("priest"))))
    end)

    it("names only registered abilities and auras", function()
        local cls = ld.load(nil, FILE, "PRIEST")
        local kinds = { buff = cls.auras, debuff = cls.auras, cooldown = cls.abilities, action = cls.abilities }
        -- Hekili's `all` (Hekili_Shared): the trinket, the consumables, the race packs' Elune's Light and Eureka!
        local shared = {
            use_items = true,
            demonic_rune = true,
            major_mana_potion = true,
            elunes_light = true,
            eureka = true,
            call_action_list = true,
        }
        for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", "priest")) do
            for list, entries in pairs(p.lists) do
                for i, e in ipairs(entries) do
                    local where = p.name .. " " .. list .. " " .. i
                    assert.is_true(cls.abilities[e.action] ~= nil or shared[e.action], where)
                    for kind, key in (e.criteria or ""):gmatch("(%a+)%.([%w_]+)") do
                        if kinds[kind] then
                            assert.is_true(kinds[kind][key] ~= nil or shared[key] ~= nil, where .. ": " .. key)
                        end
                    end
                end
            end
        end
    end)
end)
