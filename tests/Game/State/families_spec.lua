-- tests/Game/State/families_spec.lua: aura families on the Cooldown Manager (owner rule L727). A pack declares
-- `family = "<name>"` on each member aura; a Cooldown Manager entry whose candidates all name one family's members is a
-- family item: its light says some member is up, its silence that none is, and the member is the family's latest
-- application in the belief (our last cast, or a later plain read). Synthetic IDs only (fake_spec's two auras).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

describe("aura families on the Cooldown Manager (L727)", function()
    local VS, I, S, Obs, ctl, api, P, Q
    local M1, M2 = 1, 2 -- aura indices in fs.def: spender_a (fs.SPENDER_A), spender_c (fs.SPENDER_C, rank 2 _R2)
    local A, C = fs.SPENDER_A, fs.SPENDER_C

    local function def(f1, f2, extra)
        local d = fs.def(fs.new(9))
        d.auras[M1].family, d.auras[M2].family = f1, f2
        if extra then
            extra(d)
        end
        return d
    end

    local function start(d, inCombat)
        ctl.now = 1
        d.providers = { presence = "router", viewer = true }
        I.Build(d, 1)
        VS.Start(api)
        P, Q = I.presence, I.PRESENCE.viewer
        ctl.now = 10
        if inCombat ~= false then
            ctl.Fire("PLAYER_REGEN_DISABLED")
            ctl.auras.player.HELPFUL[1] = fake.SECRET -- the walk is secret: only the reduced facts speak
            ctl.Fire("UNIT_AURA", "player")
        end
        I.ObsLog.Clear(I.log)
    end

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        ctl.viewer.sets[2] = { 601, 602 }
        ctl.viewer.infos[601] = { spellID = 9000, linkedSpellIDs = { A, C, fs.SPENDER_C_R2 } } -- every member
        ctl.viewer.infos[602] = { spellID = 9001, linkedSpellIDs = { A, C, 9990 } } -- the members and an untracked ID
    end)

    local function poll(t)
        ctl.now = t
        ctl.Tick(t)
        S.RunPolls(t)
        I.Fold(t, false)
        I.Settle(t)
    end
    -- Our cast's write as Families/Now.lua makes it (the record, then ours); a member cast first takes the other
    -- member down, as the packs' `now` does.
    local function cast(j, t, d)
        local other = j == M1 and M2 or M1
        if I.auras.exp0[1][other] > 0 then
            I.AuraModel(1, other, 0, 0, 0, t, Obs.CastSuccess, false)
        end
        I.AuraModel(1, j, t, t + d, 1, t, Obs.CastSuccess, false)
        I.AuraOurs(1, j)
    end
    local function est(spell, t)
        local r = VS.Aura("player", spell, t)
        return r and r.est
    end
    local function fam(id)
        local m = Q.map[id]
        return m and m < 0 and Q.family[-m] or 0
    end

    describe("the map (out of combat)", function()
        it("an entry naming only one family's members is a family item; one with an untracked ID is not", function()
            start(def("pair", "pair"))
            assert.is_true(fam(601) > 0)
            assert.are.equal(0, fam(602))
            assert.is_true(Q.map[602] < 0) -- still ambiguous
        end)

        it("members of two families, or a member beside a non-member, stay ambiguous", function()
            start(def("pair", "other"))
            assert.is_true(Q.map[601] < 0)
            assert.are.equal(0, fam(601))
            start(def("pair", nil))
            assert.is_true(Q.map[601] < 0)
            assert.are.equal(0, fam(601))
        end)

        it("a member switched off in the Cooldown Manager panel (cdm = false) leaves the entry ambiguous", function()
            start(def("pair", "pair", function(d)
                d.auras[M2].cdm = false
            end))
            assert.is_true(Q.map[601] < 0)
            assert.are.equal(0, fam(601))
        end)
    end)

    describe("presence and identity (in combat)", function()
        local item

        before_each(function()
            item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 601)
            start(def("pair", "pair"))
        end)

        it("lit past the model's expiry re-establishes the last cast member, never the other", function()
            cast(M1, 10, 5)
            ctl.ViewerAuraBySpell("player", A, true, "player")
            for t = 10.5, 14.5, 0.5 do
                poll(t)
                assert.are.equal(15, est(A, t))
            end
            assert.are.equal(I.UP, P.Presence(M1, 1))
            for t = 15, 16.5, 0.5 do
                poll(t)
            end
            assert.is_true((est(A, 16.5) or 0) > 1000) -- held HOLD past the model's expiry: LONG (rule 4, L310)
            assert.is_nil(VS.Aura("player", C, 16.5))
        end)

        it("silent after a light closes the last cast member (consumed or removed unseen)", function()
            cast(M1, 10, 30)
            ctl.ViewerAuraBySpell("player", A, true, "player")
            poll(10.2)
            poll(11) -- lit REFRESH_LAG past our write (D14)
            ctl.ViewerAuraBySpell("player", A, false, "player")
            poll(11.5)
            assert.is_nil(VS.Aura("player", A, 11.5))
            assert.is_nil(VS.Aura("player", C, 11.5))
        end)

        it("a swap inside the family: the new member is never closed, no verdict, no strike", function()
            cast(M1, 10, 30)
            ctl.ViewerAuraBySpell("player", A, true, "player")
            for t = 10.2, 11.8, 0.4 do
                poll(t)
            end
            -- the client swaps before our cast's event folds: a sweep sees the item lit while the belief still holds M1
            ctl.ViewerAuraBySpell("player", A, false, "player")
            ctl.ViewerAuraBySpell("player", C, true, "player")
            poll(11.9)
            assert.are.equal(40, est(A, 11.9))
            cast(M2, 12, 30)
            for t = 12.2, 20, 0.4 do
                poll(t)
                assert.are.equal(42, est(C, t), t)
                assert.is_nil(VS.Aura("player", A, t), t)
            end
            assert.are.equal(I.UP, P.Presence(M2, 1))
            for _, j in ipairs({ M1, M2 }) do
                assert.are.same({ 0, 0 }, { I.auraVerdict.n[j], I.auraVerdict.strikes[j] }, j)
            end
            ctl.ViewerAuraBySpell("player", C, false, "player") -- control: the new member's silence closes it
            poll(20.5)
            assert.is_nil(VS.Aura("player", C, 20.5))
        end)

        it("with no member applied yet the item is counted ambiguous and opens nothing", function()
            ctl.ViewerAuraBySpell("player", A, true, "player")
            for t = 10.5, 13, 0.5 do
                poll(t)
            end
            assert.is_nil(VS.Aura("player", A, 13))
            assert.is_nil(VS.Aura("player", C, 13))
            assert.are.equal(1, Q.ambiguous)
            assert.are.equal(I.UNDECIDED, P.Presence(M1, 1))
        end)

        it("a sweep with a family item allocates nothing", function()
            cast(M1, 10, 30)
            ctl.ViewerAuraBySpell("player", A, true, "player")
            poll(10.5)
            local t = 11
            local bytes = alloc.bytes(function()
                t = t + 0.001
                Q.Sweep(t)
            end, 1000)
            assert.are.equal(0, bytes)
        end)
    end)

    describe("a plain direct read wins (shapeshift forms)", function()
        it(
            "the family item never acts on a member the plain form read owns; once that read is secret, it does",
            function()
                ctl.forms = { A, C }
                ctl.form = 1
                local item = ctl.ViewerItem("BuffIconCooldownViewer", 1, 601)
                start(def("pair", "pair"))
                ctl.Fire("UPDATE_SHAPESHIFT_FORM")
                poll(10.1) -- poll 9: the plain read puts member 1 up, no expiry
                assert.is_true(I.formAura[M1])
                cast(M1, 10.3, 30) -- our cast's write: ours, so a silence after a light could close it
                ctl.ViewerAuraBySpell("player", A, true, "player")
                poll(10.5)
                poll(11.5)
                ctl.ViewerClear(item) -- the item goes dark while the plain read still says member 1
                poll(12)
                poll(13.5)
                assert.are.equal(40.3, est(A, 13.5)) -- the plain read owns the record: the family item closes nothing
                ctl.form = fake.SECRET -- the read turns secret: Forms.lua hands the records back
                ctl.Fire("UPDATE_SHAPESHIFT_FORM")
                poll(14)
                assert.is_nil(I.formAura[M1])
                cast(M2, 14, 30)
                ctl.ViewerAuraBySpell("player", C, true, "player")
                poll(14.2)
                poll(15)
                ctl.ViewerAuraBySpell("player", C, false, "player")
                poll(15.5)
                assert.is_nil(VS.Aura("player", C, 15.5)) -- now the family item's silence closes the last cast member
            end
        )
    end)
end)
