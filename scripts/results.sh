#!/usr/bin/env bash
# The results of `make check`/`make gate` logs, without what varies run to run (test-speed plan, Task 1): drops make's
# lines, the runner's `== <file>` headers, busted progress lines and per-file summaries, /usr/bin/time's `wall` line
# and Python's ResourceWarnings (each with its source line: where the collector fires, and the object address, vary);
# strips the progress marks that prefix printed lines, the rig's cpu fields, and the tool file/test counts (luacheck,
# LuaLS, unittest), which change with the plan's own new files. Sorted, so file order doesn't matter.
set -euo pipefail
cat "$@" | awk '/ResourceWarning: unclosed / { skip = 1; next } skip { skip = 0; next } /^ResourceWarning: / { next } 1' |
    grep -avE '^make|make\[|^== |^[-+*.●◼✱⊝]+$| : [0-9.]+ seconds$|^wall ' |
    sed -E 's/^[-+*.●◼✱⊝]+([A-Za-z])/\1/; s/; cpu mean [^;]*per Update//; s/ in [0-9]+ files/ in N files/;
        s/.*(Diagnosis completed)/\1/; s/^Ran [0-9]+ tests? in [0-9.]+s$/Ran N tests/' | LC_ALL=C sort
