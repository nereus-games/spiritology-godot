## Fournisseur d'action piloté par le joueur : suspend la boucle jusqu'à [method submit].
##
## Contrat avec l'UI de rencontre : à chaque tour du combattant concerné, [signal
## choice_requested] est émis (l'UI ouvre son menu d'action / ciblage), puis la boucle
## reste suspendue jusqu'à ce que l'UI appelle [method submit] avec le choix validé.
## Les options proposables se lisent sur le manager ([method EncounterManager.usable_abilities],
## [method EncounterManager.candidate_targets]).
class_name UiAgent
extends EncounterAgent

## Émis quand la boucle attend un choix pour `fighter`.
signal choice_requested(fighter: EncounterFighter, manager: EncounterManager)

signal _submitted(action: EncounterAction)

## Combattant dont le choix est attendu (null si la boucle n'attend pas).
var pending_fighter: EncounterFighter = null


func decide(fighter: EncounterFighter, manager: EncounterManager) -> EncounterAction:
	pending_fighter = fighter
	# Émission DIFFÉRÉE, sinon un handler qui répond dans la foulée (ex. « aucune capacité
	# jouable » → submit immédiat) appellerait submit() avant que l'await ci-dessous ne
	# soit atteint : le signal partirait dans le vide et la rencontre resterait figée.
	# Différer garantit que la boucle est suspendue avant que quiconque puisse répondre.
	choice_requested.emit.call_deferred(fighter, manager)
	var action: EncounterAction = await _submitted
	pending_fighter = null
	return action


## Valide le choix du joueur et relance la boucle. `null` = le combattant ne peut rien
## faire (tour perdu). À n'appeler qu'en réponse à [signal choice_requested].
func submit(action: EncounterAction) -> void:
	_submitted.emit(action)
