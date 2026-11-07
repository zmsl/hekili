-- tests/Forever/wowsims_pin_spec.lua (wowsims packs plan, Task 2; check_wowsims_pin): every checked-in wowsims log
-- comes from the wowsims/forever commit tools/wowsims/export.lua pins for its spec (M.pin), every recipe has its request and log, and the
-- exporter's pure parts (the talent string, the request) hold. Data: wowsims/forever (MIT).
local ex = assert(loadfile("tools/wowsims/export.lua"))()

local function exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
    end
    return f ~= nil
end

local function tmp(text)
    local path = os.tmpname()
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
    return path
end

local function recipes()
    local out, pipe = {}, assert(io.popen("ls tools/wowsims/specs"))
    for file in pipe:lines() do
        out[#out + 1] = file:match("^(.+)%.lua$")
    end
    pipe:close()
    return out
end

local function sh(cmd) -- the command's stdout+stderr and whether it exited 0
    local pipe = assert(io.popen(cmd .. " 2>&1; echo rc=$?"))
    local s = pipe:read("*a")
    pipe:close()
    return s, s:find("rc=0\n$") ~= nil
end

local lua = io.open(".lua/bin/lua", "rb") and ".lua/bin/lua" or "lua5.1"

describe("check_wowsims_pin", function()
    it("finds every recipe's log made at its spec's pinned wowsims commit, beside its request", function()
        for _, spec in ipairs(recipes()) do
            assert.is_true(exists(ex.OUT .. spec .. ".json"), spec)
            local f = assert(io.open(ex.OUT .. spec .. ".log", "rb"), spec)
            local first = f:read("*l")
            f:close()
            assert.are.equal(ex.pin(spec), first:match("^# wowsims (%x+) "), spec)
            assert.are.equal(spec, first:match("^# wowsims %x+ (%S+) "), spec)
        end
    end)

    -- The transitional per-spec pin (docs/dev/wowsims-packs.md "Moving the pin"): every spec is at the old pin or the
    -- new one, so once every line says NEW the tooling is at one global pin again.
    it("pins every recipe, and only recipes, to the old or the new pin, each with its oracle patch set", function()
        assert.are.equal(40, #ex.OLD_PIN)
        assert.are.equal(40, #ex.NEW_PIN)
        local seen = {}
        for _, spec in ipairs(recipes()) do
            local pin = ex.SPEC_PIN[spec]
            assert.is_true(pin == ex.OLD_PIN or pin == ex.NEW_PIN, spec)
            assert.are.equal(pin, ex.pin(spec))
            seen[spec] = true
            local f = io.open("tools/wowsims/sim-pin/" .. pin:sub(1, 12) .. "/no-cast-end-pick.patch", "rb")
            assert.is_truthy(f, spec .. ": no oracle patch set for its pin")
            f:close()
        end
        for spec in pairs(ex.SPEC_PIN) do
            assert.is_true(seen[spec], spec .. " has no recipe")
        end
        assert.has_error(function()
            ex.pin("no_such_spec")
        end)
    end)

    it("refuses an export from a checkout not at the spec's pin, naming the spec and its pin", function()
        local repo = os.tmpname()
        os.remove(repo)
        assert(
            os.execute(
                ("git init -q %s && git -C %s -c user.name=t -c user.email=t@t commit -q --allow-empty -m x"):format(
                    repo,
                    repo
                )
            ) == 0
        )
        local out, ok = sh(
            ('WOWSIMS=%s %s -e \'loadfile("tools/wowsims/export.lua")().checkout("druid_balance")\''):format(repo, lua)
        )
        local built, builtOk = sh("sh tools/wowsims/sim-pin/build.sh " .. repo)
        os.execute("rm -rf " .. repo)
        assert.is_false(ok)
        assert.is_truthy(out:find("druid_balance", 1, true), out)
        assert.is_truthy(out:find(ex.pin("druid_balance"), 1, true), out)
        assert.is_false(builtOk) -- build.sh: a checkout at no pin of export.lua's has no oracle patch set
        assert.is_truthy(built:find("not at a pin", 1, true), built)
    end)

    it("asks for no execute phase the pin's sim no longer reads (25, 45, 90 gone; 20 and 35 kept)", function()
        assert.is_nil(ex.ENCOUNTER.executeProportion25)
        assert.is_nil(ex.ENCOUNTER.executeProportion45)
        assert.is_nil(ex.ENCOUNTER.executeProportion90)
        assert.are.equal(0.2, ex.ENCOUNTER.executeProportion20)
        assert.are.equal(0.35, ex.ENCOUNTER.executeProportion35)
    end)

    it("reads a siml recipe's build from the converted <spec>.build.json under M.OUT, not the checkout", function()
        local base = os.tmpname() -- creates an empty file: removed below with the build
        local out = base .. "_" -- M.OUT is a path prefix
        local path = out .. "some_spec.build.json"
        local f = assert(io.open(path, "wb"))
        f:write('{"player":{"class":"ClassHunter","talentsString":"5","equipment":{"items":[{"id":9}]}}}')
        f:close()
        local saved = ex.OUT
        ex.OUT = out
        local ok, req = pcall(ex.request, { name = "Siml", siml = "x" }, "/no/such/checkout", "some_spec")
        ex.OUT = saved
        os.remove(path)
        os.remove(base)
        assert.is_true(ok, tostring(req))
        local p = req.raid.parties[1].players[1]
        assert.are.same({ "Siml", "5", 9 }, { p.name, p.talentsString, p.equipment.items[1].id })
    end)

    -- The hunter builds carry no race, professions, consumables or player buffs: siml.LoadBuild (sim/siml/build.go:25-30,
    -- 54-62) keeps the spec's defaults.siml values for those when the build leaves them unset, and the site does the same
    -- (ui/app/apply_build_files.test.ts). Checked by hand against sim/siml/testdata/builds/hunter_dps_*_weave.json.
    it("fills the keys a siml build leaves unset from the spec's defaults, as siml.LoadBuild does", function()
        local p = { race = "RaceTroll", talentsString = "5" }
        local d = {
            race = "RaceOrc",
            profession1 = "Engineering",
            profession2 = "Blacksmithing",
            consumables = { flaskId = 1 },
            buffs = { greaterBlessingOfKings = true },
            talentsString = "9",
            distanceFromTarget = 25,
        }
        assert.are.equal(p, ex.overDefaults(p, d))
        assert.are.same({
            race = "RaceTroll",
            talentsString = "5",
            profession1 = "Engineering",
            profession2 = "Blacksmithing",
            consumables = { flaskId = 1 },
            buffs = { greaterBlessingOfKings = true },
        }, p)
    end)

    it("takes M.OUT from WOWSIMS_OUT", function()
        local lua = io.open(".lua/bin/lua", "rb") and ".lua/bin/lua" or "lua5.1"
        local pipe = assert(
            io.popen(
                "WOWSIMS_OUT=/tmp/elsewhere/ " .. lua .. [[ -e 'print(loadfile("tools/wowsims/export.lua")().OUT)']]
            )
        )
        local got = pipe:read("*l")
        pipe:close()
        assert.are.equal("/tmp/elsewhere/", got)
    end)

    it("decodes a talent string in its tree file's order: { spell, rank, tree }", function()
        local trees = {
            { talents = { { spellId = 11 }, { spellId = 12 } } },
            { talents = { { spellId = 21 } } },
            { talents = { { spellId = 31 }, { spellId = 32 } } },
        }
        assert.are.same({ { 11, 2, 1 }, { 21, 1, 2 }, { 32, 3, 3 } }, ex.talents("20-1-03", trees))
        assert.are.same({ { 12, 5, 1 } }, ex.talents("05", trees))
        assert.are.same({ { 31, 1, 3 } }, ex.talents("--1", trees))
    end)

    it("builds a seeded one-iteration debug request from a recipe's player, gear and APL", function()
        local gear = tmp('{"items":[{"id":1},{}]}')
        local apl = tmp('{"type":"TypeAPL","priorityList":[]}')
        local req = ex.request({
            name = "Tester",
            apl = apl,
            player = {
                race = "RaceOrc",
                class = "ClassWarrior",
                gear = gear,
                talentsString = "1-2-3",
                specKey = "dpsWarrior",
                options = { classOptions = { startingRage = 50 } },
                profession1 = "Engineering",
                profession2 = "Blacksmithing",
                reactionTimeMs = 100,
                distanceFromTarget = 25,
            },
        }, "")
        os.remove(gear)
        os.remove(apl)
        local p = req.raid.parties[1].players[1]
        assert.are.same({ "Tester", "RaceOrc", "1-2-3", 50, 1 }, {
            p.name,
            p.race,
            p.talentsString,
            p.dpsWarrior.options.classOptions.startingRage,
            p.equipment.items[1].id,
        })
        assert.are.equal("TypeAPL", p.rotation.type)
        assert.are.same({ 1, "101", true }, {
            req.simOptions.iterations,
            req.simOptions.randomSeed,
            req.simOptions.debug,
        })
        assert.are.same({ 180, 63 }, { req.encounter.duration, req.encounter.targets[1].level })
        assert.is_nil(req.raid.tanks) -- not a tank: no tank, no healing model
        assert.is_nil(p.healingModel)
    end)

    it("gives a build without equipment the recipe's gear set, and refuses one with neither", function()
        local bare = tmp('{"player":{"class":"ClassWarlock","talentsString":"1"}}')
        local worn = tmp('{"player":{"class":"ClassWarlock","equipment":{"items":[{"id":7}]}}}')
        local gear = tmp('{"items":[{"id":5},{"id":6}]}')
        local p = ex.request({ name = "Bare", build = bare, gear = gear }, "").raid.parties[1].players[1]
        assert.are.same({ 5, 6, "1" }, { p.equipment.items[1].id, p.equipment.items[2].id, p.talentsString })
        p = ex.request({ name = "Worn", build = worn }, "").raid.parties[1].players[1]
        assert.are.equal(7, p.equipment.items[1].id) -- the build's own, as before
        p = ex.request({ name = "Worn", build = worn, gear = gear }, "").raid.parties[1].players[1]
        assert.are.equal(5, p.equipment.items[1].id) -- the recipe's gear wins
        local ok, err = pcall(ex.request, { name = "Bare", build = bare }, "")
        os.remove(bare)
        os.remove(worn)
        os.remove(gear)
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("no equipment", 1, true))
    end)

    it("sends a build's greater blessings at the top rank, 2 (ruling R25: the build's 1 is rank 1)", function()
        local build = tmp(
            '{"player":{"equipment":{"items":[]},"buffs":{"greaterBlessingOfWisdom":1,'
                .. '"greaterBlessingOfMight":1,"greaterBlessingOfKings":true}}}'
        )
        local b = ex.request({ name = "B", build = build }, "").raid.parties[1].players[1].buffs
        os.remove(build)
        assert.are.same({ greaterBlessingOfWisdom = 2, greaterBlessingOfMight = 2, greaterBlessingOfKings = true }, b)
    end)

    it("keeps a build's greater blessing of 0 at 0 (off stays off)", function()
        local build = tmp(
            '{"player":{"equipment":{"items":[]},"buffs":{"greaterBlessingOfWisdom":0,"greaterBlessingOfMight":1}}}'
        )
        local b = ex.request({ name = "B", build = build }, "").raid.parties[1].players[1].buffs
        os.remove(build)
        assert.are.same({ greaterBlessingOfWisdom = 0, greaterBlessingOfMight = 2 }, b)
    end)

    it("writes a recipe's vars into the APL's valueVariables, as a build's simple rotation does (R29)", function()
        local apl = tmp(
            '{"valueVariables":[{"name":"Use A","value":{"const":{"val":"true"}}},'
                .. '{"name":"Keep","value":{"cmp":{"op":"OpLt"}}}]}'
        )
        local r = { name = "V", apl = apl, player = { gear = apl, specKey = "rogue" } }
        r.vars = { ["Use A"] = "false" }
        local vv = ex.request(r, "").raid.parties[1].players[1].rotation.valueVariables
        r.vars = nil
        local plain = ex.request(r, "").raid.parties[1].players[1].rotation.valueVariables
        os.remove(apl)
        assert.are.same({ const = { val = "false" } }, vv[1].value)
        assert.are.same({ cmp = { op = "OpLt" } }, vv[2].value) -- a variable the recipe does not name is untouched
        assert.are.same({ const = { val = "true" } }, plain[1].value) -- no vars: the APL as it is
    end)

    it("raises on a recipe vars name the APL lacks (an upstream rename must not fall back to the raw APL)", function()
        local apl = tmp('{"valueVariables":[{"name":"Use A","value":{"const":{"val":"true"}}}]}')
        local r = { name = "V", apl = apl, player = { gear = apl, specKey = "rogue" } }
        r.vars = { ["Use A"] = "false", ["Use Gone"] = "false" }
        local ok, err = pcall(ex.request, r, "")
        os.remove(apl)
        assert.is_false(ok)
        assert.matches("Use Gone", tostring(err), 1, true)
    end)

    it("makes a tank recipe's player the raid's tank, healed by its healing model (the UI's tank defaults)", function()
        local gear = tmp('{"items":[]}')
        local model = { hps = 2200, cadenceSeconds = 0.4 }
        local req = ex.request({
            name = "Tank",
            tank = true,
            healingModel = model,
            player = { race = "RaceHuman", class = "ClassPaladin", gear = gear, specKey = "protectionPaladin" },
        }, "")
        os.remove(gear)
        assert.are.same({ { type = "Player", index = 0 } }, req.raid.tanks)
        assert.are.same(model, req.raid.parties[1].players[1].healingModel)
        local tanks = ex.recipe("paladin_protection")
        assert.are.same({ true, 2200 }, { tanks.tank, tanks.healingModel.hps })
    end)
end)
