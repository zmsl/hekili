#!/usr/bin/env bash
# Fails when the engine reaches into the UI (restructure plan, Task 4): the engine publishes through Engine.Output and
# raises hooks; it never names a display frame (HekiliDisplay*), the UI's namespace (ns.UI.) or its DisplayPool.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
engine=(src/Hekili/Engine/Sim/{Core,State,Targets,Scripts}.lua src/Hekili/Engine/{Output,Registry,Snapshot,Driver}.lua)
for f in "${engine[@]}"; do
    [ -f "$f" ] || { echo "missing engine file: $f (renamed? update this list)"; fail=1; }
done
hits=$(grep -nE 'HekiliDisplay|ns\.UI\.|DisplayPool' "${engine[@]}")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
# Profile port (Task 6): no engine file names the AceDB profile; the engine reads Engine.settings, which Options fills
# through Engine.Configure(profile). `self.DB.` with the dot, so Scripts' own `self.DB[ id ]` passes; comment lines
# pass. Exempt: Settings.lua, whose Configure takes the profile.
hits=$(grep -rnE 'Hekili\.DB\b|self\.DB\.|\.profile\b' src/Hekili/Engine --include='*.lua' |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*--|^src/Hekili/Engine/Settings\.lua:')
[ -n "$hits" ] && { echo "$hits"; fail=1; }
# UI/Options direction (Task 5): the UI, Options, Integrations/ and Hekili.lua read the engine only through Engine.Registry, the
# commands and Engine.Output, never the driver frame (ns.EngineFrame). `state.`/`class.` not after `.` or a name char,
# so `self.state` and `classes` pass.
# Exempt: Hekili.lua's definitions of Hekili.Class/Hekili.State, DevTools' generated-text line, and DisplayPool in
# UI.lua (which owns it).
ui=(src/Hekili/UI/UI.lua src/Hekili/Options/*.lua src/Hekili/Integrations/*.lua src/Hekili/Hekili.lua)
hits=$(grep -nE '(^|[^.[:alnum:]_])(state[.:]|class\.)|Hekili\.State\b|Hekili\.Class\b|\bns\.queue|ns\.getNumberTargets|VirtualStateInternal|DisplayPool|HekiliDisplay[A-Za-z]*\.(RecommendationsStr|NewRecommendations|activeThread)|HekiliEngine\b|ns\.EngineFrame' "${ui[@]}" |
    grep -vE '^src/Hekili/Hekili\.lua:[0-9]+:Hekili\.(Class|State) = |^src/Hekili/Options/DevTools\.lua:[0-9]+:    self:Append\( "local class, state = Hekili\.Class, Hekili\.State" \)$|^src/Hekili/UI/UI\.lua:[0-9]+:.*Hekili\.DisplayPool\b')
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: the engine names no UI frame in ${#engine[@]} files and no profile; UI/Options read it through Engine in ${#ui[@]} files"
exit $fail
