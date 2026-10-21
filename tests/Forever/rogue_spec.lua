-- tests/Forever/rogue_spec.lua: the Forever Rogue class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through the recording stand-in (helpers/load_druid.lua with Rogue.lua), its
-- handlers and `now` lines, the focus lines' conditions, and the class through the real engine (headless.lua): every
-- `now` in VirtualState's context, and the weapon-enchant pseudo-auras (negative IDs) through the engine's event
-- handlers (the Day 1-2 residual). What Hekili does with the rest is verified in game (the checkpoint list).
local ld = require("Forever.helpers.load_druid")
local headless = require("Game.harness.headless")

local FILE = "src/Hekili_Rogue/Rogue.lua"

-- key = { spell IDs in rank order, energy cost with every talent at rank 0, cooldown, gcd }, from the DB2 (`wowdb
-- spell <name>`): the cooldown is the larger of RecoveryTime and CategoryRecoveryTime; gcd "totem" for the 1.0 s
-- StartRecoveryTime, "off" where it is 0.
local KIT = {
    sinister_strike = { { 1752, 1757, 1758, 1759, 1760, 8621, 11293, 11294 }, 45, 0, "totem" },
    backstab = { { 53, 2589, 2590, 2591, 8721, 11279, 11280, 11281, 25300 }, 60, 0, "totem" },
    eviscerate = { { 2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300, 31016 }, 35, 0, "totem" },
    slice_and_dice = { { 5171, 6774 }, 25, 0, "totem" },
    rupture = { { 1943, 8639, 8640, 11273, 11274, 11275 }, 25, 0, "totem" },
    expose_armor = { { 8647, 8649, 8650, 11197, 11198 }, 25, 0, "totem" },
    kick = { { 1766, 1767, 1768, 1769 }, 25, 10, "totem" },
    ambush = { { 8676, 8724, 8725, 11267, 11268, 11269 }, 60, 0, "totem" },
    garrote = { { 703, 8631, 8632, 8633, 11289, 11290 }, 50, 0, "totem" },
    mutilate = { { 1310707, 399956, 1241582, 1241584 }, 60, 0, "totem" },
    hemorrhage = { { 16511 }, 35, 0, "totem" },
    ghostly_strike = { { 14278 }, 40, 20, "totem" },
    venom = { { 1310703 }, 25, 0, "totem" },
    adrenaline_rush = { { 13750 }, 0, 300, "totem" },
    blade_flurry = { { 13877 }, 25, 120, "totem" },
    cold_blood = { { 14177 }, 0, 180, "off" },
    premeditation = { { 14183 }, 0, 120, "off" },
    preparation = { { 14185 }, 0, 600, "totem" },
    vanish = { { 1856, 1857, 1285372 }, 0, 300, "off" },
    stealth = { { 1784, 1785, 1786, 1787 }, 0, 10, "off" },
}

local function idsOf(a)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
        out[#out + 1] = id
    end
    return out
end

local function rank(n)
    return setmetatable({}, {
        __index = function()
            return { rank = n, enabled = n > 0 }
        end,
    })
end

describe("Forever Rogue", function()
    local w, e

    before_each(function()
        w = ld.load(nil, FILE, "ROGUE")
        e = ld.env(w)
    end)

    it("refunds 80% of an avoided ability's energy where wowsims does, per ability", function()
        assert.are.equal(0.8, w.resources[3].meta.refundOnAvoid)
        local yes = {}
        for key, a in pairs(w.abilities) do
            if a.refundOnAvoid then
                yes[#yes + 1] = key
            end
        end
        table.sort(yes)
        assert.are.same({
            "ambush",
            "backstab",
            "eviscerate",
            "expose_armor",
            "garrote",
            "ghostly_strike",
            "hemorrhage",
            "kick",
            "mutilate",
            "rupture",
            "sinister_strike",
        }, yes)
    end)

    it("registers the kit with the DB2's ranks, costs, cooldowns and GCDs, and the two poison reminders", function()
        local n = 0
        for key, a in pairs(w.abilities) do
            if a.item then
                assert.is_true(key == "instant_poison" or key == "deadly_poison", key)
            else
                n = n + 1
                local want = assert(KIT[key], "unexpected ability " .. key)
                assert.are.same(want[1], idsOf(a), key)
                assert.are.same({ want[2], want[3], want[4] }, { ld.run(a.spend, e) or 0, a.cooldown, a.gcd }, key)
                assert.are.equal("function", type(a.known), key)
            end
        end
        assert.are.equal(20, n)
        assert.are.same({ 8928, 8927, 8926, 6950, 6949, 6947 }, w.abilities.instant_poison.items)
        assert.are.same({ 20844, 8985, 8984, 2893, 2892 }, w.abilities.deadly_poison.items)
        assert.are.equal("cooldowns", w.abilities.vanish.toggle) -- the native Cooldowns toggle (APL usability audit B)
        assert.are.equal("ROGUE", w.class)
        assert.is_nil(w.options)
    end)

    it("places every DB2 talent in a tree and keeps the Forever-only ones at tree 0", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 3, 15, 19, 17 }, n)
    end)

    it("models the talent-modified costs, floored at 0", function()
        e.talent = rank(2)
        local function at(key)
            return ld.run(w.abilities[key].spend, e)
        end
        -- rank 1's value x the rank: Flawless Execution -10, Improved Expose Armor -10; the DB2 value as the whole
        -- talent's (wowsims/forever's casts at 2/2: Sinister Strike 40, Garrote 30): Improved Sinister Strike -5,
        -- Dirty Deeds -20
        local keys = { "sinister_strike", "eviscerate", "expose_armor", "garrote" }
        local function all()
            local out = {}
            for i, k in ipairs(keys) do
                out[i] = at(k)
            end
            return out
        end
        assert.are.same({ 40, 15, 5, 30 }, all())
        e.talent = rank(1) -- RL5: no rank past a talent's max
        assert.are.same({ 42.5, 25, 15, 40 }, all())
    end)

    it("takes 3 energy a Thousand Cuts stack off Backstab and Hemorrhage (1310723: misc 14 -3)", function()
        assert.are.same({ 10, 5 }, { w.auras.thousand_cuts.duration, w.auras.thousand_cuts.max_stack })
        e.buff.thousand_cuts.stack = 2
        assert.are.same({ 54, 29, 60 }, {
            ld.run(w.abilities.backstab.spend, e),
            ld.run(w.abilities.hemorrhage.spend, e),
            ld.run(w.abilities.mutilate.spend, e),
        })
    end)

    it("makes the finishers no ladder rungs, unusable without a combo point", function()
        for _, key in ipairs({ "eviscerate", "slice_and_dice", "rupture", "expose_armor", "venom" }) do
            local a = w.abilities[key]
            assert.is_false(a.ladder, key)
            e.combo_points.current = 0
            assert.is_false((ld.run(a.usable, e)), key)
            e.combo_points.current = 1
            assert.is_true((ld.run(a.usable, e)), key)
        end
        assert.is_nil(w.abilities.sinister_strike.ladder)
    end)

    it("sets the finishers' durations by combo points; Relentless Strikes refunds 25 only at 5", function()
        local function run(key, cp, field, talents)
            local env = ld.env(w)
            env.talent = talents or rank(0)
            env.combo_points.current = cp
            ld.run(w.abilities[key][field], env)
            return env
        end
        for _, field in ipairs({ "now", "handler" }) do
            local s = run("slice_and_dice", 1, field)
            assert.are.equal(9, s.durations.slice_and_dice, field)
            s = run("slice_and_dice", 5, field, rank(1)) -- Improved Slice and Dice 1, Relentless Strikes
            assert.is_true(math.abs(s.durations.slice_and_dice - 21 * 1.15) < 1e-9, field)
            assert.are.same({ { 25, "energy" } }, s.gained, field)
            assert.are.same({}, run("slice_and_dice", 4, field, rank(1)).gained, field)
            assert.are.equal(16, run("rupture", 5, field).durations.rupture, field)
            assert.are.equal(15, run("venom", 3, field).durations.venom, field)
        end
        -- the sim spends the points; the belief's poll reads them (no `now` spend)
        assert.are.same({ { 3, "combo_points" } }, run("eviscerate", 3, "handler").spent)
        assert.are.same({}, run("eviscerate", 3, "now").spent)
    end)

    it("opens from Stealth or Vanish only (Ambush also on Cutthroat), the opener breaking them", function()
        local function usable(key, up)
            local env = ld.env(w)
            env.buff = setmetatable({}, {
                __index = function(_, k)
                    return { up = up[k] == true, remains = 0 }
                end,
            })
            return (ld.run(w.abilities[key].usable, env))
        end
        assert.is_false(usable("ambush", {}))
        assert.is_true(usable("ambush", { stealth = true }))
        assert.is_true(usable("ambush", { vanish = true }))
        assert.is_true(usable("ambush", { cutthroat = true }))
        assert.is_false(usable("garrote", { cutthroat = true }))
        assert.is_true(usable("garrote", { vanish = true }))
        ld.run(w.abilities.ambush.now, e)
        assert.are.same({ "stealth", "vanish", "cutthroat", "cold_blood" }, e.removed)
        assert.is_true(w.abilities.garrote.missable)
        assert.is_true(w.abilities.rupture.missable)
        assert.is_true(w.abilities.hemorrhage.missable)
        assert.is_true(w.auras.stealth.isStealthed and w.auras.vanish.isStealthed)
        assert.are.same({ 1784, 1785, 1786, 1787 }, idsOf(w.auras.stealth))
        assert.are.same({ 11327, 11329 }, idsOf(w.auras.vanish))
    end)

    it("puts Cutthroat up from Ambush's usability out of Stealth, timed from its flip", function()
        w.game.known[11269] = true -- Ambush rank 6
        local hook = w.hooks.reset_precast
        local function reset(t, talentRank, usable)
            w.game.usable[11269] = usable
            w.game.now = t
            local env = ld.env(w)
            env.talent = rank(talentRank)
            env.now, env.query_time = t, t
            ld.run(hook, env)
            return env
        end
        assert.are.same({}, reset(10, 1, { false, false }).applied)
        w.events.SPELL_UPDATE_USABLE() -- the flip, at t = 10
        assert.are.same({}, reset(11, 0, { true, false }).applied) -- no talent
        w.game.now = 12
        w.events.SPELL_UPDATE_USABLE() -- the flip, at t = 12
        local env = reset(13, 1, { false, true }) -- short only of energy: the proc
        assert.are.same({ "cutthroat" }, env.applied)
        assert.are.equal(9, env.durations.cutthroat)
    end)

    it("doubles energy regen while Adrenaline Rush is up (a regen mult), combo points and energy bare", function()
        assert.are.same({ 4, 3 }, w.order)
        assert.are.same({ adrenaline_rush = { aura = "adrenaline_rush", mult = 2 } }, w.resources[3].models)
        assert.are.equal(15, w.auras.adrenaline_rush.duration)
    end)

    it("reminds of poisons from the bags only, the sim enchanting the weapon", function()
        local ip = w.abilities.instant_poison
        assert.is_false((ld.run(ip.usable, e)))
        w.game.bags[8927] = 3
        assert.are.same({ true, 8927 }, { (ld.run(ip.usable, e)), (ip.item()) })
        ld.run(ip.handler, e)
        ld.run(w.abilities.deadly_poison.handler, e)
        assert.are.same({ "main_hand_enchant", "off_hand_enchant" }, e.applied)
    end)
end)

-- The wowsims.com packs (generated from wowsims/forever's Rogue APL: tools/wowsims/specs/rogue_*.lua).
describe("Forever Rogue priorities", function()
    local PACKS = { "Combat (wowsims.com)", "Assassination (wowsims.com)", "Subtlety (wowsims.com)" }
    local packs = {}
    setup(function()
        for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", "rogue")) do
            packs[p.name] = p
        end
    end)

    local function line(pack, action)
        for i, e in ipairs(packs[pack].lists.default) do
            if e.action == action then
                return i, e
            end
        end
        error(pack .. ": no " .. action)
    end

    it("keeps the class file's generated blocks in step with APLs/, one wowsims.com pack a spec", function()
        local mp = assert(loadfile("tools/make_pack.lua"))("lib")
        local f = assert(io.open(FILE))
        local src = f:read("*a")
        f:close()
        assert.are.equal(src, (mp.sync(src, mp.load("rogue"))))
        local names = {}
        for name in pairs(packs) do
            names[#names + 1] = name
        end
        table.sort(names)
        assert.are.same({ "Assassination (wowsims.com)", "Combat (wowsims.com)", "Subtlety (wowsims.com)" }, names)
    end)

    it("names only registered abilities, auras, talents and settings", function()
        local w = ld.load(nil, FILE, "ROGUE")
        -- the shared kit's (Hekili_Shared: an item and the races' racials), not the class file's
        local shared = { thistle_tea = true, blood_fury = true, eureka = true }
        local kinds =
            { buff = w.auras, debuff = w.auras, talent = w.talents, settings = w.settings, action = w.abilities }
        for name, p in pairs(packs) do
            for list, entries in pairs(p.lists) do
                for i, e in ipairs(entries) do
                    local where = name .. " " .. list .. " " .. i
                    assert.is_true(w.abilities[e.action] ~= nil or shared[e.action], where .. ": " .. e.action)
                    for kind, key in (e.criteria or ""):gmatch("(%a+)%.([%w_]+)") do
                        if kinds[kind] and not shared[key] then
                            assert.is_not_nil(kinds[kind][key], where .. ": no " .. kind .. " " .. key)
                        end
                    end
                end
            end
        end
    end)

    it("flags Slice and Dice at tier 1 in every pack; Subtlety's Ambush at 1 and Rupture at 2", function()
        for _, name in ipairs(PACKS) do
            local _, snd = line(name, "slice_and_dice")
            assert.are.equal(1, snd.focus, name)
        end
        local _, a = line("Subtlety (wowsims.com)", "ambush")
        local _, r = line("Subtlety (wowsims.com)", "rupture")
        assert.are.same({ 1, 2 }, { a.focus, r.focus })
    end)
end)

-- Through the real engine (headless.lua): a Rogue who knows the whole kit.
describe("Forever Rogue through the engine", function()
    local H

    local function character()
        local w = ld.load(nil, FILE, "ROGUE")
        local known = {}
        for _, a in pairs(w.abilities) do
            if a.id then
                for _, id in ipairs(idsOf(a)) do
                    known[#known + 1] = id
                end
            end
        end
        return {
            class = "ROGUE",
            classID = 4,
            specID = 1488,
            level = 60,
            known = known,
            power = { type = 3, token = "ENERGY", max = 100 },
            speed = { 2.6, 1.8 },
        },
            w
    end

    before_each(function()
        H = headless.new({ character = character(), pack = "Combat (wowsims.com)" })
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

    -- Day 1-2 residual: the enchant pseudo-auras (negative IDs, Hekili_Shared) through the engine's aura and event
    -- handlers: the poison reminders' reads follow the out-of-combat enchant read, and the player's aura and cast
    -- events around them raise nothing.
    it("reads the weapon-enchant pseudo-auras the poison reminders name, through the event handlers", function()
        local S, auras = H.Hekili.State, H.Hekili.Class.auras
        assert.is_true(auras.main_hand_enchant.id < 0 and auras.off_hand_enchant.id < 0)
        local t = H.ctl.now + 1
        assert.is_true(headless.cycle(H, t))
        assert.are.same({ false, false }, { S.buff.main_hand_enchant.up, S.buff.off_hand_enchant.up })
        H.ctl.enchants[0] = {
            { hasEnchant = true, enchantType = 0, timeLeft = 1800000, charges = 0, enchantID = 7 },
        }
        H.Fire("WEAPON_ENCHANT_CHANGED")
        H.Fire("UNIT_AURA", "player")
        H.Fire("UNIT_INVENTORY_CHANGED", "player")
        t = t + 1
        assert.is_true(headless.cycle(H, t))
        assert.are.same({ true, false }, { S.buff.main_hand_enchant.up, S.buff.off_hand_enchant.up })
        assert.is_true(math.abs(S.buff.main_hand_enchant.remains - 1799) < 1.5)
        H.ctl.enchants[0] = nil
        H.Fire("WEAPON_ENCHANT_CHANGED")
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1784) -- Stealth: an aura event path beside them
        H.Fire("UNIT_AURA", "player")
        t = t + 1
        assert.is_true(headless.cycle(H, t))
        assert.is_false(S.buff.main_hand_enchant.up)
        assert.are.same({}, H.errors)
        assert.are.same({}, headless.unexpected(H, "run"))
    end)
end)
