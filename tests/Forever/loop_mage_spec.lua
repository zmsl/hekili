-- tests/Forever/loop_mage_spec.lua (class-completion plan, "The per-pack gate"): the Mage loop worlds
-- (tests/Forever/helpers/mage_world.lua) boot as a level 60 Mage on their spec and map every ability the character
-- knows. The solo gates (`Arcane solo:`, `Fire solo:`) come with the wowsims.com packs (the next task); the channels
-- (Arcane Missiles, Evocation) wait on the harness world's player channel (a shared gap: C.resolve raises for them).
local headless = require("Game.harness.headless")
local mw = require("Forever.helpers.mage_world")

describe("the Mage loop worlds", function()
    for _, name in ipairs({ "Arcane", "Fire" }) do
        it(name .. ": boots on its spec, and maps every ability the character knows", function()
            local C = mw[name]
            local H = headless.new({ character = C.character() })
            assert.are.same({}, H.loadErrors)
            local unmapped = {}
            for key, a in pairs(H.Hekili.Class.abilities) do
                if type(key) == "string" and a.key == key and a.id and H.ctl.known[a.id] and not mw.MAP[key] then
                    unmapped[#unmapped + 1] = key
                end
            end
            table.sort(unmapped)
            assert.are.same({}, unmapped)
            -- the dominant tree of the preset build picks the spec: the pick settles in the event frame's own
            -- OnUpdate (Engine/Sim/Events.lua; the harness's cycle does not run it), as spec_choice_spec.lua settles it
            for _, f in ipairs(H.frames) do
                local u = f.__scripts.OnUpdate
                if u and debug.getinfo(u, "S").source:find("Engine/Sim/Events.lua", 1, true) then
                    for _ = 1, 2 do
                        u(f, 0.016)
                    end
                end
            end
            assert.are.equal(C.SPEC, H.Hekili.State.spec.id)
            assert.is_false(pcall(C.resolve, "not_an_ability", H))
            local ok, err = pcall(C.resolve, "evocation", H)
            assert.are.same({ false, true }, { ok, tostring(err):find("no player channel", 1, true) ~= nil })
            -- a cast press: its top rank's cost and cast time on the true state
            local key = name == "Arcane" and "arcane_wrath" or "fireball"
            local p = C.resolve(key, H)
            assert.are.same(
                name == "Arcane" and { 395, 3.5, 6 } or { 410, 3, 0 }, -- Improved Fireball 5/5: 3.5 - 0.5
                { p.cost, p.cast, p.cooldown }
            )
            assert.is_true(#C.usable(H) > 0)
            assert.are.same({}, H.errors)
        end)
    end
end)
