#!/usr/bin/env bash
# lj-speed spike batch 6 (runner): P3 + P4 (this commit) against BASE (a worktree beside) on the six Warlock gate files,
# three interleaved rounds, 6 jobs each (one per file).
set -uo pipefail
cd "$(dirname "$0")/../.."
BASE=${BASE:?the base commit}
S=tests/Forever
SIX="$S/loop_warlock_destruction_spec.lua $S/loop_warlock_shadow_brand_spec.lua $S/loop_warlock_affliction_spec.lua $S/loop_warlock_demonology_spec.lua $S/loop_warlock_sm_ruin_spec.lua $S/loop_warlock_cycle_spec.lua"
B=../ljs-base6
rm -rf "$B"
git worktree add -q --detach "$B" "$BASE"
ln -s "$(readlink -f .lj)" "$B/.lj"
mkdir -p .ab/ljspeed
export LJAB=1
for i in 1 2 3; do
    echo "== base $i"
    (cd "$B" && tools/ljspeed/run.sh w_base$i 6 $SIX)
    echo "== P3+P4 $i"
    tools/ljspeed/run.sh w_p34_$i 6 $SIX
done
cp -r "$B/.ab/ljspeed/"* .ab/ljspeed/
echo "== done"
