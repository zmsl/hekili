-- tests/Forever/priest_starshards_spec.lua: the Shadow pack's `prefer_starshards` option (owner 2026-11-07: Starshards by
-- user preference replaces wowsims's spellExpectedDpet default #11). Off (the default): the pack is wowsims's with no
-- Starshards line; on, a Night Elf casts it while Mind Blast is 4 s or more from ready; never without the spell.
local loop = require("Game.harness.loop")
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.priest_world")
local ld = require("Forever.helpers.load_druid")

local PACK = "Shadow (wowsims.com)"

-- The keys anywhere in our queue over one 90 s fight; `on` sets prefer_starshards after boot.
local function shown(race, on)
    local C = ws.content(W.Shadow, {
        pack = PACK,
        level = 60,
        talents = ws.header("priest_shadow").talents,
        learn = ws.learn("PRIEST"),
        race = race,
        kit = race == "NightElf" and { "starshards" } or {},
    })
    local L = loop.new(C)
    local specs = L.us.Hekili.Engine.settings.specs
    specs[100053].settings.prefer_starshards = on -- Shadow's spec ID
    local keys = {}
    loop.run(L, 1, {
        duration = 90,
        on = function(_, steps)
            for _, name in ipairs(steps[1].q.name) do
                if name then
                    keys[name] = true
                end
            end
        end,
    }, { { H = L.us } })
    return keys
end

describe("Shadow's prefer_starshards option", function()
    it("is a toggle, off by default, with no harness default", function()
        local cls = ld.load(nil, "src/Hekili_Priest/Priest.lua", "PRIEST")
        local s = cls.settings.prefer_starshards
        assert.is_table(s)
        assert.are.same({ false, nil }, { s.default, s.option.sim })
    end)

    it("adds one Starshards line before Mind Flay, reading the option and Mind Blast's cooldown", function()
        local f = assert(io.open("src/Hekili_Priest/APLs/Shadow (wowsims.com).simc"))
        local text = f:read("*a")
        f:close()
        local line =
            "actions+=/starshards,if=settings.prefer_starshards&(!action.mind_blast.known|cooldown.mind_blast.remains>=4)"
        local a = text:find(line, 1, true)
        assert.is_truthy(a)
        assert.is_truthy(a < text:find("actions+=/mind_flay", 1, true))
    end)

    it("#slow shows Starshards only with the option on and the spell known", function()
        assert.is_nil(shown("NightElf", false).starshards)
        assert.is_true(shown("NightElf", true).starshards)
        assert.is_nil(shown("Human", true).starshards)
    end)
end)
