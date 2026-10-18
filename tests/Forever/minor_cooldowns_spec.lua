-- tests/Forever/minor_cooldowns_spec.lua: the Minor Cooldowns toggle's key is `minor_cooldowns`; `essences` (upstream's
-- name) survives only as a migrated saved key and an alias (Options.lua RunOneTimeFixes, FireToggle, the SimC
-- importer; State.lua's toggle table).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local function boot(saved)
    local H = headless.new({ character = ww.character(), pack = ww.PACK, saved = saved })
    assert.are.same({}, H.loadErrors)
    return H
end

describe("the minor_cooldowns toggle", function()
    it("takes an older profile's essences fields and ability overrides, then clears the old key", function()
        local saved = {
            profiles = {
                Default = {
                    toggles = { essences = { key = "ALT-G", value = false, separate = true, override = false } },
                    specs = { [ww.SPEC] = { abilities = { mortal_strike = { toggle = "essences" } } } },
                },
            },
        }
        local H = boot(saved)
        local p = H.Hekili.DB.profile
        assert.is_nil(rawget(p.toggles, "essences"))
        local t = p.toggles.minor_cooldowns
        assert.are.equal("ALT-G", t.key)
        assert.is_false(t.value)
        assert.is_true(t.separate)
        assert.is_false(t.override)
        assert.are.equal("minor_cooldowns", p.specs[ww.SPEC].abilities.mortal_strike.toggle)
        H.Hekili:RunOneTimeFixes() -- again: nothing left to move
        assert.are.equal("ALT-G", p.toggles.minor_cooldowns.key)
        assert.are.same({}, H.errors)
    end)

    it("keeps the defaults on a fresh profile", function()
        local H = boot()
        local t = H.Hekili.DB.profile.toggles
        assert.is_nil(rawget(t, "essences"))
        assert.are.equal("ALT-SHIFT-G", t.minor_cooldowns.key)
        assert.is_true(t.minor_cooldowns.value)
    end)

    it("answers toggle.essences, FireToggle('essences') and an imported toggle.essences as minor_cooldowns", function()
        local H = boot()
        local t = H.Hekili.DB.profile.toggles.minor_cooldowns
        t.override = false
        t.value = true
        assert.is_true(H.Hekili.State.toggle.essences)
        H.Hekili:FireToggle("essences")
        assert.is_false(t.value)
        assert.is_false(H.Hekili.State.toggle.essences)
        local out = H.Hekili:ParseActionList("actions+=/mortal_strike,if=toggle.essences&rage>=30")
        assert.are.equal("toggle.minor_cooldowns&rage>=30", out[1].criteria:gsub("%s", ""))
    end)

    it("is not spelled essences in any class pack's priorities or class file", function()
        for _, glob in ipairs({ "src/Hekili_*/APLs/*.simc", "src/Hekili_*/*.lua" }) do
            local ls = assert(io.popen("ls " .. glob))
            for file in ls:lines() do
                local f = assert(io.open(file))
                local src = f:read("*a")
                f:close()
                assert.is_nil(src:find("essences", 1, true), file)
            end
            ls:close()
        end
    end)
end)
