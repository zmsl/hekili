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
    riposte = { { 14251 }, 10, 6, "off" }, -- off the GCD (DB2); owner R70: on the Combat priority, in the parry window
    ambush = { { 8676, 8724, 8725, 11267, 11268, 11269 }, 60, 0, "totem" },
    garrote = { { 703, 8631, 8632, 8633, 11289, 11290 }, 50, 0, "totem" },
    mutilate = { { 399956, 1241582, 1241584 }, 60, 0, "totem" },
    hemorrhage = { { 16511 }, 35, 0, "totem" },
    ghostly_strike = { { 14278 }, 40, 20, "totem" },
    shank = { { 1329283, 1329549 }, 5, 10, "totem" },
    death_mark = { { 1316709, 1325756, 1325757, 1325758 }, 25, 10, "totem" },
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
            "death_mark",
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
                assert.are.same(
                    { want[2], want[3], want[4] },
                    { ld.run(a.spend, e) or 0, ld.run(a.cooldown, e), a.gcd },
                    key
                )
                assert.are.equal("function", type(a.known), key)
            end
        end
        assert.are.equal(22, n)
        assert.are.same({ 8928, 8927, 8926, 6950, 6949, 6947 }, w.abilities.instant_poison.items)
        assert.are.same({ 20844, 8985, 8984, 2893, 2892 }, w.abilities.deadly_poison.items)
        assert.are.equal("cooldowns", w.abilities.vanish.toggle) -- the native Cooldowns toggle (APL usability audit B)
        assert.are.equal("ROGUE", w.class)
        assert.is_nil(w.options)
    end)

    it("places every talent in a tree (wowsims/forever's logs place the re-pin's new ones)", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 0, 17, 19, 18 }, n) -- Forever's tree (trees/rogue.json)
    end)

    it("models the talent-modified costs, floored at 0", function()
        e.talent = rank(2)
        local function at(key)
            return ld.run(w.abilities[key].spend, e)
        end
        -- Dirty Deeds -10 a rank; Flawless Execution -15 (one rank); Improved Expose Armor {-5, -10} and Efficient
        -- Strikes {-3, -5} by rank, the latter on Sinister Strike and Hemorrhage (the logs: 40 and 30 at 2/2;
        -- wowsims/forever 4b0030a44b)
        local keys = { "sinister_strike", "eviscerate", "expose_armor", "garrote", "hemorrhage" }
        local function all()
            local out = {}
            for i, k in ipairs(keys) do
                out[i] = at(k)
            end
            return out
        end
        assert.are.same({ 40, 5, 15, 30, 30 }, all()) -- Eviscerate: rank 2 is past Flawless Execution's max (1)
        e.talent = rank(1) -- RL5: no rank past a talent's max
        assert.are.same({ 42, 20, 20, 40, 32 }, all())
    end)

    it("makes Shank an energy strike with Flash of Steel's curve, Venom's buff, and no combo point", function()
        local a = w.abilities.shank
        assert.are.same({ 5, 10 }, { ld.run(a.spend, e), ld.run(a.cooldown, e) })
        e.talent = rank(5)
        assert.are.equal(8, ld.run(a.cooldown, e)) -- 10 s - 0.4 s a rank
        for _, field in ipairs({ "now", "handler" }) do
            for _, known in ipairs({ { 1329283 }, { 1329283, 1329549 } }) do
                w.game.known = {}
                for _, id in ipairs(known) do
                    w.game.known[id] = true
                end
                local env = ld.env(w)
                env.talent = rank(5)
                ld.run(a[field], env)
                -- 15 (rank 1) or 25 (rank 2) energy, +3 a Flash of Steel rank
                assert.are.same({ { (#known == 2 and 25 or 15) + 15, "energy" } }, env.gained, field)
                assert.are.same({ "venom" }, env.applied, field)
            end
        end
        w.game.known = { [1329283] = true }
        local env = ld.env(w)
        env.talent = rank(0)
        ld.run(a.now, env)
        assert.are.same({ { 15, "energy" } }, env.gained)
        assert.are.same({}, env.applied)
    end)

    it("makes Death Mark a finisher that marks the target for 6 s", function()
        assert.are.same({ 6, 1325758 }, { w.auras.death_mark.duration, w.auras.death_mark.id })
        assert.are.same({ 1325758, 1316709, 1325756, 1325757 }, idsOf(w.auras.death_mark))
        assert.is_true(w.abilities.death_mark.missable)
        assert.is_true(w.abilities.death_mark.refundOnAvoid)
    end)

    it("makes the finishers no ladder rungs, unusable without a combo point", function()
        for _, key in ipairs({ "eviscerate", "slice_and_dice", "rupture", "expose_armor", "death_mark" }) do
            local a = w.abilities[key]
            assert.is_false(a.ladder, key)
            e.combo_points.current = 0
            assert.is_false((ld.run(a.usable, e)), key)
            e.combo_points.current = 1
            assert.is_true((ld.run(a.usable, e)), key)
        end
        assert.is_nil(w.abilities.sinister_strike.ladder)
    end)

    it(
        "sets the finishers' durations by combo points; Relentless Strikes refunds 25 only at 5 ranks and 5 points",
        function()
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
                local rs5 = setmetatable({}, { -- Improved Slice and Dice 1, Relentless Strikes 5
                    __index = function(_, k)
                        local n = k == "relentless_strikes" and 5 or 1
                        return { rank = n, enabled = true }
                    end,
                })
                s = run("slice_and_dice", 5, field, rs5)
                assert.is_true(math.abs(s.durations.slice_and_dice - 21 * 1.15) < 1e-9, field)
                assert.are.same({ { 25, "energy" } }, s.gained, field)
                assert.are.same({}, run("slice_and_dice", 4, field, rs5).gained, field)
                assert.are.same({}, run("slice_and_dice", 5, field, rank(4)).gained, field) -- 4 ranks: chance, not certain
                assert.are.equal(16, run("rupture", 5, field).durations.rupture, field)
            end
            -- the sim spends the points; the belief's poll reads them (no `now` spend)
            assert.are.same({ { 3, "combo_points" } }, run("eviscerate", 3, "handler").spent)
            assert.are.same({}, run("eviscerate", 3, "now").spent)
        end
    )

    -- Blood Splatter (1329256, DB2 effects: duration +9000 ms on Garrote's class mask 256, +6000 ms on Rupture's 1048576;
    -- wowsims's logs: Garrote 27 s in Assassination and Subtlety, a 3-point Rupture 18 s in Subtlety)
    it("lengthens Garrote by 9 s and Rupture by 6 s with Blood Splatter", function()
        local function run(key, cp, field, n)
            local env = ld.env(w)
            env.talent = rank(n)
            env.combo_points.current = cp
            ld.run(w.abilities[key][field], env)
            return env.durations
        end
        for _, field in ipairs({ "now", "handler" }) do
            assert.are.equal(18, run("garrote", 0, field, 0).garrote, field)
            assert.are.equal(27, run("garrote", 0, field, 1).garrote, field)
            assert.are.equal(12, run("rupture", 3, field, 0).rupture, field)
            assert.are.equal(18, run("rupture", 3, field, 1).rupture, field)
        end
    end)

    it("opens from Stealth, Vanish or a Ghostly Strike, the opener breaking them", function()
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
        assert.is_true(usable("ambush", { ghostly_strike_next = true }))
        assert.is_true(usable("garrote", { ghostly_strike_next = true }))
        assert.is_true(usable("garrote", { vanish = true }))
        ld.run(w.abilities.ambush.now, e)
        assert.are.same({ "stealth", "vanish", "ghostly_strike_next", "cold_blood" }, e.removed)
        assert.is_true(w.abilities.garrote.missable)
        assert.is_true(w.abilities.rupture.missable)
        assert.is_true(w.abilities.hemorrhage.missable)
        assert.is_true(w.auras.stealth.isStealthed and w.auras.vanish.isStealthed)
        assert.are.same({ 1784, 1785, 1786, 1787 }, idsOf(w.auras.stealth))
        assert.are.same({ 11327, 11329 }, idsOf(w.auras.vanish))
    end)

    it("gives the next Ambush or Garrote from a Ghostly Strike's cast, 7 s, one charge", function()
        assert.are.same({ 1329326, 7, 1 }, {
            w.auras.ghostly_strike_next.id,
            w.auras.ghostly_strike_next.duration,
            w.auras.ghostly_strike_next.max_stack,
        })
        for _, field in ipairs({ "now", "handler" }) do
            local env = ld.env(w)
            ld.run(w.abilities.ghostly_strike[field], env)
            assert.are.same({ "ghostly_strike", "ghostly_strike_next" }, env.applied, field)
        end
        e.removed = {}
        ld.run(w.abilities.garrote.now, e)
        assert.are.same({ "stealth", "vanish", "ghostly_strike_next" }, e.removed)
    end)

    -- L139: the window the client's usability answer opens (Riposte usable only in the 5 s after a parry).
    it("opens the Riposte window on the client's usability flip, 5 s, closing when it flips back", function()
        local win = w.windows.riposte
        assert.are.same({ 5, true }, { win.duration, win.close_on_false })
        local function evaluates(usable)
            w.game.usable[14251] = usable
            return win.evaluator()
        end
        assert.is_false(evaluates({ true, false })) -- no talent: not known
        w.game.known[14251] = true
        assert.is_false(evaluates({ false, false }))
        assert.is_true(evaluates({ true, false }))
        assert.is_true(evaluates({ false, true })) -- short only of energy: still the window
        assert.is_false(evaluates({ false, false }))
        -- the cast closes it, in the belief (now) and in the forecast (handler)
        for _, field in ipairs({ "now", "handler" }) do
            local env = ld.env(w)
            ld.run(w.abilities.riposte[field], env)
            assert.are.same({ "riposte" }, env.closed, field)
        end
    end)

    it("doubles energy regen while Adrenaline Rush is up (a regen mult), combo points and energy bare", function()
        assert.are.same({ 4, 3 }, w.order)
        assert.are.same({ adrenaline_rush = { aura = "adrenaline_rush", mult = 2 } }, w.resources[3].models)
        assert.are.equal(15, w.auras.adrenaline_rush.duration)
    end)

    it("reminds of poisons from the bags only, the sim enchanting the weapon", function()
        local ip = w.abilities.instant_poison
        -- buff consumables: under Potions, like the shared mana and energy ones (user, 2026-10-21)
        assert.are.same({ "potions", "potions" }, { ip.toggle, w.abilities.deadly_poison.toggle })
        assert.is_false((ld.run(ip.usable, e)))
        w.game.bags[8927] = 3
        assert.are.same({ true, 8927 }, { (ld.run(ip.usable, e)), (ip.item()) })
        ld.run(ip.handler, e)
        ld.run(w.abilities.deadly_poison.handler, e)
        assert.are.same({ "instant_poison", "main_hand_enchant", "deadly_poison", "off_hand_enchant" }, e.applied)
        -- 30 minutes and a 3 s cast (DB2 70707: Effect 360's 1800, the apply spells' cast_ms 3000; in-game check L37)
        for k, d in pairs(e.durations) do
            assert.are.equal(1800, d, k)
        end
        for _, k in ipairs({ "instant_poison", "deadly_poison" }) do
            local a = w.abilities[k]
            assert.are.same({ 3, true, k }, { a.cast, a.essential, a.nobuff }, k) -- upstream retail's
        end
    end)

    -- Enchant IDs: DB2 70707 SpellEffect.EffectMiscValue_0 of each apply spell's Effect 360, lowest rank first (weapon
    -- buffs review §1). Either hand: no `weaponEnchant`.
    it("declares the five poisons as weapon-enchant auras by their enchant IDs", function()
        local POISONS = {
            instant_poison = { 323, 324, 325, 623, 624, 625 },
            deadly_poison = { 7, 8, 626, 627, 2630 },
            crippling_poison = { 22, 603 },
            mind_numbing_poison = { 35, 23, 643 },
            wound_poison = { 703, 704, 705, 706 },
        }
        for k, ids in pairs(POISONS) do
            local a = assert(w.auras[k], k)
            assert.are.same({ ids, 1800 }, { a.enchants, a.duration }, k)
            assert.is_nil(rawget(a, "weaponEnchant"), k)
        end
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
        local shared = { thistle_tea = true, blood_fury = true, eureka = true, elunes_light = true, berserking = true }
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

    it("flags Slice and Dice at tier 1 in every pack, and Subtlety's Rupture", function()
        for _, name in ipairs(PACKS) do
            local _, snd = line(name, "slice_and_dice")
            assert.are.equal(1, snd.focus, name)
        end
        local _, r = line("Subtlety (wowsims.com)", "rupture")
        assert.are.equal(1, r.focus) -- Rupture 1 in every pack (focus_roles_spec.lua)
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

    -- Weapon buffs review §4.2: a poison's own aura follows its enchant ID on either hand, through the engine.
    it("reads buff.deadly_poison from its enchant ID on either hand, beside the slot pseudo-aura", function()
        local S, VS, I = H.Hekili.State, H.ns.VirtualState, H.ns.VirtualStateInternal
        local keys = {} -- every `enchants` aura is in both layers
        for _, rec in ipairs(I.def.auras) do
            if rec.enchants then
                keys[#keys + 1] = rec.key
                assert.is_not_nil(H.Hekili.Class.auras[rec.key], rec.key)
            end
        end
        table.sort(keys)
        assert.are.same(
            { "crippling_poison", "deadly_poison", "instant_poison", "mind_numbing_poison", "wound_poison" },
            keys
        )
        local DP = { hasEnchant = true, enchantType = 3, timeLeft = 1700000, charges = 40, enchantID = 2630 }
        local t = H.ctl.now + 1
        for slot, alias in pairs({ [0] = "main_hand_enchant", [1] = "off_hand_enchant" }) do
            H.ctl.enchants[0], H.ctl.enchants[1] = nil, nil
            H.ctl.enchants[slot] = { DP }
            H.Fire("WEAPON_ENCHANT_CHANGED")
            t = t + 1
            assert.is_true(headless.cycle(H, t))
            S.reset("Primary", true)
            assert.are.same(
                { true, true, false },
                { S.buff.deadly_poison.up, S.buff[alias].up, S.buff.instant_poison.up }
            )
            assert.is_true(
                math.abs(S.buff.deadly_poison.remains - (VS.Aura("player", S.buff.deadly_poison.id, t).est - t)) < 0.2
            )
        end
        H.ctl.enchants[1] = nil
        H.Fire("WEAPON_ENCHANT_CHANGED")
        t = t + 1
        assert.is_true(headless.cycle(H, t))
        S.reset("Primary", true)
        assert.is_false(S.buff.deadly_poison.up)
        assert.are.same({}, H.errors)
    end)
end)

-- L90: combo points are bound to one target (owner probes 2026-11-06, memory forever-combo-points-plain). The pool
-- (UnitPower 4) survives a swap; only GetComboPoints("player", "target") is usable. The sim's combo_points.current and
-- the belief's value are the same number at every step (the sim reads the belief through Facade.UnitPower).
describe("Forever Rogue combo points on the current target (L90)", function()
    local POINTS = 4
    local H, S, VS, t

    before_each(function()
        local C = require("Forever.helpers.rogue_world").Combat
        H = headless.new({ character = C.character(), pack = C.PACK })
        assert.are.same({}, H.loadErrors)
        S, VS = H.Hekili.State, H.ns.VirtualState
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.ctl.power[3] = 100
        H.Fire("PLAYER_TARGET_CHANGED")
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        t = H.ctl.now
    end)

    -- The client's pool and its answer for the current target (nil: the pool), an optional event, one refresh; the
    -- sim's value after a reset, checked equal to the belief's.
    local function at(pool, usable, swapTo)
        H.ctl.power[POINTS], H.ctl.comboPoints.target = pool, usable
        if swapTo then
            H.ctl.guid.target = swapTo
            H.Fire("PLAYER_TARGET_CHANGED")
            H.Fire("PLAYER_TARGET_CHANGED") -- twice per swap, as the client fires it
        else
            H.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
        end
        t = t + 0.2
        assert(headless.cycle(H, t))
        S.reset("Primary", true)
        assert.are.equal(VS.Power(POINTS, t).est, S.combo_points.current) -- parity: belief and sim
        return S.combo_points.current
    end

    it("refuses a finisher on a target with 0 usable points while the pool holds 4", function()
        assert.are.equal(0, at(4, 0, "Creature-B"))
        for _, key in ipairs({ "eviscerate", "slice_and_dice", "rupture" }) do
            assert.is_false((S:IsUsable(key)), key)
        end
        assert.are.equal(4, at(4, nil, "Creature-1")) -- back on the combo target
        assert.is_true((S:IsUsable("eviscerate")))
        assert.are.same({}, H.errors)
    end)

    it("follows the owner's probes: swap, swap back, a generator on another target", function()
        assert.are.equal(1, at(1, 1)) -- generator on A: pool 1, usable 1 (2026-11-06 20:58)
        assert.are.equal(0, at(1, 0, "Creature-B")) -- swap to B: 1 / 0
        assert.are.equal(1, at(1, 1, "Creature-1")) -- swap back to A: 1 / 1
        assert.are.equal(0, at(1, 0, "Creature-B"))
        assert.are.equal(1, at(1, 1)) -- generator on B: A's point gone, B's count starts at 1 (measured 2026-11-06)
        assert.are.equal(0, at(1, 0, "Creature-1")) -- A reads 0 on return
        assert.is_false((S:IsUsable("eviscerate"))) -- a finisher at 0 usable points fails in game (measured)
        assert.are.same({}, H.errors)
    end)

    it("reads 0 with no target and on a secret answer", function()
        assert.are.equal(0, at(3, false))
        assert.are.equal(0, at(3, require("Game.State.helpers.fake_api").SECRET))
        assert.are.same({}, H.errors)
    end)
end)

-- Audit item 1: an Assassination Rogue whose energy rate never came plain (a /reload or a build in combat) has
-- regen_combined 0; the forecast window must stay finite (the client raises on x/0, stock Lua gives inf).
describe("Forever Assassination with no plain energy rate", function()
    it("keeps every forecast window finite", function()
        local C = require("Forever.helpers.rogue_world").Assassination
        local H = headless.new({ character = C.character(), pack = C.PACK })
        assert.are.same({}, H.loadErrors)
        local S = H.Hekili.State
        local maxes, set = {}, S.SetConstraint
        S.SetConstraint = function(self, lo, hi)
            maxes[#maxes + 1] = hi
            return set(self, lo, hi)
        end
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.is_true(headless.cycle(H, H.ctl.now + 0.5))
        S.SetConstraint = set
        assert.is_true(S.spec.assassination and true or false)
        assert.are.equal(0, S.energy.regen_combined)
        assert.is_true(#maxes > 0)
        for _, hi in ipairs(maxes) do
            assert.is_true(hi == nil or hi < math.huge, "window " .. tostring(hi))
        end
    end)
end)
