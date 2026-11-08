-- Engine/Schema/Selectors.lua
-- The active-spec pick on Forever and the class kits' selectors (owner design 2026-11-08; the idea and API shape after
-- the Hekili classic branch's RegisterPackSelector, GPL-3.0, no code taken). Which of a class kit's specs
-- (Hekili:NewClass, Spec.lua) runs: the character's choice for the dominant tree, else the first selector whose
-- condition holds (a spec and its pack, from the talents), else the dominant tree's first spec, else the first
-- supported one. The choice is made at the pack level: a pack the player activated fixes its spec; a stored spec
-- without one yields to the selectors. And when a selector may set a spec's pack
-- (ns.SelectPack: the player's pick and custom priorities stay). Functions over a kit and the settings tables (tree
-- points from Trees.lua), pure of Hekili state: they write only the engine's selector bookkeeping (a selector's
-- `bound`, the kit's `selectorErrors`/`selectorError`) and, in SelectPack, the spec profile's `package`/`packAuto`.
-- Spec.lua calls them on login, a talent change and a spec change, never per poll; its kit:RegisterSelector stores
-- the selectors.

local _, ns = ...

local function firstOn(kit, tree)
    for _, s in ipairs(kit.trees) do
        if s.tree == tree then
            return s
        end
    end
end

-- A condition's environment, one for every kit (one class a session) and reused: `talent.<name>.rank` (the kit's
-- registered talents, ranked by the caller's `rankOf`; one cursor table, so read `.rank` at once), the level, max, min.
local cursor = { rank = 0 }
local curKit, curRank
local env = {
    max = math.max,
    min = math.min,
    level = 0,
    talent = setmetatable({}, {
        __index = function(_, name)
            local t = curKit.talents[name]
            if t == nil then
                error("no talent " .. tostring(name), 2)
            end
            cursor.rank = curRank(t) or 0
            return cursor
        end,
    }),
}

-- The first of `kit`'s selectors (RegisterSelector's order) whose spec has priorities and whose condition, called with
-- the points per tree, holds; a condition that raises counts as false and on `kit.selectorErrors` (its message in
-- `kit.selectorError`). Returns the selector and its spec.
local function firstSelector(kit, p, rankOf, level)
    local list = kit.selectors
    if not list then
        return nil
    end
    curKit, curRank, env.level = kit, rankOf, level or 0
    for i = 1, #list do
        local sel = list[i]
        local s = kit.specs[sel.spec]
        if s and not s.unsupported then
            if not sel.bound then
                setfenv(sel.condition, env)
                sel.bound = true
            end
            local ok, yes = pcall(sel.condition, p[1], p[2], p[3])
            if not ok then
                kit.selectorErrors = (kit.selectorErrors or 0) + 1
                kit.selectorError = yes
            elseif yes then
                return sel, s
            end
        end
    end
    return nil
end

--- The active spec of `kit` for a character's `choice`: { [tree] = spec key, last = tree } (a spec activated while
--- that tree was dominant, and the last dominant tree seen), or a legacy scalar spec key (before its migration). On the
--- dominant tree (else the last one seen: no points or a tie): the spec chosen for it ("stored") when its profile in
--- `specs` (the profile's specs table) carries the player's pack (`packManual`); else the first selector that holds at
--- `level` ("selector"); else the spec chosen for the tree, if any ("stored"); else the tree's first spec
--- ("dominant"); else the first supported spec ("default": no points yet). Returns the spec, the source, the dominant tree (nil on no points or a tie) and the
--- selector (nil unless the source is "selector"). With no points or a tie and `held` (the spec the last settle with
--- points chose), that spec stays ("held") unless the player activated a pack for the tree (owner ruling I2).
function ns.PickSpec(kit, choice, rankOf, level, specs, held)
    local p = ns.TreePoints(kit.talents, rankOf)
    local dominant = ns.DominantTree(p)
    local tree, key = dominant, choice
    if type(choice) == "table" then
        tree = dominant or choice.last
        key = choice[tree or 0]
    end
    local s = type(key) == "string" and kit.specs[key]
    -- activation is at the pack level (owner 2026-11-08): a stored spec whose pack the player chose is fixed; one
    -- without (a choice from before, or a pack handed back to the default) yields to the selectors
    local sp = s and specs and rawget(specs, s.id)
    if type(sp) == "table" and sp.packManual then
        return s, "stored", dominant
    end
    if dominant == nil and held then
        return held, "held", nil -- no points or a tie: the last settled spec stays, as choice.last did
    end
    local sel, ss = firstSelector(kit, p, rankOf, level)
    if ss then
        return ss, "selector", dominant, sel
    end
    if s then
        return s, "stored", dominant
    end
    s = tree and firstOn(kit, tree)
    if s then
        return s, "dominant", dominant
    end
    return ns.FirstSupportedSpec(kit), "default", dominant
end

--- Sets `spec`'s pack in its profile table `sp` to selector `sel`'s (nil: no selector holds, so back to the spec's
--- default) when the pack in place is not the player's: `sp.packManual` (a pick in the options or by command) blocks
--- it, and so does any pack but the default or the one a selector set (`sp.packAuto`, its name), so a profile from
--- before selectors keeps a non-default pick. A custom priority (no `builtIn`) is never replaced, and only a built-in
--- priority of `spec` that exists in `packs` is written. Returns true when it changed the pack.
function ns.SelectPack(sp, packs, spec, sel)
    if type(sp) ~= "table" or sp.packManual then
        return false
    end
    local cur, auto, default = sp.package, sp.packAuto, spec.options.package
    if cur ~= nil and cur ~= default and cur ~= auto then
        return false
    end
    if sel == nil and (auto == nil or cur ~= auto) then
        return false -- no selector holds: only a selector's own pick goes back to the default
    end
    local have = cur ~= nil and rawget(packs, cur)
    if type(have) == "table" and not have.builtIn then
        return false
    end
    local name = sel and sel.pack or default
    if name == nil or name == cur then
        return false
    end
    local want = rawget(packs, name)
    if type(want) ~= "table" or not want.builtIn or want.spec ~= spec.id then
        return false
    end
    sp.package, sp.packAuto = name, sel and name or nil
    return true
end
