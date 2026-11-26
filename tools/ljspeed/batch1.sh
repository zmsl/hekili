#!/usr/bin/env bash
# lj-speed spike batch 1 (runner): base times, profiles + trace log, GC settings on Destruction.
set -uo pipefail
cd "$(dirname "$0")/../.."
S=tests/Forever
FIVE="$S/loop_warlock_destruction_spec.lua $S/loop_warlock_shadow_brand_spec.lua $S/loop_warlock_affliction_spec.lua $S/loop_warlock_demonology_spec.lua $S/loop_warrior_protection_spec.lua"
R=tools/ljspeed/run.sh
echo "== base"
$R base 5 $FIVE
echo "== prof (-jp=Gplvi1 -jv)"
LJX='-jp=Gplvi1,@.prof -jv=@.jv' $R prof 5 $FIVE
echo "== gc (Destruction)"
D=$S/loop_warlock_destruction_spec.lua
LJNAME=.base $R gc 1 $D &
LJNAME=.p400 LJPRE='collectgarbage("setpause",400)' $R gc 1 $D &
LJNAME=.p1000 LJPRE='collectgarbage("setpause",1000)' $R gc 1 $D &
LJNAME=.s400 LJPRE='collectgarbage("setstepmul",400)' $R gc 1 $D &
LJNAME=.p100 LJPRE='collectgarbage("setpause",100)' $R gc 1 $D &
wait
echo "== done"
