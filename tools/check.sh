#!/usr/bin/env bash
# Проверка типов и линт всех Luau-скриптов (luau-lsp + определения типов Roblox).
# Использование: tools/check.sh [файлы...]   (без аргументов — весь src/)
set -u
cd "$(dirname "$0")/.."
BIN="${LUAU_LSP:-/tmp/tools/luau-lsp}"
DEFS="${ROBLOX_DEFS:-/tmp/tools/globalTypes.d.luau}"
if [ ! -x "$BIN" ] || [ ! -f "$DEFS" ]; then
	mkdir -p /tmp/tools
	curl -sL -o /tmp/tools/lsp.zip https://github.com/JohnnyMorganz/luau-lsp/releases/download/1.70.1/luau-lsp-linux-x86_64.zip
	(cd /tmp/tools && unzip -oq lsp.zip)
	curl -sL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
python3 tools/assemble_config.py
python3 tools/place_tool.py sourcemap src /tmp/sourcemap.json >/dev/null
if [ "$#" -eq 0 ]; then
	set -- src
fi
"$BIN" analyze --sourcemap /tmp/sourcemap.json --definitions "@roblox=$DEFS" --no-strict-dm-types "$@"
