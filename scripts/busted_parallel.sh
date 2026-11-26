#!/usr/bin/env bash
# One busted process per spec file, $BUSTED_JOBS (default $(nproc)) at a time (`make test`, `make test-<tag>`, `make
# gate`); the arguments go to each busted (tag filters). Files start longest first by the last run's busted times for
# the same arguments (a file with none first; no usable cache: path order), so a long file never starts last; each
# file's output is printed in path order once all are done (skipping files that ran no test), then the summed counts; exits 1 if any file failed.
# While running, one progress line per finished file. With GITHUB_ACTIONS=true the per-file output is also a collapsible
# group, failures are ::error annotations, and $GITHUB_STEP_SUMMARY gets a table.
set -uo pipefail
cd "$(dirname "$0")/.."
export BUSTED=${BUSTED:-.lua/bin/busted}
OUT=$(mktemp -d)
export OUT
if [ -n "${DETECT_WRITE:-}" ]; then # the floors file is read-modify-written by every writer: no parallel runs
    BUSTED_JOBS=1
    echo "DETECT_WRITE set: running the spec files serially (BUSTED_JOBS=1)"
fi
trap 'rm -rf "$OUT"' EXIT

# One progress line per finished file, printed at once (a noclobber-file lock keeps parallel jobs from interleaving and the counter
# exact): "[done/total done, N running] file ok|FAIL 3m41s, about 6 min left". The ETA is the last-run times of the files
# not yet finished over the job count; none known, none printed. The report after the run does not depend on these lines.
progress() {
    local f=$1 rc=$2 secs=$3 log=$4 status=ok done left eta="" line
    [ "$rc" = 0 ] || status=FAIL
    awk '/ failures? \/ .* errors? \/ / { if ($4 + $7 > 0) bad = 1 } END { exit !bad }' "$log" && status=FAIL
    until (set -C; : >"$OUT/.lock") 2>/dev/null; do sleep 0.05; done # O_EXCL: mkdir races on uutils coreutils
    echo "$f" >>"$OUT/.finished"
    done=$(wc -l <"$OUT/.finished" | tr -d ' ')
    left=$(awk 'FILENAME == ARGV[1] { d[$0] = 1; next } !($2 in d) { s += $1; n++ } END { if (n) printf "%d", s }' \
        "$OUT/.finished" "$TIMES")
    if [ -n "$left" ] && [ "$left" -gt 0 ]; then
        eta=$(awk -v s="$left" -v j="$JOBS" 'BEGIN { m = int(s / j / 60 + 0.5); printf ", %s left", m < 1 ? "under 1 min" : "about " m " min" }')
    fi
    line=$(printf '[%d/%d done, %d running] %s %s %dm%02ds%s' "$done" "$TOTAL" "$((TOTAL - done < JOBS ? TOTAL - done : JOBS))" \
        "$f" "$status" "$((secs / 60))" "$((secs % 60))" "$eta")
    if [ "${GITHUB_ACTIONS:-}" = true ]; then # a collapsible group per file; failures become annotations (20 a run at most)
        echo "::group::$line"
        cat "$log"
        echo "::endgroup::"
        # busted prints "Failure → file @ line", the test name, then "file:line: message"
        awk -v f="$f" -v cap=20 -v used="$(cat "$OUT/.annot" 2>/dev/null || echo 0)" '
            /^(Failure|Error) → / { ln = ""; n = split($0, a, " @ "); if (n > 1) ln = a[2]; st = 1; next }
            st == 1 { name = $0; gsub(/%/, "%25", name); st = 2; next }
            st == 2 { msg = $0; gsub(/%/, "%25", msg); gsub(/\r/, "", msg)
                if (match(msg, /[^ ]+:[0-9]+:/)) { split(substr(msg, RSTART, RLENGTH), b, ":"); ln = b[2] }
                if (used < cap) { printf "::error file=%s%s::%s: %s\n", f, (ln != "" ? ",line=" ln : ""), name, msg; used++ }
                st = 0 }
            END { print used > "/dev/stderr" }' "$log" 2>"$OUT/.annot"
        awk -v f="$f" -v st="$status" -v t="$secs" '/ success(es)? \/ .* failures? \/ .* errors? \/ / { p = $1; x = $4 + $7 }
            END { printf "%s\t%s\t%d\t%d\t%d\n", f, st, t, p, x }' "$log" >>"$OUT/.rows"
    else
        echo "$line"
    fi
    rm -f "$OUT/.lock"
}

run_one() {
    local f=$1 log start=$SECONDS rc
    shift
    log="$OUT/${f//\//_}"
    "$BUSTED" "$@" "$f" >"$log" 2>&1
    rc=$?
    echo $rc >"$log.rc"
    progress "$f" "$rc" "$((SECONDS - start))" "$log"
}
export -f run_one progress

mapfile -t files < <(find tests -name '*_spec.lua' | LC_ALL=C sort)
TIMES=${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/hekili-busted/$(printf '%s ' "$@" | md5sum | cut -c1-12)
mkdir -p "$(dirname "$TIMES")" 2>/dev/null
touch "$TIMES" 2>/dev/null
[ -r "$TIMES" ] && [ -w "$TIMES" ] || TIMES=/dev/null # the order is an optimisation: never fail a run over it
export TIMES TOTAL=${#files[@]} JOBS=${BUSTED_JOBS:-$(nproc)}
all=$(printf '%s\n' "${files[@]}" | awk 'FILENAME == ARGV[1] { t[$2] = $1; next } $0 in t { s += t[$0] } END { printf "%d", s }' "$TIMES" -)
eta=""
[ "$all" -gt 0 ] && eta=$(awk -v s="$all" -v j="$JOBS" 'BEGIN { printf ", about %d min", int(s / j / 60 + 0.5) }')
echo "running $TOTAL spec files, $JOBS at a time$eta"
printf '%s\n' "${files[@]}" | awk 'FILENAME == ARGV[1] { t[$2] = $1; next } { print ($0 in t ? t[$0] : 1e9), $0 }' \
    "$TIMES" - | LC_ALL=C sort -s -k1,1gr | cut -d' ' -f2 | tr '\n' '\0' | xargs -0 -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {} "$@"

for f in "${files[@]}"; do # this run's times, for the next run's order
    awk -v f="$f" '/ success(es)? \/ .* pending : / { print $(NF - 1), f; exit }' "$OUT/${f//\//_}"
done >"$TIMES"

failed=()
[ "${GITHUB_ACTIONS:-}" = true ] && echo "::group::Full per-file output (path order)"
for f in "${files[@]}"; do
    log="$OUT/${f//\//_}"
    rc=$(cat "$log.rc" 2>/dev/null)
    [ "$rc" = 0 ] && grep -q '^0 successes / 0 failures / 0 errors / 0 pending' "$log" && continue
    echo "== $f (rc=$rc)"
    cat "$log"
    [ "$rc" = 0 ] || failed+=("$f")
done
[ "${GITHUB_ACTIONS:-}" = true ] && echo "::endgroup::"
# busted's summary line: "N successes / N failures / N errors / N pending : S seconds"
totals=$(cat "$OUT"/*.lua | awk '/ success(es)? \/ .* failures? \/ .* errors? \/ .* pending/ {
    s += $1; f += $4; e += $7; p += $10 }
    END { printf "all files: %d successes / %d failures / %d errors / %d pending", s, f, e, p }')
printf '\n%s\n' "$totals"
if [ "${GITHUB_ACTIONS:-}" = true ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -f "$OUT/.rows" ]; then
    {
        printf '### Spec files\n\n| file | result | time | passed | failed |\n|---|---|---|---|---|\n'
        LC_ALL=C sort "$OUT/.rows" | awk -F'\t' '{ printf "| %s | %s | %dm%02ds | %d | %d |\n", $1, $2, $3 / 60, $3 % 60, $4, $5 }'
        printf '\nSlowest files:\n\n'
        LC_ALL=C sort -t "$(printf '\t')" -k3,3nr "$OUT/.rows" | head -5 | awk -F'\t' '{ printf "- %s %dm%02ds\n", $1, $3 / 60, $3 % 60 }'
        printf '\n%s\n' "$totals"
        for f in "${failed[@]+"${failed[@]}"}"; do echo "FAILED: $f"; done
    } >>"$GITHUB_STEP_SUMMARY"
fi
if [ ${#failed[@]} -gt 0 ]; then
    printf 'FAILED: %s\n' "${failed[@]}"
    exit 1
fi
