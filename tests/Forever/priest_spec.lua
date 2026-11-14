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
    vampiric_embrace = { { 15286 }, 40, 30, "spell" }, -- 30 s (wowsims, DB2 70707)
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
    -- The heals and utility a Shadow or Discipline build can press (wowsims pin spell data; a percent-of-base cost as the fraction)
    lesser_heal = { { 2050, 2052, 2053 }, 75, 0, "spell" },
    heal_spell = { { 2054, 2055, 6063, 6064 }, 305, 0, "spell" },
    greater_heal = { { 2060, 10963, 10964, 10965, 25314 }, 710, 0, "spell" },
    flash_heal = { { 2061, 9472, 9473, 9474, 10915, 10916, 10917 }, 380, 0, "spell" },
    renew = { { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 }, 410, 0, "spell" },
    prayer_of_healing = { { 596, 996, 10960, 10961, 25316 }, 1070, 0, "spell" },
    prayer_of_mending = { { 401859, 1240826, 1240827 }, 390, 10, "spell" },
    psychic_scream = { { 8122, 8124, 10888, 10890 }, 210, 30, "spell" },
    fade_spell = { { 586, 9578, 9579, 9592, 10941, 10942 }, 275, 30, "spell" },
    mana_burn = { { 8129, 8131, 10874, 10875, 10876 }, 270, 0, "spell" },
    desperate_prayer = { { 13908, 19236, 19238, 19240, 19241, 19242, 19243 }, 0, 600, "spell" },
    dispel_magic = { { 527, 988 }, 0.18, 0, "spell" },
    cure_disease = { { 528 }, 0.15, 0, "spell" },
    abolish_disease = { { 552 }, 0.15, 0, "spell" },
    elunes_grace = { { 2651 }, 0.03, 300, "spell" },
    fear_ward = { { 6346 }, 100, 180, "spell" },
    feedback = { { 13896, 19271, 19273, 19274, 19275 }, 230, 180, "spell" },
    chastise = { { 1277331, 1277332, 1277333, 1277334, 1277335 }, 225, 120, "spell" },
    silence = { { 15487 }, 225, 45, "spell" },
    touch_of_weakness = { { 2652, 19261, 19262, 19264, 19265, 19266 }, 195, 0, "spell" },
    hex_of_weakness = { { 9035, 19281, 19282, 19283, 19284, 19285 }, 240, 0, "spell" },
    power_word_fortitude = { { 1243, 1244, 1245, 2791, 10937, 10938 }, 1695, 0, "spell" },
    prayer_of_fortitude = { { 21562, 21564 }, 3400, 0, "spell" },
    divine_spirit = { { 14752, 14818, 14819, 27841 }, 970, 0, "spell" },
    prayer_of_spirit = { { 27681 }, 1940, 0, "spell" },
    shadow_protection = { { 976, 10957, 10958 }, 650, 0, "spell" },
    shackle_undead = { { 9484, 9485, 10955 }, 150, 0, "spell" },
    resurrection = { { 2006, 2010, 10880, 10881, 20770 }, 0.75, 0, "spell" },
    mind_soothe = { { 453, 8192, 10953 }, 90, 0, "spell" },
    lightwell = { { 724, 27870, 27871 }, 365, 600, "spell" },
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

    -- The stat split (L971): Divine Spirit's Spirit by our known rank (wowsims spells_auto_gen.go aura 29, misc 4:
    -- 17/23/33/40), Spirit Tap's +100% (15271: aura 137, misc 4).
    it("declares Divine Spirit's Spirit part by our known rank and Spirit Tap's x2 (L971)", function()
        local e = ld.env(w)
        local ds = w.auras.divine_spirit.stats[5]
        assert.are.equal(17, ld.run(ds, e)) -- none known: the first rank's
        w.game.known[14819] = true
        assert.are.equal(33, ld.run(ds, e))
        w.game.known[27841] = true
        assert.are.equal(40, ld.run(ds, e))
        assert.are.same({ [5] = 2 }, w.auras.spirit_tap.statsPct)
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
        assert.are.equal(49, n)
        for _, key in ipairs({ "inner_focus", "power_infusion", "dark_sacrifice" }) do
            assert.are.equal("cooldowns", w.abilities[key].toggle, key)
        end
        assert.are.equal("defensives", w.abilities.power_word_shield.toggle)
    end)

    it("places every talent in its tree (Forever's)", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 0, 18, 17, 17 }, n) -- Forever's tree (trees/priest.json)
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
        -- the regen functions run under the stand-in's w.state, as the sim's: Spirit is UnitStat(5)'s second return
        local di, ds = r.models.dark_inspiration, r.models.dark_sacrifice
        assert.are.equal("dark_inspiration", di.aura)
        w.state.stat = function()
            return 0, 187
        end
        assert.is_true(math.abs(setfenv(di.spirit, w.state)() - (1 + 0.15 * 23.375 / 29.625)) < 1e-6) -- Spirit x 1.15 (+15% of 187/8)
        assert.are.same({ "dark_sacrifice", 3, 320 + 187 / 5 }, { ds.aura, ds.interval, setfenv(ds.value, w.state)() })
        w.state.stat = function()
            return 0, 0
        end
        assert.are.same({ 1, 320 }, { setfenv(di.spirit, w.state)(), setfenv(ds.value, w.state)() }) -- before the first stat read: inert, never NaN
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
                    139,
                    453,
                    527,
                    528,
                    552,
                    585,
                    586,
                    588,
                    589,
                    596,
                    724,
                    976,
                    1243,
                    2006,
                    2050,
                    2054,
                    2060,
                    2061,
                    2651,
                    2652,
                    2944,
                    6346,
                    8092,
                    8122,
                    8129,
                    9035,
                    9484,
                    10060,
                    10797,
                    13896,
                    14752,
                    14914,
                    15237,
                    15286,
                    15407,
                    15473,
                    15487,
                    18137,
                    21562,
                    27681,
                    401859,
                    402174,
                    1277331,
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

    it("prices the heals and utility by their talents: Soul Warding, Improved Healing, Mental Agility", function()
        local A = w.abilities
        for _, id in ipairs({
            10901,
            2053,
            6064,
            25314,
            10917,
            1316995,
            1240827,
            10890,
            10942,
            25316,
            10876,
            25315,
            10938,
        }) do
            w.game.known[id] = true
        end
        local e = ld.env(w)
        local function spend(key)
            return near(ld.run(A[key].spend, e))
        end
        assert.are.same({ 4, 500 }, { ld.run(A.power_word_shield.cooldown, e), spend("power_word_shield") })
        e.talent.soul_warding = { rank = 1 } -- PWS cooldown 4 -> 0 and -15% cost (DB2 402000 effects 0 and 1)
        assert.are.same({ 0, 425 }, { ld.run(A.power_word_shield.cooldown, e), spend("power_word_shield") })
        e.talent.mental_agility = { rank = 3 }
        assert.are.equal(382.5, spend("power_word_shield")) -- two cost mods multiply
        e.talent.improved_healing = { rank = 3 } -- -15%: Lesser Heal, Heal, Greater Heal, Penance, Prayer of Mending
        assert.are.same({ 63.75, 259.25, 603.5, 327.25, 298.35 }, {
            spend("lesser_heal"),
            spend("heal_spell"),
            spend("greater_heal"),
            spend("penance"),
            spend("prayer_of_mending"), -- 390 x 0.9 (Mental Agility, its mask) x 0.85
        })
        -- outside Improved Healing's mask, and outside Mental Agility's
        assert.are.same({ 380, 1070 }, { spend("flash_heal"), spend("prayer_of_healing") })
        e.talent.improved_healing = { rank = 1 }
        assert.are.equal(674.5, spend("greater_heal"))
        -- Mental Agility reaches the instants and Renew, Fade, Scream, never the hard-cast heals
        assert.are.same({ 247.5, 189, 369 }, { spend("fade_spell"), spend("psychic_scream"), spend("renew") })
        assert.are.equal(1695 * 0.9, ld.run(A.power_word_fortitude.spend, e))
        assert.are.equal(0.18 * 0.9, ld.run(A.dispel_magic.spend, e))
    end)

    it("times the heals by Divine Fury, Improved Mana Burn and Improved Psychic Scream", function()
        local A = w.abilities
        for _, id in ipairs({ 2053, 6064, 25314, 10917, 10876, 10890, 25316 }) do
            w.game.known[id] = true
        end
        local e = ld.env(w)
        e.haste = 1
        local function cast(key)
            return near(ld.run(A[key].cast, e))
        end
        assert.are.same({ 2.5, 3, 3, 1.5, 3, 3 }, {
            cast("lesser_heal"),
            cast("heal_spell"),
            cast("greater_heal"),
            cast("flash_heal"),
            cast("mana_burn"),
            cast("prayer_of_healing"),
        })
        e.talent.divine_fury = { rank = 5 } -- Heal and Greater Heal only (DB2 18530's mask)
        e.talent.improved_mana_burn = { rank = 2 }
        assert.are.same({ 2.5, 2.5, 2.5, 1.5, 2, 3 }, {
            cast("lesser_heal"),
            cast("heal_spell"),
            cast("greater_heal"),
            cast("flash_heal"),
            cast("mana_burn"),
            cast("prayer_of_healing"),
        })
        e.haste = 0.8
        assert.are.equal(2, cast("greater_heal"))
        assert.are.equal(30, ld.run(A.psychic_scream.cooldown, e))
        e.talent.improved_psychic_scream = { rank = 2 }
        assert.are.equal(26, ld.run(A.psychic_scream.cooldown, e)) -- DB2 15392: -4 s at the top rank (-2 s a rank: unverified)
    end)

    it(
        "registers each aura under every ID the Cooldown Manager links (the live export's), ranks and talent included",
        function()
            -- the export's linkedSpellIDs per item (tests/Forever/fixtures/cdm/priest.lua on cdm-fixture): the leaf maps an item
            -- when exactly one aura holds them all
            local LINKED = {
                prayer_of_mending = { 401877, 1240848, 1240849, 401859, 1240826, 1240827 },
                shackle_undead = { 9484, 9485, 10955, 1324415, 1324420, 1324422 },
                psychic_scream = { 8122, 8124, 10888, 10890 },
                silence = { 15487, 1324427 },
                fear_ward = { 6346 },
                power_word_fortitude = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564 },
                abolish_disease = { 552 },
                blessed_recovery = { 27811, 27813 },
                inspiration = { 14892, 14893 },
                holy_purpose = { 1284536 }, -- the export also links Searing Light 14909: left out (the translator reads an aura holding a talent ID as that talent)
                spirit_of_redemption = { 27827, 20711 },
                blackout = { 15326, 15269 },
                spirit_tap = { 15270, 15271 },
                shadow_weaving = { 15257, 15258 },
                focused_casting = { 27828 },
                divine_aegis = { 431622, 431624 },
                mind_soothe = { 453, 8192, 10953 },
                shadow_protection = { 976, 10957, 10958, 27683 },
                divine_spirit = { 14752, 14818, 14819, 27841, 27681 },
                touch_of_weakness = { 19252, 2943, 19254, 19253, 19249, 19251 },
            }
            for key, ids in pairs(LINKED) do
                local a = assert(w.auras[key], key)
                local have = idsOf(a)
                table.sort(have)
                table.sort(ids)
                assert.are.same(ids, have, key)
            end
        end
    )

    it("applies the self buffs the utility spells give, with the spell's own aura ID", function()
        local A = w.abilities
        for _, row in ipairs({
            { "fade_spell", "fade_buff", 586, 10 },
            { "elunes_grace", "elunes_grace", 2651, 15 },
            { "feedback", "feedback", 13896, 15 },
            { "touch_of_weakness", "touch_of_weakness", 2943, 120 },
            { "hex_of_weakness", "hex_of_weakness", 9035, 120 },
        }) do
            local key, aura = row[1], row[2]
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                ld.run(A[key][field], e)
                assert.are.same({ aura }, e.applied, key .. field)
            end
            assert.are.same({ row[3], row[4] }, { w.auras[aura].id, w.auras[aura].duration }, aura)
        end
        for _, key in ipairs({ "flash_heal", "renew", "prayer_of_healing" }) do
            assert.is_nil(A[key].handler, key) -- the ally's buff, not the player's: no assumption
            assert.is_false(A[key].startsCombat, key)
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

    -- Dark Inspiration (talent 1326159) is applied by a Mind Blast: 10 s, in the belief and the sim; without the talent
    -- none. Holy Purpose has no producer: it is up only when the aura read says so.
    it("applies Dark Inspiration on a Mind Blast with the talent, and Holy Purpose never", function()
        for rank, want in pairs({ [0] = false, [1] = true }) do
            local c = character()
            c.talents = { [1326159] = rank }
            local H = headless.new({ character = c })
            local I, VS, S = H.ns.VirtualStateInternal, H.ns.VirtualState, H.Hekili.State
            local t = H.ctl.now + 1
            assert.is_true(headless.cycle(H, t))
            VS.Drain(t)
            S.reset("Primary", true)
            assert.is_false(S.buff.dark_inspiration.up)
            H.ctl.now = t + 1
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-MB", 10947)
            assert.is_true(headless.cycle(H, t + 1.1))
            VS.Drain(t + 1.1)
            S.reset("Primary", true)
            assert.are.equal(want, S.buff.dark_inspiration.up, "belief, rank " .. rank)
            assert.is_false(S.buff.holy_purpose.up) -- no handler applies it: the aura read alone can
            assert.are.equal(0, I.nowErrors, tostring(I.nowError))
            assert.are.same({}, H.errors)
        end
    end)

    it("registers the utility auras: Fade, Renew, Elune's Grace, Fortitude, Divine Aegis", function()
        local _, w = character()
        local out = {}
        for _, k in ipairs({ "fade_buff", "renew", "elunes_grace", "power_word_fortitude", "divine_aegis" }) do
            out[#out + 1] = { w.auras[k].id, w.auras[k].duration }
        end
        assert.are.same({ { 586, 10 }, { 139, 15 }, { 2651, 15 }, { 1243, 3600 }, { 431624, 12 } }, out)
    end)

    it("Mind Blast's now and handler apply Dark Inspiration (10 s) under the talent only", function()
        local _, w = character()
        for _, field in ipairs({ "now", "handler" }) do
            local e = ld.env(w)
            e.talent.dark_inspiration = { rank = 1 }
            ld.run(w.abilities.mind_blast[field], e)
            assert.are.same({ "dark_inspiration" }, e.applied, field)
            e = ld.env(w)
            ld.run(w.abilities.mind_blast[field], e)
            assert.are.same({}, e.applied, field)
        end
        assert.are.same({ 1326168, 10 }, { w.auras.dark_inspiration.id, w.auras.dark_inspiration.duration })
    end)

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
        local kinds = {
            buff = cls.auras,
            debuff = cls.auras,
            cooldown = cls.abilities,
            action = cls.abilities,
            settings = cls.settings,
        }
        -- Hekili's `all` (Hekili_Shared): the trinket, the consumables, the race packs' Elune's Light and Eureka!
        local shared = {
            use_items = true,
            demonic_rune = true,
            major_mana_potion = true,
            elunes_light = true,
            eureka = true,
            berserking = true, -- rule 13's Troll racial
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
