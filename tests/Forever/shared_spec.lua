-- tests/Forever/shared_spec.lua (shared-content spec §3, §4, §8): Engine/Shared.lua's `Hekili:NewShared` and the shared
-- content files Hekili.toc lists (Forever/Shared/*.lua), loaded headless against a stand-in for Hekili's `all`; and no
-- priority, class, race, engine or shared file names a key the pass dropped, nor one it stubbed outside its stub.

-- Every shared content file Hekili.toc lists, in its order.
local SHARED = {}
for line in io.lines("src/Hekili/Hekili.toc") do
    local file = line:match("^Forever\\Shared\\(%w+)%.lua")
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
}
-- Keys core reads by name (State.lua): id-less stubs in Forever/Shared/Auras.lua, never up.
local STUBS = { "voidbinding", "voidform", "shadowform", "adrenaline_rush" }
-- Keys `all` gave up to the class or race file that registers them.
local OWNERS = {
    mark_of_the_wild = "Forever/Classes/Druid.lua",
    battle_shout = "Forever/Classes/Warrior.lua",
    berserking = "Forever/Races/Troll.lua",
    blood_fury = "Forever/Races/Orc.lua",
    shadowmeld = "Forever/Races/NightElf.lua",
    will_to_survive = "Forever/Races/Human.lua",
    stoneform = "Forever/Races/Dwarf.lua",
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

describe("shared content", function()
    local all, ns, saved, debuffs

    -- Runs Engine/Races.lua, Engine/Shared.lua and the named shared files (default: every one Hekili.toc lists) against
    -- a stand-in `all` that registers as Engine/Spec.lua's RegisterAbility/RegisterAura: under the key, its id and
    -- every `copy` alias.
    local function load(files)
        all = { abilities = {}, auras = {}, keys = { abilities = {}, auras = {} } }
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
        _G.Hekili = { State = { race_token = "BloodElf" }, Class = { specs = { [0] = all }, file = "WARRIOR" } }
        debuffs = {}
        ns = {
            Facade = {
                C_LossOfControl = {
                    GetActiveLossOfControlData = function() end,
                    GetActiveLossOfControlDataCount = function()
                        return 0
                    end,
                },
            },
            -- the player's debuffs by index: name, icon, count, dispel type, duration, expiration
            UnitDebuff = function(unit, i)
                local d = unit == "player" and debuffs[i]
                if d then
                    return d[1], nil, d[2], d[3], d[4], d[5]
                end
            end,
            UnitBuff = function()
                error("a shared aura reads the target's buffs")
            end,
        }
        assert(loadfile("src/Hekili/Engine/Races.lua"))("Hekili", ns)
        assert(loadfile("src/Hekili/Engine/Shared.lua"))("Hekili", ns)
        for _, f in ipairs(files or SHARED) do
            assert(loadfile("src/Hekili/Forever/Shared/" .. f .. ".lua"))("Hekili", ns)
        end
    end

    -- The keys registered into `all`'s `kind`, sorted.
    local function keys(kind)
        local out = { unpack(all.keys[kind]) }
        table.sort(out)
        return out
    end

    before_each(function()
        saved = rawget(_G, "Hekili") or false
    end)

    after_each(function()
        _G.Hekili = saved or nil
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
        assert.are.same({ "bloodlust_actual" }, all.auras.bloodlust.alias)
        assert.are.same({ 1245940, "player" }, { all.auras.bloodlust_actual.id, all.auras.bloodlust_actual.shared })
        for _, k in ipairs(STUBS) do
            assert.are.same({}, all.auras[k], k) -- no id: never found on a unit, so never up
        end
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

    it("leaves no dropped key in a priority, a class, race, engine or shared file, and no stub outside its own", function()
        local ls = assert(io.popen("find src/Hekili/Engine src/Hekili/Forever tools/packs -name '*.lua' | sort"))
        local n = 0
        for path in ls:lines() do
            local src = read(path)
            for _, k in ipairs(DROPPED) do
                assert.is_false(names(src, k), path .. ": " .. k)
            end
            -- A class file (a future Priest or Rogue) may register a stubbed key for real; its registration wins.
            if path ~= "src/Hekili/Forever/Shared/Auras.lua" and not path:find("^src/Hekili/Forever/Classes/") then
                for _, k in ipairs(STUBS) do
                    assert.is_false(names(src, k), path .. ": " .. k)
                end
            end
            n = n + 1
        end
        ls:close()
        assert.is_true(n > 10)
    end)

    it("leaves each key `all` gave up registered by its class or race file", function()
        local spec = read("src/Hekili/Engine/Spec.lua")
        for k, owner in pairs(OWNERS) do
            assert.is_true(names(read("src/Hekili/" .. owner), k), owner .. ": " .. k)
            assert.is_false(names(spec, k), "Engine/Spec.lua: " .. k)
        end
    end)
end)
