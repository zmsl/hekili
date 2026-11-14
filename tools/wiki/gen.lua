-- tools/wiki/gen.lua: the wiki's generated tables and its check (docs/wiki/README.md).
--   lua tools/wiki/gen.lua write   rewrites every GENERATED region of docs/wiki/*.md (`make wiki-tables`)
--   lua tools/wiki/gen.lua check   fails on a stale region, a dead link, a bold label or command that names nothing,
--                                  an expression that no longer evaluates, a command not reviewed, or banned content;
--                                  open TODO placeholders and missing screenshots are warnings (`make wiki-check`)
-- Run from the repository root. The collectors boot the addon headless (tools/wiki/boot.lua), one boot per class.
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path

local markers = require("tools.wiki.markers")
local check = require("tools.wiki.check")
local text = require("tools.wiki.text")
local manifest = require("tools.wiki.manifest")

local DIR = "docs/wiki/"

local function slurp(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local s = f:read("*a")
    f:close()
    return s
end

--- The pages: { [name] = text }, name = the file name without .md.
local function pages()
    local out = {}
    local p = assert(io.popen("ls " .. DIR))
    for file in p:lines() do
        local name = file:match("^(.+)%.md$")
        if name and name ~= "README" then -- README.md is for contributors, not a wiki page
            out[name] = assert(slurp(DIR .. file))
        end
    end
    p:close()
    return out
end

local function collector(name)
    return require("tools.wiki.collect." .. name)
end

local cache = {}

--- The Markdown of table `name` (a manifest entry).
local function render(name)
    if cache[name] then
        return cache[name]
    end
    local def = manifest[name]
    assert(def, "GENERATED:" .. name .. " is not in tools/wiki/manifest.lua")
    local c = collector(def.collector)
    local raw = c[def.fn or "rows"](def)
    local rows = {}
    for i, r in ipairs(raw) do
        local row = {}
        if def.columns then
            for j, col in ipairs(def.columns) do
                row[j] = r[col]
            end
        elseif def.pick then
            for j, col in ipairs(def.pick) do
                row[j] = r[col]
            end
        else
            row = r
        end
        rows[i] = row
    end
    local s = text.table(def.headers, rows)
    if def.note then
        s = s .. "\n\n" .. def.note
    end
    cache[name] = s
    return s
end

local function exists(path)
    return slurp(DIR .. path) ~= nil
end

-- Every English string of Locales/enUS.lua, stripped as option labels are.
local function enus()
    local out = {}
    local s = assert(slurp("src/Hekili/Locales/enUS.lua"))
    for key in s:gmatch('\nL%["(.-)"%]%s*=') do
        out[text.strip((key:gsub("\\n", "\n")))] = true
    end
    return out
end

local function write()
    local changed = 0
    for name, s in pairs(pages()) do
        local fresh = markers.rewrite(s, render, name)
        if fresh ~= s then
            local f = assert(io.open(DIR .. name .. ".md", "wb"))
            f:write(fresh)
            f:close()
            changed = changed + 1
            print("wiki-tables: rewrote " .. name .. ".md")
        end
    end
    print(("wiki-tables: %d page(s) changed"):format(changed))
end

local function run()
    local ps = pages()
    local errors, warnings = {}, {}
    local function add(list, more)
        for _, m in ipairs(more) do
            list[#list + 1] = m
        end
    end
    add(errors, check.stale(ps, render))
    local e, w = check.links(ps, exists)
    add(errors, e)
    add(warnings, w)
    add(errors, check.labels(ps, collector("options").labels(), enus()))
    add(errors, check.commands(ps, collector("commands").words()))
    local _, _, problems = collector("commands").load()
    add(errors, problems)
    local used = {}
    for name, s in pairs(ps) do
        local ok, names = pcall(markers.names, s, name)
        for _, region in ipairs(ok and names or {}) do
            used[region] = true
        end
    end
    for region, def in pairs(manifest) do
        if def.collector == "expressions" and used[region] then
            add(errors, collector("expressions").problems(def))
        end
    end
    add(errors, check.banned(ps))
    add(warnings, check.todos(ps))
    for _, m in ipairs(warnings) do
        print("warning: " .. m)
    end
    for _, m in ipairs(errors) do
        print("error: " .. m)
    end
    print(("wiki-check: %d error(s), %d warning(s)"):format(#errors, #warnings))
    return #errors == 0
end

local mode = arg[1]
if mode == "write" then
    write()
elseif mode == "check" then
    if not run() then
        os.exit(1)
    end
else
    io.stderr:write("usage: lua tools/wiki/gen.lua write | check\n")
    os.exit(2)
end
