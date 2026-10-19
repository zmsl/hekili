# Hekili Forever changelog

## Unreleased

### New
- Hunter: Beast Mastery, Marksmanship and Survival default priorities (new addon folder Hekili_Hunter). Sniper Shot
  under Rapid Fire or Quick Shots, Mongoose Bite and Raptor Strike first; Serpent Sting and Hunter's Mark as focus
  abilities; shots only while in Auto Shot range and the melee list only in melee range; Arcane Shot and Wing Clip mana
  floors off by default.
- Pets and guardians: the addon tracks your pet and your summoned guardians (Summon Hawk, up to two), so priorities can
  ask whether a pet is out and how many guardians are up.
- Specializations: each supported class has one specialization page per talent tree, each with its own priorities
  and settings (the Druid's Feral Combat tree has two: Feral and Guardian). The active specialization is the talent
  tree with the most points; change it with the dropdown on any specialization page or with `/hekili spec <name>`
  (`/hekili spec` lists them). Healing trees (Holy, Restoration) and Elemental show a "no priorities on Forever"
  notice and the addon recommends nothing while one is active.

### Changed
- The AddOns list shows Hekili Forever under the Combat category.
- The addon keeps a ranged Auto Shot timer next to the melee swing timers (used by the Hunter priorities' range and
  swing checks; no other class reads it).
- Developer: the mana estimate's at-rest lower bound is pinned by tests (no behaviour change).

### Fixed
- Rogue, Paladin and Shaman: the default priorities now load. They were registered under the wrong specialization ids
  for the WoW Forever client, so the addon showed nothing for these classes.
- Developer: unreadable (secret) answers to "does this unit exist / is it dead" for target, party, boss and focus units
  are counted by the addon's diagnostics again; an unreadable "is my pet dead" falls back to the addon's own estimate.

### Known issues
- Hunter priorities are provisional and unchecked in game: Auto Shot timing, the melee/ranged deadzone, the
  percent-of-base mana costs and the rune Raptor Strike variants. Survival's Mongoose Bite window is untested.
- Rogue, Paladin and Shaman priorities are not yet checked in game.

### Upgrade notes
- Your class's existing settings (thresholds, toggles, ability and item options) are copied once into each of its
  specializations, and a custom priority you had chosen stays selected for your active specialization. Change them per
  specialization afterwards; old priority exports still import.

## v0.1.0

First release of Hekili Forever, based on the original work by Hekili, for the WoW Forever client.
- Druid (Feral, Balance, Guardian) and Warrior (Arms, Fury, Protection) default priorities.
- Classic and Timeline display styles.
- Fork notice and fork links (github.com/zmsl/hekili); licence GPLv3 or later.
