-- Headless tests for VirtualGameAPI-1.0 under a fake _G. Run from the repository root:
--   busted
local LIB = "Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua"
local INVENTORY = "tools/api_inventory.txt"

local function readInventory()
    local names = {}
    for line in io.lines(INVENTORY) do
        line = line:gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then names[#names + 1] = line end
    end
    return names
end

-- Installs a fake function for `name` ("UnitPower" or "C_Spell.GetSpellCooldown") in _G and
-- returns the call log it appends to.
local function fake(name, calls)
    local ns, key = name:match("^([%w_]+)%.([%w_]+)$")
    local f = function(...)
        calls[#calls + 1] = { name = name, n = select("#", ...), ... }
        return "real:" .. name
    end
    if ns then
        _G[ns] = _G[ns] or {}
        _G[ns][key] = f
    else
        _G[name] = f
    end
end

local function unfake(name)
    local ns, key = name:match("^([%w_]+)%.([%w_]+)$")
    if ns then _G[ns][key] = nil else _G[name] = nil end
end

local function fakeLibStub()
    local libs = {}
    local LibStub = setmetatable({}, { __call = function(self, major, silent)
        return libs[major] or (not silent and error("missing " .. major)) or nil
    end })
    function LibStub:NewLibrary(major, minor)
        if libs[major] then return nil end
        libs[major] = {}
        return libs[major]
    end
    function LibStub:GetLibrary(major, silent) return self(major, silent) end
    return LibStub
end

describe("VirtualGameAPI-1.0", function()
    local names, calls, VGA

    setup(function()
        names = readInventory()
        assert.is_true(#names > 100, "inventory should list the whole read surface")
    end)

    before_each(function()
        calls = {}
        _G.LibStub = fakeLibStub()
        _G.issecretvalue = function() return false end
        for _, n in ipairs(names) do fake(n, calls) end
        VGA = assert(loadfile(LIB))()
        VGA = VGA or _G.LibStub("VirtualGameAPI-1.0")
    end)

    after_each(function()
        for _, n in ipairs(names) do unfake(n) end
        _G.LibStub = nil
        _G.issecretvalue = nil
    end)

    local function entry(name)
        local ns, key = name:match("^([%w_]+)%.([%w_]+)$")
        if ns then return VGA[ns] and VGA[ns][key] end
        return VGA[name]
    end

    it("has a status and a function for every inventory name", function()
        for _, n in ipairs(names) do
            local s = VGA.Status(n)
            assert.is_truthy(s, n .. " has no status")
            assert.is_true(s == "passthrough" or s == "stub", n .. " status is " .. tostring(s))
            assert.is_function(entry(n), n .. " has no function")
            assert.is_string(VGA.Why(n), n .. " has no reason")
        end
    end)

    it("has no entry outside the inventory", function()
        local set = {}
        for _, n in ipairs(names) do set[n] = true end
        for _, n in ipairs(VGA.Inventory()) do
            assert.is_true(set[n] == true, n .. " is in the library but not in tools/api_inventory.txt")
        end
        assert.are.equal(#names, #VGA.Inventory())
    end)

    it("passes every passthrough call to the real function with its arguments", function()
        for _, n in ipairs(names) do
            if VGA.Status(n) == "passthrough" then
                calls = {}
                for _, m in ipairs(names) do unfake(m); fake(m, calls) end
                _G.LibStub = fakeLibStub(); VGA = assert(loadfile(LIB))()
                local r = entry(n)("player", 7, nil)
                assert.are.equal("real:" .. n, r, n)
                assert.are.equal(1, #calls, n .. " should call exactly once")
                assert.are.same({ name = n, n = 3, "player", 7, nil }, calls[1])
            end
        end
    end)

    it("never calls the real function from a stub", function()
        for _, n in ipairs(names) do
            if VGA.Status(n) == "stub" then
                calls = {}
                assert.has_no.errors(function() entry(n)("player", 1) end, n)
                assert.are.equal(0, #calls, n .. " stub must not call the game")
            end
        end
    end)

    it("returns the documented shapes from the critical stubs", function()
        assert.are.equal(0, VGA.UnitPower("player", 1))
        assert.are.equal(0, VGA.UnitHealth("target"))
        assert.is_nil(VGA.C_UnitAuras.GetBuffDataByIndex("player", 1))
        assert.is_nil(VGA.C_UnitAuras.GetDebuffDataByIndex("target", 1))
        assert.is_nil(VGA.C_UnitAuras.GetPlayerAuraBySpellID(1))
        local cd = VGA.C_Spell.GetSpellCooldown(61304)
        assert.are.same({ startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }, cd)
        assert.are.equal(cd, VGA.C_Spell.GetSpellCooldown(1), "stub tables are shared, not allocated per call")
        local ch = VGA.C_Spell.GetSpellCharges(1)
        assert.are.same({ currentCharges = 1, maxCharges = 1, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }, ch)
        assert.is_nil(VGA.C_Spell.GetSpellLossOfControlCooldown(1))
        assert.is_nil(VGA.CombatLogGetCurrentEventInfo())
        assert.are.same({ false, "", 0, 0, 0 }, { VGA.GetTotemInfo(1) })
        assert.are.same({ 0, 0 }, { VGA.GetPowerRegenForPowerType(1) })
        assert.are.same({ 2, nil }, { VGA.UnitAttackSpeed("player") })
        assert.are.same({ 0, 0, 0, 0 }, { VGA.GetUnitSpeed("player") })
    end)

    it("passes the player's own cast info through and hides every other unit's", function()
        assert.are.equal("real:UnitCastingInfo", VGA.UnitCastingInfo("player"))
        assert.is_nil(VGA.UnitCastingInfo("target"))
        assert.are.equal("real:UnitChannelInfo", VGA.UnitChannelInfo("player"))
        assert.is_nil(VGA.UnitChannelInfo("target"))
    end)

    it("records a passthrough whose real function is absent as missing and returns nil", function()
        unfake("UnitExists")
        _G.LibStub = fakeLibStub(); VGA = assert(loadfile(LIB))()
        assert.are.equal("missing", VGA.Status("UnitExists"))
        assert.is_nil(VGA.UnitExists("player"))
        local listed = false
        for _, n in ipairs(VGA.Stubs()) do if n == "UnitExists" then listed = true end end
        assert.is_true(listed, "missing entries are listed by Stubs()")
    end)

    it("lists exactly the stubbed names, sorted", function()
        local stubs = VGA.Stubs()
        for i = 2, #stubs do assert.is_true(stubs[i - 1] < stubs[i], "Stubs() must be sorted") end
        local set = {}
        for _, n in ipairs(stubs) do set[n] = true end
        for _, n in ipairs(names) do
            assert.are.equal(VGA.Status(n) ~= "passthrough", set[n] == true, n)
        end
    end)

    it("does not know names outside the inventory", function()
        assert.is_nil(VGA.Status("NoSuchFunction"))
    end)
end)
