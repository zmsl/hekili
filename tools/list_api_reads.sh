#!/usr/bin/env bash
# Lists the game API names the loaded Hekili files read directly: bare globals (via luacheck W113,
# which ignores strings and comments), C_* and AuraUtil namespace members (via grep), and _G.Name reads.
# Usage: tools/list_api_reads.sh [file ...]   (default: every .lua in Hekili.toc)
set -euo pipefail
cd "$(dirname "$0")/.."
LUACHECK="${LUACHECK:-luacheck}"
command -v "$LUACHECK" >/dev/null || { echo "luacheck not found: set LUACHECK" >&2; exit 1; }
if [ $# -gt 0 ]; then files=("$@"); else
    mapfile -t files < <(grep -E '\.lua\s*$' Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//')
    # archived expansion folders are never redirected, so their reads are not inventoried
    files=( $(printf '%s\n' "${files[@]}" | grep -vE '^(TheWarWithin|Dragonflight|Shadowlands|BfA|Legion|Wrath|Cataclysm|TheBurningCrusade)/') )
fi
{
    "$LUACHECK" --no-config --std none --formatter plain --codes "${files[@]}" 2>/dev/null \
        | grep -oE "accessing undefined variable '[^']+'" | sed -E "s/.*'([^']+)'/\1/" || true
    grep -ohE "\b(C_[A-Za-z]+|AuraUtil)\.[A-Za-z_]+" "${files[@]}" || true
    grep -ohE "_G\.[A-Za-z_]+" "${files[@]}" | sed 's/^_G\.//' || true
} | sort -u
