#!/usr/bin/env bash
#
# Runs the game in a window. On macOS, double-click this file in Finder (it opens in
# Terminal, which stays open on the game's output).
#
#   GODOT=/path/to/Godot ./tools/play.command
#
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_godot
ensure_class_cache
exec "$GODOT" --path "$PROJECT_DIR"
