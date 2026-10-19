#!/usr/bin/env bash
# Checks a packager zip: the four addon folders at the root, LICENSE in Hekili/, no dev paths, TOC versions stamped.
set -euo pipefail
zip=${1:?usage: check_package.sh <zip>}
list=$(unzip -Z1 "$zip")
fail=0
need() { grep -qx "$1" <<<"$list" || { echo "missing: $1"; fail=1; }; }
for a in Hekili Hekili_Shared Hekili_Druid Hekili_Warrior; do need "$a/$a.toc"; done
need Hekili/LICENSE
need Hekili/embeds.xml
for bad in '^Hekili/src/' '/tests/' '/tools/' '^Hekili/docs/' '/APLs/' '\.simc$' '^Hekili/Makefile$' '^Hekili/\.'; do
    if grep -qE "$bad" <<<"$list"; then echo "unexpected: $(grep -E "$bad" <<<"$list" | head -3)"; fail=1; fi
done
ver=$(basename "$zip" .zip); ver=${ver#Hekili-}
ver=${ver%-forever}
for a in Hekili Hekili_Shared Hekili_Druid Hekili_Warrior; do
    v=$(unzip -p "$zip" "$a/$a.toc" | tr -d '\r' | sed -n 's/^## Version: //p')
    [ "$v" = "$ver" ] || { echo "$a.toc Version '$v' != zip version '$ver'"; fail=1; }
done
[ $fail -eq 0 ] && echo "package ok: $zip"
exit $fail
