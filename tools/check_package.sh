#!/usr/bin/env bash
# Checks a packager zip: the eleven addon folders at the root, LICENSE in Hekili/, the embedded libraries, no dev paths,
# TOC versions stamped.
set -euo pipefail
zip=${1:?usage: check_package.sh <zip>}
list=$(unzip -Z1 "$zip")
fail=0
need() { grep -qx "$1" <<<"$list" || { echo "missing: $1"; fail=1; }; }
for a in Hekili Hekili_Shared Hekili_Druid Hekili_Warrior Hekili_Rogue Hekili_Paladin Hekili_Shaman Hekili_Hunter Hekili_Mage Hekili_Priest Hekili_Warlock; do need "$a/$a.toc"; done
need Hekili/LICENSE
need Hekili/embeds.xml
# The embedded libraries (integration design 5.5): each one's main file and licence, and embeds.xml's guard opened by
# the packager: both Include lines outside every comment, LibHiddenValues first.
for l in LibHiddenValues LibTimeToDie; do need "Hekili/Libs/$l/$l.lua"; need "Hekili/Libs/$l/LICENSE"; done
incs=$(unzip -p "$zip" Hekili/embeds.xml | perl -0pe 's/<!--.*?-->//gs' | grep -o 'Libs.Lib[A-Za-z]*.Lib[A-Za-z]*\.xml' | tr '\\' '/' | tr '\n' ' ' || true)
[ "$incs" = "Libs/LibHiddenValues/LibHiddenValues.xml Libs/LibTimeToDie/LibTimeToDie.xml " ] ||
    { echo "embeds.xml: the library includes are not open in order: '$incs'"; fail=1; }
for bad in '^Hekili/src/' '/tests/' '/tools/' '/Testing/' '^Hekili/docs/' '/APLs/' '\.simc$' '^Hekili/Makefile$' '^Hekili/\.' 'ForeverProbe'; do
    if grep -qE "$bad" <<<"$list"; then echo "unexpected: $(grep -E "$bad" <<<"$list" | head -3)"; fail=1; fi
done
ver=$(basename "$zip" .zip); ver=${ver#Hekili-}
ver=${ver%-forever}
for a in Hekili Hekili_Shared Hekili_Druid Hekili_Warrior Hekili_Rogue Hekili_Paladin Hekili_Shaman Hekili_Hunter Hekili_Mage Hekili_Priest Hekili_Warlock; do
    v=$(unzip -p "$zip" "$a/$a.toc" | tr -d '\r' | sed -n 's/^## Version: //p')
    [ "$v" = "$ver" ] || { echo "$a.toc Version '$v' != zip version '$ver'"; fail=1; }
done
[ $fail -eq 0 ] && echo "package ok: $zip"
exit $fail
