## Action choisie par un combattant pour son tour.
##
## Vocabulaire commun entre les fournisseurs d'action ([EncounterAgent], qui décident)
## et le résolveur ([EncounterManager], qui applique). Liste tirée de la doc Notion
## (Game Design / Encounters) : « Talk, Examine, Use Ability (Challenge), Use / Give
## Object, Meditate ».
##
## [constant Kind.PASS] est l'action « … » de la doc UI : elle n'apparaît que si aucune
## autre n'est disponible et fait passer le tour SANS perdre sa place dans l'ordre.
##
## [constant Kind.FLEE] est bien une action de MENU, mais jamais proposée par défaut : la
## doc la qualifie de « special action from Abilities + Talents ». Deux voies distinctes :
##   - un talent l'AJOUTE au menu, sous ses propres conditions — `run_away_2` (zuk) la
##     donne en permanence en remplacement de Talk et réussit toujours, sans QTE ;
##     `slick_merchant` (fopin) ne la donne qu'au 1er tour ou à ≤ 10 % de DEN, contre
##     10 ETH, et avec un QTE (donc faillible) ;
##   - une capacité l'EXÉCUTE directement, sans passer par le menu — cf. [method
##     EncounterContext.flee], appelé par `ghosting` et `opening_up_closing`.
## ## TODO: aucune des deux voies n'est branchée. La 1re attend le système de talents (les
## 10 talents sont des passifs non scriptés, faute de point d'application) ; la 2de est un
## stub journalisé. Dans les deux cas, quitter la rencontre suppose la téléportation en
## exploration (3-5 cases, 50 % de chance que le rival disparaisse), non bâtie.
class_name EncounterAction
extends RefCounted

## [constant Kind.STEAL] est, comme [constant Kind.FLEE], une action ajoutée au menu par un
## talent — `steal` (granop) la donne en remplacement de Talk : elle prend un objet à la
## cible, au risque de faire apparaître un membre du Coal Vetch (systèmes non bâtis → stub).
enum Kind { ABILITY, TALK, EXAMINE, MEDITATE, USE_OBJECT, FLEE, STEAL, PASS }

var kind: Kind = Kind.ABILITY
var ability: AbilityData = null   ## Kind.ABILITY uniquement
var targets: Array = []           ## EncounterFighter visés
var object_id: StringName = &""   ## Kind.USE_OBJECT uniquement

static func use_ability(p_ability: AbilityData, p_targets: Array) -> EncounterAction:
	var a := EncounterAction.new()
	a.kind = Kind.ABILITY
	a.ability = p_ability
	a.targets = p_targets
	return a

static func of_kind(p_kind: Kind, p_targets: Array = []) -> EncounterAction:
	var a := EncounterAction.new()
	a.kind = p_kind
	a.targets = p_targets
	return a

## Libellé court pour le journal de combat (debug). Les textes destinés au joueur
## passent par des clés de traduction, jamais par cette méthode.
func label() -> String:
	if kind == Kind.ABILITY:
		return String(ability.id) if ability else "?"
	return String(Kind.keys()[kind]).to_lower()
