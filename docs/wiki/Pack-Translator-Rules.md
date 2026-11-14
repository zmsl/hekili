<!--
Purpose: One line per translator rule.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack wowsims recipes](Pack-wowsims-Recipes).
-->
The **pack translator rules** are the rules by which `tools/wowsims/apl.lua` turns a wowsims.com rotation (an APL, wowsims's action priority list in JSON) into the priority text of a "(wowsims.com)" pack. This page gives each rule in one entry. The numbered header comment of `tools/wowsims/apl.lua` is the authority; where this page and that header differ, the header is right.

The translator runs during `make wowsims-packs` ([Pack wowsims recipes](Pack-wowsims-Recipes)). It reads the recipe, the checked-in request and the exported fight log, and writes one `.simc` file per pack. Why the generated priorities look the way they do is explained for players in [APL wowsims packs explained](APL-wowsims-Packs-Explained).

## Rules

A rule that changes what a wowsims line does, because the Forever client forces it, writes a `# Deviation:` line into the pack header. An entry the translator cannot express is left out and listed under `# Omitted:` (rule 2). A wowsims value it cannot map is "nil" in the wowsims sense: the term drops out of its condition rather than blocking the line (rules 6 and 12).

| Rule | Name | What it does |
|---|---|---|
| 1 | Lines and lists | One priority line per APL entry, in order. Pre-pull actions become `actions.precombat`, sorted by their constant `doAtValue` (earliest first); an entry with no constant time, or one after the pull, is left out. Each action group becomes a list `actions.<snake_name>` called with `call_action_list`. Variables are inlined. Each pre-pull cast gets a guard against recasting, derived from its ability's handler: `!buff.<key>.up` or `!debuff.<key>.up` when it applies its own aura (none when the aura lasts no longer than the cooldown), `!totem.<element>.up` when it summons a totem, else none. In a mutually exclusive group (abilities that remove each other's aura), the first line is guarded by every member's aura. |
| 2 | Omitted entries | Left out, and listed under `# Omitted:`: hidden entries, conditions that fold to false, nodes the addon lacks (`schedule`, `itemSwap`, `wait`, `activeItemSwapSet`, `selectedConjured`), a non-cast action aimed at a second target, a target change rule 20 does not absorb, an entry whose own action maps to nothing, and a call of a group whose entries were all left out. Any node the translator does not handle is unsupported, so a new wowsims node drops its entry rather than being translated wrongly. |
| 3 | ON/OFF groups | An action group with no actions is a wowsims switch. Reading it becomes `settings.wowsims_<snake_name>`, on by default exactly when the APL's own reference to it is not hidden. The class registers the setting, named "&lt;Group&gt; (wowsims.com)". The header lists a setting only when an emitted line reads it. Testing a group that has actions is a constant, as in wowsims. |
| 4 | Known auras | `auraIsKnown` becomes `talent.<key>.enabled` for a talent's aura, `action.<key>.known` for an ability's aura, and `true` for any other aura. An ID nothing resolves, or an aura on another unit, is false; an unresolved ID leaves a header note. A gear, set or consumable aura reads `true` even when the item is not worn, and the branch then rests on the aura's own state. |
| 5 | Keys | A wowsims spell, aura or item ID becomes an addon key from the character's ability set: the class kit, the shared content and every race's racials. The recipe's `map` and `auras` come first, then an ability's `id` and `copy`, then the registered auras. An aura on the player reads as `buff.`, one on the target as `debuff.`, a pet's resource as `pet.<resource>`. `includeReactionTime`, `rank` and tags are ignored. |
| 6 | Leveling guard | In wowsims, a read of an ability the character has not learned is nil, and nil drops out of `and` and `or`; a nil condition is true. The translator writes the same effect: a term that reads ability X is guarded by `action.X.known`, so it drops away while X is unlearned. The line's own action is never guarded, because the engine already skips an unknown action. `min` and `max` skip a dropped term. `tools/check_pack_levels.lua` checks every pack for these guards. |
| 7 | Recipe additions | Applies the recipe's fields: `focus` tiers (none on a pre-pull line), `use_off_gcd=1` on an off-GCD ability, `leveling` lines after the list, `levelingFirst` lines before it, `extra` lines before a named action, `settings`, `prepullSkip`, `requires`, `guard` and `condition`. A term repeated in an `and` or `or` is written once. |
| 8 | Constants | `true` and `false`, numbers, and Go durations (`1.5s`, `300ms`, `1m30s`) in seconds. A percentage is N when compared directly with a percent read such as `mana.pct` or `health.pct` (which run from 0 to 100), and N/100 anywhere else, as wowsims reads it. A percent read inside `math`, `min` or `max` is unsupported. |
| 9 | Internal cooldowns | `auraIcdIsReady` becomes `buff.<key>.icd_ready` for an aura that declares an `icd`. Any other aura is unsupported. |
| 10 | Refresh, swing timers, fight length | `auraShouldRefresh` works only for an aura in the recipe's `exclusive` set, as a remaining-time test (plus a stack test for a stacking aura). `cancelAura` becomes `cancel_buff,buff_name=<key>`. Swing speeds and swing timers become `mainhand_speed`, `offhand_speed`, `ranged_speed`, `mainhand_remains` and `ranged_remains`; a "time since the last swing" comparison is rewritten on the timer, or on a kit window named by the recipe's `windowVars`. `remainingTime` becomes `fight_remains`. `multipleCdUsages` without a base spell becomes wowsims's own test on the fight's remaining time. |
| 11 | Distance | `unitDistance` compared with a whole number N becomes `target.within<N>` or `target.outside<N>`. The client reports only whether each ability is in range, not yards, so the engine brackets the distance between the tracked abilities' ranges. An unknown distance answers both tests and never blocks a line. |
| 12 | Unresolved reads | A spell, aura or item ID nothing maps is nil inside a condition, so rule 6 drops that branch and the entry stays. `spellIsKnown` of such an ID is false. The header lists each ID. Only an entry whose own action is unmapped is left out whole. |
| 13 | Automatic cooldowns | `autocastOtherCooldowns` becomes one line per major cooldown the exported log shows wowsims using, in first-use order, each under its ability's own toggle. It also takes every racial cooldown the class can have (defensive ones only for a tank), so each race's racial has a line that stays inert for the others. An off-GCD cooldown is shown as soon as it is ready, where wowsims waits for the GCD. `castAllStatBuffCooldowns` becomes one line per instant cast in the log that raised a matching stat. |
| 14 | Strict sequences | `strictSequence` becomes one line per member, in order. The first member carries the sequence's condition; each later one requires that the member before it was the last cast (`prev.1.<key>`). |
| 14b | Sequences as windows | `sequence` becomes a stepped window: one line per cast member, `<key>,if=window.<w>.next.<key>`. The header line `# Window:` gives the steps and the evaluator, and the class registers the window with `spec:RegisterWindow`. A sequence whose condition the addon cannot read is left out, with every line that reads its window. |
| 15 | Maintenance debuffs | A debuff named in the recipe's `maintenance` (kept up for a raid) puts its cast lines behind a setting, `settings.<key>&`. Other lines that wait on that debuff read it as "up or disabled". The class registers the setting off in game and on in the test harness. |
| 16 | Option-selected casts | A cast whose spell a class option picks (the recipe's `select`) becomes a choice setting, read as `settings.<setting>='<value>'`, and one line per candidate spell. Its "the selected spell is active" value is the selected candidate's debuff. |
| 17 | DoTs on several targets | `multidot` becomes the DoT's cast line under `debuff.<key>.remains<=<maxOverlap>`. With more than one target allowed it carries `cycle_targets=1,max_cycle_targets=<N>`, so with Recommend Target Swaps on it can be shown on another target. |
| 18 | Movement terms | Run speed, "is moving" and arithmetic on yards are dropped from every condition, and the rest of the condition decides. Each dropped term is listed under `# Dropped (movement):`. |
| 19 | Moves | A `move` entry, or a `waitUntil` that only waits for range, gives no line. A move to D yards reaches the lines whose ability needs that range; each reached line gets a copy at the move's position, gated by `toggle.movement`, so with the Movement toggle on the line shows where wowsims would walk to it. The header lists each move under `# Movement:`. A spec opts into the Movement toggle (`movement = true` in its spec entry) exactly when its pack reads `toggle.movement`. |
| 20 | Target swaps | A target change to the next target, when X is up here but not on every target, after a cast of X in the same list, gives no line of its own. Instead the cast's lines carry `cycle_targets=1` and are listed under `# Cycle:`. Any other target change is left out with its reason. |
| 21 | Casts at a second target | A cast aimed at wowsims's second target carries `other_target=1`: it is shown only on another target, with Recommend Target Swaps on, never on the current one. |
| 22 | Mana under an amount | A test of the player's mana under an absolute amount N becomes a test of both the amount and its share of the mana pool, `mana.lo<N&mana.pct_lo<P`. P comes from the maximum mana in the exported log, rounded up. At the level the log was made for, the share never binds; a smaller pool at a lower level uses the share. |

## Direct values

Some wowsims values map one to one. A resource the game hides reads its low end (`.lo`), so a line that spends it fires only when the cost is certain; see [APL expression reference](APL-Expression-Reference).

| wowsims value | Priority expression |
|---|---|
| `numberTargets` | `active_enemies` |
| `currentRage` | `rage.lo` |
| `currentEnergy` | `energy.lo` |
| `currentMana` | `mana.lo` |
| `currentManaPercent` | `mana.pct_lo` |
| `maxMana` | `mana.max` |
| `currentManaRegen` | `mana.regen` |
| `currentComboPoints` | `combo_points.current` |
| `currentHealthPercent` | `health.pct` |
| `currentHealth` | `health.current` |
| `currentTime` | `time` |
| `remainingTime` | `fight_remains` |
| `gcdTimeToReady` | `gcd.remains` |
| `inputDelay` | `0` |

> [!NOTE]
> **On Forever:** The game hides target health, so `fight_remains` answers 3600 seconds ("unknown") in game. A wowsims line that tests the fight's remaining time reads a long fight.

## One-line reads

Further values have a single translation each. Where one reads another ability, rule 6 guards it and rule 12 drops it when the ID maps to nothing.

| wowsims value | Priority expression |
|---|---|
| `talentIsKnown` | `talent.<key>.enabled`, or `talent.<key>.rank>=<rank>` above rank 1 |
| `talentRank` | `talent.<key>.rank` |
| `spellFullCooldown` | `cooldown.<key>.duration` |
| `spellTravelTime` | `action.<key>.travel_time` |
| `spellGcdHastedDuration` | `action.<key>.gcd` |
| `gcdIsReady` | `gcd.remains<=0` |
| `auraDuration` | `buff.<key>.duration` or `debuff.<key>.duration` |
| `dotBaseDuration` | `debuff.<key>.duration` |
| `spellIsCasting` | `action.<key>.executing` for an ability with a cast time, else false |
| `spellIsChanneling` | `action.<key>.channeling` for an ability declared `channeled`, else false |
| `spellInRange` | `action.<key>.in_range` |
| `auraIsActiveOnAnyTarget` | `active_dot.<key>>0` |

`frontOfTarget` and `targetIsMobType` read the request's constants, since the client reports no facing and the creature type is not read; each writes a `# Deviation:` line. `spellExpectedDpet`, `numActiveAdds` and `remainingCastTime` are unsupported. Expected damage per cast would need a damage model, which the addon does not have.

## Header lines

The translator writes comment lines at the top of each generated `.simc` file. They are the first place to look when a pack does not match wowsims.

| Line | Meaning |
|---|---|
| `# Setting <key> (...), default <value>.` | A pack setting an emitted line reads: an ON/OFF group (rule 3), a recipe setting, a maintenance debuff (rule 15) or a choice (rule 16). |
| `# Omitted: <list> #<n>: <reason>` | An entry left out (rule 2), with the reason. |
| `# Deviation: <list> #<n>: ...` | A difference from wowsims that the Forever client forces. |
| `# Dropped (movement): <list> #<n>: <node>` | A movement term removed from a condition (rule 18). |
| `# Movement: <list> #<n> reaches <list>: <actions>` | A move and the lines it reaches (rule 19). |
| `# Cycle: <list> #<n> changeTarget -> ...` | A target change turned into `cycle_targets=1` (rule 20). |
| `# Window: <w>: steps ...` | A sequence turned into a stepped window (rule 14b). |

`<list> #<n>` is the APL's own list name and entry number, so a line can be traced back to the wowsims rotation. From `src/Hekili_Warrior/APLs/Arms (wowsims.com).simc`:

```text
# Setting wowsims_stance_dance (wowsims ON/OFF group), default false.
# Omitted: default #1: hidden
# Omitted: engineering #1: item 10646
```

## See also

- [Pack wowsims recipes](Pack-wowsims-Recipes)
- [APL wowsims packs explained](APL-wowsims-Packs-Explained)
- [APL expression reference](APL-Expression-Reference)
- [Pack testing and gates](Pack-Testing-And-Gates)
