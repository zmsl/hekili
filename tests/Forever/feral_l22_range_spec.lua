-- Repro (2026-11-07 owner snapshots feral-20s-*): a level 22 Cat in melee range of a mob is shown no Claw/Shred.
-- The live Forever client reports C_Spell.GetSpellInfo(<melee strike>).maxRange = 0 (ForeverProbe dump: Mortal
-- Strike, Rend, Hamstring, Overpower, Slam, Revenge, Sunder Armor, Shield Bash all 0) while still answering
-- C_Spell.IsSpellInRange(<melee strike>, "target") plain true/false (Rend: 410 plain answers). The fake client
-- assumed 0-5 for melee and nil for maxRange 0, so no test saw the live shape: its `{ 0, 0, 5 }` range is it.
local headless = require("Game.harness.headless")
local dlw = require("Forever.helpers.druid_loop_world")
local PACK = "Feral (wowsims.com)"

-- The snapshot's known kit at level 22 (snap1 lines 152-210 query IDs; "ability unknown" entries left out).
local KNOWN = {
    1082,
    5221,
    1079,
    768,
    770,
    5215,
    6808,
    779,
    5487,
    1066,
    783,
    5211,
    5209,
    8998,
    1735,
    5229,
    1062,
    6795,
    5188,
    6756,
    16810,
    8938,
    2090,
    782,
    5179,
    8926,
    22842,
    22812,
    2912,
}
-- The owner's in-game check (2026-11-07, level 22 Feral): Claw, Shred and Swipe read maxRange 0 and answer
-- IsSpellInRange true in melee, false at about 20 yd; Demoralizing Roar (1735) and Cat Form (768) read 0 and answer
-- nil at both. Claw, Shred, Swipe measured; Rip, Maul, Bash, Cower taken alike.
local MELEE = { 1082, 5221, 779, 1079, 6808, 5211, 8998 }

local function recs(combat, distance)
    local c = dlw.Feral.character()
    c.level = 22
    c.known = KNOWN
    c.talents = { [16934] = 5, [16947] = 3, [17002] = 2, [16998] = 2 } -- snap1 lines 9-12
    c.ranges = c.ranges or {}
    for _, id in ipairs(MELEE) do
        c.ranges[id] = { 0, 0, 5 } -- the live client's maxRange 0 for a melee strike, answering against 5 yd
    end
    for _, id in ipairs({ 5188, 8938, 2090 }) do
        c.ranges[id] = { 0, 40 } -- friendly heals (the fake answers every unlisted spell 0-5)
    end
    for _, id in ipairs({ 770, 6795, 1062, 8926, 5179, 2912, 6756, 782 }) do
        c.ranges[id] = { 0, 30 }
    end
    for _, id in ipairs({ 768, 5215, 5487, 1066, 783, 5209, 1735, 5229, 22842, 22812, 16810 }) do
        c.ranges[id] = { 0, 0 }
    end
    local H = headless.new({ character = c, pack = PACK })
    assert.are.same({}, H.loadErrors)
    H.ctl.level.target, H.ctl.distance.target = 22, distance or 3 -- in melee
    H.Fire("PLAYER_TARGET_CHANGED")
    local VS = H.ns.VirtualState
    local power, full = VS.Power, { est = 100, lo = 100, hi = 100, conf = 1 }
    VS.Power = function(pt, now)
        return pt == 3 and full or power(pt, now)
    end
    local t = H.ctl.now + 0.2
    assert(headless.cycle(H, t))
    if combat then
        H.Fire("PLAYER_REGEN_DISABLED")
    end
    t = t + 1
    assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
    assert(headless.cycle(H, t))
    assert.are.same({}, H.errors)
    local names = {}
    for i, r in ipairs(H.Hekili.Engine.Output.Primary.recs) do
        names[i] = r.actionName
    end
    local r = VS.TargetRange()
    return names, r
end

local function has(list, a, b)
    for _, n in ipairs(list) do
        if n == a or n == b then
            return true
        end
    end
    return false
end

describe("Feral level 22 in melee (owner snapshots 2026-11-07)", function()
    it("in combat: Shred or Claw is recommended and the bracket reads melee", function()
        local list, r = recs(true)
        assert.is_true(r.hi <= 5, ("bracket %s..%s"):format(r.lo, r.hi))
        assert.is_true(has(list, "shred", "claw"), table.concat(list, " "))
    end)

    it("out of combat: after Prowl, Shred or Claw follows", function()
        local list, r = recs(false)
        assert.is_true(r.hi <= 5, ("bracket %s..%s"):format(r.lo, r.hi))
        assert.is_true(has(list, "shred", "claw"), table.concat(list, " "))
    end)

    -- range plan R2: the bracket is LibRangeCheck's (the harness double's 5 yd steps), no longer the kit's answers
    it("at 20 yd: the library's bracket puts the target past melee", function()
        local _, r = recs(true, 20)
        assert.are.same({ 15, 20 }, { r.lo, r.hi })
    end)
end)
