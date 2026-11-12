-- tests/Game/harness/headless_spec.lua (headless loop design §1, §6, §9): stock Hekili boots headless in its own
-- environment on fake_api, with no character (class-neutral: the content's characters are booted in tests/Forever).
local headless = require("Game.harness.headless")
local fake = require("Game.State.helpers.fake_api")

-- The facade's passthrough rows no client in this repository answers (absent on Forever by the facade's own sweep;
-- nothing on the recommendation path reads them), each a row fake_api leaves out on purpose.
local ABSENT = {
    ["C_SpellBook.GetSpellBookItemInfo"] = "retail spellbook item API",
    ["C_SpellBook.GetSpellBookSkillLineInfo"] = "retail spellbook tabs API",
    ["C_Traits.GetNodeCost"] = "retail talent currency",
    ["C_Traits.GetSubTreeInfo"] = "retail hero talents",
    ["C_Traits.GetTreeCurrencyInfo"] = "retail talent currency",
}
-- Facade rows a library answers (range plan R2), served by LibStub: fake_api's double for LibRangeCheck-3.0.
local LIBRARY = { RangeLib = "LibRangeCheck-3.0", ["LibRangeCheck.GetRange"] = "LibRangeCheck-3.0" }

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
        -- Perf 1.5: gone from embeds.xml, and nothing loaded asked for them.
        local LibStub = rawget(H.env, "LibStub")
        -- Audit item 19: LibCompress (legacy import strings) and AceEvent-3.0 (never called) removed too.
        for _, name in ipairs({ "AceComm-3.0", "AceTimer-3.0", "LibChatAnims", "LibCompress", "AceEvent-3.0" }) do
            assert.is_nil(LibStub:GetLibrary(name, true))
        end
        assert.is_nil(rawget(H.env, "ChatThrottleLib"))
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
        H.env.C_Timer.After(1, function() -- overdue: it runs at the clock, never before it
            seen[#seen + 1] = H.env.GetTime() - now
        end)
        H.ctl.now = now + 5
        H.RunTimers(now + 5)
        assert.are.same({ 1, 3, 5 }, seen)
        assert.are.equal(now + 5, H.ctl.now)
    end)

    it("counts the simulated state's mutations in state.changes (the memoised cost's key)", function()
        local s = H.Hekili.State
        local n = s.changes
        local function bumps(what, fn, ...)
            fn(...)
            assert.is_true(s.changes > n, what)
            n = s.changes
        end
        bumps("applyBuff", s.applyBuff, "casting", 1.5) -- removeBuff and addStack go through it
        bumps("removeStack", s.removeStack, "casting")
        bumps("applyDebuff", s.applyDebuff, "target", "casting", 1.5) -- removeDebuff goes through it
        bumps("setStance", s.setStance, "none")
        bumps("gain", s.gain, 1, "health")
        bumps("spend", s.spend, 1, "health")
        bumps("setCooldown", s.setCooldown, "global_cooldown", 1.5)
        bumps("advance", s.advance, 0.1)
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
                if LIBRARY[name] then
                    fn = api.LibStub(LIBRARY[name]).GetRange
                end
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

    -- The content surface (restructure plan, Task 8): content reads the belief through four environment names, never
    -- through VirtualState, and declares a passive instead of asking the belief to track an ID.
    describe("the content's environment names", function()
        local VS, I, S
        local function pos(list, v)
            for i = 1, #list do
                if list[i] == v then
                    return i
                end
            end
            return nil
        end
        local function probe()
            return knownRank, swingBase, healthMax, stat -- luacheck: ignore 113 (the env names)
        end
        setup(function()
            VS, I, S = H.ns.VirtualState, H.ns.VirtualStateInternal, H.Hekili.State
        end)

        -- The sim's names read the client through the facade (audit E8, E10): out of combat every read is plain, so
        -- the belief's own functions are never reached.
        local function facadeAnswers(kr, sb, hm)
            local ctl = H.ctl
            local saved = { VS.KnownRank, VS.SwingBase, VS.HealthMax }
            local was = { ctl.speed[1], ctl.meleeHaste, ctl.healthMax }
            ctl.known[900071], ctl.known[900072] = true, false
            ctl.speed[1], ctl.meleeHaste, ctl.healthMax = 2.0, 25, 4321
            VS.KnownRank, VS.SwingBase, VS.HealthMax = error, error, error
            local ok, err = pcall(function()
                assert.are.equal(1, kr({ 900071, 900072 }))
                assert.are.equal(0, kr({ 900072 }))
                assert.are.equal(2.5, sb(1)) -- the unhasted base: UnitAttackSpeed times the haste
                assert.are.equal(4321, hm("player"))
            end)
            VS.KnownRank, VS.SwingBase, VS.HealthMax = unpack(saved)
            ctl.speed[1], ctl.meleeHaste, ctl.healthMax = unpack(was)
            assert(ok, err)
        end

        it("answers stat(name, arg) through the facade's stat hybrids in a sim handler's `state`", function()
            local ctl, st = H.ctl, select(4, setfenv(probe, S)())
            local saved, was = VS.Stat, ctl.stats.armor
            VS.Stat, ctl.stats.armor = error, 777
            local ok, err = pcall(function()
                local a, b = st("UnitArmor")
                assert.are.same({ 777, 777 }, { a, b })
                assert.are.same({ 0, 0, 0, 0, 0, 0, 0 }, { st("NoSuchStat") })
            end)
            VS.Stat, ctl.stats.armor = saved, was
            assert(ok, err)
            assert.is_number(S.stat.crit) -- `stat` stays Hekili's stat table; calling it reads the client's stats
        end)

        it("answers knownRank, swingBase and healthMax through the facade in a sim handler's `state`", function()
            facadeAnswers(setfenv(probe, S)())
        end)

        -- Spell knowledge changes only at SPELLS_CHANGED-class events: knownRank is Hekili's own memo of the facade's
        -- answer, so a read makes no client call between events, and a rank learned mid-session is seen after one.
        it("memoises knownRank: no client call between SPELLS_CHANGED events, a learned rank seen after one", function()
            local ctl, SB = H.ctl, H.ns.Facade.C_SpellBook
            local kr, ids = setfenv(probe, S)(), { 900071, 900072 }
            ctl.known[900071], ctl.known[900072] = true, false
            ctl.Fire("SPELLS_CHANGED")
            assert.are.equal(1, kr(ids))
            local real, calls = SB.IsSpellKnown, 0
            SB.IsSpellKnown = function(...)
                calls = calls + 1
                return real(...)
            end
            local ok, err = pcall(function()
                for _ = 1, 100 do
                    kr(ids)
                end
                assert.are.equal(0, calls)
                ctl.known[900072] = true -- a rank learned mid-session
                ctl.Fire("SPELLS_CHANGED")
                assert.are.equal(2, kr(ids))
            end)
            SB.IsSpellKnown = real
            ctl.known[900071], ctl.known[900072] = nil, nil
            assert(ok, err)
        end)

        it(
            "answers them from the belief in a `now` handler's context, which a resource's `taken` runs in too",
            function()
                local kr, sb, hm, st = setfenv(probe, I.nowCtx)()
                assert.are.same({ VS.KnownRank, VS.SwingBase, VS.HealthMax, VS.Stat }, { kr, sb, hm, st })
            end
        )

        it("answers them in a resource model function: RegisterResource binds its meta functions to `state`", function()
            local meta = { probe = probe }
            H.Hekili.Class.specs[0]:RegisterResource(H.env.Enum.PowerType.Rage, {}, nil, meta)
            facadeAnswers(meta.probe())
        end)

        it(
            "binds an `fsr` meta's parts to `state` and moves a `mult` regen entry out of the forecast's model",
            function()
                local spec, meta = H.Hekili.Class.specs[0], { fsr = { spirit = probe, mp5 = 2 } }
                local entry = { aura = "rate_aura", mult = 2 }
                spec:RegisterResource(H.env.Enum.PowerType.Focus, { surge = entry }, nil, meta)
                assert.are.equal(S.knownRank, (meta.fsr.spirit()))
                local st = spec.resources.focus.state
                assert.are.same(
                    { {}, { entry }, true },
                    { st.regenModel, st.regenMult, spec.resourceAuras.focus.rate_aura }
                )
            end
        )

        it("calls stat without allocating", function()
            local alloc = require("Game.State.helpers.alloc")
            assert.are.equal(
                0,
                alloc.bytes(function()
                    S.stat("UnitArmor")
                end, 100)
            )
        end)

        it(
            "forwards a passive ability to the belief's tracked set at the next build and registers no ability",
            function()
                H.Hekili.Class.specs[0]:RegisterAbility("passive_probe", { id = 999003, passive = true })
                local out = {}
                VS.Tracked("ability", out)
                assert.is_nil(pos(out, 999003))
                H.ns.BuildTracked()
                VS.Tracked("ability", out)
                assert.is_truthy(pos(out, 999003))
                assert.is_nil(rawget(H.Hekili.Class.specs[0].abilities, "passive_probe"))
                assert.has_error(function()
                    H.Hekili.Class.specs[0]:RegisterAbility("passive_noid", { passive = true })
                end)
            end
        )
    end)
end)
