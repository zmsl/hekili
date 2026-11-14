-- tests/Forever/talent_copy_aura_spec.lua (v0.8.2 review, Important 1): the packs' auras that list their talent's own
-- spell as a `copy` (the Cooldown Manager links both). If the client lists the talent's passive (no expiry) on the
-- player, the walk must not read the buff up for good (a regen or damage share always on); a timed listing under the
-- same ID is still the buff, and an aura whose own ID is the talent (Shadowform) still reads its permanent listing up.
local headless = require("Game.harness.headless")

local CASES = {
    { "priest_world", "Shadow", "spirit_tap", 15270 },
    { "shaman_world", "Enhancement", "improved_stormstrike", 1223031 },
    { "shaman_world", "Enhancement", "flurry", 16256 },
    { "shaman_world", "Elemental", "elemental_devastation", 30160 },
    { "paladin_world", "Protection", "redoubt", 20127 },
    { "paladin_world", "Protection", "reckoning", 20177 },
    { "hunter_world", "Marksmanship", "sniper_shot", 1310687 },
}

describe("a talent's spell an aura lists as its copy", function()
    local function boot(world, content)
        local C = require("Forever.helpers." .. world)[content]
        local H = headless.new({ character = C.character() })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        return H
    end

    -- The client lists `id` on the player expiring at `expires` (0 none; nil: nothing listed) at t.
    local function list(H, t, id, expires)
        H.ctl.now = t
        H.ctl.auras.player.HELPFUL[1] = id and { spellId = id, expirationTime = expires, applications = 0 } or nil
        H.Fire("UNIT_AURA", "player")
        assert(headless.cycle(H, t + 0.1))
        H.ns.VirtualState.Drain(t + 0.1)
    end

    for _, c in ipairs(CASES) do
        local world, content, key, copy = c[1], c[2], c[3], c[4]
        it(key .. " (" .. copy .. "): no expiry is the talent's passive, a timed listing is the buff", function()
            local H = boot(world, content)
            local class = H.Hekili.Class
            assert.are.equal(copy, class.talents[key][2]) -- the copy is the talent's spell
            local id = class.auras[key].id
            assert.are_not.equal(copy, id)
            local VS, t = H.ns.VirtualState, H.ctl.now + 1
            list(H, t, copy, 0)
            assert.is_nil(VS.Aura("player", id, t + 0.1))
            list(H, t + 1, copy, t + 9)
            local rec = VS.Aura("player", id, t + 1.1)
            assert.is_not_nil(rec)
            assert.are.equal(t + 9, rec.est)
            assert.are.same({}, H.errors)
        end)
    end

    it("Shadowform, whose own ID is the talent: its permanent listing still reads up", function()
        local H = boot("priest_world", "Shadow")
        local class = H.Hekili.Class
        assert.are.equal(class.auras.shadowform.id, class.talents.shadowform[2])
        local t = H.ctl.now + 1
        list(H, t, 15473, 0)
        assert.is_not_nil(H.ns.VirtualState.Aura("player", 15473, t + 0.1))
        assert.are.same({}, H.errors)
    end)
end)
