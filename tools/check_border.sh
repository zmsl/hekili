#!/usr/bin/env bash
# The belief/core border (border batch 3; docs/dev/architecture.md §1, §5): Game/ (the belief) imports nothing from
# the core, and the core reaches the belief only through ns.VirtualState.Drain, .Build, .SetLog and .WindowOp (the
# owner's approved calls; WindowOp(key, op, arg) carries the APL windows' operations, windows design v6 §5.6) and the
# facade, whose Facade.Window is the window read (re-pin decision 11) and Facade.DebuffCount the debuff count (option
# D, owner decision 2, 2026-11-11: active_dot), and Facade.TargetID the target's stable ID (L1734, one reader: State.lua's
# swapped-cast compare, enforced below), and Facade.Known whether one kind of hidden value answers (L1805, owner "yes"
# 2026-11-23: the APL conditions health.known, <power>.known, aura.known); no new pattern: ns.Facade is the allowed path. The core copies the
# windows through Facade.Window at every reset; WindowOp is the only thing it writes back. Comments are stripped before
# matching (`--` to the line's end; a string holding `--` is cut short, never a miss); the approved calls are blanked
# before the core-side match.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
# Game/: no Hekili (the addon table, its methods, its debug flag), no `class.`/`class:`/`class[`/`state.`/`state:`
# (the registry and the simulation), and no `ns` but `local _, ns = ...` and ns.Facade, ns.VirtualState,
# ns.VirtualStateInternal (so no ns.Output, ns["x"], rawget(ns, ...)). `class`/`state` not after `.` or a name
# character, so `I.class` and `r.state.meta` (a resource's own declarations, read through `def`) pass; no `state[`,
# Tickets.lua's own state array. An optional path argument (a file or a tree) stands in for Game/, for the spec.
for f in $(find "${1:-src/Hekili/Game}" -name '*.lua' | sort); do
    hits=$(sed -E 's/--.*$//' "$f" | sed -E -e 's/^[[:space:]]*local _, ns = \.\.\.[[:space:]]*$//; s/(^|[^[:alnum:]_])ns\.(Facade|VirtualStateInternal|VirtualState)([^[:alnum:]_]|$)/\1\3/g' -e 's/(^|[^[:alnum:]_])ns\.(Facade|VirtualStateInternal|VirtualState)([^[:alnum:]_]|$)/\1\3/g' |
        grep -nE '\bHekili\b|(^|[^.[:alnum:]_])(state[.:]|class[.:[])|\bns\b' | sed "s|^|$f:|")
    [ -n "$hits" ] && { echo "$hits"; fail=1; }
done
# Engine/, UI/, Options/, Integrations/ and Hekili.lua: no VS, ns.VirtualState or VirtualStateInternal but the four
# calls. An optional second path argument (a file or a tree, for the spec) is scanned with them; one that matches no
# .lua file fails.
# BORDER_STATE (for the spec) is a file scanned in State.lua's place.
real=src/Hekili/Engine/Sim/State.lua
state="${BORDER_STATE:-$real}"
core="$(find src/Hekili/Engine src/Hekili/UI src/Hekili/Options src/Hekili/Integrations -name '*.lua' | sort | sed "s|^$real\$|$state|") src/Hekili/Hekili.lua"
if [ -n "${2:-}" ]; then
    extra=$(find "$2" -name '*.lua' 2>/dev/null | sort)
    [ -z "$extra" ] && { echo "$2: no .lua file to scan"; fail=1; }
    core="$core $extra"
fi
for f in $core; do
    hits=$(sed -E 's/--.*$//' "$f" | sed -E -e 's/(^|[^[:alnum:]_])ns\.VirtualState\.(Drain|Build|SetLog|WindowOp)([^[:alnum:]_]|$)/\1\3/g' -e 's/(^|[^[:alnum:]_])ns\.VirtualState\.(Drain|Build|SetLog|WindowOp)([^[:alnum:]_]|$)/\1\3/g' |
        grep -nE '\bVS\b|ns\.VirtualState|VirtualStateInternal' | sed "s|^|$f:|")
    [ -n "$hits" ] && { echo "$hits"; fail=1; }
done
# Facade.TargetID (ledger L1734, the owner's A): the target's stable ID has one reader, Engine/Sim/State.lua's
# swapped-cast compare: exactly two lines naming TargetID, both inside `local function landsElsewhere(` up to its
# closing `    end`, and each exactly one of the two lines below (the in-flight cast's pin, the compare), so the ID never
# feeds a GUID field. Any other line naming TargetID there, a change to either line, any other core
# file, a pack (content reads the facade as Hekili.Client; BORDER_PACKS, for the spec, is the root holding the
# Hekili_* folders) or the stand-in naming it fails.
packs=$(find "${BORDER_PACKS:-src}" -mindepth 1 -maxdepth 1 -type d -name 'Hekili_*' -exec find {} -name '*.lua' \; | sort)
for f in $core $packs; do
    hits=$(sed -E 's/--.*$//' "$f" | grep -nE '\bTargetID\b')
    [ -z "$hits" ] && continue
    if [ "$f" = "$state" ]; then
        read -r lo hi < <(awk '/^    local function landsElsewhere\(/ { lo = NR } lo && !hi && NR > lo && /^    end$/ { hi = NR }
            END { print lo + 0, hi + 0 }' "$f")
        pin='^[0-9]+:[[:space:]]*castPin\.action, castPin\.id, castPin\.cast = e\.action, Facade\.TargetID\(\), rc[[:space:]]*$'
        cmp='^[0-9]+:[[:space:]]*return castPin\.action == e\.action and castPin\.id ~= nil and castPin\.id ~= Facade\.TargetID\(\)[[:space:]]*$'
        inside=$(echo "$hits" | awk -F: -v lo="$lo" -v hi="$hi" '$1 > lo && $1 < hi' | grep -E "$pin|$cmp")
        [ "$(echo "$inside" | grep -cE "$pin")" -eq 1 ] && [ "$(echo "$inside" | grep -cE "$cmp")" -eq 1 ] &&
            [ "$(echo "$hits" | wc -l)" -eq 2 ] && continue
    fi
    echo "$hits" | sed "s|^|$f:|"
    fail=1
done
[ $fail -eq 0 ] && echo "ok: Game/ names nothing of the core; the core names the belief only through Drain, Build, SetLog and WindowOp, and reads windows only through Facade.Window and debuff counts only through Facade.DebuffCount and hidden-value enablement only through Facade.Known; Facade.TargetID only in Engine/Sim/State.lua's swapped-cast compare"
exit $fail
