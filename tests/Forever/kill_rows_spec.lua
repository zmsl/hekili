-- tests/Forever/kill_rows_spec.lua (border batch 1, item 1; audit A14): a kill reaches Hekili's own enemy count. The
-- world: two mobs on us; we fight our target (mob 1) until 5 s, the add (mob 2) until 9 s with a Mortal Strike on it
-- (its SPELL_DAMAGE row is what Hekili counts enemies by, ns.updateTarget; white swings never count), then mob 1
-- again; from 12 s a stray hit of ours (a cleave's) kills the add while it is not our target, so only the death events
-- tell of it. Hekili's count must fall from 2 to 1 at the add's death, not when the damage grace (damageExpiration,
-- Audit's ticker) forgets it. The harness loop ends a fight at its first kill, so this spec runs its own ticks.
local headless = require("Game.harness.headless")
local loop = require("Game.harness.loop")
local scenarios = require("Game.harness.scenarios")
local observer = require("Game.harness.observer")
local ww = require("Forever.helpers.warrior_world")

local DURATION = 30

-- Returns the world and, per tick, { t = world time, n = Hekili's enemy count after that tick's cycle }.
local function run(seed)
    local character = ww.character()
    local H = headless.new({ character = character, pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target = true
    local pt = character.power.type
    local ms = ww.resolve("mortal_strike", H)
    local wo = setmetatable({
        pull = loop.PULL,
        prepull = 0.1,
        duration = DURATION,
        pt = pt,
        form = character.form,
        tag = "-kill",
        rage = function(hand, amount, flag)
            return ww.gain(pt, hand, amount, flag)
        end,
        attackers = 2,
        switchTo = { { 5, 2 }, { 9, 1 } },
        script = function(W)
            local us, add = W.ents[1], W.ents[3] -- ents: us, mob 1, mob 2
            W.at(6, function() -- our Mortal Strike on the add: the row that counts it
                us.power = 100
                assert(W.press(us, "mortal_strike", ms))
            end)
            local function stray() -- our off-target hit: retried past an avoid until it kills
                add.health = 1
                if W.hit(us, add, 5, 1, "melee").act ~= "WOUND" then
                    W.at(W.t + 0.5, stray)
                end
            end
            W.at(12, stray)
        end,
    }, { __index = ww.WORLD })
    local W = scenarios.world(wo, seed)
    local k = setmetatable({
        usable = ww.usable(H),
        gcdSpell = H.ns.VirtualStateInternal.GCD_SPELL,
        powerType = pt,
        powerToken = character.power.token,
    }, { __index = observer.DEFAULTS })
    local obs = observer.new(W, k)
    local base = H.ctl.now + loop.GAP
    H.ctl.now = base
    H.ctl.level.target, H.ctl.level.nameplate1, H.ctl.level.nameplate2 = 60, 60, 60
    H.Fire("UNIT_AURA", "player")
    H.Fire("SPELL_UPDATE_COOLDOWN")
    H.Fire("UPDATE_SHAPESHIFT_FORM")
    local sink, counts = {}, {}
    for i = 1, (DURATION + loop.PULL) / loop.TICK do
        local t = i * loop.TICK
        W.run(t)
        loop.feed(H, obs, t, base, sink)
        assert(headless.cycle(H, base + t))
        counts[i] = { t = t, n = H.Hekili:GetNumTargets() }
    end
    return W, counts
end

describe("a kill reaches Hekili's enemy count #slow", function()
    it("drops the count within two ticks of the add's death (not at the damage grace)", function()
        local W, counts = run(1)
        local killAt = W.killAt
        assert.is_truthy(killAt, "the add never died")
        local before, dropAt
        for _, c in ipairs(counts) do
            if c.t < killAt then
                before = c.n
            elseif not dropAt and c.n == 1 then
                dropAt = c.t
            end
        end
        print(
            ("\nkill at %.2f s: count before %d, back to 1 %s after (two ticks allowed)"):format(
                killAt,
                before or -1,
                dropAt and ("%.2f s"):format(dropAt - killAt) or "never"
            )
        )
        assert.are.equal(2, before) -- both mobs counted from our rows: the drop is the kill's to make
        assert.is_truthy(dropAt and dropAt - killAt <= 2 * loop.TICK, "the dead add stayed counted")
    end)
end)
