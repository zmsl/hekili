-- tests/Forever/wowsims_warlock_spec.lua (wowsims packs plan, Task 13): the Warlock wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local ab = require("Game.harness.ab")
local W = require("Forever.helpers.warlock_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("WARLOCK"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- recipe, world content, pack, the replay floor (the first clean run's; lowered only with its cause beside it),
-- LIVE60: the pack's own worst idle at 60, rounded up to 0.1 s (P8). The classification of each pack's
-- disagreements is in its recipe's header.
-- First runs on 5d62f44c + Task 13: Affliction 0.728 (81), SM Ruin 0.606 (94), Demonology 0.767 (116), Shadow Brand
-- 0.735 (98), Destruction 0.743 (109). Raised on central fix 31 (06eec227): Affliction 0.72 -> 0.87 (0.877) and SM
-- Ruin 0.60 -> 0.70 (0.702), G4 (wowsims's dynamite miss no longer undoes our Corruption); Demonology 0.76 -> 0.77
-- (0.776), G5 (the replay's pet mana: the `pet.mana<115` Life Tap). The rest is mostly API-forced (`fight_remains`
-- 3600 s: wowsims's last-minute Bane of Agony) and G6 (Shadow Bolt's travel, central fix 32).
-- LIVE60 0.2 in every pack: each list ends in Shadow Bolt, then Life Tap under Shadow Bolt's cost (owner 2026-11-12:
-- "Life tap is not a good filler"), so no bracket idles (worst 0.2 s at 10, 40 and 60); no other low-level filler (owner
-- ruling 2026-10-21). The L10/L40 brackets keep 6 s, only L60 may follow LIVE60 (R22).
-- Re-pin e2842f0a78 (Task 11): Affliction 0.87 -> 0.98 (0.988, 84; was 0.989, 87), replay flicker 0.00/min before and
-- after, LIVE60 0.2 -> 0.2.
-- Re-pin e2842f0a78 (Task 16; the four new Human builds and Sesam's lists; the replay answers fight_remains from the
-- log, R42; replay flicker 0.00/min in all five, oracle 0.00). Classes A and C are accepted measured limits (R50):
-- A, the Demonic Rune and Major Mana Potion refills are invisible to the mana belief (gaps "Potion mana refill"), so
-- the new `life_tap,if=mana.pct_lo<30` line fires 20-40 s after each; C, the pre-pull hard cast is omitted
-- (spellTravelTime does not fold). Each history names the floor's own cause; the counts are the traced misses.
--   Affliction 0.98 -> 1.00 (1.000, 84): the kit's fsr seed {33.88, 10.4} -> {38.13, 15.2} (the four Human logs)
--   moves one decision, Wrack at 142.50 (never -> in grain).
--   SM Ruin 0.70 -> 0.78 (0.787, 94): R49's stand-in DoT lines (wowsims gates them on spellExpectedDpet, omitted;
--   without them 0.606); top [shadow_bolt -> life_tap 9 (A); shadow_bolt -> siphon_life 5; shadow_bolt ->
--   corruption 3]: the stand-ins' remains<=cast timing against wowsims's DPET choice.
--   Demonology 0.77 -> 0.89 (0.897, 117): A 6, C 1, 5 Searing Pain / Life Tap near-ties.
--   Shadow Brand 0.73 -> 0.71 (0.718, 103; LOWERED): A 14, C 1, and the Demonic Brand charges class (API-forced: the
--   Succubus's attacks spend the brand's 6 charges, unseen; 8 misses at 157-170 s), larger now the new list leads with
--   the brand's Searing Pain line; without A and C 0.841.
--   Destruction 0.74 -> 0.90 (0.900, 110): A 7, C 1, 3 Immolate refreshes at remains<=cast.
-- Re-pin e5a9cd2a2d (0.7 re-pin, R6; DECISIONS on-GCD, the pack's APL rewritten at 4b0030a44b and the pin move to
-- e5a9cd2a2d changed nothing; replay flicker 0.00/min in all five, oracle 0.00; steady icons on, CN8 C1/D2/S):
--   Affliction 1.00 -> 0.73 (0.733, 60): the omitted Siphon Life line (CN14, spellIsChanneling: wowsims casts it 7
--   times, ours shows the next line down; top [siphon_life -> wrack 5; wrack -> corruption 3; wrack -> life_tap 3])
--   and class A (the Demonic Rune / Major Mana Potion refill is invisible to the mana belief, so the new
--   `life_tap,if=mana.lo<1800` cooldowns line fires on an under-believed lo). Neither is this lane's; not worked around.
--   SM Ruin 0.78 (0.787, 94) unchanged: R49 stand-in DoT lines, CN5 stays unsupported.
--   Demonology 0.89 -> 0.86 (0.863, 117): A and C (the pre-pull cast, spellTravelTime fold held) and the Life Tap line
--   now at mana.pct_lo<35, which fires 5 points earlier on the under-believed lo.
--   Shadow Brand 0.71 (0.718, 103) unchanged: A, C and the Demonic Brand charges class (API-forced).
--   Destruction 0.90 -> 0.89 (0.899, 109): the rewritten list (Immolate refresh inside Incinerate's cast, new
--   cooldowns group), A and C; top [incinerate -> life_tap 6; immolate -> life_tap 2; incinerate -> immolate 2].
--   LIVE60 Destruction 0.2 -> 0.4 (worst idle 0.4 s at 60 with a usable ability, not traced; limit is still 6 s).
-- Second translator lane (translator-2, R6 raises, DECISIONS on-GCD; replay flicker 0.00/min unchanged):
--   Affliction 0.73 -> 0.83 (0.833, 60): CN14 restores the Siphon Life line (its 7 casts now in grain) and the
--   travel-time fold shows the pre-pull Shadow Bolt; two Wrack decisions (35.77, 145.25) are lost: Siphon Life fades
--   0.11 s after the GCD there and the engine ranks that higher line, ready 0.11 s later, over Wrack ready now.
--   Demonology 0.86 -> 0.87 (0.872, 117) and Destruction 0.89 -> 0.90 (0.908, 109): the pre-pull Soul Fire (the
--   travel-time fold) is shown. Shadow Brand 0.71 (0.718) unchanged: its pre-pull Shadow Bolt is shown, the
--   corruption pre-pull line after it is not (the hardcast runs into it); no decision moved.
-- Re-pin e5a9cd2a2d -> e4ef929e54 (0.9, R6, DECISIONS on-GCD; with mana-09 merged, which moves no Warlock cell;
-- replay flicker 0.00/min in all five, oracle 0.00):
--   Affliction 0.83 -> 0.93 (0.935, 62; 0.850 (60) on the same tree at the old log and pack): wowsims's new Wrack APL
--   (202831a0a0: no Bane of Doom on one target, Agony and Amplify Curse no longer wait on Doom, the Cooldowns Wrack
--   line gone, racials on the Amp Agony variables); top [wrack -> life_tap 3; siphon_life -> corruption 1].
--   SM Ruin 0.78 -> 0.85 (0.851, 94), Demonology 0.87 -> 0.94 (0.940, 117), Destruction 0.90 -> 0.95 (0.954, 109),
--   Shadow Brand 0.71 (0.718, 103) unchanged: each identical at the old log and pack on this tree (BASE run; the re-pin
--   moves only the Weakness Analyzer's second use, an unscored item row); the rise predates this re-pin, not bisected;
--   floor follows the measurement (R6). LIVE60 Destruction 0.4 -> 0.2 (worst idle 0.2 s at 60): identical at the old
--   log and pack on this tree (BASE run); the fall predates this re-pin, not bisected; floor follows the measurement
--   (R6).
-- Re-pin e4ef929e54 -> ab0f00e4fc (R6, DECISIONS on-GCD; replay flicker 0.00/min in all five, oracle 0.00): every build
-- carries its own gear and is Orc (wowsims #1048/#1070; owner L1397), so the logs move on the new pools (6311 / 6121 /
-- 5323 / 6294 / 5113), Life Tap gains (712.8 / 594 / 712.8 / 603 / 712.8, Spirit 170, Shadow Brand 179) and the mp5
-- part 12 (was 15.2); the world and the kit's fsr seed follow ({27.5, 12}). Central's measure with the old kit seeds read
-- Affliction 0.954 (65), Demonology 0.940, Destruction 0.927, SM Ruin 0.787, Shadow Brand 0.812 (repin-ab0f-measure.md):
-- the seeds move Demonology and Destruction up; Affliction's rise is not the seeds (the old floor sat below its
-- measurement) and Shadow Brand's is mostly a loose old floor (0.71 against 0.812):
--   Affliction 0.93 -> 0.95 (0.954, 65): the old floor was loose; top [siphon_life -> corruption 1; wrack ->
--   corruption 1; wrack -> life_tap 1].
--   SM Ruin 0.85 -> 0.80 (0.809, 94; traced): the new main hand's Revelation enchant (8217) gives the Revelation buff
--   (1323392; 0 -> 6 gains in the log), which makes wowsims prefer Shadow Bolt over Immolate (8 Immolate misses); the
--   rest is 6 end-of-fight DoT, 2 Bane of Agony, 1 Corruption and 1 early Life Tap; top [shadow_bolt -> immolate 5;
--   shadow_bolt -> siphon_life 4; life_tap -> immolate 3].
--   Demonology 0.94 -> 0.96 (0.966, 117): Life Tap at mana.pct_lo<43 (was 42); top [searing_pain -> life_tap 3].
--   Shadow Brand 0.71 -> 0.82 (0.822, 101): mostly the loose old floor; top [searing_pain -> shadow_bolt 6; shadow_bolt -> life_tap 2].
--   Destruction 0.95 -> 0.97 (0.972, 109): Life Tap at mana.pct_lo<49 (was 48); top [incinerate -> life_tap 3].
-- The replay flicker ceiling (per minute, the last column): plain flicker bars, 0 in all five, measured 0.00/min (oracle
-- 0.00) at the re-pin e2842f0a78. They say nothing about Movement: Demonology and Shadow Brand replay with it ON (R8) but
-- every replay is single-target and the Hellfire line needs active_enemies>=3.
local PACKS = {
    { "warlock_affliction", "Affliction", "Affliction (wowsims.com)", 0.95, 0.2, 0 },
    { "warlock_sm_ruin", "SMRuin", "SM Ruin (wowsims.com)", 0.80, 0.2, 0 },
    { "warlock_demonology", "Demonology", "Demonology (wowsims.com)", 0.96, 0.2, 0 },
    { "warlock_shadow_brand", "ShadowBrand", "Shadow Brand (wowsims.com)", 0.82, 0.2, 0 },
    { "warlock_destruction", "Destruction", "Destruction (wowsims.com)", 0.97, 0.2, 0 },
}

describe("the Warlock wowsims.com packs #slow #wowsims", function()
    -- one block per pack: the replay floor, the pack's own worst idle at 60 (LIVE60, measured), and the brackets
    for _, p in ipairs(PACKS) do
        local spec, world, pack, FLOOR, LIVE60, FLICKER = p[1], W[p[2]], p[3], p[4], p[5], p[6]
        it(pack .. " follows wowsims's casts", function()
            local r, line = ws.gate(pack, content(spec, world, pack, 60), spec, FLOOR)
            ab.check(r.flicker <= FLICKER, pack, line) -- a bar: recorded in a provider arm (providers spec §4.1)
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, world, pack, level), level == 60 and math.max(6, LIVE60) or 6)
            end)
        end
    end
end)
