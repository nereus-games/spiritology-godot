## Resolves a talent to its script — what [EffectCatalog] is for abilities.
##
## Each talent's logic lives in `talents/impl/<id>.gd`, extending [TalentScript]. Without
## one, a no-op [TalentScript] stands in: the talent exists in the data but does nothing.
##
## No `class_name` — see talent_script.gd. The base is preloaded here so that
## `made is TalentScript` can be checked at all.
extends RefCounted

const TalentScript := preload("res://scripts/encounter/talents/talent_script.gd")
const IMPL_DIR := "res://scripts/encounter/talents/impl/"


## Builds a talent's script with its fields set. A null `talent` — an individual carrying
## none — yields a harmless no-op.
static func script_for(talent: TalentData, owner: EncounterIndividual, stacks: int) -> RefCounted:
	var inst: RefCounted = TalentScript.new()
	if talent != null:
		var path := IMPL_DIR + String(talent.id) + ".gd"
		if ResourceLoader.exists(path):
			var script: GDScript = load(path)
			var made = script.new()
			if made is TalentScript:
				inst = made
			else:
				push_warning("[TalentCatalog] %s does not extend TalentScript." % path)
	inst.talent = talent
	inst.owner = owner
	inst.stacks = maxi(stacks, 1)
	return inst
