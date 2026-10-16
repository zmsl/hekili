-- tests/Forever/helpers/load_druid.lua
-- Loads Forever/Classes/Druid.lua headless against a recording stand-in for Hekili (load_warrior.lua's shape): each
-- spec:RegisterX call is kept by method name, and the plain game reads the file captures at load answer from `game`
-- (known spells, queued spells, the shapeshift form, the time, the combat-log row, VirtualState's per-hand base weapon
-- speeds). `env()` is a stand-in `state` for running the file's handlers, state functions, expressions and hooks
-- (Hekili runs them with setfenv( f, state )).
local M = {}

--- Loads the class file. `vs` (optional) is the VirtualState the file binds as ns.VirtualState (a real one, for the
--- strict-context specs); by default a fake whose KnownRank answers from `game.known`. Returns `w`: `w.abilities`,
--- `w.auras` (merged by key), `w.talents`, `w.resources[powerType]` ({ models, meta }), `w.costMods` (the
--- RegisterCostMod declarations), `w.hooks[name]`, `w.events[event]`, `w.funcs[name]`, `w.exprs[name]`,
--- `w.settings[key]` ({ default, option }), `w.packs` (in order: { name, version, string }), `w.options`, `w.specID`,
--- `w.ns`, `w.state` (Hekili.State's stand-in) and `w.game`.
function M.load(vs)
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
        form = 0,
        formSpell = {},
        base = { 0, 0 }, -- VS.SwingBase: each hand's unhasted speed (0: no plain read yet)
        now = 0, -- GetTime()
        row = {}, -- the combat-log row CombatLogGetCurrentEventInfo answers
    }
    local w = { game = game, abilities = {}, auras = {}, resources = {}, hooks = {}, funcs = {}, exprs = {} }
    w.state = { buff = {}, swings = {} }
    local hekili = { State = w.state }
    function hekili:NewSpecialization(id)
        w.specID = id
        return spec
    end
    local fakes = {
        Hekili = hekili,
        UnitClassBase = function()
            return "DRUID"
        end,
        C_Spell = {
            IsCurrentSpell = function(id)
                return game.current[id] == true
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
        Enum = { PowerType = { Mana = 0, Rage = 1, Energy = 3, ComboPoints = 4 } },
    }
    local saved = {}
    for k, v in pairs(fakes) do
        saved[k] = rawget(_G, k) or false
        _G[k] = v
    end
    local ns = {
        Facade = fakes, -- the class file reads the game through ns.Facade (event-facade spec §1.2)
        VirtualState = vs or {
            KnownRank = function(ids) -- VirtualState's spellbook: the plain known reads (`game.known`)
                for i = #ids, 1, -1 do
                    if game.known[ids[i]] then
                        return i
                    end
                end
                return 0
            end,
            SwingBase = function(hand)
                return game.base[hand]
            end,
        },
    }
    w.ns = ns
    local ok, err = pcall(assert(loadfile("src/Hekili/Forever/Classes/Druid.lua")), "Hekili", ns)
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

--- A stand-in `state` that records applyBuff/applyDebuff (into `applied`, durations and stacks by key), removeBuff,
--- removeDebuff, removeStack, addStack, spend and gain, with every talent at rank 0, every aura down and every cooldown
--- ready, the settings at their defaults. The class file's state functions are bound to it.
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
