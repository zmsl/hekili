-- tests/Forever/ability_ranks_spec.lua (dry-pack-api): RegisterAbility's `ranks` and `effect`
-- (Engine/Schema/Spec/Ranks.lua). `ranks` derives what the packs' file-local `rest`, `knows` and `byRank` helpers
-- compute: checked against the helpers' own text, read out of Mage.lua and Warrior.lua (the two packs whose helpers
-- read the same), for every rank list those packs hand them. `effect` builds the sim `handler` and the belief `now` from
-- one factory: two closures, each in its own layer, doing the same.
local headless = require("Game.harness.headless")

local PACKS = { "src/Hekili_Mage/Mage.lua", "src/Hekili_Warrior/Warrior.lua" }

local function read(path)
    local f = assert(io.open(path))
    local s = f:read("*a")
    f:close()
    return s
end

-- The pack's own helper definitions, compiled over `knownRank`: returns rest, knows, byRank (nil where it has none).
local function helpers(src, knownRank)
    local body = { "local knownRank = ...", "local rest, knows, byRank" }
    for _, name in ipairs({ "rest", "knows", "byRank" }) do
        local def = src:match("\nlocal function " .. name .. "%(.-\nend\n")
        if def then
            body[#body + 1] = (def:gsub("^\nlocal function " .. name, "function " .. name))
        end
    end
    body[#body + 1] = "return rest, knows, byRank"
    return assert(loadstring(table.concat(body, "\n")))(knownRank)
end

-- A list argument: a literal `{ ... }` or a `local NAME = { ... }` (file level or in a block).
local function list(src, arg)
    local text = arg:sub(1, 1) == "{" and arg or src:match("\n%s*local " .. arg .. " = (%b{})")
    assert(text, "no list " .. arg)
    return assert(loadstring("return " .. text))()
end

-- Every rank list the pack hands rest/knows, and every (values, ids) pair it hands byRank.
local function uses(src)
    local lists, pairs_ = {}, {}
    for helper, arg in src:gmatch("(%f[%w]%a+)%(([%u_%d]+)%)") do
        if helper == "rest" or helper == "knows" then
            lists[arg] = true
        end
    end
    for arg in src:gmatch("%f[%w]knows%((%b{})%)") do
        lists[arg] = true
    end
    for values, ids in src:gmatch("%f[%w]byRank%(([%u_%d]+), ([%u_%d]+)%)") do
        pairs_[values .. " " .. ids] = { values, ids }
        lists[ids] = true
    end
    return lists, pairs_
end

describe("RegisterAbility's ranks and effect", function()
    local H, S, spec, ctl, n

    setup(function()
        H = headless.new()
        S, ctl = H.Hekili.State, H.ctl
        spec = H.Hekili.Class.specs[0]
        n = 0
    end)

    local function register(data)
        n = n + 1
        local key = "dry_ranks_" .. n
        spec:RegisterAbility(key, data)
        return spec.abilities[key]
    end

    -- Knows ranks 1..r of `ids` (none at 0), as the client's spellbook after SPELLS_CHANGED.
    local function learn(ids, r)
        for i, id in ipairs(ids) do
            ctl.known[id] = i <= r or nil
        end
        ctl.Fire("SPELLS_CHANGED")
    end

    for _, path in ipairs(PACKS) do
        it("derives id, copy and known as " .. path .. "'s rest and knows give them, at every known rank", function()
            local src = read(path)
            local rest, knows = helpers(src, H.ns.Facade.KnownRank)
            assert.is_function(rest)
            assert.is_function(knows)
            local lists, count = uses(src), 0
            for arg in pairs(lists) do
                local ids = list(src, arg)
                local a = register({ ranks = ids })
                assert.are.equal(ids[1], a.id, arg)
                assert.are.same(rest(ids), a.copy, arg)
                local known, want = a.funcs.known, knows(ids)
                for r = 0, #ids do
                    learn(ids, r)
                    assert.are.equal(want(), known(), arg .. " at rank " .. r)
                end
                learn(ids, 0)
                assert.is_nil(rawget(a, "ranks"), "ranks stays out of the record")
                count = count + 1
            end
            assert.is_true(count > 10, "found " .. count .. " rank lists")
        end)
    end

    it("reads a { byRank = values } field and state.byRank as Mage.lua's byRank, at every known rank", function()
        local src = read("src/Hekili_Mage/Mage.lua")
        local _, _, byRank = helpers(src, H.ns.Facade.KnownRank)
        assert.is_function(byRank)
        local _, uses_ = uses(src)
        local count = 0
        for _, u in pairs(uses_) do
            local values, ids = list(src, u[1]), list(src, u[2])
            local a = register({ ranks = ids, spend = { byRank = values }, spendType = "mana" })
            -- the field as declared (Races.lua's memoised `spend` wraps it, keyed by the state's changes only)
            local spend, want = rawget(a, "declaredSpend"), byRank(values, ids)
            for r = 0, #ids do
                learn(ids, r)
                assert.are.equal(want(), spend(), u[1] .. " at rank " .. r)
                assert.are.equal(want(), S.byRank(values, ids), u[1] .. " at rank " .. r)
            end
            learn(ids, 0)
            count = count + 1
        end
        assert.is_true(count > 10, "found " .. count .. " byRank uses")
    end)

    it("keeps an explicit copy and known, refuses an id that is not the first rank and byRank without ranks", function()
        local known = function()
            return true
        end
        local a = register({ ranks = { 990101, 990102 }, copy = "dry_alias", known = known })
        assert.are.same({ 990101, "dry_alias" }, { a.id, a.copy })
        assert.are.equal(known, a.funcs.known)
        assert.has_error(function()
            register({ ranks = { 990111, 990112 }, id = 990112 })
        end)
        assert.has_error(function()
            register({ id = 990121, spend = { byRank = { 1, 2 } } })
        end)
    end)

    -- A recording environment: each verb call appended to `log` as "verb arg arg".
    local function recorder(log)
        return setmetatable({}, {
            __index = function(_, verb)
                return function(...)
                    log[#log + 1] = table.concat({ verb, ... }, " ")
                end
            end,
        })
    end

    it(
        "builds the handler and the now from one effect: two closures, the handler under state, the same writes",
        function()
            local made = 0
            local a = register({
                id = 990201,
                effect = function()
                    made = made + 1
                    return function()
                        applyBuff("dry_aura") -- luacheck: ignore 113 (the layer's verb)
                        removeDebuff("target", "dry_debuff") -- luacheck: ignore 113 (the layer's verb)
                    end
                end,
            })
            local handler, now = a.handler, a.funcs.now
            assert.are.equal(2, made)
            assert.is_function(handler)
            assert.is_function(now)
            assert.are_not.equal(handler, now)
            assert.are.equal(S, getfenv(handler))
            assert.is_nil(a.funcs.effect)
            assert.is_nil(rawget(a, "effect"))
            local h, w = {}, {}
            setfenv(handler, recorder(h))()
            setfenv(now, recorder(w))()
            setfenv(handler, S)
            assert.are.same({ "applyBuff dry_aura", "removeDebuff target dry_debuff" }, h)
            assert.are.same(h, w)
        end
    )

    -- The recording loaders (load_druid, load_warrior) run the same derivation on the abilities they record, so a
    -- converted class file reads the same fields there as through the core.
    it("derives the same fields in the recording loader, its state.byRank over the loader's knownRank", function()
        local path = os.tmpname()
        local f = assert(io.open(path, "w"))
        f:write([[
local spec = Hekili:NewClass("MAGE", {})
local byRank = Hekili.State.byRank
spec:RegisterAbilities({
    dry = {
        ranks = { 990301, 990302, 990303 },
        spend = { byRank = { 10, 20, 30 } },
        cast = function()
            return byRank({ 1.5, 2, 2.5 }, { 990301, 990302, 990303 })
        end,
        effect = function()
            return function() end
        end,
    },
})
]])
        f:close()
        local ok, w = pcall(require("Forever.helpers.load_druid").load, nil, path, "MAGE")
        os.remove(path)
        assert(ok, w)
        local d = w.abilities.dry
        assert.are.same({ 990301, { 990302, 990303 } }, { d.id, d.copy })
        assert.is_false(d.known())
        assert.are.same({ 10, 1.5 }, { d.spend(), d.cast() })
        w.game.known[990302] = true
        assert.is_true(d.known())
        assert.are.same({ 20, 2 }, { d.spend(), d.cast() })
        assert.is_function(d.handler)
        assert.is_function(d.now)
        assert.is_nil(d.ranks)
        assert.is_nil(d.effect)
    end)

    it(
        "lets an explicit handler or now win over effect, and refuses a factory that returns one function twice",
        function()
            local mine = function() end
            local a = register({
                id = 990211,
                handler = mine,
                effect = function()
                    return function() end
                end,
            })
            assert.are.equal(mine, a.handler)
            assert.is_function(a.funcs.now)
            assert.are_not.equal(mine, a.funcs.now)
            local b = register({
                id = 990212,
                now = mine,
                effect = function()
                    return function() end
                end,
            })
            assert.are.equal(mine, b.funcs.now)
            assert.are_not.equal(mine, b.handler)
            local shared = function() end
            assert.has_error(function()
                register({
                    id = 990213,
                    effect = function()
                        return shared
                    end,
                })
            end)
        end
    )
end)
