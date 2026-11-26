#!/usr/bin/env bash
# lj-speed spike batch 3 (runner): P3 (harness trace-abort fixes, this commit) against the commit before it (BASE, a
# copy checked out beside), both with the clock config CFG; maxrecord flag variants; an unbiased profile (no syscalls
# in the loop: LJSPEED_CLOCK=mono LJSPEED_LOOPCPU=mono) with -jv.
set -uo pipefail
cd "$(dirname "$0")/../.."
BASE=${BASE:?the base commit}
S=tests/Forever
FIVE="$S/loop_warlock_destruction_spec.lua $S/loop_warlock_shadow_brand_spec.lua $S/loop_warlock_affliction_spec.lua $S/loop_warlock_demonology_spec.lua $S/loop_warrior_protection_spec.lua"
R=tools/ljspeed/run.sh
B=../ljs-base
rm -rf "$B"
git worktree add -q --detach "$B" "$BASE" # shares the partial clone's promisor (missing blobs fetched lazily)
ln -s "$(readlink -f .lj)" "$B/.lj"
mkdir -p .ab/ljspeed
export LJAB=1
for i in 1 2; do
    echo "== base (no P3) $i"
    (cd "$B" && env $CFG tools/ljspeed/run.sh base$i 5 $FIVE)
    echo "== P3 $i"
    env $CFG $R p3_$i 5 $FIVE
done
cp -r "$B/.ab/ljspeed/"* .ab/ljspeed/
echo "== P3 + maxrecord=16000"
LJX='-Omaxrecord=16000' env $CFG $R p3mr16 5 $FIVE
echo "== P3 + maxrecord=8000 maxirconst=1000"
LJX='-Omaxrecord=8000 -Omaxirconst=1000' env $CFG $R p3mr8 5 $FIVE
echo "== unbiased profile + jv (P3, no syscalls in the loop)"
LJSPEED_CLOCK=mono LJSPEED_LOOPCPU=mono LJX='-jp=pFvrm0i1,@.fn -jv=@.jv' $R fnmono 5 $FIVE
echo "== done"
