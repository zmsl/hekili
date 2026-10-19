-- tests/boundary_lib.lua
-- The boundary scanner (moved out of tests/boundary_spec.lua, which describes it): the content's keys and IDs, a
-- Lua tokenizer and the leak checks, shared by the spec and tools/boundary_baseline.lua. No `_spec` suffix: busted
-- does not run it.
local addons = require("helpers.addons")
local loaders = {
    Warrior = require("Forever.helpers.load_warrior"),
    Druid = require("Forever.helpers.load_druid"),
    Rogue = { -- the Rogue's class file through the Druid's recording loader
        load = function()
            return require("Forever.helpers.load_druid").load(nil, "src/Hekili_Rogue/Rogue.lua", "ROGUE")
        end,
    },
}

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
    potion = "the shared potion ability; stock Engine/Schema/Spec.lua's RegisterPotion names its argument so",
}
-- Identifiers core may use whole although a part matches content, each with its reason.
local ALLOW_NAMES = {
    GetShieldBlock = "a WoW API name (the client's block value), not the shield_block key",
    -- WoW API names in the Facade's read table, matched by their CamelCase parts (loss_of_control, battle)
    C_LossOfControl = "a WoW API name",
    GetActiveLossOfControlData = "a WoW API name",
    GetActiveLossOfControlDataCount = "a WoW API name",
    GetSpellLossOfControlCooldown = "a WoW API name",
    IsInBattle = "a WoW API name",
    -- WoW globals the headless shell stubs (tests/Game/harness/headless.lua), matched by their parts
    C_BattleNet = "a WoW API name",
    SPELL_FAILED_NOT_IN_MAGE_TOWER = "a WoW GlobalStrings name",
    TOOLTIP_NOT_IN_MAGE_TOWER = "a WoW GlobalStrings name",
    BATTLE_PET_NAME_4 = "a WoW GlobalStrings name",
}
local ALLOW_IDS = {
    [29515] = "the client's GCD spell (Constants), not content",
    [100] = "the percent scale and default maximum core uses; it collides with Charge rank 1's ID",
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

    -- the class packs' files, through their recording loaders (tests/Forever/helpers)
    for _, addon in ipairs(addons.CONTENT) do
        local name = addon ~= "Hekili_Shared" and addon:match("^Hekili_(%w+)$") -- a class pack, not the shared addon
        if name then
            local loader = assert(loaders[name], "no recording loader for " .. addon)
            local w = loader.load()
            local where = addon .. "/" .. name .. ".lua"
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
    end

    -- the race and shared files, through Engine/Schema/Races.lua and Engine/Schema/Shared.lua against a recording `all`
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
        function all:RegisterStateExpr(k)
            def(k, nil, path)
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
        local ns = { Facade = any }
        _G.Hekili.Client = any
        assert(loadfile("src/Hekili/Engine/Schema/Races.lua"))("Hekili", ns)
        assert(loadfile("src/Hekili/Engine/Schema/Shared.lua"))("Hekili", ns)
        -- a global the file reads at load (INVTYPE_*) answers `any`; Hekili and the Lua library stay real
        local chunk = assert(loadfile("src/" .. path))
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
    for _, file in ipairs(addons.lua({ "Hekili_Shared" })) do -- the race and shared files
        local path = file:gsub("^src/", "")
        run(path, read(file):match('NewRace%("(%w+)"%)'))
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

-- `name` as "_part_part_" (snake_case and CamelCase split, lowercased): `DRUID_SPEC`, `isCat`, `dire_bear`.
local function snake(name)
    return ("_" .. name:gsub("(%l)(%u)", "%1_%2"):lower() .. "_")
end

-- Whether identifier `name` contains `word` (one or more parts) as snake_case or CamelCase parts.
local function hasWord(name, word)
    return snake(name):find("_" .. word .. "_", 1, true) ~= nil
end

local function coreFiles(dirs, skips)
    local p = assert(io.popen("find " .. table.concat(dirs, " ") .. " -type f -name '*.lua' | sort"))
    local list = {}
    for path in p:lines() do
        local skip = false
        for _, pat in ipairs(skips) do
            skip = skip or path:match(pat) ~= nil
        end
        if not skip then
            list[#list + 1] = path
        end
    end
    p:close()
    return list
end

-- Why identifier-like `text` names content, or nil: a key (whole, or a multi-part key as parts: `HEROIC_STRIKE_COST`),
-- or a class or form/stance word as parts.
local function nameLeak(text, c, words)
    if ALLOW_NAMES[text] then
        return nil
    end
    local lower = text:lower()
    if c.keys[lower] and not ALLOW_KEYS[lower] then
        return "key of " .. c.keys[lower]
    end
    local parts = snake(text)
    for k, where in pairs(c.keys) do
        if k:find("_", 1, true) and not ALLOW_KEYS[k] and parts:find("_" .. k .. "_", 1, true) then
            return "key " .. k .. " of " .. where
        end
    end
    for w, reason in pairs(words) do
        if parts:find("_" .. w .. "_", 1, true) then
            return reason
        end
    end
end

local function idLeak(text, c)
    local v = tonumber(text)
    return v and c.ids[v] and not ALLOW_IDS[v] and ("spell ID of " .. c.ids[v]) or nil
end

-- One "<file>:<line>: <token> (<why>)" per content name or ID core code uses. A string with no whitespace is code-like
-- (`"buff.rend.up"`, `"772"`, `"WARRIOR,DRUID"`): each word in it is checked; one with spaces is a message.
local function leaks(path, src, c, words)
    local found = {}
    local function hit(text, line, why)
        if why then
            found[#found + 1] = ("%s:%d: %s (%s)"):format(path, line, text, why)
        end
    end
    for _, t in ipairs(tokens(src)) do
        local kind, text, line = t[1], t[2], t[3]
        if kind == "number" then
            hit(text, line, idLeak(text, c))
        elseif kind == "name" then
            hit(text, line, nameLeak(text, c, words))
        elseif not text:find("%s") then
            for word in text:gmatch("[%w_]+") do
                if word:match("^%d+$") then
                    hit(word, line, idLeak(word, c))
                else
                    hit(word, line, nameLeak(word, c, words))
                end
            end
        end
    end
    return found
end

-- How many times `path` names each content name or ID: { [token] = n }, from leaks' "<file>:<line>: <token> (<why>)".
local function counts(path, c, words)
    local n = {}
    for _, hit in ipairs(leaks(path, read(path), c, words)) do
        local token = hit:match("^.-:%d+: (%S+) %(")
        n[token] = (n[token] or 0) + 1
    end
    return n
end

return {
    ALLOW_KEYS = ALLOW_KEYS,
    ALLOW_NAMES = ALLOW_NAMES,
    ALLOW_IDS = ALLOW_IDS,
    CLASS_WORDS = CLASS_WORDS,
    read = read,
    tokens = tokens,
    content = content,
    nameWords = nameWords,
    snake = snake,
    hasWord = hasWord,
    coreFiles = coreFiles,
    nameLeak = nameLeak,
    idLeak = idLeak,
    leaks = leaks,
    counts = counts,
}
