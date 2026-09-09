#!/usr/bin/env bash
#
# Réglages communs aux scripts de tools/. À sourcer, pas à exécuter.
#
# shellcheck shell=bash

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

## Vérifie que le binaire Godot est utilisable, sinon sort en 2.
require_godot() {
	if [[ ! -x "$GODOT" ]]; then
		echo "Godot introuvable : $GODOT" >&2
		echo "Renseignez la variable d'environnement GODOT." >&2
		exit 2
	fi
}

## Garantit la présence du cache des classes globales.
##
## Sur un dépôt fraîchement cloné, `.godot/` n'existe pas — or c'est là que vit ce cache,
## que SEUL l'éditeur régénère. Sans lui, AUCUN `class_name` ne se résout : `--check-only`
## signale « Could not find type » sur tout le projet, et les scènes de test se chargent
## sans leurs scripts, donc sans jamais appeler quit(). `--import` lance l'éditeur en
## headless le temps de reconstruire le cache (quelques secondes), une fois pour toutes.
ensure_class_cache() {
	[[ -f "$PROJECT_DIR/.godot/global_script_class_cache.cfg" ]] && return 0
	echo "Premier lancement : reconstruction du cache de classes (--import)…"
	"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1
	if [[ ! -f "$PROJECT_DIR/.godot/global_script_class_cache.cfg" ]]; then
		echo "L'import n'a produit aucun cache de classes ; tout échouerait ensuite." >&2
		exit 2
	fi
	echo
}
