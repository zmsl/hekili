-- tests/Forever/chat_commands_spec.lua: the /hekili command table is readable (the wiki's Slash-Commands table walks it,
-- tools/wiki/collect/commands.lua), and a command reached through an alias still runs.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the /hekili command table", function()
    local H

    setup(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
    end)

    it("lists every handler and the three alias maps", function()
        local cc = H.ns.ChatCommands
        local names = {}
        for k, v in pairs(cc.handlers) do
            assert.are.equal("function", type(v), k)
            names[#names + 1] = k
        end
        table.sort(names)
        assert.are.same({
            "disable",
            "dotinfo",
            "enable",
            "fix",
            "lock",
            "move",
            "priority",
            "profile",
            "recover",
            "set",
            "skeleton",
            "snapshot",
            "spec",
            "stress",
            "unlock",
        }, names)
        assert.are.equal("snapshot", cc.aliases[1].snap)
        assert.are.equal("cooldowns", cc.aliases[2].cd)
        assert.are.equal("automatic", cc.aliases[3].auto)
    end)

    it("runs a command reached through an alias", function()
        local p = H.Hekili.DB.profile
        local before = p.toggles.cooldowns.value
        H.Hekili:CmdLine("set cds")
        assert.are.equal(not before, p.toggles.cooldowns.value)
    end)
end)
