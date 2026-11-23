-- tests/Forever/defensive_lines_spec.lua (L1805): each shipped line that reads the player's health (translator rule 23:
-- under `health.known`) fires on a low band, is silent while the health is unknown (the first prime, the capability
-- lost) and holds through a re-prime shorter than the hold bound (owner "Hold last reading"). The harness's fights
-- rarely lower our health, so the loops cannot show these lines working; this spec does, line by line.
local headless = require("Game.harness.headless")
local fake_lhv = require("Game.harness.fake_lhv")
local dlw = require("Forever.helpers.druid_loop_world")
local ww = require("Forever.helpers.warrior_world")

local F = 1 / 60

local PACKS = {
    {
        name = "Guardian (wowsims.com)",
        character = dlw.Guardian.character,
        -- sorted; (L1808) with the Healthstone and healing potion lines and the imported cat lists' Barkskin
        want = {
            "barkskin",
            "barkskin",
            "frenzied_regeneration",
            "healing_potion",
            "healing_potion",
            "healthstone",
            "healthstone",
        },
    },
    { -- Feral imports Guardian's lists for Bear Form (APLs/packs.lua `imports`): the same lines
        name = "Feral (wowsims.com)",
        character = dlw.Feral.character,
        want = {
            "barkskin",
            "barkskin",
            "frenzied_regeneration",
            "healing_potion",
            "healing_potion",
            "healthstone",
            "healthstone",
        },
    },
    {
        name = "Protection (wowsims.com)",
        character = ww.Protection.character,
        want = { "healing_potion", "healthstone", "last_stand", "shatter_curse", "shield_wall", "stoneform" },
    },
}

for _, P in ipairs(PACKS) do
    describe("the restored defensive lines of " .. P.name, function()
        local H, lhv, ids, keys

        before_each(function()
            H = headless.new({ character = P.character(), pack = P.name })
            lhv = fake_lhv.new({
                now = function()
                    return H.ctl.now
                end,
            })
            local major, minor = lhv:GetVersion()
            local stub = rawget(H.env, "LibStub")
            stub.libs[major], stub.minors[major] = lhv, minor
            H.Hekili.bandOff = false
            H.Hekili:ProvidersChanged()
            H.ctl.guid.target = "Creature-1"
            H.ctl.health, H.ctl.healthMax = 1000, 1000
            ids, keys = {}, {}
            for list, entries in pairs(H.Hekili.DB.profile.packs[P.name].lists) do
                for i, e in ipairs(entries) do
                    if (e.criteria or ""):find("health%.known") then
                        ids[#ids + 1] = P.name .. ":" .. list .. ":" .. i
                        keys[#keys + 1] = e.action
                    end
                end
            end
        end)

        local function push(hp)
            lhv:Push("health", "player", nil, hp, 1000, H.ctl.now)
        end

        -- n frames, a cycle each; then each guarded line's answer, in pack order
        local function frames(n)
            for i = 1, n do
                assert.is_true(headless.cycle(H, H.ctl.now + F), i)
            end
            H.Hekili.State.reset()
            local out = {}
            for i, id in ipairs(ids) do
                out[i] = H.Hekili.Scripts:CheckScript(id) == true
            end
            return out
        end

        local function all(v)
            local out = {}
            for i = 1, #ids do
                out[i] = v
            end
            return out
        end

        it("carries every restored line, each on the Defensives toggle", function()
            local got = { unpack(keys) }
            table.sort(got) -- the lists' order is the profile table's
            assert.are.same(P.want, got)
            for _, k in ipairs(keys) do
                assert.are.equal("defensives", H.Hekili.Class.abilities[k].toggle, k)
            end
        end)

        it("is silent while unknown, fires on a low band, holds through a short re-prime, silent once lost", function()
            push(1000)
            assert.are.same(all(false), frames(2)) -- the first prime: unknown, full
            assert.are.same(all(false), frames(12)) -- a reading, at full
            H.ctl.combat = true
            H.ctl.Fire("PLAYER_REGEN_DISABLED")
            push(200) -- 20%: under every threshold (the lowest, Frenzied Regeneration's, is < 25)
            assert.are.same(all(true), frames(3))
            lhv:Prime("player", H.ctl.now) -- about 10 frames unknown, under the 1 s bound
            for i = 1, 12 do
                assert.are.same(all(true), frames(1), i)
            end
            lhv:SetAvailable("unavailable", "error", "health") -- the health kind lost alone
            assert.are.same(all(false), frames(1))
            assert.are.same({}, H.errors)
        end)
    end)
end
