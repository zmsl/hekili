-- tests/Forever/stale_window_warning_spec.lua (L1937): a priority line that reads a window another priority declares, but
-- neither its own priority nor a class pack does, never fires (the window reads closed). LoadScripts reports it once
-- a session through Hekili:Error (the Warnings page). A window the priority declares itself, or a class pack registers,
-- is silent; a name nobody declares stays the compile error.
local headless = require("Game.harness.headless")
local dlw = require("Forever.helpers.druid_loop_world")

describe("the stale window read warning", function()
    local H

    local function pack(lists)
        return { spec = H.Hekili.State.spec.id, builtIn = false, lists = lists }
    end

    local function warned()
        local out = {}
        for key in pairs(H.Hekili.ErrorDB) do
            if key:find("never fire", 1, true) then
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
            local w = warned()
            assert.are.equal(1, #w, table.concat(w, "\n"))
            for _, s in ipairs({ "Old Copy", "default", "line 2", "stalew" }) do
                assert.is_truthy(w[1]:find(s, 1, true), w[1])
            end
            H.Hekili.Scripts:LoadScripts() -- every options edit loads again: still once
            assert.are.equal(1, H.Hekili.ErrorDB[w[1]].n)
        end
    )

    it("is silent for a window nobody declares (the compile error)", function()
        H.Hekili.DB.profile.packs["Nobody"] = pack({
            default = { { enabled = true, action = "maul", criteria = "window.nowhere_at_all.up" } },
        })
        H.Hekili.Scripts:LoadScripts()
        assert.are.same({}, warned())
    end)
end)
