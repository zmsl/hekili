-- tests/Forever/cdm_coverage_spec.lua (cdm-default plan Task 7, spec §6, decision 108): Cooldown Manager coverage.
-- The Performance tab's coverage line was removed (owner 2026-11-10: the Cooldown Manager panel shows the same, gold on
-- a bar, grey not); what stays is the belief's own covered=N/M in the debug snapshot (read here from its summary line,
-- test only) and the border: Options reads no belief. The auras are the pack's own, picked by sorted key.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("Cooldown Manager coverage", function()
    local H, ctl, picked

    -- the first n pack auras (sorted key) that have a spell ID of their own, each as { key, id, name }
    local function auras(n)
        local all, keys = H.Hekili.Engine.Registry.Auras(), {}
        for k, a in pairs(all) do
            if a.key == k and type(a.id) == "number" and a.id > 0 then
                keys[#keys + 1] = k
            end
        end
        table.sort(keys)
        local seen, r = {}, {}
        for _, k in ipairs(keys) do
            local id = all[k].id
            if not seen[id] and #r < n then
                seen[id] = true
                r[#r + 1] = { key = k, id = id, name = all[k].name or k }
            end
        end
        assert(#r == n, "the pack has fewer than " .. n .. " auras")
        return r
    end

    -- n auras get a Cooldown Manager entry; the first `items` of them an item (aura i in viewer (i % 4) + 1, lit)
    local function layout(n, items)
        picked = auras(n)
        local V =
            { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
        for i, a in ipairs(picked) do
            local cd = 900 + i
            local cat = i % 2 == 0 and 2 or 0
            local set = ctl.viewer.sets[cat]
            set[#set + 1] = cd
            ctl.viewer.infos[cd] = { spellID = a.id }
            if i <= items then
                local item = ctl.ViewerItem(V[(i % 4) + 1], i, cd)
                ctl.ViewerAura(item, "player", a.id)
            end
        end
        ctl.ViewerItem("BuffIconCooldownViewer", 99, nil) -- an unconfigured slot covers nothing
        ctl.ViewerChild("UtilityCooldownViewer") -- nor does a child that is not an item
    end

    -- the belief's covered=N/M after a rebuild and a drain (the map and the collect run at the rebuild)
    local function belief()
        H.Fire("COOLDOWN_VIEWER_DATA_LOADED")
        H.ns.VirtualState.Drain(ctl.now)
        local n, m = H.ns.VirtualState.Snapshot():match("presence covered=(%d+)/(%d+)")
        return tonumber(n), tonumber(m)
    end

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        ctl = H.ctl
    end)

    it("the Performance tab has no coverage line (the Cooldown Manager panel shows it)", function()
        layout(3, 1)
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        local key = H.Hekili.State.spec.key
        local args = H.Hekili.Options.args.packs.plugins.specializations[key].args.performance.args
        assert.is_table(args)
        assert.is_nil(args.cdmCoverage)
    end)

    it("the belief's covered=N/M on a plain layout", function()
        layout(6, 3)
        assert.are.same({ 3, 6 }, { belief() })
    end)

    it("the belief's covered=N/M on linked, ambiguous, secret and override entries", function()
        picked = auras(8)
        local SECRET = require("Game.State.helpers.fake_api").SECRET
        local id = function(i)
            return picked[i].id
        end
        local infos = {
            { spellID = id(1) }, -- covers 1
            { linkedSpellIDs = { id(2) } }, -- covers 2 (linked)
            { linkedSpellIDs = { id(3), id(4) } }, -- ambiguous: 3 and 4 tracked, neither covered
            { spellID = id(5), overrideSpellID = SECRET }, -- a secret candidate: 5 tracked, not covered
            { spellID = id(6) }, -- GetOverrideSpell names 7 too: 6 and 7 tracked, neither covered
            { spellID = id(8) }, -- no item: tracked, uncovered
        }
        ctl.overrides[id(6)] = id(7)
        for i, info in ipairs(infos) do
            local cd = 900 + i
            local set = ctl.viewer.sets[2]
            set[#set + 1] = cd
            ctl.viewer.infos[cd] = info
            if i < #infos then
                ctl.ViewerAura(ctl.ViewerItem("BuffIconCooldownViewer", i, cd), "player", info.spellID or id(i))
            end
        end
        assert.are.same({ 2, 8 }, { belief() })
    end)

    it("Options code reads no belief (the border: tools/check_border.sh)", function()
        local fh = assert(io.open("src/Hekili/Options/Options.lua"))
        local src = fh:read("*a")
        fh:close()
        assert.falsy(src:find("VirtualState", 1, true))
        local p = assert(io.popen("bash tools/check_border.sh"))
        local out = p:read("*a")
        p:close()
        assert.truthy(out:find("^ok: "), out)
    end)
end)
