-- tests/Forever/fields_spec.lua (refactor plan lane 3, L1827): the pack field registry (Engine/Schema/Fields.lua) and
-- its load checks V1-V7. Every shipped pack, with every race, loads through the real Register* calls with zero findings
-- (V5's list is informational); a pack with a deliberate mistake (fixtures/fields_typo.lua) fails at load with a message
-- naming the pack, the object, the field and the check; V4 agrees with the belief's own rule (Families/Expect.lua).
-- FIELDS_V5=<path> writes V5's list there (the lane page's table).
local engine = require("Forever.helpers.engine")
local addons = require("helpers.addons")
local TYPOS = dofile("tests/Forever/fixtures/fields_typo.lua")

local CLASSES, RACES = {}, {}
for _, name in ipairs(addons.CONTENT) do
    local class = name ~= "Hekili_Shared" and name:match("^Hekili_(%w+)$")
    if class then
        CLASSES[#CLASSES + 1] = class:upper()
    end
end
for _, path in ipairs(addons.files("Hekili_Shared")) do
    if path:match("/Races/") then
        local f = assert(io.open(path))
        RACES[#RACES + 1] = assert(f:read("*a"):match('NewRace%("(%w+)"[,%)]'), path)
        f:close()
    end
end

local headless = require("Game.harness.headless")

-- A headless Druid through the real login (OnInitialize's ns.LoadContent); `o` adds to headless.new's options.
local function boot(o)
    o = o or {}
    o.character = {
        class = "DRUID",
        classID = 11,
        specID = 1483,
        level = 60,
        known = { 768, 5487, 5221 },
        power = { type = 3, token = "ENERGY", max = 100 },
    }
    return headless.new(o)
end

-- A fresh Druid load whose own registrations are already finished (so a later Finish sees the fixture's alone).
local function druid()
    local env = engine.load("DRUID")
    assert.are.same({}, env.loadErrors)
    env.ns.Fields.Finish()
    return env, env.ns.Fields
end

describe("the pack field registry", function()
    it("loads every shipped pack with every race with zero findings, V3 and V4 included", function()
        local v5, n = {}, 0
        for _, c in ipairs(CLASSES) do
            for _, race in ipairs(RACES) do
                local env = engine.load(c, race)
                assert.are.same({}, env.loadErrors, c .. " " .. race)
                local F = env.ns.Fields
                local ok, err = pcall(F.Finish)
                assert(ok, c .. " " .. race .. ": " .. tostring(err))
                assert.are.same({}, F.findings, c .. " " .. race)
                for _, line in ipairs(F.unlanded) do
                    if not v5[line] then
                        v5[line], n = true, n + 1
                    end
                end
            end
        end
        assert.is_true(n > 0) -- V5 lists; it refuses nothing yet
        local out = os.getenv("FIELDS_V5")
        if out then
            local list = {}
            for line in pairs(v5) do
                list[#list + 1] = line
            end
            table.sort(list)
            local f = assert(io.open(out, "w"))
            f:write(table.concat(list, "\n"), "\n")
            f:close()
        end
    end)

    -- A class with no pack (missing, another content API, a failed load): ns.LoadContent still finishes the load, so
    -- the shared and race content's references must resolve on their own.
    it("finishes a load with no class pack, with every race, with zero findings", function()
        for _, race in ipairs(RACES) do
            local env = engine.load("NOPACK", race)
            assert.are.same({}, env.loadErrors, race)
            assert.is_nil(rawget(env.class, "kit") or nil, race)
            local ok, err = pcall(env.ns.Fields.Finish)
            assert(ok, race .. ": " .. tostring(err))
            assert.are.same({}, env.ns.Fields.findings, race)
        end
    end)

    for _, t in ipairs(TYPOS) do
        it((t.passes and "accepts at load: " or "stops a pack's mistake at load: ") .. t.what, function()
            local env, F = druid()
            local kit = env.class.kit
            if t.pre then
                kit[t.pre[1]](kit, unpack(t.pre[2]))
            end
            local ok, err = pcall(kit[t.call], kit, unpack(t.args, 1, 4))
            if t.at == "finish" then
                assert(ok, tostring(err)) -- the call itself passes: the reference may register later
                ok, err = pcall(F.Finish)
            end
            if t.passes then
                assert(ok, tostring(err))
                for _, line in ipairs(F.unlanded) do
                    assert.is_falsy(line:find(t.args[1], 1, true), line)
                end
                return
            end
            if t.listed then
                assert(ok, tostring(err))
                assert.is_true(#F[t.listed] > 0)
                assert.is_truthy(F[t.listed][#F[t.listed]]:find(t.args[1], 1, true))
                return
            end
            assert.is_false(ok)
            err = tostring(err)
            assert.is_truthy(err:find("Hekili field check " .. t.check .. ":", 1, true), err)
            assert.is_truthy(err:find("DRUID", 1, true), err) -- the pack
            assert.is_truthy(err:find(t.field, 1, true), err)
            if t.call ~= "RegisterResource" then
                assert.is_truthy(err:find(t.args[1], 1, true), err) -- the object
            end
        end)
    end

    it("names the registered field the typo is one edit from", function()
        local env = druid()
        local ok, err = pcall(env.class.kit.RegisterAbility, env.class.kit, "x", { id = 1, refundOnAviod = true })
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("one edit from refundOnAvoid", 1, true), err)
    end)

    it("counts one insertion, removal, replacement or neighbour swap as one edit, nothing more", function()
        local near = druid().ns.Fields.Near
        for _, p in ipairs({
            { "refundOnAviod", "refundOnAvoid" },
            { "expect", "expects" },
            { "expectss", "expects" },
            { "expecta", "expects" },
            { "xepects", "expects" },
        }) do
            assert.is_true(near(p[1], p[2]), p[1])
        end
        for _, p in ipairs({ { "expects", "expects" }, { "exp", "expects" }, { "stcepxe", "expects" }, { "ab", "ba!" } }) do
            assert.is_false(near(p[1], p[2]), p[1])
        end
    end)

    -- decision 3a (fable-r3-decision.md): the engine reads a list on buff, nobuff and debuff (State.lua), so the rows
    -- take one, and V3 checks each of its entries
    it("3a: buff, nobuff and debuff take a list of auras, V3 checks each entry, V2 each entry's type", function()
        for _, field in ipairs({ "buff", "nobuff", "debuff" }) do
            local env, F = druid()
            local kit = env.class.kit
            kit:RegisterAura("known_a", { id = 990300 })
            kit:RegisterAura("known_b", { id = 990301 })
            local ok, err =
                pcall(kit.RegisterAbility, kit, "list_ok", { id = 990302, [field] = { "known_a", "known_b" } })
            assert(ok, tostring(err))
            ok, err = pcall(F.Finish)
            assert(ok, tostring(err))
            ok, err = pcall(kit.RegisterAbility, kit, "list_nope", { id = 990303, [field] = { "known_a", "nope" } })
            assert(ok, tostring(err))
            ok, err = pcall(F.Finish)
            assert.is_false(ok, field)
            assert.is_truthy(
                tostring(err):find("V3: DRUID ability list_nope: " .. field .. " names nope", 1, true),
                err
            )
            ok, err = pcall(kit.RegisterAbility, kit, "list_bad", { id = 990304, [field] = { "known_a", 5 } })
            assert.is_false(ok, field)
            assert.is_truthy(tostring(err):find("V2: DRUID ability list_bad: " .. field, 1, true), err)
        end
    end)

    -- decision 3b: range is number|fn (a function answers a number through the ability's funcs), so a ranked ability's
    -- { byRank = values } passes too; the usable check's range gate compares the answer
    it("3b: range takes a function or byRank; the range gate compares the number it answers", function()
        local env = druid()
        local kit = env.class.kit
        local fn = function()
            return 30
        end
        local ok, err = pcall(kit.RegisterAbility, kit, "range_fn", { id = 990400, range = fn })
        assert(ok, tostring(err))
        ok, err = pcall(
            kit.RegisterAbility,
            kit,
            "range_rank",
            { ranks = { 990401, 990402 }, range = { byRank = { 20, 30 } } }
        )
        assert(ok, tostring(err))
        ok, err = pcall(kit.RegisterAbility, kit, "range_neg", { id = 990403, range = -1 })
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("V2: DRUID ability range_neg: range is -1, below 0", 1, true), err)

        local H = boot()
        local cls, st = H.Hekili.Class, H.Hekili.State
        kit = cls.kit
        kit:RegisterAbility("range_fn", { id = 5221, range = fn })
        kit:RegisterAbility("range_rank", { ranks = { 5221, 990402 }, range = { byRank = { 20, 30 } } })
        cls.abilities.range_fn, cls.abilities.range_rank = kit.abilities.range_fn, kit.abilities.range_rank
        -- a target at 25 yards (the range library answers 20-25), the spell reaching 40; the belief polls it once
        H.ctl.inRange.target, H.ctl.distance.target, H.ctl.ranges[5221] = true, 25, { 0, 40 }
        H.ctl.level.target = 60
        H.Fire("PLAYER_TARGET_CHANGED")
        H.ctl.now = H.ctl.now + 0.2
        assert.is_true(headless.cycle(H, H.ctl.now))
        st.rangefilter = true
        assert.are.equal(20, cls.abilities.range_rank.range) -- rank 1 known: byRank's first value
        assert.are.same({ false, "not within ability-specified range (20)" }, { st:IsUsable("range_rank") })
        assert.is_true((st:IsUsable("range_fn"))) -- 30
        st.rangefilter = false
    end)

    -- decision 3c: one edit on a name of 2 or 3 letters is no evidence of a typo, so the rule compares a key only with
    -- names of 4 or more; a key near a shorter name is listed like any unknown key. Plural slips of longer names fail.
    it("3c: the one-edit rule compares only with registered names of 4 or more characters", function()
        local env, F = druid()
        local kit = env.class.kit
        for i, k in ipairs({ "cd", "icd", "ids" }) do
            local ok, err = pcall(kit.RegisterAbility, kit, "short_" .. k, { id = 990500 + i, [k] = 1 })
            assert(ok, tostring(err))
            assert.are.equal("DRUID ability short_" .. k .. ": " .. k .. " (V1)", F.findings[#F.findings])
        end
        local ok, err = pcall(kit.RegisterAura, kit, "short_di", { id = 990504, di = 1 })
        assert(ok, tostring(err))
        assert.are.equal("DRUID aura short_di: di (V1)", F.findings[#F.findings])
        for k, close in pairs({ rank = "ranks", buffs = "buff", spends = "spend", toggles = "toggle", cas = "cast" }) do
            ok, err = pcall(kit.RegisterAbility, kit, "slip_" .. k, { id = 990510, [k] = 1 })
            assert.is_false(ok, k)
            assert.is_truthy(
                tostring(err):find(
                    "V1: DRUID ability slip_" .. k .. ": " .. k .. " is one edit from " .. close,
                    1,
                    true
                ),
                err
            )
        end
        ok, err = pcall(kit.RegisterResource, kit, 1, { short_regen = { value = 1, ab = 2 } })
        assert.is_false(ok)
        assert.is_truthy(
            tostring(err):find("V1: DRUID regen", 1, true) and tostring(err):find("ab is no field", 1, true),
            err
        )
    end)

    -- decision 3d: only RegisterAbility converts { byRank = values } (Spec/Ranks.lua); elsewhere it would reach the
    -- consumer as a table, so V2 refuses it there
    it("3d: byRank passes only on an ability's function rows", function()
        local env = druid()
        local kit = env.class.kit
        local ranked = { byRank = { 9, 12 } }
        for _, c in ipairs({
            { "RegisterAura", { "rank_aura", { id = 990600, duration = ranked } }, "aura rank_aura: duration" },
            { "RegisterResource", { 3, nil, nil, { max = ranked } }, "meta", "max is a table" },
            { "RegisterResource", { 1, { rank_regen = { value = ranked } }, nil, nil }, "regen", "value is a table" },
        }) do
            local ok, err = pcall(kit[c[1]], kit, unpack(c[2], 1, 4))
            assert.is_false(ok, c[3])
            err = tostring(err)
            assert.is_truthy(err:find("V2: DRUID " .. c[3], 1, true) and err:find(c[4] or "is a table", 1, true), err)
        end
        local ok, err = pcall(kit.RegisterAbility, kit, "rank_spend", { ranks = { 990601, 990602 }, spend = ranked })
        assert(ok, tostring(err))
    end)

    -- decision 3e: the simulation divides by an aura's tick_time unguarded (0 raises in the client), an ability's 0 tick
    -- and a regen interval at or below 0 are declarations nothing reads; a meta decayInterval of 0 is continuous decay
    it("3e: tick_time and a regen interval are above 0; a meta decayInterval is at least 0", function()
        local env = druid()
        local kit = env.class.kit
        local function v2(call, args, what)
            local ok, err = pcall(kit[call], kit, unpack(args, 1, 4))
            assert.is_false(ok, what)
            assert.is_truthy(tostring(err):find("V2: DRUID " .. what, 1, true), err)
        end
        local function passes(call, args)
            local ok, err = pcall(kit[call], kit, unpack(args, 1, 4))
            assert(ok, tostring(err))
        end
        v2("RegisterAura", { "tt_aura", { id = 990700, tick_time = 0 } }, "aura tt_aura: tick_time is 0, not above 0")
        v2("RegisterAbility", { "tt_ab", { id = 990701, tick_time = 0 } }, "ability tt_ab: tick_time is 0, not above 0")
        v2("RegisterResource", { 1, { iv_zero = { value = 1, interval = 0 } }, nil, nil }, "regen")
        v2("RegisterResource", { 1, { iv_neg = { value = 1, interval = -1 } }, nil, nil }, "regen")
        v2("RegisterResource", { 3, nil, nil, { decayInterval = -1 } }, "meta")
        passes("RegisterResource", { 1, { iv_name = { value = 1, interval = "mainhand_speed" } }, nil, nil })
        local two = function()
            return 2
        end
        passes("RegisterResource", { 1, { iv_fn = { value = 1, interval = two } }, nil, nil })
        passes("RegisterResource", { 3, nil, nil, { decayInterval = 0 } })
    end)

    -- lane 6 (L1827 rows 1-3, 5): the facts the core guessed from key names are meta fields and a totem slot
    -- declaration, checked like any other
    it("r6: a resource meta declares onTarget, rest and points; a totem slot is a whole number 1 to 4", function()
        local env = druid()
        local kit = env.class.kit
        local function fails(call, args, what)
            local ok, err = pcall(kit[call], kit, unpack(args, 1, 4))
            assert.is_false(ok, what)
            assert.is_truthy(tostring(err):find(what, 1, true), err)
        end
        local ok, err = pcall(kit.RegisterResource, kit, 1, nil, nil, { onTarget = true, rest = "max", points = true })
        assert(ok, tostring(err))
        ok, err = pcall(kit.RegisterResource, kit, 1, nil, nil, { rest = "zero" })
        assert(ok, tostring(err))
        fails("RegisterResource", { 1, nil, nil, { rest = "full" } }, "V2: DRUID meta rage: rest is full, not one of")
        fails("RegisterResource", { 1, nil, nil, { onTarget = 1 } }, "V2: DRUID meta rage: onTarget is a number")
        fails("RegisterResource", { 1, nil, nil, { points = "yes" } }, "V2: DRUID meta rage: points is a string")
        ok, err = pcall(kit.RegisterTotemSlots, kit, { spirit = { slot = 2 }, light = { slot = 4 } })
        assert(ok, tostring(err))
        assert.are.same({ spirit = 2, light = 4 }, kit.totemSlots)
        fails("RegisterTotemSlots", { { a = { slot = 0 } } }, "V2: DRUID totem a: slot is 0, below 1")
        fails("RegisterTotemSlots", { { a = { slot = 5 } } }, "V2: DRUID totem a: slot is 5, above 4")
        fails("RegisterTotemSlots", { { a = { slot = 2.5 } } }, "V2: DRUID totem a: slot is 2.5, not a whole number")
        fails("RegisterTotemSlots", { { a = { slott = 1 } } }, "V1: DRUID totem a: slott is one edit from slot")
        fails("RegisterTotemSlots", { { a = { slot = 1, other = 1 } } }, "V1: DRUID totem a: other is no field")
    end)

    -- lane 6: every pack states what the core guessed from the key name before (Tracked.lua's ON_TARGET,
    -- Constants.lua's passive_regen and points, Now.lua's TOTEM_SLOT), with the same values
    it("r6: every shipped pack declares the facts the core guessed from its resources' names", function()
        local REST = { mana = true, focus = true, energy = true, essence = true }
        local POINTS = { combo_points = true, runes = true, soul_shards = true, holy_power = true, chi = true }
        POINTS.arcane_charges, POINTS.essence = true, true
        local seen = 0
        for _, c in ipairs(CLASSES) do
            local env = engine.load(c)
            assert.are.same({}, env.loadErrors, c)
            for k, r in pairs(env.class.kit.resources) do
                local meta = r.state.meta
                local what = c .. " " .. k
                assert.are.equal(REST[k] and "max" or nil, meta.rest, what)
                assert.are.equal(POINTS[k] or nil, meta.points, what)
                assert.are.equal(k == "combo_points" or nil, meta.onTarget, what)
                seen = seen + 1
            end
            local slots = c == "SHAMAN" and { fire = 1, earth = 2, water = 3, air = 4 } or {}
            assert.are.same(slots, env.class.kit.totemSlots, c)
        end
        assert.is_true(seen >= 13) -- every class's resources: 9 pools, 2 rages, 2 combo points
    end)

    it("has one row per field with a type, a doc line and its bounds in order", function()
        local F = druid().ns.Fields
        local n = 0
        for on, names in pairs(F.names) do
            for _, name in ipairs(names) do
                local r = F.rows[on][name]
                n = n + 1
                assert.is_truthy(r.type ~= "" and r.doc ~= "", name)
                assert.is_true(r.min == nil or r.max == nil or r.min <= r.max, name)
            end
        end
        assert.is_true(n > 100)
    end)

    it("V4: refuses exactly what the belief's own rule refuses (Families/Expect.lua X.Malformed)", function()
        local env, F = druid()
        local X = env.ns.VirtualStateInternal.Expect
        local SCHOOL = env.ns.SCHOOL
        -- the enum is the belief's kinds but its own `melee`
        local kinds = {}
        for k in pairs(X.KIND) do
            if k ~= "melee" then
                kinds[#kinds + 1] = k
            end
        end
        table.sort(kinds)
        local enum = {}
        for k in pairs(F.rows.ability.expects.enum) do
            enum[#enum + 1] = k
        end
        table.sort(enum)
        assert.are.same(kinds, enum)
        local dot = { dot = "debuff" }
        local buff = { dot = "buff" }
        local cases = {}
        for _, e in ipairs({ "none", "instant", "debuff", "travel", "strike", "ticks", "channel", "melee", "debuf" }) do
            for _, school in ipairs({ false, "fire", "bogus" }) do
                for _, v in ipairs({ false, 20, 0, -1 }) do
                    for _, swing in ipairs({ false, true }) do
                        for _, au in ipairs({ false, dot, buff }) do
                            cases[#cases + 1] = {
                                expects = e,
                                school = school or nil,
                                velocity = v or nil,
                                onNextSwing = swing or nil,
                                au = au or nil,
                            }
                        end
                    end
                end
            end
        end
        for _, d in ipairs(cases) do
            local belief = X.Malformed(d, d.expects, X.KIND[d.expects], d.school and SCHOOL[d.school] or nil, d.au)
            local core = F.Misfit(F.rows.ability.expects, d.expects)
                or d.school and F.Misfit(F.rows.ability.school, d.school)
                or d.velocity and F.Misfit(F.rows.ability.velocity, d.velocity)
                or F.Landing(d, d.au)
            local name = ("%s school=%s v=%s swing=%s dot=%s"):format(
                d.expects,
                tostring(d.school),
                tostring(d.velocity),
                tostring(d.onNextSwing),
                tostring(d.au and d.au.dot)
            )
            assert.are.equal(belief == nil, core == nil, name)
        end
    end)

    -- decision 4: the core's V4 finds the aura the belief is handed (Engine/Schema/Tracked.lua's aura compile: a primary
    -- key, a positive spell ID, the id-less weapon-enchant exception; the kit's before the shared spec's, as Activation
    -- merges them), so its verdict at the end of the load equals the belief's own at its build, aura lookup included
    it(
        "V4: the core's verdict equals the belief's at its build over the compiled def, aura lookups included",
        function()
            local H = boot()
            assert.are.same({}, H.loadErrors)
            local cls, F = H.Hekili.Class, H.ns.Fields
            local kit, shared = cls.kit, cls.specs[0]
            local TICKS = {
                num = 2,
                fn = function()
                    return 2
                end,
            }
            F.closed = false -- the checks on again, as during the load
            local cases, n = {}, 0
            for _, shape in ipairs({ "id", "idless", "copy", "shared", "enchant" }) do
                for _, tt in ipairs({ "num", "fn", "none" }) do
                    for _, dot in ipairs({ "debuff", "buff", "none" }) do
                        for _, e in ipairs({ "debuff", "ticks", "channel" }) do
                            n = n + 1
                            local key = ("v4_%s_%s_%s_%s"):format(shape, tt, dot, e)
                            local name, regKey, spec = key .. "_aura", key .. "_aura", kit
                            local aura = { tick_time = TICKS[tt], dot = dot ~= "none" and dot or nil }
                            if shape ~= "idless" and shape ~= "enchant" then
                                aura.id = 991000 + n
                            end
                            if shape == "copy" then -- the ability names the aura by a copy key only
                                regKey, aura.copy = key .. "_main", name
                            elseif shape == "shared" then
                                spec = shared
                            elseif shape == "enchant" then
                                aura.weaponEnchant = 0
                            end
                            spec:RegisterAura(regKey, aura)
                            kit:RegisterAbility(key, { id = 992000 + n, startsCombat = true, expects = e, aura = name })
                            local ok, err = pcall(F.Finish)
                            cases[#cases + 1] = { key = key, core = ok, err = err }
                        end
                    end
                end
            end
            F.closed = true
            H.Hekili:SpecializationChanged() -- class.* from the specs, then the belief's build (ns.BuildTracked)
            local A = H.ns.VirtualStateInternal.ab
            local index = {}
            for a = 1, A.n do
                index[A.key[a]] = a
            end
            local refused = 0
            for _, c in ipairs(cases) do
                local a = assert(index[c.key], c.key)
                assert.are.equal(A.expDeclared[a], c.core, c.key .. ": core " .. tostring(c.err))
                refused = refused + (c.core and 0 or 1)
            end
            assert.is_true(refused > 0 and refused < #cases)
        end
    )

    it("V6: a tunable row needs a source and a ledger row, and its default inside its bounds", function()
        local F = druid().ns.Fields
        local function v6(opt, default)
            local ok, err = pcall(F.Row, "aura", "tuned_x", "number", default, "a test row", opt)
            return ok, tostring(err)
        end
        local ok, err = v6({ tune = { source = "guessed", row = "L1" } }, 0.5)
        assert.is_false(ok)
        assert.is_truthy(err:find("V6", 1, true), err)
        ok, err = v6({ tune = { source = "measured" } }, 0.5)
        assert.is_false(ok)
        assert.is_truthy(err:find("V6", 1, true), err)
        ok, err = v6({ tune = { source = "measured", row = "L1" }, min = 0.35, max = 1.5 }, 2)
        assert.is_false(ok)
        assert.is_truthy(err:find("outside its bounds", 1, true), err)
        assert.is_true((v6({ tune = { source = "measured", row = "L1" }, min = 0.35, max = 1.5 }, 0.5)))
        -- and a pack's value of it stays inside the bounds (V2)
        local env = druid()
        F = env.ns.Fields
        F.Row("aura", "tuned_y", "number", 0.5, "a test row", { tune = { source = "ruling", row = "L1" }, min = 0.35 })
        ok, err = pcall(env.class.kit.RegisterAura, env.class.kit, "a", { id = 1, tuned_y = 0.1 })
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("V2", 1, true), err)
    end)

    it("V7: a field related to another is not below it on the same object", function()
        local env, F = druid()
        local ok, err = pcall(F.Row, "aura", "late_x", "number", nil, "a test row", { atLeast = "no_such_field" })
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("V7", 1, true), err)
        F.Row("aura", "deadline_x", "number", nil, "a test row")
        F.Row("aura", "takeback_x", "number", nil, "a test row", { atLeast = "deadline_x" })
        assert.is_true(
            (pcall(env.class.kit.RegisterAura, env.class.kit, "a", { id = 1, deadline_x = 1, takeback_x = 2 }))
        )
        ok, err = pcall(env.class.kit.RegisterAura, env.class.kit, "b", { id = 2, deadline_x = 1, takeback_x = 0.5 })
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("V7", 1, true), err)
    end)

    it("checks at the end of the real load (ns.LoadContent): nothing left queued, nothing listed", function()
        local notes = {}
        local H = boot({
            beforeLogin = function(core)
                local notify = core.Notify
                core.Notify = function(self, text, ...)
                    notes[#notes + 1] = tostring(text)
                    return notify(self, text, ...)
                end
            end,
        })
        assert.are.same({}, H.loadErrors)
        local F = H.ns.Fields
        assert.are.same({}, F.pending)
        assert.are.same({}, F.findings)
        assert.is_true(#F.unlanded > 0)
        for _, note in ipairs(notes) do -- decision 1: a valid load reports nothing (the priorities' notes may show)
            assert.is_falsy(note:find("load check", 1, true), note)
        end
        for _, e in ipairs(H.errors) do
            assert.is_falsy(e:find("field check", 1, true), e)
        end
    end)

    -- decision 2 (fable-r3-decision.md): once the load's end-of-load pass has run, a registration is not checked, so the
    -- simulation's unknown-aura fallbacks (Engine/Sim/State.lua applyBuff, applyDebuff: { duration = the caller's })
    -- log and register as before the registry, never raise in combat
    it(
        "closes at the end of the real load: a later registration, the unknown-aura fallbacks, raises nothing",
        function()
            local H = boot()
            assert.are.same({}, H.loadErrors)
            local F, kit, st = H.ns.Fields, H.Hekili.Class.kit, H.Hekili.State
            local findings = #F.findings
            for i, d in ipairs({ -1, math.huge - math.huge, "10" }) do
                local ok, err = pcall(kit.RegisterAura, kit, "late_" .. i, { duration = d })
                assert(ok, tostring(err))
                assert.is_truthy(rawget(kit.auras, "late_" .. i))
                local n = #H.errors
                ok, err = pcall(st.applyBuff, "late_buff_" .. i, d)
                assert(ok, tostring(err))
                assert.is_truthy(H.errors[n + 1] and H.errors[n + 1]:find("apply unknown buff", 1, true))
                assert.is_truthy(rawget(H.Hekili.Class.auras, "late_buff_" .. i))
                n = #H.errors
                ok, err = pcall(st.applyDebuff, "target", "late_debuff_" .. i, d)
                assert(ok, tostring(err))
                assert.is_truthy(H.errors[n + 1] and H.errors[n + 1]:find("apply unknown debuff", 1, true))
                assert.is_truthy(rawget(H.Hekili.Class.auras, "late_debuff_" .. i))
            end
            assert.are.same({}, F.pending)
            assert.are.equal(findings, #F.findings)
        end
    )

    -- decision 1 (fable-r3-decision.md): a failed end-of-load pass is reported and the addon goes on: OnInitialize
    -- finishes (the profile, /hekili, the launchers), the content notice carries the check's message once, the client's
    -- error handler hears it once and ns.Error logs it. A check that raised inside a pack file (the client reported it)
    -- joins the notice too. `register(shared)` runs before OnInitialize, on the shared spec.
    local function brokenBoot(register)
        local notes = {}
        local H = boot({
            beforeLogin = function(core)
                register(core.Class.specs[0])
                local notify = core.Notify
                core.Notify = function(self, text, ...)
                    notes[#notes + 1] = tostring(text)
                    return notify(self, text, ...)
                end
            end,
        })
        assert.are.same({}, H.loadErrors)
        assert.is_table(H.Hekili.DB and H.Hekili.DB.profile) -- InitializeProfile ran
        assert.is_truthy(H.env.SlashCmdList.ACECONSOLE_HEKILI) -- /hekili
        assert.is_function(rawget(H.env, "Hekili_OnAddonCompartmentClick")) -- CreateLaunchers ran
        assert.are.same({}, H.ns.Fields.pending)
        assert.is_true(H.ns.Fields.closed)
        return H, table.concat(notes, "\n")
    end

    local function count(s, part)
        local n, at = 0, 1
        while true do
            local i = s:find(part, at, true)
            if not i then
                return n
            end
            n, at = n + 1, i + #part
        end
    end

    -- The Finish failure `msg`: once in the notice, once to the error handler, once in ns.Error's log.
    local function reported(H, notice, msg)
        assert.are.equal(1, count(notice, msg), notice)
        local n = 0
        for _, e in ipairs(H.errors) do
            n = n + (e == msg and 1 or 0)
        end
        assert.are.equal(1, H.Hekili.ErrorDB[msg] and H.Hekili.ErrorDB[msg].n, msg) -- ns.Error, once
        assert.are.equal(2, n, msg) -- H.errors hears ns.Error and the error handler: the handler once
    end

    it("reports a V3 failure at the end of the load and goes on (notice, error handler, ns.Error)", function()
        local H, notice = brokenBoot(function(shared)
            shared:RegisterAura("broken_alias", { id = 990200, alias = { "no_such_aura" } })
        end)
        local msg = "Hekili field check V3: Shared aura broken_alias: alias names no_such_aura, which no registration "
            .. "declares (auras)"
        reported(H, notice, msg)
    end)

    it("reports a V4 failure at the end of the load and goes on", function()
        local H, notice = brokenBoot(function(shared)
            shared:RegisterAbility("broken_travel", { id = 990201, startsCombat = true, expects = "travel" })
        end)
        reported(H, notice, "Hekili field check V4: Shared ability broken_travel: expects travel needs velocity")
    end)

    it("adds a check that raised inside a pack file to the notice, once, beside the end-of-load failure", function()
        local v2 = "Hekili field check V2: Shared aura broken_duration: duration is -1, below 0"
        local H, notice = brokenBoot(function(shared)
            local ok, err = pcall(shared.RegisterAura, shared, "broken_duration", { id = 990202, duration = -1 })
            assert.are.same({ false, v2 }, { ok, err }) -- the client reports a pack file's raise itself
            shared:RegisterAura("broken_alias", { id = 990203, alias = { "no_such_aura" } })
        end)
        assert.are.equal(1, count(notice, v2), notice)
        for _, e in ipairs(H.errors) do
            assert.are_not.equal(v2, e) -- not handed on again: the client reported it
        end
        reported(
            H,
            notice,
            "Hekili field check V3: Shared aura broken_alias: alias names no_such_aura, which no registration "
                .. "declares (auras)"
        )
    end)
end)
