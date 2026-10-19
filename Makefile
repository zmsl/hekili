# Headless checks for Hekili (Forever). Run `make bootstrap` once, then `make check` before every commit.
# StyLua and lua-language-server come from mise (mise.toml); the rest from .lua/ (scripts/bootstrap.sh).
LUA_ENV := .lua
BUSTED := $(LUA_ENV)/bin/busted
LUACHECK := $(LUA_ENV)/bin/luacheck
LUAC := $(LUA_ENV)/bin/luac
LUA := $(if $(wildcard $(LUA_ENV)/bin/lua),$(LUA_ENV)/bin/lua,lua5.1)

.PHONY: bootstrap lint fmt fmt-check typecheck test test-serial test-fast test-loop test-party test-druid test-rogue test-paladin test-shaman bench syntax api-check \
	packs-check check packs package package-check

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
# kinds design's fight counts (#druid), the 20-fight Rogue (#rogue), Paladin (#paladin) and Shaman (#shaman) gates and
# the benchmark
# (#bench) run only behind their own targets.
TEST_EXCLUDE := --exclude-tags=party,loop,druid,rogue,paladin,shaman,bench

# One busted process per spec file, in parallel (scripts/busted_parallel.sh); `make test-serial` is the one-process run.
test:
	BUSTED=$(BUSTED) scripts/busted_parallel.sh $(TEST_EXCLUDE)

test-serial:
	$(BUSTED) $(TEST_EXCLUDE)

# The edit loop: skips the harness gate specs tagged #slow (hundreds of simulated fights); `make check` runs them.
test-fast:
	$(BUSTED) --exclude-tags=slow,party,loop,druid,rogue,paladin,shaman,bench

test-loop:
	$(BUSTED) --tags=loop

test-party:
	$(BUSTED) --tags=party

test-druid:
	$(BUSTED) --tags=druid

test-rogue:
	$(BUSTED) --tags=rogue

test-paladin:
	$(BUSTED) --tags=paladin

test-shaman:
	$(BUSTED) --tags=shaman

# Per-Update time and allocation of headless Arms (tests/Forever/bench_spec.lua); not part of `check`.
bench:
	$(BUSTED) --tags=bench tests/Forever/bench_spec.lua

syntax:
	git ls-files -z '*.lua' | xargs -0 -n 200 $(LUAC) -p

api-check:
	LUACHECK=$(LUACHECK) bash tools/check_api_reads.sh
	bash tools/check_engine_reads.sh
	git diff --exit-code tools/api_inventory.txt

# The generated RegisterPack blocks match src/Hekili_*/APLs/ (make_pack writes only a changed file, so `make -j` is safe).
packs-check: packs
	git diff --exit-code src

check: lint fmt-check typecheck test syntax api-check packs-check

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
