-- tools/wowsims/specs/paladin_retribution.lua (wowsims packs plan, Task 9): Retribution (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/paladin/retribution/presets.ts:32-34
-- (DefaultOptions), :37 (TwistOfLightTalents), :144-151 (OtherDefaults) at the pin; the APL and gear spec.ts's default
-- (Twist of Light), at d33930d040. The re-pin (e2842f0a78) deletes the Twist of Light files: the APL moves to
-- apls/default.apl.siml (presets.ts:17, :24 DefaultAplPreset, spec.ts:105; 1091 lines) and the gear to
-- gear_sets/default.gear.siml (presets.ts:19, :37 DefaultGearPreset, spec.ts:81).
-- Re-pin e2842f0a78 (Task 17, fresh floor): the build is presets.ts DefaultBuild 'Unsealed Wrath' (TypeSimple; its
-- simpleRotation writes the APL's own values, R29), talents 050250002-501-05233011201301351, 25 yd (OtherDefaults).
-- Omitted 1 -> 6 (dry run): the pre-pull Pull range move (spec §2.3), the Prep Seal groups and move3 (each gated on
-- `!Has assigned judgement`, constant false), two empty pre-pull groups. The owner's 2026-10-21 pre-pull ruling (no
-- twist, one starter seal) now holds by wowsims itself (Retribution Aura, then Seal of the Crusader), so
-- `prepullSkip` is gone. Disagreements (P7; floor 0.93): 0.933 (45) top [consecration -> seal_of_command 3]: a white
-- swing 0.02-0.05 s before completes an Echo; wowsims reads the stack with includeReactionTime (100 ms; the
-- translator ignores it, rule 5), so it casts Consecration first (log 17.40, 47.22, 77.04): a replay limit.
-- `requires` and the two `leveling` lines: kept until ruled (A/B, Task 17: removed, the replay and L10/L15/L40-L60
-- idle are unchanged; L20-L35 swap the seals every GCD, L20 92 presses against 34, but only because the leveling
-- world knows Seal of Command, a talent spell, without its point (ws.content filters the 60's spells by learn level
-- only), so both of wowsims's refresh lines pass; inconclusive there).
-- (History below: the old pin's Twist of Light APL.)
-- Disagreements worked (P7, resume 3: after central fixes 6/8/C and 9/9b): replay 0.579 (57; 0.456 before them).
-- seal_of_righteousness -> seal_of_command 13 and consecration -> seal_of_command 3: replay limit (central GAP N,
-- tests/Game/harness/replay.lua): an aura the log removes early (a seal replaced, an Echo spent) is shown expiring at
-- its removal, so the client sees the prepull Seal of Command run out 1.5 s after its cast, Core's prepull_at
-- rule (gone since central fix 23) offers it again and the twist runs a seal behind (measured with the class
-- duration shown instead: 0.772, both gone).
-- seal_of_command -> holy_strike 2: replay limit (central GAP O, tests/Game/harness/observer.lua): wowsims casts Holy
-- Strike the instant its cooldown ends; the old cooldown's end lands a microsecond after the new start and clears it
-- (with GAP N's experiment too: 0.789). The floor was 0.57 then; central fix 13 (removals shown as removals, the
-- cooldown restart) took it to 0.87, the spec's gate (tests/Forever/wowsims_paladin_spec.lua).
-- Under-belief of about 120 mana a Judgement: GAP H, an API-forced deviation: the class model prices its 6% on the
-- maximum (3737), wowsims on base mana (81 = 6% of 1500 x 0.9), which the client does not expose.
-- Idle at 60 (LIVE60 8.4 s, owner ruling; 5.2 measured at the R41 task, the limit is max(6, 5.2)): wowsims is the
-- oracle; its own Retribution is out of mana from 60 s, and the
-- pack, run faithfully, spends itself dry the same way (4.4 s before central fix 8 kept the 10% lines from passing).
-- The Everlook Pathcarver (item 274759, a trinket wowsims's autocastOtherCooldowns uses at the pull) is `use_items`.
-- Leveling (R41, owner policy: no filler for filling's sake; a line is a real ability cast for a genuine need).
-- Seal of Righteousness: not wowsims; need-based (R41): keep a seal up, recast when it is down or has less than two
-- GCDs left. Seal of Command's line is not wowsims either (its default Retribution plays no seal line without Twist of
-- Light: its 'Prep Seal' groups are gated on `Has assigned judgement`, a constant true; the twist lines are ours). Seal
-- of Command is recast below Twist of Light when it is down; Seal of Righteousness, before Seal of Command, when it is
-- down or has less than two GCDs left (`remains<gcd.max*2`: one competing GCD, Holy Strike, Consecration or Exorcism,
-- plus about half a second of reaction; Judgement is off the GCD). The kit's Judgement does not consume the seal
-- (judgementCast only refunds mana, Paladin.lua), so the 30 s seal persists and this threshold alone decides the recast.
-- The old `remains<24` refresh recast a seal with 24 s left only to fill the live gate's idle window (L10 8.6 -> 4.4;
-- a player report, R40). L10 idles 8.6 s now, a measured limit: nothing useful to cast: Holy Strike and Judgement
-- cooling, Seal of Righteousness up. L20-L35 6.8 s, nothing useful to cast:
-- Holy Strike (10 s) and Consecration (8 s) cooling, the seal up, Judgement off the GCD, Exorcism (879 ranks) unusable
-- off Undead/Demon (the kit refuses; the harness world's missing creature-type check, paladin_world.lua:132, made it
-- look castable); mana 70-92%, no gap-AB effect; reported, never gated (the gates sample L10/L40/L60).
-- Re-pin 4b0030a44b (0.7): APL and gear are upstream's .siml files (translated the same as the .json), the log re-exported at
-- the new pin; the pack lines are unchanged (SIML drops `rank` fields only).
return {
    class = "PALADIN",
    pack = "Retribution (wowsims.com)",
    spec = "retribution",
    name = "Retribution",
    talentTree = "paladin",
    apl = "ui/specs/paladin/retribution/apls/default.apl.siml",
    player = {
        race = "RaceHuman",
        class = "ClassPaladin",
        gear = "ui/specs/paladin/retribution/gear_sets/default.gear.siml",
        talentsString = "050250002-501-05233011201301351",
        specKey = "retributionPaladin",
        -- PaladinOptions is an empty message: an object, not dkjson's default empty array
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) },
        profession1 = "Engineering",
        profession2 = "Blacksmithing",
        reactionTimeMs = 100,
        distanceFromTarget = 25,
    },
    map = { ["item:274759"] = "use_items" }, -- the Everlook Pathcarver (ItemSparse 274759: a trinket, InventoryType 12)
    -- by role (docs/dev/wowsims-packs.md); the Twist of Light seals (1) open
    focus = { hammer_of_wrath = 1, seal_of_command = 1, seal_of_righteousness = 1, consecration = 2 },
    -- The Twist of Light lines need the talent (wowsims's Auto rotation picks this APL by it): without it they swap the
    -- seals every GCD (seen again at the re-pin in the L20-L35 worlds, which know Seal of Command without its talent).
    requires = { seal_of_command = "twist_of_light", seal_of_righteousness = "twist_of_light" },
    -- Not wowsims (no fight of its reaches it): the twist's kick-start. With Unsealed Wrath and Seal of Command,
    -- wowsims's Should refresh SoC needs an Echo of Righteousness and Should refresh SoR three Echoes of Command, so
    -- neither fires until one of the two seals is up; wowsims's opener (Move to melee) casts Seal of Command, but it
    -- runs only from out of Crusader Strike's range (its build pulls from 25 yd). A fight that starts in melee (or one
    -- whose first swing closes the opener before its seal, R16) would never cast either: the live loop idled 86 s
    -- from the Crusader seal's end. Seal of Command when neither is up, once the Crusader's Judgement is out (or no
    -- seal is up at all); a genuine need (no damage seal), R41. Silent while either seal is up.
    extra = {
        {
            before = "seal_of_command",
            -- the other abilities' reads guarded (rule 6, tools/check_pack_levels.lua): an unlearned Seal of
            -- Righteousness is not up, an unlearned Judgement never cooling
            line = "seal_of_command,if=talent.twist_of_light.enabled&talent.seal_of_command.enabled&!buff.seal_of_command.up"
                .. "&(!action.seal_of_righteousness.known|!buff.seal_of_righteousness.up)"
                .. "&(!seal_up|(action.judgement.known&cooldown.judgement.remains>0))",
        },
    },
    leveling = {
        "seal_of_command,focus=2,if=!talent.twist_of_light.enabled&!buff.seal_of_command.up",
        "seal_of_righteousness,focus=2,if=!action.seal_of_command.known&buff.seal_of_righteousness.remains<gcd.max*2",
    },
}
