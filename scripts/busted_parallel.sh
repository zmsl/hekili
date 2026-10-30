#!/usr/bin/env bash
# One busted process per spec file, $BUSTED_JOBS (default $(nproc)) at a time (`make test`, `make test-<tag>`, `make
# gate`); the arguments go to each busted (tag filters). Files start longest first by the last run's busted times for
# the same arguments (a file with none first), so a long file never starts last; each file's output is printed in path
# order once all are done (skipping files that ran no test), then the summed counts; exits 1 if any file failed.
set -uo pipefail
cd "$(dirname "$0")/.."
export BUSTED=${BUSTED:-.lua/bin/busted}
OUT=$(mktemp -d)
export OUT
trap 'rm -rf "$OUT"' EXIT

run_one() {
    local f=$1 log
    shift
    log="$OUT/${f//\//_}"
    "$BUSTED" "$@" "$f" >"$log" 2>&1
    echo $? >"$log.rc"
}
export -f run_one

mapfile -t files < <(find tests -name '*_spec.lua' | sort)
TIMES=${XDG_CACHE_HOME:-$HOME/.cache}/hekili-busted/$(printf '%s ' "$@" | md5sum | cut -c1-12)
mkdir -p "$(dirname "$TIMES")" && touch "$TIMES"
printf '%s\n' "${files[@]}" | awk 'FILENAME == ARGV[1] { t[$2] = $1; next } { print ($0 in t ? t[$0] : 1e9), $0 }' \
    "$TIMES" - | sort -s -k1,1gr | cut -d' ' -f2 | tr '\n' '\0' | xargs -0 -P "${BUSTED_JOBS:-$(nproc)}" -I{} bash -c 'run_one "$@"' _ {} "$@"

for f in "${files[@]}"; do # this run's times, for the next run's order
    awk -v f="$f" '/ success(es)? \/ .* pending : / { print $(NF - 1), f; exit }' "$OUT/${f//\//_}"
done >"$TIMES"

failed=()
for f in "${files[@]}"; do
    log="$OUT/${f//\//_}"
    rc=$(cat "$log.rc" 2>/dev/null)
    [ "$rc" = 0 ] && grep -q '^0 successes / 0 failures / 0 errors / 0 pending' "$log" && continue
    echo "== $f"
    cat "$log"
    [ "$rc" = 0 ] || failed+=("$f")
done
# busted's summary line: "N successes / N failures / N errors / N pending : S seconds"
cat "$OUT"/*.lua | awk '/ success(es)? \/ .* failures? \/ .* errors? \/ .* pending/ {
    s += $1; f += $4; e += $7; p += $10 }
    END { printf "\nall files: %d successes / %d failures / %d errors / %d pending\n", s, f, e, p }'
if [ ${#failed[@]} -gt 0 ]; then
    printf 'FAILED: %s\n' "${failed[@]}"
    exit 1
fi
