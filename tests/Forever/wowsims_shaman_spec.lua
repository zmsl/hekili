-- tests/Forever/wowsims_shaman_spec.lua (wowsims packs plan, Task 10): the Shaman wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local sw = require("Forever.helpers.shaman_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("SHAMAN"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- Flametongue Totem's weapon proc is logged under the totem's ID with Tag 1 (not a choice); every totem cast fills its
-- slot (1 fire, 2 earth, 3 water, 4 air) for its top rank's DB2 duration.
local ENH_REPLAY = {
    -- Fire Nova's nova lines (Tag 1, GCD 0, cost 0) come at the instant of its real cast: the hit, not a choice.
    procs = { ["16387:1"] = true, ["408345:1"] = true, ["10587:1"] = true }, -- and Magma Totem's pulses
    totems = {
        searing_totem = { 1, 55 },
        flametongue_totem = { 1, 300 },
        magma_totem = { 1, 40 }, -- the build's Trial by Fire 2/2 (+20 s; the log recasts it 40 s apart)
        strength_of_earth_totem = { 2, 300 },
        mana_spring_totem = { 3, 300 },
        grace_of_air_totem = { 4, 300 },
        windfury_totem = { 4, 300 },
    },
}

-- Elemental: the Searing Totem's attacks (Tag 1) and Lightning Overload's extra bolts (Tag 6) are not choices.
local ELE_REPLAY = {
    procs = { ["10438:1"] = true, ["10392:6"] = true, ["15208:6"] = true },
    totems = {
        searing_totem = { 1, 55 },
        magma_totem = { 1, 20 },
        strength_of_earth_totem = { 2, 300 },
        mana_spring_totem = { 3, 300 },
        windfury_totem = { 4, 300 },
    },
}

describe("the Shaman wowsims.com packs #slow #wowsims", function()
    local PACK = "Enhancement (wowsims.com)"
    -- the learn levels are wowsims's SpellLevel (the DB2 at 70707 agrees); the table once had 25/48/58 for Mana Tide
    -- Totem, and lacked its Forever rank 4 (deferral L39). Lava Burst is gone from the game (re-pin 0.7).
    it("learns Mana Tide Totem at wowsims's levels", function()
        local learn = ws.learn("SHAMAN")
        assert.are.same({ 1, 38, 48, 58 }, { learn[16190], learn[17354], learn[17359], learn[1325256] })
    end)

    -- the replay floor, measured (0.602 first; 0.750 with Call of Flame and Stormstrike's cost; 0.784 once the replay
    -- sends shared and talent cooldowns; 0.807 on central fix 6; Fire Nova at 375 was reverted, R2; 0.818 on central
    -- fix 12's five-second-rule mana forecast; 0.909 on central fix 13's cooldown restart; 0.920 on 13 over 12), never lowered
    -- but once: 0.90 on central fix 15 (owner ruling), whose cooldown starts at the cast's own time. The ready time is
    -- now wowsims's own (Stormstrike cast at 51.0 on the replay's clock, the log's 51.5, ready at 59.000, not the fold's
    -- 59.054), and the priority picks differently at that near-tie (0.909: fire_nova -> stormstrike); recover with GAP AB
    -- 0.989 (87/88) once the replay ends a cooldown at its log timestamp (the ready-time ruling). Re-pin e2842f0a78
    -- (lane 15, R56 as amended by R57a): 0.988 (85), was 1.000 (base); floor stays 0.98. At the DB2's 520 for Fire Nova
    -- it was 0.965 (three misses); wowsims's 375 (R57a) leaves one: the Major Mana Potion refill the belief cannot see
    -- (R50 class A; log 121.47, magma_totem -> stormstrike). Re-pin 0.7 (e5a9cd2a2dfc, lane shaman, R6): 0.98 -> 0.96,
    -- 0.969 (97), was 0.988: three single misses, [fire_nova -> lightning_bolt, flame_shock -> stormstrike, magma_totem
    -- -> stormstrike], the repin triage's ties and dry mana (the build's Stormstrike cooldown is now 6 s; the potion
    -- refill the belief cannot see, R50 class A, GAP V, is among them: central); no Stormstrike pattern
    it(PACK .. " follows wowsims's casts", function()
        local C = content("shaman_enhancement", sw.Enhancement, PACK, 60)
        ws.gate(PACK, C, "shaman_enhancement", 0.96, ENH_REPLAY)
    end)
    -- the pack's own worst idle at 60, seconds rounded up to 0.1: wowsims's spending runs the mana out (its own log
    -- sits near 170 of 5530 mana from 90 s), so the priority waits for mana with only cheaper ranks usable
    -- 8.0 before the world's parry haste (decision 63: every seeded fight reordered); 8.2 -> 5.2 re-pin e2842f0a78
    -- (lane 15: the build's own list, 6565 mana, Fire Nova at 375; 5.0 at 520); under the 6 s bar (R22) as L10/L40
    local LIVE60 = 5.2
    for _, level in ipairs({ 10, 40, 60 }) do
        it(PACK .. " stays live at level " .. level, function()
            ws.live(
                PACK,
                content("shaman_enhancement", sw.Enhancement, PACK, level),
                level == 60 and math.max(6, LIVE60) or 6
            )
        end)
    end

    local ELE = "Elemental (wowsims.com)"
    -- the replay floor, measured (0.853 before the translator's multidot, central fix 28; 0.937 of 95 first clean
    -- run), never lowered; the misses are shared gaps (tools/wowsims/specs/shaman_elemental.lua's header). 0.93 -> 0.92
    -- re-pin e2842f0a78 (Task 11, ruling R26): 0.928 (97), was 0.957 (92); the central gaps.md "Travel time" row (3 of
    -- the 7 misses, Revelation spent at Lava Burst's cast end; 0.959 without them) plus gap BL; flicker 0.00/min
    -- Chain Lightning's, Lava Burst's and Mana Tide Totem's costs from wowsims's spell data (lane shamanpin): 0.928 (97) unchanged
    -- Re-pin 0.7 (e5a9cd2a2dfc, lane shaman, R6): 0.92 -> 0.89, 0.896 (96); Lava Burst is gone, Chain Lightning costs
    -- 70% more and mana-gates (`mana.pct_lo>=40`), five APL lines changed. Ten misses, three causes: chain_lightning ->
    -- lightning_bolt 3 (+ flame_shock 1): central, the Major Mana Potion and Demonic Rune refills the belief cannot see
    -- (lo ~2630 under the truth; gaps.md "Potion mana refill"; the floor recovers with that fix); earth_shock ->
    -- lightning_bolt 3: a Revelation charge gained mid-cast is dropped at the cast's end (blocker shaman-1: the belief has
    -- no cast-start hook); lightning_bolt -> searing_totem 3: the kit prices Lightning Bolt at its top rank (198) where
    -- wowsims down-ranks (rank 8, 144 mana, at mana < 20%: gap BL, disagreement 1 of the recipe), so with ~179 mana the
    -- totem (170) is the sooner wait (debug snapshot at t=117.43: Searing Totem usable at 0.89 s, Lightning Bolt at
    -- 5.4 s, cost 198)
    it(ELE .. " follows wowsims's casts", function()
        ws.gate(ELE, content("shaman_elemental", sw.Elemental, ELE, 60), "shaman_elemental", 0.89, ELE_REPLAY)
    end)
    -- the pack's own worst idle at 60, seconds rounded up to 0.1: wowsims runs its mana out (its log of 5650 sits under
    -- 220 at 100-120 s and from ~170 s, Lightning Bolt 3-6.7 s apart), so the priority waits for mana. 5.0 -> 5.0 at the
    -- re-pin (5650 mana); L10/L40 keep the 6 s bar, only L60 may follow LIVE60 (R22, both packs)
    local ELE_LIVE60 = 5.0
    for _, level in ipairs({ 10, 40, 60 }) do
        it(ELE .. " stays live at level " .. level, function()
            ws.live(
                ELE,
                content("shaman_elemental", sw.Elemental, ELE, level),
                level == 60 and math.max(6, ELE_LIVE60) or 6
            )
        end)
    end
end)
