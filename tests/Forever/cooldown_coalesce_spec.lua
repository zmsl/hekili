-- tests/Forever/cooldown_coalesce_spec.lua (perf phase 2, item 2.2): with performance.coalesceCooldown on, the event
-- facade holds SPELL_UPDATE_COOLDOWN to the frame's OnUpdate and runs it once: one walk of the tracked abilities, one
-- delivery, the edge flag intact. Off, every event runs at once.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("cooldown coalescing", function()
    local H, ctl, f, perf, id, reads, frame

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        ctl, f, perf = H.ctl, H.ns.EngineFrame, H.Hekili.DB.profile.performance
        local I = H.ns.VirtualStateInternal
        frame = I.Events.frame
        local A = I.ab
        for a = 1, A.n do
            if A.slot[a] > 0 then
                id = A.qid[a]
                break
            end
        end
        assert.is_number(id)
        local C, read = I.api.C_Spell, I.api.C_Spell.GetSpellCooldown
        reads = 0
        C.GetSpellCooldown = function(spell)
            reads = reads + 1
            return read(spell)
        end
        H.Fire("SPELL_UPDATE_COOLDOWN") -- the boot's edges
        f.criticalUpdate = false
    end)

    local function nextFrame()
        frame.__scripts.OnUpdate(frame, 0.016)
    end

    local function switch(on)
        perf.coalesceCooldown = on
        H.Hekili:ProvidersChanged()
    end

    local function walks(events)
        reads = 0
        for _ = 1, events do
            H.Fire("SPELL_UPDATE_COOLDOWN")
        end
        return reads
    end

    it("is off by default: every event walks at once", function()
        assert.is_false(perf.coalesceCooldown)
        local one = walks(1)
        assert.is_true(one > 0)
        assert.are.equal(3 * one, walks(3))
        reads = 0
        nextFrame()
        assert.are.equal(0, reads)
    end)

    it("on: three events in a frame walk once, at the frame's OnUpdate, and not again", function()
        local one = walks(1)
        switch(true)
        assert.are.equal(0, walks(3))
        nextFrame()
        assert.are.equal(one, reads)
        nextFrame()
        assert.are.equal(one, reads)
    end)

    it("on: the edge still forces a cycle, at the OnUpdate; no flip forces none", function()
        switch(true)
        ctl.cooldown[id] = { isActive = true, isOnGCD = false }
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.is_false(f.criticalUpdate)
        nextFrame()
        assert.is_true(f.criticalUpdate)
        f.criticalUpdate = false
        H.Fire("SPELL_UPDATE_COOLDOWN")
        nextFrame()
        assert.is_false(f.criticalUpdate)
    end)

    it("on: the charges event is not held", function()
        switch(true)
        reads = 0
        H.Fire("SPELL_UPDATE_CHARGES")
        assert.is_true(reads > 0)
    end)

    it("the option writes the profile and reaches the build's providers", function()
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        local key = H.Hekili.State.spec.key
        local args = H.Hekili.Options.args.packs.plugins.specializations[key].args.performance.args
        local pv = H.ns.VirtualStateInternal.def.providers
        assert.is_false(args.coalesceCooldown.get())
        assert.is_false(pv.coalesceCooldown)
        args.coalesceCooldown.set(nil, true)
        assert.is_true(perf.coalesceCooldown)
        assert.is_true(pv.coalesceCooldown)
    end)
end)
