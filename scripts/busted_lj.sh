#!/usr/bin/env bash
# busted on the LuaJIT env (.lj/, scripts/bootstrap.sh) with the compiler on and its limits raised: the defaults
# (maxtrace=1000) flush every compiled trace again and again, 2.5x slower than PUC; with these, about 2.5x faster
# (arms-speed spike). LJ_JIT=off runs the interpreter only: the unit tier (`make test`, `check`) asserts "allocates
# nothing" through collectgarbage("count"), which counts the compiler's own trace allocations. Arguments are busted's.
set -euo pipefail
LJ=$(realpath "$(dirname "$0")/../.lj")
exec "$LJ/bin/lua" ${LJ_JIT:+-j$LJ_JIT} -Omaxtrace=65000 -Omaxmcode=262144 -Osizemcode=512 -Ohotloop=1000 -Ohotexit=200 -Otryside=20 \
    -Omaxside=2000 -Omaxsnap=4000 \
    -e "package.path='$LJ/share/lua/5.1/?.lua;$LJ/share/lua/5.1/?/init.lua;'..package.path;package.cpath='$LJ/lib/lua/5.1/?.so;'..package.cpath" \
    "$LJ/lib/luarocks/rocks-5.1/busted/2.3.0-1/bin/busted" "$@"
