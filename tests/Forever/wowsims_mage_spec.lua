-- tests/Forever/wowsims_mage_spec.lua (wowsims packs plan, Task 12): the Mage wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.mage_world")
local ab = require("Game.harness.ab")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("MAGE"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- The replay's: Fireball's and Pyroblast's DoT parts are their own GCD-0 Casting lines {SpellID: 10151 / 18809,
-- Tag: 1}: procs, neither decisions nor casts.
-- Frostfire Bolt's DoT part likewise {1237313, Tag: 1}.
local REPLAY = {
    fire = { procs = { ["10151:1"] = true, ["18809:1"] = true } },
    frostfire = { procs = { ["1237313:1"] = true, ["18809:1"] = true } },
}

-- recipe, world content, pack, the replay floor (never lowered except with a named cause, written below), LIVE60:
-- the pack's own worst idle at 60, rounded up to 0.1 s (P8; the L10/L40 brackets keep 6 s, ruling R22).
-- History (before the re-pin):
-- Floors: Arcane 0.780 (46 of 59), Fire 0.794 (50 of 63), truncated; the classification in each recipe's header.
-- Fire raised 0.79 -> 0.84 on 0ce5d1a4 (0.841, 53 of 63): the replay's cooldown end is the log's timestamp, so Fire
-- Blast's three decisions at its cooldown's end agree (the CD_PROBE disagreement in mage_fire.lua's header).
-- Fire 0.84 -> 0.82 on central fix 26 (0.825, 52 of 63): the Pyroblast at the log's 134.01 follows a Mana Citrine
-- (833 mana, off the GCD, unmodelled in the replay) from about 150 mana; it agreed only through the stale forecast
-- slice that showed a 440-mana cast ready at any mana, so ours now shows Scorch waiting on its 150.
-- Arcane 0.77 -> 0.81 on the same fix (0.814, 48 of 59): wowsims's Frostbolts at the log's 93.87 and 132.37, never
-- shown before (the stale slice showed Arcane Blast ready), now shown; the Arcane Blast at 155.07 no longer early.
-- LIVE60 (then): Arcane 0; Fire 12.6, its mana out by 85 s and waiting on Fire Blast's 340, as wowsims's own fight
-- runs dry (its Evocation then on its 8-minute cooldown, which the gate counts as a usable free ability).
-- The loops' flicker (pack_gate FLICKER; 20 fights: Arcane 1.43/min, oracle 1.41; Fire 1.21/min, oracle 0.40). Fire's
-- excess is measured, not fixed: in 3 fights (seeds 1-3), 7 of its 10 first-icon A-B-A flickers are fire_blast >
-- fireball > fire_blast at Fire Blast's cooldown end (the not-ready flag pushes the believed ready time to now +
-- CD_PROBE each settle while the model's own end is nearer: central, mage_fire.lua's header) and 3 combustion > scorch;
-- the 20-fight line's waits [scorch:unknown 148] are the Scorch line's `debuff.fire_vulnerability.remains<5` edge on
-- the modelled (unreadable) target debuff, a candidate not yet measured as flicker.
-- Frostfire (Task FFB): 0.891 (49 of 55), floor 0.89 (mage_frostfire.lua's header); LIVE60 10.8: as Fire's, its mana
-- spent out by about 80 s, it waits on Frostfire Bolt's 314.5 and Fire Blast's 340 (Evocation on its cooldown).
-- Re-pin e2842f0a78 (Task 10; the misses traced in each recipe's header):
-- Arcane 0.81 -> 0.96 (0.966, 56 of 58; both misses the mana gem's restore not believed), LIVE60 0 -> 10.0 (the Deep
-- Arcane list has no cheap filler: mana dry by about 90 s, waiting on Fire Blast's 340; wowsims's own fight idles
-- 96.40 -> 114.40).
-- Fire 0.82 -> 0.97 (0.974, 76 of 78; 70.50 a replay limit (line position), 87.00 untraced), LIVE60 12.6 -> 6.0
-- (measured).
-- Frostfire 0.89 -> 0.96 (0.965, 55 of 57; the mana gem, the `remains<5` line-position edge), LIVE60 10.8 -> 11.8
-- (mana dry from about 87 s, waiting on Frostfire Bolt's 314.5 and Scorch's 150; wowsims's own fight idles about 10 s
-- at 91.6).
-- The replay's flicker rose (Fire 0 -> 2.66/min, Arcane 0.67 -> 1.33): the belief's cooldown probe push (CD_PROBE)
-- shows the filler one poll at each cooldown end, central (gaps.md CQ), fixed by Task 10b (ruling R21): the replay's
-- flicker ceiling (per minute, the last column) guards it, Fire 2.66 -> 0.67; Arcane 1.33 -> 1.33 (the same four
-- flips at the fix's base and after: 121.0, 142.4 / 142.6, 182.8; 142.4 is Fire Blast's end 0.1 s past the GCD's,
-- which the fix does not cover). The 20-fight loops cannot guard it: their presses land on the 0.2 s poll grid, so a 1.5 s GCD ends half a
-- poll off Fire Blast's end and at the frozen polls the GCD has 0.3 s or more left, where the engine keeps the frozen
-- pick; wowsims's casts line the GCD's end up with the cooldown's, 0.1 s after the last frozen poll.
-- Leveling (R22): Arcane L40 6.4 s and Frostfire L10 6.6 s took recipe `leveling` fillers (the recipes' headers).
-- 0.7 re-pin e5a9cd2a2d + CN8 (lane mage, R6, measured on the new logs, steady icons on): Arcane 0.96 -> 0.95 (0.954, 63 of
-- 66; the Arcane Concentration channel-start roll moved the random stream and the logs, 53b0b6a80e: the remaining
-- misses are arcane_blast / arcane_missiles / arcane_wrath -> evocation at its cooldown end, one each); Fire 0.97 ->
-- 0.96 (0.963, 78 of 81; the same cause: Fire takes Arcane Concentration 5/5, Clearcasting lines 20 -> 25, top
-- arcane_missiles -> arcane_blast, fireball -> scorch, pyroblast -> scorch, one each); Frostfire 0.96 kept (0.964, 55
-- of 57; fire_blast -> frostfire_bolt, fire_blast -> scorch). Flicker ceilings 1.4 / 0.7 -> 0.34 (measured 0.33, S:
-- steady icons on by default; the line rounds up) for Arcane and Fire, Frostfire 0. LIVE60 unchanged (Arcane 10.0,
-- Fire 6.2, Frostfire 11.8: re-measured, the same).
local PACKS = {
    { "mage_arcane", "Arcane", "Arcane (wowsims.com)", 0.95, 10.0, 0.34 },
    -- LIVE60 6.0 -> 6.2 (CN8 D2): the same dry-pool wait for Scorch (96.4-102.4 s, mana 49-153), one poll longer on
    -- the re-timed fight
    { "mage_fire", "Fire", "Fire (wowsims.com)", 0.96, 6.2, 0.34 },
    { "mage_frostfire", "Frostfire", "Frostfire (wowsims.com)", 0.96, 11.8, 0 },
}

describe("the Mage wowsims.com packs #slow #wowsims", function()
    -- one block per pack: the replay floor, the brackets (6 s; L60 the pack's own LIVE60 when higher)
    for _, p in ipairs(PACKS) do
        local spec, world, pack, FLOOR, LIVE60, FLICKER = p[1], W[p[2]], p[3], p[4], p[5], p[6]
        it(pack .. " follows wowsims's casts", function()
            local r, line = ws.gate(pack, content(spec, world, pack, 60), spec, FLOOR, REPLAY[p[2]:lower()])
            ab.check(r.flicker <= FLICKER, pack, line) -- a bar: recorded in a provider arm (providers spec §4.1)
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, world, pack, level), level == 60 and math.max(6, LIVE60) or 6)
            end)
        end
    end
end)
