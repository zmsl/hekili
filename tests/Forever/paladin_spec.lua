-- tests/Forever/paladin_spec.lua: the Forever Paladin class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through the recording stand-in (helpers/load_druid.lua with Paladin.lua), its
-- handlers and `now` lines (the seal twist, Judgement and Swift Judgement, Holy Shield's charges), the focus lines, and
-- the class through the real engine (headless.lua): every `now` in VirtualState's context, Holy Shield's charges spent
-- by blocks on us. What Hekili does with the rest is verified in game (the checkpoint list, docs/dev/layout.md).
local ld = require("Forever.helpers.load_druid")
local headless = require("Game.harness.headless")

local FILE = "src/Hekili_Paladin/Paladin.lua"

-- key = { spell IDs in rank order, the top rank's mana cost (a fraction: of the maximum) with every talent at rank 0,
-- cooldown, gcd }, from the DB2 (`wowdb spell <name>`): the cooldown is the larger of RecoveryTime and
-- CategoryRecoveryTime; gcd "spell" for 1.5 s, "totem" for 1.0 s, "off" for 0.
local KIT = {
    seal_of_command = { { 20375, 20915, 20918, 20919, 20920 }, 210, 0, "spell" },
    seal_of_righteousness = {
        { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 },
        200,
        0,
        "spell",
    },
    seal_of_the_crusader = { { 21082, 20162, 20305, 20306, 20307, 20308 }, 160, 0, "spell" },
    seal_of_fury = { { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 }, 200, 0, "spell" },
    judgement = { { 20271 }, 0.06, 10, "off" },
    swift_judgement = { { 1310994 }, 0, 60, "off" },
    hammer_of_wrath = { { 24275, 24274, 24239 }, 425, 6, "totem" },
    holy_strike = { { 679, 678, 1866, 680, 2495, 5569, 10332, 10333 }, 20, 10, "spell" },
    consecration = { { 26573, 20116, 20922, 20923, 20924 }, 565, 8, "spell" },
    exorcism = {
        { 879, 5614, 5615, 10312, 10313, 10314, 415068, 415069, 415070, 415071, 415072, 415073 },
        345,
        15,
        "spell",
    },
    holy_shock = { { 1311606, 20473, 20929, 20930 }, 325, 10, "spell" },
    divine_favor = { { 20216 }, 0.04, 120, "off" },
    holy_shield = { { 20925, 20927, 20928 }, 240, 10, "spell" },
    righteous_fury = { { 25780, 407627 }, 0.3, 0, "spell" },
    retribution_aura = { { 7294, 10298, 10299, 10300, 10301 }, 0, 0, "spell" },
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

-- `buff` with the keys in `up` up.
local function buffs(up)
    return setmetatable({}, {
        __index = function(_, k)
            return { up = up[k] == true, remains = up[k] and 10 or 0 }
        end,
    })
end

describe("Forever Paladin", function()
    local w

    before_each(function()
        w = ld.load(nil, FILE, "PALADIN")
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
            assert.are.same({ want[2], want[3], want[4] }, { ld.run(a.spend, e) or 0, a.cooldown, a.gcd }, key)
            assert.are.equal("function", type(a.known), key)
        end
        assert.are.equal(15, n)
        assert.are.equal(1486, w.specID)
        assert.are.same({ package = "Retribution" }, w.options)
    end)

    it("declares mana under the five-second rule, and the fillers' mana floors off by default", function()
        assert.are.same({ 0, 0 }, { w.settings.consecration_mana.default, w.settings.exorcism_mana.default })
        assert.are.same({ 0 }, w.order)
        assert.are.same({ spirit = 17, mp5 = 2 }, w.resources[0].meta.fsr)
    end)

    it("puts one seal up at a time; with Twist of Light the replaced seal leaves its Echo", function()
        for _, field in ipairs({ "now", "handler" }) do
            local e = ld.env(w)
            e.buff = buffs({ seal_of_command = true, echo_of_righteousness = true })
            e.talent = rank(1)
            ld.run(w.abilities.seal_of_righteousness[field], e)
            -- the old Echo goes (one at a time), the seal's own Echo with it, then the new seal
            assert.are.same({ "seal_of_command", "echo_of_righteousness", "echo_of_righteousness" }, e.removed, field)
            assert.are.same({ "echo_of_command", "seal_of_righteousness" }, e.applied, field)
            e = ld.env(w)
            e.buff = buffs({ seal_of_command = true })
            ld.run(w.abilities.seal_of_fury[field], e) -- no talent: no Echo
            assert.are.same({ { "seal_of_command" }, { "seal_of_fury" } }, { e.removed, e.applied }, field)
            e = ld.env(w)
            e.buff = buffs({ seal_of_fury = true })
            e.talent = rank(1)
            ld.run(w.abilities.seal_of_the_crusader[field], e)
            assert.are.same({ "echo_of_fury", "seal_of_the_crusader" }, e.applied, field)
        end
        assert.is_nil(w.abilities.seal_of_command.ladder) -- mana is a seal's only requirement: its answers are rungs
        local e = ld.env(w)
        e.talent = rank(1)
        w.game.known[20920] = true
        assert.are.equal(210 * 0.8, ld.run(w.abilities.seal_of_command.spend, e)) -- Twist of Light: -20%
    end)

    it("judges only under a seal, leaves the seal up, and Swift Judgement's charge pays it", function()
        local j = w.abilities.judgement
        local e = ld.env(w)
        e.seal_up = false
        assert.is_false((ld.run(j.usable, e)))
        e.seal_up = true
        assert.is_true((ld.run(j.usable, e)))
        assert.is_false(j.ladder)
        e.buff = buffs({ swift_judgement = true })
        assert.are.equal(0, ld.run(j.spend, e))
        for _, field in ipairs({ "now", "handler" }) do
            e = ld.env(w)
            ld.run(j[field], e)
            assert.are.same({ { "swift_judgement" }, {} }, { e.removed, e.applied }, field)
        end
        local cds = {}
        e = ld.env(w)
        e.setCooldown = function(k, v)
            cds[#cds + 1] = { k, v }
        end
        ld.run(w.abilities.swift_judgement.now, e)
        assert.are.same({ { { "judgement", 0 } }, { "swift_judgement" } }, { cds, e.applied })
        local exp = w.exprs.seal_up
        e = ld.env(w)
        assert.is_false(ld.run(exp, e))
        e.buff = buffs({ seal_of_fury = true })
        assert.is_true(ld.run(exp, e))
    end)

    it("gates Hammer of Wrath on the target's health, its cast shortened by Instrument of Law", function()
        local h = w.abilities.hammer_of_wrath
        assert.are.equal(0.2, h.healthGate)
        local e = ld.env(w)
        assert.are.same({ 1, false }, { ld.run(h.cast, e), (ld.run(h.usable, e)) })
        w.game.known[24239] = true
        w.game.usable[24239] = { false, true } -- short only of mana: in the window
        e.talent = rank(1)
        assert.are.same({ 0, true }, { ld.run(h.cast, e), (ld.run(h.usable, e)) })
    end)

    it("gives Holy Shield 4 charges, each block or partial block on us spending one", function()
        local a = w.auras.holy_shield
        assert.are.same({ 4, 10, { BLOCK = true, BLOCKED = true } }, { a.max_stack, a.duration, a.consumedBy })
        local e = ld.env(w)
        local stacks = {}
        e.applyBuff = function(k, d, s)
            stacks[#stacks + 1] = { k, d, s }
        end
        ld.run(w.abilities.holy_shield.now, e)
        assert.are.same({ { "holy_shield", nil, 4 } }, stacks)
        assert.are.same({ 1311703, 1311704, 1311701 }, {
            w.auras.echo_of_command.id,
            w.auras.echo_of_righteousness.id,
            w.auras.echo_of_fury.id,
        })
    end)

    it("marks the target with Consecrated Ground at Consecration; Holy Shock spends Divine Favor", function()
        local e = ld.env(w)
        ld.run(w.abilities.consecration.now, e)
        ld.run(w.abilities.holy_shock.now, e)
        assert.are.same({ { "consecrated_ground" }, { "divine_favor" } }, { e.applied, e.removed })
        assert.are.equal(1310905, w.auras.consecrated_ground.id)
    end)
end)

-- The priorities after wowsims/forever's Paladin APLs (reference only) and their D1 focus tiers.
describe("Forever Paladin priorities", function()
    local packs = {}
    setup(function()
        for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", "paladin")) do
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
        assert.are.equal(src, (mp.sync(src, mp.load("paladin"))))
        for _, name in ipairs({ "Retribution", "Protection" }) do
            assert.is_truthy(packs[name].desc:find("provisional", 1, true), name)
        end
    end)

    it("names only registered abilities, auras, talents and state expressions", function()
        local cls = ld.load(nil, FILE, "PALADIN")
        local kinds = {
            buff = cls.auras,
            debuff = cls.auras,
            talent = cls.talents,
            cooldown = cls.abilities,
            settings = cls.settings,
        }
        for name, p in pairs(packs) do
            for list, entries in pairs(p.lists) do
                for i, e in ipairs(entries) do
                    local where = name .. " " .. list .. " " .. i
                    assert.is_true(cls.abilities[e.action] ~= nil or e.action == "run_action_list", where)
                    for kind, key in (e.criteria or ""):gmatch("(%a+)%.([%w_]+)") do
                        if kinds[kind] then
                            assert.is_not_nil(kinds[kind][key], where .. ": no " .. kind .. " " .. key)
                        end
                    end
                    for word in (e.criteria or ""):gmatch("[%a_]+") do
                        if word == "seal_up" or word == "mainhand_remains" then
                            assert.is_not_nil(cls.exprs[word], where)
                        end
                    end
                end
            end
        end
    end)

    it("Retribution: Hammer of Wrath and the twist seals at tier 1, the swing-gap fillers at tier 2", function()
        local _, how = line("Retribution", "default", "hammer_of_wrath")
        local _, soc = line(
            "Retribution",
            "default",
            "seal_of_command",
            "talent.twist_of_light.enabled&!buff.echo_of_command.up&!buff.seal_of_command.up"
        )
        local _, sor = line(
            "Retribution",
            "default",
            "seal_of_righteousness",
            "talent.twist_of_light.enabled&!buff.echo_of_righteousness.up&!buff.seal_of_righteousness.up"
        )
        local _, con =
            line("Retribution", "default", "consecration", "mainhand_remains>1.5&mana.pct>=settings.consecration_mana")
        local _, exo =
            line("Retribution", "default", "exorcism", "mainhand_remains>1.5&mana.pct>=settings.exorcism_mana")
        local _, j = line("Retribution", "default", "judgement")
        assert.are.same({ 1, 1, 1, 2, 2 }, { how.focus, soc.focus, sor.focus, con.focus, exo.focus })
        assert.is_nil(j.focus)
        local i = line("Retribution", "default", "run_action_list")
        assert.are.equal(1, i)
        line("Retribution", "holy_shock", "holy_shock", "debuff.consecrated_ground.up")
    end)

    it("Protection: Seal of Fury and Holy Shield at tier 2, Righteous Fury before combat", function()
        local _, sof = line("Protection", "default", "seal_of_fury", "!buff.seal_of_fury.up")
        local _, hs = line("Protection", "default", "holy_shield")
        assert.are.same({ 2, 2 }, { sof.focus, hs.focus })
        assert.are.equal("righteous_fury", packs.Protection.lists.precombat[1].action)
    end)
end)

-- Through the real engine (headless.lua): a Paladin who knows the whole kit.
describe("Forever Paladin through the engine", function()
    local H

    local function character()
        local w = ld.load(nil, FILE, "PALADIN")
        local known = {}
        for _, a in pairs(w.abilities) do
            for _, id in ipairs(idsOf(a)) do
                known[#known + 1] = id
            end
        end
        return {
            class = "PALADIN",
            classID = 2,
            specID = 1486,
            level = 60,
            known = known,
            talents = { [1310735] = 1 },
            power = { type = 0, token = "MANA", max = 5000 },
            speed = { 3.6 },
        },
            w
    end

    before_each(function()
        H = headless.new({ character = character(), pack = "Retribution" })
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

    it("twists the seals in the belief: Seal of Command, then Seal of Righteousness leaves Echo of Command", function()
        local VS = H.ns.VirtualState
        local t = H.ctl.now + 1
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 20375)
        assert.is_true(headless.cycle(H, t + 0.1))
        t = t + 2
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 20154)
        assert.is_true(headless.cycle(H, t + 0.1))
        assert.are.same({ false, true, true }, {
            VS.Aura("player", 20375, t + 0.1) ~= nil,
            VS.Aura("player", 20154, t + 0.1) ~= nil,
            VS.Aura("player", 1311703, t + 0.1) ~= nil,
        })
        assert.are.same({}, H.errors)
    end)

    -- (plan "Open after Day 4", the mana bound) Mana is secret even out of combat, so `mana.pct` (the belief's lower
    -- bound) starts near 0 on a fresh boot and climbs with the declared regen's low edge: the research floor of 10 %
    -- holds after a long rest out of combat (5000 at the declared 19 a second x 0.9: about 5 minutes to full).
    it("reads mana.pct near 0 on a fresh boot and the bound full after a long rest out of combat", function()
        local t0 = H.ctl.now
        assert.is_true(headless.cycle(H, t0 + 1))
        assert.is_true(H.Hekili.State.mana.pct < 10)
        for t = t0 + 2, t0 + 360 do
            assert.is_true(headless.cycle(H, t))
        end
        assert.are.equal(5000, H.Hekili.Client.UnitPower("player", 0)) -- the facade's answer: the bound, full
        assert.is_true(H.Hekili.State.mana.pct > 90) -- the state's, as of Hekili's last state reset
        assert.are.same({}, H.errors)
    end)
end)
