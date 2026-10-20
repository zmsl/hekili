-- tests/Forever/spec_choice_spec.lua (per-spec plan, docs/superpowers/plans/2026-10-19-forever-specs.md): the active
-- spec on Forever, stock Hekili headless: the stored choice for the character, else the dominant talent tree (stored
-- once), else the first supported spec; a respec only hints. Review focus 1 and 2 (no talents; the choice across a
-- /reload and a respec, no loop).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local ARMS, FURY, PROT = 100011, 100012, 100013
local CHAR = "Player-Realm" -- the fake client's UnitName("player") .. "-" .. GetRealmName()
local FURY_TALENTS = { [23881] = 1, [12319] = 5 } -- Bloodthirst, Flurry

-- The harness's C_Traits answer for a talent build (tests/Game/harness/headless.lua's login shape).
local function traits(talents)
    local tr = { config = 1, trees = { 1 }, nodeIDs = {}, nodes = {}, defs = {} }
    for spell, rank in pairs(talents) do
        local n = #tr.nodeIDs + 1
        tr.nodeIDs[n], tr.nodes[n], tr.defs[n] = n, { entryIDs = { n }, activeRank = rank }, spell
    end
    return tr
end

local function boot(o)
    o = o or {}
    local c = ww.character()
    c.talents = o.talents or c.talents
    c.level = o.level or c.level
    local H = headless.new({ character = c, saved = o.saved, pack = o.pack })
    assert.are.same({}, H.loadErrors)
    return H
end

-- The event frame's real OnUpdate (Engine/Sim/Events.lua; the harness's cycle does not run it), called while a spec
-- change is pending: each call runs one pass; at most 2 passes.
local function settle(H)
    local frame
    for _, f in ipairs(H.frames) do
        local u = f.__scripts.OnUpdate
        if u and debug.getinfo(u, "S").source:find("Engine/Sim/Events.lua", 1, true) then
            frame = f
        end
    end
    assert.is_truthy(frame, "no event frame with an OnUpdate")
    for _ = 1, 2 do
        if not H.Hekili.PendingSpecializationChange then
            return
        end
        frame.__scripts.OnUpdate(frame, 0.016)
    end
    assert.is_false(H.Hekili.PendingSpecializationChange, "the spec change did not settle")
end

describe("the active spec (headless Warrior)", function()
    it("picks the dominant tree on first login and stores it", function()
        local H = boot()
        settle(H)
        assert.are.equal(ARMS, H.Hekili.State.spec.id)
        assert.are.equal(1491, H.Hekili.State.spec.clientID)
        assert.are.same({ last = 1 }, H.Hekili.DB.profile.specChoice[CHAR]) -- the tree seen, no choice made
        assert.are.equal("arms", H.Hekili.Engine.Output.status.specKey)
        assert.is_truthy(H.Hekili:GenerateProfile():find("\nspec: arms (", 1, true))
        local f = boot({ talents = FURY_TALENTS })
        settle(f)
        assert.are.equal(FURY, f.Hekili.State.spec.id)
        assert.are.same({ last = 2 }, f.Hekili.DB.profile.specChoice[CHAR])
    end)

    it("binds each built-in priority to its spec and makes it that spec's package", function()
        local H = boot()
        local p = H.Hekili.DB.profile
        assert.are.same({ ARMS, FURY, PROT }, { p.packs.Arms.spec, p.packs.Fury.spec, p.packs.Protection.spec })
        assert.are.same(
            { "Arms", "Fury", "Protection" },
            { p.specs[ARMS].package, p.specs[FURY].package, p.specs[PROT].package }
        )
    end)

    it(
        "gives a character with no talents (level 5) the first spec, stores nothing, then follows its first points",
        function()
            local H = boot({ talents = {}, level = 5 })
            settle(H)
            assert.are.equal(ARMS, H.Hekili.State.spec.id)
            assert.are.equal("default", H.Hekili.State.spec.source)
            assert.are.same({}, H.Hekili.DB.profile.specChoice[CHAR])
            assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
            assert.are.same({}, H.errors)
            H.ctl.traits = traits(FURY_TALENTS)
            H.Fire("TRAIT_CONFIG_UPDATED") -- the event Forever fires for spent points (probe session W)
            assert.is_true(H.Hekili.PendingSpecializationChange)
            settle(H)
            assert.are.equal(FURY, H.Hekili.State.spec.id)
            assert.are.same({ last = 2 }, H.Hekili.DB.profile.specChoice[CHAR])
        end
    )

    it("keeps a spec activated for a tree across a /reload and another build of that tree; no hint", function()
        local H1 = boot()
        settle(H1)
        assert.are.equal("fury", H1.Hekili:SetSpecChoice("fu").key) -- a prefix
        settle(H1)
        assert.are.equal(FURY, H1.Hekili.State.spec.id)
        assert.are.same({ [1] = "fury", last = 1 }, H1.Hekili.DB.profile.specChoice[CHAR]) -- for the Arms tree
        local H = boot({ saved = H1.env.HekiliDB }) -- Arms talents, Fury chosen for them
        settle(H)
        assert.are.equal(FURY, H.Hekili.State.spec.id)
        assert.are.equal("stored", H.Hekili.State.spec.source)
        H.ctl.traits = traits({ [12294] = 1, [12296] = 1, [12834] = 3 }) -- a respec deeper into Arms
        H.Fire("PLAYER_TALENT_UPDATE")
        settle(H)
        assert.are.equal(FURY, H.Hekili.State.spec.id)
        assert.is_nil(H.Hekili.GetSpecHint) -- the hint is gone: a swap to another tree switches instead
        assert.is_nil(H.Hekili:SetSpecChoice("nope"))
        assert.is_nil(H.Hekili:SetSpecChoice("")) -- every key is a prefix of "": ambiguous
    end)

    it("follows a dual-spec swap: Protection, Arms, Protection", function()
        local PROT_TALENTS = { [12298] = 5, [12975] = 1 } -- Shield Specialization, Last Stand
        local ARMS_TALENTS = { [12294] = 1, [12296] = 1, [12834] = 3 }
        local H = boot({ talents = PROT_TALENTS })
        settle(H)
        assert.are.equal(PROT, H.Hekili.State.spec.id)
        local seen = {}
        for _, talents in ipairs({ ARMS_TALENTS, PROT_TALENTS }) do
            H.ctl.traits = traits(talents)
            H.Fire("TRAIT_CONFIG_UPDATED")
            settle(H)
            seen[#seen + 1] = H.Hekili.State.spec.id
        end
        assert.are.same({ ARMS, PROT }, seen)
        assert.are.equal(3, H.Hekili.DB.profile.specChoice[CHAR].last)
    end)

    it("moves a legacy scalar choice onto the current dominant tree once", function()
        local saved = { profiles = { Default = { specChoice = { [CHAR] = "fury" } } } }
        local H = boot({ saved = saved }) -- Arms talents
        settle(H)
        assert.are.equal(FURY, H.Hekili.State.spec.id)
        assert.are.same({ [1] = "fury", last = 1 }, H.Hekili.DB.profile.specChoice[CHAR])
        H.ctl.traits = traits(FURY_TALENTS) -- the Fury tree: nothing chosen for it, its first spec
        H.Fire("TRAIT_CONFIG_UPDATED")
        settle(H)
        assert.are.equal(FURY, H.Hekili.State.spec.id)
        assert.are.same({ [1] = "fury", last = 2 }, H.Hekili.DB.profile.specChoice[CHAR])
    end)

    it("ends an OnUpdate pass whose early pick was on stale ranks on the settled spec (the extra pass runs)", function()
        local H = boot({ talents = {}, level = 5 })
        settle(H)
        assert.are.equal(ARMS, H.Hekili.State.spec.id)
        -- new points the talent walk has not seen yet: the pass picks on the old ranks (no points: Arms), its own walk
        -- then sees Fury, and SettleSpecChoice asks for one more pass
        H.ctl.traits = traits(FURY_TALENTS)
        H.Hekili.PendingSpecializationChange = true
        settle(H)
        assert.are.same({ last = 2 }, H.Hekili.DB.profile.specChoice[CHAR])
        assert.are.equal(FURY, H.Hekili.State.spec.id)
    end)

    it("selects the spec of the priority a harness instance asks for", function()
        local H = boot({ pack = "Protection" })
        assert.are.equal(PROT, H.Hekili.State.spec.id)
        assert.are.equal("Protection", H.Hekili.DB.profile.specs[PROT].package)
    end)
end)

describe("the spec options and /hekili spec (headless Warrior)", function()
    -- The spec nodes, then the priorities under them (RefreshOptions's order).
    local function embed(H)
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        return H.Hekili.Options.plugins.specializations
    end

    it("shows one node per spec with its own preferences, and the Activate button and the command set it", function()
        local H = boot()
        settle(H)
        local nodes = embed(H)
        assert.are.same({ 132292, 132347, 134952 }, { nodes.arms.icon, nodes.fury.icon, nodes.protection.icon })
        local prefs = function(key)
            return nodes[key].args.core.plugins.settings
        end
        assert.is_not_nil(prefs("arms").ww_min_enemies)
        assert.is_nil(prefs("arms").hs_threshold)
        assert.is_not_nil(prefs("fury").hs_threshold)
        assert.is_nil(prefs("fury").prot_cleave_rage)
        assert.is_not_nil(prefs("protection").prot_cleave_rage)
        assert.is_not_nil(prefs("protection").debuff_demoshout_enabled) -- shared by all three
        nodes.fury.args.core.args.activate.func()
        settle(H)
        assert.are.equal(FURY, H.Hekili.State.spec.id)
        assert.are.equal("fury", H.Hekili.DB.profile.specChoice[CHAR][1])
        local printed, print0 = {}, H.Hekili.Print
        H.Hekili.Print = function(_, text)
            printed[#printed + 1] = text
        end
        H.Hekili:CmdLine("spec") -- the list, then an unmatched name (the list again): no change
        H.Hekili:CmdLine("spec zzz")
        local out = table.concat(printed, "\n")
        assert.is_truthy(out:find("|cFFFFD100fury|r |cFF00FF00(current)|r", 1, true))
        assert.is_falsy(out:find("arms|r |cFF00FF00(current)", 1, true))
        assert.is_truthy(out:find("No single specialization matches 'zzz'.", 1, true))
        assert.is_falsy(out:find("favor", 1, true)) -- no talent hint
        H.Hekili.Print = print0
        assert.are.equal("fury", H.Hekili.DB.profile.specChoice[CHAR][1])
        H.Hekili:CmdLine("spec prot")
        settle(H)
        assert.are.equal(PROT, H.Hekili.State.spec.id)
    end)

    it("has no Active Specialization dropdown anywhere", function()
        local H = boot()
        settle(H)
        embed(H)
        local seen, found = {}, {}
        local function walk(t, path)
            if seen[t] then
                return
            end
            seen[t] = true
            if t.name == "Active Specialization" then
                found[#found + 1] = path
            end
            for k, v in pairs(t) do
                if k == "activeSpec" then
                    found[#found + 1] = path .. "." .. k
                end
                if type(v) == "table" then
                    walk(v, path .. "." .. tostring(k))
                end
            end
        end
        walk(H.Hekili.Options, "Options")
        assert.are.same({}, found)
    end)

    it("puts each priority under its spec's node; Priorities keeps sharing and the new-priority controls", function()
        local H = boot()
        settle(H)
        local packs = H.Hekili.DB.profile.packs
        local aaa = {} -- a custom Fury pack whose name sorts before "Arms": spec order, not name order
        for k, v in pairs(packs.Fury) do
            aaa[k] = v
        end
        aaa.builtIn, aaa.spec = false, FURY
        packs.Aaa = aaa
        local nodes = embed(H)
        local under = function(key)
            local names = {}
            for name, node in pairs(nodes[key].plugins.packs) do
                names[#names + 1] = name
                assert.are.same({ "group", "GetPackOption", "SetPackOption" }, { node.type, node.get, node.set })
            end
            table.sort(names)
            return names
        end
        assert.are.same({ "Arms", "Arms (wowsims.com)" }, under("arms"))
        assert.are.same({ "Aaa", "Fury" }, under("fury"))
        assert.are.same({ "Protection" }, under("protection"))
        local order = function(key, name)
            return nodes[key].plugins.packs[name].order
        end
        assert.is_true(order("arms", "Arms") < order("fury", "Aaa") and order("fury", "Aaa") < order("fury", "Fury"))
        local root = H.Hekili.Options.args.packs
        assert.are.same({}, root.plugins.packages)
        assert.is_nil(root.plugins.links)
        local keys = {}
        for k in pairs(root.args) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        assert.are.same({
            "createNewPack",
            "newPackHeader",
            "newPackName",
            "newPackSpec",
            "packDesc",
            "shareBtn",
            "shareHeader",
            "sharePacks",
        }, keys)
        -- a pack's own options still read its name at info[2], under the spec as under Priorities
        assert.are.equal(FURY, H.Hekili:GetPackOption({ "fury", "Aaa", "pack", "spec" }))
    end)

    it("moves a priority's node to its new spec when its Specialization changes", function()
        local H = boot()
        settle(H)
        local packs = H.Hekili.DB.profile.packs
        local aaa = {}
        for k, v in pairs(packs.Fury) do
            aaa[k] = v
        end
        aaa.builtIn, aaa.spec = false, FURY
        packs.Aaa = aaa
        local nodes = embed(H)
        assert.is_not_nil(nodes.fury.plugins.packs.Aaa)
        H.Hekili:SetPackOption({ "fury", "Aaa", "pack", "spec" }, PROT)
        assert.are.equal(PROT, packs.Aaa.spec)
        assert.is_nil(nodes.fury.plugins.packs.Aaa)
        assert.is_not_nil(nodes.protection.plugins.packs.Aaa)
        local ACD = H.env.LibStub("AceConfigDialog-3.0")
        assert.are.equal("protection\001Aaa", ACD:GetStatusTable("Hekili").groups.selected)
    end)

    it("re-wraps a replaced FeedGroup, resets its depth after an error, and golds the name unwrapped", function()
        local H = boot()
        settle(H)
        local nodes = embed(H)
        local ACD = H.env.LibStub("AceConfigDialog-3.0")
        local depth -- a newer AceConfigDialog's FeedGroup: no wrapper; records the spec node's view, then throws
        local function newer()
            depth = nodes.arms.childGroups
            error("boom")
        end
        ACD.FeedGroup = newer
        -- unwrapped: the stock view, and the active spec's name in gold in place of the tree's mark
        assert.are.equal("|cFFFFD100Arms|r", nodes.arms.name())
        assert.are.equal("Fury", nodes.fury.name())
        H.Hekili:WrapOptionsDialog() -- as the open path does
        assert.are_not.equal(newer, ACD.FeedGroup)
        local ok, err = pcall(ACD.FeedGroup, ACD, "Hekili", H.Hekili.Options, { children = {} }, nil, {})
        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("boom", 1, true))
        assert.are.equal("tree", depth) -- fed at the root: the tree's view
        assert.are.equal("tab", nodes.arms.childGroups) -- the depth reset despite the error
        assert.are.equal("|cFFFFD100Arms|r", nodes.arms.name()) -- outside a feed
    end)

    it("shows Activate on the other specs and the Active marker on the active one, and lists it first", function()
        local H = boot()
        settle(H)
        local nodes = embed(H)
        local core = function(key)
            return nodes[key].args.core.args
        end
        assert.are.same({ true, false }, { core("arms").activate.hidden(), core("arms").activeMarker.hidden() })
        assert.are.same({ false, true }, { core("fury").activate.hidden(), core("fury").activeMarker.hidden() })
        assert.are.equal("Activate Fury", core("fury").activate.name)
        assert.is_true(nodes.arms.order() < nodes.fury.order() and nodes.fury.order() < nodes.protection.order())
        core("protection").activate.func()
        settle(H)
        assert.are.equal(PROT, H.Hekili.State.spec.id)
        assert.are.same({ false, true }, { core("arms").activate.hidden(), core("arms").activeMarker.hidden() })
        assert.are.same(
            { true, false },
            { core("protection").activate.hidden(), core("protection").activeMarker.hidden() }
        )
        assert.is_true(nodes.protection.order() < nodes.arms.order() and nodes.arms.order() < nodes.fury.order())
        -- the priority row: Priority (with its magnifier) left, Activate / Active right
        assert.are.equal(1.5, core("arms").package.width + core("arms").openPackage.width)
        assert.are.same({ 1.5, 1.5 }, { core("arms").activate.width, core("arms").activeMarker.width })
        assert.is_true(core("arms").activate.order < core("arms").potion.order)
    end)

    it("ends the page with a Disable toggle that inverts the stored enabled flag", function()
        local H = boot()
        settle(H)
        local nodes = embed(H)
        local toggle = nodes.fury.args.core.args.enabled
        assert.are.equal("Disable Fury", toggle.name)
        assert.are.equal("No recommendations while this specialization is active.", toggle.desc)
        for _, o in pairs(nodes.fury.args.core.plugins.settings) do
            assert.is_true(o.order < toggle.order)
        end
        local info = { "fury", "core", "enabled" }
        assert.is_false(toggle.get(info))
        toggle.set(info, true)
        assert.is_false(H.Hekili.DB.profile.specs[FURY].enabled)
        assert.is_true(toggle.get(info))
        toggle.set(info, false)
        assert.is_true(H.Hekili.DB.profile.specs[FURY].enabled)
    end)

    it("gives a spec node tabs on its page, its priorities in the tree, and marks the active spec's row", function()
        local H = boot()
        settle(H)
        local nodes = embed(H)
        -- outside a dialog feed: the stock view
        assert.are.equal("tab", nodes.arms.childGroups)
        assert.is_false(nodes.arms.args.core.hidden())
        assert.is_false(nodes.arms.plugins.packs.Arms.hidden())
        -- the real AceConfigDialog, headless (its widgets on the harness's frames)
        local ACD = H.env.LibStub("AceConfigDialog-3.0")
        ACD:Open("Hekili")
        local tree = ACD.OpenFrames.Hekili.children[1]
        local entries, kids = {}, {}
        for _, e in ipairs(tree.tree) do
            entries[#entries + 1] = e.value
            if nodes[e.value] then
                kids[e.value] = {}
                for _, c in ipairs(e.children or {}) do
                    kids[e.value][#kids[e.value] + 1] = c.value
                end
            end
        end
        assert.are.same(
            { arms = { "Arms", "Arms (wowsims.com)" }, fury = { "Fury" }, protection = { "Protection" } },
            kids
        )
        local at = {}
        for i, v in ipairs(entries) do
            at[v] = i
        end
        assert.is_true(at.arms < at.fury and at.fury < at.protection and at.protection < at.packs)
        tree:SelectByValue("fury") -- the spec's page: its three tabs, no priority among them
        local tabs = {}
        for _, e in ipairs(tree.children[1]:GetUserData("tablist")) do
            tabs[#tabs + 1] = e.value
        end
        assert.are.same({ "core", "targets", "performance" }, tabs)
        H.Hekili:SelectPack("Fury") -- under its spec in the tree
        assert.are.equal("fury\001Fury", ACD:GetStatusTable("Hekili").groups.selected)
        tree = ACD.OpenFrames.Hekili.children[1] -- the dialog redrew on the selection
        -- the rows: plain buttons (the harness has no OptionsListButtonTemplate), drawn by a refresh that stops
        -- before laying out (no height), so only the hook places the mark
        local function region() -- the harness's frames answer IsShown false: these keep their shown state
            local r = { shown = true }
            function r.IsShown(self)
                return self.shown
            end
            function r.Show(self)
                self.shown = true
            end
            function r.Hide(self)
                self.shown = false
            end
            r.SetTexture = function() end
            r.SetAllPoints = r.SetTexture
            r.SetPoint = r.SetTexture
            function r.CreateTexture()
                local t = region()
                t.shown = false
                return t
            end
            return r
        end
        for i, v in ipairs({ "general", "arms", "fury" }) do
            tree.buttons[i] = region()
            tree.buttons[i].uniquevalue = v
        end
        tree.treeframe:SetHeight(0)
        local function marked()
            local out, made = {}, 0
            for _, button in ipairs(tree.buttons) do
                made = made + (button.hekiliActive and 1 or 0)
                if button.hekiliActive and button.hekiliActive:IsShown() then
                    out[#out + 1] = button.uniquevalue
                end
            end
            return out, made
        end
        tree:RefreshTree()
        assert.are.same({ { "arms" }, 1 }, { marked() })
        nodes.fury.args.core.args.activate.func()
        settle(H)
        tree:RefreshTree()
        assert.are.same({ { "fury" }, 2 }, { marked() }) -- one texture per button, made once
        tree:RefreshTree()
        assert.are.same({ { "fury" }, 2 }, { marked() })
    end)
end)

describe("the legacy profile and shares (headless Warrior)", function()
    local mp = assert(loadfile("tools/make_pack.lua"))("lib")

    it("migrates the pseudo-spec profile once, keeping thresholds and a custom priority", function()
        local saved = {
            profiles = {
                Default = {
                    specs = { [1491] = { package = "Mine", settings = { hs_threshold = 55, ww_min_enemies = 4 } } },
                    packs = { Mine = { spec = 1491, builtIn = false, lists = { default = {} } } },
                },
            },
        }
        local H = boot({ saved = saved })
        settle(H)
        local p = H.Hekili.DB.profile
        assert.are.same({ 55, 55, 55 }, {
            p.specs[ARMS].settings.hs_threshold,
            p.specs[FURY].settings.hs_threshold,
            p.specs[PROT].settings.hs_threshold,
        })
        assert.are.equal(4, p.specs[ARMS].settings.ww_min_enemies)
        assert.is_true(p.specs[ARMS].settings.debuff_sunder_enabled) -- a default the legacy table never saved
        assert.are.equal(0, p.specs[ARMS].abilities.mortal_strike.clash)
        assert.are.same(
            { "Mine", "Fury", "Protection" },
            { p.specs[ARMS].package, p.specs[FURY].package, p.specs[PROT].package }
        )
        assert.are.equal(ARMS, p.packs.Mine.spec)
        assert.is_true(p.specMigrated.WARRIOR)
        p.specs[ARMS].settings.ww_min_enemies = 2
        H.Hekili:SpecializationChanged()
        assert.are.equal(2, p.specs[ARMS].settings.ww_min_enemies)
        assert.are.equal(55, p.specs[1491].settings.hs_threshold)
        local H2 = boot({ saved = H.env.HekiliDB }) -- a /reload: the migration does not run again
        settle(H2)
        local p2 = H2.Hekili.DB.profile
        assert.are.equal(2, p2.specs[ARMS].settings.ww_min_enemies)
        assert.are.equal("Mine", p2.specs[ARMS].package)
        assert.is_true(p2.specMigrated.WARRIOR)
    end)

    it("exports the spec as its share key and imports keys and legacy ids as this session's spec", function()
        local H = boot()
        settle(H)
        local str = H.Hekili.SerializeActionPack("Fury")
        assert.are.equal("WARRIOR:fury", mp.decode(str).spec)
        assert.are.equal(FURY, H.Hekili.DeserializeActionPack(str).payload.spec)
        local legacy = mp.encode({ name = "Old", version = 1, spec = 1491, desc = "", simc = "", lists = {} })
        assert.are.equal(ARMS, H.Hekili.DeserializeActionPack(legacy).payload.spec)
        local other =
            mp.encode({ name = "Ret", version = 1, spec = "PALADIN:retribution", desc = "", simc = "", lists = {} })
        assert.are.equal("PALADIN:retribution", H.Hekili.DeserializeActionPack(other).payload.spec)
    end)

    it("imports a legacy pseudo-spec share on an idle healing spec as the first supported spec", function()
        local pw = require("Forever.helpers.paladin_world")
        local H = headless.new({ character = pw.Retribution.character() })
        settle(H)
        H.Hekili:SetSpecChoice("holy")
        settle(H)
        assert.are.equal(100021, H.Hekili.State.spec.id)
        local legacy = mp.encode({ name = "Old", version = 1, spec = pw.CLIENT_SPEC, desc = "", simc = "", lists = {} })
        assert.are.equal(100022, H.Hekili.DeserializeActionPack(legacy).payload.spec) -- Protection, tree 2
    end)

    it("rebinds a built-in priority stored on the legacy pseudo-spec at the current version (an upgrade)", function()
        local rw = require("Forever.helpers.rogue_world")
        local H1 = headless.new({ character = rw.Combat.character(), pack = rw.Combat.PACK })
        local saved = H1.env.HekiliDB
        saved.profiles.Default.packs[rw.Combat.PACK].spec = rw.CLIENT_SPEC -- the pack as the pseudo-spec release stored it
        local H = headless.new({ character = rw.Combat.character(), saved = saved, pack = rw.Combat.PACK })
        assert.are.same({}, H.loadErrors)
        settle(H)
        assert.are.equal(100042, H.Hekili.State.spec.id)
        assert.are.equal(100042, H.Hekili.DB.profile.packs[rw.Combat.PACK].spec)
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        assert.is_true(H.Hekili.Engine.Output.Primary.count > 0)
    end)
end)

describe("a Druid (headless)", function()
    local dw = require("Forever.helpers.druid_loop_world")
    local BALANCE, FERAL, GUARDIAN, RESTO = 100111, 100112, 100113, 100114

    it("gives Feral and Guardian their own specs on one tree, Feral by the talents and Guardian by choice", function()
        local H = headless.new({ character = dw.Feral.character(), pack = "Feral (wowsims.com)" })
        assert.are.same({}, H.loadErrors)
        settle(H)
        assert.are.equal(FERAL, H.Hekili.State.spec.id)
        local G = headless.new({ character = dw.Guardian.character(), pack = "Guardian" })
        assert.are.equal(GUARDIAN, G.Hekili.State.spec.id)
        assert.are.equal("guardian", G.Hekili.Engine.Output.status.specKey)
        local p = G.Hekili.DB.profile
        assert.are.same({ BALANCE, FERAL, GUARDIAN }, {
            p.packs["Balance (wowsims.com)"].spec,
            p.packs["Feral (wowsims.com)"].spec,
            p.packs.Guardian.spec,
        })
    end)

    it("keeps Guardian chosen on the Feral tree across a swap to Balance and back, and another Feral build", function()
        local H = headless.new({ character = dw.Feral.character(), pack = "Feral (wowsims.com)" })
        assert.are.same({}, H.loadErrors)
        local FERAL_BUILD = { [16942] = 3 } -- Sharpened Claws
        H.ctl.traits = traits(FERAL_BUILD)
        H.Fire("TRAIT_CONFIG_UPDATED")
        settle(H)
        assert.are.equal(FERAL, H.Hekili.State.spec.id)
        assert.are.equal("guardian", H.Hekili:SetSpecChoice("guardian").key)
        settle(H)
        local seen = { H.Hekili.State.spec.id }
        for _, build in ipairs({ { [16814] = 5 }, FERAL_BUILD, { [16942] = 3, [17007] = 1 } }) do
            H.ctl.traits = traits(build) -- Balance (Improved Wrath), Feral, Feral with Leader of the Pack
            H.Fire("TRAIT_CONFIG_UPDATED")
            settle(H)
            seen[#seen + 1] = H.Hekili.State.spec.id
        end
        assert.are.same({ GUARDIAN, BALANCE, GUARDIAN, GUARDIAN }, seen)
    end)

    it("leaves Restoration idle: no priority, no displays, its page the notice, no warning", function()
        local H = headless.new({ character = dw.Feral.character() })
        assert.are.same({}, H.loadErrors)
        settle(H)
        assert.is_not_nil(H.Hekili:SetSpecChoice("resto"))
        settle(H)
        assert.are.equal(RESTO, H.Hekili.State.spec.id)
        local p = H.Hekili.DB.profile
        assert.is_nil(rawget(p.specs[RESTO], "package"))
        assert.is_false(p.specs[RESTO].enabled)
        assert.is_true(H.Hekili.Class.initialized) -- the "no modules loaded" notice's guard
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        assert.are.same({}, H.errors)
        H.Hekili:EmbedSpecOptions()
        local node = H.Hekili.Options.plugins.specializations.restoration
        assert.is_not_nil(node.args.core.args.notice)
        assert.is_nil(node.args.core.args.enabled)
    end)
end)

describe("Rogue and Paladin specs (headless)", function()
    it("selects each Rogue pack's spec", function()
        local rw = require("Forever.helpers.rogue_world")
        for name, id in pairs({ Assassination = 100041, Combat = 100042, Subtlety = 100043 }) do
            local H = headless.new({ character = rw[name].character(), pack = rw[name].PACK })
            assert.are.same({}, H.loadErrors)
            assert.are.equal(id, H.Hekili.State.spec.id, name)
        end
    end)

    it("leaves a Holy paladin idle with the notice and no warning", function()
        local pw = require("Forever.helpers.paladin_world")
        local H = headless.new({ character = pw.Retribution.character() })
        assert.are.same({}, H.loadErrors)
        settle(H)
        assert.are.equal("holy", H.Hekili:SetSpecChoice("holy").key)
        settle(H)
        assert.are.equal(100021, H.Hekili.State.spec.id)
        assert.is_nil(rawget(H.Hekili.DB.profile.specs[100021], "package"))
        assert.is_false(H.Hekili.DB.profile.specs[100021].enabled)
        assert.is_true(H.Hekili.Class.initialized)
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        assert.are.same({}, H.errors)
        H.Hekili:EmbedSpecOptions()
        assert.is_not_nil(H.Hekili.Options.plugins.specializations.holy.args.core.args.notice)
        H.Hekili:EmbedPackOptions()
        local values = H.Hekili.Options.args.packs.args.newPackSpec.values -- no priority for a healing spec
        assert.is_nil(values[100021])
        assert.is_not_nil(values[100023])
        -- the new priority's spec defaults to a listed one, never the idle healing spec
        local get = H.Hekili.GetPackOption
        assert.are.equal(100022, get(H.Hekili, { "packs", "newPackSpec", "newPackSpec" }))
    end)
end)
