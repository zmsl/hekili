-- tests/LibHiddenValues/standalone_spec.lua: the library stands alone and embeds. The no-host-reference grep passes;
-- the TOC and the embedders' XML list the same files; LibStub keeps one running copy (the same minor twice builds and
-- replaces nothing, an older minor after a newer one returns at once, a newer one inherits the registry); the slash
-- command works.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end
local ROOT = "src/LibHiddenValues/"

describe("LibHiddenValues standalone", function()
    local Fake, W, lib

    before_each(function()
        Fake = dofile(FAKE)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
    end)

    after_each(function()
        Fake.restore()
    end)

    it("names no host addon, and no host names it (tools/libhiddenvalues/check_standalone.sh)", function()
        local p = io.popen("bash tools/libhiddenvalues/check_standalone.sh 2>&1; echo rc=$?")
        local out = p:read("*a")
        p:close()
        assert.is_truthy(out:match("rc=0"), out)
    end)

    it("lists the same files in the TOC and the XML", function()
        local toc, xml = {}, {}
        for line in io.lines(ROOT .. "LibHiddenValues.toc") do
            line = line:gsub("\r", ""):gsub("%s+$", "")
            if line ~= "" and not line:match("^#") then
                toc[#toc + 1] = line:gsub("\\", "/")
            end
        end
        for line in io.lines(ROOT .. "LibHiddenValues.xml") do
            local f = line:match('<Script file="([^"]+)"')
            if f then
                xml[#xml + 1] = f:gsub("\\", "/")
            end
        end
        assert.are.same(toc, xml)
        assert.are.equal("Libs/LibStub/LibStub.lua", toc[1])
    end)

    it("declares Interface 16001 and no SavedVariables", function()
        local f = assert(io.open(ROOT .. "LibHiddenValues.toc"))
        local s = f:read("*a")
        f:close()
        assert.is_truthy(s:match("## Interface: 16001"))
        assert.is_nil(s:match("SavedVariables"))
    end)

    it("loads the same minor twice without building or replacing anything", function()
        Fake.login()
        local n, watch, fire = #Fake.frames, lib.Watch, lib.fire
        Fake.loadLibrary()
        assert.are.equal(n, #Fake.frames)
        assert.are.equal(watch, lib.Watch)
        assert.are.equal(fire, lib.fire)
        assert.are.equal(lib, LibStub("LibHiddenValues-1.0"))
    end)

    it("ignores an older minor loaded after it", function()
        local watch = lib.Watch
        Fake.loadLibrary(0)
        assert.are.equal(watch, lib.Watch)
        assert.are.same({ "LibHiddenValues-1.0", 1 }, { lib:GetVersion() })
    end)

    it("lets a newer minor before login inherit the registry", function()
        W.unit.target = { health = 0.6 }
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } })
        local watch = lib.Watch
        Fake.loadLibrary(2)
        assert.are_not.equal(watch, lib.Watch)
        assert.are.same({ "LibHiddenValues-1.0", 2 }, { lib:GetVersion() })
        Fake.login()
        Fake.tick(10)
        assert.are.equal("live", (h:State()))
        assert.are.same({ 50, 100 }, lohi(h))
    end)

    it("lets a newer minor after login keep the frames and re-prime", function()
        W.unit.target = { health = 0.6 }
        local calls = {}
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, function(_, lo)
            calls[#calls + 1] = lo or "nil"
        end)
        Fake.login()
        Fake.tick(10)
        local n = #Fake.frames
        Fake.loadLibrary(2)
        Fake.tick(10)
        assert.are.equal(n, #Fake.frames)
        assert.are.same({ 50, "nil", 50 }, calls)
        assert.are.equal("live", (h:State()))
    end)

    it("answers /lhv: status, watch, stats, selftest, copy, off and on", function()
        W.unit.target = { health = 0.6 }
        Fake.login()
        Fake.slash("")
        assert.is_truthy(Fake.printed[#Fake.printed]:match("health"))
        Fake.slash("watch health target 20 50")
        Fake.tick(10)
        W.unit.target.health = 0.3
        Fake.tick(3)
        local seen
        for _, l in ipairs(Fake.printed) do
            seen = seen or l:match("health target .*0%-50")
        end
        assert.is_truthy(seen)
        Fake.slash("stats")
        Fake.slash("watch off")
        assert.are.equal(0, (lib:GetStats()))
        Fake.slash("selftest")
        Fake.tick(60)
        assert.is_truthy(Fake.printed[#Fake.printed]:match("PASS"))
        Fake.slash("test")
        Fake.tick(60)
        Fake.slash("copy")
        assert.is_truthy(LibHiddenValuesCopyFrame)
        Fake.slash("off")
        assert.are.same({ false, "unavailable", "off" }, { lib:IsAvailable("health") })
        Fake.slash("on")
        assert.are.same({ false, "pending" }, { lib:IsAvailable("health") })
        for _, l in ipairs(Fake.printed) do
            assert.is_true(#l < 255, l)
        end
    end)
end)
