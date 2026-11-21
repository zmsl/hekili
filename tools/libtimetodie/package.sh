#!/usr/bin/env bash
# LibTimeToDie's release: one folder (and its zip) that carries LibHiddenValues, so an author embeds or installs
# LibTimeToDie only. OUT/LibTimeToDie is src/LibTimeToDie as is plus Libs/LibHiddenValues (src/LibHiddenValues
# unmodified); its XML and TOC load that copy's XML right after LibStub, before the library's own files. The
# repository keeps the one LibHiddenValues source: in development LibTimeToDie finds it through LibStub (OptionalDeps).
# LibStub runs the newest minor of each library from any folder and settles an equal minor by load order, so two
# copies of one minor must be byte-identical: the package holds committed sources only (git archive HEAD; uncommitted
# changes are left out, with a note), and LibHiddenValues bumps its MINOR on every change.
# Usage: tools/libtimetodie/package.sh [--worktree] [OUT] (default OUT .release/libtimetodie; OUT/LibTimeToDie is
# rebuilt). --worktree packages the working tree instead: for tests only (check_standalone.sh), never a release.
set -euo pipefail
cd "$(dirname "$0")/../.."
worktree=0
if [ "${1:-}" = "--worktree" ]; then
    worktree=1
    shift
fi
out=${1:-.release/libtimetodie}
dst=$out/LibTimeToDie
from=src
tmp=
if [ $worktree -eq 0 ]; then
    git diff --quiet HEAD -- src/LibHiddenValues src/LibTimeToDie ||
        echo "note: uncommitted changes in src/LibHiddenValues or src/LibTimeToDie are left out (packaging HEAD)" >&2
    tmp=$(mktemp -d)
    git archive HEAD src/LibTimeToDie src/LibHiddenValues | tar -x -C "$tmp"
    from=$tmp/src
fi
version=$(sed -n 's/^## Version: *//p' "$from/LibTimeToDie/LibTimeToDie.toc" | tr -d '\r')
mkdir -p "$out"
rm -rf "$dst"
cp -r "$from/LibTimeToDie" "$dst"
cp -r "$from/LibHiddenValues" "$dst/Libs/LibHiddenValues"
awk -v inc='    <Include file="Libs\\LibHiddenValues\\LibHiddenValues.xml"/>' \
    '{ print } /<Script file="Libs.LibStub.LibStub\.lua"\/>/ { print inc }' \
    "$from/LibTimeToDie/LibTimeToDie.xml" >"$dst/LibTimeToDie.xml"
awk -v inc='Libs\\LibHiddenValues\\LibHiddenValues.xml' \
    '{ print } /^Libs.LibStub.LibStub\.lua/ { print inc }' \
    "$from/LibTimeToDie/LibTimeToDie.toc" >"$dst/LibTimeToDie.toc"
if [ -n "$tmp" ]; then
    rm -rf "$tmp"
fi
for f in "$dst/LibTimeToDie.xml" "$dst/LibTimeToDie.toc"; do
    [ "$(grep -c 'LibHiddenValues\\LibHiddenValues.xml' "$f")" = 1 ] || { echo "no LibHiddenValues include in $f"; exit 1; }
done
zip=LibTimeToDie-$version.zip
rm -f "$out/$zip"
(cd "$out" && zip -qr "$zip" LibTimeToDie)
echo "$out/$zip"
