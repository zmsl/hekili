local _, ns = ...
-- Engine/Registry.lua: what content registered, for the UI and Options (restructure plan, Task 5). Each view returns
-- the engine's live table (no copy, no allocation): READ-ONLY to callers; content registers through the spec API.
-- Combat, target count, spec and pack are not views: read Hekili.Engine.Output.status. The commands are
-- Engine.Evaluate (below) and Engine.Snapshot (Engine/Snapshot.lua).

local class, state = Hekili.Class, Hekili.State

local Registry = {
    GCD_SPELL = ns.VirtualStateInternal.GCD_SPELL,
}
Hekili.Engine.Registry = Registry

-- stylua: ignore start
function Registry.Specs() return class.specs end
function Registry.Abilities() return class.abilities end
function Registry.AbilityList() return class.abilityList end
function Registry.ItemList() return class.itemList end
function Registry.Auras() return class.auras end
function Registry.AuraList() return class.auraList end
function Registry.Potions() return class.potions end
function Registry.PotionList() return class.potionList end
function Registry.Gear() return class.gear end
function Registry.Talents() return class.talents end
function Registry.ClassFile() return class.file end
-- stylua: ignore end

--- The AceOption settings list `specID` registered with RegisterSetting ({ name, default, info } entries), or nil.
function Registry.Settings(specID)
    local spec = class.specs[specID]
    return spec and spec.settings
end

--- True (and a reason) when ability `key` is disabled by the profile (strict: by the user's own choice only).
function Registry.IsDisabled(key, strict)
    Hekili:ResetSpellCaches() -- the options panel reads between predictions: never a cached answer
    return state:IsDisabled(key, strict)
end

--- The pack editor's preview of `pack`:`list`:`action` (pack and list names, action index): resets the state, loads
--- the pack's other variables, then fills `results` with the values of the entry's conditions (`mod` nil) or of its
--- modifier `mod` (a ModElements key: "value", "value_else", "strict_if"). Returns results, list, action.
function Hekili.Engine.Evaluate(pack, list, action, mod, results)
    state.reset("Primary", true)

    local apack = rawget(Hekili.Engine.settings.packs, pack)

    -- Let's load variables, just in case.
    for name, alist in pairs(apack.lists) do
        state.this_list = name

        for i, entry in ipairs(alist) do
            if name ~= list or i ~= action then
                if entry.action == "variable" and entry.var_name then
                    state:RegisterVariable(entry.var_name, pack .. ":" .. name .. ":" .. i, name)
                end
            end
        end
    end

    local entry = apack and apack.lists[list]
    entry = entry and entry[action]

    state.this_action = entry.action
    state.this_list = list

    local scriptID = pack .. ":" .. list .. ":" .. action
    state.scriptID = scriptID
    Hekili.Scripts:StoreValues(results, scriptID, mod)

    return results, list, action
end
