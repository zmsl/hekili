-- Virtual/State/spec/obslog_spec.lua: the observation ring (spec §4.1).
local load = require("Virtual.State.spec.helpers.load")
local alloc = require("Virtual.State.spec.helpers.alloc")

describe("ObsLog", function()
    local ObsLog

    before_each(function()
        ObsLog = load.module().VirtualStateInternal.ObsLog
    end)

    it("refuses a capacity below 1", function()
        assert.has_error(function()
            ObsLog.New(0)
        end)
    end)

    it("keeps observations oldest first and defaults a, b, c to 0", function()
        local log = ObsLog.New(4)
        ObsLog.Add(log, 1, 10, 5)
        ObsLog.Add(log, 2, 11, 6, 7, 8)
        assert.are.equal(2, log.n)
        local o = ObsLog.At(log, 1)
        assert.are.same({ 1, 10, 5, 0, 0 }, { o.kind, o.t, o.a, o.b, o.c })
        o = ObsLog.Shift(log)
        assert.are.equal(10, o.t)
        assert.are.equal(11, ObsLog.At(log, 1).t)
    end)

    it("drops the oldest when full and counts it", function()
        local log = ObsLog.New(3)
        for i = 1, 5 do
            ObsLog.Add(log, 1, i)
        end
        assert.are.same({ 3, 2 }, { log.n, log.dropped })
        assert.are.same({ 3, 4, 5 }, { ObsLog.At(log, 1).t, ObsLog.At(log, 2).t, ObsLog.At(log, 3).t })
        ObsLog.Clear(log)
        assert.are.equal(0, log.n)
    end)

    it("allocates nothing to add and shift", function()
        local log = ObsLog.New(256)
        assert.are.equal(
            0,
            alloc.bytes(function(i)
                ObsLog.Add(log, 1, i, 2, 3, 4)
                ObsLog.Shift(log)
            end, 10000)
        )
    end)
end)
