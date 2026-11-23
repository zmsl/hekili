-- Testing/FakeClient.lua: the real LibTimeToDie on LibHiddenValues' fake client, for the library's own suite and for
-- any consumer's tests. Not in the TOC: the game never loads it. Stock Lua 5.1.
--
--   local Fake = dofile("libs/LibTimeToDie/Testing/FakeClient.lua")  -- LibHiddenValues' fake, both libraries loaded
--   Fake.world.unit.target = { health = 1.0 }  -- fractions 0-1, as the client has them
--   dofile("MyAddon.lua")                      -- calls LibStub("LibTimeToDie-1.0"):Track(...) as in the game
--   Fake.login()                               -- login, then frames until LibHiddenValues' self-test has passed
--   Fake.tick(12)                              -- priming: about 10 frames
--   Fake.world.unit.target.health = 0.62
--   Fake.advance(0.5)
--   Fake.restore()
--
-- It is LibHiddenValues' Testing/FakeClient.lua (its header lists the world and the knobs; Fake.event fires a client
-- event, e.g. "PLAYER_TARGET_CHANGED" after you swap Fake.world.unit.target) with this library loaded after it, plus
-- UnitCanAttack (W.unit[token].friendly = true: a friendly unit; W.secretAttack = true: the answer is a secret). That
-- file is looked up in Libs/LibHiddenValues (a copy kept inside this folder), then beside this folder
-- (libs/LibHiddenValues next to libs/LibTimeToDie); elsewhere pass its path:
-- loadfile(path)({ lhv = "path/to/LibHiddenValues/Testing/FakeClient.lua", before = fn }) (fn runs once the fake globals
-- exist, before any library loads). Fake.loadTimeToDie() loads this library
-- again (the files of its TOC, in order).
local opts = ... or {}
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local root = here .. "../"

-- LibHiddenValues' fake: a copy kept inside this folder (Libs/LibHiddenValues) or the sibling folder.
local bundled = root .. "Libs/LibHiddenValues/Testing/FakeClient.lua"
local f = io.open(bundled, "rb")
if f then
    f:close()
end
local Fake = loadfile(opts.lhv or (f and bundled or root .. "../LibHiddenValues/Testing/FakeClient.lua"))({
    before = opts.before,
})
local W = Fake.world

-- UnitCanAttack("player", unit): true unless W.unit[unit].friendly; false without the unit; W.secretAttack: a secret.
local savedCanAttack = rawget(_G, "UnitCanAttack")
rawset(_G, "UnitCanAttack", function(_, unit)
    local u = W.unit[unit]
    local v = u ~= nil and not u.friendly
    if W.secretAttack then
        return Fake.secret(v)
    end
    return v
end)
local restore = Fake.restore
function Fake.restore()
    rawset(_G, "UnitCanAttack", savedCanAttack)
    restore()
end

function Fake.loadTimeToDie()
    for line in io.lines(root .. "LibTimeToDie.toc") do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") and not line:match("%.xml$") then -- the bundled XML: loaded above
            local path = root .. line:gsub("\\", "/")
            assert(loadfile(path))()
        end
    end
end

Fake.loadTimeToDie()
return Fake
