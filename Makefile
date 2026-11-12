# Headless checks for Hekili (Forever). Run `make bootstrap` once, then `make check` before every commit.
# StyLua and lua-language-server come from mise (mise.toml); the rest from .lua/ (scripts/bootstrap.sh).
LUA_ENV := .lua
BUSTED := $(LUA_ENV)/bin/busted
LUACHECK := $(LUA_ENV)/bin/luacheck
LUAC := $(LUA_ENV)/bin/luac
LUA := $(if $(wildcard $(LUA_ENV)/bin/lua),$(LUA_ENV)/bin/lua,lua5.1)

.PHONY: accuracy gate gate-ab gate-body gate-ab-body bootstrap lint fmt fmt-check typecheck test test-serial test-fast test-loop test-party test-druid test-rogue test-paladin test-shaman test-hunter test-mage test-priest test-warlock bench bench-ta spell-data-check cdv-coverage syntax api-check \
	packs-check tools-test check check-full packs package package-check wowsims-cli wowsims-sim-cli wowsims-export wowsims-siml wowsims-learn shared-auras wowsims-packs test-wowsims

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

# The merge gate: check-full (never skips), then every 20-fight loop tag in one scripts/busted_parallel.sh run (one busted process per
# spec file, nproc - 2 at a time for the whole gate, at least 1). `make test-<tag>` runs one tag the same way, nproc
# at a time.
comma := ,
GATE_TAGS := loop,party,druid,rogue,paladin,shaman,hunter,mage,priest,warlock
LOOPS = $(addprefix test-,$(subst $(comma), ,$(GATE_TAGS)))
GATE_LOCK ?= /tmp/hekili-gate.lock
# One gate at a time per machine (flock): the loops assert a CPU budget per update (process CPU time, os.clock) that
# another gate's load would still inflate through shared cores.
# HEKILI_AB is never passed through from the shell (tests/Game/harness/ab.lua reads it per call, so a leaked one would
# turn a plain gate or check into a record-only provider arm): only gate-ab sets it, per arm, through AB_ARM.
unexport HEKILI_AB
gate: check-full
	flock $(GATE_LOCK) env $(if $(AB_ARM),HEKILI_AB=$(AB_ARM)) BUSTED=$(BUSTED) BUSTED_JOBS=$$(($$(nproc) > 3 ? $$(nproc) - 2 : 1)) scripts/busted_parallel.sh --tags=$(GATE_TAGS)

# The per-spec accuracy table (.accuracy/report.{json,md}, gitignored): every loop and wowsims spec file once, three
# seed sets, under the gate lock for the whole run. Dev tooling: not part of gate or check (tools/accuracy/).
accuracy:
	flock $(GATE_LOCK) env BUSTED=$(BUSTED) GATE_TAGS=$(GATE_TAGS) tools/accuracy/run.sh
	$(LUA) tools/accuracy/report.lua

# The A/B (providers spec §4.1): the gate once per arm on the same seeds; the provider arms record in .ab/<arm>.tsv.
# The four viewer arms (cdm-default decision 110) differ by the Cooldown Manager layout (scenarios.viewerLayout); the
# CDM verdict's worlds (verdict spec §5, review M4) follow, each with its verdict-off twin (-novd); the live-auras arms
# (aura audit C1) hide our own auras in combat, as live, so only the Cooldown Manager shows them.
AB_ARMS ?= meter viewer-none viewer-buffs viewer-fixture viewer-mixed \
	viewer-reshuffle viewer-reshuffle-novd viewer-nonland viewer-nonland-novd \
	secret-viewer-buffs secret-viewer-buffs-novd secret-viewer-mixed secret-viewer-mixed-novd \
	viewer-swap viewer-swap-novd viewer-late viewer-late-novd viewer-recast viewer-recast-novd \
	viewer-swap-dark viewer-swap-dark-novd live-auras live-auras-none
gate-ab:
	rm -rf .ab
	$(MAKE) gate
	$(foreach a,$(AB_ARMS),$(MAKE) gate AB_ARM=$(a) &&) true
	@wc -l .ab/*.tsv

# The gate's body alone (review S6): the loops under the lock, no check-full first (run `make check` once before).
gate-body:
	flock $(GATE_LOCK) env $(if $(AB_ARM),HEKILI_AB=$(AB_ARM)) BUSTED=$(BUSTED) BUSTED_JOBS=$$(($$(nproc) > 3 ? $$(nproc) - 2 : 1)) scripts/busted_parallel.sh --tags=$(GATE_TAGS)

# gate-ab without a check-full per arm: the default arm's body, then each of AB_ARMS's (a subset: AB_ARMS="a b"), each
# arm's output in .ab/<arm>.log (the default's .ab/default.log, for scripts/results.sh); compare with scripts/ab_delta.sh.
gate-ab-body:
	rm -rf .ab
	mkdir -p .ab
	$(MAKE) gate-body > .ab/default.log 2>&1
	@# a provider arm's failed spec (an assert outside ab.check: viewer-swap's self-check) stops no other arm
	$(foreach a,$(AB_ARMS),$(MAKE) gate-body AB_ARM=$(a) > .ab/$(a).log 2>&1 || echo "gate-ab-body: $(a) failed, see .ab/$(a).log";) true
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

# The packs' auras the Cooldown Manager tracks vs the ones modelled, per tools/data/cooldownviewer/<CLASS>.lua: a
# dev-only coverage report (providers spec decision 81); not part of check, never fails.
cdv-coverage:
	$(LUA) tools/check_cooldown_viewer.lua

# The wowsims/forever packs (docs/superpowers/plans/2026-10-19-wowsims-packs.md). Dev-only, outside `make check`:
# wowsims-cli builds the upstream CLI in the checkout (Go, protoc and protoc-gen-go on PATH; the export uses
# wowsims-sim-cli's wowsimcli-sim-pin), wowsims-export SPEC=<spec> exports one recipe's request and log,
# wowsims-learn CLASS=<TOKEN> the class's learn levels. wowsims-packs (CI-safe)
# rewrites every wowsims pack's .simc from the checked-in requests.
WOWSIMS ?= $(HOME)/src/wowsims-forever
wowsims-cli:
	cd $(WOWSIMS) && make sim/core/proto/api.pb.go && go build --tags=with_db -o wowsimcli-amd64-linux ./cmd/wowsimcli/cli_main.go

# wowsims-sim-cli: the oracle CLI (wowsimcli-sim-pin) that `export.lua export`, `siml` and `rerun` use, from a checkout at one of
# export.lua's pins with that pin's oracle patches (tools/wowsims/sim-pin/build.sh; docs/dev/wowsims-packs.md "Oracle patches").
wowsims-sim-cli:
	sh tools/wowsims/sim-pin/build.sh $(WOWSIMS)

wowsims-export:
	WOWSIMS=$(WOWSIMS) $(LUA) tools/wowsims/export.lua export $(SPEC)

# wowsims-siml SPEC=<spec>: the recipe's .siml build as tests/Forever/wowsims/<spec>.build.json (export runs it too).
wowsims-siml:
	WOWSIMS=$(WOWSIMS) $(LUA) tools/wowsims/export.lua siml $(SPEC)

shared-auras:
	python3 -I tools/gen_shared_auras.py $(PIN)

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
	bash tools/check_border.sh

# The generated RegisterPack blocks match src/Hekili_*/APLs/ (make_pack writes only a changed file, so `make -j` is safe).
packs-check: wowsims-packs packs
	git diff --exit-code src

# Offline tests of the release tools (tools/release_notes.py, cf_upload.py, changelog_release.py): no network, no keys.
tools-test:
	python3 -m unittest discover -s tests/tools -t tests/tools

# `make check` skips (one line) when every input matches the last green run (scripts/check_stamp.sh); FULL=1 runs it.
# check-full: the four long checks at once (-Otarget keeps each one's output whole), then the short serial tail; one
# exit code. The begin and write lines hold no $(MAKE), so `make -n` never runs them; make stops at the first failing
# line, so write (the stamp) runs only after both stages pass. A command-line override other than FULL (a subset or
# another tool) or -i/-e (errors ignored, environment over the Makefile) never skips and never stamps.
# shortcut: a failed or killed run leaves its start manifest in /tmp; harmless, write is the only reader.
STAMP_START := $(shell mktemp -u /tmp/hekili-check-start.XXXXXX)
STAMP_OFF := $(strip $(filter-out FULL=%,$(MAKEOVERRIDES)) $(findstring i,$(firstword -$(MAKEFLAGS))) $(findstring e,$(firstword -$(MAKEFLAGS))))
check:
	@if [ -z "$(FULL)$(STAMP_OFF)" ] && scripts/check_stamp.sh test; then :; else $(MAKE) check-full; fi

check-full:
	@$(if $(STAMP_OFF),echo "check: command-line overrides or -i/-e; this run leaves no stamp",scripts/check_stamp.sh begin $(STAMP_START))
	$(MAKE) -j4 -Otarget lint fmt-check typecheck test
	$(MAKE) syntax api-check packs-check tools-test
	@$(if $(STAMP_OFF),:,scripts/check_stamp.sh write $(STAMP_START))

# Rewrites each class file's RegisterPack blocks from its APLs/ (tools/make_pack.lua write), re-dating a class (today,
# or PACK_DATE=YYYYMMDD) only when its blocks change; not part of `check`.
packs:
	for d in src/Hekili_*/APLs; do c=$${d#src/Hekili_}; $(LUA) tools/make_pack.lua write $$(echo $${c%/APLs} | tr A-Z a-z) || exit 1; done

# The BigWigs packager run locally, no upload (-d): zip in .release/ (docs/publishing/README.md). Needs network once.
PACKAGER_REF ?= e50a250f8705041e40f2fa1ddcb280a686d65aa0
package:
	@mkdir -p $(LUA_ENV)
	@test -s $(LUA_ENV)/release-$(PACKAGER_REF).sh || curl -fsSL https://raw.githubusercontent.com/BigWigsMods/packager/$(PACKAGER_REF)/release.sh -o $(LUA_ENV)/release-$(PACKAGER_REF).sh
	bash $(LUA_ENV)/release-$(PACKAGER_REF).sh -d -l -r $(CURDIR)/.release

package-check: package
	bash tools/check_package.sh "$$(ls -t .release/Hekili-*.zip | head -1)"
