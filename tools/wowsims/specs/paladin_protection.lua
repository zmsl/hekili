-- tools/wowsims/specs/paladin_protection.lua (wowsims packs plan, Task 9): Protection (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/paladin/protection/presets.ts:23
-- (DefaultTalents), :25-27 (DefaultOptions), :86-98 (OtherDefaults) at the pin; the APL and gear spec.ts's default.
-- Disagreements worked (P7, resume 3: after central fixes 6/8/C and 9/9b): replay 0.750 (28; wowsims's own Protection
-- is out of mana from 24 s, so few decisions) on an export with no tank, so the target never swung (GAP AE, central fix
-- 13: re-exported as the tank, 0.583 (48), the hits' and blocks' mana returns unmodelled; the notes below are the
-- untanked fight's). The tanked log carries {SpellID: 20423, Tag: 1}, a stacking counter wowsims logs beside the seal
-- 20423 and fades each few seconds; the replay drops such tagged lines (replay.lua), or the seal would vanish with it. 0.679 on the rebase alone (fix 6/8/C report: the replay's client now
-- reads the log's 2597 maximum); back to 0.750 once wowsims's character is booted with that maximum too, so the class
-- file prices Righteous Fury's 30% on it (on 6000, its short answers capped the belief at 779 under a true 1568).
-- holy_strike -> false 4 and seal_of_fury -> holy_strike 3: GAP R (central fix 12;
-- src/Hekili/Engine/Sim/State.lua): in combat the engine forecasts mana at GetManaRegen's in-five-second-rule rate
-- (this build's mp5 is 0) and never the spirit part after the window, so a spell short by a few mana is never shown
-- with a wait (measured with the window-aware rate: 0.964). The floor stays 0.75. [The OLD pin's state, see the re-pin
-- below:] Holy Shock is unconditional: the APL's Consecrated Ground (1310905) is never on the target (wowsims logs Consecration's 1280353), as in wowsims; the
-- build takes no Holy Shock. Lost to autocastOtherCooldowns (not translated): nothing cast.
-- Re-pin e2842f0a78 (Task 12; floor 0.62 -> 0.84): talents presets.ts DefaultTalents 050050002-05302102213301531-502
-- (was 50003-0530313321301531-5022; by spell ID: Improved Seals 3 -> 5, + Toughness 2, + Shieldsworn 1), the pin's
-- default gear, Human, no buffs in the request (R25 does not apply), executeProportion25/45/90 dropped; the log's
-- maximum is 2627 (was 2597) and its regen 1.73 / 0.08 a tick (was 1.738 / none). Omitted 2 -> 2. The APL now opens
-- with the Righteous Fury pre-pull (-20 s); Swift Judgement reads spellFullCooldown (`cooldown.judgement.duration`;
-- wowsims's inputDelay is 0 here, so the line holds whenever Judgement is known: deviation, off-GCD only); Holy Shock
-- reads talentIsKnown(1310905) as `talent.consecrated_ground.enabled` (the kit's talent, tree 0). The APL holds no
-- `wait` or `waitUntil` at the pin (dry: waitUntil 0), so there is nothing to carry (spec §3 names Protection: premise
-- void). Decisions on-GCD 0.846 (52) top [holy_shield -> holy_strike 6; seal_of_fury -> holy_strike 2] (log times):
--   holy_shield -> holy_strike (34.04, 45.00, 88.04, 103.90, 128.04, 163.00) and seal_of_fury -> holy_strike (108.04,
--   172.04): the belief is under the truth (lo 119-208) at each. Cause (Task 12 review): wowsims restores mana on
--   every LANDED Shieldsworn Holy Strike (talents_protection.go:161-170, ProcChance 100 at rank 2): all 26 landed Holy
--   Strikes give 105.08 mana tagged 1328544 (none on the miss at 31.50 or the dodges at 80.50, 173.54), unmodelled by the
--   kit (gaps.md CU). 45.00 (return 43.50), 103.90 (return 98.50, 5.4 s earlier) and 163.00 (return 161.50) follow such a
--   return, not a block (a block returns on every block, 3 s cooldown: Shield Specialization 1310925, unseen). Holy
--   Shield's price (before R31): ours 240 (DB2 70707) vs wowsims's 195 (both pins), kit unchanged; the log's mana just before the six
--   Holy Shield misses is 224.67, 223.71, 275.24, 196.22, 213.65, 238.48 (the other two misses are Seal of Fury's), five
--   of six under 240: the price is a necessary cause in 5 of the 8 (gaps.md CU).
--   [Superseded 2026-11-06, owner's tooltips (L15): Holy Shield has FOUR ranks, 100/150/195/240 mana at levels 30/40/50/60.]
--   R31 (owner fact): Holy Shield's max rank is 3 and costs 195; DB2 70707 carries the Era ladder one rank up (20925/
--   20927/20928 at levels 40/50/60, 150/195/240; wowsims 30/40/50, 100/150/195), so the kit's rank 3 is 195 now (ranks
--   1-2 and the learn levels stay the DB2's, owner item gaps.md CV). Replay 0.846 -> 0.885 (52), floor 0.84 -> 0.88;
--   45.00 and 163.00 agree. The 6 left (Holy Shield 34.04, 88.04, 103.90, 128.04; Seal of Fury 108.04, 172.04) have
--   the truth over the cost and the belief's lo under it (lo 119 / 161 / 171 / 22 / 162 / 23 vs truth 225 / 275 /
--   196 / 214 / 300 / 256): the unmodelled Shieldsworn Holy Strike return (gaps.md CU). Live L60 4.6 -> 4.4.
--   Fixed: Holy Shield's block hits {20928, Tag 2}, Shieldsworn's {20928, Tag 1328544} and Retribution Aura's {10301,
--   Tag 2} were replayed as our casts and restarted Holy Shield's believed cooldown (0.788 -> 0.846, wowsims_paladin_spec
--   PROT_REPLAY procs).
-- Regen: Paladin.lua's seeds and tests/Forever/helpers/paladin_world.lua's `fsr = { 17.38, 0 }` were not refreshed to this
-- log's 17.3 / 0.8 (within tolerance; lanes 10/11 precedent).
-- Leveling (R41, owner policy, supersedes R28's L10 filler and R28a's `!talent.holy_shield.enabled` guard): no leveling
-- line. The old Seal of Fury refresh (`remains<24`) recast a seal with 24 s left only to fill Holy Strike's cooldown
-- for the live gate (L10 8.6 -> 4.4; a player report, R40); wowsims's own Seal of Fury line re-seals when the seal is
-- down. Live idle, measured limits with the named cause: L10 8.6 s, nothing useful to cast: Holy Strike and Judgement
-- cooling, Seal of Fury and Righteous Fury up (L15 the same). L20-L25 6.4 s, nothing useful to cast: Holy Strike (10 s)
-- and Consecration (8 s) cooling, the seal up, Judgement off the GCD, Exorcism (879 ranks) unusable off Undead/Demon
-- (the kit refuses; the harness world's missing creature-type check, paladin_world.lua:132, made it look castable);
-- mana 70-92%, no gap-AB effect; reported, never gated (the gates sample L10/L40/L60). L40 8.4 s (R28): out of mana
-- (86), nothing castable; the band L32 11.0, L35-L40 8.4 has the same cause, gated at L40 only; L41 on 4.4
-- (Shieldsworn's Holy Strike every 6 s).
-- Re-pin 4b0030a44b (0.7): APL and gear are upstream's .siml files (translated the same as the .json), the log re-exported at
-- the new pin; Holy Shield now casts rank 4 (1239570, 240 mana: R31 retired, owner tooltips 100/150/195/240) and the replay world no longer drops it (L120).
return {
    class = "PALADIN",
    pack = "Protection (wowsims.com)",
    spec = "protection",
    name = "Protection",
    talentTree = "paladin",
    apl = "ui/specs/paladin/protection/apls/default.apl.siml",
    player = {
        race = "RaceHuman",
        class = "ClassPaladin",
        gear = "ui/specs/paladin/protection/gear_sets/default.gear.siml",
        talentsString = "050050002-05302102213301531-502",
        specKey = "protectionPaladin",
        -- PaladinOptions is an empty message: an object, not dkjson's default empty array
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) },
        profession1 = "Engineering",
        profession2 = "Enchanting",
        reactionTimeMs = 100, -- defaults.siml: reaction_time 100ms, in_front_of_target
        inFrontOfTarget = true,
        distanceFromTarget = 5,
    },
    -- a tank: the raid's tank (the target swings at it) and presets.ts:92-99's healing model (apply_defaults.ts:108-122)
    tank = true,
    healingModel = {
        hps = 2200,
        cadenceSeconds = 0.4,
        cadenceVariation = 1.2,
        absorbFrac = 0.02,
        burstWindow = 6,
        inspirationUptime = 0.25,
    },
    -- 25903: Holy Shock rank 4's hostile spell (wowdb: 25903, range 40), the kit's 20930; 1311015: Templar's Bulwark, the
    -- major cooldown wowsims's autocastOtherCooldowns casts at the pull (log line 223: 110 mana, off the GCD)
    map = { [25903] = "holy_shock", [1311015] = "templars_bulwark" },
    focus = { seal_of_fury = 2, holy_shield = 2 },
    leveling = {},
}
