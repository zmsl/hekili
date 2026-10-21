-- tests/Forever/mage_spec.lua: the Forever Mage class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb; Arcane Wrath and the talents' per-rank values from wowsims/forever's spell data), loaded headless
-- through the recording stand-in (helpers/load_druid.lua with Mage.lua): the specs, the kit, the talents, mana and
-- Evocation's, the channels, Arcane Blast's charges and cost, the cast times (Presence of Mind, Heating Up, the talents),
-- Fire Vulnerability, the cost modifiers, the lockouts; and the class through the real engine (headless.lua): every
-- `now` in VirtualState's context. What Hekili does with the rest is verified in game (docs/dev/layout.md).
local ld = require("Forever.helpers.load_druid")
local headless = require("Game.harness.headless")

local FILE = "src/Hekili_Mage/Mage.lua"

-- key = { spell IDs in rank order, the top rank's mana cost, cooldown, gcd }, from the DB2 (`wowdb spell <name>`; Arcane
-- Wrath from wowsims's data): the cooldown is the larger of RecoveryTime and CategoryRecoveryTime; a percent-of-base
-- cost (PowerCostPct) as the fraction the class file declares.
local KIT = {
    arcane_blast = { { 400574, 1239696, 1239697, 1239699, 1239700 }, 0.15, 0, "spell" },
    arcane_missiles = { { 5143, 5144, 5145, 8416, 8417, 10211, 10212, 25345 }, 655, 0, "spell" },
    arcane_wrath = { { 1326079, 1326080, 1326081, 1326082 }, 395, 6, "spell" },
    frostbolt = { { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304 }, 290, 0, "spell" },
    fireball = { { 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306 }, 410, 0, "spell" },
    scorch = { { 2948, 8444, 8445, 8446, 10205, 10206, 10207 }, 150, 0, "spell" },
    pyroblast = { { 11366, 12505, 12522, 12523, 12524, 12525, 12526, 18809 }, 440, 0, "spell" },
    fire_blast = { { 2136, 2137, 2138, 8412, 8413, 10197, 10199 }, 340, 8, "spell" },
    frostfire_bolt = { { 401502, 1237312, 1237313 }, 370, 0, "spell" },
    evocation = { { 12051 }, 0, 480, "spell" },
    counterspell = { { 2139 }, 100, 30, "off" },
    arcane_power = { { 12042 }, 0, 180, "off" },
    presence_of_mind = { { 12043 }, 0, 180, "off" },
    combustion = { { 11129 }, 0, 180, "off" },
}

local function idsOf(a)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
        out[#out + 1] = id
    end
    return out
end

-- `buff` with the keys in `up` up, each { up, stack }.
local function buffs(up)
    return setmetatable({}, {
        __index = function(_, k)
            local n = up[k]
            return { up = n ~= nil, stack = n or 0, remains = n and 10 or 0 }
        end,
    })
end

local function near(x)
    return math.floor(x * 10000 + 0.5) / 10000
end

describe("Forever Mage", function()
    local w

    before_each(function()
        w = ld.load(nil, FILE, "MAGE")
    end)

    it("declares Arcane and Fire on trees 1 and 2 with their wowsims.com packs, Frost unsupported", function()
        assert.are.equal("MAGE", w.class)
        local out = {}
        for _, s in ipairs(w.def.specs) do
            out[#out + 1] = { s.key, s.tree, s.role, s.ranged, s.unsupported or false, s.package or false }
        end
        assert.are.same({
            { "arcane", 1, "attack", true, false, "Arcane (wowsims.com)" },
            { "fire", 2, "attack", true, false, "Fire (wowsims.com)" },
            { "frost", 3, "attack", true, true, false },
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
        assert.are.equal(14, n)
        for _, key in ipairs({ "arcane_power", "presence_of_mind", "combustion" }) do
            assert.are.equal("cooldowns", w.abilities[key].toggle, key)
        end
    end)

    it("places every DB2 talent in its tree and keeps the Forever-only ones at tree 0", function()
        local n = { [0] = 0, 0, 0, 0 }
        for _, t in pairs(w.talents) do
            n[t[1]] = n[t[1]] + 1
        end
        assert.are.same({ [0] = 6, 16, 16, 17 }, n)
        assert.are.same({ 0, 400588, 2 }, w.talents.missile_barrage)
        assert.are.same({ 0, 400624, 1 }, w.talents.heating_up)
    end)

    it("declares mana under the five-second rule, base 1213, and Evocation's mana while its aura is up", function()
        assert.are.same({ 0 }, w.order)
        local r = w.resources[0]
        assert.are.same({ spirit = 29.13, mp5 = 0 }, r.meta.fsr) -- wowsims's logs at 60 (P1 gear)
        assert.are.equal(1213, r.meta.base)
        local evo = r.models.evocation
        assert.are.same({ "evocation", 1, 15 * 29.13 }, { evo.aura, evo.interval, evo.value })
        w.state.query_time, w.state.buff.evocation = 13.4, { applied = 10.2 }
        assert.is_true(math.abs(evo.last() - 13.2) < 1e-9) -- the last whole tick since the aura's application
    end)

    it(
        "channels Arcane Missiles (5 s, a missile a second; 2.5 s and 0.5 s under Missile Barrage) and Evocation",
        function()
            local am, evo = w.abilities.arcane_missiles, w.abilities.evocation
            assert.are.same({ true, true }, { am.channeled, evo.channeled })
            w.game.known[25345] = true
            local e = ld.env(w)
            e.haste = 1
            assert.are.same({ 5, 1 }, { ld.run(am.cast, e), ld.run(am.tick_time, e) })
            e.buff = buffs({ missile_barrage = 1 })
            assert.are.same({ 2.5, 0.5 }, { ld.run(am.cast, e), ld.run(am.tick_time, e) })
            w.game.known[25345], w.game.known[5143] = false, true
            assert.are.equal(1.5, ld.run(am.cast, e)) -- rank 1's 3 s, halved
            assert.are.same({ 8, 1 }, { evo.cast, evo.tick_time })
            for _, field in ipairs({ "now", "start" }) do
                e = ld.env(w)
                ld.run(evo[field], e)
                assert.are.same({ "evocation" }, e.applied, field)
            end
            assert.is_nil(evo.handler) -- a channel's handler never runs in Hekili's simulation
        end
    )

    it("prices Arcane Blast at 15% of base mana, +175% a charge, and each cast adds a charge", function()
        local ab = w.abilities.arcane_blast
        local out = {}
        for n = 0, 4 do
            local e = ld.env(w)
            e.buff = buffs(n > 0 and { arcane_blast = n } or {})
            out[#out + 1] = near(ld.run(ab.spend, e))
        end
        assert.are.same({ 0.15, 0.4125, 0.675, 0.9375, 1.2 }, out)
        assert.is_true(ab.spendBase) -- every one a fraction of base, the 1.2 too
        -- 15 s from the first charge, never refreshed (ruling M9: wowsims's data and log; the DB2 at 70338 says 8 s)
        assert.are.same(
            { 400573, 15, 4 },
            { w.auras.arcane_blast.id, w.auras.arcane_blast.duration, w.auras.arcane_blast.max_stack }
        )
        for _, field in ipairs({ "now", "handler" }) do
            for _, n in ipairs({ 0, 2 }) do
                local e = ld.env(w)
                e.buff = buffs(n > 0 and { arcane_blast = n } or {}) -- a charge up has 10 s left
                function e.addStack(key, duration)
                    table.insert(e.added, { key, duration or "full" })
                end
                ld.run(ab[field], e)
                assert.are.same(
                    { { { "arcane_blast", n > 0 and 10 or "full" } }, { "presence_of_mind" } },
                    { e.added, e.removed },
                    field
                )
            end
        end
    end)

    it(
        "times the hard casts: Presence of Mind instant, Heating Up -25% a stack, Improved Fireball and Frostbolt",
        function()
            local A = w.abilities
            w.game.known[25306], w.game.known[25304] = true, true
            local e = ld.env(w)
            e.haste = 1
            assert.are.same({ 1.5, 3.5, 3, 3.5, 1.5, 6, 3 }, { -- Arcane Blast 1.5 s (ruling M9: wowsims's data)
                ld.run(A.arcane_blast.cast, e),
                ld.run(A.arcane_wrath.cast, e),
                ld.run(A.frostbolt.cast, e),
                ld.run(A.fireball.cast, e),
                ld.run(A.scorch.cast, e),
                ld.run(A.pyroblast.cast, e),
                ld.run(A.frostfire_bolt.cast, e),
            })
            local pyro = {}
            for n = 1, 3 do
                e.buff = buffs({ heating_up = n })
                pyro[#pyro + 1] = ld.run(A.pyroblast.cast, e)
            end
            assert.are.same({ 4.5, 3, 1.5 }, pyro)
            e.buff = buffs({})
            e.talent.improved_fireball = { rank = 5 }
            e.talent.improved_frostbolt = { rank = 3 }
            assert.are.same({ 3, 2.7 }, { near(ld.run(A.fireball.cast, e)), near(ld.run(A.frostbolt.cast, e)) })
            e.haste = 0.8
            assert.are.equal(2.4, near(ld.run(A.fireball.cast, e)))
            e.buff = buffs({ presence_of_mind = 1 })
            for _, key in ipairs({ "arcane_blast", "arcane_wrath", "frostbolt", "fireball", "scorch", "pyroblast" }) do
                assert.are.equal(0, ld.run(A[key].cast, e), key)
            end
        end
    )

    it("stacks Fire Vulnerability on the target from Scorch under Improved Scorch, to 5", function()
        local s = w.abilities.scorch
        for _, field in ipairs({ "now", "handler" }) do
            local e = ld.env(w)
            e.min = math.min
            ld.run(s[field], e)
            assert.are.same({}, e.applied, field) -- no talent: none
            e.talent.improved_scorch = { rank = 3 }
            e.debuff = buffs({ fire_vulnerability = 2 })
            ld.run(s[field], e)
            assert.are.same({ { "fire_vulnerability" }, 3 }, { e.applied, e.stacks.fire_vulnerability }, field)
            e.debuff = buffs({ fire_vulnerability = 5 })
            ld.run(s[field], e)
            assert.are.equal(5, e.stacks.fire_vulnerability, field)
        end
        local a = w.auras.fire_vulnerability
        assert.are.same({ 22959, 30, 5 }, { a.id, a.duration, a.max_stack })
    end)

    it("spends Heating Up on a Pyroblast unless Presence of Mind made it instant", function()
        local p = w.abilities.pyroblast
        for _, field in ipairs({ "now", "handler" }) do
            local e = ld.env(w)
            ld.run(p[field], e)
            assert.are.same({ "heating_up", "presence_of_mind" }, e.removed, field)
            e = ld.env(w)
            e.buff = buffs({ presence_of_mind = 1, heating_up = 3 })
            ld.run(p[field], e)
            assert.are.same({ "presence_of_mind" }, e.removed, field)
        end
    end)

    it("spends a Fingers of Frost charge on each damage spell's cast in the simulation, none in the belief", function()
        -- wowsims talents_frost.go: every damage spell cast spends one, a channel aside; the belief's are the aura walk's
        for _, key in ipairs({
            "arcane_blast",
            "arcane_wrath",
            "frostbolt",
            "fireball",
            "scorch",
            "pyroblast",
            "fire_blast",
            "frostfire_bolt",
        }) do
            local a = w.abilities[key]
            local e = ld.env(w)
            e.buff = buffs({ fingers_of_frost = 2 })
            ld.run(a.handler, e)
            assert.is_truthy(table.concat(e.removed, " "):find("fingers_of_frost", 1, true), key)
            e = ld.env(w)
            ld.run(a.handler, e) -- none up: none spent
            assert.is_falsy(table.concat(e.removed, " "):find("fingers_of_frost", 1, true), key)
            if a.now then
                e = ld.env(w)
                e.buff = buffs({ fingers_of_frost = 2 })
                ld.run(a.now, e)
                assert.is_falsy(table.concat(e.removed, " "):find("fingers_of_frost", 1, true), key)
            end
        end
    end)

    it(
        "casts Frostfire Bolt 0.1 s faster a rank of Improved Fireball, and prices it and Frostbolt less Frost Channeling",
        function()
            local f = w.abilities.frostfire_bolt
            local e = ld.env(w)
            e.haste = 1
            e.talent.improved_fireball = { rank = 5 }
            assert.are.equal(2.5, ld.run(f.cast, e)) -- wowsims's FFB log: 2.5 s unhasted
            w.game.known[1237313], w.game.known[10181] = true, true
            e.talent.frost_channeling = { rank = 3 }
            assert.are.same({ 314.5, 221 }, { ld.run(f.spend, e), ld.run(w.abilities.frostbolt.spend, e) }) -- 370, 260 x 0.85
            w.game.known[1237313], w.game.known[10181] = false, false
        end
    )

    it("shortens Fire Blast's cooldown 1 s a rank of Wake of Fire, 2 s at most", function()
        local cd, e, out = w.abilities.fire_blast.cooldown, ld.env(w), {}
        for rank = 0, 3 do
            e.talent.wake_of_fire = { rank = rank }
            out[#out + 1] = ld.run(cd, e)
        end
        assert.are.same({ 8, 7, 6, 6 }, out)
    end)

    it("declares Clearcasting, Missile Barrage and Arcane Power as cost modifiers on the DB2 masks' spells", function()
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
            clearcasting = { -1, 1, { 116, 133, 2136, 2948, 5143, 11366, 400574, 401502, 1326079 } },
            missile_barrage = { -1, 1, { 5143 } },
            -- Arcane Wrath too: wowsims's mask (0x9000 of word 1 covers its 0x8000), its log's 513.5 = 395 x 1.3
            arcane_power = { 0.3, false, { 116, 133, 2136, 2948, 5143, 11366, 400574, 401502, 1326079 } },
        }, by)
    end)

    it("refuses each spell while an interrupt has its school locked out", function()
        local SCHOOL = {
            arcane_blast = "arcane",
            arcane_missiles = "arcane",
            arcane_wrath = "arcane",
            evocation = "arcane",
            counterspell = "arcane",
            frostbolt = "frost",
            fireball = "fire",
            scorch = "fire",
            pyroblast = "fire",
            fire_blast = "fire",
        }
        for key, school in pairs(SCHOOL) do
            local e = ld.env(w)
            assert.is_true((ld.run(w.abilities[key].usable, e)), key)
            e["locked_out_" .. school] = true
            assert.is_false((ld.run(w.abilities[key].usable, e)), key)
        end
        for _, school in ipairs({ "fire", "frost" }) do
            local e = ld.env(w)
            e["locked_out_" .. school] = true
            assert.is_false((ld.run(w.abilities.frostfire_bolt.usable, e)), school)
        end
    end)

    it("counts Presence of Mind and Combustion on one category cooldown, and interrupts with Counterspell", function()
        for _, case in ipairs({ { "presence_of_mind", "combustion" }, { "combustion", "presence_of_mind" } }) do
            for _, field in ipairs({ "now", "handler" }) do
                local e = ld.env(w)
                ld.run(w.abilities[case[1]][field], e)
                assert.are.same({ { { case[2], 180 } }, { case[1] } }, { e.cooldowns, e.applied }, case[1] .. field)
            end
        end
        local cs, called = w.abilities.counterspell, false
        local e = ld.env(w)
        e.interrupt = function()
            called = true
        end
        ld.run(cs.handler, e)
        assert.are.same({ true, "casting" }, { called, cs.debuff })
    end)
end)

-- Through the real engine (headless.lua): a Mage who knows the whole kit.
describe("Forever Mage through the engine", function()
    local function character()
        local w = ld.load(nil, FILE, "MAGE")
        local known = {}
        for _, a in pairs(w.abilities) do
            for _, id in ipairs(idsOf(a)) do
                known[#known + 1] = id
            end
        end
        return {
            class = "MAGE",
            classID = 8,
            specID = 1485,
            level = 60,
            known = known,
            talents = {},
            power = { type = 0, token = "MANA", max = 6000, value = 6000 },
            speed = { 3 },
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
                { "arcane", "fire", "frost", true },
                { specs[100081].key, specs[100082].key, specs[100083].key, specs[100083].unsupported }
            )
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

    -- The belief's charges and their price at the cast, in both layers: `spendBase` prices every declared fraction of
    -- base, the 1.2 at 4 charges included (central fix 22, gap BB).
    it("counts Arcane Blast's charges in the belief and the simulation, four at most, each pricing the next", function()
        local H = headless.new({ character = character() })
        local I, VS, S = H.ns.VirtualStateInternal, H.ns.VirtualState, H.Hekili.State
        local a, out = I.ab.bySpell[400574], {}
        for k = 1, 5 do
            local t = H.ctl.now + 1
            H.ctl.now = t
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. k, 400574)
            assert.is_true(headless.cycle(H, t + 0.1))
            VS.Drain(t + 0.1)
            local _, n = VS.Aura("player", 400573, t + 0.1)
            S.reset("Primary", true)
            out[#out + 1] = { n, S.buff.arcane_blast.stack, I.CostOf(a), S.action.arcane_blast.cost }
        end
        -- each the declared fraction x 1213, floored (0.4125, 0.675, 0.9375, 1.2)
        assert.are.same(
            { { 1, 1, 500, 500 }, { 2, 2, 818, 818 }, { 3, 3, 1137, 1137 }, { 4, 4, 1455, 1455 }, { 4, 4, 1455, 1455 } },
            out
        )
        assert.are.same({}, H.errors)
    end)
end)

-- The priorities: the wowsims.com packs (generated from wowsims/forever's APLs by `make wowsims-packs`).
describe("Forever Mage priorities", function()
    it("keeps the class file's generated blocks in step with APLs/, each spec's package its pack", function()
        local mp = assert(loadfile("tools/make_pack.lua"))("lib")
        local f = assert(io.open(FILE))
        local src = f:read("*a")
        f:close()
        assert.are.equal(src, (mp.sync(src, mp.load("mage"))))
        local cls, names = ld.load(nil, FILE, "MAGE"), {}
        for _, sp in ipairs(cls.def.specs) do
            names[#names + 1] = sp.package or "none"
        end
        assert.are.same({ "Arcane (wowsims.com)", "Fire (wowsims.com)", "none" }, names)
    end)

    it("names only registered abilities and auras", function()
        local cls = ld.load(nil, FILE, "MAGE")
        local kinds = { buff = cls.auras, debuff = cls.auras, cooldown = cls.abilities, action = cls.abilities }
        -- Hekili's `all`: Hekili_Shared/Shared/Items.lua's use_items and the mana gem
        local shared = { use_items = true, mana_gem = true, call_action_list = true }
        for _, p in ipairs(assert(loadfile("tools/make_pack.lua"))("lists", "mage")) do
            for list, entries in pairs(p.lists) do
                for i, e in ipairs(entries) do
                    local where = p.name .. " " .. list .. " " .. i
                    assert.is_true(cls.abilities[e.action] ~= nil or shared[e.action], where)
                    for kind, key in (e.criteria or ""):gmatch("(%a+)%.([%w_]+)") do
                        if kinds[kind] then
                            assert.is_true(kinds[kind][key] ~= nil, where .. ": " .. key)
                        end
                    end
                end
            end
        end
    end)
end)
