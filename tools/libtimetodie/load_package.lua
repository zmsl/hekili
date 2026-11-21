-- Loads a packaged LibTimeToDie folder (tools/libtimetodie/package.sh) through its TOC on the bundled LibHiddenValues'
-- fake client, as the game would: XML includes and scripts in order, paths relative to each file. Then both libraries
-- must be registered and a target track must come alive. Usage: lua load_package.lua <folder>. Stock Lua 5.1.
local dir = assert(arg[1], "usage: load_package.lua <LibTimeToDie folder>") .. "/"
local Fake = dofile(dir .. "Libs/LibHiddenValues/Testing/FakeClient.lua")
-- The fake loaded LibHiddenValues from the bundled copy; the TOC loads it again (an equal minor: LibStub keeps the
-- first, the second copy's files return), as a second copy would in the game.

local loaded = {}
local function load(path)
    path = path:gsub("\\", "/")
    loaded[#loaded + 1] = path
    if path:match("%.xml$") then
        local base = path:match("^(.*/)") or ""
        local f = assert(io.open(path, "rb"))
        local xml = f:read("*a")
        f:close()
        for tag, file in xml:gmatch('<(%a+) file="([^"]+)"') do
            assert(tag == "Script" or tag == "Include", tag)
            load(base .. file)
        end
    else
        assert(loadfile(path))()
    end
end

for line in io.lines(dir .. "LibTimeToDie.toc") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") then
        load(dir .. line)
    end
end

rawset(_G, "UnitCanAttack", function()
    return true
end)
Fake.world.unit.target = { health = 0.5 }
local ttd = assert(LibStub("LibTimeToDie-1.0", true), "LibTimeToDie not registered")
assert(LibStub("LibHiddenValues-1.0", true), "LibHiddenValues not registered")
assert(Fake.login(), "LibHiddenValues' self-test did not pass")
local h = assert(ttd:Track("Check", "target"))
Fake.tick(12)
assert(h:State() == "unknown", tostring(h:State()))
Fake.restore()
-- A consumer's tests: the packaged Testing/FakeClient.lua finds the bundled LibHiddenValues.
Fake = dofile(dir .. "Testing/FakeClient.lua")
Fake.world.unit.target = { health = 0.5 }
assert(Fake.login(), "LibHiddenValues' self-test did not pass")
h = assert(LibStub("LibTimeToDie-1.0"):Track("Check", "target"))
Fake.tick(12)
assert(h:State() == "unknown", tostring(h:State()))
Fake.restore()
print("ok: the package loads " .. #loaded .. " files through its TOC and tracks the target; its fake client runs")
