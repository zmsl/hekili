#!/usr/bin/env bash
# LibTimeToDie stays standalone (extraction is a pure move): its code, tests and tools name no host addon, no host
# addon names it, and LibHiddenValues (which it calls) names it nowhere. The host's name is assembled here so this
# file passes its own scan. The library's LICENSE holds the copyright line and is the one file exempt;
# docs/libtimetodie is cleaned by hand at extraction.
set -uo pipefail
cd "$(dirname "$0")/../.."
host="heki""li"
fail=0
hits=$(grep -rniI --exclude=LICENSE "$host" src/LibTimeToDie tests/LibTimeToDie tools/libtimetodie)
[ -n "$hits" ] && { echo "$hits"; fail=1; }
hits=$(grep -rnI -e "LibTimeToDie" -e "TimeToDie-1" src/[Hh]ek* src/LibHiddenValues tests/LibHiddenValues 2>/dev/null)
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: LibTimeToDie names no host, and neither the host nor LibHiddenValues names it"
exit $fail
