-- Forever/spec/helpers/load_warrior.lua
-- Loads Forever/Warrior.lua headless against a recording stand-in for Hekili: every spec:RegisterX call is kept by
-- method name, ns.VirtualState.Track's tables are merged, and the plain game reads the file captures at load answer
-- from `game` (known spells, queued spells, usability, the shapeshift form, the level, VirtualState's cached weapon
-- damage). `env()` is a stand-in `state` for running
-- the file's handlers, state functions and hooks (Hekili runs them with setfenv( f, state )).
local M = {}

--- Loads the class file. Returns `w`: `w.abilities`, `w.auras` (merged by key), `w.talents`, `w.track`, `w.resource`
--- ({ powerType, models }), `w.hooks[name]`, `w.funcs[name]`, `w.exprs[name]`, `w.settings[key]` ({ default,
--- option }), `w.packs` (in order: { name, version, string }), `w.options`, `w.specID`, `w.state` (Hekili.State's
--- stand-in) and `w.game`.
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
        damage = { 0, 0, 0, 0 }, -- UnitDamage's first four returns in VirtualState's stat cache
        level = 22,
        SECRET = newproxy(), -- a secret value: issecretvalue says so, and arithmetic or comparison on it raises
    }
    local w = { game = game, abilities = {}, auras = {}, track = {}, hooks = {}, funcs = {}, exprs = {} }
    w.state = { main_hand = { size = 2 }, timeToInterrupt = function() end }
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
        UnitLevel = function()
            return game.level
        end,
        issecretvalue = function(v)
            return v == game.SECRET
        end,
        Enum = { PowerType = { Rage = 1 } },
    }
    local saved = {}
    for k, v in pairs(fakes) do
        saved[k] = rawget(_G, k) or false
        _G[k] = v
    end
    local ns = {
        VirtualState = {
            Track = function(t)
                for k, v in pairs(t.talents or {}) do
                    w.track[k] = v
                end
            end,
            Stat = function(name)
                if name ~= "UnitDamage" then
                    return 0, 0, 0, 0, 0, 0, 0
                end
                local d = game.damage
                return d[1], d[2], d[3], d[4], 0, 0, 1
            end,
        },
    }
    local ok, err = pcall(assert(loadfile("Forever/Warrior.lua")), "Hekili", ns)
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
    w.resource = reg.RegisterResource and reg.RegisterResource[1]
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

--- A stand-in `state` that records applyBuff/applyDebuff (into `applied`), removeBuff, spend and gain, with every
--- talent at rank 0, every aura down and every cooldown ready. The class file's state functions are bound to it.
function M.env(w)
    local e = { applied = {}, removed = {}, spent = {}, gained = {} }
    e.talent = default({ rank = 0, enabled = false })
    e.buff = default({ up = false, remains = 0, stack = 0 })
    e.debuff = e.buff
    e.cooldown = default({ remains = 0 })
    e.active_dot = default(0)
    e.rage = { current = 50 }
    e.target = { minR = 10, is_boss = false }
    e.combat, e.active_enemies = 0, 1
    function e.applyBuff(key)
        table.insert(e.applied, key)
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
