## Contexte d'exécution d'un effet de capacité pendant une rencontre.
##
## Passé à [method AbilityEffect.execute] / [method AbilityScript.execute]. Point
## d'intégration unique entre les effets (code scriptable) et l'état de la rencontre
## (combattants [EncounterFighter], ordre du tour [EncounterTimeline], UI). Applique les
## règles Notion : modificateurs de dégâts +36 %/condition (additionnés puis arrondis au
## supérieur), faiblesse active selon la position de tour, mitigation/immunité, redirection.
class_name EncounterContext
extends RefCounted

## % de dégâts ajouté par condition remplie (faiblesse, même Spiricosme, encyclopédie
## 100 %, même espèce). Les conditions s'additionnent avant application.
const MODIFIER_PER_CONDITION := 0.36

## Demande à l'UI un effet spécial (Tumult déplace les éléments, Anodyne Excess cache
## les stats des rivaux…). `kind` identifie l'effet, `data` porte ses paramètres.
signal ui_requested(kind: StringName, data: Dictionary)

var ability: AbilityData
var user                       ## EncounterFighter qui utilise la capacité
var targets: Array = []        ## EncounterFighter ciblés
var all_fighters: Array = []   ## tous les individus (portée globale, ex. Tumult)
var timeline: EncounterTimeline
var rng: RandomNumberGenerator

## Énergie effective de la capacité ce tour (résout Random/Variable ; posé par le manager).
var resolved_energy := GameEnums.Energy.NONE
## Espèces dont l'encyclopédie est à 100 % (modificateur de dégâts). species_id -> true.
var completed_species: Dictionary = {}
## Override d'énergie effective (ex. « énergie = faiblesse du user »). NONE = inactif.
var energy_override := GameEnums.Energy.NONE

## Journal lisible des effets appliqués ce tour (debug + log de combat).
var log_lines: PackedStringArray = PackedStringArray()

func note(line: String) -> void:
	log_lines.append(line)

# --- Dégâts (avec modificateurs, mitigation, redirection) ---

func deal_damage(target, base_amount: int) -> void:
	if base_amount <= 0:
		return
	var victim = target
	if victim is EncounterFighter and victim.redirect_to != null:
		victim = victim.redirect_to
		victim.redirect_to = null
	if victim is EncounterFighter and victim.is_immune_to(_effective_energy()):
		note("%s est immunisé." % _name(victim))
		return
	var amount := _apply_modifiers(victim, base_amount)
	if victim is EncounterFighter:
		amount = ceili(amount * victim.next_damage_factor * victim.energy_damage_factor.get(_effective_energy(), 1.0))
		victim.next_damage_factor = 1.0
		victim.apply_damage(amount)
		if user is EncounterFighter and amount > 0:
			victim.last_damager = user
			if victim.reflect_to_attacker and user != victim:
				user.apply_damage(amount)  # Reflux : renvoie autant à l'attaquant
	note("%d dégâts à %s." % [amount, _name(victim)])

## Modificateurs +36 % par condition (additionnés puis arrondis au supérieur), plus le
## bonus de dégâts infligés du user s'il a médité au tour précédent.
func _apply_modifiers(target, base_amount: int) -> int:
	if not (target is EncounterFighter) or not (user is EncounterFighter):
		return base_amount
	var conditions := 0
	var energy := _effective_energy()
	var pos: GameEnums.TurnPosition = timeline.position_of(target) if timeline else GameEnums.TurnPosition.MIDDLE
	if energy != GameEnums.Energy.NONE and energy == target.active_weakness(pos):
		conditions += 1
	if user.species and target.species and user.species.spiricosm == target.species.spiricosm:
		conditions += 1
	if completed_species.has(target.species_id()):
		conditions += 1
	if user.species_id() == target.species_id():
		conditions += 1
	return ceili(base_amount * (1.0 + MODIFIER_PER_CONDITION * conditions + user.outgoing_damage_bonus))

func _effective_energy() -> GameEnums.Energy:
	if energy_override != GameEnums.Energy.NONE:
		return energy_override
	if ability and ability.energy in [GameEnums.Energy.RANDOM, GameEnums.Energy.VARIABLE]:
		return resolved_energy
	return ability.energy if ability else GameEnums.Energy.NONE

# --- Autres mutations ---

func drain_eth(target, amount: int) -> void:
	if target is EncounterFighter:
		target.drain_eth(amount)
		if user is EncounterFighter:
			target.last_damager = user
	note("%s perd %d ETH." % [_name(target), amount])

func recover_den(target, amount: int) -> void:
	if target is EncounterFighter:
		target.recover_den(amount)
	note("%s récupère %d DEN." % [_name(target), amount])

func recover_eth(target, amount: int) -> void:
	if target is EncounterFighter:
		target.recover_eth(amount)
	note("%s récupère %d ETH." % [_name(target), amount])

## Change la faiblesse active de la cible pour ce tour (au hasard, différente).
func change_weakness(target) -> void:
	if target is EncounterFighter:
		target.override_weakness(_random_energy_other_than(target.active_weakness(
			timeline.position_of(target) if timeline else GameEnums.TurnPosition.MIDDLE)))
	note("la faiblesse de %s change." % _name(target))

## Réduction / augmentation / immunité (0) des prochains dégâts de la cible.
func modify_damage(target, factor: float) -> void:
	if target is EncounterFighter:
		target.next_damage_factor = factor
	note("prochains dégâts de %s ×%.2f." % [_name(target), factor])

func redirect_next_damage(from_target, to_target) -> void:
	if from_target is EncounterFighter and to_target is EncounterFighter:
		from_target.redirect_to = to_target
	note("les prochains dégâts de %s sont redirigés vers %s." % [_name(from_target), _name(to_target)])

# Stubs (systèmes à venir) : actions/dialogue/examen.
func limit_actions(target, amount: int) -> void:
	note("%s perd %d action(s) [à venir]." % [_name(target), amount])

func recover_actions(target, amount: int) -> void:
	note("%s gagne %d action(s) [à venir]." % [_name(target), amount])

func force_talk(target) -> void:
	note("%s est forcé de parler [à venir]." % _name(target))

func grant_examine_bonus(target, amount: int) -> void:
	note("bonus d'examen +%d sur %s [à venir]." % [amount, _name(target)])

func change_turn_order(payload: Dictionary = {}) -> void:
	if timeline and rng:
		timeline.request_shuffle(rng)
	note("l'ordre du tour est bouleversé.")

## Place la cible en queue de l'ordre du prochain tour.
func move_to_last(target) -> void:
	if timeline:
		timeline.request_move_last(target)
	note("%s passera en dernier au prochain tour." % _name(target))

## Place la cible en tête de l'ordre du prochain tour.
func move_to_first(target) -> void:
	if timeline:
		timeline.request_move_first(target)
	note("%s passera en premier au prochain tour." % _name(target))

## Demande de plomberie vers l'UI : ne produit AUCUNE ligne de journal (l'effet qui
## l'appelle a déjà noté ce qui est visible pour le joueur). Journaliser le tag interne
## et son dictionnaire polluait le journal (« ui 'flee' {...} »).
func request_ui(kind: StringName, data: Dictionary = {}) -> void:
	ui_requested.emit(kind, data)

# --- Ciblage ---

## Camp du user (joueurs OU rivaux), vivants — user inclus.
func team() -> Array:
	return all_fighters.filter(func(f): return f.is_player == _user_is_player() and not f.is_dissolved())

## Alliés du user (camp moins lui-même).
func allies() -> Array:
	return team().filter(func(f): return f != user)

## Adversaires vivants.
func opponents() -> Array:
	return all_fighters.filter(func(f): return f.is_player != _user_is_player() and not f.is_dissolved())

## Tous les autres individus (hors user), vivants.
func others() -> Array:
	return all_fighters.filter(func(f): return f != user and not f.is_dissolved())

func random_of(arr: Array):
	return arr[rng.randi_range(0, arr.size() - 1)] if rng and not arr.is_empty() else (arr[0] if not arr.is_empty() else null)

func random_opponent():
	return random_of(opponents())

## Cible principale : la cible désignée par le manager, sinon un adversaire au hasard.
func primary():
	return targets[0] if not targets.is_empty() else random_opponent()

## n cibles tirées parmi les adversaires (avec répétition possible si autorisée).
func random_opponents(n: int, allow_repeat := true) -> Array:
	var pool := opponents()
	var out: Array = []
	for _i in n:
		if pool.is_empty():
			break
		var pick = random_of(pool)
		out.append(pick)
		if not allow_repeat:
			pool.erase(pick)
	return out

## Adversaire en tête / en queue de l'ordre du tour (parmi les vivants).
func first_opponent_in_order():
	for f in _living_order():
		if f.is_player != _user_is_player():
			return f
	return null

func last_opponent_in_order():
	var found = null
	for f in _living_order():
		if f.is_player != _user_is_player():
			found = f
	return found

func _living_order() -> Array:
	return timeline.living() if timeline else all_fighters

func _user_is_player() -> bool:
	return user is EncounterFighter and user.is_player

# --- Niveaux de dégâts (mini / small / normal / big) ---

const DMG := {&"mini": 5, &"small": 7, &"normal": 10, &"big": 14}

func dmg(tier: StringName) -> int:
	return DMG.get(tier, 10)

## Dégâts principaux de la capacité : valeur Notion si fournie, sinon « normal ».
func base_damage() -> int:
	return ability.base_damage if ability and ability.base_damage > 0 else dmg(&"normal")

# --- Faiblesse (set / remove / reset) ---

func set_weakness(target, energy: GameEnums.Energy) -> void:
	if target is EncounterFighter:
		target.override_weakness(energy)
	note("faiblesse de %s : %s." % [_name(target), _energy_name(energy)])

func remove_weakness(target) -> void:
	set_weakness(target, GameEnums.Energy.NONE)

func reset_weakness(target) -> void:
	if target is EncounterFighter:
		target.reset_weakness()
	note("faiblesse de %s rétablie." % _name(target))

## Échange les faiblesses actives de deux combattants (Dark Gambit / Caroussel).
func swap_weakness(a, b) -> void:
	if a is EncounterFighter and b is EncounterFighter:
		var wa := weakness_of(a)
		var wb := weakness_of(b)
		a.override_weakness(wb)
		b.override_weakness(wa)
	note("%s et %s échangent leur faiblesse." % [_name(a), _name(b)])

func lock_weakness(target) -> void:
	if target is EncounterFighter:
		target.weakness_locked = true

func hide_weakness(target) -> void:
	if target is EncounterFighter:
		target.weakness_hidden = true
	note("la faiblesse de %s est masquée." % _name(target))

# --- Immunités / verrous ---

func grant_immunity(target, energies: Array) -> void:
	if target is EncounterFighter:
		target.immune_energies.append_array(energies)
	note("%s devient immunisé (%s)." % [_name(target),
		", ".join(energies.map(func(e): return _energy_name(e)))])

## Immunité à TOUT sauf l'énergie donnée (ex. immune to all non-arcane).
func grant_immunity_except(target, energy: GameEnums.Energy) -> void:
	if target is EncounterFighter:
		target.immune_all_except = energy
	note("%s devient immunisé sauf à %s." % [_name(target), _energy_name(energy)])

## Multiplie les dégâts d'une énergie donnée reçus par la cible ce tour (0.5 = moitié).
func set_energy_damage_factor(target, energy: GameEnums.Energy, factor: float) -> void:
	if target is EncounterFighter:
		target.energy_damage_factor[energy] = target.energy_damage_factor.get(energy, 1.0) * factor
	note("dégâts %s reçus par %s ×%.2f." % [_energy_name(energy), _name(target), factor])

## Position du combattant en queue de l'ordre du tour parmi le camp du user (vivants).
func last_of_team_in_order():
	var found = null
	for f in _living_order():
		if f.is_player == _user_is_player():
			found = f
	return found

func lock_den(target) -> void:
	if target is EncounterFighter:
		target.den_locked = true

func lock_eth(target) -> void:
	if target is EncounterFighter:
		target.eth_locked = true

func grant_reflect(target) -> void:
	if target is EncounterFighter:
		target.reflect_to_attacker = true
	note("%s renverra les dégâts subis." % _name(target))

func grant_full_immunity(target) -> void:
	if target is EncounterFighter:
		target.fully_immune = true
	note("%s devient totalement immunisé." % _name(target))

## Restreint les actions disponibles de la cible (système d'actions à venir → journalisé).
func restrict_to(target, allowed: Array) -> void:
	note("%s ne peut plus faire que : %s [à venir]." % [_name(target), ", ".join(allowed)])

## Fait fuir un combattant de la rencontre (mécanique de fuite à venir → journalisée).
func flee(target) -> void:
	note("%s prend la fuite [à venir]." % _name(target))
	request_ui(&"flee", {"fighter": target.species_id() if target is EncounterFighter else target})

# --- Comptages / requêtes ---

## Nombre d'individus (vivants) dont le Spiricosme d'origine est donné.
func count_natives(spiricosm: GameEnums.Spiricosm) -> int:
	return all_fighters.filter(func(f): return not f.is_dissolved() and f.species and f.species.spiricosm == spiricosm).size()

## Plus grand groupe d'individus partageant la même faiblesse active.
func largest_same_weakness_group() -> int:
	var counts := {}
	var best := 0
	for f in all_fighters:
		if f.is_dissolved():
			continue
		var w = f.active_weakness(timeline.position_of(f) if timeline else GameEnums.TurnPosition.MIDDLE)
		if w == GameEnums.Energy.NONE:
			continue
		counts[w] = counts.get(w, 0) + 1
		best = maxi(best, counts[w])
	return best

func weakness_of(fighter) -> GameEnums.Energy:
	if fighter is EncounterFighter:
		return fighter.active_weakness(timeline.position_of(fighter) if timeline else GameEnums.TurnPosition.MIDDLE)
	return GameEnums.Energy.NONE

## Force l'énergie effective de la capacité (ex. « énergie = faiblesse du user »).
## Affecte les modificateurs de dégâts et les immunités.
func set_energy(energy: GameEnums.Energy) -> void:
	energy_override = energy

## Énergie effective de la capacité ce tour (résout Random/Variable et l'override).
func energy() -> GameEnums.Energy:
	return _effective_energy()

# --- Helpers ---

func _random_energy_other_than(current: GameEnums.Energy) -> GameEnums.Energy:
	var pool := [GameEnums.Energy.HEAT, GameEnums.Energy.FLUID, GameEnums.Energy.CRYSTAL,
		GameEnums.Energy.ARCANE, GameEnums.Energy.TOXIC]
	pool.erase(current)
	return pool[rng.randi_range(0, pool.size() - 1)] if rng else pool[0]

func _name(target) -> String:
	if target is EncounterFighter:
		return target.display_name()
	return str(target)

## Nom lisible d'une énergie (l'enum s'imprimerait sinon comme un entier brut).
const _ENERGY_NAMES := {
	GameEnums.Energy.HEAT: "chaleur",
	GameEnums.Energy.FLUID: "fluide",
	GameEnums.Energy.CRYSTAL: "cristal",
	GameEnums.Energy.ARCANE: "arcane",
	GameEnums.Energy.TOXIC: "toxique",
	GameEnums.Energy.RANDOM: "aléatoire",
	GameEnums.Energy.VARIABLE: "variable",
	GameEnums.Energy.NONE: "aucune",
}

func _energy_name(e: GameEnums.Energy) -> String:
	return _ENERGY_NAMES.get(e, "?")
