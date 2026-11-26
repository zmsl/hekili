#!/usr/bin/env bash
# Ported from TacoDogForever's scripts/bootstrap.sh (credit: TacoDogForever). Installs the headless Lua toolchain into
# .lua/ (git-ignored): Lua 5.1.5 (WoW's Lua), LuaRocks 3.8.0, busted, luacheck and luacov. StyLua and
# lua-language-server come from mise (mise.toml).
set -euo pipefail
cd "$(dirname "$0")/.."
ENV_DIR=.lua
# The test runs use LuaJIT 2.1 (.lj/, make LUA_VM=luajit, the default); PUC 5.1.5 stays for `make syntax` (luac -p: the
# game is Lua 5.1, LuaJIT accepts goto, which the client rejects) and for LUA_VM=puc runs. Pinned commit, not "rolling".
LJ_DIR=.lj
LJ_PIN=96f7b297326e9fd454b7186c6858b2773f94a0dc

if [ ! -x "$ENV_DIR/bin/luarocks" ]; then
    python -m venv "$ENV_DIR/venv"
    "$ENV_DIR/venv/bin/pip" install --quiet hererocks==0.25.1
    # --no-readline: WSL and CI images lack the readline headers; the REPL isn't needed.
    "$ENV_DIR/venv/bin/hererocks" "$ENV_DIR" --lua 5.1 --luarocks 3.8.0 --no-readline
fi

install_rock() {
    "$ENV_DIR/bin/luarocks" show "$1" >/dev/null 2>&1 || "$ENV_DIR/bin/luarocks" install "$1" "$2"
}
install_rock busted 2.3.0-1
install_rock luacheck 1.2.0-1
install_rock luacov 0.17.0-1
echo "bootstrap: Lua toolchain ready in $ENV_DIR/"

if ! "$LJ_DIR/bin/lua" -e 'assert(jit)' 2>/dev/null; then
    "$ENV_DIR/venv/bin/hererocks" "$LJ_DIR" --luajit "@$LJ_PIN" --no-readline
fi
# LuaJIT cannot load luarocks' manifest ("more than 65536 constants"): the PUC luarocks installs into the LuaJIT tree.
[ -x "$LJ_DIR/bin/busted" ] || "$ENV_DIR/bin/luarocks" --lua-dir="$(pwd)/$LJ_DIR" --tree="$(pwd)/$LJ_DIR" install busted 2.3.0-1
echo "bootstrap: LuaJIT toolchain ready in $LJ_DIR/"
