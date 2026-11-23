#!/bin/sh
# tools/accuracy/run.sh: the run half of `make accuracy` (call it under flock, as the Makefile does). Every loop
# spec file with a solo gate, and every wowsims spec file, runs once under tools/accuracy/wrap.lua at nproc - 2 jobs;
# each file's output lands in .accuracy/raw/<kind>.<file>.txt for report.lua. Exit status of the specs is ignored:
# the report reads the printed lines (a floor miss is the gates' business, a missing line is the report's error).
# A second pass runs the same files under the live-auras arm (our own auras hidden in combat, as live; harness ab.lua,
# aura audit C1) into .accuracy/raw-live/: the "live-like" numbers. ACC_LIVE_ARM picks the arm: live-auras-none (the
# default, no Cooldown Manager item, runs for every class) or live-auras (the class's real layout; a class without a
# fixture prints nothing, shown as none). A provider arm records its floors and never fails.
cd "$(dirname "$0")/../.." || exit 1
BUSTED=${BUSTED:-.lua/bin/busted}
OUT=.accuracy/raw
ARM=${ACC_LIVE_ARM:-live-auras-none}
LOOPTAGS=$(echo "${GATE_TAGS:-loop,druid,rogue,paladin,shaman,hunter,mage,priest,warlock}" | sed 's/party,//;s/,party//')
rm -rf "$OUT" .accuracy/raw-live
mkdir -p "$OUT" .accuracy/raw-live
# Both passes record rows in .ab/default.tsv and .ab/$ARM.tsv, no gate-ab result: an earlier gate-ab's are put back.
KEEP=$(mktemp -d) || exit 1
for a in default "$ARM"; do
    [ ! -f ".ab/$a.tsv" ] || cp ".ab/$a.tsv" "$KEEP/$a.tsv" || exit 1
done
restore() {
    for a in default "$ARM"; do
        rm -f ".ab/$a.tsv"
        [ ! -f "$KEEP/$a.tsv" ] || cp "$KEEP/$a.tsv" ".ab/$a.tsv" || return 1
    done
    rm -rf "$KEEP"
}
trap restore EXIT
trap 'exit 1' INT TERM
jobs=$(($(nproc) > 3 ? $(nproc) - 2 : 1))
for pass in full live; do
    if [ "$pass" = full ]; then out=$OUT arm=; else out=.accuracy/raw-live arm=$ARM; fi
    {
        grep -l 'solo(' tests/Forever/loop_*_spec.lua | sed 's/^/loop /'
        grep -l 'ws\.gate' tests/Forever/wowsims_*_spec.lua | sed 's/^/wow /'
    } | LOOPTAGS=$LOOPTAGS BUSTED=$BUSTED OUT=$out HEKILI_AB=$arm xargs -P "$jobs" -L 1 sh -c '
        case $0 in loop) tags=$LOOPTAGS ;; *) tags=wowsims ;; esac
        timeout 3000 "$BUSTED" --helper=tools/accuracy/wrap.lua --tags="$tags" "$1" > "$OUT/$0.$(basename "$1" _spec.lua).txt" 2>&1'
done
echo "$ARM" > .accuracy/live-arm
ls "$OUT" | wc -l
