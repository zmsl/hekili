#!/usr/bin/env bash
# Fails when a file loaded by Hekili.toc reads a game API from tools/api_inventory.txt directly instead of through
# ns.Facade (VirtualState/Facade.lua; event-facade spec §1.2): every game read goes through the facade. Bare reads,
# namespace globals included, come from luacheck W113 (which ignores strings and comments; a `local C_Spell =
# Facade.C_Spell` covers its members); _G.Name and _G["Name"] reads come from grep, and so does a frame method reached
# through getmetatable, the one way around the event facade's shadowed RegisterEvent. VirtualState/ reads the game
# only through its injected `api` (VirtualState/spec/secrets_spec.lua checks it).
set -uo pipefail
cd "$(dirname "$0")/.."
LUACHECK="${LUACHECK:-luacheck}"
command -v "$LUACHECK" >/dev/null || { echo "luacheck not found: set LUACHECK" >&2; exit 1; }
mapfile -t files < <(grep -E '\.lua\s*$' Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//')
globals=$(cut -f1 tools/api_inventory.txt | sed -E 's/\..*//' | sort -u | paste -sd'|')
fail=0
out=$("$LUACHECK" --no-config --std none --formatter plain --codes "${files[@]}"); rc=$?
[ $rc -ge 2 ] && { echo "luacheck failed (syntax error?)" >&2; exit 1; }
hits=$(grep -E "accessing undefined variable '($globals)'" <<<"$out")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
hits=$(grep -nE "_G(\.|\[[\"'])($globals)\b" "${files[@]}")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
# shortcut: catches only a getmetatable read and a (Un)Register...Event call on one line; a split read needs review.
hits=$(grep -nE "getmetatable\(.*(Register|Unregister)[A-Za-z]*Event" "${files[@]}")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: no direct game API read in ${#files[@]} loaded files"
exit $fail
