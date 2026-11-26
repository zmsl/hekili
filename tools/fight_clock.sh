#!/usr/bin/env bash
# tools/fight_clock.sh LABEL SPEC [SEEDS] (refactor lane 4, L1827; an on-demand tool, not a gate arm: owner Q2):
# splits a fight's reading into "this fight" and "the fights before it". Runs LABEL's gate (SPEC: its loop spec file)
# on this working tree twice under tools/floors_trace.lua: chained (seeds 1..last on one boot, as the gate runs them:
# the clock, the pools and everything learned carried from fight to fight) and each seed of SEEDS alone on its own
# fresh boot (a new clock, full pools, nothing learned). Per seed it prints whether the fight is the same both ways
# (the carry changes nothing) or the first in-combat tick where the carried run departs, and each run's held /
# loOver / readyShort / flips for that fight. SEEDS: "s" or "a-b" (default 1-20). Arm: HEKILI_AB (default the default
# arm). Two busted processes at once. Exit 0: the report printed; 1: a run wrote no dump; 2: usage.
# Example: tools/fight_clock.sh "Fury L24" tests/Forever/loop_warrior_fury24_spec.lua 9
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
[ $# -ge 2 ] || {
    echo "usage: tools/fight_clock.sh LABEL SPEC [SEEDS]" >&2
    exit 2
}
LABEL=$1 SPEC=$2 SEEDS=${3:-1-20}
BUSTED=$(realpath "${BUSTED:-.lua/bin/busted}")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
last=${SEEDS#*-}
run() { # run <mode> <seeds>
    FLOORS_LABEL=$LABEL FLOORS_OUT=$TMP/$1.tsv FLOORS_SEEDS=$2 FLOORS_MODE=$1 \
        "$BUSTED" --helper=tools/floors_trace.lua "$SPEC" >"$TMP/$1.log" 2>&1
}
run chain "1-$last" &
run alone "$SEEDS" &
wait
for mode in chain alone; do
    [ -s "$TMP/$mode.tsv" ] || {
        echo "fight_clock: the $mode run wrote no dump for $LABEL; its log:" >&2
        tail -40 "$TMP/$mode.log" >&2
        exit 1
    }
done
echo "$LABEL, arm ${HEKILI_AB:-default}: seeds $SEEDS chained (1-$last on one boot) against each alone on a fresh boot"
.lua/bin/lua tools/floors.lua diverge "$TMP/chain.tsv" "$TMP/alone.tsv" clock
