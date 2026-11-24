-- tests/Forever/percent_cost_order_spec.lua: a percent-of-base mana cost is rounded whole first and then cut by a
-- talent's percent, the cut left unrounded (wowsims mana.go newManaCost `int32(pct x base) / 100`, then spell.go
-- ApplyCostModifiers `float64(cost) x PercentModifier`; L1793 item 1). A class file therefore declares the fraction
-- as it is and the cut as a talent cost modifier (the engine rounds, then cuts, in both layers); a `spend` that folds
-- the cut into the fraction would be rounded after it. Two checks per class file: no fraction `spend` moves with any
-- talent rank, and each talent cut is a cost modifier on the spell with the rank values below.
local ld = require("Forever.helpers.load_druid")

local function ranks(per, n)
    local t = {}
    for r = 1, n do
        t[r] = -per * r
    end
    return t
end

local function near(a, b)
    return math.abs(a - b) < 1e-9
end

-- file, class token, { ability key, talent key, the cut by rank }
local CASES = {
    {
        "Druid",
        "DRUID",
        {
            { "aquatic_form", "natural_shapeshifter", ranks(0.1, 3) },
            { "bear_form", "natural_shapeshifter", ranks(0.1, 3) },
            { "cat_form", "natural_shapeshifter", ranks(0.1, 3) },
            { "moonkin_form", "natural_shapeshifter", ranks(0.1, 3) },
            { "travel_form", "natural_shapeshifter", ranks(0.1, 3) },
            { "shifting_power", "natural_shapeshifter", ranks(0.1, 3) },
        },
    },
    {
        "Paladin",
        "PALADIN",
        {
            { "blessing_of_freedom", "benediction", ranks(0.02, 5) },
            { "righteous_fury", "benediction", ranks(0.02, 5) },
            { "judgement", "benediction", ranks(0.02, 5) },
            { "seal_of_justice", "benediction", ranks(0.02, 5) },
            { "cleanse", "benediction", ranks(0.02, 5) },
            { "cleanse", "purifying_power", ranks(0.1, 2) },
            { "purify", "purifying_power", ranks(0.1, 2) },
        },
    },
    {
        "Shaman",
        "SHAMAN",
        {
            { "totemic_call", "totemic_focus", ranks(0.05, 5) },
            { "earthbind_totem", "totemic_focus", ranks(0.05, 5) },
            { "grounding_totem", "totemic_focus", ranks(0.05, 5) },
            { "poison_cleansing_totem", "totemic_focus", ranks(0.05, 5) },
            { "disease_cleansing_totem", "totemic_focus", ranks(0.05, 5) },
        },
    },
    {
        "Priest",
        "PRIEST",
        {
            { "shadowform", "mental_agility", { -0.03, -0.07, -0.1 } },
            { "power_infusion", "mental_agility", { -0.03, -0.07, -0.1 } },
            { "dispel_magic", "mental_agility", { -0.03, -0.07, -0.1 } },
            { "cure_disease", "mental_agility", { -0.03, -0.07, -0.1 } },
            { "abolish_disease", "mental_agility", { -0.03, -0.07, -0.1 } },
            { "elunes_grace", "mental_agility", { -0.03, -0.07, -0.1 } },
        },
    },
    { "Hunter", "HUNTER", {
        { "revive_pet", "improved_revive_pet", ranks(0.2, 2) },
    } },
    -- Warlock's summons are not here: their Master Summoner and Fel Domination cuts are one additive sum in the pack
    -- (a game spell-mod bucket), which a multiplicative cost modifier would misprice (open item of L1793).
}

describe("a percent-of-base cost is rounded before its talent cut", function()
    for _, case in ipairs(CASES) do
        local name, class, sites = case[1], case[2], case[3]
        local w = ld.load(nil, "src/Hekili_" .. name .. "/" .. name .. ".lua", class)

        it(name .. ": no percent-of-base spend moves with a talent rank", function()
            local checked = 0
            for key, a in pairs(w.abilities) do
                if type(a.spend) == "function" then
                    local e0, e2 = ld.env(w), ld.env(w)
                    e2.talent = setmetatable({}, {
                        __index = function()
                            return { rank = 2, enabled = true }
                        end,
                    })
                    local r0, r2 = ld.run(a.spend, e0), ld.run(a.spend, e2)
                    if type(r0) == "number" and r0 > 0 and (r0 < 1 or a.spendBase) then
                        checked = checked + 1
                        assert.are.equal(r0, r2, key)
                    end
                end
            end
            assert.is_true(checked > 0)
        end)

        it(name .. ": each talent cut is a cost modifier on its spell, by rank", function()
            for _, s in ipairs(sites) do
                local key, talent, pct = s[1], s[2], s[3]
                local id = w.abilities[key].id
                local found
                for _, m in ipairs(w.costMods) do
                    local hit = false
                    for _, sp in ipairs(m.spells or {}) do
                        hit = hit or sp == id
                    end
                    if m.talent == talent and not m.aura and hit then
                        found = m
                    end
                end
                assert.is_truthy(found, key .. " " .. talent)
                for r, v in ipairs(pct) do
                    assert.is_true(near(found.pct[r], v), key .. " " .. talent .. " rank " .. r)
                end
                assert.are.equal(#pct, #found.pct, key .. " " .. talent)
                assert.is_truthy(w.abilities[key], key)
            end
        end)
    end
end)

-- The same through the engine (headless.lua), both layers: the belief's I.CostOf and the simulation's action cost are
-- the fraction rounded to a whole of the pool's base power, then cut by the talent at each rank.
local headless = require("Game.harness.headless")
local CLASS = {
    Druid = { 11, 1483 },
    Paladin = { 2, 1486 },
    Shaman = { 7, 1489 },
    Priest = { 5, 1487 },
    Hunter = { 3, 1484 },
}

local function idsOf(a)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or {}) do
        out[#out + 1] = id
    end
    return out
end

describe("a percent-of-base cost is rounded before its talent cut, through the engine", function()
    for _, case in ipairs(CASES) do
        local name, token, sites = case[1], case[2], case[3]
        it(name .. ": the belief and the simulation price whole base x (1 - cut) at every rank", function()
            local w = ld.load(nil, "src/Hekili_" .. name .. "/" .. name .. ".lua", token)
            local known = {}
            for _, a in pairs(w.abilities) do
                for _, id in ipairs(idsOf(a)) do
                    known[#known + 1] = id
                end
            end
            local byTalent, order = {}, {}
            for _, s in ipairs(sites) do
                if not byTalent[s[2]] then
                    byTalent[s[2]], order[#order + 1] = {}, s[2]
                end
                table.insert(byTalent[s[2]], s)
            end
            for _, talent in ipairs(order) do
                for rank = 0, #byTalent[talent][1][3] do
                    local H = headless.new({
                        character = {
                            class = token,
                            classID = CLASS[name][1],
                            specID = CLASS[name][2],
                            level = 60,
                            known = known,
                            talents = rank > 0 and { [w.talents[talent][2]] = rank } or {},
                            power = { type = 0, token = "MANA", max = 6000, value = 6000 },
                            speed = { 3 },
                        },
                    })
                    local I, VS, S = H.ns.VirtualStateInternal, H.ns.VirtualState, H.Hekili.State
                    local t = H.ctl.now + 1
                    assert.is_true(headless.cycle(H, t))
                    VS.Drain(t)
                    S.reset("Primary", true)
                    for _, s in ipairs(byTalent[talent]) do
                        local def = w.abilities[s[1]]
                        local a = I.ab.bySpell[def.id]
                        local f = ld.run(def.spend, ld.env(w))
                        local base = I.basePow[I.ab.slot[a]]
                        local want = math.floor(f * base + 0.5 + 1e-6) * (1 + (s[3][rank] or 0))
                        local why = ("%s %s rank %d"):format(s[1], talent, rank)
                        assert.is_true(
                            math.abs(I.CostOf(a) - want) < 1e-6,
                            why .. " belief " .. I.CostOf(a) .. " vs " .. want
                        )
                        assert.is_true(
                            math.abs(S.action[s[1]].cost - want) < 1e-6,
                            why .. " sim " .. S.action[s[1]].cost .. " vs " .. want
                        )
                    end
                    assert.are.same({}, H.errors)
                end
            end
        end)
    end
end)
