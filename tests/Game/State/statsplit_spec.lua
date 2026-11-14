-- tests/Game/State/statsplit_spec.lua: the stat split (owner rule L971; accuracy-085 item 4). A pack declares what a
-- player aura does to the spell haste (`spellHaste`, a multiplier) or to UnitStat (`stats` flat points by index, a
-- number or a function of the talent ranks; `statsPct` a multiplier by index); the belief splits the out-of-combat
-- read into a base and the parts of the declared auras that were up at that read, and in a fight composes the value
-- from its own aura records: (base + flat up) x pct up, haste base x the multipliers up. Out of combat the read stands.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

describe("the stat split (L971)", function()
    local VS, I, Obs, api, ctl

    local function near(want, got)
        assert.is_true(math.abs(want - got) < 1e-9, ("%.6f vs %.6f"):format(got, want))
    end
    local function drain(t) -- the fold, then the settle (its sweep takes an aura down by time)
        I.Fold(t)
        I.Settle(t)
    end
    local function at(t) -- the client's clock
        ctl.now = t
    end
    local function spirit(t)
        return (select(2, VS.Stat("UnitStat", 5, t)))
    end
    local function build(a1, a2)
        local def = fs.def(fs.new(9))
        a1.key, a1.id = "spender_a", fs.SPENDER_A
        def.auras[1] = a1
        if a2 then
            a2.key, a2.id, a2.copy = "spender_c", fs.SPENDER_C, { fs.SPENDER_C_R2 }
            def.auras[2] = a2
        end
        I.Build(def, 90)
    end

    before_each(function()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        Obs = VS.Obs
        api = fake.new()
        ctl = api.ctl
    end)

    it("composes the spell haste from the read's base and the `spellHaste` auras up (a cooldown used in combat)", function()
        build({ duration = 15, spellHaste = 1.1 })
        at(95)
        ctl.spellHaste = 5 -- the out-of-combat read, the aura down
        VS.Start(api)
        drain(95)
        at(99)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        drain(99)
        near(5, VS.SpellHaste(100).est)
        near(1.5 / 1.05, I.GcdLen(1, 100))
        I.AuraModel(1, 1, 101, 116, 1, 101, 0) -- up at 101 in combat: 1.05 x 1.1
        near(15.5, VS.SpellHaste(101).est)
        near(1.5 / 1.155, I.GcdLen(1, 101))
        near(1 / 1.155, I.Haste(101)) -- a `now`'s `haste`
        near(5, VS.SpellHaste(116.5).est) -- ran out at 116
        assert.are.equal(
            0,
            alloc.bytes(function()
                VS.SpellHaste(105)
            end, 2000)
        )
        at(130)
        ctl.spellHaste = 6 -- out of combat the read stands
        ctl.Fire("PLAYER_REGEN_ENABLED")
        drain(130)
        I.AuraModel(1, 1, 131, 146, 1, 131, 0)
        near(6, VS.SpellHaste(132).est)
    end)

    it("divides out a `spellHaste` aura the read held, so its fall in combat removes exactly its part", function()
        build({ duration = 15, spellHaste = 1.1 })
        I.AuraModel(1, 1, 90, 105, 1, 90, 0)
        at(95)
        ctl.spellHaste = 15.5 -- the read with the aura up: base 1.155 / 1.1 = 1.05
        VS.Start(api)
        drain(95)
        at(99)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        drain(99)
        near(15.5, VS.SpellHaste(100).est)
        near(5, VS.SpellHaste(106).est)
        I.inCombat = true -- a plain read in combat stands too: the base follows it, the aura down at its time
        I.Sources.Direct(Obs.Haste, 107, 0, 8, 2)
        drain(107)
        near(8, VS.SpellHaste(108).est)
        I.AuraModel(1, 1, 109, 124, 1, 109, 0)
        near((1.08 * 1.1 - 1) * 100, VS.SpellHaste(110).est)
    end)

    it("composes UnitStat from the read's base, the flat parts and the percent parts up in combat", function()
        build({ duration = 120, stats = {
            [5] = function()
                return 40 -- a function: the belief's `now` context (talent ranks), evaluated at the pull
            end,
        } }, { duration = 15, statsPct = { [5] = 1.15 } })
        api.UnitStat = function(_, i)
            return i, i == 5 and 300 or i * 10, 0, 0
        end
        I.AuraModel(1, 1, 90, 110, 1, 90, 0) -- up at the read: 300 = 260 + 40
        at(95)
        VS.Start(api)
        drain(95)
        near(300, spirit(96)) -- out of combat: the read
        at(99)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        drain(99)
        near(300, spirit(100))
        near(260, spirit(111)) -- its fall by time takes exactly its 40
        I.AuraModel(1, 2, 112, 127, 1, 112, 0)
        near(260 * 1.15, spirit(113)) -- a percent part gained in combat
        assert.are.same({ 5, 260 * 1.15, 0, 0, 0, 0, 0 }, { VS.Stat("UnitStat", 5, 113) })
        near(40, (select(2, VS.Stat("UnitStat", 4, 113)))) -- an index with no part: the read
        assert.are.equal(
            0,
            alloc.bytes(function()
                VS.Stat("UnitStat", 5, 113)
            end, 2000)
        )
        at(130)
        api.UnitStat = function(_, i)
            return i, i == 5 and 280 or i * 10, 0, 0
        end
        ctl.Fire("PLAYER_REGEN_ENABLED") -- a fresh plain read: it stands
        drain(130)
        near(280, spirit(131))
    end)

    it("keeps a part fallen after the read and before the pull out of the base (one fall deep)", function()
        build({ duration = 120, stats = { [5] = 40 } })
        api.UnitStat = function(_, i)
            return i, i == 5 and 300 or 0, 0, 0
        end
        I.AuraModel(1, 1, 90, 97, 1, 90, 0)
        at(95)
        VS.Start(api)
        drain(97.5) -- it ran out at 97 with no new read
        at(99)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        drain(99)
        near(260, spirit(100))
        I.AuraModel(1, 1, 101, 221, 1, 101, 0) -- a recast in combat adds it back
        near(300, spirit(102))
    end)

    it("adds no part an aura gained after the read had (an aura the pull put up)", function()
        build({ duration = 120, statsPct = { [5] = 1.15 } })
        api.UnitStat = function(_, i)
            return i, i == 5 and 200 or 0, 0, 0
        end
        at(95)
        VS.Start(api)
        drain(95)
        I.AuraModel(1, 1, 99, 219, 1, 99, 0)
        at(99)
        ctl.Fire("PLAYER_REGEN_DISABLED")
        drain(99)
        near(230, spirit(100))
    end)
end)
