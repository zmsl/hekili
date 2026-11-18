-- tests/Forever/detection_spec.lua: the promised detection symbols (src/Hekili/Hekili.lua). Hekili.IsForever() is true
-- whatever else is set on the object, and Hekili.Version is a release tag or a dated development version.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("Hekili.IsForever and Hekili.Version (headless Arms)", function()
    it(
        "IsForever() is true and does not follow the internal Flavor; Version is a tag or Dev-<build> (<date>)",
        function()
            local H = headless.new({ character = ww.character(), pack = ww.PACK })
            assert.are.same({}, H.loadErrors)
            local hk = H.Hekili
            assert.is_true(hk.IsForever())
            hk.Flavor = "Something else"
            assert.is_true(hk.IsForever())
            assert.is_string(hk.Version)
            assert.truthy(hk.Version:match("^v%d") or hk.Version:match("^Dev%-.+ %(%d+%)$"), hk.Version)
        end
    )
end)
