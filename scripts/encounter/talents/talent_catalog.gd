## Résout le script d'effet d'un talent — analogue à [EffectCatalog] pour les capacités.
##
## Chaque talent (généré depuis Notion, ligne Type=Talent) a sa logique dans un script
## dédié `talents/impl/<id>.gd` étendant [TalentScript]. Tant qu'il n'existe pas, on
## retombe sur un [TalentScript] no-op (talent présent dans les données mais non scripté).
##
## PAS de `class_name` (cf. talent_script.gd) : obtenu par `preload` chez l'appelant
## (le manager). La base est chargée ici par preload pour pouvoir tester `made is TalentScript`.
extends RefCounted

const TalentScript := preload("res://scripts/encounter/talents/talent_script.gd")
const IMPL_DIR := "res://scripts/encounter/talents/impl/"


## Instancie le script dédié d'un talent, champs `talent`/`owner`/`stacks` posés.
## `talent` peut être null (combattant sans talent) : renvoie alors un no-op neutre.
static func script_for(talent: TalentData, owner: EncounterFighter, stacks: int) -> RefCounted:
	var inst: RefCounted = TalentScript.new()
	if talent != null:
		var path := IMPL_DIR + String(talent.id) + ".gd"
		if ResourceLoader.exists(path):
			var script: GDScript = load(path)
			var made = script.new()
			if made is TalentScript:
				inst = made
			else:
				push_warning("[TalentCatalog] %s n'étend pas TalentScript." % path)
	inst.talent = talent
	inst.owner = owner
	inst.stacks = maxi(stacks, 1)
	return inst
