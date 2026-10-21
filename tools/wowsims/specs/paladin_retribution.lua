-- tools/wowsims/specs/paladin_retribution.lua (wowsims packs plan, Task 9): Retribution (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/paladin/retribution/presets.ts:32-34
-- (DefaultOptions), :37 (TwistOfLightTalents), :144-151 (OtherDefaults) at the pin; the APL and gear spec.ts's default
-- (Twist of Light).
-- Disagreements worked (P7, resume 3: after central fixes 6/8/C and 9/9b): replay 0.579 (57; 0.456 before them).
-- seal_of_righteousness -> seal_of_command 13 and consecration -> seal_of_command 3: replay limit (central GAP N,
-- tests/Game/harness/replay.lua): an aura the log removes early (a seal replaced, an Echo spent) is shown expiring at
-- its removal, so the client sees the prepull Seal of Command run out 1.5 s after its cast, Core's prepull_at rule
-- offers it again and the twist runs a seal behind (measured with the class duration shown instead: 0.772, both gone).
-- seal_of_command -> holy_strike 2: replay limit (central GAP O, tests/Game/harness/observer.lua): wowsims casts Holy
-- Strike the instant its cooldown ends; the old cooldown's end lands a microsecond after the new start and clears it
-- (with GAP N's experiment too: 0.789). The floor was 0.57 then; central fix 13 (removals shown as removals, the
-- cooldown restart) took it to 0.87, the spec's gate (tests/Forever/wowsims_paladin_spec.lua).
-- Under-belief of about 120 mana a Judgement: GAP H, an API-forced deviation: the class model prices its 6% on the
-- maximum (3737), wowsims on base mana (81 = 6% of 1500 x 0.9), which the client does not expose.
-- Idle at 60 (LIVE60 8.4 s, owner ruling): wowsims is the oracle; its own Retribution is out of mana from 60 s, and the
-- pack, run faithfully, spends itself dry the same way (4.4 s before central fix 8 kept the 10% lines from passing).
-- The Everlook Pathcarver (item 274759, a trinket wowsims's autocastOtherCooldowns uses at the pull) is `use_items`.
-- Leveling: the Seal of Righteousness refresh fills Holy Strike's cooldown before Seal of Command (L10 8.6 -> 4.4 s);
-- Seal of Command is kept up below Twist of Light (L40 6.4 s, under LIVE60's 8.4).
return {
    class = "PALADIN",
    pack = "Retribution (wowsims.com)",
    spec = "retribution",
    name = "Retribution",
    talentTree = "paladin",
    apl = "ui/specs/paladin/retribution/apls/twist_of_light.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassPaladin",
        gear = "ui/specs/paladin/retribution/gear_sets/twist_of_light.gear.json",
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
    leveling = {
        "seal_of_command,focus=2,if=!talent.twist_of_light.enabled&!buff.seal_of_command.up",
        "seal_of_righteousness,focus=2,if=!action.seal_of_command.known&buff.seal_of_righteousness.remains<24",
    },
}
