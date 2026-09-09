#!/usr/bin/env bash
#
# Parse TOUS les scripts GDScript du projet et signale les vraies erreurs.
#
#   ./tools/parse_check.sh
#   GODOT=/chemin/vers/Godot ./tools/parse_check.sh
#
# Complète tools/run_checks.sh, qui EXÉCUTE du code : un script jamais chargé par aucune
# scène de test peut être cassé sans que rien ne le dise. Ni `--quit-after` (qui ne compile
# que le chemin de boot) ni `--import` ne parsent ces fichiers-là — seul `--check-only`,
# fichier par fichier, les couvre.
#
# FAUX POSITIFS FILTRÉS : en `--check-only`, les autoloads ne sont pas enregistrés, donc
# tout script qui en référence un sort « Identifier not found: <Autoload> » alors qu'il
# est parfaitement valide. Les noms filtrés sont lus dans project.godot, et non codés en
# dur, pour qu'un autoload ajouté demain ne fasse pas échouer la CI sans raison.
# « Failed to compile depended scripts » est filtré pour la même raison : c'est la cascade
# du faux positif chez un dépendant. Une VRAIE erreur dans une dépendance reste signalée
# quand le balayage arrive sur le fichier fautif lui-même.
#
set -uo pipefail

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_godot
# Sans cache de classes, --check-only sort « Could not find type » sur tout le projet :
# ce serait 200 faux échecs au lieu d'un balayage.
ensure_class_cache

# Noms des autoloads, extraits de la section [autoload] de project.godot.
autoloads=()
while IFS= read -r name; do
	[[ -n "$name" ]] && autoloads+=("$name")
done < <(awk '/^\[autoload\]/{f=1; next} /^\[/{f=0} f && /=/{sub(/=.*/, ""); gsub(/[ \t]/, ""); if ($0 != "") print}' "$PROJECT_DIR/project.godot")

ignore_re='Failed to compile depended scripts'
for name in "${autoloads[@]}"; do
	ignore_re="$ignore_re|Identifier not found: $name"
done

echo "Godot     : $GODOT"
echo "Projet    : $PROJECT_DIR"
echo "Autoloads : ${autoloads[*]:-aucun} (identifiants ignorés en --check-only)"
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
		echo "ÉCHEC $file"
		sed -e 's/^/      | /' <<<"$errors"
	fi
done < <(cd "$PROJECT_DIR" && find . -name '*.gd' -not -path './.godot/*' | sed 's|^\./||' | sort)

echo
if [[ ${#failed[@]} -eq 0 ]]; then
	echo "$total scripts parsés, aucune erreur."
	exit 0
fi
echo "Scripts en erreur (${#failed[@]}/$total) : ${failed[*]}"
exit 1
