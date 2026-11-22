#!/usr/bin/env bash
# LibTimeToDie stays standalone (extraction is a pure move): its code, tests and tools name no host addon, no host
# addon names it outside the allow-list, and LibHiddenValues (which it calls) names it nowhere. The host's name is
# assembled here so this file passes its own scan. The library's LICENSE holds the copyright line and is the one file
# exempt; docs/libtimetodie is cleaned by hand at extraction.
set -uo pipefail
cd "$(dirname "$0")/../.."
host="heki""li"
Host="Heki""li"
# The host files that may name it (full paths): the embed and the TOC's OptionalDeps (the host embeds it after
# LibHiddenValues). A later lane whose file names it adds that file here. LibHiddenValues has no allow-list.
allow="^src/$Host/(embeds\.xml|$Host\.toc):"
fail=0
hits=$(grep -rniI --exclude=LICENSE "$host" src/LibTimeToDie tests/LibTimeToDie tools/libtimetodie)
[ -n "$hits" ] && { echo "$hits"; fail=1; }
hits=$(grep -rnI -e "LibTimeToDie" -e "TimeToDie-1" src/[Hh]ek* src/LibHiddenValues tests/LibHiddenValues 2>/dev/null |
    grep -vE "$allow")
[ -n "$hits" ] && { echo "$hits"; fail=1; }
[ $fail -eq 0 ] && echo "ok: LibTimeToDie names no host, LibHiddenValues names it nowhere, the host only in the allow-list"
# The release folder (LibHiddenValues bundled) builds and loads through its own TOC: from the working tree (the
# package script's test mode), so the check sees what is about to be committed.
tmp=$(mktemp -d)
lua=.lua/bin/lua
[ -x "$lua" ] || lua=lua5.1
if bash tools/libtimetodie/package.sh --worktree "$tmp" >/dev/null; then
    "$lua" tools/libtimetodie/load_package.lua "$tmp/LibTimeToDie" || fail=1
else
    fail=1
fi
rm -rf "$tmp"
exit $fail
