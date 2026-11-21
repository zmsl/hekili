-- tests/LibHiddenValues/secrets_spec.lua: secret safety (every read secret: nothing traps; a read's result is used once,
-- behind issecretvalue), zero allocation per steady frame, the driver unset when idle, and finite statistics with no
-- elapsed time (the client raises on a division by zero; stock Lua gives inf, so finiteness is what is checked).
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"
local ROOT = "src/LibHiddenValues/"

local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

describe("LibHiddenValues secrets and efficiency", function()
    local Fake, W, lib

    before_each(function()
        Fake = dofile(FAKE)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
    end)

    after_each(function()
        Fake.restore()
    end)

    for _, mode in ipairs({ "secret", "plain" }) do
        it("walks a fight with every read " .. mode .. " and no trap fires", function()
            W.secret = mode == "secret"
            W.secretBool = mode == "secret"
            W.unit.target = { health = 1.0 }
            local n = 0
            local function sink()
                n = n + 1
            end
            lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50, 80 } }, sink)
            lib:Watch("A", { kind = "health", unit = "player", edges = { 35 } }, sink)
            lib:Watch("B", { kind = "power", unit = "player", power = Enum.PowerType.Mana, edges = { 30, 60 } }, sink)
            assert(
                lib:Watch("B", { kind = "power", unit = "player", power = Enum.PowerType.Energy, edges = { 50 } }, sink)
            )
            Fake.login()
            for i = 1, 300 do
                W.unit.target.health = math.max(0, 1 - i / 250)
                W.unit.player.health = 1 - i / 1000
                W.unit.player.power[0] = (i % 100) / 100
                if i % 6 == 0 then
                    Fake.event("UNIT_HEALTH", "target")
                    Fake.event("UNIT_HEALTH", "player")
                end
                if i == 200 then
                    W.unit.target = { health = 0.7 }
                    Fake.event("PLAYER_TARGET_CHANGED")
                end
                Fake.tick(1)
            end
            lib:GetStats()
            lib:GetSources()
            lib:GetKinds()
            assert.are.same({}, Fake.errors)
            assert.is_true(n > 10)
        end)
    end

    it("uses each secret-returning read once, behind issecretvalue first", function()
        local reads = { "UnitHealthPercent", "UnitPowerPercent", "UnitIsDead", "UnitExists", "read" }
        local checked = 0
        for line in io.lines(ROOT .. "LibHiddenValues.toc") do
            line = line:gsub("\r", "")
            if line:match("%.lua$") and not line:match("^Libs") then
                local lines = {}
                for l in io.lines(ROOT .. line:gsub("\\", "/")) do
                    lines[#lines + 1] = l
                end
                for i, l in ipairs(lines) do
                    for _, r in ipairs(reads) do
                        if l:match("[%s%(=%.]" .. r .. "%(") and not l:match("^%s*%-%-") then
                            checked = checked + 1
                            local v = l:match("^%s*local ([%w_]+) = ")
                            local ret = l:match("^%s*return ")
                            local ok = ret or (v and lines[i + 1]:match("issecretvalue%(" .. v .. "%)"))
                            assert.is_truthy(ok, line .. ":" .. i .. ": " .. l)
                        end
                    end
                end
            end
        end
        assert.is_true(checked >= 5, checked)
    end)

    it("allocates nothing over 1000 steady frames of crossings", function()
        W.unit.target = { health = 1.0 }
        local n = 0
        local function sink()
            n = n + 1
        end
        lib:Watch("A", { kind = "health", unit = "target", edges = { 20, 50, 80 } }, sink)
        lib:Watch("A", { kind = "health", unit = "target", edges = { 50 } }, sink)
        lib:Watch("B", { kind = "power", unit = "player", power = Enum.PowerType.Mana, edges = { 30 } }, sink)
        Fake.login()
        local function frame(i)
            W.unit.target.health = (i % 37) / 36
            W.unit.player.power[0] = (i % 11) / 10
            Fake.tick(1)
        end
        for i = 1, 200 do
            frame(i)
        end
        collectgarbage("collect")
        collectgarbage("stop")
        local b = collectgarbage("count")
        for i = 1, 1000 do
            frame(i)
        end
        local grew = collectgarbage("count") - b
        collectgarbage("restart")
        assert.is_true(n > 200, n)
        assert.is_true(grew < 0.5, grew .. " KB")
    end)

    it("unsets the driver when nothing needs it", function()
        Fake.login()
        Fake.tick(1) -- the frame after the verdict finds nothing to do
        assert.is_nil(lib.drv:GetScript("OnUpdate"))
        local h = lib:Watch("A", { kind = "health", unit = "target", edges = { 20 } })
        Fake.tick(2)
        assert.is_nil(lib.drv:GetScript("OnUpdate")) -- no target: gone, not fed
        W.unit.target = { health = 0.5 }
        Fake.event("PLAYER_TARGET_CHANGED")
        assert.is_function(lib.drv:GetScript("OnUpdate"))
        h:Release()
        Fake.tick(2)
        assert.is_nil(lib.drv:GetScript("OnUpdate"))
    end)

    it("keeps statistics finite with no elapsed time", function()
        local stats = { lib:GetStats() }
        assert.are.equal(8, #stats)
        for i, x in ipairs(stats) do
            assert.is_true(finite(x), i)
        end
        Fake.login()
        lib.drive(0)
        lib.drive(0)
        for i, x in ipairs({ lib:GetStats() }) do
            assert.is_true(finite(x), i)
        end
        local h = lib:Watch("A", { kind = "health", unit = "player", edges = { 20 } })
        assert.is_true(finite(h:Latency()))
    end)
end)
