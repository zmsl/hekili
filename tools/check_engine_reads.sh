#!/usr/bin/env bash
# Fails when the engine reaches into the UI (restructure plan, Task 4): the engine publishes through Engine.Output and
# raises hooks; it never names a display frame (HekiliDisplay*), the UI's namespace (ns.UI.) or its DisplayPool.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
engine=(src/Hekili/Engine/Sim/{Core,State,Targets,Scripts}.lua src/Hekili/Engine/{Output,Driver,WeakAuras}.lua)
# shortcut: Core's OnInitialize still builds the minimap/compartment menu (ns.UI.Menu, ns.UI.Minimap); exempt until
# that addon-init code leaves Core.
hits=$(grep -nE 'HekiliDisplay|ns\.UI\.|DisplayPool' "${engine[@]}" | grep -vE 'ns\.UI\.(Menu|Minimap)\b')
[ -n "$hits" ] && { echo "$hits"; fail=1; }
# UI/Options direction (Task 5): the second grep goes here.
[ $fail -eq 0 ] && echo "ok: the engine names no UI frame in ${#engine[@]} files"
exit $fail
