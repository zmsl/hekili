-- tests/Forever/fury_spec.lua: the Fury kit on the headless engine: a booted Fury Warrior (helpers/warrior_world.lua's
-- character plus Bloodthirst) on its default priority, Fury (wowsims.com).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local BLOODTHIRST = 23881

local H, st

-- A Fury Warrior in `stance`, in melee with a level 60 target.
local function boot(stance)
    local c = ww.character()
    c.known[#c.known + 1] = BLOODTHIRST
    local talents = {}
    for k, v in pairs(ww.TALENTS) do
        talents[k] = v
    end
    talents[BLOODTHIRST] = 1
    c.talents, c.form = talents, ww.FORM[stance]
    H = headless.new({ character = c, pack = "Fury (wowsims.com)" })
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(headless.cycle(H, H.ctl.now + 0.2))
    st = H.Hekili.State
    st.reset("Primary", true) -- the now-state: the cycle's prediction may have simulated a stance return
    assert.is_true(st.buff[stance].up, stance)
end

describe("the Fury kit", function()
    -- The window (Victorious, 20 s) and the 30 s cooldown run apart: a cast is predicted only while both allow it.
    it("refuses Victory Rush when its cooldown ends after Victorious, and allows it when it ends inside", function()
        boot("berserker_stance")
        st.applyBuff("victorious", 5)
        st.cooldown.victory_rush.expires = st.query_time + 12
        st.advance(12)
        assert.is_true(st.cooldown.victory_rush.ready)
        assert.is_false(st.buff.victorious.up)
        assert.is_false((st:IsUsable("victory_rush")))
        st.reset("Primary", true)
        st.applyBuff("victorious", 5)
        st.cooldown.victory_rush.expires = st.query_time + 3
        st.advance(3)
        assert.is_true(st.cooldown.victory_rush.ready)
        assert.is_true(st.buff.victorious.up)
        assert.is_true((st:IsUsable("victory_rush")))
    end)
end)
