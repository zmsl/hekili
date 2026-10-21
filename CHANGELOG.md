# Hekili Forever changelog

## Unreleased

### New
- Warrior: Arms, Fury and Protection suggest Victory Rush after a kill, just above Bloodthirst (Mortal Strike for Arms).
- Mage: "Frostfire (wowsims.com)", wowsims/forever's Frostfire priority (Frostfire Bolt, Fire Blast unless two Fingers
  of Frost charges are up, Pyroblast on three Heating Up, Scorch for Fire Vulnerability), a second Fire priority for the
  FFB talents (more Fire points than Frost); Fire's default stays "Fire (wowsims.com)".
- Experimental, off by default: "steady icons" on each specialization's Performance tab keeps a countdown icon for one
  more update instead of swapping it for another countdown icon, so the icons flicker less; ready icons still show at once.
- Shaman: Enhancement suggests Rage of the Farseer when it is ready, right after Blood Fury, if you have the talent. It is under the Cooldowns toggle.
- Priest (new addon folder Hekili_Priest): the Priest's abilities and talents, with no default priority yet (Shadow and
  Discipline's Smite come next); Holy shows the "no priorities on Forever" notice.
- Priest (new addon folder Hekili_Priest): the Priest's abilities and talents; Holy shows the "no priorities on Forever"
  notice.
- Priest: "Shadow (wowsims.com)" is Shadow's default priority, wowsims/forever's Shadow list (Shadowform, Shadow Word:
  Pain and Devouring Plague kept up, Mind Blast, Shadow Word: Death, Inner Focus into Mind Flay); Smite fills while
  leveling until Mind Flay.
- Priest: "Smite (wowsims.com)" is Discipline's default priority, wowsims/forever's Smite list (Holy Fire and Shadow
  Word: Pain kept up, Penance, Smite; the wand at 10% mana).
- Shaman: Elemental has a priority, "Elemental (wowsims.com)", wowsims/forever's Elemental list (Flame Shock, Lava Burst
  while it is up, Earth Shock on Revelation, Elemental Mastery, Lightning Bolt, the fire totem). It is Elemental's default.

### Changed
- Mana and energy consumables (Major Mana Potion, Demonic Rune, Thistle Tea, Mana Gem) and the Rogue's poison reminders (Instant and Deadly Poison) are now under the Potions toggle, which is off by default: turn Potions on to see them. The Healthstone stays under Defensives.
- Warrior Protection's Demoralizing Shout, Arms's leveling Thunder Clap (before Mortal Strike) and Druid Guardian's Demoralizing Roar are off by default (open-world mobs die before they pay off). Turn them on in the specialization's settings for raids ("Maintain Demoralizing Shout", "Maintain Thunder Clap", "Maintain Demoralizing Roar"). Protection's Thunder Clap is unchanged.
- Guardian: with Demoralizing Roar off, Berserk no longer waits for it, and the leveling Roar filler is off too.
- The now circle's highlights follow a line's role: procs and windows the player must catch, then upkeep; core strikes, cooldowns and pre-pull steps are no longer highlighted.
- Druid: Rip is highlighted as upkeep like Rake; Shred and Claw only on Clearcasting; Innervate no longer. Guardian highlights Maul and Demoralizing Roar.
- Hunter: Raptor Strike and Serpent Sting are highlighted first in every specialization; the melee-weave strikes (Mongoose Bite, Strider Kick, Immolation Trap, Wing Clip) are not highlighted. Hunter's Mark is no longer highlighted before the pull.
- Mage: Evocation is no longer highlighted.
- Paladin: Retribution no longer highlights Exorcism or the seal before the pull; the seal you keep up while leveling is highlighted as upkeep.
- Rogue: Garrote, Slice and Dice and Rupture share the first highlight (whichever is due first) in every specialization; Ambush is no longer highlighted.
- Shaman: Fire Nova is highlighted only on Clearcasting, and the totems are no longer highlighted.
- Pre-pull suggestions now guard against recasting: each shows whenever its purpose is unmet (its buff or debuff down, its totem down, its cooldown ready) and hides while it is met. The once-per-episode schedule and `prepull_at` are gone. Arms's Pre-pull: Stance and both Arms's and Fury's Pre-pull: Move no longer repeat between pulls; Charge still shows whenever it is usable, by design.
- Paladin: Retribution's pre-pull suggests one starter seal, Seal of the Crusader, and no longer Seal of Command before it.
- Warrior: Arms and Fury fill the rotation with Hamstring while leveling (at level 40, before Mortal Strike or Bloodthirst) instead of standing idle for up to 11 seconds.
- Warrior: Bloodrage, Intimidating Shout and Mocking Blow are no longer under the Cooldowns toggle; Disarm is under Defensives.
- Warrior: Arms and Fury suggest Berserker Rage only once you have Improved Berserker Rage (for its rage), before the pull and in combat.
- Warrior focus tiers: Arms's Slam is no longer a focus line (Mortal Strike, Slam and Execute are rotational); Fury marks Rend (2) and the Battle Stance swap for Overpower (1) as focus, and Cleave takes Heroic Strike's tiers.
- Warrior Fury: the Battle Stance swap for Overpower waits until the swap keeps enough rage for Overpower (Tactical Mastery) and Overpower is off cooldown before its window closes.
- Warrior: each priority's description lists the lines the Cooldowns and Defensives toggles hide.

### Fixed
- A priority regenerated on the same day no longer shows as reverted on login.
- Built-in priorities no longer show a Delete button.
- A spell you cannot afford no longer flashes ready for a moment while you are low on mana (a Fire mage's Pyroblast, an Arcane mage's Arcane Blast).
- A pooled ability no longer blinks in and out of the queue at the moment the pool reaches its threshold (a Rogue's
  Sinister Strike waiting for 75 energy).

### Known issues

### Upgrade notes
- `prepull_at` in an imported or saved priority is now ignored, without a warning.

## v0.2.0

_Released 2026-10-21_

Hekili Forever v0.2.0 makes priorities translated from wowsims.com the default for every supported specialization, adds the Hunter and the Mage, and gives each talent tree its own specialization page and settings.

### Druid
- "Feral (wowsims.com)", "Guardian (wowsims.com)" and "Balance (wowsims.com)" are the new defaults. The old Feral, Guardian and Balance priorities are gone, along with the settings only they used.
- Guardian rotation: Berserk once Demoralizing Roar is up and Primal Bite is on cooldown, Lacerate kept at five stacks, Primal Bite, Lacerate, then Maul at 20 rage. It suggests Bear Form first when you are out of form.
- Guardian has no Swipe or multi-target branch, no Enrage and no trinket use. While leveling, it fills with Maul until you learn Primal Bite and uses Demoralizing Roar and Faerie Fire until you learn Lacerate.
- Balance shows Moonkin Form first whenever you are out of it. Feral now pairs Berserk with the Rake or Shred that follows it.
- Primal Bite is ready again during Berserk. In Bear Form, the rage estimate counts 11.25 rage per white swing (was 8.65) plus Primal Fury's rage on your critical hits.
- Costs now match the game: Lacerate and Shred with Shredding Attacks (all three points), Balance spells with Moonglow and Improved Wrath, and the forms, Shifting Power and Innervate at level 60.
- Howling Idol takes 1 s off Shifting Power's cooldown. With Wolfshead Helm, Shifting Power gives 45 energy and Enrage gives 15 instant rage. Mana now regenerates in combat outside the five-second rule.

### Hunter
- New class addon (folder Hekili_Hunter). "Beast Mastery (wowsims.com)", "Marksmanship (wowsims.com)" and "Survival (wowsims.com)" are the defaults, replacing the old priorities and their Arcane Shot and Wing Clip mana floor settings.
- Melee weave: Wing Clip, Mongoose Bite, Strider Kick and Immolation Trap while you are in melee range, shots between swings, and Rapid Fire and Blood Fury from 5 seconds into a fight.
- Multi-Shot lines now fire (before, they never recommended it). At range, Multi-Shot is no longer timed around a melee swing that never comes.
- Resourcefulness and Efficiency now lower the mana costs the addon expects, Raptor Strike included. Each rank of Improved Arcane Shot takes 0.3 s off Arcane Shot's cooldown.

### Mage
- New class addon (folder Hekili_Mage). "Arcane (wowsims.com)" and "Fire (wowsims.com)" are the defaults. Frost shows a "no priorities on Forever" notice.
- Arcane: Arcane Missiles on Missile Barrage, Arcane Wrath, Arcane Blast up to its charges while mana allows, Frostbolt in between, Evocation at 10% mana.
- Fire: Scorch to five Fire Vulnerability stacks, Pyroblast on three Heating Up stacks, Fire Blast, Arcane Missiles on Missile Barrage, Fireball, Evocation at 10% mana.

### Paladin
- Paladin priorities now load; in v0.1.0 the addon showed nothing. "Protection (wowsims.com)" and "Retribution (wowsims.com)" are the defaults, and Retribution uses your on-use trinkets.
- The old priorities are gone, along with Retribution's Holy Shock list and the Consecration and Exorcism Mana Floor settings. Righteous Fury is no longer suggested before combat.
- Retribution's Twist of Light lines now require the talent. Below it, Seal of Command is kept up.
- Each rank of Improved Judgement takes 1 s off Judgement's cooldown, Holy Conduit and Benediction lower costs, and Sanctified Judgement's mana refund is counted. Undead/Demon Exorcism ranks are suggested only against those targets.

### Rogue
- Rogue priorities now load; in v0.1.0 the addon showed nothing. "Assassination (wowsims.com)", "Combat (wowsims.com)" and "Subtlety (wowsims.com)" are the defaults, and they open with Blood Fury then Adrenaline Rush.
- The old priorities are gone, with Bleeds on Trash, Maintain Expose Armor, Vanish to Re-open, Ambush Opener, Backstab Builder and Poison Reminders. Vanish now follows the Cooldowns toggle.
- Costs now match the game: Garrote costs 10 less per Dirty Deeds rank, Backstab and Hemorrhage 3 less per Thousand Cuts stack, and Improved Sinister Strike takes 5 off at 2/2 (it took 10).

### Shaman
- Shaman priorities now load; in v0.1.0 the addon showed nothing. "Enhancement (wowsims.com)" is the default, replacing the old priority and its imbue reminder and mana settings.
- Reverberation and Improved Fire Nova shorten the shock and Fire Nova cooldowns, Shamanistic Focus lowers the cost of shocks and Lightning Shield, Call of Flame lengthens Flame Shock, and Stormstrike's cost matches the game.

### Warrior
- "Arms (wowsims.com)", "Fury (wowsims.com)" and "Protection (wowsims.com)" are the defaults. Arms keeps Stance Dance and Recklessness off, Fury keeps Rend Weave on, and Fury fills with Sunder Armor before you learn Bloodthirst.
- The old priorities are gone with their settings (queue prediction, Whirlwind, Hamstring, Sunder, Demoralizing Shout, Thunder Clap, rage and Challenging Shout options). Limit those abilities with their own options: Disable, Boss Encounter Only, or a custom toggle.
- Sweeping Strikes now follows the Cooldowns toggle. Fury no longer recommends Intercept all fight, and Arms no longer recommends its stance dance all fight.
- Thunder Clap's slow on your target is now seen from any warrior's Thunder Clap, so Thunder Clap is no longer suggested over and over.
- Below level 40, Arms and Fury no longer suggest Sunder Armor at five stacks.
- Improved Slam makes Slam a 1.0 s cast on a 1.0 s global cooldown and a 15 s cooldown (1.5 s and 18 s without the talent). Anger Management gives 1.5 rage every 5 seconds.
- Focused Rage, Improved Thunder Clap, Improved Sunder Armor, Improved Execute and Booming Voice reduce costs per rank as in the game. Focused Rage now also covers the shouts and Death Wish.

### Core and display
- Each talent tree is its own specialization with its own priorities and settings (Feral Combat has Feral and Guardian). The active one follows your most-spent tree and switches when you respec or swap specs. Change it with "Activate <Spec>" or `/hekili spec <name>`, and type `/hekili spec` to list them.
- Holy, Restoration and Elemental show a "no priorities on Forever" notice and recommend nothing.
- Options: each specialization page starts with its Priority and an "Activate" button (a gold "Active" marker on the active one) and ends with "Disable <Spec>". Priorities are listed under their specialization, and the active specialization appears first.
- The Active Specialization dropdown and the "your talents favor" hint are gone. Deleting or unchecking a custom priority returns to the default. Hekili Forever is listed under Combat in the AddOns list.
- Pre-pull actions are recommended once between fights, in order, so two seals no longer alternate before a pull.
- Raptor Strike, Heroic Strike and Maul are no longer recommended while your target is beyond melee range. Priority conditions on target distance now work on Forever.
- Rage is counted from the white swing itself. Heroic Strike no longer jumps to the next swing and back, and an ability used on a swing no longer leaves the rage estimate too high.
- A dodged, parried or missed ability no longer counts its debuff as applied. Warrior, Rogue and Feral strikes get back the 80% of their cost that the game refunds (not Whirlwind, Cleave or Thunder Clap).
- Mana regenerates at the full rate 5 seconds after your last spend, so low-mana casters no longer show a blank icon while waiting.
- Free casts (Clearcasting, five Maelstrom Weapon stacks) no longer count as spending mana, and the addon assumes full mana and energy after a reload.
- Spells that cost a percent of base mana are no longer priced from your maximum mana.
- Healthstone follows the Defensives toggle. Priorities that check your health no longer raise an error on load and treat your health as full while the game hides it.

### Known issues
- Hunter, Rogue, Paladin and Shaman priorities are not yet checked in game; Auto Shot timing and mana costs may be off. The rune versions of Raptor Strike are not recognized.
- Hunter: Multi-Shot rarely appears if you never walk into melee, and Beast Mastery and Marksmanship use the same list. The defaults never suggest Aimed Shot, Sniper Shot or Summon Hawk.
- Shaman: there is no weapon-imbue reminder. The mana potion, Demonic Rune and Fire Nova lines are always on and use estimated mana, and Fire Nova is expected to cost 520 mana where wowsims.com uses 375.
- Every fight is treated as a long one: Feral's end-of-fight Ferocious Bite and the Rogue end-of-fight lines never show, and Rip can be suggested on a mob that dies first.

### Upgrade notes
- Update the core addon (Hekili) together with its class addons. A mismatched pair loads no priorities and says "update the older one".
- A saved choice of an old Druid, Hunter, Paladin, Rogue, Shaman or Warrior priority falls back to that specialization's "(wowsims.com)" default, and the login message calls the old priority retired.
- Your class settings are copied once into each specialization, and a custom priority you had chosen stays selected for your active specialization. Old priority exports still import.

## v0.1.0

First release of Hekili Forever, based on the original work by Hekili, for the WoW Forever client.
- Druid (Feral, Balance, Guardian) and Warrior (Arms, Fury, Protection) default priorities.
- Classic and Timeline display styles.
- Fork notice and fork links (github.com/zmsl/hekili); licence GPLv3 or later.
