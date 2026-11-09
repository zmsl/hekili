-- tests/Game/State/cdm_edge_spec.lua: the Cooldown Manager's edge (owner rulings L345-L351). Per slot, the conservative
-- rule: an EDGE is a light after the same slot was seen lit, then dark, by sweeps under continuous monitoring (viewer
-- visible, same cooldownID, same unit, no reset between); any other first light is a SEED (unknown age). The router
-- classifies each reduced UNKNOWN/DOWN -> UP change (fact.edge: the edge's t, 0 a seed) and counts them per fight. The
-- belief's harness-only switch I.cdmEdge ("edge" arm) anchors a cast-opened application's expiry at the edge (edge +
-- the record's own duration); the "cast" arm (today) keeps the cast's start. Both arms keep the diagnostics.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("CDM edges: seed or edge per thing (L348-L351, conservative rule)", function()
    local VS, I, ctl, api, d, R, t, items

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        ctl.viewer.sets[2] = { 501, 502, 503 }
        ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
        ctl.viewer.infos[502] = { spellID = fs.SPENDER_C }
        ctl.viewer.infos[503] = { spellID = fs.SPENDER_A } -- a second entry for aura 1 (a re-point target)
        items = {
            player = ctl.ViewerItem("BuffIconCooldownViewer", 1, 501),
            target = ctl.ViewerItem("BuffIconCooldownViewer", 2, 502),
        }
        items.player.unit, items.target.unit = "player", "target"
        local ns = load.module()
        VS = ns.VirtualState
        I = ns.VirtualStateInternal
        d = fs.def(fs.new(9))
        d.providers = { presence = "router", viewer = true }
        I.Build(d, 1)
        VS.Start(api)
        R = I.presence
        t = 1
    end)

    -- The steps: L light, D dark, F refresh (the client's clear-then-set in one call), S sweep a frame later, s sweep in
    -- the same frame, T target change (to the other mob), H hide the viewer, V show it, R the viewer's data-loaded event
    -- (a rebuild out of combat), O the leaf off then on (Hekili.cdmOff, a rebuild), P re-point to another cooldownID of
    -- the same aura.
    local mob = 1
    local STEP = {
        L = function(it)
            ctl.ViewerAura(it, it.unit)
        end,
        D = function(it)
            ctl.ViewerClear(it)
        end,
        F = function(it)
            ctl.ViewerAura(it, it.unit)
        end,
        S = function()
            t = t + 0.5
            ctl.now = t
            R.Sweep(t)
        end,
        s = function()
            ctl.now = t
            R.Sweep(t)
        end,
        T = function()
            mob = 3 - mob
            ctl.guid.target = "Creature-" .. mob
            ctl.now = t
            ctl.Fire("PLAYER_TARGET_CHANGED")
        end,
        H = function()
            ctl.viewer.shown.BuffIconCooldownViewer = false
        end,
        V = function()
            ctl.viewer.shown.BuffIconCooldownViewer = nil
        end,
        R = function()
            ctl.Fire("COOLDOWN_VIEWER_DATA_LOADED")
            R = I.presence
        end,
        O = function()
            local off = fs.def(fs.new(9))
            off.providers = { presence = "router", viewer = false }
            I.Build(off, t)
            I.Build(d, t)
            R = I.presence
        end,
        P = function(it)
            ctl.ViewerRepoint(it, it.cooldownID == 501 and 503 or 501)
        end,
    }

    -- name, unit, steps, then the last UP's class (true: an edge at the last sweep's t) and the edges counted since the
    -- last rebuild (seeds and edges are per fight; a rebuild starts them over)
    local ROWS = {
        { "dark -> lit, each seen by a sweep: an edge", "player", "LSDSLS", true, 1 },
        { "dark for several sweeps, then lit: an edge", "player", "LSDSSSLS", true, 1 },
        { "the first read after the build is lit: a seed", "player", "LS", false, 0 },
        { "a first DARK read is no baseline (conservative rule): then lit, a seed", "player", "SSLS", false, 0 },
        { "dark and lit again inside one poll gap: no change, no edge", "player", "LSDLS", false, 0 },
        { "a refresh of a lit item: no change, no edge", "player", "LSFSS", false, 0 },
        {
            "the viewer hidden while dark, shown, then lit: a seed (monitoring broke)",
            "player",
            "LSDSHSVSLS",
            false,
            0,
        },
        { "lit while the viewer is hidden (unknown), then shown: a seed", "player", "HLSVS", false, 0 },
        { "the viewer's data-loaded rebuild between dark and lit: a seed", "player", "LSDSRLS", false, 0 },
        { "the leaf off and on between dark and lit: a seed", "player", "LSDSOLS", false, 0 },
        { "a re-point (same aura) between dark and lit: a seed", "player", "LSDSPLS", false, 0 },
        { "target: dark -> lit on one mob: an edge", "target", "LSDSLS", true, 1 },
        { "target: lit, swap away and back, lit again: a seed (no edge)", "target", "LSTDSTLS", false, 0 },
        { "target: dark on A, the swap in the flip's own frame, lit on B: a seed", "target", "LSDSTLsS", false, 0 },
        { "target: a new mob's first light is a seed; dark -> lit there is an edge", "target", "TSLSDSLS", true, 1 },
    }

    for _, row in ipairs(ROWS) do
        local name, unit, steps, edge, nEdges = row[1], row[2], row[3], row[4], row[5]
        it(name, function()
            mob = 1
            local it = items[unit]
            local u = unit == "player" and 1 or 2
            local j = u -- aura 1 on the player (spender_a), aura 2 on the target (spender_c)
            local k = (u - 1) * I.AURA_UNIT + j
            for c in steps:gmatch(".") do
                STEP[c](it)
            end
            assert.are.equal(I.UP, R.Presence(j, u), steps)
            assert.are.equal(edge and t or 0, R.fact.edge[k], steps)
            assert.are.equal(nEdges, R.edgeN[k], steps)
            assert.is_true(edge or R.seedN[k] >= 1, steps) -- a last UP that is no edge was counted a seed
        end)
    end

    it("two items for one aura: one stays lit while the other flips, the thing never went dark: no edge", function()
        local second = ctl.ViewerItem("BuffBarCooldownViewer", 1, 503)
        second.unit = "player"
        I.Build(d, 1)
        R = I.presence
        local it = items.player
        ctl.ViewerAura(it, "player")
        ctl.ViewerAura(second, "player")
        STEP.S()
        ctl.ViewerClear(it)
        STEP.S()
        ctl.ViewerAura(it, "player")
        STEP.S()
        assert.are.equal(0, R.fact.edge[1])
        assert.are.equal(0, R.edgeN[1])
        assert.are.equal(1, R.seedN[1])
    end)

    it("seeds and edges are counted per fight", function()
        local it = items.player
        for c in ("LSDSLS"):gmatch(".") do
            STEP[c](it)
        end
        assert.are.same({ 1, 1 }, { R.seedN[1], R.edgeN[1] })
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.are.same({ 0, 0 }, { R.seedN[1], R.edgeN[1] })
    end)
end)

-- The belief with the edge (Sources/Auras.lua), both arms. "cast" is today's rule (the cast's start stands, L347);
-- "edge" anchors a cast-opened application at its edge: expiry = edge + the record's own duration (L346/L348).
describe("CDM edges in the belief: the anchor (edge arm) and the diagnostics (both arms)", function()
    local VS, I, S, Obs, ctl, api, P, pi, ti
    local SHOUT, REND = 1, 2

    local function start(def)
        ctl.now = 1
        def.providers = { presence = "router", viewer = true }
        I.Build(def, 1)
        VS.Start(api)
        P = I.presence
        ctl.now = 10
        ctl.Fire("PLAYER_TARGET_CHANGED") -- mob A (Creature-1)
        I.Fold(10, false)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.auras.player.HELPFUL[1] = fake.SECRET -- both walks secret: only the reduced facts speak
        ctl.auras.target.HARMFUL[1] = fake.SECRET
        ctl.Fire("UNIT_AURA", "player")
        ctl.Fire("UNIT_AURA", "target")
        I.ObsLog.Clear(I.log)
    end

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        ctl.viewer.sets[2] = { 501, 502 }
        ctl.viewer.infos[501] = { spellID = fs.SPENDER_A }
        ctl.viewer.infos[502] = { spellID = fs.SPENDER_C }
        pi = ctl.ViewerItem("BuffIconCooldownViewer", 1, 501)
        ti = ctl.ViewerItem("BuffIconCooldownViewer", 2, 502)
    end)

    local function poll(t)
        ctl.now = t
        ctl.Tick(t)
        S.RunPolls(t)
        I.Fold(t, false)
        I.Settle(t)
    end
    local function cast(u, j, t, dur) -- our cast's write, as Families/Now.lua makes it
        I.AuraModel(u, j, t, t + dur, 1, t, Obs.CastSuccess, u == 2)
        I.AuraOurs(u, j)
    end
    local function est(unit, spell, t)
        local r = VS.Aura(unit, spell, t)
        return r and r.est
    end
    local function near(a, b)
        return a ~= nil and math.abs(a - b) < 1e-9
    end
    -- An earlier application seen lit then dark (a CDM-opened record its NONE closes): the slot's dark baseline.
    local function prime(item, unit)
        ctl.ViewerAura(item, unit)
        poll(12)
        ctl.ViewerClear(item)
        poll(12.2)
    end

    -- name, then a function(arm) of the scenario returning the believed expiry it checks, and the expected expiry per arm
    local ROWS = {
        {
            "our cast, its light 0.3 s later (an edge): the edge's start",
            function()
                prime(ti, "target")
                cast(2, REND, 20, 15)
                poll(20)
                ctl.ViewerAura(ti, "target")
                poll(20.3)
                poll(20.5)
                return est("target", fs.SPENDER_C, 20.5)
            end,
            35,
            35.3,
        },
        {
            "F3 shape, the cast logged before the drain that sees the edge: anchored at the next poll",
            function()
                prime(ti, "target")
                ctl.ViewerAura(ti, "target")
                ctl.now = 20.2
                ctl.Tick(20.2)
                S.RunPolls(20.2) -- the record is down: the CDM UP stages an open
                cast(2, REND, 20, 15) -- the cast's write, logged first, folds first
                I.Fold(20.2, false)
                I.Settle(20.2)
                poll(20.4)
                poll(20.6)
                return est("target", fs.SPENDER_C, 20.6)
            end,
            35,
            35.2,
        },
        {
            "F3 reverse order, the cast event late: the light opens, the late cast's write is anchored back",
            function()
                prime(ti, "target")
                ctl.ViewerAura(ti, "target")
                poll(20.2) -- the edge opens the record (no model yet): 35.2
                cast(2, REND, 20.4, 15) -- the late cast event (its handler reads the open as its own application)
                poll(20.6)
                poll(20.8)
                return est("target", fs.SPENDER_C, 20.8)
            end,
            35.4,
            35.2,
        },
        {
            "a seed (the first light ever): the cast's start in both arms",
            function()
                cast(2, REND, 20, 15)
                poll(20)
                ctl.ViewerAura(ti, "target")
                poll(20.3)
                poll(20.5)
                return est("target", fs.SPENDER_C, 20.5)
            end,
            35,
            35,
        },
        {
            "a refresh of the lit item 5 s on (no edge): the refresh's cast start stands",
            function()
                prime(ti, "target")
                cast(2, REND, 20, 15)
                ctl.ViewerAura(ti, "target")
                poll(20.3)
                poll(20.5)
                cast(2, REND, 25, 15)
                poll(25.2)
                poll(25.4)
                return est("target", fs.SPENDER_C, 25.4)
            end,
            40,
            40,
        },
        {
            "a proc with no cast of ours (an edge): opened from the edge in both arms",
            function()
                prime(ti, "target")
                ctl.ViewerAura(ti, "target")
                poll(20.3)
                poll(20.5)
                return est("target", fs.SPENDER_C, 20.5)
            end,
            35.3,
            35.3,
        },
        {
            "an icd aura: no anchor (its fold would take a later expiry as a new application)",
            function()
                local def = fs.def(fs.new(9))
                def.auras[SHOUT] = { key = "spender_a", id = fs.SPENDER_A, duration = 10, icd = 30 }
                start(def)
                prime(pi, "player")
                cast(1, SHOUT, 20, 10)
                poll(20)
                ctl.ViewerAura(pi, "player")
                poll(20.3)
                poll(20.5)
                return est("player", fs.SPENDER_A, 20.5)
            end,
            30,
            30,
        },
        {
            "a function duration: the record's own duration from the edge (no pack call)",
            function()
                local def = fs.def(fs.new(9))
                def.auras[REND] = {
                    key = "spender_c",
                    id = fs.SPENDER_C,
                    duration = function()
                        return 18
                    end,
                }
                start(def)
                prime(ti, "target")
                cast(2, REND, 20, 18)
                poll(20)
                ctl.ViewerAura(ti, "target")
                poll(20.3)
                poll(20.5)
                return est("target", fs.SPENDER_C, 20.5)
            end,
            38,
            38.3,
        },
        {
            "swap away and back mid-application: the remembered record, no new anchor",
            function()
                prime(ti, "target")
                cast(2, REND, 20, 15)
                poll(20)
                ctl.ViewerAura(ti, "target")
                poll(20.3)
                poll(20.5)
                ctl.now = 22
                ctl.guid.target = "Creature-2"
                ctl.Fire("PLAYER_TARGET_CHANGED")
                ctl.ViewerClear(ti)
                poll(22.1)
                poll(22.5)
                ctl.now = 24
                ctl.guid.target = "Creature-1"
                ctl.Fire("PLAYER_TARGET_CHANGED")
                ctl.ViewerAura(ti, "target") -- A's debuff lit again: a seed
                poll(24.1)
                poll(24.5)
                assert.are.equal(0, P.fact.edge[I.AURA_UNIT + REND])
                return est("target", fs.SPENDER_C, 24.5)
            end,
            35,
            35.3,
        },
    }

    for _, row in ipairs(ROWS) do
        for _, arm in ipairs({ "cast", "edge" }) do
            it(arm .. " arm: " .. row[1], function()
                start(fs.def(fs.new(9)))
                I.cdmEdge = arm == "edge"
                local got = row[2]()
                local want = arm == "cast" and row[3] or row[4]
                assert.is_true(near(got, want), ("%s: %s, want %s"):format(arm, tostring(got), tostring(want)))
            end)
        end
    end

    it("edge arm: a CDM down before the anchored expiry still closes our application (rule 1)", function()
        start(fs.def(fs.new(9)))
        I.cdmEdge = true
        prime(ti, "target")
        cast(2, REND, 20, 15)
        poll(20)
        ctl.ViewerAura(ti, "target")
        poll(20.3)
        poll(20.5)
        assert.is_true(near(est("target", fs.SPENDER_C, 20.5), 35.3))
        ctl.ViewerClear(ti) -- dispelled at 30
        poll(30)
        poll(30.2)
        assert.is_nil(VS.Aura("target", fs.SPENDER_C, 30.2))
    end)

    it("swap onto a half-expired debuff of ours the model never saw: a seed, the upper bound, age unknown", function()
        start(fs.def(fs.new(9)))
        ctl.now = 30
        ctl.guid.target = "Creature-2"
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.ViewerAura(ti, "target") -- mob B carries ours with 7 s left (applied 22, unseen)
        poll(30.1)
        poll(30.3)
        assert.is_true(near(est("target", fs.SPENDER_C, 30.3), 45.1)) -- the registered 15 s from the read
        local snap = VS.Snapshot()
        assert.is_truthy(snap:find("presence-edge spender_c unit=target seeds=1 edges=0 age=unknown", 1, true), snap)
    end)

    it("the snapshot: seeds, edges, edge minus cast and one observed cycle against the model, both arms", function()
        for _, arm in ipairs({ "cast", "edge" }) do
            start(fs.def(fs.new(9)))
            I.cdmEdge = arm == "edge"
            prime(ti, "target")
            cast(2, REND, 20, 15)
            poll(20)
            ctl.ViewerAura(ti, "target")
            poll(20.3)
            poll(20.5)
            ctl.ViewerClear(ti) -- the item goes dark at 34.0: observed 13.7 s against the modelled 15
            poll(34)
            local snap = VS.Snapshot()
            assert.is_truthy(
                snap:find(
                    "presence-edge spender_c unit=target seeds=1 edges=1 age=known anchored="
                        .. (arm == "edge" and 1 or 0)
                        .. " edgeMinusCast n=1 mean=0.300 last=0.300 cycles=1 observed=13.70 modeled=15.00",
                    1,
                    true
                ),
                arm .. "\n" .. snap
            )
            assert.is_truthy(snap:find("presence-edge mode=" .. arm, 1, true), snap)
            for line in snap:gmatch("[^\n]+") do
                assert.is_true(#line < 255, line)
            end
        end
    end)

    it("allocates nothing over 1000 polls of lights, darks, casts and anchors (edge arm)", function()
        local alloc = require("Game.State.helpers.alloc")
        start(fs.def(fs.new(9)))
        I.cdmEdge = true
        prime(ti, "target")
        local t = 20
        assert.are.equal(
            0,
            alloc.bytes(function(i)
                t = t + 0.1
                local on = i % 50 < 30 -- lit 3 s, dark 2 s: an edge every 5 s
                ti.auraInstanceID, ti.auraDataUnit = on and fake.SECRET or nil, on and "target" or nil
                if i % 50 == 49 then
                    I.AuraModel(2, REND, t, t + 15, 1, t, Obs.CastSuccess, true)
                    I.AuraOurs(2, REND)
                end
                S.RunPolls(t)
                I.Fold(t, false)
                I.Settle(t)
            end, 1000)
        )
    end)
end)
