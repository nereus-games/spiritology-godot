## Restore (akturlin) — "After an encounter, player characters regain X % DEN and Y % ETH.
## Refresh crystals restore 100 % ETH."
##
## At the end of an encounter, gives a percentage of DEN and ETH back to the bearer's team. The
## manager mutates the player [EncounterIndividual]s directly, and the encounter UI then syncs those
## values back into the persistent [GameSession] state, as it does for damage taken. Stacking in a
## duo (two akturlin) falls out naturally: one [TalentScript] per bearer, so the hook runs once
## per copy.
##
## The "refresh crystals restore 100% ETH" half belongs to EXPLORATION — refresh crystals are a
## dungeon mechanism — and so is outside the encounter, and not handled here.
extends "res://scripts/encounter/talents/talent_script.gd"

## PLACEHOLDERS: the design doc writes "X % DEN / Y % ETH" without giving numbers (same status as
## the ETH tiers or [member BalanceData.object_heal_den]). To be settled by playing.
const DEN_FRACTION := 0.2
const ETH_FRACTION := 0.35


func on_encounter_end(manager, result: StringName) -> void:
	# No resurrection: on a defeat the duo is dissolved, and "after the encounter" means nothing.
	# Give anything back only if the team survived.
	if result == &"defeat":
		return
	for f in manager.allies_of(owner):
		if f.is_dissolved():
			continue
		f.recover_den(roundi(f.max_den * DEN_FRACTION))
		f.recover_eth(roundi(f.max_eth * ETH_FRACTION))
	manager.note_talent(_tr("LOG_TALENT_RESTORE") % _label())


func _label() -> String:
	return String(TranslationServer.translate(talent.name_key())) if talent else "Restore"
