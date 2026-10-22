-- tests/Game/Events/tickets_spec.lua (unit-registry spec §3): the ticket pool. Task 5's form: holding and closing;
-- Tasks 6-9 add the lifecycle, the consumption order and the kinds.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("the ticket pool", function()
    local api, ctl, ns, VS, I, T, X, saved

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        T, X = I.Tickets, I.Expect
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        VS.Start(api)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("holds 16 commits and gives the oldest way when full", function()
        for k = 1, T.CAP do
            T.Hold(X.MELEE, 1, "Creature-1", 1.5, k, 0)
        end
        local i = T.Hold(X.MELEE, 2, "Creature-1", 2.0, 100, 0)
        assert.are.same({ 100, 2, T.OPEN }, { T.at[i], T.x[i], T.state[i] })
        local open = 0
        for j = 1, T.CAP do
            open = open + (T.state[j] ~= T.FREE and 1 or 0)
        end
        assert.are.equal(T.CAP, open)
    end)

    it("frees a closed ticket for the next commit", function()
        local i = T.Hold(X.FRAME, fs.SPENDER_C, "Creature-1", 0.6, 5, 0)
        T.Close(i)
        assert.are.equal(T.FREE, T.state[i])
        assert.are.equal(i, T.Hold(X.FRAME, fs.SPENDER_C, "Creature-1", 0.6, 6, 0))
    end)
end)
