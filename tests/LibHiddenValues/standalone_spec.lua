-- tests/LibHiddenValues/standalone_spec.lua: the library stands alone and embeds. The no-host-reference grep passes;
-- the TOC and the embedders' XML list the same files; LibStub keeps one running copy (the same minor twice builds and
-- replaces nothing, an older minor after a newer one returns at once, a newer one inherits the registry); it is a pure
-- API (no slash command, no chat output, no global but LibStub) and every diagnostic fact has a getter.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

local function lohi(h)
    local lo, hi = h:Get()
    return { lo, hi }
end
local ROOT = "src/LibHiddenValues/"
local BASE = {} -- the globals before any test of this file (busted insulates each file)
for k in pairs(_G) do
    BASE[k] = true
end

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
        assert.are.same({ "LibHiddenValues-1.0", 3 }, { lib:GetVersion() })
    end)

    it("lets a newer minor before login inherit the registry", function()
        W.unit.target = { health = 0.6 }
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } })
        local watch = lib.Watch
        Fake.loadLibrary(4)
        assert.are_not.equal(watch, lib.Watch)
        assert.are.same({ "LibHiddenValues-1.0", 4 }, { lib:GetVersion() })
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
        Fake.loadLibrary(4)
        Fake.tick(10)
        assert.are.equal(n, #Fake.frames)
        assert.are.same({ 50, "nil", 50 }, calls)
        assert.are.equal("live", (h:State()))
    end)

    it("is a pure API: no slash command, no chat output, no global but LibStub, over a whole session", function()
        Fake.restore()
        for k in pairs(_G) do -- what earlier tests' copies left behind must not hide this one's
            if not BASE[k] then
                rawset(_G, k, nil)
            end
        end
        local before = {}
        Fake = loadfile(FAKE)({
            before = function()
                for k in pairs(_G) do
                    before[k] = true
                end
            end,
        })
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        W.unit.target = { health = 0.6 }
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50 } }, function() end)
        lib:OnCapability("A", function() end)
        Fake.login()
        Fake.tick(10)
        W.unit.target.health = 0.3
        Fake.tick(3)
        assert.are.same({ 20, 50 }, lohi(h))
        lib:GetStats()
        lib:GetPool()
        lib:GetSources()
        lib:GetKinds()
        lib:GetSelfTest()
        lib:SelfTest(function() end)
        Fake.tick(60)
        lib:SetEnabled(false)
        lib:SelfTest(function() end) -- the switched-off path
        lib:SetEnabled(true)
        Fake.tick(60)
        Fake.set("drop", 1)
        lib:SelfTest(function() end) -- a failing run
        Fake.tick(60)
        assert.are.same({ false, "unavailable", "selftest" }, { lib:IsAvailable("health") })
        lib:ReleaseAll("A")
        Fake.loadLibrary(4) -- a newer minor after login
        Fake.tick(10)
        assert.are.same({}, Fake.printed)
        assert.are.same({}, _G.SlashCmdList)
        local added = {}
        for k in pairs(_G) do
            if not before[k] then
                added[#added + 1] = tostring(k)
            end
        end
        assert.are.same({ "LibStub" }, added)
    end)

    it("names no chat, slash or print call in its code", function()
        local hits = {}
        local pats = { "print%s*%(", "DEFAULT_CHAT_FRAME", "ChatFrame", "SLASH_", "SlashCmdList" }
        for line in io.lines(ROOT .. "LibHiddenValues.toc") do
            line = line:gsub("\r", "")
            if line:match("%.lua$") and not line:match("^Libs") then
                local n = 0
                for l in io.lines(ROOT .. line:gsub("\\", "/")) do
                    n = n + 1
                    local code = l:gsub("%-%-.*$", "")
                    for _, pat in ipairs(pats) do
                        if code:find(pat) then
                            hits[#hits + 1] = line .. ":" .. n .. ": " .. l
                        end
                    end
                end
            end
        end
        assert.are.same({}, hits)
    end)

    it("answers every diagnostic fact through getters", function()
        W.unit.target = { health = 0.6 }
        assert.are.same({ nil, nil, false }, { lib:GetSelfTest() })
        assert.are.same({ 0, 256, 0, 64, 8 }, { lib:GetPool() }) -- nothing is built before login
        local kinds = lib:GetKinds()
        assert.are.equal(12, #kinds)
        assert.are.same({ kind = "health", state = "pending" }, kinds[1])
        assert.are.same({ kind = "power", state = "pending" }, kinds[2])
        assert.are.same({ kind = "aura", state = "pending" }, kinds[9])
        assert.are.same({ kind = "cooldown", state = "unavailable", reason = "unproven" }, kinds[3])
        local seen = {}
        for i, row in ipairs(kinds) do
            assert.is_nil(seen[row.kind], i)
            seen[row.kind] = true
            assert.is_true(lib.KNOWN[row.kind], row.kind)
        end
        local a = lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50 } })
        lib:Watch("B", { kind = "health", unit = "target", edges = { 50 } })
        lib:Watch("B", { kind = "power", unit = "player", power = Enum.PowerType.Mana, edges = { 30 } })
        lib:Watch("B", { kind = "health", unit = "player", edges = { 40 } }):Release()
        Fake.login()
        Fake.tick(10)
        local pass, lines, running = lib:GetSelfTest()
        assert.is_true(pass)
        assert.is_false(running)
        assert.truthy(lines[#lines]:find("selftest PASS", 1, true))
        assert.are.same({ kind = "health", state = "ready" }, lib:GetKinds()[1])
        assert.are.same({
            {
                kind = "health",
                unit = "target",
                predicted = true,
                handles = 2,
                bars = 2,
                mode = "edges",
                active = true,
            },
            {
                kind = "power",
                unit = "player",
                power = 0,
                predicted = true,
                handles = 1,
                bars = 1,
                mode = "edges",
                max = 2000,
                active = true,
            },
        }, lib:GetSources())
        assert.are.same({ #lib.barFrame, 256, 0, 64, 8 }, { lib:GetPool() })
        assert.is_true(#lib.barFrame >= 32)
        assert.are.equal(3, (lib:GetStats()))
        lib:SelfTest()
        assert.is_true(select(3, lib:GetSelfTest()))
        assert.is_true((lib:GetSelfTest())) -- the earlier verdict stands while a run is going
        Fake.tick(60)
        a:Release()
        assert.are.equal(1, lib:GetSources()[1].handles)
    end)
end)
