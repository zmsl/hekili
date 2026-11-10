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
    holy_shield = { { 20925, 20927, 20928, 1239570 }, 240, 10, "spell" }, -- rank 4: the owner's in-game tooltip
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

    it("places every talent in a tree (Forever's)", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 0, 17, 17, 17 }, n) -- Forever's tree (trees/paladin.json)
    end)

    it("declares mana under the five-second rule", function()
        assert.are.same({ 0 }, w.order)
        local fsr, e = w.resources[0].meta.fsr, ld.env(w)
        local function seed(key)
            w.state.spec = { [key] = true } -- the pack's functions read state.spec (the file's `spec` is the class)
            return { ld.run(fsr.spirit, e), ld.run(fsr.mp5, e) }
        end
        assert.are.same({ 13.65, 8.25 }, seed("retribution")) -- wowsims's logs: 21.9 outside, 8.25 while casting
        assert.are.same({ 17.38, 0 }, seed("protection"))
        assert.is_nil(fsr.share)
    end)

    it(
        "puts one seal up at a time; Unsealed Wrath's Echoes come from hits, not the seal swap (hotfix 113554)",
        function()
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                e.buff = buffs({ seal_of_command = true, echo_of_righteousness = true })
                e.talent = rank(1)
                ld.run(w.abilities.seal_of_righteousness[field], e)
                -- the old seal goes; no Echo made or spent by the cast (the aura read holds them)
                assert.are.same({ { "seal_of_command" }, { "seal_of_righteousness" } }, { e.removed, e.applied }, field)
                e = ld.env(w)
                e.buff = buffs({ seal_of_command = true })
                ld.run(w.abilities.seal_of_fury[field], e)
                assert.are.same({ { "seal_of_command" }, { "seal_of_fury" } }, { e.removed, e.applied }, field)
            end
            assert.is_nil(w.abilities.seal_of_command.ladder) -- mana is a seal's only requirement: its answers are rungs
            for _, key in ipairs({ "echo_of_command", "echo_of_righteousness", "echo_of_fury" }) do
                assert.are.same({ 15, 3 }, { w.auras[key].duration, w.auras[key].max_stack }, key) -- DB2 rows (hotfix)
            end
            local e = ld.env(w)
            e.talent = talents({ twist_of_light = 1 })
            w.game.known[20920] = true
            assert.are.equal(210, ld.run(w.abilities.seal_of_command.spend, e)) -- Unsealed Wrath: no cost cut
        end
    )

    it(
        "judges only under a seal and leaves the seal up; Swift Judgement is a second Judgement (hotfix 113554)",
        function()
            local j = w.abilities.judgement
            local e = ld.env(w)
            e.seal_up = false
            assert.is_false((ld.run(j.usable, e)))
            e.seal_up = true
            assert.is_true((ld.run(j.usable, e)))
            assert.is_false(j.ladder)
            assert.is_nil(w.auras.swift_judgement) -- no charge: its own 60 s cooldown, no reset (wowsims swift_judgement.go)
            local sj = w.abilities.swift_judgement
            e = ld.env(w)
            e.seal_up = false
            assert.is_false((ld.run(sj.usable, e)))
            e.seal_up = true
            assert.is_true((ld.run(sj.usable, e)))
            for _, a in ipairs({ j, sj }) do
                for _, field in ipairs({ "now", "handler" }) do
                    local cds = {}
                    e = ld.env(w)
                    e.setCooldown = function(k, v)
                        cds[#cds + 1] = { k, v }
                    end
                    ld.run(a[field], e)
                    assert.are.same({ {}, {}, {} }, { e.removed, e.applied, cds }, field)
                end
            end
            local exp = w.exprs.seal_up
            e = ld.env(w)
            assert.is_false(ld.run(exp, e))
            e.buff = buffs({ seal_of_fury = true })
            assert.is_true(ld.run(exp, e))
        end
    )

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
        -- wowsims's log of the Twist of Light build: Holy Strike 18, Consecration 305.1; Seal of Command 210 x 0.9 (the
        -- 20% cut gone with hotfix 113554)
        assert.is_true(math.abs(ld.run(w.abilities.seal_of_command.spend, e) - 189) < 1e-9)
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
                -- wowsims (talents_retribution.go): 210 x (2 - 0.9) x 0.6, the seal's multiplier Benediction's alone
                assert.are.equal(1, #e.gained, field)
                assert.is_true(math.abs(e.gained[1][1] - 138.6) < 1e-9, field)
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

    it(
        "gates Hammer of Wrath on the target's health, its cast 0.2 s shorter a rank of Champion of the Light",
        function()
            local h = w.abilities.hammer_of_wrath
            assert.are.equal(0.2, h.healthGate)
            local e = ld.env(w)
            assert.are.same({ 1, false }, { ld.run(h.cast, e), (ld.run(h.usable, e)) })
            w.game.known[24239] = true
            w.game.usable[24239] = { false, true } -- short only of mana: in the window
            e.talent = rank(1)
            assert.is_true(math.abs(ld.run(h.cast, e) - 0.8) < 1e-9) -- hotfix 113554: 1311084, 5 ranks
            assert.is_true((ld.run(h.usable, e)))
            e.talent = rank(5)
            assert.are.equal(0, ld.run(h.cast, e))
            assert.are.same({ 3, 1311084, 5 }, w.talents.champion_of_the_light)
            assert.is_nil(w.talents.instrument_of_law)
        end
    )

    it("cuts Holy Strike's cooldown to 6 s with Shieldsworn (hotfix 113554, 1328544)", function()
        local e = ld.env(w)
        assert.are.equal(10, ld.run(w.abilities.holy_strike.cooldown, e))
        e.talent = talents({ shieldsworn = 1 })
        assert.are.equal(6, ld.run(w.abilities.holy_strike.cooldown, e))
        assert.are.same({ 2, 1328544, 1 }, w.talents.shieldsworn)
    end)
    -- The owner's in-game tooltips (2026-11-06): four ranks at 100 / 150 / 195 / 240 mana (R31's 195 is rank 3; rank 4,
    -- 1239570, is build 70755's, past our wowsims pin), priced with the Protection preset's talents (no Benediction).
    it("prices Holy Shield's four ranks at the game's 100, 150, 195 and 240", function()
        local e = ld.env(w)
        e.talent = talents({ swift_judgement = 1, holy_shield = 1, holy_shock = 1, shieldsworn = 1 })
        for top, cost in ipairs({ 100, 150, 195, 240 }) do
            for i, id in ipairs({ 20925, 20927, 20928, 1239570 }) do
                w.game.known[id] = i <= top
            end
            assert.are.equal(cost, ld.run(w.abilities.holy_shield.spend, e))
        end
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

    it("keeps the class file's generated blocks in step with APLs/", function()
        local mp = assert(loadfile("tools/make_pack.lua"))("lib")
        local f = assert(io.open(FILE))
        local src = f:read("*a")
        f:close()
        assert.are.equal(src, (mp.sync(src, mp.load("paladin"))))
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
                    -- stoneform: the Dwarf racial (Hekili_Shared/Races), rule 13's line for a tank
                    -- use_items is Hekili's `all` (Hekili_Shared/Shared/Items.lua), as in druid_spec
                    local shared = e.action == "use_items" or e.action == "stoneform"
                    assert.is_true(cls.abilities[e.action] ~= nil or isList or shared, where)
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

    it(
        "Retribution (wowsims.com): Hammer of Wrath and the Unsealed Wrath seals at tier 1, Consecration at 2, Exorcism (a filler) none",
        function()
            local R = "Retribution (wowsims.com)"
            local _, how = line(R, "default", "hammer_of_wrath")
            -- wowsims's refresh lines (Should refresh SoC / SoR), after the recipe's kick-start (no tier)
            local function refresh(action)
                for _, e in ipairs(packs[R].lists.default) do
                    if e.action == action and (e.criteria or ""):find("^talent%.twist_of_light%.enabled&%(%(") then
                        return e
                    end
                end
                error(action)
            end
            local soc, sor = refresh("seal_of_command"), refresh("seal_of_righteousness")
            assert.is_nil(select(2, line(R, "default", "seal_of_command")).focus) -- the kick-start
            local _, con = line(R, "consecration", "consecration")
            local _, exo = line(R, "exorcism", "exorcism")
            assert.are.same({ 1, 1, 1, 2 }, { how.focus, soc.focus, sor.focus, con.focus })
            assert.is_nil(exo.focus)
            assert.is_nil(select(2, line(R, "default", "judgement")).focus)
        end
    )

    it("Protection (wowsims.com): Seal of Fury and Holy Shield at tier 2 (the retired list's tiers)", function()
        local _, sof = line("Protection (wowsims.com)", "default", "seal_of_fury")
        local _, hs = line("Protection (wowsims.com)", "default", "holy_shield")
        assert.are.same({ 2, 2 }, { sof.focus, hs.focus })
    end)

    it("Protection (wowsims.com): Holy Shock reads the Consecrated Ground talent (talentIsKnown 1310905)", function()
        line(
            "Protection (wowsims.com)",
            "default",
            "holy_shock",
            "(!talent.consecrated_ground.enabled||debuff.consecrated_ground.up)"
        )
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
        H = headless.new({ character = character(), pack = "Retribution (wowsims.com)" })
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

    it("twists the seals in the belief: Seal of Command, then Seal of Righteousness, no Echo from the swap", function()
        local VS = H.ns.VirtualState
        local t = H.ctl.now + 1
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 20375)
        assert.is_true(headless.cycle(H, t + 0.1))
        t = t + 2
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 20154)
        assert.is_true(headless.cycle(H, t + 0.1))
        assert.are.same({ false, true, false }, { -- Unsealed Wrath's Echoes come from hits (hotfix 113554)
            VS.Aura("player", 20375, t + 0.1) ~= nil,
            VS.Aura("player", 20154, t + 0.1) ~= nil,
            VS.Aura("player", 1311703, t + 0.1) ~= nil,
        })
        assert.are.same({}, H.errors)
    end)

    -- R15/R16 (re-pin Task 17): Retribution's opener, wowsims's "Move to melee" sequences move1 (Seal of Command) and
    -- move2 (Seal of Righteousness), as stepped windows: open in combat until the fight's first main-hand swing (the
    -- arrival in melee), each under its sequence's talent condition; closed out of combat; open again next fight.
    it("opens the opener window of the talents at the pull, closes it at the first main-hand swing", function()
        local function fight(talents, want1, want2)
            local c = character()
            c.talents = talents
            H = headless.new({ character = c, pack = "Retribution (wowsims.com)" })
            assert.are.same({}, H.loadErrors)
            local F = H.ns.Facade
            local t = H.ctl.now + 1
            assert.is_true(headless.cycle(H, t))
            assert.are.same({ false, false }, { (F.Window("move1")), (F.Window("move2")) }) -- out of combat
            for _ = 1, 2 do
                t = t + 1
                H.ctl.now, H.ctl.combat = t, true
                H.Fire("PLAYER_REGEN_DISABLED")
                assert.is_true(headless.cycle(H, t + 0.1))
                assert.are.same({ want1, want2 }, { (F.Window("move1")), (F.Window("move2")) })
                t = t + 2
                H.ctl.now = t
                H.Fire("PLAYER_SWING", 3.6, 0) -- the first main-hand swing: the arrival in melee
                assert.is_true(headless.cycle(H, t + 0.1))
                assert.are.same({ false, false }, { (F.Window("move1")), (F.Window("move2")) })
                t = t + 2
                H.ctl.now, H.ctl.combat = t, false
                H.Fire("PLAYER_REGEN_ENABLED")
                assert.is_true(headless.cycle(H, t + 0.1))
            end
            assert.are.same({}, H.errors)
        end
        fight({ [1310735] = 1, [20375] = 1 }, true, false) -- Unsealed Wrath and Seal of Command: move1
        fight({ [1310735] = 1 }, false, true) -- no Seal of Command: move2
        fight({ [20375] = 1 }, true, true) -- Seal of Command without Unsealed Wrath: both (wowsims's conditions)
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

-- R41 (owner, 2026-11-05): a low-level Retribution (Seal of Righteousness only, no Seal of Command) re-seals when the
-- seal has under two GCDs left (gcd.max 1.5: 3 s), never earlier (the old `remains<24` refresh filled idle windows).
describe("Retribution (wowsims.com) below Seal of Command", function()
    -- shown now (wait 0) at `before` s left, not at `after`; `haste` the client's UnitSpellHaste percent
    local function probe(haste, gcdMax, after, before)
        local H = headless.new({
            character = {
                class = "PALADIN",
                classID = 2,
                specID = 1486,
                level = 10,
                known = { 20154 },
                power = { type = 0, token = "MANA", max = 5000 },
                speed = { 3.6 },
            },
            pack = "Retribution (wowsims.com)",
        })
        assert.are.same({}, H.loadErrors)
        H.ctl.spellHaste = haste
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        H.ctl.inRange.target, H.ctl.level.target = true, 10
        H.Fire("PLAYER_TARGET_CHANGED")
        H.Fire("PLAYER_REGEN_DISABLED")
        local t0 = H.ctl.now + 1
        H.ctl.now = t0
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 20154)
        assert.is_true(headless.cycle(H, t0 + 0.1))
        assert.is_true(headless.cycle(H, t0 + 30 - after))
        local gm = H.Hekili.State.gcd.max
        assert.is_true(math.abs(gm - gcdMax) < 1e-6 or error("gcd.max " .. tostring(gm)))
        local r = out.recs[1]
        assert.is_false(r ~= nil and r.actionName == "seal_of_righteousness" and (r.wait or 0) == 0)
        assert.is_true(headless.cycle(H, t0 + 30 - before))
        r = out.recs[1]
        assert.are.same({ "seal_of_righteousness", 0 }, { r and r.actionName, r and r.wait or 0 })
        assert.are.same({}, H.errors)
    end

    it("shows Seal of Righteousness at 2.9 s left, not at 3.1 s (remains<gcd.max*2, gcd.max 1.5)", function()
        probe(0, 1.5, 3.1, 2.9)
    end)

    it("scales with haste: at gcd.max 1.0 (50% spell haste) shown at 1.9 s left, not at 2.1 s", function()
        probe(50, 1.0, 2.1, 1.9)
    end)
end)

-- R8 (re-pin Task 17, spec §2.3): Retribution's opener with the Movement toggle. At the pull the move1 window is up
-- (Seal of Command build, no swing yet): the Judgement chain line `window.move1.next.judgement&(toggle.movement&
-- window.move1.up|action.judgement.in_range)` and a held main-list line (Holy Strike, under the carried gate
-- `(toggle.movement&(window.move1.up|window.move2.up)|action.holy_strike.in_range|...)`) show out of range only with
-- Movement ON; in range they show either way. Ranges: the DB2's (Judgement 0-10, Holy Strike 0-5, Hammer of Wrath
-- 0-30, the seals self).
describe("Retribution (wowsims.com)'s opener and the Movement toggle", function()
    local RANGES = { judgement = { 0, 10 }, holy_strike = { 0, 5 }, hammer_of_wrath = { 0, 30 } }

    -- A world `yd` yards from its target at the pull (Seal of the Crusader up); returns the instance and a function
    -- giving the shown abilities (the queue's records) at the next cycle: each one's first position.
    local function world(yd)
        local w = ld.load(nil, FILE, "PALADIN")
        local known, ranges = {}, {}
        for key, a in pairs(w.abilities) do
            for _, id in ipairs(idsOf(a)) do
                known[#known + 1] = id
                ranges[id] = RANGES[key] or { 0, 0 }
            end
        end
        local H = headless.new({
            character = {
                class = "PALADIN",
                classID = 2,
                specID = 1486,
                level = 60,
                known = known,
                talents = { [1310735] = 1, [20375] = 1 },
                power = { type = 0, token = "MANA", max = 5000 },
                speed = { 3.6 },
                ranges = ranges,
            },
            pack = "Retribution (wowsims.com)",
        })
        assert.are.same({}, H.loadErrors)
        for _, id in ipairs(known) do
            H.ctl.usable[id] = { true, false } -- mana for every press: the belief's floor follows the client's answer
        end
        -- Judgement's cooldown read plain and ready (the fake client's default is secret: an unknown cooldown)
        H.ctl.cooldown[20271] = { isActive = false, isOnGCD = false, startTime = 0, duration = 0 }
        H.ctl.level.target, H.ctl.distance.target = 60, yd
        H.Fire("PLAYER_TARGET_CHANGED")
        local t = H.ctl.now + 1
        H.ctl.now = t
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 20308) -- the pre-pull Seal of the Crusader
        assert.is_true(headless.cycle(H, t + 0.1))
        t = t + 1
        H.ctl.now, H.ctl.combat = t, true
        H.Fire("PLAYER_REGEN_DISABLED")
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        return H,
            function()
                t = math.max(t, H.ctl.now) + 0.2
                assert.is_true(headless.cycle(H, t))
                assert.are.same({}, H.errors)
                local shown = {}
                for i = 1, #out.recs do
                    local r = out.recs[i]
                    if r.actionName then
                        shown[r.actionName] = shown[r.actionName] or i
                    end
                end
                return shown
            end
    end

    local function both(H, pick)
        local on = pick()
        H.Hekili:FireToggle("movement", "off")
        local off = pick()
        H.Hekili:FireToggle("movement", "on")
        return on, off
    end

    it("at 20 yd shows the Judgement chain and the held Holy Strike only with Movement ON", function()
        local H, pick = world(20)
        local on, off = both(H, pick)
        assert.is_true((H.ns.Facade.Window("move1")))
        assert.are.same({ true, true }, { on.judgement ~= nil, on.holy_strike ~= nil })
        assert.are.same({ false, false }, { off.judgement ~= nil, off.holy_strike ~= nil })
    end)

    -- (Holy Strike shows later in the queue either way: the forecast casts Judgement and the seal, the window's last
    -- step, and a closed window releases the carried gate.)
    it("at 8 yd shows the Judgement chain either way", function()
        local on, off = both(world(8))
        assert.are.same({ true, true }, { on.judgement ~= nil, off.judgement ~= nil })
    end)

    it("at 3 yd shows both either way", function()
        local on, off = both(world(3))
        assert.are.same({ true, true }, { on.judgement ~= nil, on.holy_strike ~= nil })
        assert.are.same({ true, true }, { off.judgement ~= nil, off.holy_strike ~= nil })
    end)

    -- The recipe's kick-start (extra): a fight that starts in melee closes the opener at its first swing, before its
    -- Seal of Command; with Unsealed Wrath neither of wowsims's seal lines can fire until one of the two seals is up
    -- (each needs the other's Echo), so the kick-start casts Seal of Command once the Crusader's Judgement is out.
    it("in melee from the pull: Seal of Command after the Crusader's Judgement, never before it", function()
        local H, pick = world(3)
        H.ctl.now = H.ctl.now + 0.5
        H.Fire("PLAYER_SWING", 3.6, 0) -- the opener closes
        local before = pick()
        assert.is_false((H.ns.Facade.Window("move1")))
        assert.are.equal(1, before.judgement) -- Seal of Command only after it (the queue's forecast casts it first)
        assert.is_true((before.seal_of_command or 99) > 1)
        H.ctl.now = H.ctl.now + 0.3
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-j", 20271)
        assert.is_truthy(pick().seal_of_command)
    end)

    -- Review Focus 8 (decision 10, R7): after the first main-hand swing the opener is spent; knocked back out of range,
    -- no move_to_melee line returns (each needs its window, closed for the fight), with Movement ON or OFF, and the
    -- ranged pick is the main list's Judgement (shown out of range: the client's tint).
    it("after the first main-hand swing, back at 20 yd, shows no move_to_melee line", function()
        local H, pick = world(3)
        H.ctl.now = H.ctl.now + 0.5
        H.Fire("PLAYER_SWING", 3.6, 0)
        pick()
        pick() -- past the swing's first 0.1 s (the Judgement line's swing guard, wowsims's WF guard)
        H.ctl.distance.target = 20
        local on, off = both(H, pick)
        assert.are.same({ false, false }, { (H.ns.Facade.Window("move1")), (H.ns.Facade.Window("move2")) })
        assert.are.same({ true, true }, { on.judgement ~= nil, off.judgement ~= nil })
    end)
end)

-- L237/L238: in a dungeon the client hides the target's creature type; Exorcism's 879 ranks (Undead and Demon only)
-- then fall to the client's range answer, a plain nil on a target the spell cannot hit. Asked by the known rank.
describe("Exorcism's 879 ranks with the creature type hidden", function()
    local SECRET = require("Game.State.helpers.fake_api").SECRET

    it("are refused on a plain nil range answer, usable on true; the type decides once known", function()
        local H = headless.new({
            character = {
                class = "PALADIN",
                classID = 2,
                specID = 1486,
                level = 60,
                known = { 879, 5614, 5615, 10312, 10313, 10314 },
                power = { type = 0, token = "MANA", max = 5000 },
                speed = { 3.6 },
            },
            pack = "Retribution (wowsims.com)",
        })
        assert.are.same({}, H.loadErrors)
        assert.are.equal(10314, H.ns.VirtualState.KnownID(879)) -- the facade asks the client by the known rank
        H.ctl.level.target, H.ctl.distance.target, H.ctl.creature.target = 60, 3, SECRET
        H.ctl.ranges[10314] = { 0, 0 } -- the client's plain nil
        H.Fire("PLAYER_TARGET_CHANGED")
        local t = H.ctl.now
        local function usable()
            t = t + 0.2
            H.ctl.now = t
            assert.is_true(headless.cycle(H, t))
            return { H.Hekili.State:IsUsable("exorcism") }
        end
        assert.are.same({ false, "creature type unknown; range nil: wrong target type" }, usable())
        H.ctl.creature.target = "undead"
        assert.are.same({ true }, usable())
        H.ctl.creature.target = SECRET
        H.ctl.ranges[10314] = { 0, 30 } -- in range: true
        assert.are.same({ true }, usable())
        assert.are.same({}, H.errors)
    end)
end)
