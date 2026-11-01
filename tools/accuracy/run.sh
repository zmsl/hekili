#!/bin/sh
# tools/accuracy/run.sh: the run half of `make accuracy` (call it under flock, as the Makefile does). Every loop
# spec file with a solo gate, and every wowsims spec file, runs once under tools/accuracy/wrap.lua at nproc - 2 jobs;
# each file's output lands in .accuracy/raw/<kind>.<file>.txt for report.lua. Exit status of the specs is ignored:
# the report reads the printed lines (a floor miss is the gates' business, a missing line is the report's error).
cd "$(dirname "$0")/../.." || exit 1
BUSTED=${BUSTED:-.lua/bin/busted}
OUT=.accuracy/raw
LOOPTAGS=$(echo "${GATE_TAGS:-loop,druid,rogue,paladin,shaman,hunter,mage,priest,warlock}" | sed 's/party,//;s/,party//')
rm -rf "$OUT"
mkdir -p "$OUT"
jobs=$(($(nproc) > 3 ? $(nproc) - 2 : 1))
{
    grep -l 'solo(' tests/Forever/loop_*_spec.lua | sed 's/^/loop /'
    grep -l 'ws\.gate' tests/Forever/wowsims_*_spec.lua | sed 's/^/wow /'
} | LOOPTAGS=$LOOPTAGS BUSTED=$BUSTED OUT=$OUT xargs -P "$jobs" -L 1 sh -c '
    case $0 in loop) tags=$LOOPTAGS ;; *) tags=wowsims ;; esac
    timeout 3000 "$BUSTED" --helper=tools/accuracy/wrap.lua --tags="$tags" "$1" > "$OUT/$0.$(basename "$1" _spec.lua).txt" 2>&1'
ls "$OUT" | wc -l
