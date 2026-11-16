-- tests/Forever/scripts_size_spec.lua (CN25): Engine/Sim/Scripts.lua on long conditions. SimToLua turned at most 100
-- bare `!` into `not` and left the rest in the Lua text, so a longer condition never compiled ("unexpected symbol near
-- '!'", the re-pinned Feral pack's builders).
local headless = require("Game.harness.headless")

describe("Scripts.lua on a long condition (CN25)", function()
    local Sc
    setup(function()
        Sc = headless.new({}).Hekili.Scripts
    end)

    it("turns every bare ! into not, past 100 of them", function()
        local t = {}
        for i = 1, 150 do
            t[i] = "!buff.b" .. i .. ".up"
        end
        local lua = Sc.SimToLua(table.concat(t, "&"))
        assert.is_nil(lua:find("!", 1, true))
        assert.is_function((loadstring("return " .. lua)))
    end)
end)

-- A pure variable (Scripts.lua LoadScripts: a `variable` line with a value and nothing else, the only one of its name)
-- reads as its value inlined at the read would: the translator hoists a large wowsims variable into one (CN25).
describe("a pure variable reads as its inlined text (CN25)", function()
    local ww = require("Forever.helpers.warrior_world")

    -- Headless Arms; `hoist`: every condition of the pack moved into a variable line heading the default list and
    -- read by name (`variable,name=vN,value=<condition>`, the condition `variable.vN`).
    local function boot(hoist)
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        if hoist then
            local lists, defs = H.Hekili.DB.profile.packs[ww.PACK].lists, {}
            for _, name in ipairs({ "precombat", "default" }) do
                for _, e in ipairs(lists[name] or {}) do
                    if (e.criteria or "") ~= "" then
                        defs[#defs + 1] =
                            { action = "variable", enabled = true, var_name = "v" .. #defs + 1, value = e.criteria }
                        e.criteria = "variable.v" .. #defs
                    end
                end
            end
            assert.is_true(#defs > 5)
            for i = #defs, 1, -1 do
                table.insert(lists.default, 1, defs[i])
            end
            H.Hekili:LoadScripts()
            H.Hekili:ReviewPacks() -- the moved entries active (actsActive is keyed by index)
        end
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        H.Fire("PLAYER_REGEN_DISABLED")
        return H
    end

    -- Bytes `H` allocates per cycle over n cycles, the collector stopped (tests/Game/State/helpers/alloc.lua's way).
    local function perCycle(H, t, n)
        collectgarbage("collect")
        collectgarbage("collect")
        collectgarbage("stop")
        headless.cycle(H, t)
        local b = collectgarbage("count")
        for i = 1, n do
            headless.cycle(H, t + i * 0.2)
        end
        local d = (collectgarbage("count") - b) * 1024 / n
        collectgarbage("restart")
        return d
    end

    it("recommends the same actions at the same times, registers nothing and allocates nothing more", function()
        local A, B = boot(false), boot(true)
        assert.are.equal(A.ctl.now, B.ctl.now)
        local t = A.ctl.now
        for i = 1, 40 do
            t = t + 0.5
            for _, H in ipairs({ A, B }) do
                H.ctl.power[1] = (i * 17) % 100
                headless.cycle(H, t)
            end
            local ra, rb = A.Hekili.Engine.Output.Primary.recs, B.Hekili.Engine.Output.Primary.recs
            for j = 1, 3 do
                local a, b = ra[j] or {}, rb[j] or {}
                assert.are.same({ i, j, a.actionName, a.time }, { i, j, b.actionName, b.time })
            end
        end
        assert.are.same({}, B.errors)
        assert.is_nil(next(B.Hekili.State.varDB)) -- read in place: never registered
        for id, s in pairs(B.Hekili.Scripts.DB) do -- a read's own time is its value's, never `safenum(variable.vN)`
            assert.is_nil((s.RecheckScript or ""):find("variable", 1, true), id)
        end
        assert.are.equal(perCycle(A, t + 1, 30), perCycle(B, t + 1, 30))
    end)
end)
