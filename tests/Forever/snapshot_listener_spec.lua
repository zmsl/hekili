-- tests/Forever/snapshot_listener_spec.lua (central fix 20): Hekili:RegisterSnapshotListener, src/Hekili/Engine/Snapshot.lua.
-- Stock Hekili headless as Arms takes a real snapshot (two display records): each listener runs once with (first
-- index, first record, isAuto), one that raises does not stop the snapshot, and returned strings land in every
-- record's text under "## External".
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("snapshot listeners (headless Arms)", function()
    local H, hk, added

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        hk = H.Hekili
        hk.Engine.settings.screenshot = false -- the harness has no Screenshot()
        hk.DB.profile.toggles.mode.value = "dual" -- Primary and AOE both build, so a snapshot stores two records
        assert.is_true(hk.Engine.Subscribe("AOE", function() end))
        assert(headless.cycle(H, H.ctl.now + 0.2))
        added = {}
    end)

    after_each(function()
        for i = 1, #added do
            hk:UnregisterSnapshotListener(added[i])
        end
    end)

    local function listen(fn)
        added[#added + 1] = fn
        hk:RegisterSnapshotListener(fn)
    end

    it("calls each listener once per snapshot, with the first record's index, that record and isAuto", function()
        local before = #H.ns.snapshots
        local calls = {}
        listen(function(index, record, isAuto)
            calls[#calls + 1] = { index = index, record = record, isAuto = isAuto }
        end)
        hk:MakeSnapshot()
        assert.is_true(#H.ns.snapshots >= before + 2, "records: " .. (#H.ns.snapshots - before)) -- two displays
        assert.are.equal(1, #calls)
        assert.are.equal(before + 1, calls[1].index)
        assert.are.equal(H.ns.snapshots[before + 1], calls[1].record)
        assert.is_false(calls[1].isAuto)
        for i = before + 1, #H.ns.snapshots do
            assert.is_nil(H.ns.snapshots[i].log:find("## External", 1, true)) -- nothing returned, no heading
        end
    end)

    it("keeps the snapshot when a listener raises, and appends returned text under ## External", function()
        local before = #H.ns.snapshots
        listen(function()
            error("boom")
        end)
        listen(function(index)
            return "probe line " .. index .. "\n" .. string.rep("x", 5000)
        end)
        hk:MakeSnapshot()
        assert.is_true(#H.ns.snapshots >= before + 2)
        for i = before + 1, #H.ns.snapshots do -- every display's record of this snapshot carries the block once
            local log = H.ns.snapshots[i].log
            local ext = log:match("\n\n## External\n(.*)$")
            assert.is_string(ext)
            assert.is_nil(ext:find("## External", 1, true))
            assert.is_truthy(ext:find("snapshot listener 1 failed: .*boom"))
            assert.is_truthy(ext:find("probe line " .. (before + 1), 1, true))
            assert.is_nil(ext:find(string.rep("x", 4000), 1, true)) -- the 4000-character cap includes the first line
        end
    end)

    it("stops calling an unregistered listener", function()
        local n = 0
        local fn = function()
            n = n + 1
        end
        listen(fn)
        hk:RegisterSnapshotListener(fn) -- a second registration is a no-op
        hk:UnregisterSnapshotListener(fn)
        hk:MakeSnapshot()
        assert.are.equal(0, n)
    end)
end)
