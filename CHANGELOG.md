# Hekili Forever changelog

## Unreleased

### New
- Rogue: "Assassination (wowsims.com)", "Combat (wowsims.com)" and "Subtlety (wowsims.com)", translated from
  wowsims.com's Rogue priority, are each specialization's default.
- Hunter: Beast Mastery, Marksmanship and Survival (new addon folder Hekili_Hunter).
- Hunter: "Beast Mastery (wowsims.com)", "Marksmanship (wowsims.com)" and "Survival (wowsims.com)" are each
  specialization's default priority, translated from wowsims/forever's Melee Weave: Wing Clip, Mongoose Bite, Strider
  Kick and Immolation Trap while you are in melee range, the shots between swings. Resourcefulness and Efficiency
  lower the mana costs the addon expects.
- Pets and guardians: the addon tracks your pet and your summoned guardians (Summon Hawk, up to two), so priorities can
  ask whether a pet is out and how many guardians are up.
- Specializations: each supported class has one specialization page per talent tree, each with its own priorities
  and settings (the Druid's Feral Combat tree has two: Feral and Guardian). The active specialization follows the
  talent tree with the most points; change it with the "Activate <Spec>" button on a specialization page or with
  `/hekili spec <name>` (`/hekili spec` lists them). Healing trees (Holy, Restoration) and Elemental show a "no
  priorities on Forever" notice and the addon recommends nothing while one is active.
- Paladin: a "Protection (wowsims.com)" priority, translated from wowsims/forever's Protection APL (selectable; not
  yet the default).

### Changed
- Rogue: the hand-built Assassination, Combat and Subtlety priorities are gone, with their settings (Bleeds on
  Trash, Maintain Expose Armor, Vanish to Re-open, Ambush Opener, Backstab Builder, Poison Reminders).
- Hunter: the hand-built BeastMastery, Marksmanship and Survival priorities are gone, with their Arcane Shot and Wing
  Clip mana floor settings.
- Specializations follow your talents: a respec or dual-spec swap that moves your most-spent talent tree activates
  that tree's specialization, the one you last activated for it (for example Guardian on the Feral Combat tree) or
  else its first. Swapping between two builds of the same tree keeps your choice. The "your talents favor" hint is gone.
- Options: each specialization page starts with its Priority and an "Activate <Spec>" button (a gold "Active" marker
  on the active one; the Active Specialization dropdown is gone) and ends with a "Disable <Spec>" checkbox in place of
  "<Spec> Enabled". Each priority now sits under its specialization in the options tree (Priorities keeps Import /
  Export and Create a New Priority), and the active specialization is listed first with a gold highlight.
- The AddOns list shows Hekili Forever under the Combat category.
- The addon keeps a ranged Auto Shot timer next to the melee swing timers.
- Developer: the mana estimate's at-rest lower bound is pinned by tests (no behaviour change).
- Developer: the test harness answers the mana regen pair (`GetManaRegen`) as the client does, plain out of combat
  and secret in combat, and its wowsims replays read the mana regen rates from the log.
- Priorities: a precombat line may carry `prepull_at=<seconds before the pull>`; such a line is recommended once
  between fights (after its spell is cast or its buff is seen up, and again once that buff runs out), in the list's
  order, so two seals no longer alternate before a pull.
- Abilities can be limited to target creature types (for example undead and demons); the addon reads the target's
  type in any client language, and a type it cannot read never hides an ability.
- Priorities can read the distance to your target (`target.distance`, `target.within5`, `target.outside8`): the addon
  brackets it from your abilities' range checks (for example "past Wing Clip, inside Arcane Shot"), keeps the last
  reading if the game hides it, and treats an unknown distance as in range. Before, these conditions never worked on
  WoW Forever.
- Strikes on your next swing (Raptor Strike, Heroic Strike, Maul) are no longer recommended while the addon knows your
  target is beyond melee range (the game's own range check says "in range" for them at any distance).

### Fixed
- Hunter: priority lines that divide (Multi-Shot's) now fire. Divisions in the priorities translated from
  wowsims ran as a remainder, so those lines never recommended their ability.
- Rogue: Garrote costs 10 less a Dirty Deeds rank, Backstab and Hemorrhage 3 less a Thousand Cuts stack, and
  Improved Sinister Strike takes 5 off at 2/2 (it took 10), as in wowsims.com.
- Hunter: Arcane Shot's cooldown is 0.3 s shorter per rank of Improved Arcane Shot, so it comes back when the game
  says it does.
- Hunter: at range, Multi-Shot is no longer expected to fit before a melee swing that never comes; the weave line
  waits for the walk in, as wowsims's does.
- Rogue, Paladin and Shaman: the default priorities now load. They were registered under the wrong specialization ids
  for the WoW Forever client, so the addon showed nothing for these classes.
- Developer: unreadable (secret) answers to "does this unit exist / is it dead" for target, party, boss and focus units
  are counted by the addon's diagnostics again; an unreadable "is my pet dead" falls back to the addon's own estimate.
- Mana and energy: the addon no longer believes you nearly out of mana (or energy) after a reload. It assumes the
  bar full until the game says otherwise, so a mana-rich fight no longer waits on spells it can afford.
- Free casts: a spell made free by a buff it uses up (Clearcasting, five Maelstrom Weapon stacks) no longer counts as
  spending mana or opening the five-second rule.
- Rage: an ability used at the moment of a white swing no longer leaves the rage estimate too high once that swing's
  hit shows up (the swing's rage had already paid for the ability).
- Paladin: Judgement's cooldown is 1 s shorter a rank of Improved Judgement; Holy Conduit lowers the mana cost of
  Consecration, Hammer of Wrath and Exorcism.

### Known issues
- Hunter priorities are unchecked in game: Auto Shot timing, the percent-of-base mana costs and the rune Raptor
  Strike variants.
- Hunter: Multi-Shot is recommended only when it ends before your next melee swing (wowsims's melee weave), so a
  Hunter who never walks into melee rarely sees it; Beast Mastery and Marksmanship run the same list; the defaults
  never recommend Aimed Shot, Sniper Shot or Summon Hawk (wowsims's switches for them are off).
- Rogue, Paladin and Shaman priorities are not yet checked in game.

### Upgrade notes
- Rogue: a saved choice of the Assassination, Combat or Subtlety priority falls back to that specialization's
  wowsims.com default.
- Hunter: a saved choice of BeastMastery, Marksmanship or Survival falls back to that specialization's wowsims.com
  priority.
- Your class's existing settings (thresholds, toggles, ability and item options) are copied once into each of its
  specializations, and a custom priority you had chosen stays selected for your active specialization. Change them per
  specialization afterwards; old priority exports still import.

## v0.1.0

First release of Hekili Forever, based on the original work by Hekili, for the WoW Forever client.
- Druid (Feral, Balance, Guardian) and Warrior (Arms, Fury, Protection) default priorities.
- Classic and Timeline display styles.
- Fork notice and fork links (github.com/zmsl/hekili); licence GPLv3 or later.
