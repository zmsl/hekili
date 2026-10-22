-- tests/Forever/shared_spec.lua (shared-content spec §3, §4, §8): Engine/Schema/Shared.lua's `Hekili:NewShared` and the shared
-- content files Hekili_Shared.toc lists (Shared/*.lua), loaded headless against a stand-in for Hekili's `all`; and no
-- priority, class, race, engine or shared file names a key the pass dropped, nor one it stubbed outside its stub.

local addons = require("helpers.addons")

-- Every shared content file Hekili_Shared.toc lists, in its order.
local SHARED = {}
for _, path in ipairs(addons.files("Hekili_Shared")) do
    local file = path:match("/Shared/(%w+)%.lua$")
    if file then
        SHARED[#SHARED + 1] = file
    end
end

-- Keys the pass removed from `all` (spec §4): absent on Forever, or unobservable in combat on the target.
local DROPPED = {
    "ancient_hysteria",
    "heroism",
    "time_warp",
    "netherwinds",
    "primal_rage",
    "drums_of_deathly_ferocity",
    "fury_of_the_aspects",
    "harriers_cry",
    "exhaustion",
    "insanity",
    "temporal_displacement",
    "fatigued",
    "sated",
    "sated_actual",
    "out_of_range",
    "stealable_magic",
    "dispellable_enrage",
    "all_absorbs",
    "unravel_absorb",
    "unusable_trinket",
    -- retail's consumables: Tempered Potion, Pact of Gluttony's Healthstone and talent
    "tempered_potion",
    "191387",
    "224464",
    "pact_of_gluttony",
}
-- Keys core reads by name (State.lua): id-less stubs in Hekili_Shared/Shared/Auras.lua, never up.
local STUBS = { "voidbinding", "voidform", "shadowform", "adrenaline_rush" }
-- Keys `all` gave up to the class or race file that registers them.
local OWNERS = {
    mark_of_the_wild = "Hekili_Druid/Druid.lua",
    battle_shout = "Hekili_Warrior/Warrior.lua",
    berserking = "Hekili_Shared/Races/Troll.lua",
    blood_fury = "Hekili_Shared/Races/Orc.lua",
    shadowmeld = "Hekili_Shared/Races/NightElf.lua",
    will_to_survive = "Hekili_Shared/Races/Human.lua",
    stoneform = "Hekili_Shared/Races/Dwarf.lua",
}

local function read(path)
    local f = assert(io.open(path))
    local s = f:read("*a")
    f:close()
    return s
end

-- Whether `src` names `key` as a whole word (an APL token, a table key, a string).
local function names(src, key)
    return src:find("%f[%w_]" .. key .. "%f[^%w_]") ~= nil
end

-- Whether `src` registers `key` with an id (`key = { id =` or `RegisterAura( "key", { id =`).
local function registers(src, key)
    return src:find("%f[%w_]" .. key .. '"?%s*[=,]%s*{[^}]-%f[%w_]id%s*=') ~= nil
end

describe("shared content", function()
    local all, ns, saved, debuffs, bags, controls

    -- Runs Engine/Schema/Races.lua, Engine/Schema/Shared.lua and the named shared files (default: every one Hekili_Shared.toc lists) against
    -- a stand-in `all` that registers as Engine/Schema/Spec.lua's RegisterAbility/RegisterAura: under the key, its id and
    -- every `copy` alias.
    local function load(files)
        all = { abilities = {}, auras = {}, exprs = {}, keys = { abilities = {}, auras = {} } }
        local function register(t, key, def)
            table.insert(all.keys[t == all.abilities and "abilities" or "auras"], key)
            t[key] = def
            if def.id then
                t[def.id] = def
            end
            for _, c in ipairs(type(def.copy) == "table" and def.copy or { def.copy }) do
                t[c] = def
            end
        end
        function all:RegisterAbility(key, def)
            register(self.abilities, key, def)
        end
        function all:RegisterAura(key, def)
            register(self.auras, key, def)
        end
        function all:RegisterStateExpr(key, fn)
            self.exprs[key] = fn
        end
        _G.Hekili = { State = { race_token = "BloodElf" }, Class = { specs = { [0] = all }, file = "WARRIOR" } }
        debuffs, bags, controls = {}, {}, {}
        ns = {
            Facade = {
                C_Item = {
                    GetItemCount = function(id)
                        return bags[id] or 0
                    end,
                    IsUsableItem = function()
                        return true
                    end,
                },
                C_LossOfControl = {
                    GetActiveLossOfControlData = function(i)
                        return controls[i]
                    end,
                    GetActiveLossOfControlDataCount = function()
                        return #controls
                    end,
                },
                -- the player's debuffs by index (name, count, dispel type, duration, expiration), unpacked in
                -- AuraUtil.UnpackAuraData's order: name, icon, count, dispel type, duration, expiration
                C_UnitAuras = {
                    GetDebuffDataByIndex = function(unit, i)
                        return unit == "player" and debuffs[i] or nil
                    end,
                },
                AuraUtil = {
                    UnpackAuraData = function(d)
                        if d then
                            return d[1], nil, d[2], d[3], d[4], d[5]
                        end
                    end,
                },
            },
        }
        _G.Hekili.Client = ns.Facade
        _G.Hekili.SCHOOL = require("Game.State.helpers.load").school() -- Auras.lua reads it at load
        assert(loadfile("src/Hekili/Engine/Schema/Races.lua"))("Hekili", ns)
        assert(loadfile("src/Hekili/Engine/Schema/Shared.lua"))("Hekili", ns)
        for _, f in ipairs(files or SHARED) do
            assert(loadfile(addons.root("Hekili_Shared") .. "Shared/" .. f .. ".lua"))()
        end
    end

    -- The keys registered into `all`'s `kind`, sorted.
    local function keys(kind)
        local out = { unpack(all.keys[kind]) }
        table.sort(out)
        return out
    end

    before_each(function()
        saved = { rawget(_G, "Hekili") or false, rawget(_G, "INVTYPE_WEAPONMAINHAND") or false }
        _G.INVTYPE_WEAPONMAINHAND = "Main Hand" -- the client's global string, read at load
    end)

    after_each(function()
        _G.Hekili, _G.INVTYPE_WEAPONMAINHAND = saved[1] or nil, saved[2] or nil
    end)

    it("writes every registration into `all`, for any race, and the modifiers into the race packs' lists", function()
        load({})
        local shared = _G.Hekili:NewShared()
        local a, b = { id = 1 }, { id = 2 }
        shared:RegisterAbility("x", a)
        shared:RegisterAura("x", b)
        shared:RegisterResourceMod({ max = 0.05 })
        local def = { aura = "x", pct = -0.1 }
        shared:RegisterCostMod(def)
        assert.are.same({ a, b }, { all.abilities.x, all.auras.x })
        assert.are.same({ { pct = 0.05 } }, ns.raceMods.maxMods)
        assert.are.equal(def, ns.raceMods.costMods[1])
    end)

    it("registers exactly Forever's shared auras: the external ones on the player and the stubs core reads", function()
        load({ "Auras" })
        assert.are.same({
            "adrenaline_rush",
            "bloodlust",
            "bloodlust_actual",
            "disoriented",
            "dispellable_curse",
            "dispellable_disease",
            "dispellable_magic",
            "dispellable_poison",
            "feared",
            "incapacitated",
            "loss_of_control",
            "main_hand_enchant",
            "off_hand_enchant",
            "power_infusion",
            "reversible_magic",
            "rooted",
            "shadowform",
            "snared",
            "stunned",
            "voidbinding",
            "voidform",
        }, keys("auras"))
        assert.are.same({ all.auras.incapacitated, all.auras.snared }, { all.auras.sapped, all.auras.slowed })
        assert.are.same({ 10060, 15 }, { all.auras.power_infusion.id, all.auras.power_infusion.duration })
        assert.are.same(
            { 0, 1 },
            { all.auras.main_hand_enchant.weaponEnchant, all.auras.off_hand_enchant.weaponEnchant }
        )
        assert.are.same({ "bloodlust_actual" }, all.auras.bloodlust.alias)
        assert.are.same({ 1245940, "player" }, { all.auras.bloodlust_actual.id, all.auras.bloodlust_actual.shared })
        for _, k in ipairs(STUBS) do
            assert.are.same({}, all.auras[k], k) -- no id: never found on a unit, so never up
        end
    end)

    it("answers locked_out_<school> from the active lockouts' school masks, until each one ends", function()
        load({ "Auras" })
        local schools = {}
        for k in pairs(all.exprs) do
            schools[#schools + 1] = k
        end
        table.sort(schools)
        assert.are.same({
            "locked_out_arcane",
            "locked_out_fire",
            "locked_out_frost",
            "locked_out_holy",
            "locked_out_nature",
            "locked_out_physical",
            "locked_out_shadow",
        }, schools)
        local env = { query_time = 11 }
        local function locked(school)
            return setfenv(all.exprs["locked_out_" .. school], env)()
        end
        assert.is_false(locked("fire"))
        controls[1] = { locType = "STUN", lockoutSchool = 0, startTime = 10, duration = 4, timeRemaining = 3 }
        controls[2] =
            { locType = "SCHOOL_INTERRUPT", lockoutSchool = 4 + 16, startTime = 10, duration = 4, timeRemaining = 3 }
        assert.are.same(
            { true, true, false, false },
            { locked("fire"), locked("frost"), locked("shadow"), locked("arcane") }
        )
        env.query_time = 14
        assert.is_false(locked("fire")) -- ended by the query time
    end)

    it("reads dispellable magic from the player's debuffs only, as a buff or a debuff", function()
        load({ "Auras" })
        debuffs[1] = { "Curse of Agony", 1, "Curse", 24, 30 }
        debuffs[2] = { "Polymorph", 0, "Magic", 10, 20 }
        for _, kind in ipairs({ "buff", "debuff" }) do
            local t = {}
            all.auras.dispellable_magic.generate(t, kind)
            assert.are.same({ 1, 20, 10, "nobody" }, { t.count, t.expires, t.applied, t.caster }, kind)
        end
    end)

    it("registers the potion action and auras core reads, and the Healthstone from Forever's items only", function()
        load({ "Consumables" })
        assert.are.same(
            { "demonic_rune", "healthstone", "major_mana_potion", "mana_gem", "potion", "thistle_tea" },
            keys("abilities")
        )
        assert.are.same({ "fake_potion", "potion" }, keys("auras"))
        assert.are.equal(all.abilities.potion, all.abilities.potion_default)
        assert.are.same({ "fake_potion" }, all.auras.potion.alias)
        assert.are.same(
            { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 },
            all.abilities.healthstone.items
        )
        assert.are.same(
            { 120, "off", "defensives" },
            { all.abilities.healthstone.cooldown, all.abilities.healthstone.gcd, all.abilities.healthstone.toggle }
        )
        assert.is_nil(all.abilities.healthstone.now or all.abilities.potion.now) -- item actions: no cast the belief sees
        for _, path in ipairs({ "src/Hekili/Engine/Sim/Core.lua", "src/Hekili/Options/DevTools.lua" }) do
            assert.is_false(names(read(path), "tempered_potion"), path) -- the `potion` verb's old fallback
        end
    end)

    it("registers Forever's mana and energy consumables (ItemSparse IDs), each offered only from the bags", function()
        load({ "Consumables" })
        local a = all.abilities
        -- item IDs from wowdb's ItemSparse (build 1.60.1.70338); the cooldowns from wowsims/forever's db.json (MIT)
        assert.are.same({ { 13444 }, 120 }, { a.major_mana_potion.items, a.major_mana_potion.cooldown })
        assert.are.same({ { 12662 }, 120 }, { a.demonic_rune.items, a.demonic_rune.cooldown })
        assert.are.same({ { 7676 }, 300 }, { a.thistle_tea.items, a.thistle_tea.cooldown })
        assert.are.same({ { 8008, 8007, 5513, 5514 }, 120 }, { a.mana_gem.items, a.mana_gem.cooldown })
        for _, key in ipairs({ "major_mana_potion", "demonic_rune", "thistle_tea", "mana_gem" }) do
            assert.are.same({ "off", false, true }, { a[key].gcd, a[key].startsCombat, a[key].bagItem }, key)
            assert.are.equal("potions", a[key].toggle, key) -- a resource consumable: under Potions (user, 2026-10-21)
            assert.is_nil(a[key].now, key) -- an item action: no cast the belief sees
            assert.is_false((a[key].usable()), key)
        end
        assert.are.equal(5514, a.mana_gem.item()) -- the lowest rank when none is in the bags
        bags[5513], bags[8007] = 1, 1
        assert.are.equal(8007, a.mana_gem.item()) -- the best one in the bags
        assert.is_true(a.mana_gem.usable())
        bags[7676] = 2
        assert.is_true(a.thistle_tea.usable())
    end)

    it("uses the best Healthstone in the bags, and the Minor one when there is none", function()
        load({ "Consumables" })
        local item = all.abilities.healthstone.item
        assert.are.equal(5512, item())
        bags[5509], bags[19007] = 1, 2
        assert.are.equal(5509, item())
    end)

    it("offers a Healthstone only with one in the bags, and only below full health", function()
        load({ "Consumables" })
        local usable = all.abilities.healthstone.usable
        local health = { current = 50, max = 100 }
        setfenv(usable, { health = health }) -- Engine/Schema/Spec.lua runs an ability's functions in `state`
        assert.are.same({ false, "requires healthstone in bags" }, { usable() })
        bags[19004] = 1
        assert.is_true(usable())
        health.current = 100
        assert.are.same({ false, "must be damaged" }, { usable() })
    end)

    it("potion's item and consumable run under Hekili's setfenv without touching a global state", function()
        load({ "Consumables" })
        local state = _G.Hekili.State -- the env is the state table itself, as in game: no `state` or `class` key
        state.args, state.settings, state.spec = {}, {}, {}
        for _, field in ipairs({ "item", "consumable" }) do
            local fn = all.abilities.potion[field]
            setfenv(fn, state)
            local ok, result = pcall(fn)
            assert.is_true(ok, field .. ": " .. tostring(result))
            assert.is_nil(result, field) -- no potion chosen
        end
    end)

    it("registers use_items, the slots Events.lua rebinds and an empty trinket map", function()
        load({ "Items" })
        assert.are.same({ "main_hand", "null_cooldown", "trinket1", "trinket2", "use_items" }, keys("abilities"))
        local a = all.abilities
        assert.are.same(
            { a.trinket1, a.trinket2, a.main_hand },
            { a.actual_trinket1, a.actual_trinket2, a.actual_main_hand }
        )
        assert.are.same({ "|cff00ccff[Main Hand]|r", false }, { a.main_hand.name, a.main_hand.usable })
        assert.are.same({}, _G.Hekili.Class.trinkets[12345])
    end)

    it("registers each shared key in one file only, every file Hekili_Shared.toc lists", function()
        load()
        assert.are.same({ "Auras", "Consumables", "Items" }, SHARED)
        for _, kind in ipairs({ "abilities", "auras" }) do
            local seen = {}
            for _, k in ipairs(all.keys[kind]) do
                assert.is_nil(seen[k], kind .. ": " .. k)
                seen[k] = true
            end
        end
    end)

    it(
        "leaves no dropped key in a priority, a class, race, engine or shared file, and no stub outside its own",
        function()
            local roots = { "src/Hekili/Engine/Schema" } -- the class pack roots below hold the APLs/packs.lua manifests
            for _, name in ipairs(addons.CONTENT) do
                roots[#roots + 1] = addons.root(name)
            end
            local ls = assert(io.popen("find " .. table.concat(roots, " ") .. " -name '*.lua' | sort"))
            local n = 0
            for path in ls:lines() do
                local src = read(path)
                for _, k in ipairs(DROPPED) do
                    assert.is_false(names(src, k), path .. ": " .. k)
                end
                -- A class file (a future Priest or Rogue) may register a stubbed key for real; its registration wins.
                if path ~= addons.root("Hekili_Shared") .. "Shared/Auras.lua" then
                    local class = path:find("^src/Hekili_%w+/")
                    for _, k in ipairs(STUBS) do
                        assert.is_true(class and registers(src, k) or not names(src, k), path .. ": " .. k)
                    end
                end
                n = n + 1
            end
            ls:close()
            assert.is_true(n > 10)
        end
    )

    it("leaves each key `all` gave up registered by its class or race file", function()
        local spec = read("src/Hekili/Engine/Schema/Spec.lua")
        for k, owner in pairs(OWNERS) do
            assert.is_true(names(read("src/" .. owner), k), owner .. ": " .. k)
            assert.is_false(names(spec, k), "Engine/Schema/Spec.lua: " .. k)
        end
    end)

    it(
        "every range setting of every class declares a numeric min and ceiling (the quick menu's slider needs both)",
        function()
            for _, loader in ipairs({ "Forever.helpers.load_warrior", "Forever.helpers.load_druid" }) do
                for key, s in pairs(require(loader).load().settings) do
                    local info = s.option
                    if info.type == "range" then
                        assert.are.equal("number", type(info.min), key .. " min")
                        assert.are.equal("number", type(info.max), key .. " max")
                    end
                end
            end
        end
    )
end)
