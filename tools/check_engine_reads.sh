#!/usr/bin/env bash
# Fails when the engine reaches into the UI (restructure plan, Task 4): the engine publishes through Engine.Output and
# raises hooks; it never names a display frame (HekiliDisplay*), the UI's namespace (ns.UI.) or its DisplayPool.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
engine=(src/Hekili/Engine/Sim/{Core,State,Targets,Scripts}.lua src/Hekili/Engine/{Output,Registry,Snapshot,Driver,WeakAuras}.lua)
for f in "${engine[@]}"; do
    [ -f "$f" ] || { echo "missing engine file: $f (renamed? update this list)"; fail=1; }
done
hits=$(grep -nE 'HekiliDisplay|ns\.UI\.|DisplayPool' "${engine[@]}")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
# UI/Options direction (Task 5): the UI, Options and Hekili.lua read the engine only through Engine.Registry, the
# commands and Engine.Output.status. `state.`/`class.` not after `.` or a name char, so `self.state` and `classes` pass.
# Exempt: Hekili.lua's definitions of Hekili.Class/Hekili.State, DevTools' generated-text line, and DisplayPool in
# UI.lua (which owns it).
ui=(src/Hekili/UI/UI.lua src/Hekili/Options/*.lua src/Hekili/Hekili.lua)
hits=$(grep -nE '(^|[^.[:alnum:]_])(state[.:]|class\.)|Hekili\.State\b|Hekili\.Class\b|\bns\.queue|ns\.getNumberTargets|VirtualStateInternal|DisplayPool|HekiliDisplay[A-Za-z]*\.(RecommendationsStr|NewRecommendations|activeThread)|HekiliEngine\b' "${ui[@]}" |
    grep -vE '^src/Hekili/Hekili\.lua:[0-9]+:Hekili\.(Class|State) = |^src/Hekili/Options/DevTools\.lua:[0-9]+:    self:Append\( "local class, state = Hekili\.Class, Hekili\.State" \)$|^src/Hekili/UI/UI\.lua:[0-9]+:.*Hekili\.DisplayPool\b')
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: the engine names no UI frame in ${#engine[@]} files; UI/Options read it through Engine in ${#ui[@]} files"
exit $fail
