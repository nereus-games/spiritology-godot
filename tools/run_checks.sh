#!/usr/bin/env bash
#
# Lance toutes les vérifications headless de scenes/dev/*_check.tscn et agrège
# leurs résultats. Sort en 1 dès qu'une seule échoue.
#
#   ./tools/run_checks.sh                # toutes
#   ./tools/run_checks.sh encounter data # celles dont le nom contient l'un de ces mots
#   GODOT=/chemin/vers/Godot ./tools/run_checks.sh
#
# Deux pièges que ce lanceur existe pour couvrir :
#
#  - Un check dont le SCRIPT ne compile pas ne signale rien : Godot charge la scène sans
#    son script, personne n'appelle quit(), et le processus tourne indéfiniment. D'où le
#    timeout par check — sans lui, une CI reste bloquée jusqu'à sa propre limite.
#  - Godot rend 0 en signalant des erreurs de script ou des instances fuitées sur sa
#    sortie. Le code de retour seul laisserait donc passer ces régressions : on relit
#    aussi la sortie.
#
set -uo pipefail

# shellcheck source=tools/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TIMEOUT="${TIMEOUT:-300}"

# Motifs qui trahissent un échec malgré un code de retour nul.
SILENT_FAILURES='SCRIPT ERROR|Failed to load script|leaked at exit|still in use at exit'

require_godot

# Exécute une commande en la tuant au-delà de $TIMEOUT secondes (macOS n'a pas timeout(1)).
# Rend 124 en cas d'expiration, comme le ferait timeout(1).
run_with_timeout() {
	local out_file="$1"; shift
	"$@" >"$out_file" 2>&1 &
	local pid=$!
	( sleep "$TIMEOUT"; kill -9 "$pid" 2>/dev/null ) 2>/dev/null &
	local watcher=$!
	# `wait` sous silence : quand le veilleur tue le processus, le shell annoncerait
	# « Killed: 9 » en plein milieu de la ligne de résultat.
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
	echo "Aucun check à lancer." >&2
	exit 2
fi

log_dir="$(mktemp -d)"
trap 'rm -rf "$log_dir"' EXIT

failed=()
printf '%s\n' "Godot   : $GODOT"
printf '%s\n' "Projet  : $PROJECT_DIR"
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
		reason="expiré après ${TIMEOUT}s (script non compilé ? boucle infinie ?)"
	elif [[ $code -ne 0 ]]; then
		reason="code de retour $code"
	elif grep -qE "$SILENT_FAILURES" "$out"; then
		reason="erreur signalée sur la sortie malgré un code 0"
	fi

	if [[ -z "$reason" ]]; then
		printf 'OK    %3ds\n' "$elapsed"
	else
		printf 'ÉCHEC %3ds  — %s\n' "$elapsed" "$reason"
		failed+=("$name")
		sed -e 's/^/      | /' "$out" | tail -20
	fi
done

echo
if [[ ${#failed[@]} -eq 0 ]]; then
	echo "Tous les checks passent (${#scenes[@]})."
	exit 0
fi
echo "Checks en échec (${#failed[@]}/${#scenes[@]}) : ${failed[*]}"
exit 1
