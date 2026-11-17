#!/usr/bin/env bash
#
# Validates the dungeon maps in data/dungeons/<slug>/ against the level-design rules and prints
# every issue. Exits 1 if a dungeon has an error; warnings alone pass.
#
#   ./tools/validate_dungeons.sh           # every dungeon
#   ./tools/validate_dungeons.sh my_cave   # one
#   GODOT=/path/to/Godot ./tools/validate_dungeons.sh
#
set -uo pipefail

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_godot
ensure_class_cache

"$GODOT" --headless --path "$PROJECT_DIR" res://scenes/dev/validate_dungeons.tscn -- "$@" \
	| grep -v -e '^Godot Engine' -e '^\[GameData\]'
exit "${PIPESTATUS[0]}"
