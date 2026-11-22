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
local fake = require("Game.State.helpers.fake_api")

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

local function install(env, lib)
    local stub = rawget(env, "LibStub")
    stub.libs[MAJOR], stub.minors[MAJOR] = lib, 2
end

-- `early`: the library is there before login (as in game), else it is installed after; `character`: not the pack's own.
local function new(C, early, character)
    local lib = double()
    local H = headless.new({
        character = character or C.character(),
        pack = C.PACK,
        beforeLogin = early and function(core)
            install(getfenv(core.GetTTD), lib)
        end or nil,
    })
    assert.are.same({}, H.loadErrors)
    if not early then
        install(H.env, lib)
    end
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

    it("the highest line of the group, whoever comes first", function()
        local H, lib = new(mw.Frost)
        H.Hekili:NewShared():RegisterTtdLines({ ROGUE = 35 })
        H.ctl.groupMembers = 3
        member(H, "party1", "ROGUE", "DAMAGER")
        member(H, "party2", "WARRIOR", "DAMAGER")
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(35, below(lib))
    end)

    it("a raid is read by its raid tokens, the last one too", function()
        local H, lib = new(mw.Frost)
        H.ctl.raid, H.ctl.groupMembers = true, 40
        member(H, "raid40", "WARRIOR", "DAMAGER")
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(20, below(lib))
    end)

    it("in a raid the player's own token adds no class default over the pack's line", function()
        local H, lib = new(ww)
        H.Hekili:NewShared():RegisterTtdLines({ WARRIOR = 50 })
        H.ctl.raid, H.ctl.groupMembers = true, 1
        member(H, "raid1", "WARRIOR", "DAMAGER")
        H.ctl.unitIs.raid1 = "player"
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(20, below(lib))
    end)

    it("an ability not known gives no line", function()
        local c = ww.character()
        local execute, known = {}, {}
        for _, id in ipairs(ww.IDS.execute) do
            execute[id] = true
        end
        for _, id in ipairs(c.known) do
            if not execute[id] then
                known[#known + 1] = id
            end
        end
        c.known = known
        local H, lib = new(ww, false, c)
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.is_nil(below(lib))
    end)

    it("a secret role is unknown, never compared: the line counts", function()
        local H, lib = new(mw.Frost)
        H.ctl.groupMembers = 2
        member(H, "party1", "WARRIOR", fake.SECRET)
        assert.are.equal("nil", type(H.ns.Facade.UnitGroupRolesAssigned("party1"))) -- a secret cannot be printed
        H.Fire("GROUP_ROSTER_UPDATE")
        assert.are.equal(20, below(lib))
    end)

    it("a library found late is sent the line at the first track", function()
        local H, lib = new(ww)
        assert.is_nil(below(lib))
        H.Hekili:GetTTD("target")
        assert.are.equal(20, below(lib))
    end)

    it("login sends the line: no roster event, no query", function()
        local _, lib = new(ww, true)
        assert.are.equal(20, below(lib))
    end)

    it("a talent change sends it again at the spec's activation", function()
        local decimation = lw.Demonology.character()
        local id = 440870 -- the talent's spell
        local talents = {}
        for spell, rank in pairs(decimation.talents) do
            talents[spell] = rank
        end
        talents[id] = 2
        decimation.talents = talents
        local H, lib = new(lw.Demonology, true, decimation)
        assert.are.equal(35, below(lib))
        for n, spell in pairs(H.ctl.traits.defs) do
            if spell == id then
                H.ctl.traits.nodes[n].activeRank = 0
            end
        end
        H.Hekili:SpecializationChanged()
        assert.is_false(below(lib))
    end)

    it("shared content loads on a core without RegisterTtdLines", function()
        local f = assert(loadfile("src/Hekili_Shared/Shared/TimeToDie.lua"))
        local older = {}
        function older.NewShared()
            return {}
        end
        setfenv(f, { Hekili = older })
        assert.has_no.errors(f)
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
