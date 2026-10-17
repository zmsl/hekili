-- tests/boundary_spec.lua
-- The core/content boundary (core leakage audit, docs/research/2026-10-16-core-leakage-audit.md): the core engine
-- (src/Hekili/Virtual/**, src/Hekili/Engine/**) names no ability, aura or talent key and no spell ID that the Forever
-- content (src/Hekili/Forever/**: Classes, Races, Shared) registers, and no class or form/stance name. Ported from Taco
-- Dog Forever's tests/boundary_spec.lua, which scans for a fixed word list; here the keys and IDs are
-- extracted from the content at test time, so a new ability is checked without being listed.
-- Code only: comments are skipped, and so is a string literal that is not a single identifier (a message or a
-- description); a one-word string (`buff["rend"]`, `"WARRIOR"`) is checked like an identifier.
local loaders = {
    Warrior = require("Forever.helpers.load_warrior"),
    Druid = require("Forever.helpers.load_druid"),
}

local CORE = { "src/Hekili/Virtual", "src/Hekili/Engine" }

-- Content names core may use, each with its reason.
local ALLOW_KEYS = {
    -- the resource vocabulary: core models resources generically by these names (Hekili's power type keys)
    rage = "a resource name",
    energy = "a resource name",
    mana = "a resource name",
    combo_points = "a resource name",
    health = "a resource name",
    focus = "a resource name",
    runic_power = "a resource name",
    -- generic words a content file also uses as a key
    form = "the Druid's any-form aura; core reads the client's shapeshift form generically",
    potion = "the shared potion ability; stock Engine/Spec.lua's RegisterPotion names its argument so",
}
local ALLOW_IDS = {
    [29515] = "the client's GCD spell (Constants), not content",
    [100] = "Charge's rank 1 ID, and the percent scale core divides by",
}

local CLASS_WORDS =
    { "warrior", "druid", "rogue", "mage", "priest", "warlock", "hunter", "paladin", "shaman", "deathknight" }

local function read(path)
    local f = assert(io.open(path))
    local s = f:read("*a")
    f:close()
    return s
end

-- Lua 5.1 tokens of `src` that matter here, as { kind, text, line }: "name", "number" and "string" (its contents);
-- comments and whitespace are dropped.
local function tokens(src)
    local out, i, line, n = {}, 1, 1, #src
    local function add(kind, text)
        out[#out + 1] = { kind, text, line }
    end
    local function advance(j) -- moves past src[i..j-1], counting lines
        local _, nl = src:sub(i, j - 1):gsub("\n", "")
        line = line + nl
        i = j
    end
    while i <= n do
        local c = src:sub(i, i)
        local long = src:match("^%[(=*)%[", i)
        local commentLong = src:match("^%-%-%[(=*)%[", i)
        if commentLong then
            local _, e = src:find("]" .. commentLong .. "]", i, true)
            advance((e or n) + 1)
        elseif src:sub(i, i + 1) == "--" then
            advance((src:find("\n", i, true) or n + 1))
        elseif long then
            local s = i + #long + 2
            local _, e = src:find("]" .. long .. "]", s, true)
            add("string", src:sub(s, (e or n) - #long - 2))
            advance((e or n) + 1)
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n and src:sub(j, j) ~= c do
                j = j + (src:sub(j, j) == "\\" and 2 or 1)
            end
            add("string", src:sub(i + 1, j - 1))
            advance(j + 1)
        elseif c:match("[%a_]") then
            local word = src:match("^[%w_]+", i)
            add("name", word)
            advance(i + #word)
        elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
            local num = src:match("^0[xX]%x+", i)
                or src:match("^%d*%.?%d*[eE][%+%-]?%d+", i)
                or src:match("^%d*%.?%d*", i)
            add("number", num)
            advance(i + #num)
        else
            advance(i + 1)
        end
    end
    return out
end

-- The content's keys and IDs: { keys = { [key] = where }, ids = { [id] = where } }.
local function content()
    local keys, ids = {}, {}
    local function id(v, where)
        if type(v) == "number" then
            ids[v] = ids[v] or where
        end
    end
    local function def(key, d, where)
        if type(key) == "string" then
            keys[key] = keys[key] or where
        end
        id(key, where)
        if type(d) ~= "table" then
            return
        end
        id(d.id, where)
        for _, c in ipairs(type(d.copy) == "table" and d.copy or { d.copy }) do
            def(c, nil, where)
        end
    end
    local function costMods(list, where)
        for _, m in ipairs(list or {}) do
            for _, s in ipairs(m.spells or {}) do
                id(s, where)
            end
        end
    end

    -- the class files, through their recording loaders (tests/Forever/helpers)
    local classFiles = io.popen("ls src/Hekili/Forever/Classes")
    for file in classFiles:lines() do
        local name = assert(file:match("^(%w+)%.lua$"), file)
        local loader = assert(loaders[name], "no recording loader for Forever/Classes/" .. file)
        local w = loader.load()
        local where = "Forever/Classes/" .. file
        for kind in pairs({ abilities = true, auras = true }) do
            for k, d in pairs(w[kind]) do
                def(k, d, where)
            end
        end
        for k, t in pairs(w.talents or {}) do
            def(k, nil, where)
            id(t[2], where)
        end
        costMods(w.costMods, where)
    end
    classFiles:close()

    -- the race and shared files, through Engine/Races.lua and Engine/Shared.lua against a recording `all`
    local saved = rawget(_G, "Hekili") or false
    local function run(path, token)
        local all = { abilities = {}, auras = {} }
        function all:RegisterAbility(k, d)
            self.abilities[k] = d
            def(k, d, path)
        end
        function all:RegisterAura(k, d)
            self.auras[k] = d
            def(k, d, path)
        end
        _G.Hekili = { State = { race_token = token }, Class = { specs = { [0] = all }, file = "WARRIOR" } }
        local any = setmetatable({}, {
            __index = function(t)
                return t
            end,
            __call = function() end,
            __concat = function()
                return ""
            end,
        })
        local ns = { Facade = any, UnitDebuff = any, UnitBuff = any }
        assert(loadfile("src/Hekili/Engine/Races.lua"))("Hekili", ns)
        assert(loadfile("src/Hekili/Engine/Shared.lua"))("Hekili", ns)
        -- a global the file reads at load (INVTYPE_*) answers `any`; Hekili and the Lua library stay real
        local chunk = assert(loadfile("src/Hekili/" .. path))
        setfenv(
            chunk,
            setmetatable({}, {
                __index = function(_, k)
                    local v = _G[k]
                    if v == nil then
                        return any
                    end
                    return v
                end,
            })
        )
        chunk("Hekili", ns)
        costMods(ns.raceMods.costMods, path)
    end
    for line in io.lines("src/Hekili/Hekili.toc") do
        local path = line:gsub("\r", ""):match("^(Forever\\%w+\\%w+%.lua)")
        if path and not path:match("^Forever\\Classes\\") then
            path = path:gsub("\\", "/")
            run(path, read("src/Hekili/" .. path):match('NewRace%("(%w+)"%)'))
        end
    end
    _G.Hekili = saved or nil
    return { keys = keys, ids = ids }
end

-- The form and stance words content names (`cat` of cat_form, `battle` of battle_stance), class names first.
local function nameWords(keys)
    local words = {}
    for _, w in ipairs(CLASS_WORDS) do
        words[w] = "a class name"
    end
    for k, where in pairs(keys) do
        local base = k:match("^(.+)_form$") or k:match("^(.+)_stance$")
        if base then
            words[base] = "form/stance " .. k .. " (" .. where .. ")"
        end
    end
    return words
end

-- Whether identifier `name` contains `word` as snake_case or CamelCase parts (`DRUID_SPEC`, `isCat`, `dire_bear`).
local function hasWord(name, word)
    local snake = ("_" .. name:gsub("(%l)(%u)", "%1_%2"):lower() .. "_")
    return snake:find("_" .. word .. "_", 1, true) ~= nil
end

local function coreFiles()
    local p = assert(io.popen("find " .. table.concat(CORE, " ") .. " -type f -name '*.lua' | sort"))
    local list = {}
    for path in p:lines() do
        list[#list + 1] = path
    end
    p:close()
    return list
end

-- One "<file>:<line>: <token> (<why>)" per content name or ID core code uses.
local function leaks(path, src, c, words)
    local found = {}
    for _, t in ipairs(tokens(src)) do
        local kind, text, line = t[1], t[2], t[3]
        local why
        if kind == "number" then
            local v = tonumber(text)
            why = v and c.ids[v] and not ALLOW_IDS[v] and ("spell ID of " .. c.ids[v])
        elseif kind == "name" or text:match("^[%a_][%w_]*$") then
            local lower = text:lower()
            if c.keys[lower] and not ALLOW_KEYS[lower] then
                why = "key of " .. c.keys[lower]
            else
                for w, reason in pairs(words) do
                    if hasWord(text, w) then
                        why = reason
                        break
                    end
                end
            end
        end
        if why then
            found[#found + 1] = ("%s:%d: %s (%s)"):format(path, line, text, why)
        end
    end
    return found
end

describe("core/content boundary", function()
    local c = content()
    local words = nameWords(c.keys)

    it("extracts the content's keys and IDs from every Forever file kind", function()
        local n, m = 0, 0
        for _ in pairs(c.keys) do
            n = n + 1
        end
        for _ in pairs(c.ids) do
            m = m + 1
        end
        assert.is_true(n > 150, n)
        assert.is_true(m > 400, m)
        assert.are.equal("Forever/Races/Orc.lua", c.keys.blood_fury)
        assert.is_not_nil(c.keys.bloodlust) -- Shared/Auras.lua
        assert.is_not_nil(words.cat and words.battle)
    end)

    it("tokenizes code only, and matches words as snake_case or CamelCase parts", function()
        local t = tokens('-- rend\n--[==[ rend ]==] local x = "a rend" .. [[rend]] .. "rend" + 0x1F + 1.5e3')
        local got = {}
        for _, k in ipairs(t) do
            got[#got + 1] = k[1] .. ":" .. k[2]
        end
        assert.are.same(
            { "name:local", "name:x", "string:a rend", "string:rend", "string:rend", "number:0x1F", "number:1.5e3" },
            got
        )
        assert.are.equal(2, t[#t][3])
        assert.is_true(hasWord("DRUID_SPEC", "druid") and hasWord("isCatForm", "cat") and hasWord("dire_bear", "bear"))
        assert.is_false(hasWord("scatter", "cat") or hasWord("magenta", "mage"))
        local found = leaks("x.lua", 'local a = buff.rend; local b = "rend"; local c = 772; local d = "WARRIOR"', {
            keys = { rend = "R" },
            ids = { [772] = "R" },
        }, { warrior = "a class name" })
        assert.are.equal(4, #found)
    end)

    it("keeps content keys, spell IDs, class and form names out of Virtual/** and Engine/**", function()
        local found = {}
        local files = coreFiles()
        assert.is_true(#files > 30)
        for _, path in ipairs(files) do
            for _, hit in ipairs(leaks(path, read(path), c, words)) do
                found[#found + 1] = hit
            end
        end
        assert.are.same({}, found)
    end)
end)
