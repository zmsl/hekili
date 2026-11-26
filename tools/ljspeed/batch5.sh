#!/usr/bin/env bash
# lj-speed spike batch 5 (runner): the unit tier (`make test`'s LuaJIT pass) with the compiler off (as today) and on,
# per-file busted seconds and failures of each, wall time; logs .ab/ljspeed/unit-{off,on}.log. Default job count.
set -uo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .ab/ljspeed
X=--exclude-tags=party,loop,druid,rogue,paladin,shaman,hunter,mage,priest,warlock,bench,puc
for mode in off on off2 on2; do
    s=$(date +%s.%N)
    case $mode in
    off*) LJ_JIT=off BUSTED=scripts/busted_lj.sh scripts/busted_parallel.sh $X >".ab/ljspeed/unit-$mode.log" 2>&1 ;;
    on*) BUSTED=scripts/busted_lj.sh scripts/busted_parallel.sh $X >".ab/ljspeed/unit-$mode.log" 2>&1 ;;
    esac
    rc=$?
    e=$(date +%s.%N)
    echo "unit $mode: wall $(echo "$e - $s" | bc) s, rc $rc, $(tail -3 ".ab/ljspeed/unit-$mode.log" | grep 'all files')" | tee -a .ab/ljspeed/unit.txt
done
