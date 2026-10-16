# Headless checks for Hekili (Forever). Run `make bootstrap` once, then `make check` before every commit.
# StyLua and lua-language-server come from mise (mise.toml); the rest from .lua/ (scripts/bootstrap.sh).
LUA_ENV := .lua
BUSTED := $(LUA_ENV)/bin/busted
LUACHECK := $(LUA_ENV)/bin/luacheck
LUAC := $(LUA_ENV)/bin/luac

.PHONY: bootstrap lint fmt fmt-check typecheck test syntax api-check check

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

test:
	$(BUSTED)

syntax:
	git ls-files -z '*.lua' | xargs -0 -n 200 $(LUAC) -p

api-check:
	LUACHECK=$(LUACHECK) bash tools/check_api_reads.sh
	git diff --exit-code tools/api_inventory.txt

check: lint fmt-check typecheck test syntax api-check
