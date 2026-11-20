# Translation glossary

One table per group. Fill a row once, then every draft and review uses it, so the same English term gets the same word in every string.

- **enUS** is the term as the addon writes it. **deDE, esES, frFR** are the official words the Forever client shows in that language. **Source** says where each one was read: the localized client (spellbook, talent frame, options screens) or the DB2 locale names (wowdb 70707). A cell with no source is not final.
- Spanish is written once, in neutral wording that reads well in Spain and Mexico (the esES file serves both clients); where the client's two Spanish words differ, note the esMX word in the Source column.
- **Register:** informal address in German, French and Spanish (du, tu, tú), matching the Forever client's own register. Confirm it with a native reviewer before the first translated release.
- **Jargon:** use the client's words for game terms and interface words. Keep English only where players say it in English, for example AOE. Keep `wowsims.com`, `Hekili`, `/hekili ...` commands, APL expression names, colour codes and format codes verbatim.
- **Source** and **Notes** carry one entry per language (de, es, fr). Where the Spanish client's two words differ, the esES cell adds the esMX word as `(esMX: ...)`.
- **Owner-ruled exceptions to "names exactly as the client":** French writes accented capitals (Équilibre, Élémentaire, Éclats stellaires) where the Forever client writes E without the accent; French Feral and Guardian are Farouche and Gardien (the client has one "Combat farouche" tab and no Guardian). wowsims build names that are not game terms stay English: Shadow Brand, SM Ruin.
- Spell and spec names come from the client or DB2, never from memory. wow-ui-source has no per-locale game strings.

## Classes

| enUS | deDE | esES | frFR | Source | Notes |
|---|---|---|---|---|---|
| Druid | Druide | Druida | Druide | de: F-DB2 ChrClasses DRUID; es: DB2 wowf ChrClasses 11; fr: F-DB2 ChrClasses |  |
| Hunter | Jäger | Cazador | Chasseur | de: F-DB2 ChrClasses HUNTER; es: DB2 wowf ChrClasses 3; fr: F-DB2 ChrClasses | es: female Cazadora |
| Mage | Magier | Mago | Mage | de: F-DB2 ChrClasses MAGE; es: DB2 wowf ChrClasses 8; fr: F-DB2 ChrClasses | es: female Maga |
| Paladin | Paladin | Paladín | Paladin | de: F-DB2 ChrClasses PALADIN; es: DB2 wowf ChrClasses 2; fr: F-DB2 ChrClasses |  |
| Priest | Priester | Sacerdote | Prêtre | de: F-DB2 ChrClasses PRIEST; es: DB2 wowf ChrClasses 5; fr: F-DB2 ChrClasses | es: female Sacerdotisa |
| Rogue | Schurke | Pícaro | Voleur | de: F-DB2 ChrClasses ROGUE; es: DB2 wowf ChrClasses 4; fr: F-DB2 ChrClasses | es: female Pícara |
| Shaman | Schamane | Chamán | Chaman | de: F-DB2 ChrClasses SHAMAN; es: DB2 wowf ChrClasses 7; fr: F-DB2 ChrClasses |  |
| Warlock | Hexenmeister | Brujo | Démoniste | de: F-DB2 ChrClasses WARLOCK; es: DB2 wowf ChrClasses 9; fr: F-DB2 ChrClasses | es: female Bruja |
| Warrior | Krieger | Guerrero | Guerrier | de: F-DB2 ChrClasses WARRIOR; es: DB2 wowf ChrClasses 1; fr: F-DB2 ChrClasses | es: female Guerrera |

Where to read this group: client class name (DB2 ChrClasses).

## Specializations

| enUS | deDE | esES | frFR | Source | Notes |
|---|---|---|---|---|---|
| Balance | Gleichgewicht | Equilibrio | Équilibre | de: F-DB2 TalentTab 283; es: DB2 wowf TalentTab 283; fr: F-DB2 TalentTab (« Equilibre ») | fr: accent normalized |
| Feral | Wildheit | Feral | Farouche | de: retail ChrSpecialization 103; es: DB2 wowf TalentTab 281 "Combate feral"; fr: R-DB2 ChrSpecialization | de: Forever tab 281 is "Wilder Kampf" (Feral Combat); Hekili splits it into Feral (cat) and Guardian (bear), retail names used. UNCERTAIN; es: tab is "Combate feral"; spec word alone "Feral" (retail ChrSpecialization 103); fr: retail-only: Forever's talent tab is « Combat farouche » (Feral Combat) |
| Guardian | Wächter | Guardián | Gardien | de: retail ChrSpecialization 104; es: retail ChrSpecialization 104; fr: R-DB2 ChrSpecialization | de: no Forever tab; UNCERTAIN; es: no Forever tab (Feral Combat covers bears); fr: retail-only: no Forever tab of that name |
| Restoration | Wiederherstellung | Recuperación (esMX: Restauración) | Restauration | de: retail ChrSpecialization 105/264; es: DB2 wowf TalentTab 262/282; fr: F-DB2 TalentTab | de: Forever tabs 262/282 truncate to "Wiederherst" (tab width); full word used; es: esES client says Recuperación, esMX Restauración; esES name ships |
| Beast Mastery | Tierherrschaft | Dominio de bestias (esMX: Bestias) | Maîtrise des bêtes | de: F-DB2 TalentTab 361; es: DB2 wowf TalentTab 361; fr: F-DB2 TalentTab | es: retail esES also "Bestias" |
| Marksmanship | Treffsicherheit | Puntería | Précision | de: F-DB2 TalentTab 363; es: DB2 wowf TalentTab 363; fr: F-DB2 TalentTab |  |
| Survival | Überleben | Supervivencia | Survie | de: F-DB2 TalentTab 362; es: DB2 wowf TalentTab 362; fr: F-DB2 TalentTab |  |
| Arcane | Arkan | Arcano | Arcanes | de: F-DB2 TalentTab 81; es: DB2 wowf TalentTab 81; fr: F-DB2 TalentTab |  |
| Fire | Feuer | Fuego | Feu | de: F-DB2 TalentTab 41; es: DB2 wowf TalentTab 41; fr: F-DB2 TalentTab |  |
| Frost | Frost | Escarcha | Givre | de: F-DB2 TalentTab 61; es: DB2 wowf TalentTab 61; fr: F-DB2 TalentTab |  |
| Holy | Heilig | Sagrado | Sacré | de: F-DB2 TalentTab 202/382; es: DB2 wowf TalentTab 202/382; fr: F-DB2 TalentTab |  |
| Protection | Schutz | Protección | Protection | de: F-DB2 TalentTab 163/383; es: DB2 wowf TalentTab 163/383; fr: F-DB2 TalentTab |  |
| Retribution | Vergeltung | Reprensión | Vindicte | de: F-DB2 TalentTab 381; es: DB2 wowf TalentTab 381; fr: F-DB2 TalentTab |  |
| Discipline | Disziplin | Disciplina | Discipline | de: F-DB2 TalentTab 201; es: DB2 wowf TalentTab 201; fr: F-DB2 TalentTab |  |
| Shadow | Schatten | Sombra | Ombre | de: F-DB2 TalentTab 203; es: DB2 wowf TalentTab 203; fr: F-DB2 TalentTab |  |
| Assassination | Meucheln | Asesinato | Assassinat | de: F-DB2 TalentTab 182; es: DB2 wowf TalentTab 182; fr: F-DB2 TalentTab |  |
| Combat | Kampf | Combate | Combat | de: F-DB2 TalentTab 181; es: DB2 wowf TalentTab 181; fr: F-DB2 TalentTab | de: retail renamed it Outlaw/Gesetzlosigkeit; Forever name wins; es: retail renamed it Outlaw (Forajido) |
| Subtlety | Täuschung | Sutileza | Finesse | de: F-DB2 TalentTab 183; es: DB2 wowf TalentTab 183; fr: F-DB2 TalentTab |  |
| Elemental | Elementar | Elemental | Élémentaire | de: F-DB2 TalentTab 261; es: DB2 wowf TalentTab 261; fr: F-DB2 TalentTab (« Elémentaire ») | fr: accent normalized |
| Enhancement | Verstärkung | Mejora | Amélioration | de: retail ChrSpecialization 263; es: DB2 wowf TalentTab 263; fr: F-DB2 TalentTab | de: Forever tab 263 truncates to "Verstärk" |
| Affliction | Gebrechen | Aflicción | Affliction | de: F-DB2 TalentTab 302; es: DB2 wowf TalentTab 302; fr: F-DB2 TalentTab |  |
| Demonology | Dämonologie | Demonología | Démonologie | de: F-DB2 TalentTab 303; es: DB2 wowf TalentTab 303; fr: F-DB2 TalentTab |  |
| Destruction | Zerstörung | Destrucción | Destruction | de: F-DB2 TalentTab 301; es: DB2 wowf TalentTab 301; fr: F-DB2 TalentTab |  |
| Arms | Waffen | Armas | Armes | de: F-DB2 TalentTab 161; es: DB2 wowf TalentTab 161; fr: F-DB2 TalentTab |  |
| Fury | Furor | Furia | Fureur | de: F-DB2 TalentTab 164; es: DB2 wowf TalentTab 164; fr: F-DB2 TalentTab |  |

Where to read this group: client spec name (DB2 ChrSpecialization / talent tab).

## Abilities and auras named in strings

| enUS | deDE | esES | frFR | Source | Notes |
|---|---|---|---|---|---|
| Demoralizing Roar | Demoralisierendes Gebrüll | Clamor desmoralizador (esMX: Rugido desmoralizador) | Rugissement démoralisant | de: F-DB2 SpellName 99; es: DB2 wowf SpellName 99; fr: F-DB2 SpellName |  |
| Demoralizing Shout | Demoralisierungsruf | Grito desmoralizador | Cri démoralisant | de: F-DB2 SpellName 6190/11554/11555/11556 (max rank); es: DB2 wowf SpellName 1160; fr: F-DB2 SpellName | de: rank 1 (1160) reads "Demoralisierender Ruf"; same rule as Smite: the name most ranks and the max rank carry. UNCERTAIN |
| Shred | Schreddern | Triturar | Lambeau | de: F-DB2 SpellName 5221; es: DB2 wowf SpellName 3252 (lowest id of the name); fr: F-DB2 SpellName |  |
| Claw | Klaue | Zarpa | Griffe | de: F-DB2 SpellName 1082; es: DB2 wowf SpellName 1082; fr: F-DB2 SpellName |  |
| Lacerate | Aufschlitzen | Lacerar | Lacérer | de: F-DB2 SpellName 5422; es: DB2 wowf SpellName 5422; fr: F-DB2 SpellName |  |
| Berserk | Berserker | Rabia | Berserk | de: F-DB2 SpellName 1287747 (Forever row); es: DB2 wowf SpellName 23397; fr: F-DB2 SpellName |  |
| Clearcasting | Freizaubern | Conjuro libre (esMX: Lanzamiento libre) | Idées claires | de: F-DB2 SpellName 16870; es: DB2 wowf SpellName 16870/12536; fr: F-DB2 SpellName |  |
| Shredding Attacks | Schreddernde Angriffe | Ataques trituradores (esMX: Triturar mejorado) | Attaques lacérantes | de: F-DB2 SpellName 16966; es: DB2 wowf SpellName 16966; fr: F-DB2 SpellName | fr: talent |
| Bear Form | Bärengestalt | Forma de oso | Forme d’ours | de: F-DB2 SpellName 5487; es: DB2 wowf SpellName 5487; fr: F-DB2 SpellName | es: Dire Bear Form 9634: Forma de oso nefasto (esMX temible) |
| Cat Form | Katzengestalt | Forma felina | Forme de félin | de: F-DB2 SpellName 768; es: DB2 wowf SpellName 768; fr: F-DB2 SpellName |  |
| Starshards | Sternensplitter | Fragmentos estelares | Éclats stellaires | de: F-DB2 SpellName 10797; es: DB2 wowf SpellName 10797; fr: F-DB2 SpellName |  |
| Mind Flay | Gedankenschinden | Despelleje mental (esMX: Tortura mental) | Fouet mental | de: F-DB2 SpellName 15407; es: DB2 wowf SpellName 15407; fr: F-DB2 SpellName |  |
| Mind Blast | Gedankenschlag | Explosión mental | Attaque mentale | de: F-DB2 SpellName 8092; es: DB2 wowf SpellName 8092; fr: F-DB2 SpellName |  |
| Thunder Clap | Donnerknall | Trueno (esMX: Atronar) | Coup de tonnerre | de: F-DB2 SpellName 6343; es: DB2 wowf SpellName 6343; fr: F-DB2 SpellName |  |
| Mortal Strike | Tödlicher Stoß | Golpe mortal | Frappe mortelle | de: F-DB2 SpellName 12294; es: DB2 wowf SpellName 9347 (lowest id of the name); fr: F-DB2 SpellName |  |
| Rend | Verwunden | Desgarrar | Pourfendre | de: F-DB2 SpellName 772; es: DB2 wowf SpellName 772; fr: F-DB2 SpellName | de: 12054 "Zerfleischen" is an NPC spell |
| Recklessness | Tollkühnheit | Temeridad | Témérité | de: F-DB2 SpellName 1719; es: DB2 wowf SpellName 1719; fr: F-DB2 SpellName |  |
| Stance Dance | Haltungstanz | Baile de actitudes | Danse des postures | de: addons; es: lane; fr: Jargon | de: wowsims option name, not a spell. UNCERTAIN; es: a wowsims option name, not a spell; the label says "Baile de actitudes", the tooltip also names the wowsims option "Stance Dance"; fr: not a spell: the warrior habit of swapping stances (wowsims APL switch) |
| Shadow Brand | Shadow Brand | Shadow Brand | Marque de l’ombre | de: none; es: lane; fr: Recall | de: wowsims build name (Warlock.lua), no spell row; kept English like SM Ruin. UNCERTAIN; es: wowsims build name inside a priority label, no spell in DB2 wowf: kept verbatim; fr: not a spell: a wowsims Warlock build name (Shadow Bolt brand); uncertain, see report |
| Holy Shock | Heiliger Schock | Choque Sagrado | Horion sacré | de: F-DB2 SpellName 20473; es: DB2 wowf SpellName 20473; fr: F-DB2 SpellName |  |
| Smite | Göttliche Pein | Acometida (esMX: Punición) | Châtiment | de: F-DB2 SpellName 591/598/984; es: DB2 wowf SpellName 585; fr: F-DB2 SpellName | de: rank 1 (585) reads "Heilige Pein"; most ranks "Göttliche Pein". UNCERTAIN; es: retail esES says Castigo |
| Curse of the Elements | Fluch der Elemente | Maldición de los Elementos | Malédiction des éléments | de: F-DB2 SpellName 11723; es: DB2 wowf SpellName 11723 family; fr: F-DB2 SpellName |  |
| Curse of Recklessness | Fluch der Tollkühnheit | Maldición de Temeridad (esMX: Maldición de temeridad) | Malédiction de témérité | de: F-DB2 SpellName 704; es: DB2 wowf SpellName 704; fr: F-DB2 SpellName |  |
| Curse of Weakness | Fluch der Schwäche | Maldición de debilidad | Malédiction de faiblesse | de: F-DB2 SpellName 702; es: DB2 wowf SpellName 702; fr: F-DB2 SpellName |  |
| Frostfire | Frostfeuer | Pirofrío | Givrefeu | de: F-DB2 SpellName 401502 (Frostfire Bolt = Frostfeuerblitz); es: DB2 wowf SpellName 401502 "Descarga de Pirofrío"; fr: F-DB2 SpellName (Frostfire Bolt = « Éclair de givrefeu ») | de: priority name; "Frostfeuer" derived; es: the pack name; spell is Descarga de Pirofrío; fr: a priority name, cut from the spell |
| Shifting Power | Machtverschiebung | Poder cambiante | Puissance fluctuante | de: F-DB2 SpellName 1322605; es: DB2 wowf SpellName 1322605; fr: F-DB2 SpellName |  |
| Shadowform | Schattengestalt | Forma de las Sombras | Forme d’Ombre | de: F-DB2 SpellName 15473; es: DB2 wowf SpellName 15473; fr: F-DB2 SpellName | fr: rows mix « Forme d’ombre »/« d’Ombre »; Forever row 15473 reads « Forme d'Ombre » |
| Battle Stance | Kampfhaltung | Actitud de batalla | Posture de combat | de: F-DB2 SpellName 2457; es: DB2 wowf SpellName 2457; fr: F-DB2 SpellName |  |
| Berserker Stance | Berserkerhaltung | Actitud rabiosa | Posture berserker | de: F-DB2 SpellName 2458; es: DB2 wowf SpellName 2458; fr: F-DB2 SpellName |  |
| Defensive Stance | Verteidigungshaltung | Actitud defensiva | Posture défensive | de: F-DB2 SpellName 71; es: DB2 wowf SpellName 71; fr: F-DB2 SpellName |  |
| Heroic Strike | Heldenhafter Stoß | Golpe heroico | Frappe héroïque | de: F-DB2 SpellName 78; es: DB2 wowf SpellName 78; fr: F-DB2 SpellName |  |
| Cleave | Spalten | Mellar (esMX: Rajar) | Enchaînement | de: F-DB2 SpellName 845; es: DB2 wowf SpellName 845; fr: F-DB2 SpellName |  |
| Execute | Hinrichten | Ejecutar | Exécution | de: F-DB2 SpellName 5308; es: DB2 wowf SpellName 5308; fr: F-DB2 SpellName |  |
| Overpower | Überwältigen | Abrumar | Fulgurance | de: F-DB2 SpellName 7384; es: DB2 wowf SpellName 7384; fr: F-DB2 SpellName |  |
| Whirlwind | Wirbelwind | Huracán (esMX: Torbellino) | Tourbillon | de: F-DB2 SpellName 1680; es: DB2 wowf SpellName 1680; fr: F-DB2 SpellName |  |
| Bloodthirst | Blutdurst | Sed de sangre | Sanguinaire | de: F-DB2 SpellName 23881; es: DB2 wowf SpellName 23881; fr: F-DB2 SpellName |  |
| Slam | Zerschmettern | Embate | Heurtoir | de: F-DB2 SpellName 1464; es: DB2 wowf SpellName 1464; fr: F-DB2 SpellName |  |
| Sunder Armor | Rüstung zerreißen | Hender armadura | Fracasser armure | de: F-DB2 SpellName 7386; es: DB2 wowf SpellName 7386; fr: F-DB2 SpellName |  |
| Faerie Fire | Feenfeuer | Fuego feérico | Lucioles | de: F-DB2 SpellName 770; es: DB2 wowf SpellName 770; fr: F-DB2 SpellName |  |
| Moonfire | Mondfeuer | Fuegolunar (esMX: Fuego lunar) | Éclat lunaire | de: F-DB2 SpellName 8921; es: DB2 wowf SpellName 8921; fr: F-DB2 SpellName (« Eclat lunaire ») | fr: accent normalized |
| Rip | Zerfetzen | Destripar | Déchirure | de: F-DB2 SpellName 1079; es: DB2 wowf SpellName 1079; fr: F-DB2 SpellName |  |
| Rake | Krallenhieb | Arañazo | Griffure | de: F-DB2 SpellName 1822; es: DB2 wowf SpellName 1822; fr: F-DB2 SpellName |  |
| Ferocious Bite | Wilder Biss | Mordedura feroz | Morsure féroce | de: F-DB2 SpellName 22568; es: DB2 wowf SpellName 22568; fr: F-DB2 SpellName |  |
| Healthstone | Gesundheitsstein | Piedra de salud | Pierre de soins | de: F-DB2 SpellName 5720; es: DB2 wowf SpellName 5720; fr: F-DB2 SpellName |  |

Where to read this group: localized spellbook or DB2 spell name.

## Resources and stats

| enUS | deDE | esES | frFR | Source | Notes |
|---|---|---|---|---|---|
| Rage | Wut | Ira | Rage | de: F-GS RAGE; es: GS RAGE; fr: GS RAGE |  |
| Energy | Energie | Energía | Énergie | de: F-GS ENERGY; es: GS ENERGY; fr: GS ENERGY |  |
| Mana | Mana | Maná | Mana | de: F-GS MANA; es: GS MANA; fr: GS MANA |  |
| Focus | Fokus | Enfoque | Focalisation | de: F-GS FOCUS; es: GS FOCUS; fr: GS POWER_TYPE_FOCUS | es: the resource; the focus target is "foco" |
| Combo Points | Combopunkte | Puntos de combo | Points de combo | de: F-GS COMBO_POINTS_POWER; es: GS COMBO_POINTS; fr: GS COMBO_POINTS_POWER |  |
| Health | Gesundheit | Salud | Vie (prose: points de vie) | de: F-GS HEALTH; es: GS HEALTH; fr: GS HEALTH |  |
| Haste | Tempo | Celeridad | Hâte | de: F-GS SPELL_HASTE; es: GS STAT_HASTE; fr: GS STAT_HASTE |  |
| Cooldown | Abklingzeit | Tiempo de reutilización | temps de recharge | de: F-GS ITEM_COOLDOWN_TIME_SEC, SPELL_RECAST_TIME_SEC; es: GS COOLDOWN_REMAINING (esMX), SPELL_RECAST_TIME_MIN (esES "Reutilización"); fr: GS COOLDOWN_VIEWER_LABEL (« Gestionnaire de temps de recharge ») | de: "Abklingzeit" in prose and labels; plural Abklingzeiten; es: "TdR"/"CD" in chat; full word in prose, "reutilización" when short; fr: short form « recharge » where the full term is already clear (« en recharge », « balayage de recharge », « sortir de recharge »); « CD » in tight labels only |
| Global Cooldown | globale Abklingzeit (GCD) | Tiempo de reutilización global (GCD) | temps de recharge global (GCD) | de: F-GS OPTION_TOOLTIP_REDUCED_LAG_TOLERANCE; es: client UI (unverified); fr: Jargon + GS wording | de: "GCD" as the short form in tight labels, as players say it; es: players say "GCD"; prose uses "tiempo de reutilización global", short labels "GCD"; fr: French players say « GCD »; the full form in tooltips |
| Buff | Buff | Beneficio (esMX: Potenciación) | amélioration | de: addons; es: GS BUFFOPTIONS_LABEL, COOLDOWN_VIEWER_SETTINGS_TAB_BUFFS (esMX Potenciaciones); fr: GS COOLDOWN_VIEWER_SETTINGS_TAB_BUFFS (« Améliorations ») | de: client says "Stärkungszauber" (F-GS SHOW_BUFFS); German addons and players say Buff; too long for labels; es: players say "buff"; the client word ships |
| Debuff | Debuff | Perjuicio | affaiblissement | de: addons; es: GS BUFFOPTIONS_LABEL; fr: GS CAA_SAY_YOUR_DEBUFFS_FORMAT_NO_SPELLNAME | de: client "Schwächungszauber" (F-GS BUFFOPTIONS_LABEL); same reasoning; es: players say "debuff" |
| Stance | Haltung | Actitud | posture | de: F-GS TUTORIAL_TITLE61_WARRIOR (Kampfhaltungen), spell names; es: DB2 wowf (Actitud de batalla...); fr: F-DB2 (Posture de combat…) |  |
| Form | Gestalt | Forma | forme | de: F-DB2 Bärengestalt/Katzengestalt; es: DB2 wowf (Forma felina...); fr: F-DB2 (Forme d’ours…) |  |
| Talent | Talent | Talento | talent | de: F-GS TALENT; es: GS TALENTS; fr: GS TALENTS |  |
| Specialization (noun) | Spezialisierung | Especialización | spécialisation | de: F-GS SPECIALIZATION; es: GS SPECIALIZATION; fr: GS SPECIALIZATION | es: short "espec." where space is tight; fr: « spé » never in UI text |
| Level | Stufe | Nivel | niveau | de: F-GS GUILD_RECRUITMENT_LEVEL; es: GS LEVEL; fr: GS LEVEL | de: client short form "St." |
| Time to Die | Zeit bis zum Tod | Tiempo hasta morir | temps avant la mort | de: addons; es: lane; fr: Recall | de: TTD in tight labels; es: addons write "tiempo hasta morir" / TTD; fr: Hekili's TTD; French players say « TTD » or « temps restant » |

Where to read this group: localized client resource and stat names.

## Interface words the client already shows

| enUS | deDE | esES | frFR | Source | Notes |
|---|---|---|---|---|---|
| Enabled | Aktiviert | Activado | Activé | de: F-GS VIDEO_OPTIONS_ENABLED; es: client UI (unverified); fr: GS VIDEO_OPTIONS_ENABLED |  |
| Disable | Deaktivieren | Desactivar | Désactiver | de: F-GS DISABLE; es: GS DISABLE; fr: GS DISABLE |  |
| Cancel | Abbrechen | Cancelar | Annuler | de: F-GS CANCEL; es: GS CANCEL; fr: GS CANCEL |  |
| Reset | Zurücksetzen | Restablecer | Réinitialiser | de: F-GS RESET; es: GS RESET (esMX; esES client says Reiniciar); fr: GS RESET | es: Reiniciar is kept for Restart, so Restablecer serves both |
| Import | Importieren | Importar | Importer | de: F-GS HUD_EDIT_MODE_IMPORT_LAYOUT; es: client UI (unverified); fr: Recall |  |
| Export | Exportieren | Exportar | Exporter | de: addons; es: client UI (unverified); fr: Recall | de: no plain GS row; matches Importieren |
| Delete | Löschen | Eliminar | Supprimer | de: F-GS DELETE; es: GS DELETE; fr: Recall (client « Supprimer ») |  |
| Copy | Kopieren | Copiar | Copier | de: F-GS MENU_EDIT_COPY; es: client UI (unverified); fr: Recall |  |
| Apply | Übernehmen | Aplicar | Appliquer | de: F-GS APPLY; es: GS APPLY; fr: GS APPLY |  |
| Save | Speichern | Guardar | Enregistrer | de: F-GS SAVE; es: client UI (unverified); fr: Recall |  |
| Restart | Neu starten | Reiniciar | Recommencer | de: F-GS RESTART; es: client UI (unverified); fr: Recall | fr: the only use restarts the style-import wizard; the client RESTART (« Redémarrer ») is a program restart |
| Default | Standard | Predeterminado | Par défaut | de: F-GS DEFAULT; es: GS DEFAULT; fr: GS DEFAULTS |  |
| None | Keine | Ninguno | Aucun | de: F-GS NONE_KEY; es: GS NONE; fr: GS NONE | de: "Nichts" (NONE) where it stands alone for "no value"; fr: « Aucune » for a feminine noun |
| Left | Links | Izquierda | Gauche | de: F-GS HUD_EDIT_MODE_SETTING_AURA_FRAME_ICON_DIRECTION_LEFT; es: client UI (unverified); fr: Recall |  |
| Right | Rechts | Derecha | Droite | de: F-GS (same family); es: client UI (unverified); fr: Recall |  |
| Top | Oben | Arriba | Haut | de: F-GS HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_ICON_DIRECTION_TOP; es: client UI (unverified); fr: Recall |  |
| Bottom | Unten | Abajo | Bas | de: F-GS HUD_EDIT_MODE_SETTING_ENCOUNTER_EVENTS_ICON_DIRECTION_BOTTOM; es: client UI (unverified); fr: Recall |  |
| Center | Mitte | Centro | Centre | de: addons; es: client UI (unverified); fr: Recall | de: F-GS cooldown viewer uses "Zentral" in "Horizontal - Zentral" |
| Size | Größe | Tamaño | Taille | de: F-GS HUD_EDIT_MODE_SETTING_BAGS_SIZE; es: client UI (unverified); fr: GS FONT_SIZE (« Taille de la police ») |  |
| Width | Breite | Ancho | Largeur | de: F-GS HUD_EDIT_MODE_SETTING_CHAT_FRAME_WIDTH; es: client UI (unverified); fr: Recall |  |
| Height | Höhe | Alto | Hauteur | de: F-GS HUD_EDIT_MODE_SETTING_CHAT_FRAME_HEIGHT; es: client UI (unverified); fr: Recall |  |
| Position | Position | Posición | Position | de: addons; es: client UI (unverified); fr: Recall |  |
| Color | Farbe | Color | Couleur | de: F-GS COLOR; es: client UI (unverified); fr: Recall |  |
| Font | Schriftart | Fuente | Police | de: addons; es: client UI (unverified); fr: GS FONT_SIZE | de: F-GS FONT_SIZE = Schriftgröße |
| Outline | Umriss | Contorno | Contour | de: F-GS SELF_HIGHLIGHT_OUTLINE; es: client UI / addons; fr: GS SELF_HIGHLIGHT_OUTLINE |  |
| Thick Outline | Dicker Umriss | Contorno grueso | Contour épais | de: addons; es: addons; fr: Recall |  |
| Border | Rand | Borde | Bordure | de: F-GS EMBLEM_BORDER; es: client UI (unverified); fr: GS EMBLEM_BORDER |  |
| Alignment | Ausrichtung | Alineación | Alignement | de: F-GS HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_ORIENTATION; es: client UI (unverified); fr: Recall |  |
| Appearance | Darstellung | Apariencia | Apparence | de: F-GS APPEARANCE_LABEL; es: client UI (unverified); fr: Recall |  |
| Visibility | Sichtbarkeit | Visibilidad | Visibilité | de: F-GS HUD_EDIT_MODE_SETTING_COOLDOWN_VIEWER_VISIBLE_SETTING; es: client UI (unverified); fr: Recall |  |
| Advanced | Erweitert | Avanzado | Avancé | de: F-GS ADVANCED_LABEL; es: client UI (unverified); fr: GS ADVANCED_LABEL |  |
| Targets | Ziele | Objetivos | Cibles | de: addons; es: client UI (unverified); fr: GS STATUS_TEXT_TARGET (« Cible ») | de: plural of Ziel |
| Target | Ziel | Objetivo | Cible | de: F-GS TARGET; es: client UI (unverified); fr: GS STATUS_TEXT_TARGET |  |
| Focus (target) | Fokus | Foco | Focalisation | de: F-GS FOCUS; es: client UI (FOCUS unit); fr: GS FOCUS | de: "Fokusziel" (MINIMAP_TRACKING_FOCUS) where it must not read as the resource |
| Combat | Kampf | Combate | Combat | de: F-GS COMBAT; es: DB2 wowf TalentTab 181; fr: GS COMBAT | es: retail renamed it Outlaw (Forajido) |
| In Combat | Im Kampf | En combate | En combat | de: F-GS HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_IN_COMBAT; es: client UI (unverified); fr: GS …VISIBLE_SETTING_IN_COMBAT |  |
| Out of Combat | Außerhalb des Kampfes | Fuera de combate | Hors de combat | de: F-GS HUD_EDIT_MODE_SETTING_ACTION_BAR_VISIBLE_SETTING_OUT_OF_COMBAT; es: client UI (unverified); fr: GS …VISIBLE_SETTING_OUT_OF_COMBAT |  |
| Mounted | Beritten | Montado | sur une monture | de: addons; es: client UI (unverified); fr: Recall | de: F-GS MOUNT = Aufsitzen (the verb); fr: GS has « Monture » (noun); « Cacher sur une monture » |
| Interrupt | Unterbrechen / Unterbrechung | Interrupción (noun), interrumpir (verb) | Interruption | de: F-GS INTERRUPT, LOC_TYPE_INTERRUPT; es: GS INTERRUPT (verb); fr: GS LOC_TYPE_INTERRUPT; toggle « Interruptions » (GS INTERRUPTS) | de: verb on buttons, noun for the toggle (Unterbrechungen) |
| Cooldowns | Abklingzeiten | Reutilizaciones | Temps de recharge | de: F-GS (plural of Abklingzeit); es: lane (from "tiempo de reutilización"); fr: GS (Cooldown Manager wording) | es: the toggle of cooldown abilities; players say "CDs"; fr: the toggle; long label (17 chars) |
| Defensives | Defensive | Defensivas | Défensifs | de: addons, review-deDE; es: lane; fr: GS PET_DEFENSIVE (« Défensif ») | de: noun (plural), as toggle and display name ("Defensive aktivieren", Anzeige „Defensive“); adjective only in prose ("defensive Fähigkeiten"); fr: the toggle |
| Potion | Trank | Poción | Potion | de: F-DB2 item names (…trank); es: client UI (unverified); fr: Recall |  |
| Trinket | Schmuck (slot labels) / Schmuckstück (running text) | Abalorio | Bijou | de: F-GS TRINKET0SLOT, INVTYPE_TRINKET; es: GS INVTYPE_TRINKET (esMX Abalorio; current esES client says Alhaja); fr: GS TRINKET0SLOT | de: controller ruling: slot labels and dropdown entries use the client's "Schmuck" ("Schmuck #1"); prose keeps "Schmuckstück"; es: Abalorio is the older esES word too, so both regions read it; reviewers may prefer Alhaja |
| Toggles | Schalter | Interruptores | Bascules | de: addons; es: lane; fr: Recall | es: on/off switches; no client word; fr: Hekili's on/off toggles (Cooldowns, Interrupts…) |
| Keybinds | Tastenbelegung | Atajos | Raccourcis | de: F-GS KEY_BINDINGS (Tastaturbelegung) / addons; es: lane (GS KEY_BINDINGS esES "Configurar teclado", esMX "Teclado"); fr: GS KEY_BINDINGS | de: per-button binding text as Bartender4 deDE writes it; es: short label "Atajos"; prose "atajo de teclado" |
| Profile | Profil | Perfil | Profil | de: addons (AceDB deDE); es: client UI / Ace3; fr: Recall |  |
| Description | Beschreibung | Descripción | Description | de: F-GS DESCRIPTION; es: client UI (unverified); fr: Recall |  |
| Author | Autor | Autor | Auteur | de: addons; es: client UI (unverified); fr: Recall |  |
| Name | Name | Nombre | Nom | de: F-GS NAME; es: client UI (unverified); fr: Recall |  |
| Source | Quelle | Origen | Source | de: addons; es: lane; fr: Recall | es: "Fuente" is taken by Font |
| Active | Aktiv | Activo | Active (a priority / spec: feminine) ; Actif for a masculine noun | de: F-GS ACTIVE_PETS; es: client UI (unverified); fr: Recall | fr: agrees with its noun |
| Priority | Priorität | Prioridad | Priorité | de: addons; es: lane; fr: Recall |  |
| Pause | Pause | Pausa | Pause | de: F-GS EVENTTRACE_BUTTON_PAUSE; es: client UI (unverified); fr: GS QUEUED_STATUS_SUSPENDED (« En pause ») |  |
| Lock | Sperren | Bloquear | Verrouiller | de: F-GS LOCK_ACTIONBAR_TEXT (Aktionsleisten sperren); es: client UI (unverified); fr: GS LOCK |  |
| Unlock | Entsperren | Desbloquear | Déverrouiller | de: addons; es: client UI (unverified); fr: GS UNLOCK | de: F-GS UNLOCK "Freischalten" means unlocking content |
| Melee Range | Nahkampfreichweite | Alcance cuerpo a cuerpo | Allonge | de: F-GS MELEE_RANGE; es: client UI (unverified); fr: GS MELEE_RANGE | fr: « portée de mêlée » in prose |
| Range | Reichweite | Alcance | Portée | de: addons; es: client UI (unverified); fr: Recall |  |
| Alpha | Transparenz | Opacidad | Opacité | de: F-GS OPACITY; es: addons; fr: GS OPACITY | de: also for every "Opacity" key (one word for one concept; the client uses Transparenz for its opacity sliders) |
| Glow | Leuchten | Brillo | Lueur | de: addons; es: addons (WeakAuras); fr: Recall (believed WeakAuras frFR wording, not looked up) | fr: action-button glow; shorter than « Surbrillance », which stays only for the red range highlight |
| Icon | Symbol | Icono | Icône | de: F-GS SELF_HIGHLIGHT_ICON; es: client UI (unverified); fr: GS SELF_HIGHLIGHT_ICON |  |
| Display | Anzeige | Panel | Affichage | de: F-GS DISPLAY; es: lane; fr: GS DISPLAY_LABEL | es: Hekili's icon group ("Primary Display" = "Panel principal") |
| Notification | Benachrichtigung | Notificación | Notification | de: addons; es: client UI (unverified); fr: Recall |  |
| Nameplate | Namensplakette | Placa de nombre | Barre d’info | de: F-GS NAMEPLATES_LABEL (Namensplaketten); es: GS NAMEPLATES_LABEL; fr: GS NAMEPLATES_LABEL (« Barres d’info ») | es: "Show Enemy Nameplates" = "Mostrar placas de nombre de enemigos" (GS BINDING_NAME_NAMEPLATES esMX; esES binding "Placas de nombre: ver enemigos"); "Show All Nameplates" likewise; fr: « Barres d’info des adversaires » = BINDING_NAME_NAMEPLATES; « Montrer toutes les barres d’info » = BINDING_NAME_ALLNAMEPLATES |

Where to read this group: localized client UI (compare the game's own option screens).

## Addon jargon

| enUS | deDE | esES | frFR | Source | Notes |
|---|---|---|---|---|---|
| AOE | AoE | AoE | AoE | de: addons; es: addons; fr: Jargon | de: players say it; es: players say AoE; fr: French players say « AoE »; « zone » in prose where natural |
| Single Target | Einzelziel | Objetivo único | Mono-cible | de: addons; es: addons; fr: Jargon | de: the minimap mode abbreviation stays "ST" (German players say it; "EZ" is not used) |
| ETA | Restzeit | Tiempo | Délai | de: addons; es: native review (I16); fr: Recall | de: seconds until the pick is due; ETA is not German player usage. UNCERTAIN; es: "ETA" is not used in either region (reads as the Basque group in Spain); the tooltips say "los segundos que faltan" |
| Primary | Primär | Principal | Principal | de: addons; es: lane; fr: GS PRIMARY | fr: display and zone title (« affichage Principal »); in prose « l’icône principale » |
| Queued | Warteschlange (zone title); eingereiht (adjective) | En cola | En file | de: F-GS OPTION_TOOLTIP_REDUCED_LAG_TOLERANCE (anreihen); es: lane; fr: Recall | fr: the queued icons |
| Now | Jetzt | Ahora | Maintenant | de: addons; es: lane; fr: Recall |  |
| Next | Nächstes | Siguiente | Suivant | de: addons; es: lane; fr: Recall | de: zone title; compounds "Nächstes-Feld" (Timeline next box), "Jetzt-Kreis" (now circle); fr: zone and Timeline tab title; « case Suivant », « cercle Maintenant » |
| Lane | Spur | Carril | Piste | de: addons; es: lane; fr: Recall (native review, fix round 1) | fr: Timeline style lane; feminine (« la piste ») |
| Timeline | Zeitleiste | Línea temporal | Chronologie | de: addons; es: lane; fr: Recall |  |
| Forecast | Vorschau | Previsión | Prévision | de: addons; es: lane; fr: Recall |  |
| Pooling | Pooling / poolen | Acumular | Accumulation | de: addons; es: lane; fr: Jargon | de: one word for the concept in labels and prose ("Ressource poolen", "poolt das Addon Ressourcen"); "aufsparen" is no longer used; es: "acumular recursos"; fr: « accumuler » (pool resources) |
| Action List | Aktionsliste | Lista de acciones | Liste d’actions | de: addons; es: lane; fr: Recall |  |
| Action Pack | Aktionspaket | Paquete de acciones | Pack d’actions | de: addons; es: lane; fr: Recall |  |
| Modern | Modern | Moderno | Moderne | de: addons; es: lane; fr: Recall |  |
| Minor Cooldowns | Kleine Abklingzeiten | Reutilizaciones menores | Temps de recharge mineurs | de: F-GS + addons; es: lane; fr: Recall |  |
| Major Cooldowns | Große Abklingzeiten | Reutilizaciones mayores | Temps de recharge majeurs | de: F-GS + addons; es: lane; fr: Recall |  |
| wowsims.com (verbatim) | wowsims.com | wowsims.com | wowsims.com | de: verbatim; es: rule; fr: verbatim | es: never translated |
| PvE | PvE | JcE | JcE | de: verbatim; es: GS (JcE in 5 esES strings); fr: GS TRANSMOG_SET_PVE | es: the Spanish client writes JcE / JcJ |
| PvP | PvP | JcJ | JcJ | de: verbatim; es: GS PVP_ENABLED; fr: GS PVP_ENABLED |  |

Where to read this group: decide with the reviewer: the client's word, or English where players say it (AOE).

## Further terms the lanes settled

Terms found while translating that the table above does not list; each language uses its word everywhere.

| enUS | deDE | esES | frFR | Source | Notes |
|---|---|---|---|---|---|
| Cooldown Manager | Abklingzeitmanager | Gestor de tiempos de reutilización (esMX: Administrador de habilidades) |  | de: F-GS COOLDOWN_VIEWER_LABEL; es: GS COOLDOWN_VIEWER_LABEL | de: the game's Cooldown Manager; es: the game option Hekili points players at |
| Boss encounter | Bossbegegnung |  |  | de: addons (DBM deDE) |  |
| Spell | Zauber |  |  | de: F-GS SPELLS |  |
| Ability | Fähigkeit |  |  | de: F-GS ABILITIES |  |
| Item | Gegenstand |  |  | de: F-GS ITEMS |  |
| Pet | Begleiter |  |  | de: F-GS PET |  |
| Seconds | Sek. |  |  | de: F-GS LOSS_OF_CONTROL_SECONDS |  |
| Show / Hide | Anzeigen / Ausblenden |  |  | de: F-GS SHOW, HIDE |  |
| Options | Optionen |  |  | de: F-GS OPTIONS |  |
| General | Allgemein |  |  | de: F-GS GENERAL |  |
| Mode | Modus |  |  | de: F-GS MODE |  |
| Snapshot | Snapshot | Instantánea | instantané | de: addons; es: native review (I12); fr: Recall | de: the debug Snapshots page; players and Hekili users say Snapshot; es: "captura" alone reads as a screenshot; screenshot stays "captura de pantalla" |
| Warnings | Warnungen |  |  | de: F-GS PING_TYPE_WARNING (Warnung) |  |
| Spell queue window | Zauberwarteschlange |  |  | de: addons | de: client tooltip wording "neuen Zauber anreihen" (REDUCED_LAG_TOLERANCE) |
| Minimap | Minikarte |  |  | de: F-GS MINIMAP_LABEL |  |
| Raid / Party / Dungeon | Schlachtzug / Gruppe / Dungeon |  |  | de: F-GS RAID, PARTY, LFG_TYPE_DUNGEON |  |
| Off / On | Aus / An |  |  | de: F-GS OFF, TEXT_ON_TARGET_ON_LABEL |  |
| UI (interface) | UI |  |  | de: F-GS USE_UISCALE (UI-Skalierung) | de: "UI gesperrt", "dein UI neu laden" |
| Cooldown sweep / spiral | Spirale (Abklingzeit-Spirale) |  |  | de: addons | de: one word for Classic "Extend Spiral" and Timeline "Sweep" |
| Lane pick | Symbol |  |  | de: addons | de: the predicted abilities on the Timeline lane |
| Cooldowns (one word) | Abklingzeiten |  |  | de: F-GS | de: "Kleine/Große Abklingzeiten" everywhere, also the Require Toggle dropdown; "CD" survives only as the abbreviation in the minimap status text (%sCD, %skCD) |
| Stance Dance / Rend Weave | Haltungstanz / Verwunden-Weaving |  |  | de: addons | de: wowsims option names. UNCERTAIN |
| Turret (Hunter builds) | Turret |  |  | de: addons | de: wowsims build name, players say it |
| battlefield (non-PvP) | Kampfgebiet |  |  | de: review-deDE | de: "Schlachtfeld" is the PvP battleground in the client |
| Ctrl key | STRG |  |  | de: F-GS CTRL_KEY_TEXT | de: "STRG+A", "STRG+C" |
| names in messages | „%s“ |  |  | de: review-deDE | de: German quotes for names; '...' only around typed commands ('/hekili help', 'on'/'off', 'cycle', a typed mode) |
| training dummy | Trainingsattrappe |  |  | de: review-deDE (client "-attrappe", SpellName 3932 Zielattrappe) | de: NPC name not verified in this build |
| dungeon pack | Pack (im Dungeon) |  |  | de: review-deDE | de: "Gruppe" is the player's own party |
| Maul |  | Machaque (esMX: Magullar) |  | es: DB2 wowf SpellName 6807 | es: extra (in pack strings) |
| Growl |  | Bramido |  | es: DB2 wowf SpellName 6795 | es: extra |
| Combat |  | Combate |  | es: client UI (unverified) |  |
| Screenshot |  | Captura de pantalla |  | es: native review (I12) |  |
| proc |  | proc |  | es: native review (I13, I14) | es: players in both regions say "proc"; no client word ("Brillo de proc") |
| Gamepad |  | Gamepad |  | es: native review (I17) | es: esES client "Mando", esMX "Control"; "gamepad" reads the same in both |
| Turret |  | en torreta |  | es: native review (I15) | es: apposition keeps gender agreement: "Puntería en torreta (wowsims.com)" |
| Unpause |  | Reanudar / REANUDADO |  | es: native review (M1) | es: one wording for the state |
| tooltip |  | tooltip |  | es: native review (M12) | es: esES/esMX GlobalStrings both use "tooltip"; "descripción emergente" is esMX-only |
| switch |  | opción |  | es: native review (M18) | es: "interruptor" stays reserved for Hekili's Toggles |
| focus (Timeline focus ability, focus=N, Focus Tier) |  |  | mise en avant (« technique mise en avant », « niveau de mise en avant ») | fr: Recall | fr: not « focalisation », which is the focus target and the hunter resource |
| pick (Timeline lane) |  |  | choix | fr: Recall |  |
| now circle / next box |  |  | cercle Maintenant / case Suivant | fr: Recall |  |
| Caption |  |  | légende | fr: Recall |  |
| queue (icon queue) |  |  | file | fr: Recall | fr: « icônes en file » |
| Target Swap |  |  | changement de cible | fr: Recall |  |
| Damage Cooldowns |  |  | temps de recharge offensifs | fr: Recall |  |
| Minor CDs (short label) |  |  | CD mineurs | fr: Jargon |  |
| yards |  |  | mètres | fr: Recall (French client tooltips write « m »; not looked up) |  |
| Stealth (bars) |  |  | camouflage | fr: F-DB2 SpellName 1784 « Camouflage » |  |
| Night Elf |  |  | elfe de la nuit | fr: Recall (client race name) |  |
| SM Ruin |  |  | SM Ruin (verbatim) | fr: owner ruling, fix round 1 | fr: wowsims build name |
| Shadow Brand |  |  | Shadow Brand (verbatim) | fr: owner ruling, fix round 1 | fr: wowsims build name, not the spell « Marque de l’ombre » |
| Rend Weave |  |  | Intercaler Pourfendre | fr: native review, fix round 1 | fr: wowsims APL switch name |
| Turret / Melee (Hunter build) |  |  | en tourelle / en mêlée | fr: Jargon (native review) | fr: « Survie en tourelle », « Survie en mêlée » |
| Now / Next colour (Action Bar Glow) |  |  | Couleur Maintenant / Couleur Suivant | fr: controller ruling, fix round 1 | fr: names the display slots |
| NOT BOUND |  |  | PAS D’ASSOCIATION | fr: GS NOT_BOUND (« Pas d'association ») |  |
| damaged (enemies) |  |  | touchés | fr: native review | fr: « ennemis touchés » |
