-- tools/wowsims/specs/paladin_retribution.lua (wowsims packs plan, Task 9): Retribution (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/paladin/retribution/presets.ts:32-34
-- (DefaultOptions), :37 (TwistOfLightTalents), :144-151 (OtherDefaults) at the pin; the APL and gear spec.ts's default
-- (Twist of Light), at d33930d040. The re-pin (e2842f0a78) deletes the Twist of Light files: the APL moves to
-- apls/default.apl.json (presets.ts:17, :24 DefaultAplPreset, spec.ts:105; 1091 lines) and the gear to
-- gear_sets/default.gear.json (presets.ts:19, :37 DefaultGearPreset, spec.ts:81).
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
-- GCDs left. Both lines are not wowsims (its default Retribution plays no seal line without Twist of Light: its
-- 'Prep Seal' groups are
-- gated on `Has assigned judgement`, a constant true; the twist lines are ours); need-based: keep a seal up. Seal of
-- Command is recast below Twist of Light when it is down; Seal of Righteousness, before Seal of Command, when it is
-- down or has less than two GCDs left (`remains<gcd.max*2`: one competing GCD, Holy Strike, Consecration or Exorcism,
-- plus about half a second of reaction; Judgement is off the GCD). The kit's Judgement does not consume the seal
-- (judgementCast only refunds mana, Paladin.lua), so the 30 s seal persists and this threshold alone decides the recast.
-- The old `remains<24` refresh recast a seal with 24 s left only to fill the live gate's idle window (L10 8.6 -> 4.4;
-- a player report, R40). L10 idles 8.6 s now, a measured limit: nothing useful to cast: Holy Strike and Judgement
-- cooling, Seal of Righteousness up. L20-L35 6.8 s: ungated, not classified (Consecration off cooldown at the window's
-- end; not traced).
return {
    class = "PALADIN",
    pack = "Retribution (wowsims.com)",
    spec = "retribution",
    name = "Retribution",
    talentTree = "paladin",
    apl = "ui/specs/paladin/retribution/apls/default.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassPaladin",
        gear = "ui/specs/paladin/retribution/gear_sets/default.gear.json",
        talentsString = "55003003--05225331101330321",
        specKey = "retributionPaladin",
        -- PaladinOptions is an empty message: an object, not dkjson's default empty array
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) },
        profession1 = "Engineering",
        profession2 = "Blacksmithing",
        reactionTimeMs = 100,
        distanceFromTarget = 5,
    },
    map = { ["item:274759"] = "use_items" }, -- the Everlook Pathcarver (ItemSparse 274759: a trinket, InventoryType 12)
    -- by role (docs/dev/wowsims-packs.md); the Twist of Light seals (1) open
    focus = { hammer_of_wrath = 1, seal_of_command = 1, seal_of_righteousness = 1, consecration = 2 },
    -- The Twist of Light lines need the talent (wowsims's Auto rotation picks this APL by it): without it they swap the
    -- seals every GCD.
    requires = { seal_of_command = "twist_of_light", seal_of_righteousness = "twist_of_light" },
    -- Owner ruling (2026-10-21): the pre-pull must not twist; one starter seal, Seal of the Crusader. wowsims's -3 s
    -- Seal of Command (the twist's first half) is omitted.
    prepullSkip = { "seal_of_command" },
    leveling = {
        "seal_of_command,focus=2,if=!talent.twist_of_light.enabled&!buff.seal_of_command.up",
        "seal_of_righteousness,focus=2,if=!action.seal_of_command.known&buff.seal_of_righteousness.remains<gcd.max*2",
    },
}
