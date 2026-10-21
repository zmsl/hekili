-- tests/Forever/settings_spec.lua (restructure plan, Task 6): the profile port, src/Hekili/Engine/Settings.lua.
-- Configure hands the engine the profile's subtables by reference (an edit inside one is live) and copies its
-- scalars (a scalar edit needs another Configure); the headless boot runs OnInitialize -> InitializeProfile ->
-- Configure from the fresh AceDB profile, and the engine recommends from it.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local SUBTABLES =
    { "specs", "packs", "toggles", "displays", "performance", "notifications", "specChoice", "specMigrated" }
local SCALARS = { "enabled", "autoSnapshot", "screenshot" }

-- A fresh Settings.lua: returns Hekili.Engine.
local function load()
    local env = setmetatable({ Hekili = { Engine = {} } }, { __index = _G })
    local f = assert(loadfile("src/Hekili/Engine/Settings.lua"))
    setfenv(f, env)
    f("Hekili", {})
    return env.Hekili.Engine
end

local function profile()
    local p = { enabled = true, autoSnapshot = true, screenshot = false }
    for _, k in ipairs(SUBTABLES) do
        p[k] = {}
    end
    p.toggles.cooldowns = { value = false }
    return p
end

describe("Engine.Configure (pure)", function()
    local Engine
    before_each(function()
        Engine = load()
    end)

    it("swaps every subtable by identity, copies every scalar and bumps the version", function()
        local s = Engine.settings
        assert.are.equal(0, s.version)
        for n, p in ipairs({ profile(), profile() }) do
            p.screenshot = n == 2
            Engine.Configure(p)
            assert.are.equal(s, Engine.settings) -- the one preallocated table
            assert.are.equal(n, s.version)
            for _, k in ipairs(SUBTABLES) do
                assert.are.equal(p[k], s[k], k)
            end
            for _, k in ipairs(SCALARS) do
                assert.are.equal(p[k], s[k], k)
            end
        end
    end)

    it("sees a toggle flipped in the Options-held table with no second call", function()
        local p = profile()
        Engine.Configure(p)
        p.toggles.cooldowns.value = true
        assert.is_true(Engine.settings.toggles.cooldowns.value)
    end)

    it("does not see a scalar changed in the profile until Configure runs again", function()
        local p = profile()
        Engine.Configure(p)
        p.enabled = false
        assert.is_true(Engine.settings.enabled)
        Engine.Configure(p)
        assert.is_false(Engine.settings.enabled)
    end)
end)

describe("Engine.Configure (headless Arms boot)", function()
    it("runs once from the fixture profile through OnInitialize -> InitializeProfile", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local s, p = H.Hekili.Engine.settings, H.Hekili.DB.profile
        assert.are.equal(1, s.version)
        for _, k in ipairs(SUBTABLES) do
            assert.are.equal(p[k], s[k], k)
        end
        for _, k in ipairs(SCALARS) do
            assert.are.equal(p[k], s[k], k)
        end
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        assert.is_string(H.Hekili.Engine.Output.Primary.recs[1].actionName)
        assert.are.same({}, H.errors)
        assert.are.same({}, headless.unexpected(H, "run"))
    end)

    -- The class pack loads in OnInitialize before the profile (Engine/Content.lua): its spec's defaults are in the
    -- AceDB defaults from the start, so nothing re-registers them and every early holder of a profile subtable keeps
    -- the live one (LibDBIcon's iconStore: the minimap button's position and lock).
    it("keeps a saved spec setting and the minimap button's db (an all-default iconStore) across the boot", function()
        local saved = {
            profiles = {
                Default = { specs = { [100011] = { settings = { wowsims_recklessness = true } } }, iconStore = {} },
            },
        }
        local H = headless.new({ character = ww.character(), pack = ww.PACK, saved = saved })
        assert.are.same({}, H.loadErrors)
        local p = H.Hekili.DB.profile
        assert.is_true(p.specs[100011].settings.wowsims_recklessness)
        assert.is_false(p.specs[100011].settings.wowsims_stance_dance) -- a default the spec registered
        assert.are.equal(p.iconStore, saved.profiles.Default.iconStore)
        local icon = H.env.LibStub("LibDBIcon-1.0", true)
        local button = icon and icon:GetMinimapButton("Hekili")
        assert.is_not_nil(button)
        assert.are.equal(p.iconStore, button.db)
    end)
end)

-- Engine.SettingDefault: a setting registered with `option.sim` fills an unset profile value with that value under the
-- harness's scenario (Engine.scenario "sim") and with its `default` in game (nil).
describe("a setting's harness default", function()
    local function boot(scenario)
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.Hekili.Engine.scenario = scenario
        local id = H.Hekili.State.spec.id
        local spec = H.Hekili.Class.specs[id]
        local option = { type = "toggle", name = "Probe", desc = "A probe.", sim = true }
        spec:RegisterSetting("probe_sim", false, option)
        spec:RegisterSetting("probe_plain", true, { type = "toggle", name = "Plain", desc = "No sim." })
        H.Hekili:SpecializationChanged() -- the spec load's fill of unset profile values
        return H.Hekili.DB.profile.specs[id].settings, option, spec
    end

    it("fills its sim value under the harness and its default in game; a setting without one, its default", function()
        local sim = boot("sim")
        assert.are.same({ true, true }, { sim.probe_sim, sim.probe_plain })
        local game = boot(nil)
        assert.are.same({ false, true }, { game.probe_sim, game.probe_plain })
    end)

    it("keeps `sim` out of the AceConfig option and notes it in the description", function()
        local _, option, spec = boot(nil)
        assert.is_nil(option.sim)
        assert.are.equal("A probe.\n\nThe wowsims gate runs this as on.", option.desc)
        local entry = spec.settings[#spec.settings - 1]
        assert.are.same({ "probe_sim", false, true }, { entry.name, entry.default, entry.sim })
    end)

    it("a false sim value wins over a true default (an `if`, not `and/or`)", function()
        local H = {}
        local env = setmetatable({ Hekili = { Engine = H } }, { __index = _G })
        local f = assert(loadfile("src/Hekili/Engine/Settings.lua"))
        setfenv(f, env)
        f("Hekili", {})
        H.scenario = "sim"
        assert.is_false(H.SettingDefault({ default = true, sim = false }))
        H.scenario = nil
        assert.is_true(H.SettingDefault({ default = true, sim = false }))
    end)
end)

describe("the harness's scenario", function()
    it("headless.new sets it; the loop boots both instances in sim unless the content says game", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK, scenario = "sim" })
        assert.are.equal("sim", H.Hekili.Engine.scenario)
        assert.is_nil(headless.new({ character = ww.character(), pack = ww.PACK }).Hekili.Engine.scenario)
        local loop = require("Game.harness.loop")
        local L = loop.new(ww)
        assert.are.same({ "sim", "sim" }, { L.us.Hekili.Engine.scenario, L.oracle.Hekili.Engine.scenario })
        L = loop.new(setmetatable({ SCENARIO = "game" }, { __index = ww }))
        assert.are.same({}, { L.us.Hekili.Engine.scenario, L.oracle.Hekili.Engine.scenario })
    end)
end)

-- A choice setting (central fix 25): RegisterSetting with an AceConfig `select` (`values`: candidate key -> display
-- name, `sorting`: their order), a default and a harness default (`sim`) among them. A priority reads it as
-- `settings.<key>='<candidate>'` (the script language passes the quoted string through: no parser rule).
describe("a choice setting", function()
    local alloc = require("Game.State.helpers.alloc")
    local CHOICES = { alpha = "Alpha", beta = "Beta", none = "None" }
    local ORDER = { "alpha", "beta", "none" }

    local function boot(scenario)
        local H = headless.new({ character = ww.character(), pack = ww.PACK, scenario = scenario })
        assert.are.same({}, H.loadErrors)
        local id = H.Hekili.State.spec.id
        local spec = H.Hekili.Class.specs[id]
        local option =
            { type = "select", name = "Pick", desc = "A choice.", values = CHOICES, sorting = ORDER, sim = "none" }
        spec:RegisterSetting("pick", "beta", option)
        H.Hekili:SpecializationChanged()
        return H, H.Hekili.DB.profile.specs[id].settings, option, spec
    end

    it("fills its default in game and its sim value under the harness; notes the sim choice by name", function()
        local _, game, option = boot(nil)
        assert.are.equal("beta", game.pick)
        assert.are.equal("A choice.\n\nThe wowsims gate runs this as None.", option.desc)
        assert.is_nil(option.sim)
        local _, sim = boot("sim")
        assert.are.equal("none", sim.pick)
    end)

    it("refuses a default or a sim value that is not a candidate", function()
        local _, _, _, spec = boot(nil)
        assert.error_matches(function()
            spec:RegisterSetting("bad", "gamma", { type = "select", name = "B", values = CHOICES, sorting = ORDER })
        end, "RegisterSetting bad: gamma is not one of its values", 1, true)
        assert.error_matches(function()
            spec:RegisterSetting("bad2", "alpha", { type = "select", name = "B", values = CHOICES, sim = "gamma" })
        end, "RegisterSetting bad2: gamma is not one of its values", 1, true)
    end)

    it("answers each candidate's condition, allocation-free once warm", function()
        local H, settings = boot(nil)
        local lists = H.Hekili.DB.profile.packs[ww.PACK].lists
        local list = next(lists)
        for i, k in ipairs(ORDER) do
            table.insert(
                lists[list],
                i,
                { action = "battle_shout", criteria = "settings.pick='" .. k .. "'", enabled = true }
            )
        end
        H.Hekili:LoadScripts()
        local function fired()
            assert.is_true(headless.cycle(H, H.ctl.now + 1))
            H.Hekili.State.reset()
            local out = {}
            for i = 1, #ORDER do
                out[i] = H.Hekili.Scripts:CheckScript(ww.PACK .. ":" .. list .. ":" .. i)
            end
            return out
        end
        assert.are.same({ false, true, false }, fired())
        settings.pick = "alpha"
        assert.are.same({ true, false, false }, fired())
        settings.pick = "none"
        assert.are.same({ false, false, true }, fired())
        assert.are.same({}, H.errors)
        local id = ww.PACK .. ":" .. list .. ":3"
        assert.are.equal(
            0,
            alloc.bytes(function()
                H.Hekili.Scripts:CheckScript(id)
            end, 500)
        )
    end)

    it("is a dropdown on the spec's settings page, and /hekili set spec picks a candidate", function()
        local H, settings = boot(nil)
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        local key = H.Hekili.State.spec.key
        local o = H.Hekili.Options.args.packs.plugins.specializations[key].args.core.plugins.settings.pick
        assert.are.same({ "select", CHOICES, ORDER }, { o.type, o.values, o.sorting })
        local info = { "packs", key, "core", "pick" }
        assert.are.equal("beta", o.get(info))
        o.set(info, "alpha")
        assert.are.equal("alpha", settings.pick)
        H.Hekili:CmdLine("set spec pick none")
        assert.are.equal("none", settings.pick)
        H.Hekili:CmdLine("set spec pick gamma") -- not a candidate: unchanged
        assert.are.equal("none", settings.pick)
    end)
end)
