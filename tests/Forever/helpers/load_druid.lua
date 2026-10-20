-- tests/Forever/helpers/load_druid.lua
-- Loads Hekili_Druid/Druid.lua headless against a recording stand-in for Hekili (load_warrior.lua's shape): each
-- spec:RegisterX call is kept by method name, and the plain game reads the file captures at load answer from `game`
-- (known spells, queued spells, usability, bag counts, the shapeshift form, the time, the belief's per-hand base weapon
-- speeds). `env()` is a stand-in `state` for running the file's handlers, state functions, expressions and hooks
-- (Hekili runs them with setfenv( f, state )).
local M = {}

--- Loads the class file (`file`, default the Druid's, as class token `class`, default "DRUID": the Rogue's helpers
--- load theirs through it). `vs` (optional) is the VirtualState whose KnownRank the file's knownRank reads through
--- `state.knownRank` (a real one, for the strict-context specs); by default a fake answering from `game.known`. Returns `w`: `w.abilities`,
--- `w.auras` (merged by key), `w.talents`, `w.resources[powerType]` ({ models, meta }), `w.costMods` (the
--- RegisterCostMod declarations), `w.hooks[name]`, `w.events[event]`, `w.funcs[name]`, `w.exprs[name]`,
--- `w.settings[key]` ({ default, option, specs: nil for every spec }), `w.totems` (the RegisterTotems table), `w.pets`
--- (the RegisterPets table), `w.packs` (in order: { name, version, string }), `w.options`, `w.class` and
--- `w.def` (NewClass's token and definition),
--- `w.spec` (the recording spec object), `w.state` (Hekili.State's stand-in) and `w.game`.
function M.load(vs, file, class)
    local reg = {}
    local spec = setmetatable({}, {
        __index = function(_, method)
            return function(_, ...)
                reg[method] = reg[method] or {}
                table.insert(reg[method], { ... })
            end
        end,
    })
    local game = {
        known = {},
        current = {},
        usable = {}, -- C_Spell.IsSpellUsable: [id] = { usable, noMana }
        bags = {}, -- C_Item.GetItemCount: [itemID] = count
        form = 0,
        formSpell = {},
        base = { 0, 0 }, -- VS.SwingBase: each hand's unhasted speed (0: no plain read yet)
        now = 0, -- GetTime()
    }
    local w = { game = game, abilities = {}, auras = {}, resources = {}, hooks = {}, funcs = {}, exprs = {} }
    w.state = { buff = {}, swings = {} }
    local hekili = { State = w.state }
    w.spec = spec
    function hekili:NewClass(token, def)
        w.class, w.def = token, def
        return spec
    end
    local fakes = {
        Hekili = hekili,
        UnitClassBase = function()
            return class or "DRUID"
        end,
        C_Spell = {
            IsCurrentSpell = function(id)
                return game.current[id] == true
            end,
            IsSpellUsable = function(id)
                local u = game.usable[id] or {}
                return u[1] == true, u[2] == true
            end,
        },
        C_Item = {
            GetItemCount = function(id)
                return game.bags[id] or 0
            end,
        },
        GetShapeshiftForm = function()
            return game.form
        end,
        GetShapeshiftFormInfo = function(i)
            return 0, true, true, game.formSpell[i]
        end,
        GetTime = function()
            return game.now
        end,
        Enum = { PowerType = { Mana = 0, Rage = 1, Energy = 3, ComboPoints = 4 } },
    }
    local saved = {}
    for k, v in pairs(fakes) do
        saved[k] = rawget(_G, k) or false
        _G[k] = v
    end
    hekili.Client = fakes -- the class file reads the game through Hekili.Client (Hekili.lua)
    -- the belief's spellbook, as the file's knownRank calls it through `state` (State.lua's name)
    w.state.knownRank = vs and vs.KnownRank
        or function(ids) -- the plain known reads (`game.known`)
            for i = #ids, 1, -1 do
                if game.known[ids[i]] then
                    return i
                end
            end
            return 0
        end
    local ok, err = pcall(assert(loadfile(file or "src/Hekili_Druid/Druid.lua")))
    for k, v in pairs(saved) do
        _G[k] = v or nil
    end
    assert(ok, err)
    for _, call in ipairs(reg.RegisterAbilities or {}) do
        for k, v in pairs(call[1]) do
            w.abilities[k] = v
        end
    end
    for _, call in ipairs(reg.RegisterAuras or {}) do
        for k, v in pairs(call[1]) do
            w.auras[k] = v
        end
    end
    w.talents = reg.RegisterTalents and reg.RegisterTalents[1][1]
    w.order = {}
    for i, call in ipairs(reg.RegisterResource or {}) do
        w.order[i] = call[1]
        w.resources[call[1]] = { models = call[2], meta = call[4] }
    end
    w.costMods = {}
    for i, call in ipairs(reg.RegisterCostMod or {}) do
        w.costMods[i] = call[1]
    end
    w.events = {}
    for _, call in ipairs(reg.RegisterEvent or {}) do
        w.events[call[1]] = call[2]
    end
    for _, call in ipairs(reg.RegisterHook or {}) do
        w.hooks[call[1]] = call[2]
    end
    for _, call in ipairs(reg.RegisterStateFunction or {}) do
        w.funcs[call[1]] = call[2]
    end
    for _, call in ipairs(reg.RegisterStateExpr or {}) do
        w.exprs[call[1]] = call[2]
    end
    w.settings = {}
    for _, call in ipairs(reg.RegisterSetting or {}) do
        w.settings[call[1]] = { default = call[2], option = call[3], specs = call[4] and { unpack(call, 4) } or nil }
    end
    w.totems = reg.RegisterTotems and reg.RegisterTotems[1][1]
    w.pets = reg.RegisterPets and reg.RegisterPets[1][1]
    w.packs = reg.RegisterPack or {}
    w.options = reg.RegisterOptions and reg.RegisterOptions[1][1]
    return w
end

local function default(value)
    return setmetatable({}, {
        __index = function()
            return value
        end,
    })
end

--- A stand-in `state` that records applyBuff/applyDebuff (into `applied`, durations and stacks by key), removeBuff,
--- removeDebuff, removeStack, addStack, setCooldown (into `cooldowns`), spend and gain, with every talent at rank 0,
--- every aura down and every cooldown ready, the settings at their defaults. The class file's state functions are bound
--- to it.
function M.env(w)
    local e = { applied = {}, durations = {}, stacks = {}, removed = {}, spent = {}, gained = {}, added = {} }
    e.talent = default({ rank = 0, enabled = false })
    e.buff = default({ up = false, remains = 0, stack = 0, applied = 0 })
    e.debuff = e.buff
    e.cooldown = default({ remains = 0 })
    e.action = default({ cost = 0 })
    e.settings = {}
    for k, s in pairs(w.settings) do
        e.settings[k] = s.default
    end
    e.energy = { current = 100, max = 100, regen = 10 }
    e.rage = { current = 50 }
    e.mana = { current = 1000 }
    e.combo_points = { current = 0 }
    e.combat, e.active_enemies, e.group = 0, 1, false
    e.pairs, e.ipairs = pairs, ipairs -- Hekili's state has them (State.lua)
    function e.applyBuff(key, duration)
        table.insert(e.applied, key)
        e.durations[key] = duration
    end
    function e.applyDebuff(_, key, duration, stacks)
        table.insert(e.applied, key)
        e.durations[key], e.stacks[key] = duration, stacks
    end
    function e.removeBuff(key)
        table.insert(e.removed, key)
    end
    e.removeStack = e.removeBuff
    function e.removeDebuff(_, key)
        table.insert(e.removed, key)
    end
    function e.addStack(key, _, n)
        table.insert(e.added, { key, n })
    end
    e.cooldowns = {}
    function e.setCooldown(key, t)
        table.insert(e.cooldowns, { key, t })
    end
    function e.spend(n, resource)
        table.insert(e.spent, { n, resource })
    end
    function e.gain(n, resource)
        table.insert(e.gained, { n, resource })
    end
    for k, f in pairs(w.funcs) do
        e[k] = setfenv(f, e)
    end
    return e
end

--- Runs `f` (a field function of the class file) in `e`; a non-function is returned as is.
function M.run(f, e, ...)
    if type(f) ~= "function" then
        return f
    end
    return setfenv(f, e)(...)
end

return M
