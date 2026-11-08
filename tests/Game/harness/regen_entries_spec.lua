-- tests/Game/harness/regen_entries_spec.lua (border batch 2 Part C, E3): the sim's generated regen entries are the
-- engine's own, built by RegisterResource (Engine/Schema/Spec/Regen.lua) from the meta (`__decay`: the stepped
-- out-of-combat decay, stepped-decay design §3.3) and from the main hand's `taken` (`__taken`: rage from hits on the
-- player, tank design §1.2.5). Both read the reset's stored regen tail (decay_anchor, taken_rate), never the belief.
local headless = require("Game.harness.headless")
local alloc = require("Game.State.helpers.alloc")

describe("the sim's generated regen entries (RegisterResource)", function()
    local H, spec, S, Rage

    before_each(function()
        H = headless.new()
        spec, S, Rage = H.Hekili.Class.specs[0], H.Hekili.State, H.env.Enum.PowerType.Rage
    end)

    local function register(model, meta)
        spec:RegisterResource(Rage, model, nil, meta)
        return spec.resources.rage.state
    end

    local function paying(taken)
        return {
            mainhand = { swing = "mainhand", value = 3, taken = taken },
            offhand = { swing = "offhand", value = 2 },
        }
    end

    it("builds __taken from a main-hand entry's `taken`, none without one", function()
        assert.is_nil(register(paying(nil)).regenModel.__taken)
        local e = register(paying(function() end)).regenModel.__taken
        assert.are.same({ "rage", 1 }, { e.resource, e.interval })
    end)

    it("steps __taken every second from the reset at the stored rate, removed out of combat", function()
        local r = register(paying(function() end))
        local e = r.regenModel.__taken
        S.time, S.now, S.offset = 0, 20, 0
        assert.are.same({ true, 0 }, { e.stop(), e.value() }) -- out of combat: removed, and no rate stored
        S.time, S.now, S.offset = 5, 16, 1.5
        rawset(r, "taken_rate", 0.4) -- the reset's read (GetPowerRegenForPowerType's fifth value)
        assert.are.same({ false, 0.4, 17 }, { e.stop(), e.value(), e.last() })
        assert.are.equal(18, e.last() + e.interval) -- 1.5 s on, the next beat is the reset's +2, not +2.5
        S.offset = 2
        assert.are.equal(18, e.last()) -- a beat at the forecast's start is already in `actual`
    end)

    it(
        "builds __decay from the meta: the talent-scaled quantum on the stored anchor's beats, in combat removed",
        function()
            local rank = 0
            local r = register(
                { regen_aura_a = { aura = "regen_aura_a", interval = 1, value = 1, pausesDecay = true } },
                {
                    decay = function()
                        return 2 * (1 - 0.3 * rank)
                    end,
                    decayInterval = function()
                        return 1
                    end,
                }
            )
            local e = r.regenModel.__decay
            assert.are.same({ "rage", 1, -2 }, { e.resource, e.interval(), e.value() })
            rank = 1
            assert.is_true(math.abs(-1.4 - e.value()) < 1e-9) -- the talent's 30% less
            assert.is_nil(register({}, { decay = 2 }).regenModel.__decay) -- no interval: no stepped entry
            S.time, S.now, S.offset = 0, 4.5, 0
            rawset(S.buff, "regen_aura_a", { up = false, expires = 0 })
            assert.are.same({ false, 3.5 }, { e.stop(), e.last() }) -- no anchor: a quantum at the forecast's start
            S.time = 5
            assert.is_true(e.stop()) -- in combat
            S.time, S.now = 0, 3.5
            rawset(r, "decay_anchor", 3) -- the reset's read (the fourth value)
            assert.are.equal(3, e.last()) -- the belief's beat at or before now; the next at 4
            S.now = 6.2
            assert.are.equal(6, e.last()) -- rolled forward along the beats
            rawset(S.buff, "regen_aura_a", { up = true, expires = 20 })
            assert.are.equal(19, e.last()) -- a pausing aura up in the sim: the first quantum at its expiry, after its tick
            rawset(S.buff, "regen_aura_a", { up = false, expires = 0 })
            S.now, S.offset = 5, 2.5 -- after an advance: actual holds the beats at 4 to 7
            assert.are.equal(7, e.last()) -- the forecast's first beat at 8, none re-applied
            rawset(S.buff, "regen_aura_a", { up = true, expires = 20.5 })
            assert.are.equal(19.5, e.last())
            S.offset = 18.7 -- the sim advanced to 23.7, past the expiry the reset saw: beats at 20.5 to 23.5
            S.buff.regen_aura_a.up = false
            assert.are.equal(23.5, e.last()) -- not the anchor's beats (23): it is paused while the aura is up
            r.regenModel.regen_aura_a.pausesDecay = nil -- unflagged: an aura up in the sim moves no beat
            S.now, S.offset = 5, 2.5
            rawset(S.buff, "regen_aura_a", { up = true, expires = 20 })
            assert.are.equal(7, e.last())
            rawset(S.buff, "regen_aura_a", nil)
        end
    )

    it("allocates nothing when the forecast calls them", function()
        local r = register(paying(function() end), {
            decay = function()
                return 2
            end,
            decayInterval = function()
                return 1
            end,
        })
        local d, k = r.regenModel.__decay, r.regenModel.__taken
        S.time, S.now, S.offset = 0, 20, 0.5
        rawset(r, "decay_anchor", 19)
        assert.are.equal(
            0,
            alloc.bytes(function()
                d.last()
                d.stop()
                d.value()
                k.last()
                k.stop()
                k.value()
            end, 100)
        )
    end)
end)
