-- tests/Forever/wowsims_hunter_spec.lua (wowsims packs plan, Task 11): the Hunter wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ab = require("Game.harness.ab")
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.hunter_world")

-- the learn levels without the book ranks (W.BOOK: wowsims's character is trainer-taught; no level teaches them)
local LEARN = ws.learn("HUNTER")
for id in pairs(W.BOOK) do
    LEARN[id] = math.huge
end

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = LEARN,
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
-- Re-floored (0.8.5 accuracy-timing item 1, controller-approved 2026-11-14): MM L40 7.6 -> 9.4, SV L60 14.0 -> 15.4,
-- SV Melee L40 10.0 -> 10.2. Cause: the R41 mana-dry regen wait from a lower pool. Serpent Sting now lands after its
-- travel time (W.distance / 40, belief and world), which moves its recasts and so the one 120 s fight's mana timeline:
-- the worst streak dries out at 12.1 (was 14.5), 1.8 (14.7) and 1.8 (4.8) mana and waits for Arcane Shot's cost.
-- Live L40 at the re-pin e5a9cd2a2d -> e4ef929e54 (TRACED: a probe over ws.live's idle test, the worst streak of the
-- first fight, with the spend by key; every row below names its numbers): the R41 mana-dry wait, from a pool the 11%
-- shots drain faster. Arcane Shot and Summon Hawk now cost 11% of base mana at every rank, and the world prices it off
-- the level-60 base (1720: 189 at L40, where the old rank cost was 105 for Arcane Shot); no by-level base mana source
-- exists (deferral: a leveling-bracket world pass). The waits themselves are on the next cost (Aimed Shot, Serpent
-- Sting, Immolation Trap, Hunter's Mark), not on Arcane Shot.
local PACKS = {
    -- (the Beast Mastery and Marksmanship weave rows: retired with their packs, L1154)
    {
        "hunter_survival",
        "Survival",
        "Survival (wowsims.com)",
        -- 0.98 -> 0.94 (0.946 of 92 decisions on-GCD, measured at the 0.7 floors step): LOWERED with a named cause. 4 of the
        -- 5 misses are Serpent Sting: the belief starts its debuff at the cast, about 0.33 s before it lands (central belief
        -- work, no landing hook; not worked around); the 5th is the strike ordering (strider_kick -> multi_shot), the walk
        -- the replay cannot forecast (omitted weave waits, CN19). Ledger L160.
        -- 0.94 -> 0.93 (0.935 of 92 measured; flicker-085 P1, L755 / ruling L960: a mana pool with no tick seen pads
        -- nothing, so the waits run less late; loop Survival wait error +.19 -> +.13 s, est - truth unchanged): one more
        -- miss, wowsims casts Mongoose Bite where ours shows Strider Kick (mana) at a near-tie with Mongoose Bite's
        -- cooldown.
        -- 0.93 -> 0.96 (0.967 of 92 measured on integ/0.8.5-w2, the merged tree): the Serpent Sting debuff now starts at
        -- its landing (startsAtLanding, L1103) and flicker-085 and the timing merges are in (L1037); 3 misses remain.
        0.97, -- 0.96 -> 0.97 (0.977 of 86; re-pin e4ef929e54 -> ab0f00e4fc: set to the measurement on the new log)
        -- live L40 7.6 -> 10.0, L60 14.0 -> 15.4 (Lane R2, controller-accepted): as Marksmanship's (above); at L60
        -- the OOM wait runs to a 190-mana shot with the aura down
        -- live L40 10.0 -> 13.8, the re-pin's L40 cause (above, traced): Arcane Shot 12 x 189
        -- and Multi-Shot 9 x 239 are 4419 of the fight's 5414 mana; the streak (t 106.4-120.0) runs the pool 3.3 -> 165.3
        -- waiting on Serpent Sting 115, then Hunter's Mark 60.
        { [10] = 6, [40] = 13.8, [60] = 15.4 },
        -- 2.4 -> 0.7 (0.67 measured): R51's weave position bounces (above) are gone with the new weave
        -- 0.7 -> 1.1 (1.00 measured, 3 flips, was 2; flicker-085 P1, L755 / ruling L960: a mana pool with no tick seen
        -- pads nothing, at the gap BT cost crossing; not traced per tick).
        -- 1.1 -> 1.0 (1.00 measured on integ/0.8.5-w2, the merged tree, L1037/L1103): the Serpent Sting debuff at its
        -- landing, flicker-085 and the timing merges are all in; one flip a minute remains.
        -- 1.0 -> 0.4 (0.33 measured at the batch): replay-flips-09 ade4d6379 (L1317)
        0.4,
        "SurvivalRanged",
    },
    -- wowsims's non-weave builds (owner 2026-11-12, ledger L661): new rows, first measured on this lane (R6; the
    -- replay is one fight at the log's seed). The Turret worlds know every ability their list casts (no extra kit);
    -- Survival Melee's replay opens Mongoose Bite on Expose Prey as the weave's (REPLAY_EXTRA). Replay misses: the
    -- Turrets' are Serpent Sting against Arcane Shot (the sting believed up at the cast, about 0.33 s before it lands:
    -- the weave rows' class, no belief landing hook); Survival Melee's 5 (traced to the decision, not to the cause): the
    -- log's immolation_trap against our wing_clip 2 and summon_hawk 1, summon_hawk against wing_clip 1, strider_kick against
    -- wing_clip 1 (untraced).
    -- Live limits over 6 s, TRACED per tick (2026-11-13, a probe over ws.live's own idle test, worst streak of the first
    -- fight): the weave rows' R41 class, mana dry. Each worst streak starts with the pool at 2-17 of 5000 and ends when
    -- it reaches Arcane Shot's cost (95 at L40 for Marksmanship Turret, 106 at L40 for Survival Melee, 167-190 at
    -- L60: 2 -> 167 in 14.0 s, 17 -> 190 in 12.8 s, 2 -> 190 in 15.4 s, 3 -> 190 in 15.4 s), the regen of the pool
    -- (about 10 mana a second at L40, 12-13 at L60) and nothing else. What the world answers usable meanwhile: Shatter
    -- Curse from the first tick (no trap appears); Hunter's Mark and the Aspect are pack lines the probe did not trace
    -- (possibly already up); Survival Melee's Wing Clip, Strider Kick and Mongoose Bite are pack lines held by the
    -- melee range conditions at the live world's 11 yd (R63). Rows: MM Turret L40 9.4 (t 110.8-120.0) / L60 14.0 (t
    -- 61.2-75.0), BM Turret L60 13.0 (12.8, t 65.0-77.6), SV Turret L60 15.4 (t 82.8-98.0), SV Melee L40 10.0 (t
    -- 81.6-91.4) / L60 15.4 (t 65.8-81.0).
    -- ON flicker ceilings, traced per tick: MM Turret 1.7 (5 flips) and SV Turret 1.0 (3 flips). 7 of the 8 flips drop
    -- out once the log's own presses are applied (loop.flips with a press array: the replay passes none, so "shown, then
    -- cast" counts here where a live run's press excludes it; Beast Mastery's note above, the no-press-exclusion lead):
    -- 6 read ours aimed_shot -> arcane_shot -> aimed_shot against the log's arcane_shot, arcane_shot, aimed_shot (why
    -- Arcane Shot is first only at the cast tick: not traced further), and the 110.2 s one (MM Turret) reads
    -- arcane_shot -> serpent_sting -> arcane_shot against sting, sting, arcane, the log pressing the sting at the middle
    -- tick (the Serpent Sting class of the misses is its other reason). The 1 that survives, MM Turret tick 288 (57.6 s;
    -- ceiling 1.7 holds it): ours arcane -> aimed -> arcane while the log shows arcane x3, then aimed at 291. Traced
    -- (per-tick queue dump): wowsims casts Sniper Shot at 57.65 (a decision our first icon missed: it showed Arcane
    -- Shot, one of the profile's 3 decision misses), which spends 102 of the believed mana (467 -> 365: both shots stay
    -- affordable) and applies an aura at tick 289. Then a cooldown near-tie at the EARLY_EXIT edge (gap DB): at tick 289
    -- Arcane Shot, higher in the list, waits 0.26, over EARLY_EXIT's 0.2 (Core.lua:627, the list exit), and Aimed Shot
    -- (wait 0.10) is more than 0.05 s sooner (Core.lua:786), so Aimed Shot takes the icon; at 290 Arcane Shot's 0.06 is
    -- inside EARLY_EXIT and holds, and Aimed Shot returns at 291 after the log's Arcane Shot.
    {
        "hunter_beast_mastery_turret",
        "BeastMasteryTurret",
        "Beast Mastery Turret (wowsims.com)",
        -- 1.00 -> 0.98 (0.980 of 51; re-pin e5a9cd2a2d -> e4ef929e54: wowsims's hawk rotation, turret_hawk.apl.siml,
        -- traced per tick): the one miss is the Serpent Sting refresh against Summon Hawk at 84.41 s: our sting comes due
        -- 0.07 s after the decision tick and outranks the hawk (0.01 s), wowsims's sting is still up for its hawk (the
        -- Turret rows' Serpent Sting class; the old list had no hawk at that refresh)
        1.0, -- 0.98 -> 1.00 (1.000 of 55; re-pin ab0f00e4fc: the new log's hawk rotation has no sting miss)
        -- live L40 6 -> 11.0 (4.4 before: the old list cast neither shot at 40), the re-pin's L40 cause (above, traced): Summon Hawk 10 x 189 and
        -- Arcane Shot 5 x 189 are 2835 of 6006 mana; the streak (t 99.8-110.6) runs the pool 15.2 -> 159.7 waiting on
        -- Aimed Shot 160.
        { [10] = 6, [40] = 11.0, [60] = 13.0 }, -- 4.4 / 11.0 / 12.8
        -- 0 -> 0.7 (0.67 measured, 2 flips; re-pin, the hawk rotation, traced per tick): both are aimed_shot ->
        -- summon_hawk -> aimed_shot at the tick the log presses Summon Hawk (48.0 s, 173.4 s): "shown, then cast", which a
        -- replay counts because it passes no press array (the MM / SV Turret note below)
        0, -- 0.7 -> 0 (0.00 measured at the batch): replay-flips-09 ade4d6379 (L1317)
        nil,
        {},
        {},
    },
    {
        "hunter_marksmanship_turret",
        "MarksmanshipTurret",
        "Marksmanship Turret (wowsims.com)",
        -- 0.95 -> 0.98 (0.983 of 60; re-pin ab0f00e4fc; 0.982 (56) before). The one miss, located per decision (fix
        -- round): 155.96, wowsims casts Arcane Shot at its GCD end with the sting fading 0.03 s later (155.99); our
        -- sting ends 156.00, so serpent_sting 0.04 s off outranks it (the Turret rows' Serpent Sting near-tie class)
        0.98,
        -- live L40 9.4 -> 9.8, the re-pin's L40 cause (above, traced): Arcane Shot 14 x 166.3
        -- (Efficiency 4/5) are 2328 of 6020 mana; the streak (t 96.2-105.8) runs the pool 14.4 -> 139.8 waiting on Aimed
        -- Shot 140.8.
        { [10] = 6, [40] = 9.8, [60] = 14.0 }, -- 4.4 / 9.8 / 13.8
        -- 0 -> 0.34 (0.333 measured: 1 flip in 180 s, above 0.33; re-pin e4ef929e54 -> ab0f00e4fc, traced per tick):
        -- arcane_shot -> aimed_shot -> arcane_shot at 58.10-58.50. During Sniper Shot's cast (321.2, paid at 58.24) the
        -- belief's mana lo sits 464 under the truth (530 vs 994) since the build's new Demonic Rune (23.72: +1377.6, a
        -- 900-1500 roll the secret pool never shows); on lo Aimed Shot (272.8) is short after Sniper's spend, so Arcane
        -- Shot shows (its 58.57 cooldown end); at 58.30 the spend is seen, Aimed shows (its GCD end 58.40); at 58.50
        -- Arcane, 0.07 s off, outranks it again, as wowsims's own re-queue (58.16 Aimed -> 58.36 Arcane). On the true
        -- pool Aimed shows at 58.10 too: no flip
        0.34,
        nil,
        {},
        {},
    },
    {
        "hunter_survival_turret",
        "SurvivalTurret",
        "Survival Turret (wowsims.com)",
        1.0, -- 0.96 -> 1.00 (1.000 of 55; re-pin ab0f00e4fc, set to the measurement)
        -- live L40 6 -> 10.2, the re-pin's L40 cause (above, traced): Arcane Shot 14 x 189 are
        -- 2646 of 5661 mana; the streak (t 110.0-120.0) runs the pool 33.4 -> 112.8 waiting on Hunter's Mark 60 to the
        -- fight's end.
        { [10] = 6, [40] = 10.2, [60] = 15.4 }, -- 4.4 / 10.2 / 15.4
        0, -- 1.0 -> 0 (0.00 measured at the batch; 1.00 before): replay-flips-09 ade4d6379 (L1317)
        nil,
        {},
        {},
    },
    {
        "hunter_survival_melee",
        "SurvivalMelee",
        "Survival Melee (wowsims.com)",
        1.0, -- 0.94 -> 1.00 (1.000 of 81; re-pin ab0f00e4fc, set to the measurement)
        -- in melee 116.8 / 7.2 / 8.6: the live bars run W.SurvivalMeleeRanged (R63, hunter_world.lua): 4.4 / 10.0 / 15.4
        -- live L40 10.2 -> 12.0, the re-pin's L40 cause (above, traced): Arcane Shot 10 x 189
        -- and Multi-Shot 8 x 239 are 3802 of 5552 mana; the streak (t 69.8-81.6) runs the pool 2.0 -> 135.4 waiting on
        -- Immolation Trap 135.
        { [10] = 6, [40] = 12.0, [60] = 15.4 },
        -- 0 -> 0.4 (0.33 measured, 1 flip; re-pin, the Pre-BiS gear and the run-out line re-time the fight; traced per
        -- tick): summon_hawk -> mongoose_bite -> summon_hawk at 59.0 s, the tick the log presses Mongoose Bite (its
        -- Expose Prey window just open): "shown, then cast", counted because a replay passes no press array
        0, -- 0.4 -> 0 (0.00 measured at the batch): replay-flips-09 ade4d6379 (L1317)
        "SurvivalMeleeRanged",
    },
}

describe("the Hunter wowsims.com packs #slow #wowsims", function()
    -- one block per pack: the replay floor, the ON flicker ceiling, and the live limit per bracket
    for _, p in ipairs(PACKS) do
        local spec, world, pack, FLOOR, LIVE, FLICKER = p[1], W[p[2]], p[3], p[4], p[5], p[6]
        local liveWorld = W[p[7] or p[2]]
        it(pack .. " follows wowsims's casts", function()
            local r, line = ws.gate(pack, content(spec, world, pack, 60, p[8] or REPLAY_EXTRA), spec, FLOOR, REPLAY)
            ab.check(r.flicker <= FLICKER + 1e-9, pack, "ON flicker ceiling: " .. line)
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, liveWorld, pack, level, p[9] or EXTRA), LIVE[level])
            end)
        end
    end
end)

-- The replay and live characters learn the kit's ranks by level (ws.content's learn levels), so the book ranks wowsims's
-- character never casts (hunter_world.lua BOOK) must stay unlearned there too: Serpent Sting at rank 8's 230 (202.4
-- under Marksmanship's Efficiency 4/5), as every log pays.
describe("the Hunter replay characters", function()
    it("know no book rank at 60: Serpent Sting is rank 8's price", function()
        local headless = require("Game.harness.headless")
        local out = {}
        for _, p in ipairs(PACKS) do
            local C = content(p[1], W[p[2]], p[3], 60, p[8] or REPLAY_EXTRA)
            local H = headless.new({ character = C.character(), pack = C.PACK })
            out[p[1]] = {
                ("%.2f"):format(H.Hekili.State.action.serpent_sting.cost),
                H.ctl.known[25295] or false,
                H.ctl.known[25296] or false,
            }
        end
        local rank8 = { "230.00", false, false }
        assert.are.same({
            hunter_survival = rank8,
            hunter_beast_mastery_turret = rank8,
            hunter_marksmanship_turret = { "202.40", false, false },
            hunter_survival_turret = rank8,
            hunter_survival_melee = rank8,
        }, out)
    end)
end)

-- Task 9 (S2's unknown-bracket pin, the real client path): a replay world at 20 yd (beyond melee, inside the shots'
-- band) gives the belief a plain range bracket at the pull, so the bracket's unknown "both sides" answer is gone and
-- an on-next-swing melee strike reads out of range there. Here, not in tests/Game/harness/replay_spec.lua: the boundary
-- rule keeps class content out of the harness core.
describe("the Hunter replay at 20 yd #slow #wowsims", function()
    it("knows the target's range at the pull and reads the melee strike out of range", function()
        local loop = require("Game.harness.loop")
        local replay = require("Game.harness.replay")
        local spec, pack = "hunter_survival", "Survival (wowsims.com)"
        local C = ws.logged(content(spec, W.Survival, pack, 60, REPLAY_EXTRA), spec)
        local L = loop.new(C)
        local o = ws.replayOptions(C, spec, REPLAY)
        o.distance = 20
        local R = replay.new(ws.log(spec), L.oracle, o)
        local H, seen = L.us, nil
        loop.replay(L, R, {
            duration = 2,
            on = function(_, _, t)
                if not seen and t >= R.pull and t < R.pull + 0.5 then -- the log's first move is 0.71 s in
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
