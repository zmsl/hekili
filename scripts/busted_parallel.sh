#!/usr/bin/env bash
# One busted process per spec file, $BUSTED_JOBS (default $(nproc)) at a time (`make test`, `make test-<tag>`, `make
# gate`); the arguments go to each busted (tag filters). Prints each file's output in path order once all are done
# (skipping files that ran no test), then the summed counts; exits 1 if any file failed.
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
printf '%s\0' "${files[@]}" | xargs -0 -P "${BUSTED_JOBS:-$(nproc)}" -I{} bash -c 'run_one "$@"' _ {} "$@"

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
