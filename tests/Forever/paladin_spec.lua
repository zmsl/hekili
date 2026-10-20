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

-- `talent` with the ranks in `ranks` ({ key = rank }), every other talent at 0.
local function talents(ranks)
    return setmetatable({}, {
        __index = function(_, k)
            local n = ranks[k] or 0
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
            assert.are.same(
                { want[2], want[3], want[4] },
                { ld.run(a.spend, e) or 0, ld.run(a.cooldown, e), a.gcd },
                key
            )
            assert.are.equal("function", type(a.known), key)
        end
        assert.are.equal(15, n)
        assert.are.equal("PALADIN", w.class)
        assert.is_nil(w.options)
    end)

    it("places every DB2 talent in a tree and keeps the Forever-only ones at tree 0", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 5, 14, 15, 15 }, n)
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
        e.talent = talents({ twist_of_light = 1 })
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

    it(
        "shortens Judgement's cooldown 1 s a rank of Improved Judgement (Forever DB2 25956: misc 11, -1000 ms)",
        function()
            local j = w.abilities.judgement
            local e = ld.env(w)
            assert.are.equal(10, ld.run(j.cooldown, e))
            e.talent = rank(2)
            assert.are.equal(8, ld.run(j.cooldown, e)) -- wowsims's log of the 2/2 build: Judgements 8 s apart
        end
    )

    it("cuts Consecration's, Hammer of Wrath's and Exorcism's cost 20% a rank of Holy Conduit (DB2 1237268)", function()
        for key, top in pairs({ consecration = 20924, hammer_of_wrath = 24239, exorcism = 10314 }) do
            w.game.known[top] = true
            local e = ld.env(w)
            local base = ld.run(w.abilities[key].spend, e)
            e.talent = talents({ holy_conduit = 2 })
            -- wowsims's log of the 2/2 build: Consecration rank 5 costs 339 of 565
            assert.are.equal(base * 0.6, ld.run(w.abilities[key].spend, e), key)
        end
    end)

    it("cuts every cost but Hammer of Wrath's 2% a rank of Benediction (DB2 20101: -10 at 5/5)", function()
        for _, id in ipairs({ 20920, 10333, 20924, 24239 }) do
            w.game.known[id] = true
        end
        local e = ld.env(w)
        e.talent = talents({ benediction = 5, twist_of_light = 1, holy_conduit = 2 })
        -- wowsims's log of the Twist of Light build: Seal of Command 151.2, Holy Strike 18, Consecration 305.1
        assert.is_true(math.abs(ld.run(w.abilities.seal_of_command.spend, e) - 151.2) < 1e-9)
        assert.is_true(math.abs(ld.run(w.abilities.holy_strike.spend, e) - 18) < 1e-9)
        assert.is_true(math.abs(ld.run(w.abilities.consecration.spend, e) - 305.1) < 1e-9)
        assert.is_true(math.abs(ld.run(w.abilities.hammer_of_wrath.spend, e) - 425 * 0.6) < 1e-9)
        assert.is_true(math.abs(ld.run(w.abilities.judgement.spend, e) - 0.06 * 0.9) < 1e-9)
    end)

    it(
        "refunds 60% of the seal's base cost x (2 - its cost multiplier) at Judgement with Sanctified Judgement 3/3",
        function()
            w.game.known[20920] = true
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                e.talent = talents({ benediction = 5, twist_of_light = 1, sanctified_judgement = 3 })
                e.buff = buffs({ seal_of_command = true })
                ld.run(w.abilities.judgement[field], e)
                -- wowsims's log: "Gained 161.280 mana from {SpellID: 1311074}" = 210 x (2 - 0.72) x 0.6
                assert.are.equal(1, #e.gained, field)
                assert.is_true(math.abs(e.gained[1][1] - 161.28) < 1e-9, field)
                assert.are.equal("mana", e.gained[1][2], field)
                e = ld.env(w)
                e.talent = talents({ sanctified_judgement = 2 }) -- a chance under 100%: no refund believed
                e.buff = buffs({ seal_of_command = true })
                ld.run(w.abilities.judgement[field], e)
                assert.are.same({}, e.gained, field)
            end
        end
    )

    it("casts the 879 ranks of Exorcism only at an Undead or Demon target; the 415068 ranks at any", function()
        local x = w.abilities.exorcism
        w.game.known[10314] = true
        assert.are.same({ "undead", "demon" }, ld.run(x.usable_on, ld.env(w)))
        w.game.known[415073] = true
        assert.is_nil(ld.run(x.usable_on, ld.env(w)))
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
        assert.are.equal(1280353, w.auras.consecrated_ground.id) -- the area aura the client shows, not 1310905
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
        for _, name in ipairs({ "Retribution" }) do
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
                    local isList = e.action == "run_action_list" or e.action == "call_action_list"
                    -- use_items is Hekili's `all` (Hekili_Shared/Shared/Items.lua), as in druid_spec
                    assert.is_true(cls.abilities[e.action] ~= nil or isList or e.action == "use_items", where)
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

    it("Protection (wowsims.com): Seal of Fury and Holy Shield at tier 2 (the retired list's tiers)", function()
        local _, sof = line("Protection (wowsims.com)", "default", "seal_of_fury")
        local _, hs = line("Protection (wowsims.com)", "default", "holy_shield")
        assert.are.same({ 2, 2 }, { sof.focus, hs.focus })
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

    -- (plan "Open after Day 4", the mana bound; central fix 8) Mana is secret even out of combat, so nothing measures it:
    -- the belief assumes a fresh boot at rest, the bound too (`mana.pct` full), until a measurement says less (a short
    -- answer below it).
    it("reads mana.pct full on a fresh boot and keeps the bound full over a rest out of combat", function()
        local t0 = H.ctl.now
        assert.is_true(headless.cycle(H, t0 + 1))
        assert.is_true(H.Hekili.State.mana.pct > 90)
        for t = t0 + 2, t0 + 60 do
            assert.is_true(headless.cycle(H, t))
        end
        assert.are.equal(5000, H.Hekili.Client.UnitPower("player", 0)) -- the facade's answer: the bound, full
        assert.is_true(H.Hekili.State.mana.pct > 90) -- the state's, as of Hekili's last state reset
        assert.are.same({}, H.errors)
    end)
end)
