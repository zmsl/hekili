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
        local lines = {}
        hk.Print = function(_, m)
            lines[#lines + 1] = m
        end
        hk.Notify = function() end
        H.RunTimers(H.ctl.now + 6) -- the login notice: retired, not "updated"
        local said = table.concat(lines, "\n")
        assert.is_truthy(said:find("Retired Test|r priority was retired", 1, true), said)
        assert.is_falsy(said:find("Retired Test|r priority was updated", 1, true), said)
    end)

    it("is a kit method the content calls", function()
        local engine = require("Forever.helpers.engine")
        local env = engine.load("WARRIOR")
        env.class.kit:RetirePacks({ "Old A", "Old B" })
        assert.is_true(env.class.retiredPacks["Old A"] and env.class.retiredPacks["Old B"])
    end)
end)

-- A spec's default is the package its NewClass entry names; a valid saved choice wins; the order the built-ins decode
-- in (pairs over class.packs) never matters. The test drives that order itself: RestoreDefaults' pairs() is the
-- harness env's, so over class.packs it walks the given names first, then the rest.
describe("a spec's default priority with two built-in packs", function()
    local SECOND = "Second (test)"

    -- A fresh profile: every built-in decodes in one RestoreDefaults, the spec holding its AceDB default.
    local function fresh(order, saved)
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local hk, p = H.Hekili, H.Hekili.DB.profile
        local id = hk.State.spec.id
        local def = hk.Class.specs[id].options.package
        local packs = hk.Class.packs
        packs[SECOND] = packs[def]
        for name in pairs(packs) do
            p.packs[name] = nil
        end
        p.specs[id].package = saved or def
        local names = {}
        for _, n in ipairs(order) do
            names[#names + 1] = n == "default" and def or SECOND
        end
        for name in pairs(packs) do
            if name ~= def and name ~= SECOND then
                names[#names + 1] = name
            end
        end
        local walked = {}
        local envPairs = rawget(H.env, "pairs")
        rawset(H.env, "pairs", function(t)
            if t ~= packs then
                return pairs(t)
            end
            local i = 0
            return function()
                i = i + 1
                local n = names[i]
                if n then
                    walked[#walked + 1] = n
                    return n, packs[n]
                end
            end
        end)
        hk:RestoreDefaults()
        rawset(H.env, "pairs", envPairs)
        assert.are.same(names, walked) -- the decode really followed the given order
        return p.specs[id].package, def
    end

    it("is the NewClass package when the second built-in decodes first", function()
        local got, def = fresh({ "second", "default" })
        assert.are.equal(def, got)
    end)

    it("is the NewClass package when the default decodes first", function()
        local got, def = fresh({ "default", "second" })
        assert.are.equal(def, got)
    end)

    it("keeps a saved choice of another built-in for the spec, in either order", function()
        assert.are.equal(SECOND, (fresh({ "second", "default" }, SECOND)))
        assert.are.equal(SECOND, (fresh({ "default", "second" }, SECOND)))
    end)

    it("repairs a saved choice that names no pack", function()
        local got, def = fresh({ "second", "default" }, "Gone")
        assert.are.equal(def, got)
    end)
end)
