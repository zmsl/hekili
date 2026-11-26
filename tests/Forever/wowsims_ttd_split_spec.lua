-- tests/Forever/wowsims_ttd_split_spec.lua (lane a-ttd, owner rule L1902): which remaining-time term each generated
-- pack line reads. Target-bound lines (value lost if this target dies first: DoTs, debuffs, a cast landing on it, a
-- combo-point dump) read target.time_to_die; fight-length lines (cooldowns, potions, mana, buffs of ours) keep
-- fight_remains. A re-pin that changes a count is adjudicated (fable-ttd-unclear-decision.md), not absorbed.
local PACKS = {
    -- pack file = { target.time_to_die, fight_remains } occurrences in its emitted (non-comment) lines
    ["Hekili_Druid/APLs/Balance (wowsims.com).simc"] = { 0, 1 },
    ["Hekili_Druid/APLs/Feral (wowsims.com).simc"] = { 5, 9 },
    -- the Rogues' F: Slice and Dice, and the L4 Gnome Eureka hold (cooldown alignment) on 19 lines a pack
    ["Hekili_Rogue/APLs/Assassination (wowsims.com).simc"] = { 2, 21 },
    ["Hekili_Rogue/APLs/Combat (wowsims.com).simc"] = { 2, 21 },
    ["Hekili_Rogue/APLs/Subtlety (wowsims.com).simc"] = { 2, 21 },
    ["Hekili_Warlock/APLs/Affliction (wowsims.com).simc"] = { 9, 16 },
    ["Hekili_Warlock/APLs/Demonology (wowsims.com).simc"] = { 9, 2 },
    ["Hekili_Warlock/APLs/Destruction (wowsims.com).simc"] = { 12, 2 },
    ["Hekili_Warlock/APLs/SM Ruin (wowsims.com).simc"] = { 1, 1 },
    ["Hekili_Warlock/APLs/Shadow Brand (wowsims.com).simc"] = { 9, 2 },
    -- the Warriors' F: 5 each from gear-1's Blackhand's Breadth lines (cd_trinkets; an item line is fight-length, L1902 point 3)
    ["Hekili_Warrior/APLs/Arms (wowsims.com).simc"] = { 0, 20 },
    ["Hekili_Warrior/APLs/Fury (wowsims.com).simc"] = { 0, 22 },
}

local function count(s, term)
    local n, i = 0, 1
    while true do
        local a, b = s:find(term, i, true)
        if not a then
            return n
        end
        n, i = n + 1, b + 1
    end
end

describe("the generated packs' remaining-time terms (owner rule L1902)", function()
    it("read target.time_to_die on target-bound lines, fight_remains elsewhere: 51 / 138", function()
        local got, want, t, f = {}, {}, 0, 0
        local p = assert(io.popen("ls src/Hekili_*/APLs/*"))
        for path in p:read("*a"):gmatch("[^\n]+") do
            local file = assert(io.open(path, "rb"))
            local text = file:read("*a")
            file:close()
            local body = {}
            for line in text:gmatch("[^\n]+") do
                if not line:match("^#") then
                    body[#body + 1] = line
                end
            end
            local s = table.concat(body, "\n")
            local pair = { count(s, "target.time_to_die"), count(s, "fight_remains") }
            if pair[1] + pair[2] > 0 then
                got[path:sub(5)] = pair
                t, f = t + pair[1], f + pair[2]
            end
        end
        p:close()
        for k, v in pairs(PACKS) do
            want[k] = v
        end
        assert.are.same(want, got)
        assert.are.same({ 51, 138 }, { t, f })
    end)
end)

-- Acceptance 3 (Fable): with the time to die unknown (3600: no estimate, or the library off) each switched line shape
-- reads as it did on fight_remains, which counts an unknown 3600 down through the look-ahead while
-- target.time_to_die keeps it.
describe("a switched line shape at an unknown time to die", function()
    local headless = require("Game.harness.headless")
    local wl = require("Forever.helpers.warlock_world")
    local SHAPES = {
        "fight_remains<=1", -- Feral's end-of-fight Bite (rule 0)
        "fight_remains<8", -- Feral's Bite over Rip
        "fight_remains>=(8+1)", -- Feral's Rip
        "fight_remains>6", -- Feral's Rake
        "!(fight_remains<=6)", -- the Rogues' Rupture
        "fight_remains<=6", -- the Rogues' Eviscerate
        "fight_remains>12", -- the Warlocks' flat DoT lines
        "fight_remains>=60", -- SM Ruin's Bane of Doom
        "fight_remains>debuff.bane_of_doom.duration", -- the DoT and Bane lines
        "fight_remains<debuff.bane_of_doom.duration", -- Amplify Curse
        "((fight_remains-5)/debuff.bane_of_doom.duration)<1", -- the cooldowns gate
        "(action.shadow_bolt.cast+action.shadow_bolt.travel_time)>fight_remains", -- Death Coil, Searing Pain
        "action.searing_pain.cast>fight_remains", -- Death Coil
    }

    it("reads as today, in the look-ahead too", function()
        local H = headless.new({ character = wl.Destruction.character(), pack = wl.Destruction.PACK })
        assert.are.same({}, H.loadErrors)
        local st = H.Hekili.State
        local function read(s)
            local f = assert(loadstring("return " .. H.Hekili.Scripts.SimToLua(s)))
            return setfenv(f, st)() and true or false
        end
        for _, ahead in ipairs({ 0, 3, 30, 300 }) do
            st.reset()
            st.advance(ahead)
            st.delay = 0.5
            assert.are.same({ 3600, 3600 }, { st.target.time_to_die, st.longest_ttd })
            for _, s in ipairs(SHAPES) do
                local was = read(s)
                assert.are.equal(was, read((s:gsub("fight_remains", "target.time_to_die"))), s .. " at +" .. ahead)
            end
        end
    end)
end)
