## Un combattant dans une rencontre (joueur ou rival). État + règles propres.
##
## Objet de logique (RefCounted) : l'état de combat est séparé de toute représentation
## visuelle. La faiblesse ACTIVE dépend de la position dans l'ordre du tour (first /
## in-between / last) et peut être surchargée pour le tour courant par une capacité.
## DEN (vie) / ETH (énergie) : valeurs de base placeholder — Notion ne chiffre pas
## encore les stats par espèce.
class_name EncounterFighter
extends RefCounted

const BASE_DEN := 100   ## TODO: stats par espèce quand la doc les fournira.
const BASE_ETH := 50

var species: SpeciesData
var is_player: bool
var max_den: int
var max_eth: int
var den: int
var eth: int

## Capacités de rencontre disponibles (slugs). Pour les joueurs : natives + apprises ;
## pour les rivaux : surtout leurs natives.
var ability_ids: Array[StringName] = []

## Modificateur des PROCHAINS dégâts reçus (mitigation/amplification/immunité=0).
## Consommé au prochain coup. 1.0 = normal.
var next_damage_factor := 1.0
## Si défini, les prochains dégâts reçus sont redirigés vers ce combattant (Victimism…).
var redirect_to: EncounterFighter = null

# --- États de tour (réinitialisés en début de ronde par clear_turn_state) ---
var immune_energies: Array = []                ## énergies auxquelles immunisé ce tour
var immune_all_except := GameEnums.Energy.NONE ## immunisé à TOUT sauf cette énergie (NONE = inactif)
var fully_immune := false                      ## immunisé à TOUS les dégâts ce tour
var den_locked := false                        ## ne peut perdre de DEN
var eth_locked := false                        ## ne peut perdre d'ETH
## Facteur de dégâts par énergie pour ce tour (Warning, Glaciation… : énergie→facteur).
var energy_damage_factor: Dictionary = {}
## Si vrai, renvoie à l'attaquant un montant égal aux dégâts subis (Reflux).
var reflect_to_attacker := false
var weakness_locked := false                   ## faiblesse non modifiable (Isotropy)
var weakness_hidden := false                   ## faiblesse cachée aux rivaux (UI)
## Dernier combattant lui ayant fait perdre DEN ou ETH (Cold Wave, Growth Mindset…).
var last_damager: EncounterFighter = null
## Bonus de dégâts INFLIGÉS pour le tour courant (Meditate). 0.0 = aucun. Additionné aux
## conditions +36 % dans [method EncounterContext._apply_modifiers].
var outgoing_damage_bonus := 0.0
## Bonus programmé pour le PROCHAIN tour (promu par [method clear_turn_state]).
var _pending_outgoing_bonus := 0.0

var _used_single: Dictionary = {}              ## id -> true (usage unique consommé)
var _weakness_override := false
var _weakness_energy := GameEnums.Energy.NONE  ## faiblesse forcée pour le tour courant

func _init(p_species: SpeciesData, p_is_player: bool) -> void:
	species = p_species
	is_player = p_is_player
	max_den = BASE_DEN
	max_eth = BASE_ETH
	den = max_den
	eth = max_eth
	if species:
		_populate_abilities()

## Capacités par défaut : natives + également utilisées + débloquées via encyclopédie.
## (Filtrage par type ENCOUNTER fait par le manager au moment du choix.)
func _populate_abilities() -> void:
	var seen := {}
	for list in [species.origin_abilities, species.also_used_abilities, species.encyclopaedia_abilities]:
		for aid in list:
			if not seen.has(aid):
				seen[aid] = true
				ability_ids.append(aid)

func species_id() -> StringName:
	return species.id if species else &""

func display_name() -> String:
	return String(TranslationServer.translate(species.name_key())) if species else "?"

func is_dissolved() -> bool:
	return den <= 0

## Faiblesse active selon la position dans l'ordre du tour (ou surcharge du tour).
func active_weakness(position: GameEnums.TurnPosition) -> GameEnums.Energy:
	if _weakness_override:
		return _weakness_energy
	return species.weakness_for(position) if species else GameEnums.Energy.NONE

## Force la faiblesse active pour le tour courant (capacités « change weakness »).
## Sans effet si la faiblesse est verrouillée (Isotropy). NONE = « plus de faiblesse ».
func override_weakness(energy: GameEnums.Energy) -> void:
	if weakness_locked:
		return
	_weakness_override = true
	_weakness_energy = energy

## Réinitialise l'override de faiblesse (retour à la faiblesse de position par défaut).
func reset_weakness() -> void:
	if not weakness_locked:
		_weakness_override = false

## Vrai si immunisé aux dégâts de cette énergie ce tour.
func is_immune_to(energy: GameEnums.Energy) -> bool:
	if fully_immune:
		return true
	if energy in immune_energies:
		return true
	if immune_all_except != GameEnums.Energy.NONE and energy != immune_all_except:
		return true
	return false

## Programme un bonus de dégâts infligés pour le PROCHAIN tour (Meditate : « damage +Y %
## until next turn »). En DEUX TEMPS délibérément : [method clear_turn_state] remet l'état
## de tour à zéro en début de ronde, donc un bonus posé directement serait effacé avant
## que le méditant ne rejoue — Meditate n'aurait alors jamais le moindre effet.
func grant_next_turn_damage_bonus(bonus: float) -> void:
	_pending_outgoing_bonus = bonus

## Réinitialise l'état de tour (surcharges/immunités/locks). Appelé en début de ronde.
func clear_turn_state() -> void:
	# Promotion du bonus programmé (cf. grant_next_turn_damage_bonus) AVANT remise à zéro.
	outgoing_damage_bonus = _pending_outgoing_bonus
	_pending_outgoing_bonus = 0.0
	_weakness_override = false
	immune_energies = []
	immune_all_except = GameEnums.Energy.NONE
	fully_immune = false
	den_locked = false
	eth_locked = false
	weakness_locked = false
	weakness_hidden = false
	energy_damage_factor = {}
	reflect_to_attacker = false

func apply_damage(amount: int) -> void:
	if den_locked:
		return
	den = maxi(den - amount, 0)

## Perte d'ETH SUBIE (capacité adverse). Bloquée par [member eth_locked].
func drain_eth(amount: int) -> void:
	if eth_locked:
		return
	eth = maxi(eth - amount, 0)

## Paiement VOLONTAIRE du coût de sa propre capacité. Ignore délibérément
## [member eth_locked], qui protège des ponctions adverses et n'a pas à rendre les
## capacités gratuites. Appelé par le [EncounterManager] avant d'exécuter l'effet.
func pay_eth(amount: int) -> void:
	eth = maxi(eth - amount, 0)

func recover_den(amount: int) -> void:
	den = mini(den + amount, max_den)

func recover_eth(amount: int) -> void:
	eth = mini(eth + amount, max_eth)

## Initialise DEN/ETH courants depuis un état persistant (bornés [0, max]).
## Point d'intégration avec [GameSession] : appelé par la couche d'orchestration pour les
## fighters JOUEURS, afin que les dégâts subis lors des rencontres précédentes persistent.
## Le max reste celui défini par le fighter (placeholder par espèce pour l'instant).
func load_persistent_state(p_den: int, p_eth: int) -> void:
	den = clampi(p_den, 0, max_den)
	eth = clampi(p_eth, 0, max_eth)

## Vrai si l'usage unique de cette capacité est déjà consommé pour cette rencontre.
func is_spent(ability: AbilityData) -> bool:
	return ability.single_use and _used_single.has(ability.id)

## Vrai si le fighter a de quoi payer le coût en ETH de cette capacité.
func can_afford(ability: AbilityData) -> bool:
	return eth >= ability.eth_cost()

## Vrai si la capacité est jouable MAINTENANT : ni consommée, ni trop chère.
func can_use(ability: AbilityData) -> bool:
	return not is_spent(ability) and can_afford(ability)

func mark_used(ability: AbilityData) -> void:
	if ability.single_use:
		_used_single[ability.id] = true

## Annule la consommation d'une capacité à usage unique — la rend à nouveau disponible
## dans cette rencontre. Utilisé par le talent Reuse (jézal) via le manager.
func clear_used(ability: AbilityData) -> void:
	_used_single.erase(ability.id)

## Rompt les références vers d'AUTRES combattants ([member last_damager],
## [member redirect_to]). À appeler quand la rencontre est finie.
##
## Nécessaire, et pas seulement propre : deux combattants qui se sont frappés se pointent
## mutuellement, ce qui forme un CYCLE de RefCounted. Godot ne ramasse pas les cycles —
## les combattants d'une rencontre terminée resteraient donc en mémoire, avec leur
## [SpeciesData], jusqu'à la fermeture du jeu. Ces deux champs sont de l'état de combat
## transitoire, jamais affiché : les vider après coup n'ôte rien à personne.
func release_cross_references() -> void:
	last_damager = null
	redirect_to = null
