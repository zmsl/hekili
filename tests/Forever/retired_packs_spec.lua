-- tests/Forever/retired_packs_spec.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md,
-- Task 1): a built-in pack the class retires (kit:RetirePacks) leaves a saved profile at RestoreDefaults, and a spec
-- that chose it falls back to its default priority; a user's own pack of that name stays.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("retired built-in packs", function()
    it("are dropped from the profile and their specs return to the default priority", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local hk = H.Hekili
        local p = hk.DB.profile
        local id = hk.State.spec.id
        p.packs["Retired Test"] = { builtIn = true, spec = id, version = 1, date = 1, lists = {}, profile = "" }
        p.packs["Mine Test"] = { builtIn = false, spec = id, version = 1, date = 1, lists = {}, profile = "" }
        p.specs[id].package = "Retired Test"
        hk.Class.retiredPacks["Retired Test"] = true
        hk.Class.retiredPacks["Mine Test"] = true
        hk:RestoreDefaults()
        assert.is_nil(rawget(p.packs, "Retired Test"))
        assert.is_not_nil(rawget(p.packs, "Mine Test")) -- not built in: the user's
        assert.are.equal(hk.Class.specs[id].options.package, p.specs[id].package)
    end)

    it("is a kit method the content calls", function()
        local engine = require("Forever.helpers.engine")
        local env = engine.load("WARRIOR")
        env.class.kit:RetirePacks({ "Old A", "Old B" })
        assert.is_true(env.class.retiredPacks["Old A"] and env.class.retiredPacks["Old B"])
    end)
end)

-- A spec's default is the package its NewClass entry names; a valid saved choice wins; the order the built-ins decode
-- in (pairs over class.packs) never matters.
describe("a spec's default priority with two built-in packs", function()
    local EXTRA = { "Z Second", "A Second", "M Second", "Arms Second", "B", "Y", "Q Second", "C Second" }

    -- A fresh profile: every built-in decodes in one RestoreDefaults, the spec holding its AceDB default.
    local function fresh(saved)
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local hk, p = H.Hekili, H.Hekili.DB.profile
        local id = hk.State.spec.id
        local def = hk.Class.specs[id].options.package
        for _, name in ipairs(EXTRA) do
            hk.Class.packs[name] = hk.Class.packs[def]
        end
        for name in pairs(hk.Class.packs) do
            p.packs[name] = nil
        end
        p.specs[id].package = saved or def
        -- RestoreDefaults walks class.packs in this same pairs() order: some copies must decode before the default.
        local passed, before, after = false, false, false
        for name, v in pairs(hk.Class.packs) do
            if name == def then
                passed = true
            elseif v == hk.Class.packs[def] then
                before, after = before or not passed, after or passed
            end
        end
        hk:RestoreDefaults()
        return p.specs[id].package, def, before and after
    end

    it("is the NewClass package whichever built-in decodes first", function()
        local got, def, bothOrders = fresh()
        assert.is_true(bothOrders, "the extra packs did not decode on both sides of the default")
        assert.are.equal(def, got)
    end)

    it("keeps a saved choice of another built-in for the spec", function()
        local got = fresh("M Second")
        assert.are.equal("M Second", got)
    end)

    it("repairs a saved choice that names no pack", function()
        local got, def = fresh("Gone")
        assert.are.equal(def, got)
    end)
end)
