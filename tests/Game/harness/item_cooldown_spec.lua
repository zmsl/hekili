-- tests/Game/harness/item_cooldown_spec.lua (lane gear-1b): the replay worlds wear the request's trinkets, the fake
-- client calls them usable, and a logged use of an item with a category (the on-use trinkets) answers its cooldown and
-- holds the category's other members for the category's cooldown (never shortening a longer one), plain or secret by
-- the observer's knob, through C_Item.GetItemCooldown and C_Container.GetItemCooldown.
local replay = require("Game.harness.replay")
local observer = require("Game.harness.observer")
local drive = require("Game.harness.drive")
local fake = require("Game.State.helpers.fake_api")
local ws = require("Forever.helpers.wowsims")

local WO = { level = 60, max = 100, pt = 1, weapons = { { 100, 150, 3.6 } } }

-- Two trinkets of category 7 (windows 20 and 15 s) and a consumable without one.
local H = {
    Hekili = {
        Class = {
            abilities = {
                strike = { key = "strike", id = 900001, gcd = "spell" },
                eye = {
                    key = "eye",
                    id = -201,
                    copy = 900201,
                    item = 800201,
                    cooldown = 300,
                    category = 7,
                    categoryCooldown = 20,
                    gcd = "off",
                },
                charm = {
                    key = "charm",
                    id = -202,
                    copy = 900202,
                    item = 800202,
                    cooldown = 90,
                    category = 7,
                    categoryCooldown = 15,
                    gcd = "off",
                },
                tonic = { key = "tonic", id = -203, copy = 900203, items = { 800203 }, cooldown = 120, gcd = "off" },
            },
            auras = {},
        },
    },
}

local function log(lines)
    local out = { "# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 120 s target 63" }
    for _, l in ipairs(lines) do
        out[#out + 1] = ("[%.2f] [Tester (#1)] Casting {ItemID: %d} (Cost = 0.000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)"):format(
            l[1],
            l[2]
        )
        out[#out + 1] = ("[%.2f] [Tester (#1)] Completed cast {ItemID: %d}"):format(l[1], l[2])
    end
    return table.concat(out, "\n")
end

-- The world after the log, and its observed stream's item cooldown answers as "t item start duration" (times from
-- the pull, to 0.01 s: the replay places each line M.EPS on; 0 ready; SECRET named).
local function run(lines, k)
    local R = replay.new(log(lines), H, {})
    local W = R.world(setmetatable({ tag = "-ic" }, { __index = WO }), 1)
    W.run(R.pull + 100)
    local s = observer.observe(W, setmetatable(k or {}, { __index = observer.DEFAULTS }))
    local out = {}
    local function v(x, base)
        if rawequal(x, fake.SECRET) then
            return "SECRET"
        end
        return (type(x) == "number" and x > 0) and ("%.2f"):format(x - base) or tostring(x)
    end
    for i = 1, s.n do
        if s.ev[i] == "@itemCooldown" then
            out[#out + 1] = table.concat({ v(s.t[i], R.pull), s.a1[i], v(s.a2[i], R.pull), v(s.a3[i], 0) }, " ")
        end
    end
    return W.ents[1], R, out, s
end

describe("the harness's item cooldowns", function()
    it("wears the request's trinket slots (13, 14)", function()
        local g = ws.gear("mage_arcane")
        assert.are.same({ 22268 }, g[13])
        assert.are.same({ 13968 }, g[14])
        local c = ws.logged({
            character = function()
                return { items = { [16] = { 1 } } }
            end,
        }, "mage_arcane").character()
        assert.are.same({ [13] = { 22268 }, [14] = { 13968 }, [16] = { 1 } }, c.items)
    end)

    it("answers a use plain: the item's cooldown, the other member's window, each end ready", function()
        local us, R, got = run({ { 10, 800201 } }, { plain = true })
        assert.are.same({
            "10.00 800201 10.00 300.00",
            "10.00 800202 10.00 20.00",
            "30.00 800202 0 0",
            "310.00 800201 0 0",
        }, got)
        assert.is_true(math.abs(us.cdUntil.eye - (R.pull + 310)) < 1e-6)
        assert.is_true(math.abs(us.cdUntil.charm - (R.pull + 30)) < 1e-6) -- the truth refuses it too
    end)

    it("answers it secret while active, by the observer's knob", function()
        local _, _, got = run({ { 10, 800201 } })
        assert.are.same({
            "10.00 800201 SECRET SECRET",
            "10.00 800202 SECRET SECRET",
            "30.00 800202 nil nil",
            "310.00 800201 nil nil",
        }, got)
    end)

    it("never shortens a longer cooldown: a window over a running one is not sent, its end stays", function()
        local us, R, got = run({ { 10, 800202 }, { 40, 800201 } }, { plain = true })
        assert.are.same({
            "10.00 800202 10.00 90.00",
            "10.00 800201 10.00 15.00",
            "25.00 800201 0 0",
            "40.00 800201 40.00 300.00", -- charm's 90 s runs to 100: Eye's 20 s window (to 60) is not sent
            "100.00 800202 0 0",
            "340.00 800201 0 0",
        }, got)
        assert.is_true(math.abs(us.cdUntil.charm - (R.pull + 100)) < 1e-6)
    end)

    it("drops a pending end a longer restart supersedes", function()
        -- charm's window from Eye at 10 (to 30), then charm itself at 20 (to 110): the window's end at 30 must not fire
        local _, _, got = run({ { 10, 800201 }, { 20, 800202 } }, { plain = true })
        assert.are.same({
            "10.00 800201 10.00 300.00",
            "10.00 800202 10.00 20.00",
            "20.00 800202 20.00 90.00",
            "110.00 800202 0 0",
            "310.00 800201 0 0",
        }, got)
    end)

    it("sends no item cooldown for an item without a category (consumables read as before)", function()
        local _, _, got = run({ { 10, 800203 } }, { plain = true })
        assert.are.same({}, got)
    end)

    it("the drive puts the answer in the fake client's C_Item and C_Container reads", function()
        local api, ctl = fake.new()
        local c = {}
        drive.op(c, ctl, "@itemCooldown", 800201, 1010, 300)
        assert.are.same({ 1010, 300, 1 }, { api.C_Item.GetItemCooldown(800201) })
        assert.are.same({ 1010, 300, 1 }, { api.C_Container.GetItemCooldown(800201) })
        drive.op(c, ctl, "@itemCooldown", 800201, fake.SECRET, fake.SECRET)
        local s = api.C_Item.GetItemCooldown(800201)
        assert.is_true(rawequal(s, fake.SECRET))
        drive.op(c, ctl, "@itemCooldown", 800201, nil, nil)
        assert.are.same({ 0, 0, 1 }, { api.C_Item.GetItemCooldown(800201) })
    end)

    it("a loop press of a trinket: its use spell's cast, the item's cooldown and the hold", function()
        local world = require("Game.harness.world")
        local entities = require("Game.harness.entities")
        local loop = require("Game.harness.loop")
        local W = world.new(1)
        local us = W.add(entities.new({ guid = "Player-1", weapons = entities.weapons(22) }))
        W.t = 5
        local p = assert(loop.itemPress(H.Hekili.Class, "eye"))
        assert.is_true(W.press(us, "eye", p))
        local got = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "cast" or ev.kind == "itemCooldown" then
                got[#got + 1] = table.concat({ ev.kind, ev.spell or ev.item, ev.cd or 0 }, " ")
            end
        end
        assert.are.same({ "cast 900201 0", "itemCooldown 800201 300", "itemCooldown 800202 20" }, got)
        assert.are.same({ 305, 25 }, { us.cdUntil.eye, us.cdUntil.charm })
        assert.is_nil(loop.itemPress(H.Hekili.Class, "tonic")) -- no category: the content's own press
        W.t = 10
        assert.are.same({ false, "cooldown" }, { W.press(us, "charm", loop.itemPress(H.Hekili.Class, "charm")) })
    end)

    it("the client calls a worn trinket usable", function()
        local headless = require("Game.harness.headless")
        local Hh = headless.new({
            character = { class = "MAGE", classID = 8, level = 60, known = {}, items = { [13] = { 800201 } } },
        })
        assert.is_true(Hh.api.C_Item.IsUsableItem(800201))
        assert.is_false(Hh.api.C_Item.IsUsableItem(800202))
    end)
end)
