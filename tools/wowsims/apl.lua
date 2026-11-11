-- tools/wowsims/apl.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 4): a
-- wowsims/forever APL (a request's player.rotation) as a "(wowsims.com)" pack's SimC text with the fork's keys.
-- Data: wowsims/forever (MIT, https://github.com/wowsims/forever); the APL JSON is translated as data, no code copied.
--
-- The translation rules (the plan's Task 4):
-- 1. One `.simc` line per APL entry, in order: `prepullActions` -> `actions.precombat` (wowsims's order: by a
--    constant `doAtValue`, earliest first, ties in the APL's order; an entry with no `doAtValue` or one after the pull
--    is omitted, as wowsims ignores it, and one whose `doAtValue` does not fold to a constant too: it folds from
--    constants, `math` and `spellCastTime`, the kit ability's `cast` (a function read in the kit's stub state, as the
--    pre-pull guard below; re-pin plan Task 4), so `-spellCastTime(X)` is `-<X's cast>`: a `# Deviation:` line, as
--    wowsims folds the hasted cast; `spellGcdHastedDuration` folds the kit ability's unhasted GCD, `gcdTime` else 0 off
--    the GCD, 1 a totem, 1.5 a spell: its own `# Deviation:` line, CN4; `spellTravelTime` the kit ability's
--    `flightTime`, else the request's `distanceFromTarget` over its `velocity`, else 0: wowsims's distance over the
--    missile speed, translator-2), `priorityList` -> `actions`,
--    each group a list `actions.<snake of its name>` called with `call_action_list,name=<snake>`, groups in the APL's
--    order as first called; `valueVariables` are inlined where referenced.
--    The pre-pull guard (owner ruling 2026-10-21: a guard against recasting, the player decides when to press): each
--    cast line of the precombat list, and of a list only pre-pull lists call, gets one term ahead of its condition,
--    derived from what its ability's handler does (called once under pcall in the kit's stub state with the verbs
--    recorded, and once more with every buff up for its removals):
--    - it applies an aura of the ability's own key: `!buff.<key>.up` (applyBuff) or `!debuff.<key>.up` (applyDebuff),
--      unless the aura's duration is at most the ability's cooldown (moot: the cooldown already hides it);
--    - it summons a totem of its own key: `!totem.<element>.up` (the element's slot);
--    - otherwise no guard (the ability's own usability and cooldown decide).
--    A guard term the line's condition already has as an `&` term is not added twice (L102).
--    A mutually exclusive group (lines of one list whose handlers remove each other's aura) guards its first line by
--    every member's aura (`!buff.a.up&(!action.b.known|!buff.b.up)`: rule 6's guard on another ability's read),
--    later lines by their own: the first is cast only when none is up, the later replaces it. A handler that raises
--    gives no guard and a header note.
-- 2. Omitted, and listed in the file's second comment block: `hide: true` entries; entries whose condition folds to
--    false; entries whose action or condition uses a node the fork lacks (`schedule`, `itemSwap`, `wait`,
--    `activeItemSwapSet`, `selectedConjured`), a cast aimed at another target (`target` Target with an index above 0:
--    wowsims's second target, Bane of Havoc; aura audit C7, never cast on the current one), or whose own action is an
--    unmapped spell, item or other ID (an unmapped
--    read drops only its branch: rule 12); a call of a group whose every entry was omitted. Also listed: rule 12's
--    dropped reads and rule 13's unmapped cooldowns, by entry. A `wait` stays omitted (CN19, docs/dev/wowsims-packs.md):
--    the engine times each line at its own ready moment, so a hold only matters against a later line ready sooner.
-- 3. Toggles: a group whose actions are all empty is a wowsims ON/OFF switch: `actionGroupUsed` of it reads
--    `settings.wowsims_<snake of the name without " ON/OFF">`, its default on exactly when the APL's reference to it is
--    not hidden; the class registers that setting for the spec (named "<Group> (wowsims.com)"). The header lists a
--    setting only when an emitted line reads it (ruling L14): a group whose readers were all omitted is no setting.
--    `actionGroupUsed` of a group with actions is wowsims's constant (apl_action_group_reference.go Finalize): true
--    when a shown entry anywhere (the lists, a group's actions) references the group, else false.
-- 4. `auraIsKnown` (wowsims: the aura is registered on its source unit, Self by default): on Self or the target, an
--    ID that resolves (rule 5, or a kit talent's spell) to a talent's key or aura is `talent.<key>.enabled`, to an
--    ability's key `action.<key>.known`, to any other aura `true`; an ID nothing resolves, or another unit, is false.
--    An ID nothing resolves leaves a header note (`auraIsKnown of the unresolved aura <id> folds false`), so the fold
--    is not silent. wowsims registers a gear, set or consumable aura only when it is equipped or configured; `true`
--    for one of those may disagree when it is not worn, and the branch then rests on the aura's own read (down while
--    not worn): the Warlock APLs read Revelation 1323392, the weapon enchant 8217's proc. Solo exports: another
--    player's aura (wowsims's External, tag -1) is never registered, so it is not known (false, no note) and every
--    other read of it is nil (rule 6: dropped).
-- 5. Keys, from the character's ability set (tests/Forever/helpers/engine.lua abilitySet: the class kit, the shared
--    content and every race's racials, as the engine merges them): a spell ID maps through the recipe's `map`, else
--    an ability's `id` and `copy`, auras by the recipe's aura-only `auras` map ({ [aura ID] = key }: an aura wowsims
--    keys by an ability's own spell ID, where `map` would also turn that ability's casts) then `map` then the set's
--    auras then abilities (an ability's key only where the kit registers an aura under it: else rule 12's nil, as an
--    unregistered `debuff.<ability>` is an unknown aura to the engine), items by an ability's `item` or `items` (the APLs at the pin that read such an aura: the
--    CHANGELOG's central fix 13 developer note);
--    `includeReactionTime`, `rank` and a `tag` other than -1 (rule 4) are ignored. An aura's `sourceUnit` Self (or none) reads `buff.`,
--    CurrentTarget or Target `debuff.`; a resource's current value on the Pet (`currentMana`) reads `pet.<resource>`
--    (`pet.mana`: Engine/Sim/State.lua's mt_pets, the pet unit's UnitPower); any other resource value with a source unit
--    other than Self is unsupported.
-- 6. Leveling guard: a read of another ability `X` (its cooldown, cast time, cost, readiness, or an aura whose key is
--    `X`; an aura whose ID is a talent's spell: the talent) is wowsims's unresolved (nil) node while `X` is unknown,
--    and nil propagates as wowsims builds the APL (sim/core/apl_values_operators.go): `not`, `cmp` and `math` of a nil
--    are nil; `and`/`or` drop a nil term and are nil when every term is; a nil condition is true (apl_action.go). So a
--    term that may be nil is written `(!<known>|<term>)` in an `and` and as the condition, `(<known>&<term>)` in an
--    `or`, with `<known>` its known test, `(kA|kB)` (each key once) for an `and`/`or` whose every term may be nil,
--    and one guard a test for a comparison of two reads. An empty value and another player's aura are nil always (dropped here). The
--    line's own action is never guarded (the engine skips an unknown action). `min` / `max` (newValueMin/Max: a nil
--    term dropped, nil when every term is) are the engine's `min(...)` / `max(...)` (Engine/Sim/Utils.lua safeMin /
--    safeMax skip a false argument) over the terms not dropped here, each that may be nil as `(<known>&<term>)`, one
--    term as itself; nil when every term is (the and-rule).
-- 7. `focus` from the recipe (the tier by the line's role, docs/dev/wowsims-packs.md; none on a pre-pull line),
--    `use_off_gcd=1` on an ability whose `gcd` is `"off"`; the recipe's `leveling` lines are appended to `actions`
--    and its `levelingFirst` lines put before them (a form the sim starts in, which the APL's own lines would never let a trailing line reach):
--    the `levelingFirst` lines lead a non-empty precombat list too (its pre-pull cast would show before the form):
--    `leveling` lines are silent at 60, `levelingFirst` lines whenever their form is up. Each recipe `extra`
--    ({ before = action, line = text }, content outside wowsims's model) goes just before the first `actions` line of
--    `before` (an error when there is none). The recipe's `settings` ({ [key] = { default = bool, desc = text } }) are
--    pack settings like an ON/OFF group's: a line reads one as `settings.<key>`, and the header lists each one read.
--    The recipe's `prepullSkip` ({ action key, ... }: an owner ruling against a wowsims pre-pull cast) omits that
--    action's precombat lines, listed (an error when there is none).
--    The recipe's `requires` ({ [action key or group's snake name] = talent key }) puts `talent.<key>.enabled&` before
--    the condition of each such entry, in every list (not when the condition already has it as a top-level `&` term;
--    an `and`/`or` writes a repeated term once): an APL written for a talent build (wowsims picks it by that
--    talent, e.g. an Auto rotation) runs those entries only once the talent is taken, so a level without it skips them.
--    The recipe's `guard` ({ [action key or group's snake name] = SimC expression }) appends `&(<expression>)` to the
--    condition of each such entry (rule 13's automatic lines too), in every list (after a required talent); keyed
--    "<list> #<n>", to a move entry's condition, which its reached lines carry (rule 19, the ON variant): a
--    documented deviation from wowsims, each
--    with its reason in the recipe and docs/dev/wowsims-packs.md.
--    The recipe's `condition` ({ [action key] = SimC expression }) replaces the APL's condition of each cast line of
--    that action, in every list (before `requires` and `guard`; also where the APL's folds false, L11; an error when no
--    line casts it): an owner-approved
--    deviation from wowsims, with its reason in the recipe header.
-- 8. Constants: `true`/`false`; a number; a Go duration ("1.5s", "300ms", "2m", "1m30s") in seconds; "N%" as N when
--    it is a direct operand (a variable followed) of a comparison with a percent read (M.PERCENT: `mana.pct`,
--    `health.pct`, which run 0-100 where wowsims's run 0-1), else N/100 as wowsims reads it (inside `math`, or
--    compared with anything else: Demonology's "Execute at" 35% scales a time). A percent read inside `math`, `min`
--    or `max` is unsupported (rule 2): its scale would leak into the result.
-- 9. `auraIcdIsReady` (wowsims: the proc aura's internal cooldown is ready): the aura declaring `icd` (RegisterAura,
--    seconds from its last application) by its ID or its `icdSpell` (the proc trigger wowsims names the ICD by) is
--    `buff.<key>.icd_ready`, guarded by the talent when that ID is a talent's spell (rule 6); an aura declaring none is
--    unsupported (rule 2), as is a source unit other than Self. `includeReactionTime` is ignored (rule 5).
-- 10. `auraShouldRefresh` (wowsims sim/core/exclusive_effect.go ShouldRefreshExclusiveEffects: false for an aura with
--    no exclusive effect; else true when no stronger effect of its category is up and none of ours outlasts the
--    overlap; solo, ours is the only one): only for an aura the recipe's `exclusive` set ({ [spell ID] = true }) lists,
--    since neither the DB2 nor the APL tells which wowsims auras carry exclusive effects (NewExclusiveEffect, in class
--    code and spelldata/parse_effects_exclusive.go); any other is unsupported (rule 2). Then
--    `<unit>.<key>.remains<=<maxOverlap>` (0 by default; the target's by default, as wowsims's GetTargetUnit),
--    `|...stack<max_stack` for a stacking aura, guarded (rule 6); `cancelAura` is the action
--    `cancel_buff,buff_name=<key>`; `autoSwingTime` MainHand / OffHand is `mainhand_speed` / `offhand_speed`;
--    `autoSwingTime` Ranged is `ranged_speed`; `autoTimeToNext` MainHandAuto / RangedAuto is `mainhand_remains` /
--    `ranged_remains` (the kits' clocks), MeleeAuto `min(mainhand_remains,offhand_remains)` (wowsims's earlier hand;
--    a hand with no weapon reads 3600 s, never) and AnyAuto that with `ranged_remains` where the kit has it
--    (translator-5; a kit without both hand clocks: unsupported), and a comparison on `autoTimeSinceLast` (since = speed - remains) is written
--    on the clock: `since<x` is `<hand>_remains><hand>_speed-x` (the recheck parser forecasts a clock's `<` and its `>`
--    wrap). A variable the recipe's `windowVars` ({ [variable name] = window }) names reads that window instead (§3a:
--    a span the kit registers, `RegisterWindow`): its comparison on a time since is `window.<w>.up&window.<w>.elapsed
--    <op> x` (the hunters' "Just shot" from the `weave` window). A `windowVars`, `guard` or `requires` key that names no
--    variable or APL entry (an action, a group, a move entry; emitted or omitted) is an error (CN12).
--    `remainingTime` is `fight_remains`, which answers "unknown" (3600 s) on Forever: an API-forced deviation (the
--    replay world answers the log's time to its end: R42, tests/Game/harness/loop.lua). `multipleCdUsages` without a
--    base spell is wowsims's GetBool on it: `alignCdEnd` `(fight_remains<=D|fight_remains>(CD+(D/2)))`, D the
--    spell's buff's duration (`buff.<key>.duration`), CD `cooldown.<key>.duration`; without `alignCdEnd` true; with a
--    base spell unsupported.
-- 11. `unitDistance` (wowsims's yards from the APL's unit to its target; the source unit is ignored, as wowsims does)
--    compared with a whole number N: `<=`/`<` N as `target.within<N>`, `>=`/`>` N as `target.outside<N>` (either
--    side; `=`/`!=` N is unsupported, anything but a whole number N is rule 18's movement term); `not` of one is the
--    opposite bracket (`!(d>N)` is `target.within<N>`, `!(d<N)` `target.outside<N>`), as `!` of a bracket would read
--    false for an unknown distance. API-forced deviation: the client gives no yards,
--    only per-spell range checks (C_Spell.IsSpellInRange, plain in combat: probe W PR7), so the engine brackets the
--    distance between the tracked abilities' own ranges (src/Hekili/Game/State/Families/Enemies.lua VS.TargetRange)
--    and `within`/`outside` test the bracket's bounds (`maxR <= N`, `minR >= N`; `<` reads as `<=` and `>` as `>=`): a
--    distance between two abilities' ranges answers neither side, and an unknown one (no plain answer yet for the
--    target) answers both, never blocking a line. The last plain bracket stays believed if the reads go secret.
-- 12. An unresolvable read (wowsims's nil node: sim/core apl_values_aura.go and apl_values_spell.go return nil for an
--    aura or spell the unit lacks): an aura, spell, item or other ID nothing maps (rule 5) in a value or condition is
--    nil, so rule 6 drops that branch (a nil condition is true) and the entry stays; `spellIsKnown` of one is false
--    (wowsims's constant). A deviation when wowsims has the aura or spell and the fork does not (a branch wowsims
--    keeps is dropped); the header lists every such ID, once an entry. Only an entry whose own action is unmapped is
--    omitted whole (rule 2). A movement term (rule 18) is the same nil, from the node rather than an ID.
-- 13. wowsims's automatic cooldowns, read from the spec's exported log (the context's `log`; M.autocasts): the action
--    `autocastOtherCooldowns` (sim/core/apl_actions_casting.go: the first ready major cooldown, registered with
--    AddMajorCooldown in sim/core/major_cooldown.go and not cast by the APL itself, ready-at then priority first, cast
--    once the GCD is ready) is one line per cooldown the log's "Major cooldown used" lines name, in first-use order
--    (a proxy for wowsims's ready-then-priority; equal when they are first ready together), each key once and none
--    the APL casts itself under another ID (that key's own line stands; noted), with rule 7's `use_off_gcd` for an
--    off-GCD ability (a documented deviation, packs_spec requiring the flag on every off-GCD line: wowsims waits for
--    the GCD before an automatic cast, the fork shows an off-GCD cooldown as soon as it is ready; the replay scores
--    on-GCD decisions only), under the entry's condition and
--    the ability's own toggle (the engine gates `toggle = "cooldowns"`/`"defensives"` itself; a defensive one appears
--    only when wowsims fired it: its default is a tank's). The log samples one race, so `autocastOtherCooldowns` also
--    takes every racial major cooldown of the request's class (M.RACIALS by M.CLASS_RACES, the defensive ones only for a
--    tank, none the APL casts itself), as one block in racials.go's order where the log first used one, else first
--    (racials register first, sim/core/character.go:304, all at priority 0); each other race's line is inert, its
--    racial unknown (Engine/Schema/Races.lua). The player's cooldown timings or `hpPercentForDefensives`, which
--    change when wowsims autocasts a racial, are an error (none at the pin). `castAllStatBuffCooldowns` (every instant major cooldown
--    whose buff raises one of its stat types, out of the autocast list) is one line per instant cast (Effective Time 0s: off
--    the GCD, as wowsims's EffectiveTime() == 0) in the log whose
--    aura logged a "Gained {stats}" with one of those stats at the cast and that no "Major cooldown used" line or APL
--    cast (castSpell, channelSpell, castFriendlySpell) names, as a castSpell (rule 7's `use_off_gcd`). An ID nothing maps is listed, not written; none at all omits
--    the entry. Deterministic: the same log gives the same lines. Not modelled: wowsims's explosives, cast just after a
--    GCD rather than before one (the log does not type a cooldown; they read as any other).
-- 14. `strictSequence` (sim/core/apl_actions_sequences.go: ready when the GCD is within the queue window and its first
--    member is ready, its condition read once there; it then takes the rotation, each member cast as soon as it can
--    be, nothing else between, and gives it back after the last or when the GCD is ready and the next member is not)
--    is one line per member, in order, each the member's own line (rules 5-7, its own condition) whose condition also
--    says the sequence is at it: the first under the sequence's condition, each later one when the member before it
--    is the last cast, `prev.1.<key>` (the engine's cast history, upstream Hekili's: casts heard and the queue's own
--    predictions; Hekili has no sequence action), or, while that member is unlearned (wowsims drops it from the
--    sequence: rule 6), under what put the sequence at it. A later member also carries the sequence's condition
--    without the terms (of a top-level `and`, variables followed) that read a member already cast (a member's own
--    readiness is false once it is cast): two sequences sharing a first member would otherwise both open on the one
--    `prev.1`, the higher one's next member firing for the other (examples: the recipes' headers). Limit: when the
--    condition is not a top-level `and` and reads a cast member, or every term reads one, nothing is kept and two
--    such sequences sharing a first member are not told apart (none at the pin). The
--    condition's reads are all guarded (rule 6), none being the line's own. Deviations: a member is shown only once the
--    one before it is cast (wowsims holds the rotation for it, so nothing else is recommended between); a later member
--    re-reads its sequence's remaining terms, which wowsims reads once at the start, so a change between the casts can
--    stop it; a cast of a member outside the sequence also opens its next; the members must be casts (else rule 2).
-- 15. Maintenance debuffs: the recipe's `maintenance` ({ [action key] = setting key }) names a debuff (or self-buff)
--    kept up for the raid, which open-world play skips. Every emitted line whose action is that key (any list, the
--    recipe's leveling and extra lines included) is its cast line and gets `settings.<key>&` before its condition (the
--    `requires` placement); every other line's required read of its aura (the aura key is the action key:
--    `buff.`/`debuff.<key>.up`, `.remains>`/`>=`) reads "up or disabled", `(<term>|!settings.<key>)` (inside an `or`,
--    `|!settings.<key>` joins it); an absence read (`!...up`, `.remains<`) is left as is. The class registers the
--    setting with `default = false` (in game) and `sim = true` (the harness: wowsims's raid boss); the header lists it.
--    A key no line casts is an error. The rewrite is textual and reads the debuff as up while the setting is off, under
--    a negation too: right for a negated copy of another line's condition (Guardian's Lacerate lines carry
--    `!(<Berserk's condition>)`, so they still yield to a Berserk that no longer waits for the Roar); a negated group
--    of its own, `!(debuff.X.up&rage.current>10)`, also reads as if X were up (`!(rage.current>10)` with it off). No
--    pack at the pin has such a group. Not built: `.stack` reads are not rewritten, and the aura key is always the
--    action key (a debuff under another key, Fire's Scorch and `fire_vulnerability` stacks, needs both).
-- 16. An option-selected cast (a class option picks the spell, e.g. an assigned debuff): the recipe's `select`
--    ({ [wowsims action] = { setting, option, candidates = { [option value] = action key | false }, active, is } })
--    makes the option a choice setting, `settings.<setting>='<snake of the option value>'` (the script language
--    passes a quoted string through: Engine/Sim/Scripts.lua). The action is one line a candidate with a key, in the
--    option values' sorted order, each the candidate's cast line (rule 7) under the setting term and the entry's
--    condition; a `false` candidate (none) has no line. The value `active` (the selected spell's aura is up on the
--    target) is the OR over candidates with a key of (setting term & `debuff.<key>.up`), so it is false while a
--    `false` candidate is selected (wowsims's IsActive with no spell, sim/warlock/apl_values.go); each
--    candidate's term but the line's own carries its known test first, `(action.<key>.known&<term>)`, so an unlearned
--    candidate reads down, as wowsims's missing spell does, in the guard form tools/check_pack_levels.lua checks. The value `is`
--    (its one field names an option value) is that value's setting term; with no field it is the recipe's `zero`
--    (protojson omits an enum's zero value), an unknown value is unsupported. The build's value (the request's
--    `<spec>.options.classOptions.<option>` or `.options.<option>`) is the setting's default in game and in the harness
--    (`sim`), which the class registers as an AceConfig `select`; the header lists it. A build without the option holds
--    the enum's zero value (protojson omits it; re-pin: 4 of 5 warlock builds): the recipe's `zero`, the option value
--    numbered 0 in the pinned proto (each recipe cites it). An entry the APL never uses, a select with no `zero`, or a
--    build value with no candidate is an error. The value `activeAll` (the selected spell on every target) is `active`
--    on the current target, with rule 17's `# Deviation:` line.
-- 17. `multidot` (wowsims: the DoT cast on up to `maxDots` targets whose DoT has at most `maxOverlap` left) is the
--    cast's line under the entry's condition and `debuff.<key>.remains<=<maxOverlap>` (0 when absent), its aura read as
--    `dotRemainingTime` (rules 5, 6, 12; `rank` ignored, rule 5). Deviation, a `# Deviation:` header line by entry:
--    the current target only (`maxDots` unused). No `cycle_targets=1`: the engine's target cycling (State.lua SetupCycle) needs
--    other targets' DoTs (`active_dot`), which Forever does not give plainly (gap AO / AP), and the replay is one target.
--    `strictMultidot` (wowsims: the same targets, each cast re-checking the entry's condition) is the same line.
-- 18. Movement terms (re-pin plan Task 5; the design's decision 8, owner "ok"): every movement term is dropped from
--    translated conditions: run speed (`unitMovementSpeed`), "is moving" (`unitIsMoving`, any unit) and arithmetic
--    on yards (`unitDistance` inside `math`, `min`/`max`, or compared with anything but a whole-number constant). The
--    rest of the condition decides. A dropped term reads as wowsims's nil (rule 6): it leaves its `and`/`or`, and a
--    comparison or `math` over it is nil too, except that a movement addend of a sum (or the subtracted side of a
--    difference) drops alone and the rest stays (R17 refined: `cast + walk <= mainhand_remains` is
--    `action.<x>.cast<=mainhand_remains`); as a factor, a divisor or a whole side it takes the term with it. Yards are
--    a type (R17): a move's rangeFromTarget, either side of a `unitDistance` comparison and every variable feeding them
--    (transitively) are yards, and `math` over yards (a yard difference, a yard count over a speed) is a movement
--    term ("yards math"), as is each variable whose value it empties (`variable "<name>"`). This supersedes every "falls to false", "reads false" and "constant run
--    speed" text. Hekili holds only the Movement toggle, the client's range gate (rule 11's bracket, `spellInRange`)
--    and the rotation's timing terms. Each dropped term is a header line by entry,
--    `# Dropped (movement): <list> #<n>: <node>`, once an entry.
-- 19. Moves (re-pin plan Task 7; design §2.2, decisions 2, 5, 7; ruling R4): a `move` entry and a distance-only
--    `waitUntil` (its condition a rule 11 bracket, its `not`, or a spellInRange) give no line (rule 2's listing; a move
--    whose condition is unsupported says so and reaches nothing). A waitUntil's condition is held: carried, as one
--    `&` term, onto every later APL line of its list, or, when none follows (it ends its group or sequence), onto the
--    later lines of each calling list (one level; its own entry condition and a group call's are not carried).
--    A move to D yards reaches: the held gates after it in its list; and every APL line of its list and its callers'
--    lists (before or after it) whose ability cannot be cast beyond D (D a constant, or a min()/max() of constants,
--    rounded up to whole yards here): a `target.within<D>` term (one of the line's `&` terms, or of a parenthesised
--    conjunction among them), a spellInRange of an ability whose recipe `ranges` ({ [key] = { min, max } }, the
--    DB2's SpellRange) maximum is D, or, on a line with no range read, its own ability's recipe range 0-D, as a new
--    `target.within<D>` term; and, a move away, every such line that cannot be cast inside D: a `target.outside<N>`
--    with N < D, a spellInRange of an ability whose recipe minimum is below D and maximum at least D, or, on a line
--    with no range read, that recipe range as a new `target.outside<min>` term (the hunters' shots after the move
--    back to the shoot spot). Any other line is not reached. A reached line keeps its gate in place (its in-range
--    arm), and a copy of it, the move arm, with the gate as `toggle.movement&<move condition>`, goes at the move's
--    position (R51): before the first line of an entry at or after the move's (in a caller, the call's), so a line
--    wowsims ranks above the move still wins (the hunters' shots above the last-called Weave group). Arms at one
--    position keep the moves' order, then the lines'; one line's moves at one position `|`-join in one term (none
--    for an unconditional move); an arm alone right before its own line stays that one line,
--    `(toggle.movement&<move condition>|<gate>)`. The move's condition is translated by the usual rules (rule 18
--    drops its walk-time terms; a caller's line puts the call's condition before it). ON shows the line where
--    wowsims would walk to it (the client's out-of-range tint marks it); OFF leaves the bracket, so the line
--    waits for the range. An unknown bracket (no plain answer yet) still answers both sides (rule 11). Pre-pull lists
--    are never rewritten (decision 7). The header lists `# Movement: <list> #<n> reaches <list>: <actions>; ...`
--    per move that reaches a line; a spec opts into the Movement toggle (its NewClass entry's `movement = true`)
--    exactly when its pack reads `toggle.movement` (tests/Forever/packs_spec.lua). No movement icon, no wait (decision 9).
-- 14b. A `sequence` (wowsims: its members in order, each once, once per reset; design §3a) is a stepped window `<w>`
--    (the snake of its name) whose steps are its cast members: one line a cast, `<key>,if=window.<w>.next.<key>`, its
--    own condition after, consecutive equal lines once. A distance-only waitUntil member is the next cast's range gate,
--    `(toggle.movement&window.<w>.up|<gate>)` after a move member (the window is up while wowsims runs it); a trailing
--    one is held (rule 19) as `(toggle.movement&window.<w>.up|<gate>|!window.<w>.up)`, sequences sharing a gate in
--    one term; `move` and `wait` members give no line; any other member is unsupported. The sequence's condition is
--    the window's evaluator, written in the header (`# Window: <w>: steps ...; [loop;] on_deviation stay; evaluator
--    <condition>`) for the class to register (spec:RegisterWindow), only when the belief can read it (talents,
--    settings, clocks, range, known tests), else the sequence is omitted, as is every line reading its window. Its own
--    `sequenceIsComplete` is dropped there (the window opens on the evaluator's edge: once); elsewhere one is
--    `!window.<w>.up`. `resetSequence` is the window's `loop`. A strictSequence stays rule 14's chain until its lane
--    moves it (§3a).
-- One-line reads (re-pin plan, docs/superpowers/plans/2026-11-03-wowsims-repin.md, Task 3; wowsims sim/core
--    apl_values_*.go): `talentIsKnown` (wowsims's constant: the build holds that rank or a higher one) of an ID that
--    resolves to a talent (a kit talent's spell, or a recipe `map` to a talent's key, as rule 4) is
--    `talent.<key>.enabled` (a `rank` above 1: `talent.<key>.rank>=<rank>`), of one that resolves to a kit ability
--    (R52: wowsims's talent, our ability, Feral's Shifting Power) `action.<key>.known`, else false; `talentRank` is
--    `talent.<key>.rank`, else 0; `spellFullCooldown` `cooldown.<key>.duration`, `spellTravelTime`
--    `action.<key>.travel_time` and `spellGcdHastedDuration` `action.<key>.gcd` (each nil while the spell is unknown:
--    rules 6, 12); `gcdIsReady` `gcd.remains<=0` (wowsims also counts the queue window); `currentHealth`
--    `health.current` (Self only); `auraDuration` `<unit>.<key>.duration` (as `auraRemainingTime`) and
--    `dotBaseDuration` `debuff.<key>.duration` (as `dotRemainingTime`); `druidBleedIsActive` (the target's only)
--    the Druid kit's state expression `druid_bleed_active`. Re-pin plan Task 4: `spellIsCasting` is
--    `action.<key>.executing` when the kit ability has a cast time (its `cast` above 0 or unreadable), else false;
--    `spellInRange` is `action.<key>.in_range` (both rule 6 guarded, rule 12 dropped); `dotIsActiveOnAllTargets` is
--    `dotIsActive` on the current target, with rule 17's `# Deviation:` line. The second translator lane:
--    `spellIsChanneling` is `action.<key>.channeling` for a kit ability declared `channeled`, else false (CN14);
--    `frontOfTarget` and `targetIsMobType` are the request's constants, `inFrontOfTarget` (absent: false) and the
--    encounter target's `mobType` (absent: unknown, every type false), each a `# Deviation:` line where its entry
--    emits: the client gives no facing and the creature type is not read (CN16). `spellExpectedDpet` stays unsupported (no damage model: CN5, docs/dev/wowsims-packs.md), as
--    does a class's own "on all targets" read with no recipe `select` field (rule 16's `activeAll`).
--    CN4 (upstream's values after the pin): `auraIsActiveOnAllTargets` / `auraIsActiveOnAnyTarget` are the target's
--    `debuff.<key>.up` and `dotIsActiveOnAnyTarget` is `dotIsActive`, each on the current target with a `# Deviation:`
--    line (rule 17's precedent; "any" errs the other way: a DoT on another target reads down); of the current target
--    (wowsims's default unit) `targetIsActive` is true, `timeUntilTargetActive` 0 (a line is read only with the target
--    up) and `timeUntilTargetDies` `fight_remains` (one target, no despawn schedule: wowsims's fight end, as
--    `remainingTime`); another target unit is unsupported, for these and `isExecutePhase`. `numActiveAdds` (no boss/add
--    split in the engine) and `remainingCastTime` (no read mapped; no APL uses it) stay unsupported.
-- Absent enum fields (protojson omits a zero value; zeros from the pinned proto/*.proto): rule 16's option is its
-- recipe `zero`; every other enum read here has an "unknown" zero that wowsims rejects, so an absent one is
-- unsupported (`op`, math `op`: OpUnknown; `threshold`: ExecutePhaseThreshold Unknown; `autoType`: UnknownAuto, SwingType
-- Unknown) or wowsims's nil node (`totemType`: TypeUnknownTotem), and a unit reference's (UnitReference Unknown) is
-- its default unit, as sim/core/apl_helpers.go getUnit.
-- Any node not handled below is unsupported (rule 2), so a new wowsims node omits its entry rather than mistranslating.
--
-- The engine facts rule 6 rests on (tools/check_pack_levels.lua checks every pack for it):
-- - src/Hekili/Engine/Sim/State.lua `mt_default_cooldown`: for an ability `state:IsKnown` says is unknown (the
--   `if not state:IsKnown( t.key )` lines in its __index) `remains` is 0, `charges` max, `time_to_max_charges` 0, so
--   an unguarded `cooldown.X.remains>Y` is false and would block its line;
-- - State.lua `mt_default_action` answers `action.X.known`/`enabled` through `state:IsKnown` (its
--   `if k == "enabled" or k == "known"` branch), the guard's test;
-- - src/Hekili/Engine/Sim/Core.lua's list walk recommends an entry only when `ability and known and enabled` (after
--   `known, reason = self:IsSpellKnown( action )`), so a line whose own action is unlearned is skipped, never an error.
local M = {}

M.OPS = { OpEq = "=", OpNe = "!=", OpLt = "<", OpLe = "<=", OpGt = ">", OpGe = ">=" }
-- The engine's script language (Engine/Sim/Scripts.lua, as upstream) takes `/` for division and `%` for modulo;
-- SimC's `%` (division) is rewritten to `/` where SimC text enters: here, and at in-game import (Options.lua).
M.MATH = { OpAdd = "+", OpSub = "-", OpMul = "*", OpDiv = "/" }
-- Values with one translation.
M.VALUES = {
    numberTargets = "active_enemies",
    -- a banded pool reads its believed floor (border batch 2: `.lo`, `.pct_lo`; `.current` is the estimate), as every
    -- APL read did before the streams split; combo points have no band
    currentRage = "rage.lo",
    currentEnergy = "energy.lo",
    currentMana = "mana.lo",
    currentManaPercent = "mana.pct_lo",
    maxMana = "mana.max",
    currentManaRegen = "mana.regen",
    currentComboPoints = "combo_points.current",
    currentHealthPercent = "health.pct",
    currentHealth = "health.current",
    currentTime = "time",
    remainingTime = "fight_remains", -- API-forced: wowsims knows its fight length; ours answers "unknown" (3600 s)
    gcdTimeToReady = "gcd.remains",
    inputDelay = "0", -- wowsims's modelled reaction; the engine recommends without one
}

local function unsupported(what)
    error({ unsupported = what }, 0)
end

--- A name in snake_case ("Pre-pull: Stance" -> "pre_pull_stance").
function M.snake(s)
    return (s:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

-- wowsims's stat types (proto.Stat, sim/core/stats/stats.go): castAllStatBuffCooldowns's statTypeN index -> the name
-- its log's "Gained {...}" lines use.
M.STATS = {}
for i, name in ipairs({
    "Strength",
    "Agility",
    "Stamina",
    "Intellect",
    "HealingPower",
    "SpellDamage",
    "ArcaneDamage",
    "FireDamage",
    "FrostDamage",
    "HolyDamage",
    "NatureDamage",
    "ShadowDamage",
    "SpellPiercing",
    "Spirit",
    "AttackPower",
    "RangedAttackPower",
    "FeralAttackPower",
    "HitRating",
    "CritRating",
    "HasteRating",
    "ArmorPenetration",
    "ExpertiseRating",
    "DefenseRating",
    "BlockRating",
    "BlockValue",
    "DodgeRating",
    "ParryRating",
    "Armor",
    "BonusArmor",
    "Health",
    "Mana",
    "MP5",
    "ArcaneResistance",
    "FireResistance",
    "FrostResistance",
    "NatureResistance",
    "ShadowResistance",
    "PhysicalDamage",
    "ArmorNoMods",
}) do
    M.STATS[i - 1] = name
end

-- Rule 13's racials: wowsims's racial major cooldowns (sim/core/racials.go, AddMajorCooldown), in its registration
-- order (the race switch's), each { race, spell ID (Eureka!: by class, racials.go:349-363), defensive (Survival only:
-- autocast for a tank alone, sim/core/major_cooldown.go:258-263) }. Read Ley Line and Elemental Blessing are APL-only
-- (racials.go:261-264); the other races have no cooldown.
M.RACIALS = {
    { race = "RaceDwarf", id = 20594, defensive = true }, -- Stoneform, racials.go:18-48
    {
        race = "RaceGnome",
        id = {
            ClassRogue = 1259812,
            ClassWarrior = 1259813,
            ClassMage = 1259817,
            ClassWarlock = 1259821,
            ClassPriest = 1259823,
        },
    }, -- Eureka!, racials.go:344-417
    { race = "RaceNightElf", id = 1259799 }, -- Elune's Light, racials.go:61-76 (DPS: aura_helpers.go:412-428)
    { race = "RaceOrc", id = 20572 }, -- Blood Fury, racials.go:80-118
    { race = "RaceOrc", id = 1299026, defensive = true }, -- Shatter Curse, racials.go:120-160
    { race = "RaceTroll", id = 20554 }, -- Berserking, racials.go:166-197
}

-- The races each class can be (wowsims ui/sim/player/classes/capabilities_auto_gen.ts:58-68, CLASS_RACES).
M.CLASS_RACES = {}
for class, races in pairs({
    ClassWarrior = "Human Dwarf NightElf Gnome HighOrderSkyborne Orc Undead Tauren Troll WindshaperSkyborne",
    ClassPaladin = "Human Dwarf Undead",
    ClassHunter = "Human Dwarf NightElf HighOrderSkyborne Orc Tauren Troll WindshaperSkyborne",
    ClassRogue = "Human Dwarf NightElf Gnome HighOrderSkyborne Orc Undead Troll WindshaperSkyborne",
    ClassPriest = "Human Dwarf NightElf Gnome Undead Troll",
    ClassShaman = "Dwarf Orc Tauren Troll WindshaperSkyborne",
    ClassMage = "Human Gnome HighOrderSkyborne Orc Undead Troll",
    ClassWarlock = "Human Gnome Orc Undead Troll",
    ClassDruid = "NightElf HighOrderSkyborne Tauren WindshaperSkyborne",
}) do
    M.CLASS_RACES[class] = {}
    for race in races:gmatch("%a+") do
        M.CLASS_RACES[class]["Race" .. race] = true
    end
end

--- Rule 13's facts from an exported log (tools/wowsims/export.lua), our character's lines only: `mcd`, the major
--- cooldowns wowsims's autocast used ("Major cooldown used: {...}"), and `buffs`, the instant casts whose own aura
--- logged its stats ("Gained {...} from {...}." at the cast's time; instant: Effective Time 0s, off the GCD too) and that
--- are no major cooldown's, each
--- { spellId | itemId, stats = { [stat name] = true } } once, in first-use order.
function M.autocasts(text)
    local mcd, buffs, seen, instant, done, at = {}, {}, {}, {}, {}, {}
    local function id(b)
        local s, i = tonumber(b:match("SpellID: (%d+)")), tonumber(b:match("ItemID: (%d+)"))
        return (s and "spell:" .. s) or (i and "item:" .. i), { spellId = s, itemId = i }
    end
    for line in text:gmatch("[^\n]+") do
        local t, rest = line:match("^%[(%-?[%d.]+)%] %[[^%]]- %(#1%)%] (.*)$")
        if rest then
            local b = rest:match("^Major cooldown used: {([^}]*)}")
            -- wowsims's instant: DefaultCast.EffectiveTime() == 0, max(GCD, cast time) (sim/core/cast.go)
            local cast, et = rest:match("^Casting {([^}]*)} %(.-Effective Time = ([^%)]+)%)")
            local completed = rest:match("^Completed cast {([^}]*)}")
            local stats, from = rest:match("^Gained {(.-)} from {([^}]*)}%.$")
            if b then
                local k, s = id(b)
                if k and not seen[k] then
                    mcd[#mcd + 1], seen[k] = s, true
                end
            elseif cast then
                instant[id(cast) or ""] = et == "0s"
            elseif completed then
                at[id(completed) or ""] = t
            elseif stats then
                local k, s = id(from)
                if k and instant[k] and at[k] == t and not done[k] then
                    s.stats, done[k] = {}, true
                    for name in stats:gmatch('"(%w+)"') do
                        s.stats[name] = true
                    end
                    buffs[#buffs + 1] = s
                end
            end
        end
    end
    local out = {}
    for _, s in ipairs(buffs) do
        if not seen[s.spellId and "spell:" .. s.spellId or "item:" .. s.itemId] then
            out[#out + 1] = s
        end
    end
    return { mcd = mcd, buffs = out }
end

--- The translation context of an ability set (`abilities`, `auras`, `talents` as the engine registers them:
--- tests/Forever/helpers/engine.lua abilitySet), recipe `r` (map, focus, executePhase, leveling, levelingFirst, extra,
--- settings, exclusive, requires, guard, condition, maintenance, select, auras), the spec's exported log text `log` (rule 13; nil: the
--- automatic actions are unsupported), the request's player `player` (rule 16's option values; rule 13's class and
--- cooldown settings) and `tank` (the player holds a raid tank slot: rule 13's defensive racials).
function M.context(set, r, log, player, encounter, tank)
    local target = type(encounter) == "table" and type(encounter.targets) == "table" and encounter.targets[1] or {}
    local c = {
        class = type(player) == "table" and player.class, -- rule 13's racials (none without a class)
        cooldowns = type(player) == "table" and player.cooldowns or {},
        tank = tank == true,
        -- CN16 and the travel fold: the request's constants (protojson omits a zero: false, 0, MobTypeUnknown)
        inFront = type(player) == "table" and player.inFrontOfTarget == true,
        folds = {}, -- S4: this entry's CN16 fold texts (reset per entry), named on a `never` omission
        distance = type(player) == "table" and tonumber(player.distanceFromTarget) or 0,
        mobType = target.mobType,
        set = set,
        effects = {},
        autocast = log and M.autocasts(log),
        keyOf = {},
        auraOf = {},
        icdOf = {},
        stackOf = {},
        itemKey = {},
        ability = {},
        offGcd = {},
        talent = {},
        talentOf = {},
        talentKey = {},
        map = r.map or {},
        auraMap = r.auras or {},
        focus = r.focus or {},
        executePhase = r.executePhase,
        leveling = r.leveling or {},
        levelingFirst = r.levelingFirst or {},
        extra = r.extra or {},
        settings = r.settings or {},
        prepullSkip = r.prepullSkip or {},
        exclusive = r.exclusive or {},
        requires = r.requires or {},
        guard = r.guard or {},
        condition = r.condition or {}, -- rule 7: { [action key] = SimC expression }, an owner deviation's condition
        windowVars = r.windowVars or {}, -- rule 10: { [variable name] = window }, a time since read from the window
        ranges = r.ranges or {}, -- rule 19: { [action key] = { min, max } yards }, the DB2's, where the APL gives none
        maintenance = {}, -- rule 15: { { action key, setting key } }, by action key
    }
    for key, setting in pairs(r.maintenance or {}) do
        c.maintenance[#c.maintenance + 1] = { key, setting }
    end
    table.sort(c.maintenance, function(x, y)
        return x[1] < y[1]
    end)
    c.select, c.selectValue = {}, {} -- rule 16: by wowsims action; by value name -> { kind, select }
    for action, x in pairs(r.select or {}) do
        local choice
        for _, v in pairs(player or {}) do
            local o = type(v) == "table" and type(v.options) == "table" and v.options
            if o then
                choice = choice or (type(o.classOptions) == "table" and o.classOptions[x.option]) or o[x.option]
            end
        end
        if x.zero == nil or x.candidates[x.zero] == nil then
            error(("select: %s declares no zero candidate"):format(action), 0)
        end
        choice = choice == nil and x.zero or choice -- protojson omits the enum's zero value
        if x.candidates[choice] == nil then
            error(("select: %s has no candidate %s"):format(x.option, tostring(choice)), 0)
        end
        local values = {}
        for v in pairs(x.candidates) do
            values[#values + 1] = v
        end
        table.sort(values)
        local sel = { action = action, x = x, values = values, choice = choice, term = {} }
        for _, v in ipairs(values) do
            sel.term[v] = "settings." .. x.setting .. "='" .. M.snake(v) .. "'"
        end
        c.select[action] = sel
        for _, kind in ipairs({ "active", "activeAll", "is" }) do
            if x[kind] then
                c.selectValue[x[kind]] = { kind, sel }
            end
        end
    end
    local keys = {}
    for key, a in pairs(set.abilities) do
        if type(key) == "string" and type(a) == "table" and a.key == key then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local a = set.abilities[key]
        c.ability[key] = true
        c.offGcd[key] = a.gcd == "off" or nil
        for _, id in ipairs(type(a.items) == "table" and a.items or { a.item }) do
            if type(id) == "number" then
                c.itemKey[id] = c.itemKey[id] or key
            end
        end
        local list = { a.id }
        for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
            list[#list + 1] = id
        end
        for _, id in ipairs(list) do
            if type(id) == "number" then
                c.keyOf[id] = c.keyOf[id] or key
            end
        end
    end
    local akeys = {}
    for key, a in pairs(set.auras) do
        if type(key) == "string" and type(a) == "table" and type(a.id) == "number" then
            akeys[#akeys + 1] = key
        end
    end
    table.sort(akeys)
    for _, key in ipairs(akeys) do
        local a = set.auras[key]
        c.auraOf[a.id] = c.auraOf[a.id] or key
        c.stackOf[key] = type(a.max_stack) == "number" and a.max_stack or 1
        if a.icd then -- rule 9: by its own ID and by the spell wowsims names the ICD by (its proc trigger)
            c.icdOf[a.id] = key
            if a.icdSpell then
                c.icdOf[a.icdSpell] = key
            end
        end
        for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
            if type(id) == "number" then
                c.auraOf[id] = c.auraOf[id] or key
            end
        end
    end
    for key, t in pairs(set.talents or {}) do
        local aura = type(t) == "table" and c.auraOf[t[2]]
        if aura and not c.ability[aura] then
            c.talent[aura] = key
        end
        if type(t) == "table" and type(t[2]) == "number" then
            c.talentOf[t[2]], c.talentKey[key] = key, true
        end
    end
    return c
end

local SECONDS = { h = 3600, m = 60, s = 1, ms = 0.001, us = 1e-6, ns = 1e-9 } -- Go's time.ParseDuration units

-- `pct`: the constant is a direct operand of a comparison with a percent read (rule 8), so "N%" reads N, else N/100.
local function const(v, pct)
    v = tostring(v)
    if v:lower() == "true" then
        return nil, true
    elseif v:lower() == "false" then
        return nil, false
    end
    local pn = tonumber(v:match("^(%-?[%d.]+)%%$"))
    local n = pn and (pct and pn or pn / 100) or tonumber(v:match("^%-?[%d.]+$"))
    if not n and v:match("^%-?[%d.]+%a") then
        local sign, rest, sum = v:match("^(%-?)(.*)$")
        sum = 0
        local used = rest:gsub("([%d.]+)(%a+)", function(x, u)
            sum = sum + (tonumber(x) or 0 / 0) * (SECONDS[u] or 0 / 0)
            return ""
        end)
        n = used == "" and sum == sum and (sign == "-" and -sum or sum) or nil
    end
    if not n then
        unsupported("const " .. v)
    end
    return ("%g"):format(n)
end

-- A spell, item or other ID's key, or nil and what it is ("spell 123").
local function spellLookup(c, s)
    if s.spellId then
        return c.map[s.spellId] or c.keyOf[s.spellId], "spell " .. s.spellId
    elseif s.itemId then
        return c.map["item:" .. s.itemId] or c.itemKey[s.itemId], "item " .. s.itemId
    end
    return c.map[s.otherId], "other " .. tostring(s.otherId)
end

local function spellKey(c, s)
    local x, what = spellLookup(c, s)
    return x or unsupported(what)
end

-- An aura ID's key (rule 5): the recipe's maps, the set's auras, then an ability's key where the kit registers an aura
-- under it (else no aura reads it: an unregistered `debuff.<ability>` is an unknown aura to the engine; rule 12's nil).
local function auraOfId(c, id)
    local k = c.keyOf[id]
    return c.auraMap[id] or c.map[id] or c.auraOf[id] or (k and c.set.auras[k] ~= nil and k or nil)
end

local function auraKey(c, id)
    return auraOfId(c, id) or unsupported("aura " .. tostring(id))
end

local function drop(c, what, note) -- each ID once an entry; `note` replaces the default header text
    for _, d in ipairs(c.dropped) do
        if d == what then
            return
        end
    end
    c.dropped[#c.dropped + 1] = what
    c.dropNote[what] = note
end

-- Rule 12: a read of an ID nothing resolves is wowsims's nil node (its branch dropped, not the entry); the ID is noted.
local function readSpell(c, s)
    local x, what = spellLookup(c, s)
    if not x then
        drop(c, what)
    end
    return x
end

local function readAura(c, id)
    local x = auraOfId(c, id)
    if not x then
        drop(c, "aura " .. tostring(id))
    end
    return x
end

local UNIT = { Self = "buff", CurrentTarget = "debuff", Target = "debuff" }
local FLIP = { OpLe = "OpGe", OpLt = "OpGt", OpGe = "OpLe", OpGt = "OpLt", OpEq = "OpEq", OpNe = "OpNe" } -- N op d
local NEGATE = { OpLe = "OpGt", OpLt = "OpGe", OpGe = "OpLt", OpGt = "OpLe" } -- not (d op N), rule 11
local function unit(v)
    local u = v.sourceUnit and v.sourceUnit.type or "Self"
    return UNIT[u] or unsupported("unit " .. tostring(u))
end

-- The known test of key `x` (an ability's or a talent's), or nil.
local function knownTest(c, x)
    return c.ability[x] and ("action." .. x .. ".known") or (c.talent[x] and ("talent." .. c.talent[x] .. ".enabled"))
end

-- The text of "`u` is not nil".
local function present(u)
    if u.test then
        return u.test
    end
    local parts = {}
    for i, x in ipairs(u) do
        parts[i] = present(x)
    end
    return "(" .. table.concat(parts, u.op == "or" and "&" or "|") .. ")"
end

-- Rule 6's nil conditions: when a translated node is wowsims's unresolved (nil) node. `false`: never; `true`: always
-- (dropped at translation); else a formula over known tests: { test = "action.X.known" } (nil while X is unknown),
-- { op = "or", ... } (nil when any part is: a comparison, a sum), { op = "and", ... } (nil when every part is: an
-- `and`/`or` whose every term is nil).
local function nilOr(a, b)
    if a == true or b == true then
        return true
    elseif a == false then
        return b
    elseif b == false then
        return a
    end
    local out, seen = { op = "or" }, {}
    for _, u in ipairs({ a, b }) do
        for _, x in ipairs(u.op == "or" and u or { u }) do
            local k = present(x)
            if not seen[k] then
                out[#out + 1], seen[k] = x, true
            end
        end
    end
    return #out == 1 and out[1] or out
end

local function nilAnd(list)
    local out, seen = { op = "and" }, {}
    for _, u in ipairs(list) do
        if u == false then
            return false
        elseif u ~= true then
            for _, x in ipairs(u.op == "and" and u or { u }) do -- one key once, however often the terms read it
                local k = present(x)
                if not seen[k] then
                    out[#out + 1], seen[k] = x, true
                end
            end
        end
    end
    local kept = { op = "and" }
    for _, x in ipairs(out) do -- absorption: `A` with `(A or B)` is nil exactly when A is
        local absorbed = false
        for _, y in ipairs(x.op == "or" and x or {}) do
            absorbed = absorbed or (y.test ~= nil and seen[y.test] == true)
        end
        if not absorbed then
            kept[#kept + 1] = x
        end
    end
    return #kept == 0 or (#kept == 1 and kept[1]) or kept
end

-- Term `s` with nil condition `u` as wowsims evaluates it: a nil term is dropped, so it reads `want` (true in an
-- `and` and at the top, false in an `or`).
local function emit(u, s, want)
    if u == false then
        return s
    elseif u.op == "or" then -- one guard a known test, the first innermost
        for _, x in ipairs(u) do
            s = emit(x, s, want)
        end
        return s
    end
    local k = present(u)
    return want and ("(!" .. k .. "|" .. s .. ")") or ("(" .. k .. "&" .. s .. ")")
end

-- The nil condition of a read of key `x` (none for the line's own action).
local function reads(c, x)
    local test = x ~= c.self and knownTest(c, x)
    return test and { test = test } or false
end

-- Rule 8's percent reads (0-100 in the engine, 0-1 in wowsims).
M.PERCENT = { currentManaPercent = true, currentHealthPercent = true }

-- Whether value node `n` is a percent read (variables followed).
local function percentRead(c, n)
    local k, v = next(n or {})
    if k == "variableRef" then
        return c.vars[v.name] ~= nil and percentRead(c, c.vars[v.name])
    end
    return M.PERCENT[k] == true
end

-- A spell read's text by its key (rule 6 guards each: wowsims's nil while the spell is unknown).
local SPELL_FIELD = {
    spellTimeToReady = "cooldown.%s.remains",
    spellFullCooldown = "cooldown.%s.duration",
    spellCastTime = "action.%s.cast",
    spellCurrentCost = "action.%s.cost",
    spellTravelTime = "action.%s.travel_time",
    spellGcdHastedDuration = "action.%s.gcd", -- the named spell's GCD (gcd.execute is the evaluated line's)
}

-- A spell test's text by its key (rule 6 guards each).
local SPELL_TEST = {
    spellIsReady = "cooldown.%s.ready",
    spellCanCast = "action.%s.ready",
    spellInRange = "action.%s.in_range",
}

-- The kit ability's cast time in seconds (a function read under the context's state: the harness's stand-in), or nil.
local function castTime(c, key)
    local t = (c.set.abilities[key] or {}).cast or 0
    if type(t) == "function" then
        local ok, n = pcall(t)
        t = ok and n
    end
    return type(t) == "number" and t or nil
end

-- A doAtValue's seconds when it folds to a constant (constants, `math` and the kit's cast time), else nil (rule 1).
local function folded(c, n)
    local k, v = next(n)
    if k == "const" then
        return tonumber((const(v.val)))
    elseif k == "variableRef" then
        return c.vars[v.name] and folded(c, c.vars[v.name])
    elseif k == "spellCastTime" then
        local x = spellLookup(c, v.spellId)
        c.castFolded = true -- rule 1's deviation: the kit's base cast, where wowsims folds the hasted one
        return x and castTime(c, x)
    elseif k == "spellTravelTime" then
        -- wowsims: the request's distance over the spell's missile speed (0 with none); the kit's flightTime or
        -- velocity, as the engine's travel_time (State.lua), at the request's distance
        local a = c.set.abilities[spellLookup(c, v.spellId) or ""]
        if not a then
            return nil
        elseif type(a.flightTime) == "number" then
            return a.flightTime
        end
        return type(a.velocity) == "number" and a.velocity > 0 and c.distance / a.velocity or 0
    elseif k == "spellGcdHastedDuration" then
        local a = c.set.abilities[spellLookup(c, v.spellId) or ""]
        if not a then
            return nil
        end
        c.gcdFolded = true -- rule 1's deviation: the kit's unhasted GCD, where wowsims folds the hasted one
        -- shortcut: the engine's 1 s GCD of a "spell" press for a one_sec_gcd class (State.lua mt_gcd) reads 1.5 here;
        -- no pre-pull entry at the pin or upstream times by such a GCD. Upgrade if one does.
        -- An off-GCD spell reads wowsims's floor, max(1 s, its hasted 0 s) (sim/core/apl_values_spell.go:402-409); wowsims
        -- reads 0 only for a spell that ignores haste, which the kit cannot tell.
        return type(a.gcdTime) == "number" and a.gcdTime or (a.gcd == "off" and 1) or (a.gcd == "totem" and 1) or 1.5
    elseif k == "math" then
        local l, r = folded(c, v.lhs or {}), folded(c, v.rhs or {})
        if not (l and r) then
            return nil
        elseif v.op == "OpAdd" then
            return l + r
        elseif v.op == "OpSub" then
            return l - r
        elseif v.op == "OpMul" then
            return l * r
        elseif v.op == "OpDiv" and r ~= 0 then
            return l / r
        end
    end
end

-- An entry folded to never: "never", with the request constants it folded (CN16), so the header keeps the reason.
local function never(c)
    local seen, out = {}, {}
    for _, d in ipairs(c.folds or {}) do
        if not seen[d] then
            seen[d], out[#out + 1] = true, (d:gsub("%.$", ""))
        end
    end
    return #out > 0 and "never: " .. table.concat(out, "; ") .. "." or "never"
end

-- Records deviation `d` for the entry once (rule 17).
local function deviate(c, d)
    for _, x in ipairs(c.deviations) do
        if x == d then
            return
        end
    end
    c.deviations[#c.deviations + 1] = d
end
local ALL_TARGETS = 'an "on all targets" read is the current target\'s only.'
local ANY_TARGET = 'an "on any target" read is the current target\'s only.'

-- CN4: a value or test of a target unit (wowsims's default, the current target) reads only the current target here.
local function currentTarget(k, v)
    local u = v.targetUnit and v.targetUnit.type or "CurrentTarget"
    if u ~= "CurrentTarget" then
        unsupported(k .. " of " .. tostring(u))
    end
end
local FACING = "frontOfTarget is the request's in-front setting (%s the target); the client gives no facing."
local MOB_TYPE = "targetIsMobType is the request's target type (%s); the client's creature type is not read."
local PREPULL_CAST = "the pre-pull time uses the kit's base cast time; wowsims uses the hasted cast."
local PREPULL_GCD =
    "the pre-pull time uses the kit's unhasted GCD (1 s off the GCD, wowsims's floor); wowsims uses the hasted GCD."

-- Rule 18: a movement term of kind `kind`, recorded once an entry; returns wowsims's nil.
local function moved(c, kind)
    c.movedN = (c.movedN or 0) + 1 -- every drop, a repeat too: a variable's read tells a movement nil by it
    for _, x in ipairs(c.moves) do
        if x == kind then
            return nil, true
        end
    end
    c.moves[#c.moves + 1] = kind
    return nil, true
end

-- Rule 18 (R17): whether value node `n` is yards: a yards variable (c.yards: what a move's rangeFromTarget or a
-- unitDistance comparison reads, transitively), or a min()/max()/math of one. unitDistance itself is its own term.
local function isYards(c, n)
    if type(n) ~= "table" then
        return false
    elseif n.variableRef then
        return c.yards[n.variableRef.name] == true
    end
    local m = n.min or n.max
    if m then
        for _, x in ipairs(m.vals or {}) do
            if isYards(c, x) then
                return true
            end
        end
        return false
    end
    return n.math ~= nil and (isYards(c, n.math.lhs) or isYards(c, n.math.rhs))
end

-- Rule 18 (R17): every variable node `n` reads (through variables) is yards.
local function markYards(c, n)
    if type(n) ~= "table" then
        return
    elseif n.variableRef then
        local name = n.variableRef.name
        if name and not c.yards[name] then
            c.yards[name] = true
            markYards(c, c.vars[name])
        end
        return
    end
    for _, x in pairs(n) do
        markYards(c, x)
    end
end

-- Rule 18 (R17): marks the yards variables under node `n`: a move's rangeFromTarget, either side of a unitDistance cmp.
local function findYards(c, n)
    if type(n) ~= "table" then
        return
    end
    if n.move and n.move.rangeFromTarget then
        markYards(c, n.move.rangeFromTarget)
    end
    if n.cmp and (n.cmp.lhs and n.cmp.lhs.unitDistance or n.cmp.rhs and n.cmp.rhs.unitDistance) then
        markYards(c, n.cmp.lhs)
        markYards(c, n.cmp.rhs)
    end
    for _, x in pairs(n) do
        findYards(c, x)
    end
end

-- Rule 18 (R17): variable `name`'s read came out nil from a movement term (c.movedN grew past n0): it is one too.
local function movedVar(c, name, n0, u)
    if u == true and (c.movedN or 0) > n0 then
        moved(c, ('variable "%s"'):format(name))
    end
end

-- A talent ID's key (a kit talent's spell, or a recipe `map` to a talent's key), or nil.
local function talentOf(c, id)
    id = id and id.spellId
    local x = c.talentOf[id] or c.map[id]
    return (c.talentOf[id] or c.talentKey[x]) and x or nil
end

-- The clock prefix of an `autoTimeSinceLast` hand.
local SINCE = { MainHandAuto = "mainhand", RangedAuto = "ranged" }
-- The clock prefix of an `autoSwingTime` hand.
local SWING = { MainHand = "mainhand", OffHand = "offhand", Ranged = "ranged" }

-- The clock prefix when node `n` is a time since the last swing or shot (variables followed), else nil.
local function sinceHand(c, n)
    if type(n) ~= "table" then
        return nil
    elseif n.variableRef then
        return sinceHand(c, c.vars[n.variableRef.name])
    end
    return n.autoTimeSinceLast and SINCE[n.autoTimeSinceLast.autoType]
end

-- A value: its text and nil condition (`true`: nil, no text). `pct`: compared directly with a percent read (rule 8).
local function value(c, n, pct)
    local k, v = next(n)
    if k == nil then
        return nil, true -- an empty value
    elseif k == "const" then
        local s = const(v.val, pct)
        if s == nil then
            unsupported("boolean as a value")
        end
        return s, false
    elseif M.VALUES[k] then
        local u = v.sourceUnit and v.sourceUnit.type or "Self"
        local res = u == "Pet" and M.VALUES[k]:match("^(%a+)%.lo$") -- the pet's power: the sim's pet.<resource> (no band)
        if res then
            return "pet." .. res, false
        elseif u ~= "Self" then
            unsupported(k .. " of " .. tostring(u))
        end
        return M.VALUES[k], false
    elseif k == "variableRef" then
        local n0 = c.movedN or 0
        local s, u = value(c, c.vars[v.name] or unsupported("variable " .. v.name), pct)
        movedVar(c, v.name, n0, u)
        return s, u
    elseif k == "unitMovementSpeed" or k == "unitDistance" then -- rule 18 (rule 11 compares yards in bool())
        return moved(c, k)
    elseif k == "math" and (isYards(c, v.lhs) or isYards(c, v.rhs)) then -- rule 18 (R17): a walk time is one
        return moved(c, "yards math")
    elseif k == "math" then
        if percentRead(c, v.lhs) or percentRead(c, v.rhs) then -- its 0-100 against wowsims's 0-1 leaks (rule 8)
            unsupported("a percent read in math")
        end
        local n0 = c.movedN or 0
        local l, lu = value(c, v.lhs)
        local n1 = c.movedN or 0
        local r, ru = value(c, v.rhs)
        local op = M.MATH[v.op] or unsupported("math " .. tostring(v.op))
        -- rule 18 (R17 refined): a movement addend drops alone, the rest of the sum stays (`cast + walk` is `cast`);
        -- as a factor or divisor, or a difference's left side, it takes the whole term with it
        if ru == true and lu ~= true and (c.movedN or 0) > n1 and (v.op == "OpAdd" or v.op == "OpSub") then
            return l, lu
        elseif lu == true and ru ~= true and n1 > n0 and v.op == "OpAdd" then
            return r, ru
        end
        local u = nilOr(lu, ru)
        if u == true then
            return nil, true
        end
        return "(" .. l .. op .. r .. ")", u
    elseif k == "min" or k == "max" then -- wowsims's newValueMin/Max: a nil term dropped, nil when every term is
        local parts, us = {}, {}
        for _, x in ipairs(v.vals or {}) do
            if percentRead(c, x) then
                unsupported("a percent read in " .. k)
            end
            local s, u = value(c, x, pct)
            if u ~= true then
                parts[#parts + 1], us[#us + 1] = s, u
            end
        end
        if #parts == 0 then
            return nil, true
        elseif #parts == 1 then
            return parts[1], us[1]
        end
        for i, s in ipairs(parts) do
            parts[i] = emit(us[i], s, false) -- `(<known>&<term>)`: false while unlearned, which min()/max() skip
        end
        return k .. "(" .. table.concat(parts, ",") .. ")", nilAnd(us)
    elseif SPELL_FIELD[k] then
        local x = readSpell(c, v.spellId)
        if not x then
            return nil, true
        end
        return SPELL_FIELD[k]:format(x), reads(c, x)
    elseif k == "talentRank" then -- wowsims: the build's rank, 0 without points
        local t = talentOf(c, v.talentId)
        return t and ("talent." .. t .. ".rank") or "0", false
    elseif k == "dotRemainingTime" or k == "dotBaseDuration" then
        local a = readAura(c, v.spellId.spellId)
        if not a then
            return nil, true
        end
        return "debuff." .. a .. (k == "dotBaseDuration" and ".duration" or ".remains"), reads(c, a)
    elseif k == "auraRemainingTime" or k == "auraNumStacks" or k == "auraDuration" then
        if v.auraId.tag == -1 then
            return nil, true -- rule 4: another player's aura, never registered
        end
        local a = readAura(c, v.auraId.spellId)
        if not a then
            return nil, true
        end
        local field = k == "auraNumStacks" and ".stack" or (k == "auraDuration" and ".duration" or ".remains")
        return unit(v) .. "." .. a .. field, reads(c, a)
    elseif k == "autoSwingTime" and SWING[v.autoType] then -- rule 10
        return SWING[v.autoType] .. "_speed", false
    elseif k == "autoTimeToNext" and v.autoType == "MainHandAuto" then
        return "mainhand_remains", false
    elseif k == "autoTimeToNext" and v.autoType == "RangedAuto" then -- the ranged auto-shot clock (C7)
        return "ranged_remains", false
    elseif k == "autoTimeToNext" and (v.autoType == "MeleeAuto" or v.autoType == "AnyAuto") then
        -- translator-5: wowsims's earlier hand (NextAttackAt), AnyAuto with the ranged shot too (NextAnyAttackAt), each
        -- the kit's clock; a hand with no weapon never swings (wowsims's NeverExpires): its clock reads 3600 s, so
        -- min() takes the other; AnyAuto's ranged clock only where the kit has one (no ranged auto: never)
        local clocks, hands = c.set.stateExprs or {}, { "mainhand_remains", "offhand_remains" }
        for _, h in ipairs(hands) do
            if not clocks[h] then
                unsupported("autoTimeToNext " .. v.autoType .. ": the kit has no " .. h)
            end
        end
        if v.autoType == "AnyAuto" and clocks.ranged_remains then
            hands[3] = "ranged_remains"
        end
        return "min(" .. table.concat(hands, ",") .. ")", false
    elseif k == "autoTimeSinceLast" and SINCE[v.autoType] then -- inside math; compared, cmp's remains form
        return "(" .. SINCE[v.autoType] .. "_speed-" .. SINCE[v.autoType] .. "_remains)", false
    elseif k == "timeUntilTargetActive" then -- CN4: the current target is up while a line reads it
        currentTarget(k, v)
        return "0", false
    elseif k == "timeUntilTargetDies" then -- CN4: one target, no schedule: wowsims's fight end, as remainingTime
        currentTarget(k, v)
        return M.VALUES.remainingTime, false
    elseif k == "totemRemainingTime" then
        if v.totemType == nil then -- TypeUnknownTotem (0, proto/shaman.proto): wowsims's nil node
            return nil, true
        end
        return "totem." .. M.snake(tostring(v.totemType)):gsub("^totem_", "") .. ".remains", false
    end
    unsupported(tostring(k))
end

-- Whether `s` is one parenthesised group from its first character to its last.
local function grouped(s)
    if s:sub(1, 1) ~= "(" then
        return false
    end
    local depth = 0
    for i = 1, #s do
        local ch = s:sub(i, i)
        depth = depth + (ch == "(" and 1 or ch == ")" and -1 or 0)
        if depth == 0 then
            return i == #s
        end
    end
    return false
end

-- Whether node `n` reads a unitDistance (variables followed).
local function hasDistance(c, n)
    if type(n) ~= "table" then
        return false
    elseif n.unitDistance then
        return true
    elseif n.variableRef and c.vars[n.variableRef.name] then
        return hasDistance(c, c.vars[n.variableRef.name])
    end
    for _, x in pairs(n) do
        if hasDistance(c, x) then
            return true
        end
    end
    return false
end

-- A condition: its text, constant (when it folds) and nil condition, as wowsims builds it (sim/core
-- apl_values_operators.go): a nil child of `and`/`or` is dropped and one whose every child is nil is nil; `not`,
-- `cmp` and `math` of a nil are nil; a constant `false` in an `and` (`true` in an `or`) decides it.
local function bool(c, n)
    local k, v = next(n)
    if k == nil then
        return nil, nil, true -- an empty value
    elseif k == "and" or k == "or" then
        local absorb, kids, identity = k == "or", {}, false
        for _, x in ipairs(v.vals or {}) do
            local s, b, u = bool(c, x)
            if u ~= true then
                if b == absorb then
                    return nil, absorb, false
                elseif b == nil then
                    kids[#kids + 1] = { s, u }
                else
                    identity = true
                end
            end
        end
        if #kids == 0 then
            if identity then
                return nil, not absorb, false
            end
            return nil, nil, true
        elseif #kids == 1 and not identity then
            return kids[1][1], nil, kids[1][2] -- wowsims's one-child and/or is the child
        end
        local parts, us, seen = {}, {}, {}
        for _, kid in ipairs(kids) do
            local part = emit(kid[2], kid[1], k == "and")
            if not seen[part] then -- `A|A` and `A&A` are A (two ranks' auraIsKnown of one talent)
                parts[#parts + 1], us[#us + 1], seen[part] = part, kid[2], true
            end
        end
        if #parts == 1 and not identity then
            return kids[1][1], nil, kids[1][2]
        end
        local s = #parts == 1 and parts[1] or ("(" .. table.concat(parts, k == "and" and "&" or "|") .. ")")
        return s, nil, (not identity) and nilAnd(us)
    elseif k == "not" then
        local r = v.val
        while r and r.variableRef and c.vars[r.variableRef.name] do
            r = c.vars[r.variableRef.name]
        end
        if
            r
            and r.cmp
            and NEGATE[r.cmp.op]
            and (r.cmp.lhs and r.cmp.lhs.unitDistance or r.cmp.rhs and r.cmp.rhs.unitDistance)
        then
            -- rule 11: the opposite bracket (an unknown distance answers both, so `!` of one would block the line)
            return bool(c, { cmp = { op = NEGATE[r.cmp.op], lhs = r.cmp.lhs, rhs = r.cmp.rhs } })
        elseif r and (r["not"] or r["and"] or r["or"]) and hasDistance(c, r) then
            -- rule 11 through a `not`: a double `not` is its operand, a `not` of and/or goes inside (De Morgan), so
            -- each bracket is negated as above (wowsims's nil rules agree: `not` of nil is nil)
            if r["not"] then
                return bool(c, r["not"].val)
            end
            local vals = {}
            for i, x in ipairs((r["and"] or r["or"]).vals or {}) do
                vals[i] = { ["not"] = { val = x } }
            end
            return bool(c, { [r["and"] and "or" or "and"] = { vals = vals } })
        end
        local s, b, u = bool(c, v.val)
        if u == true then
            return nil, nil, true
        elseif b ~= nil then
            return nil, not b, false
        end
        return (s:match("^[%w_.]+$") or grouped(s)) and ("!" .. s) or ("!(" .. s .. ")"), nil, u
    elseif k == "const" then
        local _, b = const(v.val)
        if b == nil then
            unsupported("number as a condition")
        end
        return nil, b, false
    elseif k == "cmp" and (v.lhs and v.lhs.unitDistance or v.rhs and v.rhs.unitDistance) then -- rule 11
        local flip = not (v.lhs and v.lhs.unitDistance)
        local n = value(c, flip and v.lhs or v.rhs)
        local op = flip and FLIP[v.op] or v.op
        local side = (op == "OpLe" or op == "OpLt") and "within" or ((op == "OpGe" or op == "OpGt") and "outside")
        if not (n and n:match("^%d+$")) then
            moved(c, "unitDistance") -- rule 18: yards against anything but a whole number
            return nil, nil, true
        elseif not side then
            unsupported("unitDistance " .. tostring(v.op) .. " " .. tostring(n))
        end
        return "target." .. side .. n, nil, false
    elseif k == "cmp" and (sinceHand(c, v.lhs) or sinceHand(c, v.rhs)) then
        -- the time since in remains form, since = speed - remains, so the recheck's clock branches forecast it (R6):
        -- `since op x` is `remains FLIP(op) speed-x`, `x op since` is `remains op speed-x`
        local left = sinceHand(c, v.lhs) ~= nil
        local h = sinceHand(c, left and v.lhs or v.rhs)
        local x, u = value(c, left and v.rhs or v.lhs)
        if u == true then
            return nil, nil, true
        end
        local op = M.OPS[left and FLIP[v.op] or v.op] or unsupported("op " .. tostring(v.op))
        if not (x:match("^[%w_.]+$") or grouped(x)) then
            x = "(" .. x .. ")"
        end
        return h .. "_remains" .. op .. h .. "_speed-" .. x, nil, u
    elseif k == "cmp" then
        local l, lu = value(c, v.lhs, percentRead(c, v.rhs))
        local r, ru = value(c, v.rhs, percentRead(c, v.lhs))
        local op = M.OPS[v.op] or unsupported("op " .. tostring(v.op))
        local u = nilOr(lu, ru)
        if u == true then
            return nil, nil, true
        end
        return l .. op .. r, nil, u
    elseif k == "auraIsActive" then
        if v.auraId.tag == -1 then
            return nil, nil, true -- rule 4: another player's aura, never registered
        end
        local a = readAura(c, v.auraId.spellId)
        if not a then
            return nil, nil, true
        end
        return unit(v) .. "." .. a .. ".up", nil, reads(c, a)
    elseif k == "auraIsInactive" then
        return bool(c, { ["not"] = { val = { auraIsActive = v } } })
    elseif k == "auraIsKnown" then -- rule 4
        local id = v.auraId and v.auraId.spellId
        if not UNIT[v.sourceUnit and v.sourceUnit.type or "Self"] or not id or v.auraId.tag == -1 then
            return nil, false, false
        end
        local x = c.auraMap[id] or c.map[id] or c.talentOf[id] or c.auraOf[id] or c.keyOf[id]
        if not x then
            local what = "auraIsKnown of the unresolved aura " .. tostring(id)
            drop(c, what, what .. " folds false") -- rule 4: noted, so the fold is not silent
            return nil, false, false
        end
        local tk = c.talentOf[id] or (c.talentKey[x] and x) -- a talent's spell, or a recipe `map` to a talent's key
        local test = tk and ("talent." .. tk .. ".enabled") or knownTest(c, x)
        if not test then
            return nil, true, false
        end
        return test, nil, false
    elseif k == "talentIsKnown" then -- wowsims: a constant, the build holds the rank or a higher one
        local t = talentOf(c, v.talentId)
        if not t then
            local x = spellLookup(c, v.talentId) -- R52: wowsims's talent the kit has as an ability (Shifting Power)
            if x and c.ability[x] then
                return "action." .. x .. ".known", nil, false
            end
            return nil, false, false
        end
        local rank = v.talentId.rank or 1
        return rank > 1 and ("talent." .. t .. ".rank>=" .. rank) or ("talent." .. t .. ".enabled"), nil, false
    elseif k == "multipleCdUsages" then -- R42: wowsims's GetBool without a base spell (apl_values_misc.go:69-86)
        if v.baseSpellId and next(v.baseSpellId) then
            unsupported("multipleCdUsages with a base spell")
        end
        if not v.alignCdEnd then
            return nil, true, false
        end
        local id = v.targetSpellId and v.targetSpellId.spellId
        if not id then
            unsupported("multipleCdUsages of " .. tostring(next(v.targetSpellId or {})))
        end
        -- remaining <= D | remaining > CD + D/2 (D: the spell's own buff), on rule 10's `fight_remains`
        local left, d = { remainingTime = {} }, { auraDuration = { auraId = { spellId = id } } }
        local half = { math = { op = "OpDiv", lhs = d, rhs = { const = { val = "2" } } } }
        local cd = { math = { op = "OpAdd", lhs = { spellFullCooldown = { spellId = { spellId = id } } }, rhs = half } }
        return bool(c, {
            ["or"] = {
                vals = {
                    { cmp = { op = "OpLe", lhs = left, rhs = d } },
                    { cmp = { op = "OpGt", lhs = left, rhs = cd } },
                },
            },
        })
    elseif k == "gcdIsReady" then
        return "gcd.remains<=0", nil, false
    elseif k == "sequenceIsComplete" then -- rule 14b: the sequence's window down; in its own condition, the edge's once
        local w = M.snake(v.sequenceName or "")
        if w == c.ownSeq then
            return nil, nil, true
        end
        return "!window." .. w .. ".up", nil, false
    elseif k == "unitIsMoving" then -- rule 18, any unit
        moved(c, k)
        return nil, nil, true
    elseif k == "druidBleedIsActive" then -- the Druid kit's state expression (its bleeds on the target)
        local u = v.targetUnit and v.targetUnit.type or "CurrentTarget"
        if UNIT[u] ~= "debuff" then
            unsupported("druidBleedIsActive of " .. tostring(u))
        end
        return "druid_bleed_active", nil, false
    elseif k == "auraShouldRefresh" then -- rule 10
        local id = v.auraId.spellId
        if not c.exclusive[id] then
            unsupported("auraShouldRefresh " .. tostring(id) .. " (no exclusive effect declared)")
        end
        local a = readAura(c, id)
        if not a then
            return nil, nil, true
        end
        local un = v.sourceUnit and unit(v) or "debuff" -- wowsims reads it on the target by default
        local overlap, ou = "0", false
        if v.maxOverlap then
            overlap, ou = value(c, v.maxOverlap)
        end
        local u = nilOr(reads(c, a), ou)
        if u == true then
            return nil, nil, true
        end
        local atom = un .. "." .. a .. ".remains<=" .. overlap
        if c.stackOf[a] and c.stackOf[a] > 1 then
            atom = "(" .. atom .. "|" .. un .. "." .. a .. ".stack<" .. c.stackOf[a] .. ")"
        end
        return atom, nil, u
    elseif k == "auraIcdIsReady" then -- rule 9
        if unit(v) ~= "buff" then
            unsupported("auraIcdIsReady of " .. tostring(v.sourceUnit.type))
        end
        local id = v.auraId and v.auraId.spellId
        local a = c.icdOf[id]
        if not a and not (c.auraMap[id] or c.map[id] or c.auraOf[id] or c.keyOf[id]) then
            readAura(c, id)
            return nil, nil, true
        end
        a = a or unsupported("auraIcdIsReady " .. tostring(id))
        local tk = c.talentOf[id] -- nil (dropped) while the proc's talent is untaken, as wowsims's unregistered aura
        return "buff." .. a .. ".icd_ready", nil, tk and { test = "talent." .. tk .. ".enabled" } or false
    elseif k == "dotIsActive" then
        local a = readAura(c, v.spellId.spellId)
        if not a then
            return nil, nil, true
        end
        return "debuff." .. a .. ".up", nil, reads(c, a)
    elseif k == "dotIsActiveOnAllTargets" then -- rule 17's precedent: the current target only
        deviate(c, ALL_TARGETS)
        return bool(c, { dotIsActive = v })
    elseif k == "dotIsActiveOnAnyTarget" or k == "auraIsActiveOnAllTargets" or k == "auraIsActiveOnAnyTarget" then
        -- CN4, rule 17's precedent: the current target only, noted when the read resolves
        local n = k == "dotIsActiveOnAnyTarget" and { dotIsActive = v }
            or { auraIsActive = { auraId = v.auraId, sourceUnit = { type = "CurrentTarget" } } }
        local s, b, u = bool(c, n)
        if u ~= true then
            deviate(c, k == "auraIsActiveOnAllTargets" and ALL_TARGETS or ANY_TARGET)
        end
        return s, b, u
    elseif k == "targetIsActive" then -- CN4: the current target is up while a line reads it
        currentTarget(k, v)
        return nil, true, false
    elseif SPELL_TEST[k] or k == "spellIsCasting" or k == "spellIsChanneling" then
        local x = readSpell(c, v.spellId)
        if not x then
            return nil, nil, true
        elseif k == "spellIsCasting" and castTime(c, x) == 0 then
            return nil, false, false -- an instant is never mid-cast
        elseif k == "spellIsChanneling" and not c.set.abilities[x].channeled then
            return nil, false, false -- CN14: only a channeled spell is ever channeling
        end
        local f = SPELL_TEST[k] or (k == "spellIsCasting" and "action.%s.executing" or "action.%s.channeling")
        return f:format(x), nil, reads(c, x)
    elseif k == "frontOfTarget" then -- CN16: the request's setting, a constant (the client gives no facing)
        local d = FACING:format(c.inFront and "in front of" or "behind")
        deviate(c, d)
        c.folds[#c.folds + 1] = d -- S4: an entry this fold empties keeps the reason on its `never`
        return nil, c.inFront, false
    elseif k == "targetIsMobType" then -- CN16: the request's target type, a constant (creature type is not read)
        if c.mobType then
            local d = MOB_TYPE:format((tostring(c.mobType):gsub("^MobType", ""):lower()))
            deviate(c, d)
            c.folds[#c.folds + 1] = d
        end
        return nil, c.mobType ~= nil and v.mobType == c.mobType, false
    elseif k == "spellIsKnown" then -- wowsims: a constant, false for a spell it lacks; ours for an ID nothing resolves
        local x = spellLookup(c, v.spellId)
        if not x then
            return nil, false, false
        end
        return "action." .. x .. ".known", nil, false
    elseif k == "isExecutePhase" then
        currentTarget(k, v)
        if v.threshold == "E20" and c.executePhase then
            return c.executePhase, nil, false
        end
        unsupported("isExecutePhase " .. tostring(v.threshold))
    elseif k == "actionGroupUsed" then
        if c.toggles[v.name] then
            return "settings." .. c.toggles[v.name], nil, false
        end
        if c.groupUsed[v.name] == nil then
            unsupported("actionGroupUsed " .. tostring(v.name))
        end
        return nil, c.groupUsed[v.name], false -- rule 3: wowsims's constant, a shown reference to the group exists
    elseif k == "variableRef" and c.windowVars[v.name] then -- rule 10: a time since read from the recipe's window
        c.keyUsed["windowVars:" .. v.name] = true
        local w, cm = c.windowVars[v.name], c.vars[v.name] and c.vars[v.name].cmp
        local left = cm and sinceHand(c, cm.lhs) ~= nil
        if not (cm and (left or sinceHand(c, cm.rhs))) then
            unsupported("windowVars " .. v.name .. ": no comparison on a time since")
        end
        local x, u = value(c, left and cm.rhs or cm.lhs)
        if u == true then
            return nil, nil, true
        end
        local op = M.OPS[left and cm.op or FLIP[cm.op]] or unsupported("op " .. tostring(cm.op))
        if op == "<" and x == "0" then
            return nil, false, false -- elapsed<0 is never true (wowsims's input delay, 0 here): folded false
        end
        if not (x:match("^[%w_.]+$") or grouped(x)) then
            x = "(" .. x .. ")"
        end
        return "(window." .. w .. ".up&window." .. w .. ".elapsed" .. op .. x .. ")", nil, u
    elseif k == "variableRef" then
        local n0 = c.movedN or 0
        local s, b, u = bool(c, c.vars[v.name] or unsupported("variable " .. v.name))
        movedVar(c, v.name, n0, u)
        return s, b, u
    elseif c.selectValue[k] then -- rule 16
        local kind, sel = c.selectValue[k][1], c.selectValue[k][2]
        sel.used = true
        if kind == "is" then
            local _, val = next(v)
            val = val == nil and sel.x.zero or val -- protojson omits the enum's zero value
            return sel.term[val] or unsupported(k .. " of " .. tostring(val)), nil, false
        end
        if kind == "activeAll" then -- rule 17's precedent: the current target only
            deviate(c, ALL_TARGETS)
        end
        local parts = {}
        for _, val in ipairs(sel.values) do
            local key = sel.x.candidates[val] -- none (false): wowsims's IsActive with no spell is false, no term
            if key then
                local test = key ~= c.self and knownTest(c, key) -- an unlearned candidate's term reads false
                parts[#parts + 1] = "(" .. (test and test .. "&" or "") .. sel.term[val] .. "&debuff." .. key .. ".up)"
            end
        end
        if #parts == 0 then
            return nil, false, false
        end
        return "(" .. table.concat(parts, "|") .. ")", nil, false
    end
    unsupported(tostring(k))
end

-- Rule 7's required talent of `key` before condition `cond` (either may be nil).
local function required(c, key, cond)
    local talent = c.requires[key]
    if not talent then
        return cond
    end
    c.keyUsed["requires:" .. key] = true
    if not c.talentKey[talent] then
        error(("requires: %s is not a talent key"):format(tostring(talent)), 0)
    end
    local t = "talent." .. talent .. ".enabled"
    if cond then -- already one of its top-level `&` terms: not twice
        local top, depth, from, has = grouped(cond) and cond:sub(2, -2) or cond, 0, 1, false
        for i = 1, #top + 1 do
            local ch = top:sub(i, i)
            depth = depth + (ch == "(" and 1 or ch == ")" and -1 or 0)
            if depth == 0 and ch == "|" then
                has = false -- an `|` at the top: not an `&` of terms
                break
            elseif depth == 0 and (ch == "&" or ch == "") then
                has, from = has or top:sub(from, i - 1) == t, i + 1
            end
        end
        if has then
            return cond
        end
    end
    return cond and (t .. "&" .. ((grouped(cond) or not cond:find("|", 1, true)) and cond or "(" .. cond .. ")")) or t
end

-- Rule 15's maintenance of line body `body` (an emitted line, its condition after `,if=`); marks each key cast in `cast`.
local function maintained(c, body, cast)
    local head, cond = body:match("^(.-),if=(.*)$")
    head = head or body
    local action = body:match("^[%w_]+")
    for _, m in ipairs(c.maintenance) do
        local key, s = m[1], "settings." .. m[2]
        if action == key then
            cast[key] = true
            cond = cond
                    and (s .. "&" .. ((grouped(cond) or not cond:find("|", 1, true)) and cond or "(" .. cond .. ")"))
                or s
        elseif cond then
            -- (kind).<key>.(field)(op)(rhs), with what precedes it (`!` or not) and its bounds
            local pat = "()(!?)%f[%w_]((%a+)%." .. key .. "%.([%w_]+)([<>=]*)([%w_.]*))()"
            cond = cond:gsub(pat, function(i, neg, term, kind, field, op, rhs, j)
                local wanted = neg == ""
                    and (kind == "buff" or kind == "debuff")
                    and (
                        (field == "up" and op == "") or (field == "remains" and (op == ">" or op == ">=") and rhs ~= "")
                    )
                if not wanted then
                    return nil
                end
                if cond:sub(j, j):find("[%+%-%*/%%]") then
                    error(("maintenance: cannot rewrite %s before arithmetic"):format(term), 0)
                end
                local p, n = cond:sub(i - 1, i - 1), cond:sub(j, j)
                if
                    (p == "|" or p == "(" or p == "")
                    and (n == "|" or n == ")" or n == "")
                    and (p == "|" or n == "|")
                then
                    return term .. "|!" .. s
                end
                return "(" .. term .. "|!" .. s .. ")"
            end)
        end
    end
    return cond and (head .. ",if=" .. cond) or head
end

-- Rule 13: the keys of the cooldowns wowsims's automatic action `kind` cast in the log (`c.autocast`), in first-use
-- order, each once; an ID nothing maps is noted.
local function automatic(c, kind, v)
    local log = c.autocast or unsupported(kind .. " (no log)")
    local list = log.mcd
    if kind == "castAllStatBuffCooldowns" then
        local want = {}
        for _, n in ipairs({ v.statType1 or 0, v.statType2 or 0, v.statType3 or 0 }) do -- proto's default 0, Strength
            if M.STATS[n] then
                want[M.STATS[n]] = true
            end
        end
        list = {}
        for _, b in ipairs(log.buffs) do
            local hit = false
            for name in pairs(b.stats) do
                hit = hit or want[name] == true
            end
            if hit and not c.named[(b.spellId and "spell:" or "item:") .. (b.spellId or b.itemId)] then
                list[#list + 1] = b
            end
        end
    end
    -- the class's racial cooldowns autocast would use (M.RACIALS), placed as a block where the sampled race's racial
    -- was first used, else first (racials register before any other cooldown, character.go:304, all priority 0)
    local block, racial, placed = {}, {}, kind ~= "autocastOtherCooldowns" or not c.class
    for _, rc in ipairs(placed and {} or M.RACIALS) do
        local id = rc.id
        if type(id) == "table" then
            id = id[c.class]
        end
        local x, what
        if id then
            x, what = spellLookup(c, { spellId = id })
        end
        if (M.CLASS_RACES[c.class] or {})[rc.race] and id and (c.tank or not rc.defensive) then
            if next(c.cooldowns.cooldowns or {}) then -- timings: autocast at those times only (major_cooldown.go:122)
                error("rule 13: the player's cooldown timings are not modelled", 0)
            elseif rc.defensive and (tonumber(c.cooldowns.hpPercentForDefensives) or 0) ~= 0 then -- :126-130
                error("rule 13: the player's hpPercentForDefensives is not modelled", 0)
            elseif not x then
                c.notes[#c.notes + 1] = kind .. ": unmapped " .. what
            elseif not c.namedKeys[x] then -- one the APL casts is no autocast cooldown (sim/core/apl.go:333-340)
                block[#block + 1] = x
            end
        end
        racial[x or ""] = true
    end
    local keys, seen = {}, {}
    for _, s in ipairs(list) do
        local x, what = spellLookup(c, s)
        if x and racial[x] and not placed then
            placed = true
            for _, y in ipairs(block) do
                keys[#keys + 1], seen[y] = y, true
            end
        end
        if not x then
            c.notes[#c.notes + 1] = kind .. ": unmapped " .. what
        elseif c.namedKeys[x] then -- another ID of a key the APL casts itself: its own line stands
            c.notes[#c.notes + 1] = kind .. ": " .. what .. " is " .. x .. ", which the APL casts itself"
        elseif not seen[x] then
            keys[#keys + 1], seen[x] = x, true
        end
    end
    for i = placed and 0 or #block, 1, -1 do
        table.insert(keys, 1, block[i])
    end
    return keys
end

local entry, guard, terms

-- Rule 7's cast line of key `x`, without its condition: off-GCD and focus flags.
local function castBody(c, x)
    local tier = c.focus[x]
    if type(tier) == "table" and c.listName == "precombat" then
        -- a pre-pull line takes no tier and no occurrence: the list's tiers are the rotation's lines (the travel fold
        -- put Shadow Bolt in Affliction's precombat). shortcut: a list only precombat calls still counts; none at the pin
        tier = nil
    elseif type(tier) == "table" then
        c.seen[x] = (c.seen[x] or 0) + 1
        tier = tier[c.seen[x]] or tier[#tier]
    end
    -- a pre-pull line's tier is stripped with rule 1's guard pass (rule 7: none on a pre-pull line)
    return x .. (c.offGcd[x] and ",use_off_gcd=1" or "") .. (tier and (",focus=" .. tier) or "")
end

-- Condition node `n` as text: nil when always true (a nil condition is true: wowsims's apl_action.go), false never.
local function condition(c, n)
    local s, b, u = bool(c, n)
    if u ~= true and b == false then
        return false
    elseif u ~= true and s then
        return emit(u, s, true)
    end
end

local function paren(s) -- `s` as one term of an `&`
    return (grouped(s) or not s:find("|", 1, true)) and s or ("(" .. s .. ")")
end

-- Rule 7's guard of `key` after condition `cond` (either may be nil): one more `&` term.
local function guarded(c, key, cond)
    local g = c.guard[key]
    if not g then
        return cond
    end
    c.keyUsed["guard:" .. key] = true
    return cond and (paren(cond) .. "&" .. paren(g)) or g
end

-- Rule 14: a strictSequence's members (casts) as consecutive lines, each a member's own line (`entry`'s) whose
-- condition also says the sequence is at it: the first under the sequence's condition `cond`; a later one when the
-- member before it is the last cast (`prev.1.<key>`), or, while that member is unlearned (wowsims drops it from the
-- sequence), under what put the sequence at that member.
-- Whether condition node `n` reads one of `keys` (a spell, aura or item ID that maps to one; variables followed).
local function readsAny(c, n, keys)
    if type(n) ~= "table" then
        return false
    end
    if n.variableRef and c.vars[n.variableRef.name] then
        return readsAny(c, c.vars[n.variableRef.name], keys)
    end
    local id = n.spellId
    if type(id) == "number" and (keys[c.map[id] or c.keyOf[id] or c.auraOf[id] or ""] or keys[c.auraMap[id] or ""]) then
        return true
    end
    if type(n.itemId) == "number" and keys[c.map["item:" .. n.itemId] or c.itemKey[n.itemId] or ""] then
        return true
    end
    for _, v in pairs(n) do
        if readsAny(c, v, keys) then
            return true
        end
    end
    return false
end

local function sequence(c, members, cond, node)
    local out, at = {}, cond -- at: the condition that the sequence is at the next member (nil: always)
    local before = {} -- the keys of the members already cast
    for i, m in ipairs(members) do
        local mk
        for k in pairs(m) do
            if k ~= "condition" then
                mk = k
            end
        end
        if mk ~= "castSpell" and mk ~= "channelSpell" then
            unsupported("strictSequence of " .. tostring(mk))
        end
        local body, why = entry(c, { action = m })
        if not body then
            unsupported(("strictSequence member %d: %s"):format(i, why))
        end
        local base, own = body:match("^(.-),if=(.*)$")
        local x = c.self
        local rest -- a later member: the sequence's condition without the terms reading a member already cast
        if i > 1 and node then
            local terms = node["and"] and node["and"].vals or { node }
            local kept = {}
            for _, t in ipairs(terms) do
                if not readsAny(c, t, before) then
                    kept[#kept + 1] = t
                end
            end
            if #kept > 0 then
                c.self = nil
                local r = condition(c, { ["and"] = { vals = kept } })
                if r == false then
                    unsupported(("strictSequence member %d: its sequence's condition never holds"):format(i))
                end
                rest = r
            end
        end
        local parts = {}
        parts[#parts + 1] = at and paren(at) or nil
        parts[#parts + 1] = rest and paren(rest) or nil
        parts[#parts + 1] = own and paren(own) or nil
        out[i] = #parts > 0 and ((base or body) .. ",if=" .. table.concat(parts, "&")) or body
        before[x] = true
        local k = knownTest(c, x)
        local last = "prev.1." .. x
        at = k and ("(" .. k .. "&" .. last .. ")|(!" .. k .. (at and ("&" .. paren(at)) or "") .. ")") or last
    end
    return out
end

-- Rule 19: whether condition node `n` tests only the target's range (a rule 11 bracket, its `not`, a spellInRange;
-- variables followed): a distance-only waitUntil.
local function rangeOnly(c, n)
    while n and n.variableRef and c.vars[n.variableRef.name] do
        n = c.vars[n.variableRef.name]
    end
    if not n then
        return false
    elseif n["not"] then
        return rangeOnly(c, n["not"].val)
    elseif n.cmp then
        return (n.cmp.lhs and n.cmp.lhs.unitDistance or n.cmp.rhs and n.cmp.rhs.unitDistance) ~= nil
    end
    return n.spellInRange ~= nil
end

-- Rule 14b: the reads a window's evaluator can make in the belief (talents, settings, clocks, range).
local BELIEF = {
    "^talent%.",
    "^settings%.",
    "^target%.within%d+$",
    "^target%.outside%d+$",
    "^action%.[%w_]+%.in_range$",
    "^action%.[%w_]+%.known$",
    "^mainhand_",
    "^offhand_",
    "^time$",
    "^min$",
    "^max$",
}
local function unreadable(s)
    local bad = {}
    for tok in s:gmatch("[%a_][%w_.]*") do
        local ok = false
        for _, p in ipairs(BELIEF) do
            ok = ok or tok:find(p) ~= nil
        end
        bad[#bad + 1] = not ok and tok or nil
    end
    return #bad > 0 and table.concat(bad, ", ")
end

-- Rule 14b: a wowsims `sequence` (`a`: its action) as a stepped window, its cast members the steps: one line a cast,
-- `<key>,if=window.<w>.next.<key>[&<own>][&<gate>]`, consecutive equal lines once. A distance-only `waitUntil`
-- member is the next cast's range gate, `(toggle.movement&window.<w>.up|<gate>)` after a `move` member (the window is
-- up exactly while wowsims runs the sequence), as is; a trailing one is held (c.held: rule 19 carries it); `move` and
-- `wait` members give no line (rule 19, decision 9). The condition is the window's evaluator (the class registers it
-- from the header line), only when the belief can read it; its own `sequenceIsComplete` is dropped there (the window
-- opens on the evaluator's edge, so once).
local function windowed(c, a)
    local s = a.sequence
    local w = M.snake(s.name or "")
    c.ownSeq = w
    local cond = a.condition and condition(c, a.condition)
    c.ownSeq = nil
    if cond == false then
        return nil, never(c)
    end
    local bad = cond and unreadable(cond)
    if bad then
        unsupported(("sequence %s: its condition is not readable by the belief (%s)"):format(w, bad))
    end
    local out, steps, pending, moved = {}, {}, nil, false
    for _, m in ipairs(s.actions or {}) do
        local mk
        for k in pairs(m) do
            mk = k ~= "condition" and k or mk
        end
        if mk == "move" then
            moved = true
        elseif mk == "waitUntil" then
            if not rangeOnly(c, m.waitUntil.condition) then
                unsupported(("sequence %s: a waitUntil not on range"):format(w))
            end
            pending = m.waitUntil.condition
        elseif mk == "castSpell" or mk == "channelSpell" then
            local body, why = entry(c, { action = m })
            if not body then
                unsupported(("sequence %s member %d: %s"):format(w, #steps + 1, why))
            end
            local base, own = body:match("^(.-),if=(.*)$")
            local parts = { "window." .. w .. ".next." .. c.self }
            parts[#parts + 1] = own and paren(own) or nil
            local g = pending and condition(c, pending) -- the cast is the line's own: its range read unguarded
            if g then
                parts[#parts + 1] = moved and ("(toggle.movement&window." .. w .. ".up|" .. g .. ")") or paren(g)
            end
            pending = nil
            local line = (base or body) .. ",if=" .. table.concat(parts, "&")
            out[#out + 1] = line ~= out[#out] and line or nil
            steps[#steps + 1] = c.self
        elseif mk ~= "wait" then
            unsupported(("sequence %s of %s"):format(w, tostring(mk)))
        end
    end
    if #steps == 0 then
        unsupported(("sequence %s casts nothing"):format(w))
    end
    c.self = nil
    local g = pending and condition(c, pending)
    if g then
        c.held[#c.held + 1] = { list = c.listName, n = c.entryNo, gate = g, window = w, moved = moved }
    end
    c.windows[#c.windows + 1] = { name = w, steps = steps, cond = cond, list = c.listName, n = c.entryNo }
    if moved then -- rule 19: the sequence's move, reaching its steps' gates and its held one
        c.moving[#c.moving + 1] = { list = c.listName, n = c.entryNo, seq = w, reach = {} }
    end
    return out
end

-- One entry as a line body (a list of them for rules 13 and 14), or nil and why it folds away.
function entry(c, e)
    local a = e.action or {}
    local kind
    for k in pairs(a) do
        if k ~= "condition" then
            kind = k
        end
    end
    if not kind then
        return nil, "empty"
    end
    local body, key, auto, seq
    local tg = type(a[kind]) == "table" and a[kind].target
    if type(tg) == "table" and tg.type == "Target" and (tg.index or 0) > 0 then -- rule 2: another target's cast
        return nil, ("%s on another target (Target index %d)"):format(kind, tg.index)
    end
    if kind == "castSpell" or kind == "channelSpell" then
        local x = spellKey(c, a[kind].spellId)
        c.self, key = x, x
        body = castBody(c, x)
    elseif kind == "multidot" or kind == "strictMultidot" then -- rule 17: the cast under "its DoT has at most maxOverlap left", this target only
        local m = a[kind]
        c.deviations[#c.deviations + 1] = ("multidot keeps the DoT on up to %d targets in wowsims; this line is for the current target only."):format(
            m.maxDots or 0
        )
        local due = {
            cmp = {
                op = "OpLe",
                lhs = { dotRemainingTime = { spellId = m.spellId } },
                rhs = m.maxOverlap or { const = { val = "0s" } },
            },
        }
        local cond = a.condition and { ["and"] = { vals = { a.condition, due } } } or due
        return entry(c, { action = { castSpell = { spellId = m.spellId }, condition = cond } })
    elseif c.select[kind] then -- rule 16: one line a candidate, each under its setting term
        local sel, out = c.select[kind], {}
        sel.used = true
        for _, val in ipairs(sel.values) do
            local x = sel.x.candidates[val]
            if x then
                c.self = x
                local cond = a.condition and condition(c, a.condition)
                if cond ~= false then
                    cond =
                        guarded(c, x, required(c, x, cond and (sel.term[val] .. "&" .. paren(cond)) or sel.term[val]))
                    out[#out + 1] = castBody(c, x) .. ",if=" .. cond
                end
            end
        end
        if #out == 0 then
            return nil, never(c)
        end
        return out
    elseif kind == "groupReference" then
        local g = a.groupReference.groupName
        if c.toggles[g] then
            return nil, "toggle"
        end
        c.used[g], c.self = true, nil
        local by = c.callers[M.snake(g)] or {}
        -- rule 1: a list only pre-pull lists call is pre-pull; an omitted call line still counts (it can only drop guards)
        c.callers[M.snake(g)], by[c.listName] = by, true
        body = "call_action_list,name=" .. M.snake(g)
        key = M.snake(g)
    elseif kind == "cancelAura" then -- rule 10
        c.self = nil
        body = "cancel_buff,buff_name=" .. auraKey(c, a.cancelAura.auraId.spellId)
        key = "cancel_buff" -- a recipe `condition` / `guard` names it so (owner deviation R69)
    elseif kind == "sequence" then -- rule 14b
        c.self = nil
        return windowed(c, a)
    elseif kind == "strictSequence" then -- rule 14: its condition's reads all guarded (no member is the line's own)
        c.self, seq = nil, a.strictSequence.actions or {}
    elseif kind == "autocastOtherCooldowns" or kind == "castAllStatBuffCooldowns" then
        c.self, auto = nil, automatic(c, kind, a[kind])
        if #auto == 0 then
            return nil, #c.notes > 0 and table.concat(c.notes, "; ") or (kind .. ": none in the log")
        end
    else
        unsupported(kind)
    end
    local cond = a.condition and condition(c, a.condition)
    if cond == false and c.condition[key] == nil then -- L11: a recipe condition replaces an APL one that folds false
        return nil, never(c)
    end
    if seq then
        return sequence(c, seq, cond, a.condition)
    end
    if auto then
        local out = {}
        for i, x in ipairs(auto) do
            -- rule 7's use_off_gcd for both (autocast: the documented deviation from wowsims's GCD wait)
            local off = c.offGcd[x]
            local line = x .. (off and ",use_off_gcd=1" or "")
            local cx = guarded(c, x, required(c, x, cond))
            out[i] = cx and (line .. ",if=" .. cx) or line
        end
        return out
    end
    if c.condition[key] == false then -- rule 7: `false` omits the line (an owner deviation, R69's Prowl cancel)
        c.conditioned[key] = true
        return nil, "the recipe's condition is false"
    elseif c.condition[key] then -- rule 7: the recipe's condition replaces the APL's
        cond, c.conditioned[key] = c.condition[key], true
    end
    cond = guarded(c, key, required(c, key, cond))
    return cond and (body .. ",if=" .. cond) or body
end

-- Rule 1: what ability `key`'s handler does, recorded: { unit = "buff"|"debuff" (it applies an aura of its own key),
-- element (it summons a totem of its own key), removes = { [aura key] = true } }, or nil and the handler's error.
-- Run in the handler's own environment (the kit's stub state: Register* setfenv( f, state )) with the verbs rebound,
-- once as the stub stands and once with every buff up (a removal conditional on another aura being up).
local VERBS = { "applyBuff", "applyDebuff", "summonTotem", "removeBuff" }
local function effect(c, key)
    local done = c.effects[key]
    if done ~= nil then
        return done[1], done[2]
    end
    local a = c.set.abilities[key]
    local h = type(a) == "table" and a.handler
    if type(h) ~= "function" then
        c.effects[key] = { false }
        return false
    end
    local env, saved = getfenv(h), {}
    local r = { removes = {} }
    for _, v in ipairs(VERBS) do
        saved[v] = rawget(env, v)
    end
    env.applyBuff = function(k)
        r.unit = k == key and "buff" or r.unit
    end
    env.applyDebuff = function(_, k)
        r.unit = k == key and "debuff" or r.unit
    end
    env.summonTotem = function(k, element)
        r.element = k == key and element or r.element
    end
    env.removeBuff = function(k)
        r.removes[k] = k ~= key or nil
    end
    local ok, err = pcall(h)
    local buff = rawget(env, "buff")
    if ok and type(buff) == "table" then
        local up = setmetatable({ up = true, down = false }, { __index = buff.__any })
        env.buff = setmetatable({}, {
            __index = function()
                return up
            end,
        })
        -- every verb is recorded on this pass too: a handler applying its own aura only under another buff is guarded
        ok, err = pcall(h)
        env.buff = buff
    end
    for _, v in ipairs(VERBS) do
        env[v] = saved[v]
    end
    c.effects[key] = { ok and r or false, not ok and tostring(err) or nil }
    return c.effects[key][1], c.effects[key][2]
end

-- Rule 1: the guard term of each cast line in pre-pull list `out` (`origin`: each line's APL entry, for the notes).
function guard(c, name, out, origin, omitted)
    local eff, keys = {}, {}
    for i, b in ipairs(out) do
        local x = b:match("^([%w_]+)")
        -- a recipe line (origin false: levelingFirst) carries its own condition
        if
            x ~= "call_action_list"
            and x ~= "run_action_list"
            and x ~= "cancel_buff"
            and origin[i] ~= false
            and c.ability[x]
        then
            local r, err = effect(c, x)
            if err then
                omitted[#omitted + 1] = ("%s #%d: no guard: %s's handler raised: %s"):format(name, origin[i], x, err)
            end
            local a, aura = c.set.abilities[x], c.set.auras[x]
            if r and r.unit and type(aura) == "table" then
                local d, cd = aura.duration, a.cooldown
                if not (type(d) == "number" and type(cd) == "number" and d <= cd) then
                    eff[i], keys[i] = r, x
                end
            elseif r and r.element then
                eff[i] = r
            end
        end
    end
    local later = {}
    for i, b in ipairs(out) do
        local r, x, g = eff[i], keys[i], nil
        if r and x then
            local parts = { "!" .. r.unit .. "." .. x .. ".up" }
            for j = i + 1, later[i] and 0 or #out do
                local y, s = keys[j], eff[j]
                if y and y ~= x and s.unit == r.unit and (r.removes[y] or s.removes[x]) then
                    local k = knownTest(c, y) -- rule 6: another ability's aura, read only once it is learned
                    parts[#parts + 1], later[j] = "(!" .. k .. "|!" .. s.unit .. "." .. y .. ".up)", true
                end
            end
            g = parts
        elseif r then
            g = { "!totem." .. r.element .. ".up" }
        end
        if g then
            local head, cond = b:match("^(.-),if=(.*)$")
            local has, kept = {}, {}
            for _, t in ipairs(cond and terms(cond) or {}) do
                has[t] = true
            end
            for _, t in ipairs(g) do -- L102: a term the condition already has as an `&` term is not added twice
                kept[#kept + 1] = not has[t] and t or nil
            end
            g = table.concat(kept, "&")
            if g ~= "" then
                out[i] = head and (head .. ",if=" .. g .. "&" .. paren(cond)) or (b .. ",if=" .. g)
            end
        end
    end
end

-- Rules 19 and 14b: a `move`, `waitUntil` or `resetSequence` entry gives no line. A resetSequence is its window's
-- loop; a distance-only waitUntil is held (its condition the gate rule 19 carries); a move is recorded with its
-- target range and condition for the rewrite. Returns the entry's omitted text.
local function motion(c, a)
    c.self = nil
    if a.resetSequence then
        c.loops[M.snake(a.resetSequence.sequenceName or "")] = true
        return "resetSequence"
    elseif a.waitUntil then
        if rangeOnly(c, a.waitUntil.condition) then
            local ok, g = pcall(condition, c, a.waitUntil.condition)
            if not ok and type(g) ~= "table" then
                error(g, 0)
            end
            if ok and g then
                -- shortcut: the waitUntil's own entry condition (a.condition) is not carried with its gate, so a
                -- later line is held even where wowsims would skip the wait; at the pin it is the gate's own
                -- distance term (Feral, Guardian). Upgrade when a pin's waitUntil has another condition.
                c.held[#c.held + 1] = { list = c.listName, n = c.entryNo, gate = g }
            end
        end
        return "waitUntil"
    end
    local okD, yd = pcall(value, c, a.move.rangeFromTarget or {})
    local ok, cond = pcall(condition, c, a.condition or {})
    for _, r in ipairs({ { okD, yd }, { ok, cond } }) do
        if not r[1] and type(r[2]) ~= "table" then
            error(r[2], 0)
        end
    end
    if not ok then
        return "move (reaches nothing: its condition reads " .. tostring(cond.unsupported) .. ")"
    end
    local g = c.guard[c.listName .. " #" .. c.entryNo] -- rule 7's guard of a move: its reached lines carry it
    c.keyUsed["guard:" .. c.listName .. " #" .. c.entryNo] = g and true or nil
    if g and cond ~= false then
        cond = cond and (paren(cond) .. "&" .. paren(g)) or g
    end
    local D = okD and tonumber(yd)
    local f, args = tostring(yd):match("^(m[ai][nx])%(([%d.,]+)%)$") -- a min()/max() of constants (the hunters' spots)
    for x in (okD and not D and f and args or ""):gmatch("[^,]+") do
        D = tonumber(x) and math[f](D or tonumber(x), tonumber(x))
    end
    if cond ~= false and D then
        local dropped = {}
        for k, x in ipairs(c.moves) do
            dropped[k] = x
        end
        c.moving[#c.moving + 1] =
            { list = c.listName, n = c.entryNo, D = D, cond = cond, dropped = dropped, reach = {} }
    end
    return "move"
end

-- The `&` terms of condition text `s` (the whole as one term when it has a top-level `|`), a parenthesised
-- conjunction's own terms in its place (`(a&b)&c` is a, b, c; `(a|b)` stays one term).
function terms(s)
    local parts, depth, from = {}, 0, 1
    for i = 1, #s do
        local ch = s:sub(i, i)
        depth = depth + (ch == "(" and 1 or ch == ")" and -1 or 0)
        if depth == 0 and ch == "|" then
            return { s }
        elseif depth == 0 and ch == "&" then
            parts[#parts + 1], from = s:sub(from, i - 1), i + 1
        end
    end
    parts[#parts + 1] = s:sub(from)
    local out = {}
    for _, t in ipairs(parts) do
        local inner = grouped(t) and terms(t:sub(2, -2)) or {}
        for _, x in ipairs(#inner > 1 and inner or { t }) do
            out[#out + 1] = x
        end
    end
    return out
end

-- Rule 19's `&<move condition>` after `toggle.movement`: none when a move is unconditional (`true`), several `|`-joined.
local function moveTerm(conds)
    local parts, seen = {}, {}
    for _, x in ipairs(conds) do
        if x == true then
            return ""
        elseif not seen[x] then
            seen[x], parts[#parts + 1] = true, (grouped(x) or not x:find("[&|]")) and x or ("(" .. x .. ")")
        end
    end
    return "&" .. (#parts == 1 and parts[1] or ("(" .. table.concat(parts, "|") .. ")"))
end

-- Rule 19 over the translated lists (`lists`, `byName`; `origin`: each line's APL entry, false for a recipe line;
-- `pre`: the pre-pull lists, which no move reaches): lines reading a window no sequence made are dropped, the held
-- gates carried, each move's reached lines rewritten. Returns the header's window and movement lines.
local function rewrite(c, lists, byName, origin, pre, omitted)
    local made = {}
    for _, w in ipairs(c.windows) do
        made[w.name] = true
    end
    for _, w in pairs(c.windowVars) do -- a recipe window (the kit registers it)
        made[w] = true
    end
    for _, l in ipairs(lists) do
        local L, j = l[1], 1
        while j <= #l[2] do
            local w = l[2][j]:match("window%.([%w_]+)%.")
            if w and not made[w] then
                omitted[#omitted + 1] = ("%s #%d: reads window %s, whose sequence was omitted"):format(
                    L,
                    tonumber(origin[L][j]) or 0,
                    w
                )
                table.remove(l[2], j)
                table.remove(origin[L], j)
            else
                j = j + 1
            end
        end
    end
    local calls = {} -- [called list] = { { caller, line, its APL entry, its condition or nil } }
    for _, l in ipairs(lists) do
        for j, b in ipairs(l[2]) do
            local x, rest = b:match("^call_action_list,name=([%w_]+)(.*)$")
            if x and not pre[l[1]] then
                calls[x] = calls[x] or {}
                table.insert(calls[x], { l[1], j, tonumber(origin[l[1]][j]) or math.huge, rest:match("^,if=(.*)$") })
            end
        end
    end
    local function add(m, L, b) -- line `b` of list `L` is reached by move `m` (the header's list)
        local k = b:match("^call_action_list,name=([%w_]+)") or b:match("^([%w_]+)")
        m.reach[L] = m.reach[L] or {}
        for _, x in ipairs(m.reach[L]) do
            if x == k then
                return
            end
        end
        table.insert(m.reach[L], k)
    end
    local function later(L, after, into) -- the APL lines of `L` after entry `after` that no window's step holds
        for j, b in ipairs(byName[L]) do
            if (tonumber(origin[L][j]) or -1) > after and not b:find(",if=window%.[%w_]+%.next%.") then
                into[#into + 1] = { L, j }
            end
        end
        return into
    end
    -- the held gates: onto the later lines of their list, or of its callers' when none follows (a group's or a
    -- sequence's last); one sequence's gate is held only while its window is up, and sequences sharing a gate merge
    local merged, order = {}, {}
    for _, h in ipairs(c.held) do
        if not pre[h.list] then
            local key = h.list .. "\0" .. h.gate .. "\0" .. (h.window and "" or tostring(h.n))
            local m = merged[key]
            if not m then
                m = { list = h.list, n = h.n, gate = h.gate, conds = {}, windows = {}, movers = {} }
                merged[key], order[#order + 1] = m, m
            end
            m.n = math.min(m.n, h.n)
            if h.window then
                m.windows[#m.windows + 1] = "!window." .. h.window .. ".up"
                for _, mv in ipairs(h.moved and c.moving or {}) do
                    if mv.seq == h.window then
                        m.conds[#m.conds + 1], m.movers[#m.movers + 1] = "window." .. h.window .. ".up", mv
                    end
                end
            else
                for _, mv in ipairs(c.moving) do
                    if mv.list == h.list and mv.n < h.n and mv.D then
                        m.conds[#m.conds + 1], m.movers[#m.movers + 1] = mv.cond or true, mv
                    end
                end
            end
        end
    end
    for _, m in ipairs(order) do
        local parts = { m.gate }
        if #m.conds > 0 then
            table.insert(parts, 1, "toggle.movement" .. moveTerm(m.conds))
        end
        parts[#parts + 1] = #m.windows > 0 and table.concat(m.windows, "&") or nil
        local g = #parts == 1 and paren(m.gate) or ("(" .. table.concat(parts, "|") .. ")")
        local targets = later(m.list, m.n, {})
        if #targets == 0 then
            -- shortcut: a held gate is carried one calling list up only (not to the caller's callers, and without
            -- the call's own condition); every held gate at the pin ends a list called from the main one. Upgrade
            -- when a pin nests the holding group deeper.
            for _, k in ipairs(calls[m.list] or {}) do
                later(k[1], k[3], targets)
            end
        end
        for _, t in ipairs(targets) do
            local b = byName[t[1]][t[2]]
            byName[t[1]][t[2]] = b:find(",if=", 1, true) and (b .. "&" .. g) or (b .. ",if=" .. g)
            for _, mv in ipairs(m.movers) do
                add(mv, t[1], b)
            end
        end
    end
    for _, mv in ipairs(c.moving) do -- a sequence's move reaches its steps' range gates (rule 14b)
        for _, b in ipairs(mv.seq and byName[mv.list] or {}) do
            if
                b:find("|toggle.movement&window." .. mv.seq .. ".up|", 1, true)
                or b:find("&(toggle.movement&window." .. mv.seq .. ".up|", 1, true)
            then
                add(mv, mv.list, b)
            end
        end
    end
    -- R4: a move to D yd reaches every line of its list and its callers' (before or after it) that cannot be cast
    -- beyond D: its bracket `target.within<D>`, or its spellInRange of an ability the recipe's DB2 range gives D, or,
    -- with no range read at all, its own ability's DB2 range 0-D (a new term); a caller's line takes the call's
    -- condition before the move's
    local rewrites = {} -- [list] = { [line] = { [gate term] = { { cond =, at = its arm's line, mv = its index } } } }
    for mi, mv in ipairs(c.moving) do
        if mv.D and not pre[mv.list] then
            local seen = {}
            local function scope(L, prefix, p) -- `p`: the move's APL entry in `L` (in a caller: the call's)
                if seen[L] or pre[L] then
                    return
                end
                -- shortcut: a list is scoped once a move, so a group called twice from one list takes the first call's
                -- condition and position (R51) only; no pin has one. Upgrade when a pin calls a move's group twice.
                seen[L] = true
                local cond = mv.cond or true
                if prefix then
                    cond = cond == true and prefix or (paren(prefix) .. "&" .. paren(cond))
                end
                local at = #byName[L] + 1 -- the move's arm goes before the first line of an entry at or after `p`
                for j, o in ipairs(origin[L]) do
                    if o and o >= p then
                        at = j
                        break
                    end
                end
                -- shortcut: inward reach is on equal range only: a move to D never reaches a shorter-range gate
                -- (correct: it stops at D) nor a longer one (passed on the walk in); every inward move at the pin is
                -- to 5 yd. Upgrade when a pin moves to another range with longer-range lines behind it.
                local N = math.ceil(mv.D) -- the whole-yard bracket D is inside (the hunters' 4.99 is within5)
                local function out(m) -- whether standing at D is beyond minimum range m
                    -- shortcut: the move's direction is not checked, so a melee move (to D) would reach an
                    -- outside<N> gate with N < D too; no pin has one (gaps.md "Move reach ignores direction").
                    -- Upgrade when a pin moves in to a D above a line's minimum range.
                    return m and m > 0 and m < mv.D
                end
                for j, b in ipairs(byName[L]) do
                    local cnd = b:match(",if=(.*)$")
                    local hit, gated
                    for _, t in ipairs(origin[L][j] and cnd and terms(cnd) or {}) do
                        local k = t:match("^action%.([%w_]+)%.in_range$")
                            or t:match("^%(!action%.([%w_]+)%.known|action%.[%w_]+%.in_range%)$")
                        local r = k and c.ranges[k]
                        gated = gated or t:find("target%.within") or t:find("target%.outside") or t:find("in_range")
                        local away = out(tonumber(t:match("^target%.outside(%d+)$")))
                            or (r and out(r[1]) and mv.D <= r[2])
                        hit = hit or ((t == "target.within" .. N or (r and r[2] == N) or away) and t)
                    end
                    local r = origin[L][j] and not gated and c.ranges[b:match("^([%w_]+)")]
                    hit = hit
                        or (r and r[1] == 0 and r[2] == N and ("target.within" .. N))
                        or (r and out(r[1]) and mv.D <= r[2] and ("target.outside" .. r[1]))
                    if hit then
                        rewrites[L] = rewrites[L] or {}
                        rewrites[L][j] = rewrites[L][j] or {}
                        rewrites[L][j][hit] = rewrites[L][j][hit] or {}
                        table.insert(rewrites[L][j][hit], { cond = cond, at = at, mv = mi })
                        add(mv, L, b)
                    end
                end
                for _, k in ipairs(calls[L] or {}) do
                    scope(k[1], k[4] and (prefix and (paren(k[4]) .. "&" .. paren(prefix)) or k[4]) or prefix, k[3])
                end
            end
            scope(mv.list, nil, mv.n)
        end
    end
    -- R51: a reached line keeps its gate (the in-range arm) in place; its move arm, `toggle.movement&<move condition>`,
    -- is a copy at the move's position, so whatever wowsims ranks above the move still wins. An arm alone right
    -- before its own line is the one line `(toggle.movement&<move condition>|<gate>)`.
    for L, lines in pairs(rewrites) do
        local l, o, arms, n, merged = byName[L], origin[L], {}, {}, {}
        for j, rw in pairs(lines) do
            local byAt = {}
            for t, xs in pairs(rw) do
                for _, x in ipairs(xs) do
                    local a = byAt[x.at]
                    if not a then
                        a = { at = x.at, j = j, mv = x.mv, conds = {} }
                        byAt[x.at], arms[#arms + 1], n[x.at] = a, a, (n[x.at] or 0) + 1
                    end
                    a.mv = math.min(a.mv, x.mv)
                    a.conds[t] = a.conds[t] or {}
                    table.insert(a.conds[t], x.cond)
                end
            end
        end
        for _, a in ipairs(arms) do
            merged[a.j] = (a.at == a.j and n[a.at] == 1) and a or merged[a.j]
        end
        local function text(j, a, gate) -- line `j`, arm `a`'s terms as its move arm (`gate`: or'd with the gate)
            local b = l[j]
            local head, cnd = b:match("^(.-),if=(.*)$")
            local ts, has = cnd and terms(cnd) or {}, {}
            local function arm(t)
                local x = a and a.conds[t] and ("toggle.movement" .. moveTerm(a.conds[t]))
                return x and gate and ("(" .. x .. "|" .. t .. ")") or x or t
            end
            for i, t in ipairs(ts) do
                has[t], ts[i] = true, lines[j][t] and arm(t) or t
            end
            for t in pairs(lines[j]) do -- the DB2 range's new term
                ts[#ts + 1] = not has[t] and arm(t) or nil
            end
            return (head or b) .. ",if=" .. table.concat(ts, "&")
        end
        table.sort(arms, function(x, y)
            return x.at < y.at or (x.at == y.at and (x.mv < y.mv or (x.mv == y.mv and x.j < y.j)))
        end)
        local nl, no, k = {}, {}, 1
        for j = 1, #l + 1 do
            while arms[k] and arms[k].at == j do
                if merged[arms[k].j] ~= arms[k] then
                    nl[#nl + 1], no[#no + 1] = text(arms[k].j, arms[k]), o[arms[k].j]
                end
                k = k + 1
            end
            if j <= #l then
                nl[#nl + 1], no[#no + 1] = lines[j] and text(j, merged[j], true) or l[j], o[j]
            end
        end
        for j = 1, #nl do
            l[j], o[j] = nl[j], no[j]
        end
    end
    local header = {}
    for _, w in ipairs(c.windows) do
        if not pre[w.list] then
            header[#header + 1] = ("# Window: %s: steps %s%s; on_deviation stay; evaluator %s (the class registers it)."):format(
                w.name,
                table.concat(w.steps, ", "),
                c.loops[w.name] and "; loop" or "",
                w.cond or "true"
            )
        end
    end
    for _, mv in ipairs(c.moving) do
        if next(mv.reach) and not pre[mv.list] then
            local parts = {}
            for _, l in ipairs({ { mv.list }, unpack(lists) }) do -- its own list first
                local L = l[1]
                if mv.reach[L] and (L ~= mv.list or #parts == 0) then
                    parts[#parts + 1] = L .. ": " .. table.concat(mv.reach[L], ", ")
                end
            end
            header[#header + 1] = ("# Movement: %s #%d reaches %s"):format(mv.list, mv.n, table.concat(parts, "; "))
            for _, k in ipairs(mv.dropped or {}) do
                c.movedAll[#c.movedAll + 1] = { ("# Dropped (movement): %s #%d: %s"):format(mv.list, mv.n, k) }
            end
        end
    end
    return header
end

--- The SimC text of `rotation` (a wowsims APL table) under context `c`, the omitted entries
--- ({ "<list> #<n>: <why>" }) and the settings an emitted line reads ({ { setting key, default, source } }: the APL's
--- ON/OFF groups in its order, then the recipe's `settings` by key).
function M.translate(rotation, c)
    c.vars, c.toggles, c.used, c.seen, c.named, c.namedKeys, c.notes, c.dropped = {}, {}, {}, {}, {}, {}, {}, {}
    c.dropNote = {}
    c.callers, c.deviated, c.deviations, c.moves, c.movedAll = {}, {}, {}, {}, {}
    c.held, c.windows, c.loops, c.moving = {}, {}, {}, {} -- rules 14b, 19
    c.conditioned = {} -- rule 7: the recipe's condition keys a line took
    c.keyUsed = {} -- CN12: "<field>:<key>" of each recipe guard, requires and windowVars key a line took
    -- the IDs the APL casts itself (wowsims takes them out of its automatic cooldowns: rule 13)
    local lists = { rotation.prepullActions or {}, rotation.priorityList or {} }
    for _, g in ipairs(rotation.groups or {}) do
        lists[#lists + 1] = g.actions or {}
    end
    for _, l in ipairs(lists) do
        for _, e in ipairs(l) do
            local a = e.action or {}
            local s = (a.castSpell or a.channelSpell or a.castFriendlySpell or a.multidot or {}).spellId or {}
            if s.spellId or s.itemId then
                c.named[(s.spellId and "spell:" or "item:") .. (s.spellId or s.itemId)] = true
            end
            local x = (s.spellId or s.itemId or s.otherId) and spellLookup(c, s)
            if x then
                c.namedKeys[x] = true
            end
        end
    end
    for _, v in ipairs(rotation.valueVariables or {}) do
        c.vars[v.name] = v.value
    end
    -- CN12 (review I2): every entry name the APL has, emitted or omitted: its action's key (a select's candidates, a
    -- sequence's members), a group call's snake name, `cancel_buff`, and "<list> #<n>" (a move entry's guard key)
    c.entryNames = {}
    local function named(a)
        for k, v in pairs(a or {}) do
            if k ~= "condition" and type(v) == "table" then
                local x = type(v.spellId) == "table" and spellLookup(c, v.spellId)
                c.entryNames[x or ""] = true
                if k == "groupReference" then
                    c.entryNames[M.snake(v.groupName or "")] = true
                elseif k == "cancelAura" then
                    c.entryNames.cancel_buff = true
                elseif c.select[k] then
                    for _, key in pairs(c.select[k].x.candidates) do
                        c.entryNames[key or ""] = true
                    end
                end
                for _, m in ipairs(v.actions or {}) do
                    named(m)
                end
            end
        end
    end
    local function nameList(name, entries)
        for i, e in ipairs(entries or {}) do
            c.entryNames[name .. " #" .. i] = true
            named(e.action)
        end
    end
    nameList("precombat", rotation.prepullActions)
    nameList("default", rotation.priorityList)
    for _, g in ipairs(rotation.groups or {}) do
        nameList(M.snake(g.name or ""), g.actions)
    end
    c.yards = {} -- rule 18 (R17)
    findYards(c, rotation)
    local toggles, shown = {}, {}
    for _, e in ipairs(rotation.priorityList or {}) do
        local g = e.action and e.action.groupReference
        if g and not e.hide then
            shown[g.groupName] = true
        end
    end
    -- rule 3: a group is used when any shown entry references it (wowsims's Finalize: `referencedBy`, set by the
    -- references in the prepull and priority lists and in the groups' own actions, sequences included; a hidden entry
    -- is never built)
    c.groupUsed = {}
    local function refs(x)
        if type(x) ~= "table" or x.hide then
            return
        end
        if type(x.groupReference) == "table" and x.groupReference.groupName then
            c.groupUsed[x.groupReference.groupName] = true
        end
        for _, y in pairs(x) do
            refs(y)
        end
    end
    for _, g in ipairs(rotation.groups or {}) do
        c.groupUsed[g.name] = false
    end
    refs(rotation.priorityList)
    refs(rotation.prepullActions)
    for _, g in ipairs(rotation.groups or {}) do
        refs(g.actions)
    end
    for _, g in ipairs(rotation.groups or {}) do
        local empty = true
        for _, x in ipairs(g.actions or {}) do
            empty = empty and next(x.action or {}) == nil
        end
        if empty then
            c.toggles[g.name] = "wowsims_" .. M.snake((g.name:gsub(" ON/OFF$", "")))
            toggles[#toggles + 1] = { c.toggles[g.name], shown[g.name] == true, "wowsims ON/OFF group" }
        end
    end
    local own = {}
    for key in pairs(c.settings) do
        own[#own + 1] = key
    end
    table.sort(own)
    for _, key in ipairs(own) do
        toggles[#toggles + 1] = { key, c.settings[key].default == true, c.settings[key].desc }
    end
    local omitted, lists, byName = {}, {}, {}
    local origin = {} -- [list name][line] = its APL entry's index (for rule 1's notes)
    local skip, skipped = {}, {} -- rule 7: the recipe's prepullSkip actions, and those it omitted
    local castAt, gcdAt = {}, {} -- rule 1: the pre-pull entries whose time folds a cast time, a GCD
    for _, x in ipairs(c.prepullSkip) do
        skip[x] = true
    end
    local function run(name, entries, at)
        local out, order = {}, {}
        origin[name], c.listName = {}, name
        for i in ipairs(entries) do
            order[i] = i
        end
        if at then -- the prepull schedule: by doAtValue, earliest first (wowsims's order), ties in the APL's
            table.sort(order, function(x, y)
                local ax, ay = tonumber(at[x]) or 0, tonumber(at[y]) or 0
                ax, ay = -ax, -ay -- seconds before the pull: the earliest is the largest
                return ax < ay or (ax == ay and x < y)
            end)
        end
        for _, i in ipairs(order) do
            local e = entries[i]
            local when = at and at[i] -- seconds before the pull (0: at it), or why wowsims ignores the entry
            if e.hide then
                omitted[#omitted + 1] = ("%s #%d: hidden"):format(name, i)
            elseif type(when) == "string" then
                omitted[#omitted + 1] = ("%s #%d: %s"):format(name, i, when)
            else
                c.notes, c.dropped, c.dropNote, c.deviations, c.moves, c.folds = {}, {}, {}, {}, {}, {}
                c.entryNo, c.ownSeq = i, nil
                if at and castAt[i] then
                    deviate(c, PREPULL_CAST)
                end
                if at and gcdAt[i] then
                    deviate(c, PREPULL_GCD)
                end
                local a = e.action or {}
                local ok, body, why = true, nil, "noted"
                if a.move or a.waitUntil or a.resetSequence then -- rules 19, 14b: no line, but recorded
                    omitted[#omitted + 1] = ("%s #%d: %s"):format(name, i, motion(c, a))
                else
                    ok, body, why = pcall(entry, c, e)
                end
                if not ok then
                    if type(body) ~= "table" then
                        error(body, 0)
                    end
                    omitted[#omitted + 1] = ("%s #%d: %s"):format(name, i, body.unsupported)
                elseif body and name == "precombat" and skip[body:match("^[%w_]+")] then
                    skipped[body:match("^[%w_]+")] = true -- rule 7: the recipe's prepullSkip
                    omitted[#omitted + 1] = ("%s #%d: prepullSkip (recipe)"):format(name, i)
                elseif body then
                    for _, b in ipairs(type(body) == "table" and body or { body }) do
                        out[#out + 1] = b
                        origin[name][#out] = i
                    end
                    for _, what in ipairs(c.dropped) do
                        c.notes[#c.notes + 1] = c.dropNote[what]
                            or ("dropped the unresolved " .. what .. " (its branch only)")
                    end
                    for _, n in ipairs(c.notes) do
                        omitted[#omitted + 1] = ("%s #%d: %s"):format(name, i, n)
                    end
                    for _, d in ipairs(c.deviations) do -- an emitted line that differs from wowsims (rule 17)
                        c.deviated[#c.deviated + 1] = ("# Deviation: %s #%d: %s"):format(name, i, d)
                    end
                    local called = type(body) == "string" and body:match("^call_action_list,name=([%w_]+)")
                    for _, m in ipairs(c.moves) do -- rule 18 (not for a call that turns out empty)
                        c.movedAll[#c.movedAll + 1] =
                            { ("# Dropped (movement): %s #%d: %s"):format(name, i, m), called }
                    end
                elseif why ~= "toggle" and why ~= "noted" then
                    omitted[#omitted + 1] = ("%s #%d: %s"):format(name, i, why)
                end
            end
        end
        lists[#lists + 1], byName[name] = { name, out }, out
    end
    -- wowsims (sim/core/apl.go, the prepull parse) skips an entry with no doAtValue or one after the pull (> 0); 0 runs
    -- at the pull itself
    local prepull, at = rotation.prepullActions or {}, {}
    for i, e in ipairs(prepull) do
        c.castFolded, c.gcdFolded = false, false
        local ok, n = pcall(folded, c, e.doAtValue or {})
        n = ok and n
        castAt[i], gcdAt[i] = c.castFolded, c.gcdFolded
        if not e.doAtValue or next(e.doAtValue) == nil then
            at[i] = "no doAtValue"
        elseif not n then
            at[i] = "doAtValue not a constant"
        elseif n > 0 then
            at[i] = "doAtValue after the pull"
        else
            at[i] = n == 0 and 0 or -n
        end
    end
    run("precombat", prepull, at)
    for _, x in ipairs(c.prepullSkip) do
        if not skipped[x] then
            error("prepullSkip: no " .. x .. " line in precombat", 0)
        end
    end
    run("default", rotation.priorityList or {})
    for _, line in ipairs(c.leveling) do -- recipe lines: no APL entry (false)
        table.insert(byName.default, line)
        table.insert(origin.default, false)
    end
    for i, line in ipairs(c.levelingFirst) do
        table.insert(byName.default, i, line)
        table.insert(origin.default, i, false)
        if #byName.precombat > 0 then -- a pre-pull line would show before the form out of combat
            table.insert(byName.precombat, i, line)
            table.insert(origin.precombat, i, false)
        end
    end
    for _, x in ipairs(c.extra) do
        local at
        for i, body in ipairs(byName.default) do
            if body:match("^[%w_]+") == x.before then
                at = i
                break
            end
        end
        if not at then
            error("extra: no " .. x.before .. " line in actions", 0)
        end
        table.insert(byName.default, at, x.line)
        table.insert(origin.default, at, false)
    end
    local done = {}
    repeat
        local more = false
        for _, g in ipairs(rotation.groups or {}) do
            if c.used[g.name] and not done[g.name] then
                done[g.name], more = true, true
                run(M.snake(g.name), g.actions or {})
            end
        end
    until not more
    for x in pairs(c.condition) do -- after the groups: a condition may name an action cast only in one (review M1)
        if not c.conditioned[x] then
            error("condition: no " .. x .. " cast line", 0)
        end
    end
    -- CN12: a recipe key that names nothing is an error, as for `condition` (an upstream rename would drop it silently)
    for _, field in ipairs({ "guard", "requires", "windowVars" }) do
        local names = {}
        for key in pairs(c[field]) do
            names[#names + 1] = key
        end
        table.sort(names)
        for _, key in ipairs(names) do
            local has = field == "windowVars" and c.vars or c.entryNames -- an entry of that name, emitted or not
            if not (c.keyUsed[field .. ":" .. key] or has[key]) then
                error(("%s: no %s %s"):format(field, key, field == "windowVars" and "read" or "line"), 0)
            end
        end
    end
    local pre = { precombat = true } -- rule 1: the pre-pull lists, precombat and those only pre-pull lists call
    local function isPre(name, seen)
        if pre[name] ~= nil then
            return pre[name]
        end
        if seen[name] or not c.callers[name] then
            return false
        end
        seen[name] = true
        for by in pairs(c.callers[name]) do
            if not isPre(by, seen) then
                return false
            end
        end
        return true
    end
    for _, l in ipairs(lists) do
        pre[l[1]] = isPre(l[1], {})
    end
    local moving = rewrite(c, lists, byName, origin, pre, omitted) -- rules 19, 14b
    for _, l in ipairs(lists) do
        if pre[l[1]] then
            for i, body in ipairs(l[2]) do -- rule 7: no focus tier on a pre-pull line
                l[2][i] = body:gsub(",focus=%d+", "", 1)
            end
            guard(c, l[1], l[2], origin[l[1]], omitted)
        end
    end
    local text, cast = {}, {}
    for _, l in ipairs(lists) do
        local head = l[1] == "default" and "actions" or ("actions." .. l[1])
        local n = 0
        for _, body in ipairs(l[2]) do
            local called = body:match("^call_action_list,name=([%w_]+)")
            if called and #(byName[called] or {}) == 0 then
                omitted[#omitted + 1] = ("%s: empty group %s"):format(l[1], called)
            else
                n = n + 1
                text[#text + 1] = head .. (n == 1 and "=" or "+=/") .. maintained(c, body, cast)
            end
        end
    end
    text = table.concat(text, "\n")
    -- only the settings an emitted line reads (ruling L14): a group whose every reader was omitted registers nothing
    local read = {}
    for _, t in ipairs(toggles) do
        if text:find("settings%." .. t[1] .. "%f[^%w_]") then
            read[#read + 1] = t
        end
    end
    local header = {} -- rule 15's settings
    for _, m in ipairs(c.maintenance) do
        if not cast[m[1]] then
            error(("maintenance: %s matched no line"):format(m[1]), 0)
        end
        header[#header + 1] = ("# Setting %s (maintenance debuff: %s), default off in game, on in the harness."):format(
            m[2],
            m[1]
        )
    end
    local actions = {}
    for action in pairs(c.select) do
        actions[#actions + 1] = action
    end
    table.sort(actions)
    for _, action in ipairs(actions) do -- rule 16's settings
        local sel = c.select[action]
        if not sel.used then
            error(("select: %s is not in the APL"):format(action), 0)
        end
        local names = {}
        for i, v in ipairs(sel.values) do
            names[i] = M.snake(v)
        end
        header[#header + 1] = ("# Setting %s (choice of %s: %s), default %s in game and in the harness."):format(
            sel.x.setting,
            sel.x.option,
            table.concat(names, ", "),
            M.snake(sel.choice)
        )
    end
    for _, d in ipairs(c.deviated) do
        header[#header + 1] = d
    end
    for _, m in ipairs(c.movedAll) do
        if not (m[2] and #(byName[m[2]] or {}) == 0) then
            header[#header + 1] = m[1]
        end
    end
    for _, h in ipairs(moving) do
        header[#header + 1] = h
    end
    return text, omitted, read, header
end

--- Writes spec `spec`'s pack: src/Hekili_<Class>/APLs/<recipe.pack>.simc from the checked-in request (`ex`:
--- export.lua's module), its description (with the recipe's `notes`, player-facing lines), toggles and omitted entries in
--- the header.
function M.write(spec, ex)
    local json = require("dkjson")
    local r = ex.recipe(spec)
    local f = assert(io.open(ex.OUT .. spec .. ".json", "rb"))
    local req = json.decode(f:read("*a"))
    f:close()
    local set = require("Forever.helpers.engine").abilitySet(r.class)
    local lf = io.open(ex.OUT .. spec .. ".log", "rb")
    local log = lf and lf:read("*a")
    if lf then
        lf:close()
    end
    local player = req.raid.parties[1].players[1]
    local tank = false -- wowsims's isTank: the player (raid index 0) in a tank slot (sim/core/environment.go:123-128)
    for _, t in ipairs(req.raid.tanks or {}) do
        tank = tank or (t.type == "Player" and (t.index or 0) == 0)
    end
    local text, omitted, toggles, header =
        M.translate(player.rotation, M.context(set, r, log, player, req.encounter, tank))
    local Class = r.class:sub(1, 1) .. r.class:sub(2):lower()
    local out = {
        ("# %s: the wowsims/forever default APL for %s (%s), translated to this addon's keys."):format(
            r.pack,
            r.name,
            r.apl or r.siml or r.build
        ),
        "# Data: wowsims/forever (MIT, https://github.com/wowsims/forever) at " .. ex.pin(spec):sub(1, 12) .. ".",
    }
    for _, n in ipairs(r.notes or {}) do -- the recipe's player-facing notes: more of the in-game description
        out[#out + 1] = "# " .. n
    end
    for _, l in ipairs({
        "",
        ("# Generated by `make wowsims-packs` (tools/wowsims/apl.lua) from tools/wowsims/specs/%s.lua: edit that recipe, not this file."):format(
            spec
        ),
    }) do
        out[#out + 1] = l
    end
    for _, t in ipairs(toggles) do
        out[#out + 1] = ("# Setting %s (%s), default %s."):format(t[1], t[3], tostring(t[2]))
    end
    for _, h in ipairs(header) do
        out[#out + 1] = h
    end
    for _, o in ipairs(omitted) do
        out[#out + 1] = "# Omitted: " .. o
    end
    out[#out + 1] = ""
    out[#out + 1] = text
    local path = ("src/Hekili_%s/APLs/%s.simc"):format(Class, r.pack)
    local w = assert(io.open(path, "wb"))
    w:write(table.concat(out, "\n") .. "\n")
    w:close()
    print(("%s: %d omitted, %d toggles"):format(path, #omitted, #toggles))
end

return M
