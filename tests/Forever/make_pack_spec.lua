-- tests/Forever/make_pack_spec.lua: tools/make_pack.lua's library (loadfile(...)("lib")): each pack survives
-- encode -> decode -> unparse -> parse unchanged, and sync rewrites a class file's RegisterPack blocks from the
-- manifest (a no-op on the checked-in files) or refuses a span it cannot read. No engine boot.

local mp = assert(loadfile("tools/make_pack.lua"))("lib")

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local CLASSES = { warrior = "Warrior", druid = "Druid", rogue = "Rogue", paladin = "Paladin", shaman = "Shaman" }

describe("tools/make_pack.lua", function()
    for class in pairs(CLASSES) do
        it("round-trips every " .. class .. " pack through encode, decode, unparse and parse", function()
            for _, p in ipairs(mp.load(class)) do
                local payload = mp.decode(mp.encode(p))
                assert.are.equal(mp.unparse(p.lists), mp.unparse(payload.lists), p.name)
                assert.are.same(p.lists, mp.parse(mp.unparse(p.lists)), p.name)
                assert.are.equal(p.simc, payload.profile, p.name)
                assert.are.equal(p.desc, payload.desc, p.name)
            end
        end)

        it("leaves the checked-in " .. CLASSES[class] .. ".lua alone (every pack unchanged)", function()
            local src = slurp("src/Hekili_" .. CLASSES[class] .. "/" .. CLASSES[class] .. ".lua")
            local out, report = mp.sync(src, mp.load(class))
            assert.is_true(src == out, "the source changed")
            for _, r in ipairs(report) do
                assert.are.equal("unchanged", r[2], r[1])
            end
            assert.are.equal(#mp.load(class), #report)
        end)
    end

    describe("sync on an in-memory Warrior.lua", function()
        local src, packs, furyBlock
        before_each(function()
            src = slurp("src/Hekili_Warrior/Warrior.lua")
            packs = mp.load("warrior")
            furyBlock = src:match('spec:RegisterPack%(\n    "Fury",\n.-\n%)\n')
            assert.is_not_nil(furyBlock)
        end)

        it("restores a deleted block byte for byte", function()
            local out, report = mp.sync((src:gsub(furyBlock:gsub("%p", "%%%0"), "")), packs)
            assert.is_true(src == out, "the source changed")
            assert.are.same({ { "Arms", "unchanged" }, { "Fury", "added" }, { "Protection", "unchanged" } }, report)
        end)

        it("updates a block whose version differs", function()
            local edited = src:gsub('("Arms",\n    )(%d+)', "%11")
            assert.are_not.equal(src, edited)
            local out, report = mp.sync(edited, packs)
            assert.is_true(src == out, "the source changed")
            assert.are.same({ "Arms", "updated" }, report[1])
        end)

        it("removes a block the manifest does not list", function()
            local out, report = mp.sync(src .. 'spec:RegisterPack(\n    "Zzz",\n    1,\n    [[Hekili:x]]\n)\n', packs)
            assert.is_true(src == out, "the source changed")
            assert.are.same({ "Zzz", "removed" }, report[4])
        end)

        it("refuses a RegisterPack it cannot parse, a duplicate, stray content or no block", function()
            local _, n = src:gsub("\n", "")
            assert.has_error(function()
                mp.sync(src .. 'spec:RegisterPack("Zzz", 1, [[Hekili:x]])\n', packs)
            end, "line " .. (n + 1) .. ": a RegisterPack( not in the generated block layout")
            assert.has_error(function()
                mp.sync(src .. furyBlock, packs)
            end, "duplicate RegisterPack Fury")
            assert.has_error(function()
                mp.sync((src:gsub(furyBlock:gsub("%p", "%%%0"), furyBlock .. "-- stray\n")), packs)
            end, "non-block content between RegisterPack blocks before Protection")
            assert.has_error(function()
                mp.sync("local x = 1\n", packs)
            end, "no RegisterPack block")
        end)
    end)

    -- A scratch APLs folder: `files` maps a name to its text, or true to copy it from `from` (an APLs folder).
    local function scratch(from, files)
        local root = os.tmpname()
        os.remove(root)
        assert(os.execute("mkdir -p " .. root) == 0)
        for name, text in pairs(files) do
            local f = assert(io.open(root .. "/" .. name, "wb"))
            f:write(text == true and slurp(from .. name) or text)
            f:close()
        end
        return root .. "/"
    end

    it("names the .simc file of a line it cannot parse", function()
        local root = scratch(nil, {
            ["packs.lua"] = 'return { spec = 1, packs = { "Bad" } }\n',
            ["Bad.simc"] = "# A bad pack\nnot an action line\n",
        })
        local ok, err = pcall(mp.load, "zzz", root, 20261017)
        os.execute("rm -r " .. root)
        assert.is_false(ok)
        assert.are.equal(root .. "Bad.simc: bad line: not an action line", err)
    end)

    describe("write (the date changes only with the text)", function()
        local TODAY = 20991231
        local function date(src, name)
            return math.floor(tonumber(src:match('"' .. name .. '",\n    (%d+),')) / 1000)
        end

        for class, Class in pairs(CLASSES) do
            it("leaves the checked-in " .. Class .. ".lua alone on any day", function()
                local src = slurp("src/Hekili_" .. Class .. "/" .. Class .. ".lua")
                assert.is_true(src == mp.write(src, class, TODAY), "the source changed")
            end)
        end

        it("re-dates only the class whose text changed, by one character, and is then a no-op", function()
            local apls = "src/Hekili_Warrior/APLs/"
            local fury, n =
                slurp(apls .. "Fury.simc"):gsub("rage>=settings.hs_threshold", "rage>settings.hs_threshold", 1) -- one character
            assert.are.equal(1, n)
            local root = scratch(apls, { ["packs.lua"] = true, ["Arms.simc"] = true, ["Protection.simc"] = true })
            local f = assert(io.open(root .. "Fury.simc", "wb"))
            f:write(fury)
            f:close()
            local src = slurp("src/Hekili_Warrior/Warrior.lua")
            local out, report = mp.write(src, "warrior", TODAY, root)
            local again = mp.write(out, "warrior", TODAY + 1, root)
            os.execute("rm -r " .. root)
            assert.is_false(src == out, "the Fury change was not written")
            assert.are.same({ "Fury", "updated" }, report[2])
            for _, name in ipairs({ "Arms", "Fury", "Protection" }) do
                assert.are.equal(TODAY, date(out, name), name)
            end
            assert.is_true(out == again, "a second write changed the file")
            local druid = slurp("src/Hekili_Druid/Druid.lua")
            assert.is_true(druid == mp.write(druid, "druid", TODAY), "the Druid file changed")
            assert.are_not.equal(TODAY, date(druid, "Feral"))
        end)
    end)

    it("refuses an unknown action option", function()
        assert.has_error(function()
            mp.parse("actions=charge,foo=1\n")
        end, "unknown option foo in: actions=charge,foo=1")
        assert.has_error(function()
            mp.parse("actions=rip,focus=yes\n")
        end, "bad value focus=yes in: actions=rip,focus=yes")
        assert.has_error(function()
            mp.parse("actions=charge,use_off_gcd=x\n")
        end, "bad value use_off_gcd=x in: actions=charge,use_off_gcd=x")
        assert.are.same(
            { default = { { action = "charge", enabled = true, use_off_gcd = 1, criteria = "a&b" } } },
            mp.parse("actions=charge,use_off_gcd=1,if=a&b\n")
        )
    end)

    it("round-trips focus=1 as a number, written before if=", function()
        local simc = "actions=rip,focus=1,if=a&b\nactions.st=rake,name=x,use_off_gcd=1,focus=1\n"
        local lists = mp.parse(simc)
        assert.are.same({ action = "rip", enabled = true, focus = 1, criteria = "a&b" }, lists.default[1])
        assert.are.equal(1, lists.st[1].focus)
        assert.are.equal(simc, mp.unparse(lists))
        assert.are.same(lists, mp.parse(mp.unparse(lists)))
    end)

    it("round-trips focus=N for any positive integer tier and refuses 0, negatives and non-integers", function()
        local simc = "actions=heroic_strike,use_off_gcd=1,focus=2,if=a\nactions+=/cleave,focus=12\n"
        local lists = mp.parse(simc)
        assert.are.same({ 2, 12 }, { lists.default[1].focus, lists.default[2].focus })
        assert.are.equal(simc, mp.unparse(lists))
        for _, bad in ipairs({ "0", "-1", "1.5", "2.0", "01" }) do
            local line = "actions=rip,focus=" .. bad
            assert.has_error(function()
                mp.parse(line .. "\n")
            end, "bad value focus=" .. bad .. " in: " .. line)
        end
    end)
end)
