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

local CLASSES =
    { warrior = "Warrior", druid = "Druid", rogue = "Rogue", paladin = "Paladin", shaman = "Shaman", hunter = "Hunter" }

describe("tools/make_pack.lua", function()
    it("binds each pack to its spec's share key from the manifest", function()
        local by = {}
        for _, p in ipairs(mp.load("warrior")) do
            by[p.name] = mp.decode(mp.encode(p)).spec
        end
        assert.are.same({
            ["Protection (wowsims.com)"] = "WARRIOR:protection",
            ["Fury (wowsims.com)"] = "WARRIOR:fury",
            ["Arms (wowsims.com)"] = "WARRIOR:arms",
        }, by)
    end)

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
            furyBlock = src:match('spec:RegisterPack%(\n    "Fury %(wowsims%.com%)",\n.-\n%)\n')
            assert.is_not_nil(furyBlock)
        end)

        it("restores a deleted block byte for byte", function()
            local out, report = mp.sync((src:gsub(furyBlock:gsub("%p", "%%%0"), "")), packs)
            assert.is_true(src == out, "the source changed")
            assert.are.same({
                { "Protection (wowsims.com)", "unchanged" },
                { "Fury (wowsims.com)", "added" },
                { "Arms (wowsims.com)", "unchanged" },
            }, report)
        end)

        it("updates a block whose version differs", function()
            local edited = src:gsub('("Arms %(wowsims%.com%)",\n    )(%d+)', "%11")
            assert.are_not.equal(src, edited)
            local out, report = mp.sync(edited, packs)
            assert.is_true(src == out, "the source changed")
            assert.are.same({ "Arms (wowsims.com)", "updated" }, report[3])
        end)

        it("removes a block the manifest does not list", function()
            local zzz = 'spec:RegisterPack(\n    "Zzz",\n    1,\n    [[Hekili:x]]\n)\n'
            local edited, n = src:gsub("%)\n\n%-%- The hand%-built lists", ")\n" .. zzz .. "\n-- The hand-built lists") -- after the last block
            assert.are.equal(1, n)
            local out, report = mp.sync(edited, packs)
            assert.is_true(src == out, "the source changed")
            assert.are.same({ "Zzz", "removed" }, report[#report])
        end)

        it("refuses a RegisterPack it cannot parse, a duplicate, stray content or no block", function()
            local _, n = src:gsub("\n", "")
            assert.has_error(function()
                mp.sync(src .. 'spec:RegisterPack("Zzz", 1, [[Hekili:x]])\n', packs)
            end, "line " .. (n + 1) .. ": a RegisterPack( not in the generated block layout")
            assert.has_error(function()
                mp.sync(src .. furyBlock, packs)
            end, "duplicate RegisterPack Fury (wowsims.com)")
            assert.has_error(function()
                mp.sync((src:gsub(furyBlock:gsub("%p", "%%%0"), furyBlock .. "-- stray\n")), packs)
            end, "non-block content between RegisterPack blocks before Arms (wowsims.com)")
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
            ["packs.lua"] = 'return { class = "ZZZ", packs = { "Bad" }, specs = { Bad = "bad" } }\n',
            ["Bad.simc"] = "# A bad pack\nnot an action line\n",
        })
        local ok, err = pcall(mp.load, "zzz", root, { src = "" })
        os.execute("rm -r " .. root)
        assert.is_false(ok)
        assert.are.equal(root .. "Bad.simc: bad line: not an action line", err)
    end)

    it("refuses a manifest with no class", function()
        local root = scratch("src/Hekili_Warrior/APLs/", {
            ["packs.lua"] = 'return { packs = { "Arms (wowsims.com)" } }\n',
            ["Arms (wowsims.com).simc"] = true,
        })
        local ok, err = pcall(mp.load, "zzz", root, { src = "" })
        os.execute("rm -r " .. root)
        assert.is_false(ok)
        assert.are.equal(root .. "packs.lua: no class", err)
    end)

    -- The manifest's `imports`: a pack takes another pack's own lists (never what that pack imports) under a prefix,
    -- entered first in its default and precombat while buff.<aura>.up; its own default and precombat entries gain the
    -- negated guard, and its text is rebuilt from the merged lists.
    describe("imports", function()
        local MANIFEST = 'return { class = "ZZZ", packs = { "Host", "Other" }, specs = { Host = "h", Other = "o" },\n'
            .. '    imports = { Host = { from = "Other", as = "o", aura = "o_form" },\n'
            .. '        Other = { from = "Host", as = "h", aura = "h_form" } } }\n'
        local HOST = "# Host\nactions.precombat=a1\nactions=b1,if=x|y\n"
            .. "actions+=/call_action_list,name=sub\nactions.sub=c1\n"
        local OTHER = "# Other\nactions.precombat=p1\nactions=d1,use_off_gcd=1,if=z\n"
            .. "actions+=/call_action_list,name=sub\nactions.sub=e1\n"
        local function load(manifest, files)
            files = files or {}
            files["packs.lua"] = manifest
            files["Host.simc"] = files["Host.simc"] or HOST
            files["Other.simc"] = files["Other.simc"] or OTHER
            local root = scratch(nil, files)
            local ok, packs = pcall(mp.load, "zzz", root, { src = "" })
            os.execute("rm -r " .. root)
            return ok, packs
        end

        it("prefixes the other pack's lists, renames its calls and guards the host's default and precombat", function()
            local ok, packs = load(MANIFEST)
            assert.is_true(ok, packs)
            assert.are.equal(
                "actions=call_action_list,name=o,if=buff.o_form.up\n"
                    .. "actions+=/b1,if=(x|y)&!buff.o_form.up\n"
                    .. "actions+=/call_action_list,name=sub,if=!buff.o_form.up\n"
                    .. "actions.o=d1,use_off_gcd=1,if=z\n"
                    .. "actions.o+=/call_action_list,name=o_sub\n"
                    .. "actions.o_precombat=p1\n"
                    .. "actions.o_sub=e1\n"
                    .. "actions.precombat=call_action_list,name=o_precombat,if=buff.o_form.up\n"
                    .. "actions.precombat+=/a1,if=!buff.o_form.up\n"
                    .. "actions.sub=c1\n",
                packs[1].simc
            )
            -- the other way round from Host's own lists: no o_* list comes back as h_o_*
            assert.are.equal(
                "actions=call_action_list,name=h,if=buff.h_form.up\n"
                    .. "actions+=/d1,use_off_gcd=1,if=(z)&!buff.h_form.up\n"
                    .. "actions+=/call_action_list,name=sub,if=!buff.h_form.up\n"
                    .. "actions.h=b1,if=x|y\n"
                    .. "actions.h+=/call_action_list,name=h_sub\n"
                    .. "actions.h_precombat=a1\n"
                    .. "actions.h_sub=c1\n"
                    .. "actions.precombat=call_action_list,name=h_precombat,if=buff.h_form.up\n"
                    .. "actions.precombat+=/p1,if=!buff.h_form.up\n"
                    .. "actions.sub=e1\n",
                packs[2].simc
            )
            for _, p in ipairs(packs) do
                assert.are.same(mp.parse(p.simc), p.lists, p.name) -- the profile text is the lists
                assert.are.equal(p.simc, mp.unparse(p.lists), p.name)
            end
            assert.are.equal("Host Imports Other as the o lists, entered while buff.o_form.up.", packs[1].desc)
        end)

        it("leaves a pack without an import as its file wrote it", function()
            local ok, packs = load(
                'return { class = "ZZZ", packs = { "Host", "Other" }, specs = { Host = "h", Other = "o" },\n'
                    .. '    imports = { Host = { from = "Other", as = "o", aura = "o_form" } } }\n'
            )
            assert.is_true(ok, packs)
            assert.are.equal((OTHER:gsub("^# Other\n", "")), packs[2].simc)
            assert.are.equal("Other", packs[2].desc)
        end)

        it("refuses an unknown source and a list name the host already has", function()
            local ok, err = load((MANIFEST:gsub('from = "Other"', 'from = "Nope"')))
            assert.is_false(ok)
            assert.matches("packs%.lua: pack Host imports Nope, which the manifest does not list$", err)
            ok, err = load(MANIFEST, { ["Host.simc"] = HOST .. "actions.o_sub=f1\n" })
            assert.is_false(ok)
            assert.matches("packs%.lua: pack Host imports Other's list sub as o_sub, a list it already has$", err)
        end)
    end)

    describe("write (the version changes only with the text)", function()
        local TODAY = 20991231

        for class, Class in pairs(CLASSES) do
            it("leaves the checked-in " .. Class .. ".lua alone on any day", function()
                local src = slurp("src/Hekili_" .. Class .. "/" .. Class .. ".lua")
                assert.is_true(src == mp.write(src, class, TODAY), "the source changed")
            end)
        end

        -- writes the Warrior file with Fury's .simc text edited by `from` -> `to` (gsub patterns), from `src`, on `day`
        local function edit(src, from, to, day)
            local apls = "src/Hekili_Warrior/APLs/"
            local fury, n = slurp(apls .. "Fury (wowsims.com).simc"):gsub(from, to, 1)
            assert.are.equal(1, n)
            local root = scratch(apls, {
                ["packs.lua"] = true,
                ["Protection (wowsims.com).simc"] = true,
                ["Arms (wowsims.com).simc"] = true,
            })
            local f = assert(io.open(root .. "Fury (wowsims.com).simc", "wb"))
            f:write(fury)
            f:close()
            local out, report = mp.write(src, "warrior", day, root)
            local again = mp.write(out, "warrior", day, root)
            os.execute("rm -r " .. root)
            assert.is_true(out == again, "a second write changed the file")
            return out, report
        end
        local function version(src, name)
            return tonumber(src:match('"' .. name:gsub("%p", "%%%0") .. '",\n    (%d+),'))
        end

        it("versions only the pack whose text changed: unchanged keeps it, a later day gives today * 1000", function()
            local src = slurp("src/Hekili_Warrior/Warrior.lua")
            local out, report = edit(src, "rage.lo>=40", "rage.lo>40", TODAY) -- one character
            assert.are.same({ "Fury (wowsims.com)", "updated" }, report[2])
            assert.are.equal(TODAY * 1000, version(out, "Fury (wowsims.com)"))
            for _, name in ipairs({ "Protection (wowsims.com)", "Arms (wowsims.com)" }) do
                assert.are.equal(version(src, name), version(out, name), name)
            end
            local druid = slurp("src/Hekili_Druid/Druid.lua")
            assert.is_true(druid == mp.write(druid, "druid", TODAY), "the Druid file changed")
        end)

        it("counts up on the same day, once per change", function()
            local src = slurp("src/Hekili_Warrior/Warrior.lua")
            local one = edit(src, "rage.lo>=40", "rage.lo>40", TODAY)
            local two = edit(one, "rage.lo>=40", "rage.lo>41", TODAY) -- Fury's text differs from `one`'s again
            assert.are.equal(TODAY * 1000 + 1, version(two, "Fury (wowsims.com)"))
            local three = edit(two, "rage.lo>=40", "rage.lo>42", TODAY)
            assert.are.equal(TODAY * 1000 + 2, version(three, "Fury (wowsims.com)"))
        end)

        it("refuses a thousandth same-day change", function()
            local src = slurp("src/Hekili_Warrior/Warrior.lua")
            local one = edit(src, "rage.lo>=40", "rage.lo>40", TODAY)
            local full = one:gsub('(Fury %(wowsims%.com%)",\n    )%d+', "%1" .. TODAY * 1000 + 999)
            assert.has_error(function()
                edit(full, "rage.lo>=40", "rage.lo>41", TODAY)
            end)
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

    it("round-trips cancel_buff's buff_name as a string, written after name=", function()
        local simc = "actions=cancel_buff,buff_name=cat_form,if=a\n"
        local lists = mp.parse(simc)
        assert.are.same(
            { action = "cancel_buff", enabled = true, buff_name = "cat_form", criteria = "a" },
            lists.default[1]
        )
        assert.are.equal(simc, mp.unparse(lists))
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

    it("refuses prepull_at: pre-pull lines carry their guard in the condition (wowsims rule 1)", function()
        assert.has_error(function()
            mp.parse("actions.precombat=aura,prepull_at=10\n")
        end, "unknown option prepull_at in: actions.precombat=aura,prepull_at=10")
    end)
end)
