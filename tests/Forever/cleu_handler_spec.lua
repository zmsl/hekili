-- tests/Forever/cleu_handler_spec.lua (perf plan 1.4): what the legacy combat-log handler does with each kind of row
-- (the identity table, written and passed before the handler changed), and how often a row asks the client.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

-- Client reads a row can cost: "name" or "name:unit".
local asks = {}
local fakeNew = fake.new
fake.new = function(...)
    local api, ctl = fakeNew(...)
    for _, name in ipairs({ "UnitExists", "UnitGUID", "IsInGroup" }) do
        local real = api[name]
        api[name] = function(unit, ...)
            local key = unit and (name .. ":" .. tostring(unit)) or name
            asks[key] = (asks[key] or 0) + 1
            return real(unit, ...)
        end
    end
    return api, ctl
end

local PET, FOE, STRANGER = "Pet-1", "Creature-1", "Creature-9"
local FRIEND_FLAGS = 0x10 -- COMBATLOG_OBJECT_REACTION_FRIENDLY
local HITS = { "updateTarget", "trackDebuff", "storeDamage", "updateMinion", "eliminateUnit" }

local function boot()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    H.Hekili.UpdateDamageDetectionForCLEU(H.Hekili)
    H.I, H.L = H.ns.VirtualStateInternal, H.ns.VirtualStateInternal.Log
    H.log = {}
    for _, name in ipairs(HITS) do
        local real = H.ns[name]
        H.ns[name] = function(a, ...)
            H.log[#H.log + 1] = name .. ":" .. tostring(a)
            return real(a, ...)
        end
    end
    return H
end

-- One row through the real log, as Game/Events/CombatLog.lua delivers it to the handler.
local function row(H, sub, src, dst, spell, dstFlags)
    local L = H.L
    local r = L.Emit(sub, 16, H.ctl.now, false, "damage", "observed", src, 0, dst, dstFlags or L.HOSTILE_FLAGS)
    r[12], r[13], r[14], r[15], r[16] = spell or 1, "", 1, 100, -1
    L.Deliver()
    local got = table.concat(H.log, " ")
    H.log = {}
    return got
end

local function fight(H, on)
    H.ctl.combat = on
    H.ctl.now = H.ctl.now + 1
end

describe("the combat-log handler", function()
    it("does the same with each kind of row (identity table)", function()
        local H = boot()
        local me, st = H.ctl.guid.player, H.Hekili.State
        H.ctl.guid.pet, H.ctl.exists.pet = PET, true

        fight(H, true)
        assert.are.equal("updateTarget:" .. FOE, row(H, "SPELL_DAMAGE", me, FOE))
        assert.are.equal("updateTarget:" .. FOE, row(H, "SPELL_DAMAGE", PET, FOE))
        assert.are.equal("", row(H, "SPELL_DAMAGE", STRANGER, FOE)) -- another's row: filtered
        assert.are.equal("", row(H, "SPELL_DAMAGE", me, "Player-2", 1, FRIEND_FLAGS)) -- not hostile
        assert.are.equal("storeDamage:" .. H.ctl.now, row(H, "SPELL_DAMAGE", STRANGER, me))

        fight(H, false)
        assert.are.equal("updateTarget:" .. FOE, row(H, "SPELL_DAMAGE", me, FOE))
        assert.are.equal("updateTarget:" .. FOE, row(H, "SPELL_DAMAGE", PET, FOE))
        assert.are.equal("storeDamage:" .. H.ctl.now, row(H, "SPELL_DAMAGE", STRANGER, me))
        assert.are.equal("", row(H, "SPELL_DAMAGE", STRANGER, FOE))

        -- no pet: its old GUID is a stranger's
        H.ctl.guid.pet, H.ctl.exists.pet = nil, nil
        fight(H, true)
        assert.are.equal("", row(H, "SPELL_DAMAGE", PET, FOE))

        -- a tank's swing from a foe names the foe
        fight(H, true)
        st.role.tank = true
        assert.are.equal("updateTarget:" .. STRANGER, row(H, "SWING_MISSED", STRANGER, me))
        st.role.tank = false

        -- a debuff of ours on a foe
        fight(H, true)
        local id
        for k, a in pairs(H.Hekili.Class.auras) do
            if type(k) == "number" and not a.friendly then
                id = k
                break
            end
        end
        assert.are.equal("trackDebuff:" .. id, row(H, "SPELL_AURA_APPLIED", me, FOE, id))

        -- a counted minion's hit
        fight(H, true)
        H.ns.updateMinion(STRANGER, H.ctl.now)
        H.log = {}
        assert.are.equal("", row(H, "SPELL_DAMAGE", STRANGER, FOE))
        H.Hekili.Engine.settings.specs[st.spec.id].damagePets = true
        H.Hekili:UpdateDamageDetectionForCLEU()
        assert.are.equal("updateTarget:" .. FOE, row(H, "SPELL_DAMAGE", STRANGER, FOE))
        assert.are.same({}, H.errors)
    end)

    it("asks the client for the pet once per moment and never for a group on another's row", function()
        local H = boot()
        H.ctl.guid.pet, H.ctl.exists.pet = PET, true
        fight(H, true)
        for k in pairs(asks) do
            asks[k] = nil
        end
        for _ = 1, 10 do
            row(H, "SPELL_DAMAGE", STRANGER, FOE)
        end
        assert.are.equal(1, asks["UnitExists:pet"])
        assert.are.equal(1, asks["UnitGUID:pet"])
        assert.is_nil(asks.IsInGroup)
        assert.are.same({}, H.errors)
    end)

    it("sees a pet come and go inside one moment, by UNIT_PET, and without it at the next moment", function()
        local H = boot()
        fight(H, true)
        assert.are.equal("", row(H, "SPELL_DAMAGE", PET, FOE))
        H.ctl.guid.pet, H.ctl.exists.pet = PET, true
        H.Fire("UNIT_PET", "player")
        assert.are.equal("updateTarget:" .. FOE, row(H, "SPELL_DAMAGE", PET, FOE))
        H.ctl.guid.pet, H.ctl.exists.pet = nil, nil
        H.Fire("UNIT_PET", "player")
        assert.are.equal("", row(H, "SPELL_DAMAGE", PET, FOE))
        -- no event at all: the belief's summon model moves UnitExists("pet") silently
        H.ctl.guid.pet, H.ctl.exists.pet = PET, true
        fight(H, true)
        assert.are.equal("updateTarget:" .. FOE, row(H, "SPELL_DAMAGE", PET, FOE))
        assert.are.same({}, H.errors)
    end)
end)
