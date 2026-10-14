#!/usr/bin/env bash
# Fails when a file loaded by Hekili.toc reads a game API from tools/api_inventory.txt directly
# instead of through LibStub("VirtualGameAPI-1.0"). Bare reads, namespace globals included, come from
# luacheck W113 (which ignores strings and comments; a `local C_Spell = VGA.C_Spell` covers its members);
# _G.Name and _G["Name"] reads come from grep.
set -uo pipefail
cd "$(dirname "$0")/.."
LUACHECK="${LUACHECK:-luacheck}"
command -v "$LUACHECK" >/dev/null || { echo "luacheck not found: set LUACHECK" >&2; exit 1; }
mapfile -t files < <(grep -E '\.lua\s*$' Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//')
# archived expansion folders are never redirected
mapfile -t files < <(printf '%s\n' "${files[@]}" | grep -vE '^(TheWarWithin|Dragonflight|Shadowlands|BfA|Legion|Wrath|Cataclysm|TheBurningCrusade)/')
globals=$(sed -E 's/\..*//' tools/api_inventory.txt | sort -u | paste -sd'|')
fail=0
hits=$("$LUACHECK" --no-config --std none --formatter plain --codes "${files[@]}" \
    | grep -E "accessing undefined variable '($globals)'")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
hits=$(grep -nE "_G(\.|\[[\"'])($globals)\b" "${files[@]}")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: no direct game API read in ${#files[@]} loaded files"
exit $fail
