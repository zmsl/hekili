-- tests/Forever/wowsims_warrior_spec.lua (wowsims packs plan, Tasks 5-6): the Warrior wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log; wowsims/forever (MIT, https://github.com/wowsims/forever))
-- and at three levels.
local ws = require("Forever.helpers.wowsims")
local ww = require("Forever.helpers.warrior_world")
local loop = require("Game.harness.loop")
local replay = require("Game.harness.replay")

local function content(spec, base, pack, level, extra)
    local o = {
        pack = pack,
        level = level,
        talents = ws.header(spec).talents,
        learn = ws.learn("WARRIOR"),
        race = ws.race(spec),
    }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

-- Forever's Overpower window (aura 1282733, 5 s): wowsims's Overpower condition; the client cannot list it, so the
-- replay keeps it in the truth (`hidden`) and answers Overpower's usability from it.
local ARMS = {
    kit = { "spearing_strike", "berserker_rage" },
    requires = {
        overpower = function(_, e)
            return e.auras[1282733] ~= nil and e.form == 1, "no window"
        end,
    },
}
local ARMS_REPLAY = { hidden = { [1282733] = true }, procs = {} }
-- The replay's character wields the wowsims build's main hand (p1_arms: Arcanite Reaper, 12784, ItemDelay 3800 in the
-- Forever DB2), so the client's swing speed is the log's swings' 3.8 s, not the loop world's 3.6 s weapon.
local ARMS_CHAR = setmetatable({
    character = function()
        local c = ww.character()
        c.speed = { 3.8 }
        return c
    end,
}, { __index = ww })

-- Fury: the same Overpower window (its Overpower Weaving group reads 1282733); Berserker Rage is a trained ability the
-- loop kit lacks. The base is the dual-wield world (ww.Fury), the log's own weapon speeds.
local FURY = { kit = { "berserker_rage", "reckless_swings" }, requires = ARMS.requires }
-- Whirlwind's off-hand hit (1680 Tag 15, the off hand's item slot) is logged as its own Casting line: a hit of the one cast, not a decision.
-- wowsims logs the Heroic Strike queue (25286 Tag 1) as an aura the client never shows (the client sees
-- IsCurrentSpell): hidden.
-- Every rank's queue, so a build casting a lower rank (R30) hides it too.
local HEROIC_STRIKE_RANKS = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }
local function hideQueue(hidden)
    for _, id in ipairs(HEROIC_STRIKE_RANKS) do
        hidden[id] = true
    end
    return hidden
end
local FURY_REPLAY = { hidden = hideQueue({ [1282733] = true }), procs = { ["1680:15"] = true }, speed = 2.1 }

-- Protection: wowsims's Revenge window is an aura it logged under Revenge's own ID (25288) before e2842f0a78, and logs
-- as the DB2's Defensive State 5302 since (5 s, from a block, dodge or parry of the target's swing). The replay does not replay the target's swings, so the
-- window stays in the truth (`hidden`) and answers Revenge's usability; the live world's mob swings at us, so there
-- Revenge keeps the world's own requirement. The Heroic Strike queue (25286 Tag 1) as Fury's. Shield Slam is the talent's
-- rank 1 plus its trained ranks (the log casts rank 4, 23925).
local PROT_KIT =
    { "berserker_rage", "retaliation", "revenge", "shield_block", "shield_slam", "shield_wall", "shield_bash", "taunt" }
local PROT = {
    kit = PROT_KIT,
    requires = {
        revenge = function(_, e)
            return (e.auras[5302] ~= nil or e.auras[25288] ~= nil) and e.form == 2, "no window"
        end,
    },
}
local PROT_REPLAY = { hidden = hideQueue({ [5302] = true, [25288] = true }), procs = {}, speed = 2.35 }

describe("the Warrior wowsims.com packs #slow #wowsims", function()
    it("Arms (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Arms (wowsims.com)",
            content("warrior_arms", ARMS_CHAR, "Arms (wowsims.com)", 60, ARMS),
            "warrior_arms",
            -- measured 0.896: 0.910 after central fixes 7, 13 and 16 (was 0.86, provisional), less the pre-pull Berserker
            -- Rage wowsims casts at -4.5 without Improved Berserker Rage (the build has none), which the user's ruling
            -- (2026-10-21) gates on that talent (berserker_rage -> battle_shout, 1 of 67); 0.881 (59 of 67) with the world's
            -- parry haste (decision 63): the same-frame Bloodrage gap (gaps.md, fix 40); 0.896 (60 of 67) with fix 40.
            -- Re-pin e2842f0a78 (lane 14, R6): 0.917 (66 of 72; base 0.943, inside max(0.02, 2/72)); the recipe header
            -- names each disagreement
            -- Re-pin 4b0030a44b/e5a9cd2a2d (0.7 warrior lane, R6): 0.88 (62 of 70; measured 0.886 under steady icons) from 0.91: the
            -- ruled berserker_rage gate (1), Overpower weaves (overpower -> rend 9.55 and 92.45, -> sunder 65.85, -> slam 101.55:
            -- the usability answer's delay after a dodge), spearing_strike -> mortal_strike (50.65, 100.05) and mortal_strike
            -- slam (131.95) at the cooldown's edge
            0.88,
            ARMS_REPLAY
        )
    end)
    -- the replay's world is the log's: loop.run presses nothing of ours (Task 3's loop_spec check runs on a stub pack)
    it("Arms (wowsims.com)'s replay presses nothing", function()
        local C = content("warrior_arms", ARMS_CHAR, "Arms (wowsims.com)", 60, ARMS)
        local L = loop.new(C)
        local R = replay.new(ws.log("warrior_arms"), L.oracle, ws.replayOptions(C, "warrior_arms", ARMS_REPLAY))
        local run = loop.run(L, 1, { replay = R, trace = false }, { { H = L.us } })
        assert.are.equal(0, run.presses)
        assert.is_true(#run.dec.ours > 40, "decisions scored")
    end)
    -- The pack's own worst idle per bracket (R7; R22a: L10 and L40 keep the 6 s bar unless a measured limit names its
    -- cause; R41, owner 2026-11-05: an idle with nothing useful to cast is correct and gets a measured limit, never a
    -- filler). L60: wowsims's pooling, 9.2 after fixes 7, 13 and 16, 5.0 measured with R41 (the shared max(6, LIVE60)
    -- lifted L10 and L40 to 9.2 before). L10 7.4 and L40 12.8 since R41 removed the leveling Hamstring (5.6 / 5.6 with
    -- it; 9.0 / 11.2 before it): nothing useful to cast before Mortal Strike's talent: L10 Rend, Thunder Clap and five
    -- Sunders up, the rage going to the off-GCD Heroic Strike; L40 the same with Slam and Spearing Strike cooling.
    -- Re-pin e2842f0a78 (lane 14): 7.4 / 8.6 / 5.6 measured; L40 12.8 -> 8.6 (R6, R41: 37.4-45.4 s, Slam 8.5 s and
    -- Spearing Strike cooling, Rend up 8.1 s, five Sunders up, rage 12-28 pooling to the off-GCD Heroic Strike: nothing
    -- useful to cast); L10 and L60 stay
    -- Re-pin 4b0030a44b (R6, R41): L40 10.0 from 8.6 (measured 14.0 before the v0.6.2 melee-range
    -- fix merged: Heroic Strike now hides out of melee): Slam's cooldown is now 15 s (no Improved Slam at L40) and Mortal Strike is
    -- not learned. Traced (seed 1, 38.2-48.2 s): the only on-GCD ability the world would accept was Rend (772), whose debuff is
    -- up, so the pack correctly does not recast it: nothing useful to cast (R41)
    local ARMS_LIVE = { [10] = 7.4, [40] = 10.0, [60] = 6 } -- 7.4 / 10.0 / 6.0
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Arms (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Arms (wowsims.com)",
                content("warrior_arms", ww, "Arms (wowsims.com)", level, ARMS),
                ARMS_LIVE[level]
            )
        end)
    end
    it("Fury (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Fury (wowsims.com)",
            content("warrior_fury", ww.Fury, "Fury (wowsims.com)", 60, FURY),
            "warrior_fury",
            -- measured 0.917: 0.933 after central fixes 7, 13 and 16 (was 0.81 with GAP AD), less the pre-pull Berserker
            -- Rage the user's ruling (2026-10-21) gates on Improved Berserker Rage, which the build lacks (1 of 60);
            -- 0.897 (61 of 68) after the harness corrected to the measured swing timing (2026-10-22): the log's swings
            -- take health at the swing, so the execute phase opens a landing lag earlier than the rows show it; 0.926 (68)
            -- with the world's parry haste (decision 63). Re-pin e2842f0a78 (lane 14, R6): 0.851 (74 of 87; base 0.922):
            -- owner R46 accepts it: the belief holds an avoid on our own swing provisional until the swing ticket closes
            -- (1.5 s main hand, 2.0 s off hand: Events/Rows.lua, Events/Melee.lua L.PAIR_WINDOW_MS), so the dodge row the
            -- Overpower Weaving swap reads (enemy_dodged) reaches the kit 1.57-2.17 s late, after wowsims has swapped and
            -- cast (0.1-1.1 s after the dodge): the top misses are overpower -> bloodthirst / whirlwind / execute (3, 3, 2)
            -- Re-pin 4b0030a44b/e5a9cd2a2d (R6): 0.86 (86 of 99; measured 0.869) from 0.85: Overpower weaves (the R46 latency, and
            -- the stance keep fixed to 25: 4 overpower -> bloodthirst), 3 Reckless Swings (the 20-rage shortcut moves the belief's
            -- rage, blocker note warrior-1), execute -> death_wish, execute -> reckless_swings
            0.86,
            FURY_REPLAY
        )
    end)
    -- The pack's own worst idle per bracket (R7, R22a, R41 as Arms's). L60 6.8: wowsims's pooling, after fix 16 (8.2
    -- with GAP AD's Intercept). Below Bloodthirst nothing useful to cast: L10 7.6 (Battle Stance: Rend up, five Sunders
    -- up, the rage pooling for the off-GCD Heroic Strike; the world's off hand by rank moved it from 7.4); L40 8.4 since
    -- R41 removed the leveling Hamstring (2.4 with it): Berserker Stance (no Rend or Overpower), Whirlwind cooling, five
    -- Sunders up, the rage going to Heroic Strike
    -- Re-pin e2842f0a78 (lane 14, R41 measured limits; the build's new talents): L10 10.4 (28.4-38.8 s: Rend up, its
    -- refresh 10 -> 0.8 s out, five Sunders up, Battle Shout up, the rage to the off-GCD Heroic Strike); L60 8.6 (24.0-32.4 s:
    -- Bloodthirst 3.9 s and Whirlwind 8.4 s cooling, Death Wish not in the queue, five Sunders up, rage 3-28 pooling
    -- for Bloodthirst: wowsims's pooling). L40 8.4 unchanged.
    local FURY_LIVE = { [10] = 10.4, [40] = 8.4, [60] = 8.6 } -- 10.4 / 8.4 / 8.6
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Fury (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Fury (wowsims.com)",
                content("warrior_fury", ww.Fury, "Fury (wowsims.com)", level, FURY),
                FURY_LIVE[level]
            )
        end)
    end
    -- Central fix 18 (in game, level 30 beta: no Mortal Strike or Bloodthirst before 40): the leveling Sunder line
    -- fired at 5 stacks. Below 40, with ours driving on the secret client (target auras raise in combat), the first
    -- icon is never Sunder while the target's true 5 stacks have more than 15 s left (past any wait the queue shows)
    -- and the fifth is older than one tick (the cast's frame, before its success folds in).
    for _, case in ipairs({
        { "warrior_arms", ww, "Arms (wowsims.com)", ARMS },
        { "warrior_fury", ww.Fury, "Fury (wowsims.com)", FURY },
    }) do
        it(case[3] .. " stops Sunder Armor at 5 stacks at level 30", function()
            local L = loop.new(content(case[1], case[2], case[3], 30, case[4]))
            local H = L.us
            local id = H.Hekili.Class.auras.sunder_armor.id
            local at5, five, raised = {}, 0, 0
            loop.run(L, 1, {
                duration = 120,
                on = function(run, steps, t)
                    if H.ctl.auraError.target then
                        raised = raised
                            + (pcall(H.api.C_UnitAuras.GetAuraDataByIndex, "target", 1, "HARMFUL") and 0 or 1)
                    end
                    -- a killed target's stacks are no client's: the kill clears `target` (2026-10-22 kill capture)
                    local a = not run.W.killAt and run.us.target and run.us.target.auras[id]
                    local left = a and a.stacks == 5 and a.expires - t or 0
                    if left > 15 and left < 30 - loop.TICK then
                        five = five + 1
                        if steps[1].q.name[1] == "sunder_armor" then
                            at5[#at5 + 1] = ("%.1f"):format(t)
                        end
                    end
                end,
            }, { { H = H } })
            assert.is_true(raised > 0 and five > 0, raised .. " raised reads, " .. five .. " ticks at 5")
            assert.are.same({}, at5)
        end)
    end
    -- R30 (owner, 2026-11-05): every rank of an ability is that ability in the replay's comparison, whatever rank
    -- wowsims casts (its builds may remap Heroic Strike 25286 -> 11567 and Battle Shout 25289 -> 11551: an era choice,
    -- not ours; no spell-id remap). The rank lists are the Forever DB2's (wowdb 70707 `spell <name>`, the WARRIOR rows;
    -- Execute's 20647 is its triggered damage spell, learned at no level, so not a rank).
    local RANKS = {
        battle_shout = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 },
        bloodthirst = { 23881, 23892, 23893, 23894 },
        charge = { 100, 6178, 11578 },
        cleave = { 845, 7369, 11608, 11609, 20569 },
        demoralizing_shout = { 1160, 6190, 11554, 11555, 11556 },
        execute = { 5308, 20658, 20660, 20661, 20662 },
        hamstring = { 1715, 7372, 7373 },
        heroic_strike = HEROIC_STRIKE_RANKS,
        intercept = { 20252, 20616, 20617 },
        mocking_blow = { 694, 7400, 7402, 20559, 20560 },
        mortal_strike = { 12294, 21551, 21552, 21553 },
        overpower = { 7384, 7887, 11584, 11585 },
        pummel = { 6552, 6554 },
        rend = { 772, 6546, 6547, 6548, 11572, 11573, 11574 },
        revenge = { 6572, 6574, 7379, 11600, 11601, 25288 },
        shield_bash = { 72, 1671, 1672 },
        shield_slam = { 23922, 23923, 23924, 23925 },
        slam = { 1240193, 1464, 8820, 11604, 11605 },
        sunder_armor = { 7386, 7405, 8380, 11596, 11597 },
        thunder_clap = { 6343, 8198, 8204, 8205, 11580, 11581 },
    }
    local HEAD = "# wowsims e2842f0a784d2f329dde0bc682a6b84202a780f2 warrior_protection seed 1 180 s target 63\n"
    local CAST = "[%.2f] [Protection (#1)] Casting {SpellID: %d} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, "
        .. "Effective Time = 1.5s) APL: priority 1\n[%.2f] [Protection (#1)] Completed cast {SpellID: %d}\n"
    it("scores every rank of a Warrior ability as that ability (R30)", function()
        local C = content("warrior_protection", ww.Protection, "Protection (wowsims.com)", 60, PROT)
        local L = loop.new(C)
        local keys, want, text = {}, {}, { HEAD }
        for key in pairs(RANKS) do
            keys[#keys + 1] = key
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            for _, id in ipairs(RANKS[key]) do
                local t = 2 * #want
                text[#text + 1] = CAST:format(t, id, t, id)
                want[#want + 1] = key .. " " .. id
            end
        end
        local R = replay.new(table.concat(text), L.oracle, ws.replayOptions(C, "warrior_protection", PROT_REPLAY))
        local got = {}
        for i, d in ipairs(R.decisions) do
            got[i] = d.key .. " " .. want[i]:match("%d+$")
        end
        assert.are.same(want, got)
    end)
    -- and the feed: the Fury log with wowsims's build ranks (25286 -> 11567, 25289 -> 11551 in every line) gives the
    -- same decisions, keyed the same; the replay knobs list every rank (hideQueue: the Heroic Strike queue aura)
    it("replays the Fury log the same with the build's lower ranks (R30)", function()
        local C = content("warrior_fury", ww.Fury, "Fury (wowsims.com)", 60, FURY)
        local L = loop.new(C)
        local o = ws.replayOptions(C, "warrior_fury", FURY_REPLAY)
        local text = ws.log("warrior_fury")
        local low = text:gsub("SpellID: 25286([,}])", "SpellID: 11567%1")
            :gsub("SpellID: 25289([,}])", "SpellID: 11551%1")
        assert.are_not.equal(text, low)
        local a, b = replay.new(text, L.oracle, o), replay.new(low, L.oracle, o)
        local function keys(R)
            local out = {}
            for i, d in ipairs(R.decisions) do
                out[i] = ("%.3f %s"):format(d.t, d.key)
            end
            return out
        end
        assert.are.same(keys(a), keys(b))
        assert.is_true(#a.decisions > 40)
    end)
    it("Protection (wowsims.com) follows wowsims's casts", function()
        ws.gate(
            "Protection (wowsims.com)",
            content("warrior_protection", ww.Protection, "Protection (wowsims.com)", 60, PROT),
            "warrior_protection",
            -- measured 0.904 (94); 0.979 once the replay ends a cooldown at its log timestamp (ready-time ruling), held with
            -- partial blocks replayed as BLOCK_REDUCED wounds (gap AH); 0.97 -> 0.93 (0.938, 91 of 97, after gap AS's
            -- Rend give-back): W2's fight exposes exact-1.5 s Shield Slam ties (sim artifact; reverting upstream #755
            -- alone gives 0.989); 0.93 -> 0.98 (0.9898, 97 of 98) re-pin e2842f0a78 (Task 14): the new talents
            -- (presets.ts ProtectionTalents) and gear; the Revenge window's id 5302 mapped (recipe `auras`); the one
            -- miss is shatter_curse -> shield_slam (45.03: the Orc racial at <= 50% health; the replay does not replay our
            -- health, the old class)
            -- Re-pin 4b0030a44b/e5a9cd2a2d (R6): 0.92 (92 of 100; measured 0.920) from 0.98: the new rotation (Revenge reorder, Retaliation
            -- precombat) leaves Shield Slam ties at the cooldown's edge (sunder_armor -> shield_slam x2, rend -> shield_slam),
            -- shatter_curse -> revenge (our health is not replayed: the old class), shield_slam -> thunder_clap 5.50
            0.92,
            PROT_REPLAY
        )
    end)
    -- the pack's own worst idle by level over seeds 1-20, 120 s (gap CK, 2026-10-31; was 5.4 at 60 and 40 from one
    -- seed): L60 median 11.8 worst 17.2, L40 11.8 / 19.0; L10 7.8 / 10.4 in those 120 s fights while this check's own
    -- fight reads 5.6, so 10 keeps the 6 s floor. The world pays rage for our white swings only (wowsims's Protection log earns 55% of its rage
    -- from damage taken, 20% from white swings) and raises no block for Shield Block (no `us.taking`), so the character
    -- pools at 7-10 rage through runs of avoided swings while the APL waits on Shield Slam (Rend and Sunder gated on its
    -- cooldown). 5.4 was measured while Revenge's window never reached the client (review C1), which held the APL in
    -- the Shield Block fishing branch. A world fix (gap CK) tightens these again. Re-pin e2842f0a78 (lane 14, the new
    -- talents; the pack's lines unchanged): this check's fight 6.0 / 17.2 / 17.2 (was 6.0 / 10.2 / 14.6), L60 at its
    -- limit; re-traced (95-112 s): rage 0.9-9.1, Rend, Shield Block and Sunder waiting on rage: rage-starved, gap CK's
    -- cause. The seeds 1-20 sweep behind 19.0 / 17.2 predates the new export (not re-run)
    -- L40 19.0 -> 21.8, L60 17.2 -> 21.8 (CN8 D2; this check's fight, seed 1): the same rage-starved stretch (95-116.6 s,
    -- rage 4-7, Shield Block and Sunder waiting on rage, only Shield Wall usable), 4.6 s longer on the re-timed fight
    -- 0.7 warrior lane (R6): CN8's steady-icons limits 21.8 at L40/L60 kept; this check's fight measures 10.2 / 14.6 at the new pin; the
    -- seeds 1-20 stretch the cause names is rage-starved (gap CK: rage 0.9-9, only Shield Wall usable), not re-swept here
    -- Release fix (batch review B S5): 21.8 -> 10.2 (L40) / 14.6 (L60), the worst idle this check measures (seed 1) at the new pin; the older
    -- 21.8 was the re-timed fight under CN8 D2 and no longer happens, so the limit follows the measurement (a larger idle fails)
    local PROT_LIVE = { [10] = 6, [40] = 10.2, [60] = 14.6 }
    for _, level in ipairs({ 10, 40, 60 }) do
        it("Protection (wowsims.com) stays live at level " .. level, function()
            ws.live(
                "Protection (wowsims.com)",
                content("warrior_protection", ww.Protection, "Protection (wowsims.com)", level, { kit = PROT_KIT }),
                PROT_LIVE[level]
            )
        end)
    end
end)
