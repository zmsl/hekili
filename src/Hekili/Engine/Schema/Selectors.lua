-- Engine/Schema/Selectors.lua
-- The active-spec pick on Forever: which of a class kit's specs (Hekili:NewClass, Spec.lua) runs, from the character's
-- choice and its talent points (Trees.lua's TreePoints and DominantTree). Pure functions over a kit and the settings
-- tables; Spec.lua calls them.

local _, ns = ...

local function firstOn(kit, tree)
    for _, s in ipairs(kit.trees) do
        if s.tree == tree then
            return s
        end
    end
end

--- The active spec of `kit` for a character's `choice`: { [tree] = spec key, last = tree } (a spec activated while
--- that tree was dominant, and the last dominant tree seen), or a legacy scalar spec key (before its migration). On the
--- dominant tree (else the last one seen: no points or a tie): the spec chosen for it ("stored"), else its first spec
--- ("dominant"); else the first supported spec ("default": no points yet). Returns the spec, the source and the
--- dominant tree (nil on no points or a tie).
function ns.PickSpec(kit, choice, rankOf)
    local dominant = ns.DominantTree(ns.TreePoints(kit.talents, rankOf))
    local tree, key = dominant, choice
    if type(choice) == "table" then
        tree = dominant or choice.last
        key = choice[tree or 0]
    end
    local s = type(key) == "string" and kit.specs[key]
    if s then
        return s, "stored", dominant
    end
    s = tree and firstOn(kit, tree)
    if s then
        return s, "dominant", dominant
    end
    return ns.FirstSupportedSpec(kit), "default", dominant
end
