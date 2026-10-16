-- tests/Virtual/API/trace_spec.lua (event-facade spec §5, decisions 3 and 8): while Hekili makes a snapshot
-- (`ActiveDebug`), every facade read and every event writes one line through Hekili:Debug, naming the class that
-- answered; a secret is shown as S and counted for a passthrough; off, nothing is written and nothing allocated.
local load = require("Virtual.State.helpers.load")
local fake = require("Virtual.State.helpers.fake_api")
local alloc = require("Virtual.State.helpers.alloc")
local fs = require("Virtual.State.helpers.fake_spec")

describe("the facade trace", function()
    local api, ctl, ns, Facade, lines, hekili, saved

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        local globals = {
            CreateFrame = api.CreateFrame,
            issecretvalue = api.issecretvalue,
            GetTime = api.GetTime,
            UnitName = function(unit)
                if unit == "target" then
                    return fake.SECRET
                end
                return "Me"
            end,
            GetHaste = function()
                return fake.SECRET
            end,
            GetInstanceInfo = function()
                return { spellId = fake.SECRET, expirationTime = 5 }, { startTime = fake.SECRET, duration = 1 }
            end,
        }
        for k, v in pairs(globals) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        Facade = ns.Facade
        lines = {}
        hekili = { ActiveDebug = false }
        function hekili:Debug(fmt, ...)
            lines[#lines + 1] = string.format(fmt, ...)
        end
        Facade.Attach(hekili)
        ns.VirtualStateInternal.Build(fs.def(fs.new(9)), 1)
        ns.VirtualState.Start(api)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("writes nothing while Hekili is not debugging", function()
        Facade.UnitName("player")
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.are.same({}, lines)
    end)

    it("writes one line per read naming the class, with a secret shown as S and counted", function()
        hekili.ActiveDebug = true
        Facade.UnitName("player")
        Facade.UnitName("target")
        Facade.GetHaste()
        Facade.UnitPower("target", 1)
        Facade.GetTime()
        assert.are.same({
            "[vs] passthrough UnitName(player, nil) -> Me, nil, nil, nil #1",
            "[vs] passthrough UnitName(target, nil) -> S, nil, nil, nil #1",
            "[vs] hybrid:model GetHaste(nil, nil) -> 0, nil, nil, nil #1",
            "[vs] virtual UnitPower(target, 1) -> 0, nil, nil, nil #1",
        }, lines) -- GetTime is quiet: counted, not written
        assert.are.equal(1, Facade.secrets.UnitName)
        assert.are.equal(1, Facade.counts.GetTime)
    end)

    it("writes a table result's secret fields as S, and keeps tracing after a raising Debug", function()
        hekili.ActiveDebug = true
        Facade.GetInstanceInfo()
        assert.are.same({ "[vs] passthrough GetInstanceInfo(nil, nil) -> aura:S/5/nil, cd:S/1, nil, nil #2" }, lines)
        local debug = hekili.Debug
        hekili.Debug = function()
            error("boom")
        end
        assert.has_no.errors(function()
            Facade.UnitName("player")
        end)
        hekili.Debug = debug
        Facade.UnitName("player")
        assert.are.equal("[vs] passthrough UnitName(player, nil) -> Me, nil, nil, nil #1", lines[#lines])
    end)

    it("writes a line per event the layer receives", function()
        local f = ns.VirtualStateInternal.Events.CreateFrame("Frame")
        f:SetScript("OnEvent", function() end)
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        hekili.ActiveDebug = true
        ctl.Fire("PLAYER_TARGET_CHANGED", fake.SECRET)
        assert.are.same({ "[vs] event PLAYER_TARGET_CHANGED(nil, nil, nil)" }, lines)
    end)

    it("allocates nothing per read while tracing is off", function()
        local bytes = alloc.bytes(function()
            Facade.UnitName("player")
            Facade.GetHaste()
            Facade.UnitPower("player", 1)
        end, 10000)
        assert.are.equal(0, bytes)
    end)
end)
