-- tests/Forever/trinkets_spec.lua (lane gear-1, G6): the on-use trinkets (Hekili_Shared Items.lua) are recommended. A
-- worn one binds to trinket1/trinket2 and joins `use_items`; a cast of its use spell is its cast (the `copy` alias);
-- with the item cooldown read secret the belief answers it (the cast + the item's cooldown), and the shared category
-- 1141 holds the other trinket for its window without ever shortening a longer cooldown; an equipment change rebinds.
local headless = require("Game.harness.headless")
local fake = require("Game.State.helpers.fake_api")
local C = require("Forever.helpers.mage_world").Frost

local SECRET = fake.SECRET
local ANALYZER, ANALYZER_SPELL = 272438, 1291101 -- Weakness Analyzer: 360 s, category 1141 (20 s)
local EYE, EYE_SPELL = 13968, 1287840 -- Eye of the Beast: 300 s, category 1141 (20 s)

-- A Frost Mage wearing `t13` and `t14`, its gear read, in combat, on a pack of `line` (simc lines, "\n" apart) then
-- Frostbolt; a strict sequence's windows are applied and built as an options edit would.
local function boot(t13, t14, line)
    local char = C.character()
    char.items = char.items or {}
    char.items[13] = t13 and { t13 } or nil
    char.items[14] = t14 and { t14 } or nil
    local H = headless.new({ character = char, pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    for _, id in ipairs({ ANALYZER, EYE }) do
        H.ctl.itemUsable[id] = true
    end
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    H.Fire("PLAYER_EQUIPMENT_CHANGED")
    local t = H.ctl.now + 1.5 -- the gear re-read runs 1 s after the event
    assert(headless.cycle(H, t))
    local lines = H.Hekili:ParseActionList("actions+=/" .. (line or "use_items"):gsub("\n", "\nactions+=/"))
    for _, l in ipairs(lines) do
        l.enabled = true
    end
    lines[#lines + 1] = { enabled = true, action = "frostbolt" }
    H.Hekili.DB.profile.packs[C.PACK].lists = { precombat = {}, default = lines }
    H.Hekili:LoadScripts()
    if line and line:find("strict_sequence", 1, true) then
        H.Hekili:ReviewPacks()
        H.Hekili.Scripts:ApplyWindows(C.PACK)
        H.Hekili.State:BuildWindows()
        H.ns.VirtualState.Drain(H.ctl.now)
    end
    H.Hekili:FireToggle("cooldowns", "on")
    H.Fire("PLAYER_REGEN_DISABLED")
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
    return H, t
end

local function first(H)
    local recs = H.Hekili.Engine.Output.Primary.recs
    return recs[1] and recs[1].actionName
end

local function cooldowns(H)
    local st = H.Hekili.State
    st.reset("Primary", true)
    return st.cooldown.trinket1.remains, st.cooldown.trinket2.remains
end

describe("an on-use trinket", function()
    it("is one ability, its use spell's cast row resolving to it", function()
        local H = boot(ANALYZER)
        local class = H.Hekili.Class
        assert.are.equal(class.abilities.weakness_analyzer, class.abilities[ANALYZER_SPELL])
        assert.are.equal("weakness_analyzer", class.itemMap[ANALYZER])
        assert.are.equal("off", class.abilities.weakness_analyzer.gcd)
        assert.are.equal(360, class.abilities.weakness_analyzer.cooldown)
    end)

    it("joins use_items and binds trinket1 while worn; an unequip rebinds to none", function()
        local H, t = boot(ANALYZER)
        local st = H.Hekili.State
        assert.are.same({ "weakness_analyzer" }, st.items)
        assert.are.equal("weakness_analyzer", st.trinket.t1.__ability)
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.equal("weakness_analyzer", first(H))
        H.ctl.inventory[13] = nil
        H.Fire("PLAYER_EQUIPMENT_CHANGED")
        t = t + 1.5
        assert(headless.cycle(H, t))
        assert.are.same({}, st.items)
        assert.are.equal("null_cooldown", st.trinket.t1.__ability)
        assert.are.equal("frostbolt", first(H))
        H.ctl.inventory[13] = EYE
        H.Fire("PLAYER_EQUIPMENT_CHANGED")
        t = t + 1.5
        assert(headless.cycle(H, t))
        assert.are.equal("eye_of_the_beast", st.trinket.t1.__ability)
        assert.are.same({}, H.errors)
    end)

    it("is held by the belief after its cast while the item cooldown reads secret", function()
        local H, t = boot(ANALYZER, EYE)
        H.ctl.itemCooldown[ANALYZER], H.ctl.itemCooldown[EYE] = { SECRET, SECRET }, { SECRET, SECRET }
        H.ctl.now = t + 0.1
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", ANALYZER_SPELL)
        t = t + 5
        assert(headless.cycle(H, t))
        local r1, r2 = cooldowns(H)
        assert.is_true(math.abs(r1 - 355.1) < 0.5, "trinket1 " .. r1) -- 360 s from the cast
        assert.is_true(math.abs(r2 - 15.1) < 0.5, "trinket2 " .. r2) -- the category's 20 s window
        assert.are.equal("frostbolt", first(H))
        t = t + 16 -- the window over: the Eye is offered, the Analyzer still held
        assert(headless.cycle(H, t))
        assert.are.equal("eye_of_the_beast", first(H))
        assert.are.same({}, H.errors)
    end)

    it("holds the other trinket in the simulation's prediction after a predicted use (plain reads)", function()
        local H, t = boot(ANALYZER, EYE)
        t = t + 0.2
        assert(headless.cycle(H, t))
        local recs = H.Hekili.Engine.Output.Primary.recs
        assert.are.equal("weakness_analyzer", recs[1] and recs[1].actionName) -- the longer cooldown first (itemSorter)
        assert.is_truthy(recs[2] and recs[2].actionName)
        for i = 2, 3 do
            assert.are_not.equal("eye_of_the_beast", recs[i] and recs[i].actionName) -- its 20 s window
        end
        assert.are.same({}, H.errors)
    end)

    it("never shortens a longer cooldown with the category's window", function()
        local H, t = boot(ANALYZER, EYE)
        H.ctl.itemCooldown[ANALYZER], H.ctl.itemCooldown[EYE] = { SECRET, SECRET }, { SECRET, SECRET }
        H.ctl.now = t + 0.1
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", EYE_SPELL) -- the Eye: 300 s, the Analyzer 20 s
        H.ctl.now = t + 30
        H.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", ANALYZER_SPELL) -- the Analyzer: the Eye's 20 s window
        t = t + 31
        assert(headless.cycle(H, t))
        local r1, r2 = cooldowns(H)
        assert.is_true(math.abs(r1 - 359) < 0.5, "trinket1 " .. r1)
        assert.is_true(math.abs(r2 - 269.1) < 0.5, "trinket2 " .. r2) -- still the Eye's own 300 s
        assert.are.same({}, H.errors)
    end)

    -- L1960 (trace lane trinket-flash): the line's use_off_gcd=1 reaches the items it walks, so a trinket never waits
    -- out a running GCD a later use_off_gcd=1 line ignores (Fire: Combustion shown first until the GCD fell to 0.2 s,
    -- then the trinket by list order, a now<->next swap with no fact); a plain use_items still waits for the GCD.
    for _, c in ipairs({ { "use_items,use_off_gcd=1", false }, { "use_items", true } }) do
        it("waits for a running GCD only without use_off_gcd=1 (" .. c[1] .. ")", function()
            local H, t = boot(EYE, nil, c[1])
            H.ctl.cooldown[H.ns.GCD_SPELL] = { isActive = true, isOnGCD = false, startTime = t, duration = 1.5 }
            for _, left in ipairs({ 0.4, 0.2 }) do
                assert(headless.cycle(H, t + 1.5 - left))
                local r = H.Hekili.Engine.Output.Primary.recs[1]
                assert.are.equal("eye_of_the_beast", r and r.actionName)
                local want = c[2] and left or 0
                assert.is_true(math.abs(r.time - want) < 0.05, ("GCD %.1f left: wait %.3f"):format(left, r.time))
            end
            assert.are.same({}, H.errors)
        end)
    end

    -- L1960 condition 1: the swap itself. A use_items,use_off_gcd=1 line above a direct use_off_gcd=1 off-GCD line, both
    -- ready under a running GCD: the same now and next at 0.4 and 0.2 s left (before the fix Cold Snap took slot 1
    -- while the trinket waited out the GCD, then the trinket at the 0.2 s early exit: a swap with no fact).
    it("keeps its slot above a later use_off_gcd=1 line through a running GCD (no now<->next swap)", function()
        local H, t = boot(EYE, nil, "use_items,use_off_gcd=1\ncold_snap,use_off_gcd=1")
        H.ctl.cooldown[H.ns.GCD_SPELL] = { isActive = true, isOnGCD = false, startTime = t, duration = 1.5 }
        for _, left in ipairs({ 0.4, 0.2 }) do
            assert(headless.cycle(H, t + 1.5 - left))
            local recs = H.Hekili.Engine.Output.Primary.recs
            local got = { recs[1] and recs[1].actionName, recs[2] and recs[2].actionName }
            assert.are.same({ "eye_of_the_beast", "cold_snap" }, got, ("GCD %.1f left"):format(left))
            -- the flag holds for the items walk only: Core clears it after the walk (a leak skips later lines' GCD wait)
            assert.is_false(H.Hekili.State.itemsOffGCD)
        end
        assert.are.same({}, H.errors)
    end)

    -- L1960 condition 2: a strict hold (holdOffOnly 1, ruling 29) lets a trinket walked from use_items,use_off_gcd=1
    -- through, as it does a direct use_off_gcd=1 off-GCD line; a plain use_items line is itself held by the strict hold
    -- (Core.lua's holdOffOnly test: no use_off_gcd=1 on the line), so its items are never walked (this pins existing
    -- behaviour); hold_off_gcd=1 holds every outside line (the variable line makes that hold walk the lists).
    for _, c in ipairs({
        { "", "use_items,use_off_gcd=1", "eye_of_the_beast" },
        { "", "use_items", "frostbolt" },
        { ",hold_off_gcd=1", "use_items,use_off_gcd=1", "frostbolt" },
    }) do
        it("under a strict hold" .. c[1] .. ", from " .. c[2] .. ": " .. c[3] .. " first", function()
            local seq = "variable,name=v,value=1\nstrict_sequence,name=s" .. c[1] .. ":frostbolt:ice_lance\n"
            local H, t = boot(EYE, nil, seq .. c[2])
            assert(headless.cycle(H, t + 0.2)) -- opens the sequence at step 1 (Frostbolt)
            assert(headless.cycle(H, t + 0.4)) -- the hold walks the outside lines
            local recs = H.Hekili.Engine.Output.Primary.recs
            assert.are.equal(c[3], recs[1] and recs[1].actionName)
            assert.are.same({}, H.errors)
        end)
    end

    it("is not offered while the client calls it unusable, with no error on a secret answer", function()
        local H, t = boot(ANALYZER)
        H.ctl.itemUsable[ANALYZER] = false
        t = t + 0.2
        assert(headless.cycle(H, t))
        assert.are.equal("frostbolt", first(H))
        assert.are.same({}, H.errors)
    end)
end)
