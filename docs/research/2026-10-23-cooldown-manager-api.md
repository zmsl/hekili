# Can the client's Cooldown Manager (`C_CooldownViewer`) help our beliefs?

Date 2026-10-23. Branch `forever-cooldownviewer-research` from `forever` 093313ae. Docs only; no addon code changes.
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
(`memory/gate-spike-results.md`) [GS]. The `wow` MCP listing omits most secrecy flags; every quote below is from the raw
documentation files.

## 0. Verdict

No new numbers. `C_CooldownViewer` itself is static metadata (which cooldown IDs exist per category, and per ID its spell,
override, linked aura spells, and whether it has charges or an aura); it carries no time, charge count or aura state.
The viewer frames are an ordinary Blizzard consumer of the same getters we already call (`C_Spell.GetSpellCooldown`,
`GetSpellCharges`, `GetSpellCastCount`, `C_UnitAuras.GetUnitAuras(unit, "HARMFUL|PLAYER")`, `GetUnitAuraBySpellID`,
`GetRefreshCarryOverDuration`, `GetTotemInfo`), and they work in combat only because Blizzard's code is untainted:
the secret values flow through it into `CooldownFrame_Set`, `StatusBar:SetValue` and `FontString:SetText`, and every
read-back getter on those widgets is documented `SecretReturnsForAspect` (Cooldown, BarValue, Text, Shown). The one
untested door is **presence**: a viewer item frame's Lua fields (`auraInstanceID`, `isActive`) and its shown state
under "hide when inactive" may tell a tainted reader *that* a tracked buff or our debuff on the target is up, even when
nothing about it is readable. If that reads plain in combat it closes part of AO/AP (our DoT up on the target) and the
player-buff up/down that the aura walk loses in combat, at the cost of requiring the user to enable the viewer and
track those spells. One `/vslog cdv` session (section 5) settles it; until then, plan nothing on it.

## 1. API inventory

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
| `C_UnitAuras.GetAuraDataByAuraInstanceID` | `RequiresUnitAuraAccess = true`, `SecretWhenUnitAuraRestricted = true` [UA:190-194] | | |
| `C_UnitAuras.GetRefreshCarryOverDuration` | `SecretWhenUnitAuraRestricted = true` [UA:412-417] | pandemic alert time [V:535] | |
| `C_UnitAuras.GetAuraDuration(unit, auraInstanceID)` | `RequiresUnitAuraAccess = true`, `RequiresValidUnitAuraInstance = true`, no `SecretWhen*` [UA:286-300]; returns a `LuaDurationObject` | not used by the viewer | unprobed; duration objects from secret sources return S getters [W PR11] |
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
viewer writes secret start/duration, bar values and texts in combat, so these read back secret. Whether it writes the
**Shown** aspect from a secret is the open question: Forever's viewer code has no `issecretvalue` anywhere and branches
on secret data directly (`aura.expirationTime > timeNow` [VD:749-751], `auraInfo.sourceUnit ~= "player"` [V:395-397],
`auraData.applications > 1` [V:1375]), then calls `self:SetShown(shouldBeShown)` [V:314-317] from `self.isActive`
[V:347-358]. Untainted code may do this; whether the resulting boolean, and so the shown state and the Lua fields, are
secret is not documented.

## 2. Belief and gap mapping

| Belief / gap | What the viewer could give | Documented secrecy | Worth it? |
|---|---|---|---|
| Cooldown ready / not ready | nothing new: `isActive` and `isOnGCD` are already plain from `GetSpellCooldown` (`Sources/Spellbook.lua`) | `NeverSecret` [SS:25-30] | no |
| Cooldown remaining | Cooldown swipe on the viewer icon | S (Cooldown aspect); the source is S [W PR11] | no; our own icon already gets the game's sweep from `SetCooldownFromDurationObject` [W PR28] |
| GCD | nothing new: the GCD spell 29515's `isActive` is plain, length S [W PR4] | | no |
| Charges | the viewer shows the count; we can read `maxCharges` and `isActive` (recharging) plain without it | `currentCharges` unflagged, under `SecretWhenCooldownsRestricted` | no viewer value. By-product: `GetSpellCharges().isActive` + `maxCharges` (NeverSecret) + `SPELL_UPDATE_CHARGES` give "full / recharging" edges plain, if a Forever pack ever has a charge spell |
| Player buff up / down in combat | item frame present + shown, `auraInstanceID ~= nil` | undocumented (section 1's open question) | **probe**: the aura walk stops at the first secret in combat (`Sources/Auras.lua`), so up/down edges are tracked from casts today |
| Player buff remaining / stacks | Cooldown swipe, bar value, applications text | S (Cooldown, BarValue, Text) | no |
| Our debuff on the target (AO / AP) | tracked-debuff item (`HARMFUL\|PLAYER` on `target`) present + shown | undocumented; addons cannot read target auras in combat at all [GS] | **probe**: the only presence signal besides nameplate aura frames (AP) |
| Target debuff remaining, partner debuffs | | S; the viewer filters `PLAYER` only, so partners' debuffs never appear | no |
| Static data: a spell's linked aura spells, `hasAura`, `charges`, `selfAura` | `GetCooldownViewerCooldownInfo` | unflagged, metadata | marginal: a cross-check of the kits' spell-to-aura links against DB2 (`wowdb`), not a belief |

## 3. Secret-safety and taint constraints for any use

- **Read, never call.** Read item-frame fields with `rawget` (`cooldownID`, `auraInstanceID`, `auraSpellID`,
  `auraDataUnit`, `isActive`) and the frame's `IsShown()`. Never call the viewer's refresh or data methods
  (`GetAuraData`, `RefreshData`, `RefreshAuraInstance`, `CacheCooldownValues`): they write `self.auraDataCached`,
  `self.cooldownStartTime` and similar [VD:774-781, V:976-1011], and a write from our tainted stack taints the viewer's
  table, after which its own combat refresh would fail on secrets and the user's Cooldown Manager breaks.
- **Hooks only by `HookScript` / `hooksecurefunc`** on the item frames (OnShow/OnHide, `OnActiveStateChanged`), never by
  replacing a method. The gate spike found AuraContainer's OnShow/OnHide did not fire to Lua [GS]; the viewer's may not
  either.
- **Every value through `issecretvalue()` first**, in `Sources/` only; a secret `auraInstanceID` still proves presence
  (`issecretvalue(x)` is true only for a value), so presence is `x ~= nil` tested as `issecretvalue(x) or x ~= nil`,
  never `a and b or c`. Never pass a viewer value back into an API (`GetAuraDuration(unit, id)` with a secret id is
  `AllowedWhenUntainted` only: an error for us).
- **The data is the user's configuration.** The viewer shows only what the user tracks, only when
  `cooldownViewerEnabled` is on and `IsCooldownViewerAvailable()` is true [V:1905-1911]; the item frames are pooled
  and reassigned on layout changes, so a source must map by `cooldownID` -> `spellID` at each `RefreshLayout`, not by
  frame. A presence signal from it is an optional, degraded-gracefully input, never a requirement.
- **Allocation.** `GetCooldownViewerCooldownInfo` builds a table: call it out of combat at build. Field reads and
  `IsShown` allocate nothing.

## 4. Update events

The viewer has no state event of its own: `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED(baseSpellID, overrideSpellID?)` is
the only one with a payload [CV:106-114]. Its frames listen to `SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_USES`,
`SPELL_UPDATE_USABLE`, `SPELL_RANGE_CHECK_UPDATE`, `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` [V:2159-2164],
`UNIT_AURA` for `player` and `target`, `PLAYER_TARGET_CHANGED`, `PLAYER_TOTEM_UPDATE`, `BAG_UPDATE_COOLDOWN`
[V:1734-1739], `PLAYER_IN_COMBAT_CHANGED` [V:1669]: the same events we already have. A presence source would read the
item fields after `UNIT_AURA` / `PLAYER_TARGET_CHANGED` (the viewer's handler is registered first, so ours sees the
updated fields if it runs after; check the order in the probe) or from OnShow/OnHide hooks if those fire.

## 5. Probe list: `/vslog cdv` (ForeverProbe `Log.lua`)

Setup: enable the Cooldown Manager (Options, `cooldownViewerEnabled`), track one cooldown spell (Bloodrage or Berserker
Rage), any charge spell the class has, one self-buff with a duration (Battle Shout, or Enrage), and one target debuff
of ours (Rend; Druid: Rip or Moonfire) in the Tracked Buffs and Tracked Bars groups, with "hide when inactive" on.

`/vslog cdv` writes one copy-box line per item, out of combat and in combat (S = secret, n = nil, else the value):

1. `CDV avail=<isAvailable> reason=<failureReason> cvar=<cooldownViewerEnabled> combat=<0|1>`.
2. Per category 0-8: `CDV_CAT c=<n> ids=<#GetCooldownViewerCategorySet(c, true)> learned=<#...(c, false)>`, each count's
   `issecretvalue`. (Are there Forever entries at all for this class?)
3. Per tracked `cooldownID` (out of combat only, it allocates): `CDV_INFO id spellID override linked=<list> selfAura
   hasAura charges isKnown flags category`, each field P/S; plus `C_Secrets.GetSpellCooldownSecrecy` and
   `GetSpellAuraSecrecy` of `spellID` and each linked ID.
4. Per viewer (`EssentialCooldownViewer`, `UtilityCooldownViewer`, `BuffIconCooldownViewer`, `BuffBarCooldownViewer`)
   and each `GetItemFrames()` child, by `rawget` only: `CDV_ITEM <viewer> <cooldownID> shown=<IsShown> active=<isActive>
   aiid=<auraInstanceID> aspell=<auraSpellID> aunit=<auraDataUnit> cdActive=<cooldownIsActive> gcd=<isOnGCD>
   actual=<isOnActualCooldown> start=<cooldownStartTime> dur=<cooldownDuration> charges=<cooldownChargesCount>`, then
   `cd=<Cooldown:GetCooldownTimes()>`, `cdShown=<Cooldown:IsShown()>`, BuffBar items `bar=<Bar:GetValue()>
   max=<select(2, Bar:GetMinMaxValues())>`, and the Applications / ChargeCount `GetText()`.
5. If `aiid` is plain: `CDV_DUR <unit> <aiid> hasSecret=<GetAuraDuration(...):HasSecretValues()> rem=<GetRemainingDuration()>`
   (pcall'd), and `GetAuraDataByAuraInstanceID` pcall'd (ok / error text / S).
6. `/vslog cdv watch`: `HookScript("OnShow"/"OnHide")` on every item frame, recording `CDV_SHOW` / `CDV_HIDE <cooldownID>`
   in the ring, to line up against `UNIT_AURA`, our casts and `PLAYER_TARGET_CHANGED` (do the scripts fire; at which ms
   relative to `UNIT_AURA`?).

Sequence, each step with `/vslog note`: out of combat with nothing up; the self-buff up; then pull and in combat:
the cooldown spell cast (on cooldown), a charge spent, the self-buff up then expired, Rend applied, Rend expired,
re-target to a mob without Rend and back. Run `cdv` at each step, `dump` at the end. After the fight, check
`/console taintLog 1` output (or the error frame) for any viewer error: our reads must not break it.

Questions it answers: (Q1) is `IsShown()` of a hide-when-inactive item plain in combat, and does it follow the buff and
the target debuff? (Q2) is `auraInstanceID` / `isActive` nil-vs-set readable in combat? (Q3) do OnShow/OnHide fire to
Lua? (Q4) does any Forever spell have a NeverSecret cooldown or aura flag (`C_Secrets`)? (Q5) does the viewer have
entries for Forever's classes at all (category sets non-empty)?

If Q1 or Q2 is yes: a `Sources/` reader turns it into `Read` up/down observations with no expiry for tracked auras
(the overlay path in `Sources/Auras.lua` is the model), opt-in, with the setup documented for users. If both are no:
close this line of inquiry; the Cooldown Manager adds nothing the belief can use.
