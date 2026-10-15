-- VirtualState/spec/record_spec.lua: the Belief record, basis, debug rings, Tracked and Track (spec §2, §3.4, §3.6).
local load = require("VirtualState.spec.helpers.load")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("the Belief record", function()
    local ns, VS, I

    before_each(function()
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
    end)

    it("starts unknown with every last slot at t = 0", function()
        local r = I.NewBelief("x")
        assert.are.equal("unknown", r.basis)
        for _, o in ipairs(I.ORIGINS) do
            assert.are.same({ v = 0, t = 0, event = 0 }, r.last[o])
        end
    end)

    it("takes the default only when no other origin was written, and the newest otherwise (ties O, P, M)", function()
        local r = I.NewBelief("x")
        I.Sample(r, "default", 5, 1, 0)
        assert.are.equal("default", r.basis)
        I.Sample(r, "modelled", 6, 2, 3)
        assert.are.equal("modelled", r.basis)
        I.Sample(r, "pinned", 7, 2, 1)
        assert.are.equal("pinned", r.basis)
        I.Sample(r, "observed", 8, 2, 5)
        assert.are.equal("observed", r.basis)
        I.Sample(r, "modelled", 9, 3, 3)
        assert.are.equal("modelled", r.basis)
        assert.are.same({ v = 9, t = 3, event = 3 }, r.last.modelled)
    end)

    it("keeps at most 8 samples per origin in the debug rings, only while debug is on", function()
        I.Build(fs.def(fs.new()), 1)
        local r = I.NewBelief("x")
        assert.is_nil(r.ring)
        VS.SetDebug(true)
        for i = 1, 10 do
            I.Sample(r, "pinned", i, i, 1)
        end
        local ring = r.ring.pinned
        assert.are.equal(I.RING, #ring)
        local seen = {}
        for k = 1, I.RING do
            seen[ring[k].v] = true
        end
        assert.is_nil(seen[1])
        assert.is_true(seen[10] and seen[3])
        VS.SetDebug(false)
        assert.is_nil(r.ring)
        assert.is_truthy(VS.Snapshot():find("x est=", 1, true))
    end)

    it("fills the caller's array with the tracked IDs and clears the rest", function()
        I.TRACKED.aura = { 11, 12 }
        local out = { 1, 2, 3 }
        assert.are.equal(2, VS.Tracked("aura", out))
        assert.are.same({ 11, 12 }, out)
        assert.are.equal(0, VS.Tracked("nothing", out))
        assert.are.same({}, out)
    end)

    it("collects a pack's extra IDs for the next build", function()
        VS.Track({ abilities = { 100 }, auras = { 200, 201 }, units = { "focus" }, talents = { [9] = 8 } })
        assert.are.same({ 100 }, I.extra.abilities)
        assert.are.same({ 200, 201 }, I.extra.auras)
        assert.are.same({ "focus" }, I.extra.units)
        assert.are.equal(8, I.extra.talents[9])
    end)
end)
