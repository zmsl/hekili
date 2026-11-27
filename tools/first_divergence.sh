#!/usr/bin/env bash
# tools/first_divergence.sh BASE HEAD LABEL SPEC [SEEDS] (refactor lane 4, L1827): where a moved floor row starts.
# Runs LABEL's gate (SPEC: the loop spec file that prints "LABEL solo:"; tools/floors.lua moved names it from two gate
# logs) on BASE's tree and on HEAD's under tools/floors_trace.lua, seeds 1..last on one boot as the gate runs them
# (SEEDS default 1-20), in the arm HEKILI_AB names (default the default arm), and prints per fight the first in-combat
# tick where the two runs differ and what differs first: the icon, the belief's power or the world. The first fight
# that differs is where the move starts; a later fight whose boot clock moved was re-timed by an earlier one.
# BASE / HEAD: a commit (exported with git archive into a temporary directory, removed on exit, as tools/red_first.sh)
# or "." (this working tree). Read-only on the repository. Two busted processes at once (one per tree).
# Exit 0: the report printed; 1: a run wrote no dump (its log is printed); 2: usage.
# Example: tools/first_divergence.sh e59706ac9 50984ec49 "Fury L24" tests/Forever/loop_warrior_fury24_spec.lua
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
[ $# -ge 4 ] || {
    echo "usage: tools/first_divergence.sh BASE HEAD LABEL SPEC [SEEDS]" >&2
    exit 2
}
BASE=$1 HEAD=$2 LABEL=$3 SPEC=$4 SEEDS=${5:-1-20}
ROOT=$(pwd)
BUSTED=$(realpath "${BUSTED:-.lua/bin/busted}")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# tree <ref> <dir name>: the directory holding <ref>'s files ("." is this checkout)
tree() {
    if [ "$1" = . ]; then
        echo "$ROOT"
        return
    fi
    git rev-parse --verify -q "$1^{commit}" >/dev/null || {
        echo "first_divergence: unknown ref $1" >&2
        return 2
    }
    mkdir -p "$TMP/$2" && git archive "$1" | tar -x -C "$TMP/$2" && ln -s "$ROOT/.lua" "$TMP/$2/.lua" && echo "$TMP/$2"
}
A=$(tree "$BASE" base) || exit 2
B=$(tree "$HEAD" head) || exit 2

run() { # run <tree> <side>
    (cd "$1" && FLOORS_LABEL=$LABEL FLOORS_OUT=$TMP/$2.tsv FLOORS_SEEDS=1-${SEEDS#*-} FLOORS_MODE=chain \
        "$BUSTED" --helper="$ROOT/tools/floors_trace.lua" "$SPEC" >"$TMP/$2.log" 2>&1)
}
run "$A" base &
run "$B" head &
wait
for side in base head; do
    [ -s "$TMP/$side.tsv" ] || {
        echo "first_divergence: the $side run wrote no dump for $LABEL; its log:" >&2
        tail -40 "$TMP/$side.log" >&2
        exit 1
    }
done
echo "$LABEL, arm ${HEKILI_AB:-default}, seeds $SEEDS on one boot: base $BASE, head $HEAD"
"$ROOT/.lua/bin/lua" "$ROOT/tools/floors.lua" diverge "$TMP/base.tsv" "$TMP/head.tsv"
