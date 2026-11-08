-- tools/wowsims/talents.lua (dev-only): a kit's spec:RegisterTalents table from Forever's talent tree
-- (wowsims/forever ui/sim/talents/trees/<class>.json, generated from the game files; MIT). Run from the repository root:
--   [WOWSIMS_TREES=<dir of <class>.json>] .lua/bin/lua tools/wowsims/talents.lua all|<class>... [--write]
-- Without --write it prints each class's table; with it, rewrites the kit's block and copies the trees to
-- tests/Forever/fixtures/talent_trees/ (what tests/Forever/talent_trees_spec.lua reads).
-- Rules: tree = the JSON's order (1..3), then each tree's talents in its order, { tree, spellId, maxPoints };
-- a spell ID the kit already registers keeps its name (code reads `talent.<name>.rank`); a registered row whose name is
-- the snake_case of an unmatched node's fancyName is that node under a new spell ID (the Classic id moved on Forever);
-- any other new node is named snake_case(fancyName); a registered row absent from the tree is dropped unless M.KEEP
-- (by class) lists its name (code reads it); its trailing comment travels with it.
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path
local json = require("dkjson")

local M = {}

-- name -> why, for rows Forever's tree lacks that code still reads
M.KEEP = {}

M.CLASSES = { "druid", "hunter", "mage", "paladin", "priest", "rogue", "shaman", "warlock", "warrior" }

local function slurp(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a")
    f:close()
    return s
end

--- The class's tree list ({ { name, talents = { { fancyName, spellId, maxPoints, ... } } } x3) read from `dir`.
function M.trees(class, dir)
    return assert(json.decode(slurp(dir .. "/" .. class .. ".json")))
end

function M.snake(fancy)
    return (fancy:lower():gsub("'", ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

local OPEN = "spec:RegisterTalents({\n"

--- The kit text's RegisterTalents block: its start and end byte offsets and the rows
--- { name, tree, spell, max, comment } in file order.
function M.parseKit(text)
    local s = assert(text:find(OPEN, 1, true), "no RegisterTalents block")
    local e = assert(text:find("\n})\n", s, true), "unterminated RegisterTalents block")
    local rows = {}
    for line in text:sub(s + #OPEN, e):gmatch("[^\n]+") do
        local name, tree, spell, max, rest = line:match("^%s*([%w_]+)%s*=%s*{%s*(%d+),%s*(%d+),%s*(%d+)%s*},?%s*(.*)$")
        if name then
            rows[#rows + 1] = {
                name = name,
                tree = tonumber(tree),
                spell = tonumber(spell),
                max = tonumber(max),
                comment = rest:match("^%-%-.*") or nil,
            }
        end
    end
    return s, e, rows
end

--- The new rows (same shape, in tree order, each with `treeName` on a tree's first) for `trees` over the kit's old `rows`.
function M.build(trees, rows)
    local bySpell, byName, inTree = {}, {}, {}
    for _, r in ipairs(rows) do
        bySpell[r.spell], byName[r.name] = r, r
    end
    for _, tr in ipairs(trees) do
        for _, t in ipairs(tr.talents) do
            inTree[t.spellId] = true
        end
    end
    local out, used = {}, {}
    for ti, tr in ipairs(trees) do
        for i, t in ipairs(tr.talents) do
            local old = bySpell[t.spellId]
            if not old then
                local alias = byName[M.snake(t.fancyName)]
                if alias and not inTree[alias.spell] then
                    old = alias
                end
            end
            local name = old and old.name or M.snake(t.fancyName)
            assert(not used[name], "name taken twice: " .. name)
            used[name] = true
            out[#out + 1] = {
                name = name,
                tree = ti,
                spell = t.spellId,
                max = t.maxPoints,
                comment = old and old.comment or nil,
                header = i == 1 and ("%s (tree %d)"):format(tr.name, ti) or nil,
            }
        end
    end
    local dropped = {}
    for _, r in ipairs(rows) do
        if not used[r.name] then
            if M.KEEP[r.name] then
                out[#out + 1] = r
                used[r.name] = true
            else
                dropped[#dropped + 1] = r
            end
        end
    end
    return out, dropped
end

function M.render(rows)
    local out = {}
    for _, r in ipairs(rows) do
        if r.header then
            out[#out + 1] = "    -- " .. r.header
        end
        out[#out + 1] = ("    %s = { %d, %d, %d },%s"):format(
            r.name,
            r.tree,
            r.spell,
            r.max,
            r.comment and " " .. r.comment or ""
        )
    end
    return table.concat(out, "\n") .. "\n"
end

local function main(args)
    local dir = os.getenv("WOWSIMS_TREES") or (os.getenv("HOME") .. "/src/wowsims-pin-e5a9cd2a2d/ui/sim/talents/trees")
    local write, list = false, {}
    for _, a in ipairs(args) do
        if a == "--write" then
            write = true
        elseif a == "all" then
            for _, c in ipairs(M.CLASSES) do
                list[#list + 1] = c
            end
        else
            list[#list + 1] = a
        end
    end
    for _, class in ipairs(list) do
        local Class = class:sub(1, 1):upper() .. class:sub(2)
        local path = ("src/Hekili_%s/%s.lua"):format(Class, Class)
        local text = slurp(path)
        local s, e, rows = M.parseKit(text)
        local out, dropped = M.build(M.trees(class, dir), rows)
        io.stderr:write(("%s: %d rows -> %d; dropped:"):format(class, #rows, #out))
        for _, r in ipairs(dropped) do
            io.stderr:write((" %s(%d)"):format(r.name, r.spell))
        end
        io.stderr:write("\n")
        if write then
            local f = assert(io.open(path, "wb"))
            f:write(text:sub(1, s + #OPEN - 1), M.render(out), text:sub(e + 1))
            f:close()
            os.execute(("cp '%s/%s.json' tests/Forever/fixtures/talent_trees/"):format(dir, class))
        else
            io.write(M.render(out))
        end
    end
end

if arg and arg[0] and arg[0]:find("talents%.lua$") then
    main(arg)
end

return M
