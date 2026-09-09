## Schéma d'un objet d'inventaire (consommable, empilable).
##
## Instances .tres (texte) dans `data/objects/`, éditées à la main comme les autres
## Resources — cf. `docs/data-model.md`. Données LÉGÈRES uniquement : chargées au boot.
##
## Doc source : Game Design / section « Objects + Inventory ». « There is no necessary
## object in this game » : tous consommables (retirés après usage), tous empilables,
## obtenus chez des marchands ou auprès du Pr Shadako ravbak.
##
## ## NOTE: les objets ne sont pas une BASE DE DONNÉES Notion comme les espèces et les
## capacités — ils sont décrits en liste à puces dans la page « Game Design ». Leur effet
## est donc mappé PAR SLUG et non déduit de la prose ; la table est dans docs/data-model.md.
## Les mêmes slugs servent de tags à la propriété « Potential Loot » des espèces.
##
## ## NOTE: « costume » n'est PAS généré : la doc dit « the costume name indicates which
## spirimonster – e.g. fopin costume », donc il y en a un par espèce, et l'espèce évitée
## est « specified in object description ». Rien dans Notion ne les énumère.
class_name ObjectData
extends Resource

## Identifiant slug stable (ex. "smoke_bomb", "rune_stone"). Sert de clé d'inventaire
## (cf. [GameSession.inventory]) et de base aux clés de traduction.
## Pour les costumes, le slug porte l'espèce concernée (ex. "fopin_costume").
@export var id: StringName

## Catégorie d'effet, conditionne les champs paramétriques pertinents.
@export var effect: GameEnums.ObjectEffect = GameEnums.ObjectEffect.NONE

## Magnitude générique de l'effet, interprétée selon [member effect] :
## - HEAL_DEN : DEN donné à la cible (« Y DEN » de la doc) ;
## - DISGUISE : probabilité accrue de rencontre avec l'espèce ciblée (« X % » de la doc).
## ## TODO: chiffrages X % / Y DEN non fixés par la doc → à renseigner depuis Notion.
@export var magnitude: int = 0

## Durée d'effet exprimée en déplacements du joueur, pour les objets persistants.
## La doc fixe explicitement 15 pour le Costume (déguisement) et le Torment veil (voile).
## ## TODO: confirmer / paramétrer par instance depuis Notion (0 = sans durée / instantané).
@export var duration_moves: int = 0

## Espèce associée à l'effet (slug), pour les objets ciblant une espèce.
## Costume : espèce dont on prend l'apparence (rencontres plus probables si présente).
## Vide pour les objets sans espèce associée.
@export var species_id: StringName

## Seconde espèce associée, le cas échéant. Costume : espèce dont le port évite TOUTES
## les rencontres (précisée dans la description de l'objet). Vide si non pertinent.
@export var secondary_species_id: StringName

## Clé de traduction du nom affichable. Convention : OBJECT_<ID_MAJ>_NAME.
## Les libellés EN/FR viendront des instances générées depuis Notion (translations/*.po),
## comme pour [SpeciesData] / [AbilityData] : le schéma n'ajoute aucune clé en dur.
func name_key() -> String:
	return "OBJECT_%s_NAME" % GameEnums.key_token(id)

## Clé de traduction de la description. Convention : OBJECT_<ID_MAJ>_DESC.
func description_key() -> String:
	return "OBJECT_%s_DESC" % GameEnums.key_token(id)
