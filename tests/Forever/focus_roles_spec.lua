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

-- Rupture in Assassination and Combat: open (a spender, none, or upkeep, 2)
local ROGUE = { "slice_and_dice=1", "rupture=2" }
local HUNTER = { "raptor_strike=1", "hunters_mark=2", "mongoose_bite=1" }

local PACKS = {
    ["Rogue/APLs/Assassination"] = ROGUE,
    ["Rogue/APLs/Combat"] = ROGUE,
    ["Rogue/APLs/Subtlety"] = { "slice_and_dice=1", "rupture=1" }, -- both 1: they sort by soonest
    -- Serpent Sting: arguable (a shot that is a DoT), BM and MM keep 2, Survival none
    ["Hunter/APLs/Beast Mastery"] = { HUNTER[1], HUNTER[2], HUNTER[3], "serpent_sting=2" },
    ["Hunter/APLs/Marksmanship"] = { HUNTER[1], HUNTER[2], HUNTER[3], "serpent_sting=2" },
    ["Hunter/APLs/Survival"] = HUNTER,
    ["Paladin/APLs/Protection"] = { "seal_of_fury=2", "holy_shield=2" },
    -- the Twist of Light seals (1) and Consecration (2): arguable
    ["Paladin/APLs/Retribution"] = {
        "hammer_of_wrath=1",
        "seal_of_command=1",
        "seal_of_righteousness=1",
        "seal_of_command=2",
        "seal_of_righteousness=2",
        "consecration=2",
    },
    ["Shaman/APLs/Enhancement"] = {
        "grace_of_air_totem=2",
        "strength_of_earth_totem=2",
        "fire_nova=1",
        "lightning_shield=2",
        "searing_totem=2",
        "lightning_bolt=1",
        "flame_shock=2",
    },
    ["Druid/APLs/Balance"] = { "moonfire=2", "insect_swarm=2", "starfire=1" }, -- Starfire on Eclipse: arguable
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
