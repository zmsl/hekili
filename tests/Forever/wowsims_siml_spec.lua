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
local NEW_ROOT = (os.getenv("HOME") or "") .. "/src/wowsims-pin-4b0030a44b"
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
            local ok2, err = pcall(ex.request, r, NEW_ROOT, spec, NEW_CLI)
            assert.is_false(ok2)
            assert.is_truthy(tostring(err):find(ex.OLD_PIN, 1, true), tostring(err))
        end
    )
end)
