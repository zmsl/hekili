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
            local ok, err = pcall(kit.RegisterAbility, kit, "list_ok", { id = 990302, [field] = { "known_a", "known_b" } })
            assert(ok, tostring(err))
            ok, err = pcall(F.Finish)
            assert(ok, tostring(err))
            ok, err = pcall(kit.RegisterAbility, kit, "list_nope", { id = 990303, [field] = { "known_a", "nope" } })
            assert(ok, tostring(err))
            ok, err = pcall(F.Finish)
            assert.is_false(ok, field)
            assert.is_truthy(tostring(err):find("V3: DRUID ability list_nope: " .. field .. " names nope", 1, true), err)
            ok, err = pcall(kit.RegisterAbility, kit, "list_bad", { id = 990304, [field] = { "known_a", 5 } })
            assert.is_false(ok, field)
            assert.is_truthy(tostring(err):find("V2: DRUID ability list_bad: " .. field, 1, true), err)
        end
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
    it("closes at the end of the real load: a later registration, the unknown-aura fallbacks, raises nothing", function()
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
    end)

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
