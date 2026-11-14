<!--
Purpose: Disable an ability, move it to a toggle, override its keybind or icon.
Type: How-to
Audience: players
Prerequisites: None.
-->
This page shows how to change how one ability or item is recommended: never recommend it, tie it to a toggle, limit it by the number of enemies or to boss fights, or change the keybind text or icon shown for it. Abilities are under **/hekili > Abilities** and items under **/hekili > Gear and Items**. The settings apply to one specialization.

## Before you start

1. Type `/hekili` and open **Abilities**, or **Gear and Items** for an item.
2. Choose the specialization in **Specialization** at the top. It starts on your current one.
3. Pick the ability or item from the list on the left. Its page opens.

<!-- TODO-SCREENSHOT: an ability's page with its options -->

## Disable an ability

Check **Disable *ability name*** at the top of the ability's page. Hekili Forever then never recommends it, and the priority moves on to its next line.

Some priorities depend on an ability: disabling it can change what the rest of the priority recommends.

## Tie an ability to a toggle

**Require Toggle** ties the ability to one toggle. While that toggle is off, the ability is treated as if it were on cooldown ([Toggles](Toggles)). The choices are:

- None: the ability is never held back by a toggle;
- Default: the toggle the class addon chose, shown in brackets;
- Cooldowns, Minor CDs, Defensives, Interrupts or Potions;
- Custom 1 or Custom 2, the two custom toggles.

For example, to keep a long cooldown for boss fights, tie it to Custom 1 and bind a key to Custom #1 under **/hekili > Toggles**.

## Limit by targets or encounters

- **Boss Encounter Only**: the ability is recommended only during a boss encounter.
- **Minimum Targets** and **Maximum Targets**: the ability is recommended only with at least, or at most, that many enemies counted ([How targets are counted](How-Targets-Are-Counted)). 0 turns the limit off.
- **Maximum Applications**: for an ability that applies a debuff, it is not recommended once the debuff is on this many enemies, unless it can be refreshed on your current target. 0 turns the limit off.
- **Clash**: Hekili Forever treats the ability as ready this many seconds before it really is. Use it to prefer an important ability over one that becomes ready only slightly sooner.

All of these come on top of the priority's own conditions: an ability still needs its line in the priority to pass.

## Override the keybind text or icon

- **Override Keybind Text**: the text shown on the icon in place of the key Hekili Forever finds on your action bars. Use it when the ability is cast from a macro, or sits on several bars and the wrong key shows. The page shows the key it currently finds.
- **Icon Replacement**: a texture ID or a texture path to show in place of the ability's icon. Clear the box and press Enter to go back to the default icon.

## Gear and items

The **Gear and Items** page lists the items that the class addon knows for the specialization, such as potions, healthstones and mana items. Each item has **Boss Encounter Only**, **Require Toggle**, **Minimum Targets**, **Maximum Targets** and **Override Keybind Text**, with the same meaning as for an ability, and its own **Disable *item name*** box.

**Disable Gear and Items**, at the top of the page, stops every equipped item with a "Use:" effect, such as a trinket, from being recommended for that specialization.

## Check that it works

Close the options and fight an enemy. A disabled ability does not appear. An ability tied to a toggle disappears when you turn that toggle off. An overridden keybind shows its new text on the icon.

## See also

- [Specializations reference](Specializations-Reference)
- [Profiles and sharing](Profiles-And-Sharing): these settings are saved in your profile
