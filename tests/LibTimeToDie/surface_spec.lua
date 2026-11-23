-- tests/LibTimeToDie/surface_spec.lua: the library is a pure API. No slash command, no chat output, no SavedVariables,
-- no Bindings, and no global but LibStub (and the fake client's own UnitCanAttack) over a whole session; the repository
-- names no host addon (tools/libtimetodie/check_standalone.sh).
local FAKE = "src/LibTimeToDie/Testing/FakeClient.lua"
local ROOT = "src/LibTimeToDie/"
local BASE = {} -- the globals before any test of this file (busted insulates each file)
for k in pairs(_G) do
    BASE[k] = true
end

local function tocLines()
    local lines = {}
    for line in io.lines(ROOT .. "LibTimeToDie.toc") do
        lines[#lines + 1] = line:gsub("\r", "")
    end
    return lines
end

describe("LibTimeToDie surface", function()
    it("names no host addon (tools/libtimetodie/check_standalone.sh)", function()
        local p = io.popen("bash tools/libtimetodie/check_standalone.sh 2>&1; echo rc=$?")
        local out = p:read("*a")
        p:close()
        assert.is_truthy(out:match("rc=0"), out)
    end)

    it("declares no SavedVariables and no Bindings in the TOC", function()
        local toc = table.concat(tocLines(), "\n")
        assert.is_nil(toc:match("SavedVariables"))
        assert.is_nil(toc:match("[Bb]indings"))
    end)

    it("names no chat, slash or print call in its code", function()
        local hits = {}
        local pats = { "print%s*%(", "DEFAULT_CHAT_FRAME", "ChatFrame", "SLASH_", "SlashCmdList" }
        for _, line in ipairs(tocLines()) do
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

    it("adds no global but LibStub, prints nothing and registers no slash command over a whole session", function()
        for k in pairs(_G) do -- what earlier tests' copies left behind must not hide this one's
            if not BASE[k] then
                rawset(_G, k, nil)
            end
        end
        local before = {}
        local Fake = loadfile(FAKE)({
            before = function()
                for k in pairs(_G) do
                    before[k] = true
                end
            end,
        })
        local ttd = LibStub("LibTimeToDie-1.0")
        Fake.world.unit.target = { health = 0.9 }
        local h = ttd:Track("A", "target", function() end)
        ttd:HintBelow("A", 20, 1)
        Fake.login()
        Fake.tick(12)
        for p = 89, 40, -1 do
            Fake.world.unit.target.health = (p - 0.5) / 100
            Fake.advance(1)
        end
        h:Get()
        h:State()
        ttd:IsAvailable("target")
        ttd:GetStreams()
        ttd:GetMessage("lhv-missing")
        h:SetPaused(true)
        h:SetPaused(false)
        h:Release()
        ttd:ReleaseAll("A")
        Fake.tick(10)
        assert.are.same({}, Fake.printed)
        assert.are.same({}, _G.SlashCmdList)
        local added = {}
        for k in pairs(_G) do
            if not before[k] then
                added[#added + 1] = tostring(k)
            end
        end
        table.sort(added)
        assert.are.same({ "LibStub", "UnitCanAttack" }, added) -- UnitCanAttack is the fake client's, not the library's
        Fake.restore()
    end)
end)
