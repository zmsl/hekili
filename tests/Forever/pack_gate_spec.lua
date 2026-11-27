-- tests/Forever/pack_gate_spec.lua: a record-only arm's own floors (pack_gate.ARM_FLOORS, L1795).
local ab = require("Game.harness.ab")
local pack_gate = require("Forever.helpers.pack_gate")

describe("pack_gate's arm floors", function()
    it("replace the named fields in that arm alone; every other field and arm keeps M.FLICKER's", function()
        local arm, check = ab.arm, ab.check
        finally(function()
            ab.arm, ab.check = arm, check
        end)
        local missed
        ab.check = function(ok, _, line)
            if not ok then
                missed[#missed + 1] = line:match("^[^:]+")
            end
        end
        local fl = pack_gate.FLICKER["Arms"]
        local r = { flicker = 0.40, retracted = 0, readyShort = 0, heldReady = fl.heldReady + 1, loOver = 0 }
        for name, want in pairs({
            default = { "flicker floor", "held-while-ready floor" },
            bands = { "held-while-ready floor" },
            ["bands-drop"] = { "flicker floor", "held-while-ready floor" },
        }) do
            ab.arm = function()
                return name
            end
            missed = {}
            pack_gate.flicker("Arms", r, "line", true)
            assert.are.same(want, missed, name)
        end
    end)

    -- (L1814) the gated shipped arm: a row it measured reads ok there, the default and bands arms keep their floors
    it("the shipped arm's own floors apply in that arm alone, each only where it reads worse", function()
        local arm, check = ab.arm, ab.check
        finally(function()
            ab.arm, ab.check = arm, check
        end)
        local missed
        ab.check = function(ok, _, line)
            if not ok then
                missed[#missed + 1] = line:match("^[^:]+")
            end
        end
        local r = { flicker = 0, retracted = 0, readyShort = 0, heldReady = 194, loOver = 0 }
        for name, want in pairs({
            default = { "held-while-ready floor" },
            bands = { "held-while-ready floor" },
            shipped = {},
        }) do
            ab.arm = function()
                return name
            end
            missed = {}
            pack_gate.flicker("Balance", r, "line", true)
            assert.are.same(want, missed, name)
        end
        local fields = { flicker = true, retracted = true, readyShort = true, heldReady = true, loOver = true }
        for label, own in pairs(pack_gate.ARM_FLOORS.shipped) do
            local fl = pack_gate.FLICKER[label]
            assert.is_table(fl, label) -- a gated label's other fields come from M.FLICKER
            for k, v in pairs(own) do
                if k ~= "cause" then -- a row's causes, not a floor (the cause spec below)
                    assert.is_true(fields[k], label .. " " .. k)
                    assert.is_true(v > (fl[k] or 0), label .. " " .. k) -- named only where the shipped arm reads worse
                end
            end
        end
    end)

    it("merge the arm's loOver too: a row its default floors would MISS reads ok", function()
        local arm, check, own = ab.arm, ab.check, pack_gate.ARM_FLOORS.bands["SM Ruin"]
        finally(function()
            ab.arm, ab.check, pack_gate.ARM_FLOORS.bands["SM Ruin"] = arm, check, own
        end)
        -- no arm names a loOver floor since band-edge (L1947): a stand-in row, as the old bands SM Ruin 279
        pack_gate.ARM_FLOORS.bands["SM Ruin"] = { loOver = 279 }
        local missed
        ab.check = function(ok, _, line)
            if not ok then
                missed[#missed + 1] = line:match("^%S+")
            end
        end
        local r = { flicker = 0, retracted = 0, readyShort = 0, heldReady = 0, loOver = 279 }
        for name, want in pairs({ default = { "floor-above-truth" }, bands = {} }) do
            ab.arm = function()
                return name
            end
            missed = {}
            pack_gate.flicker("SM Ruin", r, "line", true)
            assert.are.same(want, missed, name)
        end
    end)
end)

-- (refactor lane 4, L1827) every floor names its cause: pack_gate.lua's header, "The cause field"
local function token(s)
    return s:match("^L%d+$") or s:match("^%w[%w%./_-]*@%x%x%x%x%x%x%x+$")
end

local function causeOk(c)
    if c == "untraced" then
        return true
    end
    if type(c) ~= "string" then
        return false
    end
    for part in (c .. " + "):gmatch("(.-) %+ ") do
        if not token(part) then
            return false
        end
    end
    return true
end

--- Every problem with the causes of `tables` ({ name = { label = row } }), sorted: a floor field above 0 with no
--- cause or a malformed one, or a cause naming no floor of its row.
local function causeProblems(tables)
    local out = {}
    for name, rows in pairs(tables) do
        for label, row in pairs(rows) do
            local cause = row.cause or {}
            for k, v in pairs(row) do
                if k ~= "cause" and v ~= 0 and not causeOk(cause[k]) then
                    out[#out + 1] = ("%s %s %s: cause %s"):format(name, label, k, tostring(cause[k]))
                end
            end
            for k in pairs(cause) do
                if (row[k] or 0) == 0 then
                    out[#out + 1] = ("%s %s %s: a cause with no floor"):format(name, label, k)
                end
            end
        end
    end
    table.sort(out)
    return out
end

describe("pack_gate's floor causes", function()
    it("every floor field above 0 in M.FLICKER and both ARM_FLOORS tables names its cause #self", function()
        local tables = { FLICKER = pack_gate.FLICKER }
        for arm, rows in pairs(pack_gate.ARM_FLOORS) do
            tables[arm] = rows
        end
        assert.are.same({}, causeProblems(tables))
    end)

    it("the check refuses a missing, malformed or stray cause and takes the three forms #self", function()
        assert.are.same(
            {
                "t A flicker: cause nil",
                "t B flicker: cause because",
                "t C flicker: cause untraced + L1",
                "t D heldReady: a cause with no floor",
                "t E loOver: cause L12 + abc@12",
            },
            causeProblems({
                t = {
                    A = { flicker = 0.1 },
                    B = { flicker = 0.1, cause = { flicker = "because" } },
                    C = { flicker = 0.1, cause = { flicker = "untraced + L1" } },
                    D = { flicker = 0, heldReady = 0, cause = { heldReady = "L1" } },
                    E = { loOver = 3, cause = { loOver = "L12 + abc@12" } },
                    F = {
                        flicker = 0.1,
                        loOver = 2,
                        heldReady = 1,
                        retracted = 0,
                        cause = {
                            flicker = "L1814",
                            loOver = "untraced",
                            heldReady = "integ/0.10.1@5bd9a14d5 + L1383",
                        },
                    },
                },
            })
        )
    end)

    -- item 4 (L1889 7): the one rule names an arm row in both arm tables or lists why not (M.ONE_RULE_EXCEPTIONS)
    it("the bands and shipped tables name the same fields, but for the listed exceptions #self", function()
        local B, S = pack_gate.ARM_FLOORS.bands, pack_gate.ARM_FLOORS.shipped
        local only = {}
        for _, pair in ipairs({ { "bands", B, S }, { "shipped", S, B } }) do
            for label, row in pairs(pair[2]) do
                for k in pairs(row) do
                    if k ~= "cause" and (pair[3][label] or {})[k] == nil then
                        only[#only + 1] = pair[1] .. " " .. label .. " " .. k
                    end
                end
            end
        end
        table.sort(only)
        local listed = {}
        for _, e in ipairs(pack_gate.ONE_RULE_EXCEPTIONS) do
            assert.is_string(e.why, e[2])
            local rows = e[1] == "FLICKER" and pack_gate.FLICKER or pack_gate.ARM_FLOORS[e[1]]
            assert.is_number((rows[e[2]] or {})[e[3]], table.concat(e, " ")) -- a listed row exists
            if e[1] ~= "FLICKER" then
                listed[#listed + 1] = table.concat(e, " ")
            end
        end
        table.sort(listed)
        assert.are.same(listed, only)
        -- the FLICKER rows whose reading equals the floor (gate-ab default arm, 672c0df31): the rule's + 0.01 would loosen them
        for _, at in ipairs({ { "Combat", "flicker" }, { "Fury L60", "retracted" } }) do
            local found
            for _, e in ipairs(pack_gate.ONE_RULE_EXCEPTIONS) do
                found = found or (e[1] == "FLICKER" and e[2] == at[1] and e[3] == at[2])
            end
            assert.is_true(found, "FLICKER " .. at[1] .. " " .. at[2] .. " reads its floor: list it")
        end
        for label, row in pairs(B) do -- the bands arm, as the shipped one: named only where it reads worse
            local fl = pack_gate.FLICKER[label]
            assert.is_table(fl, label)
            for k, v in pairs(row) do
                assert.is_true(k == "cause" or v > (fl[k] or 0), label .. " " .. k)
            end
        end
    end)
end)
