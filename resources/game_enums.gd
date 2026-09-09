## Énumérations partagées du jeu.
##
## Centralise les types fermés référencés par les Resources (espèces, capacités) et
## par la logique de rencontre. Source : doc Notion (Game Design / Abilities + Talents).
## Utilisé comme namespace statique : `GameEnums.Energy.HEAT`, etc.
class_name GameEnums
extends RefCounted

## Spiricosme d'origine. Affecte les modificateurs de dégâts (+36 % si user et
## cible partagent le même). Traductions : Gloom→Terne, Fiery→Ardent, Wonderful→Merveilleux.
enum Spiricosm {
	GLOOM,      ## Terne
	FIERY,      ## Ardent
	WONDERFUL,  ## Merveilleux
}

## Les 5 énergies, plus deux modes spéciaux pour les capacités dont l'énergie
## change chaque tour (identique pour tous les utilisateurs d'un même tour).
enum Energy {
	HEAT,      ## chaleur
	FLUID,     ## fluide
	CRYSTAL,   ## cristal
	ARCANE,    ## arcane
	TOXIC,     ## toxique
	RANDOM,    ## tirée au hasard chaque tour
	VARIABLE,  ## variable selon un effet de la capacité
	NONE,      ## capacité sans énergie (talents, exploration, certaines rencontres)
}

## Type de capacité (cf. [AbilityData]).
enum AbilityType {
	TALENT,       ## passif, une par espèce, non apprenable, non encyclopédiable
	EXPLORATION,  ## usage unique par visite de donjon (sauf cristaux de rechargement)
	ENCOUNTER,    ## utilisable par joueurs et rivaux ; peut modifier l'ordre du tour / l'UI
}

## Coût en ETH d'une capacité de rencontre. Valeurs issues du tableau Notion.
enum Cost {
	NONE,
	MINI,
	NORMAL,
	MEDIUM,
	A_LOT,
}

## Position dans l'ordre du tour : détermine quelle faiblesse d'une espèce est active.
## L'ordre est fixé au début de la rencontre puis modifié uniquement par des capacités.
enum TurnPosition {
	FIRST,
	MIDDLE,
	LAST,
}

## Action générant des IFP (info points) pour l'encyclopédie.
## Source : doc Notion (Game Design / Encyclopaedia, « Obtaining Info Points »).
## Le caractère Forlorn vs normal d'un rival est un booléen séparé (pas une entrée ici),
## car la majoration Forlorn n'est appliquée que si la page principale est déjà complétée.
enum IfpAction {
	EXAMINE_DECOR,  ## Examiner décor / sol pendant l'exploration (plafonné à 15 IFP/espèce).
	EXAMINE_RIVAL,  ## Examiner un rival en rencontre.
	TALK_RIVAL,     ## Parler à un rival (n'octroie que si le dialogue est effectif).
	DISSOLVE_RIVAL, ## Dissoudre (dévitaliser) un rival.
}

## Catégorie d'effet d'un objet d'inventaire (cf. [ObjectData]).
## Source : doc Notion (Game Design / Objects + Inventory). Tous les objets sont
## consommables et empilables ; cet enum décrit CE QUE FAIT l'objet, pas ses chiffres
## (magnitude / durée sont des champs paramétriques sur [ObjectData]).
## ## TODO: les flux de gameplay consommant ces effets (fuite, poison, déguisement,
## sols friables, poursuite des rivaux) ne sont pas encore construits.
enum ObjectEffect {
	NONE,            ## Aucun effet mécanique (objet narratif, ex. Notice / annonce).
	HEAL_DEN,        ## Donne du DEN à une cible (ex. Rune stone / pierre runique).
	FLEE_ENCOUNTER,  ## Permet de fuir une rencontre (ex. Smoke bomb / bombe fumée).
	CURE_POISON,     ## Soigne le mécanisme de poison (ex. Tea drop / goutte de thé).
	DISGUISE,        ## Donne l'apparence d'une espèce (ex. Costume / déguisement).
	DIG,             ## Utilisable sur les sols friables (ex. Spade / pelle).
	AVOID_PURSUIT,   ## Les rivaux ne poursuivent ni n'initient de rencontres (ex. Torment veil).
}


## Translittère un slug en token de clé de traduction : MAJUSCULE + accents pliés
## en ASCII. DOIT rester identique à `_key_token()` du générateur
## (`tools/notion_to_tres.gd`), sinon `tr()` échoue sur les ids accentués (ex.
## l'id « razél » → clé `SPECIES_RAZEL_NAME`, telle qu'écrite dans les .po).
## Point unique partagé par tous les `name_key()`/`desc_key()` des Resources.
static func key_token(raw) -> String:
	var s := str(raw).to_upper()
	var map := {"É": "E", "È": "E", "Ê": "E", "À": "A", "Â": "A", "Î": "I",
		"Ï": "I", "Ô": "O", "Û": "U", "Ù": "U", "Ç": "C"}
	for k in map:
		s = s.replace(k, map[k])
	return s
