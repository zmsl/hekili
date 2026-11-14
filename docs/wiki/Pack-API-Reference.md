<!--
Purpose: Every Register* call: parameters and an example.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack overview](Pack-Overview).
-->
The **pack API** is the set of calls a content addon uses to declare a class, the shared content or a race to the Hekili Forever core. A class file calls `Hekili:NewClass` and then the `Register*` calls on the kit it returns; the shared content and the race files use smaller objects from `Hekili:NewShared` and `Hekili:NewRace`. The table below lists every call with its parameters, and the sections after it give an example of each call from a shipped file.

| Pack API | |
|---|---|
| Entry points | `Hekili:NewClass(token, definition)`, `Hekili:NewShared()`, `Hekili:NewRace(token, raceID)` |
| Other public names | `Hekili.State`, `Hekili.Class`, `Hekili.Client`, `Hekili:GetLocale(addonName)` |
| Defined in | `src/Hekili/Engine/Schema/Spec.lua`, `Spec/*.lua`, `Shared.lua`, `Races.lua`, `Spec/Kits.lua` |
| Version | `CONTENT_API` in `src/Hekili/Engine/Content.lua` ([Pack overview](Pack-Overview#the-content-api-version)) |

## Every call

The table is generated from the definitions. The "Offered by" column names the object that has the call, and "Used by" the content addons that call it today.

<!-- GENERATED:register-api -->
<!-- /GENERATED -->

Calls registered on the class kit reach every spec of the class. A function a call stores (a state expression, a hook, an ability's `handler`) runs in the simulation with the simulated `state` as its environment, unless the call says otherwise. `kit:RetirePacks(names)` is not in the table, because its name does not start with `Register`; it is described under [Packs and settings](#packs-and-settings).

## Examples

The examples are shortened from the files named, with comments written for this page.

### Entry points

`Hekili:NewClass(token, definition)` returns the class kit, or nil when the player is another class. `definition.specs` lists the specs ([Pack talents, specs and selectors](Pack-Talents-Specs-And-Selectors#spec-entries)). From `src/Hekili_Druid/Druid.lua`:

```lua
local spec = Hekili:NewClass("DRUID", { specs = { --[[ one entry per spec ]] } })
if not spec then
    return
end
```

`Hekili:NewShared()` returns the shared object, whose registrations apply to every class. `Hekili:NewRace(token, raceID)` returns a race object, live only when the player is that race. `Hekili:GetLocale(addonName)` returns the addon's string table.

### Abilities and auras

`RegisterAbility(key, data)` and `RegisterAbilities({ [key] = data })` declare abilities ([Pack abilities reference](Pack-Abilities-Reference)). `RegisterAura(key, data)` and `RegisterAuras({ [key] = data })` declare auras ([Pack auras reference](Pack-Auras-Reference)). The shared and race objects offer the single forms. From `src/Hekili_Shared/Shared/Consumables.lua`:

```lua
shared:RegisterAura("potion", {
    alias = { "fake_potion" },
    aliasMode = "first",
    aliasType = "buff",
    duration = 30,
})
```

A race ability registers on every character, but is known only to that race. `RegisterPower` and `RegisterPowers` are inherited from the original Hekili; no pack uses them.

### Resources

`RegisterResource(powerType, regen, model, meta)` declares a resource ([Pack resources and regen](Pack-Resources-And-Regen)). From `src/Hekili_Druid/Druid.lua`:

```lua
spec:RegisterResource(Enum.PowerType.ComboPoints)
```

The shared and race objects offer `RegisterResourceMod({ max = pct })`, which raises every resource's maximum by a share. From `src/Hekili_Shared/Races/Gnome.lua`:

```lua
race:RegisterResourceMod({ max = 0.05 })
```

The race object also offers `RegisterRegenMod({ resource, aura, mult | spirit | share | mp5 })`, a regeneration entry on the class's resource while a player aura is up. From `src/Hekili_Shared/Races/HighOrderSkyborne.lua`:

```lua
race:RegisterRegenMod({ resource = "mana", aura = "energized", mult = 1.5 })
```

### Cost and GCD modifiers

`RegisterCostMod({ aura, pct | flat, charges, spells, unless })` makes the abilities in scope cheaper while the player's aura is up. `spells` lists spell IDs (an ability matches by its `id` or a `copy` rank); without it every ability paid from the resource is in scope. With `charges`, each cast whose declared cost is above 0 takes a stack. While the aura named by `unless` is up, the modifier does nothing. The class kit, the shared object and the race object all offer it. From `src/Hekili_Druid/Druid.lua`:

```lua
spec:RegisterCostMod({
    aura = "poised",
    flat = -10,
    charges = 1,
    spells = { 1082, 1822, 5221, 6785, 9005, 1079, 1328618, 8998 },
})
```

`RegisterGcdMod({ aura, pct, spells })` makes a spell GCD `(1 + pct)` times as long while the aura is up, before the GCD's minimum. From the same file:

```lua
spec:RegisterGcdMod({ aura = "natures_grace", pct = 1 / 1.1 - 1 })
```

Both layers read both kinds of modifier, so an ability's own `spend` and `gcd` never mention the proc.

### Talents, specs and gear

`RegisterTalents({ [key] = { tree, spellID, maxRank } })` lists the class's talents. `RegisterSelector(key, { spec, pack }, condition)` picks a spec and its pack from the talents. Both are on [Pack talents, specs and selectors](Pack-Talents-Specs-And-Selectors). `RegisterPvpTalents` is inherited; no pack uses it.

`RegisterGear(key, itemID, ...)` names an item or a set by item IDs, and `RegisterSetBonus(key, spellID)` a set bonus by its hidden aura; both are read as `set_bonus.<key>`. From `src/Hekili_Hunter/Hunter.lua`:

```lua
spec:RegisterGear("cryptstalker", unpack(CRYPTSTALKER))
spec:RegisterSetBonus("cryptstalker_2pc", 28755)
```

`RegisterSetBonuses(key, spellID, ...)` registers several pairs at once; no pack uses it.

### Pets and totems

`RegisterPets({ [key] = { id, spell, duration, copy, cap } })` names the class's pets. A `cap` makes a guardian the belief counts per summon, read as `pet.<key>.count`. From `src/Hekili_Hunter/Hunter.lua`:

```lua
spec:RegisterPets({
    hawk = { spell = "summon_hawk", duration = 18, cap = 2 },
})
```

`RegisterTotems({ [key] = { id, copy } })` names the totems; the Shaman's file builds its table from its totem list and passes it. `RegisterPet` and `RegisterTotem` are the single forms; no pack calls them directly.

### Simulation extensions

These add to the simulation only; the belief does not run them.

`RegisterStateExpr(key, fn)` adds a value a priority reads by name. The shared object offers it too. From `src/Hekili_Druid/Druid.lua`:

```lua
spec:RegisterStateExpr("druid_bleed_active", function()
    return debuff.rake.up or debuff.rip.up or debuff.lacerate.up or debuff.pounce_bleed.up
end)
```

`RegisterStateFunction(key, fn)` adds a function that handlers and expressions can call, such as the Druid's `swap_form(form)`. `RegisterStateTable(key, table)` adds a table with its own lookups. From `src/Hekili_Rogue/Rogue.lua`, shortened:

```lua
spec:RegisterStateTable(
    "stealthed",
    setmetatable({}, {
        __index = function(_, k)
            if k == "all" or k == "rogue" then
                return buff.stealth.up or buff.vanish.up
            end
            -- ...
        end,
    })
)
```

`RegisterHook(name, fn, noState)` runs a function at a point of the simulation's cycle, such as `reset_precast` (each reset, before the forecast) or `runHandler` (each cast the simulation runs). With `noState` true the function keeps its own environment. From `src/Hekili_Warrior/Warrior.lua`, shortened:

```lua
spec:RegisterHook("reset_precast", function()
    local hs = knownRank(HEROIC_STRIKE)
    if hs > 0 and IsCurrentSpell(HEROIC_STRIKE[hs]) then
        applyBuff("heroic_strike")
    end
end)
```

`RegisterEvent(event, fn)` runs a function on a game event while the class's spec is active. From `src/Hekili_Warrior/Warrior.lua`:

```lua
spec:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    unblockedAvg = 0
end)
```

`RegisterUnitEvent`, `RegisterCombatLogEvent`, `RegisterCycle`, `RegisterVariable`, `RegisterPhase`, `RegisterPhasedVariable`, `RegisterRecheck`, `RegisterRanges`, `RegisterRangeFilter` and `RegisterOptions` are inherited from the original Hekili; no shipped pack uses them. `RegisterPotion`, `RegisterPotions` and `RegisterPriority` are kept for old class files and do nothing.

### Windows and reactions

`RegisterWindow(name, data)` declares a rotation window, a span the client shows no aura for. `RegisterReaction(name, data)` runs a `now` function at an observed outcome instead of a cast. Both are on [Pack windows and reactions](Pack-Windows-And-Reactions). From `src/Hekili_Rogue/Rogue.lua`:

```lua
spec:RegisterWindow("riposte", {
    evaluator = riposteUsable,
    duration = 5,
    close_on_false = true,
})
```

### Packs and settings

`RegisterSetting(key, default, option, specKey, ...)` adds a class setting ([Pack settings](Pack-Settings)). `RegisterPack(name, version, string)` registers a built-in priority; `make packs` writes these blocks, and they are never edited by hand. `RetirePacks({ name, ... })` names built-in priorities the class no longer ships: when the profile's defaults are restored, a saved copy of one leaves the profile (a player's own priority of the same name stays), and a spec that chose it falls back to its default. From `src/Hekili_Druid/Druid.lua`:

```lua
spec:RetirePacks({ "Feral", "Guardian", "Balance" })
```

## See also

- [Pack abilities reference](Pack-Abilities-Reference)
- [Pack auras reference](Pack-Auras-Reference)
- [Pack settings](Pack-Settings)
- [Pack environment names](Pack-Environment-Names)
