#!/usr/bin/env bash
# lj-speed spike batch 2 (runner): clock cost on this machine; debugprofilestop call counts; P1 (fake debugprofilestop
# on an FFI monotonic clock) and P1+P2 (+ the loop's CPU clock through FFI) interleaved with base runs; a P1 profile.
set -uo pipefail
cd "$(dirname "$0")/../.."
S=tests/Forever
FIVE="$S/loop_warlock_destruction_spec.lua $S/loop_warlock_shadow_brand_spec.lua $S/loop_warlock_affliction_spec.lua $S/loop_warlock_demonology_spec.lua $S/loop_warrior_protection_spec.lua"
R=tools/ljspeed/run.sh
mkdir -p .ab/ljspeed
echo "== clockbench"
.lj/bin/lua tools/ljspeed/clockbench.lua | tee .ab/ljspeed/clockbench.txt
.lj/bin/lua -joff tools/ljspeed/clockbench.lua | tee -a .ab/ljspeed/clockbench.txt
echo "== count (LJSPEED_COUNT)"
LJAB=1 LJSPEED_COUNT=1 $R count 5 $FIVE
for i in 1 2; do
    echo "== base$i"
    LJAB=1 $R b$i 5 $FIVE
    echo "== p1 mono clock $i"
    LJAB=1 LJSPEED_CLOCK=mono $R p1m$i 5 $FIVE
    echo "== p1+p2 $i"
    LJAB=1 LJSPEED_CLOCK=mono LJSPEED_LOOPCPU=1 $R p12m$i 5 $FIVE
done
echo "== p1 cpu clock (same semantics as os.clock)"
LJAB=1 LJSPEED_CLOCK=cpu $R p1c 5 $FIVE
echo "== fn profile with P1+P2"
LJSPEED_CLOCK=mono LJSPEED_LOOPCPU=1 LJX='-jp=pFvrm0i1,@.fn' $R fnp12 5 $FIVE
echo "== done"
