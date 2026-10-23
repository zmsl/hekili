-- tests/Game/Events/saturation_spec.lua (unit-registry spec §10): saturation is counted, never an error or an
-- allocation: a full ticket pool closes its oldest as overflow; the dedupe ring overwrites its oldest group; the unit
-- pool evicts only released units.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

describe("saturation", function()
    local api, ctl, ns, I, saved

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        I = ns.VirtualStateInternal
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        ns.VirtualState.Start(api)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("closes the oldest ticket as overflow when CAP + 1 commits are open, allocating nothing", function()
        for k = 1, I.Tickets.CAP + 1 do
            ctl.now = 10 + k * 0.01
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. k, fs.SPENDER_F)
        end
        assert.are.equal(1, I.Tickets.closed.overflow)
        local bytes = alloc.bytes(function(i)
            ctl.now = 20 + i * 0.01
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-x", fs.SPENDER_F)
        end, 1000)
        assert.are.equal(0, bytes)
    end)

    it("dispatches a fifth group's echo once the ring has dropped its group", function()
        local n = 0
        I.Units.OnRow(function()
            n = n + 1
        end)
        ctl.guid.nameplate1 = "Creature-1"
        ctl.now = 30
        for a = 1, 5 do
            ctl.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", a, 1)
        end
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 1, 1) -- the first group's echo: its group was overwritten
        assert.are.equal(6, n)
    end)

    it("churns 200 GUIDs through a plate without error, keeping the bound target", function()
        for k = 1, 200 do
            ctl.guid.nameplate5 = "Creature-c" .. k
            ctl.now = 40 + k
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
            ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate5")
            ctl.Tick(ctl.now + 0.2)
        end
        assert.is_true(I.Units.evicted > 0)
        assert.are.equal("Creature-1", I.Units.Bound(1))
        assert.are.equal(0, I.Events.errors)
    end)
end)
