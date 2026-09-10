#!/usr/bin/env bash
#
# Runs every headless check in scenes/dev/*_check.tscn and gathers the results. Exits 1
# as soon as a single one fails.
#
#   ./tools/run_checks.sh                # all of them
#   ./tools/run_checks.sh encounter data # the ones whose name contains one of these words
#   GODOT=/path/to/Godot ./tools/run_checks.sh
#
# Two traps this launcher exists to cover:
#
#  - A check whose SCRIPT does not compile reports nothing: Godot loads the scene without
#    its script, nobody calls quit(), and the process runs forever. Hence the per-check
#    timeout — without it a CI run hangs until its own limit.
#  - Godot returns 0 while reporting script errors or leaked instances on its output. The
#    return code alone would therefore let those regressions through: we read the output
#    as well.
#
set -uo pipefail

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TIMEOUT="${TIMEOUT:-300}"

# Patterns that give away a failure despite a zero return code.
# `^ERROR:` covers the game's own push_error calls: Godot prints them and carries on, so a
# check can print "ALL OK" and return 0 having reported a real fault. Verified that no
# check emits one in normal operation. WARNINGs, on the other hand, stay tolerated: some
# are deliberate diagnostics (a test scenario that exercises a fall).
SILENT_FAILURES='SCRIPT ERROR|^ERROR:|Failed to load script|leaked at exit|still in use at exit'

require_godot

# Runs a command, killing it past $TIMEOUT seconds (macOS has no timeout(1)).
# Returns 124 on expiry, as timeout(1) would.
run_with_timeout() {
	local out_file="$1"; shift
	"$@" >"$out_file" 2>&1 &
	local pid=$!
	( sleep "$TIMEOUT"; kill -9 "$pid" 2>/dev/null ) 2>/dev/null &
	local watcher=$!
	# `wait` is silenced: when the watcher kills the process, the shell would announce
	# "Killed: 9" right in the middle of the result line.
	{ wait "$pid"; } 2>/dev/null; local code=$?
	{ kill "$watcher"; wait "$watcher"; } 2>/dev/null
	[[ $code -ge 128 ]] && return 124
	return $code
}

ensure_class_cache

scenes=()
for scene in "$PROJECT_DIR"/scenes/dev/*_check.tscn; do
	[[ -e "$scene" ]] || continue
	name="$(basename "$scene" .tscn)"
	if [[ $# -gt 0 ]]; then
		for filter in "$@"; do
			[[ "$name" == *"$filter"* ]] && scenes+=("$scene") && break
		done
	else
		scenes+=("$scene")
	fi
done

if [[ ${#scenes[@]} -eq 0 ]]; then
	echo "No check to run." >&2
	exit 2
fi

log_dir="$(mktemp -d)"
trap 'rm -rf "$log_dir"' EXIT

failed=()
printf '%s\n' "Godot   : $GODOT"
printf '%s\n' "Project : $PROJECT_DIR"
printf '%s\n\n' "Checks  : ${#scenes[@]}"

for scene in "${scenes[@]}"; do
	name="$(basename "$scene" .tscn)"
	out="$log_dir/$name.log"
	printf '%-26s ' "$name"
	start=$SECONDS
	run_with_timeout "$out" "$GODOT" --headless --path "$PROJECT_DIR" "res://scenes/dev/$name.tscn"
	code=$?
	elapsed=$((SECONDS - start))

	reason=""
	if [[ $code -eq 124 ]]; then
		reason="timed out after ${TIMEOUT}s (script not compiling? infinite loop?)"
	elif [[ $code -ne 0 ]]; then
		reason="return code $code"
	elif grep -qE "$SILENT_FAILURES" "$out"; then
		reason="an error reported on the output despite a 0 return code"
	fi

	if [[ -z "$reason" ]]; then
		printf 'OK    %3ds\n' "$elapsed"
	else
		printf 'FAIL  %3ds  — %s\n' "$elapsed" "$reason"
		failed+=("$name")
		sed -e 's/^/      | /' "$out" | tail -20
	fi
done

echo
if [[ ${#failed[@]} -eq 0 ]]; then
	echo "All checks pass (${#scenes[@]})."
	exit 0
fi
echo "Checks failing (${#failed[@]}/${#scenes[@]}): ${failed[*]}"
exit 1
