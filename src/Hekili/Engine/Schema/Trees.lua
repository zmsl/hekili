-- Engine/Schema/Trees.lua
-- Specs per talent tree on Forever (per-spec plan, docs/superpowers/plans/2026-10-19-forever-specs.md). The client
-- reports one pseudo-spec per class, so a class pack registers one kit and a spec per tree (Hekili:NewClass,
-- Spec.lua) with ids of our own, and the active spec is the character's stored choice, else the dominant talent tree
-- (stored once), else the first supported spec. Pure functions over a kit and the settings tables; Spec.lua, Registry
-- and Options call them.

local _, ns = ...

local ID_BASE = 100000 -- above every retail spec id and Forever's pseudo-specs (1483-1491)

--- The id of slot `slot` (0: the kit; 1..n: its specs in NewClass order) of the class with client class id `classID`.
function ns.TreeSpecID(classID, slot)
    return ID_BASE + classID * 10 + slot
end

local points = { 0, 0, 0 }

--- Points spent per talent tree: `talents` is a kit's RegisterTalents table ({ tree, spell, max rank } per key),
--- `rankOf(entry)` an entry's rank. Fills and returns one reused table { [1..3] }; tree 0 (unknown) counts nowhere.
function ns.TreePoints(talents, rankOf)
    points[1], points[2], points[3] = 0, 0, 0
    for _, t in pairs(talents) do
        local tree = t[1]
        if tree == 1 or tree == 2 or tree == 3 then
            points[tree] = points[tree] + (rankOf(t) or 0)
        end
    end
    return points
end

--- The tree holding the most points: nil when no tree has any or the most is shared (a tie).
function ns.DominantTree(p)
    local best, at, ties = 0, nil, 0
    for tree = 1, 3 do
        local v = p[tree]
        if v > best then
            best, at, ties = v, tree, 1
        elseif v == best and v > 0 then
            ties = ties + 1
        end
    end
    if ties == 1 then
        return at
    end
    return nil
end

local function firstOn(kit, tree)
    for _, s in ipairs(kit.trees) do
        if s.tree == tree then
            return s
        end
    end
end

local function firstSupported(kit)
    for _, s in ipairs(kit.trees) do
        if not s.unsupported then
            return s
        end
    end
    return kit.trees[1]
end

--- The active spec of `kit`: the stored choice (`stored`, a spec key) when the kit has it ("stored"); else the first
--- spec on the dominant tree ("dominant": the caller stores it); else the first supported spec ("default": no points
--- yet or a tie; not stored, so the first points spent decide). Returns the spec and the source.
function ns.PickSpec(kit, stored, rankOf)
    local s = stored and kit.specs[stored]
    if s then
        return s, "stored"
    end
    local tree = ns.DominantTree(ns.TreePoints(kit.talents, rankOf))
    s = tree and firstOn(kit, tree)
    if s then
        return s, "dominant"
    end
    return firstSupported(kit), "default"
end

--- The spec the talents favor when it is on another tree than the stored choice (the class page's hint), else nil.
function ns.SpecHint(kit, stored, rankOf)
    local s = stored and kit.specs[stored]
    if not s then
        return nil
    end
    local tree = ns.DominantTree(ns.TreePoints(kit.talents, rankOf))
    if tree and tree ~= s.tree then
        return firstOn(kit, tree)
    end
    return nil
end

--- A spec's key in export strings, "<CLASS TOKEN>:<spec key>" ("WARRIOR:arms"); nil for a kit or a spec outside one.
function ns.SpecShareKey(spec)
    local kit = spec and rawget(spec, "kit")
    if kit then
        return kit.token .. ":" .. spec.key
    end
    return nil
end

--- A pack payload's `spec` as this session's spec id: a share key through `byShare` (another class's: kept as the
--- string, resolved when that class logs in); the class's legacy pseudo-spec id (`legacyID`) as the active spec
--- (`activeID`); anything else as is.
function ns.SpecFromShare(v, byShare, legacyID, activeID)
    if type(v) == "string" then
        return byShare[v] or v
    end
    if v ~= nil and v == legacyID and activeID then
        return activeID
    end
    return v
end

--- Rebinds every pack whose `spec` is a share key this class registered (an import made on another character).
function ns.ResolvePackSpecs(packs, byShare)
    for _, p in pairs(packs) do
        if type(p) == "table" and type(p.spec) == "string" and byShare[p.spec] then
            p.spec = byShare[p.spec]
        end
    end
end
