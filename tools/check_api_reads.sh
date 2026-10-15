#!/usr/bin/env bash
# Fails when a file loaded by Hekili.toc reads a game API from tools/api_inventory.txt (the names that are secret in
# combat, partly secret or absent on Forever) directly instead of through ns.Facade (VirtualState/Facade.lua). Bare
# reads come from luacheck W113 (which ignores strings and comments); _G.Name and _G["Name"] reads, and dotted reads of
# a kept namespace member (C_Spell.GetSpellCooldown: a declared namespace global hides its members from W113), come
# from grep. VirtualState/ reads the game only through its injected `api` (VirtualState/spec/secrets_spec.lua checks
# it); VirtualState/Facade.lua names every kept read in strings, so the dotted grep skips it.
set -uo pipefail
cd "$(dirname "$0")/.."
LUACHECK="${LUACHECK:-luacheck}"
command -v "$LUACHECK" >/dev/null || { echo "luacheck not found: set LUACHECK" >&2; exit 1; }
mapfile -t files < <(grep -E '\.lua\s*$' Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//')
bare=$(grep -vF '.' tools/api_inventory.txt | paste -sd'|')
dotted=$(grep -F '.' tools/api_inventory.txt | sed 's/\./\\./' | paste -sd'|')
fail=0
out=$("$LUACHECK" --no-config --std none --formatter plain --codes "${files[@]}"); rc=$?
[ $rc -ge 2 ] && { echo "luacheck failed (syntax error?)" >&2; exit 1; }
hits=$(grep -E "accessing undefined variable '($bare)'" <<<"$out")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
hits=$(grep -nE "_G(\.|\[[\"'])($bare)\b" "${files[@]}")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
# comments stripped, so a comment naming a kept read is not a read
hits=$(for f in "${files[@]}"; do
    [ "$f" = VirtualState/Facade.lua ] && continue
    sed 's/--.*$//' "$f" | grep -nE "(^|[^.[:alnum:]_])($dotted)\b" | sed "s|^|$f:|"
done)
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: no direct secret or absent game API read in ${#files[@]} loaded files"
exit $fail
