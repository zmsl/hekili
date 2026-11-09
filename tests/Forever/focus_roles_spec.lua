-- tests/Forever/focus_roles_spec.lua: the focus tiers by a line's role (user ruling 2026-10-21,
-- docs/dev/wowsims-packs.md `focus`): rotational strikes, cooldowns and pre-pull lines untiered, reactive or windowed lines at 1 (the Warrior
-- rage dumps always 2, owner ruling 2026-10-22), upkeep at 2. Every generated pack but the Warrior's (their own audit): its flagged lines in file
-- order. Arguable lines keep their earlier tier until the user rules (named in the comments).
local function flagged(path)
    local out = {}
    for line in io.lines(path) do
        local action, tier = line:match("^actions[%w_.]*%+?=/?([%w_]+)[^\n]-,focus=(%d+)")
        if action then
            out[#out + 1] = action .. "=" .. tier
        end
    end
    return out
end

local ROGUE = { "garrote=1", "rupture=1", "slice_and_dice=1" } -- Slice and Dice and Rupture sort by soonest (Rupture first since the re-pin)
-- the melee-weave strikes (Mongoose Bite, Strider Kick, Immolation Trap, Wing Clip) rotational (the user)
-- (R51: each move arm is its own line where its move is called, at its source line's tier: the re-pin's Hunter's Mark
-- leads, Raptor Strike's and Serpent Sting's in-range lines, then the arms: Beast Mastery and Survival walk in (walk_in
-- #1 reaches Serpent Sting) before the weave (#6: Raptor Strike; #7, the move back: Serpent Sting); Marksmanship's walk
-- in is never called)
local HUNTER = {
    "hunters_mark=2",
    "raptor_strike=1",
    "serpent_sting=1",
    "serpent_sting=1",
    "serpent_sting=1",
    "raptor_strike=1",
}
-- 0.7 re-pin: the weave is move #4 (the shots' move back) then #5 (the strikes), so the strike line comes last
local HUNTER_MM = { "hunters_mark=2", "raptor_strike=1", "serpent_sting=1", "serpent_sting=1", "raptor_strike=1" }

-- file order of the generated simc: the Banes, Searing Pain's Demonic Brand upkeep and the curses at 2, Soul Fire on Decimation at 1
local WARLOCK_DEMO = {
    "bane_of_doom=2",
    "searing_pain=2",
    "soul_fire=1",
    "curse_of_the_elements=2",
    "curse_of_recklessness=2",
    "curse_of_weakness=2",
    "bane_of_agony=2",
    "immolate=2",
    "corruption=2",
    "bane_of_agony=2",
    "immolate=2",
    "corruption=2",
}

-- Shadow Brand's second searing_pain is the end-of-fight line (!shadow_bolt.known|cast+travel>fight_remains): filler-like, never fires
-- in game (fight_remains reads 3600, gap AN), so it takes the lower tier (2) like the other upkeep lines; the DoT order differs from Demonology's
local WARLOCK_SHADOW_BRAND = {
    "bane_of_doom=2",
    "searing_pain=2",
    "searing_pain=2",
    "curse_of_the_elements=2",
    "curse_of_recklessness=2",
    "curse_of_weakness=2",
    "bane_of_agony=2",
    "corruption=2",
    "immolate=2",
    "bane_of_agony=2",
    "corruption=2",
    "immolate=2",
}

local PACKS = {
    ["Rogue/APLs/Assassination"] = ROGUE,
    ["Rogue/APLs/Combat"] = { "riposte=1", "garrote=1", "rupture=1", "slice_and_dice=1" }, -- Riposte leads (owner R70)
    ["Rogue/APLs/Subtlety"] = ROGUE,
    ["Hunter/APLs/Beast Mastery"] = HUNTER,
    ["Hunter/APLs/Marksmanship"] = HUNTER_MM,
    ["Hunter/APLs/Survival"] = HUNTER,
    ["Paladin/APLs/Protection"] = { "seal_of_fury=2", "holy_shield=2" }, -- R41: the leveling refresh (R28) is gone
    -- the Twist of Light seals (1): open
    ["Paladin/APLs/Retribution"] = {
        "hammer_of_wrath=1",
        "seal_of_command=1",
        "seal_of_righteousness=1",
        "seal_of_command=2",
        "seal_of_righteousness=2",
        -- the opener's (move_to_melee) seals: the recipe's focus map tiers every occurrence (re-pin Task 17)
        "seal_of_command=1",
        "seal_of_righteousness=1",
        "consecration=2",
    },
    -- the totems carry none (the user, 2026-10-21)
    ["Shaman/APLs/Enhancement"] = {
        "water_shield=2",
        "flame_shock=2",
        "lightning_bolt=1",
        "flame_shock=2",
        "lightning_bolt=1",
    },
    ["Druid/APLs/Balance"] = { "moonfire=2", "insect_swarm=2", "starfire=1" },
    -- re-pin e2842f0a78 (R66): the adaptive list's order; Claw's one line is wowsims's "Claw can replace Shred" fallback
    ["Druid/APLs/Feral"] = { "shred=1", "rip=2", "rake=2", "claw=1" },
    -- re-pin e5a9cd2a2d: the adaptive list puts the upkeep Lacerate and Roar first, the rage dump (Maul) last
    ["Druid/APLs/Guardian"] = { "lacerate=2", "demoralizing_roar=2", "lacerate=2", "maul=1", "maul=2" },
    ["Mage/APLs/Arcane"] = { "arcane_missiles=1" },
    -- re-pin e2842f0a78: the closing second Scorch line is the filler, untiered (`scorch = { 2, false }`)
    ["Mage/APLs/Fire"] = { "pyroblast=1", "scorch=2", "arcane_missiles=1" },
    -- the DoTs, Banes, curses and Searing Pain's Demonic Brand upkeep at 2; Shadow Bolt on Shadow Trance and Soul Fire on
    -- Decimation at 1; Affliction's first Shadow Bolt keeps Shadow Vulnerability up (2); Amplify Curse a cooldown (none)
    -- 0.7 re-pin (e5a9cd2a2d): the rewritten build's lists (immolate no longer appears); the Siphon Life line is back
    -- with CN14 (spellIsChanneling); the pre-pull Shadow Bolt (travel fold) takes no tier
    ["Warlock/APLs/Affliction"] = {
        "shadow_bolt=2",
        "shadow_bolt=1",
        "curse_of_the_elements=2",
        "curse_of_recklessness=2",
        "curse_of_weakness=2",
        "bane_of_agony=2",
        "corruption=2",
        "bane_of_agony=2",
        "corruption=2",
        "siphon_life=2",
    },
    ["Warlock/APLs/SM Ruin"] = {
        "curse_of_the_elements=2",
        "curse_of_recklessness=2",
        "curse_of_weakness=2",
        "bane_of_doom=2",
        "shadow_bolt=1",
        "corruption=2",
        "siphon_life=2",
        "immolate=2",
    },
    ["Warlock/APLs/Demonology"] = WARLOCK_DEMO,
    ["Warlock/APLs/Shadow Brand"] = WARLOCK_SHADOW_BRAND,
    -- 0.7 re-pin (e5a9cd2a2d): the rewritten rotation (Bane of Doom first, the dot groups, Immolate in the cooldowns and
    -- as the Incinerate-cast refresh)
    ["Warlock/APLs/Destruction"] = {
        "bane_of_doom=2",
        "immolate=2",
        "curse_of_the_elements=2",
        "curse_of_recklessness=2",
        "curse_of_weakness=2",
        "bane_of_agony=2",
        "immolate=2",
        "corruption=2",
        "bane_of_agony=2",
        "immolate=2",
        "corruption=2",
        "immolate=2",
    },
}

describe("the wowsims.com packs' focus tiers by role", function()
    for pack, want in pairs(PACKS) do
        it(pack, function()
            local class, rest = pack:match("^(%w+)/(.*)$")
            assert.are.same(want, flagged("src/Hekili_" .. class .. "/" .. rest .. " (wowsims.com).simc"))
        end)
    end
end)
