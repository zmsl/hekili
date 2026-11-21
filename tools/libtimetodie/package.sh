#!/usr/bin/env bash
# LibTimeToDie's release: one folder (and its zip) that carries LibHiddenValues, so an author embeds or installs
# LibTimeToDie only. OUT/LibTimeToDie is src/LibTimeToDie as is plus Libs/LibHiddenValues (src/LibHiddenValues
# unmodified); its XML and TOC load that copy's XML right after LibStub, before the library's own files. The
# repository keeps the one LibHiddenValues source: in development LibTimeToDie finds it through LibStub (OptionalDeps).
# LibStub runs the newest minor of each library from any folder and settles an equal minor by load order, so two
# copies of one minor must be byte-identical: bundle committed sources only, and LibHiddenValues bumps its MINOR on
# every change. Usage: tools/libtimetodie/package.sh [OUT] (default .release/libtimetodie; OUT/LibTimeToDie is rebuilt).
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${1:-.release/libtimetodie}
dst=$out/LibTimeToDie
version=$(sed -n 's/^## Version: *//p' src/LibTimeToDie/LibTimeToDie.toc | tr -d '\r')
mkdir -p "$out"
rm -rf "$dst"
cp -r src/LibTimeToDie "$dst"
cp -r src/LibHiddenValues "$dst/Libs/LibHiddenValues"
awk -v inc='    <Include file="Libs\\LibHiddenValues\\LibHiddenValues.xml"/>' \
    '{ print } /<Script file="Libs.LibStub.LibStub\.lua"\/>/ { print inc }' \
    src/LibTimeToDie/LibTimeToDie.xml >"$dst/LibTimeToDie.xml"
awk -v inc='Libs\\LibHiddenValues\\LibHiddenValues.xml' \
    '{ print } /^Libs.LibStub.LibStub\.lua/ { print inc }' \
    src/LibTimeToDie/LibTimeToDie.toc >"$dst/LibTimeToDie.toc"
for f in "$dst/LibTimeToDie.xml" "$dst/LibTimeToDie.toc"; do
    [ "$(grep -c 'LibHiddenValues\\LibHiddenValues.xml' "$f")" = 1 ] || { echo "no LibHiddenValues include in $f"; exit 1; }
done
zip=LibTimeToDie-$version.zip
rm -f "$out/$zip"
(cd "$out" && zip -qr "$zip" LibTimeToDie)
echo "$out/$zip"
