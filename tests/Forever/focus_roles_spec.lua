-- tests/Forever/focus_roles_spec.lua: the focus tiers by a line's role (user ruling 2026-10-21,
-- docs/dev/wowsims-packs.md `focus`): rotational strikes, cooldowns and pre-pull lines untiered, reactive or windowed lines at 1 (off-GCD rage
-- dumps at 1 then 2), upkeep at 2. Every generated pack but the Warrior's (their own audit): its flagged lines in file
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

local ROGUE = { "garrote=1", "slice_and_dice=1", "rupture=1" } -- Slice and Dice and Rupture sort by soonest
-- the melee-weave strikes (Strider Kick, Immolation Trap, Wing Clip): 1 in Survival, 2 in BM and MM (the user)
local function hunter(weave)
    local w = "=" .. weave
    return {
        "raptor_strike=1",
        "hunters_mark=2",
        "mongoose_bite=1",
        "strider_kick" .. w,
        "immolation_trap" .. w,
        "wing_clip" .. w,
        "serpent_sting=1",
    }
end

local PACKS = {
    ["Rogue/APLs/Assassination"] = ROGUE,
    ["Rogue/APLs/Combat"] = ROGUE,
    ["Rogue/APLs/Subtlety"] = ROGUE,
    ["Hunter/APLs/Beast Mastery"] = hunter(2),
    ["Hunter/APLs/Marksmanship"] = hunter(2),
    ["Hunter/APLs/Survival"] = hunter(1),
    ["Paladin/APLs/Protection"] = { "seal_of_fury=2", "holy_shield=2" },
    -- the Twist of Light seals (1): open
    ["Paladin/APLs/Retribution"] = {
        "hammer_of_wrath=1",
        "seal_of_command=1",
        "seal_of_righteousness=1",
        "seal_of_command=2",
        "seal_of_righteousness=2",
        "consecration=2",
    },
    -- the totems carry none (the user, 2026-10-21)
    ["Shaman/APLs/Enhancement"] = { "fire_nova=1", "lightning_shield=2", "lightning_bolt=1", "flame_shock=2" },
    ["Druid/APLs/Balance"] = { "moonfire=2", "insect_swarm=2", "starfire=1" },
    ["Druid/APLs/Feral"] = { "shred=1", "claw=1", "rake=2", "rip=2", "rake=2" },
    ["Druid/APLs/Guardian"] = { "maul=1", "maul=2", "lacerate=2", "demoralizing_roar=2", "lacerate=2" },
    ["Mage/APLs/Arcane"] = { "arcane_missiles=1" },
    ["Mage/APLs/Fire"] = { "scorch=2", "pyroblast=1", "arcane_missiles=1" },
}

describe("the wowsims.com packs' focus tiers by role", function()
    for pack, want in pairs(PACKS) do
        it(pack, function()
            local class, rest = pack:match("^(%w+)/(.*)$")
            assert.are.same(want, flagged("src/Hekili_" .. class .. "/" .. rest .. " (wowsims.com).simc"))
        end)
    end
end)
