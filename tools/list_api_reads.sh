#!/usr/bin/env bash
# Lists the game API names the loaded Hekili files read: bare globals (via luacheck W113, which ignores strings and
# comments), C_* and AuraUtil namespace members (via grep), _G.Name reads, and Facade.Name / Facade.ns.Name reads
# (the secret or absent names Hekili reads through ns.Facade, Virtual/API/Facade.lua).
# Usage: tools/list_api_reads.sh [file ...]   (default: every .lua in Hekili.toc minus the archived
# expansion folders)
set -euo pipefail
cd "$(dirname "$0")/.."
LUACHECK="${LUACHECK:-luacheck}"
command -v "$LUACHECK" >/dev/null || { echo "luacheck not found: set LUACHECK" >&2; exit 1; }
if [ $# -gt 0 ]; then files=("$@"); else
    mapfile -t files < <(grep -E '\.lua\s*$' src/Hekili/Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//; s#^#src/Hekili/#')
    # archived expansion folders are never redirected, so their reads are not inventoried
    mapfile -t files < <(printf '%s\n' "${files[@]}" | grep -vE '^src/Hekili/(TheWarWithin|Dragonflight|Shadowlands|BfA|Legion|Wrath|Cataclysm|TheBurningCrusade)/')
fi
{
    "$LUACHECK" --no-config --std none --formatter plain --codes "${files[@]}" \
        | grep -oE "accessing undefined variable '[^']+'" | sed -E "s/.*'([^']+)'/\1/" || true
    grep -ohE "\b(C_[A-Za-z]+|AuraUtil)\.[A-Za-z_]+" "${files[@]}" || true
    grep -ohE "_G\.[A-Za-z_]+" "${files[@]}" | sed 's/^_G\.//' || true
    grep -ohE "\bFacade\.[A-Za-z_]+(\.[A-Za-z_]+)?" "${files[@]}" | sed 's/^Facade\.//' || true
} | sort -u
