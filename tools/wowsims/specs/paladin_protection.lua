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
--   Shield's price: ours 240 (DB2 70707) vs wowsims's 195 (both pins), kit unchanged; the log's mana just before the six
--   Holy Shield misses is 224.67, 223.71, 275.24, 196.22, 213.65, 238.48 (the other two misses are Seal of Fury's), five
--   of six under 240: the price is a necessary cause in 5 of the 8 (gaps.md CU).
--   Fixed: Holy Shield's block hits {20928, Tag 2}, Shieldsworn's {20928, Tag 1328544} and Retribution Aura's {10301,
--   Tag 2} were replayed as our casts and restarted Holy Shield's believed cooldown (0.788 -> 0.846, wowsims_paladin_spec
--   PROT_REPLAY procs).
-- Regen: Paladin.lua's seeds and tests/Forever/helpers/paladin_world.lua's `fsr = { 17.38, 0 }` were not refreshed to this
-- log's 17.3 / 0.8 (within tolerance; lanes 10/11 precedent).
-- Leveling (R28): the Seal of Fury refresh fills Holy Strike's 10 s cooldown below Shieldsworn and Holy Shield (L10
-- 8.6 -> 4.4 s; the loop world's Protection has the preset's Shieldsworn, so it is silent at 60). L40 idles 8.4 s out
-- of mana (79): nothing castable, and a filler would spend mana the character lacks (10.6 s with the refresh, hence
-- its Holy Shield guard); a measured per-bracket limit, owner FYI. R28a ratifies that guard `!talent.holy_shield.enabled`:
-- the exception is a band, L32-L40 (Holy Shield learned, Shieldsworn not, mana-dry), all idle over 6 s either way (L32
-- 11.0, L35-L40 8.4); gated at L40 only, and no other bracket got a higher limit.
return {
    class = "PALADIN",
    pack = "Protection (wowsims.com)",
    spec = "protection",
    name = "Protection",
    talentTree = "paladin",
    apl = "ui/specs/paladin/protection/apls/default.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassPaladin",
        gear = "ui/specs/paladin/protection/gear_sets/default.gear.json",
        talentsString = "050050002-05302102213301531-502",
        specKey = "protectionPaladin",
        -- PaladinOptions is an empty message: an object, not dkjson's default empty array
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) },
        profession1 = "Engineering",
        profession2 = "Enchanting",
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
    map = { [25903] = "holy_shock" }, -- Holy Shock rank 4's hostile spell (wowdb: 25903, range 40); the kit's 20930
    focus = { seal_of_fury = 2, holy_shield = 2 },
    leveling = {
        "seal_of_fury,focus=2,if=!talent.shieldsworn.enabled&!talent.holy_shield.enabled&buff.seal_of_fury.remains<24",
    },
}
