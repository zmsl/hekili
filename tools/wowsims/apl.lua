-- tools/wowsims/apl.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 4): a
-- wowsims/forever APL (a request's player.rotation) as a "(wowsims.com)" pack's SimC text with the fork's keys.
-- Data: wowsims/forever (MIT, https://github.com/wowsims/forever); the APL JSON is translated as data, no code copied.
--
-- The translation rules (the plan's Task 4):
-- 1. One `.simc` line per APL entry, in order: `prepullActions` -> `actions.precombat` (wowsims's order: by a
--    constant `doAtValue`, earliest first, ties in the APL's order; an entry with no `doAtValue` or one after the pull
--    is omitted, as wowsims ignores it, and one with a non-constant `doAtValue` too), `priorityList` -> `actions`,
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
--    A mutually exclusive group (lines of one list whose handlers remove each other's aura) guards its first line by
--    every member's aura (`!buff.a.up&(!action.b.known|!buff.b.up)`: rule 6's guard on another ability's read),
--    later lines by their own: the first is cast only when none is up, the later replaces it. A handler that raises
--    gives no guard and a header note.
-- 2. Omitted, and listed in the file's second comment block: `hide: true` entries; entries whose condition folds to
--    false; entries whose action or condition uses a node the fork lacks (`sequence`,
--    `resetSequence`, `schedule`, `itemSwap`, `move`, `wait`, `unitDistance` outside rule 11, `sequenceIsComplete`,
--    `activeItemSwapSet`, `selectedConjured`), or whose own action is an unmapped spell, item or other ID (an unmapped
--    read drops only its branch: rule 12); a call of a group whose every entry was omitted. Also listed: rule 12's
--    dropped reads and rule 13's unmapped cooldowns, by entry.
-- 3. Toggles: a group whose actions are all empty is a wowsims ON/OFF switch: `actionGroupUsed` of it reads
--    `settings.wowsims_<snake of the name without " ON/OFF">`, its default on exactly when the APL's reference to it is
--    not hidden; the class registers that setting for the spec (named "<Group> (wowsims.com)"). The header lists a
--    setting only when an emitted line reads it (ruling L14): a group whose readers were all omitted is no setting.
-- 4. `auraIsKnown` (wowsims: the aura is registered on its source unit, Self by default): on Self or the target, an
--    ID that resolves (rule 5, or a kit talent's spell) to a talent's key or aura is `talent.<key>.enabled`, to an
--    ability's key `action.<key>.known`, to any other aura `true`; an ID nothing resolves, or another unit, is false.
--    (wowsims registers a gear, set or consumable aura only when it is equipped or configured; `true` for one of those
--    may disagree, no APL reads one today.) Solo exports: another player's aura (wowsims's External, tag -1) is never
--    registered, so it is not known (false) and every other read of it is nil (rule 6: dropped).
-- 5. Keys, from the character's ability set (tests/Forever/helpers/engine.lua abilitySet: the class kit, the shared
--    content and every race's racials, as the engine merges them): a spell ID maps through the recipe's `map`, else
--    an ability's `id` and `copy`, auras by the recipe's aura-only `auras` map ({ [aura ID] = key }: an aura wowsims
--    keys by an ability's own spell ID, where `map` would also turn that ability's casts) then `map` then the set's
--    auras then abilities, items by an ability's `item` or `items` (the APLs at the pin that read such an aura: the
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
--    `leveling` lines are silent at 60, `levelingFirst` lines whenever their form is up. Each recipe `extra`
--    ({ before = action, line = text }, content outside wowsims's model) goes just before the first `actions` line of
--    `before` (an error when there is none). The recipe's `settings` ({ [key] = { default = bool, desc = text } }) are
--    pack settings like an ON/OFF group's: a line reads one as `settings.<key>`, and the header lists each one read.
--    The recipe's `prepullSkip` ({ action key, ... }: an owner ruling against a wowsims pre-pull cast) omits that
--    action's precombat lines, listed (an error when there is none).
--    The recipe's `requires` ({ [action key or group's snake name] = talent key }) puts `talent.<key>.enabled&` before
--    the condition of each such entry, in every list: an APL written for a talent build (wowsims picks it by that
--    talent, e.g. an Auto rotation) runs those entries only once the talent is taken, so a level without it skips them.
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
--    `cancel_buff,buff_name=<key>`; `autoSwingTime` MainHand / OffHand is `mainhand_speed` / `offhand_speed`.
--    `remainingTime` is `fight_remains`, which answers "unknown" (3600 s) on Forever: an API-forced deviation.
-- 11. `unitDistance` (wowsims's yards from the APL's unit to its target; the source unit is ignored, as wowsims does)
--    compared with a whole number N: `<=`/`<` N as `target.within<N>`, `>=`/`>` N as `target.outside<N>` (either
--    side; any other comparison or a non-integer N is unsupported). API-forced deviation: the client gives no yards,
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
--    omitted whole (rule 2).
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
--    only when wowsims fired it: its default is a tank's). `castAllStatBuffCooldowns` (every instant major cooldown
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
--    (its one field names an option value) is that value's setting term; with no field (protojson's zero value) or an
--    unknown value it is unsupported. The build's value (the request's `<spec>.options.classOptions.<option>` or
--    `.options.<option>`) is the setting's default in game and in the harness (`sim`), which the class registers as an
--    AceConfig `select`; the header lists it. An entry the APL never uses, or a build without the option, is an error.
-- 17. `multidot` (wowsims: the DoT cast on up to `maxDots` targets whose DoT has at most `maxOverlap` left) is the
--    cast's line under the entry's condition and `debuff.<key>.remains<=<maxOverlap>` (0 when absent), its aura read as
--    `dotRemainingTime` (rules 5, 6, 12; `rank` ignored, rule 5). Deviation, a `# Deviation:` header line by entry:
--    the current target only (`maxDots` unused). No `cycle_targets=1`: the engine's target cycling (State.lua SetupCycle) needs
--    other targets' DoTs (`active_dot`), which Forever does not give plainly (gap AO / AP), and the replay is one target.
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
    currentRage = "rage.current",
    currentEnergy = "energy.current",
    currentMana = "mana.current",
    currentManaPercent = "mana.pct",
    maxMana = "mana.max",
    currentManaRegen = "mana.regen",
    currentComboPoints = "combo_points.current",
    currentHealthPercent = "health.pct",
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
--- settings, exclusive, requires, maintenance, select, auras), the spec's exported log text `log` (rule 13; nil: the
--- automatic actions are unsupported) and the request's player `player` (rule 16's option values).
function M.context(set, r, log, player)
    local c = {
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
        if choice == nil or x.candidates[choice] == nil then
            error(("select: the build sets no %s"):format(x.option), 0)
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
        if x.active then
            c.selectValue[x.active] = { "active", sel }
        end
        if x.is then
            c.selectValue[x.is] = { "is", sel }
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

local function auraKey(c, id)
    return c.auraMap[id] or c.map[id] or c.auraOf[id] or c.keyOf[id] or unsupported("aura " .. tostring(id))
end

local function drop(c, what) -- each ID once an entry
    for _, d in ipairs(c.dropped) do
        if d == what then
            return
        end
    end
    c.dropped[#c.dropped + 1] = what
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
    local x = c.auraMap[id] or c.map[id] or c.auraOf[id] or c.keyOf[id]
    if not x then
        drop(c, "aura " .. tostring(id))
    end
    return x
end

local UNIT = { Self = "buff", CurrentTarget = "debuff", Target = "debuff" }
local FLIP = { OpLe = "OpGe", OpLt = "OpGt", OpGe = "OpLe", OpGt = "OpLt", OpEq = "OpEq", OpNe = "OpNe" } -- N op d
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
        local res = u == "Pet" and M.VALUES[k]:match("^(%a+)%.current$") -- the pet's power: the sim's pet.<resource>
        if res then
            return "pet." .. res, false
        elseif u ~= "Self" then
            unsupported(k .. " of " .. tostring(u))
        end
        return M.VALUES[k], false
    elseif k == "variableRef" then
        return value(c, c.vars[v.name] or unsupported("variable " .. v.name), pct)
    elseif k == "math" then
        if percentRead(c, v.lhs) or percentRead(c, v.rhs) then -- its 0-100 against wowsims's 0-1 leaks (rule 8)
            unsupported("a percent read in math")
        end
        local l, lu = value(c, v.lhs)
        local r, ru = value(c, v.rhs)
        local op = M.MATH[v.op] or unsupported("math " .. tostring(v.op))
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
    elseif k == "spellTimeToReady" or k == "spellCastTime" or k == "spellCurrentCost" then
        local x = readSpell(c, v.spellId)
        if not x then
            return nil, true
        end
        local field = ({
            spellTimeToReady = "cooldown." .. x .. ".remains",
            spellCastTime = "action." .. x .. ".cast",
            spellCurrentCost = "action." .. x .. ".cost",
        })[k]
        return field, reads(c, x)
    elseif k == "dotRemainingTime" then
        local a = readAura(c, v.spellId.spellId)
        if not a then
            return nil, true
        end
        return "debuff." .. a .. ".remains", reads(c, a)
    elseif k == "auraRemainingTime" or k == "auraNumStacks" then
        if v.auraId.tag == -1 then
            return nil, true -- rule 4: another player's aura, never registered
        end
        local a = readAura(c, v.auraId.spellId)
        if not a then
            return nil, true
        end
        return unit(v) .. "." .. a .. (k == "auraNumStacks" and ".stack" or ".remains"), reads(c, a)
    elseif k == "autoSwingTime" and (v.autoType == "MainHand" or v.autoType == "OffHand") then -- rule 10
        return v.autoType == "MainHand" and "mainhand_speed" or "offhand_speed", false
    elseif k == "autoTimeToNext" and v.autoType == "MainHandAuto" then
        return "mainhand_remains", false
    elseif k == "autoTimeSinceLast" and v.autoType == "MainHandAuto" then
        return "(mainhand_speed-mainhand_remains)", false
    elseif k == "totemRemainingTime" then
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
        local parts, us = {}, {}
        for i, kid in ipairs(kids) do
            parts[i], us[i] = emit(kid[2], kid[1], k == "and"), kid[2]
        end
        local s = #parts == 1 and parts[1] or ("(" .. table.concat(parts, k == "and" and "&" or "|") .. ")")
        return s, nil, (not identity) and nilAnd(us)
    elseif k == "not" then
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
        if not side or not (n and n:match("^%d+$")) then
            unsupported("unitDistance " .. tostring(v.op) .. " " .. tostring(n))
        end
        return "target." .. side .. n, nil, false
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
            return nil, false, false
        end
        local tk = c.talentOf[id] or (c.talentKey[x] and x) -- a talent's spell, or a recipe `map` to a talent's key
        local test = tk and ("talent." .. tk .. ".enabled") or knownTest(c, x)
        if not test then
            return nil, true, false
        end
        return test, nil, false
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
    elseif k == "spellIsReady" then
        local x = readSpell(c, v.spellId)
        if not x then
            return nil, nil, true
        end
        return "cooldown." .. x .. ".ready", nil, reads(c, x)
    elseif k == "spellCanCast" then
        local x = readSpell(c, v.spellId)
        if not x then
            return nil, nil, true
        end
        return "action." .. x .. ".ready", nil, reads(c, x)
    elseif k == "spellIsKnown" then -- wowsims: a constant, false for a spell it lacks; ours for an ID nothing resolves
        local x = spellLookup(c, v.spellId)
        if not x then
            return nil, false, false
        end
        return "action." .. x .. ".known", nil, false
    elseif k == "isExecutePhase" then
        if v.threshold == "E20" and c.executePhase then
            return c.executePhase, nil, false
        end
        unsupported("isExecutePhase " .. tostring(v.threshold))
    elseif k == "actionGroupUsed" then
        return "settings." .. (c.toggles[v.name] or unsupported("actionGroupUsed " .. tostring(v.name))), nil, false
    elseif k == "variableRef" then
        return bool(c, c.vars[v.name] or unsupported("variable " .. v.name))
    elseif c.selectValue[k] then -- rule 16
        local kind, sel = c.selectValue[k][1], c.selectValue[k][2]
        sel.used = true
        if kind == "is" then
            local _, val = next(v)
            if val == nil then
                unsupported(k .. " of no candidate")
            end
            return sel.term[val] or unsupported(k .. " of " .. tostring(val)), nil, false
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
    if not c.talentKey[talent] then
        error(("requires: %s is not a talent key"):format(tostring(talent)), 0)
    end
    local t = "talent." .. talent .. ".enabled"
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
    local keys, seen = {}, {}
    for _, s in ipairs(list) do
        local x, what = spellLookup(c, s)
        if not x then
            c.notes[#c.notes + 1] = kind .. ": unmapped " .. what
        elseif c.namedKeys[x] then -- another ID of a key the APL casts itself: its own line stands
            c.notes[#c.notes + 1] = kind .. ": " .. what .. " is " .. x .. ", which the APL casts itself"
        elseif not seen[x] then
            keys[#keys + 1], seen[x] = x, true
        end
    end
    return keys
end

local entry, guard

-- Rule 7's cast line of key `x`, without its condition: off-GCD and focus flags.
local function castBody(c, x)
    local tier = c.focus[x]
    if type(tier) == "table" then
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
    if kind == "castSpell" or kind == "channelSpell" then
        local x = spellKey(c, a[kind].spellId)
        c.self, key = x, x
        body = castBody(c, x)
    elseif kind == "multidot" then -- rule 17: the cast under "its DoT has at most maxOverlap left", this target only
        local m = a.multidot
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
                    cond = required(c, x, cond and (sel.term[val] .. "&" .. paren(cond)) or sel.term[val])
                    out[#out + 1] = castBody(c, x) .. ",if=" .. cond
                end
            end
        end
        if #out == 0 then
            return nil, "never"
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
    if cond == false then
        return nil, "never"
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
            local cx = required(c, x, cond)
            out[i] = cx and (line .. ",if=" .. cx) or line
        end
        return out
    end
    cond = required(c, key, cond)
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
        if x ~= "call_action_list" and x ~= "run_action_list" and x ~= "cancel_buff" and c.ability[x] then
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
            local terms = { "!" .. r.unit .. "." .. x .. ".up" }
            for j = i + 1, later[i] and 0 or #out do
                local y, s = keys[j], eff[j]
                if y and y ~= x and s.unit == r.unit and (r.removes[y] or s.removes[x]) then
                    local k = knownTest(c, y) -- rule 6: another ability's aura, read only once it is learned
                    terms[#terms + 1], later[j] = "(!" .. k .. "|!" .. s.unit .. "." .. y .. ".up)", true
                end
            end
            g = table.concat(terms, "&")
        elseif r then
            g = "!totem." .. r.element .. ".up"
        end
        if g then
            local head, cond = b:match("^(.-),if=(.*)$")
            out[i] = head and (head .. ",if=" .. g .. "&" .. paren(cond)) or (b .. ",if=" .. g)
        end
    end
end

--- The SimC text of `rotation` (a wowsims APL table) under context `c`, the omitted entries
--- ({ "<list> #<n>: <why>" }) and the settings an emitted line reads ({ { setting key, default, source } }: the APL's
--- ON/OFF groups in its order, then the recipe's `settings` by key).
function M.translate(rotation, c)
    c.vars, c.toggles, c.used, c.seen, c.named, c.namedKeys, c.notes, c.dropped = {}, {}, {}, {}, {}, {}, {}, {}
    c.callers, c.deviated, c.deviations = {}, {}, {}
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
    local toggles, shown = {}, {}
    for _, e in ipairs(rotation.priorityList or {}) do
        local g = e.action and e.action.groupReference
        if g and not e.hide then
            shown[g.groupName] = true
        end
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
                c.notes, c.dropped, c.deviations = {}, {}, {}
                local ok, body, why = pcall(entry, c, e)
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
                        c.notes[#c.notes + 1] = "dropped the unresolved " .. what .. " (its branch only)"
                    end
                    for _, n in ipairs(c.notes) do
                        omitted[#omitted + 1] = ("%s #%d: %s"):format(name, i, n)
                    end
                    for _, d in ipairs(c.deviations) do -- an emitted line that differs from wowsims (rule 17)
                        c.deviated[#c.deviated + 1] = ("# Deviation: %s #%d: %s"):format(name, i, d)
                    end
                elseif why ~= "toggle" then
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
        local ok, n = pcall(value, c, e.doAtValue or {})
        n = ok and tonumber(n)
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
    for _, line in ipairs(c.leveling) do
        table.insert(byName.default, line)
    end
    for i, line in ipairs(c.levelingFirst) do
        table.insert(byName.default, i, line)
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
    return text, omitted, read, header
end

--- Writes spec `spec`'s pack: src/Hekili_<Class>/APLs/<recipe.pack>.simc from the checked-in request (`ex`:
--- export.lua's module), its description, toggles and omitted entries in the header.
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
    local text, omitted, toggles, header = M.translate(player.rotation, M.context(set, r, log, player))
    local Class = r.class:sub(1, 1) .. r.class:sub(2):lower()
    local out = {
        ("# %s: the wowsims/forever default APL for %s (%s), translated to this addon's keys."):format(
            r.pack,
            r.name,
            r.apl or r.build
        ),
        "# Data: wowsims/forever (MIT, https://github.com/wowsims/forever) at " .. ex.PIN:sub(1, 12) .. ".",
        "",
        ("# Generated by `make wowsims-packs` (tools/wowsims/apl.lua) from tools/wowsims/specs/%s.lua: edit that recipe, not this file."):format(
            spec
        ),
    }
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
