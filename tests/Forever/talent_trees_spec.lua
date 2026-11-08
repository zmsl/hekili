-- tests/Forever/talent_trees_spec.lua: every kit's spec:RegisterTalents table follows Forever's talent tree
-- (tests/Forever/fixtures/talent_trees/<class>.json, wowsims/forever ui/sim/talents/trees at the pin, MIT; regenerate with
-- tools/wowsims/talents.lua), the talents the kits and shipped packs read are registered, and spec detection (the
-- core's ns.TreePoints over the kit's table) counts each shipped build string's own points per tree.
-- Spec detection counts only REGISTERED nodes, so a missing or mis-filed node moves a build's points between trees.
local gen = assert(loadfile("tools/wowsims/talents.lua"))()
local ex = assert(loadfile("tools/wowsims/export.lua"))()
local json = require("dkjson")

local TREES = "tests/Forever/fixtures/talent_trees"
-- classes whose kit still follows the Classic tree (its lane has not merged); empty it in that class's commit
local PENDING = {}

local function slurp(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a")
    f:close()
    return s
end
local function ls(glob)
    local p = assert(io.popen("ls " .. glob .. " 2>/dev/null"))
    local out = {}
    for l in p:lines() do
        out[#out + 1] = l
    end
    p:close()
    return out
end

local ns = {}
assert(loadfile("src/Hekili/Engine/Schema/Trees.lua"))("Hekili", ns)

local function kit(class)
    local Class = class:sub(1, 1):upper() .. class:sub(2)
    local _, _, rows = gen.parseKit(slurp(("src/Hekili_%s/%s.lua"):format(Class, Class)))
    local reg = {} -- RegisterTalents' shape
    for _, r in ipairs(rows) do
        reg[r.name] = { r.tree, r.spell, r.max }
    end
    return rows, reg, Class
end

--- Every `talent.<name>` the class's kit and shipped packs (Lua, APL text) read, { [name] = first file }.
local function reads(Class, files)
    local out = {}
    for _, path in ipairs(files or ls(("src/Hekili_%s/*.lua src/Hekili_%s/APLs/*"):format(Class, Class))) do
        for name in slurp(path):gmatch("talent%.([%a_][%w_]*)") do
            out[name] = out[name] or path
        end
    end
    return out
end

for _, class in ipairs(gen.CLASSES) do
    describe("the " .. class .. " kit's talent table", function()
        local trees = gen.trees(class, TREES)
        local rows, reg, Class = kit(class)

        it("registers every node of Forever's tree in its tree with its max rank", function()
            if PENDING[class] then
                pending("the Classic tree until its lane merges")
            end
            local byName = {}
            for _, r in ipairs(rows) do
                byName[r.spell] = r
            end
            local bad = {}
            for ti, tr in ipairs(trees) do
                for _, t in ipairs(tr.talents) do
                    local r = byName[t.spellId]
                    if not (r and r.tree == ti and r.max == t.maxPoints) then
                        bad[#bad + 1] = ("%s %d: tree %d max %d, kit %s"):format(
                            t.fancyName,
                            t.spellId,
                            ti,
                            t.maxPoints,
                            r and ("tree %d max %d"):format(r.tree, r.max) or "absent"
                        )
                    end
                end
            end
            assert.same({}, bad)
        end)

        it("holds no row Forever's tree lacks, but the allow-listed", function()
            if PENDING[class] then
                pending("the Classic tree until its lane merges")
            end
            local inTree = {}
            for _, tr in ipairs(trees) do
                for _, t in ipairs(tr.talents) do
                    inTree[t.spellId] = true
                end
            end
            local extra = {}
            for _, r in ipairs(rows) do
                if not inTree[r.spell] and not gen.KEEP[r.name] then
                    extra[#extra + 1] = r.name .. " " .. r.spell
                end
            end
            assert.same({}, extra)
        end)

        it("resolves every talent the kit and its packs read to a registered name", function()
            local missing = {}
            for name, path in pairs(reads(Class)) do
                if not reg[name] then
                    missing[#missing + 1] = name .. " (" .. path .. ")"
                end
            end
            table.sort(missing)
            assert.same({}, missing)
        end)
    end)
end

describe("spec detection counts each shipped build's own points per tree", function()
    for _, path in ipairs(ls("tools/wowsims/specs/*.lua")) do
        local spec = path:match("([^/]+)%.lua$")
        local r = dofile(path)
        local class = r.talentTree
        it(spec, function()
            if PENDING[class] then
                pending("the Classic tree until its lane merges")
            end
            local req = assert(json.decode(slurp("tests/Forever/wowsims/" .. spec .. ".json")))
            local str = req.raid.parties[1].players[1].talentsString
            local trees = gen.trees(class, TREES)
            local _, reg = kit(class)
            local max, want, rank = {}, { 0, 0, 0 }, {}
            for _, tr in ipairs(trees) do
                for _, t in ipairs(tr.talents) do
                    max[t.spellId] = t.maxPoints
                end
            end
            for _, t in ipairs(ex.talents(str, trees)) do -- { rank-1 spell, rank, tree }
                assert.is_true(t[2] <= max[t[1]], spec .. ": rank above max at " .. t[1])
                rank[t[1]], want[t[3]] = t[2], want[t[3]] + t[2]
            end
            local got = ns.TreePoints(reg, function(entry)
                return rank[entry[2]]
            end)
            assert.same(want, { got[1], got[2], got[3] }, spec .. " " .. str)
        end)
    end

    it("counts Enhancement as 17/31/3", function()
        local req = assert(json.decode(slurp("tests/Forever/wowsims/shaman_enhancement.json")))
        local trees, reg = gen.trees("shaman", TREES), select(2, kit("shaman"))
        local rank = {}
        for _, t in ipairs(ex.talents(req.raid.parties[1].players[1].talentsString, trees)) do
            rank[t[1]] = t[2]
        end
        local got = ns.TreePoints(reg, function(entry)
            return rank[entry[2]]
        end)
        assert.same({ 17, 31, 3 }, { got[1], got[2], got[3] })
    end)
end)
