-- tests/Forever/stale_window_warning_spec.lua (L1937): a priority line that reads a window another priority declares, but
-- neither its own priority nor a class pack does, reads it closed (the line may never fire, or fire differently). LoadScripts reports it once
-- a session through Hekili:Error (the Warnings page). A window the priority declares itself, or a class pack registers,
-- is silent; a name nobody declares stays the compile error.
local headless = require("Game.harness.headless")
local dlw = require("Forever.helpers.druid_loop_world")

describe("the stale window read warning", function()
    local H

    local function pack(lists)
        return { spec = H.Hekili.State.spec.id, builtIn = false, lists = lists }
    end

    -- the warnings naming priority `name` (the session dedupe and the profile outlive a test: each test owns its names)
    local function warned(name)
        local out = {}
        for key in pairs(H.Hekili.ErrorDB) do
            if key:find("reads the window", 1, true) and key:find("'" .. name .. "'", 1, true) then
                out[#out + 1] = key
            end
        end
        table.sort(out)
        return out
    end

    before_each(function()
        H = headless.new({ character = dlw.Guardian.character(), pack = "Guardian (wowsims.com)" })
        assert.are.same({}, H.loadErrors)
        for key in pairs(H.Hekili.ErrorDB) do
            H.Hekili.ErrorDB[key] = nil
        end
    end)

    it(
        "warns once for a copy reading a window only another priority declares, naming priority, list, line, window",
        function()
            local packs = H.Hekili.DB.profile.packs
            packs["Declarer"] = pack({
                windows = { { action = "window", window_name = "stalew", duration = "6", enabled = true } },
                default = { { enabled = true, action = "maul", criteria = "window.stalew.up" } },
            })
            packs["Old Copy"] = pack({
                default = {
                    { enabled = true, action = "maul", criteria = "rage>10" },
                    { enabled = true, action = "maul", criteria = "window.stalew.up&rage>5" },
                },
            })
            packs["Own"] = pack({ -- declares it itself: silent
                windows = { { action = "window", window_name = "stalew", duration = "6", enabled = true } },
                default = { { enabled = true, action = "maul", criteria = "window.stalew.down" } },
            })
            H.Hekili.Scripts:LoadScripts()
            local w = warned("Old Copy")
            assert.are.same({}, warned("Own"))
            assert.are.equal(1, #w, table.concat(w, "\n"))
            for _, s in ipairs({ "Old Copy", "default", "line 2", "stalew" }) do
                assert.is_truthy(w[1]:find(s, 1, true), w[1])
            end
            H.Hekili.Scripts:LoadScripts() -- every options edit loads again: still once
            assert.are.equal(1, H.Hekili.ErrorDB[w[1]].n)
        end
    )

    it("names the first line by list, then line number, when several read the stale window", function()
        local packs = H.Hekili.DB.profile.packs
        packs["Declarer"] = pack({
            windows = { { action = "window", window_name = "stalew", duration = "6", enabled = true } },
            default = { { enabled = true, action = "maul", criteria = "window.stalew.up" } },
        })
        packs["Two Lines"] = pack({
            default = {
                { enabled = true, action = "maul", criteria = "rage>1" },
                { enabled = true, action = "maul", criteria = "window.stalew.up" },
                { enabled = true, action = "maul", criteria = "window.stalew.down" },
            },
        })
        H.Hekili.Scripts:LoadScripts()
        local w = warned("Two Lines")
        assert.are.equal(1, #w, table.concat(w, "\n"))
        assert.is_truthy(w[1]:find("line 2 ", 1, true), w[1])
    end)

    it(
        "names a line that needs the window open over an earlier line that still fires (the Retribution copy)",
        function()
            local packs = H.Hekili.DB.profile.packs
            packs["Declarer"] = pack({
                windows = { { action = "window", window_name = "stalew", duration = "6", enabled = true } },
                default = { { enabled = true, action = "maul", criteria = "window.stalew.up" } },
            })
            packs["Ret Copy"] = pack({
                default = {
                    { enabled = true, action = "maul", criteria = "rage>1&!window.stalew.up" }, -- fires: closed reads true
                    { enabled = true, action = "maul", criteria = "rage>2|window.stalew.up" }, -- fires through its other branch
                    { enabled = true, action = "maul", criteria = "rage>3&window.stalew.next.maul" }, -- dead: needs it open
                },
            })
            packs["Only Maybe"] = pack({ -- no line needs it open: the first line, as before
                default = {
                    { enabled = true, action = "maul", criteria = "!window.stalew.up" },
                    { enabled = true, action = "maul", criteria = "rage>2|window.stalew.up" },
                },
            })
            H.Hekili.Scripts:LoadScripts()
            local w = warned("Ret Copy")
            assert.are.equal(1, #w, table.concat(w, "\n"))
            assert.is_truthy(w[1]:find("line 3 ", 1, true), w[1])
            local m = warned("Only Maybe")
            assert.are.equal(1, #m, table.concat(m, "\n"))
            assert.is_truthy(m[1]:find("line 1 ", 1, true), m[1])
        end
    )

    it("is silent for a disabled line, a class window, a priority's own window, and a longer name", function()
        local packs = H.Hekili.DB.profile.packs
        packs["Declarer"] = pack({
            windows = { { action = "window", window_name = "stalew", duration = "6", enabled = true } },
            default = { { enabled = true, action = "maul", criteria = "window.stalew.up" } },
        })
        packs["Quiet"] = pack({
            default = {
                { enabled = false, action = "maul", criteria = "window.stalew.up" },
                { enabled = true, action = "maul", criteria = "mywindow.stalew.up" },
            },
        })
        H.Hekili.Scripts:LoadScripts()
        assert.are.same({}, warned("Quiet"))
        assert.are.same({}, warned("(wowsims.com)")) -- every shipped priority reads only its own or a class window
        -- a class window (registered by a pack's spec): silent, even with a priority trying to declare it
        H.Hekili.Class.kit:RegisterWindow("classw", { duration = 6 })
        H.Hekili.DB.profile.packs["Class Declarer"] =
            pack({ -- a second priority declaring it is the E3 compile error: it never enters declaredWindows (L2000)
                windows = { { action = "window", window_name = "classw", duration = "6", enabled = true } },
                default = { { enabled = true, action = "maul", criteria = "window.classw.up" } },
            })
        H.Hekili.DB.profile.packs["Class Reader"] = pack({
            default = { { enabled = true, action = "maul", criteria = "window.classw.up" } },
        })
        H.Hekili.Scripts:LoadScripts()
        assert.are.same({}, warned("Class Reader"))
    end)

    it("is silent for a window nobody declares (the compile error)", function()
        H.Hekili.DB.profile.packs["Nobody"] = pack({
            default = { { enabled = true, action = "maul", criteria = "window.nowhere_at_all.up" } },
        })
        H.Hekili.Scripts:LoadScripts()
        assert.are.same({}, warned("Nobody"))
    end)
end)
