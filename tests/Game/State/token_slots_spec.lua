-- tests/Game/State/token_slots_spec.lua: the target's memory slots keyed by nameplate under Map (tab-targeting plan
-- §4-§5, lane T2m). Under the Map restriction the target's GUID is secret; the slot is keyed by the plate index whose
-- UnitIsUnit("target", "nameplateK") answers true. Scenarios also run with plain GUIDs: the answers must match.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("token-keyed target memory (lane T2m)", function()
    local VS, I, S, Obs, ctl, api, def, ti
    local REND = 2 -- the target debuff (fs.SPENDER_C)
    local world -- "token": secret GUIDs, plates answer; "guid": plain GUIDs (the twin)

    local function fold(t)
        ctl.now = t
        ctl.Tick(t)
        S.RunPolls(t)
        I.Fold(t, false)
        I.Settle(t)
    end

    -- Targets mob k (its plate is nameplateK in the token world; Creature-K in the twin); nil: no target. The drain
    -- follows at t + 0.05 (a later frame).
    local function tab(k, t)
        ctl.now = t
        if world == "token" then
            ctl.guid.target = k and fake.SECRET or nil
            ctl.unitIs.target = k and ("nameplate" .. k) or nil
        else
            ctl.guid.target = k and ("Creature-" .. k) or nil
        end
        ctl.Fire("PLAYER_TARGET_CHANGED")
        fold(t + 0.05)
    end
    local function plate(event, k, t)
        ctl.now = t
        ctl.Fire(event, "nameplate" .. k)
    end
    -- Our cast of the debuff on the current target, as Families/Now.lua writes it: the record, then ours.
    local function castX(t, d, stacks)
        I.AuraModel(2, REND, t, t + d, stacks or 1, t, Obs.CastSuccess, true)
        I.AuraOurs(2, REND)
    end
    local function est(t)
        local r = VS.Aura("target", fs.SPENDER_C, t)
        return r and r.est
    end
    local function near(want, got, label)
        assert.is_true(got ~= nil and math.abs(got - want) < 1e-9, (label or "") .. " " .. tostring(got))
    end
    local function keys()
        local n = 0
        for s = 1, I.TARGET_CAP do
            if type(I.targetKeys[s]) == "number" then
                n = n + 1
            end
        end
        return n
    end

    -- w: the world; plates: how many plates are up (default 3); cdm: the Cooldown Manager tracks the debuff.
    local function start(w, plates, cdm)
        world = w
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        ctl.guid.target = nil
        ctl.now = 1
        def = fs.def(fs.new(9))
        if cdm then
            ctl.viewer.sets[2] = { 502 }
            ctl.viewer.infos[502] = { spellID = fs.SPENDER_C }
            ti = ctl.ViewerItem("BuffIconCooldownViewer", 1, 502)
            def.providers = { presence = "router", viewer = true }
        end
        I.Build(def, 1)
        VS.Start(api)
        for k = 1, plates or 3 do
            plate("NAME_PLATE_UNIT_ADDED", k, 1)
        end
        fold(1)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        ctl.auras.player.HELPFUL[1] = fake.SECRET -- both walks secret in combat
        ctl.auras.target.HARMFUL[1] = fake.SECRET
        ctl.Fire("UNIT_AURA", "player")
        ctl.Fire("UNIT_AURA", "target")
        fold(2)
    end

    local WORLDS = { "token", "guid" }

    it("remembers each mob's debuff across tabs; the plain-GUID twin gives the same answers (task 3)", function()
        local got = {}
        for _, w in ipairs(WORLDS) do
            start(w)
            local out = {}
            tab(1, 10)
            castX(10.1, 15, 3) -- on A: expires 25.1, 3 stacks
            tab(2, 13)
            out[#out + 1] = est(13.1) or "down"
            castX(14, 15) -- on B: 29
            tab(1, 17)
            out[#out + 1] = est(17.1) or "down"
            out[#out + 1] = select(2, VS.Aura("target", fs.SPENDER_C, 17.1)) or 0
            local gen = VS.AuraGen("target")
            for t = 17.5, 19, 0.5 do -- no cast, no edge: no change (flicker)
                fold(t)
            end
            out[#out + 1] = VS.AuraGen("target") - gen
            tab(2, 19.5)
            out[#out + 1] = est(19.6) or "down"
            if w == "token" then
                assert.is_true(I.curSlot > 0, "a plate keyed a memory slot")
            end
            got[w] = out
        end
        assert.are.same({ "down", 25.1, 3, 0, 29 }, got.token)
        assert.are.same(got.guid, got.token)
    end)

    it("a plate's REMOVED or ADDED forgets the memory keyed by it (task 4)", function()
        start("token")
        tab(1, 10)
        castX(10.1, 15)
        tab(2, 11)
        plate("NAME_PLATE_UNIT_REMOVED", 1, 11.5)
        plate("NAME_PLATE_UNIT_ADDED", 1, 11.6) -- another mob took plate 1
        fold(11.7)
        tab(1, 12)
        assert.is_nil(est(12.1), "REMOVED then ADDED")
        castX(12.2, 15)
        tab(2, 13)
        plate("NAME_PLATE_UNIT_ADDED", 1, 13.5) -- an ADDED with no REMOVED: a new mob all the same
        fold(13.6)
        tab(1, 14)
        assert.is_nil(est(14.1), "ADDED alone")
        tab(2, 15)
        plate("NAME_PLATE_UNIT_REMOVED", 1, 15.5)
        tab(1, 16) -- UnitIsUnit still names nameplate1, but no plate 1 is up: no plate answers
        assert.are.equal(0, I.curSlot)
    end)

    it("a plate lost while targeted keeps the live record; its memory goes at the tab away (task 5)", function()
        for _, dies in ipairs({ false, true }) do
            start("token")
            local gone = {}
            I.On(Obs.TargetGone, function(o)
                gone[#gone + 1] = o.a
            end)
            tab(1, 10)
            castX(10.1, 15)
            local slot = I.curSlot
            assert.is_true(slot > 0)
            ctl.dead.target = dies or nil
            plate("NAME_PLATE_UNIT_REMOVED", 1, 11)
            fold(11.1)
            near(25.1, est(11.1), "the live record stands")
            if not dies then
                assert.is_true(VS.Health("target", 11.1).est > 0)
            end
            assert.are.same({}, gone) -- no TargetGone for the current slot: it would read as a death
            plate("NAME_PLATE_UNIT_ADDED", 1, 12)
            fold(12.1)
            near(25.1, est(12.1), "still up")
            ctl.dead.target = nil
            tab(2, 13)
            assert.are.same({ slot }, gone) -- forgotten at the tab away
            tab(1, 14)
            assert.is_nil(est(14.1), "the orphan was forgotten")
        end
    end)
end)
