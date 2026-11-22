#!/usr/bin/env bash
# LibHiddenValues stays standalone (extraction is a pure move): its code, tests and tools name no host addon, and no
# host addon names it outside the allow-list. The host's name is assembled here so this file passes its own scan. The
# library's LICENSE holds the copyright line and is the one file exempt; docs/libhiddenvalues is cleaned by hand at
# extraction.
set -uo pipefail
cd "$(dirname "$0")/../.."
host="heki""li"
Host="Heki""li"
# The host files that may name it (full paths): the embed and the TOC's OptionalDeps (the host embeds it, integration
# design 5.5), and the belief's band source (lane B1). A later lane whose file names it adds that file here.
allow="^src/$Host/(embeds\.xml|$Host\.toc|Game/State/Sources/Bands\.lua):"
fail=0
hits=$(grep -rniI --exclude=LICENSE "$host" src/LibHiddenValues tests/LibHiddenValues tools/libhiddenvalues)
[ -n "$hits" ] && { echo "$hits"; fail=1; }
hits=$(grep -rnI -e "LibHiddenValues" -e "HiddenValues-1" src/[Hh]ek* 2>/dev/null | grep -vE "$allow")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: LibHiddenValues names no host, and its host names it only in the allow-list"
exit $fail
