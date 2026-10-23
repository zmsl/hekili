# Headless checks for Hekili (Forever). Run `make bootstrap` once, then `make check` before every commit.
# StyLua and lua-language-server come from mise (mise.toml); the rest from .lua/ (scripts/bootstrap.sh).
LUA_ENV := .lua
BUSTED := $(LUA_ENV)/bin/busted
LUACHECK := $(LUA_ENV)/bin/luacheck
LUAC := $(LUA_ENV)/bin/luac
LUA := $(if $(wildcard $(LUA_ENV)/bin/lua),$(LUA_ENV)/bin/lua,lua5.1)

.PHONY: gate gate-ab bootstrap lint fmt fmt-check typecheck test test-serial test-fast test-loop test-party test-druid test-rogue test-paladin test-shaman test-hunter test-mage test-priest test-warlock bench bench-ta spell-data-check syntax api-check \
	packs-check tools-test check packs package package-check wowsims-cli wowsims-export wowsims-learn wowsims-packs test-wowsims

bootstrap:
	scripts/bootstrap.sh

lint:
	$(LUACHECK) -q .

fmt:
	stylua .

fmt-check:
	stylua --check .

typecheck:
	lua-language-server --check . --checklevel=Error --logpath $(LUA_ENV)/lsp-log

# The headless loop's 20-fight Arms gate (#loop) and party report (#party), the Druid harness gates at the GCD
# kinds design's fight counts (#druid), the 20-fight Rogue (#rogue), Paladin (#paladin), Shaman (#shaman), Hunter
# (#hunter), Mage (#mage), Priest (#priest) and Warlock (#warlock) gates and the benchmark (#bench) run only behind their own targets.
TEST_EXCLUDE := --exclude-tags=party,loop,druid,rogue,paladin,shaman,hunter,mage,priest,warlock,bench

# One busted process per spec file, in parallel (scripts/busted_parallel.sh); `make test-serial` is the one-process run.
test:
	BUSTED=$(BUSTED) scripts/busted_parallel.sh $(TEST_EXCLUDE)

test-serial:
	$(BUSTED) $(TEST_EXCLUDE)

# The edit loop: skips the harness gate specs tagged #slow (hundreds of simulated fights); `make check` runs them.
test-fast:
	$(BUSTED) --exclude-tags=slow,party,loop,druid,rogue,paladin,shaman,hunter,mage,priest,warlock,bench

# The merge gate: check, then every 20-fight loop tag in one scripts/busted_parallel.sh run (one busted process per
# spec file, nproc - 2 at a time for the whole gate, at least 1). `make test-<tag>` runs one tag the same way, nproc
# at a time.
comma := ,
GATE_TAGS := loop,party,druid,rogue,paladin,shaman,hunter,mage,priest,warlock
LOOPS = $(addprefix test-,$(subst $(comma), ,$(GATE_TAGS)))
GATE_LOCK ?= /tmp/hekili-gate.lock
# One gate at a time per machine (flock): the loops assert a CPU budget per update (process CPU time, os.clock) that
# another gate's load would still inflate through shared cores.
gate: check
	flock $(GATE_LOCK) env BUSTED=$(BUSTED) BUSTED_JOBS=$$(($$(nproc) > 3 ? $$(nproc) - 2 : 1)) scripts/busted_parallel.sh --tags=$(GATE_TAGS)

# The A/B (providers spec §4.1): the gate once per arm on the same seeds; the provider arms record in .ab/<arm>.tsv.
gate-ab:
	rm -rf .ab
	$(MAKE) gate
	HEKILI_AB=meter $(MAKE) gate
	HEKILI_AB=viewer $(MAKE) gate
	@wc -l .ab/*.tsv

$(LOOPS): test-%:
	BUSTED=$(BUSTED) scripts/busted_parallel.sh --tags=$*

# Per-Update time and allocation of headless Arms (tests/Forever/bench_spec.lua); not part of `check`.
bench:
	$(BUSTED) --tags=bench tests/Forever/bench_spec.lua

# The unit registry and ticket pool microbenchmark (unit-registry spec §10): rows/s, ms/row and ms per frame tick
# against hard budgets and a rows/s floor (tools/bench_ta_floor.lua); not part of `check`.
bench-ta:
	$(LUA) tools/bench_ta.lua

# The packs' declared expects/velocity/school/ticks against DB2 (unit-registry spec 5.5): SpellMisc, SpellEffect from
# $WOW_DB2; dev-only, outside `make check` (CI has no DB2 file). A rank with no DB2 row is a note; a mismatch fails.
spell-data-check:
	$(LUA) tools/check_spell_data.lua | python3 -I tools/check_spell_data.py

# The wowsims/forever packs (docs/superpowers/plans/2026-10-19-wowsims-packs.md). Dev-only, outside `make check`:
# wowsims-cli builds the CLI in the checkout (Go, protoc and protoc-gen-go on PATH), wowsims-export SPEC=<spec>
# exports one recipe's request and log, wowsims-learn CLASS=<TOKEN> the class's learn levels. wowsims-packs (CI-safe)
# rewrites every wowsims pack's .simc from the checked-in requests.
WOWSIMS ?= $(HOME)/src/wowsims-forever
wowsims-cli:
	cd $(WOWSIMS) && make sim/core/proto/api.pb.go && go build --tags=with_db -o wowsimcli-amd64-linux ./cmd/wowsimcli/cli_main.go

wowsims-export:
	WOWSIMS=$(WOWSIMS) $(LUA) tools/wowsims/export.lua export $(SPEC)

wowsims-learn:
	$(LUA) tools/wowsims/export.lua learn $(CLASS)

wowsims-packs:
	for r in tools/wowsims/specs/*.lua; do [ -e "$$r" ] || continue; $(LUA) tools/wowsims/export.lua pack $$(basename $$r .lua) || exit 1; done

# The wowsims replay and leveling gates (#wowsims; `make check` runs them too, in its #slow tier).
test-wowsims:
	$(BUSTED) --tags=wowsims

syntax:
	git ls-files -z '*.lua' | xargs -0 -n 200 $(LUAC) -p

api-check:
	LUACHECK=$(LUACHECK) bash tools/check_api_reads.sh
	bash tools/check_engine_reads.sh
	git diff --exit-code tools/api_inventory.txt

# The generated RegisterPack blocks match src/Hekili_*/APLs/ (make_pack writes only a changed file, so `make -j` is safe).
packs-check: wowsims-packs packs
	git diff --exit-code src

# Offline tests of the release tools (tools/release_notes.py, cf_upload.py, changelog_release.py): no network, no keys.
tools-test:
	python3 -m unittest discover -s tests/tools -t tests/tools

# The four long checks at once (-Otarget keeps each one's output whole), then the short serial tail; one exit code.
check:
	$(MAKE) -j4 -Otarget lint fmt-check typecheck test
	$(MAKE) syntax api-check packs-check tools-test

# Rewrites each class file's RegisterPack blocks from its APLs/ (tools/make_pack.lua write), re-dating a class (today,
# or PACK_DATE=YYYYMMDD) only when its blocks change; not part of `check`.
packs:
	for d in src/Hekili_*/APLs; do c=$${d#src/Hekili_}; $(LUA) tools/make_pack.lua write $$(echo $${c%/APLs} | tr A-Z a-z) || exit 1; done

# The BigWigs packager run locally, no upload (-d): zip in .release/ (docs/publishing/README.md). Needs network once.
PACKAGER_REF ?= v2
package:
	@mkdir -p $(LUA_ENV)
	@test -s $(LUA_ENV)/release.sh || curl -fsSL https://raw.githubusercontent.com/BigWigsMods/packager/$(PACKAGER_REF)/release.sh -o $(LUA_ENV)/release.sh
	bash $(LUA_ENV)/release.sh -d -l -r $(CURDIR)/.release

package-check: package
	bash tools/check_package.sh "$$(ls -t .release/Hekili-*.zip | head -1)"
