## One individual of a rival group on the map: its variety, and its DEN and ETH.
##
## A silhouette in exploration stands for a GROUP, whose members appear together in the
## encounter and need not be alike — each has its own variety, its own maximum DEN and ETH.
## Their current values are what the map and the encounters hand back and forth: damage taken
## from a fall is still there in the encounter, and damage taken in an encounter is still there
## on the map afterwards.
##
## No `class_name` (the CLI class-cache trap): preloaded.
extends RefCounted

var species_id: StringName
var max_den: int
var den: int
var max_eth: int
var eth: int
## The share taken off its Talk chance, 0 to 1: set when the duo flees its group above the first
## PSY rung. It rides into every later encounter in [method encounter_state], but only counts
## while PSY is above that rung when a Talk happens.
var talk_malus := 0.0


func _init(p_species_id: StringName = &"", p_max_den: int = 0, p_max_eth: int = 0) -> void:
	species_id = p_species_id
	max_den = p_max_den
	den = p_max_den
	max_eth = p_max_eth
	eth = p_max_eth


func is_dissolved() -> bool:
	return den <= 0


## The state an encounter starts this individual from — the `rival_states` entry
## [method TransitionManager.open_encounter] takes.
func encounter_state() -> Dictionary:
	var state := {"den": den, "max_den": max_den, "eth": eth, "max_eth": max_eth}
	if talk_malus > 0.0:
		state["talk_malus"] = talk_malus
	return state


## Takes back the DEN and ETH an encounter left this individual with — one entry of
## [method EncounterManager.rival_report].
func take_encounter_state(entry: Dictionary) -> void:
	den = clampi(int(entry.get("den", den)), 0, max_den)
	eth = clampi(int(entry.get("eth", eth)), 0, max_eth)
