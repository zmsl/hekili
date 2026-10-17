-- tests/Forever/content_spec.lua (restructure plan, Task 8): Engine/Content.lua, the class pack loader OnEnable runs:
-- it picks Hekili_Forever_<Class> by the player's class, loads it when its X-Hekili-ContentAPI matches, and Notifies
-- (without loading) when the pack is missing, of another content API, or fails to load. A fake C_AddOns records the
-- calls.
local addons = require("helpers.addons")

describe("Engine/Content.lua", function()
    local calls, notes, meta, loadResult, classToken, defaults

    local function run()
        calls, notes, defaults = {}, {}, 0
        local ns = {
            Facade = {
                UnitClass = function(unit)
                    assert.are.equal("player", unit)
                    return "Name", classToken, 1
                end,
                C_AddOns = {
                    GetAddOnMetadata = function(name, key)
                        calls[#calls + 1] = "meta " .. name .. " " .. key
                        return meta[name] and meta[name][key]
                    end,
                    LoadAddOn = function(name)
                        calls[#calls + 1] = "load " .. name
                        return loadResult()
                    end,
                },
            },
        }
        local saved = rawget(_G, "Hekili")
        _G.Hekili = {
            Notify = function(_, text)
                notes[#notes + 1] = text
            end,
            RegisterSpecDefaults = function()
                defaults = defaults + 1
            end,
        }
        assert(loadfile("src/Hekili/Engine/Content.lua"))("Hekili", ns)
        ns.LoadContent()
        _G.Hekili = saved
    end

    before_each(function()
        meta = {}
        for _, name in ipairs(addons.CONTENT) do
            meta[name] = addons.meta(name)
        end
        loadResult = function()
            return true
        end
        classToken = "WARRIOR"
    end)

    it("loads Hekili_Forever_Warrior for a Warrior, whose TOC declares the core's content API", function()
        run()
        assert.are.same({ "meta Hekili_Forever_Warrior X-Hekili-ContentAPI", "load Hekili_Forever_Warrior" }, calls)
        assert.are.same({}, notes)
        assert.are.equal(1, defaults) -- the pack's spec gets its profile defaults
        classToken = "DRUID"
        run()
        assert.are.same({ "meta Hekili_Forever_Druid X-Hekili-ContentAPI", "load Hekili_Forever_Druid" }, calls)
    end)

    it("Notifies once for a class with no pack installed, and loads nothing", function()
        classToken = "PALADIN"
        run()
        assert.are.same({ "meta Hekili_Forever_Paladin X-Hekili-ContentAPI" }, calls)
        assert.are.same({ "no Forever pack for Paladin; install Hekili_Forever_Paladin" }, notes)
        assert.are.equal(0, defaults)
    end)

    it("Notifies a content API mismatch and does not load the pack", function()
        meta.Hekili_Forever_Warrior["X-Hekili-ContentAPI"] = "2"
        run()
        assert.are.same({ "meta Hekili_Forever_Warrior X-Hekili-ContentAPI" }, calls)
        assert.are.same(1, #notes)
        assert.is_truthy(notes[1]:find("Hekili_Forever_Warrior", 1, true))
        assert.is_truthy(notes[1]:find("content API 2", 1, true))
    end)

    it("Notifies a failed load, whether LoadAddOn refuses or raises", function()
        loadResult = function()
            return false, "DISABLED"
        end
        run()
        assert.are.same({ "could not load Hekili_Forever_Warrior (DISABLED)" }, notes)
        loadResult = function()
            error("boom", 0)
        end
        run()
        assert.are.same({ "could not load Hekili_Forever_Warrior (boom)" }, notes)
    end)

    it("declares one content API in every content TOC", function()
        for _, name in ipairs(addons.CONTENT) do
            assert.are.equal("1", addons.meta(name)["X-Hekili-ContentAPI"], name)
        end
        local src = assert(io.open("src/Hekili/Engine/Content.lua")):read("*a")
        assert.is_truthy(src:find("\nlocal CONTENT_API = 1\n", 1, true))
    end)
end)
