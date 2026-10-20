-- tests/Forever/wowsims_levels_spec.lua (wowsims packs plan, Task 4): the leveling rule. A wowsims pack line may read
-- another ability's state only behind a known guard (tools/check_pack_levels.lua), so an ability a character has not
-- learned cannot block it; checked on every "(wowsims.com)" .simc in the repository.
local levels = assert(loadfile("tools/check_pack_levels.lua"))()
local engine = require("Forever.helpers.engine")

local ABIL = { strike = true, big_hit = true, stance = true }
local function isAbility(k)
    return ABIL[k] == true
end

describe("tools/check_pack_levels.lua", function()
    it("refuses an unguarded read of another ability and accepts the translator's guards", function()
        assert.are.same(
            { "cooldown.big_hit.remains" },
            levels.unguarded("cooldown.big_hit.remains>1.5", "strike", isAbility)
        )
        assert.are.same(
            {},
            levels.unguarded("(!action.big_hit.known|cooldown.big_hit.remains>1.5)", "strike", isAbility)
        )
        assert.are.same(
            {},
            levels.unguarded("!(action.stance.known&buff.stance.up)&rage.current>10", "strike", isAbility)
        )
        assert.are.same({}, levels.unguarded("cooldown.strike.remains<1&debuff.other_aura.up", "strike", isAbility))
        assert.are.same(
            { "buff.stance.up" },
            levels.unguarded("(!action.big_hit.known|cooldown.big_hit.ready)&buff.stance.up", "strike", isAbility)
        )
        assert.are.same({}, levels.unguarded("!action.big_hit.known&rage.current>=45", "strike", isAbility))
    end)

    it("finds every wowsims pack line guarded", function()
        local pipe = assert(io.popen("ls src"))
        for addon in pipe:lines() do
            local root = "src/" .. addon .. "/APLs/"
            local ok, def = pcall(dofile, root .. "packs.lua")
            if ok and def.class then
                local abilities = engine.load(def.class).class.kit.abilities
                local function isAb(k)
                    local a = abilities[k]
                    return type(a) == "table" and a.key == k
                end
                for _, name in ipairs(def.packs) do
                    if name:find("(wowsims.com)", 1, true) then
                        assert.are.same({}, levels.file(root .. name .. ".simc", isAb), name)
                    end
                end
            end
        end
        pipe:close()
    end)
end)
