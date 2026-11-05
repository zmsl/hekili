-- tests/Forever/gear_coverage_spec.lua (gear-aware spec §14.4): the r33 rows by class and their status.
local fx = dofile("tests/Forever/fixtures/gear_coverage.lua")

local STATUS = { modelled = true, dropped = true, unshipped = true, todo = true }
local CLASSES = {
    ANY = 1,
    DRUID = 1,
    HUNTER = 1,
    MAGE = 1,
    PALADIN = 1,
    PRIEST = 1,
    ROGUE = 1,
    SHAMAN = 1,
    WARLOCK = 1,
    WARRIOR = 1,
}

local function packSource(class)
    local dir = "src/Hekili_" .. class:sub(1, 1) .. class:sub(2):lower()
    local out, p = {}, assert(io.popen("find " .. dir .. " -name '*.lua' | sort"))
    for path in p:lines() do
        local f = assert(io.open(path))
        out[#out + 1] = f:read("*a")
        f:close()
    end
    p:close()
    return table.concat(out, "\n")
end

describe("the gear coverage fixture", function()
    it("gives every row an id, a known class and a status", function()
        local seen, bad = {}, {}
        for _, r in ipairs(fx.rows) do
            local id = tostring(r.id)
            if seen[id] or not CLASSES[r.class] or not STATUS[r.status] then
                bad[#bad + 1] = id .. " (" .. tostring(r.class) .. ", " .. tostring(r.status) .. ")"
            end
            seen[id] = true
        end
        assert.are.same({}, bad)
    end)
    it("explains every dropped or unshipped row", function()
        local bad = {}
        for _, r in ipairs(fx.rows) do
            if (r.status == "dropped" or r.status == "unshipped") and not (type(r.why) == "string" and r.why ~= "") then
                bad[#bad + 1] = r.id
            end
        end
        assert.are.same({}, bad)
    end)
    it("registers a modelled row's keys in the class's pack", function()
        local bad, src = {}, {}
        for _, r in ipairs(fx.rows) do
            if r.status == "modelled" then
                src[r.class] = src[r.class] or packSource(r.class)
                assert.is_true(type(r.keys) == "table" and #r.keys > 0, r.id .. " has no keys")
                for _, k in ipairs(r.keys) do
                    if
                        not (
                            src[r.class]:find(':RegisterGear("' .. k .. '"', 1, true)
                            or src[r.class]:find(':RegisterSetBonus("' .. k .. '"', 1, true)
                        )
                    then
                        bad[#bad + 1] = r.id .. ": " .. k
                    end
                end
            end
        end
        assert.are.same({}, bad)
    end)
    it("has no todo row in a finished class, and its ids match the report", function()
        for _, class in ipairs(fx.done) do
            local have, want = {}, {}
            for _, r in ipairs(fx.rows) do
                if r.class == class then
                    assert.is_true(r.status ~= "todo", r.id .. " is still todo")
                    have[#have + 1] = r.id
                end
            end
            for _, id in ipairs(fx.expected[class] or {}) do
                want[#want + 1] = id
            end
            table.sort(have)
            table.sort(want)
            assert.are.same(want, have, class)
        end
    end)
end)
