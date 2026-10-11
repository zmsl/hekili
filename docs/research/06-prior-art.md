# R6: Prior art (Hekili's end, Midnight-era rotation helpers, Forever combat addons, Catnip)

Researched 2026-10-11. Tags used below: **[verified-by-Catnip]** means Catnip's author tested it in the Forever client (dated in their doc). **[source]** means a third-party claim. **[read]** means I read it in code or on a page myself.

## Summary

- **Hekili never tried to adapt.** The repo has no `issecretvalue`, `C_Secrets` or duration-object code. The last functional commit was 2025-11-01 (TOC for 11.2.5). On 2026-01-20 the README "Goodbye" said only that "the new direction with Blizzard's API makes it impossible to continue the addon in a way that would meet our design goals and quality standards". GitHub issues add nothing technical: a collaborator says it "never can be" compatible. The concrete blockers are implied by Hekili's architecture and match Blizzard's design:
  - the combat log is gone (Hekili's `Events.lua` CLEU handler);
  - auras, power and cooldown times are secret, and a simulator needs real numbers to fast-forward state;
  - Blizzard's stated goal is "Addons should no longer offer a competitive advantage in WoW combat."
- **Every surviving Midnight "rotation helper" wraps `C_AssistedCombat`.** MaxDps (retail path), HekiLight, JustAC, Knickili, Simple Assisted Combat Icon and NextGCD all show Blizzard's suggestion. None of them computes a rotation from combat state. HekiLight's "queue" is not a prediction: it is `GetRotationSpells()` filtered by cooldown and usability. WeakAuras discontinued Midnight support.
- **On Forever, the working pattern is display-only.** Catnip, Blood in the Water, ForeverAuras (a WeakAuras fork, GPLv2), Forever Cooldown Manager (MIT), EllesmereUI (Forever branch) and Cooldown Manager Centered (Forever build) all do the same thing: they hand secrets to engine-side widgets (StatusBar, Cooldown, AuraContainer, curves, duration objects) and never branch on them in Lua.
- **Some state is readable in combat, and that is what a Forever predictor could stand on** (all [verified-by-Catnip]):
  - own casts (`UNIT_SPELLCAST_*`, `SPELL_UPDATE_COOLDOWN` arg1 spell ID);
  - the cooldown flags `isActive`/`isOnGCD`/`isEnabled`;
  - `PLAYER_SWING` duration;
  - `C_Spell.GetSpellPowerCost`, which drops to 0 under Clearcasting;
  - `C_Spell.IsSpellUsable`;
  - `IsCurrentSpell`;
  - restriction-state events.

  What is *not* readable: energy, combo points via `GetComboPoints`, any aura (all Druid spells report `ShouldSpellAuraBeSecret` = true), cooldown remaining times, and the combat log.
- **Catnip:** it has no LICENSE file in the repo, although CurseForge shows MIT. There are 0 issues and 0 PRs, 1 fork, 125 commits between 2026-09-27 and 2026-10-10, and it reached 1.0.0 on 2026-10-10. `docs/api-research.md` is the best Forever secrets reference found anywhere. Collaboration looks feasible but there's no structure for it: issues are enabled, there's no CONTRIBUTING file, and the author describes it as "a mostly AI-built side project".

## Findings

### 1. Hekili's own record

- **README "Goodbye" (commit 36daec38, 2026-01-20, syrifgit):** "The Hekili Project on Retail WoW has ended with the launch of the Midnight prepatch, version 12.0, on January 20th 2026. The new direction with Blizzard's API makes it impossible to continue the addon in a way that would meet our design goals and quality standards." No technical detail is given.
- **Last code:** commit e6918a96 (2025-11-01, "TOC"). The CurseForge latest file is v11.2.5-1.0.0 (Nov 1 2025), and the page says only "Hekili is not compatible with the Midnight (12.0) expansion."
- **Issues:**
  - #5337 (2025-10-06) "is Hekili dead in midnight?" A non-member answered: "It's well documented no, there won't be Hekili in midnight."
  - #5354 (2026-01-22): collaborator syrifgit wrote "Correct, the addon is not compatible with midnight and never can be due to blizzards API Changes."
  - Searches for "secret", "combat log" and "addon restrictions" found no maintainer design discussion. GitHub Discussions are not used. The detailed reasoning probably happened on Discord, which I did not access.
- **What "impossible" means for Hekili's design** (my inference from the code plus Blizzard's post):
  - Hekili's `Events.lua:2016` registers CLEU for its whole state model (auras applied by the player, travel times, target counts). The combat log is removed in 12.0.
  - The APL simulator needs numeric energy, buff remains, cooldown remains and debuff remains, so it can advance virtual time. All of these are secret in combat.
  - Blizzard's explicit goal is to stop addons "collapsing a nuanced combat decision into a simple binary." A Hekili-quality predictor is exactly what the system is designed to stop.

### 2. Midnight-era rotation helpers and Blizzard policy

- **Blizzard policy** ("Combat Philosophy and Addon Disarmament in Midnight", Ion Hazzikostas):
  - "Addons should no longer offer a competitive advantage in WoW combat."
  - Combat state is a "secret value" that addons can display but not "know". Addons can change how the black box looks but "can't … look inside the box."
  - The post cites Assisted Highlight and One-Button Rotation (11.1.7) as the sanctioned learning and accessibility tools.
  - Concessions in the post: "we recently made all class secondary resources fully non-secret". "New API hooks" are also mentioned.
  - The warcraft.wiki 12.0 API page adds two more:
    - "the player's own spellcasts will no longer be secret (even in combat)";
    - specific spells and auras can be flagged NeverSecret.
- **MaxDps (kaminaris/MaxDps):** active, v11.3.52 released 2026-10-06, TOC 120100.
  - On retail, `InvokeNextSpell` calls `C_AssistedCombat.GetNextCastSpell(false)` (Core.lua ~801) unless the user enabled a custom rotation.
  - It applies small hand-written overrides that use non-secret data, for example Holy Power == 5 → Shield of the Righteous (Core.lua ~813).
  - It sets the `assistedCombatIconUpdateRate` CVar out of combat.
  - It has no Forever detection: it uses `WOW_PROJECT_ID` checks only.
- **HekiLight (meruuke/HekiLight, MIT, retail only, ~39k downloads, v0.6.6 Aug 2026):** "built from scratch on top of Blizzard's own C_AssistedCombat API"; "Blizzard controls the rotation logic… You cannot customise the APL." Slot 1 is `GetNextCastSpell`. Slots 2..n are `GetRotationSpells()` split into off-cooldown and on-cooldown passes (HekiLight.lua:910-975). That is availability, not a sequence prediction.
- **Other C_AssistedCombat wrappers (CurseForge):** Just Assisted Combat (v4.57.0, 12.0.x), Knickili, Simple Assisted Combat Icon, NextGCD, Rotato (scans for Blizzard's action-bar highlight).
- **Other helpers:** I could not determine ConRO's Midnight status (no repo found; searches returned nothing). HardcoreRotation targets Classic Era 1.15, not Forever.
- **WeakAuras:** no Midnight version (announced ~Oct 2025, reaffirmed Nov 28 2025): "a tool like WeakAuras is fundamentally incompatible with Blizzard's vision for addons". The team says Blizzard's loosenings (color curves, declassified secondary resources, own casts) are not "any kind of significant walkback". Community forks (m4tjz/WeakAuras2-for-Midnight, ForeverAuras) exist.

### 3. Forever-specific addons

`C_AssistedCombat` exists in the Forever API docs: `IsAvailable`, `GetActionSpell`, `GetNextCastSpell(checkForVisibleButton)` (secretArguments AllowedWhenUntainted), `GetRotationSpells`, and the `C_ActionBar.*AssistedCombat*` helpers. It is **unknown whether Blizzard ships rotation data for Forever's vanilla classes.** Forever Cooldown Manager says Blizzard's Cooldown Manager "still has no spell data for Forever classes", which suggests the Assisted Combat data may be missing too.

| Addon | Where | Key secret-handling technique |
|---|---|---|
| **Catnip** (Durts) | github.com/DurtsGaming/Catnip; CurseForge project 1729177 | See §4 |
| **Blood in the Water** (Forever Feral) | Not found on CurseForge or GitHub by search; Catnip's author has it installed locally (not installed on this machine) | Origin of AuraContainer usage; colour curve → `SetTextColor` on secret power; combo dots as StatusBars fed the raw secret; `curve:Evaluate(secret)` errors in combat |
| **EllesmereUI** (Forever branch) | github.com/EllesmereGaming/EllesmereUI | `EllesmereUI.IS_FOREVER` is decided from the TOC number, not `WOW_PROJECT_ID`. GCD spell is 29515 on Forever vs 61304 on retail (PR #2240, merged 2026-09-26: "`C_Spell.GetSpellCooldown(61304)` returns nil on Forever"). On secret GCD it calls `GetSpellCooldownDuration` → `SetCooldownFromDurationObject`, gated on readable `isActive`. Alpha and colour curves through `UnitPowerPercent`. Swing via `PLAYER_SWING` (PR #2150) |
| **ForeverAuras** (neroxrw) | github.com/neroxrw/foreverauras, GPL-2.0, WeakAuras2 fork (plus M33kAuras code), v0.74.4 on 2026-10-11, very active | `C_Secrets.ShouldSpellCooldownBeSecret` chooses an exact timer or a 0.1s `isActive` poll. A `Secrets.lua` restriction-state tracker. `GetSpellCooldownDuration(id, true)` gives a GCD-free duration. `EvaluateRemainingDuration(curve)` and `EvaluateColorValueFromBoolean` give looks driven by secrets. Radial StatusBar `SetTimerDuration`. AuraContainer `SetDurationText`/`SetDurationBar` |
| **Forever Cooldown Manager** (Thunderz96) | curseforge forever-cooldown-manager; github.com/Thunderz96/ForeverCDM (MIT, 0.8.0, 2026-09-26) | "display only. It never casts, never picks a spell for you"; passes hidden timings to Blizzard's cooldown widget. Others' buffs show "?" in combat |
| **Cooldown Manager Centered** (WilduTools) | CurseForge; Forever 1.60.1 build is the same zip as retail (v5.8.0, 2026-10-11) | Skins and extends Blizzard's CDM. Moving AuraContainer frames in combat is blocked |
| **ThreatPlates** | github.com/Backupiseasy/ThreatPlates (13.1.0 rebuilt auras on 12.1.0 AuraContainer) | Cast bar from `UnitCastingDuration`/`UnitChannelDuration` duration objects; `GetRemainingDuration()` → `string.format` |
| **EnhancedCooldownManager** (argium) | GitHub | Reads Blizzard CDM viewer children by `cooldownInfo.spellID` and `IsShown()` |
| Others seen | ForeverMeter (uses Blizzard's meter API, CLEU forbidden), Forever_DruidManaBar, hatterstea/foreverauras (DoT trackers for warlock/druid) | Display only |

No Forever rotation helper or predictor exists that I could find.

### 4. Catnip repo

- **License:** no LICENSE file in the repo (checked a clone at HEAD, 2026-10-10). The CurseForge page lists **MIT**. `CLAUDE.md` says "Blizzard's addon rules for Forever: free, with visible (non-obfuscated) code." Ask the author to add a LICENSE file to make reuse formal.
- **Activity:**
  - repo created 2026-09-27; 125 commits, all by Durts; last push 2026-10-10 (v1.0.0, "out of beta");
  - 1 star, 1 fork (JoeyMckenzie/Catnip-Fork);
  - 0 issues and 0 PRs ever; issues enabled, discussions off;
  - 58 CurseForge downloads; releases are automated (GitHub Actions plus the BigWigs packager).
- **Collaboration signals:** there is no CONTRIBUTING file. `CLAUDE.md` describes "a mostly AI-built side project; the owner is an experienced engineer but new to addon development (formerly a WeakAuras power user)". The docs carry dated, verified claims and say "When something new is verified or disproved, update this file", which matches our working style. Practical ways to collaborate:
  - file issues or PRs that add verified facts to `docs/api-research.md`;
  - share probes.

  Catnip is a HUD, not a predictor, so there is no feature overlap.
- **Credits:** there is no formal credits section in the README or on CurseForge. The credits live in `docs/architecture.md` "Reference addons" (EllesmereUI, CMC, Forever Cooldown Manager, Blood in the Water, EnhancedCooldownManager, ForeverAuras) and in the `api-research.md` Sources. ThreatPlates is cited in `Cast.lua:10` and api-research:34.
- **`docs/api-research.md` key facts** (quoted or condensed, with line numbers in the clone):
  - Design rule (L14): "Catnip can *display* combat data but not *decide* things from it. 'Fill a bar with energy' works; 'glow when energy > 40' doesn't."
  - Widgets that accept secrets [verified 2026-09-27] (L8): `StatusBar:SetValue/SetMinMaxValues`, `FontString:SetText`, `string.format`. `Cooldown:SetCooldown` rejects them (L10); use `GetSpellCooldownDuration` → `SetCooldownFromDurationObject`.
  - When restrictions apply (L13, L45):
    - combat (including the open world and dummies), encounters, M+ and PvP;
    - **in battlegrounds auras are secret even out of combat**, so `InCombatLockdown()` is not a safe gate;
    - use the `C_Secrets.Should*BeSecret()` functions instead.
  - Energy, rage and mana are secret (L27). Thresholds are possible only with a step `C_CurveUtil` curve evaluated C-side by `UnitPowerPercent(unit, type, false, curve)` and fed straight to `SetAlpha` (L28). `UnitPowerPercent(..., CurveConstants.ScaleTo100)` → `string.format` works for display [verified].
  - Combo points (L30): `UnitPower(ComboPoints)` is readable in combat but does not reset on target death or switch (Forever has per-target classic combo points). `GetComboPoints("player","target")` is **secret** in combat (BitW).
  - Spell costs (L36) [verified 2026-10-09]: `C_Spell.GetSpellPowerCost` is "Readable in combat, and reflects Clearcasting… Shred's `costs[1].cost` read 60, turned 0 on the `UNIT_AURA`… `C_Spell.IsSpellUsable` follows it too."
  - Cooldowns (L38, L125):
    - `startTime`/`duration` are secret; `isOnGCD`, `isActive`, `isEnabled` are readable;
    - "`isActive and isOnGCD ~= true` is a real cooldown" [verified 2026-10-10];
    - `IsZero()` on duration objects is secret in combat.
  - GCD (L70-74, L127):
    - spell 29515, not 61304;
    - its length can be measured in combat by polling `isActive` each frame (1.50s, or 0.99s in Cat);
    - out of combat the numbers are plain, so Catnip learns per-spell GCD lengths.
  - Events (L126, L128):
    - `SPELL_UPDATE_COOLDOWN` arg1 is always a spell ID, 0.1-0.17s before `UNIT_SPELLCAST_SENT/SUCCEEDED`;
    - `ADDON_RESTRICTION_STATE_CHANGED` and `PLAYER_IN_COMBAT_CHANGED` exist;
    - `UNIT_SPELLCAST_SUCCEEDED` spell IDs are readable (L35);
    - `PLAYER_SWING(duration, slot)` is readable (L32).
  - Auras (L44-47, L66):
    - `GetPlayerAuraBySpellID` **returns nil** in combat, which looks exactly like "not up";
    - `GetAuraDataByIndex` errors;
    - `UNIT_AURA` payload is secret, but the event still fires;
    - `ShouldSpellAuraBeSecret` is true for **every** Druid spell in combat ("No Druid aura is readable in combat").
  - AuraContainer (L53-66) [verified]:
    - the engine shows matching auras;
    - containers can't be created in combat;
    - buttons are forbidden after setup;
    - register your own widgets via `SetDurationCooldown`/`SetIcon`/`SetApplicationCount`/`AddPandemicRegion`;
    - per-spell groups give a priority-ordered, gapless display without Lua knowing which are up.
  - Dead ends (L170-184):
    - a cast-event timer for Rip ("guessed the duration, lost track on target switches");
    - `addedAuras`/`auraInstanceID` matching;
    - spell-activation overlay events for Clearcasting;
    - the combat log;
    - talent detection via `GetTalentInfo` (absent).
  - Forever quirks:
    - characters have two names, so key data by GUID;
    - `SetCVar` from addon code can taint chat;
    - `MainActionBar` replaces `MainMenuBar`.

### 5. Synthesis: proven patterns under secrets and what they mean for a Hekili-style predictor

**Proven for display (engine-side, no Lua decision):**
1. Secret → widget: `StatusBar:SetValue`, `FontString:SetText`/`string.format`.
2. Duration objects: `C_Spell.GetSpellCooldownDuration(id[, ignoreGCD])`, `UnitCastingDuration` → `Cooldown:SetCooldownFromDurationObject`, or `StatusBar:SetTimerDuration`, including radial bars.
3. Curves: step or colour curves through `UnitPowerPercent(..., curve)`, `duration:EvaluateRemainingDuration(curve)` and `EvaluateColorValueFromBoolean` → `SetAlpha`/colour. These give visual thresholds that Lua never sees.
4. AuraContainer: the engine filters auras and drives our registered widgets. With per-spell groups it can even order its own display.
5. Cooldown Manager child reads (`IsShown()` by `cooldownInfo.spellID`): this works, but Forever's CDM lacks class data.
6. `C_AssistedCombat.GetNextCastSpell`: proven on retail (MaxDps, HekiLight). Unknown on Forever.

**Readable in combat, so usable for Lua decisions** ([verified-by-Catnip] unless noted):
- own cast events and spell IDs;
- `SPELL_UPDATE_COOLDOWN` spell IDs;
- `isActive`, `isOnGCD` and `isEnabled`, which give "ready vs on real cooldown" (binary);
- spell cost, which reveals Clearcasting up or down;
- `IsSpellUsable` (it follows the Clearcasting cost; **whether its `insufficientPower` return is readable for energy is untested**, but if it is, it is a per-spell energy threshold);
- `IsCurrentSpell` (Maul queued);
- `PLAYER_SWING` duration;
- swing range;
- restriction-state events;
- out-of-combat everything, which allows learning GCD lengths and cooldown durations.

**Not readable:**
- energy value;
- combo points on the current target (`GetComboPoints`; the `UnitPower` variant is stale across targets);
- buff and debuff presence or remaining time, including Rip, Rake and Tiger's Fury;
- cooldown remaining;
- the combat log, including target counts.

**Implications:**
- A faithful Hekili port (APL plus forward simulation over numeric state) is not possible on Forever's API. This is the same wall that ended Hekili on retail, and it is intended by Blizzard.
- What remains possible: a "reconstructed state" predictor.
  - It would track own casts, use readable binary flags (ready/not ready, usable/not usable, Clearcasting) and keep durations learned out of combat.
  - It would infer DoT and buff timers and combo points from cast events.
  - Catnip tried cast-timed Rip and abandoned it because of target switches and guessed durations. Feral's simple vanilla kit makes this more tractable than retail, but it can be wrong about energy ticks, misses, dodges and target changes, and there is no combat log to correct it.
- Any recommendation would be a Lua decision built on inferred, not secret, data. That is technically allowed (only secrets are blocked), but it runs against Blizzard's stated philosophy. That is a policy risk, not an API block.
- The lowest-risk option is a `C_AssistedCombat` wrapper (HekiLight model) if Forever ships rotation data. A hybrid is also possible: Blizzard's suggestion plus engine-side curve or AuraContainer overlays (energy thresholds as alpha, DoT pandemic regions). That stays display-only but cannot sequence multiple steps ahead.

## Evidence

- Hekili README Goodbye: `README.md:1-3`, commit 36daec38 (2026-01-20). Last code commit e6918a96 (2025-11-01). CLEU dependency: `Events.lua:1710-1711, 2016`.
- Hekili issues: https://github.com/Hekili/hekili/issues/5354, https://github.com/Hekili/hekili/issues/5337. CurseForge: https://www.curseforge.com/wow/addons/hekili
- Blizzard: https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight
- API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes
- WeakAuras: https://www.icy-veins.com/wow/news/weakauras-to-end-support-in-midnight/ ; https://www.icy-veins.com/wow/news/weakauras-responds-to-addon-limitation-loosening-in-midnight/ (Nov 28 2025); https://www.wowhead.com/news/no-weakauras-addon-for-midnight-378740
- MaxDps: https://github.com/kaminaris/MaxDps, `Core.lua` ~720-830 (C_AssistedCombat path), `Core.lua:77-79` (`IsRetailWow` = WOW_PROJECT_MAINLINE)
- HekiLight: https://www.curseforge.com/wow/addons/hekilight ; https://github.com/meruuke/HekiLight `HekiLight.lua:910-975`
- Other wrappers: https://www.curseforge.com/wow/addons/justassistedcombat , /knickili , /simple-assisted-combat-icon , /nextgcd , /rotato
- Forever C_AssistedCombat API surface: wow MCP `wow_api_search` (flavor forever)
- EllesmereUI PR #2240: https://github.com/EllesmereGaming/EllesmereUI/pull/2240 ; `EllesmereUI_Lite.lua` (`IS_FOREVER`, `GCD_SPELL`)
- ForeverAuras: https://github.com/neroxrw/foreverauras ; Forever Cooldown Manager: https://www.curseforge.com/wow/addons/forever-cooldown-manager , https://github.com/Thunderz96/ForeverCDM ; CMC: https://www.curseforge.com/wow/addons/cooldown-manager-centered ; ThreatPlates: https://github.com/Backupiseasy/ThreatPlates/releases
- Catnip: https://github.com/DurtsGaming/Catnip (`docs/api-research.md` lines cited above; `docs/architecture.md:136-145`; `CLAUDE.md`), https://www.curseforge.com/wow/addons/catnip ; local install `/mnt/c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns/Catnip/` (TOC Interface 16001, v1.0.0)

## Open questions

1. Does `C_AssistedCombat.IsAvailable()` return true on Forever for a Druid, and does `GetNextCastSpell` give sensible vanilla Feral suggestions? This needs an in-game `/dump` and is the cheapest viable path.
2. Is the `insufficientPower` return of `C_Spell.IsSpellUsable` readable in combat on Forever? If so, it gives per-ability energy thresholds that Lua can see.
3. Is `UnitPower("player", Enum.PowerType.ComboPoints)` reliable when the player never switches targets? Catnip saw it go stale on target death or switch.
4. Are any Forever Druid spells or auras NeverSecret (`C_Secrets.GetSpellAuraSecrecy`)? Catnip saw level 2 for all of them.
5. Where did Hekili's maintainers explain their reasoning (Discord)? I found no technical write-up on GitHub.
6. Where is Blood in the Water published, and what is its license?
7. Would Durts add a LICENSE file to the repo to match the MIT label on CurseForge?
8. ConRO's Midnight status is unverified.

## Confidence

- **High:** Hekili's public record (it is thin); MaxDps and HekiLight wrap `C_AssistedCombat` (read the code); the Catnip repo facts and the api-research content; the Blizzard policy quotes.
- **Medium:** the status of the other Forever addons (from CurseForge pages, not run); whether Blood in the Water's techniques can be reproduced (secondhand via Catnip).
- **Low:** whether `C_AssistedCombat` works on Forever; whether a reconstructed-state predictor would be accurate enough to be useful.
