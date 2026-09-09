## Fournisseur d'action : décide ce que fait un combattant à son tour.
##
## Sépare la BOUCLE de rencontre ([EncounterManager]) de la DÉCISION. Le manager fait
## `await agent.decide(...)` : une implémentation synchrone ([AutoAgent]) répond
## immédiatement et la rencontre se résout d'une traite (mode auto, testable headless) ;
## une implémentation qui attend le joueur ([UiAgent]) suspend la boucle jusqu'au choix.
## C'est le seul point d'entrée du pilotage — la boucle n'est écrite qu'une fois.
class_name EncounterAgent
extends RefCounted

## Renvoie l'action de `fighter` pour ce tour, ou null s'il ne peut rien faire.
## Peut être une coroutine : le manager `await` toujours le résultat.
func decide(_fighter: EncounterFighter, _manager: EncounterManager) -> EncounterAction:
	return null
