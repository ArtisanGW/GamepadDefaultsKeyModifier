#!/bin/bash
# Runs the tests twice: on LuaJIT, then on elune (Lua 5.1 with WoW's taint model,
# built from https://github.com/meorawr/elune).
# From GamepadDefaultsKeyModifier:  tests/run_both.sh
# ELUNE can point to another elune build; GDKM_TEST runs only matching tests.
set -eo pipefail   # a failing test run fails the script, even through tail
cd "$(dirname "$0")/.."

ELUNE="${ELUNE:-/var/home/artisan/Documents/Coding/WoW/elune/build/linux/bin/Release/lua5.1}"

echo "== LuaJIT"
luajit tests/run.lua | tail -1

echo "== elune"
if [ ! -x "$ELUNE" ]; then
    echo "elune not found at $ELUNE (build it: cmake --preset linux && cmake --build --preset linux --config Release)" >&2
    exit 1
fi
"$ELUNE" tests/run.lua | tail -1
