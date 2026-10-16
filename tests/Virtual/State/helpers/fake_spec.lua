-- tests/Virtual/State/helpers/fake_spec.lua
-- A tiny fake spec provider for headless specs: a fake `state` (offset, delay, now, the resources' `actual`,
-- `cooldown`, `buff`, `debuff`, setCooldown, spendCharges, RunHandler, HandleEvent, the queue calls) and a fake
-- `class` whose abilities' `spend` and `handler` act on that fake state, plus a fake `ns.spendResources`. It drives
-- the tracked-set build and Drain's read-before / read-after diff (spec §5) without Hekili.
local M = {}

M.RAGE = 1 -- Enum.PowerType.Rage
M.REND, M.REND_R2, M.STRIKE, M.SHOUT = 772, 6546, 78, 6673

--- A fake Hekili: { State, Class, ForceUpdate, forced }, and `spendResources` for ns. `swingValue` is rage per swing.
function M.new(swingValue)
    local state = {
        offset = 0,
        delay = 0,
        now = 0,
        combat = 0,
        resets = 0,
        history = {},
        queue = {},
        removed = {},
        swings = { mh_actual = 0, oh_actual = 0 },
        player = { updated = false },
        target = { updated = false },
        gcd = { execute = 1.5 },
        rage = { actual = 0, fcount = 3 },
        buff = {},
        debuff = {},
    }
    state.cooldown = { global_cooldown = { expires = 0, duration = 0, remains = 0 } }
    local function qt()
        return state.now + state.offset + state.delay
    end
    function state.reset()
        state.resets = state.resets + 1
        state.now = M.clock and M.clock() or state.now
        state.rage.actual = 0
    end
    function state.setCooldown(key, d)
        local cd = state.cooldown[key] or {}
        cd.duration, cd.expires = d, qt() + d
        if key == "global_cooldown" then
            cd.remains = d
        end
        state.cooldown[key] = cd
    end
    function state.spendCharges(key, n)
        state.setCooldown(key, 10)
    end
    function state.applyDebuff(key, d)
        local a = state.debuff[key] or {}
        a.applied, a.expires, a.count = qt(), qt() + d, 1
        state.debuff[key] = a
    end
    function state.applyBuff(key, d)
        local a = state.buff[key] or {}
        a.applied, a.expires, a.count = qt(), qt() + d, 1
        state.buff[key] = a
    end
    local class = {
        primaryResource = "rage",
        resources = {
            rage = {
                type = M.RAGE,
                state = { regenModel = { mainhand = { swing = "mainhand", value = swingValue or 9 } } },
            },
        },
        abilities = {},
        auras = {},
        talents = { improved_rend = { 0, 12286, 3 } },
    }
    local function ability(key, t)
        t.key, t.funcs = key, { now = t.now } -- Hekili keeps an unknown function field in `funcs`
        t.now = nil
        t.cast, t.cooldown, t.charges, t.recharge = t.cast or 0, t.cooldown or 0, t.charges or 1, t.recharge or 0
        class.abilities[key] = t
        class.abilities[t.id] = t
    end
    ability("rend", {
        id = M.REND,
        copy = { M.REND_R2 },
        spend = 10,
        spendType = "rage",
        startsCombat = true,
        handler = function()
            state.applyDebuff("rend", 15)
        end,
        now = function()
            applyDebuff("target", "rend", 15) -- the `now` context's verb (Families/Now.lua)
        end,
    })
    ability("heroic_strike", { id = M.STRIKE, spend = 15, spendType = "rage", gcd = "off", onNextSwing = true })
    ability("battle_shout", {
        id = M.SHOUT,
        spend = 10,
        spendType = "rage",
        handler = function()
            state.applyBuff("battle_shout", 120)
        end,
        now = function()
            applyBuff("battle_shout")
        end,
    })
    class.auras.rend = { key = "rend", id = M.REND, copy = { M.REND_R2 }, duration = 15 }
    class.auras.battle_shout = { key = "battle_shout", id = M.SHOUT, duration = 120 }
    function state:RunHandler(key)
        local a = class.abilities[key]
        if a.handler then
            a.handler()
        end
    end
    function state:HandleEvent(e)
        self.handled = e.action
        local a = class.abilities[e.action]
        state.setCooldown(e.action, a.cooldown)
        M.spend(e.action)
        self:RunHandler(e.action)
    end
    function state:RemoveSpellEvent(key, real, eType)
        table.insert(self.removed, key .. ":" .. tostring(eType))
        return true
    end
    function state:RemoveSpellEvents(key)
        table.insert(self.removed, key .. ":all")
    end
    function state:QueueEvent(key, start, finish, eType)
        table.insert(self.queue, key .. ":" .. eType)
    end
    function state:AddToHistory(key, guid)
        table.insert(self.history, key)
    end
    function M.spend(key)
        local a = class.abilities[key]
        if type(a.spend) == "number" then
            state.rage.actual = math.max(0, state.rage.actual - a.spend)
        end
    end
    local hekili = { State = state, Class = class, forced = {} }
    function hekili:ForceUpdate(event)
        self.forced[#self.forced + 1] = event
    end
    return hekili
end

--- The tracked-set definition Adapter.lua would build from M.new()'s class (for family specs without the Adapter).
function M.def(hekili)
    local class = hekili.Class
    local rage = class.resources.rage
    local mh = rage.state.regenModel.mainhand
    return {
        abilities = { class.abilities.battle_shout, class.abilities.heroic_strike, class.abilities.rend },
        abilityIds = { { M.SHOUT }, { M.STRIKE }, { M.REND, M.REND_R2 } },
        abilitySlot = { 1, 1, 1 },
        resources = { { key = "rage", type = M.RAGE, token = "RAGE", max = 100, rest = false, swing = 1, swingValue = mh.value } },
        auras = { class.auras.battle_shout, class.auras.rend },
        auraIds = { { M.SHOUT }, { M.REND, M.REND_R2 } },
        talents = { { key = "improved_rend", spell = 12286, max = 3 } },
        units = { "player", "target" },
    }
end

--- One drain without Hekili: the polls, the fold, the settle (Adapter's Drain minus the apply).
function M.fold(ns, t)
    local I = ns.VirtualStateInternal
    I.Sources.RunPolls(t)
    I.Fold(t)
    I.Settle(t)
end

return M
