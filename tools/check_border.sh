#!/usr/bin/env bash
# The belief/core border (border batch 3; docs/dev/architecture.md §1, §5): Game/ (the belief) imports nothing from
# the core, and the core reaches the belief only through ns.VirtualState.Drain, .Build, .SetLog and .WindowOp (the
# owner's approved calls; WindowOp(key, op, arg) carries the APL windows' operations, windows design v6 §5.6) and the
# facade, whose Facade.Window is the window read (re-pin decision 11) and Facade.DebuffCount the debuff count (option
# D, owner decision 2, 2026-11-11: active_dot); no new pattern: ns.Facade is the allowed path. The core copies the
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
    hits=$(sed -E 's/--.*$//' "$f" | sed -E 's/^[[:space:]]*local _, ns = \.\.\.[[:space:]]*$//; s/\bns\.(Facade|VirtualStateInternal|VirtualState)\b//g' |
        grep -nE '\bHekili\b|(^|[^.[:alnum:]_])(state[.:]|class[.:[])|\bns\b' | sed "s|^|$f:|")
    [ -n "$hits" ] && { echo "$hits"; fail=1; }
done
# Engine/, UI/, Options/, Integrations/ and Hekili.lua: no VS, ns.VirtualState or VirtualStateInternal but the four
# calls. An optional second path argument (a file or a tree, for the spec) is scanned with them; one that matches no
# .lua file fails.
core="$(find src/Hekili/Engine src/Hekili/UI src/Hekili/Options src/Hekili/Integrations -name '*.lua' | sort) src/Hekili/Hekili.lua"
if [ -n "${2:-}" ]; then
    extra=$(find "$2" -name '*.lua' 2>/dev/null | sort)
    [ -z "$extra" ] && { echo "$2: no .lua file to scan"; fail=1; }
    core="$core $extra"
fi
for f in $core; do
    hits=$(sed -E 's/--.*$//' "$f" | sed -E 's/\bns\.VirtualState\.(Drain|Build|SetLog|WindowOp)\b//g' |
        grep -nE '\bVS\b|ns\.VirtualState|VirtualStateInternal' | sed "s|^|$f:|")
    [ -n "$hits" ] && { echo "$hits"; fail=1; }
done
[ $fail -eq 0 ] && echo "ok: Game/ names nothing of the core; the core names the belief only through Drain, Build, SetLog and WindowOp, and reads windows only through Facade.Window and debuff counts only through Facade.DebuffCount"
exit $fail
