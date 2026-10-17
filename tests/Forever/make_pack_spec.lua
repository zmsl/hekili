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

local CLASSES = { warrior = "Warrior", druid = "Druid" }

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
            local src = slurp("src/Hekili/Forever/Classes/" .. CLASSES[class] .. ".lua")
            local out, report = mp.sync(src, mp.load(class))
            assert.is_true(src == out, "the source changed")
            for _, r in ipairs(report) do
                assert.are.equal("unchanged", r[2], r[1])
            end
            assert.are.equal(3, #report)
        end)
    end

    describe("sync on an in-memory Warrior.lua", function()
        local src, packs, furyBlock
        before_each(function()
            src = slurp("src/Hekili/Forever/Classes/Warrior.lua")
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
            assert.has_error(function()
                mp.sync(src .. 'spec:RegisterPack("Zzz", 1, [[Hekili:x]])\n', packs)
            end)
            assert.has_error(function()
                mp.sync(src .. furyBlock, packs)
            end)
            assert.has_error(function()
                mp.sync((src:gsub(furyBlock:gsub("%p", "%%%0"), furyBlock .. "-- stray\n")), packs)
            end)
            assert.has_error(function()
                mp.sync("local x = 1\n", packs)
            end)
        end)
    end)

    it("refuses an unknown action option", function()
        assert.has_error(function()
            mp.parse("actions=charge,foo=1\n")
        end, "unknown option foo in: actions=charge,foo=1")
        assert.are.same(
            { default = { { action = "charge", enabled = true, use_off_gcd = 1, criteria = "a&b" } } },
            mp.parse("actions=charge,use_off_gcd=1,if=a&b\n")
        )
    end)
end)
