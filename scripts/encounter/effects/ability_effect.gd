## Base class of one scriptable effect brick.
##
## Each effect tag in the design doc — "damage", "change weakness", "recover ETH" — has a
## subclass here. [EffectCatalog] turns an ability's `tags` into a list of these, in a
## fixed order, as the FALLBACK for abilities whose own mechanic is not written yet.
##
## Effects never mutate anything directly: everything goes through [EncounterContext],
## which is where the damage rules and the logging live.
class_name AbilityEffect
extends RefCounted


## The tag this brick answers to.
func tag() -> StringName:
	return &""


## Override this.
func execute(_ctx: EncounterContext) -> void:
	pass
