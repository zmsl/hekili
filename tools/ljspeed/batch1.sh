#!/usr/bin/env bash
# lj-speed spike batch 1 (runner): base times twice (the second with run A / run B seconds per fight), function profile,
# call-tree profile + trace log, GC settings on Destruction.
set -uo pipefail
cd "$(dirname "$0")/../.."
S=tests/Forever
FIVE="$S/loop_warlock_destruction_spec.lua $S/loop_warlock_shadow_brand_spec.lua $S/loop_warlock_affliction_spec.lua $S/loop_warlock_demonology_spec.lua $S/loop_warrior_protection_spec.lua"
R=tools/ljspeed/run.sh
echo "== base"
$R base 5 $FIVE
echo "== base2 (A/B seconds per fight)"
LJAB=1 $R base2 5 $FIVE
echo "== fn (-jp=pFvrm0i1)"
LJX='-jp=pFvrm0i1,@.fn' $R fn 5 $FIVE
echo "== flame (-jp=Gpfvi10 -jv)"
LJX='-jp=Gpfvi10,@.flame -jv=@.jv' $R flame 5 $FIVE
echo "== gc (Destruction)"
D=$S/loop_warlock_destruction_spec.lua
LJNAME=.base $R gc 1 $D &
LJNAME=.p400 LJPRE='collectgarbage("setpause",400)' $R gc 1 $D &
LJNAME=.p1000 LJPRE='collectgarbage("setpause",1000)' $R gc 1 $D &
LJNAME=.s400 LJPRE='collectgarbage("setstepmul",400)' $R gc 1 $D &
wait
cp .ab/default.tsv .ab/ljspeed/ 2>/dev/null
echo "== done"
