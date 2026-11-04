-- tests/Forever/wowsims_hunter_spec.lua (wowsims packs plan, Task 11): the Hunter wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ab = require("Game.harness.ab")
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.hunter_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("HUNTER"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- The abilities the Melee Weave casts or recommends that the worlds' characters lack (usable on cost); Strider Kick
-- comes with the MM and SV builds' talent (the log header's), never the BM build's.
local EXTRA = {
    kit = {
        "aspect_of_the_hawk",
        "immolation_trap",
        "mongoose_bite",
        "multi_shot",
        "raptor_strike",
        "serpent_sting",
        "arcane_shot",
        "wing_clip",
    },
}
-- The replay's: Mongoose Bite's window in wowsims's fights is Expose Prey (1310726, 10 s, the MM and SV builds' talent
-- proc); the client answers the bite usable while it is up (the kit reads that plain usability, not the aura).
local REPLAY_EXTRA = {
    kit = EXTRA.kit,
    requires = {
        mongoose_bite = function(_, e)
            return e.auras[1310726] ~= nil, "no window"
        end,
    },
}
-- Expose Prey in the truth only: the kit opens Mongoose Bite from its usability read, never from the player aura walk
local REPLAY = { hidden = { [1310726] = true } }

-- recipe, world content, pack, the replay floor (the first clean run's, never lowered), LIVE60: the pack's own worst
-- idle at 60, rounded up to 0.1 s (P8). It is our secret-mana lower bound, not a wowsims pooling condition: BM and MM
-- (their worlds at 11 yd, the weave's range) believe Arcane Shot's mana short after Rapid Fire's 100 (BM less long: its
-- Efficiency; MM longer since Improved Arcane Shot 3/5 casts it every 5.1 s); SV, whose strikes Resourcefulness makes
-- cheap, never idles at 60.
-- MM 11.8 -> 12.8 (Task 5): the world's regen is now wowsims's log (15.88 a second outside the rule, 0 while casting
-- but for Resourcefulness) instead of 21 / 3, so Arcane Shot's 190 mana is reached about a second later; with the old
-- world regen and the new class seeds the idle is still 11.8 (measured), so the cause is the world's truth;
-- owner-approved 2026-10-30.
-- Re-floored on central fix 14 (percent-of-base costs from base mana): BM 0.963 -> 1.000, MM 0.881 -> 0.929, SV
-- 0.878 -> 0.976.
-- ON flicker ceiling (re-pin Task 9, the replay with Movement ON at d3393): the measured flicker per minute rounded up
-- to the next 0.1, pack_gate.FLICKER's convention (0 stays 0). The oracle + FLICKER_K bar does not apply: a replay has
-- no oracle run (loop.replay, its oracle flicker reads 0). Measured BM 0.00, MM 0.67, SV 0.33 (one 180 s fight: a flip
-- is 0.33/min).
local PACKS = {
    { "hunter_beast_mastery", "BeastMastery", "Beast Mastery (wowsims.com)", 1.00, 5.4, 0 },
    { "hunter_marksmanship", "Marksmanship", "Marksmanship (wowsims.com)", 0.92, 12.8, 0.7 },
    { "hunter_survival", "Survival", "Survival (wowsims.com)", 0.97, 0, 0.4 },
}

describe("the Hunter wowsims.com packs #slow #wowsims", function()
    -- one block per pack: the replay floor (measured on the first clean run, never lowered), the pack's own worst
    -- idle at 60 (LIVE60, measured), and the brackets
    for _, p in ipairs(PACKS) do
        local spec, world, pack, FLOOR, LIVE60, FLICKER = p[1], W[p[2]], p[3], p[4], p[5], p[6]
        it(pack .. " follows wowsims's casts", function()
            local r, line = ws.gate(pack, content(spec, world, pack, 60, REPLAY_EXTRA), spec, FLOOR, REPLAY)
            ab.check(r.flicker <= FLICKER + 1e-9, pack, "ON flicker ceiling: " .. line)
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, world, pack, level, EXTRA), math.max(6, LIVE60))
            end)
        end
    end
end)

-- Task 9 (S2's unknown-bracket pin, the real client path): a replay world at 20 yd (beyond melee, inside the shots'
-- band) gives the belief a plain range bracket at the pull, so the bracket's unknown "both sides" answer is gone and
-- an on-next-swing melee strike reads out of range there. Here, not in tests/Game/harness/replay_spec.lua: the boundary
-- rule keeps class content out of the harness core.
describe("the Hunter replay at 20 yd #slow #wowsims", function()
    it("knows the target's range at the pull and reads the melee strike out of range", function()
        local loop = require("Game.harness.loop")
        local replay = require("Game.harness.replay")
        local spec, pack = "hunter_beast_mastery", "Beast Mastery (wowsims.com)"
        local C = ws.logged(content(spec, W.BeastMastery, pack, 60, REPLAY_EXTRA), spec)
        local L = loop.new(C)
        local o = ws.replayOptions(C, spec, REPLAY)
        o.distance = 20
        local R = replay.new(ws.log(spec), L.oracle, o)
        local H, seen = L.us, nil
        loop.replay(L, R, {
            duration = 2,
            on = function(_, _, t)
                if not seen and t >= R.pull and t < R.pull + 0.5 then -- the log's first move is 0.51 s in
                    seen = {
                        H.ns.VirtualState.TargetRange().basis ~= "unknown",
                        H.Hekili.State.action.raptor_strike.in_range,
                    }
                end
            end,
        })
        assert.are.same({ true, false }, seen)
        assert.are.same({}, H.errors)
    end)
end)
