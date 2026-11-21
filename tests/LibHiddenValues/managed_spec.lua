-- tests/LibHiddenValues/managed_spec.lua: Mode B, the managed Cooldown Manager layout. The consumer hands the library
-- its persisted table; ManageCooldownManager adds one layout (a copy of the active one with every watched aura's entry
-- on a tracked bar), the consumer reloads, the library checks the result and hides the four viewers (alpha 0) while it
-- holds; RestoreCooldownManager puts the player's layouts back (byte-exact when nothing else changed). Covered: manage,
-- pending, reload, managed with bars; restore byte-exact; undo before the reload; drift; 5 of 5; combat; the API
-- missing; a write that does not stick (the original kept unless put back); a check that fails; a manage that needs no
-- reload checks in the same load; the player's edits kept by restore; an update after a new aura watch; another owner;
-- the alpha the player had.
local FAKE = "src/LibHiddenValues/Testing/FakeClient.lua"
local TAG = 111 -- class 11, spec 1

-- 21 is spell 6001's cooldown (Essential), 22 its aura (a tracked buff icon); 23 a tracked bar by default; 24 an icon
-- the player's layout "Mine" places as a bar; 25 an icon nobody watches at first; 26 an aura not learned yet.
local function catalogue()
    return {
        [21] = { spellID = 6001, category = 0 },
        [22] = { spellID = 6001, category = 2 },
        [23] = { spellID = 6002, category = 3 },
        [24] = { spellID = 6003, category = 2 },
        [25] = { spellID = 6004, category = 2 },
        [26] = { spellID = 6005, category = 2 },
    }
end

local function playerLayouts()
    return {
        [1] = 5,
        [2] = { [TAG] = 1, [121] = 2 },
        [3] = {
            [TAG] = { [1] = { [1] = { 21, 22, 23, 24 }, [2] = { [3] = { 24 } } } },
            [121] = { [2] = { [1] = { 7 } } },
        },
        [4] = { [1] = "Mine", [2] = "Other" },
    }
end

local VIEWERS =
    { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

describe("LibHiddenValues managed Cooldown Manager layout (Mode B)", function()
    local Fake, W, lib, store, told, h, orig

    -- The consumer's files: hand over the store, watch, listen. Runs at boot and again at every reload.
    local function consumer()
        lib = LibStub("LibHiddenValues-1.0")
        assert.is_true(lib:SetCooldownManagerStore("A", store))
        h = {
            left = assert(
                lib:Watch("A", { kind = "aura", unit = "player", spell = 6001, what = "left", edges = { 3 } })
            ),
            up = assert(lib:Watch("A", { kind = "aura", unit = "player", spell = 6002, what = "up" })),
            late = assert(lib:Watch("A", { kind = "aura", unit = "player", spell = 6005, what = "up" })),
        }
        lib:OnCapability("A", function(kind, state, reason)
            if kind == "cdm" then
                told[#told + 1] = state .. ":" .. tostring(reason)
            end
        end)
    end

    local function boot(layouts)
        Fake = dofile(FAKE)
        W = Fake.world
        W.cdm.catalogue = catalogue()
        W.cdm.unlearned = { [26] = true }
        if layouts ~= false then
            W.cdm.store = Fake.encodeLayouts(layouts or playerLayouts())
        end
        orig = W.cdm.store
        W.cdm.opacity = 0.5 -- the player's Edit Mode opacity (a reload applies it again)
        for _, name in ipairs(VIEWERS) do
            _G[name]:SetAlpha(0.5)
        end
        Fake.touched = {}
        store, told = {}, {}
        consumer()
        Fake.onReload = consumer
        assert.is_true(Fake.login())
        Fake.tick(2)
    end

    local function mode()
        return { lib:GetCooldownManagerMode() }
    end

    local function alphas()
        local out = {}
        for i, name in ipairs(VIEWERS) do
            out[i] = _G[name]:GetAlpha()
        end
        return out
    end

    local function layouts()
        return Fake.decodeLayouts(W.cdm.store)
    end

    local function band(x)
        local lo, hi = x:Get()
        return { lo, hi }
    end

    after_each(function()
        assert.are.same({}, Fake.errors)
        Fake.restore()
    end)

    it("manages: one new layout, the watched auras' entries on bars, a reload, then managed and hidden", function()
        boot()
        assert.are.same({ "player" }, mode())
        assert.are.same({ "unavailable", "cdm-icon-only" }, { h.left:State() })
        assert.are.same({ false }, { lib:IsReloadPending() })

        assert.is_true(lib:ManageCooldownManager("A", store))
        assert.are.same({ true, "manage" }, { lib:IsReloadPending() })
        assert.are.same({ "pending", "reload" }, mode())
        local t = layouts()
        assert.are.equal(3, t[2][TAG]) -- a new id: the largest + 1, active for the tag
        assert.are.equal(2, t[2][121]) -- another tag's active layout untouched
        assert.are.equal("A", t[4][3])
        -- a copy of "Mine" with 22 (the aura entry, never 21: the cooldown) and 26 (not learned yet) moved to bars
        assert.are.same({ [1] = { 21, 22, 23, 24 }, [2] = { [3] = { 24, 22, 26 } } }, t[3][TAG][3])
        local before = playerLayouts()
        assert.are.same(before[3][TAG][1], t[3][TAG][1])
        assert.are.same(before[3][121], t[3][121])
        assert.are.same(before[4][1], t[4][1])
        assert.are.equal(orig, store.orig) -- the original saved before the write
        Fake.tick(2)
        assert.are.same({ "pending:reload" }, told)
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas()) -- nothing hidden before the reload
        assert.are.same({}, Fake.touched)

        told = {}
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ false }, { lib:IsReloadPending() })
        assert.are.same({ "managed" }, mode())
        assert.are.same({ "managed:nil" }, told)
        assert.are.same({ 0, 0, 0, 0 }, alphas())
        assert.are.same({ 22, 23, 24 }, W.cdm.bar) -- 26 is not learned: no item
        local spec = { kind = "aura", unit = "player", spell = 6001, what = "left", edges = { 3 } }
        assert.are.same({ true, "ready" }, { lib:IsAvailable("aura", spec) })
        Fake.setAura("player", 6001, 1, 10)
        Fake.tick(12)
        assert.are.same({ 3, math.huge }, band(h.left))
        assert.are.equal("live", (h.left:State()))
        assert.are.same({ 0, 0 }, band(h.up)) -- placed on a bar by default, not up: a known 0
    end)

    it("restores byte-exact after the reload, gives the alpha back, and the next load is the player's", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
        told = {}
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store) -- byte for byte
        assert.are.same({ true, "restore" }, { lib:IsReloadPending() })
        assert.are.same({ "pending", "reload" }, mode())
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas()) -- given back at once
        assert.are.equal("restoring", store.state) -- the saved original stays until the next load shows it took
        assert.are.equal(orig, store.orig)
        Fake.tick(2)
        assert.are.same({ "pending:reload" }, told)
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "player" }, mode())
        assert.is_nil(next(store)) -- the restore took: the saved state is gone
        assert.are.same({ false }, { lib:IsReloadPending() })
        assert.are.same({ 23, 24 }, W.cdm.bar)
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas())
        assert.are.equal("cdm-icon-only", select(2, h.left:State()))
    end)

    it("undoes a manage before the reload with no reload needed", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store)
        assert.are.same({ false }, { lib:IsReloadPending() })
        assert.are.same({ "player" }, mode())
        assert.is_nil(next(store))
        Fake.tick(2)
        assert.are.same({}, told) -- never left "player" as far as the callbacks know
    end)

    it("works from an empty store (no layout saved yet) and restores it to empty", function()
        boot(false)
        assert.are.equal("", W.cdm.store)
        assert.is_true(lib:ManageCooldownManager("A", store))
        local t = layouts()
        assert.are.equal(1, t[2][TAG])
        assert.are.same({ [2] = { [3] = { 22, 26 } } }, t[3][TAG][1])
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal("", W.cdm.store)
    end)

    it("reports drift when the player switches to another layout, and manages again to switch back", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        told = {}
        -- the player picks "Mine" in the Cooldown Manager's settings: the client saves the store and lays out again
        local t = layouts()
        t[2][TAG] = 1
        W.cdm.store = Fake.encodeLayouts(t)
        W.cdm.bar = { 23, 24 }
        Fake.cdmLayout()
        Fake.tick(2)
        assert.are.same({ "drift", "switched" }, mode())
        assert.are.same({ "drift:switched" }, told)
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas()) -- the player's layout shows: never fought
        assert.is_true(lib:ManageCooldownManager("A", store)) -- "use the managed layout": ours again, same id
        t = layouts()
        assert.are.equal(3, t[2][TAG])
        assert.are.same({ [1] = { 21, 22, 23, 24 }, [2] = { [3] = { 24, 22, 26 } } }, t[3][TAG][3])
        assert.are.same({ true, "manage" }, { lib:IsReloadPending() })
    end)

    it("reports drift when the player deletes the managed layout or turns the Cooldown Manager off", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        Fake.cdmEnable(false)
        Fake.tick(2)
        assert.are.same({ "drift", "cdm-off" }, mode())
        Fake.cdmEnable(true)
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
        local t = layouts()
        t[3][TAG][3], t[4][3], t[2][TAG] = nil, nil, 1
        W.cdm.store = Fake.encodeLayouts(t)
        Fake.cdmLayout()
        Fake.tick(2)
        assert.are.same({ "drift", "deleted" }, mode())
        -- restore: nothing of ours is left and the store is the original again (the same bytes as the client
        -- holds): the saved state goes, no write, no reload
        local n = W.cdm.writes
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store)
        assert.are.equal(n, W.cdm.writes) -- equal bytes are not written again
        assert.are.same({ false }, { lib:IsReloadPending() })
        assert.are.same({ "player" }, mode())
        assert.is_nil(next(store))
    end)

    it("refuses with 5 of 5 layouts, in combat, without the API, when off, and for another owner", function()
        local five = playerLayouts()
        five[3][131] = { [3] = {}, [4] = {} }
        five[3][141] = { [5] = {} }
        boot(five)
        assert.are.same({ nil, "cdm-slots-full" }, { lib:ManageCooldownManager("A", store) })
        assert.are.equal(orig, W.cdm.store)
        assert.is_nil(next(store))
        W.cdm.store = Fake.encodeLayouts(playerLayouts())
        W.combat = true
        assert.are.same({ nil, "cdm-combat" }, { lib:ManageCooldownManager("A", store) })
        W.combat = false
        local EU = _G.C_EncodingUtil
        _G.C_EncodingUtil = nil
        assert.are.same({ nil, "cdm-api" }, { lib:ManageCooldownManager("A", store) })
        _G.C_EncodingUtil = EU
        W.cdm.store = "2|zz"
        assert.are.same({ nil, "cdm-unreadable" }, { lib:ManageCooldownManager("A", store) })
        W.cdm.store = Fake.encodeLayouts(playerLayouts())
        assert.are.same({ nil, "store-invalid" }, { lib:ManageCooldownManager("A", "x") })
        assert.are.same({ nil, "cdm-not-managed" }, { lib:RestoreCooldownManager("A", store) })
        assert.is_true(lib:ManageCooldownManager("A", store))
        assert.are.same({ nil, "cdm-owner" }, { lib:ManageCooldownManager("B", {}) })
        assert.are.same({ nil, "cdm-owner" }, { lib:SetCooldownManagerStore("B", {}) })
        W.combat = true
        assert.are.same({ nil, "cdm-combat" }, { lib:RestoreCooldownManager("A", store) })
        W.combat = false
        Fake.cdmEnable(false)
        Fake.tick(2)
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.same({ nil, "cdm-off" }, { lib:ManageCooldownManager("A", store) })
        for _, code in ipairs({ "cdm-slots-full", "cdm-combat", "cdm-api", "cdm-unreadable", "store-invalid" }) do
            assert.is_string(lib:GetMessage(code), code)
        end
        for _, code in ipairs({ "cdm-owner", "cdm-not-managed", "cdm-write-failed", "check-failed", "switched" }) do
            assert.is_string(lib:GetMessage(code), code)
        end
    end)

    it("puts the layouts back when a write does not read back as written", function()
        boot()
        W.cdm.badWrite = true
        assert.are.same({ nil, "cdm-write-failed" }, { lib:ManageCooldownManager("A", store) })
        W.cdm.badWrite = false
        assert.are.equal(orig .. "x", W.cdm.store) -- the put-back did not stick either
        assert.are.equal(orig, store.orig) -- so the saved original is kept
        assert.are.same({ false }, { lib:IsReloadPending() })
        assert.are.same({ "player" }, mode())
        -- restore: the store cannot be read, the saved original goes back raw
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store)
        assert.is_nil(next(store))
    end)

    it("forgets the saved original when a failed write was put back", function()
        boot()
        W.cdm.badWrite = true
        local set = _G.C_CooldownViewer.SetLayoutData
        _G.C_CooldownViewer.SetLayoutData = function(data) -- only our layout fails to stick
            W.cdm.badWrite = data ~= orig
            set(data)
        end
        assert.are.same({ nil, "cdm-write-failed" }, { lib:ManageCooldownManager("A", store) })
        _G.C_CooldownViewer.SetLayoutData = set
        W.cdm.badWrite = false
        assert.are.equal(orig, W.cdm.store)
        assert.is_nil(next(store))
    end)

    it("becomes managed when a manage again needs no reload (restore, then manage, in one session)", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.is_true(lib:ManageCooldownManager("A", store)) -- the same bytes as this load: no reload
        assert.are.same({ false }, { lib:IsReloadPending() })
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
        assert.are.same({ 0, 0, 0, 0 }, alphas())
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
    end)

    it("checks again when a manage follows a failed check whose cause went away", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        Fake.onReload = function()
            consumer()
            W.cdm.enabled = false -- the Cooldown Manager is off at the reload
        end
        _G.ReloadUI()
        Fake.advance(21)
        assert.are.same({ "player", "check-failed" }, mode())
        Fake.cdmEnable(true)
        Fake.tick(2)
        assert.are.same({ "player", "check-failed" }, mode())
        local n = W.cdm.writes
        assert.is_true(lib:ManageCooldownManager("A", store)) -- ours is still active: nothing to write
        assert.are.equal(n, W.cdm.writes)
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
        assert.are.same({ 0, 0, 0, 0 }, alphas())
    end)

    it("gives up when the layout did not take after the reload, and restore still works", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        local written = W.cdm.store
        W.cdm.store = orig -- the client threw our layout away at the reload
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "pending", "checking" }, mode())
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas())
        Fake.advance(21)
        assert.are.same({ "player", "check-failed" }, mode())
        assert.is_nil(lib.mb.checking) -- the check ended: the driver may stop
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas())
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store)
        assert.are_not.equal(written, W.cdm.store)
    end)

    it("keeps the player's edits made while managed: only the managed layout goes", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        local t = layouts()
        t[3][121][2][1] = { 7, 8 } -- the player edits a layout of another class
        t[3][TAG][4] = { [2] = { [2] = { 23 } } } -- and adds one
        t[4][4] = "New"
        W.cdm.store = Fake.encodeLayouts(t)
        assert.is_true(lib:RestoreCooldownManager("A", store))
        local r = layouts()
        assert.are.same({ 7, 8 }, r[3][121][2][1])
        assert.are.same({ [2] = { [2] = { 23 } } }, r[3][TAG][4])
        assert.are.equal("New", r[4][4])
        assert.is_nil(r[3][TAG][3]) -- ours gone
        assert.is_nil(r[4][3])
        assert.are.equal(1, r[2][TAG]) -- the layout active before ours is active again
        assert.are.same(playerLayouts()[3][TAG][1], r[3][TAG][1])
        assert.are.same({ true, "restore" }, { lib:IsReloadPending() })
    end)

    it("keeps the player's choice when they switched away and edited before restoring", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        local t = layouts()
        t[3][TAG][4], t[4][4], t[2][TAG] = { [2] = {} }, "New", 4
        W.cdm.store = Fake.encodeLayouts(t)
        assert.is_true(lib:RestoreCooldownManager("A", store))
        local r = layouts()
        assert.are.equal(4, r[2][TAG])
        assert.is_nil(r[3][TAG][3])
    end)

    it("asks for an update when a new aura is watched, and rewrites only its own layout", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
        told = {}
        local extra = assert(lib:Watch("A", { kind = "aura", unit = "player", spell = 6004, what = "stacks", max = 3 }))
        Fake.tick(2)
        assert.are.same({ "managed", "update" }, mode())
        assert.are.same({ "managed:update" }, told)
        assert.are.same({ 0, 0, 0, 0 }, alphas())
        local before = layouts()
        assert.is_true(lib:ManageCooldownManager("A", store))
        local t = layouts()
        assert.are.same({ 24, 22, 26, 25 }, t[3][TAG][3][2][3])
        before[3][TAG][3] = nil
        t[3][TAG][3] = nil
        assert.are.same(before, t) -- nothing else changed
        assert.are.same({ "pending", "reload" }, mode())
        assert.are.same({ 0, 0, 0, 0 }, alphas()) -- the loaded layout is still ours: hidden until the reload
        local orig0 = store.orig
        Fake.onReload = function()
            consumer()
            lib:Watch("A", { kind = "aura", unit = "player", spell = 6004, what = "stacks", max = 3 })
        end
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
        assert.are.same({ 22, 23, 24, 25 }, W.cdm.bar)
        assert.are.equal(orig0, store.orig) -- the first original is kept
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store)
        assert.is_true(extra ~= nil)
    end)

    it("writes nothing when managing again changes nothing", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        local n = W.cdm.writes
        assert.is_true(lib:ManageCooldownManager("A", store))
        assert.are.equal(n, W.cdm.writes)
        assert.are.same({ false }, { lib:IsReloadPending() })
        assert.are.same({ "managed" }, mode())
    end)

    it("gives the viewers back when the library is switched off, and hides them again when on", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        lib:SetEnabled(false)
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas())
        lib:SetEnabled(true)
        Fake.tick(60)
        assert.are.same({ 0, 0, 0, 0 }, alphas())
    end)

    it("waits out combat after a reload before it checks, and touches only the viewers' alpha", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        Fake.touched = {}
        Fake.onReload = function()
            consumer()
            W.combat = true -- a reload in combat: the library loads before the fight ends
        end
        Fake.reload()
        Fake.advance(30)
        assert.are.same({ "pending", "checking" }, mode())
        W.combat = false
        Fake.event("PLAYER_REGEN_ENABLED")
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
        for _, m in ipairs(Fake.touched) do
            assert.are.equal("SetAlpha", m)
        end
        assert.are.equal(4, #Fake.touched)
    end)

    -- The layouts with a layout of the player's own at id 3 (the id ours had), active.
    local function theirsAt3()
        local t = layouts()
        t[3][TAG][3], t[4][3], t[2][TAG] = { [1] = { 23 }, [2] = { [2] = { 23 } } }, "Player New", 3
        W.cdm.store = Fake.encodeLayouts(t)
        Fake.cdmLayout()
        Fake.tick(2)
        return W.cdm.store
    end

    local function managedAfterReload()
        assert.is_true(lib:ManageCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
    end

    it("never takes a layout of the player that reuses our id for ours (deleted, then a new one)", function()
        boot()
        managedAfterReload()
        local t = layouts()
        t[3][TAG][3], t[4][3], t[2][TAG] = nil, nil, 1 -- the player deletes ours
        W.cdm.store = Fake.encodeLayouts(t)
        Fake.cdmLayout()
        Fake.tick(2)
        assert.are.same({ "drift", "deleted" }, mode())
        local theirs = theirsAt3() -- and makes a new layout: the client gives it id 3
        assert.are.same({ "drift", "deleted" }, mode())
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas()) -- their layout shows
        assert.is_true(lib:ManageCooldownManager("A", store)) -- "use the managed layout": a new one, theirs untouched
        local r = layouts()
        assert.are.same(Fake.decodeLayouts(theirs)[3][TAG][3], r[3][TAG][3])
        assert.are.equal("Player New", r[4][3])
        assert.are.equal("A", r[4][4])
        assert.are.equal(4, r[2][TAG])
        assert.is_true(lib:RestoreCooldownManager("A", store)) -- an undo: theirs back, byte for byte
        assert.are.equal(theirs, W.cdm.store)
        assert.are.same({ false }, { lib:IsReloadPending() })
    end)

    it("never touches a layout of the player that took our id while its store was stale", function()
        boot()
        managedAfterReload()
        local stale = {}
        for k, v in pairs(store) do
            stale[k] = v
        end
        assert.is_true(lib:RestoreCooldownManager("A", store))
        _G.ReloadUI()
        Fake.tick(2)
        assert.is_nil(next(store))
        local theirs = theirsAt3()
        for k, v in pairs(stale) do -- the consumer's SavedVariables from before the restore (a crash)
            store[k] = v
        end
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "drift", "deleted" }, mode())
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas())
        local n = W.cdm.writes
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(n, W.cdm.writes)
        assert.are.equal(theirs, W.cdm.store)
        assert.are.same({ "player" }, mode())
    end)

    it("never takes the player's layout for ours after a failed check", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        W.cdm.store = orig -- the client threw our layout away at the reload
        _G.ReloadUI()
        Fake.advance(21)
        assert.are.same({ "player", "check-failed" }, mode())
        local theirs = theirsAt3()
        assert.is_true(lib:ManageCooldownManager("A", store))
        local r = layouts()
        assert.are.equal("Player New", r[4][3])
        assert.are.same(Fake.decodeLayouts(theirs)[3][TAG][3], r[3][TAG][3])
        assert.are.equal(4, r[2][TAG])
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(theirs, W.cdm.store)
    end)

    it("refuses to restore when the layouts cannot be read, and changes nothing", function()
        boot()
        managedAfterReload()
        local t = layouts()
        t[3][121][2][1] = { 7, 8, 9 } -- the player edits a layout of another class
        local edited = Fake.encodeLayouts(t)
        W.cdm.store = edited
        local CV = _G.C_CooldownViewer
        local get = CV.GetLayoutData
        local n = W.cdm.writes
        for _, how in ipairs({ "error", "nil", "secret" }) do
            CV.GetLayoutData = function()
                if how == "error" then
                    error("restricted")
                elseif how == "secret" then
                    W.cdm.secretStore = true
                    return get()
                end
            end
            assert.are.same({ nil, "cdm-unreadable" }, { lib:RestoreCooldownManager("A", store) }, how)
            W.cdm.secretStore = nil
        end
        CV.GetLayoutData = get
        assert.are.equal(edited, W.cdm.store)
        assert.are.equal(n, W.cdm.writes)
        assert.are.equal(orig, store.orig)
        assert.are.same({ "managed" }, mode())
        assert.is_nil(lib:GetMessage("cdm-write-failed"):find("were put back", 1, true))
    end)

    it("refuses to restore over layouts it cannot decode, or of another save version", function()
        boot()
        managedAfterReload()
        local t = layouts()
        t[1] = 6
        for _, s in ipairs({ "2|zz", "1|zz", Fake.encodeLayouts(t) }) do
            W.cdm.store = s
            assert.are.same({ nil, "cdm-unreadable" }, { lib:RestoreCooldownManager("A", store) }, s)
            assert.are.equal(s, W.cdm.store)
            assert.are.equal(orig, store.orig)
        end
    end)

    it("refuses to manage layouts of a save version other than 5", function()
        local l = playerLayouts()
        l[1] = 6
        boot(l)
        assert.are.same({ nil, "cdm-unreadable" }, { lib:ManageCooldownManager("A", store) })
        assert.are.equal(orig, W.cdm.store)
        assert.is_nil(next(store))
    end)

    it("keeps the saved original until the next load shows the restore took, and retries", function()
        boot()
        managedAfterReload()
        local managed = W.cdm.store
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.is_true(lib:RestoreCooldownManager("A", store)) -- twice: still one reload pending
        assert.are.same({ true, "restore" }, { lib:IsReloadPending() })
        assert.are.equal(orig, W.cdm.store)
        W.cdm.store = managed -- the client wrote its loaded layouts back over the restore before the reload
        told = {}
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "player", "restore-failed" }, mode())
        assert.are.same({ "player:restore-failed" }, told)
        assert.is_string(lib:GetMessage("restore-failed"))
        assert.are.equal(orig, store.orig)
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas())
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store)
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "player" }, mode())
        assert.is_nil(next(store))
    end)

    it("reads pending, checking during a reload in combat while managed", function()
        boot()
        managedAfterReload()
        Fake.onReload = function()
            consumer()
            W.combat = true
        end
        Fake.reload()
        Fake.advance(5)
        assert.are.same({ "pending", "checking" }, mode())
        assert.are.same({ 0.5, 0.5, 0.5, 0.5 }, alphas())
        W.combat = false
        Fake.event("PLAYER_REGEN_ENABLED")
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
        assert.are.same({ 0, 0, 0, 0 }, alphas())
    end)

    it("restores the saved bytes, not a re-encode, when the client's encoder is not canonical", function()
        boot()
        W.cdm.salt = 0
        managedAfterReload()
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store) -- a re-encode would carry a salt
        assert.is_true(lib:ManageCooldownManager("A", store)) -- other bytes than this load's: a reload
        assert.are.same({ true, "manage" }, { lib:IsReloadPending() })
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "managed" }, mode())
    end)

    it("clears the pending reload when a restore finds nothing to write", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        W.cdm.store = orig -- the client wrote its loaded layouts back over ours before the reload
        local n = W.cdm.writes
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(n, W.cdm.writes)
        assert.are.same({ false }, { lib:IsReloadPending() })
        assert.are.same({ "player" }, mode())
        assert.is_nil(next(store))
    end)

    it("pauses the check's 20 s in combat", function()
        boot()
        assert.is_true(lib:ManageCooldownManager("A", store))
        W.cdm.store = orig -- the layout does not take
        _G.ReloadUI()
        Fake.advance(5)
        W.combat = true
        Fake.advance(30)
        W.combat = false
        Fake.event("PLAYER_REGEN_ENABLED")
        Fake.advance(10)
        assert.are.same({ "pending", "checking" }, mode())
        Fake.advance(10)
        assert.are.same({ "player", "check-failed" }, mode())
    end)

    it("hides the viewers again after Edit Mode applies its opacity, and gives the latest back", function()
        boot()
        managedAfterReload()
        for _, name in ipairs(VIEWERS) do
            _G[name]:SetAlpha(0.7) -- Edit Mode applies the player's opacity after the check
        end
        Fake.cdmLayout()
        Fake.tick(2)
        assert.are.same({ 0, 0, 0, 0 }, alphas())
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.same({ 0.7, 0.7, 0.7, 0.7 }, alphas())
    end)

    -- An update written, then the client writes its loaded layouts (ours as before the update) back over it.
    local function updateUndone()
        managedAfterReload()
        local v1 = W.cdm.store
        lib:Watch("A", { kind = "aura", unit = "player", spell = 6004, what = "stacks", max = 3 })
        Fake.tick(2)
        assert.is_true(lib:ManageCooldownManager("A", store))
        assert.are.same({ true, "manage" }, { lib:IsReloadPending() })
        W.cdm.store = v1
    end

    it("still knows its layout as it was before an update the client undid, and restores it", function()
        boot()
        updateUndone()
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store)
    end)

    it("still knows its layout after a reload when the client undid an update, and restores it", function()
        boot()
        updateUndone()
        _G.ReloadUI()
        Fake.advance(21)
        assert.are.same({ "player", "check-failed" }, mode())
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store)
    end)

    it("adopts the layout a check passed on when the client undid an update, and restores it later", function()
        boot()
        managedAfterReload()
        local v1 = W.cdm.store
        W.cdm.unlearned = { [26] = true, [25] = true } -- the new aura is not learned: the check does not count it
        local function watch()
            lib:Watch("A", { kind = "aura", unit = "player", spell = 6004, what = "up" })
        end
        watch()
        Fake.tick(2)
        assert.are.same({ "managed", "update" }, mode())
        assert.is_true(lib:ManageCooldownManager("A", store))
        W.cdm.store = v1 -- the client writes its loaded layouts back before the reload
        Fake.onReload = function()
            consumer()
            watch()
        end
        _G.ReloadUI()
        Fake.tick(2)
        assert.are.same({ "managed", "update" }, mode()) -- passed on v1: ours, the update still owed
        Fake.cdmLayout()
        Fake.tick(2)
        assert.are.same({ "managed", "update" }, mode()) -- not drift deleted at the next read
        assert.is_true(lib:RestoreCooldownManager("A", store))
        assert.are.equal(orig, W.cdm.store)
    end)

    it("keeps the player's edits when a restore write and its put-back both failed", function()
        boot()
        managedAfterReload()
        local t = layouts()
        t[3][121][2][1] = { 7, 8, 9 } -- the player edits a layout of another class
        W.cdm.store = Fake.encodeLayouts(t)
        W.cdm.badWrite = true
        assert.are.same({ nil, "cdm-write-failed" }, { lib:RestoreCooldownManager("A", store) })
        W.cdm.badWrite = false
        assert.is_nil(layouts()) -- our failed write's leftover
        assert.is_true(lib:RestoreCooldownManager("A", store))
        local r = layouts()
        assert.are.same({ 7, 8, 9 }, r[3][121][2][1]) -- the edit kept, not the original from before the manage
        assert.is_nil(r[3][TAG][3])
        assert.are.equal(1, r[2][TAG])
    end)
end)
