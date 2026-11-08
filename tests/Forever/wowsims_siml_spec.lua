-- tests/Forever/wowsims_siml_spec.lua (CN2 export side, translator-1.md): export.lua M.request reads a recipe's `apl`,
-- `gear`, `player.gear` and `build` path that ends in `.siml` through the CLI's `siml parse -json` (M.simlParse, which
-- drift.lua shares), and only with the CLI of a checkout at the spec's pin. Data: wowsims/forever (MIT).
local ex = assert(loadfile("tools/wowsims/export.lua"))()
local json = require("dkjson")

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function spit(path, s)
    local f = assert(io.open(path, "wb"))
    f:write(s)
    f:close()
end

-- the shared new-pin checkout and its oracle CLI (docs/dev/wowsims-packs.md "Moving the pin"); absent off this machine
local NEW_ROOT = (os.getenv("HOME") or "") .. "/src/wowsims-pin-e5a9cd2a2d"
local NEW_CLI = NEW_ROOT .. "/wowsimcli-sim-pin"
local function present(path)
    local f = io.open(path, "rb")
    return f ~= nil and f:close()
end

describe("export.lua .siml recipe paths", function()
    it("refuses a .siml path unless the CLI is the checkout's at the spec's pin, naming spec, pin and path", function()
        local dir = os.tmpname()
        os.remove(dir)
        os.execute("mkdir -p '" .. dir .. "'")
        local cli = dir .. "/wowsimcli-sim-pin" -- a non-git directory: at no pin
        spit(cli, '#!/bin/sh\necho \'{"type":"TypeAPL"}\'\n')
        os.execute("chmod +x '" .. cli .. "'")
        spit(dir .. "/gear.json", '{"items":[]}')
        local r = { name = "S", apl = "a/default.apl.siml", player = { gear = "gear.json", specKey = "rogue" } }
        local ok, err = pcall(ex.request, r, dir, "paladin_retribution", cli)
        os.execute("rm -rf '" .. dir .. "'")
        assert.is_false(ok)
        err = tostring(err)
        assert.is_truthy(err:find("paladin_retribution", 1, true), err)
        assert.is_truthy(err:find(ex.pin("paladin_retribution"), 1, true), err)
        assert.is_truthy(err:find("a/default.apl.siml", 1, true), err)
        assert.is_truthy(err:find(cli, 1, true), err) -- the CLI and its head (none here)
        assert.is_truthy(err:find("no commit", 1, true), err)
    end)

    it("refuses a spec at the new pin with a CLI whose checkout is at another commit, naming that head", function()
        local dir = os.tmpname()
        os.remove(dir)
        os.execute("mkdir -p '" .. dir .. "'")
        os.execute(
            "cd '" .. dir .. "' && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m old"
        )
        local pipe = assert(io.popen("git -C '" .. dir .. "' rev-parse HEAD"))
        local head = pipe:read("*l")
        pipe:close()
        local cli = dir .. "/wowsimcli-sim-pin"
        spit(dir .. "/gear.json", '{"items":[]}')
        local spec = "paladin_protection"
        local saved = ex.SPEC_PIN[spec]
        ex.SPEC_PIN[spec] = ex.NEW_PIN
        local r = { name = "S", apl = "a/default.apl.siml", player = { gear = "gear.json", specKey = "rogue" } }
        local ok, err = pcall(ex.request, r, dir, spec, cli)
        ex.SPEC_PIN[spec] = saved
        os.execute("rm -rf '" .. dir .. "'")
        assert.is_false(ok)
        err = tostring(err)
        for _, want in ipairs({ spec, ex.NEW_PIN, "a/default.apl.siml", cli, head }) do
            assert.is_truthy(err:find(want, 1, true), want .. " in " .. err)
        end
    end)

    it("quotes a CLI and a .siml path holding a quote for the shell", function()
        local base = os.tmpname()
        os.remove(base)
        local dir = base .. "it's"
        os.execute('mkdir -p "' .. dir .. '"')
        local cli = dir .. "/cli"
        spit(cli, '#!/bin/sh\ncat "$4.json"\n')
        os.execute('chmod +x "' .. cli .. '"')
        spit(dir .. "/a.apl.siml.json", '{"type":"TypeAPL"}')
        local ok, t = pcall(ex.simlParse, cli, dir .. "/a.apl.siml", "test")
        os.execute('rm -rf "' .. dir .. '"')
        assert(ok, t)
        assert.are.equal("TypeAPL", t.type)
    end)

    it("keeps a recipe player's inFrontOfTarget in the request", function()
        local gear = os.tmpname()
        spit(gear, '{"items":[]}')
        local p = ex.request(
            { name = "F", player = { gear = gear, specKey = "protectionPaladin", inFrontOfTarget = true } },
            "",
            "paladin_protection"
        ).raid.parties[1].players[1]
        os.remove(gear)
        assert.is_true(p.inFrontOfTarget)
    end)

    it("gives drift's new side a .siml build over its defaults, as M.request does (one implementation)", function()
        local drift = assert(loadfile("tools/wowsims/drift.lua"))()
        local dir = os.tmpname()
        os.remove(dir)
        os.execute("mkdir -p '" .. dir .. "'")
        local cli = dir .. "/cli" -- a fake CLI: the JSON beside each .siml
        spit(cli, '#!/bin/sh\ncat "$4.json"\n')
        os.execute("chmod +x '" .. cli .. "'")
        spit(dir .. "/b.siml", "") -- drift checks the file is in the tree
        spit(dir .. "/d.siml", "")
        spit(dir .. "/b.siml.json", '{"player":{"class":"ClassHunter","equipment":{"items":[{"id":9}]}}}')
        spit(dir .. "/d.siml.json", '{"player":{"race":"RaceOrc","buffs":{"giftOfTheWild":2}}}')
        local ok, req = pcall(
            drift.newRequest,
            ex,
            { name = "B", build = "b.siml", defaults = "d.siml" },
            "hunter_survival",
            dir,
            cli,
            {}
        )
        os.execute("rm -rf '" .. dir .. "'")
        assert(ok, req)
        local p = req.raid.parties[1].players[1]
        assert.are.same({ "RaceOrc", 2, 9 }, { p.race, p.buffs and p.buffs.giftOfTheWild, p.equipment.items[1].id })
    end)

    it("still reads a .json path as JSON, with no CLI", function()
        local gear = os.tmpname()
        spit(gear, '{"items":[{"id":3}]}')
        local p = ex.request({ name = "J", player = { gear = gear, specKey = "rogue" } }, "", "paladin_retribution")
        os.remove(gear)
        assert.are.equal(3, p.raid.parties[1].players[1].equipment.items[1].id)
    end)

    local real = present(NEW_CLI) and it or pending
    real(
        "parses the new pin's Retribution .apl.siml and .gear.siml (a scratch recipe) as the translator's fixture",
        function()
            local spec = "paladin_retribution"
            local saved = ex.SPEC_PIN[spec]
            ex.SPEC_PIN[spec] = ex.NEW_PIN -- the scratch recipe is at the new pin; the checked-in line is the lane's flip
            local r = ex.recipe(spec)
            r.apl = "ui/specs/paladin/retribution/apls/default.apl.siml"
            r.player.gear = "ui/specs/paladin/retribution/gear_sets/default.gear.siml"
            local ok, req = pcall(ex.request, r, NEW_ROOT, spec, NEW_CLI)
            ex.SPEC_PIN[spec] = saved
            assert(ok, req)
            local p = req.raid.parties[1].players[1]
            local want = json.decode(slurp("tests/Forever/fixtures/wowsims_siml_" .. spec .. ".apl.json"))
            assert.are.same(want, p.rotation)
            assert.is_true(#p.equipment.items > 0)
            -- and it translates as the checked-in request's JSON APL (the translator lane's check, on the request)
            local apl = require("tools.wowsims.apl")
            local set = require("Forever.helpers.engine").abilitySet(r.class)
            local log = slurp("tests/Forever/wowsims/" .. spec .. ".log")
            local old = json.decode(slurp("tests/Forever/wowsims/" .. spec .. ".json")).raid.parties[1].players[1]
            assert.are.same(
                { apl.translate(old.rotation, apl.context(set, r, log, old)) },
                { apl.translate(p.rotation, apl.context(set, r, log, old)) }
            )
            -- a spec left at the old pin refuses the new pin's CLI instead of parsing with it
            ex.SPEC_PIN[spec] = ex.OLD_PIN -- explicit: the checked-in line is NEW once the lane has flipped this spec
            local ok2, err = pcall(ex.request, r, NEW_ROOT, spec, NEW_CLI)
            ex.SPEC_PIN[spec] = saved
            assert.is_false(ok2)
            assert.is_truthy(tostring(err):find(ex.OLD_PIN, 1, true), tostring(err))
        end
    )

    real("parses a whole .siml build over its defaults, with a .siml gear set (the Hunters' shape)", function()
        local spec = "hunter_survival"
        local saved = ex.SPEC_PIN[spec]
        ex.SPEC_PIN[spec] = ex.NEW_PIN
        local ok, req = pcall(ex.request, {
            name = "S",
            build = "ui/specs/hunter/dps/builds/sv_weave.siml",
            defaults = "ui/specs/hunter/dps/defaults.siml",
            gear = "ui/specs/hunter/dps/gear_sets/p1_melee.gear.siml",
        }, NEW_ROOT, spec, NEW_CLI)
        ex.SPEC_PIN[spec] = saved
        assert(ok, req)
        local p = req.raid.parties[1].players[1]
        assert.are.same({ "RaceOrc", "TypeAPL" }, { p.race, p.rotation.type }) -- the race is the defaults'
        assert.is_true(#p.equipment.items > 0)
    end)
end)
