-- tests/Game/harness/viewer_layout_spec.lua (cdm-default plan Task 8, decision 110): the Cooldown Manager layouts the
-- loops' viewer arms build on an instance's fake (scenarios.viewerLayout), from the pack's auras or a class fixture.
local fake = require("Game.State.helpers.fake_api")
local scenarios = require("Game.harness.scenarios")
local ESS, UTIL, ICON, BAR = fake.VIEWERS[1], fake.VIEWERS[2], fake.VIEWERS[3], fake.VIEWERS[4]

-- A pack of three auras (b with a second rank) and two abilities, b's sharing its aura's key.
local function def()
    return {
        auras = { { key = "a" }, { key = "b" }, { key = "c" } },
        auraIds = { { 101 }, { 102, 1102 }, { 103 } },
        abilities = { { key = "b" }, { key = "x" } },
        abilityIds = { { 202 }, { 203 } },
    }
end

local O = { pull = 3, duration = 60 }

local function items(ctl, name)
    local n = 0
    for _, c in ipairs(ctl.viewer.items[name]) do
        n = n + ((c.isItem and c.cooldownID ~= nil) and 1 or 0)
    end
    return n
end

local function children(ctl)
    local n = 0
    for _, name in ipairs(fake.VIEWERS) do
        n = n + #ctl.viewer.items[name]
    end
    return n
end

describe("the loops' Cooldown Manager layouts", function()
    local ctl
    before_each(function()
        local _
        _, ctl = fake.new()
    end)

    it("none: no item in any viewer, no event, no lag", function()
        local ev = scenarios.viewerLayout(ctl, def(), "none", 1, O)
        assert.are.same({}, ev)
        assert.are.same({ 0, false }, { children(ctl), ctl.viewer.lag })
    end)

    it("buffs: one Buff icon item per pack aura naming every ID of it; any rank lights it, our auras only", function()
        scenarios.viewerLayout(ctl, def(), "buffs", 1, O)
        assert.are.same({ 0, 0, 3, 0 }, { items(ctl, ESS), items(ctl, UTIL), items(ctl, ICON), items(ctl, BAR) })
        assert.are.equal(3, #ctl.viewer.sets[2])
        assert.is_false(ctl.viewer.log) -- the loops' fake keeps no write log (L279)
        ctl.ViewerAuraBySpell("player", 1102, true, "player")
        assert.are.equal(fake.SECRET, ctl.viewer.items[ICON][2].auraInstanceID)
        ctl.ViewerAuraBySpell("target", 103, true, "party1")
        assert.is_nil(ctl.viewer.items[ICON][3].auraInstanceID)
    end)

    it(
        "fixture: each entry in its category's viewer, plus an Essential entry per ability whose aura the pack has",
        function()
            local fixture = {
                [700] = { 0, 9, 9, { 101 } }, -- an Essential cooldown entry linking aura a
                [701] = { 2, 103, nil, {} }, -- a Buff icon entry of aura c
                [7702] = { 3, 555, 555, {} }, -- a Buff bar entry of no pack aura
            }
            scenarios.viewerLayout(ctl, def(), "fixture", 1, setmetatable({ fixture = fixture }, { __index = O }))
            -- Essential: the fixture's 700 and ability b's entry (its aura b); ability x has no aura: none
            assert.are.same({ 2, 0, 1, 1 }, { items(ctl, ESS), items(ctl, UTIL), items(ctl, ICON), items(ctl, BAR) })
            assert.are.same({ 9, 103 }, { ctl.viewer.infos[700].spellID, ctl.viewer.infos[701].spellID })
            ctl.ViewerAuraBySpell("player", 1102, true, "player") -- aura b's rank 2 lights ability b's Essential entry
            local lit = 0
            for _, c in ipairs(ctl.viewer.items[ESS]) do
                lit = lit + (c.auraInstanceID ~= nil and 1 or 0)
            end
            assert.are.equal(1, lit)
            local _, bare = fake.new()
            assert.is_nil(scenarios.viewerLayout(bare, def(), "fixture", 1, O)) -- no fixture: the arm is skipped
            assert.are.equal(0, children(bare))
        end
    )

    it(
        "mixed: 0-3 items an aura, unconfigured slots, a silent and a no-unit item, and the fight's layout events",
        function()
            local seen = { hide = 0, repoint = 0, acquire = 0, silent = 0, noUnit = 0, unconfigured = 0 }
            for seed = 1, 6 do
                local _, c = fake.new()
                local ev = scenarios.viewerLayout(c, def(), "mixed", seed, O)
                for _, name in ipairs(fake.VIEWERS) do
                    for _, item in ipairs(c.viewer.items[name]) do
                        seen.silent = seen.silent + (item.silent and 1 or 0)
                        seen.noUnit = seen.noUnit + (item.noUnit and 1 or 0)
                        seen.unconfigured = seen.unconfigured + (item.cooldownID == nil and 1 or 0)
                    end
                end
                for _, e in ipairs(ev) do
                    assert.is_true(e[1] >= O.pull and e[1] <= O.pull + O.duration, "inside the fight")
                    if e[2] == "@viewerShown" and e[4] == false then
                        seen.hide = seen.hide + 1
                        local back
                        for _, f in ipairs(ev) do
                            back = back or (f[2] == "@viewerShown" and f[3] == e[3] and f[4] == true and f[1]) or nil
                        end
                        assert.is_true(math.abs(back - e[1] - 10) < 1e-9, "hidden for 10 s")
                    elseif e[2] == "@viewerLayout" then
                        seen[e[3]] = seen[e[3]] + 1
                    end
                end
                assert.are.equal(seed % 2 == 0 and 1 or false, c.viewer.lag) -- the seen rule's lag on even seeds
            end
            assert.are.same({ hide = 6, repoint = 6, acquire = 6, silent = 6, noUnit = 6, unconfigured = 12 }, seen)
        end
    )

    it("built once an instance: the next fight resets auras, the re-point, the hidden viewer; no new frame", function()
        local ev = scenarios.viewerLayout(ctl, def(), "mixed", 2, O)
        local n0 = children(ctl)
        local drive = require("Game.harness.drive")
        ctl.ViewerAuraBySpell("player", 101, true, "player")
        ctl.ViewerFlush()
        local repointed
        for _, e in ipairs(ev) do
            drive.op({}, ctl, e[2], e[3], e[4], e[5], e[6])
            if e[3] == "repoint" then
                repointed = e[5]
            end
        end
        local grown = children(ctl)
        assert.are.equal(n0 + 1, grown) -- the first fight's pool growth
        ctl.viewer.shown[UTIL] = false
        local ev2 = scenarios.viewerLayout(ctl, def(), "mixed", 3, O)
        assert.are.equal(grown, children(ctl)) -- the slots stay bounded: no frame is made again
        for _, e in ipairs(ev2) do
            assert.is_true(e[3] ~= "acquire", "the pool grows in the first fight only")
        end
        assert.are.same({}, ctl.viewer.shown)
        assert.is_true(ctl.viewer.parentShown)
        assert.are.same({ 0, 0, false }, { #ctl.viewer.applied, #ctl.viewer.pending, ctl.viewer.lag })
        for _, name in ipairs(fake.VIEWERS) do
            for _, item in ipairs(ctl.viewer.items[name]) do
                assert.is_nil(item.auraInstanceID)
                if item.isItem and item.base then
                    assert.are.equal(item.base, item.cooldownID) -- the re-point undone
                end
            end
        end
        assert.is_truthy(repointed)
    end)
end)
