-- tests/Forever/wowsims_warlock_spec.lua (wowsims packs plan, Task 13): the Warlock wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
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
-- LIVE60 0.2 in every pack: each list ends in an unconditional Life Tap, so no bracket idles (worst 0.2 s at 10, 40
-- and 60); no low-level filler (owner ruling 2026-10-21). The L10/L40 brackets keep 6 s, only L60 may follow LIVE60 (R22).
-- Re-pin e2842f0a78 (Task 11): Affliction 0.87 -> 0.98 (0.988, 84; was 0.989, 87), replay flicker 0.00/min before and
-- after, LIVE60 0.2 -> 0.2.
-- Re-pin e2842f0a78 (Task 16; the four new Human builds and Sesam's lists; the replay answers fight_remains from the
-- log, R42; replay flicker 0.00/min in all five, oracle 0.00). Classes A and C are accepted measured limits (R50):
-- A, the Demonic Rune and Major Mana Potion refills are invisible to the mana belief (gaps "Potion mana refill"), so
-- the new `life_tap,if=mana.pct_lo<30` line fires 20-40 s after each; C, the pre-pull hard cast is omitted
-- (spellTravelTime does not fold). Each history names the floor's own cause; the counts are the traced misses.
--   Affliction 0.98 -> 1.00 (1.000, 84): the kit's fsr seed {33.88, 10.4} -> {38.13, 15.2} (the four Human logs)
--   moves one decision, Wrack at 142.50 (never -> in grain).
--   Demonology 0.77 -> 0.89 (0.897, 117): A 6, C 1, 5 Searing Pain / Life Tap near-ties.
--   Shadow Brand 0.73 -> 0.71 (0.718, 103; LOWERED): A 14, C 1, and the Demonic Brand charges class (API-forced: the
--   Succubus's attacks spend the brand's 6 charges, unseen; 8 misses at 157-170 s), larger now the new list leads with
--   the brand's Searing Pain line; without A and C 0.841.
local PACKS = {
    { "warlock_affliction", "Affliction", "Affliction (wowsims.com)", 1.00, 0.2 },
    { "warlock_sm_ruin", "SMRuin", "SM Ruin (wowsims.com)", 0.70, 0.2 },
    { "warlock_demonology", "Demonology", "Demonology (wowsims.com)", 0.89, 0.2 },
    { "warlock_shadow_brand", "ShadowBrand", "Shadow Brand (wowsims.com)", 0.71, 0.2 },
    { "warlock_destruction", "Destruction", "Destruction (wowsims.com)", 0.74, 0.2 },
}

describe("the Warlock wowsims.com packs #slow #wowsims", function()
    -- one block per pack: the replay floor, the pack's own worst idle at 60 (LIVE60, measured), and the brackets
    for _, p in ipairs(PACKS) do
        local spec, world, pack, FLOOR, LIVE60 = p[1], W[p[2]], p[3], p[4], p[5]
        it(pack .. " follows wowsims's casts", function()
            ws.gate(pack, content(spec, world, pack, 60), spec, FLOOR)
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                ws.live(pack, content(spec, world, pack, level), level == 60 and math.max(6, LIVE60) or 6)
            end)
        end
    end
end)
