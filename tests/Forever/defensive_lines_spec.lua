-- tests/Forever/defensive_lines_spec.lua (L1805): each shipped line that reads the player's health (translator rule 23:
-- under `health.known`) fires on a low band, is silent while the health is unknown (the first prime, the capability
-- lost) and holds through a re-prime shorter than the hold bound (owner "Hold last reading"). The harness's fights
-- rarely lower our health, so the loops cannot show these lines working; this spec does, line by line.
local headless = require("Game.harness.headless")
local fake_lhv = require("Game.harness.fake_lhv")
local dlw = require("Forever.helpers.druid_loop_world")
local ww = require("Forever.helpers.warrior_world")

local F = 1 / 60

local PACKS = {
    {
        name = "Guardian (wowsims.com)",
        character = dlw.Guardian.character,
        -- sorted; (L1808) with the Healthstone and healing potion lines and the imported cat lists' Barkskin
        want = {
            "barkskin",
            "barkskin",
            "frenzied_regeneration",
            "healing_potion",
            "healing_potion",
            "healthstone",
            "healthstone",
        },
    },
    { -- Feral imports Guardian's lists for Bear Form (APLs/packs.lua `imports`): the same lines
        name = "Feral (wowsims.com)",
        character = dlw.Feral.character,
        want = {
            "barkskin",
            "barkskin",
            "frenzied_regeneration",
            "healing_potion",
            "healing_potion",
            "healthstone",
            "healthstone",
        },
    },
    {
        name = "Protection (wowsims.com)",
        character = ww.Protection.character,
        want = { "healing_potion", "healthstone", "last_stand", "shatter_curse", "shield_wall", "stoneform" },
    },
    { -- (owner 2026-11-24) rule 13's Stoneform waits for low health, as Protection Warrior's own line
        name = "Protection (wowsims.com)",
        character = require("Forever.helpers.paladin_world").Protection.character,
        label = ", Paladin",
        want = { "divine_shield", "healing_potion", "healthstone", "lay_on_hands", "stoneform" },
        low = 100, -- 10%: under Lay on Hands' 15
    },
}

for _, P in ipairs(PACKS) do
    describe("the restored defensive lines of " .. P.name .. (P.label or ""), function()
        local H, lhv, ids, keys

        before_each(function()
            H = headless.new({ character = P.character(), pack = P.name })
            lhv = fake_lhv.new({
                now = function()
                    return H.ctl.now
                end,
            })
            local major, minor = lhv:GetVersion()
            local stub = rawget(H.env, "LibStub")
            stub.libs[major], stub.minors[major] = lhv, minor
            H.Hekili.bandOff = false
            H.Hekili:ProvidersChanged()
            H.ctl.guid.target = "Creature-1"
            H.ctl.health, H.ctl.healthMax = 1000, 1000
            ids, keys = {}, {}
            for list, entries in pairs(H.Hekili.DB.profile.packs[P.name].lists) do
                for i, e in ipairs(entries) do
                    if (e.criteria or ""):find("health%.known") then
                        ids[#ids + 1] = P.name .. ":" .. list .. ":" .. i
                        keys[#keys + 1] = e.action
                    end
                end
            end
        end)

        local function push(hp)
            lhv:Push("health", "player", nil, hp, 1000, H.ctl.now)
        end

        -- n frames, a cycle each; then each guarded line's answer, in pack order
        local function frames(n)
            for i = 1, n do
                assert.is_true(headless.cycle(H, H.ctl.now + F), i)
            end
            H.Hekili.State.reset()
            local out = {}
            for i, id in ipairs(ids) do
                out[i] = H.Hekili.Scripts:CheckScript(id) == true
            end
            return out
        end

        local function all(v)
            local out = {}
            for i = 1, #ids do
                out[i] = v
            end
            return out
        end

        it("carries every restored line, each on the Defensives toggle", function()
            local got = { unpack(keys) }
            table.sort(got) -- the lists' order is the profile table's
            assert.are.same(P.want, got)
            for _, k in ipairs(keys) do
                assert.are.equal("defensives", H.Hekili.Class.abilities[k].toggle, k)
            end
        end)

        it("is silent while unknown, fires on a low band, holds through a short re-prime, silent once lost", function()
            push(1000)
            assert.are.same(all(false), frames(2)) -- the first prime: unknown, full
            assert.are.same(all(false), frames(12)) -- a reading, at full
            H.ctl.combat = true
            H.ctl.Fire("PLAYER_REGEN_DISABLED")
            push(P.low or 200) -- 20%, the Paladin row 10%: under every threshold (the lowest, Frenzied Regeneration's, < 25)
            assert.are.same(all(true), frames(3))
            lhv:Prime("player", H.ctl.now) -- about 10 frames unknown, under the 1 s bound
            for i = 1, 12 do
                assert.are.same(all(true), frames(1), i)
            end
            lhv:SetAvailable("unavailable", "error", "health") -- the health kind lost alone
            assert.are.same(all(false), frames(1))
            assert.are.same({}, H.errors)
        end)
    end)
end

-- L1808 (def-2 step 4): each defensive line beyond wowsims, one at a time (every other health setting at 1, so only
-- the line under test can fire): it fires below its setting on a low band and not above it, follows its setting when
-- moved, holds through a short re-prime, is silent while the health is unknown and with its toggle off, and shows in
-- the Defensives display, never in Primary (the toggles' Separate default, owner L1808).
local LINES = {
    -- { content, pack, action, setting key; spell: a spell the character learns (the worlds know only what their
    -- rotation casts); talent: a talent the line needs; item: an item in the bags }
    { dlw.Feral, "Feral (wowsims.com)", "barkskin", "barkskin_cat_health", spell = 22812 },
    { dlw.Balance, "Balance (wowsims.com)", "barkskin", "barkskin_health", spell = 22812 },
    {
        require("Forever.helpers.rogue_world").Combat,
        "Combat (wowsims.com)",
        "evasion",
        "evasion_health",
        spell = 5277,
    },
    {
        require("Forever.helpers.mage_world").Frost,
        "Frost (wowsims.com)",
        "ice_block",
        "ice_block_health",
        talent = 11958,
    },
    {
        require("Forever.helpers.paladin_world").Retribution,
        "Retribution (wowsims.com)",
        "divine_shield",
        "divine_shield_health",
        spell = 642,
    },
    {
        require("Forever.helpers.paladin_world").Retribution,
        "Retribution (wowsims.com)",
        "lay_on_hands",
        "lay_on_hands_health",
        spell = 633,
    },
    {
        require("Forever.helpers.priest_world").Shadow,
        "Shadow (wowsims.com)",
        "power_word_shield",
        "power_word_shield_health",
        spell = 17,
    },
    -- (owner 2026-11-24) a Dwarf tank's Stoneform: no poison or disease needed, at or below its setting (a Dwarf knows
    -- it from level 1; the worlds know only what their rotation casts)
    {
        ww.Protection,
        "Protection (wowsims.com)",
        "stoneform",
        "stoneform_health",
        spell = 20594,
        race = "Dwarf",
        label = ", Warrior",
    },
    {
        require("Forever.helpers.paladin_world").Protection,
        "Protection (wowsims.com)",
        "stoneform",
        "stoneform_health",
        spell = 20594,
        race = "Dwarf",
        label = ", Paladin",
        shield = 642, -- (owner 2026-11-24, L1808) it waits while Divine Shield is up, as Lay on Hands does
    },
    { -- owner: "Desperate Prayer is exclusive to dwarf priests"
        require("Forever.helpers.priest_world").Shadow,
        "Shadow (wowsims.com)",
        "desperate_prayer",
        "desperate_prayer_health",
        spell = 13908,
        race = "Dwarf",
    },
    {
        require("Forever.helpers.hunter_world").Survival,
        "Survival (wowsims.com)",
        "deterrence",
        "deterrence_health",
        talent = 19263,
    },
    {
        require("Forever.helpers.warlock_world").Affliction,
        "Affliction (wowsims.com)",
        "death_coil_defensive",
        "death_coil_defensive_health",
    },
    {
        require("Forever.helpers.rogue_world").Combat,
        "Combat (wowsims.com)",
        "healthstone",
        "healthstone_health",
        item = 5509,
    },
    {
        require("Forever.helpers.rogue_world").Combat,
        "Combat (wowsims.com)",
        "healing_potion",
        "healing_potion_health",
        item = 13446,
    },
}

for _, P in ipairs(LINES) do
    local C, pack, action, key = P[1], P[2], P[3], P[4]
    describe("the " .. action .. " line of " .. pack .. (P.label or ""), function()
        local H, lhv, S

        local function setting(k, v)
            H.Hekili.Engine.settings.specs[S.spec.id].settings[k] = v
            H.Hekili:SettingsChanged()
        end

        before_each(function()
            local c = C.character()
            if P.spell then
                c.known[#c.known + 1] = P.spell
            end
            if P.shield then
                c.known[#c.known + 1] = P.shield
            end
            c.race = P.race or c.race
            if P.talent then
                c.talents = c.talents or {}
                c.talents[P.talent] = 1
                c.known[#c.known + 1] = P.talent
            end
            H = headless.new({ character = c, pack = pack })
            assert.are.same({}, H.loadErrors)
            lhv = fake_lhv.new({
                now = function()
                    return H.ctl.now
                end,
            })
            local major, minor = lhv:GetVersion()
            local stub = rawget(H.env, "LibStub")
            stub.libs[major], stub.minors[major] = lhv, minor
            H.Hekili.bandOff = false
            H.Hekili:ProvidersChanged()
            H.ctl.guid.target = "Creature-1"
            H.ctl.health, H.ctl.healthMax = 1000, 1000
            if P.item then
                H.ctl.itemCount[P.item], H.ctl.itemUsable[P.item] = 1, true
            end
            S = H.Hekili.State
            for _, e in ipairs(H.Hekili.Class.specs[S.spec.id].settings) do -- every other line quiet
                if e.name:match("_health$") and e.name ~= key then
                    setting(e.name, 1)
                end
            end
        end)

        local function push(pct)
            lhv:Push("health", "player", nil, pct * 10, 1000, H.ctl.now)
        end

        -- n frames; then whether the line is shown in Defensives (its first icon) and anywhere in Primary
        local function frames(n)
            for i = 1, n do
                assert.is_true(headless.cycle(H, H.ctl.now + F), i)
            end
            local out = H.Hekili.Engine.Output
            local primary = false
            for i = 1, out.Primary.count do
                primary = primary or out.Primary.recs[i].actionName == action
            end
            assert.is_false(primary, "shown in Primary")
            return out.Defensives.count > 0 and out.Defensives.recs[1].actionName == action
        end

        it("fires below its setting, follows it, holds a short re-prime, stays in Defensives", function()
            local d = S.settings[key]
            assert.is_true(S.action[action].known, action .. " known")
            push(100)
            assert.is_false(frames(14)) -- the first prime, then a reading at full
            H.ctl.combat = true
            H.ctl.Fire("PLAYER_REGEN_DISABLED")
            push(d + 1) -- the cell above the setting
            assert.is_false(frames(3))
            push(d - 1) -- below it
            assert.is_true(frames(3))
            lhv:Prime("player", H.ctl.now) -- about 10 frames unknown, under the 1 s bound
            for i = 1, 12 do
                assert.is_true(frames(1), i)
            end
            setting(key, d - 5) -- moved under the reading: off; the reading under it again: on
            assert.is_false(frames(2))
            push(d - 6)
            assert.is_true(frames(3))
            assert.are.same({}, H.errors)
        end)

        it("is silent while the health is unknown, and with its toggle off", function()
            local d = S.settings[key]
            push(100)
            frames(14)
            H.ctl.combat = true
            H.ctl.Fire("PLAYER_REGEN_DISABLED")
            push(d - 1)
            assert.is_true(frames(3))
            H.Hekili.DB.profile.toggles.defensives.value = false
            H.Hekili:ResetSpellCaches()
            assert.is_false(frames(2))
            H.Hekili.DB.profile.toggles.defensives.value = true
            H.Hekili:ResetSpellCaches()
            assert.is_true(frames(2))
            lhv:SetAvailable("unavailable", "error", "health") -- the health kind lost
            assert.is_false(frames(2))
            assert.are.same({}, H.errors)
        end)

        -- the line's wait in Defensives after n frames (nil: not its first icon); under the shield the engine
        -- forecasts the shield's fall, so the line is queued for then, not offered now (Lay on Hands the same)
        local function wait(n)
            return frames(n) and H.Hekili.Engine.Output.Defensives.recs[1].wait or nil
        end

        if P.shield then
            it("waits while the shield is up: queued for its fall, offered at once when it is gone", function()
                assert.is_true(S.action.divine_shield.known, "divine_shield known")
                push(100)
                frames(14)
                H.ctl.combat = true
                H.ctl.Fire("PLAYER_REGEN_DISABLED")
                push(S.settings[key] - 1)
                assert.are.equal(0, wait(3))
                H.ctl.auras.player.HELPFUL[1] =
                    { spellId = P.shield, expirationTime = H.ctl.now + 12, applications = 0 }
                H.ctl.Fire("UNIT_AURA", "player")
                local w = wait(3)
                assert.is_true(w == nil or w > 11, tostring(w))
                H.ctl.auras.player.HELPFUL[1] = nil
                H.ctl.Fire("UNIT_AURA", "player")
                assert.are.equal(0, wait(3))
                assert.are.same({}, H.errors)
            end)
        end
    end)
end

-- L1808 (owner: "barkskin is available in all forms"): no Barkskin line waits on a form, and each form reaches one:
-- Feral's own outside Bear Form, the imported Guardian line in it (and Guardian's own the other way round)
describe("the Barkskin lines", function()
    for _, P in ipairs({
        { dlw.Balance, "Balance (wowsims.com)", { default = "" } },
        { dlw.Feral, "Feral (wowsims.com)", { default = "!buff.bear_form.up", bear = "" } },
        { dlw.Guardian, "Guardian (wowsims.com)", { default = "!buff.cat_form.up", cat = "" } },
    }) do
        it("of " .. P[2] .. " read no form but the import's own guard", function()
            local H = headless.new({ character = P[1].character(), pack = P[2] })
            local got = {}
            for list, entries in pairs(H.Hekili.DB.profile.packs[P[2]].lists) do
                for _, e in ipairs(entries) do
                    if e.action == "barkskin" then
                        assert.is_nil(got[list], list .. ": one Barkskin line a list")
                        local forms = {} -- the form terms the line reads (tools/make_pack.lua's import guard)
                        for f in (e.criteria or ""):gmatch("!?buff%.[%w_]*_form%.up") do
                            forms[#forms + 1] = f
                        end
                        got[list] = table.concat(forms, "&")
                    end
                end
            end
            assert.are.same(P[3], got)
        end)
    end
end)

-- owner L1808: "Desperate Prayer is exclusive to dwarf priests": another race's Priest never sees the line, even with
-- the spell in the spellbook (the race check, state.race: the client's race token, as the race packs read it)
describe("Desperate Prayer for a priest of another race", function()
    it("is unknown and never shown, at any health", function()
        local pw = require("Forever.helpers.priest_world")
        local c = pw.Shadow.character()
        c.known[#c.known + 1], c.race = 13908, "Human"
        local H = headless.new({ character = c, pack = "Shadow (wowsims.com)" })
        local lhv = fake_lhv.new({
            now = function()
                return H.ctl.now
            end,
        })
        local major, minor = lhv:GetVersion()
        local stub = rawget(H.env, "LibStub")
        stub.libs[major], stub.minors[major] = lhv, minor
        H.Hekili.bandOff = false
        H.Hekili:ProvidersChanged()
        H.ctl.guid.target = "Creature-1"
        H.ctl.health, H.ctl.healthMax = 1000, 1000
        local S = H.Hekili.State
        assert.is_false(S.action.desperate_prayer.known)
        lhv:Push("health", "player", nil, 1000, 1000, H.ctl.now)
        for _ = 1, 14 do
            assert(headless.cycle(H, H.ctl.now + F))
        end
        H.ctl.combat = true
        H.ctl.Fire("PLAYER_REGEN_DISABLED")
        lhv:Push("health", "player", nil, 50, 1000, H.ctl.now) -- 5%: under every threshold
        for _ = 1, 30 do
            assert(headless.cycle(H, H.ctl.now + F))
            local out = H.Hekili.Engine.Output.Defensives
            for i = 1, out.count do
                assert.are_not.equal("desperate_prayer", out.recs[i].actionName)
            end
        end
    end)
end)
