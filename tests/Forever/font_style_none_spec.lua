-- Hotfix 0.6.1: the Style dropdowns store "NONE" for None, and the client raises on it ("bad argument #3 to
-- SetFont"); the styles map it to "" (plain). The fake SetFont below rejects flags exactly as the client does.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local VALID = {
    OUTLINE = true,
    THICKOUTLINE = true,
    MONOCHROME = true,
    FILTER = true,
    FIXEDHEIGHT = true,
    NEVERCULL = true,
    SLUG = true,
}

describe("Style: None on a font", function()
    local function run(style, notify)
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local seen = {}
        local mt = getmetatable(H.CreateFrame("Frame"))
        local inner = mt.__index
        mt.__index = function(t, k)
            if k ~= "SetFont" then
                return inner(t, k)
            end
            return function(self, path, size, flags)
                if flags ~= nil and flags ~= "" then
                    for tok in flags:gmatch("[^,%s]+") do
                        if not VALID[tok] then
                            error("bad argument #3 to SetFont (supported flags: OUTLINE)", 2)
                        end
                    end
                end
                seen[#seen + 1] = flags
            end
        end
        local p = H.Hekili.DB.profile
        local c = p.displays.Primary
        c.style = style
        for _, k in ipairs({ "captions", "keybindings", "targets", "delays" }) do
            c.classic[k].fontStyle = "NONE"
            c.timeline[k] = c.timeline[k] or {}
            c.timeline[k].fontStyle = "NONE"
        end
        c.classic.keybindings.queuedFontStyle = "NONE"
        c.timeline.keybindings.queuedFontStyle = "NONE"
        c.timeline.eta.style = "NONE"
        if notify then
            p.notifications.fontStyle = "NONE"
        end
        H.Hekili:BuildUI()
        return H, seen
    end

    it("builds the displays without the notification's help (each alone fails the build on the old code)", function()
        local H, seen = run("classic", false)
        assert.are.same({}, H.errors)
        assert.is_true(#seen > 0)
    end)

    for _, style in ipairs({ "classic", "timeline" }) do
        it("builds the " .. style .. " display and the notification without error, passing plain flags", function()
            local H, seen = run(style, true)
            assert.are.same({}, H.errors)
            assert.is_true(#seen > 0)
            local plain = 0
            for _, f in ipairs(seen) do
                assert.is_true(f == "" or f == "OUTLINE", f) -- OUTLINE: the options panel's hard-coded headers
                if f == "" then
                    plain = plain + 1
                end
            end
            assert.is_true(plain >= 5, plain) -- caption, keybinding, targets, (delays | eta), notification
        end)
    end
end)
