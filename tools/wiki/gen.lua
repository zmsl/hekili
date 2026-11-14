-- tools/wiki/gen.lua: the wiki's generated tables and its check (docs/wiki/README.md).
--   lua tools/wiki/gen.lua build   writes a copy of docs/wiki/ with every GENERATED region filled to build/wiki/
--                                  (`make wiki-build`); docs/wiki/ itself is never written (its regions stay empty)
--   lua tools/wiki/gen.lua check   fails on a malformed or unknown marker, a dead link, a bold label or command that names nothing,
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

-- Every English string of every addon's Locales/enUS.lua (the core's and each class pack's), stripped as option
-- labels are.
local function enus()
    local out = {}
    local p = assert(io.popen("ls src/*/Locales/enUS.lua"))
    for path in p:lines() do
        local s = assert(slurp(path))
        for key in s:gmatch('\nL%["(.-)"%]%s*=') do
            out[text.strip((key:gsub("\\n", "\n")))] = true
        end
    end
    p:close()
    return out
end

local OUT = ((arg[2] or "build/wiki"):gsub("/*$", "/")) -- the second argument is for the tests

local function build()
    -- Contributor files (README.md, data/, .gitkeep) are not wiki content.
    os.execute("rm -rf " .. OUT .. " && mkdir -p " .. OUT)
    os.execute(
        "tar -C "
            .. DIR
            .. " --exclude=./README.md --exclude=./data --exclude=.gitkeep -cf - . | tar -C "
            .. OUT
            .. " -xf -"
    )
    local n = 0
    for name, s in pairs(pages()) do
        local f = assert(io.open(OUT .. name .. ".md", "wb"))
        f:write(markers.rewrite(s, render, name))
        f:close()
        n = n + 1
    end
    print(("wiki-build: %d page(s) written to %s"):format(n, OUT))
end

local function run()
    local ps = pages()
    local errors, warnings = {}, {}
    local function add(list, more)
        for _, m in ipairs(more) do
            list[#list + 1] = m
        end
    end
    local known = {}
    for region in pairs(manifest) do
        known[region] = true
    end
    add(errors, check.markers(ps, known))
    local retired = {}
    for line in (slurp(DIR .. "data/retired-pages.txt") or ""):gmatch("[^\n]+") do
        retired[#retired + 1] = line
    end
    add(errors, check.retired(ps, retired))
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
if mode == "build" then
    build()
elseif mode == "check" then
    if not run() then
        os.exit(1)
    end
else
    io.stderr:write("usage: lua tools/wiki/gen.lua build | check\n")
    os.exit(2)
end
