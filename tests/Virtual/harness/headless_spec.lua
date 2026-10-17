-- tests/Virtual/harness/headless_spec.lua (headless loop design §1, §6, §9): stock Hekili boots headless in its own
-- environment on fake_api, with no character (class-neutral: the content's characters are booted in tests/Forever).
local headless = require("Virtual.harness.headless")
local fake = require("Virtual.State.helpers.fake_api")

-- The facade's passthrough rows no client in this repository answers (absent on Forever by the facade's own sweep;
-- nothing on the recommendation path reads them), each a row fake_api leaves out on purpose.
local ABSENT = {
    ["C_SpellBook.GetSpellBookItemInfo"] = "retail spellbook item API",
    ["C_SpellBook.GetSpellBookSkillLineInfo"] = "retail spellbook tabs API",
    ["C_Traits.GetNodeCost"] = "retail talent currency",
    ["C_Traits.GetSubTreeInfo"] = "retail hero talents",
    ["C_Traits.GetTreeCurrencyInfo"] = "retail talent currency",
}

describe("headless Hekili", function()
    local H
    setup(function()
        H = headless.new()
    end)

    it("loads every TOC file but the listed XML and logs in (OnInitialize, OnEnable, VirtualState started)", function()
        assert.are.same({}, H.loadErrors)
        assert.is_table(H.Hekili.DB.profile) -- AceDB's profile: OnInitialize ran
        assert.are.equal(H.env, H.ns.VirtualStateInternal.api) -- VS.Start(_G) at PLAYER_LOGIN (OnEnable)
        assert.is_true(H.env.IsLoggedIn())
    end)

    it("reads no unset global at load or login beyond the known lists; safeAbs is not one", function()
        assert.are.same({}, headless.unexpected(H, "load"))
        assert.are.same({}, headless.unexpected(H, "login"))
        assert.is_nil(H.misses.load.safeAbs)
        assert.is_nil(headless.KNOWN_LOAD_NILS.safeAbs)
        assert.are.equal(math.abs, H.Hekili.State.abs)
    end)

    it("runs a ticker on the fake clock and nothing before its time", function()
        local n = 0
        local t = H.env.C_Timer.NewTicker(1, function()
            n = n + 1
        end)
        local now = H.ctl.now
        H.RunTimers(now + 0.5)
        assert.are.equal(0, n)
        H.RunTimers(now + 2)
        assert.are.equal(2, n)
        t:Cancel()
        H.RunTimers(now + 5)
        assert.are.equal(2, n)
    end)

    it("runs due timers in due order, each callback at its own due time", function()
        local now, seen = H.ctl.now, {}
        H.env.C_Timer.After(3, function()
            seen[#seen + 1] = H.env.GetTime() - now
        end)
        H.env.C_Timer.After(1, function()
            seen[#seen + 1] = H.env.GetTime() - now
        end)
        H.RunTimers(now + 5)
        assert.are.same({ 1, 3 }, seen)
        assert.are.equal(now, H.ctl.now)
    end)

    it("counts every Hekili error path: the copy State.lua takes at load and Hekili:Error", function()
        local n = #H.errors
        H.Hekili.State.applyBuff(nil) -- State.lua's load-time `Error` copy (the nameless-aura report)
        assert.are.equal(n + 1, #H.errors)
        H.Hekili:Error("probe %s", "x")
        assert.are.equal(n + 2, #H.errors)
        H.errors[n + 1], H.errors[n + 2] = nil, nil
    end)

    it("keeps two instances apart and adds no global to the real _G", function()
        local before, shared = {}, { "string", "math", "os", "coroutine", "debug" }
        for k in pairs(_G) do
            before[k] = true
        end
        for _, lib in ipairs(shared) do
            for k in pairs(_G[lib]) do
                before[lib .. "." .. k] = true
            end
        end
        local other = headless.new({ now = 50 })
        assert.are_not.equal(H.Hekili, other.Hekili)
        assert.are_not.equal(H.env.LibStub, other.env.LibStub)
        other.ctl.now = 60
        assert.are.equal(60, other.env.GetTime())
        assert.are_not.equal(60, H.env.GetTime())
        local added = {}
        for k in pairs(_G) do
            if not before[k] then
                added[#added + 1] = tostring(k)
            end
        end
        for _, lib in ipairs(shared) do
            for k in pairs(_G[lib]) do
                if not before[lib .. "." .. k] then
                    added[#added + 1] = lib .. "." .. tostring(k)
                end
            end
        end
        assert.are.same({}, added)
        assert.is_nil(rawget(_G, "Hekili"))
        assert.is_nil(rawget(_G, "LibStub"))
    end)

    it("answers every facade row the client resolves from fake_api, but the five absent on Forever", function()
        local api = fake.new()
        local missing = {}
        for _, name in ipairs(H.ns.Facade.Inventory()) do
            if H.ns.Facade.Status(name) ~= "virtual" and not ABSENT[name] then
                local space, key = name:match("^([%w_]+)%.([%w_]+)$")
                local fn = space and api[space] and api[space][key] or (not space and api[name])
                if type(fn) ~= "function" then
                    missing[#missing + 1] = name
                end
            end
        end
        assert.are.same({}, missing)
    end)

    it(
        "answers the facade rows `o.raw` names with the client's raw function (the oracle's secret-free reads)",
        function()
            local raw = headless.new({ raw = { "UnitHealth", "C_Spell.GetSpellCooldown" } })
            assert.are.equal(raw.env.UnitHealth, raw.ns.Facade.UnitHealth)
            assert.are.equal(raw.env.C_Spell.GetSpellCooldown, raw.ns.Facade.C_Spell.GetSpellCooldown)
            assert.are_not.equal(H.env.UnitHealth, H.ns.Facade.UnitHealth)
        end
    )

    it("answers UnitIsUnit true for a unit and itself; a secret answer for two tokens stays secret", function()
        local api, ctl = fake.new()
        assert.is_true(api.UnitIsUnit("player", "player"))
        assert.is_true(api.UnitIsUnit("target", "target"))
        ctl.unitIs.targettarget = fake.SECRET
        assert.is_true(api.issecretvalue(api.UnitIsUnit("targettarget", "player")))
    end)
end)
