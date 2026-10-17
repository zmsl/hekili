# Headless checks for Hekili (Forever). Run `make bootstrap` once, then `make check` before every commit.
# StyLua and lua-language-server come from mise (mise.toml); the rest from .lua/ (scripts/bootstrap.sh).
LUA_ENV := .lua
BUSTED := $(LUA_ENV)/bin/busted
LUACHECK := $(LUA_ENV)/bin/luacheck
LUAC := $(LUA_ENV)/bin/luac

.PHONY: bootstrap lint fmt fmt-check typecheck test test-fast test-loop test-party test-druid syntax api-check check

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

# The headless loop's 20-fight Arms gate (#loop) and party report (#party), and the Druid harness gates at the GCD
# kinds design's fight counts (#druid), run only behind their own targets.
test:
	$(BUSTED) --exclude-tags=party,loop,druid

# The edit loop: skips the harness gate specs tagged #slow (hundreds of simulated fights); `make check` runs them.
test-fast:
	$(BUSTED) --exclude-tags=slow,party,loop,druid

test-loop:
	$(BUSTED) --tags=loop

test-party:
	$(BUSTED) --tags=party

test-druid:
	$(BUSTED) --tags=druid

syntax:
	git ls-files -z '*.lua' | xargs -0 -n 200 $(LUAC) -p

api-check:
	LUACHECK=$(LUACHECK) bash tools/check_api_reads.sh
	git diff --exit-code tools/api_inventory.txt

check: lint fmt-check typecheck test syntax api-check
