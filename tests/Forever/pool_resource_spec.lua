-- tests/Forever/pool_resource_spec.lua (fable-eng3-decision.md Q2, reading D; L893, L1908): a plain pool_resource line
-- (no for_next) holds every line below it, in its list and in the callers that reached it, at each time its condition
-- holds; the lines below are offered from the condition's first false time, as a countdown; `wait=` has no effect.
-- Headless Combat Rogue with a test priority; energy regenerates at 10 a second.
local headless = require("Game.harness.headless")
local rw = require("Forever.helpers.rogue_world")

local C = rw.Combat
local H, S, t, energy

local function boot(e)
    H = headless.new({ character = C.character(), pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    S = H.Hekili.State
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    energy = e
    H.ctl.power[3] = energy
    H.Fire("PLAYER_TARGET_CHANGED")
    t = H.ctl.now + 0.2
    assert(headless.cycle(H, t))
    H.ctl.combat = true
    H.Fire("PLAYER_REGEN_DISABLED")
end

-- The pack's lists from simc text by list name; loads the scripts.
local function load(lists)
    local out = { precombat = {} }
    for name, text in pairs(lists) do
        local lines, warnings = H.Hekili:ParseActionList(text, true)
        assert.are.same({}, warnings or {})
        for _, l in ipairs(lines) do
            l.enabled = true
        end
        out[name] = lines
    end
    H.Hekili.DB.profile.packs[C.PACK].lists = out
    H.Hekili:LoadScripts()
    H.Hekili:ReviewPacks()
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
end

-- One update `dt` [0.2] s on (energy regenerating 10 a second, capped at 100); Primary's first record { name, wait }.
local function tick(dt)
    dt = dt or 0.2
    t = t + dt
    energy = math.min(100, energy + 10 * dt)
    H.ctl.power[3] = energy
    assert(headless.cycle(H, t))
    assert.are.same({}, H.errors)
    local r = H.Hekili.Engine.Output.Primary.recs[1]
    return { r.actionName or false, r.actionName and math.floor(r.wait * 100 + 0.5) / 100 or false }
end

-- Three updates of `lists` from energy `e` [60]: Primary's first record at each.
local function run(lists, e)
    boot(e or 60)
    load(lists)
    return { tick(), tick(), tick() }
end

local ABOVE = "actions+=/shank,if=time>4\n" -- above the line, a countdown of its own (4 s into the fight)
local FILLER = "actions+=/sinister_strike"

describe("a plain pool_resource line (reading D)", function()
    it("1/2: the line below shows at the time the condition ends, counting down by the poll interval", function()
        local recs = run({ default = ABOVE .. "actions+=/pool_resource,if=energy<90\n" .. FILLER })
        -- energy 62 at the first update: 90 at +2.8 s, not now and not at wait= (its default 0.5)
        assert.are.same({ { "sinister_strike", 2.8 }, { "sinister_strike", 2.6 }, { "sinister_strike", 2.4 } }, recs)
        assert.are.same({ "sinister_strike", 0 }, run({ default = ABOVE .. FILLER })[1]) -- the same list without it
    end)

    it("3: wait= has no effect", function()
        local half = run({ default = ABOVE .. "actions+=/pool_resource,wait=0.5,if=energy<90\n" .. FILLER })
        local five = run({ default = ABOVE .. "actions+=/pool_resource,wait=5,if=energy<90\n" .. FILLER })
        assert.are.same(half, five)
        assert.are.same(run({ default = ABOVE .. "actions+=/pool_resource,if=energy<90\n" .. FILLER }), five)
    end)

    it("4: held through the whole window, nothing below shows; the line above keeps its countdown", function()
        local recs = run({ default = ABOVE .. "actions+=/pool_resource,if=energy<200\n" .. FILLER })
        assert.are.same({ { "shank", 3.8 }, { "shank", 3.6 }, { "shank", 3.4 } }, recs)
    end)

    it("5: inside a called list, the caller's lines below are held too", function()
        local recs = run({
            default = ABOVE .. "actions+=/call_action_list,name=pool\n" .. FILLER,
            pool = "actions+=/pool_resource,if=energy<90",
        })
        assert.are.same({ "sinister_strike", 2.8 }, recs[1])
    end)

    it("6: a condition that never holds changes nothing", function()
        local base = run({ default = ABOVE .. FILLER })
        assert.are.same(base, run({ default = ABOVE .. "actions+=/pool_resource,if=energy<10\n" .. FILLER }))
    end)

    -- for_next=1 keeps its own path: the forecast advances to the next entry's cost, so that entry shows at 0 (as on
    -- the parent commit, where the same list gives the same records; without the line it waits 1.8 s for its cost)
    it("7: for_next=1 keeps its own path", function()
        local SS = { "sinister_strike", 0 }
        assert.are.same({ SS, SS, SS }, run({ default = "actions+=/pool_resource,for_next=1\n" .. FILLER }, 20))
    end)
end)
