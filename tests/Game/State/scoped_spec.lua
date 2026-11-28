-- tests/Game/State/scoped_spec.lua: scoped state (refactor lane 7, Pr-10).
-- The reset matrix: every field a reset site writes, pinned on the tree before the refactor (forever b478aa74e). Each
-- site runs over sentinel-filled private arrays (reached through upvalues, helpers/upvals.lua), and the spec lists
-- exactly what changed. The refactor must leave every list as it was (identity).
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local up = require("Game.State.helpers.upvals")

local SA = "Sources/Auras.lua"
-- Sources/Auras.lua's per-record arrays (k = (u - 1) * AURA_UNIT + j), in a fixed order: a sentinel names its array.
local AURA_ARRAYS = {
    "lastE",
    "lastSt",
    "longE",
    "lateTo",
    "W",
    "verdictAt",
    "verdictN",
    "strikeN",
    "darkN",
    "strikePend",
    "refundN",
    "backN",
    "refPend",
    "dueAt",
    "facts",
    "disagree",
    "staged",
    "exitFix",
    "ours",
    "oursAp",
    "upAt",
    "claimT",
    "anAp",
    "emcN",
    "emcSum",
    "emcLast",
    "cyT",
    "cyD",
    "cyAp",
    "cyE",
    "cyN",
    "cySum",
    "cyObs",
    "cyMod",
    "seedAp",
    "floor",
}

describe("scoped state: the reset matrix", function()
    local VS, I, S, api, ctl, roots, T, K1, K2
    local LABEL

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S = I.Sources
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
        K1, K2 = I.AURA_UNIT + 1, I.AURA_UNIT + 2
        LABEL = { [1] = "p1", [2] = "p2", [K1] = "t1", [K2] = "t2" }
        roots = {
            I.AuraVerdictClosed,
            I.AuraUndone,
            I.AuraClaimFolded,
            I.AuraLateMember,
            I.AuraOurs,
            I.OnPresence,
            I.WalkAuras,
        }
        for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
            for _, f in ipairs(up.handlers(S.HANDLERS[ev], SA)) do
                roots[#roots + 1] = f
            end
        end
        local polls = up.all("Sources/Sources.lua", { S.Poll, S.RunPolls }).POLL_FN
        for _, f in ipairs(up.handlers(polls, SA)) do
            roots[#roots + 1] = f
        end
        for _, f in ipairs(up.handlers(I.BUILD, SA)) do
            roots[#roots + 1] = f
        end
        T = up.all(SA, roots)
        for _, name in ipairs(AURA_ARRAYS) do
            assert(type(T[name]) == "table", name)
        end
    end)

    -- Every array at every index of both auras on both units: a distinct sentinel (array number * 10 + index slot).
    local function fill()
        for a, name in ipairs(AURA_ARRAYS) do
            local arr = T[name]
            for _, k in ipairs({ 1, 2, K1, K2 }) do
                if name ~= "floor" or k < I.AURA_UNIT then
                    arr[k] = a * 10 + (k > I.AURA_UNIT and 2 or 0) + (k - 1) % I.AURA_UNIT + 1
                end
            end
        end
        up.set(SA, roots, "anyLong", "S")
        up.set(SA, roots, "anyLast", "S")
    end

    -- What changed since fill(), as sorted "array[slot]=value" lines, plus the two flags.
    local function changed()
        local out = {}
        for a, name in ipairs(AURA_ARRAYS) do
            local arr = T[name]
            for _, k in ipairs({ 1, 2, K1, K2 }) do
                if name ~= "floor" or k < I.AURA_UNIT then
                    local s = a * 10 + (k > I.AURA_UNIT and 2 or 0) + (k - 1) % I.AURA_UNIT + 1
                    if arr[k] ~= s then
                        out[#out + 1] = name .. "[" .. LABEL[k] .. "]=" .. tostring(arr[k])
                    end
                end
            end
        end
        table.sort(out)
        local all = up.all(SA, roots)
        out[#out + 1] = "anyLong=" .. tostring(all.anyLong)
        out[#out + 1] = "anyLast=" .. tostring(all.anyLast)
        return out
    end

    local function pin(site, got, want)
        assert.are.same(want, got, site .. ":\n  " .. table.concat(got, "\n  "))
    end

    it("rule 1's close (apply: a reduced DOWN on a record the CDM opened)", function()
        fill()
        local apply = up.all(SA, roots).apply
        local U = I.auras
        I.inCombat = true
        I.targetSwapN, I.curSwapN = 3, 3
        U.exp0[2][1], U.applied[2][1] = 60, 5
        T.ours[K1], T.oursAp[K1], T.staged[K1] = 2, 5, 0
        assert.is_true(apply(1, 2, false, 20, true))
        pin("rule 1", changed(), {
            "disagree[t1]=164",
            "facts[t1]=154",
            "lastE[t1]=0",
            "lastSt[t1]=0",
            "lateTo[t1]=22",
            "longE[t1]=0",
            "oursAp[t1]=5",
            "ours[t1]=2",
            "staged[t1]=20",
            "anyLong=S",
            "anyLast=S",
        })
    end)

    it("the verdict's close (I.AuraVerdictClosed)", function()
        fill()
        I.AuraVerdictClosed(K1, 20, 5)
        pin("verdict", changed(), {
            "lastE[t1]=0",
            "lastSt[t1]=0",
            "lateTo[t1]=22",
            "longE[t1]=0",
            "refPend[t1]=0",
            "verdictAt[t1]=20",
            "verdictN[t1]=74",
            "anyLong=S",
            "anyLast=S",
        })
    end)

    it("the avoid undo (I.AuraUndone): a light since the cast closes, one from before keeps preE", function()
        fill()
        I.presence = nil
        I.AuraUndone(1, 15, 40, 20)
        pin("undo close", changed(), {
            "lastE[t1]=0",
            "lastSt[t1]=0",
            "longE[t1]=0",
            "anyLong=S",
            "anyLast=S",
        })
        fill()
        I.presence = { fact = { state = { [K1] = I.UP }, t = { [K1] = 10 } } }
        I.AuraUndone(1, 15, 40, 20)
        pin("undo kept", changed(), { "lastE[t1]=40", "anyLong=S", "anyLast=true" })
        fill()
        I.AuraUndone(1, 15, 0, 20)
        pin("undo kept, no preE", changed(), { "lastE[t1]=20", "anyLong=S", "anyLast=true" })
    end)

    -- Poll 15 alone (Sources/Sources.lua's sorted poll list).
    local function poll15(t)
        local P = up.all("Sources/Sources.lua", { S.Poll, S.RunPolls })
        for i = 1, P.POLL_N do
            if P.POLL_ORDER[i] == 15 then
                return P.POLL_FN[i](api, t)
            end
        end
        error("no poll 15")
    end

    it("no live slot (poll 15, covered 0): every record's debounce memory, LONG records clamped", function()
        fill()
        I.presence = { Sweep = function() end, covered = 0 }
        I.inCombat = true
        I.auras.exp0[1][1] = 1e5
        T.longE[1] = 1e5 -- a LONG record: one clamp, its Read staged
        poll15(20)
        pin("no live slot", changed(), {
            "lastE[p1]=0",
            "lastE[p2]=0",
            "lastE[t1]=0",
            "lastE[t2]=0",
            "lastSt[p1]=0",
            "lastSt[p2]=0",
            "lastSt[t1]=0",
            "lastSt[t2]=0",
            "longE[p1]=0",
            "longE[p2]=0",
            "longE[t1]=0",
            "longE[t2]=0",
            "staged[p1]=20",
            "anyLong=false",
            "anyLast=false",
        })
    end)

    it("dark past the model's expiry (poll 15, an UNDECIDED answer): lastE and lastSt, after the clamp", function()
        fill()
        I.presence = {
            Sweep = function() end,
            covered = 1,
            fact = {},
            Presence = function()
                return I.UNDECIDED
            end,
        }
        I.inCombat = true
        for u = 1, 2 do
            for j = 1, 2 do
                I.auras.exp0[u][j] = 5 -- past: the debounce memory goes
            end
        end
        poll15(20)
        pin("dark past expiry", changed(), {
            "floor[p1]=0",
            "floor[p2]=0",
            "lastE[p1]=0",
            "lastE[p2]=0",
            "lastE[t1]=0",
            "lastE[t2]=0",
            "lastSt[p1]=0",
            "lastSt[p2]=0",
            "lastSt[t1]=0",
            "lastSt[t2]=0",
            "longE[p1]=0",
            "longE[p2]=0",
            "longE[t1]=0",
            "longE[t2]=0",
            "anyLong=S",
            "anyLast=S",
        })
    end)

    it("a target change (Sources/Auras.lua's PLAYER_TARGET_CHANGED): the target records only", function()
        fill()
        I.targetSwapN, I.curSwapN = 3, 3
        I.auras.exp0[2][1] = T.longE[K1] -- the LONG record of mob A: clamped first
        local h = up.handlers(S.HANDLERS.PLAYER_TARGET_CHANGED, SA)
        assert.are.equal(1, #h)
        h[1](api, 20)
        pin("target change", changed(), {
            "cyT[t1]=0",
            "cyT[t2]=0",
            "dueAt[t1]=0",
            "dueAt[t2]=0",
            "lastE[t1]=0",
            "lastE[t2]=0",
            "lastSt[t1]=0",
            "lastSt[t2]=0",
            "lateTo[t1]=0",
            "lateTo[t2]=0",
            "longE[t1]=0",
            "longE[t2]=0",
            "refPend[t1]=0",
            "refPend[t2]=0",
            "staged[t1]=20",
            "strikePend[t1]=0",
            "strikePend[t2]=0",
            "verdictAt[t1]=0",
            "verdictAt[t2]=0",
            "anyLong=S",
            "anyLast=true", -- the clamp moved lastE to its HOLD
        })
    end)

    it("a fight's start (PLAYER_REGEN_DISABLED): every key the fight counts, dueAt kept", function()
        fill()
        local h = up.handlers(S.HANDLERS.PLAYER_REGEN_DISABLED, SA)
        assert.are.equal(1, #h)
        h[1](api, 20)
        local want = {}
        for _, name in ipairs({
            "backN",
            "cyMod",
            "cyN",
            "cyObs",
            "cySum",
            "cyT",
            "darkN",
            "disagree",
            "emcLast",
            "emcN",
            "emcSum",
            "exitFix",
            "facts",
            "lastE",
            "lastSt",
            "lateTo",
            "longE",
            "refPend",
            "refundN",
            "staged",
            "strikeN",
            "strikePend",
            "verdictAt",
            "verdictN",
        }) do
            for _, s in ipairs({ "p1", "p2", "t1", "t2" }) do
                want[#want + 1] = name .. "[" .. s .. "]=0"
            end
        end
        table.sort(want)
        want[#want + 1] = "anyLong=false"
        want[#want + 1] = "anyLast=false"
        pin("pull", changed(), want)
    end)

    it("a build (Sources/Auras.lua's OnBuild): every record of every unit", function()
        fill()
        local h = up.handlers(I.BUILD, SA)
        assert.are.equal(1, #h)
        h[1](I.def, 20)
        local want = {}
        for _, name in ipairs(AURA_ARRAYS) do
            for _, s in ipairs({ "p1", "p2", "t1", "t2" }) do
                if name ~= "floor" or s:sub(1, 1) == "p" then
                    want[#want + 1] = name .. "[" .. s .. "]=" .. (name == "W" and "0.5" or "0")
                end
            end
        end
        table.sort(want)
        want[#want + 1] = "anyLong=false"
        want[#want + 1] = "anyLast=false"
        pin("build", changed(), want)
    end)

    -- The target scope's order (refactor plan Pr-10: "only after a test pins today's handler order"): the client event's
    -- handlers run in registration order, which is Hekili.toc's file order. Each one relies on the one before it.
    it("PLAYER_TARGET_CHANGED's handlers run in Hekili.toc order", function()
        local got = {}
        for _, f in ipairs(S.HANDLERS.PLAYER_TARGET_CHANGED) do
            got[#got + 1] = debug.getinfo(f, "S").source:match("Game/(.*)$")
        end
        assert.are.same({
            "State/Sources/Units.lua", -- rebinds token 1 first: the swap reads its binding
            "State/Sources/Power.lua", -- an on-target slot's points
            "State/Sources/Auras.lua", -- mob A's LONG record clamped while it is still the target's
            "State/Sources/Target.lua", -- the swap: TargetSwap logged, the new target walked
            "State/Sources/Presence/CooldownViewer.lua", -- the leaf's target slots settle
            "State/Sources/Presence/Router.lua", -- then the router's target facts start over
            "Events/Attackers.lua",
        }, got)
    end)

    it("a target change logs mob A's clamp (AuraHeld) before the swap's TargetSwap", function()
        fill()
        I.targetSwapN, I.curSwapN = 3, 3
        I.auras.exp0[2][1], T.longE[K1], T.staged[K1] = 1e5, 1e5, 0
        I.ObsLog.Clear(I.log)
        S.Run(api, "PLAYER_TARGET_CHANGED")
        local held, swap
        for i = 1, I.log.n do
            local o = I.ObsLog.At(I.log, i)
            if o.kind == VS.Obs.Read and o.a == K1 and o.c % I.AURA_STACK == I.ReadOf.AuraHeld then
                held = held or i
            elseif o.kind == VS.Obs.TargetSwap then
                swap = swap or i
            end
        end
        assert.is_truthy(held)
        assert.is_truthy(swap)
        assert.is_true(held < swap)
    end)
end)

-- The other families' reset sites, the same way: every array a site's file holds (its upvalue tables, and the fields
-- of its struct tables, e.g. Resources.lua's R) at a few indices gets a sentinel, the site runs, and the changed
-- entries must equal the list recorded on forever b478aa74e (helpers/scoped_pins.lua; SCOPED_RECORD=1 rewrites it, on
-- the base tree only).
describe("scoped state: the families' reset matrix", function()
    local PINS_PATH = "tests/Game/State/helpers/scoped_pins.lua"
    local record = os.getenv("SCOPED_RECORD") == "1"
    local PINS = record and {} or dofile(PINS_PATH)
    local VS, I, S, api, ctl, APPLY

    local function setup()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S = I.Sources
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
        APPLY = up.all("State/Belief.lua", { I.On }).APPLY
    end

    -- Every hook of `file` the registries hold: builds, folds and client events.
    local function roots(file)
        local out = {}
        local function add(list)
            for _, f in ipairs(up.handlers(list or {}, file)) do
                out[#out + 1] = f
            end
        end
        add(I.BUILD)
        add(I.BUILT)
        for _, list in pairs(APPLY) do
            add(list)
        end
        for _, list in pairs(S.HANDLERS) do
            add(list)
        end
        add(up.all("Sources/Sources.lua", { S.Poll, S.RunPolls }).POLL_FN)
        local exports = {}
        for _, v in pairs(I) do
            if type(v) == "function" then
                exports[#exports + 1] = v
            end
        end
        add(exports)
        return out
    end

    local function arrays(file, structs)
        local out = {}
        for name, v in pairs(up.all(file, roots(file))) do
            if type(v) == "table" and name ~= "I" and name ~= "VS" and name ~= "S" and name ~= "ns" then
                if structs[name] then
                    for f, a in pairs(v) do
                        if type(a) == "table" then
                            out[name .. "." .. f] = a
                        end
                    end
                else
                    out[name] = v
                end
            end
        end
        return out
    end

    local function scalar(v)
        local t = type(v)
        return t == "number" or t == "boolean" or t == "string"
    end

    -- Sentinels into every scalar entry at `idx`, the site run, the changes as sorted lines.
    local function matrix(file, structs, idx, run, nils)
        local A = arrays(file, structs)
        local names = {}
        for name in pairs(A) do
            names[#names + 1] = name
        end
        table.sort(names)
        local sent = {}
        for _, name in ipairs(names) do
            local a = 0 -- by the name, not its place: a new local elsewhere in the file moves no sentinel
            for c = 1, #name do
                a = (a * 31 + name:byte(c)) % 9973
            end
            for p, i in ipairs(idx) do
                if scalar(A[name][i]) or nils and A[name][i] == nil then
                    -- a number (arithmetic and comparisons still run), a string for a string
                    local s = 1000000 + a * 10 + p
                    if type(A[name][i]) == "string" then
                        s = "#" .. s
                    end
                    A[name][i], sent[name .. "[" .. i .. "]"] = s, s
                end
            end
        end
        run()
        local out = {}
        for _, name in ipairs(names) do
            for _, i in ipairs(idx) do
                local key = name .. "[" .. i .. "]"
                local v = A[name][i]
                if sent[key] and v ~= sent[key] then
                    out[#out + 1] = key .. "=" .. tostring(v)
                end
            end
        end
        table.sort(out)
        return out
    end

    local function hook(list, file, n)
        local h = up.handlers(list, file)
        assert(h[n or 1], file)
        return h[n or 1]
    end

    local K = 4096 -- I.AURA_UNIT
    local SITES = {
        {
            "resources build",
            "Families/Resources.lua",
            { R = true },
            { 1, 2, 3 },
            function()
                hook(I.BUILD, "Families/Resources.lua")(I.def, 20)
            end,
        },
        {
            "resources pull",
            "Families/Resources.lua",
            { R = true },
            { 1, 2 },
            function()
                hook(APPLY[VS.Obs.CombatStart], "Families/Resources.lua")({ t = 20 }, 20)
            end,
        },
        {
            "resources combat end",
            "Families/Resources.lua",
            { R = true },
            { 1, 2 },
            function()
                hook(APPLY[VS.Obs.CombatEnd], "Families/Resources.lua")({ t = 20 }, 20)
            end,
        },
        {
            "swing build",
            "Families/Swing.lua",
            {},
            { 1, 2, 3 },
            function()
                hook(I.BUILD, "Families/Swing.lua")(I.def, 20)
            end,
        },
        {
            "swing combat end",
            "Families/Swing.lua",
            {},
            { 1, 2, 3 },
            function()
                hook(APPLY[VS.Obs.CombatEnd], "Families/Swing.lua")({ t = 20 }, 20)
            end,
        },
        {
            "player build",
            "Families/Player.lua",
            {},
            { 0, 1, 5 },
            function()
                hook(I.BUILD, "Families/Player.lua")(I.def, 20)
            end,
        },
        {
            "casts build",
            "Families/Casts.lua",
            { A = true },
            { 1, 2, 3 },
            function()
                hook(I.BUILD, "Families/Casts.lua", 2)(I.def, 20)
            end,
        },
        {
            "now build",
            "Families/Now.lua",
            {},
            { 1, 2, 3 },
            function()
                hook(I.BUILD, "Families/Now.lua")(I.def, 20)
            end,
        },
        {
            "talents build",
            "Families/Talents.lua",
            { T = true },
            { 1, 2 },
            function()
                hook(I.BUILD, "Families/Talents.lua")(I.def, 20)
            end,
        },
        {
            "source casts build",
            "Sources/Casts.lua",
            {},
            { 1, 2, 3 },
            function()
                hook(I.BUILD, "Sources/Casts.lua")(I.def, 20)
            end,
        },
        {
            "spellbook build",
            "Sources/Spellbook.lua",
            {},
            { 1, 2, 3 },
            function()
                hook(I.BUILD, "Sources/Spellbook.lua")(I.def, 20)
            end,
        },
        {
            "power build",
            "Sources/Power.lua",
            {},
            { 1, 2, 3 },
            function()
                hook(I.BUILD, "Sources/Power.lua")(I.def, 20)
            end,
        },
        {
            "source talents build",
            "Sources/Talents.lua",
            {},
            { 1, 2 },
            function()
                hook(I.BUILD, "Sources/Talents.lua")(I.def, 20)
            end,
        },
        {
            "target build",
            "Sources/Target.lua",
            {},
            { 1, 2, 3 },
            function()
                hook(I.BUILD, "Sources/Target.lua")(I.def, 20)
            end,
        },
        {
            "units combat end",
            "Sources/Units.lua",
            {},
            { 1, 2, 3 },
            function()
                hook(S.HANDLERS.PLAYER_REGEN_ENABLED, "Sources/Units.lua")(api, 20)
            end,
        },
        {
            "router target",
            "Presence/Router.lua",
            {},
            { 1, 2, K + 1, K + 2 },
            function()
                up.set("Presence/Router.lua", roots("Presence/Router.lua"), "def0", I.def) -- as its activation sets it
                hook(S.HANDLERS.PLAYER_TARGET_CHANGED, "Presence/Router.lua")(api, 20)
            end,
            true, -- a fact the router holds (nil: none)
        },
        {
            "router pull",
            "Presence/Router.lua",
            {},
            { 1, 2, K + 1, K + 2 },
            function()
                hook(S.HANDLERS.PLAYER_REGEN_DISABLED, "Presence/Router.lua")(api, 20)
            end,
            true,
        },
        {
            "attackers combat end",
            "Events/Attackers.lua",
            {},
            { 1, 2, 3 },
            function()
                hook(S.HANDLERS.PLAYER_REGEN_ENABLED, "Events/Attackers.lua")(api, 20)
            end,
        },
        {
            "tickets build",
            "Events/Tickets.lua",
            { T = true },
            { 1, 2, 3 },
            function()
                hook(I.BUILD, "Events/Tickets.lua")(I.def, 20)
            end,
        },
    }

    -- The registry (I.Scope, VirtualState.lua): each scope by its arrays' names, as the files name them.
    local FILES = {
        ["Sources/Auras.lua"] = {},
        ["Families/Resources.lua"] = { R = true },
        ["Families/Swing.lua"] = {},
        ["Families/Player.lua"] = {},
        ["Families/Casts.lua"] = { A = true },
        ["Families/Now.lua"] = {},
        ["Sources/Spellbook.lua"] = {},
        ["Sources/Power.lua"] = {},
        ["Sources/Target.lua"] = {},
        ["Presence/Router.lua"] = {},
        ["Events/Tickets.lua"] = { T = true },
    }
    local REGISTRY = require("Game.State.helpers.scoped_registry")

    -- array table -> "file: name" over every converted file (Sources/Auras.lua's own roots include its exports).
    local function names()
        local out = {}
        for file, structs in pairs(FILES) do
            for name, arr in pairs(arrays(file, structs)) do
                out[arr] = out[arr] or name
            end
        end
        for k, v in pairs(I) do -- arrays the files keep on I (Sources/Power.lua's I.maxPlain)
            if type(v) == "table" and not out[v] then
                out[v] = "I." .. k
            end
        end
        return out
    end

    it("every scope registers exactly its arrays, and Reset sets each one's none value", function()
        setup()
        local byArr = names()
        local got = {}
        for scope, L in pairs(I.SCOPES) do
            local list = {}
            for n = 1, L.n do
                list[n] = (byArr[L.arr[n]] or "?") .. "=" .. tostring(L.none[n])
                L.arr[n][7] = "sentinel"
            end
            I.Reset(scope, 7)
            for n = 1, L.n do
                assert.are.equal(L.none[n], L.arr[n][7], scope .. " " .. list[n])
            end
            table.sort(list)
            got[scope] = list
        end
        for scope in pairs(REGISTRY.scopes) do
            got[scope] = got[scope] or {}
        end
        for scope, list in pairs(got) do
            assert.are.same(REGISTRY.scopes[scope], list, scope .. ":\n  " .. table.concat(list, "\n  "))
        end
    end)

    -- A constant written at an index, by every target of the line: `x[i], R.y[i] = 0, false` (a reset by hand).
    local CONST = { ["0"] = true, ["1"] = true, ["-1"] = true, ["-1e9"] = true, ["false"] = true, ["true"] = true }
    -- (nil: a map's wipe over its own keys, no state array)
    for _, c in ipairs({ '""', "math.huge", "HUGE", "NEG", "W0", "OTHER", "UNKNOWN", "FREE", "I.UNDECIDED" }) do
        CONST[c] = true
    end
    local function trim(x)
        return (x:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local function handReset(line)
        local code = line:gsub("%-%-.*$", "")
        local lhs, rhs = code:match("^%s*([^=]-[^=~<>])%s*=%s*([^=].*)$")
        if not lhs then
            return false
        end
        for target in (lhs .. ","):gmatch("([^,]*),") do
            if not trim(target):match("^[%w_%.]+%[[^%]]+%]$") then
                return false
            end
        end
        for value in (rhs .. ","):gmatch("([^,]*),") do
            if not CONST[trim(value)] then
                return false
            end
        end
        return true
    end

    -- The scope events' handlers of every converted file: builds, the fight's edges, a target change, a swap.
    local function siteHooks(file)
        local out = {}
        local function add(list)
            for _, f in ipairs(up.handlers(list or {}, file)) do
                out[#out + 1] = f
            end
        end
        add(I.BUILD)
        add(APPLY[VS.Obs.CombatStart])
        add(APPLY[VS.Obs.CombatEnd])
        add(APPLY[VS.Obs.TargetSwap])
        add(APPLY[VS.Obs.TargetGone])
        for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED" }) do
            add(S.HANDLERS[ev])
        end
        return out
    end

    -- (none missed) No scope event's handler in a converted file resets an array by hand, except the lines
    -- helpers/scoped_registry.lua's `stays` names with their reason; the seven close sites call closeRecord.
    it("no converted scope site resets an array by hand (none missed)", function()
        setup()
        local found = {}
        for file in pairs(FILES) do
            for _, f in ipairs(siteHooks(file)) do
                local info = debug.getinfo(f, "S")
                local path = info.source:sub(2)
                local n = 0
                for line in io.lines(path) do
                    n = n + 1
                    if n >= info.linedefined and n <= info.lastlinedefined and handReset(line) then
                        local key = file .. ": " .. trim(line:gsub("%-%-.*$", ""))
                        if not REGISTRY.stays[key] then
                            found[#found + 1] = key
                        end
                    end
                end
            end
        end
        table.sort(found)
        assert.are.same({}, found, table.concat(found, "\n"))
        local src = assert(io.open(load.ROOT .. "Game/State/Sources/Auras.lua")):read("*a")
        local _, closes = src:gsub("\n%s*closeRecord%(k%)", "")
        assert.are.equal(7, closes) -- rule 1, the verdict, the avoid undo, no live slot, dark past expiry, target, pull
    end)

    for _, site in ipairs(SITES) do
        it(site[1], function()
            setup()
            local got = matrix(site[2], site[3], site[4], site[5], site[6])
            if record then
                PINS[site[1]] = got
            else
                assert.are.same(PINS[site[1]], got, site[1] .. ":\n  " .. table.concat(got, "\n  "))
            end
        end)
    end

    if record then
        teardown(function()
            local f = assert(io.open(PINS_PATH, "w"))
            f:write(
                "-- " .. PINS_PATH .. ": scoped_spec's families matrix, recorded on forever b478aa74e. Generated.\n"
            )
            f:write("return {\n")
            local names = {}
            for name in pairs(PINS) do
                names[#names + 1] = name
            end
            table.sort(names)
            for _, name in ipairs(names) do
                f:write(string.format("    [%q] = {\n", name))
                for _, l in ipairs(PINS[name]) do
                    f:write(string.format("        %q,\n", l))
                end
                f:write("    },\n")
            end
            f:write("}\n")
            f:close()
        end)
    end
end)
