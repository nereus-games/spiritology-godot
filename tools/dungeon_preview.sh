#!/usr/bin/env bash
#
# Looks at a dungeon without playing it: an ASCII dump, PNGs, statistics, and a walk of the real
# engine that cross-checks the validator. Everything runs headless.
#
#   ./tools/dungeon_preview.sh dump  norgzevod_frozen_lake --floor 0 --issues
#   ./tools/dungeon_preview.sh dump  norgzevod_frozen_lake --rect AB24:AF30 --list
#   ./tools/dungeon_preview.sh png   norgzevod_frozen_lake --out /tmp/lake --issues
#   ./tools/dungeon_preview.sh stats norgzevod_frozen_lake [--json]
#   ./tools/dungeon_preview.sh walk  norgzevod_frozen_lake     # exits 1 on a disagreement
#   ./tools/dungeon_preview.sh help
#
# Exit code: 0 on success, 1 when `walk` finds a disagreement, 2 for a usage error.
# GODOT=/path/to/Godot ./tools/dungeon_preview.sh ...
#
set -uo pipefail

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_godot
ensure_class_cache

# Make --out absolute here, relative to where the command was typed: the engine is started with
# --path, and its idea of a relative path is not the caller's.
args=()
while [[ $# -gt 0 ]]; do
	if [[ "$1" == "--out" && $# -ge 2 ]]; then
		args+=("--out" "$(realpath -m "$2")")
		shift 2
	else
		args+=("$1")
		shift
	fi
done

"$GODOT" --headless --path "$PROJECT_DIR" res://scenes/dev/dungeon_preview.tscn -- "${args[@]}" \
	| grep -v -e '^Godot Engine' -e '^\[GameData\]'
exit "${PIPESTATUS[0]}"
