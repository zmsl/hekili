#!/usr/bin/env bash
# The belief/core border (border batch 3; docs/dev/architecture.md §1, §5): Game/ (the belief) imports nothing from
# the core, and the core reaches the belief only through ns.VirtualState.Drain, .Build and .SetLog (the owner's three
# approved calls), the facade, and Engine/Sim/Core.lua's debug bridge. Comments are stripped before matching (`--` to the
# line's end; a string holding `--` is cut short, never a miss); the approved calls and the bridge line are blanked
# before the core-side match.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
# Game/: no Hekili (the addon table, its methods, its debug flag), no `class.`/`state.` (the registry and the
# simulation), no ns.Output (the engine's publish side). `class.`/`state.` not after `.` or a name character, so
# `I.class` and `r.state.meta` (a resource's own declarations, read through `def`) pass.
for f in $(find src/Hekili/Game -name '*.lua' | sort); do
    hits=$(sed -E 's/--.*$//' "$f" | grep -nE '\bHekili\b|(^|[^.[:alnum:]_])(state[.:]|class\.)|ns\.Output' | sed "s|^|$f:|")
    [ -n "$hits" ] && { echo "$hits"; fail=1; }
done
# Engine/, UI/, Options/ and Hekili.lua: no VS, ns.VirtualState or VirtualStateInternal but the three calls and the
# bridge line (Engine/Sim/Core.lua's `Hekili.Virtual = { ... }`, anchored to the whole line).
bridge='^Hekili\.Virtual = \{ State = ns\.VirtualState, Events = ns\.VirtualStateInternal\.Events, Prof = ns\.VirtualStateInternal\.Prof \}$'
for f in $(find src/Hekili/Engine src/Hekili/UI src/Hekili/Options -name '*.lua' | sort) src/Hekili/Hekili.lua; do
    hits=$(sed -E 's/--.*$//' "$f" | sed -E "s/$bridge//" | sed -E 's/\bns\.VirtualState\.(Drain|Build|SetLog)\b//g' |
        grep -nE '\bVS\b|ns\.VirtualState|VirtualStateInternal' | sed "s|^|$f:|")
    [ -n "$hits" ] && { echo "$hits"; fail=1; }
done
[ $fail -eq 0 ] && echo "ok: Game/ names nothing of the core; the core names the belief only through Drain, Build, SetLog and the bridge"
exit $fail
