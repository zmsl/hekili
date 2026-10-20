-- tests/Forever/wowsims_levels_spec.lua (wowsims packs plan, Task 4): the leveling rule. A wowsims pack line may read
-- another ability's state only behind a known guard (tools/check_pack_levels.lua), so an ability a character has not
-- learned cannot block it; checked on every "(wowsims.com)" .simc in the repository.
local levels = assert(loadfile("tools/check_pack_levels.lua"))()
local engine = require("Forever.helpers.engine")

local ABIL = { strike = true, big_hit = true, stance = true }
local function isAbility(k)
    return ABIL[k] == true
end

describe("tools/check_pack_levels.lua", function()
    it("refuses an unguarded read of another ability and accepts the translator's guards", function()
        assert.are.same(
            { "cooldown.big_hit.remains" },
            levels.unguarded("cooldown.big_hit.remains>1.5", "strike", isAbility)
        )
        assert.are.same(
            {},
            levels.unguarded("(!action.big_hit.known|cooldown.big_hit.remains>1.5)", "strike", isAbility)
        )
        assert.are.same(
            {},
            levels.unguarded("!(action.stance.known&buff.stance.up)&rage.current>10", "strike", isAbility)
        )
        assert.are.same({}, levels.unguarded("cooldown.strike.remains<1&debuff.other_aura.up", "strike", isAbility))
        assert.are.same(
            { "buff.stance.up" },
            levels.unguarded("(!action.big_hit.known|cooldown.big_hit.ready)&buff.stance.up", "strike", isAbility)
        )
        assert.are.same({}, levels.unguarded("!action.big_hit.known&rage.current>=45", "strike", isAbility))
    end)

    it("refuses a guard of the wrong polarity, which blocks an unlearned ability like no guard", function()
        assert.are.same(
            { "cooldown.big_hit.remains" },
            levels.unguarded("(action.big_hit.known|cooldown.big_hit.remains>1.5)", "strike", isAbility)
        )
        assert.are.same(
            { "cooldown.big_hit.remains" },
            levels.unguarded("(!action.big_hit.known&cooldown.big_hit.remains>1.5)", "strike", isAbility)
        )
    end)

    it("wants the guard that drops the term: the & form in an or, the | form in an and, flipped by a not", function()
        assert.are.same(
            {},
            levels.unguarded("((action.big_hit.known&cooldown.big_hit.ready)|rage.current>10)", "strike", isAbility)
        )
        assert.are.same(
            { "cooldown.big_hit.ready" },
            levels.unguarded("((!action.big_hit.known|cooldown.big_hit.ready)|rage.current>10)", "strike", isAbility)
        )
        assert.are.same(
            { "cooldown.big_hit.ready" },
            levels.unguarded("((action.big_hit.known&cooldown.big_hit.ready)&rage.current>10)", "strike", isAbility)
        )
        assert.are.same(
            {},
            levels.unguarded("(!(!action.big_hit.known|cooldown.big_hit.ready)|rage.current>10)", "strike", isAbility)
        )
        assert.are.same(
            {},
            levels.unguarded("!((action.big_hit.known&buff.big_hit.up)|rage.current>10)", "strike", isAbility)
        )
        assert.are.same({}, levels.unguarded("(action.big_hit.known&cooldown.big_hit.ready)|x>1", "strike", isAbility))
    end)

    it("holds a group guard to the same position rule", function()
        local G = "(action.big_hit.known&cooldown.big_hit.ready)|(action.stance.known&buff.stance.up)"
        assert.are.same(
            {},
            levels.unguarded("(!(action.big_hit.known|action.stance.known)|(" .. G .. "))&x>1", "s", isAbility)
        )
        assert.are.same(
            {},
            levels.unguarded("((action.big_hit.known|action.stance.known)&(" .. G .. "))|x>1", "s", isAbility)
        )
        assert.are.same(
            { "guard action.big_hit.known|action.stance.known" },
            levels.unguarded("((action.big_hit.known|action.stance.known)&(" .. G .. "))&x>1", "s", isAbility)
        )
    end)

    it("reads a guard nested in another's guarded term, or under a not, at its own position", function()
        local P = "((energy.current-action.big_hit.cost)+10)<action.stance.cost"
        assert.are.same(
            {},
            levels.unguarded("(!action.stance.known|(!action.big_hit.known|" .. P .. "))&x>1", "s", isAbility)
        )
        assert.are.same(
            {},
            levels.unguarded("!((x>1&(!action.stance.known|(!action.big_hit.known|" .. P .. ")))|y>1)", "s", isAbility)
        )
        assert.are.same(
            {},
            levels.unguarded("((action.stance.known&(action.big_hit.known&!(" .. P .. ")))|y>1)", "s", isAbility)
        )
        -- the inner guard has the `|`-form's polarity where its outer guard's term must read false
        assert.are.same(
            { "action.big_hit.cost" },
            levels.unguarded("((action.stance.known&(!action.big_hit.known|" .. P .. "))|y>1)", "s", isAbility)
        )
        assert.are.same(
            { "action.big_hit.cost" },
            levels.unguarded("(!action.stance.known|(action.big_hit.known&" .. P .. "))&x>1", "s", isAbility)
        )
    end)

    it("takes a group guard of one repeated key as that key's guard", function()
        local T = "((action.big_hit.known|action.big_hit.known)|action.big_hit.known)"
        assert.are.same({}, levels.unguarded("(!" .. T .. "|cooldown.big_hit.ready)&x>1", "s", isAbility))
        assert.are.same({}, levels.unguarded("(" .. T .. "&cooldown.big_hit.ready)|x>1", "s", isAbility))
        assert.are.same(
            { "guard " .. T:sub(2, -2), "cooldown.big_hit.ready" },
            levels.unguarded("(" .. T .. "&cooldown.big_hit.ready)&x>1", "s", isAbility)
        )
        -- a group of two keys guards neither alone
        assert.are.same(
            { "cooldown.big_hit.ready" },
            levels.unguarded("(!(action.big_hit.known|action.stance.known)|cooldown.big_hit.ready)", "s", isAbility)
        )
    end)

    it("checks a dot read of another ability", function()
        assert.are.same({ "dot.big_hit.remains" }, levels.unguarded("dot.big_hit.remains<2", "strike", isAbility))
        assert.are.same({}, levels.unguarded("(!action.big_hit.known|dot.big_hit.remains<2)", "strike", isAbility))
    end)

    it("finds every wowsims pack line guarded", function()
        local pipe = assert(io.popen("ls src"))
        for addon in pipe:lines() do
            local root = "src/" .. addon .. "/APLs/"
            local ok, def = pcall(dofile, root .. "packs.lua")
            if ok and def.class then
                local abilities = engine.abilitySet(def.class).abilities
                local function isAb(k)
                    local a = abilities[k]
                    return type(a) == "table" and a.key == k
                end
                for _, name in ipairs(def.packs) do
                    if name:find("(wowsims.com)", 1, true) then
                        assert.are.same({}, levels.file(root .. name .. ".simc", isAb), name)
                    end
                end
            end
        end
        pipe:close()
    end)
end)

describe("the character's racials (engine.abilitySet)", function()
    local ws = require("Forever.helpers.wowsims")
    local ww = require("Forever.helpers.warrior_world")
    local RACIAL = { [20572] = "blood_fury", [20554] = "berserking", [1259813] = "eureka", [1259799] = "elunes_light" }

    it("reads the request's race as the client's token", function()
        local dir = os.tmpname()
        os.remove(dir)
        os.execute("mkdir -p '" .. dir .. "'")
        for spec, race in pairs({ orc_test = "RaceOrc", undead_test = "RaceUndead", elf_test = "RaceNightElf" }) do
            local f = assert(io.open(dir .. "/" .. spec .. ".json", "wb"))
            f:write(('{"raid":{"parties":[{"players":[{"race":"%s"}]}]}}'):format(race))
            f:close()
        end
        local saved = ws.DIR
        ws.DIR = dir .. "/"
        local got = { ws.race("orc_test"), ws.race("undead_test"), ws.race("elf_test") }
        ws.DIR = saved
        os.execute("rm -r '" .. dir .. "'")
        assert.are.same({ "Orc", "Scourge", "NightElf" }, got)
    end)

    it("reads the request's target creature type as target.creature_type's key", function()
        local dir = os.tmpname()
        os.remove(dir)
        os.execute("mkdir -p '" .. dir .. "'")
        for spec, mob in pairs({ undead_test = "MobTypeUndead", mech_test = "MobTypeMechanical" }) do
            local f = assert(io.open(dir .. "/" .. spec .. ".json", "wb"))
            f:write(('{"encounter":{"targets":[{"level":63,"mobType":"%s"}]}}'):format(mob))
            f:close()
        end
        local f = assert(io.open(dir .. "/none_test.json", "wb"))
        f:write('{"encounter":{"targets":[{"level":63}]}}')
        f:close()
        local saved = ws.DIR
        ws.DIR = dir .. "/"
        local got = { ws.creatureType("undead_test"), ws.creatureType("mech_test"), ws.creatureType("none_test") }
        ws.DIR = saved
        os.execute("rm -r '" .. dir .. "'")
        assert.are.same({ "undead", "mechanical" }, got)
        assert.is_nil(got[3])
    end)

    it("holds every race's racials as registered, off the GCD", function()
        local set = engine.abilitySet("WARRIOR")
        for id, key in pairs(RACIAL) do
            assert.are.same({ id, "off" }, { set.abilities[key].id, set.abilities[key].gcd })
        end
        assert.are.equal("Orc", set.racial.blood_fury)
        assert.are.same({ blood_fury = "Orc", shatter_curse = "Orc" }, engine.abilitySet("WARRIOR", "Orc").racial)
    end)

    it("knows the content race's racials from level 1, usable, and the replay maps their casts", function()
        local C = ws.content(ww, { level = 10, race = "Orc", learn = {} })
        local c = C.character()
        local known = {}
        for _, id in ipairs(c.known) do
            known[id] = true
        end
        assert.are.same({ "Orc", true, nil }, { c.race, known[20572], known[20554] })
        local H = require("Game.harness.headless").new({ character = c })
        local rows = {}
        for _, row in ipairs(C.usable(H)) do
            rows[row[1]] = true
        end
        assert.is_true(rows[20572])
        local R = require("Game.harness.replay").new(
            table.concat({
                "# wowsims 0123456789abcdef0123456789abcdef01234567 warrior_test seed 101 10 s target 63",
                "[0.00] [Arms (#1)] Casting {SpellID: 20572} (Cost = 0.000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)",
                "[0.00] [Arms (#1)] Completed cast {SpellID: 20572}",
            }, "\n"),
            H
        )
        assert.are.same({ "blood_fury", false }, { R.decisions[1].key, R.decisions[1].gcd })
    end)
end)
