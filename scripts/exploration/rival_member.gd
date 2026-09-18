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
	return {"den": den, "max_den": max_den, "eth": eth, "max_eth": max_eth}


## Takes back the DEN and ETH an encounter left this individual with — one entry of
## [method EncounterManager.rival_report].
func take_encounter_state(entry: Dictionary) -> void:
	den = clampi(int(entry.get("den", den)), 0, max_den)
	eth = clampi(int(entry.get("eth", eth)), 0, max_eth)
