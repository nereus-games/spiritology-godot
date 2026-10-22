## What four abilities ask of the encounter, kept apart from [EncounterContext]: Shuffle trades ETH
## by position, Deflection doubles the damage that matches a weakness, Tactical Retreat turns
## damage into ETH, and Self-Denial drains at the start of every turn.
##
## Static functions taking the ability's own context. They live here because the context is at the
## limit of public methods the linter allows, and because nothing else uses them. The rules they
## set up are applied elsewhere: Deflection and Tactical Retreat in
## [method EncounterContext.deal_damage], the recurring drain in [EncounterManager].
extends RefCounted


## Shuffle: throws the turn order into disarray, and every living individual ends up with the ETH
## of whoever stood where it will stand. The trade is made at once, with the ETH everyone has
## now, while the new order only takes hold at the end of the round.
static func shuffle_trading_eth(ctx: EncounterContext) -> void:
	if ctx.timeline == null or ctx.rng == null:
		ctx.change_turn_order()
		return
	var before: Array = ctx.timeline.living()
	var ahead: Array = ctx.timeline.request_shuffle(ctx.rng)
	var after: Array = []
	for f in ahead:
		if not f.is_dissolved():
			after.append(f)
	var eth_of_place: Array = []
	for f in before:
		eth_of_place.append(f.eth)
	for i in mini(after.size(), eth_of_place.size()):
		# A lock against losing ETH holds against a trade as well.
		after[i].eth = (
			maxi(eth_of_place[i], after[i].eth) if after[i].eth_locked else eth_of_place[i]
		)
	ctx.note(_tr("LOG_TURN_ORDER_SHUFFLED"))
	ctx.note(_tr("LOG_ETH_TRADED"))


## Deflection: until the user's next turn, the damage that matches an individual's exposed
## weakness is multiplied for every individual standing.
static func amplify_weakness_damage(ctx: EncounterContext, factor: float) -> void:
	for f in ctx.all_individuals:
		f.amplify_weakness_damage(factor, ctx.user)
	ctx.note(_tr("LOG_WEAKNESS_DAMAGE_AMPLIFIED") % factor)


## Tactical Retreat: until the user's next turn, the target gets ETH instead of taking the damage
## of these energies.
static func convert_damage_to_eth(ctx: EncounterContext, target, energies: Array) -> void:
	if not (target is EncounterIndividual):
		return
	var names: Array = []
	for e in energies:
		target.convert_damage_to_eth(e, ctx.user)
		names.append(ctx._energy_name(e))
	ctx.note(_tr("LOG_DAMAGE_TO_ETH_ARMED") % [target.display_name(), ", ".join(names)])


## Self-Denial: from now on, [method AbilityScript.recur] runs at the start of each of the
## target's turns, until [method AbilityScript.on_meditated] ends it.
static func recur_each_turn(ctx: EncounterContext, target) -> void:
	if target is EncounterIndividual and ctx.ability != null:
		target.add_recurring(ctx.ability, ctx.user)


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
