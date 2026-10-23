# Can the client's Cooldown Manager (`C_CooldownViewer`) help our beliefs?

Date 2026-10-23, revised the same day with in-game captures. Branch `forever-cooldownviewer-research` from `forever`
093313ae. Docs only; no addon code changes.
Question (owner): can the built-in Cooldown Manager (the "Cooldown Viewer": `C_CooldownViewer.*`, the
`EssentialCooldownViewer` / `UtilityCooldownViewer` / `BuffIconCooldownViewer` / `BuffBarCooldownViewer` frames, the
`COOLDOWN_VIEWER_*` events and the `C_Spell` / `C_UnitAuras` fields it reads) give us anything in combat that addons
otherwise cannot read: cooldowns, charges, player aura durations and stacks, target debuffs, the GCD.

Sources: the Forever generated docs `Blizzard_APIDocumentationGenerated/CooldownViewerDocumentation.lua` [CV:line],
`SpellDocumentation.lua` [SP:line], `SpellSharedDocumentation.lua` [SS:line], `UnitAuraDocumentation.lua` [UA:line],
`SecretPredicatesDocumentation.lua` [PR:line], `FrameAPICooldownDocumentation.lua` [CD:line],
`SimpleStatusBarAPIDocumentation.lua` [SB:line], `SimpleFrameAPIDocumentation.lua` [FR:line],
`LuaDurationObjectAPIDocumentation.lua` [DO:line]; Blizzard's `Blizzard_CooldownViewer` addon (Forever UI source):
`CooldownViewer.lua` [V:line], `CooldownViewerItemData.lua` [VD:line], `CooldownViewer.xml` [VX:line]; our earlier
measurements in `docs/research/tdf/2026-10-13-probe-session-W-results.md` (PR4, PR11, PR28) [W] and the gate spike
(`memory/gate-spike-results.md`) [GS]; and the `/vslog cdv` captures of 2026-10-23 [CAP:ms], ForeverProbe 215c0eb
(`Log.lua`: `cdvStatus`, `cdvIds`, `itemFrame`, `itemAura`, `itemWatch`). Every in-game value below is read the way
`Log.lua` reads it: item frames from the viewer's `GetChildren()` (those with a `layoutIndex`), item fields by `rawget`,
`item:IsShown()`, `item.Cooldown:GetCooldownTimes()`, the Applications / ChargeCount `GetText()`, each pcall'd and
each value tested with `issecretvalue` before it is printed (S = secret, nil, else the value); edges by
`item:HookScript("OnShow" / "OnHide")`, recording the time and the item's `cooldownID`, `spellID`, `auraInstanceID`.

## 0. Verdict

Yes, for **presence**. With no user setup the Forever client already fills the viewer with each class's default
category sets, and its item frames carry plain state in combat that the aura walk loses: for every tracked self-buff
and every debuff of ours on the target, `auraInstanceID` is a secret value while the aura is up and nil when it is not,
so `issecretvalue(x) or x ~= nil` is a plain up/down boolean, and `HookScript` OnShow/OnHide on the buff icons deliver
those edges to our code 3-4 ms after the game event. That closes the AO/AP gap for our own DoTs and debuffs on the
target, gives Victory Rush its Victorious window, and gives self-buff up/down edges in combat. It also gives a plain
GCD flag per item, a plain "on a real cooldown" boolean (the secrecy of `cooldownIsActive`), and full plain durations
for auras applied before the pull. It gives no remaining time, stacks or charges for anything applied in combat.

## 1. Captures

| Capture | Character | Content |
|---|---|---|
| `/vslog cdv` status + `ids` | Fury Warrior L25, Razormane, out of combat | category counts, every `CDV_ID` field and `C_Secrets` secrecy |
| `/vslog cdv frames` | same, out of combat (10089) and in combat (33218, 61255, 93207) | every item of the four viewers |
| `/vslog cdv aura` | in combat (36966) | `GetAuraDataByAuraInstanceID` / `GetAuraDuration` on the item's aura instance |
| `/vslog cdv watch` | open-world fights 52499-138832 | `CDV_SHOW` / `CDV_HIDE` against our casts, kills and `PLAYER_TARGET_CHANGED` |

No Cooldown Manager setup was done: the sets below are the client's defaults. The full 758-line dump is in the chat
transcript; the decisive rows are condensed in `cooldownviewer-2026-10-23.log` (job captures).

## 2. Measured

**Setup, out of combat.** `GetCooldownViewerCategorySet(c, learned / all)` for the Warrior: Essential (0) 10 / 16,
Utility (1) 12 / 20, TrackedBuff (2) 20 / 36, SpecAgnosticEssential (5) 3, EquipSlotEssential (7) 0 / 2. Every
`CDV_ID` field (spellID, override, linked spells, `selfAura`, `hasAura`, `charges`, `isKnown`, flags, category) read
plain; `C_Secrets.GetSpellCooldownSecrecy` and `GetSpellAuraSecrecy` read 2 (contextual) for every spell
[CAP: status, ids]. Item frames at 10089: `shown` and `isActive` plain true for the cooldown viewers,
`cooldownIsActive` false and `isOnGCD` false plain, `cd` 0 plain; the BuffIcon items plain `shown=false` (hidden while
their aura is down); the BuffBar viewer's items unconfigured (`cooldownID` nil).

**Cooldown flags in combat.** At 33218, during the GCD after the pull: every item's `shown` and `isActive` plain;
`cooldownIsActive` true and `isOnGCD` true, plain, for the on-GCD spells; Heroic Strike (1608, off the GCD) plain false
and false; Charge (100, its real cooldown running) `cooldownIsActive` **secret** and `cd` secret. So `isOnGCD` is a
plain GCD flag, `cooldownIsActive` is plain while the item is ready or only on the GCD, and
`issecretvalue(cooldownIsActive)` is a plain "a real cooldown runs" boolean. `Sources/Spellbook.lua` already reads the
equivalent (`GetSpellCooldown().isActive` / `isOnGCD`, `NeverSecret` [SS:25-30]), so this is a cross-check, not news.

**Presence.** Rend (6547) on the target at 61255: `auraInstanceID` and `auraSpellID` secret, `auraDataUnit` plain
"target", `cdShown` true; at 93207, after Rend fell off: `auraInstanceID` nil. Demoralizing Shout (6190) on the
target and Victorious (402975) on the player behave the same (secret while up, nil while down). `issecretvalue()` on a
secret is allowed for tainted code, so `issecretvalue(id) or id ~= nil` is a plain presence boolean with no comparison
on a secret. `auraDataUnit` ("player" / "target") is plain.

**Edges.** The OnShow/OnHide hooks fire into addon code (unlike the AuraContainer hooks of the gate spike [GS]):

| Edge | Game event | Hook | Lag |
|---|---|---|---|
| Victorious shows | kill (`TARGET none` 52495) | `CDV_SHOW` BuffIcon i=2 402975 at 52499 | 4 ms |
| Victorious hides | 20 s timeout | `CDV_HIDE` 87499 | |
| Victorious shows | Execute kill | `CDV_SHOW` 98977 | |
| Victorious hides | 20 s timeout | `CDV_HIDE` 118995 | |
| Victorious shows | kill | `CDV_SHOW` 128758 | |
| Victorious hides | Victory Rush cast 402927 at 130776 (consumed) | `CDV_HIDE` 130779 | 3 ms |
| Demoralizing Shout shows | its cast | `CDV_SHOW` i=3 6190 at 135085, `auraDataUnit` target | 3 ms |
| Demoralizing Shout hides | target died (`TARGET none` 138832) | `CDV_HIDE` 138830 | -2 ms |

**Pre-pull auras stay plain.** Bloodrage (2687), applied at 30975 out of combat: at 33218, in combat, its item read
`auraInstanceID` 319, `auraSpellID` 29131, `auraDataUnit` player, and `cd` start 453384280, duration 10000 ms, all
plain. Auras applied in combat read secret. A pre-pull buff's full timing is therefore readable in combat from the
item's Cooldown widget until it falls off.

**Direct reads refused.** At 36966 `C_UnitAuras.GetAuraDataByAuraInstanceID` and `GetAuraDuration` on an item's aura
instance failed: "Auras cannot be accessed when secret while tainted by 'ForeverProbe'". Presence only: no duration and
no stacks for an in-combat aura. The Applications and ChargeCount texts read nil / none (no stacking aura or charge
spell was tracked), so stack and charge text secrecy is untested.

**BuffBar.** The BuffBar viewer had no configured items (`cooldownID` nil): its bars need user setup.

## 3. API inventory

| Function / field | Args | Returns | Secrecy (raw doc) | Blizzard usage |
|---|---|---|---|---|
| `C_CooldownViewer.IsCooldownViewerAvailable()` | none | `isAvailable`, `failureReason` | none [CV:76-84] | `CooldownViewerMixin:ShouldBeShown` [V:1909], Settings predicate |
| `C_CooldownViewer.GetCooldownViewerCategorySet(category, allowUnlearned=false)` | `CooldownViewerCategory` 0-8 (Essential, Utility, TrackedBuff, TrackedBar, GroupBuff, SpecAgnosticEssential, SpecAgnosticTracked, EquipSlotEssential, EquipSlotTracked) | `cooldownIDs` (table of number) | `SecretArguments = "AllowedWhenUntainted"` [CV:13]; returns unflagged | settings data provider |
| `C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)` | number | `CooldownViewerCooldown` | `MayReturnNothing = true`, `SecretArguments = "AllowedWhenUntainted"` [CV:29-30]; returns unflagged | `GetCooldownInfoForID`, cached per item [VD:71] |
| `CooldownViewerCooldown` fields | | `cooldownID`, `spellID?`, `spellCategoryID?`, `overrideSpellID?`, `overrideTooltipSpellID?`, `equipSlot?`, `buffSlot?`, `linkedSpellIDs`, `selfAura`, `hasAura`, `charges`, `isKnown`, `isInvisible`, `flags`, `category` | no field flags [CV:127-146] | static: which spell, which aura spells it shows |
| `C_CooldownViewer.GetValidAlertTypes(cooldownID)` | number | alert event types (Available, PandemicTime, OnCooldown, ChargeGained, OnAuraApplied, OnAuraRemoved) | `SecretArguments = "AllowedWhenUntainted"` [CV:63] | alert settings |
| `GetLayoutData()` / `SetLayoutData(data)` | | cstring | Set: `SecretArguments = "AllowedWhenUntainted"` [CV:88] | the user's saved layout |
| `GetGroupBuffItems()` | | `GroupBuffItem` (spellID, name, iconID, flags, isKnown) | none [CV:43-49] | group buff filter |
| `COOLDOWN_VIEWER_DATA_LOADED`, `COOLDOWN_VIEWER_TABLE_HOTFIXED` | | no payload | `SynchronousEvent = true` [CV:100-121] | data reload |
| `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED` | | `baseSpellID`, `overrideSpellID?` | no secret flag [CV:106-114] | item override refresh [V:1778] |

What the viewer frames read (all on the untainted side):

| Getter | Secrecy (raw doc) | Viewer use | Measured for us |
|---|---|---|---|
| `C_Spell.GetSpellCooldown` | `SecretWhenCooldownsRestricted = true`, `SecretArguments = "AllowedWhenTainted"` [SP:312-313]; fields: `isEnabled`, `isActive`, `isOnGCD` `NeverSecret = true`; `startTime`, `duration`, `modRate` unflagged [SS:23-30] | start/duration into `CooldownFrame_Set` [VD:419, V:984-999, V:1150] | flags P in combat, times S [W PR4, PR11]; already read by `Sources/Spellbook.lua` |
| `C_Spell.GetSpellCharges` | `SecretWhenCooldownsRestricted = true` [SP:294]; `maxCharges` and `isActive` `NeverSecret = true`; `currentCharges`, `cooldownStartTime`, `cooldownDuration`, `chargeModRate` unflagged [SS:10-15] | charge swipe and count [VD:434, V:902-927, V:1110] | unprobed |
| `C_Spell.GetSpellCastCount` | `SecretWhenCooldownsRestricted = true` [SP:259] | count text [V:1119] | unprobed |
| `C_Spell.GetLastCategoryCooldownSource` | `SecretWhenCooldownsRestricted = true` [SP:157] | potions/healthstone category [VD:62] | |
| `C_UnitAuras.GetUnitAuras(unit, filter)` | `RequiresUnitAuraAccess = true`, `SecretArguments = "AllowedWhenUntainted"`, returns `ConditionalSecretContents = true` [UA:493-513] | `"HARMFUL\|PLAYER"` on `target` (or `"HELPFUL\|PLAYER\|INCLUDE_NAME_PLATE_ONLY"` on a friend) for tracked debuffs [VD:716-743] | target auras error in combat for tainted code ("Auras cannot be accessed when secret while tainted") [GS] |
| `C_UnitAuras.GetUnitAuraBySpellID` | `SecretWhenUnitAuraRestricted = true`, `RequiresNonSecretAura = true` [UA:454-458] | linked-spell scan of player and target [VD:23-31] | |
| `C_UnitAuras.GetPlayerAuraBySpellID` | `SecretWhenUnitAuraRestricted = true`, `RequiresNonSecretAura = true` [UA:395-399] | not used by the viewer | nil in combat (Catnip) [W, player-auras row] |
| `C_UnitAuras.GetAuraDataByAuraInstanceID` | `RequiresUnitAuraAccess = true`, `SecretWhenUnitAuraRestricted = true` [UA:190-194] | | refused in combat for tainted code on a viewer item's aura [CAP:36966] |
| `C_UnitAuras.GetRefreshCarryOverDuration` | `SecretWhenUnitAuraRestricted = true` [UA:412-417] | pandemic alert time [V:535] | |
| `C_UnitAuras.GetAuraDuration(unit, auraInstanceID)` | `RequiresUnitAuraAccess = true`, `RequiresValidUnitAuraInstance = true`, no `SecretWhen*` [UA:286-300]; returns a `LuaDurationObject` | not used by the viewer | refused in combat for tainted code [CAP:36966] |
| `UNIT_AURA` | `SecretWhenAurasRestricted = true` [UA:644] | viewer registers `player`, `target` [V:1736] | fires in combat, unit plain, `addedAuras` secret [W] |

The predicate text, the same for both restriction kinds [PR:80-92]: "Guarded APIs and events produce secret values when
combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as
never or always secret, which takes priority over restrictions." `C_Secrets.GetSpellCooldownSecrecy`,
`GetSpellAuraSecrecy` and `GetSpellCastSecrecy` report that per-spell flag; Warrior spells read 2 (contextual) [W].

Widget read-back on the viewer's own frames:

| Getter | Raw doc |
|---|---|
| `Cooldown:GetCooldownTimes()`, `GetCooldownDuration()`, `GetCooldownDisplayDuration()` | `SecretReturnsForAspect = { Enum.SecretAspect.Cooldown }` [CD:19-49] |
| `StatusBar:GetValue()`, `GetMinMaxValues()` (the BuffBar viewer's bar, `SetMinMaxValues(0, duration)` / `SetValue(remaining)` [V:1564-1565]) | `SecretReturnsForAspect = { Enum.SecretAspect.BarValue }` [SB:38, SB:162] |
| `FontString:GetText()` (stack and charge counts [V:1441, V:1599]) | `SecretReturnsForAspect = { Enum.SecretAspect.Text }` |
| `Frame:IsShown()`, `IsVisible()` | `SecretReturnsForAspect = { Enum.SecretAspect.Shown }` [FR:915, FR:969] |
| `Frame:GetAlpha()` | `SecretReturnsForAspect = { Enum.SecretAspect.Alpha }` |
| `Cooldown:SetCooldownFromDurationObject` | `IsProtectedFunction = true`, `SecretArguments = "AllowedWhenUntainted"` [CD:308]; works for us in combat [W PR28] |
| `LuaDurationObject:GetRemainingDuration()` etc. | `SecretArguments = "AllowedWhenUntainted"`, no return flag [DO:271-333]; `EvaluateRemaining*(curve)`: `SecretWhenCurveSecret = true` [DO:73-95]; `HasSecretValues()`: `ReturnsNeverSecret = true` [DO:351-354]; measured S 125/125 in combat [W PR11] |

`SecretReturnsForAspect` means the value is secret once a secret was written into that aspect of that widget. The
viewer writes secret start/duration, bar values and texts in combat, so these read back secret; the viewer's code has no
`issecretvalue` and branches on secret data directly (`aura.expirationTime > timeNow` [VD:749-751],
`auraData.applications > 1` [V:1375]), then calls `self:SetShown(shouldBeShown)` [V:314-317] from `self.isActive`
[V:347-358]. The captures (section 2) settle what the documentation left open: the **Shown** aspect and `isActive` stay
plain in combat, and the Cooldown aspect is plain for a cooldown or aura whose values were set before combat.

## 4. Mapping to beliefs

| Belief / gap | What the viewer gives in combat | Measured | Worth it? |
|---|---|---|---|
| Our debuff / DoT on the target (AO / AP) | item present: `auraInstanceID` secret = up, nil = down; OnShow / OnHide edges for BuffIcon items | Rend 61255 up, 93207 down; Demoralizing Shout 135085-138830 | **yes**: the only plain presence of our debuff on the target besides nameplate aura frames |
| Proc windows (Victorious for Victory Rush) | OnShow 4 ms after the kill, OnHide at the 20 s timeout or 3 ms after the consuming cast | 52499, 98977, 128758; 118995, 130779 | **yes**: a plain proc edge, today inferred from the kill |
| Player buff up / down | same presence rule, `auraDataUnit` player | Victorious; Bloodrage | **yes**: the aura walk stops at the first secret in combat (`Sources/Auras.lua`) |
| Pre-pull buff timing | `auraInstanceID`, `auraSpellID` and the Cooldown start / duration, all plain | Bloodrage 33218 | yes, cheap: exact expiry for buffs and potions taken before the pull |
| GCD | `isOnGCD` per item, plain | 33218 | cross-check only; Spellbook reads `isOnGCD` already |
| Real cooldown running | `issecretvalue(cooldownIsActive)` | Charge 33218 | cross-check for the usability gate |
| Remaining time, stacks, charges of in-combat auras | nothing: Cooldown aspect secret, direct reads refused | 33218, 36966 | no |
| Partners' debuffs | nothing: the viewer filters `HARMFUL\|PLAYER` [VD:716-743] | | no |
| Static spell-to-aura links | `GetCooldownViewerCooldownInfo` (`linkedSpellIDs`, `selfAura`, `hasAura`) | plain ooc | a tools-time cross-check of pack aura links |

Dependencies: the user's Cooldown Manager must be enabled (`cooldownViewerEnabled` and `IsCooldownViewerAvailable()`
[V:1905-1911]), and only tracked spells have presence. The default sets are game data, filled per class without setup,
so most pack auras are probably covered; a tools check could compare each pack's aura spell IDs against the class's
category sets (and `linkedSpellIDs`) and list the gaps. A missing or disabled viewer must leave the belief exactly as
it is today: the viewer is an optional, degrade-gracefully input, never a requirement.

## 5. Secret-safety and taint constraints

- **Read, never call.** Item fields by `rawget` (`cooldownID`, `auraInstanceID`, `auraSpellID`, `auraDataUnit`,
  `isActive`, `isOnGCD`, `cooldownIsActive`) and frame / widget getters (`IsShown`, `Cooldown:GetCooldownTimes`).
  Never call the viewer's own methods (`GetAuraData`, `RefreshData`, `RefreshAuraInstance`, `CacheCooldownValues`) and
  never write its tables: they write `self.auraDataCached`, `self.cooldownStartTime` [VD:774-781, V:976-1011], and a
  write from our tainted stack taints the viewer, after which its own combat refresh fails on secrets.
- **Hooks only by `HookScript`** (or `hooksecurefunc`), never by replacing a script or method.
- **Every value through `issecretvalue()` first**, in `Sources/` only. Presence is `issecretvalue(id) or id ~= nil`,
  never `a and b or c`, never a comparison on the id. Never pass a viewer value into an API: the aura-instance getters
  refuse tainted callers (measured).
- **Pooled frames.** Items are pooled and reassigned on layout changes, so map by the item's plain `cooldownID` at
  each layout refresh, out of combat, not by frame identity.

## 6. How a Source would consume it

A `src/Hekili/Game/State/Sources/CooldownViewer.lua`, in the shape of `Sources/Auras.lua`'s overlay path (poll 11),
which already turns a plain on / off signal into `Obs.Read` with `ReadOf.Aura` (remaining -1 = up with no expiry,
0 = down):

1. **Build, out of combat** (load, spec change, `COOLDOWN_VIEWER_DATA_LOADED`, the viewer's layout refresh): read
   `GetCooldownViewerCategorySet` for each category and `GetCooldownViewerCooldownInfo` per id (both allocate; never in
   combat), and map `cooldownID` → the pack's aura index (unit × aura key, as `(u - 1) * I.AURA_UNIT + j`) through the
   spell ID, `overrideSpellID` and `linkedSpellIDs`. Walk the four viewers' item frames and, for each item whose
   `cooldownID` maps to a tracked aura, install `HookScript("OnShow")` and `HookScript("OnHide")` once (a plain
   per-frame flag stops double hooks; frames are reused, so the hook reads the item's `cooldownID` at fire time and looks
   it up in a preallocated id → aura-index array). Nothing is called on the viewer and nothing written to its frames.
2. **Edges.** On each hook: read `auraInstanceID` by `rawget`, presence = `issecretvalue(id) or id ~= nil`; stage
   `Obs.Read` up (-1) on OnShow with presence, down (0) on OnHide or no presence, keyed by the pack's aura index and
   the unit from the plain `auraDataUnit`. OnShow without presence (a cooldown item, or "hide when inactive" off) is
   ignored. If the id is plain (a pre-pull aura) and the item's `GetCooldownTimes()` is plain, stage the real expiry
   instead of -1.
3. **Per poll.** A rawget of `isOnGCD` and `issecretvalue(cooldownIsActive)` on the mapped cooldown items, as a
   cross-check of the usability gate (`Sources/Spellbook.lua`), plus a presence re-read on `PLAYER_TARGET_CHANGED`
   (the target's debuff items change without a show edge when "hide when inactive" is off).
4. **Allocation.** No tables or closures per edge: the two hook closures are created at build, one per item frame;
   the lookup arrays are preallocated; `Stage` writes into the preallocated stage ring.
5. **Taint rule.** Our hooks run after Blizzard's script on the same frame; they only read. If the open question below
   shows any viewer breakage, the source must drop the hooks and fall back to a per-poll presence read.

## 7. Open questions and probes

- **Taint.** Do the hooks taint the viewer? The owner is being asked whether the Cooldown Manager kept working through
  the session and whether `/console taintLog 1` shows anything. Until confirmed clean, no code.
- **Hide when inactive.** With that setting off an item stays shown while its aura is down, so `shown` is not
  presence; use `isActive` and the aura fields, and verify `isActive` follows the aura (only `shown` / `auraInstanceID`
  were watched here).
- **Coverage.** Spells not in the default sets: can the user (or we, never) add them; which pack auras the Warrior and
  Druid sets miss (the tools check above). Stacking auras and charge spells: are Applications / ChargeCount texts secret?
- **Re-target.** Does the target's debuff item hide and re-show on `PLAYER_TARGET_CHANGED`, and in which order against
  the event?
- **Instances.** Encounter and challenge restrictions may make more of these fields secret; re-run `/vslog cdv` in a
  dungeon.
