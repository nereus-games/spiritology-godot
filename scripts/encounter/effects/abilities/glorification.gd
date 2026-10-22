## Glorification — malcouli · [change weakness, recover ETH]
## MECHANIC: the user takes on the target's weakness (approximated across the 3) and gains ETH:
## a little from a teammate, more from a rival of the same origin, more still from a rival of a
## different one. It loses that ETH if the target then hurts it.
##
## "Then" is until the user's next turn, the window of every reaction, and the ETH is lost once:
## it is "that ETH", which the user no longer has to give back a second time. The target is the one
## the history says the user's last Glorification was aimed at; with none designated, which a game
## never does, nothing is armed.
extends AbilityScript


func execute(ctx: EncounterContext) -> void:
	var t = ctx.primary()
	if t == null:
		return
	ctx.set_weakness(ctx.user, ctx.weakness_of(t))
	ctx.recover_eth(ctx.user, _gain(ctx, t))
	ctx.watch_reactions()


func react(ctx: EncounterContext, event) -> void:
	if not event.hurt(ctx.user) or event.actor == null:
		return
	var last = ctx.history.last_use(ctx.user, ctx.ability.id)
	if last == null or not last.targets.has(event.actor):
		return
	ctx.drain_eth(ctx.user, _gain(ctx, event.actor))
	ctx.user.unwatch(ctx.ability)


## What taking on `target`'s weakness is worth to the user.
func _gain(ctx: EncounterContext, target) -> int:
	if target.is_player == ctx.user.is_player:
		return ctx.dmg(&"small")
	if (
		target.species
		and ctx.user.species
		and target.species.spiricosm == ctx.user.species.spiricosm
	):
		return ctx.dmg(&"normal")
	return ctx.dmg(&"big")
