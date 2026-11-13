-- tests/Forever/helpers/druid_vs.lua: the Forever Druid in a real VirtualState (tests/Forever/druid_spec.lua's "in
-- VirtualState's now context" and the Druid harness scenarios, tests/Forever/helpers/druid_world.lua): Hekili's class
-- built from the class file's registrations (load_druid.lua's recording load; values evaluated at talent rank 0,
-- functions kept in `funcs`) and handed to the build (Engine/Schema/Tracked.lua) through the fake spec provider.
local ld = require("Forever.helpers.load_druid")
local load = require("Game.State.helpers.load")
local fs = require("Game.State.helpers.fake_spec")

local M = {}

--- Builds the Druid's class into the VirtualState `ns` loaded (Game.State.helpers.load) on fake_api `api` and
--- starts it at SpecChanged. `edit(class, w)` (optional) changes the class before the build (a scenario's declaration
--- variant). Returns `w` (the recording load, bound to this VirtualState) and `h` (the fake Hekili). The caller sets
--- the globals the build reads (GetTime, UnitGUID, CreateFrame, issecretvalue, debugprofilestop) and clears
--- `fs.clock` afterwards.
function M.boot(ns, api, edit)
    local VS = ns.VirtualState
    local w = ld.load(VS) -- the class file's knownRank reads this VirtualState
    w.state.mainhand_speed = 2.5
    local e = ld.env(w)
    local class = { primaryResource = "energy", abilities = {}, auras = {}, talents = w.talents }
    -- the rate-field entries (Bear Form's energy pause), which Spec/Regen.lua moves out of the model into regenMult
    local rates = {}
    for _, m in pairs(w.resources[3].models or {}) do
        if m.mult or m.spirit or m.share or m.mp5 then
            rates[#rates + 1] = m
        end
    end
    class.resources = {
        energy = { type = 3, state = { meta = w.resources[3].meta, regenMult = rates } },
        combo_points = { type = 4, state = {} },
        rage = { type = 1, state = { regenModel = w.resources[1].models, meta = w.resources[1].meta } },
        mana = { type = 0, state = { meta = w.resources[0].meta } }, -- its `base`: a fraction cost's base mana
    }
    for key, a in pairs(w.abilities) do
        class.abilities[key] = {
            key = key,
            id = a.id,
            copy = a.copy,
            -- Feral Charge's cost reads the form (Bear Form's only): the belief runs it (Engine/Schema/Tracked.lua)
            spend = key == "feral_charge" and a.spend or (a.spend ~= nil and ld.run(a.spend, e) or nil),
            spendType = a.spendType,
            cooldown = ld.run(a.cooldown, e),
            gcd = a.gcd,
            onNextSwing = a.onNextSwing,
            startsCombat = ld.run(a.startsCombat, e), -- Rows.lua credits a strike's hit to its cast
            refundOnAvoid = a.refundOnAvoid, -- an avoid's refund (Families/Now.lua)
            ladder = a.ladder, -- `false`: its answers are no rungs (Families/Resources.lua)
            expects = a.expects, -- the declared outcome (Families/Expect.lua): which rows its ticket takes
            velocity = a.velocity,
            school = a.school,
            cast = 0,
            charges = 1,
            recharge = 0,
            funcs = { now = a.now, handler = a.handler, onCrit = a.onCrit },
        }
    end
    for key, a in pairs(w.auras) do
        class.auras[key] = {
            key = key,
            id = a.id,
            copy = a.copy,
            duration = a.duration,
            max_stack = a.max_stack,
            tick_time = a.tick_time, -- a declared ticking outcome's schedule (Families/Expect.lua)
            dot = a.dot,
        }
    end
    if edit then
        edit(class, w)
    end
    local h = fs.new(9)
    h.Class = class
    fs.clock = api.GetTime
    ns.spendResources = fs.spend
    ns.ResourceRegenerates = function(k)
        return k == "energy" or k == "mana"
    end
    ns.ResourceIsPoints = function(k) -- Constants.lua's, for the one point resource here
        return k == "combo_points"
    end
    -- Clearcasting and Nature's Grace, as spec:RegisterCostMod and spec:RegisterGcdMod append them
    ns.raceMods = { maxMods = {}, costMods = w.costMods, gcdMods = w.gcdMods }
    load.schema(ns, h)
    VS.Start(api)
    ns.BuildTracked()
    return w, h
end

return M
