#!/usr/bin/env bash
# lj-speed spike (L1954), runner-only measurement driver; never merges. Runs each spec file in its own busted process on
# the .lj env with scripts/busted_lj.sh's flags, JOBS at a time, the gate's tags.
# usage: tools/ljspeed/run.sh <phase> <jobs> <spec>...
#   LJX   extra luajit arguments, '@' replaced by .ab/ljspeed/<phase>/<file> (e.g. LJX='-jp=Gplvi1,@.prof -jv=@.jv')
#   LJPRE Lua run before busted (e.g. 'collectgarbage("setpause",400)')
#   LJNAME suffix for the output names (several variants of one file in one phase)
set -uo pipefail
cd "$(dirname "$0")/../.."
export LJ
LJ=$(realpath .lj)
export OUTD=.ab/ljspeed/$1
jobs=$2
shift 2
mkdir -p "$OUTD"
one() {
    local f=$1 n x
    n=$(basename "$f" _spec.lua)${LJNAME:-}
    x=${LJX:-}
    x=${x//@/$OUTD/$n}
    TIMEFORMAT="TIME real %R user %U sys %S"
    # shellcheck disable=SC2086
    { time "$LJ/bin/lua" -Omaxtrace=65000 -Omaxmcode=262144 -Osizemcode=512 -Ohotloop=1000 -Ohotexit=200 -Otryside=20 \
        -Omaxside=2000 -Omaxsnap=4000 \
        -e "package.path='$LJ/share/lua/5.1/?.lua;$LJ/share/lua/5.1/?/init.lua;'..package.path;package.cpath='$LJ/lib/lua/5.1/?.so;'..package.cpath;${LJPRE:-}" \
        $x "$LJ/lib/luarocks/rocks-5.1/busted/2.3.0-1/bin/busted" --tags=loop,party,druid,rogue,paladin,shaman,hunter,mage,priest,warlock \
        "$f" >"$OUTD/$n.log" 2>&1; } 2>"$OUTD/$n.time"
    echo "$n $(cat "$OUTD/$n.time") $(grep -h ' seconds$' "$OUTD/$n.log" | tail -1)"
}
export -f one
printf '%s\n' "$@" | xargs -P "$jobs" -I{} bash -c 'one "$@"' _ {}
