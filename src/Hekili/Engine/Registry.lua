local _, ns = ...
-- Engine/Registry.lua: what content registered, for the UI and Options (restructure plan, Task 5). Each view returns
-- the engine's live table (no copy, no allocation): READ-ONLY to callers; content registers through the spec API.
-- Combat, target count, spec and pack are not views: read Hekili.Engine.Output.status.

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
function Registry.SetBonus() return class.setBonuses end
function Registry.ClassFile() return class.file end
-- stylua: ignore end

--- The AceOption settings list `specID` registered with RegisterSetting ({ name, default, info } entries), or nil.
function Registry.Settings(specID)
    local spec = class.specs[specID]
    return spec and spec.settings
end

--- True (and a reason) when ability `key` is disabled by the profile (strict: by the user's own choice only).
function Registry.IsDisabled(key, strict)
    return state:IsDisabled(key, strict)
end
