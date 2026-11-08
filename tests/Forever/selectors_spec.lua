-- tests/Forever/selectors_spec.lua: spec/pack selectors (owner design 2026-11-08, after the Hekili classic branch's
-- RegisterPackSelector): the pure rules of src/Hekili/Engine/Schema/Selectors.lua (ns.PickSpec with the kit's ordered
-- selectors, ns.SelectPack's precedence), then the shipped selectors on the engine headless: each shipped wowsims build
-- string (tests/Forever/wowsims/<spec>.json, decoded against tests/Forever/fixtures/talent_trees) picks its own spec
-- and pack, partial builds fall back to the dominant-tree rule, and the player's own choices stay.
local headless = require("Game.harness.headless")
local json = require("dkjson")
local ex = assert(loadfile("tools/wowsims/export.lua"))()

local function load()
    local ns = {}
    assert(loadfile("src/Hekili/Engine/Schema/Trees.lua"))("Hekili", ns)
    assert(loadfile("src/Hekili/Engine/Schema/Selectors.lua"))("Hekili", ns)
    return ns
end

-- A kit as NewClass builds it ({ key, tree, unsupported } per spec), its selectors as RegisterSelector stores them.
local function kit(selectors)
    local k = { token = "TEST", trees = {}, specs = {}, selectors = selectors }
    k.talents = { a = { 1, 101, 5 }, b = { 2, 201, 5 }, c = { 3, 301, 5 }, d = { 2, 202, 1 } }
    for i, d in ipairs({ { "one", 1 }, { "two", 2 }, { "two_b", 2 }, { "heal", 3, true } }) do
        local s = { id = 100050 + i, key = d[1], name = d[1], tree = d[2], unsupported = d[3], options = {} }
        k.trees[i], k.specs[d[1]] = s, s
    end
    k.specs.two.options.package = "P1"
    return k
end
local function sel(key, spec, pack, condition)
    return { key = key, spec = spec, pack = pack, condition = condition }
end
local function ranks(r)
    return function(t)
        return r[t[2]] or 0
    end
end

describe("Selectors.lua", function()
    local T = load()

    describe("PickSpec with selectors", function()
        local K = kit({
            sel("deep_d", "two_b", "PB", function(_, tab2)
                return tab2 > 0 and talent.d.rank > 0 -- luacheck: ignore 113
            end),
            sel("tree2", "two", "P1", function(tab1, tab2, tab3)
                return tab2 > max(tab1, tab3) -- luacheck: ignore 113
            end),
        })

        it("takes the first selector whose condition is true, in registration order", function()
            local s, source, tree, picked = T.PickSpec(K, nil, ranks({ [201] = 3, [202] = 1 }), 60)
            assert.are.same({ "two_b", "selector", 2, "deep_d" }, { s.key, source, tree, picked.key })
            s, source, tree, picked = T.PickSpec(K, nil, ranks({ [201] = 3 }), 60)
            assert.are.same({ "two", "selector", 2, "tree2" }, { s.key, source, tree, picked.key })
        end)

        it(
            "lets a spec whose pack the player chose win; an older choice with no such pack yields to the selectors",
            function()
                local hand = { [100052] = { packManual = true } } -- two's pack is the player's
                local s, source, _, picked =
                    T.PickSpec(K, { [2] = "two", last = 2 }, ranks({ [201] = 3, [202] = 1 }), 60, hand)
                assert.are.same({ "two", "stored" }, { s.key, source })
                assert.is_nil(picked)
                -- the same choice from before pack-level activation (owner 2026-11-08): the selectors pick spec and pack
                s, source, _, picked = T.PickSpec(K, { [2] = "two", last = 2 }, ranks({ [201] = 3, [202] = 1 }), 60, {})
                assert.are.same({ "two_b", "selector", "deep_d" }, { s.key, source, picked.key })
                -- and with none holding, the stored spec stays the spec
                s, source = T.PickSpec(K, { [1] = "two", last = 1 }, ranks({ [101] = 5 }), 60, {})
                assert.are.same({ "two", "stored" }, { s.key, source })
            end
        )

        it(
            "holds the last settled spec with no points or a tie, unless the tree's stored spec has the player's pack",
            function()
                local held = K.specs.two_b
                local choice = { [2] = "two", last = 2 }
                local s, source = T.PickSpec(K, choice, ranks({}), 60, { [100052] = { packManual = true } }, held)
                assert.are.same({ "two", "stored" }, { s.key, source }) -- the activation wins
                s, source = T.PickSpec(K, choice, ranks({}), 60, {}, held)
                assert.are.same({ "two_b", "held" }, { s.key, source }) -- an older choice does not
                s, source = T.PickSpec(K, { last = 2 }, ranks({ [101] = 3, [201] = 3 }), 60, {}, held) -- a tie
                assert.are.same({ "two_b", "held" }, { s.key, source })
                s, source = T.PickSpec(K, choice, ranks({}), 60, {}, nil) -- no settle yet: the stored spec, as before
                assert.are.same({ "two", "stored" }, { s.key, source })
            end
        )

        it("falls back to today's rule when no selector is true", function()
            local s, source, _, picked = T.PickSpec(K, nil, ranks({ [101] = 5 }), 60)
            assert.are.same({ "one", "dominant" }, { s.key, source })
            assert.is_nil(picked)
            s, source = T.PickSpec(K, nil, ranks({}), 1)
            assert.are.same({ "one", "default" }, { s.key, source })
        end)

        it("counts a raising selector as false, counts it on the kit and keeps selecting", function()
            local k = kit({
                sel("typo", "two_b", "PB", function()
                    return talent.nope.rank > 0 -- luacheck: ignore 113
                end),
                sel("boom", "two_b", "PB", function()
                    local x
                    return x.boom
                end),
                sel("tree2", "two", "P1", function(_, tab2)
                    return tab2 > 0
                end),
            })
            local s, source, _, picked = T.PickSpec(k, nil, ranks({ [201] = 1 }), 60)
            assert.are.same({ "two", "selector", "tree2" }, { s.key, source, picked.key })
            assert.are.equal(2, k.selectorErrors)
            assert.is_truthy(tostring(k.selectorError):find("index local 'x'", 1, true))
        end)

        it("skips a selector whose spec is unsupported (a healing spec has no pack)", function()
            local k = kit({
                sel("heals", "heal", "PH", function()
                    return true
                end),
                sel("tree2", "two", "P1", function(_, tab2)
                    return tab2 > 0
                end),
            })
            local s, _, _, picked = T.PickSpec(k, nil, ranks({ [201] = 1 }), 60)
            assert.are.same({ "two", "tree2" }, { s.key, picked.key })
        end)

        it("reads the level, max and min in a condition", function()
            local k = kit({
                sel("capped", "two_b", "PB", function(tab1, tab2, tab3)
                    return level >= 60 and min(tab1, tab3) == 0 and tab2 > 0 -- luacheck: ignore 113
                end),
            })
            assert.are.equal("two_b", (T.PickSpec(k, nil, ranks({ [201] = 1 }), 60)).key)
            assert.are.equal("two", (T.PickSpec(k, nil, ranks({ [201] = 1 }), 59)).key)
        end)

        it("allocates nothing per evaluation after the first", function()
            local rank = ranks({ [201] = 3, [202] = 1 })
            T.PickSpec(K, nil, rank, 60) -- binds each condition's environment once
            collectgarbage("collect")
            collectgarbage("collect")
            collectgarbage("stop")
            local b = collectgarbage("count")
            for _ = 1, 200 do
                T.PickSpec(K, nil, rank, 60)
            end
            local d = (collectgarbage("count") - b) * 1024
            collectgarbage("restart")
            assert.are.equal(0, d)
        end)
    end)

    describe("SelectPack", function()
        local K = kit({})
        local TWO = K.specs.two
        local function packs()
            return {
                P1 = { builtIn = true, spec = TWO.id }, -- the spec's default
                P2 = { builtIn = true, spec = TWO.id },
                P3 = { builtIn = true, spec = TWO.id },
                Other = { builtIn = true, spec = K.specs.one.id },
                Mine = { spec = TWO.id }, -- a custom priority
            }
        end
        local P2, P3 = { pack = "P2" }, { pack = "P3" }

        it("replaces the default (or no choice) and marks the pack as the selector's", function()
            local sp = { package = "P1" }
            assert.is_true(T.SelectPack(sp, packs(), TWO, P2))
            assert.are.same({ package = "P2", packAuto = "P2" }, sp)
            sp = {}
            assert.is_true(T.SelectPack(sp, packs(), TWO, P2))
            assert.are.same({ package = "P2", packAuto = "P2" }, sp)
        end)

        it(
            "lets a later selector change a pack a selector set, and goes back to the default when none matches",
            function()
                local sp = { package = "P2", packAuto = "P2" }
                assert.is_true(T.SelectPack(sp, packs(), TWO, P3))
                assert.are.same({ package = "P3", packAuto = "P3" }, sp)
                assert.is_true(T.SelectPack(sp, packs(), TWO, nil))
                assert.are.same({ package = "P1" }, sp)
                assert.is_false(T.SelectPack(sp, packs(), TWO, nil))
            end
        )

        it("never replaces the player's pick: marked, or any other unmarked value (an older profile's)", function()
            local sp = { package = "P1", packManual = true }
            assert.is_false(T.SelectPack(sp, packs(), TWO, P2))
            assert.are.same({ package = "P1", packManual = true }, sp)
            sp = { package = "P3" } -- picked before markers existed
            assert.is_false(T.SelectPack(sp, packs(), TWO, P2))
            assert.is_false(T.SelectPack(sp, packs(), TWO, nil))
            assert.are.same({ package = "P3" }, sp)
            sp = { package = "(none)" }
            assert.is_false(T.SelectPack(sp, packs(), TWO, P2))
        end)

        it("never replaces a custom priority, even one named as the selector's last pick", function()
            local p = packs()
            local sp = { package = "Mine" }
            assert.is_false(T.SelectPack(sp, p, TWO, P2))
            sp = { package = "Mine", packAuto = "Mine" }
            assert.is_false(T.SelectPack(sp, p, TWO, P2))
            assert.are.equal("Mine", sp.package)
        end)

        it("writes only a built-in priority of that spec that exists", function()
            for _, target in ipairs({ { pack = "Mine" }, { pack = "Other" }, { pack = "Gone" } }) do
                local sp = { package = "P1" }
                assert.is_false(T.SelectPack(sp, packs(), TWO, target), target.pack)
                assert.are.same({ package = "P1" }, sp)
            end
            assert.is_false(T.SelectPack(nil, packs(), TWO, P2))
        end)
    end)
end)

------------------------------------------------------------------------------------------------------------------------
-- The shipped selectors, headless.

local TREES = "tests/Forever/fixtures/talent_trees"

local function slurp(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a")
    f:close()
    return s
end

--- A shipped recipe's build ({ [rank-1 spell] = rank }) from its wowsims request's talent string.
local function build(spec, class)
    local req = assert(json.decode(slurp("tests/Forever/wowsims/" .. spec .. ".json")))
    local trees = assert(json.decode(slurp(TREES .. "/" .. class .. ".json")))
    local out = {}
    for _, t in ipairs(ex.talents(req.raid.parties[1].players[1].talentsString, trees)) do
        out[t[1]] = t[2]
    end
    return out
end

-- The harness's C_Traits answer for a talent build (tests/Game/harness/headless.lua's login shape).
local function traits(talents)
    local tr = { config = 1, trees = { 1 }, nodeIDs = {}, nodes = {}, defs = {} }
    for spell, rank in pairs(talents) do
        local n = #tr.nodeIDs + 1
        tr.nodeIDs[n], tr.nodes[n], tr.defs[n] = n, { entryIDs = { n }, activeRank = rank }, spell
    end
    return tr
end

-- The event frame's real OnUpdate (Engine/Sim/Events.lua), run while a spec change is pending (as spec_choice_spec).
local function settle(H)
    local frame
    for _, f in ipairs(H.frames) do
        local u = f.__scripts.OnUpdate
        if u and debug.getinfo(u, "S").source:find("Engine/Sim/Events.lua", 1, true) then
            frame = f
        end
    end
    for _ = 1, 3 do
        if not H.Hekili.PendingSpecializationChange then
            return
        end
        frame.__scripts.OnUpdate(frame, 0.016)
    end
    assert.is_false(H.Hekili.PendingSpecializationChange, "the spec change did not settle")
end

local WORLDS = {
    druid = require("Forever.helpers.druid_loop_world").Feral,
    mage = require("Forever.helpers.mage_world").Fire,
    warlock = require("Forever.helpers.warlock_world").Affliction,
}

-- Logs in a character of `class` with `talents` (no pack forced); counts notifications.
local function boot(class, talents, saved)
    local c = WORLDS[class].character()
    c.talents = talents
    local H = headless.new({ character = c, saved = saved })
    assert.are.same({}, H.loadErrors)
    H.notes = {}
    local notify = H.Hekili.Notify
    H.Hekili.Notify = function(self, msg, ...)
        H.notes[#H.notes + 1] = msg
        return notify(self, msg, ...)
    end
    settle(H)
    H.ctl.now = H.ctl.now + 6
    H.RunTimers(H.ctl.now)
    return H
end

local function respec(H, talents)
    H.ctl.traits = traits(talents)
    H.Fire("TRAIT_CONFIG_UPDATED")
    settle(H)
    H.ctl.now = H.ctl.now + 6
    H.RunTimers(H.ctl.now)
end

local function active(H)
    local id = H.Hekili.State.spec.id
    return id, H.Hekili.DB.profile.specs[id].package
end

-- Each shipped build: its class, its spec id, the pack it must run and the selector that picks it (none: the tree's
-- rule).
local SHIPPED = {
    druid_balance = { "druid", 100111, "Balance (wowsims.com)" },
    druid_feral = { "druid", 100112, "Feral (wowsims.com)" },
    druid_guardian = { "druid", 100113, "Guardian (wowsims.com)", "guardian" },
    mage_arcane = { "mage", 100081, "Arcane (wowsims.com)" },
    mage_fire = { "mage", 100082, "Fire (wowsims.com)" },
    mage_frostfire = { "mage", 100082, "Frostfire (wowsims.com)", "frostfire" },
    warlock_affliction = { "warlock", 100091, "Affliction (wowsims.com)" },
    warlock_sm_ruin = { "warlock", 100091, "SM Ruin (wowsims.com)", "sm_ruin" },
    warlock_demonology = { "warlock", 100092, "Demonology (wowsims.com)" },
    warlock_shadow_brand = { "warlock", 100092, "Shadow Brand (wowsims.com)", "shadow_brand" },
    warlock_destruction = { "warlock", 100093, "Destruction (wowsims.com)" },
}

describe("the shipped selectors (headless)", function()
    for spec, want in pairs(SHIPPED) do
        it(spec .. "'s shipped build picks its own spec and pack", function()
            local H = boot(want[1], build(spec, want[1]))
            assert.are.same({ want[2], want[3] }, { active(H) })
            assert.are.equal(want[4] or false, H.Hekili.State.spec.selector or false) -- state.spec reads false unset
            assert.are.equal(want[4] and "selector" or "dominant", H.Hekili.State.spec.source)
            assert.are.same({}, H.errors)
            assert.is_nil(H.Hekili.Class.kit.selectorErrors)
        end)
    end

    it(
        "moves between neighbours on a respec: Feral and Guardian, Fire and Frostfire, Affliction and SM Ruin",
        function()
            for _, pair in ipairs({
                { "druid_feral", "druid_guardian", 1 }, -- to Guardian: the selector's spec switch; back: the tree's rule
                { "mage_fire", "mage_frostfire", 2 }, -- a pack switch each way (back: no selector, the default again)
                { "warlock_affliction", "warlock_sm_ruin", 2 },
                { "warlock_demonology", "warlock_shadow_brand", 2 },
            }) do
                local a, b = SHIPPED[pair[1]], SHIPPED[pair[2]]
                local H = boot(a[1], build(pair[1], a[1]))
                respec(H, build(pair[2], a[1]))
                assert.are.same({ b[2], b[3] }, { active(H) }, pair[2])
                respec(H, build(pair[1], a[1]))
                assert.are.same({ a[2], a[3] }, { active(H) }, pair[1])
                assert.are.equal(pair[3], #H.notes, pair[1]) -- one notice per automatic switch, none at login
            end
        end
    )

    it("falls back to the dominant tree's spec and default pack on partial (leveling) builds", function()
        for _, case in ipairs({
            { "druid", { [16942] = 2, [16934] = 5 }, 100112, "Feral (wowsims.com)" }, -- Sharpened Claws, Ferocity
            { "mage", { [11069] = 5, [11119] = 5 }, 100082, "Fire (wowsims.com)" }, -- Improved Fireball, Ignite
            { "warlock", { [18174] = 5, [17810] = 3 }, 100091, "Affliction (wowsims.com)" }, -- Suppression, Imp. Corr.
        }) do
            local H = boot(case[1], case[2])
            assert.are.same({ case[3], case[4] }, { active(H) }, case[1])
            assert.are.equal("dominant", H.Hekili.State.spec.source, case[1])
            assert.are.same({}, H.notes, case[1])
        end
    end)

    it("keeps the last pack and gives no notice through a read with no points (a login walk, a talent wipe)", function()
        local H = boot("mage", build("mage_frostfire", "mage"))
        local n = #H.notes -- the login's own pack change
        respec(H, {})
        assert.are.same({ 100082, "Frostfire (wowsims.com)" }, { active(H) })
        respec(H, build("mage_frostfire", "mage"))
        assert.are.same({ 100082, "Frostfire (wowsims.com)" }, { active(H) })
        assert.are.equal(n, #H.notes)
        -- a Druid whose first settle read no points: Guardian once the ranks arrive, with no switch notice
        local D = boot("druid", {})
        respec(D, build("druid_guardian", "druid"))
        assert.are.same({ 100113, "Guardian (wowsims.com)" }, { active(D) })
        respec(D, {}) -- a wipe and back: no notice either way
        respec(D, build("druid_guardian", "druid"))
        assert.are.equal(100113, (active(D)))
        assert.are.same({}, D.notes)
    end)

    it("keeps the last settled spec through a read with no points; a first login with no history does not", function()
        local H = boot("druid", build("druid_guardian", "druid"))
        assert.are.same({ 100113, "Guardian (wowsims.com)" }, { active(H) })
        respec(H, {}) -- the ranks read zero (a walk before they arrive, a wipe)
        assert.are.same({ 100113, "Guardian (wowsims.com)" }, { active(H) })
        assert.are.equal("held", H.Hekili.State.spec.source)
        respec(H, build("druid_guardian", "druid"))
        assert.are.same({ 100113, "Guardian (wowsims.com)" }, { active(H) })
        assert.are.same({}, H.notes)
        local F = boot("druid", {}) -- no settle with points yet: the first supported spec, as before
        assert.are.equal(100111, (active(F)))
        assert.are.equal("default", F.Hekili.State.spec.source)
    end)

    it("gives one notice naming the pack when a selector switches the spec and its pack together", function()
        local H = boot("warlock", build("warlock_destruction", "warlock"))
        local n = #H.notes
        -- Destruction to Affliction and SM Ruin over its default, the pass's first pick on the last walk's ranks (as
        -- spec_choice_spec's stale-ranks case): the pack changes on that pass, the spec on the next
        H.ctl.traits = traits(build("warlock_sm_ruin", "warlock"))
        H.Hekili.PendingSpecializationChange = true
        settle(H)
        H.ctl.now = H.ctl.now + 6
        H.RunTimers(H.ctl.now)
        assert.are.same({ 100091, "SM Ruin (wowsims.com)" }, { active(H) })
        assert.are.equal(n + 1, #H.notes)
        assert.is_truthy(H.notes[#H.notes]:find("SM Ruin", 1, true), H.notes[#H.notes])
    end)

    it("keeps a Feral build with a stray Thick Hide point Feral (Guardian takes all three)", function()
        local feral = build("druid_feral", "druid")
        feral[16929] = 1 -- Thick Hide 1/3
        local H = boot("druid", feral)
        assert.are.same({ 100112, "Feral (wowsims.com)" }, { active(H) })
        feral[16929] = 3
        respec(H, feral)
        assert.are.same({ 100113, "Guardian (wowsims.com)" }, { active(H) })
    end)

    it("names the selector in the snapshot's spec line", function()
        local H = boot("druid", build("druid_guardian", "druid"))
        assert.are.equal("selector", H.Hekili.State.spec.source)
        assert.is_truthy(H.Hekili:GenerateProfile():find("\nspec: guardian (selector guardian)", 1, true))
    end)

    -- A pack node's Active toggle (Options.lua's packs tree), as the player clicks it.
    local function toggleActive(H, spec, pack)
        H.Hekili:EmbedSpecOptions()
        H.Hekili:EmbedPackOptions()
        local function find(t)
            if type(t) ~= "table" then
                return nil
            end
            if t.args and t.args.toggleActive then
                return t.args.toggleActive
            end
            for _, v in pairs(t.args or {}) do
                local f = find(v)
                if f then
                    return f
                end
            end
        end
        local nodes = H.Hekili.Options.args.packs.plugins.specializations
        local node = assert(find(nodes[spec].plugins.packs[pack]), "no Active toggle for " .. pack)
        node.set()
    end

    it("lets a pack the player picked in another spec of the tree override the selector's spec and pack", function()
        local H = boot("druid", build("druid_guardian", "druid"))
        assert.are.same({ 100113, "Guardian (wowsims.com)" }, { active(H) })
        H.Hekili:EmbedSpecOptions()
        H.Hekili:SetSpecOption({ "packs", "feral", "core", "package" }, "Feral (wowsims.com)") -- Feral's page
        settle(H)
        assert.are.same({ 100112, "Feral (wowsims.com)" }, { active(H) })
        respec(H, build("druid_guardian", "druid"))
        assert.are.same({ 100112, "Feral (wowsims.com)" }, { active(H) })
        -- Activate <Spec> (and /hekili spec) is pack-level: it activates that spec's pack in place
        assert.are.equal("guardian", H.Hekili:SetSpecChoice("guardian").key)
        settle(H)
        assert.are.same({ 100113, "Guardian (wowsims.com)" }, { active(H) })
        assert.is_true(H.Hekili.DB.profile.specs[100113].packManual)
    end)

    it("takes (none) on another spec's page as that spec's pick only: the active spec stays", function()
        local H = boot("druid", build("druid_feral", "druid"))
        assert.are.equal(100112, (active(H)))
        H.Hekili:EmbedSpecOptions()
        H.Hekili:SetSpecOption({ "packs", "guardian", "core", "package" }, "(none)")
        settle(H)
        assert.are.same({ 100112, "Feral (wowsims.com)" }, { active(H) })
        local sp = H.Hekili.DB.profile.specs[100113]
        assert.are.same({ "(none)", true }, { sp.package, sp.packManual })
        assert.is_nil(H.Hekili.DB.profile.specChoice["Player-Realm"][2])
    end)

    it("leaves an automatic Frostfire alone until the player activates the Fire pack, then keeps Fire", function()
        local H = boot("mage", build("mage_fire", "mage"))
        respec(H, build("mage_frostfire", "mage")) -- the automatic Fire becomes Frostfire
        assert.are.same({ 100082, "Frostfire (wowsims.com)" }, { active(H) })
        respec(H, build("mage_frostfire", "mage")) -- no press: Frostfire stays
        assert.are.same({ 100082, "Frostfire (wowsims.com)" }, { active(H) })
        toggleActive(H, "fire", "Fire (wowsims.com)") -- the review's I1 press, on the pack
        settle(H)
        assert.are.same({ 100082, "Fire (wowsims.com)" }, { active(H) })
        respec(H, build("mage_frostfire", "mage"))
        assert.are.same({ 100082, "Fire (wowsims.com)" }, { active(H) })
    end)

    it(
        "loads an older stored spec choice: no manual pack, so the selectors apply and it stays the spec otherwise",
        function()
            local old = { profiles = { Default = { specChoice = { ["Player-Realm"] = { [2] = "feral", last = 2 } } } } }
            local H = boot("druid", build("druid_guardian", "druid"), old)
            assert.are.same({ 100113, "Guardian (wowsims.com)" }, { active(H) })
            old = { profiles = { Default = { specChoice = { ["Player-Realm"] = { [2] = "guardian", last = 2 } } } } }
            H = boot("druid", build("druid_feral", "druid"), old) -- no selector holds: the stored Guardian stays
            assert.are.same({ 100113, "Guardian (wowsims.com)" }, { active(H) })
            assert.is_nil(rawget(H.Hekili.DB.profile.specs[100113], "packManual"))
            assert.are.same({}, H.errors)
        end
    )

    it("keeps a pack the player picked in the options or by command, and a reset hands it back", function()
        local H = boot("mage", build("mage_frostfire", "mage"))
        local sp = H.Hekili.DB.profile.specs[100082]
        H.Hekili:EmbedSpecOptions()
        H.Hekili:SetSpecOption({ "packs", "fire", "core", "package" }, "Fire (wowsims.com)")
        assert.is_true(sp.packManual)
        assert.is_nil(sp.packAuto)
        respec(H, build("mage_frostfire", "mage"))
        assert.are.equal("Fire (wowsims.com)", sp.package)
        H.Hekili:HandlePriorityCommand({ "priority", "default" }) -- the default: the selector may pick again
        assert.is_nil(sp.packManual)
        respec(H, build("mage_frostfire", "mage"))
        assert.are.equal("Frostfire (wowsims.com)", sp.package)
        H.Hekili:HandlePriorityCommand({ "priority", "fire" })
        assert.is_true(sp.packManual)
        respec(H, build("mage_frostfire", "mage"))
        assert.are.equal("Fire (wowsims.com)", sp.package)
    end)

    it("leaves a custom priority alone", function()
        local H = boot("mage", build("mage_fire", "mage"))
        local p = H.Hekili.DB.profile
        local copy = {}
        for k, v in pairs(p.packs["Fire (wowsims.com)"]) do
            copy[k] = v
        end
        copy.builtIn = nil
        p.packs["My Fire"] = copy
        p.specs[100082].package = "My Fire"
        respec(H, build("mage_frostfire", "mage"))
        assert.are.equal("My Fire", p.specs[100082].package)
    end)

    it("loads an older profile unchanged: its non-default pick stays, a default is the selector's", function()
        local old = { profiles = { Default = { specs = { [100082] = { package = "Fire (wowsims.com)" } } } } }
        local H = boot("mage", build("mage_frostfire", "mage"), old) -- Fire: the default, so replaceable
        assert.are.same({ 100082, "Frostfire (wowsims.com)" }, { active(H) })
        old = { profiles = { Default = { specs = { [100091] = { package = "SM Ruin (wowsims.com)" } } } } }
        H = boot("warlock", build("warlock_affliction", "warlock"), old) -- a non-default pick: the player's
        assert.are.same({ 100091, "SM Ruin (wowsims.com)" }, { active(H) })
        assert.is_nil(rawget(H.Hekili.DB.profile.specs[100091], "packManual"))
        assert.is_nil(rawget(H.Hekili.DB.profile.specs[100091], "packAuto"))
        assert.are.same({}, H.errors)
    end)

    it("reports no activation when a spec's profile is unreadable", function()
        local H = boot("druid", build("druid_feral", "druid"))
        rawset(H.Hekili.DB.profile.specs, 100113, "broken") -- never in a real profile (Options seeds a table)
        assert.is_nil(H.Hekili:SetSpecChoice("guardian"))
        assert.is_nil(H.Hekili.DB.profile.specChoice["Player-Realm"][2])
    end)

    it("rejects a selector for a spec the class does not have", function()
        local H = boot("druid", build("druid_feral", "druid"))
        local kit = H.Hekili.Class.kit
        assert.error_matches(function()
            kit:RegisterSelector("bad", { spec = "nope", pack = "Feral (wowsims.com)" }, function()
                return true
            end)
        end, "RegisterSelector: bad's spec is not one of the class's", 1, true)
        assert.error_matches(function()
            kit:RegisterSelector("bad", { spec = "feral", pack = "Feral (wowsims.com)" }, "not a function")
        end, "RegisterSelector: bad's condition is not a function", 1, true)
        assert.are.equal(1, #kit.selectors) -- Guardian's only
    end)
end)
