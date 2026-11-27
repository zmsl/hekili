-- tests/Forever/cooldown_on_event_spec.lua (lane cooldown-on-event, L2012; from PR zmsl/hekili#22, reported by
-- himea-saito): a spell whose cooldown starts when its effect ends (spell attribute 0x02000000, "cooldown on event":
-- Divine Favor, Presence of Mind, Nature's Swiftness, ...) declares the aura with `cooldownAfter`, and the core holds its
-- cooldown while that aura is up and starts it when the aura is spent or runs out: in the read (the belief, in combat)
-- and in the forecast (the simulation).
local headless = require("Game.harness.headless")
local fake = require("Game.State.helpers.fake_api")
local ld = require("Forever.helpers.load_druid")

local SECRET = fake.SECRET
local DIVINE_FAVOR, HOLY_SHOCK, AMPLIFY_CURSE = 20216, 1311606, 18288
local RUNNING = { isActive = true, isOnGCD = false, startTime = SECRET, duration = SECRET } -- the client, in combat

local function boot(C)
    local H = headless.new({ character = C.character(), pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    local t = H.ctl.now + 0.2
    assert(headless.cycle(H, t))
    H.Fire("PLAYER_REGEN_DISABLED")
    return H, t
end

local function cast(H, t, n, id)
    H.ctl.now = t
    H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, id)
    assert(headless.cycle(H, t + 0.1))
end

local function near(want, got, eps)
    assert(math.abs(want - got) <= (eps or 0.3), ("want %.2f, got %.2f"):format(want, got))
end

describe("a cooldown that starts when its aura ends (cooldownAfter)", function()
    it("is a registered ability field naming an aura", function()
        local H = headless.new({
            character = require("Forever.helpers.paladin_world").HolyShock.character(),
            pack = "Holy Shock (wowsims.com)",
        })
        local row = H.ns.Fields.rows.ability.cooldownAfter
        assert.is_table(row)
        assert.are.equal("aura", row.type)
    end)

    -- the read: Divine Favor pressed in combat is held while its charge is up, then runs 120 s from Holy Shock's spend
    it("holds Divine Favor while its charge is up and runs it from the spend (the read)", function()
        local H, t = boot(require("Forever.helpers.paladin_world").HolyShock)
        local st = H.Hekili.State
        cast(H, t + 1, 1, DIVINE_FAVOR)
        st.reset("Primary", true)
        assert.is_true(st.buff.divine_favor.up)
        assert.is_false(st.cooldown.divine_favor.ready)
        assert.is_true(st.cooldown.divine_favor.remains > 1000, tostring(st.cooldown.divine_favor.remains))

        -- 10 s later Holy Shock spends the charge: the client starts the cooldown then
        t = t + 11
        H.ctl.cooldown[DIVINE_FAVOR] = RUNNING
        cast(H, t, 2, HOLY_SHOCK)
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert(headless.cycle(H, t + 0.2))
        st.reset("Primary", true)
        assert.is_false(st.buff.divine_favor.up)
        near(120 - 0.2, st.cooldown.divine_favor.remains)

        -- and keeps running (no frozen "ready in 0.5 s")
        t = t + 60
        H.ctl.now = t
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert(headless.cycle(H, t))
        st.reset("Primary", true)
        near(60, st.cooldown.divine_favor.remains)
        assert.are.same({}, H.errors)
    end)

    -- the client's cooldown edge comes a poll after our spend (the flag still reads ready then): the run is from the spend
    it("runs Divine Favor from the spend when the client's edge comes after it", function()
        local H, t = boot(require("Forever.helpers.paladin_world").HolyShock)
        local st = H.Hekili.State
        cast(H, t + 1, 1, DIVINE_FAVOR)
        t = t + 11
        cast(H, t, 2, HOLY_SHOCK) -- the fake's flag still ready (isActive false)
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert(headless.cycle(H, t + 0.2))
        H.ctl.now = t + 0.3
        H.ctl.cooldown[DIVINE_FAVOR] = RUNNING
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert(headless.cycle(H, t + 0.4))
        st.reset("Primary", true)
        near(120 - 0.4, st.cooldown.divine_favor.remains)
        t = t + 30
        H.ctl.now = t
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert(headless.cycle(H, t))
        st.reset("Primary", true)
        near(90, st.cooldown.divine_favor.remains)
        assert.are.same({}, H.errors)
    end)

    -- the forecast: a press holds it, a spend starts it from the spend
    it("holds Divine Favor after a forecast press and starts it at the forecast spend", function()
        local H, t = boot(require("Forever.helpers.paladin_world").HolyShock)
        local st = H.Hekili.State
        assert(headless.cycle(H, t + 1))
        st.reset("Primary", true)
        assert.is_true(st.cooldown.divine_favor.ready)
        st.setCooldown("divine_favor", 120) -- the forecast's press (Engine/Sim/Core.lua), then its handler
        st.runHandler("divine_favor")
        assert.is_true(st.buff.divine_favor.up)
        assert.is_true(st.cooldown.divine_favor.remains > 1000, tostring(st.cooldown.divine_favor.remains))
        st.advance(5)
        st.runHandler("holy_shock") -- spends the charge
        assert.is_false(st.buff.divine_favor.up)
        near(120, st.cooldown.divine_favor.remains, 0.01)
        assert.are.same({}, H.errors)
    end)

    -- a timed aura: Amplify Curse's 30 s runs out unspent, the cooldown starts at its expiry
    it("starts Amplify Curse's cooldown when its 30 s aura runs out (forecast and read)", function()
        local C = require("Forever.helpers.warlock_world").Affliction
        local H, t = boot(C)
        local st = H.Hekili.State
        assert(headless.cycle(H, t + 1))
        st.reset("Primary", true)
        st.setCooldown("amplify_curse", 180)
        st.runHandler("amplify_curse")
        near(30 + 180, st.cooldown.amplify_curse.remains, 0.01)
        st.advance(40)
        near(170, st.cooldown.amplify_curse.remains, 0.01)

        -- the read: pressed in combat, never spent; the client starts the cooldown at the expiry
        cast(H, t + 2, 1, AMPLIFY_CURSE)
        t = t + 2 + 31
        H.ctl.now = t
        H.ctl.cooldown[AMPLIFY_CURSE] = RUNNING
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert(headless.cycle(H, t))
        st.reset("Primary", true)
        near(180 - 1, st.cooldown.amplify_curse.remains)
        assert.are.same({}, H.errors)
    end)
end)

-- Each declared holder and one spender its pack models (the `now` in the read, the handler in the forecast): the
-- spend takes the aura down and starts the cooldown from it. Combustion (no spender modelled: its charges go on crits)
-- and Shadowform (only cancelled) have none.
describe("each declared holder's spend", function()
    local CASES = {
        { "mage_world", "Frost", "presence_of_mind", "frostbolt", 180 },
        { "druid_loop_world", "Balance", "natures_swiftness", "wrath", 180 },
        { "druid_loop_world", "Feral", "prowl", "ravage", 10 },
        { "shaman_world", "Elemental", "natures_swiftness", "lightning_bolt", 180 },
        { "rogue_world", "Combat", "cold_blood", "sinister_strike", 180 },
        { "rogue_world", "Subtlety", "stealth", "ambush", 10 },
        { "priest_world", "Shadow", "inner_focus", "mind_blast", 180 },
        { "warlock_world", "Affliction", "amplify_curse", "bane_of_agony", 180 },
    }
    for _, c in ipairs(CASES) do
        local holder, spender, cd = c[3], c[4], c[5]
        it(holder .. " is held, then runs from " .. spender .. " (read and forecast)", function()
            local C = require("Forever.helpers." .. c[1])[c[2]]
            local ch = C.character()
            local H0 = headless.new({ character = ch, pack = C.PACK })
            local ab = H0.Hekili.Class.abilities
            for _, key in ipairs({ holder, spender }) do -- known, whatever the content's kit
                ch.known[#ch.known + 1] = ab[key].id
            end
            local H = headless.new({ character = ch, pack = C.PACK })
            assert.are.same({}, H.loadErrors)
            H.ctl.inRange.target, H.ctl.level.target = true, 60
            H.Fire("PLAYER_TARGET_CHANGED")
            local t = H.ctl.now + 0.2
            assert(headless.cycle(H, t))
            local st = H.Hekili.State
            ab = H.Hekili.Class.abilities

            -- the forecast
            st.reset("Primary", true)
            st.setCooldown(holder, cd)
            st.runHandler(holder)
            assert.is_true(st.cooldown[holder].remains > cd, "forecast hold")
            st.advance(2)
            H.ns.spendResources(spender) -- as the forecast's press does (Engine/Sim/Core.lua): a cost charge's spend
            st.runHandler(spender)
            assert.is_false(st.buff[holder].up, "forecast spend")
            near(cd, st.cooldown[holder].remains, 0.01)

            -- the read (in combat but Prowl and Stealth, used before it)
            if holder ~= "prowl" and holder ~= "stealth" then
                H.Fire("PLAYER_REGEN_DISABLED")
            end
            cast(H, t + 1, 1, ab[holder].id)
            st.reset("Primary", true)
            assert.is_true(st.cooldown[holder].remains > cd, "read hold")
            t = t + 5
            H.ctl.cooldown[H.ns.VirtualState.KnownID(ab[holder].id)] = RUNNING -- the client answers the known rank
            cast(H, t, 2, ab[spender].id)
            H.Fire("SPELL_UPDATE_COOLDOWN")
            assert(headless.cycle(H, t + 0.2))
            st.reset("Primary", true)
            assert.is_false(st.buff[holder].up, "read spend")
            near(cd - 0.2, st.cooldown[holder].remains)
            assert.are.same({}, H.errors)
        end)
    end
end)

-- Every modelled spell of the class (wowsims pin ab0f00e4fc spells_auto_gen.go, Attr[0] & 0x02000000) declares its aura.
describe("the packs' cooldown-on-event spells", function()
    local DECLARED = {
        { "src/Hekili_Paladin/Paladin.lua", "PALADIN", { divine_favor = "divine_favor" } },
        {
            "src/Hekili_Mage/Mage.lua",
            "MAGE",
            { presence_of_mind = "presence_of_mind", combustion = "combustion" },
        },
        { "src/Hekili_Druid/Druid.lua", "DRUID", { natures_swiftness = "natures_swiftness", prowl = "prowl" } },
        { "src/Hekili_Shaman/Shaman.lua", "SHAMAN", { natures_swiftness = "natures_swiftness" } },
        { "src/Hekili_Rogue/Rogue.lua", "ROGUE", { cold_blood = "cold_blood", stealth = "stealth" } },
        { "src/Hekili_Priest/Priest.lua", "PRIEST", { inner_focus = "inner_focus", shadowform = "shadowform" } },
        { "src/Hekili_Warlock/Warlock.lua", "WARLOCK", { amplify_curse = "amplify_curse" } },
    }
    for _, d in ipairs(DECLARED) do
        it(d[2] .. " declares cooldownAfter on each", function()
            local w = ld.load(nil, d[1], d[2])
            for key, aura in pairs(d[3]) do
                assert.are.equal(aura, w.abilities[key] and w.abilities[key].cooldownAfter, key)
            end
        end)
    end
end)
