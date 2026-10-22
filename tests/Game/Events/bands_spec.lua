-- tests/Game/Events/bands_spec.lua (owner ruling 2026-10-22): amount bands, written once.
local load = require("Game.State.helpers.load")

describe("amount bands", function()
    local B = load.module().VirtualStateInternal.Bands

    it("normalises by policy: a crit halved; theirs divide a crush and drop a partial block", function()
        assert.are.same({ 15, 30, 30 }, {
            B.Normalise(30, "CRITICAL", "ours"),
            B.Normalise(30, "CRUSHING", "ours"),
            B.Normalise(30, "BLOCK_REDUCED", "ours"),
        })
        assert.are.same({ 15, 20 }, { B.Normalise(30, "CRITICAL", "theirs"), B.Normalise(30, "CRUSHING", "theirs") })
        assert.is_nil(B.Normalise(30, "BLOCK_REDUCED", "theirs"))
        assert.is_nil(B.Normalise(nil, "", "ours"))
    end)

    it("learns min and max with no creep, and creeps toward a sample inside", function()
        local lo, hi, n = { 0 }, { 0 }, { 0 }
        for _, v in ipairs({ 20, 24, 18 }) do
            B.Learn(lo, hi, n, 1, v, 0)
        end
        assert.are.same({ 18, 24, 3 }, { lo[1], hi[1], n[1] })
        B.Learn(lo, hi, n, 1, 22, 0.05)
        assert.is_true(math.abs(lo[1] - 18.2) < 1e-12 and math.abs(hi[1] - 23.9) < 1e-12)
    end)

    it("fits once taught, and grades a fixed range", function()
        local lo, hi, n = { 18 }, { 24 }, { 3 }
        assert.is_true(B.Fits(lo, hi, n, 1, 28, 0.8, 1.2, 3))
        assert.is_false(B.Fits(lo, hi, n, 1, 29, 0.8, 1.2, 3))
        assert.is_false(B.Fits(lo, hi, { 2 }, 1, 20, 0.8, 1.2, 3))
        assert.are.same({ 1, 2, 3, 0, 0 }, {
            B.Class(40, 36, 50, 21.6),
            B.Class(54, 36, 50, 21.6),
            B.Class(90, 36, 50, 21.6),
            B.Class(101, 36, 50, 21.6),
            B.Class(10, 36, 50, 21.6),
        })
    end)
end)
