-- tests/Virtual/State/helpers/fake_spec.lua
-- A tiny fake spec provider for headless specs: a fake `state` (offset, delay, now, the resources' `actual`,
-- `cooldown`, `buff`, `debuff`, setCooldown, spendCharges, RunHandler, HandleEvent, the queue calls) and a fake
-- `class` whose abilities' `spend` and `handler` act on that fake state, plus a fake `ns.spendResources`. It drives
-- the tracked-set build and Drain's read-before / read-after diff (spec §5) without Hekili.
local M = {}

M.RAGE = 1 -- Enum.PowerType.Rage
-- Neutral fixtures, no class's facts: spender_a puts a 120 s buff on us, spender_b waits for the next swing (off the
-- GCD), spender_c puts a 15 s debuff on the target and has a rank 2. The keys sort in that order, as the slots do.
-- With `kinds` (M.new's second argument) two free casts on Hekili's other GCD kinds follow: spender_t on the fixed
-- 1.0 s one ("totem"), spender_u on a declared `gcdTime` of 0.8 s.
M.SPENDER_A, M.SPENDER_B, M.SPENDER_C, M.SPENDER_C_R2 = 1001, 1002, 1003, 1004
M.SPENDER_T, M.SPENDER_U = 1005, 1006

--- A fake Hekili: { State, Class, ForceUpdate, forced }, and `spendResources` for ns. `swingValue` is rage per swing;
--- `kinds` adds spender_t and spender_u.
function M.new(swingValue, kinds)
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
        talents = { talent_a = { 0, 1011, 3 } },
    }
    local function ability(key, t)
        t.key, t.funcs = key, { now = t.now } -- Hekili keeps an unknown function field in `funcs`
        t.now = nil
        t.cast, t.cooldown, t.charges, t.recharge = t.cast or 0, t.cooldown or 0, t.charges or 1, t.recharge or 0
        class.abilities[key] = t
        class.abilities[t.id] = t
    end
    ability("spender_c", {
        id = M.SPENDER_C,
        copy = { M.SPENDER_C_R2 },
        spend = 10,
        spendType = "rage",
        startsCombat = true,
        handler = function()
            state.applyDebuff("spender_c", 15)
        end,
        now = function()
            applyDebuff("target", "spender_c", 15) -- the `now` context's verb (Families/Now.lua)
        end,
    })
    ability("spender_b", { id = M.SPENDER_B, spend = 15, spendType = "rage", gcd = "off", onNextSwing = true })
    ability("spender_a", {
        id = M.SPENDER_A,
        spend = 10,
        spendType = "rage",
        handler = function()
            state.applyBuff("spender_a", 120)
        end,
        now = function()
            applyBuff("spender_a")
        end,
    })
    if kinds then
        ability("spender_t", { id = M.SPENDER_T, gcd = "totem" })
        ability("spender_u", { id = M.SPENDER_U, gcdTime = 0.8 })
    end
    class.auras.spender_c = { key = "spender_c", id = M.SPENDER_C, copy = { M.SPENDER_C_R2 }, duration = 15 }
    class.auras.spender_a = { key = "spender_a", id = M.SPENDER_A, duration = 120 }
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
    local def = {
        abilities = { class.abilities.spender_a, class.abilities.spender_b, class.abilities.spender_c },
        abilityIds = { { M.SPENDER_A }, { M.SPENDER_B }, { M.SPENDER_C, M.SPENDER_C_R2 } },
        abilitySlot = { 1, 1, 1 },
        resources = {
            { key = "rage", type = M.RAGE, token = "RAGE", max = 100, rest = false, swing = 1, swingValue = mh.value },
        },
        auras = { class.auras.spender_a, class.auras.spender_c },
        auraIds = { { M.SPENDER_A }, { M.SPENDER_C, M.SPENDER_C_R2 } },
        talents = { { key = "talent_a", spell = 1011, max = 3 } },
        units = { "player", "target" },
    }
    for _, k in ipairs({ "spender_t", "spender_u" }) do
        local a = class.abilities[k]
        if a then
            def.abilities[#def.abilities + 1], def.abilityIds[#def.abilityIds + 1] = a, { a.id }
            def.abilitySlot[#def.abilitySlot + 1] = 0
        end
    end
    return def
end

--- One drain without Hekili: the polls, the fold, the settle (Adapter's Drain minus the apply).
function M.fold(ns, t)
    local I = ns.VirtualStateInternal
    I.Sources.RunPolls(t)
    I.Fold(t)
    I.Settle(t)
end

return M
