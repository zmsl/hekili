-- tests/Forever/interrupt_engine_spec.lua (INT-0, L1805): the target cast's interruptibility from the facade through
-- debuff.casting.v2 to state.timeToInterrupt, the readyTime of every interrupt ability. Unknown reads 3600 (no
-- interrupt), as does known not; known yes reads the cast's time.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

-- timeToInterrupt after a target cast (or channel) start and an optional interruptible event.
local function tti(event, channel)
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    local st, VI = H.Hekili.State, H.ns.VirtualStateInternal
    H.ctl.now = 1100 -- the harness clock starts at 1000: an earlier event sits behind the boot rows and never folds
    assert(headless.cycle(H, 1100))
    H.Fire(channel and "UNIT_SPELLCAST_CHANNEL_START" or "UNIT_SPELLCAST_START", "target", fake.SECRET, fake.SECRET, 77)
    if event then
        H.Fire(event, "target")
    end
    assert(headless.cycle(H, 1100.2))
    VI.Sources.Flush() -- the update alone does not fold the staged cast
    VI.Fold(1100.2, false)
    st.reset("Primary", true)
    return st.timeToInterrupt()
end

describe("timeToInterrupt on a target cast", function()
    for _, channel in ipairs({ false, true }) do
        local what = channel and "channel" or "cast"
        it("reads 3600 on an unknown or uninterruptible " .. what .. ", its time on an interruptible one", function()
            assert.are.equal(3600, tti(nil, channel), what .. " unknown")
            assert.is_true(tti("UNIT_SPELLCAST_INTERRUPTIBLE", channel) < 3600, what .. " interruptible")
            assert.are.equal(3600, tti("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", channel), what .. " not interruptible")
        end)
    end
end)
