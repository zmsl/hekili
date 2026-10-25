# Hekili Forever changelog

## Unreleased

### New

- Your own hits, misses and DoT ticks are now matched to the cast that made them, even when they come late: a projectile's landing (Wrath, Shadow Bolt, Frostbolt), the killing blow that arrives after your target clears, a cast you switched targets during, and a crowded pull with other players hitting the same mob. A projectile's crit and miss now count when the bolt lands, so crit-triggered effects and miss refunds follow. The class priorities now declare each projectile's travel speed and each spell's school for this.
- Late or out-of-order hits now still count: a result that arrives after its expected time is matched to its cast instead of being dropped, and a swing whose result never shows is counted at its expected rage.
- Snapshots gain two lines, `units` and `tickets`, that show how many of your outcomes were matched, lost or ambiguous. Please include them when you report a wrong recommendation.
- Experimental option, off by default (Options > Performance > Experimental): use the game's damage meter events (read even with the Damage Meter window hidden or disabled) to know at once whether your white swing hit, and that another player's hit was not yours. In our simulated fights the rage estimate is closer in crowds and other players' hits are credited to you less often, while Fury's suggestions changed slightly more often than without it (flicker 1.84 against 1.74 per minute at level 60) and agreement with the true best choice was the same within noise; it has not been measured in game yet and will be play-tested after launch.
- Experimental option, off by default (Options > Performance > Experimental): read aura presence from the game's Cooldown Manager for the auras it tracks. It reads the Cooldown Manager's buff icon and buff bar items, and only auras you applied (presence only, no durations or stacks); the others keep their timers. For Warriors it covers 4 of 42 auras so far (a lower bound until the auras are re-captured on launch day). The Cooldown Manager must be enabled in the game options. A change made in combat waits until the fight ends. It is not yet measured in our simulated fights, which build no Cooldown Manager items; it will be play-tested after launch.
- Parry haste, both ways: when you parry, your next main-hand swing comes sooner, and the addon now expects it then (the swing timer, the rage that swing brings and anything timed to it, such as a Slam between swings or a queued strike, follow). A mob that parries you swings at you sooner too, and its hit on you is still matched to it when several mobs are on you.

### Changed

### Fixed

- A Maul that lands just after Demoralizing Roar is no longer credited to the Roar.
- Rage no longer drifts when a fight ends: a white swing just before combat ends still counts its rage.
- A DoT whose application missed (Insect Swarm, for example) is no longer believed to be ticking on the target.
- A mob running at you while you cast no longer makes the addon lose your spell's landing.

- No more "attempt to index field 'leftText' (a secret string value)" errors in combat: spell tooltips are secret in combat on Forever, and the check for spells disabled in this area now skips them until you leave combat.
- The next on-GCD ability no longer disappears behind off-GCD suggestions (Bloodrage, Heroic Strike and the like). When those fill every icon, the queue now looks up to two steps further so the Timeline still shows your next GCD; the classic icon row still shows your set number of icons.
- WeakAuras: the Hekili recommendation payload can now carry up to two records beyond your icon count (the off-GCD look-ahead above).

### Known issues

- In a crowded pull with a laggy connection, white swings are still credited less often (the harness measures about a third of them in a five-man). Swings whose result never shows now count at their expected rage, so rage reads closer (the harness's mean error there fell from 32 to under 25 rage) but can still be off until a known cost pins it.
- In a raid-sized crowd on one target, projectile landings are not credited at all yet: other casters' hits of the same school take the ticket first, so the amount band never learns (measured, not yet addressed).
- Fast dual-wield rage can still read off: in a five-man the harness credits about 4 in 10 main-hand and 7 in 10 off-hand swings to the right hand, and swings swapped between the hands only partly cancel out.
- Solo, the expected rage of a swing whose result never shows makes rage read one swing high in about 1 of 2400 ten-second windows.

### Upgrade notes

## v0.3.0

_Released 2026-10-22_

v0.3.0 adds the Warlock and Priest with default priorities, an Elemental Shaman priority and a Frostfire option for Fire Mages, and makes the highlighted icon and the pre-pull suggestions more reliable.

### Druid
- Guardian: Demoralizing Roar is off by default because open-world mobs die before it pays off. Turn on "Maintain Demoralizing Roar" for raids. While it is off, Berserk no longer waits for it and the leveling Roar filler is off too.
- Rip is now highlighted as upkeep, like Rake. Shred and Claw are highlighted only on Clearcasting, and Innervate is no longer highlighted. Guardian highlights Maul and Demoralizing Roar.

### Hunter
- All specializations: Raptor Strike and Serpent Sting get the highlight first. The melee-weave strikes (Mongoose Bite, Strider Kick, Immolation Trap, Wing Clip) and the pre-pull Hunter's Mark are no longer highlighted.

### Mage
- Fire: new optional priority "Frostfire (wowsims.com)" for Frostfire Bolt talents (more Fire points than Frost). It uses Frostfire Bolt, Fire Blast unless two Fingers of Frost charges are up, Pyroblast on three Heating Up, and Scorch for Fire Vulnerability. Fire's default stays "Fire (wowsims.com)".
- Evocation is no longer highlighted.

### Paladin
- Retribution: the pre-pull suggests one starter seal, Seal of the Crusader, and no longer Seal of Command before it. Exorcism and the pre-pull seal are no longer highlighted, and the seal you keep up while leveling is highlighted as upkeep.

### Priest
- New: Priest support in a new addon folder, Hekili_Priest. Holy has no priority and shows the "no priorities on Forever" notice.
- Shadow: the default priority is "Shadow (wowsims.com)". It keeps Shadowform, Shadow Word: Pain and Devouring Plague up and uses Mind Blast, Shadow Word: Death, then Inner Focus into Mind Flay. Smite fills while leveling until you learn Mind Flay.
- Discipline: the default priority is "Smite (wowsims.com)". It keeps Holy Fire and Shadow Word: Pain up, then uses Penance and Smite, and your wand at 10% mana.

### Rogue
- The Instant and Deadly Poison reminders are now under the Potions toggle, which is off by default.
- Garrote, Slice and Dice and Rupture share the top highlight in every specialization, whichever is due first. Ambush is no longer highlighted.

### Shaman
- Elemental: new default priority "Elemental (wowsims.com)". It uses Flame Shock, Lava Burst while Flame Shock is up, Earth Shock on Revelation, Elemental Mastery, Lightning Bolt and your fire totem.
- Enhancement: Rage of the Farseer is suggested when ready, right after Blood Fury, if you have the talent. It is under the Cooldowns toggle.
- Fire Nova is highlighted only on Clearcasting, and totems are no longer highlighted.

### Warlock
- New: Warlock support in a new addon folder, Hekili_Warlock, with default priorities for Affliction, Demonology and Destruction.
- Affliction: the default "Affliction (wowsims.com)" keeps Bane of Agony, Corruption, Siphon Life, your curse and Immolate up. It uses Shadow Bolt on Shadow Trance, Wrack while the DoTs last, then Shadow Bolt and Life Tap. "SM Ruin (wowsims.com)" is an alternative built on Bane of Doom with a Shadow Bolt filler.
- Demonology: the default "Demonology (wowsims.com)" (Fire Brand) keeps Bane of Doom, Immolate, your curse and Corruption up and uses Searing Pain for Demonic Brand. It also uses Life Tap when the Imp runs low on mana and Soul Fire on Decimation, with a Searing Pain filler. "Shadow Brand (wowsims.com)" is an alternative with a Shadow Bolt filler and the Succubus.
- Destruction: the default "Destruction (wowsims.com)" keeps Bane of Doom, your curse, Immolate and Corruption up, then uses Conflagrate, Shadowburn, Incinerate and Life Tap.
- New "Assigned Curse" setting: choose the curse every Warlock priority keeps on the target. The options are Curse of the Elements (default), Recklessness, Weakness or none.

### Warrior
- Arms, Fury and Protection suggest Victory Rush after a kill, just above Bloodthirst (Mortal Strike for Arms).
- Protection's Demoralizing Shout and Arms's leveling Thunder Clap are off by default. Turn on "Maintain Demoralizing Shout" or "Maintain Thunder Clap" in the specialization's settings for raids. Protection's Thunder Clap is unchanged.
- Arms and Fury: while leveling (around level 40, before Mortal Strike or Bloodthirst), Hamstring now fills the rotation. Previously you could stand idle for up to 11 seconds.
- Arms and Fury: Berserker Rage is suggested, before the pull and in combat, only once you have Improved Berserker Rage.
- Fury: the Battle Stance swap for Overpower now waits until the swap keeps enough rage for Overpower (Tactical Mastery) and Overpower will be off cooldown before its window closes.
- Bloodrage, Intimidating Shout and Mocking Blow are no longer under the Cooldowns toggle, and Disarm is now under Defensives. Each priority's description lists what the Cooldowns and Defensives toggles hide.
- Highlights: Arms no longer highlights Slam. Fury highlights Rend, the Battle Stance swap for Overpower, and Cleave the same way as Heroic Strike. Protection highlights Revenge, Heroic Strike and Cleave, but not Shield Slam or other strikes.
- Protection's description explains that its defensive suggestions never show in combat, because the game hides your health from addons, so press them yourself. It also explains how to keep Demoralizing Shout and Thunder Clap for bosses.

### Core and display
- Mana and energy consumables (Major Mana Potion, Demonic Rune, Thistle Tea, Mana Gem) are now under the Potions toggle, which is off by default. Turn Potions on to see them. Healthstone stays under Defensives.
- The highlighted icon follows each line's role: first procs and windows you must catch, then upkeep. Core strikes, cooldowns and pre-pull steps are no longer highlighted.
- Pre-pull suggestions now show whenever they are needed (buff or debuff down, totem down, cooldown ready) and hide once they are not. For example, Arms's stance and Arms's and Fury's move suggestions no longer repeat between pulls; Charge still shows whenever it is usable.
- Experimental, off by default: the "steady icons" option on each specialization's Performance tab reduces flicker. It keeps a countdown icon for one more update instead of swapping it for another countdown; ready icons still show at once.
- A spell you cannot afford no longer flashes ready for a moment when you are low on mana, such as a Fire Mage's Pyroblast or an Arcane Mage's Arcane Blast.
- A pooled ability no longer blinks in and out of the queue just as the resource reaches its threshold, such as a Rogue's Sinister Strike waiting for 75 energy.
- A priority updated on the same day no longer shows as reverted when you log in.
- Built-in priorities no longer show a Delete button.

### Upgrade notes
- Saved or imported priorities that set a pre-pull timing now ignore it without a warning. Their pre-pull lines follow the new show-while-needed rule.

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
