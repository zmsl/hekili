-- tests/Forever/attackerless_rows_spec.lua: hits on us with no known attacker in a dungeon (the Map restriction: every
-- other unit's identity secret), from the player's UNIT_COMBAT to the pack readers and the core's enemy count. The
-- player's own GUID is the world's plain one (unmeasured in game under the restriction).
local headless = require("Game.harness.headless")
local mw = require("Forever.helpers.map_world")
local protection = require("Forever.helpers.protection_gate")
local sw = require("Forever.helpers.shaman_world")

local REVENGE = { 6572, 6574, 7379, 11600, 11601, 25288 }
local STORMSTRIKE = 17364

-- A fight under the Map restriction: two plates on us, one our target, as far as the client says.
local function dungeon(content, onMe)
    local H = mw.new("C", { character = content.character(), pack = content.PACK })
    for k = 1, 2 do
        mw.plate(H, k)
        H.ctl.unitIs["nameplate" .. k .. "target"] = onMe
        H.Fire("UNIT_TARGET", "nameplate" .. k)
    end
    mw.target(H, 1)
    H.ctl.now = H.ctl.now + 1
    return H
end

local function hit(H, act, flag)
    H.Fire("UNIT_COMBAT", "player", act, flag or "", mw.SECRET, 1)
end

local function reset(H, dt)
    assert(headless.cycle(H, H.ctl.now + dt))
    H.Hekili.State.reset("Primary", true)
    return H.Hekili.State
end

-- The targets and debuff keys the core is handed.
local function watch(H)
    local keys = {}
    for name, pos in pairs({ updateTarget = 1, eliminateUnit = 1, updateMinion = 1, trackDebuff = 2 }) do
        local real = H.ns[name]
        H.ns[name] = function(...)
            local key = select(pos, ...) -- (never `arg`: 5.1 gives a vararg function its own)
            keys[#keys + 1] = name .. ":" .. (H.env.issecretvalue(key) and "secret" or tostring(key))
            return real(...)
        end
    end
    return keys
end

for _, on in ipairs({ { "plain", "player" }, { "secret", mw.SECRET } }) do
    describe("hits on us with no known attacker under the Map restriction, target-of " .. on[1], function()
        for _, case in ipairs({ { "DODGE" }, { "PARRY" }, { "BLOCK" }, { "WOUND", "BLOCK_REDUCED" } }) do
            it("opens Revenge on a " .. case[1] .. " and counts no enemy for it", function()
                local H = dungeon(protection.content(60), on[2])
                H.Hekili.State.role.tank = true -- the tank branch: a tank tree's role picks it (L1715)
                for _, id in ipairs(REVENGE) do
                    H.ctl.usable[id] = { true, false } -- the client's answer; the row dates the window's end
                end
                local count, keys = mw.count(H), watch(H)
                hit(H, case[1], case[2])
                assert.are.equal(1, H.ns.VirtualStateInternal.Log.unattributed)
                assert.are.same({}, H.errors)
                assert.are.same({}, keys)
                assert.is_false(H.ns.isTarget(""))
                local S = reset(H, 1)
                assert.is_true(S.buff.revenge_usable.up)
                assert.is_near(4, S.buff.revenge_usable.remains, 1e-6)
                assert.are.equal(count, mw.count(H))
                assert.are.same({}, H.errors)
            end)
        end

        for _, act in ipairs({ "DODGE", "PARRY" }) do
            it("resets Stormstrike at rank 2 on a " .. act, function()
                local H = dungeon(sw.Enhancement, on[2])
                H.ctl.cooldown[STORMSTRIKE] =
                    { isActive = true, isOnGCD = false, startTime = mw.SECRET, duration = mw.SECRET }
                H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", STORMSTRIKE)
                H.Fire("SPELL_UPDATE_COOLDOWN")
                local S = reset(H, 1)
                assert.are.equal(2, S.talent.improved_stormstrike.rank)
                assert.is_true(S.cooldown.stormstrike.remains > 0, "the cast's cooldown")
                local count, keys = mw.count(H), watch(H)
                hit(H, act)
                assert.are.same({}, keys)
                assert.are.equal(0, reset(H, 0.5).cooldown.stormstrike.remains)
                assert.are.equal(count, mw.count(H))
                assert.are.same({}, H.errors)
            end)
        end
    end)
end
