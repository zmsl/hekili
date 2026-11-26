#!/usr/bin/env bash
# lj-speed spike batch 4 (runner): the default gate body at several job counts (the Makefile's is nproc - 2 = 10 here),
# wall time each; logs under .ab/ljspeed/jobs<N>.log for the row check. Order alternates so drift is visible.
set -uo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .ab/ljspeed
for j in ${JOBS_LIST:-10 8 12 6 10}; do
    n=$j
    [ -f ".ab/ljspeed/jobs$n.log" ] && n=${j}b
    s=$(date +%s.%N)
    BUSTED=scripts/busted_lj.sh BUSTED_JOBS=$j scripts/busted_parallel.sh --tags=loop,party,druid,rogue,paladin,shaman,hunter,mage,priest,warlock \
        >".ab/ljspeed/jobs$n.log" 2>&1
    rc=$?
    e=$(date +%s.%N)
    w=$(echo "$e - $s" | bc)
    sum=$(grep -h 'pending : ' ".ab/ljspeed/jobs$n.log" | awk '{s += $(NF-1)} END {printf "%.0f", s}')
    echo "jobs $j: wall $w s, work $sum s, rc $rc" | tee -a .ab/ljspeed/jobs.txt
done
