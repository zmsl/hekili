-- tests/Forever/ttd_hints_spec.lua (lane B8, owner L1651, L1658): Hekili's time-to-die hints to LibTimeToDie.
-- HintBelow("Hekili", pct), threshold only (the factor learned), with the highest execute line present: the player's
-- own from its pack (abilities with `healthGate` while known, `ttdBelow` lines while their talent has a rank; these
-- replace the shared default for the player's class), and each group member's class default from shared content
-- (Shared:RegisterTtdLines), tanks out. Sent out of combat at login/spec change and GROUP_ROSTER_UPDATE (in combat:
-- at PLAYER_REGEN_ENABLED). Core's existing
-- handlers are extended, never doubled (owner 2026-11-22: "please do not construct new things when hekili had already
-- previously been designed with cleu in mind"). The library is a double in the instance's LibStub.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local mw = require("Forever.helpers.mage_world")
local lw = require("Forever.helpers.warlock_world")

local MAJOR = "LibTimeToDie-1.0"

local function double()
    local lib = { hints = {} }
    local h = { state = "priming" }
    function h.Get(self)
        return nil, nil, nil, self.state
    end
    function h.Release() end
    function lib.Track()
        return h
    end
    function lib.HintBelow(_, owner, pct, factor)
        lib.hints[#lib.hints + 1] = { "below", owner, pct, factor }
        return true
    end
    return lib
end

local function new(C)
    local H = headless.new({ character = C.character(), pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    local lib = double()
    local stub = rawget(H.env, "LibStub")
    stub.libs[MAJOR], stub.minors[MAJOR] = lib, 2
    return H, lib
end

-- The last threshold sent (nil: none sent, false: cleared).
local function below(lib)
    for i = #lib.hints, 1, -1 do
        local x = lib.hints[i]
        if x[1] == "below" then
            assert.are.equal("Hekili", x[2])
            assert.is_nil(x[4]) -- threshold only: the factor is learned
            return x[3] or false
        end
    end
end

local function member(H, token, class, role)
    H.ctl.exists[token] = true
    H.ctl.unitClass[token] = class
    H.ctl.roles[token] = role
end

describe("time-to-die hints (lane B8)", function()
    it("solo: the player's own line from its pack (an ability's healthGate, known)", function()
        local H, lib = new(ww)
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(20, below(lib))
    end)

    it("the pack's line replaces the shared default for the player's class", function()
        local H, lib = new(ww)
        H.Hekili:NewShared():RegisterTtdLines({ WARRIOR = 50 })
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(20, below(lib))
    end)

    it("a talent line counts while its talent has a rank", function()
        local H, lib = new(ww)
        local st, key = H.Hekili.State, nil
        for k, t in pairs(st.talent) do
            if type(t) == "table" and (t.rank or 0) > 0 then
                key = k
                break
            end
        end
        assert.is_string(key)
        local a = H.Hekili.Class.abilities.hamstring
        rawset(a, "ttdBelow", { pct = 30, talent = key })
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(30, below(lib))
        st.talent[key].rank = 0
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(20, below(lib))
        rawset(a, "ttdBelow", nil)
    end)

    it("group members add their class's default line; a tank's does not count", function()
        local H, lib = new(mw.Frost)
        H.Hekili:NewShared():RegisterTtdLines({ ROGUE = 35 })
        H.ctl.groupMembers = 3
        member(H, "party1", "WARRIOR", "DAMAGER")
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(20, below(lib))
        member(H, "party2", "ROGUE", "TANK")
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(20, below(lib))
        H.ctl.roles.party2 = "NONE" -- roles not set: the line counts
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(35, below(lib))
    end)

    it("no execute line in the group: no hint; one that leaves clears it", function()
        local H, lib = new(mw.Frost)
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.is_nil(below(lib))
        H.ctl.groupMembers = 2
        member(H, "party1", "WARRIOR", "DAMAGER")
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(20, below(lib))
        H.ctl.exists.party1, H.ctl.groupMembers = false, 0
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.is_false(below(lib))
    end)

    it("in combat a roster change waits for the combat's end", function()
        local H, lib = new(mw.Frost)
        H.ctl.combat = true
        H.ctl.groupMembers = 2
        member(H, "party1", "WARRIOR", "DAMAGER")
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.is_nil(below(lib))
        H.ctl.combat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(20, below(lib))
    end)

    it("a shipped pack line is readable as registered: the talent's 35 while it has a rank", function()
        local H, lib = new(lw.Demonology)
        local st = H.Hekili.State
        st.talent.decimation.rank = 2
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(35, below(lib))
        st.talent.decimation.rank = 0
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.is_false(below(lib))
    end)

    it("time to die registers no event core already handles (the combat's end)", function()
        local fh = assert(io.open("src/Hekili/Engine/Sim/Targets.lua"))
        local src = fh:read("*a")
        fh:close()
        local at = src:find("local TTD_MAJOR", 1, true)
        local block = src:sub((assert(at)))
        assert.is_nil(block:find('"PLAYER_REGEN_ENABLED"', 1, true))
        assert.is_truthy(block:find('RegisterEvent( "GROUP_ROSTER_UPDATE"', 1, true)) -- core has no handler of it
    end)
end)
