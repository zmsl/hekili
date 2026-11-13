-- tests/Forever/mana_share_spec.lua: a wowsims pack's absolute mana threshold on a small pool (translator rule 22,
-- tools/wowsims/apl.lua). A player's report (v0.8.0): a level 20 Affliction Warlock (1132 mana) was shown Life Tap
-- every GCD at full mana from the cooldowns list's `mana.lo<1800`, an amount wowsims writes for its level 60 kit's
-- pool. Each threshold also reads its share of the kit's pool: quiet on a full small pool, firing as before under the
-- amount on the kit's pool. Each case runs the pack's own line through the engine, the believed mana set directly.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warlock_world")
local dlw = require("Forever.helpers.druid_loop_world")
local pw = require("Forever.helpers.priest_world")

local MANA, ENERGY = 0, 3

-- The pack's one line that starts with `head`, as an `actions+=/` line.
local function line(class, pack, head)
    local f = assert(io.open(("src/Hekili_%s/APLs/%s.simc"):format(class, pack), "rb"))
    local s = f:read("*a")
    f:close()
    local rest = assert(s:match("\n" .. head:gsub("%p", "%%%0") .. "([^\n]*)"), head)
    return "actions+=/" .. head:match("/(.*)$") .. rest
end

-- The first recommendation of character `ch` running `text` as the pack's default list, on a mana pool of `max`;
-- each call sets the believed mana (and energy, when given) and returns it.
local function engine(ch, pack, text, max, distance)
    ch.power = ch.power.type == MANA and { type = MANA, token = "MANA", max = max } or ch.power
    local H = headless.new({ character = ch, pack = pack })
    assert.are.same({}, H.loadErrors)
    H.ctl.powerMax[MANA] = max
    H.ctl.level.target, H.ctl.distance.target = 60, distance
    H.Fire("PLAYER_TARGET_CHANGED")
    local t = H.ctl.now + 0.2
    assert(headless.cycle(H, t))
    local lines = H.Hekili:ParseActionList(text)
    for _, l in ipairs(lines) do
        l.enabled = true
    end
    H.Hekili.DB.profile.packs[pack].lists = { precombat = {}, default = lines }
    H.Hekili:LoadScripts()
    H.Hekili.DB.profile.toggles.cooldowns.value = true -- Dark Sacrifice is a cooldowns-toggle ability
    H.Fire("PLAYER_REGEN_DISABLED")
    local VS = H.ns.VirtualState
    local power, pools = VS.Power, {}
    VS.Power = function(pt, now)
        return pools[pt] or power(pt, now)
    end
    local out = H.Hekili.Engine.Output.Primary
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
    return function(mana, energy)
        pools[MANA] = { est = mana, lo = mana, hi = mana, conf = 1 }
        pools[ENERGY] = energy and { est = energy, lo = energy, hi = energy, conf = 1 } or nil
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.same({}, H.errors)
        assert.are.equal(max, H.Hekili.State.mana.max)
        return out.recs[1] and out.recs[1].actionName
    end
end

describe("a wowsims pack's absolute mana threshold on a small pool (rule 22)", function()
    -- Warlock: the cooldowns list's Life Tap, Shadow Bolt after it (any line below a quiet Life Tap)
    for _, p in ipairs({
        { "Affliction", 6277, 1800 }, -- the kit's pool: tests/Forever/wowsims/warlock_affliction.log
        { "Destruction", 5503, 2600 }, -- warlock_destruction.log
        { "Demonology", 6328, 2600 }, -- warlock_demonology.log
        { "ShadowBrand", 6328, 2600 }, -- warlock_shadow_brand.log
    }) do
        local name, kit, n = p[1], p[2], p[3]
        local function at(max)
            local C = ww[name]
            local text = line("Warlock", C.PACK, "actions.cooldowns+=/life_tap") .. "\nactions+=/shadow_bolt"
            assert.is_truthy(text:find("mana.lo<" .. n, 1, true), text)
            return engine(C.character(), C.PACK, text, max, 25)
        end

        it(name .. ": no cooldowns-list Life Tap at full mana on a 1132 pool (level 20), one near empty", function()
            local d = at(1132)
            assert.are.same({ "shadow_bolt", "life_tap" }, { d(1132), d(300) })
        end)

        it(name .. ": the kit's pool still taps under " .. n .. ", not over", function()
            local d = at(kit)
            assert.are.same({ "life_tap", "shadow_bolt" }, { d(n - 1), d(n + 1) })
        end)
    end

    -- Feral: Innervate in Cat Form at low energy, in melee
    local function innervate(max)
        local C = dlw.Feral
        local text = line("Druid", "Feral (wowsims.com)", "actions+=/innervate")
        assert.is_truthy(text:find("mana.lo<1400", 1, true), text)
        return engine(C.character(), "Feral (wowsims.com)", text, max, 3)
    end

    it("Feral: no Innervate at full mana on a 1132 pool (level 20)", function()
        local d = innervate(1132)
        assert.are.same({ "none", "innervate" }, { d(1132, 20) or "none", d(300, 20) })
    end)

    it("Feral: the kit's pool (2584) still innervates under 1400, not over", function()
        local d = innervate(2584) -- tests/Forever/wowsims/druid_feral.log
        assert.are.same({ "innervate", "none" }, { d(1399, 20), d(1401, 20) or "none" })
    end)

    -- Shadow Priest: Dark Sacrifice's `<=` line, Shadow Word: Pain after it
    local function sacrifice(max)
        local C = pw.Shadow
        local text = line("Priest", C.PACK, "actions+=/dark_sacrifice") .. "\nactions+=/shadow_word_pain"
        assert.is_truthy(text:find("mana.lo<=2000", 1, true), text)
        local ch = C.character()
        ch.known[#ch.known + 1] = 1277324 -- Dark Sacrifice, the Undead's: the Shadow world's kit has no racial
        return engine(ch, C.PACK, text, max, 25)
    end

    it("Shadow Priest: no Dark Sacrifice at full mana on a 1132 pool (level 20), one near empty", function()
        local d = sacrifice(1132)
        assert.are.same({ "shadow_word_pain", "dark_sacrifice" }, { d(1132), d(300) })
    end)

    it("Shadow Priest: the kit's pool (4846) still sacrifices at 2000 and under, not over", function()
        local d = sacrifice(4846) -- tests/Forever/wowsims/priest_shadow.log
        assert.are.same({ "dark_sacrifice", "dark_sacrifice", "shadow_word_pain" }, { d(1999), d(2000), d(2001) })
    end)
end)
