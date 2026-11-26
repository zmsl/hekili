-- Hekili_Shared/Shared/Items.lua
-- The equipped-item actions every class shares (shared-content spec §4.4), through Engine/Schema/Shared.lua into `all`:
-- `use_items` (the APL verb Core.lua expands into the equipped trinkets) and the slots Events.lua rebinds on an equipment
-- change (trinket1, trinket2, main_hand; null_cooldown while a slot has no on-use), the on-use trinkets (lane gear-1,
-- G6: one ability each, so a worn one joins `use_items`), and class.trinkets, State.lua's per-item map. Hekili's unused
-- item-settings helpers and its unlisted unusable-trinket stub were dropped.

local class = Hekili.Class

local shared = Hekili:NewShared()

-- Should handle trinkets/items internally.
-- 1.  Check APLs and don't try to recommend items that have their own APL entries.
-- 2.  Respect item preferences registered in spec options.

shared:RegisterAbility("use_items", {
    name = "Use Items", -- l10n: verbatim
    listName = "|T136243:0|t |cff00ccff[Use Items]|r",
    cast = 0,
    cooldown = 120,
    gcd = "off",
})

local items = {
    null_cooldown = {
        name = "|cff00ccff[Null Cooldown]|r", -- l10n: verbatim
        listName = "|T136243:0|t |cff00ccff[Null Cooldown]|r",
        cast = 0,
        cooldown = 0.001,
        gcd = "off",

        startsCombat = false,

        unlisted = true,
    },

    trinket1 = {
        name = "|cff00ccff[Trinket #1]|r", -- l10n: verbatim
        listName = "|T136243:0|t |cff00ccff[Trinket #1]|r",
        cast = 0,
        cooldown = 600,
        gcd = "off",

        usable = false,

        copy = "actual_trinket1",
    },

    trinket2 = {
        name = "|cff00ccff[Trinket #2]|r", -- l10n: verbatim
        listName = "|T136243:0|t |cff00ccff[Trinket #2]|r",
        cast = 0,
        cooldown = 600,
        gcd = "off",

        usable = false,

        copy = "actual_trinket2",
    },

    main_hand = {
        name = "|cff00ccff[" .. INVTYPE_WEAPONMAINHAND .. "]|r",
        listName = "|T136243:0|t |cff00ccff[" .. INVTYPE_WEAPONMAINHAND .. "]|r",
        cast = 0,
        cooldown = 600,
        gcd = "off",

        usable = false,

        copy = "actual_main_hand",
    },
}

for key, def in pairs(items) do
    shared:RegisterAbility(key, def)
end

class.trinkets = {
    [0] = { -- for when nothing is equipped.
    },
}

-- The on-use trinkets, from the wowsims pin's db.json (ab0f00e4fc, the item's first itemEffect: buffId the use spell,
-- onUse cooldownMs, categoryId, categoryCooldownMs): { item, key, use spell, cooldown, category, category cooldown }.
-- Each is an off-GCD ability on its item (Events.lua binds a worn one to trinket1/trinket2 and `use_items`), its use
-- spell a `copy` so our cast of it is the ability's (the belief tracks it by that ID; the cast row resolves to it), on
-- its item's cooldown; a use holds every other member of its category for the category's cooldown, never shortening
-- a longer one (`lockCooldown`, in the simulation and the belief alike). Offered while the client calls the item usable
-- (plain [W PR13]; a secret answer is not usable). No buff aura is registered: no line reads one yet (State.lua's
-- `trinket.*.buff` reads stay down), and every registered aura is tracked by the belief.
-- Owner call pending: the Weakness Analyzer's cooldown is the pin's 360 s (90 s in wowsims e2842f0a78); a live
-- measurement beats both (probe-trinkets-runsheet.md, probe 6).
local ON_USE = {
    { 272438, "weakness_analyzer", 1291101, 360, 1141, 20 },
    { 18820, "talisman_of_ephemeral_power", 23271, 90, 1141, 15 },
    { 19339, "mind_quickening_gem", 23723, 300, 1141, 20 },
    { 274759, "everlook_pathcarver", 1295270, 300, 1141, 15 },
    { 13968, "eye_of_the_beast", 1287840, 300, 1141, 20 },
    { 13965, "blackhands_breadth", 1318944, 300, 1141, 20 },
}

local C_Item, issecretvalue = Hekili.Client.C_Item, Hekili.Client.issecretvalue

-- A use's lock on the rest of its category: one closure per layer (the simulation's `handler` and the belief's `now`
-- are each bound to their own context).
local function locker(key, members, duration)
    return function()
        for i = 1, #members do
            if members[i] ~= key then
                lockCooldown(members[i], duration) -- luacheck: ignore 113 (the context's verb)
            end
        end
    end
end

local byCategory = {}
for _, u in ipairs(ON_USE) do
    byCategory[u[5]] = byCategory[u[5]] or {}
    table.insert(byCategory[u[5]], u[2])
end

for _, u in ipairs(ON_USE) do
    local item, key, spell, cooldown, category, lock = u[1], u[2], u[3], u[4], u[5], u[6]
    shared:RegisterAbility(key, {
        cast = 0,
        cooldown = cooldown,
        gcd = "off",
        copy = spell,
        item = item,
        category = category,
        categoryCooldown = lock,

        startsCombat = false,
        toggle = "cooldowns",

        usable = function()
            local ok = C_Item.IsUsableItem(item)
            return not issecretvalue(ok) and ok == true, "not usable"
        end,

        handler = locker(key, byCategory[category], lock),
        now = locker(key, byCategory[category], lock),
    })
    class.trinkets[item] = { ability = key }
end

setmetatable(class.trinkets, {
    __index = function(t, k)
        return t[0]
    end,
})
