-- tests/Forever/cdm_panel_spec.lua (cdm-panel, owner 2026-11-09): the Cooldown Manager panel and its per-aura switches.
-- The profile's switch (per spec, by aura key) and a pack's `cdm = false` become def.auras[j].cdm (Tracked.lua); an
-- aura switched off maps no item in the leaf (Presence/CooldownViewer.lua), applied out of combat, at combat end
-- otherwise; the panel (Options.lua EmbedCdmOptions) lists only the items that name one pack aura, gold on a bar, grey
-- in the pool, in one grid (owner 2026-11-09). The auras are the pack's own, picked by sorted key.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the Cooldown Manager switches", function()
    local H, ctl, picked

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

    -- n auras get an entry (cooldownID 900 + i, info from `infos[i]` or { spellID }); the first `items` an item, lit
    local function layout(n, items, infos)
        picked = auras(n)
        for i, a in ipairs(picked) do
            local cd = 900 + i
            local set = ctl.viewer.sets[0]
            set[#set + 1] = cd
            local info = infos and infos[i] or {}
            info.spellID = a.id
            ctl.viewer.infos[cd] = info
            if i <= items then
                ctl.ViewerAura(ctl.ViewerItem("BuffIconCooldownViewer", i, cd), "player", a.id)
            end
        end
    end

    local function I()
        return H.ns.VirtualStateInternal
    end

    local function jOf(key)
        for j, a in ipairs(I().def.auras) do
            if a.key == key then
                return j
            end
        end
    end

    local function spec()
        local sp = H.Hekili.DB.profile.specs[H.Hekili.State.spec.id]
        sp.cdm = sp.cdm or {}
        return sp
    end

    local function covered()
        H.ns.VirtualState.Drain(ctl.now)
        local n, m = H.ns.VirtualState.Snapshot():match("presence covered=(%d+)/(%d+)")
        return { tonumber(n), tonumber(m) }
    end

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        ctl = H.ctl
    end)

    it("profile -> def flag: off, absent, the pack's default, the profile winning both ways", function()
        picked = auras(2)
        local k1, k2 = picked[1].key, picked[2].key
        assert.is_nil(I().def.auras[jOf(k1)].cdm) -- absent: on
        spec().cdm[k1] = false
        H.Hekili:CdmSwitchChanged()
        assert.are.equal(false, I().def.auras[jOf(k1)].cdm)
        spec().cdm[k1] = true
        H.Hekili:CdmSwitchChanged()
        assert.are.equal(true, I().def.auras[jOf(k1)].cdm)
        -- a pack's `cdm = false`: off until the profile says otherwise
        rawset(H.Hekili.Class.auras[k2], "cdm", false)
        H.Hekili:CdmSwitchChanged()
        assert.are.equal(false, I().def.auras[jOf(k2)].cdm)
        spec().cdm[k2] = true
        H.Hekili:CdmSwitchChanged()
        assert.are.equal(true, I().def.auras[jOf(k2)].cdm)
        -- a full build reads the same
        spec().cdm[k1] = false
        H.ns.BuildTracked()
        assert.are.equal(false, I().def.auras[jOf(k1)].cdm)
        assert.are.equal(true, I().def.auras[jOf(k2)].cdm)
    end)

    it("an aura switched off maps no item: unmapped, not tracked, no CDM fact", function()
        layout(3, 3)
        H.Fire("COOLDOWN_VIEWER_DATA_LOADED")
        assert.are.same({ 3, 3 }, covered())
        local Q, R = I().PRESENCE.viewer, I().presence
        local j1 = jOf(picked[1].key)
        assert.are.equal(j1, Q.map[901])
        assert.are.equal(I().UP, R.Presence(j1, 1))
        spec().cdm[picked[1].key] = false
        H.Hekili:CdmSwitchChanged()
        assert.are.same({ 2, 2 }, covered())
        assert.is_nil(Q.map[901])
        assert.is_false(Q.Mappable(j1))
        assert.are.equal(I().UNDECIDED, R.Presence(j1, 1))
        assert.are.equal(1, Q.Unmapped()) -- its item, on a bar, now maps to nothing
        -- the others keep their facts
        assert.are.equal(I().UP, R.Presence(jOf(picked[2].key), 1))
        spec().cdm[picked[1].key] = nil -- back on
        H.Hekili:CdmSwitchChanged()
        assert.are.same({ 3, 3 }, covered())
        assert.are.equal(j1, Q.map[901])
    end)

    it("a switch flipped in combat applies at combat end, never mid-fight", function()
        layout(2, 2)
        H.Fire("COOLDOWN_VIEWER_DATA_LOADED")
        assert.are.same({ 2, 2 }, covered())
        ctl.combat = true
        H.Fire("PLAYER_REGEN_DISABLED")
        spec().cdm[picked[1].key] = false
        H.Hekili:CdmSwitchChanged()
        assert.are.same({ 2, 2 }, covered())
        assert.are.equal(jOf(picked[1].key), I().PRESENCE.viewer.map[901])
        ctl.combat = false
        H.Fire("PLAYER_REGEN_ENABLED")
        assert.are.same({ 1, 1 }, covered())
        assert.is_nil(I().PRESENCE.viewer.map[901])
    end)

    it("an item naming an off aura and an on aura stays ambiguous (unknown candidate)", function()
        picked = auras(2)
        local cd = 950
        ctl.viewer.sets[0][1] = cd
        ctl.viewer.infos[cd] = { linkedSpellIDs = { picked[1].id, picked[2].id } }
        ctl.ViewerAura(ctl.ViewerItem("BuffIconCooldownViewer", 1, cd), "player", picked[1].id)
        H.Fire("COOLDOWN_VIEWER_DATA_LOADED")
        covered()
        assert.is_true(I().PRESENCE.viewer.map[cd] < 0)
        spec().cdm[picked[1].key] = false
        H.Hekili:CdmSwitchChanged()
        covered()
        assert.is_true(I().PRESENCE.viewer.map[cd] < 0) -- the off aura's ID is untracked now: still ambiguous
    end)

    describe("the panel", function()
        local function panel()
            H.Hekili:EmbedCdmOptions()
            return H.Hekili.Options.args.cdm.args
        end
        -- AceConfig's own validator (the vendored file behind a stub LibStub): what AceConfigDialog:Open runs on the
        -- whole options table. A key it does not know on a card ("imageWidth" on a toggle) raises and no window opens.
        local function aceValidate(options)
            local libs = {
                ["CallbackHandler-1.0"] = {
                    New = function()
                        return {}
                    end,
                },
            }
            local stub = setmetatable({
                NewLibrary = function(_, major)
                    libs[major] = {}
                    return libs[major]
                end,
            }, {
                __call = function(_, major)
                    return libs[major]
                end,
            })
            local chunk =
                assert(loadfile("src/Hekili/Libs/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua"))
            setfenv(chunk, setmetatable({ LibStub = stub }, { __index = _G }))
            chunk()
            libs["AceConfigRegistry-3.0"]:ValidateOptionsTable(options, "cdm")
        end
        -- AceConfigDialog's GetOptionsMemberValue for `hidden` and `disabled`: both are INHERITED, so a group's function
        -- also runs for each of its children, with info.option = that child. Returns { [path] = value } for every node.
        local function aceInherited(root, member)
            local out = {}
            local function walk(node, path, inherited)
                if node[member] ~= nil then
                    inherited = node[member]
                end
                if type(inherited) == "function" then
                    local info = { option = node, type = node.type, uiType = "dialog" }
                    for i = 1, #path do
                        info[i] = path[i]
                    end
                    out[table.concat(path, ".")] = inherited(info)
                else
                    out[table.concat(path, ".")] = inherited
                end
                for key, child in pairs(node.args or {}) do
                    local p = { unpack(path) }
                    p[#p + 1] = key
                    walk(child, p, inherited)
                end
            end
            walk(root, { "cdm" }, nil)
            return out
        end

        it("lists only the items that name one pack aura, gold on a bar, grey in the pool, in one grid", function()
            layout(4, 2, { { selfAura = true }, { hasAura = true, selfAura = false }, {}, { hasAura = true } })
            -- an item naming no pack aura, and one naming two: no card
            ctl.viewer.sets[1] = { 960, 961 }
            ctl.viewer.infos[960] = { spellID = 1 }
            ctl.viewer.infos[961] = { linkedSpellIDs = { picked[1].id, picked[2].id } }
            local args = panel()
            local buffs = args.items.args -- one grid whatever the item's selfAura/hasAura say (owner 2026-11-09)
            local debuffs = buffs
            assert.is_nil(args.buffs)
            assert.is_nil(args.debuffs)
            assert.are.equal("", args.items.name)
            local k = function(i)
                return picked[i].key
            end
            assert.is_table(buffs[k(1)])
            assert.is_table(debuffs[k(2)])
            assert.is_table(buffs[k(3)])
            assert.is_table(debuffs[k(4)])
            local n = 0
            for _ in pairs(buffs) do
                n = n + 1
            end
            assert.are.equal(4, n)
            assert.are.equal("toggle", buffs[k(1)].type)
            assert.truthy(buffs[k(1)].name:find("^|cffffd100")) -- on a bar
            assert.truthy(debuffs[k(2)].name:find("^|cffffd100"))
            assert.truthy(buffs[k(3)].name:find("^|cff808080")) -- in the pool only
            assert.truthy(debuffs[k(4)].name:find("^|cff808080"))
            assert.truthy(buffs[k(1)].name:find(picked[1].name, 1, true))
            assert.is_nil(buffs[k(1)].label)
            assert.are.equal("", args.state.name)
            -- (batch review Must 1) the panel with its cards passes AceConfig's validation: the options can open
            assert.has_no.errors(function()
                aceValidate(H.Hekili.Options.args.cdm)
            end)
            -- (in game 2026-11-10) opening the panel: the grid's `hidden` is inherited by each card (info.option = the
            -- card, which has no args); it must not raise, and the cards and the grid show
            local hidden
            assert.has_no.errors(function()
                hidden = aceInherited(H.Hekili.Options.args.cdm, "hidden")
            end)
            assert.is_false(hidden["cdm.items"])
            assert.is_false(hidden["cdm.items." .. k(1)])
            assert.has_no.errors(function()
                aceInherited(H.Hekili.Options.args.cdm, "disabled")
            end)

            -- the switch: default on, a write goes to the profile by key and reaches the def
            local info = { "cdm", "items", k(3) }
            assert.is_true(buffs[k(3)].get(info))
            buffs[k(3)].set(info, false)
            assert.are.equal(false, spec().cdm[k(3)])
            assert.is_false(buffs[k(3)].get(info))
            assert.are.equal(false, I().def.auras[jOf(k(3))].cdm)
            args.reset.func()
            assert.is_true(buffs[k(3)].get(info))
            assert.is_nil(I().def.auras[jOf(k(3))].cdm)
        end)

        it("in combat the cards stay and the combat note shows; off and not available say so", function()
            layout(2, 1)
            local args = panel()
            assert.is_table(args.items.args[picked[1].key])
            assert.is_true(args.combat.hidden())
            ctl.combat = true
            args = panel()
            assert.is_table(args.items.args[picked[1].key]) -- kept
            assert.is_false(args.combat.hidden())
            ctl.combat = false

            ctl.cvars.cooldownViewerEnabled = "0"
            args = panel()
            assert.truthy(args.state.name:find("Turn on the Cooldown Manager", 1, true))
            assert.is_table(args.items.args[picked[1].key]) -- the switches stay usable

            ctl.cvars.cooldownViewerEnabled = "1"
            ctl.viewer.available, ctl.viewer.failureReason = false, "Requires level 10"
            args = panel()
            assert.truthy(args.state.name:find("Requires level 10", 1, true))
            assert.is_nil(next(args.items.args))
            assert.is_true(args.items.hidden({ option = args.items }))
        end)
    end)
end)
