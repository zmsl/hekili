# Hekili Forever changelog

## Unreleased

### New
- Druid: "Feral (wowsims.com)", "Guardian (wowsims.com)" and "Balance (wowsims.com)", translated from wowsims.com's
  own priorities for WoW Forever, are the Feral, Guardian and Balance defaults. Guardian: Berserk once Demoralizing
  Roar is up and Primal Bite is on cooldown, Lacerate kept at five stacks, Primal Bite, then Lacerate, and Maul at 20
  rage; Bear Form first when you are out of it.
- Hunter (new addon folder Hekili_Hunter): "Beast Mastery (wowsims.com)", "Marksmanship (wowsims.com)" and "Survival
  (wowsims.com)" are each specialization's default, translated from wowsims/forever's Melee Weave: Wing Clip,
  Mongoose Bite, Strider Kick and Immolation Trap while you are in melee range, the shots between swings, Rapid Fire
  and Blood Fury from 5 seconds into a fight. Resourcefulness and Efficiency lower the mana costs the addon expects.
- Mage (new addon folder Hekili_Mage): the Mage's abilities and talents; Frost shows the "no priorities on Forever"
  notice.
- Mage: "Arcane (wowsims.com)" is the Arcane default, translated from wowsims.com's own: Missiles on Missile Barrage,
  Arcane Wrath, Arcane Blast to its charges while mana allows, Frostbolt between, Evocation at 10% mana.
- Mage: "Fire (wowsims.com)" is the Fire default, translated from wowsims.com's own: Scorch to five Fire
  Vulnerability stacks, Pyroblast on three Heating Up stacks, Fire Blast, Missiles on Missile Barrage, Fireball,
  Evocation at 10% mana.
- Paladin: "Protection (wowsims.com)" and "Retribution (wowsims.com)" (wowsims's Twist of Light, your on-use
  trinkets included) are the Protection and Retribution defaults.
- Rogue: "Assassination (wowsims.com)", "Combat (wowsims.com)" and "Subtlety (wowsims.com)", translated from
  wowsims.com's Rogue priority, are each specialization's default.
- Shaman: "Enhancement (wowsims.com)", translated from wowsims.com's own, is the Enhancement default.
- Warrior: "Arms (wowsims.com)", "Fury (wowsims.com)" and "Protection (wowsims.com)", translated from wowsims/forever's
  own rotations, are the Arms, Fury and Protection defaults. Below the level of Bloodthirst, Fury fills with Sunder
  Armor; Arms (wowsims.com) keeps wowsims's Stance Dance and Recklessness switches off, Fury its Rend Weave on.
- Pets and guardians: the addon tracks your pet and your summoned guardians (Summon Hawk, up to two), so priorities can
  ask whether a pet is out and how many guardians are up.
- Specializations: each supported class has one specialization page per talent tree, each with its own priorities
  and settings (the Druid's Feral Combat tree has two: Feral and Guardian). The active specialization follows the
  talent tree with the most points; change it with the "Activate <Spec>" button on a specialization page or with
  `/hekili spec <name>` (`/hekili spec` lists them). Healing trees (Holy, Restoration) and Elemental show a "no
  priorities on Forever" notice and the addon recommends nothing while one is active.
- Priorities: a precombat line may carry `prepull_at=<seconds before the pull>`; such a line is recommended once
  between fights (after its spell is cast or its buff is seen up, and again once that buff runs out), in the list's
  order, so two seals no longer alternate before a pull.
- Priorities can read the distance to your target (`target.distance`, `target.within5`, `target.outside8`): the addon
  brackets it from your abilities' range checks (for example "past Wing Clip, inside Arcane Shot"), keeps the last
  reading if the game hides it, and treats an unknown distance as in range. Before, these conditions never worked on
  WoW Forever.
- Abilities can be limited to target creature types (for example undead and demons); the addon reads the target's
  type in any client language, and a type it cannot read never hides an ability.
- The addon keeps a ranged Auto Shot timer next to the melee swing timers.

### Changed
- Sweeping Strikes and Vanish follow the Cooldowns toggle and Healthstone the Defensives toggle, so you can hide them;
  "Balance (wowsims.com)" shows Moonkin Form first whenever you are out of it.
- Druid: the hand-built Feral, Guardian and Balance priorities are gone, with the settings only they read (Ferocious
  Bite finisher, out-of-combat buffs, Moonkin Form, Moonfire on trash, Starfire filler, Hurricane targets, Innervate
  and its mana thresholds, Swipe Rage Threshold, Use Enrage, Lacerate Refresh Window) and the unread "Rip Combo
  Points". The Guardian default has no Swipe or multi-target branch, no Faerie Fire, no Enrage and no trinket use,
  which the old list had.
- Hunter: the hand-built BeastMastery, Marksmanship and Survival priorities are gone, with their Arcane Shot and Wing
  Clip mana floor settings.
- Paladin: the hand-built Protection and Retribution priorities are gone, with Retribution's Holy Shock list and the
  Consecration and Exorcism Mana Floor settings (wowsims's 10% floor is in the new priority); Righteous Fury is no
  longer suggested before combat (wowsims's Protection never casts it).
- Rogue: the hand-built Assassination, Combat and Subtlety priorities are gone, with their settings (Bleeds on
  Trash, Maintain Expose Armor, Vanish to Re-open, Ambush Opener, Backstab Builder, Poison Reminders).
- Shaman: the hand-built "Enhancement" priority is gone, and with it its imbue reminder and mana settings.
- Warrior: the hand-built Arms, Fury and Protection priorities are gone, with their settings: Use Queue Prediction,
  Queue During Execute, Minimum Enemies For Whirlwind, Whirlwind Cooldown Differential, Hamstring Rage Threshold,
  Hamstring Cooldown Differential, Maintain Sunder Armor, Max Sunders, Minimum Sunder Level, Maintain Demoralizing
  Shout, Maintain Thunder Clap, Rage Cap, Heroic Strike Rage, Cleave Rage and Challenging Shout Enemies. Limit Sunder
  Armor, Demoralizing Shout or Thunder Clap with the ability's own options (Disable, Boss Encounter Only, a custom
  toggle).
- At login, a retired priority is announced as retired ("a spec that used it now runs its default priority"), not as
  updated.
- Deleting or unchecking a custom priority falls back to the specialization's default priority.
- Specializations follow your talents: a respec or dual-spec swap that moves your most-spent talent tree activates
  that tree's specialization, the one you last activated for it (for example Guardian on the Feral Combat tree) or
  else its first. Swapping between two builds of the same tree keeps your choice. The "your talents favor" hint is gone.
- Options: each specialization page starts with its Priority and an "Activate <Spec>" button (a gold "Active" marker
  on the active one; the Active Specialization dropdown is gone) and ends with a "Disable <Spec>" checkbox in place of
  "<Spec> Enabled". Each priority now sits under its specialization in the options tree (Priorities keeps Import /
  Export and Create a New Priority), and the active specialization is listed first with a gold highlight.
- The AddOns list shows Hekili Forever under the Combat category.
- Strikes on your next swing (Raptor Strike, Heroic Strike, Maul) are no longer recommended while the addon knows your
  target is beyond melee range (the game's own range check says "in range" for them at any distance).
- Developer: the default priorities are generated from wowsims/forever (pinned d33930d0) by `make wowsims-packs` from
  the recipes in `tools/wowsims/specs/`, each gated against wowsims's own fight (`make test-wowsims`, also in
  `make check`); the guide is `docs/dev/wowsims-packs.md`, the open gaps `docs/dev/gaps.md`.
- Developer: other addons can listen to snapshots with `Hekili:RegisterSnapshotListener(fn)` (and
  `UnregisterSnapshotListener`): `fn(index, record, isAuto)` runs once after each snapshot is saved, and text it returns
  shows in the snapshot under "## External".
- Developer: a wowsims recipe may map aura IDs alone (`auras = { [id] = key }`) for an aura wowsims keys by an
  ability's own spell ID. At the pinned wowsims, Protection Warrior's APL reads two: 25288 (Revenge rank 6, its
  Revenge window: map it to `revenge_usable`) and 12975 (Last Stand, read as `buff.last_stand` as wanted).
- Developer: a generated pack's header lists only the wowsims switches an emitted line reads.
- Developer: the mana estimate's at-rest lower bound is pinned by tests (no behaviour change).
- Developer: the test harness answers the mana regen pair (`GetManaRegen`) as the client does, plain out of combat
  and secret in combat, and its wowsims replays read the mana regen rates from the log.
- Developer: unreadable (secret) answers to "does this unit exist / is it dead" for target, party, boss and focus units
  are counted by the addon's diagnostics again; an unreadable "is my pet dead" falls back to the addon's own estimate.
- Developer: the headless loop ends a fight killed by its last press out of combat for both instances, and starts each
  fight with no buffs believed from the last one (the next fight used to start "in combat", skipping the precombat
  list, and the oracle's own run depended on the run before it).
- Developer: the headless loop's cost-refusal gate counts a refusal against the addon only when the oracle would not
  have pressed the same icon at that tick; the line keeps the raw rates and shows the paired one ("unmatched").
- Developer: each fight of a multi-fight headless loop starts with the pools the last one left, regenerated (mana,
  energy) or decayed (rage) through the 30 s gap, instead of full, as the addon's estimate already carries them.

### Fixed
- Testing: the headless harness models cast bars and channels (cast start, channel start, ticks, stop and a clipped
  channel), in its own fights and in the wowsims replays, so casters and channels can be checked.
- Costs: a class can declare a spell's mana cost as a share of base mana that a stacking effect raises past 100%
  (`spendBase`); such a cost is priced from base mana, not read as a cost of one or two mana.
- Rogue, Paladin and Shaman: the default priorities now load. They were registered under the wrong specialization ids
  for the WoW Forever client, so the addon showed nothing for these classes.
- Rage: a white swing's rage is counted from the swing itself, as the game gives it (measured in game), not from the
  hit's combat report half a second later. The addon now reads the "not enough rage" answers it hears after a swing
  as news about that swing, keeps a critical hit's extra rage when the game confirms it, and no longer credits a swing
  that gave no rage with another player's hit.
- Rage: an ability used at the moment of a white swing no longer leaves the rage estimate too high once that swing's
  hit shows up (the swing's rage had already paid for the ability).
- Rage: Heroic Strike no longer counts down to a swing, jumps to the next one and turns ready a moment later: a swing's
  rage stays expected until an answer that could show it, its hit, or the time its hit is due.
- Dodged, parried and missed abilities: the addon no longer counts their debuff as applied (a dodged Sunder Armor is no
  stack, a missed Rend is not up), and the rage or energy estimate gets back the 80% that the game returns for the
  abilities that refund it (Warrior, Rogue and Feral Druid strikes; not Whirlwind, Cleave or Thunder Clap), counted
  from the moment the ability was used, where the game gives it; an avoid reported up to about half a second later
  still finds its ability.
- Mana (Paladin, Shaman, Hunter and other spirit regenerators): in combat the addon forecast mana with the
  while-casting rate, as if the five-second rule never ended, so at low mana it waited for mana that never came and
  showed no icon. It now regenerates at the full rate from 5 seconds after your last mana spend, its own planned
  casts included.
- Mana and energy: the addon no longer believes you nearly out of mana (or energy) after a reload. It assumes the
  bar full until the game says otherwise, so a mana-rich fight no longer waits on spells it can afford.
- Free casts: a spell made free by a buff it uses up (Clearcasting, five Maelstrom Weapon stacks) no longer counts as
  spending mana or opening the five-second rule.
- Priorities that check your own health (such as "below 50% health") no longer raise an error when they load. While
  the game hides your health the addon treats it as full, so a defensive line waits rather than firing on a guess;
  out of combat it reads your real health.
- Pre-pull actions no longer show in combat when the pre-pull list hands them to another list: Fury recommended
  Intercept all fight (and planned its rage around it), and Arms did the same with stance dancing on.
- Druid: Primal Bite is ready again during Berserk; Lacerate's cost with Shredding Attacks and the Balance spells' mana
  costs with Moonglow and Improved Wrath now match the game's numbers as wowsims.com models them.
- Druid: in Bear Form the rage estimate counts 11.25 rage a white swing (it counted 8.65) and Primal Fury's rage (5 at
  2/2, 2.5 on average at 1/2) on each of your critical hits, white or Maul, Swipe, Lacerate and Primal Bite, as
  wowsims.com models them.
- Druid: "Feral (wowsims.com)" now pairs Berserk with the Rake or Shred that follows it, as wowsims does.
- Druid: Shifting Power's cooldown is 1 s shorter with the Howling Idol equipped; with the Wolfshead Helm equipped,
  Shifting Power gives 45 energy and Enrage 15 instant rage.
- Druid: Moonglow's first two points cut the Balance spells' mana by 8% and 17%, as in the game.
- Druid: at level 60 the forms, Shifting Power and Innervate cost their percent of base mana (Shifting Power 684, not
  over 1200), and Shredding Attacks counts all three points (Shred 42 energy at 3/3).
- Druid: the mana estimate regenerates in combat outside the five-second rule (about 22 a second with pre-raid gear)
  instead of not at all.
- Hunter: priority lines that divide (Multi-Shot's) now fire. Divisions in the priorities translated from
  wowsims ran as a remainder, so those lines never recommended their ability.
- Hunter: Arcane Shot's cooldown is 0.3 s shorter per rank of Improved Arcane Shot, so it comes back when the game
  says it does.
- Hunter: at range, Multi-Shot is no longer expected to fit before a melee swing that never comes; the weave line
  waits for the walk in, as wowsims's does.
- Paladin: Judgement's cooldown is 1 s shorter a rank of Improved Judgement; Holy Conduit lowers the mana cost of
  Consecration, Hammer of Wrath and Exorcism; Benediction lowers every other cost; Sanctified Judgement's mana refund
  is counted; the Undead/Demon ranks of Exorcism are recommended only against an Undead or Demon target; Consecration's
  mark on the target is the aura the game shows (1280353).
- Rogue: "Assassination (wowsims.com)", "Combat (wowsims.com)" and "Subtlety (wowsims.com)" now open with Blood Fury
  then Adrenaline Rush, as wowsims does; the translation had left out wowsims's fixed-order pairs.
- Rogue: Garrote costs 10 less a Dirty Deeds rank, Backstab and Hemorrhage 3 less a Thousand Cuts stack, and
  Improved Sinister Strike takes 5 off at 2/2 (it took 10), as in wowsims.com.
- Shaman: Reverberation and Improved Fire Nova now shorten the shock and Fire Nova cooldowns, Shamanistic Focus lowers
  the shocks' and Lightning Shield's cost, Call of Flame lengthens Flame Shock, and Stormstrike costs what wowsims.com
  charges.
- Warrior: Thunder Clap's debuff on the target was always read as down, so priorities that refresh it suggested
  Thunder Clap again and again; it now counts from any warrior's Thunder Clap on your target, as the game's slow
  does (a group's second warrior no longer reapplies it).
- Warrior: Arms and Fury below level 40 no longer suggest Sunder Armor at five stacks.
- Warrior: Improved Slam is modelled: with the talent Slam is a 1.0 s cast with a 1.0 s global cooldown on a 15 s
  cooldown (1.5 s and 18 s without), so the Arms priorities place Slam on its real timing.
- Warrior: Anger Management's rage is 1.5 every 5 seconds in combat (it was assumed 1 every 3 seconds), as the game data
  and wowsims/forever give it; rage forecasts with the talent are slightly lower.
- Warrior: talent cost reductions are priced per rank as wowsims/forever charges them: Focused Rage takes 1 rage a rank
  (it was 3) and now also covers Demoralizing, Challenging and Intimidating Shout and Death Wish; Improved Thunder
  Clap 2 a rank (was 6), Improved Sunder Armor 1 a rank (was 3), Improved Execute 3 then 5 (was 5 then 10); Booming
  Voice lowers the shouts' cost 5% a rank.

### Known issues
- Hunter priorities are unchecked in game: Auto Shot timing, the percent-of-base mana costs and the rune Raptor
  Strike variants.
- Hunter: Multi-Shot is recommended only when it ends before your next melee swing (wowsims's melee weave), so a
  Hunter who never walks into melee rarely sees it; Beast Mastery and Marksmanship run the same list; the defaults
  never recommend Aimed Shot, Sniper Shot or Summon Hawk (wowsims's switches for them are off).
- Rogue, Paladin and Shaman priorities are not yet checked in game.
- Shaman: the Enhancement priority no longer shows the weapon-imbue reminder (the wowsims.com list has none).
- Shaman: the Enhancement priority's mana lines (mana potion, Demonic Rune, Fire Nova above 10%) are always on and read
  an estimated mana.
- Shaman: Fire Nova is believed to cost 520 mana where wowsims.com uses 375.
- The game does not tell an addon how long a fight has left, so every priority treats each fight as a long one: Feral's
  end-of-fight Ferocious Bite and the Rogue priorities' end-of-fight lines never show, and Rip can be recommended on a
  mob that dies before it ticks out.

### Upgrade notes
- Rogue: a saved choice of the Assassination, Combat or Subtlety priority falls back to that specialization's
  wowsims.com default.
- Hunter: a saved choice of BeastMastery, Marksmanship or Survival falls back to that specialization's wowsims.com
  priority.
- Druid: a saved choice of the old Feral, Guardian or Balance priority falls back to its "(wowsims.com)" default.
- Warrior: a saved choice of the old Arms, Fury or Protection priority falls back to that specialization's
  "(wowsims.com)" default.
- Update the core (Hekili) together with its class addons: the class addons now need content API 8 (an ability's
  avoid refund); a mismatched pair loads no priorities and says "update the older one".
- Your class's existing settings (thresholds, toggles, ability and item options) are copied once into each of its
  specializations, and a custom priority you had chosen stays selected for your active specialization. Change them per
  specialization afterwards; old priority exports still import.
- Paladin: a saved choice of the old "Protection" or "Retribution" priority falls back to its "(wowsims.com)" default
  at the next login.
- Shaman: a saved choice of the "Enhancement" priority falls back to "Enhancement (wowsims.com)".

## v0.1.0

First release of Hekili Forever, based on the original work by Hekili, for the WoW Forever client.
- Druid (Feral, Balance, Guardian) and Warrior (Arms, Fury, Protection) default priorities.
- Classic and Timeline display styles.
- Fork notice and fork links (github.com/zmsl/hekili); licence GPLv3 or later.
