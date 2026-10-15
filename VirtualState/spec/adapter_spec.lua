-- VirtualState/spec/adapter_spec.lua: Adapter.lua's first version against a fake Hekili (spec §3.6): the debug
-- handle, the tracked set built at SpecChanged, Drain's fold.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("Adapter", function()
    local ns, VS, I, api, ctl, h, saved

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        saved = {}
        for _, k in ipairs({ "LibStub", "GetTime", "CreateFrame", "debugprofilestop" }) do
            saved[k] = rawget(_G, k) or false
        end
        _G.LibStub = function()
            return { GetTime = api.GetTime }
        end
        _G.GetTime, _G.CreateFrame = api.GetTime, api.CreateFrame -- (Task 8 turns the facade read into a direct one)
        _G.debugprofilestop = function()
            return os.clock() * 1000
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        h = fs.new(9)
        ns.ResourceRegenerates = function()
            return false
        end
        load.adapter(ns, h)
        VS.Start(api)
        VS.SpecChanged()
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("sets the debug handle and builds the tracked set at SpecChanged", function()
        assert.are.equal(VS, h.VirtualState)
        assert.is_true(I.built)
        assert.is_truthy(VS.Snapshot():find("class=WARRIOR", 1, true))
    end)

    it("drains by folding the log up to the cut-off", function()
        ctl.now = 5
        ctl.Fire("PLAYER_STARTED_MOVING")
        ctl.Tick(5)
        VS.Drain(5)
        assert.is_true(VS.Moving())
        assert.are.equal(0, I.log.n)
        assert.are.equal(0, I.drainCasts)
    end)

    it("asks Hekili for a sooner cycle on the urgent lane", function()
        I.Sources.Urgent("PLAYER_SWING")
        assert.are.same({ "PLAYER_SWING" }, h.forced)
    end)
end)
