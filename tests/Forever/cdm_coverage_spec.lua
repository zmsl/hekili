-- tests/Forever/cdm_coverage_spec.lua (cdm-default plan Task 7, spec §6, decision 108): the Performance tab's Cooldown
-- Manager coverage line. Options computes it from the client API and the active spec's auras (no belief read); on the
-- same fake layout its "N of M" equals the belief's own covered=N/M (read here from the snapshot's summary line, test
-- only). The auras are the pack's own, picked by sorted key: no aura is named here.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the Cooldown Manager coverage line", function()
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

    local function line()
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        local key = H.Hekili.State.spec.key
        local args = H.Hekili.Options.args.packs.plugins.specializations[key].args.performance.args
        assert.is_table(args.cdmCoverage)
        assert.are.equal("description", args.cdmCoverage.type)
        return args.cdmCoverage.name()
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

    it("N of M equals the belief's covered on the same fake layout", function()
        layout(6, 3)
        local n, m = belief()
        assert.are.same({ 3, 6 }, { n, m })
        local text = line()
        assert.truthy(text:find("3 of 6 tracked auras have an item in a Cooldown Manager bar", 1, true), text)
    end)

    it("uncovered names listed, at most five, then 'and N more'", function()
        layout(9, 1)
        local text = line()
        assert.truthy(text:find("1 of 9", 1, true), text)
        local names = {}
        for i = 2, 9 do
            names[#names + 1] = picked[i].name
        end
        table.sort(names)
        local want = table.concat(names, ", ", 1, 5) .. " and 3 more"
        assert.truthy(text:find(want, 1, true), text)
        assert.falsy(text:find(picked[1].name .. ",", 1, true), text) -- the covered one is not listed

        H = headless.new({ character = ww.character(), pack = ww.PACK })
        ctl = H.ctl
        layout(4, 1)
        text = line()
        names = { picked[2].name, picked[3].name, picked[4].name }
        table.sort(names)
        assert.truthy(text:find(table.concat(names, ", "), 1, true), text)
        assert.falsy(text:find("more", 1, true), text)
    end)

    it("in combat the line says it updates after combat", function()
        layout(3, 1)
        ctl.combat = true
        local text = line()
        assert.truthy(text:find("updates after combat", 1, true), text)
        assert.falsy(text:find(" of 3", 1, true), text)
    end)

    it("with the Cooldown Manager off in the game options (its CVar) the line says how to turn it on", function()
        layout(3, 1)
        ctl.cvars.cooldownViewerEnabled = "0" -- the feature is available, the player turned it off
        local text = line()
        assert.truthy(text:find("Turn on the Cooldown Manager in the game options", 1, true), text)
        assert.falsy(text:find(" of 3", 1, true), text)
    end)

    it("not available to the player: the game's reason, never the turn-it-on advice", function()
        layout(3, 1)
        ctl.viewer.available, ctl.viewer.failureReason = false, "Requires level 10"
        local text = line()
        assert.truthy(text:find("Requires level 10", 1, true), text)
        assert.falsy(text:find("Turn on", 1, true), text)
        ctl.viewer.failureReason = nil -- no reason given
        text = line()
        assert.truthy(text:find("not available", 1, true), text)
        assert.falsy(text:find("Turn on", 1, true), text)
    end)

    it("linked, ambiguous, secret and override entries: the line counts only auras an item names alone", function()
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
        local n, m = belief()
        assert.are.same({ 2, 8 }, { n, m }) -- the belief's own count keeps every aura some item names
        -- (in game 2026-11-10: the Druid forms share one item, on a bar; the line told the player to add Bear Form to a
        -- bar) the line counts and lists only auras an item names alone: adding a shared item to a bar cannot help
        local text = line()
        assert.truthy(text:find("2 of 3 tracked auras", 1, true), text)
        assert.truthy(text:find(picked[8].name, 1, true), text)
        for _, i in ipairs({ 3, 4, 5, 6, 7 }) do
            assert.falsy(text:find(picked[i].name, 1, true), picked[i].name .. " | " .. text)
        end
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
