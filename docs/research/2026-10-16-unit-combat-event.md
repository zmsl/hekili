# UNIT_COMBAT on a Midnight-API client (Forever 1.60.1)

Date 2026-10-16. Tags: MEASURED (our probe in-game), DOCUMENTED (API docs / Blizzard source / wiki), INFERRED.

## Short answer
UNIT_COMBAT(unitTarget, event, flagText, amount, schoolMask) is victim-side and source-agnostic: it reports what happened TO the unit
in position 1, whoever caused it. All five args arrived PLAIN (non-secret) in combat on the Forever client for target, player, nameplateN
and targettarget/softenemy/softinteract (MEASURED, solo level-21 Warrior, 779 firings, 0 secret, 752 in combat). That others' damage
on `target` is included is INFERRED from victim-side semantics + wiki wording; our probe was solo (no third-party attacker), so it did
not directly test it.

## 1. Which tokens, whose damage
- DOCUMENTED: payload `unitTarget: UnitTokenVariant, event, flagText, amount, schoolMask`, SynchronousEvent. Forever API data (wow_api_event_search flavor=forever);
  Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:4168-4170 (forever), :4045 (mainline).
- DOCUMENTED: wiki: "fires when an npc or player participates in combat and takes damage", unitTarget = affected unit. https://warcraft.wiki.gg/wiki/UNIT_COMBAT
  (page lists Midnight 12.1.5 build 69848 plus Forever, Mists, TBC, Vanilla; no restriction or secret note; last edit 2026-08-13).
- DOCUMENTED (Blizzard UI use): only the player/pet frames consume it: PlayerFrame.lua:74 `RegisterUnitEvent("UNIT_COMBAT","player","vehicle")`, :121-125
  `if arg1 == self.unit then CombatFeedback_OnCombatEvent(self, arg2, arg3, arg4, arg5)`; PetFrame.lua:47 (`"pet","player"`), :107-111. Paths under
  Interface/AddOns/Blizzard_UnitFrame/Mainline/ (forever grep). Forever's UI tree has no TargetFrame/party use of UNIT_COMBAT (grep found 5 matches total, same files).
  Blizzard does not show target feedback, but the event itself is not limited to those tokens (see MEASURED).
- DOCUMENTED: CombatFeedback_OnCombatEvent (Blizzard_FrameXML/Mainline/CombatFeedback.lua:26-95) shows the vocabulary: IMMUNE, WOUND (amount; amount 0 + flag ABSORB/BLOCK/RESIST
  = fully mitigated, else MISS), BLOCK, HEAL, ENERGIZE, plus INTERRUPT/EVADE/DEFLECT/REFLECT/DODGE/PARRY text table (:6-18); flags CRITICAL, CRUSHING, GLANCING, BLOCK_REDUCED. It does arithmetic-free display only (BreakUpLargeNumbers).
- MEASURED (docs/research/2026-10-14-probe-session-O-results.md section 3, lines 43-78; row O1 line 26): per bucket firings (in combat): target 374 (370), player 165 (162),
  nameplate 63 (47), other tokens targettarget/softinteract/softenemy 177 (173). Victim-side: "the token is the unit that was hit or healed, there is no source";
  "with other attackers on the same target the events mix" (that sentence is the report's reasoning, group content "not measured here").
- MEASURED: target saw WOUND, MISS, PARRY, HEAL, DODGE; nameplate saw WOUND, MISS, DODGE, PARRY; HEAL seen on target and player (heals on units we hold a token for appear).
- INFERRED: third-party damage on a token we hold is included (the client emits per victim; no filter on attacker is documented). Not probed in a group.
  Third-party hits on units with no token are not observable (docs/research/2026-10-14-virtual-combat-log-events.md line 12, row C8 line 97).

## 2. History and Midnight secrecy
- DOCUMENTED: wiki "Added in 1.0.0 / 1.13.2" (https://warcraft.wiki.gg/wiki/UNIT_COMBAT, via search snippet). No page found on the wiki, wowpedia or forums that documents
  the amount arg being removed/restored; I could not confirm the WotLK removal claim. NOT FOUND, treat as unknown. Blizzard forum opinion that only player/pet frames use it:
  https://us.forums.blizzard.com/en/wow/t/unit-combat-event/385243 (user opinion, not official).
- DOCUMENTED: the UNIT_COMBAT entry in UnitDocumentation (forever :4168) carries no SecretWhen*/SecretReturns fields, only Name/LiteralName/SynchronousEvent/Payload (grep context).
  Ketho's older annotation copy also has 0 "Secret" strings in UnitDocumentation.lua (~/.vscode-server/extensions/ketho.wow-api-0.22.3/Annotations/Core/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) - that copy is probably pre-secrets, weak evidence.
  Caveat from CLAUDE.md: the docs under-report secrecy, so the measurement is the real evidence.
- DOCUMENTED: Midnight restrictions target COMBAT_LOG_EVENT_UNFILTERED / combat log parsing and aura data (https://github.com/Xerrion/DragonShout/issues/28,
  https://www.icy-veins.com/wow/news/blizzard-relaxing-more-addon-limitations-in-midnight/). Searches found no statement either way for UNIT_COMBAT. Absence of evidence only.
- MEASURED: Forever, in combat, 0 of 779 firings secret/nil in any position (probe O1). Contrast: COMBAT_TEXT_UPDATE details are secret (O2, line 66-70).
  Amounts not checked against ground truth (line ~62: "not checked against a ground truth").
- UNMEASURED: retail Midnight 12.x (not the Forever client) behavior in instanced content (M+/boss encounters) where retail restrictions are strictest; Forever probe was open world, solo.
  Only the secret-value predicate `issecretvalue()` can be trusted at runtime, so guard anyway.

## 3. Classic Era vs Forever
- DOCUMENTED: wiki lists the event for Vanilla/TBC/Mists/Forever/Midnight with one payload; wow_api_event_search flavor=forever shows the same 5 args. No difference found.
- Forever's Blizzard UI is the Mainline tree (paths contain /Mainline/) so Blizzard usage matches retail. Nothing Forever-specific documented; Classic Era 1.15 not separately checked.
- MEASURED Forever specifics: event strings seen WOUND, MISS, PARRY, DODGE, HEAL, BLOCK; flags CRITICAL, GLANCING, CRUSHING, BLOCK, BLOCK_REDUCED; school numbers 1, 2, 8, 32. Not seen: IMMUNE, RESIST, ABSORB, REFLECT, EVADE, DEFLECT, INTERRUPT, ENERGIZE.

## 4. Caveats
- MEASURED: duplicates per token. One hit fires once per token resolving to the unit; `player` and `targettarget/softenemy/softinteract` buckets repeated identical amounts in the same order (17,18,20,19,0,16) (probe O section 3, "One hit can appear under several tokens"). Dedupe by resolved GUID or time/content. Same effect for casts.
- MEASURED: nameplateN fires (63 firings), also for nameplate tokens that equal target (INFERRED duplicate with target; not isolated).
- NOT MEASURED: pets as victims other than via `pet` token (Blizzard registers "pet", PetFrame.lua:47); DoT ticks and environmental damage as WOUND (rows C51/C52/C60 of virtual-combat-log-events.md say not isolated); group content; IMMUNE/RESIST/ABSORB vocabulary.
- Not source-attributed: no source GUID/name; ours vs others' mix on shared target.
- Healing on other units: HEAL shows for units we hold a token for (MEASURED on target/player); heals on units without a token are not visible.
- Secret-safety: amount arrived as a Lua number, but guard with issecretvalue() per project rule.
