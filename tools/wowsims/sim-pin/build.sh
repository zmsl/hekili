#!/bin/sh
# tools/wowsims/sim-pin/build.sh <checkout>: the oracle CLI <checkout>/wowsimcli-sim-pin, built from a wowsims/forever
# checkout at M.SIM_PIN with this directory's oracle patches (docs/dev/wowsims-packs.md "Oracle patches"): every *.patch
# applied and leftover_db.go's items put back in the db. The checkout's files are restored after, built or not.
set -e
here=$(cd "$(dirname "$0")" && pwd)
pin=$(sed -n 's/^M.PIN = "\([0-9a-f]*\)".*/\1/p' "$here/../export.lua") # M.SIM_PIN = M.PIN
[ -n "$pin" ] || { echo "no M.PIN in export.lua" >&2; exit 1; }
cd "$1"
[ "$(git rev-parse HEAD)" = "$pin" ] || { echo "$1 is not at M.PIN" >&2; exit 1; }
git diff --quiet || { echo "$1 has local changes" >&2; exit 1; }
tmp=$(mktemp -d)
trap 'git checkout -q -- . && rm -rf tools/hekilidb "$tmp"' EXIT
for p in "$here"/*.patch; do [ -e "$p" ] && git apply "$p"; done
make sim/core/proto/api.pb.go
git show d33930d04030c3f556582f31949f1f22c17da0e4:assets/database/db.bin >"$tmp/db.bin"
git show d33930d04030c3f556582f31949f1f22c17da0e4:assets/database/leftover_db.bin >"$tmp/leftover_db.bin"
mkdir -p tools/hekilidb
cp "$here/leftover_db.go" tools/hekilidb/main.go
go run ./tools/hekilidb assets/database/db.bin assets/database/leftover_db.bin "$tmp/db.bin" "$tmp/leftover_db.bin" \
    assets/database/leftover_db.bin
go build --tags=with_db -o wowsimcli-sim-pin ./cmd/wowsimcli/cli_main.go
