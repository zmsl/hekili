-- tests/Game/API/trace_spec.lua (event-facade spec §5, decisions 3 and 8): while Hekili makes a snapshot
-- (`ActiveDebug`), every facade read and every event writes one line through Hekili:Debug, naming the class that
-- answered; a secret is shown as S and counted for a passthrough; off, nothing is written and nothing allocated.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local alloc = require("Game.State.helpers.alloc")
local fs = require("Game.State.helpers.fake_spec")

describe("the facade trace", function()
    local api, ctl, ns, Facade, lines, hekili, saved

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        local globals = {
            CreateFrame = api.CreateFrame,
            issecretvalue = api.issecretvalue,
            GetTime = api.GetTime,
            UnitClass = function(unit)
                if unit == "target" then
                    return fake.SECRET
                end
                return "Me"
            end,
            GetHaste = function()
                return fake.SECRET
            end,
            UnitExists = function(unit)
                if unit == "target" then
                    return fake.SECRET
                end
                return false
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
        ns.VirtualState.SetLog({
            active = function()
                return hekili.ActiveDebug
            end,
            write = function(...)
                hekili:Debug(...)
            end,
        })
        ns.VirtualStateInternal.Build(fs.def(fs.new(9)), 1)
        ns.VirtualState.Start(api)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("fills the logger's onOpen: the belief's own Snapshot(), or one failure line when it raises", function()
        local logger = {
            active = function()
                return true
            end,
            write = function(...)
                lines[#lines + 1] = string.format(...)
            end,
        }
        ns.VirtualState.SetLog(logger)
        logger.onOpen()
        assert.are.equal(1, #lines)
        assert.are.equal(1, lines[1]:find("VirtualState t=", 1, true))
        local snapshot = ns.VirtualState.Snapshot
        ns.VirtualState.Snapshot = function()
            error("snap boom", 0)
        end
        logger.onOpen()
        ns.VirtualState.Snapshot = snapshot
        assert.are.equal("[vs] snapshot failed: snap boom", lines[2])
    end)

    it("writes nothing while Hekili is not debugging", function()
        Facade.UnitClass("player")
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.are.same({}, lines)
    end)

    it("writes one line per read naming the class, with a secret shown as S and counted", function()
        hekili.ActiveDebug = true
        Facade.UnitClass("player")
        Facade.UnitClass("target")
        Facade.GetHaste()
        Facade.UnitPower("target", 1)
        Facade.GetTime()
        assert.are.same({
            "[vs] passthrough UnitClass(player, nil) -> Me, nil, nil, nil #1",
            "[vs] passthrough UnitClass(target, nil) -> S, nil, nil, nil #1",
            "[vs] hybrid:model GetHaste(nil, nil) -> 0, nil, nil, nil #1",
            "[vs] hybrid:model UnitPower(target, 1) -> 0, nil, nil, nil #1",
        }, lines) -- GetTime is quiet: counted, not written
        assert.are.equal(1, Facade.secrets.UnitClass)
        assert.are.equal(1, Facade.counts.GetTime)
    end)

    it("counts a hybrid's secret raw answer (UnitExists of another unit), and not the pet's plain one", function()
        hekili.ActiveDebug = true
        Facade.UnitExists("target")
        assert.is_false(Facade.UnitExists("pet"))
        assert.are.same({
            "[vs] hybrid:raw UnitExists(target, nil) -> S, nil, nil, nil #1",
            "[vs] hybrid:raw UnitExists(pet, nil) -> false, nil, nil, nil #1",
        }, lines)
        assert.are.same({ UnitExists = 1 }, Facade.secrets)
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
            Facade.UnitClass("player")
        end)
        hekili.Debug = debug
        Facade.UnitClass("player")
        assert.are.equal("[vs] passthrough UnitClass(player, nil) -> Me, nil, nil, nil #1", lines[#lines])
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
            Facade.UnitClass("player")
            Facade.GetHaste()
            Facade.UnitPower("player", 1)
        end, 10000)
        assert.are.equal(0, bytes)
    end)
end)
