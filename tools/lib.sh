#!/usr/bin/env bash
#
# Settings shared by the scripts in tools/. Source it, do not run it.
#
# shellcheck shell=bash

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

## Checks that the Godot binary is usable, and exits 2 otherwise.
require_godot() {
	if [[ ! -x "$GODOT" ]]; then
		echo "Godot not found: $GODOT" >&2
		echo "Set the GODOT environment variable." >&2
		exit 2
	fi
}

## Makes sure the global class cache is there.
##
## On a freshly cloned repository `.godot/` does not exist — and that is where the cache
## lives, the one thing ONLY the editor regenerates. Without it NO `class_name` resolves:
## `--check-only` reports "Could not find type" across the whole project, and the test
## scenes load without their scripts, so nothing ever calls quit(). `--import` runs the
## editor headless just long enough to rebuild the cache (a few seconds), once and for all.
ensure_class_cache() {
	[[ -f "$PROJECT_DIR/.godot/global_script_class_cache.cfg" ]] && return 0
	echo "First run: rebuilding the class cache (--import)…"
	"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1
	if [[ ! -f "$PROJECT_DIR/.godot/global_script_class_cache.cfg" ]]; then
		echo "The import produced no class cache; everything after this would fail." >&2
		exit 2
	fi
	echo
}
