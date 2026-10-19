-- tests/Forever/hunter_spec.lua: the Forever Hunter class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through the recording stand-in (helpers/load_druid.lua with Hunter.lua), its
-- handlers and `now` lines (the aspects, the target's debuffs, the shared cooldowns, Summon Hawk's guardians, Raptor
-- Strike's queue, Mongoose Bite's window, the ranged casts), the focus lines, and the class through the real engine
-- (headless.lua): every `now` in VirtualState's context, the hawks counted in the belief and the simulation, the
-- ranged clock after a modelled Auto Shot. What Hekili does with the rest is verified in game (docs/dev/layout.md).
local ld = require("Forever.helpers.load_druid")
local headless = require("Game.harness.headless")

local FILE = "src/Hekili_Hunter/Hunter.lua"

-- key = { spell IDs in rank order, the top rank's mana cost, cooldown, gcd }, from the DB2 (`wowdb spell <name>`): the
-- cooldown is the larger of RecoveryTime and CategoryRecoveryTime; a percent-of-base-mana cost (PowerCostPct) as the
-- fraction the class file declares.
local KIT = {
    auto_shot = { { 75 }, 0, 0, "off" },
    hunters_mark = { { 1130, 14323, 14324, 14325, 1213268 }, 60, 0, "spell" },
    aspect_of_the_hawk = { { 13165, 14318, 14319, 14320, 14321, 14322, 25296 }, 120, 0, "spell" },
    aspect_of_the_beast = { { 13161, 1299445, 1299446, 1299447 }, 110, 0, "spell" },
    rapid_fire = { { 3045 }, 100, 300, "off" },
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
            assert.are.same({ want[2], want[3], want[4] }, { ld.run(a.spend, e) or 0, a.cooldown, a.gcd }, key)
            assert.are.equal("function", type(a.known), key)
        end
        assert.are.equal(15, n)
        assert.are.equal("HUNTER", w.class)
        assert.is_nil(w.options)
        assert.are.equal("cooldowns", w.abilities.rapid_fire.toggle)
    end)

    it("places every DB2 talent in a tree and keeps the Forever-only ones at tree 0", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 0, 16, 14, 16 }, n)
    end)

    it("declares mana under the five-second rule and both mana floors off", function()
        assert.are.same({ 0 }, w.order)
        assert.are.same({ spirit = 15, mp5 = 2 }, w.resources[0].meta.fsr)
        for _, key in ipairs({ "arcane_shot_mana", "wing_clip_mana" }) do
            assert.are.equal(0, w.settings[key].default, key)
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
    end)

    it("models the target's Hunter's Mark and Serpent Sting, Rapid Fire, and one aspect at a time", function()
        for _, case in ipairs({
            { "hunters_mark", { "hunters_mark" }, {} },
            { "serpent_sting", { "serpent_sting" }, {} },
            { "rapid_fire", { "rapid_fire" }, {} },
            { "aspect_of_the_hawk", { "aspect_of_the_hawk" }, { "aspect_of_the_beast" } },
            { "aspect_of_the_beast", { "aspect_of_the_beast" }, { "aspect_of_the_hawk" } },
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
            A.rapid_fire.duration,
            A.quick_shots.id,
            A.quick_shots.duration,
            A.defensive_state.id,
            A.defensive_state.duration,
        })
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
        assert.is_true((ld.run(r.usable, e)))
        ld.run(r.handler, e)
        assert.are.same({ "raptor_strike" }, e.applied)
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

-- The priorities after wowsims/forever's Hunter APLs (reference only), D3 builds and the D1 focus tiers.
describe("Forever Hunter priorities", function()
    local packs = {}
    setup(function()
        for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", "hunter")) do
            packs[p.name] = p
        end
    end)

    local function line(pack, list, action, criteria)
        for i, e in ipairs(packs[pack].lists[list]) do
            if e.action == action and (criteria == nil or e.criteria == criteria) then
                return i, e
            end
        end
        error(pack .. ": no " .. action .. " if " .. tostring(criteria))
    end

    it("keeps the class file's generated blocks in step with APLs/ and marks every pack provisional", function()
        local mp = assert(loadfile("tools/make_pack.lua"))("lib")
        local f = assert(io.open(FILE))
        local src = f:read("*a")
        f:close()
        assert.are.equal(src, (mp.sync(src, mp.load("hunter"))))
        for _, name in ipairs({ "BeastMastery", "Marksmanship", "Survival" }) do
            assert.is_truthy(packs[name].desc:find("provisional", 1, true), name)
        end
    end)

    it("names only registered abilities, auras, settings and the hawk", function()
        local cls = ld.load(nil, FILE, "HUNTER")
        local kinds = { buff = cls.auras, debuff = cls.auras, cooldown = cls.abilities, settings = cls.settings }
        for name, p in pairs(packs) do
            for list, entries in pairs(p.lists) do
                for i, e in ipairs(entries) do
                    local where = name .. " " .. list .. " " .. i
                    assert.is_true(e.action == "call_action_list" or cls.abilities[e.action] ~= nil, where)
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

    it("flags Sniper Shot, Mongoose Bite and Raptor Strike at tier 1, the sting and mark at tier 2", function()
        local _, sniper = line("Marksmanship", "shots", "sniper_shot", "buff.rapid_fire.up||buff.quick_shots.up")
        local _, bite = line("Survival", "melee", "mongoose_bite")
        local _, raptor = line("Survival", "default", "raptor_strike")
        assert.are.same({ 1, 1, 1 }, { sniper.focus, bite.focus, raptor.focus })
        for _, pack in ipairs({ "BeastMastery", "Marksmanship" }) do
            local _, sting = line(pack, "shots", "serpent_sting", "!debuff.serpent_sting.up")
            assert.are.equal(2, sting.focus, pack)
            -- D5: no Aimed or Multi line gates on the auto-shot gap or carries a focus
            for _, key in ipairs({ "aimed_shot", "multi_shot" }) do
                local _, e = line(pack, "shots", key)
                assert.is_nil(e.focus, pack .. " " .. key)
                assert.is_falsy((e.criteria or ""):find("swing", 1, true), pack .. " " .. key)
            end
        end
        for _, pack in ipairs({ "BeastMastery", "Marksmanship", "Survival" }) do
            local _, mark = line(pack, "default", "hunters_mark", "!debuff.hunters_mark.up")
            assert.are.equal(2, mark.focus, pack)
        end
    end)

    it("keeps the shots out of the deadzone and the strikes in melee range (C11, Hekili's in_range)", function()
        for _, pack in ipairs({ "BeastMastery", "Marksmanship" }) do
            line(pack, "default", "call_action_list", "action.auto_shot.in_range")
        end
        line("Survival", "default", "call_action_list", "action.raptor_strike.in_range")
        line("BeastMastery", "shots", "summon_hawk", "pet.hawk.count<2")
        line("Survival", "melee", "summon_hawk", "pet.hawk.count<2")
        line("BeastMastery", "shots", "arcane_shot", "mana.pct>=settings.arcane_shot_mana")
        line("Survival", "melee", "wing_clip", "mana.pct>=settings.wing_clip_mana")
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
        H = headless.new({ character = character(), pack = "BeastMastery" })
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
        assert.are.same({ 2, t + 12 + 18 }, { VS.PetCount("hawk", now) })
        S.reset("Primary", true)
        assert.are.equal(2, S.pet.hawk.count)
        assert.are.same({ 1 }, { (VS.PetCount("hawk", t + 6 + 18 + 0.1)) })
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
end)
