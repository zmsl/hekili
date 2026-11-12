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
    bestial_wrath = { { 19574 }, 0, 120, "off" },
    serpent_sting = { { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295 }, 250, 0, "spell" },
    arcane_shot = { { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 }, 190, 6, "spell" },
    summon_hawk = { { 1293241, 1293525, 1293526, 1293527 }, 190, 6, "spell" },
    aimed_shot = { { 19434, 20900, 20901, 20902, 20903, 20904 }, 310, 6, "spell" },
    multi_shot = { { 2643 }, 0.139, 6, "spell" },
    sniper_shot = { { 1310687, 1310785, 1310786 }, 365, 15, "spell" },
    raptor_strike = { { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 }, 100, 6, "off" },
    mongoose_bite = { { 1495, 14269, 14270, 14271 }, 65, 5, "spell" },
    strider_kick = { { 1317257 }, 0.0581, 8, "spell" },
    wing_clip = { { 2974, 1310180, 14267, 14268 }, 80, 0, "spell" },
    -- wowsims's Melee Weave casts it in melee range (category cooldown 30 s, SpellCooldowns)
    immolation_trap = { { 13795, 14302, 14303, 14304, 14305 }, 245, 30, "spell" },
}

local function idsOf(a)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
        out[#out + 1] = id
    end
    return out
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
        assert.are.equal(18, n)
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
        assert.are.same({ 7.94, 7.94, 0.5 }, seed("beast_mastery")) -- Bestial Discipline
        assert.are.same({ 15.88, 0, 0 }, seed("marksmanship"))
        assert.are.same({ 15.88, 0, 0 }, seed("survival"))
        assert.are.same({ aura = "resourcefulness", share = 0.5 }, r.models.resourcefulness)
        assert.are.same({ aura = "rapid_recuperation", share = 0.5 }, r.models.rapid_recuperation)
        assert.are.same(1242688, w.auras.resourcefulness.id)
        assert.are.same(1242512, w.auras.rapid_recuperation.id)
        assert.are.same({ 2, 1223987, 2 }, w.talents.rapid_recuperation)
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
    end)

    it("models the target's Hunter's Mark and Serpent Sting, Rapid Fire, and one aspect at a time", function()
        for _, case in ipairs({
            { "hunters_mark", { "hunters_mark" }, {} },
            { "serpent_sting", { "serpent_sting" }, {} },
            { "rapid_fire", { "rapid_fire" }, {} },
            { "aspect_of_the_hawk", { "aspect_of_the_hawk" }, { "aspect_of_the_beast", "aspect_of_the_cheetah" } },
            { "aspect_of_the_beast", { "aspect_of_the_beast" }, { "aspect_of_the_hawk", "aspect_of_the_cheetah" } },
            { "aspect_of_the_cheetah", { "aspect_of_the_cheetah" }, { "aspect_of_the_hawk", "aspect_of_the_beast" } },
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
    -- price, their percents added (one SPELLMOD_COST percent each). wowsims's logs: the 2/2 Resourcefulness builds pay
    -- 40 Raptor Strike, 26 Mongoose Bite, 32 Wing Clip, 98 Immolation Trap, 39.6 Strider Kick; the 2/5 Efficiency BM
    -- build 94 Raptor Strike, 75.2 Wing Clip, 178.6 Arcane Shot, 235 Serpent Sting, 224.66 Multi-Shot (of 239).
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
                out[#out + 1] = math.floor(ld.run(w.abilities[key].spend, e) * 100000 + 0.5) / 100000
            end
            return out
        end
        -- raptor, bite, clip, trap, kick, arcane, sting, multi, aimed, hawk, mark, rapid fire
        assert.are.same({ 100, 65, 80, 245, 0.0581, 190, 250, 0.139, 310, 190, 60, 100 }, costs(0, 0))
        assert.are.same({ 70, 45.5, 56, 171.5, 0.04067, 190, 250, 0.139, 310, 190, 60, 100 }, costs(1, 0))
        assert.are.same({ 40, 26, 32, 98, 0.02324, 190, 250, 0.139, 310, 190, 60, 100 }, costs(2, 0))
        -- Efficiency on Strider Kick since hotfix 113554 (19416's mask, wowsims)
        assert.are.same({ 94, 61.1, 75.2, 245, 0.05461, 178.6, 235, 0.13066, 291.4, 178.6, 60, 100 }, costs(0, 2))
        assert.are.same({ 34, 22.1, 27.2, 98, 0.01975, 178.6, 235, 0.13066, 291.4, 178.6, 60, 100 }, costs(2, 2))
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
        assert.are.same(
            { "Beast Mastery (wowsims.com)", "Marksmanship (wowsims.com)", "Survival (wowsims.com)" },
            names
        )
        assert.is_truthy(src:find('spec:RetirePacks({ "BeastMastery", "Marksmanship", "Survival" })', 1, true))
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
        for name, p in pairs(packs) do
            for list, entries in pairs(p.lists) do
                for i, e in ipairs(entries) do
                    local where = name .. " " .. list .. " " .. i
                    local window = e.action == "open_window" or e.action == "close_window"
                    assert.is_true(
                        e.action == "call_action_list" or window or cls.abilities[e.action] ~= nil or racials[e.action],
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
                            assert.is_true(cls.pets[key] ~= nil, where .. ": pet " .. key)
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
        H = headless.new({ character = character(), pack = "Beast Mastery (wowsims.com)" })
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
        H = headless.new({ character = c, pack = "Beast Mastery (wowsims.com)" })
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
        H.Hekili.DB.profile.packs["Beast Mastery (wowsims.com)"].lists = { precombat = {}, default = parsed }
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
        H = headless.new({ character = c, pack = "Beast Mastery (wowsims.com)" })
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
            if not l:find("max%(") then -- ParseActionList splits a line at its commas: the weave arm's max(a,b) stays out
                local parsed = H.Hekili:ParseActionList(l)
                parsed[1].enabled = true
                list[#list + 1] = parsed[1]
            end
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
