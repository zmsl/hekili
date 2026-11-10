-- tests/Forever/cdm_ranks_spec.lua (cdm-verdict spec §4, decision 124): the Cooldown Manager item follows the player's
-- current rank, each rank its own spell ID, so a pack aura's id/copy must name every ID the viewer can report.
-- What it checks: (1) every captured viewer entry (tools/data/cooldownviewer/<CLASS>.lua) that already shares at least
-- one ID with a pack aura has ALL its candidate IDs (the leaf's rule below) in that aura's id/copy; (2) the Druid rank
-- families checked by hand against the DB2 (build 70707: same name, class set 7, "Rank N", SpellLevels 1-60) are listed
-- here so CI needs no DB2.
-- What it cannot catch: an ID the viewer reports that no aura has at all (an entry sharing no ID with any aura is never
-- looked at: Lacerate's 414647 was missing that way), and every class without a fixture (only Druid and Warrior have
-- one) or a FAMILIES list (Druid only).
local loader = require("Forever.helpers.load_druid")
local warrior = require("Forever.helpers.load_warrior")

local function idsOf(a)
    local set = { [a.id] = true }
    for _, c in ipairs(type(a.copy) == "table" and a.copy or {}) do
        set[c] = true
    end
    return set
end

-- The leaf's own candidate rule (Presence/CooldownViewer.lua candidates()): the entry's linkedSpellIDs when it has any,
-- else its spellID and overrideSpellID. An entry that links the buff and names the cast or a passive as spellID (Omen of
-- Clarity 16864 -> 16870) needs only the links in the pack: a passive in `copy` could match the aura walk wrongly.
local function fixtureIds(e)
    if type(e[4]) == "table" and #e[4] > 0 then
        return e[4]
    end
    return { e[2], e[3] }
end

local function missing(w, fix)
    local out, seen = {}, {}
    for cdID, e in pairs(fix) do
        for key, a in pairs(w.auras) do
            if type(key) == "string" and type(a) == "table" and type(a.id) == "number" then
                local set, touched = idsOf(a), false
                local ids = fixtureIds(e)
                for _, id in ipairs(ids) do
                    touched = touched or set[id]
                end
                if touched then
                    for _, id in ipairs(ids) do
                        if not set[id] and not seen[key .. id] then
                            seen[key .. id] = true
                            out[#out + 1] = key .. " lacks " .. id .. " (cooldownID " .. cdID .. ")"
                        end
                    end
                end
            end
        end
    end
    table.sort(out)
    return out
end

describe("the pack auras cover the ranks the Cooldown Manager reports", function()
    local druid, war
    setup(function()
        druid = loader.load(nil, "src/Hekili_Druid/Druid.lua", "DRUID")
        war = warrior.load()
    end)

    it("Druid: every fixture entry's IDs are all in the aura they touch", function()
        assert.are.same({}, missing(druid, dofile("tools/data/cooldownviewer/DRUID.lua")))
    end)

    it("Warrior: every fixture entry's IDs are all in the aura they touch", function()
        assert.are.same({}, missing(war, dofile("tools/data/cooldownviewer/WARRIOR.lua")))
    end)

    -- DB2 rank families (Forever's own same-rank IDs included), verified 2026-11-09
    local FAMILIES = {
        bash = { 5211, 6798, 8983 },
        demoralizing_roar = { 99, 1735, 9490, 9747, 9898 },
        faerie_fire = { 770, 778, 9749, 9907 },
        gift_of_the_wild = { 21849, 21850 },
        hurricane = { 16914, 17401, 17402, 1278965, 1278968, 1278759 }, -- the last three: the tick's target debuff
        insect_swarm = { 5570, 24974, 24975, 24976, 24977 },
        lacerate = { 414644, 414647, 1235826, 1235827 },
        mark_of_the_wild = { 1126, 5232, 5234, 6756, 8907, 9884, 9885, 1291335, 1310503 },
        moonfire = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 },
        natures_grasp = { 16689, 16810, 16811, 16812, 16813, 17329 },
        pounce = { 9005, 9823, 9827 },
        prowl = { 5215, 6783, 9913 },
        rake = { 1822, 1823, 1824, 9904 },
        rip = { 1079, 9492, 9493, 9752, 9894, 9896 },
        thorns = { 467, 782, 1075, 8914, 9756, 9910 },
    }

    for key, ranks in pairs(FAMILIES) do
        it("Druid " .. key .. " names every rank", function()
            local set = idsOf(druid.auras[key])
            for _, id in ipairs(ranks) do
                assert.is_true(set[id] == true, key .. " lacks " .. id)
            end
        end)
    end
end)
