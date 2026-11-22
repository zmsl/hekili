-- tests/Forever/channel_cut_spec.lua (L1748, owner: "if wowsims cuts channels, we should too"): each wowsims.com pack
-- line that carries wowsims's interruptIf (translator rule 24) compiles to the engine's interrupt_if and reads, through
-- the real engine, while its channel runs: Affliction's Wrack at two ticks with Corruption down, Shadow's Mind Flay at
-- its third tick (MF3: its own end), Evocation's 99% mana.
local headless = require("Game.harness.headless")

-- `C` (a world content) booted on its pack, its channel `key` (spell `id`, `length` s) started at the boot's now and
-- succeeded; returns at(t): the engine's CheckChannel and the line's interrupt_if, `t` s into the channel.
local function channel(C, key, id, length)
    local H = headless.new({ character = C.character(), pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    local st = H.Hekili.State
    local cut = H.Hekili.Scripts.Channels[C.PACK][key].interrupt_if -- compiled from the pack
    assert.are.equal("function", type(cut))
    local t0 = H.ctl.now
    H.ctl.channel = { t0 * 1000, (t0 + length) * 1000, spell = id } -- UnitChannelInfo
    H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
    return function(t)
        H.ctl.now = t0 + t
        st.reset("Primary", true)
        st.system.packName = C.PACK -- the display update's own (Core.lua)
        local a, b = H.Hekili:CheckChannel(nil, 0), cut()
        assert.are.same({}, H.errors)
        return a, b
    end
end

describe("a wowsims.com channel line's interrupt_if through the engine", function()
    it("cuts Wrack at its second tick with Corruption down, not at its first", function()
        local at = channel(require("Forever.helpers.warlock_world").Affliction, "wrack", 1316697, 6)
        assert.are.same({ false, false }, { at(1) }) -- one tick
        assert.are.same({ true, true }, { at(2) }) -- two ticks
    end)

    it("reads Mind Flay's third tick only (its own end)", function()
        local at = channel(require("Forever.helpers.priest_world").Shadow, "mind_flay", 15407, 3)
        assert.are.same({ false, false }, { at(2) })
        assert.is_true(select(2, at(2.995)))
    end)

    it("reads Evocation's 99% mana", function()
        local at = channel(require("Forever.helpers.mage_world").Frost, "evocation", 12051, 8)
        local _, cut = at(1)
        assert.are.equal("boolean", type(cut))
    end)
end)

-- L1753: a channel whose start the engine never saw (a /reload mid-channel: UnitChannelInfo answers, no success fired)
-- is read at the reset from `buff.casting`, its ticks queued, no error.
describe("a channel already running when the engine first looks (a /reload mid-channel)", function()
    it("queues its ticks with no error", function()
        local C = require("Forever.helpers.warlock_world").Affliction
        local H = headless.new({ character = C.character(), pack = C.PACK })
        assert.are.same({}, H.loadErrors)
        local st = H.Hekili.State
        local t0 = H.ctl.now
        H.ctl.channel = { (t0 - 0.5) * 1000, (t0 + 5.5) * 1000, spell = 1316697 } -- Wrack, 0.5 s in, no success
        st.reset("Primary", true)
        assert.are.same({}, H.errors)
        local ticks = 0
        for _, e in ipairs(st.queue) do
            ticks = ticks + (e.type == "CHANNEL_TICK" and 1 or 0)
        end
        assert.are.equal(5, ticks) -- 1 to 5 s in; the one at 6 s is the finish's
    end)
end)

-- The driver's generic clip (loop.lua): a fight driven by the oracle alone, our channels read from the world's truth.
local loop = require("Game.harness.loop")

-- `C` driven by its oracle for `duration` s (a mob that never dies); `on(run, H, t)` each tick. Returns the run and the
-- oracle.
local function fight(C, duration, on)
    local L = loop.new(C)
    local run = loop.run(L, 1, {
        duration = duration,
        mobHealth = 1e9,
        on = function(r, _, t)
            on(r, L.oracle, t)
        end,
    }, { { H = L.oracle, plain = true } })
    assert.are.equal(0, run.errors)
    return run, L.oracle
end

-- The key of our channel in progress in `run`, read through `H`'s abilities (nil: none).
local function channelKey(run, H)
    local ch = run.us.channel
    local a = ch and H.Hekili.Class.abilities[ch.spell]
    return a and a.key
end

-- Our channels of ability `key` in the run's truth: { start, ends, stop, next (the key of our next cast after it) }.
local function channels(run, H, key)
    local out, cur = {}, nil
    local abilities = H.Hekili.Class.abilities
    for _, ev in ipairs(run.W.truth) do
        local a = ev.src == run.us and type(ev.spell) == "number" and abilities[ev.spell]
        if a and (ev.kind == "cast" or ev.kind == "castStart") and cur and cur.stop and not cur.next then
            cur.next = a.key
        end
        if a and a.key == key and ev.kind == "cast" and ev.chanEnds then
            cur = { start = ev.t, ends = ev.chanEnds }
            out[#out + 1] = cur
        elseif a and a.key == key and ev.kind == "channelStop" and cur then
            cur.stop = ev.t
        end
    end
    return out
end

-- The first of `list` stopped before its end, not by the run's own end (W.endCasts at `run.t`); nil: none.
local function firstCut(run, list)
    for _, c in ipairs(list) do
        if c.stop and c.stop < c.ends - 1e-6 and c.stop < run.t - 1e-6 then
            return c
        end
    end
end

describe("the loop's driver cuts our channel when the engine moves off it", function()
    it("Affliction: cuts Wrack at its second tick once Corruption is down, then casts Corruption", function()
        local C = require("Forever.helpers.warlock_world").Affliction
        local dropped
        local run, H = fight(C, 40, function(r, oracle)
            local v, id = r.us.target, oracle.Hekili.Class.auras.corruption.id
            if not dropped and channelKey(r, oracle) == "wrack" and v.auras[id] then -- Corruption off mid-Wrack, once
                dropped = true
                v.dots.corruption, v.auras[id] = nil, nil
                r.W.emit({ kind = "aura", dst = v, aura = id, stacks = 0, expires = 0, duration = 0 })
            end
        end)
        assert.is_true(dropped, "no Wrack over Corruption")
        local cut = firstCut(run, channels(run, H, "wrack"))
        assert.is_truthy(cut, "no Wrack cut")
        local at = cut.stop - cut.start
        assert.is_true(at >= 2 - 1e-6 and at < 2.25, tostring(at)) -- its second tick landed: cut at the first poll on
        assert.are.equal("corruption", cut.next)
    end)

    it("Shadow: names Mind Flay to the engine and runs it to its own end", function()
        local C = require("Forever.helpers.priest_world").Shadow
        local seen, named, prev = 0, 0, nil
        local run, H = fight(C, 30, function(r, oracle)
            -- from the tick after its press (the instance reads the press's events at the next poll)
            if channelKey(r, oracle) == "mind_flay" and r.us.channel == prev then
                seen = seen + 1
                oracle.Hekili.State.reset("Primary", true) -- the Update's walk leaves its prediction ahead of now
                named = named + (oracle.Hekili.State.buff.casting.v1 == prev.spell and 1 or 0)
            end
            prev = r.us.channel
        end)
        local flays = channels(run, H, "mind_flay")
        assert.is_true(#flays > 0 and seen > 0, "no Mind Flay")
        assert.are.equal(seen, named) -- buff.casting.v1, the spell CheckChannel reads
        assert.is_nil(firstCut(run, flays))
    end)

    it("Arcane: cuts Evocation at 99% mana, its buff gone with the channel", function()
        local C = require("Forever.helpers.mage_world").Arcane
        local topped
        local run, H = fight(C, 120, function(r, oracle)
            -- the pool at 97% once Evocation runs: 99% comes within its 8 s
            if not topped and channelKey(r, oracle) == "evocation" then
                topped = true
                r.W.emit({ kind = "gain", src = r.us, pt = 0, rage = 0.97 * r.us.powerMax - r.W.res(r.us, 0) })
            end
        end)
        assert.is_true(topped, "no Evocation")
        local cut = firstCut(run, channels(run, H, "evocation"))
        assert.is_truthy(cut, "no Evocation cut")
        assert.is_truthy(cut.next)
        local off
        for _, ev in ipairs(run.W.truth) do -- the buff ends with the channel
            if ev.kind == "aura" and ev.dst == run.us and ev.aura == 12051 and ev.stacks == 0 and not off then
                off = ev.t > cut.start and ev.t
            end
        end
        assert.are.equal(cut.stop, off)
    end)
end)
