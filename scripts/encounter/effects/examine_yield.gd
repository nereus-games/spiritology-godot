## What an ability does to the info an Examine yields: the bonus Halo Effect gives the Examine it
## makes, the bonus Priming and Catatonia leave on later ones.
##
## The rules, which the doc does not give and which are ours:
##   - a bonus is counted in POINTS, and a point is worth `examine_bonus_step` (10 %) of the
##     Examine's IFP; points add up, so 4 points are +40 %, not 1.1 to the fourth;
##   - that factor MULTIPLIES the talents' (Reconnaissance Glide's +10 %), and the product is what
##     [signal EncounterManager.ifp_earned] carries as `yield_factor`;
##   - the amount is rounded by [method GameSession.scale_amount]: a bonus rounds UP;
##   - only a player character's Examine of a rival earns IFP, as for a plain Examine: an
##     ability that "Examines" an ally or is used by a rival changes nothing but the log.
##
## Static functions, used as `const ExamineYield := preload(...)` — no `class_name`, see CLAUDE.md.
extends RefCounted


## The factor `points` of info bonus put on an Examine's IFP.
static func factor_for(points: int) -> float:
	return 1.0 + points * BalanceData.current().examine_bonus_step


## The user Examines `target` as part of the ability, with `points` of info bonus on top of any it
## already has. Carried out by the manager when the effect is over.
static func examine(ctx: EncounterContext, target, points: int) -> void:
	ctx.examines.append([target, points])
	if points > 0:
		ctx.note(_tr("LOG_EXAMINE_BOOST") % [points, _name(target)])
	else:
		ctx.note(_tr("LOG_EXAMINE_MADE") % _name(target))


## `target`'s Examines get `points` of info bonus until `anchor`'s next turn, or for `turns` of it.
static func boost(
	ctx: EncounterContext,
	target,
	points: int,
	turns := EncounterIndividual.UNTIL_NEXT_TURN,
	anchor = null
) -> void:
	if target is EncounterIndividual:
		target.grant_examine_bonus_points(points, anchor if anchor != null else ctx.user, turns)
	ctx.note(_tr("LOG_EXAMINE_BOOST") % [points, _name(target)])


static func _name(target) -> String:
	return target.display_name() if target is EncounterIndividual else str(target)


static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))
