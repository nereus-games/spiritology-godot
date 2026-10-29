## Altruism — érdouss · Fluid · mini · [recover DEN]
## MECHANIC: destroys an object from the inventory, picked by the user, then the target gains
## X DEN. A player character pays from the session's inventory, through the narrow handle the
## encounter is given ([member EncounterManager.inventory_view]); a rival, with one it carries.
## With nothing to destroy the ability is not usable, and does nothing if forced.
extends AbilityScript


func is_usable(ctx: EncounterContext) -> bool:
	return ctx.object_to_destroy() != &""


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		t = ctx.user
	var spent := ctx.destroy_object()
	if spent == &"":
		ctx.note(TranslationServer.translate("LOG_ALTRUISM_NO_OBJECT"))
		return
	ctx.note(TranslationServer.translate("LOG_ALTRUISM_DESTROYS") % ctx.object_name(spent))
	ctx.recover_den(t, ctx.dmg(&"normal"))
