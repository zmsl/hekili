-- tests/LibHiddenValues/lazy_spec.lua: the Cooldown Manager is hooked on first use (minor 8). With no aura watch
-- nothing is hooked and no item is read, only the catalogue (at login and when an event says it changed, out of combat
-- as minor 7); the first watch hooks each thing once and gives the true answer or unknown; the getters answer with no
-- hook; an upgrade from minor 7 hooks nothing twice. The differential runs play the same scripts on the real minor 7
-- (from git, pending without it) and on this tree and judge both by the fake's world.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"
local SEVEN = "f0c7d1c" -- the last commit of minor 7
local SEEDS = tonumber(os.getenv("LHV_SEEDS")) or 40 -- scripts per differential
local FROM = tonumber(os.getenv("LHV_FROM")) or 1 -- the first seed
local MINOR -- this tree's
for line in io.lines("src/LibHiddenValues/LibHiddenValues.lua") do
    MINOR = MINOR or tonumber(line:match('^local MAJOR, MINOR = "[^"]+", (%d+)'))
end

local CATALOGUE = {
    [11] = { spellID = 5001, category = 3 },
    [12] = { spellID = 5002, category = 2 },
    [13] = { spellID = 5003, category = 2, linkedSpellIDs = { 5013 } },
    [14] = { spellID = 5004, category = 0 },
    [15] = { spellID = 5005, category = 3 },
    [17] = { spellID = 5001, category = 2 }, -- a second entry naming 5001
    [18] = { spellID = 5008, category = 1 },
}
local SPELLS = { 5001, 5002, 5003, 5004, 5005, 5008, 5013, 5017, 9999 }
local SPECS = {
    { unit = "player", spell = 5001, what = "left", edges = { 3, 6 } },
    { unit = "target", spell = 5002, what = "up" },
    { unit = "target", spell = 5002, what = "stacks", max = 4 },
    { unit = "player", spell = 5005, what = "stacks", edges = { 2, 3 } },
    { unit = "player", cooldown = 17, what = "up" },
    { unit = "target", cooldown = 14, what = "up" },
    { unit = "target", spell = 5001, what = "left", edges = { 2 } },
    { unit = "player", spell = 9999, what = "up" },
    { unit = "player", spell = 5001, what = "stacks", edges = { 2, 3 } }, -- two entries: its placement can move
    { unit = "player", spell = 5001, what = "up" },
    { unit = "player", spell = 5013, what = "stacks", edges = { 2, 3 } }, -- a linked aura
}
for i = 1, #SPECS do
    SPECS[i].kind = "aura"
end

-- The differential's world: two entries name 5001 and can hold different auras (17 shows its own 5017 before it), an
-- override that moves to a new entry, entries that come and go. The catalogue changes to copies, never in place.
local ANNOUNCE = {
    "COOLDOWN_VIEWER_DATA_LOADED",
    "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
    "COOLDOWN_VIEWER_TABLE_HOTFIXED",
    "PLAYER_LEVEL_CHANGED",
    "SPELLS_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_PVP_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_COMBAT_CONFIG_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED",
}
local PROVIDED = {} -- the events the client's data provider builds its entries again on
for _, event in ipairs(ANNOUNCE) do
    if event ~= "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" and event ~= "PLAYER_LEVEL_CHANGED" then
        PROVIDED[#PROVIDED + 1] = event
    end
end
local function worldCatalogue(v)
    local c = {
        [11] = { spellID = 5001, category = 3 },
        [12] = { spellID = 5002, category = 2 },
        [13] = { spellID = 5003, category = 2, linkedSpellIDs = { 5013 } },
        [14] = { spellID = 5004, category = 0 },
        [15] = { spellID = 5015, overrideSpellID = 5005, category = 3 },
        [17] = { spellID = 5017, category = 2, linkedSpellIDs = { 5001 } },
        [18] = { spellID = 5008, category = 1 },
    }
    if v.moved then -- the override is another entry's
        c[15] = { spellID = 5015, category = 3 }
        c[21] = { spellID = 5005, category = 3 }
    end
    if v.unlinked then -- an entry that stops naming 5001
        c[17] = { spellID = 5017, category = 2 }
    end
    if v.added then
        c[22] = { spellID = 9999, category = 2 }
    end
    if v.second then
        c[23] = { spellID = 5002, category = 3 }
    end
    return c
end

local orderOf = setmetatable({}, { __mode = "k" }) -- catalogue -> its IDs in catalogue order
local function ordered(c)
    local out = orderOf[c]
    if not out then
        out = {}
        for id in pairs(c) do
            out[#out + 1] = id
        end
        table.sort(out, function(a, b)
            if c[a].category ~= c[b].category then
                return c[a].category < c[b].category
            end
            return a < b
        end)
        orderOf[c] = out
    end
    return out
end

local function names(e, spell)
    if e.spellID == spell or e.overrideSpellID == spell or e.overrideTooltipSpellID == spell then
        return true
    end
    for _, id in ipairs(e.linkedSpellIDs or {}) do
        if id == spell then
            return true
        end
    end
    return false
end

-- The README's rule: the entry a spec answers for in this list with these items on screen, its viewer, else the reason.
local function entryOf(spec, list, at)
    local cd, k, named
    if not list then
        return nil, nil, "pending"
    end
    for _, id in ipairs(ordered(list)) do
        if id == spec.cooldown or (spec.spell and names(list[id], spec.spell)) then
            named = true
            local p = at[id]
            if p and (not k or p < k) then
                cd, k = id, p
            end
        end
    end
    if not cd then
        return nil, nil, named and "cdm-not-tracked" or "not-in-cdm"
    end
    if spec.what ~= "up" and k > 2 then
        return cd, k, "cdm-cooldown-only"
    end
    if spec.what == "left" and k == 2 then
        return cd, k, "cdm-icon-only"
    end
    return cd, k
end

-- The aura an entry's item shows on one unit, in the fake's world (it decides nothing from the library).
local function auraOf(e, auras)
    if not e then
        return nil
    end
    local a = auras[e.spellID] or auras[e.overrideSpellID or 0] or auras[e.overrideTooltipSpellID or 0]
    for _, id in ipairs(e.linkedSpellIDs or {}) do
        a = a or auras[id]
    end
    return a
end

-- Whether a band holds what the world held in one snapshot (n nil: no aura; left: its seconds then).
local function fits(what, lo, hi, snap)
    local v = snap.n or 0
    if what == "up" then
        v = snap.n and 1 or 0
        return lo == v and hi == v
    elseif what == "left" then
        v = snap.left
        return v >= lo - 0.05 and (v < hi + 0.05 or hi == math.huge)
    end
    return v >= lo and (v < hi or hi == math.huge or lo == hi)
end

local sevenFiles -- { { path, source }, ... } in TOC order; false: git has no such commit
local function sevenSource()
    if sevenFiles ~= nil then
        return sevenFiles
    end
    local function show(path)
        local p = io.popen("git show " .. SEVEN .. ":src/LibHiddenValues/" .. path .. " 2>/dev/null")
        local s = p:read("*a")
        p:close()
        return s
    end
    sevenFiles = false
    local toc, files = show("LibHiddenValues.toc"), {}
    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^#") then
            local path = line:gsub("\\", "/")
            files[#files + 1] = { path, show(path) }
        end
    end
    if #files > 0 then
        sevenFiles = files
    end
    return sevenFiles
end

describe("LibHiddenValues Cooldown Manager hooks on first use", function()
    local Fake, W, lib, seen, twice

    local function loadSeven(minor)
        for _, f in ipairs(sevenSource()) do
            local src = f[2]
            if minor then
                src = src:gsub('"LibHiddenValues%-1%.0", %d+', '"LibHiddenValues-1.0", ' .. minor)
            end
            assert(loadstring(src, "@" .. f[1]))()
        end
    end

    -- A fresh client running this tree, or minor 7 (old). Counts the item reads (pool
    -- enumerations), the catalogue reads and the hooks put twice on one method of one object.
    local function boot(old, setup)
        if Fake then
            Fake.restore()
        end
        Fake = loadfile(FAKE)({ noLoad = true })
        seen, twice = { items = 0, catalogue = 0 }, 0
        local hook, once = _G.hooksecurefunc, {}
        rawset(_G, "hooksecurefunc", function(t, k, fn)
            once[t] = once[t] or {}
            twice = twice + (once[t][k] and 1 or 0)
            once[t][k] = true
            return hook(t, k, fn)
        end)
        for _, v in ipairs(Fake.viewers) do
            local base = v.itemFramePool.EnumerateActive
            v.itemFramePool.EnumerateActive = function(pool)
                seen.items = seen.items + 1
                return base(pool)
            end
        end
        local cv = _G.C_CooldownViewer
        local set = cv.GetCooldownViewerCategorySet
        cv.GetCooldownViewerCategorySet = function(cat, ...)
            if cat == 0 then -- a read asks every category once
                seen.catalogue = seen.catalogue + 1
            end
            return set(cat, ...)
        end
        if old then
            loadSeven()
        else
            Fake.loadLibrary()
        end
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        W.cdm.catalogue = CATALOGUE
        W.cdm.bar, W.cdm.icon = { 11, 15 }, { 12, 13 }
        W.cdm.essential, W.cdm.utility = { 14 }, { 18 }
        W.unit.target = { health = 0.7 }
        if setup then
            setup()
        end
    end

    local function untouched()
        assert.are.equal(0, Fake.hooks, "hooks")
        assert.are.equal(0, seen.items, "item reads")
        assert.are.equal(0, select(7, lib:GetAuraSources()), "scans")
    end

    -- Every change the Cooldown Manager and the client announce.
    local function churn(step)
        local steps = {
            Fake.cdmLayout,
            function()
                W.cdm.bar = { 15, 11, 16 }
                Fake.cdmLayout()
            end,
            Fake.cdmData,
            function()
                Fake.event("COOLDOWN_VIEWER_DATA_LOADED")
            end,
            function()
                Fake.event("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
            end,
            function()
                Fake.event("COOLDOWN_VIEWER_TABLE_HOTFIXED")
            end,
            function()
                Fake.event("PLAYER_LEVEL_CHANGED")
            end,
            function()
                Fake.event("LOADING_SCREEN_DISABLED")
            end,
            function()
                Fake.setAura("player", 5001, 2, 10)
            end,
            function()
                W.combat = true
                W.aura.target = { [5002] = { stacks = 3, duration = 60, expires = GetTime() + 60 } }
                Fake.event("PLAYER_TARGET_CHANGED")
            end,
            function()
                Fake.event("UNIT_AURA", "target")
            end,
            Fake.cdmLayout,
            function()
                W.combat = false
                Fake.event("PLAYER_REGEN_ENABLED")
            end,
            function()
                Fake.cdmEnable(false)
            end,
            function()
                Fake.cdmEnable(true)
            end,
        }
        for i = 1, #steps do
            steps[i]()
            Fake.tick(3)
            step()
        end
    end

    after_each(function()
        assert.are.same({}, Fake and Fake.touched or {})
        if Fake then
            Fake.restore()
            Fake = nil
        end
    end)

    describe("1: no aura watch", function()
        it("hooks nothing and reads no item, at login and through every announced change", function()
            boot()
            assert.is_true(Fake.login())
            untouched()
            assert.are.equal(1, seen.catalogue)
            assert.is_true((select(3, lib:GetAuraSources()))) -- known, with no getter called
            churn(untouched)
            assert.are.equal(5, seen.catalogue) -- the churn's four catalogue events
            assert.are.same({}, Fake.errors)
        end)

        -- The client's own data provider builds the catalogue again on the last eight (its source, build 71037).
        for _, event in ipairs({
            "COOLDOWN_VIEWER_DATA_LOADED",
            "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
            "COOLDOWN_VIEWER_TABLE_HOTFIXED",
            "PLAYER_LEVEL_CHANGED",
            "SPELLS_CHANGED",
            "PLAYER_EQUIPMENT_CHANGED",
            "PLAYER_PVP_TALENT_UPDATE",
            "TRAIT_CONFIG_UPDATED",
            "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
            "ACTIVE_COMBAT_CONFIG_CHANGED",
            "ACTIVE_TALENT_GROUP_CHANGED",
        }) do
            it("reads the catalogue again on " .. event .. ", in combat once when combat ends", function()
                boot()
                Fake.login()
                Fake.event(event)
                Fake.tick(2)
                assert.are.equal(2, seen.catalogue)
                W.combat = true
                for _ = 1, 3 do
                    Fake.event(event)
                    Fake.tick(2)
                end
                assert.are.equal(2, seen.catalogue) -- not readable now
                W.combat = false
                Fake.event("PLAYER_REGEN_ENABLED")
                Fake.tick(2)
                assert.are.equal(3, seen.catalogue)
                W.combat = true
                Fake.tick(2)
                W.combat = false
                Fake.event("PLAYER_REGEN_ENABLED")
                Fake.tick(2)
                assert.are.equal(3, seen.catalogue) -- nothing left to read
                untouched()
            end)
        end

        it("reads no catalogue over 10 pulls with no catalogue event", function()
            boot()
            lib:Watch("A", { kind = "health", unit = "target", step = 1 })
            Fake.login()
            assert.are.equal(1, seen.catalogue)
            for i = 1, 10 do
                W.combat = true
                Fake.event("PLAYER_TARGET_CHANGED")
                Fake.setAura("player", 5001, i, 30)
                Fake.setAura("target", 5002, i, 30)
                Fake.cdmLayout()
                Fake.cdmData()
                Fake.tick(30)
                W.combat = false
                Fake.event("PLAYER_REGEN_ENABLED")
                Fake.tick(30)
            end
            assert.are.equal(1, seen.catalogue)
            untouched()
        end)

        it("reads what it could not with the Cooldown Manager off once it is on", function()
            boot(false, function()
                W.cdm.enabled = false
            end)
            Fake.login()
            assert.are.equal(0, seen.catalogue)
            Fake.cdmEnable(true)
            Fake.tick(2)
            assert.are.equal(1, seen.catalogue)
            Fake.cdmEnable(false)
            Fake.event("COOLDOWN_VIEWER_DATA_LOADED")
            Fake.tick(2)
            assert.are.equal(1, seen.catalogue)
            Fake.cdmEnable(true)
            Fake.tick(2)
            assert.are.equal(2, seen.catalogue)
            untouched()
        end)

        it("a first watch made while it is off never says cdm-not-tracked once it is on with secret IDs", function()
            boot()
            Fake.setAura("player", 5001, 2, 30)
            W.cdm.secretId = true
            Fake.login()
            Fake.tick(80)
            W.cdm.bar, W.cdm.icon, W.cdm.essential, W.cdm.utility = {}, {}, {}, {}
            Fake.cdmLayout() -- no item on screen
            Fake.cdmEnable(false)
            Fake.tick(14)
            W.combat = true
            local w = lib:Watch("A", SPECS[4])
            Fake.tick(10)
            W.cdm.bar, W.cdm.icon, W.cdm.essential, W.cdm.utility = { 11, 15 }, { 12, 13 }, { 14 }, { 18 }
            Fake.cdmEnable(true)
            Fake.cdmData()
            for _ = 1, 30 do
                Fake.tick(1)
                local _, reason = w:State()
                assert.is_not.equal("cdm-not-tracked", reason)
            end
        end)

        it("hooks nothing with health and power watches", function()
            boot()
            lib:Watch("A", { kind = "health", unit = "target", step = 1 })
            lib:Watch("A", { kind = "health", unit = "player", edges = { 50 } })
            lib:Watch("A", { kind = "power", unit = "player", power = 0, points = { 300, 500 } })
            assert.is_true(Fake.login())
            untouched()
            churn(untouched)
            assert.are.same({}, Fake.errors)
        end)

        it("hooks nothing for a refused or unproven aura watch", function()
            boot()
            Fake.login()
            assert.is_nil(lib:Watch("A", { kind = "aura", unit = "player", what = "up" }))
            local h = lib:Watch("A", { kind = "aura", unit = "focus", spell = 5001, what = "up" })
            assert.are.same({ "unavailable", "unproven" }, { h:State() })
            assert.are.same(
                { false, "unavailable", "unproven" },
                { lib:IsAvailable("aura", { unit = "focus", spell = 5001, what = "up" }) }
            )
            Fake.tick(3)
            untouched()
        end)

        it("still tells the kind's own answer: cdm-off, also with the viewers missing", function()
            boot()
            local told = {}
            lib:OnCapability("A", function(kind, state, reason)
                if kind == "aura" then
                    told[#told + 1] = state .. ":" .. tostring(reason)
                end
            end)
            Fake.login()
            told = {}
            Fake.cdmEnable(false)
            Fake.tick(1)
            assert.are.same({ false, "unavailable", "cdm-off" }, { lib:IsAvailable("aura") })
            Fake.cdmEnable(true)
            Fake.tick(1)
            assert.are.same({ true, "ready" }, { lib:IsAvailable("aura") })
            assert.are.same({ "unavailable:cdm-off", "ready:nil" }, told)
            untouched()
            boot(false, function()
                for _, n in ipairs({ "BuffBar", "BuffIcon", "Essential", "Utility" }) do
                    rawset(_G, n .. "CooldownViewer", nil)
                end
            end)
            Fake.login()
            assert.are.same({ kind = "aura", state = "unavailable", reason = "cdm-off" }, lib:GetKinds()[9])
            untouched()
        end)

        it("allocates nothing per steady frame", function()
            boot()
            lib:Watch("A", { kind = "health", unit = "target", step = 1 })
            Fake.login()
            Fake.tick(120)
            local reads = seen.catalogue
            collectgarbage("collect")
            collectgarbage("stop")
            local before = collectgarbage("count")
            Fake.tick(1000)
            W.combat = true
            Fake.tick(1000)
            local grown = collectgarbage("count") - before
            collectgarbage("restart")
            assert.is_true(grown < 1, "KB grown: " .. grown)
            assert.are.equal(reads, seen.catalogue)
            untouched()
        end)
    end)

    describe("2: the first watch", function()
        it("installs each hook once, the items on screen included, and reads a new item after it", function()
            boot()
            Fake.setAura("player", 5001, 2, 30)
            Fake.login()
            untouched()
            local h = assert(lib:Watch("A", SPECS[1]))
            assert.are.equal("priming", (h:State())) -- answered inside Watch
            -- 4 viewers x 2, 2 bar items x 2, 2 icon items x 2 (the count and MarkDirty)
            assert.are.equal(16, Fake.hooks)
            assert.are.equal(0, twice)
            Fake.tick(20)
            assert.are.same({ 6, math.huge }, { h.lo, h.hi })
            lib:Watch("B", SPECS[2])
            Fake.cdmLayout()
            Fake.tick(3)
            assert.are.equal(16, Fake.hooks)
            W.cdm.bar = { 11, 15, 16 }
            Fake.cdmLayout()
            assert.are.equal(18, Fake.hooks) -- the third bar item, as it was acquired
            W.cdm.icon = { 12, 13, 17 }
            Fake.cdmLayout()
            assert.are.equal(20, Fake.hooks) -- the third icon item's
            assert.are.equal(0, twice)
            assert.are.same({}, Fake.errors)
        end)

        it("made before login installs nothing before the first frame", function()
            boot()
            lib:Watch("A", SPECS[2])
            assert.are.equal(0, Fake.hooks)
            Fake.login()
            assert.are.equal(16, Fake.hooks)
        end)

        it("never calls a capability callback from inside itself", function()
            boot()
            local told = 0
            Fake.login()
            lib:OnCapability("A", function()
                told = told + 1
            end)
            lib:Watch("A", SPECS[1])
            lib:Watch("A", SPECS[8])
            assert.are.equal(0, told)
            assert.are.equal(16, Fake.hooks)
        end)

        it("in combat, the first of the session: answered as by minor 7, in the same frames", function()
            if not sevenSource() then
                pending("no minor 7 in this clone (git show " .. SEVEN .. ")")
                return
            end
            local function run(old)
                boot(old)
                Fake.setAura("player", 5001, 2, 30)
                Fake.setAura("target", 5002, 2, 30)
                Fake.login()
                W.combat = true
                Fake.tick(5)
                local reads = seen.catalogue -- none in combat, as minor 7
                local hs, out = {}, {}
                for k = 1, #SPECS do
                    hs[k] = lib:Watch("A", SPECS[k])
                    out[#out + 1] = { hs[k]:State() }
                end
                assert.are.equal(old and 14 or 16, Fake.hooks) -- installed at once: hooks and item reads work in combat
                for _ = 1, 40 do
                    Fake.tick(1)
                    for k = 1, #hs do
                        out[#out + 1] = { hs[k]:Get() }
                        out[#out + 1] = { hs[k]:State() }
                    end
                end
                assert.are.equal(reads, seen.catalogue)
                return out, hs
            end
            local seven = run(true)
            local this, hs = run(false)
            assert.are.same(seven, this)
            assert.are.equal(6, (hs[1]:Get()))
            assert.are.equal(1, (hs[2]:Get()))
            assert.are.equal(0, twice)
        end)

        it("after a login in combat: pending, never a 0, until combat ends", function()
            boot(false, function()
                W.combat = true
            end)
            Fake.setAura("player", 5001, 2, 30)
            Fake.setAura("target", 5002, 2, 30)
            Fake.login()
            local calls = {}
            local function sink(_, lo)
                calls[#calls + 1] = lo
            end
            local left, up = lib:Watch("A", SPECS[1], sink), lib:Watch("A", SPECS[2], sink)
            for _ = 1, 120 do
                Fake.tick(1)
                assert.are.equal("pending", (left:State()))
                assert.are.equal("pending", (up:State()))
                assert.is_nil((left:Get()))
                assert.is_nil((up:Get()))
            end
            assert.are.same({}, calls)
            assert.are.equal(16, Fake.hooks)
            assert.are.equal(0, seen.catalogue) -- none in combat
            W.combat = false
            Fake.event("PLAYER_REGEN_ENABLED")
            Fake.tick(20)
            assert.are.equal(6, (left:Get()))
            assert.are.equal(1, (up:Get()))
            assert.are.equal(0, twice)
        end)

        it("in combat, an item's identity secret: pending, not cdm-not-tracked", function()
            boot()
            Fake.setAura("player", 5001, 2, 30)
            Fake.login()
            W.combat, W.cdm.secretId = true, true
            Fake.cdmData() -- a data pass in combat writes each cooldownID secret
            Fake.tick(2)
            assert.are.same({ false, "pending" }, { lib:IsAvailable("aura", SPECS[1]) })
            assert.are.same({ false, "unavailable", "not-in-cdm" }, { lib:IsAvailable("aura", SPECS[8]) })
            assert.are.equal(0, Fake.hooks)
            local left, gone = lib:Watch("A", SPECS[1]), lib:Watch("A", SPECS[5])
            for _ = 1, 30 do
                Fake.tick(1)
                assert.are.equal("pending", (left:State()))
                assert.is_nil((left:Get()))
                assert.is_nil((gone:Get()))
            end
            W.combat, W.cdm.secretId = false, false
            Fake.event("PLAYER_REGEN_ENABLED")
            Fake.cdmLayout()
            Fake.tick(20)
            assert.are.equal(6, (left:Get()))
            assert.are.same({ "unavailable", "cdm-not-tracked" }, { gone:State() })
        end)
    end)

    describe("3: the getters with no watch", function()
        local left = { kind = "aura", unit = "player", spell = 5005, what = "left", edges = { 3 } }

        it("answer from a read with no hook, following the layout", function()
            boot()
            Fake.login()
            assert.are.same({ true, "ready" }, { lib:IsAvailable("aura", left) })
            assert.are.equal("bar", lib:GetAuraEntries(5005)[1].placement)
            W.cdm.bar, W.cdm.icon = { 11 }, { 12, 15 }
            Fake.cdmLayout()
            Fake.tick(1)
            assert.are.same({ false, "unavailable", "cdm-icon-only" }, { lib:IsAvailable("aura", left) })
            assert.are.equal("icon", lib:GetAuraEntries(5005)[1].placement)
            assert.are.same({ false, "unavailable", "not-in-cdm" }, { lib:IsAvailable("aura", SPECS[8]) })
            W.combat = true
            assert.are.same({ false, "unavailable", "cdm-icon-only" }, { lib:IsAvailable("aura", left) })
            assert.are.equal(0, Fake.hooks)
        end)

        it("follow a catalogue change announced by its event", function()
            local c = {}
            for id, e in pairs(CATALOGUE) do
                c[id] = e
            end
            boot(false, function()
                W.cdm.catalogue = c
            end)
            Fake.login()
            assert.are.equal(0, #lib:GetAuraEntries(5006))
            c[16] = { spellID = 5006, category = 3 }
            Fake.event("COOLDOWN_VIEWER_DATA_LOADED")
            Fake.tick(1)
            assert.are.equal(1, #lib:GetAuraEntries(5006))
            assert.are.equal(0, Fake.hooks)
        end)

        it("answer at a first call in combat", function()
            boot()
            Fake.login()
            W.combat = true
            assert.are.same({ true, "ready" }, { lib:IsAvailable("aura", left) })
            local list, read = lib:GetAuraEntries(5005)
            assert.is_true(read)
            assert.are.equal("bar", list[1].placement)
            assert.are.equal(1, seen.catalogue) -- login's
            assert.are.equal(0, Fake.hooks)
        end)

        it("say not read after a login in combat", function()
            boot(false, function()
                W.combat = true
            end)
            Fake.login()
            assert.are.same({ false, "pending" }, { lib:IsAvailable("aura", left) })
            assert.are.same({ {}, false }, { lib:GetAuraEntries(5005) })
            assert.are.equal(0, seen.catalogue)
            assert.are.equal(0, Fake.hooks)
        end)

        it("report a read that fails on the next frame, not from inside the getter", function()
            boot()
            Fake.login()
            local told = {}
            lib:OnCapability("A", function(kind, state, reason)
                if kind == "aura" then
                    told[#told + 1] = state .. ":" .. tostring(reason)
                end
            end)
            Fake.viewers[1].itemFramePool.EnumerateActive = function()
                error("refused")
            end
            assert.is_nil(lib:GetAuraEntries(5005)[1].placement)
            assert.are.same({}, told)
            assert.are.same({}, Fake.errors)
            Fake.tick(1)
            assert.are.same({ "unavailable:error" }, told)
            assert.are.equal(1, #Fake.errors)
        end)
    end)

    -- A change of the catalogue's content, the IDs placed on the Tracked Bars, and the aura then on the player.
    local function world(catalogue, bar, icon)
        boot(false, function()
            W.cdm.catalogue, W.cdm.bar, W.cdm.icon = catalogue, bar, icon or {}
            W.cdm.essential, W.cdm.utility = {}, {}
        end)
    end

    local function aura(spell, stacks, unit)
        W.aura[unit or "player"][spell] = { stacks = stacks, duration = 90, expires = GetTime() + 90 }
    end

    -- Each frame of n: a band, if known, holds v (stacks or up). Returns the last band's lo.
    local function never(h, n, v)
        local lo, hi
        for f = 1, n do
            Fake.tick(1)
            lo, hi = h:Get()
            if lo ~= nil then
                local ok = v >= lo and (v < hi or hi == math.huge or lo == hi and v >= lo)
                if h.what == "up" then
                    ok = lo == v and hi == v
                end
                assert.is_true(ok, ("frame %d: %s-%s, true %d"):format(f, tostring(lo), tostring(hi), v))
            end
        end
        return lo
    end

    describe("an inactive source's presence is not kept", function()
        local UP = { kind = "aura", unit = "player", spell = 5001, what = "up" }
        local ST = { kind = "aura", unit = "player", spell = 5001, what = "stacks", edges = { 2, 3 } }
        local paths = {
            ["released and watched again"] = function(h, spec, change)
                h:Release()
                Fake.tick(3)
                change()
                Fake.tick(5)
                return lib:Watch("A", spec)
            end,
            ["released and watched again in combat"] = function(h, spec, change)
                h:Release()
                W.combat = true
                change()
                Fake.tick(5)
                return lib:Watch("A", spec)
            end,
            ["released and watched again after the driver slept"] = function(h, spec, change)
                h:Release()
                Fake.tick(300)
                change()
                Fake.tick(300)
                return lib:Watch("A", spec)
            end,
            ["not tracked, then tracked"] = function(h, spec, change)
                W.cdm.bar = {}
                Fake.cdmLayout()
                Fake.tick(5)
                change()
                Fake.tick(5)
                W.cdm.bar = { 11 }
                Fake.cdmLayout()
                return h
            end,
            ["the Cooldown Manager off, then on"] = function(h, spec, change)
                Fake.cdmEnable(false)
                Fake.tick(5)
                change()
                Fake.tick(5)
                Fake.cdmEnable(true)
                return h
            end,
            ["switched off, then on"] = function(h, spec, change)
                lib:SetEnabled(false)
                Fake.tick(5)
                change()
                Fake.tick(5)
                lib:SetEnabled(true)
                return h
            end,
        }
        for name, path in pairs(paths) do
            for _, case in ipairs({
                { UP, 1, "the aura came" },
                { UP, 0, "the aura went" },
                { ST, 3, "stacks came" },
            }) do
                it(name .. ", " .. case[3] .. ": never the presence it had", function()
                    world({ [11] = { spellID = 5001, category = 3 } }, { 11 })
                    Fake.login()
                    local v = case[2]
                    if v == 0 then
                        Fake.setAura("player", 5001, 3)
                    end
                    local h = lib:Watch("A", case[1])
                    Fake.tick(20)
                    h = path(h, case[1], function()
                        Fake.setAura("player", 5001, v > 0 and 3 or nil)
                    end)
                    local lo = never(h, 80, v)
                    if h.what == "up" then
                        assert.are.equal(v, lo)
                    end
                end)
            end
        end

        it("also released under minor 7 and watched again after the upgrade", function()
            if not sevenSource() then
                pending("no minor 7 in this clone (git show " .. SEVEN .. ")")
                return
            end
            boot(true)
            Fake.login()
            local h = lib:Watch("A", UP)
            Fake.tick(20)
            h:Release()
            Fake.loadLibrary()
            Fake.setAura("player", 5001, 2)
            Fake.tick(2)
            assert.are.equal(1, never(lib:Watch("A", UP), 20, 1))
        end)
    end)

    describe("a move to another entry keeps nothing of the one it left", function()
        local ST = { kind = "aura", unit = "player", spell = 5001, what = "stacks", edges = { 2, 3 } }
        local TWO = { [11] = { spellID = 5001, category = 3 }, [17] = { spellID = 5001, category = 2 } }
        local LINKED = {
            [11] = { spellID = 5013, category = 3, linkedSpellIDs = { 5001 } },
            [17] = { spellID = 5001, category = 2 },
        }

        local function placed(spec, catalogue, toIcon, unit, n)
            world(catalogue or TWO, toIcon and { 11 } or {}, toIcon and {} or { 17 })
            W.unit.target = { health = 1 }
            local h = lib:Watch("A", spec)
            Fake.login()
            Fake.tick(20)
            Fake.setAura(unit or "player", 5001, n)
            Fake.tick(20)
            return h
        end
        local function toBar()
            W.cdm.bar, W.cdm.icon = { 11 }, {}
        end

        local cases = {
            ["the count rose in that frame"] = function()
                local h = placed(ST, nil, false, nil, 1)
                toBar()
                Fake.cdmLayout()
                Fake.setAura("player", 5001, 3)
                return h, 3
            end,
            ["the count written inside the layout"] = function()
                local h = placed(ST, nil, false, nil, 1)
                toBar()
                W.aura.player[5001].stacks = 3
                Fake.cdmLayout()
                return h, 3
            end,
            ["the count fell in that frame"] = function()
                local h = placed(ST, nil, false, nil, 3)
                toBar()
                Fake.cdmLayout()
                Fake.setAura("player", 5001, 1)
                return h, 1
            end,
            ["in combat, with only the viewers' data refreshed"] = function()
                local h = placed(ST, nil, false, nil, 1)
                W.combat = true
                toBar()
                Fake.cdmData()
                Fake.setAura("player", 5001, 4)
                return h, 4
            end,
            ["from a bar to an icon"] = function()
                local h = placed(ST, nil, true, nil, 1)
                W.cdm.bar, W.cdm.icon = {}, { 17 }
                Fake.cdmLayout()
                Fake.setAura("player", 5001, 3)
                return h, 3
            end,
            ["its item holds another linked aura"] = function()
                local h = placed(ST, LINKED, false, nil, 1)
                aura(5013, 5)
                toBar()
                Fake.cdmLayout()
                return h, 5
            end,
            ["with a target swap"] = function()
                local spec = { kind = "aura", unit = "target", spell = 5001, what = "stacks", edges = { 2, 3 } }
                local h = placed(spec, nil, false, "target", 1)
                toBar()
                Fake.cdmLayout()
                W.aura.target = {}
                aura(5001, 3, "target")
                Fake.event("PLAYER_TARGET_CHANGED")
                return h, 3
            end,
        }
        for name, run in pairs(cases) do
            it("stacks, " .. name .. ": never the other entry's count", function()
                local h, v = run()
                never(h, 400, v)
            end)
        end

        it("up: not the other entry's presence, then this one's", function()
            local spec = { kind = "aura", unit = "player", spell = 5001, what = "up" }
            local h = placed(spec, LINKED, false, nil, nil)
            aura(5013, 2) -- only the other entry's item shows this one
            toBar()
            Fake.cdmLayout()
            assert.are.equal(1, never(h, 10, 1))
        end)

        it("left: not the other entry's seconds", function()
            world({
                [11] = { spellID = 5013, category = 3, linkedSpellIDs = { 5001 } },
                [17] = { spellID = 5001, category = 3 },
            }, { 17 })
            local h = lib:Watch("A", { kind = "aura", unit = "player", spell = 5001, what = "left", edges = { 6 } })
            Fake.login()
            Fake.setAura("player", 5001, 1, 90)
            Fake.tick(20)
            assert.are.equal(6, (h:Get()))
            W.aura.player[5013] = { stacks = 1, duration = 4, expires = GetTime() + 4 }
            W.cdm.bar = { 11 }
            Fake.cdmLayout()
            assert.are.equal(0, never(h, 30, 4))
        end)

        -- The price: the count written as the layout changed went to nobody.
        it("the same count after the move: unknown until the next count", function()
            local h = placed(ST, nil, false, nil, 3)
            toBar()
            Fake.cdmLayout()
            for _ = 1, 400 do
                Fake.tick(1)
                assert.is_nil((h:Get()))
                assert.are.equal("priming", (h:State()))
            end
            Fake.setAura("player", 5001, 3)
            assert.are.equal(3, never(h, 10, 3))
        end)

        it("the same entry on another viewer: the count stands", function()
            world({ [17] = { spellID = 5001, category = 2 } }, {}, { 17 })
            local h = lib:Watch("A", ST)
            Fake.login()
            Fake.tick(20)
            Fake.setAura("player", 5001, 3)
            Fake.tick(20)
            W.cdm.bar, W.cdm.icon = { 17 }, {}
            Fake.cdmLayout()
            for _ = 1, 30 do
                Fake.tick(1)
                assert.are.equal(3, (h:Get()))
            end
        end)
    end)

    describe("the catalogue, read out of combat", function()
        local UP = { kind = "aura", unit = "player", spell = 7001, what = "up" }
        local ONE = { [20] = { spellID = 7000, category = 3 } }
        local NEW = { [20] = { spellID = 7000, category = 3 }, [21] = { spellID = 7001, category = 3 } }
        local OVER = { [20] = { spellID = 7000, overrideSpellID = 7001, category = 3 } }

        -- In a fight an entry for 7001 is added, announced, and shown with its aura up: the list from before has none.
        local function added()
            world(ONE, { 20 })
            Fake.login()
            Fake.tick(20)
            W.combat = true
            aura(7001, 1)
            W.cdm.catalogue, W.cdm.bar = NEW, { 20, 21 }
            Fake.event("SPELLS_CHANGED")
            Fake.cdmLayout()
            Fake.tick(5)
        end

        for _, event in ipairs({
            "TRAIT_CONFIG_UPDATED",
            "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
            "ACTIVE_COMBAT_CONFIG_CHANGED",
            "ACTIVE_TALENT_GROUP_CHANGED",
        }) do
            it("the getters follow " .. event .. " into combat, with no watch", function()
                world(OVER, { 20 })
                Fake.login()
                W.cdm.catalogue, W.cdm.bar = NEW, { 20, 21 }
                Fake.event(event)
                Fake.cdmLayout()
                Fake.tick(5)
                W.combat = true
                local list, read = lib:GetAuraEntries(7001)
                assert.are.equal(21, list[1] and list[1].cooldownID)
                assert.is_true(read)
                assert.are.same({ true, "ready" }, { lib:IsAvailable("aura", UP) })
                assert.are.equal(0, Fake.hooks)
            end)
        end

        it("the getters in combat: an item the list does not hold proves it old", function()
            added()
            local reads = seen.catalogue
            assert.are.same({ false, "pending" }, { lib:IsAvailable("aura", UP) })
            assert.is_false(select(2, lib:GetAuraEntries(7001)))
            assert.are.equal(reads, seen.catalogue)
            W.combat = false
            Fake.event("PLAYER_REGEN_ENABLED")
            Fake.tick(2)
            assert.are.same({ true, "ready" }, { lib:IsAvailable("aura", UP) })
            assert.are.equal(reads + 1, seen.catalogue)
            assert.are.equal(0, Fake.hooks)
        end)

        it("the getters out of combat: that item has the list read on the next frame", function()
            world(ONE, { 20 })
            Fake.login()
            Fake.tick(20)
            W.cdm.catalogue, W.cdm.bar = NEW, { 20, 21 } -- an ID shown that no event the library knows announced
            Fake.cdmLayout()
            Fake.tick(5)
            lib:GetAuraEntries(7001)
            Fake.tick(1)
            assert.are.same({ true, "ready" }, { lib:IsAvailable("aura", UP) })
            assert.are.equal(0, Fake.hooks)
        end)

        it("a first watch in combat, an item the list does not hold: pending, never a 0, until combat ends", function()
            added()
            local reads = seen.catalogue
            local h = lib:Watch("A", UP)
            assert.are.equal(16, Fake.hooks) -- installed at once, in combat too
            for _ = 1, 30 do
                Fake.tick(1)
                assert.are.same({ "pending" }, { h:State() })
                assert.is_nil((h:Get()))
            end
            assert.are.equal(reads, seen.catalogue)
            W.combat = false
            Fake.event("PLAYER_REGEN_ENABLED")
            assert.are.equal(1, never(h, 20, 1))
        end)
    end)

    -- The catalogue is read out of combat only: what is read in a fight is the list from before it, as minor 7.
    describe("a list read before the fight", function()
        -- 15 shows 5005 while its override is up; 21 (an icon, "two") shows it always.
        local function A(two)
            local c = { [15] = { spellID = 5015, category = 3 }, [11] = { spellID = 5001, category = 3 } }
            if two then
                c[21] = { spellID = 5005, category = 2 }
            end
            return c
        end
        local function B(two)
            local c = A(two)
            c[15] = { spellID = 5015, overrideSpellID = 5005, category = 3 }
            return c
        end
        local OVER = "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED"
        local ends = { -- how the override ends in the fight
            ["an override that ends"] = function(two)
                W.cdm.catalogue = A(two)
                Fake.event(OVER)
                Fake.cdmData()
            end,
            ["an event that changes nothing"] = function()
                Fake.event("SPELLS_CHANGED")
                Fake.cdmData()
            end,
            ["an override that ends with no event"] = function(two)
                W.cdm.catalogue = A(two)
                Fake.cdmData()
            end,
            ["an override that ends, its field secret"] = function(two)
                W.cdm.catalogue = A(two)
                W.cdm.catalogue[15].overrideSpellID = Fake.secret(5015)
                Fake.event(OVER)
                Fake.cdmData()
            end,
        }
        local asks = { -- what asks after the override came
            ["IsAvailable"] = function()
                lib:IsAvailable("aura", { kind = "aura", unit = "player", spell = 5001, what = "up" })
            end,
            ["GetAuraEntries"] = function()
                lib:GetAuraEntries(5001)
            end,
            ["another watch"] = function()
                lib:Watch("D", { kind = "aura", unit = "player", spell = 5001, what = "up" })
            end,
            ["a new watch on the override"] = true,
            ["nothing"] = function() end,
        }
        -- Each frame of n: a band, if known (and known: must), holds 5005's aura on the player.
        local function holds(h, n, must)
            for f = 1, n do
                Fake.tick(1)
                local lo, hi = h:Get()
                local a = W.aura.player[5005]
                local v = h.what == "up" and (a and 1 or 0) or (a and a.stacks or 0)
                if must then
                    assert.is_not_nil(lo, "frame " .. f)
                end
                if lo ~= nil then
                    local ok = h.what == "up" and lo == v and hi == v or v >= lo and (v < hi or hi == math.huge)
                    assert.is_true(ok, ("frame %d: %s-%s, true %d"):format(f, tostring(lo), tostring(hi), v))
                end
            end
        end

        for name, ending in pairs(ends) do
            for who, ask in pairs(asks) do
                for _, what in ipairs({ "up", "stacks" }) do
                    it(
                        name .. ", " .. who .. " asked in it, " .. what .. ": never a band the world does not hold",
                        function()
                            local two = ask ~= true
                            world(A(two), { 15, 11 }, two and { 21 } or {})
                            Fake.login()
                            Fake.tick(60)
                            local spec = { kind = "aura", unit = "player", spell = 5005, what = what, edges = { 2, 3 } }
                            local h
                            if two then
                                h = lib:Watch("C", spec)
                            else
                                lib:Watch("C", { kind = "aura", unit = "player", spell = 5001, what = "up" })
                            end
                            Fake.tick(10)
                            W.combat = true
                            Fake.event("PLAYER_REGEN_DISABLED")
                            Fake.setAura("player", 5005, 3, 600)
                            Fake.tick(10)
                            W.cdm.catalogue = B(two)
                            Fake.event(OVER)
                            Fake.cdmData()
                            Fake.tick(1)
                            if two then
                                ask()
                            else
                                h = lib:Watch("C", spec)
                            end
                            holds(h, 20, false)
                            Fake.setAura("player", 5005, 3, 600)
                            holds(h, 20, false)
                            ending(two)
                            holds(h, 600, two) -- minor 7: known and true on every frame where it was watched before
                            Fake.setAura("player", 5005, 4, 600)
                            holds(h, 20, two)
                            assert.are.same({}, Fake.errors)
                        end
                    )
                end
            end
        end

        it("an item keeps its info while only the client's answer changed: the list from before", function()
            world({
                [20] = { spellID = 7000, overrideSpellID = 7001, category = 3 },
                [21] = { spellID = 7002, category = 3 },
            }, { 20, 21 })
            Fake.login()
            Fake.tick(20)
            W.cdm.catalogue = { -- no event: the items keep the provider's info, as the client's do
                [20] = { spellID = 7000, category = 3 },
                [21] = { spellID = 7002, overrideSpellID = 7001, category = 3 },
            }
            Fake.cdmLayout()
            Fake.tick(5)
            aura(7001, 1)
            W.combat = true
            Fake.event("UNIT_AURA", "player")
            Fake.tick(5)
            local h = lib:Watch("A", { kind = "aura", unit = "player", spell = 7001, what = "up" })
            assert.are.equal(1, never(h, 20, 1))
        end)
    end)

    describe("a secret cooldownID at the first watch", function()
        local function hide(cd)
            for item in pairs(Fake.viewers[1].itemFramePool.active) do
                if item.cooldownID == cd then
                    item.cooldownID = Fake.secret(cd)
                end
            end
        end

        for _, what in ipairs({ "left", "up" }) do
            it(what .. ": an item that could rank first: pending, not the lower one's answer", function()
                world(
                    { [11] = { spellID = 5001, category = 3 }, [17] = { spellID = 5001, category = 2 } },
                    { 11 },
                    { 17 }
                )
                Fake.login()
                W.combat = true
                Fake.setAura("player", 5001, 3)
                hide(11)
                Fake.tick(2)
                local h = lib:Watch("A", { kind = "aura", unit = "player", spell = 5001, what = what, edges = { 3 } })
                for _ = 1, 20 do
                    Fake.tick(1)
                    assert.are.same({ "pending" }, { h:State() })
                    assert.is_nil((h:Get()))
                end
            end)
        end

        it("an earlier entry of the same viewer could rank first: pending", function()
            world({ [11] = { spellID = 5001, category = 3 }, [12] = { spellID = 5001, category = 3 } }, { 11, 12 })
            Fake.login()
            W.combat = true
            hide(11)
            local h = lib:Watch("A", { kind = "aura", unit = "player", spell = 5001, what = "up" })
            assert.are.same({ "pending" }, { h:State() })
        end)

        it("a later watch over one: pending, and the answers given stand", function()
            world({
                [11] = { spellID = 5001, category = 3 },
                [15] = { spellID = 5005, category = 3 },
                [17] = { spellID = 5001, category = 2 },
                [18] = { spellID = 5008, category = 3 },
            }, { 11, 15, 18 }, { 17 })
            local old = lib:Watch("A", { kind = "aura", unit = "player", spell = 5005, what = "up" })
            Fake.login()
            W.combat = true
            hide(11)
            hide(15)
            Fake.cdmData() -- a read of the items that meets them
            for item in pairs(Fake.viewers[1].itemFramePool.active) do
                if item.cd == 11 or item.cd == 15 then
                    item.cooldownID = Fake.secret(item.cd)
                end
            end
            Fake.tick(2)
            local h = lib:Watch("A", { kind = "aura", unit = "player", spell = 5001, what = "up" })
            local same = lib:Watch("A", { kind = "aura", unit = "player", spell = 5008, what = "up" })
            assert.are.same({ "pending" }, { h:State() })
            assert.are.equal("priming", (same:State()))
            for _ = 1, 10 do
                Fake.tick(1)
                assert.is_nil((h:Get()))
                assert.are.same({ "gone" }, { old:State() }) -- its item cannot be told: not "cdm-not-tracked"
            end
        end)

        it("watched again while one is hidden: a new watch, not the lower entry's answer", function()
            world({
                [11] = { spellID = 5001, category = 3 },
                [17] = { spellID = 5017, category = 2, linkedSpellIDs = { 5001 } },
            }, {}, { 17 })
            local spec = { kind = "aura", unit = "player", spell = 5001, what = "up" }
            local h = lib:Watch("A", spec)
            Fake.login()
            Fake.tick(5)
            h:Release()
            W.combat = true
            W.cdm.bar = { 11 }
            Fake.cdmData() -- the bar's item shows the entry that ranks first now, its identity secret
            hide(11)
            Fake.tick(2)
            h = lib:Watch("A", spec)
            for _ = 1, 10 do
                Fake.tick(1)
                assert.are.same({ "pending" }, { h:State() })
                assert.is_nil((h:Get()))
            end
        end)

        it("none could rank before the one shown: it answers", function()
            world({
                [11] = { spellID = 5001, category = 3 },
                [12] = { spellID = 5001, category = 3 },
                [15] = { spellID = 5005, category = 3 },
            }, { 11, 12, 15 })
            Fake.login()
            W.combat = true
            hide(12)
            hide(15)
            assert.are.equal(
                0,
                never(lib:Watch("A", { kind = "aura", unit = "player", spell = 5001, what = "up" }), 5, 0)
            )
        end)
    end)

    describe("a presence set after the count was written", function()
        for _, icon in ipairs({ false, true }) do
            for _, combat in ipairs({ false, true }) do
                local how = (icon and ", an icon" or ", a bar") .. (combat and ", in combat" or "")
                it("is not 0-1 stacks: unknown until a count" .. how, function()
                    local entry = { [11] = { spellID = 5001, category = 3, linkedSpellIDs = { 5013 } } }
                    world(entry, icon and {} or { 11 }, icon and { 11 } or {})
                    W.cdm.filtered = { [5013] = true }
                    local spec = { kind = "aura", unit = "player", spell = 5013, what = "stacks", edges = { 2, 3 } }
                    local h = lib:Watch("A", spec)
                    local up = lib:Watch("A", { kind = "aura", unit = "player", spell = 5013, what = "up" })
                    Fake.login()
                    Fake.tick(20)
                    W.combat = combat
                    Fake.setAura("player", 5013, 4)
                    Fake.tick(2) -- the absent band's own latency
                    assert.is_nil(never(h, 100, 4))
                    assert.are.equal(1, (up:Get()))
                    Fake.setAura("player", 5013, 4) -- the same linked spell bound again: no MarkDirty comes
                    assert.is_nil(never(h, 100, 4))
                    W.cdm.filtered = {} -- a scan that finds it writes its count
                    Fake.setAura("player", 5013, 4)
                    assert.are.equal(3, never(h, 12, 4))
                end)
            end
        end
    end)

    -- An icon's OnCooldownDone runs RefreshActive alone: another aura is bound and no count written.
    describe("an icon that binds a linked aura when its aura ran out", function()
        local ST = { kind = "aura", unit = "player", spell = 5001, what = "stacks", edges = { 2, 3 } }
        for _, combat in ipairs({ false, true }) do
            it("keeps no count of it: unknown until the next" .. (combat and ", in combat" or ""), function()
                world({
                    [12] = { spellID = 5002, category = 2 },
                    [17] = { spellID = 5001, category = 2, linkedSpellIDs = { 5013 } },
                }, {}, { 17, 12 })
                local h = lib:Watch("A", ST)
                local other = lib:Watch("A", { kind = "aura", unit = "player", spell = 5002, what = "stacks", max = 4 })
                local up = lib:Watch("A", { kind = "aura", unit = "player", spell = 5001, what = "up" })
                Fake.login()
                Fake.tick(20)
                Fake.setAura("player", 5002, 4)
                Fake.setAura("player", 5001, 3)
                Fake.tick(20)
                assert.are.equal(3, (h:Get()))
                W.combat = combat
                aura(5013, 1)
                Fake.cdmExpire("player", 5001)
                for _ = 1, 200 do
                    Fake.tick(1)
                    assert.is_nil((h:Get()))
                    assert.are.equal("priming", (h:State()))
                    assert.are.equal(4, (other:Get())) -- the other item's count stands
                    assert.are.equal(1, (up:Get()))
                end
                Fake.setAura("player", 5013, 1) -- the next count write
                assert.are.equal(0, never(h, 12, 1))
            end)
        end

        it("also one already hooked by minor 7, after the upgrade", function()
            if not sevenSource() then
                pending("no minor 7 in this clone (git show " .. SEVEN .. ")")
                return
            end
            boot(true, function()
                W.cdm.catalogue = { [17] = { spellID = 5001, category = 2, linkedSpellIDs = { 5013 } } }
                W.cdm.bar, W.cdm.icon = {}, { 17 }
            end)
            local h = lib:Watch("A", ST)
            Fake.login()
            Fake.loadLibrary()
            Fake.tick(80)
            Fake.setAura("player", 5001, 3)
            Fake.tick(20)
            assert.are.equal(3, (h:Get()))
            aura(5013, 1)
            Fake.cdmExpire("player", 5001)
            Fake.tick(1)
            assert.is_nil(never(h, 60, 1))
        end)
    end)

    -- The same script on minor 7 and on this tree ---------------------------------------------------------------------
    --
    -- Two judgements, both against the fake's world, never against the library's own reads:
    --   - every known band of this tree holds what the world held within the kind's latency (h:Latency()), counted
    --     only since the watch last started to follow that entry: a band from before a release, a switch-off or a
    --     move to another entry is wrong in the first frame, also where minor 7 says the same. The entry is the rule's
    --     on minor 7's own list (the catalogue as read out of combat: this tree's too, never what the library read), its
    --     aura the one its item shows in the world (the item's cached info);
    --   - where this tree differs from the real minor 7, a placement answer must be the true one on that list, and an
    --     unknown where minor 7 was right must have one of the named causes: it is counted under it. Any other fails.
    -- Every change of the catalogue is announced by a provider event (an unannounced one is not the client's: an item
    -- keeps its info until one). A remap in a fight is seen when it ends, by minor 7 too: in a fight a change only adds
    -- an entry. LHV_REPORT: a file the counts are appended to.

    -- One random session. when: "login" (the watches made before login), "later" (out of combat), "combat" (in combat,
    -- a getter asked before it), "cold" (in combat, nothing asked before it), "getters" (no watch, the getters asked
    -- every step). mid (when set) runs once, mid-session; bands are judged from there.
    local function session(old, seed, when, mid)
        local r = seed * 7919 + 17
        local function rand(n)
            r = r * 16807 % 2147483647
            return math.floor(r / 2147483647 * n) + 1
        end
        boot(old)
        local v, hs, sunk, tr, rows, asked, steps = {}, {}, {}, {}, {}, {}, 28
        local list -- minor 7's: the catalogue as last read out of combat
        local stale, used, poked, warmed = true, false, true, false
        local unheld = false -- an item on screen the list does not hold, met by a getter or the first watch
        local shown = {} -- cooldownID -> the info its item shows
        local blind, offLast, disabled, now = false, false, false, 0
        local at, lost, lostLast, settled, blindLast = {}, false, false, false, false
        local retest -- the last frame of the self-test an upgrade started again
        local wrote, writes = {}, {} -- cooldownID -> the frame its count was last written
        local relaid, lateTo, swapSeen, judging = 0, 0, true, mid == nil
        W.cdm.catalogue = worldCatalogue(v)
        W.cdm.bar, W.cdm.icon, W.cdm.essential, W.cdm.utility = { 11, 15 }, { 12, 13 }, { 14 }, { 18 }
        -- secret identities only where no history is needed, and in the cold runs
        W.cdm.secretId = (when == "login" or when == "cold") and rand(5) == 1
        W.cdm.secretUnit = rand(6) == 1
        W.cdm.quietSwap = rand(2) == 1
        W.cdm.lateSwap = rand(2) == 1 and rand(20) or nil
        W.cdm.shuffle = rand(3) == 1
        W.cdm.filtered = rand(4) == 1 and { [5013] = true } or nil
        local secretReads = rand(4) > 1 -- from the login self-test on (its prime must be secret)
        W.cdm.enabled = rand(10) > 1
        W.combat = when == "login" and rand(6) == 1
        local secretLag = rand(2) - 1
        Fake.set("secretlag", secretLag)
        if rand(2) == 1 then
            W.aura.player[5001] = { stacks = 2, duration = 20, expires = GetTime() + 20 }
        end

        local function screen()
            at, lost, shown = {}, false, {}
            for k, viewer in ipairs(Fake.viewers) do
                for item in pairs(viewer.itemFramePool.active) do
                    if item.cd and not at[item.cd] then
                        at[item.cd], shown[item.cd] = k, item.info
                    end
                    if issecretvalue(item.cooldownID) then
                        lost = true
                    end
                    if item.wrote ~= writes[item] then
                        writes[item] = item.wrote
                        if item.cd and k <= 2 then
                            wrote[item.cd] = now
                        end
                    end
                end
            end
        end

        -- The catalogue as read out of combat (a load and an event leave it to be read).
        local function read()
            list, stale, unheld = W.cdm.catalogue, false, false
        end

        -- A getter with no watch or the first watch reads the items: one the list does not hold makes new answers wait.
        local function getter()
            if used or not judging then
                return -- with a watch, or under minor 7 before an upgrade: no read here
            end
            screen()
            if stale and not W.combat and not offLast then
                read()
            end
            for item in pairs(at) do
                if list and not list[item] then
                    stale, unheld = true, true
                end
            end
        end

        local function watch(k)
            screen()
            blind = blind or lost
            if not used and now > 0 then
                getter()
                poked = true
            end
            used = true
            poked = poked or not tr[k]
            tr[k] = { fresh = unheld and judging, hist = {}, mid = {}, said = {} } -- made on minor 7, before an upgrade: it answered
            sunk[k] = {}
            local to = sunk[k]
            hs[k] = assert(lib:Watch("A", SPECS[k], function(_, lo, hi)
                to[1], to[2] = lo, hi
            end))
        end

        local function watchAll()
            for k = 1, #SPECS do
                watch(k)
            end
        end

        local function snapshot(cd, spec, f)
            local a = auraOf(shown[cd], W.aura[spec.unit])
            return { f = f, n = a and a.stacks, left = a and math.max(0, a.expires - GetTime()) or 0 }
        end

        local function frame()
            now, settled = now + 1, true
            Fake.tick(1)
            if stale and not W.combat and W.cdm.enabled then
                read()
            end
            screen()
            if lost then
                blind = true -- until a read of the items with every ID plain
            elseif poked then
                blind = false
            end
            poked = false
            local tested = lib:GetSelfTest() == true
            local row = {}
            for k = 1, #SPECS do
                local h, t = hs[k], tr[k]
                if h then
                    local spec = SPECS[k]
                    local lo, hi = h:Get()
                    local state, why = h:State()
                    local rec = { lo = lo, hi = hi, state = state, why = why }
                    row[k] = rec
                    -- the entry on minor 7's own list (this tree's too), its aura what that item shows in the world
                    local cd, _, reason = entryOf(spec, list, at)
                    if t.fresh and not unheld then -- it answers from here on
                        t.fresh, t.hist, t.cd = false, {}, nil
                    end
                    local follow = not disabled
                        and W.cdm.enabled
                        and not reason
                        and (spec.what == "up" or tested)
                        and cd ~= nil
                    local was, wasMove = t.hist, false
                    if not follow then
                        t.hist, t.cd = {}, nil
                    elseif t.cd ~= cd then
                        wasMove = t.cd ~= nil
                        t.why = wasMove and "move" or "start"
                        t.cd, t.since, t.hist = cd, now, {}
                        t.movedAt, t.banded = now, false
                        if not wasMove then
                            t.born = now
                        end
                    end
                    if follow then
                        local hist = t.hist
                        if #hist > 0 then -- what the world held between two ops of one frame, of a source following
                            for i = 1, #t.mid do
                                hist[#hist + 1] = t.mid[i]
                            end
                        end
                        hist[#hist + 1] = snapshot(cd, spec, now)
                        -- a target swapped to whose auras had not come, and a UNIT_AURA of it since: the client's word
                        if spec.unit == "target" and now < lateTo and swapSeen then
                            hist[#hist + 1] = { f = now, left = 0 }
                        end
                        local back = spec.what == "up" and 1
                            or (spec.what == "stacks" and lib.SETTLE + 1 or lib.HOLD + lib.SETTLE + 3) + secretLag
                        while hist[1].f < now - back do
                            table.remove(hist, 1)
                        end
                    end
                    if lo ~= nil then
                        local snaps = t.hist
                        -- with an ID secret the library cannot see a layout move: one frame on the entry it had
                        if (lost or lostLast) and (wasMove or not follow) and #was > 0 then
                            snaps = was
                        end
                        local holds = false
                        for i = 1, #snaps do
                            holds = holds or fits(spec.what, lo, hi, snaps[i])
                        end
                        rec.right = holds
                        if (t.fresh or not holds) and judging then
                            rec.wrong = t.fresh and "a band while an item the list does not hold is shown"
                                or not follow and "a band with no entry to follow"
                                or t.since == now and (t.why == "move" and "a band from the entry it left")
                                or t.since == now and "a band from before the source started"
                                or t.why == "move" and "a band wrong since a move"
                                or "a band against the world"
                            rec.wrong = rec.wrong .. ", " .. spec.what
                        end
                    end
                    if state == "pending" and reason and not (tested or lost or blind or t.fresh) then
                        t.said[reason] = true -- placed while the self-test runs: the answer it has when it passes
                    end
                    if state == "unavailable" and why and (why:find("^cdm%-") or why == "not-in-cdm") then
                        -- with an ID secret an answer given stands
                        local stands = (lost or lostLast or blind) and t.said[why] and not t.fresh
                        if why == "cdm-off" then
                            t.said[reason or "ready"] = true -- placed while off: the answer it has when it is on
                        elseif (t.fresh or why ~= reason) and not stands then
                            rec.false_ = t.fresh and "while an item the list does not hold is shown"
                                or "not the true one"
                        elseif why == reason then
                            t.said = { [why] = true }
                        end
                    end
                    if t.why == "move" and (lost or lostLast or blind) then
                        t.movedAt = now -- the move is seen once the items read with every ID plain
                    end
                    if lost or lostLast or blind or blindLast then
                        t.hiddenAt = now -- an identity read plain again in a pass that wrote the count before it
                    end
                    if (lost or lostLast or blind or t.fresh) and state == "pending" then
                        t.waited = now
                    end
                    if lost or lostLast or blind or blindLast then -- and the frame that decodes the first plain read
                        rec.cause = "secret cooldownID"
                    elseif retest and now <= retest + lib.HOLD + lib.SETTLE + 3 and spec.what ~= "up" then
                        rec.cause = "the self-test run again at the upgrade"
                    elseif t.fresh then
                        rec.cause = "an item the list does not hold"
                    elseif t.waited and now - t.waited <= lib.HOLD + lib.SETTLE + 3 + secretLag then
                        rec.cause = "its bars made as a pending answer came"
                    elseif follow then
                        local age, moved = now - t.since, now - t.movedAt
                        local w = wrote[cd] or -1
                        local settling = now - w <= lib.SETTLE + 2 + secretLag
                        local born = math.max(t.born or 0, relaid, t.waited or 0, t.hiddenAt or 0)
                        local other = spec.unit == "player" and "target" or "player"
                        local e = shown[cd]
                        local held = auraOf(e, W.aura[other]) -- the client scans the player first
                            and (other == "player" or not auraOf(e, W.aura.player))
                        local primed = lib.HOLD + lib.SETTLE + 3 + secretLag
                        local making = not t.banded and (moved <= primed or now - w <= primed)
                        local present = false -- only an aura up waits for a count
                        for i = 1, #t.hist do
                            present = present or t.hist[i].n ~= nil
                        end
                        if held then
                            t.heldAt = now
                        end
                        if t.why == "move" and spec.what == "up" and moved <= 1 then
                            rec.cause = "a move to another entry"
                        elseif t.why == "move" and spec.what == "left" and making then
                            rec.cause = "a move to another entry"
                        elseif
                            t.why == "move"
                            and spec.what == "stacks"
                            and (moved <= 1 or settling or (present and w <= t.movedAt))
                        then
                            rec.cause = "a move to another entry, no count since"
                        elseif age <= 1 and t.why == "start" then
                            rec.cause = "the first frame after inactive"
                        elseif spec.what == "left" and t.why == "start" and making then
                            rec.cause = "its bars made as the source started"
                        elseif spec.what == "stacks" and (settling or (present and w <= born + lib.HOLD + 2)) then
                            rec.cause = "no count seen since the bars were made"
                        elseif spec.what == "stacks" and W.cdm.filtered and W.aura[spec.unit][5013] then
                            rec.cause = "the presence set after the count"
                        elseif t.heldAt and now - t.heldAt <= 1 then -- and the frame it is read in
                            rec.cause = "the item holds the other unit's aura" -- the entry of the list read now
                        elseif
                            state == "gone"
                            and spec.unit == "target"
                            and not swapSeen
                            and (not W.cdm.lateSwap or now <= lateTo)
                        then -- followed sooner than by minor 7, which can keep the presence of the entry it left
                            rec.cause = "a target swap's doubt"
                        end
                    end
                    t.mid = {}
                    t.banded = t.banded or lo ~= nil
                    if judging and (lo ~= sunk[k][1] or hi ~= sunk[k][2]) then
                        rec.sink = true
                    end
                end
            end
            rows[#rows + 1] = row
            lostLast, blindLast, offLast = lost, blind, not W.cdm.enabled
        end

        local function relist()
            local bars = { { 11, 15 }, { 15 }, { 15, 11, 13 }, { 17, 21 }, { 11, 21, 23 }, { 23, 17, 22 } }
            local icons = { { 12, 13 }, { 13, 12, 17 }, { 11 }, {}, { 17, 22, 12 }, { 21, 15, 13, 12 } }
            local function known(ids)
                local out = {}
                for _, id in ipairs(ids) do
                    if W.cdm.catalogue[id] then
                        out[#out + 1] = id
                    end
                end
                return out
            end
            local bar, icon = known(bars[rand(#bars)]), known(icons[rand(#icons)])
            local sized = math.max(#bar, 2) ~= math.max(#W.cdm.bar, 2) or math.max(#icon, 2) ~= math.max(#W.cdm.icon, 2)
            W.cdm.bar, W.cdm.icon = bar, icon
            poked = true
            if not sized and rand(2) == 1 then
                Fake.cdmData() -- the client's, while the item count stands
            else
                Fake.cdmLayout()
            end
        end

        local function change()
            local adds = { "added", "second" }
            local all = { "added", "second", "moved", "unlinked" }
            if W.combat then -- a remap in a fight is seen when it ends, by minor 7 too
                v[adds[rand(2)]] = true
            else
                local flag = all[rand(4)]
                v[flag] = not v[flag]
            end
            W.cdm.catalogue = worldCatalogue(v)
            stale = true
            Fake.event(PROVIDED[rand(#PROVIDED)]) -- the provider builds it again
            relist() -- and notifies: the viewers refresh
        end

        local function swap()
            W.aura.target = {}
            if rand(3) > 1 then
                W.aura.target[SPELLS[rand(#SPELLS)]] = { stacks = rand(4), duration = 25, expires = GetTime() + 25 }
            end
            lateTo, swapSeen = now + (W.cdm.lateSwap or 0), false
            Fake.event("PLAYER_TARGET_CHANGED")
        end

        local function setAura(unit, ...)
            if unit == "target" then
                swapSeen = true
            end
            Fake.setAura(unit, ...)
        end

        if when == "login" then
            watchAll()
        end
        Fake.event("PLAYER_LOGIN")
        for _ = 1, 50 do
            frame()
        end
        W.secret = secretReads
        for n = 1, steps do
            local op, ready = rand(30), true
            local eligible = not used
                and n >= 4
                and (
                    (when == "later" and not W.combat)
                    or ((when == "combat" or when == "cold") and W.combat and warmed)
                )
            settled = false
            if op <= 5 then
                local spell = SPELLS[rand(#SPELLS)]
                setAura(rand(2) == 1 and "player" or "target", spell, rand(5), rand(4) == 1 and rand(8) or 30)
            elseif op <= 7 then
                setAura(rand(2) == 1 and "player" or "target", SPELLS[rand(#SPELLS)], nil)
            elseif op <= 10 then
                swap()
            elseif op <= 13 then
                if W.combat then
                    W.combat, poked = false, true
                    Fake.event("PLAYER_REGEN_ENABLED")
                else
                    if not used and (when == "combat" or when == "getters") then
                        getter()
                        lib:GetAuraEntries(5001) -- asked before combat
                    end
                    W.combat, warmed = true, true
                end
            elseif op == 14 then
                relist()
            elseif op == 15 then
                poked = true
                Fake.cdmLayout()
            elseif op == 16 then
                poked = true
                Fake.cdmEnable(not W.cdm.enabled)
            elseif op == 17 then
                relaid = now
                Fake.event("LOADING_SCREEN_DISABLED")
            elseif op == 18 then
                stale, poked = true, true
                Fake.event(ANNOUNCE[rand(#ANNOUNCE)])
            elseif op == 19 then
                swapSeen = true
                Fake.event("UNIT_AURA", "target")
            elseif op <= 22 and used then
                local k = rand(#SPECS)
                if hs[k] then
                    hs[k]:Release()
                    hs[k] = nil
                    if rand(2) == 1 then
                        watch(k)
                    end
                else
                    watch(k)
                end
            elseif op <= 24 then
                change()
            elseif op <= 26 then -- a move and a count in one frame
                relist()
                setAura("player", rand(3) == 1 and 5017 or 5001, rand(5), 30)
            elseif op == 27 and used and rand(2) == 1 then
                disabled = not disabled
                if not disabled then
                    W.secret = true -- the self-test runs again
                end
                lib:SetEnabled(not disabled)
                for k = 1, #SPECS do
                    if tr[k] then -- every source stops or starts
                        tr[k].cd, tr[k].hist, tr[k].mid = nil, {}, {}
                    end
                end
            else
                ready = false
            end
            local early = eligible and rand(2) == 1
            if early then
                watchAll() -- in the event's own frame
            end
            if rand(4) > 1 or n == steps then -- else the next op lands in the same frame
                for _ = 1, rand(12) + (ready and 0 or 4) do
                    frame()
                end
            else
                for k = 1, #SPECS do
                    local t = tr[k]
                    if hs[k] and t.cd then
                        t.mid[#t.mid + 1] = snapshot(t.cd, SPECS[k], now + 1)
                    end
                end
            end
            if eligible and not early and not used then
                if (when == "later" and not W.combat) or (when ~= "later" and W.combat) then
                    watchAll()
                end
            end
            if when == "getters" or (used and (seed + n) % 2 == 0) then
                screen()
                local answers = {}
                if when == "getters" then
                    for k, spell in ipairs(SPELLS) do
                        getter()
                        local entries, read = lib:GetAuraEntries(spell)
                        local rec, parts, true_ = { read = read }, {}, {}
                        for _, e in ipairs(entries) do
                            parts[#parts + 1] = e.cooldownID .. "=" .. tostring(e.placement)
                        end
                        for _, id in ipairs(list and ordered(list) or {}) do
                            if names(list[id], spell) then
                                local p = ({ "bar", "icon", "essential", "utility" })[at[id] or 0]
                                true_[#true_ + 1] = id .. "=" .. tostring(p)
                            end
                        end
                        rec.text = table.concat(parts, ",")
                        if read and not lost and not offLast then
                            if unheld then
                                rec.false_ = "read while an item the list does not hold is shown"
                            elseif rec.text ~= table.concat(true_, ",") then
                                rec.false_ = "entries not the true ones"
                            end
                        end
                        rec.cause = unheld and "an item the list does not hold" or lost and "secret cooldownID" or nil
                        answers[#answers + 1] = rec
                        rec.k = k
                    end
                    local kind = lib:GetKinds()[9]
                    answers[#answers + 1] = { text = kind.state .. tostring(kind.reason) }
                end
                for k = 1, #SPECS do
                    local ok, state, why = lib:IsAvailable("aura", SPECS[k])
                    -- a getter reads only where the kind answers
                    local reads = state == "ready" or state == "pending" or not (why == "selftest" or why == "off")
                    if reads and why ~= "cdm-off" then
                        getter()
                    end
                    local rec = { text = tostring(ok) .. state .. tostring(why) }
                    local _, _, reason = entryOf(SPECS[k], list, at)
                    local placed = why == "not-in-cdm" or (why and why:find("^cdm%-") and why ~= "cdm-off")
                    if judging and not (lost or lostLast) and (placed or state == "ready") and W.cdm.enabled then
                        if unheld then
                            rec.false_ = "answered while an item the list does not hold is shown"
                        elseif
                            not (stale and not W.combat)
                            and reason ~= why
                            and not offLast
                            and (settled or not used)
                        then
                            -- (with a watch an answer can be a frame old: judged once a frame has run)
                            rec.false_ = "answered " .. state .. ":" .. tostring(why) .. ", not the true one"
                        end
                    end
                    rec.cause = unheld and "an item the list does not hold"
                        or (lost or lostLast or blind) and "secret cooldownID"
                        or retest and now <= retest and "the self-test run again at the upgrade"
                        or nil
                    answers[#answers + 1] = rec
                end
                asked[#asked + 1] = answers
            end
            if mid and n == 12 then
                W.secret = true -- an upgrade runs the self-test again: its prime must be secret
                mid()
                stale, poked, judging, relaid = true, true, true, now -- a load reads it as a login does
                retest = now + 50 -- a run takes 44 frames
                rows.from = #rows
            end
        end
        assert.are.same({}, Fake.errors, "seed " .. seed)
        assert.are.equal(0, twice, "seed " .. seed)
        assert.are.same({}, Fake.touched, "seed " .. seed)
        local marks = 0 -- MarkDirty on the icons, which minor 7 does not hook
        for _ in pairs(lib.cdm.marked or {}) do
            marks = marks + 1
        end
        assert.is_true(marks <= Fake.viewers[2].made, "seed " .. seed)
        return { rows = rows, asked = asked, hooks = Fake.hooks, marks = marks, watched = used }
    end

    -- Judges every seed of a mode; fails with each failing class, its seeds and its first place.
    local function differential(when, each)
        local failed, counted, ran, differing = {}, {}, 0, 0
        local function add(to, class, seed, place)
            local c = to[class]
            if not c then
                c = { seeds = 0, frames = 0, first = place, list = {} }
                to[class] = c
            end
            c.frames = c.frames + 1
            if c.seed ~= seed then
                c.seed, c.seeds = seed, c.seeds + 1
                c.list[#c.list + 1] = seed
            end
        end
        for seed = FROM, FROM + SEEDS - 1 do
            local seven, this
            if each then
                seven, this = each(seed)
            else
                seven, this = session(true, seed, when), session(false, seed, when)
            end
            ran = ran + (this.watched and 1 or 0)
            local from, differs = this.rows.from or 0, false
            assert.are.equal(#seven.rows, #this.rows, when .. " seed " .. seed)
            for f = from + 1, #this.rows do
                for k = 1, #SPECS do
                    local a, b = seven.rows[f][k], this.rows[f][k]
                    if b then
                        local place = ("seed %d, frame %d, watch %d: %s-%s %s:%s"):format(
                            seed,
                            f,
                            k,
                            tostring(b.lo),
                            tostring(b.hi),
                            b.state,
                            tostring(b.why)
                        )
                        if b.wrong then
                            add(failed, b.wrong, seed, place)
                        end
                        if b.sink then
                            add(failed, "the sink is not Get()", seed, place)
                        end
                        if a.lo ~= b.lo or a.hi ~= b.hi or a.state ~= b.state or a.why ~= b.why then
                            differs = true
                            local was = a.lo == nil and "unknown" or a.right and "right" or "wrong"
                            if b.false_ then
                                add(failed, "a placement answer " .. b.false_, seed, place)
                            elseif b.lo ~= nil and b.right then
                                add(counted, "right here, minor 7 " .. was, seed, place)
                            elseif b.lo == nil and was == "right" then
                                if b.cause then
                                    add(counted, "unknown here, minor 7 right: " .. b.cause, seed, place)
                                else
                                    add(failed, "unknown with no cause where minor 7 was right", seed, place)
                                end
                            elseif b.lo == nil then
                                local class = "unknown here, minor 7 " .. was .. (b.cause and ": " .. b.cause or "")
                                add(counted, class, seed, place)
                            end
                        end
                    end
                end
            end
            for n, answers in ipairs(this.asked) do
                for j, b in ipairs(answers) do
                    local place = ("seed %d, step %d, answer %d: %s"):format(seed, n, j, tostring(b.text))
                    if b.false_ then
                        add(failed, "a getter " .. b.false_, seed, place)
                    end
                    local a = seven.asked[n] and seven.asked[n][j]
                    if a and (a.text ~= b.text or a.read ~= b.read) then
                        differs = true
                        local pend = b.read == false or (b.text and b.text:find("pending", 1, true))
                        if pend and b.cause then
                            add(counted, "a getter not read here: " .. b.cause, seed, place)
                        elseif pend then
                            add(failed, "a getter not read with no cause", seed, place)
                        else
                            add(counted, "a getter true here, minor 7 another answer", seed, place)
                        end
                    end
                end
            end
            if when == "login" or when == "upgrade" then
                if seven.hooks ~= this.hooks - this.marks then
                    add(failed, "hooks", seed, seven.hooks .. " and " .. this.hooks)
                end
            elseif this.hooks - this.marks > seven.hooks or (when == "getters" and this.hooks > 0) then
                add(failed, "hooks", seed, seven.hooks .. " and " .. this.hooks)
            end
            differing = differing + (differs and 1 or 0)
        end
        local report = os.getenv("LHV_REPORT")
        if report then
            local out = assert(io.open(report, "a"))
            out:write(("%s from %d, %d seeds: %d differ, %d watched\n"):format(when, FROM, SEEDS, differing, ran))
            for tag, set in pairs({ FAILED = failed, counted = counted }) do
                for class, c in pairs(set) do
                    out:write(
                        ("  %s %s: %d seeds, %d frames, first %s\n"):format(tag, class, c.seeds, c.frames, c.first)
                    )
                    out:write("    seeds " .. table.concat(c.list, " ") .. "\n")
                end
            end
            out:close()
        end
        local summary = {}
        for class, c in pairs(failed) do
            summary[class] = ("%d seeds, %d frames, first %s"):format(c.seeds, c.frames, c.first)
        end
        assert.are.same({}, summary)
        if when ~= "getters" then
            assert.is_true(ran >= SEEDS / 2, "watched in " .. ran)
        end
    end

    local function needSeven()
        if not sevenSource() then
            pending("no minor 7 in this clone (git show " .. SEVEN .. ")")
            return false
        end
        return true
    end

    describe("differential with minor 7", function()
        it("judges by what the items show: a false 0 after an override ends fails, the true band passes", function()
            local shown = { -- the override ended: 15 shows its own spell, 21 shows 5005
                [15] = { spellID = 5015, category = 3 },
                [11] = { spellID = 5001, category = 3 },
                [21] = { spellID = 5005, category = 2 },
            }
            local at, auras = { [15] = 1, [11] = 1, [21] = 2 }, { [5005] = { stacks = 3 } }
            for what, bands in pairs({ up = { { 0, 0 }, { 1, 1 } }, stacks = { { 0, 2 }, { 3, math.huge } } }) do
                local spec = { spell = 5005, what = what }
                local cd = entryOf(spec, shown, at)
                local a = auraOf(shown[cd], auras)
                local snap = { n = a and a.stacks }
                assert.is_false(fits(what, bands[1][1], bands[1][2], snap))
                assert.is_true(fits(what, bands[2][1], bands[2][2], snap))
            end
        end)

        for when, name in pairs({
            login = "a watch made at login",
            later = "a first watch out of combat",
            combat = "a first watch in combat, a getter asked before it",
            cold = "a first watch in combat, nothing asked before it",
            getters = "the getters with no watch",
        }) do
            it(name .. ": true, or unknown for a named cause", function()
                if needSeven() then
                    differential(when)
                end
            end)
        end

        it("a watch over an upgrade from minor 7: true, or unknown for a named cause", function()
            if not needSeven() then
                return
            end
            -- beside it: the same code as a newer minor, its self-test run again as minor 8 does
            differential("upgrade", function(seed)
                local seven = session(true, seed, "login", function()
                    lib.stVerdict, lib.stLines = nil, nil
                    loadSeven(select(2, LibStub("LibHiddenValues-1.0")) + 1)
                    lib.capChanged()
                    lib:SelfTest()
                end)
                local before, after
                local this = session(true, seed, "login", function()
                    before = Fake.hooks
                    Fake.loadLibrary()
                    after = Fake.hooks
                end)
                assert.are.same({ "LibHiddenValues-1.0", MINOR }, { lib:GetVersion() })
                assert.are.equal(before, after)
                return seven, this
            end)
        end)
    end)

    describe("4: an upgrade from minor 7", function()
        it("that hooked, with a watch, in combat: carries on", function()
            if not needSeven() then
                return
            end
            boot(true)
            Fake.setAura("player", 5001, 2, 60)
            local h = lib:Watch("A", SPECS[1])
            Fake.login()
            W.combat = true
            Fake.tick(20)
            assert.are.equal(6, (h:Get()))
            local hooks = Fake.hooks
            Fake.loadLibrary()
            Fake.tick(80) -- the self-test again, then the bars
            assert.are.same({ "LibHiddenValues-1.0", MINOR }, { lib:GetVersion() })
            assert.are.equal("live", (h:State()))
            assert.are.equal(6, (h:Get()))
            assert.are.equal(hooks + 2, Fake.hooks) -- the two icons' MarkDirty, which minor 7 did not hook
            assert.are.equal(0, twice)
        end)

        it("that hooked, with a watch still waiting: the load itself reads and hooks nothing", function()
            if not needSeven() then
                return
            end
            boot(true, function()
                W.combat, W.cdm.secretId = true, true
            end)
            lib:Watch("A", SPECS[1])
            Fake.login()
            W.combat = false
            Fake.event("PLAYER_REGEN_ENABLED")
            Fake.tick(5) -- a list, and the items' identities still secret: never placed
            local hooks, reads = Fake.hooks, seen.catalogue
            Fake.loadLibrary()
            assert.are.equal(hooks, Fake.hooks)
            assert.are.equal(reads, seen.catalogue)
            Fake.tick(1)
            assert.are.equal(hooks + 2, Fake.hooks) -- the icons' MarkDirty, on the first frame
        end)

        it(
            "that hooked, with no watch: adds no hook and one catalogue read until one is made, then none twice",
            function()
                if not needSeven() then
                    return
                end
                boot(true)
                Fake.login()
                assert.are.equal(14, Fake.hooks) -- minor 7's login
                Fake.loadLibrary()
                seen.items, seen.catalogue = 0, 0
                local c = { [16] = { spellID = 5006, category = 3 } } -- the bar's third, as the client has it
                for id, e in pairs(CATALOGUE) do
                    c[id] = e
                end
                W.cdm.catalogue = c
                W.cdm.bar = { 11, 15, 16 }
                Fake.cdmLayout()
                Fake.tick(3)
                Fake.event("PLAYER_REGEN_ENABLED")
                Fake.tick(3)
                assert.are.same({ "LibHiddenValues-1.0", MINOR }, { lib:GetVersion() })
                assert.are.equal(14, Fake.hooks)
                assert.are.same({ items = 0, catalogue = 1 }, seen) -- a load reads it as a login does
                Fake.setAura("player", 5001, 2, 30)
                W.combat = true -- known: a first watch in combat answers
                local h = lib:Watch("A", SPECS[1])
                Fake.tick(80) -- the self-test again, then the bars
                assert.are.equal(6, (h:Get()))
                assert.are.equal(18, Fake.hooks) -- the new bar item's two, the icons' MarkDirty
                assert.are.equal(0, twice)
            end
        )

        describe("the self-test verdict", function()
            local function over(secret, closed, midRun)
                boot(true, function()
                    W.secret = secret
                    if closed then
                        Fake.set("closed", true)
                    end
                end)
                local h = lib:Watch("A", { kind = "health", unit = "target", step = 1 })
                if midRun then
                    Fake.event("PLAYER_LOGIN")
                    Fake.tick(15) -- minor 7's run, past its prime's plain push
                    W.secret = true
                else
                    Fake.login()
                    Fake.tick(20)
                end
                local old, told = lib:GetSelfTest(), {}
                lib:OnCapability("A", function(kind, state, reason)
                    if kind == "health" then
                        told[#told + 1] = state .. ":" .. tostring(reason)
                    end
                end)
                Fake.loadLibrary()
                assert.are.equal("pending", (h:State())) -- what minor 7 found does not stand
                assert.is_nil((lib:GetSelfTest()))
                Fake.tick(80)
                return old, lib:GetSelfTest(), h, told
            end

            it("a pass on a plain prime does not stand: run again, it fails", function()
                if not needSeven() then
                    return
                end
                local old, new, h, told = over(false, true)
                assert.is_true(old)
                assert.is_false(new)
                assert.is_nil((h:Get()))
                assert.are.same({ "pending:nil", "unavailable:selftest" }, told)
            end)

            it("a secret pass is run again and passes", function()
                if not needSeven() then
                    return
                end
                local old, new, h, told = over(true, false)
                assert.is_true(old)
                assert.is_true(new)
                assert.are.equal(70, (h:Get()))
                assert.are.same({ "pending:nil", "ready:nil" }, told)
            end)

            it("a run it left is started again: no bar lost, no pass on its plain push", function()
                if not needSeven() then
                    return
                end
                local _, new, h = over(false, true, true)
                assert.is_false(new)
                assert.is_nil((h:Get()))
                assert.are.equal(0, (lib:GetStats()))
            end)

            it("switched off: stays off, then tests when switched on", function()
                if not needSeven() then
                    return
                end
                boot(true)
                Fake.login()
                lib:SetEnabled(false)
                Fake.loadLibrary()
                Fake.tick(5)
                assert.are.same({ false, "unavailable", "off" }, { lib:IsAvailable("health") })
                lib:SetEnabled(true)
                Fake.tick(60)
                assert.are.same({ true, "ready" }, { lib:IsAvailable("health") })
            end)

            it("this minor's own verdict stands over a newer minor", function()
                boot()
                Fake.login()
                Fake.loadLibrary(MINOR + 1)
                assert.is_true((lib:GetSelfTest()))
                assert.is_false((select(3, lib:GetSelfTest())))
            end)
        end)

        it("before login with no watch: stays lazy", function()
            if not needSeven() then
                return
            end
            boot(true)
            lib:Watch("A", { kind = "health", unit = "player", edges = { 50 } })
            Fake.loadLibrary()
            Fake.login()
            assert.are.same({ "LibHiddenValues-1.0", MINOR }, { lib:GetVersion() })
            untouched()
            churn(untouched)
        end)

        it("before login with an aura watch: installs after login", function()
            if not needSeven() then
                return
            end
            boot(true)
            local h = lib:Watch("A", SPECS[2])
            Fake.loadLibrary()
            assert.are.equal(0, Fake.hooks)
            Fake.login()
            assert.are.equal(16, Fake.hooks)
            assert.are.equal("live", (h:State()))
        end)
    end)
end)
