-- tests/Forever/snapshot_listener_spec.lua (central fix 20): Hekili:RegisterSnapshotListener, src/Hekili/Engine/Snapshot.lua.
-- Stock Hekili headless as Arms takes a real snapshot: listeners get (index, record, isAuto), one that raises does
-- not stop the snapshot, and returned strings land in the record's text under "## External".
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("snapshot listeners (headless Arms)", function()
    local H, hk, added

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        hk = H.Hekili
        hk.Engine.settings.screenshot = false -- the harness has no Screenshot()
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

    it("calls each listener with the stored record's index, the record and isAuto", function()
        local calls = {}
        listen(function(index, record, isAuto)
            calls[#calls + 1] = { index = index, record = record, isAuto = isAuto }
        end)
        hk:MakeSnapshot()
        assert.is_true(#calls >= 1)
        for i = 1, #calls do
            assert.are.equal(H.ns.snapshots[calls[i].index], calls[i].record)
            assert.is_false(calls[i].isAuto)
        end
        assert.is_nil(calls[1].record.log:find("## External", 1, true)) -- nothing returned, no heading
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
        assert.is_true(#H.ns.snapshots > before)
        local snap = H.ns.snapshots[before + 1]
        local ext = snap.log:match("\n\n## External\n(.*)$")
        assert.is_string(ext)
        assert.is_truthy(ext:find("snapshot listener 1 failed: .*boom"))
        assert.is_truthy(ext:find("probe line " .. (before + 1), 1, true))
        assert.is_nil(ext:find(string.rep("x", 4000), 1, true)) -- the 4000-character cap includes the first line
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
