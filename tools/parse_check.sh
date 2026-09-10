#!/usr/bin/env bash
#
# Parses EVERY GDScript file in the project and reports the real errors.
#
#   ./tools/parse_check.sh
#   GODOT=/path/to/Godot ./tools/parse_check.sh
#
# Completes tools/run_checks.sh, which RUNS code: a script no test scene ever loads can be
# broken with nothing saying so. Neither `--quit-after` (which only compiles the boot path)
# nor `--import` parses those files — only `--check-only`, file by file, covers them.
#
# FALSE POSITIVES FILTERED OUT: under `--check-only` the autoloads are not registered, so
# any script that references one reports "Identifier not found: <Autoload>" while being
# perfectly valid. The names filtered are read from project.godot rather than hardcoded, so
# that an autoload added tomorrow does not fail CI for no reason. "Failed to compile
# depended scripts" is filtered for the same reason: it is the false positive cascading
# into a dependent. A REAL error in a dependency is still reported when the sweep reaches
# the offending file itself.
#
set -uo pipefail

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_godot
# With no class cache, --check-only reports "Could not find type" across the whole
# project: that would be 200 false failures instead of a sweep.
ensure_class_cache

# The autoload names, read from project.godot's [autoload] section.
autoloads=()
while IFS= read -r name; do
	[[ -n "$name" ]] && autoloads+=("$name")
done < <(awk '/^\[autoload\]/{f=1; next} /^\[/{f=0} f && /=/{sub(/=.*/, ""); gsub(/[ \t]/, ""); if ($0 != "") print}' "$PROJECT_DIR/project.godot")

ignore_re='Failed to compile depended scripts'
for name in "${autoloads[@]}"; do
	ignore_re="$ignore_re|Identifier not found: $name"
done

echo "Godot     : $GODOT"
echo "Project   : $PROJECT_DIR"
echo "Autoloads : ${autoloads[*]:-none} (identifiers ignored under --check-only)"
echo

failed=()
total=0
while IFS= read -r file; do
	total=$((total + 1))
	errors="$("$GODOT" --headless --path "$PROJECT_DIR" --check-only --script "res://$file" 2>&1 \
		| grep -E 'Parse Error|Compile Error' \
		| grep -vE "$ignore_re")"
	if [[ -n "$errors" ]]; then
		failed+=("$file")
		echo "FAIL $file"
		sed -e 's/^/      | /' <<<"$errors"
	fi
done < <(cd "$PROJECT_DIR" && find . -name '*.gd' -not -path './.godot/*' | sed 's|^\./||' | sort)

echo
if [[ ${#failed[@]} -eq 0 ]]; then
	echo "$total scripts parsed, no error."
	exit 0
fi
echo "Scripts in error (${#failed[@]}/$total): ${failed[*]}"
exit 1
