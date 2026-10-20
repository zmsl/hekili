-- tests/Forever/known_cache_spec.lua (audit first wave, Task 3, item 5): State.lua's per-prediction memos of IsKnown
-- and of IsDisabled's static prefix. Shadow mode: on every cache hit the uncached answer is computed too (the entry
-- dropped, the call repeated, the entry put back) and compared, over the seeds 1-3 Arms gate and a headless Feral
-- fight; a DoT cap flips inside one prediction; a toggle flipped between two predictions is seen by the second.
local headless = require("Game.harness.headless")
local loop = require("Game.harness.loop")
local ww = require("Forever.helpers.warrior_world")
local ld = require("Forever.helpers.load_druid")

-- Wraps instance H's IsKnown and IsDisabled; returns the tally { known, disabled, mismatches }.
local function shadow(H)
    local st, abilities, c = H.Hekili.State, H.Hekili.Class.abilities, H.ns.SpellCaches
    local tally = { known = 0, disabled = 0, mismatches = {} }
    local isKnown, isDisabled = st.IsKnown, st.IsDisabled
    st.IsKnown = function(self, sID)
        local id = sID
        if type(id) ~= "number" then
            id = abilities[id] and abilities[id].id
        end
        if id == nil or c.known[id] == nil then
            return isKnown(self, sID)
        end
        local k, r = isKnown(self, sID)
        c.known[id] = nil
        local k2, r2 = isKnown(self, sID)
        c.known[id], c.knownReason[id] = k, r
        tally.known = tally.known + 1
        if k ~= k2 or r ~= r2 then
            tally.mismatches[#tally.mismatches + 1] = ("IsKnown %s: %s/%s vs %s/%s"):format(
                tostring(sID),
                tostring(k),
                tostring(r),
                tostring(k2),
                tostring(r2)
            )
        end
        return k, r
    end
    st.IsDisabled = function(self, spell, strict)
        local a = abilities[spell or self.this_action]
        local cache, reasons = c.disabled, c.disabledReason
        if strict then
            cache, reasons = c.disabledStrict, c.disabledStrictReason
        end
        if not a or cache[a.key] == nil then
            return isDisabled(self, spell, strict)
        end
        local d, r = isDisabled(self, spell, strict)
        local code, why = cache[a.key], reasons[a.key]
        cache[a.key] = nil
        local d2 = isDisabled(self, spell, strict)
        cache[a.key], reasons[a.key] = code, why
        tally.disabled = tally.disabled + 1
        if not d ~= not d2 then
            tally.mismatches[#tally.mismatches + 1] = ("IsDisabled %s: %s vs %s"):format(
                a.key,
                tostring(d),
                tostring(d2)
            )
        end
        return d, r
    end
    return tally
end

-- A level 60 Feral Druid on the whole addon headless: every rank of every ability the class file registers known,
-- the four forms, Cat Form up, energy 100.
local function druid()
    local w = ld.load()
    local known = {}
    for _, a in pairs(w.abilities) do
        if type(a.id) == "number" and a.id > 0 then
            known[#known + 1] = a.id
            for _, id in ipairs(type(a.copy) == "table" and a.copy or {}) do
                known[#known + 1] = id
            end
        end
    end
    local forms = {}
    for i, key in ipairs({ "bear_form", "aquatic_form", "cat_form", "travel_form" }) do
        forms[i] = w.abilities[key].id
    end
    return headless.new({
        character = {
            class = "DRUID",
            classID = 11,
            specID = 1483, -- the client's Druid pseudo-spec
            level = 60,
            known = known,
            power = { type = 3, token = "ENERGY", max = 100, value = 100 },
            forms = forms,
            form = 3,
        },
        pack = "Feral (wowsims.com)",
    })
end

describe("the per-prediction memos of IsKnown and IsDisabled", function()
    it("answer every cache hit as the uncached computation does over the seeds 1-3 Arms gate #slow", function()
        local L = loop.new(ww)
        local us, oracle = shadow(L.us), shadow(L.oracle)
        local m = loop.tally(L, 3)
        assert.are.same({ 0, 0, 0 }, { m.errors, m.raises, m.selfCheck })
        print(
            ("\nshadow Arms: IsKnown hits %d, IsDisabled hits %d, mismatches %d"):format(
                us.known + oracle.known,
                us.disabled + oracle.disabled,
                #us.mismatches + #oracle.mismatches
            )
        )
        assert.are.same({}, us.mismatches)
        assert.are.same({}, oracle.mismatches)
        assert.is_true(us.known > 1000 and us.disabled > 1000 and oracle.known > 1000)
    end)

    it("answer every cache hit as the uncached computation does over a headless Feral fight #slow", function()
        local H = druid()
        assert.are.same({}, H.loadErrors)
        local tally = shadow(H)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        H.ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        local t = H.ctl.now
        for _ = 1, 300 do -- 60 s at 5 Hz, nothing pressed: the APL and its predicted casts read the cooldowns
            t = t + 0.2
            assert(headless.cycle(H, t))
        end
        print(
            ("\nshadow Feral: IsKnown hits %d, IsDisabled hits %d, mismatches %d"):format(
                tally.known,
                tally.disabled,
                #tally.mismatches
            )
        )
        assert.are.same({}, H.errors)
        assert.are.same({}, tally.mismatches)
        assert.is_true(tally.known > 100 and tally.disabled > 100)
    end)

    describe("within and between predictions (headless Arms)", function()
        local H, st, opt

        before_each(function()
            H = headless.new({ character = ww.character(), pack = ww.PACK })
            assert.are.same({}, H.loadErrors)
            H.ctl.inRange.target, H.ctl.level.target = true, 60
            H.Fire("PLAYER_TARGET_CHANGED")
            assert(headless.cycle(H, H.ctl.now + 0.2))
            st = H.Hekili.State
            opt = H.Hekili.Engine.settings.specs[ww.SPEC].abilities.rend
        end)

        after_each(function()
            opt.dotCap = 0
        end)

        it("re-reads the DoT cap as the simulation advances, within one prediction", function()
            opt.dotCap = 1
            st.reset("Primary", true)
            st.applyDebuff("target", "rend")
            assert.are.equal(1, st.active_dot.rend)
            assert.is_false(st.dot.rend.refreshable)
            assert.is_true((st:IsDisabled("rend")))
            st.advance(0.8 * st.debuff.rend.duration) -- past the 30% refresh threshold; no ResetSpellCaches between
            assert.is_true(st.dot.rend.refreshable)
            assert.is_false((st:IsDisabled("rend")))
        end)

        it("sees a toggle flipped between two predictions", function()
            local toggles = H.Hekili.Engine.settings.toggles
            local key = H.Hekili.Class.abilities.recklessness.toggle
            assert.is_string(key)
            local was = toggles[key].value
            toggles[key].value = true
            H.Hekili:ResetSpellCaches()
            st.reset("Primary", true)
            assert.is_false((st:IsDisabled("recklessness")))
            assert.is_false((st:IsDisabled("recklessness"))) -- the cached answer
            assert.is_not_nil(H.ns.SpellCaches.disabled.recklessness)
            toggles[key].value = false
            H.Hekili:ResetSpellCaches() -- the next prediction, as GetNextPrediction starts it
            assert.is_true((st:IsDisabled("recklessness")))
            toggles[key].value = was
        end)

        it("never caches the prefix of an ability whose toggle has an override (a buff can flip it)", function()
            local toggles = H.Hekili.Engine.settings.toggles
            local key = H.Hekili.Class.abilities.recklessness.toggle
            local was = toggles[key].override
            toggles[key].override = true
            H.Hekili:ResetSpellCaches()
            st.reset("Primary", true)
            st:IsDisabled("recklessness")
            assert.is_nil(H.ns.SpellCaches.disabled.recklessness)
            toggles[key].override = was
        end)

        it("wipes the caches in state.reset after the display's filter is set", function()
            local a = H.Hekili.Class.abilities.mortal_strike
            st.reset("Primary", true)
            assert.is_false((st:IsDisabled("mortal_strike")))
            assert.is_not_nil(H.ns.SpellCaches.disabled.mortal_strike)
            assert.is_falsy(a.interrupts) -- not an interrupt: the Interrupts display's filter disables it
            assert.is_table(H.Hekili.Engine.settings.displays.Interrupts)
            -- a read inside reset before the filter is assigned (the reset_preauras hook) caches the old filter's answer
            local hooks = H.Hekili.Class.hooks
            local had = hooks.reset_preauras
            hooks.reset_preauras = {
                function()
                    st:IsDisabled("mortal_strike")
                end,
            }
            st.reset("Interrupts", true)
            hooks.reset_preauras = had
            assert.are.equal("interrupts", st.filter)
            assert.is_true((st:IsDisabled("mortal_strike")))
            st.reset("Primary", true)
            assert.is_false((st:IsDisabled("mortal_strike")))
        end)

        it("caches the target-count check for one prediction and re-reads it in the next", function()
            local ms = H.Hekili.Engine.settings.specs[ww.SPEC].abilities.mortal_strike
            st.reset("Primary", true)
            assert.are.equal(1, st.active_enemies)
            ms.targetMin = 2
            H.Hekili:ResetSpellCaches()
            assert.is_true((st:IsDisabled("mortal_strike")))
            ms.targetMin = 0
            H.Hekili:ResetSpellCaches()
            assert.is_false((st:IsDisabled("mortal_strike")))
        end)
    end)
end)
