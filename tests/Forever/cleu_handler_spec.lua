-- tests/Forever/cleu_handler_spec.lua (perf plan 1.4): what the legacy combat-log handler does with each kind of row
-- (the identity table, written and passed before the handler changed), and how often a row asks the client.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local rw = require("Forever.helpers.rogue_world")
local fake = require("Game.State.helpers.fake_api")
local alloc = require("Game.State.helpers.alloc")

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

local function boot(content)
    content = content or ww
    local H = headless.new({ character = content.character(), pack = content.PACK })
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

    -- Game/Events/Attackers.lua's rows for a hit on us with no known attacker: the source "", the none flags.
    describe("a row on us with no source", function()
        local NOBODY = ""
        local H, me, st

        before_each(function()
            H = boot()
            me, st = H.ctl.guid.player, H.Hekili.State
            fight(H, true)
        end)

        local function flush()
            H.L.Deliver()
            local got = table.concat(H.log, " ")
            H.log = {}
            return got
        end

        -- The rows by subevent, each with `amount` and, a spell's, `spell`.
        local function rows(amount, spell)
            local L, t, none, mine = H.L, H.ctl.now, H.L.NONE_FLAGS, H.L.PLAYER_FLAGS
            return {
                SWING_DAMAGE = function()
                    L.Swing(t, "onus", NOBODY, none, me, mine, amount, "BLOCK_REDUCED", false)
                end,
                SWING_MISSED = function()
                    L.Miss(t, "onus", NOBODY, none, me, mine, nil, 1, "DODGE", false)
                end,
                SPELL_DAMAGE = function()
                    L.SpellHit("SPELL_DAMAGE", t, "onus", NOBODY, none, me, mine, spell or 0, 4, amount, "")
                end,
                SPELL_MISSED = function() -- the source makes none today: the handler's branch all the same
                    L.Miss(t, "onus", NOBODY, none, me, mine, spell or 0, 4, "PARRY", false)
                end,
            }
        end

        -- Each row in each world: tank or not, grouped or solo, in combat or not.
        local function worlds(run, spell)
            for _, tank in ipairs({ true, false }) do
                for _, grouped in ipairs({ true, false }) do
                    for _, combat in ipairs({ true, false }) do
                        fight(H, combat)
                        st.role.tank, H.ctl.inGroup = tank, grouped
                        local at = ("tank=%s grouped=%s combat=%s "):format(
                            tostring(tank),
                            tostring(grouped),
                            tostring(combat)
                        )
                        for name, emit in pairs(rows(0, spell)) do
                            run(emit, at .. name)
                        end
                    end
                end
            end
        end

        it("counts no enemy, tank or not, and eliminates none", function()
            H.ns.updateTarget(FOE, H.ctl.now, true)
            H.ns.updatedTargetCount = false
            H.log = {}
            worlds(function(emit, at)
                emit()
                assert.are.equal("", flush(), at) -- no target, minion or debuff touched, no zero amount stored
                assert.is_false(H.ns.isTarget(NOBODY), at)
                assert.is_false(H.ns.isMyTarget(NOBODY), at)
                assert.is_false(H.ns.isSummoned(NOBODY), at)
                assert.is_true(H.ns.isTarget(FOE), at)
                assert.are.same({ 1, 1 }, { H.ns.numTargets(), H.ns.numMyTargets() }, at)
                assert.is_false(H.ns.updatedTargetCount, at) -- so no TARGET_COUNT_CHANGED
            end)
            assert.are.same({}, H.errors)
        end)

        it("is never our swing: both swing clocks and the GCD stay", function()
            local sw = st.swings
            local function clocks()
                return { sw.mh_actual, sw.mh_speed, sw.oh_actual, sw.oh_speed, st.gcd.lastStart }
            end
            local before = clocks()
            worlds(function(emit, at)
                emit()
                flush()
                assert.are.same(before, clocks(), at)
            end)
        end)

        it("is never a pet's or a counted minion's, whether the pet's GUID is plain, secret or absent", function()
            H.Hekili.Engine.settings.specs[st.spec.id].damagePets = true
            H.Hekili:UpdateDamageDetectionForCLEU()
            H.ns.updateMinion(STRANGER, H.ctl.now)
            H.log = {}
            local sw = st.swings
            local mh, oh = sw.mh_actual, sw.oh_actual
            for _, pet in ipairs({ PET, fake.SECRET, false }) do
                H.ctl.guid.pet, H.ctl.exists.pet = pet or nil, true
                worlds(function(emit, at)
                    emit()
                    assert.are.equal("", flush(), at)
                    -- a counted minion's row would reach the own-swing branch, which logs nothing
                    assert.are.same({ mh, oh }, { sw.mh_actual, sw.oh_actual }, at)
                end)
            end
            assert.are.same({}, H.errors)
        end)

        it("is never us, though our own GUID be unknown", function()
            st.GUID, me = false, NOBODY -- no GUID of ours to equal (a secret one); the belief's destination is then ""
            worlds(function(emit, at)
                emit()
                assert.are.equal("", flush(), at)
            end)
            assert.are.same({}, H.errors)
        end)

        it("tracks no debuff, though the spell be one of the spec's", function()
            local id
            for k, a in pairs(H.Hekili.Class.auras) do
                if type(k) == "number" and not a.friendly then
                    id = k
                    break
                end
            end
            worlds(function(emit, at)
                emit()
                assert.are.equal("", flush(), at)
                assert.is_false(H.ns.actorHasDebuff(NOBODY, id), at)
            end, id)
        end)

        it("stores a plain amount as damage taken, as a credited row does", function()
            for name, emit in pairs(rows(40)) do
                emit()
                local want = name:find("_DAMAGE") and "storeDamage:" .. H.ctl.now or ""
                assert.are.equal(want, flush(), name)
            end
        end)

        it("is no missed cast of ours (the missable hook)", function()
            H = boot(rw.Combat) -- a class with a missable ability
            me, st = H.ctl.guid.player, H.Hekili.State
            fight(H, true)
            local spec
            for _, s in pairs(H.Hekili.Engine.Registry.Specs()) do
                if s.missAura and next(s.missAura) then
                    spec = s
                end
            end
            local id, aura = next(assert(spec, "no missable ability in the world").missAura)
            rows(0, id).SPELL_MISSED()
            flush()
            assert.are.equal(0, spec.missedAt[aura])
        end)

        it("reaches a hook whole: the empty source and no hole in the tuple", function()
            local hooks, ev, seen = H.Hekili.Class.hooks, "COMBAT_LOG_EVENT_UNFILTERED", {}
            hooks[ev] = hooks[ev] or {}
            hooks[ev][#hooks[ev] + 1] = function(...)
                local _, sub, _, src = ...
                seen[sub] = { src, select("#", ...) }
            end
            for _, emit in pairs(rows(0)) do
                emit()
            end
            flush()
            assert.are.same({ "", 21 }, seen.SWING_DAMAGE)
            assert.are.same({ "", 15 }, seen.SWING_MISSED)
            assert.are.same({ "", 24 }, seen.SPELL_DAMAGE)
            assert.are.same({ "", 18 }, seen.SPELL_MISSED)
        end)

        it("raises nothing in the dev tools' listener", function()
            local f, heard = H.I.Events.CreateFrame("Frame"), 0
            f:SetScript("OnEvent", function(self, event)
                heard = heard + 1
                H.ns.SkeletonHandler(self, event)
            end)
            f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            for _, emit in pairs(rows(40)) do
                emit()
            end
            flush()
            assert.are.equal(4, heard)
            assert.are.same({}, H.errors)
        end)

        it("allocates nothing in the handler, tank or not", function()
            local L, none, mine = H.L, H.L.NONE_FLAGS, H.L.PLAYER_FLAGS
            local function friendly()
                return FRIEND_FLAGS
            end
            H.env.bit = { band = friendly } -- the client's is C; the harness's Lua one makes a closure a call
            for _, tank in ipairs({ true, false }) do
                st.role.tank = tank
                local bytes = alloc.bytes(function()
                    L.Swing(H.ctl.now, "onus", NOBODY, none, me, mine, 0, "", false)
                    L.Miss(H.ctl.now, "onus", NOBODY, none, me, mine, nil, 1, "DODGE", false)
                    L.Deliver()
                end, 10000)
                assert.are.equal(0, bytes, "tank=" .. tostring(tank))
            end
        end)
    end)
end)
