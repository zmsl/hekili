#!/usr/bin/env bash
# lj-speed spike batch 6 (runner): three legs on the six Warlock gate files, three interleaved rounds, 6 jobs each:
# BASE (no P3), P3ONLY (P3, no P4), and this commit (P3 + P4); worktrees beside. Per-fight seconds (LJAB) for a paired
# per-file/seed comparison.
set -uo pipefail
cd "$(dirname "$0")/../.."
BASE=${BASE:?the no-P3 commit}
P3ONLY=${P3ONLY:?the P3-only commit}
S=tests/Forever
SIX="$S/loop_warlock_destruction_spec.lua $S/loop_warlock_shadow_brand_spec.lua $S/loop_warlock_affliction_spec.lua $S/loop_warlock_demonology_spec.lua $S/loop_warlock_sm_ruin_spec.lua $S/loop_warlock_cycle_spec.lua"
mkdir -p .ab/ljspeed
for leg in base:$BASE p3:$P3ONLY; do
    d=../ljs-${leg%%:*}
    rm -rf "$d"
    git worktree add -q --detach "$d" "${leg#*:}"
    ln -s "$(readlink -f .lj)" "$d/.lj"
done
export LJAB=1
for i in 1 2 3; do
    echo "== base $i"
    (cd ../ljs-base && tools/ljspeed/run.sh w_base$i 6 $SIX)
    echo "== P3 $i"
    (cd ../ljs-p3 && tools/ljspeed/run.sh w_p3_$i 6 $SIX)
    echo "== P3+P4 $i"
    tools/ljspeed/run.sh w_p34_$i 6 $SIX
done
cp -r ../ljs-base/.ab/ljspeed/* ../ljs-p3/.ab/ljspeed/* .ab/ljspeed/
echo "== done"
