-- tests/Forever/avoid_tie_spec.lua (L1917, L1918; fable-tr1-decision.md D2, D4): a missed Curse of the Elements on the
-- Shadow Brand build, alone and beside Corruption's success, in the engine (`debuff.x.up` after a reset) and in the
-- belief (VS.Aura). From the seed-15 tracer's headless cases (central-needs tr1-seed15-scratch/lone_spec.lua).
local headless = require("Game.harness.headless")
local w = require("Forever.helpers.warlock_world")

local CURSE, CORR, RECK = 1311680, 25311, 11717 -- Curse of the Elements r4, Corruption, Curse of Recklessness r4
local CURSE_AURA, CORR_AURA, RECK_AURA = 440892, 172, 704

local function boot()
    local C = w.ShadowBrand
    local H = headless.new({ character = C.character(), pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    local ctl = H.ctl
    ctl.inRange.target, ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    ctl.combat = true
    H.Fire("PLAYER_REGEN_DISABLED")
    local t = ctl.now + 1
    assert.is_true(headless.cycle(H, t))
    return H, t
end

-- events: { dt, kind, a, b } after t0, then two cycles and a reset. Returns a table of what each case asserts.
local function run(events)
    local H, t0 = boot()
    local S, VS, ctl, I = H.Hekili.State, H.ns.VirtualState, H.ctl, H.ns.VirtualStateInternal
    local d0 = I.Tickets.divergent
    local misses, avoided = {}, {}
    local miss = I.Log.Miss
    I.Log.Miss = function(...)
        misses[#misses + 1] = select(7, ...) -- the row's spell ID
        return miss(...)
    end
    local stage = I.Sources.Stage
    I.Sources.Stage = function(kind, t, a, b, c, ...)
        if kind == VS.Obs.Avoided then
            avoided[#avoided + 1] = { I.ab.key[a], c }
        end
        return stage(kind, t, a, b, c, ...)
    end
    t0 = t0 + 5
    for _, e in ipairs(events) do
        ctl.now = t0 + e[1]
        if e[2] == "start" then
            H.Fire("UNIT_SPELLCAST_START", "player", e[3], e[4])
        elseif e[2] == "success" then
            H.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", e[3], e[4])
            H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", e[3], e[4])
        elseif e[2] == "row" then
            H.Fire("UNIT_COMBAT", "target", e[3], "", e[3] == "WOUND" and 50 or 0, e[4])
        elseif e[2] == "cycle" then
            assert.is_true(headless.cycle(H, ctl.now))
        end
    end
    local tq = ctl.now + 0.2
    assert.is_true(headless.cycle(H, tq))
    assert.is_true(headless.cycle(H, tq + 0.5))
    S.reset("Primary", true)
    assert.are.same({}, H.errors)
    local te = tq + 0.5
    return {
        curse = { S.debuff.curse_of_the_elements.up, VS.Aura("target", CURSE_AURA, te) ~= nil },
        corr = { S.debuff.corruption.up, VS.Aura("target", CORR_AURA, te) ~= nil },
        reck = { S.debuff.curse_of_recklessness.up, VS.Aura("target", RECK_AURA, te) ~= nil },
        divergent = I.Tickets.divergent - d0,
        misses = misses,
        avoided = avoided,
        undoFull = I.undoFull,
    }
end

describe("a missed curse (L1918: the belief's undo reaches it)", function()
    it("Z: a lone Corruption MISS goes down in both (as warlock_spec)", function()
        local r = run({ { -1.6, "start", "Cast-1", CORR }, { 0, "success", "Cast-1", CORR }, { 0, "row", "MISS", 1 } })
        assert.are.same({ false, false }, r.corr)
        assert.are.same({ 0, { CORR }, 0 }, { r.divergent, r.misses, r.undoFull })
    end)

    it("A: a lone curse MISS in its own frame goes down in both", function()
        local r = run({ { 0, "success", "Cast-1", CURSE }, { 0, "row", "MISS", 1 } })
        assert.are.same({ false, false }, r.curse)
        assert.are.same({ 0, { CURSE }, 0 }, { r.divergent, r.misses, r.undoFull })
    end)

    it("A2: a lone curse MISS 0.15 s after its success goes down in both", function()
        local r = run({ { 0, "success", "Cast-1", CURSE }, { 0.15, "row", "MISS", 1 } })
        assert.are.same({ false, false }, r.curse)
        assert.are.same({ 0, { CURSE }, 0 }, { r.divergent, r.misses, r.undoFull })
    end)

    it("A3: a curse MISS with Corruption's success 1.5 s before: the curse down, Corruption up", function()
        local r = run({
            { -1.6, "start", "Cast-1", CORR },
            { -1.5, "success", "Cast-1", CORR },
            { -1.4, "cycle" },
            { 0, "success", "Cast-2", CURSE },
            { 0, "row", "MISS", 1 },
        })
        assert.are.same({ false, false }, r.curse)
        assert.are.same({ true, true }, r.corr)
        assert.are.same({ 0, { CURSE }, 0 }, { r.divergent, r.misses, r.undoFull })
    end)

    it("a curse cast over another running curse, then missed: the old curse is back, the new one down", function()
        local r = run({
            { -3, "success", "Cast-1", RECK }, -- landed: no row
            { -2.9, "cycle" },
            { 0, "success", "Cast-2", CURSE },
            { 0, "row", "MISS", 1 },
        })
        assert.are.same({ false, false }, r.curse)
        assert.is_true(r.reck[2])
        assert.are.same({ 0, { CURSE }, 0 }, { r.divergent, r.misses, r.undoFull })
    end)
end)
