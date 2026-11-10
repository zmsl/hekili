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

-- recipe, world content, pack, the replay floor, the live limit per bracket, the ON flicker ceiling, the live world
-- (default: the replay's). History (old pin): LIVE60, the pack's own worst
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
-- Re-pin e2842f0a78 (Task 19, after R51; fresh floors, spec §7: the old floors are not comparable): replay BM 1.00 ->
-- 0.92 (0.929, 65 of 70), MM 0.92 -> 0.96 (0.966, 84 of 87), SV 0.97 -> 0.98 (0.989, 89 of 90). Named causes (recipe
-- headers): wowsims's HHA sequence index stalls on queued hawks (BM 3, an oracle quirk); Serpent Sting applied at the
-- cast, not the landing, with EARLY_EXIT's 0.2 s (BM 2, MM 2: central, no belief landing hook); a mana refill the belief
-- cannot see (MM 1, R50 class A); Serpent Sting priced 250 where wowsims charges 224.9 (SV 1, source not found).
-- ON flicker: BM 0, MM 0; SV 0.4 -> 2.4 (2.33 measured: one-tick bounces at the weave's position changes since R51
-- placed the move arms where the weave is called; that is the R51 part. 2.33 was measured before and after R61, so the
-- remainder is untraced (L115); PROPOSED-hunters-4, owner FYI).
-- Live limits per bracket (R22a: 6 s unless a traced R41 cause). L40 and L60: mana dry (3-18 of 5000), Arcane Shot
-- waiting on its cost, nothing useful to cast (R41, owner FYI): BM 7.8 / 12.2, MM 7.6 / 15.4, SV 7.6 / 14.0. BM L10 13.4
-- -> 4.6 with the recipe's leveling Arcane Shot (wowsims's non-hawk line, below Summon Hawk's 25). Survival's live bars
-- run at 11 yd with a ranged weapon (R63, W.SurvivalRanged): at melee the shots sit inside their 8-35 band and Raptor
-- Strike is off the GCD, so the GCD-idle metric read 116.8 s at L10; its loop and replay worlds stay melee.
local PACKS = {
    {
        "hunter_beast_mastery",
        "BeastMastery",
        "Beast Mastery (wowsims.com)",
        0.95,
        { [10] = 6, [40] = 7.8, [60] = 12.2 },
        -- ON flicker 0 -> 1.0 (CN8 D2, 1.00 measured, the same with steady icons off): the not-ready flag keeps the
        -- modelled end, so Multi-Shot (n147) and Blood Fury (n631) lead for the tick before the log casts them; under the
        -- old probe their last 0.5 s read 0.50 and never led. A replay has no press exclusion (the log presses)
        -- 0.7 floors (e5a9cd2a2d, steady icons on): 1.0 -> 3.4 (3.33 measured = 10 flips in the 180 s fight, the same with
        -- the v0.6.2 melee-range fix merged). Traced per tick (ticks 37, 127, 146, 169, 227, 249, 374, 729, 769, 791): the
        -- first icon sits on the weave filler (wing_clip, immolation_trap) and bounces for ONE tick to the ability the log
        -- casts within the next 1-2 ticks (summon_hawk x5, multi_shot x3, immolation_trap/wing_clip x2), then back until the
        -- log's press lands: the same lead-before-the-log-casts mechanism as the CN8 note above (a replay has no press
        -- exclusion); the new weave's strike/filler lines make it more often than the old weave's
        3.4,
    },
    {
        "hunter_marksmanship",
        "Marksmanship",
        "Marksmanship (wowsims.com)",
        0.98,
        { [10] = 6, [40] = 7.6, [60] = 15.4 },
        -- 0 -> 1.0 (1.00 measured = 3 flips; same with the v0.6.2 range fix): traced per tick (131, 429, 469): one-tick
        -- bounce of the filler (wing_clip, immolation_trap) to arcane_shot / strider_kick, which the log casts 1-2 ticks
        -- later: the replay's no-press-exclusion lead (BM's note)
        1.0,
    },
    {
        "hunter_survival",
        "Survival",
        "Survival (wowsims.com)",
        -- 0.98 -> 0.94 (0.946 of 92 decisions on-GCD, measured at the 0.7 floors step): LOWERED with a named cause. 4 of the
        -- 5 misses are Serpent Sting: the belief starts its debuff at the cast, about 0.33 s before it lands (central belief
        -- work, no landing hook; not worked around); the 5th is the strike ordering (strider_kick -> multi_shot), the walk
        -- the replay cannot forecast (omitted weave waits, CN19). Ledger L160.
        0.94,
        { [10] = 6, [40] = 7.6, [60] = 14.0 },
        -- 2.4 -> 0.7 (0.67 measured): R51's weave position bounces (above) are gone with the new weave
        0.7,
        "SurvivalRanged",
    },
}

describe("the Hunter wowsims.com packs #slow #wowsims", function()
    -- one block per pack: the replay floor, the ON flicker ceiling, and the live limit per bracket
    for _, p in ipairs(PACKS) do
        local spec, world, pack, FLOOR, LIVE, FLICKER = p[1], W[p[2]], p[3], p[4], p[5], p[6]
        local liveWorld = W[p[7] or p[2]]
        it(pack .. " follows wowsims's casts", function()
            local r, line = ws.gate(pack, content(spec, world, pack, 60, REPLAY_EXTRA), spec, FLOOR, REPLAY)
            ab.check(r.flicker <= FLICKER + 1e-9, pack, "ON flicker ceiling: " .. line)
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, liveWorld, pack, level, EXTRA), LIVE[level])
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
