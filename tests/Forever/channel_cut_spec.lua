-- tests/Forever/channel_cut_spec.lua (L1748, owner: "if wowsims cuts channels, we should too"): each wowsims.com pack
-- line that carries wowsims's interruptIf (translator rule 24) compiles to the engine's interrupt_if and reads, through
-- the real engine, while its channel runs: Affliction's Wrack at two ticks with Corruption down, Shadow's Mind Flay at
-- its third tick (MF3: its own end), Evocation's 99% mana.
local headless = require("Game.harness.headless")

-- `C` (a world content) booted on its pack, its channel `key` (spell `id`, `length` s) started at the boot's now and
-- succeeded; returns at(t): the engine's CheckChannel and the line's interrupt_if, `t` s into the channel.
local function channel(C, key, id, length)
    local H = headless.new({ character = C.character(), pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    local st = H.Hekili.State
    local cut = H.Hekili.Scripts.Channels[C.PACK][key].interrupt_if -- compiled from the pack
    assert.are.equal("function", type(cut))
    local t0 = H.ctl.now
    H.ctl.channel = { t0 * 1000, (t0 + length) * 1000, spell = id } -- UnitChannelInfo
    H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
    return function(t)
        H.ctl.now = t0 + t
        st.reset("Primary", true)
        st.system.packName = C.PACK -- the display update's own (Core.lua)
        local a, b = H.Hekili:CheckChannel(nil, 0), cut()
        assert.are.same({}, H.errors)
        return a, b
    end
end

describe("a wowsims.com channel line's interrupt_if through the engine", function()
    it("cuts Wrack at its second tick with Corruption down, not at its first", function()
        local at = channel(require("Forever.helpers.warlock_world").Affliction, "wrack", 1316697, 6)
        assert.are.same({ false, false }, { at(1) }) -- one tick
        assert.are.same({ true, true }, { at(2) }) -- two ticks
    end)

    it("reads Mind Flay's third tick only (its own end)", function()
        local at = channel(require("Forever.helpers.priest_world").Shadow, "mind_flay", 15407, 3)
        assert.are.same({ false, false }, { at(2) })
        assert.is_true(select(2, at(2.995)))
    end)

    it("reads Evocation's 99% mana", function()
        local at = channel(require("Forever.helpers.mage_world").Frost, "evocation", 12051, 8)
        local _, cut = at(1)
        assert.are.equal("boolean", type(cut))
    end)
end)

-- L1753: a channel whose start the engine never saw (a /reload mid-channel: UnitChannelInfo answers, no success fired)
-- is read at the reset from `buff.casting`, its ticks queued, no error.
describe("a channel already running when the engine first looks (a /reload mid-channel)", function()
    it("queues its ticks with no error", function()
        local C = require("Forever.helpers.warlock_world").Affliction
        local H = headless.new({ character = C.character(), pack = C.PACK })
        assert.are.same({}, H.loadErrors)
        local st = H.Hekili.State
        local t0 = H.ctl.now
        H.ctl.channel = { (t0 - 0.5) * 1000, (t0 + 5.5) * 1000, spell = 1316697 } -- Wrack, 0.5 s in, no success
        st.reset("Primary", true)
        assert.are.same({}, H.errors)
        local ticks = 0
        for _, e in ipairs(st.queue) do
            ticks = ticks + (e.type == "CHANNEL_TICK" and 1 or 0)
        end
        assert.are.equal(5, ticks) -- 1 to 5 s in; the one at 6 s is the finish's
    end)
end)
