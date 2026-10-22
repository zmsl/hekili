-- tests/Game/State/expect_spec.lua (unit-registry spec §5): each ability's declared outcome compiled at build: the
-- type's kind, its school and velocity, a ticking kind's aura (resolved as the simulation does: cycle, aura, key)
-- whose period and count are read at the commit, the default type when absent, and a malformed declaration reported
-- once and falling back to the default.
local load = require("Game.State.helpers.load")
local fs = require("Game.State.helpers.fake_spec")

describe("expectation compile", function()
    local ns, I, A, X

    local function build(h)
        ns = load.module()
        I = ns.VirtualStateInternal
        A, X = I.ab, I.Expect
        I.Build(fs.def(h or fs.new(9, false, false, true)), 1)
    end

    -- kind, school, declared, velocity, tick count, period
    local function of(id)
        local a = A.bySpell[id]
        local period, count = X.Tick(a)
        return A.expKind[a], A.school[a], A.expDeclared[a], A.velocity[a], count, period
    end

    -- spender_a (def.abilities[1]) with `fields` set; `auras` { [aura key] = { field = value } } set on the fake
    -- spec's auras: kind, school, errors counted, the last error
    local function one(fields, auras)
        local h = fs.new(9)
        for k, v in pairs(fields) do
            h.Class.abilities.spender_a[k] = v
        end
        for key, f in pairs(auras or {}) do
            for k, v in pairs(f) do
                h.Class.auras[key][k] = v
            end
        end
        build(h)
        return A.expKind[1], A.school[1], I.nowErrors, I.nowError
    end

    it("compiles each declared type with its fields; a ticking one from its aura at the commit", function()
        build()
        assert.are.same({ X.FLIGHT, 8, true, 20, 0, 0 }, { of(fs.SPENDER_P) })
        assert.are.same({ X.FRAME, 4, true, 0, 0, 0 }, { of(fs.SPENDER_F) })
        assert.are.same({ X.FRAME, 64, true, 0, 4, 3 }, { of(fs.SPENDER_M) }) -- its aura: 12 s / 3 s, a debuff dot
        assert.are.same({ X.TICKS, 8, true, 40, 5, 3 }, { of(fs.SPENDER_S) }) -- 15 s / 3 s
        assert.are.same({ X.CHANNEL, 64, true, 0, 3, 1 }, { of(fs.SPENDER_H) }) -- 3 s / 1 s
        assert.are.same({ X.NONE, 0, true, 0, 0, 0 }, { of(fs.SPENDER_N) })
        assert.is_true(A.ticking[A.bySpell[fs.SPENDER_M]])
        assert.is_false(A.ticking[A.bySpell[fs.SPENDER_F]])
    end)

    it("maps an absent expects to today's behaviour; a channeled ability stays on it", function()
        build()
        local k, sc, d = of(fs.SPENDER_B)
        assert.are.same({ X.STRIKE, X.ANY, false }, { k, sc, d })
        assert.are.equal(X.FRAME, (of(fs.SPENDER_C)))
        assert.are.equal(X.ANY, select(2, of(fs.SPENDER_C)))
        assert.are.equal(X.NONE, (of(fs.SPENDER_A)))
        local kind = one({ startsCombat = true, channeled = true }, { spender_a = { tick_time = 1 } })
        assert.are.equal(X.FRAME, kind) -- CHANNEL is opt-in
    end)

    it("resolves the aura as the simulation does: cycle, else aura, else the ability's key", function()
        one({ expects = "ticks", school = "shadow", aura = "spender_c", cycle = "spender_a" }, {
            spender_a = { tick_time = 4, duration = 20, dot = "debuff" },
            spender_c = { tick_time = 3, dot = "debuff" },
        })
        assert.are.same({ 4, 5 }, { X.Tick(1) }) -- the cycle aura's 20 s / 4 s
        one(
            { expects = "ticks", school = "shadow", aura = "spender_c" },
            { spender_c = { tick_time = 5, dot = "debuff" } }
        )
        assert.are.same({ 5, 3 }, { X.Tick(1) }) -- the aura field's 15 s / 5 s
    end)

    it("infers an instant's ticks from its aura's tick_time and dot = \"debuff\", never from either alone", function()
        one({ expects = "instant", school = "fire" }, { spender_a = { tick_time = 3, duration = 9 } })
        assert.is_false(A.ticking[1])
        one({ expects = "instant", school = "fire" }, { spender_a = { tick_time = 3, duration = 9, dot = "debuff" } })
        assert.is_true(A.ticking[1])
        assert.are.same({ 3, 3 }, { X.Tick(1) })
        one({ startsCombat = true }, { spender_a = { tick_time = 3, duration = 9, dot = "debuff" } })
        assert.is_false(A.ticking[1]) -- a default type keeps today's behaviour
    end)

    it("calls a function duration in Hekili's own state at the commit, not at the build", function()
        local n, rank = 0, 1
        local h = fs.new(9, false, false, true)
        h.Class.auras.spender_m.duration = function()
            n = n + 1
            return rank > 1 and 12 or 9
        end
        build(h)
        assert.are.equal(0, n)
        assert.are.same({ 3, 3 }, { X.Tick(A.bySpell[fs.SPENDER_M]) })
        rank = 2
        assert.are.same({ 3, 4 }, { X.Tick(A.bySpell[fs.SPENDER_M]) })
    end)

    -- An aura as Engine/Schema/Spec.lua's RegisterAura leaves it: the declared tick_time kept as `base_tick_time`
    -- (a number on the aura, or a function in `funcs`) and `funcs.tick_time` the haste wrapper the __index runs.
    local function registered(key, declared, duration)
        local au = { key = key, id = 1, duration = duration, dot = "debuff", funcs = {} }
        au.funcs.tick_time = function()
            return 99 -- the haste-wrapped period: never the ticket's
        end
        if type(declared) == "function" then
            au.funcs.base_tick_time = declared
        else
            au.base_tick_time = declared
        end
        return setmetatable(au, {
            __index = function(t, k)
                if t.funcs[k] then
                    return t.funcs[k]()
                end
            end,
        })
    end

    for _, case in ipairs({
        { "a number", 3, 4 },
        {
            "a function",
            function()
                return 2
            end,
            6,
        },
    }) do
        it(
            "reads a registered aura's declared tick_time when it is " .. case[1] .. ", not the haste wrapper",
            function()
                local h = fs.new(9)
                h.Class.abilities.spender_a.expects = "ticks"
                h.Class.auras.spender_a = registered("spender_a", case[2], 12)
                build(h)
                assert.are.equal(X.TICKS, A.expKind[1])
                assert.are.same({ 12 / case[3], case[3] }, { X.Tick(1) })
            end
        )
    end

    it("reports a malformed declaration once and falls back to the default type", function()
        build()
        local k, sc, d = of(fs.SPENDER_Q)
        assert.are.same({ X.FRAME, X.ANY, false }, { k, sc, d })
        assert.are.equal(1, I.nowErrors)
        assert.is_truthy(I.nowError:find("spender_q unknown expects bogus", 1, true))
    end)

    for _, case in ipairs({
        { { expects = "travel", school = "nature" }, nil, "travel needs velocity" },
        { { expects = "ticks" }, nil, "ticks needs an aura with tick_time and dot" },
        { { expects = "ticks" }, { spender_a = { tick_time = 3 } }, "ticks needs an aura with tick_time and dot" },
        { { expects = "channel" }, nil, "channel needs an aura with tick_time" },
        { { expects = "strike" }, nil, "strike needs onNextSwing" },
        { { expects = "melee" }, nil, "expects melee is the engine's own" },
        { { expects = "instant", school = "fel" }, nil, "unknown school fel" },
        { { expects = "instant", school = 8 }, nil, "unknown school 8" },
        { { expects = "travel", velocity = "fast" }, nil, "velocity is not a number" },
    }) do
        it("rejects " .. case[3], function()
            local kind, school, errors, err = one(case[1], case[2])
            assert.are.same({ X.NONE, X.ANY, 1 }, { kind, school, errors })
            assert.is_truthy(err:find(case[3], 1, true))
        end)
    end

    it("keeps a declared school on a default type", function()
        local kind, school, errors = one({ startsCombat = true, school = "frost" })
        assert.are.same({ X.FRAME, 16, 0 }, { kind, school, errors })
    end)
end)
