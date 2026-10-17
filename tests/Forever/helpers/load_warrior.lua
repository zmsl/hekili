-- tests/Forever/helpers/load_warrior.lua
-- Loads Forever/Classes/Warrior.lua headless against a recording stand-in for Hekili: each spec:RegisterX call is
-- kept by method name, and the plain game reads the file captures at load answer from `game` (known spells, queued
-- spells, usability, the shapeshift form, the belief's per-hand base weapon speeds). `env()` is a stand-in `state` for running
-- the file's handlers, state functions and hooks (Hekili runs them with setfenv( f, state )).
local M = {}

--- Loads the class file. Returns `w`: `w.abilities`, `w.auras` (merged by key), `w.talents`, `w.resource`
--- ({ powerType, models }), `w.hooks[name]`, `w.events[event]` (spec:RegisterEvent's handlers), `w.funcs[name]`,
--- `w.exprs[name]`, `w.settings[key]` ({ default, option }), `w.packs` (in order: { name, version, string }),
--- `w.options`, `w.specID`, `w.state` (Hekili.State's stand-in, its knownRank, swingBase, stat and healthMax answering
--- from `game`) and `w.game`. `w.passives`: spec:RegisterAbility's single registrations (the passives).
function M.load()
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
        usable = {},
        noMana = {},
        form = 0,
        formSpell = {},
        base = { 0, 0 }, -- VS.SwingBase: each hand's unhasted speed (0: no plain read yet)
        stat = {}, -- VS.Stat: [api name] = its cached returns (default zeros)
        healthMax = 100, -- VS.HealthMax("player")
        now = 0, -- GetTime()
        row = {}, -- the combat-log row CombatLogGetCurrentEventInfo answers
    }
    local w = { game = game, abilities = {}, auras = {}, hooks = {}, funcs = {}, exprs = {} }
    w.state = { main_hand = { size = 2 }, equipped = {}, timeToInterrupt = function() end }
    local hekili = { State = w.state }
    function hekili:NewSpecialization(id)
        w.specID = id
        return spec
    end
    local fakes = {
        Hekili = hekili,
        UnitClassBase = function()
            return "WARRIOR"
        end,
        C_SpellBook = {
            IsSpellKnown = function(id)
                return game.known[id] == true
            end,
        },
        C_Spell = {
            IsCurrentSpell = function(id)
                return game.current[id] == true
            end,
            IsSpellUsable = function(id)
                return game.usable[id] == true, game.noMana[id] == true
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
        CombatLogGetCurrentEventInfo = function()
            return unpack(game.row, 1, 15)
        end,
        Enum = { PowerType = { Rage = 1 } },
    }
    local saved = {}
    for k, v in pairs(fakes) do
        saved[k] = rawget(_G, k) or false
        _G[k] = v
    end
    hekili.Client = fakes -- the class file reads the game through Hekili.Client (Hekili.lua)
    -- the belief's reads, as the file's helpers call them through `state` (State.lua's names)
    function w.state.knownRank(ids) -- the belief's spellbook: the plain known reads (`game.known`)
        for i = #ids, 1, -1 do
            if game.known[ids[i]] then
                return i
            end
        end
        return 0
    end
    function w.state.swingBase(hand)
        return game.base[hand]
    end
    function w.state.stat(name)
        local v = game.stat[name] or {}
        return v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0
    end
    function w.state.healthMax()
        return game.healthMax
    end
    local ok, err = pcall(assert(loadfile("src/Hekili/Forever/Classes/Warrior.lua")))
    for k, v in pairs(saved) do
        _G[k] = v or nil
    end
    assert(ok, err)
    for _, call in ipairs(reg.RegisterAbilities or {}) do
        for k, v in pairs(call[1]) do
            w.abilities[k] = v
        end
    end
    w.passives = {}
    for _, call in ipairs(reg.RegisterAbility or {}) do
        w.passives[call[1]] = call[2]
    end
    for _, call in ipairs(reg.RegisterAuras or {}) do
        for k, v in pairs(call[1]) do
            w.auras[k] = v
        end
    end
    w.talents = reg.RegisterTalents and reg.RegisterTalents[1][1]
    w.resource = reg.RegisterResource and reg.RegisterResource[1]
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
        w.settings[call[1]] = { default = call[2], option = call[3] }
    end
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

--- A stand-in `state` that records applyBuff/applyDebuff (into `applied`; applyBuff's stacks into `stacks`), removeBuff, spend and gain, with every
--- talent at rank 0, every aura down and every cooldown ready. The class file's state functions are bound to it.
function M.env(w)
    local e = { applied = {}, durations = {}, stacks = {}, removed = {}, spent = {}, gained = {} }
    e.talent = default({ rank = 0, enabled = false })
    e.buff = default({ up = false, remains = 0, stack = 0 })
    e.debuff = e.buff
    e.cooldown = default({ remains = 0 })
    e.active_dot = default(0)
    e.rage = { current = 50 }
    e.target = { minR = 10, is_boss = false }
    e.combat, e.active_enemies = 0, 1
    function e.applyBuff(key, duration, stacks)
        table.insert(e.applied, key)
        e.durations[key], e.stacks[key] = duration, stacks
    end
    function e.applyDebuff(_, key)
        table.insert(e.applied, key)
    end
    function e.removeBuff(key)
        table.insert(e.removed, key)
    end
    function e.spend(n)
        table.insert(e.spent, n)
    end
    function e.gain(n)
        table.insert(e.gained, n)
    end
    function e.setDistance() end
    function e.interrupt() end
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
