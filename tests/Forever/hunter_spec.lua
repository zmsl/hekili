-- tests/Forever/hunter_spec.lua: the Forever Hunter class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through the recording stand-in (helpers/load_druid.lua with Hunter.lua), its
-- handlers and `now` lines (the aspects, the target's debuffs, the shared cooldowns, Summon Hawk's guardians, Raptor
-- Strike's queue, Mongoose Bite's window, the ranged casts), the focus lines, and the class through the real engine
-- (headless.lua): every `now` in VirtualState's context, the hawks counted in the belief and the simulation, the
-- ranged clock after a modelled Auto Shot. What Hekili does with the rest is verified in game (docs/dev/layout.md).
local ld = require("Forever.helpers.load_druid")
local ws = require("Forever.helpers.wowsims")
local headless = require("Game.harness.headless")

local FILE = "src/Hekili_Hunter/Hunter.lua"
local TOC_SHARED = "src/Hekili_Shared/Hekili_Shared.toc"

-- key = { spell IDs in rank order, the top rank's mana cost, cooldown, gcd }, from the DB2 (`wowdb spell <name>`): the
-- cooldown is the larger of RecoveryTime and CategoryRecoveryTime; a percent-of-base-mana cost (PowerCostPct) as the
-- fraction the class file declares.
local KIT = {
    auto_shot = { { 75 }, 0, 0, "off" },
    hunters_mark = { { 1130, 14323, 14324, 14325, 1213268 }, 60, 0, "spell" },
    aspect_of_the_hawk = { { 13165, 14318, 14319, 14320, 14321, 14322, 25296 }, 120, 0, "spell" },
    aspect_of_the_beast = { { 13161, 1299445, 1299446, 1299447 }, 110, 0, "spell" },
    aspect_of_the_cheetah = { { 5118 }, 40, 0, "spell" },
    rapid_fire = { { 3045 }, 100, 300, "off" },
    -- the BM talent (19574): its pet's 18 s rage, autocast as a major cooldown in wowsims's BM log
    bestial_wrath = { { 19574 }, 0.12, 120, "off" }, -- 12% of base mana (the pin's row CostPct 12; the DB2 had it free)
    serpent_sting = { { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 }, 250, 0, "spell" },
    -- 11% of base mana at every rank (wowsims e4ef929e54's spell data, CostPct 11; was 25-190 by rank)
    arcane_shot = { { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 }, 0.11, 6, "spell" },
    summon_hawk = { { 1293241, 1293525, 1293526, 1293527 }, 0.11, 6, "spell" },
    aimed_shot = { { 19434, 20900, 20901, 20902, 20903, 20904 }, 310, 6, "spell" },
    multi_shot = { { 2643 }, 0.139, 6, "spell" },
    sniper_shot = { { 1310687, 1310785, 1310786 }, 365, 15, "spell" },
    raptor_strike = { { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 }, 100, 6, "off" },
    mongoose_bite = { { 1495, 14269, 14270, 14271 }, 65, 5, "spell" },
    strider_kick = { { 1317257 }, 0.0581, 8, "spell" },
    wing_clip = { { 2974, 1310180, 14267, 14268 }, 80, 0, "spell" },
    -- wowsims's Melee Weave casts it in melee range (category cooldown 30 s, SpellCooldowns)
    immolation_trap = { { 13795, 14302, 14303, 14304, 14305 }, 245, 30, "spell" },
    -- Lane A (coverage): the pin's sim/hunter/spell_data_auto_gen.go ladders with spells_auto_gen.go's rows (cost, cooldown,
    -- GCD); Forever's own Freezing Trap rows (1324500-2) come first, as the CDM links them (cdm/hunter.lua)
    explosive_trap = { { 13813, 14316, 14317 }, 520, 30, "spell" },
    freezing_trap = { { 1324500, 1324501, 1324502, 1499, 14310, 14311 }, 100, 30, "spell" },
    frost_trap = { { 13809 }, 60, 30, "spell" },
    scorpid_sting = { { 3043 }, 0.09, 0, "spell" },
    viper_sting = { { 3034, 14279, 14280 }, 215, 15, "spell" },
    concussive_shot = { { 5116 }, 0.08, 12, "spell" },
    scatter_shot = { { 19503 }, 0.08, 30, "spell" },
    intimidation = { { 19577 }, 0.08, 60, "spell" },
    counterattack = { { 19306, 1242634, 20909, 20910 }, 85, 5, "spell" },
    deterrence = { { 19263 }, 0, 300, "off" },
    disengage = { { 781, 14272, 14273 }, 150, 5, "spell" },
    feign_death = { { 5384 }, 80, 30, "off" },
    flare = { { 1543 }, 50, 15, "spell" },
    distracting_shot = { { 20736, 14274, 15629, 15630, 15631, 15632 }, 110, 8, "spell" },
    tranquilizing_shot = { { 19801 }, 270, 20, "spell" },
    volley = { { 1510, 14294, 14295 }, 490, 0, "spell" },
    scare_beast = { { 1513, 14326, 14327 }, 75, 30, "spell" },
    trueshot_aura = { { 1299346, 1299348, 19506, 20905, 20906 }, 525, 0, "spell" },
    mend_pet = { { 136, 3111, 3661, 3662, 13542, 13543, 13544 }, 480, 0, "spell" },
    aspect_of_the_monkey = { { 13163 }, 20, 0, "spell" },
    aspect_of_the_pack = { { 13159 }, 100, 0, "spell" },
    aspect_of_the_wild = { { 20043, 20190 }, 115, 0, "spell" },
    aspect_of_the_viper = { { 415423 }, 0, 0, "spell" },
    -- L1059: the pet's calls (the pin's rows: Call Pet free and instant; Revive Pet 100% of base mana, 10 s cast)
    call_pet = { { 883 }, 0, 0, "spell" },
    revive_pet = { { 982 }, 1, 0, "spell" },
}

-- one aspect at a time: each cast takes every other aspect down, in this order
local ASPECTS = {
    "aspect_of_the_hawk",
    "aspect_of_the_beast",
    "aspect_of_the_cheetah",
    "aspect_of_the_monkey",
    "aspect_of_the_pack",
    "aspect_of_the_wild",
    "aspect_of_the_viper",
}
local function OTHER_ASPECTS(key)
    local out = {}
    for _, k in ipairs(ASPECTS) do
        if k ~= key then
            out[#out + 1] = k
        end
    end
    return out
end

local function idsOf(a)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
        out[#out + 1] = id
    end
    return out
end

-- Ability `a`'s declared cost in env `e` (class load `w`) under the class file's talent-gated cost modifiers
-- (RegisterCostMod `talent`, no aura) in scope at e's ranks, each a factor (two SPELLMOD_COST pct rows multiply:
-- wowsims spell_mod.go SpellMod_PowerCost_Pct). The engine's own pricing is checked in both layers below ("prices
-- Efficiency's cut on the whole cost in both layers").
local function cutCost(w, a, e)
    local c, ids = ld.run(a.spend, e), idsOf(a)
    for _, m in ipairs(w.costMods) do
        local rank = m.talent and e.talent[m.talent].rank or 0
        local hit = m.spells == nil
        for _, s in ipairs(m.spells or {}) do
            for _, id in ipairs(ids) do
                hit = hit or s == id
            end
        end
        if m.aura == nil and rank > 0 and hit then
            c = c * (1 + (type(m.pct) == "table" and m.pct[rank] or m.pct))
        end
    end
    return c
end

-- `buff` with the keys in `up` up.
local function buffs(up)
    return setmetatable({}, {
        __index = function(_, k)
            return { up = up[k] == true, stack = up[k] and 1 or 0, remains = up[k] and 10 or 0 }
        end,
    })
end

describe("Forever Hunter", function()
    local w

    before_each(function()
        w = ld.load(nil, FILE, "HUNTER")
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
        assert.are.equal(43, n)
        assert.are.equal("HUNTER", w.class)
        assert.is_nil(w.options)
        assert.are.equal("cooldowns", w.abilities.rapid_fire.toggle)
        assert.are.equal("cooldowns", w.abilities.bestial_wrath.toggle)
    end)

    it("places every talent in a tree (Forever's)", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 0, 16, 16, 18 }, n) -- Forever's tree (trees/hunter.json)
    end)

    it("declares mana as wowsims's logs measure it per spec, and the two casting shares", function()
        assert.are.same({ 0 }, w.order)
        local r, e = w.resources[0], ld.env(w)
        local function seed(key)
            w.state.spec = { [key] = true } -- the pack's functions read state.spec (the file's `spec` is the class)
            return { ld.run(r.meta.fsr.spirit, e), ld.run(r.meta.fsr.mp5, e), ld.run(r.meta.fsr.share, e) or 0 }
        end
        assert.are.same({ 8.75, 24.15, 0 }, seed("beast_mastery"))
        assert.are.same({ 17.5, 15.4, 0 }, seed("marksmanship"))
        assert.are.same({ 17.5, 15.4, 0 }, seed("survival"))
        -- the static share follows Bestial Discipline's rank (25/50%, wowsims's curve), never the spec
        local shares = {}
        for rank = 0, 2 do
            e.talent.bestial_discipline = { rank = rank }
            shares[#shares + 1] = ld.run(r.meta.fsr.share, e)
        end
        assert.are.same({ 0, 0.25, 0.5 }, shares)
        assert.are.same({ aura = "resourcefulness", share = 0.5 }, r.models.resourcefulness)
        assert.are.same("rapid_recuperation", r.models.rapid_recuperation.aura)
        assert.are.same(1242688, w.auras.resourcefulness.id)
        assert.are.same(1242512, w.auras.rapid_recuperation.id)
        assert.are.same({ 2, 1223987, 2 }, w.talents.rapid_recuperation)
    end)

    -- Rapid Recuperation (1223987, wowsims talents_marksmanship.go): 25/50% of the spirit regen while casting by rank for
    -- 15 s when a Serpent Sting lands (the listener needs no damage); the belief opens it at the cast
    it("opens Rapid Recuperation at a Serpent Sting, its casting share 25/50% by rank", function()
        local rr = w.resources[0].models.rapid_recuperation
        local got = {}
        for rank = 0, 2 do
            local e = ld.env(w)
            e.talent.rapid_recuperation = { rank = rank }
            ld.run(w.abilities.serpent_sting.now, e)
            got[#got + 1] = { ld.run(rr.share, e), #e.applied }
        end
        assert.are.same({ { 0, 1 }, { 0.25, 2 }, { 0.5, 2 } }, got) -- the sting's dot, and the buff once talented
    end)

    -- shortcut (Hunter.lua stings()): a missed sting keeps the buff, as no landed signal reaches it on live; a landed
    -- signal that fixes this changes this expectation on purpose
    it("keeps Rapid Recuperation in the belief on a missed Serpent Sting (the named over-count)", function()
        local e = ld.env(w)
        e.talent.rapid_recuperation = { rank = 2 }
        ld.run(w.abilities.serpent_sting.now, e) -- the cast; no landed signal follows on a miss
        assert.are.same(2, #e.applied)
        assert.are.same(0.5, ld.run(w.resources[0].models.rapid_recuperation.share, e))
    end)

    -- Resourcefulness (440529 2/2, wowsims talents_survival.go): a melee or ranged ability's crit (proc flags 0x110: not a
    -- white swing or Auto Shot) gives its 30 s buff, 50/100% by rank; the owner's rule assumes it at 2/2 only. The crit
    -- reaches the belief by kind, flag and school with its amount secret (Rows.lua, D1): the ability's `onCrit`.
    it("opens Resourcefulness at a melee or ranged ability's crit at 2/2", function()
        local A = w.abilities
        for _, key in ipairs({
            "arcane_shot",
            "aimed_shot",
            "multi_shot",
            "sniper_shot",
            "raptor_strike",
            "mongoose_bite",
            "strider_kick",
            "wing_clip",
        }) do
            for rank = 1, 2 do
                local e = ld.env(w)
                e.talent.resourcefulness = { rank = rank }
                assert.is_function(A[key].onCrit, key)
                ld.run(A[key].onCrit, e)
                assert.are.same(rank == 2 and { "resourcefulness" } or {}, e.applied, key .. " rank " .. rank)
            end
        end
        assert.is_nil(A.auto_shot.onCrit)
    end)

    -- Survivalist's Discipline (1310496, curve {-20, -40} %, PCT on the cooldown: its mask is every trap placement and
    -- Deterrence, talents_survival.go:135) and Improved Stings (1310661: Viper Sting -2/-4/-6 s, mask 1:128).
    it(
        "cuts the traps' and Deterrence's cooldown by Survivalist's Discipline, Viper Sting's by Improved Stings",
        function()
            local e = ld.env(w)
            local function cd(key, talent, rank)
                e.talent[talent] = { rank = rank, enabled = rank > 0 }
                return math.floor(ld.run(w.abilities[key].cooldown, e) * 1000 + 0.5) / 1000
            end
            for _, key in ipairs({ "immolation_trap", "explosive_trap", "freezing_trap", "frost_trap" }) do
                assert.are.same({ 30, 24, 18 }, {
                    cd(key, "survivalists_discipline", 0),
                    cd(key, "survivalists_discipline", 1),
                    cd(key, "survivalists_discipline", 2),
                }, key)
            end
            assert.are.same({ 300, 240, 180 }, {
                cd("deterrence", "survivalists_discipline", 0),
                cd("deterrence", "survivalists_discipline", 1),
                cd("deterrence", "survivalists_discipline", 2),
            })
            assert.are.same({ 15, 13, 11, 9 }, {
                cd("viper_sting", "improved_stings", 0),
                cd("viper_sting", "improved_stings", 1),
                cd("viper_sting", "improved_stings", 2),
                cd("viper_sting", "improved_stings", 3),
            })
        end
    )

    it("puts every trap on one 30 s category cooldown (shortened by Survivalist's Discipline)", function()
        local traps = { "immolation_trap", "explosive_trap", "freezing_trap", "frost_trap" }
        for _, me in ipairs(traps) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                e.talent.survivalists_discipline = { rank = 2, enabled = true }
                ld.run(w.abilities[me][field], e)
                local got = {}
                for _, c in ipairs(e.cooldowns) do
                    got[c[1]] = c[2]
                end
                for _, other in ipairs(traps) do
                    assert.are.equal(other ~= me and 18 or nil, got[other], me .. " " .. field .. " -> " .. other)
                end
            end
        end
    end)

    it(
        "prices the new shots, stings and traps under Efficiency and Resourcefulness, Mend Pet under Improved Mend Pet",
        function()
            for key, want in pairs(KIT) do
                if key ~= "bestial_wrath" then
                    w.game.known[want[1][#want[1]]] = true
                end
            end
            local e = ld.env(w)
            local function price(key, res, eff, mend)
                e.talent.resourcefulness = { rank = res, enabled = res > 0 }
                e.talent.efficiency = { rank = eff, enabled = eff > 0 }
                e.talent.improved_mend_pet = { rank = mend or 0, enabled = (mend or 0) > 0 }
                return math.floor(cutCost(w, w.abilities[key], e) * 100000 + 0.5) / 100000
            end
            -- Efficiency's mask (19416, 5/5 = -15%): the stings, Concussive, Scatter, Distracting, Tranquilizing, Counterattack,
            -- Volley; Sniper Shot (wowsims's MM logs: 321.2 of 365 under 4/5); not the traps
            for key, want in pairs({
                sniper_shot = { 365, 310.25 },
                viper_sting = { 215, 182.75 },
                scorpid_sting = { 0.09, 0.0765 },
                concussive_shot = { 0.08, 0.068 },
                scatter_shot = { 0.08, 0.068 },
                distracting_shot = { 110, 93.5 },
                volley = { 490, 416.5 },
                tranquilizing_shot = { 270, 229.5 },
                counterattack = { 85, 72.25 },
                explosive_trap = { 520, 520 },
                freezing_trap = { 100, 100 },
                frost_trap = { 60, 60 },
            }) do
                assert.are.same(want, { price(key, 0, 0), price(key, 0, 5) }, key)
            end
            -- Resourcefulness's mask (440529, 2/2 = -60%): the traps and Counterattack; not the stings or Scatter Shot
            for key, want in pairs({
                explosive_trap = { 520, 208 },
                freezing_trap = { 100, 40 },
                frost_trap = { 60, 24 },
                counterattack = { 85, 34 },
                viper_sting = { 215, 215 },
                scatter_shot = { 0.08, 0.08 },
            }) do
                assert.are.same(want, { price(key, 0, 0), price(key, 2, 0) }, key)
            end
            -- Improved Mend Pet (19572's second row: -10% a rank)
            assert.are.same(
                { 480, 432, 384 },
                { price("mend_pet", 0, 0, 0), price("mend_pet", 0, 0, 1), price("mend_pet", 0, 0, 2) }
            )
        end
    )

    -- The auras the Cooldown Manager links (cdm/hunter.lua): the buff's own spell ID, every rank.
    it("registers the Cooldown Manager's linked auras under their own spell IDs", function()
        local A = w.auras
        for aura, ids in pairs({
            sniper_shot = { 1310687, 1310785, 1310786 },
            immolation_trap = { 13797, 14298, 14299, 14300, 14301 },
            freezing_trap = { 3355, 14308, 14309, 1324500, 1324501, 1324502 },
            frost_trap = { 13810 },
            trueshot_aura = { 1299346, 1299348, 19506, 20905, 20906 },
            scare_beast = { 1324506, 1324507, 1324510 },
            intimidation = { 1324494 },
            scatter_shot = { 1324499 },
            deterrence = { 19263 },
            entrapment = { 19185 },
            improved_concussive_shot = { 1324511 },
            frenzy = { 19621 },
        }) do
            assert.is_table(A[aura], aura)
            local have = { [A[aura].id] = true }
            for _, c in ipairs(A[aura].copy or {}) do
                have[c] = true
            end
            for _, id in ipairs(ids) do
                assert.is_true(have[id] == true, aura .. " " .. id)
            end
        end
    end)

    it("anchors the ranged clock on Auto Shot, off the GCD", function()
        local a = w.abilities.auto_shot
        assert.are.same({ true, "off", 0 }, { a.rangedSwing, a.gcd, a.cast })
    end)

    it("declares Summon Hawk's guardians, two at most for 18 s, and each dive summons one", function()
        assert.are.same({ hawk = { spell = "summon_hawk", duration = 18, cap = 2 } }, w.pets)
        for _, field in ipairs({ "now", "handler" }) do
            local e = ld.env(w)
            local pets, cds = {}, {}
            e.summonPet = function(...)
                pets[#pets + 1] = { ... }
            end
            e.setCooldown = function(k, v)
                cds[#cds + 1] = { k, v }
            end
            ld.run(w.abilities.summon_hawk[field], e)
            assert.are.same({ { { "hawk", 18 } }, { { "arcane_shot", 6 } } }, { pets, cds }, field)
        end
    end)

    it("shares the 6 s category cooldowns: Arcane Shot and Summon Hawk, Aimed Shot and Multi-Shot", function()
        for _, case in ipairs({
            { "arcane_shot", "summon_hawk" },
            { "aimed_shot", "multi_shot" },
            { "multi_shot", "aimed_shot" },
        }) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                local cds = {}
                e.setCooldown = function(k, v)
                    cds[#cds + 1] = { k, v }
                end
                ld.run(w.abilities[case[1]][field], e)
                assert.are.same({ { case[2], 6 } }, cds, case[1] .. " " .. field)
            end
        end
        -- Improved Arcane Shot shortens the category recovery Arcane Shot puts on Summon Hawk too (wowsims's
        -- hunter_beast_mastery_turret.log, 2/5: Summon Hawk 5.4 s after an Arcane Shot at the earliest, Arcane Shot 6.0 s
        -- after a Summon Hawk); Summon Hawk's own stays 6
        for _, case in ipairs({ { "arcane_shot", "summon_hawk", 5.4 }, { "summon_hawk", "arcane_shot", 6 } }) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                e.talent.improved_arcane_shot = { rank = 2, enabled = true }
                local cds = {}
                e.setCooldown = function(k, v)
                    cds[#cds + 1] = { k, math.floor(v * 1000 + 0.5) / 1000 }
                end
                e.summonPet = function() end
                ld.run(w.abilities[case[1]][field], e)
                assert.are.same({ { case[2], case[3] } }, cds, case[1] .. " " .. field)
            end
        end
    end)

    it("models the target's Hunter's Mark and Serpent Sting, Rapid Fire, and one aspect at a time", function()
        for _, case in ipairs({
            { "hunters_mark", { "hunters_mark" }, {} },
            { "serpent_sting", { "serpent_sting" }, {} },
            { "rapid_fire", { "rapid_fire" }, {} },
            { "aspect_of_the_hawk", { "aspect_of_the_hawk" }, OTHER_ASPECTS("aspect_of_the_hawk") },
            { "aspect_of_the_beast", { "aspect_of_the_beast" }, OTHER_ASPECTS("aspect_of_the_beast") },
            { "aspect_of_the_cheetah", { "aspect_of_the_cheetah" }, OTHER_ASPECTS("aspect_of_the_cheetah") },
            { "aspect_of_the_monkey", { "aspect_of_the_monkey" }, OTHER_ASPECTS("aspect_of_the_monkey") },
            { "aspect_of_the_pack", { "aspect_of_the_pack" }, OTHER_ASPECTS("aspect_of_the_pack") },
            { "aspect_of_the_wild", { "aspect_of_the_wild" }, OTHER_ASPECTS("aspect_of_the_wild") },
            { "aspect_of_the_viper", { "aspect_of_the_viper" }, OTHER_ASPECTS("aspect_of_the_viper") },
        }) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                ld.run(w.abilities[case[1]][field], e)
                assert.are.same({ case[2], case[3] }, { e.applied, e.removed }, case[1] .. " " .. field)
            end
        end
        local A = w.auras
        assert.are.same({ 1978, 15, 3, 1130, 120, 3045, 15, 6150, 12, 5302, 5 }, {
            A.serpent_sting.id,
            A.serpent_sting.duration,
            A.serpent_sting.tick_time,
            A.hunters_mark.id,
            A.hunters_mark.duration,
            A.rapid_fire.id,
            ld.run(A.rapid_fire.duration, ld.env(w)), -- a function since the Cryptstalker 2-piece
            A.quick_shots.id,
            A.quick_shots.duration,
            A.defensive_state.id,
            A.defensive_state.duration,
        })
    end)

    -- L1058: The Beast Within (1223758; DB2 effects A_DUMMY 10 and -50 on the caster, no mask; the pin has no row):
    -- our Bestial Wrath's 18 s on us, every mana cost -50%. Bestial Wrath only with the pet out alive (wowsims's
    -- ExtraCastCondition pet.IsEnabled, talents_beast_mastery.go:136-138).
    it(
        "puts Bestial Wrath's 18 s on us at the cast, halving every mana cost, and casts it only with the pet out",
        function()
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                ld.run(w.abilities.bestial_wrath[field], e)
                assert.are.same({ "bestial_wrath" }, e.applied, field)
            end
            assert.are.same({ 19574, 18 }, { w.auras.bestial_wrath.id, w.auras.bestial_wrath.duration })
            local mods = {}
            for _, m in ipairs(w.costMods) do
                if m.aura == "bestial_wrath" then
                    mods[#mods + 1] = { m.pct, m.charges or false, m.spells or false }
                end
            end
            assert.are.same({ { -0.5, false, false } }, mods)
            local function usable(exists, dead)
                w.game.exists.pet, w.game.dead.pet = exists, dead
                return (ld.run(w.abilities.bestial_wrath.usable, ld.env(w)))
            end
            assert.are.same({ false, false, true }, { usable(false, false), usable(true, true), usable(true, false) })
        end
    )

    -- L1059: Revive Pet's cast and cost by Improved Revive Pet's rank (the pin's 24443 curve: {-3000, -6000} ms,
    -- {-20, -40}%), its cost a fraction of base mana at any magnitude; each call only while the client says usable
    -- (Revive Pet also when only short of mana).
    it(
        "prices Revive Pet by Improved Revive Pet's rank and offers each call only while the client says usable",
        function()
            local rp, e = w.abilities.revive_pet, ld.env(w)
            assert.is_true(rp.spendBase)
            local out = {}
            for r = 0, 2 do
                e.talent.improved_revive_pet = { rank = r, enabled = r > 0 }
                out[#out + 1] = { ld.run(rp.cast, e), math.floor(ld.run(rp.spend, e) * 100 + 0.5) / 100 }
            end
            assert.are.same({ { 10, 1 }, { 7, 0.8 }, { 4, 0.6 } }, out)
            w.game.known[883], w.game.known[982] = true, true
            local function usable(key, id, u)
                w.game.usable[id] = u
                return (ld.run(w.abilities[key].usable, ld.env(w)))
            end
            assert.are.same({ true, false, false, true, true, false }, {
                usable("call_pet", 883, { true, false }),
                usable("call_pet", 883, { false, true }),
                usable("call_pet", 883, nil),
                usable("revive_pet", 982, { true, false }),
                usable("revive_pet", 982, { false, true }),
                usable("revive_pet", 982, nil),
            })
        end
    )

    it("shortens Rapid Fire's cooldown by Rapid Killing's curve {-60, -120} s (talents_marksmanship.go:100)", function()
        local e = ld.env(w)
        local cd = {}
        for n = 0, 2 do
            e.talent = setmetatable({}, {
                __index = function()
                    return { rank = n, enabled = n > 0 }
                end,
            })
            cd[n + 1] = ld.run(w.abilities.rapid_fire.cooldown, e)
        end
        assert.are.same({ 300, 240, 180 }, cd)
    end)

    -- Aspect of the Cheetah (5118: 40 mana, aura 30% speed, a proc of Dazed 15571: 4 s) and the Cryptstalker set
    -- (sim/hunter/item_sets.go: 2pc 28755 Rapid Fire +4 s, 8pc 28751 Multi-Shot and Aimed Shot -20 mana).
    it("registers Dazed, and the Cryptstalker bonuses lengthen Rapid Fire and cut the shots' cost", function()
        local A = w.auras
        assert.are.same({ 5118, 3600, 15571, 4, 28755, 28751 }, {
            A.aspect_of_the_cheetah.id,
            A.aspect_of_the_cheetah.duration,
            A.dazed.id,
            A.dazed.duration,
            A.cryptstalker_2pc.id,
            A.cryptstalker_8pc.id,
        })
        local function with(sb, f)
            local e = ld.env(w)
            e.set_bonus = setmetatable(sb, {
                __index = function()
                    return 0
                end,
            })
            return ld.run(f, e)
        end
        assert.are.same(
            { 15, 19 },
            { with({}, A.rapid_fire.duration), with({ cryptstalker_2pc = 1 }, A.rapid_fire.duration) }
        )
        local e8 = { cryptstalker_8pc = 1 }
        local function round(x)
            return math.floor(x * 100000 + 0.5) / 100000
        end
        w.game.known[2643], w.game.known[20904] = true, true
        assert.are.same({ 0.139, 310, round(0.139 - 20 / 1720), 290 }, {
            round(with({}, w.abilities.multi_shot.spend)),
            with({}, w.abilities.aimed_shot.spend),
            round(with(e8, w.abilities.multi_shot.spend)),
            with(e8, w.abilities.aimed_shot.spend),
        })
    end)

    it("registers the pin's bookkeeping auras (id, duration, stacks) and Immolation Trap's burn", function()
        local A = w.auras
        -- id, duration, max_stack: wowsims sim/hunter (spells_auto_gen.go rows 415407, 1310786, 1310726, 1317257,
        -- 1310536, 14301)
        for key, want in pairs({
            rapid_killing = { 415407, 20, 1 },
            sniper_shot = { 1310786, 10, 3 },
            expose_prey = { 1310726, 10, 1 },
            strider_kick = { 1317257, 3, 1 },
            lacerating_strikes = { 1310536, 21, 1 },
            immolation_trap = { 14301, 15, 1 },
        }) do
            assert.are.same(want, { A[key].id, A[key].duration, A[key].max_stack }, key)
        end
        for _, field in ipairs({ "now", "handler" }) do
            local e = ld.env(w)
            ld.run(w.abilities.immolation_trap[field], e)
            assert.are.same({ "immolation_trap" }, e.applied, field)
        end
    end)

    it("hastes Aimed Shot, Multi-Shot and Sniper Shot's casts by Rapid Fire and Quick Shots", function()
        local e = ld.env(w)
        local function casts()
            return {
                ld.run(w.abilities.aimed_shot.cast, e),
                ld.run(w.abilities.multi_shot.cast, e),
                ld.run(w.abilities.sniper_shot.cast, e),
            }
        end
        assert.are.same({ 2, 0.5, 4 }, casts())
        e.buff = buffs({ rapid_fire = true, quick_shots = true })
        local c = casts()
        assert.is_true(math.abs(c[3] - 4 / 1.82) < 1e-9)
        assert.is_true(math.abs(c[1] - 2 / 1.82) < 1e-9)
    end)

    it("queues Raptor Strike on the next swing, once, read back from IsCurrentSpell", function()
        local r = w.abilities.raptor_strike
        assert.is_true(r.onNextSwing)
        local e = ld.env(w)
        w.state.mainhand_remains, w.state.mainhand_speed = 0, 2.6 -- the stand-in now runs the aura's duration function (reads the file's `state`)
        assert.is_true((ld.run(r.usable, e)))
        ld.run(r.handler, e)
        assert.are.same({ "raptor_strike" }, e.applied)
        assert.are.same({ "weave" }, e.closed) -- the weave's strike ends its window in the forecast
        e = ld.env(w)
        ld.run(r.now, e)
        assert.are.same({ { "weave" }, {} }, { e.closed, e.applied }) -- and in the belief, at the real cast
        e = ld.env(w)
        e.buff = buffs({ raptor_strike = true })
        assert.is_false((ld.run(r.usable, e)))
        -- reset_precast: the queued rank answers IsCurrentSpell
        w.game.known[14266] = true
        w.game.current[14266] = true
        e = ld.env(w)
        e.now, e.query_time = 0, 1 -- not the present: no usability read
        ld.run(w.hooks.reset_precast, e)
        assert.are.same({ "raptor_strike" }, e.applied)
    end)

    -- Resourcefulness (440529: 30% / 60% at ranks 1 / 2) and Efficiency (19416: 3% a rank) on each ability's top-rank
    -- price, each a talent-gated cost modifier (one SPELLMOD_COST percent each, multiplied). wowsims's logs: the 2/2
    -- Resourcefulness builds pay 40 Raptor Strike, 26 Mongoose Bite, 32 Wing Clip, 98 Immolation Trap, 39.6 Strider
    -- Kick; the 2/5 Efficiency BM build 94 Raptor Strike, 75.2 Wing Clip, 235 Serpent Sting, 224.66 Multi-Shot (of 239).
    it("prices the abilities under Resourcefulness and Efficiency by rank", function()
        local KEYS = {
            "raptor_strike",
            "mongoose_bite",
            "wing_clip",
            "immolation_trap",
            "strider_kick",
            "arcane_shot",
            "serpent_sting",
            "multi_shot",
            "aimed_shot",
            "summon_hawk",
            "hunters_mark",
            "rapid_fire",
        }
        for _, key in ipairs(KEYS) do
            local ids = KIT[key][1]
            w.game.known[ids[#ids]] = true
        end
        local e = ld.env(w)
        local function costs(res, eff)
            e.talent.resourcefulness = { rank = res, enabled = res > 0 }
            e.talent.efficiency = { rank = eff, enabled = eff > 0 }
            local out = {}
            for _, key in ipairs(KEYS) do
                out[#out + 1] = math.floor(cutCost(w, w.abilities[key], e) * 100000 + 0.5) / 100000
            end
            return out
        end
        -- raptor, bite, clip, trap, kick, arcane, sting, multi, aimed, hawk, mark, rapid fire
        -- Arcane Shot and Summon Hawk 11% of base mana (wowsims e4ef929e54; was 190 at the top rank)
        assert.are.same({ 100, 65, 80, 245, 0.0581, 0.11, 250, 0.139, 310, 0.11, 60, 100 }, costs(0, 0))
        assert.are.same({ 70, 45.5, 56, 171.5, 0.04067, 0.11, 250, 0.139, 310, 0.11, 60, 100 }, costs(1, 0))
        assert.are.same({ 40, 26, 32, 98, 0.02324, 0.11, 250, 0.139, 310, 0.11, 60, 100 }, costs(2, 0))
        -- Efficiency on Strider Kick since hotfix 113554 (19416's mask, wowsims)
        assert.are.same({ 94, 61.1, 75.2, 245, 0.05461, 0.1034, 235, 0.13066, 291.4, 0.1034, 60, 100 }, costs(0, 2))
        -- both talents: two cost rows, multiplied (0.4 x 0.94), not their percents added (wowsims spell_mod.go)
        assert.are.same({ 37.6, 24.44, 30.08, 98, 0.02185, 0.1034, 235, 0.13066, 291.4, 0.1034, 60, 100 }, costs(2, 2))
        -- the two talent-gated modifiers carry the cuts (no aura; the ability's own `spend` is the uncut price)
        local mods = {}
        for _, m in ipairs(w.costMods) do
            if m.talent then
                mods[#mods + 1] = { m.talent, m.aura or false, m.pct, #m.spells }
            end
        end
        assert.are.same({
            { "resourcefulness", false, { -0.3, -0.6 }, 9 },
            { "efficiency", false, { -0.03, -0.06, -0.09, -0.12, -0.15 }, 18 },
        }, mods)
        assert.are.same({ 100, 0.11 }, { ld.run(w.abilities.raptor_strike.spend, e), w.abilities.arcane_shot.spend })
    end)

    -- Improved Arcane Shot (19454, 5 ranks): Arcane Shot's cooldown -0.3 s a rank (wowsims's 19454 curve
    -- {-300 .. -1500}; DB2 carries only rank 1's row): the MM build's 3/5 casts it 5.1 s apart in wowsims's log.
    it("shortens Arcane Shot's cooldown 0.3 s a rank of Improved Arcane Shot", function()
        local cd = w.abilities.arcane_shot.cooldown
        local e = ld.env(w)
        local out = {}
        for rank = 0, 5 do
            e.talent.improved_arcane_shot = { rank = rank, enabled = rank > 0 }
            out[#out + 1] = math.floor(ld.run(cd, e) * 1000 + 0.5) / 1000
        end
        assert.are.same({ 6, 5.7, 5.4, 5.1, 4.8, 4.5 }, out)
    end)

    it("answers mainhand_remains, the time to the next main-hand swing (wowsims's Multi-Shot weave gap)", function()
        local f = assert(w.exprs.mainhand_remains, "no mainhand_remains")
        local e = ld.env(w)
        e.combat, e.mainhand_speed = 1, 3
        e.nextMH, e.now, e.query_time = 12, 10, 10
        assert.are.equal(2, ld.run(f, e))
        e.query_time = 11
        assert.are.equal(1, ld.run(f, e))
        e.target = { within5 = true }
        e.query_time = 13 -- past the swing in melee: the next one, a period later
        assert.are.equal(2, ld.run(f, e))
        e.target = { within5 = false } -- out of melee no swing comes: wowsims's due timer reads 0 until one lands
        assert.are.equal(0, ld.run(f, e))
        e.target = { within5 = true }
        e.nextMH, e.combat, e.query_time = 0, 0, 10 -- out of combat: anchored at this evaluation
        assert.are.equal(0, ld.run(f, e))
    end)

    it(
        "answers ranged_remains and ranged_speed, the ranged auto-shot clock (C7), anchored like mainhand_remains",
        function()
            local f = assert(w.exprs.ranged_remains, "no ranged_remains")
            local sp = assert(w.exprs.ranged_speed, "no ranged_speed")
            local function near(want, got)
                assert.is_true(math.abs(want - got) < 1e-9, tostring(got))
            end
            local e = ld.env(w)
            e.combat = 1
            e.swings = { ranged_projected = 11.2, ranged_speed = 2.9 }
            e.now, e.query_time = 10, 10
            near(1.2, ld.run(f, e))
            e.query_time = 10.5
            near(0.7, ld.run(f, e))
            e.query_time = 12 -- 0.8 s past a due shot: ranged_speed - (elapsed % ranged_speed); shots fire from range
            near(2.1, ld.run(f, e))
            e.query_time = 11.2 + 2 * 2.9 + 0.4
            near(2.5, ld.run(f, e))
            assert.are.equal(2.9, ld.run(sp, e))
            e.swings.ranged_speed = 0 -- Review Focus 5: no speed read yet; the client raises on x % 0
            assert.are.equal(0, ld.run(f, e))
            assert.are.equal(0, ld.run(sp, e))
            -- no shot believed: 0, at now and in the forecast, no wrap (a wrap would forecast a weave open at the pull)
            e.swings = { ranged_projected = 0, ranged_speed = 2.9 }
            e.combat, e.query_time = 0, 10
            assert.are.equal(0, ld.run(f, e))
            e.query_time = 10.5
            assert.are.equal(0, ld.run(f, e))
        end
    )

    -- wowsims e4ef929e54 (talents_survival.go): Strider Kick's speed (1317257, 3 s) comes with the kick, hit or miss;
    -- Lacerating Strikes (1310533) bleeds the target on each Mongoose Bite, a new bite replacing the bleed on a new
    -- timer (774fc188dd). Survival Melee's run out for the Sting reads the speed.
    it("puts Strider Kick's speed on us, and Lacerating Strikes' bleed on the bitten target when talented", function()
        for _, field in ipairs({ "now", "handler" }) do
            local e = ld.env(w)
            ld.run(w.abilities.strider_kick[field], e)
            assert.are.same({ "strider_kick" }, e.applied, field)
            for rank, want in pairs({ [0] = {}, [1] = { "lacerating_strikes" } }) do
                e = ld.env(w)
                e.talent.lacerating_strikes = { rank = rank, enabled = rank > 0 }
                ld.run(w.abilities.mongoose_bite[field], e)
                assert.are.same(want, e.applied, field .. " " .. rank)
            end
        end
    end)

    it("opens Mongoose Bite's window from the usability flip, 5 s from the flip, and the bite spends it", function()
        local b = w.abilities.mongoose_bite
        local e = ld.env(w)
        assert.is_false((ld.run(b.usable, e)))
        e.buff = buffs({ defensive_state = true })
        assert.is_true((ld.run(b.usable, e)))
        for _, field in ipairs({ "now", "handler" }) do
            e = ld.env(w)
            ld.run(b[field], e)
            assert.are.same({ "defensive_state" }, e.removed, field)
        end
        w.game.known[14271] = true
        w.game.usable[14271] = { true, false }
        w.game.now = 10
        w.events.SPELL_UPDATE_USABLE()
        e = ld.env(w)
        e.now, e.query_time = 12, 12
        ld.run(w.hooks.reset_precast, e)
        assert.are.same({ { "defensive_state" }, 3 }, { e.applied, e.durations.defensive_state })
    end)
end)

-- The priorities: the wowsims.com packs (generated from wowsims/forever's Melee Weave by `make wowsims-packs`).
describe("Forever Hunter priorities", function()
    local packs = {}
    setup(function()
        for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", "hunter")) do
            packs[p.name] = p
        end
    end)

    -- L1059 (owner): no pet out, call it; the pet dead, revive it; at the top of every list (a Lone Wolf Hunter wants
    -- none out).
    it("leads every list with Call Pet and Revive Pet", function()
        local n = 0
        for name, p in pairs(packs) do
            for _, list in ipairs({ "precombat", "default" }) do
                local e = p.lists[list]
                n = n + 1
                assert.are.same({
                    { "call_pet", "!pet_out&!pet.dead&!talent.lone_wolf.enabled" },
                    { "revive_pet", "pet.dead" },
                }, {
                    { e[1].action, e[1].criteria },
                    { e[2].action, e[2].criteria },
                }, name .. " " .. list)
            end
        end
        assert.are.equal(10, n)
    end)

    it("keeps the class file's generated blocks in step with APLs/ and retires the hand-built lists", function()
        local mp = assert(loadfile("tools/make_pack.lua"))("lib")
        local f = assert(io.open(FILE))
        local src = f:read("*a")
        f:close()
        assert.are.equal(src, (mp.sync(src, mp.load("hunter"))))
        local cls, names = ld.load(nil, FILE, "HUNTER"), {}
        for _, sp in ipairs(cls.def.specs) do
            names[#names + 1] = sp.package
        end
        assert.are.same({
            "Beast Mastery Turret (wowsims.com)",
            "Marksmanship Turret (wowsims.com)",
            "Survival Turret (wowsims.com)",
        }, names)
        assert.is_truthy(src:find('spec:RetirePacks({ "BeastMastery", "Marksmanship", "Survival" })', 1, true))
        -- the weave packs whose wowsims builds are gone (L1154)
        assert.is_truthy(
            src:find('spec:RetirePacks({ "Beast Mastery (wowsims.com)", "Marksmanship (wowsims.com)" })', 1, true)
        )
    end)

    -- Ledger L682: every Hunter pack carries the racials wowsims's autocast would use for a Hunter's races (rule 13's racial block,
    -- tools/wowsims/apl.lua M.RACIALS over CLASS_RACES.ClassHunter: Night Elf's Elune's Light, Orc's Blood Fury, Troll's
    -- Berserking; Stoneform and Shatter Curse are tanks' only), from the racial block and not from the sampled log.
    it("carries Elune's Light, Blood Fury and Berserking in every pack", function()
        local n = 0
        for name, p in pairs(packs) do
            n = n + 1
            local have = {}
            for _, entries in pairs(p.lists) do
                for _, e in ipairs(require("Forever.helpers.pack_entries").flat(entries)) do -- members too
                    have[e.action] = true
                end
            end
            for _, key in ipairs({ "elunes_light", "blood_fury", "berserking" }) do
                assert.is_true(have[key] == true, name .. " " .. key)
            end
            assert.is_nil(have.stoneform, name)
        end
        assert.are.equal(5, n)
    end)

    it("names only registered abilities, auras, settings and the hawk", function()
        local cls = ld.load(nil, FILE, "HUNTER")
        local kinds = { buff = cls.auras, debuff = cls.auras, cooldown = cls.abilities, settings = cls.settings }
        -- every race's racials (the Races files Hekili_Shared's TOC lists: rule 13's Blood Fury) and the shared
        -- consumables (rule 13's Demonic Rune and Major Mana Potion) are registered too
        local racials = {}
        local toc = assert(io.open(TOC_SHARED))
        for path in toc:read("*a"):gmatch("((%a+)\\[%w_]+%.lua)") do
            local f = assert(io.open("src/Hekili_Shared/" .. path:gsub("\\", "/")))
            local text = f:read("*a")
            for key in text:gmatch('RegisterAbility%("([%w_]+)"') do
                racials[key] = true
            end
            for key in text:gmatch('consume%("([%w_]+)"') do
                racials[key] = true
            end
            f:close()
        end
        toc:close()
        assert.is_true(racials.blood_fury)
        local pe = require("Forever.helpers.pack_entries") -- a sequence's members walked too
        for name, p in pairs(packs) do
            for list, entries in pairs(p.lists) do
                for i, e in ipairs(pe.flat(entries)) do
                    local where = name .. " " .. list .. " " .. i
                    local window = e.action == "open_window" or e.action == "close_window"
                    assert.is_true(
                        e.action == "call_action_list"
                            or pe.LINE[e.action]
                            or cls.abilities[e.action] ~= nil
                            or racials[e.action],
                        where
                    )
                    assert.is_true(not window or cls.windows[e.window_name or e.list_name] ~= nil, where)
                    for key in (e.criteria or ""):gmatch("window%.([%w_]+)") do
                        assert.is_true(cls.windows[key] ~= nil, where .. ": window " .. key)
                    end
                    for kind, key in (e.criteria or ""):gmatch("(%a+)%.([%w_]+)") do
                        if kinds[kind] then
                            assert.is_true(kinds[kind][key] ~= nil, where .. ": " .. key)
                        elseif kind == "pet" then
                            -- `dead`: the engine's pet-unit read (State.lua), Revive Pet's line (L1059)
                            assert.is_true(cls.pets[key] ~= nil or key == "dead", where .. ": pet " .. key)
                        elseif kind == "action" then
                            assert.is_true(cls.abilities[key] ~= nil, where .. ": action " .. key)
                        end
                    end
                end
            end
        end
    end)
end)

-- Through the real engine (headless.lua): a Hunter who knows the whole kit.
describe("Forever Hunter through the engine", function()
    local H

    local function character()
        local w = ld.load(nil, FILE, "HUNTER")
        local known = {}
        for _, a in pairs(w.abilities) do
            for _, id in ipairs(idsOf(a)) do
                known[#known + 1] = id
            end
        end
        return {
            class = "HUNTER",
            classID = 3,
            specID = 1484,
            level = 60,
            known = known,
            talents = {},
            power = { type = 0, token = "MANA", max = 5000, value = 5000 },
            speed = { 3.5 },
        },
            w
    end

    before_each(function()
        H = headless.new({ character = character(), pack = "Beast Mastery Turret (wowsims.com)" })
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

    it("counts the hawks our dives summon in the belief and the simulation, two at most, each for 18 s", function()
        local VS, S = H.ns.VirtualState, H.Hekili.State
        local t = H.ctl.now + 1
        for k = 1, 3 do
            H.ctl.now = t + 6 * (k - 1)
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. k, 1293527)
            assert.is_true(headless.cycle(H, H.ctl.now + 0.1))
        end
        local now = H.ctl.now + 0.1
        -- the simulation counts them in the facade's totem slots past the client's five (RegisterPets' `cap`: slots 6-7)
        assert.are.equal(6, H.Hekili.Class.pets.hawk.slot)
        local up, name, start, dur = H.ns.Facade.GetTotemInfo(6) -- the third dive took the oldest's slot
        assert.are.same({ true, "hawk", t + 12, 18 }, { up, name, start, dur })
        S.reset("Primary", true)
        assert.are.equal(2, S.pet.hawk.count)
        H.ctl.now = t + 6 + 18 + 0.1 -- the second dive's hawk is gone, the third's is up
        assert.are.same({ true, false }, { (H.ns.Facade.GetTotemInfo(6)), (H.ns.Facade.GetTotemInfo(7)) })
        assert.are.same({}, H.errors)
    end)

    -- L1058: pet_out is the pet unit (UnitExists / UnitIsDead of "pet", plain), not the simulation's pet.up, which a
    -- hawk's summon also makes true; The Beast Within's -50% holds Bestial Wrath's 18 s in both layers, through an
    -- in-combat walk of our auras (the buff is the pet's: never on us).
    it("gates Bestial Wrath on the pet out alive, and halves the shots' cost for its 18 s in both layers", function()
        local I, VS, S = H.ns.VirtualStateInternal, H.ns.VirtualState, H.Hekili.State
        local arcane = I.ab.bySpell[3044]
        local function at(t)
            assert.is_true(headless.cycle(H, t))
            VS.Drain(t)
            S.reset("Primary", true)
        end
        local t = H.ctl.now + 1
        H.ctl.exists.pet = nil
        at(t + 0.1)
        assert.is_false((S:IsUsable("bestial_wrath")))
        S.summonPet("hawk", 18) -- the forecast's dive (Summon Hawk's handler): pet.up, but no pet out
        assert.are.same({ true, false }, { S.pet.up, S.pet_out })
        assert.is_false((S:IsUsable("bestial_wrath")))
        H.ctl.exists.pet, H.ctl.dead.pet = true, true
        at(t + 0.2)
        assert.is_false((S:IsUsable("bestial_wrath")))
        H.ctl.dead.pet = nil
        at(t + 0.3)
        assert.is_true((S:IsUsable("bestial_wrath")))
        local full = I.CostOf(arcane)
        assert.are.same({ false, full }, { S.buff.bestial_wrath.up, S.action.arcane_shot.cost })

        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        t = t + 1
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-BW", 19574)
        at(t + 0.1)
        H.Fire("UNIT_AURA", "player")
        at(t + 0.2)
        assert.is_true(full > 0)
        assert.are.same(
            { true, full / 2, full / 2 },
            { S.buff.bestial_wrath.up, I.CostOf(arcane), S.action.arcane_shot.cost }
        )
        at(t + 18.1)
        assert.are.same({ false, full, full }, { S.buff.bestial_wrath.up, I.CostOf(arcane), S.action.arcane_shot.cost })
        assert.are.same({}, H.errors)
    end)

    -- L1059: the pack's first pick with no pet out (Call Pet), the pet dead (Revive Pet), the pet out alive (neither),
    -- and neither while the client calls the spell unusable (no tamed pet, no corpse).
    it("recommends Call Pet with no pet out and Revive Pet for a dead one, only while usable", function()
        H.ctl.level.target, H.ctl.distance.target = 60, 25
        H.Fire("PLAYER_TARGET_CHANGED")
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        local t = H.ctl.now
        local function first(exists, dead)
            H.ctl.exists.pet, H.ctl.dead.pet = exists, dead
            t = t + 0.2
            assert.is_true(headless.cycle(H, t))
            local recs = H.Hekili.Engine.Output.Primary.recs
            return recs[1] and recs[1].actionName
        end
        H.ctl.usable[883], H.ctl.usable[982] = { true, false }, { true, false }
        assert.are.equal("call_pet", first(nil, nil))
        assert.are.equal("revive_pet", first(true, true))
        local up = first(true, nil)
        assert.is_true(up ~= "call_pet" and up ~= "revive_pet", tostring(up))
        H.ctl.usable[883], H.ctl.usable[982] = nil, nil
        local none = first(nil, nil)
        assert.is_true(none ~= "call_pet" and none ~= "revive_pet", tostring(none))
        none = first(true, true)
        assert.is_true(none ~= "call_pet" and none ~= "revive_pet", tostring(none))
        assert.are.same({}, H.errors)
    end)

    it("answers the ranged clock after a modelled Auto Shot in swing.ranged and swings.ranged_*", function()
        local VS, S = H.ns.VirtualState, H.Hekili.State
        local t = H.ctl.now + 1
        H.ctl.now = t
        H.ctl.combat = true -- out of combat Hekili's swing timers answer from now
        H.Fire("PLAYER_REGEN_DISABLED")
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 75)
        assert.is_true(headless.cycle(H, t + 0.5))
        S.reset("Primary", true)
        local next = VS.Swing(3, S.now).est
        assert.is_true(next > S.now)
        assert.are.equal(next, S.swings.ranged_projected)
        assert.is_true(math.abs(S.swing.ranged.remains - (next - S.now)) < 1e-9)
        assert.are.same({}, H.errors)
    end)

    -- Review Focus 6 (R6). How `mainhand_remains<x` reaches script.Recheck (verified by printing BuildRecheck's
    -- output): scripts:BuildRecheck runs EmulateSyntax first, which wraps a term whose state value is not a number at
    -- compile time in `safenum(...)`; then ConvertTimeComparison: a bare `X_remains` matches its `decreases` table
    -- ("remains$") and `<` compiles to `(lhs+0.01)-(rhs)`, a wrapped `safenum(X_remains)` falls to the generic
    -- `0.01+lhs-rhs`: either way the time until it holds (0.01 past, for the strict `<`). `ranged_remains` takes the
    -- same paths. A `>`/`>=` on a decreasing clock fell to that fallback, negative while false; the wrap branch answers
    -- the time to the clock's wrap (0.01 past it), when the clock jumps back to its speed.
    it("forecasts the ranged clock through scripts:BuildRecheck: a `<` its time to x, a `>` its wrap", function()
        local Sc = H.Hekili.Scripts
        local env = { ranged_remains = 1.2, ranged_speed = 2.9, mainhand_remains = 0.4, mainhand_speed = 2.6 }
        env.safenum = function(x)
            return type(x) == "number" and x or 0
        end
        local function at(cond)
            local rs = assert(Sc:BuildRecheck(cond), cond)
            return setfenv(assert(loadstring("return " .. rs)), env)()
        end
        local function near(want, got)
            assert.is_true(math.abs(want - got) < 1e-9, tostring(got))
        end
        near(0.71, at("ranged_remains<0.5")) -- 1.2 - 0.5 = 0.7, plus the strict comparison's 0.01
        assert.is_false(env.ranged_remains > env.ranged_speed - 0.1) -- currently false: true just past the wrap
        near(1.21, at("ranged_remains>ranged_speed-0.1"))
        near(1.21, at("ranged_remains>=ranged_speed-0.1"))
        near(0.41, at("mainhand_remains>mainhand_speed-0.2")) -- Retribution's hammer_of_wrath, in remains form
        env.fight_remains = 3600
        near(0.01 + 3600 - 10, at("fight_remains>=10")) -- no clock: no wrap, the fallback as before
    end)

    -- The weave window (spec §3a): the belief opens it on an observed Auto Shot with the main hand due, a real Raptor
    -- Strike closes it (now()); the forecast's open is the packs' open_window line, its countdown R6's wrap.
    local function weaveWorld(distance)
        local c = character()
        c.speed = { 2.6 }
        H = headless.new({ character = c, pack = "Beast Mastery Turret (wowsims.com)" })
        H.ctl.level.target, H.ctl.distance.target = 60, distance
        H.Fire("PLAYER_TARGET_CHANGED")
        H.ctl.now = H.ctl.now + 1
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        return H.Hekili.State, H.ns.Facade
    end
    local function shoot(t)
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. t, 75)
    end
    local function lines(apl)
        local parsed = H.Hekili:ParseActionList(apl)
        for _, l in ipairs(parsed) do
            l.enabled = true
        end
        H.Hekili.DB.profile.packs["Beast Mastery Turret (wowsims.com)"].lists = { precombat = {}, default = parsed }
        H.Hekili:LoadScripts()
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
    end

    -- R17: timing only. The window opens at an Auto Shot whose next main-hand swing comes before the next shot and
    -- closes at that swing (or at Raptor Strike).
    it(
        "opens the weave window at an Auto Shot with the main-hand swing before the next shot, closes it at the swing",
        function()
            local _, F = weaveWorld(11)
            local t = H.ctl.now
            shoot(t) -- no main-hand swing yet: due
            assert.is_true(headless.cycle(H, t + 0.1))
            local rs = H.ns.VirtualState.SwingSpeed(3, t).est -- UnitRangedDamage's (the fake client's 3.1 s)
            assert.is_true(rs > 2.6 and rs < 3.6, tostring(rs))
            assert.is_true((F.Window("weave")))
            H.ctl.now = t + 0.5
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-r", 14266) -- a real Raptor Strike
            assert.is_true(headless.cycle(H, t + 0.6))
            assert.is_false((F.Window("weave")))
            H.ctl.now = t + 1
            H.Fire("PLAYER_SWING", 2.6, 0) -- the main hand swings: next at t + 3.6, before the shot after t + rs
            assert.is_true(headless.cycle(H, t + 1.1))
            assert.is_false((F.Window("weave")))
            shoot(t + rs)
            assert.is_true(headless.cycle(H, t + rs + 0.1))
            assert.is_true((F.Window("weave")))
            H.ctl.now = t + 3.6
            H.Fire("PLAYER_SWING", 2.6, 0) -- the swing comes: the weave's chance is spent
            assert.is_true(headless.cycle(H, t + 3.7))
            assert.is_false((F.Window("weave")))
            H.ctl.now = t + 3.8
            H.Fire("PLAYER_SWING", 4, 0) -- a slow swing (4 s): the next one after the next shot
            shoot(t + 3.9)
            assert.is_true(headless.cycle(H, t + 4))
            assert.is_false((F.Window("weave")))
            assert.are.same({}, H.errors)
        end
    )

    -- Fix round 2 ruling: the window closes at the main-hand swing or at the next shot, whichever comes first.
    it("closes the weave window at the next shot (the shot opens its own) and a ranged speed after the last", function()
        local _, F = weaveWorld(11)
        local t = H.ctl.now
        shoot(t) -- out of melee: no main-hand swing comes, so only the shots end the windows
        assert.is_true(headless.cycle(H, t + 0.1))
        local rs = H.ns.VirtualState.SwingSpeed(3, t).est
        local up, at = F.Window("weave")
        assert.is_true(up)
        assert.is_true(math.abs(at - t) < 1e-9, tostring(at))
        shoot(t + rs)
        assert.is_true(headless.cycle(H, t + rs + 0.1))
        up, at = F.Window("weave")
        assert.is_true(up)
        assert.is_true(math.abs(at - (t + rs)) < 1e-9, tostring(at)) -- closed at the shot, reopened by it
        H.ctl.now = t + 2 * rs + 0.1 -- no shot after it: the window ends a ranged speed after the last
        assert.is_true(headless.cycle(H, t + 2 * rs + 0.1))
        assert.is_false((F.Window("weave")))
        assert.are.same({}, H.errors)
    end)

    -- Task 8a-5 (owner 2026-11-04): the weave lasts 1.2 x the ranged shot time, read at each open in its own layer: the
    -- belief's stat("UnitRangedDamage") (the evaluator's read), the forecast's ranged_speed.
    it("times the weave at 1.2 x the shot time at each open, in the belief and in the forecast", function()
        local S, F = weaveWorld(11)
        local VS = H.ns.VirtualState
        local t = H.ctl.now
        shoot(t)
        assert.is_true(headless.cycle(H, t + 0.1))
        local rs = VS.Stat("UnitRangedDamage")
        local up, _, exp = F.Window("weave")
        assert.is_true(up)
        assert.is_true(math.abs(exp - (t + 1.2 * rs)) < 1e-6, tostring(exp))
        H.ctl.now, H.ctl.combat = t + 0.5, false -- out of combat, a faster bow (the stats are read out of combat)
        H.ctl.ranged[1] = 2.5
        H.Fire("PLAYER_REGEN_ENABLED")
        H.ctl.now, H.ctl.combat = t + 1, true
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.are.equal(2.5, (VS.Stat("UnitRangedDamage")))
        shoot(t + 1.5)
        assert.is_true(headless.cycle(H, t + 1.6))
        up, _, exp = F.Window("weave")
        assert.is_true(up)
        assert.is_true(math.abs(exp - (t + 1.5 + 3)) < 1e-6, tostring(exp)) -- the next open follows it
        -- the forecast's own open (the packs' open_window line), nothing closing it: down at 1.2 x ranged_speed
        S.reset("Primary", true)
        S.closeWindow("weave")
        local speed = S.ranged_speed
        assert.is_true(speed > 0, tostring(speed))
        S.openWindow("weave")
        assert.is_true(math.abs(S.window.weave.remains - 1.2 * speed) < 1e-6, tostring(S.window.weave.remains))
        S.advance(1.2 * speed - 0.01)
        assert.is_true(S.window.weave.up)
        S.advance(0.02)
        assert.is_false(S.window.weave.up)
        S.reset("Primary", true)
        S.closeWindow("weave")
        S.swings.ranged_speed = 2 -- a changed shot time: the next forecast open follows it
        S.openWindow("weave")
        assert.is_true(math.abs(S.window.weave.remains - 2.4) < 1e-6, tostring(S.window.weave.remains))
        assert.are.same({}, H.errors)
    end)

    it('keeps Beast Mastery\'s hha open for the fight ("combat"), closed at combat end', function()
        local _, F = weaveWorld(11)
        assert.are.equal("combat", H.Hekili.Class.windows.hha.duration)
        local t = H.ctl.now
        assert.is_true(headless.cycle(H, t + 0.1))
        assert.is_true((F.Window("hha")))
        assert.is_true(headless.cycle(H, t + 4000))
        assert.is_true((F.Window("hha")))
        H.ctl.combat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(headless.cycle(H, t + 4000.1))
        assert.is_false((F.Window("hha")))
    end)

    -- User report (v0.7.3): after the first fight the hawk sequence never came back until a reload; the belief's
    -- `combat` kept the old pull's start, so the evaluator never saw a new false->true edge.
    it("reopens Beast Mastery's hha at the next pull, out of combat closed", function()
        local S, F = weaveWorld(11)
        local t = H.ctl.now
        assert.is_true(headless.cycle(H, t + 0.1))
        assert.is_true((F.Window("hha")))
        H.ctl.now, H.ctl.combat = t + 30, false
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(headless.cycle(H, t + 30.1))
        assert.is_true(headless.cycle(H, t + 35))
        assert.is_false((F.Window("hha")))
        H.ctl.now, H.ctl.combat = t + 40, true
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.is_true(headless.cycle(H, t + 40.1))
        local up, _, _, _, step = F.Window("hha")
        assert.is_true(up)
        assert.are.equal(1, step)
        S.reset("Primary", true)
        assert.is_true(S.window.hha.next.summon_hawk)
        assert.are.same({}, H.errors)
    end)

    it("forecasts no weave open at the pull, before any shot", function()
        local S, F = weaveWorld(11)
        lines(
            "actions+=/open_window,name=weave,if=ranged_remains>ranged_speed-0.1&mainhand_remains<ranged_remains\n"
                .. "actions+=/arcane_shot,if=window.weave.up\n"
                .. "actions+=/serpent_sting"
        )
        assert.is_true(headless.cycle(H, H.ctl.now + 0.1))
        assert.is_false((F.Window("weave")))
        local recs = H.Hekili.Engine.Output.Primary.recs
        for i = 1, #recs do
            assert.are_not.equal("arcane_shot", recs[i].actionName)
        end
        S.reset("Primary", true)
        assert.are.equal(0, S.ranged_remains)
        assert.are.same({}, H.errors)
    end)

    it("recommends a line gated window.weave.up with the delay to the next shot, the main hand due", function()
        local S = weaveWorld(11)
        lines(
            "actions+=/open_window,name=weave,if=ranged_remains>ranged_speed-0.1&mainhand_remains<ranged_remains\n"
                .. "actions+=/arcane_shot,if=window.weave.up"
        )
        local t = H.ctl.now
        shoot(t)
        H.ctl.now = t + 0.1
        H.Fire("PLAYER_SWING", 2.6, 0) -- the main hand swings just after the shot: its chance is spent
        assert.is_true(headless.cycle(H, t + 0.6))
        assert.is_true(headless.cycle(H, t + 0.7)) -- the shot's now() opened it; the next evaluation closes it
        assert.is_false((H.ns.Facade.Window("weave")))
        S.reset("Primary", true)
        local speed = S.ranged_speed
        assert.is_true(speed - 1.2 > 0.6, tostring(speed))
        H.ctl.now = t + speed - 1.2 -- the next shot 1.2 s ahead
        assert.is_true(headless.cycle(H, H.ctl.now))
        local recs = H.Hekili.Engine.Output.Primary.recs
        assert.are.equal("arcane_shot", recs[1] and recs[1].actionName)
        assert.is_true(math.abs(recs[1].wait - 1.21) < 0.02, tostring(recs[1].wait))
        assert.are.same({}, H.errors)
    end)

    it(
        "closes the weave window in the forecast at Raptor Strike's handler: the next pick is made with it down",
        function()
            local S, F = weaveWorld(3)
            lines(
                "actions+=/raptor_strike,if=window.weave.up\n"
                    .. "actions+=/arcane_shot,if=window.weave.up\n"
                    .. "actions+=/serpent_sting"
            )
            local t = H.ctl.now
            shoot(t)
            assert.is_true(headless.cycle(H, t + 0.1))
            assert.is_true((F.Window("weave")))
            local recs = H.Hekili.Engine.Output.Primary.recs
            assert.are.same(
                { "raptor_strike", "serpent_sting" },
                { recs[1].actionName, recs[2] and recs[2].actionName }
            )
            S.reset("Primary", true)
            assert.is_true(S.window.weave.up)
            S:RunHandler("raptor_strike")
            assert.is_false(S.window.weave.up)
            assert.is_true((F.Window("weave"))) -- the belief's own window is untouched
            assert.are.same({}, H.errors)
        end
    )

    -- The drift guard (spec §3a, owner "ok"; tests/Forever/helpers/wowsims.lua windowGuard, run by every replay gate):
    -- Auto Shots every ranged speed, a main-hand swing 1 s after each (it closes the window, the next shot reopens it),
    -- polled at 5 Hz: the forecast's opens (the open line's countdown to each shot) are each matched by the belief's
    -- within a poll, and an evaluator shifted 0.4 s late fails it, each miss listed with its time. Over the replays
    -- (R18: OtherID 4 is the shot) the guard runs on the logs' shots too (tests/Forever/helpers/wowsims.lua gate).
    local function guarded(shift)
        weaveWorld(11)
        lines(
            "actions+=/open_window,name=weave,if=ranged_remains>ranged_speed-0.1&mainhand_remains<ranged_remains\n"
                .. "actions+=/arcane_shot,if=window.weave.up"
        )
        local I = H.ns.VirtualStateInternal
        if shift then -- the belief's own evaluator (Families/Windows.lua), opened `shift` s after the shot
            for a = 1, #I.ab.key do
                if I.ab.key[a] == "auto_shot" then
                    I.ab.now[a] = false -- and the shot's own open (its now()) off
                end
            end
            I.win.eval[I.win.byKey.weave] = setfenv(function()
                local since = now - lastSwing(3) -- luacheck: ignore 113 (the belief's now context)
                return lastSwing(3) > 0 and since >= shift and since < shift + 2 -- luacheck: ignore 113
            end, I.nowCtx)
        end
        local tick, misses, predicted, believed = ws.windowGuard(H, 0.2)
        local t0 = H.ctl.now
        local shot, swing = t0, math.huge
        for k = 0, 50 do
            local t = t0 + 0.2 * k
            if t >= swing then -- a main-hand swing 1 s after each shot: it closes the window, the next shot reopens it
                H.ctl.now, swing = swing, math.huge
                H.Fire("PLAYER_SWING", 2.6, 0)
            end
            if t >= shot then -- a shot every ranged speed (the client's 3.1 s), off the poll grid
                H.ctl.now = shot
                H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. k, 75)
                swing = shot + 1
                shot = shot + H.ns.VirtualState.SwingSpeed(3, shot).est
            end
            H.ctl.now = t
            assert.is_true(headless.cycle(H, t))
            tick(t0)
        end
        assert.are.same({}, H.errors)
        return misses(), predicted, believed
    end

    it("guards the weave's forecast opens: each matched by the belief's within a poll", function()
        local missed, predicted, believed = guarded()
        assert.is_true(#predicted >= 2 and #believed >= 3, #predicted .. " " .. #believed)
        assert.are.same({}, missed)
    end)

    it("fails the guard with an evaluator shifted late, listing each miss with its time", function()
        local missed = guarded(0.4)
        assert.is_true(#missed >= 2, table.concat(missed, "; "))
        assert.is_truthy(missed[1]:match("^weave at %d+%.%d%d s$"), missed[1])
    end)

    -- Review Focus 7 (R13): the queued strike lasts until the swing that takes it (`mainhand_remains`).
    it("ends the queued Raptor Strike at the next swing, and the pick after the swing is made without it", function()
        local c, w = character()
        c.speed = { 2.6 }
        H = headless.new({ character = c, pack = "Beast Mastery Turret (wowsims.com)" })
        local S = H.Hekili.State
        local ids = idsOf(w.abilities.raptor_strike)
        H.ctl.level.target, H.ctl.distance.target = 60, 3 -- in melee
        H.Fire("PLAYER_TARGET_CHANGED")
        local t = H.ctl.now + 1
        H.ctl.now = t
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        H.Fire("PLAYER_SWING", 2.6, 0)
        assert.is_true(headless.cycle(H, t + 0.1))
        H.ctl.now = t + 1.8 -- queued 0.8 s before the 2.6 s swing
        H.ctl.current[ids[#ids]] = true
        assert.is_true(headless.cycle(H, t + 1.8))
        S.reset("Primary", true)
        assert.is_true(math.abs(S.buff.raptor_strike.remains - 0.8) < 1e-6, tostring(S.buff.raptor_strike.remains))
        assert.are.same({ false, "a strike is already queued" }, { S:IsUsable("raptor_strike") }) -- not re-recommended
        S.advance(0.9)
        assert.is_true(S.buff.raptor_strike.down)
        assert.are.same({ true }, { S:IsUsable("raptor_strike") })
        assert.are.same({}, H.errors)
    end)
end)

-- R8 (re-pin plan Task 19 Step 2): the weave's moves reach the strikes (weave #6, to melee) and the shots (weave #7,
-- the move back). The packs' own lines through the real engine in the Survival world (the DB2's ranges), Aspect of
-- the Hawk after them as the filler: OFF hides Raptor Strike's in-range line outside 5 yd and Multi-Shot's inside 8
-- yd, and shows each in its own band; ON shows Multi-Shot inside 8 yd too (weave #7's arm is unconditional). Raptor
-- Strike's arm needs the weave's swing state (the loops and the replay exercise it); here its text is pinned.
describe("Forever Hunter Movement (R8)", function()
    local hw = require("Forever.helpers.hunter_world")
    local PACK = "Survival (wowsims.com)"

    local function lines(key)
        local f = assert(io.open("src/Hekili_Hunter/APLs/" .. PACK .. ".simc"))
        local s = f:read("*a")
        f:close()
        local out = {}
        for l in s:gmatch("\n(actions%+=/" .. key .. ",[^\n]+)") do
            out[#out + 1] = l
        end
        return out
    end

    local function world(key, yd)
        local C = hw.Survival
        local H = headless.new({ character = C.character(), pack = PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.level.target, H.ctl.distance.target = 60, yd
        H.Fire("PLAYER_TARGET_CHANGED")
        local t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        local list = {}
        for _, l in ipairs(lines(key)) do
            local parsed = H.Hekili:ParseActionList(l)
            parsed[1].enabled = true
            list[#list + 1] = parsed[1]
        end
        list[#list + 1] = { enabled = true, action = "aspect_of_the_hawk" }
        H.Hekili.DB.profile.packs[PACK].lists = { precombat = {}, default = list }
        H.Hekili:LoadScripts()
        H.Fire("PLAYER_REGEN_DISABLED")
        local VS = H.ns.VirtualState
        local power, mana = VS.Power, { est = 5000, lo = 5000, hi = 5000, conf = 1 }
        VS.Power = function(pt, now)
            return pt == 0 and mana or power(pt, now)
        end
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        assert.is_true(H.Hekili.Engine.Registry.MovementSpec(C.SPEC)) -- the options row shows (R3)
        return function(movement)
            H.Hekili:FireToggle("movement", movement and "on" or "off")
            t = t + 0.2
            assert(headless.cycle(H, t))
            assert.are.same({}, H.errors)
            return out.recs[1] and out.recs[1].actionName
        end
    end

    it(
        "OFF hides Raptor Strike outside 5 yd and shows it inside; its move arm waits on the toggle and the weave",
        function()
            local l = lines("raptor_strike")
            assert.are.equal(2, #l)
            assert.matches(",if=target%.within5$", l[1])
            -- 0.7 re-pin: the weave's move arm is gated on the Auto Shot since the last swing, not the old weave window
            assert.matches(
                ",if=toggle%.movement&ranged_remains>=ranged_speed%-%(mainhand_speed%-mainhand_remains%)$",
                l[2]
            )
            local far, near = world("raptor_strike", 11), world("raptor_strike", 3)
            assert.are.same({ "aspect_of_the_hawk", "raptor_strike" }, { far(false), near(false) })
        end
    )

    it("OFF hides Multi-Shot inside 8 yd and shows it outside; ON shows it inside too (the move back)", function()
        local far, near = world("multi_shot", 11), world("multi_shot", 3)
        assert.are.same({ "multi_shot", "aspect_of_the_hawk" }, { far(false), near(false) })
        assert.are.same({ "multi_shot", "multi_shot" }, { far(true), near(true) })
    end)
end)

-- Lane R (Fable decision 3): the worlds grant Resourcefulness on an ability's own crit row, the one the client shows
-- (rank / 2 of a crit, wowsims talents_survival.go), never on a second roll beside it.
describe("the Hunter worlds' Resourcefulness", function()
    local hw = require("Forever.helpers.hunter_world")

    it("opens on an ability's crit row only, rank / 2 of the crit", function()
        local C = hw.Survival -- Resourcefulness 2/2
        local H = headless.new({ character = C.character(), pack = "Survival (wowsims.com)" })
        local p = C.resolve("arcane_shot", H)
        local applied, chances = {}, {}
        local function fake(flag)
            local W = { t = 1 }
            W.rng = {
                chance = function(x)
                    chances[#chances + 1] = x
                    return true
                end,
            }
            function W.hit(e)
                e.lastHit = { act = "WOUND", flag = flag }
                return e.lastHit
            end
            function W.applyAura(_, id)
                applied[#applied + 1] = id
            end
            return W
        end
        local e = { cdUntil = {}, target = {} }
        p.effect(fake(""), e)
        assert.are.same({}, applied) -- a plain hit: nothing
        p.effect(fake("CRITICAL"), e)
        assert.are.same({ 1242688 }, applied)
        assert.are.same({ 1 }, chances) -- 2/2: every crit
        -- every ability whose crit the pack's onCrit counts, Wing Clip's included (a main-hand special, wowsims)
        for _, key in ipairs({ "wing_clip", "multi_shot", "strider_kick" }) do
            applied = {}
            C.resolve(key, H).effect(fake("CRITICAL"), e)
            -- Strider Kick's own speed (1317257) comes with every kick
            assert.are.same(key == "strider_kick" and { 1242688, 1317257 } or { 1242688 }, applied, key)
        end
    end)

    -- Lane R2: the worlds grant it as the game would, at the export's own crit rate and on the queued Raptor Strike's crit
    it("rolls a Resourcefulness build's ability crits at its log's rate; the queued Raptor Strike crits too", function()
        assert.are.same({ 11 / 93, 11 / 93, 7 / 41 }, {
            hw.Survival.WORLD.crit,
            hw.SurvivalRanged.WORLD.crit,
            hw.SurvivalTurret.WORLD.crit,
        })
        assert.is_nil(hw.BeastMasteryTurret.WORLD.crit) -- no Resourcefulness: world.CRIT
        local C = hw.Survival
        local H = headless.new({ character = C.character(), pack = "Survival (wowsims.com)" })
        assert.is_true(C.resolve("raptor_strike", H).crits)
        assert.is_nil(C.resolve("arcane_shot", H).crits) -- an instant's crit is W.hit's already
        local applied = {}
        local W = {
            t = 1,
            rng = {
                chance = function()
                    return true
                end,
            },
            applyAura = function(_, id)
                applied[#applied + 1] = id
            end,
        }
        local us = { auras = {} }
        C.WORLD.script(W, us)
        applied = {} -- the aspect
        us.struck(W, "WOUND", "")
        us.struck(W, "DODGE", "")
        assert.are.same({}, applied)
        us.struck(W, "WOUND", "CRITICAL")
        assert.are.same({ 1242688 }, applied)
    end)
end)

-- Ledger L1154 (owner, 0.9 re-pin): the Beast Mastery and Marksmanship weave packs are retired (wowsims deleted their
-- builds and APLs, PR #1041). A player who picked one runs the same spec's Turret pack, the spec's default, and is told
-- once (RestoreDefaults' retired notice); the next login says nothing.
-- Efficiency (19416) as a talent-gated cost modifier (mana-09's RegisterCostMod `talent`): the cut lands on the whole
-- price, unrounded, as wowsims e4ef929e54 (mana.go rounds 11% of 1720 to 189, spell.go then multiplies): the MM Turret
-- build's 4/5 pays 189 x 0.88 = 166.32 for Arcane Shot in its log, and the belief and the simulation both price it so.
describe("the Hunter talent cost cuts through the engine", function()
    local hw = require("Forever.helpers.hunter_world")

    it("prices Efficiency's cut on the whole cost in both layers (MM Turret Arcane Shot 166.32)", function()
        local H =
            headless.new({ character = hw.MarksmanshipTurret.character(), pack = "Marksmanship Turret (wowsims.com)" })
        local I, VS, S = H.ns.VirtualStateInternal, H.ns.VirtualState, H.Hekili.State
        local t = H.ctl.now + 1
        assert.is_true(headless.cycle(H, t))
        VS.Drain(t)
        S.reset("Primary", true)
        local function r(x)
            return math.floor(x * 1000 + 0.5) / 1000
        end
        assert.are.same({ 4, 166.32, 166.32 }, {
            S.talent.efficiency.rank,
            r(I.CostOf(I.ab.bySpell[3044])),
            r(S.action.arcane_shot.cost),
        })
        assert.are.same({}, H.errors)
    end)

    -- mana-09's LearnBases on the class that caused the 0.9 regression (L1230): a client read cut by Efficiency (3% a
    -- rank: Arcane Shot's 189 reads 183, 178, 172, 166, 161) must teach base mana 1720 out of combat, alone and beside
    -- an uncut read (Bestial Wrath's 12% reads 206).
    it("learns base mana 1720 from Efficiency-cut and uncut cost reads at every rank", function()
        for rank = 1, 5 do
            local c = hw.BeastMasteryTurret.character()
            c.talents = { [19416] = rank }
            local H = headless.new({ character = c, pack = "Beast Mastery Turret (wowsims.com)" })
            local VS, S = H.ns.VirtualState, H.Hekili.State
            H.ctl.costs[3044] = { { type = 0, cost = math.floor(189 * (1 - 0.03 * rank) + 0.5) } }
            H.Fire("SPELLS_CHANGED")
            assert.are.same({ rank, 1720 }, { S.talent.efficiency.rank, VS.BasePower(0) }, "cut alone, rank " .. rank)
            H.ctl.costs[19574] = { { type = 0, cost = 206 } }
            H.Fire("SPELLS_CHANGED")
            assert.are.equal(1720, VS.BasePower(0), "beside an uncut read, rank " .. rank)
            assert.are.same({}, H.errors)
        end
    end)

    -- no wowsims log takes both talents: the engine's own product of the two talent mods (Raptor Strike rank 8's 100
    -- x (1 - 0.6) x (1 - 0.06) = 37.6, not the added 34), in the belief and the simulation
    it("multiplies Resourcefulness 2/2 and Efficiency 2/5 in both layers (Raptor Strike 37.6)", function()
        local c = hw.Survival.character()
        c.talents = { [440529] = 2, [19416] = 2 }
        local H = headless.new({ character = c, pack = "Survival (wowsims.com)" })
        local I, VS, S = H.ns.VirtualStateInternal, H.ns.VirtualState, H.Hekili.State
        local t = H.ctl.now + 1
        assert.is_true(headless.cycle(H, t))
        VS.Drain(t)
        S.reset("Primary", true)
        local function r(x)
            return math.floor(x * 1000 + 0.5) / 1000
        end
        assert.are.same({ 2, 2, 37.6, 37.6 }, {
            S.talent.resourcefulness.rank,
            S.talent.efficiency.rank,
            r(I.CostOf(I.ab.bySpell[VS.KnownID(H.Hekili.Class.abilities.raptor_strike.id)])),
            r(S.action.raptor_strike.cost),
        })
        assert.are.same({}, H.errors)
    end)
end)

describe("the retired Hunter weave packs", function()
    for _, case in ipairs({
        { "BeastMasteryTurret", 100031, "Beast Mastery (wowsims.com)", "Beast Mastery Turret (wowsims.com)" },
        { "MarksmanshipTurret", 100032, "Marksmanship (wowsims.com)", "Marksmanship Turret (wowsims.com)" },
    }) do
        local world, id, old, new = case[1], case[2], case[3], case[4]
        it("moves a profile that picked " .. old .. " to " .. new .. " with a one-time notice", function()
            local hw = require("Forever.helpers.hunter_world")
            local saved = {
                profiles = {
                    Default = {
                        packs = {
                            [old] = { builtIn = true, spec = id, version = 1, date = 1, lists = {}, profile = "" },
                        },
                        specs = { [id] = { package = old, packManual = true } },
                    },
                },
            }
            local lines = {}
            local H = headless.new({ -- no pack forced: the spec's own (the build's talents pick it)
                character = hw[world].character(),
                saved = saved,
                beforeLogin = function(core)
                    core.Print = function(_, m)
                        lines[#lines + 1] = m
                    end
                    core.Notify = function() end
                end,
            })
            assert.are.same({}, H.loadErrors)
            local p = H.Hekili.DB.profile
            assert.is_nil(rawget(p.packs, old))
            assert.are.equal(new, p.specs[id].package)
            assert.is_nil(p.specs[id].packManual)
            H.RunTimers(H.ctl.now + 6)
            local said = table.concat(lines, "\n")
            assert.is_truthy(said:find(old .. "|r priority was retired", 1, true), said)
            assert.is_truthy(said:find("runs |cFFFFD100" .. new .. "|r", 1, true), said) -- names the replacement
            assert.is_falsy(said:find("default priority", 1, true), said)
            lines = {}
            H.Hekili:RestoreDefaults() -- the next login: nothing retired is left to say
            H.RunTimers(H.ctl.now + 12)
            assert.is_falsy(table.concat(lines, "\n"):find("retired", 1, true))
        end)

        it("says nothing to a profile that never picked " .. old .. " (the pack still leaves)", function()
            local hw = require("Forever.helpers.hunter_world")
            local saved = {
                profiles = {
                    Default = {
                        packs = {
                            [old] = { builtIn = true, spec = id, version = 1, date = 1, lists = {}, profile = "" },
                        },
                    },
                },
            }
            local lines = {}
            local H = headless.new({
                character = hw[world].character(),
                saved = saved,
                beforeLogin = function(core)
                    core.Print = function(_, m)
                        lines[#lines + 1] = m
                    end
                    core.Notify = function() end
                end,
            })
            assert.are.same({}, H.loadErrors)
            assert.is_nil(rawget(H.Hekili.DB.profile.packs, old))
            H.RunTimers(H.ctl.now + 6)
            assert.is_falsy(table.concat(lines, "\n"):find("retired", 1, true))
        end)
    end
end)
