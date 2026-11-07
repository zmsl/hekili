#!/bin/sh
# tools/wowsims/sim-pin/build.sh <checkout>: the oracle CLI <checkout>/wowsimcli-sim-pin, built from a wowsims/forever
# checkout at one of export.lua's pins (M.OLD_PIN, M.NEW_PIN) with that pin's oracle patches, this directory's
# <first 12 hex of the pin>/ (docs/dev/wowsims-packs.md "Oracle patches"): every *.patch applied and, where the set
# has one, leftover_db.go's items put back in the db. The checkout's files are restored after, built or not.
set -e
here=$(cd "$(dirname "$0")" && pwd)
cd "$1"
pin=$(git rev-parse HEAD)
set_dir="$here/$(echo "$pin" | cut -c1-12)"
grep -q "\"$pin\"" "$here/../export.lua" && [ -d "$set_dir" ] ||
    { echo "$1 is not at a pin in tools/wowsims/export.lua with an oracle patch set" >&2; exit 1; }
git diff --quiet || { echo "$1 has local changes" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'git checkout -q -- . && rm -rf tools/hekilidb "$tmp"' EXIT
for p in "$set_dir"/*.patch; do [ -e "$p" ] && git apply "$p"; done
make sim/core/proto/api.pb.go
if [ -e "$set_dir/leftover_db.go" ]; then
    git show d33930d04030c3f556582f31949f1f22c17da0e4:assets/database/db.bin >"$tmp/db.bin"
    git show d33930d04030c3f556582f31949f1f22c17da0e4:assets/database/leftover_db.bin >"$tmp/leftover_db.bin"
    mkdir -p tools/hekilidb
    cp "$set_dir/leftover_db.go" tools/hekilidb/main.go
    go run ./tools/hekilidb assets/database/db.bin assets/database/leftover_db.bin "$tmp/db.bin" "$tmp/leftover_db.bin" \
        assets/database/leftover_db.bin
fi
go build --tags=with_db -o wowsimcli-sim-pin ./cmd/wowsimcli/cli_main.go
