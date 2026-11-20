#!/usr/bin/env bash
# LibHiddenValues stays standalone (extraction is a pure move): its code, tests and tools name no host addon, and no
# host addon names it. The host's name is assembled here so this file passes its own scan. The library's LICENSE holds
# the copyright line and is the one file exempt; docs/libhiddenvalues is cleaned by hand at extraction.
set -uo pipefail
cd "$(dirname "$0")/../.."
host="heki""li"
fail=0
hits=$(grep -rniI --exclude=LICENSE "$host" src/LibHiddenValues tests/LibHiddenValues tools/libhiddenvalues)
[ -n "$hits" ] && { echo "$hits"; fail=1; }
hits=$(grep -rnI -e "LibHiddenValues" -e "HiddenValues-1" src/[Hh]ek* 2>/dev/null)
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: LibHiddenValues and its host name each other nowhere"
exit $fail
