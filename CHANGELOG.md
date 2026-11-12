# Hekili Forever changelog

## Unreleased

### New
- Shaman: Stormstrike's debuff on the target (the extra damage your next Lightning Bolt, Chain Lightning or Earth Shock deals) now shows with the other auras.
- Shaman: a totem you drop now shows its buff for the totem's life and takes down the buff of the totem it replaces, Mana Tide Totem adds its mana, Improved Stormstrike (2/2) is applied by Stormstrike and a dodge or parry on you readies Stormstrike, Maelstrom Weapon cuts Lightning Bolt by 4% a talent rank a stack, Nature's Swiftness makes the next Lightning Bolt or Chain Lightning instant, the Burning Totem relic lengthens Flame Shock, and Flurry, Elemental Devastation and Windfury Totem's attack-power buff are now known to the addon and shown when the game reports them.
- A new Action Bar Glow page in the options can glow your real action bar buttons: the buttons that cast the first recommendation of a display in gold, and the second recommendation's in blue. It works on the game's keyboard and gamepad bars and on ElvUI, Bartender and Dominos, follows the display you choose, glows in combat only unless you change that, and works with the icons hidden. It is off by default.
- Mage, Priest, Druid, Hunter and Paladin: the Revelation buff of the weapon enchant of that name now shows with the other auras when the game reports it; the Undead's Touch of the Grave likewise. They are shown, not predicted.
- Custom priorities can check the kind of weapon you wear: `main_hand`, `off_hand` and `ranged` each answer `dagger`, `sword`, `axe`, `mace`, `fist`, `staff`, `polearm`, `bow`, `gun`, `crossbow`, `thrown` or `wand` (for example `main_hand.axe&main_hand.two_handed` for a two-handed axe).
- Warlock: the Doomcaller's Attire set bonuses are counted when you wear them.
- Priest: utility auras are now known to the addon, for custom priorities.
- Custom priorities can label a recommendation: `label=R6` on a line shows "R6" on its icon, and `label_if=<condition>` shows it only while the condition holds (for example to mark a lower spell rank). `icon=` (a spell ID, texture ID or texture path) with `icon_if=<condition>` asks the display to show a different icon for that line.
- Warrior: Weaponmaster now shows its three auras (`weaponmaster_axe_polearm`, `weaponmaster_mace_staff`, `weaponmaster_sword`) while you have the talent and hold that kind of weapon, for custom priorities. The sword's extra attack is not predicted.

### Changed
- Druid: in Cat Form, Feral and Guardian now recommend Claw instead of Shred while your target is attacking you (you cannot get behind it), and also when you have fewer than 2 points in Shredding Attacks, where Claw does more damage for its energy; Shred is still recommended with Clearcasting unless the target is attacking you. Claw is now shown as soon as you have its energy. Who your target is attacking can be read in the open world; in dungeons the game hides it, so Shred is assumed as before (or "Always Behind" decides). Turn on "Always Behind" if you can always get behind your target.
- The SpellFlash options are gone: SpellFlash never worked on Forever, and Action Bar Glow replaces it. Settings you saved for it are ignored.
- Hekili now reads your target's distance from LibRangeCheck, the range library other addons use, instead of from your abilities' ranges. Priorities that check how far away the target is use its answer, which comes in steps of about 5 yards. The melee range check of a display style shows the target as in melee while its distance is unknown.
- Rogue: a Shank at 5 of 5 Boot Knife now counts its 2 combo points in the forecast, and the opening Poised discount (10 energy, plus Composure's 5 or 10) is priced on the abilities it covers, so the first recommendations after a pull see the energy you really have. The Remorseless buff is known to the addon and shown when the game reports it.
- Hunter: Rapid Killing now shortens Rapid Fire's cooldown (60 seconds a rank), so a long fight shows the second Rapid Fire sooner. Aspect of the Cheetah and Dazed are known to the addon for custom priorities, and the Cryptstalker set bonuses (Rapid Fire 4 seconds longer, Multi-Shot and Aimed Shot 20 mana cheaper) are counted when you wear them.

### Fixed
- In dungeons (and in raids, if the game hides targets there too), switching targets with Tab no longer makes a debuff that the Cooldown Manager shows on your new target (such as Faerie Fire) look missing, so it is no longer recommended again.
- In dungeons (and in raids, if the game hides targets there too), the debuffs you put on an enemy are remembered when you Tab away and back, as long as its nameplate stays shown, so they are not recommended again while they are still up.
- If the range library stops answering during a fight, Hekili now treats your target's distance as unknown after 1.5 seconds instead of keeping the last distance it read. In dungeons, enemies beyond the range set for counting targets are now left out of the count.
- A display style whose range check is set to melee no longer raises a Lua error in dungeons while you target an enemy: Hekili now ships the newer LibRangeCheck-3.0.
- Gnome Warriors, Rogues, Mages, Warlocks and Priests: Eureka! now lasts 8 seconds and makes every ability it covers cost 10% less (it was 15 seconds and three casts), so it is still suggested closer to the end of a fight.
- Protection Warriors: the default priority's Thunder Clap line again checks for the Thunderfury slow; it reads down in combat, so nothing changes unless you can see the debuff.
- Druid: Balance now reads the Eclipse and Nature's Grace buffs in combat through the Cooldown Manager's talent entries, Starfire's cast time follows Improved Starfire, the Eclipse charge and Nature's Grace (Wrath follows Nature's Grace too), Nature's Swiftness makes the next Wrath instant, and the Haruspex's Garb 3-piece lengthens Faerie Fire by 5 seconds.
- Druid: the Wrath that Nature's Swiftness makes instant now uses the buff up as soon as you cast it, so the next Wrath is no longer shown as instant.
- Druid: each Starfire you cast now uses up one Eclipse charge, so the next Starfire is no longer shown with the shorter cast of a charge already used.
- Druid: Nature's Grace now shortens the global cooldown too (about 1.23 seconds on Wrath, Starfire, Moonfire and the other Balance and healing spells, 1.36 on the rest), so the recommendations after a crit come on time.
- Druid: shifting into Cat Form now sets your energy as the game does: none without Furor, and with Furor its 20% a rank of the energy you left Cat Form with plus 10 a second you spent out of Bear Form, so the first recommendations after a shift no longer count energy you do not have.
- Warrior: Deep Wound is read from the Cooldown Manager's copy of the debuff, Flurry counts its three charges, Retaliation its 30, and Gore Drinker's buff is tracked from the abilities that grant it.
- Warlock: Affliction and Shadow Brand (wowsims.com) now react to the Revelation weapon enchant's proc, Decimation and Shadow Trance are now also read from the spell's glow in combat where the game lights it, and Destruction (wowsims.com) now tracks Shadow and Flame's buffs the way wowsims does.
- Priest: Shadow (wowsims.com) now counts Dark Inspiration as soon as you cast Mind Blast, so the mana estimate no longer ignores it.
- Paladin: Seal of Justice, Light and Wisdom now count as a seal for Judgement, and Protection (wowsims.com) suggests Templar's Bulwark whenever it is ready and Cooldowns are on.
- Mage: Fingers of Frost is followed under the id the game shows, Combustion ends with its crit counter, and Master of Elements' mana refund now counts when the crit of a Fire or Frost spell is seen.
- Paladin: a landed Shieldsworn Holy Strike returns its mana, but only when the game shows target hit data (it does not on live today).
- Warlock: a hard-cast Shadow Bolt no longer uses up Shadow Trance.
- Mage: Fire Blast spends a Fingers of Frost charge at the cast.
- Retribution Paladins: each landed melee swing now stores an Echo of the seal that was up when you swung, even when you change seals before the hit shows, so a seal twist is timed from the right Echo.
- Druids and Rogues: after a /reload in combat, the estimate of your energy now refills at 10 a second straight away, instead of staying low until you leave combat.

### Known issues

### Upgrade notes
- Update the core addon (Hekili) together with its class addons (content API 14). A mismatched pair loads no priorities and says "update the older one".

## v0.7.3

_Released 2026-11-11_

This release shows your controller buttons on the recommendation icons when you play with a gamepad.

### Core and display
- Recommendations now show the controller buttons that cast them when the ability is on the game's own gamepad action bars, including modifier bars and form bars.
- The buttons are drawn as the game's button pictures in your controller style, on the icon where keybinds normally sit.
- Gamepad keys bound on normal action bars now show as pictures too; number-pad keys still show as keyboard text.
- The Generic controller style shows X, Y, B and A, matching the game's gamepad bars.
- A new Gamepad tab in each display's style options sets the button pictures' anchor point, X and Y offsets, and size, separately from keyboard keybind text.
- The ConsolePort button options now live in the Gamepad tab, and your saved choices carry over.

## v0.7.2

_Released 2026-11-10_

Feral and Guardian Druids now get suggestions that follow their current form, and several wowsims.com priorities now use your race's cooldown whatever your race.

### Druid
- Feral (wowsims.com): in Bear Form you now get the Guardian suggestions; in caster form you still get Feral's.
- Guardian (wowsims.com): in Cat Form you now get the Feral suggestions; in caster form you still get Guardian's.
- The settings for the other form's suggestions now appear on your specialization's page under their own heading, and each specialization keeps its own values.

### Hunter
- All three wowsims.com priorities now suggest your race's cooldown the way wowsims uses it, whatever your race; before, only one race got it.

### Mage
- All three wowsims.com priorities now suggest your race's cooldown the way wowsims uses it, whatever your race; before, only one race got it.

### Paladin
- Protection (wowsims.com) now suggests your race's cooldown, such as Stoneform, the way wowsims uses it, whatever your race; before, only one race got it.

### Priest
- Shadow (wowsims.com) now suggests your race's cooldown the way wowsims uses it, whatever your race; before, only one race got it.

### Rogue
- All three wowsims.com priorities now suggest your race's cooldown the way wowsims uses it, whatever your race; before, only one race got it.

### Shaman
- Enhancement (wowsims.com) now suggests your race's cooldown the way wowsims uses it, whatever your race; before, only one race got it.

### Warlock
- Affliction and SM Ruin (wowsims.com) now suggest your race's cooldown the way wowsims uses it, whatever your race; before, only one race got it.

## v0.7.1

_Released 2026-11-10_

This release attempts to fix Paladin Exorcism suggestions in dungeons.

### Paladin
- In dungeons, where the game hides a target's creature type, Exorcism is no longer suggested on targets it cannot hit, since it only works on Undead and Demons. This is an experimental fix based on evidence gathered on a Druid and not yet been confirmed in game.

## v0.7.0

_Released 2026-11-10_

Hekili Forever 0.7.0 picks some Druid, Mage and Warlock priorities from your talents, adds a Cooldown Manager options panel, reduces icon flicker and brings every class's wowsims.com priorities up to date.

### Druid
- A build with all three points of Thick Hide now runs the Guardian priority on its own, and a single stray point keeps a Feral build on Feral.
- Feral: Poised is now counted, so out of combat at full energy your next Claw, Rake, Shred, Ravage, Pounce, Rip, Ferocious Bite or Cower costs 10 less energy.
- Guardian follows the current wowsims bear priority (Tauren) and uses the Movement toggle: Bear Form first when you're out of it, Faerie Fire only while the debuff is down, Lacerate kept at 5 stacks, plus Barkskin, Enrage and Feral Charge. Berserk is no longer shown because it has left the game.

### Hunter
- Beast Mastery, Marksmanship and Survival show melee strikes once an Auto Shot has gone off since your last swing, replacing the old timing window, and show shots otherwise. Survival uses a new talent build.

### Mage
- A Fire build with Ice Shards now runs the Frostfire priority on its own.
- Arcane Missiles under Missile Barrage no longer spends Clearcasting, and Arcane Missiles can now give Clearcasting when it starts and on each missile, at most once a second.
- Arcane, Fire and Frostfire follow wowsims as of 7 November 2026.

### Paladin
- Retribution and Protection follow the current wowsims: Retribution is unchanged and Protection casts Holy Shield rank 4.

### Priest
- Shadow has a new Prefer Starshards option, off by default and only useful if you know Starshards. When on, it shows Starshards before Mind Flay whenever Mind Blast is 4 seconds or more from ready.
- Shadow and Smite follow the wowsims build of 7 November. Shadow uses its new talent build and casts Elune's Light (Night Elf) or Eureka! (Gnome) when Shadow Word: Pain and Devouring Plague have 10 s left (8 s for Eureka!) instead of on cooldown.

### Rogue
- All three specs follow the game's talent rework (wowsims as of 7 November 2026). Shank (all specs) and Death Mark (Subtlety) are now on the priorities, and Venom, Cutthroat, Thousand Cuts and Murder are gone.
- Subtlety gets Ghostly Strike back, assuming you stand behind the target, and Ghostly Strike now lets your next Ambush or Garrote skip Stealth.
- Preparation also resets Riposte. Flawless Execution makes Eviscerate cost 15 less, Efficient Strikes makes Sinister Strike and Hemorrhage cost 3 or 5 less, and Mutilate has three ranks.
- If your custom priority checks whether Riposte is usable, copy the new Riposte check from the built-in Combat priority, because the old name no longer works.

### Shaman
- Elemental and Enhancement follow the current wowsims build: Chain Lightning costs about 70% more mana, Stormstrike's cooldown is 6 seconds, and Enhancement gets its area Chain Lightning back, timed by your next weapon swing.
- Elemental: Lava Burst is gone from the game and the priority. Chain Lightning now also shows on a single target above 40% mana, Earth Shock waits for a single target, and Water Shield comes before Searing Totem.

### Warlock
- These priorities are now picked from your talents: an Affliction build with Ruin and no Wrack runs SM Ruin, and a Demonology build with Improved Shadow Bolt runs Shadow Brand.
- All five priorities follow the wowsims build of 7 November. Affliction, Demonology, Destruction and Shadow Brand open with a pre-pull Shadow Bolt or Soul Fire, and Demonology and Destruction use Life Tap below 35% mana while Affliction stays at 30%.
- Affliction uses Bane of Doom, Death Coil and Life Tap, uses Shadow Bolt only on Shadow Trance, and uses Siphon Life again (not while channelling Wrack).
- Destruction has new Hellfire, damage-over-time and cooldown sections and refreshes Immolate during Incinerate's cast. It uses Searing Pain and Death Coil as end-of-fight fillers and now uses the Movement toggle for Hellfire.

### Warrior
- Arms, Fury and Protection follow the wowsims build of 7 November:
  - Flurry, Bloodthrill and Improved Tactical Mastery have fewer ranks.
  - Raging Blows is now Improved Whirlwind: Whirlwind's cooldown is 1 s shorter per rank, and Cleave and Whirlwind no longer cost 3 less rage.
  - A stance swap keeps at most 25 rage, and Piercing Howl's cost now includes Focused Rage and Booming Voice.
- Arms uses Slam through the execute phase and Whirlwind from two targets. Slam now has a 15 s cooldown (10 s with Improved Slam).
- Fury uses the new Reckless Swings talent before the pull and on its 15 s cooldown. It uses Cleave from 25 rage and Bloodrage timed by your next weapon swing.
- Protection opens with Bloodrage, Battle Shout, Retaliation and Defensive Stance. It uses Heroic Strike from 20 rage, moves Revenge earlier, and puts Retaliation under the Cooldowns toggle.

### Core and display
- Automatic picks never replace a priority you chose yourself or a custom priority. This covers picking it, its Active toggle, `/hekili priority` and Activate on a spec page. `/hekili priority default` hands the choice back, and a notice tells you when Hekili switches.
- Every class's talent list now matches Forever's talent trees, so points per tree are counted correctly and a hybrid build close to a tie gets the right spec's priority.
- Hekili now always uses the Cooldown Manager: whenever one of its bars shows one of your auras, Hekili corrects whether it thinks that buff or debuff is up. There is no on/off setting.
- The new Cooldown Manager options panel has one switch per aura; turn one off and Hekili ignores that aura there.
  - Gold means the aura is on a bar. Grey means it isn't, and the switch applies once you add it.
  - Changes apply after combat.
- An ability waiting for mana, rage or energy now shows as ready only once you surely have enough, so pressing it no longer fails. It can light up about 0.2 s later than before.
- The first icon flickers much less: when it would swap between two abilities that are both still counting down, it keeps the current one for one more update. Ready abilities and anything after your own cast still show at once.
- Icons no longer briefly flash to the next ability as a cooldown comes back.

### Known issues
- Guardian Druids: Hekili doesn't yet count the rage you gain from hits you take. Lacerate, Primal Bite and Maul show only once the game reports the rage, and the icon can lag behind your real rage.
- Fury Warriors: the rage from Reckless Swings is counted the moment you cast it.
- Subtlety Rogues: Death Mark's payout and Boot Knife's chance of a combo point aren't counted yet.

### Upgrade notes
- Update Hekili together with its class addons. A mismatched pair loads no priorities and says "update the older one".
- Druids: if you chose Feral yourself on 0.6.2 and have all three points of Thick Hide, you may be switched to Guardian at first login without a notice. Press "Activate Feral" on the Feral spec page once and your choice stays.

## v0.6.2

_Released 2026-11-08_

This hotfix makes Hekili Forever recognize when you are in melee range, so melee abilities now appear and disappear correctly for Druids, Hunters and Warriors.

### Druid
- Feral: Shred, Claw and your other damage abilities are now recommended in melee range; before, only Prowl or Faerie Fire was shown.
- Maul is no longer recommended once your target is beyond melee range.

### Hunter
- Survival: Mongoose Bite, Wing Clip and Strider Kick should now be recommended correctly in melee range. This has not yet been confirmed in game.
- Raptor Strike is no longer recommended once your target is beyond melee range.

### Warrior
- Heroic Strike is no longer recommended once your target is beyond melee range.

### Known issues
- Feral: when you stand in front of your target, Shred is still recommended even though the game refuses it, and Claw is not offered in its place.

## v0.6.1

_Released 2026-11-07_

This small fix release stops the font outline setting "None" from breaking the display.

### Core and display
- Setting a font's outline Style to None no longer causes a Lua error that kept the display from appearing. The display now shows with plain, unoutlined text.

## v0.6.0

_Released 2026-11-06_

This release updates most wowsims.com priorities to wowsims as it was on 2 November 2026 and adds a Movement toggle, weapon imbue and poison tracking, a combo point fix for target switches, and lighter CPU and memory use.

### Druid
- Balance: follows the latest wowsims.com rotation; out of combat it shows Wrath to open after Moonkin Form, and Innervate shows only below 40% mana.
- Balance: Insect Swarm's duration now counts the Swarming Idol (+2 s) and the Grovekeeper Eclipse 5-piece (+3 s).
- Feral (wowsims.com): follows wowsims's adaptive list with the Movement toggle, and Faerie Fire shows only while its debuff is down.
- Feral: opening from Prowl now recommends Ravage, Faerie Fire waits while you are Prowled, and Prowl is no longer shown to cancel.
- Feral: after you switch targets, finishers no longer show while the new target has no combo points, and they come back when you switch back.
- Guardian: at low levels, Faerie Fire and Demoralizing Roar are no longer recast while the debuff is still on the target.
- Guardian: the Maintain Demoralizing Roar and Maintain Thunder Clap tooltips now say they recast the debuff only when it is missing.

### Hunter
- Beast Mastery, Marksmanship and Survival (wowsims.com) follow wowsims's 2 November Orc build, with consumable lines and Bestial Wrath on cooldown.
- Shots show only outside 8 yd, Wing Clip waits while Strider Kick is within 1.5 s of ready, and Beast Mastery below level 25 shows Arcane Shot.
- With Movement on, melee weave strikes can show at range from an Auto Shot until your next melee swing, and Raptor Strike ends the weave. With Movement off, they show only in melee.
- Strider Kick's cost now counts the Efficiency discount.

### Mage
- Arcane: uses Frostbolt as a filler only without Arcane Instability, adds Fire Blast, opens with Arcane Wrath and lines up cooldowns with Missile Barrage or Arcane Wrath.
- Fire: keeps Arcane Blast up, uses Scorch as a filler while Fire Blast is nearly ready, and opens with Pyroblast.
- Frostfire: opens with Pyroblast and shows Fireball while levelling until you learn Frostfire Bolt.
- Arcane Blast stacks now add 100% cost each and last 18 s, and Read Ley Line casts in 0.5 s.

### Paladin
- Protection: follows the latest wowsims.com rotation; Righteous Fury shows before the pull, and with Consecrated Ground, Holy Shock waits for Consecration.
- Protection: Holy Shield has four ranks costing 100, 150, 195 and 240 mana, learned at levels 30, 40, 50 and 60.
- Retribution (wowsims.com) follows the Unsealed Wrath priority:
  - Judgement and Holy Strike are held 0.1 s around a swing.
  - The pull opens with Judgement, then a seal while you close to melee (Movement toggle).
  - A fight started in melee kick-starts with Seal of Command.
- Low levels: Retribution re-seals only when Seal of Righteousness is down or under two global cooldowns from ending, and Protection only when Seal of Fury is down.
- Holy Strike's cooldown is 6 s with Shieldsworn, and Swift Judgement is a second Judgement on its own 60 s cooldown.

### Rogue
- Assassination, Combat and Subtlety (wowsims.com) follow wowsims's 2 November build; Combat builds with Sinister Strike and Subtlety with Hemorrhage again.
- Blood Fury and Elune's Light line up with Adrenaline Rush, and Cold Blood waits while Elune's Light is up.
- Eureka goes with Adrenaline Rush (or when Adrenaline Rush is further off than Eureka's cooldown), and builders wait while Eureka is about to be used.
- Riposte can be used in custom priorities, and Combat casts it first in the window after you parry.
- Your five poisons are now tracked on your weapons, in combat too, and a poison line in your precombat list also shows in combat while the poison is missing.
- After you switch targets, finishers no longer show while the new target has no combo points.
- Assassination no longer raises a Lua error after a /reload in combat.

### Shaman
- Enhancement (wowsims.com) follows wowsims's current build:
  - Magma and Windfury Totems, Water Shield only while it is down, Fire Nova as the filler, and an AoE list.
  - Magma Totem lasts 40 s with Trial by Fire 2/2.
  - A weapon imbue reminder (Flametongue, or Rockbiter before level 10) leads the list while your main hand has none.
- Elemental (wowsims.com): on-use items are used on cooldown, and Elemental Mastery, Blood Fury and Berserking wait for Flame Shock on the target.
- Elemental: Mana Spring Totem counts at your real rank from the first fight of a session.
- Fire Nova's mana cost now matches the game at every rank (375 at rank 5, was 520).
- Chain Lightning and Mana Tide Totem costs and rank levels are corrected (Chain Lightning rank 4 is 315 mana, was 485).
- Weapon imbues (Rockbiter, Flametongue, Windfury, Frostbrand) are tracked in combat too, and an imbue line in your precombat list also shows in combat while the imbue is missing.
- Stoneskin, Healing Stream, the resistance totems, Windwall, Tremor, the cleansing totems, Sentry, Earthbind, Stoneclaw and Grounding can now be cast and tracked in custom priorities. Their buffs can be checked too.

### Warlock
- Demonology, Shadow Brand, Destruction and SM Ruin (wowsims.com) follow the new Human builds, with Life Tap below 30% mana and Major Mana Potion and Demonic Rune lines.
- SM Ruin keeps Corruption, Siphon Life and Immolate up, casting each when it is down or about to fall off.
- Demonology and Shadow Brand use the Movement toggle: Hellfire on three or more enemies can show at range.

### Warrior
- Arms and Fury (wowsims.com) follow wowsims's 2 November build; Death Wish, Recklessness and racials are used on cooldown, and Hamstring no longer shows while levelling.
- Fury: Whirlwind comes before Bloodthirst, and Overpower weaving (a swap to Battle Stance for Overpower) is back.
- Arms: Heroic Strike is held when you have Improved Slam.
- In Battle Stance, Overpower no longer shows on another player's dodge.
- Rage tracking now doubles rage from white critical hits and counts rage from hits taken in Defensive Stance and Shield Wall.

### Core and display
- New Movement toggle, on by default: supported priorities show the next ability while out of range. Turn it off under /hekili, Toggles, Movement.
- Sharpening stones and weapon oils no longer count as a weapon imbue or poison.
- The priority editor can add Open Window and Close Window lines; no built-in priority uses them yet.
- An ability held back from your melee swing now counts down to just after the swing instead of briefly disappearing.
- Fewer one-moment flashes of a filler as a cooldown comes back.
- Enemies you kill leave the target count at once, so AoE and cleave lines are no longer held back.
- Your mana estimate stays right at low frame rates when a cast grants a free-cast proc.
- No more Lua errors from nameplates in dungeons and raids.
- A display that fails to build reports its error once and stays blank instead of erroring on every redraw.
- Import boxes reject broken strings with a message, and /hekili lock no longer errors before you have unlocked.
- Lighter in big pulls and raids: less memory use, fewer refreshes from auras, and no listening to group addon messages. Buffs still show within about 0.2 s.
- Out of combat with no hostile target, icons refresh every 1.5 s; changing target, casting or entering combat still refreshes them at once.
- The Auto Snapshot option and the experimental damage meter and Cooldown Manager options are removed, and those experimental features are now off.

### Known issues
- Many updated priorities have not been checked in game yet, and more wowsims updates follow in 0.6.1 and later.
- Elemental (wowsims.com) still has a Lava Burst line (it is skipped), and the rest of the rotation is not yet re-tuned for Lava Burst's removal.
- Survival: with an empty mana pool in melee, the first icon can switch between Raptor Strike and Strider Kick about once or twice a minute.
- Warlock: after a Demonic Rune or Major Mana Potion, Life Tap may show for up to 40 s even though your mana is high.
- In dungeons and raids, only one enemy is counted, so AoE abilities are not recommended there.
- A display can occasionally fail to build and stay blank; the cause is still being investigated.

### Upgrade notes
- In custom or imported priorities, `energy.current` and `mana.pct` now give the addon's best estimate. Use `energy.lo` or `mana.pct_lo` for the old cautious reading.

## v0.5.0

_Released 2026-10-31_

This release makes mana predictions much more accurate for every mana class, so recommendations near your mana cost are steadier. It also adds an experimental Modern display option that shows the game's own cooldown and usability feedback.

### Druid
- Mana prediction now includes the Serenity Field trinket's Spirit buff (about 9 mana a second more for its 15 seconds).
- High Order Skyborne: Energized's doubled mana regen now counts in predicted mana, and Read Ley Line is tracked. Windshaper Skyborne don't get either.

### Hunter
- Mana prediction now includes Resourcefulness and Rapid Recuperation.
- Mana prediction now starts from measured regen rates for Beast Mastery, Marksmanship and Survival instead of a guess.
- High Order Skyborne: Energized's doubled mana regen now counts in predicted mana, and Read Ley Line is tracked. Windshaper Skyborne don't get either.

### Mage
- Evocation's mana now follows your actual mana regen instead of a fixed amount.
- Mana prediction now starts from measured regen rates for Arcane, Fire and Frostfire.
- High Order Skyborne: Read Ley Line is now recommended where the Mage priorities cast it, and Energized's doubled mana regen counts in predicted mana. Windshaper Skyborne don't get either.

### Paladin
- Retribution and Protection mana prediction now uses measured regen rates, so the icons follow you down to an empty mana pool.

### Priest
- Mana prediction now includes Dark Inspiration's Spirit.
- Dark Sacrifice's mana now follows your Spirit instead of a fixed amount.
- Shadow and Smite mana prediction now uses measured regen rates.

### Shaman
- Enhancement: mana prediction now includes Improved Stormstrike.
- Elemental and Enhancement mana prediction now uses measured regen rates instead of a guess.
- Mana Spring Totem's mana now counts only while your water totem is standing, not all the time.

### Warlock
- Mana prediction now includes Fel Energy from sacrificing your Voidwalker (2% of maximum mana every 4 seconds while it is up).

### Core and display
- Channels you paid mana for keep casting-rate regen until the channel ends, instead of switching back to Spirit regen after 5 seconds.
  - This covers Wrack, Drain Soul, Rain of Fire, Hellfire, Arcane Missiles, Blizzard, Hurricane and Volley.
  - Free channels, such as Evocation or a free Arcane Missiles, are not affected.
- Two abilities that are nearly tied on mana or energy no longer swap places in the first icon on every update as your resource ticks up.
- When your mana sits just under a higher-priority ability's cost, the first icon no longer flickers to a cheaper ability for one update.
  - The higher-priority ability keeps its countdown until you can afford it.
- Abilities can show as ready up to one update sooner. They stay on a countdown while the game says you can't afford them.
- New experimental Modern option in each display's Modern tab. It keeps your Classic or Timeline look and adds:
  - the game's own cooldown swipes;
  - an immediate grey when the game says an ability can't be used yet;
  - an optional proc mark on the next ability when the game lights its proc (off by default).

### Known issues
- With Timeline's Timers Out of Combat turned off, Modern's cooldown swipe still shows running cooldowns out of combat.
- Modern is experimental, and parts of it may be switched off in a later update.

## v0.4.0

_Released 2026-10-26_

This release matches your hits, misses and DoT ticks to the right cast more reliably, adds parry haste, Simplified Chinese and two experimental options, and fixes many resource and display issues.

### Druid
- Innervate's mana is now expected as the game gives it: five times your Spirit-based regeneration, all of it while casting. A mana reading taken while Innervate is up no longer skews the estimate afterwards.
- Balance and Feral no longer show a mana-costing ability such as Shifting Power before you can afford it.
- A Maul that lands just after Demoralizing Roar is no longer mistaken for the Roar's result.

### Warlock
- After Life Tap, or any spell that gives you mana or energy, the resource estimate no longer stays too low. Shadow Bolt is no longer shown as unaffordable right after a Life Tap.

### Warrior
- Rage from being hit now follows the game's rage formula, counting armor buffs such as Inspiration.
- Rage from Bloodrage, and from Berserker Rage with Improved Berserker Rage, now counts at once. An ability you can afford with it is no longer shown as unaffordable right after the press.
- Protection: a partly blocked hit on you now opens Revenge's window, as a full block, dodge or parry does.
- Protection: rage from Shield Specialization (5/5) and Master of Defense (2/2) is now counted in full on every block, dodge or parry.

### Core and display
- Your hits, misses and DoT ticks are now matched to the cast that made them, even when they arrive late. This covers:
  - a projectile landing (Wrath, Shadow Bolt, Frostbolt)
  - a killing blow after your target clears
  - a cast where you switched targets midway
  - a crowded pull where other players hit the same mob
- A projectile's crit or miss now counts when the bolt lands, so crit-triggered effects and miss refunds follow it.
- Hits that arrive late or out of order are now matched to their cast instead of dropped. A white swing whose result never shows now counts at its expected rage.
- If a mob runs at you while you cast, the addon no longer loses track of your spell's landing.
- A DoT whose application missed (Insect Swarm, for example) is no longer treated as ticking on the target.
- Parry haste, both ways:
  - When you parry, the swing timer expects your next main-hand swing sooner. Its rage, a Slam between swings and queued strikes follow.
  - A mob that parries you swings sooner too, and its hits on you are still told apart when several mobs are on you.
- Rage no longer drifts when a fight ends: a white swing just before combat ends still counts its rage.
- Orc Blood Fury's cooldown is now 3 minutes, as on Forever.
- The next on-GCD ability no longer disappears behind off-GCD suggestions such as Bloodrage or Heroic Strike. The Timeline now looks up to two steps further, while the classic icon row still shows your set number of icons.
- A queued strike that is not ready yet (Heroic Strike, Cleave, Maul, Raptor Strike) now shows its cooldown sweep until it is time to press it. This applies to every icon of the classic row and to the Timeline.
- An ability due exactly 0.2 s away no longer flickers in and out of the first icon. An example is a DoT falling off just as Mind Flay ends.
- The "attempt to index field 'leftText' (a secret string value)" error in combat is fixed.
- WeakAuras: the recommendation data can now carry up to two extra entries beyond your icon count, for the off-GCD look-ahead.
- Steady icons (experimental, off by default): turning it on now shows an "updates to hold" slider.
  - The range is 1 to 3 (default 1); each update is about 0.1 to 0.2 s.
  - A countdown icon is no longer held when the next one is about to become ready, so holding never turns a change into a brief flash.
- New experimental option, off by default (Options > Performance > Experimental): use the game's damage meter events to know at once whether your white swing hit.
  - It works even with the Damage Meter window hidden or disabled.
  - It should credit other players' hits to you less often and keep rage closer in crowds, but Fury suggestions may change slightly more often.
  - It has not been tested in game yet.
- New experimental option, off by default (Options > Performance > Experimental): read whether an aura is up from the game's Cooldown Manager.
  - It only covers auras you applied that the Cooldown Manager tracks; so far that is a few Warrior auras.
  - The Cooldown Manager must be enabled in the game options.
  - Changing the option in combat takes effect when the fight ends.
- Snapshots now include two extra lines showing how many of your hits and misses were matched, lost or unclear. Please include them when you report a wrong recommendation.
- Simplified Chinese (简体中文): on a Chinese client, the following are now in Chinese. Untranslated text still shows in English. Translation by dodoels.
  - options and class settings
  - chat messages and notifications
  - the minimap menu

### Known issues
- In a crowded pull on a laggy connection, many white swings are still not recognized, so rage can read off until your next ability press corrects it.
- In a raid-sized group all hitting one target, your projectile landings are not recognized yet, so their crit and miss effects are not followed.
- Fast dual-wield rage can still read off in groups, because swings are sometimes credited to the wrong hand.
- Solo, rage very rarely reads one swing too high.

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
