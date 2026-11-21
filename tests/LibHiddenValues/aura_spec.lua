-- tests/LibHiddenValues/aura_spec.lua: the aura kind read from the fake client's Cooldown Manager. A watch resolves to
-- the item that shows its spell (each reason when none can serve it), presence from the item, stacks from its count
-- text, seconds left from its tracked bar (a fall through each edge, a refresh, the expiry), a reshuffle of the pooled
-- frames in combat (plain, secret cooldownID, both secret), a target swap without priming, the Cooldown Manager turned
-- off and on mid-session, nothing of the Cooldown Manager's touched, a freed aura bar reused by another kind, an error
-- kept to the aura kind, secret safety and no allocation in steady frames.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"

-- cooldownIDs 11-16 name spells 5001-5006 (5013 is 13's linked spell); placed: 11 and 15 bars, 12 and 13 icons.
local CATALOGUE = {
    [11] = { spellID = 5001, category = 3 },
    [12] = { spellID = 5002, category = 2 },
    [13] = { spellID = 5003, category = 2, linkedSpellIDs = { 5013 } },
    [14] = { spellID = 5004, category = 0 },
    [15] = { spellID = 5005, category = 3 },
    [16] = { spellID = 5006, category = 3 },
}

describe("LibHiddenValues aura kind", function()
    local Fake, W, lib, calls

    local function sink(h, lo, hi, dir, t, q)
        calls[#calls + 1] = { lo = lo, hi = hi, dir = dir, q = q }
    end

    local function band(h)
        local lo, hi = h:Get()
        return { lo, hi }
    end

    local function last()
        local c = calls[#calls]
        return c and { c.lo, c.hi, c.dir }
    end

    local function boot(setup)
        Fake = dofile(FAKE)
        W = Fake.world
        lib = LibStub("LibHiddenValues-1.0")
        W.cdm.catalogue = CATALOGUE
        W.cdm.bar = { 11, 15 }
        W.cdm.icon = { 12, 13 }
        if setup then
            setup()
        end
    end

    local function watch(spec)
        spec.kind = "aura"
        spec.unit = spec.unit or "player"
        return assert(lib:Watch("A", spec, sink))
    end

    local function av(spec)
        spec.kind = "aura"
        spec.unit = spec.unit or "player"
        return { lib:IsAvailable("aura", spec) }
    end

    before_each(function()
        calls = {}
    end)

    after_each(function()
        assert.are.same({}, Fake.touched)
        Fake.restore()
    end)

    it("resolves a watch to the item that shows it and answers each reason", function()
        boot()
        assert.are.same({ false, "pending" }, av({ spell = 5001, what = "up" }))
        local left = watch({ spell = 5001, what = "left", edges = { 3 } })
        local iconLeft = watch({ spell = 5002, what = "left", edges = { 3 } })
        local iconStacks = watch({ spell = 5002, what = "stacks", max = 3 })
        local linked = watch({ spell = 5013, what = "up" })
        local essential = watch({ spell = 5004, what = "up" })
        local nowhere = watch({ spell = 9999, what = "up" })
        local hidden = watch({ spell = 5006, what = "stacks", edges = { 2 } })
        assert.are.equal("pending", (left:State()))
        assert.is_true(Fake.login())
        Fake.tick(2)
        assert.are.same({ true, "ready" }, av({ spell = 5001, what = "left", edges = { 3 } }))
        assert.are.same({ false, "unavailable", "cdm-icon-only" }, av({ spell = 5002, what = "left", edges = { 3 } }))
        assert.are.same({ true, "ready" }, av({ spell = 5002, what = "stacks", max = 3 }))
        assert.are.same({ true, "ready" }, av({ spell = 5002, what = "up" }))
        assert.are.same({ true, "ready" }, av({ spell = 5013, what = "up" }))
        assert.are.same({ false, "unavailable", "cdm-not-tracked" }, av({ spell = 5004, what = "up" }))
        assert.are.same({ false, "unavailable", "cdm-not-tracked" }, av({ spell = 5006, what = "up" }))
        assert.are.same({ false, "unavailable", "not-in-cdm" }, av({ spell = 9999, what = "up" }))
        assert.are.same({ false, "unavailable", "bad-spec" }, av({ spell = 5001, what = "sideways" }))
        assert.are.equal("priming", (left:State()))
        Fake.tick(8)
        assert.are.equal("live", (left:State()))
        assert.are.same({ "unavailable", "cdm-icon-only" }, { iconLeft:State() })
        assert.are.equal("live", (linked:State()))
        assert.are.same({ "unavailable", "cdm-not-tracked" }, { essential:State() })
        assert.are.same({ "unavailable", "not-in-cdm" }, { nowhere:State() })
        assert.are.same({ "unavailable", "cdm-not-tracked" }, { hidden:State() })
        assert.truthy(iconStacks:State())
        local rows, off, read = lib:GetAuraSources()
        assert.are.equal(7, #rows)
        assert.is_false(off)
        assert.is_true(read)
        assert.are.same(
            { 5001, "left", 11, "bar" },
            { rows[1].spell, rows[1].what, rows[1].cooldownID, rows[1].placement }
        )
        assert.are.same({ 12, "icon", "cdm-icon-only" }, { rows[2].cooldownID, rows[2].placement, rows[2].reason })
        assert.are.same({ 13, "icon" }, { rows[4].cooldownID, rows[4].placement })
        assert.are.same({ "unavailable", "not-in-cdm" }, { rows[6].state, rows[6].reason })
        -- the player places 16 as a tracked bar: the answer changes, the owner hears it per handle
        local told = {}
        lib:OnCapability("A", function(kind, state, reason, h)
            told[#told + 1] = { kind, state, reason, h }
        end)
        W.cdm.bar = { 11, 15, 16 }
        Fake.cdmLayout()
        Fake.tick(2)
        assert.are.same({ { "aura", "ready", nil, hidden } }, told)
        assert.are.same({ true, "ready" }, av({ spell = 5006, what = "stacks", edges = { 2 } }))
        assert.are.equal("priming", (hidden:State()))
        Fake.tick(8)
        assert.are.same({ "live", nil }, { hidden:State() })
        assert.are.same({}, Fake.errors)
    end)

    it("rejects bad specs and keeps other tokens unproven", function()
        boot()
        local function bad(spec)
            spec.kind = "aura"
            local h, err = lib:Watch("A", spec)
            assert.is_nil(h)
            return err
        end
        local E = lib.ERR
        assert.are.equal(E.UNIT_INVALID, bad({ unit = 7, spell = 5001, what = "up" }))
        assert.are.equal(E.WHAT_INVALID, bad({ unit = "player", spell = 5001 }))
        assert.are.equal(E.SPELL_INVALID, bad({ unit = "player", spell = "x", what = "up" }))
        assert.are.equal(E.SPELL_OR_COOLDOWN, bad({ unit = "player", what = "up" }))
        assert.are.equal(E.SPELL_OR_COOLDOWN, bad({ unit = "player", spell = 5001, cooldown = 11, what = "up" }))
        assert.are.equal(E.COOLDOWN_INVALID, bad({ unit = "player", cooldown = 1.5, what = "up" }))
        assert.are.equal(E.COOLDOWN_INVALID, bad({ unit = "player", cooldown = "11", what = "up" }))
        assert.are.equal(E.COOLDOWN_INVALID, bad({ unit = "player", cooldown = 0, what = "up" }))
        assert.is_string(lib:GetMessage(E.SPELL_OR_COOLDOWN))
        assert.is_string(lib:GetMessage(E.COOLDOWN_INVALID))
        assert.are.equal(E.EDGES_INVALID, bad({ unit = "player", spell = 5001, what = "up", edges = 3 }))
        assert.are.equal(E.MAX_INVALID, bad({ unit = "player", spell = 5001, what = "stacks", max = 0 }))
        assert.are.equal(E.EDGES_REQUIRED, bad({ unit = "player", spell = 5001, what = "stacks" }))
        assert.are.equal(E.EDGES_INVALID, bad({ unit = "player", spell = 5001, what = "stacks", edges = { 1.5 } }))
        assert.are.equal(E.EDGES_INVALID, bad({ unit = "player", spell = 5001, what = "left", edges = { "3" } }))
        local over = { unit = "player", spell = 5001, what = "stacks", max = 3, edges = { 4 } }
        assert.are.equal(E.EDGES_OUT_OF_RANGE, bad(over))
        assert.are.equal(E.EDGES_OUT_OF_RANGE, bad({ unit = "player", spell = 5001, what = "stacks", edges = { 0 } }))
        assert.are.equal(E.EDGES_REQUIRED, bad({ unit = "player", spell = 5001, what = "left" }))
        assert.are.equal(E.EDGES_OUT_OF_RANGE, bad({ unit = "player", spell = 5001, what = "left", edges = { 0 } }))
        local h = watch({ unit = "focus", spell = 5001, what = "up" })
        assert.are.same({ "unavailable", "unproven" }, { h:State() })
        local s = watch({ spell = 5001, what = "stacks", max = 4 })
        assert.are.same({ nil, 0, 4 }, { s:Domain() })
        local l = watch({ spell = 5001, what = "left", edges = { 6, 3, 3 } })
        assert.are.same({ 3, 6 }, l.edges)
        assert.are.equal(math.huge, select(3, l:Domain()))
    end)

    it("watches one entry by its cooldownID: no entry choice, each reason for that entry", function()
        boot(function()
            local c = {}
            for id, e in pairs(CATALOGUE) do
                c[id] = e
            end
            c[17] = { spellID = 5001, category = 2 } -- a second entry naming 5001, an icon
            W.cdm.catalogue, W.cdm.icon = c, { 12, 13, 17 }
        end)
        assert.are.same({ false, "pending" }, av({ cooldown = 17, what = "up" }))
        local bySpell = watch({ spell = 5001, what = "left", edges = { 3 } })
        local left = watch({ cooldown = 17, what = "left", edges = { 3 } })
        local up = watch({ cooldown = 17, what = "up" })
        local stacks = watch({ cooldown = 17, what = "stacks", max = 3 })
        local unplaced = watch({ cooldown = 16, what = "up" })
        local nowhere = watch({ cooldown = 99, what = "up" })
        local same = watch({ cooldown = 11, what = "up" }) -- cooldownID 11 and spell 11 are two sources
        local spell11 = watch({ spell = 11, what = "up" })
        Fake.login()
        Fake.tick(2 + lib.SETTLE + lib.HOLD)
        assert.are.same({ true, "ready" }, av({ spell = 5001, what = "left", edges = { 3 } }))
        assert.are.same({ false, "unavailable", "cdm-icon-only" }, av({ cooldown = 17, what = "left", edges = { 3 } }))
        assert.are.same({ true, "ready" }, av({ cooldown = 17, what = "up" }))
        assert.are.same({ false, "unavailable", "cdm-not-tracked" }, av({ cooldown = 16, what = "up" }))
        assert.are.same({ false, "unavailable", "not-in-cdm" }, av({ cooldown = 99, what = "up" }))
        assert.are.equal("live", (bySpell:State()))
        assert.are.same({ "unavailable", "cdm-icon-only" }, { left:State() })
        assert.are.same({ "unavailable", "cdm-not-tracked" }, { unplaced:State() })
        assert.are.same({ "unavailable", "not-in-cdm" }, { nowhere:State() })
        assert.are.same({ "unavailable", "not-in-cdm" }, { spell11:State() })
        assert.are.equal("live", (same:State()))
        assert.are.same({ 0, 0 }, band(up))
        Fake.setAura("player", 5001, 2)
        Fake.tick(2 + lib.SETTLE)
        assert.are.same({ 1, 1 }, band(up))
        assert.are.same({ 2, 3 }, band(stacks))
        local rows = lib:GetAuraSources()
        assert.are.same(
            { nil, 17, 17, "icon", "cdm-icon-only" },
            { rows[2].spell, rows[2].cooldown, rows[2].cooldownID, rows[2].placement, rows[2].reason }
        )
        assert.are.same(
            { 5001, nil, 11, "bar" },
            { rows[1].spell, rows[1].cooldown, rows[1].cooldownID, rows[1].placement }
        )
        assert.are.same({ 16, nil }, { rows[5].cooldown, rows[5].cooldownID })
        assert.are.equal(8, #rows)
        -- entry 17 leaves the layout: its watches go, though entry 11 still shows the aura
        W.cdm.icon = { 12, 13 }
        Fake.cdmLayout()
        Fake.tick(2)
        assert.are.same({ "unavailable", "cdm-not-tracked" }, { up:State() })
        assert.is_nil(band(up)[1])
        assert.are.same({ 1, 1 }, band(same))
        assert.are.same({}, Fake.errors)
    end)

    it("reads up from Essential and Utility items; stacks and left need an aura viewer", function()
        boot(function()
            local c = {}
            for id, e in pairs(CATALOGUE) do
                c[id] = e
            end
            c[18] = { spellID = 5008, category = 1 } -- a Utility cooldown naming its aura
            c[19] = { spellID = 5001, category = 0 } -- an Essential entry naming 5001, also on a bar (11)
            W.cdm.catalogue, W.cdm.essential, W.cdm.utility = c, { 14, 19 }, { 18 }
        end)
        local ess = watch({ spell = 5004, what = "up" })
        local essStacks = watch({ spell = 5004, what = "stacks", max = 3 })
        local uti = watch({ unit = "target", spell = 5008, what = "up" })
        local byId = watch({ cooldown = 14, what = "up" })
        local both = watch({ spell = 5001, what = "up" })
        Fake.login()
        W.combat = true
        Fake.tick(2)
        assert.are.same({ true, "ready" }, av({ spell = 5004, what = "up" }))
        local only = { false, "unavailable", "cdm-cooldown-only" }
        assert.are.same(only, av({ spell = 5004, what = "stacks", max = 3 }))
        assert.are.same(only, av({ spell = 5004, what = "left", edges = { 3 } }))
        assert.are.same(only, av({ cooldown = 18, what = "left", edges = { 3 } }))
        assert.are.same({ "unavailable", "cdm-cooldown-only" }, { essStacks:State() })
        assert.is_string(lib:GetMessage("cdm-cooldown-only"))
        assert.are.same({ 0, 0 }, band(ess))
        assert.are.same({ 0, 0 }, band(uti))
        Fake.setAura("player", 5004, 1)
        Fake.setAura("target", 5008, 1)
        Fake.setAura("player", 5001, 1)
        Fake.tick(2)
        assert.are.same({ 1, 1 }, band(ess))
        assert.are.same({ 1, 1 }, band(byId))
        assert.are.same({ 1, 1 }, band(uti))
        assert.are.same({ 1, 1 }, band(both))
        local rows = lib:GetAuraSources()
        assert.are.same({ 14, "essential" }, { rows[1].cooldownID, rows[1].placement })
        assert.are.same({ 18, "utility" }, { rows[3].cooldownID, rows[3].placement })
        assert.are.same({ 11, "bar" }, { rows[5].cooldownID, rows[5].placement }) -- an aura viewer's entry first
        -- a hidden Essential viewer: its watches are unknown, the others carry on
        _G.EssentialCooldownViewer.shown = false
        Fake.tick(2)
        assert.are.same({ "gone", nil }, { ess:State() })
        assert.are.same({ 1, 1 }, band(uti))
        _G.EssentialCooldownViewer.shown = true
        Fake.setAura("player", 5004, nil)
        Fake.tick(2)
        assert.are.same({ 0, 0 }, band(ess))
        assert.are.same({}, Fake.errors)
    end)

    it("reports presence: 0 absent, 1 up, unknown when no item shows it", function()
        boot()
        local h = watch({ spell = 5001, what = "up" })
        Fake.login()
        Fake.tick(2)
        assert.are.same({ 0, 0 }, band(h))
        Fake.setAura("player", 5001, 1, 20)
        Fake.tick(2)
        assert.are.same({ 1, 1, 1 }, last())
        Fake.setAura("player", 5001, nil)
        Fake.tick(2)
        assert.are.same({ 0, 0, -1 }, last())
        W.cdm.bar = { 15 }
        Fake.cdmLayout()
        Fake.tick(2)
        assert.are.same({ "unavailable", "cdm-not-tracked" }, { h:State() })
        assert.is_nil(last()[1])
        assert.are.same({}, Fake.errors)
    end)

    it("bands stacks in combat from the count text, the lowest band while the aura is absent", function()
        boot()
        local h = watch({ spell = 5001, what = "stacks", edges = { 2, 4 } })
        local exact = watch({ spell = 5001, what = "stacks", max = 5 })
        Fake.login()
        W.combat = true
        Fake.tick(10)
        assert.are.same({ 0, 2 }, band(h))
        assert.are.same({ 0, 1 }, band(exact))
        Fake.setAura("player", 5001, 1)
        Fake.tick(2 + lib.SETTLE) -- the first count after an absence settles; the band before it stands meanwhile
        assert.are.same({ 0, 2 }, band(h))
        assert.are.same({ 1, 2 }, band(exact))
        Fake.setAura("player", 5001, 3)
        Fake.tick(2)
        assert.are.same({ 2, 4 }, band(h))
        assert.are.same({ 3, 4 }, band(exact))
        Fake.setAura("player", 5001, 5)
        Fake.tick(2)
        assert.are.same({ 4, math.huge }, band(h))
        assert.are.same({ 5, 5 }, band(exact))
        Fake.setAura("player", 5001, 2)
        Fake.tick(2)
        assert.are.same({ 2, 4 }, band(h))
        assert.are.same({ 2, 3 }, band(exact))
        Fake.setAura("player", 5001, nil)
        Fake.tick(2)
        assert.are.same({ 0, 2 }, band(h))
        assert.are.same({ 0, 1 }, band(exact))
        assert.are.same({}, Fake.errors)
    end)

    it("keeps a stacks watch made while the aura is up priming until the next count", function()
        boot()
        Fake.setAura("player", 5001, 3)
        Fake.login()
        W.combat = true
        Fake.tick(2)
        local h = watch({ spell = 5001, what = "stacks", edges = { 2 } })
        Fake.tick(20)
        assert.are.equal("priming", (h:State())) -- no count written since the watch: no band
        assert.is_nil(band(h)[1])
        Fake.setAura("player", 5001, 4)
        Fake.tick(2 + lib.SETTLE)
        assert.are.equal("live", (h:State()))
        assert.are.same({ 2, math.huge }, band(h))
    end)

    it("bands seconds left in combat from the tracked bar: each fall, a refresh, the expiry", function()
        -- the timer starts at 21 offsets inside one frame, so some falls land inside a bar for a frame
        for k = 0, 20 do
            boot()
            local h = watch({ spell = 5001, what = "left", edges = { 3, 6 } })
            Fake.login()
            W.combat = true
            Fake.tick(2)
            Fake.setAura("player", 5001, 1, 9 + k / 20 / 60)
            Fake.tick(12)
            assert.are.same({ 6, math.huge }, band(h), k)
            calls = {}
            Fake.advance(7)
            assert.are.same({ { 3, 6, -1 }, { 0, 3, -1 } }, {
                { calls[1].lo, calls[1].hi, calls[1].dir },
                { calls[2].lo, calls[2].hi, calls[2].dir },
            }, k)
            assert.are.equal(2, #calls, k)
            Fake.setAura("player", 5001, 1, 5)
            Fake.tick(3)
            assert.are.same({ 3, 6, 1 }, last(), k)
            Fake.advance(6)
            assert.are.same({ 0, 3 }, band(h), k) -- expired: no seconds left
            assert.is_nil(W.aura.player[5001])
            assert.are.equal(0, lib.desyncs, k)
            assert.are.same({}, Fake.errors)
            assert.are.same({}, Fake.touched)
            Fake.restore()
        end
        boot()
    end)

    it("ends above the edge after a refresh on any frame around a fall through it", function()
        -- a clean fall at one frame and a jump back at the next fire like a fall that lands inside the bar
        for k = 0, 4 do
            for d = -3, 3 do
                boot()
                local h = watch({ spell = 5001, what = "left", edges = { 3 } })
                Fake.login()
                W.combat = true
                Fake.tick(8)
                Fake.setAura("player", 5001, 1, 9 + k / 5 / 60)
                Fake.tick(360 + d)
                Fake.setAura("player", 5001, 1, 9)
                Fake.tick(10)
                local tag = k .. "/" .. d
                assert.are.same({ 3, math.huge }, band(h), tag)
                Fake.advance(6.5)
                assert.are.same({ 0, 3 }, band(h), tag)
                assert.are.same({}, Fake.errors)
                assert.are.same({}, Fake.touched)
                Fake.restore()
            end
        end
        boot()
    end)

    it("keeps up ready when only the bar self-test fails or is pending; stacks and left wait for it", function()
        boot()
        Fake.set("drop", 1) -- every firing lost: the self-test fails
        local up = watch({ spell = 5001, what = "up" })
        local st = watch({ spell = 5001, what = "stacks", max = 3 })
        Fake.event("PLAYER_LOGIN")
        Fake.tick(3)
        assert.is_nil(lib.stVerdict) -- the self-test is still running: up does not wait for it
        assert.are.same({ "pending", nil }, { st:State() })
        assert.are.same({ "live", nil }, { up:State() })
        assert.is_false(Fake.login())
        Fake.tick(2)
        assert.are.same({ false, "unavailable", "selftest" }, { lib:IsAvailable("aura") })
        assert.are.same({ true, "ready" }, av({ spell = 5001, what = "up" }))
        assert.are.same({ false, "unavailable", "selftest" }, av({ spell = 5001, what = "stacks", max = 3 }))
        assert.are.same({ false, "unavailable", "selftest" }, av({ spell = 5001, what = "left", edges = { 3 } }))
        assert.are.same({ "unavailable", "selftest" }, { st:State() })
        assert.are.same({ "live", nil }, { up:State() })
        assert.are.same({ 0, 0 }, band(up))
        Fake.setAura("player", 5001, 2)
        Fake.tick(2)
        assert.are.same({ 1, 1 }, band(up))
        assert.is_nil(band(st)[1])
        local rows = lib:GetAuraSources()
        assert.are.same({ "ready", "unavailable", "selftest" }, { rows[1].state, rows[2].state, rows[2].reason })
        -- every other failure still takes up down: off, then on again (a fresh self-test, failing again)
        lib:SetEnabled(false)
        assert.are.same({ "unavailable", "off" }, { up:State() })
        assert.are.same({ false, "unavailable", "off" }, av({ spell = 5001, what = "up" }))
        lib:SetEnabled(true)
        Fake.tick(2)
        assert.are.same({ "live", nil }, { up:State() })
        assert.are.same({ 1, 1 }, band(up))
        Fake.cdmEnable(false)
        Fake.tick(2)
        assert.are.same({ "unavailable", "cdm-off" }, { up:State() })
        Fake.cdmEnable(true)
        Fake.tick(10)
        assert.are.same({ "live", nil }, { up:State() })
        Fake.set("refuse", "InCombatLockdown")
        Fake.event("COOLDOWN_VIEWER_DATA_LOADED")
        Fake.tick(2)
        assert.are.same({ "unavailable", "error" }, { up:State() })
        assert.are.equal(1, #Fake.errors)
    end)

    it("keeps up unavailable with reason api when the Cooldown Manager API is missing", function()
        boot()
        Fake.set("drop", 1)
        rawset(_G, "C_CooldownViewer", nil)
        local up = watch({ spell = 5001, what = "up" })
        Fake.login()
        Fake.tick(2)
        assert.are.same({ "unavailable", "api" }, { up:State() })
        assert.are.same({ false, "unavailable", "api" }, av({ spell = 5001, what = "up" }))
    end)

    it("does not call the capability callback inside Watch", function()
        boot()
        local told = {}
        lib:OnCapability("A", function(kind, state, reason, x)
            told[#told + 1] = { kind, state, reason, x }
        end)
        Fake.login()
        Fake.tick(2)
        told = {}
        local h = watch({ spell = 5001, what = "up" })
        local n = watch({ spell = 9999, what = "up" })
        assert.are.same({}, told)
        assert.are.equal("priming", (h:State())) -- no band yet: presence is read next frame, decoded the one after
        Fake.tick(2)
        assert.are.equal("live", (h:State()))
        assert.are.same({ "unavailable", "not-in-cdm" }, { n:State() })
        Fake.tick(3)
        assert.are.same({}, told)
    end)

    it("follows a reshuffle of the pooled frames in combat: plain, secret cooldownID, both secret", function()
        boot()
        Fake.setAura("player", 5001, 2)
        Fake.setAura("player", 5005, 4)
        local h = watch({ spell = 5001, what = "stacks", edges = { 3 } })
        local up = watch({ spell = 5001, what = "up" })
        Fake.login()
        W.combat = true
        Fake.tick(8) -- past the new bars' hold
        Fake.setAura("player", 5001, 2)
        Fake.tick(2 + lib.SETTLE)
        assert.are.same({ 0, 3 }, band(h))
        local before = {}
        for item in pairs(Fake.viewers[1].itemFramePool.active) do
            before[item] = item.cd
        end
        W.cdm.shuffle = true
        Fake.cdmLayout()
        local moved = 0
        for item in pairs(Fake.viewers[1].itemFramePool.active) do
            moved = moved + ((before[item] ~= item.cd) and 1 or 0)
        end
        assert.is_true(moved > 0)
        Fake.tick(2)
        assert.are.same({ 0, 3 }, band(h))
        Fake.setAura("player", 5001, 3)
        Fake.tick(2)
        assert.are.same({ 3, math.huge }, band(h))
        -- the cooldownID reads secret: the layoutIndex read plain before maps it
        W.cdm.secretId = true
        Fake.cdmLayout()
        Fake.setAura("player", 5001, 2)
        Fake.tick(2)
        assert.are.same({ 0, 3 }, band(h))
        assert.are.same({ 1, 1 }, band(up))
        -- both secret: the item is lost until the layout reads plain again
        W.cdm.secretIdx = true
        Fake.cdmLayout()
        Fake.tick(2)
        assert.are.equal("gone", (h:State()))
        assert.is_nil(band(h)[1])
        assert.is_nil(band(up)[1])
        W.combat, W.cdm.secretId, W.cdm.secretIdx = false, false, false
        Fake.event("PLAYER_REGEN_ENABLED")
        Fake.cdmLayout()
        Fake.tick(2 + lib.SETTLE)
        assert.are.same({ 1, 1 }, band(up))
        assert.are.same({ 0, 3 }, band(h))
        assert.are.same({}, Fake.errors)
    end)

    it("follows a target swap without priming", function()
        boot()
        W.aura.target = { [5002] = { stacks = 3, duration = 30, expires = GetTime() + 30 } }
        local h = watch({ unit = "target", spell = 5002, what = "stacks", edges = { 2, 4 } })
        local mine = watch({ unit = "player", spell = 5002, what = "up" })
        Fake.login()
        W.combat = true
        Fake.tick(8) -- past the new bars' hold
        Fake.event("UNIT_AURA", "target")
        Fake.tick(2 + lib.SETTLE)
        assert.are.same({ 2, 4 }, band(h))
        assert.are.same({ 0, 0 }, band(mine)) -- shown, but on the target
        local first = W.aura.target
        W.aura.target = {}
        Fake.event("PLAYER_TARGET_CHANGED")
        Fake.tick(2)
        assert.are.same({ 0, 2 }, band(h)) -- absent: no stacks
        assert.are.equal("live", (h:State()))
        W.aura.target = first
        Fake.event("PLAYER_TARGET_CHANGED")
        local seen = {}
        for _ = 1, 2 + lib.SETTLE do
            Fake.tick(1)
            if h:State() ~= "live" then
                seen[#seen + 1] = h:State()
            end
        end
        assert.are.same({}, seen) -- never priming: the band before the swap stands while the count settles
        assert.are.same({ 2, 4 }, band(h))
    end)

    it("reads a watch unknown while its item's unit is secret, never as this unit", function()
        boot()
        W.cdm.secretUnit = true
        Fake.setAura("target", 5002, 1)
        local mine = watch({ unit = "player", spell = 5002, what = "up" })
        local theirs = watch({ unit = "target", spell = 5002, what = "up" })
        Fake.login()
        W.combat = true
        Fake.tick(2)
        assert.are.same({ "gone", nil }, { mine:State() })
        assert.are.same({ "gone", nil }, { theirs:State() })
        assert.is_nil(band(mine)[1])
        assert.is_nil(band(theirs)[1])
        Fake.setAura("target", 5002, nil) -- absent: a known value, no unit to read
        Fake.tick(2)
        assert.are.same({ 0, 0 }, band(mine))
        assert.are.same({ 0, 0 }, band(theirs))
        W.cdm.secretUnit = false
        Fake.setAura("target", 5002, 1)
        Fake.tick(2)
        assert.are.same({ 0, 0 }, band(mine))
        assert.are.same({ 1, 1 }, band(theirs))
        assert.are.same({}, Fake.errors)
    end)

    it("turns off with the Cooldown Manager mid-session and comes back", function()
        boot()
        local h = watch({ spell = 5001, what = "stacks", edges = { 2 } })
        local told = {}
        lib:OnCapability("A", function(kind, state, reason, x)
            told[#told + 1] = { kind, state, reason, x ~= nil }
        end)
        Fake.login()
        W.combat = true
        Fake.tick(8) -- past the new bars' hold
        Fake.setAura("player", 5001, 3)
        Fake.tick(2 + lib.SETTLE)
        assert.are.same({ 2, math.huge }, band(h))
        told = {}
        Fake.cdmEnable(false)
        Fake.tick(2)
        assert.are.same({ false, "unavailable", "cdm-off" }, { lib:IsAvailable("aura") })
        assert.are.same({ false, "unavailable", "cdm-off" }, av({ spell = 5001, what = "up" }))
        assert.are.same({ "unavailable", "cdm-off" }, { h:State() })
        assert.is_nil(last()[1])
        assert.are.same(
            { { "aura", "unavailable", "cdm-off", false }, { "aura", "unavailable", "cdm-off", true } },
            told
        )
        Fake.setAura("player", 5001, 1)
        Fake.cdmEnable(true)
        Fake.tick(10)
        assert.are.same({ true, "ready" }, { lib:IsAvailable("aura") })
        Fake.setAura("player", 5001, 4)
        Fake.tick(2 + lib.SETTLE)
        assert.are.same({ 2, math.huge }, band(h))
        assert.are.same({}, Fake.errors)
    end)

    it("answers cdm-off at login when the client says the viewer is not available", function()
        boot(function()
            W.cdm.available = false
        end)
        local h = watch({ spell = 5001, what = "up" })
        Fake.login()
        Fake.tick(2)
        assert.are.same({ "unavailable", "cdm-off" }, { h:State() })
        local kinds = lib:GetKinds()
        assert.are.same({ kind = "aura", state = "unavailable", reason = "cdm-off" }, kinds[9])
    end)

    it("hooks each widget once and touches nothing of the Cooldown Manager's", function()
        boot()
        W.cdm.essential = { 14 }
        watch({ spell = 5004, what = "up" })
        watch({ spell = 5001, what = "stacks", edges = { 2 } })
        watch({ spell = 5001, what = "left", edges = { 3 } })
        watch({ spell = 5002, what = "up" })
        Fake.login()
        W.combat = true
        for _ = 1, 3 do
            Fake.setAura("player", 5001, 2, 5)
            Fake.cdmLayout()
            Fake.advance(1)
        end
        -- 4 viewers (acquire, RefreshData), 2 bar items (count + bar), 2 icon items (count); Essential and Utility
        -- items none (presence is a field read)
        assert.are.equal(4 * 2 + 2 * 2 + 2, Fake.hooks)
        for _, v in ipairs(Fake.viewers) do
            assert.is_true(v.shown)
            assert.is_nil(v.alpha)
        end
        assert.are.same({}, Fake.touched)
    end)

    it("gives a freed aura bar back in the pool's shape", function()
        boot()
        W.unit.target = { health = 0.6 }
        local a = watch({ spell = 5001, what = "stacks", max = 3 })
        Fake.login()
        Fake.tick(2)
        a:Release()
        Fake.tick(1)
        local h = lib:Watch("B", { kind = "health", unit = "target", edges = { 50 } }, sink)
        Fake.tick(lib.HOLD + lib.SETTLE + 3)
        assert.are.same({ 50, 100 }, band(h))
        W.unit.target.health = 0.4
        Fake.tick(2)
        assert.are.same({ 0, 50 }, band(h))
    end)

    it("keeps an error to the aura kind", function()
        boot()
        W.unit.target = { health = 0.6 }
        local a = watch({ spell = 5001, what = "up" })
        local h = lib:Watch("B", { kind = "health", unit = "target", edges = { 50 } }, sink)
        Fake.login()
        Fake.tick(lib.HOLD + lib.SETTLE + 3)
        Fake.set("refuse", "InCombatLockdown")
        Fake.event("COOLDOWN_VIEWER_DATA_LOADED")
        Fake.tick(2)
        assert.are.same({ "unavailable", "error" }, { a:State() })
        assert.are.equal("live", (h:State()))
        assert.are.equal(1, #Fake.errors)
    end)

    for _, mode in ipairs({ "secret", "plain" }) do
        it("walks a fight with every read " .. mode .. " and no trap fires", function()
            boot()
            W.secret = mode == "secret"
            watch({ spell = 5001, what = "stacks", edges = { 2, 3 } })
            watch({ spell = 5001, what = "left", edges = { 2, 5 } })
            watch({ spell = 5002, what = "up" })
            watch({ unit = "target", spell = 5003, what = "stacks", max = 3 })
            Fake.login()
            W.combat = mode == "secret"
            for i = 1, 300 do
                if i % 40 == 1 then
                    Fake.setAura("player", 5001, 1 + (i % 3), 6)
                    Fake.setAura("target", 5003, 1 + (i % 2), 10)
                end
                if i == 150 then
                    W.cdm.shuffle = true
                    Fake.cdmLayout()
                end
                Fake.tick(1)
            end
            lib:GetAuraSources()
            lib:GetSources()
            assert.are.same({}, Fake.errors)
        end)
    end

    it("allocates nothing over 600 steady frames of presence, stacks and seconds", function()
        boot()
        W.secret = false
        local n = 0
        local function count()
            n = n + 1
        end
        lib:Watch("A", { kind = "aura", unit = "player", spell = 5001, what = "stacks", edges = { 2 } }, count)
        lib:Watch("A", { kind = "aura", unit = "player", spell = 5001, what = "left", edges = { 1, 3 } }, count)
        lib:Watch("A", { kind = "aura", unit = "player", spell = 5001, what = "up" }, count)
        lib:Watch("A", { kind = "aura", unit = "target", spell = 5003, what = "stacks", edges = { 2 } }, count)
        lib:Watch("A", { kind = "aura", unit = "player", cooldown = 14, what = "up" }, count) -- an Essential item
        W.cdm.essential = { 14 }
        Fake.setAura("player", 5004, 1, 600)
        W.unit.target = { health = 0.5 }
        Fake.login()
        -- a refresh every 200 frames (before the 4 s expiry: the fake allocates when it drops an aura), stacks 3 and
        -- 1 in turn: the seconds fall through 3 and 1 each time
        local function frame(i)
            if i % 200 == 1 then
                Fake.setAura("player", 5001, 1 + (i % 400 == 1 and 2 or 0), 4)
            end
            Fake.event("UNIT_HEALTH", "target") -- re-syncs every target source
            Fake.tick(1)
        end
        for i = 1, 600 do
            frame(i)
        end
        collectgarbage("collect")
        frame(1) -- the full collection shrank the Lua stack: the first deep call regrows it (no garbage)
        collectgarbage("stop")
        local b = collectgarbage("count")
        for i = 2, 600 do
            frame(i)
        end
        local grew = collectgarbage("count") - b
        collectgarbage("restart")
        assert.is_true(n > 8, n)
        assert.is_true(grew < 0.5, grew .. " KB")
    end)
end)
