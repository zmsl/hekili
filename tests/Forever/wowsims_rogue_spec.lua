-- tests/Forever/wowsims_rogue_spec.lua (wowsims packs plan, Task 8): the Rogue wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.rogue_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("ROGUE"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- { pack, recipe, world content, replay floor (decisions on-GCD, measured 2026-10-20, never lowered; Combat 0.958 and
-- Subtlety 0.963 (0.988 over central fix 12) on central fix 13: the strictSequence opener, the cooldown restart), LIVE60 (the
-- pack's own worst idle at 60: wowsims's energy pooling, seconds rounded up to 0.1; Combat 4.8 -> 4.0 and Subtlety
-- 3.8 -> 4.2 re-set on central fix 22 round 2 from their measurement, both under the 6 s floor and unmoved by fix 22:
-- Combat's L60 fell to 4.0 earlier; Subtlety's rose to 4.2 at 5a9b9987 (each world rolls wowsims's avoids per press:
-- the live world's draws moved, git bisect on the L60 line) }
-- Subtlety 0.98 -> 0.96 (0.963, 79 of 82 = base 0.988 - 2/82, R2) on the oracle refresh (sim pin e2842f0a78 + documented
-- patches: upstream #750's item-slot hand tags, the Darkmantle set ID 512 patch) and its fight-end edges 49.81/153.25/178.55
-- Mutilate's per-hand hits are GCD-0 Casting lines {SpellID: 1241584, Tag: 14/15}: procs, neither decisions nor casts.
local MUTILATE_HANDS = { procs = { ["1241584:14"] = true, ["1241584:15"] = true } }
-- Re-pin e2842f0a78 (Task 13, ruling R29: the recipes' `vars` play the builds' Use Backstab = false): Assassination
-- 0.98 -> 0.93 (0.932 of 59; 3 of the 4 misses are the fight's last 6 s, "Fight About to End" never fires: remainingTime
-- reads 3600, gap AN, API; 1 an unseen Rogue Armor Energize 27788 at log 79.25 (venom at 80.69, belief lo 13.1 vs truth 25);
-- without the 3 fight-end misses 0.949, within max(0.02, 2/59) of base 0.982); LIVE60 5.0 measured. Combat 0.95 -> 0.97
-- (0.973 of 73; LIVE60 4.0 -> 4.4 measured). Subtlety 0.96 -> 0.96 (0.964 of 83; LIVE60 4.2 measured).
-- Floors step on integ/0.7 5deb101c4 (CN8 cooldown probe + steady icons default; logs unchanged since pin move 2, R6 truncation):
-- Assassination 0.93 -> 0.97 (0.978 of 91 decisions on-GCD), LIVE60 5.0 -> 5.2 (L60 world re-rolled under the new cooldown
-- handling and steady icons; still under the 6 s bar, which governs: max(6, LIVE60)). Combat 0.97 -> 0.99 (0.991 of 108),
-- LIVE60 4.4 -> 3.0 (measured; same cause). Flicker 0.00/min (Assassination), 1.00/min (Combat), both inside the harness ceiling.
-- Subtlety unchanged and BLOCKED by CN16 (frontOfTarget, rogue-1.md): measured 0.670 (CN8 moved it from the 0.976 the
-- coordinator quotes; the missing Ghostly Strike line is the cause), idle 99.6/84.8 s at L40/L60: fails until CN16 lands.
local PACKS = {
    { "Assassination (wowsims.com)", "rogue_assassination", W.Assassination, 0.97, 5.2, MUTILATE_HANDS },
    { "Combat (wowsims.com)", "rogue_combat", W.Combat, 0.99, 3.0 },
    { "Subtlety (wowsims.com)", "rogue_subtlety", W.Subtlety, 0.96, 4.2 },
}

describe("the Rogue wowsims.com packs #slow #wowsims", function()
    for _, p in ipairs(PACKS) do
        local pack, spec, base, FLOOR, LIVE60, knobs = p[1], p[2], p[3], p[4], p[5], p[6]
        it(pack .. " follows wowsims's casts", function()
            ws.gate(pack, content(spec, base, pack, 60), spec, FLOOR, knobs)
        end)
        for _, level in ipairs({ 10, 40, 60 }) do
            it(pack .. " stays live at level " .. level, function()
                -- R22a: L10/L40 keep the 6 s bar; only L60 may follow the pack's LIVE60
                ws.live(pack, content(spec, base, pack, level), level == 60 and math.max(6, LIVE60) or 6)
            end)
        end
    end
end)
