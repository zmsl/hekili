-- Export.lua: /fprobe export dumps the player's class data (spellbook, talent trees, stances) into
-- ForeverProbeDB.export (overwritten each time), out of combat only; /reload writes it to disk.
-- Every client value goes through IsSecret() first (secrets are stored as "S"); every client call runs under pcall
-- ("E:<msg>" when it raised, "-" when the API is absent). Encoding as Core.lua, except that strings keep their full
-- length (descriptions and tooltip lines are longer than Core's 80-character cut) and returned tables are copied whole.
local ADDON_NAME, ns = ...

local IsSecret, Enc, ErrText, Print = ns.IsSecret, ns.Enc, ns.ErrText, ns.Print
local MAX_DEPTH = 6 -- returned tables nest a few levels (tooltip lines, colours); deeper is cut as "<deep>"

-- Plain copy of a client value: "S" secret, "nil", "=<text>" (full length), number/boolean via Enc, tables walked.
local function Val(v, depth)
    if IsSecret(v) then
        return "S"
    end
    if type(v) == "string" then
        return "=" .. v
    end
    if type(v) ~= "table" then
        return Enc(v)
    end
    depth = depth or 0
    if depth >= MAX_DEPTH then
        return "<deep>"
    end
    local out = {}
    for k, x in pairs(v) do
        if IsSecret(k) then
            out["<secretKey>"] = true
        elseif type(k) == "number" or type(k) == "string" then
            out[k] = Val(x, depth + 1)
        end
    end
    return out
end

local function Fn(ns1, name)
    local t = _G[ns1]
    if type(t) ~= "table" then
        return nil
    end
    return t[name]
end

-- pcall(fn, ...) storing rec[key] = Val(first return) (or "-" / "E:<msg>"); returns the first return when plain.
local function Try(rec, key, fn, ...)
    if type(fn) ~= "function" then
        rec[key] = "-"
        return nil
    end
    local ok, v = pcall(fn, ...)
    if not ok then
        rec[key] = ErrText(v)
        return nil
    end
    rec[key] = Val(v)
    if IsSecret(v) then
        return nil
    end
    return v
end

-- Same, keeping every return: rec[key] = { n = count, [i] = Val(return i) }.
local function TryAll(rec, key, fn, ...)
    if type(fn) ~= "function" then
        rec[key] = "-"
        return
    end
    local function pack(...)
        return select("#", ...), { ... }
    end
    local n, r = pack(pcall(fn, ...))
    if not r[1] then
        rec[key] = ErrText(r[2])
        return
    end
    local out = { n = n - 1 }
    for i = 2, n do
        out[i - 1] = Val(r[i])
    end
    rec[key] = out
end

-- Plain number from a table field, or nil.
local function Num(t, field)
    if IsSecret(t) or type(t) ~= "table" then
        return nil
    end
    local v = t[field]
    if IsSecret(v) or type(v) ~= "number" then
        return nil
    end
    return v
end

-- Tooltip lines of a spell: { {l = leftText, r = rightText}, ... } (or the encoded failure).
local function Tooltip(rec, id)
    local data = Try(rec, "tip", Fn("C_TooltipInfo", "GetSpellByID"), id)
    if type(data) ~= "table" then
        return -- rec.tip holds the encoded failure
    end
    local lines = data.lines
    if IsSecret(lines) or type(lines) ~= "table" then
        rec.tip = Val(lines)
        return
    end
    local tip = {}
    for k = 1, #lines do
        local line = lines[k]
        if IsSecret(line) or type(line) ~= "table" then
            tip[k] = Val(line)
        else
            tip[k] = { l = Val(line.leftText), r = Val(line.rightText) }
        end
    end
    rec.tip = tip
end

-- Name, description and tooltip of a spell ID (shared by the spellbook and the talent definitions).
local function SpellText(rec, id)
    Try(rec, "info", Fn("C_Spell", "GetSpellInfo"), id)
    Try(rec, "desc", Fn("C_Spell", "GetSpellDescription"), id)
    Tooltip(rec, id)
end

local function SpellDetail(rec, id)
    SpellText(rec, id)
    Try(rec, "cost", Fn("C_Spell", "GetSpellPowerCost"), id)
    Try(rec, "charges", Fn("C_Spell", "GetSpellCharges"), id)
    Try(rec, "cd", Fn("C_Spell", "GetSpellCooldown"), id)
    Try(rec, "passive", Fn("C_Spell", "IsSpellPassive"), id)
    Try(rec, "override", Fn("C_Spell", "GetOverrideSpell"), id)
    Try(rec, "known", Fn("C_SpellBook", "IsSpellKnown"), id)
    Try(rec, "knownOrBook", Fn("C_SpellBook", "IsSpellKnownOrInSpellBook"), id)
    Try(rec, "isPlayerSpell", ns.G("IsPlayerSpell"), id)
end

local function Spells(ex)
    local bank = 0 -- Enum.SpellBookSpellBank.Player
    if type(Enum) == "table" and type(Enum.SpellBookSpellBank) == "table" and type(Enum.SpellBookSpellBank.Player) == "number" then
        bank = Enum.SpellBookSpellBank.Player
    end
    local lines, spells = {}, {}
    ex.skillLines, ex.spells = lines, spells
    local n = Try(ex, "numSkillLines", Fn("C_SpellBook", "GetNumSpellBookSkillLines"))
    if type(n) ~= "number" then
        return 0
    end
    for i = 1, n do
        local line = {}
        lines[i] = line
        local info = Try(line, "info", Fn("C_SpellBook", "GetSpellBookSkillLineInfo"), i)
        local offset, count = Num(info, "itemIndexOffset"), Num(info, "numSpellBookItems")
        if offset and count then
            for j = offset + 1, offset + count do
                local rec = { index = j, line = i }
                spells[#spells + 1] = rec
                local item = Try(rec, "item", Fn("C_SpellBook", "GetSpellBookItemInfo"), j, bank)
                TryAll(rec, "itemName", Fn("C_SpellBook", "GetSpellBookItemName"), j, bank)
                local id = Num(item, "spellID")
                if id then
                    SpellDetail(rec, id)
                end
            end
        end
    end
    return #spells
end

-- The talent walk, as Probes.lua's TalentWalk and VirtualState's Sources/Talents.lua: active config -> treeIDs ->
-- tree nodes -> node info -> each entry -> its definition -> the definition spell's text.
local function Talents(ex)
    local t = { trees = {} }
    ex.talents = t
    local nodes, nTrees = 0, 0
    local cfg = Try(t, "configID", Fn("C_ClassTalents", "GetActiveConfigID"))
    if type(cfg) ~= "number" then
        return 0, 0
    end
    local info = Try(t, "configInfo", Fn("C_Traits", "GetConfigInfo"), cfg)
    local ids = type(info) == "table" and info.treeIDs or nil
    if IsSecret(ids) or type(ids) ~= "table" then
        return 0, 0
    end
    for _, treeID in ipairs(ids) do
        if not IsSecret(treeID) and type(treeID) == "number" then
            nTrees = nTrees + 1
            local tree = { id = treeID, nodes = {} }
            t.trees[#t.trees + 1] = tree
            Try(tree, "info", Fn("C_Traits", "GetTreeInfo"), cfg, treeID)
            local nodeIDs = Try(tree, "nodeIDs", Fn("C_Traits", "GetTreeNodes"), treeID)
            if type(nodeIDs) == "table" then
                tree.nodeIDs = nil -- the node records carry the IDs
                for _, nodeID in ipairs(nodeIDs) do
                    local rec = { id = Val(nodeID), entries = {} }
                    tree.nodes[#tree.nodes + 1] = rec
                    nodes = nodes + 1
                    local node = not IsSecret(nodeID) and Try(rec, "node", Fn("C_Traits", "GetNodeInfo"), cfg, nodeID)
                    local entryIDs = type(node) == "table" and node.entryIDs or nil
                    if not IsSecret(entryIDs) and type(entryIDs) == "table" then
                        for _, entryID in ipairs(entryIDs) do
                            local e = { id = Val(entryID) }
                            rec.entries[#rec.entries + 1] = e
                            if not IsSecret(entryID) and type(entryID) == "number" then
                                local entry = Try(e, "entry", Fn("C_Traits", "GetEntryInfo"), cfg, entryID)
                                local defID = Num(entry, "definitionID")
                                local def = defID and Try(e, "def", Fn("C_Traits", "GetDefinitionInfo"), defID)
                                local spellID = Num(def, "spellID")
                                if spellID then
                                    SpellText(e, spellID)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nodes, nTrees
end

local function Stances(ex)
    local s = { forms = {} }
    ex.stances = s
    Try(s, "current", ns.G("GetShapeshiftForm"))
    local n = Try(s, "num", ns.G("GetNumShapeshiftForms"))
    if type(n) ~= "number" then
        return 0
    end
    for i = 1, n do
        TryAll(s.forms, i, ns.G("GetShapeshiftFormInfo"), i) -- icon, active, castable, spellID
    end
    return n
end

function ns.Export()
    if ns.InCombat() then
        Print("export refused in combat: leave combat and run /fprobe export again")
        return
    end
    local ex = { meta = { when = date("%Y-%m-%d %H:%M"), version = ns.VERSION } }
    local m = ex.meta
    Try(m, "time", ns.G("GetTime"))
    Try(m, "level", ns.G("UnitLevel"), "player")
    Try(m, "class", ns.G("UnitClassBase"), "player")
    TryAll(m, "build", ns.G("GetBuildInfo"))
    Try(m, "spec", ns.G("GetSpecialization"))
    Try(m, "specInfo", Fn("C_SpecializationInfo", "GetSpecialization"))
    local nSpells = Spells(ex)
    local nNodes, nTrees = Talents(ex)
    local nStances = Stances(ex)
    ns.db.export = ex
    Print(nSpells .. " spells, " .. nNodes .. " talent nodes in " .. nTrees .. " trees, " .. nStances
        .. " stances; /reload to write ForeverProbeDB to disk")
end
