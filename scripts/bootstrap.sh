#!/usr/bin/env bash
# Ported from TacoDogForever's scripts/bootstrap.sh (credit: TacoDogForever). Installs the headless Lua toolchain into
# .lua/ (git-ignored): Lua 5.1.5 (WoW's Lua), LuaRocks 3.8.0, busted, luacheck and luacov. StyLua and
# lua-language-server come from mise (mise.toml).
set -euo pipefail
cd "$(dirname "$0")/.."
ENV_DIR=.lua

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
