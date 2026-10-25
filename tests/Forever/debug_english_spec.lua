-- tests/Forever/debug_english_spec.lua (localization plan, Task 4; spec §4): debug output is English only. A snapshot
-- names the spec by its key and an aura by its key (`spell <id>` unmodelled), never by a name a translation or the
-- client gives in the player's language (fake_api's GetSpellInfo answers "Spell <id>": the client's name).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the snapshot on a non-English client (headless Arms)", function()
    local H, hk
    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        hk = H.Hekili
        hk.Engine.settings.screenshot = false -- the harness has no Screenshot()
        assert(headless.cycle(H, H.ctl.now + 0.2))
    end)

    local function snapshot()
        hk:MakeSnapshot()
        return H.ns.snapshots[#H.ns.snapshots].log
    end

    it("names a custom priority's spec by its key", function()
        hk.Engine.Registry.Specs()[ww.SPEC].name = "武器" -- the spec's name as a zhCN client's pack shows it
        hk.State.spec.name = "武器"
        hk.Engine.settings.packs[ww.PACK].builtIn = false -- a custom priority: the overview names its spec
        local log = snapshot()
        assert.is_truthy(log:find("(*arms[100011])", 1, true))
        assert.is_nil(log:find("武器", 1, true))
    end)

    it("prints each aura by its key, with no client name column", function()
        local auras = assert(snapshot():match("player_buffs:(.-)previous_spells"))
        assert.is_truthy(auras:find("battle_stance", 1, true))
        assert.is_nil(auras:find("Spell %d"))
    end)
end)
