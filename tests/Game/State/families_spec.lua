-- tests/Game/State/families_spec.lua: aura families on the Cooldown Manager (owner rule L727). A pack declares
-- `family = "<name>"` on each member aura; a Cooldown Manager entry whose candidates all name one family's members is a
-- family item: its light says some member is up, its silence that none is, and the member is the one the belief holds
-- up (our last cast, or a later plain read); with none up a light names none. Synthetic IDs only (fake_spec's two auras).
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

        it("lit past the model's expiry: the last cast member ends there, the light opens no member", function()
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
            -- the light names no member once ours is down (another member, cast unseen, lights it too): no LONG
            assert.is_nil(VS.Aura("player", A, 16.5))
            assert.is_nil(VS.Aura("player", C, 16.5))
        end)

        it("a light while the last cast member is down opens no member, before or after our cast folds", function()
            cast(M2, 10, 5)
            ctl.ViewerAuraBySpell("player", C, true, "player")
            for t = 10.2, 14.8, 0.2 do
                poll(t)
            end
            ctl.ViewerAuraBySpell("player", C, false, "player")
            for t = 15, 30, 0.2 do
                poll(t)
            end
            ctl.ViewerAuraBySpell("player", A, true, "player") -- the client lights for M1 a sweep before our cast folds
            poll(30.2)
            assert.is_nil(VS.Aura("player", C, 30.2)) -- the fallen member is not reopened
            assert.is_nil(VS.Aura("player", A, 30.2))
            cast(M1, 30.3, 30)
            for t = 30.4, 32, 0.2 do
                poll(t)
            end
            assert.are.equal(60.3, est(A, 32))
            assert.is_nil(VS.Aura("player", C, 32))
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

        -- (lane C review I1/m4) A close by the Cooldown Manager (rule 1 or the verdict) is healed by a light within
        -- STRIKE_WIN as for a one-aura item (cdm-verdict §2.7): the member re-opens, and after a verdict it strikes.
        it("a rule-1 close, then a light within STRIKE_WIN: the member re-opens as a one-aura item's does", function()
            cast(M1, 10, 30)
            ctl.ViewerAuraBySpell("player", A, true, "player")
            for t = 10.2, 12, 0.2 do
                poll(t)
            end
            ctl.ViewerAuraBySpell("player", A, false, "player") -- dark ~2 s while truly up
            for t = 12.2, 14, 0.2 do
                poll(t)
                assert.is_nil(VS.Aura("player", A, t), t) -- rule 1 closed it at the first NONE
            end
            ctl.ViewerAuraBySpell("player", A, true, "player")
            poll(14.2)
            assert.is_true((est(A, 14.2) or 0) > 14.2) -- re-opened (rule 3), as the one-aura control does
            assert.is_nil(VS.Aura("player", C, 14.2))
            assert.are.same({ 0, 0 }, { I.auraVerdict.n[M1], I.auraVerdict.strikes[M1] }) -- no verdict: no strike
        end)

        it("a rule-1 close, then a light past STRIKE_WIN: no member is named, nothing opens", function()
            cast(M1, 10, 30)
            ctl.ViewerAuraBySpell("player", A, true, "player")
            for t = 10.2, 12, 0.2 do
                poll(t)
            end
            ctl.ViewerAuraBySpell("player", A, false, "player")
            for t = 12.2, 14.6, 0.2 do
                poll(t)
            end
            ctl.ViewerAuraBySpell("player", A, true, "player")
            poll(14.8)
            poll(15)
            assert.is_nil(VS.Aura("player", A, 15))
            assert.is_nil(VS.Aura("player", C, 15))
        end)

        -- The item proven on an earlier application, then our recast while it is dark (the seen rule cannot close
        -- it): the verdict closes it after W.
        local function prove()
            cast(M1, 10, 30)
            ctl.ViewerAuraBySpell("player", A, true, "player")
            poll(10.2)
            poll(11)
            ctl.ViewerAuraBySpell("player", A, false, "player")
            poll(11.2)
            assert.is_true(Q.proven[601])
        end
        local function verdictAfter(c)
            cast(M1, c, 30)
            for t = c + 0.2, c + 1.4, 0.2 do
                poll(t)
            end
            assert.is_nil(VS.Aura("player", A, c + 1.4)) -- the verdict
        end

        it("a verdict, then a light within STRIKE_WIN: re-opened, one strike; two strikes retire the item", function()
            prove()
            verdictAfter(13)
            ctl.ViewerAuraBySpell("player", A, true, "player") -- the late light (> W): no cast of ours since
            poll(14.6)
            assert.is_true((est(A, 14.6) or 0) > 14.6) -- re-opened (BY_CDM)
            poll(14.8) -- (review M2) judged at the next poll
            assert.are.same({ 1, 1, 1 }, { I.auraVerdict.n[M1], I.auraVerdict.strikes[M1], Q.strikes[601] })
            ctl.ViewerAuraBySpell("player", A, false, "player")
            poll(15)
            verdictAfter(20)
            ctl.ViewerAuraBySpell("player", A, true, "player")
            poll(21.6)
            poll(21.8)
            assert.are.same({ 2, 2, 2, false }, {
                I.auraVerdict.n[M1],
                I.auraVerdict.strikes[M1],
                Q.strikes[601],
                Q.proven[601],
            })
            ctl.ViewerAuraBySpell("player", A, false, "player")
            poll(22)
            cast(M1, 30, 30) -- retired: belief-only, the cap of 2 holds
            for t = 30.2, 32, 0.2 do
                poll(t)
                assert.are.equal(60, est(A, t), t)
            end
            assert.are.same({ 2, 2 }, { I.auraVerdict.n[M1], I.auraVerdict.strikes[M1] })
        end)

        it("a verdict, then the light of our cast of another member in the same drain: no re-open, no strike", function()
            prove()
            verdictAfter(13)
            -- the client lights the item for M2; the poll stages before our cast's event folds in this drain
            ctl.ViewerAuraBySpell("player", C, true, "player")
            ctl.now = 14.6
            ctl.Tick(14.6)
            S.RunPolls(14.6)
            cast(M2, 14.5, 30)
            I.Fold(14.6, false)
            I.Settle(14.6)
            for t = 14.8, 16, 0.2 do
                poll(t)
                assert.is_nil(VS.Aura("player", A, t), t)
                assert.are.equal(44.5, est(C, t), t)
            end
            assert.are.same({ 1, 0, 0 }, { I.auraVerdict.n[M1], I.auraVerdict.strikes[M1], Q.strikes[601] })
        end)

        it("a sweep naming a member a close took down allocates nothing", function()
            cast(M1, 10, 30)
            ctl.ViewerAuraBySpell("player", A, true, "player")
            poll(10.2)
            poll(11)
            ctl.ViewerAuraBySpell("player", A, false, "player")
            poll(11.2) -- closed: inside its late window from here
            ctl.ViewerAuraBySpell("player", A, true, "player")
            local t = 11.3
            local bytes = alloc.bytes(function()
                t = t + 0.001
                Q.Sweep(t)
            end, 1000)
            assert.are.equal(0, bytes)
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
                -- the item goes dark while the plain read still says member 1 (A's removal: a hand clear would leave
                -- A applied, and the fake's refresh would show it again at C's removal)
                ctl.ViewerAuraBySpell("player", A, false, "player")
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
