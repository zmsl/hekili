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

    -- The recipe's extra line (the user's ruling, 2026-10-21): Victory Rush, free, just above Bloodthirst.
    it("recommends Victory Rush ahead of Bloodthirst inside Victorious, and never outside it", function()
        boot("berserker_stance")
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        H.ctl.auras.target.HARMFUL[1] = { -- Sunder Armor at 5: the list's Sunder lines stand aside
            name = "Sunder Armor",
            spellId = H.Hekili.Class.auras.sunder_armor.id,
            expirationTime = H.ctl.now + 30,
            duration = 30,
            applications = 5,
            sourceUnit = "player",
        }
        H.Fire("UNIT_AURA", "target")
        local function first()
            assert(headless.cycle(H, H.ctl.now + 0.2))
            local p = H.Hekili.Engine.Output.Primary
            local names = {} -- the on-GCD queue: an off-GCD line (Bloodrage) rides beside it
            for i = 1, p.count do
                local n = p.recs[i].actionName
                if H.Hekili.Class.abilities[n].gcd ~= "off" then
                    names[#names + 1] = n
                end
            end
            return names
        end
        local closed = first()
        assert.are.equal("bloodthirst", closed[1], table.concat(closed, " "))
        for _, n in ipairs(closed) do
            assert.are_not.equal("victory_rush", n)
        end
        H.ctl.usable[402927] = { true, false } -- a kill with XP: the client's usability flips
        H.Fire("SPELL_UPDATE_USABLE")
        local open = first()
        assert.are.equal("victory_rush", open[1], table.concat(open, " "))
    end)
end)
