#!/usr/bin/env bash
# The A/B's comparison (cdm-verdict review M4): ab_delta.sh <base .ab dir> <head .ab dir>. Per arm file in both dirs
# (base -> head), and per verdict arm against its -novd twin in the head dir (novd -> on): per spec the agreement and
# flicker/min of its summary row (the label column, `fights=` rows), and per character (the `layout`/`edge` fight rows)
# the summed staleUp (player/target), verdicts and strikes. Exit 1 when a flicker rises by more than 0.3/min or an
# agreement falls (both comparisons), or when the new side lacks a spec or an arm the old side has (a failed or
# cut-short run is never a pass); a twin pair whose character has 0 verdicts on both sides is marked "vacuous".
set -euo pipefail
[ $# -eq 2 ] && [ -d "$1" ] && [ -d "$2" ] || {
    echo "usage: $0 <base .ab dir> <head .ab dir>" >&2
    exit 2
}

# compare <title> <twin: 0|1> <old tsv> <new tsv>: prints the rows, exits 1 on a failure (gawk: asorti)
compare() {
    gawk -F'\t' -v title="$1" -v twin="$2" '
    function add(arr, k, s, a) { # a "p/t" pair (a lone number: the player) onto arr[k, 1], arr[k, 2]
        split(s, a, "/")
        arr[k, 1] += a[1]
        arr[k, 2] += a[2]
    }
    FNR == 1 { side = (side == 0 && FILENAME == ARGV[1]) ? 1 : 2 } # the old file, then the new (an empty old: none)
    {
        line = $3
        if (($1 == "layout" || $1 == "edge") && line ~ / seed /) {
            split(line, wd, " ")
            who = wd[1] " " wd[2]
            WHO[who] = 1
            if ($1 == "layout") {
                N[who, side]++
                if (match(line, /verdicts [0-9.]+\/[0-9.]+/)) add(V, who SUBSEP side, substr(line, RSTART + 9, RLENGTH - 9))
                if (match(line, /strikes [0-9.]+\/[0-9.]+/)) add(K, who SUBSEP side, substr(line, RSTART + 8, RLENGTH - 8))
            } else if (match(line, /staleUp [0-9.]+(\/[0-9.]+)?/)) {
                add(S, who SUBSEP side, substr(line, RSTART + 8, RLENGTH - 8))
            }
        } else if (line ~ /fights=/ && match(line, /agreement [0-9.]+/)) {
            spec = $1
            SPEC[spec] = 1
            A[spec, side] = substr(line, RSTART + 10, RLENGTH - 10) + 0
            F[spec, side] = match(line, /flicker [0-9.]+\/min/) ? substr(line, RSTART + 8, RLENGTH - 12) : "" # as printed
        }
    }
    END {
        bad = 0
        n = asorti(SPEC, specs)
        for (i = 1; i <= n; i++) {
            s = specs[i]
            if (!((s, 1) in A) || !((s, 2) in A)) {
                if ((s, 1) in A) { # a spec the old side has and the new lost: its rows are missing, never a pass
                    printf "%s\t%s\tonly in old FAIL missing\n", title, s
                    bad = 1
                } else {
                    printf "%s\t%s\tonly in new\n", title, s
                }
                continue
            }
            da = A[s, 2] - A[s, 1]
            df = (F[s, 1] == "" || F[s, 2] == "") ? 0 : F[s, 2] - F[s, 1]
            flag = (df > 0.3 + 1e-9 ? " FAIL flicker" : "") (da < -1e-9 ? " FAIL agreement" : "")
            bad = bad || flag != ""
            printf "%s\t%s\tagreement %.3f -> %.3f (%+.3f)\tflicker %s -> %s (%+.2f)%s\n", title, s, A[s, 1], A[s, 2], da, F[s, 1], F[s, 2], df, flag
        }
        n = asorti(WHO, whos)
        for (i = 1; i <= n; i++) {
            w = whos[i]
            v1 = V[w, 1, 1] + V[w, 1, 2]
            v2 = V[w, 2, 1] + V[w, 2, 2]
            printf "%s\t%s\tfights %d -> %d\tstaleUp %.2f/%.2f -> %.2f/%.2f (%+.2f/%+.2f)\tverdicts %d/%d -> %d/%d\tstrikes %d/%d -> %d/%d%s\n",
                title, w, N[w, 1], N[w, 2], S[w, 1, 1], S[w, 1, 2], S[w, 2, 1], S[w, 2, 2],
                S[w, 2, 1] - S[w, 1, 1], S[w, 2, 2] - S[w, 1, 2],
                V[w, 1, 1], V[w, 1, 2], V[w, 2, 1], V[w, 2, 2], K[w, 1, 1], K[w, 1, 2], K[w, 2, 1], K[w, 2, 2],
                (twin && v1 == 0 && v2 == 0) ? "\tvacuous" : ""
        }
        exit bad
    }' "$3" "$4"
}

rc=0
for new in "$2"/*.tsv; do
    [ -e "$new" ] || continue
    arm=$(basename "$new" .tsv)
    [ "$arm" = abspec ] && continue
    if [ -f "$1/$arm.tsv" ]; then
        compare "$arm" 0 "$1/$arm.tsv" "$new" || rc=1
    fi
    if [ "${arm%-novd}" = "$arm" ] && [ -f "$2/$arm-novd.tsv" ]; then
        compare "$arm (novd -> on)" 1 "$2/$arm-novd.tsv" "$new" || rc=1
    fi
done
for old in "$1"/*.tsv; do # a base arm the head never wrote (its run failed or was cut short)
    [ -e "$old" ] || continue
    arm=$(basename "$old" .tsv)
    [ "$arm" = abspec ] && continue
    if [ ! -f "$2/$arm.tsv" ]; then
        printf '%s\t-\tonly in old FAIL missing arm\n' "$arm"
        rc=1
    fi
done
exit $rc
