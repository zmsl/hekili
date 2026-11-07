-- tests/Forever/wowsims_paladin_spec.lua (wowsims packs plan, Task 9): the Paladin wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ab = require("Game.harness.ab")
local ws = require("Forever.helpers.wowsims")
local pw = require("Forever.helpers.paladin_world")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("PALADIN"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- `base` as wowsims's character: without the spells in `drop` (by ID: ws.content only adds) and `world` over its WORLD.
local function wowsims(base, drop, world)
    return setmetatable({
        WORLD = setmetatable(world, { __index = base.WORLD }),
        character = function()
            local c, known = base.character(), {}
            for _, id in ipairs(c.known) do
                if not drop[id] then
                    known[#known + 1] = id
                end
            end
            c.known = known
            return c
        end,
    }, { __index = base })
end

local function set(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, id in ipairs(list) do
            out[id] = true
        end
    end
    return out
end

-- wowsims's Paladin knows the 879 ranks of Exorcism only (Undead or Demon targets; its target is Mechanical).
local EXORCISM_ANY = { 415068, 415069, 415070, 415071, 415072, 415073 }
-- The seals' hits (Seal of Command 20424, Seal of Righteousness 25713, Seal of Fury 20418, Vindication 440667) log
-- under their own IDs, never a seal's: no kit key, nothing to list in `procs`.
local REPLAY = {}
-- Protection's GCD-0 Casting lines under a kit ID are the procs' hits, not presses: Holy Shield's block damage
-- {SpellID: 20928, Tag: 2} and a Shieldsworn Holy Strike's {20928, Tag: 1328544} (each restarted the believed 10 s
-- cooldown: holy_shield -> holy_strike, re-pin e2842f0a78) and Retribution Aura's {10301, Tag: 2}
local PROT_REPLAY = {
    procs = {
        ["20928:2"] = true,
        ["20928:1328544"] = true,
        ["1239570:2"] = true,
        ["1239570:1328544"] = true,
        ["10301:2"] = true,
    },
}

describe("the Paladin wowsims.com packs #slow #wowsims", function()
    pw.Retribution.character() -- fills IDS
    pw.Protection.character()

    -- Mana: its regen per second, { from 5 s after the last spend, inside the five-second rule }
    -- (Retribution: 2.252 and 0.844 each 0.1 s in the e2842f0a78 log, was 2.19 and 0.825; Protection: 1.73 and 0.08 in
    -- the e2842f0a78 log, was 1.738 and none).
    local RET = wowsims(pw.Retribution, set(EXORCISM_ANY), { fsr = { [0] = { 22.52, 8.44 } } })
    local RET_LIVE = wowsims(pw.Retribution, set(EXORCISM_ANY), {})

    -- the replay floor: 0.860 measured on central fix 13 (49/57: removals shown as removals, the cooldown restart); 0.877
    -- (50/57) on central fix 14 (Judgement's percent-of-base cost from base mana); 0.912 (52/57) once the replay ends a
    -- cooldown at its log timestamp (the ready-time ruling); 0.895 (51/57) under the owner's ruling (2026-10-21) that the
    -- pre-pull must not twist, one starter seal (the recipe's prepullSkip): wowsims's -3 s Seal of Command is now ours
    -- Seal of the Crusader, one decision
    it("Retribution (wowsims.com) follows wowsims's casts", function()
        local C = content("paladin_retribution", RET, "Retribution (wowsims.com)", 60)
        -- 0.860 over central fix 12 too (floor 0.85). Before central fix 13: 0.56 (0.561), lowered from 0.57 (0.579) by
        -- central fix 12's mana tick padding: with the tick's phase unknown (a secret pool) the icon for a mana-gated
        -- seal comes one tick late, so one decision of 57 (Seal of Command on the tick that pays for it) shows Seal of
        -- Righteousness. Recover after the in-game UNIT_POWER_FREQUENT-for-mana
        -- checkpoint by rounding up to the observed tick; the belief's precision at near-ties is GAP AB.
        -- 0.89 -> 0.93 re-pin e2842f0a78 (fresh floor, Task 17: the Unsealed Wrath APL, default.apl.json, the build's
        -- talents, 25 yd with the opener move, Movement ON): 0.933 (45) top [consecration -> seal_of_command 3]; each at
        -- a white swing 0.02-0.05 s before wowsims's cast that completes an Echo, which wowsims reads with
        -- includeReactionTime (100 ms; the translator ignores it, rule 5) so it casts Consecration first (log 17.40,
        -- 47.22, 77.04). ON flicker ceiling 2.4 (2.33/min measured: 7 flips, 4 at an Echo-completing swing, 3
        -- Judgement / Holy Strike at Judgement's ready edge; 2.00 at the old pin, the same kinds)
        -- ON flicker 2.4 -> 2.0 (R61, the swing-clock recheck at the guard's window end: 2.33 -> 2.00/min; decisions
        -- unchanged, 0.933 (45)). ON THE BAR (= measured 2.00): re-measure at integration.
        -- 2.0 -> 2.7 (CN8 D2, 2.66 measured, the same with steady icons off): two more one-tick Holy Strike leads
        -- (n219, n319), the shape traced on Arms and Beast Mastery (an end the old probe read 0.50 now leads for a tick)
        local r, line = ws.gate("Retribution (wowsims.com)", C, "paladin_retribution", 0.93, REPLAY)
        ab.check(r.flicker <= 2.7 + 1e-9, "Retribution (wowsims.com)", "ON flicker ceiling: " .. line)
    end)
    -- the pack's own worst idle at 60: wowsims's priority spends itself dry (its own Retribution is out of mana from 60 s
    -- of its log), so its longest wait is for mana. 4.4 before central fix 8, while
    -- the collapsed mana lower bound kept Consecration's and Exorcism's `mana.pct>=10` from passing.
    -- 8.4 -> 5.2 (R41 task, measured at the base and after: the old 8.4 had not been re-measured since the re-pin); the
    -- 5.2 is no longer a mana wait: Holy Strike, Consecration and Judgement cooling, the seals up (t 57.2-62.2, mana
    -- about 60%)
    -- 5.2 -> 5.0 re-pin e2842f0a78 (Task 17, with the recipe's Seal of Command kick-start; 86.4 without it: the twist
    -- deadlocks from a melee start, see the recipe): nothing useful to cast, the strikes cooling, a seal up
    -- 5.0 -> 5.2 pin move 2 on CN8 (steady icons on), measured 5.2 at L60 (the same cause; the 6 s bar governs)
    local RET_LIVE60 = 5.2
    -- R41 (owner policy: no filler for filling's sake): the old `remains<24` Seal of Righteousness refresh held L10 at
    -- 4.4; it re-seals now only under two GCDs left. Nothing useful to cast: Holy Strike and Judgement cooling, Seal of
    -- Righteousness up (L10-L15 8.6, t 5.2-13.6). L40 keeps the 6 s bar (5.2); only L60 follows LIVE60 (R22)
    -- 8.6 -> 8.8 re-pin e2842f0a78 (Task 17): the same cause, Holy Strike (now waiting for Judgement on cooldown,
    -- wowsims's line), Judgement and Exorcism cooling, Seal of Righteousness up (t 5.0-13.2); L40 5.2
    -- 8.8 -> 8.6 (R61, the swing-clock recheck: the same cause, one tick shorter)
    local RET_LIVE10 = 8.6
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Retribution (wowsims.com) stays live at level " .. level, function()
            local C = content("paladin_retribution", RET_LIVE, "Retribution (wowsims.com)", level)
            local limit = level == 60 and math.max(6, RET_LIVE60) or level == 10 and RET_LIVE10 or 6
            ws.live("Retribution (wowsims.com)", C, limit)
        end)
    end

    -- The build takes no Holy Shock.
    local PROT_DROP = set(pw.Protection.IDS.holy_shock, EXORCISM_ANY)
    local PROT = wowsims(pw.Protection, PROT_DROP, {
        fsr = { [0] = { 17.3, 0.8 } },
    })
    local PROT_LIVE = wowsims(pw.Protection, PROT_DROP, {})

    -- the replay floor: 0.750 (28) was measured on a fight the target never swung in (the export set no tank, GAP AE);
    -- as the tank, 0.583 (48), 0.625 over central fix 12: blocks and hits return mana (Improved Seal of Fury, 61 gains; Shield Specialization, 18)
    -- that the class file does not model and the replay cannot drive (it replays no target swings), so the belief
    -- waits for mana it has (holy_shield -> holy_strike 9, seal_of_fury -> holy_strike 4)
    it("Protection (wowsims.com) follows wowsims's casts", function()
        local C = content("paladin_protection", PROT, "Protection (wowsims.com)", 60)
        -- 0.964 on central fix 12 (GAP R) was the untanked fight's; the tanked one's floor is 0.62 (30/48)
        -- 0.62 -> 0.84 re-pin e2842f0a78: 0.846 (52) top [holy_shield -> holy_strike 6; seal_of_fury -> holy_strike 2]
        -- (0.788 before PROT_REPLAY's procs: Holy Shield's block hits restarted its believed cooldown); the 8 left have
        -- the belief under the truth: wowsims returns 105.08 mana on every landed Shieldsworn Holy Strike (the kit does
        -- not model it, gaps.md CU; 45.00, 103.90, 163.00 follow one) and Holy Shield's price, ours 240 (DB2) vs
        -- wowsims's 195, is a necessary cause in 5 of the 8 (the log's mana before Holy Shield: 196-275, five under 240)
        -- 0.84 -> 0.88 (R31 owner fact: Holy Shield rank 3 costs 195, the kit's 240 was DB2 70707's Era ladder): 0.885
        -- (52) top [holy_shield -> holy_strike 4; seal_of_fury -> holy_strike 2]; 45.00 and 163.00 now agree. The 6 left
        -- (34.04, 88.04, 103.90, 128.04 Holy Shield; 108.04, 172.04 Seal of Fury) all have the truth over the cost and
        -- the belief's lo under it (lo 119 / 161 / 171 / 22 / 162 / 23 vs truth 225 / 275 / 196 / 214 / 300 / 256): the
        -- unmodelled Shieldsworn Holy Strike return (gaps.md CU), no longer the price
        -- 0.88 -> 0.95 pin move 2 (e5a9cd2a2dfc, logs identical to 4b0030a44b's but the header) on CN8: 0.958 (46/48), top
        -- [holy_shield -> holy_strike 1; seal_of_fury -> holy_strike 1] (decisions on-GCD; tick agreement 0.866). Cause of the
        -- rise from 0.885 (old pin, rank 3 at 195): the log casts Holy Shield rank 4 (1239570), and PROT_REPLAY's procs now
        -- hold its block hits (Tag 2) and Shieldsworn returns (Tag 1328544), which were replayed as casts that restarted
        -- Holy Shield's believed cooldown and spent 240 mana. The 2 left are the unmodelled Shieldsworn Holy Strike
        -- return (gaps.md CU)
        ws.gate("Protection (wowsims.com)", C, "paladin_protection", 0.95, PROT_REPLAY)
    end)
    -- the pack's own worst idle at 60: wowsims's priority spends itself dry (its own Protection is out of mana from 24 s),
    -- so its longest wait is for mana. 10.4 on central fix 22 rebased (the live world's presses resolve from the driving
    -- instance's current state: L60 11.8 -> 10.4, L40 11.0 -> 9.4, L10 8.6, measured with the gate counting only on-GCD
    -- presses, final review fix 3); 17.8 before (the untanked fight's)
    -- 11.0 at L40 with the world's parry haste (decision 63: every seeded fight reordered; L60 8.4)
    -- 12.6 at L60 from Swift Judgement as a second Judgement (hotfix 113554, 66573cf37: no Judgement reset, no free
    -- Judgement charge; wowsims swift_judgement.go): a mana wait for Holy Strike, Retribution Aura the only usable
    -- on-GCD press (L10 8.6, L40 8.4)
    -- 12.6 -> 4.6 re-pin e2842f0a78 (the new build's Shieldsworn: Holy Strike every 6 s); L10/L40 keep the 6 s bar,
    -- only L60 may follow LIVE60 (R22): L10 8.6 -> 4.4 with the recipe's Seal of Fury refresh (R28); L40 8.4, its own
    -- measured limit (R28, a one-bracket exception to R7): out of mana, nothing castable; a filler would spend mana the
    -- character lacks (10.6 s with the refresh, so the refresh stops at Holy Shield). R28a ratifies that guard
    -- (`!talent.holy_shield.enabled`): the exception is a band, L32-L40 (Holy Shield learned, Shieldsworn not,
    -- mana-dry), idle over 6 s either way (L32 11.0, L35-L40 8.4); gated at L40 only; no other bracket got a higher limit
    -- 4.6 -> 4.4 (R31: Holy Shield rank 3 costs 195, not 240; the price is the only change, L10 4.4 and L40 8.4 hold,
    -- rank 3 is learned at 60 only)
    -- 4.4 -> 4.6 at L60 (Holy Shield's four ranks, the owner's in-game tooltips 2026-11-06: 100 / 150 / 195 / 240 at
    -- 30 / 40 / 50 / 60, was the DB2's 150 / 195 / 195 at 40 / 50 / 60): rank 4's 240 is L60's price again, under
    -- the 6 s bar; L10 8.6 and L40 8.4 (rank 2 at 150, the old rank 1's price) hold; the replay keeps rank 3 (PROT);
    -- the L32-L40 band above was measured on the DB2 ladder
    -- R41 (owner policy, supersedes R28's L10 filler and R28a's guard): the Seal of Fury refresh (`remains<24`) is gone;
    -- wowsims's own line re-seals when the seal is down. L10 4.4 -> 8.6, its measured limit: nothing useful to cast:
    -- Holy Strike and Judgement cooling, Seal of Fury and Righteous Fury up (L10-L15 8.6, t 6.6-15.0). L20-L25 6.4,
    -- nothing useful to cast: Holy Strike (10 s) and Consecration (8 s) cooling, the seal up, Judgement off the GCD, Exorcism (879 ranks)
    -- unusable off Undead/Demon (the kit refuses; the harness world's missing creature-type check,
    -- paladin_world.lua:132, made it look castable); mana 70-92%, no gap-AB effect; reported, never gated (the gates
    -- sample L10/L40/L60).
    -- L40 8.4 keeps R28's cause: out of mana (86), nothing castable; the band L32 11.0
    -- (mana 13), L35-L40 8.4
    -- is the same cause, gated at L40 only; L41 and up 4.4 (Shieldsworn)
    -- pin move 2 on CN8 (steady icons on), measured: L10 8.6 -> 8.4 (the same cause: nothing useful to cast), L60 4.6
    -- (rank 4's 240 as above; the 6 s bar governs), L40 8.4 holds
    local PROT_LIVE60 = 4.6
    local PROT_LIVE40 = 8.4
    local PROT_LIVE10 = 8.4
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Protection (wowsims.com) stays live at level " .. level, function()
            local C = content("paladin_protection", PROT_LIVE, "Protection (wowsims.com)", level)
            local limit = level == 60 and math.max(6, PROT_LIVE60)
                or level == 40 and PROT_LIVE40
                or level == 10 and PROT_LIVE10
                or 6
            ws.live("Protection (wowsims.com)", C, limit)
        end)
    end
end)
