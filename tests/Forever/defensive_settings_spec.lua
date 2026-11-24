-- tests/Forever/defensive_settings_spec.lua (L1808, owner "Setting per line"): every shipped line that reads the
-- player's health reads its threshold from a per-spec setting (`settings.<action>_health`, a 1-100 slider), default
-- the wowsims or upstream value; a setting every pack reads (Healthstone, the healing potion) comes from the shared
-- content, registered on every spec of the class.
local headless = require("Game.harness.headless")
local dlw = require("Forever.helpers.druid_loop_world")
local ww = require("Forever.helpers.warrior_world")

-- [pack] = { character, { [setting key] = its default } }: def-1's restored lines (L1805) and the shared ones
local PACKS = {
    ["Guardian (wowsims.com)"] = {
        dlw.Guardian.character,
        { barkskin_health = 60, frenzied_regeneration_health = 25 },
    },
    ["Feral (wowsims.com)"] = { -- the imported Guardian lines read the same keys on Feral's own page
        dlw.Feral.character,
        { barkskin_health = 60, frenzied_regeneration_health = 25 },
    },
    ["Protection (wowsims.com)"] = {
        ww.Protection.character,
        {
            last_stand_health = 40,
            shield_wall_health = 35,
            stoneform_health = 50,
            shatter_curse_health = 50,
            healthstone_health = 30,
        },
    },
    -- (owner 2026-11-24) Protection Paladin's Stoneform: Protection Warrior's line and default, a Protection setting
    ["Protection (wowsims.com), Paladin"] = {
        require("Forever.helpers.paladin_world").Protection.character,
        { stoneform_health = 50, divine_shield_health = 20, lay_on_hands_health = 15, healthstone_health = 30 },
        pack = "Protection (wowsims.com)",
    },
}

describe("a shared setting", function()
    it("is registered on every spec of the class, the shared content's default (Healthstone 30)", function()
        local H = headless.new({ character = dlw.Guardian.character(), pack = "Guardian (wowsims.com)" })
        local n = 0
        for _, s in ipairs(H.Hekili.Class.kit.trees) do
            if not s.unsupported then
                local found
                for _, e in ipairs(s.settings) do
                    found = found or (e.name == "healthstone_health" and e)
                end
                assert.is_table(found, s.key)
                assert.are.equal(30, found.default)
                n = n + 1
            end
        end
        assert.are.equal(3, n)
    end)
end)

for label, P in pairs(PACKS) do
    local pack = P.pack or label
    describe("the health settings of " .. label, function()
        local H

        before_each(function()
            H = headless.new({ character = P[1](), pack = pack })
            assert.are.same({}, H.loadErrors)
        end)

        it("are registered with their default, a 1-100 slider each, and read by the lines", function()
            local S = H.Hekili.State
            local spec = H.Hekili.Class.specs[S.spec.id]
            local byKey = {}
            for _, e in ipairs(spec.settings) do
                byKey[e.name] = e
            end
            local text = {}
            for _, entries in pairs(H.Hekili.DB.profile.packs[pack].lists) do
                for _, e in ipairs(entries) do
                    text[#text + 1] = e.criteria or ""
                end
            end
            text = table.concat(text, "\n")
            for key, default in pairs(P[2]) do
                local e = assert(byKey[key], key)
                assert.are.equal(default, e.default, key)
                assert.are.equal("range", e.info.type, key)
                assert.are.same({ 1, 100 }, { e.info.min, e.info.max }, key)
                assert.are.equal("string", type(e.info.name()), key)
                assert.are.equal(default, S.settings[key], key) -- never nil: `health.pct<=nil` would raise
                assert.is_truthy(text:find("settings%." .. key .. "%f[^%w_]"), key)
            end
            -- no line compares the player's health with a bare number
            assert.is_nil(text:find("[^%w_.]health%.pct[<>=]+%d"))
        end)
    end)
end

-- L1808 (def-2 step 3): every pack's defensive lines beyond wowsims, each reading its own setting. [world module] =
-- { contents }, every shipped pack once; the class's own line(s) and their defaults; the shared ones in every pack.
local SHARED = { healthstone = { "healthstone_health", 30 }, healing_potion = { "healing_potion_health", 25 } }
local OWN = {
    druid = {
        Feral = { barkskin = { "barkskin_cat_health", 50 } },
        Balance = { barkskin = { "barkskin_health", 50 } },
        Guardian = {},
    },
    rogue = { evasion = { "evasion_health", 50 } },
    mage = { ice_block = { "ice_block_health", 15 } },
    paladin = { divine_shield = { "divine_shield_health", 20 }, lay_on_hands = { "lay_on_hands_health", 15 } },
    priest = {
        power_word_shield = { "power_word_shield_health", 50 },
        desperate_prayer = { "desperate_prayer_health", 40 },
    },
    hunter = { deterrence = { "deterrence_health", 35 } },
    warlock = { death_coil_defensive = { "death_coil_defensive_health", 35 } },
    shaman = {},
    warrior = {},
}
local WORLDS = {
    { "druid", dlw, { "Feral", "Balance", "Guardian" } },
    { "rogue", require("Forever.helpers.rogue_world"), { "Combat", "Assassination", "Subtlety" } },
    { "mage", require("Forever.helpers.mage_world"), { "Arcane", "Fire", "Frostfire", "Frost" } },
    { "paladin", require("Forever.helpers.paladin_world"), { "Retribution", "Protection", "HolyShock" } },
    { "priest", require("Forever.helpers.priest_world"), { "Shadow", "Smite" } },
    {
        "hunter",
        require("Forever.helpers.hunter_world"),
        { "Survival", "SurvivalMelee", "BeastMasteryTurret", "MarksmanshipTurret", "SurvivalTurret" },
    },
    {
        "warlock",
        require("Forever.helpers.warlock_world"),
        { "Affliction", "Demonology", "Destruction", "SMRuin", "ShadowBrand" },
    },
    { "shaman", require("Forever.helpers.shaman_world"), { "Enhancement", "Elemental" } },
    { "warrior", ww, { "Arms", "Fury", "Protection" } }, -- Arms: the module itself
}

for _, W in ipairs(WORLDS) do
    local class, mod = W[1], W[2]
    for _, name in ipairs(W[3]) do
        local C = rawget(mod, name) or mod
        local PACK = class == "warrior" and name .. " (wowsims.com)" or C.PACK -- Fury's and Protection's inherit Arms's
        describe("the defensive lines of " .. PACK, function()
            it("each read a 1-100 setting registered on the spec, the shared lines and the class's own", function()
                local H = headless.new({ character = C.character(), pack = PACK })
                assert.are.same({}, H.loadErrors)
                local S = H.Hekili.State
                local byKey = {}
                for _, e in ipairs(H.Hekili.Class.specs[S.spec.id].settings) do
                    byKey[e.name] = e
                end
                -- every line as built (an imported form's lists included): each health setting it reads is a number
                local cast = {} -- [action] = its lines' criteria, the default list's first
                for _, entries in pairs(H.Hekili.DB.profile.packs[PACK].lists) do
                    for _, e in ipairs(entries) do
                        local crit = e.criteria or ""
                        for key in crit:gmatch("settings%.([%w_]+_health)") do
                            assert.is_number(S.settings[key], PACK .. ": " .. key)
                            assert.are.equal("range", byKey[key].info.type, key)
                        end
                        cast[e.action] = cast[e.action] or {}
                        table.insert(cast[e.action], crit)
                    end
                end
                local own = class == "druid" and OWN.druid[name] or OWN[class]
                for _, set in ipairs({ SHARED, own }) do
                    for action, s in pairs(set) do
                        local key, default = s[1], s[2]
                        local found
                        for _, crit in ipairs(cast[action] or {}) do
                            -- first, or first in an import's group (`(...)&!buff.bear_form.up`, tools/make_pack.lua)
                            found = found
                                or ("&" .. crit):find("[&(]health%.known&health%.pct<=settings%." .. key .. "%f[^%w_]")
                        end
                        assert.is_truthy(found, PACK .. ": " .. action .. " reads " .. key)
                        assert.are.equal(default, byKey[key].default, key)
                        assert.are.equal(default, S.settings[key], key)
                        assert.are.equal("defensives", H.Hekili.Class.abilities[action].toggle, action)
                    end
                end
            end)
        end)
    end
end

-- L1808 (DEF-4): the healing potions, one key under Defensives; every potion's on-use is category 4, 120 s, the mana
-- potion's too (the wowsims pin's db.json), so either use starts the other's cooldown in the simulation
describe("the healing potion", function()
    it("is a Defensives item, best first, sharing the Major Mana Potion's cooldown both ways", function()
        local mw = require("Forever.helpers.mage_world")
        local H = headless.new({ character = mw.Arcane.character(), pack = mw.Arcane.PACK })
        assert.are.same({}, H.loadErrors)
        local a = H.Hekili.Class.abilities.healing_potion
        assert.are.equal("defensives", a.toggle)
        assert.are.equal(13446, a.items[1])
        assert.are.equal(11, #a.items)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        local S = H.Hekili.State
        S.reset("Primary")
        assert.are.equal(0, S.cooldown.major_mana_potion.true_remains)
        S.runHandler("healing_potion")
        assert.is_true(S.cooldown.major_mana_potion.true_remains > 100)
        S.reset("Primary")
        assert.are.equal(0, S.cooldown.healing_potion.true_remains)
        S.runHandler("major_mana_potion")
        assert.is_true(S.cooldown.healing_potion.true_remains > 100)
    end)
end)

-- L1808 (def-2 part 2, item 3): the shared lines' sliders name their item in the player's language: the client's item
-- name (plain) when it has the item, else the shared content's own string (Hekili_Shared's locale files)
describe("the Healthstone and healing potion sliders", function()
    local function label(H, key)
        local S = H.Hekili.State
        for _, e in ipairs(H.Hekili.Class.specs[S.spec.id].settings) do
            if e.name == key then
                return e.info.name()
            end
        end
    end

    it("read the shared content's string when the client has no item name yet (English, French)", function()
        local H = headless.new({ character = ww.Protection.character(), pack = "Protection (wowsims.com)" })
        assert.are.equal("Healthstone: once health is under (%)", label(H, "healthstone_health"))
        assert.are.equal("Healing Potion: once health is under (%)", label(H, "healing_potion_health"))
        local fr =
            headless.new({ character = ww.Protection.character(), pack = "Protection (wowsims.com)", locale = "frFR" })
        assert.is_truthy(label(fr, "healthstone_health"):find("Pierre de soins", 1, true))
        assert.is_truthy(label(fr, "healing_potion_health"):find("Potion de soins", 1, true))
    end)

    it("read the client's item name when it has one", function()
        local H = headless.new({
            character = ww.Protection.character(),
            pack = "Protection (wowsims.com)",
            beforeLogin = function(core)
                core.Client.C_Item.GetItemInfo = function(id)
                    return ({ [5509] = "Client Stone", [929] = "Client Potion" })[id]
                end
            end,
        })
        assert.are.equal("Client Stone: once health is under (%)", label(H, "healthstone_health"))
        assert.are.equal("Client Potion: once health is under (%)", label(H, "healing_potion_health"))
    end)
end)

-- def-2 review Minors 4 and 5: the two Barkskin sliders on Feral's and Guardian's pages say which form each is for
-- (the form's name in the client); Desperate Prayer's slider shows only for a Dwarf priest (its line's race)
describe("the health sliders", function()
    local function entry(H, key)
        local S = H.Hekili.State
        local found
        for _, e in ipairs(H.Hekili.Class.specs[S.spec.id].settings) do
            if e.name == key then
                found = e
            end
        end
        return assert(found, key)
    end

    for _, P in ipairs({ { "Feral", "Feral (wowsims.com)" }, { "Guardian", "Guardian (wowsims.com)" } }) do
        it("tell the two Barkskin sliders apart by form (" .. P[1] .. ")", function()
            local H = headless.new({ character = dlw[P[1]].character(), pack = P[2] })
            local bear, cat = entry(H, "barkskin_health").info.name(), entry(H, "barkskin_cat_health").info.name()
            assert.are_not.equal(bear, cat)
            local A = H.Hekili.Class.abilities -- the forms' names, as the client gives them
            assert.is_truthy(bear:find("(" .. A.bear_form.name .. ")", 1, true), bear)
            assert.is_truthy(cat:find("(" .. A.cat_form.name .. ")", 1, true), cat)
        end)
    end

    it("show Desperate Prayer's only for a Dwarf priest", function()
        local pw = require("Forever.helpers.priest_world")
        for race, hidden in pairs({ Dwarf = false, Human = true }) do
            local c = pw.Shadow.character()
            c.race = race
            local H = headless.new({ character = c, pack = "Shadow (wowsims.com)" })
            local info = entry(H, "desperate_prayer_health").info
            assert.are.equal(hidden, info.hidden ~= nil and info.hidden() == true, race)
        end
    end)
end)

-- (owner 2026-11-24) Protection Paladin's Stoneform threshold is that spec's own setting, not a shared one: a shared
-- `<action>_health` would give every pack of every class the line (translator rule 25)
describe("Protection Paladin's Stoneform setting", function()
    it("is registered on Protection, not on Retribution", function()
        local pw = require("Forever.helpers.paladin_world")
        local function has(C)
            local H = headless.new({ character = C.character(), pack = C.PACK })
            for _, e in ipairs(H.Hekili.Class.specs[H.Hekili.State.spec.id].settings) do
                if e.name == "stoneform_health" then
                    return true
                end
            end
            return false
        end
        assert.is_true(has(pw.Protection))
        assert.is_false(has(pw.Retribution))
    end)
end)
