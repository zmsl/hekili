#!/usr/bin/env bash
# The stamped check (`make check`): a manifest of every input the check reads (the index, the working tree's raw bytes
# and modes, the toolchain, the environment); a run whose manifest equals the last green run's stamp skips.
#   manifest      the inputs, one per line, sorted
#   begin START   writes the manifest to START (before the check's parts run)
#   write START   stamps START when the inputs still match it (after every part passed); removes START
#   test          exit 0 with one line when the stamp matches the inputs, else exit 1 silently
# The stamp is in the worktree's own git dir. A file edited and reverted during a run is not seen (DEVELOPMENT.md).
set -euo pipefail

# Environment the check's parts read (tests/tools/test_check_stamp.py keeps it complete); LC_* are added as set.
ENV_VARS="HEKILI_AB DETECT_WRITE HEKILI_LOOP_HOLD HEKILI_LOOP_STEADY ARMS_RECS ENUS_GOLDEN TIMING STYLE_OPTIONS CLASSIC_DRAW TIMELINE_DRAW PACK_DATE WOWSIMS WOWSIMS_CLI WOWDB HOME BUSTED BUSTED_JOBS LUA_INIT LUA_PATH LUA_CPATH WOW_DB2 LANG TZ PYTHONPATH PATH"

env_lines() {
    local n
    for n in $ENV_VARS $(compgen -e | grep '^LC_' || true); do
        if [ -n "${!n+x}" ]; then printf 'E %s=%s\n' "$n" "${!n}"; else printf 'E %s unset\n' "$n"; fi
    done
}
ENV_LINES=$(env_lines) # before LC_ALL is pinned below

cd "$(git rev-parse --show-toplevel)"
STAMP="$(git rev-parse --absolute-git-dir)/hekili-check-stamp"
export LC_ALL=C
LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT

# Raw bytes and mode of every file present: tracked, untracked unignored, and ignored *.lua/*.toc/*.xml outside .lua/
# (luacheck, stylua and the test finders walk the tree, not the index).
worktree_lines() {
    {
        git -c core.quotePath=false ls-files -co --exclude-standard
        git -c core.quotePath=false ls-files -oi --exclude-standard -- '*.lua' '*.toc' '*.xml' ':!:.lua/'
    } | sort -u | comm -23 - <(git -c core.quotePath=false ls-files -d | sort -u) >"$LIST"
    [ -s "$LIST" ] || return 0
    paste <(tr '\n' '\0' <"$LIST" | xargs -0 stat -c '%A') <(git hash-object --no-filters --stdin-paths <"$LIST") "$LIST" |
        awk -F'\t' '{ m = substr($1, 1, 1) == "l" ? "120000" : (substr($1, 4, 1) ~ /[xs]/ ? "100755" : "100644")
            print "W " m " " $2 "\t" $3 }'
}

version() { if command -v "$1" >/dev/null; then "$@" 2>&1 | tr '\n' ' '; else echo missing; fi; }

toolchain_lines() {
    local f d
    for f in .lua/bin/*; do
        if [ -f "$f" ]; then echo "T $f $(md5sum <"$f" | cut -d' ' -f1)"; fi
    done
    if [ -d .lua/lib/luarocks/rocks-5.1 ]; then
        for d in .lua/lib/luarocks/rocks-5.1/*/*/; do echo "T rock ${d#.lua/lib/luarocks/rocks-5.1/}"; done
    else
        echo "T rocks missing"
    fi
    echo "T stylua $(version stylua --version)"
    echo "T lua-language-server $(version lua-language-server --version)"
    echo "T python3 $(version python3 -V)"
    [ -f .luarc.json ] || return 0
    python3 -I -c 'import json, sys; print("\n".join(json.load(open(sys.argv[1])).get("workspace.library", [])))' \
        .luarc.json 2>/dev/null >"$LIST" || echo "T lib unreadable .luarc.json"
    while IFS= read -r d; do
        if [ -d "$d" ]; then
            echo "T lib $d $(find "$d/" -type f -printf '%P %s %T@\n' | sort | md5sum | cut -d' ' -f1)"
        else
            echo "T lib $d missing"
        fi
    done <"$LIST"
}

manifest() {
    {
        git ls-files -s | sed 's/^/I /'
        worktree_lines
        toolchain_lines
        printf '%s\n' "$ENV_LINES"
    } | sort
}

case "${1:-}" in
manifest) manifest ;;
begin) manifest >"$2" ;;
write)
    if manifest | cmp -s - "$2"; then
        cp "$2" "$STAMP.new" # same filesystem as the stamp, so the mv below is atomic
        mv "$STAMP.new" "$STAMP"
    else
        echo "check: inputs changed during the run; no stamp"
    fi
    rm -f "$2"
    ;;
test)
    if [ -f "$STAMP" ] && manifest | cmp -s - "$STAMP"; then
        echo "check: skipped, inputs unchanged since the last green check; FULL=1 runs it"
        exit 0
    fi
    exit 1
    ;;
*)
    echo "usage: $0 manifest | begin START | write START | test" >&2
    exit 2
    ;;
esac
