#!/usr/bin/env bash
# tools/red_first.sh BASE [SPEC...] (refactor plan lane 2, L1827): a lane's NEW tests must fail on the base tree (red
# first). The base tree is BASE's src/ (and everything else of BASE) under this checkout's tests/: each SPEC file runs
# there, and every test whose full name BASE's own copy of the file does not hold must fail ("not ok"). A new test
# green on base proves nothing about the lane's change, so it fails this check, unless its name carries a tag that says
# it is green by design: #pin (it pins today's behaviour for a later lane, as the pairing matrix does) or #self (it checks
# the spec's own tooling, not src/). A declared one red on base fails too. A spec file that raises before any test runs
# is reported as a load error and counts as red for its new tests.
# SPEC defaults to the *_spec.lua files under tests/ added or changed against BASE (the working tree and untracked
# files included).
# Exit 0: every new test is red on base (or declared and green); 1: a finding; 2: usage.
# Read-only on the repository: BASE is exported with git archive into a temporary directory, removed on exit.
# Example: tools/red_first.sh origin/forever, or tools/red_first.sh 8a00bd0b9 tests/Game/State/latency_spec.lua
set -uo pipefail
cd "$(dirname "$0")/.."
BASE=${1:?usage: tools/red_first.sh BASE [SPEC...]}
shift
git rev-parse --verify -q "$BASE^{commit}" >/dev/null || {
    echo "red_first: unknown ref $BASE" >&2
    exit 2
}
BUSTED=$(realpath "${BUSTED:-.lua/bin/busted}")
LUA_ENV=$(realpath .lua)
if [ $# -gt 0 ]; then
    specs=("$@")
else
    mapfile -t specs < <({
        git diff --name-only --diff-filter=AM "$BASE" -- 'tests/*_spec.lua'
        git ls-files --others --exclude-standard -- 'tests/*_spec.lua' # new, not yet added
    } | LC_ALL=C sort -u)
fi
if [ ${#specs[@]} -eq 0 ]; then
    echo "red_first: no spec file added or changed against $BASE"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git archive "$BASE" | tar -x -C "$TMP" || exit 2
ln -s "$LUA_ENV" "$TMP/.lua"

# the full names a spec file holds (busted --list: "file:line: name")
names() { (cd "$TMP" && "$BUSTED" --list "$1" 2>/dev/null | sed -E 's/^[^:]+:[0-9]+: //' | LC_ALL=C sort -u); }

for f in "${specs[@]}"; do
    if [ -f "$TMP/$f" ]; then names "$f" >"$TMP/.base.${f//\//_}"; else : >"$TMP/.base.${f//\//_}"; fi
done
rm -rf "$TMP/tests"
cp -r tests "$TMP/tests"

bad=0
for f in "${specs[@]}"; do
    key=${f//\//_}
    names "$f" | LC_ALL=C comm -23 - "$TMP/.base.$key" >"$TMP/.new.$key"
    n=$(wc -l <"$TMP/.new.$key")
    if [ "$n" -eq 0 ]; then
        echo "$f: no new test"
        continue
    fi
    # one result per test: "ok" or "not ok", then the name (TAP: "ok 3 - name")
    (cd "$TMP" && "$BUSTED" -o TAP "$f" 2>&1) | sed -nE 's/^(not ok|ok) [0-9]+ - (.*)$/\1\t\2/p' >"$TMP/.tap.$key"
    loaderr=0
    [ -s "$TMP/.tap.$key" ] || loaderr=1
    red=0 green=0 decl=0
    while IFS= read -r name; do
        st=$(awk -F'\t' -v n="$name" '$2 == n { s = $1 } END { print s }' "$TMP/.tap.$key")
        case "$name" in *"#pin"* | *"#self"*) tagged=1 ;; *) tagged=0 ;; esac
        if [ "$loaderr" -eq 1 ] || [ "$st" = "not ok" ] || [ -z "$st" ]; then
            if [ "$tagged" -eq 1 ]; then
                echo "  RED, declared green: $name"
                bad=1
            else
                red=$((red + 1))
            fi
        elif [ "$tagged" -eq 1 ]; then
            decl=$((decl + 1))
        else
            echo "  GREEN on base: $name"
            green=$((green + 1))
            bad=1
        fi
    done <"$TMP/.new.$key"
    echo "$f: $n new: $red red$([ "$loaderr" -eq 1 ] && echo ' (load error)'), $green green, $decl declared green (#pin/#self)"
done
[ "$bad" -eq 0 ] && echo "red_first: OK against $BASE" || echo "red_first: FAILED against $BASE"
exit "$bad"
