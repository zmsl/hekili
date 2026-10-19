-- tests/Forever/spec_choice_spec.lua (per-spec plan, docs/superpowers/plans/2026-10-19-forever-specs.md): the active
-- spec on Forever, stock Hekili headless: the stored choice for the character, else the dominant talent tree (stored
-- once), else the first supported spec; a respec only hints. Review focus 1 and 2 (no talents; the choice across a
-- /reload and a respec, no loop).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local ARMS, FURY, PROT = 100011, 100012, 100013
local CHAR = "Player-Realm" -- the fake client's UnitName("player") .. "-" .. GetRealmName()
local FURY_TALENTS = { [23881] = 1, [12319] = 5 } -- Bloodthirst, Flurry

-- The harness's C_Traits answer for a talent build (tests/Game/harness/headless.lua's login shape).
local function traits(talents)
    local tr = { config = 1, trees = { 1 }, nodeIDs = {}, nodes = {}, defs = {} }
    for spell, rank in pairs(talents) do
        local n = #tr.nodeIDs + 1
        tr.nodeIDs[n], tr.nodes[n], tr.defs[n] = n, { entryIDs = { n }, activeRank = rank }, spell
    end
    return tr
end

local function boot(o)
    o = o or {}
    local c = ww.character()
    c.talents = o.talents or c.talents
    c.level = o.level or c.level
    local H = headless.new({ character = c, saved = o.saved, pack = o.pack })
    assert.are.same({}, H.loadErrors)
    return H
end

-- The event frame's real OnUpdate (Engine/Sim/Events.lua; the harness's cycle does not run it), called while a spec
-- change is pending: each call runs one pass; at most 2 passes.
local function settle(H)
    local frame
    for _, f in ipairs(H.frames) do
        local u = f.__scripts.OnUpdate
        if u and debug.getinfo(u, "S").source:find("Engine/Sim/Events.lua", 1, true) then
            frame = f
        end
    end
    assert.is_truthy(frame, "no event frame with an OnUpdate")
    for _ = 1, 2 do
        if not H.Hekili.PendingSpecializationChange then
            return
        end
        frame.__scripts.OnUpdate(frame, 0.016)
    end
    assert.is_false(H.Hekili.PendingSpecializationChange, "the spec change did not settle")
end

describe("the active spec (headless Warrior)", function()
    it("picks the dominant tree on first login and stores it", function()
        local H = boot()
        settle(H)
        assert.are.equal(ARMS, H.Hekili.State.spec.id)
        assert.are.equal(1491, H.Hekili.State.spec.clientID)
        assert.are.equal("arms", H.Hekili.DB.profile.specChoice[CHAR])
        assert.are.equal("arms", H.Hekili.Engine.Output.status.specKey)
        assert.is_truthy(H.Hekili:GenerateProfile():find("\nspec: arms (", 1, true))
        local f = boot({ talents = FURY_TALENTS })
        settle(f)
        assert.are.equal(FURY, f.Hekili.State.spec.id)
        assert.are.equal("fury", f.Hekili.DB.profile.specChoice[CHAR])
    end)

    it("binds each built-in priority to its spec and makes it that spec's package", function()
        local H = boot()
        local p = H.Hekili.DB.profile
        assert.are.same({ ARMS, FURY, PROT }, { p.packs.Arms.spec, p.packs.Fury.spec, p.packs.Protection.spec })
        assert.are.same(
            { "Arms", "Fury", "Protection" },
            { p.specs[ARMS].package, p.specs[FURY].package, p.specs[PROT].package }
        )
    end)

    it(
        "gives a character with no talents (level 5) the first spec, stores nothing, then follows its first points",
        function()
            local H = boot({ talents = {}, level = 5 })
            settle(H)
            assert.are.equal(ARMS, H.Hekili.State.spec.id)
            assert.are.equal("default", H.Hekili.State.spec.source)
            assert.is_nil(H.Hekili.DB.profile.specChoice[CHAR])
            assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
            assert.are.same({}, H.errors)
            H.ctl.traits = traits(FURY_TALENTS)
            H.Fire("PLAYER_TALENT_UPDATE")
            assert.is_true(H.Hekili.PendingSpecializationChange)
            settle(H)
            assert.are.equal(FURY, H.Hekili.State.spec.id)
            assert.are.equal("fury", H.Hekili.DB.profile.specChoice[CHAR])
        end
    )

    it(
        "keeps a stored choice across a /reload and a respec, hints the dominant spec, and runs no extra pass",
        function()
            local H1 = boot()
            settle(H1)
            assert.are.equal("fury", H1.Hekili:SetSpecChoice("fu").key) -- a prefix
            settle(H1)
            assert.are.equal(FURY, H1.Hekili.State.spec.id)
            local H = boot({ saved = H1.env.HekiliDB }) -- Arms talents, Fury stored
            settle(H)
            assert.are.equal(FURY, H.Hekili.State.spec.id)
            assert.are.equal("stored", H.Hekili.State.spec.source)
            assert.are.equal("arms", H.Hekili:GetSpecHint().key)
            local passes, change = 0, H.Hekili.SpecializationChanged
            H.Hekili.SpecializationChanged = function(...)
                passes = passes + 1
                return change(...)
            end
            H.ctl.traits = traits({ [12294] = 1, [12296] = 1, [12834] = 3 }) -- a respec deeper into Arms
            H.Fire("PLAYER_TALENT_UPDATE")
            assert.is_false(H.Hekili.PendingSpecializationChange)
            settle(H)
            assert.are.equal(0, passes)
            assert.are.equal(FURY, H.Hekili.State.spec.id)
            assert.are.equal("arms", H.Hekili:GetSpecHint().key)
            assert.is_nil(H.Hekili:SetSpecChoice("nope"))
            assert.is_nil(H.Hekili:SetSpecChoice("")) -- every key is a prefix of "": ambiguous
        end
    )

    it("ends an OnUpdate pass whose early pick was on stale ranks on the settled spec (the extra pass runs)", function()
        local H = boot({ talents = {}, level = 5 })
        settle(H)
        assert.are.equal(ARMS, H.Hekili.State.spec.id)
        -- new points the talent walk has not seen yet: the pass picks on the old ranks (no points: Arms), its own walk
        -- then sees Fury, and SettleSpecChoice asks for one more pass
        H.ctl.traits = traits(FURY_TALENTS)
        H.Hekili.PendingSpecializationChange = true
        settle(H)
        assert.are.equal("fury", H.Hekili.DB.profile.specChoice[CHAR])
        assert.are.equal(FURY, H.Hekili.State.spec.id)
    end)

    it("selects the spec of the priority a harness instance asks for", function()
        local H = boot({ pack = "Protection" })
        assert.are.equal(PROT, H.Hekili.State.spec.id)
        assert.are.equal("Protection", H.Hekili.DB.profile.specs[PROT].package)
    end)
end)

describe("the spec options and /hekili spec (headless Warrior)", function()
    it("shows one node per spec with its own preferences, and the dropdown and the command set the choice", function()
        local H = boot()
        settle(H)
        H.Hekili:EmbedSpecOptions()
        local nodes = H.Hekili.Options.plugins.specializations
        assert.are.same({ 132292, 132347, 134952 }, { nodes.arms.icon, nodes.fury.icon, nodes.protection.icon })
        local prefs = function(key)
            return nodes[key].args.core.plugins.settings
        end
        assert.is_not_nil(prefs("arms").ww_min_enemies)
        assert.is_nil(prefs("arms").hs_threshold)
        assert.is_not_nil(prefs("fury").hs_threshold)
        assert.is_nil(prefs("fury").prot_cleave_rage)
        assert.is_not_nil(prefs("protection").prot_cleave_rage)
        assert.is_not_nil(prefs("protection").debuff_demoshout_enabled) -- shared by all three
        local pick = nodes.arms.args.core.args.activeSpec
        assert.are.same({ arms = "Arms", fury = "Fury", protection = "Protection" }, pick.values())
        assert.are.equal("arms", pick.get())
        pick.set(nil, "fury")
        settle(H)
        assert.are.equal(FURY, H.Hekili.State.spec.id)
        assert.are.equal("fury", H.Hekili.DB.profile.specChoice[CHAR])
        assert.is_true(nodes.arms.args.core.args.specHint.hidden() == false) -- Arms talents, Fury chosen
        H.Hekili:CmdLine("spec") -- the list, then an unmatched name (the list again): no error, no change
        H.Hekili:CmdLine("spec zzz")
        assert.are.equal("fury", H.Hekili.DB.profile.specChoice[CHAR])
        H.Hekili:CmdLine("spec prot")
        settle(H)
        assert.are.equal(PROT, H.Hekili.State.spec.id)
    end)

    it("orders the Priorities list by spec", function()
        local H = boot()
        settle(H)
        H.Hekili:EmbedPackOptions() -- builds the Priorities tree into Hekili.Options.args.packs
        local packages = H.Hekili.Options.args.packs.plugins.packages
        local order = {}
        for _, name in ipairs({ "Arms", "Fury", "Protection" }) do
            order[#order + 1] = packages[name].order
        end
        assert.is_true(order[1] < order[2] and order[2] < order[3])
    end)
end)
