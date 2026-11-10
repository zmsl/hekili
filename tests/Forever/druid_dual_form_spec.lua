-- tests/Forever/druid_dual_form_spec.lua: the form-following Feral and Guardian packs (owner 2026-11-10; design
-- dual-form-druid-apl-research.md B1). APLs/packs.lua imports Guardian's lists into Feral (wowsims.com) as bear* and
-- Feral's into Guardian (wowsims.com) as cat*, entered while that form is up: in Bear Form the Feral pack recommends
-- what the Guardian pack would, in Cat Form the Guardian pack what the Feral pack would, in caster form each its own.
-- The imported lines' setting shows on the importing spec's page below its own, its own stored value.
local W = require("Forever.helpers.druid_loop_world")
local headless = require("Game.harness.headless")
local mp = assert(loadfile("tools/make_pack.lua"))("lib")

local FERAL, GUARDIAN = "Feral (wowsims.com)", "Guardian (wowsims.com)"
local BEAR_KIT =
    { "maul", "swipe_bear", "primal_bite", "lacerate", "demoralizing_roar", "enrage", "frenzied_regeneration" }
local BEAR = { bear_form = true }
local CAT = { cat_form = true, shred = true, claw = true, rake = true, rip = true, ferocious_bite = true }
for _, k in ipairs(BEAR_KIT) do
    BEAR[k] = true
end

-- A world's character in `form` (a druid_loop_world form key, or nil: caster form) with `power`.
local function character(world, form, power)
    local c = world.character()
    c.form, c.power = form and W.FORM[form] or 0, power
    return c
end
local RAGE = { type = 1, token = "RAGE", max = 100, value = 30 }
local ENERGY = { type = 3, token = "ENERGY", max = 100, value = 100 }
local MANA = { type = 0, token = "MANA", max = 4000, value = 4000 }

-- Boots `c` on `pack` (its spec becomes the choice), `combat` or not, and returns H and the queue's action names.
local function boot(c, pack, combat, setup)
    local H = headless.new({ character = c, pack = pack })
    assert.are.same({}, H.loadErrors)
    local hk = H.Hekili
    assert.are.equal(pack, hk.DB.profile.specs[hk.State.spec.id].package)
    if setup then
        setup(H)
    end
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    if combat then
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
    end
    assert.is_true(hk.Engine.Subscribe("Primary", function() end))
    assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
    assert.are.same({}, H.errors)
    local names = {}
    for i, r in ipairs(hk.Engine.Output.Primary.recs) do
        names[i] = r.actionName
    end
    return H, names
end

local function none(names, set, what)
    for _, n in ipairs(names) do
        assert.is_nil(set[n], what .. ": " .. table.concat(names, " "))
    end
end

-- The Guardian world's bear (it knows every bear rank and cat form), booted on either pack.
local function bear(rage)
    local p = rage and { type = RAGE.type, token = RAGE.token, max = RAGE.max, value = rage } or RAGE
    return character(W.Guardian, "bear_form", p)
end

describe("the form-following Druid packs", function()
    -- rage 0: every bear pick waits on rage while Cat Form (the Feral list's own line) is ready: it must not leak
    for _, case in ipairs({ { true }, { false }, { true, 0 } }) do
        local combat, rage = case[1], case[2]
        local when = (combat and "in combat" or "out of combat") .. (rage and " at " .. rage .. " rage" or "")
        it("Feral (wowsims.com) in Bear Form " .. when .. " recommends what Guardian (wowsims.com) does", function()
            local H, feral = boot(bear(rage), FERAL, combat)
            assert.are.equal("feral", H.Hekili.State.spec.key)
            local G, guardian = boot(bear(rage), GUARDIAN, combat)
            assert.are.equal("guardian", G.Hekili.State.spec.key)
            assert.is_true(#guardian > 0)
            assert.are.same(guardian, feral)
            none(feral, CAT, "a cat ability in Bear Form")
            -- the bear default list, not only its precombat Enrage
            local seen = false
            for _, n in ipairs(feral) do
                seen = seen or n == "lacerate" or n == "primal_bite" or n == "maul"
            end
            assert.is_true(seen, table.concat(feral, " "))
        end)
    end

    it("Guardian (wowsims.com) in Cat Form recommends what Feral (wowsims.com) does", function()
        local G, guardian = boot(character(W.Feral, "cat_form", ENERGY), GUARDIAN, true)
        assert.are.equal("guardian", G.Hekili.State.spec.key)
        local _, feral = boot(character(W.Feral, "cat_form", ENERGY), FERAL, true)
        assert.is_true(#feral > 0)
        assert.are.same(feral, guardian)
        none(guardian, BEAR, "a bear ability in Cat Form")
    end)

    it("each pack in caster form runs its own list (its own form)", function()
        local _, feral = boot(character(W.Feral, nil, MANA), FERAL, true)
        none(feral, BEAR, "a bear ability in caster form on Feral")
        local _, guardian = boot(character(W.Guardian, nil, MANA), GUARDIAN, true)
        assert.are.equal("bear_form", guardian[1])
        none(guardian, CAT, "a cat ability in caster form on Guardian")
    end)

    it("leaves a custom priority as its lists say: a Feral-only one in Bear Form gets no bear list", function()
        local f = assert(io.open("src/Hekili_Druid/APLs/" .. FERAL .. ".simc", "rb"))
        local own = f:read("*a"):gsub("#[^\n]*\n", "")
        f:close()
        local _, names = boot(bear(), FERAL, true, function(H)
            local hk = H.Hekili
            local mine = {}
            for k, v in pairs(hk.DB.profile.packs[FERAL]) do
                mine[k] = v
            end
            mine.builtIn, mine.lists = false, mp.parse(own)
            hk.DB.profile.packs.Mine = mine
            hk.DB.profile.specs[hk.State.spec.id].package = "Mine"
            hk:LoadScripts()
        end)
        for _, k in ipairs(BEAR_KIT) do
            none(names, { [k] = true }, "a bear list line in a custom Feral priority")
        end
    end)

    it("reads Feral's own stored Demoralizing Roar setting in Bear Form, Guardian's untouched", function()
        local function names(on)
            local H, out = boot(bear(), FERAL, true, function(H)
                H.Hekili.DB.profile.specs[H.Hekili.State.spec.id].settings.maintain_demoralizing_roar = on
                H.Hekili:SettingsChanged()
            end)
            local g
            for id, sp in pairs(H.Hekili.Engine.Registry.Specs()) do
                g = sp.key == "guardian" and rawget(H.Hekili.DB.profile.specs, id) or g
            end
            assert.is_not_true(g and g.settings.maintain_demoralizing_roar) -- Guardian's own value: untouched
            return table.concat(out, " ")
        end
        assert.matches("demoralizing_roar", names(true))
        assert.not_matches("demoralizing_roar", names(false))
    end)

    describe("the imported setting on the other spec's page", function()
        local function page(key)
            local H = headless.new({ character = character(W.Feral, "cat_form", ENERGY), pack = FERAL })
            assert.are.same({}, H.loadErrors)
            H.Hekili:EmbedSpecOptions()
            H.Hekili:EmbedPackOptions()
            local settings = H.Hekili.Options.args.packs.plugins.specializations[key].args.core.plugins.settings
            local rows = {}
            for name, o in pairs(settings) do
                if o.order > 100.5 and (o.type ~= "description" or o.name ~= "") then
                    rows[#rows + 1] = { o.order, o.type, name, o.name }
                end
            end
            table.sort(rows, function(a, b)
                return a[1] < b[1]
            end)
            local out = {}
            for i, r in ipairs(rows) do
                out[i] = r[2] .. " " .. (r[2] == "toggle" and r[3] or r[4])
            end
            return out
        end

        it("puts Guardian's Roar on Feral's page below its own, after a divider and what it is for", function()
            assert.are.same({
                "toggle behind",
                "header Bear Form (Guardian)",
                "description These settings come from the Guardian priority. They apply only while you are in Bear Form.",
                "toggle maintain_demoralizing_roar",
            }, page("feral"))
        end)

        it("puts the Shred setting the cat lines read on Guardian's page below its own, likewise", function()
            assert.are.same({
                "toggle maintain_demoralizing_roar",
                "header Cat Form (Feral)",
                "description These settings come from the Feral priority. They apply only while you are in Cat Form.",
                "toggle behind",
            }, page("guardian"))
        end)

        it("leaves Balance's page as it was", function()
            assert.are.same({ "toggle behind" }, page("balance"))
        end)
    end)
end)
