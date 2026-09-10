## État de la partie en cours (autoload `GameSession`).
##
## Tout ce qui change pendant une partie et doit être sauvegardé : duo de personnages,
## avancement de l'encyclopédie, états des donjons, score PSY. Distinct de [GameData]
## (données statiques chargées au boot). Sérialisé par [SaveSystem] en JSON.
extends Node

## Paliers de score PSY qui modulent les IFP gagnés (≤10, 10<PSY≤30, >30).
const PSY_LOW := 10
const PSY_HIGH := 30

## Seuil du compteur FDE : à 3 rencontres « parfaites » d'affilée, +1 PSY.
const FDE_THRESHOLD := 3

## Plafond d'IFP gagnables par espèce via « Examine decor / ground » en exploration.
## Distinct du total de page (0..100) : cette source ne peut octroyer qu'au plus 15 IFP.
const EXAMINE_DECOR_CAP := 15

## Table des IFP gagnés selon (action, palier PSY). Source : doc Notion (Encyclopaedia,
## « Obtaining Info Points »). Chaque entrée est `[tier 0, tier 1, tier 2]`, indexée par
## [method psy_tier] (tier 0 = PSY ≤ 10 ; tier 1 = 10 < PSY ≤ 30 ; tier 2 = 30 < PSY).
## Les variantes Forlorn sont des lignes séparées ; la substitution Forlorn→normal
## (page principale incomplète) est gérée dans [method ifp_amount], pas ici.
const IFP_TABLE := {
	# Examine décor / sol : identique normal/Forlorn (pas de variante Forlorn).
	GameEnums.IfpAction.EXAMINE_DECOR:
	{
		false: [3, 3, 2],
	},
	GameEnums.IfpAction.EXAMINE_RIVAL:
	{
		false: [6, 8, 9],  # rival normal
		true: [12, 13, 14],  # rival Forlorn (page principale complétée)
	},
	GameEnums.IfpAction.TALK_RIVAL:
	{
		false: [2, 2, 1],
		true: [4, 4, 2],
	},
	GameEnums.IfpAction.DISSOLVE_RIVAL:
	{
		false: [1, 2, 2],
		true: [2, 3, 4],
	},
}

## DEN (Density) maximum d'un personnage joueur, fixe pour toute la partie.
const MAX_DEN := 100

## ORDRES DE GRANDEUR du DEN d'un rival ordinaire selon l'avancement du jeu (doc « Game Units
## / Density » : ~50 early, 100 mid, 125 late).
##
## Ce ne sont PAS des paliers appliqués automatiquement : le DEN de départ d'un rival est
## attribué par le LEVEL DESIGN, donjon par donjon, en visant ces ordres de grandeur. D'où des
## constantes de référence plutôt qu'un état de partie.
const RIVAL_DEN_EARLY := 50
const RIVAL_DEN_MID := 100
const RIVAL_DEN_LATE := 125

## ETH (Ether) maximum d'un personnage joueur.
## ## TODO: max ETH par espèce quand Notion le chiffrera (placeholder cohérent avec
## BalanceData.base_eth).
const MAX_ETH := 50

## Emplacements du duo jouable. Indexe [member party_den] / [member party_eth].
enum PartySlot { MAIN, TEAMMATE }

signal psy_changed(new_value: int)
signal fde_changed(new_value: int)
signal encyclopaedia_progress(species_id: StringName, ifp: int)
## DEN persistant d'un emplacement modifié (dégâts/soin, restauration de dévitalisation).
signal den_changed(slot: PartySlot, new_value: int)
## ETH persistant d'un emplacement modifié (coût/récupération, restauration en donjon).
signal eth_changed(slot: PartySlot, new_value: int)
## Les DEUX personnages du duo sont dévitalisés simultanément (DEN restauré à 1 chacun).
## L'exploration doit réagir en sortant le duo du donjon courant.
signal party_wiped
## Quantité d'un objet d'inventaire modifiée. `new_count` est 0 si l'objet est épuisé.
signal inventory_changed(object_id: StringName, new_count: int)

## Duo jouable (slugs d'espèces), déterminé par le mini-quiz de personnalité.
## Peut contenir deux fois la même espèce (talent cumulé).
var main_character: StringName
var teammate: StringName

## Nom donné par le joueur au personnage principal.
var player_name: String = ""

## DEN (vie) persistant par emplacement : [enum PartySlot] -> int dans [0, MAX_DEN].
## Persiste sur toute la partie (les dégâts subis en rencontre ne sont PAS oubliés).
var party_den: Dictionary = {
	PartySlot.MAIN: MAX_DEN,
	PartySlot.TEAMMATE: MAX_DEN,
}

## ETH (énergie des capacités) persistant par emplacement : [enum PartySlot] -> int dans
## [0, MAX_ETH]. Entièrement restauré à chaque entrée de donjon ([method restore_party_eth]).
var party_eth: Dictionary = {
	PartySlot.MAIN: MAX_ETH,
	PartySlot.TEAMMATE: MAX_ETH,
}

## Score psychologique courant. Influence le nombre d'IFP obtenus.
var psy_score: int = 0:
	set(value):
		psy_score = value
		psy_changed.emit(psy_score)

## Compteur FDE (Full Devitalisation Encounters) — « murderous spree » caché au joueur.
## S'incrémente à chaque rencontre où TOUS les rivaux sont dévitalisés ; se remet à 0
## dès qu'une rencontre se termine autrement. À [constant FDE_THRESHOLD], convertit en +1 PSY.
var fde_count: int = 0:
	set(value):
		fde_count = value
		fde_changed.emit(fde_count)

## Avancement encyclopédie : species_id -> IFP accumulés (1 IFP = 1 % d'une page).
var encyclopaedia_ifp: Dictionary = {}

## Suivi persistant de l'IFP déjà gagné par espèce via « Examine decor / ground » en
## exploration : species_id -> int cumulé, plafonné à [constant EXAMINE_DECOR_CAP].
## Sert à appliquer le plafond de 15 IFP/espèce de cette source (restriction 1).
var exploration_examine_ifp: Dictionary = {}

## États persistants par donjon : dungeon_id -> Dictionary (cases visitées, etc.).
var dungeon_states: Dictionary = {}

## Capacités d'exploration déjà utilisées cette visite de donjon (id -> true). Une capacité
## d'exploration s'utilise UNE fois par visite ; l'action Recycle (litière) en rafraîchit une
## au hasard, le cristal de rafraîchissement les rafraîchit toutes. Réinitialisé à l'entrée
## d'un donjon ([method reset_exploration_abilities]).
var used_exploration_abilities: Dictionary = {}

## Inventaire : slug d'objet (StringName) -> quantité (int > 0). « Stackable » : un même
## objet est compté, pas dupliqué. Une entrée à 0 est supprimée (cf. [method remove_object]).
## Réfère un [ObjectData] via [GameData]. Aucun objet n'est nécessaire pour finir le jeu.
var inventory: Dictionary = {}


## Palier PSY courant (0, 1 ou 2) pour le calcul d'IFP.
func psy_tier() -> int:
	if psy_score <= PSY_LOW:
		return 0
	if psy_score <= PSY_HIGH:
		return 1
	return 2


## Espèce déjà inscrite à l'encyclopédie (au moins 1 IFP glané) ?
##
## Sert de garde d'affichage à l'UI de rencontre : « rival's density and weakness aren't
## shown in timeline if they aren't in the encyclopaedia (yet) ».
func knows_species(species_id: StringName) -> bool:
	return int(encyclopaedia_ifp.get(species_id, 0)) > 0


## Ajoute des IFP à une espèce et notifie la progression.
func add_ifp(species_id: StringName, amount: int) -> void:
	var current: int = encyclopaedia_ifp.get(species_id, 0)
	encyclopaedia_ifp[species_id] = min(current + amount, 100)
	encyclopaedia_progress.emit(species_id, encyclopaedia_ifp[species_id])


# --- Calcul des IFP gagnés (table « Obtaining Info Points ») ---


## Montant brut d'IFP de la table pour une `action` et son caractère Forlorn, au palier PSY
## courant ([method psy_tier]). Fonction pure : ne modifie aucun état.
##
## Restriction 3 (substitution Forlorn) : un rival Forlorn n'octroie ses IFP majorés que si
## la page principale de son espèce est déjà complétée. `main_page_complete` porte cette
## information (calculée par l'appelant depuis [member encyclopaedia_ifp]) ; si Forlorn mais
## page incomplète, on retombe sur la ligne « normale » de la même action.
func ifp_amount(
	action: GameEnums.IfpAction, is_forlorn: bool, main_page_complete: bool = false
) -> int:
	# Forlorn majoré seulement si la page principale est complète ; sinon ligne normale.
	var use_forlorn := is_forlorn and main_page_complete
	var variants: Dictionary = IFP_TABLE[action]
	# EXAMINE_DECOR n'a pas de variante Forlorn : repli sur la ligne normale.
	var by_tier: Array = variants.get(use_forlorn, variants[false])
	return by_tier[psy_tier()]


## Octroie les IFP d'une `action` à une espèce et retourne le montant réellement ajouté.
## Point d'entrée de haut niveau qui applique les trois restrictions documentées :
##   - restriction 2 : un Talk non effectif (`dialogue_effective == false`) n'octroie rien ;
##   - restriction 3 : la substitution Forlorn→normal (page principale incomplète), via
##     [method ifp_amount] (`main_page_complete` calculé ici depuis [member encyclopaedia_ifp]) ;
##   - restriction 1 : pour [constant GameEnums.IfpAction.EXAMINE_DECOR], le cumul par espèce
##     est plafonné à [constant EXAMINE_DECOR_CAP] (montant tronqué, puis 0 une fois atteint).
## L'ajout final passe par [method add_ifp] (qui borne déjà la page à 100).
## ## TODO: page Forlorn à pourcentage distinct quand le modèle d'encyclopédie le supportera
## (aujourd'hui les IFP Forlorn s'ajoutent à la page d'espèce existante).
## ## TODO: brancher l'exploration (Examine decor/ground), seule source d'IFP encore sans
## site d'appel. La rencontre, elle, appelle : Examine / Talk / dissolution passent par le
## signal [signal EncounterManager.ifp_earned], relayé ici par l'UI de rencontre.
func award_ifp(
	species_id: StringName,
	action: GameEnums.IfpAction,
	is_forlorn: bool = false,
	dialogue_effective: bool = true
) -> int:
	# Restriction 2 : Talk inefficace → aucun IFP.
	if action == GameEnums.IfpAction.TALK_RIVAL and not dialogue_effective:
		return 0
	var main_page_complete: bool = int(encyclopaedia_ifp.get(species_id, 0)) >= 100
	var amount := ifp_amount(action, is_forlorn, main_page_complete)
	# Restriction 1 : plafond cumulé de 15 IFP/espèce pour Examine decor / ground.
	if action == GameEnums.IfpAction.EXAMINE_DECOR:
		var already: int = exploration_examine_ifp.get(species_id, 0)
		var room := EXAMINE_DECOR_CAP - already
		if room <= 0:
			return 0
		amount = mini(amount, room)
		exploration_examine_ifp[species_id] = already + amount
	if amount <= 0:
		return 0
	add_ifp(species_id, amount)
	return amount


# --- Talents du duo ---


## Le duo porte-t-il ce talent ? Un talent appartient à une ESPÈCE (relation 1:1, cf.
## [member SpeciesData.talent]) : le duo le possède si l'un de ses deux membres est de cette
## espèce. Nécessaire HORS rencontre, où il n'existe aucun [EncounterFighter] pour porter le
## [TalentScript] — c'est le cas des talents d'exploration (coffres, pièges, carte).
func party_has_talent(talent_id: StringName) -> bool:
	return party_talent_stacks(talent_id) > 0


## Nombre d'exemplaires du talent dans le duo (0, 1 ou 2 : un duo de même espèce le cumule,
## cf. [member TalentData.stackable]).
func party_talent_stacks(talent_id: StringName) -> int:
	var stacks := 0
	for member in [main_character, teammate]:
		if member == &"":
			continue
		var sp: SpeciesData = GameData.species(member)
		if sp != null and sp.talent == talent_id:
			stacks += 1
	return stacks


# --- État persistant DEN / ETH du duo ---


## DEN courant d'un emplacement, borné [0, MAX_DEN].
func get_den(slot: PartySlot) -> int:
	return party_den.get(slot, MAX_DEN)


## ETH courant d'un emplacement, borné [0, MAX_ETH].
func get_eth(slot: PartySlot) -> int:
	return party_eth.get(slot, MAX_ETH)


## Fixe le DEN d'un emplacement (borné [0, MAX_DEN]) et notifie si changement.
func set_den(slot: PartySlot, value: int) -> void:
	var clamped := clampi(value, 0, MAX_DEN)
	if party_den.get(slot) == clamped:
		return
	party_den[slot] = clamped
	den_changed.emit(slot, clamped)


## Fixe l'ETH d'un emplacement (borné [0, MAX_ETH]) et notifie si changement.
func set_eth(slot: PartySlot, value: int) -> void:
	var clamped := clampi(value, 0, MAX_ETH)
	if party_eth.get(slot) == clamped:
		return
	party_eth[slot] = clamped
	eth_changed.emit(slot, clamped)


## Applique des dégâts DEN à un emplacement (montant >= 0). Retourne le DEN restant.
func apply_den_damage(slot: PartySlot, amount: int) -> int:
	set_den(slot, get_den(slot) - maxi(amount, 0))
	return get_den(slot)


## Soigne le DEN d'un emplacement (montant >= 0). Retourne le DEN restant.
func heal_den(slot: PartySlot, amount: int) -> int:
	set_den(slot, get_den(slot) + maxi(amount, 0))
	return get_den(slot)


## Dépense de l'ETH sur un emplacement (coût d'une capacité, >= 0). Retourne l'ETH restant.
func spend_eth(slot: PartySlot, amount: int) -> int:
	set_eth(slot, get_eth(slot) - maxi(amount, 0))
	return get_eth(slot)


## Récupère de l'ETH sur un emplacement (montant >= 0). Retourne l'ETH restant.
func recover_eth(slot: PartySlot, amount: int) -> int:
	set_eth(slot, get_eth(slot) + maxi(amount, 0))
	return get_eth(slot)


## Restaure entièrement l'ETH des deux emplacements du duo.
## À appeler à l'entrée d'un donjon (« Fully restored when entering a dungeon »).
func restore_party_eth() -> void:
	set_eth(PartySlot.MAIN, MAX_ETH)
	set_eth(PartySlot.TEAMMATE, MAX_ETH)


## Vrai si l'emplacement est dévitalisé (DEN tombé à 0).
func is_devitalised(slot: PartySlot) -> bool:
	return get_den(slot) <= 0


## Vrai si les DEUX emplacements du duo sont dévitalisés simultanément.
func is_party_wiped() -> bool:
	return is_devitalised(PartySlot.MAIN) and is_devitalised(PartySlot.TEAMMATE)


## Applique la règle de duo entièrement dévitalisé : DEN restauré à 1 pour chacun, puis
## émet [signal party_wiped] pour que l'exploration sorte le duo du donjon courant.
## Ne fait rien si le duo n'est pas entièrement dévitalisé. Retourne true si déclenché.
func resolve_party_wipe() -> bool:
	if not is_party_wiped():
		return false
	set_den(PartySlot.MAIN, 1)
	set_den(PartySlot.TEAMMATE, 1)
	party_wiped.emit()
	return true


## Enregistre la fin d'une rencontre pour mettre à jour le compteur FDE.
## `all_rivals_devitalised` = true uniquement si tous les rivaux ont été dissous (victoire).
## À [constant FDE_THRESHOLD] rencontres parfaites d'affilée : +1 PSY puis remise à 0.
func register_encounter_end(all_rivals_devitalised: bool) -> void:
	if not all_rivals_devitalised:
		fde_count = 0
		return
	fde_count += 1
	if fde_count >= FDE_THRESHOLD:
		psy_score += 1
		fde_count = 0


# --- Inventaire (objets consommables empilables) ---


## Quantité possédée d'un objet (0 si absent).
func object_count(object_id: StringName) -> int:
	return inventory.get(object_id, 0)


## Vrai si au moins un exemplaire de l'objet est possédé.
func has_object(object_id: StringName) -> bool:
	return object_count(object_id) > 0


## Ajoute `count` exemplaires d'un objet (empilable). `count` <= 0 est ignoré.
## Notifie via [signal inventory_changed]. Retourne la nouvelle quantité.
func add_object(object_id: StringName, count: int = 1) -> int:
	if count <= 0:
		return object_count(object_id)
	var new_count := object_count(object_id) + count
	inventory[object_id] = new_count
	inventory_changed.emit(object_id, new_count)
	return new_count


## Retire `count` exemplaires d'un objet. Échoue (retourne false, sans rien changer) si
## `count` <= 0 ou si la quantité possédée est insuffisante. Nettoie l'entrée tombée à 0.
## Notifie via [signal inventory_changed] en cas de succès.
func remove_object(object_id: StringName, count: int = 1) -> bool:
	if count <= 0:
		return false
	var current := object_count(object_id)
	if current < count:
		return false
	var new_count := current - count
	if new_count == 0:
		inventory.erase(object_id)
	else:
		inventory[object_id] = new_count
	inventory_changed.emit(object_id, new_count)
	return true


## Consomme un exemplaire d'un objet (sémantique « consommable » : retiré après usage).
## Retourne false si l'objet n'est pas possédé.
func consume_object(object_id: StringName) -> bool:
	return remove_object(object_id, 1)


# --- Capacités d'exploration (usage unique par visite, rafraîchissables) ---


## Marque une capacité d'exploration comme utilisée pour cette visite de donjon.
func mark_exploration_ability_used(id: StringName) -> void:
	used_exploration_abilities[id] = true


## Vrai si la capacité d'exploration a déjà été utilisée cette visite.
func is_exploration_ability_used(id: StringName) -> bool:
	return used_exploration_abilities.get(id, false)


## Rafraîchit UNE capacité d'exploration utilisée, choisie au hasard (action Recycle de la
## litière). Retourne l'id rafraîchi, ou &"" si aucune n'était utilisée. `rng` optionnel
## pour les tests déterministes.
func refresh_random_exploration_ability(rng: RandomNumberGenerator = null) -> StringName:
	var used: Array = used_exploration_abilities.keys()
	if used.is_empty():
		return &""
	var idx := (rng.randi() if rng != null else randi()) % used.size()
	var id: StringName = used[idx]
	used_exploration_abilities.erase(id)
	return id


## Rafraîchit TOUTES les capacités d'exploration utilisées (cristal de rafraîchissement).
func refresh_all_exploration_abilities() -> void:
	used_exploration_abilities.clear()


## Réinitialise le suivi des capacités d'exploration (à l'entrée d'un donjon).
func reset_exploration_abilities() -> void:
	used_exploration_abilities.clear()


## Réinitialise la session pour une nouvelle partie.
## DEN/ETH du duo repartent au maximum ([constant MAX_DEN] / [constant MAX_ETH]).
func reset() -> void:
	main_character = &""
	teammate = &""
	player_name = ""
	psy_score = 0
	fde_count = 0
	encyclopaedia_ifp.clear()
	exploration_examine_ifp.clear()
	dungeon_states.clear()
	used_exploration_abilities.clear()
	inventory.clear()
	party_den = {
		PartySlot.MAIN: MAX_DEN,
		PartySlot.TEAMMATE: MAX_DEN,
	}
	party_eth = {
		PartySlot.MAIN: MAX_ETH,
		PartySlot.TEAMMATE: MAX_ETH,
	}
